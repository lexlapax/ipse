defmodule Ipse.ProfileSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal}

  defmodule Parent do
    def complete(config, messages, _tools, _emit) do
      send(config.test_pid, {:profile_parent_call, messages})

      if List.last(messages)["role"] == "tool" do
        {:ok, %{"role" => "assistant", "content" => List.last(messages)["content"]}, %{}}
      else
        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "provider_data" => %{"opaque" => "PARENT_NATIVE_PRIVATE"},
           "tool_calls" => [
             %{
               "id" => "route",
               "type" => "function",
               "function" => %{
                 "name" => "delegate",
                 "arguments" =>
                   Jason.encode!(%{
                     "task" => "Return selected evidence",
                     "context" => "SELECTED_EVIDENCE",
                     "profile" => config.selected
                   })
               }
             }
           ]
         }, %{}}
      end
    end
  end

  setup do
    root =
      Path.join(System.tmp_dir!(), "ipse-profile-session-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, dir: Path.join(root, "sessions")}
  end

  defp start(c, profile, selected \\ "local") do
    config = %{
      provider: :demo,
      model: "parent",
      provider_module: Parent,
      test_pid: self(),
      home: Path.join(c.root, "home"),
      approval: :ask,
      sandbox: :off,
      max_steps: 4,
      api_key: "PARENT_CREDENTIAL_PRIVATE",
      subagents: true,
      selected: selected,
      profiles: %{"local" => profile},
      roles: %{"routine" => "local"}
    }

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: c.root, state_dir: c.dir, subscriber: self()}
      )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    pid
  end

  test "approved routing uses real Ollama wire, private child history and durable execution metadata",
       c do
    response =
      Jason.encode!(%{
        model: "fixture-reported",
        message: %{role: "assistant", content: "Child verified SELECTED_EVIDENCE"},
        done: true
      }) <> "\n"

    {base, server} = fixture(response)

    profile = %{
      "provider" => "ollama",
      "model" => "configured-local",
      "base_url" => base,
      "timeout_ms" => 5000
    }

    parent = start(c, profile)
    :ok = Session.prompt(parent, "PARENT_HISTORY_PRIVATE")
    assert_receive {:ipse, ^parent, {:approval, ref, "delegate", args}}, 2000
    assert args["profile"] == "local"
    assert :ok = Session.approve(parent, ref, true)
    assert_receive {:ipse, ^parent, {:subagent, child, :started}}, 2000
    assert_receive {:ipse, ^parent, {:done, :ok}}, 5000
    {headers, request} = Task.await(server)
    assert request["model"] == "configured-local"
    assert Jason.encode!(request) =~ "SELECTED_EVIDENCE"
    refute Jason.encode!(request) <> headers =~ "PARENT_HISTORY_PRIVATE"
    refute Jason.encode!(request) <> headers =~ "PARENT_NATIVE_PRIVATE"
    refute Jason.encode!(request) <> headers =~ "PARENT_CREDENTIAL_PRIVATE"

    refute Enum.any?(
             request["tools"],
             &(get_in(&1, ["function", "name"]) in ["delegate", "delegate_parallel"])
           )

    id = Session.info(parent).id
    child_dir = Path.join([c.dir, "subagents", id])
    {:ok, child_events} = Journal.load(child_dir, child)
    meta = hd(child_events)["metadata"]
    assert meta["provider"] == "ollama"
    assert meta["execution"]["id"] == "local"
    assert meta["execution"]["role"] == "routine"
    assert meta["mcp_servers"] == []
    assert Session.info(parent).final =~ "Child verified SELECTED_EVIDENCE"
    :ok = Session.close(parent)
    before_bytes = File.read!(Path.join(c.dir, id <> ".jsonl"))

    config = %{
      provider: :demo,
      model: "parent",
      home: Path.join(c.root, "home"),
      approval: :deny,
      subagents: true
    }

    {:ok, resumed} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: c.root, state_dir: c.dir, id: id, subscriber: self()}
      )

    assert Session.info(resumed).phase == :idle
    assert File.read!(Path.join(c.dir, id <> ".jsonl")) == before_bytes
    :ok = Session.close(resumed)
  end

  test "invented profile fails before child creation or approval and never falls back", c do
    parent = start(c, %{"provider" => "ollama", "model" => "fixture"}, "invented")
    :ok = Session.prompt(parent, "route")
    assert_receive {:ipse, ^parent, {:done, :ok}}, 2000
    refute_receive {:ipse, ^parent, {:approval, _, _, _}}, 50
    refute_receive {:ipse, ^parent, {:subagent, _, :started}}, 50
    assert Session.info(parent).final =~ "not configured"
    refute File.exists?(Path.join(c.dir, "subagents"))
  end

  defp fixture(body) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        {headers, payload} = request(socket, "")

        :ok =
          :gen_tcp.send(
            socket,
            "HTTP/1.1 200 OK\r\ncontent-type: application/x-ndjson\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
              body
          )

        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        {headers, Jason.decode!(payload)}
      end)

    {"http://127.0.0.1:#{port}", task}
  end

  defp request(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [headers, body] ->
        [_, size] = Regex.run(~r/content-length:\s*(\d+)/i, headers)
        {headers, rest(socket, body, String.to_integer(size))}

      [_] ->
        {:ok, chunk} = :gen_tcp.recv(socket, 0, 5000)
        request(socket, buffer <> chunk)
    end
  end

  defp rest(_, body, size) when byte_size(body) >= size, do: body

  defp rest(socket, body, size) do
    {:ok, chunk} = :gen_tcp.recv(socket, 0, 5000)
    rest(socket, body <> chunk, size)
  end
end
