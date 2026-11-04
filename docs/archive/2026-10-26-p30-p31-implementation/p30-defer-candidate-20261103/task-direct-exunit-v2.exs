expected = Path.expand("_build/test/lib/ipse/ebin")
for module <- [Ipse.Session, Ipse.Session.ManagedReads, Ipse.Extension.DecisionExperiment] do
  {:module, ^module} = Code.ensure_loaded(module)
  true = Path.dirname(module |> :code.which() |> List.to_string() |> Path.expand()) == expected
end
{:ok, _} = Application.ensure_all_started(:ipse)
ExUnit.start(
  autorun: false,
  seed: 0,
  exclude: [:test],
  include: [test: :"test actual bundled shadow Session is deferred candidate"]
)
Code.require_file("test/extensions/knowledge/shadow_pending_candidate_session_test.exs")
%{total: 11, excluded: 10, skipped: 0, failures: 0} = ExUnit.run()
