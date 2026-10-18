defmodule Ipse.TextStreamTest do
  use ExUnit.Case, async: true
  alias Ipse.{TextStream, Usage}

  setup do
    {:ok, server} = TextStream.start(self(), Usage.id())
    {:ok, handle} = TextStream.subscribe(server, self())
    owner = self()
    {:ok, producer} = Task.start(fn -> produce(server, owner) end)

    on_exit(fn ->
      if Process.alive?(producer), do: Process.exit(producer, :kill)
    end)

    request = Usage.id()
    :ok = TextStream.begin(server, request, producer)
    %{server: server, handle: handle, producer: producer, request: request}
  end

  defp produce(server, owner) do
    receive do
      {:push, ref, request, text} ->
        result = TextStream.push(server, request, text)
        send(owner, {:push_result, ref, result})
        produce(server, owner)
    end
  end

  defp push(ctx, text) do
    ref = make_ref()
    send(ctx.producer, {:push, ref, ctx.request, text})
    assert_receive {:push_result, ^ref, :ok}, 1000
  end

  defp drain(ctx, frames \\ []) do
    receive do
      {:ipse_text, server, %{"sequence" => sequence} = frame} when server == ctx.server ->
        assert frame["request_id"] == ctx.request
        assert frame["stream_id"] == ctx.request
        assert frame["subscription_id"] == ctx.handle.subscription_id
        assert :ok = Ipse.Extension.validate(frame)

        if frame["kind"] == "text" do
          assert byte_size(frame["text"]) <= 2048
          assert String.valid?(frame["text"])
        end

        assert :ok = TextStream.ack(ctx.handle, sequence)
        frames = frames ++ [frame]
        if frame["kind"] == "end", do: frames, else: drain(ctx, frames)
    after
      2000 -> flunk("Text stream did not finish")
    end
  end

  defp text(frames), do: Enum.map_join(frames, "", &(&1["text"] || ""))

  test "coalescing and bounded Unicode frames preserve exact visible concatenation", ctx do
    chunks = [String.duplicate(<<0>>, 2048), "begin", String.duplicate("é🙂\n", 3000), "\u0000end"]
    Enum.each(chunks, &push(ctx, &1))
    assert :ok = TextStream.finish(ctx.server, ctx.request, "completed")
    frames = drain(ctx)
    assert text(frames) == Enum.join(chunks)
    assert hd(frames)["kind"] == "start"
    assert List.last(frames)["complete"]
    assert Enum.map(frames, & &1["sequence"]) == Enum.to_list(1..length(frames))
  end

  test "private status and caller-bound acknowledgment reject stale or forged credits", ctx do
    push(ctx, "synthetic-private-visible-text")
    assert_receive {:ipse_text, _, %{"sequence" => 1}}
    status = :sys.get_status(ctx.server)
    refute inspect(status) =~ "synthetic-private-visible-text"
    forged = Task.async(fn -> TextStream.ack(ctx.handle, 1) end)
    assert Task.await(forged) == {:error, :invalid_text_acknowledgment}
    assert TextStream.push(ctx.server, ctx.request, "forged") == {:error, :text_stream_refused}
    assert TextStream.ack(ctx.handle, 1) == :ok
    assert TextStream.ack(ctx.handle, 1) == {:error, :invalid_text_acknowledgment}
    assert :ok = TextStream.finish(ctx.server, ctx.request, "completed")
    assert text(drain(ctx)) == "synthetic-private-visible-text"
  end

  test "owner admission checks live enrollment rather than consumer process existence", ctx do
    assert TextStream.enrolled?(ctx.server, ctx.handle.subscription_id, self())
    owner = self()

    outsider =
      Task.async(fn -> TextStream.enrolled?(ctx.server, ctx.handle.subscription_id, owner) end)

    refute Task.await(outsider)
    assert :ok = TextStream.unsubscribe(ctx.handle)
    assert Process.alive?(self())
    refute TextStream.enrolled?(ctx.server, ctx.handle.subscription_id, self())
    refute TextStream.enrolled?(nil, ctx.handle.subscription_id, self())
  end

  test "full buffers backpressure the producer and acknowledgment resumes it losslessly", ctx do
    chunk = String.duplicate("a", 65_536)
    push(ctx, chunk)
    ref = make_ref()
    send(ctx.producer, {:push, ref, ctx.request, "tail"})
    refute_receive {:push_result, ^ref, _}, 20
    assert_receive {:ipse_text, _, %{"sequence" => 1} = start}
    assert :ok = TextStream.ack(ctx.handle, 1)
    assert_receive {:push_result, ^ref, :ok}, 1000
    :ok = TextStream.finish(ctx.server, ctx.request, "completed")
    assert text(drain(ctx, [start])) == chunk <> "tail"
  end

  test "cancel releases a blocked producer and marks the accepted stream incomplete", ctx do
    push(ctx, String.duplicate("a", 65_536))
    ref = make_ref()
    send(ctx.producer, {:push, ref, ctx.request, "unaccepted"})
    refute_receive {:push_result, ^ref, _}, 20
    assert :ok = TextStream.finish(ctx.server, ctx.request, "cancelled")
    assert_receive {:push_result, ^ref, {:error, :text_request_finished}}, 1000
    frames = drain(ctx)
    assert byte_size(text(frames)) == 65_536
    refute List.last(frames)["complete"]
    assert List.last(frames)["outcome"] == "cancelled"
  end

  test "slow consumer gets explicit bounded shutdown rather than silent truncation", ctx do
    push(ctx, String.duplicate("a", 65_536))
    ref = make_ref()
    send(ctx.producer, {:push, ref, ctx.request, "tail"})

    assert_receive {:ipse_text, _,
                    %{
                      "kind" => "closed",
                      "complete" => false,
                      "reason" => "backpressure_timeout",
                      "unsent_bytes" => 65_536,
                      "pending_bytes" => 4
                    }},
                   6000

    assert_receive {:push_result, ^ref, :ok}, 1000
    assert :ok = TextStream.finish(ctx.server, ctx.request, "failed")
    refute_receive {:ipse_text, _, %{"kind" => "text"}}, 0
  end

  test "stalled control frames are bounded across consecutive requests", ctx do
    :ok = TextStream.finish(ctx.server, ctx.request, "completed")

    for _ <- 1..40 do
      request = Usage.id()
      :ok = TextStream.begin(ctx.server, request, ctx.producer)
      :ok = TextStream.finish(ctx.server, request, "completed")
    end

    assert_receive {:ipse_text, _, %{"kind" => "start"}}

    assert_receive {:ipse_text, _,
                    %{
                      "kind" => "closed",
                      "reason" => "control_queue_full",
                      "unsent_frames" => 64,
                      "complete" => false
                    }}

    refute_receive {:ipse_text, _, _}, 0
  end

  test "a slow optional peer detaches while a required peer finishes losslessly" do
    owner = self()
    {:ok, server} = TextStream.start(owner, Usage.id())
    {:ok, optional} = TextStream.subscribe(server, owner)

    consumer =
      spawn(fn ->
        receive do
          {:handle, handle} -> required_consume(handle, owner, [])
        end
      end)

    {:ok, required} = TextStream.subscribe(server, consumer, 1, true)
    on_exit(fn -> if Process.alive?(consumer), do: Process.exit(consumer, :kill) end)
    send(consumer, {:handle, required})
    request = Usage.id()

    {:ok, producer} =
      Task.start(fn ->
        receive do
          :go ->
            chunk = String.duplicate("a", 65_536)
            :ok = TextStream.push(server, request, chunk)

            receive do
              :tail -> :ok
            end

            :ok = TextStream.push(server, request, "tail")
            send(owner, {:sealed, TextStream.finish(server, request, "completed")})
        end
      end)

    on_exit(fn -> if Process.alive?(producer), do: Process.exit(producer, :kill) end)
    assert {:ok, true} = TextStream.begin_with_policy(server, request, producer)
    send(producer, :go)
    assert_receive :required_buffer_drained, 5000
    send(producer, :tail)

    assert_receive {:ipse_text, ^server,
                    %{
                      "kind" => "closed",
                      "reason" => "backpressure_timeout",
                      "subscription_id" => id
                    }},
                   10_000

    assert id == optional.subscription_id
    assert_receive {:required_text, text}, 1000
    assert text == String.duplicate("a", 65_536) <> "tail"
    assert_receive {:sealed, :ok}, 1000
    GenServer.stop(server)
  end

  defp required_consume(handle, owner, chunks) do
    receive do
      {:ipse_text, server, frame} when server == handle.server ->
        :ok = TextStream.ack(handle, frame["sequence"])
        chunks = [frame["text"] || "" | chunks]

        if frame["kind"] == "text" and IO.iodata_length(chunks) == 65_536,
          do: send(owner, :required_buffer_drained)

        if frame["kind"] == "end",
          do: send(owner, {:required_text, chunks |> Enum.reverse() |> Enum.join()}),
          else: required_consume(handle, owner, chunks)
    end
  end

  test "invalid chunks and stale request producers fail explicitly", ctx do
    ref = make_ref()
    send(ctx.producer, {:push, ref, ctx.request, <<255>>})
    assert_receive {:push_result, ^ref, {:error, :invalid_text_chunk}}, 1000
    assert_receive {:ipse_text, _, %{"kind" => "closed", "reason" => "invalid_chunk"}}
    :ok = TextStream.finish(ctx.server, ctx.request, "failed")
    next = Usage.id()
    :ok = TextStream.begin(ctx.server, next, ctx.producer)
    stale = make_ref()
    send(ctx.producer, {:push, stale, ctx.request, "stale"})
    assert_receive {:push_result, ^stale, {:error, :text_stream_refused}}, 1000
    :ok = TextStream.finish(ctx.server, next, "completed")
  end

  test "direct producer pushes retain the 64 KiB bound", ctx do
    ref = make_ref()
    send(ctx.producer, {:push, ref, ctx.request, String.duplicate("a", 65_537)})
    assert_receive {:push_result, ^ref, {:error, :invalid_text_chunk}}, 1000
    assert_receive {:ipse_text, _, %{"kind" => "closed", "reason" => "invalid_chunk"}}, 1000
    assert :ok = TextStream.finish(ctx.server, ctx.request, "failed")
  end

  test "four private subscriptions is a host ceiling and peers cannot enroll themselves" do
    {:ok, server} = TextStream.start(self(), Usage.id())
    for _ <- 1..4, do: assert({:ok, _} = TextStream.subscribe(server, self()))
    assert TextStream.subscribe(server, self()) == {:error, :text_subscription_unavailable}
    forged = Task.async(fn -> TextStream.subscribe(server, self()) end)
    assert Task.await(forged) == {:error, :text_stream_refused}
    GenServer.stop(server)
  end

  test "consumer death releases pending flow and owner death closes remaining private consumers" do
    parent = self()

    {:ok, owner} =
      Task.start(fn ->
        {:ok, server} = TextStream.start(self(), Usage.id())
        {:ok, handle} = TextStream.subscribe(server, parent)
        send(parent, {:owned_stream, server, handle})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:owned_stream, server, handle}, 1000
    ref = Process.monitor(server)
    Process.exit(owner, :kill)

    assert_receive {:ipse_text, ^server,
                    %{
                      "kind" => "closed",
                      "reason" => "owner_down",
                      "subscription_id" => id,
                      "complete" => false
                    }},
                   1000

    assert id == handle.subscription_id
    assert_receive {:DOWN, ^ref, :process, ^server, :normal}, 1000

    # This second broker's consumer is independent of its owner.
    {:ok, consumer} = Task.start(fn -> Process.sleep(:infinity) end)
    {:ok, broker} = TextStream.start(self(), Usage.id())
    {:ok, _} = TextStream.subscribe(broker, consumer)
    {:ok, producer} = Task.start(fn -> produce(broker, parent) end)
    request = Usage.id()
    :ok = TextStream.begin(broker, request, producer)
    push(%{producer: producer, request: request}, String.duplicate("a", 65_536))
    pending = make_ref()
    send(producer, {:push, pending, request, "tail"})
    refute_receive {:push_result, ^pending, _}, 20
    Process.exit(consumer, :kill)
    assert_receive {:push_result, ^pending, :ok}, 1000
    Process.exit(producer, :kill)
    GenServer.stop(broker)
  end
end
