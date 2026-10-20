#[cfg(target_os = "linux")]
mod implementation {
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt};
use std::path::{Path, PathBuf};

const MAX_DESCRIPTOR: usize = 1_048_576;
const MAX_PROTOCOL: usize = 8192;
const NONBLOCK: i32 = 0x800;
#[cfg(target_os = "linux")]
const NOFOLLOW: i32 = 0x20000;
#[cfg(not(target_os = "linux"))]
const NOFOLLOW: i32 = 0x100;

#[derive(Clone, Debug)]
struct Stage { token: String, timeout: u64, output: PathBuf, argv: Vec<String> }
struct Bootstrap { output: PathBuf, cells: PathBuf, preparation: Stage, finalization: Stage }
struct Decoder<'a> { bytes: &'a [u8], offset: usize }
impl<'a> Decoder<'a> {
    fn take(&mut self, size: usize) -> Result<&'a [u8], String> {
        let end = self.offset.checked_add(size).ok_or("descriptor overflow")?;
        let bytes = self.bytes.get(self.offset..end).ok_or("truncated sequence descriptor")?;
        self.offset = end; Ok(bytes)
    }
    fn number(&mut self) -> Result<u32, String> { Ok(u32::from_be_bytes(self.take(4)?.try_into().unwrap())) }
    fn string(&mut self) -> Result<String, String> {
        let size = self.number()? as usize;
        if size > 65_536 { return Err("sequence string exceeds bound".into()); }
        let value = std::str::from_utf8(self.take(size)?).map_err(|_| "non-UTF8 sequence string")?;
        if value.as_bytes().contains(&0) { return Err("NUL in sequence string".into()); }
        Ok(value.into())
    }
    fn path(&mut self) -> Result<PathBuf, String> {
        let path = PathBuf::from(self.string()?);
        if !path.is_absolute() || path.components().any(|c| matches!(c, std::path::Component::ParentDir | std::path::Component::CurDir))
            || path.components().collect::<PathBuf>().as_os_str() != path.as_os_str() {
            return Err("sequence requires absolute normalized paths".into());
        }
        Ok(path)
    }
    fn stage(&mut self) -> Result<Stage, String> {
        let token = self.string()?;
        if token.len() != 32 || !token.bytes().all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c)) {
            return Err("invalid sequence token".into());
        }
        let timeout = u64::from_be_bytes(self.take(8)?.try_into().unwrap());
        if !(1..=86_400_000).contains(&timeout) { return Err("invalid sequence timeout".into()); }
        let output = self.path()?;
        let count = self.number()?;
        if !(1..=121).contains(&count) { return Err("invalid sequence argument count".into()); }
        let argv = (0..count).map(|_| self.string()).collect::<Result<Vec<_>, _>>()?;
        if !Path::new(&argv[0]).is_absolute() || argv.iter().map(String::len).sum::<usize>() > 65_536 {
            return Err("invalid sequence executable or argument bound".into());
        }
        Ok(Stage { token, timeout, output, argv })
    }
    fn finish(self) -> Result<(), String> {
        if self.offset == self.bytes.len() { Ok(()) } else { Err("trailing sequence descriptor bytes".into()) }
    }
}
fn bootstrap(bytes: &[u8]) -> Result<Bootstrap, String> {
    let mut read = Decoder { bytes, offset: 0 };
    if read.take(8)? != b"IPSEQ001" { return Err("unsupported sequence descriptor".into()); }
    let result = Bootstrap { output: read.path()?, cells: read.path()?, preparation: read.stage()?, finalization: read.stage()? };
    read.finish()?;
    distinct(&[result.preparation.clone(), result.finalization.clone()], &result.output)?;
    Ok(result)
}
fn cells(bytes: &[u8]) -> Result<Vec<Stage>, String> {
    let mut read = Decoder { bytes, offset: 0 };
    if read.take(8)? != b"IPSCELL1" { return Err("unsupported cell descriptor".into()); }
    let count = read.number()?;
    if !(1..=64).contains(&count) { return Err("invalid sequence cell count".into()); }
    let stages = (0..count).map(|_| read.stage()).collect::<Result<Vec<_>, _>>()?;
    read.finish()?; Ok(stages)
}
fn distinct(stages: &[Stage], output: &Path) -> Result<(), String> {
    for (index, stage) in stages.iter().enumerate() {
        if stage.output == output || stages[..index].iter().any(|other| other.token == stage.token || other.output == stage.output) {
            return Err("duplicate sequence token or output".into());
        }
    }
    Ok(())
}
fn descriptor(path: &Path) -> Result<(Vec<u8>, String), String> {
    let mut file = OpenOptions::new().read(true).custom_flags(NOFOLLOW | NONBLOCK).open(path).map_err(|e| e.to_string())?;
    let before = file.metadata().map_err(|e| e.to_string())?;
    extern "C" { fn geteuid() -> u32; }
    if !before.is_file() || before.uid() != unsafe { geteuid() } || before.mode() & 0o077 != 0 || before.len() > MAX_DESCRIPTOR as u64 {
        return Err("sequence descriptor must be a bounded owner-only regular file".into());
    }
    let mut bytes = Vec::new();
    (&mut file).take(MAX_DESCRIPTOR as u64 + 1).read_to_end(&mut bytes).map_err(|e| e.to_string())?;
    let after = file.metadata().map_err(|e| e.to_string())?;
    if bytes.len() > MAX_DESCRIPTOR || before.len() != bytes.len() as u64 || before.len() != after.len()
        || before.mtime() != after.mtime() || before.mtime_nsec() != after.mtime_nsec()
        || before.ctime() != after.ctime() || before.ctime_nsec() != after.ctime_nsec() {
        return Err("sequence descriptor changed while reading".into());
    }
    let identity = format!("device={} inode={} bytes={} uid={} mode={:o}\n", before.dev(), before.ino(), before.len(), before.uid(), before.mode());
    Ok((bytes, identity))
}
fn save(root: &Path, name: &str, bytes: &[u8]) -> Result<(), String> {
    let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).custom_flags(NOFOLLOW)
        .open(root.join(name)).map_err(|e| e.to_string())?;
    file.write_all(bytes).and_then(|_| file.sync_all()).map_err(|e| e.to_string())?;
    File::open(root).and_then(|f| f.sync_all()).map_err(|e| e.to_string())
}
fn put_string(bytes: &mut Vec<u8>, value: &str) {
    bytes.extend_from_slice(&(value.len() as u32).to_be_bytes()); bytes.extend_from_slice(value.as_bytes());
}
fn claim(stage: &Stage) -> Vec<u8> {
    let mut bytes = b"IPSECLM1".to_vec(); put_string(&mut bytes, &stage.token);
    bytes.extend_from_slice(&stage.timeout.to_be_bytes()); put_string(&mut bytes, stage.output.to_str().unwrap());
    bytes.extend_from_slice(&(stage.argv.len() as u32).to_be_bytes());
    for arg in &stage.argv { put_string(&mut bytes, arg); } bytes
}
#[derive(Clone, Copy)]
struct Status { complete: bool, cleanup: bool }
fn protocol(bytes: &[u8], receipt: &[u8]) -> Result<Status, String> {
    if bytes.len() < 12 || bytes[0] != b'M' { return Err("missing native sequence measurement".into()); }
    let size = u32::from_be_bytes(bytes[1..5].try_into().unwrap()) as usize;
    if size == 0 || size > 4096 || bytes.len() != 5 + size + 7 || &bytes[5..5 + size] != receipt
        || &bytes[5 + size..10 + size] != b"T\0\0\0\x02" || bytes[10 + size] > 1 || bytes[11 + size] > 1 {
        return Err("invalid native sequence completion protocol".into());
    }
    Ok(Status { complete: bytes[10 + size] == 1, cleanup: bytes[11 + size] == 1 })
}

