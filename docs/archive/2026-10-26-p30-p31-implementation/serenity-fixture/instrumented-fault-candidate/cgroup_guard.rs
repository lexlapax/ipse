//! Pure checks for a proposed unique Docker sibling-anchor scope experiment.
//! No filesystem, cgroup or Docker effects are performed by this module.
use std::collections::BTreeSet;
fn hex(v: &str, size: usize) -> bool {
    v.len()==size && v.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}
pub(crate) fn group_path(value: &str, nonce: &str, id: &str) -> Option<String> {
    if !hex(nonce,32) || !hex(id,64) || value.len()>8192 { return None; }
    let mut lines=value.lines(); let only=lines.next()?;
    if lines.next().is_some() {return None;}
    let expected=format!("/system.slice/system-ipsequal{nonce}.slice/docker-{id}.scope");
    if only==format!("0::{expected}") {Some(expected)} else {None}
}
pub(crate) fn status_ok(value: &str, uid: u32) -> bool {
    if value.len()>65_536 {return false;}
    let get=|name: &str| -> Option<&str> {
        let vals:Vec<_>=value.lines().filter_map(|line|line.strip_prefix(name).map(str::trim)).collect();
        if vals.len()==1 {Some(vals[0])} else {None}
    };
    let ids:Vec<_>=get("Uid:").unwrap_or("").split_ascii_whitespace().collect();
    ids.len()==4 && ids.iter().all(|x|x.parse::<u32>()==Ok(uid)) &&
        get("CapEff:").and_then(|s|u64::from_str_radix(s,16).ok())==Some(0) &&
        get("NoNewPrivs:")==Some("1") && get("Seccomp:")==Some("2")
}
/// Necessary, not sufficient: matching the initial user namespace and uid map
/// says nothing about actual seccomp filter rules or cgroup DAC permissions.
pub(crate) fn host_user_namespace(uid_map: &str, host_inode:u64, target_inode:u64) -> bool {
    host_inode>0 && host_inode==target_inode &&
        uid_map.lines().count()==1 &&
        uid_map.split_ascii_whitespace().collect::<Vec<_>>()==["0","0","4294967295"]
}
/// Deliberately conservative: any inherited descriptor on cgroup2 is refused,
/// regardless of access mode. An unknown filesystem/failed fstatfs refuses.
pub(crate) fn no_cgroup_descriptors(fs_types:&[Option<u64>]) -> bool {
    fs_types.len()<=4096 && fs_types.iter().all(|v|matches!(v,Some(kind) if *kind!=0x6367_7270))
}
pub(crate) fn only_readonly_cgroup2(mounts: &str) -> bool {
    if mounts.len()>1_048_576 {return false;}
    let mut found=0usize;
    for line in mounts.lines() {
        let Some((left,right))=line.split_once(" - ") else {return false;};
        let a:Vec<_>=left.split_ascii_whitespace().collect();
        let b:Vec<_>=right.split_ascii_whitespace().collect();
        if a.len()<6 || b.len()<3 {return false;}
        if b[0]=="cgroup2" {
            found+=1;
            if !a[5].split(',').any(|s|s=="ro") {return false;}
        }
    }
    found>0
}
pub(crate) fn proc_identity(stat: &str, expected_pid: u32) -> Option<u64> {
    if stat.len()>65_536 {return None;}
    let open=stat.find('(')?; let close=stat.rfind(')')?;
    if close<=open || stat[..open].trim().parse::<u32>().ok()? != expected_pid {return None;}
    let rest:Vec<_>=stat[close+1..].split_ascii_whitespace().collect();
    // Field 3 is rest[0]; field 22 (starttime) is rest[19].
    let ticks=rest.get(19)?.parse::<u64>().ok()?;
    if ticks==0 {None} else {Some(ticks)}
}
pub(crate) fn exact_children(children:&[String], ids:&[String]) -> bool {
    if ids.len()>2 || ids.iter().any(|x|!hex(x,64)) || children.len()!=ids.len() {return false;}
    let actual: BTreeSet<_> = children.iter().cloned().collect();
    let expected: BTreeSet<_> = ids.iter().map(|id|format!("docker-{id}.scope")).collect();
    actual.len()==children.len() && actual==expected
}
pub(crate) fn populated(events:&str) -> Option<bool> {
    if events.len()>8192 {return None;}
    let values:Vec<_>=events.lines().filter_map(|line|line.strip_prefix("populated ")).collect();
    match values.as_slice() { ["0"]=>Some(false),["1"]=>Some(true),_=>None }
}
#[cfg(test)] mod tests {
    use super::*;
    #[test] fn exact_scope_and_nonce_reject_foreign_and_traversal() {
        let n="a".repeat(32);let id="b".repeat(64); let s=format!("0::/system.slice/system-ipsequal{n}.slice/docker-{id}.scope\n");
        assert!(group_path(&s,&n,&id).is_some());
        assert!(group_path(&(s.clone()+"0::/other\n"),&n,&id).is_none());
        assert!(group_path(&s.replace("/system.slice/","/other/../"),&n,&id).is_none());
    }
    #[test] fn unprivileged_all_ids_no_caps_and_no_new_privs_required() {
        let good="Uid:\t1000 1000 1000 1000\nCapEff:\t0000000000000000\nNoNewPrivs:\t1\nSeccomp:\t2\n";
        assert!(status_ok(good,1000));
        assert!(!status_ok(&good.replace("1000 1000 1000 1000","1000 0 1000 1000"),1000));
        assert!(!status_ok(&good.replace("0000000000000000","0000000000200000"),1000));
        assert!(!status_ok(&good.replace("NoNewPrivs:\t1","NoNewPrivs:\t0"),1000));
        assert!(!status_ok(&good.replace("Seccomp:\t2","Seccomp:\t0"),1000));
        assert!(!status_ok(&(good.to_owned()+"CapEff:\t0\n"),1000));
    }
    #[test] fn namespace_and_descriptor_unknowns_refuse() {
        assert!(host_user_namespace("0 0 4294967295\n",100,100));
        assert!(!host_user_namespace("0 1000 1000\n",100,100));
        assert!(!host_user_namespace("0 0 4294967295\n",100,101));
        assert!(no_cgroup_descriptors(&[Some(0x01021994),Some(0x9fa0)]));
        assert!(!no_cgroup_descriptors(&[Some(0x63677270)]));
        assert!(!no_cgroup_descriptors(&[None]));
    }
    #[test] fn all_visible_cgroup_mounts_must_be_read_only() {
        let ro="41 22 0:30 / /sys/fs/cgroup ro,nosuid - cgroup2 cgroup ro\n";
        let rw="42 22 0:30 / /else rw - cgroup2 cgroup rw\n";
        assert!(only_readonly_cgroup2(ro));assert!(!only_readonly_cgroup2(&(ro.to_owned()+rw)));
        assert!(!only_readonly_cgroup2("broken\n"));assert!(!only_readonly_cgroup2("1 1 0:1 / / rw - tmpfs tmpfs rw\n"));
    }
    #[test] fn pid_identity_handles_parentheses_and_rejects_truncation() {
        let mut fields=vec!["S".to_string()];fields.extend((4..=21).map(|x|x.to_string()));fields.push("998877".into());
        let stat=format!("123 (name with ) parentheses) {}",fields.join(" "));
        assert_eq!(proc_identity(&stat,123),Some(998877));assert_eq!(proc_identity(&stat,124),None);
        assert_eq!(proc_identity("123 (x) S 1",123),None);
    }
    #[test] fn children_and_population_require_unique_exact_rows() {
        let a="a".repeat(64);let b="b".repeat(64);
        let rows=vec![format!("docker-{a}.scope"),format!("docker-{b}.scope")];
        assert!(exact_children(&rows,&[a.clone(),b]));
        assert!(!exact_children(&[rows[0].clone(),rows[0].clone()],&[a.clone(),a]));
        assert_eq!(populated("populated 0\nfrozen 0\n"),Some(false));
        assert_eq!(populated("populated 0\npopulated 1\n"),None);
    }
}
