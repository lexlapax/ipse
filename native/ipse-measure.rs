#[cfg(target_os = "linux")]
mod linux {
    use std::env;
    use std::ffi::CString;
    use std::fs::{self, File, OpenOptions};
    use std::io::{self, Read, Seek, SeekFrom, Write};
    use std::os::fd::{AsRawFd, FromRawFd};
    use std::os::unix::ffi::OsStrExt;
    use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
    use std::os::unix::process::CommandExt;
    use std::path::{Path, PathBuf};
    use std::process::{Child, Command, Stdio};
    use std::time::{Duration, Instant};

    const MAX_LOG: usize = 16 * 1024 * 1024;
    const O_CLOEXEC: i32 = 0x80000;
    const O_NOFOLLOW: i32 = 0x20000;
    const O_DIRECTORY: i32 = 0x10000;

    #[repr(C)]
    #[derive(Default)]
    struct CloneArgs {
        flags: u64, pidfd: u64, child_tid: u64, parent_tid: u64,
        exit_signal: u64, stack: u64, stack_size: u64, tls: u64,
        set_tid: u64, set_tid_size: u64, cgroup: u64,
    }

    #[repr(C)]
    struct PollFd { fd: i32, events: i16, revents: i16 }

    extern "C" {
        fn syscall(number: i64, ...) -> i64;
        fn execve(path: *const i8, argv: *const *const i8, env: *const *const i8) -> i32;
        fn _exit(status: i32) -> !;
        fn waitpid(pid: i32, status: *mut i32, options: i32) -> i32;
        fn pipe2(fds: *mut i32, flags: i32) -> i32;
        fn dup2(old: i32, new: i32) -> i32;
        fn poll(fds: *mut PollFd, count: usize, timeout: i32) -> i32;
        fn fstatfs(fd: i32, stat: *mut usize) -> i32;
        fn geteuid() -> u32;
        fn read(fd: i32, bytes: *mut std::ffi::c_void, count: usize) -> isize;
        fn close(fd: i32) -> i32;
        fn fcntl(fd: i32, operation: i32, ...) -> i32;
        fn signal(number: i32, handler: usize) -> usize;
    }

    fn failure(error: impl std::fmt::Display) -> String { error.to_string() }

    fn directory(path: &Path) -> Result<File, String> {
        let file = OpenOptions::new().read(true)
            .custom_flags(O_DIRECTORY | O_NOFOLLOW).open(path).map_err(failure)?;
        let metadata = file.metadata().map_err(failure)?;
        let mut stat = [0_usize; 32];
        if unsafe { fstatfs(file.as_raw_fd(), stat.as_mut_ptr()) } != 0
            || stat[0] != 0x6367_7270
            || metadata.uid() != unsafe { geteuid() }
            || metadata.mode() & 0o022 != 0 {
            return Err("measurement requires an owner-only-writable cgroup-v2 directory".into());
        }
        Ok(file)
    }

    fn control(directory: &File, name: &str, write: bool) -> Result<File, String> {
        OpenOptions::new().read(!write).write(write).custom_flags(O_NOFOLLOW)
            .open(format!("/proc/self/fd/{}/{name}", directory.as_raw_fd())).map_err(failure)
    }

    fn read_text(file: &mut File) -> Result<String, String> {
        file.seek(SeekFrom::Start(0)).map_err(failure)?;
        let mut text = String::new();
        file.take(8193).read_to_string(&mut text).map_err(failure)?;
        if text.len() > 8192 { return Err("cgroup control exceeds bound".into()); }
        Ok(text)
    }

    fn peak(file: &mut File) -> Result<u64, String> {
        read_text(file)?.trim().parse().map_err(failure)
    }

    fn empty(file: &mut File) -> Result<bool, String> {
        let text = read_text(file)?;
        match text.lines().find_map(|line| line.strip_prefix("populated ")) {
            Some("0") => Ok(true), Some("1") => Ok(false),
            _ => Err("invalid cgroup population".into()),
        }
    }

