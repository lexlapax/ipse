# Private source-only diagnostic variant; performs no mount.
source=File.read!("/tmp/ipse-serenity-qualification-plan/fixture/tmpfs_umount_parentfd_probe.rs")
marker = ~S"""
  let id=mount_entry(&read_info()?,root)?.ok_or(io::ErrorKind::NotFound)?;
""" |> String.trim()
extra = ~S"""
  let root_fd=OpenOptions::new().read(true).custom_flags(0x200000|0x10000|0x20000).open("/")?;
  let root_info=fs::read_to_string(format!("/proc/self/fdinfo/{}",root_fd.as_raw_fd()))?;
  let ids:Vec<_>=root_info.lines().filter_map(|l|l.strip_prefix("mnt_id:\t")).collect();
  if ids.len()!=1{return Err(io::ErrorKind::InvalidData.into())}
  let root_id:u64=ids[0].parse().map_err(|_|io::ErrorKind::InvalidData)?;
  let info=read_info()?;let mut edges=std::collections::HashMap::new();
  for line in info.lines(){let (left,_)=line.split_once(" - ").ok_or(io::ErrorKind::InvalidData)?;let fields:Vec<_>=left.split_whitespace().collect();if fields.len()<6{return Err(io::ErrorKind::InvalidData.into())}let child:u64=fields[0].parse().map_err(|_|io::ErrorKind::InvalidData)?;let parent:u64=fields[1].parse().map_err(|_|io::ErrorKind::InvalidData)?;if edges.insert(child,parent).is_some(){return Err(io::ErrorKind::InvalidData.into())}}
  let mut current=id;let mut reached=false;for _ in 0..edges.len(){if current==root_id{reached=true;break}current=*edges.get(&current).ok_or(io::ErrorKind::NotFound)?;}if !reached{return Err(io::ErrorKind::PermissionDenied.into())}
  println!("ROOT_FD_MOUNT_ID {root_id} target_ancestry_contains_root=true");
"""
if not String.contains?(source,marker),do: raise("missing insertion site")
[source_before,source_after]=String.split(source,marker)
:ok=File.write("/tmp/ipse-serenity-qualification-plan/fixture/tmpfs_umount_rootfd_probe.rs",source_before<>marker<>"\n"<>extra<>source_after,[:exclusive])
supervisor=File.read!("/tmp/ipse-serenity-qualification-plan/fixture/tmpfs_umount_parentfd_supervisor.exs")
:ok=File.write("/tmp/ipse-serenity-qualification-plan/fixture/tmpfs_umount_rootfd_supervisor.exs",String.replace(supervisor,"tmpfs_umount_parentfd_probe","tmpfs_umount_rootfd_probe"),[:exclusive])
IO.puts("Generated root-FD diagnostic source; no mount performed.")
