defmodule Ipse.CLITest.IOFixture do
  use GenServer

  def start_link(owner), do: GenServer.start_link(__MODULE__, owner)
  def feed(pid, line), do: GenServer.call(pid, {:feed, line})
  def output(pid), do: GenServer.call(pid, :output)
  def pending?(pid), do: GenServer.call(pid, :pending?)

  @impl true
  def init(owner), do: {:ok, %{owner: owner, output: [], lines: [], pending: nil}}

  @impl true
  def handle_call({:feed, line}, _from, %{pending: {reader, reply_as}} = state) do
    send(reader, {:io_reply, reply_as, line_reply(line)})
    send(state.owner, {:io_line_fed, self(), line})
    {:reply, :ok, %{state | pending: nil}}
  end

  def handle_call({:feed, line}, _from, state) do
    send(state.owner, {:io_line_fed, self(), line})
    {:reply, :ok, %{state | lines: state.lines ++ [line]}}
  end

  def handle_call(:output, _from, state),
    do: {:reply, IO.iodata_to_binary(Enum.reverse(state.output)), state}

  def handle_call(:pending?, _from, state), do: {:reply, state.pending != nil, state}

  @impl true
  def handle_info({:io_request, from, reply_as, {:get_line, _encoding, prompt}}, state) do
    send(state.owner, {:io_waiting, self(), prompt})
    state = append(state, prompt)

    case state.lines do
      [line | rest] ->
        send(from, {:io_reply, reply_as, line_reply(line)})
        {:noreply, %{state | lines: rest}}

      [] ->
        {:noreply, %{state | pending: {from, reply_as}}}
    end
  end

  def handle_info({:io_request, from, reply_as, {:put_chars, _encoding, chars}}, state) do
    send(from, {:io_reply, reply_as, :ok})
    {:noreply, append(state, chars)}
  end

  def handle_info(
        {:io_request, from, reply_as, {:put_chars, _encoding, module, function, args}},
        state
      ) do
    send(from, {:io_reply, reply_as, :ok})
    {:noreply, append(state, apply(module, function, args))}
  end

  def handle_info({:io_request, from, reply_as, request}, state) do
    send(from, {:io_reply, reply_as, {:error, {:unsupported_io_request, request}}})
    {:noreply, state}
  end

  defp append(state, chars) do
    text = IO.iodata_to_binary(chars)
    send(state.owner, {:io_output, self(), text})
    %{state | output: [text | state.output]}
  end

  defp line_reply(:eof), do: :eof
  defp line_reply(text) when is_binary(text), do: text <> "\n"
end

