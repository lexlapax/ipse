defmodule IpseKnowledgeExample.EvaluationFreeze do
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
  """
  alias Ipse.Extensions.{Manifest, Store}

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
          case Store.import(path, store) do
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
        "plan_sha256" => Manifest.sha256(plan_bytes),
        "artifacts" => copied
      }

      bytes = JSON.encode!(manifest) <> "\n"
      require!(byte_size(bytes) <= 1_048_576, :manifest_limit)
      path = Path.join(output, "manifest.json")
      write_private(path, bytes)
      digest = Manifest.sha256(bytes)
      write_private(Path.join(output, "manifest.sha256"), digest <> "\n")
      %{"path" => path, "sha256" => digest, "source_commit" => source["commit"]}
    end)
  end

  def verify(path, expected_sha256) do
    protect(fn ->
      require!(hash?(expected_sha256), :invalid_manifest_hash)
      bytes = read_bounded!(path, 1_048_576)
      require!(Manifest.sha256(bytes) == expected_sha256, :manifest_changed)
      {:ok, manifest} = Manifest.decode_json(bytes, 1_048_576)

      require!(
        exact?(manifest, ~w(version created_at source runtime plan_sha256 artifacts)) and
          manifest["version"] === 1,
        :invalid_manifest
      )

      source = manifest["source"]
      require!(source_snapshot(source["root"]) == source, :source_changed)
      require!(runtime_snapshot() == manifest["runtime"], :runtime_changed)
      root = Path.dirname(Path.expand(path))
      plan_bytes = read_bounded!(Path.join(root, "plan.json"), 1_048_576)
      require!(Manifest.sha256(plan_bytes) == manifest["plan_sha256"], :plan_changed)
      plan = decode_plan!(plan_bytes)
      store = Path.join(root, "artifacts")

      paths =
        Map.new(manifest["artifacts"], fn {name, digest} ->
          require!(name?(name) and hash?(digest), :invalid_artifacts)

          case Store.lookup(store, digest) do
            {:ok, artifact} -> {name, artifact.path}
            _ -> fail!(:artifact_changed)
          end
        end)

      %{"manifest" => manifest, "plan" => plan, "artifact_paths" => paths}
    end)
  end

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
    case Manifest.decode_json(bytes, 1_048_576) do
      {:ok, %{"version" => 1} = plan} -> plan
      _ -> fail!(:invalid_plan)
    end
  end

  defp git!(root, arguments) do
    case System.cmd("git", ["-C", root | arguments], stderr_to_stdout: true) do
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
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp require!(true, _), do: :ok
  defp require!(_, code), do: fail!(code)
  defp fail!(code), do: throw({:evaluation_freeze, code})
end
