//! Private diagnostic receipt model. Disabled: no host-device operations.
//! A journaled intent is not evidence that an effect did or did not happen.
use std::io;
#[derive(Clone,Copy,Debug,PartialEq,Eq)]pub(crate) enum Effect {ConfigureLoop,CreateMapper,MakeFilesystem,Mount,PrepareStage,SwitchError,ReleaseStage,RestoreLinear,Unmount,RemoveMapper,AttemptCloseLoop}
#[derive(Clone,Copy,Debug,PartialEq,Eq)]pub(crate) enum Record {Pending(Effect),Confirmed(Effect)}
#[derive(Debug,PartialEq,Eq)]pub(crate) enum Status {Ready,Pending(Effect),Confirmed(Effect)}
fn ordinal(e:Effect)->usize {match e {Effect::ConfigureLoop=>0,Effect::CreateMapper=>1,Effect::MakeFilesystem=>2,Effect::Mount=>3,Effect::PrepareStage=>4,Effect::SwitchError=>5,Effect::ReleaseStage=>6,Effect::RestoreLinear=>7,Effect::Unmount=>8,Effect::RemoveMapper=>9,Effect::AttemptCloseLoop=>10}}
fn name(e:Effect)->&'static str {match e {Effect::ConfigureLoop=>"configure-loop",Effect::CreateMapper=>"create-mapper",Effect::MakeFilesystem=>"make-filesystem",Effect::Mount=>"mount",Effect::PrepareStage=>"prepare-stage",Effect::SwitchError=>"switch-error",Effect::ReleaseStage=>"release-stage",Effect::RestoreLinear=>"restore-linear",Effect::Unmount=>"unmount",Effect::RemoveMapper=>"remove-mapper",Effect::AttemptCloseLoop=>"attempt-close-loop"}}
fn effect(s:&str)->Option<Effect> {[Effect::ConfigureLoop,Effect::CreateMapper,Effect::MakeFilesystem,Effect::Mount,Effect::PrepareStage,Effect::SwitchError,Effect::ReleaseStage,Effect::RestoreLinear,Effect::Unmount,Effect::RemoveMapper,Effect::AttemptCloseLoop].into_iter().find(|e|name(*e)==s)}
pub(crate) fn parse(bytes:&[u8],nonce:&str)->io::Result<Status>{
 if nonce.len()!=32||!nonce.bytes().all(|b|b.is_ascii_digit()||(b'a'..=b'f').contains(&b))||bytes.len()>4096||(!bytes.is_empty()&&!bytes.ends_with(b"\n")){return Err(io::ErrorKind::InvalidData.into())}
 let text=std::str::from_utf8(bytes).map_err(|_|io::ErrorKind::InvalidData)?;let mut next=0;let mut pending=None;let mut last=None;
 for (seq,line) in text.lines().enumerate(){let parts:Vec<_>=line.split(':').collect();if parts.len()!=4||parts[0]!=seq.to_string()||parts[1]!=nonce{return Err(io::ErrorKind::InvalidData.into())}let e=effect(parts[3]).ok_or(io::ErrorKind::InvalidData)?;
  match parts[2] {"pending" if pending.is_none()&&ordinal(e)==next=>pending=Some(e),"confirmed" if pending==Some(e)=>{pending=None;last=Some(e);next+=1},_=>return Err(io::ErrorKind::InvalidData.into())}
 }Ok(match (pending,last){(Some(e),_)=>Status::Pending(e),(None,Some(e))=>Status::Confirmed(e),_=>Status::Ready})
}
#[cfg(test)]mod tests {use super::*;const N:&str="0123456789abcdef0123456789abcdef";
 #[test]fn pending_effect_is_unknown_not_replay_permission(){let s=format!("0:{N}:pending:configure-loop\n");assert_eq!(parse(s.as_bytes(),N).unwrap(),Status::Pending(Effect::ConfigureLoop));}
 #[test]fn rejects_torn_wrong_run_duplicate_and_skipped(){for s in [format!("0:{N}:pending:configure-loop"),format!("0:{N}:confirmed:configure-loop\n"),format!("0:{N}:pending:configure-loop\n1:{N}:pending:configure-loop\n"),format!("0:{N}:pending:create-mapper\n"),format!("0:{N}:pending:configure-loop\n1:{N}:confirmed:create-mapper\n")] {assert!(parse(s.as_bytes(),N).is_err())}assert!(parse(format!("0:{N}:pending:configure-loop\n").as_bytes(),"ffffffffffffffffffffffffffffffff").is_err());}
 #[test]fn confirmed_effects_do_not_imply_later_cleanup(){let s=format!("0:{N}:pending:configure-loop\n1:{N}:confirmed:configure-loop\n2:{N}:pending:create-mapper\n");assert_eq!(parse(s.as_bytes(),N).unwrap(),Status::Pending(Effect::CreateMapper));}
}

