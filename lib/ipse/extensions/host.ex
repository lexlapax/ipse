defmodule Ipse.Extensions.Host do
  @moduledoc "Ordered bounded transform jobs, owned by Session's monitored task chain."
  alias Ipse.Extensions.{Registry, Worker, Projection, Actions, State}

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
             {:ok, response, actions} <- continue(worker, response, entry, owner, job_ref, []),
             {:ok, event} <- Ipse.Extensions.Invocation.build_result(intent, response, actions),
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

  defp continue(worker, %{"kind" => "host_call"} = response, entry, owner, job_ref, actions)
       when length(actions) < 16 do
    with {:ok, request} <- Actions.proposal(response, entry.identity),
         {:ok, intent, outcome} <- run_action(owner, job_ref, request),
         {:ok, event} <- Actions.result(intent, outcome),
         {:ok, payload} <- GenServer.call(owner, {:extension_action_commit, job_ref, event}),
         true <- payload["outcome"]["status"] != "unknown",
         {:ok, response} <- Worker.call(worker, "host.actions", payload) do
      continue(worker, response, entry, owner, job_ref, actions ++ [event])
    else
      _ -> {:error, :extension_action_stopped}
    end
  end

  defp continue(_, %{"kind" => "host_call"}, _, _, _, _),
    do: {:error, :extension_action_limit}

  defp continue(_, response, _, _, _, actions), do: {:ok, response, actions}

  defp run_action(owner, job_ref, request) do
    case GenServer.call(owner, {:extension_action_begin, job_ref, request}, :infinity) do
      {:ok, intent, context} ->
        outcome =
          case State.execute(context.root, intent["namespace"], request, intent["operation_id"]) do
            {:ok, value} -> %{"status" => "ok", "value" => value}
            {:conflict, value} -> %{"status" => "conflict", "value" => value}
            _ -> %{"status" => "unknown", "value" => %{}}
          end

        {:ok, intent, outcome}

      {:denied, intent} ->
        {:ok, intent, %{"status" => "denied", "value" => %{}}}

      _ ->
        {:error, :extension_action_refused}
    end
  end
end
