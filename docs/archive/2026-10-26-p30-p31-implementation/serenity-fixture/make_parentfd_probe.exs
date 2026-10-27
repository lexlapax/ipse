# Source-only transformation; does not execute a mount or unmount.
source = File.read!("/tmp/ipse-serenity-qualification-plan/fixture/tmpfs_umount_probe.rs")
old = ~S"""
  if unsafe{umount2(target.as_ptr(),0)}!=0{return Err(io::Error::last_os_error())}println!("exact private path nonlazy cleanup: success");
""" |> String.trim()
new = ~S"""
  let parent=OpenOptions::new().read(true).custom_flags(0x200000|0x10000|0x20000).open("/tmp")?;
  let parent_held=parent.metadata()?;let parent_named=fs::symlink_metadata("/tmp")?;
  if (parent_held.dev(),parent_held.ino())!=(parent_named.dev(),parent_named.ino()){return Err(io::ErrorKind::PermissionDenied.into())}
  let leaf=root.strip_prefix("/tmp/").ok_or(io::ErrorKind::InvalidInput)?;
  if leaf.contains('/')||leaf.is_empty(){return Err(io::ErrorKind::InvalidInput.into())}
  let via_parent=c(&format!("/proc/self/fd/{}/{leaf}",parent.as_raw_fd()))?;
  if unsafe{umount2(via_parent.as_ptr(),0)}!=0{return Err(io::Error::last_os_error())}println!("retained-parent-fd nonlazy cleanup: success");
""" |> String.trim()
if not String.contains?(source,old), do: raise("expected exactly named fallback")
[source_before,source_after] = String.split(source,old)
:ok = File.write("/tmp/ipse-serenity-qualification-plan/fixture/tmpfs_umount_parentfd_probe.rs",source_before<>new<>source_after,[:exclusive])
supervisor=File.read!("/tmp/ipse-serenity-qualification-plan/fixture/tmpfs_umount_supervisor.exs")
:ok=File.write("/tmp/ipse-serenity-qualification-plan/fixture/tmpfs_umount_parentfd_supervisor.exs",String.replace(supervisor,"tmpfs_umount_probe","tmpfs_umount_parentfd_probe"),[:exclusive])
IO.puts("Generated private parent-FD source; no mount performed.")
