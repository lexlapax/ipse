//! Inert Linux lease collector. This mode cannot display or deliver payloads.
//! It authenticates the process and file identity of each transferred lease,
//! retains the descriptions, and reports a close only after dropping them.
use std::ffi::c_void;
use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::mem::size_of;
use std::os::fd::{AsRawFd, FromRawFd};
use std::os::unix::fs::MetadataExt;
use std::os::unix::net::UnixStream;
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
struct Control([u8; 4096]);
#[repr(C)]
struct Address {
    family: u16,
    path: [u8; 108],
}
unsafe extern "C" {
    fn poll(fds: *mut Poll, count: usize, timeout: i32) -> i32;
    fn socket(domain: i32, kind: i32, protocol: i32) -> i32;
    fn connect(fd: i32, address: *const c_void, len: u32) -> i32;
    fn getsockopt(fd: i32, level: i32, name: i32, value: *mut c_void, length: *mut u32) -> i32;
    fn recvmsg(fd: i32, message: *mut Message, flags: i32) -> isize;
    fn fcntl(fd: i32, command: i32, ...) -> i32;
    #[cfg(any(target_arch = "x86_64", target_arch = "aarch64"))]
    fn syscall(number: i64, ...) -> i64;
    fn geteuid() -> u32;
}

const INPUT: i16 = 1;
const OUTPUT: i16 = 4;
const BAD: i16 = 8 | 16 | 32;
// Up to 128 external sources, the separately held live Session, and Identity
// plus Consent. The live Session can exist even if no proof refers to it.
pub(crate) const MAX_LEASES: usize = 131;
pub(crate) const ENTRY_SIZE: usize = 68;

pub(crate) struct Expected {
    pub(crate) pid: u32,
    pub(crate) name: [u8; 16],
    pub(crate) secret: [u8; 32],
    pub(crate) dev: u64,
    pub(crate) ino: u64,
    pub(crate) process: File,
}

fn error() -> io::Error {
    io::Error::other("lease collection refused")
}

#[cfg(ipse_lease_export_test_hook)]
fn test_marker(name: &str) {
    if let Some(path) = std::env::var_os(name) {
        let _ = fs::write(path, b"ready");
    }
}

fn ready(
    fd: i32,
    events: i16,
    control: Option<i32>,
    process: Option<i32>,
    deadline: Instant,
) -> io::Result<()> {
    ready_owner(fd, events, control, process, None, deadline)
}

pub(crate) fn ready_owner(
    fd: i32,
    events: i16,
    control: Option<i32>,
    process: Option<i32>,
    owner: Option<i32>,
    deadline: Instant,
) -> io::Result<()> {
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return Err(error());
        }
        let mut fds = [
            Poll {
                fd,
                events,
                revents: 0,
            },
            Poll {
                fd: control.unwrap_or(-1),
                events: INPUT,
                revents: 0,
            },
            Poll {
                fd: process.unwrap_or(-1),
                events: INPUT,
                revents: 0,
            },
            Poll {
                fd: owner.unwrap_or(-1),
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
        if result < 0 {
            let e = io::Error::last_os_error();
            if e.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(e);
        }
        if fds[1].revents != 0
            || fds[2].revents != 0
            || fds[3].revents != 0
            || fds[0].revents & BAD != 0
        {
            return Err(error());
        }
        if fds[0].revents & events != 0 {
            return Ok(());
        }
    }
}

pub(crate) fn ready_watch(
    fd: i32, events: i16, control: i32, watched: &[i32], deadline: Instant,
) -> io::Result<()> {
    if watched.len() > 400 { return Err(error()); }
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() { return Err(error()); }
        let mut fds = Vec::with_capacity(watched.len() + 2);
        fds.push(Poll { fd, events, revents: 0 });
        fds.push(Poll { fd: control, events: INPUT, revents: 0 });
        fds.extend(watched.iter().map(|fd| Poll { fd: *fd, events: INPUT, revents: 0 }));
        let result = unsafe { poll(fds.as_mut_ptr(), fds.len(), left.as_millis().max(1).min(5000) as i32) };
        if result < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted { continue; }
        if result < 0 || fds.iter().skip(1).any(|p| p.revents != 0) || fds[0].revents & BAD != 0 { return Err(error()); }
        if fds[0].revents & events != 0 { return Ok(()); }
    }
}

