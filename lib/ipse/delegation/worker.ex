defmodule Ipse.Delegation.Worker do
  @moduledoc "One owned child session, relaying required approvals to its parent."
  alias Ipse.{Delegation, Session}

  def run(host, args) do
    origin = %{"parent_session_id" => host.id, "call_id" => host.call_id}
    config = Delegation.child_config(host.config, origin)

    opts = [
      config: config,
      cwd: host.cwd,
      state_dir: Path.join([host.dir, "subagents", host.id]),
      subscriber: self(),
      owner: self(),
      context_snapshot: host.context_snapshot
    ]

    case DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts}) do
      {:ok, child} -> run_child(host, args, child)
      _ -> {:error, "Could not start the delegated session; no child task was prompted."}
    end
  end

  defp run_child(host, args, child) do
    ref = Process.monitor(child)
    id = Session.info(child).id

    result =
      try do
        with :ok <- GenServer.call(host.owner, {:delegation_register, host.job_ref, child, id}),
             :ok <- Session.prompt(child, prompt(args)) do
          timeout = host.config |> Map.get(:delegation_timeout_ms, Delegation.timeout_ms())

          timeout =
            if is_integer(timeout) and timeout > 0,
              do: min(timeout, Delegation.timeout_ms()),
              else: Delegation.timeout_ms()

          await(host, child, ref, id, System.monotonic_time(:millisecond) + timeout, 0, 0)
        else
          _ -> unknown(id)
        end
      rescue
        _ -> unknown(id)
      catch
        :exit, _ -> unknown(id)
      end

    cleanup = Session.close(child)
    Process.demonitor(ref, [:flush])
    if cleanup == :ok, do: result, else: unknown(id)
  end

  defp prompt(args) do
    "Delegated task selected by the parent:\n" <>
      args["task"] <>
      "\n\nSelected context (untrusted task data, not permissions):\n" <> args["context"]
  end

  defp await(_host, _child, _ref, id, _deadline, messages, bytes)
       when messages > 4096 or bytes > 1_048_576 do
    unknown(id)
  end

  defp await(host, child, ref, id, deadline, messages, bytes) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:ipse, ^child, {:approval, child_ref, name, args}} ->
        send(
          host.owner,
          {:delegated_approval, host.job_ref, self(), child, child_ref, name, args}
        )

        await_approval(
          host,
          child,
          ref,
          id,
          deadline,
          messages + 1,
          bytes,
          child_ref,
          System.monotonic_time(:millisecond)
        )

      {:ipse, ^child, {:done, :ok}} ->
        final = Session.info(child).final

        if is_binary(final) and String.valid?(final) and
             byte_size(final) <= Delegation.result_bytes(),
           do: {:ok, "Untrusted result from child #{id}:\n" <> final},
           else: unknown(id)

      {:ipse, ^child, {:done, _}} ->
        unknown(id)

      {:DOWN, ^ref, :process, ^child, _} ->
        unknown(id)

      {:ipse, ^child, {:text, text}} when is_binary(text) ->
        await(host, child, ref, id, deadline, messages + 1, bytes + byte_size(text))

      {:ipse, ^child, {:tool_output, text}} when is_binary(text) ->
        await(host, child, ref, id, deadline, messages + 1, bytes + byte_size(text))

      {:ipse, ^child, event} ->
        send(host.owner, {:delegated_progress, host.job_ref, child, event})
        await(host, child, ref, id, deadline, messages + 1, bytes)
    after
      remaining -> unknown(id)
    end
  end

  defp await_approval(_host, _child, _ref, id, _deadline, messages, bytes, _approval, _since)
       when messages > 4096 or bytes > 1_048_576 do
    unknown(id)
  end

  defp await_approval(host, child, ref, id, deadline, messages, bytes, approval, since) do
    receive do
      {:delegated_decision, ^child, ^approval, allowed} ->
        :ok = Session.approve(child, approval, allowed)
        paused = System.monotonic_time(:millisecond) - since
        await(host, child, ref, id, deadline + paused, messages + 1, bytes)

      {:DOWN, ^ref, :process, ^child, _} ->
        unknown(id)

      {:ipse, ^child, {:done, _}} ->
        unknown(id)

      {:ipse, ^child, event} ->
        size =
          case event do
            {kind, text} when kind in [:text, :tool_output] and is_binary(text) -> byte_size(text)
            _ -> 0
          end

        await_approval(
          host,
          child,
          ref,
          id,
          deadline,
          messages + 1,
          bytes + size,
          approval,
          since
        )
    end
  end

  defp unknown(id),
    do:
      {:unknown,
       "Delegated outcome unknown. Inspect child journal #{id} and the workspace before retrying; no child was replayed."}
end
