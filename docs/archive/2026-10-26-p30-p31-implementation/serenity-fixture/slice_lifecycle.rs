//! Pure/mock lifecycle for the harmless slice proposal. No live executor exists.
#![allow(dead_code)]
#[path="slice_plan.rs"] mod plan;
#[path="cgroup_guard.rs"] mod checks;
use plan::{Plan,id_ok};

#[derive(Clone,Copy,Debug,PartialEq,Eq)] enum Stage { Empty,AnchorCreated,AnchorStarted,AnchorChecked,WorkCreated,WorkStarted,WorkChecked,KillPending,WorkStopped,ProofAccepted,AnchorStopPending,Finished,Unknown }
#[derive(Clone,Debug)] struct Anchor { id:String,parent_dev:u64,parent_inode:u64,pid:u32,start:u64 }
#[derive(Clone,Debug)] struct Evidence {
 parent_dev:u64,parent_inode:u64,parent_populated:bool,parent_direct_empty:bool,children:Vec<String>,
 anchor_id:String,anchor_pid:u32,anchor_start:u64,anchor_alive:bool,anchor_single_process:bool,
 workload_id:String,workload_running:bool,workload_all_pids_checked:bool,
 all_fds_known_and_safe:bool,readonly_cgroup:bool,uid_and_userns_checked:bool,seccomp_rules_attested:bool,
}
trait Backend {
 fn journal(&mut self,stage:Stage)->Result<(),()>;
 fn command(&mut self,args:&[String])->Result<String,()>;
 fn anchor(&mut self,p:&Plan,id:&str)->Result<Anchor,()>;
 fn evidence(&mut self,p:&Plan,a:&Anchor,id:&str)->Result<Evidence,()>;
}
fn same_anchor(a:&Anchor,e:&Evidence)->bool {a.parent_dev==e.parent_dev && a.parent_inode==e.parent_inode &&
 e.parent_populated && e.parent_direct_empty && e.anchor_id==a.id && e.anchor_pid==a.pid &&
 e.anchor_start==a.start && e.anchor_alive && e.anchor_single_process}
fn pre(a:&Anchor,e:&Evidence)->bool {same_anchor(a,e) && e.workload_running && e.workload_all_pids_checked &&
 e.all_fds_known_and_safe && e.readonly_cgroup && e.uid_and_userns_checked && e.seccomp_rules_attested &&
 checks::exact_children(&e.children,&[a.id.clone(),e.workload_id.clone()])}
fn post(a:&Anchor,e:&Evidence)->bool {same_anchor(a,e) && !e.workload_running && e.workload_all_pids_checked &&
 e.all_fds_known_and_safe && e.readonly_cgroup && e.uid_and_userns_checked && e.seccomp_rules_attested &&
 checks::exact_children(&e.children,std::slice::from_ref(&a.id))}
