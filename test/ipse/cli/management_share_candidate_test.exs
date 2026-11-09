defmodule Ipse.CLI.ManagementShareCandidateTest do
  use ExUnit.Case, async: false
  alias Ipse.{Journal, Runner, Usage}
  alias Ipse.CLI.Knowledge.Management
  alias Ipse.Extension.ProjectIdentity
  alias Ipse.Journal.Writer
  alias Ipse.Session.Lock
  alias Ipse.Session.Resources

  test "unused owner-control cancellation requires its owner and an exact native acknowledgement" do
    assert {:ok, port} = Runner.open_owner_control()
    assert frame(port, ?R) == "owner-control-v1"
    deadline = System.monotonic_time(:millisecond) + 5_000

    assert {:error, :owner_control_unconfirmed} =
             Task.async(fn -> Runner.cancel_unused_owner_control(port, deadline) end)
             |> Task.await()

    assert {:error, :owner_control_unconfirmed} =
             Runner.cancel_unused_owner_control(port, System.monotonic_time(:millisecond) - 1)

    assert :ok = Runner.cancel_unused_owner_control(port, deadline)

    assert {:error, :owner_control_unconfirmed} =
             Runner.cancel_unused_owner_control(port, deadline)
  end

  @tag :native_storage
  test "unused management controls acknowledge a pre-display refusal" do
    root = Path.join(System.tmp_dir!(), "ipse-management-refusal-" <> Usage.id())
    home = Path.join(root, "home")
    cwd = Path.join(root, "cwd")
    File.mkdir_p!(home)
    File.mkdir!(cwd)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    assert {:ok, _} = ProjectIdentity.admit(home, cwd, :folder)
    deadline = System.monotonic_time(:millisecond) + 10_000

    assert {:closed, {:error, :fixture_refused}} =
             Management.controlled_review_journal_candidate(%{home: home}, cwd, deadline, fn _ ->
               {:error, :fixture_refused}
             end)

    assert {:unknown, :management_control_unconfirmed} =
             Management.controlled_review_journal_candidate(%{home: home}, cwd, deadline, fn _ ->
               {:ok, :unreviewed_result}
             end)
  end

  @tag timeout: 30_000
  @tag :native_storage
  test "a retained lifecycle journal binds its latest intent to the same transaction owner" do
    root = Path.join(System.tmp_dir!(), "ipse-management-lifecycle-share-" <> Usage.id())
    home = Path.join(root, "home")
    cwd = Path.join(root, "cwd")
    File.mkdir_p!(home)
    File.mkdir!(cwd)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    assert {:ok, _} = ProjectIdentity.admit(home, cwd, :folder)

    paths =
      for n <- 1..3 do
        dir = Path.join(root, "lease-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    assert {:ok, :bound} =
             Management.share_journal_candidate(%{home: home}, cwd, fn owned ->
               now = System.system_time(:millisecond)

               body = %{
                 "kind" => "managed_literal_retention",
                 "operation_id" => Usage.id(),
                 "context" => %{"session_id" => owned.id},
                 "policy" => %{"kind" => "pin"},
                 "metadata" => %{"first_admitted_ms" => now, "valid_until_ms" => now + 60_000},
                 "old_deadline_ms" => now + 60_000
               }

               facts = Map.put(body, "action_sha256", Ipse.JSON.digest([body]))

               intent = %{
                 "type" => "managed_lifecycle_intent",
                 "version" => 1,
                 "operation_id" => facts["operation_id"],
                 "facts" => facts
               }

               assert :ok = Writer.append(owned.writer, intent)

               caps =
                 Enum.map(paths, fn path ->
                   {:ok, cap} = Ipse.Runner.Transaction.acquire(path)
                   cap
                 end)

               cap = List.last(caps)

               assert {:error, :invalid_transaction_capability} =
                        Ipse.Runner.Transaction.lifecycle_guard(cap, intent)

               assert {:error, :invalid_transaction_request} =
                        Ipse.Runner.Transaction.with_lifecycle_journal_lease(
                          cap,
                          owned,
                          Map.put(intent, "version", 2),
                          fn -> flunk("altered intent entered the callback") end
                        )

               result =
                 Ipse.Runner.Transaction.with_lifecycle_journal_lease(cap, owned, intent, fn ->
                   assert :ok = Ipse.Runner.Transaction.lifecycle_guard(cap, intent)

                   assert {:error, :invalid_transaction_capability} =
                            Ipse.Runner.Transaction.lifecycle_guard(
                              cap,
                              Map.put(intent, "version", 2)
                            )

                   assert {:error, :invalid_transaction_capability} =
                            Task.await(
                              Task.async(fn ->
                                Ipse.Runner.Transaction.lifecycle_guard(cap, intent)
                              end)
                            )

                   {:ok, :bound}
                 end)

               Enum.reverse(caps)
               |> Enum.each(fn item -> assert :ok = Ipse.Runner.Transaction.release(item) end)

               result
             end)
  end

  @tag timeout: 30_000
  @tag :native_storage
  test "original management journal lock shares in place and Writer thaws only after settlement" do
    root = Path.join(System.tmp_dir!(), "ipse-management-share-" <> Usage.id())
    home = Path.join(root, "home")
    cwd = Path.join(root, "cwd")
    File.mkdir_p!(home)
    File.mkdir!(cwd)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    assert {:ok, _} = ProjectIdentity.admit(home, cwd, :folder)
    test = self()

    caller =
      Task.async(fn ->
        Management.share_journal_candidate(%{home: home}, cwd, fn owned ->
          assert owned.cli_owner != owned.journal_owner
          assert owned.journal_owner == self()
          assert :ok = Writer.append(owned.writer, %{"type" => "synthetic_before"})
          guard_port = GenServer.call(owned.guard, :port)
          {:os_pid, exporter} = Port.info(guard_port, :os_pid)
          send(test, {:journal_started, self(), owned, exporter})

          receive do
            :begin -> :ok
          after
            5_000 -> exit(:fixture_timeout)
          end

          operation = :crypto.strong_rand_bytes(16)
          job = make_ref()
          generation = make_ref()

          {:reply, {:ok, token, snapshot}} =
            response(Writer.request_share_barrier(owned.writer, operation, job, generation))

          assert snapshot.session_id == owned.id and snapshot.job_ref == job and
                   snapshot.owner_generation == generation

          assert {:error, :journal_share_frozen} =
                   Writer.append(owned.writer, %{"type" => "must_not_append"})

          {:reply, {:ok, transport}} =
            response(Lock.request_share_arm(owned.guard, owned.writer, token, operation))

          send(test, {:armed, self(), transport, snapshot})

          receive do
            {:export, recipient} ->
              deadline = System.monotonic_time(:millisecond) + 5_000

              assert {:reply, :ok} =
                       response(
                         Lock.request_share_export(
                           owned.guard,
                           token,
                           operation,
                           recipient,
                           deadline
                         )
                       )

              send(test, {:exported, self()})

              receive do
                :settle -> :ok
              after
                5_000 -> exit(:fixture_timeout)
              end

              assert {:reply, :ok} =
                       response(
                         Lock.request_share_settle(owned.guard, token, operation, deadline)
                       )

              send(test, {:settled, self()})
              assert :ok = Writer.thaw_share_barrier(owned.writer, token, operation)
              assert :ok = Writer.append(owned.writer, %{"type" => "synthetic_after"})
              :ok
          after
            5_000 -> exit(:fixture_timeout)
          end
        end)
      end)

    assert_receive {:journal_started, effect, owned, exporter}, 5_000
    assert owned.cli_owner == caller.pid and owned.journal_owner == effect
    path = Path.join(owned.directory, owned.id <> ".lock")
    journal_path = Path.join(owned.directory, owned.id <> ".jsonl")
    assert {:error, _} = Runner.protected_lock(path)
    stat = File.stat!(path)
    [header, before] = elem(Journal.load(owned.directory, owned.id), 1)
    assert header["metadata"]["kind"] == "knowledge_management"
    assert header["metadata"]["native_journal_layout"] == Journal.native_owner_layout()
    refute Map.has_key?(header["metadata"], "release_receipt_layout")
    assert before["type"] == "synthetic_before"
    bytes_before = File.read!(journal_path)
    send(effect, :begin)
    assert_receive {:armed, ^effect, transport, snapshot}, 5_000
    assert snapshot.offset == byte_size(bytes_before)
    assert {:error, _} = Runner.protected_lock(path)
    helper = Path.join(to_string(:code.priv_dir(:ipse)), "ipse-runner")

    collector =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        args: ["--lease-collect-close-ready-v3"]
      ])

    on_exit(fn -> if Port.info(collector), do: Port.close(collector) end)
    {:os_pid, pid} = Port.info(collector, :os_pid)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)

    entry =
      <<0, exporter::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>

    initial = <<5_000::64, transport::binary, 1, entry::binary>>
    assert Port.command(collector, <<?I, byte_size(initial)::32, initial::binary>>)
    assert frame(collector, ?H) == <<transport::binary, 1>>
    recipient = <<pid::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>
    send(effect, {:export, recipient})
    assert_receive {:exported, ^effect}, 5_000
    assert frame(collector, ?L) == <<transport::binary, 1>>
    assert File.read!(journal_path) == bytes_before
    assert {:error, _} = Runner.protected_lock(path)
    assert Port.command(collector, <<?C, transport::binary>>)
    send(effect, :settle)
    assert_receive {:settled, ^effect}, 5_000
    assert frame(collector, ?C) == <<transport::binary, 1>>
    assert_receive {^collector, {:exit_status, 0}}, 5_000
    assert :ok = Task.await(caller, 10_000)

    assert {:ok, [_header, %{"type" => "synthetic_before"}, %{"type" => "synthetic_after"}]} =
             Journal.load(owned.directory, owned.id)

    assert {:ok, contender} = Runner.protected_lock(path)
    assert :ok = Runner.unlock(contender)
  end

  @tag :management_share_old
  @tag skip: System.get_env("IPSE_MANAGEMENT_SHARE_OLD_HELPER") != "1"
  test "older pinned helper refuses candidate before a management journal header exists" do
    root = Path.join(System.tmp_dir!(), "ipse-management-share-old-" <> Usage.id())
    home = Path.join(root, "home")
    cwd = Path.join(root, "cwd")
    File.mkdir_p!(home)
    File.mkdir!(cwd)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    assert {:ok, _} = ProjectIdentity.admit(home, cwd, :folder)
    caller = self()

    assert {:error, :knowledge_management_refused} =
             Management.share_journal_candidate(%{home: home}, cwd, fn _ ->
               send(caller, :unexpected_callback)
               :ok
             end)

    refute_received :unexpected_callback
    assert Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"])) == []
  end

  @tag :management_controls
  @tag :native_storage
  test "actual CLI and journal peers own independent native control senders", c do
    root = Path.join(System.tmp_dir!(), "ipse-management-controls-" <> Usage.id())
    home = Path.join(root, "home")
    cwd = Path.join(root, "cwd")
    File.mkdir_p!(home)
    File.mkdir!(cwd)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    assert {:ok, _} = ProjectIdentity.admit(home, cwd, :folder)
    test = self()

    caller =
      Task.async(fn ->
        Management.controlled_share_journal_candidate(%{home: home}, cwd, fn owned ->
          send(test, {:controls_ready, self(), owned})

          receive do
            {:transfer, cli, journal} ->
              {cli_recipient, cli_name, cli_secret} = cli
              {journal_recipient, journal_name, journal_secret} = journal

              cli_result =
                Resources.management_control_transfer(
                  owned.cli_control,
                  cli_recipient,
                  cli_name,
                  cli_secret
                )

              journal_result =
                Management.management_journal_control_transfer(
                  owned.journal_control,
                  journal_recipient,
                  journal_name,
                  journal_secret
                )

              send(test, {:controls_transferred, self(), cli_result, journal_result})

              receive do
                :finish -> :ok
              after
                10_000 -> :timeout
              end
          after
            5_000 -> :timeout
          end
        end)
      end)

    Process.unlink(caller.pid)
    assert_receive {:controls_ready, effect, owned}, 5_000
    assert owned.cli_owner == caller.pid and owned.journal_owner == effect
    assert owned.cli_control.owner == caller.pid and owned.cli_control.effect == effect
    assert owned.journal_control.owner == effect
    assert owned.cli_control.operation == owned.journal_control.operation

    assert {:unknown, :management_control_unconfirmed} =
             Resources.management_control_transfer(owned.cli_control, 1, <<1::128>>, <<1::256>>)

    assert {:unknown, :management_control_unconfirmed} =
             Management.management_journal_control_transfer(
               owned.journal_control,
               1,
               <<1::128>>,
               <<1::256>>
             )

    {cli_observer, cli_request} =
      observer(owned.cli_control.sender_pid, owned.cli_control.operation, 1)

    {journal_observer, journal_request} =
      observer(owned.journal_control.sender_pid, owned.cli_control.operation, 2)

    on_exit(fn ->
      for port <- [cli_observer, journal_observer], Port.info(port), do: Port.close(port)
    end)

    send(effect, {:transfer, cli_request, journal_request})
    assert_receive {:controls_transferred, ^effect, :ok, :ok}, 5_000
    assert frame(cli_observer, ?L) == <<owned.cli_control.operation::binary, 1>>
    assert frame(journal_observer, ?L) == <<owned.cli_control.operation::binary, 2>>
    caller_ref = Process.monitor(caller.pid)
    Process.exit(caller.pid, :kill)
    assert_receive {:DOWN, ^caller_ref, :process, _, _}, 5_000
    assert frame(cli_observer, ?D) == <<owned.cli_control.operation::binary, 1>>
    assert Process.alive?(effect)
    effect_ref = Process.monitor(effect)
    Process.exit(effect, :kill)
    assert_receive {:DOWN, ^effect_ref, :process, _, _}, 5_000
    assert frame(journal_observer, ?D) == <<owned.cli_control.operation::binary, 2>>
    assert_receive {^cli_observer, {:exit_status, 0}}, 5_000
    assert_receive {^journal_observer, {:exit_status, 0}}, 5_000
    _ = c
  end

  defp observer(sender, operation, role) do
    info = File.stat!("/proc/#{sender}/fd/0")
    helper = Path.join(to_string(:code.priv_dir(:ipse)), "ipse-runner")

    port =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        args: ["--owner-control-observe-v1"]
      ])

    assert frame(port, ?H) == "owner-observer-v1"
    {:os_pid, recipient} = Port.info(port, :os_pid)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)
    entry = <<sender::32, name::binary, secret::binary, info.major_device::64, info.inode::64>>
    request = <<operation::binary, role, entry::binary, 30_000::64>>
    assert Port.command(port, <<?I, byte_size(request)::32, request::binary>>)
    {port, {recipient, name, secret}}
  end

  @tag :management_control_replay
  @tag :native_storage
  test "replayed management owner-control requests poison both senders" do
    root = Path.join(System.tmp_dir!(), "ipse-management-replay-" <> Usage.id())
    home = Path.join(root, "home")
    cwd = Path.join(root, "cwd")
    File.mkdir_p!(home)
    File.mkdir!(cwd)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    assert {:ok, _} = ProjectIdentity.admit(home, cwd, :folder)
    test = self()

    caller =
      Task.async(fn ->
        Management.controlled_share_journal_candidate(%{home: home}, cwd, fn owned ->
          send(test, {:replay_ready, self(), owned})

          receive do
            {:transfer, {cp, cn, cs}, {jp, jn, js}} ->
              assert :ok = Resources.management_control_transfer(owned.cli_control, cp, cn, cs)

              assert :ok =
                       Management.management_journal_control_transfer(
                         owned.journal_control,
                         jp,
                         jn,
                         js
                       )

              send(test, {:replay_transferred, self()})

              receive do
                :repeat -> :ok
              after
                5_000 -> exit(:fixture_timeout)
              end

              journal =
                Management.management_journal_control_transfer(owned.journal_control, jp, jn, js)

              cli = Resources.management_control_transfer(owned.cli_control, cp, cn, cs)
              send(test, {:replay_refused, self(), cli, journal})
              :ok
          after
            5_000 -> exit(:fixture_timeout)
          end
        end)
      end)

    assert_receive {:replay_ready, effect, owned}, 5_000

    {cli_observer, cli_request} =
      observer(owned.cli_control.sender_pid, owned.cli_control.operation, 1)

    {journal_observer, journal_request} =
      observer(owned.journal_control.sender_pid, owned.cli_control.operation, 2)

    on_exit(fn ->
      for port <- [cli_observer, journal_observer], Port.info(port), do: Port.close(port)
    end)

    send(effect, {:transfer, cli_request, journal_request})
    assert_receive {:replay_transferred, ^effect}, 5_000
    assert frame(cli_observer, ?L) == <<owned.cli_control.operation::binary, 1>>
    assert frame(journal_observer, ?L) == <<owned.cli_control.operation::binary, 2>>
    send(effect, :repeat)

    assert_receive {:replay_refused, ^effect, {:unknown, :management_control_unconfirmed},
                    {:unknown, :management_control_unconfirmed}},
                   5_000

    assert frame(cli_observer, ?D) == <<owned.cli_control.operation::binary, 1>>
    assert frame(journal_observer, ?D) == <<owned.cli_control.operation::binary, 2>>
    assert {:unknown, :management_control_unconfirmed} = Task.await(caller, 5_000)
  end

  @tag :management_control_stall
  @tag timeout: 20_000
  @tag :native_storage
  test "stalled CLI transfer returns unknown at the original setup deadline" do
    root = Path.join(System.tmp_dir!(), "ipse-management-stall-" <> Usage.id())
    home = Path.join(root, "home")
    cwd = Path.join(root, "cwd")
    File.mkdir_p!(home)
    File.mkdir!(cwd)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    assert {:ok, _} = ProjectIdentity.admit(home, cwd, :folder)
    helper = Path.join(to_string(:code.priv_dir(:ipse)), "ipse-runner")

    observer =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        args: ["--owner-control-observe-v1"]
      ])

    on_exit(fn -> if Port.info(observer), do: Port.close(observer) end)
    assert frame(observer, ?H) == "owner-observer-v1"
    {:os_pid, recipient} = Port.info(observer, :os_pid)
    test = self()
    start = System.monotonic_time(:millisecond)

    result =
      Management.controlled_share_journal_candidate(%{home: home}, cwd, fn owned ->
        result =
          Resources.management_control_transfer(
            owned.cli_control,
            recipient,
            :crypto.strong_rand_bytes(16),
            :crypto.strong_rand_bytes(32)
          )

        send(test, {:stalled_transfer, result})
        :ok
      end)

    assert_receive {:stalled_transfer, {:unknown, :management_control_unconfirmed}}, 1_000
    assert {:unknown, :management_control_unconfirmed} = result
    assert System.monotonic_time(:millisecond) - start < 7_000
  end

  defp response(request), do: :gen_server.receive_response(request, 5_000)

  defp frame(port, tag, buffer \\ <<>>) do
    case buffer do
      <<^tag, size::32, body::binary-size(size)>> ->
        body

      _ ->
        receive do
          {^port, {:data, bytes}} when byte_size(buffer) + byte_size(bytes) <= 256 ->
            frame(port, tag, buffer <> bytes)

          {^port, {:exit_status, status}} ->
            flunk("collector exit #{status}")
        after
          5_000 -> flunk("collector timeout")
        end
    end
  end
end
