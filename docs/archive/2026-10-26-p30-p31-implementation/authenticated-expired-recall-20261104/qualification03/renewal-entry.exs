ExUnit.start(
  autorun: false,
  max_cases: 1,
  seed: 0,
  exclude: [:test],
  include: [clock_consent_recall: true]
)

import ExUnit.Assertions
root = Path.expand("../..", __DIR__)

claim = %{
  "kind" => "fresh_current_typed_expiry_renewal_control",
  "runtime_manifest_sha256" =>
    Ipse.JSON.sha256(File.read!(Path.expand("../runtime-final.sha256", __DIR__))),
  "fixture_manifest_sha256" =>
    Ipse.JSON.sha256(File.read!(Path.join(__DIR__, "renewal-fixtures.sha256"))),
  "knowledge_artifact_sha256" =>
    "7858680228caf268ae8b9aaf7f6e4bef360d76de7a2724d51ab65d084a003a5a",
  "retained_2000_cohort_access" => false
}

{:ok, file} =
  :file.open(String.to_charlist(Path.join(__DIR__, "renewal-launch.claim")), [
    :write,
    :binary,
    :exclusive
  ])

:ok = :file.write(file, Jason.encode!(claim) <> "\n")
:ok = :file.sync(file)
:ok = :file.close(file)
:ok = Ipse.Runner.protected_sync_directory(__DIR__)

assert {:ok, "ac424d10e2ce6809cedcb157acd70092b00ca68aa7a48201a6007ac5dccbf33b"} =
         Ipse.Runner.protected_helper_digest()

assert Ipse.JSON.sha256(
         File.read!(
           Path.join(
             root,
             "clock-runtime/stdio-runtime/ipse/priv/extension-bundles/knowledge/extension.json"
           )
         )
       ) ==
         "7858680228caf268ae8b9aaf7f6e4bef360d76de7a2724d51ab65d084a003a5a"

refute :code.is_loaded(IpseKnowledge.Knowledge)
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file(Path.join(__DIR__, "focused-clock-test.exs"))
tests = Ipse.Development.ManagedClockLifecycleTest.__ex_unit__().tests
selected = Enum.filter(tests, &(&1.tags[:clock_consent_recall] == true))
assert length(selected) == 1

File.write!(
  Path.join(__DIR__, "renewal-selection.json"),
  Jason.encode!(%{
    "defined" => length(tests),
    "selected" => Enum.map(selected, &Atom.to_string(&1.name))
  }),
  [:exclusive]
)

result = ExUnit.run()
File.write!(Path.join(__DIR__, "renewal-result.json"), Jason.encode!(result), [:exclusive])

System.halt(
  if(result.failures == 0 and result.total - result.excluded - result.skipped == 1,
    do: 0,
    else: 1
  )
)
