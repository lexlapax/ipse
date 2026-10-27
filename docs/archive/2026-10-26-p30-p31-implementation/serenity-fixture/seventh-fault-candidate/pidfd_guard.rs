//! Unwired Linux pidfd pause/guardian experiment. The live entry is disabled.
//! Caller must separately establish UID, PID/start-time, exact cgroup membership
//! and resource cleanup. Guardian retains only pidfd, lease and readiness FDs.
#![allow(dead_code)]
use std::ffi::{c_int,c_long,c_void};
use std::fs::File;
use std::io::{self,Write};
use std::os::fd::{AsRawFd,FromRawFd};
use std::time::{Duration,Instant};
#[repr(C)] struct PollFd { fd:c_int, events:i16, revents:i16 }
unsafe extern "C" {fn syscall(number:c_long,...)->c_long; fn pipe2(fds:*mut c_int,flags:c_int)->c_int;
 fn fork()->c_int; fn close(fd:c_int)->c_int; fn read(fd:c_int,buf:*mut c_void,count:usize)->isize;
 fn write(fd:c_int,buf:*const c_void,count:usize)->isize;fn dup2(old:c_int,new:c_int)->c_int;
 fn fcntl(fd:c_int,command:c_int,...)->c_int;fn poll(fd:*mut PollFd,count:usize,timeout:c_int)->c_int;
 fn waitpid(pid:c_int,status:*mut c_int,options:c_int)->c_int;fn getppid()->c_int;
 fn __errno_location()->*mut c_int;fn _exit(code:c_int)->!;}
const PIDFD_OPEN:c_long=434;const PIDFD_SEND_SIGNAL:c_long=424;const CLOSE_RANGE:c_long=436;
const SIGSTOP:c_int=19;const SIGCONT:c_int=18;const O_CLOEXEC:c_int=0x80000;
const F_DUPFD_CLOEXEC:c_int=1030;
fn open(pid:u32)->io::Result<File>{
 let fd=unsafe{syscall(PIDFD_OPEN,pid,0u32)};
 if fd<0 {Err(io::Error::last_os_error())} else {Ok(unsafe{File::from_raw_fd(fd as c_int)})}
}
fn signal(fd:&File,sig:c_int)->io::Result<()>{
 if unsafe{syscall(PIDFD_SEND_SIGNAL,fd.as_raw_fd(),sig,std::ptr::null::<u8>(),0u32)}<0 {
  Err(io::Error::last_os_error())
 } else {Ok(())}
}
fn dup_high(fd:c_int)->io::Result<c_int>{let n=unsafe{fcntl(fd,F_DUPFD_CLOEXEC,64)};
 if n<0 {Err(io::Error::last_os_error())}else{Ok(n)}}
