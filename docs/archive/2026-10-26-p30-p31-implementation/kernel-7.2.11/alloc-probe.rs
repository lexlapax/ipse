use std::env;
use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
use std::os::unix::process::ExitStatusExt;
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::time::Duration;

struct OwnedChild(Option<Child>);
impl Drop for OwnedChild {
    fn drop(&mut self) {
        if let Some(child) = self.0.as_mut() { let _ = child.kill(); let _ = child.wait(); }
    }
}

fn child(path: &str, len: usize) -> Result<(), Box<dyn std::error::Error>> {
    let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(path)?;
    let mut state = 0x9e3779b97f4a7c15u64;
    let mut buffer = [0u8; 65536];
    let mut remaining = len;
    while remaining != 0 {
        for b in &mut buffer {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17;
            *b = state as u8;
        }
        let n = remaining.min(buffer.len());
        file.write_all(&buffer[..n])?;
        remaining -= n;
    }
    // Keep the file open and dirty; the parent kills this writer after observing it.
    std::io::stdout().write_all(b"R")?;
    std::io::stdout().flush()?;
    loop { std::thread::sleep(Duration::from_secs(1)); }
}

fn parent(root: &str) -> Result<(), Box<dyn std::error::Error>> {
    let root = Path::new(root);
    let exe = env::current_exe()?;
    println!("bytes\tbefore_blocks\tafter_kill_blocks\tafter_10ms\tafter_100ms\tafter_1000ms\tsignal");
    for size in [1usize, 4095, 4096, 6144, 65535, 65536, 1048576, 8388608] {
        let path = root.join(format!("dense-{size}"));
        let mut process = OwnedChild(Some(Command::new(&exe).arg("child").arg(&path).arg(size.to_string())
            .stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::inherit()).spawn()?));
        let mut ready = [0u8; 1];
        process.0.as_mut().ok_or("missing child")?.stdout.as_mut().ok_or("missing child output")?.read_exact(&mut ready)?;
        if ready != *b"R" { return Err("unexpected readiness".into()); }
        let handle = OpenOptions::new().read(true).open(&path)?;
        let initial = handle.metadata()?;
        if initial.len() != size as u64 { return Err("unexpected file length".into()); }
        process.0.as_mut().ok_or("missing child")?.kill()?;
        let status = process.0.as_mut().ok_or("missing child")?.wait()?;
        let _reaped = process.0.take();
        if status.signal() != Some(9) { return Err("writer death was not SIGKILL".into()); }
        let after = handle.metadata()?.blocks();
        std::thread::sleep(Duration::from_millis(10)); let p10 = handle.metadata()?.blocks();
        std::thread::sleep(Duration::from_millis(90)); let p100 = handle.metadata()?.blocks();
        std::thread::sleep(Duration::from_millis(900)); let p1000 = handle.metadata()?.blocks();
        if handle.metadata()?.len() != size as u64 { return Err("file length changed".into()); }
        println!("{size}\t{}\t{after}\t{p10}\t{p100}\t{p1000}\t9", initial.blocks());
        fs::remove_file(path)?;
    }
    Ok(())
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let result = match args.as_slice() {
        [_, mode, path, size] if mode == "child" => size.parse::<usize>().map_err(|e| e.into()).and_then(|n| child(path, n)),
        [_, mode, path] if mode == "parent" => parent(path),
        _ => Err("usage: probe parent DIR or child PATH LENGTH".into()),
    };
    if let Err(error) = result { eprintln!("probe failed: {error}"); std::process::exit(1); }
}
