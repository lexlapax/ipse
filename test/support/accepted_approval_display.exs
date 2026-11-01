defmodule Ipse.Test.AcceptedApprovalDisplay do
  import ExUnit.Assertions
  alias Ipse.JSON
  alias Ipse.Session.PendingAcceptance

  def install(root) do
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    source = File.read!(Path.expand("../../lib/ipse/runner/leased_terminal.ex", __DIR__))
    anchor = ":ok <- send_frame(port, ?A, body),"
    assert length(:binary.matches(source, anchor)) == 1

    instrumented =
      String.replace(
        source,
        anchor,
        ":ok <- Ipse.Test.AcceptedApprovalDisplay.before_display(port, sources, controls.operation),\n           " <>
          anchor,
        global: false
      )

    IO.puts("ACCEPTED_APPROVAL_DISPLAY_SOURCE_SHA256=" <> JSON.sha256(instrumented))
    [{module, beam}] = Code.compile_string(instrumented, "accepted-approval-display-control.ex")
    path = Path.join(root, "Elixir.Ipse.Runner.LeasedTerminal.beam")
    File.write!(path, beam)
    assert {:module, ^module} = :code.load_binary(module, String.to_charlist(path), beam)
  end

  def observe(consumer, paths, link, lose_journal?, marker) do
    owner = self()

    task =
      Task.async(fn ->
        true = Process.register(self(), :ipse_accepted_approval_display)
        send(owner, :accepted_approval_display_ready)

        receive do
          {:accepted_approval_display, publisher, terminal, sources, shares, operation} ->
            assert {:os_pid, native} = Port.info(terminal, :os_pid)
            state = :sys.get_state(consumer)
            assert state.phase == :managed_approval
            assert Enum.any?(state.managed_approval.dependencies, &(&1["version"] === 6))
            assert state.share_barrier.owner_recipient == native
            assert state.share_barrier.phase == :exported

            writer = :sys.get_state(state.journal_writer)
            assert writer.owner == consumer
            assert writer.share_barrier.token === state.share_barrier.token
            assert writer.share_barrier.operation === operation
            assert writer.share_barrier.snapshot === state.share_barrier.snapshot

            assert {:error, :journal_share_frozen} =
                     Ipse.Journal.Writer.append(state.journal_writer, %{
                       "type" => "forbidden_during_accepted_display"
                     })

            identities =
              for fd <- File.ls!("/proc/#{native}/fd"),
                  {:ok, stat} <- [File.stat("/proc/#{native}/fd/#{fd}")],
                  do: {stat.major_device, stat.inode}

            for path <- paths do
              stat = File.stat!(path)
              assert {stat.major_device, stat.inode} in identities
            end

            for port <- [state.share_barrier.owner_port, state.share_barrier.host_port] do
              assert {:os_pid, owner_control} = Port.info(port, :os_pid)
              control = File.stat!("/proc/#{owner_control}/fd/0")
              assert {control.major_device, control.inode} in identities
            end

            assert [{{:acceptance_journal, token}, identity}] =
                     Enum.filter(sources, &match?({{:acceptance_journal, _}, _}, &1))

            share = Map.fetch!(shares, token)
            assert share.owner == publisher and share.phase == :shared
            assert share.link == link and share.operation == operation
            assert Port.info(share.port, :connected) == {:connected, publisher}
            assert {:os_pid, peer} = Port.info(share.port, :os_pid)
            assert peer == identity.pid

            journal_lock = List.last(paths)
            assert {:error, _} = Ipse.Runner.lock(journal_lock)

            if lose_journal? do
              monitor = :erlang.monitor(:port, share.port)
              assert {_, 0} = System.cmd("/bin/kill", ["-KILL", Integer.to_string(peer)])
              assert_receive {:DOWN, ^monitor, :port, _, _}, 5_000
              assert Port.info(share.port) == nil
            end

            send(publisher, :accepted_approval_display_continue)
            File.write!(marker, "checked")

            receive do
              {:inspection_result, caller, ref} -> send(caller, {ref, :owners_checked})
            after
              30_000 -> flunk("accepted display ownership result was not collected")
            end

            :owners_checked
        after
          30_000 -> flunk("accepted approval did not reach the actual native display sink")
        end
      end)

    assert_receive :accepted_approval_display_ready, 1_000
    task
  end

  def before_display(terminal, sources, operation) do
    if Enum.any?(sources, &match?({{:acceptance_journal, _}, _}, &1)) do
      send(
        Process.whereis(:ipse_accepted_approval_display),
        {:accepted_approval_display, self(), terminal, sources,
         Process.get({PendingAcceptance, :journal_share}), operation}
      )

      receive do
        :accepted_approval_display_continue -> :ok
      after
        10_000 -> flunk("accepted display ownership observer did not release the publisher")
      end
    else
      :ok
    end
  end
end
