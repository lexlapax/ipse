//! Review-only client for a separately supervised held-FD loop owner.
//! This is not an authenticated launcher or a process-cleanup receipt.
use std::fs::File;use std::io::{self,Read,Write};use std::os::fd::AsRawFd;use std::os::unix::fs::{FileTypeExt,MetadataExt};
#[repr(C)]struct PollFd{fd:i32,events:i16,revents:i16}
unsafe extern "C"{fn poll(p:*mut PollFd,n:usize,t:i32)->i32;fn fcntl(fd:i32,cmd:i32,...)->i32;}
pub(super) struct Client {command:File,reply:File}
impl Client {
 /// Only a future independently authenticated supervisor may supply pipes.
 /// Supplying two pipes alone does not prove which process owns the other ends.
 pub(super) fn new(command:File,reply:File)->io::Result<Self>{
  let cm=command.metadata()?;let rm=reply.metadata()?;if !cm.file_type().is_fifo()||!rm.file_type().is_fifo()||(cm.dev(),cm.ino())==(rm.dev(),rm.ino()){return Err(io::ErrorKind::InvalidInput.into())}
  for (f,mode) in [(&command,1),(&reply,0)] {let flags=unsafe{fcntl(f.as_raw_fd(),3)};if flags<0{return Err(io::Error::last_os_error())}if flags&3!=mode{return Err(io::ErrorKind::InvalidInput.into())}if unsafe{fcntl(f.as_raw_fd(),4,flags|0x800)}<0{return Err(io::Error::last_os_error())}}
  Ok(Self{command,reply})
 }
 pub(super) fn configure(&mut self)->io::Result<()> {self.exchange(b'C',b'B')}
 /// R may enter CLR_FD and X attempts close. No result is a detach receipt.
 pub(super) fn rundown_close(&mut self)->io::Result<()> {self.send(b'R')?;self.send(b'X')?;self.receive(b'C')}
 fn exchange(&mut self,cmd:u8,reply:u8)->io::Result<()> {self.send(cmd)?;self.receive(reply)}
 fn send(&mut self,b:u8)->io::Result<()> {self.command.write_all(&[b])}
 fn receive(&mut self,expected:u8)->io::Result<()> {let mut p=PollFd{fd:self.reply.as_raw_fd(),events:1,revents:0};if unsafe{poll(&mut p,1,3000)}!=1||p.revents&1==0{return Err(io::ErrorKind::TimedOut.into())}let mut b=[0u8];self.reply.read_exact(&mut b)?;if b[0]!=expected{return Err(io::ErrorKind::InvalidData.into())}Ok(())}
}
#[cfg(test)]mod tests {use super::*;use std::os::fd::FromRawFd;use std::thread;unsafe extern "C"{fn pipe(p:*mut i32)->i32;}
 fn pair()->(File,File){let mut p=[0;2];assert_eq!(unsafe{pipe(p.as_mut_ptr())},0);unsafe{(File::from_raw_fd(p[0]),File::from_raw_fd(p[1]))}}
 #[test]fn config_and_close_require_exact_protocol(){let (mut cr,cw)=pair();let (rr,mut rw)=pair();let mut client=Client::new(cw,rr).unwrap();let worker=thread::spawn(move||{let mut b=[0];cr.read_exact(&mut b).unwrap();assert_eq!(b,[b'C']);rw.write_all(b"B").unwrap();cr.read_exact(&mut b).unwrap();assert_eq!(b,[b'R']);cr.read_exact(&mut b).unwrap();assert_eq!(b,[b'X']);rw.write_all(b"C").unwrap();});client.configure().unwrap();client.rundown_close().unwrap();worker.join().unwrap()}
 #[test]fn reversed_or_same_pipe_is_rejected(){let (read,write)=pair();assert!(Client::new(read,write).is_err());let (read,write)=pair();let other=write.try_clone().unwrap();assert!(Client::new(other,read).is_err());drop(write);}
 #[test]fn wrong_ack_and_disconnected_command_are_unknown(){let (_cr,cw)=pair();let (rr,mut rw)=pair();let mut client=Client::new(cw,rr).unwrap();rw.write_all(b"Q").unwrap();assert_eq!(client.configure().unwrap_err().kind(),io::ErrorKind::InvalidData);let (cr,cw)=pair();let (rr,_rw)=pair();drop(cr);let mut c=Client::new(cw,rr).unwrap();assert!(c.configure().is_err());}
}
