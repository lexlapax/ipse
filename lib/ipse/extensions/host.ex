defmodule Ipse.Extensions.Host do
  @moduledoc "Ordered bounded transform jobs, owned by Session's monitored task chain."
  alias Ipse.Extensions.{Registry, Worker, Projection}

  def enabled?(config, stage),
    do: Enum.any?(Map.get(config, :extensions, []), &(stage in &1.identity["capabilities"]))

  def run(config, stage, owner, job_ref) do
    config
    |> Map.get(:extensions, [])
    |> Enum.filter(&(stage in &1.identity["capabilities"]))
    |> Enum.reduce_while(:ok, fn entry, :ok ->
      with true <- Registry.live?(entry.identity),
           {:ok, intent, input} <-
             GenServer.call(owner, {:extension_begin, job_ref, entry.identity["instance"], stage}),
           {:ok, result} <- invoke(entry, stage, input),
           {:ok, event} <- Projection.build(intent, input, result),
           :ok <- GenServer.call(owner, {:extension_commit, job_ref, event}) do
        {:cont, :ok}
      else
        _ ->
          {:halt,
           {:error,
            "Extension transform failed or expired; committed input/output remains available. No callback was replayed."}}
      end
    end)
  end

  defp invoke(entry, stage, input) do
    with {:ok, worker} <-
           Worker.start(
             owner: self(),
             store: entry.store,
             digest: entry.identity["artifact"],
             trusted: entry.identity["artifact"],
             artifact_sha256: entry.identity["artifact_sha256"],
             options: entry.options
           ) do
      try do
        with {:ok, _} <- Worker.call(worker, "initialize", entry.options),
             {:ok, result} <- Worker.call(worker, stage, %{"text" => input}),
             :ok <- Worker.close(worker) do
          {:ok, result}
        end
      after
        if Process.alive?(worker), do: Worker.close(worker)
      end
    end
  end

  def invoke_export(stage, name, arguments, owner, job_ref) do
    with {:ok, intent, entry} <-
           GenServer.call(owner, {:extension_invoke_begin, job_ref, stage, name, arguments}),
         {:ok, worker} <-
           Worker.start(
             owner: self(),
             store: entry.store,
             digest: entry.identity["artifact"],
             trusted: entry.identity["artifact"],
             artifact_sha256: entry.identity["artifact_sha256"],
             options: entry.options
           ) do
      try do
        with {:ok, _} <- Worker.call(worker, "initialize", entry.options),
             {:ok, response} <- Worker.call(worker, stage, intent["payload"]),
             {:ok, event} <- Ipse.Extensions.Invocation.build_result(intent, response),
             :ok <- Worker.close(worker) do
          {:extension_invocation_result, event}
        else
          _ -> invocation_unknown()
        end
      after
        if Process.alive?(worker), do: Worker.close(worker)
      end
    else
      _ -> invocation_unknown()
    end
  catch
    :exit, _ -> invocation_unknown()
  end

  defp invocation_unknown,
    do:
      {:unknown,
       "Extension outcome unknown after refusal, failure or interruption. Inspect its receipt before retrying; no callback was replayed."}
end
