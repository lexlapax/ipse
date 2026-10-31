//! Private matched-tty lease probes. The inert mode writes no terminal bytes;
//! the synthetic display candidate has no production or Review call site.
use crate::ipse_lease_sink as sink;
use crate::ipse_owner_control as controls;
use std::fs::File;
use std::io::{self, Read, Write};
use std::os::fd::{AsRawFd, FromRawFd};
use std::os::unix::fs::MetadataExt;
use std::os::unix::net::UnixStream;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

#[repr(C)]
struct Poll {
    fd: i32,
    events: i16,
    revents: i16,
}
#[repr(C)]
struct Timespec {
    sec: i64,
    nsec: i64,
}
unsafe extern "C" {
    fn poll(fds: *mut Poll, count: usize, timeout: i32) -> i32;
    fn pipe2(fds: *mut i32, flags: i32) -> i32;
    fn fork() -> i32;
    fn kill(pid: i32, signal: i32) -> i32;
    fn waitpid(pid: i32, status: *mut i32, options: i32) -> i32;
    fn _exit(status: i32) -> !;
    fn clock_gettime(clock: i32, time: *mut Timespec) -> i32;
    #[cfg(ipse_terminal_display_test_hook)]
    fn raise(signal: i32) -> i32;
}
const INPUT: i16 = 1;
const OUTPUT: i16 = 4;
const BAD: i16 = 8 | 16 | 32;
fn err() -> String {
    "terminal lease probe unavailable".into()
}

fn wall_current(expiry: u64) -> bool {
    expiry > 0
        && expiry <= 9_007_199_254_740_991
        && SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .is_ok_and(|n| n.as_millis() < u128::from(expiry))
}

fn monotonic_ms(round_up: bool) -> Result<u64, String> {
    let mut time = Timespec { sec: 0, nsec: 0 };
    if unsafe { clock_gettime(1, &mut time) } != 0
        || time.sec < 0
        || !(0..1_000_000_000).contains(&time.nsec)
    {
        return Err(err());
    }
    let ms = (time.sec as u64)
        .checked_mul(1000)
        .ok_or_else(err)?
        .checked_add((time.nsec as u64) / 1_000_000)
        .ok_or_else(err)?;
    if round_up && time.nsec % 1_000_000 != 0 {
        ms.checked_add(1).ok_or_else(err)
    } else {
        Ok(ms)
    }
}

fn wait_reader_command(
    reader_control: &mut File,
    watched: &[i32],
    deadline: Instant,
    want: u8,
) -> bool {
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return false;
        }
        let mut fds = vec![Poll {
            fd: reader_control.as_raw_fd(),
            events: INPUT,
            revents: 0,
        }];
        fds.extend(watched.iter().map(|fd| Poll {
            fd: *fd,
            events: INPUT,
            revents: 0,
        }));
        let n = unsafe {
            poll(
                fds.as_mut_ptr(),
                fds.len(),
                left.as_millis().max(1).min(20) as i32,
            )
        };
        if n < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
            continue;
        }
        if n < 0
            || Instant::now() >= deadline
            || fds[0].revents & BAD != 0
            || fds.iter().skip(1).any(|p| p.revents != 0)
        {
            return false;
        }
        if fds[0].revents & INPUT != 0 {
            let mut byte = [0u8; 1];
            return matches!(reader_control.read(&mut byte), Ok(1)) && byte == [want];
        }
    }
}

