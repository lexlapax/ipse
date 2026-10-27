//! Read-only observation of a retained Docker bind and one possible Btrfs
//! overlay. This is not a global mount-quiescence or unmount proof.
use std::fs::{self,File,OpenOptions};use std::io::{self,Read};use std::os::unix::fs::{MetadataExt,OpenOptionsExt};use std::path::{Path,PathBuf};
use super::btrfs_identity::mount_id;
#[derive(Debug,PartialEq,Eq)]enum View {Original,Overlay(u64)}
fn parse(text:&str,target:&str,id:u64,original:&str)->io::Result<View>{
 if id==0||target.is_empty()||!target.starts_with('/')||target.contains('\\'){return Err(io::ErrorKind::InvalidInput.into())}
 let mut ids=std::collections::HashSet::new();let mut baseline=false;let mut overlay=None;let mut rows=0;
 for line in text.lines(){let (left,right)=line.split_once(" - ").ok_or(io::ErrorKind::InvalidData)?;let l:Vec<_>=left.split_whitespace().collect();let r:Vec<_>=right.split_whitespace().collect();if l.len()<6||r.len()<3{return Err(io::ErrorKind::InvalidData.into())}let mid:u64=l[0].parse().map_err(|_|io::ErrorKind::InvalidData)?;if mid==0||!ids.insert(mid){return Err(io::ErrorKind::InvalidData.into())}
  if l[4].starts_with(&format!("{target}/")) || (l[4].starts_with(target)&&l[4].contains('\\')){return Err(io::ErrorKind::PermissionDenied.into())}
  if l[4]!=target {continue}rows+=1;if rows>2{return Err(io::ErrorKind::PermissionDenied.into())}
  if mid==id {if baseline||line!=original||r[0]!="tmpfs"{return Err(io::ErrorKind::PermissionDenied.into())}baseline=true}
  else {if overlay.is_some()||r[0]!="btrfs"||l[6..].iter().any(|x|x.starts_with("shared:")||x.starts_with("master:")||x.starts_with("propagate_from:")){return Err(io::ErrorKind::PermissionDenied.into())}overlay=Some(mid)}
 }
 if !baseline{return Err(io::ErrorKind::PermissionDenied.into())}match overlay {None if rows==1=>Ok(View::Original),Some(n) if rows==2=>Ok(View::Overlay(n)),_=>Err(io::ErrorKind::PermissionDenied.into())}
}
fn snapshot()->io::Result<String>{let mut s=String::new();File::open("/proc/self/mountinfo")?.take(1_048_577).read_to_string(&mut s)?;if s.len()>1_048_576{return Err(io::ErrorKind::InvalidData.into())}Ok(s)}
pub(super) struct Bind {pin:File,path:PathBuf,id:u64,dev:u64,inode:u64,ns:u64,line:String}
impl Bind {
 pub(super) fn capture(path:&Path)->io::Result<Self>{let target=path.to_str().ok_or(io::ErrorKind::InvalidInput)?;let pin=OpenOptions::new().read(true).custom_flags(0x30000).open(path)?;let m=pin.metadata()?;let named=fs::symlink_metadata(path)?;if !m.is_dir()||(m.dev(),m.ino())!=(named.dev(),named.ino()){return Err(io::ErrorKind::PermissionDenied.into())}let id=mount_id(&pin)?;let ns=fs::metadata("/proc/self/ns/mnt")?.ino();let snap=snapshot()?;let mut matching=snap.lines().filter(|line|{let f:Vec<_>=line.split_whitespace().collect();f.len()>4&&f[4]==target});let line=matching.next().ok_or(io::ErrorKind::NotFound)?.to_owned();if matching.next().is_some(){return Err(io::ErrorKind::PermissionDenied.into())}if parse(&snap,target,id,&line)?!=View::Original{return Err(io::ErrorKind::PermissionDenied.into())}let fields:Vec<_>=line.split_once(" - ").ok_or(io::ErrorKind::InvalidData)?.0.split_whitespace().collect();if fields[6..].iter().any(|x|x.starts_with("shared:")||x.starts_with("master:")||x.starts_with("propagate_from:")){return Err(io::ErrorKind::PermissionDenied.into())}Ok(Self{pin,path:path.to_owned(),id,dev:m.dev(),inode:m.ino(),ns,line})}
 /// None means the exact retained original bind is currently visible; Some is
 /// one candidate overlay ID, still requiring separate Btrfs/device proof.
 pub(super) fn observe(&self)->io::Result<Option<u64>> {let held=self.pin.metadata()?;if fs::metadata("/proc/self/ns/mnt")?.ino()!=self.ns||mount_id(&self.pin)?!=self.id||(held.dev(),held.ino())!=(self.dev,self.inode){return Err(io::ErrorKind::PermissionDenied.into())}let view=parse(&snapshot()?,self.path.to_str().ok_or(io::ErrorKind::InvalidInput)?,self.id,&self.line)?;let visible=OpenOptions::new().read(true).custom_flags(0x30000).open(&self.path)?;let named=fs::symlink_metadata(&self.path)?;let m=visible.metadata()?;if (m.dev(),m.ino())!=(named.dev(),named.ino()){return Err(io::ErrorKind::PermissionDenied.into())}let actual=mount_id(&visible)?;match view {View::Original if actual==self.id&&(m.dev(),m.ino())==(self.dev,self.inode)=>Ok(None),View::Overlay(id) if actual==id=>Ok(Some(id)),_=>Err(io::ErrorKind::PermissionDenied.into())}}
}
#[cfg(test)]mod tests {use super::*;const BASE:&str="22 3 0:53 /stage /work/mount rw - tmpfs tmpfs rw";
 #[test]fn original_and_one_btrfs_overlay_are_distinct(){let plain=format!("{BASE}\n");assert_eq!(parse(&plain,"/work/mount",22,BASE).unwrap(),View::Original);let overlay=format!("{BASE}\n23 22 0:81 / /work/mount rw - btrfs /dev/dm-1 rw\n");assert_eq!(parse(&overlay,"/work/mount",22,BASE).unwrap(),View::Overlay(23));}
 #[test]fn changed_missing_nested_or_stacked_mounts_are_refused(){for s in ["23 3 0:81 / /work/mount rw - btrfs x rw\n".to_owned(),format!("{}\n",BASE.replace("rw -","ro -")),format!("{BASE}\n23 22 0:81 / /work/mount rw - btrfs x rw\n24 23 0:82 / /work/mount rw - btrfs y rw\n"),format!("{BASE}\n24 22 0:82 / /work/mount/sub rw - tmpfs x rw\n"),format!("{BASE}\n23 22 0:81 / /work/mount rw shared:1 - btrfs x rw\n")] {assert!(parse(&s,"/work/mount",22,BASE).is_err())}}
}
