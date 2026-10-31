defmodule Ipse.Runner.LeasedTerminal do
  @moduledoc false
  # Private synthetic integration candidate. It never accepts protected text or
  # worker-selected terminal/lease identities and has no production call site.
  alias Ipse.Extension.Host
  alias Ipse.Runner.Transaction
  alias Ipse.Session.Resources
  @payload "SYNTHETIC_LEASED_DISPLAY"

  def exercise(owner, job, intent, caps, cwd)
      when is_pid(owner) and is_reference(job) and is_map(intent) and is_list(caps) and
             is_binary(cwd) do
    with [a, b, c] <- caps,
         [%{slot: 0}, %{slot: 1}, %{slot: 2}] = identities <- Enum.map([a, b, c], &identity/1),
         true <- length(Enum.uniq(Enum.map(identities, & &1.pid))) == 1,
         {:ok, helper} <- Ipse.Runner.protected_helper(cwd),
         {:ok, ticket} <- Resources.register(:lock) do
      result =
        try do
          case Host.begin_controlled_session_share(owner, job, intent) do
            {:ok, cap, transport, _snapshot, controls} ->
              run(owner, job, cap, transport, controls, caps, identities, helper)

            _ ->
              {:error, :cleanup_unconfirmed}
          end
        catch
          kind, reason -> trace("catch=" <> inspect({kind, reason, __STACKTRACE__})); {:error, :cleanup_unconfirmed}
        end

      Resources.closed(ticket, if(result == :ok, do: :ok, else: {:error, :cleanup_unconfirmed}))
      result
    else
      _ -> {:error, :cleanup_unconfirmed}
    end
  rescue
    _ -> {:error, :cleanup_unconfirmed}
  end

  def exercise(_, _, _, _, _), do: {:error, :cleanup_unconfirmed}

  defp trace(stage) do
    File.write!("/tmp/ipse-tty-bridge-v7-markers", stage <> "\n", [:append]); :ok
  end
  defp identity(cap) do
    case Transaction.retained_share_identity(cap) do
      {:ok, identity} -> identity
      _ -> nil
    end
  end

  defp run(owner, job, cap, transport, controls, caps, identities, helper) do
    try do
      run_opened(owner, job, cap, transport, controls, caps, identities, helper)
    after
      if Port.info(controls.host_port),
        do: Host.abort_controlled_session_share(owner, job, cap, controls.host_port)
    end
  catch
    kind, reason -> trace("catch=" <> inspect({kind, reason, __STACKTRACE__})); {:error, :cleanup_unconfirmed}
  end

  defp run_opened(owner, job, cap, transport, controls, caps, identities, helper) do
    deadline = controls.deadline
    remaining = min(deadline - System.monotonic_time(:millisecond), 5_000)
    if remaining <= 0, do: throw(:expired)

    port =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :nouse_stdio,
        :hide,
        args: ["--operator-input", Integer.to_string(remaining), "v4-synthetic-lease-display"]
      ])

    try do
      with {:os_pid, pid} when is_integer(pid) and pid > 0 <- Port.info(port, :os_pid),
           {:os_pid, host_pid} <- Port.info(controls.host_port, :os_pid),
           {:ok, session_identity} <- Host.session_share_identity(owner, job, cap),
           {:ok, session_control} <- pipe_identity(controls.session_pid),
           {:ok, host_control} <- pipe_identity(host_pid),
           {:ok, tty} <- File.stat("/proc/#{pid}/fd/0"),
           true <- tty.type == :device,
           bindings =
             Enum.map(0..5, fn _ ->
               {:crypto.strong_rand_bytes(16), :crypto.strong_rand_bytes(32)}
             end),
           [session_pair, host_pair | lease_pairs] <- bindings,
           session_entry = entry(controls.session_pid, session_pair, session_control),
           host_entry = entry(host_pid, host_pair, host_control),
           leases = [session_identity | identities],
           slots = [0, 0, 1, 2],
           operations = [transport, controls.operation, controls.operation, controls.operation],
           manifest =
             Enum.zip([slots, operations, leases, lease_pairs])
             |> Enum.map(fn {slot, operation, id, pair} ->
               <<slot, operation::binary, entry(id.pid, pair, id)::binary>>
             end)
             |> IO.iodata_to_binary(),
           expiry =
             System.system_time(:millisecond) +
               max(deadline - System.monotonic_time(:millisecond), 0),
           body =
             <<controls.operation::binary, 4, session_entry::binary, host_entry::binary,
               manifest::binary, tty.major_device::64, tty.inode::64, tty.minor_device::64,
               expiry::64, byte_size(@payload)::32, @payload::binary>>,
           :ok <- send_frame(port, ?I, body),
           {:ok, <<operation::binary-size(16), 4>>} <- frame(port, ?H, owner, deadline),
           true <- operation == controls.operation,
           :ok <-
             configure_controls(owner, job, cap, controls, pid, session_pair, host_pair, deadline),
           :ok <- export_all(owner, job, cap, controls, pid, caps, leases, lease_pairs, deadline),
           {:ok, <<operation::binary-size(16), 4, _reader::32>>} <-
             frame(port, ?L, owner, deadline),
           true <- operation == controls.operation,
           :ok <- send_frame(port, ?A, body),
           {:ok, <<operation::binary-size(16), 4>>} <- frame(port, ?D, owner, deadline),
           true <- operation == controls.operation,
           :ok <- trace("got D"),
           true <- Port.command(port, <<?C, controls.operation::binary>>, [:nosuspend]),
           :ok <- trace("sent C"),
           :ok <- Host.settle_session_share(owner, job, cap),
           :ok <- trace("session settled"),
           :ok <-
             Enum.reduce_while(caps, :ok, fn tx, :ok ->
               trace("start slot " <> to_string(tx.depth))
               case Transaction.retained_share_settle(tx, controls.operation, deadline) do
                 :ok -> trace("slot settled " <> to_string(tx.depth)); {:cont, :ok}
                 _ -> {:halt, :error}
               end
             end),
           {:ok, <<operation::binary-size(16), 4>>} <- frame(port, ?C, owner, deadline),
           :ok <- trace("got final C"),
           true <- operation == controls.operation,
           :ok <- await_exit(port, owner, deadline),
           :ok <- trace("exit"),
           :ok <- Host.finish_controlled_session_share(owner, job, cap, controls.host_port) do
        trace("thawed")
        :ok
      else
        other -> trace("fail=" <> inspect(other)); {:error, :cleanup_unconfirmed}
      end
    after
      if Port.info(port), do: Port.close(port)
    end
  end

  defp pipe_identity(pid) do
    with {:ok, s} <- File.stat("/proc/#{pid}/fd/0"),
         true <- Bitwise.band(s.mode, 0xF000) == 0x1000 and s.inode > 0 do
      {:ok, %{device: s.major_device, inode: s.inode}}
    else
      _ -> {:error, :cleanup_unconfirmed}
    end
  end

  defp entry(pid, {name, secret}, id),
    do: <<pid::32, name::binary, secret::binary, id.device::64, id.inode::64>>

  defp recipient(pid, {name, secret}, id),
    do: <<pid::32, name::binary, secret::binary, id.device::64, id.inode::64>>

  defp configure_controls(owner, job, cap, controls, pid, {sn, ss}, {hn, hs}, deadline) do
    with :ok <- Host.configure_session_control(owner, job, cap, pid, sn, ss),
         :ok <- await_session_transfer(owner, cap, deadline),
         :ok <-
           Ipse.Runner.send_owner_control(
             controls.host_port,
             controls.operation,
             :host,
             pid,
             hn,
             hs
           ),
         :ok <- host_transfer(controls.host_port, owner, controls.operation, deadline, <<>>) do
      :ok
    end
  end

  defp await_session_transfer(owner, cap, deadline) do
    ref = Process.monitor(owner)

    try do
      receive do
        {:session_owner_control, ^cap, :transferred} -> :ok
        {:DOWN, ^ref, :process, _, _} -> :error
      after
        max(deadline - System.monotonic_time(:millisecond), 0) -> :error
      end
    after
      Process.demonitor(ref, [:flush])
    end
  end

  defp host_transfer(port, owner, operation, deadline, buffer) do
    expected = <<?H, 17::32, operation::binary, 2, ?T, 17::32, operation::binary, 2>>

    cond do
      System.monotonic_time(:millisecond) >= deadline ->
        :error

      buffer == expected ->
        :ok

      byte_size(buffer) >= byte_size(expected) or
          binary_part(expected, 0, byte_size(buffer)) != buffer ->
        :error

      true ->
        receive do
          {^port, {:data, bytes}} ->
            host_transfer(port, owner, operation, deadline, buffer <> bytes)

          {^port, _} ->
            :error
        after
          max(deadline - System.monotonic_time(:millisecond), 0) -> :error
        end
    end
  end

  defp export_all(owner, job, cap, controls, pid, caps, [session | ids], pairs, deadline) do
    [first | rest] = pairs

    with :ok <- Host.export_session_share(owner, job, cap, recipient(pid, first, session)) do
      Enum.zip([caps, ids, rest])
      |> Enum.reduce_while(:ok, fn {tx, id, pair}, :ok ->
        case Transaction.retained_share_export(
               tx,
               controls.operation,
               recipient(pid, pair, id),
               deadline
             ) do
          :ok -> {:cont, :ok}
          _ -> {:halt, :error}
        end
      end)
    end
  end

  defp send_frame(port, tag, body) do
    if Port.command(port, <<tag, byte_size(body)::32, body::binary>>, [:nosuspend]),
      do: :ok,
      else: :error
  end

  defp frame(port, tag, owner, deadline), do: frame(port, tag, owner, deadline, <<>>)

  defp frame(port, tag, owner, deadline, buffer) do
    case buffer do
      <<^tag, size::32, body::binary-size(size)>> when size <= 32 ->
        if System.monotonic_time(:millisecond) < deadline and Process.alive?(owner),
          do: {:ok, body},
          else: :error

      _ when byte_size(buffer) > 37 ->
        :error

      _ ->
        receive do
          {^port, {:data, bytes}} -> frame(port, tag, owner, deadline, buffer <> bytes)
          {^port, _} -> :error
        after
          max(deadline - System.monotonic_time(:millisecond), 0) -> :error
        end
    end
  end

  defp await_exit(port, owner, deadline) do
    receive do
      {^port, {:exit_status, 0}} ->
        if Process.alive?(owner) and System.monotonic_time(:millisecond) < deadline,
          do: :ok,
          else: :error

      {^port, _} ->
        :error
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> :error
    end
  end
end
