defmodule IpseKnowledgeExample.EvaluationInventory do
  @moduledoc "Read-only State metadata audit in a separately loaded, verified domain artifact."
  import Bitwise
  alias Ipse.Extensions.{Manifest, Registry, State}
  @bytes 1_048_576

  @doc "Exact project-scope deletions after all roots in a verified partition are suppressed."
  def collection_requests(path, expected_sha256, partition) do
    with {:ok, ^expected_sha256} <- fingerprint(path) do
      if expected_sha256 == nil do
        {:ok, []}
      else
        bytes = File.read!(path)
        true = Manifest.sha256(bytes) == expected_sha256
        :ok = validate_namespace!(bytes, path)
        state = JSON.decode!(bytes)

        records =
          state["records"]
          |> Map.values()
          |> Enum.filter(&(not &1["deleted"] and get_in(&1, ["value", "partition"]) == partition))

        true =
          Enum.all?(records, fn row ->
            value = row["value"]

            value["kind"] == "page" or
              (value["kind"] == "root" and value["state"] == "suppressed" and
                 value["draft"] == nil)
          end)

        requests =
          records
          |> Enum.filter(&(get_in(&1, ["value", "kind"]) == "page"))
          |> Enum.sort_by(& &1["key"])
          |> Enum.map(fn row ->
            %{
              "op" => "state.delete",
              "scope" => "project",
              "key" => row["key"],
              "expected_revision" => row["revision"]
            }
          end)

        {:ok, ^expected_sha256} = fingerprint(path)
        {:ok, requests}
      end
    else
      _ -> {:error, :collection_unavailable}
    end
  rescue
    _ -> {:error, :collection_unavailable}
  end

  def fingerprint(path) do
    case File.lstat(path) do
      {:error, :enoent} ->
        {:ok, nil}

      {:ok, %{type: :regular, size: size, mode: mode}} when size <= @bytes ->
        true = (mode &&& 0o077) == 0
        bytes = File.read!(path)
        true = byte_size(bytes) <= @bytes
        {:ok, Manifest.sha256(bytes)}

      _ ->
        {:error, :inventory_unavailable}
    end
  rescue
    _ -> {:error, :inventory_unavailable}
  end

  def snapshot(path, store, digest, partition, output) do
    true = :code.is_loaded(IpseKnowledge.Store) == false
    {:ok, artifact} = Registry.lookup(store, digest)

    case File.lstat(path) do
      {:error, :enoent} ->
        {:ok,
         %{
           "status" => "absent",
           "artifact_sha256" => digest,
           "partition" => partition,
           "state_sha256" => nil,
           "state_file_bytes" => 0,
           "inventory" => nil
         }}

      {:ok, stat} ->
        true = stat.type == :regular and stat.size <= @bytes and (stat.mode &&& 0o077) == 0
        bytes = File.read!(path)
        true = byte_size(bytes) <= @bytes
        validate_namespace!(bytes, path)
        hash = Manifest.sha256(bytes)
        result = Path.join(output, "storage-inventory-" <> Ipse.Usage.id() <> ".json")
        File.write!(result, "", [:exclusive])
        File.chmod!(result, 0o600)

        expression = ~S'''
        try do
          [path, expected, partition, output] = System.argv()
          %{type: :regular, size: size} = File.lstat!(path)
          true = size <= 1_048_576
          bytes = File.read!(path)
          true = byte_size(bytes) <= 1_048_576
          true = Ipse.Extensions.Manifest.sha256(bytes) == expected
          state = JSON.decode!(bytes)
          {:ok, report} = IpseKnowledge.Store.inventory(
            Map.take(state, ~w(records generation)), partition)
          true = Ipse.Extensions.Manifest.sha256(File.read!(path)) == expected
          File.write!(output, JSON.encode!(report))
        rescue
          _ -> System.halt(2)
        end
        '''

        {_, 0} =
          System.cmd(
            System.find_executable("elixir") || raise("Elixir unavailable"),
            [
              "--erl",
              "+S 2:2",
              "-pa",
              Application.app_dir(:ipse, "ebin"),
              "-pa",
              Application.app_dir(:jason, "ebin"),
              "-pa",
              Path.join(artifact.path, "ebin"),
              "-e",
              expression,
              "--",
              path,
              hash,
              partition,
              result
            ],
            stderr_to_stdout: true
          )

        true = File.read!(path) == bytes
        {:ok, ^artifact} = Registry.lookup(store, digest)
        %{type: :regular, size: size} = File.lstat!(result)
        true = size <= @bytes
        {:ok, inventory} = Manifest.decode_json(File.read!(result), @bytes)
        true = :code.is_loaded(IpseKnowledge.Store) == false

        {:ok,
         %{
           "status" => "verified",
           "artifact_sha256" => digest,
           "partition" => partition,
           "state_sha256" => hash,
           "state_file_bytes" => byte_size(bytes),
           "inventory" => inventory,
           "inventory_path" => Path.basename(result),
           "inventory_sha256" => Manifest.sha256(File.read!(result))
         }}

      _ ->
        {:error, :inventory_unavailable}
    end
  rescue
    _ -> {:error, :inventory_unavailable}
  end

  defp validate_namespace!(bytes, path) do
    namespace = path |> Path.dirname() |> Path.basename()
    true = Regex.match?(~r/\A[0-9a-f]{64}\z/, namespace)
    {:ok, state} = Manifest.decode_json(bytes, @bytes)
    true = Enum.sort(Map.keys(state)) == ~w(generation namespace records version)
    true = state["version"] === 1 and state["namespace"] == namespace
    true = is_integer(state["generation"]) and state["generation"] in 0..9_007_199_254_740_991
    records = state["records"]
    true = is_map(records) and map_size(records) <= 256

    true =
      Enum.all?(records, fn {key, record} ->
        State.valid_outcome?(
          %{"op" => "state.get", "key" => key},
          "ok",
          %{"generation" => state["generation"], "record" => record},
          nil
        ) and record["revision"] > 0
      end)

    true =
      Enum.sum(Enum.map(records, fn {_, record} -> record["revision"] end)) == state["generation"]

    :ok
  end
end
