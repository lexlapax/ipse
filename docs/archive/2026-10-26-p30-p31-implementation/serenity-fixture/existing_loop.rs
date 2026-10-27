//! Source-only existing-index loop prototype; no entrypoint or live execution.
//! The caller must durably record provenance and contain the exact backing FD.
//! Never removes the global index. Unproven detach remains unknown.
use std::fs::{self,File,OpenOptions};
use std::io;
use std::os::fd::{AsRawFd,IntoRawFd};
use std::os::unix::fs::{FileTypeExt,MetadataExt,OpenOptionsExt};
use std::path::Path;
unsafe extern "C"{fn ioctl(fd:i32,req:u64,...)->i32;fn close(fd:i32)->i32;fn fcntl(fd:i32,cmd:i32,...)->i32;fn syscall(n:i64,...)->i64;}
const CONFIGURE:u64=0x4c0a;const GET_STATUS:u64=0x4c05;const CLEAR:u64=0x4c01;const AUTO_CLEAR:u32=4;
#[repr(C)]#[derive(Clone,Copy)]struct LoopInfo{device:u64,inode:u64,rdevice:u64,offset:u64,sizelimit:u64,number:u32,encrypt_type:u32,encrypt_key_size:u32,flags:u32,file_name:[u8;64],crypt_name:[u8;64],encrypt_key:[u8;32],init:[u64;2]}
#[repr(C)]struct LoopConfig{fd:u32,block_size:u32,info:LoopInfo,reserved:[u64;8]}
fn zero_info()->LoopInfo{unsafe{std::mem::zeroed()}}
fn device(major:u64,minor:u64)->u64{((major&0xfff)<<8)|((major&0xffff_f000)<<32)|(minor&0xff)|((minor&0xffff_ff00)<<12)}
// This is only evidence of the observed same-FD rundown transition. Kernel
// build parity, complete scope cleanup and final backing release are separate.
pub(super) struct Rundown {owner:Existing}
pub(super) struct CloseAttempted {_private:()}
// Local FD scan only: it does not rule out other processes or kernel refs.
fn no_local_aliases(file:&File)->io::Result<()> {
 let expected=file.metadata()?;let fd=file.as_raw_fd();let flags=unsafe{fcntl(fd,1)};if flags<0 || flags&1==0{return Err(io::ErrorKind::PermissionDenied.into())}
 let mut seen=0usize;for e in fs::read_dir("/proc/self/fd")? {let e=e?;let m=fs::metadata(e.path())?;
  if (m.dev(),m.ino())==(expected.dev(),expected.ino()){seen+=1;if e.file_name().to_str().and_then(|s|s.parse::<i32>().ok())!=Some(fd){return Err(io::ErrorKind::PermissionDenied.into())}}
 }if seen==1{Ok(())}else{Err(io::ErrorKind::PermissionDenied.into())}
}
fn is_sysfs(fd:&File)->io::Result<bool> {if !cfg!(all(target_os="linux",target_arch="x86_64")){return Err(io::ErrorKind::Unsupported.into())}let mut stat=[0u64;16];if unsafe{syscall(138,fd.as_raw_fd(),stat.as_mut_ptr())}<0{return Err(io::Error::last_os_error())}Ok(stat[0]==0x62656572)}
pub(super) struct Existing {fd:File,sysroot:File,sys:File,minor:u32,node_dev:u64,node_inode:u64,sys_dev:u64,sys_inode:u64}
impl Existing {
 /// Opens only an index already visible in sysfs; it never opens loop-control
 /// and never calls GET_FREE, LOOP_CTL_ADD or LOOP_CTL_REMOVE. Caller must
 /// already know that the loop module is loaded, else opening may autoload it.
 pub(super) fn open_existing(minor:u32)->io::Result<Self>{
  let sysroot=File::open("/sys")?;let root_meta=sysroot.metadata()?;let named_root=fs::symlink_metadata("/sys")?;if !is_sysfs(&sysroot)? || (root_meta.dev(),root_meta.ino())!=(named_root.dev(),named_root.ino()){return Err(io::ErrorKind::PermissionDenied.into())}
  let root=format!("/proc/self/fd/{}",sysroot.as_raw_fd());
  if minor>4095||!Path::new(&format!("{root}/module/loop")).is_dir(){return Err(io::ErrorKind::PermissionDenied.into())}
  if fs::read_to_string(format!("{root}/module/loop/parameters/max_part"))?.trim()!="0"{return Err(io::ErrorKind::PermissionDenied.into())}
  let sys_file=File::open(format!("{root}/dev/block/7:{minor}"))?;let sys=sys_file.metadata()?;if !sys.is_dir(){return Err(io::ErrorKind::NotFound.into())}
  let path=format!("/dev/loop{minor}");let named=fs::symlink_metadata(&path)?;
  if !named.file_type().is_block_device()||named.rdev()!=device(7,minor as u64){return Err(io::ErrorKind::PermissionDenied.into())}
  let fd=OpenOptions::new().read(true).write(true).custom_flags(0x20000).open(&path)?;let held=fd.metadata()?;
  if (held.dev(),held.ino(),held.rdev())!=(named.dev(),named.ino(),named.rdev()){return Err(io::ErrorKind::PermissionDenied.into())}
  let sys_after=fs::metadata(format!("{root}/dev/block/7:{minor}"))?;if (sys.dev(),sys.ino())!=(sys_after.dev(),sys_after.ino()){return Err(io::ErrorKind::PermissionDenied.into())}
  Ok(Self{fd,sysroot,sys:sys_file,minor,node_dev:held.dev(),node_inode:held.ino(),sys_dev:sys.dev(),sys_inode:sys.ino()})
 }
 fn status(&self)->io::Result<LoopInfo>{let mut info=zero_info();if unsafe{ioctl(self.fd.as_raw_fd(),GET_STATUS,&mut info)}<0{Err(io::Error::last_os_error())}else{Ok(info)}}
 /// Atomic kernel-side configure: a concurrent binder yields EBUSY. A failure
 /// after attempting ioctl is always uncertain until exact identity is checked.
 pub(super) fn configure(&self,backing:&File,reference:&str)->io::Result<()> {
  if reference.is_empty()||reference.len()>63||!reference.bytes().all(|b|b.is_ascii_alphanumeric()||b==b'-'){return Err(io::ErrorKind::InvalidInput.into())}
  let node=self.fd.metadata()?;let sys=self.sys.metadata()?;let sys_named=fs::metadata(format!("/proc/self/fd/{}/dev/block/7:{}",self.sysroot.as_raw_fd(),self.minor))?;let b=backing.metadata()?;
  if (sys.dev(),sys.ino())!=(self.sys_dev,self.sys_inode)||(sys_named.dev(),sys_named.ino())!=(self.sys_dev,self.sys_inode){return Err(io::ErrorKind::PermissionDenied.into())}
  if (node.dev(),node.ino(),node.rdev())!=(self.node_dev,self.node_inode,device(7,self.minor as u64)) || !b.is_file()||b.nlink()!=1||b.len()!=536_870_912{return Err(io::ErrorKind::PermissionDenied.into())}
  match self.status(){Err(e) if e.raw_os_error()==Some(6)=>(),_=>return Err(io::ErrorKind::PermissionDenied.into())} // ENXIO only
  let mut info=zero_info();info.flags=AUTO_CLEAR;info.sizelimit=b.len();info.file_name[..reference.len()].copy_from_slice(reference.as_bytes());
  let config=LoopConfig{fd:u32::try_from(backing.as_raw_fd()).map_err(|_|io::ErrorKind::InvalidInput)?,block_size:0,info,reserved:[0;8]};
  if unsafe{ioctl(self.fd.as_raw_fd(),CONFIGURE,&config)}<0{return Err(io::Error::last_os_error())}
  let got=self.status()?;if got.device!=b.dev()||got.inode!=b.ino()||got.number!=self.minor||got.offset!=0||got.sizelimit!=b.len()||got.flags!=AUTO_CLEAR||got.file_name[..reference.len()]!=*reference.as_bytes()||got.file_name[reference.len()]!=0{return Err(io::ErrorKind::InvalidData.into())}Ok(())
 }
 /// Begin a source-derived single-opener protocol on the same held block FD.
 /// On failure the caller retains ownership for inspection; no retry occurs.
 pub(super) fn begin_rundown(self,backing:&File,reference:&str)->Result<Rundown,(Self,io::Error)> {
  let result=(||->io::Result<()> {
   let b=backing.metadata()?;let info=self.status()?;
   no_local_aliases(&self.fd)?;
   if reference.is_empty()||reference.len()>63||info.device!=b.dev()||info.inode!=b.ino()||info.number!=self.minor||info.offset!=0||info.sizelimit!=b.len()||info.flags!=AUTO_CLEAR||info.file_name[..reference.len()]!=*reference.as_bytes()||info.file_name[reference.len()]!=0{return Err(io::ErrorKind::PermissionDenied.into())}
   if unsafe{ioctl(self.fd.as_raw_fd(),CLEAR)}<0{return Err(io::Error::last_os_error())}
   match self.status(){Err(e) if e.raw_os_error()==Some(6)=>Ok(()),_=>Err(io::ErrorKind::Other.into())}
  })();
  match result {Ok(())=>Ok(Rundown{owner:self}),Err(e)=>Err((self,e))}
 }
 /// This ioctl may only schedule autoclear; success is NOT a detach receipt.
 fn request_clear(&self)->io::Result<()> {if unsafe{ioctl(self.fd.as_raw_fd(),CLEAR)}<0{Err(io::Error::last_os_error())}else{Ok(())}}
}
impl Rundown {
 /// A successful close is not labeled backing-release proof until kernel
 /// release/task-work semantics and the live test are independently reviewed.
 pub(super) fn close_attempt(self)->io::Result<CloseAttempted> {
  let fd=self.owner.fd.into_raw_fd();if unsafe{close(fd)}!=0{return Err(io::Error::last_os_error())}Ok(CloseAttempted{_private:()})
 }
}
#[cfg(test)]mod tests{use super::*;#[test]fn linux_abi_sizes_and_device_encoding(){assert_eq!(std::mem::size_of::<LoopInfo>(),232);assert_eq!(std::mem::size_of::<LoopConfig>(),304);assert_eq!(device(7,42),0x72a);assert_eq!(AUTO_CLEAR,4);}
 #[test]fn non_loop_ioctl_failure_is_not_treated_as_unbound(){let fd=File::open("/dev/null").unwrap();let sys=File::open("/sys").unwrap();let node=fd.metadata().unwrap();let sm=sys.metadata().unwrap();let sysroot=File::open("/sys").unwrap();let fake=Existing{fd,sysroot,sys,minor:0,node_dev:node.dev(),node_inode:node.ino(),sys_dev:sm.dev(),sys_inode:sm.ino()};assert_eq!(fake.status().err().and_then(|e|e.raw_os_error()),Some(25));}
 #[test]fn local_alias_and_unrelated_reopen_are_rejected(){let path=std::env::temp_dir().join(format!("ipse-fd-alias-{}",std::process::id()));let f=OpenOptions::new().write(true).create_new(true).mode(0o600).open(&path).unwrap();assert!(no_local_aliases(&f).is_ok());let duplicate=f.try_clone().unwrap();assert!(no_local_aliases(&f).is_err());drop(duplicate);let second=File::open(&path).unwrap();assert!(no_local_aliases(&f).is_err());drop(second);drop(f);fs::remove_file(path).unwrap();}
 #[test]fn ordinary_temp_directory_is_not_sysfs(){let sys=File::open("/sys").unwrap();let tmp=File::open(std::env::temp_dir()).unwrap();assert!(is_sysfs(&sys).unwrap());assert!(!is_sysfs(&tmp).unwrap());}
}
