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
    use std::os::unix::process::CommandExt;
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
        fn setrlimit(resource: i32, limits: *const Limit) -> i32;
        fn pipe2(fds: *mut i32, flags: i32) -> i32;
        fn dup2(old: i32, new: i32) -> i32;
    }
    #[repr(C)]
    struct Limit {
        current: u64,
        maximum: u64,
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
        open_helper_stalled(helper, directory, source, race, false)
    }
    fn open_helper_stalled(
        helper: &Path,
        directory: &Path,
        source: bool,
        race: bool,
        stall: bool,
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
        if stall {
            command.env("IPSE_TEST_EXPORT_STALL", directory.join("stall"));
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
    fn collector_case(root: &Path, helper: &Path, mode: u8) -> io::Result<()> {
        let directory = root.join(format!("collector-{mode}"));
        DirBuilder::new().mode(0o700).create(&directory)?;
        let (mut a, mut a_in, mut a_out, a_lock) =
            open_helper(helper, &directory.join("a"), false, false)?;
        let (mut b, mut b_in, mut b_out, b_lock) =
            open_helper(helper, &directory.join("b"), true, false)?;
        let mut collector = OwnedChild(
            Command::new(helper)
                .arg("--lease-collect-v1")
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()?,
        );
        let mut input = collector
            .0
            .stdin
            .take()
            .ok_or_else(|| io::Error::other("collector stdin missing"))?;
        let mut output = collector
            .0
            .stdout
            .take()
            .ok_or_else(|| io::Error::other("collector stdout missing"))?;
        let a_meta = std::fs::metadata(&a_lock)?;
        let b_meta = std::fs::metadata(&b_lock)?;
        let mut name_a = [61u8; 16];
        let mut name_b = [62u8; 16];
        name_a[..4].copy_from_slice(&std::process::id().to_be_bytes());
        name_b[..4].copy_from_slice(&std::process::id().to_be_bytes());
        let secret_a = [71u8; 32];
        let secret_b = [72u8; 32];
        let a_req = request(
            collector.0.id(),
            name_a,
            secret_a,
            a_meta.dev(),
            a_meta.ino(),
        );
        let b_req = request(
            collector.0.id(),
            name_b,
            secret_b,
            b_meta.dev(),
            b_meta.ino(),
        );
        write_frame(&mut a_in, b'X', 2, 1, &a_req)?;
        write_frame(&mut b_in, b'X', 1, 1, &b_req[1..])?;
        // Both helpers need time to bind their unique private listeners.
        thread::sleep(Duration::from_millis(50));
        let a_pid = if mode == 2 {
            std::process::id()
        } else {
            a.0.id()
        };
        let a_ino = if mode == 1 {
            a_meta.ino() ^ 1
        } else {
            a_meta.ino()
        };
        let a_entry = request(a_pid, name_a, secret_a, a_meta.dev(), a_ino);
        let b_entry = if mode == 3 {
            a_entry.clone()
        } else {
            request(b.0.id(), name_b, secret_b, b_meta.dev(), b_meta.ino())
        };
        let mut body = (if mode == 5 { 250u64 } else { 10_000u64 })
            .to_be_bytes()
            .to_vec();
        body.push(2);
        body.extend_from_slice(&a_entry[1..]);
        body.extend_from_slice(&b_entry[1..]);
        input.write_all(b"I")?;
        input.write_all(&(body.len() as u32).to_be_bytes())?;
        input.write_all(&body)?;
        input.flush()?;
        if (1..=3).contains(&mode) {
            let status = collector.0.wait()?;
            if status.success() {
                return Err(io::Error::other("invalid collection succeeded"));
            }
            a.0.kill()?;
            b.0.kill()?;
            a.0.wait()?;
            b.0.wait()?;
            for path in [a_lock, b_lock] {
                let contender = OpenOptions::new().read(true).write(true).open(path)?;
                locked(&contender)?;
            }
            println!(
                "COLLECTOR_{}_REFUSED_NO_RETAINED_LOCK",
                match mode {
                    1 => "WRONG_INODE",
                    2 => "WRONG_EXECUTABLE",
                    _ => "DUPLICATE",
                }
            );
            return Ok(());
        }
        let (tag, content) = read_frame(&mut output)?;
        if tag != b'L' || content != [2] {
            return Err(io::Error::other(format!(
                "two leases not collected: tag {tag}, {}",
                String::from_utf8_lossy(&content)
            )));
        }
        for stream in [&mut a_out, &mut b_out] {
            let (kind, body) = read_frame(stream)?;
            if kind != b'X' {
                return Err(io::Error::other(format!(
                    "helper export response {kind}: {body:?}"
                )));
            }
        }
        a.0.kill()?;
        b.0.kill()?;
        a.0.wait()?;
        b.0.wait()?;
        let mut contenders = Vec::new();
        for path in [a_lock, b_lock] {
            let file = OpenOptions::new().read(true).write(true).open(path)?;
            if !locked(&file).is_err_and(|e| e.kind() == io::ErrorKind::WouldBlock) {
                return Err(io::Error::other("collector lost a lease"));
            }
            contenders.push(file);
        }
        if mode == 4 || mode == 5 {
            if mode == 4 {
                drop(input);
            }
            let (kind, _) = read_frame(&mut output)?;
            if kind != b'E' || collector.0.wait()?.success() {
                return Err(io::Error::other("cancelled collector did not refuse"));
            }
        } else {
            input.write_all(b"C")?;
            input.flush()?;
            let (kind, count) = read_frame(&mut output)?;
            if kind != b'C' || count != [2] {
                return Err(io::Error::other("collector close unconfirmed"));
            }
            if !collector.0.wait()?.success() {
                return Err(io::Error::other("collector exited unsuccessfully"));
            }
        }
        for file in contenders {
            locked(&file)?;
        }
        println!(
            "COLLECTOR_{}",
            match mode {
                4 => "OWNER_LOSS_RELEASED",
                5 => "DEADLINE_RELEASED",
                _ => "TWO_LEASES_RETAINED_AND_CLOSED",
            }
        );
        Ok(())
    }
    fn collector_capacity(root: &Path, helper: &Path) -> io::Result<()> {
        let mut holders = Vec::new();
        for index in 0..131usize {
            holders.push(open_helper(
                helper,
                &root.join(format!("lease-{index}")),
                index < 129,
                false,
            )?);
        }
        let mut collector = OwnedChild(
            Command::new(helper)
                .arg("--lease-collect-v1")
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()?,
        );
        let mut input = collector
            .0
            .stdin
            .take()
            .ok_or_else(|| io::Error::other("collector stdin missing"))?;
        let mut output = collector
            .0
            .stdout
            .take()
            .ok_or_else(|| io::Error::other("collector stdout missing"))?;
        let mut body = 30_000u64.to_be_bytes().to_vec();
        body.push(131);
        for (index, (child, stdin, _, path)) in holders.iter_mut().enumerate() {
            let meta = std::fs::metadata(path)?;
            let mut name = [91u8; 16];
            name[..4].copy_from_slice(&std::process::id().to_be_bytes());
            name[4..6].copy_from_slice(&(index as u16).to_be_bytes());
            let mut secret = [92u8; 32];
            secret[..2].copy_from_slice(&(index as u16).to_be_bytes());
            let transfer = request(collector.0.id(), name, secret, meta.dev(), meta.ino());
            write_frame(
                stdin,
                b'X',
                if index < 129 { 1 } else { 2 },
                1,
                if index < 129 {
                    &transfer[1..]
                } else {
                    &transfer
                },
            )?;
            let entry = request(child.0.id(), name, secret, meta.dev(), meta.ino());
            body.extend_from_slice(&entry[1..]);
        }
        input.write_all(b"I")?;
        input.write_all(&(body.len() as u32).to_be_bytes())?;
        input.write_all(&body)?;
        input.flush()?;
        let (tag, data) = read_frame(&mut output)?;
        if tag != b'L' || data != [131] {
            return Err(io::Error::other(format!(
                "capacity refused: {tag}, {}",
                String::from_utf8_lossy(&data)
            )));
        }
        let mut contenders = Vec::new();
        for (child, _, stdout, path) in &mut holders {
            let (kind, _) = read_frame(stdout)?;
            if kind != b'X' {
                return Err(io::Error::other("capacity export not acknowledged"));
            }
            child.0.kill()?;
            child.0.wait()?;
            let file = OpenOptions::new().read(true).write(true).open(path)?;
            if !locked(&file).is_err_and(|e| e.kind() == io::ErrorKind::WouldBlock) {
                return Err(io::Error::other("capacity lease lost"));
            }
            contenders.push(file);
        }
        input.write_all(b"C")?;
        input.flush()?;
        let (tag, count) = read_frame(&mut output)?;
        if tag != b'C' || count != [131] || !collector.0.wait()?.success() {
            return Err(io::Error::other("capacity close unconfirmed"));
        }
        for contender in contenders {
            locked(&contender)?;
        }
        println!("COLLECTOR_128_SOURCE_ONE_LIVE_STANDIN_TWO_TRANSACTION_HELD_AND_CLOSED");
        Ok(())
    }
    fn retained_close(root: &Path, helper: &Path, mode: &str) -> io::Result<()> {
        let (mut owner, mut owner_in, mut owner_out, first) = open_helper(helper, &root.join("owner"), false, false)?;
        let mut paths = vec![first];
        for index in 1..3 {
            let directory = root.join(format!("nested-{index}"));
            DirBuilder::new().mode(0o700).create(&directory)?;
            let path = directory.join(".lock");
            write_frame(&mut owner_in, b'A', index as u64 + 1, index as u8, path.to_str().unwrap().as_bytes())?;
            let (kind, _) = read_frame(&mut owner_out)?;
            if kind != b'A' { return Err(io::Error::other("nested acquisition failed")); }
            paths.push(path);
        }
        let (mut source, mut source_in, mut source_out, source_path) = open_helper(helper, &root.join("source"), false, false)?;
        paths.push(source_path);
        let mut collector = OwnedChild(Command::new(helper).arg("--lease-collect-close-v2")
            .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn()?);
        let mut input = collector.0.stdin.take().ok_or_else(|| io::Error::other("missing collector input"))?;
        let mut output = collector.0.stdout.take().ok_or_else(|| io::Error::other("missing collector output"))?;
        let operation = [37_u8; 16];
        let metas: Vec<_> = paths.iter().map(std::fs::metadata).collect::<io::Result<_>>()?;
        let mut names = [[51_u8; 16], [52_u8; 16], [53_u8; 16], [54_u8; 16]];
        for name in &mut names { name[..4].copy_from_slice(&std::process::id().to_be_bytes()); }
        let secrets = [[61_u8; 32], [62_u8; 32], [63_u8; 32], [64_u8; 32]];
        let slots = [0_u8, 1, 2, 0];
        let mut body = 15_000_u64.to_be_bytes().to_vec();
        body.extend_from_slice(&operation); body.push(4);
        for index in 0..4 {
            let exporter = if index < 3 { owner.0.id() } else { source.0.id() };
            let entry = request(exporter, names[index], secrets[index], metas[index].dev(), metas[index].ino());
            body.push(slots[index]); body.extend_from_slice(&entry[1..]);
        }
        input.write_all(b"I")?; input.write_all(&(body.len() as u32).to_be_bytes())?;
        input.write_all(&body)?; input.flush()?;
        for index in 0..4 {
            let request = request(collector.0.id(), names[index], secrets[index], metas[index].dev(), metas[index].ino());
            let mut extra = vec![slots[index]]; extra.extend_from_slice(&operation); extra.extend_from_slice(&request[1..]);
            let (stream, output, seq, depth) = if index < 3 { (&mut owner_in, &mut owner_out, 4 + index as u64, 3) } else { (&mut source_in, &mut source_out, 2, 1) };
            write_frame(stream, b'Y', seq, depth, &extra)?;
            let (kind, response) = read_frame(output)?;
            if kind != b'Y' || response.len() != 26 || response[9] != slots[index] || response[10..] != operation {
                return Err(io::Error::other(format!("retained transfer refused: kind={} response={response:?}", kind as char)));
            }
        }
        let (kind, response) = read_frame(&mut output)?;
        if kind != b'L' || response != [operation.as_slice(), &[4]].concat() { return Err(io::Error::other("retained collection refused")); }
        let contenders: Vec<_> = paths.iter().map(|path| OpenOptions::new().read(true).write(true).open(path)).collect::<io::Result<_>>()?;
        for file in &contenders {
            if !locked(file).is_err_and(|e| e.kind() == io::ErrorKind::WouldBlock) { return Err(io::Error::other("shared lock escaped")); }
        }
        if mode == "exporter-lost" {
            owner.0.kill()?; owner.0.wait()?;
            let (kind, _) = read_frame(&mut output)?;
            if kind != b'E' || collector.0.wait()?.success() { return Err(io::Error::other("exporter loss did not stop collector")); }
            for file in &contenders[..3] { locked(file)?; }
            if !locked(&contenders[3]).is_err_and(|e| e.kind() == io::ErrorKind::WouldBlock) { return Err(io::Error::other("surviving exporter lost lock")); }
            source.0.kill()?; source.0.wait()?;
            locked(&contenders[3])?;
            println!("RETAINED_EXPORTER_LOSS_STOPPED_COLLECTOR");
            return Ok(());
        }
        if mode == "wrong-slot" {
            let mut extra = vec![0]; extra.extend_from_slice(&[38_u8; 16]);
            write_frame(&mut owner_in, b'K', 7, 3, &extra)?;
            let (kind, _) = read_frame(&mut owner_out)?;
            if kind != b'U' || !owner.0.wait()?.success() { return Err(io::Error::other("forged settlement was not unknown")); }
            for file in &contenders {
                if !locked(file).is_err_and(|e| e.kind() == io::ErrorKind::WouldBlock) { return Err(io::Error::other("recipient failed to retain shared lock")); }
            }
            collector.0.kill()?; collector.0.wait()?;
            source.0.kill()?; source.0.wait()?;
            for file in &contenders { locked(file)?; }
            println!("RETAINED_FORGED_SETTLEMENT_BLOCKS_UNTIL_RECIPIENT_EXIT");
            return Ok(());
        }
        if mode == "lost" {
            collector.0.kill()?; collector.0.wait()?;
            let mut extra = vec![0]; extra.extend_from_slice(&operation);
            write_frame(&mut owner_in, b'K', 7, 3, &extra)?;
            let (kind, _) = read_frame(&mut owner_out)?;
            if kind != b'U' { return Err(io::Error::other("recipient loss reported settled")); }
            println!("RETAINED_RECIPIENT_LOSS_UNKNOWN");
            return Ok(());
        }
        let close_operation = if mode == "wrong" { [38_u8; 16] } else { operation };
        input.write_all(b"C")?; input.write_all(&close_operation)?; input.flush()?;
        if mode == "wrong" {
            if collector.0.wait()?.success() { return Err(io::Error::other("wrong close accepted")); }
            let mut extra = vec![0]; extra.extend_from_slice(&operation);
            write_frame(&mut owner_in, b'K', 7, 3, &extra)?;
            let (kind, _) = read_frame(&mut owner_out)?;
            if kind != b'U' { return Err(io::Error::other("wrong close reported settled")); }
            println!("RETAINED_WRONG_CLOSE_UNKNOWN");
            return Ok(());
        }
        for index in 0..4 {
            let mut extra = vec![slots[index]]; extra.extend_from_slice(&operation);
            let (stream, output, seq, depth) = if index < 3 { (&mut owner_in, &mut owner_out, 7 + index as u64, 3) } else { (&mut source_in, &mut source_out, 3, 1) };
            write_frame(stream, b'K', seq, depth, &extra)?;
            let (kind, response) = read_frame(output)?;
            if kind != b'K' || response.len() != 26 || response[9] != slots[index] || response[10..] != operation { return Err(io::Error::other("retained close unconfirmed")); }
        }
        let (kind, response) = read_frame(&mut output)?;
        let collector_status = collector.0.wait()?;
        if kind != b'C' || response != [operation.as_slice(), &[4]].concat() || !collector_status.success() { return Err(io::Error::other(format!("collector close unconfirmed kind={} response={response:?} status={collector_status}", kind as char))); }
        for file in &contenders {
            if !locked(file).is_err_and(|e| e.kind() == io::ErrorKind::WouldBlock) { return Err(io::Error::other("original owner lost lock early")); }
        }
        for (seq, depth) in [(10,3), (11,2), (12,1)] {
            write_frame(&mut owner_in, b'R', seq, depth, &[])?;
            let (kind, _) = read_frame(&mut owner_out)?;
            if kind != b'R' { return Err(io::Error::other("owner release unconfirmed")); }
        }
        write_frame(&mut source_in, b'R', 4, 1, &[])?;
        let (kind, _) = read_frame(&mut source_out)?;
        if kind != b'R' || !owner.0.wait()?.success() || !source.0.wait()?.success() { return Err(io::Error::other("source release unconfirmed")); }
        for file in &contenders { locked(file)?; }
        println!("RETAINED_FOUR_LEASES_CLOSED_AND_RELEASED");
        Ok(())
    }

    fn retained_repeat(root: &Path, helper: &Path) -> io::Result<()> {
        let (mut owner, mut owner_in, mut owner_out, lock) = open_helper(helper, &root.join("owner"), false, false)?;
        let meta = std::fs::metadata(&lock)?;
        let contender = OpenOptions::new().read(true).write(true).open(&lock)?;
        for round in 0..2 {
            let operation = [70 + round; 16];
            let mut name = [80 + round; 16]; name[..4].copy_from_slice(&std::process::id().to_be_bytes());
            let secret = [90 + round; 32];
            let mut collector = OwnedChild(Command::new(helper).arg("--lease-collect-close-v2")
                .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn()?);
            let mut input = collector.0.stdin.take().ok_or_else(|| io::Error::other("missing collector input"))?;
            let mut output = collector.0.stdout.take().ok_or_else(|| io::Error::other("missing collector output"))?;
            let mut body = 10_000_u64.to_be_bytes().to_vec(); body.extend_from_slice(&operation); body.push(1);
            let entry = request(owner.0.id(), name, secret, meta.dev(), meta.ino());
            body.push(0); body.extend_from_slice(&entry[1..]);
            input.write_all(b"I")?; input.write_all(&(body.len() as u32).to_be_bytes())?; input.write_all(&body)?; input.flush()?;
            let target = request(collector.0.id(), name, secret, meta.dev(), meta.ino());
            let mut extra = vec![0]; extra.extend_from_slice(&operation); extra.extend_from_slice(&target[1..]);
            let base = 2 + u64::from(round) * 2;
            write_frame(&mut owner_in, b'Y', base, 1, &extra)?;
            if read_frame(&mut owner_out)?.0 != b'Y' || read_frame(&mut output)?.0 != b'L' { return Err(io::Error::other("repeat transfer refused")); }
            input.write_all(b"C")?; input.write_all(&operation)?; input.flush()?;
            let mut settlement = vec![0]; settlement.extend_from_slice(&operation);
            write_frame(&mut owner_in, b'K', base + 1, 1, &settlement)?;
            if read_frame(&mut owner_out)?.0 != b'K' || read_frame(&mut output)?.0 != b'C' || !collector.0.wait()?.success() { return Err(io::Error::other("repeat settlement refused")); }
            if !locked(&contender).is_err_and(|e| e.kind() == io::ErrorKind::WouldBlock) { return Err(io::Error::other("repeat owner lost original lock")); }
        }
        let mut replay = vec![0]; replay.extend_from_slice(&[70_u8; 16]); replay.extend_from_slice(&[0_u8; 68]);
        write_frame(&mut owner_in, b'Y', 6, 1, &replay)?;
        if read_frame(&mut owner_out)?.0 != b'U' || !owner.0.wait()?.success() { return Err(io::Error::other("replayed operation was not refused")); }
        locked(&contender)?;
        println!("RETAINED_REPEAT_THAW_AND_REPLAY_REFUSAL");
        Ok(())
    }

    fn collector_nested(root: &Path, helper: &Path) -> io::Result<()> {
        let (mut owner, mut owner_in, mut owner_out, first) =
            open_helper(helper, &root.join("first"), false, false)?;
        let second_dir = root.join("second");
        DirBuilder::new().mode(0o700).create(&second_dir)?;
        let second = second_dir.join(".lock");
        write_frame(
            &mut owner_in,
            b'A',
            2,
            1,
            second.to_str().unwrap().as_bytes(),
        )?;
        let (kind, _) = read_frame(&mut owner_out)?;
        if kind != b'A' {
            return Err(io::Error::other("nested lock acquisition refused"));
        }
        let mut collector = OwnedChild(
            Command::new(helper)
                .arg("--lease-collect-v1")
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()?,
        );
        let mut input = collector
            .0
            .stdin
            .take()
            .ok_or_else(|| io::Error::other("collector stdin missing"))?;
        let mut output = collector
            .0
            .stdout
            .take()
            .ok_or_else(|| io::Error::other("collector stdout missing"))?;
        let mut names = [[101u8; 16], [102u8; 16]];
        for name in &mut names {
            name[..4].copy_from_slice(&std::process::id().to_be_bytes());
        }
        let metas = [std::fs::metadata(&first)?, std::fs::metadata(&second)?];
        let secrets = [[111u8; 32], [112u8; 32]];
        let first_req = request(
            collector.0.id(),
            names[0],
            secrets[0],
            metas[0].dev(),
            metas[0].ino(),
        );
        let mut second_req = request(
            collector.0.id(),
            names[1],
            secrets[1],
            metas[1].dev(),
            metas[1].ino(),
        );
        second_req[0] = 1;
        write_frame(&mut owner_in, b'X', 3, 2, &first_req)?;
        let mut body = 10_000u64.to_be_bytes().to_vec();
        body.push(2);
        for index in 0..2 {
            let entry = request(
                owner.0.id(),
                names[index],
                secrets[index],
                metas[index].dev(),
                metas[index].ino(),
            );
            body.extend_from_slice(&entry[1..]);
        }
        input.write_all(b"I")?;
        input.write_all(&(body.len() as u32).to_be_bytes())?;
        input.write_all(&body)?;
        input.flush()?;
        let (kind, data) = read_frame(&mut owner_out)?;
        if kind != b'X' || data.last() != Some(&0) {
            return Err(io::Error::other("first nested export refused"));
        }
        write_frame(&mut owner_in, b'X', 4, 2, &second_req)?;
        let (kind, data) = read_frame(&mut owner_out)?;
        if kind != b'X' || data.last() != Some(&1) {
            return Err(io::Error::other("second nested export refused"));
        }
        let (kind, data) = read_frame(&mut output)?;
        if kind != b'L' || data != [2] {
            return Err(io::Error::other("nested collection refused"));
        }
        owner.0.kill()?;
        owner.0.wait()?;
        let mut contenders = Vec::new();
        for path in [first, second] {
            let file = OpenOptions::new().read(true).write(true).open(path)?;
            if !locked(&file).is_err_and(|e| e.kind() == io::ErrorKind::WouldBlock) {
                return Err(io::Error::other("nested lease lost"));
            }
            contenders.push(file);
        }
        input.write_all(b"C")?;
        input.flush()?;
        let (kind, count) = read_frame(&mut output)?;
        if kind != b'C' || count != [2] || !collector.0.wait()?.success() {
            return Err(io::Error::other("nested collector close unconfirmed"));
        }
        for file in contenders {
            locked(&file)?;
        }
        println!("COLLECTOR_SAME_TRANSACTION_DISTINCT_SLOTS_RETAINED_AND_CLOSED");
        Ok(())
    }
    fn wait_child(child: &mut Child) -> io::Result<std::process::ExitStatus> {
        let deadline = Instant::now() + Duration::from_secs(6);
        loop {
            if let Some(status) = child.try_wait()? {
                return Ok(status);
            }
            if Instant::now() >= deadline {
                return Err(io::Error::new(
                    io::ErrorKind::TimedOut,
                    "child did not stop",
                ));
            }
            thread::sleep(Duration::from_millis(5));
        }
    }
    fn collector_fault(root: &Path, helper: &Path, mode: u8) -> io::Result<()> {
        let dir = root.join(format!("fault-{mode}"));
        DirBuilder::new().mode(0o700).create(&dir)?;
        let (mut holder, mut holder_in, mut holder_out, lock) =
            open_helper_stalled(helper, &dir.join("one"), true, false, mode == 4)?;
        let mut second = if mode == 3 {
            Some(open_helper(helper, &dir.join("two"), true, false)?)
        } else {
            None
        };
        let mut command = Command::new(helper);
        command
            .arg("--lease-collect-v1")
            .stdin(Stdio::piped())
            .stderr(Stdio::null());
        if mode == 2 {
            command.env("IPSE_TEST_COLLECT_CONNECT", dir.join("connect.ready"));
        }
        if mode == 5 || mode == 6 {
            command.env("IPSE_TEST_COLLECT_WRITE", dir.join("write.ready"));
        }
        let mut held_reader = None;
        if mode == 5 || mode == 6 {
            let (reader, mut writer) = UnixStream::pair()?;
            writer.set_nonblocking(true)?;
            let bytes = [0u8; 8192];
            loop {
                match writer.write(&bytes) {
                    Ok(0) => return Err(io::Error::other("failed to fill output")),
                    Ok(_) => (),
                    Err(e) if e.kind() == io::ErrorKind::WouldBlock => break,
                    Err(e) => return Err(e),
                }
            }
            let fd: std::os::fd::OwnedFd = writer.into();
            command.stdout(Stdio::from(File::from(fd)));
            held_reader = Some(reader);
        } else {
            command.stdout(Stdio::piped());
        }
        let mut collector = OwnedChild(command.spawn()?);
        let mut input = collector
            .0
            .stdin
            .take()
            .ok_or_else(|| io::Error::other("collector stdin missing"))?;
        if mode == 1 {
            input.write_all(&[b'I', 0, 0])?;
            drop(input);
            if wait_child(&mut collector.0)?.success() {
                return Err(io::Error::other("truncated setup accepted"));
            }
        } else {
            let meta = std::fs::metadata(&lock)?;
            let mut name = [121u8; 16];
            name[..4].copy_from_slice(&std::process::id().to_be_bytes());
            let secret = [122u8; 32];
            let transfer = request(collector.0.id(), name, secret, meta.dev(), meta.ino());
            if mode != 2 {
                write_frame(&mut holder_in, b'X', 1, 1, &transfer[1..])?;
            }
            let entry = request(holder.0.id(), name, secret, meta.dev(), meta.ino());
            let mut body = (if mode == 6 { 500u64 } else { 10_000u64 })
                .to_be_bytes()
                .to_vec();
            body.push(if second.is_some() { 2 } else { 1 });
            body.extend_from_slice(&entry[1..]);
            if let Some((child, _, _, path)) = &second {
                let second_meta = std::fs::metadata(path)?;
                let mut second_name = name;
                second_name[15] ^= 1;
                let second_entry = request(
                    child.0.id(),
                    second_name,
                    [123; 32],
                    second_meta.dev(),
                    second_meta.ino(),
                );
                body.extend_from_slice(&second_entry[1..]);
            }
            input.write_all(b"I")?;
            input.write_all(&(body.len() as u32).to_be_bytes())?;
            input.write_all(&body)?;
            input.flush()?;
            if mode == 4 {
                let ready = dir.join("one/stall.ready");
                let end = Instant::now() + Duration::from_secs(4);
                while !ready.exists() && Instant::now() < end {
                    thread::sleep(Duration::from_millis(5));
                }
                if !ready.exists() {
                    return Err(io::Error::other("stalled exporter was not reached"));
                }
            } else if matches!(mode, 3 | 5 | 6) {
                let (kind, _) = read_frame(&mut holder_out)?;
                if kind != b'X' {
                    return Err(io::Error::other("first export not acknowledged"));
                }
            }
            if matches!(mode, 2 | 5 | 6) {
                let marker = dir.join(if mode == 2 {
                    "connect.ready"
                } else {
                    "write.ready"
                });
                let end = Instant::now() + Duration::from_secs(4);
                while !marker.exists() && Instant::now() < end {
                    thread::sleep(Duration::from_millis(5));
                }
                if !marker.exists() {
                    return Err(io::Error::other("collector fault boundary not reached"));
                }
                if mode == 5 || mode == 6 {
                    thread::sleep(Duration::from_millis(30));
                    if collector.0.try_wait()?.is_some() {
                        return Err(io::Error::other("full-output collector was not waiting"));
                    }
                }
            }
            if mode != 6 {
                drop(input);
            }
            if wait_child(&mut collector.0)?.success() {
                return Err(io::Error::other("interrupted collector succeeded"));
            }
            if mode == 4 {
                std::fs::write(dir.join("one/stall.proceed"), b"proceed")?;
                let (kind, _) = read_frame(&mut holder_out)?;
                if kind != b'E' && kind != b'U' {
                    return Err(io::Error::other("stalled exporter reported success"));
                }
            }
        }
        holder.0.kill()?;
        holder.0.wait()?;
        let contender = OpenOptions::new().read(true).write(true).open(lock)?;
        locked(&contender)?;
        if let Some((ref mut child, _, _, ref path)) = second {
            child.0.kill()?;
            child.0.wait()?;
            let contender = OpenOptions::new().read(true).write(true).open(path)?;
            locked(&contender)?;
        }
        drop(held_reader);
        println!(
            "COLLECTOR_{}_CLEANED",
            match mode {
                1 => "PARTIAL_PARSE_OWNER_LOSS",
                2 => "CONNECT_OWNER_LOSS",
                3 => "PARTIAL_COLLECTION_OWNER_LOSS",
                4 => "STALLED_EXPORTER_OWNER_LOSS",
                5 => "FULL_OUTPUT_OWNER_LOSS",
                _ => "FULL_OUTPUT_DEADLINE",
            }
        );
        Ok(())
    }
    fn collector_fd_limit(root: &Path, helper: &Path) -> io::Result<()> {
        let mut holders = Vec::new();
        for index in 0..6usize {
            holders.push(open_helper(
                helper,
                &root.join(format!("limited-{index}")),
                true,
                false,
            )?);
        }
        let mut command = Command::new(helper);
        command
            .arg("--lease-collect-v1")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        unsafe {
            command.pre_exec(|| {
                let limit = Limit {
                    current: 16,
                    maximum: 16,
                };
                if setrlimit(7, &limit) != 0 {
                    return Err(io::Error::last_os_error());
                }
                Ok(())
            });
        }
        let mut collector = OwnedChild(command.spawn()?);
        let mut input = collector
            .0
            .stdin
            .take()
            .ok_or_else(|| io::Error::other("collector stdin missing"))?;
        let mut output = collector
            .0
            .stdout
            .take()
            .ok_or_else(|| io::Error::other("collector stdout missing"))?;
        let mut body = 10_000u64.to_be_bytes().to_vec();
        body.push(6);
        for (index, (child, stdin, _, path)) in holders.iter_mut().enumerate() {
            let meta = std::fs::metadata(path)?;
            let mut name = [131u8; 16];
            name[..4].copy_from_slice(&std::process::id().to_be_bytes());
            name[4] = index as u8;
            let mut secret = [132u8; 32];
            secret[0] = index as u8;
            let transfer = request(collector.0.id(), name, secret, meta.dev(), meta.ino());
            write_frame(stdin, b'X', 1, 1, &transfer[1..])?;
            let entry = request(child.0.id(), name, secret, meta.dev(), meta.ino());
            body.extend_from_slice(&entry[1..]);
        }
        input.write_all(b"I")?;
        input.write_all(&(body.len() as u32).to_be_bytes())?;
        input.write_all(&body)?;
        input.flush()?;
        let (first, _) = read_frame(&mut holders[0].2)?;
        if first != b'X' {
            return Err(io::Error::other(
                "resource exhaustion did not follow a successful transfer",
            ));
        }
        let (result, _) = read_frame(&mut output)?;
        if result != b'E' || wait_child(&mut collector.0)?.success() {
            return Err(io::Error::other("resource exhaustion did not refuse"));
        }
        let (uncertain, _) = read_frame(&mut holders[3].2)?;
        if uncertain != b'U' {
            return Err(io::Error::other(
                "unacknowledged fourth export was not unknown",
            ));
        }
        for (child, _, _, path) in &mut holders {
            child.0.kill()?;
            child.0.wait()?;
            let contender = OpenOptions::new().read(true).write(true).open(path)?;
            locked(&contender)?;
        }
        println!("COLLECTOR_LOW_FD_AFTER_TRANSFER_UNKNOWN_AND_CLEANED");
        Ok(())
    }
    fn test_pipe() -> io::Result<(File, File)> {
        let mut fds = [-1; 2];
        if unsafe { pipe2(fds.as_mut_ptr(), 0x800 | 0x80000) } != 0 {
            return Err(io::Error::last_os_error());
        }
        Ok((unsafe { File::from_raw_fd(fds[0]) }, unsafe {
            File::from_raw_fd(fds[1])
        }))
    }
    fn high_clone(file: &File) -> io::Result<File> {
        let fd = unsafe { fcntl(file.as_raw_fd(), 1030, 10) };
        if fd < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(unsafe { File::from_raw_fd(fd) })
    }
    fn output_case(root: &Path, helper: &Path, mode: u8) -> io::Result<()> {
        let dir = root.join(format!("output-{mode}"));
        DirBuilder::new().mode(0o700).create(&dir)?;
        let (mut holder, mut holder_in, mut holder_out, lock) =
            open_helper(helper, &dir.join("lease"), true, false)?;
        let (mut target_read, target_write) = test_pipe()?;
        if unsafe { fcntl(target_write.as_raw_fd(), 1031, 4096) } < 0 {
            return Err(io::Error::last_os_error());
        }
        let (owner_read, owner_write) = test_pipe()?;
        let mut owner_write = Some(owner_write);
        let target_meta = target_write.metadata()?;
        let owner_meta = owner_read.metadata()?;
        let target_child = high_clone(&target_write)?;
        let owner_child = high_clone(&owner_read)?;
        let target_fd = target_child.as_raw_fd();
        let owner_fd = owner_child.as_raw_fd();
        let mut command = Command::new(helper);
        command
            .arg("--lease-output-v1")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        if mode == 9 {
            command.env("IPSE_TEST_OUTPUT_RACE", dir.join("race"));
        }
        unsafe {
            command.pre_exec(move || {
                if dup2(target_fd, 3) < 0 || dup2(owner_fd, 4) < 0 {
                    return Err(io::Error::last_os_error());
                }
                Ok(())
            });
        }
        let mut child = OwnedChild(command.spawn()?);
        drop(target_child);
        drop(owner_child);
        drop(target_write);
        drop(owner_read);
        let mut input = child
            .0
            .stdin
            .take()
            .ok_or_else(|| io::Error::other("writer stdin missing"))?;
        let mut output = child
            .0
            .stdout
            .take()
            .ok_or_else(|| io::Error::other("writer stdout missing"))?;
        let meta = std::fs::metadata(&lock)?;
        let mut name = [143u8; 16];
        name[..4].copy_from_slice(&std::process::id().to_be_bytes());
        let secret = [144u8; 32];
        let transfer = request(child.0.id(), name, secret, meta.dev(), meta.ino());
        write_frame(&mut holder_in, b'X', 1, 1, &transfer[1..])?;
        let entry = request(holder.0.id(), name, secret, meta.dev(), meta.ino());
        let operation = [145u8; 16];
        let payload = if matches!(mode, 3 | 4 | 6) {
            vec![b'p'; 65_536]
        } else {
            b"protected payload".to_vec()
        };
        let mut body = (if mode == 6 { 250u64 } else { 10_000u64 })
            .to_be_bytes()
            .to_vec();
        body.extend_from_slice(&operation);
        body.push(1);
        for value in [
            target_meta.dev(),
            if mode == 7 {
                target_meta.ino() ^ 1
            } else {
                target_meta.ino()
            },
            owner_meta.dev(),
            if mode == 8 {
                owner_meta.ino() ^ 1
            } else {
                owner_meta.ino()
            },
        ] {
            body.extend_from_slice(&value.to_be_bytes());
        }
        body.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        body.extend_from_slice(&entry[1..]);
        body.extend_from_slice(&payload);
        input.write_all(b"I")?;
        input.write_all(&(body.len() as u32).to_be_bytes())?;
        input.write_all(&body)?;
        input.flush()?;
        let (kind, result) = read_frame(&mut output)?;
        if mode == 7 || mode == 8 {
            if kind != b'E' || wait_child(&mut child.0)?.success() {
                return Err(io::Error::other("wrong pipe identity accepted"));
            }
            let mut bytes = Vec::new();
            target_read.read_to_end(&mut bytes).or_else(|e| {
                if e.kind() == io::ErrorKind::WouldBlock {
                    Ok(bytes.len())
                } else {
                    Err(e)
                }
            })?;
            if !bytes.is_empty() {
                return Err(io::Error::other("identity refusal wrote bytes"));
            }
            holder.0.kill()?;
            holder.0.wait()?;
            let contender = OpenOptions::new().read(true).write(true).open(lock)?;
            locked(&contender)?;
            println!(
                "OUTPUT_WRONG_{}_IDENTITY_REFUSED",
                if mode == 7 { "DESTINATION" } else { "OWNER" }
            );
            return Ok(());
        }
        if kind != b'L' || result.len() != 20 || result[..16] != operation {
            return Err(io::Error::other("output collection refused"));
        }
        let (kind, _) = read_frame(&mut holder_out)?;
        if kind != b'X' {
            return Err(io::Error::other("output lease export refused"));
        }
        let mut probe = [0u8; 1];
        if !target_read
            .read(&mut probe)
            .is_err_and(|e| e.kind() == io::ErrorKind::WouldBlock)
        {
            return Err(io::Error::other("output preceded activation"));
        }
        if mode == 5 {
            holder.0.kill()?;
            holder.0.wait()?;
        }
        if mode == 2 {
            drop(owner_write.take());
        } else {
            let mut activation = vec![b'A'];
            activation.extend_from_slice(if mode == 1 { &[146u8; 16] } else { &operation });
            input.write_all(&activation)?;
            input.flush()?;
        }
        if mode == 9 {
            let ready = dir.join("race.ready");
            let end = Instant::now() + Duration::from_secs(4);
            while !ready.exists() && Instant::now() < end {
                thread::sleep(Duration::from_millis(5));
            }
            if !ready.exists() {
                return Err(io::Error::other("write race boundary not reached"));
            }
            drop(owner_write.take());
            std::fs::write(dir.join("race.proceed"), b"proceed")?;
        }
        if matches!(mode, 3 | 4 | 6) {
            let mut state = Poll {
                fd: target_read.as_raw_fd(),
                events: 1,
                revents: 0,
            };
            if unsafe { poll(&mut state, 1, 5000) } <= 0 || state.revents & 1 == 0 {
                return Err(io::Error::other("backpressure output did not start"));
            }
            if mode == 3 {
                drop(owner_write.take());
            } else if mode == 4 {
                drop(input);
            }
        }
        if mode == 0 {
            let mut received = vec![0; payload.len()];
            read_until(
                &mut target_read,
                &mut received,
                Instant::now() + Duration::from_secs(5),
            )?;
            let (kind, result) = read_frame(&mut output)?;
            if kind != b'D'
                || result[..16] != operation
                || u32::from_be_bytes(result[16..20].try_into().unwrap()) as usize != payload.len()
                || received != payload
            {
                return Err(io::Error::other("completed output mismatch"));
            }
            if !wait_child(&mut child.0)?.success() {
                return Err(io::Error::other("complete output failed"));
            }
        } else {
            let status = wait_child(&mut child.0)?;
            if status.success() {
                return Err(io::Error::other("interrupted output reported success"));
            }
            let mut received = Vec::new();
            target_read.read_to_end(&mut received).or_else(|e| {
                if e.kind() == io::ErrorKind::WouldBlock {
                    Ok(received.len())
                } else {
                    Err(e)
                }
            })?;
            if matches!(mode, 1 | 2 | 5) && !received.is_empty() {
                return Err(io::Error::other("refused output wrote bytes"));
            }
            if matches!(mode, 3 | 4 | 6)
                && (received.is_empty()
                    || received.len() >= payload.len()
                    || received != payload[..received.len()])
            {
                return Err(io::Error::other("partial output mismatch"));
            }
            if mode == 9 && received != payload {
                return Err(io::Error::other(
                    "owner-loss race did not write the observed chunk",
                ));
            }
            if mode == 3 || mode == 5 || mode == 9 {
                let (kind, result) = read_frame(&mut output)?;
                if kind != b'U'
                    || result[..16] != operation
                    || u32::from_be_bytes(result[16..20].try_into().unwrap()) as usize
                        != received.len()
                {
                    return Err(io::Error::other("partial output was not unknown"));
                }
            }
        }
        if mode != 5 {
            holder.0.kill()?;
            holder.0.wait()?;
        }
        let contender = OpenOptions::new().read(true).write(true).open(lock)?;
        locked(&contender)?;
        println!(
            "OUTPUT_{}_PASSED",
            match mode {
                0 => "COMPLETE_AFTER_ACTIVATION",
                1 => "WRONG_ACTIVATION_REFUSED",
                2 => "OWNER_LOSS_BEFORE_ACTIVATION_REFUSED",
                3 => "OWNER_LOSS_PARTIAL_UNKNOWN",
                4 => "HOST_LOSS_PARTIAL_UNKNOWN",
                5 => "EXPORTER_LOSS_BEFORE_OUTPUT_UNKNOWN",
                6 => "DEADLINE_PARTIAL_UNKNOWN",
                _ => "POST_CHECK_OWNER_LOSS_OBSERVED_UNKNOWN",
            }
        );
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
        if args.len() == 8 && args[1] == "--hold-export" {
            fn parse_hex<const N: usize>(text: &str) -> Result<[u8; N], String> {
                if text.len() != N * 2 {
                    return Err("invalid hex length".into());
                }
                let mut bytes = [0; N];
                for (index, byte) in bytes.iter_mut().enumerate() {
                    *byte = u8::from_str_radix(&text[index * 2..index * 2 + 2], 16)
                        .map_err(|e| e.to_string())?;
                }
                Ok(bytes)
            }
            let name = parse_hex::<16>(&args[2].to_string_lossy())?;
            let secret = parse_hex::<32>(&args[3].to_string_lossy())?;
            let helper_pid = args[4]
                .to_string_lossy()
                .parse::<u32>()
                .map_err(|e| e.to_string())?;
            let uid = args[5]
                .to_string_lossy()
                .parse::<u32>()
                .map_err(|e| e.to_string())?;
            let dev = args[6]
                .to_string_lossy()
                .parse::<u64>()
                .map_err(|e| e.to_string())?;
            let ino = args[7]
                .to_string_lossy()
                .parse::<u64>()
                .map_err(|e| e.to_string())?;
            let (lease, socket) =
                peer(name, secret, true, helper_pid, uid, dev, ino).map_err(|e| e.to_string())?;
            println!("HELD");
            io::stdout().flush().map_err(|e| e.to_string())?;
            let mut stop = [0];
            let _ = io::stdin().read(&mut stop);
            drop(lease);
            drop(socket);
            println!("CLOSED");
            return Ok(());
        }
        if args.len() == 2 && args[1] == "--frame-controls" {
            return frame_controls().map_err(|e| e.to_string());
        }
        if (args.len() == 4 || args.len() == 5) && args[1] == "--collector-controls" {
            let selected = if args.len() == 5 {
                Some(
                    args[4]
                        .to_string_lossy()
                        .parse::<u8>()
                        .map_err(|e| e.to_string())?,
                )
            } else {
                None
            };
            for mode in 0..=5 {
                if selected.is_some_and(|value| value != mode) {
                    continue;
                }
                collector_case(Path::new(&args[2]), Path::new(&args[3]), mode)
                    .map_err(|e| format!("collector case {mode}: {e}"))?;
            }
            return Ok(());
        }
        if args.len() == 4 && args[1] == "--collector-capacity" {
            return collector_capacity(Path::new(&args[2]), Path::new(&args[3]))
                .map_err(|e| e.to_string());
        }
        if args.len() == 4 && args[1] == "--collector-nested" {
            return collector_nested(Path::new(&args[2]), Path::new(&args[3]))
                .map_err(|e| e.to_string());
        }
        if args.len() == 5 && args[1] == "--retained-close" {
            let mode = args[4].to_str().ok_or("invalid retained close mode")?;
            if !matches!(mode, "normal" | "wrong" | "wrong-slot" | "lost" | "exporter-lost") { return Err("invalid retained close mode".into()); }
            return retained_close(Path::new(&args[2]), Path::new(&args[3]), mode).map_err(|e| e.to_string());
        }
        if args.len() == 4 && args[1] == "--retained-repeat" {
            return retained_repeat(Path::new(&args[2]), Path::new(&args[3])).map_err(|e| e.to_string());
        }
        if (args.len() == 4 || args.len() == 5) && args[1] == "--leased-output" {
            let selected = if args.len() == 5 {
                Some(
                    args[4]
                        .to_string_lossy()
                        .parse::<u8>()
                        .map_err(|e| e.to_string())?,
                )
            } else {
                None
            };
            for mode in 0..=9 {
                if selected.is_none() && mode == 9 {
                    continue;
                }
                if selected.is_some_and(|value| value != mode) {
                    continue;
                }
                output_case(Path::new(&args[2]), Path::new(&args[3]), mode)
                    .map_err(|e| format!("output case {mode}: {e}"))?;
            }
            return Ok(());
        }
        if (args.len() == 4 || args.len() == 5) && args[1] == "--collector-faults" {
            let selected = if args.len() == 5 {
                Some(
                    args[4]
                        .to_string_lossy()
                        .parse::<u8>()
                        .map_err(|e| e.to_string())?,
                )
            } else {
                None
            };
            for mode in 1..=6 {
                if selected.is_some_and(|value| value != mode) {
                    continue;
                }
                collector_fault(Path::new(&args[2]), Path::new(&args[3]), mode)
                    .map_err(|e| format!("collector fault {mode}: {e}"))?;
            }
            if selected.is_none() || selected == Some(7) {
                collector_fd_limit(Path::new(&args[2]), Path::new(&args[3]))
                    .map_err(|e| e.to_string())?;
            }
            return Ok(());
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
