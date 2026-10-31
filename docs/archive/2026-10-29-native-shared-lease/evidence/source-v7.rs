//! Linux-only development experiment. No Ipse runtime path invokes this file.
//! It demonstrates kernel transfer of an already-held flock open description;
//! it does not authenticate paths, transfer production leases, or authorize display.
#[cfg(target_os = "linux")]
mod experiment {
    use std::env;
    use std::ffi::c_void;
    use std::fs::{DirBuilder, File, OpenOptions};
    use std::io::{self, Read, Write};
    use std::mem::{size_of, zeroed};
    use std::os::fd::{AsRawFd, FromRawFd, RawFd};
    use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt};
    use std::os::unix::net::UnixStream;
    use std::path::Path;
    use std::process::{Command, Stdio};
    use std::time::Duration;

    #[repr(C)]
    struct IoVec {
        base: *mut c_void,
        len: usize,
    }
    #[repr(C)]
    struct Message {
        name: *mut c_void,
        name_len: u32,
        iov: *mut IoVec,
        iov_len: usize,
        control: *mut c_void,
        control_len: usize,
        flags: i32,
    }
    #[repr(C)]
    struct ControlHeader {
        len: usize,
        level: i32,
        kind: i32,
    }
    #[repr(C, align(8))]
    struct DescriptorControl {
        header: ControlHeader,
        descriptor: i32,
        padding: i32,
    }

    unsafe extern "C" {
        fn flock(fd: i32, operation: i32) -> i32;
        fn sendmsg(fd: i32, message: *const Message, flags: i32) -> isize;
        fn recvmsg(fd: i32, message: *mut Message, flags: i32) -> isize;
        fn fcntl(fd: i32, command: i32, ...) -> i32;
        fn fork() -> i32;
        fn kill(pid: i32, signal: i32) -> i32;
        fn pause() -> i32;
        fn waitpid(pid: i32, status: *mut i32, options: i32) -> i32;
        fn _exit(status: i32) -> !;
    }
    const LOCK_EX_NB: i32 = 2 | 4;
    const SOL_SOCKET: i32 = 1;
    const SCM_RIGHTS: i32 = 1;
    const MSG_CMSG_CLOEXEC: i32 = 0x4000_0000;
    const MSG_CTRUNC: i32 = 0x08;
    const F_GETFD: i32 = 1;
    const FD_CLOEXEC: i32 = 1;

    fn lock(file: &File) -> io::Result<()> {
        if unsafe { flock(file.as_raw_fd(), LOCK_EX_NB) } == 0 {
            Ok(())
        } else {
            Err(io::Error::last_os_error())
        }
    }
    fn send_fd(socket: &UnixStream, file: &File) -> io::Result<()> {
        let mut byte = [b'L'];
        let mut iov = IoVec {
            base: byte.as_mut_ptr().cast(),
            len: 1,
        };
        let mut control = DescriptorControl {
            header: ControlHeader {
                len: size_of::<ControlHeader>() + size_of::<i32>(),
                level: SOL_SOCKET,
                kind: SCM_RIGHTS,
            },
            descriptor: file.as_raw_fd(),
            padding: 0,
        };
        let message = Message {
            name: std::ptr::null_mut(),
            name_len: 0,
            iov: &mut iov,
            iov_len: 1,
            control: (&mut control as *mut DescriptorControl).cast(),
            control_len: size_of::<DescriptorControl>(),
            flags: 0,
        };
        if unsafe { sendmsg(socket.as_raw_fd(), &message, 0) } == 1 {
            Ok(())
        } else {
            Err(io::Error::last_os_error())
        }
    }
    fn receive_fd(socket: &UnixStream) -> io::Result<File> {
        let mut byte = [0u8];
        let mut iov = IoVec {
            base: byte.as_mut_ptr().cast(),
            len: 1,
        };
        let mut control: DescriptorControl = unsafe { zeroed() };
        let mut message = Message {
            name: std::ptr::null_mut(),
            name_len: 0,
            iov: &mut iov,
            iov_len: 1,
            control: (&mut control as *mut DescriptorControl).cast(),
            control_len: size_of::<DescriptorControl>(),
            flags: 0,
        };
        let count = unsafe { recvmsg(socket.as_raw_fd(), &mut message, MSG_CMSG_CLOEXEC) };
        if message.control_len < size_of::<ControlHeader>() + size_of::<i32>()
            || control.header.len != size_of::<ControlHeader>() + size_of::<i32>()
            || control.header.level != SOL_SOCKET
            || control.header.kind != SCM_RIGHTS
            || control.descriptor < 0
        {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "invalid descriptor transfer",
            ));
        }
        let file = unsafe { File::from_raw_fd(control.descriptor as RawFd) };
        if count != 1 || byte[0] != b'L' || message.flags & MSG_CTRUNC != 0 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "invalid descriptor transfer",
            ));
        }
        let flags = unsafe { fcntl(file.as_raw_fd(), F_GETFD) };
        if flags < 0 || flags & FD_CLOEXEC == 0 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "descriptor is not close-on-exec",
            ));
        }
        Ok(file)
    }
    fn byte(socket: &mut UnixStream, expected: u8) -> io::Result<()> {
        let mut value = [0];
        socket.read_exact(&mut value)?;
        if value[0] == expected {
            Ok(())
        } else {
            Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "unexpected control byte",
            ))
        }
    }
    fn child_status(pid: i32) -> io::Result<()> {
        let mut status = 0;
        if unsafe { waitpid(pid, &mut status, 0) } == pid && status == 0 {
            Ok(())
        } else {
            Err(io::Error::other("child failed"))
        }
    }
    struct Children(Vec<i32>);
    impl Drop for Children {
        fn drop(&mut self) {
            for pid in self.0.drain(..) {
                unsafe {
                    kill(pid, 9);
                    waitpid(pid, &mut 0, 0);
                }
            }
        }
    }
    fn receiver(
        socket: UnixStream,
        mut control: UnixStream,
        expected: (u64, u64),
    ) -> io::Result<()> {
        let lease = receive_fd(&socket)?;
        let meta = lease.metadata()?;
        if (meta.dev(), meta.ino()) != expected {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "wrong lock identity",
            ));
        }
        control.write_all(b"R")?;
        byte(&mut control, b'X')?;
        drop(lease);
        control.write_all(b"D")?;
        Ok(())
    }
    fn helper_lock(helper: &Path, path: &Path) -> io::Result<std::process::Output> {
        Command::new(helper)
            .arg("--lock")
            .arg(path)
            .stdin(Stdio::null())
            .output()
    }
    fn run_case(
        root: &Path,
        helper: &Path,
        wrong_identity: bool,
        kill_recipient: bool,
    ) -> io::Result<()> {
        let (mut invalid_sender, invalid_receiver) = UnixStream::pair()?;
        invalid_sender.write_all(b"X")?;
        if receive_fd(&invalid_receiver).is_ok() {
            return Err(io::Error::other("missing descriptor accepted"));
        }
        let path = root.join("held.lock");
        let lease = OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&path)?;
        lock(&lease)?;
        let meta = lease.metadata()?;
        let expected = (
            meta.dev(),
            if wrong_identity {
                meta.ino() ^ 1
            } else {
                meta.ino()
            },
        );
        let (send_socket, receive_socket) = UnixStream::pair()?;
        let (mut parent_control, child_control) = UnixStream::pair()?;
        parent_control.set_read_timeout(Some(Duration::from_secs(5)))?;
        child_control.set_read_timeout(Some(Duration::from_secs(5)))?;

        let recipient = unsafe { fork() };
        if recipient < 0 {
            return Err(io::Error::last_os_error());
        }
        if recipient == 0 {
            drop(lease);
            drop(send_socket);
            drop(parent_control);
            let result = receiver(receive_socket, child_control, expected);
            unsafe { _exit(if result.is_ok() { 0 } else { 1 }) }
        }
        let mut children = Children(vec![recipient]);
        let sender = unsafe { fork() };
        if sender < 0 {
            return Err(io::Error::last_os_error());
        }
        if sender == 0 {
            drop(receive_socket);
            drop(parent_control);
            drop(child_control);
            let result = send_fd(&send_socket, &lease);
            if result.is_err() {
                unsafe { _exit(1) }
            }
            loop {
                unsafe {
                    pause();
                }
            }
        }
        children.0.push(sender);
        drop(lease);
        drop(send_socket);
        drop(receive_socket);
        drop(child_control);
        byte(&mut parent_control, b'R')?;
        if unsafe { kill(sender, 9) } != 0 {
            return Err(io::Error::last_os_error());
        }
        let mut sender_status = 0;
        let waited_sender = unsafe { waitpid(sender, &mut sender_status, 0) };
        if waited_sender == sender {
            children.0.retain(|pid| *pid != sender);
        }
        if waited_sender != sender || sender_status & 0x7f != 9 {
            return Err(io::Error::other("original holder did not die by SIGKILL"));
        }
        let contender = OpenOptions::new().read(true).write(true).open(&path)?;
        let blocked = lock(&contender).is_err_and(|e| e.kind() == io::ErrorKind::WouldBlock);
        if !blocked {
            return Err(io::Error::other(
                "transferred lease did not retain exclusion",
            ));
        }
        let busy_helper = helper_lock(helper, &path)?;
        if busy_helper.status.success()
            || busy_helper.stdout.first() != Some(&b'E')
            || !String::from_utf8_lossy(&busy_helper.stdout).contains("cannot acquire session lock")
        {
            return Err(io::Error::other(
                "real lock helper did not refuse the held lease",
            ));
        }
        let recipient_result = if kill_recipient {
            if unsafe { kill(recipient, 9) } != 0 {
                return Err(io::Error::last_os_error());
            }
            let mut status = 0;
            if unsafe { waitpid(recipient, &mut status, 0) } == recipient && status & 0x7f == 9 {
                Ok(())
            } else {
                Err(io::Error::other("recipient did not die by SIGKILL"))
            }
        } else {
            parent_control.write_all(b"X")?;
            byte(&mut parent_control, b'D')?;
            child_status(recipient)
        };
        children.0.retain(|pid| *pid != recipient);
        recipient_result?;
        lock(&contender)?;
        drop(contender);
        let free_helper = helper_lock(helper, &path)?;
        if !free_helper.status.success() || free_helper.stdout.first() != Some(&b'L') {
            return Err(io::Error::other(
                "real lock helper did not acquire after final release",
            ));
        }
        println!("SCM_RIGHTS_SHARED_FLOCK_PASSED sender_sigkill=1 receiver_sigkill={} receiver_held=1 contender_blocked=1 real_helper_blocked=1 real_helper_acquired=1 final_release=1 cloexec=1 missing_fd_rejected=1", u8::from(kill_recipient));
        Ok(())
    }
    fn run(root: &Path, helper: &Path) -> io::Result<()> {
        for name in ["wrong-identity", "graceful-release", "recipient-kill"] {
            DirBuilder::new().mode(0o700).create(root.join(name))?;
        }
        let bad_root = root.join("wrong-identity");
        if run_case(&bad_root, helper, true, false).is_ok() {
            return Err(io::Error::other("wrong descriptor identity accepted"));
        }
        let contender = OpenOptions::new()
            .read(true)
            .write(true)
            .open(bad_root.join("held.lock"))?;
        lock(&contender)?;
        drop(contender);
        println!("SCM_RIGHTS_WRONG_IDENTITY_REFUSED cleanup_released_lock=1");
        let hazard = root.join("shared-unlock.lock");
        let original = OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&hazard)?;
        lock(&original)?;
        let duplicate = original.try_clone()?;
        if unsafe { flock(duplicate.as_raw_fd(), 8) } != 0 {
            return Err(io::Error::last_os_error());
        }
        let probe = OpenOptions::new().read(true).write(true).open(&hazard)?;
        lock(&probe)?;
        println!("SHARED_FLOCK_UNLOCK_HAZARD_CONFIRMED explicit_unlock_releases_all_duplicates=1");
        drop(probe);
        drop(duplicate);
        drop(original);
        run_case(&root.join("graceful-release"), helper, false, false)?;
        run_case(&root.join("recipient-kill"), helper, false, true)
    }
    pub fn main() -> Result<(), String> {
        let args: Vec<_> = env::args_os().collect();
        if args.len() != 3 {
            return Err("usage: shared-lease-experiment PRIVATE_TEST_DIRECTORY IPSE_RUNNER".into());
        }
        run(Path::new(&args[1]), Path::new(&args[2])).map_err(|e| e.to_string())
    }
}
#[cfg(target_os = "linux")]
fn main() {
    if let Err(error) = experiment::main() {
        eprintln!("shared lease experiment failed: {error}");
        std::process::exit(1);
    }
}
#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("shared lease experiment is Linux-only");
    std::process::exit(1);
}
