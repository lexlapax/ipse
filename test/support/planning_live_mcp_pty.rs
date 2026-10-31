//! Synthetic terminal control; its input does not establish human interaction.
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

fn prompted_after(text: &str, marker: &str) -> bool {
    match (text.rfind("you> "), text.rfind(marker)) {
        (Some(prompt), Some(event)) => prompt > event,
        _ => false,
    }
}

fn main() {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    let mode = args[0].to_str().unwrap();
    assert!(mode == "entry_release" || mode == "exit_kill");
    let root = std::path::PathBuf::from(args.last().unwrap());
    let flags = 0x100 | 0x80000;
    let fd = unsafe { posix_openpt(2 | flags) }; assert!(fd >= 0);
    let mut master = unsafe { File::from_raw_fd(fd) };
    assert_eq!(unsafe { grantpt(fd) }, 0);
    assert_eq!(unsafe { unlockpt(fd) }, 0);
    let name = unsafe { ptsname(fd) }; assert!(!name.is_null());
    let slave = OpenOptions::new().read(true).write(true).custom_flags(flags)
        .open(OsStr::from_bytes(unsafe { CStr::from_ptr(name) }.to_bytes())).unwrap();
    let check = slave.try_clone().unwrap();
    let mut original = [0_usize; 64];
    assert_eq!(unsafe { tcgetattr(check.as_raw_fd(), original.as_mut_ptr().cast()) }, 0);
    let mut child = Command::new(&args[1]).args(&args[2..])
        .stdin(Stdio::from(slave.try_clone().unwrap()))
        .stdout(Stdio::from(slave.try_clone().unwrap()))
        .stderr(Stdio::from(slave.try_clone().unwrap())).spawn().unwrap();
    drop(slave);
    let deadline = Instant::now() + Duration::from_secs(45);
    let mut output = Vec::new();
    let mut phase = 0;
    let status = loop {
        let mut descriptor = Poll { fd, events: 1, revents: 0 };
        if unsafe { poll(&mut descriptor, 1, 20) } > 0 && descriptor.revents & 1 != 0 {
            let mut chunk = [0; 8192];
            match master.read(&mut chunk) {
                Ok(n) if n > 0 => output.extend_from_slice(&chunk[..n]),
                Ok(_) => {},
                Err(e) if e.raw_os_error() == Some(5) => {},
                Err(e) => panic!("terminal read: {e}"),
            }
        }
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
            std::io::stdout().write_all(&output).unwrap();
            panic!("live MCP terminal exceeded its bound at phase {phase}");
        }
        let text = String::from_utf8_lossy(&output);
        if mode == "entry_release" {
            match phase {
                0 if text.contains("you> ") => { master.write_all(b"lookup\n").unwrap(); phase = 1; },
                1 if root.join("live-resources-captured").exists() => { master.write_all(b"/plan\n").unwrap(); phase = 2; },
                2 if text.contains("Planning entry requires an idle native terminal.") => {
                    std::fs::write(root.join("planning-read-release"), b"release").unwrap(); phase = 3;
                },
                3 if text.contains("Finished.") && prompted_after(&text, "Planning entry requires") => {
                    master.write_all(b"/plan\n").unwrap(); phase = 4;
                },
                4 if text.contains("Planning mode entered.") && prompted_after(&text, "Planning mode entered.") => {
                    master.write_all(b"/plan exit\n").unwrap(); phase = 5;
                },
                5 if text.contains("Local planning mode exited.") && prompted_after(&text, "Local planning mode exited.") => {
                    master.write_all(b"/exit\n").unwrap(); phase = 6;
                },
                _ => {},
            }
        } else {
            match phase {
                0 if text.contains("you> ") => { master.write_all(b"/plan\n").unwrap(); phase = 1; },
                1 if text.contains("Planning mode entered.") && prompted_after(&text, "Planning mode entered.") => {
                    master.write_all(b"lookup\n").unwrap(); phase = 2;
                },
                2 if root.join("live-resources-captured").exists() => { master.write_all(b"/plan exit\n").unwrap(); phase = 3; },
                3 if text.contains("Planning exit requires an idle native terminal.") => {
                    std::fs::write(root.join("kill-session"), b"kill").unwrap(); phase = 4;
                },
                _ => {},
            }
        }
    };
    let restored_deadline = Instant::now() + Duration::from_secs(3);
    loop {
        let mut current = [0_usize; 64];
        assert_eq!(unsafe { tcgetattr(check.as_raw_fd(), current.as_mut_ptr().cast()) }, 0);
        if current == original { break; }
        assert!(Instant::now() < restored_deadline, "terminal restoration did not finish");
        std::thread::sleep(Duration::from_millis(2));
    }
    std::io::stdout().write_all(&output).unwrap();
    assert!(status.success());
    assert_eq!(phase, if mode == "entry_release" { 6 } else { 4 });
    println!("LIVE_MCP_TERMINAL_RESTORED");
}
