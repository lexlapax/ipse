root = "/dev/shm/ipse-p30-concurrent-dcbb-20261103-01"
app = Path.join(root, "_build/test/lib/ipse")
true = Path.expand(Application.app_dir(:ipse)) == app
for module <- [Ipse.Extension.Consent, Ipse.Extension.DecisionExperiment] do
  expected = Path.join([app, "ebin", Atom.to_string(module) <> ".beam"])
  ^expected = module |> :code.which() |> List.to_string() |> Path.expand()
end
for {relative, expected} <- [
  {"priv/ipse-runner", "ac424d10e2ce6809cedcb157acd70092b00ca68aa7a48201a6007ac5dccbf33b"},
  {"priv/extension-bundles/knowledge-decision-shadow/extension.json", "f57dfefc70850f1ff83d736fc39fb4437f50a26589785d30092d2a69750a7606"}
] do
  actual = :sha256 |> :crypto.hash(File.read!(Path.join(app, relative))) |> Base.encode16(case: :lower)
  ^expected = actual
end
{:ok, _} = Application.ensure_all_started(:ipse)
ExUnit.start(autorun: false, seed: 0)
Code.require_file("test/extensions/knowledge/shadow_concurrent_session_test.exs")
result = ExUnit.run()
if result.total != 1 or result.excluded != 0 or result.skipped != 0 or result.failures != 0,
  do: System.halt(1)
