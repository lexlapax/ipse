defmodule Ipse.Provider.MintTextDecisionTest do
  use ExUnit.Case, async: false
  alias Ipse.Provider.{MintText, MintDecision}
  alias Ipse.Session.Resources

  defp start_owned(fun) do
    {:ok, scope} = Resources.start(self())
    parent = self()

    worker =
      spawn(fn ->
        receive do
          :start ->
            Resources.bind(scope)
            send(parent, {:result, fun.()})
            receive do: (:finish -> :ok)
        end
      end)

    :ok = Resources.attach(scope, worker)
    send(worker, :start)
    {scope, worker}
  end

  defp cleanup(scope, worker) do
    if Process.alive?(worker), do: send(worker, :finish)
    if Process.alive?(scope), do: Resources.close(scope)
  end

  defp listen do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    {socket, "http://127.0.0.1:#{port}"}
  end

  defp request(socket, bytes \\ "") do
    case :binary.split(bytes, "\r\n\r\n") do
      [head, body] ->
        [_, size] = Regex.run(~r/content-length: (\d+)/i, head)
        size = String.to_integer(size)

        if byte_size(body) >= size,
          do: {head, binary_part(body, 0, size)},
          else: request_more(socket, bytes)

      _ ->
        request_more(socket, bytes)
    end
  end

  defp request_more(socket, bytes) do
    {:ok, next} = :gen_tcp.recv(socket, 0, 5000)
    request(socket, bytes <> next)
  end

  defp server(listener, data, parent) do
    Task.async(fn ->
      {:ok, socket} = :gen_tcp.accept(listener, 5000)
      {headers, body} = request(socket)
      send(parent, {:wire, headers, body})
      split = div(byte_size(data), 2)

      :ok =
        :gen_tcp.send(
          socket,
          "HTTP/1.1 200 OK\r\ncontent-length: #{byte_size(data)}\r\n\r\n" <>
            binary_part(data, 0, split)
        )

      send(parent, :partial)
      receive do: (:continue -> :ok)
      :ok = :gen_tcp.send(socket, binary_part(data, split, byte_size(data) - split))
      closed = :gen_tcp.recv(socket, 0, 5000)
      :gen_tcp.close(socket)
      :gen_tcp.close(listener)
      closed
    end)
  end

  defp decision_request do
    %{
      "version" => 1,
      "profile" => "test",
      "input" => "fresh fixture",
      "questions" => [
        %{"id" => "relevant", "type" => "predicate", "instructions" => "Is this relevant?"}
      ]
    }
  end

  test "text derives native chat and preserves tool continuation only after settlement" do
    {listener, base} = listen()
    parent = self()
    call = %{"function" => %{"name" => "lookup", "arguments" => %{"query" => "x"}}}

    native = %{
      "model" => "fixture",
      "message" => %{"content" => "answer", "thinking" => "hidden", "tool_calls" => [call]},
      "done" => true
    }

    task = server(listener, Jason.encode!(native) <> "\n", parent)

    runtime = %{
      provider: :ollama,
      model: "fixture",
      base_url: base,
      timeout_ms: 4000,
      headers: [{"authorization", "fake"}]
    }

    messages = [%{"role" => "user", "content" => "question"}]
    {:ok, expected} = Ipse.Session.InferenceWire.derive("model", runtime, messages, [])

    {scope, worker} =
      start_owned(fn ->
        MintText.complete(runtime, messages, [], fn facts, send ->
          assert Ipse.Session.InferenceWire.matches?(expected, facts)
          Kernel.send(parent, {:facts, facts})
          send.()
        end)
      end)

    try do
      assert_receive {:wire, headers, body}, 5000
      assert headers =~ "POST /api/chat HTTP/1.1"
      refute String.downcase(headers) =~ "authorization:"

      assert {:ok, %{"model" => "fixture", "messages" => ^messages, "stream" => true}} =
               Jason.decode(body)

      assert_receive {:facts,
                      %{"kind" => "text", "target_sha256" => target, "body_sha256" => hash}},
                     5000

      assert target == Ipse.JSON.sha256(base <> "/api/chat")
      assert hash == Ipse.JSON.sha256(body)
      assert_receive :partial, 5000
      refute_receive {:result, _}, 150
      send(task.pid, :continue)
      assert_receive {:result, {:settled, {:ok, message, _}}}, 5000
      assert message["content"] == "answer"
      assert get_in(message, ["provider_data", "message", "thinking"]) == "hidden"
      assert get_in(message, ["provider_data", "message", "tool_calls"]) == [call]

      assert [%{"function" => %{"name" => "lookup", "arguments" => "{\"query\":\"x\"}"}}] =
               message["tool_calls"]

      assert {:error, :closed} = Task.await(task, 6000)
    after
      cleanup(scope, worker)
    end
  end

  test "decision derives compatible endpoint and withholds typed result until cleanup" do
    {listener, base} = listen()
    parent = self()

    native = %{
      "model" => "fixture",
      "answers" => %{"relevant" => %{"type" => "noul", "noul" => 0.8}},
      "usage" => %{"input_tokens" => 10, "output_tokens" => 2}
    }

    task = server(listener, Jason.encode!(native), parent)

    runtime = %{
      provider: :system_one_compatible,
      model: "fixture",
      expected_model: "fixture",
      base_url: base,
      timeout_ms: 4000,
      headers: [{"authorization", "fake"}]
    }

    {:ok, expected} =
      Ipse.Session.InferenceWire.derive(
        "decision.create",
        runtime,
        Map.merge(decision_request(), %{"op" => "decision.create", "timeout_ms" => 4000}),
        []
      )

    {scope, worker} =
      start_owned(fn ->
        MintDecision.request(runtime, decision_request(), fn facts, send ->
          assert Ipse.Session.InferenceWire.matches?(expected, facts)
          Kernel.send(parent, {:facts, facts})
          send.()
        end)
      end)

    try do
      assert_receive {:wire, headers, body}, 5000
      assert headers =~ "POST /systemone HTTP/1.1"
      refute String.downcase(headers) =~ "authorization:"
      assert {:ok, %{"model" => "fixture", "state" => "fresh fixture"}} = Jason.decode(body)

      assert_receive {:facts,
                      %{"kind" => "decision", "target_sha256" => target, "body_sha256" => hash}},
                     5000

      assert target == Ipse.JSON.sha256(base <> "/systemone")
      assert hash == Ipse.JSON.sha256(body)
      assert_receive :partial, 5000
      refute_receive {:result, _}, 150
      send(task.pid, :continue)
      assert_receive {:result, {:settled, {:ok, %{"kind" => "decision"}, _}}}, 5000
      assert {:error, :closed} = Task.await(task, 6000)
    after
      cleanup(scope, worker)
    end
  end

  test "compaction and helper wire facts match the actual serialized requests" do
    for phase <- ["compaction", "model.complete"] do
      {listener, base} = listen()
      parent = self()
      data = ~s({"model":"fixture","message":{"content":"ok"},"done":true}\n)
      task = server(listener, data, parent)
      runtime = %{provider: :ollama, model: "fixture", base_url: base, timeout_ms: 4000}

      runtime =
        if phase == "compaction", do: Ipse.Session.Context.summary_config(runtime), else: runtime

      messages =
        if phase == "model.complete",
          do: Ipse.Session.Context.helper_messages("instruction", "input"),
          else: [%{"role" => "user", "content" => "summary"}]

      {:ok, expected} = Ipse.Session.InferenceWire.derive(phase, runtime, messages, [])

      {scope, worker} =
        start_owned(fn ->
          MintText.complete(runtime, messages, [], fn facts, send ->
            Kernel.send(parent, {:wire_facts, facts})
            send.()
          end)
        end)

      try do
        assert_receive {:wire, headers, body}, 5000
        assert headers =~ "POST /api/chat HTTP/1.1"
        assert_receive {:wire_facts, actual}, 5000
        assert Ipse.Session.InferenceWire.matches?(expected, actual)
        assert expected["body_sha256"] == Ipse.JSON.sha256(body)
        assert_receive :partial, 5000
        refute_receive {:result, _}, 100
        send(task.pid, :continue)
        assert_receive {:result, {:settled, {:ok, _, _}}}, 5000
        assert {:error, :closed} = Task.await(task, 6000)
      after
        cleanup(scope, worker)
      end
    end
  end

  test "incomplete text and duplicate-key decision frames remain unknown" do
    for {kind, data} <- [
          {:text, ~s({"message":{"content":"partial"},"done":false}\n)},
          {:text, ~s({"message":{"content":"x"},"done":true,"done_reason":"length"}\n)},
          {:text,
           ~s({"done":true}\n{"message":{"tool_calls":[{"function":{"name":"late","arguments":{}}}]},"done":false}\n)},
          {:text, ~s({"done":true}\n{"done":true}\n)},
          {:decision, ~s({"model":"fixture","model":"fixture","answers":{},"usage":{}})}
        ] do
      {listener, base} = listen()
      task = server(listener, data, self())

      runtime = %{
        provider: if(kind == :text, do: :ollama, else: :system_one_compatible),
        model: "fixture",
        base_url: base,
        timeout_ms: 4000
      }

      {scope, worker} =
        start_owned(fn ->
          admit = fn _, send -> send.() end

          if kind == :text,
            do: MintText.complete(runtime, [%{"role" => "user", "content" => "x"}], [], admit),
            else: MintDecision.request(runtime, decision_request(), admit)
        end)

      try do
        assert_receive {:wire, _, _}, 5000
        assert_receive :partial, 5000
        refute_receive {:result, _}, 100
        send(task.pid, :continue)
        assert_receive {:result, {:unknown, _}}, 5000
        Task.await(task, 6000)
      after
        cleanup(scope, worker)
      end
    end
  end

  test "unsupported providers and configured text credentials fail before connection" do
    {listener, base} = listen()
    runtime = %{provider: :ollama, model: "fixture", base_url: base, api_key: "private"}

    assert {:unstarted, :invalid_inference_request} =
             MintText.complete(runtime, [], [], fn _, _ -> flunk("admit") end)

    assert {:unstarted, :invalid_inference_request} =
             MintDecision.request(%{runtime | provider: :openai}, decision_request(), fn _, _ ->
               flunk("admit")
             end)

    assert {:error, :timeout} = :gen_tcp.accept(listener, 200)
    :gen_tcp.close(listener)
  end

  test "live Ollama streaming rejects text and tool calls after the completion marker" do
    for late <- [
          ~s({"message":{"content":"late"},"done":false}\n),
          ~s({"message":{"tool_calls":[{"function":{"name":"late","arguments":{}}}]},"done":false}\n),
          ~s({"done":true}\n)
        ] do
      {listener, base} = listen()
      parent = self()
      task = server(listener, ~s({"message":{"content":"first"},"done":true}\n) <> late, parent)
      runtime = %{provider: :ollama, model: "fixture", base_url: base, timeout_ms: 4000}

      provider =
        Task.async(fn ->
          Ipse.Provider.Ollama.complete(
            runtime,
            [%{"role" => "user", "content" => "x"}],
            [],
            fn event ->
              send(parent, {:event, event})
            end
          )
        end)

      assert_receive {:wire, _, _}, 5000
      assert_receive :partial, 5000
      send(task.pid, :continue)

      assert {:error, "Ollama stream contained data after its completion marker."} =
               Task.await(provider, 6000)

      refute_receive {:event, {:text, "late"}}, 100
      Task.await(task, 6000)
    end
  end

  test "blank lines after a terminal frame are allowed and native continuation is retained" do
    body =
      ~s({"model":"fixture","message":{"content":"ok","thinking":"private","tool_calls":[{"function":{"name":"lookup","arguments":{"q":"x"}}}]},"done":true}\n\n)

    assert {:ok, message, _} = Ipse.Provider.Ollama.parse_buffered(body)
    assert get_in(message, ["provider_data", "message", "thinking"]) == "private"

    assert [%{"function" => %{"name" => "lookup"}}] =
             get_in(message, ["provider_data", "message", "tool_calls"])
  end
end
