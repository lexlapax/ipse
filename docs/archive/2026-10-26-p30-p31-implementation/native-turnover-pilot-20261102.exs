defmodule Ipse.Development.NativeTurnoverPilot do
  import ExUnit.Assertions
  alias Ipse.{JSON, Journal, Session, Usage}
  alias Ipse.CLI.Knowledge.Management
  alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission}
  alias Ipse.Extension.Collection.ObservedRead
  @day 86_400_000
  @actions [
    %{"day" => 2, "op" => "capture", "result" => "pilot/capture"},
    %{"day" => 2, "op" => "correct", "target" => "seed/4", "result" => "pilot/correct"},
    %{"day" => 2, "op" => "forget", "target" => "seed/5"},
    %{"day" => 2, "op" => "supersede", "target" => "seed/3", "result" => "pilot/current"},
    %{"day" => 92, "op" => "expire", "target" => "seed/4"},
    %{"day" => 92, "op" => "expire", "target" => "pilot/correct"},
    %{"day" => 368, "op" => "expire", "target" => "seed/3"}
  ]

  defmodule NoModel do
    def complete(config, _, _, _) do
      File.write!(Path.join(config.fixture_root, "unexpected-model"), "called", [:exclusive])
      raise "native turnover pilot attempted inference"
    end
  end

  def main(["--init", root, audit_path]) do
    assert Path.dirname(root) == "/tmp" and String.starts_with?(Path.basename(root), "ipse-native-seed-")
    seed = read(Path.join(root, "manifest.json"))
    assert seed["kind"] == "smoke" and seed["root"] == root
    assert not File.exists?(Path.join(root, "inflight.json"))
    audit = read(audit_path)
    assert audit["root"] == root and audit["verified_records"] == 7
    assert audit["unchanged_root"] and audit["unchanged_control"]
    assert fingerprint(audit["manifest"]["path"]) === audit["manifest"]
    assert fingerprint(audit["verified_rows"]["path"]) === audit["verified_rows"]
    Enum.each(seed["files"], &verify/1)
    reports = for i <- 1..length(seed["plan"]), do: read(Path.join(root, "checkpoints/report-#{i}.json"))
    for i <- 1..length(reports) do
      closed = read(Path.join(root, "checkpoints/closed-#{i}.json"))
      assert closed["index"] == i and closed["exit_code"] == 0
      verify(closed["report"])
      verify(closed["log"])
    end
    for report <- reports, source <- report["sources"], do: verify(source)
    records = Enum.reduce(reports, %{}, fn report, acc -> Map.merge(acc, report["new_records"]) end)
    rows = read(audit["verified_rows"]["path"])
    assert length(rows) == 7 and map_size(records) == 7
    for row <- rows do
      rec = Map.fetch!(records, Integer.to_string(row["number"]))
      assert row["key"] == rec["key"] and row["record_sha256"] == JSON.sha256(Collection.Migration.encode(rec["value"]))
    end
    dir = Path.join(root, "turnover-pilot")
    assert {:error, :enoent} = File.lstat(dir)
    File.mkdir!(dir)
    File.chmod!(dir, 0o700)
    File.cp!(__ENV__.file, Path.join(dir, "driver.exs"))
    files = [fingerprint(Path.join(dir, "driver.exs")), fingerprint(audit_path), audit["verified_rows"], audit["manifest"]] ++ seed["files"]
    save(Path.join(dir, "manifest.json"), %{"version" => 1, "root" => root, "seed_created_wall_ms" => seed["created_wall_ms"], "initial_snapshot" => audit["snapshot"], "initial_root_sha256" => audit["root_sha256"], "initial_control_sha256" => List.last(reports)["control_sha256"], "seed_sources" => Enum.flat_map(reports, & &1["sources"]), "records" => Map.new(records, fn {n, v} -> {"seed/" <> n, v} end), "actions" => @actions, "files" => files, "qualification" => false})
    IO.puts("NATIVE_TURNOVER_PILOT_INITIALIZED=#{root}")
  end

  def main(["--run", root]) do
    m = manifest(root)
    dir = Path.join(root, "turnover-pilot")
    assert not File.exists?(Path.join(dir, "inflight.json")), "inspect retained in-flight effect; never replay automatically"
    completed = closed(root, m)
    assert length(completed) < length(@actions)
    for i <- (length(completed) + 1)..length(@actions) do
      Enum.each(m["files"], &verify/1)
      action = Enum.at(@actions, i - 1)
      save(Path.join(dir, "inflight.json"), %{"index" => i, "manifest_sha256" => JSON.sha256(File.read!(Path.join(dir, "manifest.json")))})
      paths = Path.wildcard(Path.join(root, "stdio-runtime/*/ebin")) |> Enum.flat_map(&["-pa", &1])
      {output, status} = System.cmd(Path.join(root, "pty"), ["--assertion", System.find_executable("elixir"), "--erl", "+S 2:2 +C multi_time_warp"] ++ paths ++ [Path.join(dir, "driver.exs"), "--child", root, Integer.to_string(i)], stderr_to_stdout: true, env: [{"LD_PRELOAD", Path.join(root, "clock.so")}, {"IPSE_TEST_CLOCK_OFFSET_MS", Integer.to_string(action["day"] * @day)}, {"HOME", root}, {"IPSE_HOME", Path.join(root, "home")}, {"TMPDIR", root}])
      log = Path.join(dir, "segment-#{i}.log")
      File.write!(log, output, [:exclusive])
      File.chmod!(log, 0o600)
      assert status == 0, "pilot segment #{i} failed; retain in-flight and inspect #{log}"
      report = Path.join(dir, "report-#{i}.json")
      assert read(report)["index"] == i
      save(Path.join(dir, "closed-#{i}.json"), %{"index" => i, "exit_code" => status, "report" => fingerprint(report), "log" => fingerprint(log)})
      File.rm!(Path.join(dir, "inflight.json"))
      IO.puts("NATIVE_TURNOVER_PILOT_CLOSED=#{i} op=#{action["op"]} day=#{action["day"]}")
    end
  end

  def main(["--child", root, index]) do
    i = String.to_integer(index)
    m = manifest(root)
    dir = Path.join(root, "turnover-pilot")
    assert read(Path.join(dir, "inflight.json"))["index"] == i
    Enum.each(m["files"], &verify/1)
    for source <- m["seed_sources"], do: verify(source)
    prior = closed(root, m)
    assert length(prior) == i - 1
    action = Enum.at(@actions, i - 1)
    assert System.get_env("IPSE_TEST_CLOCK_OFFSET_MS") == Integer.to_string(action["day"] * @day)
    assert System.system_time(:millisecond) >= m["seed_created_wall_ms"] + action["day"] * @day
    Code.require_file(Path.join(root, "runtime/managed_clock_lifecycle.exs"))
    {:ok, _} = Application.ensure_all_started(:ipse)
    Ipse.Test.ManagedClockLifecycle.check_stdio_clock(root)
    home = Path.join(root, "home")
    cwd = Path.join(root, "work")
    for key <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS), do: System.delete_env(key)
    client = %{workspace: cwd, home: home, auth_dir: Path.join(home, "auth"), operator_home: root, mcp_config: nil, base_url: nil, operator_questions: true, accept_edits: false, approval: :ask, approval_origin: :interactive, headless: false}
    {:ok, effective} = Ipse.Config.resolve(cwd, home, [config: Path.join(home, "config.json"), project_config: false], %{})
    {:ok, config} = Ipse.Config.runtime(effective, client)
    config = Map.merge(config, %{provider_module: NoModel, fixture_root: root})
    {:ok, binding} = ProjectIdentity.existing(home, cwd)
    {:ok, ns} = Ipse.Extension.SemanticConsent.namespace(binding["project_id"], "knowledge")
    collection = SemanticAdmission.collection_root(home)
    control_root = SemanticAdmission.control_root(home)
    {:ok, control} = Consent.existing_snapshot(control_root, binding["project_id"])
    {:ok, observed} = ObservedRead.read(collection, ns, %{"op" => "snapshot"})
    expected_snapshot = if prior == [], do: m["initial_snapshot"], else: List.last(prior)["snapshot"]
    expected_root = if prior == [], do: m["initial_root_sha256"], else: List.last(prior)["root_sha256"]
    expected_control = if prior == [], do: m["initial_control_sha256"], else: List.last(prior)["control_sha256"]
    assert observed["value"] === expected_snapshot and observed["witness"]["root_sha256"] == expected_root
    assert JSON.digest([control]) == expected_control
    records = Enum.reduce(prior, m["records"], fn r, acc -> if r["new_record"], do: Map.put(acc, r["result"], r["new_record"]), else: acc end)
    target = if action["target"], do: Map.fetch!(records, action["target"])
    new_record = effect(action, target, config, cwd, root)
    {:ok, after_snapshot} = ObservedRead.read(collection, ns, %{"op" => "snapshot"})
    assert after_snapshot["value"]["generation"] == observed["value"]["generation"] + 1
    {:ok, after_control} = Consent.existing_snapshot(control_root, binding["project_id"])
    assert after_control["sequence"] == control["sequence"] + 1
    for source <- m["seed_sources"], do: verify(source)
    assert not File.exists?(Path.join(root, "unexpected-model"))
    save(Path.join(dir, "report-#{i}.json"), %{"index" => i, "action" => action, "result" => action["result"], "new_record" => new_record, "snapshot" => after_snapshot["value"], "root_sha256" => after_snapshot["witness"]["root_sha256"], "control_sha256" => JSON.digest([after_control]), "qualification" => false})
  end

  defp effect(%{"op" => op}, target, config, cwd, root) when op in ~w(capture correct supersede) do
    dir = Path.join(config.home, "sessions")
    {:ok, session} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, config: config, cwd: cwd, state_dir: dir, subscriber: self()})
    id = Session.info(session).id
    {:ok, channel} = Session.open_input_channel(session, self())
    command = case op do
      "capture" -> "/remember ordinary Pilot continuation statement"
      "correct" -> "/correct " <> target["key"] <> " Pilot corrected continuation statement"
      "supersede" -> "/supersede " <> target["key"] <> " Pilot replacement current statement"
    end
    File.write!(Path.join(root, "supersession-input-1"), command)
    IO.write("IPSE_SUPERSESSION_READ_1> ")
    assert {:ok, ^command, witness} = Session.observe_channel(session, channel, %{"kind" => "prompt"}, 30_000)
    {:ok, ticket} = Session.stage_input(session, channel, command, witness)
    {:ok, %{"render_id" => render}} = Session.prepare_assertion(session, channel, command, ticket)
    {:ok, input, witnessed} = Session.observe_channel(session, channel, %{"kind" => "assertion", "render_id" => render}, 30_000)
    :ok = Session.accept_assertion_observed(session, channel, render, input, witnessed)
    assert_receive {:ipse, ^session, {:done, :ok}}, 30_000
    :ok = Session.close_confirmed(session)
    {:ok, events} = Journal.load(dir, id)
    {:ok, _} = Session.Saved.restore(events, id)
    {:ok, %{"release_claim" => "signed_release_claim"}} = Session.Saved.inspect_saved(dir, id)
    refute Enum.any?(events, &(&1["type"] in ~w(request_admitted inference_dispatch_intent)))
    if op == "capture" do
      [event] = Enum.filter(events, &(&1["type"] == "extension_action_result" and get_in(&1, ["request", "op"]) == "collection.managed" and get_in(&1, ["outcome", "status"]) == "ok"))
      [change] = event["request"]["request"]["changes"]
      %{"key" => change["key"], "value" => change["value"]}
    else
      [intent] = Enum.filter(events, &(&1["type"] == "managed_supersession_intent"))
      [result] = Enum.filter(events, &(&1["type"] == "managed_supersession_result" and &1["operation_id"] == intent["operation_id"]))
      assert result["status"] == "settled" and intent["facts"]["target"]["key"] == target["key"]
      intent["facts"]["replacement"]
    end
  end
  defp effect(%{"op" => op}, target, config, cwd, _root) when op in ~w(forget expire) do
    result = if op == "forget", do: Management.forget(config, cwd, target["key"]), else: Management.expire(config, cwd, target["key"])
    assert {:ok, value} = result
    assert value["storage_status"] == "settled"
    assert {:ok, %{"journal_status" => "settled", "control_status" => "settled", "replayed" => false}} = Management.operation(config, cwd, value["journal_id"])
    nil
  end
  defp manifest(root) do
    m = read(Path.join(root, "turnover-pilot/manifest.json"))
    assert m["root"] == root and m["actions"] === @actions
    m
  end
  defp closed(root, _m) do
    dir = Path.join(root, "turnover-pilot")
    Enum.reduce_while(1..length(@actions), [], fn i, acc ->
      path = Path.join(dir, "closed-#{i}.json")
      if File.exists?(path) do
        c = read(path)
        assert c["index"] == i and c["exit_code"] == 0
        verify(c["report"])
        verify(c["log"])
        {:cont, acc ++ [read(c["report"]["path"])]}
      else
        assert length(Path.wildcard(Path.join(dir, "closed-*.json"))) == length(acc)
        {:halt, acc}
      end
    end)
  end
  defp fingerprint(path), do: %{"path" => path, "bytes" => File.stat!(path).size, "sha256" => JSON.sha256(File.read!(path))}
  defp verify(row), do: assert(fingerprint(row["path"]) === row)
  defp read(path), do: path |> File.read!() |> Jason.decode!()
  defp save(path, value) do
    File.write!(path, Jason.encode!(value) <> "\n", [:exclusive])
    File.chmod!(path, 0o600)
  end
end
Ipse.Development.NativeTurnoverPilot.main(System.argv())
