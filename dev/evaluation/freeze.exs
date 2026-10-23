Code.require_file("model_service.exs", __DIR__)
Code.require_file("contract.exs", __DIR__)

defmodule Ipse.Development.Evaluation.Freeze do
  @moduledoc """
  Seal the identities needed by a knowledge evaluation before opening its inputs.

  The caller supplies a public plan and reviewed independent artifact paths.
  create/4 requires a clean repository, copies artifacts through the inert host
  store and records all tracked source files, code-path BEAM files and Ipse native
  helpers. No dataset, provider, worker or model is opened. A failed creation leaves
  its partial directory for inspection and never replaces an earlier run.

  verify/2 requires the separately retained manifest digest. It rechecks source,
  runtime, plan and copied artifact bytes. This is identity verification; the
  orchestrator still owns plan validation, egress decisions, budgets and execution.

  declare/3 removes local bindings from a public plan and records portable source
  and artifact content identities. resolve_plan/2 supplies local bindings without
  IO; create_v2/4 seals a fresh execution identity, runtime and canonical report
  and attempt-registry paths. Its semantic launch recipe authorizes no execution
  and establishes no attempt claim. Version 1 seals keep their original contract.
  """
  alias Ipse.Extension.Artifact
  alias Ipse.Development.Evaluation.Contract

  @max_measured_lifetime_ms 15 * 86_400_000

  @completion_policy %{
    "completion_policy" => "bounded_natural_drain_v1",
    "population_drain_limit_ms" => 2000
  }
  @policy Map.merge(@completion_policy, %{
            "metric" => "linux_memcg_charged_peak_bytes_v1",
            "device" => "cpu_only",
            "cache" => "fresh_private_inodes_per_cell",
            "expected_projects" => 2,
            "backend" => "linux_cgroup_v2_v2"
          })

  @doc "Fixed native population completion policy bound into each new experiment."
  def completion_policy, do: @completion_policy

  @doc "Declare portable source, artifact and experiment identities without opening evaluation inputs."
  def declare(repository, plan_bytes, artifacts, resolution \\ nil) do
    protect(fn ->
      {:ok, _} = Application.ensure_all_started(:ipse)
      plan = decode_execution_plan!(plan_bytes)

      {device, context_tokens} =
        case resolution do
          nil ->
            {"cpu_only", nil}

          selection ->
            validate_resolution!(selection)
            require!(selection["model_service"]["models"] == plan["models"], :model_selection)

            {:ok, device} =
              Ipse.Development.Evaluation.ModelService.device_policy(selection["model_service"])

            {device, selection["model_service"]["context_tokens"]}
        end

      require!(!Contract.long_answers?(plan) or context_tokens != nil, :context_selection)
      require_context!(plan, context_tokens)

      validate_artifact_paths!(artifacts)

      require!(
        Enum.sort(Map.keys(plan["artifacts"])) == Enum.sort(Map.keys(artifacts)),
        :artifact_aliases
      )

      source = source_snapshot(canonical!(repository))
      temporary = Path.join(System.tmp_dir!(), "ipse-declaration-" <> nonce())
      File.mkdir!(temporary)
      File.chmod!(temporary, 0o700)

      digests =
        try do
          import_artifacts!(artifacts, Path.join(temporary, "artifacts"))
        after
          File.rm_rf!(temporary)
        end

      require!(source_snapshot(source["root"]) == source, :source_changed)

      policy = Map.put(@policy, "device", device)

      policy =
        if context_tokens, do: Map.put(policy, "context_tokens", context_tokens), else: policy

      experiment = %{
        "version" => if(context_tokens, do: 3, else: 2),
        "kind" => "knowledge_experiment",
        "source" => Map.delete(source, "root"),
        "plan" => portable_plan!(plan),
        "artifacts" => digests,
        "policy" => policy
      }

      bytes = JSON.encode!(experiment) <> "\n"
      _ = decode_experiment!(bytes)

      %{
        "bytes" => bytes,
        "sha256" => Ipse.JSON.sha256(bytes),
        "source_commit" => source["commit"]
      }
    end)
  end

  @doc "Resolve the portable plan from closed local values, without filesystem or service IO."
  def resolve_plan(experiment_bytes, resolution) do
    protect(fn -> resolved_plan!(decode_experiment!(experiment_bytes), resolution) end)
  end

  @doc "Inspect the current ERTS launch identity for explicitly selected evaluation fixtures."
  def runtime_launch do
    protect(fn -> measured_runtime_snapshot()["launch"] end)
  end

  @doc "Seal one fresh local resolution of a portable declaration; this does not authorize execution."
  def create_v2(repository, experiment_bytes, resolution, output) do
    protect(fn ->
      {:ok, _} = Application.ensure_all_started(:ipse)
      experiment = decode_experiment!(experiment_bytes)
      validate_resolution!(resolution)
      require_service_policy!(experiment, resolution)
      repository = canonical!(repository)
      output = canonical!(output)
      resolution = normalize_resolution!(resolution)
      plan = resolved_plan!(experiment, resolution)
      source = source_snapshot(repository)
      require!(Map.delete(source, "root") == experiment["source"], :source_changed)
      require!(!overlap?(output, resolution["reports"]), :reports_overlap)
      require!(!within?(repository, resolution["reports"]), :reports_overlap)
      require!(match?({:error, :enoent}, File.lstat(resolution["reports"])), :reports_exists)
      require!(match?({:error, :enoent}, File.lstat(output)), :output_exists)
      File.mkdir!(output)
      File.chmod!(output, 0o700)
      registry = Path.join(output, "attempts")
      File.mkdir!(registry)
      File.chmod!(registry, 0o700)
      registry_identity = directory_identity!(registry)
      write_private(Path.join(output, "experiment.json"), experiment_bytes)
      plan_bytes = JSON.encode!(plan) <> "\n"
      write_private(Path.join(output, "plan.json"), plan_bytes)
      copied = import_artifacts!(resolution["artifacts"], Path.join(output, "artifacts"))
      require!(copied == experiment["artifacts"], :artifact_changed)
      runtime = measured_runtime_snapshot()
      require!(source_snapshot(repository) == source, :source_changed)
      id = nonce()
      experiment_digest = Ipse.JSON.sha256(experiment_bytes)
      plan_digest = Ipse.JSON.sha256(plan_bytes)

      recipe =
        launch_recipe(id, experiment_digest, plan_digest, registry, registry_identity, resolution)

      manifest = %{
        "version" => 2,
        "created_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "execution_id" => id,
        "source" => source,
        "runtime" => runtime,
        "experiment_sha256" => experiment_digest,
        "plan_sha256" => plan_digest,
        "artifacts" => copied,
        "resolution" => resolution,
        "attempt_registry" => registry,
        "attempt_registry_identity" => registry_identity,
        "launch_recipe" => recipe,
        "recipe_sha256" => Ipse.JSON.sha256(JSON.encode!(recipe)),
        "provenance" => %{
          "os" => :os.type() |> Tuple.to_list() |> Enum.map(&Atom.to_string/1),
          "architecture" => to_string(:erlang.system_info(:system_architecture)),
          "elixir" => System.version(),
          "otp" => System.otp_release()
        }
      }

      bytes = JSON.encode!(manifest) <> "\n"
      require!(byte_size(bytes) <= 1_048_576, :manifest_limit)
      path = Path.join(output, "manifest.json")
      write_private(path, bytes)
      digest = Ipse.JSON.sha256(bytes)
      write_private(Path.join(output, "manifest.sha256"), digest <> "\n")

      %{
        "path" => path,
        "sha256" => digest,
        "source_commit" => source["commit"],
        "execution_id" => id,
        "attempt_registry" => registry,
        "reports" => resolution["reports"]
      }
    end)
  end

  def create(repository, plan_bytes, artifacts, output) do
    protect(fn ->
      {:ok, _} = Application.ensure_all_started(:ipse)
      _plan = decode_plan!(plan_bytes)
      repository = Path.expand(repository)
      output = Path.expand(output)
      require!(is_map(artifacts) and map_size(artifacts) in 1..16, :invalid_artifacts)

      require!(
        Enum.all?(artifacts, fn {name, path} -> name?(name) and is_binary(path) end),
        :invalid_artifacts
      )

      source = source_snapshot(repository)
      require!(match?({:error, :enoent}, File.lstat(output)), :output_exists)
      File.mkdir!(output)
      File.chmod!(output, 0o700)
      write_private(Path.join(output, "plan.json"), plan_bytes)
      store = Path.join(output, "artifacts")

      copied =
        Map.new(artifacts, fn {name, path} ->
          case Artifact.import(path, store) do
            {:ok, installed} -> {name, installed.digest}
            _ -> fail!(:artifact_import)
          end
        end)

      runtime = runtime_snapshot()
      require!(source_snapshot(repository) == source, :source_changed)

      manifest = %{
        "version" => 1,
        "created_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "source" => source,
        "runtime" => runtime,
        "plan_sha256" => Ipse.JSON.sha256(plan_bytes),
        "artifacts" => copied
      }

      bytes = JSON.encode!(manifest) <> "\n"
      require!(byte_size(bytes) <= 1_048_576, :manifest_limit)
      path = Path.join(output, "manifest.json")
      write_private(path, bytes)
      digest = Ipse.JSON.sha256(bytes)
      write_private(Path.join(output, "manifest.sha256"), digest <> "\n")
      %{"path" => path, "sha256" => digest, "source_commit" => source["commit"]}
    end)
  end

  def verify(path, expected_sha256) do
    protect(fn ->
      require!(Ipse.JSON.sha256?(expected_sha256), :invalid_manifest_hash)
      bytes = read_bounded!(path, 1_048_576)
      require!(Ipse.JSON.sha256(bytes) == expected_sha256, :manifest_changed)
      {:ok, manifest} = Ipse.JSON.decode_bounded(bytes, 1_048_576)
      require!(is_map(manifest), :invalid_manifest)
      root = Path.dirname(Path.expand(path))

      case manifest["version"] do
        1 -> verify_v1!(root, manifest)
        2 -> verify_v2!(root, manifest)
        _ -> fail!(:invalid_manifest)
      end
    end)
  end

  defp verify_v1!(root, manifest) do
    require!(
      exact?(manifest, ~w(version created_at source runtime plan_sha256 artifacts)) and
        manifest["version"] === 1,
      :invalid_manifest
    )

    source = manifest["source"]
    require!(source_snapshot(source["root"]) == source, :source_changed)
    require!(runtime_snapshot() == manifest["runtime"], :runtime_changed)
    plan_bytes = read_bounded!(Path.join(root, "plan.json"), 1_048_576)
    require!(Ipse.JSON.sha256(plan_bytes) == manifest["plan_sha256"], :plan_changed)
    plan = decode_plan!(plan_bytes)
    store = Path.join(root, "artifacts")

    paths =
      Map.new(manifest["artifacts"], fn {name, digest} ->
        require!(name?(name) and Ipse.JSON.sha256?(digest), :invalid_artifacts)

        case Artifact.lookup(store, digest) do
          {:ok, artifact} -> {name, artifact.path}
          _ -> fail!(:artifact_changed)
        end
      end)

    %{"manifest" => manifest, "plan" => plan, "artifact_paths" => paths}
  end

  defp verify_v2!(root, manifest) do
    require!(
      exact?(
        manifest,
        ~w(version created_at execution_id source runtime experiment_sha256 plan_sha256 artifacts resolution attempt_registry attempt_registry_identity launch_recipe recipe_sha256 provenance)
      ),
      :invalid_manifest
    )

    require!(
      is_binary(manifest["execution_id"]) and
        Regex.match?(~r/\A[0-9a-f]{32}\z/, manifest["execution_id"]),
      :invalid_manifest
    )

    require!(canonical!(root) == root, :freeze_path_changed)
    registry = Path.join(root, "attempts")

    require!(
      manifest["attempt_registry"] == registry and canonical!(registry) == registry,
      :registry_changed
    )

    %{type: :directory, mode: mode} = File.lstat!(registry)
    require!(Bitwise.band(mode, 0o777) == 0o700, :registry_changed)

    require!(
      directory_identity!(registry) == manifest["attempt_registry_identity"],
      :registry_changed
    )

    experiment_bytes = read_bounded!(Path.join(root, "experiment.json"), 1_048_576)

    require!(
      Ipse.JSON.sha256(experiment_bytes) == manifest["experiment_sha256"],
      :experiment_changed
    )

    experiment = decode_experiment!(experiment_bytes)
    source = manifest["source"]

    require!(
      source_snapshot(source["root"]) == source and
        Map.delete(source, "root") == experiment["source"],
      :source_changed
    )

    require!(measured_runtime_snapshot() == manifest["runtime"], :runtime_changed)
    resolution = manifest["resolution"]
    plan = resolved_plan!(experiment, resolution)
    require!(canonical!(resolution["reports"]) == resolution["reports"], :reports_changed)

    require!(
      !overlap?(root, resolution["reports"]) and !within?(source["root"], resolution["reports"]),
      :reports_overlap
    )

    plan_bytes = read_bounded!(Path.join(root, "plan.json"), 1_048_576)
    require!(Ipse.JSON.sha256(plan_bytes) == manifest["plan_sha256"], :plan_changed)
    require!(decode_execution_plan!(plan_bytes) == plan, :plan_changed)
    require!(manifest["artifacts"] == experiment["artifacts"], :artifact_changed)

    paths =
      Map.new(manifest["artifacts"], fn {name, digest} ->
        case Artifact.lookup(Path.join(root, "artifacts"), digest) do
          {:ok, artifact} -> {name, artifact.path}
          _ -> fail!(:artifact_changed)
        end
      end)

    recipe =
      launch_recipe(
        manifest["execution_id"],
        manifest["experiment_sha256"],
        manifest["plan_sha256"],
        registry,
        manifest["attempt_registry_identity"],
        resolution
      )

    require!(
      manifest["launch_recipe"] == recipe and
        manifest["recipe_sha256"] == Ipse.JSON.sha256(JSON.encode!(recipe)),
      :recipe_changed
    )

    %{
      "manifest" => manifest,
      "plan" => plan,
      "artifact_paths" => paths,
      "experiment" => experiment,
      "resolution" => resolution
    }
  end

  defp decode_execution_plan!(bytes) do
    {:ok, plan} = Ipse.JSON.decode_bounded(bytes, 1_048_576)
    require!(Contract.validate_shape(plan, :execution) == :ok, :invalid_plan)

    plan
  end

  defp portable_plan!(plan) do
    plan
    |> Map.drop(~w(artifacts search_port model_origin))
    |> Map.put("version", if(plan["version"] == 3, do: 3, else: 2))
    |> Map.update!("profiles", &without_origins!/1)
    |> Map.update!("embedding_profiles", &without_origins!/1)
  end

  defp without_origins!(profiles) do
    Map.new(profiles, fn {id, profile} ->
      require!(name?(id) and is_map(profile), :invalid_plan)
      {id, Map.delete(profile, "base_url")}
    end)
  end

  defp decode_experiment!(bytes) do
    {:ok, experiment} = Ipse.JSON.decode_bounded(bytes, 1_048_576)

    require!(
      exact?(experiment, ~w(version kind source plan artifacts policy)) and
        experiment["version"] in [2, 3] and experiment["kind"] == "knowledge_experiment",
      :invalid_experiment
    )

    policy = experiment["policy"]
    context_tokens = if is_map(policy), do: policy["context_tokens"]

    legacy_policy =
      if experiment["version"] == 3 and is_map(policy),
        do: Map.delete(policy, "context_tokens"),
        else: policy

    require!(
      legacy_policy in [@policy, Map.put(@policy, "device", "nvidia_visible_mixed_v1")],
      :invalid_experiment
    )

    if experiment["version"] == 3 do
      require!(is_integer(context_tokens) and context_tokens in 1..1_048_576, :invalid_experiment)
    end

    source = experiment["source"]

    require!(
      exact?(source, ~w(commit tree files)) and is_list(source["files"]) and
        length(source["files"]) in 1..4096,
      :invalid_experiment
    )

    require!(
      Enum.all?(
        [source["commit"], source["tree"]],
        &(is_binary(&1) and Regex.match?(~r/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/, &1))
      ),
      :invalid_experiment
    )

    require!(
      Enum.all?(source["files"], fn file ->
        exact?(file, ~w(path bytes sha256)) and source_relative?(file["path"]) and
          is_integer(file["bytes"]) and file["bytes"] in 0..67_108_864 and
          Ipse.JSON.sha256?(file["sha256"])
      end),
      :invalid_experiment
    )

    require!(
      length(Enum.uniq_by(source["files"], & &1["path"])) == length(source["files"]),
      :invalid_experiment
    )

    artifacts = experiment["artifacts"]

    require!(
      is_map(artifacts) and map_size(artifacts) in 1..16 and
        Enum.all?(artifacts, fn {id, digest} -> name?(id) and Ipse.JSON.sha256?(digest) end),
      :invalid_experiment
    )

    plan = experiment["plan"]

    require!(Contract.validate_shape(plan, :portable) == :ok, :invalid_experiment)
    require_context!(plan, context_tokens)

    experiment
  end

  defp resolved_plan!(experiment, resolution) do
    validate_resolution!(resolution)
    require_service_policy!(experiment, resolution)

    require!(
      resolution["model_service"]["models"] == experiment["plan"]["models"],
      :model_selection
    )

    actual_aliases = Enum.sort(Map.keys(resolution["artifacts"]))
    declared_aliases = Enum.sort(Map.keys(experiment["artifacts"]))
    require!(actual_aliases == declared_aliases, :artifact_aliases)

    experiment["plan"]
    |> Map.put("artifacts", resolution["artifacts"])
    |> Map.put("search_port", resolution["search_port"])
    |> Map.put("model_origin", resolution["model_origin"])
    |> Map.update!("profiles", &with_origin(&1, resolution["model_origin"]))
    |> Map.update!("embedding_profiles", &with_origin(&1, resolution["model_origin"]))
  end

  defp require_service_policy!(experiment, resolution) do
    {:ok, device} =
      Ipse.Development.Evaluation.ModelService.device_policy(resolution["model_service"])

    require!(device == experiment["policy"]["device"], :device_selection)

    require!(
      resolution["model_service"]["context_tokens"] == experiment["policy"]["context_tokens"],
      :context_selection
    )
  end

  defp require_context!(_plan, nil), do: :ok

  defp require_context!(plan, context_tokens) do
    require!(
      Enum.all?(Map.values(plan["profiles"]), fn profile ->
        is_integer(profile["max_output_tokens"]) and context_tokens > profile["max_output_tokens"]
      end),
      :context_selection
    )
  end

  defp with_origin(profiles, origin),
    do: Map.new(profiles, fn {id, profile} -> {id, Map.put(profile, "base_url", origin)} end)

  defp validate_resolution!(resolution) do
    require!(
      exact?(
        resolution,
        ~w(artifacts model_origin search_port reports data_manifest model_service)
      ),
      :invalid_resolution
    )

    validate_artifact_paths!(resolution["artifacts"])

    require!(
      Enum.all?(Map.values(resolution["artifacts"]), &absolute?/1) and
        absolute?(resolution["reports"]) and absolute?(resolution["data_manifest"]),
      :invalid_resolution
    )

    origin = resolution["model_origin"]
    require!(is_binary(origin) and byte_size(origin) <= 128, :model_origin)
    uri = URI.parse(origin)

    require!(
      is_integer(uri.port) and uri.port in 1..65_535 and uri.port != 11_434 and
        origin == "http://127.0.0.1:#{uri.port}",
      :model_origin
    )

    require!(
      is_integer(resolution["search_port"]) and resolution["search_port"] in 1..65_535 and
        resolution["search_port"] != uri.port,
      :search_port
    )

    require!(
      Ipse.Development.Evaluation.ModelService.validate(resolution["model_service"]) == :ok,
      :model_service
    )

    require!(resolution["model_service"]["origin"] == origin, :model_origin)
    _ = measured_timeouts!(resolution)
  end

  defp normalize_resolution!(resolution) do
    artifacts =
      Map.new(resolution["artifacts"], fn {id, path} ->
        path = canonical!(path)
        require!(File.dir?(path), :invalid_artifacts)
        {id, path}
      end)

    %{
      resolution
      | "artifacts" => artifacts,
        "reports" => canonical!(resolution["reports"]),
        "data_manifest" => canonical!(resolution["data_manifest"])
    }
  end

  defp validate_artifact_paths!(artifacts) do
    require!(
      is_map(artifacts) and map_size(artifacts) in 1..16 and
        Enum.all?(artifacts, fn {name, path} -> name?(name) and is_binary(path) end),
      :invalid_artifacts
    )
  end

  defp import_artifacts!(artifacts, store) do
    Map.new(artifacts, fn {name, path} ->
      case Artifact.import(path, store) do
        {:ok, installed} -> {name, installed.digest}
        _ -> fail!(:artifact_import)
      end
    end)
  end

  defp launch_recipe(id, experiment, plan, registry, identity, resolution),
    do: %{
      "version" => 1,
      "kind" => "knowledge_measured_v1",
      "execution_id" => id,
      "experiment_sha256" => experiment,
      "plan_sha256" => plan,
      "attempt_registry" => registry,
      "attempt_registry_identity" => identity,
      "reports" => resolution["reports"],
      "data_manifest" => resolution["data_manifest"],
      "timeouts" => measured_timeouts!(resolution)
    }

  defp measured_timeouts!(resolution) do
    cell = resolution["model_service"]["limits"]["lifetime_ms"] + 30_000
    root = 14 * cell + 360_000 + 16 * 8_000 + 10_000
    require!(root <= @max_measured_lifetime_ms, :execution_limits)
    %{"root_ms" => root, "prepare_ms" => 180_000, "cell_ms" => cell, "finalize_ms" => 180_000}
  end

  defp directory_identity!(path) do
    %{type: :directory, major_device: device, inode: inode} = File.lstat!(path)
    %{"device" => device, "inode" => inode}
  end

  defp nonce, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

  defp canonical!(path) do
    require!(
      is_binary(path) and String.valid?(path) and byte_size(path) in 1..4096 and
        !String.contains?(path, <<0>>),
      :invalid_path
    )

    {:ok, canonical} = Ipse.Workspace.canonical_path(path)
    canonical
  end

  defp absolute?(path),
    do:
      is_binary(path) and String.valid?(path) and byte_size(path) in 1..4096 and
        !String.contains?(path, <<0>>) and Path.type(path) == :absolute and
        Path.expand(path) == path

  defp source_relative?(path),
    do:
      is_binary(path) and String.valid?(path) and byte_size(path) in 1..4096 and
        !String.contains?(path, <<0>>) and Path.type(path) == :relative and
        Enum.all?(String.split(path, "/"), &(&1 not in ["", ".", ".."]))

  defp within?(path, root),
    do: path == root or String.starts_with?(path, String.trim_trailing(root, "/") <> "/")

  defp overlap?(left, right), do: within?(left, right) or within?(right, left)

  defp source_snapshot(root) do
    require!(
      git!(root, ["status", "--porcelain=v1", "--untracked-files=all"]) == "",
      :dirty_source
    )

    commit = git!(root, ["rev-parse", "HEAD"]) |> String.trim()
    tree = git!(root, ["rev-parse", "HEAD^{tree}"]) |> String.trim()
    paths = git!(root, ["ls-files", "-z", "--cached"]) |> String.split(<<0>>, trim: true)
    require!(paths != [] and length(paths) <= 4096, :source_file_limit)

    files =
      paths
      |> Enum.sort()
      |> Enum.map(fn relative ->
        path = Path.join(root, relative)
        Map.put(file_identity(path), "path", relative)
      end)

    %{"root" => root, "commit" => commit, "tree" => tree, "files" => files}
  end

  defp runtime_snapshot do
    beams =
      Enum.flat_map(:code.get_path(), fn directory ->
        Path.wildcard(Path.join(to_string(directory), "*.beam"))
      end)

    native =
      Application.app_dir(:ipse, "priv/ipse-*")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)

    paths = (beams ++ native) |> Enum.map(&Path.expand/1) |> Enum.uniq() |> Enum.sort()
    require!(paths != [] and length(paths) <= 4096, :runtime_file_limit)

    %{
      "elixir" => System.version(),
      "otp" => System.otp_release(),
      "erts" => to_string(:erlang.system_info(:version)),
      "platform" => to_string(:erlang.system_info(:system_architecture)),
      "files" => Enum.map(paths, &file_identity/1)
    }
  end

  defp measured_runtime_snapshot do
    root = to_string(:code.root_dir()) |> Path.expand()

    binary_directory =
      Path.join([root, "erts-" <> to_string(:erlang.system_info(:version)), "bin"])

    executable = Path.join(binary_directory, "erl")

    release_boot =
      case :init.get_argument(:boot) do
        {:ok, [[path]]} ->
          path = to_string(path)

          if Path.type(path) == :absolute and
               String.starts_with?(Path.expand(path), Path.join(root, "releases") <> "/"),
             do: Path.join(Path.dirname(path), "start_clean")

        _ ->
          nil
      end

    boot =
      Enum.find(
        [release_boot, Path.join(root, "bin/no_dot_erlang")],
        &(is_binary(&1) and File.regular?(&1 <> ".boot"))
      ) || fail!(:runtime_launcher)

    require!(File.regular?(executable), :runtime_launcher)

    paths =
      :code.get_path()
      |> Enum.map(&(to_string(&1) |> Path.expand()))

    files =
      [boot <> ".boot" | Path.wildcard(Path.join(binary_directory, "*"))]
      |> Enum.filter(&match?({:ok, %{type: :regular}}, File.lstat(&1)))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(&file_identity/1)

    Map.put(runtime_snapshot(), "launch", %{
      "executable" => executable,
      "boot" => boot,
      "root" => root,
      "code_paths" => paths,
      "files" => files
    })
  end

  defp file_identity(path) do
    %{type: :regular, size: size} = File.lstat!(path)
    require!(size <= 67_108_864, :file_size_limit)

    digest =
      path
      |> File.stream!(1_048_576, [])
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)

    %{"path" => path, "bytes" => size, "sha256" => digest}
  end

  defp read_bounded!(path, limit) do
    %{type: :regular, size: size} = File.lstat!(path)
    require!(size <= limit, :file_size_limit)
    {:ok, bytes} = File.open(path, [:read, :binary], &IO.binread(&1, limit + 1))
    require!(is_binary(bytes) and byte_size(bytes) <= limit, :file_size_limit)
    bytes
  end

  defp write_private(path, bytes) do
    File.write!(path, bytes, [:exclusive, :sync])
    File.chmod!(path, 0o600)
  end

  defp decode_plan!(bytes) do
    case Ipse.JSON.decode_bounded(bytes, 1_048_576) do
      {:ok, %{"version" => 1} = plan} -> plan
      _ -> fail!(:invalid_plan)
    end
  end

  defp git!(root, arguments) do
    case System.cmd("git", ["--no-optional-locks", "-C", root | arguments],
           stderr_to_stdout: true
         ) do
      {output, 0} -> output
      _ -> fail!(:source_git)
    end
  end

  defp protect(fun) do
    {:ok, fun.()}
  rescue
    _ -> {:error, :freeze_io_or_shape}
  catch
    {:evaluation_freeze, code} -> {:error, code}
  end

  defp exact?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp name?(value), do: is_binary(value) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, value)
  defp require!(true, _), do: :ok
  defp require!(_, code), do: fail!(code)
  defp fail!(code), do: throw({:evaluation_freeze, code})
end
