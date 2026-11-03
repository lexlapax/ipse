ExUnit.start(autorun: false)

defmodule Ipse.Development.FreshPopulatedProbe do
  import ExUnit.Assertions
  alias Ipse.{JSON, Journal, Session}
  alias Ipse.Extension.{Consent, Mode, ProjectIdentity, SemanticAdmission, SemanticConsent}
  alias Ipse.Extension.Collection.ObservedRead
  @root "/dev/shm/ipse-native-seed-recall-d739-20261103-01"
  @evidence "/dev/shm/ipse-recall-seed-populated-d739-20261103-01"
  @output "/dev/shm/ipse-fresh-recall-probe-d739-20261103-02"
  @attempt @output <> "/attempt.json"
  @claim @output <> "/child-claim.json"
  @day 86_400_000
  @max_file 33_554_432
  @max_total 536_870_912
  @max_files 10_000

  def main(["--run", output]) do
    assert output == @output
    assert {:error, :enoent} = File.lstat(@output)
    File.mkdir!(@output)
    File.chmod!(@output, 0o700)
    private_output!()
    assert File.ls!(@output) == []
    File.cp!(__ENV__.file, Path.join(output, "probe.exs"))
    File.cp!(Path.join(__DIR__, "provider.exs"), Path.join(output, "provider.exs"))
    for name <- ~w(probe.exs provider.exs), do: File.chmod!(Path.join(output, name), 0o600)
    {manifest, seed, final} = seed!()
    before = inventory!(@root)
    evidence_before = inventory!(@evidence)
    save!(Path.join(output, "before-files.json"), before)
    save!(Path.join(output, "before-evidence.json"), evidence_before)
    save!(Path.join(output, "intent.json"), %{
      "version" => 1, "kind" => "fresh_populated_read_only_probe",
      "seed_intent_sha256" => hash_file(Path.join(@evidence, "seed-intent.json")),
      "seed_result_sha256" => hash_file(Path.join(@evidence, "seed-result.json")),
      "seed_manifest_sha256" => hash_file(Path.join(@root, "manifest.json")),
      "fixture_port" => seed["fixture_port"], "final_checkpoint_index" => final["index"],
      "offset_ms" => List.last(manifest["plan"])["day"] * @day,
      "before_files_sha256" => hash_file(Path.join(output, "before-files.json")),
      "before_evidence_sha256" => hash_file(Path.join(output, "before-evidence.json")),
      "driver_sha256" => hash_file(Path.join(output, "probe.exs")),
      "provider_sha256" => hash_file(Path.join(output, "provider.exs")), "qualification" => false
    })
    save!(@attempt, %{"version" => 1, "output" => output,
      "intent_sha256" => hash_file(Path.join(output, "intent.json"))})
    paths = Path.wildcard(Path.join(@root, "stdio-runtime/*/ebin")) |> Enum.flat_map(&["-pa", &1])
    env = [{"IPSE_HOME", Path.join(@root, "home")}, {"TMPDIR", output},
      {"LD_PRELOAD", Path.join(@root, "clock.so")},
      {"IPSE_TEST_CLOCK_OFFSET_MS", Integer.to_string(List.last(manifest["plan"])["day"] * @day)}]
    {log, status} = child_command(output, paths, env, "--child")
    child_log_saved = safely(fn -> write!(Path.join(output, "child.log"), log) end) == {:ok, :ok}
    {verify_log, verify_status} = child_command(output, paths, env, "--verify")
    verify_log_saved = safely(fn -> write!(Path.join(output, "verify.log"), verify_log) end) == {:ok, :ok}
    files_result = safely(fn -> inventory!(@root) end)
    evidence_result = safely(fn -> inventory!(@evidence) end)
    files_saved = case files_result do
      {:ok, files} -> safely(fn -> save!(Path.join(output, "after-files.json"), files) end) == {:ok, :ok}
      _ -> false
    end
    evidence_saved = case evidence_result do
      {:ok, files} -> safely(fn -> save!(Path.join(output, "after-evidence.json"), files) end) == {:ok, :ok}
      _ -> false
    end
    {changed, added, inventory_ok} = case files_result do
      {:ok, after_files} ->
        changed = for {path, item} <- before, after_files[path] !== item, do: path
        {Enum.sort(changed), Enum.sort(Map.keys(after_files) -- Map.keys(before)), true}
      _ -> {[], [], false}
    end
    evidence_ok = evidence_result == {:ok, evidence_before}
    state_ok = with {:ok, before_state} <- safely(fn -> read(Path.join(output, "before-state.json")) end),
                    {:ok, after_state} <- safely(fn -> read(Path.join(output, "after-state.json")) end),
                    do: before_state === after_state, else: (_ -> false)
    turn = safely(fn -> read(Path.join(output, "turn-intent.json")) end)
    additions_ok = case turn do
      {:ok, %{"session_id" => id}} when is_binary(id) ->
        Regex.match?(~r/\A[0-9a-f]{32}\z/, id) and
          added == Enum.sort(["home/sessions/#{id}.jsonl", "home/sessions/#{id}.lock"])
      _ -> added == []
    end
    verified = inventory_ok and changed == [] and evidence_ok and state_ok and additions_ok and
      verify_status == 0 and child_log_saved and verify_log_saved and files_saved and evidence_saved
    save!(Path.join(output, "comparison.json"), %{"version" => 1,
      "changed_or_missing" => changed, "added" => added,
      "inventory_confirmed" => inventory_ok, "seed_evidence_unchanged" => evidence_ok,
      "child_log_saved" => child_log_saved, "verify_log_saved" => verify_log_saved,
      "files_saved" => files_saved, "evidence_saved" => evidence_saved,
      "root_control_unchanged" => state_ok, "allowed_additions" => additions_ok,
      "child_exit_code" => status, "verification_exit_code" => verify_status,
      "outcome" => if(verified and status == 0, do: "pending_result_validation", else: "unknown"),
      "qualification" => false})
    assert verified, "preservation or cleanup unconfirmed; retain unknown without retry"
    assert status == 0, "probe stopped; preserve unknown without retry"
    result = read(Path.join(output, "result.json"))
    assert {:ok, turn_intent} = turn
    assert turn_intent["session_id"] == result["session_id"]
    save!(Path.join(output, "complete.json"), %{"version" => 1,
      "result_sha256" => hash_file(Path.join(output, "result.json")),
      "comparison_sha256" => hash_file(Path.join(output, "comparison.json")), "qualification" => false})
  end

  def main(["--child", output]) do
    assert output == @output
    private_output!()
    for name <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS IPSE_SUBAGENT_CONCURRENCY IPSE_MAX_STEPS IPSE_CONTEXT_BYTES IPSE_COMPACT IPSE_TIMEOUT_MS IPSE_MAX_OUTPUT_TOKENS IPSE_OBSERVABILITY IPSE_RUNNER_PATH),
      do: System.delete_env(name)
    attempt = read(@attempt)
    assert attempt["version"] == 1 and attempt["output"] == output
    assert attempt["intent_sha256"] == hash_file(Path.join(output, "intent.json"))
    save!(@claim, %{"version" => 1, "output" => output,
      "attempt_sha256" => hash_file(@attempt)})
    intent = read(Path.join(output, "intent.json"))
    assert intent["kind"] == "fresh_populated_read_only_probe"
    assert intent["driver_sha256"] == hash_file(__ENV__.file)
    assert intent["provider_sha256"] == hash_file(Path.join(output, "provider.exs"))
    assert intent["before_files_sha256"] == hash_file(Path.join(output, "before-files.json"))
    assert intent["before_evidence_sha256"] == hash_file(Path.join(output, "before-evidence.json"))
    assert inventory!(@root) === read(Path.join(output, "before-files.json"))
    assert inventory!(@evidence) === read(Path.join(output, "before-evidence.json"))
    {manifest, seed, final} = seed!()
    assert seed["fixture_port"] === intent["fixture_port"]
    assert intent["offset_ms"] == List.last(manifest["plan"])["day"] * @day
    assert System.get_env("IPSE_TEST_CLOCK_OFFSET_MS") == Integer.to_string(intent["offset_ms"])
    for module <- [Ipse.Runner, Ipse.Session.ManagedUse, Ipse.Extension.Collection.ObservedRead] do
      assert {:module, ^module} = Code.ensure_loaded(module)
      actual = module |> :code.which() |> List.to_string() |> Path.expand()
      assert actual == Path.join([@root, "stdio-runtime/ipse/ebin", Atom.to_string(module) <> ".beam"])
    end
    Code.require_file(Path.join(output, "provider.exs"))
    {:ok, _} = Application.ensure_all_started(:ipse)
    home = Path.join(@root, "home")
    cwd = Path.join(@root, "work")
    dir = Path.join(home, "sessions")
    verify_idle!(dir)
    no_pending!()
    {:ok, binding} = ProjectIdentity.existing(home, cwd)
    {:ok, namespace} = SemanticConsent.namespace(binding["project_id"], "knowledge")
    collection = SemanticAdmission.collection_root(home)
    control_root = SemanticAdmission.control_root(home)
    {:ok, before_root} = ObservedRead.read(collection, namespace, %{"op" => "snapshot"})
    {:ok, before_control} = Consent.existing_snapshot(control_root, binding["project_id"])
    assert before_root["value"] === final["snapshot"]
    assert JSON.digest([before_control]) === final["control_sha256"]
    assert Enum.all?(before_control["operations"], fn {_, row} -> row["status"] == "settled" end)
    assert Enum.all?(before_control["compacted"], fn {_, row} -> Enum.at(row, 4) == "settled" end)
    save!(Path.join(output, "before-state.json"), state_receipt(before_root, before_control))
    client = %{workspace: cwd, home: home, auth_dir: Path.join(home, "auth"), operator_home: @root,
      mcp_config: nil, base_url: nil, operator_questions: true, accept_edits: false,
      approval: :ask, approval_origin: :interactive, headless: false}
    {:ok, effective} = Ipse.Config.resolve(cwd, home, [config: Path.join(home, "config.json"), project_config: false], %{})
    {:ok, config} = Ipse.Config.runtime(effective, client)
    config = Map.merge(config, %{execution_mode: :read_only, enclosing_mode: :read_only})
    {:ok, mode} = Mode.capture(config)
    assert mode["ceiling"] == "read_only" and mode["enclosing_ceiling"] == "read_only"
    assert :ok = Mode.knowledge(mode, "collection.read")
    assert {:error, :knowledge_mode_denied} = Mode.knowledge(mode, "collection.publish")
    assert :deny = Mode.ordinary(mode, true)
    assert config.provider == :ollama and config.model == "synthetic"
    assert config.base_url == "http://127.0.0.1:#{seed["fixture_port"]}"
    assert config.timeout_ms == 15_000
    assert config.max_steps in 1..30
    assert Ipse.Extension.Actions.limit() == 16
    provider = Ipse.Development.SyntheticOllamaRetained
    {:ok, server} = provider.start(seed["fixture_port"], self())
    try do
      {:ok, session} = DynamicSupervisor.start_child(Ipse.Sessions,
        {Session, config: config, cwd: cwd, state_dir: dir, subscriber: self(), owner: self()})
      id = Session.info(session).id
      refute Map.has_key?(read(Path.join(output, "before-files.json")), "home/sessions/#{id}.jsonl")
      live = :sys.get_state(session).config
      assert get_in(live, [:semantic_admission, "status"]) == "active"
      knowledge = Enum.find(live.extensions, &(&1.identity["instance"] == "knowledge"))
      assert is_map(knowledge) and Ipse.Extension.Actions.limit(knowledge.identity) == 528
      prompt = provider.prompt()
      save!(Path.join(output, "turn-intent.json"), %{"version" => 1, "session_id" => id,
        "prompt_sha256" => JSON.sha256(prompt)})
      started = System.monotonic_time(:microsecond)
      assert :ok = Session.prompt(session, prompt)
      {request_sha, request_bytes, number, visible} =
        await_turn!(session, System.monotonic_time(:millisecond) + 150_000, nil, false, "")
      assert visible == "Synthetic diagnostic response."
      audit = read(Path.join(@evidence, "ipse-native-seed-audit-#{JSON.sha256(@root)}.json"))
      rows = read(audit["verified_rows"]["path"])
      [row] = Enum.filter(rows, &(&1["number"] == number))
      assert row["metadata"]["category"] in ~w(pin preference current ordinary)
      deadline = row["metadata"]["valid_until_ms"]
      assert is_nil(deadline) or System.system_time(:millisecond) < deadline
      assert :ok = Task.await(server, 30_000)
      assert :ok = Session.close_confirmed(session)
      assert {:ok, events} = Journal.load(dir, id)
      assert {:ok, _} = Session.Saved.restore(events, id)
      inputs = Enum.filter(events, &(&1["type"] == "input_received"))
      dispatches = Enum.filter(events, &(&1["type"] == "inference_dispatch_intent"))
      assert length(inputs) == 1 and length(dispatches) == 1
      assert hd(inputs)["turn_id"] == hd(dispatches)["turn_id"]
      assert hd(inputs)["text_sha256"] == JSON.sha256(prompt)
      assert JSON.sha256?(request_sha) and request_bytes in 1..2_097_152
      {:ok, after_root} = ObservedRead.read(collection, namespace, %{"op" => "snapshot"})
      {:ok, after_control} = Consent.existing_snapshot(control_root, binding["project_id"])
      assert before_root === after_root and before_control === after_control
      no_pending!()
      save!(Path.join(output, "result.json"), %{"version" => 1, "session_id" => id,
        "turn_id" => hd(inputs)["turn_id"], "request_sha256" => request_sha,
        "request_bytes" => request_bytes, "verified_seeded_note_number" => number,
        "visible_response_sha256" => JSON.sha256(visible),
        "elapsed_us" => System.monotonic_time(:microsecond) - started,
        "execution_mode" => mode, "qualification" => false})
    after
      if Process.alive?(server.pid), do: Task.shutdown(server, :brutal_kill)
    end
  end

  def main(["--verify", output]) do
    assert output == @output
    private_output!()
    {:ok, _} = Application.ensure_all_started(:ipse)
    home = Path.join(@root, "home")
    cwd = Path.join(@root, "work")
    verify_idle!(Path.join(home, "sessions"))
    {:ok, binding} = ProjectIdentity.existing(home, cwd)
    {:ok, namespace} = SemanticConsent.namespace(binding["project_id"], "knowledge")
    {:ok, root} = ObservedRead.read(SemanticAdmission.collection_root(home), namespace, %{"op" => "snapshot"})
    {:ok, control} = Consent.existing_snapshot(SemanticAdmission.control_root(home), binding["project_id"])
    save!(Path.join(output, "after-state.json"), state_receipt(root, control))
  end

  defp seed! do
    intent = read(Path.join(@evidence, "seed-intent.json"))
    result = read(Path.join(@evidence, "seed-result.json"))
    post = read(Path.join(@evidence, "post-input-check.json"))
    assert intent["kind"] == "fresh_synthetic_population_only" and intent["root"] == @root
    assert intent["source_commit"] == "d739f4020b73a8784dc74079c7ed6eedf58ead2b"
    assert intent["records"] == 2000 and intent["fixture_port"] in 1..65_535
    assert result["status"] == "seed_audited" and result["root"] == @root
    assert result["verified_records"] == 2000 and result["fixture_port"] == intent["fixture_port"]
    assert result["intent_sha256"] == hash_file(Path.join(@evidence, "seed-intent.json"))
    assert post["manifests_and_membership_verified"] == true
    assert not File.exists?(Path.join(@root, "inflight.json"))
    manifest = read(Path.join(@root, "manifest.json"))
    assert result["seed_manifest_sha256"] == hash_file(Path.join(@root, "manifest.json"))
    assert manifest["root"] == @root and manifest["kind"] == "initial"
    assert manifest["fixture_port"] == intent["fixture_port"] and is_list(manifest["plan"])
    audit = Path.join(@evidence, "ipse-native-seed-audit-#{JSON.sha256(@root)}.json")
    assert result["seed_audit_sha256"] == hash_file(audit)
    summary = read(audit)
    assert summary["verified_records"] == 2000 and summary["unchanged_root"] and summary["unchanged_control"]
    rows = summary["verified_rows"]
    assert is_map(rows) and is_binary(rows["path"]) and String.starts_with?(rows["path"], @evidence <> "/")
    bytes = File.read!(rows["path"])
    assert byte_size(bytes) == rows["bytes"] and JSON.sha256(bytes) == rows["sha256"]
    assert length(Jason.decode!(bytes)) == 2000
    for row <- manifest["files"], do: fingerprint!(row)
    count = length(manifest["plan"])
    assert count > 0
    reports = for index <- 1..count do
      closed = read(Path.join(@root, "checkpoints/closed-#{index}.json"))
      assert closed["index"] == index and closed["exit_code"] == 0
      for key <- ~w(report log), do: fingerprint!(closed[key])
      report = read(closed["report"]["path"])
      assert report["index"] == index and report["closed"] == true
      for source <- report["sources"], do: fingerprint!(source)
      report
    end
    assert length(Path.wildcard(Path.join(@root, "checkpoints/closed-*.json"))) == count
    final = List.last(reports)
    assert final["initial_seed_complete"] == true and final["public_records"] == 2000
    identity = intent["candidate_identity"]
    for module <- ~w(Elixir.Ipse.Session.ManagedUse Elixir.Ipse.Extension.Collection.ObservedRead) do
      assert hash_file(Path.join([@root, "stdio-runtime/ipse/ebin", module <> ".beam"])) == identity["module_sha256"][module]
    end
    assert hash_file(Path.join(@root, "stdio-runtime/ipse/priv/ipse-runner")) == identity["helper_sha256"]
    clock = read(Path.join(@evidence, "clock-runtime-identity.json"))
    recorded = read(Path.join(@root, "clock-stdio-runtime.json"))
    assert clock["production_source_sha256"] == identity["runner_source_sha256"]
    for key <- ~w(production_source_sha256 instrumented_source_sha256 runner_beam_sha256 helper_sha256),
      do: assert(clock[key] == recorded[key])
    assert clock["original_runner_beam_sha256"] == identity["module_sha256"]["Elixir.Ipse.Runner"]
    assert clock["instrumented_source_sha256"] == hash_file(Path.join(@root, "stdio-runtime/ipse/lib/ipse/runner.ex"))
    assert clock["runner_beam_sha256"] == hash_file(Path.join(@root, "stdio-runtime/ipse/ebin/Elixir.Ipse.Runner.beam"))
    assert clock["helper_sha256"] == identity["helper_sha256"]
    {manifest, intent, final}
  end

  defp private_output! do
    assert {:ok, uid} = Ipse.Runner.protected_current_uid()
    assert {:ok, stat} = File.lstat(@output)
    assert stat.type == :directory and stat.uid == uid
    assert Bitwise.band(stat.mode, 0o7777) == 0o700
    :ok
  end

  defp fingerprint!(row) do
    path = row["path"]
    assert is_binary(path) and String.starts_with?(path, @root <> "/")
    bytes = File.read!(path)
    assert byte_size(bytes) == row["bytes"] and JSON.sha256(bytes) == row["sha256"]
  end
  defp verify_idle!(dir) do
    journals = Path.wildcard(Path.join(dir, "*.jsonl"))
    locks = Path.wildcard(Path.join(dir, "*.lock"))
    assert journals != [] and Enum.all?(journals, &((Path.rootname(&1, ".jsonl") <> ".lock") in locks))
    for lock <- locks do
      assert File.lstat!(lock).type == :regular
      assert {:ok, port} = Ipse.Runner.protected_lock(lock)
      assert :ok = Ipse.Runner.unlock(port)
    end
  end
  defp no_pending! do
    home = Path.join(@root, "home")
    assert Path.wildcard(Path.join(home, "**/.pending-*"), match_dot: true) == []
    assert Path.wildcard(Path.join(home, "**/.metadata-active"), match_dot: true) == []
    assert not File.exists?(Path.join(@root, "unexpected-model"))
  end
  defp await_turn!(_session, _deadline, {digest, bytes, number}, true, text),
    do: {digest, bytes, number, text}
  defp await_turn!(session, deadline, request, done, text) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)
    receive do
      {:retained_request, digest, bytes, number} when is_nil(request) ->
        await_turn!(session, min(deadline, System.monotonic_time(:millisecond) + 30_000),
          {digest, bytes, number}, done, text)
      {:ipse, ^session, {:text, chunk}} when is_binary(chunk) ->
        assert byte_size(text) + byte_size(chunk) <= 1024
        await_turn!(session, deadline, request, done, text <> chunk)
      {:ipse, ^session, {:done, :ok}} -> await_turn!(session, deadline, request, true, text)
      {:ipse, ^session, {:done, status}} -> flunk("new Session failed: #{inspect(status)}")
    after
      remaining -> flunk("diagnostic deadline expired; inspect without retry")
    end
  end
  defp child_command(output, paths, env, phase) do
    case safely(fn ->
      System.cmd(System.find_executable("elixir"),
        ["--erl", "+S 2:2 +C multi_time_warp"] ++ paths ++ [Path.join(output, "probe.exs"), phase, output],
        stderr_to_stdout: true, env: env)
    end) do
      {:ok, result} -> result
      _ -> {"child launch unavailable; outcome unknown\n", "unknown"}
    end
  end
  defp safely(fun) do
    try do
      {:ok, fun.()}
    rescue
      _ -> {:error, :unavailable}
    catch
      _, _ -> {:error, :unavailable}
    end
  end
  defp state_receipt(root, control), do: %{"root" => root, "control_sha256" => JSON.digest([control])}
  defp inventory!(root) do
    paths = walk!(root, "")
    assert length(paths) <= @max_files
    entries = Enum.map(paths, fn relative ->
      path = Path.join(root, relative)
      stat = File.lstat!(path)
      assert stat.type == :regular and stat.size <= @max_file
      bytes = File.read!(path)
      assert byte_size(bytes) == stat.size
      {relative, %{"bytes" => stat.size, "sha256" => JSON.sha256(bytes), "inode" => stat.inode,
        "major_device" => stat.major_device, "minor_device" => stat.minor_device,
        "uid" => stat.uid, "mode" => stat.mode}}
    end)
    assert Enum.sum(Enum.map(entries, fn {_, value} -> value["bytes"] end)) <= @max_total
    Map.new(entries)
  end
  defp walk!(root, relative) do
    Path.join(root, relative) |> File.ls!() |> Enum.sort() |> Enum.flat_map(fn name ->
      child = Path.join(relative, name)
      case File.lstat!(Path.join(root, child)).type do
        :directory -> walk!(root, child)
        :regular -> [child]
        _ -> flunk("non-regular seed entry; refuse probe")
      end
    end)
  end
  defp hash_file(path), do: path |> File.read!() |> JSON.sha256()
  defp read(path), do: path |> File.read!() |> Jason.decode!()
  defp save!(path, value), do: write!(path, Jason.encode!(value) <> "\n")
  defp write!(path, bytes) do
    {:ok, file} = :file.open(String.to_charlist(path), [:write, :binary, :exclusive])
    :ok = :file.write(file, bytes)
    :ok = File.chmod(path, 0o600)
    :ok = :file.sync(file)
    :ok = :file.close(file)
    :ok = Ipse.Runner.protected_sync_directory(Path.dirname(path))
  end
end

Ipse.Development.FreshPopulatedProbe.main(System.argv())
