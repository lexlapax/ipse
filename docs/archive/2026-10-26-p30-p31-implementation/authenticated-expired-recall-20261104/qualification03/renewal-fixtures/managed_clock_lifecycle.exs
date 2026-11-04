# The manifest carries expected fixture data, never publication authority.
defmodule Ipse.Test.ManagedClockLifecycle do
  import ExUnit.Assertions
  alias Ipse.{JSON, Journal, Usage}
  alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission}
  alias Ipse.Extension.Collection.{ManagedRetention, ObservedRead}
  alias Ipse.CLI.Knowledge.Management
  @day 86_400_000

  defmodule UnexpectedModel do
    def complete(config, _, _, _) do
      File.write!(Path.join(config.fixture_root, "unexpected-model"), "called")
      raise "native lifecycle must not invoke a model"
    end
  end

  def prepare_stdio_clock([root, original_ebin]) do
    isolated = Path.join(root, "stdio-runtime/ipse")
    ebin = Path.join(isolated, "ebin")
    File.mkdir_p!(isolated)
    File.cp_r!(original_ebin, ebin)

    assert {"", 0} =
             System.cmd("cp", [
               "-R",
               "-L",
               Path.expand("../priv", original_ebin),
               Path.join(isolated, "priv")
             ])

    source = File.read!("lib/ipse/runner.ex")
    environment = ~S(%{"PATH" => "/usr/bin:/bin", "LANG" => "C.UTF-8"})
    assert length(:binary.matches(source, environment)) == 2

    instrumented =
      String.replace(
        source,
        environment,
        "Map.merge(" <>
          environment <>
          ", Map.new(~w(LD_PRELOAD IPSE_TEST_CLOCK_OFFSET_MS), &{&1, System.fetch_env!(&1)}))"
      )

    source_path = Path.join(isolated, "lib/ipse/runner.ex")
    File.mkdir_p!(Path.dirname(source_path))
    File.write!(source_path, instrumented)
    Code.compiler_options(ignore_module_conflict: true)
    [{Ipse.Runner, beam}] = Code.compile_string(instrumented, source_path)
    File.write!(Path.join(ebin, "Elixir.Ipse.Runner.beam"), beam)

    write_report(root, "clock-stdio-runtime.json", %{
      "production_source_sha256" => JSON.sha256(source),
      "instrumented_source_sha256" => JSON.sha256(instrumented),
      "runner_beam_sha256" => JSON.sha256(beam),
      "helper_sha256" => JSON.sha256(File.read!(Path.join(isolated, "priv/ipse-runner"))),
      "environment_additions" => ~w(LD_PRELOAD IPSE_TEST_CLOCK_OFFSET_MS),
      "production_source_modified" => false,
      "qualification" => false
    })

    IO.puts("NATIVE_CLOCK_STDIO_RUNTIME=" <> ebin)
  end

  def check_stdio_clock(root) do
    manifest = root |> Path.join("clock-stdio-runtime.json") |> File.read!() |> Jason.decode!()

    assert JSON.sha256(File.read!(to_string(:code.which(Ipse.Runner)))) ==
             manifest["runner_beam_sha256"]

    previous = System.get_env("IPSE_CLOCK_SANITIZATION_CANARY")
    System.put_env("IPSE_CLOCK_SANITIZATION_CANARY", "must-not-reach-the-child")

    try do
      before = System.system_time(:millisecond)

      script = ~S'''
      IO.puts(JSON.encode!(%{"wall_ms" => System.system_time(:millisecond),
        "canary" => System.get_env("IPSE_CLOCK_SANITIZATION_CANARY")}))
      IO.read(:stdio, 1)
      '''

      assert {:ok, port} =
               Ipse.Runner.open_protected_stdio(
                 System.find_executable("elixir"),
                 ["--erl", "+S 2:2", "-e", script],
                 Path.join(root, "work"),
                 %{"HOME" => root, "TMPDIR" => root},
                 5_000
               )

      observed = stdio_clock_output(port, <<>>, <<>>, System.monotonic_time(:millisecond) + 5_000)
      assert observed["wall_ms"] in before..System.system_time(:millisecond)
      assert observed["canary"] == nil
      assert :ok = Ipse.Runner.close_stdio(port)
      IO.puts("NATIVE_CLOCK_STDIO_COHERENT")
    after
      if previous,
        do: System.put_env("IPSE_CLOCK_SANITIZATION_CANARY", previous),
        else: System.delete_env("IPSE_CLOCK_SANITIZATION_CANARY")
    end
  end

  defp stdio_clock_output(
         port,
         <<kind, bytes::32, body::binary-size(bytes), rest::binary>>,
         output,
         deadline
       ) do
    output = if kind == ?O, do: output <> body, else: output
    assert byte_size(output) <= 4096

    if String.contains?(output, "\n"),
      do: output |> String.split("\n", parts: 2) |> hd() |> Jason.decode!(),
      else: stdio_clock_output(port, rest, output, deadline)
  end

  defp stdio_clock_output(port, buffer, output, deadline) do
    assert byte_size(buffer) <= 8192

    receive do
      {^port, {:data, bytes}} -> stdio_clock_output(port, buffer <> bytes, output, deadline)
      {^port, other} -> flunk("clock probe exited before its observation: #{inspect(other)}")
    after
      max(0, deadline - System.monotonic_time(:millisecond)) ->
        flunk("stdio clock probe timed out")
    end
  end

  def seed_late(config, root, id, current) do
    check_stdio_clock(root)
    admission = config.semantic_admission
    assert DynamicSupervisor.which_children(Ipse.Sessions) == []
    strict_saved(config.home, id)

    recipe =
      admission["policy"]["settings"]["recipes"]
      |> Map.values()
      |> Enum.find(&(&1["kind"] == "literal_source"))

    assert is_map(recipe)
    source = Path.join([config.home, "sessions", id <> ".jsonl"])

    seed = %{
      "version" => 1,
      "session_id" => id,
      "source_sha256" => JSON.sha256(File.read!(source)),
      "binding" => admission["binding"],
      "namespace" => admission["pin"]["namespace"],
      "recipe" => recipe,
      "current" => current,
      "seed_wall_ms" => System.system_time(:millisecond)
    }

    observed = live(late_context(root, seed), current)
    assert observed["metadata"]["category"] == "current"
    assert observed["metadata"]["valid_until_ms"] == nil
    write_report(root, "clock-late-seed.json", seed)
    IO.puts("NATIVE_CLOCK_LATE_SEED_PASSED")
  end

  def run_late(root, day) when day in [100, 366, 464, 466] do
    check_stdio_clock(root)
    seed = root |> Path.join("clock-late-seed.json") |> File.read!() |> Jason.decode!()
    assert seed["version"] == 1
    c = late_context(root, seed)
    System.put_env("IPSE_HOME", c.home)
    assert {:ok, binding} = ProjectIdentity.existing(c.home, c.cwd)
    assert binding === seed["binding"]
    now = System.system_time(:millisecond)
    assert now >= seed["seed_wall_ms"] + day * @day
    assert now < seed["seed_wall_ms"] + (day + 1) * @day
    source = Path.join([c.home, "sessions", seed["session_id"] <> ".jsonl"])
    assert JSON.sha256(File.read!(source)) == seed["source_sha256"]
    strict_saved(c.home, seed["session_id"])

    relation =
      if day == 100 do
        observed = live(c, seed["current"])
        assert observed["metadata"]["category"] == "current"
        assert observed["metadata"]["valid_until_ms"] == nil
        config = config(root, c.home, c.cwd)
        config = Map.merge(config, %{provider_module: UnexpectedModel, fixture_root: root})
        relation = supersede_late(config, root, seed)
        write_report(root, "clock-late-relation.json", relation)
        relation
      else
        root |> Path.join("clock-late-relation.json") |> File.read!() |> Jason.decode!()
      end

    now = System.system_time(:millisecond)
    config = config(root, c.home, c.cwd)

    expired =
      if day == 466 do
        assert now > relation["history_deadline_ms"]
        [expire(config, c, seed["current"]["key"], relation["history_deadline_ms"])]
      else
        retained = history(c, seed["current"])
        assert retained["metadata"]["valid_until_ms"] == relation["history_deadline_ms"]
        assert retained["metadata"]["successor"]["key"] == relation["replacement"]["key"]
        assert ManagedRetention.eligible_history_metadata?(retained["metadata"], now)
        before = snapshot(c)
        assert {:error, _} = Management.expire(config, c.cwd, seed["current"]["key"])
        assert snapshot(c) === before
        []
      end

    successor = live(c, relation["replacement"])
    assert successor["metadata"]["valid_until_ms"] == nil
    assert relation["history_deadline_ms"] == relation["reviewed_at_ms"] + 365 * @day
    assert relation["reviewed_at_ms"] > seed["seed_wall_ms"] + 90 * @day
    assert relation["history_deadline_ms"] > seed["seed_wall_ms"] + 465 * @day
    assert JSON.sha256(File.read!(source)) == seed["source_sha256"]
    strict_saved(c.home, seed["session_id"])
    strict_saved(c.home, relation["consumer_session_id"])
    refute File.exists?(Path.join(root, "unexpected-model"))
    assert DynamicSupervisor.which_children(Ipse.Sessions) == []

    write_report(root, "clock-late-day-#{day}.json", %{
      "day" => day,
      "wall_ms" => now,
      "first_supersession_after_day_90" => true,
      "controlled_stdio_clock_propagation" => true,
      "history_deadline_ms" => relation["history_deadline_ms"],
      "expired_operations" => expired,
      "source_sha256" => seed["source_sha256"],
      "annual_workload_qualification" => false
    })

    IO.puts("NATIVE_CLOCK_LATE_DAY_PASSED=#{day}")
  end

  defp supersede_late(config, root, seed) do
    dir = Path.join(config.home, "sessions")
    opts = [config: config, cwd: Path.join(root, "work"), state_dir: dir, subscriber: self()]
    assert {:ok, session} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
    id = Ipse.Session.info(session).id
    assert {:ok, channel} = Ipse.Session.open_input_channel(session, self())
    command = "/supersede " <> seed["current"]["key"] <> " My fixture timezone is Europe/Berlin"
    File.write!(Path.join(root, "supersession-input-1"), command)
    IO.write("IPSE_SUPERSESSION_READ_1> ")

    assert {:ok, ^command, witness} =
             Ipse.Session.observe_channel(session, channel, %{"kind" => "prompt"}, 30_000)

    assert {:ok, ticket} = Ipse.Session.stage_input(session, channel, command, witness)

    assert {:ok, %{"render_id" => render}} =
             Ipse.Session.prepare_assertion(session, channel, command, ticket)

    assert {:ok, input, witness} =
             Ipse.Session.observe_channel(
               session,
               channel,
               %{"kind" => "assertion", "render_id" => render},
               30_000
             )

    assert :ok = Ipse.Session.accept_assertion_observed(session, channel, render, input, witness)
    assert_receive {:ipse, ^session, {:done, :ok}}, 20_000
    assert :ok = Ipse.Session.close_confirmed(session)
    assert {:ok, events} = Journal.load(dir, id)
    temporal = intent(events, "temporal")
    settled = result(events, temporal["operation_id"])
    assert temporal["facts"]["target"]["key"] == seed["current"]["key"]

    [review] = Enum.filter(events, &(&1["type"] == "managed_supersession_review"))
    refute Enum.any?(events, &(&1["type"] in ~w(request_admitted inference_dispatch_intent)))

    %{
      "consumer_session_id" => id,
      "replacement" => temporal["facts"]["replacement"],
      "reviewed_at_ms" => review["review"]["observed_at_ms"],
      "history_deadline_ms" =>
        settled["outcome"]["publication"]["normalization"]["history_valid_until_ms"]
    }
  end

  defp late_context(root, seed) do
    home = Path.join(root, "home")

    %{
      root: SemanticAdmission.collection_root(home),
      home: home,
      cwd: Path.join(root, "work"),
      binding: seed["binding"],
      namespace: seed["namespace"],
      recipe: seed["recipe"]
    }
  end

  defp write_report(root, filename, report) do
    path = Path.join(root, filename)
    File.write!(path, Jason.encode!(report), [:exclusive])
    File.chmod!(path, 0o600)
  end

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
