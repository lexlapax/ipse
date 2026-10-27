//! Process adapter for the private temporary-file peer listener. Diagnostic
//! only: no privileged tools, device actions or cgroup cleanup are performed.
use std::io::{self,Write};
use std::os::fd::AsRawFd;
use std::process::{Child,ChildStdin,ChildStdout,Command,Stdio};
use std::time::{Duration,Instant};
#[repr(C)]struct PollFd{fd:i32,events:i16,revents:i16}
extern "C" {fn poll(fd:*mut PollFd,n:usize,t:i32)->i32;fn read(fd:i32,buf:*mut std::ffi::c_void,count:usize)->isize;}
fn valid_report(s:&str)->bool {let Some(v)=s.strip_prefix("REPORT W=") else{return false};let parts:Vec<_>=v.split(" S=").collect();
 if parts.is_empty()||parts.len()>2||parts.iter().any(|x|x.is_empty()||x.len()>10||!x.bytes().all(|b|b.is_ascii_digit())){return false}
 let Ok(w)=parts[0].parse::<i32>() else{return false};if w>0{return parts.len()==1}if w!=0||parts.len()!=2{return false}
 parts[1].parse::<i32>().is_ok_and(|s|s>=0)
}
pub(super) struct Channel{child:Child,input:ChildStdin,output:ChildStdout,state:u8}
impl Channel {
 pub(super) fn start(root:&str)->io::Result<Self>{
  if !root.strip_prefix("/tmp/ipse-serenity-barrier-benign/").is_some_and(|s|!s.is_empty()&&s.len()<=64&&s.bytes().all(|b|b.is_ascii_lowercase()||b.is_ascii_digit()||b==b'-')){return Err(io::ErrorKind::InvalidInput.into())}
  let mut child=Command::new("/tmp/ipse-serenity-qualification-plan/fixture/peer_listener")
   .args(["/tmp/ipse-serenity-barrier-benign/control.sock",root,"/tmp/ipse-serenity-barrier-graph/project/priv/ipse-runner"])
   .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn()?;
  let input=child.stdin.take().ok_or(io::ErrorKind::BrokenPipe)?;let output=child.stdout.take().ok_or(io::ErrorKind::BrokenPipe)?;
  let mut result=Self{child,input,output,state:0};if result.line()? != "LISTENING"{return Err(io::ErrorKind::InvalidData.into())}result.state=1;Ok(result)
 }
 fn line(&mut self)->io::Result<String>{let deadline=Instant::now()+Duration::from_secs(5);let mut bytes=Vec::new();loop {
  let remaining=deadline.saturating_duration_since(Instant::now());if remaining.is_zero(){return Err(io::ErrorKind::TimedOut.into())}
  let mut p=PollFd{fd:self.output.as_raw_fd(),events:1,revents:0};let n=unsafe{poll(&mut p,1,remaining.as_millis().min(5000) as i32)};
  if n<=0{return Err(if n==0{io::ErrorKind::TimedOut.into()}else{io::Error::last_os_error()})}
  let mut b=[0];if unsafe{read(self.output.as_raw_fd(),b.as_mut_ptr().cast(),1)}!=1{return Err(io::ErrorKind::UnexpectedEof.into())}
  if b[0]==b'\n'{break}if bytes.len()>=256 || !b[0].is_ascii(){return Err(io::ErrorKind::InvalidData.into())}bytes.push(b[0]);
 }String::from_utf8(bytes).map_err(|_|io::ErrorKind::InvalidData.into())}
 pub(super) fn ready(&mut self)->io::Result<String>{if self.state!=1{return Err(io::ErrorKind::InvalidInput.into())}let s=self.line()?;
  let f:Vec<_>=s.split(' ').collect();if f.len()!=6||f[0]!="READY"||f[1..].iter().any(|v|v.is_empty()||v.len()>20||!v.bytes().all(|b|b.is_ascii_digit())){return Err(io::ErrorKind::InvalidData.into())}self.state=2;Ok(s)}
 pub(super) fn authorize(&mut self,pid:u32)->io::Result<()>{if self.state!=2||pid==0{return Err(io::ErrorKind::InvalidInput.into())}writeln!(self.input,"{pid}")?;self.input.flush()?;if self.line()? != "VERIFIED"{return Err(io::ErrorKind::InvalidData.into())}self.state=3;Ok(())}
 pub(super) fn release(&mut self)->io::Result<String>{if self.state!=3{return Err(io::ErrorKind::InvalidInput.into())}writeln!(self.input,"G")?;self.input.flush()?;let s=self.line()?;
  let valid=valid_report(&s);
  if !valid{return Err(io::ErrorKind::InvalidData.into())}self.state=4;Ok(s)}
 pub(super) fn finish(&mut self)->io::Result<()> {if self.state!=4{return Err(io::ErrorKind::InvalidInput.into())}let deadline=Instant::now()+Duration::from_secs(3);let status=loop {match self.child.try_wait()? {Some(s)=>break s,None if Instant::now()<deadline=>std::thread::sleep(Duration::from_millis(10)),None=>return Err(io::ErrorKind::TimedOut.into())}};if !status.success(){return Err(io::ErrorKind::Other.into())}self.state=5;Ok(())}
}
impl Drop for Channel{fn drop(&mut self){if self.state!=5{let _=self.child.kill();let deadline=Instant::now()+Duration::from_secs(2);while Instant::now()<deadline {match self.child.try_wait(){Ok(Some(_))|Err(_)=>break,Ok(None)=>std::thread::sleep(Duration::from_millis(10))}}}}}
#[cfg(test)]mod tests{use super::*;#[test]fn report_parser_accepts_only_ordered_nonnegative_kernel_results(){for s in ["REPORT W=5","REPORT W=0 S=0","REPORT W=0 S=5"]{assert!(valid_report(s))}for s in ["REPORT W=0","REPORT W=5 S=0","REPORT W=-1","REPORT W=0 S=-1","REPORT W=9999999999","REPORT W=0 S=0 extra"]{assert!(!valid_report(s))}}}
