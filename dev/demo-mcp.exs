# Run with mix run dev/demo-mcp.exs. This is a scripted model, real stdio MCP.
defmodule Ipse.Examples.MCPDemoModel do
  def complete(_, messages, tools, emit) do
    if List.last(messages)["role"] == "tool" do
      text = "Scripted MCP demo finished. No model service was contacted."
      emit.({:text, text})
      {:ok, %{"role" => "assistant", "content" => text}, %{}}
    else
      true = Enum.any?(tools, &(get_in(&1, ["function", "name"]) == "mcp__demo__write_note"))

      resource_id = Ipse.MCP.Config.resource_id("demo", "notes://guide")
      prompt_id = Ipse.MCP.Config.prompt_id("demo", "summarize")

      true =
        Enum.all?([resource_id, prompt_id], fn name ->
          Enum.any?(tools, &(get_in(&1, ["function", "name"]) == name))
        end)

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
           },
           %{
             "id" => "demo-resource",
             "type" => "function",
             "function" => %{"name" => resource_id, "arguments" => "{}"}
           },
           %{
             "id" => "demo-prompt",
             "type" => "function",
             "function" => %{
               "name" => prompt_id,
               "arguments" => Jason.encode!(%{"topic" => "scratch notes"})
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
    [Path.expand("../priv/demo/mcp-notes.exs", __DIR__)]

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
        "resources" => ["notes://guide"],
        "prompts" => ["summarize"],
        "env" => %{"PATH" => Path.join(to_string(:code.root_dir()), "bin") <> ":/usr/bin:/bin"},
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

    {:ipse, ^pid, {:approval, ref, name, args}} ->
      true =
        {name, args} in [
          {Ipse.MCP.Config.resource_id("demo", "notes://guide"), %{}},
          {Ipse.MCP.Config.prompt_id("demo", "summarize"), %{"topic" => "scratch notes"}}
        ]

      IO.puts("Approving this one scripted #{name} call:\n" <> Jason.encode!(args, pretty: true))
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
  {:ok, events} = Ipse.Journal.load(Path.join(root, "sessions"), Ipse.Session.info(pid).id)
  results = for e <- events, get_in(e, ["message", "role"]) == "tool", do: e["message"]["content"]
  3 = length(results)
  true = Enum.any?(results, &String.contains?(&1, "plain UTF-8 text"))
  true = Enum.any?(results, &String.contains?(&1, "Summarize this topic: scratch notes"))

  IO.puts(
    "PASS: approved MCP write, resource and prompt results verified. Session: #{Ipse.Session.info(pid).id}"
  )
after
  DynamicSupervisor.terminate_child(Ipse.Sessions, pid)
end
