use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

extern "C" {
    fn prctl(option: i32, arg2: usize, arg3: usize, arg4: usize, arg5: usize) -> i32;
    fn waitpid(pid: i32, status: *mut i32, flags: i32) -> i32;
    fn signal(number: i32, handler: usize) -> usize;
}

struct Owned { native: Child, output: PathBuf, adopted: Option<i32> }
impl Owned {
    fn finish(&mut self) -> Result<(), String> {
        let _ = fs::write(self.output.join("release"), b"release\n");
        drop(self.native.stdin.take());
        let deadline = Instant::now() + Duration::from_secs(4);
        loop {
            if let Some(status) = self.native.try_wait().map_err(|e| e.to_string())? {
                if !status.success() { return Err("diagnostic helper failed".into()); }
                break;
            }
            if Instant::now() >= deadline { return Err("diagnostic helper exit unconfirmed".into()); }
            std::thread::sleep(Duration::from_millis(2));
        }
        if let Some(pid) = self.adopted.take() {
            let deadline = Instant::now() + Duration::from_secs(2);
            loop {
                let mut status = 0;
                let result = unsafe { waitpid(pid, &mut status, 1) };
                if result == pid { break; }
                if result < 0 { return Err("owned diagnostic child adoption unconfirmed".into()); }
                if Instant::now() >= deadline { return Err("owned diagnostic child reap unconfirmed".into()); }
                std::thread::sleep(Duration::from_millis(2));
            }
        }
        Ok(())
    }
}
impl Drop for Owned {
    fn drop(&mut self) {
        let _ = fs::write(self.output.join("release"), b"release\n");
        drop(self.native.stdin.take());
        let deadline = Instant::now() + Duration::from_secs(2);
        while matches!(self.native.try_wait(), Ok(None)) && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(2));
        }
        if matches!(self.native.try_wait(), Ok(None)) { let _ = self.native.kill(); }
        let deadline = Instant::now() + Duration::from_secs(2);
        let mut exited = false;
        while Instant::now() < deadline {
            if self.native.try_wait().ok().flatten().is_some() { exited = true; break; }
            std::thread::sleep(Duration::from_millis(2));
        }
        if exited {
            if let Some(pid) = self.adopted.take() {
                let deadline = Instant::now() + Duration::from_secs(2);
                while Instant::now() < deadline {
                    let mut status = 0;
                    if unsafe { waitpid(pid, &mut status, 1) } != 0 { break; }
                    std::thread::sleep(Duration::from_millis(2));
                }
            }
        }
    }
}
fn string(bytes: &mut Vec<u8>, value: &str) {
    bytes.extend_from_slice(&(value.len() as u32).to_be_bytes()); bytes.extend_from_slice(value.as_bytes());
}
fn main() {
    let args = std::env::args().collect::<Vec<_>>(); assert_eq!(args.len(), 5);
    let output = PathBuf::from(&args[3]);
    fs::create_dir(&output).unwrap();
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(&output, fs::Permissions::from_mode(0o700)).unwrap();
    assert_ne!(unsafe { signal(17, 0) }, usize::MAX, "diagnostic child reaping unavailable");
    assert_eq!(unsafe { prctl(36, 1, 0, 0, 0) }, 0, "owned diagnostic subreaper unavailable");
    let barrier = output.join("never-release-inspection");
    let native = Command::new(&args[1])
        .args(["--stdio-listener", args[3].as_str(), "3000", "21434", "--", &args[2], "forge"])
        .env_clear().env("PATH", "/usr/bin:/bin").env("LANG", "C.UTF-8")
        .env("IPSE_LISTENER_PROBE_BARRIER", &barrier).env("IPSE_LISTENER_PROBE_OUTPUT", &output)
        .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().unwrap();
    let mut owned = Owned { native, output: output.clone(), adopted: None };
    drop(owned.native.stdout.take());
    let mut environment = 2_u32.to_be_bytes().to_vec();
    for (key, value) in [("PATH", "/usr/bin:/bin"), ("LANG", "C.UTF-8")] {
        string(&mut environment, key); string(&mut environment, value);
    }
    let mut launch = vec![b'L']; launch.extend_from_slice(&(environment.len() as u32).to_be_bytes()); launch.extend(environment);
    owned.native.stdin.as_mut().unwrap().write_all(&launch).unwrap();
    let deadline = Instant::now() + Duration::from_secs(2);
    let pid = loop {
        if let Ok(bytes) = fs::read_to_string(output.join("child-pid")) { break bytes.parse::<i32>().unwrap(); }
        assert!(Instant::now() < deadline, "output-failure observation absent");
        assert!(owned.native.try_wait().unwrap().is_none(), "helper ended before observation");
        std::thread::sleep(Duration::from_millis(1));
    };
    assert!(pid > 0);
    assert_eq!(fs::read_to_string(output.join("pending")).unwrap(), "true");
    let deadline = Instant::now() + Duration::from_secs(1);
    let retained = loop {
        match fs::read_to_string(format!("/proc/{pid}/status")) {
            Ok(text) if text.lines().any(|line| line.starts_with("State:\tZ")) => break true,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => break false,
            Ok(_) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(1)),
            other => panic!("owned child did not reach killed/retained state: {other:?}"),
        }
    };
    if retained { owned.adopted = Some(pid); }
    let expected = match args[4].as_str() { "retained" => true, "reaped" => false, _ => panic!("expected retained or reaped") };
    owned.finish().unwrap();
    assert_eq!(retained, expected, "pending inspection child-reaping invariant violated");
    let report = format!("{{\"pending_inspection\":true,\"output_delivery_failed\":true,\"child_retained_unreaped\":{retained},\"helper_exited\":true,\"diagnostic_cleanup_confirmed\":true}}\n");
    fs::write(output.join("result.json"), &report).unwrap(); print!("{report}");
}
