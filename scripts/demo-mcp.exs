# Run with mix run scripts/demo-mcp.exs. This is a scripted model, real stdio MCP.
defmodule Ipse.Examples.MCPDemoModel do
  def complete(_, messages, tools, emit) do
    if List.last(messages)["role"] == "tool" do
      text = "Scripted MCP demo finished. No model service was contacted."
      emit.({:text, text})
      {:ok, %{"role" => "assistant", "content" => text}, %{}}
    else
      true = Enum.any?(tools, &(get_in(&1, ["function", "name"]) == "mcp__demo__write_note"))

      {:ok,
       %{
         "role" => "assistant",
         "content" => "",
         "tool_calls" => [
           %{
             "id" => "demo-note",
             "type" => "function",
             "function" => %{
               "name" => "mcp__demo__write_note",
               "arguments" => Jason.encode!(%{"content" => "Hello through MCP!\n"})
             }
           }
         ]
       }, %{}}
    end
  end
end

root =
  Path.join(
    System.tmp_dir!(),
    "ipse-mcp-demo-#{Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)}"
  )

File.mkdir_p!(root)

args =
  ["--erl", "+S 2:2"] ++
    Enum.flat_map([Jason, MCP.Server, UUID], fn module ->
      ["-pa", Path.dirname(to_string(:code.which(module)))]
    end) ++
    [Path.expand("../priv/mcp-notes.exs", __DIR__)]

path = Path.join(root, "mcp.json")

File.write!(
  path,
  Jason.encode!(%{
    "servers" => [
      %{
        "id" => "demo",
        "command" => System.find_executable("elixir"),
        "args" => args,
        "tools" => ["write_note"],
        "timeout_ms" => 10_000
      }
    ]
  })
)

{:ok, servers} = Ipse.MCP.Config.load(path)

config = %{
  provider: :demo,
  model: "scripted-mcp",
  provider_module: Ipse.Examples.MCPDemoModel,
  approval: :ask,
  home: Path.join(root, "home"),
  mcp_servers: servers
}

{:ok, pid} =
  DynamicSupervisor.start_child(
    Ipse.Sessions,
    {Ipse.Session,
     config: config, cwd: root, state_dir: Path.join(root, "sessions"), subscriber: self()}
  )

IO.puts("Scripted MCP demo workspace: #{root}\nReal local SDK server; no live model.")
:ok = Ipse.Session.prompt(pid, "Write the example note through MCP.")

await = fn await ->
  receive do
    {:ipse, ^pid, {:approval, ref, "mcp__demo__write_note", args}} ->
      true = args == %{"content" => "Hello through MCP!\n"}
      IO.puts("Approving this one scripted scratch call:\n" <> Jason.encode!(args, pretty: true))
      :ok = Ipse.Session.approve(pid, ref, true)
      await.(await)

    {:ipse, ^pid, {:error, message}} ->
      raise message

    {:ipse, ^pid, {:done, :ok}} ->
      :ok

    {:ipse, ^pid, _} ->
      await.(await)
  after
    15_000 ->
      Ipse.Session.cancel(pid)
      raise "MCP demonstration timed out"
  end
end

try do
  await.(await)
  "Hello through MCP!\n" = File.read!(Path.join(root, "mcp-note.txt"))
  IO.puts("PASS: approved MCP write and result verified. Session: #{Ipse.Session.info(pid).id}")
after
  DynamicSupervisor.terminate_child(Ipse.Sessions, pid)
end
