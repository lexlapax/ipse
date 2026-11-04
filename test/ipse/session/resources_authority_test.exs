defmodule Ipse.Session.ResourcesAuthorityTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Resources

  test "only the owning Session can recognize its current worker and actual file effect" do
    owner = self()
    {:ok, scope} = Resources.start(owner)

    worker =
      spawn(fn ->
        Process.flag(:trap_exit, true)

        receive do
          :start -> :ok
        end

        Resources.bind(scope)

        Resources.async(fn ->
          send(owner, {:ordinary, self()})
          receive do: (:finish -> :ok)
        end)

        Resources.file_effect(fn ->
          send(owner, {:effect, self()})
          receive do: (:finish -> :ok)
        end)

        send(owner, :effect_finished)
        receive do: (:stop -> :ok)
      end)

    on_exit(fn ->
      if Process.alive?(worker), do: Process.exit(worker, :kill)
      if Process.alive?(scope), do: Resources.close(scope)
    end)

    assert :ok = Resources.attach(scope, worker)
    send(worker, :start)
    assert_receive {:ordinary, ordinary}
    assert_receive {:effect, effect}
    assert Resources.authorized_effect?(worker, worker)
    assert Resources.authorized_effect?(worker, effect)
    assert Resources.authorized_task?(worker, ordinary)
    refute Resources.authorized_task?(worker, effect)
    refute Resources.authorized_task?(worker, self())
    refute Task.async(fn -> Resources.authorized_task?(worker, ordinary) end) |> Task.await()
    refute Resources.authorized_effect?(worker, ordinary)
    refute Resources.authorized_effect?(ordinary, effect)
    refute Resources.authorized_effect?(worker, self())

    refute Task.async(fn -> Resources.authorized_effect?(worker, effect) end) |> Task.await()
    send(effect, :finish)
    assert_receive :effect_finished
    assert :ok = Resources.finish(scope)
    refute Resources.authorized_task?(worker, ordinary)
    refute Resources.authorized_effect?(worker, worker)
    refute Resources.authorized_effect?(worker, effect)
    assert :ok = Resources.close(scope)
    refute Resources.authorized_effect?(worker, worker)
  end

  test "the owner scope terminates an unlinked tracked reader on owner loss" do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, scope} = Resources.start(self())

        worker =
          spawn(fn ->
            receive do: (:start -> :ok)
            Resources.bind(scope)

            task =
              Resources.async(fn ->
                send(parent, {:snapshot_reader, self()})
                receive do: (:stop -> :ok)
              end)

            Process.unlink(task.pid)
            receive do: (:stop -> :ok)
          end)

        :ok = Resources.attach(scope, worker)
        send(worker, :start)
        send(parent, {:snapshot_scope, self(), scope, worker})
        receive do: (:stop -> :ok)
      end)

    assert_receive {:snapshot_scope, ^owner, scope, worker}
    assert_receive {:snapshot_reader, reader}
    reader_ref = Process.monitor(reader)
    scope_ref = Process.monitor(scope)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^reader_ref, :process, ^reader, _}, 5_000
    assert_receive {:DOWN, ^scope_ref, :process, ^scope, _}, 5_000
    refute Process.alive?(worker)
  end

  test "a document effect with a queued start refuses IO after its Worker dies" do
    parent = self()
    {:ok, scope} = Resources.start(parent)

    worker =
      spawn(fn ->
        receive do: (:start -> :ok)
        Resources.bind(scope)

        Resources.document_file_effect(
          fn ->
            send(parent, :late_document_effect_started)
            :ok
          end,
          fn peer ->
            send(parent, {:dormant_document_peer, peer})
            receive do: (:allow_document_registration -> :ok)
            :ok
          end
        )
      end)

    on_exit(fn ->
      if Process.alive?(worker), do: Process.exit(worker, :kill)
      if Process.alive?(scope), do: Resources.close(scope)
    end)

    :ok = Resources.attach(scope, worker)
    send(worker, :start)
    assert_receive {:dormant_document_peer, peer}, 2_000

    on_exit(fn ->
      if Process.alive?(peer) do
        try do
          :erlang.resume_process(peer)
        rescue
          ArgumentError -> :ok
        end

        Process.exit(peer, :kill)
      end
    end)

    peer_ref = Process.monitor(peer)
    worker_ref = Process.monitor(worker)
    true = :erlang.suspend_process(peer)
    send(worker, :allow_document_registration)

    queued =
      Enum.reduce_while(1..200, false, fn _, _ ->
        case Process.info(peer, :messages) do
          {:messages, messages} ->
            if Enum.any?(messages, &(&1 == {:begin_file_effect, worker})),
              do: {:halt, true},
              else:
                (
                  Process.sleep(10)
                  {:cont, false}
                )

          _ ->
            {:halt, false}
        end
      end)

    assert queued
    Process.exit(worker, :kill)
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}, 2_000
    true = :erlang.resume_process(peer)
    assert_receive {:DOWN, ^peer_ref, :process, ^peer, _}, 5_000
    refute_received :late_document_effect_started
  end
end
