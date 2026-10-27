//! Private, unreviewed Linux/x86-64 loop-owner confinement experiment.
//! It limits self-created FD aliases and process descendants; it does not prove
//! absence of preexisting refs, other processes, kernel refs or device cleanup.
#![allow(dead_code)]
use std::io;
#[repr(C)]#[derive(Clone,Copy)]struct Filter{code:u16,jt:u8,jf:u8,k:u32}
#[repr(C)]struct Prog{len:u16,filter:*const Filter}
unsafe extern "C"{fn prctl(option:i32,...)->i32;}
fn stmt(code:u16,k:u32)->Filter{Filter{code,jt:0,jf:0,k}}
fn jump(code:u16,k:u32,jt:u8,jf:u8)->Filter{Filter{code,jt,jf,k}}
/// Install only in a newly created, single-thread owner after independent FD
/// inventory. No undo exists. Trusted host root can still interfere.
pub(crate) fn install()->io::Result<()> {
 if !cfg!(all(target_os="linux",target_arch="x86_64")){return Err(io::ErrorKind::Unsupported.into())}
 // PR_SET_DUMPABLE=0 prevents ordinary same-UID ptrace/pidfd_getfd access.
 if unsafe{prctl(4,0,0,0,0)}!=0||unsafe{prctl(3,0,0,0,0)}!=0{return Err(io::Error::last_os_error())}
 if unsafe{prctl(38,1,0,0,0)}!=0{return Err(io::Error::last_os_error())} // NO_NEW_PRIVS
 let mut v=vec![stmt(0x20,4),jump(0x15,0xc000003e,1,0),stmt(0x06,0x80000000),stmt(0x20,0),jump(0x45,0x40000000,0,1),stmt(0x06,0x00050001)];
 // After activation, only anonymous mmap is allowed; file-backed mappings
 // could otherwise retain the loop file description after close.
 v.extend([jump(0x15,9,0,4),stmt(0x20,48),jump(0x15,0xffffffff,1,0),stmt(0x06,0x00050001),stmt(0x06,0x7fff0000)]);
 // fcntl only F_GETFD: reject all duplication and FD-flag mutation.
 v.extend([jump(0x15,72,0,4),stmt(0x20,24),jump(0x15,1,1,0),stmt(0x06,0x00050001),stmt(0x06,0x7fff0000)]);
 // syscalls which could create another task, FD alias, socket transfer,
 // asynchronous kernel FD registration or a new security/namespace context.
 for nr in [32,33,41,46,47,53,56,57,58,59,101,157,165,166,206,207,208,209,210,233,272,292,298,299,304,307,308,317,321,322,323,333,425,426,427,428,429,430,431,432,433,435,436,438,442] {v.push(jump(0x15,nr,0,1));v.push(stmt(0x06,0x00050001));}
 v.push(stmt(0x06,0x7fff0000));let prog=Prog{len:u16::try_from(v.len()).map_err(|_|io::ErrorKind::InvalidData)?,filter:v.as_ptr()};
 if unsafe{prctl(22,2,&prog as *const Prog,0,0)}!=0{return Err(io::Error::last_os_error())}Ok(())
}
#[cfg(test)]mod tests{use super::*;use std::os::fd::AsRawFd;unsafe extern "C"{fn ioctl(fd:i32,request:u64,...)->i32;fn fork()->i32;fn waitpid(pid:i32,status:*mut i32,opts:i32)->i32;fn syscall(n:i64,...)->i64;fn _exit(code:i32)->!;}
 #[test]fn isolated_child_refuses_dup_and_allows_getfd(){let pid=unsafe{fork()};assert!(pid>=0);if pid==0{let null=std::fs::File::open("/dev/null").unwrap();let result=install().is_ok();let probe=unsafe{ioctl(null.as_raw_fd(),0x4c05u64)};let ierr=io::Error::last_os_error().raw_os_error();let duplicate=unsafe{syscall(32,0)};let derr=io::Error::last_os_error().raw_os_error();let got=unsafe{syscall(72,0,1)};let fdup=unsafe{syscall(72,0,0,0)};let ferr=io::Error::last_os_error().raw_os_error();let undump=unsafe{prctl(4,1,0,0,0)};let perr=io::Error::last_os_error().raw_os_error();let socket=unsafe{syscall(41,-1,-1,-1)};let serr=io::Error::last_os_error().raw_os_error();let clone3=unsafe{syscall(435,0,0)};let cerr=io::Error::last_os_error().raw_os_error();let unshare=unsafe{syscall(272,0)};let uerr=io::Error::last_os_error().raw_os_error();let map=unsafe{syscall(9,0,4096,0,2,0,0)};let merr=io::Error::last_os_error().raw_os_error();let anon=unsafe{syscall(9,0,4096,3,0x22,-1,0)};if anon>=0{unsafe{syscall(11,anon,4096);}}let code=if result&&probe == -1&&ierr==Some(25)&&map == -1&&merr==Some(1)&&anon>=0&&duplicate == -1&&derr==Some(1)&&fdup == -1&&ferr==Some(1)&&undump == -1&&perr==Some(1)&&got>=0&&socket == -1&&serr==Some(1)&&clone3 == -1&&cerr==Some(1)&&unshare == -1&&uerr==Some(1) {0}else{1};unsafe{_exit(code)}}let mut status=0;assert_eq!(unsafe{waitpid(pid,&mut status,0)},pid);assert_eq!(status,0);}
}
