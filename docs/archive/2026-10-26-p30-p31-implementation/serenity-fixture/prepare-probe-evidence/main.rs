#![allow(dead_code)]
mod identity_guard;use identity_guard::Expected;mod btrfs_identity;mod private_mapper_node;
fn main(){let n="0123456789abcdef0123456789abcdef";let e=Expected{loop_major:7,loop_minor:1,backing_major:0,backing_minor:0,backing_inode:0,loop_ref:format!("ipse-q-{n}"),dm_name:format!("ipse-q-{n}"),dm_uuid:format!("IPSE-Q-{n}"),dm_major:252,dm_minor:1,sectors:1048576};let r=private_mapper_node::prepare(&e,4026531832,(7,1));eprintln!("ACTUAL_PREPARE={}",if r.is_ok(){"OK"}else{"ERR"});private_mapper_node::explain(&e,4026531832,(7,1));}
