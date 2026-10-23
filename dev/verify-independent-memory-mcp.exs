# Optional check for the separately reviewed mcp-memory 2.0.0 executable.
# This script never downloads, builds, installs, or enables a server for normal use.
defmodule Ipse.IndependentMemoryMCPCheck do
  alias Ipse.MCP
  alias Ipse.MCP.Config

  @entity %{
    "name" => "ipse-synthetic-record",
    "entityType" => "fixture",
    "observations" => ["Independent memory interoperability verified."]
  }

  def complete(_, messages, tools, _emit) do
    last = List.last(messages)

    if last["role"] == "tool" do
      {:ok, %{"role" => "assistant", "content" => "Synthetic memory check finished."}, %{}}
    else
      stage = last["content"]
      calls = calls(stage)

      true =
        Enum.all?(calls, fn {name, _args} ->
          Enum.any?(tools, &(get_in(&1, ["function", "name"]) == name))
        end)

      {:ok,
       %{
         "role" => "assistant",
         "content" => "",
         "tool_calls" =>
           Enum.with_index(calls, fn {name, args}, index ->
             %{
               "id" => "#{stage}-#{index}",
               "type" => "function",
               "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
             }
           end)
       }, %{}}
    end
  end

  defp calls("deny-write"), do: [create_call()]

  defp calls("approve-checks") do
    [
      create_call(),
      {Config.tool_id("memory", "get_entity"), %{"name" => @entity["name"]}},
      {Config.tool_id("memory", "search_nodes"), %{"query" => @entity["name"], "limit" => 1}},
      {Config.tool_id("memory", "get_entity"), %{"name" => "ipse-missing-record"}}
    ]
  end

  defp create_call,
    do: {Config.tool_id("memory", "create_entities"), %{"entities" => [@entity]}}

  def run(binary, mode \\ :stdio) do
    root =
      Path.join(
        System.tmp_dir!(),
        "ipse-independent-memory-#{Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)}"
      )

    workspace = Path.join(root, "workspace")
    home = Path.join(root, "home")
    File.mkdir_p!(workspace)
    File.mkdir!(home)
    File.chmod!(home, 0o700)
    previous_home = System.get_env("IPSE_HOME")
    previous_token = System.get_env("IPSE_MCP_INDEPENDENT_TOKEN")
    System.put_env("IPSE_HOME", home)

    try do
      check(binary, root, workspace, home, mode)
    after
      cleanup =
        if port = Process.delete(:independent_http_port),
          do: Ipse.Runner.close_stdio(port),
          else: :ok

      if previous_token,
        do: System.put_env("IPSE_MCP_INDEPENDENT_TOKEN", previous_token),
        else: System.delete_env("IPSE_MCP_INDEPENDENT_TOKEN")

      if previous_home,
        do: System.put_env("IPSE_HOME", previous_home),
        else: System.delete_env("IPSE_HOME")

      File.rm_rf!(root)
      :ok = cleanup
    end
  end

  defp check(binary, root, workspace, home, mode) do
    executable = Path.join(workspace, "memory-server")
    File.cp!(Path.expand(binary), executable)
    File.chmod!(executable, 0o700)
    graph = Path.join(workspace, "fixture.mcpmem")
    path = Path.join(root, "mcp.json")

    entry =
      if mode == :http do
        {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
        {:ok, {_, port}} = :inet.sockname(listener)
        :gen_tcp.close(listener)
        token = Base.encode16(:crypto.strong_rand_bytes(24), case: :lower)
        System.put_env("IPSE_MCP_INDEPENDENT_TOKEN", token)

        {:ok, process} =
          Ipse.Runner.open_stdio(
            executable,
            [
              "--memory-file",
              graph,
              "--transport",
              "http",
              "--bind",
              "127.0.0.1:#{port}",
              "--log-level",
              "error"
            ],
            workspace,
            %{"MCP_MEMORY_DURABILITY" => "sync", "MCP_MEMORY_AUTH_TOKEN" => token},
            120_000
          )

        Process.put(:independent_http_port, process)

        true =
          Enum.any?(1..100, fn _ ->
            case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 50) do
              {:ok, socket} ->
                :gen_tcp.close(socket)
                true

              _ ->
                Process.sleep(25)
                false
            end
          end)

        %{
          "id" => "memory",
          "transport" => "http",
          "url" => "http://127.0.0.1:#{port}/mcp",
          "allow_insecure_loopback" => true,
          "bearer_env" => "IPSE_MCP_INDEPENDENT_TOKEN",
          "tools" => ["create_entities", "get_entity", "search_nodes"],
          "timeout_ms" => 15_000
        }
      else
        %{
          "id" => "memory",
          "command" => executable,
          "args" => ["--memory-file", graph, "--transport", "stdio", "--log-level", "error"],
          "tools" => ["create_entities", "get_entity", "search_nodes"],
          "sandbox" => "native",
          "env" => %{"MCP_MEMORY_DURABILITY" => "sync"},
          "timeout_ms" => 15_000
        }
      end

    File.write!(
      path,
      Jason.encode!(%{
        "servers" => [entry]
      })
    )

    {:ok, [server]} = Config.load(path)
    {:ok, descriptors} = MCP.discover_server(server, workspace)
    true = Enum.sort(Enum.map(descriptors, & &1.name)) == Enum.sort(server.tools)
    # This upstream opens its scratch log during startup, before any tool call.
    empty_graph = File.read!(graph)

    opts = [
      cwd: workspace,
      state_dir: Path.join(root, "sessions"),
      subscriber: self(),
      config: %{
        provider: :demo,
        model: "scripted-independent-memory",
        provider_module: __MODULE__,
        approval: :ask,
        home: home,
        mcp_servers: [server]
      }
    ]

    {id, events, written_graph} =
      with_session(opts, fn pid ->
        prompt(pid, "deny-write", false)
        ^empty_graph = File.read!(graph)
        {:ok, denied_events} = Ipse.Journal.load(opts[:state_dir], Ipse.Session.info(pid).id)
        [] = Enum.filter(denied_events, &(&1["type"] == "tool_started"))

        prompt(pid, "approve-checks", true)
        id = Ipse.Session.info(pid).id
        {:ok, events} = Ipse.Journal.load(opts[:state_dir], id)
        verify_events(events, server)
        {id, events, File.read!(graph)}
      end)

    true = byte_size(written_graph) > byte_size(empty_graph)

    with_session(Keyword.put(opts, :id, id), fn resumed ->
      :idle = Ipse.Session.info(resumed).phase
      {:ok, ^events} = Ipse.Journal.load(opts[:state_dir], id)
      ^written_graph = File.read!(graph)
    end)

    ^written_graph = File.read!(graph)

    IO.puts(
      "PASS: independent memory MCP #{mode} discovery, denied write without dispatch, " <>
        "exact approved write/get/search, persistence across connections, tool error, " <>
        "and idle resume without replay. No model service contacted."
    )
  end

  defp with_session(opts, fun) do
    {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})

    try do
      fun.(pid)
    after
      if Process.alive?(pid), do: Ipse.Session.close(pid)
    end
  end

  defp verify_events(events, server) do
    intents = Enum.filter(events, &(&1["type"] == "tool_started"))
    expected = calls("approve-checks")
    ^expected = Enum.map(intents, &{&1["name"], &1["arguments"]})

    true =
      Enum.all?(intents, fn event ->
        event["approval"] == "approved" and event["mcp"]["server_id"] == "memory" and
          get_in(event, ["mcp", "origin", "sandbox_requested"]) == to_string(server.sandbox) and
          get_in(event, ["mcp", "origin", "configured_endpoint_fingerprint"]) ==
            server.fingerprint
      end)

    results = for e <- events, get_in(e, ["message", "role"]) == "tool", do: e["message"]

    ["denied", "result_recorded", "result_recorded", "result_recorded", "error"] =
      Enum.map(results, &get_in(&1, ["ipse_tool_outcome", "status"]))

    [_denied, created, fetched, searched, missing] = results
    [@entity] = Jason.decode!(created["content"])
    @entity = Jason.decode!(fetched["content"])
    [@entity] = Jason.decode!(searched["content"])
    true = String.contains?(missing["content"], "ipse-missing-record")
    true = String.contains?(missing["content"], "not found")
  end

  defp prompt(pid, stage, allow) do
    :ok = Ipse.Session.prompt(pid, stage)
    await(pid, calls(stage), allow, System.monotonic_time(:millisecond) + 30_000)
  end

  defp await(pid, approvals, allow, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:ipse, ^pid, {:approval, ref, name, args}} ->
        [{^name, ^args} | rest] = approvals
        decision = if allow, do: "Approving", else: "Denying"
        IO.puts("#{decision} exact scratch call #{name}: " <> Jason.encode!(args))
        :ok = Ipse.Session.approve(pid, ref, allow)
        await(pid, rest, allow, deadline)

      {:ipse, ^pid, {:done, :ok}} ->
        [] = approvals

      {:ipse, ^pid, {:error, message}} ->
        raise "Independent memory MCP session failed: #{message}"

      {:ipse, ^pid, {:done, _}} ->
        raise "Independent memory MCP session did not complete."

      {:ipse, ^pid, _} ->
        await(pid, approvals, allow, deadline)
    after
      remaining ->
        Ipse.Session.cancel(pid)
        raise "Independent memory MCP check timed out."
    end
  end
end

case System.argv() do
  [binary] ->
    Ipse.IndependentMemoryMCPCheck.run(binary)

  [binary, "--http"] ->
    Ipse.IndependentMemoryMCPCheck.run(binary, :http)

  _ ->
    raise "Usage: mix run dev/verify-independent-memory-mcp.exs /path/to/reviewed/mcp-memory [--http]"
end
