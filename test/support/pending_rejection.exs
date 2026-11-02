# Trusted synthetic source members; actual signed Collection, management policy,
# public CLI and native terminal input. No original Session/source or inference qualification.
ExUnit.start(autorun: false)
Code.require_file("../ipse/extension/collection_normalizer_v3_integration_test.exs", __DIR__)
import ExUnit.Assertions
alias Ipse.{JSON, Usage}

alias Ipse.Extension.{
  Artifact,
  Bundles,
  Collection,
  Consent,
  ProjectIdentity,
  SemanticAdmission,
  SemanticConsent
}

alias Ipse.Extension.Collection.{ManagedPages, NormalizerV3, ObservedRead}
alias Ipse.Extension.CollectionNormalizerV3IntegrationTest, as: Fixture
alias Ipse.Session.PendingRejection

[root, mode] = System.argv()
{:ok, _} = Application.ensure_all_started(:ipse)
home = Path.join(root, "home")
cwd = Path.join(root, "work")

for path <- [home, cwd] do
  File.mkdir!(path)
  File.chmod!(path, 0o700)
end

{:ok, binding} = ProjectIdentity.admit(home, cwd, :folder)
{:ok, namespace} = SemanticConsent.namespace(binding["project_id"], "knowledge")
assert {:ok, _} = Bundles.install("knowledge", home)
{:ok, entries} = Bundles.inventory()
%{digest: digest} = Enum.find(entries, &(&1.id == "knowledge"))

{:ok, bytes} =
  Artifact.read_declared(Path.join(home, "extensions/artifacts"), digest, "operator.json", 65_536)

{:ok, sidecar} = JSON.decode_unique(bytes)

c = %{
  home: home,
  cwd: cwd,
  binding: binding,
  root: SemanticAdmission.collection_root(home),
  namespace: namespace
}

scope = fn first ->
  %{
    namespace: namespace,
    format: "managed-metadata-v3",
    operation_id: Usage.id(),
    initialize: first
  }
end

now = if(mode == "expired", do: 0, else: System.system_time(:millisecond))

note = %{
  Fixture.options(1, 0)
  | recipe: sidecar["recipes"]["note"],
    constraints: sidecar["publication"]["note"],
    now_ms: now
}

pending = %{
  Fixture.options(1, 1, "proposal")
  | recipe: sidecar["recipes"]["pending"],
    constraints: sidecar["publication"]["pending"],
    now_ms: now
}

assert {:ok, _} = Fixture.publish(c, note, scope.(true), first: true)
assert {:ok, _} = Fixture.publish(c, pending, scope.(false))
[source] = pending.verified_sources
[target] = pending.request["changes"]

{:ok, other_key, other_value} =
  IpseKnowledge.Knowledge.Records.capture(
    %{
      "text" => "Acme may appoint Bea",
      "category" => "ordinary",
      "reason" => "another synthetic candidate",
      "event_at_ms" => nil
    },
    source,
    10 * 86_400_000
  )

other = %{
  pending
  | request: %{
      pending.request
      | "expected_generation" => 2,
        "changes" => [%{"key" => other_key, "expected_revision" => 0, "value" => other_value}]
    }
}

assert {:ok, _} = Fixture.publish(c, other, scope.(false))
"pending." <> id = target["key"]
rejection_key = "reject." <> id

keys = [
  target["key"],
  other_key,
  hd(note.request["changes"])["key"],
  rejection_key,
  ManagedPages.prefix(:anchor) <> ManagedPages.zero(:anchor),
  ManagedPages.format_key()
]

snapshot = fn ->
  {:ok, view} = Collection.open_view(c.root, namespace)

  try do
    {:ok, result} = Collection.view_read(view, %{"op" => "get_many", "keys" => keys})
    result
  after
    assert :ok = Collection.close_view(view)
  end
end

control = SemanticAdmission.control_root(home)
assert {:ok, %{"epoch" => 1}} = Consent.revoke(control, binding["project_id"], 0)

if mode in ~w(retained-peer forgotten-peer) do
  config = %{home: home, headless: false, approval: :ask, approval_origin: :interactive}
  note_key = hd(note.request["changes"])["key"]

  assert {:ok, _} =
           if(mode == "retained-peer",
             do: Ipse.CLI.Knowledge.Management.retain(config, cwd, note_key, %{"kind" => "pin"}),
             else: Ipse.CLI.Knowledge.Management.forget(config, cwd, note_key)
           )
