Code.require_file("../../../dev/knowledge/native_notes_integrated.ex", __DIR__)
Code.require_file("../../../dev/fixtures/synthetic_ollama.exs", __DIR__)

defmodule Ipse.Development.NativeNotesIntegratedTest do
  use ExUnit.Case, async: false
  alias Ipse.Development.{NativeNotesIntegrated, SyntheticOllama}

  test "the frozen smoke schedule interleaves four native effects and forty distinct turns" do
    schedule = NativeNotesIntegrated.smoke_schedule()
    assert Enum.map(schedule, & &1["segment"]) == [1, 2, 3, 4]
    assert Enum.all?(schedule, &(&1["process_offset_day"] == 2 and &1["turns"] == 10))

    turns =
      Enum.flat_map(schedule, fn item ->
        Enum.to_list(item["first_turn"]..(item["first_turn"] + item["turns"] - 1))
      end)

    assert turns == Enum.to_list(1..40)
    assert length(Enum.uniq(Enum.map(turns, &SyntheticOllama.prompt/1))) == 40
  end

  test "any prior run or turn receipt refuses automatic restart" do
    dir =
      Path.join(System.tmp_dir!(), "ipse-integrated-guard-#{System.unique_integer([:positive])}")

    File.mkdir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    assert NativeNotesIntegrated.new_run?(dir)

    for name <- [
          "run-intent.json",
          "effect-1.log",
          "effect-1-intent.json",
          "turn-1-inflight.json",
          "turn-1-result.json",
          "turns-1.json",
          "turns-1.log",
          "complete.json"
        ] do
      File.write!(Path.join(dir, name), "{}")
      refute NativeNotesIntegrated.new_run?(dir)
      File.rm!(Path.join(dir, name))
    end

    assert NativeNotesIntegrated.new_run?(dir)
  end

  test "synthetic evidence destination rejects existing paths and symlinks" do
    dir =
      Path.join(System.tmp_dir!(), "ipse-evidence-guard-#{System.unique_integer([:positive])}")

    File.mkdir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    File.mkdir!(Path.join(dir, "existing-dir"))
    File.write!(Path.join(dir, "existing-file"), "unchanged")
    File.ln_s!(Path.join(dir, "existing-dir"), Path.join(dir, "dir-link"))
    File.ln_s!(Path.join(dir, "missing"), Path.join(dir, "dangling-link"))

    assert safe_evidence_destination?(Path.join(dir, "new"))
    refute safe_evidence_destination?(Path.join(dir, "existing-dir"))
    refute safe_evidence_destination?(Path.join(dir, "existing-file"))
    refute safe_evidence_destination?(Path.join(dir, "dir-link"))
    refute safe_evidence_destination?(Path.join(dir, "dangling-link"))
    refute safe_evidence_destination?(Path.join(dir, "dir-link/new"))
    refute safe_evidence_destination?("relative-path")
    assert File.read!(Path.join(dir, "existing-file")) == "unchanged"
  end

  @tag timeout: 900_000
  @tag :native_integrated_smoke
  @tag skip:
         if(System.get_env("IPSE_TEST_INTEGRATED_SMOKE") == "1",
           do: false,
           else: "native 40-turn workload is an opt-in development qualification"
         )
  test "a fresh admitted synthetic cohort executes native effects and forty actual Session turns" do
    evidence = System.get_env("IPSE_TEST_INTEGRATED_EVIDENCE_DIR")

    if evidence do
      assert safe_evidence_destination?(evidence),
             "evidence destination must be new and have no symlink ancestors"
    end

    root = Path.join("/tmp", "ipse-native-seed-integrated-#{Ipse.Usage.id()}")
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    :ok = :gen_tcp.close(listener)

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    script = Path.expand("dev/knowledge/native_notes_integrated.exs")

    run = fn args ->
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2 +C multi_time_warp"] ++ paths ++ [script] ++ args,
        stderr_to_stdout: true
      )
    end

    {prepared, 0} = run.(["--prepare", root, Integer.to_string(port)])
    assert prepared =~ "NATIVE_INTEGRATED_SMOKE_PREPARED"
    {completed, 0} = run.(["--run", root])
    assert completed =~ "NATIVE_INTEGRATED_SMOKE_COMPLETED turns=40 effects=4"

    assert %{"turns" => 40, "native_effects" => 4, "audit" => audit, "qualification" => false} =
             root |> Path.join("integrated/complete.json") |> File.read!() |> Jason.decode!()

    assert audit["sha256"] == Ipse.JSON.sha256(File.read!(audit["path"]))

    closure = File.read!(Path.join(root, "turnover/closed-4.json"))
    audit_bytes = File.read!(audit["path"])
    {refused, status} = run.(["--run", root])
    assert status != 0
    assert refused =~ "inspect retained evidence and do not replay"
    assert File.read!(Path.join(root, "turnover/closed-4.json")) == closure
    assert File.read!(audit["path"]) == audit_bytes
    assert length(Path.wildcard(Path.join(root, "integrated/turn-*-result.json"))) == 40
    if evidence, do: retain_evidence!(root, evidence)
    File.rm_rf!(root)
    audit = Path.join("/tmp", "ipse-native-seed-audit-#{Ipse.JSON.sha256(root)}.json")
    for suffix <- ["", ".log", ".driver.ex", ".rows.json"], do: File.rm(audit <> suffix)
  end

  defp safe_evidence_destination?(path) do
    Path.type(path) == :absolute and Path.expand(path) == path and
      match?({:error, :enoent}, File.lstat(path)) and real_directory?(Path.dirname(path))
  end

  defp real_directory?(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :directory}} ->
        parent = Path.dirname(path)
        parent == path or real_directory?(parent)

      _ ->
        false
    end
  end

  defp retain_evidence!(root, destination) do
    assert safe_evidence_destination?(destination)
    File.mkdir!(destination)
    File.chmod!(destination, 0o700)

    for dir <- ["integrated", "turnover"] do
      path = Path.join(destination, dir)
      File.mkdir!(path)
      File.chmod!(path, 0o700)
    end

    files =
      [
        "integrated/prepared.json",
        "integrated/run-intent.json",
        "integrated/audit.json",
        "integrated/complete.json"
      ] ++
        for(i <- 1..4, do: "integrated/effect-#{i}-intent.json") ++
        for(i <- 1..4, do: "integrated/turns-#{i}.json") ++
        for(i <- 1..4, do: "turnover/closed-#{i}.json") ++
        for(i <- 1..40, kind <- ["intent", "result"], do: "integrated/turn-#{i}-#{kind}.json")

    entries =
      Enum.map(files, fn relative ->
        source = Path.join(root, relative)
        target = Path.join(destination, relative)
        File.cp!(source, target)
        File.chmod!(target, 0o600)
        File.open!(target, [:read, :binary], fn io -> :ok = :file.sync(io) end)
        bytes = File.read!(target)
        assert bytes == File.read!(source)
        %{"path" => relative, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
      end)

    for dir <- ["integrated", "turnover"] do
      assert :ok = Ipse.Runner.protected_sync_directory(Path.join(destination, dir))
    end

    overlay =
      Enum.map(
        ~w(dev/knowledge/native_notes_seed.ex dev/knowledge/native_notes_integrated.ex dev/knowledge/native_notes_integrated.exs dev/fixtures/synthetic_ollama.exs test/dev/knowledge/native_notes_seed_test.exs test/dev/knowledge/native_notes_integrated_test.exs),
        fn path ->
          bytes = File.read!(path)
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
        end
      )

    manifest = %{
      "version" => 1,
      "status" => "complete",
      "qualification" => false,
      "synthetic_only" => true,
      "turns" => 40,
      "native_effects" => 4,
      "replay_refused" => true,
      "source_overlay" => overlay,
      "files" => entries
    }

    pending = Path.join(destination, "manifest.pending")

    File.open!(pending, [:write, :binary, :exclusive], fn io ->
      File.chmod!(pending, 0o600)
      IO.binwrite(io, Jason.encode!(manifest) <> "\n")
      :ok = :file.sync(io)
    end)

    File.rename!(pending, Path.join(destination, "manifest.json"))
    assert :ok = Ipse.Runner.protected_sync_directory(destination)
    IO.puts("NATIVE_INTEGRATED_SYNTHETIC_EVIDENCE=#{destination}")
  end
end
