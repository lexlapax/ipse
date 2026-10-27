ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
root = List.last(System.argv())

defmodule DraftMCPResumeProvider do
  def complete(config, messages, tools, _) do
    send(config.fixture_owner, {:model_input, messages, tools})
    last = messages |> Enum.reject(&Ipse.Session.Reference.reference?/1) |> List.last()

    cond do
      last["content"] == "preload" ->
        {:ok, %{"role" => "assistant", "content" => "ready"}, %{}}

      last["role"] == "tool" ->
        {:ok, %{"role" => "assistant", "content" => "proposal"}, %{}}

      true ->
        args = %{"questions" => [%{"id" => "detail", "kind" => "text", "prompt" => "Detail?"}]}

        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "draft-q",
               "type" => "function",
               "function" => %{"name" => "ask_operator", "arguments" => Jason.encode!(args)}
             }
           ]
         }, %{}}
    end
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
        Path.expand("test/support/mcp_catalog_server.exs"),
        cond do
          "drift" in System.argv() ->
            "metadata_drift"

          "interrupt" in System.argv() or "cancel" in System.argv() or "timeout" in System.argv() ->
            "revalidation_hold"

          true ->
            "normal"
        end
      ],
      "resources" => ["notes://guide"],
      "prompts" => ["summarize"],
      "env" => %{"PATH" => Path.join(to_string(:code.root_dir()), "bin") <> ":/usr/bin:/bin"},
      "timeout_ms" => 5_000
    }
  ]
}

path = Path.join(root, "mcp.json")
File.write!(path, Jason.encode!(document))
{:ok, servers} = Ipse.MCP.Config.load(path)

config = %{
  provider: :demo,
  model: "catalog-fixture",
  provider_module: DraftMCPResumeProvider,
  fixture_owner: self(),
  home: Path.join(root, "home"),
  mcp_servers: servers,
  approval: :allow,
  operator_questions: true
}

opts = [config: config, cwd: root, state_dir: Path.join(root, "state"), subscriber: self()]
{:ok, pid} = Ipse.Session.start_link(opts)
Process.unlink(pid)
id = Ipse.Session.info(pid).id

definitions =
  if "first" in System.argv() do
    assert :ok = Ipse.Session.start_draft(pid, "private requirement")
    assert_receive {:model_input, _, definitions}, 10_000
    definitions
  else
    assert :ok = Ipse.Session.prompt(pid, "preload")
    assert_receive {:model_input, _, definitions}, 10_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    assert :ok = Ipse.Session.start_draft(pid, "private requirement")
    assert_receive {:model_input, _, ^definitions}, 10_000
    definitions
  end

assert_receive {:ipse, ^pid, {:question, "draft-q", _}}, 10_000
before = File.read!(Path.join(root, "catalog.log"))
ref = Process.monitor(pid)
Process.exit(pid, :kill)
assert_receive {:DOWN, ^ref, :process, ^pid, _}, 10_000
File.write!(Path.join(root, "trace-discovery"), "enabled")
if "drift" in System.argv(), do: File.write!(Path.join(root, "catalog-force-drift"), "changed")

definitions =
  if "forge" in System.argv() do
    journal = Path.join([root, "state", id <> ".jsonl"])
    bytes = File.read!(journal)
    {:ok, events} = Ipse.Journal.load(Path.join(root, "state"), id)
    started = Enum.find(events, &(&1["type"] == "draft_started"))
    snapshot = started["mcp_snapshot"]
    original = get_in(snapshot, ["definitions", Access.at(0), "function", "description"])
    replacement = String.duplicate("X", byte_size(original))

    forged =
      update_in(snapshot["definitions"], fn defs ->
        List.update_at(defs, 0, &put_in(&1, ["function", "description"], replacement))
      end)

    old_self = snapshot["definitions_sha256"]
    new_self = Ipse.JSON.digest(forged["definitions"])
    old_catalog = Ipse.JSON.digest(snapshot["base_definitions"] ++ snapshot["definitions"])
    new_catalog = Ipse.JSON.digest(forged["base_definitions"] ++ forged["definitions"])

    changed =
      bytes
      |> String.replace(original, replacement, global: false)
      |> String.replace(old_self, new_self, global: false)
      |> String.replace(old_catalog, new_catalog)

    assert byte_size(changed) == byte_size(bytes)
    File.write!(journal, changed)
    snapshot["base_definitions"] ++ forged["definitions"]
  else
    definitions
  end

