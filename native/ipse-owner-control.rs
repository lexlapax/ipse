//! Inert, one-use Linux owner-control handoff. This mode cannot write a tty.
//! Once transferred, the Port's stdin is never read again: any readable state,
//! EOF, error or helper loss is sticky loss for the recipient.
use crate::ipse_lease_sink as sink;
use crate::ipse_lease_transfer as transfer;
use std::fs::File;
use std::io::{self, Write};
use std::os::fd::{AsRawFd, FromRawFd};
use std::os::linux::net::SocketAddrExt;
use std::os::unix::fs::{FileTypeExt, MetadataExt};
use std::os::unix::net::{SocketAddr, UnixListener};
use std::time::{Duration, Instant};

#[repr(C)]
struct Poll {
    fd: i32,
    events: i16,
    revents: i16,
}
unsafe extern "C" {
    fn poll(fds: *mut Poll, count: usize, timeout: i32) -> i32;
    fn fcntl(fd: i32, command: i32, ...) -> i32;
    fn geteuid() -> u32;
}
const INPUT: i16 = 1;
const OUTPUT: i16 = 4;
const REQUEST: usize = 69;
const OBSERVE: usize = 93;

fn refused() -> String {
    "owner-control unavailable".into()
}
fn valid_operation(operation: &[u8], role: u8) -> bool {
    operation.len() == 16 && operation.iter().any(|b| *b != 0) && matches!(role, 1 | 2)
}
fn pipe_read_end(file: &File, expected: Option<(u64, u64)>) -> bool {
    let Ok(meta) = file.metadata() else {
        return false;
    };
    let flags = unsafe { fcntl(file.as_raw_fd(), 3) };
    meta.file_type().is_fifo()
        && flags >= 0
        && flags & 3 == 0
        && expected.map_or(true, |(dev, ino)| meta.dev() == dev && meta.ino() == ino)
}
fn initial(input: &mut File, length: usize, deadline: Instant, allow_cancel: bool) -> Result<Vec<u8>, String> {
    let mut header = [0u8; 5];
    sink::read_exact(input, &mut header, None, None, deadline).map_err(|_| refused())?;
    let size = u32::from_be_bytes(header[1..].try_into().unwrap()) as usize;
    if allow_cancel && header[0] == b'C' && size == 0 && transfer::control_quiet(0) {
        return Ok(Vec::new());
    }
    if header[0] != b'I' || size != length {
        return Err(refused());
    }
    let mut body = vec![0; length];
    sink::read_exact(input, &mut body, None, None, deadline).map_err(|_| refused())?;
    if !transfer::control_quiet(0) {
        return Err(refused());
    }
    Ok(body)
}

fn expected_sender(
    entry: &[u8],
    control: i32,
    watched: &[i32],
    deadline: Instant,
) -> Result<sink::Expected, String> {
    let pid = u32::from_be_bytes(entry[..4].try_into().unwrap());
    let process = sink::pidfd(pid).map_err(|_| refused())?;
    loop {
        if let Ok(expected) = sink::expected(entry) {
            return Ok(expected);
        }
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return Err(refused());
        }
        let mut fds = vec![
            Poll {
                fd: control,
                events: INPUT,
                revents: 0,
            },
            Poll {
                fd: process.as_raw_fd(),
                events: INPUT,
                revents: 0,
            },
        ];
        fds.extend(watched.iter().map(|fd| Poll {
            fd: *fd,
            events: INPUT,
            revents: 0,
        }));
        let result = unsafe {
            poll(
                fds.as_mut_ptr(),
                fds.len(),
                left.as_millis().max(1).min(5) as i32,
            )
        };
        if result < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
            continue;
        }
        if result < 0 || fds.iter().any(|p| p.revents != 0) {
            return Err(refused());
        }
    }
}

