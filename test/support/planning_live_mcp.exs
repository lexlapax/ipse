ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
[mode, root] = System.argv()
assert mode in ~w(entry_release exit_kill)

defmodule Ipse.Test.PlanningLiveMCP do
  import ExUnit.Assertions

  def complete(_config, messages, _tools, _emit) do
    last = messages |> Enum.reject(&Ipse.Session.Reference.reference?/1) |> List.last()

    if last["role"] == "tool" do
      {:ok, %{"role" => "assistant", "content" => "Live read finished"}, %{}}
    else
      {:ok,
       %{
         "role" => "assistant",
         "tool_calls" => [
           %{
             "id" => "live-read",
             "type" => "function",
             "function" => %{
               "name" => "mcp__notes__lookup",
               "arguments" => ~s({"query":"public"})
             }
           }
         ]
       }, %{}}
    end
  end

  def await(check, remaining \\ 1_000)
  def await(_, 0), do: flunk("live MCP fixture did not settle")

  def await(check, remaining) do
    if check.() do
      :ok
    else
      Process.sleep(10)
      await(check, remaining - 1)
    end
  end

  def alive?(pid) do
    case File.read("/proc/#{pid}/stat") do
      {:ok, bytes} ->
        [_prefix, suffix] = String.split(bytes, ") ", parts: 2)
        not String.starts_with?(suffix, ["Z ", "X "])

      {:error, :enoent} ->
        false
    end
  end

  def monitor_live(session, root, mode) do
    await(fn -> File.exists?(Path.join(root, "planning-read-ready")) end)
    state = :sys.get_state(session)
    assert state.phase != :idle and not is_nil(state.task)
    [transport] = Map.keys(state.mcp_resources)
    transport_state = :sys.get_state(transport)
    client = transport_state.owner
    assert is_pid(client) and Process.alive?(client)
    {:os_pid, helper} = Port.info(transport_state.port, :os_pid)
    server = File.read!(Path.join(root, "planning-read-ready")) |> String.to_integer()
    assert alive?(helper) and alive?(server)
    assert File.read!(Path.join(root, "calls.log")) == "lookup\n"
    worker = state.task.pid
    refs = for pid <- Enum.uniq([transport, worker, client]), do: {Process.monitor(pid), pid}
    ceiling = if mode == "entry_release", do: "normal", else: "planning"
    assert Ipse.Session.info(session).execution_mode["ceiling"] == ceiling
    File.write!(Path.join(root, "live-resources-captured"), "captured")

    if mode == "exit_kill" do
      await(fn -> File.exists?(Path.join(root, "kill-session")) end)
      {:ok, before_kill} = Ipse.Journal.load(Path.join(root, "state"), state.id)
      refute Enum.any?(before_kill, &(&1["type"] == "planning_exited"))
      assert Process.alive?(transport) and alive?(helper) and alive?(server)
      Process.exit(session, :kill)
    else
      await(fn -> File.exists?(Path.join(root, "planning-read-release")) end)
    end

    for {ref, pid} <- refs do
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 10_000
    end

    await(fn ->
      is_nil(Port.info(transport_state.port)) and not alive?(helper) and not alive?(server)
    end)

    %{
      transport_stopped: true,
      sdk_client_stopped: true,
      worker_stopped: true,
      native_helper_stopped: true,
      server_stopped: true
    }
  end
end

document = %{
  "servers" => [
    %{
      "id" => "notes",
      "command" => System.find_executable("elixir"),
      "args" => [
        "--erl",
        "+S 2:2",
        "-pa",
        Path.dirname(to_string(:code.which(Jason))),
        Path.expand("mcp_server.exs", __DIR__),
        "planning_read_controlled"
      ],
      "tools" => ["lookup"],
      "env" => %{"PATH" => Path.join(to_string(:code.root_dir()), "bin") <> ":/usr/bin:/bin"},
      "timeout_ms" => 20_000
    }
  ]
}

path = Path.join(root, "mcp.json")
File.write!(path, Jason.encode!(document))
{:ok, [server]} = Ipse.MCP.Config.load(path)
{:ok, [tool]} = Ipse.MCP.discover([server], root)

reads = %{
  tool.tool_id => %{
    "version" => 1,
    "server_id" => server.id,
    "tool" => tool.name,
    "endpoint_sha256" => server.fingerprint,
    "descriptor_sha256" => tool.digest
  }
}

config = %{
  provider: :demo,
  model: "synthetic",
  provider_module: Ipse.Test.PlanningLiveMCP,
  home: Path.join(root, "home"),
  approval: :allow,
  mcp_servers: [server],
  planning_mcp_reads: reads,
  configuration: %{fingerprint: Ipse.JSON.digest([reads]), planning_mcp_reads: reads, sources: []}
}

dir = Path.join(root, "state")
opts = [config: config, cwd: root, state_dir: dir, subscriber: self()]
{:ok, session} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
id = Ipse.Session.info(session).id
monitor = Process.monitor(session)

observer =
  spawn_link(fn ->
    result = Ipse.Test.PlanningLiveMCP.monitor_live(session, root, mode)
    File.write!(Path.join(root, "resources-stopped.json"), Jason.encode!(result))
  end)

assert if(mode == "exit_kill", do: 1, else: 0) ==
         Ipse.CLI.Terminal.interact(session, monitor, true, nil, root)

Ipse.Test.PlanningLiveMCP.await(fn ->
  File.exists?(Path.join(root, "resources-stopped.json")) and not Process.alive?(observer)
end)

resources = File.read!(Path.join(root, "resources-stopped.json")) |> Jason.decode!()

if mode == "entry_release" do
  state = :sys.get_state(session)
  assert state.mcp_resources == %{} and is_nil(state.task)
  assert Ipse.Session.info(session).execution_mode["ceiling"] == "normal"
  assert :ok = Ipse.Session.close_confirmed(session)
end

{:ok, events} = Ipse.Journal.load(dir, id)
assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
assert :ok = Ipse.Session.PlanningMCP.validate_events(events, id)
assert Enum.count(events, &(&1["type"] == "tool_started")) == 1
assert Enum.count(events, &(&1["type"] == "planning_entry_observed")) == 1

assert Enum.count(events, &(&1["type"] == "planning_exited")) ==
         if(mode == "entry_release", do: 1, else: 0)

if mode == "entry_release" do
  result = Enum.find_index(events, &(get_in(&1, ["message", "role"]) == "tool"))
  entered = Enum.find_index(events, &(&1["type"] == "planning_entry_observed"))
  assert is_integer(result) and result < entered
else
  assert Enum.count(events, &(&1["type"] == "planning_mcp_read_intent")) == 1

  {:ok, resumed} =
    DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, Keyword.put(opts, :id, id)})

  assert Ipse.Session.info(resumed).execution_mode["ceiling"] == "planning"
  assert :sys.get_state(resumed).mcp_resources == %{}

  assert Enum.any?(
           :sys.get_state(resumed).messages,
           &(get_in(&1, ["ipse_tool_outcome", "status"]) == "unknown")
         )

  assert :ok = Ipse.Session.close_confirmed(resumed)
  {:ok, after_resume} = Ipse.Journal.load(dir, id)
  assert Enum.count(after_resume, &(&1["type"] == "tool_started")) == 1
  assert Enum.count(after_resume, &(&1["type"] == "planning_mcp_read_intent")) == 1
  refute Enum.any?(after_resume, &(&1["type"] == "planning_exited"))
end

assert File.read!(Path.join(root, "calls.log")) == "lookup\n"
IO.puts("PLANNING_LIVE_MCP_PASSED " <> Jason.encode!(Map.put(resources, :mode, mode)))
