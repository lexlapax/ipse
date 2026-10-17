#[path = "../../native/ipse-process-group.rs"]
mod group;
use std::io::{BufRead, Read};
use std::process::{Command, Stdio};
use std::sync::{mpsc, Arc, Mutex};
use std::time::Duration;
extern "C" {
    fn getpgid(pid: i32) -> i32;
    fn kill(pid: i32, signal: i32) -> i32;
    fn signal(number: i32, handler: usize) -> usize;
}
fn main() {
    let role = std::env::args().nth(1);
    if role.as_deref() == Some("--group-anchor") {
        group::run_anchor().unwrap();
        return;
    }
    if role.as_deref() == Some("--held-child") {
        println!("child-ready");
        std::thread::sleep(Duration::from_secs(10));
        return;
    }
    if role.as_deref() == Some("--lease-owner") {
        let slot = Arc::new(Mutex::new(None));
        let guard = group::GroupGuard::start(slot).unwrap();
        let mut command = Command::new(std::env::current_exe().unwrap());
        command.arg("--held-child").stdin(Stdio::null());
        guard.attach(&mut command);
        let mut child = command.spawn().unwrap();
        println!("owner-ready:{}", child.id());
        child.wait().unwrap();
        return;
    }

    #[cfg(target_os = "linux")]
    let child_signal = 17;
    #[cfg(target_os = "macos")]
    let child_signal = 20;
    assert_ne!(unsafe { signal(child_signal, 1) }, usize::MAX);
    let slot = Arc::new(Mutex::new(None));
    let guard = group::GroupGuard::start(slot.clone()).unwrap();
    let pid = slot.lock().unwrap().unwrap();
    let mut command = Command::new("/bin/sh");
    command.args(["-c", "exit 0"]);
    guard.attach(&mut command);
    let mut child = command.spawn().unwrap();
    assert_ne!(child.id(), pid as u32);
    assert!(child.wait().unwrap().success());
    assert_eq!(unsafe { getpgid(pid) }, pid);
    assert!(group::signal_group(&slot));
    std::thread::sleep(Duration::from_millis(20));
    assert_eq!(unsafe { kill(pid, 0) }, 0);
    drop(guard);
    assert!(slot.lock().unwrap().is_none());
    assert!(!group::signal_group(&slot));

    let mut owner = Command::new(std::env::current_exe().unwrap())
        .arg("--lease-owner")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut output = std::io::BufReader::new(owner.stdout.take().unwrap());
    let mut ready = Vec::new();
    for _ in 0..2 {
        let mut line = String::new();
        assert!(output.read_line(&mut line).unwrap() > 0);
        ready.push(line);
    }
    assert!(ready.iter().any(|line| line.trim() == "child-ready"));
    assert!(ready.iter().any(|line| line.starts_with("owner-ready:")));
    owner.kill().unwrap();
    owner.wait().unwrap();
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let mut bytes = Vec::new();
        output.read_to_end(&mut bytes).unwrap();
        tx.send(bytes).unwrap();
    });
    assert!(rx.recv_timeout(Duration::from_secs(2)).unwrap().is_empty());
    println!("PASS: anchor identity retained until release, late signals refused, abrupt owner loss closes child pipes");
}
