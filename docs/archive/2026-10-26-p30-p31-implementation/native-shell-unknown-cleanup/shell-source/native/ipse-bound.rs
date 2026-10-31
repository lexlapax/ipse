use std::path::{Path, PathBuf};

#[derive(Clone, Debug)]
pub struct Authority {
    pub registry: PathBuf, pub device: u64, pub inode: u64,
    pub root: PathBuf, pub bootstrap: PathBuf,
}
impl Authority {
    pub fn decode(bytes: &[u8]) -> Result<Self, String> {
        struct Read<'a> { bytes: &'a [u8], at: usize }
        impl Read<'_> {
            fn take(&mut self, n: usize) -> Result<&[u8], String> {
                let end = self.at.checked_add(n).ok_or("bound authority overflow")?;
                let value = self.bytes.get(self.at..end).ok_or("truncated bound authority")?;
                self.at = end; Ok(value)
            }
            fn path(&mut self) -> Result<PathBuf, String> {
                let n = u32::from_be_bytes(self.take(4)?.try_into().unwrap()) as usize;
                if n > 65_536 { return Err("bound authority path exceeds bound".into()); }
                let text = std::str::from_utf8(self.take(n)?).map_err(|_| "invalid bound authority UTF-8")?;
                let path = PathBuf::from(text);
                if text.as_bytes().contains(&0) || !path.is_absolute()
                    || path.components().any(|c| matches!(c, std::path::Component::ParentDir | std::path::Component::CurDir))
                    || path.components().collect::<PathBuf>().as_os_str() != path.as_os_str() {
                    return Err("bound authority path is not normalized absolute".into());
                }
                Ok(path)
            }
        }
        let mut r = Read { bytes, at: 0 };
        if r.take(8)? != b"IPBND001" { return Err("unsupported bound authority".into()); }
        let registry = r.path()?;
        let device = u64::from_be_bytes(r.take(8)?.try_into().unwrap());
        let inode = u64::from_be_bytes(r.take(8)?.try_into().unwrap());
        let root = r.path()?; let bootstrap = r.path()?;
        if r.at != bytes.len() || root.file_name() != Some(std::ffi::OsStr::new("native-root"))
            || root.parent().map(|p| p.join("attempts")) != Some(registry.clone())
            || root.parent().map(|p| p.join("bootstrap.bin")) != Some(bootstrap.clone()) {
            return Err("invalid bound authority relation".into());
        }
        Ok(Self { registry, device, inode, root, bootstrap })
    }
}

