# Optional check for a separately reviewed/built rust-mcp-filesystem executable.
# This script never downloads, builds, or installs an external server.
defmodule Ipse.IndependentMCPCheck do
  alias Ipse.MCP.Config

  def complete(_, messages, _tools, _emit) do
    if List.last(messages)["role"] == "tool" do
      {:ok, %{"role" => "assistant", "content" => "Independent MCP check finished."}, %{}}
    else
      calls = approved_calls()

      {:ok,
       %{
         "role" => "assistant",
         "content" => "",
         "tool_calls" =>
           Enum.with_index(calls, fn {name, args}, index ->
             %{
               "id" => "independent-#{index}",
               "type" => "function",
               "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
             }
           end)
       }, %{}}
    end
  end

  defp approved_calls do
    [
      {Config.tool_id("independent", "read_text_file"), %{"path" => "fixture.txt"}},
      {Config.tool_id("independent", "list_directory"), %{}},
      {Config.tool_id("independent", "write_text_file"),
       %{"path" => "approved.txt", "content" => "Independent write verified.\n"}}
    ]
  end

  def run(binary) do
    root =
      Path.join(
        System.tmp_dir!(),
        "ipse-independent-check-#{Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)}"
      )

    workspace = Path.join(root, "workspace")
    File.mkdir_p!(workspace)
    executable = Path.join(workspace, "filesystem-server")
    File.cp!(Path.expand(binary), executable)
    File.chmod!(executable, 0o700)
    File.write!(Path.join(workspace, "fixture.txt"), "Independent MCP verified.\n")
    path = Path.join(root, "mcp.json")

    File.write!(
      path,
      Jason.encode!(%{
        "servers" => [
          %{
            "id" => "independent",
            "command" => executable,
            "args" => ["--root", workspace],
            "tools" => ["read_text_file", "list_directory", "write_text_file"],
            "sandbox" => "native",
            "env" => %{},
            "timeout_ms" => 15_000
          }
        ]
      })
    )

    {:ok, [server]} = Config.load(path)
    {:ok, descriptors} = Ipse.MCP.discover_server(server, workspace)
    3 = length(descriptors)
    read = Enum.find(descriptors, &(&1.name == "read_text_file"))
    "https://json-schema.org/draft/2020-12/schema" = read.input_schema["$schema"]
    list = Enum.find(descriptors, &(&1.name == "list_directory"))
    true = Enum.sort(list.input_schema["properties"]["path"]["type"]) == ["null", "string"]
    write = Enum.find(descriptors, &(&1.name == "write_text_file"))
    false = write.input_schema["properties"]["overwrite"]["default"]

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Ipse.Session,
         cwd: workspace,
         state_dir: Path.join(root, "sessions"),
         subscriber: self(),
         config: %{
           provider: :demo,
           model: "scripted-independent",
           provider_module: __MODULE__,
           approval: :ask,
           home: Path.join(root, "home"),
           mcp_servers: [server]
         }}
      )

    try do
      :ok = Ipse.Session.prompt(pid, "Run the exact independent MCP scratch checks.")
      await(pid, Map.new(approved_calls()))
      "Independent write verified.\n" = File.read!(Path.join(workspace, "approved.txt"))
      id = Ipse.Session.info(pid).id
      {:ok, events} = Ipse.Journal.load(Path.join(root, "sessions"), id)
      intents = Enum.filter(events, &(&1["type"] == "tool_started"))
      3 = length(intents)
      true = Enum.all?(intents, &(&1["approval"] == "approved"))
      results = for e <- events, get_in(e, ["message", "role"]) == "tool", do: e["message"]
      3 = length(results)

      true =
        Enum.all?(results, &(get_in(&1, ["ipse_tool_outcome", "status"]) == "result_recorded"))

      true = Enum.any?(results, &String.contains?(&1["content"], "Independent MCP verified."))
      :ok = Ipse.Session.close(pid)

      {:ok, resumed} =
        DynamicSupervisor.start_child(
          Ipse.Sessions,
          {Ipse.Session,
           cwd: workspace,
           state_dir: Path.join(root, "sessions"),
           id: id,
           subscriber: self(),
           config: %{
             provider: :demo,
             model: "scripted-independent",
             provider_module: __MODULE__,
             approval: :ask,
             home: Path.join(root, "home"),
             mcp_servers: [server]
           }}
        )

      :idle = Ipse.Session.info(resumed).phase
      {:ok, ^events} = Ipse.Journal.load(Path.join(root, "sessions"), id)
      :ok = Ipse.Session.close(resumed)

      IO.puts(
        "PASS: independent MCP native stdio discovery, exact approved read/list/write, schema compatibility, and idle resume. No model service contacted."
      )
    after
      if Process.alive?(pid), do: Ipse.Session.close(pid)
      File.rm_rf!(root)
    end
  end

  defp await(pid, approvals) do
    receive do
      {:ipse, ^pid, {:approval, ref, name, args}} ->
        ^args = Map.fetch!(approvals, name)
        IO.puts("Approving exact scratch call #{name}: " <> Jason.encode!(args))
        :ok = Ipse.Session.approve(pid, ref, true)
        await(pid, Map.delete(approvals, name))

      {:ipse, ^pid, {:done, :ok}} ->
        0 = map_size(approvals)

      {:ipse, ^pid, {:error, _}} ->
        raise "Independent MCP session failed."

      {:ipse, ^pid, {:done, _}} ->
        raise "Independent MCP session did not complete."

      {:ipse, ^pid, _} ->
        await(pid, approvals)
    after
      30_000 ->
        Ipse.Session.cancel(pid)
        raise "Independent MCP check timed out."
    end
  end
end

case System.argv() do
  [binary] ->
    Ipse.IndependentMCPCheck.run(binary)

  _ ->
    raise "Usage: mix run dev/verify-independent-mcp.exs /path/to/reviewed/filesystem-server"
end
