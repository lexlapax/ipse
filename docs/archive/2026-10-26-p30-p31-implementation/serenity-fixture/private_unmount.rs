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
// `boundary` must come from independently attested namespace-root topology;
// an absent parent from a chroot-truncated view is not itself evidence.
fn parse_mounts(text:&str,boundary:u64,root_fd_id:u64)->io::Result<Option<Mount>> {
 if boundary==0||root_fd_id==0{return Err(io::ErrorKind::InvalidInput.into())}
 let mut rows=std::collections::HashMap::new();
 for line in text.lines(){
  let (l,r)=line.split_once(" - ").ok_or(io::ErrorKind::InvalidData)?;
  let a:Vec<_>=l.split_whitespace().collect();let b:Vec<_>=r.split_whitespace().collect();
  if a.len()<6||b.len()<3{return Err(io::ErrorKind::InvalidData.into())}
  let id=a[0].parse::<u64>().map_err(|_|io::ErrorKind::InvalidData)?;
  if id==0||rows.insert(id,(a,b)).is_some(){return Err(io::ErrorKind::InvalidData.into())}
 }
 let mut selected=None;
 for (id,(a,b)) in &rows {if a[4]=="/work/mount" {
  if selected.is_some()||b[0]!="btrfs"||a[6..].iter().any(|s|s.starts_with("shared:")||s.starts_with("master:")||s.starts_with("propagate_from:")){return Err(io::ErrorKind::PermissionDenied.into())}
  selected=Some(Mount{id:*id,dev:a[2].into()});
 }}
 let Some(ref m)=selected else{return Ok(None)};
 let selected_row=rows.get(&m.id).ok_or(io::ErrorKind::InvalidData)?;
 let mut ancestor=selected_row.0[1].parse::<u64>().map_err(|_|io::ErrorKind::InvalidData)?;
 let mut visited=std::collections::HashSet::new();let mut boundary_attested=false;
 for _ in 0..rows.len(){
  if !visited.insert(ancestor){return Err(io::ErrorKind::PermissionDenied.into())}
  let (a,_)=rows.get(&ancestor).ok_or(io::ErrorKind::PermissionDenied)?;
  if a[6..].iter().any(|s|s.starts_with("shared:")||s.starts_with("master:")||s.starts_with("propagate_from:")){return Err(io::ErrorKind::PermissionDenied.into())}
  let next=a[1].parse::<u64>().map_err(|_|io::ErrorKind::InvalidData)?;
  if next==boundary && !rows.contains_key(&next) && a[4]=="/" {boundary_attested=true;break}
  ancestor=next;
 }
 if !boundary_attested || !visited.contains(&root_fd_id){return Err(io::ErrorKind::PermissionDenied.into())}
 if rows.values().any(|(a,_)|a[4].starts_with("/work/mount/")||(a[2]==m.dev&&a[4]!="/work/mount")){return Err(io::ErrorKind::PermissionDenied.into())}
 Ok(selected)
}
fn mountinfo()->io::Result<String>{let mut s=String::new();File::open("/proc/self/mountinfo")?.take(1_048_577).read_to_string(&mut s)?;if s.len()>1_048_576{return Err(io::ErrorKind::InvalidData.into())}Ok(s)}
fn target(parent:&File)->io::Result<File>{let name=c"mount";let fd=unsafe{openat(parent.as_raw_fd(),name.as_ptr(),0x10000|0x20000|0x80000)};if fd<0{Err(io::Error::last_os_error())}else{Ok(unsafe{File::from_raw_fd(fd)})}}
/// Intentionally has no production constructor. Must ultimately prove the
/// retained namespace, no privileged competitor, full cgroup quiescence and
/// no escaped namespace or mount FDs. Dummy values are allowed only in tests.
struct QuiescenceToken{_private:()}
pub(super) struct Guard {parent:File,parent_dev:u64,parent_inode:u64,namespace_inode:u64,fsid:[u8;16],mount_id:u64,mapper:(u32,u32),namespace_root_boundary:u64,root_fd_id:u64,namespace_root:File}
impl Guard {
 fn verify(&self)->io::Result<File>{
  let p=fs::symlink_metadata("/work")?;let held=self.parent.metadata()?;
  let current_root=OpenOptions::new().read(true).custom_flags(0x200000|0x10000|0x20000).open("/")?;
  if super::btrfs_identity::mount_id(&self.namespace_root)?!=self.root_fd_id || super::btrfs_identity::mount_id(&current_root)?!=self.root_fd_id{return Err(io::ErrorKind::PermissionDenied.into())}
  if (held.dev(),held.ino())!=(self.parent_dev,self.parent_inode)||(p.dev(),p.ino())!=(self.parent_dev,self.parent_inode)||fs::metadata("/proc/self/ns/mnt")?.ino()!=self.namespace_inode{return Err(io::ErrorKind::PermissionDenied.into())}
  let m=parse_mounts(&mountinfo()?,self.namespace_root_boundary,self.root_fd_id)?.ok_or(io::ErrorKind::NotFound)?;if m.id!=self.mount_id{return Err(io::ErrorKind::PermissionDenied.into())}
  let f=target(&self.parent)?;let id=super::btrfs_identity::inspect(&f,Path::new("/sys"))?;
  if id.fsid!=self.fsid||id.mount_id!=self.mount_id||id.underlying!=self.mapper{return Err(io::ErrorKind::PermissionDenied.into())}Ok(f)
 }
 fn new(fsid:[u8;16],mount_id:u64,mapper:(u32,u32),namespace_inode:u64,namespace_root_boundary:u64,root_fd_id:u64)->io::Result<Self>{
  if fsid==[0;16]||mount_id==0||namespace_inode==0{return Err(io::ErrorKind::InvalidInput.into())}
  let parent=OpenOptions::new().read(true).custom_flags(0x200000|0x10000|0x20000).open("/work")?;let p=parent.metadata()?;
  let namespace_root=OpenOptions::new().read(true).custom_flags(0x200000|0x10000|0x20000).open("/")?;if super::btrfs_identity::mount_id(&namespace_root)?!=root_fd_id{return Err(io::ErrorKind::PermissionDenied.into())}
  let g=Self{parent,parent_dev:p.dev(),parent_inode:p.ino(),namespace_inode,fsid,mount_id,mapper,namespace_root_boundary,root_fd_id,namespace_root};drop(g.verify()?);Ok(g)
 }
 /// The caller must durably record exact unmount intent before invoking this.
 /// Failures are unknown, not permission to retry or proceed to mapper removal.
 fn unmount(self,_token:QuiescenceToken)->io::Result<()> {
  let mounted=self.verify()?;drop(mounted); // holding mount-root FD causes EBUSY
  let parent=fs::symlink_metadata("/work")?;if (parent.dev(),parent.ino())!=(self.parent_dev,self.parent_inode)||fs::metadata("/proc/self/ns/mnt")?.ino()!=self.namespace_inode{return Err(io::ErrorKind::PermissionDenied.into())}
  let path=CString::new(format!("/proc/self/fd/{}/mount",self.parent.as_raw_fd())).map_err(|_|io::ErrorKind::InvalidInput)?;
  if unsafe{umount2(path.as_ptr(),0)}!=0{return Err(io::Error::last_os_error())}
  if parse_mounts(&mountinfo()?,self.namespace_root_boundary,self.root_fd_id)?.is_some(){return Err(io::ErrorKind::Other.into())}Ok(())
 }
}
#[cfg(test)]mod tests{use super::*;
 #[test]fn held_process_root_id_must_be_in_attested_chain(){let row="2 1 0:50 / / rw - tmpfs tmpfs rw\n77 2 0:99 / /work/mount rw - btrfs /dev/dm-2 rw\n";assert!(parse_mounts(row,1,99).is_err());assert!(parse_mounts(row,1,2).is_ok());}
 #[test]fn private_chain_is_required_and_aliases_are_refused(){let row="2 1 0:50 / / rw - tmpfs tmpfs rw\n77 2 0:99 / /work/mount rw - btrfs /dev/dm-2 rw\n";assert_eq!(parse_mounts(row,1,2).unwrap(),Some(Mount{id:77,dev:"0:99".into()}));assert!(parse_mounts(&(row.to_owned()+"78 2 0:99 / /elsewhere rw - btrfs /dev/dm-2 rw\n"),1,2).is_err());assert!(parse_mounts(&(row.to_owned()+"79 77 0:55 / /work/mount/sub rw - tmpfs tmpfs rw\n"),1,2).is_err());assert!(parse_mounts(&row.replace("rw -", "rw shared:2 -"),1,2).is_err());assert!(parse_mounts(&row.replace("rw -", "rw master:3 -"),1,2).is_err());}
 #[test]fn stacked_root_shared_ancestor_missing_parent_duplicate_and_cycle_refuse(){
  let stacked="3 2 0:51 / / rw - tmpfs tmpfs rw\n2 1 0:50 / / rw shared:7 - tmpfs tmpfs rw\n77 3 0:99 / /work/mount rw - btrfs /dev/dm-2 rw\n";assert!(parse_mounts(stacked,1,3).is_err());
  let hidden="77 2 0:99 / /work/mount rw - btrfs /dev/dm-2 rw\n";assert!(parse_mounts(hidden,1,2).is_err());
  let duplicate="2 1 0:50 / / rw - tmpfs tmpfs rw\n2 1 0:51 / /other rw - tmpfs tmpfs rw\n77 2 0:99 / /work/mount rw - btrfs /dev/dm-2 rw\n";assert!(parse_mounts(duplicate,1,2).is_err());
  let cycle="2 3 0:50 / / rw - tmpfs tmpfs rw\n3 2 0:51 / / rw - tmpfs tmpfs rw\n77 2 0:99 / /work/mount rw - btrfs /dev/dm-2 rw\n";assert!(parse_mounts(cycle,1,2).is_err());
  let truncated="3 2 0:51 / / rw - tmpfs tmpfs rw\n77 3 0:99 / /work/mount rw - btrfs /dev/dm-2 rw\n";assert!(parse_mounts(truncated,1,3).is_err());
 }
}
