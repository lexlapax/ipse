defmodule Ipse.Test.SessionTransactionBridge do
  import ExUnit.Assertions
  alias Ipse.Extension.Host
  alias Ipse.Runner.Transaction, as: T

  def run(owner, job, intent, paths, hold \\ false) do
    caps =
      Enum.map(paths, fn path ->
        {:ok, cap} = T.acquire(path)
        cap
      end)

    tx = List.last(caps)
    root = Path.dirname(List.last(paths))
    old = ".pending-" <> Ipse.Usage.id()
    stage = ".pending-" <> Ipse.Usage.id()
    assert :ok = T.stage(tx, ".", [{old, "old"}])
    assert :ok = T.switch(tx, old, "root.json")
    assert :ok = T.stage(tx, ".", [{stage, "new"}])

    {:ok, capability, transport, snapshot, controls} =
      case hold do
        {:source, proofs} ->
          Host.begin_synthetic_source_share(owner, job, intent, proofs)

        {:source_hold, proofs} ->
          Host.begin_synthetic_source_share(owner, job, intent, proofs)

        {:source_group, proofs, _} ->
          Host.begin_synthetic_source_share(owner, job, intent, proofs)

        {:source_group_loss, proofs, _} ->
          Host.begin_synthetic_source_share(owner, job, intent, proofs)

        _ ->
          Host.begin_controlled_session_share(owner, job, intent)
      end

    if is_tuple(hold) and elem(hold, 0) in [:source, :source_hold] do
      {_, proofs} = hold
      assert Enum.map(snapshot.verified_sources, & &1["proof"]) === proofs
    end

    if is_tuple(hold) and elem(hold, 0) in [:source_group, :source_group_loss] do
      {_, proofs, _} = hold
      assert Enum.map(snapshot.verified_sources, & &1["proof"]) === proofs
    end

    {:ok, %{pid: recipient}} = T.retained_share_identity(tx)
    {:ok, writer} = Host.session_share_writer_open(owner, job, capability)
    {name, secret} = transfer_binding()
    writer_entry = entry(writer, name, secret)

    request =
      :gen_server.send_request(
        tx.controller,
        {:writer_control_import, tx, controls.operation, writer_entry, controls.deadline}
      )

    assert :ok =
             Host.session_share_writer_transfer(owner, job, capability, recipient, name, secret)

    assert {:reply, :ok} = :gen_server.receive_response(request, remaining(controls.deadline))

    stat = File.stat!("/proc/#{controls.session_pid}/fd/0")
    session = %{pid: controls.session_pid, device: stat.major_device, inode: stat.inode}
    {name, secret} = transfer_binding()

    if hold == :wrong_recipient do
      send(Process.whereis(:ipse_share_host_fixture), {:session_switch_ready, self(), root})
      Host.configure_session_control(owner, job, capability, recipient + 1, name, secret)
      flunk("different writer and Session recipients were accepted")
    end

    request =
      :gen_server.send_request(
        tx.controller,
        {:session_control_import, tx, controls.operation, entry(session, name, secret),
         controls.deadline}
      )

    assert :ok = Host.configure_session_control(owner, job, capability, recipient, name, secret)

    receive do
      {:session_owner_control, ^capability, :transferred} -> :ok
    after
      remaining(controls.deadline) -> flunk("Session control transfer timed out")
    end

    assert {:reply, :ok} = :gen_server.receive_response(request, remaining(controls.deadline))

    {:ok, identity} = Host.session_share_identity(owner, job, capability)
    {name, secret} = transfer_binding()

    request =
      :gen_server.send_request(
        tx.controller,
        {:source_import, tx, transport, entry(identity, name, secret), controls.deadline}
      )

    recipient_entry =
      <<recipient::32, name::binary, secret::binary, identity.device::64, identity.inode::64>>

    assert :ok = Host.export_session_share(owner, job, capability, recipient_entry)
    assert {:reply, :ok} = :gen_server.receive_response(request, remaining(controls.deadline))

    if hold == true or match?({:source_hold, _}, hold) do
      send(Process.whereis(:ipse_share_host_fixture), {:session_switch_ready, self(), root})

      receive do
        :continue_session_switch -> :ok
      after
        remaining(controls.deadline) -> flunk("held Session switch timed out")
      end
    end

    loss_pid =
      case hold do
        {:source_group_loss, _, [token | _]} ->
          {:ok, source} = Ipse.Session.StoredSources.share_identity(token)
          source.pid

        _ ->
          nil
      end

    switch = fn ->
      if match?({:source_group_loss, _, _}, hold) do
        send(
          Process.whereis(:ipse_share_host_fixture),
          {:source_switch_ready, self(), root, loss_pid}
        )

        receive do
          :continue_session_switch -> :ok
        after
          remaining(controls.deadline) -> flunk("held source switch timed out")
        end
      end

      T.switch_before(tx, stage, "root.json", System.system_time(:millisecond) + 10_000)
    end

    result =
      case hold do
        {:source_group, _, tokens} -> T.with_source_leases(tx, tokens, switch)
        {:source_group_loss, _, tokens} -> T.with_source_leases(tx, tokens, switch)
        _ -> switch.()
      end

    if match?({:source_group_loss, _, _}, hold) do
      send(Process.whereis(:ipse_share_host_fixture), {:source_switch_result, result})
      Process.exit(self(), :kill)
    end

    assert :ok = result

    closing =
      :gen_server.send_request(tx.controller, {:source_close, tx, transport, controls.deadline})

    assert :ok = Host.settle_session_share(owner, job, capability)
    assert {:reply, :ok} = :gen_server.receive_response(closing, remaining(controls.deadline))
    assert :ok = Host.session_share_writer_prepare_close(owner, job, capability)
    assert :ok = Host.prepare_transaction_share_close(owner, job, capability)
    assert :ok = GenServer.call(tx.controller, {:session_control_close, tx, controls.deadline})

    receive do
      {:session_owner_control, ^capability, :closed} -> :ok
    after
      remaining(controls.deadline) -> flunk("Session control close timed out")
    end

    assert :ok = GenServer.call(tx.controller, {:writer_control_close, tx, controls.deadline})
    assert :ok = Host.session_share_writer_close(owner, job, capability)
    assert :ok = Host.finish_controlled_session_share(owner, job, capability, controls.host_port)
    Enum.each(Enum.reverse(caps), fn c -> assert :ok = T.release(c) end)
    assert File.read!(Path.join(root, "root.json")) == "new"
    :ok
  end

  defp transfer_binding, do: {:crypto.strong_rand_bytes(16), :crypto.strong_rand_bytes(32)}

  def begin_prepared(owner, job, intent, ticket, operation, deadline) do
    {:ok, prepared} = Ipse.Runner.prepare_owner_control(job, intent, ticket, operation, deadline)
    {:ok, port} = Ipse.Runner.open_prepared_owner_control(prepared, self(), job, intent)

    receive do
      {^port, {:data, <<?R, 16::32, "owner-control-v1">>}} -> :ok
    after
      remaining(deadline) -> flunk("owner control setup timed out")
    end

    GenServer.call(owner, {:session_share_begin_controlled, job, intent, prepared, port}, 6_000)
  end

  defp entry(id, name, secret),
    do: <<id.pid::32, name::binary, secret::binary, id.device::64, id.inode::64>>

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
