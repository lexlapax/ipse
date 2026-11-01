//! Deterministic Linux pipe backpressure for protected stdin delivery tests.
use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::PathBuf;

unsafe extern "C" {
    fn fcntl(fd: i32, command: i32, ...) -> i32;
}

fn main() {
    let root = PathBuf::from(std::env::args_os().nth(1).expect("fixture root"));
    assert_eq!(unsafe { fcntl(0, 1031, 4096) }, 4096);
    let mut output = File::create(root.join("worker-input")).unwrap();
    fs::write(root.join("pipe-ready"), b"ready").unwrap();
    let mut bytes = [0u8; 4096];
    std::io::stdin().read_exact(&mut bytes).unwrap();
    output.write_all(&bytes).unwrap();
    output.sync_all().unwrap();
    fs::write(root.join("pipe-partial"), b"4096").unwrap();
    // The owner must cancel this real process group after the uncertain write.
    loop {
        std::thread::park();
    }
}