    fn token(value: &str) -> bool {
        value.len() == 32 && value.bytes().all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
    }

    fn own_membership() -> Result<PathBuf, String> {
        let text = fs::read_to_string("/proc/self/cgroup").map_err(failure)?;
        if text.len() > 8192 { return Err("cgroup membership exceeds bound".into()); }
        let relative = text.lines().find_map(|s| s.strip_prefix("0::"))
            .ok_or("cgroup-v2 membership unavailable")?;
        if !relative.starts_with('/') || relative.split('/').any(|s| s == ".." || s == ".") {
            return Err("invalid cgroup membership".into());
        }
        Ok(Path::new("/sys/fs/cgroup").join(relative.trim_start_matches('/')))
    }

    struct Scope {
        path: PathBuf, directory: File, peak: File, kill: File, events: File,
    }

    impl Scope {
        fn create(parent: &Path, name: &str) -> Result<Self, String> {
            let path = parent.join(name);
            fs::create_dir(&path).map_err(failure)?;
            let directory = directory(&path)?;
            let peak = control(&directory, "memory.peak", false)?;
            let kill = control(&directory, "cgroup.kill", true)?;
            let events = control(&directory, "cgroup.events", false)?;
            Ok(Self { path, directory, peak, kill, events })
        }

        fn kill(&mut self) -> Result<(), String> {
            self.kill.write_all(b"1").map_err(failure)
        }

        fn remove(&self) -> Result<(), String> {
            fn remove_tree(path: &Path) -> Result<(), String> {
                let _checked = directory(path)?;
                for entry in fs::read_dir(path).map_err(failure)? {
                    let entry = entry.map_err(failure)?;
                    if entry.file_type().map_err(failure)?.is_dir() { remove_tree(&entry.path())?; }
                }
                fs::remove_dir(path).map_err(failure)
            }
            let saved = self.directory.metadata().map_err(failure)?;
            let current = fs::symlink_metadata(&self.path).map_err(failure)?;
            if saved.dev() != current.dev() || saved.ino() != current.ino() {
                return Err("measurement directory identity changed".into());
            }
            remove_tree(&self.path)
        }
    }

    struct Anchor { child: Child }
    impl Anchor {
        fn start(scope: &Scope) -> Result<Self, String> {
            let kill = scope.kill.try_clone().map_err(failure)?;
            let fd = kill.as_raw_fd();
            let mut command = Command::new(env::current_exe().map_err(failure)?);
            command.arg("--measure-anchor").env_clear().stdin(Stdio::piped())
                .stdout(Stdio::piped()).stderr(Stdio::null());
            unsafe { command.pre_exec(move || {
                if dup2(fd, 3) < 0 || fcntl(3, 2, 0) < 0 { return Err(io::Error::last_os_error()); }
                Ok(())
            }); }
            let mut anchor = Self { child: command.spawn().map_err(failure)? };
            let ready = anchor.child.stdout.as_mut().unwrap();
            let mut pollfd = PollFd { fd: ready.as_raw_fd(), events: 1, revents: 0 };
            if unsafe { poll(&mut pollfd, 1, 5000) } <= 0 { return Err("scope anchor did not start".into()); }
            let mut byte = [0];
            ready.read_exact(&mut byte).map_err(failure)?;
            if byte != [b'A'] { return Err("invalid scope anchor readiness".into()); }
            Ok(anchor)
        }

        fn lease_fd(&self) -> i32 { self.child.stdin.as_ref().unwrap().as_raw_fd() }

