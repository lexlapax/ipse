defmodule Ipse.TextStreamSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, TextStream}

  defmodule Visible do
    def complete(config, _messages, _tools, emit) do
      send(config.test_pid, {:visible_worker, self()})

      content =
        config[:large_delta] ||
          if(config[:flood], do: String.duplicate("a", 65_536) <> "tail", else: "é🙂 visible")

      if config[:flood] do
        emit.({:text, String.duplicate("a", 65_536)})
        send(config.test_pid, :first_chunk_accepted)
        emit.({:text, "tail"})
        send(config.test_pid, :second_chunk_accepted)
      else
        if config[:large_delta] do
          receive do
            :emit_large -> :ok
          end

          emit.({:text, content})
        else
          emit.({:text, "é"})
          emit.({:text, "🙂 visible"})
        end
      end

      {:ok,
       %{
         "role" => "assistant",
         "content" => content,
         "provider_data" => %{"private" => "synthetic-native-reasoning"}
       }, config[:usage] || %{}}
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
      {:ipse_text, server, %{"kind" => "closed", "reason" => reason}}
      when server == handle.server ->
        flunk("Session private stream closed: #{reason}")

      {:ipse_text, server, %{"sequence" => seq} = frame} when server == handle.server ->
        assert :ok = TextStream.ack(handle, seq)
        frames = frames ++ [frame]
        if frame["kind"] == "end", do: frames, else: drain(handle, frames)
    after
      2000 -> flunk("Session private stream did not finish")
    end
  end

  test "a large provider delta preserves Unicode text, source ranges and private native data",
       ctx do
    text = "x" <> String.duplicate("é🙂", 23_000) <> "\u0000end"
    ctx = %{ctx | config: Map.put(ctx.config, :large_delta, text)}
    pid = start(ctx)
    {:ok, handle} = Session.subscribe_text(pid, 2)
    assert :ok = Session.prompt(pid, "large provider delta fixture")
    assert_receive {:visible_worker, worker}, 1000

    assert_receive {:ipse_text, server, %{"kind" => "start", "sequence" => sequence} = first},
                   1000

    assert server == handle.server
    assert :ok = TextStream.ack(handle, sequence)
    send(worker, :emit_large)
    frames = drain(handle, [first])
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    assert_receive {:ipse, ^pid, {:text, ^text}}, 1000
    refute_receive {:ipse, ^pid, {:text, _}}, 20
    assert Enum.map_join(frames, "", &(&1["text"] || "")) == text
    assert List.last(frames)["complete"]

    offset =
      frames
      |> Enum.filter(&(&1["kind"] == "text"))
      |> Enum.reduce(0, fn frame, offset ->
        assert String.valid?(frame["text"])
        assert byte_size(frame["text"]) <= 2048
        assert Ipse.Lifecycle.Ephemeral.valid_frame?(frame)
        assert frame["source"]["start_byte"] == offset
        next = offset + byte_size(frame["text"])
        assert frame["source"]["end_byte"] == next
        next
      end)

    assert offset == byte_size(text)
    refute Jason.encode!(frames) =~ "synthetic-native-reasoning"
    {:ok, events} = Ipse.Journal.load(ctx.dir, Session.info(pid).id)
    {:ok, messages} = Session.restore_context(events)
    assert List.last(messages)["content"] == text
    assert List.last(messages)["provider_data"]["private"] == "synthetic-native-reasoning"
  end

  test "optional backpressure closes delivery but preserves successful inference and native history",
       ctx do
    pid = start(%{ctx | config: Map.put(ctx.config, :flood, true)})
    {:ok, handle} = Session.subscribe_text(pid)
    :ok = Session.prompt(pid, "synthetic optional pressure")
    assert_receive :first_chunk_accepted, 2_000

    assert_receive {:ipse_text, server,
                    %{"kind" => "closed", "reason" => "backpressure_timeout"}},
                   7_000

    assert server == handle.server
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2_000
    {:ok, events} = Ipse.Journal.load(ctx.dir, Session.info(pid).id)
    {:ok, messages} = Session.restore_context(events)
    assert List.last(messages)["content"] == String.duplicate("a", 65_536) <> "tail"
    assert List.last(messages)["provider_data"]["private"] == "synthetic-native-reasoning"
    assert List.last(Session.info(pid).accounting["requests"])["outcome"] == "completed"
  end

  for required <- [false, true] do
    test "broker loss with required=#{required} preserves the selected delivery policy", ctx do
      pid = start(%{ctx | config: Map.put(ctx.config, :large_delta, "gated synthetic text")})
      {:ok, handle} = Session.subscribe_text(pid, 2, required: unquote(required))
      assert :ok = Session.prompt(pid, "synthetic broker loss")
      assert_receive {:visible_worker, worker}, 2_000
      monitor = Process.monitor(handle.server)
      Process.exit(handle.server, :kill)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 2_000
      send(worker, :emit_large)

      if unquote(required) do
        assert_receive {:ipse, ^pid, {:error, error}}, 2_000
        assert error =~ "Required visible-text delivery failed"
        refute error =~ "invalid response"
        assert_receive {:ipse, ^pid, {:done, :error}}, 2_000
      else
        assert_receive {:ipse, ^pid, {:done, :ok}}, 2_000
        assert Session.info(pid).final == "gated synthetic text"
      end

      assert :ok = Session.close(pid)
    end
  end

  test "required completion waits for acknowledgment and retains final usage on refusal and resume",
       ctx do
    config =
      Map.merge(ctx.config, %{
        usage: %{"input_tokens" => 12, "output_tokens" => 3},
        budget: %{
          "version" => 1,
          "max_requests" => 4,
          "max_input_tokens" => 1000,
          "reserve_input_tokens" => 128
        }
      })

    ctx = %{ctx | config: config}
    pid = start(ctx)
    id = Session.info(pid).id
    {:ok, _} = Session.subscribe_text(pid, 1, required: true)
    assert {:error, :invalid_text_policy} = Session.subscribe_text(pid, 1, required: "yes")
    :ok = Session.prompt(pid, "synthetic required completion")
    assert_receive {:ipse, ^pid, {:error, error}}, 7_000
    assert error =~ "Required visible-text delivery failed"
    assert_receive {:ipse, ^pid, {:done, :error}}, 2_000
    request = List.last(Session.info(pid).accounting["requests"])
    assert request["outcome"] == "failed"
    assert :ok = Session.close(pid)
    resumed = start(ctx, id)
    assert Session.info(resumed).phase == :idle
    {:ok, events} = Ipse.Journal.load(ctx.dir, id)
    assert Enum.any?(events, &(get_in(&1, ["usage", "counts", "input_tokens"]) == 12))
    refute Enum.any?(events, &(get_in(&1, ["message", "role"]) == "assistant"))
    assert :ok = Session.close(resumed)
  end

  test "optional end reports transport coverage while required delivery can still refuse admission",
       ctx do
    pid = start(ctx)
    owner = self()

    {:ok, stalled} =
      Task.start(fn ->
        {:ok, _} = Session.subscribe_text(pid, 2, required: true)
        send(owner, :stalled_ready)
        Process.sleep(:infinity)
      end)

    on_exit(fn -> if Process.alive?(stalled), do: Process.exit(stalled, :kill) end)
    assert_receive :stalled_ready, 2000
    {:ok, optional} = Session.subscribe_text(pid)
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "Synthetic transport versus admission")
    frames = drain(optional)
    assert %{"kind" => "end", "outcome" => "completed", "complete" => true} = List.last(frames)
    refute_receive {:ipse, ^pid, {:done, _}}, 20
    assert_receive {:ipse, ^pid, {:error, error}}, 7000
    assert error =~ "Required visible-text delivery failed"
    assert_receive {:ipse, ^pid, {:done, :error}}, 1000
    assert List.last(Session.info(pid).accounting["requests"])["outcome"] == "failed"
    {:ok, events} = Ipse.Journal.load(ctx.dir, id)
    {:ok, messages} = Session.restore_context(events)
    refute Enum.any?(messages, &(&1["role"] == "assistant"))
    assert :ok = Session.close(pid)
  end

  test "a healthy explicitly required client acknowledges completion before inference is admitted",
       ctx do
    pid = start(ctx)
    parent = self()

    client =
      Task.async(fn ->
        {:ok, handle} = Session.subscribe_text(pid, 2, required: true)
        send(parent, :required_ready)
        receive_required(handle)
      end)

    assert_receive :required_ready, 2_000
    :ok = Session.prompt(pid, "synthetic required delivery")
    assert :ok = Task.await(client, 2_000)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2_000
    assert :ok = Session.close(pid)
  end

  defp receive_required(handle) do
    receive do
      {:ipse_text, server, %{"sequence" => sequence} = frame} when server == handle.server ->
        :ok = TextStream.ack(handle, sequence)
        if frame["kind"] == "end", do: :ok, else: receive_required(handle)
    after
      2_000 -> flunk("required delivery did not finish")
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
