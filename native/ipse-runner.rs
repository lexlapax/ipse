//! Dependency-free Unix shell supervisor. See native/README.md for the protocol.
use std::env;
use std::fs::{OpenOptions, Permissions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::os::unix::io::AsRawFd;
#[cfg(target_os = "linux")]
use std::os::unix::process::CommandExt;
use std::os::unix::process::ExitStatusExt;
use std::process::{Command, Stdio};
use std::sync::{mpsc, Arc, Mutex};
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, Instant};
#[cfg(target_os = "linux")]
#[path = "ipse-linux-sandbox.rs"]
mod ipse_linux_sandbox;
#[cfg(target_os = "macos")]
#[path = "ipse-macos-sandbox.rs"]
mod ipse_macos_sandbox;
#[path = "ipse-stdio.rs"]
mod ipse_stdio;
#[path = "ipse-process-group.rs"]
mod process_group;
#[path = "ipse-measure.rs"]
mod ipse_measure;
#[path = "ipse-sequence.rs"]
mod ipse_sequence;
use process_group::{signal_group, GroupGuard};

extern "C" {
    fn flock(fd: i32, operation: i32) -> i32;
    fn geteuid() -> u32;
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
    if args.len() == 2 && args[1] == "--measure-anchor" { return ipse_measure::anchor(); }
    if args.get(1).is_some_and(|arg| arg == "--measure-sequence") { return ipse_sequence::run(&args); }
    if args.get(1).is_some_and(|arg| arg == "--measure-stage") { return ipse_measure::stage(&args); }
    if args.get(1).is_some_and(|arg| arg == "--measure-cgroup") { return ipse_measure::run(&args); }
    if args.len() == 2 && args[1] == "--group-anchor" {
        return process_group::run_anchor().map_err(|_| "process-group owner failed".into());
    }
    if args.len() == 2 && args[1] == "--uid" { println!("{}", unsafe { geteuid() }); return Ok(()); }
    #[cfg(target_os = "macos")]
    {
        if args.len() == 4 && args[1] == "--macos-entitlements" {
            print!("{}", ipse_macos_sandbox::entitlements(&args[2], &args[3])?);
            return Ok(());
        }
        if args.len() >= 3 && args[1] == "--codesign" {
            return Err(format!("cannot execute codesign: {}", ipse_macos_sandbox::codesign_exec(&args[2..])));
        }
        if args.len() >= 2 && (args[1] == "--macos-worker" || args[1] == "--macos-worker-stdio") {
            if let Err(error) = ipse_macos_sandbox::worker(&args) {
                eprintln!("macOS sandbox worker: {error}");
                std::process::exit(1);
            }
            return Ok(());
        }
    }
    if args.len() == 3 && args[1] == "--lock" { return lock_file(&args[2]); }
    if args.get(1).is_some_and(|arg|arg=="--stdio" || arg=="--stdio-listener") {return ipse_stdio::run(&args);}
    let (sandboxed, offset) = if args.len() == 8 && args[1] == "--sandbox" && args[2] == "macos-workspace-v1" {
        #[cfg(not(target_os = "macos"))]
        return Err("macos-workspace-v1 requires macOS".into());
        #[cfg(target_os = "macos")]
        (true, 5)
    } else if args.len() == 6 && args[1] == "--sandbox" {
        if args[2] != "linux-workspace-v1" {return Err("unsupported sandbox profile".into());}
        (true, 3)
    } else if args.len() == 4 { (false, 1) }
    else {return Err("usage: ipse-runner [--sandbox linux-workspace-v1] CWD TIMEOUT_MS COMMAND".into());};
    let timeout: u64 = args[offset+1].parse().map_err(|_| "invalid timeout")?;
    #[cfg(not(target_os = "linux"))]
    if sandboxed && args[2] == "linux-workspace-v1" { return Err("linux-workspace-v1 requires Linux".into()); }
    let cancelled = Arc::new(AtomicBool::new(false));
    let child_slot = Arc::new(Mutex::new(None::<i32>));
    let owner_cancelled = cancelled.clone();
    let owner_child = child_slot.clone();
    // Watch owner death during signature verification as well as command execution.
    thread::spawn(move || {
        let mut input = io::stdin();
        let mut buffer = [0u8; 256];
        loop {
            match input.read(&mut buffer) {
                Ok(0) => break,
                Ok(size) if buffer[..size].contains(&b'C') => break,
                Ok(_) => (),
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => break,
            }
        }
        owner_cancelled.store(true, Ordering::SeqCst);
        signal_group(&owner_child);
    });
    // Declared before the group guard: reverse drop order kills descendants
    // before removing the sandbox's private directories on every return path.
    #[cfg(target_os = "linux")]
    let sandbox = if sandboxed {
        debug_assert_eq!(ipse_linux_sandbox::PROFILE, args[2]);
        Some(std::sync::Arc::new(ipse_linux_sandbox::prepare(std::path::Path::new(&args[offset]),Duration::from_millis(timeout))?))
    } else {None};
    #[cfg(target_os = "macos")]
    let mut macos = if sandboxed {
        debug_assert_eq!(ipse_macos_sandbox::PROFILE, args[2]);
        Some(ipse_macos_sandbox::prepare(&args[3], &args[offset], &args[4], timeout,
            &args[offset+2], &cancelled)?)
    } else { None };
    let mut plain_command = Command::new("/bin/sh");
    plain_command.arg("-c").arg(&args[offset+2]);
    #[cfg(target_os = "macos")]
    let command = match &mut macos { Some(policy) => &mut policy.command, None => &mut plain_command };
    #[cfg(not(target_os = "macos"))]
    let command = &mut plain_command;
    command.current_dir(&args[offset])
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
    let cleanup = GroupGuard::start(child_slot.clone())
        .map_err(|_| "cannot start process-group owner")?;
    cleanup.attach(command);
    #[cfg(target_os = "linux")]
    let child_sandbox = sandbox.clone();
    #[cfg(target_os = "linux")]
    unsafe {
        command.pre_exec(move || {
            if let Some(policy) = &child_sandbox {policy.apply()?;}
            Ok(())
        });
    }
    let slot = child_slot.lock().unwrap();
    if cancelled.load(Ordering::SeqCst) { return Err("shell owner disconnected before launch".into()); }
    let mut child = command.spawn().map_err(|e| format!("cannot start shell: {e}"))?;
    drop(slot);
    // The owner watcher kills this group even while output delivery is blocked.
    let (tx, rx) = mpsc::sync_channel(32);
    reader(child.stdout.take().unwrap(), tx.clone());
    reader(child.stderr.take().unwrap(), tx.clone());
    drop(tx);
    let start = Instant::now();
    let mut timed_out = false;
    let mut status = None;
    let mut drain_deadline = None;
    let mut disconnected = false;
    loop {
        if status.is_none() {
            if start.elapsed() >= Duration::from_millis(timeout) {
                timed_out = true;
                signal_group(&child_slot);
            }
            status = match child.try_wait() {
                Ok(status) => status,
                Err(error) => {
                    let _ = frame(b'U', format!("cannot confirm shell outcome: {error}").as_bytes());
                    return Ok(());
                }
            };
            // Stop remaining group members when the initial child exits.
            if status.is_some() {
                signal_group(&child_slot);
                drain_deadline = Some(Instant::now() + Duration::from_millis(500));
            }
        }
        // Detached descendants may retain the output pipes. Completion stays bounded.
        if drain_deadline.is_some_and(|deadline| Instant::now() >= deadline) { break; }
        if status.is_some() && disconnected { break; }
        match rx.recv_timeout(Duration::from_millis(10)) {
            Ok(bytes) => if frame(b'O', &bytes).is_err() {
                signal_group(&child_slot);
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
