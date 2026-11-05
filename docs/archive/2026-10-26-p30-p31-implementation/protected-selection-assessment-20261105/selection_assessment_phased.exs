defmodule Ipse.Test.SelectionAssessmentPhased do
  @moduledoc false
  import ExUnit.Assertions
  alias Ipse.{Session, Journal, JSON}
  alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission}

  def run(root, phase_name) when phase_name in ~w(setup selection assessment) do
    true = :sys.get_state(Session.Input).entries === %{}
    home = Path.join(root, "home")
    cwd = Path.join(root, "project")
    dir = Path.join(root, "sessions")
    for path <- [home, cwd, dir], do: File.mkdir_p!(path)
    File.chmod!(home, 0o700)
    System.put_env("IPSE_HOME", home)
    path = Path.join(home, "config.json")
    prior = if phase_name == "setup", do: nil, else: load(root, "setup-checkpoint.json")
    if prior, do: true = prior["config_sha256"] === JSON.sha256(File.read!(path))
    port = if prior, do: URI.parse(prior["base_url"]).port, else: 0
    {:ok, calls} = Agent.start_link(fn -> [] end)

    phase_data =
      case phase_name do
        "setup" -> %{kind: :pending, step: 0}
        "selection" -> %{kind: :selection, step: 0, arguments: prior["arguments"]}
        "assessment" -> %{kind: :assessment, step: 0, key: prior["pending"]}
      end

    {:ok, phase} = Agent.start_link(fn -> phase_data end)
    {base, listener, server} = server(calls, phase, port)
    started = System.monotonic_time(:millisecond)

    try do
      if prior do
        true = base === prior["base_url"]
      else
        File.write!(
          Path.join(cwd, "synthetic.txt"),
          "Synthetic local source for a proposed interpretation.\n"
        )

        config_file(path, base)
        cli = ["--cwd", cwd, "--config", path, "--no-project-config"]
        assert Ipse.CLI.run(["knowledge", "experiment", "advice", "2", "1800"] ++ cli) == 0
      end

      {:ok, effective} =
        Ipse.Config.resolve(cwd, home, [config: path, project_config: false], %{})

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

      {:ok, runtime} = Ipse.Config.runtime(effective, client)
      {:ok, project} = ProjectIdentity.existing(home, cwd)
      control = SemanticAdmission.control_root(home)
      collection = SemanticAdmission.collection_root(home)
      {:ok, policy} = Consent.existing_snapshot(control, project["project_id"])
      true = policy["policy"]["limits"]["model_calls"] === 2

      context = %{
        root: root,
        home: home,
        cwd: cwd,
        dir: dir,
        path: path,
        base: base,
        calls: calls,
        runtime: runtime,
        project: project,
        control: control,
        collection: collection,
        policy: policy
      }

      case phase_name do
        "setup" -> setup(context)
        "selection" -> select(context, prior)
        "assessment" -> assess(context, prior)
      end

      save(root, phase_name <> "-phase-status.json", %{
        status: "passed",
        elapsed_ms: System.monotonic_time(:millisecond) - started
      })
    rescue
      error ->
        save(root, phase_name <> "-phase-status.json", %{
          status: "failed",
          exception_class: Atom.to_string(error.__struct__),
          elapsed_ms: System.monotonic_time(:millisecond) - started
        })

        reraise(error, __STACKTRACE__)
    after
      :gen_tcp.close(listener)
      Task.shutdown(server, :brutal_kill)
      Agent.stop(calls)
      Agent.stop(phase)
    end
  end

  defp setup(c) do
    {:ok, source} = start(c.runtime, c.cwd, c.dir)
    source_id = Session.info(source).id
    namespace = :sys.get_state(source).config.semantic_admission["pin"]["namespace"]
    {:ok, channel} = Session.open_input_channel(source, self())

    texts =
      for n <- 1..8 do
        marker = "~S#{n}~ café 雪 "
        marker <> String.duplicate("x", 700 - byte_size(marker))
      end

    for {text, step} <- Enum.with_index(texts, 1) do
      command = "/remember ordinary " <> text
      File.write!(Path.join(c.root, "supersession-input-#{step}"), command)
      IO.write("IPSE_SUPERSESSION_READ_#{step}> ")

      assert {:ok, ^command, witness} =
               Session.observe_channel(source, channel, %{"kind" => "prompt"}, 30000)

      assert {:ok, ticket} = Session.stage_input(source, channel, command, witness)

      assert {:ok, %{"render_id" => render}} =
               Session.prepare_assertion(source, channel, command, ticket)

      assert {:ok, input, observed} =
               Session.observe_channel(
                 source,
                 channel,
                 %{"kind" => "assertion", "render_id" => render},
                 30000
               )

      assert :ok = Session.accept_assertion_observed(source, channel, render, input, observed)
      assert_receive {:ipse, ^source, {:done, :ok}}, 30000
    end

    close(source, c.dir, source_id)
    originals_before = fingerprints(c.dir, [source_id])
    save(c.root, "setup-originals-before.json", originals_before)

    {:ok, snapshot} =
      Collection.execute(c.collection, namespace, %{"op" => "snapshot"}, Ipse.Usage.id())

    {:ok, page} =
      Collection.scan_visible(
        c.collection,
        namespace,
        %{"op" => "scan", "after" => nil, "generation" => snapshot["generation"], "limit" => 16},
        Ipse.Usage.id()
      )

    true = page["next"] == nil and length(page["records"]) == 8
    keys = Enum.sort(Enum.map(page["records"], & &1["key"]))

    {:ok, seed} =
      start(
        %{c.runtime | approval: :deny, approval_origin: :default_headless, headless: true},
        c.cwd,
        c.dir
      )

    seed_id = Session.info(seed).id
    monitor = Process.monitor(seed)

    assert :ok =
             Session.prompt(
               seed,
               "Read the synthetic file and propose its interpretation using the capture tool."
             )

    observed = await_seed(seed, monitor, System.monotonic_time(:millisecond) + 30000, {[], 0})
    save(c.root, "setup-observed.json", observed)
    Process.demonitor(monitor, [:flush])

    closed =
      try do
        Session.close_confirmed(seed)
      catch
        _, _ -> :unconfirmed
      end

    save(c.root, "setup-close.json", %{confirmed: closed === :ok})
    true = observed.status === "done_ok"
    true = closed === :ok
    {:ok, events} = Journal.load(c.dir, seed_id)
    assert {:ok, _} = Session.Saved.restore(events, seed_id)
    true = :sys.get_state(Session.Input).entries === %{}
    pending = assert_pending(events)
    true = originals_unchanged?(originals_before, fingerprints(c.dir, [source_id]))
    originals = fingerprints(c.dir, [source_id, seed_id])

    {:ok, before} =
      Collection.execute(c.collection, namespace, %{"op" => "snapshot"}, Ipse.Usage.id())

    true = before["generation"] === snapshot["generation"] + 1

    for key <- keys do
      {:ok, %{"record" => record}} =
        Collection.execute(
          c.collection,
          namespace,
          %{"op" => "get", "key" => key},
          Ipse.Usage.id()
        )

      true = is_map(record)
    end

    {:ok, before_policy} = Consent.existing_snapshot(c.control, c.project["project_id"])
    wires = Agent.get(c.calls, & &1)
    true = Enum.count(wires, &(&1.kind == :main)) === 5
    true = Enum.count(wires, &(&1.kind == :decision)) === 0

    args = %{
      "query" => "Which current synthetic references support café 雪?",
      "packs" => [
        %{"id" => "first", "members" => Enum.take(keys, 4)},
        %{"id" => "second", "members" => Enum.drop(keys, 4)}
      ]
    }

    checkpoint = %{
      "version" => 1,
      "status" => "known_closed",
      "base_url" => c.base,
      "config_sha256" => JSON.sha256(File.read!(c.path)),
      "source_id" => source_id,
      "seed_id" => seed_id,
      "namespace" => namespace,
      "pending" => pending,
      "keys" => keys,
      "originals" => originals,
      "snapshot" => before,
      "policy" => before_policy,
      "arguments" => args,
      "main_wire_calls" => 5,
      "decision_wire_calls" => 0
    }

    save(c.root, "frozen-inputs.json", %{
      "version" => 1,
      "selection_arguments" => args,
      "selection_arguments_sha256" => JSON.digest([args]),
      "assessment_key" => pending,
      "assessment_original_sha256" => originals[seed_id <> ".jsonl"]["bytes"],
      "note_original_sha256" => originals[source_id <> ".jsonl"]["bytes"],
      "policy_sha256" => JSON.digest([before_policy["policy"]]),
      "first_decision_prediction" => "not_yet_observed",
      "route" => "registered_synthetic_numeric_loopback",
      "quality_labels" => "unavailable",
      "quality_disposition" => "unverified"
    })

    save(c.root, "setup-checkpoint.json", checkpoint)
  end

  defp assert_pending(events) do
    [capture] =
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "op"]) == "collection.managed")
      )

    true = capture["outcome"]["status"] === "ok"
    [%{"key" => pending}] = capture["request"]["request"]["changes"]
    true = String.starts_with?(pending, "pending.")
    parent = capture["parent_invocation_id"]

    result = fn op ->
      events
      |> Enum.find(
        &(&1["type"] == "extension_action_result" and &1["parent_invocation_id"] == parent and
            get_in(&1, ["request", "op"]) == op)
      )
      |> get_in(["outcome", "value"])
    end

    page = result.("source.read")
    quote = result.("source.quote")

    [expected] =
      for outcome <- events,
          outcome["type"] == "lifecycle_tool_outcome",
          intent =
            Enum.find(
              events,
              &(&1["type"] == "lifecycle_tool_intent" and &1["tool_id"] == outcome["tool_id"])
            ),
          intent && get_in(intent, ["input", "name"]) == "read",
          facts = Map.take(outcome, ~w(status approval duration_ms)) |> Map.put("tool", "read"),
          text = Jason.encode!(facts),
          JSON.sha256(text) === page["content_sha256"],
          do: text

    true =
      page["text"] === expected and page["kind"] === "tool.outcome" and
        page["origin"] === "typed_host_outcome" and page["complete"] === true and
        page["offset"] === 0 and page["original_bytes"] === byte_size(expected)

    true =
      quote["start_byte"] === 0 and quote["end_byte"] === byte_size(expected) and
        quote["content_sha256"] === JSON.sha256(expected) and
        quote["quote_sha256"] === JSON.sha256(expected)

    read_at =
      Enum.find_index(
        events,
        &(&1["type"] == "extension_action_result" and &1["parent_invocation_id"] == parent and
            get_in(&1, ["request", "op"]) == "source.read")
      )

    quote_at =
      Enum.find_index(
        events,
        &(&1["type"] == "extension_action_result" and &1["parent_invocation_id"] == parent and
            get_in(&1, ["request", "op"]) == "source.quote")
      )

    true = read_at < quote_at
    [transition] = Enum.filter(events, &(&1["type"] == "worker_input_root_transition"))

    input =
      Enum.find(
        events,
        &(&1["type"] == "worker_input_intent" and &1["input_id"] == transition["input_id"])
      )

    reads =
      events
      |> Enum.take_while(&(&1 !== input))
      |> Enum.filter(&(&1["type"] == "managed_read_observed"))
      |> Enum.flat_map(& &1["dependencies"])

    {:ok, deps} = Ipse.Session.ManagedReference.union([reads])
    true = Enum.frequencies_by(deps, & &1["version"]) === %{3 => 4, 4 => 8}
    true = JSON.digest(deps) === input["dependencies_sha256"]

    true =
      Enum.all?(
        Enum.filter(deps, &(&1["version"] == 3)),
        &(&1["collection"]["generation"] === 8 and &1["collection"]["floor"] === 8)
      )

    true = transition["evidence"]["fresh_dependency"]["collection"]["generation"] === 9

    true =
      Enum.any?(
        events,
        &(&1["type"] == "worker_input_result" and &1["input_id"] == input["input_id"] and
            &1["status"] == "delivered")
      )

    true =
      Enum.any?(
        events,
        &(&1["type"] == "extension_invocation_result" and &1["invocation_id"] == parent)
      )

    pending
  end

  defp select(c, p) do
    assert_checkpoint(c, p, 0)

    result =
      experiment(
        c.root,
        c.runtime,
        c.cwd,
        c.dir,
        c.calls,
        "selection",
        "Use ext__knowledge__select_shadow once with the supplied frozen alternatives; do not mutate or publish any note."
      )

    save(c.root, "selection-observed.json", %{
      output: result.output,
      main_wire_calls: Enum.count(Agent.get(c.calls, & &1), &(&1.kind == :main)),
      decision_wire_calls: Enum.count(Agent.get(c.calls, & &1), &(&1.kind == :decision))
    })

    assert_phase_wires(c, :selection)
    assert_selection(result, p["keys"])
    assert_checkpoint(c, p, 1)

    save(c.root, "selection-checkpoint.json", %{
      "status" => "known_closed",
      "output" => result.output,
      "main_wire_calls" => 2,
      "decision_wire_calls" => 1
    })
  end

  defp assess(c, p) do
    selected = load(c.root, "selection-checkpoint.json")
    true = selected["status"] === "known_closed"
    assert_checkpoint(c, p, 1)

    result =
      experiment(
        c.root,
        c.runtime,
        c.cwd,
        c.dir,
        c.calls,
        "assessment",
        "Use ext__knowledge__assess once for the pending candidate " <>
          p["pending"] <> ". Do not capture, accept, edit or publish any note."
      )

    save(c.root, "assessment-observed.json", %{
      output: result.output,
      main_wire_calls: Enum.count(Agent.get(c.calls, & &1), &(&1.kind == :main)),
      decision_wire_calls: Enum.count(Agent.get(c.calls, & &1), &(&1.kind == :decision))
    })

    assert_phase_wires(c, :assessment)

    assert %{
             "status" => "assessed",
             "key" => pending,
             "experimental" => true,
             "note_mutation" => "none"
           } = result.output

    true = pending === p["pending"]
    true = result.output["advice"] === %{"choice" => "keep_baseline", "reason" => "selected"}
    assert_checkpoint(c, p, 2)
    true = p["main_wire_calls"] + selected["main_wire_calls"] + 2 === 9
    true = p["decision_wire_calls"] + selected["decision_wire_calls"] + 1 === 2

    save(c.root, "result.json", %{
      "status" => "passed",
      "evidence_scope" => "synthetic_local_protocol",
      "quality" => "unverified",
      "default_strategy" => "unchanged",
      "native_assertions" => 8,
      "main_wire_calls" => 9,
      "decision_wire_calls" => 2,
      "settled_model_calls" => 2,
      "selection" =>
        Map.take(
          selected["output"],
          ~w(input_sha256 source_binding_sha256 allocation_bytes eligible_count eligible_rendered_bytes baseline candidate outcome)
        ),
      "assessment_advice" => result.output["advice"],
      "saved_and_idle" => true,
      "originals_unchanged" => true
    })
  end

  defp assert_checkpoint(c, p, expected_calls) do
    true = p["status"] === "known_closed"
    true = p["config_sha256"] === JSON.sha256(File.read!(c.path))

    {:ok, snapshot} =
      Collection.execute(c.collection, p["namespace"], %{"op" => "snapshot"}, Ipse.Usage.id())

    true = snapshot === p["snapshot"]

    true =
      originals_unchanged?(p["originals"], fingerprints(c.dir, [p["source_id"], p["seed_id"]]))

    {:ok, policy} = Consent.existing_snapshot(c.control, c.project["project_id"])
    before = p["policy"]
    true = policy["epoch"] === before["epoch"] and policy["policy"] === before["policy"]
    true = Map.take(policy["operations"], Map.keys(before["operations"])) === before["operations"]
    new = Map.drop(policy["operations"], Map.keys(before["operations"])) |> Map.values()
    true = length(new) === expected_calls
    true = Enum.all?(new, &(&1["status"] === "settled" and &1["actual"]["model_calls"] === 1))
    true = Enum.sum(Enum.map(new, & &1["actual"]["model_calls"])) === expected_calls

    if expected_calls > 0 do
      wires = Agent.get(c.calls, & &1)
      true = Enum.count(wires, &(&1.kind == :main)) in [0, 2]
      true = Enum.count(wires, &(&1.kind == :decision)) in [0, 1]
    end

    true = :sys.get_state(Session.Input).entries === %{}
  end

  defp assert_phase_wires(c, name) do
    wires = Agent.get(c.calls, & &1)
    true = Enum.count(wires, &(&1.kind == :main)) === 2
    true = Enum.count(wires, &(&1.kind == :decision)) === 1
    true = Enum.all?(wires, &(&1.phase === name))
  end

  defp assert_selection(selection, keys) do
    assert %{"status" => "selection_shadow", "context_mutation" => "none", "experimental" => true} =
             selection.output

    true = selection.output["eligible_count"] === 8
    true = selection.output["eligible_rendered_bytes"] > selection.output["allocation_bytes"]
    true = selection.output["allocation_bytes"] <= 8192
    true = selection.output["baseline"]["included"] > 4
    true = selection.output["candidate"]["included"] === 4
    true = Enum.sort(Enum.map(selection.output["reads"], & &1["key"])) === keys

    true =
      Enum.all?(
        selection.output["reads"],
        &(is_binary(&1["read_operation_id"]) and &1["revision"] > 0)
      )

    for read <- selection.output["reads"] do
      [event] =
        Enum.filter(
          selection.events,
          &(&1["type"] == "extension_action_result" and
              &1["operation_id"] == read["read_operation_id"])
        )

      true = event["request"]["op"] === "collection.call"
      true = event["request"]["request"] === %{"op" => "get", "key" => read["key"]}
      true = event["outcome"]["status"] === "ok"

      true =
        Map.take(event["outcome"]["value"]["record"], ~w(key revision sha256 bytes)) ===
          Map.take(read, ~w(key revision sha256 bytes))

      [observed] =
        Enum.filter(
          selection.events,
          &(&1["type"] == "managed_read_observed" and
              &1["operation_id"] == read["read_operation_id"])
        )

      true =
        Enum.any?(
          observed["dependencies"],
          &(&1["version"] == 4 and &1["subject"]["key"] == read["key"])
        )
    end
  end

  defp load(root, name), do: Path.join(root, name) |> File.read!() |> Jason.decode!()

  defp originals_unchanged?(before, current) do
    MapSet.new(Map.keys(before)) === MapSet.new(Map.keys(current)) and
      Enum.all?(before, fn {name, prior} ->
        now = current[name]

        if String.ends_with?(name, ".lock"),
          do:
            is_map(now) and Map.delete(now, "ctime") === Map.delete(prior, "ctime") and
              is_integer(now["ctime"]) and now["ctime"] >= prior["ctime"],
          else: now === prior
      end)
  end

  defp await_seed(seed, monitor, deadline, {errors, count}) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      %{
        status: "timeout",
        error_hashes: errors,
        error_count: count,
        error_hashes_truncated: count > 8
      }
    else
      receive do
        {:ipse, ^seed, {:done, status}} ->
          %{
            status:
              case status do
                :ok -> "done_ok"
                :error -> "done_error"
                :cancelled -> "done_cancelled"
                _ -> "done_other"
              end,
            error_hashes: errors,
            error_count: count,
            error_hashes_truncated: count > 8
          }

        {:ipse, ^seed, {:error, reason}} ->
          await_seed(
            seed,
            monitor,
            deadline,
            {Enum.take(
               errors ++ [JSON.sha256(:erlang.term_to_binary(reason, [:deterministic]))],
               8
             ), count + 1}
          )

        {:DOWN, ^monitor, :process, ^seed, _} ->
          %{
            status: "session_down",
            error_hashes: errors,
            error_count: count,
            error_hashes_truncated: count > 8
          }
      after
        remaining ->
          %{
            status: "timeout",
            error_hashes: errors,
            error_count: count,
            error_hashes_truncated: count > 8
          }
      end
    end
  end

  defp experiment(root, runtime, cwd, dir, calls, name, prompt) do
    for file <-
          ~w(managed-approval-input-ready managed-approval-control-checked managed-approval-exit-ready),
        do: File.rm(Path.join(root, file))

    {:ok, pid} = start(runtime, cwd, dir)
    id = Session.info(pid).id
    caller = self()
    returned = make_ref()

    watcher =
      Task.async(fn ->
        wait_file(Path.join(root, "managed-approval-input-ready"), 4500)
        assert :sys.get_state(pid).phase == :managed_approval
        File.write!(Path.join(root, "managed-approval-control-checked"), "checked")
        wait_idle(pid, 2000)
        File.write!(Path.join(root, "managed-approval-exit-ready"), "ready")

        receive do
          {^returned, ^caller} -> :ok
        after
          60_000 -> flunk("CLI caller did not acknowledge fixture completion")
        end
      end)

    IO.puts("IPSE_MANAGED_APPROVAL_CLI_READY")
    terminal = Ipse.CLI.Terminal.interact(pid, Process.monitor(pid), true, prompt, cwd)
    # Preserve terminal status before strict outcome checks.
    save(root, name <> "-terminal.json", %{"terminal_status" => terminal, "session_id" => id})
    send(watcher.pid, {returned, self()})
    Task.await(watcher, 5000)
    close(pid, dir, id)
    {:ok, events} = Journal.load(dir, id)
    assert terminal == 0

    assert [decision] =
             Enum.filter(
               events,
               &(&1["type"] == "extension_action_result" and
                   get_in(&1, ["request", "op"]) == "decision.create")
             )

    assert decision["outcome"]["status"] == "ok"
    refute Enum.any?(events, &(get_in(&1, ["request", "op"]) == "collection.managed"))

    assert Enum.any?(
             events,
             &(&1["type"] == "managed_output_release_result" and &1["decision"] == "current")
           )

    tool =
      if name == "selection", do: "ext__knowledge__select_shadow", else: "ext__knowledge__assess"

    output =
      Agent.get(calls, & &1)
      |> Enum.find_value(fn
        %{kind: :main, request: %{"messages" => messages}} ->
          Enum.find(messages, &(&1["role"] == "tool" and &1["tool_name"] == tool))

        _ ->
          nil
      end)

    assert is_map(output)
    value = Jason.decode!(output["content"])
    before = intent_ids(events)
    prior_calls = Agent.get(calls, & &1)
    {:ok, resumed} = start(runtime, cwd, dir, id)
    assert Session.info(resumed).phase == :idle
    assert Agent.get(calls, & &1) === prior_calls
    close(resumed, dir, id)
    {:ok, final} = Journal.load(dir, id)
    assert intent_ids(final) === before
    assert :sys.get_state(Session.Input).entries === %{}
    %{output: value, events: final}
  end

  defp start(config, cwd, dir, id \\ nil),
    do:
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         [config: config, cwd: cwd, state_dir: dir, subscriber: self()] ++
           if(id, do: [id: id], else: [])}
      )

  defp close(pid, dir, id) do
    assert :ok = Session.close_confirmed(pid)
    assert {:ok, events} = Journal.load(dir, id)
    assert {:ok, _} = Session.Saved.restore(events, id)
  end

  defp intent_ids(events),
    do:
      Enum.filter(
        events,
        &(&1["type"] in ~w(input_received extension_invocation_intent extension_action_intent worker_input_intent request_admitted inference_dispatch_intent))
      )

  defp fingerprints(dir, ids),
    do:
      Map.new(
        for id <- ids,
            kind <- ~w(jsonl lock),
            do: {id <> "." <> kind, file_pin(Path.join(dir, id <> "." <> kind))}
      )

  defp file_pin(path) do
    s = File.stat!(path, time: :posix)

    %{
      bytes: JSON.sha256(File.read!(path)),
      inode: s.inode,
      device: s.major_device,
      mode: s.mode,
      size: s.size,
      mtime: s.mtime,
      ctime: s.ctime
    }
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp wait_file(path, n) when n > 0 do
    if File.exists?(path),
      do: :ok,
      else:
        (
          Process.sleep(10)
          wait_file(path, n - 1)
        )
  end

  defp wait_file(_, _), do: flunk("native approval readiness unavailable")

  defp wait_idle(pid, n) when n > 0 do
    wait_idle_until(pid, System.monotonic_time(:millisecond) + n * 10)
  end

  defp wait_idle(_, _), do: flunk("experiment did not become idle")

  defp wait_idle_until(pid, deadline) do
    if System.monotonic_time(:millisecond) >= deadline,
      do: flunk("experiment did not become idle within its absolute fixture budget")

    reply =
      try do
        Session.info(pid)
      catch
        :exit, _ -> {:error, :idle_status_unavailable}
      end

    now = System.monotonic_time(:millisecond)

    case idle_observation(reply, now, deadline) do
      :idle ->
        :ok

      :waiting ->
        Process.sleep(min(10, deadline - now))
        wait_idle_until(pid, deadline)

      :expired ->
        flunk("experiment did not become idle within its absolute fixture budget")

      :unavailable ->
        flunk("Session status unavailable during idle coordination")
    end
  end

  defp idle_observation(_, now, deadline) when now >= deadline, do: :expired
  defp idle_observation(%{phase: :idle}, _, _), do: :idle
  defp idle_observation(%{phase: phase}, _, _) when is_atom(phase), do: :waiting
  defp idle_observation({:error, :session_share_frozen}, _, _), do: :waiting
  defp idle_observation(_, _, _), do: :unavailable

  defp save(root, name, value),
    do: File.write!(Path.join(root, name), Jason.encode!(value) <> "\n")

  defp config_file(path, base) do
    File.write!(
      path,
      Jason.encode!(%{
        "version" => 1,
        "profiles" => %{
          "main" => %{
            "provider" => "ollama",
            "model" => "synthetic",
            "base_url" => base,
            "max_output_tokens" => 64,
            "timeout_ms" => 20_000
          }
        },
        "roles" => %{"main" => "main"},
        "decision_profiles" => %{
          "advice" => %{
            "operation" => "decision",
            "provider" => "system_one_compatible",
            "model" => "synthetic",
            "service_id" => "fixture",
            "base_url" => base,
            "timeout_ms" => 3000
          }
        },
        "inference_services" => %{"fixture" => %{"version" => 1, "origins" => [base]}}
      })
    )

    File.chmod!(path, 0o600)
  end

  defp server(calls, phase, port) do
    {:ok, listener} =
      :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    task = Task.async(fn -> serve(listener, calls, phase) end)
    {"http://127.0.0.1:#{port}", listener, task}
  end

  defp serve(listener, calls, phase) do
    case :gen_tcp.accept(listener, 30_000) do
      {:ok, socket} ->
        try do
          {headers, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
          request = Jason.decode!(bytes)
          p = Agent.get(phase, & &1)
          decision? = String.starts_with?(headers, "POST /systemone ")

          Agent.update(
            calls,
            &(&1 ++
                [
                  %{
                    kind: if(decision?, do: :decision, else: :main),
                    phase: p.kind,
                    request: request
                  }
                ])
          )

          response = if decision?, do: decision_response(p), else: main_response(p, request)
          unless decision?, do: Agent.update(phase, &Map.update!(&1, :step, fn n -> n + 1 end))
          body = Jason.encode!(response) <> if(decision?, do: "", else: "\n")

          :ok =
            :gen_tcp.send(
              socket,
              "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                body
            )
        after
          :gen_tcp.close(socket)
        end

        serve(listener, calls, phase)

      {:error, :closed} ->
        :ok

      {:error, :timeout} ->
        :ok
    end
  end

  defp decision_response(p) do
    {id, first, second} =
      if p.kind == :selection,
        do: {"pack", "first", "second"},
        else: {"candidate", "keep_baseline", "defer_candidate"}

    %{
      "model" => "synthetic",
      "answers" => %{
        id => %{
          "type" => "choice",
          "choice" => first,
          "confidence" => 0.9,
          "probabilities" => %{first => 0.9, second => 0.1}
        }
      },
      "usage" => %{"input_tokens" => 10, "output_tokens" => 2}
    }
  end

  defp main_response(p, request) do
    tool = fn name ->
      Enum.find(
        Enum.reverse(request["messages"]),
        &(&1["role"] == "tool" and &1["tool_name"] == name)
      )
    end

    action =
      case {p.kind, p.step} do
        {:pending, 0} ->
          {"read", %{"path" => "synthetic.txt"}}

        {:pending, 1} ->
          {"source_list", %{"limit" => 32}}

        {:pending, 2} ->
          page = tool.("source_list")["content"] |> Jason.decode!()

          source =
            Enum.find(
              Enum.reverse(page["sources"]),
              &(&1["kind"] == "tool.outcome" and &1["origin"] == "typed_host_outcome")
            )

          {"source_read", %{"handle" => source["read_handle"]}}

        {:pending, 3} ->
          page = tool.("source_read")["content"] |> Jason.decode!()

          {"ext__knowledge__capture",
           %{
             "text" => "Synthetic proposed interpretation of a real local observation.",
             "category" => "ordinary",
             "reason" => "fixture main-tool candidate",
             "event_at_ms" => nil,
             "source" => %{"handle" => page["handle"], "quote" => page["text"]}
           }}

        {:selection, 0} ->
          {"ext__knowledge__select_shadow", p.arguments}

        {:assessment, 0} ->
          {"ext__knowledge__assess", %{"key" => p.key}}

        _ ->
          nil
      end

    message =
      if action,
        do: %{
          "role" => "assistant",
          "content" => "",
          "tool_calls" => [
            %{"function" => %{"name" => elem(action, 0), "arguments" => elem(action, 1)}}
          ]
        },
        else: %{"role" => "assistant", "content" => "Synthetic experiment finished."}

    %{
      "model" => "synthetic",
      "message" => message,
      "done" => true,
      "prompt_eval_count" => 1,
      "eval_count" => 1
    }
  end
end
