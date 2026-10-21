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

#[cfg(target_os = "linux")]
fn ipv6_only_listener(port: u16) -> TcpListener {
    use std::os::fd::{AsRawFd, FromRawFd};
    #[repr(C)]
    struct Address { family: u16, port: u16, flow: u32, address: [u8; 16], scope: u32 }
    extern "C" {
        fn socket(domain: i32, kind: i32, protocol: i32) -> i32;
        fn setsockopt(fd: i32, level: i32, option: i32, value: *const i32, size: u32) -> i32;
        fn bind(fd: i32, address: *const Address, size: u32) -> i32;
        fn listen(fd: i32, backlog: i32) -> i32;
    }
    let fd = unsafe { socket(10, 1 | 0x80000, 0) };
    assert!(fd >= 0, "fixture IPv6 socket: {}", std::io::Error::last_os_error());
    let listener = unsafe { TcpListener::from_raw_fd(fd) };
    let one = 1_i32;
    assert_eq!(unsafe { setsockopt(listener.as_raw_fd(), 41, 26, &one, 4) }, 0);
    let address = Address { family: 10, port: port.to_be(), flow: 0, address: [0; 16], scope: 0 };
    assert_eq!(unsafe { bind(listener.as_raw_fd(), &address, std::mem::size_of::<Address>() as u32) }, 0);
    assert_eq!(unsafe { listen(listener.as_raw_fd(), 1) }, 0);
    listener
}

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
    assert!(["own", "occupied", "wildcard", "ipv6-wildcard", "namespace"].contains(&mode.as_str()), "unknown fixture mode");
    if mode == "namespace" {
        if let Err(error) = separate_namespace() {
            eprintln!("namespace capability unavailable: {error}");
            std::process::exit(77);
        }
    }

    let port: u16 = args[2].parse().unwrap();
    #[cfg(target_os = "linux")]
    let _ipv6 = if mode == "ipv6-wildcard" { Some(ipv6_only_listener(port)) } else { None };
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