defmodule Ipse.CLITest.HTTPFixture do
  def start(owner) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_ip, port}} = :inet.sockname(listener)

    server =
      Task.Supervisor.async_nolink(Ipse.Tasks, fn ->
        accept_loop(listener, owner, 1, %{})
      end)

    %{listener: listener, server: server, url: "http://127.0.0.1:#{port}"}
  end

  def reply(server, number, body), do: send(server, {:fixture_reply, number, body})

  def stop(%{listener: listener, server: server}) do
    if Process.alive?(server.pid), do: Task.shutdown(server, :brutal_kill)
    :gen_tcp.close(listener)
    :ok
  rescue
    ArgumentError -> :ok
  end

  def final_body(text \\ "Fixture answer") do
    Jason.encode!(%{"message" => %{"role" => "assistant", "content" => text}, "done" => true}) <>
      "\n"
  end

  def error_body(message \\ "fixture model failure"),
    do: Jason.encode!(%{"error" => message}) <> "\n"

  def write_call_body do
    Jason.encode!(%{
      "message" => %{
        "role" => "assistant",
        "content" => "",
        "tool_calls" => [
          %{
            "function" => %{
              "name" => "write",
              "arguments" => %{"path" => "should-not-exist.txt", "content" => "no"}
            }
          }
        ]
      },
      "done" => true
    }) <> "\n"
  end

  defp accept_loop(listener, owner, number, handlers) do
    receive do
      {:fixture_reply, reply_number, body} when is_map_key(handlers, reply_number) ->
        send(Map.fetch!(handlers, reply_number), {:fixture_reply, body})
        accept_loop(listener, owner, number, handlers)

      {:handler_closed, ^number} ->
        accept_loop(listener, owner, number, Map.delete(handlers, number))
    after
      20 ->
        case :gen_tcp.accept(listener, 20) do
          {:ok, socket} ->
            parent = self()
            server = self()
            handler = spawn_link(fn -> await_socket(parent, server, owner, number) end)
            :ok = :gen_tcp.controlling_process(socket, handler)
            send(handler, {:socket, socket})
            accept_loop(listener, owner, number + 1, Map.put(handlers, number, handler))

          {:error, :closed} ->
            :ok

          {:error, :timeout} ->
            accept_loop(listener, owner, number, handlers)
        end
    end
  end

  defp await_socket(parent, server, owner, number) do
    receive do
      {:socket, socket} ->
        {_headers, payload} = read_request(socket, <<>>)
        send(owner, {:ollama_request, server, number, Jason.decode!(payload)})
        await_reply_or_disconnect(parent, server, socket, owner, number)
    end
  end

  defp await_reply_or_disconnect(parent, server, socket, owner, number) do
    receive do
      {:fixture_reply, body} ->
        response =
          "HTTP/1.1 200 OK\r\ncontent-type: application/x-ndjson\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
            body

        :ok = :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)
        send(parent, {:handler_closed, number})
    after
      40 ->
        case :gen_tcp.recv(socket, 0, 0) do
          {:error, :closed} ->
            send(owner, {:ollama_disconnected, server, number})
            send(parent, {:handler_closed, number})

          {:error, :timeout} ->
            await_reply_or_disconnect(parent, server, socket, owner, number)

          {:ok, _unexpected} ->
            await_reply_or_disconnect(parent, server, socket, owner, number)
        end
    end
  end

  defp read_request(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [headers, body] ->
        [_, length] = Regex.run(~r/content-length:\s*(\d+)/i, headers)
        {headers, read_body(socket, body, String.to_integer(length))}

      [_] ->
        {:ok, chunk} = :gen_tcp.recv(socket, 0, 5_000)
        read_request(socket, buffer <> chunk)
    end
  end

  defp read_body(_socket, body, length) when byte_size(body) >= length, do: body

  defp read_body(socket, body, length) do
    {:ok, chunk} = :gen_tcp.recv(socket, 0, 5_000)
    read_body(socket, body <> chunk, length)
  end
end

defmodule Ipse.CLITest do
  use ExUnit.Case, async: false

  setup_all do
    {:ok, _} = Application.ensure_all_started(:ipse)
    :ok
  end

  setup do
    home =
      Path.join(System.tmp_dir!(), "ipse-cli-home-#{Base.encode16(:crypto.strong_rand_bytes(8))}")

    File.mkdir_p!(home)
    previous = System.get_env("IPSE_HOME")
    System.put_env("IPSE_HOME", home)

    on_exit(fn ->
      if previous, do: System.put_env("IPSE_HOME", previous), else: System.delete_env("IPSE_HOME")
      File.rm_rf!(home)
    end)

    :ok
  end

  test "EOF while idle exits cleanly" do
    with_fixture_and_cli(fn _fixture, cli ->
      await_input(cli.stdio)
      assert Ipse.CLITest.IOFixture.output(cli.stderr) =~ Ipse.Sandbox.describe(:off)
      Ipse.CLITest.IOFixture.feed(cli.stdio, :eof)
      assert 0 == Task.await(cli.task, 3_000)
      refute_receive {:ollama_request, _, _, _}, 100
    end)
  end

  test "extension inspection and invalid commands stay local without model requests" do
    with_fixture_and_cli(fn _fixture, cli ->
      await_input(cli.stdio)
      Ipse.CLITest.IOFixture.feed(cli.stdio, "/ext")
      await_text(cli.stdio, "\"entries\": []")
      Ipse.CLITest.IOFixture.feed(cli.stdio, "/ext missing {}")
      await_text(cli.stderr, "Extension command unavailable")
      Ipse.CLITest.IOFixture.feed(cli.stdio, "/ext missing")
      await_text(cli.stderr, "Use /ext NAME JSON_OBJECT")
      refute_receive {:ollama_request, _, _, _}, 50
      Ipse.CLITest.IOFixture.feed(cli.stdio, :eof)
      assert Task.await(cli.task, 3000) == 0
    end)
  end

  test "/info is local and stays available while a model response is pending" do
    with_fixture_and_cli(fn fixture, cli ->
      await_input(cli.stdio)
      stdio = cli.stdio
      Ipse.CLITest.IOFixture.feed(cli.stdio, "/info")
      assert_receive {:io_output, ^stdio, "Ipse version: " <> _ = first_info}, 2_000
      assert first_info =~ "Ipse version: #{Application.spec(:ipse, :vsn)}"
      assert first_info =~ "Requested model: test"
      refute_receive {:ollama_request, _, _, _}, 100
      Ipse.CLITest.IOFixture.feed(cli.stdio, "identify yourself")
      {server, 1, request} = await_request(fixture)
      assert hd(request["messages"])["content"] =~ "Configured provider: ollama"
      Ipse.CLITest.IOFixture.feed(cli.stdio, "/info")
      assert_receive {:io_output, ^stdio, "Ipse version: " <> _ = pending_info}, 2_000
      assert pending_info =~ "Last response model (current run): unavailable"
      Ipse.CLITest.HTTPFixture.reply(server, 1, Ipse.CLITest.HTTPFixture.final_body("done"))
      await_text(cli.stderr, "Finished.")
      refute_receive {:ollama_request, _, _, _}, 100
      Ipse.CLITest.IOFixture.feed(cli.stdio, :eof)
      assert 0 == Task.await(cli.task, 3_000)
    end)
  end

  test "provider errors are visible and finish the turn with an error status" do
    with_fixture_and_cli(fn fixture, cli ->
      await_input(cli.stdio)
      Ipse.CLITest.IOFixture.feed(cli.stdio, "fail this task")
      {server, 1, _request} = await_request(fixture)
      await_text(cli.stderr, "Running…")
      Ipse.CLITest.HTTPFixture.reply(server, 1, Ipse.CLITest.HTTPFixture.error_body())
      await_text(cli.stderr, "Finished with an error.")
      assert Ipse.CLITest.IOFixture.output(cli.stderr) =~ "Error: Ollama rejected the request"
      Ipse.CLITest.IOFixture.feed(cli.stdio, :eof)
      assert 0 == Task.await(cli.task, 3_000)
    end)
  end

  test "/context refresh adopts instructions locally and is refused during work" do
    with_fixture_and_cli(fn fixture, cli ->
      await_input(cli.stdio)
      File.write!(Path.join(cli.cwd, "AGENTS.md"), "Use the workspace marker persimmon.")
      Ipse.CLITest.IOFixture.feed(cli.stdio, "/context refresh")
      await_text(cli.stderr, "Finished.")
      assert Ipse.CLITest.IOFixture.output(cli.stdio) =~ "AGENTS.md"
      refute_receive {:ollama_request, _, _, _}, 100

      Ipse.CLITest.IOFixture.feed(cli.stdio, "describe the instructions")
      {server, 1, request} = await_request(fixture)
      assert hd(request["messages"])["content"] =~ "persimmon"
      Ipse.CLITest.IOFixture.feed(cli.stdio, "/context refresh")
      await_text(cli.stderr, "Finish or cancel active work")
      Ipse.CLITest.IOFixture.feed(cli.stdio, "/context")
      refute_receive {:ollama_request, _, _, _}, 100
      Ipse.CLITest.HTTPFixture.reply(server, 1, Ipse.CLITest.HTTPFixture.final_body("done"))
      await_text(cli.stderr, "Finished.")
      Ipse.CLITest.IOFixture.feed(cli.stdio, :eof)
      assert 0 == Task.await(cli.task, 3_000)
    end)
  end

  test "provider errors stop queued inference until the user sends a fresh task" do
    with_fixture_and_cli(fn fixture, cli ->
      await_input(cli.stdio)
      Ipse.CLITest.IOFixture.feed(cli.stdio, "first task")
      {server, 1, _} = await_request(fixture)
      Ipse.CLITest.IOFixture.feed(cli.stdio, "queued task")
      await_text(cli.stderr, "Queued for the next turn")
      Ipse.CLITest.HTTPFixture.reply(server, 1, Ipse.CLITest.HTTPFixture.error_body())
      await_text(cli.stderr, "Queued input was discarded after the error")
      refute_receive {:ollama_request, _, _, _}, 100

      Ipse.CLITest.IOFixture.feed(cli.stdio, "fresh task after reviewing failure")
      {^server, 2, request} = await_request(fixture)
      contents = Enum.map(request["messages"], & &1["content"])
      refute "queued task" in contents
      assert "fresh task after reviewing failure" in contents
      Ipse.CLITest.HTTPFixture.reply(server, 2, Ipse.CLITest.HTTPFixture.final_body("recovered"))
      await_text(cli.stderr, "Finished.")
      Ipse.CLITest.IOFixture.feed(cli.stdio, :eof)
      assert 0 == Task.await(cli.task, 3_000)
    end)
  end

  test "running and finished are visible; EOF during work drains queued input" do
    with_fixture_and_cli(fn fixture, cli ->
      await_input(cli.stdio)
      Ipse.CLITest.IOFixture.feed(cli.stdio, "first task")
      {server, 1, first} = await_request(fixture)
      assert first["messages"] |> Enum.any?(&(&1["content"] == "first task"))
      await_text(cli.stderr, "Running…")

      Ipse.CLITest.IOFixture.feed(cli.stdio, "queued before EOF")
      await_text(cli.stderr, "Queued for the next turn")
      Ipse.CLITest.IOFixture.feed(cli.stdio, :eof)

      Ipse.CLITest.HTTPFixture.reply(server, 1, Ipse.CLITest.HTTPFixture.final_body("first done"))
      {^server, 2, second} = await_request(fixture)
      assert second["messages"] |> Enum.any?(&(&1["content"] == "queued before EOF"))

      Ipse.CLITest.HTTPFixture.reply(
        server,
        2,
        Ipse.CLITest.HTTPFixture.final_body("queued done")
      )

      assert 0 == Task.await(cli.task, 5_000)
      assert Ipse.CLITest.IOFixture.output(cli.stderr) =~ "Finished."
      assert String.contains?(Ipse.CLITest.IOFixture.output(cli.stdio), "queued done")
    end)
  end

  test "EOF during approval denies the tool and waits for model completion" do
    with_fixture_and_cli(false, fn fixture, cli ->
      await_input(cli.stdio)
      Ipse.CLITest.IOFixture.feed(cli.stdio, "please write")
      {server, 1, _request} = await_request(fixture)
      await_text(cli.stderr, "Running…")
      Ipse.CLITest.HTTPFixture.reply(server, 1, Ipse.CLITest.HTTPFixture.write_call_body())
      await_text(cli.stderr, "Waiting for approval")
      Ipse.CLITest.IOFixture.feed(cli.stdio, :eof)

      {^server, 2, second} = await_request(fixture)

      assert Enum.any?(second["messages"], fn message ->
               message["role"] == "tool" and
                 String.contains?(message["content"], "Denied by user")
             end)

      Ipse.CLITest.HTTPFixture.reply(server, 2, Ipse.CLITest.HTTPFixture.final_body())
      assert 0 == Task.await(cli.task, 5_000)
      assert Ipse.CLITest.IOFixture.output(cli.stderr) =~ "Finished."
      refute File.exists?(Path.join(cli.cwd, "should-not-exist.txt"))
    end)
  end

  test "resuming a finished CLI session retains history without replaying a completed write" do
    with_fixture_and_cli(fn fixture, cli ->
      await_input(cli.stdio)
      Ipse.CLITest.IOFixture.feed(cli.stdio, "write fixture")
      {server, 1, first} = await_request(fixture)
      session_id = session_id(cli.stderr)
      assert Enum.any?(first["messages"], &(&1["content"] == "write fixture"))

      Ipse.CLITest.HTTPFixture.reply(server, 1, Ipse.CLITest.HTTPFixture.write_call_body())
      {^server, 2, _after_tool} = await_request(fixture)
      assert File.read!(Path.join(cli.cwd, "should-not-exist.txt")) == "no"
      Ipse.CLITest.HTTPFixture.reply(server, 2, Ipse.CLITest.HTTPFixture.final_body("write done"))
      await_text(cli.stderr, "Finished.")
      Ipse.CLITest.IOFixture.feed(cli.stdio, :eof)
      assert 0 == Task.await(cli.task, 3_000)
      cleanup_cli(cli)

      File.write!(Path.join(cli.cwd, "should-not-exist.txt"), "user edit")
      resumed_cli = start_cli(fixture.url, cli.cwd, true, session_id)

      try do
        await_input(resumed_cli.stdio)
        Ipse.CLITest.IOFixture.feed(resumed_cli.stdio, "resume and inspect")
        {^server, 3, resumed} = await_request(fixture)
        assert Enum.any?(resumed["messages"], &(&1["content"] == "write fixture"))
        assert Enum.any?(resumed["messages"], &(&1["content"] == "resume and inspect"))

        assert Enum.any?(resumed["messages"], fn message ->
                 message["role"] == "tool" and String.contains?(message["content"], "Wrote")
               end)

        assert File.read!(Path.join(cli.cwd, "should-not-exist.txt")) == "user edit"

        Ipse.CLITest.HTTPFixture.reply(server, 3, Ipse.CLITest.HTTPFixture.final_body("resumed"))
        await_text(resumed_cli.stderr, "Finished.")
        Ipse.CLITest.IOFixture.feed(resumed_cli.stdio, :eof)
        assert 0 == Task.await(resumed_cli.task, 3_000)
        assert File.read!(Path.join(cli.cwd, "should-not-exist.txt")) == "user edit"
      after
        cleanup_cli(resumed_cli)
      end
    end)
  end

  test "cancel is visible and input during cancellation is discarded before a fresh turn" do
    with_fixture_and_cli(fn fixture, cli ->
      await_input(cli.stdio)
      Ipse.CLITest.IOFixture.feed(cli.stdio, "first gated task")
      {server, 1, _first_request} = await_request(fixture)
      await_text(cli.stderr, "Running…")
      Ipse.CLITest.IOFixture.feed(cli.stdio, "old queued task")
      await_text(cli.stderr, "Queued for the next turn")

      session_id = session_id(cli.stderr)
      session = lookup_session(cli.state_dir, session_id)
      :ok = :sys.suspend(session)

      try do
        Ipse.CLITest.IOFixture.feed(cli.stdio, "/cancel")
        await_text(cli.stderr, "Cancelling active work…")
        await_cancel_call(session)

        Ipse.CLITest.IOFixture.feed(cli.stdio, "/cancel")
        await_cli_input(cli.task.pid, "/cancel")

        # The CLI blocks in Session.cancel/1. This line is guaranteed to be in
        # its mailbox before the suspended session is allowed to answer.
        Ipse.CLITest.IOFixture.feed(cli.stdio, "line arriving during cancellation")
        await_cli_input(cli.task.pid, "line arriving during cancellation")
        :ok = :sys.resume(session)

        await_text(cli.stderr, "Cancelled.")
        await_text(cli.stderr, "Cancellation already requested.")
        await_text(cli.stderr, "Input received during cancellation was discarded.")
        refute_receive {:ollama_request, ^server, 2, _}, 250

        Ipse.CLITest.IOFixture.feed(cli.stdio, "fresh follow-up")
        {^server, 2, fresh} = await_request(fixture)
        contents = Enum.map(fresh["messages"], & &1["content"])
        assert "first gated task" in contents
        assert "fresh follow-up" in contents
        refute "old queued task" in contents
        refute "line arriving during cancellation" in contents

        Ipse.CLITest.HTTPFixture.reply(
          server,
          2,
          Ipse.CLITest.HTTPFixture.final_body("fresh completed")
        )

        await_text(cli.stderr, "Finished.")
        Ipse.CLITest.IOFixture.feed(cli.stdio, :eof)
        assert 0 == Task.await(cli.task, 3_000)
      after
        if Process.alive?(session), do: :sys.resume(session)
      end
    end)
  end

  defp question_body do
    args = %{
      "questions" => [
        %{
          "id" => "one",
          "kind" => "single",
          "prompt" => "Pick one",
          "recommended" => "b",
          "options" => [%{"id" => "a", "label" => "A"}, %{"id" => "b", "label" => "B"}]
        },
        %{
          "id" => "many",
          "kind" => "multiple",
          "prompt" => "Pick several",
          "options" => [%{"id" => "a", "label" => "A"}, %{"id" => "b", "label" => "B"}]
        },
        %{"id" => "text", "kind" => "text", "prompt" => "Provide notes"}
      ]
    }

    Jason.encode!(%{
      "message" => %{
        "role" => "assistant",
        "content" => "",
        "tool_calls" => [%{"function" => %{"name" => "ask_operator", "arguments" => args}}]
      },
      "done" => true
    }) <> "\n"
  end

  test "structured CLI questions validate single/multiple/text input without selecting recommendations" do
    with_fixture_and_cli(false, fn fixture, cli ->
      await_input(cli.stdio)
      Ipse.CLITest.IOFixture.feed(cli.stdio, "choose")
      {server, 1, _} = await_request(fixture)
      Ipse.CLITest.HTTPFixture.reply(server, 1, question_body())
      await_text(cli.stderr, "Pick one")
      refute_receive {:ollama_request, _, _, _}, 50
      Ipse.CLITest.IOFixture.feed(cli.stdio, "99")
      await_text(cli.stderr, "Invalid answer")
      refute_receive {:ollama_request, _, _, _}, 50
      Ipse.CLITest.IOFixture.feed(cli.stdio, "1")
      await_text(cli.stderr, "Pick several")
      Ipse.CLITest.IOFixture.feed(cli.stdio, "1,2")
      await_text(cli.stderr, "Provide notes")
      Ipse.CLITest.IOFixture.feed(cli.stdio, "=/exit")
      {^server, 2, request} = await_request(fixture)
      answer = Enum.find(request["messages"], &(&1["role"] == "tool"))

      assert Jason.decode!(answer["content"])["answers"] == %{
               "one" => "a",
               "many" => ["a", "b"],
               "text" => "/exit"
             }

      refute Ipse.CLITest.IOFixture.output(cli.stderr) =~ "Waiting for approval"
      Ipse.CLITest.HTTPFixture.reply(server, 2, Ipse.CLITest.HTTPFixture.final_body("answered"))
      await_text(cli.stderr, "Finished.")
      Ipse.CLITest.IOFixture.feed(cli.stdio, :eof)
      assert Task.await(cli.task, 3000) == 0
    end)
  end

  test "EOF during operator questions cancels without a default or another model request" do
    with_fixture_and_cli(fn fixture, cli ->
      await_input(cli.stdio)
      Ipse.CLITest.IOFixture.feed(cli.stdio, "choose")
      {server, 1, _} = await_request(fixture)
      Ipse.CLITest.HTTPFixture.reply(server, 1, question_body())
      await_text(cli.stderr, "Pick one")
      id = session_id(cli.stderr)
      Ipse.CLITest.IOFixture.feed(cli.stdio, :eof)
      assert Task.await(cli.task, 3000) == 0
      {:ok, events} = Ipse.Journal.load(cli.state_dir, id)
      assert Enum.any?(events, &(&1["type"] == "operator_question_closed"))
      refute Enum.any?(events, &(&1["type"] == "operator_answer"))
      refute_receive {:ollama_request, _, _, _}, 50
    end)
  end

  test "headless CLI fails required operator input even with yes enabled" do
    root =
      Path.join(System.tmp_dir!(), "ipse-headless-question-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    fixture = Ipse.CLITest.HTTPFixture.start(self())

    try do
      task =
        Task.async(fn ->
          Ipse.CLI.run([
            "run",
            "--provider",
            "ollama",
            "--model",
            "test",
            "--base-url",
            fixture.url,
            "--cwd",
            root,
            "--state-dir",
            Path.join(root, "state"),
            "--yes",
            "choose"
          ])
        end)

      {server, 1, _} = await_request(fixture)
      Ipse.CLITest.HTTPFixture.reply(server, 1, question_body())
      assert Task.await(task, 3000) == 1
      refute_receive {:ollama_request, _, _, _}, 50
    after
      Ipse.CLITest.HTTPFixture.stop(fixture)
      File.rm_rf!(root)
    end
  end

  test "fresh chat handoff stays idle until a prompt and retains current routing and approvals" do
    root = Path.join(System.fetch_env!("IPSE_HOME"), "handoff-workspace")
    File.mkdir_p!(root)
    path = Path.join(root, "handoff.json")
    bytes = Jason.encode!(handoff_artifact(), pretty: true) <> "\n"
    File.write!(path, bytes)
    fixture = Ipse.CLITest.HTTPFixture.start(self())
    cli = start_cli(fixture.url, root, false, nil, ["--handoff", path])

    try do
      await_input(cli.stdio)
      await_text(cli.stderr, "Imported historical handoff from " <> String.duplicate("a", 32))
      assert Ipse.CLITest.IOFixture.output(cli.stderr) =~ "unknown source calls: 1"
      assert Ipse.CLITest.IOFixture.output(cli.stderr) =~ "Type a fresh prompt to begin."
      id = session_id(cli.stderr)
      refute id == handoff_artifact()["source_session_id"]
      session = lookup_session(cli.state_dir, id)
      state = :sys.get_state(session)
      assert state.phase == :idle
      assert state.config.provider == :ollama
      assert state.config.model == "test"
      assert state.config.approval == :ask
      assert {:ok, events} = Ipse.Journal.load(cli.state_dir, id)
      assert [record] = Enum.filter(events, &(&1["type"] == "handoff_imported"))
      assert record["artifact"] == bytes
      assert String.ends_with?(record["message"]["content"], handoff_artifact()["note"])
      refute Enum.any?(events, &(&1["type"] in ["message", "tool_started", "tool_approved"]))
      refute_receive {:ollama_request, _, _, _}, 100

      Ipse.CLITest.IOFixture.feed(cli.stdio, "A fresh operator task")
      {server, 1, request} = await_request(fixture)
      assert request["model"] == "test"
      assert List.last(request["messages"])["content"] == "A fresh operator task"
      assert Enum.any?(request["messages"], &(&1["content"] == record["message"]["content"]))
      Ipse.CLITest.HTTPFixture.reply(server, 1, Ipse.CLITest.HTTPFixture.write_call_body())
      await_text(cli.stderr, "Waiting for approval")
      refute File.exists?(Path.join(root, "should-not-exist.txt"))
      Ipse.CLITest.IOFixture.feed(cli.stdio, "n")
      {^server, 2, denied} = await_request(fixture)
      assert Enum.any?(denied["messages"], &(&1["role"] == "tool" and &1["content"] =~ "Denied"))
      Ipse.CLITest.HTTPFixture.reply(server, 2, Ipse.CLITest.HTTPFixture.final_body())
      await_text(cli.stderr, "Finished.")
      Ipse.CLITest.IOFixture.feed(cli.stdio, :eof)
      assert Task.await(cli.task, 3000) == 0
      refute File.exists?(Path.join(root, "should-not-exist.txt"))

      refute File.exists?(
               Path.join(cli.state_dir, handoff_artifact()["source_session_id"] <> ".jsonl")
             )
    after
      cleanup_cli(cli)
      Ipse.CLITest.HTTPFixture.stop(fixture)
    end
  end

  test "handoff rejects resume and other command modes without reading input or mutating source state" do
    root = System.fetch_env!("IPSE_HOME")
    dir = Path.join(root, "source-sessions")
    {:ok, id} = Ipse.Journal.create(dir, %{provider: "demo", model: "fixture", cwd: root})
    source = Path.join(dir, id <> ".jsonl")
    before = File.read!(source)
    missing = Path.join(root, "not-present.json")
    fresh_dir = Path.join(root, "never-created")

    for mode <- [
          ["chat", "--resume", id],
          ["--resume", id],
          ["run", "task"],
          ["run"],
          ["demo"],
          ["--demo"],
          ["sessions"],
          ["config"],
          ["skills"],
          ["research"],
          ["diagnose"],
          ["handoff"],
          ["login"],
          ["logout"],
          ["status"],
          ["--help"],
          ["chat", "unexpected-task"]
        ] do
      output =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          assert Ipse.CLI.run(mode ++ ["--handoff", missing, "--state-dir", fresh_dir]) == 1
        end)

      assert output =~ "--handoff requires fresh interactive chat"
      refute output =~ "Invalid handoff"
      assert File.read!(source) == before
      refute File.exists?(fresh_dir)
      refute File.exists?(Path.join(root, "auth"))
    end
  end

  test "fresh default or explicit chat validates handoff before authentication or session creation" do
    root = System.fetch_env!("IPSE_HOME")
    dir = Path.join(root, "never-created")
    path = Path.join(root, "invalid.json")

    for mode <- [[], ["chat"]],
        bytes <- ["{}", "[]", <<255>>, String.duplicate(" ", 16_385)] do
      File.write!(path, bytes)

      output =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          assert Ipse.CLI.run(mode ++ ["--handoff", path, "--state-dir", dir]) == 1
        end)

      assert output =~ "Invalid handoff"
      refute output =~ "Session:"
      refute File.exists?(dir)
      refute File.exists?(Path.join(root, "auth"))
      assert File.read!(path) == bytes
    end
  end

  defp handoff_artifact do
    %{
      "version" => 1,
      "source_session_id" => String.duplicate("a", 32),
      "source_events_sha256" => String.duplicate("b", 64),
      "note" => "  Historical task only. Do not replay the old call.\n ",
      "requires_effect_review" => true,
      "unknown_tool_count" => 1,
      "unknown_call_ids" => ["old-call"],
      "unknown_ids_omitted" => 0
    }
  end

  defp with_fixture_and_cli(fun), do: with_fixture_and_cli(true, fun)

  defp with_fixture_and_cli(trusted?, fun) do
    root = Path.join(System.tmp_dir!(), "ipse-p1-cli-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    fixture = Ipse.CLITest.HTTPFixture.start(self())
    cli = start_cli(fixture.url, root, trusted?)

    try do
      fun.(fixture, cli)
    after
      try do
        cleanup_cli(cli)
      after
        try do
          Ipse.CLITest.HTTPFixture.stop(fixture)
        after
          File.rm_rf!(root)
        end
      end
    end
  end

  defp start_cli(base_url, root, trusted?, resume \\ nil, extra \\ []) do
    {:ok, stdio} = Ipse.CLITest.IOFixture.start_link(self())
    {:ok, stderr} = Ipse.CLITest.IOFixture.start_link(self())
    old_stderr = Process.whereis(:standard_error)
    true = Process.unregister(:standard_error)
    true = Process.register(stderr, :standard_error)
    state_dir = Path.join(root, "state")

    trusted = if trusted?, do: ["--yes"], else: []
    resume_opt = if resume, do: ["--resume", resume], else: []

    args =
      ["--provider", "ollama", "--model", "test", "--base-url", base_url] ++
        trusted ++ ["--cwd", root, "--state-dir", state_dir] ++ resume_opt ++ ["chat"] ++ extra

    task =
      Task.Supervisor.async_nolink(Ipse.Tasks, fn ->
        Process.group_leader(self(), stdio)
        Ipse.CLI.run(args)
      end)

    %{
      task: task,
      stdio: stdio,
      stderr: stderr,
      old_stderr: old_stderr,
      cwd: root,
      state_dir: Path.expand(state_dir)
    }
  end

  defp cleanup_cli(cli) do
    if Process.alive?(cli.task.pid), do: Task.shutdown(cli.task, :brutal_kill)

    try do
      sessions = Registry.select(Ipse.Registry, [{{{cli.state_dir, :_}, :"$1", :_}, [], [:"$1"]}])

      for session <- sessions do
        DynamicSupervisor.terminate_child(Ipse.Sessions, session)
      end
    after
      if Process.whereis(:standard_error) == cli.stderr do
        Process.unregister(:standard_error)
        Process.register(cli.old_stderr, :standard_error)
      end

      for device <- [cli.stdio, cli.stderr],
          Process.alive?(device),
          do: GenServer.stop(device, :normal)
    end

    :ok
  end

  defp await_input(stdio, timeout \\ 3_000) do
    receive do
      {:io_waiting, ^stdio, _prompt} -> :ok
      {:io_output, _device, _text} -> await_input(stdio, timeout)
      {:io_line_fed, _device, _line} -> await_input(stdio, timeout)
    after
      timeout -> flunk("CLI input reader did not request a line")
    end
  end

  defp await_text(device, text, timeout \\ 4_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    await_text_loop(device, text, deadline)
  end

  defp await_text_loop(device, text, deadline) do
    if String.contains?(Ipse.CLITest.IOFixture.output(device), text) do
      :ok
    else
      receive do
        {:io_output, ^device, _chunk} -> await_text_loop(device, text, deadline)
        {:io_waiting, _other, _prompt} -> await_text_loop(device, text, deadline)
        {:io_line_fed, _other, _line} -> await_text_loop(device, text, deadline)
      after
        max(deadline - System.monotonic_time(:millisecond), 0) ->
          flunk("CLI output did not contain #{inspect(text)}")
      end
    end
  end

  defp await_request(fixture, timeout \\ 5_000) do
    receive do
      {:ollama_request, server, number, request} when server == fixture.server.pid ->
        {server, number, request}

      {:io_output, _device, _text} ->
        await_request(fixture, timeout)

      {:io_waiting, _device, _prompt} ->
        await_request(fixture, timeout)
    after
      timeout ->
        flunk("Ollama fixture did not receive a request")
    end
  end

  defp session_id(stderr) do
    case Regex.run(~r/Session: ([a-f0-9]+)/, Ipse.CLITest.IOFixture.output(stderr)) do
      [_, id] -> id
      _ -> flunk("CLI did not print a session id")
    end
  end

  defp lookup_session(state_dir, id) do
    case Registry.lookup(Ipse.Registry, {state_dir, id}) do
      [{pid, _}] -> pid
      _ -> flunk("session is not registered")
    end
  end

  defp await_cancel_call(session, timeout \\ 3_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    await_cancel_call_loop(session, deadline)
  end

  defp await_cancel_call_loop(session, deadline) do
    {:messages, messages} = Process.info(session, :messages)

    if Enum.any?(messages, fn
         {:"$gen_call", {_from, _tag}, :cancel} -> true
         _ -> false
       end) do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        flunk("CLI did not send Session.cancel/1")
      else
        Process.sleep(5)
        await_cancel_call_loop(session, deadline)
      end
    end
  end

  defp await_cli_input(cli, text, timeout \\ 3_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    await_cli_input_loop(cli, text, deadline)
  end

  defp await_cli_input_loop(cli, text, deadline) do
    case Process.info(cli, :messages) do
      {:messages, messages} when is_list(messages) ->
        if {:input, text} in messages do
          :ok
        else
          if System.monotonic_time(:millisecond) >= deadline do
            flunk("input line was not queued in the CLI process")
          else
            Process.sleep(5)
            await_cli_input_loop(cli, text, deadline)
          end
        end

      _ ->
        flunk("CLI stopped before queued input arrived")
    end
  end
end
