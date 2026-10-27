//! Private final-publication lock owner. Policy and JSON remain in the host.
#[cfg(any(target_os = "linux", target_os = "macos"))]
mod unix {
    use std::ffi::CString;
    use std::fs::{File, Metadata};
    use std::io::{self, Read, Seek, SeekFrom, Write};
    use std::os::unix::fs::MetadataExt;
    use std::os::unix::io::{AsRawFd, FromRawFd};
    use std::path::{Component, Path, PathBuf};
    use std::time::{Duration, Instant};

    #[repr(C)] struct Poll { fd: i32, events: i16, revents: i16 }
    #[cfg(target_os = "macos")] type PollCount = u32;
    #[cfg(target_os = "linux")] type PollCount = usize;
    extern "C" {
        fn open(path: *const i8, flags: i32, ...) -> i32;
        fn openat(fd: i32, path: *const i8, flags: i32, ...) -> i32;
        fn renameat(from: i32, name: *const i8, to: i32, target: *const i8) -> i32;
        fn unlinkat(fd: i32, name: *const i8, flags: i32) -> i32;
        fn flock(fd: i32, operation: i32) -> i32;
        fn geteuid() -> u32;
        fn fcntl(fd: i32, command: i32, ...) -> i32;
        fn poll(fds: *mut Poll, count: PollCount, timeout: i32) -> i32;
        fn read(fd: i32, bytes: *mut std::ffi::c_void, count: usize) -> isize;
    }
    #[cfg(target_os = "linux")]
    extern "C" { fn renameat2(from: i32, name: *const i8, to: i32, target: *const i8, flags: u32) -> i32; }
    #[cfg(target_os = "macos")]
    extern "C" { fn renameatx_np(from: i32, name: *const i8, to: i32, target: *const i8, flags: u32) -> i32; }
    #[cfg(target_os = "linux")]
    const FLAGS: i32 = 0x20000 | 0x800 | 0x80000;
    #[cfg(target_os = "macos")]
    const FLAGS: i32 = 0x100 | 0x4 | 0x1000000;
    #[cfg(target_os = "linux")] const DIRECTORY: i32 = 0x10000;
    #[cfg(target_os = "macos")] const DIRECTORY: i32 = 0x100000;
    #[cfg(target_os = "linux")] const CREATE: i32 = 0x40;
    #[cfg(target_os = "macos")] const CREATE: i32 = 0x200;
    #[cfg(target_os = "linux")] const EXCLUSIVE: i32 = 0x80;
    #[cfg(target_os = "macos")] const EXCLUSIVE: i32 = 0x800;
    #[cfg(target_os = "linux")] const NONBLOCK: i32 = 0x800;
    #[cfg(target_os = "macos")] const NONBLOCK: i32 = 0x4;
    const MAX_FILE: u64 = 8 * 1024 * 1024;
    const BUSY: u8 = 1;
    const UNSAFE: u8 = 2;
    const INVALID: u8 = 3;
    const IO: u8 = 4;