/// Collect one operation- and role-bound EOF-only owner descriptor. This
/// primitive retains the authenticated peer and sender pidfd for its caller;
/// receiving the FD is not activation or proof of future process lifetime.
pub(crate) fn collect(
    entry: &[u8],
    operation: &[u8; 16],
    role: u8,
    control: i32,
    watched: &[i32],
    deadline: Instant,
) -> Result<(File, sink::Expected, std::os::unix::net::UnixStream), String> {
    if entry.len() != sink::ENTRY_SIZE || !valid_operation(operation, role) {
        return Err(refused());
    }
    let expected = expected_sender(entry, control, watched, deadline)?;
    let mut stream =
        sink::open_peer_watch(&expected, control, watched, deadline).map_err(|_| refused())?;
    let mut binding = [0u8; 17];
    binding[..16].copy_from_slice(operation);
    binding[16] = role;
    let mut at = 0;
    while at < binding.len() {
        let mut guards = watched.to_vec();
        guards.push(expected.process.as_raw_fd());
        sink::ready_watch(stream.as_raw_fd(), OUTPUT, control, &guards, deadline)
            .map_err(|_| refused())?;
        match stream.write(&binding[at..]) {
            Ok(0) => return Err(refused()),
            Ok(n) => at += n,
            Err(e)
                if matches!(
                    e.kind(),
                    io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock
                ) =>
            {
                ()
            }
            Err(_) => return Err(refused()),
        }
    }
    let owner = sink::receive_raw_watch(&stream, &expected, control, watched, deadline)
        .map_err(|_| refused())?;
    if !pipe_read_end(&owner, Some((expected.dev, expected.ino)))
        || !transfer::control_quiet(owner.as_raw_fd())
    {
        return Err(refused());
    }
    let mut guards = watched.to_vec();
    guards.push(expected.process.as_raw_fd());
    sink::ready_watch(stream.as_raw_fd(), OUTPUT, control, &guards, deadline)
        .map_err(|_| refused())?;
    if stream.write(b"A").map_err(|_| refused())? != 1 {
        return Err(refused());
    }
    Ok((owner, expected, stream))
}

