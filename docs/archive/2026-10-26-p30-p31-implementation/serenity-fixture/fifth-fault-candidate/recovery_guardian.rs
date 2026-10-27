//! Read-only process-exit observer for an owned synthetic ledger. It never
//! detaches, restores, mounts, removes or otherwise mutates any device.
use std::fs::{File,OpenOptions};
use std::io::{self,Read};
use std::os::unix::fs::{MetadataExt,OpenOptionsExt};
use std::os::unix::io::{AsRawFd,FromRawFd};
use std::path::Path;
use std::time::{Duration,Instant};
use super::recovery_ledger::{parse_ledger,Entry};
#[repr(C)]struct PollFd{fd:i32,events:i16,revents:i16}
extern "C" {fn syscall(num:i64,...)->i64;fn poll(p:*mut PollFd,n:usize,t:i32)->i32;fn close(fd:i32)->i32;fn geteuid()->u32;fn openat(fd:i32,path:*const i8,flags:i32,...)->i32;}
struct PidFd(i32);impl Drop for PidFd{fn drop(&mut self){unsafe{close(self.0);}}}
fn stat(pid:u32)->io::Result<u64>{let s=std::fs::read_to_string(format!("/proc/{pid}/stat"))?;let end=s.rfind(')').ok_or(io::ErrorKind::InvalidData)?;let fields:Vec<_>=s[end+1..].split_whitespace().collect();fields.get(19).ok_or(io::ErrorKind::InvalidData)?.parse().map_err(|_|io::ErrorKind::InvalidData.into())}
#[derive(Debug,PartialEq,Eq)]pub(super) enum Observation{Unknown(Entry),CleanupRecorded}
pub(super) fn watch(path:&Path,nonce:&str,pid:u32,expected_start:u64,timeout:Duration)->io::Result<Observation>{
 if pid==0 || expected_start==0 || timeout.is_zero() || timeout>Duration::from_secs(30) {return Err(io::ErrorKind::InvalidInput.into())}
 let dir=OpenOptions::new().read(true).custom_flags(0x30000).open(path)?;let dm=dir.metadata()?;
 if !dm.is_dir() || dm.uid()!=unsafe{geteuid()} || dm.mode()&0o777!=0o700{return Err(io::ErrorKind::PermissionDenied.into())}
 let file_path=path.join("recovery.ledger");let name=std::ffi::CString::new("recovery.ledger").unwrap();
 let raw=unsafe{openat(dir.as_raw_fd(),name.as_ptr(),0x20000|0x80000)};if raw<0{return Err(io::Error::last_os_error())}let mut file=unsafe{File::from_raw_fd(raw)};let identity=file.metadata()?;
 if !identity.is_file() || identity.uid()!=unsafe{geteuid()} || identity.nlink()!=1{return Err(io::ErrorKind::PermissionDenied.into())}
 if stat(pid)?!=expected_start{return Err(io::ErrorKind::NotFound.into())}
 let raw=unsafe{syscall(434,pid,0)};if raw<0{return Err(io::Error::last_os_error())}let pin=PidFd(raw as i32);
 if stat(pid)?!=expected_start{return Err(io::ErrorKind::NotFound.into())}
 let deadline=Instant::now()+timeout;loop {let remaining=deadline.saturating_duration_since(Instant::now());if remaining.is_zero(){return Err(io::ErrorKind::TimedOut.into())}
  let mut p=PollFd{fd:pin.0,events:1,revents:0};let rc=unsafe{poll(&mut p,1,remaining.as_millis().min(30_000) as i32)};
  if rc<0{return Err(io::Error::last_os_error())}if rc>0 {if p.revents&1==0{return Err(io::ErrorKind::InvalidData.into())}break}
 }
 let after=file.metadata()?;let named=std::fs::symlink_metadata(&file_path)?;let current_dir=std::fs::symlink_metadata(path)?;
 if (current_dir.dev(),current_dir.ino())!=(dm.dev(),dm.ino()) ||
 (after.dev(),after.ino(),after.nlink())!=(identity.dev(),identity.ino(),1) ||
 (named.dev(),named.ino())!=(identity.dev(),identity.ino()) || after.len()>4096 {return Err(io::ErrorKind::PermissionDenied.into())}
 let mut bytes=Vec::new();file.by_ref().take(4097).read_to_end(&mut bytes)?;
 let state=parse_ledger(&bytes,nonce)?;Ok(if state==Entry::CleanupDone {Observation::CleanupRecorded}else{Observation::Unknown(state)})
}
#[cfg(test)]mod tests {use super::*;use std::fs;use std::os::unix::fs::PermissionsExt;use std::process::{Command,Stdio};use super::super::recovery_ledger::Ledger;
 #[test]fn observes_only_exact_owned_child_exit_and_reports_pending_unknown(){
  let parent=std::env::temp_dir().join(format!("ipse-guardian-test-{}",std::process::id()));fs::create_dir(&parent).unwrap();fs::set_permissions(&parent,fs::Permissions::from_mode(0o700)).unwrap();
  let nonce="0123456789abcdef0123456789abcdef";let mut l=Ledger::create_in_parent(&parent,nonce).unwrap();l.record(Entry::SetupPending).unwrap();let dir=parent.join(format!(".ipse-fault-ledger-{nonce}"));
  let mut child=Command::new("/usr/bin/sleep").arg("10").stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn().unwrap();let pid=child.id();let start=stat(pid).unwrap();let observed=dir.clone();
  let watcher=std::thread::spawn(move ||watch(&observed,nonce,pid,start,Duration::from_secs(5)));
  std::thread::sleep(Duration::from_millis(100));child.kill().unwrap();let _=child.wait().unwrap();
  assert_eq!(watcher.join().unwrap().unwrap(),Observation::Unknown(Entry::SetupPending));
  drop(l);fs::remove_file(dir.join("recovery.ledger")).unwrap();fs::remove_dir(dir).unwrap();fs::remove_dir(parent).unwrap();
 }
 #[test]fn separately_running_observer_reports_synthetic_process_exit(){
  let parent=std::env::temp_dir().join(format!("ipse-guardian-process-{}",std::process::id()));fs::create_dir(&parent).unwrap();fs::set_permissions(&parent,fs::Permissions::from_mode(0o700)).unwrap();
  let nonce="0123456789abcdef0123456789abcdef";let mut l=Ledger::create_in_parent(&parent,nonce).unwrap();l.record(Entry::SetupPending).unwrap();let dir=parent.join(format!(".ipse-fault-ledger-{nonce}"));
  let mut child=Command::new("/usr/bin/sleep").arg("10").stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn().unwrap();let pid=child.id();let start=stat(pid).unwrap();
  let observer=Command::new("/tmp/ipse-serenity-qualification-plan/fixture/guardian_observer").arg(&dir).arg(nonce).arg(pid.to_string()).arg(start.to_string()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().unwrap();
  std::thread::sleep(Duration::from_millis(150));child.kill().unwrap();let _=child.wait().unwrap();let output=observer.wait_with_output().unwrap();assert!(output.status.success(),"{}",String::from_utf8_lossy(&output.stderr));assert_eq!(output.stdout,b"Unknown(SetupPending)\n");
  drop(l);fs::remove_file(dir.join("recovery.ledger")).unwrap();fs::remove_dir(dir).unwrap();fs::remove_dir(parent).unwrap();
 }
}
