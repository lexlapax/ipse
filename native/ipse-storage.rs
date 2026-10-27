//! Bounded allocated-byte inspection of an already protected storage directory.
use std::fs::{self, File, Metadata, OpenOptions};
use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
use std::path::Path;
use std::io::{Read, Write};
use std::os::unix::io::AsRawFd;
#[path = "ipse-storage-profile.rs"]
mod allocation_profile;
pub(crate) use allocation_profile::TransactionAllowanceError;

extern "C" { fn geteuid() -> u32; fn flock(fd: i32, operation: i32) -> i32; }

const MAX_ENTRIES: u64 = 40_000;
const MAX_DEPTH: usize = 4;

#[derive(Default, Debug)]
struct Usage { logical: u64, allocated: u64, entries: u64, directory_allocated: u64 }

#[cfg(target_os = "linux")]
fn flags(directory: bool) -> i32 { 0x20000 | 0x800 | if directory { 0x10000 } else { 0 } }
#[cfg(target_os = "macos")]
fn flags(directory: bool) -> i32 { 0x100 | 0x4 | if directory { 0x100000 } else { 0 } }
#[cfg(not(any(target_os = "linux", target_os = "macos")))]
fn flags(_: bool) -> i32 { 0 }

fn same(a: &Metadata, b: &Metadata) -> bool { a.dev() == b.dev() && a.ino() == b.ino() }

fn protected(metadata: &Metadata, uid: u32) -> bool {
    metadata.uid() == uid && metadata.mode() & 0o077 == 0 &&
        (metadata.is_dir() || (metadata.is_file() && metadata.nlink() == 1))
}

fn open(path: &Path, uid: u32) -> Result<(File, Metadata), String> {
    let before = fs::symlink_metadata(path).map_err(|_| "storage allocation unavailable")?;
    if !protected(&before, uid) { return Err("unsafe storage allocation entry".into()); }
    let file = OpenOptions::new().read(true).custom_flags(flags(before.is_dir())).open(path)
        .map_err(|_| "cannot retain storage allocation entry")?;
    let metadata = file.metadata().map_err(|_| "storage allocation unavailable")?;
    if !protected(&metadata, uid) || !same(&before, &metadata) {
        return Err("changed storage allocation identity".into());
    }
    Ok((file, metadata))
}

fn visit(path: &Path, uid: u32, depth: usize, usage: &mut Usage) -> Result<(), String> {
    if depth > MAX_DEPTH { return Err("storage allocation depth limit".into()); }
    let (_retained, metadata) = open(path, uid)?;
    usage.entries = usage.entries.checked_add(1).ok_or("storage allocation overflow")?;
    if usage.entries > MAX_ENTRIES { return Err("storage allocation entry limit".into()); }
    usage.logical = usage.logical.checked_add(metadata.len()).ok_or("storage allocation overflow")?;
    let blocks = metadata.blocks().checked_mul(512).ok_or("storage allocation overflow")?;
    usage.allocated = usage.allocated.checked_add(blocks).ok_or("storage allocation overflow")?;
    if metadata.is_dir() {
        usage.directory_allocated = usage.directory_allocated.checked_add(blocks).ok_or("storage allocation overflow")?;
        for entry in fs::read_dir(path).map_err(|_| "cannot enumerate storage allocation")? {
            let entry = entry.map_err(|_| "cannot enumerate storage allocation")?;
            visit(&entry.path(), uid, depth + 1, usage)?;
        }
    }
    let after = fs::symlink_metadata(path).map_err(|_| "changed storage allocation identity")?;
    if !same(&metadata, &after) || !protected(&after, uid) {
        return Err("changed storage allocation identity".into());
    }
    Ok(())
}

fn inspect(path: &Path) -> Result<Usage, String> {
    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    return Err("storage allocation requires Linux or macOS".into());
    if !path.is_absolute() || fs::canonicalize(path).map_err(|_| "storage allocation unavailable")?.as_os_str() != path.as_os_str() {
        return Err("storage allocation requires a canonical absolute directory".into());
    }
    let uid = unsafe { geteuid() };
    let (_retained, metadata) = open(path, uid)?;
    if !metadata.is_dir() { return Err("storage allocation requires a directory".into()); }
    let mut usage = Usage::default();
    visit(path, uid, 0, &mut usage)?;
    let after = fs::symlink_metadata(path).map_err(|_| "changed storage allocation root")?;
    if !same(&metadata, &after) { return Err("changed storage allocation root".into()); }
    Ok(usage)
}

pub fn run(args: &[String]) -> Result<(), String> {
    if args.len() != 3 { return Err("storage allocation requires one directory".into()); }
    let (logical, allocated, entries) = transaction_usage(Path::new(&args[2]))?;
    println!("{logical} {allocated} {entries}");
    Ok(())
}

