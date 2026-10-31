# Local trusted-source fixture; signed records and protected storage are real.
# This does not claim a genuine original assertion or Review permit.
ExUnit.start(autorun: false)
Code.require_file("../ipse/extension/collection_normalizer_v3_integration_test.exs", __DIR__)
import ExUnit.Assertions
alias Ipse.{JSON, Usage}
alias Ipse.CLI.Knowledge.Management

alias Ipse.Extension.{
  Artifact,
  Bundles,
  Consent,
  ProjectIdentity,
  SemanticAdmission,
  SemanticConsent
}

alias Ipse.Extension.CollectionNormalizerV3IntegrationTest, as: Fixture

defmodule Ipse.Test.ManagementDisplayProbe do
  def replacement_recipe(root, home) do
    bundle_root = Application.app_dir(:ipse, "priv/extension-bundles")
    candidate = Path.join(root, "alternate-knowledge")
    File.cp_r!(Path.join(bundle_root, "knowledge"), candidate)
    sidecar_path = Path.join(candidate, "operator.json")
    {:ok, sidecar} = Ipse.JSON.decode_unique(File.read!(sidecar_path))
    original_recipe = sidecar["recipes"]["note"]
    rules = sidecar["recipes"]["note"]["rules"]

    rules =
      Enum.map(rules, fn rule ->
        if rule["category"] == "ordinary",
          do: Map.update!(rule, "max_age_ms", &(&1 + 1)),
          else: rule
      end)

    sidecar = put_in(sidecar, ["recipes", "note", "rules"], rules)
    true = Ipse.Extension.ManagedRecipe.valid?(sidecar["recipes"]["note"])
    true = sidecar["recipes"]["note"] != original_recipe
    sidecar_bytes = Jason.encode!(sidecar)
    File.write!(sidecar_path, sidecar_bytes)
    manifest_path = Path.join(candidate, "extension.json")
    {:ok, manifest} = Ipse.JSON.decode_unique(File.read!(manifest_path))

    files =
      Enum.map(manifest["files"], fn file ->
        if file["path"] == "operator.json",
          do: %{
            file
            | "bytes" => byte_size(sidecar_bytes),
              "sha256" => Ipse.JSON.sha256(sidecar_bytes)
          },
          else: file
      end)

    manifest_bytes = Jason.encode!(%{manifest | "files" => files})
    File.write!(manifest_path, manifest_bytes)
    digest = Ipse.JSON.sha256(manifest_bytes)

    {:ok, %{digest: ^digest}} =
      Ipse.Extension.Artifact.import(candidate, Path.join(home, "extensions/artifacts"))

    {:ok, ^sidecar_bytes} =
      Ipse.Extension.Artifact.read_declared(
        Path.join(home, "extensions/artifacts"),
        digest,
        "operator.json",
        65_536
      )

    target = Path.join(bundle_root, "knowledge-alternate")
    File.cp_r!(candidate, target)

    catalog =
      Jason.encode!(%{
        "version" => 1,
        "artifacts" => [
          %{"id" => "knowledge", "path" => "knowledge-alternate", "manifest_sha256" => digest}
        ]
      })

    {Path.join(bundle_root, "catalog.json"), catalog}
  end

  def alter_target(root, namespace, key, before, mode) do
    generation = before["witness"]["root"]["generation"]
    [record] = before["records"]

    {changed_key, revision, value} =
      if mode == "forget-target-change" do
        {key, record["revision"], Map.put(record["value"], "text", "Changed synthetic assertion")}
      else
        {"probe.other", 0, %{"version" => 1, "value" => "independent synthetic change"}}
      end

    request = %{
      "op" => "commit",
      "expected_generation" => generation,
      "advance_floor" => true,
      "changes" => [%{"key" => changed_key, "expected_revision" => revision, "value" => value}]
    }

    {:ok, _} =
      Ipse.Extension.Collection.execute_profile(
        root,
        namespace,
        request,
        Ipse.Usage.id(),
        Ipse.Extension.Collection.Profile.notes()
      )

    record(root, namespace, key)
  end

  def close_unknown(writer) do
    :ok = Ipse.Journal.Writer.close(writer)
    {:unknown, :synthetic_lost_close_reply}
  end

  def append_unknown(writer, token, intent) do
    :ok = Ipse.Journal.Writer.append_reserved(writer, token, intent)
    {:unknown, :synthetic_lost_intent_reply}
  end

  def record(root, namespace, key) do
    {:ok, view} = Ipse.Extension.Collection.open_view(root, namespace)

    try do
      {:ok, result} =
        Ipse.Extension.Collection.view_read(view, %{"op" => "get_many", "keys" => [key]})

      result
    after
      :ok = Ipse.Extension.Collection.close_view(view)
    end
  end

  def metadata(c, key, recipe) do
    alias Ipse.Extension.{Consent, ProjectIdentity, SemanticAdmission}
    alias Ipse.Extension.Collection.ObservedRead

    control = SemanticAdmission.control_root(c.home)
    {:ok, snapshot} = Consent.existing_snapshot(control, c.binding["project_id"])

    management_sha =
      Consent.management_sha256(c.binding["project_id"], snapshot["epoch"], snapshot["policy"])

    ProjectIdentity.with_existing_domain_auth(
      c.home,
      c.cwd,
      c.binding,
      %{namespace: c.namespace, format: "managed-metadata-v3"},
      fn cap, catalog ->
        Consent.with_existing_management_snapshot(
          control,
          c.binding["project_id"],
          snapshot["epoch"],
          management_sha,
          fn _ ->
            ObservedRead.with_managed_record(
              c.root,
              c.namespace,
              %{"op" => "get_record", "key" => key},
              cap,
              catalog,
              recipe,
              fn managed ->
                {:ok, managed["metadata"]}
              end
            )
          end
        )
      end
    )
  end

  def foreign_handle(handle, facts) do
    {:error, :native_review_refused} =
      Ipse.Runner.Review.with_management_input("retain", facts, handle, fn _ -> :ok end)

    task = Task.async(fn -> Ipse.Runner.ManagementTerminal.finish_review(handle, facts) end)
    {:error, :management_input_refused} = Task.await(task, 5_000)
    :ok
  end

  def replay_handle(handle, facts) do
    {:error, :management_input_refused} =
      Ipse.Runner.ManagementTerminal.finish_review(handle, facts)

    IO.puts("MANAGEMENT_REVIEW_FOREIGN_AND_REPLAY_REFUSED")
    :ok
  end

  def pause_close(owned, guardian) do
    send(Process.whereis(:management_display_probe), {:close_paused, self(), owned, guardian})

    receive do
      :continue -> :ok
    after
      10_000 -> :error
    end
  end

  def pause_snapshot do
    send(Process.whereis(:management_display_probe), {:snapshot_paused, self()})

    receive do
      :continue -> :ok
    after
      10_000 -> :error
    end
  end

  def pause(owned, reader, guardian, ids, journal) do
    send(
      Process.whereis(:management_display_probe),
      {:display_paused, self(), owned, reader, guardian, ids, journal}
    )

    receive do
      :continue -> :ok
    after
      10_000 -> :error
    end
  end

  def stopped?(pid, attempts \\ 500)
  def stopped?(_, 0), do: false

  def stopped?(pid, attempts) do
    case File.read("/proc/#{pid}/status") do
      {:ok, status} ->
        if Enum.any?(
             String.split(status, "\n"),
             &(String.starts_with?(&1, "State:") and String.contains?(&1, "stopped"))
           ),
           do: true,
           else:
             (
               Process.sleep(10)
               stopped?(pid, attempts - 1)
             )

      _ ->
        false
    end
  end

  def gone?(pid, attempts \\ 600)
  def gone?(_, 0), do: false

  def gone?(pid, attempts) do
    case File.read("/proc/#{pid}/stat") do
      {:error, :enoent} ->
        true

      {:ok, stat} ->
        if Regex.match?(~r/\) Z /, stat),
          do: true,
          else:
            (
              Process.sleep(10)
              gone?(pid, attempts - 1)
            )

      _ ->
        false
    end
  end

  def acquire(path, attempts \\ 600)
  def acquire(_, 0), do: {:error, :still_locked}

  def acquire(path, attempts) do
    case Ipse.Runner.protected_lock(path) do
      {:ok, _} = result ->
        result

      _ ->
        Process.sleep(10)
        acquire(path, attempts - 1)
    end
  end
