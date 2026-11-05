defmodule Ipse.Development.NativeNotesSeed do
  @moduledoc false
  import ExUnit.Assertions
  alias Ipse.{JSON, Journal, Session, Usage}
  alias Ipse.CLI.Knowledge.Management
  alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission}
  alias Ipse.Extension.Collection.ObservedRead
  @day 86_400_000
  @source_files ~w(dev/knowledge/native_notes_seed.ex dev/knowledge/native_notes_seed.exs test/support/managed_clock_lifecycle.exs)
  @recorded_time_keys ~w(checked_at_ms observed_at_ms created_at_ms accepted_at_ms reviewed_at_ms started_at_ms finished_at_ms published_at_ms)

  defmodule NoModel do
    def complete(config, _, _, _) do
      File.write!(Path.join(config.fixture_root, "unexpected-model"), "called", [:exclusive])
      raise "native notes seed attempted inference"
    end
  end

  def plan("initial") do
    Enum.flat_map(1..2000, fn number ->
      category =
        cond do
          number in 101..150 -> "preference"
          number in 151..200 -> "current"
          true -> "ordinary"
        end

      capture = %{"op" => "capture", "number" => number, "category" => category}
      if number <= 100, do: [capture, %{"op" => "pin", "number" => number}], else: [capture]
    end)
    |> Enum.with_index()
    |> Enum.group_by(fn {_, index} -> div(index, 100) end, &elem(&1, 0))
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {day, actions} ->
      Enum.chunk_every(actions, 8)
      |> Enum.map(fn actions ->
        %{"day" => day, "actions" => Enum.sort_by(actions, & &1["op"])}
      end)
    end)
  end

  def plan("smoke") do
    [
      %{
        "day" => 0,
        "actions" => [
          %{"op" => "capture", "number" => 1, "category" => "ordinary"},
          %{"op" => "capture", "number" => 2, "category" => "preference"},
          %{"op" => "capture", "number" => 3, "category" => "current"},
          %{"op" => "pin", "number" => 1}
        ]
      },
      %{
        "day" => 1,
        "actions" =>
          Enum.map(4..7, &%{"op" => "capture", "number" => &1, "category" => "ordinary"})
      }
    ]
  end

  def plan("maximum") do
    [%{"day" => 0, "actions" => [%{"op" => "capture", "number" => 1, "category" => "ordinary"}]}]
  end

  @doc "Byte geometry only: no source proof, native observation or stored value is constructed."
  def maximum_geometry(now, category \\ "ordinary")
      when is_integer(now) and now >= 0 and category in ~w(ordinary preference current) do
    escapes =
      Enum.find(998..0//-1, fn count ->
        maximum_proof_bytes(count, category) <= 2048
      end)

    statement = maximum_statement(escapes)
    proof = maximum_proof_bytes(escapes, category)
    encoded = fn value -> byte_size(Jason.encode!(value)) end
    evidence = maximum_object_bytes([{"sources", proof + 2}])

    value =
      maximum_object_bytes([
        {"version", 1},
        {"id", 66},
        {"lineage", 66},
        {"text", encoded.(statement)},
        {"evidence", evidence},
        {"category", encoded.(category)},
        {"reason", encoded.("Native operator statement and category review.")},
        {"created_at_ms", encoded.(now)},
        {"observed_at_ms", encoded.(now)},
        {"event_at_ms", 4},
        {"expires_at_ms", encoded.(if(category == "ordinary", do: now + 90 * @day))},
        {"superseded_at_ms", 4},
        {"previous_category", 4},
        {"metadata_reserve", 66}
      ])

    quote_bytes = encoded.(statement)
    fixed_proof_bytes = proof - quote_bytes

    upper_bound =
      Enum.map(1..1024, fn source_bytes ->
        fixed = fixed_proof_bytes + byte_size(Integer.to_string(source_bytes)) - 3
        quote = min(6 * source_bytes + 2, 2048 - fixed)
        value + quote - quote_bytes + fixed + quote - proof
      end)
      |> Enum.max()

    %{
      "source_bytes" => byte_size(statement),
      "json_escape_count" => escapes,
      "proof_encoded_bytes" => proof,
      "next_escape_proof_bytes" => maximum_proof_bytes(escapes + 1, category),
      "predicted_note_value_bytes" => value,
      "all_source_lengths_upper_bound_bytes" => upper_bound,
      "record_ceiling_bytes" => 6144,
      "category" => category,
      "timestamp_digits" => byte_size(Integer.to_string(now)),
      "source_limit_bytes" => 1024,
      "proof_limit_bytes" => 2048,
      "geometry_only" => true
    }
  end

  def maximum_statement(escapes) when escapes in 0..998,
    do: "M" <> String.duplicate("\\", escapes) <> String.duplicate("x", 998 - escapes)

  defp maximum_proof_bytes(escapes, category) do
    encoded = fn value -> byte_size(Jason.encode!(value)) end

    maximum_object_bytes([
      {"version", 1},
      {"session_id", 34},
      {"occurrence_id", 34},
      {"version_id", 34},
      {"kind", encoded.("input.assertion." <> category)},
      {"origin", encoded.("native_operator_assertion")},
      {"coverage", encoded.("available")},
      {"path", 4},
      {"start_byte", 1},
      {"end_byte", 3},
      {"quote", encoded.(maximum_statement(escapes))},
      {"quote_sha256", 66},
      {"content_sha256", 66},
      {"receipt_sha256", 66}
    ])
  end

  defp maximum_object_bytes(fields) do
    2 + length(fields) - 1 +
      Enum.sum(Enum.map(fields, fn {key, size} -> byte_size(Jason.encode!(key)) + 1 + size end))
  end

  @doc "Summarize selected recorded event times; this is not a physical-completion bound."
  def recorded_times(events) when is_list(events) do
    %{
      "events" => length(events),
      "maxima_ms" => Enum.reduce(events, %{}, &recorded_times_in/2)
    }
  end

  defp recorded_times_in(value, maxima) when is_map(value) do
    Enum.reduce(value, maxima, fn {key, nested}, acc ->
      acc =
        if key in @recorded_time_keys and JSON.safe_uint?(nested),
          do: Map.update(acc, key, nested, &max(&1, nested)),
          else: acc

      recorded_times_in(nested, acc)
    end)
  end

  defp recorded_times_in(value, maxima) when is_list(value),
    do: Enum.reduce(value, maxima, &recorded_times_in/2)

  defp recorded_times_in(_, maxima), do: maxima

  def main(["--init", root, kind]) when kind in ~w(initial smoke maximum),
    do: initialize(root, kind, nil)

  def main(["--init", root, kind, "--fixture-port", port])
      when kind in ~w(initial smoke maximum) do
    {port, ""} = Integer.parse(port)
    assert port in 1..65_535
    initialize(root, kind, port)
  end

  def main(["--run", root, count]), do: run(root, count)
  def main(["--child", root, index]), do: child(root, String.to_integer(index))
  def main(["--audit", root, output]), do: audit(root, output)
  def main(["--audit-child", root, output]), do: audit_child(root, output)

  def main(_),
    do:
      raise(
        "use --init ROOT initial|smoke|maximum [--fixture-port PORT], --run ROOT SEGMENTS|all, or --audit ROOT OUTPUT"
      )

  @doc "A loopback-only synthetic profile; this does not enable or contact a service."
  def fixture_config(port) when is_integer(port) and port in 1..65_535 do
    origin = "http://127.0.0.1:#{port}"

    %{
      "version" => 1,
      "profiles" => %{
        "synthetic" => %{
          "provider" => "ollama",
          "model" => "synthetic",
          "base_url" => origin,
          "max_output_tokens" => 64,
          "timeout_ms" => 15_000
        }
      },
      "roles" => %{"main" => "synthetic"},
      "inference_services" => %{"local" => %{"version" => 1, "origins" => [origin]}}
    }
  end

  defp audit(root, output) do
    manifest = manifest(root)
    assert not File.exists?(Path.join(root, "inflight.json"))
    assert length(closed(root, manifest)) == length(manifest["plan"])
    verify_files(manifest)

    assert Path.dirname(output) == "/tmp" and
             String.starts_with?(Path.basename(output), "ipse-native-seed-audit-")

    for path <- [output, output <> ".log", output <> ".driver.ex", output <> ".rows.json"],
        do: assert(not File.exists?(path))

    source = output <> ".driver.ex"
    File.cp!(__ENV__.file, source)
    File.chmod!(source, 0o600)
    day = List.last(manifest["plan"])["day"]

    {log, code} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2 +C multi_time_warp"] ++
          private_paths(root) ++
          [
            "-r",
            source,
            "-e",
            "Ipse.Development.NativeNotesSeed.main(System.argv())",
            "--",
            "--audit-child",
            root,
            output
          ],
        stderr_to_stdout: true,
        env: [
          {"LD_PRELOAD", if(manifest["kind"] != "maximum", do: Path.join(root, "clock.so"))},
          {"IPSE_TEST_CLOCK_OFFSET_MS",
           if(manifest["kind"] != "maximum", do: Integer.to_string(day * @day))},
          {"HOME", root},
          {"IPSE_HOME", Path.join(root, "home")},
          {"TMPDIR", root}
        ]
      )

    File.write!(output <> ".log", log, [:exclusive])
    File.chmod!(output <> ".log", 0o600)

    assert code == 0,
           "read-only population audit refused; inspect #{output}.log; no publication replay"

    IO.write(log)
  end

  defp audit_child(root, output) do
    Process.flag(:max_heap_size, %{size: 16_000_000, kill: true, error_logger: true})
    manifest = manifest(root)
    verify_files(manifest)
    assert not File.exists?(Path.join(root, "inflight.json"))
    reports = closed(root, manifest)
    assert length(reports) == length(manifest["plan"])
    {:ok, _} = Application.ensure_all_started(:ipse)

    if manifest["kind"] != "maximum" do
      modules = Code.require_file(Path.join(root, "runtime/managed_clock_lifecycle.exs"))

      {clock_module, _} =
        Enum.find(modules, fn {module, _} -> module === Ipse.Test.ManagedClockLifecycle end)

      clock_module.check_stdio_clock(root)
    end

    home = Path.join(root, "home")
    cwd = Path.join(root, "work")
    assert {:ok, binding} = ProjectIdentity.existing(home, cwd)

    assert {:ok, namespace} =
             Ipse.Extension.SemanticConsent.namespace(binding["project_id"], "knowledge")

    collection = SemanticAdmission.collection_root(home)
    assert {:ok, selected} = Management.selection(home)

    assert {:ok, control} =
             Consent.existing_snapshot(
               SemanticAdmission.control_root(home),
               binding["project_id"]
             )

    assert JSON.digest([control]) === List.last(reports)["control_sha256"]

    assert {:ok, initial} = ObservedRead.read(collection, namespace, %{"op" => "snapshot"})
    assert initial["value"] === List.last(reports)["snapshot"]
    root_sha = initial["witness"]["root_sha256"]

    records =
      Enum.reduce(reports, %{}, fn report, all -> Map.merge(all, report["new_records"]) end)

    assert visible(collection, namespace) === expected_records(records)
    actions = Enum.flat_map(manifest["plan"], & &1["actions"])
    pins = actions |> Enum.filter(&(&1["op"] == "pin")) |> MapSet.new(& &1["number"])

    capture_days =
      Map.new(
        Enum.flat_map(manifest["plan"], fn segment ->
          for action <- segment["actions"],
              action["op"] == "capture",
              do: {action["number"], segment["day"]}
        end)
      )

    sources = Enum.flat_map(reports, & &1["sources"])

    recorded =
      Enum.reduce(sources, %{"events" => 0, "maxima_ms" => %{}}, fn source, totals ->
        verify_fingerprint(source)
        directory = Path.dirname(source["path"])
        id = Path.basename(source["path"], ".jsonl")
        assert {:ok, events} = Journal.load(directory, id)

        if directory == Path.join(home, "sessions") do
          assert {:ok, %{"release_claim" => "signed_release_claim"}} =
                   Session.Saved.inspect_saved(directory, id)

          assert {:ok, _} = Session.Saved.restore(events, id)
        end

        summary = recorded_times(events)

        %{
          "events" => totals["events"] + summary["events"],
          "maxima_ms" =>
            Map.merge(totals["maxima_ms"], summary["maxima_ms"], fn _, a, b -> max(a, b) end)
        }
      end)

    rows =
      records
      |> Enum.sort_by(fn {number, _} -> String.to_integer(number) end)
      |> Enum.map(fn {number, expected} ->
        number = String.to_integer(number)

        assert {:ok, managed} =
                 ProjectIdentity.with_existing_domain_auth(
                   home,
                   cwd,
                   binding,
                   %{namespace: namespace, format: "managed-metadata-v3"},
                   fn cap, catalog ->
                     ObservedRead.with_managed_note_record(
                       collection,
                       namespace,
                       %{"op" => "get_record", "key" => expected["key"]},
                       cap,
                       catalog,
                       selected.recipe,
                       &{:ok, &1}
                     )
                   end
                 )

        actual = managed["observation"]["value"]["record"]
        metadata = managed["metadata"]
        assert managed["observation"]["witness"]["root_sha256"] === root_sha
        assert actual["value"] === expected["value"]
        assert metadata["recipe_sha256"] === JSON.digest([selected.recipe])
        assert metadata["policy_sha256"] === JSON.digest([control["policy"]])
        category = if MapSet.member?(pins, number), do: "pin", else: expected["category"]
        assert metadata["category"] === category
        first = metadata["first_admitted_ms"]
        day = capture_days[number]
        assert first >= manifest["created_wall_ms"] + day * @day
        assert first < manifest["created_wall_ms"] + (day + 1) * @day
        deadline = metadata["valid_until_ms"]
        assert deadline === if(category == "ordinary", do: first + 90 * @day, else: nil)
        assert is_nil(deadline) or System.system_time(:millisecond) < deadline
        if rem(number, 100) == 0, do: IO.puts("NATIVE_NOTES_AUDIT_RECORD=#{number}")

        %{
          "number" => number,
          "key" => expected["key"],
          "record_sha256" => actual["sha256"],
          "metadata" => metadata,
          "encoded_bytes" => actual["bytes"]
        }
      end)

    categories = Enum.frequencies_by(rows, & &1["metadata"]["category"])

    expected_categories =
      actions
      |> Enum.filter(&(&1["op"] == "capture"))
      |> Enum.frequencies_by(fn action ->
        if MapSet.member?(pins, action["number"]), do: "pin", else: action["category"]
      end)

    assert categories === expected_categories
    assert {:ok, ^initial} = ObservedRead.read(collection, namespace, %{"op" => "snapshot"})

    assert {:ok, ^control} =
             Consent.existing_snapshot(
               SemanticAdmission.control_root(home),
               binding["project_id"]
             )

    for source <- sources, do: verify_fingerprint(source)
    verify_files(manifest)

    assert {:ok, status} =
             Collection.execute(collection, namespace, %{"op" => "status"}, Usage.id())

    physical =
      Map.new(
        [
          {"control", SemanticAdmission.control_root(home)},
          {"identity", Path.join(home, "project-identities")},
          {"management", Path.join(home, "knowledge-management")},
          {"sessions", Path.join(home, "sessions")}
        ],
        fn {name, path} ->
          assert {:ok, allocation} = component_allocation(name, path, actions, manifest["kind"])
          {name, allocation}
        end
      )

    measured =
      status["allocated_bytes"] +
        Enum.reduce(physical, 0, fn
          {_, %{"presence" => "absent", "native_allocation" => nil}}, total ->
            total

          {_, %{"allocated_bytes" => bytes}}, total when is_integer(bytes) and bytes >= 0 ->
            total + bytes
        end)

    save(output <> ".rows.json", rows)

    save(output, %{
      "version" => 1,
      "root" => root,
      "kind" => manifest["kind"],
      "manifest" => fingerprint(Path.join(root, "manifest.json")),
      "audit_source" => fingerprint(__ENV__.file),
      "verified_records" => length(rows),
      "verified_categories" => categories,
      "verified_rows" => fingerprint(output <> ".rows.json"),
      "rows_sha256" => JSON.digest([rows]),
      "largest_record_encoded_bytes" => Enum.max(Enum.map(rows, & &1["encoded_bytes"])),
      "root_sha256" => root_sha,
      "snapshot" => initial["value"],
      "unchanged_sources" => length(sources),
      "recorded_event_times" => recorded,
      "recorded_time_scope" =>
        "Selected event-field maxima in retained source journals; not an upper bound on physical completion or proof of clock monotonicity",
      "unchanged_control" => true,
      "unchanged_root" => true,
      "status" => status,
      "physical_allocations" => physical,
      "measured_components_allocated_bytes" => measured,
      "absent_physical_components" => absent_components(physical),
      "allocation_scope" =>
        "Collection plus actual control, identity, management and original Session sources; excludes installed artifacts, frozen SDK and benchmark oracle; no double-counted control reserve",
      "full_6_kib_record_payload_qualification" => false,
      "annual_workload_qualification" => false
    })

    IO.puts("NATIVE_NOTES_AUDIT_CLOSED=#{length(rows)} categories=#{Jason.encode!(categories)}")
  end

  defp initialize(root, kind, fixture_port) do
    assert :os.type() == {:unix, :linux}
    assert String.contains?(to_string(:erlang.system_info(:system_architecture)), "x86_64")
    assert is_nil(System.get_env("IPSE_RUNNER_PATH"))
    assert Path.type(root) == :absolute and Path.expand(root) == root

    assert Path.dirname(root) == "/tmp" and
             String.starts_with?(Path.basename(root), "ipse-native-seed-")

    assert {:error, :enoent} = File.lstat(root)
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    for name <- ~w(runtime checkpoints logs work), do: File.mkdir!(Path.join(root, name))

    for path <- @source_files do
      source = if path == "dev/knowledge/native_notes_seed.ex", do: __ENV__.file, else: path
      File.cp!(source, Path.join(root, "runtime/" <> Path.basename(path)))
    end

    for {source, flags, target} <-
          Enum.reject(
            [
              {"dev/fixtures/process_clock.rs", ["--crate-type=cdylib"], "clock.so"},
              {"test/support/operator_pty.rs", [], "pty"}
            ],
            fn {_, _, target} -> kind == "maximum" and target == "clock.so" end
          ) do
      {output, code} =
        System.cmd(
          "rustc",
          ["--edition=2021", "-D", "warnings", source] ++ flags ++ ["-o", Path.join(root, target)],
          stderr_to_stdout: true
        )

      assert code == 0, output
    end

    paths = current_paths()

    if kind != "maximum" do
      {output, code} =
        System.cmd(
          System.find_executable("elixir"),
          ["--erl", "+S 2:2"] ++
            paths ++
            [
              "-r",
              Path.join(root, "runtime/managed_clock_lifecycle.exs"),
              "-e",
              "Ipse.Test.ManagedClockLifecycle.prepare_stdio_clock(System.argv())",
              root,
              Application.app_dir(:ipse, "ebin")
            ],
          stderr_to_stdout: true
        )

      File.write!(Path.join(root, "logs/runtime-build.log"), output, [:exclusive])
      assert code == 0, output
      # Freeze dependency BEAMs instead of sharing a mutable Mix build directory.
      for path <- :code.get_path(),
          path = List.to_string(path),
          String.contains?(Path.expand(path), "/_build/") and Path.basename(path) == "ebin",
          Path.basename(Path.dirname(path)) != "ipse" do
        target = Path.join(root, "stdio-runtime/" <> Path.basename(Path.dirname(path)) <> "/ebin")
        File.mkdir_p!(Path.dirname(target))
        File.cp_r!(path, target)
      end
    end

    private_files =
      Path.wildcard(Path.join(root, "stdio-runtime/ipse/priv/**/*"))
      |> Enum.filter(&(File.lstat!(&1).type == :regular))

    frozen =
      private_files ++
        Path.wildcard(Path.join(root, "stdio-runtime/*/ebin/*")) ++
        Path.wildcard(Path.join(root, "runtime/*")) ++
        Enum.map(
          if(kind == "maximum", do: ~w(pty), else: ~w(clock.so pty clock-stdio-runtime.json)),
          &Path.join(root, &1)
        )

    manifest = %{
      "version" => 1,
      "kind" => kind,
      "root" => root,
      "created_wall_ms" => System.system_time(:millisecond),
      "plan" => plan(kind),
      "files" => Enum.map(frozen, &fingerprint/1),
      "fixture_sources" =>
        Enum.map(
          ~w(dev/fixtures/process_clock.rs test/support/operator_pty.rs lib/ipse/runner.ex),
          &fingerprint/1
        ),
      "runtime" => %{
        "elixir" => System.version(),
        "otp" => List.to_string(:erlang.system_info(:otp_release)),
        "architecture" => List.to_string(:erlang.system_info(:system_architecture))
      },
      "normal_runtime_ebins" =>
        if(kind == "maximum",
          do: Path.wildcard(Path.join(Path.dirname(Application.app_dir(:ipse)), "*/ebin"))
        ),
      "clock_scope" =>
        if(kind == "maximum",
          do: "normal immutable SDK, actual wall clock; no clock adapter",
          else: "private Runner environment adapter; monotonic/kernel clocks unchanged"
        ),
      "native_statement_bytes" => if(kind == "maximum", do: 999, else: 1024),
      "full_6_kib_record_payload_qualification" => false,
      "annual_workload_qualification" => false
    }

    manifest =
      if fixture_port,
        do: Map.put(manifest, "fixture_port", fixture_port),
        else: manifest

    save(Path.join(root, "manifest.json"), manifest)
    IO.puts("NATIVE_NOTES_SEED_INITIALIZED=#{root} segments=#{length(manifest["plan"])}")
  end

  defp run(root, requested) do
    manifest = manifest(root)

    assert not File.exists?(Path.join(root, "inflight.json")),
           "inflight seed may have effects; inspect without replay"

    completed = closed(root, manifest)
    remaining = length(manifest["plan"]) - length(completed)
    count = if requested == "all", do: remaining, else: String.to_integer(requested)
    assert remaining > 0 and count in 1..remaining

    for index <- (length(completed) + 1)..(length(completed) + count) do
      verify_files(manifest)
      segment = Enum.at(manifest["plan"], index - 1)

      inflight = %{
        "index" => index,
        "day" => segment["day"],
        "manifest_sha256" => JSON.sha256(File.read!(Path.join(root, "manifest.json")))
      }

      save(Path.join(root, "inflight.json"), inflight)
      paths = private_paths(root)

      {output, code} =
        System.cmd(
          Path.join(root, "pty"),
          ["--assertion", System.find_executable("elixir"), "--erl", "+S 2:2 +C multi_time_warp"] ++
            paths ++
            [
              Path.join(root, "runtime/native_notes_seed.exs"),
              "--child",
              root,
              Integer.to_string(index)
            ],
          stderr_to_stdout: true,
          env: [
            {"LD_PRELOAD", if(manifest["kind"] != "maximum", do: Path.join(root, "clock.so"))},
            {"IPSE_TEST_CLOCK_OFFSET_MS",
             if(manifest["kind"] != "maximum", do: Integer.to_string(segment["day"] * @day))},
            {"HOME", root},
            {"IPSE_HOME", Path.join(root, "home")},
            {"TMPDIR", root}
          ]
        )

      log = Path.join(root, "logs/segment-#{index}.log")
      File.write!(log, output, [:exclusive])
      File.chmod!(log, 0o600)

      assert code == 0,
             "native seed segment #{index} stopped; inspect #{log}; inflight retained, no replay"

      report_path = report_path(root, index)
      report = read(report_path)
      assert report["index"] == index and report["closed"] == true

      save(closed_path(root, index), %{
        "index" => index,
        "report" => fingerprint(report_path),
        "log" => fingerprint(log),
        "exit_code" => code
      })

      File.rm!(Path.join(root, "inflight.json"))

      IO.puts(
        "NATIVE_NOTES_SEED_SEGMENT=#{index} day=#{segment["day"]} records=#{report["public_records"]} operations=#{report["snapshot"]["generation"]}"
      )
    end
  end

  defp child(root, index) do
    Process.flag(:max_heap_size, %{size: 16_000_000, kill: true, error_logger: true})
    manifest = manifest(root)
    verify_files(manifest)
    segment = Enum.at(manifest["plan"], index - 1)
    inflight = read(Path.join(root, "inflight.json"))
    assert inflight["index"] == index

    assert inflight["manifest_sha256"] ===
             JSON.sha256(File.read!(Path.join(root, "manifest.json")))

    if manifest["kind"] == "maximum" do
      assert segment["day"] == 0
      assert is_nil(System.get_env("LD_PRELOAD"))
      assert is_nil(System.get_env("IPSE_TEST_CLOCK_OFFSET_MS"))
    else
      assert System.get_env("IPSE_TEST_CLOCK_OFFSET_MS") ==
               Integer.to_string(segment["day"] * @day)
    end

    assert System.system_time(:millisecond) >= manifest["created_wall_ms"] + segment["day"] * @day
    previous = closed(root, manifest)
    assert length(previous) == index - 1

    records =
      Enum.reduce(previous, %{}, fn report, all -> Map.merge(all, report["new_records"]) end)

    for report <- previous, source <- report["sources"], do: verify_fingerprint(source)
    {:ok, _} = Application.ensure_all_started(:ipse)

    if manifest["kind"] != "maximum" do
      modules = Code.require_file(Path.join(root, "runtime/managed_clock_lifecycle.exs"))

      {clock_module, _} =
        Enum.find(modules, fn {module, _} -> module === Ipse.Test.ManagedClockLifecycle end)

      clock_module.check_stdio_clock(root)
    end

    home = Path.join(root, "home")
    cwd = Path.join(root, "work")

    for name <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
        do: System.delete_env(name)

    config_path = Path.join(home, "config.json")

    if index == 1 do
      File.mkdir!(home)
      File.chmod!(home, 0o700)

      seed_config =
        if manifest["fixture_port"],
          do: fixture_config(manifest["fixture_port"]),
          else: %{"version" => 1, "settings" => %{"provider" => "demo", "model" => "scripted"}}

      save(config_path, seed_config)

      assert Ipse.CLI.run([
               "knowledge",
               "enable",
               "--cwd",
               cwd,
               "--config",
               config_path,
               "--no-project-config"
             ]) == 0
    end

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
             Ipse.Config.resolve(cwd, home, [config: config_path, project_config: false], %{})

    assert {:ok, config} = Ipse.Config.runtime(effective, client)
    config = Map.merge(config, %{provider_module: NoModel, fixture_root: root})
    dir = Path.join(home, "sessions")
    assert {:ok, binding} = ProjectIdentity.existing(home, cwd)

    assert {:ok, namespace} =
             Ipse.Extension.SemanticConsent.namespace(binding["project_id"], "knowledge")

    collection = SemanticAdmission.collection_root(home)

    if previous != [] do
      assert {:ok, snapshot} =
               Collection.execute(collection, namespace, %{"op" => "snapshot"}, Usage.id())

      assert snapshot === List.last(previous)["snapshot"]
      assert visible(collection, namespace) === expected_records(records)
    end

    owner = self()
    telemetry = "native-seed-" <> Usage.id()

    :ok =
      :telemetry.attach(
        telemetry,
        [:ipse, :extension, :collection, :staged],
        fn _, m, _, _ ->
          send(
            owner,
            {:seed_allocation, m.accounted_allocated_bytes + m.root_publication_reserved_bytes}
          )
        end,
        nil
      )

    assert {:ok, session} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, config: config, cwd: cwd, state_dir: dir, subscriber: self()}
             )

    id = Session.info(session).id
    assert {:ok, channel} = Session.open_input_channel(session, self())
    captures = Enum.filter(segment["actions"], &(&1["op"] == "capture"))

    measurements =
      Enum.with_index(captures, 1)
      |> Enum.map(fn {action, step} ->
        started = System.monotonic_time(:microsecond)
        command = "/remember #{action["category"]} " <> text(action["number"], manifest["kind"])
        File.write!(Path.join(root, "supersession-input-#{step}"), command)
        IO.write("IPSE_SUPERSESSION_READ_#{step}> ")

        assert {:ok, ^command, witness} =
                 Session.observe_channel(session, channel, %{"kind" => "prompt"}, 30_000)

        assert {:ok, ticket} = Session.stage_input(session, channel, command, witness)

        assert {:ok, %{"render_id" => render}} =
                 Session.prepare_assertion(session, channel, command, ticket)

        assert {:ok, input, observed} =
                 Session.observe_channel(
                   session,
                   channel,
                   %{"kind" => "assertion", "render_id" => render},
                   30_000
                 )

        assert :ok = Session.accept_assertion_observed(session, channel, render, input, observed)
        assert_receive {:ipse, ^session, {:done, :ok}}, 30_000
        System.monotonic_time(:microsecond) - started
      end)

    maximum =
      if manifest["kind"] == "maximum",
        do:
          maximum_refusals(session, channel, root, dir, id, collection, namespace, home, binding),
        else: nil

    assert :ok = Session.close_confirmed(session)
    assert {:ok, events} = Journal.load(dir, id)

    assert {:ok, _} = Session.Saved.restore(events, id)

    assert {:ok, %{"release_claim" => "signed_release_claim"}} =
             Session.Saved.inspect_saved(dir, id)

    commits =
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "op"]) == "collection.managed" and
            get_in(&1, ["outcome", "status"]) == "ok")
      )

    assert length(commits) == length(captures)

    delta =
      Enum.zip(captures, commits)
      |> Map.new(fn {action, event} ->
        [change] = event["request"]["request"]["changes"]
        value = change["value"]
        assert value["text"] == text(action["number"], manifest["kind"])
        assert value["category"] == action["category"]
        [proof] = value["evidence"]["sources"]
        assert proof["origin"] == "native_operator_assertion" and proof["quote"] == value["text"]

        {Integer.to_string(action["number"]),
         %{"key" => change["key"], "value" => value, "category" => action["category"]}}
      end)

    maximum =
      if maximum do
        [accepted] = Map.values(delta)
        value = accepted["value"]
        [proof] = value["evidence"]["sources"]
        geometry = maximum_geometry(value["created_at_ms"])
        assert byte_size(Jason.encode!(proof)) == geometry["proof_encoded_bytes"]

        assert byte_size(Collection.Migration.encode(value)) ==
                 geometry["predicted_note_value_bytes"]

        intent =
          Enum.find(
            events,
            &(&1["type"] == "extension_invocation_intent" and
                &1["invocation_id"] == maximum["refusal_invocation_id"])
          )

        result =
          Enum.find(
            events,
            &(&1["type"] == "extension_invocation_result" and
                &1["invocation_id"] == maximum["refusal_invocation_id"])
          )

        assert {:ok, refusal} = maximum_inline_refusal(intent, result)
        intents = invocation_intents(events)

        assert {:ok, idle} =
                 DynamicSupervisor.start_child(
                   Ipse.Sessions,
                   {Session, config: config, cwd: cwd, state_dir: dir, subscriber: self(), id: id}
                 )

        assert Session.info(idle).phase == :idle
        assert :ok = Session.close_confirmed(idle)
        assert :sys.get_state(Ipse.Session.Input).entries == %{}
        assert {:ok, reopened} = Journal.load(dir, id)
        assert {:ok, _} = Session.Saved.restore(reopened, id)
        assert invocation_intents(reopened) === intents

        assert {:ok, unchanged} =
                 Collection.execute(collection, namespace, %{"op" => "snapshot"}, Usage.id())

        assert unchanged === maximum["snapshot"]

        Map.merge(maximum, geometry)
        |> Map.merge(%{
          "actual_proof_encoded_bytes" => byte_size(Jason.encode!(proof)),
          "actual_note_value_bytes" => byte_size(Collection.Migration.encode(value)),
          "idle_reopen_no_replay" => true,
          "refusal_code" => refusal["code"]
        })
      end

    records = Map.merge(records, delta)

    management_before = Path.wildcard(Path.join(home, "knowledge-management/*.jsonl"))

    for action <- segment["actions"], action["op"] == "pin" do
      assert {:ok, _} =
               Management.retain(
                 config,
                 cwd,
                 records[Integer.to_string(action["number"])]["key"],
                 %{"kind" => "pin"}
               )
    end

    :ok = :telemetry.detach(telemetry)
    allocations = allocations([])
    assert length(allocations) == length(segment["actions"])

    assert {:ok, snapshot} =
             Collection.execute(collection, namespace, %{"op" => "snapshot"}, Usage.id())

    executed =
      manifest["plan"] |> Enum.take(index) |> Enum.map(&length(&1["actions"])) |> Enum.sum()

    assert snapshot["generation"] == executed and snapshot["floor"] == executed
    assert visible(collection, namespace) === expected_records(records)
    assert {:ok, selected} = Management.selection(home)

    for action <- segment["actions"] do
      target = records[Integer.to_string(action["number"])]

      assert {:ok, managed} =
               ProjectIdentity.with_existing_domain_auth(
                 home,
                 cwd,
                 binding,
                 %{namespace: namespace, format: "managed-metadata-v3"},
                 fn cap, catalog ->
                   ObservedRead.with_managed_note_record(
                     collection,
                     namespace,
                     %{"op" => "get_record", "key" => target["key"]},
                     cap,
                     catalog,
                     selected.recipe,
                     &{:ok, &1}
                   )
                 end
               )

      assert managed["observation"]["value"]["record"]["value"] === target["value"]

      category =
        if action["op"] == "pin" or
             Enum.any?(
               segment["actions"],
               &(&1["op"] == "pin" and &1["number"] == action["number"])
             ), do: "pin", else: target["category"]

      assert managed["metadata"]["category"] == category
      first = managed["metadata"]["first_admitted_ms"]
      assert first >= manifest["created_wall_ms"] + segment["day"] * @day

      assert managed["metadata"]["valid_until_ms"] ==
               if(category == "ordinary", do: first + 90 * @day, else: nil)
    end

    assert {:ok, status} =
             Collection.execute(collection, namespace, %{"op" => "status"}, Usage.id())

    assert {:ok, control} =
             Consent.existing_snapshot(
               SemanticAdmission.control_root(home),
               binding["project_id"]
             )

    assert control["sequence"] == executed
    assert map_size(control["operations"]) + map_size(control["compacted"]) == executed

    assert Enum.all?(control["operations"], fn {_, operation} ->
             operation["status"] == "settled" and operation["actual"]["operations"] == 1 and
               operation["actual"]["model_calls"] == 0
           end)

    assert not File.exists?(Path.join(root, "unexpected-model"))
    for report <- previous, source <- report["sources"], do: verify_fingerprint(source)

    sources =
      [Path.join(dir, id <> ".jsonl")] ++
        (Path.wildcard(Path.join(home, "knowledge-management/*.jsonl")) -- management_before)

    physical =
      Map.new(
        [
          {"control", SemanticAdmission.control_root(home)},
          {"identity", Path.join(home, "project-identities")},
          {"management", Path.join(home, "knowledge-management")},
          {"sessions", dir}
        ],
        fn {name, path} ->
          assert {:ok, allocation} =
                   component_allocation(name, path, segment["actions"], manifest["kind"])

          {name, allocation}
        end
      )

    report = %{
      "version" => 1,
      "index" => index,
      "day" => segment["day"],
      "closed" => true,
      "snapshot" => snapshot,
      "status" => status,
      "new_records" => delta,
      "largest_new_record_encoded_bytes" =>
        delta
        |> Map.values()
        |> Enum.map(&byte_size(Collection.Migration.encode(&1["value"])))
        |> Enum.max(),
      "public_records" => map_size(records),
      "sources" => Enum.map(sources, &fingerprint/1),
      "capture_elapsed_us" => measurements,
      "staged_accounted_allocation_peak" => Enum.max(allocations),
      "staged_publications" => length(allocations),
      "control_sequence" => control["sequence"],
      "control_sha256" => JSON.digest([control]),
      "physical_allocations" => physical,
      "absent_physical_components" => absent_components(physical),
      "beam_memory_after_segment" => :erlang.memory(:total),
      "maximum_payload_boundary" => maximum,
      "annual_workload_qualification" => false,
      "initial_seed_complete" =>
        manifest["kind"] == "initial" and index == length(manifest["plan"])
    }

    save(report_path(root, index), report)
    IO.puts("NATIVE_NOTES_SEED_CLOSED=#{index}")
  end

  defp visible(root, namespace) do
    {:ok, snapshot} = Collection.execute(root, namespace, %{"op" => "snapshot"}, Usage.id())
    visible(root, namespace, nil, snapshot["generation"], %{})
  end

  defp visible(root, namespace, after_key, generation, records) do
    {:ok, page} =
      Collection.scan_visible(
        root,
        namespace,
        %{"op" => "scan", "after" => after_key, "generation" => generation, "limit" => 32},
        Usage.id()
      )

    records = Enum.reduce(page["records"], records, &Map.put(&2, &1["key"], &1["value"]))

    if is_nil(page["next"]),
      do: records,
      else: visible(root, namespace, page["next"], page["generation"], records)
  end

  defp expected_records(records),
    do: Map.new(records, fn {_, item} -> {item["key"], item["value"]} end)

  defp allocations(values) do
    receive do
      {:seed_allocation, bytes} -> allocations([bytes | values])
    after
      0 -> values
    end
  end

  @doc "Describe only the absent management component of a capture-only maximum fixture."
  def absent_management_storage(path, actions) when is_binary(path) and is_list(actions) do
    with true <- actions != [] and Enum.all?(actions, &(is_map(&1) and &1["op"] == "capture")),
         {:error, :enoent} <- File.lstat(path) do
      {:ok,
       %{
         "presence" => "absent",
         "basis" => "lstat_enoent_no_management_actions",
         "native_allocation" => nil,
         "missing_dimensions" => ~w(logical_bytes allocated_bytes entries)
       }}
    else
      _ -> {:error, :native_seed_management_storage_unavailable}
    end
  end

  def absent_management_storage(_, _), do: {:error, :native_seed_management_storage_unavailable}

  defp component_allocation("management", path, actions, "maximum"),
    do: absent_management_storage(path, actions)

  defp component_allocation(_, path, _, _), do: Ipse.Runner.storage_allocation(path)

  defp absent_components(physical),
    do: for({name, %{"presence" => "absent"}} <- physical, do: name)

  defp maximum_refusals(session, channel, root, dir, id, collection, namespace, home, binding) do
    assert {:ok, before_events} = Journal.load(dir, id)

    assert {:ok, before_snapshot} =
             Collection.execute(collection, namespace, %{"op" => "snapshot"}, Usage.id())

    before_records = visible(collection, namespace)

    assert {:ok, control_before} =
             Consent.existing_snapshot(
               SemanticAdmission.control_root(home),
               binding["project_id"]
             )

    geometry = maximum_geometry(System.system_time(:millisecond))
    command = "/remember ordinary " <> maximum_statement(geometry["json_escape_count"] + 1)
    native_assertion(session, channel, root, 2, command)
    assert_receive {:ipse, ^session, {:done, :ok}}, 30_000
    assert {:ok, refused_events} = Journal.load(dir, id)
    assert Enum.take(refused_events, length(before_events)) === before_events

    [result] =
      Enum.filter(
        Enum.drop(refused_events, length(before_events)),
        &(&1["type"] == "extension_invocation_result")
      )

    [intent] =
      Enum.filter(
        Enum.drop(refused_events, length(before_events)),
        &(&1["type"] == "extension_invocation_intent")
      )

    assert {:ok, _} = Session.Saved.restore(refused_events, id)

    assert {:ok, %{"status" => "refused", "code" => "source_refused"}} =
             maximum_inline_refusal(intent, result)

    assert {:ok, ^before_snapshot} =
             Collection.execute(collection, namespace, %{"op" => "snapshot"}, Usage.id())

    assert visible(collection, namespace) === before_records
    command = "/remember ordinary " <> String.duplicate("x", 1025)
    File.write!(Path.join(root, "supersession-input-3"), command)
    IO.write("IPSE_SUPERSESSION_READ_3> ")

    assert {:ok, ^command, witness} =
             Session.observe_channel(session, channel, %{"kind" => "prompt"}, 30_000)

    assert {:ok, ticket} = Session.stage_input(session, channel, command, witness)

    assert {:error, :operator_assertion_refused} =
             Session.prepare_assertion(session, channel, command, ticket)

    assert {:ok, after_events} = Journal.load(dir, id)
    assert after_events === refused_events

    assert {:ok, ^before_snapshot} =
             Collection.execute(collection, namespace, %{"op" => "snapshot"}, Usage.id())

    assert visible(collection, namespace) === before_records

    assert {:ok, control_after} =
             Consent.existing_snapshot(
               SemanticAdmission.control_root(home),
               binding["project_id"]
             )

    assert control_after === control_before

    %{
      "refusal_invocation_id" => result["invocation_id"],
      "snapshot" => before_snapshot,
      "proof_over_limit_bytes" => geometry["next_escape_proof_bytes"],
      "source_over_limit_bytes" => 1025,
      "old_head_and_values_unchanged" => true,
      "saved_consent_accounting_unchanged" => true,
      "accepted_prefix_sha256" => JSON.digest(before_events),
      "source_limit_refused_before_append" => true
    }
  end

  defp native_assertion(session, channel, root, step, command) do
    File.write!(Path.join(root, "supersession-input-#{step}"), command)
    IO.write("IPSE_SUPERSESSION_READ_#{step}> ")

    assert {:ok, ^command, witness} =
             Session.observe_channel(session, channel, %{"kind" => "prompt"}, 30_000)

    assert {:ok, ticket} = Session.stage_input(session, channel, command, witness)

    assert {:ok, %{"render_id" => render}} =
             Session.prepare_assertion(session, channel, command, ticket)

    assert {:ok, input, observed} =
             Session.observe_channel(
               session,
               channel,
               %{"kind" => "assertion", "render_id" => render},
               30_000
             )

    assert :ok = Session.accept_assertion_observed(session, channel, render, input, observed)
  end

  @doc "Inspect a small inline refusal; this grants no source or mutation authority."
  def maximum_inline_refusal(intent, result) when is_map(intent) and is_map(result) do
    with :ok <- Ipse.Extension.Invocation.validate_intent(intent),
         true <- result["type"] == "extension_invocation_result" and result["version"] in [1, 3],
         true <- Ipse.Extension.Invocation.result_intent(result) === intent,
         true <- result["payload_sha256"] == JSON.digest([result["payload"]]),
         true <-
           is_binary(result["text"]) and result["text_sha256"] == JSON.sha256(result["text"]),
         {:ok, value} <- JSON.decode_bounded(result["text"]),
         true <- Ipse.Extension.Invocation.delivery(result) === %{"value" => value},
         true <- value === %{"status" => "refused", "code" => "source_refused"} do
      {:ok, value}
    else
      _ -> {:error, :maximum_inline_refusal_unavailable}
    end
  rescue
    _ -> {:error, :maximum_inline_refusal_unavailable}
  end

  def maximum_inline_refusal(_, _), do: {:error, :maximum_inline_refusal_unavailable}

  defp invocation_intents(events),
    do: Enum.filter(events, &(&1["type"] == "extension_invocation_intent"))

  defp text(_number, "maximum"),
    do: maximum_statement(maximum_geometry(System.system_time(:millisecond))["json_escape_count"])

  defp text(number, _kind), do: text(number)

  defp text(number) do
    prefix = "Native capacity source #{number}: "
    body = Enum.map_join(1..17, " ", &JSON.sha256("native capacity #{number}:#{&1}"))
    prefix <> binary_part(body, 0, 1024 - byte_size(prefix))
  end

  defp current_paths, do: Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

  defp private_paths(root) do
    paths =
      manifest(root)["normal_runtime_ebins"] ||
        Path.wildcard(Path.join(root, "stdio-runtime/*/ebin"))

    Enum.flat_map(paths, &["-pa", &1])
  end

  defp report_path(root, index), do: Path.join(root, "checkpoints/report-#{index}.json")
  defp closed_path(root, index), do: Path.join(root, "checkpoints/closed-#{index}.json")

  defp closed(root, manifest) do
    Enum.reduce_while(1..length(manifest["plan"]), [], fn index, reports ->
      if File.exists?(closed_path(root, index)) do
        closed = read(closed_path(root, index))
        assert closed["index"] == index and closed["exit_code"] == 0
        verify_fingerprint(closed["report"])
        verify_fingerprint(closed["log"])
        {:cont, reports ++ [read(report_path(root, index))]}
      else
        assert Path.wildcard(Path.join(root, "checkpoints/closed-*.json")) |> length() ==
                 length(reports)

        {:halt, reports}
      end
    end)
  end

  defp manifest(root) do
    assert Path.dirname(root) == "/tmp" and
             String.starts_with?(Path.basename(root), "ipse-native-seed-")

    assert File.lstat!(root).type == :directory and
             Bitwise.band(File.stat!(root).mode, 0o077) == 0

    manifest = read(Path.join(root, "manifest.json"))
    assert manifest["root"] == root and manifest["plan"] === plan(manifest["kind"])
    assert is_nil(manifest["fixture_port"]) or manifest["fixture_port"] in 1..65_535
    manifest
  end

  defp verify_files(manifest), do: Enum.each(manifest["files"], &verify_fingerprint/1)
  defp verify_fingerprint(item), do: assert(fingerprint(item["path"]) === item)

  defp fingerprint(path),
    do: %{
      "path" => path,
      "bytes" => File.stat!(path).size,
      "sha256" => JSON.sha256(File.read!(path))
    }

  defp read(path), do: path |> File.read!() |> Jason.decode!()

  defp save(path, value) do
    File.write!(path, Jason.encode!(value) <> "\n", [:exclusive])
    File.chmod!(path, 0o600)
  end
end
