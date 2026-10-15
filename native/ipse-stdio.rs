//! Bidirectional pipes and process-group lifetime for directly executed servers.
use super::{frame, kill_group, setpgid, GroupGuard};
use std::io::{self, Read, Write};
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::{mpsc, Arc};
use std::thread;
use std::time::{Duration, Instant};

const CHUNK: usize = 8192;
const INPUT_CHUNKS: usize = 128;
const OUTPUT_CHUNKS: usize = 32;
const DRAIN: Duration = Duration::from_millis(500);

#[path = "ipse-environment.rs"]
mod child_environment;

fn launch_environment() -> Result<Vec<(String, String)>, String> {
    #[repr(C)]
    struct PollFd {
        fd: i32,
        events: i16,
        revents: i16,
    }
    #[cfg(target_os = "macos")]
    type Nfds = u32;
    #[cfg(not(target_os = "macos"))]
    type Nfds = usize;
    extern "C" {
        fn poll(fds: *mut PollFd, count: Nfds, timeout: i32) -> i32;
        fn read(fd: i32, bytes: *mut std::ffi::c_void, count: usize) -> isize;
    }
    let deadline = Instant::now() + Duration::from_secs(5);
    let exact = |mut bytes: &mut [u8]| -> Result<(), String> {
        while !bytes.is_empty() {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Err("stdio launch timed out".into());
            }
            let mut fd = PollFd {
                fd: 0,
                events: 1,
                revents: 0,
            };
            let ready = unsafe { poll(&mut fd, 1, remaining.as_millis().min(5000) as i32) };
            if ready < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
                continue;
            }
            if ready <= 0 {
                return Err("stdio launch unavailable".into());
            }
            let size = unsafe { read(0, bytes.as_mut_ptr().cast(), bytes.len()) };
            if size < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
                continue;
            }
            if size <= 0 {
                return Err("stdio launch unavailable".into());
            }
            bytes = &mut bytes[size as usize..];
        }
        Ok(())
    };
    let mut header = [0u8; 5];
    exact(&mut header)?;
    let size = u32::from_be_bytes(header[1..].try_into().unwrap()) as usize;
    if header[0] != b'L' || size > 134_144 {
        return Err("invalid launch environment".into());
    }
    let mut bytes = vec![0u8; size];
    exact(&mut bytes)?;
    child_environment::decode_environment(&bytes)
}

fn output_reader<R: Read + Send + 'static>(
    mut input: R,
    kind: u8,
    tx: mpsc::SyncSender<(u8, Vec<u8>)>,
) {
    thread::spawn(move || {
        let mut bytes = [0u8; CHUNK];
        loop {
            match input.read(&mut bytes) {
                Ok(0) => break,
                Ok(count) => {
                    if tx.send((kind, bytes[..count].to_vec())).is_err() {
                        break;
                    }
                }
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => {
                    let _ = tx.send((b'E', b"stdio output read failed".to_vec()));
                    break;
                }
            }
        }
    });
}

