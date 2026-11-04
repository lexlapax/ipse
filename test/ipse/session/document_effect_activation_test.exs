defmodule Ipse.Session.DocumentEffectActivationTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Resources, as: R

  @moduletag timeout: 15_000

  # These real cleanup actors execute only messages, never native or file IO.
  defp open(scope_owner \\ self()) do
    parent = self()
    {:ok, scope} = R.start(scope_owner)

    worker =
      spawn(fn ->
        receive do
          :start -> :ok
        end

        R.bind(scope)

        result =
          R.document_file_effect(
            fn ->
              send(parent, {:effect_entered, self()})

              receive do
                :finish_effect -> :done
              after
                6_000 -> :timed_out
              end
            end,
            fn peer ->
              send(parent, {:dormant, self(), peer})

              receive do
                :finish_registration -> :ok
              end
            end,
            fn peer ->
              send(parent, {:activation_requested, self(), peer})

              receive do
                {:activation_reply, result} -> result
              end
            end
          )

        send(parent, {:document_result, self(), result})

        receive do
          :stop -> :ok
        end
      end)

    assert :ok = R.attach(scope, worker)
    send(worker, :start)
    assert_receive {:dormant, ^worker, peer}, 1_000

    on_exit(fn ->
      send(peer, :finish_effect)
      if Process.alive?(worker), do: Process.exit(worker, :kill)
      if Process.alive?(scope), do: R.close(scope)
    end)

    %{scope: scope, worker: worker, peer: peer}
  end

  defp request(c) do
    send(c.worker, :finish_registration)
    assert_receive {:activation_requested, worker, peer}, 1_000
    assert worker === c.worker and peer === c.peer
  end

  test "tracking stays dormant and queued revocation closes it without entering an effect" do
    c = open()
    assert :sys.get_state(c.scope).document_effects[c.peer] === :dormant
    refute_receive {:effect_entered, _}
    request(c)
    assert :ok = :sys.suspend(c.scope)
    revoke = :gen_server.send_request(c.scope, {:revoke_document_effects, c.worker})
    activate = :gen_server.send_request(c.scope, {:activate_document_effect, c.worker, c.peer})
    assert :ok = :sys.resume(c.scope)
    assert {:reply, :ok} = :gen_server.wait_response(revoke, 1_000)
    assert {:reply, {:error, :cleanup_scope_closed}} = :gen_server.wait_response(activate, 1_000)
    monitor = Process.monitor(c.peer)
    assert :ok = R.close(c.scope)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}, 1_000
    refute_receive {:effect_entered, _}
  end

  test "foreign, wrong-worker and stale activation cannot consume a live dormant peer" do
    c = open()
    request(c)

    assert {:error, :cleanup_scope_closed} =
             Task.async(fn -> R.activate_document_effect(c.worker, c.peer) end) |> Task.await()

    assert {:error, :cleanup_scope_closed} = R.activate_document_effect(self(), c.peer)
    assert {:error, :cleanup_scope_closed} = R.activate_document_effect(c.worker, self())
    assert :sys.get_state(c.scope).document_effects[c.peer] === :dormant
    assert :ok = R.activate_document_effect(c.worker, c.peer)
    send(c.worker, {:activation_reply, :ok})
    assert_receive {:effect_entered, peer}, 1_000
    assert peer === c.peer
    assert {:error, :cleanup_scope_closed} = R.activate_document_effect(c.worker, c.peer)
    send(c.peer, :finish_effect)
    assert_receive {:document_result, worker, :done}, 1_000
    assert worker === c.worker
    assert :ok = R.close(c.scope)
    refute_receive {:effect_entered, _}
  end

  test "duplicate tracking cannot relabel an active effect as dormant" do
    c = open()
    request(c)
    assert :ok = R.activate_document_effect(c.worker, c.peer)
    send(c.worker, {:activation_reply, :ok})
    assert_receive {:effect_entered, peer}, 1_000
    assert peer === c.peer

    assert {:reply, {:error, :cleanup_scope_closed}, state} =
             R.handle_call(
               {:track_document_effect, c.peer},
               {c.worker, make_ref()},
               :sys.get_state(c.scope)
             )

    assert state.document_effects[c.peer] === :active
    send(c.peer, :finish_effect)
    assert_receive {:document_result, _, :done}, 1_000
    assert :ok = R.close(c.scope)
  end

  test "an active effect is awaited rather than killed during confirmed close" do
    c = open()
    request(c)
    assert :ok = R.activate_document_effect(c.worker, c.peer)
    send(c.worker, {:activation_reply, :ok})
    assert_receive {:effect_entered, _}, 1_000
    closer = Task.async(fn -> R.close(c.scope) end)
    assert Task.yield(closer, 50) === nil
    assert Process.alive?(c.peer)
    send(c.peer, :finish_effect)
    assert :ok = Task.await(closer, 5_000)
    assert_receive {:document_result, _, :done}, 1_000
  end

  test "generic active file effects remain alive and unconfirmed when cleanup cannot finish" do
    parent = self()
    {:ok, scope} = R.start(parent)

    worker =
      spawn(fn ->
        receive do
          :start -> :ok
        end

        R.bind(scope)

        result =
          R.file_effect(fn ->
            send(parent, {:generic_effect_entered, self()})

            receive do
              :finish_effect -> :done
            after
              6_000 -> :timed_out
            end
          end)

        send(parent, {:generic_result, result})

        receive do
          :stop -> :ok
        end
      end)

    assert :ok = R.attach(scope, worker)
    send(worker, :start)
    assert_receive {:generic_effect_entered, peer}, 1_000

    on_exit(fn ->
      send(peer, :finish_effect)
      if Process.alive?(worker), do: Process.exit(worker, :kill)
      if Process.alive?(scope), do: R.close(scope)
    end)

    state = :sys.get_state(scope)

    assert {:reply, {:error, :cleanup_scope_closed}, ^state} =
             R.handle_call({:track_document_effect, peer}, {worker, make_ref()}, state)

    assert {:error, :cleanup_unconfirmed} = R.close(scope)
    assert Process.alive?(peer)
    send(peer, :finish_effect)
    assert_receive {:generic_result, :done}, 1_000
  end

  test "lost activation reply remains uncertain and never kills the admitted effect as dormant" do
    c = open()
    request(c)
    assert :ok = R.activate_document_effect(c.worker, c.peer)
    assert_receive {:effect_entered, _}, 1_000
    # The actual owner accepted activation, but its response was not delivered.
    send(c.worker, {:activation_reply, {:error, :synthetic_response_loss}})
    ref = Process.monitor(c.worker)
    scope_ref = Process.monitor(c.scope)
    assert_receive {:DOWN, ^ref, :process, _, :document_effect_activation_unconfirmed}, 1_000
    assert Process.alive?(c.peer)
    send(c.peer, :finish_effect)
    assert_receive {:DOWN, ^scope_ref, :process, _, :normal}, 5_000
    refute_receive {:effect_entered, _}
  end

  test "owner loss before activation stops the dormant peer without effect entry" do
    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)
    c = open(owner)
    refs = Enum.map([c.peer, c.scope, c.worker], &{&1, Process.monitor(&1)})
    Process.exit(owner, :kill)
    for {pid, ref} <- refs, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 1_000)
    refute_receive {:effect_entered, _}
  end

  test "scope loss cannot start a peer still waiting for activation" do
    c = open()
    refs = Enum.map([c.peer, c.worker], &{&1, Process.monitor(&1)})
    Process.exit(c.scope, :kill)
    for {pid, ref} <- refs, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 1_000)
    refute_receive {:effect_entered, _}
  end

  test "worker loss before activation terminates dormant work without effect entry" do
    c = open()
    peer_ref = Process.monitor(c.peer)
    scope_ref = Process.monitor(c.scope)
    Process.exit(c.worker, :kill)
    assert_receive {:DOWN, ^peer_ref, :process, _, _}, 1_000
    assert_receive {:DOWN, ^scope_ref, :process, _, _}, 1_000
    refute_receive {:effect_entered, _}
  end

  test "Session activation binds the exact job, caller, reader, peer and unused token before storage" do
    c = open()

    reader =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> send(reader, :stop) end)
    job = make_ref()
    intent = %{"request" => %{}}
    token = make_ref()
    bound = %{reader: reader, token: token, peer: c.peer, bound: false, used: false}

    state = %{
      job_ref: job,
      task: %{pid: c.worker},
      invocation: %{action: %{intent: intent, workspace_snapshot_reader: bound}}
    }

    for {request, from} <- [
          {{:extension_workspace_snapshot_activate, job, intent, reader, c.peer, token}, self()},
          {{:extension_workspace_snapshot_activate, make_ref(), intent, reader, c.peer, token},
           c.worker},
          {{:extension_workspace_snapshot_activate, job, intent, c.worker, c.peer, token},
           c.worker},
          {{:extension_workspace_snapshot_activate, job, intent, reader, reader, token},
           c.worker},
          {{:extension_workspace_snapshot_activate, job, intent, reader, c.peer, make_ref()},
           c.worker}
        ] do
      assert {:reply, {:error, :document_store_refused}, ^state} =
               Ipse.Session.handle_call(request, {from, make_ref()}, state)
    end

    for field <- [:bound, :used] do
      changed = put_in(state.invocation.action.workspace_snapshot_reader[field], true)
      request = {:extension_workspace_snapshot_activate, job, intent, reader, c.peer, token}

      assert {:reply, {:error, :document_store_refused}, ^changed} =
               Ipse.Session.handle_call(request, {c.worker, make_ref()}, changed)
    end

    assert :sys.get_state(c.scope).document_effects[c.peer] === :dormant
    refute_receive {:effect_entered, _}
  end
end
