use std::ffi::{CStr, OsStr};
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::os::fd::FromRawFd;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::OpenOptionsExt;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};
#[repr(C)] struct Poll { fd: i32, events: i16, revents: i16 }
unsafe extern "C" { fn posix_openpt(flags: i32) -> i32; fn grantpt(fd: i32) -> i32; fn unlockpt(fd: i32) -> i32; fn ptsname(fd: i32) -> *mut std::ffi::c_char; fn poll(fds: *mut Poll, count: usize, timeout: i32) -> i32; }
fn main() {
    let fd = unsafe { posix_openpt(2 | 0x100 | 0x80000) }; assert!(fd >= 0);
    let mut master = unsafe { File::from_raw_fd(fd) };
    assert_eq!(unsafe { grantpt(fd) }, 0); assert_eq!(unsafe { unlockpt(fd) }, 0);
    let name = unsafe { ptsname(fd) }; assert!(!name.is_null());
    let path = OsStr::from_bytes(unsafe { CStr::from_ptr(name) }.to_bytes());
    let slave = OpenOptions::new().read(true).write(true).custom_flags(0x100 | 0x80000).open(path).unwrap();
    let line = std::env::args().nth(1).expect("test line");
    let test_path = format!("test/ipse/extension/collection_call_session_test.exs:{line}");
    let mut child = Command::new("/usr/bin/mix").args(["test", &test_path, "--seed", "20270381", "--max-cases", "1"])
       .stdin(Stdio::from(slave.try_clone().unwrap())).stdout(Stdio::from(slave.try_clone().unwrap())).stderr(Stdio::from(slave)).spawn().unwrap();
    let deadline = Instant::now() + Duration::from_secs(60); let mut output=Vec::new(); let mut sent=false;
    let status = loop {
        if let Some(status)=child.try_wait().unwrap() { break status; }
        if Instant::now() >= deadline || output.len() > 2_000_000 { let _=child.kill(); let _=child.wait(); panic!("PTY deadline"); }
        let mut p=Poll{fd,events:1,revents:0};
        if unsafe { poll(&mut p,1,50) } > 0 && p.revents & 1 != 0 { let mut b=[0;8192]; match master.read(&mut b) {Ok(n) if n>0=>output.extend_from_slice(&b[..n]), _=>{}} }
        if !sent { let s=String::from_utf8_lossy(&output); if let Some(pos)=s.rfind("Type withdraw ") { let tail=&s[pos+14..]; if tail.len()>=44 { let code=&tail[..32]; if code.bytes().all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c)) && tail[32..].starts_with(" to confirm.") { master.write_all(format!("withdraw {code}\n").as_bytes()).unwrap(); sent=true; } } } }
    };
    let mut p=Poll{fd,events:1,revents:0}; while unsafe{poll(&mut p,1,50)}>0 && p.revents&1!=0 {let mut b=[0;8192]; match master.read(&mut b) {Ok(n) if n>0=>output.extend_from_slice(&b[..n]), _=>break} p.revents=0;}
    std::io::stdout().write_all(&output).unwrap(); assert!(sent,"expected withdrawal display was not observed"); assert!(status.success(),"test process failed: {status}");
}