fn input_reader() -> (
    mpsc::Receiver<Vec<u8>>,
    Arc<AtomicU8>,
    Arc<AtomicBool>,
    Arc<std::sync::Mutex<Option<i32>>>,
) {
    let failure = Arc::new(AtomicU8::new(0));
    let (input_tx, input_rx) = mpsc::sync_channel::<Vec<u8>>(INPUT_CHUNKS);
    let input_failure = failure.clone();
    let cancelled = Arc::new(AtomicBool::new(false));
    let slot = Arc::new(std::sync::Mutex::new(None::<i32>));
    let reader_slot = slot.clone();
    let reader_cancelled = cancelled.clone();
    thread::spawn(move || {
        let mut owner = io::stdin();
        let mut bytes = [0u8; CHUNK];
        'frames: loop {
            let mut header = [0u8; 5];
            match owner.read(&mut header[..1]) {
                Ok(0) => {
                    reader_cancelled.store(true, Ordering::SeqCst);
                    if let Some(pid) = *reader_slot.lock().unwrap() {
                        kill_group(pid);
                    }
                    break;
                }
                Ok(_) => (),
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => {
                    input_failure.store(2, Ordering::Release);
                    reader_cancelled.store(true, Ordering::SeqCst);
                    if let Some(pid) = *reader_slot.lock().unwrap() {
                        kill_group(pid);
                    }
                    break;
                }
            }
            if owner.read_exact(&mut header[1..]).is_err() {
                input_failure.store(2, Ordering::Release);
                reader_cancelled.store(true, Ordering::SeqCst);
                if let Some(pid) = *reader_slot.lock().unwrap() {
                    kill_group(pid);
                }
                break;
            }
            let mut remaining =
                u32::from_be_bytes([header[1], header[2], header[3], header[4]]) as usize;
            if header[0] == b'C' && remaining == 0 {
                reader_cancelled.store(true, Ordering::SeqCst);
                if let Some(pid) = *reader_slot.lock().unwrap() {
                    kill_group(pid);
                }
                break;
            }
            if header[0] != b'I' || remaining > 1_048_576 {
                input_failure.store(2, Ordering::Release);
                reader_cancelled.store(true, Ordering::SeqCst);
                if let Some(pid) = *reader_slot.lock().unwrap() {
                    kill_group(pid);
                }
                break;
            }
            while remaining > 0 {
                let count = remaining.min(CHUNK);
                if owner.read_exact(&mut bytes[..count]).is_err() {
                    input_failure.store(2, Ordering::Release);
                    reader_cancelled.store(true, Ordering::SeqCst);
                    if let Some(pid) = *reader_slot.lock().unwrap() {
                        kill_group(pid);
                    }
                    break 'frames;
                }
                match input_tx.try_send(bytes[..count].to_vec()) {
                    Ok(()) => (),
                    Err(mpsc::TrySendError::Full(_)) => {
                        input_failure.store(1, Ordering::Release);
                        reader_cancelled.store(true, Ordering::SeqCst);
                        if let Some(pid) = *reader_slot.lock().unwrap() {
                            kill_group(pid);
                        }
                        break 'frames;
                    }
                    Err(mpsc::TrySendError::Disconnected(_)) => {
                        reader_cancelled.store(true, Ordering::SeqCst);
                        if let Some(pid) = *reader_slot.lock().unwrap() {
                            kill_group(pid);
                        }
                        break 'frames;
                    }
                }
                remaining -= count;
            }
        }
    });
    (input_rx, failure, cancelled, slot)
}