use std::fs::File;use std::io::{Read,Write};use std::os::fd::{AsRawFd,FromRawFd};use std::os::unix::fs::MetadataExt;
unsafe extern "C"{fn openat(dir:i32,path:*const i8,flags:i32,...)->i32;fn geteuid()->u32;}
pub(crate) struct Receipt {directory:File,file:File,nonce:String,dev:u64,inode:u64,identity:Option<File>,observations:Vec<(&'static str,File)>}
impl Receipt {
 pub(crate) fn create(directory:File,nonce:&str)->io::Result<Self>{
  parse(b"",nonce)?;let dm=directory.metadata()?;if !dm.is_dir()||dm.uid()!=unsafe{geteuid()}||dm.mode()&0o777!=0o700{return Err(io::ErrorKind::PermissionDenied.into())}
  let name=c"diagnostic.receipt";let fd=unsafe{openat(directory.as_raw_fd(),name.as_ptr(),0x40|0x80|0x2|0x400|0x20000|0x80000,0o600)};if fd<0{return Err(io::Error::last_os_error())}
  let file=unsafe{File::from_raw_fd(fd)};let fm=file.metadata()?;if !fm.is_file()||fm.uid()!=dm.uid()||fm.nlink()!=1{return Err(io::ErrorKind::PermissionDenied.into())}file.sync_all()?;directory.sync_all()?;
  Ok(Self{directory,file,nonce:nonce.into(),dev:fm.dev(),inode:fm.ino(),identity:None,observations:Vec::new()})
 }
 pub(crate) fn record(&mut self,record:Record)->io::Result<()> {
  for (path,held) in &self.observations {let name=std::ffi::CString::new(*path).map_err(|_|io::ErrorKind::InvalidInput)?;let raw=unsafe{openat(self.directory.as_raw_fd(),name.as_ptr(),0x20000|0x80000)};if raw<0{return Err(io::Error::last_os_error())}let named=unsafe{File::from_raw_fd(raw)};let a=held.metadata()?;let b=named.metadata()?;if a.nlink()!=1||b.nlink()!=1||(a.dev(),a.ino())!=(b.dev(),b.ino()){return Err(io::ErrorKind::PermissionDenied.into())}}
  let identity=self.identity.as_ref().ok_or(io::ErrorKind::PermissionDenied)?;let identity_name=c"initial.identity";let raw=unsafe{openat(self.directory.as_raw_fd(),identity_name.as_ptr(),0x20000|0x80000)};if raw<0{return Err(io::Error::last_os_error())}let named=unsafe{File::from_raw_fd(raw)};let held=identity.metadata()?;let observed=named.metadata()?;if held.nlink()!=1||observed.nlink()!=1||(held.dev(),held.ino())!=(observed.dev(),observed.ino()){return Err(io::ErrorKind::PermissionDenied.into())}
  use std::io::{Seek,SeekFrom};let entry_name=c"diagnostic.receipt";let raw=unsafe{openat(self.directory.as_raw_fd(),entry_name.as_ptr(),0x20000|0x80000)};if raw<0{return Err(io::Error::last_os_error())}let named=unsafe{File::from_raw_fd(raw)};let a=self.file.metadata()?;let b=named.metadata()?;
  if !a.is_file()||a.uid()!=unsafe{geteuid()}||a.nlink()!=1||b.nlink()!=1||(a.dev(),a.ino())!=(self.dev,self.inode)||(b.dev(),b.ino())!=(self.dev,self.inode)||a.len()>4096{return Err(io::ErrorKind::PermissionDenied.into())}
  self.file.seek(SeekFrom::Start(0))?;let mut bytes=Vec::new();(&mut self.file).take(4097).read_to_end(&mut bytes)?;let previous=parse(&bytes,&self.nonce)?;let (kind,e)=match record {Record::Pending(e)=>("pending",e),Record::Confirmed(e)=>("confirmed",e)};
  if let Record::Confirmed(e)=record {let required=match e {Effect::CreateMapper=>Some("mapper.identity"),Effect::MakeFilesystem=>Some("filesystem.identity"),Effect::Mount=>Some("mount.identity"),_=>None};if required.is_some_and(|n|!self.observations.iter().any(|(name,_)|*name==n)){return Err(io::ErrorKind::PermissionDenied.into())}}
  let seq=bytes.iter().filter(|b|**b==b'\n').count();let line=format!("{seq}:{}:{kind}:{}\n",self.nonce,name(e));let mut candidate=bytes;candidate.extend_from_slice(line.as_bytes());let after=parse(&candidate,&self.nonce)?;
  if matches!(previous,Status::Pending(_))&&!matches!(record,Record::Confirmed(_)){return Err(io::ErrorKind::InvalidData.into())}let _=after;
  self.file.write_all(line.as_bytes())?;self.file.sync_data()
 }
}
#[cfg(test)]mod receipt_tests{use super::*;use std::fs::{self,OpenOptions};use std::os::unix::fs::{OpenOptionsExt,PermissionsExt};const N:&str="0123456789abcdef0123456789abcdef";
 #[test]fn records_only_legal_order_and_refuses_replaced_name(){let dir=std::env::temp_dir().join(format!("ipse-diagnostic-receipt-{}",std::process::id()));fs::create_dir(&dir).unwrap();fs::set_permissions(&dir,fs::Permissions::from_mode(0o700)).unwrap();let parent=OpenOptions::new().read(true).custom_flags(0x30000).open(&dir).unwrap();let mut r=Receipt::create(parent,N).unwrap();assert!(r.record(Record::Pending(Effect::ConfigureLoop)).is_err());let id=InitialIdentity{nonce:N.into(),boot_id:"01234567-89ab-cdef-0123-456789abcdef".into(),backing_dev:1,backing_inode:2,loop_minor:3,loop_node_dev:4,loop_node_inode:5};r.bind_initial(&id).unwrap();r.record(Record::Pending(Effect::ConfigureLoop)).unwrap();assert!(r.record(Record::Pending(Effect::ConfigureLoop)).is_err());r.record(Record::Confirmed(Effect::ConfigureLoop)).unwrap();fs::rename(dir.join("diagnostic.receipt"),dir.join("original")).unwrap();fs::write(dir.join("diagnostic.receipt"),"unrelated").unwrap();assert!(r.record(Record::Pending(Effect::CreateMapper)).is_err());assert_eq!(fs::read(dir.join("diagnostic.receipt")).unwrap(),b"unrelated");drop(r);fs::remove_file(dir.join("initial.identity")).unwrap();fs::remove_file(dir.join("original")).unwrap();fs::remove_file(dir.join("diagnostic.receipt")).unwrap();fs::remove_dir(dir).unwrap();}
}

#[derive(Debug)]pub(crate) struct InitialIdentity {pub nonce:String,pub boot_id:String,pub backing_dev:u64,pub backing_inode:u64,pub loop_minor:u32,pub loop_node_dev:u64,pub loop_node_inode:u64}
impl Receipt {
 /// Record immutable initial resource identity before configuring the loop.
 /// Later mapper, filesystem and namespace identities require separate records.
 pub(crate) fn bind_initial(&mut self,id:&InitialIdentity)->io::Result<()> {
  if id.nonce!=self.nonce || id.boot_id.len()!=36 || !id.boot_id.bytes().enumerate().all(|(i,b)|if [8,13,18,23].contains(&i){b==b'-'}else{b.is_ascii_digit()||(b'a'..=b'f').contains(&b)}) || id.backing_inode==0 || id.loop_node_inode==0 || id.loop_minor>4095 || self.file.metadata()?.len()!=0 {return Err(io::ErrorKind::InvalidInput.into())}
  let identity_name=c"initial.identity";let raw=unsafe{openat(self.directory.as_raw_fd(),identity_name.as_ptr(),0x40|0x80|1|0x20000|0x80000,0o600)};if raw<0{return Err(io::Error::last_os_error())}let mut f=unsafe{File::from_raw_fd(raw)};let meta=f.metadata()?;if !meta.is_file()||meta.uid()!=unsafe{geteuid()}||meta.nlink()!=1{return Err(io::ErrorKind::PermissionDenied.into())}
  writeln!(f,"v1 {} {} {} {} {} {} {}",id.nonce,id.boot_id,id.backing_dev,id.backing_inode,id.loop_minor,id.loop_node_dev,id.loop_node_inode)?;f.sync_all()?;self.directory.sync_all()?;self.identity=Some(f);Ok(())
 }
}
#[cfg(test)]mod identity_tests {use super::*;use std::fs::{self,OpenOptions};use std::os::unix::fs::{OpenOptionsExt,PermissionsExt};
 #[test]fn initial_binding_is_exclusive_and_must_precede_effects(){let p=std::env::temp_dir().join(format!("ipse-diagnostic-id-{}",std::process::id()));fs::create_dir(&p).unwrap();fs::set_permissions(&p,fs::Permissions::from_mode(0o700)).unwrap();let d=OpenOptions::new().read(true).custom_flags(0x30000).open(&p).unwrap();let n="0123456789abcdef0123456789abcdef";let mut r=Receipt::create(d,n).unwrap();let id=InitialIdentity{nonce:n.into(),boot_id:"01234567-89ab-cdef-0123-456789abcdef".into(),backing_dev:1,backing_inode:2,loop_minor:3,loop_node_dev:4,loop_node_inode:5};r.bind_initial(&id).unwrap();assert!(r.bind_initial(&id).is_err());r.record(Record::Pending(Effect::ConfigureLoop)).unwrap();assert!(r.bind_initial(&id).is_err());drop(r);fs::remove_file(p.join("initial.identity")).unwrap();fs::remove_file(p.join("diagnostic.receipt")).unwrap();fs::remove_dir(p).unwrap();}
}
#[derive(Debug)]pub(crate) enum Observation {Mapper{major:u32,minor:u32,uuid:String},Filesystem{uuid:String},Mount{namespace_inode:u64,mount_id:u64}}
fn valid_uuid(s:&str)->bool {s.len()==36&&s.bytes().enumerate().all(|(i,b)|if [8,13,18,23].contains(&i){b==b'-'}else{b.is_ascii_digit()||(b'a'..=b'f').contains(&b)})}
impl Receipt {
 /// Record exact observations before confirming the corresponding effect.
 /// Values must be independently gathered from pinned objects; this writer
 /// cannot itself prove they are truthful or refer to the intended resource.
 pub(crate) fn observe(&mut self,o:Observation)->io::Result<()> {
  use std::io::{Seek,SeekFrom};self.file.seek(SeekFrom::Start(0))?;let mut bytes=Vec::new();(&mut self.file).take(4097).read_to_end(&mut bytes)?;let state=parse(&bytes,&self.nonce)?;
  let (filename,body)=match o {Observation::Mapper{major,minor,uuid} if state==Status::Pending(Effect::CreateMapper)&&major>0&&major!=7&&uuid==format!("IPSE-Q-{}",self.nonce)=>("mapper.identity",format!("v1 {} {major} {minor} {uuid}\n",self.nonce)),Observation::Filesystem{uuid} if state==Status::Pending(Effect::MakeFilesystem)&&valid_uuid(&uuid)=>("filesystem.identity",format!("v1 {} {uuid}\n",self.nonce)),Observation::Mount{namespace_inode,mount_id} if state==Status::Pending(Effect::Mount)&&namespace_inode>0&&mount_id>0=>("mount.identity",format!("v1 {} {namespace_inode} {mount_id}\n",self.nonce)),_=>return Err(io::ErrorKind::InvalidInput.into())};
  let name=std::ffi::CString::new(filename).unwrap();let raw=unsafe{openat(self.directory.as_raw_fd(),name.as_ptr(),0x40|0x80|1|0x20000|0x80000,0o600)};if raw<0{return Err(io::Error::last_os_error())}let mut f=unsafe{File::from_raw_fd(raw)};let m=f.metadata()?;if !m.is_file()||m.uid()!=unsafe{geteuid()}||m.nlink()!=1{return Err(io::ErrorKind::PermissionDenied.into())}f.write_all(body.as_bytes())?;f.sync_all()?;self.directory.sync_all()?;self.observations.push((filename,f));Ok(())
 }
}
#[cfg(test)]mod observation_tests {use super::*;use std::fs::{self,OpenOptions};use std::os::unix::fs::{OpenOptionsExt,PermissionsExt};
 #[test]fn mapper_confirmation_requires_unique_matching_observation(){let p=std::env::temp_dir().join(format!("ipse-diagnostic-observation-{}",std::process::id()));fs::create_dir(&p).unwrap();fs::set_permissions(&p,fs::Permissions::from_mode(0o700)).unwrap();let d=OpenOptions::new().read(true).custom_flags(0x30000).open(&p).unwrap();let n="0123456789abcdef0123456789abcdef";let mut r=Receipt::create(d,n).unwrap();let id=InitialIdentity{nonce:n.into(),boot_id:"01234567-89ab-cdef-0123-456789abcdef".into(),backing_dev:1,backing_inode:2,loop_minor:3,loop_node_dev:4,loop_node_inode:5};r.bind_initial(&id).unwrap();r.record(Record::Pending(Effect::ConfigureLoop)).unwrap();r.record(Record::Confirmed(Effect::ConfigureLoop)).unwrap();r.record(Record::Pending(Effect::CreateMapper)).unwrap();assert!(r.record(Record::Confirmed(Effect::CreateMapper)).is_err());assert!(r.observe(Observation::Mapper{major:253,minor:0,uuid:"wrong".into()}).is_err());r.observe(Observation::Mapper{major:253,minor:0,uuid:format!("IPSE-Q-{n}")}).unwrap();r.record(Record::Confirmed(Effect::CreateMapper)).unwrap();r.record(Record::Pending(Effect::MakeFilesystem)).unwrap();assert!(r.record(Record::Confirmed(Effect::MakeFilesystem)).is_err());assert!(r.observe(Observation::Filesystem{uuid:"invalid".into()}).is_err());r.observe(Observation::Filesystem{uuid:"01234567-89ab-cdef-0123-456789abcdef".into()}).unwrap();r.record(Record::Confirmed(Effect::MakeFilesystem)).unwrap();r.record(Record::Pending(Effect::Mount)).unwrap();assert!(r.observe(Observation::Mount{namespace_inode:0,mount_id:3}).is_err());r.observe(Observation::Mount{namespace_inode:2,mount_id:3}).unwrap();r.record(Record::Confirmed(Effect::Mount)).unwrap();drop(r);for f in ["initial.identity","mapper.identity","filesystem.identity","mount.identity","diagnostic.receipt"] {fs::remove_file(p.join(f)).unwrap()}fs::remove_dir(p).unwrap();}
}
