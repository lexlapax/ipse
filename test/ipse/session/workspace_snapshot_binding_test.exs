defmodule Ipse.Session.WorkspaceSnapshotBindingTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Collection.WorkspaceDocumentGuard, as: Guard

  test "the live action refuses a different effect, reader, or reused request" do
    job = make_ref()
    token = make_ref()
    intent = %{"request" => %{}}
    worker = self()
    reader = spawn(fn -> receive do: (:stop -> :ok) end)
    peer = spawn(fn -> receive do: (:stop -> :ok) end)
    impostor = spawn(fn -> receive do: (:stop -> :ok) end)
    on_exit(fn -> Enum.each([reader, peer, impostor], &Process.exit(&1, :kill)) end)

    action = %{
      intent: intent,
      workspace_snapshot_reader: %{
        reader: reader,
        token: token,
        peer: peer,
        bound: false,
        used: false
      }
    }

    state = %{job_ref: job, task: %{pid: worker}, invocation: %{action: action}}
    from = fn pid -> {pid, make_ref()} end
    refused = {:error, :document_store_refused}

    assert {:reply, ^refused, ^state} =
             Ipse.Session.handle_call(
               {:extension_workspace_snapshot_bind, job, intent, reader, token},
               from.(impostor),
               state
             )

    assert {:reply, ^refused, ^state} =
             Ipse.Session.handle_call(
               {:extension_workspace_snapshot_bind, job, intent, impostor, token},
               from.(peer),
               state
             )

    bound_action = put_in(action, [:workspace_snapshot_reader, :bound], true)
    bound_state = put_in(state, [:invocation, :action], bound_action)

    assert {:reply, ^refused, ^bound_state} =
             Ipse.Session.handle_call(
               {:extension_workspace_snapshot_peer, job, intent, peer, token},
               from.(impostor),
               bound_state
             )

    assert {:reply, ^refused, ^bound_state} =
             Ipse.Session.handle_call(
               {:extension_workspace_snapshot_peer, job, intent, impostor, token},
               from.(reader),
               bound_state
             )

    used_state =
      put_in(bound_state, [:invocation, :action, :workspace_snapshot_reader, :used], true)

    assert {:reply, ^refused, ^used_state} =
             Ipse.Session.handle_call(
               {:extension_workspace_snapshot_peer, job, intent, peer, token},
               from.(reader),
               used_state
             )
  end

  test "the bounded reader wait withholds on timeout, missing termination, or owner loss" do
    token = make_ref()
    sleeper = spawn(fn -> receive do: (:stop -> :ok) end)
    on_exit(fn -> if Process.alive?(sleeper), do: Process.exit(sleeper, :kill) end)
    ref = Process.monitor(sleeper)
    deadline = System.monotonic_time(:millisecond) + 30

    assert {:unknown, :workspace_check_unconfirmed} =
             Guard.await_snapshot_reader(sleeper, token, ref, deadline)

    ref = Process.monitor(sleeper)
    send(self(), {:workspace_snapshot_result, token, {:ok, :synthetic}})
    deadline = System.monotonic_time(:millisecond) + 30

    assert {:unknown, :workspace_check_unconfirmed} =
             Guard.await_snapshot_reader(sleeper, token, ref, deadline)

    dead = spawn(fn -> :ok end)
    ref = Process.monitor(dead)
    deadline = System.monotonic_time(:millisecond) + 1_000

    assert {:unknown, :workspace_check_unconfirmed} =
             Guard.await_snapshot_reader(dead, token, ref, deadline)
  end

  test "a reader result is accepted only after its producer terminates normally" do
    parent = self()
    token = make_ref()

    reader =
      spawn(fn ->
        receive do
          :go -> send(parent, {:workspace_snapshot_result, token, {:ok, :synthetic}})
        end
      end)

    ref = Process.monitor(reader)
    send(reader, :go)

    assert {:ok, :synthetic} =
             Guard.await_snapshot_reader(
               reader,
               token,
               ref,
               System.monotonic_time(:millisecond) + 1_000
             )
  end
end