pub fn run(args: &[String]) -> Result<(), String> {
    if args.len() < 5 {
        return Err("usage: ipse-runner --stdio CWD TIMEOUT_MS EXECUTABLE [ARGS...]".into());
    }
    let timeout: u64 = args[3].parse().map_err(|_| "invalid stdio timeout")?;
    if timeout == 0 || timeout > 86_400_000 {
        return Err("stdio timeout must be between 1 and 86400000 ms".into());
    }
    if args.len() > 261 || args.iter().map(String::len).sum::<usize>() > 131072 {
        return Err("stdio launch arguments exceed limit".into());
    }
    let selected = launch_environment()?;
    let (input_rx, failure, cancelled, slot) = input_reader();
    let sandboxed = args[4] == "--sandbox";
    let mut executable = 4;
    if sandboxed {
        if args.len() < 7 {
            return Err("invalid stdio sandbox arguments".into());
        }
        match args[5].as_str() {
            #[cfg(target_os = "linux")]
            "linux-workspace-v1" => executable = 6,
            #[cfg(target_os = "macos")]
            "macos-workspace-v1" => executable = 8,
            _ => return Err("unsupported stdio sandbox profile".into()),
        }
        if args.len() <= executable {
            return Err("invalid stdio sandbox arguments".into());
        }
    }
    #[cfg(target_os = "linux")]
    let sandbox = if sandboxed {
        Some(Arc::new(super::ipse_linux_sandbox::prepare(
            std::path::Path::new(&args[2]),
            Duration::from_millis(timeout),
        )?))
    } else {
        None
    };
    #[cfg(target_os = "macos")]
    let mut macos = if sandboxed {
        Some(super::ipse_macos_sandbox::prepare_stdio(
            &args[6],
            &args[2],
            &args[7],
            timeout,
            &args[executable..],
            &selected,
            &cancelled,
        )?)
    } else {
        None
    };
    let mut plain_command = Command::new(&args[executable]);
    plain_command
        .args(&args[executable + 1..])
        .env_clear()
        .envs(selected);
    #[cfg(target_os = "linux")]
    if let Some(policy) = &sandbox {
        plain_command
            .env("HOME", policy.temp_dir())
            .env("TMPDIR", policy.temp_dir());
    }
    #[cfg(target_os = "macos")]
    let command = match &mut macos {
        Some(policy) => &mut policy.command,
        None => &mut plain_command,
    };
    #[cfg(not(target_os = "macos"))]
    let command = &mut plain_command;
    command
        .current_dir(&args[2])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    #[cfg(target_os = "linux")]
    let child_sandbox = sandbox.clone();
    unsafe {
        command.pre_exec(move || {
            if setpgid(0, 0) < 0 {
                return Err(io::Error::last_os_error());
            }
            #[cfg(target_os = "linux")]
            if let Some(policy) = &child_sandbox {
                policy.apply()?;
            }
            Ok(())
        });
    }
    let mut child_slot = slot.lock().unwrap();
    if cancelled.load(Ordering::SeqCst) {
        return Err("stdio owner disconnected before launch".into());
    }
    let mut child = command.spawn().map_err(|_| "cannot start stdio server")?;
    let pid = child.id() as i32;
    *child_slot = Some(pid);
    drop(child_slot);
    let _cleanup = GroupGuard(pid);
    let finished = Arc::new(AtomicBool::new(false));
    let timed_out = Arc::new(AtomicBool::new(false));
    let watchdog_finished = finished.clone();
    let watchdog_timeout = timed_out.clone();
    let started = Instant::now();
    // A separate watchdog owns the deadline even if stdout delivery is blocked.
    thread::spawn(move || {
        while !watchdog_finished.load(Ordering::Acquire)
            && started.elapsed() < Duration::from_millis(timeout)
        {
            thread::sleep(Duration::from_millis(5));
        }
        if watchdog_finished.load(Ordering::Acquire) {
            return;
        }
        watchdog_timeout.store(true, Ordering::Release);
        kill_group(pid);
        let grace = Instant::now();
        while !watchdog_finished.load(Ordering::Acquire) && grace.elapsed() < Duration::from_secs(1)
        {
            thread::sleep(Duration::from_millis(5));
        }
        if !watchdog_finished.load(Ordering::Acquire) {
            kill_group(pid);
            std::process::exit(1);
        }
    });
    let mut child_input = child.stdin.take().ok_or("stdio server input unavailable")?;
    let write_failure = failure.clone();
    thread::spawn(move || {
        for bytes in input_rx {
            if child_input.write_all(&bytes).is_err() {
                let _ = write_failure.compare_exchange(0, 2, Ordering::AcqRel, Ordering::Acquire);
                kill_group(pid);
                break;
            }
        }
    });
    let (output_tx, output_rx) = mpsc::sync_channel(OUTPUT_CHUNKS);
    output_reader(
        child
            .stdout
            .take()
            .ok_or("stdio server output unavailable")?,
        b'O',
        output_tx.clone(),
    );
    output_reader(
        child
            .stderr
            .take()
            .ok_or("stdio server errors unavailable")?,
        b'S',
        output_tx,
    );
    let mut status = None;
    let mut drain_deadline = None;
    let mut disconnected = false;
    let mut cleanup_pending = false;
    loop {
        if status.is_none() {
            status = child
                .try_wait()
                .map_err(|_| "cannot wait for stdio server")?;
            if status.is_some() {
                cleanup_pending = unsafe { super::kill(-pid, 9) } == 0;
                drain_deadline = Some(Instant::now() + DRAIN);
            }
        }
        if status.is_some() && disconnected {
            break;
        }
        if drain_deadline.is_some_and(|deadline| Instant::now() >= deadline) {
            frame(b'E', b"stdio output did not drain")
                .map_err(|_| "stdio output delivery failed")?;
            finished.store(true, Ordering::Release);
            return Ok(());
        }
        match output_rx.recv_timeout(Duration::from_millis(5)) {
            Ok((kind, bytes)) => {
                if frame(kind, &bytes).is_err() {
                    kill_group(pid);
                    let _ = child.wait();
                    return Ok(());
                }
                if kind == b'E' {
                    kill_group(pid);
                    finished.store(true, Ordering::Release);
                    return Ok(());
                }
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                disconnected = true;
                if status.is_none() {
                    thread::sleep(Duration::from_millis(5));
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {
                // A descendant can fork while the first group signal is being
                // delivered. Retry only during the original bounded drain and
                // stop once the group is gone; detached children remain outside it.
                if cleanup_pending {
                    cleanup_pending = unsafe { super::kill(-pid, 9) } == 0;
                }
            }
        }
    }
    match failure.load(Ordering::Acquire) {
        1 => {
            frame(b'E', b"stdio input queue exceeded limit")
                .map_err(|_| "stdio output delivery failed")?;
        }
        2 => {
            frame(b'E', b"stdio input relay failed").map_err(|_| "stdio output delivery failed")?;
        }
        _ => (),
    }
    let status = status.ok_or("stdio server status unavailable")?;
    let code = status
        .code()
        .unwrap_or_else(|| 128 + status.signal().unwrap_or(0));
    let result = format!(
        "{{\"exit_code\":{code},\"timed_out\":{}}}",
        timed_out.load(Ordering::Acquire)
    );
    frame(b'X', result.as_bytes()).map_err(|_| "stdio output delivery failed")?;
    finished.store(true, Ordering::Release);
    Ok(())
}
