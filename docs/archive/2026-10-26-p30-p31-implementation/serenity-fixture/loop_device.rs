//! Proposed Linux loop-control adapter, currently unreachable from main.
//! Host-global device creation is destructive to the global namespace. The
//! caller MUST first durably journal pending, prove private /dev and mount
//! namespace, cap device cgroup to the exact 7:minor and validate no existing
//! device; `add` failure is unknown, not permission to remove anything.
use std::fs::{self, OpenOptions};
use std::io;
use std::os::unix::fs::{FileTypeExt, MetadataExt};
use std::os::fd::AsRawFd;
use std::ffi::{c_int, c_ulong};
use std::path::{Path,PathBuf};

const LOOP_CTL_ADD: c_ulong = 0x4c80;
const LOOP_CTL_REMOVE: c_ulong = 0x4c81;
const S_IFBLK: u32 = 0o060000;
unsafe extern "C" { fn ioctl(fd:c_int, request:c_ulong, ...)->c_int; fn mknod(path:*const i8, mode:u32, device:u64)->c_int; }

fn number(major:u64,minor:u64)->u64 {
    ((major & 0xfff) << 8) | ((major & 0xffff_f000) << 32) |
    (minor & 0xff) | ((minor & 0xffff_ff00) << 12)
}
fn node(minor:u64)->Option<PathBuf> {
    if minor > 4095 { return None; }
    Some(PathBuf::from(format!("/dev/loop{minor}")))
}
fn local_control() -> io::Result<std::fs::File> {
    let path=Path::new("/dev/loop-control");
    let named=fs::symlink_metadata(path)?;
    if !named.file_type().is_char_device() || named.rdev()!=number(10,237) {
        return Err(io::Error::other("unexpected loop control"));
    }
    let file=OpenOptions::new().read(true).write(true).open(path)?;
    let held=file.metadata()?;
    if held.dev()!=named.dev() || held.ino()!=named.ino() || held.rdev()!=named.rdev() {
        return Err(io::Error::other("loop control changed"));
    }
    Ok(file)
}
/// Unreachable in current executable. A successful ioctl requires a separate
/// durable created-record before any subsequent action; if interrupted earlier,
/// do not assume ownership or remove the device automatically.
fn add(minor:u64) -> io::Result<PathBuf> {
    let path=node(minor).ok_or_else(||io::Error::other("loop minor bound"))?;
    match fs::symlink_metadata(&path) {
        Err(e) if e.kind()==io::ErrorKind::NotFound => (),
        _ => return Err(io::Error::other("device node exists or unavailable")),
    }
    let control=local_control()?;
    // Opening loop-control can autoload the host-global module. Inspect its
    // partition parameter before creating an index; no loop creation on an
    // unsupported numbering profile. Module loading itself remains a host effect.
    let part=fs::read_to_string("/sys/module/loop/parameters/max_part")?;
    if part.trim()!="0" { return Err(io::Error::other("unsupported loop partition shift")); }
    let result=unsafe { ioctl(control.as_raw_fd(),LOOP_CTL_ADD,minor as c_ulong) };
    if result < 0 { return Err(io::Error::last_os_error()); }
    if result as u64 != minor { return Err(io::Error::other("unexpected allocated loop")); }
    let part=fs::read_to_string("/sys/module/loop/parameters/max_part")?;
    if part.trim()!="0" { return Err(io::Error::other("loop partition profile changed after add")); }
    let cpath=std::ffi::CString::new(path.as_os_str().as_encoded_bytes())
        .map_err(|_|io::Error::other("invalid path"))?;
    if unsafe { mknod(cpath.as_ptr(),S_IFBLK | 0o600,number(7,minor)) } != 0 {
        return Err(io::Error::last_os_error());
    }
    let metadata=fs::symlink_metadata(&path)?;
    if !metadata.file_type().is_block_device() || metadata.rdev()!=number(7,minor) {
        return Err(io::Error::other("created loop node identity changed"));
    }
    Ok(path)
}
/// Unreachable in current executable. The controller must prove successful
/// detach, no holders, and exact original created-record before this ioctl.
fn remove(minor:u64) -> io::Result<()> {
    let control=local_control()?;
    if node(minor).is_none() {return Err(io::Error::other("loop minor bound"));}
    let result=unsafe { ioctl(control.as_raw_fd(),LOOP_CTL_REMOVE,minor as c_ulong) };
    if result==0 {Ok(())} else if result<0 {Err(io::Error::last_os_error())}
    else {Err(io::Error::other("unexpected loop remove result"))}
}
#[cfg(test)] mod tests {
    use super::*;
    #[test] fn linux_dev_numbers_and_name_bounds() {
        assert_eq!(number(7,42),0x72a); assert_eq!(number(10,237),0xaed);
        assert_eq!(node(42).unwrap(),PathBuf::from("/dev/loop42"));
        assert!(node(4096).is_none());
    }
}
