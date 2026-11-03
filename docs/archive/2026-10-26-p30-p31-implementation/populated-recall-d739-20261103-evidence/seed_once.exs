Code.require_file("native_notes_seed.ex", __DIR__)

defmodule Ipse.Development.PopulatedSeedOnce do
  import ExUnit.Assertions
  alias Ipse.{JSON, Runner}
  alias Ipse.Development.NativeNotesSeed

  @inputs ~w(populated-build.sha256 populated-source.sha256 populated-fixtures.sha256 populated-critical.sha256 v4-final-source.sha256)

  def main(args) do
    {root, evidence, kind, records} =
      case args do
        ["--smoke"] ->
          {"/dev/shm/ipse-native-seed-recall-smoke-d739-20261103-04",
           "/dev/shm/ipse-recall-seed-smoke-d739-20261103-04", "smoke", 7}

        ["--initial"] ->
          {"/dev/shm/ipse-native-seed-recall-d739-20261103-01",
           "/dev/shm/ipse-recall-seed-populated-d739-20261103-01", "initial", 2000}

        _ ->
          raise "use --smoke or --initial; never restart an existing root"
      end

    audit_path = Path.join(evidence, "ipse-native-seed-audit-#{JSON.sha256(root)}.json")
    assert Path.expand(root) == root and Path.expand(evidence) == evidence
    assert {:error, :enoent} = File.lstat(root)
    assert {:error, :enoent} = File.lstat(evidence)

    for path <- [
          audit_path,
          audit_path <> ".log",
          audit_path <> ".driver.ex",
          audit_path <> ".rows.json"
        ],
        do: assert({:error, :enoent} = File.lstat(path))

    assert is_nil(System.get_env("IPSE_RUNNER_PATH"))
    assert System.get_env("IPSE_HOME") == Path.join(File.cwd!(), "task-home")
    assert System.get_env("TMPDIR") == "/dev/shm"
    verify_inputs!()
    assert {:ok, _} = Application.ensure_all_started(:ipse)
    identity = candidate_identity!()

    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    File.mkdir!(evidence)
    File.chmod!(evidence, 0o700)
    :ok = Runner.protected_sync_directory(evidence)

    try do
      input_hashes = Map.new(@inputs, &{&1, JSON.sha256(File.read!(&1))})

      save!(Path.join(evidence, "seed-intent.json"), %{
        "version" => 1,
        "kind" => "fresh_synthetic_population_only",
        "root" => root,
        "fixture_port" => port,
        "source_commit" => "d739f4020b73a8784dc74079c7ed6eedf58ead2b",
        "candidate_identity" => identity,
        "input_manifests_sha256" => input_hashes,
        "records" => records,
        "qualification" => false,
        "scope" => "seed and audit only; no main-model workload turn, day or annual qualification"
      })

      started = System.monotonic_time(:microsecond)
      NativeNotesSeed.main(["--init", root, kind, "--fixture-port", Integer.to_string(port)])
      save!(Path.join(evidence, "clock-runtime-identity.json"), clock_identity!(root, identity))
      NativeNotesSeed.main(["--run", root, "all"])
      seeded = System.monotonic_time(:microsecond)
      NativeNotesSeed.main(["--audit", root, audit_path])
      audited = System.monotonic_time(:microsecond)
      audit = audit_path |> File.read!() |> Jason.decode!()

      assert audit["verified_records"] == records and audit["unchanged_root"] and
               audit["unchanged_control"] and is_integer(audit["unchanged_sources"]) and
               audit["unchanged_sources"] > 0

      assert not File.exists?(Path.join(root, "inflight.json"))
      assert not File.exists?(Path.join(root, "unexpected-model"))
      assert Map.new(@inputs, &{&1, JSON.sha256(File.read!(&1))}) == input_hashes
      verify_inputs!()

      save!(Path.join(evidence, "seed-result.json"), %{
        "version" => 1,
        "status" => "seed_audited",
        "root" => root,
        "fixture_port" => port,
        "intent_sha256" => JSON.sha256(File.read!(Path.join(evidence, "seed-intent.json"))),
        "seed_manifest_sha256" => JSON.sha256(File.read!(Path.join(root, "manifest.json"))),
        "seed_audit_sha256" => JSON.sha256(File.read!(audit_path)),
        "seed_elapsed_us" => seeded - started,
        "audit_elapsed_us" => audited - seeded,
        "verified_records" => records,
        "qualification" => false
      })

      IO.puts("FRESH_POPULATED_SEED_AUDITED=#{root}")
    after
      :gen_tcp.close(listener)

      verified =
        try do
          verify_inputs!()
          true
        rescue
          _ -> false
        catch
          _, _ -> false
        end

      save!(Path.join(evidence, "post-input-check.json"), %{
        "version" => 1,
        "manifests_and_membership_verified" => verified
      })

      assert verified, "source or build inventory changed; inspect without retry"
    end
  end

  defp candidate_identity! do
    app_dir = Path.expand(Application.app_dir(:ipse))
    assert app_dir == Path.join(File.cwd!(), "_build/test/lib/ipse")

    modules =
      Map.new(
        [Ipse.Runner, Ipse.Session.ManagedUse, Ipse.Extension.Collection.ObservedRead],
        fn module ->
          {:module, ^module} = Code.ensure_loaded(module)
          path = module |> :code.which() |> List.to_string() |> Path.expand()
          assert path == Path.join([app_dir, "ebin", Atom.to_string(module) <> ".beam"])
          {Atom.to_string(module), JSON.sha256(File.read!(path))}
        end
      )

    %{
      "app_dir" => app_dir,
      "module_sha256" => modules,
      "runner_source_sha256" => JSON.sha256(File.read!("lib/ipse/runner.ex")),
      "helper_sha256" => JSON.sha256(File.read!(Path.join(app_dir, "priv/ipse-runner"))),
      "knowledge_files" => tree_hashes!("priv/extension-bundles/knowledge")
    }
  end

  defp clock_identity!(root, identity) do
    recorded = root |> Path.join("clock-stdio-runtime.json") |> File.read!() |> Jason.decode!()
    clock_dir = Path.join(root, "stdio-runtime/ipse")
    source = Path.join(clock_dir, "lib/ipse/runner.ex")
    beam = Path.join(clock_dir, "ebin/Elixir.Ipse.Runner.beam")
    helper = Path.join(clock_dir, "priv/ipse-runner")
    assert recorded["production_source_sha256"] == identity["runner_source_sha256"]
    assert recorded["instrumented_source_sha256"] == JSON.sha256(File.read!(source))
    assert recorded["runner_beam_sha256"] == JSON.sha256(File.read!(beam))
    assert recorded["helper_sha256"] == JSON.sha256(File.read!(helper))
    assert recorded["helper_sha256"] == identity["helper_sha256"]

    for module <- ~w(Elixir.Ipse.Session.ManagedUse Elixir.Ipse.Extension.Collection.ObservedRead) do
      copied = Path.join([clock_dir, "ebin", module <> ".beam"])
      assert JSON.sha256(File.read!(copied)) == identity["module_sha256"][module]
    end

    assert tree_hashes!(Path.join(clock_dir, "priv/extension-bundles/knowledge")) ==
             identity["knowledge_files"]

    Map.put(
      recorded,
      "original_runner_beam_sha256",
      identity["module_sha256"]["Elixir.Ipse.Runner"]
    )
  end

  defp tree_hashes!(root) do
    Map.new(walk!(root, true), fn path ->
      {Path.relative_to(path, root), JSON.sha256(File.read!(path))}
    end)
  end

  defp save!(path, value) do
    {:ok, file} = :file.open(String.to_charlist(path), [:write, :binary, :exclusive])
    :ok = :file.write(file, Jason.encode!(value) <> "\n")
    File.chmod!(path, 0o600)
    :ok = :file.sync(file)
    :ok = :file.close(file)
    :ok = Runner.protected_sync_directory(Path.dirname(path))
  end

  defp verify_inputs! do
    entries = Map.new(@inputs, &{&1, verify_manifest!(&1)})
    assert entries["populated-build.sha256"] == MapSet.new(walk!("_build/test/lib", true))

    assert entries["populated-source.sha256"] ==
             MapSet.new(Enum.flat_map(~w(lib native extensions), &walk!(&1, false)))

    :ok
  end

  defp verify_manifest!(path) do
    paths =
      path
      |> File.stream!(:line, [])
      |> Enum.map(fn line ->
        [_, digest, relative] = Regex.run(~r/\A([0-9a-f]{64})  ([^\n]+)\n\z/, line)
        assert Path.type(relative) == :relative and not Enum.member?(Path.split(relative), "..")
        assert JSON.sha256(File.read!(relative)) == digest
        relative
      end)

    assert paths != [] and length(paths) == MapSet.size(MapSet.new(paths))
    MapSet.new(paths)
  end

  defp walk!(path, follow?) do
    info = if follow?, do: File.stat!(path), else: File.lstat!(path)

    case info.type do
      :regular -> [path]
      :directory -> path |> File.ls!() |> Enum.flat_map(&walk!(Path.join(path, &1), follow?))
      :symlink when not follow? -> []
      _ -> raise "unsupported frozen inventory entry"
    end
  end
end

Ipse.Development.PopulatedSeedOnce.main(System.argv())
