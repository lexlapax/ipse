use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, Instant};
extern "C" {
    fn unshare(flags: i32) -> i32;
    fn geteuid() -> u32;
    fn getegid() -> u32;
    fn getpid() -> i32;
    fn fork() -> i32;
    fn waitpid(pid: i32, status: *mut i32, flags: i32) -> i32;
    fn kill(pid: i32, signal: i32) -> i32;
    fn signal(number: i32, handler: usize) -> usize;
    fn mount(source: *const i8, target: *const i8, kind: *const i8, flags: usize, data: *const std::ffi::c_void) -> i32;
    fn _exit(code: i32) -> !;
}
fn write(root: &Path, name: &str, bytes: impl AsRef<[u8]>) -> io::Result<()> {
    let path = root.join(name); fs::write(&path, bytes)?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))
}
struct Init { pid: Option<i32>, root: PathBuf }
impl Drop for Init {
    fn drop(&mut self) {
        if let Some(pid) = self.pid.take() {
            unsafe { kill(pid, 9); }
            let end = Instant::now() + Duration::from_secs(2);
            while Instant::now() < end {
                let mut status = 0;
                if unsafe { waitpid(pid, &mut status, 1) } == pid { let _ = write(&self.root, "cleanup", "killed-and-reaped\n"); break; }
                std::thread::sleep(Duration::from_millis(2));
            }
        }
    }
}
fn fresh_proc() -> io::Result<()> {
    if unsafe { unshare(0x0002_0000) } != 0 { return Err(io::Error::last_os_error()); }
    // Isolate propagation BEFORE mounting anything. Both operations affect only this new mount namespace.
    if unsafe { mount(std::ptr::null(), b"/\0".as_ptr().cast(), std::ptr::null(), (1 << 18) | (1 << 14), std::ptr::null()) } != 0 { return Err(io::Error::last_os_error()); }
    if unsafe { mount(b"proc\0".as_ptr().cast(), b"/proc\0".as_ptr().cast(), b"proc\0".as_ptr().cast(), 2 | 4 | 8, std::ptr::null()) } != 0 { return Err(io::Error::last_os_error()); }
    Ok(())
}
fn init(args: &[String], parent_pidns: &Path, parent_mountns: &Path) -> io::Result<()> {
    let root = Path::new(&args[3]); let mode = &args[4];
    let pidns = fs::read_link("/proc/self/ns/pid")?;
    if unsafe { getpid() } != 1 || pidns == parent_pidns { return Err(io::Error::other("fresh PID namespace not confirmed")); }
    let inherited = fs::read_to_string("/proc/self/status")?;
    if mode == "fresh-listener" { fresh_proc()?; }
    let mountns = fs::read_link("/proc/self/ns/mnt")?;
    if mode == "fresh-listener" && mountns == parent_mountns { return Err(io::Error::other("fresh mount namespace not confirmed")); }
    write(root, "namespace.txt", format!("helper_getpid=1\nmode={mode}\nparent_pidns={}\nhelper_pidns={}\nparent_mountns={}\nhelper_mountns={}\n--- inherited status ---\n{inherited}\n--- effective status ---\n{}", parent_pidns.display(), pidns.display(), parent_mountns.display(), mountns.display(), fs::read_to_string("/proc/self/status")?))?;
    let wrapper = std::env::current_exe()?;
    let mut command = Command::new(&args[1]);
    if mode == "ordinary" { command.args(["--stdio", &args[3], "3000"]); }
    else { command.args(["--stdio-listener", &args[3], "3000", &args[5], "--"]); }
    let fixture_mode = if mode == "fresh-listener" { "own" } else { "exit" };
    let error = command.arg(wrapper).args(["--selected", &args[2], &args[3], fixture_mode, &args[5]])
        .env_clear().env("PATH", "/usr/bin:/bin").env("LANG", "C.UTF-8").exec();
    Err(error)
}
fn selected(args: &[String]) -> io::Result<()> {
    if args.len() != 6 { return Err(io::Error::other("invalid selected fixture arguments")); }
    let root = Path::new(&args[3]);
    write(root, "selected.txt", format!("selected_getpid={}\n{}", unsafe { getpid() }, fs::read_to_string("/proc/self/status")?))?;
    let error = Command::new(&args[2]).args([args[4].as_str(), args[5].as_str(), root.join("http-request-marker").to_str().unwrap()]).exec();
    Err(error)
}
fn run(args: &[String]) -> io::Result<i32> {
    if args.len() != 6 || !["inherited-listener", "ordinary", "fresh-listener"].contains(&args[4].as_str()) { return Err(io::Error::other("usage: WRAPPER ABS_HELPER ABS_FIXTURE PRIVATE_ROOT MODE PORT")); }
    for path in [&args[1], &args[2], &args[3]] { if !Path::new(path).is_absolute() { return Err(io::Error::other("absolute paths required")); } }
    let port = args[5].parse::<u16>().map_err(io::Error::other)?;
    if port == 0 { return Err(io::Error::other("positive port required")); }
    if unsafe { signal(17, 0) } == usize::MAX { return Err(io::Error::last_os_error()); }
    let uid = unsafe { geteuid() }; let gid = unsafe { getegid() };
    if unsafe { unshare(0x1000_0000) } != 0 { return Err(io::Error::last_os_error()); }
    fs::write("/proc/self/setgroups", "deny")?;
    fs::write("/proc/self/uid_map", format!("0 {uid} 1\n"))?;
    fs::write("/proc/self/gid_map", format!("0 {gid} 1\n"))?;
    let parent_pidns = fs::read_link("/proc/self/ns/pid")?;
    let parent_mountns = fs::read_link("/proc/self/ns/mnt")?;
    if unsafe { unshare(0x2000_0000) } != 0 { return Err(io::Error::last_os_error()); }
    let pid = unsafe { fork() };
    if pid < 0 { return Err(io::Error::last_os_error()); }
    if pid == 0 {
        let error = init(args, &parent_pidns, &parent_mountns).unwrap_err();
        let _ = write(Path::new(&args[3]), "unavailable", format!("namespace setup or exec: {error}\n"));
        unsafe { _exit(77); }
    }
    let mut owned = Init { pid: Some(pid), root: PathBuf::from(&args[3]) };
    let end = Instant::now() + Duration::from_secs(8);
    let mut status = 0;
    loop {
        let result = unsafe { waitpid(pid, &mut status, 1) };
        if result == pid { owned.pid = None; break; }
        if result < 0 { return Err(io::Error::last_os_error()); }
        if Instant::now() >= end { return Err(io::Error::other("owned helper deadline exceeded")); }
        std::thread::sleep(Duration::from_millis(2));
    }
    write(&owned.root, "cleanup", format!("reaped=true\nwait_status={status}\n"))?;
    Ok(if status & 0x7f == 0 { (status >> 8) & 255 } else { 128 + (status & 0x7f) })
}
fn main() {
    let args = std::env::args().collect::<Vec<_>>();
    if args.get(1).is_some_and(|s| s == "--selected") {
        if let Err(error) = selected(&args) { eprintln!("selected fixture failed: {error}"); }
        std::process::exit(1);
    }
    let code = match run(&args) { Ok(code) => code, Err(error) => { if let Some(root) = args.get(3) { let _ = write(Path::new(root), "unavailable", error.to_string()); } eprintln!("namespace control unavailable: {error}"); 77 } };
    std::process::exit(code);
}
