//! Matching terminal observations; descriptor 3/4 pipes never carry operator input.
#[cfg(any(target_os = "linux", target_os = "macos"))]
mod unix {
    use std::ffi::{CStr, OsStr};
    use std::fs::{File, OpenOptions, DirBuilder};
    use std::io::{Read, Write};
    use std::os::fd::{BorrowedFd, AsRawFd};
    use std::os::unix::ffi::OsStrExt;
    use std::os::unix::fs::{MetadataExt, FileTypeExt, OpenOptionsExt, DirBuilderExt};
    use std::time::{Duration, Instant};
    #[repr(C)]
    struct Poll { fd: i32, events: i16, revents: i16 }
    #[cfg(target_os = "linux")]
    type Count = usize;
    #[cfg(target_os = "macos")]
    type Count = u32;
    extern "C" {
        fn isatty(fd: i32) -> i32;
        fn poll(fds: *mut Poll, count: Count, timeout: i32) -> i32;
        fn tcflush(fd: i32, selector: i32) -> i32;
        fn ttyname_r(fd: i32, name: *mut std::ffi::c_char, size: usize) -> i32;
        fn fcntl(fd: i32, command: i32, ...) -> i32;
        fn flock(fd: i32, operation: i32) -> i32;
        fn geteuid() -> u32;
    }
    #[cfg(target_os = "linux")]
    const NONBLOCK: i32 = 0x800;
    #[cfg(target_os = "macos")]
    const NONBLOCK: i32 = 0x4;
    #[cfg(target_os = "linux")]
    const TTY_FLAGS: i32 = NONBLOCK | 0x20000 | 0x100;
    #[cfg(target_os = "macos")]
    const TTY_FLAGS: i32 = NONBLOCK | 0x100 | 0x20000;
    #[cfg(target_os = "linux")]
    const INPUT_QUEUE: i32 = 0;
    #[cfg(target_os = "macos")]
    const INPUT_QUEUE: i32 = 1;
    const LIMIT: usize = 8192;
    enum Failure { Cancelled, Refused(&'static str) }
    type Result<T> = std::result::Result<T, Failure>;

    fn fd(n: i32) -> Result<File> {
        let owned = unsafe { BorrowedFd::borrow_raw(n) }.try_clone_to_owned()
            .map_err(|_| Failure::Refused("operator descriptor unavailable"))?;
        Ok(File::from(owned))
    }
    fn nonblocking(file: &File) -> Result<()> {
        let flags = unsafe { fcntl(file.as_raw_fd(), 3) };
        if flags < 0 || unsafe { fcntl(file.as_raw_fd(), 4, flags | NONBLOCK) } < 0 {
            return Err(Failure::Refused("cannot bound operator control IO"));
        }
        Ok(())
    }
    fn terminal() -> Result<File> {
        let input = fd(0)?; let display = fd(1)?;
        let a = input.metadata().map_err(|_| Failure::Refused("operator input identity unavailable"))?;
        let b = display.metadata().map_err(|_| Failure::Refused("operator display identity unavailable"))?;
        let identity = |m: &std::fs::Metadata| (m.dev(), m.ino(), m.rdev());
        if unsafe { isatty(0) } != 1 || unsafe { isatty(1) } != 1 || identity(&a) != identity(&b) {
            return Err(Failure::Refused("matching actual input/display terminal required"));
        }
        let mut name = [0 as std::ffi::c_char; 4096];
        if unsafe { ttyname_r(0, name.as_mut_ptr(), name.len()) } != 0 {
            return Err(Failure::Refused("operator terminal path unavailable"));
        }
        let path = OsStr::from_bytes(unsafe { CStr::from_ptr(name.as_ptr()) }.to_bytes());
        // A fresh open description avoids changing the parent's stdout flags.
        // NOCTTY keeps this detached helper from acquiring a controlling terminal.
        let tty = OpenOptions::new().read(true).write(true).custom_flags(TTY_FLAGS).open(path)
            .map_err(|_| Failure::Refused("cannot open bounded operator terminal"))?;
        let m = tty.metadata().map_err(|_| Failure::Refused("operator terminal identity unavailable"))?;
        if unsafe { isatty(tty.as_raw_fd()) } != 1 || identity(&a) != identity(&m) {
            return Err(Failure::Refused("operator terminal identity changed"));
        }
        Ok(tty)
    }
    fn channel_lock() -> Result<File> {
        let fail = |_| Failure::Refused("operator channel lock unavailable");
        let root = std::fs::canonicalize("/tmp").map_err(fail)?;
        let metadata = std::fs::symlink_metadata(&root).map_err(fail)?;
        if !metadata.is_dir() || metadata.uid() != 0 || metadata.mode() & 0o1002 != 0o1002 {
            return Err(Failure::Refused("protected temporary root required"));
        }
        let uid = unsafe { geteuid() };
        let directory = root.join(format!("ipse-operator-{uid}"));
        match DirBuilder::new().mode(0o700).create(&directory) {
            Ok(()) => {},
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {},
            Err(_) => return Err(Failure::Refused("cannot create private operator lock directory")),
        }
        let d = std::fs::symlink_metadata(&directory).map_err(fail)?;
        if !d.is_dir() || d.uid() != uid || d.mode() & 0o077 != 0 ||
            std::fs::canonicalize(&directory).map_err(fail)? != directory {
            return Err(Failure::Refused("unsafe operator lock directory"));
        }
        let path = directory.join("input.lock");
        // NONBLOCK also prevents a substituted FIFO from blocking before validation.
        #[cfg(target_os = "linux")]
        let flags = NONBLOCK | 0x20000;
        #[cfg(target_os = "macos")]
        let flags = NONBLOCK | 0x100;
        let lock = OpenOptions::new().read(true).write(true).create(true).mode(0o600)
            .custom_flags(flags).open(&path).map_err(fail)?;
        let m = lock.metadata().map_err(fail)?;
        let p = std::fs::symlink_metadata(&path).map_err(fail)?;
        if !m.is_file() || m.uid() != uid || m.nlink() != 1 || m.mode() & 0o077 != 0 || m.len() != 0 ||
            (m.dev(), m.ino()) != (p.dev(), p.ino()) || unsafe { flock(lock.as_raw_fd(), 2 | 4) } != 0 {
            return Err(Failure::Refused("operator channel busy or unsafe lock"));
        }
        let current = std::fs::symlink_metadata(&path).map_err(fail)?;
        let current_directory = std::fs::symlink_metadata(&directory).map_err(fail)?;
        if !current.is_file() || current.uid() != uid || current.nlink() != 1 || current.mode() & 0o077 != 0 ||
            (current.dev(), current.ino()) != (m.dev(), m.ino()) ||
            (current_directory.dev(), current_directory.ino()) != (d.dev(), d.ino()) ||
            current_directory.uid() != uid || current_directory.mode() & 0o077 != 0 {
            return Err(Failure::Refused("operator channel lock identity changed"));
        }
        Ok(lock)
    }
    fn wait(control: &File, target: &File, event: i16, deadline: Instant, reading_control: bool) -> Result<()> {
        loop {
            let left = deadline.saturating_duration_since(Instant::now()).as_millis();
            if left == 0 { return Err(Failure::Cancelled); }
            let mut fds = [Poll { fd: control.as_raw_fd(), events: 1, revents: 0 },
                Poll { fd: target.as_raw_fd(), events: event, revents: 0 }];
            let ready = unsafe { poll(fds.as_mut_ptr(), fds.len() as Count, left.min(1000) as i32) };
            if ready < 0 {
                if std::io::Error::last_os_error().kind() == std::io::ErrorKind::Interrupted { continue; }
                return Err(Failure::Refused("operator IO poll failed"));
            }
            if fds[0].revents & (8 | 16 | 32) != 0 || (!reading_control && fds[0].revents != 0) {
                return Err(Failure::Cancelled);
            }
            if fds[1].revents & (8 | 16 | 32) != 0 { return Err(Failure::Cancelled); }
            if fds[1].revents & event != 0 { return Ok(()); }
        }
    }
    fn read_exact(control: &mut File, bytes: &mut [u8], deadline: Instant) -> Result<()> {
        let mut at = 0;
        while at < bytes.len() {
            wait(control, control, 1, deadline, true)?;
            match control.read(&mut bytes[at..]) {
                Ok(0) => return Err(Failure::Cancelled),
                Ok(n) => at += n,
                Err(e) if matches!(e.kind(), std::io::ErrorKind::Interrupted | std::io::ErrorKind::WouldBlock) => {},
                Err(_) => return Err(Failure::Refused("operator request read failed")),
            }
        }
        Ok(())
    }
    fn write(control: &File, output: &mut File, bytes: &[u8], deadline: Instant) -> Result<()> {
        let mut at = 0;
        while at < bytes.len() {
            wait(control, output, 4, deadline, false)?;
            let end = (at + 4096).min(bytes.len());
            match output.write(&bytes[at..end]) {
                Ok(0) => return Err(Failure::Cancelled),
                Ok(n) => at += n,
                Err(e) if matches!(e.kind(), std::io::ErrorKind::Interrupted | std::io::ErrorKind::WouldBlock) => {},
                Err(_) => return Err(Failure::Refused("operator output failed")),
            }
        }
        Ok(())
    }
    fn bytes(kind: u8, body: &[u8]) -> Vec<u8> {
        let mut result = vec![kind]; result.extend_from_slice(&(body.len() as u32).to_be_bytes());
        result.extend_from_slice(body); result
    }
    fn display_request(control: &mut File, deadline: Instant) -> Result<([u8; 16], Vec<u8>)> {
        let mut header = [0; 5]; read_exact(control, &mut header, deadline)?;
        let count = u32::from_be_bytes(header[1..5].try_into().unwrap()) as usize;
        if header[0] != b'D' || !(17..=LIMIT + 16).contains(&count) {
            return Err(Failure::Refused("invalid operator display request"));
        }
        let mut body = vec![0; count]; read_exact(control, &mut body, deadline)?;
        // Minimum native filtering; the host must apply its full Unicode escape policy.
        if !std::str::from_utf8(&body[16..]).is_ok_and(|s|
            s.chars().all(|c| !c.is_control() || c == '\n' || c == '\t')) {
            return Err(Failure::Refused("operator display contains control characters"));
        }
        Ok((body[..16].try_into().unwrap(), body[16..].to_vec()))
    }
    fn input(control: &File, tty: &mut File, output: &mut File, nonce: &[u8; 16], deadline: Instant) -> Result<()> {
        let mut text = Vec::new();
        loop {
            wait(control, tty, 1, deadline, false)?;
            let mut byte = [0; 1];
            match tty.read(&mut byte) {
                Ok(0) => return Err(Failure::Cancelled),
                Ok(_) if byte[0] == b'\n' => {
                    if text.last() == Some(&b'\r') { text.pop(); }
                    if std::str::from_utf8(&text).is_err() { return Err(Failure::Refused("invalid operator input UTF-8")); }
                    let mut response = nonce.to_vec(); response.extend_from_slice(&text);
                    return write(control, output, &bytes(b'I', &response), deadline);
                }
                Ok(_) if text.len() < LIMIT => text.push(byte[0]),
                Ok(_) => return Err(Failure::Refused("operator line exceeds bound")),
                Err(e) if matches!(e.kind(), std::io::ErrorKind::Interrupted | std::io::ErrorKind::WouldBlock) => {},
                Err(_) => return Err(Failure::Refused("operator terminal input lost")),
            }
        }
    }
    pub fn run(args: &[String]) -> std::result::Result<(), String> {
        let mut output = fd(4).map_err(|_| "private operator output unavailable")?;
        if !output.metadata().map_err(|_| "private operator output unavailable")?.file_type().is_fifo() {
            return Err("private operator output pipe required".into());
        }
        nonblocking(&output).map_err(|_| "cannot bound operator output")?;
        let mut nonce = None;
        let result = (|| {
            if args.len() != 3 { return Err(Failure::Refused("usage: --operator-input TIMEOUT_MS")); }
            let ms: u64 = args[2].parse().ok().filter(|n| (1000..=600_000).contains(n))
                .ok_or(Failure::Refused("invalid operator input deadline"))?;
            let deadline = Instant::now() + Duration::from_millis(ms);
            let mut control = fd(3)?;
            if !control.metadata().map_err(|_| Failure::Refused("operator control unavailable"))?.file_type().is_fifo()
                || !output.metadata().map_err(|_| Failure::Refused("operator control unavailable"))?.file_type().is_fifo() {
                return Err(Failure::Refused("private operator control pipes required"));
            }
            nonblocking(&control)?;
            let mut tty = terminal()?;
            let _channel_lock = channel_lock()?;
            let (token, body) = display_request(&mut control, deadline)?; nonce = Some(token);
            if unsafe { tcflush(tty.as_raw_fd(), INPUT_QUEUE) } != 0 {
                return Err(Failure::Refused("cannot clear prior terminal input"));
            }
            let result = (|| {
                write(&control, &mut tty, &body, deadline)?;
                write(&control, &mut output, &bytes(b'Y', &token), deadline)?;
                input(&control, &mut tty, &mut output, &token, deadline)
            })();
            if unsafe { tcflush(tty.as_raw_fd(), INPUT_QUEUE) } != 0 {
                return Err(Failure::Refused("cannot invalidate terminal input"));
            }
            result
        })();
        let response = match result {
            Ok(()) => return Ok(()),
            Err(Failure::Cancelled) => bytes(b'C', &nonce.unwrap_or([0; 16])),
            Err(Failure::Refused(reason)) => bytes(b'E', reason.as_bytes()),
        };
        // Cancellation/error receipts are one small atomic, nonblocking pipe write.
        // A lost receipt never keeps the helper alive or reaches the human display.
        let _ = output.write(&response);
        Ok(())
    }
}
#[cfg(any(target_os = "linux", target_os = "macos"))]
pub use unix::run;
#[cfg(not(any(target_os = "linux", target_os = "macos")))]
pub fn run(_args: &[String]) -> Result<(), String> { Err("operator terminal requires Linux or macOS".into()) }

#[cfg(all(test, any(target_os = "linux", target_os = "macos")))]
mod tests {
    use super::run;
    use std::fs::{File, OpenOptions};
    use std::ffi::{CStr, OsStr};
    use std::io::{Read, Write};
    use std::os::fd::{AsRawFd, FromRawFd};
    use std::os::unix::process::CommandExt;
    use std::os::unix::ffi::OsStrExt;
    use std::os::unix::fs::OpenOptionsExt;
    use std::process::{Child, Command, Stdio};
    use std::sync::{Mutex, MutexGuard};
    use std::time::{Duration, Instant};
    #[repr(C)]
    struct Poll { fd: i32, events: i16, revents: i16 }
    #[cfg(target_os = "linux")]
    type Count = usize;
    #[cfg(target_os = "macos")]
    type Count = u32;
    extern "C" {
        fn posix_openpt(flags: i32) -> i32;
        fn grantpt(fd: i32) -> i32;
        fn unlockpt(fd: i32) -> i32;
        fn ptsname(fd: i32) -> *mut std::ffi::c_char;
        #[cfg(target_os = "macos")]
        fn pipe(fds: *mut i32) -> i32;
        #[cfg(target_os = "linux")]
        fn pipe2(fds: *mut i32, flags: i32) -> i32;
        fn dup2(old: i32, new: i32) -> i32;
        fn fcntl(fd: i32, op: i32, ...) -> i32;
        fn poll(fds: *mut Poll, count: Count, timeout: i32) -> i32;
        fn tcgetattr(fd: i32, value: *mut std::ffi::c_void) -> i32;
        fn tcsetattr(fd: i32, mode: i32, value: *const std::ffi::c_void) -> i32;
        fn cfmakeraw(value: *mut std::ffi::c_void);
        fn kill(pid: i32, signal: i32) -> i32;
        fn waitpid(pid: i32, status: *mut i32, options: i32) -> i32;
    }
    const NONCE: [u8; 16] = [71; 16];
    static PROBES: Mutex<()> = Mutex::new(());
    fn own(fd: i32) -> File {
        assert!(fd >= 0);
        assert_eq!(unsafe { fcntl(fd, 2, 1) }, 0);
        unsafe { File::from_raw_fd(fd) }
    }
    fn pipes() -> (File, File) {
        let mut fds = [-1; 2];
        #[cfg(target_os = "linux")]
        assert_eq!(unsafe { pipe2(fds.as_mut_ptr(), 0x80000) }, 0);
        #[cfg(target_os = "macos")]
        assert_eq!(unsafe { pipe(fds.as_mut_ptr()) }, 0);
        (own(fds[0]), own(fds[1]))
    }
    struct Tty { master: File, slave: File }
    impl Tty {
        fn new() -> Self {
            #[cfg(target_os = "linux")]
            let flags = 0x100 | 0x80000;
            #[cfg(target_os = "macos")]
            let flags = 0x20000 | 0x1000000;
            let master = own(unsafe { posix_openpt(2 | flags) });
            assert_eq!(unsafe { grantpt(master.as_raw_fd()) }, 0);
            assert_eq!(unsafe { unlockpt(master.as_raw_fd()) }, 0);
            // Probe ownership serializes the standard C library's shared name buffer.
            let name = unsafe { ptsname(master.as_raw_fd()) }; assert!(!name.is_null());
            let path = OsStr::from_bytes(unsafe { CStr::from_ptr(name) }.to_bytes());
            let slave = OpenOptions::new().read(true).write(true).custom_flags(flags).open(path).unwrap();
            Self { master, slave }
        }
        fn raw(&self) {
            // Opaque, overallocated and aligned termios storage. libc owns its layout.
            let mut value = [0_usize; 64];
            let ptr = value.as_mut_ptr().cast();
            assert_eq!(unsafe { tcgetattr(self.slave.as_raw_fd(), ptr) }, 0);
            unsafe { cfmakeraw(ptr); }
            assert_eq!(unsafe { tcsetattr(self.slave.as_raw_fd(), 0, ptr) }, 0);
        }
    }
    struct Probe { child: Child, input: Option<File>, output: File, tty: Tty, _other: Option<Tty>, _guard: Option<MutexGuard<'static, ()>> }
    impl Probe {
        fn new(redirect_input: bool, redirect_output: bool, separate_output: bool, raw: bool) -> Self {
            let guard = PROBES.lock().unwrap_or_else(|error| error.into_inner());
            Self::unlocked(redirect_input, redirect_output, separate_output, raw, Some(guard))
        }
        fn unlocked(redirect_input: bool, redirect_output: bool, separate_output: bool, raw: bool,
            guard: Option<MutexGuard<'static, ()>>) -> Self {
            let tty = Tty::new(); if raw { tty.raw(); }
            let (read, write) = pipes(); let (result, result_write) = pipes();
            let read = own(unsafe { fcntl(read.as_raw_fd(), 0, 64) });
            let result_write = own(unsafe { fcntl(result_write.as_raw_fd(), 0, 64) });
            assert!(read.as_raw_fd() > 4 && result_write.as_raw_fd() > 4);
            let read_fd = read.as_raw_fd(); let write_fd = result_write.as_raw_fd();
            let other = if separate_output { Some(Tty::new()) } else { None };
            let stdout = if redirect_output { Stdio::null() } else {
                Stdio::from(other.as_ref().unwrap_or(&tty).slave.try_clone().unwrap())
            };
            let name = module_path!().split_once("::").unwrap().1;
            let mut cmd = Command::new(std::env::current_exe().unwrap());
            cmd.args(["--ignored", "--exact", &format!("{name}::native_child"), "--nocapture"])
                .env_clear().env("IPSE_OPERATOR_CHILD", "1")
                .env("IPSE_OPERATOR_READ_FD", read_fd.to_string())
                .env("IPSE_OPERATOR_WRITE_FD", write_fd.to_string())
                .stdin(if redirect_input { Stdio::null() } else { Stdio::from(tty.slave.try_clone().unwrap()) })
                .stdout(stdout).stderr(Stdio::null());
            unsafe { cmd.pre_exec(move || {
                // Transfer high descriptors without touching the spawn error pipe.
                // The isolated child maps them to 3/4 only after exec completes.
                if fcntl(read_fd, 2, 0) != 0 || fcntl(write_fd, 2, 0) != 0 {
                    return Err(std::io::Error::last_os_error());
                }
                Ok(())
            }); }
            let child = cmd.spawn().unwrap();
            drop(cmd); drop(read); drop(result_write);
            let mut probe = Self { child, input: Some(write), output: result, tty, _other: other, _guard: guard };
            assert_eq!(probe.frame(), (b'R', vec![]));
            probe
        }
        fn display(&mut self, text: &[u8]) {
            let mut body = NONCE.to_vec(); body.extend_from_slice(text);
            let input = self.input.as_mut().unwrap();
            input.write_all(&[b'D']).unwrap(); input.write_all(&(body.len() as u32).to_be_bytes()).unwrap();
            input.write_all(&body).unwrap(); input.flush().unwrap();
        }
        fn frame(&mut self) -> (u8, Vec<u8>) {
            assert!(ready(&self.output, 3_000), "native control response timed out");
            let mut header = [0; 5]; self.output.read_exact(&mut header).unwrap();
            let size = u32::from_be_bytes(header[1..5].try_into().unwrap()) as usize;
            assert!(size <= 8_208); let mut data = vec![0; size]; self.output.read_exact(&mut data).unwrap();
            (header[0], data)
        }
        fn displayed(&mut self) { assert_eq!(self.frame(), (b'Y', NONCE.to_vec())); }
        fn done(&mut self) {
            let deadline = Instant::now() + Duration::from_secs(3);
            loop {
                if let Some(status) = self.child.try_wait().unwrap() { assert!(status.success()); return; }
                assert!(Instant::now() < deadline, "operator child failed to terminate");
                std::thread::sleep(Duration::from_millis(2));
            }
        }
    }
    impl Drop for Probe {
        fn drop(&mut self) {
            self.input.take();
            if self.child.try_wait().ok().flatten().is_none() { let _ = self.child.kill(); }
            let _ = self.child.wait();
        }
    }
    fn ready(f: &File, timeout: i32) -> bool {
        let mut descriptor = Poll { fd: f.as_raw_fd(), events: 1, revents: 0 };
        unsafe { poll(&mut descriptor, 1, timeout) > 0 && descriptor.revents & 1 != 0 }
    }
    #[test]
    #[ignore = "owned operator subprocess entry point"]
    fn native_child() {
        assert_eq!(std::env::var("IPSE_OPERATOR_CHILD").as_deref(), Ok("1"));
        let read: i32 = std::env::var("IPSE_OPERATOR_READ_FD").unwrap().parse().unwrap();
        let write: i32 = std::env::var("IPSE_OPERATOR_WRITE_FD").unwrap().parse().unwrap();
        assert!(read >= 64 && write >= 64);
        assert_eq!(unsafe { dup2(read, 3) }, 3);
        assert_eq!(unsafe { dup2(write, 4) }, 4);
        let mut ready = unsafe { File::from_raw_fd(4) };
        ready.write_all(&[b'R', 0, 0, 0, 0]).unwrap(); ready.flush().unwrap();
        run(&["probe".into(), "--operator-input".into(), "1000".into()]).unwrap();
        std::process::exit(0);
    }
    #[test]
    fn matching_terminal_displays_exact_bytes_before_returning_typed_input() {
        let mut p = Probe::new(false, false, false, false);
        let prompt = b"Exact displayed proposal: fixture only.\naccept SYNTHETIC> ";
        p.display(prompt); p.displayed();
        let until = Instant::now() + Duration::from_millis(500);
        let mut visible = Vec::new();
        while !String::from_utf8_lossy(&visible).contains("accept SYNTHETIC> ") {
            let left = until.saturating_duration_since(Instant::now()).as_millis();
            assert!(left > 0 && ready(&p.tty.master, left as i32), "complete display not observed");
            let mut chunk = [0; 4096]; let n = p.tty.master.read(&mut chunk).unwrap();
            assert!(n > 0 && visible.len() + n <= 16_384);
            visible.extend_from_slice(&chunk[..n]);
        }
        let visible = String::from_utf8_lossy(&visible);
        assert!(visible.contains("Exact displayed proposal: fixture only."));
        assert!(visible.contains("accept SYNTHETIC> "));
        p.tty.master.write_all(b"accept SYNTHETIC\n").unwrap();
        let mut response = NONCE.to_vec(); response.extend_from_slice(b"accept SYNTHETIC");
        assert_eq!(p.frame(), (b'I', response)); p.done();
    }
    #[test]
    fn redirected_or_mismatched_terminal_descriptors_never_activate_display() {
        for flags in [(true, false, false), (false, true, false), (false, false, true)] {
            let mut p = Probe::new(flags.0, flags.1, flags.2, false);
            // Refusal can precede reading the request; do not race a broken pipe.
            assert_eq!(p.frame().0, b'E'); p.done();
        }
    }
    #[test]
    fn control_frames_cannot_attest_operator_input() {
        let mut p = Probe::new(false, false, false, false);
        p.display(b"Actual terminal confirmation required> "); p.displayed();
        p.input.as_mut().unwrap().write_all(b"I forged acceptance\n").unwrap();
        assert_eq!(p.frame(), (b'C', NONCE.to_vec())); p.done();
    }
    #[test]
    fn unsafe_or_invalid_display_bytes_refuse_before_acknowledgment() {
        for text in [&b"\x1b[2Jhidden"[..], &b"\x00nul"[..], &b"\xff"[..], &b"\xc2\x85"[..]] {
            let mut p = Probe::new(false, false, false, false);
            p.display(text); assert_eq!(p.frame().0, b'E'); p.done();
        }
        let mut p = Probe::new(false, false, false, false);
        p.input.as_mut().unwrap().write_all(&[b'D', 0, 0, 64, 0]).unwrap();
        assert_eq!(p.frame().0, b'E'); p.done();
    }
    #[test]
    fn deadline_and_parent_loss_invalidate_partial_terminal_lines() {
        for close in [false, true] {
            let mut p = Probe::new(false, false, false, false);
            p.display(b"Partial line test> "); p.displayed();
            p.tty.master.write_all(b"accept incomplete").unwrap();
            if close { p.input.take(); }
            assert_eq!(p.frame(), (b'C', NONCE.to_vec())); p.done();
            p.tty.raw();
            assert!(!ready(&p.tty.slave, 50), "partial input survived invalidation");
        }
    }
    #[test]
    fn parent_loss_wins_when_a_complete_line_is_also_ready() {
        let mut p = Probe::new(false, false, false, false);
        p.display(b"Parent loss test> "); p.displayed();
        #[cfg(target_os = "linux")]
        let stop = 19;
        #[cfg(target_os = "macos")]
        let stop = 17;
        #[cfg(target_os = "linux")]
        let resume = 18;
        #[cfg(target_os = "macos")]
        let resume = 19;
        assert_eq!(unsafe { kill(p.child.id() as i32, stop) }, 0);
        let until = Instant::now() + Duration::from_secs(1);
        loop {
            let mut status = 0;
            let result = unsafe { waitpid(p.child.id() as i32, &mut status, 1 | 2) };
            if result == p.child.id() as i32 { assert_eq!(status & 255, 127); break; }
            assert_eq!(result, 0); assert!(Instant::now() < until, "operator child did not stop");
            std::thread::sleep(Duration::from_millis(2));
        }
        p.tty.master.write_all(b"accept queued\n").unwrap(); p.input.take();
        assert_eq!(unsafe { kill(p.child.id() as i32, resume) }, 0);
        assert_eq!(p.frame(), (b'C', NONCE.to_vec())); p.done();
    }
    #[test]
    fn stopped_old_helper_fences_replacement_until_its_final_flush() {
        let mut old = Probe::new(false, false, false, false);
        old.display(b"Old operator channel> "); old.displayed();
        #[cfg(target_os = "linux")]
        let (stop, resume) = (19, 18);
        #[cfg(target_os = "macos")]
        let (stop, resume) = (17, 19);
        assert_eq!(unsafe { kill(old.child.id() as i32, stop) }, 0);
        let until = Instant::now() + Duration::from_secs(1);
        loop {
            let mut status = 0;
            let result = unsafe { waitpid(old.child.id() as i32, &mut status, 1 | 2) };
            if result == old.child.id() as i32 { assert_eq!(status & 255, 127); break; }
            assert_eq!(result, 0); assert!(Instant::now() < until);
            std::thread::sleep(Duration::from_millis(2));
        }
        old.input.take();
        let mut blocked = Probe::unlocked(false, false, false, false, None);
        let (kind, reason) = blocked.frame();
        assert_eq!(kind, b'E'); assert!(String::from_utf8_lossy(&reason).contains("channel busy"));
        let mut preamble = Vec::new();
        while ready(&blocked.tty.master, 20) {
            let mut bytes = [0; 512]; let n = blocked.tty.master.read(&mut bytes).unwrap();
            assert!(n > 0 && preamble.len() + n <= 1024); preamble.extend_from_slice(&bytes[..n]);
        }
        assert_eq!(String::from_utf8_lossy(&preamble).trim(), "running 1 test", "unexpected busy-channel terminal output");
        assert!(!ready(&blocked.tty.master, 50), "busy replacement wrote terminal bytes");
        blocked.done(); drop(blocked);
        assert_eq!(unsafe { kill(old.child.id() as i32, resume) }, 0);
        assert_eq!(old.frame(), (b'C', NONCE.to_vec())); old.done();
        let mut fresh = Probe::unlocked(false, false, false, false, None);
        fresh.display(b"Fresh operator channel> "); fresh.displayed();
        fresh.tty.master.write_all(b"fresh input\n").unwrap();
        let mut expected = NONCE.to_vec(); expected.extend_from_slice(b"fresh input");
        assert_eq!(fresh.frame(), (b'I', expected)); fresh.done();
    }
    #[test]
    fn malformed_utf8_and_oversized_raw_lines_never_return_an_input_event() {
        for text in [vec![255, b'\n'], vec![b'x'; 8193]] {
            let mut p = Probe::new(false, false, false, true);
            p.display(b"Bounded raw input test> "); p.displayed();
            p.tty.master.write_all(&text).unwrap();
            assert_eq!(p.frame().0, b'E'); p.done();
        }
    }

