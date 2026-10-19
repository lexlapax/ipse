defmodule Ipse.Extensions.Inference do
  @moduledoc "Owned inference lifetime shared by explicit text and embedding actions."

  def execute(context, intent, kind, perform) when kind in [:text, :embedding] do
    case GenServer.call(context.owner, {begin_message(kind), context.job_ref, intent}, :infinity) do
      {:ok, config, admission} -> run(context, intent, kind, perform, config, admission)
      _ -> {:failed, %{"code" => code(kind, :limit)}}
    end
  end

  defp run(context, intent, kind, perform, config, admission) do
    coordinator = self()
    tag = make_ref()
    monitor = Process.monitor(context.worker)

    task =
      Ipse.TaskResources.async(fn ->
        emit = fn
          {:provider_usage, raw} ->
            usage = Ipse.Usage.observation(admission, raw, 1)["usage"]
            send(coordinator, {tag, :usage, usage})

          _ ->
            :ok
        end

        Ipse.Budget.run(config, admission, emit, fn selected, guarded_emit ->
          result = perform.(selected, intent["request"], guarded_emit)

          case result do
            {:ok, value, raw} ->
              capture = %{value: value, usage: Ipse.Usage.observation(admission, raw, 1)["usage"]}
              send(coordinator, {tag, :response, capture})
              if kind == :embedding, do: guarded_emit.({:provider_usage, raw})

            _ ->
              :ok
          end

          result
        end)
      end)

    deadline = System.monotonic_time(:millisecond) + config.timeout_ms

    try do
      {result, capture, reason} = await(task, tag, monitor, context, intent, kind, deadline, nil)

      GenServer.call(
        context.owner,
        {finish_message(kind), context.job_ref, intent, result, capture, reason},
        :infinity
      )
    after
      Process.demonitor(monitor, [:flush])
      Task.shutdown(task, :brutal_kill)
    end
  end

  defp await(task, tag, monitor, context, intent, kind, deadline, capture) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 or not Ipse.Extensions.Registry.live?(context.identity) do
      Task.shutdown(task, :brutal_kill)
      capture = drain(tag, context, intent, kind, capture)
      {:cancelled, capture, code(kind, if(remaining <= 0, do: :timeout, else: :cancelled))}
    else
      receive do
        {^tag, :usage, usage} ->
          forward_usage(context, intent, kind, usage)
          await(task, tag, monitor, context, intent, kind, deadline, capture)

        {^tag, :response, response} ->
          await(task, tag, monitor, context, intent, kind, deadline, response)

        {ref, result} when ref == task.ref ->
          Process.demonitor(ref, [:flush])
          {result, capture, nil}

        {:DOWN, ^monitor, :process, _, _} ->
          Task.shutdown(task, :brutal_kill)
          {:cancelled, drain(tag, context, intent, kind, capture), code(kind, :cancelled)}

        {:DOWN, ref, :process, _, _} when ref == task.ref ->
          {{:error, :provider_down}, capture, nil}
      after
        min(remaining, 100) -> await(task, tag, monitor, context, intent, kind, deadline, capture)
      end
    end
  end

  defp drain(tag, context, intent, kind, capture) do
    receive do
      {^tag, :usage, usage} ->
        forward_usage(context, intent, kind, usage)
        drain(tag, context, intent, kind, capture)

      {^tag, :response, response} ->
        drain(tag, context, intent, kind, response)
    after
      0 -> capture
    end
  end

  defp forward_usage(context, intent, kind, usage) do
    :ok =
      GenServer.call(
        context.owner,
        {usage_message(kind), context.job_ref, intent["operation_id"], usage},
        :infinity
      )
  end

  defp begin_message(:text), do: :extension_model_begin
  defp begin_message(:embedding), do: :extension_embedding_begin
  defp usage_message(:text), do: :extension_model_usage
  defp usage_message(:embedding), do: :extension_embedding_usage
  defp finish_message(:text), do: :extension_model_finish
  defp finish_message(:embedding), do: :extension_embedding_finish
  defp code(:text, :limit), do: "model_limit"
  defp code(:text, :timeout), do: "model_timeout"
  defp code(:text, :cancelled), do: "model_cancelled"
  defp code(:embedding, :limit), do: "embedding_limit"
  defp code(:embedding, :timeout), do: "embedding_timeout"
  defp code(:embedding, :cancelled), do: "embedding_cancelled"
end