#[cfg(target_os = "linux")]
mod linux {
    use super::*;
    use std::fs::{self, File, OpenOptions};
    use std::io::{Read, Write};
    use std::os::fd::{AsRawFd, FromRawFd};
    use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt};
    use std::os::unix::process::CommandExt;
    use std::process::Command;

    const NAMES: [&str; 5] = ["IPSE_BOUND_ROOT_FD", "IPSE_BOUND_REGISTRY_FD", "IPSE_MEASURE_ROOT_FD", "IPSE_MEASURE_SCOPE_FD", "IPSE_BOUND_SEQUENCE_FD"];
    const NOFOLLOW: i32 = 0x20000;
    const DIRECTORY: i32 = 0x10000;
    const NONBLOCK: i32 = 0x800;
    extern "C" { fn fcntl(fd: i32, operation: i32, ...) -> i32; fn dup2(old: i32, new: i32) -> i32; fn close(fd: i32) -> i32; fn geteuid() -> u32; fn fstatfs(fd: i32, value: *mut usize) -> i32; }
    fn failure(e: std::io::Error) -> String { e.to_string() }
    fn same(a: &fs::Metadata, b: &fs::Metadata) -> bool { a.dev() == b.dev() && a.ino() == b.ino() }
    fn secure(m: &fs::Metadata) -> bool { m.is_dir() && m.uid() == unsafe { geteuid() } && m.mode() & 0o077 == 0 }
    pub fn directory(path: &Path) -> Result<File, String> {
        let f = OpenOptions::new().read(true).custom_flags(DIRECTORY | NOFOLLOW).open(path).map_err(failure)?;
        if !secure(&f.metadata().map_err(failure)?) { return Err("bound directory is not owner-only".into()); }
        Ok(f)
    }
    fn duplicate(fd: i32) -> Result<File, String> {
        let copy = unsafe { fcntl(fd, 1030, 64) };
        if copy < 0 { return Err("bound handle unavailable".into()); }
        Ok(unsafe { File::from_raw_fd(copy) })
    }
    fn cgroup(file: &File) -> Result<(), String> {
        let mut stat = [0_usize; 32];
        if unsafe { fstatfs(file.as_raw_fd(), stat.as_mut_ptr()) } != 0 || stat[0] != 0x63677270
            || !file.metadata().map_err(failure)?.is_dir() { return Err("bound scope is not cgroup-v2".into()); }
        Ok(())
    }
    pub fn fd_path(file: &File) -> PathBuf { PathBuf::from(format!("/proc/self/fd/{}", file.as_raw_fd())) }
    pub fn read(path: &Path) -> Result<Vec<u8>, String> {
        let mut f = OpenOptions::new().read(true).custom_flags(NOFOLLOW | NONBLOCK).open(path).map_err(failure)?;
        let a = f.metadata().map_err(failure)?;
        if !a.is_file() || a.uid() != unsafe { geteuid() } || a.mode() & 0o077 != 0 || a.len() > 1_048_576 { return Err("invalid bound regular file".into()); }
        let mut bytes = Vec::new(); (&mut f).take(1_048_577).read_to_end(&mut bytes).map_err(failure)?;
        let b = f.metadata().map_err(failure)?;
        if bytes.len() as u64 != a.len() || !same(&a, &b) || a.len() != b.len() || a.mtime() != b.mtime()
            || a.mtime_nsec() != b.mtime_nsec() || a.ctime() != b.ctime() || a.ctime_nsec() != b.ctime_nsec() { return Err("bound file changed while reading".into()); }
        Ok(bytes)
    }
    pub fn save(dir: &File, name: &str, bytes: &[u8]) -> Result<(), String> {
        if Path::new(name).components().count() != 1 || name == "." || name == ".." { return Err("invalid bound leaf".into()); }
        let mut f = OpenOptions::new().write(true).create_new(true).mode(0o600).custom_flags(NOFOLLOW).open(fd_path(dir).join(name)).map_err(failure)?;
        f.write_all(bytes).and_then(|_| f.sync_all()).map_err(failure)?; dir.sync_all().map_err(failure)
    }
    fn membership() -> Result<PathBuf, String> {
        let mut f = File::open("/proc/self/cgroup").map_err(failure)?;
        let mut bytes = Vec::new(); (&mut f).take(8193).read_to_end(&mut bytes).map_err(failure)?;
        if bytes.len() > 8192 { return Err("bound cgroup membership exceeds bound".into()); }
        let text = std::str::from_utf8(&bytes).map_err(|_| "invalid cgroup membership")?;
        let relative = text.lines().find_map(|s| s.strip_prefix("0::")).ok_or("missing cgroup membership")?;
        let p = Path::new(relative);
        if !p.is_absolute() || p.components().any(|c| matches!(c, std::path::Component::ParentDir | std::path::Component::CurDir)) { return Err("invalid cgroup membership".into()); }
        Ok(Path::new("/sys/fs/cgroup").join(p.strip_prefix("/").unwrap()))
    }
    pub struct Bound {
        pub authority: Authority, pub root: File, registry: File,
        whole: Option<File>, scope: Option<File>, pub sequence: Option<File>,
    }
    impl Bound {
        pub fn create(path: &Path, output: &Path, command: &[String]) -> Result<Self, String> {
            let bytes = read(path)?; let authority = Authority::decode(&bytes)?;
            if path != authority.root.parent().unwrap().join("native-authority.bin") || output != authority.root
                || command.len() != 3 || command[1] != "--measure-sequence" || Path::new(&command[2]) != authority.bootstrap
                || !same(&fs::metadata(&command[0]).map_err(failure)?, &fs::metadata(std::env::current_exe().map_err(failure)?).map_err(failure)?) {
                return Err("bound root launch differs from authority".into());
            }
            let registry = directory(&authority.registry)?;
            let identity = registry.metadata().map_err(failure)?;
            if identity.dev() != authority.device || identity.ino() != authority.inode { return Err("sealed registry identity changed".into()); }
            let bootstrap = read(&authority.bootstrap)?;
            let parent = directory(authority.root.parent().unwrap())?;
            if !same(&parent.metadata().map_err(failure)?, &fs::symlink_metadata(authority.root.parent().unwrap()).map_err(failure)?) { return Err("bound parent changed".into()); }
            fs::DirBuilder::new().mode(0o700).create(fd_path(&parent).join("native-root")).map_err(|e| format!("bound first launch refused: {e}"))?;
            parent.sync_all().map_err(failure)?;
            let root = directory(&fd_path(&parent).join("native-root"))?;
            let result = Self { authority, root, registry, whole: None, scope: None, sequence: None };
            result.check()?;
            save(&result.root, "authority.bin", &bytes)?; save(&result.root, "bootstrap.bin", &bootstrap)?;
            Ok(result)
        }
        pub fn inherited() -> Result<Option<Self>, String> {
            if std::env::var_os(NAMES[0]).is_none() { return Ok(None); }
            for (i, name) in NAMES[..4].iter().enumerate() {
                if std::env::var(name).ok().as_deref() != Some((i as i32 + 4).to_string().as_str()) { return Err("invalid bound descriptor contract".into()); }
            }
            let root = duplicate(4)?; let registry = duplicate(5)?; let whole = duplicate(6)?; let scope = duplicate(7)?;
            if !secure(&root.metadata().map_err(failure)?) || !secure(&registry.metadata().map_err(failure)?) { return Err("invalid bound filesystem handles".into()); }
            cgroup(&whole)?; cgroup(&scope)?;
            let authority = Authority::decode(&read(&fd_path(&root).join("authority.bin"))?)?;
            let sequence = match std::env::var_os(NAMES[4]) {
                None => None,
                Some(value) if value == "8" => Some(duplicate(8)?),
                _ => return Err("invalid bound sequence handle".into()),
            };
            let result = Self { authority, root, registry, whole: Some(whole), scope: Some(scope), sequence };
            result.check()?; result.current(false)?;
            if let Some(sequence) = &result.sequence {
                if !secure(&sequence.metadata().map_err(failure)?) || !same(&sequence.metadata().map_err(failure)?, &fs::symlink_metadata(result.anchor(&result.authority.root.join("sequence"))?).map_err(failure)?) { return Err("bound sequence directory changed".into()); }
            }
            for (i, name) in NAMES.iter().enumerate() {
                if std::env::var_os(name).is_some() && unsafe { fcntl(i as i32 + 4, 2, 1) } < 0 { return Err("cannot restrict inherited bound handle".into()); }
            }
            Ok(Some(result))
        }
        pub fn check(&self) -> Result<(), String> {
            let held = self.registry.metadata().map_err(failure)?;
            let named = fs::symlink_metadata(&self.authority.registry).map_err(failure)?;
            let root = fs::symlink_metadata(&self.authority.root).map_err(failure)?;
            if !secure(&held) || !secure(&named) || held.dev() != self.authority.device || held.ino() != self.authority.inode || !same(&held, &named)
                || !secure(&root) || !same(&root, &self.root.metadata().map_err(failure)?) { return Err("bound registry or root identity changed".into()); }
            if let Some(sequence) = &self.sequence {
                if !same(&sequence.metadata().map_err(failure)?, &fs::symlink_metadata(fd_path(&self.root).join("sequence")).map_err(failure)?) { return Err("bound sequence identity changed".into()); }
            }
            Ok(())
        }
        pub fn stage(&self, args: &[String]) -> Result<(), String> {
            let index = std::env::var("IPSE_BOUND_STAGE_INDEX").map_err(|_| "missing bound stage index")?;
            let n: usize = index.parse().map_err(|_| "invalid bound stage index")?;
            if n > 65 || index != n.to_string() { return Err("invalid bound stage index".into()); }
            let put = |b: &mut Vec<u8>, s: &str| { b.extend_from_slice(&(s.len() as u32).to_be_bytes()); b.extend_from_slice(s.as_bytes()); };
            let mut claim = b"IPSECLM1".to_vec(); put(&mut claim, &args[3]);
            claim.extend_from_slice(&args[4].parse::<u64>().map_err(|_| "invalid stage timeout")?.to_be_bytes());
            put(&mut claim, &args[5]); claim.extend_from_slice(&((args.len() - 7) as u32).to_be_bytes());
            for arg in &args[7..] { put(&mut claim, arg); }
            let sequence = self.sequence.as_ref().ok_or("missing bound sequence claim directory")?;
            if claim != read(&fd_path(sequence).join(format!("stage-{n:03}.claim")))? { return Err("bound stage differs from native claim".into()); }
            Ok(())
        }
        pub fn current(&self, application: bool) -> Result<(), String> {
            let whole = self.whole.as_ref().ok_or("missing bound root scope")?;
            let scope = self.scope.as_ref().ok_or("missing bound workload scope")?;
            let path = PathBuf::from(std::env::var_os("IPSE_MEASURE_ROOT").ok_or("missing bound measured root")?);
            let name = path.file_name().and_then(|s| s.to_str()).unwrap_or("");
            if name.len() != 41 || !name.starts_with("ipse-run-") || !name[9..].bytes().all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
                || !same(&fs::metadata(&path).map_err(failure)?, &whole.metadata().map_err(failure)?) { return Err("bound measured root changed".into()); }
            let actual = membership()?;
            if !same(&fs::metadata(&actual).map_err(failure)?, &scope.metadata().map_err(failure)?) { return Err("bound workload membership changed".into()); }
            let selected = if application || actual == path.join("application") { path.join("application") } else {
                let token = std::env::var("IPSE_BOUND_STAGE_TOKEN").map_err(|_| "missing bound stage token")?;
                if token.len() != 32 || !token.bytes().all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c)) { return Err("invalid bound stage token".into()); }
                path.join(format!("cell-{token}"))
            };
            if actual != selected { return Err("bound scope is not exact expected kernel membership".into()); }
            Ok(())
        }
        pub fn anchor(&self, path: &Path) -> Result<PathBuf, String> {
            let relative = path.strip_prefix(&self.authority.root).map_err(|_| "bound output outside native-root")?;
            if relative.components().any(|c| !matches!(c, std::path::Component::Normal(_))) { return Err("invalid bound relative path".into()); }
            Ok(fd_path(&self.root).join(relative))
        }
        #[cfg_attr(test, allow(dead_code))]
        pub fn set_sequence(&mut self, directory: File) { self.sequence = Some(directory); }
        pub fn transfer(&self, whole: &File, scope: &File) -> Result<Transfer, String> {
            self.check()?;
            let mut files = vec![duplicate(self.root.as_raw_fd())?, duplicate(self.registry.as_raw_fd())?, duplicate(whole.as_raw_fd())?, duplicate(scope.as_raw_fd())?];
            if let Some(sequence) = &self.sequence { files.push(duplicate(sequence.as_raw_fd())?); }
            Ok(Transfer { files })
        }
        #[cfg_attr(test, allow(dead_code))]
        pub fn inherited_transfer(&self) -> Result<Transfer, String> {
            self.current(true)?; self.transfer(self.whole.as_ref().unwrap(), self.scope.as_ref().unwrap())
        }
    }
    pub struct Transfer { files: Vec<File> }
    impl Transfer {
        pub fn environment(&self) -> Vec<(String, String)> { self.files.iter().enumerate().map(|(i, _)| (NAMES[i].into(), (i + 4).to_string())).collect() }
        pub unsafe fn install(&self) -> bool {
            self.files.iter().enumerate().all(|(i, f)| dup2(f.as_raw_fd(), i as i32 + 4) >= 0 && fcntl(i as i32 + 4, 2, 0) >= 0)
        }
        pub fn command(self, command: &mut Command) {
            for (key, value) in self.environment() { command.env(key, value); }
            let mut reservations = Vec::new();
            for (i, file) in self.files.iter().enumerate() {
                let target = i as i32 + 4;
                let reserved = unsafe { fcntl(file.as_raw_fd(), 1030, target) };
                if reserved >= 0 {
                    let owned = unsafe { File::from_raw_fd(reserved) };
                    if reserved == target { reservations.push(owned); }
                }
            }
            unsafe { command.pre_exec(move || {
                let _held = &reservations;
                if self.install() { Ok(()) } else { Err(std::io::Error::last_os_error()) }
            }); }
        }
    }
    pub fn is_bound_key(key: &[u8]) -> bool { NAMES.iter().any(|n| n.as_bytes() == key) }
    pub fn scrub_ordinary() {
        if matches!(Bound::inherited(), Ok(Some(_))) {
            for (i, name) in NAMES.iter().enumerate() {
                if std::env::var_os(name).is_some() { unsafe { close(i as i32 + 4); } }
                std::env::remove_var(name);
            }
            std::env::remove_var("IPSE_BOUND_STAGE_INDEX"); std::env::remove_var("IPSE_BOUND_STAGE_TOKEN");
        }
    }
    #[cfg(test)]
    mod tests {
        use super::*;
        use std::time::{Duration, SystemTime, UNIX_EPOCH};
        use std::sync::atomic::{AtomicU64, Ordering};
        static NEXT_TEMP: AtomicU64 = AtomicU64::new(0);
        struct Temp(PathBuf);
        impl Temp {
            fn new() -> Self {
                Self::new_at(SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos())
            }
            fn new_at(n: u128) -> Self {
                let ordinal = NEXT_TEMP.fetch_add(1, Ordering::Relaxed);
                let p = std::env::temp_dir().join(format!("ipse-bound-{}-{n}-{ordinal}", std::process::id()));
                fs::DirBuilder::new().mode(0o700).create(&p).unwrap(); Self(p)
            }
        }
        impl Drop for Temp { fn drop(&mut self) { let _ = fs::remove_dir_all(&self.0); } }
        #[test]
        fn equal_clock_ticks_keep_fixture_directories_distinct() {
            let _ordinary = Temp::new();
            let first = Temp::new_at(1);
            let second = Temp::new_at(1);
            assert_ne!(first.0, second.0);
        }
        fn authority(path: &Path) -> Vec<u8> {
            let m = fs::metadata(path.join("attempts")).unwrap();
            let mut b = b"IPBND001".to_vec();
            let put = |b: &mut Vec<u8>, p: PathBuf| { let s = p.to_str().unwrap(); b.extend_from_slice(&(s.len() as u32).to_be_bytes()); b.extend_from_slice(s.as_bytes()); };
            put(&mut b, path.join("attempts")); b.extend_from_slice(&m.dev().to_be_bytes()); b.extend_from_slice(&m.ino().to_be_bytes());
            put(&mut b, path.join("native-root")); put(&mut b, path.join("bootstrap.bin")); b
        }
        #[test] fn first_launch_survives_registry_recreation_and_live_replacement_refuses() {
            let tmp = Temp::new(); let parent = directory(&tmp.0).unwrap();
            fs::DirBuilder::new().mode(0o700).create(tmp.0.join("attempts")).unwrap();
            save(&parent, "bootstrap.bin", b"opaque bootstrap").unwrap();
            save(&parent, "native-authority.bin", &authority(&tmp.0)).unwrap();
            let args = vec![std::env::current_exe().unwrap().to_str().unwrap().into(), "--measure-sequence".into(), tmp.0.join("bootstrap.bin").to_str().unwrap().into()];
            let bound = Bound::create(&tmp.0.join("native-authority.bin"), &tmp.0.join("native-root"), &args).unwrap();
            fs::remove_dir(tmp.0.join("attempts")).unwrap();
            fs::DirBuilder::new().mode(0o700).create(tmp.0.join("attempts")).unwrap();
            assert!(bound.check().is_err());
            fs::remove_file(tmp.0.join("native-authority.bin")).unwrap();
            save(&parent, "native-authority.bin", &authority(&tmp.0)).unwrap();
            assert!(Bound::create(&tmp.0.join("native-authority.bin"), &tmp.0.join("native-root"), &args).is_err());
            assert_eq!(read(&fd_path(&bound.root).join("bootstrap.bin")).unwrap(), b"opaque bootstrap");
        }
        #[test] fn writerless_authority_fifo_refuses_within_deadline() {
            use std::os::unix::ffi::OsStrExt;
            extern "C" { fn mkfifo(path: *const i8, mode: u32) -> i32; }
            let tmp = Temp::new(); let p = tmp.0.join("fifo");
            let c = std::ffi::CString::new(p.as_os_str().as_bytes()).unwrap();
            assert_eq!(unsafe { mkfifo(c.as_ptr(), 0o600) }, 0);
            let (send, receive) = std::sync::mpsc::channel();
            std::thread::spawn(move || { let _ = send.send(read(&p)); });
            assert!(receive.recv_timeout(Duration::from_secs(1)).expect("authority FIFO blocked").is_err());
        }
        #[test] fn transfer_child() {
            if std::env::var_os("IPSE_BOUND_TEST_CHILD").is_none() { return; }
            scrub_ordinary();
            assert_eq!(std::env::var("IPSE_BOUND_ROOT_FD").unwrap(), "4");
            for i in 0..5 {
                let mut file = duplicate(i + 4).unwrap(); let mut s = String::new(); file.read_to_string(&mut s).unwrap();
                assert_eq!(s, format!("owned-{i}"));
            }
        }
        #[test] fn transfer_preserves_all_handles_without_clobbering_spawn_error_pipe() {
            let tmp = Temp::new(); let root = directory(&tmp.0).unwrap();
            let mut files = Vec::new();
            for i in 0..5 { let name = format!("{i}"); save(&root, &name, format!("owned-{i}").as_bytes()).unwrap(); files.push(File::open(tmp.0.join(name)).unwrap()); }
            let transfer = Transfer { files: files.iter().map(|f| duplicate(f.as_raw_fd()).unwrap()).collect() };
            let mut command = Command::new(std::env::current_exe().unwrap());
            let module = module_path!().split_once("::").unwrap().1;
            command.args(["--exact", &format!("{module}::transfer_child")]).env("IPSE_BOUND_TEST_CHILD", "1");
            transfer.command(&mut command);
            let mut child = command.spawn().unwrap(); let deadline = std::time::Instant::now() + Duration::from_secs(5);
            loop {
                if let Some(status) = child.try_wait().unwrap() { assert!(status.success()); break; }
                if std::time::Instant::now() >= deadline { child.kill().unwrap(); let _ = child.wait(); panic!("owned descriptor child exceeded deadline"); }
                std::thread::sleep(Duration::from_millis(10));
            }
            let transfer = Transfer { files: files.iter().map(|f| duplicate(f.as_raw_fd()).unwrap()).collect() };
            let mut invalid = Command::new(tmp.0.join("absent-executable")); transfer.command(&mut invalid);
            assert!(invalid.spawn().is_err());
        }
    }
}
#[cfg(target_os = "linux")]
pub use linux::*;