        fn finish(&mut self) -> Result<(), String> {
            drop(self.child.stdin.take());
            let deadline = Instant::now() + Duration::from_secs(1);
            loop {
                if let Some(status) = self.child.try_wait().map_err(failure)? {
                    return if status.success() { Ok(()) } else { Err("scope anchor failed".into()) };
                }
                if Instant::now() >= deadline { return Err("scope anchor cleanup unconfirmed".into()); }
                std::thread::sleep(Duration::from_millis(5));
            }
        }
    }
    impl Drop for Anchor {
        fn drop(&mut self) {
            drop(self.child.stdin.take());
            if matches!(self.child.try_wait(), Ok(None)) {
                // The retained Child has not been reaped, so this PID cannot be reused.
                let _ = self.child.kill();
                let _ = self.child.try_wait();
            }
        }
    }

    pub fn anchor() -> Result<(), String> {
        let mut stat = [0_usize; 32];
        if unsafe { fstatfs(3, stat.as_mut_ptr()) } != 0 || stat[0] != 0x6367_7270 {
            return Err("scope anchor requires a retained cgroup descriptor".into());
        }
        let mut kill = unsafe { File::from_raw_fd(3) };
        io::stdout().write_all(b"A").map_err(failure)?;
        io::stdout().flush().map_err(failure)?;
        let mut byte = [0_u8; 256];
        loop {
            let count = unsafe { read(0, byte.as_mut_ptr().cast(), byte.len()) };
            if count == 0 { break; }
            if count < 0 && io::Error::last_os_error().kind() != io::ErrorKind::Interrupted { break; }
        }
        kill.write_all(b"1").map_err(failure)
    }

    fn owner_closed() -> Result<bool, String> {
        let mut consumed = 0;
        loop {
            let mut fd = PollFd { fd: 0, events: 1, revents: 0 };
            let count = unsafe { poll(&mut fd, 1, 0) };
            if count < 0 {
                if io::Error::last_os_error().kind() == io::ErrorKind::Interrupted { continue; }
                return Err("measurement owner poll failed".into());
            }
            if count == 0 { return Ok(false); }
            if fd.revents & 32 != 0 { return Err("invalid measurement owner descriptor".into()); }
            let mut bytes = [0_u8; 4096];
            let count = unsafe { read(0, bytes.as_mut_ptr().cast(), bytes.len()) };
            if count == 0 { return Ok(true); }
            if count < 0 {
                if io::Error::last_os_error().kind() == io::ErrorKind::Interrupted { continue; }
                return Err("measurement owner read failed".into());
            }
            if bytes[..count as usize].contains(&b'C') { return Ok(true); }
            consumed += count;
            if consumed > 65_536 { return Err("measurement control input exceeds bound".into()); }
        }
    }

    struct Lease { scope: Scope, pid: Option<i32>, anchor: Option<Anchor> }
    impl Drop for Lease {
        fn drop(&mut self) {
            let _ = self.scope.kill();
            if let Some(pid) = self.pid.take() {
                let mut status = 0;
                let _ = unsafe { waitpid(pid, &mut status, 1) };
            }
            if let Some(anchor) = self.anchor.as_mut() { let _ = anchor.finish(); }
        }
    }

    fn private_file(path: &Path, bytes: &[u8]) -> Result<(), String> {
        let mut file = OpenOptions::new().write(true).create_new(true)
            .mode(0o600).custom_flags(O_NOFOLLOW).open(path).map_err(failure)?;
        file.write_all(bytes).map_err(failure)?;
        file.sync_all().map_err(failure)
    }

    fn cstring(bytes: &[u8]) -> Result<CString, String> {
        CString::new(bytes).map_err(|_| "NUL in launch argument".into())
    }

