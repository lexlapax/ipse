//! Private harmless test listener. It never touches block devices or changes a mapper.
//! This is not a live fault backend or recovery implementation.
use std::env;
use std::fs::{self,OpenOptions};
use std::io::{self,Read,Write};
use std::os::unix::fs::{MetadataExt,OpenOptionsExt};
use std::os::unix::io::{AsRawFd,FromRawFd};
use std::os::unix::net::UnixListener;
use std::time::{Duration,Instant};
#[repr(C)] struct Ucred {pid:i32,uid:u32,gid:u32}
#[repr(C)] struct PollFd {fd:i32,events:i16,revents:i16}
extern "C" {fn getsockopt(fd:i32,level:i32,opt:i32,value:*mut Ucred,len:*mut u32)->i32; fn syscall(num:i64,...)->i64; fn poll(fds:*mut PollFd,nfds:usize,timeout:i32)->i32; fn close(fd:i32)->i32; fn geteuid()->u32; fn read(fd:i32,buf:*mut std::ffi::c_void,count:usize)->isize; fn openat(fd:i32,path:*const i8,flags:i32,...)->i32;}
struct PidFd(i32);
impl Drop for PidFd {fn drop(&mut self){unsafe{close(self.0);}}}
fn live(fd:&PidFd)->bool {let mut p=PollFd{fd:fd.0,events:1,revents:0};unsafe{poll(&mut p,1,0)==0}}
fn same_namespace(pid:i32, namespace:&str)->io::Result<bool> {
 if !matches!(namespace,"pid"|"user"|"mnt") {return Err(io::ErrorKind::InvalidInput.into())}
 let own=fs::metadata(format!("/proc/self/ns/{namespace}"))?;let peer=fs::metadata(format!("/proc/{pid}/ns/{namespace}"))?;
 Ok((own.dev(),own.ino())==(peer.dev(),peer.ino()))
}
fn proc_stat(pid:i32)->io::Result<(i32,u64)> {
 let s=fs::read_to_string(format!("/proc/{pid}/stat"))?;
 let end=s.rfind(')').ok_or(io::ErrorKind::InvalidData)?;
 let fields:Vec<_>=s[end+1..].split_whitespace().collect();
 if fields.len()<20{return Err(io::ErrorKind::InvalidData.into())}
 Ok((fields[1].parse().map_err(|_|io::ErrorKind::InvalidData)?,fields[19].parse().map_err(|_|io::ErrorKind::InvalidData)?))
}
fn mount_id(pid:i32, fd:i32)->io::Result<u64> {
 let info=fs::read_to_string(format!("/proc/{pid}/fdinfo/{fd}"))?;
 let mut ids=info.lines().filter_map(|s|s.strip_prefix("mnt_id:\t"));
 let id=ids.next().ok_or(io::ErrorKind::InvalidData)?.parse().map_err(|_|io::ErrorKind::InvalidData)?;
 if ids.next().is_some(){return Err(io::ErrorKind::InvalidData.into())}Ok(id)
}
fn peer_owns_file(pid:i32,file:&std::fs::File)->io::Result<bool> {
 let expected=file.metadata()?;let mount=mount_id(std::process::id() as i32,file.as_raw_fd())?;let mut count=0;
 for entry in fs::read_dir(format!("/proc/{pid}/fd"))? {
  let entry=entry?;let name=entry.file_name();let fd:i32=name.to_str().ok_or(io::ErrorKind::InvalidData)?.parse().map_err(|_|io::ErrorKind::InvalidData)?;
  let metadata=fs::metadata(entry.path())?;
  if metadata.dev()==expected.dev() && metadata.ino()==expected.ino() {if mount_id(pid,fd)? != mount {return Ok(false)} count+=1;}
 } Ok(count==1)
}
fn control_line()->io::Result<String> {
 let deadline=Instant::now()+Duration::from_secs(3);let mut bytes=Vec::new();
 loop {let left=deadline.saturating_duration_since(Instant::now());if left.is_zero(){return Err(io::ErrorKind::TimedOut.into())}
  let mut fd=PollFd{fd:0,events:1,revents:0};if unsafe{poll(&mut fd,1,left.as_millis().min(3000) as i32)}!=1 {return Err(io::ErrorKind::TimedOut.into())}
  let mut byte=[0];if unsafe{read(0,byte.as_mut_ptr().cast(),1)}!=1 {return Err(io::ErrorKind::UnexpectedEof.into())}if byte[0]==b'\n'{break}if !(byte[0].is_ascii_digit() || byte[0]==b'G') || bytes.len()>=10{return Err(io::ErrorKind::InvalidData.into())}bytes.push(byte[0]);
 } String::from_utf8(bytes).map_err(|_|io::ErrorKind::InvalidData.into())
}
fn main()->io::Result<()> {
 let args:Vec<_>=env::args().collect();if args.len()!=4{return Err(io::ErrorKind::InvalidInput.into())}
 let path=&args[1];let root=&args[2];let helper=&args[3];
 if path!="/tmp/ipse-stage-gate-review/control.sock" || helper!="/tmp/ipse-stage-gate-review/build/lib/ipse/priv/ipse-runner" || !root.strip_prefix("/tmp/ipse-stage-gate-review/").is_some_and(|s| !s.is_empty() && s.len()<=64 && s.bytes().all(|b|b.is_ascii_lowercase()||b.is_ascii_digit()||b==b'-')) {return Err(io::ErrorKind::PermissionDenied.into())}
 let base=fs::symlink_metadata("/tmp/ipse-stage-gate-review")?;if !base.is_dir() || base.uid()!=unsafe{geteuid()} || base.mode()&0o777!=0o700 {return Err(io::ErrorKind::PermissionDenied.into())}
 let root_m=fs::symlink_metadata(root)?; if !root_m.is_dir() || root_m.mode()&0o777!=0o700 || root_m.uid()!=unsafe{geteuid()} {return Err(io::ErrorKind::PermissionDenied.into())}
 let root_fd=OpenOptions::new().read(true).custom_flags(0x30000).open(root)?;let root_open=root_fd.metadata()?;
 if (root_open.dev(),root_open.ino())!=(root_m.dev(),root_m.ino()) {return Err(io::ErrorKind::PermissionDenied.into())}
 let executable=fs::metadata(helper)?; let listener=UnixListener::bind(path)?;
 println!("LISTENING");io::stdout().flush()?;
 listener.set_nonblocking(true)?;let deadline=Instant::now()+Duration::from_secs(5);
 let (mut peer,_)=loop {match listener.accept(){Ok(v)=>break v,Err(e) if e.kind()==io::ErrorKind::WouldBlock && Instant::now()<deadline=>std::thread::sleep(Duration::from_millis(10)),Err(e)=>return Err(e)}}; peer.set_read_timeout(Some(Duration::from_secs(5)))?;peer.set_write_timeout(Some(Duration::from_secs(5)))?;
 let mut c=Ucred{pid:0,uid:0,gid:0};let mut len=std::mem::size_of::<Ucred>() as u32;
 if unsafe{getsockopt(peer.as_raw_fd(),1,17,&mut c,&mut len)}!=0 || len as usize!=std::mem::size_of::<Ucred>() || c.pid<=0 || c.uid!=unsafe{geteuid()} {return Err(io::ErrorKind::PermissionDenied.into())}
 let first=proc_stat(c.pid)?;let raw=unsafe{syscall(434,c.pid,0)};if raw<0{return Err(io::Error::last_os_error())}let pinned=PidFd(raw as i32);
 if !same_namespace(c.pid,"pid")? || !same_namespace(c.pid,"user")? || !same_namespace(c.pid,"mnt")? || !live(&pinned) || proc_stat(c.pid)?!=first{return Err(io::ErrorKind::PermissionDenied.into())}
 let exe=fs::metadata(format!("/proc/{}/exe",c.pid))?;
 if (exe.dev(),exe.ino())!=(executable.dev(),executable.ino()){return Err(io::ErrorKind::PermissionDenied.into())}
 let mut ready=[0];peer.read_exact(&mut ready)?;if ready!=*b"R"{return Err(io::ErrorKind::InvalidData.into())}
 let pending=format!("{root}/.pending-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
 let name=std::ffi::CString::new(".pending-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb").unwrap();
 let rawfile=unsafe{openat(root_fd.as_raw_fd(),name.as_ptr(),0x20000)};if rawfile<0{return Err(io::Error::last_os_error())}let file=unsafe{std::fs::File::from_raw_fd(rawfile)};
 let before=file.metadata()?;let named=fs::symlink_metadata(&pending)?;
 if !before.is_file() || before.uid()!=c.uid || before.nlink()!=1 || before.len()==0 || before.len()>=65536 || (before.dev(),before.ino())!=(named.dev(),named.ino()){return Err(io::ErrorKind::PermissionDenied.into())}
 println!("READY {} {} {} {} {}",c.pid,first.1,before.dev(),before.ino(),before.len());io::stdout().flush()?;
 let expected_parent:i32=control_line()?.parse().map_err(|_|io::ErrorKind::InvalidData)?;
 let parent_first=proc_stat(expected_parent)?;let parent_raw=unsafe{syscall(434,expected_parent,0)};if parent_raw<0{return Err(io::Error::last_os_error())}let parent_pin=PidFd(parent_raw as i32);
 if !same_namespace(expected_parent,"pid")? || !same_namespace(expected_parent,"user")? || !same_namespace(expected_parent,"mnt")? || !live(&parent_pin)||proc_stat(expected_parent)?!=parent_first{return Err(io::ErrorKind::PermissionDenied.into())}
 if first.0!=expected_parent || !peer_owns_file(c.pid,&file)? {return Err(io::ErrorKind::PermissionDenied.into())}
 println!("VERIFIED");io::stdout().flush()?;if control_line()? != "G" {return Err(io::ErrorKind::PermissionDenied.into())}
 let after=file.metadata()?;let named=fs::symlink_metadata(&pending)?;
 let root_after=fs::symlink_metadata(root)?;let exe_after=fs::metadata(format!("/proc/{}/exe",c.pid))?;
 if (root_after.dev(),root_after.ino())!=(root_open.dev(),root_open.ino()) || (exe_after.dev(),exe_after.ino())!=(executable.dev(),executable.ino()) {return Err(io::ErrorKind::PermissionDenied.into())}
 if !same_namespace(c.pid,"pid")? || !same_namespace(c.pid,"user")? || !same_namespace(c.pid,"mnt")? || !same_namespace(expected_parent,"pid")? || !same_namespace(expected_parent,"user")? || !same_namespace(expected_parent,"mnt")? || !live(&parent_pin) || proc_stat(expected_parent)?!=parent_first || !peer_owns_file(c.pid,&file)? || expected_parent<=0 || first.0!=expected_parent || !live(&pinned) || proc_stat(c.pid)?!=first ||
    (after.dev(),after.ino(),after.len(),after.nlink())!=(before.dev(),before.ino(),before.len(),1) ||
    (named.dev(),named.ino())!=(before.dev(),before.ino()) {return Err(io::ErrorKind::PermissionDenied.into())}
 peer.write_all(b"G")?;
 let mut write=[0u8;5];peer.read_exact(&mut write)?;if write[0]!=b'W'{return Err(io::ErrorKind::InvalidData.into())}
 let w=i32::from_be_bytes(write[1..5].try_into().map_err(|_|io::ErrorKind::InvalidData)?);
 if w<0 {return Err(io::ErrorKind::InvalidData.into())}
 if w>0 {let mut trailing=[0];if peer.read(&mut trailing)?!=0{return Err(io::ErrorKind::InvalidData.into())}println!("REPORT W={w}");io::stdout().flush()?;return Ok(())}
 let mut sync=[0u8;5];peer.read_exact(&mut sync)?;if sync[0]!=b'S'{return Err(io::ErrorKind::InvalidData.into())}
 let s=i32::from_be_bytes(sync[1..5].try_into().map_err(|_|io::ErrorKind::InvalidData)?);
 if s<0 {return Err(io::ErrorKind::InvalidData.into())}let mut trailing=[0];if peer.read(&mut trailing)?!=0{return Err(io::ErrorKind::InvalidData.into())}
 println!("REPORT W=0 S={s}");io::stdout().flush()?;Ok(())
}
