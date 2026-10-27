# Create a private container-path source variant; perform no device operation.
source = File.read!("/tmp/ipse-serenity-qualification-plan/fixture/peer_channel.rs")
replacements = [
  {"/tmp/ipse-serenity-qualification-plan/fixture/peer_listener", "/work/tools/bin/peer_listener"},
  {"/tmp/ipse-serenity-barrier-benign/control.sock", "/work/control/native-stage.sock"},
  {"/tmp/ipse-serenity-barrier-graph/project/priv/ipse-runner", "/work/runtime/priv/ipse-runner"}
]
result = Enum.reduce(replacements, source, fn {old,new}, text ->
  if not String.contains?(text, old), do: raise("missing source token #{old}")
  String.replace(text, old, new)
end)
old = ~S"""
!root.strip_prefix("/tmp/ipse-serenity-barrier-benign/").is_some_and(|s|!s.is_empty()&&s.len()<=64&&s.bytes().all(|b|b.is_ascii_lowercase()||b.is_ascii_digit()||b==b'-'))
""" |> String.trim()
if not String.contains?(result, old), do: raise("root guard mismatch")
result = String.replace(result, old, ~S(root!="/work/mount/transaction"))
:ok = File.write("/tmp/ipse-serenity-qualification-plan/fixture/peer_channel_container.rs", result, [:exclusive])
driver = File.read!("/tmp/ipse-serenity-qualification-plan/fixture/peer_channel_driver.rs")
:ok = File.write("/tmp/ipse-serenity-qualification-plan/fixture/peer_channel_container_driver.rs", String.replace(driver,"peer_channel.rs","peer_channel_container.rs"), [:exclusive])
IO.puts("Created private container channel sources; no device effects.")