// The transaction owner retains the logical lock, directory identity and all
// writer leases while using this shared bounded inventory implementation.
pub(crate) fn transaction_usage(path: &Path) -> Result<(u64, u64, u64), String> {
    let usage = inspect(path)?;
    Ok((usage.logical, usage.allocated, usage.entries))
}

pub(crate) fn transaction_preflight(path: &Path, sizes: &[u64], ceiling: u64) -> Result<(), TransactionAllowanceError> {
    if !(1..=64 * 1024 * 1024).contains(&ceiling) { return Err(TransactionAllowanceError::Unsafe); }
    let uid = unsafe { geteuid() };
    let (directory, before) = open(path, uid).map_err(|_| TransactionAllowanceError::Unsafe)?;
    if !before.is_dir() { return Err(TransactionAllowanceError::Unsafe); }
    let reserve = allocation_profile::reserve(&directory, sizes)?;
    let usage = inspect(path).map_err(|_| TransactionAllowanceError::Unsafe)?;
    // These finite profiles have no per-directory st_blocks allocation. A kernel
    // or mount whose observations differ is quarantined, never approximated.
    if usage.directory_allocated != 0 { return Err(TransactionAllowanceError::Unsupported); }
    let after = fs::symlink_metadata(path).map_err(|_| TransactionAllowanceError::Unsafe)?;
    if !same(&before, &after) { return Err(TransactionAllowanceError::Unsafe); }
    if usage.allocated.checked_add(reserve).ok_or(TransactionAllowanceError::Unsafe)? > ceiling {
        Err(TransactionAllowanceError::Capacity)
    } else { Ok(()) }
}

fn write_path<R: Read>(path: &Path, expected: u64, input: &mut R) -> Result<File, String> {
    if expected == 0 || expected > 8 * 1024 * 1024 || !path.is_absolute() {
        return Err("invalid protected staging bounds".into());
    }
    let name = path.file_name().and_then(|v| v.to_str()).ok_or("invalid protected staging name")?;
    if !name.starts_with(".pending-") || name.len() != 41 ||
        !name.as_bytes()[9..].iter().all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(c)) {
        return Err("invalid protected staging name".into());
    }
    let parent = path.parent().ok_or("invalid protected staging parent")?;
    if fs::canonicalize(parent).map_err(|_| "protected staging unavailable")?.as_os_str() != parent.as_os_str() {
        return Err("protected staging requires a canonical parent".into());
    }
    let uid = unsafe { geteuid() };
    let (_parent, parent_metadata) = open(parent, uid)?;
    if !parent_metadata.is_dir() { return Err("protected staging requires a directory".into()); }
    // No name or allocated payload exists before the first admitted bytes. A
    // writer that becomes ready only after its owner dies cannot leave a file.
    let mut buffer = [0u8; 65_536];
    let first_limit = (expected as usize).min(buffer.len());
    let first = loop {
        match input.read(&mut buffer[..first_limit]) {
            Ok(0) => return Err("truncated protected staging input".into()),
            Ok(n) => break n,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => return Err("protected staging input unavailable".into()),
        }
    };
    let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600)
        .custom_flags(flags(false)).open(path).map_err(|_| "cannot exclusively create protected staging")?;
    let created = file.metadata().map_err(|_| "cannot inspect protected staging")?;
    if !protected(&created, uid) || !created.is_file() { return Err("unsafe protected staging".into()); }
    file.write_all(&buffer[..first]).map_err(|_| "protected staging write unavailable")?;
    let mut remaining = expected - first as u64;
    while remaining > 0 {
        let limit = (remaining as usize).min(buffer.len());
        let count = match input.read(&mut buffer[..limit]) {
            Ok(0) => return Err("truncated protected staging input".into()),
            Ok(n) => n,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => return Err("protected staging input unavailable".into()),
        };
        file.write_all(&buffer[..count]).map_err(|_| "protected staging write unavailable")?;
        remaining -= count as u64;
    }
    let named = fs::symlink_metadata(path).map_err(|_| "changed protected staging identity")?;
    let after_parent = fs::symlink_metadata(parent).map_err(|_| "changed protected staging parent")?;
    if !same(&created, &named) || !protected(&named, uid) || named.len() != expected ||
        !same(&parent_metadata, &after_parent) || !protected(&after_parent, uid) {
        return Err("changed protected staging identity".into());
    }
    Ok(file)
}

