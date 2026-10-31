//! Bidirectional pipes and process-group lifetime for directly executed servers.
use super::{frame, signal_group, GroupGuard};
use std::io::{self, Read, Write};
use std::os::unix::io::AsRawFd;
#[cfg(target_os = "linux")]
use std::os::unix::process::CommandExt;
use std::os::unix::process::ExitStatusExt;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::{mpsc, Arc};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const CHUNK: usize = 8192;
const INPUT_CHUNKS: usize = 128;
const OUTPUT_CHUNKS: usize = 32;
const DRAIN: Duration = Duration::from_millis(500);

#[path = "ipse-environment.rs"]
mod child_environment;
#[path = "ipse-listener.rs"]
mod listener;

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

enum InputFrame {
    Plain(Vec<u8>),
    Start(u64),
    Managed { deadline: u64, nonce: [u8; 16], bytes: Vec<u8>, pending: Arc<AtomicBool> },
}

// 0 means no bytes were written; 1 means the complete frame was written;
// 2 means a partial write or cleanup failure leaves the outcome unknown.
fn managed_write<W: Write + AsRawFd>(output: &mut W, bytes: &[u8], deadline: u64, cancelled: &AtomicBool) -> u8 {
    #[repr(C)] struct PollFd { fd: i32, events: i16, revents: i16 }
    #[cfg(target_os = "macos")] type Nfds = u32;
    #[cfg(not(target_os = "macos"))] type Nfds = usize;
    extern "C" {
        fn fcntl(fd: i32, cmd: i32, ...) -> i32;
        fn poll(fds: *mut PollFd, count: Nfds, timeout: i32) -> i32;
    }
    #[cfg(target_os = "linux")] const NONBLOCK: i32 = 0x800;
    #[cfg(not(target_os = "linux"))] const NONBLOCK: i32 = 0x4;
    let fd = output.as_raw_fd();
    let flags = unsafe { fcntl(fd, 3) };
    if flags < 0 || unsafe { fcntl(fd, 4, flags | NONBLOCK) } < 0 { return 0; }
    let mut offset = 0;
    let result = loop {
        let now = match SystemTime::now().duration_since(UNIX_EPOCH) {
            Ok(now) => now.as_millis(),
            Err(_) => break if offset == 0 { 0 } else { 2 },
        };
        if cancelled.load(Ordering::SeqCst) || now >= u128::from(deadline) {
            break if offset == 0 { 0 } else { 2 };
        }
        match output.write(&bytes[offset..]) {
            Ok(0) => break if offset == 0 { 0 } else { 2 },
            Ok(count) => {
                offset += count;
                if offset == bytes.len() { break 1; }
            },
            Err(error) if error.kind() == io::ErrorKind::Interrupted => (),
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                let wait = (u128::from(deadline) - now).min(25) as i32;
                let mut p = PollFd { fd, events: 4, revents: 0 };
                let ready = unsafe { poll(&mut p, 1, wait) };
                if ready < 0 && io::Error::last_os_error().kind() != io::ErrorKind::Interrupted {
                    break if offset == 0 { 0 } else { 2 };
                }
                if ready > 0 && p.revents & (8 | 16 | 32) != 0 {
                    break if offset == 0 { 0 } else { 2 };
                }
            },
            Err(_) => break if offset == 0 { 0 } else { 2 },
        }
    };
    if unsafe { fcntl(fd, 4, flags) } < 0 { 2 } else { result }
}

