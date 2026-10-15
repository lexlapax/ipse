//! Dependency-free Unix shell supervisor. See native/README.md for the protocol.
use std::env;
use std::fs::{OpenOptions, Permissions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::os::unix::io::AsRawFd;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};
#[cfg(target_os = "linux")]
#[path = "ipse-linux-sandbox.rs"]
mod ipse_linux_sandbox;

extern "C" {
    fn setpgid(pid: i32, pgid: i32) -> i32;
    fn kill(pid: i32, signal: i32) -> i32;
    fn flock(fd: i32, operation: i32) -> i32;
}
fn kill_group(pid: i32) { unsafe { kill(-pid, 9); } }
struct GroupGuard(i32);
impl Drop for GroupGuard {
    fn drop(&mut self) { kill_group(self.0); }
}
fn frame(kind: u8, bytes: &[u8]) -> io::Result<()> {
    let mut out = io::stdout().lock();
    out.write_all(&[kind])?;
    out.write_all(&(bytes.len() as u32).to_be_bytes())?;
    out.write_all(bytes)?;
    out.flush()
}
fn reader<R: Read + Send + 'static>(mut input: R, tx: mpsc::SyncSender<Vec<u8>>) {
    thread::spawn(move || {
        let mut buf = [0u8; 8192];
        loop {
            match input.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => if tx.send(buf[..n].to_vec()).is_err() { break; },
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => break,
            }
        }
    });
}
fn lock_file(path: &str) -> Result<(), String> {
    #[cfg(target_os = "linux")]
    let nofollow = 0x20000;
    #[cfg(target_os = "macos")]
    let nofollow = 0x100;
    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    let nofollow = 0;
    let file = OpenOptions::new().read(true).write(true).create(true)
        .mode(0o600).custom_flags(nofollow).open(path)
        .map_err(|e| format!("cannot open session lock: {e}"))?;
    // LOCK_EX | LOCK_NB: the kernel releases this lock on process termination.
    if unsafe { flock(file.as_raw_fd(), 2 | 4) } == -1 {
        return Err(format!("cannot acquire session lock (session may already be open): {}", io::Error::last_os_error()));
    }
    file.set_permissions(Permissions::from_mode(0o600))
        .map_err(|e| format!("cannot secure session lock: {e}"))?;
    frame(b'L', b"locked").map_err(|e| format!("cannot report session lock: {e}"))?;
    let mut input = io::stdin();
    let mut buf = [0u8; 256];
    loop {
        match input.read(&mut buf) {
            Ok(0) => break,
            Ok(_) => break,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(_) => break,
        }
    }
    drop(file);
    let _ = frame(b'U', b"unlocked");
    Ok(())
}
fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().collect();
    if args.len() == 3 && args[1] == "--lock" { return lock_file(&args[2]); }
    let (sandboxed, offset) = if args.len() == 6 && args[1] == "--sandbox" {
        if args[2] != "linux-workspace-v1" {return Err("unsupported sandbox profile".into());}
        (true, 3)
    } else if args.len() == 4 { (false, 1) }
    else {return Err("usage: ipse-runner [--sandbox linux-workspace-v1] CWD TIMEOUT_MS COMMAND".into());};
    let timeout: u64 = args[offset+1].parse().map_err(|_| "invalid timeout")?;
    #[cfg(not(target_os = "linux"))]
    if sandboxed { return Err("linux-workspace-v1 requires Linux".into()); }
    // Declared before the group guard: reverse drop order kills descendants
    // before removing the sandbox's private directories on every return path.
    #[cfg(target_os = "linux")]
    let sandbox = if sandboxed {
        debug_assert_eq!(ipse_linux_sandbox::PROFILE, args[2]);
        Some(std::sync::Arc::new(ipse_linux_sandbox::prepare(std::path::Path::new(&args[offset]),Duration::from_millis(timeout))?))
    } else {None};
    let mut command = Command::new("/bin/sh");
    command.arg("-c").arg(&args[offset+2]).current_dir(&args[offset])
        .stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped());
    if sandboxed {
        command.env_clear().env("PATH","/usr/bin:/bin").env("LANG","C.UTF-8");
        #[cfg(target_os = "linux")]
        if let Some(policy) = &sandbox {
            command.env("HOME",policy.temp_dir()).env("TMPDIR",policy.temp_dir());
        }
    } else {
        for key in ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "IPSE_CHATGPT_ACCESS_TOKEN"] {
            command.env_remove(key);
        }
    }
    #[cfg(target_os = "linux")]
    let child_sandbox = sandbox.clone();
    unsafe {
        command.pre_exec(move || {
            if setpgid(0, 0) == -1 { return Err(io::Error::last_os_error()); }
            #[cfg(target_os = "linux")]
            if let Some(policy) = &child_sandbox {policy.apply()?;}
            Ok(())
        });
    }
    let mut child = command.spawn().map_err(|e| format!("cannot start shell: {e}"))?;
    let pid = child.id() as i32;
    let _cleanup = GroupGuard(pid);
    // The Elixir Port keeps this pipe open. Closing/crashing the owner terminates
    // the complete shell process group, even if the supervisor is blocked writing.
    thread::spawn(move || {
        let mut stdin = io::stdin();
        let mut buf = [0u8; 256];
        loop {
            match stdin.read(&mut buf) {
                Ok(0) => { kill_group(pid); break; },
                Ok(_) => (),
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => { kill_group(pid); break; },
            }
        }
    });
    let (tx, rx) = mpsc::sync_channel(32);
    reader(child.stdout.take().unwrap(), tx.clone());
    reader(child.stderr.take().unwrap(), tx.clone());
    drop(tx);
    let start = Instant::now();
    let mut timed_out = false;
    let mut status = None;
    let mut disconnected = false;
    loop {
        if status.is_none() {
            if start.elapsed() >= Duration::from_millis(timeout) {
                timed_out = true;
                kill_group(pid);
            }
            status = child.try_wait().map_err(|e| format!("cannot wait for shell: {e}"))?;
            // Background jobs must not survive their shell or hold output open.
            if status.is_some() { kill_group(pid); }
        }
        if status.is_some() && disconnected { break; }
        match rx.recv_timeout(Duration::from_millis(10)) {
            Ok(bytes) => if frame(b'O', &bytes).is_err() {
                kill_group(pid);
                let _ = child.wait();
                return Ok(());
            },
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                disconnected = true;
                if status.is_none() { thread::sleep(Duration::from_millis(5)); }
            },
            Err(mpsc::RecvTimeoutError::Timeout) => (),
        }
    }
    let status = status.unwrap();
    let code = status.code().unwrap_or_else(|| 128 + status.signal().unwrap_or(0));
    let result = format!("{{\"exit_code\":{code},\"timed_out\":{timed_out}}}");
    let _ = frame(b'X', result.as_bytes());
    Ok(())
}
fn main() {
    if let Err(error) = run() {
        let _ = frame(b'E', error.as_bytes());
        std::process::exit(1);
    }
}
