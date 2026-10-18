use std::ffi::CString;
use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::path::Path;
use std::thread;
use std::time::Duration;

unsafe extern "C" {
    fn mkfifo(path: *const std::ffi::c_char, mode: u32) -> i32;
}

fn main() {
    thread::spawn(|| {
        let _ = std::io::stdin().read_to_end(&mut Vec::new());
        std::process::exit(2);
    });
    let args: Vec<String> = std::env::args().collect();
    let path = CString::new(args[1].clone()).unwrap();
    assert_eq!(unsafe { mkfifo(path.as_ptr(), 0o600) }, 0);
    let mut fifo = OpenOptions::new().read(true).write(true).open(&args[1]).unwrap();
    println!("ready");
    std::io::stdout().flush().unwrap();
    fifo.read_exact(&mut [0; 1]).unwrap();
    println!("writing");
    std::io::stdout().flush().unwrap();
    while !Path::new(&args[2]).exists() {
        thread::sleep(Duration::from_millis(5));
    }
    let mut remaining = 262_143;
    let mut buffer = [0; 4096];
    while remaining > 0 {
        let size = remaining.min(buffer.len());
        let received = fifo.read(&mut buffer[..size]).unwrap();
        assert!(received > 0);
        remaining -= received;
    }
    fs::write(&args[3], "drained").unwrap();
}
