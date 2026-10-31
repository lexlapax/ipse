//! Real-PTY, synthetic native owners for the inert four-lease guardian probe.
#[cfg(target_os = "linux")]
mod linux {
    use std::fs::{self, DirBuilder, File, OpenOptions};
    use std::io::{self, Read, Write};
    use std::os::fd::{AsRawFd, FromRawFd};
    use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt};
    use std::os::unix::process::CommandExt;
    use std::path::{Path, PathBuf};
    use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
    use std::time::{Duration, Instant};
    #[repr(C)]
    struct Poll {
        fd: i32,
        events: i16,
        revents: i16,
    }
    unsafe extern "C" {
        fn poll(fds: *mut Poll, count: usize, timeout: i32) -> i32;
        fn posix_openpt(flags: i32) -> i32;
        fn grantpt(fd: i32) -> i32;
        fn unlockpt(fd: i32) -> i32;
        fn ptsname_r(fd: i32, buf: *mut i8, size: usize) -> i32;
        fn pipe2(fds: *mut i32, flags: i32) -> i32;
        fn fcntl(fd: i32, cmd: i32, ...) -> i32;
        fn dup2(from: i32, to: i32) -> i32;
        fn flock(fd: i32, op: i32) -> i32;
        fn kill(pid: i32, signal: i32) -> i32;
    }
    struct Owned(Child);
    impl Drop for Owned {
        fn drop(&mut self) {
            let _ = self.0.kill();
            let _ = self.0.wait();
        }
    }
    struct StoppedReader(i32);
    impl Drop for StoppedReader {
        fn drop(&mut self) {
            if self.0 > 0 {
                unsafe {
                    kill(self.0, 18);
                    kill(self.0, 9);
                }
            }
        }
    }
    fn fail(msg: &str) -> io::Error {
        io::Error::other(msg)
    }
    fn frame<R: Read + AsRawFd>(r: &mut R) -> io::Result<(u8, Vec<u8>)> {
        let deadline = Instant::now() + Duration::from_secs(8);
        fn exact<R: Read + AsRawFd>(
            r: &mut R,
            mut out: &mut [u8],
            deadline: Instant,
        ) -> io::Result<()> {
            while !out.is_empty() {
                let left = deadline.saturating_duration_since(Instant::now());
                if left.is_zero() {
                    return Err(fail("frame timeout"));
                }
                let mut p = Poll {
                    fd: r.as_raw_fd(),
                    events: 1,
                    revents: 0,
                };
                let n = unsafe { poll(&mut p, 1, left.as_millis().max(1).min(5000) as i32) };
                if n < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
                    continue;
                }
                if n <= 0 {
                    continue;
                }
                match r.read(out) {
                    Ok(0) => return Err(fail("frame EOF")),
                    Ok(n) => out = &mut out[n..],
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
        let mut header = [0; 5];
        exact(r, &mut header, deadline)?;
        let len = u32::from_be_bytes(header[1..].try_into().unwrap()) as usize;
        if len > 1024 {
            return Err(fail("frame too large"));
        }
        let mut body = vec![0; len];
        exact(r, &mut body, deadline)?;
        Ok((header[0], body))
    }
    fn packet<W: Write>(w: &mut W, tag: u8, body: &[u8]) -> io::Result<()> {
        w.write_all(&[tag])?;
        w.write_all(&(body.len() as u32).to_be_bytes())?;
        w.write_all(body)?;
        w.flush()
    }
    fn tx_frame(w: &mut ChildStdin, tag: u8, seq: u64, depth: u8, data: &[u8]) -> io::Result<()> {
        let mut body = seq.to_be_bytes().to_vec();
        body.push(depth);
        body.extend_from_slice(data);
        packet(w, tag, &body)
    }
    fn lock_owner(
        helper: &Path,
        dir: &Path,
    ) -> io::Result<(Owned, ChildStdin, ChildStdout, PathBuf)> {
        DirBuilder::new().mode(0o700).create(dir)?;
        let path = dir.join(".lock");
        let mut p = Owned(
            Command::new(helper)
                .args(["--transaction-lock", "30000"])
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()?,
        );
        let mut input = p.0.stdin.take().ok_or_else(|| fail("missing input"))?;
        let mut output = p.0.stdout.take().ok_or_else(|| fail("missing output"))?;
        tx_frame(&mut input, b'A', 1, 0, path.to_str().unwrap().as_bytes())?;
        if frame(&mut output)?.0 != b'A' {
            return Err(fail("lock failed"));
        }
        Ok((p, input, output, path))
    }
    fn control_owner(helper: &Path, notice: bool) -> io::Result<(Owned, ChildStdin, ChildStdout, u64, u64)> {
        let mut p = Owned(
            Command::new(helper)
                .arg(if notice { "--owner-control-send-v2" } else { "--owner-control-send-v1" })
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()?,
        );
        let input =
            p.0.stdin
                .take()
                .ok_or_else(|| fail("missing owner input"))?;
        let mut output =
            p.0.stdout
                .take()
                .ok_or_else(|| fail("missing owner output"))?;
        let greeting = if notice { b"owner-control-v2" } else { b"owner-control-v1" };
        if frame(&mut output)? != (b'R', greeting.to_vec()) {
            return Err(fail("owner readiness failed"));
        }
        let meta = fs::metadata(format!("/proc/{}/fd/0", p.0.id()))?;
        Ok((p, input, output, meta.dev(), meta.ino()))
    }
    fn tty() -> io::Result<(File, File)> {
        let fd = unsafe { posix_openpt(0x102) };
        if fd < 0 {
            return Err(io::Error::last_os_error());
        }
        let master = unsafe { File::from_raw_fd(fd) };
        if unsafe { grantpt(fd) } != 0 || unsafe { unlockpt(fd) } != 0 {
            return Err(io::Error::last_os_error());
        }
        let mut name = [0i8; 4096];
        if unsafe { ptsname_r(fd, name.as_mut_ptr(), name.len()) } != 0 {
            return Err(fail("tty name"));
        }
        let path = unsafe { std::ffi::CStr::from_ptr(name.as_ptr()) }
            .to_str()
            .map_err(|_| fail("tty path"))?;
        let slave = OpenOptions::new()
            .read(true)
            .write(true)
            .custom_flags(0x100)
            .open(path)?;
        Ok((master, slave))
    }
    fn pipes() -> io::Result<(File, File)> {
        let mut f = [-1; 2];
        if unsafe { pipe2(f.as_mut_ptr(), 0x80000) } != 0 {
            return Err(io::Error::last_os_error());
        }
        Ok((unsafe { File::from_raw_fd(f[0]) }, unsafe {
            File::from_raw_fd(f[1])
        }))
    }
    fn guardian(
        helper: &Path,
        slave: &File,
        active: bool,
        partial: bool,
        prewrite: bool,
        ready_stop: bool,
        management: bool,
        close_ready_stop: bool,
        input_phase: bool,
        notice: bool,
        final_notice_stop: bool,
    ) -> io::Result<(Owned, File, File)> {
        let (read, write) = pipes()?;
        let (out, out_write) = pipes()?;
        let read_high = unsafe { fcntl(read.as_raw_fd(), 0, 64) };
        let out_high = unsafe { fcntl(out_write.as_raw_fd(), 0, 64) };
        if read_high < 0 || out_high < 0 {
            return Err(fail("dup descriptors"));
        }
        let high_read = unsafe { File::from_raw_fd(read_high) };
        let high_out = unsafe { File::from_raw_fd(out_high) };
        let mut cmd = Command::new(helper);
        let mode = if notice {
            "v9-synthetic-notice-display"
        } else if input_phase {
            "v6-management-lease-input"
        } else if management {
            "v5-management-lease-display"
        } else if active {
            "v4-synthetic-lease-display"
        } else {
            "v3-inert-lease-probe"
        };
        cmd.args([
            "--operator-input",
            if input_phase { "10000" } else { "5000" },
            mode,
        ])
        .stdin(Stdio::from(slave.try_clone()?))
        .stdout(Stdio::from(slave.try_clone()?))
        .stderr(Stdio::null());
        if prewrite {
            cmd.env("IPSE_TEST_TTY_PREWRITE_STOP", "1");
        } else if partial {
            cmd.env("IPSE_TEST_TTY_PARTIAL_STOP", "1");
        }
        if ready_stop {
            cmd.env("IPSE_TEST_TTY_READY_STOP", "1");
        }
        if close_ready_stop {
            cmd.env("IPSE_TEST_FRAME_CLOSE_READY_STOP", "1");
        }
        if final_notice_stop {
            cmd.env("IPSE_TEST_TTY_FINAL_NOTICE_STOP", "1");
        }
        unsafe {
            cmd.pre_exec(move || {
                if dup2(read_high, 3) != 3 || dup2(out_high, 4) != 4 {
                    return Err(io::Error::last_os_error());
                }
                Ok(())
            });
        }
        let child = Owned(cmd.spawn()?);
        drop(cmd);
        drop(read);
        drop(out_write);
        drop(high_read);
        drop(high_out);
        Ok((child, write, out))
    }
    fn entry(pid: u32, name: &[u8; 16], secret: &[u8; 32], dev: u64, ino: u64) -> Vec<u8> {
        let mut b = pid.to_be_bytes().to_vec();
        b.extend(name);
        b.extend(secret);
        b.extend(dev.to_be_bytes());
        b.extend(ino.to_be_bytes());
        b
    }
    fn request(target: u32, name: &[u8; 16], secret: &[u8; 32], dev: u64, ino: u64) -> Vec<u8> {
        entry(target, name, secret, dev, ino)
    }
    fn held(path: &Path) -> io::Result<bool> {
        let file = OpenOptions::new().read(true).write(true).open(path)?;
        let result = unsafe { flock(file.as_raw_fd(), 2 | 4) };
        if result == 0 {
            Ok(false)
        } else if io::Error::last_os_error().kind() == io::ErrorKind::WouldBlock {
            Ok(true)
        } else {
            Err(io::Error::last_os_error())
        }
    }
    fn eventually_free(paths: &[PathBuf]) -> io::Result<()> {
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            if paths.iter().all(|p| held(p).is_ok_and(|v| !v)) {
                return Ok(());
            }
            if Instant::now() >= deadline {
                return Err(fail("last holder remained"));
            }
            std::thread::sleep(Duration::from_millis(10));
        }
    }
    pub fn main() -> io::Result<()> {
        let args: Vec<_> = std::env::args_os().collect();
        if args.len() != 4 {
            return Err(fail(
                "usage: fixture ROOT HELPER normal|guardian-loss|reader-loss|owner-loss|owner-loss-collect",
            ));
        }
        let root = Path::new(&args[1]);
        let helper = Path::new(&args[2]);
        let mode = args[3].to_str().unwrap_or("");
        if !matches!(
            mode,
            "normal"
                | "guardian-loss"
                | "reader-loss"
                | "owner-loss"
                | "owner-loss-collect"
                | "display-ok"
                | "display-notice"
                | "display-notice-forged"
                | "display-notice-owner-loss"
                | "display-notice-expiry"
                | "display-notice-final-stop"
                | "display-forged"
                | "display-forged-manifest"
                | "display-wrong-tty"
                | "display-reader-loss"
                | "display-expired"
                | "display-owner-loss"
                | "display-partial-owner"
                | "display-partial-expired"
                | "display-admitted-race"
                | "display-replay"
                | "display-receipt-stall"
                | "display-short-1"
                | "display-short-2"
                | "display-short-3"
                | "display-mono-ready"
                | "display-management-large"
                | "display-management-mono-expired"
                | "display-management-mono-ready"
                | "display-management-close-mono"
                | "display-management-close-wall"
                | "display-management-input"
                | "display-management-input-owner-loss"
        ) {
            return Err(fail("bad mode"));
        }
        let mut locks = Vec::new();
        for i in 0..4 {
            locks.push(lock_owner(helper, &root.join(format!("lock-{i}")))?);
        }
        let mut session = control_owner(helper, mode.starts_with("display-notice"))?;
        let mut host = control_owner(helper, false)?;
        let (mut master, slave) = tty()?;
        let active = mode.starts_with("display-");
        let prewrite = mode == "display-admitted-race" || mode == "display-replay";
        let partial = mode.starts_with("display-partial-") || prewrite;
        let (mut guardian, mut input, mut output) = guardian(
            helper,
            &slave,
            active,
            partial,
            prewrite,
            mode == "display-mono-ready" || mode == "display-management-mono-ready",
            mode.starts_with("display-management-"),
            mode == "display-management-close-mono" || mode == "display-management-close-wall",
            mode == "display-management-input" || mode == "display-management-input-owner-loss",
            mode.starts_with("display-notice"),
            mode == "display-notice-final-stop",
        )?;
        let management_clock = if mode.starts_with("display-management-") {
            let (tag, body) = frame(&mut output)?;
            if tag != b'R' || body.len() != 8 {
                return Err(fail("management clock unavailable"));
            }
            Some(u64::from_be_bytes(body.try_into().unwrap()))
        } else {
            None
        };
        let count = match mode {
            "display-short-1" => 1,
            "display-short-2" => 2,
            "display-short-3" => 3,
            _ => 4,
        };
        let operation = [37u8; 16];
        let mut names = [[0u8; 16]; 6];
        let mut secrets = [[0u8; 32]; 6];
        for i in 0..6 {
            names[i] = [(40 + i) as u8; 16];
            secrets[i] = [(60 + i) as u8; 32];
            names[i][..4].copy_from_slice(&std::process::id().to_be_bytes());
        }
        let mut body = operation.to_vec();
        body.push(count as u8);
        body.extend(entry(
            session.0 .0.id(),
            &names[0],
            &secrets[0],
            session.3,
            session.4,
        ));
        body.extend(entry(
            host.0 .0.id(),
            &names[1],
            &secrets[1],
            host.3,
            host.4,
        ));
        for i in 0..count {
            let m = fs::metadata(&locks[i].3)?;
            body.push(0);
            body.extend(operation);
            body.extend(entry(
                locks[i].0 .0.id(),
                &names[i + 2],
                &secrets[i + 2],
                m.dev(),
                m.ino(),
            ));
        }
        let payload = if mode == "display-management-large" {
            vec![b'X'; 65_536]
        } else if partial {
            vec![b'X'; 8192]
        } else {
            b"SYNTHETIC_LEASED_DISPLAY".to_vec()
        };
        if active {
            let tty_meta = slave.metadata()?;
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map_err(|_| fail("clock"))?
                .as_millis() as u64;
            let expiry = now
                + if mode == "display-expired"
                    || mode == "display-partial-expired"
                    || mode == "display-receipt-stall"
                    || mode == "display-management-close-wall"
                    || mode == "display-notice-expiry"
                    || mode == "display-notice-final-stop"
                {
                    1000
                } else if mode == "display-mono-ready"
                    || mode == "display-management-mono-ready"
                    || mode == "display-management-close-mono"
                {
                    10_000
                } else {
                    4000
                };
            body.extend(tty_meta.dev().to_be_bytes());
            let tty_inode = if mode == "display-wrong-tty" {
                tty_meta.ino() ^ 1
            } else {
                tty_meta.ino()
            };
            body.extend(tty_inode.to_be_bytes());
            body.extend(tty_meta.rdev().to_be_bytes());
            body.extend(expiry.to_be_bytes());
            if let Some(clock) = management_clock {
                body.extend(
                    (clock
                        + match mode {
                            "display-management-mono-expired" => 1,
                            "display-management-mono-ready" | "display-management-close-mono" => {
                                1_000
                            }
                            _ => 4_000,
                        })
                    .to_be_bytes(),
                );
                if mode == "display-management-input"
                    || mode == "display-management-input-owner-loss"
                {
                    body.extend((now + 8_000).to_be_bytes());
                    body.extend((clock + 8_000).to_be_bytes());
                }
            }
            body.extend((payload.len() as u32).to_be_bytes());
            body.extend(&payload);
        }
        if mode == "display-management-mono-expired" {
            std::thread::sleep(Duration::from_millis(20));
        }
        packet(&mut input, b'I', &body)?;
        if mode == "display-wrong-tty"
            || mode.starts_with("display-short-")
            || mode == "display-management-mono-expired"
        {
            if guardian.0.wait()?.success() {
                return Err(fail("wrong terminal identity falsely confirmed"));
            }
            if let Ok((b'H' | b'D' | b'C', _)) = frame(&mut output) {
                return Err(fail("wrong terminal identity emitted authority"));
            }
            let mut visible = Poll {
                fd: master.as_raw_fd(),
                events: 1,
                revents: 0,
            };
            if unsafe { poll(&mut visible, 1, 0) } != 0 {
                return Err(fail("wrong terminal identity wrote bytes"));
            }
            let paths: Vec<_> = locks.iter().map(|v| v.3.clone()).collect();
            for (p, _, _, _) in &mut locks {
                p.0.kill()?;
                p.0.wait()?;
            }
            eventually_free(&paths)?;
            println!("TTY_SYNTHETIC_INITIAL_MANIFEST_REFUSED_WITHOUT_WRITE");
            return Ok(());
        }
        let mut summary = operation.to_vec();
        summary.push(4);
        if frame(&mut output)? != (b'H', summary.clone()) {
            return Err(fail("guardian not ready"));
        }
        for (index, owner) in [&mut session, &mut host].into_iter().enumerate() {
            let mut req = operation.to_vec();
            req.push((index + 1) as u8);
            req.extend(guardian.0.id().to_be_bytes());
            req.extend(names[index]);
            req.extend(secrets[index]);
            packet(&mut owner.1, b'I', &req)?;
            if frame(&mut owner.2)?.0 != b'H' || frame(&mut owner.2)?.0 != b'T' {
                return Err(fail("owner transfer unconfirmed"));
            }
            if index == 0 && mode == "owner-loss-collect" {
                owner.0 .0.kill()?;
                owner.0 .0.wait()?;
                if guardian.0.wait()?.success() {
                    return Err(fail("partial owner loss falsely confirmed"));
                }
                if let Ok((b'C', _)) = frame(&mut output) {
                    return Err(fail("partial owner loss emitted a close receipt"));
                }
                let mut visible = Poll {
                    fd: master.as_raw_fd(),
                    events: 1,
                    revents: 0,
                };
                if unsafe { poll(&mut visible, 1, 0) } != 0 {
                    return Err(fail("inert probe wrote to tty"));
                }
                let paths: Vec<_> = locks.iter().map(|v| v.3.clone()).collect();
                for (p, _, _, _) in &mut locks {
                    p.0.kill()?;
                    p.0.wait()?;
                }
                eventually_free(&paths)?;
                println!("TTY_LEASE_PARTIAL_COLLECTION_OWNER_LOSS_CLEANED");
                return Ok(());
            }
        }
        for i in 0..4 {
            let meta = fs::metadata(&locks[i].3)?;
            let mut data = vec![0];
            data.extend(operation);
            data.extend(request(
                guardian.0.id(),
                &names[i + 2],
                &secrets[i + 2],
                meta.dev(),
                meta.ino(),
            ));
            tx_frame(&mut locks[i].1, b'Y', 2, 1, &data)?;
            if frame(&mut locks[i].2)?.0 != b'Y' {
                return Err(fail("lease transfer failed"));
            }
        }
        let (tag, collected) = frame(&mut output)?;
        if tag != b'L' || collected.len() != 21 || collected[..17] != summary {
            return Err(fail("fork collection failed"));
        }
        let mut visible = Poll {
            fd: master.as_raw_fd(),
            events: 1,
            revents: 0,
        };
        if unsafe { poll(&mut visible, 1, 0) } != 0 {
            return Err(fail("inert probe wrote to tty"));
        }
        let reader = u32::from_be_bytes(collected[17..21].try_into().unwrap()) as i32;
        let paths: Vec<_> = locks.iter().map(|v| v.3.clone()).collect();
        for p in &paths {
            if !held(p)? {
                return Err(fail("lease not held"));
            }
        }
        if active {
            if mode == "display-reader-loss" {
                if unsafe { kill(reader, 9) } != 0 {
                    return Err(fail("reader kill failed"));
                }
                let until = Instant::now() + Duration::from_millis(1000);
                loop {
                    if let Some(status) = guardian.0.try_wait()? {
                        if status.success() {
                            return Err(fail("reader loss falsely confirmed"));
                        }
                        break;
                    }
                    if Instant::now() >= until {
                        return Err(fail("guardian failed to detect reader loss"));
                    }
                    std::thread::sleep(Duration::from_millis(2));
                }
            } else if mode == "display-owner-loss" {
                session.0 .0.kill()?;
                session.0 .0.wait()?;
                if guardian.0.wait()?.success() {
                    return Err(fail("owner loss falsely confirmed"));
                }
            } else {
                if mode == "display-expired" {
                    std::thread::sleep(Duration::from_millis(1100));
                }
                let mut activation = body.clone();
                if mode == "display-forged" || mode == "display-notice-forged" {
                    let last = activation.len() - 1;
                    activation[last] ^= 1;
                }
                if mode == "display-forged-manifest" {
                    activation[170] ^= 1;
                }
                if mode == "display-receipt-stall" {
                    let mut inject = OpenOptions::new()
                        .write(true)
                        .custom_flags(0x800)
                        .open(format!("/proc/{}/fd/4", guardian.0.id()))?;
                    let filler = [b'Z'; 4096];
                    let mut filled = 0usize;
                    loop {
                        match inject.write(&filler) {
                            Ok(0) => return Err(fail("status pipe closed")),
                            Ok(n) => {
                                filled += n;
                                if filled > 1_048_576 {
                                    return Err(fail("status pipe unbounded"));
                                }
                            }
                            Err(e) if e.kind() == io::ErrorKind::WouldBlock => break,
                            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                            Err(e) => return Err(e),
                        }
                    }
                    if filled == 0 {
                        return Err(fail("status pipe not filled"));
                    }
                    drop(inject);
                    packet(&mut input, b'A', &activation)?;
                    std::thread::sleep(Duration::from_millis(1200));
                    let flags = unsafe { fcntl(output.as_raw_fd(), 3) };
                    if flags < 0 || unsafe { fcntl(output.as_raw_fd(), 4, flags | 0x800) } < 0 {
                        return Err(fail("status nonblocking failed"));
                    }
                    let mut status_bytes = Vec::new();
                    let mut chunk = [0u8; 4096];
                    loop {
                        match output.read(&mut chunk) {
                            Ok(0) => break,
                            Ok(n) => status_bytes.extend_from_slice(&chunk[..n]),
                            Err(e) if e.kind() == io::ErrorKind::WouldBlock => break,
                            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                            Err(e) => return Err(e),
                        }
                    }
                    if guardian.0.wait()?.success() {
                        return Err(fail("late receipt falsely confirmed"));
                    }
                    loop {
                        match output.read(&mut chunk) {
                            Ok(0) => break,
                            Ok(n) => status_bytes.extend_from_slice(&chunk[..n]),
                            Err(e) if e.kind() == io::ErrorKind::WouldBlock => break,
                            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                            Err(e) => return Err(e),
                        }
                    }
                    if status_bytes.len() != filled || status_bytes.iter().any(|b| *b != b'Z') {
                        return Err(fail("late display status emitted"));
                    }
                    let mut visible = Poll {
                        fd: master.as_raw_fd(),
                        events: 1,
                        revents: 0,
                    };
                    if unsafe { poll(&mut visible, 1, 1000) } <= 0 {
                        return Err(fail("display write did not precede stalled status"));
                    }
                    let mut received = vec![0; payload.len()];
                    master.read_exact(&mut received)?;
                    if received != payload {
                        return Err(fail("display bytes mismatch"));
                    }
                    for p in &paths {
                        if !held(p)? {
                            return Err(fail("original lock escaped"));
                        }
                    }
                    for (p, _, _, _) in &mut locks {
                        p.0.kill()?;
                        p.0.wait()?;
                    }
                    eventually_free(&paths)?;
                    println!("TTY_SYNTHETIC_STATUS_BACKPRESSURE_EXPIRED_UNKNOWN");
                    return Ok(());
                }
                let draining = if mode == "display-management-large" {
                    let mut reader = master.try_clone()?;
                    let count = payload.len();
                    Some(std::thread::spawn(move || {
                        let mut data = vec![0; count];
                        reader.read_exact(&mut data).map(|_| data)
                    }))
                } else {
                    None
                };
                packet(&mut input, b'A', &activation)?;
                if mode == "display-mono-ready" || mode == "display-management-mono-ready" {
                    let mut cleanup = StoppedReader(reader);
                    let until = Instant::now() + Duration::from_secs(1);
                    loop {
                        let state = fs::read_to_string(format!("/proc/{reader}/status"))?;
                        if state
                            .lines()
                            .any(|line| line.starts_with("State:") && line.contains("stopped"))
                        {
                            break;
                        }
                        if Instant::now() >= until {
                            return Err(fail("reader did not stop after readiness"));
                        }
                        std::thread::sleep(Duration::from_millis(2));
                    }
                    if unsafe { kill(guardian.0.id() as i32, 19) } != 0 {
                        return Err(fail("guardian stop failed"));
                    }
                    std::thread::sleep(Duration::from_millis(
                        if mode == "display-management-mono-ready" {
                            1_200
                        } else {
                            5_200
                        },
                    ));
                    if unsafe { kill(reader, 18) } != 0 {
                        return Err(fail("reader continue failed"));
                    }
                    std::thread::sleep(Duration::from_millis(50));
                    if unsafe { kill(guardian.0.id() as i32, 18) } != 0 {
                        return Err(fail("guardian continue failed"));
                    }
                    if guardian.0.wait()?.success() {
                        return Err(fail("expired monotonic deadline confirmed"));
                    }
                    cleanup.0 = -1;
                    if let Ok((b'D' | b'C', _)) = frame(&mut output) {
                        return Err(fail("late monotonic status emitted"));
                    }
                    let mut visible = Poll {
                        fd: master.as_raw_fd(),
                        events: 1,
                        revents: 0,
                    };
                    if unsafe { poll(&mut visible, 1, 0) } != 0 {
                        return Err(fail("tty write admitted after monotonic deadline"));
                    }
                    for p in &paths {
                        if !held(p)? {
                            return Err(fail("original lock escaped"));
                        }
                    }
                    for (p, _, _, _) in &mut locks {
                        p.0.kill()?;
                        p.0.wait()?;
                    }
                    eventually_free(&paths)?;
                    println!("TTY_SYNTHETIC_LATE_READY_MONOTONIC_REFUSED_WITHOUT_WRITE");
                    return Ok(());
                }
                if partial {
                    let mut cleanup = StoppedReader(reader);
                    let until = Instant::now() + Duration::from_secs(1);
                    loop {
                        let state = fs::read_to_string(format!("/proc/{reader}/status"))?;
                        if state
                            .lines()
                            .any(|line| line.starts_with("State:") && line.contains("stopped"))
                        {
                            break;
                        }
                        if Instant::now() >= until {
                            return Err(fail("reader did not stop after its first write"));
                        }
                        std::thread::sleep(Duration::from_millis(2));
                    }
                    if mode == "display-replay" {
                        let _ = packet(&mut input, b'A', &body);
                        if guardian.0.wait()?.success() {
                            return Err(fail("replayed activation falsely confirmed"));
                        }
                        if let Ok((b'D' | b'C', _)) = frame(&mut output) {
                            return Err(fail("replayed activation emitted success"));
                        }
                        for p in &paths {
                            if !held(p)? {
                                return Err(fail("original lock escaped"));
                            }
                        }
                        for (p, _, _, _) in &mut locks {
                            p.0.kill()?;
                            p.0.wait()?;
                        }
                        eventually_free(&paths)?;
                        cleanup.0 = -1;
                        let mut visible = Poll {
                            fd: master.as_raw_fd(),
                            events: 1,
                            revents: 0,
                        };
                        if unsafe { poll(&mut visible, 1, 0) } != 0 {
                            return Err(fail("replayed activation wrote terminal bytes"));
                        }
                        println!("TTY_SYNTHETIC_REPLAY_REFUSED_WITHOUT_WRITE");
                        return Ok(());
                    }
                    let mut visible = Poll {
                        fd: master.as_raw_fd(),
                        events: 1,
                        revents: 0,
                    };
                    let visible_result =
                        unsafe { poll(&mut visible, 1, if prewrite { 0 } else { 1000 }) };
                    if !prewrite && visible_result <= 0 {
                        return Err(fail("no partial tty bytes"));
                    }
                    if prewrite && visible_result != 0 {
                        return Err(fail("tty wrote before admitted race"));
                    }
                    let flags = unsafe { fcntl(master.as_raw_fd(), 3) };
                    if flags < 0 || unsafe { fcntl(master.as_raw_fd(), 4, flags | 0x800) } < 0 {
                        return Err(fail("tty nonblocking failed"));
                    }
                    let mut observed = Vec::new();
                    let mut chunk = [0u8; 8192];
                    loop {
                        match master.read(&mut chunk) {
                            Ok(0) => break,
                            Ok(n) => observed.extend_from_slice(&chunk[..n]),
                            Err(e) if e.kind() == io::ErrorKind::WouldBlock => break,
                            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                            Err(e) => return Err(e),
                        }
                    }
                    if (!prewrite && observed.is_empty())
                        || (prewrite && !observed.is_empty())
                        || observed.len() >= payload.len()
                        || observed.iter().any(|x| *x != b'X')
                    {
                        return Err(fail("partial tty bytes invalid"));
                    }
                    if mode == "display-partial-owner" || prewrite {
                        if unsafe { kill(guardian.0.id() as i32, 19) } != 0 {
                            return Err(fail("guardian stop failed"));
                        }
                        session.0 .0.kill()?;
                        session.0 .0.wait()?;
                        for (p, _, _, _) in &mut locks {
                            p.0.kill()?;
                            p.0.wait()?;
                        }
                        guardian.0.kill()?;
                        guardian.0.wait()?;
                        for p in &paths {
                            if !held(p)? {
                                return Err(fail("stopped writer lost its lock"));
                            }
                        }
                        if unsafe { kill(reader, 18) } != 0 {
                            return Err(fail("reader continue failed"));
                        }
                        eventually_free(&paths)?;
                    } else {
                        std::thread::sleep(Duration::from_millis(1100));
                        if unsafe { kill(reader, 18) } != 0 {
                            return Err(fail("reader continue failed"));
                        }
                        if guardian.0.wait()?.success() {
                            return Err(fail("expired partial display falsely confirmed"));
                        }
                        for p in &paths {
                            if !held(p)? {
                                return Err(fail("original lock escaped"));
                            }
                        }
                        for (p, _, _, _) in &mut locks {
                            p.0.kill()?;
                            p.0.wait()?;
                        }
                        eventually_free(&paths)?;
                    }
                    cleanup.0 = -1;
                    if let Ok((b'D' | b'C', _)) = frame(&mut output) {
                        return Err(fail("partial write falsely confirmed"));
                    }
                    loop {
                        match master.read(&mut chunk) {
                            Ok(0) => break,
                            Ok(n) => observed.extend_from_slice(&chunk[..n]),
                            Err(e) if e.kind() == io::ErrorKind::WouldBlock => break,
                            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                            Err(e) => return Err(e),
                        }
                    }
                    if observed.is_empty()
                        || observed.len() >= payload.len()
                        || observed.iter().any(|x| *x != b'X')
                    {
                        return Err(fail("partial result was not bounded"));
                    }
                    println!(
                        "TTY_SYNTHETIC_{}_PARTIAL_UNKNOWN_AND_CLEANED",
                        mode.to_uppercase().replace('-', "_")
                    );
                    return Ok(());
                }
                if mode == "display-ok"
                    || mode == "display-notice"
                    || mode == "display-notice-owner-loss"
                    || mode == "display-notice-expiry"
                    || mode == "display-notice-final-stop"
                    || mode == "display-management-large"
                    || mode == "display-management-close-mono"
                    || mode == "display-management-close-wall"
                    || mode == "display-management-input"
                    || mode == "display-management-input-owner-loss"
                {
                    if frame(&mut output)? != (b'D', summary.clone()) {
                        return Err(fail("display completion unconfirmed"));
                    }
                    let actual = if let Some(task) = draining {
                        task.join().map_err(|_| fail("terminal drain panicked"))??
                    } else {
                        let mut actual = vec![0u8; payload.len()];
                        master.read_exact(&mut actual)?;
                        actual
                    };
                    if actual != payload {
                        return Err(fail("terminal bytes differ"));
                    }
                } else if guardian.0.wait()?.success() {
                    return Err(fail("invalid activation falsely confirmed"));
                }
            }
            if mode != "display-ok"
                && mode != "display-notice"
                && mode != "display-notice-owner-loss"
                && mode != "display-notice-expiry"
                && mode != "display-notice-final-stop"
                && mode != "display-management-large"
                && mode != "display-management-close-mono"
                && mode != "display-management-close-wall"
                && mode != "display-management-input"
                && mode != "display-management-input-owner-loss"
            {
                if mode == "display-notice-forged" {
                    if let Ok((b'N', _)) = frame(&mut session.2) {
                        return Err(fail("invalid activation emitted a peer notice"));
                    }
                }
                if let Ok((b'D' | b'C', _)) = frame(&mut output) {
                    return Err(fail("loss falsely reported success"));
                }
                let mut visible = Poll {
                    fd: master.as_raw_fd(),
                    events: 1,
                    revents: 0,
                };
                if unsafe { poll(&mut visible, 1, 0) } != 0 {
                    return Err(fail("refused activation wrote terminal bytes"));
                }
                for p in &paths {
                    if !held(p)? {
                        return Err(fail("original lock escaped"));
                    }
                }
                for (p, _, _, _) in &mut locks {
                    p.0.kill()?;
                    p.0.wait()?;
                }
                eventually_free(&paths)?;
                println!(
                    "TTY_SYNTHETIC_{}_REFUSED_WITHOUT_WRITE",
                    mode.to_uppercase().replace('-', "_")
                );
                return Ok(());
            }
        }
        if mode == "guardian-loss" {
            if unsafe { kill(reader, 19) } != 0 {
                return Err(fail("reader stop failed"));
            }
            guardian.0.kill()?;
            guardian.0.wait()?;
            for (p, _, _, _) in &mut locks {
                p.0.kill()?;
                p.0.wait()?;
            }
            for p in &paths {
                if !held(p)? {
                    unsafe {
                        kill(reader, 18);
                    };
                    return Err(fail("stopped reader lost lease"));
                }
            }
            if unsafe { kill(reader, 18) } != 0 {
                return Err(fail("reader continue failed"));
            }
            eventually_free(&paths)?;
            println!("TTY_LEASE_GUARDIAN_LOSS_RETAINED_UNTIL_READER_EXIT");
            return Ok(());
        }
        if mode == "reader-loss" {
            if unsafe { kill(reader, 9) } != 0 {
                return Err(fail("reader kill failed"));
            }
            input.write_all(b"C")?;
            input.write_all(&operation)?;
            input.flush()?;
            if guardian.0.wait()?.success() {
                return Err(fail("reader loss falsely confirmed"));
            }
            if let Ok((b'C', _)) = frame(&mut output) {
                return Err(fail("reader loss emitted a close receipt"));
            }
            for p in &paths {
                if !held(p)? {
                    return Err(fail("exporter lost original lease"));
                }
            }
            for (p, _, _, _) in &mut locks {
                p.0.kill()?;
                p.0.wait()?;
            }
            eventually_free(&paths)?;
            println!("TTY_LEASE_READER_LOSS_UNCONFIRMED_AND_CLEANED");
            return Ok(());
        }
        if mode == "owner-loss" {
            session.0 .0.kill()?;
            session.0 .0.wait()?;
            if guardian.0.wait()?.success() {
                return Err(fail("owner loss falsely confirmed"));
            }
            if let Ok((b'C', _)) = frame(&mut output) {
                return Err(fail("owner loss emitted a close receipt"));
            }
            for p in &paths {
                if !held(p)? {
                    return Err(fail("exporter lost original lease"));
                }
            }
            for (p, _, _, _) in &mut locks {
                p.0.kill()?;
                p.0.wait()?;
            }
            eventually_free(&paths)?;
            println!("TTY_LEASE_OWNER_LOSS_UNCONFIRMED_AND_CLEANED");
            return Ok(());
        }
        input.write_all(b"C")?;
        input.write_all(&operation)?;
        input.flush()?;
        for (p, writer, output, _) in &mut locks {
            let mut data = vec![0];
            data.extend(operation);
            tx_frame(writer, b'K', 3, 1, &data)?;
            let (kind, _) = frame(output)?;
            if kind != b'K' {
                return Err(fail("settlement failed"));
            }
            let _ = p;
        }
        if mode == "display-management-close-mono" || mode == "display-management-close-wall" {
            let until = Instant::now() + Duration::from_secs(1);
            loop {
                let state = fs::read_to_string(format!("/proc/{}/status", guardian.0.id()))?;
                if state
                    .lines()
                    .any(|line| line.starts_with("State:") && line.contains("stopped"))
                {
                    break;
                }
                if Instant::now() >= until {
                    return Err(fail("guardian did not stop after close readiness"));
                }
                std::thread::sleep(Duration::from_millis(2));
            }
            std::thread::sleep(Duration::from_millis(1200));
            if unsafe { kill(guardian.0.id() as i32, 18) } != 0 {
                return Err(fail("guardian continue failed"));
            }
            if let Ok((b'C', _)) = frame(&mut output) {
                return Err(fail("late close frame emitted"));
            }
            if guardian.0.wait()?.success() {
                return Err(fail("late close falsely confirmed"));
            }
            for (p, writer, output, _) in &mut locks {
                tx_frame(writer, b'R', 4, 1, &[])?;
                if frame(output)?.0 != b'R' || !p.0.wait()?.success() {
                    return Err(fail("original release failed"));
                }
            }
            eventually_free(&paths)?;
            println!("TTY_MANAGEMENT_LATE_CLOSE_STATUS_REFUSED");
            return Ok(());
        }
        if frame(&mut output)? != (b'C', summary) {
            return Err(fail("guardian close failed"));
        }
        if mode == "display-notice" || mode == "display-notice-owner-loss" || mode == "display-notice-expiry" || mode == "display-notice-final-stop" {
            let mut expected = operation.to_vec();
            expected.push(1);
            let expiry_at = 153 + count * 85 + 24;
            expected.extend_from_slice(&body[expiry_at..expiry_at + 8]);
            if frame(&mut session.2)? != (b'N', expected) {
                return Err(fail("owner notice missing or mismatched"));
            }
        }
        if mode == "display-notice-owner-loss" {
            session.0 .0.kill()?;
            session.0 .0.wait()?;
            if guardian.0.wait()?.success() {
                return Err(fail("owner loss after notice falsely confirmed"));
            }
            for (p, writer, output, _) in &mut locks {
                tx_frame(writer, b'R', 4, 1, &[])?;
                if frame(output)?.0 != b'R' || !p.0.wait()?.success() {
                    return Err(fail("original release failed"));
                }
            }
            eventually_free(&paths)?;
            println!("TTY_NOTICE_OWNER_LOSS_AFTER_DISPLAY_UNCONFIRMED");
            return Ok(());
        }
        if mode == "display-notice-expiry" {
            std::thread::sleep(Duration::from_millis(1100));
            input.write_all(b"U")?;
            input.write_all(&operation)?;
            input.flush()?;
            if guardian.0.wait()?.success() {
                return Err(fail("expired release falsely confirmed"));
            }
            if let Ok((b'F', _)) = frame(&mut session.2) {
                return Err(fail("expired release emitted final notice"));
            }
            for (p, writer, output, _) in &mut locks {
                tx_frame(writer, b'R', 4, 1, &[])?;
                if frame(output)?.0 != b'R' || !p.0.wait()?.success() {
                    return Err(fail("original release failed"));
                }
            }
            eventually_free(&paths)?;
            println!("TTY_NOTICE_EXPIRED_RELEASE_UNCONFIRMED");
            return Ok(());
        }
        if mode == "display-notice-final-stop" {
            input.write_all(b"U")?;
            input.write_all(&operation)?;
            input.flush()?;
            let until = Instant::now() + Duration::from_secs(1);
            loop {
                let state = fs::read_to_string(format!("/proc/{}/status", guardian.0.id()))?;
                if state.lines().any(|line| line.starts_with("State:") && line.contains("stopped")) { break; }
                if Instant::now() >= until { return Err(fail("guardian did not stop before final notice")); }
                std::thread::sleep(Duration::from_millis(2));
            }
            std::thread::sleep(Duration::from_millis(1100));
            if unsafe { kill(guardian.0.id() as i32, 18) } != 0 { return Err(fail("guardian continue failed")); }
            let final_frame = frame(&mut session.2);
            if let Ok((b'F', _)) = final_frame {
                println!("TTY_NOTICE_FINAL_AFTER_EXPIRY_COUNTEREXAMPLE");
            } else {
                println!("TTY_NOTICE_FINAL_AFTER_EXPIRY_REFUSED");
            }
            let _ = guardian.0.wait();
            for (p, writer, output, _) in &mut locks {
                tx_frame(writer, b'R', 4, 1, &[])?;
                if frame(output)?.0 != b'R' || !p.0.wait()?.success() { return Err(fail("original release failed")); }
            }
            eventually_free(&paths)?;
            return Ok(());
        }
        if active {
            if mode == "display-management-input" || mode == "display-management-input-owner-loss" {
                master.write_all(b"stale-before-release\n")?;
                std::thread::sleep(Duration::from_millis(20));
                let flags = unsafe { fcntl(master.as_raw_fd(), 3) };
                if flags < 0 || unsafe { fcntl(master.as_raw_fd(), 4, flags | 0x800) } < 0 {
                    return Err(fail("tty nonblocking failed"));
                }
                let mut discarded = [0u8; 256];
                loop {
                    match master.read(&mut discarded) {
                        Ok(n) if n > 0 => (),
                        Err(e) if e.kind() == io::ErrorKind::WouldBlock => break,
                        Err(e) if e.kind() == io::ErrorKind::Interrupted => (),
                        _ => break,
                    }
                }
                if unsafe { fcntl(master.as_raw_fd(), 4, flags) } < 0 {
                    return Err(fail("tty restore blocking failed"));
                }
            }
            input.write_all(b"U")?;
            input.write_all(&operation)?;
            input.flush()?;
            if mode == "display-notice" {
                let mut expected = operation.to_vec();
                expected.push(1);
                if frame(&mut session.2)? != (b'F', expected) {
                    return Err(fail("owner final notice missing or mismatched"));
                }
            }
            if mode == "display-management-input" || mode == "display-management-input-owner-loss" {
                let mut prompt = [0u8; 10];
                master.read_exact(&mut prompt)?;
                if &prompt != b"approval> " {
                    return Err(fail("input prompt mismatch"));
                }
                if mode == "display-management-input-owner-loss" {
                    session.0 .0.kill()?;
                    session.0 .0.wait()?;
                    if guardian.0.wait()?.success() {
                        return Err(fail("input owner loss falsely confirmed"));
                    }
                    if let Ok((b'i' | b'z', _)) = frame(&mut output) {
                        return Err(fail("input owner loss emitted observation"));
                    }
                    for (p, writer, output, _) in &mut locks {
                        tx_frame(writer, b'R', 4, 1, &[])?;
                        if frame(output)?.0 != b'R' || !p.0.wait()?.success() {
                            return Err(fail("original release failed"));
                        }
                    }
                    eventually_free(&paths)?;
                    println!("TTY_MANAGEMENT_INPUT_OWNER_LOSS_UNCONFIRMED");
                    return Ok(());
                }
                master.write_all(b"forget synthetic\n")?;
                let mut expected = operation.to_vec();
                expected.extend_from_slice(b"forget synthetic");
                if frame(&mut output)? != (b'i', expected)
                    || frame(&mut output)? != (b'z', operation.to_vec())
                {
                    return Err(fail("input observation unconfirmed"));
                }
            }
        }
        if !guardian.0.wait()?.success() {
            return Err(fail("guardian release failed"));
        }
        if mode == "display-notice" && !session.0 .0.wait()?.success() {
            return Err(fail("owner final close unconfirmed"));
        }
        for p in &paths {
            if !held(p)? {
                return Err(fail("original exporter unexpectedly lost lease"));
            }
        }
        for (p, writer, output, _) in &mut locks {
            tx_frame(writer, b'R', 4, 1, &[])?;
            if frame(output)?.0 != b'R' || !p.0.wait()?.success() {
                return Err(fail("original release failed"));
            }
        }
        eventually_free(&paths)?;
        println!("TTY_FOUR_LEASES_TWO_OWNER_CONTROLS_REAPED_AND_SETTLED");
        Ok(())
    }
}
#[cfg(target_os = "linux")]
fn main() {
    if let Err(e) = linux::main() {
        eprintln!("{e}");
        std::process::exit(1);
    }
}
#[cfg(not(target_os = "linux"))]
fn main() {
    std::process::exit(1);
}
