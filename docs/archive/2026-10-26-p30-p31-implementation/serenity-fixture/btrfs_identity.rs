//! Read-only Btrfs filesystem/underlying-device identity probe. No mounting or
//! device writes. Running-kernel ABI and namespace remain subject to review.
use std::fs::{self,File};
use std::io;
use std::os::fd::AsRawFd;
use std::path::Path;
#[repr(C)]struct FsInfo{max_id:u64,num_devices:u64,fsid:[u8;16],nodesize:u32,sectorsize:u32,clone_alignment:u32,csum_type:u16,csum_size:u16,flags:u64,generation:u64,metadata_uuid:[u8;16],reserved:[u8;944]}
#[repr(C)]struct StatFs{kind:i64,block:i64,blocks:u64,free:u64,available:u64,files:u64,files_free:u64,fsid:[i32;2],names:i64,fragment:i64,flags:i64,spare:[i64;4]}
unsafe extern "C"{fn ioctl(fd:i32,request:u64,...)->i32;fn fstatfs(fd:i32,stat:*mut StatFs)->i32;}
const FS_INFO:u64=0x8400_941f;
#[derive(Debug,PartialEq,Eq)]pub(super) struct Identity {pub(super) fsid:[u8;16],pub(super) underlying:(u32,u32),pub(super) sectorsize:u32,pub(super) mount_id:u64}
fn mount_id(file:&File)->io::Result<u64>{let info=fs::read_to_string(format!("/proc/self/fdinfo/{}",file.as_raw_fd()))?;let mut ids=info.lines().filter_map(|s|s.strip_prefix("mnt_id:\t"));let n=ids.next().ok_or(io::ErrorKind::InvalidData)?.parse().map_err(|_|io::ErrorKind::InvalidData)?;if ids.next().is_some(){return Err(io::ErrorKind::InvalidData.into())}Ok(n)}
fn uuid(v:&[u8;16])->String{let mut s=String::new();for(i,b)in v.iter().enumerate(){if [4,6,8,10].contains(&i){s.push('-')}s.push_str(&format!("{b:02x}"));}s}
fn parse_device(s:&str)->io::Result<(u32,u32)>{let (a,b)=s.trim().split_once(':').ok_or(io::ErrorKind::InvalidData)?;let a=a.parse().map_err(|_|io::ErrorKind::InvalidData)?;let b=b.parse().map_err(|_|io::ErrorKind::InvalidData)?;Ok((a,b))}
pub(super) fn inspect(directory:&File,sysfs:&Path)->io::Result<Identity>{
 if !directory.metadata()?.is_dir()||std::mem::size_of::<FsInfo>()!=1024{return Err(io::ErrorKind::InvalidInput.into())}
 let sys=File::open(sysfs)?;let mut stat=std::mem::MaybeUninit::<StatFs>::uninit();if unsafe{fstatfs(sys.as_raw_fd(),stat.as_mut_ptr())}!=0||unsafe{stat.assume_init()}.kind!=0x62656572{return Err(io::ErrorKind::PermissionDenied.into())}
 let mut data:FsInfo=unsafe{std::mem::zeroed()};if unsafe{ioctl(directory.as_raw_fd(),FS_INFO,&mut data)}<0{return Err(io::Error::last_os_error())}
 if data.num_devices!=1||data.fsid==[0;16]||!data.sectorsize.is_power_of_two()||!(4096..=65536).contains(&data.sectorsize){return Err(io::ErrorKind::InvalidData.into())}
 let devices=sysfs.join("fs/btrfs").join(uuid(&data.fsid)).join("devices");let mut entries=fs::read_dir(devices)?;let entry=entries.next().ok_or(io::ErrorKind::NotFound)??;if entries.next().is_some()||!entry.file_type()?.is_symlink(){return Err(io::ErrorKind::InvalidData.into())}
 let underlying=parse_device(&fs::read_to_string(entry.path().join("dev"))?)?;
 Ok(Identity{fsid:data.fsid,underlying,sectorsize:data.sectorsize,mount_id:mount_id(directory)?})
}
#[cfg(test)]mod tests{use super::*;#[test]fn abi_and_device_parser(){assert_eq!(std::mem::size_of::<FsInfo>(),1024);assert_eq!(parse_device("259:12\n").unwrap(),(259,12));for v in ["1","1:2:3","x:2"]{assert!(parse_device(v).is_err())}}}
