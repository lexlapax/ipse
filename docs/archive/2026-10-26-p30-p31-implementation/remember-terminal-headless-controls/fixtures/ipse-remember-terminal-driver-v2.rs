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
    let guard_backpressure = args.first().is_some_and(|a| a == "--guard-backpressure");
    if guard_backpressure { args.remove(0); }
    let assertion = args.first().is_some_and(|a| a == "--assertion");
    if assertion { args.remove(0); }
    let channel = args.first().is_some_and(|a| a == "--channel");
    if channel { args.remove(0); }
    let guarded_review = args.first().is_some_and(|a| a == "--review-guarded");
    let management_review = args.first().is_some_and(|a| a == "--management-review" || a == "--management-review-cancel" || a == "--management-review-race");
    let management_race = args.first().is_some_and(|a| a == "--management-review-race");
    let review = guarded_review || management_review || args.first().is_some_and(|a| a == "--review" || a == "--review-cancel" || a == "--review-stale");
    let cancel_review = args.first().is_some_and(|a| a == "--review-cancel" || a == "--management-review-cancel");
    let stale_review = args.first().is_some_and(|a| a == "--review-stale");
    if review { args.remove(0); }
    let knowledge = assertion || args.first().is_some_and(|a| a == "--knowledge" || a == "--knowledge-cancel" || a == "--knowledge-stale" || a == "--knowledge-cas" || a == "--knowledge-config");
    let cancel_knowledge = args.first().is_some_and(|a| a == "--knowledge-cancel");
    let stale_knowledge = args.first().is_some_and(|a| a == "--knowledge-stale");
    let cas_knowledge = args.first().is_some_and(|a| a == "--knowledge-cas");
    let config_knowledge = args.first().is_some_and(|a| a == "--knowledge-config");
    if knowledge && !assertion { args.remove(0); }
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
    let mut assertion_step = 0;
    let mut assertion_sent_at = 0;
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
        let can_read = !guard_backpressure || std::path::Path::new(&args[args.len() - 2]).join("guard-owner-lost").is_file();
        if !can_read && unsafe { poll(&mut descriptor, 1, 0) } > 0 && descriptor.revents & 1 != 0 {
            let root = std::path::Path::new(&args[args.len() - 2]);
            let _ = std::fs::write(root.join("guard-display-buffered"), b"buffered");
        }
        if can_read && unsafe { poll(&mut descriptor, 1, 50) } > 0 && descriptor.revents & 1 != 0 {
            let mut chunk = [0; 8192];
            match master.read(&mut chunk) {
                Ok(0) => {},
                Ok(n) => output.extend_from_slice(&chunk[..n]),
                Err(e) if e.raw_os_error() == Some(5) => {},
                Err(e) => panic!("terminal read: {e}"),
            }
        } else if !can_read { std::thread::sleep(Duration::from_millis(5)); }
        let marker = format!("IPSE_FIXTURE_INPUT_{number}> {}", if channel { "you> " } else { "" });
        if String::from_utf8_lossy(&output).contains(&marker) {
            master.write_all(format!("synthetic café 日本語 {number}\n").as_bytes()).unwrap();
            number += 1;
        } else if String::from_utf8_lossy(&output).contains(&format!("IPSE_FIXTURE_EMPTY_{number}> ")) {
            master.write_all(b"\n").unwrap();
            number += 1;
        }
        if review || assertion {
            let text = String::from_utf8_lossy(&output);
            for command in ["pin", "ordinary", "forget", "duration", "accept", "correct", "supersede"] {
                let prefix = format!("\nType {command} ");
                for (index, _) in text.match_indices(&prefix) {
                    let tail = &text[index + prefix.len()..];
                    let Some(code) = tail.get(..16) else { continue; };
                    if !code.bytes().all(|b| b.is_ascii_hexdigit()) || !tail[16..].starts_with(" to confirm,") || !tail[16..].contains("> ") {
                        continue;
                    }
                    let reply = format!("{command} {code}");
                    if !answered.contains(&reply) {
                        if management_review && !tail.contains("approval> ") { continue; }
                        if management_race {
                            let root = std::path::Path::new(&args[args.len() - 2]);
                            std::fs::write(root.join("management-review-input-ready"), b"ready").unwrap();
                            if !root.join("management-review-race-complete").is_file() { continue; }
                        }
                        if guarded_review {
                            let root = std::path::Path::new(&args[args.len() - 2]);
                            if !root.join("guard-review-ready").is_file() { continue; }
                        }
                        let assertion_case = args.last().unwrap().to_string_lossy();
                        if assertion && command == "forget" && assertion_case == "save_forget_stale" {
                            let root = std::path::Path::new(&args[args.len() - 2]);
                            std::fs::write(root.join("forget-review-ready"), b"ready").unwrap();
                            if !root.join("forget-control-changed").is_file() { continue; }
                        }
                        if assertion && command == "correct" && assertion_case == "revoke" {
                            let root = std::path::Path::new(&args[args.len() - 2]);
                            std::fs::write(root.join("supersession-review-ready"), b"ready").unwrap();
                            if !root.join("supersession-revoked").is_file() { continue; }
                        }
                        if assertion && command == "correct" && assertion_case == "terminal_unknown" {
                            continue;
                        }
                        let wrong = format!("{command} {}", if code == "0000000000000000" { "1111111111111111" } else { "0000000000000000" });
                        let cancel_forget = assertion && command == "forget" && assertion_case == "save_forget_cancel";
                        let cancel_correction = assertion && command == "correct" && (assertion_case == "relation_cancel" || assertion_case == "terminal_cancel");
                        let line = if cancel_review || cancel_forget || cancel_correction { "yes" } else if stale_review { &wrong } else { &reply };
                        master.write_all(format!("{line}\n").as_bytes()).unwrap();
                        answered.push(reply);
                    }
                }
            }
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
                        if (cas_knowledge || config_knowledge) && action == "enable" {
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
        if assertion {
            let text = String::from_utf8_lossy(&output);
            let root = std::path::Path::new(&args[args.len() - 2]);
            if args.last().is_some_and(|value| value == "terminal" || value == "terminal_cancel" || value == "terminal_unknown") {
                let ready = "IPSE_SUPERSESSION_TERMINAL_READY";
                if let Some(start) = text.find(ready) {
                    let tail = &text[start + ready.len()..];
                    if !answered.iter().any(|item| item == "terminal-command") && tail.contains("you> ") {
                        let command = std::fs::read_to_string(root.join("supersession-terminal-command")).unwrap();
                        master.write_all(format!("{command}\n").as_bytes()).unwrap();
                        answered.push("terminal-command".to_owned());
                    }
                    if answered.iter().any(|item| item == "terminal-command") && !answered.iter().any(|item| item == "terminal-exit") {
                        if tail.contains("Finished.") || tail.contains("Finished with an error.") {
                            if tail.contains("you> ") {
                                master.write_all(b"/exit\n").unwrap();
                                answered.push("terminal-exit".to_owned());
                            }
                        }
                    }
                }
            }
            for step in 1..=8 {
                let marker = format!("IPSE_SUPERSESSION_READ_{step}> you> ");
                if text.contains(&marker) && !answered.contains(&marker) {
                    let command = std::fs::read_to_string(root.join(format!("supersession-input-{step}"))).unwrap();
                    master.write_all(format!("{command}\n").as_bytes()).unwrap();
                    answered.push(marker);
                }
            }
            let scenario = args.last().unwrap().to_string_lossy();
            let scenario = if scenario.starts_with("save_") { std::borrow::Cow::Borrowed("save") } else { scenario };
            for (index, _) in text.match_indices("Type remember ") {
                let tail = &text[index + "Type remember ".len()..];
                let Some(code) = tail.get(..32) else { continue; };
                if !code.bytes().all(|b| b.is_ascii_hexdigit()) || !tail[32..].starts_with(" to confirm.") || !tail[32..].contains("remember> ") { continue; }
                let reply = format!("remember {code}");
                if !answered.contains(&reply) {
                    if scenario == "revoked" {
                        let root = std::path::Path::new(&args[args.len() - 2]);
                        std::fs::write(root.join("assertion-review-ready"), b"ready").unwrap();
                        if !root.join("assertion-permission-revoked").is_file() { continue; }
                    }
                    let line = match scenario.as_ref() {
                        "cancel" => "yes".to_owned(),
                        "stale" => format!("remember {}", if code == "00000000000000000000000000000000" { "11111111111111111111111111111111" } else { "00000000000000000000000000000000" }),
                        _ => reply.clone(),
                    };
                    master.write_all(format!("{line}\n").as_bytes()).unwrap();
                    answered.push(reply);
                    assertion_sent_at = text.len();
                }
            }
            if text.contains("IPSE_ASSERTION_CLI_READY") && text.rfind("you> ").is_some_and(|position| position >= assertion_sent_at) && assertion_step < 4 {
                let completed = text.matches("Finished.").count();
                let cancelled = text.contains("Statement review or note publication admission was refused;") || text.contains("Statement review refused.");
                let commands = ["/remember ordinary Synthetic ordinary statement", "/remember preference My synthetic preference is compact output", "/remember current My synthetic timezone is UTC"];
                if text.contains("Finished with an error.") || (scenario != "save" && cancelled && assertion_step == 1) {
                    master.write_all(b"/exit\n").unwrap();
                    assertion_step = 4;
                } else if completed == assertion_step && (assertion_step == 0 || scenario == "save") {
                    if assertion_step < 3 {
                        master.write_all(format!("{}\n", commands[assertion_step]).as_bytes()).unwrap();
                        assertion_step += 1;
                        assertion_sent_at = text.len();
                    } else {
                        master.write_all(b"/exit\n").unwrap();
                        assertion_step = 4;
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
