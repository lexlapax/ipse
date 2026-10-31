defmodule Ipse.Runner.ManagementTerminal do
  @moduledoc false
  # Private exact-facts display and retained same-guardian input candidate.
  # It does not mint permits, publish, or expose a worker or public route.
  alias Ipse.{JSON, Runner}
  alias Ipse.CLI.Knowledge.Management
  alias Ipse.Journal.Writer
  alias Ipse.Runner.{Review, Transaction}
  alias Ipse.Session.{Lock, Resources}
  alias Ipse.Session.StoredSources
  @input_slot {__MODULE__, :review_input}

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
      result = run(owned, caps, ids, facts, display, overall_wall, helper, :display)

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

  # A handle exists only in the file-effect owner that performed this exact
  # display. It is never an authority encoded in a receipt or worker input.
  @doc false
  def begin_review(owned, caps, facts, overall_wall),
    do: begin_review_for("forget", owned, caps, facts, overall_wall, nil)

  @doc false
  def begin_accept_review(owned, caps, facts, overall_wall, source_lease),
    do: begin_review_for("accept", owned, caps, facts, overall_wall, source_lease)

  @doc false
  def begin_historical_accept_review(owned, caps, facts, overall_wall),
    do: begin_review_for("accept", owned, caps, facts, overall_wall, :historical_pending)

  @doc false
  def begin_historical_accept_review(owned, caps, facts, overall_wall, annotation),
    do:
      begin_review_for(
        "accept",
        owned,
        caps,
        facts,
        overall_wall,
        :historical_pending,
        annotation
      )

  @doc false
  def begin_accept_group_review(owned, caps, facts, overall_wall, source_leases)
      when is_list(source_leases),
      do: begin_review_for("accept", owned, caps, facts, overall_wall, {:group, source_leases})

  def begin_accept_group_review(_, _, _, _, _), do: {:error, :management_display_refused}

  @doc false
  def begin_retention_review(owned, caps, facts, overall_wall) do
    command = Ipse.Extension.Collection.ManagedRetention.command(facts["policy"])
    begin_review_for(command, owned, caps, facts, overall_wall, nil)
  rescue
    _ -> {:error, :management_display_refused}
  end

  defp begin_review_for(
         command,
         owned,
         caps,
         facts,
         overall_wall,
         source_lease,
         annotation \\ nil
       )

  defp begin_review_for(command, owned, caps, facts, overall_wall, source_lease, annotation)
       when is_map(owned) and is_list(caps) and is_map(facts) and is_integer(overall_wall) do
    with nil <- Process.get(@input_slot),
         [_identity, consent, collection] <- caps,
         true <- Process.get({Ipse.Extension.ProjectIdentity, :lock_held}) === true,
         true <- Process.get({Ipse.Extension.Consent, :lock_held}) === consent,
         true <- Process.get({Ipse.Extension.Collection, :lock_held}) === collection,
         [%{slot: 0}, %{slot: 1}, %{slot: 2}] = ids <- Enum.map(caps, &identity/1),
         true <- Enum.all?(caps, &(&1.owner == self())),
         true <- length(Enum.uniq(Enum.map(ids, & &1.pid))) == 1,
         {:ok, source_identity} <- source_identity(command, source_lease),
         true <- owned.journal_owner == self() and owned.cli_owner == owned.cli_control.owner,
         true <- owned.cli_control.operation == owned.journal_control.operation,
         {:ok, display, challenge, wall} <- review_display(command, facts, overall_wall),
         {:ok, display} <- annotate_display(command, annotation, display),
         {:ok, helper} <- Runner.protected_helper(Path.dirname(owned.directory)),
         {:ok, ticket} <- Resources.register(:lock) do
      result =
        run(
          owned,
          caps,
          ids,
          facts,
          display,
          wall,
          helper,
          {:input, command, challenge, ticket},
          {source_lease, source_identity}
        )

      if not match?({:ok, _}, result),
        do: Resources.closed(ticket, {:error, :cleanup_unconfirmed})

      result
    else
      _ -> {:error, :management_display_refused}
    end
  rescue
    _ -> {:unknown, :management_display_unconfirmed}
  catch
    _, _ -> {:unknown, :management_display_unconfirmed}
  end

  defp begin_review_for(_, _, _, _, _, _, _), do: {:error, :management_display_refused}

  defp annotate_display(_, nil, display), do: {:ok, display}

  defp annotate_display("accept", annotation, display) when is_binary(annotation) do
    display = Ipse.CLI.Terminal.escape(annotation) <> display
    if byte_size(display) <= 8192, do: {:ok, display}, else: {:error, :management_display_refused}
  end

  defp annotate_display(_, _, _), do: {:error, :management_display_refused}

  defp source_identity("forget", nil), do: {:ok, nil}
  defp source_identity(command, nil) when command in ~w(pin ordinary duration), do: {:ok, nil}
  defp source_identity("accept", :historical_pending), do: {:ok, :historical_pending}

  defp source_identity("accept", {:group, leases}) when is_list(leases) do
    with true <- length(leases) in 1..128,
         true <- Enum.all?(leases, &is_reference/1),
         true <- length(Enum.uniq(leases)) == length(leases) do
      Enum.reduce_while(leases, {:ok, []}, fn token, {:ok, ids} ->
        case StoredSources.share_identity(token) do
          {:ok, identity} -> {:cont, {:ok, [identity | ids]}}
          _ -> {:halt, {:error, :management_display_refused}}
        end
      end)
      |> case do
        {:ok, ids} -> {:ok, Enum.reverse(ids)}
        other -> other
      end
    else
      _ -> {:error, :management_display_refused}
    end
  end

  defp source_identity("accept", source), do: StoredSources.share_identity(source)
  defp source_identity(_, _), do: {:error, :management_display_refused}

  defp review_display("forget", facts, wall) do
    with {:ok, display, challenge} <-
           Review.preview_management_display("forget", facts, System.system_time(:millisecond)),
         do: {:ok, display, challenge, wall}
  end

  defp review_display("accept", facts, wall) do
    with true <- Ipse.Session.PendingAcceptance.valid_facts?(facts),
         true <- System.system_time(:millisecond) < facts["valid_until_ms"],
         {:ok, display, challenge} <- Review.preview_display("accept", facts),
         display =
           "Historical pending candidate; current source eligibility requires revalidation before publication.\n" <>
             display,
         true <- byte_size(display) <= 8192 do
      {:ok, display, challenge, min(wall, facts["valid_until_ms"])}
    else
      _ -> {:error, :management_display_refused}
    end
  end

  defp review_display(command, facts, wall) when command in ~w(pin ordinary duration) do
    with true <-
           Ipse.Session.ManagedLifecycle.retention_review?(
             command,
             facts,
             System.system_time(:millisecond)
           ),
         {:ok, display, challenge} <-
           Review.preview_management_display(command, facts, System.system_time(:millisecond)) do
      deadline = facts["old_deadline_ms"]
      {:ok, display, challenge, if(is_nil(deadline), do: wall, else: min(wall, deadline))}
    else
      _ -> {:error, :management_display_refused}
    end
  end

  defp review_display(_, _, _), do: {:error, :management_display_refused}

  defp identity(cap) do
    case Transaction.retained_share_identity(cap) do
      {:ok, id} -> id
      _ -> nil
    end
  end

  defp run(owned, caps, ids, facts, display, overall_wall, helper, mode, source \\ {nil, nil}) do
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
      input? = match?({:input, _, _, _}, mode)

      {source_leases, source_ids, grouped?} =
        case source do
          {nil, nil} -> {[], [], false}
          {:historical_pending, :historical_pending} -> {[], [], false}
          {{:group, leases}, ids} when is_list(leases) and is_list(ids) -> {leases, ids, true}
          {lease, id} when is_reference(lease) and is_map(id) -> {[lease], [id], false}
        end

      count = 4 + length(source_leases)
      overall = owned.cli_control.overall_deadline

      port_remaining =
        if input?, do: overall - System.monotonic_time(:millisecond), else: remaining

      if port_remaining <= 0 or port_remaining > 120_000, do: throw(:expired)

      port =
        Port.open({:spawn_executable, String.to_charlist(helper)}, [
          :binary,
          :exit_status,
          :nouse_stdio,
          :hide,
          args: [
            "--operator-input",
            Integer.to_string(port_remaining),
            cond do
              grouped? -> "v11-management-source-group-input"
              source_leases != [] -> "v7-management-source-lease-input"
              input? -> "v6-management-lease-input"
              true -> "v5-management-lease-display"
            end
          ]
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
               Enum.map(1..(count + 2), fn _ ->
                 {:crypto.strong_rand_bytes(16), :crypto.strong_rand_bytes(32)}
               end),
             [cli_pair, journal_pair | lease_pairs] <- bindings,
             owners =
               entry(owned.cli_control.sender_pid, cli_pair, cli_pipe) <>
                 entry(owned.journal_control.sender_pid, journal_pair, journal_pipe),
             leases = [journal | ids] ++ source_ids,
             slots = [0, 0, 1, 2] ++ List.duplicate(0, length(source_leases)),
             operations =
               [transport, operation, operation, operation] ++
                 List.duplicate(operation, length(source_leases)),
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
             extra =
               if(input?,
                 do:
                   <<overall_wall::64,
                     native_clock + max(overall - System.monotonic_time(:millisecond), 0)::64>>,
                 else: <<>>
               ),
             body =
               <<operation::binary, count, owners::binary, manifest::binary, tty.major_device::64,
                 tty.inode::64, tty.minor_device::64, expiry::64, native_deadline::64,
                 extra::binary, byte_size(display)::32, display::binary>>,
             :ok <- send_frame(port, ?I, body),
             {:ok, <<^operation::binary-size(16), ^count>>} <-
               frame(port, ?H, owned.cli_owner, deadline),
             :ok <- transfer_controls(owned, pid, cli_pair, journal_pair),
             :ok <-
               export_all(
                 owned,
                 caps,
                 leases,
                 lease_pairs,
                 pid,
                 token,
                 operation,
                 deadline,
                 {source_leases, source_ids}
               ),
             {:ok, <<^operation::binary-size(16), ^count, _reader::32>>} <-
               frame(port, ?L, owned.cli_owner, deadline),
             :ok <- send_frame(port, ?A, body),
             {:ok, <<^operation::binary-size(16), ^count>>} <-
               frame(port, ?D, owned.cli_owner, deadline),
             true <- Port.command(port, <<?C, operation::binary>>, [:nosuspend]),
             {:reply, :ok} <-
               response(
                 Lock.request_share_settle(owned.guard, token, operation, deadline),
                 deadline
               ),
             :ok <- settle_all(caps, operation, deadline),
             :ok <- settle_sources(source_leases, operation, deadline),
             {:ok, <<^operation::binary-size(16), ^count>>} <-
               frame(port, ?C, owned.cli_owner, deadline) do
          complete_display(
            mode,
            port,
            owned,
            token,
            operation,
            facts,
            display,
            overall_wall,
            deadline
          )
        else
          _ -> {:unknown, :management_display_unconfirmed}
        end
      after
        if Port.info(port) != nil and not match?(%{port: ^port}, Process.get(@input_slot)),
          do: Port.close(port)
      end
    else
      _ -> {:unknown, :management_display_unconfirmed}
    end
  end

  defp complete_display(:display, port, owned, token, operation, facts, display, wall, deadline) do
    with :ok <- Resources.management_control_prepare_close(owned.cli_control),
         true <- Port.command(port, <<?U, operation::binary>>, [:nosuspend]),
         :ok <- await_exit(port, owned.cli_owner, deadline),
         :ok <- await_exit(owned.journal_control.port, owned.cli_owner, deadline),
         :ok <- Resources.management_control_await_closed(owned.cli_control),
         :ok <- Writer.thaw_share_barrier(owned.writer, token, operation),
         true <-
           System.monotonic_time(:millisecond) < deadline and
             System.system_time(:millisecond) < wall do
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
  end

  defp complete_display(
         {:input, command, challenge, ticket},
         port,
         owned,
         token,
         operation,
         facts,
         display,
         wall,
         deadline
       ) do
    with :ok <- Writer.thaw_share_barrier(owned.writer, token, operation),
         true <-
           System.monotonic_time(:millisecond) < deadline and
             System.system_time(:millisecond) < wall do
      ref = make_ref()

      Process.put(@input_slot, %{
        ref: ref,
        port: port,
        owned: owned,
        operation: operation,
        facts: facts,
        command: command,
        display_sha: JSON.sha256(display),
        challenge: challenge,
        wall: wall,
        overall: owned.cli_control.overall_deadline,
        ticket: ticket
      })

      {:ok, ref}
    else
      _ -> {:unknown, :management_display_unconfirmed}
    end
  end

  @doc false
  def finish_review(ref, facts), do: finish_review(ref, facts, "forget")

  def finish_review(ref, facts, command) when is_reference(ref) and is_map(facts) do
    case Process.delete(@input_slot) do
      %{ref: ^ref, facts: ^facts, command: ^command} = held ->
        finish_input(held)

      nil ->
        {:error, :management_input_refused}

      held ->
        close_input(held, false)
        {:error, :management_input_refused}
    end
  end

  def finish_review(_, _, _), do: {:error, :management_input_refused}

  defp finish_input(held) do
    %{port: port, owned: owned, operation: operation, overall: deadline, wall: wall} = held

    result =
      with nil <- Process.get({Ipse.Extension.ProjectIdentity, :lock_held}),
           nil <- Process.get({Ipse.Extension.Consent, :lock_held}),
           nil <- Process.get({Ipse.Extension.Collection, :lock_held}),
           true <- Process.alive?(owned.cli_owner),
           true <-
             System.monotonic_time(:millisecond) < deadline and
               System.system_time(:millisecond) < wall,
           :ok <- Resources.management_control_prepare_close(owned.cli_control),
           true <- Port.command(port, <<?U, operation::binary>>, [:nosuspend]),
           {:ok, text} <-
             input_frames(port, operation, owned.cli_owner, deadline, wall, <<>>, nil),
           permit_deadline = System.monotonic_time(:millisecond) + 30_000,
           :ok <- await_exit(port, owned.cli_owner, deadline),
           :ok <- await_exit(owned.journal_control.port, owned.cli_owner, deadline),
           :ok <- Resources.management_control_await_closed(owned.cli_control),
           true <-
             System.monotonic_time(:millisecond) < deadline and
               System.system_time(:millisecond) < wall and
               System.monotonic_time(:millisecond) < deadline do
        observation = %{
          "version" => 2,
          "event_id" => Base.encode16(operation, case: :lower),
          "display_sha256" => held.display_sha,
          "text_sha256" => JSON.sha256(text),
          "input_limit" => 1_048_576,
          "display_limit" => 16_777_216,
          "text" => text
        }

        {:ok, observation, held.challenge, permit_deadline}
      else
        _ -> {:unknown, :management_input_unconfirmed}
      end

    close_input(held, match?({:ok, _, _, _}, result))
    result
  rescue
    _ ->
      close_input(held, false)
      {:unknown, :management_input_unconfirmed}
  catch
    _, _ ->
      close_input(held, false)
      {:unknown, :management_input_unconfirmed}
  end

  defp close_input(%{port: port, ticket: ticket}, success?) do
    if Port.info(port), do: Port.close(port)
    Resources.closed(ticket, if(success?, do: :ok, else: {:error, :cleanup_unconfirmed}))
  end

  # Both frames may arrive fragmented or coalesced. Do not admit a partial,
  # oversized, out-of-order or trailing transcript as a native observation.
  defp input_frames(port, operation, owner, deadline, wall, buffer, text) do
    cond do
      System.monotonic_time(:millisecond) >= deadline or System.system_time(:millisecond) >= wall or
        not Process.alive?(owner) or byte_size(buffer) > 298 ->
        :error

      is_nil(text) and byte_size(buffer) >= 5 ->
        case buffer do
          <<?i, size::32, rest::binary>>
          when size >= 16 and size <= 272 and byte_size(rest) >= size ->
            <<body::binary-size(^size), tail::binary>> = rest

            case body do
              <<^operation::binary-size(16), input::binary>> ->
                input_frames(port, operation, owner, deadline, wall, tail, input)

              _ ->
                :error
            end

          <<?i, size::32, _::binary>> when size >= 16 and size <= 272 ->
            input_receive(port, operation, owner, deadline, wall, buffer, text)

          _ ->
            :error
        end

      not is_nil(text) and byte_size(buffer) >= 21 ->
        if buffer == <<?z, 16::32, operation::binary>>, do: {:ok, text}, else: :error

      true ->
        input_receive(port, operation, owner, deadline, wall, buffer, text)
    end
  end

  defp input_receive(port, operation, owner, deadline, wall, buffer, text) do
    receive do
      {^port, {:data, bytes}} ->
        input_frames(port, operation, owner, deadline, wall, buffer <> bytes, text)

      {^port, _} ->
        :error
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> :error
    end
  end

  defp transfer_controls(owned, pid, {cn, cs}, {jn, js}) do
    with :ok <- Resources.management_control_transfer(owned.cli_control, pid, cn, cs),
         :ok <- Management.management_journal_control_transfer(owned.journal_control, pid, jn, js),
         do: :ok
  end

  defp export_all(
         owned,
         caps,
         [journal | ids],
         [jp | pairs],
         pid,
         token,
         operation,
         deadline,
         source
       ) do
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
      with :ok <-
             Enum.zip([caps, ids, pairs])
             |> Enum.reduce_while(:ok, fn {cap, id, pair}, :ok ->
               case Transaction.retained_share_export(
                      cap,
                      operation,
                      recipient(pid, pair, id),
                      deadline
                    ) do
                 :ok -> {:cont, :ok}
                 _ -> {:halt, :error}
               end
             end),
           :ok <- export_sources(source, Enum.drop(pairs, length(caps)), pid, operation, deadline) do
        :ok
      end
    else
      _ -> :error
    end
  end

  defp export_sources({leases, ids}, pairs, pid, operation, deadline) do
    if length(leases) == length(ids) and length(ids) == length(pairs) do
      Enum.zip([leases, ids, pairs])
      |> Enum.reduce_while(:ok, fn {lease, identity, pair}, :ok ->
        case StoredSources.share_export(
               lease,
               operation,
               recipient(pid, pair, identity),
               deadline
             ) do
          :ok -> {:cont, :ok}
          _ -> {:halt, :error}
        end
      end)
    else
      :error
    end
  end

  defp settle_sources(leases, operation, deadline) do
    Enum.reduce_while(leases, :ok, fn lease, :ok ->
      case StoredSources.share_settle(lease, operation, deadline) do
        :ok -> {:cont, :ok}
        _ -> {:halt, :error}
      end
    end)
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
