//! Disabled held-owner launcher prototype. No constructor exists for the
//! required independently verified boundary; do not enable for device use.
use std::fs::{File,OpenOptions};use std::io::{self,Read};use std::os::fd::OwnedFd;use std::os::unix::fs::{FileTypeExt,MetadataExt,OpenOptionsExt};use std::path::Path;use std::process::{Child,Command,Stdio};
use super::held_loop_client::{self,Client,VerifiedOwner};
#[derive(Clone)]pub(super) struct LaunchBoundary{container_id:String,mount_namespace:u64,host_mount_namespace:u64}
impl LaunchBoundary {
 /// Narrow diagnostic preflight; this is not a proof of cgroup quiescence.
 /// Caller must separately inspect the Docker ID/image and retain a guardian.
 pub(super) fn validate(container_id:&str,host_mount_ns:u64)->io::Result<Self> {
  if container_id.len()!=64||!container_id.bytes().all(|b|b.is_ascii_digit()||(b'a'..=b'f').contains(&b))||host_mount_ns==0{return Err(io::ErrorKind::InvalidInput.into())}
  let mut cg=String::new();File::open("/proc/self/cgroup")?.take(4097).read_to_string(&mut cg)?;if cg.len()>4096||cg!=format!("0::/system.slice/docker-{container_id}.scope\n"){return Err(io::ErrorKind::PermissionDenied.into())}
  let ns=std::fs::metadata("/proc/self/ns/mnt")?.ino();if ns==host_mount_ns{return Err(io::ErrorKind::PermissionDenied.into())}
  for p in ["/work","/work/tools","/work/tools/bin","/work/tools/lib"] {let m=std::fs::symlink_metadata(p)?;if !m.is_dir()||m.uid()!=0||m.mode()&0o022!=0{return Err(io::ErrorKind::PermissionDenied.into())}}
  let mut input=Vec::new();File::open("/proc/self/mountinfo")?.take(1_048_577).read_to_end(&mut input)?;if input.len()>1_048_576{return Err(io::ErrorKind::InvalidData.into())}let text=std::str::from_utf8(&input).map_err(|_|io::ErrorKind::InvalidData)?;let mut matches=0;for line in text.lines(){let f:Vec<_>=line.split_whitespace().collect();if f.len()>6&&f[4]=="/work/tools" {if !f[5].split(',').any(|o|o=="ro"){return Err(io::ErrorKind::PermissionDenied.into())}matches+=1}}if matches!=1{return Err(io::ErrorKind::PermissionDenied.into())}
  Ok(Self{container_id:container_id.into(),mount_namespace:ns,host_mount_namespace:host_mount_ns})
 }
 pub(super) fn validate_runtime(&self)->io::Result<()> {
  self.recheck()?;let mut input=Vec::new();File::open("/proc/self/mountinfo")?.take(1_048_577).read_to_end(&mut input)?;if input.len()>1_048_576{return Err(io::ErrorKind::InvalidData.into())}let text=std::str::from_utf8(&input).map_err(|_|io::ErrorKind::InvalidData)?;
  for path in ["/","/usr/lib/erlang","/usr/lib/elixir","/usr/lib/libsctp.so.1","/work/runtime"] {let rows:Vec<_>=text.lines().filter_map(|line|{let f:Vec<_>=line.split_whitespace().collect();if f.len()>6&&f[4]==path{Some(f[5].to_owned())}else{None}}).collect();if rows.len()!=1||!rows[0].split(',').any(|o|o=="ro"){return Err(io::ErrorKind::PermissionDenied.into())}}
  for path in ["/usr/lib/erlang","/usr/lib/elixir","/work/runtime"] {let m=std::fs::symlink_metadata(path)?;if !m.is_dir()||m.uid()!=0||m.mode()&0o022!=0{return Err(io::ErrorKind::PermissionDenied.into())}}Ok(())
 }
 pub(super) fn recheck(&self)->io::Result<()> {let again=Self::validate(&self.container_id,self.host_mount_namespace)?;if again.mount_namespace!=self.mount_namespace{return Err(io::ErrorKind::PermissionDenied.into())}Ok(())}
}
use super::guardian_launcher::GuardianReady;
pub(super) struct PreparedOwner {child:Child,client:Client,proof:Option<VerifiedOwner>,minor:u32,nonce:String,backing_dev:u64,backing_inode:u64}
pub(super) struct Owner {child:Child,client:Client,guardian:GuardianReady,minor:u32,nonce:String,backing_dev:u64,backing_inode:u64}
impl PreparedOwner {
 pub(super) fn pid(&self)->u32 {self.child.id()}
 /// No device open can occur until a separately armed guardian is supplied.
 pub(super) fn activate(mut self,guardian:GuardianReady)->Result<Owner,(Self,GuardianReady,io::Error)> {if !guardian.matches(self.child.id(),&self.nonce){return Err((self,guardian,io::ErrorKind::PermissionDenied.into()))}let proof=match self.proof.take(){Some(p)=>p,None=>return Err((self,guardian,io::ErrorKind::PermissionDenied.into()))};if let Err(e)=self.client.activate(proof){return Err((self,guardian,e))}Ok(Owner{child:self.child,client:self.client,guardian,minor:self.minor,nonce:self.nonce,backing_dev:self.backing_dev,backing_inode:self.backing_inode})}
}
impl Owner {
 pub(super) fn matches(&self,minor:u32,reference:&str,dev:u64,inode:u64)->bool {self.minor==minor && reference==format!("ipse-q-{}",self.nonce) && (self.backing_dev,self.backing_inode)==(dev,inode)}
 pub(super) fn guardian_live(&self)->bool {self.guardian.matches(self.child.id(),&self.nonce)}
 pub(super) fn configure(&mut self)->io::Result<()> {if !self.guardian_live(){return Err(io::ErrorKind::BrokenPipe.into())}self.client.configure()}
 pub(super) fn rundown_close(&mut self)->io::Result<()> {if !self.guardian_live(){return Err(io::ErrorKind::BrokenPipe.into())}self.client.rundown_close()}
 /// Stop only this attested owner and attempt bounded reap. A timeout or
 /// failed signal retains this Owner; kernel resource outcomes stay unknown.
 pub(super) fn stop_and_reap(&mut self)->io::Result<Option<std::process::ExitStatus>> {
  if let Some(status)=self.child.try_wait()? {return Ok(Some(status))}
  match self.client.signal_owned(9) {Ok(())=>(),Err(e) if e.raw_os_error()==Some(3)=>(),Err(e)=>return Err(e)}
  let deadline=std::time::Instant::now()+std::time::Duration::from_secs(3);loop {if let Some(status)=self.child.try_wait()?{return Ok(Some(status))}if std::time::Instant::now()>=deadline{return Ok(None)}std::thread::sleep(std::time::Duration::from_millis(10));}
 }
}
pub(super) struct LaunchFailure {pub(super) child:Option<Child>,pub(super) error:io::Error}
/// Boundary must prove protected read-only executable ancestry and an external
/// guardian of this exact child/container. No producer for it exists yet.
pub(super) fn launch(boundary:&LaunchBoundary,path:&Path,minor:u32,nonce:&str,backing_dev:u64,backing_inode:u64,stderr:File)->Result<PreparedOwner,LaunchFailure>{
 let preflight=(||->io::Result<File>{
  boundary.recheck()?;
  if path!=Path::new("/work/tools/bin/ipse-loop-owner")||minor>4095||nonce.len()!=32||!nonce.bytes().all(|b|b.is_ascii_digit()||(b'a'..=b'f').contains(&b))||backing_inode==0||!stderr.metadata()?.file_type().is_fifo(){return Err(io::ErrorKind::InvalidInput.into())}
  let executable=OpenOptions::new().read(true).custom_flags(0x20000|0x80000).open(path)?;let meta=executable.metadata()?;let named=std::fs::symlink_metadata(path)?;if !meta.is_file()||meta.uid()!=0||meta.mode()&0o022!=0||(meta.dev(),meta.ino())!=(named.dev(),named.ino()){return Err(io::ErrorKind::PermissionDenied.into())}Ok(executable)
 })();let executable=preflight.map_err(|error|LaunchFailure{child:None,error})?;
 let spawned=Command::new(path).env_clear().arg(minor.to_string()).arg(format!("ipse-q-{nonce}")).arg(backing_dev.to_string()).arg(backing_inode.to_string()).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::from(stderr)).spawn();
 let mut child=spawned.map_err(|error|LaunchFailure{child:None,error})?;
 let setup=(||->io::Result<(Client,VerifiedOwner)>{let input=child.stdin.take().ok_or(io::ErrorKind::BrokenPipe)?;let output=child.stdout.take().ok_or(io::ErrorKind::BrokenPipe)?;let command=File::from(OwnedFd::from(input));let reply=File::from(OwnedFd::from(output));let proof=held_loop_client::attest(child.id(),&executable,&command,&reply)?;let client=Client::new(command,reply)?;Ok((client,proof))})();
 // Return the exact Child to the guardian even when setup is uncertain; it
 // must observe termination/reap and retain pending records. Dropping Child
 // by itself proves neither process nor device cleanup.
 match setup {Ok((client,proof))=>Ok(PreparedOwner{child,client,proof:Some(proof),minor,nonce:nonce.into(),backing_dev,backing_inode}),Err(error)=>Err(LaunchFailure{child:Some(child),error})}
}
#[cfg(test)]mod tests {use super::*;use std::os::fd::FromRawFd;unsafe extern "C"{fn pipe(p:*mut i32)->i32;}
 #[test]fn invalid_boundary_rejects_without_touching_container_resources(){for id in ["","uppercaseXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX","0123"] {assert!(LaunchBoundary::validate(id,1).is_err())}assert!(LaunchBoundary::validate(&"a".repeat(64),0).is_err());}
 #[test]fn invalid_launch_fails_before_process_creation(){let mut fds=[0;2];assert_eq!(unsafe{pipe(fds.as_mut_ptr())},0);let read=unsafe{File::from_raw_fd(fds[0])};let write=unsafe{File::from_raw_fd(fds[1])};let result=launch(&LaunchBoundary{container_id:String::new(),mount_namespace:0,host_mount_namespace:0},Path::new("/not/allowed"),0,"0123456789abcdef0123456789abcdef",1,2,write);match result {Err(e)=>{assert!(e.child.is_none());assert_eq!(e.error.kind(),io::ErrorKind::InvalidInput)},Ok(_)=>panic!("unexpected process")};drop(read);}
}
