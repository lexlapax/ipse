//! Temporary tmpfs-only mount-FD diagnostic. Run only under an independently
//! created user+mount namespace after review. Never touches a block device.
use std::ffi::{CString,c_char,c_int,c_ulong,c_void};
use std::fs::{self,File,OpenOptions};
use std::io::{self,Read};
use std::os::fd::AsRawFd;
use std::os::unix::fs::{MetadataExt,OpenOptionsExt};
use std::time::{Duration,Instant};
#[repr(C)]struct PollFd{fd:i32,events:i16,revents:i16}
unsafe extern "C"{fn mount(src:*const c_char,target:*const c_char,kind:*const c_char,flags:c_ulong,data:*const c_void)->c_int;fn umount2(target:*const c_char,flags:c_int)->c_int;fn geteuid()->u32;fn read(fd:i32,buf:*mut c_void,count:usize)->isize;fn poll(fd:*mut PollFd,n:usize,t:i32)->i32;}
fn c(s:&str)->io::Result<CString>{CString::new(s).map_err(|_|io::ErrorKind::InvalidInput.into())}
fn read_info()->io::Result<String>{let mut s=String::new();File::open("/proc/self/mountinfo")?.take(1_048_577).read_to_string(&mut s)?;if s.len()>1_048_576{return Err(io::ErrorKind::InvalidData.into())}Ok(s)}
fn mount_entry(info:&str,target:&str)->io::Result<Option<u64>>{let mut found=None;for line in info.lines(){let (left,right)=line.split_once(" - ").ok_or(io::ErrorKind::InvalidData)?;let l:Vec<_>=left.split_whitespace().collect();let r:Vec<_>=right.split_whitespace().collect();if l.len()<6||r.len()<3{return Err(io::ErrorKind::InvalidData.into())}if l[4]==target{if found.is_some()||r[0]!="tmpfs"{return Err(io::ErrorKind::InvalidData.into())}found=Some(l[0].parse().map_err(|_|io::ErrorKind::InvalidData)?);}}Ok(found)}
fn run()->io::Result<()> {
 let args:Vec<_>=std::env::args().collect();if args.len()!=3{return Err(io::ErrorKind::InvalidInput.into())}
 let root=&args[1];let expected_ns:u64=args[2].parse().map_err(|_|io::ErrorKind::InvalidInput)?;
 if !root.strip_prefix("/tmp/ipse-umount-fd-").is_some_and(|s|s.len()==16&&s.bytes().all(|b|b.is_ascii_alphanumeric())) || expected_ns==0 || unsafe{geteuid()}!=0{return Err(io::ErrorKind::PermissionDenied.into())}
 let namespace=fs::metadata("/proc/self/ns/mnt")?.ino();if namespace==expected_ns{return Err(io::ErrorKind::PermissionDenied.into())}
 let meta=fs::symlink_metadata(root)?;if !meta.is_dir()||meta.uid()!=0||meta.mode()&0o777!=0o700||fs::read_dir(root)?.next().is_some()||mount_entry(&read_info()?,root)?.is_some(){return Err(io::ErrorKind::PermissionDenied.into())}
 let target_fd=OpenOptions::new().read(true).custom_flags(0x200000|0x10000|0x20000).open(root)?;let held=target_fd.metadata()?;if (held.dev(),held.ino())!=(meta.dev(),meta.ino()){return Err(io::ErrorKind::PermissionDenied.into())}
 let userns=fs::metadata("/proc/self/ns/user")?.ino();println!("READY {namespace} {userns}");
 let deadline=Instant::now()+Duration::from_secs(3);let mut gate=[0u8;3];
 for b in &mut gate {let left=deadline.saturating_duration_since(Instant::now());if left.is_zero(){return Err(io::ErrorKind::TimedOut.into())}let mut p=PollFd{fd:0,events:1,revents:0};if unsafe{poll(&mut p,1,left.as_millis().min(3000) as i32)}!=1{return Err(io::ErrorKind::TimedOut.into())}if unsafe{read(0,(b as *mut u8).cast(),1)}!=1{return Err(io::ErrorKind::UnexpectedEof.into())}}
 if gate!=*b"GO\n"{return Err(io::ErrorKind::PermissionDenied.into())}
 let slash=c("/")?;if unsafe{mount(std::ptr::null(),slash.as_ptr(),std::ptr::null(),(1<<18)|(1<<14),std::ptr::null())}!=0{return Err(io::Error::last_os_error())} // MS_REC|MS_PRIVATE
 if fs::metadata("/proc/self/ns/mnt")?.ino()!=namespace{return Err(io::ErrorKind::PermissionDenied.into())}
 let named=fs::symlink_metadata(root)?;if (named.dev(),named.ino())!=(held.dev(),held.ino()){return Err(io::ErrorKind::PermissionDenied.into())}
 let target=c(root)?;let source=c("none")?;let kind=c("tmpfs")?;let options=c("size=1048576,mode=0700")?;
 if unsafe{mount(source.as_ptr(),target.as_ptr(),kind.as_ptr(),2|4|8,options.as_ptr().cast())}!=0{return Err(io::Error::last_os_error())} // nosuid,nodev,noexec
 let observed=(||->io::Result<()> {
  let id=mount_entry(&read_info()?,root)?.ok_or(io::ErrorKind::NotFound)?;
  println!("PRIVATE_MOUNT namespace={namespace} mount_id={id}");
  let fd=OpenOptions::new().read(true).custom_flags(0x200000|0x10000|0x20000).open(root)?; // O_PATH|O_DIRECTORY|O_NOFOLLOW
  let fdinfo=fs::read_to_string(format!("/proc/self/fdinfo/{}",fd.as_raw_fd()))?;let ids:Vec<_>=fdinfo.lines().filter_map(|l|l.strip_prefix("mnt_id:\t")).collect();
  if ids.len()!=1||ids[0].parse::<u64>().ok()!=Some(id){return Err(io::ErrorKind::PermissionDenied.into())}
  let magic=c(&format!("/proc/self/fd/{}",fd.as_raw_fd()))?;let result=unsafe{umount2(magic.as_ptr(),0)};
  if result==0 {println!("retained-fd nonlazy umount: success");drop(fd);if mount_entry(&read_info()?,root)?.is_some(){return Err(io::ErrorKind::Other.into())}return Ok(())}
  let errno=io::Error::last_os_error().raw_os_error().unwrap_or(-1);println!("retained-fd nonlazy umount errno={errno}");drop(fd);
  if fs::metadata("/proc/self/ns/mnt")?.ino()!=namespace||mount_entry(&read_info()?,root)?!=Some(id){return Err(io::ErrorKind::PermissionDenied.into())}
  if unsafe{umount2(target.as_ptr(),0)}!=0{return Err(io::Error::last_os_error())}println!("exact private path nonlazy cleanup: success");
  if mount_entry(&read_info()?,root)?.is_some(){return Err(io::ErrorKind::Other.into())}Ok(())
 })();
 // On any error the parent must not interpret cleanup as proven. Exiting the
 // only member's private mount namespace is fallback, not an unmount receipt.
 observed
}
fn main(){if let Err(e)=run(){eprintln!("probe unknown: {e}");std::process::exit(1)}}
#[cfg(test)]mod tests{use super::*;#[test]fn exact_mount_parser_refuses_ambiguity_and_wrong_fs(){let one="42 1 0:9 / /tmp/fixture rw - tmpfs tmpfs rw\n";assert_eq!(mount_entry(one,"/tmp/fixture").unwrap(),Some(42));assert_eq!(mount_entry(one,"/other").unwrap(),None);assert!(mount_entry(&(one.to_owned()+one),"/tmp/fixture").is_err());assert!(mount_entry(&one.replace("tmpfs","btrfs"),"/tmp/fixture").is_err());}}
