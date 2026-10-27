//! Private disposable fixture root permission operation; no production use.
use std::{fs::{self,OpenOptions},io,os::unix::fs::{MetadataExt,OpenOptionsExt,PermissionsExt},path::Path};
pub(super) fn set_private(path:&Path,mut validate:impl FnMut(&std::fs::File)->io::Result<()>)->io::Result<()> {
 let file=OpenOptions::new().read(true).custom_flags(0x30000).open(path)?;let before=file.metadata()?;
 if !before.is_dir(){return Err(io::ErrorKind::PermissionDenied.into())}validate(&file)?;
 file.set_permissions(fs::Permissions::from_mode(0o700))?;file.sync_all()?;
 let after=file.metadata()?;let named=fs::symlink_metadata(path)?;
 if !named.is_dir()||(before.dev(),before.ino())!=(named.dev(),named.ino())||(after.dev(),after.ino())!=(named.dev(),named.ino())||after.mode()&0o7777!=0o700{return Err(io::ErrorKind::PermissionDenied.into())}validate(&file)
}
#[cfg(test)] mod tests{use super::*;use std::os::unix::fs::symlink;
 #[test] fn owned_root_mode_and_symlink_refusal(){let root=std::env::temp_dir().join(format!("ipse-mode-test-{}",std::process::id()));fs::create_dir(&root).unwrap();fs::set_permissions(&root,fs::Permissions::from_mode(0o755)).unwrap();assert!(set_private(&root,|_|Err(io::ErrorKind::PermissionDenied.into())).is_err());assert_eq!(fs::metadata(&root).unwrap().mode()&0o7777,0o755);let mut checks=0;set_private(&root,|_|{checks+=1;Ok(())}).unwrap();assert_eq!(checks,2);assert_eq!(fs::metadata(&root).unwrap().mode()&0o7777,0o700);let link=root.with_extension("link");symlink(&root,&link).unwrap();assert!(set_private(&link,|_|Ok(())).is_err());fs::remove_file(link).unwrap();fs::remove_dir(root).unwrap();}}
