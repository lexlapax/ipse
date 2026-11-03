defmodule Ipse.Development.NativeNotesIntegratedFull do
  @moduledoc "Fresh synthetic native-effect and actual-Session workload checkpoints."
  import ExUnit.Assertions
  alias Ipse.{JSON, Journal, Session}

  @turns_per_segment 10
  @segments 4

  @doc "Split one full-cohort fixture day into four turn groups around its effects."
  def full_schedule(day, effects)
      when is_integer(day) and day >= 0 and is_integer(effects) and effects >= @segments do
    for segment <- 1..@segments do
      %{
        "segment" => segment,
        "process_offset_day" => day,
        "first_effect" => div((segment - 1) * effects, @segments) + 1,
        "last_effect" => div(segment * effects, @segments),
        "first_turn" => (segment - 1) * @turns_per_segment + 1,
        "turns" => @turns_per_segment
      }
    end
  end

  def main(["--prepare", root, port]), do: prepare(root, port, "initial")

  def main(["--run", root]) do
    run_started = System.monotonic_time(:microsecond)
    m = prepared(root)
    dir = Path.join(root, "integrated-full")
    turnover_manifest = read(m["turnover_manifest"]["path"])
    segments = read(turnover_manifest["segments_file"]["path"]) |> List.to_tuple()

    assert new_run?(dir),
           "integrated run already started; inspect retained evidence and do not replay"

    assert not File.exists?(Path.join(root, "turnover/inflight.json"))
    assert Path.wildcard(Path.join(root, "turnover/closed-*.json")) == []

    save(Path.join(dir, "run-intent.json"), %{
      "version" => 1,
      "prepared_sha256" => JSON.sha256(File.read!(Path.join(dir, "prepared.json")))
    })

    for item <- m["schedule"] do
      segment = item["segment"]
      started_real = System.system_time(:millisecond)

      prior =
        if segment == 1, do: nil, else: fingerprint(Path.join(dir, "turns-#{segment - 1}.json"))

      {first_effect, last_effect} = effect_range(item)

      for effect <- first_effect..last_effect do
        started_real = System.system_time(:millisecond)
        started_monotonic = System.monotonic_time(:microsecond)
        planned = elem(segments, effect - 1)
        assert planned["index"] == effect and length(planned["actions"]) == 1
        assert planned["process_offset_day"] == item["process_offset_day"]
        intent_path = Path.join(dir, "effect-#{effect}-intent.json")

        save(intent_path, %{
          "version" => 1,
          "segment" => effect,
          "turn_group" => segment,
          "planned_action" => hd(planned["actions"]),
          "started_real_ms" => started_real,
          "prior_turn_report" => prior
        })

        run_child(
          root,
          m["turnover_driver"]["path"],
          ["--run", root, "1"],
          [],
          Path.join(dir, "effect-#{effect}.log")
        )

        closed_path = Path.join(root, "turnover/closed-#{effect}.json")
        closed = read(closed_path)
        assert closed["index"] == effect and closed["exit_code"] == 0
        for key <- ~w(input report log), do: verify(closed[key])
        input = read(closed["input"]["path"])
        assert input["segment"] === planned and length(input["actions"]) == 1

        save(Path.join(dir, "effect-#{effect}-result.json"), %{
          "version" => 1,
          "segment" => effect,
          "intent_sha256" => JSON.sha256(File.read!(intent_path)),
          "closure" => fingerprint(closed_path),
          "elapsed_us" => System.monotonic_time(:microsecond) - started_monotonic,
          "coordinator_beam_memory_bytes" => :erlang.memory(:total)
        })
      end

      closed = read(Path.join(root, "turnover/closed-#{last_effect}.json"))
      report = read(closed["report"]["path"])
      anchor = read(clock_path(root, item))
      assert started_real + anchor["offset_ms"] <= report["ended_virtual_ms"]

      if prior do
        verify(prior)
        assert started_real + anchor["offset_ms"] >= read(prior["path"])["ended_virtual_ms"]
      end

      env = [
        {"LD_PRELOAD", Path.join(root, "clock.so")},
        {"IPSE_TEST_CLOCK_OFFSET_MS", Integer.to_string(anchor["offset_ms"])}
      ]

      run_child(
        root,
        m["launcher"]["path"],
        ["--turns", root, Integer.to_string(segment)],
        env,
        Path.join(dir, "turns-#{segment}.log")
      )

      turn_report = read(Path.join(dir, "turns-#{segment}.json"))
      assert turn_report["segment"] == segment and turn_report["turns"] == @turns_per_segment
      assert turn_report["started_virtual_ms"] >= report["ended_virtual_ms"]
      assert turn_report["ended_virtual_ms"] < anchor["end_ms"]
    end

    assert length(Path.wildcard(Path.join(dir, "turn-*-result.json"))) == 40
    assert Path.wildcard(Path.join(dir, "turn-*-inflight.json")) == []
    anchor = read(clock_path(root, hd(m["schedule"])))

    env = [
      {"LD_PRELOAD", Path.join(root, "clock.so")},
      {"IPSE_TEST_CLOCK_OFFSET_MS", Integer.to_string(anchor["offset_ms"])}
    ]

    run_child(root, m["launcher"]["path"], ["--audit", root], env, Path.join(dir, "audit.log"))
    audit = fingerprint(Path.join(dir, "audit.json"))

    save(Path.join(dir, "complete.json"), %{
      "turns" => 40,
      "native_effects" => last_effect(m),
      "audit" => audit,
      "elapsed_us" => System.monotonic_time(:microsecond) - run_started,
      "coordinator_beam_memory_bytes" => :erlang.memory(:total),
      "resource_scope" => "coordinator BEAM sample only, not process-tree or disk peak",
      "fixture_provider_cost_usd" => 0,
      "qualification" => false
    })

    IO.puts(
      "NATIVE_INTEGRATED_#{String.upcase(m["kind"])}_COMPLETED turns=40 effects=#{last_effect(m)}"
    )
  end

  def main(["--turns", root, segment]) do
    {segment, ""} = Integer.parse(segment)
    m = prepared(root)
    item = Enum.at(m["schedule"], segment - 1)
    assert is_map(item) and item["segment"] == segment
    dir = Path.join(root, "integrated-full")
    verify_run_intent(dir)
    assert not File.exists?(Path.join(dir, "turns-#{segment}.json"))
    {_, last_effect} = effect_range(item)
    closed = read(Path.join(root, "turnover/closed-#{last_effect}.json"))
    assert closed["index"] == last_effect and closed["exit_code"] == 0
    verify(closed["report"])

    if segment > 1 do
      for prior <- 1..(segment - 1),
          do: assert(File.regular?(Path.join(dir, "turns-#{prior}.json")))
    end

    Code.require_file(m["provider"]["path"])
    provider = Ipse.Development.SyntheticOllama
    {:ok, _} = Application.ensure_all_started(:ipse)
    home = Path.join(root, "home")
    cwd = Path.join(root, "work")

    for key <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
        do: System.delete_env(key)

    config_path = Path.join(home, "config.json")

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
      Ipse.Config.resolve(cwd, home, [config: config_path, project_config: false], %{})

    {:ok, config} = Ipse.Config.runtime(effective, client)

    assert config.provider == :ollama and
             config.base_url == "http://127.0.0.1:#{m["fixture_port"]}"

    assert config.model == "synthetic"

    {:ok, server} =
      apply(provider, :start, [m["fixture_port"], self(), item["first_turn"], item["turns"]])

    state_dir = Path.join(home, "sessions")

    {:ok, session} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: config, cwd: cwd, state_dir: state_dir, subscriber: self(), owner: self()}
      )

    :ok = Ipse.Session.Lock.track_session(session)
    id = Session.info(session).id
    anchor = read(clock_path(root, item))
    assert System.get_env("IPSE_TEST_CLOCK_OFFSET_MS") == Integer.to_string(anchor["offset_ms"])
    started = System.system_time(:millisecond)
    assert started in anchor["start_ms"]..(anchor["end_ms"] - 1)

    for {turn, local} <-
          Enum.with_index(item["first_turn"]..(item["first_turn"] + item["turns"] - 1), 1) do
      intent = Path.join(dir, "turn-#{turn}-intent.json")
      inflight = Path.join(dir, "turn-#{turn}-inflight.json")
      result = Path.join(dir, "turn-#{turn}-result.json")
      assert not File.exists?(intent) and not File.exists?(inflight) and not File.exists?(result)
      prompt = apply(provider, :prompt, [turn])
      turn_started = System.monotonic_time(:microsecond)

      save(intent, %{
        "version" => 1,
        "turn" => turn,
        "session_id" => id,
        "prompt_sha256" => JSON.sha256(prompt)
      })

      intent_sha256 = JSON.sha256(File.read!(intent))
      save(inflight, %{"version" => 1, "turn" => turn, "intent_sha256" => intent_sha256})
      assert :ok = Session.prompt(session, prompt)

      {request_sha256, request_bytes} =
        receive do
          {:synthetic_provider_request, ^turn, digest, bytes, true} ->
            {digest, bytes}

          {:synthetic_provider_request, ^turn, _, _, false} ->
            flunk("synthetic request omitted every seeded reference")

          {:ipse, ^session, {:done, status}} ->
            flunk("session stopped before request: #{inspect(status)}")
        after
          120_000 -> flunk("synthetic provider request not confirmed; do not replay")
        end

      assert_receive {:ipse, ^session, {:done, :ok}}, 30_000
      assert {:ok, events} = Journal.load(state_dir, id)
      inputs = Enum.filter(events, &(&1["type"] == "input_received"))
      dispatches = Enum.filter(events, &(&1["type"] == "inference_dispatch_intent"))
      finished = Enum.filter(events, &(&1["type"] == "turn_finished"))
      assert length(inputs) == local and length(dispatches) == local and length(finished) == local
      assert List.last(inputs)["turn_id"] == List.last(dispatches)["turn_id"]
      assert List.last(inputs)["text_sha256"] == JSON.sha256(prompt)
      assert List.last(finished)["status"] == "ok"
      now = System.system_time(:millisecond)
      assert now in anchor["start_ms"]..(anchor["end_ms"] - 1)

      save(result, %{
        "version" => 1,
        "turn" => turn,
        "session_id" => id,
        "turn_id" => List.last(inputs)["turn_id"],
        "request_sha256" => request_sha256,
        "request_bytes" => request_bytes,
        "intent_sha256" => intent_sha256,
        "reference_observed" => true,
        "elapsed_us" => System.monotonic_time(:microsecond) - turn_started,
        "finished_virtual_ms" => now
      })

      File.rm!(inflight)
      assert :ok = Ipse.Runner.protected_sync_directory(dir)
    end

    assert :ok = Task.await(server, 30_000)
    assert :ok = Session.close_confirmed(session)
    assert {:ok, events} = Journal.load(state_dir, id)
    assert {:ok, _} = Session.Saved.restore(events, id)
    ended = System.system_time(:millisecond)
    assert ended >= started and ended < anchor["end_ms"]

    save(Path.join(dir, "turns-#{segment}.json"), %{
      "segment" => segment,
      "session_id" => id,
      "journal" => fingerprint(Path.join(state_dir, id <> ".jsonl")),
      "turns" => item["turns"],
      "started_virtual_ms" => started,
      "ended_virtual_ms" => ended,
      "qualification" => false
    })
  end

  def main(["--audit", root]) do
    m = prepared(root)
    dir = Path.join(root, "integrated-full")
    verify_run_intent(dir)
    assert not File.exists?(Path.join(dir, "audit.json"))
    assert Path.wildcard(Path.join(dir, "turn-*-inflight.json")) == []
    assert length(Path.wildcard(Path.join(dir, "turn-*-result.json"))) == 40
    Code.require_file(m["provider"]["path"])
    provider = Ipse.Development.SyntheticOllama
    {:ok, _} = Application.ensure_all_started(:ipse)
    home = Path.join(root, "home")
    cwd = Path.join(root, "work")
    state_dir = Path.join(home, "sessions")
    anchor = read(clock_path(root, hd(m["schedule"])))
    assert System.get_env("IPSE_TEST_CLOCK_OFFSET_MS") == Integer.to_string(anchor["offset_ms"])

    results =
      for item <- m["schedule"] do
        segment = item["segment"]
        {first_effect, last_effect} = effect_range(item)

        for effect_index <- first_effect..last_effect do
          closed_path = Path.join(root, "turnover/closed-#{effect_index}.json")
          closed = read(closed_path)
          assert closed["index"] == effect_index and closed["exit_code"] == 0
          for key <- ~w(input report log), do: verify(closed[key])
          effect = read(closed["report"]["path"])
          input = read(closed["input"]["path"])
          intent_path = Path.join(dir, "effect-#{effect_index}-intent.json")
          intent = read(intent_path)
          result = read(Path.join(dir, "effect-#{effect_index}-result.json"))
          assert intent["version"] == 1 and intent["segment"] == effect_index
          assert intent["turn_group"] == segment and length(input["actions"]) == 1
          assert intent["planned_action"] === hd(input["segment"]["actions"])
          assert result["segment"] == effect_index and result["version"] == 1
          assert result["intent_sha256"] == JSON.sha256(File.read!(intent_path))
          assert result["closure"] === fingerprint(closed_path)
          assert is_integer(result["elapsed_us"]) and result["elapsed_us"] >= 0
          assert intent["started_real_ms"] + anchor["offset_ms"] <= effect["ended_virtual_ms"]

          if segment == 1 do
            assert is_nil(intent["prior_turn_report"])
          else
            prior = intent["prior_turn_report"]
            verify(prior)
            assert prior["path"] == Path.join(dir, "turns-#{segment - 1}.json")

            assert intent["started_real_ms"] + anchor["offset_ms"] >=
                     read(prior["path"])["ended_virtual_ms"]
          end
        end

        closed = read(Path.join(root, "turnover/closed-#{last_effect}.json"))
        effect = read(closed["report"]["path"])

        group = read(Path.join(dir, "turns-#{segment}.json"))
        assert group["segment"] == segment and group["turns"] == @turns_per_segment
        assert group["started_virtual_ms"] >= effect["ended_virtual_ms"]
        assert group["ended_virtual_ms"] < anchor["end_ms"]
        verify(group["journal"])
        assert {:ok, events} = Journal.load(state_dir, group["session_id"])
        assert {:ok, _} = Session.Saved.restore(events, group["session_id"])

        assert :ok =
                 Ipse.Session.SourceWindow.validate_sources(
                   state_dir,
                   group["session_id"],
                   events
                 )

        inputs = Enum.filter(events, &(&1["type"] == "input_received"))
        dispatches = Enum.filter(events, &(&1["type"] == "inference_dispatch_intent"))
        finished = Enum.filter(events, &(&1["type"] == "turn_finished"))
        assert length(inputs) == @turns_per_segment and length(dispatches) == @turns_per_segment

        assert length(finished) == @turns_per_segment and
                 Enum.all?(finished, &(&1["status"] == "ok"))

        for {turn, index} <-
              Enum.with_index(item["first_turn"]..(item["first_turn"] + item["turns"] - 1)) do
          intent_path = Path.join(dir, "turn-#{turn}-intent.json")
          intent = read(intent_path)
          result = read(Path.join(dir, "turn-#{turn}-result.json"))
          input = Enum.at(inputs, index)
          dispatch = Enum.at(dispatches, index)

          assert intent["version"] == 1 and intent["turn"] == turn and
                   intent["session_id"] == group["session_id"]

          assert intent["prompt_sha256"] == JSON.sha256(apply(provider, :prompt, [turn]))

          assert result["version"] == 1 and result["turn"] == turn and
                   result["session_id"] == group["session_id"]

          assert result["intent_sha256"] == JSON.sha256(File.read!(intent_path))
          assert result["turn_id"] == input["turn_id"] and input["turn_id"] == dispatch["turn_id"]
          assert input["text_sha256"] == JSON.sha256(apply(provider, :prompt, [turn]))

          assert JSON.sha256?(result["request_sha256"]) and
                   result["request_bytes"] in 1..2_097_152

          assert result["reference_observed"] == true

          assert result["finished_virtual_ms"] in group["started_virtual_ms"]..group[
                   "ended_virtual_ms"
                 ]

          result["turn_id"]
        end
      end
      |> List.flatten()

    assert length(results) == 40 and length(Enum.uniq(results)) == 40
    {:ok, binding} = Ipse.Extension.ProjectIdentity.existing(home, cwd)

    {:ok, namespace} =
      Ipse.Extension.SemanticConsent.namespace(binding["project_id"], "knowledge")

    collection = Ipse.Extension.SemanticAdmission.collection_root(home)

    {:ok, before} =
      Ipse.Extension.Collection.ObservedRead.read(collection, namespace, %{"op" => "snapshot"})

    last = read(read(Path.join(root, "turnover/closed-#{last_effect(m)}.json"))["report"]["path"])

    assert before["value"] === last["snapshot"] and
             before["witness"]["root_sha256"] == last["root_sha256"]

    {:ok, control} =
      Ipse.Extension.Consent.existing_snapshot(
        Ipse.Extension.SemanticAdmission.control_root(home),
        binding["project_id"]
      )

    assert JSON.digest([control]) == last["control_sha256"]
    assert Enum.all?(control["operations"], fn {_, row} -> row["status"] == "settled" end)

    {:ok, after_snapshot} =
      Ipse.Extension.Collection.ObservedRead.read(collection, namespace, %{"op" => "snapshot"})

    {:ok, after_control} =
      Ipse.Extension.Consent.existing_snapshot(
        Ipse.Extension.SemanticAdmission.control_root(home),
        binding["project_id"]
      )

    assert after_snapshot === before and after_control === control

    assert {:ok, status} =
             Ipse.Extension.Collection.execute(
               collection,
               namespace,
               %{"op" => "status"},
               Ipse.Usage.id()
             )

    physical =
      Map.new(
        [
          {"control", Ipse.Extension.SemanticAdmission.control_root(home)},
          {"identity", Path.join(home, "project-identities")},
          {"management", Path.join(home, "knowledge-management")},
          {"sessions", state_dir}
        ],
        fn {name, path} ->
          assert {:ok, allocation} = Ipse.Runner.storage_allocation(path)
          {name, allocation}
        end
      )

    measured =
      status["allocated_bytes"] +
        Enum.sum(Enum.map(physical, fn {_, usage} -> usage["allocated_bytes"] end))

    save(Path.join(dir, "audit.json"), %{
      "turns" => 40,
      "native_effects" => last_effect(m),
      "collection_generation" => before["value"]["generation"],
      "control_sequence" => control["sequence"],
      "unchanged_root_and_control" => true,
      "collection_status" => status,
      "physical_allocations" => physical,
      "measured_components_allocated_bytes" => measured,
      "allocation_scope" =>
        "sample after audit: collection, control, identity, management and sessions; excludes runtime and process-tree peaks",
      "qualification" => false
    })

    IO.puts("NATIVE_INTEGRATED_#{String.upcase(m["kind"])}_AUDIT_PASSED")
  end

  def main(_), do: raise("use --prepare ROOT PORT or --run ROOT")

  defp prepare(root, port, kind) do
    preparation_started = System.monotonic_time(:microsecond)
    {port, ""} = Integer.parse(port)
    assert port in 1..65_535
    Code.require_file(Path.expand("dev/knowledge/native_notes_seed.ex"))
    seed = Ipse.Development.NativeNotesSeed
    apply(seed, :main, [["--init", root, kind, "--fixture-port", Integer.to_string(port)]])

    dir = Path.join(root, "integrated-full")
    File.mkdir!(dir)
    File.chmod!(dir, 0o700)
    File.cp!(__ENV__.file, Path.join(dir, "native_notes_integrated_full.ex"))

    File.cp!(
      Path.expand("dev/knowledge/native_notes_integrated_full.exs"),
      Path.join(dir, "native_notes_integrated_full.exs")
    )

    File.cp!(Path.expand("dev/fixtures/synthetic_ollama.exs"), Path.join(dir, "provider.exs"))

    apply(seed, :main, [["--run", root, "all"]])
    seed_finished = System.monotonic_time(:microsecond)
    audit = Path.join("/tmp", "ipse-native-seed-audit-#{JSON.sha256(root)}.json")
    apply(seed, :main, [["--audit", root, audit]])
    seed_audit_finished = System.monotonic_time(:microsecond)

    turnover = Path.expand("dev/knowledge/native_notes_turnover.exs")

    run_child(
      root,
      turnover,
      ["--init", root, audit, "1"],
      [],
      Path.join(dir, "turnover-init.log")
    )

    frozen = Path.join(root, "turnover/driver.exs")
    turnover_manifest = read(Path.join(root, "turnover/manifest.json"))
    segments = read(turnover_manifest["segments_file"]["path"])

    first_day = hd(segments)["process_offset_day"]
    day_segments = Enum.take_while(segments, &(&1["process_offset_day"] == first_day))
    assert Enum.all?(day_segments, &(length(&1["actions"]) == 1))

    actions = Enum.map(day_segments, &hd(&1["actions"]))
    reasons = Enum.frequencies_by(actions, & &1["reason"])

    assert reasons == %{
             "ordinary_additions" => 20,
             "ordinary_corrections" => 4,
             "explicit_forgets" => 2,
             "temporal_supersessions" => 4,
             "additional_churn" => 27
           }

    fixture_path = Path.join(dir, "fixture-day.json")

    save(fixture_path, %{
      "version" => 1,
      "scope" =>
        "synthetic one-day fixture; intake and mix are provisional, not pilot-derived or representative",
      "intake_ratified" => false,
      "ordinary_intake" => 20,
      "additional_mixed_changes" => 27,
      "reasons" => reasons,
      "segments" => day_segments,
      "qualification" => false
    })

    schedule = full_schedule(first_day, length(day_segments))
    fixture = fingerprint(fixture_path)

    save(Path.join(dir, "prepared.json"), %{
      "version" => 1,
      "root" => root,
      "fixture_port" => port,
      "kind" => kind,
      "schedule" => schedule,
      "fixture_day" => fixture,
      "seed_elapsed_us" => seed_finished - preparation_started,
      "seed_audit_elapsed_us" => seed_audit_finished - seed_finished,
      "resource_scope" =>
        "seed audit components and coordinator BEAM samples; no process-tree or disk peak",
      "driver" => fingerprint(Path.join(dir, "native_notes_integrated_full.ex")),
      "launcher" => fingerprint(Path.join(dir, "native_notes_integrated_full.exs")),
      "provider" => fingerprint(Path.join(dir, "provider.exs")),
      "seed_manifest" => fingerprint(Path.join(root, "manifest.json")),
      "seed_audit" => fingerprint(audit),
      "turnover_manifest" => fingerprint(Path.join(root, "turnover/manifest.json")),
      "turnover_driver" => fingerprint(frozen),
      "qualification" => false
    })

    IO.puts("NATIVE_INTEGRATED_#{String.upcase(kind)}_PREPARED")
  end

  @doc false
  def new_run?(dir) when is_binary(dir) do
    not File.exists?(Path.join(dir, "run-intent.json")) and
      Path.wildcard(Path.join(dir, "effect-*.log")) == [] and
      Path.wildcard(Path.join(dir, "effect-*.json")) == [] and
      Path.wildcard(Path.join(dir, "turn-*.json")) == [] and
      Path.wildcard(Path.join(dir, "turns-*.json")) == [] and
      Path.wildcard(Path.join(dir, "turns-*.log")) == [] and
      not File.exists?(Path.join(dir, "complete.json"))
  end

  defp prepared(root) do
    dir = Path.join(root, "integrated-full")
    m = read(Path.join(dir, "prepared.json"))
    assert m["version"] == 1 and m["root"] == root and m["kind"] == "initial"

    for key <-
          ~w(driver launcher provider seed_manifest seed_audit turnover_manifest turnover_driver),
        do: verify(m[key])

    verify(m["fixture_day"])
    fixture = read(m["fixture_day"]["path"])
    assert fixture["intake_ratified"] == false and fixture["ordinary_intake"] == 20
    assert length(fixture["segments"]) == 57
    first_day = hd(fixture["segments"])["process_offset_day"]
    assert m["schedule"] == full_schedule(first_day, length(fixture["segments"]))

    assert JSON.sha256(File.read!(__ENV__.file)) == m["driver"]["sha256"]
    m
  end

  defp effect_range(item) do
    {item["first_effect"], item["last_effect"]}
  end

  defp last_effect(m), do: m["schedule"] |> List.last() |> effect_range() |> elem(1)

  defp clock_path(root, item),
    do: Path.join(root, "turnover/clock-day-#{item["process_offset_day"]}.json")

  defp verify_run_intent(dir) do
    expected = %{
      "version" => 1,
      "prepared_sha256" => JSON.sha256(File.read!(Path.join(dir, "prepared.json")))
    }

    assert read(Path.join(dir, "run-intent.json")) === expected
  end

  defp run_child(root, script, args, extra_env, log) do
    paths = Path.wildcard(Path.join(root, "stdio-runtime/*/ebin")) |> Enum.flat_map(&["-pa", &1])

    env =
      %{
        "IPSE_HOME" => Path.join(root, "home"),
        "TMPDIR" => root,
        "LD_PRELOAD" => Path.join(root, "clock.so"),
        "IPSE_TEST_CLOCK_OFFSET_MS" => "0"
      }
      |> Map.merge(Map.new(extra_env))
      |> Map.to_list()

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2 +C multi_time_warp"] ++ paths ++ [script] ++ args,
        stderr_to_stdout: true,
        env: env
      )

    File.write!(log, output, [:exclusive])
    File.chmod!(log, 0o600)

    assert status == 0,
           "integrated child failed; inspect #{log}; never replay an unknown effect or turn"
  end

  defp fingerprint(path),
    do: %{
      "path" => path,
      "bytes" => File.stat!(path).size,
      "sha256" => JSON.sha256(File.read!(path))
    }

  defp verify(row), do: assert(fingerprint(row["path"]) === row)
  defp read(path), do: path |> File.read!() |> Jason.decode!()

  defp save(path, value) do
    {:ok, file} = :file.open(String.to_charlist(path), [:write, :binary, :exclusive])
    :ok = :file.write(file, Jason.encode!(value) <> "\n")
    File.chmod!(path, 0o600)
    :ok = :file.sync(file)
    :ok = :file.close(file)
    :ok = Ipse.Runner.protected_sync_directory(Path.dirname(path))
  end
end
