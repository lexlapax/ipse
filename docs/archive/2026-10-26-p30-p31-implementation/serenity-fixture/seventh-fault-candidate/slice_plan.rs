//! Immutable command plan for the harmless sibling-anchor cgroup experiment.
//! No Docker call, cgroup read or host mutation is performed here.
#![allow(dead_code)]
const IMAGE:&str="sha256:757718cecb34fbe2c56e22b5f6299a45f149c7ce1c9b85def543a340bacdf7af";
#[derive(Clone,Debug,PartialEq,Eq)] pub(crate) struct Plan { pub(crate) nonce:String,pub(crate) uid:u32,pub(crate) gid:u32,pub(crate) slice:String,pub(crate) anchor:String,pub(crate) workload:String }
fn nonce_ok(s:&str)->bool {s.len()==32 && s.bytes().all(|b|b.is_ascii_digit()||(b'a'..=b'f').contains(&b))}
pub(crate) fn id_ok(s:&str)->bool {s.len()==64 && s.bytes().all(|b|b.is_ascii_digit()||(b'a'..=b'f').contains(&b))}
impl Plan {
 pub(crate) fn new(nonce:&str,uid:u32,gid:u32)->Option<Self>{
  if !nonce_ok(nonce)||uid==0||uid>65535||gid==0||gid>65535{return None;}
  Some(Self{nonce:nonce.into(),uid,gid,slice:format!("system-ipsequal{nonce}.slice"),
    anchor:format!("ipse-anchor-{nonce}"),workload:format!("ipse-workload-{nonce}")})
 }
 pub(crate) fn create(&self,anchor:bool)->Vec<String>{
  let name=if anchor {&self.anchor}else{&self.workload};
  let mut args:Vec<String>=["create","--name",name,"--pull","never","--network","none",
   "--read-only","--cap-drop","ALL","--security-opt","no-new-privileges:true",
   "--pids-limit","16","--memory","64m","--cgroup-parent",&self.slice,"--user"]
    .into_iter().map(str::to_string).collect();
  args.push(format!("{}:{}",self.uid,self.gid));args.push(IMAGE.into());
  if anchor {args.extend(["/usr/bin/sleep","60"].into_iter().map(str::to_string));}
  else {args.extend(["/usr/bin/sh","-c","/usr/bin/setsid /usr/bin/sleep 60 & wait"]
    .into_iter().map(str::to_string));} args
 }
 pub(crate) fn per_id(action:&str,id:&str)->Option<Vec<String>>{
  if !id_ok(id)||!matches!(action,"start"|"kill"|"wait"|"rm"){return None;}
  Some(vec![action.into(),id.into()])
 }
}
fn main(){eprintln!("Harmless slice execution is disabled pending independent review.");std::process::exit(2);}
#[cfg(test)] mod tests {
 use super::*;
 #[test] fn static_commands_are_scoped_and_have_no_device_or_host_mount() {
  let n="abcdef0123456789abcdef0123456789";let p=Plan::new(n,1000,1000).unwrap();
  for a in [p.create(true),p.create(false)] {
   assert_eq!(a[0],"create"); assert!(a.contains(&"--network".into())); assert!(a.contains(&"none".into()));
   assert!(a.contains(&"--read-only".into())); assert!(a.contains(&"--cap-drop".into()));
   assert!(a.contains(&"no-new-privileges:true".into())); assert!(a.contains(&p.slice));
   assert!(a.contains(&IMAGE.into())); assert!(!a.iter().any(|v|v=="--device"||v=="--mount"||v=="--privileged"));
  }
 }
 #[test] fn malformed_names_or_nonexact_ids_cannot_create_or_kill(){
  assert!(Plan::new("bad;id",1000,1000).is_none());assert!(Plan::new(&"a".repeat(32),0,1000).is_none());assert!(Plan::new(&"a".repeat(32),1000,0).is_none());
  assert!(Plan::per_id("rm","a").is_none());assert!(Plan::per_id("remove_all",&"a".repeat(64)).is_none());
  assert_eq!(Plan::per_id("kill",&"a".repeat(64)).unwrap(),vec!["kill","aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]);
 }
}
