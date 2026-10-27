//! Bounded, exclusive loop-index identity record for a future fixture.
//! Correlates a successful create receipt to one run; does not prove ownership
//! across restart, stable sysfs, cgroup quiescence, or authorize device removal.
use std::fs::File;
use std::io::{self,Read,Write};
use std::os::fd::{AsRawFd,FromRawFd};
use std::os::unix::fs::MetadataExt;
extern "C"{fn openat(fd:i32,path:*const i8,flags:i32,...)->i32;fn geteuid()->u32;}
#[derive(Debug,PartialEq,Eq)]pub(super) struct Provenance {pub(super) run:String,pub(super) index:u32,pub(super) node_dev:u64,pub(super) node_inode:u64,pub(super) control_dev:u64,pub(super) control_inode:u64}
fn valid(p:&Provenance)->bool {p.run.len()==32 && p.run.bytes().all(|b|b.is_ascii_digit()||(b'a'..=b'f').contains(&b)) && p.index<=4095 && p.node_inode>0 && p.control_inode>0}
fn open_named(dir:&File,flags:i32)->io::Result<File>{let name=c"loop.identity";let fd=unsafe{openat(dir.as_raw_fd(),name.as_ptr(),flags|0x20000|0x80000,0o600)};if fd<0{Err(io::Error::last_os_error())}else{Ok(unsafe{File::from_raw_fd(fd)})}}
pub(super) fn write_once(dir:&File,p:&Provenance)->io::Result<()> {
 let dm=dir.metadata()?;if !valid(p)||!dm.is_dir()||dm.uid()!=unsafe{geteuid()}||dm.mode()&0o777!=0o700{return Err(io::ErrorKind::PermissionDenied.into())}
 let mut file=open_named(dir,0x40|0x80|1)?;let fm=file.metadata()?;if !fm.is_file()||fm.uid()!=dm.uid()||fm.nlink()!=1{return Err(io::ErrorKind::PermissionDenied.into())}
 writeln!(file,"1 {} {} {} {} {} {}",p.run,p.index,p.node_dev,p.node_inode,p.control_dev,p.control_inode)?;
 file.sync_all()?;dir.sync_all()
}
pub(super) fn read(dir:&File,expected_run:&str)->io::Result<Provenance> {
 let dm=dir.metadata()?;if !dm.is_dir()||dm.uid()!=unsafe{geteuid()}||dm.mode()&0o777!=0o700{return Err(io::ErrorKind::PermissionDenied.into())}
 let file=open_named(dir,0)?;let fm=file.metadata()?;if !fm.is_file()||fm.uid()!=dm.uid()||fm.nlink()!=1||fm.len()>256{return Err(io::ErrorKind::PermissionDenied.into())}
 let mut bytes=Vec::new();file.take(257).read_to_end(&mut bytes)?;if !bytes.ends_with(b"\n")||bytes.len()>256{return Err(io::ErrorKind::InvalidData.into())}
 let text=std::str::from_utf8(&bytes).map_err(|_|io::ErrorKind::InvalidData)?;let f:Vec<_>=text.split_ascii_whitespace().collect();if f.len()!=7||f[0]!="1"{return Err(io::ErrorKind::InvalidData.into())}
 let parse=|s:&str|s.parse::<u64>().map_err(|_|io::ErrorKind::InvalidData);
 let index=parse(f[2])?;if index>4095{return Err(io::ErrorKind::InvalidData.into())}
 let p=Provenance{run:f[1].into(),index:index as u32,node_dev:parse(f[3])?,node_inode:parse(f[4])?,control_dev:parse(f[5])?,control_inode:parse(f[6])?};
 if !valid(&p)||p.run!=expected_run{return Err(io::ErrorKind::InvalidData.into())}Ok(p)
}
#[cfg(test)]mod tests{use super::*;use std::fs::{self,OpenOptions};use std::os::unix::fs::{PermissionsExt,OpenOptionsExt};
 #[test]fn record_is_exclusive_bounded_and_run_specific(){let path=std::env::temp_dir().join(format!("ipse-provenance-{}",std::process::id()));fs::create_dir(&path).unwrap();fs::set_permissions(&path,fs::Permissions::from_mode(0o700)).unwrap();let d=OpenOptions::new().read(true).custom_flags(0x30000).open(&path).unwrap();let p=Provenance{run:"0123456789abcdef0123456789abcdef".into(),index:42,node_dev:53,node_inode:123,control_dev:54,control_inode:456};write_once(&d,&p).unwrap();assert_eq!(read(&d,&p.run).unwrap(),p);assert!(write_once(&d,&p).is_err());assert!(read(&d,"ffffffffffffffffffffffffffffffff").is_err());drop(d);fs::remove_file(path.join("loop.identity")).unwrap();fs::remove_dir(path).unwrap();}
}
