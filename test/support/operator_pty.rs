//! Synthetic terminal driver for host Session integration tests.
use std::ffi::{CStr, OsStr};
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::os::fd::FromRawFd;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::OpenOptionsExt;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

#[repr(C)]
struct Poll { fd: i32, events: i16, revents: i16 }
#[cfg(target_os = "linux")]
type Count = usize;
#[cfg(target_os = "macos")]
type Count = u32;
extern "C" {
    fn posix_openpt(flags: i32) -> i32;
    fn grantpt(fd: i32) -> i32;
    fn unlockpt(fd: i32) -> i32;
    fn ptsname(fd: i32) -> *mut std::ffi::c_char;
    fn poll(fds: *mut Poll, count: Count, timeout: i32) -> i32;
}

fn main() {
    #[cfg(target_os = "linux")]
    let flags = 0x100 | 0x80000;
    #[cfg(target_os = "macos")]
    let flags = 0x20000 | 0x1000000;
    let fd = unsafe { posix_openpt(2 | flags) }; assert!(fd >= 0);
    let mut master = unsafe { File::from_raw_fd(fd) };
    assert_eq!(unsafe { grantpt(fd) }, 0);
    assert_eq!(unsafe { unlockpt(fd) }, 0);
    let name = unsafe { ptsname(fd) }; assert!(!name.is_null());
    let path = OsStr::from_bytes(unsafe { CStr::from_ptr(name) }.to_bytes());
    let slave = OpenOptions::new().read(true).write(true).custom_flags(flags).open(path).unwrap();
    let mut args: Vec<_> = std::env::args_os().skip(1).collect();
    let channel = args.first().is_some_and(|a| a == "--channel");
    if channel { args.remove(0); }
    let knowledge = args.first().is_some_and(|a| a == "--knowledge" || a == "--knowledge-cancel" || a == "--knowledge-stale" || a == "--knowledge-cas");
    let cancel_knowledge = args.first().is_some_and(|a| a == "--knowledge-cancel");
    let stale_knowledge = args.first().is_some_and(|a| a == "--knowledge-stale");
    let cas_knowledge = args.first().is_some_and(|a| a == "--knowledge-cas");
    if knowledge { args.remove(0); }
    assert!(!args.is_empty());
    let mut child = Command::new(&args[0]).args(&args[1..])
        .stdin(Stdio::from(slave.try_clone().unwrap()))
        .stdout(Stdio::from(slave.try_clone().unwrap()))
        .stderr(Stdio::from(slave.try_clone().unwrap())).spawn().unwrap();
    drop(slave);
    let deadline = Instant::now() + Duration::from_secs(60);
    let mut output = Vec::new();
    let mut number = 1;
    let mut answered = Vec::new();
    let status = loop {
        if let Some(status) = child.try_wait().unwrap() {
            loop {
                let mut descriptor = Poll { fd, events: 1, revents: 0 };
                if output.len() > 2 * 1024 * 1024 || unsafe { poll(&mut descriptor, 1, 100) } <= 0 || descriptor.revents & 1 == 0 { break; }
                let mut chunk = [0; 8192];
                match master.read(&mut chunk) {
                    Ok(n) if n > 0 => output.extend_from_slice(&chunk[..n]),
                    _ => break,
                }
            }
            break status;
        }
        if Instant::now() >= deadline || output.len() > 2 * 1024 * 1024 {
            let _ = child.kill(); let _ = child.wait();
            eprintln!("synthetic terminal exceeded its bound");
            std::io::stdout().write_all(&output).unwrap();
            std::process::exit(1);
        }
        let mut descriptor = Poll { fd, events: 1, revents: 0 };
        if unsafe { poll(&mut descriptor, 1, 50) } > 0 && descriptor.revents & 1 != 0 {
            let mut chunk = [0; 8192];
            match master.read(&mut chunk) {
                Ok(0) => {},
                Ok(n) => output.extend_from_slice(&chunk[..n]),
                Err(e) if e.raw_os_error() == Some(5) => {},
                Err(e) => panic!("terminal read: {e}"),
            }
        }
        let marker = format!("IPSE_FIXTURE_INPUT_{number}> {}", if channel { "you> " } else { "" });
        if String::from_utf8_lossy(&output).contains(&marker) {
            master.write_all(format!("synthetic café 日本語 {number}\n").as_bytes()).unwrap();
            number += 1;
        } else if String::from_utf8_lossy(&output).contains(&format!("IPSE_FIXTURE_EMPTY_{number}> ")) {
            master.write_all(b"\n").unwrap();
            number += 1;
        }
        if knowledge {
            let text = String::from_utf8_lossy(&output);
            for (action, prefix) in [
                ("folder", "Type one exact choice: folder "),
                ("repository", "Type one exact choice: repository "),
                ("enable", "Type enable "),
                ("disable", "Type disable "),
            ] {
                for (index, _) in text.match_indices(prefix) {
                    let tail = &text[index + prefix.len()..];
                    let Some(code) = tail.get(..16) else { continue; };
                    if !code.bytes().all(|b| b.is_ascii_hexdigit()) || !tail[16..].contains("> ") {
                        continue;
                    }
                    let reply = format!("{action} {code}");
                    if !answered.contains(&reply) {
                        if cas_knowledge && action == "enable" {
                            let root = std::path::Path::new(&args[args.len() - 2]);
                            std::fs::write(root.join("native-review-ready"), b"ready").unwrap();
                            if !root.join("consent-raced").is_file() { continue; }
                        }
                        let stale_reply = format!("enable {}", if code == "0000000000000000" { "1111111111111111" } else { "0000000000000000" });
                        let line = if cancel_knowledge && action == "enable" { "yes" }
                            else if stale_knowledge && action == "enable" { &stale_reply }
                            else { &reply };
                        master.write_all(format!("{line}\n").as_bytes()).unwrap();
                        answered.push(reply);
                    }
                }
            }
        }
        if channel {
            let root = std::path::Path::new(args.last().unwrap());
            for n in 1..=3 {
                if String::from_utf8_lossy(&output).contains(&format!("IPSE_CHANNEL_WAIT_{n}> ")) {
                    std::fs::write(root.join(format!("native-wait-{n}")), b"ready").unwrap();
                }
            }
        }
    };
    std::io::stdout().write_all(&output).unwrap();
    std::process::exit(status.code().unwrap_or(1));
}