end

[root | rest] = System.argv()
{:ok, _} = Application.ensure_all_started(:ipse)
home = Path.join(root, "home")
cwd = Path.join(root, "work")
File.mkdir_p!(home)
File.mkdir!(cwd)
File.chmod!(home, 0o700)
{:ok, binding} = ProjectIdentity.admit(home, cwd, :folder)
{:ok, namespace} = SemanticConsent.namespace(binding["project_id"], "knowledge")
assert {:ok, _} = Bundles.install("knowledge", home)
{:ok, entries} = Bundles.inventory()
%{digest: digest} = Enum.find(entries, &(&1.id == "knowledge"))

{:ok, sidecar_bytes} =
  Artifact.read_declared(Path.join(home, "extensions/artifacts"), digest, "operator.json", 65_536)

{:ok, sidecar} = JSON.decode_unique(sidecar_bytes)

opts = %{
  Fixture.options(1, 0)
  | recipe: sidecar["recipes"]["note"],
    constraints: sidecar["publication"]["note"]
}

opts =
  if rest == ["large"] do
    quote = String.duplicate("\\\"", 200)
    digest = JSON.sha256(quote)
    [original] = opts.verified_sources

    source =
      original
      |> Map.put("quote", quote)
      |> Map.put("end_byte", byte_size(quote))
      |> Map.put("quote_sha256", digest)
      |> Map.put("content_sha256", digest)

    {:ok, key, value} =
      IpseKnowledge.Knowledge.Records.capture(
        %{
          "text" => quote,
          "category" => "ordinary",
          "reason" => "trusted fixture source",
          "event_at_ms" => nil
        },
        source,
        10 * 86_400_000
      )

    %{
      opts
      | verified_sources: [source],
        request:
          put_in(opts.request, ["changes"], [
            %{"key" => key, "expected_revision" => 0, "value" => value}
          ])
    }
  else
    opts
  end

opts =
  cond do
    rest in [
      ["retention-review"],
      ["retention-review-ordinary"],
      ["retention-review-duration"],
      ["retention-review-cancel"],
      ["retention-effect"],
      ["retention-effect-ordinary"],
      ["retention-effect-duration"],
      ["retention-effect-writer-loss"],
      ["retention-effect-writer-after-rename"],
      ["retention-effect-writer-after-sync"],
      ["retention-effect-epoch-race"],
      ["retention-effect-root-race"],
      ["cli-retention-pin"],
      ["cli-retention-automatic"],
      ["cli-retention-duration"],
      ["cli-retention-cancel"],
      ["cli-retention-writer-loss"]
    ] ->
      Map.put(opts, :now_ms, System.system_time(:millisecond))

    rest == ["retention-review-future"] ->
      Map.put(opts, :now_ms, System.system_time(:millisecond) + 60_000)

    rest == ["retention-review-expire-after-input"] ->
      Map.put(opts, :now_ms, System.system_time(:millisecond) - 90 * 86_400_000 + 12_000)

    rest == ["retention-effect-expiry"] ->
      Map.put(opts, :now_ms, System.system_time(:millisecond) - 90 * 86_400_000 + 8_000)

    rest == ["cli-retention-expiry"] ->
      Map.put(opts, :now_ms, System.system_time(:millisecond) - 90 * 86_400_000 + 8_000)

    rest == ["retention-effect-new-expiry"] ->
      Map.put(opts, :now_ms, System.system_time(:millisecond))

    true ->
      opts
  end

c = %{
  home: home,
  cwd: cwd,
  binding: binding,
  root: SemanticAdmission.collection_root(home),
  namespace: namespace
}

scope = %{
  namespace: namespace,
  format: "managed-metadata-v3",
  operation_id: Usage.id(),
  initialize: true
}

assert {:ok, _} = Fixture.publish(c, opts, scope, first: true)
[key] = Enum.map(opts.request["changes"], & &1["key"])

assert {:ok, %{"epoch" => 1}} =
         Consent.revoke(SemanticAdmission.control_root(home), binding["project_id"], 0)

if rest in [
     ["cli-retention-pin"],
     ["cli-retention-automatic"],
     ["cli-retention-duration"],
     ["cli-retention-cancel"],
     ["cli-retention-expiry"],
     ["cli-retention-writer-loss"]
   ] do
  System.put_env("IPSE_HOME", home)

  for env <-
        ~w(IPSE_PROVIDER IPSE_MODEL IPSE_SANDBOX IPSE_MAX_STEPS IPSE_CONTEXT_BYTES IPSE_COMPACT IPSE_SUBAGENTS IPSE_SUBAGENT_CONCURRENCY IPSE_TIMEOUT_MS IPSE_MAX_OUTPUT_TOKENS IPSE_PROFILE IPSE_CONFIG),
      do: System.delete_env(env)

  config_path = Path.join(home, "config.json")

  File.write!(
    config_path,
    Jason.encode!(%{"version" => 1, "settings" => %{"provider" => "demo", "model" => "scripted"}})
  )

  File.chmod!(config_path, 0o600)

  {cli_policy, expected, days} =
    case rest do
      ["cli-retention-automatic"] ->
        {"automatic", %{"kind" => "ordinary"}, []}

      ["cli-retention-duration"] ->
        {"duration", %{"kind" => "duration", "duration_ms" => 86_400_000}, ["--days", "1"]}

      _ ->
        {"pin", %{"kind" => "pin"}, []}
    end

  args =
    ["knowledge", "retention", key, "--policy", cli_policy] ++
      days ++ ["--cwd", cwd, "--config", config_path, "--no-project-config"]

  before = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)
  {:ok, metadata} = Ipse.Test.ManagementDisplayProbe.metadata(c, key, opts.recipe)
  assert Ipse.CLI.run(args ++ ["--yes"]) == 1
  assert Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"])) == []

  if rest == ["cli-retention-expiry"] do
    owner = self()

    :ok =
      :telemetry.attach(
        "public-retention-expiry",
        [:ipse, :extension, :collection, :staged],
        fn _, _, _, _ ->
          deadline = Process.get({Ipse.Extension.Collection, :switch_deadline})
          assert deadline == metadata["valid_until_ms"]
          send(owner, {:public_retention_staged, deadline})
          Process.sleep(max(0, deadline - System.system_time(:millisecond)) + 50)
        end,
        nil
      )
  end

  if rest == ["cli-retention-writer-loss"] do
    source = File.read!("lib/ipse/cli/knowledge/management.ex")
    needle = "_ <- Process.put(slot, :effect_unknown),"
    assert length(String.split(source, needle)) == 2

    source =
      String.replace(
        source,
        needle,
        needle <> "\n               _ <- Process.put(:retention_test_writer, owned.writer),"
      )

    Code.compiler_options(ignore_module_conflict: true)

    [{Management, _}] =
      Code.compile_string(source, "public-retention-writer-loss-instrumented.ex")

    owner = self()

    :ok =
      :telemetry.attach(
        "public-retention-writer-loss",
        [:ipse, :extension, :collection, :staged],
        fn _, _, _, _ ->
          writer = Process.get(:retention_test_writer)
          assert is_pid(writer)
          send(owner, {:public_retention_writer_killed, writer})
          Process.exit(writer, :kill)
        end,
        nil
      )
  end

  code = Ipse.CLI.run(args)
  after_effect = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)
  assert hd(after_effect["records"])["value"] === hd(before["records"])["value"]

  if rest in [["cli-retention-cancel"], ["cli-retention-expiry"], ["cli-retention-writer-loss"]] do
    assert code == 1
    assert after_effect["witness"]["root_sha256"] === before["witness"]["root_sha256"]

    if rest in [["cli-retention-expiry"], ["cli-retention-writer-loss"]] do
      if rest == ["cli-retention-expiry"] do
        assert_receive {:public_retention_staged, deadline}, 1_000
        assert System.system_time(:millisecond) >= deadline
        :telemetry.detach("public-retention-expiry")
      else
        assert_receive {:public_retention_writer_killed, writer}, 1_000
        monitor = Process.monitor(writer)
        assert_receive {:DOWN, ^monitor, :process, ^writer, _}, 5_000
        :telemetry.detach("public-retention-writer-loss")
      end

      [journal] = Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"]))

      assert {:ok, %{"journal_status" => "unconfirmed", "replayed" => false}} =
               Management.operation(%{home: home}, cwd, Path.basename(journal, ".jsonl"))

      IO.puts(
        if(rest == ["cli-retention-expiry"],
          do: "PUBLIC_RETENTION_EXPIRY_UNCONFIRMED",
          else: "PUBLIC_RETENTION_WRITER_LOSS_UNCONFIRMED"
        )
      )
    else
      IO.puts("PUBLIC_RETENTION_CANCELLED")
    end
  else
    assert code == 0
    assert after_effect["witness"]["root"]["generation"] > before["witness"]["root"]["generation"]
    {:ok, after_metadata} = Ipse.Test.ManagementDisplayProbe.metadata(c, key, opts.recipe)
    assert after_metadata["first_admitted_ms"] === metadata["first_admitted_ms"]
    assert after_metadata["choice"]["policy"] === expected
    [journal] = Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"]))

    assert {:ok, %{"journal_status" => "settled", "replayed" => false}} =
             Management.operation(%{home: home}, cwd, Path.basename(journal, ".jsonl"))

    IO.puts("PUBLIC_RETENTION_SETTLED " <> cli_policy)
  end

  System.halt(0)