fn synthetic_write(
    tty: &mut File,
    control: i32,
    guardian: i32,
    watched: &[i32],
    payload: &[u8],
    expiry: u64,
    deadline: Instant,
) -> bool {
    let mut guards = watched.to_vec();
    guards.push(guardian);
    let mut at = 0;
    #[cfg(ipse_terminal_display_test_hook)]
    let mut prewrite_stop = std::env::var_os("IPSE_TEST_TTY_PREWRITE_STOP").is_some();
    while at < payload.len() {
        if !wall_current(expiry)
            || Instant::now() >= deadline
            || sink::ready_watch(tty.as_raw_fd(), OUTPUT, control, &guards, deadline).is_err()
        {
            return false;
        }
        #[cfg(ipse_terminal_display_test_hook)]
        if std::env::var_os("IPSE_TEST_TTY_READY_STOP").is_some() {
            unsafe {
                raise(19);
            }
        }
        if !wall_current(expiry) || Instant::now() >= deadline {
            return false;
        }
        #[cfg(ipse_terminal_display_test_hook)]
        if prewrite_stop {
            prewrite_stop = false;
            unsafe {
                raise(19);
            }
        }
        match tty.write(&payload[at..(at + 4096).min(payload.len())]) {
            Ok(0) => return false,
            Ok(n) => {
                at += n;
                #[cfg(ipse_terminal_display_test_hook)]
                if at < payload.len() && std::env::var_os("IPSE_TEST_TTY_PARTIAL_STOP").is_some() {
                    unsafe {
                        raise(19);
                    }
                }
            }
            Err(e)
                if matches!(
                    e.kind(),
                    io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock
                ) =>
            {
                ()
            }
            Err(_) => return false,
        }
    }
    wall_current(expiry)
        && Instant::now() < deadline
        && crate::ipse_lease_transfer::control_quiet(control)
        && guards
            .iter()
            .all(|fd| crate::ipse_lease_transfer::control_quiet(*fd))
}

struct ChildGuard(i32);
impl Drop for ChildGuard {
    fn drop(&mut self) {
        if self.0 <= 0 {
            return;
        }
        unsafe {
            kill(self.0, 9);
        }
        let mut status = 0;
        loop {
            let n = unsafe { waitpid(self.0, &mut status, 0) };
            if n == self.0
                || (n < 0 && io::Error::last_os_error().kind() != io::ErrorKind::Interrupted)
            {
                break;
            }
        }
    }
}

fn frame(
    output: &mut File,
    control: i32,
    watched: &[i32],
    kind: u8,
    body: &[u8],
    deadline: Instant,
    expiry: Option<u64>,
) -> Result<(), String> {
    let mut frame = vec![kind];
    frame.extend_from_slice(&(body.len() as u32).to_be_bytes());
    frame.extend_from_slice(body);
    let mut at = 0;
    while at < frame.len() {
        if Instant::now() >= deadline || expiry.is_some_and(|wall| !wall_current(wall)) {
            return Err(err());
        }
        sink::ready_watch(output.as_raw_fd(), OUTPUT, control, watched, deadline)
            .map_err(|_| err())?;
        #[cfg(ipse_terminal_display_test_hook)]
        if kind == b'C' && std::env::var_os("IPSE_TEST_FRAME_CLOSE_READY_STOP").is_some() {
            unsafe {
                raise(19);
            }
        }
        if Instant::now() >= deadline || expiry.is_some_and(|wall| !wall_current(wall)) {
            return Err(err());
        }
        match output.write(&frame[at..]) {
            Ok(0) => return Err(err()),
            Ok(n) => at += n,
            Err(e)
                if matches!(
                    e.kind(),
                    io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock
                ) =>
            {
                ()
            }
            Err(_) => return Err(err()),
        }
    }
    if Instant::now() >= deadline || expiry.is_some_and(|wall| !wall_current(wall)) {
        Err(err())
    } else {
        Ok(())
    }
}

// `D` is native write progress only, never an effect or Review receipt. A
// partially delivered or late status remains unknown to any future caller.
fn display_frame(
    output: &mut File,
    control: i32,
    watched: &[i32],
    body: &[u8],
    expiry: u64,
    deadline: Instant,
) -> Result<(), String> {
    let mut bytes = vec![b'D'];
    bytes.extend_from_slice(&(body.len() as u32).to_be_bytes());
    bytes.extend_from_slice(body);
    let mut at = 0;
    while at < bytes.len() {
        if !wall_current(expiry) || Instant::now() >= deadline {
            return Err(err());
        }
        sink::ready_watch(output.as_raw_fd(), OUTPUT, control, watched, deadline)
            .map_err(|_| err())?;
        if !wall_current(expiry) || Instant::now() >= deadline {
            return Err(err());
        }
        match output.write(&bytes[at..]) {
            Ok(0) => return Err(err()),
            Ok(n) => at += n,
            Err(e)
                if matches!(
                    e.kind(),
                    io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock
                ) =>
            {
                ()
            }
            Err(_) => return Err(err()),
        }
    }
    if wall_current(expiry) && Instant::now() < deadline {
        Ok(())
    } else {
        Err(err())
    }
}

