//! Linux/x86_64 diagnostic: stop the real helper after its wall check, before renameat.
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod probe {
    use std::ffi::c_void;
    use std::fs::{self, DirBuilder, OpenOptions};
    use std::io::{self, Read, Write};
    use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
    use std::os::unix::process::CommandExt;
    use std::path::Path;
    use std::process::{Command, Stdio};
    use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

    unsafe extern "C" {
        fn ptrace(request: u32, pid: i32, address: *mut c_void, data: *mut c_void) -> i64;
        fn waitpid(pid: i32, status: *mut i32, options: i32) -> i32;
    }
    fn now() -> u64 {
        SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64
    }
    fn trace(request: u32, pid: i32, data: *mut c_void) -> io::Result<()> {
        if unsafe { ptrace(request, pid, std::ptr::null_mut(), data) } < 0 {
            Err(io::Error::last_os_error())
        } else {
            Ok(())
        }
    }
    fn frame(kind: u8, seq: u64, depth: u8, bytes: &[u8]) -> Vec<u8> {
        let mut result = vec![kind];
        result.extend_from_slice(&((9 + bytes.len()) as u32).to_be_bytes());
        result.extend_from_slice(&seq.to_be_bytes());
        result.push(depth);
        result.extend_from_slice(bytes);
        result
    }
    fn target(pid: i32, address: u64) -> io::Result<String> {
        let mut result = Vec::new();
        for offset in (0..64).step_by(8) {
            let word = unsafe {
                ptrace(2, pid, (address + offset) as *mut c_void, std::ptr::null_mut())
            };
            if word == -1 {
                return Err(io::Error::last_os_error());
            }
            for byte in word.to_ne_bytes() {
                if byte == 0 {
                    return String::from_utf8(result).map_err(io::Error::other);
                }
                result.push(byte);
            }
        }
        Err(io::Error::other("unterminated rename target"))
    }
    fn private_file(path: &Path, bytes: &[u8]) -> io::Result<()> {
        let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(path)?;
        file.write_all(bytes)?;
        file.sync_all()
    }
    pub fn run() -> io::Result<()> {
        let args: Vec<_> = std::env::args().collect();
        if args.len() != 3 {
            return Err(io::Error::other("usage: probe PINNED_HELPER NEW_PRIVATE_DIRECTORY"));
        }
        let root = Path::new(&args[2]);
        DirBuilder::new().mode(0o700).create(root)?;
        let stage = ".pending-0123456789abcdef0123456789abcdef";
        private_file(&root.join(stage), b"after")?;
        private_file(&root.join("root.json"), b"before")?;
        let mut command = Command::new(&args[1]);
        command.args(["--transaction-lock", "15000"]).stdin(Stdio::piped())
            .stdout(Stdio::piped()).stderr(Stdio::piped());
        unsafe {
            command.pre_exec(|| trace(0, 0, std::ptr::null_mut()));
        }
        let mut child = command.spawn()?;
        let pid = child.id() as i32;
        let result = (|| {
            let mut status = 0;
            if unsafe { waitpid(pid, &mut status, 0) } != pid || status & 0xff != 0x7f {
                return Err(io::Error::other("missing initial traced exec stop"));
            }
            trace(0x4200, pid, 1_usize as *mut c_void)?;
            let deadline = now() + 1500;
            let mut body = deadline.to_be_bytes().to_vec();
            body.extend_from_slice(stage.as_bytes());
            body.extend_from_slice(b"root.json");
            let mut input = child.stdin.take().unwrap();
            input.write_all(&frame(b'A', 1, 0, root.join(".lock").to_str().unwrap().as_bytes()))?;
            input.write_all(&frame(b'T', 2, 1, &body))?;
            input.write_all(&frame(b'R', 3, 1, &[]))?;
            input.flush()?;
            let mut interposed = None;
            let limit = Instant::now() + Duration::from_secs(8);
            loop {
                if Instant::now() > limit {
                    return Err(io::Error::other("traced helper exceeded diagnostic bound"));
                }
                trace(24, pid, std::ptr::null_mut())?;
                if unsafe { waitpid(pid, &mut status, 0) } != pid {
                    return Err(io::Error::last_os_error());
                }
                if status & 0x7f == 0 {
                    if status >> 8 != 0 {
                        return Err(io::Error::other("helper exited unsuccessfully"));
                    }
                    break;
                }
                if status & 0xff != 0x7f {
                    return Err(io::Error::other("helper terminated while tracing"));
                }
                if status >> 8 == 133 {
                    let mut registers = [0_u64; 27];
                    trace(12, pid, registers.as_mut_ptr().cast())?;
                    // Linux x86_64: orig_rax=renameat, rax=-ENOSYS at syscall entry;
                    // r10 is the fourth argument, the destination basename.
                    if registers[15] == 264 && registers[10] == (-38_i64) as u64
                        && target(pid, registers[7])? == "root.json" {
                        if interposed.is_some() || now() >= deadline {
                            return Err(io::Error::other("rename not reached before deadline"));
                        }
                        let entered = now();
                        assert_eq!(fs::read(root.join("root.json"))?, b"before");
                        std::thread::sleep(Duration::from_millis(deadline - entered + 50));
                        let resumed = now();
                        assert!(entered < deadline && resumed > deadline);
                        interposed = Some((entered, resumed));
                    }
                }
            }
            drop(input);
            let mut output = Vec::new();
            child.stdout.take().unwrap().read_to_end(&mut output)?;
            let expected = [frame(b'A', 1, 1, &[]), frame(b'T', 2, 1, &[]), frame(b'R', 3, 0, &[])].concat();
            if output != expected || fs::read(root.join("root.json"))? != b"after" {
                return Err(io::Error::other("late rename or successful helper reply not observed"));
            }
            let (entered, resumed) = interposed.ok_or_else(|| io::Error::other("rename never interposed"))?;
            println!("LATE_NATIVE_SWITCH_PROVED entered_ms={entered} deadline_ms={deadline} resumed_ms={resumed} successful_reply=T root=after");
            Ok(())
        })();
        let _ = child.kill();
        let _ = child.wait();
        result
    }
}
fn main() {
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    if let Err(error) = probe::run() {
        eprintln!("deadline interposition refused: {error}");
        std::process::exit(1);
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    panic!("diagnostic requires Linux x86_64");
}
