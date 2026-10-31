defmodule Ipse.Runner.ManagementTerminal do
  @moduledoc false
  # Private exact-facts display candidate. It does not read input, mint a permit,
  # publish, or expose this route to workers or the public management commands.
  alias Ipse.{JSON, Runner}
  alias Ipse.CLI.Knowledge.Management
  alias Ipse.Journal.Writer
  alias Ipse.Runner.{Review, Transaction}
  alias Ipse.Session.{Lock, Resources}

  def display(owned, caps, facts, overall_wall)
      when is_map(owned) and is_list(caps) and is_map(facts) and is_integer(overall_wall) do
    with [identity, consent, collection] <- caps,
         true <- Process.get({Ipse.Extension.ProjectIdentity, :lock_held}) === true,
         true <- Process.get({Ipse.Extension.Consent, :lock_held}) === consent,
         true <- Process.get({Ipse.Extension.Collection, :lock_held}) === collection,
         [%{slot: 0}, %{slot: 1}, %{slot: 2}] = ids <- Enum.map(caps, &identity/1),
         true <-
           identity.owner == self() and consent.owner == self() and collection.owner == self(),
         true <- length(Enum.uniq(Enum.map(ids, & &1.pid))) == 1,
         true <- owned.journal_owner == self() and owned.cli_owner == owned.cli_control.owner,
         true <- owned.cli_control.operation == owned.journal_control.operation,
         {:ok, display, _challenge} <-
           Review.preview_management_display("forget", facts, System.system_time(:millisecond)),
         {:ok, helper} <- Runner.protected_helper(Path.dirname(owned.directory)),
         {:ok, ticket} <- Resources.register(:lock) do
      result = run(owned, caps, ids, facts, display, overall_wall, helper)

      Resources.closed(
        ticket,
        if(match?({:ok, _}, result), do: :ok, else: {:error, :cleanup_unconfirmed})
      )

      result
    else
      _ -> {:error, :management_display_refused}
    end
  rescue
    _ -> {:unknown, :management_display_unconfirmed}
  catch
    _, _ -> {:unknown, :management_display_unconfirmed}
  end

  def display(_, _, _, _), do: {:error, :management_display_refused}

  defp identity(cap) do
    case Transaction.retained_share_identity(cap) do
      {:ok, id} -> id
      _ -> nil
    end
  end

  defp run(owned, caps, ids, facts, display, overall_wall, helper) do
    operation = owned.cli_control.operation
    deadline = owned.cli_control.deadline
    remaining = min(deadline - System.monotonic_time(:millisecond), 5_000)
    if remaining <= 0 or System.system_time(:millisecond) >= overall_wall, do: throw(:expired)
    job = make_ref()
    generation = make_ref()

    with {:reply, {:ok, token, snapshot}} <-
           response(
             Writer.request_share_barrier(owned.writer, operation, job, generation),
             deadline
           ),
         true <-
           snapshot.session_id == owned.id and snapshot.job_ref == job and
             snapshot.owner_generation == generation,
         {:reply, {:ok, transport}} <-
           response(Lock.request_share_arm(owned.guard, owned.writer, token, operation), deadline),
         {:reply, {:ok, journal}} <-
           response(
             Lock.request_share_identity(owned.guard, token, operation, deadline),
             deadline
           ) do
      port =
        Port.open({:spawn_executable, String.to_charlist(helper)}, [
          :binary,
          :exit_status,
          :nouse_stdio,
          :hide,
          args: ["--operator-input", Integer.to_string(remaining), "v5-management-lease-display"]
        ])

      try do
        with {:os_pid, pid} when is_integer(pid) and pid > 0 <- Port.info(port, :os_pid),
             {:ok, <<native_clock::64>>} <- frame(port, ?R, owned.cli_owner, deadline),
             native_deadline =
               native_clock + max(deadline - System.monotonic_time(:millisecond), 0),
             {:ok, cli_pipe} <- pipe_identity(owned.cli_control.sender_pid),
             {:ok, journal_pipe} <- pipe_identity(owned.journal_control.sender_pid),
             {:ok, tty} <- File.stat("/proc/#{pid}/fd/0"),
             true <- tty.type == :device,
             bindings =
               Enum.map(0..5, fn _ ->
                 {:crypto.strong_rand_bytes(16), :crypto.strong_rand_bytes(32)}
               end),
             [cli_pair, journal_pair | lease_pairs] <- bindings,
             owners =
               entry(owned.cli_control.sender_pid, cli_pair, cli_pipe) <>
                 entry(owned.journal_control.sender_pid, journal_pair, journal_pipe),
             leases = [journal | ids],
             slots = [0, 0, 1, 2],
             operations = [transport, operation, operation, operation],
             manifest =
               Enum.zip([slots, operations, leases, lease_pairs])
               |> Enum.map(fn {slot, op, id, pair} ->
                 <<slot, op::binary, entry(id.pid, pair, id)::binary>>
               end)
               |> IO.iodata_to_binary(),
             expiry =
               min(
                 overall_wall,
                 System.system_time(:millisecond) +
                   max(deadline - System.monotonic_time(:millisecond), 0)
               ),
             body =
               <<operation::binary, 4, owners::binary, manifest::binary, tty.major_device::64,
                 tty.inode::64, tty.minor_device::64, expiry::64, native_deadline::64,
                 byte_size(display)::32, display::binary>>,
             :ok <- send_frame(port, ?I, body),
             {:ok, <<^operation::binary-size(16), 4>>} <-
               frame(port, ?H, owned.cli_owner, deadline),
             :ok <- transfer_controls(owned, pid, cli_pair, journal_pair),
             :ok <- export_all(owned, caps, leases, lease_pairs, pid, token, operation, deadline),
             {:ok, <<^operation::binary-size(16), 4, reader::32>>} <-
               frame(port, ?L, owned.cli_owner, deadline),
             :ok <- send_frame(port, ?A, body),
             :ok <- Ipse.Test.ManagementDisplayProbe.pause(owned, reader, pid, ids, journal),
             {:ok, <<^operation::binary-size(16), 4>>} <-
               frame(port, ?D, owned.cli_owner, deadline),
             true <- Port.command(port, <<?C, operation::binary>>, [:nosuspend]),
             {:reply, :ok} <-
               response(
                 Lock.request_share_settle(owned.guard, token, operation, deadline),
                 deadline
               ),
             :ok <- settle_all(caps, operation, deadline),
             {:ok, <<^operation::binary-size(16), 4>>} <-
               frame(port, ?C, owned.cli_owner, deadline),
             :ok <- Resources.management_control_prepare_close(owned.cli_control),
             true <- Port.command(port, <<?U, operation::binary>>, [:nosuspend]),
             :ok <- await_exit(port, owned.cli_owner, deadline),
             :ok <- await_exit(owned.journal_control.port, owned.cli_owner, deadline),
             :ok <- Resources.management_control_await_closed(owned.cli_control),
             :ok <- Writer.thaw_share_barrier(owned.writer, token, operation),
             true <-
               System.monotonic_time(:millisecond) < deadline and
                 System.system_time(:millisecond) < overall_wall do
          {:ok,
           %{
             facts_sha256: JSON.digest([facts]),
             display_sha256: JSON.sha256(display),
             operation: operation,
             journal_id: owned.id
           }}
        else
          _ -> {:unknown, :management_display_unconfirmed}
        end
      after
        if Port.info(port), do: Port.close(port)
      end
    else
      _ -> {:unknown, :management_display_unconfirmed}
    end
  end

  defp transfer_controls(owned, pid, {cn, cs}, {jn, js}) do
    with :ok <- Resources.management_control_transfer(owned.cli_control, pid, cn, cs),
         :ok <- Management.management_journal_control_transfer(owned.journal_control, pid, jn, js),
         do: :ok
  end

  defp export_all(owned, caps, [journal | ids], [jp | pairs], pid, token, operation, deadline) do
    with {:reply, :ok} <-
           response(
             Lock.request_share_export(
               owned.guard,
               token,
               operation,
               recipient(pid, jp, journal),
               deadline
             ),
             deadline
           ) do
      Enum.zip([caps, ids, pairs])
      |> Enum.reduce_while(:ok, fn {cap, id, pair}, :ok ->
        case Transaction.retained_share_export(cap, operation, recipient(pid, pair, id), deadline) do
          :ok -> {:cont, :ok}
          _ -> {:halt, :error}
        end
      end)
    else
      _ -> :error
    end
  end

  defp settle_all(caps, operation, deadline) do
    Enum.reduce_while(caps, :ok, fn cap, :ok ->
      case Transaction.retained_share_settle(cap, operation, deadline) do
        :ok -> {:cont, :ok}
        _ -> {:halt, :error}
      end
    end)
  end

  defp response(request, deadline),
    do:
      :gen_server.receive_response(
        request,
        max(deadline - System.monotonic_time(:millisecond), 0)
      )

  defp pipe_identity(pid) do
    with {:ok, s} <- File.stat("/proc/#{pid}/fd/0"),
         true <- Bitwise.band(s.mode, 0xF000) == 0x1000 and s.inode > 0 do
      {:ok, %{device: s.major_device, inode: s.inode}}
    else
      _ -> :error
    end
  end

  defp entry(pid, {name, secret}, id),
    do: <<pid::32, name::binary, secret::binary, id.device::64, id.inode::64>>

  defp recipient(pid, pair, id), do: entry(pid, pair, id)

  defp send_frame(port, tag, body),
    do:
      if(Port.command(port, <<tag, byte_size(body)::32, body::binary>>, [:nosuspend]),
        do: :ok,
        else: :error
      )

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
