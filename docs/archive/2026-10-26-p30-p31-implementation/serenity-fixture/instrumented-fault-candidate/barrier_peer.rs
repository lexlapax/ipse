//! Pure evidence evaluator. This module does not obtain credentials or pin
//! identities; a future live backend must gather each field without races.
#[derive(Debug,PartialEq,Eq)]
pub(super) struct Identity { pub(super) pid: u32, pub(super) start: u64, pub(super) uid: u32, pub(super) exe_dev: u64, pub(super) exe_inode: u64 }
#[derive(Debug,PartialEq,Eq)]
pub(super) struct FileId {pub(super) dev: u64,pub(super) inode:u64,pub(super) links:u64,pub(super) size:u64}
pub(super) struct Evidence<'a> {
 pub(super) peer_before: &'a Identity, pub(super) peer_after: &'a Identity,
 pub(super) pidfd_bound: bool, pub(super) exe_immutable: bool,
 pub(super) expected_uid:u32, pub(super) expected_exe:(u64,u64),
 pub(super) port_to_os_pid_bound:bool, pub(super) scope_ticket_and_upstream_bound:bool,
 pub(super) pid_uid_namespace_mapping_proven:bool, pub(super) submitted_stage_bound:bool,
 pub(super) retained_file_and_directory_bound:bool, pub(super) filesystem_and_mapper_bound:bool,
 pub(super) scope_live:bool, pub(super) controller_live:bool,
 pub(super) pending_before: &'a FileId, pub(super) pending_after: &'a FileId,
 pub(super) expected_total:u64,
}
pub(super) fn authorized(e: &Evidence<'_>)->bool {
 let i=e.peer_before; let p=e.pending_before;
 i==e.peer_after && i.pid>0 && i.start>0 && i.uid==e.expected_uid &&
 (i.exe_dev,i.exe_inode)==e.expected_exe && i.exe_inode>0 &&
 e.pidfd_bound && e.exe_immutable && e.port_to_os_pid_bound && e.scope_ticket_and_upstream_bound && e.pid_uid_namespace_mapping_proven && e.submitted_stage_bound && e.retained_file_and_directory_bound && e.filesystem_and_mapper_bound &&
 e.scope_live && e.controller_live && p==e.pending_after && p.inode>0 && p.links==1 &&
 p.size>0 && p.size<e.expected_total
}
#[cfg(test)] mod tests {
 use super::*;
 #[test] fn refuses_unpinned_mismatched_or_ambiguous_identity() {
  let id=Identity{pid:42,start:321,uid:1000,exe_dev:2,exe_inode:3};
  let other=Identity{pid:42,start:322,uid:1000,exe_dev:2,exe_inode:3};
  let file=FileId{dev:4,inode:5,links:1,size:42};let altered=FileId{dev:4,inode:5,links:1,size:43};
  let mut e=Evidence {peer_before:&id,peer_after:&id,pidfd_bound:true,exe_immutable:true,expected_uid:1000,expected_exe:(2,3),port_to_os_pid_bound:true,scope_ticket_and_upstream_bound:true,pid_uid_namespace_mapping_proven:true,submitted_stage_bound:true,retained_file_and_directory_bound:true,filesystem_and_mapper_bound:true,scope_live:true,controller_live:true,pending_before:&file,pending_after:&file,expected_total:64};
  assert!(authorized(&e)); e.peer_after=&other;assert!(!authorized(&e));e.peer_after=&id;
  e.pending_after=&altered;assert!(!authorized(&e));e.pending_after=&file;
  e.pidfd_bound=false;assert!(!authorized(&e));e.pidfd_bound=true;
  e.exe_immutable=false;assert!(!authorized(&e));e.exe_immutable=true;
  e.port_to_os_pid_bound=false;assert!(!authorized(&e));e.port_to_os_pid_bound=true;
  e.scope_live=false;assert!(!authorized(&e));
 }
}
