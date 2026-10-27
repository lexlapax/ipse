path = "/tmp/ipse-serenity-qualification-plan/fixture/private_unmount.rs"
s = File.read!(path)
[first, rest] = String.split(s, "fn parse_mounts(text:&str)->io::Result<Option<Mount>> {", parts: 2)
[_old, last] = String.split(rest, "fn mountinfo()->io::Result<String>", parts: 2)
replacement = ~S"""
// `boundary` must come from independently attested namespace-root topology;
// an absent parent from a chroot-truncated view is not itself evidence.
fn parse_mounts(text:&str,boundary:u64)->io::Result<Option<Mount>> {
 if boundary==0{return Err(io::ErrorKind::InvalidInput.into())}
 let mut rows=std::collections::HashMap::new();
 for line in text.lines(){
  let (l,r)=line.split_once(" - ").ok_or(io::ErrorKind::InvalidData)?;
  let a:Vec<_>=l.split_whitespace().collect();let b:Vec<_>=r.split_whitespace().collect();
  if a.len()<6||b.len()<3{return Err(io::ErrorKind::InvalidData.into())}
  let id=a[0].parse::<u64>().map_err(|_|io::ErrorKind::InvalidData)?;
  if id==0||rows.insert(id,(a,b)).is_some(){return Err(io::ErrorKind::InvalidData.into())}
 }
 let mut selected=None;
 for (id,(a,b)) in &rows {if a[4]=="/work/mount" {
  if selected.is_some()||b[0]!="btrfs"||a[6..].iter().any(|s|s.starts_with("shared:")||s.starts_with("master:")||s.starts_with("propagate_from:")){return Err(io::ErrorKind::PermissionDenied.into())}
  selected=Some(Mount{id:*id,dev:a[2].into()});
 }}
 let Some(ref m)=selected else{return Ok(None)};
 let selected_row=rows.get(&m.id).ok_or(io::ErrorKind::InvalidData)?;
 let mut ancestor=selected_row.0[1].parse::<u64>().map_err(|_|io::ErrorKind::InvalidData)?;
 let mut visited=std::collections::HashSet::new();let mut boundary_attested=false;
 for _ in 0..rows.len(){
  if !visited.insert(ancestor){return Err(io::ErrorKind::PermissionDenied.into())}
  let (a,_)=rows.get(&ancestor).ok_or(io::ErrorKind::PermissionDenied)?;
  if a[6..].iter().any(|s|s.starts_with("shared:")||s.starts_with("master:")||s.starts_with("propagate_from:")){return Err(io::ErrorKind::PermissionDenied.into())}
  let next=a[1].parse::<u64>().map_err(|_|io::ErrorKind::InvalidData)?;
  if next==boundary && !rows.contains_key(&next) && a[4]=="/" {boundary_attested=true;break}
  ancestor=next;
 }
 if !boundary_attested{return Err(io::ErrorKind::PermissionDenied.into())}
 if rows.values().any(|(a,_)|a[4].starts_with("/work/mount/")||(a[2]==m.dev&&a[4]!="/work/mount")){return Err(io::ErrorKind::PermissionDenied.into())}
 Ok(selected)
}
"""
File.write!(path, first <> replacement <> "fn mountinfo()->io::Result<String>" <> last)
