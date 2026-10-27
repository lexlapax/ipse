//! Disabled single-process borrowed-loop owner. No live entry is enabled.
//! A separate supervisor must durably record all intent, own exact cgroups and
//! namespace, authenticate this process, and resolve errors as unknown.
#![allow(dead_code)]
#[path="existing_loop.rs"]mod existing_loop;
#[path="loop_owner_filter.rs"]mod loop_owner_filter;
use std::fs::{self,File,OpenOptions};use std::io::{self,Write};use std::os::unix::fs::{MetadataExt,OpenOptionsExt,FileTypeExt};use std::os::fd::{AsRawFd,FromRawFd};
const ENABLED:bool=false;
#[repr(C)]struct PollFd{fd:i32,events:i16,revents:i16}
unsafe extern "C"{fn poll(fd:*mut PollFd,n:usize,timeout:i32)->i32;fn read(fd:i32,buf:*mut std::ffi::c_void,n:usize)->isize;fn openat(fd:i32,path:*const i8,flags:i32,...)->i32;fn geteuid()->u32;fn fcntl(fd:i32,cmd:i32,...)->i32;}
fn run()->io::Result<()> {
 // Only an exact, narrowly scoped owner process can enter. This draft lacks
 // the attested launch/guardian, so the entrypoint remains disabled.
 if !ENABLED{return Err(io::Error::new(io::ErrorKind::PermissionDenied,"private loop owner disabled"))}
 let args:Vec<_>=std::env::args().collect();if args.len()!=5{return Err(io::ErrorKind::InvalidInput.into())}
 let minor:u32=args[1].parse().map_err(|_|io::ErrorKind::InvalidInput)?;let reference=&args[2];
 if reference.len()!=39||!reference.starts_with("ipse-q-")||!reference[7..].bytes().all(|b|b.is_ascii_digit()||(b'a'..=b'f').contains(&b)){return Err(io::ErrorKind::InvalidInput.into())}
 let expected_dev:u64=args[3].parse().map_err(|_|io::ErrorKind::InvalidInput)?;let expected_inode:u64=args[4].parse().map_err(|_|io::ErrorKind::InvalidInput)?;if expected_inode==0{return Err(io::ErrorKind::InvalidInput.into())}
 // The fresh single-thread process has no inherited extra FDs. Mark it
 // non-dumpable and apply the initial filter before acquisition; strict
 // no-open confinement follows acquisition.
 verify_initial_fds()?;
 verify_single_task()?;
 loop_owner_filter::install()?;
 let loop_device=existing_loop::Existing::open_existing(minor)?;
 let parent=OpenOptions::new().read(true).custom_flags(0x10000|0x20000).open("/work/fixture")?;let pm=parent.metadata()?;let pn=fs::symlink_metadata("/work/fixture")?;
 if !pm.is_dir()||pm.uid()!=unsafe{geteuid()}||pm.mode()&0o777!=0o700||(pm.dev(),pm.ino())!=(pn.dev(),pn.ino()){return Err(io::ErrorKind::PermissionDenied.into())}
 let name=c"backing.img";let raw=unsafe{openat(parent.as_raw_fd(),name.as_ptr(),0x2|0x20000|0x80000)};if raw<0{return Err(io::Error::last_os_error())}let backing=unsafe{File::from_raw_fd(raw)};
 let meta=backing.metadata()?;if !meta.is_file()||meta.nlink()!=1||meta.len()!=536_870_912||(meta.dev(),meta.ino())!=(expected_dev,expected_inode){return Err(io::ErrorKind::PermissionDenied.into())}
 // Reject any unexpected acquisition-time descriptor before confinement.
 let mut owned=loop_device.fd_numbers().to_vec();owned.extend([parent.as_raw_fd(),backing.as_raw_fd()]);verify_acquired_fds(&owned)?;
 // Scan local aliases, then irrevocably deny opening or duplicating FDs.
 // The process must terminate on partial filter-install failure.
 let loop_device=match loop_device.lock_down(){Ok(v)=>v,Err((_held,e))=>return Err(e)};
 // External supervisor must fsync exact pending intent before sending CONFIG.
 command(b'C')?;loop_device.configure(&backing,reference)?;report(b'B')?;
 // Supervisor must first end the staged owner, prove private namespace and
 // remove the exact mapper nondeferred; then durably journal CLEAR intent.
 command(b'R')?;
 let rundown=match loop_device.begin_rundown(&backing,reference){Ok(v)=>v,Err((_held,e))=>return Err(e)};
 // Close is attempted only once. Its return is not a detach receipt until
 // final-file-reference and running-build proof are independently accepted.
 command(b'X')?;let _attempt=rundown.close_attempt()?;report(b'C')?;
 // Retain backing until after close; no device index removal is ever attempted.
 drop(backing);Ok(())
}
fn verify_initial_fds()->io::Result<()> {
 for n in 0..=2 {if !fs::metadata(format!("/proc/self/fd/{n}"))?.file_type().is_fifo(){return Err(io::ErrorKind::PermissionDenied.into())}}
 let expected=format!("/proc/{}/fd",std::process::id());let mut scan_fd=0;
 for entry in fs::read_dir("/proc/self/fd")? {let entry=entry?;let name=entry.file_name();let n=name.to_str().ok_or(io::ErrorKind::InvalidData)?.parse::<u32>().map_err(|_|io::ErrorKind::InvalidData)?;
  if n>2 {let path=fs::read_link(entry.path())?;if path.to_str()!=Some(expected.as_str()){return Err(io::ErrorKind::PermissionDenied.into())}scan_fd+=1;}
 }if scan_fd==1 {Ok(())}else{Err(io::ErrorKind::PermissionDenied.into())}
}
fn verify_single_task()->io::Result<()> {
 let mut tasks=fs::read_dir("/proc/self/task")?;
 let entry=tasks.next().ok_or(io::ErrorKind::InvalidData)??;
 let id=entry.file_name().to_str().ok_or(io::ErrorKind::InvalidData)?.parse::<u32>().map_err(|_|io::ErrorKind::InvalidData)?;
 if id!=std::process::id()||tasks.next().is_some(){return Err(io::ErrorKind::PermissionDenied.into())}Ok(())
}
fn verify_acquired_fds(owned:&[i32])->io::Result<()> {
 let mut expected=owned.to_vec();expected.sort_unstable();expected.dedup();
 if expected.len()!=owned.len()||expected.iter().any(|fd|{let flags=unsafe{fcntl(*fd,1)};*fd<=2||flags<0||flags&1!=1}){return Err(io::ErrorKind::PermissionDenied.into())}
 let scan=format!("/proc/{}/fd",std::process::id());let mut found=Vec::new();let mut scan_count=0;
 for entry in fs::read_dir("/proc/self/fd")? {let entry=entry?;let name=entry.file_name();let n=name.to_str().ok_or(io::ErrorKind::InvalidData)?.parse::<i32>().map_err(|_|io::ErrorKind::InvalidData)?;
  if n>2 {if fs::read_link(entry.path())?.to_str()==Some(scan.as_str()){scan_count+=1}else{found.push(n)}}
 }found.sort_unstable();if found==expected&&scan_count==1{Ok(())}else{Err(io::ErrorKind::PermissionDenied.into())}
}
fn command(expected:u8)->io::Result<()> {let mut fd=PollFd{fd:0,events:1,revents:0};if unsafe{poll(&mut fd,1,30_000)}!=1{return Err(io::ErrorKind::TimedOut.into())}let mut byte=[0u8;1];if unsafe{read(0,byte.as_mut_ptr().cast(),1)}!=1{return Err(io::ErrorKind::UnexpectedEof.into())}if byte[0]!=expected{return Err(io::ErrorKind::InvalidData.into())}Ok(())}
fn report(byte:u8)->io::Result<()> {let mut out=io::stdout().lock();out.write_all(&[byte])?;out.flush()}
fn main(){if let Err(e)=run(){eprintln!("loop owner outcome unknown: {e}");std::process::exit(2)}}
#[cfg(test)]mod tests {
 use super::*;unsafe extern "C"{fn fork()->i32;fn waitpid(pid:i32,status:*mut i32,opts:i32)->i32;fn pipe(fds:*mut i32)->i32;fn dup2(old:i32,new:i32)->i32;fn close(fd:i32)->i32;fn _exit(code:i32)->!;}
 #[test]fn inherited_extra_fd_is_refused_in_isolated_child(){
  let pid=unsafe{fork()};assert!(pid>=0);if pid==0 {let mut fds=[0i32;2];if unsafe{pipe(fds.as_mut_ptr())}!=0{unsafe{_exit(1)}}
   if unsafe{dup2(fds[0],0)}!=0 || unsafe{dup2(fds[1],1)}!=1 || unsafe{dup2(fds[1],2)}!=2 {unsafe{_exit(2)}}
   for fd in 3..1024 {unsafe{close(fd);}}
   let clean=verify_initial_fds().is_ok()&&verify_single_task().is_ok();let extra=File::open("/dev/null").unwrap();let refused=verify_initial_fds().is_err();
   let exact=verify_acquired_fds(&[extra.as_raw_fd()]).is_ok();let duplicate=verify_acquired_fds(&[extra.as_raw_fd(),extra.as_raw_fd()]).is_err();
   let cleared=unsafe{fcntl(extra.as_raw_fd(),2,0)}==0 && verify_acquired_fds(&[extra.as_raw_fd()]).is_err();
   let other=File::open("/dev/zero").unwrap();let unexpected=verify_acquired_fds(&[extra.as_raw_fd()]).is_err();drop(other);drop(extra);
   unsafe{_exit(if clean&&refused&&exact&&duplicate&&cleared&&unexpected{0}else{3})}
  }
  let mut status=0;assert_eq!(unsafe{waitpid(pid,&mut status,0)},pid);assert_eq!(status,0);
 }
}
