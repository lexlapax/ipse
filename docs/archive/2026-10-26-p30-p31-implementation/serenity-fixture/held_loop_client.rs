//! Review-only client for a separately supervised held-FD loop owner.
//! This is not an authenticated launcher or a process-cleanup receipt.
use std::fs::File;use std::io::{self,Read,Write};use std::os::fd::{AsRawFd,FromRawFd};use std::os::unix::fs::{FileTypeExt,MetadataExt};
#[repr(C)]struct PollFd{fd:i32,events:i16,revents:i16}
unsafe extern "C"{fn poll(p:*mut PollFd,n:usize,t:i32)->i32;fn fcntl(fd:i32,cmd:i32,...)->i32;fn syscall(n:i64,...)->i64;}
pub(super) struct Client {command:File,reply:File,active:bool,pidfd:Option<File>}
pub(super) struct VerifiedOwner {pidfd:File,command:(u64,u64),reply:(u64,u64)}
impl VerifiedOwner {
 pub(super) fn verify_pipes(&self,command:&File,reply:&File)->io::Result<()> {live(&self.pidfd)?;let c=command.metadata()?;let r=reply.metadata()?;if (c.dev(),c.ino())!=self.command||(r.dev(),r.ino())!=self.reply{return Err(io::ErrorKind::PermissionDenied.into())}Ok(())}
 pub(super) fn into_pidfd(self)->File {self.pidfd}
}
impl Client {
 /// Only a future independently authenticated supervisor may supply pipes.
 /// Supplying two pipes alone does not prove which process owns the other ends.
 pub(super) fn new(command:File,reply:File)->io::Result<Self>{
  let cm=command.metadata()?;let rm=reply.metadata()?;if !cm.file_type().is_fifo()||!rm.file_type().is_fifo()||(cm.dev(),cm.ino())==(rm.dev(),rm.ino()){return Err(io::ErrorKind::InvalidInput.into())}
  for (f,mode) in [(&command,1),(&reply,0)] {let flags=unsafe{fcntl(f.as_raw_fd(),3)};if flags<0{return Err(io::Error::last_os_error())}if flags&3!=mode{return Err(io::ErrorKind::InvalidInput.into())}if unsafe{fcntl(f.as_raw_fd(),4,flags|0x800)}<0{return Err(io::Error::last_os_error())}}
  Ok(Self{command,reply,active:false,pidfd:None})
 }
 pub(super) fn activate(&mut self,proof:VerifiedOwner)->io::Result<()> {self.receive(b'H')?;live(&proof.pidfd)?;let c=self.command.metadata()?;let r=self.reply.metadata()?;if (c.dev(),c.ino())!=proof.command||(r.dev(),r.ino())!=proof.reply{return Err(io::ErrorKind::PermissionDenied.into())}self.send(b'A')?;self.pidfd=Some(proof.pidfd);self.active=true;Ok(())}
 pub(super) fn configure(&mut self)->io::Result<()> {if !self.active{return Err(io::ErrorKind::PermissionDenied.into())}if let Some(p)=&self.pidfd{live(p)?}self.exchange(b'C',b'B')}
 /// Signal only the exact pidfd pinned during attestation. This can cause
 /// kernel AUTOCLEAR and therefore never establishes device cleanup.
 pub(super) fn signal_owned(&self,signal:i32)->io::Result<()> {if signal!=9{return Err(io::ErrorKind::InvalidInput.into())}let p=self.pidfd.as_ref().ok_or(io::ErrorKind::PermissionDenied)?;let rc=unsafe{syscall(424,p.as_raw_fd(),signal,0,0)};if rc<0{Err(io::Error::last_os_error())}else{Ok(())}}
 /// R may enter CLR_FD and X attempts close. No result is a detach receipt.
 pub(super) fn rundown_close(&mut self)->io::Result<()> {if !self.active{return Err(io::ErrorKind::PermissionDenied.into())}if let Some(p)=&self.pidfd{live(p)?}self.send(b'R')?;self.send(b'X')?;self.receive(b'C')}
 fn exchange(&mut self,cmd:u8,reply:u8)->io::Result<()> {self.send(cmd)?;self.receive(reply)}
 fn send(&mut self,b:u8)->io::Result<()> {self.command.write_all(&[b])}
 fn receive(&mut self,expected:u8)->io::Result<()> {let mut p=PollFd{fd:self.reply.as_raw_fd(),events:1,revents:0};if unsafe{poll(&mut p,1,3000)}!=1||p.revents&1==0{return Err(io::ErrorKind::TimedOut.into())}let mut b=[0u8];self.reply.read_exact(&mut b)?;if b[0]!=expected{return Err(io::ErrorKind::InvalidData.into())}Ok(())}
}
fn live(fd:&File)->io::Result<()> {let mut p=PollFd{fd:fd.as_raw_fd(),events:1,revents:0};match unsafe{poll(&mut p,1,0)} {0=>Ok(()),_=>Err(io::ErrorKind::NotFound.into())}}
fn stat(pid:u32)->io::Result<(u32,u64)> {let s=std::fs::read_to_string(format!("/proc/{pid}/stat"))?;let end=s.rfind(')').ok_or(io::ErrorKind::InvalidData)?;let f:Vec<_>=s[end+1..].split_whitespace().collect();let parent=f.get(1).ok_or(io::ErrorKind::InvalidData)?.parse().map_err(|_|io::ErrorKind::InvalidData)?;let start=f.get(19).ok_or(io::ErrorKind::InvalidData)?.parse().map_err(|_|io::ErrorKind::InvalidData)?;Ok((parent,start))}
/// Same-PID-namespace snapshot only. The caller must independently protect the
/// binary and parent ancestry, and hold a guardian/process containment boundary.
pub(super) fn attest(pid:u32,executable:&File,command:&File,reply:&File)->io::Result<VerifiedOwner> {
 if pid==0{return Err(io::ErrorKind::InvalidInput.into())}let before=stat(pid)?;if before.0!=std::process::id()||before.1==0{return Err(io::ErrorKind::PermissionDenied.into())}
 let raw=unsafe{syscall(434,pid,0)};if raw<0{return Err(io::Error::last_os_error())}let pin=unsafe{File::from_raw_fd(raw as i32)};live(&pin)?;
 for (path,held) in [(format!("/proc/{pid}/exe"),executable),(format!("/proc/{pid}/fd/0"),command),(format!("/proc/{pid}/fd/1"),reply)] {let a=held.metadata()?;let b=std::fs::metadata(path)?;if (a.dev(),a.ino())!=(b.dev(),b.ino()){return Err(io::ErrorKind::PermissionDenied.into())}}
 if stat(pid)?!=before{return Err(io::ErrorKind::NotFound.into())}live(&pin)?;let c=command.metadata()?;let r=reply.metadata()?;Ok(VerifiedOwner{pidfd:pin,command:(c.dev(),c.ino()),reply:(r.dev(),r.ino())})
}
#[cfg(test)]mod tests {use super::*;use std::os::fd::FromRawFd;use std::thread;unsafe extern "C"{fn pipe(p:*mut i32)->i32;}
 fn pair()->(File,File){let mut p=[0;2];assert_eq!(unsafe{pipe(p.as_mut_ptr())},0);unsafe{(File::from_raw_fd(p[0]),File::from_raw_fd(p[1]))}}
 #[test]fn config_and_close_require_exact_protocol(){let (mut cr,cw)=pair();let (rr,mut rw)=pair();let mut client=Client::new(cw,rr).unwrap();let worker=thread::spawn(move||{let mut b=[0];cr.read_exact(&mut b).unwrap();assert_eq!(b,[b'C']);rw.write_all(b"B").unwrap();cr.read_exact(&mut b).unwrap();assert_eq!(b,[b'R']);cr.read_exact(&mut b).unwrap();assert_eq!(b,[b'X']);rw.write_all(b"C").unwrap();});client.active=true;client.configure().unwrap();client.rundown_close().unwrap();worker.join().unwrap()}
 #[test]fn reversed_or_same_pipe_is_rejected(){let (read,write)=pair();assert!(Client::new(read,write).is_err());let (read,write)=pair();let other=write.try_clone().unwrap();assert!(Client::new(other,read).is_err());drop(write);}
 #[test]fn wrong_ack_and_disconnected_command_are_unknown(){let (_cr,cw)=pair();let (rr,mut rw)=pair();let mut client=Client::new(cw,rr).unwrap();client.active=true;rw.write_all(b"Q").unwrap();assert_eq!(client.configure().unwrap_err().kind(),io::ErrorKind::InvalidData);let (cr,cw)=pair();let (rr,_rw)=pair();drop(cr);let mut c=Client::new(cw,rr).unwrap();c.active=true;assert!(c.configure().is_err());}
}
#[cfg(test)]mod attestation_tests {use super::*;use std::os::fd::{AsRawFd,FromRawFd};unsafe extern "C"{fn pipe(p:*mut i32)->i32;fn fork()->i32;fn dup2(a:i32,b:i32)->i32;fn close(fd:i32)->i32;fn read(fd:i32,p:*mut std::ffi::c_void,n:usize)->isize;fn write(fd:i32,p:*const std::ffi::c_void,n:usize)->isize;fn waitpid(pid:i32,s:*mut i32,o:i32)->i32;fn kill(pid:i32,s:i32)->i32;fn _exit(n:i32)->!;}
 struct Child(i32);impl Drop for Child{fn drop(&mut self){if self.0>0{unsafe{kill(self.0,9);let mut status=0;waitpid(self.0,&mut status,0);}}}}
 #[test]fn exact_child_and_pipe_identity_gate_activation(){let mut a=[0;2];let mut b=[0;2];assert_eq!(unsafe{pipe(a.as_mut_ptr())},0);assert_eq!(unsafe{pipe(b.as_mut_ptr())},0);let pid=unsafe{fork()};assert!(pid>=0);if pid==0{unsafe{if dup2(a[0],0)!=0||dup2(b[1],1)!=1{_exit(2)}for fd in [a[0],a[1],b[0],b[1]]{if fd>2{close(fd);}}let h=[b'H'];if write(1,h.as_ptr().cast(),1)!=1{_exit(3)}let mut x=[0u8];if read(0,x.as_mut_ptr().cast(),1)!=1||x[0]!=b'A'{_exit(4)}if read(0,x.as_mut_ptr().cast(),1)!=1||x[0]!=b'C'{_exit(5)}let y=[b'B'];if write(1,y.as_ptr().cast(),1)!=1{_exit(6)}let _=read(0,x.as_mut_ptr().cast(),1);_exit(7)}}
 let mut child=Child(pid);unsafe{close(a[0]);close(b[1]);}let command=unsafe{File::from_raw_fd(a[1])};let reply=unsafe{File::from_raw_fd(b[0])};let exe=File::open("/proc/self/exe").unwrap();let wrong=File::open("/dev/null").unwrap();assert!(attest(pid as u32,&wrong,&command,&reply).is_err());let mut other=[0;2];assert_eq!(unsafe{pipe(other.as_mut_ptr())},0);let wrong_command=unsafe{File::from_raw_fd(other[1])};assert!(attest(pid as u32,&exe,&wrong_command,&reply).is_err());drop(wrong_command);unsafe{close(other[0]);}let proof=attest(pid as u32,&exe,&command,&reply).unwrap();let mut client=Client::new(command,reply).unwrap();assert!(client.configure().is_err());client.activate(proof).unwrap();client.configure().unwrap();assert!(client.signal_owned(15).is_err());client.signal_owned(9).unwrap();let mut status=0;assert_eq!(unsafe{waitpid(pid,&mut status,0)},pid);child.0=0;assert_eq!(status&0x7f,9);assert_eq!(unsafe{fcntl(client.command.as_raw_fd(),3)}&0x800,0x800);
 }
}
