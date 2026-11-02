defmodule Ipse.Runner.SessionSource do
  @moduledoc false
  alias Ipse.Extension.Host
  alias Ipse.Runner.Transaction
  alias Ipse.Session.Resources
  @unknown {:unknown, :session_source_ownership_unconfirmed}

  def with_supersession(cap, context, intent, sha, leases, fun) when is_function(fun, 0) do
    with_sources(cap, context, leases, fun, fn ->
      Host.begin_supersession_source_share(context.owner, context.job_ref, intent, sha)
    end)
  end

  def with_supersession(_, _, _, _, _, _), do: @unknown

  def with_worker_input(cap, context, intent, sha, leases, proofs, wall, fun)
      when is_function(fun, 0) do
    with_sources(cap, context, leases, fun, fn ->
      Host.begin_worker_input_share(context.owner, context.job_ref, intent, sha, proofs, wall)
    end)
  end

  def with_worker_input(_, _, _, _, _, _, _, _), do: @unknown

  def with_capture(cap, context, intent, sha, leases, proofs, wall, fun)
      when is_function(fun, 0) do
    with_sources(cap, context, leases, fun, fn ->
      Host.begin_capture_source_share(context.owner, context.job_ref, intent, sha, proofs, wall)
    end)
  end

  defp with_sources(cap, context, leases, fun, begin_share) do
    with %Transaction.Capability{owner: owner, depth: 3} <- cap,
         true <- owner == self() and Resources.active?(),
         {:ok, %{pid: recipient}} <- Transaction.retained_share_identity(cap),
         {:ok, ticket} <- Resources.register(:lock),
         {:ok, binding, transport, snapshot, controls} <-
           begin_share.() do
      result =
        try do
          with true <- snapshot.session_id === context.session_id,
               true <-
                 bound_leases?(
                   leases,
                   controls[:original_source_proofs],
                   snapshot[:inactive_source_locks]
                 ),
               :ok <- import_writer(cap, context, binding, recipient, controls),
               :ok <- import_session(cap, context, binding, recipient, controls),
               :ok <- import_source(cap, context, binding, recipient, transport, controls) do
            result =
              if leases == [],
                do: fun.(),
                else: Transaction.with_source_leases(cap, Enum.map(leases, & &1.token), fun)

            case settle(cap, context, binding, transport, controls) do
              :ok -> result
              _ -> @unknown
            end
          else
            _ -> @unknown
          end
        rescue
          _ -> @unknown
        catch
          _, _ -> @unknown
        end

      if Port.info(controls.host_port),
        do:
          Host.abort_controlled_session_share(
            context.owner,
            context.job_ref,
            binding,
            controls.host_port
          )

      if match?({:unknown, _}, result), do: Transaction.abort_owned(cap)

      Resources.closed(
        ticket,
        if(match?({:unknown, _}, result), do: {:error, :cleanup_unconfirmed}, else: :ok)
      )

      result
    else
      _ ->
        Transaction.abort_owned(cap)
        @unknown
    end
  rescue
    _ -> @unknown
  catch
    _, _ -> @unknown
  end

  defp bound_leases?(leases, proofs, locks) when is_list(leases) and is_list(proofs) do
    groups = Enum.group_by(proofs, & &1["session_id"])

    length(leases) == map_size(groups) and
      Enum.sort(Enum.map(leases, & &1.session_id)) === Enum.sort(Map.keys(groups)) and
      Enum.all?(leases, fn %{session_id: id, token: token} ->
        case Ipse.Session.StoredSources.share_verified_identity(token, Map.fetch!(groups, id)) do
          {:ok, %{identity: identity}} ->
            is_nil(locks) or
              %{session_id: id, device: identity.device, inode: identity.inode} in locks

          _ ->
            false
        end
      end) and (is_nil(locks) or length(locks) == length(leases))
  end

  defp bound_leases?(_, _, _), do: false

  defp import_writer(cap, c, binding, recipient, controls) do
    with {:ok, identity} <- Host.session_share_writer_open(c.owner, c.job_ref, binding) do
      {name, secret} = pair()

      request =
        :gen_server.send_request(
          cap.controller,
          {:writer_control_import, cap, controls.operation, entry(identity, name, secret),
           controls.deadline}
        )

      with :ok <-
             Host.session_share_writer_transfer(
               c.owner,
               c.job_ref,
               binding,
               recipient,
               name,
               secret
             ),
           {:reply, :ok} <- response(request, controls.deadline),
           do: :ok
    end
  end

  defp import_session(cap, c, binding, recipient, controls) do
    with {:ok, stat} <- File.stat("/proc/#{controls.session_pid}/fd/0"),
         true <- Bitwise.band(stat.mode, 0xF000) == 0x1000 and stat.inode > 0 do
      identity = %{pid: controls.session_pid, device: stat.major_device, inode: stat.inode}
      {name, secret} = pair()

      request =
        :gen_server.send_request(
          cap.controller,
          {:session_control_import, cap, controls.operation, entry(identity, name, secret),
           controls.deadline}
        )

      with :ok <-
             Host.configure_session_control(c.owner, c.job_ref, binding, recipient, name, secret),
           :ok <- await_owner(c.owner, binding, :transferred, controls.deadline),
           {:reply, :ok} <- response(request, controls.deadline),
           do: :ok
    end
  end

  defp import_source(cap, c, binding, recipient, transport, controls) do
    with {:ok, identity} <- Host.session_share_identity(c.owner, c.job_ref, binding) do
      {name, secret} = pair()

      request =
        :gen_server.send_request(
          cap.controller,
          {:source_import, cap, transport, entry(identity, name, secret), controls.deadline}
        )

      target = %{identity | pid: recipient}

      with :ok <-
             Host.export_session_share(c.owner, c.job_ref, binding, entry(target, name, secret)),
           {:reply, :ok} <- response(request, controls.deadline),
           do: :ok
    end
  end

  defp settle(cap, c, binding, transport, controls) do
    deadline = controls.deadline
    request = :gen_server.send_request(cap.controller, {:source_close, cap, transport, deadline})

    with :ok <- Host.settle_session_share(c.owner, c.job_ref, binding),
         {:reply, :ok} <- response(request, deadline),
         :ok <- Host.session_share_writer_prepare_close(c.owner, c.job_ref, binding),
         :ok <- Host.prepare_transaction_share_close(c.owner, c.job_ref, binding),
         :ok <-
           GenServer.call(
             cap.controller,
             {:session_control_close, cap, deadline},
             remaining(deadline)
           ),
         :ok <- await_owner(c.owner, binding, :closed, deadline),
         :ok <-
           GenServer.call(
             cap.controller,
             {:writer_control_close, cap, deadline},
             remaining(deadline)
           ),
         :ok <- Host.session_share_writer_close(c.owner, c.job_ref, binding),
         :ok <-
           Host.finish_controlled_session_share(c.owner, c.job_ref, binding, controls.host_port),
         do: :ok
  end

  defp await_owner(owner, binding, phase, deadline) do
    receive do
      {:session_owner_control, ^binding, ^phase} ->
        if Process.alive?(owner) and remaining(deadline) > 0, do: :ok, else: @unknown
    after
      remaining(deadline) -> @unknown
    end
  end

  defp response(request, deadline), do: :gen_server.receive_response(request, remaining(deadline))
  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
  defp pair, do: {:crypto.strong_rand_bytes(16), :crypto.strong_rand_bytes(32)}

  defp entry(identity, name, secret),
    do:
      <<identity.pid::32, name::binary, secret::binary, identity.device::64, identity.inode::64>>
end