end

if rest in [["retention-effect-epoch-race"], ["retention-effect-root-race"]] do
  before = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)
  {:ok, before_metadata} = Ipse.Test.ManagementDisplayProbe.metadata(c, key, opts.recipe)
  config = %{home: home, approval: :ask, approval_origin: :interactive, headless: false}

  task =
    Task.async(fn ->
      Management.full_facts_retention_effect_candidate(
        config,
        cwd,
        key,
        %{"kind" => "pin"},
        "Review synthetic retention"
      )
    end)

  ready = Path.join(root, "management-review-input-ready")
  deadline = System.monotonic_time(:millisecond) + 10_000

  wait = fn wait ->
    cond do
      File.exists?(ready) ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        :timeout

      true ->
        Process.sleep(10)
        wait.(wait)
    end
  end

  assert :ok = wait.(wait)

  competing =
    if rest == ["retention-effect-epoch-race"] do
      assert {:ok, %{"epoch" => 2}} =
               Consent.revoke(SemanticAdmission.control_root(home), binding["project_id"], 1)

      before
    else
      Ipse.Test.ManagementDisplayProbe.alter_target(
        c.root,
        namespace,
        key,
        before,
        "forget-root-change"
      )
    end

  File.write!(Path.join(root, "management-review-race-complete"), "done")
  result = Task.await(task, 30_000)
  refute match?({:closed, {:ok, _}}, result)
  after_effect = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)
  assert after_effect["witness"]["root_sha256"] === competing["witness"]["root_sha256"]
  assert hd(after_effect["records"])["value"] === hd(before["records"])["value"]
  {:ok, after_metadata} = Ipse.Test.ManagementDisplayProbe.metadata(c, key, opts.recipe)
  assert after_metadata === before_metadata
  [journal] = Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"]))
  id = Path.basename(journal, ".jsonl")
  {:ok, events} = Ipse.Journal.load(Path.dirname(journal), id)
  assert Enum.count(events, &(&1["type"] == "managed_lifecycle_intent")) == 1

  assert {:ok, %{"journal_status" => status, "replayed" => false}} =
           Management.operation(%{home: home}, cwd, id)

  assert status in ~w(refused unconfirmed)
  IO.puts("MANAGEMENT_RETENTION_RACE_NOT_SETTLED " <> hd(rest) <> " " <> status)
  System.halt(0)
end

if rest in [
     ["retention-effect"],
     ["retention-effect-ordinary"],
     ["retention-effect-duration"],
     ["retention-effect-expiry"],
     ["retention-effect-new-expiry"],
     ["retention-effect-writer-loss"],
     ["retention-effect-writer-after-rename"],
     ["retention-effect-writer-after-sync"]
   ] do
  before = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)
  {:ok, before_metadata} = Ipse.Test.ManagementDisplayProbe.metadata(c, key, opts.recipe)

  policy =
    case rest do
      ["retention-effect-ordinary"] -> %{"kind" => "ordinary"}
      ["retention-effect-duration"] -> %{"kind" => "duration", "duration_ms" => 86_400_000}
      ["retention-effect-new-expiry"] -> %{"kind" => "duration", "duration_ms" => 8_000}
      _ -> %{"kind" => "pin"}
    end

  if rest in [
       ["retention-effect-writer-loss"],
       ["retention-effect-writer-after-rename"],
       ["retention-effect-writer-after-sync"]
     ] do
    source = File.read!("lib/ipse/cli/knowledge/management.ex")
    needle = "_ <- Process.put(slot, :effect_unknown),"
    assert length(String.split(source, needle)) == 2

    source =
      String.replace(
        source,
        needle,
        needle <> "\n               _ <- Process.put(:retention_test_writer, owned.writer),"
      )

    Code.compiler_options(ignore_module_conflict: true)
    [{Management, _}] = Code.compile_string(source, "retention-writer-loss-instrumented.ex")

    owner = self()

    :ok =
      :telemetry.attach(
        "synthetic-retention-writer-loss",
        [:ipse, :extension, :collection, :staged],
        fn _, _, _, _ ->
          writer = Process.get(:retention_test_writer)
          assert is_pid(writer)

          if rest in [
               ["retention-effect-writer-after-rename"],
               ["retention-effect-writer-after-sync"]
             ] do
            phase =
              if rest == ["retention-effect-writer-after-rename"],
                do: "after-rename",
                else: "after-sync"

            File.write!(Path.join(cwd, "source-switch-#{phase}.arm"), "armed")
            send(owner, :retention_switch_watcher_started)

            spawn(fn ->
              marker = Path.join(cwd, "source-switch-#{phase}.ready")
              limit = System.monotonic_time(:millisecond) + 15_000

              wait = fn wait ->
                cond do
                  File.exists?(marker) ->
                    :ok

                  System.monotonic_time(:millisecond) >= limit ->
                    :timeout

                  true ->
                    Process.sleep(5)
                    wait.(wait)
                end
              end

              if wait.(wait) == :ok do
                send(owner, {:retention_writer_kill_requested, writer})
                monitor = Process.monitor(writer)
                Process.exit(writer, :kill)

                receive do
                  {:DOWN, ^monitor, :process, ^writer, _} ->
                    File.write!(Path.join(cwd, "source-switch-#{phase}.go"), "go")
                after
                  5_000 -> :ok
                end
              else
                send(owner, :retention_switch_watcher_timeout)
              end
            end)
          else
            send(owner, {:retention_writer_kill_requested, writer})
            Process.exit(writer, :kill)
          end
        end,
        nil
      )
  end

  if rest in [["retention-effect-expiry"], ["retention-effect-new-expiry"]] do
    owner = self()

    :ok =
      :telemetry.attach(
        "synthetic-retention-expiry",
        [:ipse, :extension, :collection, :staged],
        fn _, _, _, _ ->
          deadline = Process.get({Ipse.Extension.Collection, :switch_deadline})
          assert Ipse.JSON.safe_uint?(deadline)
          send(owner, {:retention_staged, deadline, System.system_time(:millisecond)})
          Process.sleep(max(0, deadline - System.system_time(:millisecond)) + 50)
        end,
        nil
      )
  end

  result =
    Management.full_facts_retention_effect_candidate(
      %{home: home, approval: :ask, approval_origin: :interactive, headless: false},
      cwd,
      key,
      policy,
      "Review selected synthetic retention choice"
    )

  after_effect = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)
  assert hd(after_effect["records"])["value"] === hd(before["records"])["value"]

  if rest in [["retention-effect"], ["retention-effect-ordinary"], ["retention-effect-duration"]] do
    assert {:closed, {:ok, packet}} = result
    assert packet["storage_status"] == "settled"

    assert get_in(packet, ["receipt", "publication", "normalization", "policy"]) == policy
    {:ok, after_metadata} = Ipse.Test.ManagementDisplayProbe.metadata(c, key, opts.recipe)
    assert after_metadata["first_admitted_ms"] === before_metadata["first_admitted_ms"]
    assert after_metadata["choice"]["policy"] === policy

    assert after_metadata["valid_until_ms"] ===
             get_in(packet, ["receipt", "publication", "normalization", "valid_until_ms"])

    assert after_effect["witness"]["root"]["generation"] > before["witness"]["root"]["generation"]

    assert {:ok, %{"journal_status" => "settled", "replayed" => false}} =
             Management.operation(%{home: home}, cwd, packet["journal_id"])

    IO.puts("MANAGEMENT_RETENTION_EFFECT_SETTLED")
  else
    if rest in [
         ["retention-effect-writer-loss"],
         ["retention-effect-writer-after-rename"],
         ["retention-effect-writer-after-sync"]
       ] do
      if rest in [
           ["retention-effect-writer-after-rename"],
           ["retention-effect-writer-after-sync"]
         ],
         do: assert_receive(:retention_switch_watcher_started, 1_000)

      assert_receive {:retention_writer_kill_requested, writer}, 1_000
      monitor = Process.monitor(writer)
      assert_receive {:DOWN, ^monitor, :process, ^writer, _}, 5_000
      assert match?({:unknown, _}, result) or match?({:closed, {:unknown, _}}, result)

      if rest == ["retention-effect-writer-loss"] do
        assert after_effect["witness"]["root_sha256"] === before["witness"]["root_sha256"]
      else
        assert after_effect["witness"]["root"]["generation"] >
                 before["witness"]["root"]["generation"]

        {:ok, metadata} = Ipse.Test.ManagementDisplayProbe.metadata(c, key, opts.recipe)
        assert metadata["choice"]["policy"] === %{"kind" => "pin"}
      end

      [journal] = Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"]))
      id = Path.basename(journal, ".jsonl")

      if rest in [
           ["retention-effect-writer-after-rename"],
           ["retention-effect-writer-after-sync"]
         ] do
        {:ok, events} = Ipse.Journal.load(Path.dirname(journal), id)
        [intent] = Enum.filter(events, &(&1["type"] == "managed_lifecycle_intent"))
        assert after_effect["witness"]["root"]["floor_anchor"] === intent["operation_id"]
        refute Enum.any?(events, &(&1["type"] == "managed_lifecycle_result"))
      end

      assert {:ok, %{"journal_status" => "unconfirmed", "replayed" => false}} =
               Management.operation(%{home: home}, cwd, id)

      :telemetry.detach("synthetic-retention-writer-loss")
      IO.puts("MANAGEMENT_RETENTION_WRITER_LOSS_UNKNOWN " <> hd(rest))
      System.halt(0)
    end

    assert_receive {:retention_staged, deadline, staged_at}, 1_000

    if rest == ["retention-effect-new-expiry"] do
      assert deadline > staged_at
      assert deadline <= staged_at + 8_000
      assert deadline < before_metadata["valid_until_ms"]
    end

    assert System.system_time(:millisecond) >= deadline
    assert {:closed, {:unknown, _}} = result
    assert after_effect["witness"]["root_sha256"] === before["witness"]["root_sha256"]
    [journal] = Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"]))
    id = Path.basename(journal, ".jsonl")

    assert {:ok, %{"journal_status" => "unconfirmed", "replayed" => false}} =
             Management.operation(%{home: home}, cwd, id)

    :telemetry.detach("synthetic-retention-expiry")
    IO.puts("MANAGEMENT_RETENTION_EFFECT_EXPIRED_UNKNOWN")
  end

  System.halt(0)
