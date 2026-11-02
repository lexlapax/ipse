alias Ipse.JSON

fp = fn path ->
  bytes = File.read!(path)
  %{"path" => path, "bytes" => byte_size(bytes), "sha256" => JSON.sha256(bytes)}
end

roots =
  ~w(/tmp/ipse-p30-current-split-20261102-post-population /tmp/ipse-p30-current-stale-20261102-fresh /tmp/ipse-p30-current-stale-20261102-final)

fixtures =
  Enum.map(roots, fn root ->
    path = Path.join(root, "literal-ab-seed.json")
    seed = path |> File.read!() |> Jason.decode!()
    true = length(seed["keys"]) == 8 and length(seed["source_journals"]) == 2

    sources =
      Enum.map(seed["source_journals"], fn source ->
        actual = fp.(source["path"])
        true = actual["sha256"] == source["sha256"]
        false = File.exists?(source["path"] <> ".wide-pack-fixture-held")
        actual
      end)

    %{"seed" => fp.(path), "sources" => sources}
  end)

logs = ~w(
  /tmp/ipse-p30-current-compile-20261102.log
  /tmp/ipse-p30-current-split-seed-20261102-post-population.log
  /tmp/ipse-p30-current-overflow-20261102-post-population.log
  /tmp/ipse-p30-current-overflow-stale-20261102-post-population.log
  /tmp/ipse-p30-current-stale-seed-20261102-fresh.log
  /tmp/ipse-p30-current-overflow-stale-20261102-fresh.log
  /tmp/ipse-p30-stale-source-restore-20261102.log
  /tmp/ipse-p30-current-stale-seed-20261102-repaired.log
  /tmp/ipse-p30-current-overflow-stale-20261102-repaired.log
  /tmp/ipse-p30-current-decision-regression-20261102.log
  /tmp/ipse-p30-current-stale-seed-20261102-final.log
  /tmp/ipse-p30-current-overflow-stale-20261102-final.log
  /tmp/ipse-p30-stale-control-format-final-20261102.log
)

report = %{
  "version" => 1,
  "date" => "2026-11-02",
  "kind" => "signed_note_decision_withdrawal_control",
  "runtime_base_commit" => "e68566d",
  "scope" =>
    "Synthetic local decision service and native fixture; no live engine or human quality claim",
  "paid_model_calls" => 0,
  "qualification_passed" => false,
  "inventory_scope" =>
    "Selected source, helper, synthetic seed and log hashes; not a complete pre/post build-graph inventory",
  "positive" => %{"passed" => 1, "excluded" => 191, "seed" => 791_839},
  "initial_withdrawal_failures" => 2,
  "preliminary_repair" => %{
    "passed" => 1,
    "excluded" => 191,
    "seed" => 791_842,
    "source_snapshot" => "not separately retained"
  },
  "current_stale_decision_regression" => %{"passed" => 2, "excluded" => 190, "seed" => 791_843},
  "final_withdrawal" => %{"passed" => 1, "excluded" => 191, "seed" => 791_844},
  "fixtures" => fixtures,
  "sources" =>
    Enum.map(
      ~w(test/ipse/extension/managed_collection_call_session_test.exs test/support/managed_literal_pair_runner.exs test/support/managed_literal_ab_seed.exs test/support/provider_fixture.ex test/support/operator_pty.rs lib/ipse/extension/decision_call.ex lib/ipse/extension/collection/observed_read.ex),
      fp
    ),
  "helper" => fp.("_build/test/lib/ipse/priv/ipse-runner"),
  "logs" => Enum.map(logs, fp),
  "documentation_log" => fp.("/tmp/ipse-p30-signed-withdrawal-docs-20261102.log"),
  "receipt_generator" =>
    fp.("docs/archive/2026-10-26-p30-p31-implementation/p30-signed-withdrawal-20261102.exs")
}

File.write!(
  "docs/archive/2026-10-26-p30-p31-implementation/p30-signed-withdrawal-20261102.json",
  Jason.encode!(report, pretty: true) <> "\n"
)
