defmodule Ipse.Extensions.Examples.LocalTrace do
  @moduledoc "Default-off owner-only rotating JSONL sink for allowlisted diagnostic metadata."
  @behaviour Ipse.Extension
  @impl true
  def describe, do: %{"sdk" => 1, "capabilities" => ["observe.local"]}
  @impl true
  def init(options) do
    requested = Path.expand(options["directory"])

    with {:ok, parent} <- Ipse.WorkspaceContext.canonical_path(Path.dirname(requested)),
         path = Path.join(parent, Path.basename(requested)),
         :ok <- private_directory(path) do
      {:ok,
       %{directory: path, retained_leases: Map.get(options, "retained_leases", 4), lease: nil}}
    end
  end

  @impl true
  def handle("observe.local", payload, state) do
    with true <- Ipse.Observability.Event.valid?(payload["event"]),
         handle when is_binary(handle) <- payload["handle"],
         true <- Regex.match?(~r/\A[0-9a-f]{32}\z/, handle),
         bytes = Jason.encode!(payload["event"]) <> "\n",
         limits = payload["limits"],
         true <- is_map(limits) and Enum.sort(Map.keys(limits)) == ~w(file_bytes retained_files),
         true <- is_integer(limits["file_bytes"]) and limits["file_bytes"] in 16_384..10_485_760,
         true <- limits["retained_files"] in 1..2,
         true <- byte_size(bytes) <= limits["file_bytes"],
         true <- state.retained_leases in 1..32,
         limits = Map.put(limits, "retained_leases", state.retained_leases),
         {:ok, lease} <- append(state, handle, bytes, limits) do
      {:ok,
       %{
         "api_version" => 1,
         "kind" => "ack",
         "handle" => handle,
         "event_id" => payload["event"]["event"]["event_id"],
         "sequence" => payload["event"]["sequence"]
       }, %{state | lease: lease}}
    else
      _ -> {:error, :local_trace_failed}
    end
  end

  defp append(state, handle, bytes, limits) do
    with {:ok, directory_lock} <- acquire(Path.join(state.directory, ".trace-ring.lock"), 25) do
      try do
        directory = Path.join(state.directory, "trace-ring-v1")

        with {:ok, catalog} <- catalog(directory, limits),
             {:ok, lease, _catalog} <- reserve(directory, catalog, state.lease, handle),
             true <- live?(directory_lock) and live?(lease.lock),
             path = Path.join(directory, "slot-#{lease.slot}.jsonl"),
             :ok <- write(path, bytes, limits),
             true <- live?(directory_lock) and live?(lease.lock) do
          {:ok, lease}
        else
          _ -> {:error, :trace_ring_unavailable}
        end
      after
        Ipse.Runner.unlock(directory_lock)
      end
    end
  end

  defp catalog(directory, limits) do
    case File.lstat(directory) do
      {:error, :enoent} ->
        value = %{"version" => 1, "limits" => limits, "next_slot" => 1, "slots" => %{}}

        with :ok <- File.mkdir(directory),
             :ok <- File.chmod(directory, 0o700),
             :ok <- publish(directory, value),
             do: {:ok, value}

      {:ok, %{type: :directory, mode: mode}} ->
        path = Path.join(directory, "catalog.json")

        with true <- Bitwise.band(mode, 0o077) == 0,
             {:ok, size} <- regular_size(path),
             true <- size > 0 and size <= 16_384,
             {:ok, bytes} <- bounded_read(path),
             {:ok, value} <- Ipse.Extensions.Manifest.decode_json(bytes, 16_384),
             true <- valid_catalog?(value, limits),
             do: {:ok, value}

      _ ->
        {:error, :unsafe_trace_ring}
    end
  end

  defp valid_catalog?(value, limits) do
    is_map(value) and Enum.sort(Map.keys(value)) == ~w(limits next_slot slots version) and
      value["version"] === 1 and value["limits"] === limits and
      is_integer(value["next_slot"]) and value["next_slot"] in 1..limits["retained_leases"] and
      is_map(value["slots"]) and map_size(value["slots"]) <= limits["retained_leases"] and
      Enum.all?(value["slots"], fn {slot, id} ->
        slot in Enum.map(1..limits["retained_leases"], &Integer.to_string/1) and id?(id)
      end) and length(Map.values(value["slots"])) == length(Enum.uniq(Map.values(value["slots"])))
  end

  defp reserve(_directory, catalog, %{slot: slot, lock: lock, handle: handle} = lease, handle) do
    if live?(lock) and catalog["slots"][Integer.to_string(slot)] == handle,
      do: {:ok, lease, catalog},
      else: {:error, :trace_lease_lost}
  end

  defp reserve(directory, catalog, nil, handle) do
    count = catalog["limits"]["retained_leases"]

    candidates =
      for offset <- 0..(count - 1), do: rem(catalog["next_slot"] - 1 + offset, count) + 1

    Enum.reduce_while(candidates, {:error, :trace_ring_full}, fn slot, _ ->
      case acquire(Path.join(directory, ".slot-#{slot}.lock"), 0) do
        {:ok, lock} ->
          path = Path.join(directory, "slot-#{slot}.jsonl")

          value =
            catalog
            |> Map.put("next_slot", rem(slot, count) + 1)
            |> put_in(["slots", Integer.to_string(slot)], handle)

          result =
            with {:ok, _} <- regular_size(path),
                 {:ok, _} <- regular_size(path <> ".1"),
                 :ok <- remove(path),
                 :ok <- remove(path <> ".1"),
                 :ok <- publish(directory, value),
                 do: {:ok, %{slot: slot, lock: lock, handle: handle}, value}

          if match?({:ok, _, _}, result) do
            {:halt, result}
          else
            Ipse.Runner.unlock(lock)
            {:halt, {:error, :trace_ring_unavailable}}
          end

        {:error, :trace_lock_busy} ->
          {:cont, {:error, :trace_ring_full}}

        _ ->
          {:halt, {:error, :trace_ring_unavailable}}
      end
    end)
  end

  defp reserve(_, _, _, _), do: {:error, :trace_lease_mismatch}

  defp publish(directory, catalog) do
    path = Path.join(directory, "catalog.json")
    temporary = Path.join(directory, ".catalog.next")
    bytes = Jason.encode!(catalog)

    with true <- byte_size(bytes) <= 16_384,
         {:ok, _} <- regular_size(path),
         {:ok, size} <- regular_size(temporary),
         true <- size <= 16_384,
         :ok <- remove(temporary),
         {:ok, file} <- File.open(temporary, [:write, :binary, :exclusive]) do
      result =
        try do
          with :ok <- File.chmod(temporary, 0o600),
               :ok <- IO.binwrite(file, bytes),
               :ok <- :file.sync(file),
               do: :ok
        after
          File.close(file)
        end

      with :ok <- result, do: File.rename(temporary, path)
    end
  end

  defp bounded_read(path) do
    with {:ok, file} <- File.open(path, [:read, :binary]) do
      try do
        case IO.binread(file, 16_385) do
          bytes when is_binary(bytes) and byte_size(bytes) <= 16_384 -> {:ok, bytes}
          _ -> {:error, :trace_catalog_too_large}
        end
      after
        File.close(file)
      end
    end
  end

  defp acquire(path, retries) do
    with {:ok, size} <- regular_size(path), true <- size == 0 do
      case Ipse.Runner.lock(path) do
        {:ok, lock} ->
          {:ok, lock}

        {:error, reason} when is_binary(reason) ->
          if String.starts_with?(reason, "cannot acquire session lock") do
            if retries > 0 do
              Process.sleep(10)
              acquire(path, retries - 1)
            else
              {:error, :trace_lock_busy}
            end
          else
            {:error, :trace_lock_unavailable}
          end
      end
    else
      _ -> {:error, :unsafe_trace_lock}
    end
  end

  defp live?(lock), do: is_port(lock) and Port.info(lock) != nil
  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)

  defp private_directory(path) do
    case File.lstat(path) do
      {:ok, %{type: :directory, mode: mode}} ->
        if Bitwise.band(mode, 0o077) == 0,
          do: ancestors(path),
          else: {:error, :private_directory_required}

      {:error, :enoent} ->
        with :ok <- ancestors(Path.dirname(path)),
             :ok <- File.mkdir(path),
             :ok <- File.chmod(path, 0o700),
             do: :ok

      _ ->
        {:error, :unsafe_trace_path}
    end
  end

  defp ancestors(path) do
    with {:ok, %{type: :directory}} <- File.lstat(path) do
      if Path.dirname(path) == path, do: :ok, else: ancestors(Path.dirname(path))
    else
      _ -> {:error, :unsafe_trace_path}
    end
  end

  defp write(path, bytes, limits) do
    with {:ok, size} <- regular_size(path),
         true <- size <= limits["file_bytes"],
         {:ok, backup_size} <- regular_size(path <> ".1"),
         true <- backup_size <= limits["file_bytes"],
         :ok <- rotate(path, size + byte_size(bytes), limits),
         {:ok, file} <- File.open(path, [:append, :binary]) do
      try do
        with :ok <- File.chmod(path, 0o600),
             :ok <- IO.binwrite(file, bytes),
             :ok <- :file.sync(file),
             do: :ok
      after
        File.close(file)
      end
    end
  end

  defp regular_size(path) do
    case File.lstat(path) do
      {:ok, %{type: :regular, size: size, links: 1, mode: mode}} ->
        if Bitwise.band(mode, 0o077) == 0, do: {:ok, size}, else: {:error, :private_file_required}

      {:error, :enoent} ->
        {:ok, 0}

      _ ->
        {:error, :unsafe_trace_path}
    end
  end

  defp rotate(_, next, %{"file_bytes" => limit}) when next <= limit, do: :ok

  defp rotate(path, _, limits) do
    backup = path <> ".1"

    with {:ok, _} <- regular_size(backup),
         :ok <- remove(backup) do
      if limits["retained_files"] == 2, do: File.rename(path, backup), else: remove(path)
    end
  end

  defp remove(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end
end