end

if rest in [
     ["retention-review"],
     ["retention-review-ordinary"],
     ["retention-review-duration"],
     ["retention-review-cancel"],
     ["retention-review-expired"],
     ["retention-review-future"],
     ["retention-review-expire-after-input"]
   ] do
  if rest == ["retention-review-expire-after-input"] do
    source = File.read!("lib/ipse/cli/knowledge/management.ex")
    needle = "if ManagedLifecycle.retention_review?("
    assert length(String.split(source, needle)) == 2

    source =
      String.replace(source, needle, "Process.sleep(13_000)\n                      " <> needle)

    Code.compiler_options(ignore_module_conflict: true)
    [{Management, _}] = Code.compile_string(source, "retention-review-delayed.ex")
  end

  before = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)

  policy =
    case rest do
      ["retention-review-ordinary"] -> %{"kind" => "ordinary"}
      ["retention-review-duration"] -> %{"kind" => "duration", "duration_ms" => 86_400_000}
      _ -> %{"kind" => "pin"}
    end

  result =
    Management.full_facts_retention_review_candidate(
      %{home: home},
      cwd,
      key,
      policy,
      "Review selected synthetic claim"
    )

  if rest in [["retention-review"], ["retention-review-ordinary"], ["retention-review-duration"]] do
    assert {:closed, {:ok, receipt}} = result
    assert receipt["kind"] == "native_review" and receipt["command"] == policy["kind"]
  else
    assert {:closed, {:error, _}} = result
  end

  after_review = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)
  assert after_review == before
  IO.puts("MANAGEMENT_RETENTION_REVIEW_RESULT " <> hd(rest))
  System.halt(0)
end

if rest == ["review-handles"] do
  source = File.read!("lib/ipse/cli/knowledge/management.ex")
  first = "Review.with_management_input(\"forget\", prepared[\"facts\"], handle, fn permit ->"

  last =
    "            end)\n          end\n        end)\n\n      management_display_completion(result, overall, wall)"

  assert length(String.split(source, first)) == 2
  assert length(String.split(source, last)) == 2

  source =
    String.replace(
      source,
      first,
      "Ipse.Test.ManagementDisplayProbe.foreign_handle(handle, prepared[\"facts\"])\n            review_result = " <>
        first
    )

  source =
    String.replace(
      source,
      last,
      "            end)\n            Ipse.Test.ManagementDisplayProbe.replay_handle(handle, prepared[\"facts\"])\n            review_result\n          end\n        end)\n\n      management_display_completion(result, overall, wall)"
    )

  File.write!(Path.join(root, "management-handles-instrumented.ex"), source)
  Code.compiler_options(ignore_module_conflict: true)

  [{Ipse.CLI.Knowledge.Management, beam}] =
    Code.compile_string(source, "management-handles-instrumented.ex")

  File.write!(Path.join(root, "management-handles-instrumented.beam"), beam)
end

if rest in [["review-expired"], ["forget-expired"]] do
  source = File.read!("lib/ipse/runner/management_terminal.ex")
  needle = "permit_deadline = System.monotonic_time(:millisecond) + 30_000"
  assert length(String.split(source, needle)) == 2

  source =
    String.replace(source, needle, "permit_deadline = System.monotonic_time(:millisecond) - 1")

  File.write!(Path.join(root, "management-expired-instrumented.ex"), source)
  Code.compiler_options(ignore_module_conflict: true)

  [{Ipse.Runner.ManagementTerminal, beam}] =
    Code.compile_string(source, "management-expired-instrumented.ex")

  File.write!(Path.join(root, "management-expired-instrumented.beam"), beam)
end

if rest == ["forget-late"] do
  :ok =
    :telemetry.attach(
      "management-forget-late",
      [:ipse, :extension, :collection, :staged],
      fn _, _, _, _ ->
        pending = Process.get({Ipse.Runner.Review, :permit})
        assert pending.status == :consumed
        cap = Process.get({Ipse.Extension.Collection, :lock_held})
        {:os_pid, native} = Port.info(cap.port, :os_pid)
        assert {_, 0} = System.cmd("/bin/kill", ["-STOP", Integer.to_string(native)])

        try do
          Process.sleep(max(pending.deadline - System.monotonic_time(:millisecond) + 50, 0))
          assert System.monotonic_time(:millisecond) > pending.deadline
        after
          System.cmd("/bin/kill", ["-CONT", Integer.to_string(native)], stderr_to_stdout: true)
        end

        IO.puts("MANAGEMENT_FORGET_PERMIT_EXPIRED_BEFORE_SWITCH")
      end,
      nil
    )
end