    fn launch(scope: &Scope, command: &[String], root: &Path, anchor_lease: i32) -> Result<(i32, File), String> {
        let args = command.iter().map(|s| cstring(s.as_bytes())).collect::<Result<Vec<_>, _>>()?;
        let mut argv = args.iter().map(|s| s.as_ptr()).collect::<Vec<_>>();
        argv.push(std::ptr::null());
        let mut environment = env::vars_os().filter(|(key, _)| {
            !matches!(key.as_bytes(), b"IPSE_MEASURE_ROOT" | b"OPENAI_API_KEY" |
                b"ANTHROPIC_API_KEY" | b"IPSE_CHATGPT_ACCESS_TOKEN")
        }).map(|(key, value)| {
            let mut item = key.as_bytes().to_vec(); item.push(b'='); item.extend(value.as_bytes()); cstring(&item)
        }).collect::<Result<Vec<_>, _>>()?;
        let mut root_env = b"IPSE_MEASURE_ROOT=".to_vec(); root_env.extend(root.as_os_str().as_bytes());
        environment.push(cstring(&root_env)?);
        let mut envp = environment.iter().map(|s| s.as_ptr()).collect::<Vec<_>>(); envp.push(std::ptr::null());
        let null = File::open("/dev/null").map_err(failure)?;
        let mut fds = [-1_i32; 2];
        if unsafe { pipe2(fds.as_mut_ptr(), O_CLOEXEC) } != 0 { return Err(failure(io::Error::last_os_error())); }
        let read = unsafe { File::from_raw_fd(fds[0]) };
        let write = unsafe { File::from_raw_fd(fds[1]) };
        let clone = CloneArgs { flags: 1_u64 << 33, exit_signal: 17,
            cgroup: scope.directory.as_raw_fd() as u64, ..Default::default() };
        let pid = unsafe { syscall(435, &clone, std::mem::size_of::<CloneArgs>()) };
        if pid < 0 { return Err(format!("clone-into-cgroup unavailable: {}", io::Error::last_os_error())); }
        if pid == 0 {
            unsafe {
                if close(anchor_lease) < 0 || signal(13, 0) == usize::MAX || signal(17, 0) == usize::MAX { _exit(126); }
                if dup2(null.as_raw_fd(), 0) < 0 || dup2(write.as_raw_fd(), 1) < 0 || dup2(write.as_raw_fd(), 2) < 0 { _exit(126); }
                execve(args[0].as_ptr(), argv.as_ptr(), envp.as_ptr());
                _exit(127);
            }
        }
        drop(write);
        Ok((pid as i32, read))
    }

    fn parent(role: &str, id: &str) -> Result<(PathBuf, Option<File>), String> {
        let current = own_membership()?;
        if role == "root" {
            if current.file_name().and_then(|s| s.to_str()) != Some(&format!("ipse-measure-{id}.service")) {
                return Err("root collector requires its dedicated delegated user service".into());
            }
            let root = directory(&current)?;
            let members = read_text(&mut control(&root, "cgroup.procs", false)?)?;
            if members.trim() != std::process::id().to_string() {
                return Err("measurement service is not exclusively owned".into());
            }
            let collector = current.join(format!("collector-{id}"));
            fs::create_dir(&collector).map_err(failure)?;
            let collector = directory(&collector)?;
            control(&collector, "cgroup.procs", true)?.write_all(b"0").map_err(failure)?;
            control(&root, "cgroup.subtree_control", true)?.write_all(b"+memory").map_err(failure)?;
            Ok((current, None))
        } else {
            let parent = PathBuf::from(env::var_os("IPSE_MEASURE_ROOT").ok_or("missing parent measurement scope")?);
            let name = parent.file_name().and_then(|s| s.to_str()).ok_or("invalid parent scope")?;
            if !name.strip_prefix("ipse-run-").is_some_and(token)
                || !current.starts_with(&parent) || current == parent {
                return Err("collector is outside its parent measurement".into());
            }
            let checked = directory(&parent)?;
            let mut interval = OpenOptions::new().read(true).write(true).custom_flags(O_NOFOLLOW)
                .open(format!("/proc/self/fd/{}/memory.peak", checked.as_raw_fd())).map_err(failure)?;
            interval.write_all(b"1").map_err(failure)?;
            Ok((parent, Some(interval)))
        }
    }

