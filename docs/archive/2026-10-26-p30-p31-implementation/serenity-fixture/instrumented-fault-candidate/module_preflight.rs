//! Candidate for separately reviewed Serenity module activation. No ioctl,
//! loop binding, mapper creation, mount or unload is performed. Module
//! autoload and default index creation are persistent host effects.
use std::fs::{self,File,OpenOptions};use std::io::{self,Write};use std::os::fd::{AsRawFd,FromRawFd};use std::os::unix::fs::{FileTypeExt,MetadataExt,OpenOptionsExt};
unsafe extern "C"{fn openat(d:i32,p:*const i8,f:i32,...)->i32;fn geteuid()->u32;fn syscall(n:i64,...)->i64;}
fn is_sysfs(f:&File)->io::Result<bool>{let mut data=[0u64;16];if unsafe{syscall(138,f.as_raw_fd(),data.as_mut_ptr())}<0{return Err(io::Error::last_os_error())}Ok(data[0]==0x62656572)}
fn module(root:&File,name:&str)->io::Result<bool>{let p=format!("/proc/self/fd/{}/module/{name}",root.as_raw_fd());match fs::symlink_metadata(p){Ok(m) if m.is_dir()=>Ok(true),Err(e) if e.kind()==io::ErrorKind::NotFound=>Ok(false),_=>Err(io::ErrorKind::InvalidData.into())}}
fn dev(major:u64,minor:u64)->u64{((major&0xfff)<<8)|((major&0xffff_f000)<<32)|(minor&0xff)|((minor&0xffff_ff00)<<12)}
fn run()->io::Result<()> {
 if !cfg!(ipse_live_reviewed){return Err(io::Error::new(io::ErrorKind::PermissionDenied,"module preflight disabled"))}
 let args:Vec<_>=std::env::args().collect();if args.len()!=2||args[1].len()!=32||!args[1].bytes().all(|b|b.is_ascii_digit()||(b'a'..=b'f').contains(&b)){return Err(io::ErrorKind::InvalidInput.into())}
 let sys=File::open("/sys")?;let sm=sys.metadata()?;let sn=fs::symlink_metadata("/sys")?;if !is_sysfs(&sys)?||(sm.dev(),sm.ino())!=(sn.dev(),sn.ino()){return Err(io::ErrorKind::PermissionDenied.into())}
 let dir=OpenOptions::new().read(true).custom_flags(0x30000).open("/work/fixture-ledger")?;let dm=dir.metadata()?;let dn=fs::symlink_metadata("/work/fixture-ledger")?;if !dm.is_dir()||dm.uid()!=unsafe{geteuid()}||dm.mode()&0o777!=0o700||(dm.dev(),dm.ino())!=(dn.dev(),dn.ino()){return Err(io::ErrorKind::PermissionDenied.into())}
 let name=c"module-load.receipt";let raw=unsafe{openat(dir.as_raw_fd(),name.as_ptr(),0x40|0x80|1|0x400|0x20000|0x80000,0o600)};if raw<0{return Err(io::Error::last_os_error())}let mut receipt=unsafe{File::from_raw_fd(raw)};let rm=receipt.metadata()?;if !rm.is_file()||rm.uid()!=dm.uid()||rm.nlink()!=1{return Err(io::ErrorKind::PermissionDenied.into())}
 writeln!(receipt,"v1 {} loop_before={} dm_before={}",args[1],module(&sys,"loop")?,module(&sys,"dm_mod")?)?;receipt.sync_all()?;dir.sync_all()?;
 for (kind,path,minor) in [("loop","/dev/loop-control",237u64),("dm","/dev/mapper/control",236u64)] {
  let named=fs::symlink_metadata(path)?;if !named.file_type().is_char_device()||named.rdev()!=dev(10,minor){return Err(io::ErrorKind::PermissionDenied.into())}
  writeln!(receipt,"pending {kind} node={} inode={} rdev={}",named.dev(),named.ino(),named.rdev())?;receipt.sync_data()?;
  let opened=OpenOptions::new().read(true).custom_flags(0x800|0x20000|0x80000).open(path);
  match opened {Ok(f)=>{let held=f.metadata()?;if (held.dev(),held.ino(),held.rdev())!=(named.dev(),named.ino(),named.rdev()){return Err(io::ErrorKind::PermissionDenied.into())}drop(f);writeln!(receipt,"opened {kind} module={}",module(&sys,if kind=="loop"{"loop"}else{"dm_mod"})?)?;receipt.sync_data()?},Err(e)=>{writeln!(receipt,"open-failed {kind} errno={} module={}",e.raw_os_error().unwrap_or(-1),module(&sys,if kind=="loop"{"loop"}else{"dm_mod"})?)?;receipt.sync_data()?;return Err(e)}}
 }
 println!("MODULE_PREFLIGHT_OBSERVED; preserve receipt and default indices");Ok(())
}
fn main(){if let Err(e)=run(){eprintln!("module outcome unknown: {e}");std::process::exit(2)}}