end

before = snapshot.()
assert {:ok, before_control} = Consent.existing_snapshot(control, binding["project_id"])
assert before_control["policy"] === nil

assert {:ok, managed} =
         ProjectIdentity.with_existing_domain_auth(
           home,
           cwd,
           binding,
           %{namespace: namespace, format: "managed-metadata-v3"},
           fn cap, catalog ->
             if mode in ~w(retained-peer forgotten-peer) do
               assert {:error, :collection_observation_refused} =
                        ObservedRead.managed_proposal(
                          c.root,
                          namespace,
                          %{"op" => "get_record", "key" => target["key"]},
                          cap,
                          catalog,
                          pending.recipe
                        )
             end

             ObservedRead.with_managed_proposal_removal(
               c.root,
               namespace,
               %{"op" => "get_record", "key" => target["key"]},
               cap,
               catalog,
               pending.recipe,
               &{:ok, &1}
             )
           end
         )

context = %{
  "session_id" => Usage.id(),
  "job_id" => Usage.id(),
  "client_id" => Usage.id(),
  "project_id" => binding["project_id"],
  "namespace" => namespace,
  "binding_sha256" => binding["binding_sha256"],
  "management_epoch" => 1,
  "management_sha256" => Consent.management_sha256(binding["project_id"], 1, nil),
  "original_pin" => nil,
  "recipe" => pending.recipe
}

assert {:ok, prepared} = PendingRejection.prepare(context, managed, "synthetic exact rejection")
assert PendingRejection.valid_facts?(prepared["facts"])
assert prepared["facts"]["request"] === prepared["request"]

refute PendingRejection.valid_facts?(
         put_in(prepared["facts"], ["target", "value", "text"], "forged")
       )

refute PendingRejection.valid_facts?(
         Map.put(prepared["facts"], "request_sha256", JSON.sha256("forged request"))
       )

assert {:error, :managed_lifecycle_refused} =
         Ipse.Session.ManagedLifecycle.prepare(context, managed, "wrong target kind")

for forged <- [nil, %{"kind" => "native_review", "command" => "reject"}] do
  assert {:error, :managed_normalization_refused} =
           ProjectIdentity.with_domain_publication(
             home,
             cwd,
             binding,
             scope.(false) |> Map.put(:operation_id, prepared["facts"]["operation_id"]),
             fn _ -> :ok end,
             fn cap, catalog ->
               Collection.execute_managed_v3(
                 c.root,
                 namespace,
                 prepared["request"],
                 prepared["facts"]["operation_id"],
                 JSON.digest([pending.recipe]),
                 fn witness, read ->
                   NormalizerV3.reject(witness, read, %{
                     request: prepared["request"],
                     facts: prepared["facts"],
                     permit: forged,
                     now_ms: System.system_time(:millisecond),
                     domain_cap: cap,
                     catalog: catalog
                   })
                 end
               )
             end
           )

  assert snapshot.() === before
end

System.put_env("IPSE_HOME", home)

for env <-
      ~w(IPSE_PROVIDER IPSE_MODEL IPSE_SANDBOX IPSE_MAX_STEPS IPSE_CONTEXT_BYTES IPSE_COMPACT IPSE_SUBAGENTS IPSE_SUBAGENT_CONCURRENCY IPSE_TIMEOUT_MS IPSE_MAX_OUTPUT_TOKENS IPSE_PROFILE IPSE_CONFIG),
    do: System.delete_env(env)

config_path = Path.join(home, "config.json")

File.write!(
  config_path,
  Jason.encode!(%{"version" => 1, "settings" => %{"provider" => "demo", "model" => "synthetic"}}),
  [:exclusive]
)

File.chmod!(config_path, 0o600)

args = [
  "knowledge",
  "reject",
  target["key"],
  "--cwd",
  cwd,
  "--config",
  config_path,
  "--no-project-config"
]

assert 1 == Ipse.CLI.run(args ++ ["--yes"])
before_journals = Path.wildcard(Path.join(home, "knowledge-management/*.jsonl"))

