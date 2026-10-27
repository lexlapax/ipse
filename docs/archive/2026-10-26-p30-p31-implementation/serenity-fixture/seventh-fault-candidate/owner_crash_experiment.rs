//! Harmless regular-file crash experiment. It does not access devices and does
//! not assert loop release, mount quiescence, crash durability or recovery.
#[cfg(test)] mod tests {
 use std::ffi::CString;use std::fs::{self,OpenOptions};use std::io::{Read,Write};use std::os::fd::AsRawFd;use std::os::unix::ffi::OsStrExt;use std::os::unix::fs::{OpenOptionsExt,PermissionsExt};
 unsafe extern "C" {fn fork()->i32;fn pipe(p:*mut i32)->i32;fn open(path:*const i8,flags:i32,...)->i32;fn flock(fd:i32,operation:i32)->i32;fn write(fd:i32,p:*const std::ffi::c_void,n:usize)->isize;fn read(fd:i32,p:*mut std::ffi::c_void,n:usize)->isize;fn close(fd:i32)->i32;fn kill(pid:i32,sig:i32)->i32;fn waitpid(pid:i32,status:*mut i32,opts:i32)->i32;fn _exit(status:i32)->!;}
 #[repr(C)]struct PollFd{fd:i32,events:i16,revents:i16}
 unsafe extern "C" {fn poll(f:*mut PollFd,n:usize,timeout:i32)->i32;}
 struct Child(i32);impl Drop for Child {fn drop(&mut self){if self.0>0 {unsafe{kill(self.0,9);let mut status=0;waitpid(self.0,&mut status,0);}}}}
 #[test]fn killed_owner_leaves_pending_record_and_releases_its_regular_file_lock(){
  let dir=std::env::temp_dir().join(format!("ipse-owner-crash-{}",std::process::id()));fs::create_dir(&dir).unwrap();fs::set_permissions(&dir,fs::Permissions::from_mode(0o700)).unwrap();
  let file=dir.join("fixture");let ledger=dir.join("ledger");let mut f=OpenOptions::new().write(true).create_new(true).mode(0o600).open(&file).unwrap();f.write_all(b"sentinel").unwrap();f.sync_all().unwrap();drop(f);
  let mut l=OpenOptions::new().write(true).create_new(true).mode(0o600).open(&ledger).unwrap();l.write_all(b"setup-pending\n").unwrap();l.sync_all().unwrap();std::fs::File::open(&dir).unwrap().sync_all().unwrap();drop(l);
  let name=CString::new(file.as_os_str().as_bytes()).unwrap();let mut signal=[0i32;2];let mut gate=[0i32;2];assert_eq!(unsafe{pipe(signal.as_mut_ptr())},0);assert_eq!(unsafe{pipe(gate.as_mut_ptr())},0);
  let pid=unsafe{fork()};assert!(pid>=0);if pid==0 {unsafe{close(signal[0]);close(gate[1]);let fd=open(name.as_ptr(),0x80000|0x20000);if fd<0 || flock(fd,2|4)!=0{_exit(2)}let b=[b'R'];if write(signal[1],b.as_ptr().cast(),1)!=1{_exit(3)}let mut wait=[0u8];let _=read(gate[0],wait.as_mut_ptr().cast(),1);_exit(4)}}
  let mut child=Child(pid);unsafe{close(signal[1]);close(gate[0]);}let mut pollfd=PollFd{fd:signal[0],events:1,revents:0};assert_eq!(unsafe{poll(&mut pollfd,1,3000)},1);let mut ready=[0u8];assert_eq!(unsafe{read(signal[0],ready.as_mut_ptr().cast(),1)},1);assert_eq!(ready,[b'R']);
  let held=OpenOptions::new().read(true).open(&file).unwrap();assert_eq!(unsafe{flock(held.as_raw_fd(),2|4)},-1);assert_eq!(std::io::Error::last_os_error().raw_os_error(),Some(11));
  assert_eq!(unsafe{kill(pid,9)},0);let mut status=0;assert_eq!(unsafe{waitpid(pid,&mut status,0)},pid);child.0=0;assert_eq!(status&0x7f,9);
  assert_eq!(unsafe{flock(held.as_raw_fd(),2|4)},0);let mut content=String::new();std::fs::File::open(&file).unwrap().read_to_string(&mut content).unwrap();assert_eq!(content,"sentinel");assert_eq!(fs::read(&ledger).unwrap(),b"setup-pending\n");
  drop(held);unsafe{close(signal[0]);close(gate[1]);}fs::remove_file(file).unwrap();fs::remove_file(ledger).unwrap();fs::remove_dir(dir).unwrap();
 }
}
