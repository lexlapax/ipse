//! Experimental, private pipe writer. No Session or worker caller is wired.
//! Descriptor 0 is the host control, 1 its receipt, 3 the pre-bound nonblocking
//! pipe destination, and 4 a separate owner-liveness pipe. A caller must prove
//! the ownership and operation bindings before this mode can be integrated.
use super::ipse_lease_sink::{self as sink, Expected, ENTRY_SIZE, MAX_LEASES};
use std::fs::File;
use std::io::{self, Read, Write};
use std::os::fd::{AsRawFd, FromRawFd};
use std::os::unix::fs::{FileTypeExt, MetadataExt};
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
}
const MAX_PAYLOAD: usize = 65_536;
fn error() -> io::Error {
    io::Error::other("leased pipe output refused")
}

fn read_exact(input: &mut File, bytes: &mut [u8], deadline: Instant) -> io::Result<()> {
    let mut at = 0;
    while at < bytes.len() {
        sink::ready_owner(0, 1, None, None, Some(4), deadline)?;
        match input.read(&mut bytes[at..]) {
            Ok(0) => return Err(error()),
            Ok(n) => at += n,
            Err(e)
                if matches!(
                    e.kind(),
                    io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock
                ) =>
            {
                ()
            }
            Err(e) => return Err(e),
        }
    }
    Ok(())
}

fn receipt(
    output: &mut File,
    kind: u8,
    operation: &[u8; 16],
    count: u32,
    deadline: Instant,
) -> io::Result<()> {
    let mut frame = Vec::with_capacity(25);
    frame.push(kind);
    frame.extend_from_slice(&20u32.to_be_bytes());
    frame.extend_from_slice(operation);
    frame.extend_from_slice(&count.to_be_bytes());
    let mut at = 0;
    while at < frame.len() {
        sink::ready_owner(1, 4, Some(0), None, None, deadline)?;
        match output.write(&frame[at..]) {
            Ok(0) => return Err(error()),
            Ok(n) => at += n,
            Err(e)
                if matches!(
                    e.kind(),
                    io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock
                ) =>
            {
                ()
            }
            Err(e) => return Err(e),
        }
    }
    Ok(())
}

fn output_ready(expected: &[Expected], deadline: Instant) -> io::Result<()> {
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return Err(error());
        }
        let mut fds = vec![
            Poll {
                fd: 3,
                events: 4,
                revents: 0,
            },
            Poll {
                fd: 0,
                events: 1,
                revents: 0,
            },
            Poll {
                fd: 4,
                events: 1,
                revents: 0,
            },
        ];
        fds.extend(expected.iter().map(|item| Poll {
            fd: item.process.as_raw_fd(),
            events: 1,
            revents: 0,
        }));
        let result = unsafe {
            poll(
                fds.as_mut_ptr(),
                fds.len(),
                left.as_millis().max(1).min(i32::MAX as u128) as i32,
            )
        };
        if result < 0 {
            let e = io::Error::last_os_error();
            if e.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(e);
        }
        if fds[0].revents & (8 | 16 | 32) != 0 || fds[1..].iter().any(|fd| fd.revents != 0) {
            return Err(error());
        }
        if fds[0].revents & 4 != 0 {
            return Ok(());
        }
    }
}

fn controls_live(expected: &[Expected], deadline: Instant) -> io::Result<()> {
    if Instant::now() >= deadline {
        return Err(error());
    }
    let mut fds = vec![
        Poll {
            fd: 0,
            events: 1,
            revents: 0,
        },
        Poll {
            fd: 4,
            events: 1,
            revents: 0,
        },
    ];
    fds.extend(expected.iter().map(|item| Poll {
        fd: item.process.as_raw_fd(),
        events: 1,
        revents: 0,
    }));
    if unsafe { poll(fds.as_mut_ptr(), fds.len(), 0) } != 0 {
        return Err(error());
    }
    Ok(())
}

#[cfg(ipse_lease_export_test_hook)]
fn test_before_write() {
    if let Some(base) = std::env::var_os("IPSE_TEST_OUTPUT_RACE") {
        let mut ready = std::path::PathBuf::from(&base);
        ready.set_extension("ready");
        let mut proceed = std::path::PathBuf::from(base);
        proceed.set_extension("proceed");
        let _ = std::fs::write(ready, b"ready");
        let until = Instant::now() + Duration::from_secs(5);
        while !proceed.exists() && Instant::now() < until {
            std::thread::sleep(Duration::from_millis(5));
        }
    }
}

fn validate_pipe(
    file: &File,
    dev: u64,
    ino: u64,
    access: i32,
    nonblocking: bool,
) -> io::Result<()> {
    let metadata = file.metadata()?;
    let flags = unsafe { fcntl(file.as_raw_fd(), 3) };
    if flags < 0
        || flags & 3 != access
        || (nonblocking && flags & 0x800 == 0)
        || !metadata.file_type().is_fifo()
        || metadata.dev() != dev
        || metadata.ino() != ino
    {
        return Err(error());
    }
    Ok(())
}