#[cfg(target_os = "linux")]
mod linux {
    use super::*;
    use std::os::fd::AsRawFd;
    use std::process::{Child, Command, Stdio};
    use std::time::{Duration, Instant};
    #[repr(C)] struct PollFd { fd: i32, events: i16, revents: i16 }
    extern "C" { fn poll(fds: *mut PollFd, count: usize, timeout: i32) -> i32; fn signal(number: i32, handler: usize) -> usize; }
    struct Owned { child: Child }
    impl Drop for Owned {
        fn drop(&mut self) {
            drop(self.child.stdin.take());
            if matches!(self.child.try_wait(), Ok(None)) { let _ = self.child.kill(); let _ = self.child.try_wait(); }
        }
    }
    fn admitted() -> Result<(), String> {
        let root = PathBuf::from(std::env::var_os("IPSE_MEASURE_ROOT").ok_or("sequence requires measured root")?);
        let name = root.file_name().and_then(|s| s.to_str()).unwrap_or("");
        let token = name.strip_prefix("ipse-run-").unwrap_or("");
        if token.len() != 32 || !token.bytes().all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c)) { return Err("invalid sequence measured root".into()); }
        let membership = fs::read_to_string("/proc/self/cgroup").map_err(|e| e.to_string())?;
        let relative = membership.lines().find_map(|s| s.strip_prefix("0::")).ok_or("sequence cgroup unavailable")?;
        let current = Path::new("/sys/fs/cgroup").join(relative.trim_start_matches('/'));
        if !current.starts_with(&root) || current == root { return Err("sequence is outside measured application".into()); }
        Ok(())
    }
    fn run_stage(root: &Path, index: usize, stage: &Stage) -> Result<Status, String> {
        let executable = std::env::current_exe().map_err(|e| e.to_string())?;
        let executable_text = executable.to_str().ok_or("non-UTF8 sequence helper path")?;
        let mut args = vec!["--measure-stage".to_string(), "cell".into(), stage.token.clone(),
            stage.timeout.to_string(), stage.output.to_str().unwrap().into(), "--".into()];
        args.extend(stage.argv.clone());
        if executable_text.len() + args.iter().map(String::len).sum::<usize>() > 65_536 {
            return Err("native sequence launch arguments exceed bound".into());
        }
        save(root, &format!("stage-{index:03}.claim"), &claim(stage))?;
        let mut owned = Owned { child: Command::new(executable)
            .args(&args).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null())
            .spawn().map_err(|e| format!("claimed stage launch failed: {e}"))? };
        let mut output = owned.child.stdout.take().unwrap();
        let mut bytes = Vec::new(); let mut eof = false; let mut status = None;
        let deadline = Instant::now() + Duration::from_millis(stage.timeout + 8000);
        let outcome = loop {
            if status.is_none() {
                match owned.child.try_wait() {
                    Ok(value) => status = value,
                    Err(_) => break Err("native stage collector wait failed".to_string()),
                }
            }
            if eof && status.is_some() { break Ok(()); }
            if Instant::now() >= deadline { break Err("native stage completion deadline exceeded".to_string()); }
            let mut fd = PollFd { fd: if eof { -1 } else { output.as_raw_fd() }, events: 1, revents: 0 };
            let result = unsafe { poll(&mut fd, 1, 10) };
            if result < 0 && std::io::Error::last_os_error().kind() != std::io::ErrorKind::Interrupted {
                break Err("native stage output poll failed".to_string());
            }
            if fd.revents & (1 | 8 | 16) != 0 {
                let mut chunk = [0_u8; 1024];
                match output.read(&mut chunk) {
                    Ok(0) => eof = true,
                    Ok(size) => {
                        if bytes.len() + size > MAX_PROTOCOL { break Err("native stage output exceeds bound".to_string()); }
                        bytes.extend_from_slice(&chunk[..size]);
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::Interrupted => (),
                    Err(_) => break Err("native stage output read failed".to_string()),
                }
            }
        };
        save(root, &format!("stage-{index:03}.protocol"), &bytes)?;
        outcome?;
        if !status.unwrap().success() { return Err("native stage collector exit unconfirmed".into()); }
        let (receipt, identity) = descriptor(&stage.output.join("receipt.json"))?;
        save(root, &format!("stage-{index:03}.receipt"), &receipt)?;
        save(root, &format!("stage-{index:03}.receipt-identity"), identity.as_bytes())?;
        let result = protocol(&bytes, &receipt)?;
        save(root, &format!("stage-{index:03}.status"), &[u8::from(result.complete), u8::from(result.cleanup)])?;
        if !result.cleanup { return Err("native stage cleanup unconfirmed".into()); }
        Ok(result)
    }
    pub fn execute(path: &Path) -> Result<(), String> {
        admitted()?;
        if unsafe { signal(17, 0) } == usize::MAX { return Err("cannot retain sequence collectors".into()); }
        let (bytes, identity) = descriptor(path)?; let launch = bootstrap(&bytes)?;
        match fs::symlink_metadata(&launch.cells) {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => (),
            _ => return Err("sequence cells descriptor is not fresh".into()),
        }
        fs::DirBuilder::new().mode(0o700).create(&launch.output).map_err(|e| e.to_string())?;
        File::open(launch.output.parent().ok_or("sequence output has no parent")?)
            .and_then(|f| f.sync_all()).map_err(|e| e.to_string())?;
        save(&launch.output, "bootstrap.bin", &bytes)?; save(&launch.output, "bootstrap.identity", identity.as_bytes())?;
        let prep = run_stage(&launch.output, 0, &launch.preparation)?;
        if !prep.complete { return Err("sequence preparation failed".into()); }
        let (bytes, identity) = descriptor(&launch.cells)?; let selected = cells(&bytes)?;
        let mut all = vec![launch.preparation.clone(), launch.finalization.clone()]; all.extend(selected.clone());
        distinct(&all, &launch.output)?;
        save(&launch.output, "cells.bin", &bytes)?; save(&launch.output, "cells.identity", identity.as_bytes())?;
        let mut completed = true;
        for (index, stage) in selected.iter().enumerate() { completed &= run_stage(&launch.output, index + 1, stage)?.complete; }
        completed &= run_stage(&launch.output, selected.len() + 1, &launch.finalization)?.complete;
        let summary = format!("{{\"version\":1,\"stages\":{},\"complete\":{completed},\"cleanup_confirmed\":true}}\n", selected.len() + 2);
        save(&launch.output, "sequence.json", summary.as_bytes())?;
        if completed { Ok(()) } else { Err("sequence contains failed first stages".into()) }
    }
}