fn reap(child:c_int)->io::Result<()> {
 let deadline=Instant::now()+Duration::from_secs(2);let mut status=0;
 while Instant::now()<deadline {
  let r=unsafe{waitpid(child,&mut status,1)};
  if r==child {return if status==0 {Ok(())} else {Err(io::Error::other("guardian failed"))};}
  if r<0{return Err(io::Error::last_os_error());}
  std::thread::sleep(Duration::from_millis(5));
 }
 Err(io::Error::other("guardian cleanup unconfirmed"))
}
struct Guard { pidfd:File,lease:Option<File>,guardian:c_int }
impl Guard {
 fn new(pid:u32)->io::Result<Self>{
  let pidfd=open(pid)?;let mut lease=[-1;2];let mut ready=[-1;2];
  if unsafe{pipe2(lease.as_mut_ptr(),O_CLOEXEC)}!=0{return Err(io::Error::last_os_error());}
  if unsafe{pipe2(ready.as_mut_ptr(),O_CLOEXEC)}!=0{unsafe{close(lease[0]);close(lease[1]);}return Err(io::Error::last_os_error());}
  let copied=(||->io::Result<[File;3]>{Ok([
    unsafe{File::from_raw_fd(dup_high(pidfd.as_raw_fd())?)},
    unsafe{File::from_raw_fd(dup_high(lease[0])?)},
    unsafe{File::from_raw_fd(dup_high(ready[1])?)}
  ])})();
  let copied=match copied {Ok(v)=>v,Err(e)=>{unsafe{close(lease[0]);close(lease[1]);close(ready[0]);close(ready[1]);}return Err(e);}};
  let copied_fds=[copied[0].as_raw_fd(),copied[1].as_raw_fd(),copied[2].as_raw_fd()];
  let child=unsafe{fork()};
  if child<0 {drop(copied);unsafe{close(lease[0]);close(lease[1]);close(ready[0]);close(ready[1]);}return Err(io::Error::last_os_error());}
  if child==0 {unsafe{
    // All original sources are >=64, so assigning 3/4/5 cannot clobber them.
    if dup2(copied_fds[0],3)<0 || dup2(copied_fds[1],4)<0 || dup2(copied_fds[2],5)<0 {_exit(4);}
    if syscall(CLOSE_RANGE,6u32,u32::MAX,0u32)<0 {_exit(5);}
    close(0);close(1);close(2);
    if write(5,b"Y".as_ptr().cast(),1)!=1 {_exit(6);}close(5);
    let mut byte=0u8;
    loop {let n=read(4,(&mut byte as *mut u8).cast(),1);
     if n<0 && *__errno_location()==4 {continue;} break;}
    // Resume on normal release, EOF, or read error: never leave a process
    // suspended merely because the private lease failed.
    let result=syscall(PIDFD_SEND_SIGNAL,3,SIGCONT,std::ptr::null::<u8>(),0u32);
    _exit(if result==0 {0}else{3});
  }}
  drop(copied);unsafe{close(lease[0]);close(ready[1]);}
  let mut pollfd=PollFd{fd:ready[0],events:1,revents:0};
  let p=unsafe{poll(&mut pollfd,1,2_000)};let mut byte=0u8;
  let n=if p>0 {unsafe{read(ready[0],(&mut byte as *mut u8).cast(),1)}}else{-1};
  unsafe{close(ready[0]);}
  if n!=1 || byte!=b'Y' {
   unsafe{close(lease[1]);} let _=reap(child);
   return Err(io::Error::other("guardian readiness unconfirmed"));
  }
  Ok(Self {pidfd,lease:Some(unsafe{File::from_raw_fd(lease[1])}),guardian:child})
 }
 fn pause(&mut self)->io::Result<()> {
  let mut status=0;let state=unsafe{waitpid(self.guardian,&mut status,1)};
  if state!=0 {if state==self.guardian {self.guardian=0;} return Err(io::Error::other("guardian lost"));}
  signal(&self.pidfd,SIGSTOP)
 }
 fn release(&mut self)->io::Result<()> {
  self.lease.take().ok_or_else(||io::Error::other("already released"))?.write_all(b"R")?;
  let result=reap(self.guardian);if result.is_ok(){self.guardian=0;}result
 }
}
impl Drop for Guard {fn drop(&mut self){
 let _=signal(&self.pidfd,SIGCONT);drop(self.lease.take());
 if self.guardian>0 {let _=reap(self.guardian);}
}}
fn main(){
 let args:Vec<_>=std::env::args().collect();
 if args.len()!=3 || args[1]!="--owned-dummy-child-test" {
  eprintln!("Live pidfd pause disabled until reviewed.");std::process::exit(2);
 }
 let pid:u32=match args[2].parse(){Ok(p) if p>1=>p,_=>std::process::exit(2)};
 // Only a sibling synthetic `/usr/bin/sleep 5` owned by our parent may be
 // targeted in this narrow smoke test. This is not a production admission API.
 let status=std::fs::read_to_string(format!("/proc/{pid}/status")).unwrap_or_default();
 let expected_parent=unsafe{getppid()};
 let ppid=status.lines().find_map(|s|s.strip_prefix("PPid:")).and_then(|s|s.trim().parse::<c_int>().ok());
 let cmd=std::fs::read(format!("/proc/{pid}/cmdline")).unwrap_or_default();
 let exe=std::fs::read_link(format!("/proc/{pid}/exe")).ok();
 if ppid!=Some(expected_parent)||cmd!=b"/usr/bin/sleep\0".iter().copied().chain(b"5\0".iter().copied()).collect::<Vec<_>>()||
    exe.as_deref()!=Some(std::path::Path::new("/usr/bin/sleep")) {std::process::exit(2);}
 let mut guard=Guard::new(pid).unwrap_or_else(|_|std::process::exit(2));
 guard.pause().unwrap_or_else(|_|std::process::exit(2));
 let until=Instant::now()+Duration::from_secs(2);
 while Instant::now()<until {
  let status=std::fs::read_to_string(format!("/proc/{pid}/status")).unwrap_or_default();
  if status.lines().any(|s|s.starts_with("State:\tT")){println!("PAUSED");let _=io::stdout().flush();
   std::thread::sleep(Duration::from_secs(10));let _=guard.release();return;}
  std::thread::sleep(Duration::from_millis(5));
 }
 std::process::exit(2)
}
#[cfg(test)]mod tests{
 use super::*;use std::process::{Command,Stdio};
 fn stopped(pid:u32)->bool{
  std::fs::read_to_string(format!("/proc/{pid}/status")).unwrap().lines().any(|x|x.starts_with("State:\tT"))
 }
 #[test]fn guardian_resumes_only_an_owned_dummy_child() {
  let mut child=Command::new("/usr/bin/sleep").arg("5").stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn().unwrap();
  let pid=child.id();let mut guard=Guard::new(pid).unwrap();guard.pause().unwrap();
  let deadline=Instant::now()+Duration::from_secs(2);
  while !stopped(pid) && Instant::now()<deadline {std::thread::sleep(Duration::from_millis(5));}
  assert!(stopped(pid));guard.release().unwrap();
  let deadline=Instant::now()+Duration::from_secs(2);
  while stopped(pid) && Instant::now()<deadline {std::thread::sleep(Duration::from_millis(5));}
  assert!(!stopped(pid));child.kill().unwrap();child.wait().unwrap();
 }
 #[test]fn guardian_does_not_inherit_an_unrelated_cgroup_descriptor() {
  let unrelated=File::open("/sys/fs/cgroup").unwrap();
  let mut child=Command::new("/usr/bin/sleep").arg("5").stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn().unwrap();
  let mut guard=Guard::new(child.id()).unwrap();
  let directory=format!("/proc/{}/fd",guard.guardian);
  let mut fds:Vec<_>=std::fs::read_dir(directory).unwrap().map(|e|e.unwrap().file_name().to_string_lossy().into_owned()).collect();
  fds.sort();assert_eq!(fds,vec!["3".to_string(),"4".to_string()]);
  assert!(unrelated.metadata().is_ok());guard.release().unwrap();child.kill().unwrap();child.wait().unwrap();
 }
 #[test]fn lease_eof_resumes_the_owned_child_without_a_release_byte() {
  let mut child=Command::new("/usr/bin/sleep").arg("5").stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn().unwrap();
  let pid=child.id();let mut guard=Guard::new(pid).unwrap();guard.pause().unwrap();
  let deadline=Instant::now()+Duration::from_secs(2);
  while !stopped(pid) && Instant::now()<deadline {std::thread::sleep(Duration::from_millis(5));}
  assert!(stopped(pid));drop(guard.lease.take());reap(guard.guardian).unwrap();guard.guardian=0;
  let deadline=Instant::now()+Duration::from_secs(2);
  while stopped(pid) && Instant::now()<deadline {std::thread::sleep(Duration::from_millis(5));}
  assert!(!stopped(pid));child.kill().unwrap();child.wait().unwrap();
 }
 #[test]fn coordinator_sigkill_causes_guardian_to_resume_an_owned_sibling() {
  use std::io::{BufRead,BufReader};
  struct Cleanup(std::process::Child,Option<std::process::Child>);
  impl Drop for Cleanup {fn drop(&mut self){if let Some(c)=self.1.as_mut(){let _=c.kill();let _=c.wait();}let _=self.0.kill();let _=self.0.wait();}}
  let target=Command::new("/usr/bin/sleep").arg("5").stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn().unwrap();
  let mut cleanup=Cleanup(target,None);let pid=cleanup.0.id();
  let coordinator=Command::new(std::env::var("IPSE_PIDFD_SMOKE_BIN").expect("smoke binary"))
   .arg("--owned-dummy-child-test").arg(pid.to_string()).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().unwrap();
  cleanup.1=Some(coordinator);let output=cleanup.1.as_mut().unwrap().stdout.take().unwrap();
  let mut line=String::new();BufReader::new(output).read_line(&mut line).unwrap();assert_eq!(line,"PAUSED\n");assert!(stopped(pid));
  cleanup.1.as_mut().unwrap().kill().unwrap();cleanup.1.as_mut().unwrap().wait().unwrap();cleanup.1=None;
  let deadline=Instant::now()+Duration::from_secs(2);
  while stopped(pid) && Instant::now()<deadline {std::thread::sleep(Duration::from_millis(5));}
  assert!(!stopped(pid));
 }
}