#[cfg(test)]
mod tests {
    use super::*;
    fn bytes() -> Vec<u8> {
        let mut b = b"IPBND001".to_vec();
        let put = |b: &mut Vec<u8>, p: &str| { b.extend_from_slice(&(p.len() as u32).to_be_bytes()); b.extend_from_slice(p.as_bytes()); };
        put(&mut b, "/tmp/seal/attempts"); b.extend_from_slice(&12_u64.to_be_bytes()); b.extend_from_slice(&34_u64.to_be_bytes());
        put(&mut b, "/tmp/seal/native-root"); put(&mut b, "/tmp/seal/bootstrap.bin"); b
    }
    #[test] fn closed_authority_preserves_identity_and_refuses_every_truncation() {
        let b = bytes(); let a = Authority::decode(&b).unwrap();
        assert_eq!(a.registry, Path::new("/tmp/seal/attempts")); assert_eq!((a.device, a.inode), (12, 34));
        assert_eq!(a.root, Path::new("/tmp/seal/native-root")); assert_eq!(a.bootstrap, Path::new("/tmp/seal/bootstrap.bin"));
        for n in 0..b.len() { assert!(Authority::decode(&b[..n]).is_err(), "prefix {n}"); }
        let mut b = b; b.push(0); assert!(Authority::decode(&b).is_err());
    }
    #[test] fn output_registry_and_bootstrap_cannot_escape_seal_relation() {
        for (from, to) in [("attempts", "attemptx"), ("native-root", "native-roox"), ("bootstrap.bin", "bootstrap.bix")] {
            let mut b = bytes(); let at = b.windows(from.len()).position(|p| p == from.as_bytes()).unwrap(); b[at..at + to.len()].copy_from_slice(to.as_bytes());
            assert!(Authority::decode(&b).is_err());
        }
    }
    #[test] fn authority_refuses_non_utf8_nul_and_non_normal_paths() {
        for bad in ["relative", "/tmp/./attempts", "/tmp//attempts", "/tmp/../attempts", "/tmp/\0attempts"] {
            let mut b = b"IPBND001".to_vec(); b.extend_from_slice(&(bad.len() as u32).to_be_bytes()); b.extend_from_slice(bad.as_bytes());
            assert!(Authority::decode(&b).is_err());
        }
        let mut b = b"IPBND001".to_vec(); b.extend_from_slice(&1_u32.to_be_bytes()); b.push(255);
        assert!(Authority::decode(&b).is_err());
        let mut b = b"IPBND001".to_vec(); b.extend_from_slice(&65_537_u32.to_be_bytes());
        assert!(Authority::decode(&b).is_err());
    }
}
