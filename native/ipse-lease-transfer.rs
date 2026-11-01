//! Linux-only, one-shot export of a trusted helper's retained flock description.
//! The caller supplies an already validated lock and a private, operation-bound
//! request. This is not a path admission API and creates no lock or directory.
use std::ffi::c_void;
use std::fs::File;
use std::io::{self, Read, Write};
use std::mem::size_of;
use std::os::fd::{AsRawFd, FromRawFd};
use std::os::linux::net::SocketAddrExt;
use std::os::unix::fs::MetadataExt;
use std::os::unix::fs::FileTypeExt;
use std::os::unix::net::{SocketAddr, UnixListener, UnixStream};
use std::time::{Duration, Instant};

#[repr(C)]
struct Poll {
    fd: i32,
    events: i16,
    revents: i16,
}
#[repr(C)]
struct Peer {
    pid: i32,
    uid: u32,
    gid: u32,
}
#[repr(C)]
struct IoVec {
    base: *mut c_void,
    len: usize,
}
#[repr(C)]
struct Message {
    name: *mut c_void,
    name_len: u32,
    iov: *mut IoVec,
    iov_len: usize,
    control: *mut c_void,
    control_len: usize,
    flags: i32,
}
#[repr(C)]
struct Header {
    len: usize,
    level: i32,
    kind: i32,
}
#[repr(C, align(8))]
struct Descriptor {
    header: Header,
    fd: i32,
    padding: i32,
}

unsafe extern "C" {
    fn poll(fds: *mut Poll, count: usize, timeout: i32) -> i32;
    fn getsockopt(fd: i32, level: i32, name: i32, value: *mut c_void, length: *mut u32) -> i32;
    fn sendmsg(fd: i32, message: *const Message, flags: i32) -> isize;
    #[cfg(any(target_arch = "x86_64", target_arch = "aarch64"))]
    fn syscall(number: i64, ...) -> i64;
}
const SOL_SOCKET: i32 = 1;
const SO_PEERCRED: i32 = 17;
const SCM_RIGHTS: i32 = 1;
const MSG_NOSIGNAL: i32 = 0x4000;
const INPUT: i16 = 1;
const LOST: i16 = 8 | 16 | 32;
const REQUEST_SIZE: usize = 68;

#[derive(Debug, PartialEq, Eq)]
pub(crate) enum Failure {
    Refused,
    Unconfirmed,
}

/// A completed descriptor handoff with its authenticated recipient channel
/// still open. The caller must freeze the shared lock until `settle` succeeds;
/// any lost or malformed settlement is unconfirmed. The recipient is trusted
/// only when its actual pinned implementation proves every inherited copy was
/// closed before sending the receipt.
pub(crate) struct RetainedTransfer {
    stream: UnixStream,
    operation: [u8; 16],
    slot: u8,
    recipient: u32,
    uid: u32,
    process: File,
}

pub(crate) fn recipient_process(pid: u32) -> Result<File, Failure> {
    #[cfg(any(target_arch = "x86_64", target_arch = "aarch64"))]
    let fd = unsafe { syscall(434, pid, 0u32) };
    #[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
    let fd = -1;
    if fd < 0 { return Err(Failure::Refused); }
    Ok(unsafe { File::from_raw_fd(fd as i32) })
}

pub(crate) fn recipient_current(pid: u32, process: &File) -> bool {
    let mut p = Poll { fd: process.as_raw_fd(), events: INPUT, revents: 0 };
    if unsafe { poll(&mut p, 1, 0) } != 0 { return false; }
    let mine = std::fs::metadata("/proc/self/exe");
    let other = std::fs::metadata(format!("/proc/{pid}/exe"));
    match (mine, other) { (Ok(a), Ok(b)) => a.dev() == b.dev() && a.ino() == b.ino(), _ => false }
}