fn read_command(
    control: &mut File,
    watched: &[i32],
    deadline: Instant,
    out: &mut [u8],
) -> Result<(), String> {
    let mut at = 0;
    while at < out.len() {
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return Err(err());
        }
        let mut fds = vec![Poll {
            fd: control.as_raw_fd(),
            events: INPUT,
            revents: 0,
        }];
        fds.extend(watched.iter().map(|fd| Poll {
            fd: *fd,
            events: INPUT,
            revents: 0,
        }));
        let n = unsafe {
            poll(
                fds.as_mut_ptr(),
                fds.len(),
                left.as_millis().max(1).min(20) as i32,
            )
        };
        if n < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
            continue;
        }
        if n < 0
            || Instant::now() >= deadline
            || fds[0].revents & BAD != 0
            || fds.iter().skip(1).any(|p| p.revents != 0)
        {
            return Err(err());
        }
        if fds[0].revents & INPUT == 0 {
            continue;
        }
        match control.read(&mut out[at..]) {
            Ok(0) => return Err(err()),
            Ok(n) => at += n,
            Err(e)
                if matches!(
                    e.kind(),
                    io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock
                ) =>
            {
                ()
            }
            Err(_) => return Err(err()),
        }
    }
    Ok(())
}

fn send_peer(
    peer: &mut UnixStream,
    bytes: &[u8],
    control: i32,
    watched: &[i32],
    deadline: Instant,
) -> Result<(), String> {
    let mut at = 0;
    while at < bytes.len() {
        sink::ready_watch(peer.as_raw_fd(), OUTPUT, control, watched, deadline)
            .map_err(|_| err())?;
        match peer.write(&bytes[at..]) {
            Ok(0) => return Err(err()),
            Ok(n) => at += n,
            Err(e)
                if matches!(
                    e.kind(),
                    io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock
                ) =>
            {
                ()
            }
            Err(_) => return Err(err()),
        }
    }
    Ok(())
}
fn read_peer(
    peer: &mut UnixStream,
    bytes: &mut [u8],
    control: i32,
    watched: &[i32],
    deadline: Instant,
) -> Result<(), String> {
    let mut at = 0;
    while at < bytes.len() {
        sink::ready_watch(peer.as_raw_fd(), INPUT, control, watched, deadline)
            .map_err(|_| err())?;
        match peer.read(&mut bytes[at..]) {
            Ok(0) => return Err(err()),
            Ok(n) => at += n,
            Err(e)
                if matches!(
                    e.kind(),
                    io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock
                ) =>
            {
                ()
            }
            Err(_) => return Err(err()),
        }
    }
    Ok(())
}

struct InputRestore {
    state: crate::ipse_operator::unix::v2::RetainedInput,
    tty: File,
    armed: bool,
}
impl Drop for InputRestore {
    fn drop(&mut self) {
        if self.armed {
            let _ = self.state.restore(&self.tty);
        }
    }
}