race =
  if mode in ~w(epoch-race root-race) do
    Task.async(fn ->
      deadline = System.monotonic_time(:millisecond) + 15_000

      wait = fn wait ->
        cond do
          File.exists?(Path.join(root, "management-review-input-ready")) ->
            :ok

          System.monotonic_time(:millisecond) >= deadline ->
            :timeout

          true ->
            Process.sleep(10)
            wait.(wait)
        end
      end

      assert :ok = wait.(wait)

      if mode == "epoch-race" do
        assert {:ok, %{"epoch" => 2}} = Consent.revoke(control, binding["project_id"], 1)
      else
        assert {:ok, _} =
                 Collection.execute(
                   c.root,
                   namespace,
                   %{
                     "op" => "commit",
                     "advance_floor" => true,
                     "expected_generation" => 3,
                     "changes" => [
                       %{
                         "key" => "synthetic.race",
                         "expected_revision" => 0,
                         "value" => %{"version" => 1, "kind" => "trusted_root_race_fixture"}
                       }
                     ]
                   },
                   Usage.id()
                 )
      end

      competing = snapshot.()
      File.write!(Path.join(root, "management-review-race-complete"), "done", [:exclusive])
      competing
    end)
  end

code = Ipse.CLI.run(args)
competing = if race, do: Task.await(race, 20_000), else: before
after_review = snapshot.()
assert {:ok, after_control} = Consent.existing_snapshot(control, binding["project_id"])
[journal] = Path.wildcard(Path.join(home, "knowledge-management/*.jsonl")) -- before_journals
assert {:ok, %{events: events, tail: :none}} = Ipse.Journal.read_path(journal)

if mode in ~w(cancel stale epoch-race root-race) do
  assert code == 1
  assert after_review === competing
  assert after_review["records"] === before["records"]
  assert after_control["epoch"] == if(mode == "epoch-race", do: 2, else: 1)

  if mode in ~w(cancel stale) do
    assert after_control === before_control
    refute Enum.any?(events, &(&1["type"] == "managed_lifecycle_intent"))
  end
else
  assert code == 0

  [nil, other_after, note_after, suppression, anchor_after, format_after] =
    after_review["records"]

  [_, ^other_after, ^note_after, nil, ^anchor_after, ^format_after] = before["records"]
  assert suppression["value"]["candidate_id"] === id
  assert suppression["value"]["record_sha256"] === hd(before["records"])["sha256"]
  [intent] = Enum.filter(events, &(&1["type"] == "managed_lifecycle_intent"))
  [result] = Enum.filter(events, &(&1["type"] == "managed_lifecycle_result"))
  assert result["status"] === "settled"
  operation = after_control["operations"][intent["operation_id"]]
  assert operation["status"] === "settled" and operation["operation"] === "collection.forget"
  assert operation["actual"]["operations"] === 1 and operation["actual"]["model_calls"] === 0
  assert operation["receipt"]["publication"]["normalization"]["kind"] === "native_proposal_reject"

  assert {:ok,
          %{"control_status" => "settled", "journal_status" => "settled", "replayed" => false}} =
           Ipse.CLI.Knowledge.Management.operation(
             %{home: home},
             cwd,
             Path.basename(journal, ".jsonl")
           )

  # The old exact candidate cannot return, even when its source and shared anchor survive.
  retry = %{
    pending
    | request: %{pending.request | "expected_generation" => after_review["summary"]["generation"]}
  }

  assert {:error, :managed_normalization_refused} = Fixture.publish(c, retry, scope.(false))
  assert snapshot.() === after_review

  latest =
    if mode == "valid" do
      {:ok, fresh_key, fresh_value} =
        IpseKnowledge.Knowledge.Records.capture(
          %{
            "text" => "Acme may appoint Cam",
            "category" => "ordinary",
            "reason" => "a later distinct candidate",
            "event_at_ms" => nil
          },
          source,
          10 * 86_400_000
        )

      fresh = %{
        pending
        | request: %{
            pending.request
            | "expected_generation" => after_review["summary"]["generation"],
              "changes" => [
                %{"key" => fresh_key, "expected_revision" => 0, "value" => fresh_value}
              ]
          }
      }

      assert {:ok, admitted} = Fixture.publish(c, fresh, scope.(false))

      assert admitted.core["normalization"]["first_admitted_ms"] ===
               managed["metadata"]["first_admitted_ms"]

      assert admitted.core["normalization"]["valid_until_ms"] ===
               managed["metadata"]["valid_until_ms"]

      current = snapshot.()
      assert current["records"] === after_review["records"]
      current
    else
      after_review
    end

  assert 1 == Ipse.CLI.run(args)
  assert snapshot.() === latest
end

IO.puts("PENDING_REJECTION_#{String.upcase(mode)}_PASSED")
