//! Linux-only disposable probe: a regular-file lease does not fence its name.
//! Pass a new private directory; the probe leaves its two empty files there.
#![cfg(target_os = "linux")]

use std::fs::{self, OpenOptions};
use std::os::fd::AsRawFd;
use std::path::Path;
use std::process::Command;

unsafe extern "C" {
    fn fcntl(fd: i32, cmd: i32, ...) -> i32;
    fn flock(fd: i32, op: i32) -> i32;
}

const F_SETLEASE: i32 = 1024;
const F_GETLEASE: i32 = 1025;
const F_WRLCK: i32 = 1;
const F_UNLCK: i32 = 2;
const LOCK_EX_NONBLOCK: i32 = 2 | 4;

fn main() {
    let args: Vec<_> = std::env::args().collect();
    assert!(args.len() == 3, "expected mode and private fixture directory");
    let root = Path::new(&args[2]);
    let path = root.join("source.lock");
    let held = root.join("held.lock");

    if args[1] == "replace" {
        fs::rename(&path, &held).expect("rename original lock");
        let replacement = OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .open(&path)
            .expect("create replacement lock");
        assert_eq!(unsafe { flock(replacement.as_raw_fd(), LOCK_EX_NONBLOCK) }, 0);
        println!("replacement_lock_acquired");
        return;
    }

    assert_eq!(args[1], "probe");
    let original = OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .open(&path)
        .expect("create original lock");
    assert_eq!(unsafe { flock(original.as_raw_fd(), LOCK_EX_NONBLOCK) }, 0);
    if unsafe { fcntl(original.as_raw_fd(), F_SETLEASE, F_WRLCK) } != 0 {
        eprintln!("lease_unavailable: {}", std::io::Error::last_os_error());
        std::process::exit(2);
    }
    let child = Command::new(std::env::current_exe().expect("current executable"))
        .args(["replace", &args[2]])
        .output()
        .expect("run replacement process");
    assert!(child.status.success(), "replacement process failed");
    assert_eq!(child.stdout, b"replacement_lock_acquired\n");
    assert_eq!(unsafe { fcntl(original.as_raw_fd(), F_GETLEASE) }, F_WRLCK);
    assert_eq!(unsafe { fcntl(original.as_raw_fd(), F_SETLEASE, F_UNLCK) }, 0);
    println!("replacement_lock_acquired_while_original_was_leased");
}
