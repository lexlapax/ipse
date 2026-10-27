defmodule ControlledEffectDiagnosticTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Resources

  setup do
    {:ok, _} = Application.ensure_all_started(:ipse)
    {:ok, root} = Resources.start(self())

    worker =
      spawn(fn ->
        receive do
          {:run, parent, timeout, mode} ->
            Resources.bind(root)

            value =
              Resources.controlled_file_effect(
                fn ->
                  scope = Resources.current()
                  peer = self()

                  resource =
                    spawn(fn ->
                      Resources.bind(scope)
                      {:ok, ticket} = Resources.register(:lock)
                      send(parent, {:child_resource, self(), peer, ticket.id})

                      receive do
                        {:ipse_cancel_resource, id} when id == ticket.id ->
                          if mode == :confirm,
                            do: Resources.closed(ticket, :ok),
                            else: receive(do: (:never -> :ok))
                      end
                    end)

                  send(parent, {:effect_running, self(), resource})
                  receive do: (:never -> :ok)
                end,
                timeout
              )

            send(parent, {:effect_result, value})
        end
      end)

    :ok = Resources.attach(root, worker)

    on_exit(fn ->
      if Process.alive?(worker), do: Process.exit(worker, :kill)
      if Process.alive?(root), do: Resources.close(root)
    end)

    %{root: root, worker: worker}
  end

  test "timeout kills peer and waits for its resource receipt", c do
    send(c.worker, {:run, self(), 300, :confirm})
    assert_receive {:child_resource, resource, peer, _}, 3000
    ref = Process.monitor(resource)
    assert_receive {:effect_result, {:unknown, :effect_interrupted}}, 7000
    refute Process.alive?(peer)
    assert_receive {:DOWN, ^ref, :process, ^resource, _}, 1000
  end

  test "a withheld resource receipt cannot confirm cleanup", c do
    send(c.worker, {:run, self(), 1000, :withhold})
    assert_receive {:child_resource, resource, peer, _}, 3000
    [{token, entry}] = Map.to_list(:sys.get_state(c.root).child_tokens)
    assert :unconfirmed == GenServer.call(c.root, {:child_cancelled, token, peer})
    send(c.worker, {:child_scope_finished, make_ref(), entry.child, :ok})
    send(c.worker, {:child_scope_finished, token, self(), :ok})

    try do
      assert_receive {:effect_result, {:unknown, :cleanup_unconfirmed}}, 9000
    after
      Process.exit(resource, :kill)
    end
  end
end

defmodule ControlledEffectNativeDiagnosticTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Resources
  alias Ipse.Runner.Transaction, as: T

  test "deadline awaits native controller cleanup before allowing a fresh lock" do
    {:ok, _} = Application.ensure_all_started(:ipse)
    dir = Path.join(Path.expand(System.tmp_dir!()), "controlled-native-" <> Ipse.Usage.id())
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)
    path = Path.join(dir, ".lock")
    {:ok, root} = Resources.start(self())
    parent = self()

    worker =
      spawn(fn ->
        receive do
          :run ->
            Resources.bind(root)

            outcome =
              Resources.controlled_file_effect(
                fn ->
                  result = T.acquire(path)
                  send(parent, {:native_acquire, result})
                  {:ok, cap} = result
                  send(parent, {:native_held, self(), cap.controller})
                  receive do: (:never -> :ok)
                end,
                400
              )

            send(parent, {:native_outcome, outcome})
        end
      end)

    try do
      :ok = Resources.attach(root, worker)
      send(worker, :run)
      assert_receive {:native_held, peer, controller}, 5000
      ref = Process.monitor(controller)
      assert_receive {:native_outcome, {:unknown, :effect_interrupted}}, 10000
      refute Process.alive?(peer)
      assert_receive {:DOWN, ^ref, :process, ^controller, _}, 3000
      assert {:ok, fresh} = T.acquire(path)
      assert :ok = T.release(fresh)
    after
      if Process.alive?(worker), do: Process.exit(worker, :kill)
      if Process.alive?(root), do: Resources.close(root)
      File.rm_rf!(dir)
    end
  end
end

defmodule ControlledEffectIsolationDiagnosticTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Resources

  test "timing out one child does not close a sibling" do
    {:ok, _} = Application.ensure_all_started(:ipse)
    {:ok, root} = Resources.start(self())
    parent = self()

    worker =
      spawn(fn ->
        receive do
          :run ->
            Resources.bind(root)
            sibling = Resources.async(fn -> receive do: (:stop -> :done) end)
            result = Resources.controlled_file_effect(fn -> receive do: (:never -> :ok) end, 200)
            send(parent, {:isolation, result, sibling.pid, Process.alive?(sibling.pid)})
            receive do: (:finish -> :ok)
        end
      end)

    try do
      :ok = Resources.attach(root, worker)
      send(worker, :run)
      assert_receive {:isolation, {:unknown, :effect_interrupted}, sibling, true}, 7000
      assert Process.alive?(sibling)
      send(sibling, :stop)
      send(worker, :finish)
    after
      if Process.alive?(worker), do: Process.exit(worker, :kill)
      if Process.alive?(root), do: Resources.close(root)
    end
  end
end