// One acknowledged frame may be outstanding. This keeps the generic stdio
// supervisor's bounded input queue below its limit even if the writer stops.
struct FramedInput<R: Read> { input: R, remaining: usize }
impl<R: Read> Read for FramedInput<R> {
    fn read(&mut self, bytes: &mut [u8]) -> std::io::Result<usize> {
        if bytes.is_empty() { return Ok(0); }
        if self.remaining == 0 {
            let mut header = [0u8; 4];
            self.input.read_exact(&mut header)?;
            self.remaining = u32::from_be_bytes(header) as usize;
            if !(1..=16_384).contains(&self.remaining) {
                return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "invalid staging frame"));
            }
        }
        let limit = bytes.len().min(self.remaining);
        let count = self.input.read(&mut bytes[..limit])?;
        if count == 0 { return Err(std::io::Error::new(std::io::ErrorKind::UnexpectedEof, "truncated staging frame")); }
        self.remaining -= count;
        if self.remaining == 0 {
            std::io::stdout().write_all(b"A")?;
            std::io::stdout().flush()?;
        }
        Ok(count)
    }
}

pub fn write(args: &[String]) -> Result<(), String> {
    if args.len() != 4 { return Err("protected staging requires path and size".into()); }
    let expected = args[3].parse::<u64>().map_err(|_| "invalid protected staging size")?;
    if expected == 0 || expected > 8 * 1024 * 1024 { return Err("invalid protected staging size".into()); }
    let path = Path::new(&args[2]);
    let _writer = writer_lease(path.parent().ok_or("invalid protected staging parent")?)?;
    std::io::stdout().write_all(b"R").map_err(|_| "protected staging readiness unavailable")?;
    std::io::stdout().flush().map_err(|_| "protected staging readiness unavailable")?;
    let mut input = FramedInput { input: std::io::stdin().lock(), remaining: 0 };
    let file = write_path(path, expected, &mut input)?;
    if input.remaining != 0 { return Err("extra protected staging payload".into()); }
    drop(input);
    // After the bounded payload, stdin is a lease. Owner EOF or extra bytes
    // terminate this helper while a pending sync remains an unknown outcome.
    lease();
    file.sync_all().map_err(|_| "protected staging sync unavailable".into())
}

fn writer_lease(parent: &Path) -> Result<File, String> {
    let uid = unsafe { geteuid() };
    if !parent.is_absolute() || fs::canonicalize(parent).map_err(|_| "writer lease unavailable")?.as_os_str() != parent.as_os_str() {
        return Err("writer lease requires canonical protected parent".into());
    }
    let (_parent, metadata) = open(parent, uid)?;
    if !metadata.is_dir() { return Err("writer lease requires a directory".into()); }
    let path = parent.join(".writer.lock");
    let file = OpenOptions::new().read(true).write(true).create(true).mode(0o600)
        .custom_flags(flags(false)).open(&path).map_err(|_| "writer lease unavailable")?;
    let held = file.metadata().map_err(|_| "writer lease unavailable")?;
    let named = fs::symlink_metadata(path).map_err(|_| "writer lease unavailable")?;
    if !protected(&held, uid) || !held.is_file() || !same(&held, &named) || unsafe { flock(file.as_raw_fd(), 2 | 4) } != 0 {
        return Err("writer lease busy or unsafe".into());
    }
    Ok(file)
}

fn lease() {
    std::thread::spawn(|| {
        let mut byte = [0u8; 1];
        let _ = std::io::stdin().read(&mut byte);
        std::process::exit(2);
    });
}