/// The Port owner sends one bounded request, then never writes another byte.
/// The helper retains its duplicate read end but does not consume it after the
/// handoff. A successful T frame means transfer only, not owner liveness.
pub(crate) fn send(args: &[String]) -> Result<(), String> {
    let review = args.get(1).is_some_and(|mode| matches!(mode.as_str(), "--owner-control-send-review-v3" | "--owner-control-send-review-notice-v4"));
    let lifetime = if review {
        if args.len() != 3 { return Err(refused()); }
        args[2].parse::<u64>().ok().filter(|n| (5_000..=120_000).contains(n)).ok_or_else(refused)?
    } else {
        if args.len() != 2 { return Err(refused()); }
        5_000
    };
    let notice_mode = matches!(args[1].as_str(), "--owner-control-send-v2" | "--owner-control-send-review-notice-v4");
    sink::nonblocking(0).map_err(|_| refused())?;
    sink::nonblocking(1).map_err(|_| refused())?;
    let mut input = unsafe { File::from_raw_fd(0) };
    let mut output = std::mem::ManuallyDrop::new(unsafe { File::from_raw_fd(1) });
    if !pipe_read_end(&input, None) {
        return Err(refused());
    }
    let started = Instant::now();
    let deadline = started + Duration::from_secs(5);
    let overall_deadline = started + Duration::from_millis(lifetime);
    let greeting = if notice_mode { &b"owner-control-v2"[..] } else { &b"owner-control-v1"[..] };
    sink::write_frame(&mut output, b'R', greeting, deadline).map_err(|_| refused())?;
    let request = initial(&mut input, REQUEST, deadline, true)?;
    if request.is_empty() {
        sink::write_frame(&mut output, b'C', b"cancelled", deadline).map_err(|_| refused())?;
        return Ok(());
    }
    let operation = &request[..16];
    let role = request[16];
    let pid = u32::from_be_bytes(request[17..21].try_into().unwrap());
    let name = &request[21..37];
    let secret = &request[37..69];
    if !valid_operation(operation, role)
        || pid == 0
        || name.iter().all(|v| *v == 0)
        || secret.iter().all(|v| *v == 0)
    {
        return Err(refused());
    }
    let peer_process = transfer::recipient_process(pid).map_err(|_| refused())?;
    if !transfer::recipient_current(pid, &peer_process) {
        return Err(refused());
    }
    let mut abstract_name = b"ipse-lease-v1-".to_vec();
    abstract_name.extend_from_slice(name);
    let address = SocketAddr::from_abstract_name(abstract_name).map_err(|_| refused())?;
    let listener = UnixListener::bind_addr(&address).map_err(|_| refused())?;
    listener.set_nonblocking(true).map_err(|_| refused())?;
    sink::write_frame(&mut output, b'H', &request[..17], deadline).map_err(|_| refused())?;
    transfer::wait(listener.as_raw_fd(), 0, deadline).map_err(|_| refused())?;
    let (mut stream, _) = listener.accept().map_err(|_| refused())?;
    stream.set_nonblocking(true).map_err(|_| refused())?;
    if !transfer::peer(&stream, pid, unsafe { geteuid() })
        || !transfer::recipient_current(pid, &peer_process)
    {
        return Err(refused());
    }
    let mut challenge = [0u8; 49];
    transfer::exact(&mut stream, 0, &mut challenge, deadline).map_err(|_| refused())?;
    let mismatch = challenge[..32]
        .iter()
        .zip(secret)
        .fold(0u8, |a, (x, y)| a | (x ^ y));
    if mismatch != 0
        || challenge[32..48] != *operation
        || challenge[48] != role
        || !transfer::control_quiet(0)
        || !transfer::recipient_current(pid, &peer_process)
    {
        return Err(refused());
    }
    // After sendmsg, failure means transfer may have occurred. No retry occurs.
    if !transfer::send_fd(&stream, &input) {
        return Err("owner-control transfer unconfirmed".into());
    }
    let mut ack = [0u8; 1];
    if transfer::exact(&mut stream, 0, &mut ack, deadline).is_err()
        || ack != [b'A']
        || !transfer::control_quiet(0)
        || !transfer::recipient_current(pid, &peer_process)
    {
        return Err("owner-control transfer unconfirmed".into());
    }
    sink::write_frame(&mut output, b'T', &request[..17], deadline)
        .map_err(|_| "owner-control transfer unconfirmed".to_string())?;
    let deadline = overall_deadline;
    // V2 permits one bound peer notice; it is not evidence of display or consent.
    let mut noticed = false;
    let mut finished = false;
    loop {
        let mut fds = [
            Poll {
                fd: 0,
                events: INPUT,
                revents: 0,
            },
            Poll {
                fd: peer_process.as_raw_fd(),
                events: INPUT,
                revents: 0,
            },
            Poll {
                fd: stream.as_raw_fd(),
                events: INPUT,
                revents: 0,
            },
        ];
        let timeout = if notice_mode || review {
            let left = deadline.saturating_duration_since(Instant::now());
            if left.is_zero() { return Err(refused()); }
            left.as_millis().max(1).min(i32::MAX as u128) as i32
        } else {
            -1
        };
        let result = unsafe { poll(fds.as_mut_ptr(), fds.len(), timeout) };
        if result < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
            continue;
        }
        if (notice_mode || review) && Instant::now() >= deadline {
            return Err(refused());
        }
        if result < 0 || fds[0].revents != 0 {
            break;
        }
        if fds[2].revents != 0 {
            if !notice_mode {
                break;
            }
            if finished && fds[2].revents & (16 | INPUT) != 0 {
                let mut byte = [0u8; 1];
                match std::io::Read::read(&mut stream, &mut byte) {
                    Ok(0) => break,
                    _ => return Err(refused()),
                }
            }
            if fds[2].revents != INPUT { return Err(refused()); }
            let mut notice = [0u8; 17];
            if transfer::exact(&mut stream, 0, &mut notice, deadline).is_err()
                || notice[1..] != *operation
                || !transfer::recipient_current(pid, &peer_process)
                || !transfer::control_quiet(0)
            {
                return Err(refused());
            }
            match (notice[0], noticed, finished) {
                (b'N', false, false) => {
                    let mut expiry = [0u8; 8];
                    if transfer::exact(&mut stream, 0, &mut expiry, deadline).is_err()
                        || !(1..=9_007_199_254_740_991).contains(&u64::from_be_bytes(expiry))
                        || !transfer::recipient_current(pid, &peer_process)
                        || !transfer::control_quiet(0)
                        || !transfer::control_quiet(stream.as_raw_fd())
                    { return Err(refused()); }
                    let mut body = request[..17].to_vec();
                    body.extend_from_slice(&expiry);
                    sink::write_frame(&mut output, b'N', &body, deadline).map_err(|_| refused())?;
                    noticed = true;
                }
                (b'F', true, false) => {
                    if !transfer::control_quiet(stream.as_raw_fd()) { return Err(refused()); }
                    sink::write_frame(&mut output, b'F', &request[..17], deadline).map_err(|_| refused())?;
                    transfer::send_exact(&mut stream, 0, b"A", deadline).map_err(|_| refused())?;
                    finished = true;
                }
                _ => return Err(refused()),
            }
        }
        if fds[1].revents != 0 {
            if notice_mode { return Err(refused()); }
            break;
        }
    }
    Ok(())
}

