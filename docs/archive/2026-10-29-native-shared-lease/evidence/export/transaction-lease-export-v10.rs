//! Focused Linux protocol fixture for the private transaction helper export.
#[cfg(target_os = "linux")]
mod test {
    use std::env;
    use std::ffi::c_void;
    use std::fs::{DirBuilder, File, OpenOptions};
    use std::io::{self, Read, Write};
    use std::mem::{size_of, zeroed};
    use std::os::fd::{AsRawFd, FromRawFd};
    use std::os::linux::net::SocketAddrExt;
    use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt};
    use std::os::unix::net::{SocketAddr, UnixListener, UnixStream};
    use std::path::Path;
    use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
    use std::sync::mpsc;
    use std::thread;
    use std::time::{Duration, Instant};

    #[repr(C)]
    struct Poll {
        fd: i32,
        events: i16,
        revents: i16,
    }
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
    struct Header {
        len: usize,
        level: i32,
        kind: i32,
    }
    #[repr(C)]
    struct Peer {
        pid: i32,
        uid: u32,
        gid: u32,
    }
    #[repr(C, align(8))]
    struct Control([u8; 4096]);
    unsafe extern "C" {
        fn poll(fds: *mut Poll, count: usize, timeout: i32) -> i32;
        fn recvmsg(fd: i32, message: *mut Message, flags: i32) -> isize;
        fn sendmsg(fd: i32, message: *const Message, flags: i32) -> isize;
        fn fcntl(fd: i32, cmd: i32, ...) -> i32;
        fn getsockopt(fd: i32, level: i32, name: i32, value: *mut c_void, length: *mut u32) -> i32;
        fn flock(fd: i32, operation: i32) -> i32;
    }
    struct OwnedChild(Child);
    impl Drop for OwnedChild {
        fn drop(&mut self) {
            let _ = self.0.kill();
            let _ = self.0.wait();
        }
    }
    fn write_frame(
        out: &mut ChildStdin,
        tag: u8,
        seq: u64,
        depth: u8,
        extra: &[u8],
    ) -> io::Result<()> {
        let mut body = seq.to_be_bytes().to_vec();
        body.push(depth);
        body.extend_from_slice(extra);
        out.write_all(&[tag])?;
        out.write_all(&(body.len() as u32).to_be_bytes())?;
        out.write_all(&body)?;
        out.flush()
    }
    fn read_until<R: Read + AsRawFd>(
        input: &mut R,
        out: &mut [u8],
        deadline: Instant,
    ) -> io::Result<()> {
        let mut offset = 0;
        while offset < out.len() {
            let left = deadline.saturating_duration_since(Instant::now());
            if left.is_zero() {
                return Err(io::Error::new(
                    io::ErrorKind::TimedOut,
                    "helper reply timed out",
                ));
            }
            let mut p = Poll {
                fd: input.as_raw_fd(),
                events: 1,
                revents: 0,
            };
            let timeout = left.as_millis().max(1).min(i32::MAX as u128) as i32;
            let ready = unsafe { poll(&mut p, 1, timeout) };
            if ready < 0 {
                let error = io::Error::last_os_error();
                if error.kind() == io::ErrorKind::Interrupted {
                    continue;
                }
                return Err(error);
            }
            if ready == 0 {
                continue;
            }
            match input.read(&mut out[offset..]) {
                Ok(0) => {
                    return Err(io::Error::new(
                        io::ErrorKind::UnexpectedEof,
                        "helper closed frame",
                    ))
                }
                Ok(count) => offset += count,
                Err(error)
                    if matches!(
                        error.kind(),
                        io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock
                    ) => {}
                Err(error) => return Err(error),
            }
        }
        Ok(())
    }
    fn read_frame_for<R: Read + AsRawFd>(
        input: &mut R,
        timeout: Duration,
    ) -> io::Result<(u8, Vec<u8>)> {
        let flags = unsafe { fcntl(input.as_raw_fd(), 3) };
        if flags < 0 || unsafe { fcntl(input.as_raw_fd(), 4, flags | 0x800) } < 0 {
            return Err(io::Error::last_os_error());
        }
        let deadline = Instant::now() + timeout;
        let mut header = [0u8; 5];
        read_until(input, &mut header, deadline)?;
        let len = u32::from_be_bytes(header[1..].try_into().unwrap()) as usize;
        if len > 1024 {
            return Err(io::Error::other("oversized helper reply"));
        }
        let mut body = vec![0; len];
        read_until(input, &mut body, deadline)?;
        Ok((header[0], body))
    }
    fn read_frame(input: &mut ChildStdout) -> io::Result<(u8, Vec<u8>)> {
        read_frame_for(input, Duration::from_secs(8))
    }
    fn open_helper(
        helper: &Path,
        directory: &Path,
        source: bool,
        race: bool,
    ) -> io::Result<(OwnedChild, ChildStdin, ChildStdout, std::path::PathBuf)> {
        DirBuilder::new().mode(0o700).create(directory)?;
        let lock = if source {
            directory.join(format!("{}.lock", "a".repeat(32)))
        } else {
            directory.join(".lock")
        };
        let mut command = Command::new(helper);
        if race {
            command.env("IPSE_TEST_EXPORT_RACE", directory.join("race"));
        }
        if source {
            command.arg("--lock-export-v1").arg(&lock);
        } else {
            command.arg("--transaction-lock").arg("30000");
        }
        let mut child = OwnedChild(
            command
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()?,
        );
        let mut stdin = child
            .0
            .stdin
            .take()
            .ok_or_else(|| io::Error::other("missing stdin"))?;
        let mut stdout = child
            .0
            .stdout
            .take()
            .ok_or_else(|| io::Error::other("missing stdout"))?;
        if source {
            let (kind, payload) = read_frame(&mut stdout)?;
            if kind != b'L' || payload != b"locked" {
                return Err(io::Error::other("source lock acquisition failed"));
            }
        } else {
            write_frame(&mut stdin, b'A', 1, 0, lock.to_str().unwrap().as_bytes())?;
            let (kind, payload) = read_frame(&mut stdout)?;
            if kind != b'A' || payload.len() != 9 || payload[8] != 1 {
                return Err(io::Error::other("lock acquisition failed"));
            }
        }
        Ok((child, stdin, stdout, lock))
    }
    fn receive_fd(socket: &UnixStream, dev: u64, ino: u64, uid: u32) -> io::Result<File> {
        receive_fd_bounded(socket, dev, ino, uid, 4096)
    }
    fn receive_fd_bounded(
        socket: &UnixStream,
        dev: u64,
        ino: u64,
        uid: u32,
        capacity: usize,
    ) -> io::Result<File> {
        let mut byte = [0u8];
        let mut iov = IoVec {
            base: byte.as_mut_ptr().cast(),
            len: 1,
        };
        let mut control = Control([0; 4096]);
        let mut message = Message {
            name: std::ptr::null_mut(),
            name_len: 0,
            iov: &mut iov,
            iov_len: 1,
            control: control.0.as_mut_ptr().cast(),
            control_len: capacity,
            flags: 0,
        };
        let n = unsafe { recvmsg(socket.as_raw_fd(), &mut message, 0x4000_0000) };
        // Own every delivered descriptor before interpreting the frame. Linux
        // closes descriptors omitted by MSG_CTRUNC; these are the ones it did
        // deliver, including entries in an otherwise invalid message.
        let mut files = Vec::new();
        let mut offset = 0usize;
        let mut valid = true;
        while offset + size_of::<Header>() <= message.control_len {
            let header = unsafe { &*(control.0.as_ptr().add(offset).cast::<Header>()) };
            if header.len < size_of::<Header>() || header.len > message.control_len - offset {
                valid = false;
                break;
            }
            let data = header.len - size_of::<Header>();
            if header.level == 1 && header.kind == 1 && data % size_of::<i32>() == 0 {
                for index in 0..data / size_of::<i32>() {
                    let ptr = unsafe {
                        control
                            .0
                            .as_ptr()
                            .add(offset + size_of::<Header>() + index * size_of::<i32>())
                    };
                    let fd = unsafe { std::ptr::read_unaligned(ptr.cast::<i32>()) };
                    if fd >= 0 {
                        files.push(unsafe { File::from_raw_fd(fd) });
                    } else {
                        valid = false;
                    }
                }
            } else {
                valid = false;
            }
            offset += (header.len + size_of::<usize>() - 1) & !(size_of::<usize>() - 1);
        }
        if n != 1 || byte != [b'L'] || message.flags & 8 != 0 || !valid || files.len() != 1 {
            return Err(io::Error::other("descriptor not delivered"));
        }
        let file = files.pop().unwrap();
        let meta = file.metadata()?;
        let fd_flags = unsafe { fcntl(file.as_raw_fd(), 1) };
        if fd_flags < 0
            || fd_flags & 1 == 0
            || meta.dev() != dev
            || meta.ino() != ino
            || !meta.is_file()
            || meta.uid() != uid
            || meta.nlink() != 1
            || meta.mode() & 0o7777 != 0o600
            || meta.len() != 0
        {
            return Err(io::Error::other("unexpected descriptor identity"));
        }
        Ok(file)
    }
    fn connect(
        name: [u8; 16],
        secret: [u8; 32],
        expected_pid: u32,
        expected_uid: u32,
    ) -> io::Result<UnixStream> {
        let mut abstract_name = b"ipse-lease-v1-".to_vec();
        abstract_name.extend_from_slice(&name);
        let address = SocketAddr::from_abstract_name(abstract_name)?;
        let end = Instant::now() + Duration::from_secs(5);
        let mut socket = loop {
            match UnixStream::connect_addr(&address) {
                Ok(socket) => break socket,
                Err(_) if Instant::now() < end => thread::sleep(Duration::from_millis(10)),
                Err(e) => return Err(e),
            }
        };
        socket.set_read_timeout(Some(Duration::from_secs(5)))?;
        let mut credentials: Peer = unsafe { zeroed() };
        let mut length = size_of::<Peer>() as u32;
        if unsafe {
            getsockopt(
                socket.as_raw_fd(),
                1,
                17,
                (&mut credentials as *mut Peer).cast(),
                &mut length,
            )
        } != 0
            || length as usize != size_of::<Peer>()
            || credentials.pid <= 0
            || credentials.pid as u32 != expected_pid
            || credentials.uid != expected_uid
        {
            return Err(io::Error::other("unexpected helper peer"));
        }
        socket.write_all(&secret)?;
        Ok(socket)
    }
    fn peer(
        name: [u8; 16],
        secret: [u8; 32],
        acknowledge: bool,
        helper_pid: u32,
        uid: u32,
        dev: u64,
        ino: u64,
    ) -> io::Result<(File, Option<UnixStream>)> {
        let mut socket = connect(name, secret, helper_pid, uid)?;
        let fd = receive_fd(&socket, dev, ino, uid)?;
        if acknowledge {
            socket.write_all(b"A")?;
            Ok((fd, Some(socket)))
        } else {
            drop(socket);
            Ok((fd, None))
        }
    }
    fn request(pid: u32, name: [u8; 16], secret: [u8; 32], dev: u64, ino: u64) -> Vec<u8> {
        let mut bytes = vec![0];
        bytes.extend_from_slice(&pid.to_be_bytes());
        bytes.extend_from_slice(&name);
        bytes.extend_from_slice(&secret);
        bytes.extend_from_slice(&dev.to_be_bytes());
        bytes.extend_from_slice(&ino.to_be_bytes());
        bytes
    }
    fn receiver_controls(root: &Path) -> io::Result<()> {
        let path = root.join("receiver-lock");
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(path)?;
        let meta = file.metadata()?;
        for (label, count, byte, capacity, inode) in [
            ("bad_frame", 1, b'?', 4096, meta.ino()),
            ("multiple", 2, b'L', 4096, meta.ino()),
            ("truncated", 16, b'L', 24, meta.ino()),
            ("wrong_inode", 1, b'L', 4096, meta.ino() ^ 1),
        ] {
            let (sender, receiver) = UnixStream::pair()?;
            let mut control = Control([0; 4096]);
            let header = control.0.as_mut_ptr().cast::<Header>();
            unsafe {
                std::ptr::write(
                    header,
                    Header {
                        len: size_of::<Header>() + count * size_of::<i32>(),
                        level: 1,
                        kind: 1,
                    },
                );
            }
            for i in 0..count {
                let ptr = unsafe {
                    control
                        .0
                        .as_mut_ptr()
                        .add(size_of::<Header>() + i * size_of::<i32>())
                };
                unsafe {
                    std::ptr::write_unaligned(ptr.cast::<i32>(), file.as_raw_fd());
                }
            }
            let mut data = [byte];
            let mut iov = IoVec {
                base: data.as_mut_ptr().cast(),
                len: 1,
            };
            let message = Message {
                name: std::ptr::null_mut(),
                name_len: 0,
                iov: &mut iov,
                iov_len: 1,
                control: control.0.as_mut_ptr().cast(),
                control_len: (size_of::<Header>() + count * size_of::<i32>() + 7) & !7,
                flags: 0,
            };
            let before = std::fs::read_dir("/proc/self/fd")?.count();
            if unsafe { sendmsg(sender.as_raw_fd(), &message, 0) } != 1 {
                return Err(io::Error::last_os_error());
            }
            if receive_fd_bounded(&receiver, meta.dev(), inode, meta.uid(), capacity).is_ok() {
                return Err(io::Error::other(format!("{label} accepted")));
            }
            let after = std::fs::read_dir("/proc/self/fd")?.count();
            if after != before {
                return Err(io::Error::other(format!("{label} leaked descriptors")));
            }
            println!("RECEIVER_{}_REFUSED_NO_FD_LEAK", label.to_uppercase());
        }
        let mut name = [0x55; 16];
        name[..4].copy_from_slice(&std::process::id().to_be_bytes());
        let mut abstract_name = b"ipse-lease-v1-".to_vec();
        abstract_name.extend_from_slice(&name);
        let listener = UnixListener::bind_addr(&SocketAddr::from_abstract_name(abstract_name)?)?;
        let handle = thread::spawn(move || -> io::Result<usize> {
            let (mut stream, _) = listener.accept()?;
            stream.set_read_timeout(Some(Duration::from_secs(3)))?;
            let mut received = [0; 32];
            stream.read(&mut received)
        });
        if connect(name, [7; 32], std::process::id() + 1, meta.uid()).is_ok() {
            return Err(io::Error::other("substitute helper accepted"));
        }
        if handle
            .join()
            .map_err(|_| io::Error::other("listener panicked"))??
            != 0
        {
            return Err(io::Error::other("secret disclosed to substitute helper"));
        }
        println!("RECEIVER_WRONG_HELPER_REFUSED_BEFORE_SECRET");
        Ok(())
    }
    fn frame_controls() -> io::Result<()> {
        for (label, bytes) in [
            ("partial_header", vec![b'X', 0]),
            ("partial_body", vec![b'X', 0, 0, 0, 3, 1]),
        ] {
            let (mut sender, mut receiver) = UnixStream::pair()?;
            sender.write_all(&bytes)?;
            let start = Instant::now();
            let result = read_frame_for(&mut receiver, Duration::from_millis(100));
            if !result.is_err_and(|error| error.kind() == io::ErrorKind::TimedOut)
                || start.elapsed() > Duration::from_secs(2)
            {
                return Err(io::Error::other(format!("{label} was not bounded")));
            }
            println!("FRAME_{}_TIMED_OUT", label.to_uppercase());
        }
        let (mut sender, mut receiver) = UnixStream::pair()?;
        sender.write_all(&[b'X', 0, 0, 0, 2, 7, 8])?;
        if read_frame_for(&mut receiver, Duration::from_millis(100))? != (b'X', vec![7, 8]) {
            return Err(io::Error::other("complete frame changed"));
        }
        println!("FRAME_COMPLETE_PASSED");
        Ok(())
    }
    fn locked(file: &File) -> io::Result<()> {
        if unsafe { flock(file.as_raw_fd(), 2 | 4) } == 0 {
            Ok(())
        } else {
            Err(io::Error::last_os_error())
        }
    }
    fn run_case(root: &Path, helper: &Path, mode: u8, source: bool) -> io::Result<()> {
        let directory = root.join(format!(
            "{}-{mode}",
            if source { "source" } else { "transaction" }
        ));
        let (mut child, mut input, mut output, lock_path) =
            open_helper(helper, &directory, source, mode == 12)?;
        if mode == 7 {
            input.write_all(&[b'C', 0, 0, 0, 0])?;
            input.flush()?;
            let (tag, body) = read_frame(&mut output)?;
            if tag != b'U' || body != b"unlocked" {
                return Err(io::Error::other("source cancellation failed"));
            }
            child.0.wait()?;
            let contender = OpenOptions::new().read(true).write(true).open(lock_path)?;
            locked(&contender)?;
            println!("SOURCE_EXPORT_CANCEL_RELEASED");
            return Ok(());
        }
        let second_lock = if mode == 6 || mode == 10 {
            let second = directory.join("second");
            DirBuilder::new().mode(0o700).create(&second)?;
            let path = second.join(".lock");
            write_frame(&mut input, b'A', 2, 1, path.to_str().unwrap().as_bytes())?;
            let (tag, payload) = read_frame(&mut output)?;
            if tag != b'A' || payload.len() != 9 || payload[8] != 2 {
                return Err(io::Error::other("second lock acquisition failed"));
            }
            Some(path)
        } else {
            None
        };
        let meta = std::fs::metadata(&lock_path)?;
        let helper_pid = child.0.id();
        let uid = meta.uid();
        let dev = meta.dev();
        let expected_inode = meta.ino();
        let mut name = [mode + if source { 20 } else { 10 }; 16];
        name[0..4].copy_from_slice(&std::process::id().to_be_bytes());
        let secret = [mode + 30; 32];
        let pid = if mode == 1 {
            std::process::id().saturating_add(100_000)
        } else {
            std::process::id()
        };
        let inode = if mode == 2 {
            meta.ino() ^ 1
        } else {
            meta.ino()
        };
        let request = request(pid, name, secret, meta.dev(), inode);
        write_frame(
            &mut input,
            b'X',
            if source {
                1
            } else if mode == 6 || mode == 10 {
                3
            } else {
                2
            },
            if mode == 6 || mode == 10 { 2 } else { 1 },
            if source { &request[1..] } else { &request },
        )?;
        if mode == 2 {
            let (tag, _) = read_frame(&mut output)?;
            if tag != b'E' {
                return Err(io::Error::other("wrong inode was not refused"));
            }
            let contender = OpenOptions::new().read(true).write(true).open(&lock_path)?;
            if !locked(&contender).is_err_and(|e| e.kind() == io::ErrorKind::WouldBlock) {
                return Err(io::Error::other("refusal lost the original lock"));
            }
            child.0.kill()?;
            child.0.wait()?;
            locked(&contender)?;
            println!(
                "{}_EXPORT_WRONG_INODE_REFUSED",
                if source { "SOURCE" } else { "TRANSACTION" }
            );
            return Ok(());
        }
        if mode == 5 {
            let (ready_tx, ready_rx) = mpsc::channel();
            let (proceed_tx, proceed_rx) = mpsc::channel();
            let (result_tx, result_rx) = mpsc::channel();
            let handle = thread::spawn(move || {
                let result = (|| {
                    let socket = connect(name, secret, helper_pid, uid)?;
                    ready_tx
                        .send(())
                        .map_err(|_| io::Error::other("owner missing"))?;
                    proceed_rx
                        .recv_timeout(Duration::from_secs(5))
                        .map_err(|_| io::Error::other("owner missing"))?;
                    receive_fd(&socket, dev, expected_inode, uid)
                })();
                let _ = result_tx.send(result);
            });
            ready_rx
                .recv_timeout(Duration::from_secs(7))
                .map_err(|_| io::Error::other("peer did not connect"))?;
            drop(input);
            proceed_tx
                .send(())
                .map_err(|_| io::Error::other("peer stopped"))?;
            let (tag, _) = read_frame(&mut output)?;
            let received = result_rx
                .recv_timeout(Duration::from_secs(7))
                .map_err(|_| io::Error::other("peer timed out"))?;
            handle
                .join()
                .map_err(|_| io::Error::other("peer panicked"))?;
            child.0.wait()?;
            match received {
                Ok(lease) if tag == b'U' => {
                    let contender = OpenOptions::new().read(true).write(true).open(lock_path)?;
                    if !locked(&contender).is_err_and(|e| e.kind() == io::ErrorKind::WouldBlock) {
                        return Err(io::Error::other("transferred lock not retained"));
                    }
                    drop(lease);
                    locked(&contender)?;
                    println!(
                        "{}_EXPORT_OWNER_LOSS_UNKNOWN transfer_occurred=1",
                        if source { "SOURCE" } else { "TRANSACTION" }
                    );
                }
                Err(_) if tag == b'E' => println!(
                    "{}_EXPORT_OWNER_LOSS_REFUSED transfer_occurred=0",
                    if source { "SOURCE" } else { "TRANSACTION" }
                ),
                _ => return Err(io::Error::other("owner loss falsely reported success")),
            }
            return Ok(());
        }
        let (tx, rx) = mpsc::channel();
        let actual_secret = if mode == 3 { [99; 32] } else { secret };
        let handle = thread::spawn(move || {
            let result = peer(
                name,
                actual_secret,
                mode != 4,
                helper_pid,
                uid,
                dev,
                expected_inode,
            );
            let _ = tx.send(result);
        });
        if mode == 12 {
            let received = rx
                .recv_timeout(Duration::from_secs(7))
                .map_err(|_| io::Error::other("receiver timed out"))??;
            handle
                .join()
                .map_err(|_| io::Error::other("peer panicked"))?;
            let ready = directory.join("race.ready");
            let until = Instant::now() + Duration::from_secs(7);
            while !ready.exists() && Instant::now() < until {
                thread::sleep(Duration::from_millis(5));
            }
            if !ready.exists() {
                return Err(io::Error::other("test hook did not stop helper"));
            }
            drop(input);
            std::fs::write(directory.join("race.proceed"), b"proceed")?;
            let (tag, body) = read_frame(&mut output)?;
            if tag != b'X' || body.len() != 10 || body[9] != 0 {
                return Err(io::Error::other("expected X after final-check owner loss"));
            }
            child.0.wait()?;
            drop(received);
            println!(
                "{}_FINAL_CHECK_OWNER_LOSS_X_OBSERVED",
                if source { "SOURCE" } else { "TRANSACTION" }
            );
            return Ok(());
        }
        let (tag, body) = read_frame(&mut output)?;
        let received = rx
            .recv_timeout(Duration::from_secs(7))
            .map_err(|_| io::Error::other("receiver timed out"))?;
        handle
            .join()
            .map_err(|_| io::Error::other("receiver panicked"))?;
        if mode == 1 || mode == 3 {
            if tag != b'E' || received.is_ok() {
                return Err(io::Error::other("wrong peer or secret was accepted"));
            }
            let contender = OpenOptions::new().read(true).write(true).open(&lock_path)?;
            if !locked(&contender).is_err_and(|e| e.kind() == io::ErrorKind::WouldBlock) {
                return Err(io::Error::other("refusal lost the original lock"));
            }
            child.0.kill()?;
            child.0.wait()?;
            locked(&contender)?;
            println!(
                "{}_EXPORT_WRONG_{}_REFUSED",
                if source { "SOURCE" } else { "TRANSACTION" },
                if mode == 1 { "PID" } else { "SECRET" }
            );
            return Ok(());
        }
        let (lease, _socket) = received?;
        if mode == 8 || mode == 9 || mode == 10 || mode == 11 {
            if tag != b'X' || body.len() != 10 || body[9] != 0 {
                return Err(io::Error::other("export not acknowledged"));
            }
            if mode == 11 {
                write_frame(
                    &mut input,
                    b'X',
                    if source { 2 } else { 3 },
                    1,
                    if source { &request[1..] } else { &request },
                )?;
                let (duplicate, _) = read_frame(&mut output)?;
                if duplicate != b'E' {
                    return Err(io::Error::other("duplicate slot export accepted"));
                }
                println!(
                    "{}_DUPLICATE_SLOT_REFUSED",
                    if source { "SOURCE" } else { "TRANSACTION" }
                );
            }
            if mode == 9 {
                input.write_all(&[b'C', 0, 0, 0, 0])?;
                input.flush()?;
                let (release, _) = read_frame(&mut output)?;
                if release != b'E' {
                    return Err(io::Error::other(
                        "source cancellation falsely confirmed release",
                    ));
                }
            } else {
                let seq = if mode == 10 {
                    4
                } else if mode == 11 {
                    if source {
                        3
                    } else {
                        4
                    }
                } else if source {
                    2
                } else {
                    3
                };
                write_frame(&mut input, b'R', seq, if mode == 10 { 2 } else { 1 }, &[])?;
                let (release, _) = read_frame(&mut output)?;
                if release != b'U' {
                    return Err(io::Error::other("exported release was falsely confirmed"));
                }
            }
            child.0.wait()?;
        } else if mode == 4 {
            if tag != b'U' || body.len() != 10 {
                return Err(io::Error::other("missing ack did not become unknown"));
            }
            child.0.wait()?;
        } else {
            if tag != b'X' || body.len() != 10 || body[9] != 0 {
                return Err(io::Error::other("export not acknowledged"));
            }
            child.0.kill()?;
            child.0.wait()?;
        }
        let contender = OpenOptions::new().read(true).write(true).open(lock_path)?;
        if !locked(&contender).is_err_and(|e| e.kind() == io::ErrorKind::WouldBlock) {
            return Err(io::Error::other("exported lease failed to retain lock"));
        }
        if let Some(path) = second_lock {
            let second = OpenOptions::new().read(true).write(true).open(path)?;
            locked(&second)?;
            println!("TRANSACTION_PARENT_SLOT_EXPORT_PASSED nonexported_top_released=1");
        }
        drop(lease);
        locked(&contender)?;
        println!(
            "{}_EXPORT_{}_PASSED helper_dead=1 recipient_retained=1 last_close_released=1",
            if source { "SOURCE" } else { "TRANSACTION" },
            if mode == 8 || mode == 9 || mode == 10 || mode == 11 {
                "RELEASE_UNKNOWN"
            } else if mode == 4 {
                "MISSING_ACK_UNKNOWN"
            } else {
                "ACKNOWLEDGED"
            }
        );
        Ok(())
    }
    pub fn main() -> Result<(), String> {
        let args: Vec<_> = env::args_os().collect();
        if args.len() == 2 && args[1] == "--frame-controls" {
            return frame_controls().map_err(|e| e.to_string());
        }
        if args.len() == 3 && args[1] == "--receiver-controls" {
            return receiver_controls(Path::new(&args[2])).map_err(|e| e.to_string());
        }
        if args.len() != 3 && args.len() != 4 {
            return Err("usage: transaction-export-test PRIVATE_DIR IPSE_RUNNER [MODE]".into());
        }
        let selected = if args.len() == 4 {
            Some(
                args[3]
                    .to_string_lossy()
                    .parse::<u8>()
                    .map_err(|e| e.to_string())?,
            )
        } else {
            None
        };
        for source in [false, true] {
            for mode in 0..=12 {
                if selected.is_some_and(|selected| selected != mode)
                    || (selected.is_none() && mode == 12)
                {
                    continue;
                }
                if source && (mode == 6 || mode == 10) {
                    continue;
                }
                if !source && (mode == 7 || mode == 9) {
                    continue;
                }
                run_case(Path::new(&args[1]), Path::new(&args[2]), mode, source)
                    .map_err(|e| format!("source {source}, case {mode}: {e}"))?;
            }
        }
        let invalid_dir = Path::new(&args[1]).join("invalid-source");
        DirBuilder::new()
            .mode(0o700)
            .create(&invalid_dir)
            .map_err(|e| e.to_string())?;
        let invalid = Command::new(&args[2])
            .arg("--lock-export-v1")
            .arg(invalid_dir.join("bad.lock"))
            .stdin(Stdio::null())
            .output()
            .map_err(|e| e.to_string())?;
        if invalid.status.success() || invalid.stdout.first() != Some(&b'E') {
            return Err("invalid source name accepted".into());
        }
        let target = invalid_dir.join("target");
        File::create(&target).map_err(|e| e.to_string())?;
        let symlink = invalid_dir.join(format!("{}.lock", "b".repeat(32)));
        std::os::unix::fs::symlink(&target, &symlink).map_err(|e| e.to_string())?;
        let refused = Command::new(&args[2])
            .arg("--lock-export-v1")
            .arg(&symlink)
            .stdin(Stdio::null())
            .output()
            .map_err(|e| e.to_string())?;
        if refused.status.success() || refused.stdout.first() != Some(&b'E') {
            return Err("source symlink accepted".into());
        }
        println!("SOURCE_EXPORT_INVALID_NAME_AND_SYMLINK_REFUSED");
        Ok(())
    }
}
#[cfg(target_os = "linux")]
fn main() {
    if let Err(error) = test::main() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("Linux-only test");
    std::process::exit(1);
}