pub fn run(args: &[String]) -> Result<(), String> {
    if args.len() != 3 || !Path::new(&args[2]).is_absolute() { return Err("usage: --measure-sequence ABSOLUTE_BOOTSTRAP".into()); }
    #[cfg(target_os = "linux")] { linux::execute(Path::new(&args[2])) }
    #[cfg(not(target_os = "linux"))] { Err("measured sequencing requires Linux cgroup-v2 support".into()) }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn stage(n: u32) -> Stage {
        Stage { token: format!("{n:032x}"), timeout: 1000, output: PathBuf::from(format!("/tmp/metric-{n}")), argv: vec!["/bin/true".into(), "λ".into()] }
    }
    fn bootstrap_bytes() -> Vec<u8> {
        let mut bytes = b"IPSEQ001".to_vec(); put_string(&mut bytes, "/tmp/sequence"); put_string(&mut bytes, "/tmp/cells.bin");
        bytes.extend_from_slice(&claim(&stage(1))[8..]); bytes.extend_from_slice(&claim(&stage(2))[8..]); bytes
    }
    #[test]
    fn descriptor_round_trip_preserves_argv_and_claim() {
        let decoded = bootstrap(&bootstrap_bytes()).unwrap();
        assert_eq!(decoded.output, Path::new("/tmp/sequence"));
        assert_eq!(decoded.preparation.argv, vec!["/bin/true", "λ"]);
        let bytes = claim(&decoded.finalization);
        let mut reader = Decoder { bytes: &bytes, offset: 8 };
        assert_eq!(reader.stage().unwrap().token, stage(2).token); reader.finish().unwrap();
    }
    #[test]
    fn every_truncation_and_trailing_bytes_are_refused() {
        let bytes = bootstrap_bytes();
        for size in 0..bytes.len() { assert!(bootstrap(&bytes[..size]).is_err(), "prefix {size}"); }
        let mut extra = bytes; extra.push(0); assert!(bootstrap(&extra).is_err());
    }
    #[test]
    fn malformed_strings_and_stage_bounds_are_refused() {
        for bytes in [vec![0, 1, 0, 1], vec![0, 0, 0, 1, 255], vec![0, 0, 0, 1, 0]] {
            assert!(Decoder { bytes: &bytes, offset: 0 }.string().is_err());
        }
        for value in ["relative", "/tmp/../metric", "/tmp/./metric", "/tmp//metric"] {
            let mut bytes = Vec::new(); put_string(&mut bytes, value);
            assert!(Decoder { bytes: &bytes, offset: 0 }.path().is_err());
        }
        for count in [0, 121, 122] {
            let mut sample = stage(1); sample.argv = vec!["/bin/true".into(); count];
            let bytes = claim(&sample);
            assert_eq!(Decoder { bytes: &bytes, offset: 8 }.stage().is_ok(), count == 121);
        }
        for timeout in [0, 86_400_001] {
            let mut invalid = stage(1); invalid.timeout = timeout;
            let bytes = claim(&invalid);
            assert!(Decoder { bytes: &bytes, offset: 8 }.stage().is_err());
        }
        let mut bad = stage(1); bad.token = "A".repeat(32); let bytes = claim(&bad);
        assert!(Decoder { bytes: &bytes, offset: 8 }.stage().is_err());
        let mut bad = stage(1); bad.argv[0] = "relative".into(); let bytes = claim(&bad);
        assert!(Decoder { bytes: &bytes, offset: 8 }.stage().is_err());
    }
    #[test]
    fn schedule_count_and_duplicate_identities_are_refused() {
        let mut bytes = b"IPSCELL1".to_vec(); bytes.extend_from_slice(&1_u32.to_be_bytes()); bytes.extend_from_slice(&claim(&stage(1))[8..]);
        assert_eq!(cells(&bytes).unwrap().len(), 1);
        for count in [0_u32, 65] { bytes[8..12].copy_from_slice(&count.to_be_bytes()); assert!(cells(&bytes).is_err()); }
        assert!(distinct(&[stage(1), stage(1)], Path::new("/tmp/sequence")).is_err());
        let mut alias = stage(2); alias.output = stage(1).output;
        assert!(distinct(&[stage(1), alias], Path::new("/tmp/sequence")).is_err());
        assert!(distinct(&[stage(1)], &stage(1).output).is_err());
    }
    #[test]
    fn writerless_fifo_is_rejected_without_waiting_for_a_writer() {
        use std::ffi::CString;
        use std::os::unix::ffi::OsStrExt;
        use std::time::{Duration, SystemTime, UNIX_EPOCH};
        extern "C" { fn mkfifo(path: *const i8, mode: u32) -> i32; }
        let nonce = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
        let root = std::env::temp_dir().join(format!("ipse-sequence-fifo-{}-{nonce}", std::process::id()));
        fs::DirBuilder::new().mode(0o700).create(&root).unwrap();
        let path = root.join("descriptor");
        let name = CString::new(path.as_os_str().as_bytes()).unwrap();
        assert_eq!(unsafe { mkfifo(name.as_ptr(), 0o600) }, 0);
        let (send, receive) = std::sync::mpsc::channel();
        std::thread::spawn(move || { let _ = send.send(descriptor(&path)); });
        let result = receive.recv_timeout(Duration::from_secs(1));
        fs::remove_file(root.join("descriptor")).unwrap();
        fs::remove_dir(root).unwrap();
        assert!(result.expect("FIFO admission waited for a writer").is_err());
    }
    #[test]
    fn typed_terminal_requires_exact_native_frame_and_receipt() {
        let receipt = b"opaque native JSON";
        let mut bytes = vec![b'M']; bytes.extend_from_slice(&(receipt.len() as u32).to_be_bytes()); bytes.extend_from_slice(receipt);
        assert!(protocol(&bytes, receipt).is_err());
        bytes.extend_from_slice(b"T\0\0\0\x02\0\x01");
        let status = protocol(&bytes, receipt).unwrap(); assert!(!status.complete && status.cleanup);
        assert!(protocol(&bytes, b"different").is_err());
        let mut extra = bytes.clone(); extra.push(0); assert!(protocol(&extra, receipt).is_err());
        let last = bytes.len() - 1; bytes[last] = 2; assert!(protocol(&bytes, receipt).is_err());
    }
}

}

pub fn run(args: &[String]) -> Result<(), String> {
    #[cfg(target_os = "linux")] { implementation::run(args) }
    #[cfg(not(target_os = "linux"))] { let _ = args; Err("measured sequencing requires Linux cgroup-v2 support".into()) }
}
