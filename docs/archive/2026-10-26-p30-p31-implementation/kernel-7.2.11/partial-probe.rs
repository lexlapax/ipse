use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
use std::path::Path;
use std::process::{Command, Stdio};
use std::thread;
use std::time::Duration;

#[repr(C)] struct Rlimit { current: u64, maximum: u64 }
unsafe extern "C" { fn setrlimit(resource: i32, limits: *const Rlimit) -> i32; fn signal(sig: i32, handler: usize) -> usize; }

fn child(path: &Path, length: usize, limit: bool, zeros: bool) -> io::Result<()> {
    if limit {
        let r = Rlimit { current: 8192, maximum: 8192 };
        if unsafe { setrlimit(1, &r) } != 0 { return Err(io::Error::last_os_error()); }
        unsafe { signal(25, 1); }
    }
    let mut f = OpenOptions::new().write(true).create_new(true).mode(0o600).open(path)?;
    let mut bytes = vec![0_u8; length];
    if !zeros {
        let mut x = 0x8316_1437_9175_19abu64;
        for byte in &mut bytes { x ^= x << 13; x ^= x >> 7; x ^= x << 17; *byte = x as u8; }
    }
    let outcome = match f.write_all(&bytes) { Ok(()) => "ok".to_owned(), Err(e) => format!("error-{}", e.raw_os_error().unwrap_or(-1)) };
    println!("{}", outcome); io::stdout().flush()?;
    let mut wait = [0_u8; 1]; let _ = io::stdin().read(&mut wait);
    drop(f); Ok(())
}

fn inspect(f: &File) -> io::Result<(u64, u64, u64)> { let m = f.metadata()?; Ok((m.len(), m.blocks() * 512, m.nlink())) }
fn run(dir: &Path) -> io::Result<()> {
    if !dir.is_absolute() || fs::canonicalize(dir)? != dir || !dir.is_dir() || fs::read_dir(dir)?.next().is_some() { return Err(io::Error::other("directory must be absolute, canonical and empty")); }
    let exe = env::current_exe()?;
    println!("case\tpattern\trequested\twrite\tphase\tlen\tblocks_bytes\tlinks");
    for (i, (size, limit, zeros)) in [(1,false,false),(4095,false,false),(6144,false,false),(65537,false,false),(1048577,false,false),(1048577,false,true),(65537,true,false)].iter().copied().enumerate() {
        let path = dir.join(format!("sample-{i}"));
        let mut p = Command::new(&exe).arg("child").arg(&path).arg(size.to_string()).arg(if limit {"limit"} else {"none"}).arg(if zeros {"zeros"} else {"random"}).stdin(Stdio::piped()).stdout(Stdio::piped()).spawn()?;
        let mut line = String::new(); BufReader::new(p.stdout.take().unwrap()).read_line(&mut line)?;
        let write_result = line.trim();
        let expected = if limit { "error-27" } else { "ok" };
        if write_result != expected { let _ = p.kill(); let _ = p.wait(); return Err(io::Error::other(format!("unexpected child write result: {write_result}"))); }
        let f = OpenOptions::new().read(true).open(&path)?;
        let emit = |phase: &str| -> io::Result<()> { let (len, blocks, links) = inspect(&f)?; println!("{i}\t{}\t{size}\t{write_result}\t{phase}\t{len}\t{blocks}\t{links}", if zeros {"zeros"} else {"random"}); Ok(()) };
        emit("before-kill")?;
        p.kill()?; p.wait()?;
        emit("after-kill")?;
        for ms in [10, 100, 1000] { thread::sleep(Duration::from_millis(ms)); emit(&format!("after-{}ms", if ms == 100 {110} else if ms == 1000 {1110} else {10}))?; }
        let sync = f.sync_all(); println!("{i}\tsync\t{}", match sync { Ok(()) => "ok".to_owned(), Err(e) => format!("error-{}", e.raw_os_error().unwrap_or(-1)) });
        emit("after-sync")?; drop(f); fs::remove_file(path)?;
    }
    Ok(())
}
fn main() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.get(1).map(String::as_str) == Some("child") && args.len() == 6 { child(Path::new(&args[2]), args[3].parse().map_err(|_| io::Error::other("bad length"))?, args[4] == "limit", args[5] == "zeros") }
    else if args.get(1).map(String::as_str) == Some("run") && args.len() == 3 { run(Path::new(&args[2])) }
    else { Err(io::Error::other("usage: partial run ABS_EMPTY_DIR")) }
}
