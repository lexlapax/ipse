//! Bounded adapter for a separately launched, authenticated BEAM stage process.
//! The caller must retain the Child and prove executable/cgroup identity.
use std::fs::File;use std::io::{self,Write};use std::os::fd::{AsRawFd,OwnedFd};use std::process::Child;use std::time::{Duration,Instant};
#[repr(C)]struct PollFd{fd:i32,events:i16,revents:i16}unsafe extern "C"{fn poll(p:*mut PollFd,n:usize,t:i32)->i32;fn read(fd:i32,b:*mut std::ffi::c_void,n:usize)->isize;}
pub(super) struct Stage {child:Child,input:File,output:File,state:u8,pidfd:Option<File>}
impl Stage {
 pub(super) fn from_child(mut child:Child)->Result<Self,(Child,io::Error)> {let input=match child.stdin.take(){Some(v)=>v,None=>return Err((child,io::ErrorKind::BrokenPipe.into()))};let output=match child.stdout.take(){Some(v)=>v,None=>return Err((child,io::ErrorKind::BrokenPipe.into()))};Ok(Self{child,input:File::from(OwnedFd::from(input)),output:File::from(OwnedFd::from(output)),state:0,pidfd:None})}
 fn line(&mut self)->io::Result<String>{let end=Instant::now()+Duration::from_secs(10);let mut out=Vec::new();loop {let left=end.saturating_duration_since(Instant::now());if left.is_zero(){return Err(io::ErrorKind::TimedOut.into())}let mut p=PollFd{fd:self.output.as_raw_fd(),events:1,revents:0};if unsafe{poll(&mut p,1,left.as_millis().min(10_000) as i32)}!=1||p.revents&1==0{return Err(io::ErrorKind::TimedOut.into())}let mut b=[0u8];if unsafe{read(self.output.as_raw_fd(),b.as_mut_ptr().cast(),1)}!=1{return Err(io::ErrorKind::UnexpectedEof.into())}if b[0]==b'\n'{break}if out.len()>=128 {eprintln!("STAGE_DIAG line_overlong");return Err(io::ErrorKind::InvalidData.into())}if !b[0].is_ascii(){eprintln!("STAGE_DIAG line_non_ascii");return Err(io::ErrorKind::InvalidData.into())}out.push(b[0]);}String::from_utf8(out).map_err(|_|io::ErrorKind::InvalidData.into())}
 pub(super) fn attest_and_activate(&mut self,executable:&File)->io::Result<()> {if self.state!=0{return Err(io::ErrorKind::InvalidInput.into())}if self.line()?!="STAGE_ARMED"{return Err(io::ErrorKind::InvalidData.into())}let proof=super::held_loop_client::attest(self.child.id(),executable,&self.input,&self.output)?;proof.verify_pipes(&self.input,&self.output)?;self.input.write_all(b"AUTH\n")?;self.input.flush()?;self.pidfd=Some(proof.into_pidfd());self.state=1;Ok(())}
 pub(super) fn prepare(&mut self)->io::Result<u32>{if self.state!=1{return Err(io::ErrorKind::InvalidInput.into())}let s=self.line()?;let n=s.strip_prefix("OWNER ").ok_or(io::ErrorKind::InvalidData)?;if n.is_empty()||n.len()>10||!n.bytes().all(|b|b.is_ascii_digit()) {return Err(io::ErrorKind::InvalidData.into())}let pid=n.parse::<u32>().map_err(|_|io::ErrorKind::InvalidData)?;if pid==0{return Err(io::ErrorKind::InvalidData.into())}self.state=2;Ok(pid)}
 pub(super) fn begin(&mut self)->io::Result<()> {if self.state!=2{return Err(io::ErrorKind::InvalidInput.into())}self.input.write_all(b"GO\n")?;self.input.flush()?;self.state=3;Ok(())}
 pub(super) fn finish(&mut self,report:&str)->io::Result<()> {if self.state!=3{return Err(io::ErrorKind::InvalidInput.into())}let diag=self.line()?;let category=stage_category(&diag).ok_or_else(||{eprintln!("STAGE_DIAG category_invalid");io::ErrorKind::InvalidData})?;eprintln!("STAGE_DIAG outcome_category={category}");let line=self.line()?;eprintln!("STAGE_DIAG line_category={}",line_category(&line));if !category_consistent(category,&line)||!consistent(report,&line){return Err(io::ErrorKind::InvalidData.into())}let deadline=Instant::now()+Duration::from_secs(5);loop {match self.child.try_wait()? {Some(s) if s.success()=>break,Some(_)=>{eprintln!("STAGE_DIAG child_failed");return Err(io::ErrorKind::Other.into())},None if Instant::now()<deadline=>std::thread::sleep(Duration::from_millis(10)),None=>{eprintln!("STAGE_DIAG child_timeout");return Err(io::ErrorKind::TimedOut.into())}}}self.state=4;Ok(())}
}
fn stage_category(line:&str)->Option<&'static str> {match line {"STAGE_DIAG stage=ok scope=ok"=>Some("ok_ok"),"STAGE_DIAG stage=ok scope=other"=>Some("ok_other"),"STAGE_DIAG stage=error scope=ok"=>Some("error_ok"),"STAGE_DIAG stage=error scope=other"=>Some("error_other"),"STAGE_DIAG stage=other scope=ok"=>Some("other_ok"),"STAGE_DIAG stage=other scope=other"=>Some("other_other"),_=>None}}
fn line_category(line:&str)->&'static str {match line {"STAGE_OK SCOPE_OK"=>"stage_ok_scope_ok","STAGE_ERROR SCOPE_OK"=>"stage_error_scope_ok","STAGE_UNKNOWN"=>"stage_unknown",_=>"unexpected"}}
fn category_consistent(category:&str,line:&str)->bool {match category {"ok_ok"=>line=="STAGE_OK SCOPE_OK","error_ok"=>line=="STAGE_ERROR SCOPE_OK","ok_other"|"error_other"|"other_ok"|"other_other"=>line=="STAGE_UNKNOWN",_=>false}}
fn consistent(report:&str,line:&str)->bool {if report=="REPORT W=0 S=0" {line=="STAGE_OK SCOPE_OK"} else if let Some(v)=report.strip_prefix("REPORT W=") {if let Some((w,s))=v.split_once(" S="){w=="0"&&s.parse::<i32>().is_ok_and(|n|n>0)&&line=="STAGE_ERROR SCOPE_OK"}else{v.parse::<i32>().is_ok_and(|n|n>0)&&line=="STAGE_ERROR SCOPE_OK"}} else {false}}
#[cfg(test)]mod tests {use super::*;#[test]fn stage_categories_are_allowlisted(){assert_eq!(stage_category("STAGE_DIAG stage=error scope=ok"),Some("error_ok"));assert_eq!(stage_category("STAGE_DIAG stage=private scope=ok"),None);assert_eq!(stage_category("STAGE_DIAG stage=other scope=other"),Some("other_other"));}#[test]fn categories_do_not_echo_unexpected_content(){assert_eq!(line_category("STAGE_UNKNOWN"),"stage_unknown");assert_eq!(line_category("STAGE_ERROR SCOPE_OK"),"stage_error_scope_ok");assert_eq!(line_category("private payload"),"unexpected");}#[test]fn reports_must_match_the_scoped_stage_outcome(){assert!(consistent("REPORT W=0 S=0","STAGE_OK SCOPE_OK"));assert!(consistent("REPORT W=5","STAGE_ERROR SCOPE_OK"));assert!(consistent("REPORT W=0 S=5","STAGE_ERROR SCOPE_OK"));for (a,b) in [("REPORT W=5","STAGE_OK SCOPE_OK"),("REPORT W=0 S=0","STAGE_ERROR SCOPE_OK"),("REPORT W=0 S=5","STAGE_UNKNOWN"),("REPORT W=0 S=-1","STAGE_ERROR SCOPE_OK")] {assert!(!consistent(a,b));}}}

