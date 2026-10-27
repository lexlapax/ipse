//! Private integration driver; no block device use.
#![allow(dead_code)]
#[path="peer_channel.rs"]mod peer_channel;
use std::io::{self,Write};use std::time::{Duration,Instant};
#[repr(C)]struct PollFd{fd:i32,events:i16,revents:i16}
extern "C"{fn poll(fd:*mut PollFd,n:usize,t:i32)->i32;fn read(fd:i32,buf:*mut std::ffi::c_void,n:usize)->isize;}
fn input()->io::Result<String>{let deadline=Instant::now()+Duration::from_secs(3);let mut v=Vec::new();loop {let rem=deadline.saturating_duration_since(Instant::now());if rem.is_zero(){return Err(io::ErrorKind::TimedOut.into())}let mut p=PollFd{fd:0,events:1,revents:0};if unsafe{poll(&mut p,1,rem.as_millis().min(3000) as i32)}!=1{return Err(io::ErrorKind::TimedOut.into())}let mut b=[0];if unsafe{read(0,b.as_mut_ptr().cast(),1)}!=1{return Err(io::ErrorKind::UnexpectedEof.into())}if b[0]==b'\n'{break}if v.len()>=16||!b[0].is_ascii_alphanumeric(){return Err(io::ErrorKind::InvalidData.into())}v.push(b[0]);}String::from_utf8(v).map_err(|_|io::ErrorKind::InvalidData.into())}
fn main()->io::Result<()> {let a:Vec<_>=std::env::args().collect();if a.len()!=2{return Err(io::ErrorKind::InvalidInput.into())}
 let mut c=peer_channel::Channel::start(&a[1])?;println!("LISTENING");io::stdout().flush()?;println!("{}",c.ready()?);io::stdout().flush()?;
 let pid:u32=input()?.parse().map_err(|_|io::ErrorKind::InvalidData)?;c.authorize(pid)?;println!("VERIFIED");io::stdout().flush()?;
 if input()? != "G"{return Err(io::ErrorKind::InvalidData.into())}println!("{}",c.release()?);io::stdout().flush()?;c.finish()
}
