# Direct, single synthetic test; test_helper would override HOME.
root = Path.expand(".")
app = Path.join(root, "_build/test/lib/ipse")
^app = Application.app_dir(:ipse) |> Path.expand()
for module <- [Ipse.Session, Ipse.Session.InferenceDispatch, Ipse.Session.ManagedUse,
               Ipse.Session.StoredSources, Ipse.Session.Resources, Ipse.Test.SourceTiming,
               Ipse.Provider.Ollama] do
  expected = Path.join([app, "ebin", Atom.to_string(module) <> ".beam"])
  ^expected = module |> :code.which() |> List.to_string() |> Path.expand()
end
"1" = System.fetch_env!("IPSE_TEST_SOURCE_PHASE_PROBE")
true = System.fetch_env!("IPSE_TEST_SOURCE_PHASE_MODE") in ["single", "split8"]
"5000" = System.fetch_env!("IPSE_TEST_RECALL_PROVIDER_TIMEOUT_MS")
{:ok, _} = Application.ensure_all_started(:ipse)
ExUnit.start(autorun: false, seed: 0, exclude: [:test],
             include: [test: :"test fresh native source ownership phase comparison"])
Code.require_file("test/ipse/session/native_note_recall_test.exs")
result = ExUnit.run()
if result.total != 6 or result.excluded != 5 or result.skipped != 0 or result.failures != 0 do
  IO.inspect(Map.take(result, [:total, :excluded, :skipped, :failures]), label: "inconclusive test result")
  System.halt(1)
end