    #[derive(Clone, Copy)] struct Budget { mode: u8, ceiling: u64 }
    struct Held { path: PathBuf, parent: File, lock: File, parent_id: Metadata, lock_id: Metadata, budget: Option<Budget> }
    fn same(a: &Metadata, b: &Metadata) -> bool { a.dev() == b.dev() && a.ino() == b.ino() }
    fn private_dir(m: &Metadata, uid: u32) -> bool {
        m.is_dir() && m.uid() == uid && m.mode() & 0o7777 == 0o700
    }
    fn private_file(m: &Metadata, uid: u32) -> bool {
        m.is_file() && m.uid() == uid && m.nlink() == 1 && m.mode() & 0o7777 == 0o600 && m.len() <= MAX_FILE
    }
    fn c(text: &str) -> Result<CString, u8> { CString::new(text).map_err(|_| INVALID) }
    fn relative(parent: &File, name: &str, flags: i32) -> Result<File, u8> {
        relative_optional(parent, name, flags, false)?.ok_or(IO)
    }
    fn relative_optional(parent: &File, name: &str, flags: i32, optional: bool) -> Result<Option<File>, u8> {
        let name = c(name)?;
        let fd = unsafe { openat(parent.as_raw_fd(), name.as_ptr(), flags | FLAGS, 0o600_u32) };
        if fd < 0 {
            let error = io::Error::last_os_error().raw_os_error();
            if optional && error == Some(2) { Ok(None) } else { Err(IO) }
        } else { Ok(Some(unsafe { File::from_raw_fd(fd) })) }
    }
    // Each component is opened relative to its retained predecessor. Lexical
    // normalization never erases a symlink or an outward traversal.
    fn parent(path: &Path, uid: u32) -> Result<File, u8> {
        let text = path.to_str().ok_or(INVALID)?;
        if text.len() > 4096 || !path.is_absolute() || text == "/" || text.ends_with('/') ||
            text.as_bytes().iter().any(|b| *b < 32 || *b == 127) { return Err(INVALID); }
        if text.split('/').skip(1).any(|part| part.is_empty() || part == "." || part == "..") { return Err(INVALID); }
        let slash = c("/")?;
        let fd = unsafe { open(slash.as_ptr(), FLAGS | DIRECTORY) };
        if fd < 0 { return Err(IO); }
        let mut current = unsafe { File::from_raw_fd(fd) };
        let root_uid = current.metadata().map_err(|_| IO)?.uid();
        let parts: Vec<_> = path.components().filter_map(|p| match p { Component::Normal(s) => s.to_str(), _ => None }).collect();
        if parts.len() > 128 { return Err(INVALID); }
        for (index, part) in parts.iter().enumerate() {
            current = relative(&current, part, DIRECTORY)?;
            let m = current.metadata().map_err(|_| IO)?;
            let trusted = m.uid() == uid || m.uid() == 0 || m.uid() == root_uid;
            let sticky = m.mode() & 0o1000 != 0 && (m.uid() == 0 || m.uid() == root_uid);
            if !m.is_dir() || !trusted || (m.mode() & 0o022 != 0 && !sticky) { return Err(UNSAFE); }
            if index + 1 == parts.len() && !private_dir(&m, uid) { return Err(UNSAFE); }
        }
        Ok(current)
    }
    fn acquire(path: &str, uid: u32, stack: &[Held]) -> Result<Held, u8> {
        let path = Path::new(path);
        if path.file_name().and_then(|s| s.to_str()) != Some(".lock") { return Err(INVALID); }
        let parent_path = path.parent().ok_or(INVALID)?;
        let directory = parent(parent_path, uid)?;
        let parent_id = directory.metadata().map_err(|_| IO)?;
        let lock = relative(&directory, ".lock", 2 | CREATE)?;
        let lock_id = lock.metadata().map_err(|_| IO)?;
        if !private_file(&lock_id, uid) || lock_id.len() != 0 { return Err(UNSAFE); }
        if stack.iter().any(|held| same(&held.lock_id, &lock_id)) { return Err(INVALID); }
        if unsafe { flock(lock.as_raw_fd(), 2 | 4) } != 0 { return Err(BUSY); }
        let held = Held { path: path.to_path_buf(), parent: directory, lock, parent_id, lock_id, budget: None };
        if !valid(&held, uid) { return Err(UNSAFE); }
        Ok(held)
    }
    fn valid(held: &Held, uid: u32) -> bool {
        let result = (|| {
            let named_parent = parent(held.path.parent().ok_or(INVALID)?, uid)?;
            let named_lock = relative(&named_parent, ".lock", 0)?;
            let pm = named_parent.metadata().map_err(|_| IO)?;
            let lm = named_lock.metadata().map_err(|_| IO)?;
            let retained_p = held.parent.metadata().map_err(|_| IO)?;
            let retained_l = held.lock.metadata().map_err(|_| IO)?;
            Ok::<_, u8>(same(&pm, &held.parent_id) && same(&retained_p, &pm) && private_dir(&pm, uid) &&
                same(&lm, &held.lock_id) && same(&retained_l, &lm) && private_file(&lm, uid) && lm.len() == 0)
        })();
        result.unwrap_or(false)
    }
    fn target_name(name: &str) -> bool { matches!(name, "index.json" | "control.json" | "root.json") }
    fn stage_name(name: &str) -> bool {
        name.len() == 41 && name.starts_with(".pending-") && name.as_bytes()[9..].iter().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(b))
    }
    fn immutable_name(name: &str) -> bool {
        name.len() == 69 && name.ends_with(".json") && name.as_bytes()[..64].iter().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(b))
    }
    fn child(held: &Held, selector: u8, uid: u32) -> Result<File, u8> {
        if held.budget.is_some_and(|budget| budget.mode == 0 && selector != 0) { return Err(INVALID); }
        let directory = match selector {
            0 => held.parent.try_clone().map_err(|_| IO)?,
            1 => relative(&held.parent, "objects", DIRECTORY)?,
            2 => relative(&held.parent, "manifests", DIRECTORY)?,
            _ => return Err(INVALID),
        };
        if !private_dir(&directory.metadata().map_err(|_| IO)?, uid) { return Err(UNSAFE); }
        Ok(directory)
    }
    // The retained lock owner is also the only process that opens data files.
    // Every response follows closing all data FDs. A killed/blocked owner cannot
    // release its flock while a separate host IO process retains an unlinked FD.
    fn read_chunk(held: &Held, bytes: &[u8], uid: u32, optional: bool) -> Result<Option<Vec<u8>>, u8> {
        if bytes.len() < 10 { return Err(INVALID); }
        let selector = bytes[0]; let length = bytes[1] as usize;
        if bytes.len() != 10 + length { return Err(INVALID); }
        let name = std::str::from_utf8(&bytes[2..2 + length]).map_err(|_| INVALID)?;
        if !target_name(name) && !immutable_name(name) { return Err(INVALID); }
        let offset = u32::from_be_bytes(bytes[2 + length..6 + length].try_into().unwrap()) as u64;
        let maximum = u32::from_be_bytes(bytes[6 + length..10 + length].try_into().unwrap()) as u64;
        if maximum == 0 || maximum > MAX_FILE { return Err(INVALID); }
        let directory = child(held, selector, uid)?;
        let mut file = match relative_optional(&directory, name, 0, optional)? {
            Some(file) => file,
            None => {
                if offset != 0 || !directory_valid(held, &directory, selector, uid) { return Err(UNSAFE); }
                drop(directory);
                return Ok(None);
            },
        };
        let before = file.metadata().map_err(|_| IO)?;
        if !private_file(&before, uid) || before.len() > maximum || offset > before.len() { return Err(UNSAFE); }
        let size = (before.len() - offset).min(16_384) as usize;
        let mut content = vec![0_u8; size];
        file.seek(SeekFrom::Start(offset)).map_err(|_| IO)?;
        file.read_exact(&mut content).map_err(|_| IO)?;
        let after = file.metadata().map_err(|_| IO)?;
        let named = relative(&directory, name, 0)?;
        let named_id = named.metadata().map_err(|_| IO)?;
        if !private_file(&after, uid) || !private_file(&named_id, uid) ||
            !same(&before, &after) || !same(&after, &named_id) ||
            before.len() != after.len() || before.len() != named_id.len() ||
            !directory_valid(held, &directory, selector, uid) { return Err(UNSAFE); }
        let mut result = (before.len() as u32).to_be_bytes().to_vec();
        result.extend_from_slice(&(offset as u32).to_be_bytes());
        result.extend_from_slice(&before.dev().to_be_bytes());
        result.extend_from_slice(&before.ino().to_be_bytes());
        result.extend_from_slice(&content);
        drop(named); drop(file); drop(directory);
        Ok(Some(result))
    }
    fn writer(directory: &File, uid: u32) -> Result<File, u8> {
        let lock = relative(directory, ".writer.lock", 2 | CREATE)?;
        let m = lock.metadata().map_err(|_| IO)?;
        if !private_file(&m, uid) || m.len() != 0 { return Err(UNSAFE); }
        if unsafe { flock(lock.as_raw_fd(), 2 | 4) } != 0 { return Err(BUSY); }
        let named = relative(directory, ".writer.lock", 0)?;
        if !same(&m, &named.metadata().map_err(|_| IO)?) { return Err(UNSAFE); }
        Ok(lock)
    }
    fn directory_valid(held: &Held, directory: &File, selector: u8, uid: u32) -> bool {
        valid(held, uid) && child(held, selector, uid).and_then(|named| {
            Ok(same(&directory.metadata().map_err(|_| IO)?, &named.metadata().map_err(|_| IO)?))
        }).unwrap_or(false)
    }
    fn scope_writers(held: &Held, mode: Option<u8>, selected: u8, uid: u32) -> Result<(Vec<(u8, File)>, Vec<File>), u8> {
        let selectors = match mode {
            Some(0) if selected == 0 => vec![0],
            Some(1) => vec![0,1,2],
            None => vec![selected],
            _ => return Err(INVALID),
        };
        let mut directories = Vec::new(); let mut leases = Vec::new();
        for selector in selectors {
            let d = child(held, selector, uid)?; leases.push(writer(&d, uid)?); directories.push((selector,d));
        }
        Ok((directories,leases))
    }
    fn scope_valid(held: &Held, directories: &[(u8, File)], uid: u32) -> bool {
        directories.iter().all(|(selector,d)| directory_valid(held,d,*selector,uid))
    }
    fn flat(held: &Held) -> Result<(),u8> {
        let mut count = 0usize;
        for entry in std::fs::read_dir(held.path.parent().ok_or(INVALID)?).map_err(|_| IO)? {
            count += 1; if count > 40_000 { return Err(INVALID); }
            if entry.map_err(|_| IO)?.file_type().map_err(|_| IO)?.is_dir() { return Err(UNSAFE); }
        }
        Ok(())
    }
    fn allowance(held: &Held, budget: Budget, sizes: &[u64]) -> Result<(),u8> {
        if budget.mode == 0 { flat(held)?; }
        super::super::ipse_storage::transaction_preflight(held.path.parent().ok_or(INVALID)?, sizes, budget.ceiling)
            .map_err(|error| match error {
                super::super::ipse_storage::TransactionAllowanceError::Unsupported => 7,
                super::super::ipse_storage::TransactionAllowanceError::Capacity => 6,
                super::super::ipse_storage::TransactionAllowanceError::Unsafe => UNSAFE,
            })
    }
    fn names(bytes: &[u8], count: usize) -> Result<Vec<String>, u8> {
        let mut result = Vec::new(); let mut at = 0;
        for _ in 0..count {
            let size = *bytes.get(at).ok_or(INVALID)? as usize; at += 1;
            let name = std::str::from_utf8(bytes.get(at..at + size).ok_or(INVALID)?).map_err(|_| INVALID)?.to_owned();
            if !stage_name(&name) && !immutable_name(&name) { return Err(INVALID); }
            if result.contains(&name) { return Err(INVALID); }
            result.push(name); at += size;
        }
        if at != bytes.len() { return Err(INVALID); } Ok(result)
    }
    fn reclaim(held: &Held, bytes: &[u8], uid: u32) -> Result<(), (bool, u8)> {
        let prepare = (|| {
            if bytes.len() < 2 || !(1..=64).contains(&bytes[1]) { return Err(INVALID); }
            let selector = bytes[0];
            let names = names(&bytes[2..], bytes[1] as usize)?;
            let directory = child(held, selector, uid)?; let lease = writer(&directory, uid)?;
            let mut retained = Vec::new();
            for name in &names {
                let file = relative(&directory, name, 2)?;
                if !private_file(&file.metadata().map_err(|_| IO)?, uid) { return Err(UNSAFE); }
                file.sync_all().map_err(|_| IO)?;
                retained.push(file);
            }
            if !directory_valid(held, &directory, selector, uid) { return Err(UNSAFE); }
            Ok((selector, directory, lease, names, retained))
        })().map_err(|code| (false, code))?;
        for (name, file) in prepare.3.iter().zip(prepare.4.iter()) {
            let named = relative(&prepare.1, name, 0).map_err(|code| (true, code))?;
            if !same(&file.metadata().map_err(|_| (true, IO))?, &named.metadata().map_err(|_| (true, IO))?) { return Err((true, UNSAFE)); }
            let name = c(name).map_err(|code| (true, code))?;
            if unsafe { unlinkat(prepare.1.as_raw_fd(), name.as_ptr(), 0) } != 0 { return Err((true, IO)); }
        }
        prepare.1.sync_all().map_err(|_| (true, IO))?;
        // Drop unlisted file descriptors before acknowledging reclamation;
        // otherwise the next namespace inventory would miss their allocation.
        drop(prepare.4);
        if !directory_valid(held, &prepare.1, prepare.0, uid) { return Err((true, UNSAFE)); }
        Ok(())
    }
    fn install(held: &Held, bytes: &[u8], uid: u32) -> Result<(), (bool, u8)> {
        let prepare = (|| {
            if bytes.len() != 111 { return Err(INVALID); }
            let selector = bytes[0];
            let stage = std::str::from_utf8(&bytes[1..42]).map_err(|_| INVALID)?;
            let target = std::str::from_utf8(&bytes[42..]).map_err(|_| INVALID)?;
            if !stage_name(stage) || !immutable_name(target) { return Err(INVALID); }
            let directory = child(held, selector, uid)?; let lease = writer(&directory, uid)?;
            let file = relative(&directory, stage, 0)?;
            let before = file.metadata().map_err(|_| IO)?;
            if !private_file(&before, uid) { return Err(UNSAFE); }
            file.sync_all().map_err(|_| IO)?;
            let named = relative(&directory, stage, 0)?;
            let after = named.metadata().map_err(|_| IO)?;
            if !same(&before, &after) || !private_file(&after, uid) || before.len() != after.len() { return Err(UNSAFE); }
            if !directory_valid(held, &directory, selector, uid) { return Err(UNSAFE); }
            Ok((selector, directory, lease, c(stage)?, c(target)?))
        })().map_err(|code| (false, code))?;
        #[cfg(target_os = "linux")]
        let result = unsafe { renameat2(prepare.1.as_raw_fd(), prepare.3.as_ptr(), prepare.1.as_raw_fd(), prepare.4.as_ptr(), 1) };
        #[cfg(target_os = "macos")]
        let result = unsafe { renameatx_np(prepare.1.as_raw_fd(), prepare.3.as_ptr(), prepare.1.as_raw_fd(), prepare.4.as_ptr(), 4) };
        if result != 0 {
            if io::Error::last_os_error().raw_os_error() == Some(17) { return Err((false, 5)); }
            return Err((true, IO));
        }
        prepare.1.sync_all().map_err(|_| (true, IO))?;
        if !directory_valid(held, &prepare.1, prepare.0, uid) { return Err((true, UNSAFE)); } Ok(())
    }
    struct Stage {
        selector: u8, directory: File, directories: Vec<(u8,File)>, _writers: Vec<File>, entries: Vec<(String, usize)>,
        index: usize, written: usize, file: Option<File>, remaining: usize,
    }
    fn absent(directory: &File, name: &str) -> Result<(), u8> {
        let name = c(name)?;
        let fd = unsafe { openat(directory.as_raw_fd(), name.as_ptr(), FLAGS, 0o600_u32) };
        if fd >= 0 { drop(unsafe { File::from_raw_fd(fd) }); return Err(UNSAFE); }
        if io::Error::last_os_error().raw_os_error() != Some(2) { return Err(UNSAFE); } Ok(())
    }
    fn stage(held: &Held, bytes: &[u8], uid: u32) -> Result<Stage, u8> {
        if bytes.len() < 2 || !(1..=128).contains(&bytes[1]) { return Err(INVALID); }
        let selector = bytes[0]; let count = bytes[1] as usize;
        if bytes.len() != 2 + count * 45 { return Err(INVALID); }
        let directory = child(held, selector, uid)?;
        let (directories,leases) = scope_writers(held,held.budget.map(|b|b.mode),selector,uid)?;
        let mut entries = Vec::new(); let mut total = 0usize;
        for record in bytes[2..].chunks_exact(45) {
            let name = std::str::from_utf8(&record[..41]).map_err(|_| INVALID)?.to_owned();
            let size = u32::from_be_bytes(record[41..].try_into().unwrap()) as usize;
            if !stage_name(&name) || size == 0 || entries.iter().any(|(n, _)| n == &name) { return Err(INVALID); }
            total = total.checked_add(size).ok_or(INVALID)?;
            if total > MAX_FILE as usize { return Err(INVALID); }
            absent(&directory, &name)?; entries.push((name, size));
        }
        if let Some(budget) = held.budget { allowance(held,budget,&entries.iter().map(|(_,size)|*size as u64).collect::<Vec<_>>())?; }
        if !scope_valid(held,&directories,uid) || !directory_valid(held, &directory, selector, uid) { return Err(UNSAFE); }
        Ok(Stage { selector, directory, directories, _writers: leases, entries, index: 0, written: 0, file: None, remaining: total })
    }
    // PRIVATE TEST-ONLY: fixed synthetic pending file, one controller socket.
    fn fixture_barrier(name: &str, remaining: usize, count: usize) -> Result<Option<std::os::unix::net::UnixStream>, u8> {
        if name != ".pending-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" || remaining != count { return Ok(None); }
        let mut peer = std::os::unix::net::UnixStream::connect("/tmp/ipse-stage-gate-review/control.sock").map_err(|_| IO)?;
        peer.set_read_timeout(Some(Duration::from_secs(10))).map_err(|_| IO)?;
        peer.set_write_timeout(Some(Duration::from_secs(10))).map_err(|_| IO)?;
        peer.write_all(b"R").map_err(|_| IO)?;
        let mut gate = [0_u8; 1]; peer.read_exact(&mut gate).map_err(|_| IO)?;
        if gate != *b"G" { return Err(IO); }
        Ok(Some(peer))
    }
    fn fixture_report(peer: &mut Option<std::os::unix::net::UnixStream>, phase: u8, result: &io::Result<()>) -> Result<(), u8> {
        if let Some(peer) = peer.as_mut() {
            let errno = match result { Ok(()) => 0_i32, Err(error) => error.raw_os_error().unwrap_or(-1) };
            peer.write_all(&[phase]).map_err(|_| IO)?;
            peer.write_all(&errno.to_be_bytes()).map_err(|_| IO)?;
        }
        Ok(())
    }

    fn stage_data(stage: &mut Stage, held: &Held, bytes: &[u8], uid: u32) -> Result<(), u8> {
        if bytes.is_empty() || bytes.len() > 16_384 || bytes.len() > stage.remaining { return Err(INVALID); }
        if !scope_valid(held,&stage.directories,uid) || !directory_valid(held, &stage.directory, stage.selector, uid) { return Err(UNSAFE); }
        let mut bytes = bytes;
        while !bytes.is_empty() {
            let (name, size) = &stage.entries[stage.index];
            if stage.file.is_none() {
                let file = relative(&stage.directory, name, 1 | CREATE | EXCLUSIVE)?;
                if !private_file(&file.metadata().map_err(|_| IO)?, uid) { return Err(UNSAFE); }
                stage.file = Some(file);
            }
            let count = bytes.len().min(size - stage.written);
            let mut fixture_peer = fixture_barrier(name, stage.remaining, count)?;
            let written = stage.file.as_mut().unwrap().write_all(&bytes[..count]);
            fixture_report(&mut fixture_peer, b'W', &written)?;
            written.map_err(|_| IO)?;
            stage.written += count; stage.remaining -= count; bytes = &bytes[count..];
            if stage.written == *size {
                let file = stage.file.take().unwrap();
                let synced = file.sync_all(); fixture_report(&mut fixture_peer, b'S', &synced)?;
                synced.map_err(|_| IO)?;
                let named = relative(&stage.directory, name, 0)?;
                let m = named.metadata().map_err(|_| IO)?;
                if !same(&file.metadata().map_err(|_| IO)?, &m) || !private_file(&m, uid) || m.len() != *size as u64 { return Err(UNSAFE); }
                stage.index += 1; stage.written = 0;
            }
        }
        if stage.remaining == 0 { stage.directory.sync_all().map_err(|_| IO)?; }
        if !scope_valid(held,&stage.directories,uid) || !directory_valid(held, &stage.directory, stage.selector, uid) { return Err(UNSAFE); } Ok(())
    }
    // Err(false, ...) proves no rename was attempted; Err(true, ...) is unknown.
    fn switch(held: &Held, stage: &str, target: &str, uid: u32) -> Result<(), (bool, u8)> {
        let _writer = writer(&held.parent, uid).map_err(|code| (false, code))?;
        let prepare = (|| {
            if !stage_name(stage) || !target_name(target) { return Err(INVALID); }
            let file = relative(&held.parent, stage, 0)?;
            let metadata = file.metadata().map_err(|_| IO)?;
            if !private_file(&metadata, uid) { return Err(UNSAFE); }
            match relative(&held.parent, target, 0) {
                Ok(existing) => if !private_file(&existing.metadata().map_err(|_| IO)?, uid) { return Err(UNSAFE); },
                Err(_) => {
                    // Only ENOENT is admissible. Symlinks, FIFOs and access errors
                    // must not be mistaken for an absent target.
                    let name = c(target)?;
                    let fd = unsafe { openat(held.parent.as_raw_fd(), name.as_ptr(), FLAGS, 0o600_u32) };
                    if fd >= 0 { drop(unsafe { File::from_raw_fd(fd) }); return Err(UNSAFE); }
                    if io::Error::last_os_error().raw_os_error() != Some(2) { return Err(UNSAFE); }
                }
            }
            file.sync_all().map_err(|_| IO)?;
            let named = relative(&held.parent, stage, 0)?;
            let after = named.metadata().map_err(|_| IO)?;
            if !same(&metadata, &after) || !private_file(&after, uid) || metadata.len() != after.len() { return Err(UNSAFE); }
            Ok((c(stage)?, c(target)?))
        })().map_err(|code| (false, code))?;
        if unsafe { renameat(held.parent.as_raw_fd(), prepare.0.as_ptr(), held.parent.as_raw_fd(), prepare.1.as_ptr()) } != 0 {
            return Err((true, IO));
        }
        held.parent.sync_all().map_err(|_| (true, IO))?;
        if !valid(held, uid) { return Err((true, UNSAFE)); }
        Ok(())
    }
    fn nonblocking(fd: i32) -> Result<(), String> {
        let flags = unsafe { fcntl(fd, 3) };
        if flags < 0 || unsafe { fcntl(fd, 4, flags | NONBLOCK) } < 0 { return Err("transaction pipe unavailable".into()); }
        Ok(())
    }
    fn ready(deadline: Instant) -> Result<bool, String> {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() { return Err("transaction deadline".into()); }
        let mut p = Poll { fd: 0, events: 1, revents: 0 };
        let rc = unsafe { poll(&mut p, 1, remaining.as_millis().min(5000) as i32) };
        if rc < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted { return ready(deadline); }
        if rc < 0 { return Err("transaction pipe unavailable".into()); }
        // HUP/ERR/NVAL win over any already queued request.
        if p.revents & (8 | 16 | 32) != 0 { return Ok(false); }
        Ok(rc != 0)
    }
    fn request(deadline: Instant) -> Result<Option<(u8, Vec<u8>)>, String> {
        let mut bytes = Vec::with_capacity(8197);
        let mut end = deadline;
        loop {
            if !ready(end)? {
                if Instant::now() >= end { return Err("transaction deadline".into()); }
                // A pipe HUP cannot recover; distinguish timeout by a zero poll.
                let mut p = Poll { fd: 0, events: 1, revents: 0 };
                unsafe { poll(&mut p, 1, 0); }
                if p.revents & (8 | 16 | 32) != 0 { return Ok(None); }
                continue;
            }
            let need = if bytes.len() < 5 { 5 - bytes.len() } else {
                let size = u32::from_be_bytes(bytes[1..5].try_into().unwrap()) as usize;
                if size > 16393 || (bytes[0] != b'D' && size > 8192) { return Err("transaction frame limit".into()); }
                5 + size - bytes.len()
            };
            if need == 0 { return Ok(Some((bytes[0], bytes[5..].to_vec()))); }
            let mut chunk = [0_u8; 8192];
            let count = unsafe { read(0, chunk.as_mut_ptr().cast(), need.min(8192)) };
            let result = if count < 0 { Err(io::Error::last_os_error()) } else { Ok(count as usize) };
            match result {
                Ok(0) => return Ok(None),
                Ok(n) => { if bytes.is_empty() { end = deadline.min(Instant::now() + Duration::from_secs(5)); } bytes.extend_from_slice(&chunk[..n]); },
                Err(e) if matches!(e.kind(), io::ErrorKind::Interrupted | io::ErrorKind::WouldBlock) => continue,
                Err(_) => return Err("transaction input unavailable".into()),
            }
            if bytes.len() >= 5 {
                let size = u32::from_be_bytes(bytes[1..5].try_into().unwrap()) as usize;
                if size > 16393 || (bytes[0] != b'D' && size > 8192) { return Err("transaction frame limit".into()); }
                if bytes.len() == size + 5 { return Ok(Some((bytes[0], bytes[5..].to_vec()))); }
            }
        }
    }
    fn reply(kind: u8, seq: u64, depth: usize, code: Option<u8>) -> Result<(), String> {
        let mut bytes = seq.to_be_bytes().to_vec(); bytes.push(depth as u8);
        if let Some(code) = code { bytes.push(code); }
        super::super::frame(kind, &bytes).map_err(|_| "transaction output unavailable".into())
    }
    pub fn run(args: &[String]) -> Result<(), String> {
        if args.len() != 3 { return Err("invalid transaction arguments".into()); }
        let milliseconds: u64 = args[2].parse().ok().filter(|n| (1..=120_000).contains(n)).ok_or("invalid transaction deadline")?;
        let deadline = Instant::now() + Duration::from_millis(milliseconds);
        nonblocking(0)?; nonblocking(1)?;
        let uid = unsafe { geteuid() };
        let mut stack: Vec<Held> = Vec::new();
        let mut previous = 0_u64;
        let mut staging: Option<Stage> = None;
        macro_rules! answer {
            ($kind:expr, $seq:expr, $code:expr) => {{
                if !stack.iter().all(|held| valid(held, uid)) {
                    reply(b'U', $seq, stack.len(), Some(UNSAFE))?;
                    return Ok(());
                }
                reply($kind, $seq, stack.len(), $code)?;
            }};
        }
        while let Some((kind, bytes)) = request(deadline)? {
            if bytes.len() < 9 { return Err("invalid transaction command".into()); }
            let seq = u64::from_be_bytes(bytes[..8].try_into().unwrap());
            let depth = bytes[8] as usize;
            if seq != previous + 1 || depth != stack.len() { return Err("invalid transaction sequence".into()); }
            previous = seq;
            if !stack.iter().all(|h| valid(h, uid)) {
                reply(b'U', seq, stack.len(), Some(UNSAFE))?; return Ok(());
            }
            if staging.is_some() && kind != b'D' { return Err("transaction staging interrupted".into()); }
            match kind {
                b'A' => {
                    let result = if stack.len() >= 3 { Err(INVALID) } else {
                        std::str::from_utf8(&bytes[9..]).map_err(|_| INVALID).and_then(|path| acquire(path, uid, &stack))
                    };
                    match result {
                        Ok(held) => { stack.push(held); answer!(b'A', seq, None); },
                        Err(code) => answer!(b'E', seq, Some(code)),
                    }
                }
                b'P' if bytes.len() == 9 && !stack.is_empty() => answer!(b'P', seq, None),
                b'G' | b'H' if !stack.is_empty() => {
                    let optional = kind == b'H';
                    let data = if optional {
                        if bytes.get(9) != Some(&1) { answer!(b'E', seq, Some(INVALID)); continue; }
                        &bytes[10..]
                    } else { &bytes[9..] };
                    match read_chunk(stack.last().unwrap(), data, uid, optional) {
                        Ok(data) => {
                            if !stack.iter().all(|h| valid(h, uid)) { reply(b'U', seq, stack.len(), Some(UNSAFE))?; return Ok(()); }
                            let mut payload = seq.to_be_bytes().to_vec(); payload.push(stack.len() as u8);
                            if optional { payload.extend_from_slice(&[1, u8::from(data.is_some())]); }
                            match data {
                                Some(data) => payload.extend_from_slice(&data),
                                None if optional => {},
                                None => return Err("transaction read unavailable".into()),
                            }
                            super::super::frame(kind, &payload).map_err(|_| "transaction output unavailable")?;
                        },
                        Err(code) => answer!(b'E', seq, Some(code)),
                    }
                }
                b'R' if bytes.len() == 9 && !stack.is_empty() => {
                    stack.pop(); answer!(b'R', seq, None);
                    if stack.is_empty() { return Ok(()); }
                }
                b'S' if bytes.len() >= 50 && !stack.is_empty() => {
                    let stage = std::str::from_utf8(&bytes[9..50]).map_err(|_| "invalid transaction names")?;
                    let target = std::str::from_utf8(&bytes[50..]).map_err(|_| "invalid transaction names")?;
                    match switch(stack.last().unwrap(), stage, target, uid) {
                        Ok(()) => {
                            if !stack.iter().all(|h| valid(h, uid)) { reply(b'U', seq, stack.len(), Some(UNSAFE))?; return Ok(()); }
                            answer!(b'S', seq, None);
                        },
                        Err((false, code)) => answer!(b'E', seq, Some(code)),
                        Err((true, code)) => { reply(b'U', seq, stack.len(), Some(code))?; return Ok(()); },
                    }
                }
                b'Q' | b'N' if !stack.is_empty() => {
                    let result = if kind == b'Q' { reclaim(stack.last().unwrap(), &bytes[9..], uid) } else { install(stack.last().unwrap(), &bytes[9..], uid) };
                    match result {
                        Ok(()) => {
                            if !stack.iter().all(|h| valid(h, uid)) { reply(b'U', seq, stack.len(), Some(UNSAFE))?; return Ok(()); }
                            answer!(kind, seq, None);
                        },
                        Err((false, code)) => answer!(b'E', seq, Some(code)),
                        Err((true, code)) => { reply(b'U', seq, stack.len(), Some(code))?; return Ok(()); },
                    }
                }
                b'W' if !stack.is_empty() => match stage(stack.last().unwrap(), &bytes[9..], uid) {
                    Ok(job) => { staging = Some(job); answer!(b'W', seq, None); },
                    Err(code) => answer!(b'E', seq, Some(code)),
                },
                b'D' if staging.is_some() => {
                    match stage_data(staging.as_mut().unwrap(), stack.last().unwrap(), &bytes[9..], uid) {
                        Ok(()) => {
                            if !stack.iter().all(|h| valid(h, uid)) { reply(b'U', seq, stack.len(), Some(UNSAFE))?; return Ok(()); }
                            if staging.as_ref().unwrap().remaining == 0 { staging = None; } answer!(b'D', seq, None);
                        },
                        Err(code) => { reply(b'U', seq, stack.len(), Some(code))?; return Ok(()); },
                    }
                }
                b'B' if bytes.len() == 18 && bytes[9] <= 1 && !stack.is_empty() => {
                    let budget = Budget { mode: bytes[9], ceiling: u64::from_be_bytes(bytes[10..18].try_into().unwrap()) };
                    let result = (|| {
                        let held = stack.last().unwrap();
                        if budget.ceiling == 0 || budget.ceiling > 64 * 1024 * 1024 ||
                            held.budget.is_some_and(|old| old.mode != budget.mode || budget.ceiling > old.ceiling) { return Err(INVALID); }
                        let (directories,_leases) = scope_writers(held,Some(budget.mode),0,uid)?;
                        allowance(held,budget,&[])?;
                        if !scope_valid(held,&directories,uid) { return Err(UNSAFE); }
                        Ok(())
                    })();
                    match result {
                        Ok(()) => { stack.last_mut().unwrap().budget = Some(budget); answer!(b'B',seq,None); },
                        Err(code) => answer!(b'E',seq,Some(code)),
                    }
                }
                b'F' if bytes.len() >= 11 && !stack.is_empty() => {
                    let result = (|| {
                        let held = stack.last().unwrap(); let budget = held.budget.ok_or(INVALID)?;
                        let count = u16::from_be_bytes(bytes[9..11].try_into().unwrap()) as usize;
                        if count > 256 || bytes.len() != 11 + count * 4 { return Err(INVALID); }
                        let mut sizes = Vec::new(); let mut total = 0_u64;
                        for record in bytes[11..].chunks_exact(4) {
                            let size = u32::from_be_bytes(record.try_into().unwrap()) as u64;
                            total = total.checked_add(size).ok_or(INVALID)?;
                            if size == 0 || size > MAX_FILE || total > 64 * 1024 * 1024 { return Err(INVALID); }
                            sizes.push(size);
                        }
                        let (directories,_leases) = scope_writers(held,Some(budget.mode),0,uid)?;
                        allowance(held,budget,&sizes)?;
                        if !scope_valid(held,&directories,uid) { return Err(UNSAFE); } Ok(())
                    })();
                    match result { Ok(()) => answer!(b'F',seq,None), Err(code) => answer!(b'E',seq,Some(code)) }
                }
                b'M' if bytes.len() == 10 && bytes[9] <= 1 && !stack.is_empty() => {
                    let held = stack.last().unwrap();
                    let result = (|| {
                        let mut leases = Vec::new();
                        let last = if bytes[9] == 0 { 0 } else { 2 };
                        let mut directories = Vec::new();
                        for selector in 0..=last { let d = child(held, selector, uid)?; leases.push(writer(&d, uid)?); directories.push(d); }
                        let path = held.path.parent().ok_or(INVALID)?;
                        if bytes[9] == 0 {
                            let mut count = 0usize;
                            for entry in std::fs::read_dir(path).map_err(|_| IO)? {
                                count += 1; if count > 40_000 { return Err(INVALID); }
                                if entry.map_err(|_| IO)?.file_type().map_err(|_| IO)?.is_dir() { return Err(UNSAFE); }
                            }
                        }
                        let usage = super::super::ipse_storage::transaction_usage(path).map_err(|_| IO)?;
                        if !stack.iter().all(|h| valid(h, uid)) || !directories.iter().enumerate().all(|(selector,d)| directory_valid(held,d,selector as u8,uid)) { return Err(UNSAFE); }
                        Ok(usage)
                    })();
                    match result {
                        Ok((logical, allocated, entries)) => {
                            let mut payload = seq.to_be_bytes().to_vec(); payload.push(stack.len() as u8);
                            payload.extend_from_slice(&logical.to_be_bytes()); payload.extend_from_slice(&allocated.to_be_bytes()); payload.extend_from_slice(&entries.to_be_bytes());
                            super::super::frame(b'M', &payload).map_err(|_| "transaction output unavailable")?;
                        },
                        Err(code) => answer!(b'E', seq, Some(code)),
                    }
                }
                _ => return Err("invalid transaction command".into()),
            }
        }
        Ok(())
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
        use std::sync::atomic::{AtomicU64, Ordering};
        static NEXT: AtomicU64 = AtomicU64::new(0);
        struct Fixture { path: PathBuf, held: Option<Held>, uid: u32 }
        impl Fixture {
            fn new() -> Self {
                let path = std::env::temp_dir().join(format!("ipse-optional-native-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed)));
                std::fs::DirBuilder::new().mode(0o700).create(&path).unwrap();
                let uid = unsafe { geteuid() };
                let held = acquire(path.join(".lock").to_str().unwrap(), uid, &[]).unwrap();
                Self { path, held: Some(held), uid }
            }
            fn held(&self) -> &Held { self.held.as_ref().unwrap() }
            fn write(&self, name: &str, bytes: &[u8]) {
                let mut file = std::fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(self.path.join(name)).unwrap();
                file.write_all(bytes).unwrap();
            }
            fn request(name: &str, offset: u32, maximum: u32) -> Vec<u8> {
                let mut bytes = vec![0, name.len() as u8]; bytes.extend_from_slice(name.as_bytes());
                bytes.extend_from_slice(&offset.to_be_bytes()); bytes.extend_from_slice(&maximum.to_be_bytes()); bytes
            }
            fn read(&self, name: &str, offset: u32) -> Result<Option<Vec<u8>>,u8> {
                read_chunk(self.held(), &Self::request(name, offset, 65_536), self.uid, true)
            }
        }
        impl Drop for Fixture {
            fn drop(&mut self) { self.held.take(); let _ = std::fs::remove_dir_all(&self.path); }
        }
        #[test]
        fn optional_missing_is_distinct_from_empty_and_never_continues_a_prefix() {
            let f = Fixture::new();
            assert_eq!(f.read("root.json", 0), Ok(None));
            assert_eq!(f.read("root.json", 1), Err(UNSAFE));
            assert_eq!(read_chunk(f.held(), &Fixture::request("root.json",0,100), f.uid, false), Err(IO));
            f.write("root.json", b"");
            let bytes = f.read("root.json",0).unwrap().unwrap();
            assert_eq!(bytes.len(), 24); assert_eq!(&bytes[..8], &[0;8]);
            assert!(valid(f.held(),f.uid));
        }
        #[test]
        fn optional_present_reuses_chunk_bounds_and_private_file_checks() {
            let f = Fixture::new(); f.write("control.json", &vec![7;20_000]);
            assert_eq!(f.read("control.json",0).unwrap().unwrap().len(), 24+16_384);
            assert_eq!(f.read("control.json",16_384).unwrap().unwrap().len(), 24+3_616);
            assert_eq!(read_chunk(f.held(), &Fixture::request("control.json",0,19_999),f.uid,true),Err(UNSAFE));
            let metadata = std::fs::metadata(f.path.join("control.json")).unwrap();
            assert!(!private_file(&metadata,f.uid.wrapping_add(1)));
            std::fs::set_permissions(f.path.join("control.json"),std::os::unix::fs::PermissionsExt::from_mode(0o644)).unwrap();
            assert_eq!(f.read("control.json",0),Err(UNSAFE));
        }
        #[test]
        fn optional_links_directories_and_bad_names_are_not_absence() {
            let f = Fixture::new();
            std::os::unix::fs::symlink("absent-target",f.path.join("root.json")).unwrap();
            assert_eq!(f.read("root.json",0),Err(IO));
            std::fs::remove_file(f.path.join("root.json")).unwrap();
            f.write("control.json",b"private");
            std::fs::hard_link(f.path.join("control.json"),f.path.join("root.json")).unwrap();
            assert_eq!(f.read("root.json",0),Err(UNSAFE));
            std::fs::remove_file(f.path.join("root.json")).unwrap();
            std::fs::DirBuilder::new().mode(0o700).create(f.path.join("root.json")).unwrap();
            assert_eq!(f.read("root.json",0),Err(UNSAFE));
            assert_eq!(f.read("../root.json",0),Err(INVALID));
            let mut request = Fixture::request("root.json",0,100); request[0]=1;
            assert_eq!(read_chunk(f.held(),&request,f.uid,true),Err(IO));
        }
        #[test]
        fn optional_absence_requires_the_retained_named_root_and_child_identity() {
            let f = Fixture::new();
            std::fs::DirBuilder::new().mode(0o700).create(f.path.join("objects")).unwrap();
            let mut request = Fixture::request(&format!("{}.json","a".repeat(64)),0,100); request[0]=1;
            assert_eq!(read_chunk(f.held(),&request,f.uid,true),Ok(None));
            std::fs::set_permissions(f.path.join("objects"),std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
            assert_eq!(read_chunk(f.held(),&request,f.uid,true),Err(UNSAFE));
            std::fs::set_permissions(f.path.join("objects"),std::os::unix::fs::PermissionsExt::from_mode(0o700)).unwrap();
            let moved = f.path.with_extension("moved"); std::fs::rename(&f.path,&moved).unwrap();
            std::fs::DirBuilder::new().mode(0o700).create(&f.path).unwrap();
            assert_eq!(f.read("root.json",0),Err(UNSAFE));
            std::fs::remove_dir(&f.path).unwrap(); std::fs::rename(moved,&f.path).unwrap();
        }
    }
}

pub fn run(args: &[String]) -> Result<(), String> {
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    { unix::run(args) }
    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    { let _ = args; Err("transaction locks require Linux or macOS".into()) }
}
