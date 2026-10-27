//! Read-only, bounded independently running observer; never performs recovery.
#![allow(dead_code)]
#[path="recovery_ledger.rs"] mod recovery_ledger;
#[path="recovery_guardian.rs"] mod recovery_guardian;
use std::path::Path;
use std::time::Duration;
fn main()->Result<(),Box<dyn std::error::Error>>{
 let args:Vec<_>=std::env::args().collect();if args.len()!=5{return Err("usage: observer DIRECTORY NONCE PID STARTTIME".into())}
 let pid:u32=args[3].parse()?;let start:u64=args[4].parse()?;
 let result=recovery_guardian::watch(Path::new(&args[1]),&args[2],pid,start,Duration::from_secs(15))?;
 println!("{result:?}");Ok(())
}