impl RetainedTransfer {
    pub(crate) fn settle<F: Fn() -> bool>(
        mut self,
        operation: &[u8; 16],
        slot: u8,
        control: i32,
        deadline: Instant,
        valid: F,
    ) -> Result<(), Failure> {
        if operation != &self.operation || slot != self.slot || !peer(&self.stream, self.recipient, self.uid) || !recipient_current(self.recipient, &self.process) {
            return Err(Failure::Unconfirmed);
        }
        let mut receipt = [0_u8; 18];
        if exact(&mut self.stream, control, &mut receipt, deadline).is_err() ||
            receipt[0] != b'C' || receipt[1..17] != self.operation || receipt[17] != self.slot ||
            !valid() || !recipient_current(self.recipient, &self.process) || !control_quiet(control) {
            return Err(Failure::Unconfirmed);
        }
        receipt[0] = b'F';
        if send_exact(&mut self.stream, control, &receipt, deadline).is_err() ||
            !valid() || !recipient_current(self.recipient, &self.process) || !control_quiet(control) {
            return Err(Failure::Unconfirmed);
        }
        let mut final_ack = [0_u8; 18];
        if exact(&mut self.stream, control, &mut final_ack, deadline).is_err() ||
            final_ack[0] != b'G' || final_ack[1..17] != self.operation || final_ack[17] != self.slot ||
            !valid() || !recipient_current(self.recipient, &self.process) || !control_quiet(control) {
            return Err(Failure::Unconfirmed);
        }
        Ok(())
    }
}

pub(crate) fn wait(fd: i32, control: i32, deadline: Instant) -> Result<(), Failure> {
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return Err(Failure::Refused);
        }
        let mut fds = [
            Poll {
                fd: control,
                events: INPUT,
                revents: 0,
            },
            Poll {
                fd,
                events: INPUT,
                revents: 0,
            },
        ];
        let result = unsafe {
            poll(
                fds.as_mut_ptr(),
                fds.len(),
                left.as_millis().min(5000) as i32,
            )
        };
        if result < 0 {
            if io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(Failure::Refused);
        }
        // Any pending or lost control input invalidates this one-shot handoff.
        if fds[0].revents != 0 || fds[1].revents & LOST != 0 {
            return Err(Failure::Refused);
        }
        if fds[1].revents & INPUT != 0 {
            return Ok(());
        }
    }
}

pub(crate) fn exact(
    stream: &mut UnixStream,
    control: i32,
    out: &mut [u8],
    deadline: Instant,
) -> Result<(), Failure> {
    let mut at = 0;
    while at < out.len() {
        wait(stream.as_raw_fd(), control, deadline)?;
        match stream.read(&mut out[at..]) {
            Ok(0) => return Err(Failure::Refused),
            Ok(n) => at += n,
            Err(e)
                if matches!(
                    e.kind(),
                    io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
                ) => {}
            Err(_) => return Err(Failure::Refused),
        }
    }
    Ok(())
}

pub(crate) fn send_exact(stream: &mut UnixStream, control: i32, bytes: &[u8], deadline: Instant) -> Result<(), Failure> {
    let mut offset = 0;
    while offset < bytes.len() {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() { return Err(Failure::Unconfirmed); }
        let mut fds = [Poll { fd: control, events: INPUT, revents: 0 }, Poll { fd: stream.as_raw_fd(), events: 4, revents: 0 }];
        let ready = unsafe { poll(fds.as_mut_ptr(), fds.len(), remaining.as_millis().min(5000) as i32) };
        if ready < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted { continue; }
        if ready < 0 || fds[0].revents != 0 || fds[1].revents & LOST != 0 { return Err(Failure::Unconfirmed); }
        if fds[1].revents & 4 == 0 { continue; }
        match stream.write(&bytes[offset..]) {
            Ok(0) => return Err(Failure::Unconfirmed),
            Ok(n) => offset += n,
            Err(e) if matches!(e.kind(), io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock) => {},
            Err(_) => return Err(Failure::Unconfirmed),
        }
    }
    Ok(())
}

pub(crate) fn peer(stream: &UnixStream, pid: u32, uid: u32) -> bool {
    let mut peer = Peer {
        pid: 0,
        uid: 0,
        gid: 0,
    };
    let mut length = size_of::<Peer>() as u32;
    (unsafe {
        getsockopt(
            stream.as_raw_fd(),
            SOL_SOCKET,
            SO_PEERCRED,
            (&mut peer as *mut Peer).cast(),
            &mut length,
        )
    }) == 0
        && length as usize == size_of::<Peer>()
        && peer.pid > 0
        && peer.pid as u32 == pid
        && peer.uid == uid
}

