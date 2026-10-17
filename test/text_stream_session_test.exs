defmodule Ipse.TextStreamSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, TextStream}

  defmodule Visible do
    def complete(config, _messages, _tools, emit) do
      send(config.test_pid, {:visible_worker, self()})

      if config[:flood] do
        emit.({:text, String.duplicate("a", 65_536)})
        send(config.test_pid, :first_chunk_accepted)
        emit.({:text, "tail"})
        send(config.test_pid, :second_chunk_accepted)
      else
        emit.({:text, "é"})
        emit.({:text, "🙂 visible"})
      end

      {:ok,
       %{
         "role" => "assistant",
         "content" => "é🙂 visible",
         "provider_data" => %{"private" => "synthetic-native-reasoning"}
       }, %{}}
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-text-session-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    config = %{
      provider: :ollama,
      model: "fixture",
      provider_module: Visible,
      home: Path.join(root, "home"),
      test_pid: self(),
      approval: :deny
    }

    %{root: root, dir: Path.join(root, "state"), config: config}
  end

  defp start(ctx, id \\ nil) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: ctx.config, cwd: ctx.root, state_dir: ctx.dir, subscriber: self(), id: id}
      )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    pid
  end

  defp drain(handle, frames \\ []) do
    receive do
      {:ipse_text, server, %{"sequence" => seq} = frame} when server == handle.server ->
        assert :ok = TextStream.ack(handle, seq)
        frames = frames ++ [frame]
        if frame["kind"] == "end", do: frames, else: drain(handle, frames)
    after
      2000 -> flunk("Session private stream did not finish")
    end
  end

  test "subscriptions are opt-in and visible text preserves final native data", ctx do
    pid = start(ctx)
    assert :sys.get_state(pid).text_stream == nil
    assert :ok = Session.prompt(pid, "ordinary")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    assert :sys.get_state(pid).text_stream == nil
    {:ok, handle} = Session.subscribe_text(pid)
    assert :ok = Session.prompt(pid, "private subscription")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    frames = drain(handle)
    assert Enum.map_join(frames, "", &(&1["text"] || "")) == "é🙂 visible"
    refute Jason.encode!(frames) =~ "synthetic-native-reasoning"
    assert List.last(frames)["complete"]
    info = Session.info(pid)
    last = List.last(info.accounting["requests"])
    assert hd(frames)["request_id"] == last["request_id"]
    {:ok, events} = Ipse.Journal.load(ctx.dir, info.id)
    {:ok, messages} = Session.restore_context(events)
    assert List.last(messages)["provider_data"]["private"] == "synthetic-native-reasoning"
    assert :ok = TextStream.unsubscribe(handle)
    assert_receive {:ipse_text, _, %{"kind" => "closed", "reason" => "unsubscribed"}}
    :ok = Session.close(pid)
    bytes = File.read!(Path.join(ctx.dir, info.id <> ".jsonl"))
    resumed = start(ctx, info.id)
    assert :sys.get_state(resumed).text_stream == nil
    assert File.read!(Path.join(ctx.dir, info.id <> ".jsonl")) == bytes
    refute_receive {:ipse_text, _, _}, 20
  end

  test "cancel remains responsive while a private consumer backpressures its provider", ctx do
    ctx = %{ctx | config: Map.put(ctx.config, :flood, true)}
    pid = start(ctx)
    {:ok, handle} = Session.subscribe_text(pid)
    :ok = Session.prompt(pid, "slow consumer fixture")
    assert_receive {:visible_worker, worker}, 2000
    assert_receive :first_chunk_accepted, 2000
    refute_receive :second_chunk_accepted, 20
    assert Session.subscribe_text(pid) == {:error, :busy}
    monitor = Process.monitor(worker)
    started = System.monotonic_time(:millisecond)
    assert :ok = Session.cancel(pid)
    assert System.monotonic_time(:millisecond) - started < 1000
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1000
    assert_receive {:ipse, ^pid, {:done, :cancelled}}, 1000
    frames = drain(handle)
    assert Enum.map_join(frames, "", &(&1["text"] || "")) == String.duplicate("a", 65_536)
    assert List.last(frames)["outcome"] == "cancelled"
    refute List.last(frames)["complete"]

    assert [%{"outcome" => "cancelled", "finality" => "partial"}] =
             Session.info(pid).accounting["requests"]
  end

  test "session death closes private resources and idle resume never replays live text", ctx do
    ctx = %{ctx | config: Map.put(ctx.config, :flood, true)}
    pid = start(ctx)
    {:ok, handle} = Session.subscribe_text(pid)
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "owner fixture")
    assert_receive {:visible_worker, worker}, 2000
    assert_receive :first_chunk_accepted, 2000
    refute_receive :second_chunk_accepted, 20
    monitor = Process.monitor(handle.server)
    worker_ref = Process.monitor(worker)
    Process.exit(pid, :kill)

    assert_receive {:ipse_text, _,
                    %{"kind" => "closed", "reason" => "owner_down", "complete" => false}},
                   2000

    assert_receive {:DOWN, ^monitor, :process, _, _}, 2000
    assert_receive {:DOWN, ^worker_ref, :process, _, _}, 2000
    resumed = start(ctx, id)
    assert Session.info(resumed).phase == :idle
    assert [%{"outcome" => "unknown"}] = Session.info(resumed).accounting["requests"]
    # Drain the one already-delivered start notification; there is no text replay.
    assert_receive {:ipse_text, _, %{"kind" => "start"}}, 0
    refute_receive {:ipse_text, _, %{"kind" => "text"}}, 20
    assert :sys.get_state(resumed).text_stream == nil
  end
end
