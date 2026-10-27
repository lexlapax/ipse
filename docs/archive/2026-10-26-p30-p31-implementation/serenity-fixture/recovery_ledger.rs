//! Private tmpfs process-crash intent ledger prototype. Not device recovery.
//! Partial tails, impossible order and interrupted effects mean unknown.
use std::fs::{File, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::{MetadataExt,OpenOptionsExt};
use std::os::unix::io::{AsRawFd,FromRawFd};
use std::path::Path;
extern "C" {fn openat(fd:i32,path:*const i8,flags:i32,...)->i32;fn geteuid()->u32;fn mkdirat(fd:i32,path:*const i8,mode:u32)->i32;}
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub(super) enum Entry { Created, SetupPending, SetupDone, FaultPending, FaultDone, RestorePending, RestoreDone, CleanupPending, CleanupDone }
pub(super) struct Ledger { file: File, directory: File, file_dev:u64, file_inode:u64, next:usize, last:Option<Entry>, run:String }
fn legal(previous:Option<Entry>, next:Entry)->bool {matches!((previous,next),
 (None,Entry::Created)|(Some(Entry::Created),Entry::SetupPending)|(Some(Entry::SetupPending),Entry::SetupDone)|
 (Some(Entry::SetupDone),Entry::FaultPending)|(Some(Entry::FaultPending),Entry::FaultDone)|
 (Some(Entry::FaultDone),Entry::RestorePending)|(Some(Entry::RestorePending),Entry::RestoreDone)|
 (Some(Entry::RestoreDone),Entry::CleanupPending)|(Some(Entry::CleanupPending),Entry::CleanupDone))}
fn parse_ledger(bytes:&[u8],expected:&str)->io::Result<Entry> {
 if bytes.is_empty() || bytes.len()>4096 || !bytes.ends_with(b"\n") {return Err(io::ErrorKind::InvalidData.into())}
 let text=std::str::from_utf8(bytes).map_err(|_|io::ErrorKind::InvalidData)?;let mut previous=None;let mut count=0usize;
 for line in text.lines() {let (number,rest)=line.split_once(':').ok_or(io::ErrorKind::InvalidData)?;let (run,kind)=rest.split_once(':').ok_or(io::ErrorKind::InvalidData)?;if run!=expected{return Err(io::ErrorKind::InvalidData.into())}
  if number!=count.to_string() || count>=9{return Err(io::ErrorKind::InvalidData.into())}
  let entry=match kind {"Created"=>Entry::Created,"SetupPending"=>Entry::SetupPending,"SetupDone"=>Entry::SetupDone,"FaultPending"=>Entry::FaultPending,"FaultDone"=>Entry::FaultDone,"RestorePending"=>Entry::RestorePending,"RestoreDone"=>Entry::RestoreDone,"CleanupPending"=>Entry::CleanupPending,"CleanupDone"=>Entry::CleanupDone,_=>return Err(io::ErrorKind::InvalidData.into())};
  if !legal(previous,entry){return Err(io::ErrorKind::InvalidData.into())}previous=Some(entry);count+=1;
 } previous.ok_or(io::ErrorKind::InvalidData.into())
}
fn named(dir:&File,flags:i32,mode:u32)->io::Result<File> {
 let name=std::ffi::CString::new("recovery.ledger").unwrap();
 let raw=unsafe{openat(dir.as_raw_fd(),name.as_ptr(),flags|0x20000|0x80000,mode)};
 if raw<0{return Err(io::Error::last_os_error())}Ok(unsafe{File::from_raw_fd(raw)})
}
impl Ledger {
 pub(super) fn create_in_parent(parent:&Path, suffix:&str)->io::Result<Self>{
  if suffix.len()!=32 || !suffix.bytes().all(|b|b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) {return Err(io::ErrorKind::InvalidInput.into())}
  let parent_fd=OpenOptions::new().read(true).custom_flags(0x30000).open(parent)?;let pm=parent_fd.metadata()?;
  if !pm.is_dir() || pm.uid()!=unsafe{geteuid()} || pm.mode()&0o022!=0 {return Err(io::ErrorKind::PermissionDenied.into())}
  let name=std::ffi::CString::new(format!(".ipse-fault-ledger-{suffix}")).unwrap();
  if unsafe{mkdirat(parent_fd.as_raw_fd(),name.as_ptr(),0o700)}!=0{return Err(io::Error::last_os_error())}
  parent_fd.sync_all()?;
  let raw=unsafe{openat(parent_fd.as_raw_fd(),name.as_ptr(),0x30000|0x80000)};if raw<0{return Err(io::Error::last_os_error())}
  let dir=unsafe{File::from_raw_fd(raw)};Self::create_in_directory(dir,suffix)
 }
 pub(super) fn create(directory:&Path) -> io::Result<Self> {
  let directory=OpenOptions::new().read(true).custom_flags(0x30000).open(directory)?;
  Self::create_in_directory(directory,"0123456789abcdef0123456789abcdef")
 }
 fn create_in_directory(directory:File,run:&str)->io::Result<Self> {
  let dm=directory.metadata()?;
  if !dm.is_dir() || dm.mode()&0o777!=0o700 || dm.uid()!=unsafe{geteuid()} {return Err(io::ErrorKind::PermissionDenied.into())}
  let file=named(&directory,0x40|0x80|1,0o600)?;
  let m=file.metadata()?;if !m.is_file() || m.nlink()!=1 || m.uid()!=dm.uid(){return Err(io::ErrorKind::PermissionDenied.into())}
  let mut result=Self{file,directory,file_dev:m.dev(),file_inode:m.ino(),next:0,last:None,run:run.to_owned()};result.record(Entry::Created)?;result.directory.sync_all()?;Ok(result)
 }
 pub(super) fn record(&mut self,entry:Entry)->io::Result<()> {
  if !legal(self.last,entry) || self.next>=9 {return Err(io::ErrorKind::InvalidData.into())}
  let held=self.file.metadata()?;let current=named(&self.directory,0,0)?.metadata()?;
  if !current.is_file() || current.uid()!=unsafe{geteuid()} || current.nlink()!=1 || held.nlink()!=1 || held.len()>4096 ||
    (held.dev(),held.ino())!=(self.file_dev,self.file_inode) || (current.dev(),current.ino())!=(self.file_dev,self.file_inode) {
    return Err(io::ErrorKind::PermissionDenied.into());
  }
  writeln!(self.file,"{}:{}:{entry:?}",self.next,self.run)?;self.file.sync_data()?;self.next+=1;self.last=Some(entry);Ok(())
 }
}
#[cfg(test)] mod tests {
 use super::*;use std::fs;use std::os::unix::fs::PermissionsExt;
 #[test] fn pending_is_visible_and_existing_ledger_never_overwritten(){
  let dir=std::env::temp_dir().join(format!("ipse-ledger-test-{}",std::process::id()));fs::create_dir(&dir).unwrap();fs::set_permissions(&dir,fs::Permissions::from_mode(0o700)).unwrap();
  let mut ledger=Ledger::create(&dir).unwrap();ledger.record(Entry::SetupPending).unwrap();
  assert_eq!(fs::read_to_string(dir.join("recovery.ledger")).unwrap(),"0:0123456789abcdef0123456789abcdef:Created\n1:0123456789abcdef0123456789abcdef:SetupPending\n");
  assert!(Ledger::create(&dir).is_err());assert!(ledger.record(Entry::CleanupDone).is_err());
  assert_eq!(fs::read_to_string(dir.join("recovery.ledger")).unwrap(),"0:0123456789abcdef0123456789abcdef:Created\n1:0123456789abcdef0123456789abcdef:SetupPending\n");
  drop(ledger);fs::remove_file(dir.join("recovery.ledger")).unwrap();fs::remove_dir(dir).unwrap();
 }
 #[test] fn replaced_name_is_refused_without_writing_replacement(){
  let dir=std::env::temp_dir().join(format!("ipse-ledger-replace-{}",std::process::id()));fs::create_dir(&dir).unwrap();fs::set_permissions(&dir,fs::Permissions::from_mode(0o700)).unwrap();
  let mut ledger=Ledger::create(&dir).unwrap();fs::rename(dir.join("recovery.ledger"),dir.join("original")).unwrap();fs::write(dir.join("recovery.ledger"),"unrelated").unwrap();
  assert!(ledger.record(Entry::SetupPending).is_err());assert_eq!(fs::read_to_string(dir.join("recovery.ledger")).unwrap(),"unrelated");
  drop(ledger);fs::remove_file(dir.join("recovery.ledger")).unwrap();fs::remove_file(dir.join("original")).unwrap();fs::remove_dir(dir).unwrap();
 }
 #[test] fn recovery_parser_rejects_torn_duplicate_and_out_of_order_records(){
  assert_eq!(parse_ledger(b"0:0123456789abcdef0123456789abcdef:Created\n1:0123456789abcdef0123456789abcdef:SetupPending\n","0123456789abcdef0123456789abcdef").unwrap(),Entry::SetupPending);
  assert!(parse_ledger(b"0:0123456789abcdef0123456789abcdef:Created\n","ffffffffffffffffffffffffffffffff").is_err());
  for bytes in [&b"0:0123456789abcdef0123456789abcdef:Created\n1:0123456789abcdef0123456789abcdef:SetupPend"[..],&b"0:0123456789abcdef0123456789abcdef:Created\n0:0123456789abcdef0123456789abcdef:SetupPending\n"[..],&b"0:0123456789abcdef0123456789abcdef:Created\n1:0123456789abcdef0123456789abcdef:FaultPending\n"[..],&b"0:0123456789abcdef0123456789abcdef:Created\n1:0123456789abcdef0123456789abcdef:SetupPending\n2:0123456789abcdef0123456789abcdef:SetupPending\n"[..]] {assert!(parse_ledger(bytes,"0123456789abcdef0123456789abcdef").is_err());}
 }
 #[test] fn creates_and_syncs_a_unique_named_subdirectory(){
  let parent=std::env::temp_dir().join(format!("ipse-ledger-parent-{}",std::process::id()));fs::create_dir(&parent).unwrap();fs::set_permissions(&parent,fs::Permissions::from_mode(0o700)).unwrap();
  let suffix="0123456789abcdef0123456789abcdef";let mut ledger=Ledger::create_in_parent(&parent,suffix).unwrap();ledger.record(Entry::SetupPending).unwrap();
  assert!(Ledger::create_in_parent(&parent,suffix).is_err());assert!(Ledger::create_in_parent(&parent,"../escape").is_err());
  let child=parent.join(format!(".ipse-fault-ledger-{suffix}"));assert_eq!(parse_ledger(&fs::read(child.join("recovery.ledger")).unwrap(),suffix).unwrap(),Entry::SetupPending);
  drop(ledger);fs::remove_file(child.join("recovery.ledger")).unwrap();fs::remove_dir(child).unwrap();fs::remove_dir(parent).unwrap();
 }
}
