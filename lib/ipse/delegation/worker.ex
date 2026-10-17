defmodule Ipse.Delegation.Worker do
  @moduledoc "One owned child session, relaying required approvals to its parent."
  alias Ipse.{Delegation, Session}

  def run(host, args) do
    origin = %{
      "parent_session_id" => host.id,
      "call_id" => host.call_id,
      "parent_request_id" => Map.get(host, :request_id)
    }

    with {:ok, config} <- Ipse.Profiles.child_config(host.config, origin, args) do
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
          _ -> unknown(id, "admission_refused")
        end
      rescue
        _ -> unknown(id, "worker_failed")
      catch
        :exit, _ -> unknown(id, "worker_failed")
      end

    cleanup = Session.close_confirmed(child)
    Process.demonitor(ref, [:flush])

    result =
      if match?({:ok, _}, result) and cleanup != :ok,
        do: unknown(id, "cleanup_unconfirmed"),
        else: result

    {status, reason, public_result} =
      case result do
        {:ok, text} -> {"result_recorded", "completed", {:ok, text}}
        {:unknown, text, reason} -> {"unknown", reason, {:unknown, text}}
      end

    try do
      case GenServer.call(
             host.owner,
             {:delegation_finished, host.job_ref, child, status, reason, cleanup == :ok}
           ) do
        :ok -> public_result
        _ -> public_unknown(id)
      end
    catch
      :exit, _ -> public_unknown(id)
    end
  end

  defp prompt(args) do
    "Delegated task selected by the parent:\n" <>
      args["task"] <>
      "\n\nSelected context (untrusted task data, not permissions):\n" <> args["context"]
  end

  defp await(_host, _child, _ref, id, _deadline, messages, bytes)
       when messages > 4096 or bytes > 1_048_576 do
    unknown(id, "bounds")
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
        info = Session.info(child)
        final = info.final

        if is_binary(final) and String.valid?(final) and
             byte_size(final) <= Delegation.result_bytes(),
           do:
             {:ok,
              "Host routing facts: #{Jason.encode!(info.runtime)}\nUntrusted result from child #{id}:\n" <>
                final},
           else: unknown(id, "result_unavailable")

      {:ipse, ^child, {:done, _}} ->
        unknown(id, "child_failed")

      {:DOWN, ^ref, :process, ^child, _} ->
        unknown(id, "child_down")

      {:ipse, ^child, {:text, text}} when is_binary(text) ->
        await(host, child, ref, id, deadline, messages + 1, bytes + byte_size(text))

      {:ipse, ^child, {:tool_output, text}} when is_binary(text) ->
        await(host, child, ref, id, deadline, messages + 1, bytes + byte_size(text))

      {:ipse, ^child, event} ->
        send(host.owner, {:delegated_progress, host.job_ref, child, event})
        await(host, child, ref, id, deadline, messages + 1, bytes)
    after
      remaining -> unknown(id, "timeout")
    end
  end

  defp await_approval(_host, _child, _ref, id, _deadline, messages, bytes, _approval, _since)
       when messages > 4096 or bytes > 1_048_576 do
    unknown(id, "bounds")
  end

  defp await_approval(host, child, ref, id, deadline, messages, bytes, approval, since) do
    receive do
      {:delegated_decision, ^child, ^approval, allowed} ->
        :ok = Session.approve(child, approval, allowed)
        paused = System.monotonic_time(:millisecond) - since
        await(host, child, ref, id, deadline + paused, messages + 1, bytes)

      {:DOWN, ^ref, :process, ^child, _} ->
        unknown(id, "child_down")

      {:ipse, ^child, {:done, _}} ->
        unknown(id, "child_failed")

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

  defp unknown(id, reason),
    do:
      {:unknown,
       "Delegated outcome unknown. Inspect child journal #{id} and the workspace before retrying; no child was replayed.",
       reason}

  defp public_unknown(id),
    do:
      {:unknown,
       "Delegated outcome unknown. Inspect child journal #{id} and the workspace before retrying; no child was replayed."}
end
