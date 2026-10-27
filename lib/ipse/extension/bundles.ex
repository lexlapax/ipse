defmodule Ipse.Extension.Bundles do
  @moduledoc "Inert packaged-artifact discovery and explicit import; neither operation grants trust or activation."
  alias Ipse.Extension.Artifact
  @error {:error, :extension_bundle_unavailable}
  @entry %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ~w(id path manifest_sha256),
    "properties" => %{
      "id" => %{"type" => "string", "minLength" => 1, "maxLength" => 64},
      "path" => %{"type" => "string", "minLength" => 1, "maxLength" => 128},
      "manifest_sha256" => %{"type" => "string", "minLength" => 64, "maxLength" => 64}
    }
  }
  @schema %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ~w(version artifacts),
    "properties" => %{
      "version" => %{"type" => "integer", "enum" => [1]},
      "artifacts" => %{"type" => "array", "minItems" => 1, "maxItems" => 8, "items" => @entry}
    }
  }

  @doc "Inspect shipped manifests without loading code or creating operator state."
  def inventory, do: inventory(Application.app_dir(:ipse, "priv/extension-bundles"))

  @doc false
  def inventory(root) do
    with {:ok, bytes} <- read(Path.join(root, "catalog.json"), 16_384),
         {:ok, catalog} <- Ipse.JSON.decode_unique(bytes),
         :ok <- Ipse.JSON.validate_arguments(@schema, catalog),
         entries = catalog["artifacts"],
         true <-
           Enum.map(entries, & &1["id"]) ==
             Enum.sort(Enum.uniq_by(Enum.map(entries, & &1["id"]), & &1)),
         true <- length(Enum.uniq_by(entries, & &1["path"])) == length(entries),
         {:ok, artifacts} <- manifests(root, entries) do
      {:ok, artifacts}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Copy a deliberately selected packaged artifact into the private artifact store. Host-only; caller supplies authorization."
  def install(id, home),
    do: install(Application.app_dir(:ipse, "priv/extension-bundles"), id, home)

  @doc false
  def install(root, id, home) do
    with true <- is_binary(home) and Path.type(home) == :absolute,
         {:ok, entries} <- inventory(root),
         entry when is_map(entry) <- Enum.find(entries, &(&1.id == id)),
         true <- Artifact.compatible?(entry.manifest),
         {:ok, artifact} <- Artifact.import(entry.path, Path.join(home, "extensions/artifacts")),
         true <- artifact.digest == entry.digest do
      {:ok, artifact}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp manifests(root, entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      with true <- Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, entry["id"]),
           true <- Artifact.safe_path?(entry["path"]),
           true <- Ipse.JSON.sha256?(entry["manifest_sha256"]),
           path = Path.join(root, entry["path"]),
           {:ok, bytes} <- read(Path.join(path, "extension.json"), 16_384),
           true <- Ipse.JSON.sha256(bytes) == entry["manifest_sha256"],
           {:ok, manifest} <- Artifact.decode(bytes) do
        {:cont,
         {:ok,
          acc ++
            [%{id: entry["id"], path: path, digest: entry["manifest_sha256"], manifest: manifest}]}}
      else
        _ -> {:halt, @error}
      end
    end)
  end

  defp read(path, limit) do
    with {:ok, %{type: :regular, size: size}} <- File.lstat(path),
         true <- size <= limit,
         {:ok, file} <- :file.open(String.to_charlist(path), [:read, :binary]) do
      try do
        case :file.read(file, limit + 1) do
          {:ok, bytes} when byte_size(bytes) == size -> {:ok, bytes}
          _ -> @error
        end
      after
        :file.close(file)
      end
    else
      _ -> @error
    end
  end
end
