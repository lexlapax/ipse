# The manifest carries expected fixture data, never publication authority.
defmodule Ipse.Test.ManagedClockLifecycle do
  import ExUnit.Assertions
  alias Ipse.{JSON, Journal, Usage}
  alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission}
  alias Ipse.Extension.Collection.{ManagedRetention, ObservedRead}
  alias Ipse.CLI.Knowledge.Management
  @day 86_400_000

  def seed(config, root, events, id) do
    admission = config.semantic_admission
    ordinary = intent(events, "ordinary")
    temporal = intent(events, "temporal")
    temporal_result = result(events, temporal["operation_id"])
    ordinary_result = result(events, ordinary["operation_id"])
    pin = admission["pin"]
    home = config.home
    directory = Path.join(home, "sessions")
    assert DynamicSupervisor.which_children(Ipse.Sessions) == []
    assert {:ok, _} = Ipse.Session.Saved.inspect_saved(directory, id)
    source = Path.join(directory, id <> ".jsonl")

    seed = %{
      "version" => 1,
      "session_id" => id,
      "source_sha256" => JSON.sha256(File.read!(source)),
      "binding" => admission["binding"],
      "namespace" => pin["namespace"],
      "recipe" => ordinary["facts"]["context"]["recipe"],
      "ordinary_old" => ordinary["facts"]["target"],
      "ordinary_current" => ordinary["facts"]["replacement"],
      "temporal_old" => temporal["facts"]["target"],
      "temporal_current" => temporal["facts"]["replacement"],
      "ordinary_deadline_ms" =>
        ordinary_result["outcome"]["publication"]["normalization"]["valid_until_ms"],
      "history_deadline_ms" =>
        temporal_result["outcome"]["publication"]["normalization"]["history_valid_until_ms"],
      "seed_wall_ms" => System.system_time(:millisecond)
    }

    assert seed["ordinary_deadline_ms"] > seed["seed_wall_ms"]
    assert seed["history_deadline_ms"] > seed["ordinary_deadline_ms"]
    path = Path.join(root, "clock-seed.json")
    File.write!(path, Jason.encode!(seed), [:exclusive])
    File.chmod!(path, 0o600)
    IO.puts("NATIVE_CLOCK_SEED_SHA256=" <> JSON.sha256(File.read!(path)))
  end

  def run(root, day) when day in [30, 91, 366] do
    home = Path.join(root, "home")
    cwd = Path.join(root, "work")
    System.put_env("IPSE_HOME", home)
    seed = root |> Path.join("clock-seed.json") |> File.read!() |> Jason.decode!()
    assert seed["version"] == 1
    assert {:ok, binding} = ProjectIdentity.existing(home, cwd)
    assert binding === seed["binding"]

    assert {:ok, control} =
             Consent.existing_snapshot(
               SemanticAdmission.control_root(home),
               binding["project_id"]
             )

    assert seed["recipe"] in Map.values(control["policy"]["settings"]["recipes"])
    now = System.system_time(:millisecond)
    assert now >= seed["seed_wall_ms"] + day * @day
    assert now < seed["seed_wall_ms"] + (day + 1) * @day
    config = config(root, home, cwd)

    context = %{
      root: SemanticAdmission.collection_root(home),
      home: home,
      cwd: cwd,
      binding: binding,
      namespace: seed["namespace"],
      recipe: seed["recipe"]
    }

    source = Path.join([home, "sessions", seed["session_id"] <> ".jsonl"])
    source_bytes = File.read!(source)
    assert JSON.sha256(source_bytes) == seed["source_sha256"]
    strict_saved(home, seed["session_id"])

    temporal_current = live(context, seed["temporal_current"])
    assert temporal_current["metadata"]["category"] == if(day == 30, do: "current", else: "pin")
    assert temporal_current["metadata"]["valid_until_ms"] == nil
    before = snapshot(context)
    assert {:error, _} = Management.expire(config, cwd, seed["temporal_current"]["key"])
    assert snapshot(context) === before

    expired =
      case day do
        30 ->
          assert now < seed["ordinary_deadline_ms"]
          ordinary = live(context, seed["ordinary_current"])
          assert ordinary["metadata"]["valid_until_ms"] == seed["ordinary_deadline_ms"]
          assert {:error, _} = Management.expire(config, cwd, seed["ordinary_current"]["key"])
          assert {:error, _} = Management.expire(config, cwd, seed["temporal_old"]["key"])
          assert snapshot(context) === before
          []

        91 ->
          assert now > seed["ordinary_deadline_ms"]
          assert now < seed["history_deadline_ms"]

          for key <- ~w(ordinary_current ordinary_old) do
            expire(config, context, seed[key]["key"], seed["ordinary_deadline_ms"])
          end

        366 ->
          assert now > seed["history_deadline_ms"]
          for key <- ~w(ordinary_current ordinary_old), do: absent(context, seed[key]["key"])
          [expire(config, context, seed["temporal_old"]["key"], seed["history_deadline_ms"])]
      end

    if day < 366 do
      history = history(context, seed["temporal_old"])
      assert history["metadata"]["valid_until_ms"] == seed["history_deadline_ms"]
      assert history["metadata"]["successor"]["key"] == seed["temporal_current"]["key"]
      assert ManagedRetention.eligible_history_metadata?(history["metadata"], now)
    else
      absent(context, seed["temporal_old"]["key"])
    end

    retained =
      if day == 30 do
        review_started_at = System.system_time(:millisecond)

        assert {:ok, result} =
                 Management.retain(config, cwd, seed["temporal_current"]["key"], %{
                   "kind" => "pin"
                 })

        review_finished_at = System.system_time(:millisecond)

        pinned = live(context, seed["temporal_current"])
        choice = pinned["metadata"]["choice"]
        assert pinned["metadata"]["category"] == "pin"
        assert choice["kind"] == "native_management"
        assert choice["policy"] == %{"kind" => "pin"}
        assert choice["observed_at_ms"] >= review_started_at
        assert choice["observed_at_ms"] <= review_finished_at

        assert Map.drop(pinned["metadata"], ~w(category choice)) ===
                 Map.drop(temporal_current["metadata"], ~w(category choice))

        [
          Map.put(
            settled_operation(config, context, result),
            "native_review_at_ms",
            choice["observed_at_ms"]
          )
        ]
      else
        assert live(context, seed["temporal_current"])["metadata"] ===
                 temporal_current["metadata"]

        []
      end

    assert File.read!(source) === source_bytes
    strict_saved(home, seed["session_id"])
    assert DynamicSupervisor.which_children(Ipse.Sessions) == []
    refute File.exists?(Path.join(root, "unexpected-model"))
    after_snapshot = snapshot(context)

    assert after_snapshot["generation"] ==
             before["generation"] + length(expired) + length(retained)

    report = %{
      "day" => day,
      "wall_ms" => now,
      "seed_sha256" => JSON.sha256(File.read!(Path.join(root, "clock-seed.json"))),
      "generation_before" => before["generation"],
      "generation_after" => after_snapshot["generation"],
      "expired_operations" => expired,
      "retention_operations" => retained,
      "source_sha256" => seed["source_sha256"],
      "actual_native_clock_component" => true,
      "annual_workload_qualification" => false
    }

    path = Path.join(root, "clock-day-#{day}.json")
    File.write!(path, Jason.encode!(report), [:exclusive])
    File.chmod!(path, 0o600)
    IO.puts("NATIVE_CLOCK_DAY_PASSED=#{day}")
  end

  defp expire(config, context, key, deadline) do
    before = snapshot(context)
    started_at = System.system_time(:millisecond)
    assert {:ok, result} = Management.expire(config, context.cwd, key)
    finished_at = System.system_time(:millisecond)
    assert result["storage_status"] == "settled"
    normalization = result["receipt"]["publication"]["normalization"]
    assert normalization["kind"] in ~w(managed_literal_expiry managed_literal_history_expiry)
    assert normalization["valid_until_ms"] == deadline
    assert normalization["checked_at_ms"] >= started_at
    assert normalization["checked_at_ms"] <= finished_at
    operation = settled_operation(config, context, result)
    absent(context, key)
    after_snapshot = snapshot(context)
    assert after_snapshot["generation"] == before["generation"] + 1
    assert after_snapshot["floor"] == after_snapshot["generation"]
    Map.put(operation, "checked_at_ms", normalization["checked_at_ms"])
  end

  defp settled_operation(config, context, result) do
    assert result["storage_status"] == "settled"
    assert {:ok, inspection} = Management.operation(config, context.cwd, result["journal_id"])
    assert inspection["journal_status"] == "settled"
    assert inspection["control_status"] == "settled"
    assert inspection["replayed"] == false
    journal = Path.join(result["journal_directory"], result["journal_id"] <> ".jsonl")
    bytes = File.read!(journal)
    assert {:ok, ^inspection} = Management.operation(config, context.cwd, result["journal_id"])
    assert File.read!(journal) === bytes
    Map.take(result, ~w(operation_id journal_id storage_status))
  end

  defp config(root, home, cwd) do
    client = %{
      workspace: cwd,
      home: home,
      auth_dir: Path.join(home, "auth"),
      operator_home: root,
      mcp_config: nil,
      base_url: nil,
      operator_questions: true,
      accept_edits: false,
      approval: :ask,
      approval_origin: :interactive,
      headless: false
    }

    assert {:ok, effective} =
             Ipse.Config.resolve(
               cwd,
               home,
               [config: Path.join(home, "config.json"), project_config: false],
               %{}
             )

    assert {:ok, config} = Ipse.Config.runtime(effective, client)
    config
  end

  defp snapshot(c) do
    assert {:ok, value} =
             Collection.execute(c.root, c.namespace, %{"op" => "snapshot"}, Usage.id())

    value
  end

  defp absent(c, key) do
    assert {:ok, %{"record" => nil}} =
             Collection.execute(c.root, c.namespace, %{"op" => "get", "key" => key}, Usage.id())
  end

  defp live(c, expected), do: observe(c, expected, :managed_record)
  defp history(c, expected), do: observe(c, expected, :managed_history)

  defp observe(c, expected, function) do
    assert {:ok, value} =
             ProjectIdentity.with_existing_domain_auth(
               c.home,
               c.cwd,
               c.binding,
               %{namespace: c.namespace, format: "managed-metadata-v3"},
               fn cap, catalog ->
                 apply(ObservedRead, function, [
                   c.root,
                   c.namespace,
                   %{"op" => "get_record", "key" => expected["key"]},
                   cap,
                   catalog,
                   c.recipe
                 ])
               end
             )

    assert value["observation"]["value"]["record"]["value"] === expected["value"]
    value
  end

  defp strict_saved(home, id) do
    assert {:ok, events} = Journal.load(Path.join(home, "sessions"), id)
    assert {:ok, _} = Ipse.Session.Saved.restore(events, id)

    assert {:ok, %{"release_claim" => "signed_release_claim"}} =
             Ipse.Session.Saved.inspect_saved(Path.join(home, "sessions"), id)
  end

  defp intent(events, mode) do
    [intent] =
      Enum.filter(
        events,
        &(&1["type"] == "managed_supersession_intent" and &1["facts"]["mode"] == mode)
      )

    intent
  end

  defp result(events, id) do
    [result] =
      Enum.filter(
        events,
        &(&1["type"] == "managed_supersession_result" and &1["operation_id"] == id)
      )

    assert result["status"] == "settled"
    result
  end
end
