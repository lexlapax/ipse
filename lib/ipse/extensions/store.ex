defmodule Ipse.Extensions.Store do
  @moduledoc "Private content-addressed local imports, independent of trust and activation."
  alias Ipse.Extensions.Manifest
  import Bitwise, only: [band: 2]
  @invalid {:error, :invalid_extension_artifact}

  @doc "Snapshot only declared files. No builds, code loading, network or activation."
  def import(source, root) when is_binary(source) and is_binary(root) do
    with {:ok, bytes} <- read_regular(source, "extension.json", 16_384),
         {:ok, manifest} <- Manifest.decode(bytes),
         {:ok, files} <- snapshot(source, manifest),
         :ok <- private_directory(root) do
      digest = Manifest.sha256(bytes)

      lock_path = Path.join(root, ".import-#{digest}.lock")

      with :ok <- lock_path_valid(lock_path),
           {:ok, lock} <- Ipse.Runner.lock(lock_path) do
        try do
          publish(root, digest, bytes, files, manifest)
        after
          Ipse.Runner.unlock(lock)
        end
      end
    else
      _ -> @invalid
    end
  rescue
    _ -> @invalid
  end

  def import(_, _), do: @invalid

  @doc "Reverify pinned content on lookup. A digest is provenance, never permission."
  def lookup(root, digest) when is_binary(root) and is_binary(digest) do
    with true <- Regex.match?(~r/\A[0-9a-f]{64}\z/, digest),
         :ok <- check_private_directory(root),
         path = Path.join(root, digest),
         :ok <- check_private_directory(path),
         {:ok, bytes} <- read_regular(path, "extension.json", 16_384),
         true <- Manifest.sha256(bytes) == digest,
         {:ok, manifest} <- Manifest.decode(bytes),
         {:ok, _files} <- snapshot(path, manifest),
         {:ok, inventory, _remaining} <- inventory(path, "", 1024),
         true <-
           Enum.sort(inventory) ==
             Enum.sort(["extension.json" | Enum.map(manifest["files"], & &1["path"])]) do
      {:ok, %{digest: digest, manifest: manifest, path: path}}
    else
      _ -> @invalid
    end
  rescue
    _ -> @invalid
  end

  def lookup(_, _), do: @invalid

  defp lock_path_valid(path) do
    case File.lstat(path) do
      {:error, :enoent} -> :ok
      {:ok, %{type: :regular, mode: mode}} when band(mode, 0o077) == 0 -> :ok
      _ -> @invalid
    end
  end

  defp publish(root, digest, bytes, files, manifest) do
    final = Path.join(root, digest)

    case File.lstat(final) do
      {:ok, _} ->
        lookup(root, digest)

      {:error, :enoent} ->
        stage =
          Path.join(
            root,
            ".staging-" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
          )

        with :ok <- File.mkdir(stage) do
          try do
            with :ok <- File.chmod(stage, 0o700),
                 :ok <- write_file(stage, "extension.json", bytes),
                 :ok <- write_files(stage, files),
                 :ok <- File.rename(stage, final) do
              {:ok, %{digest: digest, manifest: manifest, path: final}}
            else
              _ -> @invalid
            end
          after
            File.rm_rf(stage)
          end
        end

      _ ->
        @invalid
    end
  end

  defp snapshot(root, manifest) do
    Enum.reduce_while(manifest["files"], {:ok, []}, fn file, {:ok, acc} ->
      with {:ok, bytes} <- read_regular(root, file["path"], file["bytes"]),
           true <- byte_size(bytes) == file["bytes"],
           true <- Manifest.sha256(bytes) == file["sha256"] do
        {:cont, {:ok, [{file["path"], bytes} | acc]}}
      else
        _ -> {:halt, @invalid}
      end
    end)
  end

  defp read_regular(root, relative, limit) do
    with {:ok, %{type: :directory}} <- File.lstat(root),
         :ok <- regular_components(root, Path.split(relative)),
         {:ok, %{type: :regular, size: size}} <- File.lstat(Path.join(root, relative)),
         true <- size <= limit,
         {:ok, result} <-
           File.open(Path.join(root, relative), [:read, :binary], &IO.binread(&1, limit + 1)),
         bytes = if(result == :eof, do: "", else: result),
         true <- is_binary(bytes) and byte_size(bytes) <= limit do
      {:ok, bytes}
    else
      _ -> @invalid
    end
  end

  defp regular_components(root, [file]) do
    case File.lstat(Path.join(root, file)) do
      {:ok, %{type: :regular}} -> :ok
      _ -> @invalid
    end
  end

  defp regular_components(root, [dir | rest]) do
    path = Path.join(root, dir)

    case File.lstat(path) do
      {:ok, %{type: :directory}} -> regular_components(path, rest)
      _ -> @invalid
    end
  end

  defp private_directory(path) do
    with :ok <- File.mkdir_p(path),
         {:ok, %{type: :directory}} <- File.lstat(path),
         :ok <- File.chmod(path, 0o700),
         :ok <- check_private_directory(path) do
      :ok
    else
      _ -> @invalid
    end
  end

  defp check_private_directory(path) do
    case File.lstat(path) do
      {:ok, %{type: :directory, mode: mode}} when band(mode, 0o077) == 0 -> :ok
      _ -> @invalid
    end
  end

  defp write_files(stage, files) do
    Enum.reduce_while(files, :ok, fn {path, bytes}, :ok ->
      case write_file(stage, path, bytes) do
        :ok -> {:cont, :ok}
        _ -> {:halt, @invalid}
      end
    end)
  end

  defp write_file(stage, relative, bytes) do
    path = Path.join(stage, relative)

    with :ok <- make_parents(stage, Path.split(relative) |> Enum.drop(-1)),
         :ok <- File.write(path, bytes, [:binary, :exclusive, :sync]),
         :ok <- File.chmod(path, 0o600) do
      :ok
    end
  end

  defp make_parents(_root, []), do: :ok

  defp make_parents(root, [dir | rest]) do
    path = Path.join(root, dir)
    with :ok <- File.mkdir_p(path), :ok <- File.chmod(path, 0o700), do: make_parents(path, rest)
  end

  defp inventory(_root, _relative, remaining) when remaining <= 0, do: @invalid

  defp inventory(root, relative, remaining) do
    with {:ok, entries} <- File.ls(Path.join(root, relative)),
         true <- length(entries) < remaining do
      Enum.reduce_while(entries, {:ok, [], remaining - length(entries)}, fn entry,
                                                                            {:ok, acc, left} ->
        path = if relative == "", do: entry, else: relative <> "/" <> entry

        case File.lstat(Path.join(root, path)) do
          {:ok, %{type: :regular}} ->
            {:cont, {:ok, [path | acc], left}}

          {:ok, %{type: :directory}} ->
            case inventory(root, path, left) do
              {:ok, children, remaining} -> {:cont, {:ok, children ++ acc, remaining}}
              _ -> {:halt, @invalid}
            end

          _ ->
            {:halt, @invalid}
        end
      end)
      |> case do
        {:ok, files, left} -> {:ok, files, left}
        _ -> @invalid
      end
    else
      _ -> @invalid
    end
  end
end