/// Inert receiver for native ownership controls. Its only output is status; it
/// retains the received read end and sender pidfd, and cannot display content.
pub(crate) fn observe(args: &[String]) -> Result<(), String> {
    if args.len() != 2 {
        return Err(refused());
    }
    let notice_mode = args[1] == "--owner-control-observe-v2";
    sink::nonblocking(0).map_err(|_| refused())?;
    sink::nonblocking(1).map_err(|_| refused())?;
    let mut input = unsafe { File::from_raw_fd(0) };
    let mut output = std::mem::ManuallyDrop::new(unsafe { File::from_raw_fd(1) });
    let deadline = Instant::now() + Duration::from_secs(5);
    sink::write_frame(&mut output, b'H', b"owner-observer-v1", deadline).map_err(|_| refused())?;
    let request = initial(&mut input, OBSERVE, deadline, false)?;
    let operation = &request[..16];
    let role = request[16];
    let lifetime = u64::from_be_bytes(request[85..93].try_into().unwrap());
    if !valid_operation(operation, role) || !(1..=120_000).contains(&lifetime) {
        return Err(refused());
    }
    let expected = expected_sender(&request[17..85], 0, &[], deadline)?;
    let mut stream = sink::open_peer(&expected, None, deadline).map_err(|_| refused())?;
    let mut binding = [0u8; 17];
    binding[..16].copy_from_slice(operation);
    binding[16] = role;
    let mut sent = 0;
    while sent < binding.len() {
        sink::ready_owner(
            stream.as_raw_fd(),
            OUTPUT,
            Some(0),
            Some(expected.process.as_raw_fd()),
            None,
            deadline,
        )
        .map_err(|_| refused())?;
        match stream.write(&binding[sent..]) {
            Ok(0) => return Err(refused()),
            Ok(n) => sent += n,
            Err(e)
                if matches!(
                    e.kind(),
                    io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock
                ) =>
            {
                ()
            }
            Err(_) => return Err(refused()),
        }
    }
    let owner = sink::receive_raw(&stream, &expected, None, deadline).map_err(|_| refused())?;
    if !pipe_read_end(&owner, Some((expected.dev, expected.ino)))
        || !transfer::control_quiet(owner.as_raw_fd())
    {
        return Err(refused());
    }
    transfer::send_exact(&mut stream, 0, b"A", deadline).map_err(|_| refused())?;
    sink::write_frame(&mut output, b'L', &binding, deadline).map_err(|_| refused())?;
    let until = Instant::now() + Duration::from_millis(lifetime);
    let mut noticed = false;
    loop {
        let left = until.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return Err(refused());
        }
        let mut fds = [
            Poll {
                fd: 0,
                events: INPUT,
                revents: 0,
            },
            Poll {
                fd: owner.as_raw_fd(),
                events: INPUT,
                revents: 0,
            },
            Poll {
                fd: expected.process.as_raw_fd(),
                events: INPUT,
                revents: 0,
            },
            Poll {
                fd: stream.as_raw_fd(),
                events: INPUT,
                revents: 0,
            },
        ];
        let result = unsafe {
            poll(
                fds.as_mut_ptr(),
                fds.len(),
                left.as_millis().max(1).min(i32::MAX as u128) as i32,
            )
        };
        if result < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
            continue;
        }
        if result < 0 {
            return Err(refused());
        }
        if fds[0].revents != 0 {
            if !notice_mode || noticed || fds[0].revents != INPUT {
                return Err(refused());
            }
            let mut command = [0u8; 25];
            sink::read_exact(&mut input, &mut command, None, Some(expected.process.as_raw_fd()), until)
                .map_err(|_| refused())?;
            if command[0] != b'N' || command[1..17] != *operation
                || !(1..=9_007_199_254_740_991).contains(&u64::from_be_bytes(command[17..25].try_into().unwrap()))
                || !transfer::control_quiet(owner.as_raw_fd())
                || !transfer::control_quiet(stream.as_raw_fd())
                || !transfer::control_quiet(0)
            {
                return Err(refused());
            }
            transfer::send_exact(&mut stream, 0, &command, until).map_err(|_| refused())?;
            noticed = true;
        }
        if fds[1..].iter().any(|p| p.revents != 0) {
            sink::write_frame(&mut output, b'D', &binding, until).map_err(|_| refused())?;
            return Ok(());
        }
    }
}