#[cfg(test)]
mod stage_protocol_tests {
 use super::*;
 use std::process::{Command,Stdio};

 fn finish_with(output:&str,report:&str)->io::Result<()> {
  let child=Command::new("/bin/sh").args(["-c", "printf '%s' \"$1\"", "stage-test", output])
   .stdin(Stdio::piped()).stdout(Stdio::piped()).spawn()?;
  let mut stage=Stage::from_child(child).map_err(|(_,e)|e)?;
  stage.state=3;
  let result=stage.finish(report);
  let _=stage.child.wait();
  result
 }

 #[test]
 fn real_pipe_requires_matching_diagnostic_and_stage_result() {
  assert!(finish_with("STAGE_DIAG stage=error scope=ok\nSTAGE_ERROR SCOPE_OK\n","REPORT W=0 S=5").is_ok());
  for output in [
   "STAGE_DIAG stage=other scope=other\nSTAGE_ERROR SCOPE_OK\n",
   "STAGE_DIAG stage=error scope=ok\nSTAGE_UNKNOWN\n",
   "STAGE_DIAG stage=private scope=ok\nSTAGE_ERROR SCOPE_OK\n",
   "STAGE_DIAG stage=error scope=other\nSTAGE_UNKNOWN\n",
  ] {assert_eq!(finish_with(output,"REPORT W=0 S=5").unwrap_err().kind(),io::ErrorKind::InvalidData);}
 }
}
