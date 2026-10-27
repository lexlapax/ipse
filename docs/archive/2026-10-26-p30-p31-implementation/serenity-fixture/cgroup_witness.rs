//! Read-only retained-parent witness prototype. No Docker or device actions.
//! Same PID/mount namespace and cgroup migration restrictions must be proven
//! separately. A hostile/root-equivalent host actor can invalidate the witness.
use std::fs::{self,File,OpenOptions};
use std::io::{self,Read};
use std::os::unix::fs::{MetadataExt,OpenOptionsExt};
use std::os::fd::{AsRawFd,FromRawFd};
use std::path::{Path,PathBuf};
#[repr(C)]struct PollFd {fd:i32,events:i16,revents:i16}
struct PidFd(i32);impl Drop for PidFd {fn drop(&mut self){unsafe{close(self.0);}}}
fn alive(fd:&PidFd)->bool {let mut p=PollFd{fd:fd.0,events:1,revents:0};unsafe{poll(&mut p,1,0)==0}}
#[repr(C)]struct StatFs {kind:i64,block:i64,blocks:u64,free:u64,available:u64,files:u64,files_free:u64,fsid:[i32;2],names:i64,fragment:i64,flags:i64,spare:[i64;4]}
extern "C"{fn openat(fd:i32,path:*const i8,flags:i32,...)->i32;fn fstatfs(fd:i32,buf:*mut StatFs)->i32;fn syscall(num:i64,...)->i64;fn poll(fd:*mut PollFd,n:usize,t:i32)->i32;fn close(fd:i32)->i32;}
fn read_named(dir:&File,name:&str)->io::Result<String>{
 let name=std::ffi::CString::new(name).map_err(|_|io::ErrorKind::InvalidInput)?;let fd=unsafe{openat(dir.as_raw_fd(),name.as_ptr(),0x20000|0x80000)};if fd<0{return Err(io::Error::last_os_error())}
 let mut bytes=Vec::new();unsafe{File::from_raw_fd(fd)}.take(4097).read_to_end(&mut bytes)?;if bytes.len()>4096{return Err(io::ErrorKind::InvalidData.into())}
 String::from_utf8(bytes).map_err(|_|io::ErrorKind::InvalidData.into())
}
fn populated(s:&str)->io::Result<bool>{let mut values=s.lines().filter_map(|line|line.strip_prefix("populated "));let one=values.next().ok_or(io::ErrorKind::InvalidData)?;if values.next().is_some(){return Err(io::ErrorKind::InvalidData.into())}match one{"0"=>Ok(false),"1"=>Ok(true),_=>Err(io::ErrorKind::InvalidData.into())}}
fn pid_start(pid:u32)->io::Result<u64>{let s=fs::read_to_string(format!("/proc/{pid}/stat"))?;let end=s.rfind(')').ok_or(io::ErrorKind::InvalidData)?;let fields:Vec<_>=s[end+1..].split_whitespace().collect();fields.get(19).ok_or(io::ErrorKind::InvalidData)?.parse().map_err(|_|io::ErrorKind::InvalidData.into())}
pub(super) struct Witness {parent:File,path:PathBuf,dev:u64,inode:u64,anchor:String,pid:u32,start:u64,anchor_dev:u64,anchor_inode:u64,anchor_fd:File,membership:String,pin:PidFd}
impl Witness {
 pub(super) fn retain(path:&Path,anchor_id:&str,pid:u32,start:u64)->io::Result<Self>{
  if anchor_id.len()!=64 || !anchor_id.bytes().all(|b|b.is_ascii_digit()||(b'a'..=b'f').contains(&b)) || pid==0 || start==0{return Err(io::ErrorKind::InvalidInput.into())}
  let parent=OpenOptions::new().read(true).custom_flags(0x30000).open(path)?;let m=parent.metadata()?;let named=fs::symlink_metadata(path)?;
  let mut stat=std::mem::MaybeUninit::<StatFs>::uninit();if unsafe{fstatfs(parent.as_raw_fd(),stat.as_mut_ptr())}!=0 || unsafe{stat.assume_init()}.kind!=0x63677270{return Err(io::ErrorKind::PermissionDenied.into())}
  if !m.is_dir()||(m.dev(),m.ino())!=(named.dev(),named.ino())||pid_start(pid)?!=start{return Err(io::ErrorKind::PermissionDenied.into())}
  let raw=unsafe{syscall(434,pid,0)};if raw<0{return Err(io::Error::last_os_error())}let pin=PidFd(raw as i32);if !alive(&pin)||pid_start(pid)?!=start{return Err(io::ErrorKind::PermissionDenied.into())}
  let relative=path.strip_prefix("/sys/fs/cgroup").map_err(|_|io::ErrorKind::PermissionDenied)?;
  let expected=format!("0::/{}/docker-{}.scope",relative.display(),anchor_id);
  let membership=fs::read_to_string(format!("/proc/{pid}/cgroup"))?;
  if membership.trim()!=expected || membership.lines().count()!=1{return Err(io::ErrorKind::PermissionDenied.into())}
  let anchor=format!("docker-{anchor_id}.scope");let c=std::ffi::CString::new(anchor.as_str()).unwrap();let raw=unsafe{openat(parent.as_raw_fd(),c.as_ptr(),0x30000|0x80000)};if raw<0{return Err(io::Error::last_os_error())}let anchor_fd=unsafe{File::from_raw_fd(raw)};let a=anchor_fd.metadata()?;
  if !a.is_dir(){return Err(io::ErrorKind::InvalidData.into())}
  Ok(Self{parent,path:path.to_owned(),dev:m.dev(),inode:m.ino(),anchor,pid,start,anchor_dev:a.dev(),anchor_inode:a.ino(),anchor_fd,membership:expected,pin})
 }
 pub(super) fn after_workload_exit(&self)->io::Result<()> {
  let same=||->io::Result<bool>{let m=fs::symlink_metadata(&self.path)?;let a=fs::symlink_metadata(self.path.join(&self.anchor))?;Ok((m.dev(),m.ino())==(self.dev,self.inode) && (a.dev(),a.ino())==(self.anchor_dev,self.anchor_inode))};
  if !alive(&self.pin)||!same()?||pid_start(self.pid)?!=self.start || fs::read_to_string(format!("/proc/{0}/cgroup",self.pid))?.trim()!=self.membership || !populated(&read_named(&self.parent,"cgroup.events")?)? || !read_named(&self.parent,"cgroup.procs")?.trim().is_empty() || !populated(&read_named(&self.anchor_fd,"cgroup.events")?)? {return Err(io::ErrorKind::PermissionDenied.into())}
  let pids=read_named(&self.anchor_fd,"cgroup.procs")?;let list:Vec<_>=pids.split_whitespace().collect();if list.len()!=1||list[0]!=self.pid.to_string(){return Err(io::ErrorKind::PermissionDenied.into())}
  for e in fs::read_dir(self.path.join(&self.anchor))? {if e?.file_type()?.is_dir(){return Err(io::ErrorKind::PermissionDenied.into())}}
  let mut dirs=Vec::new();for e in fs::read_dir(&self.path)? {let e=e?;if e.file_type()?.is_dir(){dirs.push(e.file_name().into_string().map_err(|_|io::ErrorKind::InvalidData)?);}}
  if dirs.len()!=1||dirs[0]!=self.anchor||!alive(&self.pin)||!same()?||pid_start(self.pid)?!=self.start || fs::read_to_string(format!("/proc/{0}/cgroup",self.pid))?.trim()!=self.membership {return Err(io::ErrorKind::PermissionDenied.into())}Ok(())
 }
}
#[cfg(test)]mod tests{use super::*;
 #[test]fn populated_parser_rejects_missing_duplicate_and_invalid(){assert_eq!(populated("populated 1\nfrozen 0\n").unwrap(),true);assert!(!populated("populated 0\n").unwrap());for s in ["", "populated 1\npopulated 1\n", "populated 2\n"]{assert!(populated(s).is_err());}}
 #[test]fn invalid_inputs_refuse_before_any_cgroup_access(){assert!(Witness::retain(Path::new("/nonexistent"),"x",1,1).is_err());assert!(Witness::retain(Path::new("/nonexistent"),&"a".repeat(64),0,1).is_err());}
 #[test]fn ordinary_directory_cannot_masquerade_as_retained_cgroup(){let path=std::env::temp_dir().join(format!("ipse-cgroup-test-{}",std::process::id()));fs::create_dir(&path).unwrap();let pid=std::process::id();let start=pid_start(pid).unwrap();assert!(Witness::retain(&path,&"a".repeat(64),pid,start).is_err());fs::remove_dir(path).unwrap();}
}
