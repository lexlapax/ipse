//! Test-only EIO sentinel. Live execution is disabled until reviewed; the Rust
//! mock tests do not open a block device or demonstrate actual kernel EIO.
#![allow(dead_code)]
use std::io;
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
#[derive(Debug,PartialEq,Eq)] enum Verdict { ObservedEio, UnexpectedSuccess, OtherError(i32), IdentityUnknown }
#[derive(Clone,Copy,Debug)] enum Stage { Identity, Write, Sync }
#[derive(Debug)] struct Failure { stage: Stage, error: io::Error }
fn classify(result: Result<(),Failure>) -> Verdict {
    match result { Ok(()) => Verdict::UnexpectedSuccess,
        Err(Failure {stage: Stage::Identity,..}) => Verdict::IdentityUnknown,
        Err(Failure {stage: Stage::Write | Stage::Sync,error}) if error.raw_os_error()==Some(5) => Verdict::ObservedEio,
        Err(Failure {error,..}) => Verdict::OtherError(error.raw_os_error().unwrap_or(-1)) }
}
trait Sentinel { fn dirty_and_sync(&mut self) -> Result<(),Failure>; }
fn after_fault<T:Sentinel>(sentinel: &mut T) -> Verdict { classify(sentinel.dirty_and_sync()) }
struct FileSentinel { path: PathBuf, file: File, dev: u64, ino: u64 }
impl FileSentinel {
    fn prepare(path: &Path) -> io::Result<Self> {
        if path != Path::new("/work/mount/ipse-fault-sentinel") {
            return Err(io::Error::other("unexpected sentinel path"));
        }
        let file=OpenOptions::new().read(true).write(true).create_new(true).mode(0o600)
            .custom_flags(0x20000).open(path)?; // Linux O_NOFOLLOW
        let metadata=file.metadata()?;
        if !metadata.is_file() || metadata.nlink()!=1 || metadata.mode()&0o777!=0o600 {
            return Err(io::Error::other("unexpected sentinel identity"));
        }
        Ok(Self {path:path.to_owned(),file,dev:metadata.dev(),ino:metadata.ino()})
    }
    fn identity(&self) -> io::Result<()> {
        let held=self.file.metadata()?; let named=std::fs::symlink_metadata(&self.path)?;
        if !named.is_file() || named.nlink()!=1 || held.nlink()!=1 ||
           held.dev()!=self.dev || named.dev()!=self.dev || held.ino()!=self.ino || named.ino()!=self.ino {
            return Err(io::Error::other("sentinel identity changed"));
        }
        Ok(())
    }
}
impl Sentinel for FileSentinel {
    fn dirty_and_sync(&mut self) -> Result<(),Failure> {
        self.identity().map_err(|error|Failure{stage:Stage::Identity,error})?;
        let mut x=0x5ae4_78c2_8a31_75d9u64;
        let mut bytes=[0u8;16_384];
        for byte in &mut bytes { x ^= x<<13; x ^= x>>7; x ^= x<<17; *byte=x as u8; }
        self.file.write_all(&bytes).map_err(|error|Failure{stage:Stage::Write,error})?;
        self.file.sync_all().map_err(|error|Failure{stage:Stage::Sync,error})?;
        self.identity().map_err(|error|Failure{stage:Stage::Identity,error})
    }
}
fn main() { eprintln!("Live EIO sentinel disabled until reviewed."); std::process::exit(2); }
#[cfg(test)] mod tests {
    use super::*;
    struct Fake(Option<(Stage,i32)>);
    impl Sentinel for Fake { fn dirty_and_sync(&mut self)->Result<(),Failure> {
        match self.0 { None=>Ok(()),Some((stage,n))=>Err(Failure{stage,error:io::Error::from_raw_os_error(n)}) }
    }}
    #[test] fn explicit_eio_only_is_the_expected_failure() {
        assert_eq!(after_fault(&mut Fake(Some((Stage::Sync,5)))),Verdict::ObservedEio);
        assert_eq!(after_fault(&mut Fake(Some((Stage::Write,5)))),Verdict::ObservedEio);
        assert_eq!(after_fault(&mut Fake(Some((Stage::Identity,5)))),Verdict::IdentityUnknown);
        assert_eq!(after_fault(&mut Fake(Some((Stage::Write,28)))),Verdict::OtherError(28));
        assert_eq!(after_fault(&mut Fake(None)),Verdict::UnexpectedSuccess);
    }
}