pub fn write_many(args: &[String]) -> Result<(), String> {
    if args.len() != 4 { return Err("protected batch staging requires directory and count".into()); }
    let count = args[3].parse::<usize>().map_err(|_| "invalid protected staging count")?;
    if !(1..=128).contains(&count) { return Err("protected staging count limit".into()); }
    let directory = Path::new(&args[2]);
    let _writer = writer_lease(directory)?;
    std::io::stdout().write_all(b"R").map_err(|_| "protected staging readiness unavailable")?;
    std::io::stdout().flush().map_err(|_| "protected staging readiness unavailable")?;
    let mut input = FramedInput { input: std::io::stdin().lock(), remaining: 0 };
    let mut total = 0u64;
    let mut names = std::collections::HashSet::new();
    for _ in 0..count {
        let mut header = [0u8; 36];
        input.read_exact(&mut header).map_err(|_| "truncated protected staging header")?;
        let id = std::str::from_utf8(&header[..32]).map_err(|_| "invalid protected staging name")?;
        if !id.bytes().all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c)) || !names.insert(id.to_owned()) {
            return Err("invalid or repeated protected staging name".into());
        }
        let size = u32::from_be_bytes(header[32..36].try_into().map_err(|_| "invalid protected staging length")?) as u64;
        total = total.checked_add(size).ok_or("protected staging input overflow")?;
        if total > 8 * 1024 * 1024 { return Err("protected staging input limit".into()); }
        let file = write_path(&directory.join(format!(".pending-{id}")), size, &mut input)?;
        file.sync_all().map_err(|_| "protected staging sync unavailable")?;
    }
    if input.remaining != 0 { return Err("extra protected staging payload".into()); }
    drop(input);
    lease();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::{symlink, PermissionsExt};
    fn directory() -> std::path::PathBuf {
        let nonce = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
        let path = std::env::temp_dir().join(format!("ipse-allocation-{}-{nonce}", std::process::id()));
        fs::create_dir(&path).unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
        fs::canonicalize(path).unwrap()
    }
    #[test]
    fn includes_directory_and_file_blocks() {
        let path = directory();
        let file = path.join("value");
        fs::write(&file, b"bounded bytes").unwrap();
        fs::set_permissions(&file, fs::Permissions::from_mode(0o600)).unwrap();
        let usage = inspect(&path).unwrap();
        assert_eq!(usage.entries, 2);
        assert_eq!(usage.allocated, (fs::metadata(&path).unwrap().blocks() + fs::metadata(&file).unwrap().blocks()) * 512);
        assert_eq!(usage.logical, fs::metadata(&path).unwrap().len() + 13);
        fs::remove_dir_all(path).unwrap();
    }
    #[test]
    fn rejects_links_modes_and_noncanonical_roots() {
        let path = directory();
        let file = path.join("value");
        fs::write(&file, b"x").unwrap();
        fs::set_permissions(&file, fs::Permissions::from_mode(0o600)).unwrap();
        let link = path.join("link");
        fs::hard_link(&file, &link).unwrap();
        assert!(inspect(&path).is_err());
        fs::remove_file(&link).unwrap();
        symlink(&file, &link).unwrap();
        assert!(inspect(&path).is_err());
        fs::remove_file(&link).unwrap();
        fs::set_permissions(&file, fs::Permissions::from_mode(0o644)).unwrap();
        assert!(inspect(&path).is_err());
        assert!(inspect(&path.join(".")).is_err());
        fs::remove_dir_all(path).unwrap();
    }
    #[test]
    fn rejects_excessive_depth() {
        let path = directory();
        let mut deep = path.clone();
        for _ in 0..6 {
            deep = deep.join("d"); fs::create_dir(&deep).unwrap();
            fs::set_permissions(&deep, fs::Permissions::from_mode(0o700)).unwrap();
        }
        assert!(inspect(&path).is_err());
        fs::remove_dir_all(path).unwrap();
    }
    #[test]
    fn staging_is_exclusive_private_bounded_and_retains_partial_unknown_bytes() {
        let path = directory();
        let file = path.join(".pending-00000000000000000000000000000000");
        let staged = write_path(&file, 3, &mut &b"abc"[..]).unwrap();
        staged.sync_all().unwrap();
        assert_eq!(fs::read(&file).unwrap(), b"abc");
        assert_eq!(fs::metadata(&file).unwrap().mode() & 0o777, 0o600);
        assert!(write_path(&file, 3, &mut &b"def"[..]).is_err());
        let partial = path.join(".pending-11111111111111111111111111111111");
        assert!(write_path(&partial, 4, &mut &b"x"[..]).is_err());
        assert_eq!(fs::read(&partial).unwrap(), b"x");
        assert_eq!(fs::metadata(&partial).unwrap().mode() & 0o077, 0);
        assert!(write_path(&path.join("ordinary"), 1, &mut &b"x"[..]).is_err());
        assert!(write_path(&path.join(".pending-22222222222222222222222222222222"), 8 * 1024 * 1024 + 1, &mut &b"x"[..]).is_err());
        let empty = path.join(".pending-33333333333333333333333333333333");
        assert!(write_path(&empty, 1, &mut &b""[..]).is_err());
        assert!(!empty.exists());
        fs::remove_dir_all(path).unwrap();
    }

    #[test]
    fn writer_lease_retains_inode_and_excludes_another_open() {
        let path = directory();
        let held = writer_lease(&path).unwrap();
        let inode = held.metadata().unwrap().ino();
        assert!(writer_lease(&path).is_err());
        drop(held);
        let next = writer_lease(&path).unwrap();
        assert_eq!(next.metadata().unwrap().ino(), inode);
        drop(next);
        fs::remove_dir_all(path).unwrap();
    }
    #[test]
    fn supported_preflight_reserves_before_creating_any_staging_file() {
        let path = directory();
        let before = inspect(&path).unwrap().allocated;
        match transaction_preflight(&path, &[6144], before + 1) {
            Err(TransactionAllowanceError::Unsupported) => (),
            result => {
                assert_eq!(result, Err(TransactionAllowanceError::Capacity));
                assert!(transaction_preflight(&path, &[6144], before + 131_072).is_ok());
                assert!(transaction_preflight(&path, &[], before.max(1)).is_ok());
                assert_eq!(fs::read_dir(&path).unwrap().count(), 0);
                assert_eq!(inspect(&path).unwrap().allocated, before);
            }
        }
        fs::remove_dir_all(path).unwrap();
    }
}
