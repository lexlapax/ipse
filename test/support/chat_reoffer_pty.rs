//! Synthetic two-card PTY control; it does not establish human qualification.
use std::ffi::{CStr, OsStr};
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::os::fd::{AsRawFd, FromRawFd};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::OpenOptionsExt;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

#[repr(C)]
struct Poll { fd: i32, events: i16, revents: i16 }
extern "C" {
    fn posix_openpt(flags: i32) -> i32;
    fn grantpt(fd: i32) -> i32;
    fn unlockpt(fd: i32) -> i32;
    fn ptsname(fd: i32) -> *mut std::ffi::c_char;
    fn poll(fds: *mut Poll, count: usize, timeout: i32) -> i32;
    fn tcgetattr(fd: i32, value: *mut std::ffi::c_void) -> i32;
}

fn card_code(text: &str) -> Option<&str> {
    let (_, card) = text.rsplit_once("Type accept ")?;
    let code = card.get(..16)?;
    if code.bytes().all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
        && card[16..].starts_with(" to confirm,") && card[16..].contains("approval> ") {
        Some(code)
    } else { None }
}

fn recalled(text: &str) -> bool {
    let Some((_, fresh)) = text.rsplit_once("CHAT_FRESH_RECALL_READY") else { return false; };
    match (fresh.rfind("CHAT_RECALL_VERIFIED"), fresh.rfind("Finished."), fresh.rfind("you> "), fresh.rfind("Recall the decision I just accepted.")) {
        (Some(verified), Some(done), Some(prompt), Some(request)) => done > verified && prompt > request,
        _ => false,
    }
}

fn main() {
    assert!(cfg!(target_os = "linux"), "this native qualification is Linux-only");
    let flags = 0x100 | 0x80000;
    let fd = unsafe { posix_openpt(2 | flags) }; assert!(fd >= 0);
    let mut master = unsafe { File::from_raw_fd(fd) };
    assert_eq!(unsafe { grantpt(fd) }, 0);
    assert_eq!(unsafe { unlockpt(fd) }, 0);
    let name = unsafe { ptsname(fd) }; assert!(!name.is_null());
    let path = OsStr::from_bytes(unsafe { CStr::from_ptr(name) }.to_bytes());
    let slave = OpenOptions::new().read(true).write(true).custom_flags(flags).open(path).unwrap();
    let check = slave.try_clone().unwrap();
    let mut original = [0_usize; 64];
    assert_eq!(unsafe { tcgetattr(check.as_raw_fd(), original.as_mut_ptr().cast()) }, 0);
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    assert!(!args.is_empty());
    let mut child = Command::new(&args[0]).args(&args[1..])
        .stdin(Stdio::from(slave.try_clone().unwrap()))
        .stdout(Stdio::from(slave.try_clone().unwrap()))
        .stderr(Stdio::from(slave.try_clone().unwrap())).spawn().unwrap();
    drop(slave);
    let deadline = Instant::now() + Duration::from_secs(120);
    let mut output = Vec::new();
    let mut phase = 0;
    let mut sent = Vec::<String>::new();
    let mut first_code = String::new();
    let status = loop {
        if let Some(status) = child.try_wait().unwrap() {
            loop {
                let mut descriptor = Poll { fd, events: 1, revents: 0 };
                if unsafe { poll(&mut descriptor, 1, 100) } <= 0 || descriptor.revents & 1 == 0 { break; }
                let mut chunk = [0; 8192];
                match master.read(&mut chunk) { Ok(n) if n > 0 => output.extend_from_slice(&chunk[..n]), _ => break }
            }
            break status;
        }
        if Instant::now() >= deadline || output.len() > 2 * 1024 * 1024 {
            child.kill().unwrap();
            let status = child.wait().unwrap();
            eprintln!("qualification deadline/output bound reached; no effects retried");
            break status;
        }
        let mut descriptor = Poll { fd, events: 1, revents: 0 };
        if unsafe { poll(&mut descriptor, 1, 50) } > 0 && descriptor.revents & 1 != 0 {
            let mut chunk = [0; 8192];
            if let Ok(n) = master.read(&mut chunk) { output.extend_from_slice(&chunk[..n]); }
        }
        let text = String::from_utf8_lossy(&output);
        if phase == 0 {
            for (action, prefix) in [("folder", "Type one exact choice: folder "), ("repository", "Type one exact choice: repository "), ("enable", "Type enable ")] {
                for (offset, _) in text.match_indices(prefix) {
                    let tail = &text[offset + prefix.len()..];
                    let Some(code) = tail.get(..16) else { continue; };
                    if !code.bytes().all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase()) || !tail[16..].contains("> ") { continue; }
                    let reply = format!("{action} {code}");
                    if !sent.contains(&reply) { master.write_all(format!("{reply}\n").as_bytes()).unwrap(); sent.push(reply); }
                }
            }
        }
        match phase {
            0 if text.contains("CHAT_INITIAL_AUTHORITY_CHECKED") && text.contains("you> ") => {
                master.write_all(b"Propose a durable decision for this workspace.\n").unwrap(); phase = 1;
            },
            1 => if let Some(code) = card_code(&text) {
                first_code = code.to_string(); master.write_all(b"cancel\n").unwrap(); phase = 2;
            },
            2 => if let Some((_, resumed)) = text.rsplit_once("Conversation resumed: ") {
                if resumed.contains("you> ") && text.contains("CHAT_RESUME_AUTHORITY_CHECKED") {
                    master.write_all(b"/exit\n").unwrap(); phase = 3;
                }
            },
            3 => if let Some((_, fresh)) = text.rsplit_once("CHAT_EXPLICIT_REOFFER_READY") {
                assert!(!fresh.contains("you> "), "ordinary chat prompt armed before startup review");
                if let Some(code) = card_code(fresh) {
                    assert_ne!(code, first_code, "reoffer must use a fresh native code");
                    master.write_all(format!("accept {code}\n").as_bytes()).unwrap(); phase = 4;
                }
            },
            4 => if let Some((_, fresh)) = text.rsplit_once("CHAT_EXPLICIT_REOFFER_READY") {
                if let Some((_, resumed)) = fresh.rsplit_once("Conversation resumed: ") {
                    if resumed.contains("you> ") { master.write_all(b"/exit\n").unwrap(); phase = 5; }
                }
            },
            5 => if let Some((_, fresh)) = text.rsplit_once("CHAT_FRESH_RECALL_READY") {
                if fresh.contains("you> ") { master.write_all(b"Recall the decision I just accepted.\n").unwrap(); phase = 6; }
            },
            6 if recalled(&text) => { master.write_all(b"/exit\n").unwrap(); phase = 7; },
            _ => {},
        }
    };
    std::io::stdout().write_all(&output).unwrap();
    let mut restored = [0_usize; 64];
    assert_eq!(unsafe { tcgetattr(check.as_raw_fd(), restored.as_mut_ptr().cast()) }, 0);
    assert_eq!(original, restored, "native terminal attributes were not restored");
    assert_eq!(phase, 7);
    assert!(status.success());
}