fn input_reader(admitted: bool) -> (
    mpsc::Receiver<InputFrame>,
    Arc<AtomicU8>,
    Arc<AtomicBool>,
    Arc<std::sync::Mutex<Option<i32>>>,
) {
    let failure = Arc::new(AtomicU8::new(0));
    let (input_tx, input_rx) = mpsc::sync_channel::<InputFrame>(INPUT_CHUNKS);
    let input_failure = failure.clone();
    let cancelled = Arc::new(AtomicBool::new(false));
    let slot = Arc::new(std::sync::Mutex::new(None::<i32>));
    let reader_slot = slot.clone();
    let reader_cancelled = cancelled.clone();
    let managed_pending = Arc::new(AtomicBool::new(false));
    thread::spawn(move || {
        let mut owner = io::stdin();
        let mut bytes = [0u8; CHUNK];
        let mut awaiting_start = admitted;
        'frames: loop {
            let mut header = [0u8; 5];
            match owner.read(&mut header[..1]) {
                Ok(0) => {
                    reader_cancelled.store(true, Ordering::SeqCst);
                    signal_group(&reader_slot);
                    break;
                }
                Ok(_) => (),
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => {
                    input_failure.store(2, Ordering::Release);
                    reader_cancelled.store(true, Ordering::SeqCst);
                    signal_group(&reader_slot);
                    break;
                }
            }
            if owner.read_exact(&mut header[1..]).is_err() {
                input_failure.store(2, Ordering::Release);
                reader_cancelled.store(true, Ordering::SeqCst);
                signal_group(&reader_slot);
                break;
            }
            let mut remaining =
                u32::from_be_bytes([header[1], header[2], header[3], header[4]]) as usize;
            if header[0] == b'C' && remaining == 0 {
                reader_cancelled.store(true, Ordering::SeqCst);
                signal_group(&reader_slot);
                break;
            }
            if header[0] == b'G' {
                if !awaiting_start || remaining != 8 {
                    input_failure.store(2, Ordering::Release);
                    reader_cancelled.store(true, Ordering::SeqCst);
                    signal_group(&reader_slot);
                    break;
                }
                let mut grant = [0u8; 8];
                if owner.read_exact(&mut grant).is_err() {
                    input_failure.store(2, Ordering::Release);
                    reader_cancelled.store(true, Ordering::SeqCst);
                    signal_group(&reader_slot);
                    break;
                }
                awaiting_start = false;
                if input_tx.try_send(InputFrame::Start(u64::from_be_bytes(grant))).is_err() {
                    input_failure.store(1, Ordering::Release);
                    reader_cancelled.store(true, Ordering::SeqCst);
                    signal_group(&reader_slot);
                    break;
                }
                continue;
            }
            if awaiting_start {
                input_failure.store(2, Ordering::Release);
                reader_cancelled.store(true, Ordering::SeqCst);
                signal_group(&reader_slot);
                break;
            }
            if header[0] == b'D' {
                if !(25..=32_792).contains(&remaining) ||
                    managed_pending.compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire).is_err() {
                    input_failure.store(2, Ordering::Release);
                    reader_cancelled.store(true, Ordering::SeqCst);
                    signal_group(&reader_slot);
                    break;
                }
                let mut payload = vec![0u8; remaining];
                if owner.read_exact(&mut payload).is_err() {
                    input_failure.store(2, Ordering::Release);
                    reader_cancelled.store(true, Ordering::SeqCst);
                    signal_group(&reader_slot);
                    break;
                }
                let deadline = u64::from_be_bytes(payload[..8].try_into().unwrap());
                if deadline == 0 || deadline > 9_007_199_254_740_991 {
                    input_failure.store(2, Ordering::Release);
                    reader_cancelled.store(true, Ordering::SeqCst);
                    signal_group(&reader_slot);
                    break;
                }
                let nonce = payload[8..24].try_into().unwrap();
                let message = InputFrame::Managed { deadline, nonce, bytes: payload[24..].to_vec(), pending: managed_pending.clone() };
                if input_tx.try_send(message).is_err() {
                    input_failure.store(1, Ordering::Release);
                    reader_cancelled.store(true, Ordering::SeqCst);
                    signal_group(&reader_slot);
                    break;
                }
                continue;
            }
            if header[0] != b'I' || remaining > 1_048_576 {
                input_failure.store(2, Ordering::Release);
                reader_cancelled.store(true, Ordering::SeqCst);
                signal_group(&reader_slot);
                break;
            }
            while remaining > 0 {
                let count = remaining.min(CHUNK);
                if owner.read_exact(&mut bytes[..count]).is_err() {
                    input_failure.store(2, Ordering::Release);
                    reader_cancelled.store(true, Ordering::SeqCst);
                    signal_group(&reader_slot);
                    break 'frames;
                }
                match input_tx.try_send(InputFrame::Plain(bytes[..count].to_vec())) {
                    Ok(()) => (),
                    Err(mpsc::TrySendError::Full(_)) => {
                        input_failure.store(1, Ordering::Release);
                        reader_cancelled.store(true, Ordering::SeqCst);
                        signal_group(&reader_slot);
                        break 'frames;
                    }
                    Err(mpsc::TrySendError::Disconnected(_)) => {
                        reader_cancelled.store(true, Ordering::SeqCst);
                        signal_group(&reader_slot);
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
    let listener_mode = args[1] == "--stdio-listener";
    let admitted = args[1] == "--admitted-stdio";
    #[cfg(target_os = "macos")]
    if admitted { return Err("managed stdio startup is unavailable on this platform".into()); }
    if args.len() > (if listener_mode { 263 } else { 261 }) || args.iter().map(String::len).sum::<usize>() > 131072 {
        return Err("stdio launch arguments exceed limit".into());
    }
    let mut listener = if listener_mode {
        if args.len() < 7 || args[5] != "--" || !std::path::Path::new(&args[6]).is_absolute() {
            return Err("usage: --stdio-listener CWD TIMEOUT_MS PORT -- ABSOLUTE_EXEC ARGS".into());
        }
        Some(listener::Listener::new(listener::port(&args[4])?)?)
    } else { None };
    let selected = launch_environment()?;
    let (input_rx, failure, cancelled, slot) = input_reader(admitted);
    let sandboxed = !listener_mode && args[4] == "--sandbox";
    let mut executable = if listener_mode { 6 } else { 4 };
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
    #[cfg(target_os = "macos")]
    let input_prefix = macos.as_mut()
        .map(|policy| std::mem::take(&mut policy.input_prefix)).unwrap_or_default();
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
    let cleanup = GroupGuard::start(slot.clone()).map_err(|_| "cannot start process-group owner")?;
    cleanup.attach(command);
    let start_deadline = if admitted {
        frame(b'R', &[]).map_err(|_| "stdio startup readiness unavailable")?;
        let deadline = match input_rx.recv_timeout(Duration::from_secs(5)) {
            Ok(InputFrame::Start(deadline)) => deadline,
            _ => return Err("stdio startup grant unavailable".into()),
        };
        if deadline == 0 || deadline > 9_007_199_254_740_991 || cancelled.load(Ordering::SeqCst) ||
            SystemTime::now().duration_since(UNIX_EPOCH).map_err(|_| "stdio clock unavailable")?.as_millis() >= u128::from(deadline) {
            return Err("stdio startup deadline elapsed".into());
        }
        Some(deadline)
    } else { None };
    #[cfg(target_os = "linux")]
    let child_sandbox = sandbox.clone();
    #[cfg(not(target_os = "linux"))]
    let _ = start_deadline;
    #[cfg(target_os = "linux")]
    let child_cancelled = cancelled.clone();
    #[cfg(target_os = "linux")]
    unsafe {
        command.pre_exec(move || {
            if let Some(policy) = &child_sandbox {
                policy.apply()?;
            }
            if let Some(deadline) = start_deadline {
                let now = SystemTime::now().duration_since(UNIX_EPOCH)
                    .map_err(|_| io::Error::new(io::ErrorKind::Other, "stdio clock unavailable"))?.as_millis();
                if child_cancelled.load(Ordering::SeqCst) || now >= u128::from(deadline) {
                    return Err(io::Error::new(io::ErrorKind::TimedOut, "stdio startup deadline elapsed"));
                }
            }
            Ok(())
        });
    }
    let child_slot = slot.lock().unwrap();
    if cancelled.load(Ordering::SeqCst) {
        return Err("stdio owner disconnected before launch".into());
    }
    let mut child = command.spawn().map_err(|_| "cannot start stdio server")?;
    drop(child_slot);
    if admitted { frame(b'A', &[]).map_err(|_| "stdio startup acknowledgement unavailable")?; }
    let finished = Arc::new(AtomicBool::new(false));
    let timed_out = Arc::new(AtomicBool::new(false));
    let watchdog_finished = finished.clone();
    let watchdog_timeout = timed_out.clone();
    let watchdog_group = slot.clone();
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
        signal_group(&watchdog_group);
        let grace = Instant::now();
        while !watchdog_finished.load(Ordering::Acquire) && grace.elapsed() < Duration::from_secs(1)
        {
            thread::sleep(Duration::from_millis(5));
        }
        if !watchdog_finished.load(Ordering::Acquire) {
            signal_group(&watchdog_group);
            // Distinguish forced watchdog termination from a returned error,
            // whose stack-owned group guard has completed cleanup.
            std::process::exit(2);
        }
    });
    let mut child_input = child.stdin.take().ok_or("stdio server input unavailable")?;
    let write_failure = failure.clone();
    let input_group = slot.clone();
    let input_cancelled = cancelled.clone();
    thread::spawn(move || {
        #[cfg(target_os = "macos")]
        if child_input.write_all(&input_prefix).is_err() {
            let _ = write_failure.compare_exchange(0, 2, Ordering::AcqRel, Ordering::Acquire);
            signal_group(&input_group);
            return;
        }
        for input in input_rx {
            match input {
                InputFrame::Plain(bytes) => {
                    if child_input.write_all(&bytes).is_err() {
                        let _ = write_failure.compare_exchange(0, 2, Ordering::AcqRel, Ordering::Acquire);
                        signal_group(&input_group);
                        break;
                    }
                },
                InputFrame::Start(_) => {
                    let _ = write_failure.compare_exchange(0, 2, Ordering::AcqRel, Ordering::Acquire);
                    signal_group(&input_group);
                    break;
                },
                InputFrame::Managed { deadline, nonce, bytes, pending } => {
                    let status = managed_write(&mut child_input, &bytes, deadline, &input_cancelled);
                    let mut receipt = nonce.to_vec();
                    receipt.push(status);
                    pending.store(false, Ordering::Release);
                    if status == 2 { signal_group(&input_group); }
                    if frame(b'A', &receipt).is_err() || status == 2 {
                        let _ = write_failure.compare_exchange(0, 2, Ordering::AcqRel, Ordering::Acquire);
                        signal_group(&input_group);
                        break;
                    }
                },
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
            let proof;
            (status, proof) = match listener.as_mut() {
                Some(listener) => listener.poll_child(&mut child)?,
                None => (child.try_wait().map_err(|_| "cannot wait for stdio server")?, None),
            };
            if let Some(proof) = proof {
                if !cancelled.load(Ordering::SeqCst) && !timed_out.load(Ordering::Acquire) {
                    frame(b'P', &proof).map_err(|_| "stdio listener delivery failed")?;
                }
            }
            if status.is_some() {
                cleanup_pending = signal_group(&slot);
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
                    signal_group(&slot);
                    if !listener.as_ref().is_some_and(listener::Listener::inspection_pending) {
                        let _ = child.wait();
                    }
                    return Ok(());
                }
                if kind == b'E' {
                    signal_group(&slot);
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
                // delivered. Retry during the original bounded drain or until
                // pipe disconnect. The unreaped anchor can keep the group present;
                // detached children remain outside it.
                if cleanup_pending {
                    cleanup_pending = signal_group(&slot);
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

#[cfg(test)]
mod managed_tests {
    use super::*;
    use std::os::unix::net::UnixStream;

    fn now_ms() -> u64 {
        SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64
    }

    #[test]
    fn managed_pipe_rejects_elapsed_and_confirms_complete_live_write() {
        let (mut writer, mut reader) = UnixStream::pair().unwrap();
        let cancelled = AtomicBool::new(false);
        assert_eq!(managed_write(&mut writer, b"private", now_ms(), &cancelled), 0);
        reader.set_nonblocking(true).unwrap();
        let mut result = [0u8; 7];
        assert_eq!(reader.read(&mut result).unwrap_err().kind(), io::ErrorKind::WouldBlock);
        reader.set_nonblocking(false).unwrap();
        assert_eq!(managed_write(&mut writer, b"private", now_ms() + 2000, &cancelled), 1);
        reader.read_exact(&mut result).unwrap();
        assert_eq!(&result, b"private");
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn managed_pipe_times_out_after_partial_write_as_unknown() {
        use std::fs::File;
        use std::os::unix::io::FromRawFd;
        extern "C" { fn pipe(fds: *mut i32) -> i32; fn fcntl(fd: i32, cmd: i32, ...) -> i32; }
        let mut fds = [0i32; 2];
        assert_eq!(unsafe { pipe(fds.as_mut_ptr()) }, 0);
        let mut reader = unsafe { File::from_raw_fd(fds[0]) };
        let mut writer = unsafe { File::from_raw_fd(fds[1]) };
        let flags = unsafe { fcntl(fds[1], 3) };
        assert!(flags >= 0);
        assert_eq!(unsafe { fcntl(fds[1], 4, flags | 0x800) }, 0);
        let chunk = [b'x'; 4096];
        loop {
            match writer.write(&chunk) {
                Ok(n) => assert!(n > 0),
                Err(error) if error.kind() == io::ErrorKind::WouldBlock => break,
                Err(error) => panic!("pipe setup failed: {error}"),
            }
        }
        let mut drained = [0u8; 4096];
        reader.read_exact(&mut drained).unwrap();
        assert_eq!(unsafe { fcntl(fds[1], 4, flags) }, 0);
        let status = managed_write(&mut writer, &[b'y'; 32_768], now_ms() + 500, &AtomicBool::new(false));
        assert_eq!(status, 2);
    }
}
