// Bounded fixture for the signed-helper process-boundary check, never a backend.
use std::env;
use std::fs;
use std::io::{self, Write};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

extern "C" {
    fn setsid() -> i32;
    fn setpgid(pid: i32, pgid: i32) -> i32;
    fn getpgrp() -> i32;
    fn kill(pid: i32, signal: i32) -> i32;
}

fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().collect();
    if args.len() == 3 && args[1] == "alive" {
        let pid: i32 = args[2].parse().map_err(|_| "invalid PID")?;
        if pid <= 0 { return Err("PID must be positive".into()); }
        if unsafe { kill(pid, 0) } == 0 {
            println!("alive");
        } else if io::Error::last_os_error().raw_os_error() == Some(3) {
            println!("gone");
        } else {
            return Err(format!("cannot check process: {}", io::Error::last_os_error()));
        }
        return Ok(());
    }
    if args.len() != 8 {
        return Err("usage: probe parent|child group|setsid|setpgid hold|exit READY RELEASE EFFECT SECRET".into());
    }
    if args[1] == "parent" {
        let mut child = Command::new(env::current_exe().map_err(|e| e.to_string())?)
            .arg("child").args(&args[2..])
            .stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null())
            .spawn().map_err(|e| e.to_string())?;
        let deadline = Instant::now() + Duration::from_secs(3);
        while !std::path::Path::new(&args[4]).exists() {
            if let Some(status) = child.try_wait().map_err(|e| e.to_string())? {
                return Err(format!("child failed before readiness: {status}"));
            }
            if Instant::now() >= deadline {
                let _ = child.kill();
                let _ = child.wait();
                return Err("child readiness deadline exceeded".into());
            }
            thread::sleep(Duration::from_millis(5));
        }
        println!("process-probe-ready");
        io::stdout().flush().map_err(|e| e.to_string())?;
        if args[3] == "hold" {
            thread::sleep(Duration::from_secs(6));
            let _ = child.wait();
        }
        return Ok(());
    }
    if args[1] != "child" { return Err("invalid fixture role".into()); }
    let original_group = unsafe { getpgrp() };
    let changed = match args[2].as_str() {
        "group" => 0,
        "setsid" => unsafe { setsid() },
        "setpgid" => unsafe { setpgid(0, 0) },
        _ => return Err("invalid escape mode".into()),
    };
    if changed < 0 { return Err(format!("escape denied: {}", io::Error::last_os_error())); }
    let group = unsafe { getpgrp() };
    if (args[2] == "group") != (group == original_group) {
        return Err("unexpected process group identity".into());
    }
    // An escaped process must still prove that it inherited the file policy.
    match fs::read(&args[7]) {
        Err(e) if e.kind() == io::ErrorKind::PermissionDenied => (),
        other => return Err(format!("expected inherited outside-read denial: {other:?}")),
    }
    fs::write(&args[4], format!("{} {group}\n", std::process::id())).map_err(|e| e.to_string())?;
    // Never leave an unbounded child behind, even if the Elixir probe crashes.
    let deadline = Instant::now() + Duration::from_secs(5);
    while Instant::now() < deadline {
        if std::path::Path::new(&args[5]).exists() {
            fs::write(&args[6], "survived cleanup\n").map_err(|e| e.to_string())?;
            return Ok(());
        }
        thread::sleep(Duration::from_millis(5));
    }
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