defmodule ControlledEffectOwnerLossDiagnosticTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Resources

  test "root owner death stops the peer even while root cleanup is waiting" do
    {:ok, _} = Application.ensure_all_started(:ipse)
    observer = self()
    owner = spawn(fn -> receive do: (:never -> :ok) end)
    {:ok, root} = Resources.start(owner)

    resource =
      spawn(fn ->
        Resources.bind(root)
        {:ok, ticket} = Resources.register(:lock)
        send(observer, {:dummy_ready, self()})

        receive do
          {:ipse_cancel_resource, id} when id == ticket.id ->
            send(observer, {:cleanup_blocked, self()})
            receive do: (:release -> :ok)
            Resources.closed(ticket, :ok)
        end
      end)

    worker =
      spawn(fn ->
        receive do
          :run ->
            Resources.bind(root)

            Resources.controlled_file_effect(
              fn ->
                send(observer, {:active_peer, self()})
                receive do: (:never -> :ok)
              end,
              5000
            )
        end
      end)

    try do
      assert_receive {:dummy_ready, ^resource}, 3000
      :ok = Resources.attach(root, worker)
      send(worker, :run)
      assert_receive {:active_peer, peer}, 3000
      ref = Process.monitor(peer)
      Process.exit(owner, :kill)
      assert_receive {:cleanup_blocked, ^resource}, 3000
      assert_receive {:DOWN, ^ref, :process, ^peer, _}, 1500
      send(resource, :release)
    after
      if Process.alive?(owner), do: Process.exit(owner, :kill)
      if Process.alive?(worker), do: Process.exit(worker, :kill)
      if Process.alive?(resource), do: Process.exit(resource, :kill)
      if Process.alive?(root), do: Resources.close(root)
    end
  end
end

defmodule ControlledEffectStoppedNativeDiagnosticTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Resources
  alias Ipse.Runner.Transaction, as: T

  test "stopped actual native controller cannot yield confirmed cleanup" do
    {:ok, _} = Application.ensure_all_started(:ipse)
    dir = Path.join(Path.expand(System.tmp_dir!()), "controlled-stopped-" <> Ipse.Usage.id())
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)
    path = Path.join(dir, ".lock")
    {:ok, root} = Resources.start(self())
    parent = self()

    worker =
      spawn(fn ->
        receive do
          :run ->
            Resources.bind(root)

            outcome =
              Resources.controlled_file_effect(
                fn ->
                  {:ok, cap} = T.acquire(path)
                  send(parent, {:stopped_native_held, self(), cap.controller})
                  receive do: (:never -> :ok)
                end,
                1000
              )

            send(parent, {:stopped_native_outcome, outcome})
        end
      end)

    :ok = Resources.attach(root, worker)
    send(worker, :run)
    assert_receive {:stopped_native_held, _peer, controller}, 5000
    port = :sys.get_state(controller).port
    {:os_pid, helper} = Port.info(port, :os_pid)
    assert {_, 0} = System.cmd("kill", ["-STOP", Integer.to_string(helper)])

    try do
      assert_receive {:stopped_native_outcome, {:unknown, :cleanup_unconfirmed}}, 10000
    after
      System.cmd("kill", ["-KILL", Integer.to_string(helper)], stderr_to_stdout: true)
      if Process.alive?(worker), do: Process.exit(worker, :kill)
      if Process.alive?(root), do: Resources.close(root)
      File.rm_rf!(dir)
    end
  end
end

defmodule ControlledEffectScopeDeathDiagnosticTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Resources

  test "lost child scope kills peer and never reports confirmed cleanup" do
    {:ok, _} = Application.ensure_all_started(:ipse)
    {:ok, root} = Resources.start(self())
    parent = self()

    worker =
      spawn(fn ->
        receive do
          :run ->
            Resources.bind(root)

            outcome =
              Resources.controlled_file_effect(
                fn ->
                  send(parent, {:owned_peer_and_scope, self(), Resources.current()})
                  receive do: (:never -> :ok)
                end,
                5000
              )

            send(parent, {:scope_loss_outcome, outcome})
            receive do: (:finish -> :ok)
        end
      end)

    try do
      :ok = Resources.attach(root, worker)
      send(worker, :run)
      assert_receive {:owned_peer_and_scope, peer, child}, 3000
      ref = Process.monitor(peer)
      Process.exit(child, :kill)
      assert_receive {:DOWN, ^ref, :process, ^peer, _}, 3000
      assert_receive {:scope_loss_outcome, {:unknown, :cleanup_unconfirmed}}, 9000
      send(worker, :finish)
    after
      if Process.alive?(worker), do: Process.exit(worker, :kill)
      if Process.alive?(root), do: Resources.close(root)
    end
  end
end

defmodule ControlledEffectNestingDiagnosticTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Resources

  test "ordinary nested effects remain inline while nested controlled scopes refuse" do
    {:ok, _} = Application.ensure_all_started(:ipse)
    {:ok, root} = Resources.start(self())
    parent = self()

    worker =
      spawn(fn ->
        receive do
          :run ->
            Resources.bind(root)

            outcome =
              Resources.controlled_file_effect(
                fn ->
                  peer = self()
                  assert Resources.file_effect(fn -> self() end) == peer

                  assert {:error, :nested_controlled_effect} =
                           Resources.controlled_file_effect(
                             fn ->
                               send(parent, :unexpected_nested_effect)
                             end,
                             1000
                           )

                  :ok
                end,
                3000
              )

            send(parent, {:nesting_result, outcome})
            receive do: (:done -> :ok)
        end
      end)

    try do
      :ok = Resources.attach(root, worker)
      send(worker, :run)
      assert_receive {:nesting_result, {:ok, :ok}}, 5000
      refute_receive :unexpected_nested_effect, 100
      send(worker, :done)
    after
      if Process.alive?(worker), do: Process.exit(worker, :kill)
      if Process.alive?(root), do: Resources.close(root)
    end
  end
end
