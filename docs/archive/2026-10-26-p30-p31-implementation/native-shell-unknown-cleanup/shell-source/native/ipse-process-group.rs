use std::env;
use std::io::{self, Read};
use std::os::unix::io::AsRawFd;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};

extern "C" {
    fn setpgid(pid: i32, pgid: i32) -> i32;
    fn kill(pid: i32, signal: i32) -> i32;
    fn close(fd: i32) -> i32;
    fn signal(number: i32, handler: usize) -> usize;
}

pub type GroupSlot = Arc<Mutex<Option<i32>>>;

pub fn signal_group(slot: &GroupSlot) -> bool {
    let group = slot.lock().unwrap();
    group.is_some_and(|pid| unsafe { kill(-pid, 9) == 0 })
}

pub struct GroupGuard {
    // Keep this PID unreaped until every signaling path has lost its slot.
    anchor: Child,
    slot: GroupSlot,
}

impl GroupGuard {
    pub fn start(slot: GroupSlot) -> io::Result<Self> {
        Self::start_at(&env::current_exe()?, slot)
    }

    fn start_at(executable: &Path, slot: GroupSlot) -> io::Result<Self> {
        #[cfg(target_os = "linux")]
        const CHILD_SIGNAL: i32 = 17;
        #[cfg(target_os = "macos")]
        const CHILD_SIGNAL: i32 = 20;
        // An inherited ignored SIGCHLD must not automatically reap the group anchor.
        if unsafe { signal(CHILD_SIGNAL, 0) } == usize::MAX {
            return Err(io::Error::last_os_error());
        }
        let mut entry = slot.lock().unwrap();
        if entry.is_some() {
            return Err(io::Error::new(
                io::ErrorKind::AlreadyExists,
                "group already owned",
            ));
        }
        let mut command = Command::new(executable);
        command
            .arg("--group-anchor")
            .env_clear()
            .env("LANG", "C")
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        unsafe {
            command.pre_exec(|| {
                if setpgid(0, 0) == -1 {
                    return Err(io::Error::last_os_error());
                }
                Ok(())
            });
        }
        let anchor = command.spawn()?;
        *entry = Some(anchor.id() as i32);
        drop(entry);
        Ok(Self { anchor, slot })
    }

    pub fn attach(&self, command: &mut Command) {
        let pgid = self.anchor.id() as i32;
        let lease = self.anchor.stdin.as_ref().unwrap().as_raw_fd();
        unsafe {
            command.pre_exec(move || {
                // Join before releasing the inherited lease, including pre-exec failure paths.
                if setpgid(0, pgid) == -1 {
                    return Err(io::Error::last_os_error());
                }
                if close(lease) == -1 {
                    return Err(io::Error::last_os_error());
                }
                Ok(())
            });
        }
    }
}

impl Drop for GroupGuard {
    fn drop(&mut self) {
        let mut entry = self.slot.lock().unwrap();
        let pid = self.anchor.id() as i32;
        unsafe {
            kill(-pid, 9);
        }
        *entry = None;
        // Signalers hold this mutex through kill; none can retain a stale PID past reap.
        let _ = self.anchor.wait();
    }
}

pub fn run_anchor() -> io::Result<()> {
    if unsafe { setpgid(0, 0) } == -1 {
        return Err(io::Error::last_os_error());
    }
    let mut input = io::stdin();
    let mut byte = [0];
    loop {
        match input.read(&mut byte) {
            Ok(0) => break,
            Ok(_) => (),
            Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
            Err(_) => break,
        }
    }
    unsafe {
        kill(-(std::process::id() as i32), 9);
    }
    Ok(())
}