    pub fn run(args: &[String]) -> Result<(), String> {
        if args.len() < 8 || args[6] != "--" || !matches!(args[2].as_str(), "root" | "cell")
            || !token(&args[3]) || !Path::new(&args[7]).is_absolute()
            || args.len() > 128 || args.iter().map(String::len).sum::<usize>() > 65_536 {
            return Err("usage: --measure-cgroup root|cell TOKEN TIMEOUT_MS OUTPUT -- ABSOLUTE_COMMAND ARGS".into());
        }
        let role = &args[2]; let id = &args[3];
        if unsafe { signal(17, 0) } == usize::MAX { return Err("cannot retain measurement children".into()); }
        let timeout: u64 = args[4].parse().map_err(|_| "invalid measurement timeout")?;
        if !(1..=86_400_000).contains(&timeout) { return Err("invalid measurement timeout".into()); }
        let output = PathBuf::from(&args[5]);
        if !output.is_absolute() { return Err("measurement output must be absolute".into()); }
        if owner_closed()? { return Err("measurement owner closed before admission".into()); }
        let (parent, mut interval) = parent(role, id)?;
        fs::DirBuilder::new().mode(0o700).create(&output).map_err(failure)?;
        let name = format!("{}-{id}", if role == "root" { "ipse-run" } else { "cell" });
        let scope = Scope::create(&parent, &name)?;
        let mut lease = Lease { scope, pid: None, anchor: None };
        let root = if role == "root" { lease.scope.path.clone() } else { parent };
        lease.anchor = Some(Anchor::start(&lease.scope)?);
        private_file(&output.join("started.json"), format!("{{\"version\":1,\"token\":\"{id}\",\"role\":\"{role}\",\"collector_pid\":{},\"anchor_pid\":{},\"scope_inode\":{},\"scope_device\":{}}}\n",
            std::process::id(), lease.anchor.as_ref().unwrap().child.id(), lease.scope.directory.metadata().map_err(failure)?.ino(), lease.scope.directory.metadata().map_err(failure)?.dev()).as_bytes())?;
        File::open(&output).and_then(|f| f.sync_all()).map_err(failure)?;
        let workload = if role == "root" {
            control(&lease.scope.directory, "cgroup.subtree_control", true)?.write_all(b"+memory").map_err(failure)?;
            Some(Scope::create(&lease.scope.path, "application")?)
        } else { None };
        if owner_closed()? { return Err("measurement owner closed before launch".into()); }
        let (pid, mut child_output) = launch(workload.as_ref().unwrap_or(&lease.scope), &args[7..], &root,
            lease.anchor.as_ref().unwrap().lease_fd())?;
        lease.pid = Some(pid);
        let mut log = OpenOptions::new().write(true).create_new(true).mode(0o600)
            .open(output.join("process.log")).map_err(failure)?;
        let start = Instant::now();
        let mut logged = 0; let mut status = None; let mut reason = "completed";
        let mut stopped_at = None; let mut cleanup = false; let mut output_open = true;
        let mut log_truncated = false;
        loop {
            if stopped_at.is_none() && owner_closed()? {
                reason = "owner_closed"; lease.scope.kill()?; stopped_at = Some(Instant::now());
            }
            if stopped_at.is_none() && lease.anchor.as_mut().unwrap().child.try_wait().map_err(failure)?.is_some() {
                reason = "anchor_lost"; lease.scope.kill()?; stopped_at = Some(Instant::now());
            }
            if status.is_none() {
                let mut raw = 0;
                let result = unsafe { waitpid(pid, &mut raw, 1) };
                if result == pid { status = Some(raw); lease.pid = None; }
                else if result < 0 && io::Error::last_os_error().kind() != io::ErrorKind::Interrupted {
                    return Err("measurement child reap failed".into());
                }
            }
            if status.is_some() && stopped_at.is_none() {
                if !empty(&mut lease.scope.events)? {
                    reason = "residual_descendants"; lease.scope.kill()?;
                }
                stopped_at = Some(Instant::now());
            }
            if stopped_at.is_none() && start.elapsed() >= Duration::from_millis(timeout) {
                reason = "timeout"; lease.scope.kill()?; stopped_at = Some(Instant::now());
            }
            if status.is_some() && empty(&mut lease.scope.events)? {
                cleanup = true;
                if !output_open { break; }
                if stopped_at.is_some_and(|t| t.elapsed() >= Duration::from_millis(500)) { break; }
            }
            if stopped_at.is_some_and(|t| t.elapsed() >= Duration::from_secs(5)) { break; }
            let mut fds = [PollFd { fd: if output_open { child_output.as_raw_fd() } else { -1 }, events: 1, revents: 0 }];
            let polled = unsafe { poll(fds.as_mut_ptr(), fds.len(), 10) };
            if polled < 0 && io::Error::last_os_error().kind() != io::ErrorKind::Interrupted { return Err("measurement poll failed".into()); }
            if fds[0].revents & (1 | 8 | 16) != 0 {
                let mut bytes = [0_u8; 8192];
                match child_output.read(&mut bytes) {
                    Ok(0) => output_open = false,
                    Ok(n) => {
                        let keep = n.min(MAX_LOG - logged);
                        log_truncated |= keep < n;
                        log.write_all(&bytes[..keep]).map_err(failure)?; logged += keep;
                    }
                    Err(error) if error.kind() == io::ErrorKind::Interrupted => (),
                    Err(_) => return Err("measurement output read failed".into()),
                }
            }
        }
        let bytes = peak(&mut lease.scope.peak)?;
        lease.anchor.as_mut().unwrap().finish()?;
        let parent_peak = match interval.as_mut() { Some(fd) => peak(fd)?.to_string(), None => "null".into() };
        let raw = status.unwrap_or(-1);
        let code = if raw < 0 { -1 } else if raw & 127 == 0 { (raw >> 8) & 255 } else { 128 + (raw & 127) };
        let complete = cleanup && code == 0 && reason == "completed";
        log.sync_all().map_err(failure)?;
        let record = format!("{{\"version\":1,\"metric\":\"linux_memcg_charged_peak_bytes_v1\",\"token\":\"{id}\",\"role\":\"{role}\",\"peak_bytes\":{bytes},\"parent_interval_peak_bytes\":{parent_peak},\"born_in_scope\":true,\"cleanup_confirmed\":{cleanup},\"exit_code\":{code},\"reason\":\"{reason}\",\"complete\":{complete},\"log_bytes\":{logged},\"log_truncated\":{log_truncated}}}\n");
        private_file(&output.join("receipt.json"), record.as_bytes())?;
        File::open(&output).and_then(|f| f.sync_all()).map_err(failure)?;
        if cleanup { lease.scope.remove()?; }
        crate::frame(b'M', record.as_bytes()).map_err(failure)
    }

    use std::os::unix::fs::DirBuilderExt;
}

pub fn run(args: &[String]) -> Result<(), String> {
    #[cfg(all(target_os = "linux", any(target_arch = "x86_64", target_arch = "aarch64")))]
    { linux::run(args) }
    #[cfg(not(all(target_os = "linux", any(target_arch = "x86_64", target_arch = "aarch64"))))]
    { let _ = args; Err("exact aggregate memory requires supported Linux cgroup-v2 capabilities".into()) }
}

pub fn anchor() -> Result<(), String> {
    #[cfg(all(target_os = "linux", any(target_arch = "x86_64", target_arch = "aarch64")))]
    { linux::anchor() }
    #[cfg(not(all(target_os = "linux", any(target_arch = "x86_64", target_arch = "aarch64"))))]
    { Err("measurement anchor requires supported Linux".into()) }
}
