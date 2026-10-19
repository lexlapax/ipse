defmodule Ipse.ObservabilityTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal}
  alias Ipse.Extensions.{Registry, Store, Manifest}
  alias Ipse.Observability.{Config, Resources}

  defmodule Model do
    def complete(_, _, _, emit) do
      emit.({:text, "synthetic-private-answer"})

      {:ok,
       %{
         "role" => "assistant",
         "content" => "synthetic-private-answer",
         "provider_data" => %{"native" => "synthetic-private-native"}
       }, %{}}
    end
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-observer-artifact-#{Ipse.Usage.id()}")
    File.mkdir_p!(Path.join(root, "ebin"))
    module = "Independent.Observer#{System.unique_integer([:positive])}"

    code = """
    defmodule #{module} do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 1, "capabilities" => ["observe.export"]}
      def init(options), do: (File.write!((options["pid"]) <> ".ready-" <> System.pid(), System.pid()); File.rename!((options["pid"]) <> ".ready-" <> System.pid(), options["pid"]); {:ok, options})
      def handle("observe.export", payload, state) do
        if state["mode"] == "crash", do: raise("synthetic callback failure")
        if state["mode"] == "hang" do
          File.write!(state["gate"], "entered")
          Process.sleep(:infinity)
        end
        File.write!(state["trace"], Jason.encode!(payload) <> "\\n", [:append])
        reply = if state["mode"] == "bad" do
          %{"api_version" => 1, "kind" => "host_call", "request" => %{"op" => "state.put"}}
        else
          %{"api_version" => 1, "kind" => "ack", "handle" => payload["handle"],
            "event_id" => payload["event"]["event"]["event_id"], "sequence" => payload["event"]["sequence"]}
        end
        {:ok, reply, state}
      end
    end
    """

    file = Path.join(root, "fixture.ex")
    File.write!(file, code)

    {output, status} =
      System.cmd(
        System.find_executable("elixirc"),
        ["-pa", Application.app_dir(:ipse, "ebin"), "-o", Path.join(root, "ebin"), file],
        stderr_to_stdout: true
      )

    assert status == 0, output
    File.write!(Path.join(root, "LICENSE"), "MIT synthetic fixture")

    manifest = %{
      "format" => 1,
      "id" => "fixture/observer",
      "version" => "0.1.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => module,
      "license_file" => "LICENSE",
      "capabilities" => ["observe.export"],
      "options_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ~w(trace pid gate mode),
        "properties" => Map.new(~w(trace pid gate mode), &{&1, %{"type" => "string"}})
      },
      "runtime" => %{
        "elixir" => "== " <> System.version(),
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      },
      "files" =>
        Enum.map(["ebin/Elixir.#{module}.beam", "LICENSE"], fn path ->
          bytes = File.read!(Path.join(root, path))
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Manifest.sha256(bytes)}
        end)
    }

    File.write!(Path.join(root, "extension.json"), Jason.encode!(manifest))
    on_exit(fn -> File.rm_rf!(root) end)
    %{artifact: root}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-observability-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      home: Path.join(root, "home"),
      dir: Path.join(root, "sessions"),
      trace: Path.join(root, "trace"),
      pidfile: Path.join(root, "pid"),
      gate: Path.join(root, "gate")
    }
  end

  defp config(c, kind \\ :local, mode \\ "local", behavior \\ "record", policy \\ %{}) do
    {retained_leases, policy} = Map.pop(policy, "retained_leases", 4)

    {artifact, capabilities, options} =
      if kind == :local do
        {"builtin:local-trace:1", ["observe.local"],
         %{"directory" => Path.join(c.root, "logs"), "retained_leases" => retained_leases}}
      else
        {:ok, imported} = Store.import(c.artifact, Path.join(c.home, "extensions/artifacts"))

        {imported.digest, ["observe.export"],
         %{"trace" => c.trace, "pid" => c.pidfile, "gate" => c.gate, "mode" => behavior}}
      end

    data = %{
      "extensions" => [
        %{
          "instance" => "trace",
          "artifact" => artifact,
          "enabled" => true,
          "options" => options,
          "order" => 0,
          "lifetime" => "session"
        }
      ],
      "extension_trust" => [
        %{
          "artifact" => artifact,
          "capabilities" => capabilities,
          "allow_project" => false,
          "allow_children" => false
        }
      ]
    }

    {:ok, selected} =
      Ipse.Extensions.Config.resolve(
        [%{scope: "operator", path: "/fixture/operator.json", data: data}],
        []
      )

    {:ok, entries} = Registry.prepare(selected, c.home)

    %{
      provider: :demo,
      model: "fixture",
      provider_module: Model,
      approval: :deny,
      home: c.home,
      extensions: entries,
      observability: Map.merge(Config.defaults(), Map.put(policy, "mode", mode))
    }
  end

  defp start(c, config, extra \\ []) do
    {:ok, pid} =
      Session.start_link(
        [config: config, cwd: c.root, state_dir: c.dir, subscriber: self()] ++ extra
      )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    pid
  end

  defp done(pid), do: assert_receive({:ipse, ^pid, {:done, :ok}}, 10_000)
  defp eventually(fun, tries \\ 300)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, tries),
    do:
      if(fun.(),
        do: :ok,
        else:
          (
            Process.sleep(10)
            eventually(fun, tries - 1)
          )
      )

  defp sinks(pid), do: Session.diagnostics(pid)["observability"]["sinks"]
  defp ring(c), do: Path.join([c.root, "logs", "trace-ring-v1"])

  defp trace_path(c, resource) do
    catalog = File.read!(Path.join(ring(c), "catalog.json")) |> Jason.decode!()
    {slot, ^resource} = Enum.find(catalog["slots"], fn {_, id} -> id == resource end)
    Path.join(ring(c), "slot-#{slot}.jsonl")
  end

  test "off creates no sink, lease or file but mandatory accounting still works", c do
    pid = start(c, config(c, :local, "off"))
    :ok = Session.prompt(pid, "synthetic-private-prompt")
    done(pid)
    refute File.exists?(Path.join(c.root, "logs"))
    assert sinks(pid) == []
    id = Session.info(pid).id
    :ok = Session.close(pid)
    {:ok, events} = Journal.load(c.dir, id)
    refute Enum.any?(events, &(&1["type"] in Resources.types()))
    assert Enum.any?(events, &(&1["type"] == "request_finished"))
  end

  test "local capture preserves shared identities and excludes private data", c do
    pid = start(c, config(c))
    :ok = Session.prompt(pid, "synthetic-private-prompt")
    done(pid)
    eventually(fn -> Enum.any?(sinks(pid), &(&1["delivered"] >= 4)) end)
    [sink] = sinks(pid)
    path = trace_path(c, sink["resource_id"])
    eventually(fn -> File.exists?(path) end)
    lines = File.read!(path) |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    refute String.contains?(Jason.encode!(lines), [
             "synthetic-private",
             "record_sha256",
             "content_sha256"
           ])

    id = Session.info(pid).id
    {:ok, %{records: records}} = Journal.source_page(c.dir, id, 0, 64)

    for line <- lines do
      assert Ipse.Observability.Event.valid?(line)
      assert Enum.any?(records, &(&1.source["event_id"] == line["event"]["event_id"]))
    end

    assert Bitwise.band(File.stat!(path).mode, 0o077) == 0
    assert Bitwise.band(File.stat!(Path.dirname(path)).mode, 0o077) == 0
    :ok = Session.close(pid)
    {:ok, events} = Journal.load(c.dir, id)
    assert Resources.validate(events, id) == :ok

    assert Enum.any?(
             events,
             &(&1["type"] == "diagnostic_sink_closed" and &1["cleanup_confirmed"])
           )
  end

  test "capture stops immediately while prompts, usage and journals remain usable", c do
    pid = start(c, config(c))
    eventually(fn -> Enum.any?(sinks(pid), & &1["ready"]) end)
    assert :ok = Session.stop_observability(pid)
    snapshot = Session.diagnostics(pid)["observability"]
    assert snapshot["mode"] == "off"
    assert Enum.all?(snapshot["sinks"], &(&1["active"] == 0))
    offered = snapshot["offered"]
    :ok = Session.prompt(pid, "after-stop-secret")
    done(pid)
    assert Session.diagnostics(pid)["observability"]["offered"] == offered
    assert Session.info(pid).accounting["request_count"] == 1
    :ok = Session.close(pid)
  end

  test "local policy refuses exporters and export requires operator scope", c do
    cfg = config(c, :external, "local")

    assert {:error, _} =
             Session.start_link(config: cfg, cwd: c.root, state_dir: c.dir, subscriber: self())

    refute File.exists?(c.pidfile)
    export = config(c, :external, "export")
    [entry] = export.extensions
    project = put_in(entry.identity["scope"], "project")

    assert Config.runtime(%{export | extensions: [project]}) ==
             {:error, :invalid_observability_policy}

    pid = start(c, export)
    :ok = Session.prompt(pid, "synthetic-private-prompt")
    done(pid)
    eventually(fn -> File.exists?(c.trace) end)
    refute File.read!(c.trace) =~ "synthetic-private"
    :ok = Session.close(pid)
  end

  test "slow sink has bounded pending work and never blocks inference", c do
    pid = start(c, config(c, :external, "export", "hang", %{"queue_events" => 2}))
    eventually(fn -> File.exists?(c.gate) end)
    :ok = Session.prompt(pid, "synthetic-private-prompt")
    done(pid)
    [sink] = sinks(pid)
    assert sink["pending"] <= 2
    assert sink["dropped"] > 0
    started = System.monotonic_time(:millisecond)
    :ok = Session.stop_observability(pid)
    assert System.monotonic_time(:millisecond) - started < 500
    assert :ok = Session.close(pid)
  end

  test "invalid sink replies cannot request effects or fail the agent turn", c do
    pid = start(c, config(c, :external, "export", "bad"))
    :ok = Session.prompt(pid, "synthetic-private-prompt")
    done(pid)
    eventually(fn -> Enum.any?(sinks(pid), & &1["closed"]) end)
    [sink] = sinks(pid)
    assert sink["failures"] == 1
    {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
    refute Enum.any?(events, &(&1["type"] == "extension_action_intent"))
    assert Resources.validate(events, Session.info(pid).id) == :ok
  end

  test "operator capture settings have explicit precedence and project refusal", c do
    file = Path.join(c.home, "config.json")
    File.mkdir_p!(c.home)

    File.write!(
      file,
      Jason.encode!(%{
        "version" => 1,
        "observability" => %{"mode" => "local", "sample_every" => 3}
      })
    )

    {:ok, effective} =
      Ipse.Config.resolve(c.root, c.home, [observability: "off"], %{
        "IPSE_OBSERVABILITY" => "export"
      })

    assert effective.observability.policy["mode"] == "off"
    assert effective.observability.policy["sample_every"] == 3
    assert effective.observability.mode_source == "CLI"

    assert {:error, _} =
             Config.resolve(
               [%{scope: "project", data: %{"observability" => %{"mode" => "off"}}}],
               [],
               %{}
             )

    assert {:error, _} = Config.resolve([], [observability: "invalid"], %{})
  end

  test "optional source overflow cannot lose or duplicate the recovery record", c do
    {:ok, id} = Journal.create(c.dir, %{})
    record = %{"type" => "fixture", "private" => String.duplicate("x", 1_048_576)}
    assert {:ok, nil} = Journal.append_observed(c.dir, id, record)
    assert {:ok, [_, ^record]} = Journal.load(c.dir, id)
  end

  test "rotation bounds each lease and rejects private-field injection", c do
    pid =
      start(
        c,
        config(c, :local, "local", "record", %{"file_bytes" => 16_384, "retained_files" => 2})
      )

    for n <- 1..12 do
      :ok = Session.prompt(pid, "synthetic-private-#{n}")
      done(pid)
    end

    eventually(fn -> Enum.all?(sinks(pid), &(&1["ready"] and &1["pending"] == 0)) end)
    paths = Path.wildcard(Path.join(ring(c), "slot-*.jsonl*"))
    assert length(paths) == 2
    assert Enum.all?(paths, &(File.stat!(&1).size <= 16_384))

    event =
      paths |> hd() |> File.read!() |> String.split("\n", trim: true) |> hd() |> Jason.decode!()

    for injected <- [
          put_in(event, ["event", "data", "text"], "private"),
          put_in(event, ["event", "source", "record_sha256"], String.duplicate("a", 64)),
          put_in(event, ["event", "correlations", "endpoint_sha256"], String.duplicate("b", 64))
        ],
        do: refute(Ipse.Observability.Event.valid?(injected))

    :ok = Session.close(pid)
  end

  test "owner death stops a blocked independent sink VM", c do
    pid = start(c, config(c, :external, "export", "hang"))
    eventually(fn -> File.exists?(c.gate) end)
    vm = File.read!(c.pidfile)
    Process.unlink(pid)
    Process.exit(pid, :kill)
    eventually(fn -> elem(System.cmd("kill", ["-0", vm], stderr_to_stdout: true), 1) != 0 end)
  end

  test "enabled idle resume creates a fresh diagnostic lease without replaying historical samples",
       c do
    cfg = config(c, :external, "export")
    first = start(c, cfg)
    :ok = Session.prompt(first, "old-private-prompt")
    done(first)
    eventually(fn -> Enum.all?(sinks(first), &(&1["ready"] and &1["pending"] == 0)) end)
    id = Session.info(first).id
    :ok = Session.close(first)
    old = File.read!(c.trace)
    resumed = start(c, cfg, id: id)
    eventually(fn -> Enum.all?(sinks(resumed), &(&1["ready"] and &1["pending"] == 0)) end)
    resumed_bytes = File.read!(c.trace)
    assert String.starts_with?(resumed_bytes, old)

    new_lines =
      resumed_bytes
      |> binary_part(byte_size(old), byte_size(resumed_bytes) - byte_size(old))
      |> String.split("\n", trim: true)

    assert [%{"event" => %{"event" => %{"type" => "session.resumed"}}}] =
             Enum.map(new_lines, &Jason.decode!/1)

    :ok = Session.prompt(resumed, "new-private-prompt")
    done(resumed)
    eventually(fn -> Enum.all?(sinks(resumed), &(&1["pending"] == 0)) end)
    lines = File.read!(c.trace) |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
    ids = Enum.map(lines, & &1["event"]["event"]["event_id"])
    assert length(ids) == length(Enum.uniq(ids))
    :ok = Session.close(resumed)
    {:ok, events} = Journal.load(c.dir, id)
    assert Resources.validate(events, id) == :ok
    assert Enum.count(events, &(&1["type"] == "diagnostic_sink_intent")) == 2
  end

  test "sampling and category filters are visible and do not suppress recovery facts", c do
    pid =
      start(
        c,
        config(c, :local, "local", "record", %{"groups" => ["model"], "sample_every" => 2})
      )

    :ok = Session.prompt(pid, "private-sampled-prompt")
    done(pid)
    eventually(fn -> Enum.all?(sinks(pid), &(&1["ready"] and &1["pending"] == 0)) end)
    [sink] = sinks(pid)
    assert sink["filtered"] > 0

    if File.dir?(Path.join(c.root, "logs")) do
      for path <- Path.wildcard(Path.join(ring(c), "slot-*.jsonl*")),
          line <- String.split(File.read!(path), "\n", trim: true) do
        assert Jason.decode!(line)["group"] == "model"
      end
    end

    id = Session.info(pid).id
    :ok = Session.close(pid)
    {:ok, events} = Journal.load(c.dir, id)
    assert Enum.any?(events, &(&1["type"] == "message" and &1["message"]["role"] == "user"))
  end

  test "restoration refuses an invalid diagnostic grant or duplicated receipt", c do
    pid = start(c, config(c))
    eventually(fn -> Enum.any?(sinks(pid), & &1["ready"]) end)
    id = Session.info(pid).id
    :ok = Session.close(pid)
    {:ok, events} = Journal.load(c.dir, id)
    intent = Enum.find(events, &(&1["type"] == "diagnostic_sink_intent"))
    forged = put_in(intent, ["policy", "mode"], "off")
    altered = Enum.map(events, &if(&1 == intent, do: forged, else: &1))
    assert {:error, :invalid_diagnostic_receipts} = Session.restore_context(altered)
    ready = Enum.find(events, &(&1["type"] == "diagnostic_sink_ready"))
    assert {:error, :invalid_diagnostic_receipts} = Session.restore_context(events ++ [ready])
  end

  defp settled(pid) do
    eventually(fn ->
      Enum.all?(
        sinks(pid),
        &(&1["ready"] and not &1["closed"] and &1["pending"] == 0 and &1["delivered"] > 0)
      )
    end)
  end

  test "a failed callback with confirmed worker cleanup still closes the session", c do
    pid = start(c, config(c, :export, "export", "crash"))
    :ok = Session.prompt(pid, "synthetic-private-prompt")
    done(pid)
    eventually(fn -> Enum.any?(sinks(pid), & &1["closed"]) end)
    [sink] = sinks(pid)
    assert sink["failures"] == 1
    id = Session.info(pid).id
    assert :ok = Session.close(pid)
    {:ok, events} = Journal.load(c.dir, id)

    assert Enum.any?(
             events,
             &(&1["type"] == "diagnostic_sink_closed" and &1["cleanup_confirmed"])
           )
  end

  test "an interrupted first catalog publish refuses capture but confirms cleanup", c do
    File.mkdir_p!(ring(c))
    File.chmod!(Path.dirname(ring(c)), 0o700)
    File.chmod!(ring(c), 0o700)
    temporary = Path.join(ring(c), ".catalog.next")
    File.write!(temporary, "")
    File.chmod!(temporary, 0o644)

    pid = start(c, config(c))
    :ok = Session.prompt(pid, "synthetic-private-prompt")
    done(pid)
    eventually(fn -> Enum.any?(sinks(pid), & &1["closed"]) end)
    [sink] = sinks(pid)
    assert sink["ready"]
    assert sink["failures"] == 1
    assert sink["delivered"] == 0
    assert :ok = Session.close(pid)
    refute File.exists?(Path.join(ring(c), "catalog.json"))
    assert File.read!(temporary) == ""
    assert Bitwise.band(File.stat!(temporary).mode, 0o777) == 0o644
  end

  test "a fixed lease ring bounds files and bytes across repeated sessions", c do
    cfg = config(c, :local, "local", "record", %{"retained_leases" => 2, "file_bytes" => 16_384})

    ids =
      for n <- 1..5 do
        pid = start(c, cfg)
        :ok = Session.prompt(pid, "private-lease-#{n}")
        done(pid)
        settled(pid)
        [sink] = sinks(pid)
        id = Session.info(pid).id
        :ok = Session.close(pid)
        {sink["resource_id"], id}
      end

    catalog = File.read!(Path.join(ring(c), "catalog.json")) |> Jason.decode!()

    assert MapSet.new(Map.values(catalog["slots"])) ==
             MapSet.new(Enum.take(ids, -2) |> Enum.map(&elem(&1, 0)))

    paths = Path.wildcard(Path.join(ring(c), "slot-*.jsonl*"))
    assert length(paths) <= 4
    assert Enum.sum(Enum.map(paths, &File.stat!(&1).size)) <= 2 * 2 * 16_384

    sessions =
      for path <- paths,
          line <- String.split(File.read!(path), "\n", trim: true),
          do: Jason.decode!(line)["event"]["source"]["session_id"]

    assert MapSet.new(sessions) == MapSet.new(Enum.take(ids, -2) |> Enum.map(&elem(&1, 1)))
    assert {:ok, _} = Journal.load(c.dir, elem(hd(ids), 1))
    assert length(Path.wildcard(Path.join(ring(c), ".slot-*.lock"), match_dot: true)) == 2
  end

  test "full rings refuse new writers without evicting active sessions", c do
    cfg = config(c, :local, "local", "record", %{"retained_leases" => 2})
    first = start(c, cfg)
    :ok = Session.prompt(first, "first-private")
    done(first)
    settled(first)
    second = start(c, cfg)
    :ok = Session.prompt(second, "second-private")
    done(second)
    settled(second)

    for n <- 1..3 do
      :ok = Session.prompt(first, "concurrent-first-#{n}")
      :ok = Session.prompt(second, "concurrent-second-#{n}")
      done(first)
      done(second)
    end

    settled(first)
    settled(second)
    [second_sink] = sinks(second)
    second_path = trace_path(c, second_sink["resource_id"])
    before = File.read!(second_path)
    catalog = File.read!(Path.join(ring(c), "catalog.json"))
    lock_inode = File.stat!(Path.join(ring(c), ".slot-1.lock")).inode
    refused = start(c, cfg)
    :ok = Session.prompt(refused, "refused-private")
    done(refused)
    # Startup and initialize each have a five-second worker deadline.
    eventually(fn -> Enum.any?(sinks(refused), & &1["closed"]) end, 1500)
    assert File.read!(second_path) == before
    assert File.read!(Path.join(ring(c), "catalog.json")) == catalog
    :ok = Session.close(first)
    replacement = start(c, cfg)
    :ok = Session.prompt(replacement, "replacement-private")
    done(replacement)
    settled(replacement)
    assert File.read!(second_path) == before
    assert File.stat!(Path.join(ring(c), ".slot-1.lock")).inode == lock_inode
    :ok = Session.close(replacement)
    :ok = Session.close(second)
  end

  test "owner death releases its slot for a new capture without replay", c do
    cfg = config(c, :local, "local", "record", %{"retained_leases" => 1})
    first = start(c, cfg)
    :ok = Session.prompt(first, "old-private")
    done(first)
    settled(first)
    Process.unlink(first)
    Process.exit(first, :kill)
    lock_path = Path.join(ring(c), ".slot-1.lock")

    eventually(fn ->
      case Ipse.Runner.lock(lock_path) do
        {:ok, lock} ->
          Ipse.Runner.unlock(lock)
          true

        _ ->
          false
      end
    end)

    next = start(c, cfg)
    :ok = Session.prompt(next, "new-private")
    done(next)
    settled(next)
    :ok = Session.close(next)
  end

  test "shared-directory limit mismatch refuses without altering existing logs", c do
    first = start(c, config(c, :local, "local", "record", %{"retained_leases" => 1}))
    :ok = Session.prompt(first, "protected-private")
    done(first)
    settled(first)
    before = File.read!(Path.join(ring(c), "slot-1.jsonl"))
    mismatch = start(c, config(c, :local, "local", "record", %{"retained_leases" => 2}))
    :ok = Session.prompt(mismatch, "mismatch-private")
    done(mismatch)
    eventually(fn -> Enum.any?(sinks(mismatch), & &1["closed"]) end)
    assert File.read!(Path.join(ring(c), "slot-1.jsonl")) == before
    :ok = Session.close(first)
  end

  test "corrupt or oversized catalogs refuse without repair or data deletion", c do
    cfg = config(c, :local, "local", "record", %{"retained_leases" => 1})
    first = start(c, cfg)
    :ok = Session.prompt(first, "protected-private")
    done(first)
    settled(first)
    :ok = Session.close(first)
    path = Path.join(ring(c), "catalog.json")
    before = File.read!(Path.join(ring(c), "slot-1.jsonl"))

    for bytes <- ["{\"version\":1,\"version\":1}", String.duplicate("x", 16_385)] do
      File.write!(path, bytes)
      pid = start(c, cfg)
      :ok = Session.prompt(pid, "refused-private")
      done(pid)
      eventually(fn -> Enum.any?(sinks(pid), & &1["closed"]) end)
      assert File.read!(path) == bytes
      assert File.read!(Path.join(ring(c), "slot-1.jsonl")) == before
    end
  end

  test "slot symlinks cannot redirect rotation or erasure", c do
    cfg = config(c, :local, "local", "record", %{"retained_leases" => 1})
    first = start(c, cfg)
    :ok = Session.prompt(first, "first-private")
    done(first)
    settled(first)
    :ok = Session.close(first)
    slot = Path.join(ring(c), "slot-1.jsonl")
    File.rm!(slot)
    sentinel = Path.join(c.root, "sentinel")
    File.write!(sentinel, "synthetic-outside-data")
    File.ln_s!(sentinel, slot)
    next = start(c, cfg)
    :ok = Session.prompt(next, "refused-private")
    done(next)
    eventually(fn -> Enum.any?(sinks(next), & &1["closed"]) end)
    assert File.read!(sentinel) == "synthetic-outside-data"
    assert File.lstat!(slot).type == :symlink
  end

  test "legacy root files remain outside the managed ring", c do
    directory = Path.join(c.root, "logs")
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)
    path = Path.join(directory, Ipse.Usage.id() <> ".jsonl")
    File.write!(path, "legacy-synthetic-private")
    pid = start(c, config(c))
    :ok = Session.prompt(pid, "new-private")
    done(pid)
    settled(pid)
    :ok = Session.close(pid)
    assert File.read!(path) == "legacy-synthetic-private"
  end
end
