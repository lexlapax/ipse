# Source generation only. No listener execution or device access.
source = File.read!("/tmp/ipse-serenity-qualification-plan/fixture/peer_listener.rs")
replacements = [
  {"/tmp/ipse-serenity-barrier-benign/control.sock", "/work/control/native-stage.sock"},
  {"/tmp/ipse-serenity-barrier-graph/project/priv/ipse-runner", "/work/runtime/priv/ipse-runner"},
  {"/tmp/ipse-serenity-barrier-benign/", "/work/mount/"},
  {"/tmp/ipse-serenity-barrier-benign", "/work/mount"},
  {"before.len()>=65536", "before.len()>=8388608"}
]
result = Enum.reduce(replacements, source, fn {old,new}, text ->
  if not String.contains?(text, old), do: raise("missing source token #{old}")
  String.replace(text, old, new)
end)
old = ~S"""
!root.strip_prefix("/work/mount/").is_some_and(|s| !s.is_empty() && s.len()<=64 && s.bytes().all(|b|b.is_ascii_lowercase()||b.is_ascii_digit()||b==b'-'))
""" |> String.trim()
new = ~S(root!="/work/mount/transaction")
if not String.contains?(result, old), do: raise("root guard mismatch")
result = String.replace(result, old, new)
marker = " let root_m=fs::symlink_metadata(root)?;"
control = ~S"""
 let control=fs::symlink_metadata("/work/control")?;if !control.is_dir() || control.uid()!=unsafe{geteuid()} || control.mode()&0o777!=0o700{return Err(io::ErrorKind::PermissionDenied.into())}
"""
if not String.contains?(result, marker), do: raise("control guard mismatch")
result = String.replace(result, marker, control <> marker)
output = "/tmp/ipse-serenity-qualification-plan/fixture/peer_listener_container.rs"
:ok = File.write(output, result, [:exclusive])
IO.puts("Created private container listener source; no device effects.")
