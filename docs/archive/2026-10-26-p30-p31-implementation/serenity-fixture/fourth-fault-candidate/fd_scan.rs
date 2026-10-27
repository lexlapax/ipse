//! Read-only descriptor sample. It is NOT a proof without an independently
//! frozen, identity-bound target and complete /proc access. No process is
//! signalled by this code. Failed statfs/readlink or changing rows refuse.
#![allow(dead_code)]
use std::collections::BTreeMap;
use std::ffi::{c_char,c_int,CString};
use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::path::Path;
unsafe extern "C" { fn statfs(path:*const c_char, stat:*mut usize)->c_int; }
const CGROUP2_MAGIC:usize=0x6367_7270;
fn entries(pid:u32)->Result<BTreeMap<u32,(std::path::PathBuf,usize)>,()> {
    let directory=format!("/proc/{pid}/fd");
    let mut result=BTreeMap::new();
    for entry in fs::read_dir(directory).map_err(|_|())? {
        let entry=entry.map_err(|_|())?;
        let number=entry.file_name().to_str().ok_or(())?.parse::<u32>().map_err(|_|())?;
        if result.len()>=4096{return Err(());}
        let path=entry.path(); let link=fs::read_link(&path).map_err(|_|())?;
        let cpath=CString::new(Path::new(&path).as_os_str().as_bytes()).map_err(|_|())?;
        let mut stat=[0usize;32];
        if unsafe {statfs(cpath.as_ptr(),stat.as_mut_ptr())}!=0 {return Err(());}
        if result.insert(number,(link,stat[0])).is_some(){return Err(());}
    }
    Ok(result)
}
fn no_cgroup_fds(pid:u32)->Result<bool,()> {
    let before=entries(pid)?; let after=entries(pid)?;
    if before!=after{return Err(());}
    Ok(before.values().all(|(_,kind)|*kind!=CGROUP2_MAGIC))
}
fn main(){ eprintln!("Live foreign-process FD scanning disabled pending audit."); std::process::exit(2); }
#[cfg(test)] mod tests {
    use super::*;
    #[test] fn unavailable_pid_is_not_empty_success() {
        assert!(entries(u32::MAX).is_err());
    }
    #[test] fn deliberate_cgroup_descriptor_is_detected_on_self() {
        let fd=std::fs::File::open("/sys/fs/cgroup").unwrap();
        use std::os::fd::AsRawFd;
        let id=fd.as_raw_fd() as u32;
        let values=entries(std::process::id()).unwrap();
        assert_eq!(values[&id].1,CGROUP2_MAGIC);
        assert!(!no_cgroup_fds(std::process::id()).unwrap());
    }
}