pub(crate) fn read_exact<R: Read + AsRawFd>(
    input: &mut R,
    bytes: &mut [u8],
    control: Option<i32>,
    process: Option<i32>,
    deadline: Instant,
) -> io::Result<()> {
    let mut at = 0;
    while at < bytes.len() {
        ready(input.as_raw_fd(), INPUT, control, process, deadline)?;
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

pub(crate) fn nonblocking(fd: i32) -> io::Result<()> {
    let flags = unsafe { fcntl(fd, 3) };
    if flags < 0 || unsafe { fcntl(fd, 4, flags | 0x800) } < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

pub(crate) fn write_frame(output: &mut File, kind: u8, body: &[u8], deadline: Instant) -> io::Result<()> {
    let mut frame = Vec::with_capacity(5 + body.len());
    frame.push(kind);
    frame.extend_from_slice(&(body.len() as u32).to_be_bytes());
    frame.extend_from_slice(body);
    let mut offset = 0;
    while offset < frame.len() {
        ready(output.as_raw_fd(), OUTPUT, Some(0), None, deadline)?;
        match output.write(&frame[offset..]) {
            Ok(0) => return Err(error()),
            Ok(count) => offset += count,
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

fn read_control_all(input: &mut File, bytes: &mut [u8], entries: &[(u8, Expected)], deadline: Instant) -> io::Result<()> {
    let mut at = 0;
    while at < bytes.len() {
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() { return Err(error()); }
        let mut fds = vec![Poll { fd: input.as_raw_fd(), events: INPUT, revents: 0 }];
        fds.extend(entries.iter().map(|(_, item)| Poll { fd: item.process.as_raw_fd(), events: INPUT, revents: 0 }));
        let result = unsafe { poll(fds.as_mut_ptr(), fds.len(), left.as_millis().max(1).min(5000) as i32) };
        if result < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted { continue; }
        if result < 0 || fds[0].revents & BAD != 0 || fds.iter().skip(1).any(|fd| fd.revents != 0) { return Err(error()); }
        if fds[0].revents & INPUT == 0 { continue; }
        match input.read(&mut bytes[at..]) {
            Ok(0) => return Err(error()),
            Ok(n) => at += n,
            Err(e) if matches!(e.kind(), io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock) => {},
            Err(_) => return Err(error()),
        }
    }
    Ok(())
}

pub(crate) fn pidfd(pid: u32) -> io::Result<File> {
    // Linux pidfd_open has the same syscall number on x86-64 and aarch64.
    #[cfg(any(target_arch = "x86_64", target_arch = "aarch64"))]
    let fd = unsafe { syscall(434, pid, 0u32) };
    #[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
    let fd = -1;
    if fd < 0 {
        return Err(error());
    }
    Ok(unsafe { File::from_raw_fd(fd as i32) })
}

fn same_helper(pid: u32) -> io::Result<()> {
    let mine = fs::metadata("/proc/self/exe")?;
    let peer = fs::metadata(format!("/proc/{pid}/exe"))?;
    if mine.dev() != peer.dev() || mine.ino() != peer.ino() {
        return Err(error());
    }
    Ok(())
}

pub(crate) fn expected(entry: &[u8]) -> io::Result<Expected> {
    let pid = u32::from_be_bytes(entry[0..4].try_into().unwrap());
    let name: [u8; 16] = entry[4..20].try_into().unwrap();
    let secret: [u8; 32] = entry[20..52].try_into().unwrap();
    let dev = u64::from_be_bytes(entry[52..60].try_into().unwrap());
    let ino = u64::from_be_bytes(entry[60..68].try_into().unwrap());
    if pid == 0 || name.iter().all(|x| *x == 0) || secret.iter().all(|x| *x == 0) || ino == 0 {
        return Err(error());
    }
    let process = pidfd(pid)?;
    same_helper(pid)?;
    Ok(Expected {
        pid,
        name,
        secret,
        dev,
        ino,
        process,
    })
}

pub(crate) fn open_peer(
    item: &Expected,
    owner: Option<i32>,
    deadline: Instant,
) -> io::Result<UnixStream> {
    open_peer_control(item, 0, owner, deadline)
}

pub(crate) fn open_peer_control(
    item: &Expected,
    control: i32,
    owner: Option<i32>,
    deadline: Instant,
) -> io::Result<UnixStream> {
    let watched: Vec<i32> = owner.into_iter().collect();
    open_peer_watch(item, control, &watched, deadline)
}

pub(crate) fn open_peer_watch(
    item: &Expected, control: i32, watched: &[i32], deadline: Instant,
) -> io::Result<UnixStream> {
    let mut address = Address {
        family: 1,
        path: [0; 108],
    };
    address.path[1..15].copy_from_slice(b"ipse-lease-v1-");
    address.path[15..31].copy_from_slice(&item.name);
    let mut stream = loop {
        let fd = unsafe { socket(1, 1 | 0x800 | 0x80000, 0) };
        if fd < 0 {
            return Err(io::Error::last_os_error());
        }
        let stream = unsafe { UnixStream::from_raw_fd(fd) };
        let result = unsafe {
            connect(
                fd,
                (&address as *const Address).cast(),
                (size_of::<u16>() + 31) as u32,
            )
        };
        if result == 0 {
            break stream;
        }
        let cause = io::Error::last_os_error();
        if !matches!(
            cause.kind(),
            io::ErrorKind::NotFound | io::ErrorKind::ConnectionRefused | io::ErrorKind::WouldBlock
        ) {
            return Err(cause);
        }
        #[cfg(ipse_lease_export_test_hook)]
        test_marker("IPSE_TEST_COLLECT_CONNECT");
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return Err(error());
        }
        let mut fds = vec![Poll { fd: control, events: INPUT, revents: 0 },
            Poll { fd: item.process.as_raw_fd(), events: INPUT, revents: 0 }];
        fds.extend(watched.iter().map(|fd| Poll { fd: *fd, events: INPUT, revents: 0 }));
        let result = unsafe {
            poll(
                fds.as_mut_ptr(),
                fds.len(),
                left.as_millis().max(1).min(5) as i32,
            )
        };
        if result < 0 && io::Error::last_os_error().kind() != io::ErrorKind::Interrupted {
            return Err(error());
        }
        if fds.iter().any(|fd| fd.revents != 0) {
            return Err(error());
        }
    };
    let fd = stream.as_raw_fd();
    let mut peer = Peer {
        pid: 0,
        uid: 0,
        gid: 0,
    };
    let mut len = size_of::<Peer>() as u32;
    if unsafe { getsockopt(fd, 1, 17, (&mut peer as *mut Peer).cast(), &mut len) } != 0
        || len as usize != size_of::<Peer>()
        || peer.pid <= 0
        || peer.pid as u32 != item.pid
        || peer.uid != unsafe { geteuid() }
    {
        return Err(error());
    }
    same_helper(item.pid)?;
    let mut at = 0;
    while at < item.secret.len() {
        let mut guards = watched.to_vec();
        guards.push(item.process.as_raw_fd());
        ready_watch(fd, OUTPUT, control, &guards, deadline)?;
        match stream.write(&item.secret[at..]) {
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
    Ok(stream)
}

pub(crate) fn receive(
    stream: &UnixStream,
    item: &Expected,
    owner: Option<i32>,
    deadline: Instant,
) -> io::Result<File> {
    receive_control(stream, item, 0, owner, deadline)
}

pub(crate) fn receive_control(
    stream: &UnixStream,
    item: &Expected,
    control: i32,
    owner: Option<i32>,
    deadline: Instant,
) -> io::Result<File> {
    let watched: Vec<i32> = owner.into_iter().collect();
    receive_watch(stream, item, control, &watched, deadline)
}

pub(crate) fn receive_watch(
    stream: &UnixStream, item: &Expected, control: i32, watched: &[i32], deadline: Instant,
) -> io::Result<File> {
    let file = receive_raw_watch(stream, item, control, watched, deadline)?;
    let m = file.metadata()?;
    if !m.is_file()
        || m.uid() != unsafe { geteuid() }
        || m.nlink() != 1
        || m.mode() & 0o7777 != 0o600
        || m.len() != 0
        || m.dev() != item.dev
        || m.ino() != item.ino
    {
        return Err(error());
    }
    Ok(file)
}

/// Check a retained descriptor and its exporter immediately before a native
/// decision. This observes liveness and inode metadata; callers must still
/// retain the channel, enforce their own deadline and settle the transfer.
pub(crate) fn retained_live(item: &Expected, peer: &UnixStream, file: &File) -> bool {
    let Ok(metadata) = file.metadata() else { return false; };
    if !metadata.is_file() || metadata.uid() != unsafe { geteuid() } || metadata.nlink() != 1 ||
        metadata.mode() & 0o7777 != 0o600 || metadata.len() != 0 ||
        metadata.dev() != item.dev || metadata.ino() != item.ino || same_helper(item.pid).is_err() {
        return false;
    }
    let mut watched = [
        Poll { fd: peer.as_raw_fd(), events: INPUT, revents: 0 },
        Poll { fd: item.process.as_raw_fd(), events: INPUT, revents: 0 },
    ];
    unsafe { poll(watched.as_mut_ptr(), watched.len(), 0) == 0 }
}

/// A single original source description and exporter channel held by a native
/// transaction owner. It cannot grant semantic consent or publication by itself.
pub(crate) struct RetainedSource {
    item: Expected,
    peer: UnixStream,
    file: Option<File>,
    operation: [u8; 16],
    pipe: Option<Vec<u8>>,
}

impl RetainedSource {
    pub(crate) fn acquire(entry: &[u8], operation: [u8; 16], deadline: Instant) -> io::Result<Self> {
        if entry.len() != ENTRY_SIZE || operation.iter().all(|b| *b == 0) { return Err(error()); }
        let item = expected(entry)?;
        let mut peer = open_peer(&item, None, deadline)?;
        let file = receive(&peer, &item, None, deadline)?;
        ready(peer.as_raw_fd(), OUTPUT, Some(0), Some(item.process.as_raw_fd()), deadline)?;
        peer.write_all(b"A")?;
        if !retained_live(&item, &peer, &file) { return Err(error()); }
        Ok(Self { item, peer, file: Some(file), operation, pipe: None })
    }

    pub(crate) fn acquire_pipe(
        entry: &[u8], operation: [u8; 16], expiry: u64, payload: &[u8], watched: &[i32], deadline: Instant,
    ) -> io::Result<Self> {
        if entry.len() != ENTRY_SIZE || operation.iter().all(|b| *b == 0) ||
            payload.is_empty() || payload.len() > 32_772 { return Err(error()); }
        let item = expected(entry)?;
        let mut peer = open_peer_watch(&item, 0, watched, deadline)?;
        let mut binding = operation.to_vec();
        binding.extend_from_slice(&expiry.to_be_bytes());
        binding.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        binding.extend_from_slice(payload);
        let mut guards = watched.to_vec();
        guards.push(item.process.as_raw_fd());
        let mut sent = 0;
        while sent < binding.len() {
            ready_watch(peer.as_raw_fd(), OUTPUT, 0, &guards, deadline)?;
            match peer.write(&binding[sent..]) {
                Ok(0) => return Err(error()),
                Ok(n) => sent += n,
                Err(e) if matches!(e.kind(), io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock) => (),
                Err(e) => return Err(e),
            }
        }
        let file = receive_raw_watch(&peer, &item, 0, watched, deadline)?;
        if !super::ipse_lease_transfer::pipe_identity(&file, unsafe { geteuid() }) {
            return Err(error());
        }
        let metadata = file.metadata()?;
        if (metadata.dev(), metadata.ino()) != (item.dev, item.ino) { return Err(error()); }
        ready_watch(peer.as_raw_fd(), OUTPUT, 0, &guards, deadline)?;
        peer.write_all(b"A")?;
        let retained = Self { item, peer, file: Some(file), operation, pipe: Some(payload.to_vec()) };
        if !retained.live() { return Err(error()); }
        Ok(retained)
    }

    pub(crate) fn live(&self) -> bool {
        self.file.as_ref().is_some_and(|file| {
            if self.pipe.is_none() { return retained_live(&self.item, &self.peer, file); }
            let Ok(metadata) = file.metadata() else { return false; };
            if !super::ipse_lease_transfer::pipe_identity(file, unsafe { geteuid() }) ||
                (metadata.dev(), metadata.ino()) != (self.item.dev, self.item.ino) ||
                same_helper(self.item.pid).is_err() { return false; }
            let mut fds = [Poll { fd: self.peer.as_raw_fd(), events: INPUT, revents: 0 },
                Poll { fd: self.item.process.as_raw_fd(), events: INPUT, revents: 0 }];
            unsafe { poll(fds.as_mut_ptr(), fds.len(), 0) == 0 }
        })
    }

    /// One exact bounded frame under the importing controller's live owners.
    /// The controller consumes the operation before entering this method.
    /// A partial write or failed final check is always an unknown effect.
    pub(crate) fn write_pipe<F: Fn() -> bool>(
        &mut self, bytes: &[u8], expiry: u64, deadline: Instant, valid: F,
    ) -> io::Result<()> {
        use std::time::{SystemTime, UNIX_EPOCH};
        if self.pipe.as_deref() != Some(bytes) || bytes.is_empty() || bytes.len() > 32_772 ||
            expiry == 0 || expiry > 9_007_199_254_740_991 { return Err(error()); }
        let mut offset = 0;
        while offset < bytes.len() {
            let current = || SystemTime::now().duration_since(UNIX_EPOCH)
                .is_ok_and(|n| n.as_millis() < u128::from(expiry));
            if Instant::now() >= deadline || !current() || !valid() || !self.live() ||
                !super::ipse_lease_transfer::control_quiet(0) { return Err(error()); }
            let file = self.file.as_mut().ok_or_else(error)?;
            match file.write(&bytes[offset..(offset + 4096).min(bytes.len())]) {
                Ok(0) => return Err(error()),
                Ok(n) => offset += n,
                Err(e) if e.kind() == io::ErrorKind::Interrupted => (),
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                    // A bounded wait never hides owner loss or renews a deadline.
                    let mut p = Poll { fd: file.as_raw_fd(), events: OUTPUT, revents: 0 };
                    let rc = unsafe { poll(&mut p, 1, 5) };
                    if rc < 0 && io::Error::last_os_error().kind() != io::ErrorKind::Interrupted ||
                        p.revents & BAD != 0 { return Err(error()); }
                },
                Err(e) => return Err(e),
            }
        }
        if Instant::now() >= deadline || !valid() || !self.live() ||
            !super::ipse_lease_transfer::control_quiet(0) ||
            !SystemTime::now().duration_since(UNIX_EPOCH)
                .is_ok_and(|n| n.as_millis() < u128::from(expiry)) { return Err(error()); }
        Ok(())
    }

    /// Drop this owner's description before the exporter settles. A caller
    /// must concurrently request settlement from the original source owner.
    pub(crate) fn close(mut self, operation: &[u8; 16], deadline: Instant) -> io::Result<()> {
        if operation != &self.operation || !self.live() { return Err(error()); }
        drop(self.file.take());
        let mut receipt = [0_u8; 18];
        receipt[0] = b'C'; receipt[1..17].copy_from_slice(operation); receipt[17] = 0;
        ready(self.peer.as_raw_fd(), OUTPUT, Some(0), Some(self.item.process.as_raw_fd()), deadline)?;
        self.peer.write_all(&receipt)?;
        read_exact(&mut self.peer, &mut receipt, Some(0), Some(self.item.process.as_raw_fd()), deadline)?;
        if receipt[0] != b'F' || receipt[1..17] != *operation || receipt[17] != 0 { return Err(error()); }
        receipt[0] = b'G';
        ready(self.peer.as_raw_fd(), OUTPUT, Some(0), Some(self.item.process.as_raw_fd()), deadline)?;
        self.peer.write_all(&receipt)?;
        loop {
            let left = deadline.saturating_duration_since(Instant::now());
            if left.is_zero() { return Err(error()); }
            let mut fds = [Poll { fd: self.peer.as_raw_fd(), events: INPUT, revents: 0 },
                Poll { fd: 0, events: INPUT, revents: 0 },
                Poll { fd: self.item.process.as_raw_fd(), events: INPUT, revents: 0 }];
            let rc = unsafe { poll(fds.as_mut_ptr(), fds.len(), left.as_millis().max(1).min(5000) as i32) };
            if rc < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted { continue; }
            if rc < 0 || fds[1].revents != 0 || fds[2].revents != 0 || fds[0].revents & (8 | 32) != 0 { return Err(error()); }
            if fds[0].revents & (INPUT | 16) == 0 { continue; }
            let mut byte = [0_u8; 1];
            match self.peer.read(&mut byte) {
                Ok(0) => return Ok(()),
                Err(e) if matches!(e.kind(), io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock) => {},
                _ => return Err(error()),
            }
        }
    }
}

#[cfg(test)]
mod retained_live_tests {
    use super::*;
    use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};

    #[test]
    fn observes_retained_inode_and_quiet_exporter_channel() {
        let path = std::env::temp_dir().join(format!("ipse-source-check-{}", std::process::id()));
        let file = fs::OpenOptions::new().read(true).write(true).create_new(true).mode(0o600).open(&path).unwrap();
        let metadata = file.metadata().unwrap();
        let (peer, mut exporter) = UnixStream::pair().unwrap();
        let item = Expected { pid: std::process::id(), name: [1; 16], secret: [2; 32], dev: metadata.dev(), ino: metadata.ino(), process: pidfd(std::process::id()).unwrap() };
        assert!(retained_live(&item, &peer, &file));
        fs::set_permissions(&path, fs::Permissions::from_mode(0o644)).unwrap();
        assert!(!retained_live(&item, &peer, &file));
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).unwrap();
        assert!(retained_live(&item, &peer, &file));
        exporter.write_all(b"unexpected").unwrap();
        assert!(!retained_live(&item, &peer, &file));
        drop(exporter); drop(peer); drop(file);
        fs::remove_file(path).unwrap();
    }
}

pub(crate) fn receive_raw(
    stream: &UnixStream,
    item: &Expected,
    owner: Option<i32>,
    deadline: Instant,
) -> io::Result<File> {
    receive_raw_control(stream, item, 0, owner, deadline)
}

pub(crate) fn receive_raw_control(
    stream: &UnixStream,
    item: &Expected,
    control: i32,
    owner: Option<i32>,
    deadline: Instant,
) -> io::Result<File> {
    let watched: Vec<i32> = owner.into_iter().collect();
    receive_raw_watch(stream, item, control, &watched, deadline)
}

pub(crate) fn receive_raw_watch(
    stream: &UnixStream, item: &Expected, control: i32, watched: &[i32], deadline: Instant,
) -> io::Result<File> {
    let mut guards = watched.to_vec();
    guards.push(item.process.as_raw_fd());
    ready_watch(stream.as_raw_fd(), INPUT, control, &guards, deadline)?;
    let mut byte = [0u8];
    let mut iov = IoVec {
        base: byte.as_mut_ptr().cast(),
        len: 1,
    };
    let mut control = Control([0; 4096]);
    let mut message = Message {
        name: std::ptr::null_mut(),
        name_len: 0,
        iov: &mut iov,
        iov_len: 1,
        control: control.0.as_mut_ptr().cast(),
        control_len: control.0.len(),
        flags: 0,
    };
    let result = unsafe { recvmsg(stream.as_raw_fd(), &mut message, 0x4000_0000) };
    let mut files = Vec::new();
    let mut offset = 0usize;
    let mut valid = true;
    while offset + size_of::<Header>() <= message.control_len {
        let header = unsafe { &*(control.0.as_ptr().add(offset).cast::<Header>()) };
        if header.len < size_of::<Header>() || header.len > message.control_len - offset {
            valid = false;
            break;
        }
        let count = header.len - size_of::<Header>();
        if header.level == 1 && header.kind == 1 && count % size_of::<i32>() == 0 {
            for index in 0..count / size_of::<i32>() {
                let ptr = unsafe {
                    control
                        .0
                        .as_ptr()
                        .add(offset + size_of::<Header>() + index * size_of::<i32>())
                };
                let fd = unsafe { std::ptr::read_unaligned(ptr.cast::<i32>()) };
                if fd < 0 {
                    valid = false;
                } else {
                    files.push(unsafe { File::from_raw_fd(fd) });
                }
            }
        } else {
            valid = false;
        }
        offset += (header.len + size_of::<usize>() - 1) & !(size_of::<usize>() - 1);
    }
    if result != 1 || byte != [b'L'] || message.flags & 8 != 0 || !valid || files.len() != 1 {
        return Err(error());
    }
    let file = files.pop().unwrap();
    let flags = unsafe { fcntl(file.as_raw_fd(), 1) };
    if flags < 0 || flags & 1 == 0 {
        return Err(error());
    }
    Ok(file)
}

pub(crate) fn run(args: &[String]) -> Result<(), String> {
    if args.len() != 2 {
        return Err("invalid lease collector arguments".into());
    }
    nonblocking(0).map_err(|_| "lease collector unavailable")?;
    nonblocking(1).map_err(|_| "lease collector output unavailable")?;
    // Read the descriptor directly: Stdin's buffered reader can prefetch the
    // body, leaving poll unable to observe those already buffered bytes.
    let mut input = unsafe { File::from_raw_fd(0) };
    // The top-level helper owns stdout and may report a refusal after return.
    let mut output = std::mem::ManuallyDrop::new(unsafe { File::from_raw_fd(1) });
    let setup_deadline = Instant::now() + Duration::from_secs(5);
    let mut header = [0u8; 5];
    read_exact(&mut input, &mut header, None, None, setup_deadline)
        .map_err(|_| "lease collector request unavailable")?;
    let len = u32::from_be_bytes(header[1..].try_into().unwrap()) as usize;
    if header[0] != b'I' || len < 9 || len > 9 + ENTRY_SIZE * MAX_LEASES {
        return Err("invalid lease collector request".into());
    }
    let mut body = vec![0; len];
    read_exact(&mut input, &mut body, None, None, setup_deadline)
        .map_err(|_| "lease collector request unavailable")?;
    let ms = u64::from_be_bytes(body[..8].try_into().unwrap());
    let count = body[8] as usize;
    if !(1..=30_000).contains(&ms)
        || count == 0
        || count > MAX_LEASES
        || len != 9 + count * ENTRY_SIZE
    {
        return Err("invalid lease collector request".into());
    }
    let deadline = Instant::now() + Duration::from_millis(ms);
    let mut expected_items = Vec::new();
    for entry in body[9..].chunks_exact(ENTRY_SIZE) {
        let item = expected(entry).map_err(|_| "lease helper unavailable")?;
        if expected_items
            .iter()
            .any(|old: &Expected| old.dev == item.dev && old.ino == item.ino)
        {
            return Err("duplicate lease identity".into());
        }
        expected_items.push(item);
    }
    let mut leases = Vec::new();
    let mut peers = Vec::new();
    for item in &expected_items {
        let mut peer = open_peer(item, None, deadline).map_err(|_| "lease helper unavailable")?;
        let file =
            receive(&peer, item, None, deadline).map_err(|_| "lease descriptor unavailable")?;
        ready(
            peer.as_raw_fd(),
            OUTPUT,
            Some(0),
            Some(item.process.as_raw_fd()),
            deadline,
        )
        .map_err(|_| "lease acknowledgment unavailable")?;
        peer.write_all(b"A")
            .map_err(|_| "lease acknowledgment unavailable")?;
        leases.push(file);
        peers.push(peer);
    }
    // This is a collection observation only; process death can still race the
    // following response and must be fenced separately before any future use.
    if Instant::now() >= deadline {
        return Err("lease collection expired".into());
    }
    let mut live = vec![Poll {
        fd: 0,
        events: INPUT,
        revents: 0,
    }];
    live.extend(expected_items.iter().map(|item| Poll {
        fd: item.process.as_raw_fd(),
        events: INPUT,
        revents: 0,
    }));
    if unsafe { poll(live.as_mut_ptr(), live.len(), 0) } != 0 {
        return Err("lease collection lost its owner or helper".into());
    }
    #[cfg(ipse_lease_export_test_hook)]
    test_marker("IPSE_TEST_COLLECT_WRITE");
    write_frame(&mut output, b'L', &[count as u8], deadline)
        .map_err(|_| "lease collector output unavailable")?;
    let mut close = [0u8; 1];
    read_exact(&mut input, &mut close, None, None, deadline)
        .map_err(|_| "lease collector close unavailable")?;
    if close != [b'C'] {
        return Err("invalid lease collector close".into());
    }
    drop(leases);
    drop(peers);
    write_frame(&mut output, b'C', &[count as u8], deadline)
        .map_err(|_| "lease collector output unavailable")?;
    Ok(())
}

/// Inert, management-sized retained-channel collector. This private mode has
/// no tty or payload operation. Its closed receipt is meaningful only for this
/// collector's own FD table; it does not qualify the forked operator guardian.
pub(crate) fn run_close(args: &[String], readiness: bool, accepted: bool) -> Result<(), String> {
    if args.len() != 2 { return Err("invalid retained collector arguments".into()); }
    nonblocking(0).map_err(|_| "retained collector unavailable")?;
    nonblocking(1).map_err(|_| "retained collector unavailable")?;
    let mut input = unsafe { File::from_raw_fd(0) };
    let mut output = std::mem::ManuallyDrop::new(unsafe { File::from_raw_fd(1) });
    let started = Instant::now();
    let setup_deadline = started + Duration::from_secs(5);
    let mut header = [0_u8; 5];
    read_exact(&mut input, &mut header, None, None, setup_deadline).map_err(|_| "retained collector request unavailable")?;
    let length = u32::from_be_bytes(header[1..].try_into().unwrap()) as usize;
    let maximum = if accepted { 5 } else { 4 };
    if header[0] != b'I' || !(25 + 69..=25 + 69 * maximum).contains(&length) { return Err("invalid retained collector request".into()); }
    let mut body = vec![0_u8; length];
    read_exact(&mut input, &mut body, None, None, setup_deadline).map_err(|_| "retained collector request unavailable")?;
    let ms = u64::from_be_bytes(body[..8].try_into().unwrap());
    let operation: [u8; 16] = body[8..24].try_into().unwrap();
    let count = body[24] as usize;
    if !(1..=120_000).contains(&ms) || operation.iter().all(|b| *b == 0) || !(1..=maximum).contains(&count) || (accepted && count != 5) || length != 25 + count * 69 {
        return Err("invalid retained collector request".into());
    }
    let deadline = started + Duration::from_millis(ms);
    let collection_deadline = deadline.min(setup_deadline);
    let mut entries = Vec::new();
    for entry in body[25..].chunks_exact(69) {
        let slot = entry[0];
        if slot > 2 { return Err("invalid retained collector slot".into()); }
        let item = expected(&entry[1..]).map_err(|_| "retained collector peer unavailable")?;
        if entries.iter().any(|(old_slot, old): &(u8, Expected)|
            (old.dev == item.dev && old.ino == item.ino) || old.name == item.name || old.secret == item.secret ||
            (*old_slot == slot && old.pid == item.pid)) { return Err("duplicate retained collector entry".into()); }
        entries.push((slot, item));
    }
    if accepted && entries.iter().map(|(slot, _)| *slot).collect::<Vec<_>>() != [0, 1, 2, 0, 0] {
        return Err("invalid accepted collector slots".into());
    }
    if readiness {
        let mut ready_body = operation.to_vec(); ready_body.push(count as u8);
        write_frame(&mut output, b'H', &ready_body, collection_deadline).map_err(|_| "retained collector readiness unavailable")?;
    }
    let mut leases = Vec::new();
    let mut peers = Vec::new();
    for (_, item) in &entries {
        let mut peer = open_peer(item, None, collection_deadline).map_err(|_| "retained collector peer unavailable")?;
        let lease = receive(&peer, item, None, collection_deadline).map_err(|_| "retained collector descriptor unavailable")?;
        ready(peer.as_raw_fd(), OUTPUT, Some(0), Some(item.process.as_raw_fd()), collection_deadline).map_err(|_| "retained collector ack unavailable")?;
        peer.write_all(b"A").map_err(|_| "retained collector ack unavailable")?;
        leases.push(lease);
        peers.push(peer);
    }
    let mut live = vec![Poll { fd: 0, events: INPUT, revents: 0 }];
    live.extend(entries.iter().map(|(_, item)| Poll { fd: item.process.as_raw_fd(), events: INPUT, revents: 0 }));
    if unsafe { poll(live.as_mut_ptr(), live.len(), 0) } != 0 ||
        !entries.iter().zip(peers.iter()).zip(leases.iter())
            .all(|(((_, item), peer), lease)| retained_live(item, peer, lease)) {
        return Err("retained collector lost an owner".into());
    }
    let mut collected = operation.to_vec(); collected.push(count as u8);
    write_frame(&mut output, b'L', &collected, collection_deadline).map_err(|_| "retained collector reply unavailable")?;
    let mut close = [0_u8; 17];
    read_control_all(&mut input, &mut close, &entries, deadline).map_err(|_| "retained collector close unavailable")?;
    if close[0] != b'C' || close[1..] != operation { return Err("invalid retained collector close".into()); }
    // This process has never forked or passed these FDs onward. Drop every
    // description before sending any per-slot close message.
    drop(leases);
    for (index, (slot, item)) in entries.iter().enumerate() {
        let mut receipt = [0_u8; 18]; receipt[0] = b'C'; receipt[1..17].copy_from_slice(&operation); receipt[17] = *slot;
        let peer = &mut peers[index];
        let mut at = 0;
        while at < receipt.len() {
            ready(peer.as_raw_fd(), OUTPUT, Some(0), Some(item.process.as_raw_fd()), deadline).map_err(|_| "retained collector close unavailable")?;
            match peer.write(&receipt[at..]) {
                Ok(0) => return Err("retained collector close unavailable".into()),
                Ok(n) => at += n,
                Err(e) if matches!(e.kind(), io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock) => {},
                Err(_) => return Err("retained collector close unavailable".into()),
            }
        }
    }
    for (index, (slot, item)) in entries.iter().enumerate() {
        let mut ack = [0_u8; 18];
        read_exact(&mut peers[index], &mut ack, Some(0), Some(item.process.as_raw_fd()), deadline).map_err(|_| "retained collector settlement unavailable")?;
        if ack[0] != b'F' || ack[1..17] != operation || ack[17] != *slot { return Err("invalid retained collector settlement".into()); }
        ack[0] = b'G';
        let peer = &mut peers[index];
        let mut at = 0;
        while at < ack.len() {
            ready(peer.as_raw_fd(), OUTPUT, Some(0), Some(item.process.as_raw_fd()), deadline).map_err(|_| "retained collector final ack unavailable")?;
            match peer.write(&ack[at..]) {
                Ok(0) => return Err("retained collector final ack unavailable".into()),
                Ok(n) => at += n,
                Err(e) if matches!(e.kind(), io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock) => {},
                Err(_) => return Err("retained collector final ack unavailable".into()),
            }
        }
        // Keep the socket alive until the exporter consumes G and closes its
        // endpoint. This avoids mistaking an ACK queued alongside HUP for a
        // confirmed close at either end.
        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() { return Err("retained collector peer close unavailable".into()); }
            let mut fds = [Poll { fd: peer.as_raw_fd(), events: INPUT, revents: 0 }, Poll { fd: 0, events: INPUT, revents: 0 }, Poll { fd: item.process.as_raw_fd(), events: INPUT, revents: 0 }];
            let result = unsafe { poll(fds.as_mut_ptr(), fds.len(), remaining.as_millis().max(1).min(5000) as i32) };
            if result < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted { continue; }
            if result < 0 || fds[1].revents != 0 || fds[2].revents != 0 || fds[0].revents & (8 | 32) != 0 { return Err("retained collector peer close unavailable".into()); }
            if fds[0].revents & (INPUT | 16) == 0 { continue; }
            let mut extra = [0_u8; 1];
            match peer.read(&mut extra) {
                Ok(0) => break,
                Ok(_) => return Err("invalid retained collector trailing data".into()),
                Err(e) if matches!(e.kind(), io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock) => {},
                Err(_) => return Err("retained collector peer close unavailable".into()),
            }
        }
    }
    drop(peers);
    write_frame(&mut output, b'C', &collected, deadline).map_err(|_| "retained collector completion unavailable")?;
    Ok(())
}
