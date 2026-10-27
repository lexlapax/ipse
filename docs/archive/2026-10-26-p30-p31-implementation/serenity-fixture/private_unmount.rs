//! Disabled, namespace-scoped Btrfs cleanup prototype. No public token
//! constructor exists: cgroup/process/namespace quiescence is unimplemented.
//! This does not establish global mount absence or eliminate same-namespace
//! leaf replacement; it relies on a separately reviewed exclusion boundary.
use std::ffi::{CString,c_char,c_int};
use std::fs::{self,File,OpenOptions};
use std::io::{self,Read};
use std::os::fd::{AsRawFd,FromRawFd};
use std::os::unix::fs::{MetadataExt,OpenOptionsExt};
use std::path::Path;
unsafe extern "C"{fn openat(fd:c_int,path:*const c_char,flags:c_int,...)->c_int;fn umount2(path:*const c_char,flags:c_int)->c_int;}
#[derive(Debug,PartialEq,Eq)]struct Mount {id:u64,dev:String}
fn parse_mounts(text:&str)->io::Result<Option<Mount>> {
 let mut rows=Vec::new();
 for line in text.lines(){let (l,r)=line.split_once(" - ").ok_or(io::ErrorKind::InvalidData)?;let a:Vec<_>=l.split_whitespace().collect();let b:Vec<_>=r.split_whitespace().collect();if a.len()<6||b.len()<3{return Err(io::ErrorKind::InvalidData.into())}rows.push((a,b));}
 let mut selected=None;
 for (a,b) in &rows {if a[4]=="/work/mount" {if selected.is_some()||b[0]!="btrfs"||a[6..].iter().any(|s|s.starts_with("shared:")||s.starts_with("master:")||s.starts_with("propagate_from:")){return Err(io::ErrorKind::PermissionDenied.into())}selected=Some(Mount{id:a[0].parse().map_err(|_|io::ErrorKind::InvalidData)?,dev:a[2].into()});}}
 let Some(ref m)=selected else{return Ok(None)};
 if rows.iter().any(|(a,_)|a[4].starts_with("/work/mount/") || (a[2]==m.dev && a[4]!="/work/mount")){return Err(io::ErrorKind::PermissionDenied.into())}
 Ok(selected)
}
fn mountinfo()->io::Result<String>{let mut s=String::new();File::open("/proc/self/mountinfo")?.take(1_048_577).read_to_string(&mut s)?;if s.len()>1_048_576{return Err(io::ErrorKind::InvalidData.into())}Ok(s)}
fn target(parent:&File)->io::Result<File>{let name=c"mount";let fd=unsafe{openat(parent.as_raw_fd(),name.as_ptr(),0x10000|0x20000|0x80000)};if fd<0{Err(io::Error::last_os_error())}else{Ok(unsafe{File::from_raw_fd(fd)})}}
/// Intentionally has no production constructor. Must ultimately prove the
/// retained namespace, no privileged competitor, full cgroup quiescence and
/// no escaped namespace or mount FDs. Dummy values are allowed only in tests.
struct QuiescenceToken{_private:()}
pub(super) struct Guard {parent:File,parent_dev:u64,parent_inode:u64,namespace_inode:u64,fsid:[u8;16],mount_id:u64,mapper:(u32,u32)}
impl Guard {
 fn verify(&self)->io::Result<File>{
  let p=fs::symlink_metadata("/work")?;let held=self.parent.metadata()?;
  if (held.dev(),held.ino())!=(self.parent_dev,self.parent_inode)||(p.dev(),p.ino())!=(self.parent_dev,self.parent_inode)||fs::metadata("/proc/self/ns/mnt")?.ino()!=self.namespace_inode{return Err(io::ErrorKind::PermissionDenied.into())}
  let m=parse_mounts(&mountinfo()?)?.ok_or(io::ErrorKind::NotFound)?;if m.id!=self.mount_id{return Err(io::ErrorKind::PermissionDenied.into())}
  let f=target(&self.parent)?;let id=super::btrfs_identity::inspect(&f,Path::new("/sys"))?;
  if id.fsid!=self.fsid||id.mount_id!=self.mount_id||id.underlying!=self.mapper{return Err(io::ErrorKind::PermissionDenied.into())}Ok(f)
 }
 fn new(fsid:[u8;16],mount_id:u64,mapper:(u32,u32),namespace_inode:u64)->io::Result<Self>{
  if fsid==[0;16]||mount_id==0||namespace_inode==0{return Err(io::ErrorKind::InvalidInput.into())}
  let parent=OpenOptions::new().read(true).custom_flags(0x200000|0x10000|0x20000).open("/work")?;let p=parent.metadata()?;
  let g=Self{parent,parent_dev:p.dev(),parent_inode:p.ino(),namespace_inode,fsid,mount_id,mapper};drop(g.verify()?);Ok(g)
 }
 /// The caller must durably record exact unmount intent before invoking this.
 /// Failures are unknown, not permission to retry or proceed to mapper removal.
 fn unmount(self,_token:QuiescenceToken)->io::Result<()> {
  let mounted=self.verify()?;drop(mounted); // holding mount-root FD causes EBUSY
  let parent=fs::symlink_metadata("/work")?;if (parent.dev(),parent.ino())!=(self.parent_dev,self.parent_inode)||fs::metadata("/proc/self/ns/mnt")?.ino()!=self.namespace_inode{return Err(io::ErrorKind::PermissionDenied.into())}
  let path=CString::new(format!("/proc/self/fd/{}/mount",self.parent.as_raw_fd())).map_err(|_|io::ErrorKind::InvalidInput)?;
  if unsafe{umount2(path.as_ptr(),0)}!=0{return Err(io::Error::last_os_error())}
  if parse_mounts(&mountinfo()?)?.is_some(){return Err(io::ErrorKind::Other.into())}Ok(())
 }
}
#[cfg(test)]mod tests{use super::*;
 #[test]fn exact_private_mount_without_alias_or_submount(){let row="77 2 0:99 / /work/mount rw - btrfs /dev/dm-2 rw\n";assert_eq!(parse_mounts(row).unwrap(),Some(Mount{id:77,dev:"0:99".into()}));assert!(parse_mounts(&(row.to_owned()+"78 2 0:99 / /elsewhere rw - btrfs /dev/dm-2 rw\n")).is_err());assert!(parse_mounts(&(row.to_owned()+"79 77 0:55 / /work/mount/sub rw - tmpfs tmpfs rw\n")).is_err());assert!(parse_mounts(&row.replace("rw -", "rw shared:2 -")).is_err());assert!(parse_mounts(&row.replace("rw -", "rw master:3 -")).is_err());}
}
