defmodule Ipse.TextEventsTest do
  use ExUnit.Case, async: false
  alias Ipse.{TextStream, Usage, Session}
  alias Ipse.Lifecycle.Ephemeral

  setup do
    session = Usage.id()
    {:ok, server} = TextStream.start(self(), session)
    owner = self()
    producer = spawn(fn -> produce(server, owner) end)
    on_exit(fn -> if Process.alive?(producer), do: Process.exit(producer, :kill) end)
    %{session: session, server: server, producer: producer, request: Usage.id()}
  end

  defp produce(server, owner) do
    receive do
      {:push, ref, request, text} ->
        result = TextStream.push(server, request, text)
        send(owner, {:pushed, ref, result})
        produce(server, owner)
    end
  end

  defp push(c, text) do
    ref = make_ref()
    send(c.producer, {:push, ref, c.request, text})
    assert_receive {:pushed, ^ref, :ok}, 1_000
  end

  defp frame(c, handle) do
    server = c.server
    id = handle.subscription_id

    receive do
      {:ipse_text, ^server, %{"subscription_id" => ^id} = f} -> f
    after
      1_000 -> flunk("Expected selected text frame")
    end
  end

  defp ack(handle, frame), do: assert(:ok = TextStream.ack(handle, frame["sequence"]))

  defp drain(c, handle, frames \\ []) do
    f = frame(c, handle)
    assert Ephemeral.valid_frame?(f)
    ack(handle, f)
    frames = frames ++ [f]
    if f["kind"] == "end", do: frames, else: drain(c, handle, frames)
  end

  test "unequal delivery boundaries retain shared stream ranges and terminal identity", c do
    {:ok, fast} = TextStream.subscribe(c.server, self(), 2)
    {:ok, slow} = TextStream.subscribe(c.server, self(), 2)
    :ok = TextStream.begin(c.server, c.request, c.producer)
    fs = frame(c, fast)
    ss = frame(c, slow)
    assert fs["source"] == ss["source"]
    ack(fast, fs)
    ack(slow, ss)
    push(c, "A")
    fa = frame(c, fast)
    sa = frame(c, slow)
    assert fa["source"] == sa["source"]
    ack(fast, fa)
    push(c, "λ")
    fb = frame(c, fast)
    ack(fast, fb)
    push(c, "🙂")
    fc = frame(c, fast)
    ack(fast, fc)
    :ok = TextStream.finish(c.server, c.request, "completed")
    fe = frame(c, fast)
    ack(fast, fe)
    ack(slow, sa)
    [sb, se] = drain(c, slow)
    assert fb["text"] <> fc["text"] == sb["text"]
    assert {fb["source"]["start_byte"], fc["source"]["end_byte"]} == {1, 7}
    assert {sb["source"]["start_byte"], sb["source"]["end_byte"]} == {1, 7}
    refute fb["source"]["event_id"] == sb["source"]["event_id"]
    assert fe["source"] == se["source"]
    refute fe["sequence"] == se["sequence"]
    for f <- [fs, fa, fb, fc, fe, ss, sa, sb, se], do: assert(Ephemeral.valid_frame?(f))
    assert {:ok, private} = Ephemeral.project(sb, "text.visible")
    assert {:ok, metadata} = Ephemeral.project(sb, "metadata")
    assert private["event_id"] == metadata["event_id"]
    assert private["data"] == %{"text" => "λ🙂"}
    assert metadata["data"] == %{"output_bytes" => 6}
    refute String.contains?(Jason.encode!(metadata), ["λ", "🙂", "sha256"])
  end

  test "v1 stays unchanged while repeated requests and broker restarts get fresh live identity",
       c do
    {:ok, legacy} = TextStream.subscribe(c.server, self())
    {:ok, current} = TextStream.subscribe(c.server, self(), 2)
    :ok = TextStream.begin(c.server, c.request, c.producer)
    old = frame(c, legacy)
    first = frame(c, current)
    assert old["version"] == 1 and old["stream_id"] == c.request
    refute Map.has_key?(old, "source")
    refute Map.has_key?(old, "offset")
    assert first["version"] == 2 and first["stream_id"] != c.request
    ack(legacy, old)
    ack(current, first)
    :ok = TextStream.finish(c.server, c.request, "completed")
    ack(legacy, frame(c, legacy))
    ack(current, frame(c, current))
    :ok = TextStream.begin(c.server, c.request, c.producer)
    second = frame(c, current)
    assert first["source"]["epoch_id"] == second["source"]["epoch_id"]
    refute first["stream_id"] == second["stream_id"]
    refute first["source"]["event_id"] == second["source"]["event_id"]
    {:ok, restarted} = TextStream.start(self(), c.session)
    {:ok, other} = TextStream.subscribe(restarted, self(), 2)
    :ok = TextStream.begin(restarted, c.request, c.producer)
    third = frame(%{c | server: restarted}, other)
    refute first["source"]["epoch_id"] == third["source"]["epoch_id"]
    GenServer.stop(restarted)
  end

  test "UTF-8 splits preserve exact byte ranges and cancelled pending bytes stay outside the stream",
       c do
    {:ok, handle} = TextStream.subscribe(c.server, self(), 2)
    :ok = TextStream.begin(c.server, c.request, c.producer)
    text = String.duplicate("λ🙂", 10_000) <> String.duplicate(<<0>>, 5_536)
    push(c, text)
    ref = make_ref()
    send(c.producer, {:push, ref, c.request, "discarded"})
    refute_receive {:pushed, ^ref, _}, 20
    :ok = TextStream.finish(c.server, c.request, "cancelled")
    assert_receive {:pushed, ^ref, {:error, :text_request_finished}}
    frames = drain(c, handle)
    chunks = Enum.filter(frames, &(&1["kind"] == "text"))
    assert Enum.map_join(chunks, "", & &1["text"]) == text

    assert Enum.reduce(chunks, 0, fn f, offset ->
             assert f["source"]["start_byte"] == offset
             f["source"]["end_byte"]
           end) == 65_536

    assert List.last(frames)["source"]["start_byte"] == 65_536
    refute List.last(frames)["complete"]
  end

  test "idle closure is subscription-scoped without an invented request or stream position", c do
    {:ok, a} = TextStream.subscribe(c.server, self(), 2)
    {:ok, b} = TextStream.subscribe(c.server, self(), 2)
    :ok = TextStream.unsubscribe(a)
    :ok = TextStream.unsubscribe(b)
    first = frame(c, a)
    second = frame(c, b)
    assert Ephemeral.valid_frame?(first)
    assert Ephemeral.valid_frame?(second)
    assert first["source"]["scope"] == "subscription"
    refute first["source"]["event_id"] == second["source"]["event_id"]
    refute Map.has_key?(first["source"], "request_id")
    refute Map.has_key?(first["source"], "start_byte")
    assert {:ok, event} = Ephemeral.project(first, "metadata")
    assert event["type"] == "text.subscription_closed"
    assert event["correlations"] == %{}
    assert {:error, _} = Ephemeral.project(first, "text.visible")
  end

  test "malformed source/frame bindings refuse instead of producing plausible projections", c do
    {:ok, handle} = TextStream.subscribe(c.server, self(), 2)
    :ok = TextStream.begin(c.server, c.request, c.producer)
    ack(handle, frame(c, handle))
    push(c, "private")
    original = frame(c, handle)

    for f <- [
          put_in(original, ["source", "end_byte"], 999),
          put_in(original, ["source", "epoch_id"], "bad"),
          Map.put(original, "request_id", Usage.id()),
          Map.put(original, "sequence", 0),
          Map.put(original, "text", String.duplicate("x", 2_049)),
          Map.put(original, "version", 1),
          Map.put(original, "hidden_reasoning", "private")
        ] do
      refute Ephemeral.valid_frame?(f)
      assert {:error, _} = Ephemeral.project(f, "metadata")
    end
  end

  test "explicit session negotiation rejects unsupported versions without creating a broker" do
    root = Path.join(System.tmp_dir!(), "ipse-text-events-#{Usage.id()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: %{provider: :demo, model: "scripted", home: root, approval: :deny},
         cwd: root,
         state_dir: Path.join(root, "state"),
         subscriber: self()}
      )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    assert {:error, :unsupported_text_version} = Session.subscribe_text(pid, 3)
    assert :sys.get_state(pid).text_stream == nil
    assert {:ok, _} = Session.subscribe_text(pid, 2)
    :ok = Session.close(pid)
    assert {:error, _} = Ipse.Extensions.Catalog.validate(nil, ["stream.text.events"])
    assert :ok = Ipse.Extensions.Catalog.validate(nil, ~w(stream.text stream.text.events))
  end

  test "position exhaustion closes visibly without accepting overflowing text", c do
    {:ok, handle} = TextStream.subscribe(c.server, self(), 2)
    :ok = TextStream.begin(c.server, c.request, c.producer)
    :sys.replace_state(c.server, &put_in(&1, [:active, :offset], 9_007_199_254_740_991))
    ref = make_ref()
    send(c.producer, {:push, ref, c.request, "x"})
    assert_receive {:pushed, ^ref, {:error, :text_position_limit}}
    _start = frame(c, handle)
    closed = frame(c, handle)
    assert closed["reason"] == "position_limit"
    assert Ephemeral.valid_frame?(closed)
  end
end
