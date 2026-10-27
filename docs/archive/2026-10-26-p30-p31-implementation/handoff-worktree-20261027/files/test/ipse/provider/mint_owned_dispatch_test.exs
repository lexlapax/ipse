defmodule Ipse.Provider.MintOwnedDispatchTest do
  use ExUnit.Case, async: false
  alias Ipse.{InferenceDispatch, InferenceSlots, Usage}
  alias Ipse.Provider.MintOwned
  alias Ipse.Session.Resources

  setup do
    base = Path.join(Path.expand(System.tmp_dir!()), "ipse-mint-dispatch-" <> Usage.id())
    home = Path.join(base, "operator")
    cwd = Path.join(base, "project")

    for path <- [base, home, cwd] do
      File.mkdir_p!(path)
      File.chmod!(path, 0o700)
    end

    on_exit(fn -> File.rm_rf!(base) end)
    %{home: home, cwd: cwd}
  end

  defp listener do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    {socket, "http://127.0.0.1:#{port}"}
  end

  defp runtime(c, base, registered) do
    %{
      provider: :ollama,
      model: "fixture",
      base_url: base,
      timeout_ms: 2000,
      home: c.home,
      max_output_tokens: 32,
      inference_services:
        if(registered, do: %{"local" => %{"version" => 1, "origins" => [base]}}, else: %{})
    }
  end

  defp context(c, runtime) do
    session = Usage.id()
    admission = Usage.admission(session, runtime, "model", Usage.id())

    %{
      cwd: c.cwd,
      session_id: session,
      project_id: Ipse.JSON.sha256(c.cwd),
      request_sha256: Ipse.JSON.digest([admission]),
      priority: "foreground",
      wait_ms: 2000,
      admission: admission
    }
  end

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

  defp dispatch(c, runtime, base) do
    InferenceDispatch.run(
      runtime,
      runtime,
      "main",
      nil,
      context(c, runtime),
      fn _ -> :ok end,
      fn _ -> {:ok, %{checked: true}} end,
      fn selected, _emit, _prepared ->
        result =
          MintOwned.run(
            selected,
            :text,
            base <> "/api/chat",
            [{"content-type", "application/json"}],
            ~s({"input":"fixture"}),
            2000,
            1024,
            "",
            fn
              {:data, _, bytes}, acc -> {:cont, acc <> bytes}
              _, acc -> {:cont, acc}
            end,
            fn send -> send.() end,
            fn body ->
              case Jason.decode(body) do
                {:ok, %{"done" => true}} ->
                  {:ok, %{"role" => "assistant", "content" => "fixture"}, %{}}

                _ ->
                  {:error, :invalid_fixture}
              end
            end
          )

        case result do
          {:settled, completed} -> completed
          _ -> {:error, "Synthetic owned request was not settled."}
        end
      end
    )
  end

  defp serve(listener) do
    Task.async(fn ->
      case :gen_tcp.accept(listener, 2500) do
        {:ok, socket} ->
          {:ok, request} = :gen_tcp.recv(socket, 0, 2500)
          body = ~s({"done":true})

          :ok =
            :gen_tcp.send(
              socket,
              "HTTP/1.1 200 OK\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n#{body}"
            )

          :gen_tcp.close(socket)
          :gen_tcp.close(listener)
          {:request, request}

        result ->
          :gen_tcp.close(listener)
          result
      end
    end)
  end

  defp finish(scope, worker) do
    if Process.alive?(worker), do: send(worker, :finish)
    if Process.alive?(scope), do: Resources.close(scope)
  end

  test "unregistered route executes the owned seam without inventing a service", c do
    {listener, base} = listener()
    server = serve(listener)
    runtime = runtime(c, base, false)
    assert {:ok, :unregistered} = InferenceDispatch.selection(runtime, runtime, "main", nil)
    {scope, worker} = start_owned(fn -> dispatch(c, runtime, base) end)

    try do
      assert_receive {:result, {:ok, %{"content" => "fixture"}, _}}, 8000
      assert {:request, request} = Task.await(server, 4000)
      assert request =~ "POST /api/chat HTTP/1.1"
    after
      finish(scope, worker)
    end
  end

  test "registered route settles only when its ledger is supported", c do
    {listener, base} = listener()
    server = serve(listener)
    runtime = runtime(c, base, true)
    assert {:ok, %{route: _}} = InferenceDispatch.selection(runtime, runtime, "main", nil)
    support = InferenceSlots.status(runtime, cwd: c.cwd)
    {scope, worker} = start_owned(fn -> dispatch(c, runtime, base) end)

    try do
      case support do
        {:ok, _} ->
          assert_receive {:result, {:ok, %{"content" => "fixture"}, _}}, 10_000
          assert {:request, _} = Task.await(server, 4000)
          assert {:ok, state} = InferenceSlots.status(runtime, cwd: c.cwd)
          assert state["services"]["local"]["active"] == nil

        {:error, :service_filesystem_unsupported} ->
          assert_receive {:result, {:error, message}}, 8000
          assert message =~ "filesystem is unsupported"
          assert {:error, :timeout} = Task.await(server, 4000)
          IO.puts("registered owned dispatch: unsupported filesystem; positive path NOT RUN")

        other ->
          flunk("unexpected service state: #{inspect(other)}")
      end
    after
      finish(scope, worker)
    end
  end
end
