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
    if kill_owner { args.remove(0); }
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
        if kill_owner {
            if phase == 0 && text.contains("you> ") { child.kill().unwrap(); phase = 1; }
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
            5 if text.contains("Finished.") && text.rsplit("Finished.").next().unwrap().contains("you> ") => {
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
    std::process::exit(status.code().unwrap_or(1));
}
