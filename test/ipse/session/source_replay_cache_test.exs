defmodule Ipse.Session.SourceReplayCacheTest do
  use ExUnit.Case, async: true

  alias Ipse.Session.{Input, Resources, SourceReplayCache, SourceWindow}
  @id String.duplicate("a", 32)
  @other_id String.duplicate("b", 32)

  defp events, do: [%{"type" => "session", "metadata" => %{}}]

  defp with_root(fun) do
    {:ok, scope} = Resources.start(self())
    :ok = Resources.attach(scope, self())
    previous = Resources.bind(scope)

    try do
      fun.(scope)
    after
      Resources.bind(previous)
      if Process.alive?(scope), do: Resources.close(scope)
    end
  end

  defp with_slot_scope(fun) do
    {:ok, scope} = Resources.start_with_source_replay_cache(self())
    :ok = Resources.attach(scope, self())
    previous = Resources.bind(scope)

    try do
      fun.(scope)
    after
      Resources.bind(previous)
      assert :ok = Resources.close(scope)
    end
  end

  test "slot and controlled scopes borrow the original job cache before the gate warms it" do
    with_root(fn original ->
      assert :sys.get_state(original).source_replay_cache == nil
      parent = self()

      task =
        Resources.async(fn ->
          with_slot_scope(fn _ ->
            {:ok, cache} = Resources.source_replay_cache()
            send(parent, {:slot_cache, cache})
            receive do: (:gate_warmed -> :ok)

            Resources.controlled_owned_effect(
              fn ->
                assert {:ok, ^cache} = Resources.source_replay_cache()
                assert {:ok, index} = SourceReplayCache.restore(cache, events(), @id)
                changed = put_in(events(), [Access.at(0), "metadata", "probe"], true)
                assert {:ok, _} = SourceReplayCache.restore(cache, changed, @id)
                {cache, index}
              end,
              5_000
            )
          end)
        end)

      assert_receive {:slot_cache, cache}
      assert {:ok, ^cache} = Resources.source_replay_cache()
      assert :sys.get_state(cache.pid).entries == %{}
      assert {:ok, original_index} = SourceReplayCache.restore(cache, events(), @id)
      send(task.pid, :gate_warmed)
      assert {:ok, {^cache, child_index}} = Task.await(task, 10_000)
      assert child_index.window_id != original_index.window_id
      assert child_index.secret != original_index.secret
      assert map_size(:sys.get_state(cache.pid).entries) == 2
      assert Process.alive?(cache.pid)
      assert {:ok, _} = SourceReplayCache.restore(cache, events(), @id)
    end)
  end

  test "killing a controlled borrower leaves the original cache alive and reusable" do
    with_root(fn _ ->
      parent = self()

      task =
        Resources.async(fn ->
          with_slot_scope(fn _ ->
            Resources.controlled_owned_effect(
              fn ->
                {:ok, cache} = Resources.source_replay_cache()
                {:ok, _} = SourceReplayCache.restore(cache, events(), @id)
                send(parent, {:borrower, self(), cache})
                Process.sleep(:infinity)
              end,
              5_000
            )
          end)
        end)

      assert_receive {:borrower, peer, cache}
      Process.exit(peer, :kill)
      assert Task.await(task, 10_000) == {:unknown, :effect_interrupted}
      assert Process.alive?(cache.pid)
      assert {:ok, ^cache} = Resources.source_replay_cache()
      assert {:ok, _} = SourceReplayCache.restore(cache, events(), @id)
    end)
  end

  test "a foreign current scope and a different owner cannot borrow the job cache" do
    with_root(fn scope ->
      {:ok, cache} = Resources.source_replay_cache()

      foreign =
        Task.async(fn ->
          Resources.bind(scope)
          Resources.start_with_source_replay_cache(self())
        end)

      assert Task.await(foreign) == {:error, :cleanup_scope_closed}

      assert Resources.start_with_source_replay_cache(foreign.pid) ==
               {:error, :cleanup_scope_closed}

      assert Process.alive?(cache.pid)
    end)
  end

  test "a dead borrowed cache is refused rather than reowned by the slot or its child" do
    with_root(fn _ ->
      parent = self()

      task =
        Resources.async(fn ->
          with_slot_scope(fn _ ->
            {:ok, cache} = Resources.source_replay_cache()
            send(parent, {:borrow_ready, cache})
            receive do: (:cache_killed -> :ok)
            assert {:error, :cleanup_scope_closed} = Resources.source_replay_cache()
            Resources.controlled_owned_effect(fn -> Resources.source_replay_cache() end, 5_000)
          end)
        end)

      assert_receive {:borrow_ready, cache}
      monitor = Process.monitor(cache.pid)
      Process.exit(cache.pid, :kill)
      assert_receive {:DOWN, ^monitor, :process, _, :killed}
      send(task.pid, :cache_killed)
      assert Task.await(task, 10_000) == {:ok, {:error, :cleanup_scope_closed}}
    end)
  end

  test "ordinary and parentless scopes keep independent owned cache lifetimes" do
    with_root(fn _ ->
      {:ok, parent_cache} = Resources.source_replay_cache()
      {:ok, ordinary} = Resources.start(self())
      previous = Resources.bind(ordinary)
      {:ok, own_cache} = Resources.source_replay_cache()
      Resources.bind(previous)
      assert own_cache.pid != parent_cache.pid
      assert :ok = Resources.close(ordinary)
      refute Process.alive?(own_cache.pid)
      assert Process.alive?(parent_cache.pid)
    end)

    previous = Resources.bind(nil)

    try do
      {:ok, scope} = Resources.start_with_source_replay_cache(self())
      Resources.bind(scope)
      {:ok, cache} = Resources.source_replay_cache()
      assert :ok = Resources.close(scope)
      refute Process.alive?(cache.pid)
    after
      Resources.bind(previous)
    end
  end

  test "a controlled child owns its cache only when the parent had none" do
    with_root(fn scope ->
      assert {:ok, cache} =
               Resources.controlled_owned_effect(
                 fn ->
                   {:ok, cache} = Resources.source_replay_cache()
                   cache
                 end,
                 5_000
               )

      refute Process.alive?(cache.pid)
      assert :sys.get_state(scope).source_replay_cache == nil
    end)
  end

  test "loss of the original owner stops its cache and the three-level controlled peer" do
    parent = self()

    owner =
      spawn(fn ->
        with_root(fn root ->
          Resources.async(fn ->
            with_slot_scope(fn slot ->
              Resources.controlled_owned_effect(
                fn ->
                  {:ok, cache} = Resources.source_replay_cache()
                  send(parent, {:owned_tree, root, slot, self(), cache})
                  Process.sleep(:infinity)
                end,
                20_000
              )
            end)
          end)

          Process.sleep(:infinity)
        end)
      end)

    assert_receive {:owned_tree, root, slot, peer, cache}, 2_000
    watches = Enum.map([root, slot, peer, cache.pid], &{&1, Process.monitor(&1)})
    :ok = :sys.suspend(cache.pid)
    Process.exit(owner, :kill)

    for {pid, ref} <- watches do
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 5_000
    end
  end

  test "reconstructs its own result, distinguishes changed input and refreshes index secrets" do
    assert {:ok, cache} = SourceReplayCache.start(self())
    on_exit(fn -> if Process.alive?(cache.pid), do: Process.exit(cache.pid, :kill) end)

    assert {:ok, first} = SourceReplayCache.restore(cache, events(), @id)
    assert {:ok, second} = SourceReplayCache.restore(cache, events(), @id)
    assert first.window_id != second.window_id and first.secret != second.secret

    assert Map.drop(Map.from_struct(first), [:window_id, :secret]) ==
             Map.drop(Map.from_struct(second), [:window_id, :secret])

    assert map_size(:sys.get_state(cache.pid).entries) == 1
    assert {:ok, other} = SourceReplayCache.restore(cache, events(), @other_id)
    assert other.session_id == @other_id
    assert map_size(:sys.get_state(cache.pid).entries) == 2

    invalid = [%{"type" => "session", "metadata" => %{"semantic_admission" => "forged"}}]
    assert {:error, :source_replay_unavailable} = SourceReplayCache.restore(cache, invalid, @id)
    assert map_size(:sys.get_state(cache.pid).entries) == 2
    assert {:error, :source_replay_unavailable} = GenServer.call(cache.pid, {:insert, first})
  end

  test "cache dies with its owner and cannot outlive task cleanup" do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, cache} = SourceReplayCache.start(self())
        send(parent, {:cache, cache})

        receive do
          :finish -> :ok
        end
      end)

    assert_receive {:cache, cache}
    monitor = Process.monitor(cache.pid)
    send(owner, :finish)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}

    owner =
      spawn(fn ->
        {:ok, cache} = SourceReplayCache.start(self())
        send(parent, {:busy_cache, cache})
        Process.sleep(:infinity)
      end)

    assert_receive {:busy_cache, busy_cache}
    :ok = :sys.suspend(busy_cache.pid)
    monitor = Process.monitor(busy_cache.pid)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}

    assert {:ok, scope} = Resources.start(self())
    Resources.bind(scope)
    on_exit(fn -> Process.delete({Resources, :scope}) end)
    assert {:ok, scoped_cache} = Resources.source_replay_cache()
    assert {:ok, ^scoped_cache} = Resources.source_replay_cache()
    monitor = Process.monitor(scoped_cache.pid)

    task =
      Task.async(fn ->
        Resources.bind(scope)
        Resources.source_replay_cache()
      end)

    assert Task.await(task) == {:error, :cleanup_scope_closed}
    assert :ok = Resources.close(scope)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}
  end

  test "cache retains at most 128 reconstructed indexes and respects its byte budget" do
    assert {:ok, cache} = SourceReplayCache.start(self())

    for n <- 1..130 do
      id = n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")
      assert {:ok, %{session_id: ^id}} = SourceReplayCache.restore(cache, events(), id)
    end

    state = :sys.get_state(cache.pid)
    assert map_size(state.entries) == 128
    assert state.bytes <= 8_388_608
  end

  test "large or concurrent inputs do not enter the cache mailbox" do
    assert {:ok, cache} = SourceReplayCache.start(self())
    :atomics.put(cache.gate, 1, 1)
    assert {:ok, _} = SourceReplayCache.restore(cache, events(), @id)
    assert map_size(:sys.get_state(cache.pid).entries) == 0
    :atomics.put(cache.gate, 1, 0)

    oversized = [
      %{"type" => "session", "metadata" => %{"padding" => String.duplicate("x", 8_388_608)}}
    ]

    assert :erlang.external_size(oversized) > 8_388_608
    :ok = :sys.suspend(cache.pid)

    try do
      task = Task.async(fn -> SourceReplayCache.restore(cache, oversized, @id) end)
      assert {:ok, {:ok, _}} = Task.yield(task, 10_000)
      assert Process.info(cache.pid, :message_queue_len) == {:message_queue_len, 0}
    after
      :sys.resume(cache.pid)
    end

    assert map_size(:sys.get_state(cache.pid).entries) == 0
  end

  test "a killed cache caller cannot strand later source reconstruction" do
    assert {:ok, cache} = SourceReplayCache.start(self())
    :ok = :sys.suspend(cache.pid)
    caller = spawn(fn -> SourceReplayCache.restore(cache, events(), @id) end)
    monitor = Process.monitor(caller)

    try do
      held =
        Enum.reduce_while(1..500, false, fn _, _ ->
          if :atomics.get(cache.gate, 1) == 1 do
            {:halt, true}
          else
            Process.sleep(5)
            {:cont, false}
          end
        end)

      assert held
      Process.exit(caller, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^caller, :killed}
      assert {:ok, %{session_id: @id}} = SourceReplayCache.restore(cache, events(), @id)
      assert :atomics.get(cache.gate, 1) == 1
    after
      :sys.resume(cache.pid)
    end
  end

  test "cached source text does not retain the journal's larger backing binary" do
    assert {:ok, cache} = SourceReplayCache.start(self())
    text = :binary.part(:binary.copy("x", 16_384), 0, 128)
    assert :binary.referenced_byte_size(text) == 16_384

    journal = [
      %{"type" => "session", "metadata" => %{"source_layout" => SourceWindow.layout()}},
      Input.received(@id, Ipse.Usage.id(), text, text, nil),
      %{"type" => "message", "message" => %{"role" => "user", "content" => text}}
    ]

    assert {:ok, _} = SourceReplayCache.restore(cache, journal, @id)
    [%{index: index}] = :sys.get_state(cache.pid).entries |> Map.values()
    [entry] = Map.values(index.entries)
    assert entry.text == text
    assert :binary.referenced_byte_size(entry.text) == byte_size(entry.text)
  end
end