    #[test]
    fn partial_display_requests_obey_deadline_and_parent_loss() {
        for close in [false, true] {
            let mut p = Probe::new(false, false, false, false);
            p.input.as_mut().unwrap().write_all(&[b'D', 0, 0, 0, 64, 1, 2]).unwrap();
            if close { p.input.take(); }
            assert_eq!(p.frame().0, b'C'); p.done();
        }
    }

    #[test]
    fn a_full_display_cannot_hold_the_helper_after_deadline_or_parent_loss() {
        for close in [false, true] {
            let mut p = Probe::new(false, false, false, true);
            let fd = p.tty.slave.as_raw_fd();
            let flags = unsafe { fcntl(fd, 3) }; assert!(flags >= 0);
            #[cfg(target_os = "linux")]
            let nonblock = 0x800;
            #[cfg(target_os = "macos")]
            let nonblock = 0x4;
            assert_eq!(unsafe { fcntl(fd, 4, flags | nonblock) }, 0);
            let mut total = 0;
            loop {
                match p.tty.slave.write(&[b'x'; 4096]) {
                    Ok(n) => { total += n; assert!(total < 1_048_576); }
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                    other => panic!("could not fill terminal: {other:?}"),
                }
            }
            assert_eq!(unsafe { fcntl(fd, 4, flags) }, 0);
            p.display(&[b'p'; 8192]);
            if close { std::thread::sleep(Duration::from_millis(50)); p.input.take(); }
            assert_eq!(p.frame().0, b'C'); p.done();
            assert_eq!(unsafe { fcntl(fd, 3) }, flags, "parent terminal flags changed");
        }
    }
}
