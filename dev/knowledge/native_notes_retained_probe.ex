defmodule Ipse.Development.NativeNotesRetainedProbe do
  @moduledoc false
  import ExUnit.Assertions
  alias Ipse.{JSON, Journal, Session}
  alias Ipse.Extension.{Consent, Mode, ProjectIdentity, SemanticAdmission, SemanticConsent}
  alias Ipse.Extension.Collection.ObservedRead

  @root "/tmp/ipse-native-seed-integrated-full-520e8f45f283205ed1d526e3669abdde"
  @failed_session "138f473c4c3a1e087eed76a68522586f"
  @failed_turn "a49a24e49e67867a2724775d792a4d5e"
  @intent_sha "160c817c22b6dfe9f5b18f5bd0a98342df57a9f1a8450c68e7d3cc2dc5537e92"
  @inflight_sha "0afcd40033d8c18ed17b6e27580b4b14be361d6fc7a4c69a24d85dcd069edf25"
  @journal_sha "0d9d113121dd90bd13dbe13ba19aa014215afbf6b3ff81bbd0613d2fa5ab3248"
  @seed_audit "/tmp/ipse-native-seed-audit-c58d10b45909e624386a2d6d62c33100bfa9ceacfd223ac590cba9d27c055350.json"
  @seed_audit_sha "0f75b490537985d8a5b077a8bfba2a39d7ad9626af41c989211aa0457ef74d0e"
  @maximum_files 10_000
  @maximum_file_bytes 33_554_432
  @maximum_total_bytes 536_870_912

  def main(["--run", root, output]) do
    assert root == @root and Path.expand(root) == root
    assert Path.type(output) == :absolute and Path.dirname(output) == "/tmp"
    assert String.starts_with?(Path.basename(output), "ipse-retained-readonly-")
    assert {:error, :enoent} = File.lstat(output)
    assert File.lstat!(root).type == :directory
    File.mkdir!(output)
    File.chmod!(output, 0o700)

    fixture = Path.expand("dev/fixtures/synthetic_ollama_retained.exs")
    script = Path.expand(__ENV__.file)
    launcher = Path.expand("dev/knowledge/native_notes_retained_probe.exs")
    File.cp!(fixture, Path.join(output, "provider.exs"))
    File.cp!(script, Path.join(output, "native_notes_retained_probe.ex"))
    File.cp!(launcher, Path.join(output, "native_notes_retained_probe.exs"))
    File.chmod!(Path.join(output, "provider.exs"), 0o600)
    File.chmod!(Path.join(output, "native_notes_retained_probe.ex"), 0o600)
    File.chmod!(Path.join(output, "native_notes_retained_probe.exs"), 0o600)

    failed_evidence!(root)
    no_pending!(root)
    before = inventory!(root)
    save!(Path.join(output, "before-files.json"), before)
    before_external = external_evidence!()
    save!(Path.join(output, "before-external.json"), before_external)
    prepared = read(Path.join(root, "integrated-full/prepared.json"))
    anchor = read(Path.join(root, "turnover/clock-day-21.json"))
    assert prepared["kind"] == "initial" and prepared["root"] == root
    assert prepared["fixture_port"] in 1..65_535

    save!(Path.join(output, "intent.json"), %{
      "version" => 1,
      "kind" => "distinct_read_only_retained_cohort_probe",
      "root" => root,
      "before_files_sha256" => JSON.sha256(File.read!(Path.join(output, "before-files.json"))),
      "before_external_sha256" =>
        JSON.sha256(File.read!(Path.join(output, "before-external.json"))),
      "failed_turn_intent_sha256" => @intent_sha,
      "failed_turn_inflight_sha256" => @inflight_sha,
      "failed_journal_sha256" => @journal_sha,
      "provider_sha256" => JSON.sha256(File.read!(Path.join(output, "provider.exs"))),
      "driver_sha256" =>
        JSON.sha256(File.read!(Path.join(output, "native_notes_retained_probe.ex"))),
      "launcher_sha256" =>
        JSON.sha256(File.read!(Path.join(output, "native_notes_retained_probe.exs"))),
      "qualification" => false
    })

    paths = Path.wildcard(Path.join(root, "stdio-runtime/*/ebin")) |> Enum.flat_map(&["-pa", &1])

    env = [
      {"IPSE_HOME", Path.join(root, "home")},
      {"TMPDIR", output},
      {"LD_PRELOAD", Path.join(root, "clock.so")},
      {"IPSE_TEST_CLOCK_OFFSET_MS", Integer.to_string(anchor["offset_ms"])}
    ]

    {log, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2 +C multi_time_warp"] ++
          paths ++
          [Path.join(output, "native_notes_retained_probe.exs"), "--child", root, output],
        stderr_to_stdout: true,
        env: env
      )

    write!(Path.join(output, "child.log"), log)

    {verify_log, verify_status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2 +C multi_time_warp"] ++
          paths ++
          [Path.join(output, "native_notes_retained_probe.exs"), "--verify", root, output],
        stderr_to_stdout: true,
        env: env
      )

    write!(Path.join(output, "verify.log"), verify_log)
    after_files = inventory!(root)
    after_external = external_evidence!()
    save!(Path.join(output, "after-external.json"), after_external)

    changed =
      Enum.filter(before, fn {path, expected} -> after_files[path] !== expected end)
      |> Enum.map(&elem(&1, 0))

    added = Map.keys(after_files) -- Map.keys(before)
    save!(Path.join(output, "after-files.json"), after_files)

    save!(Path.join(output, "file-comparison.json"), %{
      "version" => 1,
      "existing_files_unchanged" => changed == [],
      "external_files_unchanged" => after_external === before_external,
      "changed_or_missing" => Enum.sort(changed),
      "added" => Enum.sort(added),
      "child_exit_code" => status,
      "verification_exit_code" => verify_status,
      "qualification" => false
    })

    assert changed == [], "pre-existing evidence changed; inspect without retry"

    assert after_external === before_external,
           "external audit evidence changed; inspect without retry"

    assert verify_status == 0, "post-diagnostic state could not be verified"
    assert status == 0, "diagnostic failed; inspect retained evidence without retry"

    assert read(Path.join(output, "before-state.json")) ===
             read(Path.join(output, "after-state.json"))

    child = read(Path.join(output, "result.json"))

    expected_additions =
      Enum.sort([
        "home/sessions/#{child["session_id"]}.jsonl",
        "home/sessions/#{child["session_id"]}.lock"
      ])

    assert Enum.sort(added) == expected_additions
    assert child["session_id"] != @failed_session

    save!(Path.join(output, "complete.json"), %{
      "version" => 1,
      "status" => "verified",
      "turn_result_sha256" => JSON.sha256(File.read!(Path.join(output, "result.json"))),
      "file_comparison_sha256" =>
        JSON.sha256(File.read!(Path.join(output, "file-comparison.json"))),
      "before_state_sha256" => JSON.sha256(File.read!(Path.join(output, "before-state.json"))),
      "after_state_sha256" => JSON.sha256(File.read!(Path.join(output, "after-state.json"))),
      "qualification" => false
    })

    IO.puts("NATIVE_RETAINED_READONLY_PROBE_PASSED=#{output}")
  end

  def main(["--child", root, output]) when root == @root do
    assert Path.type(output) == :absolute and Path.dirname(output) == "/tmp"
    assert String.starts_with?(Path.basename(output), "ipse-retained-readonly-")
    intent = read(Path.join(output, "intent.json"))
    assert intent["kind"] == "distinct_read_only_retained_cohort_probe" and intent["root"] == root
    assert intent["driver_sha256"] == JSON.sha256(File.read!(__ENV__.file))

    assert intent["launcher_sha256"] ==
             JSON.sha256(File.read!(Path.join(output, "native_notes_retained_probe.exs")))

    assert intent["provider_sha256"] == JSON.sha256(File.read!(Path.join(output, "provider.exs")))

    assert intent["before_files_sha256"] ==
             JSON.sha256(File.read!(Path.join(output, "before-files.json")))

    assert intent["before_external_sha256"] ==
             JSON.sha256(File.read!(Path.join(output, "before-external.json")))

    assert inventory!(root) === read(Path.join(output, "before-files.json"))
    assert external_evidence!() === read(Path.join(output, "before-external.json"))
    assert not File.exists?(Path.join(output, "turn-intent.json"))

    save!(Path.join(output, "child-started.json"), %{
      "version" => 1,
      "intent_sha256" => JSON.sha256(File.read!(Path.join(output, "intent.json")))
    })

    Code.require_file(Path.join(output, "provider.exs"))
    provider = Ipse.Development.SyntheticOllamaRetained
    {:ok, _} = Application.ensure_all_started(:ipse)
    failed_evidence!(root)
    no_pending!(root)
    home = Path.join(root, "home")
    cwd = Path.join(root, "work")
    state_dir = Path.join(home, "sessions")
    anchor = read(Path.join(root, "turnover/clock-day-21.json"))
    assert System.get_env("IPSE_TEST_CLOCK_OFFSET_MS") == Integer.to_string(anchor["offset_ms"])
    assert System.system_time(:millisecond) in anchor["start_ms"]..(anchor["end_ms"] - 1)
    verify_idle_sources!(state_dir)
    assert {:ok, _} = Ipse.Session.Lock.acquire(Path.join(state_dir, @failed_session <> ".lock"))
    failed_guard = Ipse.Session.Lock.current()

    try do
      {:ok, binding} = ProjectIdentity.existing(home, cwd)
      assert binding["project_id"] != nil
      {:ok, namespace} = SemanticConsent.namespace(binding["project_id"], "knowledge")
      collection = SemanticAdmission.collection_root(home)
      control_root = SemanticAdmission.control_root(home)
      {:ok, before_root} = ObservedRead.read(collection, namespace, %{"op" => "snapshot"})
      {:ok, before_control} = Consent.existing_snapshot(control_root, binding["project_id"])
      last = read(read(Path.join(root, "turnover/closed-14.json"))["report"]["path"])
      assert before_root["value"] === last["snapshot"]
      assert before_root["witness"]["root_sha256"] == last["root_sha256"]
      assert JSON.digest([before_control]) == last["control_sha256"]

      assert Enum.all?(before_control["operations"], fn {_, row} -> row["status"] == "settled" end)

      assert Enum.all?(before_control["compacted"], fn {_, row} ->
               Enum.at(row, 4) == "settled"
             end)

      save!(Path.join(output, "before-state.json"), state_receipt(before_root, before_control))

      for key <-
            ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
          do: System.delete_env(key)

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

      {:ok, effective} =
        Ipse.Config.resolve(
          cwd,
          home,
          [config: Path.join(home, "config.json"), project_config: false],
          %{}
        )

      {:ok, config} = Ipse.Config.runtime(effective, client)
      config = Map.merge(config, %{execution_mode: :read_only, enclosing_mode: :read_only})
      {:ok, mode} = Mode.capture(config)
      assert mode["ceiling"] == "read_only" and mode["enclosing_ceiling"] == "read_only"
      assert :ok = Mode.knowledge(mode, "collection.read")
      assert {:error, :knowledge_mode_denied} = Mode.knowledge(mode, "collection.publish")
      assert :deny = Mode.ordinary(mode, true)
      prepared = read(Path.join(root, "integrated-full/prepared.json"))
      assert config.provider == :ollama and config.model == "synthetic"
      assert config.base_url == "http://127.0.0.1:#{prepared["fixture_port"]}"
      no_pending!(root)
      {:ok, server} = apply(provider, :start, [prepared["fixture_port"], self()])

      try do
        {:ok, session} =
          DynamicSupervisor.start_child(
            Ipse.Sessions,
            {Session,
             config: config, cwd: cwd, state_dir: state_dir, subscriber: self(), owner: self()}
          )

        id = Session.info(session).id
        assert id != @failed_session
        {:ok, live_mode} = Mode.capture(:sys.get_state(session).config)
        assert live_mode === mode
        assert get_in(:sys.get_state(session).config, [:semantic_admission, "status"]) == "active"
        prompt = apply(provider, :prompt, [])

        save!(Path.join(output, "turn-intent.json"), %{
          "version" => 1,
          "session_id" => id,
          "prompt_sha256" => JSON.sha256(prompt)
        })

        started = System.monotonic_time(:microsecond)
        assert :ok = Session.prompt(session, prompt)

        {request_sha, request_bytes, reference} =
          await_turn!(session, System.monotonic_time(:millisecond) + 150_000, nil, false)

        assert :ok = Task.await(server, 30_000)
        assert :ok = Session.close_confirmed(session)
        assert {:ok, events} = Journal.load(state_dir, id)
        assert {:ok, _} = Session.Saved.restore(events, id)
        inputs = Enum.filter(events, &(&1["type"] == "input_received"))
        dispatches = Enum.filter(events, &(&1["type"] == "inference_dispatch_intent"))
        assert length(inputs) == 1 and length(dispatches) == 1
        assert hd(inputs)["turn_id"] == hd(dispatches)["turn_id"]
        assert hd(inputs)["turn_id"] != @failed_turn
        assert hd(inputs)["text_sha256"] == JSON.sha256(prompt)
        assert JSON.sha256?(request_sha) and request_bytes in 1..2_097_152

        {:ok, after_root} = ObservedRead.read(collection, namespace, %{"op" => "snapshot"})
        {:ok, after_control} = Consent.existing_snapshot(control_root, binding["project_id"])
        assert after_root === before_root and after_control === before_control
        failed_evidence!(root)
        no_pending!(root)

        save!(Path.join(output, "result.json"), %{
          "version" => 1,
          "status" => "turn_completed_pending_verification",
          "session_id" => id,
          "turn_id" => hd(inputs)["turn_id"],
          "request_sha256" => request_sha,
          "request_bytes" => request_bytes,
          "reference_observed" => reference,
          "elapsed_us" => System.monotonic_time(:microsecond) - started,
          "execution_mode" => mode,
          "qualification" => false
        })
      after
        if Process.alive?(server.pid), do: Task.shutdown(server, :brutal_kill)
      end
    after
      :ok = Ipse.Session.Lock.release(failed_guard)
    end
  end

  def main(["--verify", root, output]) when root == @root do
    {:ok, _} = Application.ensure_all_started(:ipse)
    home = Path.join(root, "home")
    cwd = Path.join(root, "work")
    verify_idle_sources!(Path.join(home, "sessions"))
    {:ok, binding} = ProjectIdentity.existing(home, cwd)
    {:ok, namespace} = SemanticConsent.namespace(binding["project_id"], "knowledge")

    {:ok, observed} =
      ObservedRead.read(SemanticAdmission.collection_root(home), namespace, %{"op" => "snapshot"})

    {:ok, control} =
      Consent.existing_snapshot(SemanticAdmission.control_root(home), binding["project_id"])

    save!(Path.join(output, "after-state.json"), state_receipt(observed, control))
  end

  def main(_), do: raise("use --run RETAINED_ROOT NEW_OUTPUT_DIR")

  defp failed_evidence!(root) do
    dir = Path.join(root, "integrated-full")
    assert JSON.sha256(File.read!(Path.join(dir, "turn-1-intent.json"))) == @intent_sha
    assert JSON.sha256(File.read!(Path.join(dir, "turn-1-inflight.json"))) == @inflight_sha

    assert JSON.sha256(File.read!(Path.join(root, "home/sessions/#{@failed_session}.jsonl"))) ==
             @journal_sha

    assert not File.exists?(Path.join(dir, "turn-1-result.json"))
    assert length(Path.wildcard(Path.join(dir, "effect-*-result.json"))) == 14
    assert length(Path.wildcard(Path.join(root, "turnover/closed-*.json"))) == 14
    assert not File.exists?(Path.join(root, "turnover/inflight.json"))

    for index <- 1..14 do
      intent_path = Path.join(dir, "effect-#{index}-intent.json")
      result = read(Path.join(dir, "effect-#{index}-result.json"))
      closure_path = Path.join(root, "turnover/closed-#{index}.json")
      closure = read(closure_path)

      assert result["segment"] == index and
               result["intent_sha256"] == JSON.sha256(File.read!(intent_path))

      assert result["closure"]["path"] == closure_path
      verify_fingerprint!(result["closure"])
      assert closure["index"] == index and closure["exit_code"] == 0
      for key <- ~w(input report log), do: verify_fingerprint!(closure[key])
    end

    assert JSON.sha256(File.read!(@seed_audit)) == @seed_audit_sha
    audit = read(@seed_audit)

    assert audit["verified_records"] == 2000 and audit["unchanged_root"] and
             audit["unchanged_control"]

    verify_fingerprint!(audit["verified_rows"])
  end

  defp verify_fingerprint!(row) do
    assert is_map(row) and is_binary(row["path"]) and is_integer(row["bytes"])
    bytes = File.read!(row["path"])
    assert byte_size(bytes) == row["bytes"] and JSON.sha256(bytes) == row["sha256"]
  end

  defp no_pending!(root) do
    home = Path.join(root, "home")
    assert Path.wildcard(Path.join(home, "**/.pending-*"), match_dot: true) == []
    assert Path.wildcard(Path.join(home, "**/.metadata-active"), match_dot: true) == []
  end

  defp verify_idle_sources!(directory) do
    journals = Path.wildcard(Path.join(directory, "*.jsonl"))
    locks = Path.wildcard(Path.join(directory, "*.lock"))
    assert journals != []
    assert Enum.all?(journals, &((Path.rootname(&1, ".jsonl") <> ".lock") in locks))

    for lock <- locks do
      assert File.lstat!(lock).type == :regular
      assert {:ok, port} = Ipse.Runner.protected_lock(lock)
      assert :ok = Ipse.Runner.unlock(port)
    end
  end

  defp await_turn!(_session, _deadline, request, true) when is_tuple(request), do: request

  defp await_turn!(session, deadline, request, done) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:retained_request, digest, bytes, observed} when is_nil(request) ->
        next_deadline = min(deadline, System.monotonic_time(:millisecond) + 30_000)
        await_turn!(session, next_deadline, {digest, bytes, observed}, done)

      {:ipse, ^session, {:done, :ok}} ->
        await_turn!(session, deadline, request, true)

      {:ipse, ^session, {:done, status}} ->
        flunk("new Session failed: #{inspect(status)}")
    after
      remaining ->
        flunk("diagnostic request or completion deadline expired; inspect without retry")
    end
  end

  defp state_receipt(root, control),
    do: %{"root" => root, "control_sha256" => JSON.digest([control])}

  defp external_evidence! do
    Map.new(
      [
        @seed_audit,
        @seed_audit <> ".rows.json",
        @seed_audit <> ".driver.ex",
        @seed_audit <> ".log"
      ],
      fn path ->
        stat = File.lstat!(path)
        assert stat.type == :regular and stat.size <= @maximum_file_bytes
        bytes = File.read!(path)

        {path,
         %{
           "bytes" => stat.size,
           "sha256" => JSON.sha256(bytes),
           "inode" => stat.inode,
           "major_device" => stat.major_device,
           "minor_device" => stat.minor_device
         }}
      end
    )
  end

  defp inventory!(root) do
    paths = walk!(root, "")
    assert length(paths) <= @maximum_files

    entries =
      Enum.map(paths, fn relative ->
        path = Path.join(root, relative)
        stat = File.lstat!(path)
        assert stat.type == :regular and stat.size <= @maximum_file_bytes
        bytes = File.read!(path)
        assert byte_size(bytes) == stat.size

        {relative,
         %{
           "bytes" => stat.size,
           "sha256" => JSON.sha256(bytes),
           "inode" => stat.inode,
           "major_device" => stat.major_device,
           "minor_device" => stat.minor_device,
           "uid" => stat.uid,
           "mode" => stat.mode
         }}
      end)

    assert Enum.sum(Enum.map(entries, fn {_, value} -> value["bytes"] end)) <=
             @maximum_total_bytes

    Map.new(entries)
  end

  defp walk!(root, relative) do
    dir = Path.join(root, relative)

    File.ls!(dir)
    |> Enum.sort()
    |> Enum.flat_map(fn name ->
      child = Path.join(relative, name)

      case File.lstat!(Path.join(root, child)).type do
        :directory -> walk!(root, child)
        :regular -> [child]
        _ -> flunk("non-regular retained entry; refuse diagnostic")
      end
    end)
  end

  defp read(path), do: path |> File.read!() |> Jason.decode!()

  defp save!(path, value), do: write!(path, Jason.encode!(value) <> "\n")

  defp write!(path, bytes) do
    {:ok, file} = :file.open(String.to_charlist(path), [:write, :binary, :exclusive])
    :ok = :file.write(file, bytes)
    File.chmod!(path, 0o600)
    :ok = :file.sync(file)
    :ok = :file.close(file)
    :ok = Ipse.Runner.protected_sync_directory(Path.dirname(path))
  end
end
