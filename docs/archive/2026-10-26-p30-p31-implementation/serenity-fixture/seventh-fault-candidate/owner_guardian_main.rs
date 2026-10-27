//! Private test-only external guardian. No device actions or live launcher.
#![allow(dead_code)]
#[path="owner_guardian.rs"]mod owner_guardian;
use std::fs::OpenOptions;use std::os::unix::fs::OpenOptionsExt;
fn main()->Result<(),Box<dyn std::error::Error>>{let a:Vec<_>=std::env::args().collect();if a.len()!=8{return Err("usage: DIR NONCE SUPERVISOR START OWNER START TIMEOUT_MS".into())}let dir=OpenOptions::new().read(true).custom_flags(0x30000).open(&a[1])?;let _result=owner_guardian::watch(&dir,&a[2],a[3].parse()?,a[4].parse()?,a[5].parse()?,a[6].parse()?,a[7].parse()?)?;Ok(())}