{:ok, resumed} = Ipse.Session.start_link(Keyword.put(opts, :id, id))
Process.unlink(resumed)

if "interrupt" in System.argv() or "cancel" in System.argv() or "timeout" in System.argv(),
  do: File.write!(Path.join(root, "hold-discovery"), "hold")

owner = self()

reader =
  spawn(fn ->
    receive do
      {:read, channel, request} ->
        send(owner, {:result, Ipse.Session.observe_channel(resumed, channel, request, 30_000)})

        receive do
          :stop -> :ok
        end
    end
  end)

{:ok, channel} = Ipse.Session.open_input_channel(resumed, reader)
{:ok, render} = Ipse.Session.render_question(resumed, channel, "detail")
send(reader, {:read, channel, %{"kind" => "question", "render_id" => render["render_id"]}})
assert_receive {:result, {:ok, text, witness}}, 10_000
assert :ok = Ipse.Session.answer_observed(resumed, channel, render["render_id"], text, witness)
send(reader, :stop)

if "interrupt" in System.argv() or "cancel" in System.argv() do
  wait = fn wait, n ->
    cond do
      n == 0 ->
        flunk("revalidation did not begin")

      :sys.get_state(resumed).phase == :mcp_discovery and
          File.exists?(Path.join(root, "revalidation-held.pid")) ->
        :ok

      true ->
        Process.sleep(10)
        wait.(wait, n - 1)
    end
  end

  wait.(wait, 500)
  held_pid = File.read!(Path.join(root, "revalidation-held.pid"))

  if "cancel" in System.argv() do
    assert :ok = Ipse.Session.cancel_draft(resumed)
    assert elem(System.cmd("kill", ["-0", held_pid], stderr_to_stdout: true), 1) != 0
    assert :ok = Ipse.Session.close_confirmed(resumed)
    {:ok, settled} = Ipse.Journal.load(Path.join(root, "state"), id)

    assert Enum.any?(
             settled,
             &(&1["type"] == "draft_mcp_revalidation_result" and &1["result"] == "unknown")
           )

    assert {:ok, _} = Ipse.Session.Saved.restore(settled, id)
    IO.puts("SYNTHETIC_DRAFT_MCP_INTERRUPT_PASSED")
    System.halt(0)
  end

  monitor = Process.monitor(resumed)
  Process.exit(resumed, :kill)
  assert_receive {:DOWN, ^monitor, :process, ^resumed, _}, 10_000

  dead = fn dead, n ->
    cond do
      elem(System.cmd("kill", ["-0", held_pid], stderr_to_stdout: true), 1) != 0 ->
        :ok

      n == 0 ->
        flunk("MCP server survived owner loss")

      true ->
        Process.sleep(10)
        dead.(dead, n - 1)
    end
  end

  dead.(dead, 500)
  {:ok, recovered} = Ipse.Session.start_link(Keyword.put(opts, :id, id))
  assert :sys.get_state(recovered).draft_mcp_interrupted
  refute_receive {:model_input, _, _}, 200
  {:ok, events} = Ipse.Journal.load(Path.join(root, "state"), id)
  assert Enum.count(events, &(&1["type"] == "draft_mcp_revalidation_intent")) == 1
  refute Enum.any?(events, &(&1["type"] == "draft_mcp_revalidation_result"))
  intent = Enum.find(events, &(&1["type"] == "draft_mcp_revalidation_intent"))
  assert {:ok, %{interrupted: true}} = Ipse.Session.DraftMCP.restore(events, id)

  assert {:error, :invalid_draft_mcp_catalog} =
           Ipse.Session.DraftMCP.restore(events ++ [intent], id)

  bad_result = %{
    "type" => "draft_mcp_revalidation_result",
    "version" => 1,
    "session_id" => id,
    "revalidation_id" => Ipse.Usage.id(),
    "result" => "matched"
  }

  assert {:error, :invalid_draft_mcp_catalog} =
           Ipse.Session.DraftMCP.restore(events ++ [bad_result], id)

  unknown = %{bad_result | "revalidation_id" => intent["revalidation_id"], "result" => "unknown"}

  assert {:ok, %{interrupted: true, pending: nil}} =
           Ipse.Session.DraftMCP.restore(events ++ [unknown], id)

  assert {:error, :invalid_draft_mcp_catalog} =
           Ipse.Session.DraftMCP.restore(
             events ++ [unknown, Map.put(intent, "revalidation_id", Ipse.Usage.id())],
             id
           )

  prefix = Enum.reject(events, &(&1["type"] == "draft_mcp_revalidation_intent"))
  bad_turn = Map.put(intent, "turn_id", Ipse.Usage.id())

  assert {:error, :invalid_draft_mcp_catalog} =
           Ipse.Session.DraftMCP.restore(prefix ++ [bad_turn], id)

  bad_session = Map.put(intent, "session_id", Ipse.Usage.id())

  assert {:error, :invalid_draft_mcp_catalog} =
           Ipse.Session.DraftMCP.restore(prefix ++ [bad_session], nil)

  attempts =
    Enum.flat_map(1..17, fn _ ->
      attempt = Map.put(intent, "revalidation_id", Ipse.Usage.id())
      result = %{bad_result | "revalidation_id" => attempt["revalidation_id"]}
      [attempt, result]
    end)

  assert {:ok, %{attempts: 16}} =
           Ipse.Session.DraftMCP.restore(prefix ++ Enum.take(attempts, 32), id)

  assert {:error, :invalid_draft_mcp_catalog} =
           Ipse.Session.DraftMCP.restore(prefix ++ attempts, id)

  assert :ok = Ipse.Session.cancel_draft(recovered)
  assert :ok = Ipse.Session.close_confirmed(recovered)
  {:ok, settled} = Ipse.Journal.load(Path.join(root, "state"), id)

  assert Enum.any?(
           settled,
           &(&1["type"] == "draft_mcp_revalidation_result" and &1["result"] == "unknown")
         )

  assert {:ok, _} = Ipse.Session.Saved.restore(settled, id)
  IO.puts("SYNTHETIC_DRAFT_MCP_INTERRUPT_PASSED")
  System.halt(0)
