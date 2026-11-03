# Focused synthetic tests without test_helper's HOME override.
root = Path.expand(".")
app = Path.join(root, "_build/test/lib/ipse")
^app = Application.app_dir(:ipse) |> Path.expand()
for module <- [Ipse.Session, Ipse.Session.Draft, Ipse.Session.DraftNative, Ipse.Provider.Ollama, Ipse.Session.Saved] do
  expected = Path.join([app, "ebin", Atom.to_string(module) <> ".beam"])
  ^expected = module |> :code.which() |> List.to_string() |> Path.expand()
end
{:ok, _} = Application.ensure_all_started(:ipse)
{path, selection, total} =
  case System.argv() do
    ["projection"] ->
      {"test/ipse/session/draft_projection_test.exs", nil, 7}
    ["vertical"] ->
      {"test/ipse/session/draft_vertical_test.exs", :"test Ollama transport withdraws no-tool drafts with thinking on cancellation and acceptance across resume", 20}
    ["accept"] ->
      {"test/ipse/session/draft_acceptance_test.exs", :"test native enhance command retains exact input and rejects a stale ID before acceptance", 9}
    ["cancel"] ->
      {"test/ipse/session/draft_acceptance_test.exs", :"test cancel clears draft entry and replacement, and abandons a rendered acceptance", 9}
  end
options = [autorun: false, seed: 0]
options = if selection, do: options ++ [exclude: [:test], include: [test: selection]], else: options
ExUnit.start(options)
Code.require_file("test/support/resume_assertions.exs")
Code.require_file("test/support/witnessed_draft.exs")
Code.require_file(path)
result = ExUnit.run()
expected_excluded = if selection, do: total - 1, else: 0
if result.total != total or result.excluded != expected_excluded or result.skipped != 0 or result.failures != 0 do
  IO.inspect(Map.take(result, [:total, :excluded, :skipped, :failures]), label: "unexpected test result")
  System.halt(1)
end
