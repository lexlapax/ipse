//! Harmless regular-file inotify diagnostic; no loop device interaction.
//! A close event identifies an inode, not the specific open file description.
use std::ffi::CString;
use std::fs::{self,File,OpenOptions};
use std::io::{self,Read};
use std::os::fd::{AsRawFd,FromRawFd};
use std::os::unix::fs::{MetadataExt,OpenOptionsExt};
use std::path::Path;
#[repr(C)]struct PollFd{fd:i32,events:i16,revents:i16}
unsafe extern "C"{fn inotify_init1(flags:i32)->i32;fn inotify_add_watch(fd:i32,path:*const i8,mask:u32)->i32;fn poll(fd:*mut PollFd,n:usize,t:i32)->i32;}
const CLOSE_WRITE:u32=0x8;const Q_OVERFLOW:u32=0x4000;const IGNORED:u32=0x8000;const UNMOUNT:u32=0x2000;const DELETE_SELF:u32=0x400;const MOVE_SELF:u32=0x800;const DONT_FOLLOW:u32=0x0200_0000;
fn parse_events(bytes:&[u8],expected:i32)->io::Result<usize>{let mut offset=0;let mut closes=0;while offset<bytes.len(){if bytes.len()-offset<16{return Err(io::ErrorKind::InvalidData.into())}let wd=i32::from_ne_bytes(bytes[offset..offset+4].try_into().unwrap());let mask=u32::from_ne_bytes(bytes[offset+4..offset+8].try_into().unwrap());let len=u32::from_ne_bytes(bytes[offset+12..offset+16].try_into().unwrap()) as usize;if len>bytes.len()-offset-16{return Err(io::ErrorKind::InvalidData.into())}if mask&(Q_OVERFLOW|IGNORED|UNMOUNT|DELETE_SELF|MOVE_SELF)!=0||wd!=expected||len!=0||mask!=CLOSE_WRITE{return Err(io::ErrorKind::Other.into())}closes+=1;offset+=16+len;}Ok(closes)}
struct Watch{fd:File,wd:i32,dev:u64,ino:u64}
impl Watch {
 fn arm(path:&Path)->io::Result<Self>{let before=fs::symlink_metadata(path)?;if !before.is_file()||before.nlink()!=1{return Err(io::ErrorKind::InvalidInput.into())}
  let raw=unsafe{inotify_init1(0x800|0x80000)};if raw<0{return Err(io::Error::last_os_error())}let fd=unsafe{File::from_raw_fd(raw)};let p=CString::new(path.as_os_str().as_encoded_bytes()).map_err(|_|io::ErrorKind::InvalidInput)?;
  let wd=unsafe{inotify_add_watch(fd.as_raw_fd(),p.as_ptr(),CLOSE_WRITE|UNMOUNT|DELETE_SELF|MOVE_SELF|DONT_FOLLOW)};if wd<0{return Err(io::Error::last_os_error())}
  let after=fs::symlink_metadata(path)?;if (before.dev(),before.ino())!=(after.dev(),after.ino()){return Err(io::ErrorKind::PermissionDenied.into())}
  Ok(Self{fd,wd,dev:before.dev(),ino:before.ino()})
 }
 fn events(&mut self,timeout_ms:i32)->io::Result<usize>{if !(0..=5000).contains(&timeout_ms){return Err(io::ErrorKind::InvalidInput.into())}let mut p=PollFd{fd:self.fd.as_raw_fd(),events:1,revents:0};let n=unsafe{poll(&mut p,1,timeout_ms)};if n<0{return Err(io::Error::last_os_error())}if n==0{return Ok(0)}if p.revents&1==0{return Err(io::ErrorKind::Other.into())}
  let mut bytes=[0u8;8192];let mut total=0usize;let mut closes=0usize;
  loop {match self.fd.read(&mut bytes) {
   Ok(0)=>return Err(io::ErrorKind::UnexpectedEof.into()),
   Ok(n)=>{total=total.checked_add(n).ok_or(io::ErrorKind::InvalidData)?;if total>131072{return Err(io::ErrorKind::InvalidData.into())}closes+=parse_events(&bytes[..n],self.wd)?;},
   Err(e) if e.kind()==io::ErrorKind::WouldBlock=>break,
   Err(e)=>return Err(e),
  }}
  Ok(closes)

 }
 fn same(&self,path:&Path)->bool{fs::symlink_metadata(path).is_ok_and(|m|m.is_file()&&m.nlink()==1&&(m.dev(),m.ino())==(self.dev,self.ino))}
}
#[cfg(test)]mod tests{use super::*;use std::os::unix::fs::PermissionsExt;
 #[test]fn duplicated_description_closes_once_but_unrelated_writer_is_indistinguishable(){let dir=std::env::temp_dir().join(format!("ipse-inotify-test-{}",std::process::id()));fs::create_dir(&dir).unwrap();fs::set_permissions(&dir,fs::Permissions::from_mode(0o700)).unwrap();let path=dir.join("synthetic");let created=OpenOptions::new().write(true).create_new(true).mode(0o600).open(&path).unwrap();drop(created);
  let mut watch=Watch::arm(&path).unwrap();let one=OpenOptions::new().write(true).open(&path).unwrap();let duplicate=one.try_clone().unwrap();drop(one);assert_eq!(watch.events(100).unwrap(),0);drop(duplicate);assert_eq!(watch.events(2000).unwrap(),1);assert!(watch.same(&path));
  let first=OpenOptions::new().write(true).open(&path).unwrap();let second=OpenOptions::new().write(true).open(&path).unwrap();drop(second);assert_eq!(watch.events(2000).unwrap(),1);drop(first);assert_eq!(watch.events(2000).unwrap(),1);drop(watch);fs::remove_file(path).unwrap();fs::remove_dir(dir).unwrap();
 }
 #[test]fn overflow_ignored_wrong_watch_and_truncated_records_are_unknown(){let mut event=[0u8;16];event[..4].copy_from_slice(&4i32.to_ne_bytes());event[4..8].copy_from_slice(&CLOSE_WRITE.to_ne_bytes());assert_eq!(parse_events(&event,4).unwrap(),1);assert!(parse_events(&event,3).is_err());assert!(parse_events(&event[..15],4).is_err());event[4..8].copy_from_slice(&Q_OVERFLOW.to_ne_bytes());assert!(parse_events(&event,4).is_err());event[4..8].copy_from_slice(&IGNORED.to_ne_bytes());assert!(parse_events(&event,4).is_err());}
}
