//! Deliberately incomplete private protocol fixture; it never opens a terminal.
use std::fs::File;
use std::io::{Read, Write};
use std::os::fd::FromRawFd;
use std::time::{Duration, Instant};
extern "C" { fn fcntl(fd: i32, command: i32, ...) -> i32; }
fn frame(output: &mut File, kind: u8, body: &[u8]) {
    output.write_all(&[kind]).unwrap();
    output.write_all(&(body.len() as u32).to_be_bytes()).unwrap();
    output.write_all(body).unwrap();
}
fn main() {
    let mut input = unsafe { File::from_raw_fd(3) };
    let mut output = unsafe { File::from_raw_fd(4) };
    let mut header = [0; 5]; input.read_exact(&mut header).unwrap();
    let count = u32::from_be_bytes(header[1..].try_into().unwrap()) as usize;
    assert!(header[0] == b'd' && (17..=4096).contains(&count));
    let mut body = vec![0; count]; input.read_exact(&mut body).unwrap();
    let nonce = &body[..16];
    let mut ready = nonce.to_vec();
    ready.extend_from_slice(&(std::process::id() + 1).to_be_bytes());
    ready.extend_from_slice(&std::process::id().to_be_bytes());
    frame(&mut output, b'g', &ready); frame(&mut output, b'y', nonce);
    frame(&mut output, b'c', nonce);
    let root = std::env::current_exe().unwrap().parent().unwrap().to_path_buf();
    std::fs::write(root.join("native-c-emitted"), b"c").unwrap();
    #[cfg(target_os = "linux")]
    let nonblock = 0x800;
    #[cfg(target_os = "macos")]
    let nonblock = 0x4;
    let flags = unsafe { fcntl(3, 3) }; assert!(flags >= 0);
    assert_eq!(unsafe { fcntl(3, 4, flags | nonblock) }, 0);
    // A c receipt alone is not cleanup. The host must still enforce its deadline
    // and send cancellation rather than waiting forever for a missing R.
    let until = Instant::now() + Duration::from_secs(8);
    while Instant::now() < until {
        let mut byte = [0; 1];
        match input.read(&mut byte) {
            Ok(0) => break,
            Ok(_) => {
                if byte[0] == b'C' { std::fs::write(root.join("host-cancel-received"), b"C").unwrap(); }
            },
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => std::thread::sleep(Duration::from_millis(10)),
            Err(_) => break,
        }
    }
}
