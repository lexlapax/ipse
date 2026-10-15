use std::fs;
use std::io::Write;
use std::os::unix::process::CommandExt;
use std::process::Command;
use std::time::{Duration, Instant};
#[repr(C)]
#[derive(Default)]
struct Limit { soft: u64, hard: u64 }
extern "C" {
    fn getrlimit(resource: i32, value: *mut Limit) -> i32;
    fn setrlimit(resource: i32, value: *const Limit) -> i32;
    fn kill(pid: i32, signal: i32) -> i32;
    fn getppid() -> i32;
    fn setsid() -> i32;
    fn signal(number: i32, handler: usize) -> usize;
}
fn wait(path: &str) {
    let deadline = Instant::now() + Duration::from_secs(5);
    while !std::path::Path::new(path).exists() {
        assert!(Instant::now() < deadline, "gate timed out");
        std::thread::sleep(Duration::from_millis(10));
    }
}
fn denied(value: i32) {
    assert_eq!(value, -1);
    assert_eq!(std::io::Error::last_os_error().raw_os_error(), Some(1));
}
fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args[1].as_str() {
        "network" => {
            let result = std::net::TcpStream::connect(format!("127.0.0.1:{}", args[2]));
            if args[3] == "allow" { result.unwrap(); }
            else { assert_eq!(result.unwrap_err().raw_os_error(), Some(1)); }
            println!("network {}", args[3]);
        }
        "signals" => {
            denied(unsafe { kill(args[2].parse().unwrap(), 0) });
            denied(unsafe { kill(getppid(), 0) });
            println!("host signals denied");
        }
        "limits" => {
            for (resource, cap) in [(4, 0), (8, 256), (1, 64 * 1024 * 1024), (0, 7)] {
                let mut value = Limit::default();
                assert_eq!(unsafe { getrlimit(resource, &mut value) }, 0);
                assert!(value.soft <= cap && value.hard <= cap);
            }
            denied(unsafe { setrlimit(8, &Limit { soft: 1024, hard: 1024 }) });
            let mut files = Vec::new();
            loop {
                match fs::File::open("/dev/null") {
                    Ok(file) => files.push(file),
                    Err(error) => { assert_eq!(error.raw_os_error(), Some(24)); break; }
                }
            }
            assert!(files.len() < 256);
            drop(files);
            assert_eq!(unsafe { setrlimit(1, &Limit { soft: 1024 * 1024, hard: 1024 * 1024 }) }, 0);
            unsafe { signal(25, 1); } // Ignore SIGXFSZ so the write reports EFBIG.
            let mut file = fs::File::create("limited-file").unwrap();
            let error = file.write_all(&vec![0u8; 2 * 1024 * 1024]).unwrap_err();
            assert_eq!(error.raw_os_error(), Some(27));
            assert!(file.metadata().unwrap().len() <= 1024 * 1024);
            println!("resource limits enforced");
        }
        "detach" => {
            let mut command = Command::new(std::env::current_exe().unwrap());
            command.args(["detached", &args[2]]);
            unsafe { command.pre_exec(|| { assert!(setsid() > 0); Ok(()) }); }
            let _child = command.spawn().unwrap();
            wait("detached-ready");
        }
        "detached" => {
            fs::write("detached-ready", std::process::id().to_string()).unwrap();
            wait("release-detached");
            assert!(fs::read(&args[2]).is_err());
            assert!(fs::write(&args[2], "changed").is_err());
            fs::write("detached-confined", "yes").unwrap();
        }
        _ => panic!("unknown probe"),
    }
}
