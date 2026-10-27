defmodule Ipse.Development.StoragePlanningProbe do
  @moduledoc false
  alias Ipse.Extension.Collection, as: C
  alias Ipse.Extension.Collection.{Encoding, Migration}
  alias Ipse.Runner.Transaction, as: T
  @count 4096
  @operations 20_950
  @control 22 * 1024 * 1024

  def run(args) do
    Process.flag(:max_heap_size, %{size: 16_000_000, kill: true, error_logger: true})
    {options, [], []} = OptionParser.parse(args, strict: [parent: :string, output: :string])
    {:ok, base} = Ipse.Workspace.canonical_path(Path.expand(Keyword.fetch!(options, :parent)))
    parent = Path.join(base, "planning-probe-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    root = Path.join(parent, "collections")
    project = Ipse.JSON.sha256("independent physical planning probe")
    filesystem = filesystem(parent)
    true = filesystem["type"] == "btrfs"
    location = %{"root" => root, "project" => project}
    output = Keyword.fetch!(options, :output)
    File.write!(output <> ".location.json", Jason.encode!(location, pretty: true) <> "\n")
    IO.puts(:stderr, "planning fixture retained at #{root}")
    {:ok, _} = C.execute(root, project, %{"op" => "snapshot"}, Ipse.Usage.id())
    path = Path.join(root, project)
    {:ok, cap} = T.acquire(Path.join(path, ".lock"), cwd: parent, timeout_ms: 120_000)
    :ok = T.quota(cap, :collection, 42 * 1024 * 1024)

    {peak, records} =
      try do
        Enum.reduce(Enum.chunk_every(1..@count, 128), {0, %{}}, fn chunk, {peak, records} ->
          values =
            Enum.map(chunk, fn n ->
              value = value(n)
              bytes = Migration.encode(value)
              true = byte_size(bytes) == 6144
              hash = Ipse.JSON.sha256(bytes)
              {"note#{n}", hash, bytes, ".pending-" <> Ipse.Usage.id()}
            end)

          :ok =
            T.stage(
              cap,
              "objects",
              Enum.map(values, fn {_, _, bytes, pending} -> {pending, bytes} end)
            )

          {:ok, allocation} = T.allocation(cap)
          peak = max(peak, allocation.allocated + @control)

          Enum.each(values, fn {_, hash, _, pending} ->
            :ok = T.install(cap, "objects", pending, hash <> ".json")
          end)

          records =
            Enum.reduce(values, records, fn {key, hash, bytes, _}, rows ->
              Map.put(rows, key, %{
                "key" => key,
                "sha256" => hash,
                "bytes" => byte_size(bytes),
                "revision" => 1,
                "operation_id" => id(1)
              })
            end)

          {peak, records}
        end)
      rescue
        error ->
          T.release(cap)
          reraise error, __STACKTRACE__
      end

    true =
      records |> Map.values() |> Enum.map(& &1["sha256"]) |> Enum.uniq() |> length() == @count

    operations =
      Map.new(1..@operations, fn n ->
        {id(n),
         %{
           "generation" => n,
           "floor" => 0,
           "request_sha256" => Ipse.JSON.sha256("independent synthetic planning receipt #{n}")
         }}
      end)

    state = %{
      "version" => 3,
      "project" => project,
      "generation" => @operations,
      "floor" => 0,
      "floor_anchor" => nil,
      "floor_lineage" => [],
      "records" => records,
      "operations" => operations,
      "imported_operations" => %{},
      "migration" => nil,
      "checkpoint" => nil
    }

    bytes = Encoding.encode(state)
    manifest = Ipse.JSON.sha256(bytes)
    pending = ".pending-" <> Ipse.Usage.id()
    :ok = T.stage(cap, "manifests", [{pending, bytes}])
    :ok = T.install(cap, "manifests", pending, manifest <> ".json")
    pending = ".pending-" <> Ipse.Usage.id()

    pointer =
      state
      |> Map.take(~w(version project generation floor floor_anchor))
      |> Map.put("manifest", manifest)
      |> Jason.encode!()

    :ok = T.stage(cap, ".", [{pending, pointer}])
    {:ok, allocation} = T.allocation(cap)
    peak = max(peak, allocation.allocated + @control)
    :ok = T.switch(cap, pending, "root.json")
    :ok = T.release(cap)
    {:ok, before} = C.execute(root, project, %{"op" => "status"}, Ipse.Usage.id())

    {:ok, exported} =
      C.execute(
        root,
        project,
        %{"op" => "export.plan", "generation" => @operations},
        Ipse.Usage.id()
      )

    result =
      C.execute(
        root,
        project,
        %{
          "op" => "import.open",
          "expected_generation" => @operations,
          "descriptor" => exported["descriptor"],
          "plan" => exported["plan"]
        },
        Ipse.Usage.id()
      )

    {:ok, after_status} = C.execute(root, project, %{"op" => "status"}, Ipse.Usage.id())
    {:ok, helper} = Ipse.Runner.protected_helper(parent)

    report = %{
      "kind" => "independent_physical_planning_fixture",
      "qualification_passed" => false,
      "individual_operations_performed" => false,
      "synthetic_receipts" => @operations,
      "distinct_values" => @count,
      "value_bytes" => 6144,
      "persistent_policy_exercised" => false,
      "control_stress_overlap" => true,
      "latency_qualified" => false,
      "retained_store" => location,
      "native_helper_sha256" => Ipse.JSON.sha256(File.read!(helper)),
      "filesystem" => filesystem,
      "kernel" => inspect(:os.version()),
      "peak_accounted_allocated_bytes" => peak,
      "fixture_manifest_bytes" => byte_size(bytes),
      "fixture_manifest_sha256" => manifest,
      "descriptor" => exported["descriptor"],
      "plan_sha256" => Ipse.JSON.digest([exported["plan"]]),
      "import_open_result" => inspect(result),
      "before" => before,
      "after" => after_status,
      "sources" =>
        Map.new(
          ~w(lib/ipse/extension/collection.ex lib/ipse/extension/collection/migration.ex lib/ipse/extension/collection/encoding.ex lib/ipse/extension/collection/planning.ex native/ipse-storage-profile.rs dev/knowledge/storage_planning_probe.exs),
          fn file -> {file, Ipse.JSON.sha256(File.read!(file))} end
        )
    }

    if match?({:failed, _}, result) do
      true =
        before["generation"] == after_status["generation"] and
          before["floor"] == after_status["floor"]

      true = is_nil(after_status["migration"])
    end

    File.write!(output, Jason.encode!(report, pretty: true) <> "\n")

    IO.puts(
      Jason.encode!(
        Map.take(
          report,
          ~w(import_open_result peak_accounted_allocated_bytes fixture_manifest_bytes)
        )
      )
    )
  end

  defp value(n) do
    base = %{
      "text" => "independent fixture #{n}",
      "evidence" => %{"source" => "synthetic:#{n}", "padding" => ""}
    }

    count = 6144 - byte_size(Migration.encode(base))

    padding =
      for piece <- 0..div(count + 42, 43),
          do: Base.encode64(:crypto.hash(:sha256, "#{n}:#{piece}"), padding: false)

    put_in(
      base,
      ["evidence", "padding"],
      padding |> IO.iodata_to_binary() |> binary_part(0, count)
    )
  end

  defp id(n), do: n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")

  defp filesystem(path) do
    {text, 0} = System.cmd("stat", ["-f", "-c", "%T %S %s", path])
    [type, fragment, block] = String.split(text)
    {:ok, data} = File.open("/proc/self/mountinfo", [:read, :binary], &IO.binread(&1, 1_048_577))
    true = is_binary(data) and byte_size(data) <= 1_048_576

    selected =
      data
      |> String.split("\n", trim: true)
      |> Enum.flat_map(fn row ->
        [left, right] = String.split(row, " - ", parts: 2)

        point =
          left
          |> String.split()
          |> Enum.at(4)
          |> String.replace("\\040", " ")
          |> String.replace("\\134", "\\")

        if path == point or String.starts_with?(path, String.trim_trailing(point, "/") <> "/"),
          do: [{byte_size(point), right}],
          else: []
      end)
      |> Enum.max_by(&elem(&1, 0))
      |> elem(1)
      |> String.split()

    [_type, _source | options] = selected

    options =
      options
      |> Enum.join(",")
      |> String.split(",")
      |> Enum.filter(
        &Regex.match?(
          ~r/\A(?:rw|ro|ssd|compress=[a-z0-9:]+|discard=[a-z]+|space_cache=[a-z0-9]+|huge=[a-z]+)\z/,
          &1
        )
      )

    %{
      "type" => type,
      "fragment_size" => String.to_integer(fragment),
      "block_size" => String.to_integer(block),
      "mount_options" => options
    }
  end
end

Ipse.Development.StoragePlanningProbe.run(System.argv())
