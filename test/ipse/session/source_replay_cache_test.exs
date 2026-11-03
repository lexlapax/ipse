defmodule Ipse.Session.SourceReplayCacheTest do
  use ExUnit.Case, async: true

  alias Ipse.Session.{Input, Resources, SourceReplayCache, SourceWindow}
  @id String.duplicate("a", 32)
  @other_id String.duplicate("b", 32)

  defp events, do: [%{"type" => "session", "metadata" => %{}}]

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
