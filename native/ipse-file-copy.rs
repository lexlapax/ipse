//! Copy a bounded regular source through a retained, nonblocking, nonfollowing FD.
#[cfg(any(target_os = "linux", target_os = "macos"))]
mod unix {
    use std::fs::{self, File, Metadata, OpenOptions, Permissions};
    use std::io::{Read, Write};
    use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
    use std::path::Path;

    const MAX_BYTES: u64 = 64 * 1024 * 1024 * 1024;
    #[cfg(target_os = "linux")]
    const FLAGS: i32 = 0x800 | 0x20000;
    #[cfg(target_os = "macos")]
    const FLAGS: i32 = 0x4 | 0x100;
    #[cfg(target_os = "linux")]
    const DIRECTORY: i32 = 0x10000;
    #[cfg(target_os = "macos")]
    const DIRECTORY: i32 = 0x100000;

    #[derive(Clone, Debug, PartialEq, Eq)]
    struct Identity {
        device: u64, inode: u64, bytes: u64, mode: u32, nlink: u64,
        mtime_seconds: i64, mtime_nanoseconds: i64,
        ctime_seconds: i64, ctime_nanoseconds: i64,
    }
    impl Identity {
        fn of(metadata: &Metadata) -> Self {
            Self { device: metadata.dev(), inode: metadata.ino(), bytes: metadata.len(),
                mode: metadata.mode(), nlink: metadata.nlink(), mtime_seconds: metadata.mtime(),
                mtime_nanoseconds: metadata.mtime_nsec(), ctime_seconds: metadata.ctime(),
                ctime_nanoseconds: metadata.ctime_nsec() }
        }
        fn json(&self) -> String {
            format!("{{\"device\":\"{}\",\"inode\":\"{}\",\"bytes\":{},\"mode\":{},\"nlink\":\"{}\",\"mtime_seconds\":\"{}\",\"mtime_nanoseconds\":{},\"ctime_seconds\":\"{}\",\"ctime_nanoseconds\":{}}}",
                self.device, self.inode, self.bytes, self.mode, self.nlink,
                self.mtime_seconds, self.mtime_nanoseconds, self.ctime_seconds, self.ctime_nanoseconds)
        }
    }
    struct Receipt { bytes: u64, source: Identity, destination: Identity }
    impl Receipt {
        fn json(&self) -> String {
            format!("{{\"version\":1,\"bytes\":{},\"source\":{},\"destination\":{}}}\n",
                self.bytes, self.source.json(), self.destination.json())
        }
    }
    fn unchanged(source: &File, path: &Path, before: &Identity) -> Result<(), String> {
        let retained = source.metadata().map_err(|_| "copy source metadata unavailable")?;
        let named = fs::symlink_metadata(path).map_err(|_| "copy source path unavailable")?;
        if !retained.is_file() || !named.is_file()
            || Identity::of(&retained) != *before || Identity::of(&named) != *before {
            return Err("copy source changed".into());
        }
        Ok(())
    }
    fn copy(source_path: &Path, destination_path: &Path, expected: u64) -> Result<Receipt, String> {
        if expected > MAX_BYTES { return Err("copy size exceeds 64 GiB".into()); }
        if !source_path.is_absolute() || !destination_path.is_absolute() {
            return Err("copy requires absolute source and destination paths".into());
        }
        let mut source = OpenOptions::new().read(true).custom_flags(FLAGS).open(source_path)
            .map_err(|e| format!("cannot open copy source: {e}"))?;
        let metadata = source.metadata().map_err(|_| "copy source metadata unavailable")?;
        if !metadata.is_file() || metadata.len() != expected {
            return Err("copy source must be a regular file of the exact expected size".into());
        }
        let before = Identity::of(&metadata);
        unchanged(&source, source_path, &before)?;
        let parent_path = destination_path.parent().ok_or("copy destination has no parent")?;
        let parent = OpenOptions::new().read(true).custom_flags(FLAGS | DIRECTORY).open(parent_path)
            .map_err(|e| format!("cannot open copy destination parent: {e}"))?;
        let parent_before = parent.metadata().map_err(|_| "copy parent metadata unavailable")?;
        if !parent_before.is_dir() { return Err("copy destination parent is not a directory".into()); }
        let mut destination = OpenOptions::new().write(true).create_new(true).mode(0o600)
            .custom_flags(FLAGS).open(destination_path)
            .map_err(|e| format!("cannot create copy destination: {e}"))?;
        destination.set_permissions(Permissions::from_mode(0o600))
            .map_err(|_| "cannot secure copy destination")?;
        let mut buffer = [0_u8; 65_536];
        let mut copied = 0;
        while copied < expected {
            let size = (expected - copied).min(buffer.len() as u64) as usize;
            let count = source.read(&mut buffer[..size]).map_err(|_| "copy source read failed")?;
            if count == 0 { return Err("copy source ended before expected size".into()); }
            destination.write_all(&buffer[..count]).map_err(|_| "copy destination write failed")?;
            copied += count as u64;
        }
        if source.read(&mut buffer[..1]).map_err(|_| "copy source EOF unavailable")? != 0 {
            return Err("copy source exceeds expected size".into());
        }
        destination.sync_all().map_err(|_| "copy destination sync failed")?;
        parent.sync_all().map_err(|_| "copy parent sync failed")?;
        unchanged(&source, source_path, &before)?;
        let after = destination.metadata().map_err(|_| "copy destination metadata unavailable")?;
        let named = fs::symlink_metadata(destination_path).map_err(|_| "copy destination path unavailable")?;
        let parent_after = fs::symlink_metadata(parent_path).map_err(|_| "copy parent path unavailable")?;
        if !after.is_file() || !named.is_file() || Identity::of(&after) != Identity::of(&named)
            || after.len() != expected || after.nlink() != 1 || after.mode() & 0o7777 != 0o600
            || (after.dev(), after.ino()) == (before.device, before.inode)
            || !parent_after.is_dir()
            || (parent_after.dev(), parent_after.ino()) != (parent_before.dev(), parent_before.ino()) {
            return Err("copy destination identity changed".into());
        }
        Ok(Receipt { bytes: copied, source: before, destination: Identity::of(&after) })
    }
    fn expected(text: &str) -> Result<u64, String> {
        if text.is_empty() || !text.bytes().all(|byte| byte.is_ascii_digit()) {
            return Err("copy size must be an unsigned decimal byte count".into());
        }
        text.parse::<u64>().ok().filter(|size| *size <= MAX_BYTES)
            .ok_or_else(|| "copy size exceeds 64 GiB".into())
    }
    pub fn run(args: &[String]) -> Result<(), String> {
        if args.len() != 5 { return Err("usage: --copy-regular ABS_SOURCE ABS_DEST EXPECTED_BYTES".into()); }
        let receipt = copy(Path::new(&args[2]), Path::new(&args[3]), expected(&args[4])?)?;
        let bytes = receipt.json();
        if bytes.len() > 2048 { return Err("copy receipt exceeds bound".into()); }
        std::io::stdout().lock().write_all(bytes.as_bytes()).map_err(|_| "copy receipt delivery failed".into())
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        use std::os::unix::fs::symlink;
        use std::process::{Child, Command, Stdio};
        use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
        struct Root(std::path::PathBuf);
        impl Root {
            fn new() -> Self {
                let nonce = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
                let path = std::env::temp_dir().join(format!("ipse-copy-{}-{nonce}", std::process::id()));
                fs::create_dir(&path).unwrap();
                fs::set_permissions(&path, Permissions::from_mode(0o700)).unwrap(); Self(path)
            }
            fn path(&self, name: &str) -> std::path::PathBuf { self.0.join(name) }
        }
        impl Drop for Root { fn drop(&mut self) { let _ = fs::remove_dir_all(&self.0); } }
        #[test]
        fn empty_and_multibuffer_copies_are_new_private_regular_inodes() {
            let root = Root::new();
            for size in [0, 131_091] {
                let source = root.path(&format!("source-{size}")); let destination = root.path(&format!("dest-{size}"));
                let bytes = vec![197; size]; fs::write(&source, &bytes).unwrap();
                fs::set_permissions(&source, Permissions::from_mode(0o444)).unwrap();
                let receipt = copy(&source, &destination, size as u64).unwrap();
                assert_eq!(fs::read(destination).unwrap(), bytes);
                assert_eq!(receipt.bytes, size as u64);
                assert_eq!(receipt.destination.nlink, 1);
                assert_eq!(receipt.destination.mode & 0o7777, 0o600);
                assert_ne!((receipt.source.device, receipt.source.inode), (receipt.destination.device, receipt.destination.inode));
                assert!(receipt.json().len() < 2048);
            }
        }
        #[test]
        fn source_and_destination_symlinks_are_refused_without_replacing_targets() {
            let root = Root::new(); let source = root.path("source"); fs::write(&source, b"keep").unwrap();
            let link = root.path("source-link"); symlink(&source, &link).unwrap();
            assert!(copy(&link, &root.path("absent"), 4).is_err());
            assert!(!root.path("absent").exists());
            let dest = root.path("dest-link"); symlink(&source, &dest).unwrap();
            assert!(copy(&source, &dest, 4).is_err());
            assert_eq!(fs::read(&source).unwrap(), b"keep"); assert!(fs::symlink_metadata(dest).unwrap().file_type().is_symlink());
        }
        #[test]
        fn existing_destinations_and_wrong_sizes_are_preserved() {
            let root = Root::new(); let source = root.path("source"); let dest = root.path("dest");
            fs::write(&source, b"abc").unwrap(); fs::write(&dest, b"preserve").unwrap();
            assert!(copy(&source, &dest, 3).is_err()); assert_eq!(fs::read(&dest).unwrap(), b"preserve");
            for size in [0, 2, 4] { assert!(copy(&source, &root.path(&format!("absent-{size}")), size).is_err()); assert!(!root.path(&format!("absent-{size}")).exists()); }
            assert!(copy(&root.0, &root.path("directory-copy"), 0).is_err());
        }
        #[test]
        fn retained_and_named_source_metadata_changes_are_detected() {
            let root = Root::new(); let path = root.path("source"); fs::write(&path, b"abc").unwrap();
            let source = File::open(&path).unwrap(); let before = Identity::of(&source.metadata().unwrap());
            fs::set_permissions(&path, Permissions::from_mode(0o400)).unwrap(); assert!(unchanged(&source, &path, &before).is_err());
            fs::set_permissions(&path, Permissions::from_mode(0o600)).unwrap();
            let before = Identity::of(&source.metadata().unwrap()); fs::write(&path, b"abcd").unwrap(); assert!(unchanged(&source, &path, &before).is_err());
            let before = Identity::of(&source.metadata().unwrap()); fs::rename(&path, root.path("old")).unwrap(); fs::write(&path, b"abcd").unwrap(); assert!(unchanged(&source, &path, &before).is_err());
        }
        #[test]
        fn literal_size_and_absolute_path_limits_refuse_before_copy() {
            for value in ["", "+1", "-1", " 1", "1x", "68719476737", "18446744073709551616"] { assert!(expected(value).is_err()); }
            assert_eq!(expected("0").unwrap(), 0); assert_eq!(expected("68719476736").unwrap(), MAX_BYTES);
            assert!(copy(Path::new("relative"), Path::new("/tmp/absent"), 0).is_err());
        }
        struct OwnedChild(Child);
        impl Drop for OwnedChild {
            fn drop(&mut self) {
                if self.0.try_wait().ok().flatten().is_none() { let _ = self.0.kill(); }
                let until = Instant::now() + Duration::from_secs(2);
                while Instant::now() < until { if self.0.try_wait().ok().flatten().is_some() { break; } std::thread::sleep(Duration::from_millis(2)); }
            }
        }
        #[test]
        fn writerless_fifo_refuses_without_waiting_for_a_writer() {
            extern "C" { fn mkfifo(path: *const i8, mode: u32) -> i32; }
            use std::os::unix::ffi::OsStrExt;
            let root = Root::new(); let path = root.path("fifo");
            let name = std::ffi::CString::new(path.as_os_str().as_bytes()).unwrap();
            assert_eq!(unsafe { mkfifo(name.as_ptr(), 0o600) }, 0);
            let name = std::thread::current().name().unwrap().to_string();
            let (prefix, _) = name.rsplit_once("::").unwrap();
            let mut child = OwnedChild(Command::new(std::env::current_exe().unwrap())
                .args(["--ignored", "--exact", &format!("{prefix}::fifo_open_probe")])
                .env_clear().env("IPSE_COPY_FIFO_PROBE", &root.0)
                .stdout(Stdio::null()).stderr(Stdio::null()).spawn().unwrap());
            let until = Instant::now() + Duration::from_millis(1500);
            loop {
                if let Some(status) = child.0.try_wait().unwrap() { assert!(status.success()); break; }
                assert!(Instant::now() < until, "nonblocking FIFO admission exceeded 1500ms");
                std::thread::sleep(Duration::from_millis(2));
            }
            assert_eq!(fs::read(root.path("finished")).unwrap(), b"refused");
            assert!(!root.path("dest").exists());
        }
        #[test]
        #[ignore = "isolated subprocess control for the bounded FIFO test"]
        fn fifo_open_probe() {
            let root = std::path::PathBuf::from(std::env::var_os("IPSE_COPY_FIFO_PROBE").expect("owned FIFO probe root"));
            assert!(copy(&root.join("fifo"), &root.join("dest"), 0).is_err());
            fs::write(root.join("finished"), b"refused").unwrap();
        }
    }
}
#[cfg(any(target_os = "linux", target_os = "macos"))]
pub use unix::run;
#[cfg(not(any(target_os = "linux", target_os = "macos")))]
pub fn run(_args: &[String]) -> Result<(), String> { Err("regular-file copy requires Linux or macOS".into()) }
