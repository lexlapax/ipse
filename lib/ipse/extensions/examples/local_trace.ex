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
      {:ok, %{directory: path}}
    end
  end

  @impl true
  def handle("observe.local", payload, state) do
    with true <- Ipse.Observability.Event.valid?(payload["event"]),
         handle when is_binary(handle) <- payload["handle"],
         true <- Regex.match?(~r/\A[0-9a-f]{32}\z/, handle),
         bytes = Jason.encode!(payload["event"]) <> "\n",
         limits = payload["limits"],
         true <- is_integer(limits["file_bytes"]) and limits["file_bytes"] in 16_384..10_485_760,
         true <- limits["retained_files"] in 1..2,
         true <- byte_size(bytes) <= limits["file_bytes"],
         path = Path.join(state.directory, handle <> ".jsonl"),
         :ok <- write(path, bytes, limits) do
      {:ok,
       %{
         "api_version" => 1,
         "kind" => "ack",
         "handle" => handle,
         "event_id" => payload["event"]["event"]["event_id"],
         "sequence" => payload["event"]["sequence"]
       }, state}
    else
      _ -> {:error, :local_trace_failed}
    end
  end

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