end

if "timeout" in System.argv() do
  assert_receive {:ipse, ^resumed, {:error, _}}, 15_000
  assert_receive {:ipse, ^resumed, {:done, :error}}, 15_000
  refute_receive {:model_input, _, ^definitions}, 200
else
  if "forge" in System.argv() or "drift" in System.argv() do
    assert_receive {:ipse, ^resumed, {:error, reason}}, 10_000
    assert reason =~ "catalog changed"
    assert_receive {:ipse, ^resumed, {:done, :error}}, 10_000
    refute_receive {:model_input, _, ^definitions}, 200
  else
    assert_receive {:model_input, messages, ^definitions}, 10_000

    assert Enum.any?(
             messages,
             &(is_binary(&1["content"]) and String.contains?(&1["content"], "synthetic answer"))
           )

    assert_receive {:ipse, ^resumed, {:done, :ok}}, 10_000
  end
end

after_log = File.read!(Path.join(root, "catalog.log"))
assert String.starts_with?(after_log, before) and after_log != before
delta = binary_part(after_log, byte_size(before), byte_size(after_log) - byte_size(before))
refute delta =~ "private requirement"
refute delta =~ "synthetic answer"
refute delta =~ "read_resource"
refute delta =~ "get_prompt"
assert :ok = Ipse.Session.cancel_draft(resumed)
assert :ok = Ipse.Session.close_confirmed(resumed)
{:ok, events} = Ipse.Journal.load(Path.join(root, "state"), id)

assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
assert Enum.count(events, &(&1["type"] == "draft_mcp_revalidation_intent")) == 1

assert Enum.any?(
         events,
         &(&1["type"] == "draft_mcp_revalidation_result" and
             &1["result"] ==
               cond do
                 "timeout" in System.argv() -> "unknown"
                 "forge" in System.argv() or "drift" in System.argv() -> "mismatch"
                 true -> "matched"
               end)
       )

IO.puts("SYNTHETIC_DRAFT_MCP_RESUME_PASSED")
