defmodule Ipse.Development.NativeNotesTurnover do
  @moduledoc "Development-only, bounded native turnover continuation; no model turns."
  import ExUnit.Assertions
  alias Ipse.{JSON, Journal, Session, Usage}
  alias Ipse.CLI.Knowledge.Management
  alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission}
  alias Ipse.Extension.Collection.ObservedRead
  @day 86_400_000
  @smoke_actions [
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

  def main(["--init", root, audit_path, maximum_arg]) do
    Process.flag(:max_heap_size, %{size: 64_000_000, kill: true, error_logger: true})
    maximum = String.to_integer(maximum_arg)
    assert maximum in 1..8

    assert Path.expand(root) == root and Path.dirname(root) == "/tmp" and
             String.starts_with?(Path.basename(root), "ipse-native-seed-")

    assert File.lstat!(root).type == :directory
    {:ok, uid} = Ipse.Runner.protected_current_uid()
    root_stat = File.stat!(root)
    assert root_stat.uid == uid and Bitwise.band(root_stat.mode, 0o077) == 0

    for child <- ~w(home work runtime checkpoints),
        do: assert(File.lstat!(Path.join(root, child)).type == :directory)

    assert Path.expand(audit_path) == audit_path and Path.dirname(audit_path) == "/tmp"
    assert String.starts_with?(Path.basename(audit_path), "ipse-native-seed-audit-")
    assert File.lstat!(audit_path).type == :regular

    seed = read(Path.join(root, "manifest.json"))
    assert seed["kind"] in ~w(smoke initial) and seed["root"] == root
    assert not File.exists?(Path.join(root, "inflight.json"))
    audit = read(audit_path)
    expected_count = if seed["kind"] == "smoke", do: 7, else: 2000
    assert audit["root"] == root and audit["verified_records"] == expected_count
    assert audit["unchanged_root"] and audit["unchanged_control"]
    assert audit["manifest"]["path"] == Path.join(root, "manifest.json")
    assert audit["verified_rows"]["path"] == audit_path <> ".rows.json"
    assert audit["audit_source"]["path"] == audit_path <> ".driver.ex"
    assert fingerprint(audit["manifest"]["path"]) === audit["manifest"]
    assert fingerprint(audit["verified_rows"]["path"]) === audit["verified_rows"]
    assert fingerprint(audit["audit_source"]["path"]) === audit["audit_source"]

    assert audit["audit_source"]["sha256"] ==
             JSON.sha256(File.read!("dev/knowledge/native_notes_seed.ex"))

    Enum.each(seed["files"], &verify/1)

    reports =
      for i <- 1..length(seed["plan"]), do: read(Path.join(root, "checkpoints/report-#{i}.json"))

    for i <- 1..length(reports) do
      closed = read(Path.join(root, "checkpoints/closed-#{i}.json"))
      assert closed["index"] == i and closed["exit_code"] == 0
      verify(closed["report"])
      verify(closed["log"])
    end

    for report <- reports, source <- report["sources"], do: verify(source)

    records =
      Enum.reduce(reports, %{}, fn report, acc -> Map.merge(acc, report["new_records"]) end)

    rows = read(audit["verified_rows"]["path"])
    assert length(rows) == expected_count and map_size(records) == expected_count
    assert audit["rows_sha256"] == JSON.digest([rows])

    for row <- rows do
      rec = Map.fetch!(records, Integer.to_string(row["number"]))

      assert row["key"] == rec["key"] and
               row["record_sha256"] == JSON.sha256(Collection.Migration.encode(rec["value"]))
    end

    {:ok, _} = Application.ensure_all_started(:ipse)
    home = Path.join(root, "home")
    cwd = Path.join(root, "work")
    {:ok, binding} = ProjectIdentity.existing(home, cwd)

    {:ok, namespace} =
      Ipse.Extension.SemanticConsent.namespace(binding["project_id"], "knowledge")

    {:ok, control} =
      Consent.existing_snapshot(SemanticAdmission.control_root(home), binding["project_id"])

    assert JSON.digest([control]) == List.last(reports)["control_sha256"]

    {:ok, current_root} =
      ObservedRead.read(SemanticAdmission.collection_root(home), namespace, %{"op" => "snapshot"})

    assert current_root["value"] === audit["snapshot"] and
             current_root["witness"]["root_sha256"] == audit["root_sha256"]

    assert Enum.all?(control["operations"], fn {_, row} -> row["status"] == "settled" end)
    assert Enum.all?(control["compacted"], fn {_, row} -> Enum.at(row, 4) == "settled" end)

    dir = Path.join(root, "turnover")
    assert {:error, :enoent} = File.lstat(dir)
    seed_source = "dev/knowledge/native_notes_seed.ex"
    seed_source_hash = JSON.sha256(File.read!(seed_source))
    Code.require_file(seed_source)
    assert seed["plan"] === apply(Ipse.Development.NativeNotesSeed, :plan, [seed["kind"]])
    workload_source = "dev/knowledge/native_notes_workload.ex"
    workload_hash = JSON.sha256(File.read!(workload_source))
    Code.require_file(workload_source)

    plan =
      if seed["kind"] == "initial",
        do: apply(Ipse.Development.NativeNotesWorkload, :calendar, [20]),
        else: smoke_calendar()

    first_day = hd(plan["days"])["process_offset_day"]
    first_quota_period = div(seed["created_wall_ms"] + first_day * @day, @day) * @day

    times =
      Enum.map(control["operations"], fn {_, row} -> row["created_at_ms"] end) ++
        Enum.map(control["compacted"], fn {_, row} -> Enum.at(row, 3) end)

    assert Enum.all?(times, &(JSON.safe_uint?(&1) and &1 < first_quota_period))

    expiry = control["policy"]["expires_at_ms"]
    final_start = seed["created_wall_ms"] + List.last(plan["days"])["process_offset_day"] * @day

    renewal_day =
      if final_start >= expiry do
        candidate =
          plan["days"]
          |> Enum.filter(
            &(seed["created_wall_ms"] + &1["process_offset_day"] * @day + @day <= expiry)
          )
          |> List.last()

        assert is_map(candidate)
        candidate["process_offset_day"]
      end

    plan =
      if renewal_day do
        update_in(plan["days"], fn days ->
          Enum.map(days, fn day ->
            if day["process_offset_day"] == renewal_day,
              do: Map.update!(day, "actions", &[%{"op" => "renew"} | &1]),
              else: day
          end)
        end)
      else
        plan
      end

    segments = apply(Ipse.Development.NativeNotesWorkload, :segments, [plan, maximum])
    assert segments != []
    assert Enum.all?(segments, &(&1["daily_required_quota_excess"] == 0))
    segment_digests = Map.new(segments, &{Integer.to_string(&1["index"]), JSON.digest([&1])})

    recorded = audit["recorded_event_times"]["maxima_ms"] |> Map.values() |> Enum.max()
    seed_day = List.last(seed["plan"])["day"]
    real_bound = System.system_time(:millisecond) + seed_day * @day
    prior_virtual = max(recorded, real_bound)
    first_day = hd(segments)["process_offset_day"]
    assert prior_virtual < seed["created_wall_ms"] + first_day * @day

    File.mkdir!(dir)
    File.chmod!(dir, 0o700)
    File.cp!(__ENV__.file, Path.join(dir, "driver.exs"))
    File.cp!(seed_source, Path.join(dir, "seed.ex"))
    File.cp!(workload_source, Path.join(dir, "workload.ex"))
    File.cp!("test/support/managed_clock_lifecycle.exs", Path.join(dir, "clock.exs"))
    assert JSON.sha256(File.read!(Path.join(dir, "seed.ex"))) == seed_source_hash
    assert JSON.sha256(File.read!(Path.join(dir, "workload.ex"))) == workload_hash
    save(Path.join(dir, "segments.json"), segments)
    save(Path.join(dir, "records.json"), Map.new(records, fn {n, v} -> {"seed/" <> n, v} end))

    files =
      [
        fingerprint(Path.join(dir, "driver.exs")),
        fingerprint(Path.join(dir, "seed.ex")),
        fingerprint(Path.join(dir, "workload.ex")),
        fingerprint(Path.join(dir, "clock.exs")),
        fingerprint(audit_path),
        audit["verified_rows"],
        audit["manifest"]
      ] ++ seed["files"]

    save(Path.join(dir, "manifest.json"), %{
      "version" => 1,
      "root" => root,
      "seed_created_wall_ms" => seed["created_wall_ms"],
      "initial_virtual_bound" => prior_virtual,
      "initial_bound_scope" =>
        "conservative current real time plus the last seed offset; assumes no backwards real-clock step since seed closure",
      "initial_snapshot" => audit["snapshot"],
      "initial_root_sha256" => audit["root_sha256"],
      "initial_control_sha256" => List.last(reports)["control_sha256"],
      "seed_sources" => Enum.flat_map(reports, & &1["sources"]),
      "records_file" => fingerprint(Path.join(dir, "records.json")),
      "segments_file" => fingerprint(Path.join(dir, "segments.json")),
      "segment_count" => length(segments),
      "segment_digests" => segment_digests,
      "seed_kind" => seed["kind"],
      "maximum_effects_per_segment" => maximum,
      "renewal_process_day" => renewal_day,
      "planned_main_turns" => if(seed["kind"] == "initial", do: plan["main_turns"], else: 0),
      "files" => files,
      "qualification" => false
    })

    IO.puts("NATIVE_NOTES_TURNOVER_INITIALIZED=#{root} segments=#{length(segments)}")
  end

  def main(["--run", root, count_arg]) do
    Process.flag(:max_heap_size, %{size: 64_000_000, kill: true, error_logger: true})
    m = manifest(root)
    dir = Path.join(root, "turnover")

    assert JSON.sha256(File.read!(__ENV__.file)) ==
             JSON.sha256(File.read!(Path.join(dir, "driver.exs")))

    Enum.each(m["files"], &verify/1)
    verify(m["records_file"])
    verify(m["segments_file"])
    for source <- m["seed_sources"], do: verify(source)
    Code.require_file(Path.join(dir, "seed.ex"))
    Code.require_file(Path.join(dir, "workload.ex"))

    segments = read(m["segments_file"]["path"])
    assert length(segments) == m["segment_count"]
    assert map_size(m["segment_digests"]) == m["segment_count"]
    assert Enum.map(segments, & &1["index"]) == Enum.to_list(1..m["segment_count"])

    assert Enum.all?(
             segments,
             &(JSON.digest([&1]) == m["segment_digests"][Integer.to_string(&1["index"])])
           )

    segments = List.to_tuple(segments)

    assert not File.exists?(Path.join(dir, "inflight.json")),
           "inspect retained in-flight effect; never replay automatically"

    completed = closed(root, m)
    count = String.to_integer(count_arg)
    remaining = m["segment_count"] - length(completed)
    assert remaining > 0 and count in 1..remaining

    records =
      Enum.reduce(completed, read(m["records_file"]["path"]), fn report, acc ->
        Map.merge(acc, report["new_records"])
      end)

    last = List.last(completed)

    initial = %{
      records: records,
      snapshot: if(last, do: last["snapshot"], else: m["initial_snapshot"]),
      root_sha256: if(last, do: last["root_sha256"], else: m["initial_root_sha256"]),
      control_sha256: if(last, do: last["control_sha256"], else: m["initial_control_sha256"]),
      previous_virtual_ms:
        if(last, do: last["ended_virtual_ms"], else: m["initial_virtual_bound"])
    }

    Enum.reduce((length(completed) + 1)..(length(completed) + count), initial, fn i, state ->
      segment = elem(segments, i - 1)
      assert segment["index"] == i and segment["daily_required_quota_excess"] == 0
      group = segment["actions"]
      day = segment["process_offset_day"]
      anchor_path = Path.join(dir, "clock-day-#{day}.json")
      now = System.system_time(:millisecond)

      anchor =
        if File.exists?(anchor_path) do
          read(anchor_path)
        else
          {:ok, planned} =
            apply(Ipse.Development.NativeNotesWorkload, :clock_day, [
              m["seed_created_wall_ms"],
              day,
              now,
              state.previous_virtual_ms
            ])

          save(anchor_path, planned)
          planned
        end

      assert {:ok, _} =
               apply(Ipse.Development.NativeNotesWorkload, :clock_now, [
                 anchor,
                 now,
                 state.previous_virtual_ms
               ])

      resolved =
        Enum.map(group, fn action ->
          Map.put(
            action,
            "target_record",
            if(action["target"], do: Map.fetch!(state.records, action["target"]), else: nil)
          )
        end)

      input = %{
        "index" => i,
        "segment" => segment,
        "actions" => resolved,
        "anchor" => anchor,
        "previous_virtual_ms" => state.previous_virtual_ms,
        "snapshot" => state.snapshot,
        "root_sha256" => state.root_sha256,
        "control_sha256" => state.control_sha256,
        "manifest_sha256" => JSON.sha256(File.read!(Path.join(dir, "manifest.json")))
      }

      input_path = Path.join(dir, "input-#{i}.json")

      if File.exists?(input_path),
        do: assert(read(input_path) === input),
        else: save(input_path, input)

      paths =
        Path.wildcard(Path.join(root, "stdio-runtime/*/ebin")) |> Enum.flat_map(&["-pa", &1])

      {output, status} =
        System.cmd(
          Path.join(root, "pty"),
          ["--assertion", System.find_executable("elixir"), "--erl", "+S 2:2 +C multi_time_warp"] ++
            paths ++ [Path.join(dir, "driver.exs"), "--child", root, Integer.to_string(i)],
          stderr_to_stdout: true,
          env: [
            {"LD_PRELOAD", Path.join(root, "clock.so")},
            {"IPSE_TEST_CLOCK_OFFSET_MS", Integer.to_string(anchor["offset_ms"])},
            {"HOME", root},
            {"IPSE_HOME", Path.join(root, "home")},
            {"TMPDIR", root}
          ]
        )

      log = Path.join(dir, "segment-#{i}-#{Usage.id()}.log")
      File.write!(log, output, [:exclusive])
      File.chmod!(log, 0o600)
      assert status == 0, "pilot segment #{i} failed; retain in-flight and inspect #{log}"
      assert read(Path.join(dir, "inflight.json"))["index"] == i
      report = Path.join(dir, "report-#{i}.json")
      result = read(report)

      assert result["index"] == i and
               result["input_sha256"] == JSON.sha256(File.read!(input_path))

      save(Path.join(dir, "closed-#{i}.json"), %{
        "index" => i,
        "exit_code" => status,
        "input" => fingerprint(input_path),
        "report" => fingerprint(report),
        "log" => fingerprint(log)
      })

      File.rm!(Path.join(dir, "inflight.json"))
      assert :ok = Ipse.Runner.protected_sync_directory(dir)
      IO.puts("NATIVE_NOTES_TURNOVER_CLOSED=#{i} effects=#{length(group)} day=#{day}")

      %{
        records: Map.merge(state.records, result["new_records"]),
        snapshot: result["snapshot"],
        root_sha256: result["root_sha256"],
        control_sha256: result["control_sha256"],
        previous_virtual_ms: result["ended_virtual_ms"]
      }
    end)

    for source <- m["seed_sources"], do: verify(source)
  end

  def main(["--child", root, index]) do
    Process.flag(:max_heap_size, %{size: 16_000_000, kill: true, error_logger: true})
    i = String.to_integer(index)
    m = manifest(root)
    dir = Path.join(root, "turnover")

    assert JSON.sha256(File.read!(__ENV__.file)) ==
             JSON.sha256(File.read!(Path.join(dir, "driver.exs")))

    {:ok, _} = Application.ensure_all_started(:ipse)
    {:ok, _} = Ipse.Session.Lock.acquire(Path.join(dir, "runner.lock"))
    guard = Ipse.Session.Lock.current()

    try do
      assert not File.exists?(Path.join(dir, "inflight.json")),
             "unconfirmed prior effect; inspect without replay"

      Enum.each(m["files"], &verify/1)
      assert not File.exists?(Path.join(dir, "closed-#{i}.json"))
      input_path = Path.join(dir, "input-#{i}.json")
      input = read(input_path)
      assert input["index"] == i
      assert input["manifest_sha256"] == JSON.sha256(File.read!(Path.join(dir, "manifest.json")))

      segment = input["segment"]
      assert segment["index"] == i and segment["daily_required_quota_excess"] == 0
      assert JSON.digest([segment]) == m["segment_digests"][Integer.to_string(i)]
      assert Enum.map(input["actions"], &Map.delete(&1, "target_record")) === segment["actions"]

      assert read(Path.join(dir, "clock-day-#{segment["process_offset_day"]}.json")) ===
               input["anchor"]

      if i == 1 do
        assert input["snapshot"] === m["initial_snapshot"] and
                 input["root_sha256"] == m["initial_root_sha256"]

        assert input["control_sha256"] == m["initial_control_sha256"] and
                 input["previous_virtual_ms"] == m["initial_virtual_bound"]
      else
        prior = read(Path.join(dir, "closed-#{i - 1}.json"))
        assert prior["index"] == i - 1 and prior["exit_code"] == 0
        verify(prior["report"])
        previous = read(prior["report"]["path"])

        assert input["snapshot"] === previous["snapshot"] and
                 input["root_sha256"] == previous["root_sha256"]

        assert input["control_sha256"] == previous["control_sha256"] and
                 input["previous_virtual_ms"] == previous["ended_virtual_ms"]
      end

      assert System.get_env("IPSE_TEST_CLOCK_OFFSET_MS") ==
               Integer.to_string(input["anchor"]["offset_ms"])

      Code.require_file(Path.join(dir, "seed.ex"))
      Code.require_file(Path.join(dir, "workload.ex"))
      clock_check(input["anchor"], input["previous_virtual_ms"])
      Code.require_file(Path.join(dir, "clock.exs"))
      {:ok, _} = Application.ensure_all_started(:ipse)
      apply(Ipse.Test.ManagedClockLifecycle, :check_stdio_clock, [root])
      home = Path.join(root, "home")
      cwd = Path.join(root, "work")

      for key <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
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
      config = Map.merge(config, %{provider_module: NoModel, fixture_root: root})
      {:ok, binding} = ProjectIdentity.existing(home, cwd)
      {:ok, ns} = Ipse.Extension.SemanticConsent.namespace(binding["project_id"], "knowledge")
      collection = SemanticAdmission.collection_root(home)
      control_root = SemanticAdmission.control_root(home)
      {:ok, control} = Consent.existing_snapshot(control_root, binding["project_id"])
      {:ok, observed} = ObservedRead.read(collection, ns, %{"op" => "snapshot"})

      assert observed["value"] === input["snapshot"] and
               observed["witness"]["root_sha256"] == input["root_sha256"]

      assert JSON.digest([control]) == input["control_sha256"]

      save(Path.join(dir, "inflight.json"), %{
        "index" => i,
        "manifest_sha256" => input["manifest_sha256"],
        "input_sha256" => JSON.sha256(File.read!(input_path))
      })

      {new_records, after_snapshot, after_control, _, last_virtual} =
        Enum.reduce(
          input["actions"],
          {%{}, observed, control, 0, input["previous_virtual_ms"]},
          fn action, {added, snapshot, current_control, step, previous_virtual} ->
            clock_check(input["anchor"], previous_virtual)

            next_step =
              if action["op"] in ~w(capture correct supersede update), do: step + 1, else: step

            new_record = effect(action, action["target_record"], config, cwd, root, next_step)
            {:ok, next_snapshot} = ObservedRead.read(collection, ns, %{"op" => "snapshot"})
            {:ok, next_control} = Consent.existing_snapshot(control_root, binding["project_id"])

            if action["op"] == "renew" do
              assert next_snapshot["value"] === snapshot["value"] and
                       next_snapshot["witness"]["root_sha256"] ==
                         snapshot["witness"]["root_sha256"]

              assert next_control["sequence"] == current_control["sequence"] and
                       next_control["epoch"] == current_control["epoch"] + 1

              assert Map.delete(next_control["policy"], "expires_at_ms") ===
                       Map.delete(current_control["policy"], "expires_at_ms")

              assert next_control["policy"]["expires_at_ms"] >
                       current_control["policy"]["expires_at_ms"]
            else
              assert next_snapshot["value"]["generation"] == snapshot["value"]["generation"] + 1
              assert next_control["sequence"] == current_control["sequence"] + 1
              assert next_control["epoch"] == current_control["epoch"]
            end

            time = clock_check(input["anchor"], previous_virtual)

            added =
              if action["result"], do: Map.put(added, action["result"], new_record), else: added

            {added, next_snapshot, next_control, next_step, time}
          end
        )

      assert not File.exists?(Path.join(root, "unexpected-model"))

      save(Path.join(dir, "report-#{i}.json"), %{
        "index" => i,
        "input_sha256" => JSON.sha256(File.read!(input_path)),
        "new_records" => new_records,
        "snapshot" => after_snapshot["value"],
        "root_sha256" => after_snapshot["witness"]["root_sha256"],
        "control_sha256" => JSON.digest([after_control]),
        "ended_virtual_ms" => last_virtual,
        "qualification" => false
      })
    after
      Ipse.Session.Lock.release(guard)
    end
  end

  defp smoke_calendar do
    days =
      @smoke_actions
      |> Enum.group_by(& &1["day"])
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {day, actions} ->
        %{
          "day" => day,
          "process_offset_day" => day,
          "required_quota_excess" => 0,
          "actions" => actions
        }
      end)

    %{"kind" => "native_annual_action_calendar", "days" => days}
  end

  defp clock_check(anchor, previous) do
    virtual = System.system_time(:millisecond)
    real = virtual - anchor["offset_ms"]

    assert {:ok, %{"virtual_ms" => ^virtual}} =
             apply(Ipse.Development.NativeNotesWorkload, :clock_now, [anchor, real, previous])

    virtual
  end

  defp effect(%{"op" => op} = action, target, config, cwd, root, step)
       when op in ~w(capture correct supersede update) do
    dir = Path.join(config.home, "sessions")

    {:ok, session} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: cwd, state_dir: dir, subscriber: self()}
      )

    :ok = Ipse.Session.Lock.track_session(session)
    id = Session.info(session).id
    {:ok, channel} = Session.open_input_channel(session, self())

    text = statement(action["result"])

    command =
      case op do
        "capture" -> "/remember ordinary " <> text
        "correct" -> "/correct " <> target["key"] <> " " <> text
        _ -> "/supersede " <> target["key"] <> " " <> text
      end

    File.write!(Path.join(root, "supersession-input-#{step}"), command)
    IO.write("IPSE_SUPERSESSION_READ_#{step}> ")

    assert {:ok, ^command, witness} =
             Session.observe_channel(session, channel, %{"kind" => "prompt"}, 30_000)

    {:ok, ticket} = Session.stage_input(session, channel, command, witness)
    {:ok, %{"render_id" => render}} = Session.prepare_assertion(session, channel, command, ticket)

    {:ok, input, witnessed} =
      Session.observe_channel(
        session,
        channel,
        %{"kind" => "assertion", "render_id" => render},
        30_000
      )

    :ok = Session.accept_assertion_observed(session, channel, render, input, witnessed)
    assert_receive {:ipse, ^session, {:done, :ok}}, 30_000
    :ok = Session.close_confirmed(session)
    {:ok, events} = Journal.load(dir, id)
    {:ok, _} = Session.Saved.restore(events, id)
    {:ok, %{"release_claim" => "signed_release_claim"}} = Session.Saved.inspect_saved(dir, id)
    refute Enum.any?(events, &(&1["type"] in ~w(request_admitted inference_dispatch_intent)))

    if op == "capture" do
      [event] =
        Enum.filter(
          events,
          &(&1["type"] == "extension_action_result" and
              get_in(&1, ["request", "op"]) == "collection.managed" and
              get_in(&1, ["outcome", "status"]) == "ok")
        )

      [change] = event["request"]["request"]["changes"]
      assert change["value"]["text"] == text and change["value"]["category"] == "ordinary"
      %{"key" => change["key"], "value" => change["value"]}
    else
      [intent] = Enum.filter(events, &(&1["type"] == "managed_supersession_intent"))

      [result] =
        Enum.filter(
          events,
          &(&1["type"] == "managed_supersession_result" and
              &1["operation_id"] == intent["operation_id"])
        )

      assert result["status"] == "settled" and intent["facts"]["target"]["key"] == target["key"]
      assert intent["facts"]["mode"] == if(op == "correct", do: "ordinary", else: "temporal")
      assert intent["facts"]["replacement"]["value"]["text"] == text
      intent["facts"]["replacement"]
    end
  end

  defp effect(%{"op" => "renew"}, _target, config, cwd, _root, _step) do
    guarded_peer(fn ->
      assert Ipse.CLI.run([
               "knowledge",
               "enable",
               "--cwd",
               cwd,
               "--config",
               Path.join(config.home, "config.json"),
               "--no-project-config"
             ]) == 0
    end)

    nil
  end

  defp effect(%{"op" => op}, target, config, cwd, _root, _step) when op in ~w(forget expire) do
    guarded_peer(fn ->
      result =
        if op == "forget",
          do: Management.forget(config, cwd, target["key"]),
          else: Management.expire(config, cwd, target["key"])

      assert {:ok, value} = result
      assert value["storage_status"] == "settled"

      assert {:ok,
              %{
                "journal_status" => "settled",
                "control_status" => "settled",
                "replayed" => false
              }} = Management.operation(config, cwd, value["journal_id"])
    end)

    nil
  end

  defp statement(alias_name) when is_binary(alias_name) do
    prefix = "Annual native fixture #{alias_name}: "
    body = Enum.map_join(1..17, " ", &JSON.sha256("#{alias_name}:#{&1}"))
    assert byte_size(prefix) < 1024
    prefix <> binary_part(body, 0, 1024 - byte_size(prefix))
  end

  defp guarded_peer(fun) do
    owner = self()

    {worker, ref} =
      spawn_monitor(fn ->
        receive do
          {:begin_management, ^owner} -> :ok
        end

        fun.()
        send(owner, {:management_settled, self()})
      end)

    :ok = Ipse.Session.Lock.track_in(Ipse.Session.Lock.current(), worker, :peer)
    send(worker, {:begin_management, owner})

    receive do
      {:management_settled, ^worker} ->
        Process.demonitor(ref, [:flush])

      {:DOWN, ^ref, :process, ^worker, reason} ->
        raise "management worker failed: #{inspect(reason)}"
    after
      120_000 -> raise "management worker did not confirm; leave in-flight marker"
    end

    :ok
  end

  defp manifest(root) do
    m = read(Path.join(root, "turnover/manifest.json"))
    assert m["version"] == 1 and m["root"] == root and m["seed_kind"] in ~w(smoke initial)
    assert is_integer(m["segment_count"]) and m["segment_count"] > 0
    m
  end

  defp closed(root, m) do
    dir = Path.join(root, "turnover")

    Enum.reduce_while(1..m["segment_count"], [], fn i, acc ->
      path = Path.join(dir, "closed-#{i}.json")

      if File.exists?(path) do
        c = read(path)
        assert c["index"] == i and c["exit_code"] == 0
        verify(c["input"])
        verify(c["report"])
        verify(c["log"])
        {:cont, [read(c["report"]["path"]) | acc]}
      else
        assert length(Path.wildcard(Path.join(dir, "closed-*.json"))) == length(acc)
        {:halt, acc}
      end
    end)
    |> Enum.reverse()
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

Ipse.Development.NativeNotesTurnover.main(System.argv())
