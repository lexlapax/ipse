defmodule Ipse.Extension.Artifact do
  @moduledoc "Version-one inert worker artifact descriptors. Validation never loads code."
  alias Ipse.JSON, as: Schema

  @limit 16_384
  @keys ~w(format id version sdk protocol backend entrypoint files options_schema capabilities runtime license_file)
  @text %{"type" => "string", "minLength" => 1, "maxLength" => 256}
  @schema %{
    "type" => "object",
    "required" => @keys,
    "additionalProperties" => false,
    "properties" => %{
      "format" => %{"type" => "integer", "enum" => [1]},
      "id" => @text,
      "version" => @text,
      "sdk" => %{"type" => "integer", "enum" => [1, 2]},
      "protocol" => %{"type" => "integer", "enum" => [1]},
      "backend" => %{"type" => "string", "enum" => ["elixir_worker"]},
      "entrypoint" => @text,
      "license_file" => @text,
      "options_schema" => %{"type" => "object"},
      "exports" => %{"type" => "object"},
      "requires" => %{"type" => "object"},
      "subscriptions" => %{"type" => "array", "maxItems" => 4, "items" => %{"type" => "object"}},
      "capabilities" => %{"type" => "array", "maxItems" => 32, "items" => @text},
      "files" => %{
        "type" => "array",
        "minItems" => 2,
        "maxItems" => 64,
        "items" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ~w(path sha256 bytes),
          "properties" => %{
            "path" => @text,
            "sha256" => %{"type" => "string", "minLength" => 64, "maxLength" => 64},
            "bytes" => %{"type" => "integer", "minimum" => 0, "maximum" => 8_388_608}
          }
        }
      },
      "runtime" => %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ~w(elixir otp platforms),
        "properties" => %{
          "elixir" => @text,
          "otp" => %{
            "type" => "array",
            "minItems" => 1,
            "maxItems" => 16,
            "items" => %{"type" => "integer", "minimum" => 27, "maximum" => 255}
          },
          "platforms" => %{"type" => "array", "minItems" => 1, "maxItems" => 8, "items" => @text}
        }
      }
    }
  }

  @doc "Decode bounded JSON with duplicate keys rejected at every nesting level."
  def decode(bytes) when is_binary(bytes) and byte_size(bytes) <= @limit do
    with {:ok, manifest} <- Ipse.JSON.decode_bounded(bytes),
         :ok <- Schema.validate_arguments(@schema, manifest),
         true <- Enum.all?(~w(format protocol), &(manifest[&1] === 1)),
         true <-
           Ipse.Extension.Catalog.sdk_capabilities?(manifest["sdk"], manifest["capabilities"]),
         true <-
           Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\/[a-z][a-z0-9_-]{0,63}\z/, manifest["id"]),
         {:ok, _} <- Version.parse(manifest["version"]),
         {:ok, _} <- Version.parse_requirement(manifest["runtime"]["elixir"]),
         true <-
           Regex.match?(~r/\A[A-Z][A-Za-z0-9_]*(\.[A-Z][A-Za-z0-9_]*)*\z/, manifest["entrypoint"]),
         :ok <- Schema.validate_schema(manifest["options_schema"]),
         true <- manifest["options_schema"]["type"] == "object",
         :ok <- Ipse.Extension.Catalog.validate(manifest["exports"], manifest["capabilities"]),
         :ok <-
           Ipse.Extension.Subscriptions.validate(
             manifest["subscriptions"],
             manifest["capabilities"]
           ),
         :ok <-
           Ipse.Extension.Subscriptions.validate_handlers(
             manifest["subscriptions"],
             manifest["exports"]
           ),
         :ok <-
           Ipse.Extension.Services.validate_requirements(
             manifest["requires"],
             manifest["capabilities"]
           ),
         true <- valid_files?(manifest),
         true <- unique?(manifest["capabilities"]),
         true <-
           Enum.all?(manifest["capabilities"], &Regex.match?(~r/\A[a-z][a-z0-9_.-]{0,127}\z/, &1)),
         true <- unique?(manifest["runtime"]["otp"]),
         true <- Enum.all?(manifest["runtime"]["otp"], &is_integer/1),
         true <- unique?(manifest["runtime"]["platforms"]),
         true <-
           Enum.all?(
             manifest["runtime"]["platforms"],
             &Regex.match?(~r/\A[a-zA-Z0-9_.-]{1,128}\z/, &1)
           ) do
      {:ok, manifest}
    else
      _ -> {:error, :invalid_extension_manifest}
    end
  rescue
    _ -> {:error, :invalid_extension_manifest}
  end

  def decode(_), do: {:error, :invalid_extension_manifest}

  @doc "Compatibility is explicit; admission must recheck it before activation."
  def compatible?(manifest) do
    Version.match?(System.version(), manifest["runtime"]["elixir"]) and
      String.to_integer(System.otp_release()) in manifest["runtime"]["otp"] and
      to_string(:erlang.system_info(:system_architecture)) in manifest["runtime"]["platforms"]
  rescue
    _ -> false
  end

  @doc "Allow portable relative file paths, excluding manifest and traversal."
  def safe_path?(path) when is_binary(path) do
    byte_size(path) <= 256 and path != "extension.json" and
      Regex.match?(~r/\A[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*\z/, path) and
      length(String.split(path, "/")) <= 8 and
      Enum.all?(String.split(path, "/"), &(&1 not in [".", ".."]))
  end

  def safe_path?(_), do: false

  defp valid_files?(manifest) do
    files = manifest["files"]
    paths = Enum.map(files, & &1["path"])

    unique?(paths) and Enum.all?(paths, &safe_path?/1) and
      Enum.all?(
        files,
        &(is_integer(&1["bytes"]) and Regex.match?(~r/\A[0-9a-f]{64}\z/, &1["sha256"]))
      ) and
      Enum.sum(Enum.map(files, & &1["bytes"])) <= 33_554_432 and
      manifest["license_file"] in paths and
      "ebin/Elixir.#{manifest["entrypoint"]}.beam" in paths and
      not Enum.any?(paths, fn path -> Enum.any?(paths, &String.starts_with?(&1, path <> "/")) end)
  end

  defp unique?(values), do: length(values) == length(Enum.uniq(values))

  import Bitwise, only: [band: 2]
  @invalid {:error, :invalid_extension_artifact}

  @doc "Snapshot only declared files. No builds, code loading, network or activation."
  def import(source, root) when is_binary(source) and is_binary(root) do
    with {:ok, bytes} <- read_regular(source, "extension.json", 16_384),
         {:ok, manifest} <- decode(bytes),
         {:ok, files} <- snapshot(source, manifest),
         :ok <- private_directory(root) do
      digest = Ipse.JSON.sha256(bytes)

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
         true <- Ipse.JSON.sha256(bytes) == digest,
         {:ok, manifest} <- decode(bytes),
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
           true <- Ipse.JSON.sha256(bytes) == file["sha256"] do
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
