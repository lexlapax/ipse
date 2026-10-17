defmodule Ipse.Extensions.Manifest do
  @moduledoc "Version-one inert worker artifact descriptors. Validation never loads code."
  alias Ipse.MCP.Schema

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
      "sdk" => %{"type" => "integer", "enum" => [1]},
      "protocol" => %{"type" => "integer", "enum" => [1]},
      "backend" => %{"type" => "string", "enum" => ["elixir_worker"]},
      "entrypoint" => @text,
      "license_file" => @text,
      "options_schema" => %{"type" => "object"},
      "exports" => %{"type" => "object"},
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
    with {:ok, manifest} <- decode_json(bytes),
         :ok <- Schema.validate_arguments(@schema, manifest),
         true <- Enum.all?(~w(format sdk protocol), &(manifest[&1] === 1)),
         true <-
           Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\/[a-z][a-z0-9_-]{0,63}\z/, manifest["id"]),
         {:ok, _} <- Version.parse(manifest["version"]),
         {:ok, _} <- Version.parse_requirement(manifest["runtime"]["elixir"]),
         true <-
           Regex.match?(~r/\A[A-Z][A-Za-z0-9_]*(\.[A-Z][A-Za-z0-9_]*)*\z/, manifest["entrypoint"]),
         :ok <- Schema.validate_schema(manifest["options_schema"]),
         true <- manifest["options_schema"]["type"] == "object",
         :ok <- Ipse.Extensions.Catalog.validate(manifest["exports"], manifest["capabilities"]),
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

  @doc false
  def decode_json(bytes) when is_binary(bytes) and byte_size(bytes) <= 32_768 do
    with {:ok, ordered} <- Jason.decode(bytes, objects: :ordered_objects),
         {:ok, value} <- unique_object(ordered, 0) do
      {:ok, value}
    end
  rescue
    _ -> {:error, :invalid_json}
  end

  def decode_json(_), do: {:error, :invalid_json}

  @doc "Compatibility is explicit; admission must recheck it before activation."
  def compatible?(manifest) do
    Version.match?(System.version(), manifest["runtime"]["elixir"]) and
      String.to_integer(System.otp_release()) in manifest["runtime"]["otp"] and
      to_string(:erlang.system_info(:system_architecture)) in manifest["runtime"]["platforms"]
  rescue
    _ -> false
  end

  def sha256(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

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

  defp unique_object(_value, depth) when depth > 16, do: {:error, :invalid_json}

  defp unique_object(%Jason.OrderedObject{values: pairs}, depth) do
    if length(pairs) == map_size(Map.new(pairs)) do
      Enum.reduce_while(pairs, {:ok, %{}}, fn {key, value}, {:ok, map} ->
        case unique_object(value, depth + 1) do
          {:ok, decoded} -> {:cont, {:ok, Map.put(map, key, decoded)}}
          error -> {:halt, error}
        end
      end)
    else
      {:error, :duplicate_key}
    end
  end

  defp unique_object(list, depth) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn value, {:ok, acc} ->
      case unique_object(value, depth + 1) do
        {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp unique_object(value, _depth), do: {:ok, value}
end
