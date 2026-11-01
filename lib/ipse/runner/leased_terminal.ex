defmodule Ipse.Runner.LeasedTerminal do
  @moduledoc false
  # Session-owned approval display and private fixed-text controls share the
  # native transport. Workers cannot select terminal payloads or lease identities.
  alias Ipse.Extension.Host
  alias Ipse.Runner.Transaction
  alias Ipse.Session.Resources
  @payload "SYNTHETIC_LEASED_DISPLAY"
  @review_payload "Synthetic grouped review.\nType pin 0123456789abcdef to confirm, or anything else to cancel.\n> "
  @approval_slot {__MODULE__, :approval}

  @doc false
  def begin_approval(owner, job, intent, held, cwd) do
    proofs = Enum.reject(held.source_proofs, &(&1["session_id"] == intent["session_id"]))
    caps = [held.identity, held.consent, held.collection]

    with nil <- Process.get(@approval_slot),
         true <- held.owner == self(),
         true <- Process.get({Ipse.Extension.ProjectIdentity, :lock_held}) === true,
         true <- Process.get({Ipse.Extension.Consent, :lock_held}) === held.consent,
         true <- Process.get({Ipse.Extension.Collection, :lock_held}) === held.collection,
         {:ok, ^caps} <- Transaction.retained_share_stack(),
         {:ok, sources} <- bound_source_identities(held.source_leases, proofs),
         {:ok, journals} <- bound_journal_identities(held.journal_leases),
         true <- length(sources) + length(journals) <= 128 do
      exercise_mode(
        owner,
        job,
        intent,
        caps,
        cwd,
        {:approval, sources ++ journals, held.source_proofs, held.deadline_ms}
      )
    else
      _ -> {:error, :cleanup_unconfirmed}
    end
  end

  @doc false
  def begin_relation(owner, job, intent, held, cwd, sha) do
    proofs = Enum.reject(held.source_proofs, &(&1["session_id"] == held.session_id))
    caps = [held.identity, held.consent, held.collection]

    with nil <- Process.get(@approval_slot),
         true <- held.owner == self(),
         true <- Process.get({Ipse.Extension.ProjectIdentity, :lock_held}) === true,
         true <- Process.get({Ipse.Extension.Consent, :lock_held}) === held.consent,
         true <- Process.get({Ipse.Extension.Collection, :lock_held}) === held.collection,
         {:ok, ^caps} <- Transaction.retained_share_stack(),
         {:ok, sources} <- bound_source_identities(held.source_leases, proofs) do
      exercise_mode(
        owner,
        job,
        intent,
        caps,
        cwd,
        {:relation, sources, sha, held.source_proofs, held.deadline_ms}
      )
    else
      _ -> {:error, :cleanup_unconfirmed}
    end
  end

  @doc false
  def finish_approval(handle, token), do: finish_input(handle, {:approval, token})

  @doc false
  def finish_relation(handle, facts, command),
    do: finish_input(handle, {:relation, facts, command})

  defp finish_input(handle, expected) do
    case Process.get(@approval_slot) do
      %{handle: ^handle, owner_process: owner} = state when owner == self() ->
        Process.delete(@approval_slot)

        try do
          with true <- not Process.get({Ipse.Extension.ProjectIdentity, :lock_held}, false),
               nil <- Process.get({Ipse.Extension.Consent, :lock_held}),
               nil <- Process.get({Ipse.Extension.Collection, :lock_held}),
               true <- input_binding?(state, expected),
               true <-
                 Port.command(state.port, <<?U, state.controls.operation::binary>>, [:nosuspend]),
               {:ok, text} <-
                 approval_input(
                   state.port,
                   state.owner,
                   state.controls.overall_deadline,
                   state.controls.operation,
                   <<>>
                 ),
               permit_deadline = System.monotonic_time(:millisecond) + 30_000,
               :ok <- await_exit(state.port, state.owner, state.controls.overall_deadline),
               :ok <-
                 await_exit(
                   state.controls.host_port,
                   state.owner,
                   state.controls.overall_deadline
                 ),
               :ok <-
                 await_session_closed(state.owner, state.cap, state.controls.overall_deadline),
               :ok <- Host.finish_session_share(state.owner, state.job, state.cap) do
            Resources.closed(state.ticket, :ok)

            input_result(state, expected, text, permit_deadline)
          else
            _ ->
              Resources.closed(state.ticket, {:error, :cleanup_unconfirmed})
              {:error, :cleanup_unconfirmed}
          end
        after
          if Port.info(state.port), do: Port.close(state.port)

          if Port.info(state.controls.host_port),
            do: Ipse.Runner.close_owner_control(state.controls.host_port)
        end

      _ ->
        {:error, :cleanup_unconfirmed}
    end
  end

  defp input_binding?(%{kind: :approval} = state, {:approval, token}),
    do: Ipse.JSON.sha256("allow " <> token) == state.allow_sha256

  defp input_binding?(%{kind: :relation, controls: controls}, {:relation, facts, command}),
    do: controls.review_facts === facts and controls.review_command === command

  defp input_binding?(_, _), do: false

  defp input_result(_, {:approval, token}, text, _deadline) do
    choice =
      case text do
        "/cancel" -> :cancel
        "/exit" -> :exit
        _ -> text == "allow " <> token
      end

    {:ok, choice}
  end

  defp input_result(state, {:relation, _, _}, text, deadline) do
    observation = %{
      "version" => 2,
      "event_id" => Base.encode16(state.controls.operation, case: :lower),
      "display_sha256" => Ipse.JSON.sha256(state.controls.payload),
      "text_sha256" => Ipse.JSON.sha256(text),
      "input_limit" => 1_048_576,
      "display_limit" => 16_777_216,
      "text" => text
    }

    {:ok, observation, state.controls.review_challenge, deadline}
  end

  def exercise(owner, job, intent, caps, cwd)
      when is_pid(owner) and is_reference(job) and is_map(intent) and is_list(caps) and
             is_binary(cwd),
      do: exercise_mode(owner, job, intent, caps, cwd, :legacy)

  def exercise(_, _, _, _, _), do: {:error, :cleanup_unconfirmed}

  @doc false
  def exercise_notice(owner, job, intent, caps, cwd)
      when is_pid(owner) and is_reference(job) and is_map(intent) and is_list(caps) and
             is_binary(cwd),
      do: exercise_mode(owner, job, intent, caps, cwd, :synthetic_notice)

  def exercise_notice(_, _, _, _, _), do: {:error, :cleanup_unconfirmed}

  @doc false
  def exercise_group(owner, job, intent, caps, cwd, tokens)
      when is_pid(owner) and is_reference(job) and is_map(intent) and is_list(caps) and
             is_binary(cwd) and is_list(tokens) do
    with true <- length(tokens) in 1..128,
         true <- Enum.all?(tokens, &is_reference/1),
         true <- length(Enum.uniq(tokens)) == length(tokens),
         {:ok, sources} <- source_identities(tokens) do
      exercise_mode(owner, job, intent, caps, cwd, {:group, sources})
    else
      _ -> {:error, :cleanup_unconfirmed}
    end
  end

  def exercise_group(_, _, _, _, _, _), do: {:error, :cleanup_unconfirmed}

  @doc false
  def exercise_review(owner, job, intent, caps, cwd, leases, proofs)
      when is_pid(owner) and is_reference(job) and is_map(intent) and is_list(caps) and
             is_binary(cwd) and is_list(leases) and is_list(proofs) do
    with {:ok, sources} <- bound_source_identities(leases, proofs) do
      exercise_mode(owner, job, intent, caps, cwd, {:review_group, sources})
    else
      _ -> {:error, :cleanup_unconfirmed}
    end
  end

  def exercise_review(_, _, _, _, _, _, _), do: {:error, :cleanup_unconfirmed}

  # Fixed-text bridge for a Session-owned pre-review relation. The real
  # protected display and cross-process publisher handoff remain separate.
  @doc false
  def exercise_supersession_review(owner, job, intent, caps, cwd, leases, proofs, sha)
      when is_pid(owner) and is_reference(job) and is_map(intent) and is_list(caps) and
             is_binary(cwd) and is_list(leases) and is_list(proofs) do
    with true <- Ipse.JSON.sha256?(sha),
         {:ok, sources} <- bound_source_identities(leases, proofs) do
      exercise_mode(
        owner,
        job,
        intent,
        caps,
        cwd,
        {:supersession_review_group, sources, sha, Ipse.JSON.digest([proofs])}
      )
    else
      _ -> {:error, :cleanup_unconfirmed}
    end
  end

  def exercise_supersession_review(_, _, _, _, _, _, _, _),
    do: {:error, :cleanup_unconfirmed}

  defp bound_source_identities(leases, proofs) do
    groups = Enum.group_by(proofs, & &1["session_id"])
    ids = Enum.map(leases, & &1[:session_id])
    tokens = Enum.map(leases, & &1[:token])

    with true <- length(proofs) in 0..128 and length(Enum.uniq(proofs)) == length(proofs),
         true <- length(leases) in 0..128 and length(Enum.uniq(ids)) == length(ids),
         true <- Enum.sort(ids) === Enum.sort(Map.keys(groups)),
         true <-
           Enum.all?(tokens, &is_reference/1) and length(Enum.uniq(tokens)) == length(tokens) do
      Enum.reduce_while(leases, {:ok, []}, fn %{session_id: id, token: token}, {:ok, acc} ->
        case Ipse.Session.StoredSources.share_verified_identity(token, Map.fetch!(groups, id)) do
          {:ok, %{session_id: ^id, identity: identity}} ->
            {:cont, {:ok, [{token, identity} | acc]}}

          _ ->
            {:halt, {:error, :cleanup_unconfirmed}}
        end
      end)
      |> case do
        {:ok, sources} -> {:ok, Enum.reverse(sources)}
        other -> other
      end
    else
      _ -> {:error, :cleanup_unconfirmed}
    end
  rescue
    _ -> {:error, :cleanup_unconfirmed}
  end

  defp source_identities(tokens) do
    Enum.reduce_while(tokens, {:ok, []}, fn token, {:ok, acc} ->
      case Ipse.Session.StoredSources.share_identity(token) do
        {:ok, id} -> {:cont, {:ok, [{token, id} | acc]}}
        _ -> {:halt, {:error, :cleanup_unconfirmed}}
      end
    end)
    |> case do
      {:ok, sources} -> {:ok, Enum.reverse(sources)}
      other -> other
    end
  end

  defp bound_journal_identities(leases) when is_list(leases) and length(leases) <= 128 do
    tokens = Enum.map(leases, & &1[:token])

    with true <- Enum.all?(tokens, &is_reference/1),
         true <- length(Enum.uniq(tokens)) == length(tokens) do
      Enum.reduce_while(leases, {:ok, []}, fn %{token: token, link: link}, {:ok, acc} ->
        case Ipse.Session.PendingAcceptance.journal_share_verified_identity(token, link) do
          {:ok, identity} ->
            {:cont, {:ok, acc ++ [{{:acceptance_journal, token}, identity}]}}

          _ ->
            {:halt, {:error, :cleanup_unconfirmed}}
        end
      end)
    else
      _ -> {:error, :cleanup_unconfirmed}
    end
  rescue
    _ -> {:error, :cleanup_unconfirmed}
  end

  defp bound_journal_identities(_), do: {:error, :cleanup_unconfirmed}

  defp exercise_mode(owner, job, intent, caps, cwd, mode) do
    with [a, b, c] <- caps,
         [%{slot: 0}, %{slot: 1}, %{slot: 2}] = identities <- Enum.map([a, b, c], &identity/1),
         true <- length(Enum.uniq(Enum.map(identities, & &1.pid))) == 1,
         {:ok, helper} <- Ipse.Runner.protected_helper(cwd),
         {:ok, ticket} <- Resources.register(:lock) do
      mode =
        if match?({:approval, _, _, _}, mode) or match?({:relation, _, _, _, _}, mode),
          do: Tuple.insert_at(mode, tuple_size(mode), ticket),
          else: mode

      result =
        try do
          begin =
            cond do
              approval_mode?(mode) ->
                Host.begin_approval_share(owner, job, intent, elem(mode, 2), elem(mode, 3))

              relation_mode?(mode) ->
                Host.begin_relation_share(
                  owner,
                  job,
                  intent,
                  elem(mode, 2),
                  elem(mode, 3),
                  elem(mode, 4)
                )

              mode == :synthetic_notice ->
                Host.begin_synthetic_notice_share(owner, job, intent)

              match?({:supersession_review_group, _, _, _}, mode) ->
                Host.begin_synthetic_supersession_review_share(owner, job, intent, elem(mode, 2))

              match?({:review_group, _}, mode) ->
                Host.begin_synthetic_review_share(owner, job, intent)

              true ->
                Host.begin_controlled_session_share(owner, job, intent)
            end

          case begin do
            {:ok, cap, transport, _snapshot, controls} ->
              run(owner, job, cap, transport, controls, caps, identities, helper, mode)

            _ ->
              {:error, :cleanup_unconfirmed}
          end
        catch
          _, _ -> {:error, :cleanup_unconfirmed}
        end

      unless match?({:ok, {:leased_approval, _}}, result),
        do:
          Resources.closed(
            ticket,
            if(result == :ok, do: :ok, else: {:error, :cleanup_unconfirmed})
          )

      result
    else
      _ -> {:error, :cleanup_unconfirmed}
    end
  rescue
    _ -> {:error, :cleanup_unconfirmed}
  end

  defp identity(cap) do
    case Transaction.retained_share_identity(cap) do
      {:ok, identity} -> identity
      _ -> nil
    end
  end

  defp run(owner, job, cap, transport, controls, caps, identities, helper, mode) do
    try do
      if relation_sources_match?(mode, controls),
        do: run_opened(owner, job, cap, transport, controls, caps, identities, helper, mode),
        else: {:error, :cleanup_unconfirmed}
    after
      if not is_nil(Port.info(controls.host_port)) and
           not retained_approval_port?(controls.host_port, :host),
         do: Host.abort_controlled_session_share(owner, job, cap, controls.host_port)
    end
  catch
    _, _ -> {:error, :cleanup_unconfirmed}
  end

  defp relation_sources_match?({:supersession_review_group, _, _, digest}, controls),
    do: controls[:relation_inactive_sha256] === digest

  defp relation_sources_match?({:relation, _, _, proofs, _, _}, controls) do
    inactive = Enum.reject(proofs, &(&1["session_id"] == controls.review_session_id))
    controls[:relation_inactive_sha256] === Ipse.JSON.digest([inactive])
  end

  defp relation_sources_match?(_, _), do: true

  defp run_opened(owner, job, cap, transport, controls, caps, identities, helper, mode) do
    deadline = controls.deadline
    remaining = min(deadline - System.monotonic_time(:millisecond), 5_000)
    if remaining <= 0, do: throw(:expired)

    port =
      if mode == :synthetic_notice or review_mode?(mode) do
        {:ok, port} = Host.spawn_synthetic_notice_terminal(owner, job, cap)
        port
      else
        Port.open({:spawn_executable, String.to_charlist(helper)}, [
          :binary,
          :exit_status,
          :nouse_stdio,
          :hide,
          args: [
            "--operator-input",
            Integer.to_string(remaining),
            if(match?({:group, _}, mode),
              do: "v10-synthetic-source-group-display",
              else: "v4-synthetic-lease-display"
            )
          ]
        ])
      end

    try do
      review? = review_mode?(mode)

      with {:ok, native_clock} <- review_clock(port, owner, deadline, review?),
           {:os_pid, pid} when is_integer(pid) and pid > 0 <- Port.info(port, :os_pid),
           {:os_pid, host_pid} <- Port.info(controls.host_port, :os_pid),
           {:ok, session_identity} <- Host.session_share_identity(owner, job, cap),
           {:ok, session_control} <- pipe_identity(controls.session_pid),
           {:ok, host_control} <- pipe_identity(host_pid),
           {:ok, tty} <- File.stat("/proc/#{pid}/fd/0"),
           true <- tty.type == :device,
           sources = if(match?({:group, _}, mode) or review?, do: elem(mode, 1), else: []),
           count = 4 + length(sources),
           bindings =
             Enum.map(1..(count + 2), fn _ ->
               {:crypto.strong_rand_bytes(16), :crypto.strong_rand_bytes(32)}
             end),
           [session_pair, host_pair | lease_pairs] <- bindings,
           session_entry = entry(controls.session_pid, session_pair, session_control),
           host_entry = entry(host_pid, host_pair, host_control),
           leases = [session_identity | identities] ++ Enum.map(sources, &elem(&1, 1)),
           slots = [0, 0, 1, 2] ++ List.duplicate(0, length(sources)),
           operations =
             [transport, controls.operation, controls.operation, controls.operation] ++
               List.duplicate(controls.operation, length(sources)),
           manifest =
             Enum.zip([slots, operations, leases, lease_pairs])
             |> Enum.map(fn {slot, operation, id, pair} ->
               <<slot, operation::binary, entry(id.pid, pair, id)::binary>>
             end)
             |> IO.iodata_to_binary(),
           expiry =
             System.system_time(:millisecond) +
               max(deadline - System.monotonic_time(:millisecond), 0),
           expiry =
             if(mode == :synthetic_notice or review?, do: controls.wall_deadline, else: expiry),
           payload =
             if(approval_mode?(mode) or relation_mode?(mode),
               do: controls.payload,
               else: if(review?, do: @review_payload, else: @payload)
             ),
           extra =
             if(review?,
               do:
                 <<native_clock + max(deadline - System.monotonic_time(:millisecond), 0)::64,
                   controls.overall_wall::64,
                   native_clock +
                     max(controls.overall_deadline - System.monotonic_time(:millisecond), 0)::64>>,
               else: <<>>
             ),
           prefix =
             <<controls.operation::binary, count, session_entry::binary, host_entry::binary,
               manifest::binary, tty.major_device::64, tty.inode::64, tty.minor_device::64,
               expiry::64, extra::binary>>,
           body = <<prefix::binary, byte_size(payload)::32, payload::binary>>,
           :ok <-
             if(review?,
               do: Host.send_synthetic_review_manifest(owner, job, cap, prefix),
               else: send_frame(port, ?I, body)
             ),
           {:ok, <<operation::binary-size(16), ^count>>} <- frame(port, ?H, owner, deadline),
           true <- operation == controls.operation,
           :ok <-
             configure_controls(owner, job, cap, controls, pid, session_pair, host_pair, deadline),
           :ok <- export_all(owner, job, cap, controls, pid, caps, leases, lease_pairs, deadline),
           :ok <-
             export_sources(sources, Enum.drop(lease_pairs, 4), pid, controls.operation, deadline),
           {:ok, <<operation::binary-size(16), ^count, _reader::32>>} <-
             frame(port, ?L, owner, deadline),
           true <- operation == controls.operation,
           :ok <- send_frame(port, ?A, body),
           {:ok, <<operation::binary-size(16), ^count>>} <- frame(port, ?D, owner, deadline),
           true <- operation == controls.operation,
           true <- Port.command(port, <<?C, controls.operation::binary>>, [:nosuspend]),
           :ok <- Host.settle_session_share(owner, job, cap),
           :ok <-
             Enum.reduce_while(caps, :ok, fn tx, :ok ->
               case Transaction.retained_share_settle(tx, controls.operation, deadline) do
                 :ok -> {:cont, :ok}
                 _ -> {:halt, :error}
               end
             end),
           :ok <- settle_sources(sources, controls.operation, deadline),
           {:ok, <<operation::binary-size(16), ^count>>} <- frame(port, ?C, owner, deadline),
           true <- operation == controls.operation,
           :ok <-
             if(mode == :synthetic_notice or review?,
               do: await_session_notice(owner, cap, deadline),
               else: :ok
             ),
           result <- complete_review(mode, owner, job, cap, controls, port, deadline),
           true <-
             result == :ok or
               ((approval_mode?(mode) or relation_mode?(mode)) and
                  match?({:ok, {:leased_approval, _}}, result)) do
        result
      else
        _ -> {:error, :cleanup_unconfirmed}
      end
    after
      if not is_nil(Port.info(port)) and not retained_approval_port?(port, :terminal),
        do: Port.close(port)
    end
  end

  defp review_mode?({:review_group, _}), do: true
  defp review_mode?({:supersession_review_group, _, _, _}), do: true
  defp review_mode?({:approval, _, _, _, _}), do: true
  defp review_mode?({:relation, _, _, _, _, _}), do: true
  defp review_mode?(_), do: false

  defp approval_mode?({:approval, _, _, _, _}), do: true
  defp approval_mode?(_), do: false

  defp relation_mode?({:relation, _, _, _, _, _}), do: true
  defp relation_mode?(_), do: false

  defp retained_approval_port?(port, kind) do
    case Process.get(@approval_slot) do
      %{port: ^port} when kind == :terminal -> true
      %{controls: %{host_port: ^port}} when kind == :host -> true
      _ -> false
    end
  end

  defp review_clock(_port, _owner, _deadline, false), do: {:ok, nil}

  defp review_clock(port, owner, deadline, true) do
    with {:ok, <<clock::64>>} <- frame(port, ?R, owner, deadline), do: {:ok, clock}
  end

  defp complete_review({:review_group, _}, owner, job, cap, controls, port, _deadline) do
    with :ok <- Host.thaw_synthetic_review(owner, job, cap, port),
         true <- Port.command(port, <<?U, controls.operation::binary>>, [:nosuspend]),
         :ok <- review_input(port, owner, controls.overall_deadline, controls.operation, <<>>),
         :ok <- await_exit(port, owner, controls.overall_deadline),
         :ok <- await_exit(controls.host_port, owner, controls.overall_deadline),
         :ok <- await_session_closed(owner, cap, controls.overall_deadline),
         :ok <- Host.finish_session_share(owner, job, cap) do
      :ok
    else
      _ -> :error
    end
  end

  defp complete_review({:approval, _, _, _, ticket}, owner, job, cap, controls, port, _deadline),
    do: retain_input(:approval, ticket, owner, job, cap, controls, port)

  defp complete_review(
         {:relation, _, _, _, _, ticket},
         owner,
         job,
         cap,
         controls,
         port,
         _deadline
       ),
       do: retain_input(:relation, ticket, owner, job, cap, controls, port)

  defp complete_review(
         {:supersession_review_group, sources, _, _},
         owner,
         job,
         cap,
         controls,
         port,
         deadline
       ),
       do: complete_review({:review_group, sources}, owner, job, cap, controls, port, deadline)

  defp complete_review(_, owner, job, cap, controls, port, deadline) do
    with :ok <- Host.prepare_terminal_share_close(owner, job, cap, port),
         true <- Port.command(port, <<?U, controls.operation::binary>>, [:nosuspend]),
         :ok <- await_exit(port, owner, deadline),
         :ok <- await_exit(controls.host_port, owner, deadline),
         :ok <- await_session_closed(owner, cap, deadline),
         :ok <- Host.finish_session_share(owner, job, cap),
         do: :ok
  end

  defp retain_input(kind, ticket, owner, job, cap, controls, port) do
    with :ok <- Host.thaw_synthetic_review(owner, job, cap, port) do
      handle = {:leased_approval, make_ref()}

      Process.put(@approval_slot, %{
        handle: handle,
        owner_process: self(),
        owner: owner,
        job: job,
        cap: cap,
        controls: controls,
        port: port,
        ticket: ticket,
        kind: kind,
        allow_sha256: controls[:allow_sha256]
      })

      {:ok, handle}
    else
      _ -> :error
    end
  end

  defp approval_input(port, owner, deadline, operation, buffer) do
    case buffer do
      <<?i, size::32, ^operation::binary-size(16), text::binary-size(size - 16), ?z, 16::32,
        ^operation::binary-size(16)>>
      when size in 16..144 ->
        if Process.alive?(owner) and System.monotonic_time(:millisecond) < deadline,
          do: {:ok, text},
          else: :error

      _ when byte_size(buffer) > 170 ->
        :error

      _ ->
        receive do
          {^port, {:data, bytes}} ->
            approval_input(port, owner, deadline, operation, buffer <> bytes)

          {^port, _} ->
            :error
        after
          max(deadline - System.monotonic_time(:millisecond), 0) -> :error
        end
    end
  end

  defp review_input(port, owner, deadline, operation, buffer) do
    expected =
      <<?i, 36::32, operation::binary, "pin 0123456789abcdef", ?z, 16::32, operation::binary>>

    cond do
      System.monotonic_time(:millisecond) >= deadline or not Process.alive?(owner) ->
        :error

      buffer == expected ->
        :ok

      byte_size(buffer) >= byte_size(expected) or
          binary_part(expected, 0, byte_size(buffer)) != buffer ->
        :error

      true ->
        receive do
          {^port, {:data, bytes}} ->
            review_input(port, owner, deadline, operation, buffer <> bytes)

          {^port, _} ->
            :error
        after
          max(deadline - System.monotonic_time(:millisecond), 0) -> :error
        end
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

  defp await_session_closed(owner, cap, deadline) do
    ref = Process.monitor(owner)

    try do
      receive do
        {:session_owner_control, ^cap, :closed} -> :ok
        {:DOWN, ^ref, :process, _, _} -> :error
      after
        max(deadline - System.monotonic_time(:millisecond), 0) -> :error
      end
    after
      Process.demonitor(ref, [:flush])
    end
  end

  defp await_session_notice(owner, cap, deadline) do
    ref = Process.monitor(owner)

    try do
      receive do
        {:session_owner_control, ^cap, :notice} -> :ok
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

  defp export_sources(sources, pairs, pid, operation, deadline) do
    if length(sources) == length(pairs) do
      Enum.zip(sources, pairs)
      |> Enum.reduce_while(:ok, fn {{token, id}, pair}, :ok ->
        result =
          case token do
            {:acceptance_journal, journal} ->
              Ipse.Session.PendingAcceptance.journal_share_export(
                journal,
                operation,
                recipient(pid, pair, id),
                deadline
              )

            source when is_reference(source) ->
              Ipse.Session.StoredSources.share_export(
                source,
                operation,
                recipient(pid, pair, id),
                deadline
              )
          end

        case result do
          :ok -> {:cont, :ok}
          _ -> {:halt, :error}
        end
      end)
    else
      :error
    end
  end

  defp settle_sources(sources, operation, deadline) do
    Enum.reduce_while(sources, :ok, fn {token, _}, :ok ->
      result =
        case token do
          {:acceptance_journal, journal} ->
            Ipse.Session.PendingAcceptance.journal_share_settle(journal, operation, deadline)

          source when is_reference(source) ->
            Ipse.Session.StoredSources.share_settle(source, operation, deadline)
        end

      case result do
        :ok -> {:cont, :ok}
        _ -> {:halt, :error}
      end
    end)
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
