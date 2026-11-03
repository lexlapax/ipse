# Focused replay tests without test_helper's HOME assignment.
root = Path.expand(".")
app = Path.join(root, "_build/test/lib/ipse")
^app = Application.app_dir(:ipse) |> Path.expand()
for module <- [Ipse.Session, Ipse.Session.Saved, Ipse.Session.SourceWindow,
               Ipse.Session.SourceIndex, Ipse.Session.SourceReplayCache,
               Ipse.Session.ManagedUse] do
  expected = Path.join([app, "ebin", Atom.to_string(module) <> ".beam"])
  ^expected = module |> :code.which() |> List.to_string() |> Path.expand()
end
{:ok, _} = Application.ensure_all_started(:ipse)
{path, selection, total} =
  case System.argv() do
    ["window"] -> {"test/ipse/session/source_window_test.exs", nil, 8}
    ["cache"] -> {"test/ipse/session/source_replay_cache_test.exs", nil, 6}
    ["draft-cancel"] ->
      {"test/ipse/session/draft_vertical_test.exs", :"test cancelling in-flight work fences its task and remains inert on resume", 20}
    ["draft-accept"] ->
      {"test/ipse/session/draft_vertical_test.exs", :"test replacement acceptance sends only the accepted intent and survives replay", 20}
    ["source-loss"] ->
      {"test/extensions/knowledge/shadow_pending_candidate_session_test.exs", :"test actual bundled shadow Session is source withdrawn before decision", 10}
    ["output-loss"] ->
      {"test/extensions/knowledge/shadow_pending_candidate_session_test.exs", :"test actual bundled shadow Session is source withdrawn before output release", 10}
    ["revocation"] ->
      {"test/extensions/knowledge/shadow_pending_candidate_session_test.exs", :"test actual bundled shadow Session is revoked grant", 10}
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