if rest == ["forget-staged-owner-loss"] do
  Process.register(self(), :management_staged_owner_probe)

  :ok =
    :telemetry.attach(
      "management-staged-owner-loss",
      [:ipse, :extension, :collection, :staged],
      fn _, _, _, _ ->
        pending = Process.get({Ipse.Runner.Review, :permit})
        assert pending.status == :consumed
        cap = Process.get({Ipse.Extension.Collection, :lock_held})
        {:os_pid, native} = Port.info(cap.port, :os_pid)
        assert {_, 0} = System.cmd("/bin/kill", ["-STOP", Integer.to_string(native)])

        try do
          send(Process.whereis(:management_staged_owner_probe), {:staged_owner, self(), native})

          receive do
            :continue -> :ok
          after
            15_000 -> :timeout
          end
        after
          System.cmd("/bin/kill", ["-CONT", Integer.to_string(native)], stderr_to_stdout: true)
        end
      end,
      nil
    )
end

if rest == ["forget-uncertain"] do
  source = File.read!("lib/ipse/extension/collection/normalizer_v3.ex")
  needle = "def forget(witness, read, options), do: manage(witness, read, options, :forget)"
  assert length(String.split(source, needle)) == 2

  source =
    String.replace(
      source,
      needle,
      "def forget(_witness, _read, _options), do: raise(\"synthetic normalizer loss\")"
    )

  File.write!(Path.join(root, "normalizer-uncertain-instrumented.ex"), source)
  Code.compiler_options(ignore_module_conflict: true)

  [{Ipse.Extension.Collection.NormalizerV3, beam}] =
    Code.compile_string(source, "normalizer-uncertain-instrumented.ex")

  File.write!(Path.join(root, "normalizer-uncertain-instrumented.beam"), beam)
end

if rest == ["forget-intent-unknown"] do
  source = File.read!("lib/ipse/cli/knowledge/management.ex")
  needle = "Writer.append_reserved(owned.writer, token, prepared[\"intent\"])"
  assert length(String.split(source, needle)) == 2

  source =
    String.replace(
      source,
      needle,
      "Ipse.Test.ManagementDisplayProbe.append_unknown(owned.writer, token, prepared[\"intent\"])"
    )

  File.write!(Path.join(root, "management-intent-unknown-instrumented.ex"), source)
  Code.compiler_options(ignore_module_conflict: true)

  [{Ipse.CLI.Knowledge.Management, beam}] =
    Code.compile_string(source, "management-intent-unknown-instrumented.ex")

  File.write!(Path.join(root, "management-intent-unknown-instrumented.beam"), beam)
end

if rest in [["forget-settle-unknown"], ["forget-close-unknown"], ["cli-close-unknown"]] do
  source = File.read!("lib/ipse/cli/knowledge/management.ex")

  {needle, replacement} =
    if rest == ["forget-settle-unknown"] do
      {"{:ok, _} = settled -> settled",
       "{:ok, _} -> {:unknown, :synthetic_lost_settlement_reply}"}
    else
      {"if Writer.close(writer) == :ok,",
       "if Ipse.Test.ManagementDisplayProbe.close_unknown(writer) == :ok,"}
    end

  assert String.contains?(source, needle)
  source = String.replace(source, needle, replacement)
  File.write!(Path.join(root, "management-cleanup-unknown-instrumented.ex"), source)
  Code.compiler_options(ignore_module_conflict: true)

  [{Ipse.CLI.Knowledge.Management, beam}] =
    Code.compile_string(source, "management-cleanup-unknown-instrumented.ex")

  File.write!(Path.join(root, "management-cleanup-unknown-instrumented.beam"), beam)
end

if rest == ["late-return"] do
  source = File.read!("lib/ipse/cli/knowledge/management.ex")
  needle = "management_display_completion(result, overall, wall)"
  assert length(String.split(source, needle)) == 2

  source =
    String.replace(
      source,
      needle,
      "management_display_completion(result, overall, System.system_time(:millisecond) - 1)"
    )

  File.write!(Path.join(root, "management-late-instrumented.ex"), source)
  Code.compiler_options(ignore_module_conflict: true)

  [{Ipse.CLI.Knowledge.Management, beam}] =
    Code.compile_string(source, "management-late-instrumented.ex")

  File.write!(Path.join(root, "management-late-instrumented.beam"), beam)

  assert {:unknown, :management_display_unconfirmed} =
           Management.full_facts_display_candidate(
             %{home: home},
             cwd,
             key,
             "Forget selected synthetic claim"
           )

  IO.puts("\nMANAGEMENT_LATE_RETURN_UNKNOWN_AFTER_ACTUAL_CLOSURE")