fn retained_input(
    control: &mut File,
    output: &mut File,
    tty: &mut File,
    watched: &[i32],
    operation: &[u8; 16],
    wall: u64,
    deadline: Instant,
) -> Result<(), String> {
    let state = crate::ipse_operator::unix::v2::RetainedInput::capture(tty)?;
    let mut restore = InputRestore {
        state: state.clone(),
        tty: tty.try_clone().map_err(|_| err())?,
        armed: true,
    };
    let mut guard_pipe = [-1; 2];
    let mut event_pipe = [-1; 2];
    if unsafe { pipe2(guard_pipe.as_mut_ptr(), 0x80000 | 0x800) } != 0 {
        return Err(err());
    }
    let guard_read = unsafe { File::from_raw_fd(guard_pipe[0]) };
    let guard_write = unsafe { File::from_raw_fd(guard_pipe[1]) };
    if unsafe { pipe2(event_pipe.as_mut_ptr(), 0x80000 | 0x800) } != 0 {
        return Err(err());
    }
    let mut events = unsafe { File::from_raw_fd(event_pipe[0]) };
    let mut emitter = unsafe { File::from_raw_fd(event_pipe[1]) };
    let child = unsafe { fork() };
    if child < 0 {
        return Err(err());
    }
    if child == 0 {
        drop(guard_write);
        drop(events);
        let value = state.read(control, &guard_read, tty, watched, deadline);
        let code = match value {
            Ok(Some(text)) if text.len() <= 256 => {
                let mut bytes = (text.len() as u32).to_be_bytes().to_vec();
                bytes.extend_from_slice(&text);
                if emitter.write_all(&bytes).is_ok() {
                    0
                } else {
                    2
                }
            }
            _ => 2,
        };
        unsafe { _exit(code) }
    }
    drop(guard_read);
    drop(emitter);
    let mut guard = ChildGuard(child);
    let mut input = Vec::new();
    let mut exited = false;
    let mut status = 0;
    loop {
        if !wall_current(wall)
            || Instant::now() >= deadline
            || !crate::ipse_lease_transfer::control_quiet(control.as_raw_fd())
            || watched
                .iter()
                .any(|fd| !crate::ipse_lease_transfer::control_quiet(*fd))
        {
            return Err(err());
        }
        if !exited {
            let n = unsafe { waitpid(child, &mut status, 1) };
            if n == child {
                exited = true;
                guard.0 = -1;
            } else if n < 0 && io::Error::last_os_error().kind() != io::ErrorKind::Interrupted {
                return Err(err());
            }
        }
        let mut chunk = [0u8; 260];
        match events.read(&mut chunk) {
            Ok(0) if exited => break,
            Ok(n) if n > 0 && input.len() + n <= 260 => input.extend_from_slice(&chunk[..n]),
            Ok(0) => (),
            Ok(_) => return Err(err()),
            Err(e)
                if matches!(
                    e.kind(),
                    io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock
                ) =>
            {
                ()
            }
            Err(_) => return Err(err()),
        }
        std::thread::sleep(Duration::from_millis(2));
    }
    drop(guard_write);
    if status != 0 || input.len() < 4 {
        return Err(err());
    }
    let size = u32::from_be_bytes(input[..4].try_into().unwrap()) as usize;
    if size > 256 || input.len() != size + 4 {
        return Err(err());
    }
    state.restore(tty)?;
    restore.armed = false;
    let mut result = operation.to_vec();
    result.extend_from_slice(&input[4..]);
    frame(
        output,
        control.as_raw_fd(),
        watched,
        b'i',
        &result,
        deadline,
        Some(wall),
    )?;
    frame(
        output,
        control.as_raw_fd(),
        watched,
        b'z',
        operation,
        deadline,
        Some(wall),
    )?;
    Ok(())
}