pub(crate) fn run(args: &[String]) -> Result<(), String> {
    if args.len() != 2 {
        return Err("invalid leased output arguments".into());
    }
    sink::nonblocking(0).map_err(|_| "host control unavailable")?;
    sink::nonblocking(1).map_err(|_| "receipt channel unavailable")?;
    if unsafe { fcntl(3, 3) } < 0 || unsafe { fcntl(4, 3) } < 0 {
        return Err("destination or owner control unavailable".into());
    }
    let mut host = unsafe { File::from_raw_fd(0) };
    let mut receipt_out = std::mem::ManuallyDrop::new(unsafe { File::from_raw_fd(1) });
    let mut destination = unsafe { File::from_raw_fd(3) };
    let owner = unsafe { File::from_raw_fd(4) };
    let setup = Instant::now() + Duration::from_secs(5);
    let mut header = [0; 5];
    read_exact(&mut host, &mut header, setup).map_err(|_| "output request unavailable")?;
    let len = u32::from_be_bytes(header[1..].try_into().unwrap()) as usize;
    if header[0] != b'I' || len < 61 || len > 61 + MAX_LEASES * ENTRY_SIZE + MAX_PAYLOAD {
        return Err("invalid output request".into());
    }
    let mut body = vec![0; len];
    read_exact(&mut host, &mut body, setup).map_err(|_| "output request unavailable")?;
    let ms = u64::from_be_bytes(body[0..8].try_into().unwrap());
    let operation: [u8; 16] = body[8..24].try_into().unwrap();
    let count = body[24] as usize;
    let dest_dev = u64::from_be_bytes(body[25..33].try_into().unwrap());
    let dest_ino = u64::from_be_bytes(body[33..41].try_into().unwrap());
    let owner_dev = u64::from_be_bytes(body[41..49].try_into().unwrap());
    let owner_ino = u64::from_be_bytes(body[49..57].try_into().unwrap());
    let payload_len = u32::from_be_bytes(body[57..61].try_into().unwrap()) as usize;
    if !(1..=30_000).contains(&ms)
        || operation.iter().all(|v| *v == 0)
        || count == 0
        || count > MAX_LEASES
        || payload_len == 0
        || payload_len > MAX_PAYLOAD
        || len != 61 + count * ENTRY_SIZE + payload_len
    {
        return Err("invalid output request".into());
    }
    validate_pipe(&destination, dest_dev, dest_ino, 1, true)
        .map_err(|_| "destination unavailable")?;
    validate_pipe(&owner, owner_dev, owner_ino, 0, false)
        .map_err(|_| "owner control unavailable")?;
    if (dest_dev, dest_ino) == (owner_dev, owner_ino) {
        return Err("owner and destination overlap".into());
    }
    let deadline = Instant::now() + Duration::from_millis(ms);
    let mut expected = Vec::new();
    let entries_end = 61 + count * ENTRY_SIZE;
    for entry in body[61..entries_end].chunks_exact(ENTRY_SIZE) {
        let item = sink::expected(entry).map_err(|_| "lease helper unavailable")?;
        if expected
            .iter()
            .any(|old: &Expected| old.dev == item.dev && old.ino == item.ino)
        {
            return Err("duplicate lease identity".into());
        }
        expected.push(item);
    }
    let mut leases = Vec::new();
    let mut peers = Vec::new();
    for item in &expected {
        let mut peer =
            sink::open_peer(item, Some(4), deadline).map_err(|_| "lease helper unavailable")?;
        let file = sink::receive(&peer, item, Some(4), deadline)
            .map_err(|_| "lease descriptor unavailable")?;
        sink::ready_owner(
            peer.as_raw_fd(),
            4,
            Some(0),
            Some(item.process.as_raw_fd()),
            Some(4),
            deadline,
        )
        .map_err(|_| "lease acknowledgment unavailable")?;
        peer.write_all(b"A")
            .map_err(|_| "lease acknowledgment unavailable")?;
        leases.push(file);
        peers.push(peer);
    }
    // Collection is not permission to write. The owner supplies a separate,
    // operation-bound activation only after independently revalidating facts.
    receipt(&mut receipt_out, b'L', &operation, count as u32, deadline)
        .map_err(|_| "collection receipt unavailable")?;
    let mut activation = [0; 17];
    read_exact(&mut host, &mut activation, deadline).map_err(|_| "activation unavailable")?;
    if activation[0] != b'A' || activation[1..] != operation {
        return Err("activation refused".into());
    }
    let payload = &body[entries_end..];
    let mut written = 0usize;
    let result = (|| -> io::Result<()> {
        while written < payload.len() {
            output_ready(&expected, deadline)?;
            #[cfg(ipse_lease_export_test_hook)]
            if written == 0 {
                test_before_write();
            }
            match destination.write(&payload[written..(written + 4096).min(payload.len())]) {
                Ok(0) => return Err(error()),
                Ok(n) => written += n,
                Err(e)
                    if matches!(
                        e.kind(),
                        io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock
                    ) =>
                {
                    ()
                }
                Err(e) => return Err(e),
            }
        }
        controls_live(&expected, deadline)
    })();
    drop(destination);
    drop(leases);
    drop(peers);
    let kind = if result.is_ok() { b'D' } else { b'U' };
    receipt(&mut receipt_out, kind, &operation, written as u32, deadline)
        .map_err(|_| "delivery outcome unconfirmed")?;
    if result.is_err() {
        return Err("delivery unconfirmed".into());
    }
    Ok(())
}