fn run<B:Backend>(b:&mut B,p:&Plan)->Stage {
 // Failure returns unknown without automatic kill, force, remove, or retry.
 if b.journal(Stage::Empty).is_err(){return Stage::Unknown;}
 let aid=match b.command(&p.create(true)){Ok(id) if id_ok(&id)=>id,_=>return Stage::Unknown};
 if b.journal(Stage::AnchorCreated).is_err(){return Stage::Unknown;}
 if b.command(&Plan::per_id("start",&aid).unwrap()).is_err() || b.journal(Stage::AnchorStarted).is_err(){return Stage::Unknown;}
 let a=match b.anchor(p,&aid){Ok(a) if a.id==aid && a.parent_dev>0 && a.parent_inode>0 && a.pid>0 && a.start>0=>a,_=>return Stage::Unknown};
 if b.journal(Stage::AnchorChecked).is_err(){return Stage::Unknown;}
 let wid=match b.command(&p.create(false)){Ok(id) if id_ok(&id)&&id!=aid=>id,_=>return Stage::Unknown};
 if b.journal(Stage::WorkCreated).is_err(){return Stage::Unknown;}
 if b.command(&Plan::per_id("start",&wid).unwrap()).is_err() || b.journal(Stage::WorkStarted).is_err(){return Stage::Unknown;}
 let before=match b.evidence(p,&a,&wid){Ok(v)=>v,_=>return Stage::Unknown};
 if before.workload_id!=wid || !pre(&a,&before) || b.journal(Stage::WorkChecked).is_err(){return Stage::Unknown;}
 if b.journal(Stage::KillPending).is_err() || b.command(&Plan::per_id("kill",&wid).unwrap()).is_err() ||
    b.command(&Plan::per_id("wait",&wid).unwrap()).is_err() || b.journal(Stage::WorkStopped).is_err(){return Stage::Unknown;}
 let after=match b.evidence(p,&a,&wid){Ok(v)=>v,_=>return Stage::Unknown};
 if after.workload_id!=wid || !post(&a,&after) || b.journal(Stage::ProofAccepted).is_err(){return Stage::Unknown;}
 // Actual cleanup requires fresh Docker ID/name/image and live parent checks
 // before each action. This mock deliberately does not yet implement it.
 Stage::ProofAccepted
}
fn main(){eprintln!("Live slice lifecycle is disabled; no real backend exists.");std::process::exit(2);}
#[cfg(test)] mod tests {
 use super::*;
 fn aid()->String{"a".repeat(64)} fn wid()->String{"b".repeat(64)}
 struct Mock {journal:Vec<Stage>,commands:Vec<Vec<String>>,refuse_pre:bool,refuse_post:bool,fail_at:Option<usize>}
 impl Mock {fn new()->Self{Self{journal:vec![],commands:vec![],refuse_pre:false,refuse_post:false,fail_at:None}}}
 impl Backend for Mock {
  fn journal(&mut self,s:Stage)->Result<(),()>{self.journal.push(s);Ok(())}
  fn command(&mut self,c:&[String])->Result<String,()>{self.commands.push(c.to_vec());
   if self.fail_at==Some(self.commands.len()){return Err(());}if c[0]=="create" {if self.commands.len()==1 {Ok(aid())}else{Ok(wid())}}else{Ok("ok".into())}}
  fn anchor(&mut self,_:&Plan,id:&str)->Result<Anchor,()>{Ok(Anchor{id:id.into(),parent_dev:30,parent_inode:50,pid:12,start:31})}
  fn evidence(&mut self,_:&Plan,a:&Anchor,id:&str)->Result<Evidence,()>{let after=self.commands.iter().any(|c|c[0]=="kill");
   Ok(Evidence{parent_dev:a.parent_dev,parent_inode:a.parent_inode,parent_populated:true,parent_direct_empty:true,
   children:if after {vec![format!("docker-{}.scope",a.id)]}else{vec![format!("docker-{}.scope",a.id),format!("docker-{id}.scope")]},
   anchor_id:a.id.clone(),anchor_pid:a.pid,anchor_start:a.start,anchor_alive:true,anchor_single_process:true,
   workload_id:id.into(),workload_running:!after,workload_all_pids_checked:true,all_fds_known_and_safe:true,
   readonly_cgroup:true,uid_and_userns_checked:true,seccomp_rules_attested:if after {!self.refuse_post}else{!self.refuse_pre}})}
 }
 #[test] fn only_complete_observation_reaches_scoped_kill_and_post_proof(){let mut b=Mock::new();let p=Plan::new(&"0".repeat(32),1000,1000).unwrap();
  assert_eq!(run(&mut b,&p),Stage::ProofAccepted); assert_eq!(b.commands.iter().filter(|c|c[0]=="kill").count(),1);
  assert_eq!(b.commands.iter().find(|c|c[0]=="kill").unwrap()[1],wid());assert!(!b.commands.iter().any(|c|c[0]=="rm")); }
 #[test] fn missing_seccomp_evidence_never_kills(){let mut b=Mock::new();b.refuse_pre=true;let p=Plan::new(&"0".repeat(32),1000,1000).unwrap();
  assert_eq!(run(&mut b,&p),Stage::Unknown);assert!(!b.commands.iter().any(|c|c[0]=="kill"));}
 #[test] fn changed_postcondition_does_not_claim_success_or_remove(){let mut b=Mock::new();b.refuse_post=true;let p=Plan::new(&"0".repeat(32),1000,1000).unwrap();
  assert_eq!(run(&mut b,&p),Stage::Unknown);assert!(!b.commands.iter().any(|c|c[0]=="rm"));}
 #[test] fn effect_failure_never_replays_or_auto_compensates(){let p=Plan::new(&"0".repeat(32),1000,1000).unwrap();
  for n in 1..=6 {let mut b=Mock::new();b.fail_at=Some(n);assert_eq!(run(&mut b,&p),Stage::Unknown);assert_eq!(b.commands.len(),n);}}
}