pub(crate) fn run(
    mut control: File,
    mut output: File,
    mut tty: File,
    channel: File,
    mut deadline: Instant,
    mut overall_deadline: Instant,
    display_limit: usize,
    input_phase: bool,
    source_limit: usize,
    accepted_delivery: bool,
    peer_notice: bool,
    session_payload: bool,
) -> Result<(), String> {
    let synthetic_display = display_limit != 0;
    let management_display = display_limit == 65_536;
    sink::nonblocking(control.as_raw_fd()).map_err(|_| err())?;
    sink::nonblocking(output.as_raw_fd()).map_err(|_| err())?;
    let control_fd = control.as_raw_fd();
    if management_display {
        let clock = monotonic_ms(false)?;
        frame(
            &mut output,
            control_fd,
            &[],
            b'R',
            &clock.to_be_bytes(),
            deadline,
            None,
        )?;
    }
    let mut header = [0u8; 5];
    sink::read_exact(&mut control, &mut header, None, None, deadline).map_err(|_| err())?;
    let size = u32::from_be_bytes(header[1..].try_into().unwrap()) as usize;
    let max_size = if synthetic_display {
        529 + display_limit + if accepted_delivery { 170 } else { 85 * source_limit }
            + if management_display { 8 } else { 0 }
            + if input_phase { 16 } else { 0 }
    } else {
        493
    };
    if header[0] != b'I' || !(238..=max_size).contains(&size) {
        return Err(err());
    }
    let mut body = vec![0u8; size];
    sink::read_exact(&mut control, &mut body, None, None, deadline).map_err(|_| err())?;
    let operation: [u8; 16] = body[..16].try_into().unwrap();
    let count = body[16] as usize;
    let manifest_size = 153 + 85 * count;
    let minimum = if accepted_delivery { 6 } else if source_limit > 0 && !session_payload { 5 } else { 4 };
    let maximum = if accepted_delivery { 6 } else { 4 + source_limit };
    if operation.iter().all(|b| *b == 0)
        || !(1..=maximum).contains(&count)
        || (synthetic_display && !(minimum..=maximum).contains(&count))
        || size < manifest_size
    {
        return Err(err());
    }
    let (payload, expiry, overall_wall, tty_identity) = if synthetic_display {
        if size
            < manifest_size
                + 37
                + if management_display { 8 } else { 0 }
                + if input_phase { 16 } else { 0 }
        {
            return Err(err());
        }
        let extra = &body[manifest_size..];
        let dev = u64::from_be_bytes(extra[..8].try_into().unwrap());
        let ino = u64::from_be_bytes(extra[8..16].try_into().unwrap());
        let rdev = u64::from_be_bytes(extra[16..24].try_into().unwrap());
        let expiry = u64::from_be_bytes(extra[24..32].try_into().unwrap());
        let mut whole_wall = expiry;
        let length_offset = if management_display {
            let absolute = u64::from_be_bytes(extra[32..40].try_into().unwrap());
            let instant_before = Instant::now();
            let now = monotonic_ms(true)?;
            let remaining = absolute
                .checked_sub(now)
                .filter(|n| *n > 0 && *n <= 5_000)
                .ok_or_else(err)?;
            deadline = deadline.min(instant_before + Duration::from_millis(remaining));
            if input_phase {
                whole_wall = u64::from_be_bytes(extra[40..48].try_into().unwrap());
                let absolute_overall = u64::from_be_bytes(extra[48..56].try_into().unwrap());
                let before_overall = Instant::now();
                let now_overall = monotonic_ms(true)?;
                let overall_remaining = absolute_overall
                    .checked_sub(now_overall)
                    .filter(|n| *n > 0 && *n <= 120_000)
                    .ok_or_else(err)?;
                if !wall_current(whole_wall) || whole_wall < expiry || absolute_overall < absolute {
                    return Err(err());
                }
                overall_deadline =
                    overall_deadline.min(before_overall + Duration::from_millis(overall_remaining));
                56
            } else {
                40
            }
        } else {
            32
        };
        let length = u32::from_be_bytes(extra[length_offset..length_offset + 4].try_into().unwrap())
            as usize;
        if !(1..=display_limit).contains(&length)
            || extra.len() != length_offset + 4 + length
            || !wall_current(expiry)
        {
            return Err(err());
        }
        let payload = &extra[length_offset + 4..];
        let notice_payload: &[u8] = if input_phase {
            b"Synthetic grouped review.\nType pin 0123456789abcdef to confirm, or anything else to cancel.\n> "
        } else {
            b"SYNTHETIC_LEASED_DISPLAY"
        };
        if (accepted_delivery && payload != b"SYNTHETIC_ACCEPTED_LEASE_DISPLAY")
            || (peer_notice && !accepted_delivery && !session_payload && payload != notice_payload) {
            return Err(err());
        }
        if !std::str::from_utf8(payload)
            .is_ok_and(|s| s.chars().all(|c| !c.is_control() || c == '\n' || c == '\t'))
        {
            return Err(err());
        }
        let m = tty.metadata().map_err(|_| err())?;
        if (m.dev(), m.ino(), m.rdev()) != (dev, ino, rdev) {
            return Err(err());
        }
        (payload, expiry, whole_wall, Some((dev, ino, rdev)))
    } else {
        if size != manifest_size {
            return Err(err());
        }
        (&[][..], 0, 0, None)
    };
    let session_entry = &body[17..85];
    let host_entry = &body[85..153];
    let mut raw = Vec::new();
    for entry in [session_entry, host_entry] {
        raw.push(entry);
    }
    let mut requests = Vec::new();
    for chunk in body[153..manifest_size].chunks_exact(85) {
        if chunk[0] > 2 || chunk[1..17].iter().all(|b| *b == 0) {
            return Err(err());
        }
        let op: [u8; 16] = chunk[1..17].try_into().unwrap();
        requests.push((chunk[0], op, &chunk[17..85]));
        raw.push(&chunk[17..85]);
    }
    if source_limit > 0 {
        let slots: Vec<_> = requests.iter().map(|item| item.0).collect();
        if slots.len() < minimum || slots[..4] != [0, 0, 1, 2] || slots[4..].iter().any(|slot| *slot != 0) {
            return Err(err());
        }
    }
    if accepted_delivery && requests.iter().map(|item| item.0).collect::<Vec<_>>() != [0, 0, 1, 2, 0, 0] {
        return Err(err());
    }
    for (i, a) in raw.iter().enumerate() {
        for b in raw.iter().skip(i + 1) {
            if a[4..20] == b[4..20] || a[20..52] == b[20..52] || a[52..68] == b[52..68] {
                return Err(err());
            }
        }
    }
    let mut ready = operation.to_vec();
    ready.push(count as u8);
    frame(
        &mut output,
        control_fd,
        &[],
        b'H',
        &ready,
        deadline,
        if synthetic_display {
            Some(expiry)
        } else {
            None
        },
    )?;
    let mut owners = Vec::new();
    let mut watched = Vec::new();
    for (role, entry) in [(1, session_entry), (2, host_entry)] {
        let (owner, expected, peer) =
            controls::collect(entry, &operation, role, control_fd, &watched, deadline)?;
        watched.extend([
            owner.as_raw_fd(),
            expected.process.as_raw_fd(),
            peer.as_raw_fd(),
        ]);
        owners.push((owner, expected, peer));
    }
    let owner_watch = watched.clone();
    let mut leases = Vec::new();
    let mut entries = Vec::new();
    let mut peers = Vec::new();
    for (slot, op, bytes) in requests {
        let item = sink::expected(bytes).map_err(|_| err())?;
        if entries
            .iter()
            .any(|(prior_slot, _, old): &(u8, [u8; 16], sink::Expected)| {
                *prior_slot == slot && old.pid == item.pid
            })
        {
            return Err(err());
        }
        let mut peer =
            sink::open_peer_watch(&item, control_fd, &watched, deadline).map_err(|_| err())?;
        let lease =
            sink::receive_watch(&peer, &item, control_fd, &watched, deadline).map_err(|_| err())?;
        let mut guards = watched.clone();
        guards.push(item.process.as_raw_fd());
        send_peer(&mut peer, b"A", control_fd, &guards, deadline)?;
        watched.push(item.process.as_raw_fd());
        leases.push(lease);
        entries.push((slot, op, item));
        peers.push(peer);
    }
    // During a synthetic display, retained lease peer EOF is also loss even if
    // its exporter process remains alive. Settlement F/G becomes readable
    // only after the reader has stopped, so those sockets are not watched as
    // unexpected input during the later ordered close protocol.
    let mut display_watch = watched.clone();
    if synthetic_display {
        display_watch.extend(peers.iter().map(|peer| peer.as_raw_fd()));
    }
    // Both forked processes inherit every exact lease and owner descriptor.
    let mut pipe = [-1; 2];
    if unsafe { pipe2(pipe.as_mut_ptr(), 0x80000 | 0x800) } != 0 {
        return Err(err());
    }
    let mut reader_control = unsafe { File::from_raw_fd(pipe[0]) };
    let mut guardian_control = unsafe { File::from_raw_fd(pipe[1]) };
    let mut event_pipe = [-1; 2];
    if unsafe { pipe2(event_pipe.as_mut_ptr(), 0x80000 | 0x800) } != 0 {
        return Err(err());
    }
    let mut reader_events = unsafe { File::from_raw_fd(event_pipe[0]) };
    let mut reader_emit = unsafe { File::from_raw_fd(event_pipe[1]) };
    let child = unsafe { fork() };
    if child < 0 {
        return Err(err());
    }
    if child == 0 {
        drop(guardian_control);
        drop(reader_events);
        if synthetic_display {
            if !wait_reader_command(&mut reader_control, &display_watch, deadline, b'A')
                || !synthetic_write(
                    &mut tty,
                    control_fd,
                    reader_control.as_raw_fd(),
                    &display_watch,
                    payload,
                    expiry,
                    deadline,
                )
            {
                unsafe { _exit(2) }
            }
            let mut guards = display_watch.clone();
            guards.push(reader_control.as_raw_fd());
            if sink::ready_watch(
                reader_emit.as_raw_fd(),
                OUTPUT,
                control_fd,
                &guards,
                deadline,
            )
            .is_err()
                || !wall_current(expiry)
                || Instant::now() >= deadline
                || !matches!(reader_emit.write(b"D"), Ok(1))
            {
                unsafe { _exit(2) }
            }
        }
        let success = wait_reader_command(&mut reader_control, &display_watch, deadline, b'C');
        unsafe { _exit(if success { 0 } else { 2 }) }
    }
    drop(reader_control);
    drop(reader_emit);
    let mut child_guard = ChildGuard(child);
    let child_process = if synthetic_display {
        Some(sink::pidfd(child as u32).map_err(|_| err())?)
    } else {
        None
    };
    let mut active_watch = display_watch.clone();
    if let Some(process) = &child_process {
        active_watch.push(process.as_raw_fd());
    }
    let mut collected = ready.clone();
    collected.extend_from_slice(&(child as u32).to_be_bytes());
    frame(
        &mut output,
        control_fd,
        &active_watch,
        b'L',
        &collected,
        deadline,
        if synthetic_display {
            Some(expiry)
        } else {
            None
        },
    )?;
    if synthetic_display {
        let mut activation_header = [0u8; 5];
        read_command(
            &mut control,
            &active_watch,
            deadline,
            &mut activation_header,
        )?;
        let activation_len =
            u32::from_be_bytes(activation_header[1..].try_into().unwrap()) as usize;
        if activation_header[0] != b'A' || activation_len != body.len() {
            return Err(err());
        }
        let mut activation = vec![0u8; activation_len];
        read_command(&mut control, &active_watch, deadline, &mut activation)?;
        let m = tty.metadata().map_err(|_| err())?;
        if activation != body
            || !wall_current(expiry)
            || Instant::now() >= deadline
            || Some((m.dev(), m.ino(), m.rdev())) != tty_identity
        {
            return Err(err());
        }
        guardian_control.write_all(b"A").map_err(|_| err())?;
        sink::ready_watch(
            reader_events.as_raw_fd(),
            INPUT,
            control_fd,
            &active_watch,
            deadline,
        )
        .map_err(|_| err())?;
        let mut done = [0u8; 1];
        if !matches!(reader_events.read(&mut done), Ok(1))
            || done != [b'D']
            || !wall_current(expiry)
            || !crate::ipse_lease_transfer::control_quiet(control_fd)
            || active_watch
                .iter()
                .any(|fd| !crate::ipse_lease_transfer::control_quiet(*fd))
        {
            return Err(err());
        }
        display_frame(
            &mut output,
            control_fd,
            &active_watch,
            &ready,
            expiry,
            deadline,
        )?;
    }
    let mut close = [0u8; 17];
    read_command(&mut control, &active_watch, deadline, &mut close)?;
    if close[0] != b'C' || close[1..] != operation {
        return Err(err());
    }
    guardian_control.write_all(b"C").map_err(|_| err())?;
    let mut status = 0;
    loop {
        let n = unsafe { waitpid(child, &mut status, 1) };
        if n == child {
            break;
        }
        if n < 0 && io::Error::last_os_error().kind() != io::ErrorKind::Interrupted {
            return Err(err());
        }
        if Instant::now() >= deadline
            || !crate::ipse_lease_transfer::control_quiet(control_fd)
            || watched
                .iter()
                .any(|fd| !crate::ipse_lease_transfer::control_quiet(*fd))
        {
            return Err(err());
        }
        std::thread::sleep(Duration::from_millis(1));
    }
    child_guard.0 = -1;
    if status != 0 {
        return Err(err());
    }
    drop(leases);
    for (index, (slot, op, _)) in entries.iter().enumerate() {
        let mut receipt = [0u8; 18];
        receipt[0] = b'C';
        receipt[1..17].copy_from_slice(op);
        receipt[17] = *slot;
        send_peer(&mut peers[index], &receipt, control_fd, &watched, deadline)?;
    }
    for (index, (slot, op, _)) in entries.iter().enumerate() {
        let mut ack = [0u8; 18];
        read_peer(&mut peers[index], &mut ack, control_fd, &watched, deadline)?;
        if ack[0] != b'F' || ack[1..17] != *op || ack[17] != *slot {
            return Err(err());
        }
        ack[0] = b'G';
        send_peer(&mut peers[index], &ack, control_fd, &watched, deadline)?;
        let mut fds = [Poll {
            fd: peers[index].as_raw_fd(),
            events: INPUT,
            revents: 0,
        }];
        loop {
            if Instant::now() >= deadline
                || !crate::ipse_lease_transfer::control_quiet(control_fd)
                || watched
                    .iter()
                    .any(|fd| !crate::ipse_lease_transfer::control_quiet(*fd))
            {
                return Err(err());
            }
            let n = unsafe { poll(fds.as_mut_ptr(), fds.len(), 10) };
            if n < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
                continue;
            }
            if n < 0 || fds[0].revents & (8 | 32) != 0 {
                return Err(err());
            }
            if fds[0].revents & (INPUT | 16) != 0 {
                let mut byte = [0u8; 1];
                match peers[index].read(&mut byte) {
                    Ok(0) => break,
                    Err(e)
                        if matches!(
                            e.kind(),
                            io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock
                        ) =>
                    {
                        ()
                    }
                    _ => return Err(err()),
                }
            }
        }
    }
    // Retain matched tty, channel, owner controls and peer state until all
    // original exporters have completed their per-slot close protocol.
    drop(peers);
    if peer_notice {
        // This private mode sends only after its fixed synthetic bytes and the
        // exporter close handshakes. The recipient still needs purpose binding.
        if !wall_current(expiry) || Instant::now() >= deadline { return Err(err()); }
        let mut notice = [0u8; 25];
        notice[0] = b'N';
        notice[1..17].copy_from_slice(&operation);
        notice[17..25].copy_from_slice(&expiry.to_be_bytes());
        send_peer(&mut owners[0].2, &notice, control_fd, &watched, deadline)?;
    }
    frame(
        &mut output,
        control_fd,
        &[],
        b'C',
        &ready,
        deadline,
        if synthetic_display {
            Some(expiry)
        } else {
            None
        },
    )?;
    if synthetic_display {
        // Keep both owner channels live until the same caller acknowledges the
        // settled close. This prevents their helper EOF from racing ahead of C.
        let mut release = [0u8; 17];
        read_command(
            &mut control,
            if input_phase { &owner_watch } else { &watched },
            if input_phase {
                overall_deadline
            } else {
                deadline
            },
            &mut release,
        )?;
        if release[0] != b'U' || release[1..] != operation {
            return Err(err());
        }
        if peer_notice {
            if !wall_current(expiry) || Instant::now() >= deadline { return Err(err()); }
            #[cfg(ipse_terminal_display_test_hook)]
            if std::env::var_os("IPSE_TEST_TTY_FINAL_NOTICE_STOP").is_some() {
                unsafe { raise(19); }
            }
            let mut final_notice = [0u8; 17];
            final_notice[0] = b'F';
            final_notice[1..].copy_from_slice(&operation);
            let peer_fd = owners[0].2.as_raw_fd();
            let other_watch: Vec<i32> = watched.iter().copied().filter(|fd| *fd != peer_fd).collect();
            send_peer(&mut owners[0].2, &final_notice, control_fd, &other_watch, deadline)?;
            let mut ack = [0u8; 1];
            read_peer(&mut owners[0].2, &mut ack, control_fd, &other_watch, deadline)?;
            if ack != [b'A'] { return Err(err()); }
        }
        if input_phase {
            if !wall_current(overall_wall) || Instant::now() >= overall_deadline {
                return Err(err());
            }
            retained_input(
                &mut control,
                &mut output,
                &mut tty,
                &owner_watch,
                &operation,
                overall_wall,
                overall_deadline,
            )?;
        }
    }
    drop((tty, channel, owners));
    Ok(())
}