pub(crate) fn control_quiet(control: i32) -> bool {
    let mut state = Poll {
        fd: control,
        events: INPUT,
        revents: 0,
    };
    unsafe { poll(&mut state, 1, 0) == 0 }
}

// Compiled only into a developer test helper. It exposes the interval after
// the last liveness check so the owner-loss race can be demonstrated exactly.
#[cfg(ipse_lease_export_test_hook)]
fn test_after_final_check() {
    if let Some(base) = std::env::var_os("IPSE_TEST_EXPORT_RACE") {
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

#[cfg(ipse_lease_export_test_hook)]
fn test_before_send() {
    if let Some(base) = std::env::var_os("IPSE_TEST_EXPORT_STALL") {
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

pub(crate) fn send_fd(stream: &UnixStream, file: &File) -> bool {
    let mut byte = [b'L'];
    let mut iov = IoVec {
        base: byte.as_mut_ptr().cast(),
        len: 1,
    };
    let mut descriptor = Descriptor {
        header: Header {
            len: size_of::<Header>() + size_of::<i32>(),
            level: SOL_SOCKET,
            kind: SCM_RIGHTS,
        },
        fd: file.as_raw_fd(),
        padding: 0,
    };
    let message = Message {
        name: std::ptr::null_mut(),
        name_len: 0,
        iov: &mut iov,
        iov_len: 1,
        control: (&mut descriptor as *mut Descriptor).cast(),
        control_len: size_of::<Descriptor>(),
        flags: 0,
    };
    unsafe { sendmsg(stream.as_raw_fd(), &message, MSG_NOSIGNAL) == 1 }
}

/// Request: recipient PID (u32), abstract name (16 bytes), secret (32 bytes),
/// and expected lock device/inode (two u64), all integers big-endian. Only a
/// host-owned private control stream may select these fields. The recipient
/// must be a pinned, trusted native sink that never calls LOCK_UN on this FD.
pub(crate) fn export<F: Fn() -> bool>(
    file: &File,
    bytes: &[u8],
    uid: u32,
    control: i32,
    outer_deadline: Instant,
    valid: F,
) -> Result<(), Failure> {
    handoff(file, bytes, uid, control, outer_deadline, valid, false, None).map(|_| ())
}

pub(crate) fn export_retained<F: Fn() -> bool>(
    file: &File,
    bytes: &[u8],
    operation: [u8; 16],
    slot: u8,
    uid: u32,
    control: i32,
    outer_deadline: Instant,
    valid: F,
) -> Result<RetainedTransfer, Failure> {
    if operation.iter().all(|byte| *byte == 0) { return Err(Failure::Refused); }
    if bytes.len() != REQUEST_SIZE { return Err(Failure::Refused); }
    let recipient = u32::from_be_bytes(bytes[..4].try_into().unwrap());
    let process = recipient_process(recipient)?;
    if !recipient_current(recipient, &process) { return Err(Failure::Refused); }
    let stream = handoff(file, bytes, uid, control, outer_deadline, valid, true, None)?;
    if !recipient_current(recipient, &process) { return Err(Failure::Unconfirmed); }
    Ok(RetainedTransfer { stream, operation, slot, recipient, uid, process })
}

/// Lend the supervisor's actual nonblocking stdin write description once. This
/// is a distinct descriptor class: it never satisfies a regular flock export.
pub(crate) fn export_pipe<F: Fn() -> bool>(
    file: &File, bytes: &[u8], operation: [u8; 16], expiry: u64, payload: &[u8], uid: u32,
    control: i32, deadline: Instant, valid: F,
) -> Result<RetainedTransfer, Failure> {
    if operation.iter().all(|byte| *byte == 0) || bytes.len() != REQUEST_SIZE ||
        payload.is_empty() || payload.len() > 32_772 {
        return Err(Failure::Refused);
    }
    let recipient = u32::from_be_bytes(bytes[..4].try_into().unwrap());
    let process = recipient_process(recipient)?;
    if !recipient_current(recipient, &process) { return Err(Failure::Refused); }
    let mut binding = operation.to_vec();
    binding.extend_from_slice(&expiry.to_be_bytes());
    binding.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    binding.extend_from_slice(payload);
    let stream = handoff(file, bytes, uid, control, deadline, valid, true, Some(&binding))?;
    if !recipient_current(recipient, &process) { return Err(Failure::Unconfirmed); }
    Ok(RetainedTransfer { stream, operation, slot: 0, recipient, uid, process })
}

pub(crate) fn pipe_identity(file: &File, uid: u32) -> bool {
    unsafe extern "C" { fn fcntl(fd: i32, command: i32, ...) -> i32; }
    let Ok(meta) = file.metadata() else { return false; };
    let flags = unsafe { fcntl(file.as_raw_fd(), 3) };
    meta.file_type().is_fifo() && meta.uid() == uid && flags >= 0 &&
        flags & 3 == 1 && flags & 0x800 != 0
}

fn handoff<F: Fn() -> bool>(
    file: &File,
    bytes: &[u8],
    uid: u32,
    control: i32,
    outer_deadline: Instant,
    valid: F,
    uncertain_on_send: bool,
    pipe: Option<&[u8]>,
) -> Result<UnixStream, Failure> {
    if bytes.len() != REQUEST_SIZE {
        return Err(Failure::Refused);
    }
    let pid = u32::from_be_bytes(bytes[0..4].try_into().unwrap());
    let name = &bytes[4..20];
    let secret = &bytes[20..52];
    let dev = u64::from_be_bytes(bytes[52..60].try_into().unwrap());
    let ino = u64::from_be_bytes(bytes[60..68].try_into().unwrap());
    let meta = file.metadata().map_err(|_| Failure::Refused)?;
    let descriptor_valid = if pipe.is_some() { pipe_identity(file, uid) } else {
        meta.is_file() && meta.nlink() == 1 && meta.mode() & 0o7777 == 0o600 && meta.len() == 0
    };
    if pid == 0
        || name.iter().all(|v| *v == 0)
        || secret.iter().all(|v| *v == 0)
        || meta.uid() != uid
        || !descriptor_valid
        || meta.dev() != dev
        || meta.ino() != ino
        || !valid()
    {
        return Err(Failure::Refused);
    }
    let mut abstract_name = b"ipse-lease-v1-".to_vec();
    abstract_name.extend_from_slice(name);
    let address = SocketAddr::from_abstract_name(abstract_name).map_err(|_| Failure::Refused)?;
    let listener = UnixListener::bind_addr(&address).map_err(|_| Failure::Refused)?;
    listener
        .set_nonblocking(true)
        .map_err(|_| Failure::Refused)?;
    let deadline = outer_deadline.min(Instant::now() + Duration::from_secs(5));
    wait(listener.as_raw_fd(), control, deadline)?;
    let (mut stream, _) = listener.accept().map_err(|_| Failure::Refused)?;
    stream.set_nonblocking(true).map_err(|_| Failure::Refused)?;
    if !peer(&stream, pid, uid) {
        return Err(Failure::Refused);
    }
    let mut received = [0u8; 32];
    exact(&mut stream, control, &mut received, deadline)?;
    let mismatch = received
        .iter()
        .zip(secret)
        .fold(0u8, |acc, (left, right)| acc | (left ^ right));
    if mismatch != 0 || !valid() || !control_quiet(control) {
        return Err(Failure::Refused);
    }
    if let Some(binding) = pipe {
        let mut received = vec![0u8; binding.len()];
        exact(&mut stream, control, &mut received, deadline)?;
        if received != binding || !valid() || !control_quiet(control) {
            return Err(Failure::Refused);
        }
    }
    #[cfg(ipse_lease_export_test_hook)]
    test_before_send();
    if !send_fd(&stream, file) {
        return Err(if uncertain_on_send { Failure::Unconfirmed } else { Failure::Refused });
    }
    let mut ack = [0u8; 1];
    if exact(&mut stream, control, &mut ack, deadline).is_err()
        || ack != [b'A']
        || !valid()
        || !control_quiet(control)
    {
        return Err(Failure::Unconfirmed);
    }
    #[cfg(ipse_lease_export_test_hook)]
    test_after_final_check();
    Ok(stream)
}
