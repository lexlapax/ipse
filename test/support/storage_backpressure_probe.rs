use std::fs::OpenOptions;
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::process::CommandExt;
use std::os::fd::AsRawFd;
use std::process::Command;
extern "C" { fn raise(signal: i32) -> i32; fn flock(fd: i32, op: i32) -> i32; }
fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).is_some_and(|v| v == "--storage-write") {
        let parent = std::path::Path::new(&args[2]).parent().unwrap();
        let _lease = OpenOptions::new().read(true).write(true).create(true).mode(0o600)
            .open(parent.join(".writer.lock")).unwrap();
        assert_eq!(unsafe { flock(_lease.as_raw_fd(), 2 | 4) }, 0);
        let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600)
            .open(format!("{}.pid", args[2])).unwrap();
        write!(file, "{}", std::process::id()).unwrap();
        file.sync_all().unwrap();
        std::io::stdout().write_all(b"R").unwrap();
        std::io::stdout().flush().unwrap();
        #[cfg(target_os = "linux")]
        let stop = 19;
        #[cfg(target_os = "macos")]
        let stop = 17;
        unsafe { raise(stop); }
        loop { std::thread::park(); }
    }
    let _ = Command::new(env!("IPSE_REAL_HELPER")).args(&args[1..]).exec();
    std::process::exit(1);
}
