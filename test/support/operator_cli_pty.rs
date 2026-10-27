//! Synthetic PTY driver; its terminal events never establish that a human typed.
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
    fn tcgetattr(fd: i32, value: *mut std::ffi::c_void) -> i32;
}

fn ready_for_exit(text: &str) -> bool {
    text.contains("Finished.") && match (text.rfind("you> "), text.rfind("answer> ")) {
        (Some(prompt), Some(answer)) => prompt > answer,
        _ => false,
    }
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
    let kill_owner = args.first().is_some_and(|a| a == "--kill-owner");
    let queued_eof = args.first().is_some_and(|a| a == "--queued-eof");
    let draft = args.first().is_some_and(|a| a == "--draft");
    let draft_cli = args.first().is_some_and(|a| a == "--draft-cli");
    let draft_multi = args.first().is_some_and(|a| a == "--draft-multi");
    let draft_question = args.first().is_some_and(|a| a == "--draft-question");
    let draft_mcp_resume = args.first().is_some_and(|a| a == "--draft-mcp-resume");
    let enhance_cancel = args.first().is_some_and(|a| a == "--enhance-cancel");
    if kill_owner || queued_eof || draft || draft_cli || draft_multi || draft_question || draft_mcp_resume || enhance_cancel { args.remove(0); }
    let root = std::path::PathBuf::from(args.last().unwrap());
    let check_terminal = slave.try_clone().unwrap();
    let mut original = [0_usize; 64];
    use std::os::fd::AsRawFd;
    assert_eq!(unsafe { tcgetattr(check_terminal.as_raw_fd(), original.as_mut_ptr().cast()) }, 0);
    assert!(!args.is_empty());
    let mut child = Command::new(&args[0]).args(&args[1..])
        .stdin(Stdio::from(slave.try_clone().unwrap()))
        .stdout(Stdio::from(slave.try_clone().unwrap()))
        .stderr(Stdio::from(slave.try_clone().unwrap())).spawn().unwrap();
    drop(slave);
    let deadline = Instant::now() + Duration::from_secs(60);
    let mut output = Vec::new();
    let mut phase = 0;
    let mut codes: Vec<String> = Vec::new();
    let mut rejected = String::new();
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
        let text = String::from_utf8_lossy(&output);
        if enhance_cancel {
            let prompts = text.matches("you> ").count();
            let finished = text.matches("Finished.").count();
            match phase {
                0 if prompts >= 1 => { master.write_all(b"/enhance\n").unwrap(); phase = 1; },
                1 if prompts >= 2 && text.contains("Enter the request to draft") => {
                    master.write_all(b"/cancel\n").unwrap(); phase = 2;
                },
                2 if prompts >= 3 && text.contains("Draft input cancelled") => {
                    master.write_all(b"ordinary before draft\n").unwrap(); phase = 3;
                },
                3 if prompts >= 4 && finished >= 1 => {
                    master.write_all(b"/enhance private initial request\n").unwrap(); phase = 4;
                },
                4 if prompts >= 5 && finished >= 2 => {
                    master.write_all(b"/enhance replace\n").unwrap(); phase = 5;
                },
                5 if prompts >= 6 && text.contains("Enter the replacement request") => {
                    master.write_all(b"/cancel\n").unwrap(); phase = 6;
                },
                6 if prompts >= 7 && text.matches("Draft input cancelled").count() >= 2 => {
                    master.write_all(b"/enhance show\n").unwrap(); phase = 7;
                },
                7 if prompts >= 8 && text.contains("Proposed request:\r\nsuggested request") => {
                    master.write_all(b"/enhance accept\n").unwrap(); phase = 8;
                },
                8 if text.contains("Type accept ") && text.contains("draft> ") => {
                    master.write_all(b"/cancel\n").unwrap(); phase = 9;
                },
                9 if prompts >= 9 && text.contains("Draft cancelled.") => {
                    master.write_all(b"ordinary after cancellation\n").unwrap(); phase = 10;
                },
                10 if prompts >= 10 && finished >= 3 => {
                    master.write_all(b"/exit\n").unwrap(); phase = 11;
                },
                _ => {},
            }
            continue;
        }
        if draft_mcp_resume {
            if phase == 0 {
                if let Some(part) = text.split("Type answer ").nth(1) {
                    if part.len() >= 32 && part.as_bytes()[..32].iter().all(u8::is_ascii_hexdigit) && part.contains("answer> ") {
                        master.write_all(format!("answer {} synthetic answer\n", &part[..32]).as_bytes()).unwrap(); phase = 1;
                    }
                }
            }
            continue;
        }
        if draft_question {
            match phase {
                0 if text.contains("you> ") => { master.write_all(b"/enhance\n").unwrap(); phase = 1; },
                1 if text.contains("Enter the request to draft") && text.matches("you> ").count() >= 2 => {
                    master.write_all(b"private initial request\n").unwrap(); phase = 2;
                },
                2 => if let Some(part) = text.split("Type answer ").nth(1) {
                    if part.len() >= 32 && part.as_bytes()[..32].iter().all(u8::is_ascii_hexdigit) && part.contains("answer> ") {
                        master.write_all(format!("answer {} private answer canary\n", &part[..32]).as_bytes()).unwrap(); phase = 3;
                    }
                },
                3 if text.contains("Finished.") && text.matches("you> ").count() >= 3 => {
                    master.write_all(b"/enhance accept\n").unwrap(); phase = 4;
                },
                4 => if let Some(part) = text.split("Type accept ").nth(1) {
                    if part.len() >= 32 && part.as_bytes()[..32].iter().all(u8::is_ascii_hexdigit) && part.contains("draft> ") {
                        master.write_all(format!("accept {}\n", &part[..32]).as_bytes()).unwrap(); phase = 5;
                    }
                },
                5 if text.matches("Finished.").count() >= 2 && text.matches("you> ").count() >= 4 => { master.write_all(b"/exit\n").unwrap(); phase = 6; },
                _ => {},
            }
            continue;
        }
        if draft_multi {
            match phase {
                0 if text.contains("you> ") => { master.write_all(b"/enhance\n").unwrap(); phase = 1; },
                1 if text.contains("Enter the request to draft") && text.matches("you> ").count() >= 2 => {
                    master.write_all(b"private initial request\n").unwrap(); phase = 2;
                },
                2 if text.contains("Finished.") && text.matches("you> ").count() >= 3 => {
                    master.write_all(b"/enhance replace multi\n").unwrap(); phase = 3;
                },
                3 if text.contains("Enter up to 16 lines") && text.matches("you> ").count() >= 4 => {
                    master.write_all(b"first replacement line\n").unwrap(); phase = 4;
                },
                4 if text.matches("you> ").count() >= 5 => { master.write_all(b"second replacement line\n").unwrap(); phase = 5; },
                5 if text.matches("you> ").count() >= 6 => { master.write_all(b"/end\n").unwrap(); phase = 6; },
                6 if text.contains("Draft replaced") && text.matches("you> ").count() >= 7 => { master.write_all(b"/enhance accept\n").unwrap(); phase = 7; },
                7 => if let Some(part) = text.split("Type accept ").nth(1) {
                    if part.len() >= 32 && part.as_bytes()[..32].iter().all(u8::is_ascii_hexdigit) && part.contains("draft> ") {
                        master.write_all(format!("accept {}\n", &part[..32]).as_bytes()).unwrap(); phase = 8;
                    }
                },
                8 if text.matches("Finished.").count() >= 2 && text.matches("you> ").count() >= 8 => { master.write_all(b"/exit\n").unwrap(); phase = 9; },
                _ => {},
            }
            continue;
        }
        if draft_cli {
            match phase {
                0 if text.contains("you> ") => {
                    master.write_all(b"/enhance private initial request\n").unwrap(); phase = 1;
                },
                1 if text.contains("Finished.") && text.matches("you> ").count() >= 2 => {
                    master.write_all(b"/enhance replace\n").unwrap(); phase = 2;
                },
                2 if text.contains("Enter the replacement request") && text.matches("you> ").count() >= 3 => {
                    master.write_all(b"accepted replacement\n").unwrap(); phase = 3;
                },
                3 if text.contains("Draft replaced") && text.matches("you> ").count() >= 4 => {
                    master.write_all(b"/enhance accept stale-id\n").unwrap(); phase = 4;
                },
                4 if text.contains("Draft cannot be accepted") && text.matches("you> ").count() >= 5 => {
                    assert!(!text.contains("Type accept "));
                    if let Some(id) = text.split("Draft ").find_map(|part| {
                        (part.len() >= 32 && part.as_bytes()[..32].iter().all(u8::is_ascii_hexdigit))
                            .then(|| &part[..32])
                    }) {
                        master.write_all(format!("/enhance accept {id}\n").as_bytes()).unwrap(); phase = 5;
                    }
                },
                5 => if let Some(part) = text.split("Type accept ").nth(1) {
                    if part.len() >= 32 && part.as_bytes()[..32].iter().all(u8::is_ascii_hexdigit) && part.contains("draft> ") {
                        master.write_all(format!("accept {}\n", &part[..32]).as_bytes()).unwrap(); phase = 6;
                    }
                },
                6 if text.matches("Finished.").count() >= 2 && text.matches("you> ").count() >= 6 => {
                    master.write_all(b"/exit\n").unwrap(); phase = 7;
                },
                _ => {},
            }
            continue;
        }
        if draft {
            if phase == 0 && text.matches("you> ").count() >= 1 {
                master.write_all(b"rejected original\n").unwrap(); phase = 1;
            } else if phase == 1 && text.matches("you> ").count() >= 2 {
                master.write_all(b"synthetic draft input\n").unwrap(); phase = 2;
            } else if phase == 2 && text.matches("you> ").count() >= 3 {
                master.write_all(b"rejected replacement\n").unwrap(); phase = 3;
            } else if phase == 3 && text.matches("you> ").count() >= 4 {
                master.write_all(b"synthetic proposed request\n").unwrap(); phase = 4;
            } else if phase == 4 {
                if let Some(part) = text.split("Type accept ").nth(1) {
                    if part.len() >= 32 && part.as_bytes()[..32].iter().all(u8::is_ascii_hexdigit) && part.contains("draft> ") {
                        master.write_all(format!("accept {}\n", &part[..32]).as_bytes()).unwrap();
                        phase = 5;
                    }
                }
            } else if phase == 5 {
                if let Some(part) = text.split("Type accept ").nth(2) {
                    if part.len() >= 32 && part.as_bytes()[..32].iter().all(u8::is_ascii_hexdigit) && part.contains("draft> ") {
                        master.write_all(format!("accept {}\n", &part[..32]).as_bytes()).unwrap();
                        phase = 6;
                    }
                }
            } else if phase == 6 && text.matches("you> ").count() >= 5 {
                master.write_all(b"staged before cancellation\n").unwrap(); phase = 7;
            } else if phase == 7 && text.matches("you> ").count() >= 6 {
                master.write_all(b"staged before owner loss\n").unwrap(); phase = 8;
            } else if phase == 8 {
                if let Some(part) = text.split("Type accept ").nth(3) {
                    if part.len() >= 32 && part.as_bytes()[..32].iter().all(u8::is_ascii_hexdigit) && part.contains("draft> ") {
                        master.write_all(format!("accept {}\n", &part[..32]).as_bytes()).unwrap(); phase = 9;
                    }
                }
            }
            continue;
        }
        if kill_owner {
            if phase == 0 && text.contains("you> ") { child.kill().unwrap(); phase = 1; }
            continue;
        }
        if queued_eof {
            let queued = text.matches("Queued for the next turn.").count();
            match phase {
                0 if text.contains("you> ") => {
                    master.write_all("first café original\n".as_bytes()).unwrap(); phase = 1;
                },
                1 if text.matches("you> ").count() >= 2 => {
                    master.write_all("queued 雪 one\n".as_bytes()).unwrap(); phase = 2;
                },
                2 if queued >= 1 && text.rsplit("Queued for the next turn.").next().unwrap().contains("you> ") => {
                    master.write_all("queued café two\n".as_bytes()).unwrap(); phase = 3;
                },
                3 if queued >= 2 => {
                    std::fs::write(root.join("release-model"), b"release").unwrap(); phase = 4;
                },
                4 if text.contains("Type answer ") && text.contains("answer> ") => {
                    master.write_all(&[4]).unwrap(); phase = 5;
                },
                _ => {},
            }
            continue;
        }
        for part in text.split("Type answer ").skip(1) {
            if part.len() >= 32 && part.as_bytes()[..32].iter().all(u8::is_ascii_hexdigit) &&
                part[32..].starts_with(" followed by your answer.") && part.contains("answer> ") {
                let code = part[..32].to_string();
                if !codes.contains(&code) { codes.push(code); }
            }
        }
        match phase {
            0 if text.contains("you> ") => {
                master.write_all("  synthetic café original  \n".as_bytes()).unwrap(); phase = 1;
            },
            1 if !codes.is_empty() => {
                rejected = codes[0].clone();
                master.write_all(format!("answer {} 99\n", codes[0]).as_bytes()).unwrap(); phase = 2;
            },
            2 if codes.len() >= 2 => {
                master.write_all(format!("answer {rejected} 2\n").as_bytes()).unwrap(); phase = 3;
            },
            3 if codes.len() >= 3 => {
                master.write_all(format!("answer {} 2\n", codes[2]).as_bytes()).unwrap(); phase = 4;
            },
            4 if codes.len() >= 4 && text.contains("Synthetic native literal answer") => {
                master.write_all(format!("answer {} =/exit 雪 café  \n", codes[3]).as_bytes()).unwrap(); phase = 5;
            },
            5 if ready_for_exit(&text) => {
                master.write_all(b"/exit\n").unwrap(); phase = 6;
            },
            _ => {},
        }
    };
    let restored_deadline = Instant::now() + Duration::from_secs(3);
    loop {
        let mut current = [0_usize; 64];
        assert_eq!(unsafe { tcgetattr(check_terminal.as_raw_fd(), current.as_mut_ptr().cast()) }, 0);
        if current == original { break; }
        assert!(Instant::now() < restored_deadline, "VM owner loss stranded terminal mode");
        std::thread::sleep(Duration::from_millis(2));
    }
    std::io::stdout().write_all(&output).unwrap();
    if kill_owner {
        assert_eq!(phase, 1); assert!(!status.success());
        println!("OPERATOR_OWNER_DEATH_RESTORED");
        std::process::exit(0);
    }
    if queued_eof { assert_eq!(phase, 5); assert!(status.success()); }
    if enhance_cancel { assert_eq!(phase, 11); assert!(status.success()); }
    std::process::exit(status.code().unwrap_or(1));
}

#[cfg(test)]
mod tests {
    use super::ready_for_exit;
    #[test]
    fn complete_then_active_prompt() { assert!(ready_for_exit("answer> done\nFinished.\nyou> ")); }
    #[test]
    fn active_prompt_then_complete() { assert!(ready_for_exit("answer> done\nyou> \nFinished.\n")); }
    #[test]
    fn historical_initial_prompt_is_not_current() { assert!(!ready_for_exit("you> task\nanswer> done\nFinished.\n")); }
    #[test]
    fn active_prompt_without_completion_is_not_ready() { assert!(!ready_for_exit("answer> done\nyou> ")); }
    #[test]
    fn completion_without_active_prompt_is_not_ready() { assert!(!ready_for_exit("answer> done\nFinished.\n")); }
    #[test]
    fn refreshed_answer_invalidates_earlier_prompt() { assert!(!ready_for_exit("answer> old\nyou> \nanswer> fresh\nFinished.\n")); }
    #[test]
    fn completion_and_prompt_without_question_are_not_this_phase() { assert!(!ready_for_exit("Finished.\nyou> ")); }
}