else
  if rest == ["closure-loss"] do
    source = File.read!("lib/ipse/runner/management_terminal.ex")
    needle = ":ok <- Resources.management_control_prepare_close(owned.cli_control),"
    assert length(String.split(source, needle)) == 2

    source =
      String.replace(
        source,
        needle,
        ":ok <- Ipse.Test.ManagementDisplayProbe.pause_close(owned, pid),\n             " <>
          needle
      )

    File.write!(Path.join(root, "management-terminal-close-instrumented.ex"), source)
    Code.compiler_options(ignore_module_conflict: true)

    [{Ipse.Runner.ManagementTerminal, beam}] =
      Code.compile_string(source, "management-terminal-close-instrumented.ex")

    File.write!(Path.join(root, "management-terminal-close-instrumented.beam"), beam)
    Process.register(self(), :management_display_probe)

    task =
      Task.async(fn ->
        Management.full_facts_display_candidate(
          %{home: home},
          cwd,
          key,
          "Forget selected synthetic claim"
        )
      end)

    assert_receive {:close_paused, effect, owned, guardian}, 5_000

    paths = [
      Path.join(owned.directory, owned.id <> ".lock"),
      Path.join([home, "project-identities", ".lock"]),
      Path.join([SemanticAdmission.control_root(home), binding["project_id"], ".lock"]),
      Path.join([SemanticAdmission.collection_root(home), namespace, ".lock"])
    ]

    for path <- paths, do: assert({:error, _} = Ipse.Runner.protected_lock(path))
    monitor = Process.monitor(effect)
    Process.exit(effect, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 5_000
    assert {:unknown, _} = Task.await(task, 10_000)
    assert Ipse.Test.ManagementDisplayProbe.gone?(guardian)

    for path <- paths do
      assert {:ok, lock} = Ipse.Test.ManagementDisplayProbe.acquire(path)
      assert :ok = Ipse.Runner.unlock(lock)
    end

    IO.puts("\nMANAGEMENT_CLOSE_ACK_LOSS_UNKNOWN_NO_THAW_CLAIM")
  else
    if rest == ["stale"] do
      source = File.read!("lib/ipse/cli/knowledge/management.ex")
      needle = "controlled_share_journal_candidate(config, cwd, overall, fn owned ->"
      assert length(String.split(source, needle)) == 2

      source =
        String.replace(
          source,
          needle,
          "controlled_share_journal_candidate(config, cwd, (Ipse.Test.ManagementDisplayProbe.pause_snapshot(); overall), fn owned ->"
        )

      File.write!(Path.join(root, "management-instrumented.ex"), source)
      Code.compiler_options(ignore_module_conflict: true)

      [{Ipse.CLI.Knowledge.Management, beam}] =
        Code.compile_string(source, "management-instrumented.ex")

      File.write!(Path.join(root, "management-instrumented.beam"), beam)
      Process.register(self(), :management_display_probe)

      task =
        Task.async(fn ->
          Management.full_facts_display_candidate(
            %{home: home},
            cwd,
            key,
            "Forget selected synthetic claim"
          )
        end)

      assert_receive {:snapshot_paused, caller}, 5_000
      assert caller == task.pid

      assert {:ok, %{"epoch" => 2}} =
               Consent.revoke(SemanticAdmission.control_root(home), binding["project_id"], 1)

      send(caller, :continue)
      assert {:closed, {:error, :consent_read_refused}} = Task.await(task, 10_000)
      IO.puts("MANAGEMENT_STALE_EPOCH_REFUSED_BEFORE_DISPLAY")
    else
      if rest in [["loss"], ["journal-loss"], ["cli-loss"]] do
        source = File.read!("lib/ipse/runner/management_terminal.ex")
        assert length(String.split(source, "_reader::32")) == 2
        source = String.replace(source, "_reader::32", "reader::32")
        needle = ":ok <- send_frame(port, ?A, body),"
        assert length(String.split(source, needle)) == 2

        source =
          String.replace(
            source,
            needle,
            needle <>
              "\n             :ok <- Ipse.Test.ManagementDisplayProbe.pause(owned, reader, pid, ids, journal),"
          )

        File.write!(Path.join(root, "management-terminal-instrumented.ex"), source)
        Code.compiler_options(ignore_module_conflict: true)

        [{Ipse.Runner.ManagementTerminal, beam}] =
          Code.compile_string(source, "management-terminal-instrumented.ex")

        File.write!(Path.join(root, "management-terminal-instrumented.beam"), beam)
        Process.register(self(), :management_display_probe)

        task =
          Task.async(fn ->
            Management.full_facts_display_candidate(
              %{home: home},
              cwd,
              key,
              "Forget selected synthetic claim"
            )
          end)

        Process.unlink(task.pid)
        assert_receive {:display_paused, effect, owned, reader, guardian, ids, journal}, 5_000
        assert owned.cli_owner == task.pid and owned.journal_owner == effect
        assert Ipse.Test.ManagementDisplayProbe.stopped?(reader)
        assert {_, 0} = System.cmd("kill", ["-STOP", Integer.to_string(guardian)])

        paths = [
          Path.join(owned.directory, owned.id <> ".lock"),
          Path.join([home, "project-identities", ".lock"]),
          Path.join([SemanticAdmission.control_root(home), binding["project_id"], ".lock"]),
          Path.join([SemanticAdmission.collection_root(home), namespace, ".lock"])
        ]

        try do
          caller_ref = Process.monitor(task.pid)
          effect_ref = Process.monitor(effect)

          if rest == ["loss"] or rest == ["cli-loss"] do
            Process.exit(task.pid, :kill)
            assert_receive {:DOWN, ^caller_ref, :process, _, _}, 5_000

            if rest == ["loss"] do
              Process.exit(effect, :kill)
              assert_receive {:DOWN, ^effect_ref, :process, _, _}, 5_000
            else
              assert Process.alive?(effect)
            end
          else
            Process.exit(effect, :kill)
            assert_receive {:DOWN, ^effect_ref, :process, _, _}, 5_000
            assert {:unknown, _} = Task.await(task, 10_000)
          end

          assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(guardian)])

          if rest != ["cli-loss"] do
            assert Ipse.Test.ManagementDisplayProbe.gone?(journal.pid)
            assert Ipse.Test.ManagementDisplayProbe.gone?(hd(ids).pid)
          end

          for path <- paths, do: assert({:error, _} = Ipse.Runner.protected_lock(path))
          assert {_, 0} = System.cmd("kill", ["-CONT", Integer.to_string(reader)])

          if rest == ["cli-loss"] do
            send(effect, :continue)
            assert_receive {:DOWN, ^effect_ref, :process, _, _}, 10_000
          end

          for path <- paths do
            assert {:ok, lock} = Ipse.Test.ManagementDisplayProbe.acquire(path)
            assert :ok = Ipse.Runner.unlock(lock)
          end

          IO.puts(
            if(rest == ["cli-loss"],
              do: "\nMANAGEMENT_CLI_LOSS_WITH_LIVE_EFFECT_UNKNOWN_AND_RELEASED",
              else:
                "\nMANAGEMENT_ADMITTED_WRITE_OWNER_LOSS_UNKNOWN_FOUR_LOCKS_HELD_UNTIL_READER_EXIT"
            )
          )
        after
          System.cmd("kill", ["-CONT", Integer.to_string(reader)], stderr_to_stdout: true)
          System.cmd("kill", ["-KILL", Integer.to_string(reader)], stderr_to_stdout: true)
          System.cmd("kill", ["-CONT", Integer.to_string(guardian)], stderr_to_stdout: true)
          System.cmd("kill", ["-KILL", Integer.to_string(guardian)], stderr_to_stdout: true)
        end
      else
        if rest in [
             ["cli-success"],
             ["cli-session"],
             ["cli-session-cancel"],
             ["cli-close-unknown"],
             ["cli-no-tty"]
           ] do
          System.put_env("IPSE_HOME", home)

          for env <-
                ~w(IPSE_PROVIDER IPSE_MODEL IPSE_SANDBOX IPSE_MAX_STEPS IPSE_CONTEXT_BYTES IPSE_COMPACT IPSE_SUBAGENTS IPSE_SUBAGENT_CONCURRENCY IPSE_TIMEOUT_MS IPSE_MAX_OUTPUT_TOKENS IPSE_PROFILE IPSE_CONFIG),
              do: System.delete_env(env)

          config_path = Path.join(home, "config.json")

          File.write!(
            config_path,
            Jason.encode!(%{
              "version" => 1,
              "settings" => %{"provider" => "demo", "model" => "scripted"}
            })
          )

          File.chmod!(config_path, 0o600)

          command =
            if rest in [["cli-session"], ["cli-session-cancel"]],
              do: ["retention", key, "--policy", "session"],
              else: ["forget", key]

          args =
            ["knowledge"] ++
              command ++ ["--cwd", cwd, "--config", config_path, "--no-project-config"]

          before = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)
          assert Ipse.CLI.run(args ++ ["--yes"]) == 1
          assert Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"])) == []
          code = Ipse.CLI.run(args)

          if rest in [["cli-no-tty"], ["cli-session-cancel"]] do
            assert code == 1

            if rest == ["cli-no-tty"],
              do:
                assert(Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"])) == [])

            after_result = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)
            assert after_result["witness"]["root_sha256"] === before["witness"]["root_sha256"]

            IO.puts(
              if(rest == ["cli-session-cancel"],
                do: "\nMANAGEMENT_SESSION_CANCELLED",
                else: "\nMANAGEMENT_PUBLIC_NO_TTY_REFUSED"
              )
            )
          else
            assert code == if(rest in [["cli-success"], ["cli-session"]], do: 0, else: 1)
            [path] = Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"]))
            id = Path.basename(path, ".jsonl")

            assert {:ok,
                    %{
                      "journal_status" => "settled",
                      "control_status" => "settled",
                      "replayed" => false
                    }} = Management.operation(%{home: home}, cwd, id)

            if rest == ["cli-success"] do
              complete = File.read!(path)
              partial = complete <> "{\"type\":\"managed_lifecycle_result\""
              lock_path = Path.join(Path.dirname(path), id <> ".lock")
              assert {:ok, lock} = Ipse.Runner.protected_resume_lock(lock_path)
              File.write!(path, partial)
              assert :ok = Ipse.Runner.unlock_export_candidate(lock)

              assert {:ok,
                      %{
                        "journal_status" => "unconfirmed",
                        "control_status" => "settled",
                        "replayed" => false
                      }} = Management.operation(%{home: home}, cwd, id)

              assert File.read!(path) === partial
              assert {:ok, lock} = Ipse.Runner.protected_resume_lock(lock_path)
              File.write!(path, complete)
              assert :ok = Ipse.Runner.unlock_export_candidate(lock)
            end

            assert Ipse.CLI.run([
                     "knowledge",
                     "operation",
                     id,
                     "--cwd",
                     cwd,
                     "--config",
                     config_path,
                     "--no-project-config",
                     "--json"
                   ]) == 0

            after_result = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)
            assert after_result["records"] == [nil]

            IO.puts(
              case rest do
                ["cli-success"] -> "\nMANAGEMENT_PUBLIC_FORGET_SETTLED"
                ["cli-session"] -> "\nMANAGEMENT_PUBLIC_SESSION_RETENTION_SETTLED"
                _ -> "\nMANAGEMENT_PUBLIC_FORGET_UNKNOWN_INSPECTED"
              end
            )
          end
        else
          if rest == ["forget-staged-owner-loss"] do
            before = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)
            config = %{home: home, approval: :ask, approval_origin: :interactive, headless: false}

            task =
              Task.async(fn ->
                Management.full_facts_forget_candidate(
                  config,
                  cwd,
                  key,
                  "Forget selected synthetic claim"
                )
              end)

            Process.unlink(task.pid)
            caller_ref = Process.monitor(task.pid)
            assert_receive {:staged_owner, effect, native}, 10_000
            effect_ref = Process.monitor(effect)
            [path] = Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"]))
            id = Path.basename(path, ".jsonl")

            paths = [
              Path.join([home, "knowledge-management", id <> ".lock"]),
              Path.join([home, "project-identities", ".lock"]),
              Path.join([SemanticAdmission.control_root(home), binding["project_id"], ".lock"]),
              Path.join([c.root, namespace, ".lock"])
            ]

            try do
              Process.exit(task.pid, :kill)
              assert_receive {:DOWN, ^caller_ref, :process, _, _}, 5_000
              assert Process.alive?(effect)
              assert Ipse.Test.ManagementDisplayProbe.stopped?(native)

              for lock_path <- paths,
                  do: assert({:error, _} = Ipse.Runner.protected_lock(lock_path))

              send(effect, :continue)
              assert_receive {:DOWN, ^effect_ref, :process, _, _}, 12_000

              for lock_path <- paths do
                assert {:ok, lock} = Ipse.Test.ManagementDisplayProbe.acquire(lock_path)
                assert :ok = Ipse.Runner.unlock(lock)
              end

              assert {:ok, %{"journal_status" => "unconfirmed", "replayed" => false} = inspected} =
                       Management.operation(config, cwd, id)

              assert inspected["control_status"] in ["publishing", "unavailable"]
              current = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)
              assert current["records"] == [nil] or current["records"] === before["records"]

              IO.puts(
                "\nMANAGEMENT_FORGET_STAGED_OWNER_LOSS_UNCONFIRMED_NO_REPLAY target_present=#{current["records"] != [nil]} control=#{inspected["control_status"]}"
              )
            after
              System.cmd("/bin/kill", ["-CONT", Integer.to_string(native)],
                stderr_to_stdout: true
              )
            end
          else
            if rest in [
                 ["forget-target-change"],
                 ["forget-root-change"],
                 ["forget-recipe-change"]
               ] do
              [mode] = rest
              before = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)

              alternate =
                if mode == "forget-recipe-change",
                  do: Ipse.Test.ManagementDisplayProbe.replacement_recipe(root, home),
                  else: nil

              config = %{
                home: home,
                approval: :ask,
                approval_origin: :interactive,
                headless: false
              }

              Code.ensure_loaded!(Ipse.Runner.Review)
              1 = :erlang.trace_pattern({Ipse.Runner.Review, :consume, 3}, true, [:local])
              true = :erlang.trace(:all, true, [:call, :set_on_spawn]) > 0
              observer = self()

              probe =
                spawn(fn ->
                  send(
                    observer,
                    {:trace_probe, self(), Ipse.Runner.Review.consume(nil, "forget", %{})}
                  )
                end)

              assert_receive {:trace, ^probe, :call, {Ipse.Runner.Review, :consume, _}}, 5_000
              assert_receive {:trace_probe, ^probe, {:error, :native_review_refused}}, 5_000

              task =
                Task.async(fn ->
                  Management.full_facts_forget_candidate(
                    config,
                    cwd,
                    key,
                    "Forget selected synthetic claim"
                  )
                end)

              ready = Path.join(root, "management-review-input-ready")
              deadline = System.monotonic_time(:millisecond) + 8_000

              wait = fn wait ->
                cond do
                  File.exists?(ready) ->
                    :ok

                  System.monotonic_time(:millisecond) >= deadline ->
                    :error

                  true ->
                    Process.sleep(10)
                    wait.(wait)
                end
              end

              assert :ok = wait.(wait)

              changed =
                if mode == "forget-recipe-change" do
                  {catalog, bytes} = alternate
                  File.write!(catalog, bytes)
                  assert {:ok, [entry]} = Bundles.inventory()

                  assert entry.digest ==
                           JSON.sha256(File.read!(Path.join(entry.path, "extension.json")))

                  before
                else
                  Ipse.Test.ManagementDisplayProbe.alter_target(
                    c.root,
                    namespace,
                    key,
                    before,
                    mode
                  )
                end

              File.write!(Path.join(root, "management-review-race-complete"), "done")
              result = Task.await(task, 10_000)

              delivery = :erlang.trace_delivered(:all)
              assert_receive {:trace_delivered, :all, ^delivery}, 5_000
              refute_receive {:trace, _, :call, {Ipse.Runner.Review, :consume, _}}, 100
              :erlang.trace(:all, false, [:call, :set_on_spawn])
              :erlang.trace_pattern({Ipse.Runner.Review, :consume, 3}, false, [:local])

              assert match?({:closed, {:error, _}}, result) or
                       match?({:closed, {:unknown, _}}, result)

              current = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)
              assert current["records"] === changed["records"]
              assert current["witness"]["root_sha256"] === changed["witness"]["root_sha256"]
              [path] = Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"]))
              id = Path.basename(path, ".jsonl")

              assert {:ok, %{"replayed" => false} = inspected} =
                       Management.operation(config, cwd, id)

              assert inspected["journal_status"] in ["refused", "unconfirmed"]

              IO.puts(
                "\nMANAGEMENT_FORGET_CHANGED_TARGET_ROOT_RECIPE_REFUSED #{mode} #{inspected["journal_status"]}"
              )
            else
              if rest == ["forget-owner-loss"] do
                before = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)

                config = %{
                  home: home,
                  approval: :ask,
                  approval_origin: :interactive,
                  headless: false
                }

                task =
                  Task.async(fn ->
                    Management.full_facts_forget_candidate(
                      config,
                      cwd,
                      key,
                      "Forget selected synthetic claim"
                    )
                  end)

                Process.unlink(task.pid)
                monitor = Process.monitor(task.pid)
                ready = Path.join(root, "management-review-input-ready")
                deadline = System.monotonic_time(:millisecond) + 8_000

                wait = fn wait ->
                  cond do
                    File.exists?(ready) ->
                      :ok

                    System.monotonic_time(:millisecond) >= deadline ->
                      :error

                    true ->
                      Process.sleep(10)
                      wait.(wait)
                  end
                end

                assert :ok = wait.(wait)
                Process.exit(task.pid, :kill)
                assert_receive {:DOWN, ^monitor, :process, _, _}, 5_000
                [path] = Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"]))
                id = Path.basename(path, ".jsonl")

                assert {:ok, lock} =
                         Ipse.Test.ManagementDisplayProbe.acquire(
                           Path.join([home, "knowledge-management", id <> ".lock"])
                         )

                assert :ok = Ipse.Runner.unlock(lock)

                assert {:ok,
                        %{
                          "journal_status" => "unconfirmed",
                          "control_status" => "unavailable",
                          "replayed" => false
                        }} = Management.operation(config, cwd, id)

                after_result = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)
                assert after_result["witness"]["root_sha256"] === before["witness"]["root_sha256"]
                IO.puts("\nMANAGEMENT_FORGET_OWNER_LOSS_UNCONFIRMED_NO_REPLAY")
              else
                if rest in [
                     ["forget-late"],
                     ["forget-uncertain"],
                     ["forget-intent-unknown"],
                     ["forget-settle-unknown"],
                     ["forget-close-unknown"]
                   ] do
                  before = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)

                  config = %{
                    home: home,
                    approval: :ask,
                    approval_origin: :interactive,
                    headless: false
                  }

                  assert {:closed, {:unknown, _}} =
                           Management.full_facts_forget_candidate(
                             config,
                             cwd,
                             key,
                             "Forget selected synthetic claim"
                           )

                  after_result = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)

                  if rest in [
                       ["forget-late"],
                       ["forget-settle-unknown"],
                       ["forget-close-unknown"]
                     ] do
                    assert after_result["records"] == [nil]

                    assert after_result["witness"]["root"]["generation"] >
                             before["witness"]["root"]["generation"]
                  else
                    assert after_result["records"] === before["records"]

                    assert after_result["witness"]["root_sha256"] ===
                             before["witness"]["root_sha256"]
                  end

                  [path] = Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"]))
                  id = Path.basename(path, ".jsonl")

                  expected_control =
                    cond do
                      rest == ["forget-intent-unknown"] -> "unavailable"
                      rest in [["forget-settle-unknown"], ["forget-close-unknown"]] -> "settled"
                      true -> "publishing"
                    end

                  expected_journal =
                    if(rest == ["forget-close-unknown"], do: "settled", else: "unconfirmed")

                  assert {:ok,
                          %{
                            "journal_status" => ^expected_journal,
                            "control_status" => ^expected_control,
                            "replayed" => false
                          }} = Management.operation(config, cwd, id)

                  IO.puts(
                    if(rest == ["forget-late"],
                      do: "\nMANAGEMENT_FORGET_LATE_COMMIT_UNKNOWN_NO_REPLAY",
                      else: "\nMANAGEMENT_FORGET_UNCERTAIN_NO_REPLAY"
                    )
                  )
                else
                  if rest in [["forget-cancel"], ["forget-race"], ["forget-expired"]] do
                    before = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)

                    config = %{
                      home: home,
                      approval: :ask,
                      approval_origin: :interactive,
                      headless: false
                    }

                    result =
                      if rest == ["forget-race"] do
                        task =
                          Task.async(fn ->
                            Management.full_facts_forget_candidate(
                              config,
                              cwd,
                              key,
                              "Forget selected synthetic claim"
                            )
                          end)

                        ready = Path.join(root, "management-review-input-ready")
                        deadline = System.monotonic_time(:millisecond) + 8_000

                        wait = fn wait ->
                          cond do
                            File.exists?(ready) ->
                              :ok

                            System.monotonic_time(:millisecond) >= deadline ->
                              :error

                            true ->
                              Process.sleep(10)
                              wait.(wait)
                          end
                        end

                        assert :ok = wait.(wait)

                        assert {:ok, %{"epoch" => 2}} =
                                 Consent.revoke(
                                   SemanticAdmission.control_root(home),
                                   binding["project_id"],
                                   1
                                 )

                        File.write!(Path.join(root, "management-review-race-complete"), "done")
                        Task.await(task, 10_000)
                      else
                        Management.full_facts_forget_candidate(
                          config,
                          cwd,
                          key,
                          "Forget selected synthetic claim"
                        )
                      end

                    assert {:closed, {:error, _}} = result
                    after_result = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)
                    assert after_result["records"] === before["records"]

                    assert after_result["witness"]["root_sha256"] ===
                             before["witness"]["root_sha256"]

                    [path] = Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"]))
                    id = Path.basename(path, ".jsonl")

                    assert {:ok, %{"journal_status" => "refused", "replayed" => false}} =
                             Management.operation(config, cwd, id)

                    IO.puts("\nMANAGEMENT_GENUINE_FORGET_REFUSED_UNCHANGED")
                  else
                    if rest == ["forget-effect"] do
                      before = Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)
                      assert [record] = before["records"]
                      assert is_map(record)

                      config = %{
                        home: home,
                        approval: :ask,
                        approval_origin: :interactive,
                        headless: false
                      }

                      assert {:error, :knowledge_management_refused} =
                               Management.full_facts_forget_candidate(
                                 %{config | approval: :deny},
                                 cwd,
                                 key,
                                 "denied"
                               )

                      assert {:error, :knowledge_management_refused} =
                               Management.full_facts_forget_candidate(
                                 %{config | headless: true},
                                 cwd,
                                 key,
                                 "headless"
                               )

                      assert Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"])) ==
                               []

                      assert {:closed, {:ok, result}} =
                               Management.full_facts_forget_candidate(
                                 config,
                                 cwd,
                                 key,
                                 "Forget selected synthetic claim"
                               )

                      assert result["storage_status"] == "settled"

                      assert result["receipt"]["publication"]["normalization"]["kind"] ==
                               "native_literal_forget"

                      assert {:ok, events} =
                               Ipse.Journal.load(
                                 result["journal_directory"],
                                 result["journal_id"]
                               )

                      assert [intent] =
                               Enum.filter(events, &(&1["type"] == "managed_lifecycle_intent"))

                      assert [final] =
                               Enum.filter(events, &(&1["type"] == "managed_lifecycle_result"))

                      assert intent["operation_id"] == result["operation_id"] and
                               final["status"] == "settled"

                      assert {:ok,
                              %{
                                "journal_status" => "settled",
                                "control_status" => "settled",
                                "replayed" => false
                              }} =
                               Management.operation(config, cwd, result["journal_id"])

                      after_result =
                        Ipse.Test.ManagementDisplayProbe.record(c.root, namespace, key)

                      assert after_result["records"] == [nil]

                      assert after_result["witness"]["root"]["generation"] >
                               before["witness"]["root"]["generation"]

                      IO.puts("\nMANAGEMENT_GENUINE_FORGET_SETTLED_AND_INSPECTED")
                    else
                      if rest in [
                           ["review"],
                           ["review-cancel"],
                           ["review-race"],
                           ["review-handles"],
                           ["review-expired"]
                         ] do
                        if rest == ["review-race"] do
                          task =
                            Task.async(fn ->
                              Management.full_facts_review_candidate(
                                %{home: home},
                                cwd,
                                key,
                                "Forget selected synthetic claim"
                              )
                            end)

                          ready = Path.join(root, "management-review-input-ready")
                          deadline = System.monotonic_time(:millisecond) + 8_000

                          wait = fn wait ->
                            cond do
                              File.exists?(ready) ->
                                :ok

                              System.monotonic_time(:millisecond) >= deadline ->
                                :error

                              true ->
                                Process.sleep(10)
                                wait.(wait)
                            end
                          end

                          assert :ok = wait.(wait)

                          for path <- [
                                Path.join([home, "project-identities", ".lock"]),
                                Path.join([
                                  SemanticAdmission.control_root(home),
                                  binding["project_id"],
                                  ".lock"
                                ]),
                                Path.join([
                                  SemanticAdmission.collection_root(home),
                                  namespace,
                                  ".lock"
                                ])
                              ] do
                            assert {:ok, lock} = Ipse.Runner.protected_lock(path)
                            assert :ok = Ipse.Runner.unlock(lock)
                          end

                          assert {:ok, %{"epoch" => 2}} =
                                   Consent.revoke(
                                     SemanticAdmission.control_root(home),
                                     binding["project_id"],
                                     1
                                   )

                          File.write!(Path.join(root, "management-review-race-complete"), "done")
                          assert {:closed, {:error, _}} = Task.await(task, 10_000)
                          IO.puts("\nMANAGEMENT_GENUINE_REVIEW_CHANGED_EPOCH_REFUSED")
                        else
                          if rest in [["review-cancel"], ["review-expired"]] do
                            assert {:closed, {:error, :native_review_refused}} =
                                     Management.full_facts_review_candidate(
                                       %{home: home},
                                       cwd,
                                       key,
                                       "Forget selected synthetic claim"
                                     )

                            IO.puts(
                              if(rest == ["review-expired"],
                                do: "\nMANAGEMENT_EXPIRED_REVIEW_REFUSED",
                                else: "\nMANAGEMENT_GENUINE_REVIEW_CANCELLED"
                              )
                            )
                          else
                            assert {:closed, {:ok, receipt}} =
                                     Management.full_facts_review_candidate(
                                       %{home: home},
                                       cwd,
                                       key,
                                       "Forget selected synthetic claim"
                                     )

                            assert receipt["kind"] == "native_review"
                            assert receipt["command"] == "forget"

                            IO.puts(
                              "\nMANAGEMENT_GENUINE_REVIEW_CONSUMED #{receipt["facts_sha256"]}"
                            )
                          end
                        end
                      else
                        assert {:closed, {:ok, receipt}} =
                                 Management.full_facts_display_candidate(
                                   %{home: home},
                                   cwd,
                                   key,
                                   "Forget selected synthetic claim"
                                 )

                        assert receipt.facts_sha256 =~ ~r/\A[0-9a-f]{64}\z/
                        assert receipt.display_sha256 =~ ~r/\A[0-9a-f]{64}\z/

                        IO.puts(
                          "\nMANAGEMENT_FULL_FACTS_DISPLAY_CLOSED #{receipt.facts_sha256} #{receipt.display_sha256} #{key}"
                        )
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
