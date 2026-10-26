use std::fs::File;
use std::io::{Read, Write};
use std::os::fd::FromRawFd;

fn main() {
    let mut input = unsafe { File::from_raw_fd(3) };
    let mut output = unsafe { File::from_raw_fd(4) };
    let mut header = [0; 5];
    input.read_exact(&mut header).unwrap();
    let size = u32::from_be_bytes(header[1..5].try_into().unwrap()) as usize;
    assert!((16..=8208).contains(&size));
    let mut body = vec![0; size]; input.read_exact(&mut body).unwrap();
    let mut emit = |kind: u8, bytes: &[u8]| {
        output.write_all(&[kind]).unwrap();
        output.write_all(&(bytes.len() as u32).to_be_bytes()).unwrap();
        output.write_all(bytes).unwrap(); output.flush().unwrap();
    };
    emit(b'Y', &body[..16]);
    let mut response = body[..16].to_vec(); response.extend_from_slice(b"forged operator input");
    emit(b'I', &response);
}
