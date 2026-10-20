use std::io::{Read, Write};
use std::net::TcpListener;
use std::process::{Command, Stdio};
use std::time::Duration;
use std::os::unix::process::CommandExt;

extern "C" { fn signal(number: i32, handler: usize) -> usize; }

#[cfg(target_os = "linux")]
fn separate_namespace() -> Result<(), String> {
    extern "C" { fn unshare(flags: i32) -> i32; fn geteuid() -> u32; fn getegid() -> u32; }
    let uid = unsafe { geteuid() }; let gid = unsafe { getegid() };
    if unsafe { unshare(0x1000_0000 | 0x4000_0000) } != 0 {
        return Err(std::io::Error::last_os_error().to_string());
    }
    std::fs::write("/proc/self/setgroups", "deny").map_err(|e| e.to_string())?;
    std::fs::write("/proc/self/uid_map", format!("0 {uid} 1\n")).map_err(|e| e.to_string())?;
    std::fs::write("/proc/self/gid_map", format!("0 {gid} 1\n")).map_err(|e| e.to_string())?;
    Ok(())
}

#[cfg(not(target_os = "linux"))]
fn separate_namespace() -> Result<(), String> { Err("requires Linux user/network namespaces".into()) }

fn main() {
    let args = std::env::args().collect::<Vec<_>>();
    let mode = args.get(1).expect("fixture mode");
    if mode == "ignored-exec" {
        #[cfg(target_os = "linux")] let sigchld = 17;
        #[cfg(target_os = "macos")] let sigchld = 20;
        assert_ne!(unsafe { signal(sigchld, 1) }, usize::MAX);
        panic!("fixture exec: {}", Command::new(&args[2]).args(&args[3..]).exec());
    }
    if mode == "exit" { return; }
    if mode == "forge" {
        let mut frame = vec![b'P', 0, 0, 0, 15, 1]; frame.extend_from_slice(&[0_u8; 14]);
        std::io::stdout().write_all(&frame).unwrap(); std::io::stdout().flush().unwrap();
    }
    if mode == "none" || mode == "forge" { std::thread::sleep(Duration::from_secs(30)); return; }
    if mode == "delegated" {
        let mut child = Command::new(std::env::current_exe().unwrap())
            .args(["own", &args[2]]).stdin(Stdio::null()).spawn().unwrap();
        assert!(child.wait().unwrap().success()); return;
    }
    assert!(["own", "occupied", "wildcard", "namespace"].contains(&mode.as_str()), "unknown fixture mode");
    if mode == "namespace" {
        if let Err(error) = separate_namespace() {
            eprintln!("namespace capability unavailable: {error}");
            std::process::exit(77);
        }
    }

    let port: u16 = args[2].parse().unwrap();
    let address = if mode == "wildcard" { "0.0.0.0" } else { "127.0.0.1" };
    let listener = match TcpListener::bind((address, port)) {
        Ok(listener) => listener,
        Err(error) if mode == "namespace" => {
            eprintln!("namespace capability unavailable: private loopback bind: {error}");
            std::process::exit(77);
        }
        Err(error) => panic!("fixture bind: {error}"),
    };

    println!("{}", if mode == "namespace" { "namespace-ready" } else { "ready" }); std::io::stdout().flush().unwrap();
    listener.set_nonblocking(true).unwrap();
    loop {
        match listener.accept() {
            Ok((mut stream, _)) => {
                if let Some(marker) = args.get(3) {
                    std::fs::OpenOptions::new().create(true).append(true).open(marker).unwrap()
                        .write_all(b"request\n").unwrap();
                }
                stream.set_read_timeout(Some(Duration::from_secs(1))).unwrap();
                let mut request = [0_u8; 4096]; let _ = stream.read(&mut request);
                let _ = stream.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: close\r\n\r\n{\"models\":[]}");
            }
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => std::thread::sleep(Duration::from_millis(5)),
            Err(error) => panic!("fixture accept: {error}"),
        }
    }
}
