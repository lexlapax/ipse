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
struct OwnedLoop {minor:u64,node:PathBuf,control:std::fs::File,sysfs:std::fs::File,node_dev:u64,node_ino:u64}
/// The handle exists only after creation and exact node inspection succeeded.
/// Losing it does not authorize recovery: durable provenance is still needed.

fn add(minor:u64) -> io::Result<OwnedLoop> {
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
    let sysfs=std::fs::File::open(format!("/sys/dev/block/7:{minor}"))?;
    if !sysfs.metadata()?.is_dir(){return Err(io::Error::other("loop sysfs identity unavailable"))}
    Ok(OwnedLoop{minor,node:path,control,sysfs,node_dev:metadata.dev(),node_ino:metadata.ino()})
}
/// Unreachable in current executable. The controller must prove successful
/// detach, no holders, and exact original created-record before this ioctl.
fn add_recorded(dir:&std::fs::File,run:&str,minor:u64)->io::Result<OwnedLoop>{
 // Caller must fsync a pending create intent before entering this function.
 // Any error after ioctl is unknown and must never trigger automatic removal.
 let owned=add(minor)?;owned.record_created(dir,run)?;Ok(owned)
}

impl OwnedLoop {
 fn record_created(&self,dir:&std::fs::File,run:&str)->io::Result<()> {
  let node=fs::symlink_metadata(&self.node)?;let control=self.control.metadata()?;
  if !node.file_type().is_block_device() || node.rdev()!=number(7,self.minor) ||
    (node.dev(),node.ino())!=(self.node_dev,self.node_ino) || !control.file_type().is_char_device() || control.rdev()!=number(10,237) {return Err(io::Error::other("owned loop or control identity changed"))}
  let sys=self.sysfs.metadata()?;let sys_named=fs::metadata(format!("/sys/dev/block/7:{}",self.minor))?;
  if !sys.is_dir() || (sys.dev(),sys.ino())!=(sys_named.dev(),sys_named.ino()){return Err(io::Error::other("loop sysfs changed"))}
  let boot=fs::read_to_string("/proc/sys/kernel/random/boot_id")?;if boot.len()>64 {return Err(io::Error::other("invalid boot id"))}
  let record=super::loop_provenance::Provenance {run:run.to_owned(),index:self.minor as u32,node_dev:node.dev(),node_inode:node.ino(),control_dev:control.dev(),control_inode:control.ino(),sys_dev:sys.dev(),sys_inode:sys.ino(),boot_id:boot.trim().to_owned()};
  super::loop_provenance::write_once(dir,&record)
 }
 fn remove_unbound(self)->io::Result<()> {
  let named=fs::symlink_metadata(&self.node)?;
  if !named.file_type().is_block_device() || named.rdev()!=number(7,self.minor) ||
    (named.dev(),named.ino())!=(self.node_dev,self.node_ino) {return Err(io::Error::other("owned loop node changed"))}
  let sys=self.sysfs.metadata()?;let current=fs::metadata(format!("/sys/dev/block/7:{}",self.minor))?;
  if (sys.dev(),sys.ino())!=(current.dev(),current.ino()){return Err(io::Error::other("owned loop sysfs changed"))}
  let result=unsafe {ioctl(self.control.as_raw_fd(),LOOP_CTL_REMOVE,self.minor as c_ulong)};
  if result==0 {Ok(())} else if result<0 {Err(io::Error::last_os_error())} else {Err(io::Error::other("unexpected loop remove result"))}
 }
}

pub(super) fn remove(minor:u64) -> io::Result<()> {
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
