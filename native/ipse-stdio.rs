//! Bidirectional pipes and process-group lifetime for directly executed servers.
use super::{frame, kill_group, setpgid, GroupGuard};
use std::env;
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
    let mut command = Command::new(&args[4]);
    command
        .args(&args[5..])
        .current_dir(&args[2])
        .env_clear()
        .envs(env::vars_os())
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    unsafe {
        command.pre_exec(|| {
            if setpgid(0, 0) < 0 {
                return Err(io::Error::last_os_error());
            }
            Ok(())
        });
    }
    let mut child = command.spawn().map_err(|_| "cannot start stdio server")?;
    let pid = child.id() as i32;
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
    let failure = Arc::new(AtomicU8::new(0));
    let (input_tx, input_rx) = mpsc::sync_channel::<Vec<u8>>(INPUT_CHUNKS);
    let input_failure = failure.clone();
    thread::spawn(move || {
        let mut owner = io::stdin();
        let mut bytes = [0u8; CHUNK];
        'frames: loop {
            let mut header = [0u8; 5];
            match owner.read(&mut header[..1]) {
                Ok(0) => {
                    kill_group(pid);
                    break;
                }
                Ok(_) => (),
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => {
                    input_failure.store(2, Ordering::Release);
                    kill_group(pid);
                    break;
                }
            }
            if owner.read_exact(&mut header[1..]).is_err() {
                input_failure.store(2, Ordering::Release);
                kill_group(pid);
                break;
            }
            let mut remaining =
                u32::from_be_bytes([header[1], header[2], header[3], header[4]]) as usize;
            if header[0] == b'C' && remaining == 0 {
                kill_group(pid);
                break;
            }
            if header[0] != b'I' || remaining > 1_048_576 {
                input_failure.store(2, Ordering::Release);
                kill_group(pid);
                break;
            }
            while remaining > 0 {
                let count = remaining.min(CHUNK);
                if owner.read_exact(&mut bytes[..count]).is_err() {
                    input_failure.store(2, Ordering::Release);
                    kill_group(pid);
                    break 'frames;
                }
                match input_tx.try_send(bytes[..count].to_vec()) {
                    Ok(()) => (),
                    Err(mpsc::TrySendError::Full(_)) => {
                        input_failure.store(1, Ordering::Release);
                        kill_group(pid);
                        break 'frames;
                    }
                    Err(mpsc::TrySendError::Disconnected(_)) => {
                        kill_group(pid);
                        break 'frames;
                    }
                }
                remaining -= count;
            }
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
    loop {
        if status.is_none() {
            status = child
                .try_wait()
                .map_err(|_| "cannot wait for stdio server")?;
            if status.is_some() {
                kill_group(pid);
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
            Err(mpsc::RecvTimeoutError::Timeout) => (),
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
