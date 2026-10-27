defmodule Ipse.MCP.CatalogSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.MCP.Config

  defmodule Model do
    def complete(config, messages, tools, _emit) do
      send(config.test_pid, {:catalog_model_input, messages, tools})
      last_real = messages |> Enum.reject(&Ipse.Session.Reference.reference?/1) |> List.last()

      if last_real["role"] == "tool" do
        {:ok, %{"role" => "assistant", "content" => "Fixture finished"}, %{}}
      else
        calls = [
          {Config.resource_id("notes", "notes://guide"), %{}},
          {Config.prompt_id("notes", "summarize"), %{"topic" => "approval boundaries"}}
        ]

        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" =>
             Enum.with_index(calls, fn {name, args}, index ->
               %{
                 "id" => "catalog-#{index}",
                 "type" => "function",
                 "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
               }
             end)
         }, %{}}
      end
    end
  end

  defmodule DraftModel do
    def complete(config, messages, tools, _) do
      send(config.test_pid, {:draft_mcp_input, messages, tools})
      last = messages |> Enum.reject(&Ipse.Session.Reference.reference?/1) |> List.last()

      cond do
        last["role"] == "tool" ->
          {:ok, %{"role" => "assistant", "content" => "proposal"}, %{}}

        last["content"] == "preload" ->
          {:ok, %{"role" => "assistant", "content" => "ready"}, %{}}

        true ->
          {:ok,
           %{
             "role" => "assistant",
             "content" => "",
             "tool_calls" => [
               %{
                 "id" => "draft-mcp-call",
                 "type" => "function",
                 "function" => %{
                   "name" => Ipse.MCP.Config.resource_id("notes", "notes://guide"),
                   "arguments" => "{}"
                 }
               }
             ]
           }, %{}}
      end
    end
  end

  defmodule DraftWaitModel do
    def complete(config, messages, _, _) do
      last = messages |> Enum.reject(&Ipse.Session.Reference.reference?/1) |> List.last()

      if last["content"] == "preload" do
        {:ok, %{"role" => "assistant", "content" => "ready"}, %{}}
      else
        send(config.test_pid, {:mcp_draft_waiting, self()})
        Process.sleep(:infinity)
      end
    end
  end

  setup do
    root =
      Path.join(System.tmp_dir!(), "ipse-catalog-session-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, dir: Path.join(root, "state")}
  end

  test "draft uses the pre-admitted MCP catalog and never dispatches its calls", ctx do
    pid = session(ctx, provider_module: DraftModel, approval: :allow)
    assert :ok = Ipse.Session.prompt(pid, "preload")
    assert_receive {:draft_mcp_input, _, tools}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    before = File.read!(Path.join(ctx.root, "catalog.log"))
    assert :ok = Ipse.Session.start_draft(pid, "private draft")
    assert_receive {:draft_mcp_input, _, ^tools}, 5_000
    assert_receive {:draft_mcp_input, _, ^tools}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert File.read!(Path.join(ctx.root, "catalog.log")) == before
    assert content_calls(ctx) == []
    {:ok, events} = Ipse.Journal.load(ctx.dir, Ipse.Session.info(pid).id)

    started = Enum.find(events, &(&1["type"] == "draft_started"))
    assert is_map(started["mcp_snapshot"])

    forged_snapshot =
      update_in(started["mcp_snapshot"]["definitions"], fn definitions ->
        List.update_at(definitions, 0, &put_in(&1, ["function", "description"], "forged content"))
      end)

    forged_snapshot =
      put_in(
        forged_snapshot["mcp_snapshot"]["definitions_sha256"],
        Ipse.JSON.digest(forged_snapshot["mcp_snapshot"]["definitions"])
      )

    forged_events = Enum.map(events, fn e -> if e == started, do: forged_snapshot, else: e end)

    assert {:error, :invalid_draft_mcp_catalog} =
             Ipse.Session.Saved.restore(forged_events, Ipse.Session.info(pid).id)

    forged_schema =
      update_in(started["mcp_snapshot"]["definitions"], fn definitions ->
        List.update_at(
          definitions,
          0,
          &put_in(&1, ["function", "parameters"], %{
            "type" => "object",
            "properties" => %{"forged" => %{"type" => "string"}}
          })
        )
      end)

    forged_schema =
      put_in(
        forged_schema["mcp_snapshot"]["definitions_sha256"],
        Ipse.JSON.digest(forged_schema["mcp_snapshot"]["definitions"])
      )

    bad_schema = Enum.map(events, fn e -> if e == started, do: forged_schema, else: e end)

    assert {:error, :invalid_draft_mcp_catalog} =
             Ipse.Session.Saved.restore(bad_schema, Ipse.Session.info(pid).id)

    state = :sys.get_state(pid)

    forged_tools =
      List.update_at(tools, -1, fn definition ->
        put_in(definition, ["function", "description"], "forged description")
      end)

    assert {:error, :reference_catalog_or_history_changed} =
             Ipse.Session.Reference.prepare(
               state.reference,
               state.id,
               state.turn_id,
               Ipse.Session.Context.publishers(state),
               forged_tools,
               state.messages
             )

    assert {:ok, _} = Ipse.Session.DraftMCP.restore(events, Ipse.Session.info(pid).id)
    forged = put_in(started, ["mcp_snapshot", "definitions_sha256"], String.duplicate("0", 64))
    bad = Enum.map(events, fn e -> if e == started, do: forged, else: e end)

    assert {:error, :invalid_draft_mcp_catalog} =
             Ipse.Session.Saved.restore(bad, Ipse.Session.info(pid).id)

    forged = put_in(started, ["mcp_snapshot", "manifests_sha256"], String.duplicate("0", 64))
    bad = Enum.map(events, fn e -> if e == started, do: forged, else: e end)

    assert {:error, :invalid_draft_mcp_catalog} =
             Ipse.Session.Saved.restore(bad, Ipse.Session.info(pid).id)

    assert Enum.any?(
             events,
             &(get_in(&1, ["message", "tool_call_id"]) == "draft-mcp-call" and
                 get_in(&1, ["message", "ipse_tool_outcome", "status"]) == "denied")
           )

    assert :ok = Ipse.Session.cancel_draft(pid)
  end

  test "a first-use draft admits the configured MCP catalog without sending draft input", ctx do
    File.write!(Path.join(ctx.root, "trace-discovery"), "enabled")
    pid = session(ctx, provider_module: DraftModel, approval: :allow)
    assert :ok = Ipse.Session.start_draft(pid, "first-draft-private-canary")
    assert_receive {:draft_mcp_input, _, tools}, 10_000
    assert_receive {:draft_mcp_input, _, ^tools}, 10_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    log = File.read!(Path.join(ctx.root, "catalog.log"))
    refute log =~ "first-draft-private-canary"
    assert content_calls(ctx) == []
    assert :ok = Ipse.Session.cancel_draft(pid)
    id = Ipse.Session.info(pid).id
    assert :ok = Ipse.Session.close_confirmed(pid)
    {:ok, events} = Ipse.Journal.load(ctx.dir, id)
    assert Enum.any?(events, &(&1["type"] == "draft_mcp_setup_intent"))

    assert Enum.any?(
             events,
             &(&1["type"] == "draft_mcp_setup_result" and &1["result"] == "observed")
           )

    assert Enum.any?(events, &(&1["type"] == "draft_mcp_snapshot"))
    setup_index = Enum.find_index(events, &(&1["type"] == "draft_mcp_setup_result"))
    setup_prefix = Enum.take(events, setup_index + 1)

    assert {:ok, %{interrupted: true, snapshot: nil, pending: nil}} =
             Ipse.Session.DraftMCP.restore(setup_prefix, id)

    snapshot_index = Enum.find_index(events, &(&1["type"] == "draft_mcp_snapshot"))

    assert {:ok, %{interrupted: false, snapshot: snapshot}} =
             Ipse.Session.DraftMCP.restore(Enum.take(events, snapshot_index + 1), id)

    assert is_map(snapshot)
    assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
  end

  test "owner loss during first-use draft discovery remains unknown and is not replayed", ctx do
    File.write!(Path.join(ctx.root, "trace-discovery"), "enabled")
    File.write!(Path.join(ctx.root, "hold-discovery"), "hold")
    opts = [provider_module: DraftModel, approval: :allow, scenario: "revalidation_hold"]
    pid = session(ctx, opts)
    id = Ipse.Session.info(pid).id
    assert :ok = Ipse.Session.start_draft(pid, "first-draft-interrupted-canary")

    wait = fn wait, n ->
      cond do
        File.exists?(Path.join(ctx.root, "revalidation-held.pid")) ->
          :ok

        n == 0 ->
          flunk("synthetic MCP server did not reach discovery")

        true ->
          Process.sleep(10)
          wait.(wait, n - 1)
      end
    end

    wait.(wait, 500)
    held_pid = File.read!(Path.join(ctx.root, "revalidation-held.pid"))
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 5_000

    wait_dead = fn wait_dead, n ->
      cond do
        elem(System.cmd("kill", ["-0", held_pid], stderr_to_stdout: true), 1) != 0 ->
          :ok

        n == 0 ->
          flunk("synthetic MCP process survived")

        true ->
          Process.sleep(10)
          wait_dead.(wait_dead, n - 1)
      end
    end

    wait_dead.(wait_dead, 500)
    before = File.read!(Path.join(ctx.root, "catalog.log"))
    refute before =~ "first-draft-interrupted-canary"
    resumed = session(ctx, opts, id)
    assert :sys.get_state(resumed).draft_mcp_interrupted
    refute_receive {:draft_mcp_input, _, _}, 200
    assert File.read!(Path.join(ctx.root, "catalog.log")) == before
    assert :ok = Ipse.Session.cancel_draft(resumed)
    assert :ok = Ipse.Session.close_confirmed(resumed)
    {:ok, events} = Ipse.Journal.load(ctx.dir, id)

    assert Enum.any?(
             events,
             &(&1["type"] == "draft_mcp_setup_result" and &1["result"] == "unknown")
           )

    assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
  end

  test "accepted draft lineage binds a later actual MCP resource call", ctx do
    pid = session(ctx, provider_module: DraftModel, approval: :allow)
    id = Ipse.Session.info(pid).id
    assert :ok = Ipse.Session.prompt(pid, "preload")
    assert_receive {:draft_mcp_input, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert :ok = Ipse.Session.start_draft(pid, "private draft source")
    assert_receive {:draft_mcp_input, _, _}, 5_000
    assert_receive {:draft_mcp_input, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    {:ok, %{id: draft_id, revision: revision}} = Ipse.Session.draft(pid)
    assert :ok = Ipse.Session.replace_draft(pid, draft_id, revision, "accepted request")
    assert :ok = Ipse.Session.close_confirmed(pid)
    {:ok, events} = Ipse.Journal.load(ctx.dir, id)
    {:ok, draft} = Ipse.Session.Draft.restore(events, id)
    {:ok, render} = Ipse.Session.DraftAcceptance.render(draft, Ipse.Usage.id())
    text = "accept " <> render["code"]

    observation = %{
      "version" => 2,
      "event_id" => Ipse.Usage.id(),
      "display_limit" => 16_777_216,
      "input_limit" => 1_048_576,
      "display_sha256" => Ipse.JSON.sha256(render["display"]),
      "text_sha256" => Ipse.JSON.sha256(text)
    }

    {:ok, receipt} = Ipse.Session.DraftAcceptance.receipt(draft, render, text, observation)
    assert :ok = Ipse.Journal.append(ctx.dir, id, Ipse.Session.Draft.accepted(draft, receipt))
    resumed = session(ctx, [provider_module: DraftModel, approval: :allow], id)
    assert :ok = Ipse.Session.consume_draft(resumed, draft_id, revision + 1)
    assert_receive {:draft_mcp_input, input, _}, 5_000
    refute inspect(input) =~ "private draft source"
    assert_receive {:draft_mcp_input, _, _}, 5_000
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 5_000
    assert Enum.map(content_calls(ctx), & &1["event"]) == ["read_resource"]
    assert :ok = Ipse.Session.close_confirmed(resumed)
    {:ok, events} = Ipse.Journal.load(ctx.dir, id)

    link =
      Enum.find(
        events,
        &(&1["type"] == "draft_effect_intent" and &1["call_id"] == "draft-mcp-call")
      )

    assert length(link["possible_source_lineages"]) == 1
    assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
  end

  test "pending MCP draft resumes without rediscovery or automatic dispatch", ctx do
    pid = session(ctx, provider_module: DraftWaitModel, approval: :allow)
    id = Ipse.Session.info(pid).id
    assert :ok = Ipse.Session.prompt(pid, "preload")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert :ok = Ipse.Session.start_draft(pid, "private draft")
    assert_receive {:mcp_draft_waiting, worker}, 5_000
    before = File.read!(Path.join(ctx.root, "catalog.log"))
    monitor = Process.monitor(pid)
    worker_monitor = Process.monitor(worker)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 5_000
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _}, 5_000
    resumed = session(ctx, [provider_module: DraftWaitModel, approval: :allow], id)
    assert :sys.get_state(resumed).config.execution_mode == :draft
    refute_receive {:mcp_draft_waiting, _}, 100
    assert File.read!(Path.join(ctx.root, "catalog.log")) == before
    assert :ok = Ipse.Session.cancel_draft(resumed)
  end

  test "native answer resumes a pending MCP draft with the admitted catalog", ctx do
    driver = Path.join(ctx.root, "pty")

    assert {_, 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 "test/support/operator_cli_pty.rs",
                 "-o",
                 driver
               ],
               stderr_to_stdout: true
             )

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    {output, status} =
      System.cmd(
        driver,
        ["--draft-mcp-resume", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++ [Path.expand("test/support/draft_mcp_resume_pty.exs"), ctx.root],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "SYNTHETIC_DRAFT_MCP_RESUME_PASSED"

    forged_root = Path.join(ctx.root, "correlated-journal-rewrite")
    File.mkdir!(forged_root)

    {forged_output, forged_status} =
      System.cmd(
        driver,
        ["--draft-mcp-resume", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++ [Path.expand("test/support/draft_mcp_resume_pty.exs"), "forge", forged_root],
        stderr_to_stdout: true
      )

    assert forged_status == 0, forged_output
    assert forged_output =~ "SYNTHETIC_DRAFT_MCP_RESUME_PASSED"

    drift_root = Path.join(ctx.root, "server-catalog-drift")
    File.mkdir!(drift_root)

    {drift_output, drift_status} =
      System.cmd(
        driver,
        ["--draft-mcp-resume", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++ [Path.expand("test/support/draft_mcp_resume_pty.exs"), "drift", drift_root],
        stderr_to_stdout: true
      )

    assert drift_status == 0, drift_output
    assert drift_output =~ "SYNTHETIC_DRAFT_MCP_RESUME_PASSED"

    interrupted_root = Path.join(ctx.root, "revalidation-owner-death")
    File.mkdir!(interrupted_root)

    {interrupted_output, interrupted_status} =
      System.cmd(
        driver,
        ["--draft-mcp-resume", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [Path.expand("test/support/draft_mcp_resume_pty.exs"), "interrupt", interrupted_root],
        stderr_to_stdout: true
      )

    assert interrupted_status == 0, interrupted_output
    assert interrupted_output =~ "SYNTHETIC_DRAFT_MCP_INTERRUPT_PASSED"

    cancelled_root = Path.join(ctx.root, "revalidation-active-cancel")
    File.mkdir!(cancelled_root)

    {cancelled_output, cancelled_status} =
      System.cmd(
        driver,
        ["--draft-mcp-resume", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [Path.expand("test/support/draft_mcp_resume_pty.exs"), "cancel", cancelled_root],
        stderr_to_stdout: true
      )

    assert cancelled_status == 0, cancelled_output
    assert cancelled_output =~ "SYNTHETIC_DRAFT_MCP_INTERRUPT_PASSED"

    timeout_root = Path.join(ctx.root, "revalidation-timeout")
    File.mkdir!(timeout_root)

    {timeout_output, timeout_status} =
      System.cmd(
        driver,
        ["--draft-mcp-resume", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++ [Path.expand("test/support/draft_mcp_resume_pty.exs"), "timeout", timeout_root],
        stderr_to_stdout: true
      )

    assert timeout_status == 0, timeout_output
    assert timeout_output =~ "SYNTHETIC_DRAFT_MCP_RESUME_PASSED"

    first_root = Path.join(ctx.root, "first-use-question-restart")
    File.mkdir!(first_root)

    {first_output, first_status} =
      System.cmd(
        driver,
        ["--draft-mcp-resume", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++ [Path.expand("test/support/draft_mcp_resume_pty.exs"), "first", first_root],
        stderr_to_stdout: true
      )

    assert first_status == 0, first_output
    assert first_output =~ "SYNTHETIC_DRAFT_MCP_RESUME_PASSED"
  end

  test "resource and prompt content need separate exact approvals and stay tool data", ctx do
    pid = session(ctx)
    :ok = Ipse.Session.prompt(pid, "inspect catalog")
    assert_receive {:catalog_model_input, _, definitions}, 5_000

    assert length(
             Enum.filter(
               definitions,
               &String.starts_with?(get_in(&1, ["function", "name"]), "mcp__")
             )
           ) == 2

    resource = Config.resource_id("notes", "notes://guide")
    prompt = Config.prompt_id("notes", "summarize")

    assert_receive {:ipse, ^pid,
                    {:mcp_approval_context,
                     %{kind: "resource", source: "notes://guide", tool_id: ^resource}}},
                   5_000

    assert_receive {:ipse, ^pid, {:approval, ref, ^resource, %{}}}, 5_000
    assert content_calls(ctx) == []
    assert {:error, :no_pending_approval} = Ipse.Session.approve(pid, make_ref(), true)
    assert content_calls(ctx) == []
    :ok = Ipse.Session.approve(pid, ref, true)
    args = %{"topic" => "approval boundaries"}
    assert_receive {:ipse, ^pid, {:approval, ref, ^prompt, ^args}}, 5_000
    assert Enum.map(content_calls(ctx), & &1["event"]) == ["read_resource"]
    {:ok, before} = Ipse.Journal.load(ctx.dir, Ipse.Session.info(pid).id)
    assert Enum.any?(before, &(&1["type"] == "tool_started" and &1["name"] == resource))
    :ok = Ipse.Session.approve(pid, ref, true)
    assert_receive {:catalog_model_input, messages, _}, 5_000
    assert Ipse.Session.Reference.reference?(List.last(messages))
    assert List.last(messages)["role"] == "user"
    assert Ipse.Session.Reference.safe_tail?(messages)

    assert messages
           |> Enum.reject(&Ipse.Session.Reference.reference?/1)
           |> List.last()
           |> Map.fetch!("role") == "tool"

    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    results = Enum.filter(messages, &(&1["role"] == "tool"))
    assert length(results) == 2
    assert Enum.at(results, 0)["content"] =~ "A local fixture note."
    assert Enum.at(results, 1)["content"] =~ "[user]\nSummarize: approval boundaries"

    refute Enum.any?(
             messages,
             &(&1["role"] == "user" and String.contains?(&1["content"], "Summarize:"))
           )

    {:ok, events} = Ipse.Journal.load(ctx.dir, Ipse.Session.info(pid).id)
    intents = Enum.filter(events, &(&1["type"] == "tool_started"))
    assert Enum.map(intents, &get_in(&1, ["mcp", "kind"])) == ["resource", "prompt"]
    assert Enum.map(intents, &get_in(&1, ["mcp", "source"])) == ["notes://guide", "summarize"]
    assert Enum.all?(intents, &(&1["approval"] == "approved"))
  end

  test "headless denial reads no content; completed resume replays neither request", ctx do
    denied = session(ctx, approval: :deny)
    :ok = Ipse.Session.prompt(denied, "inspect catalog")
    assert_receive {:ipse, ^denied, {:done, :ok}}, 5_000
    assert content_calls(ctx) == []
    :ok = Ipse.Session.close(denied)
    allowed = session(ctx, approval: :allow)
    :ok = Ipse.Session.prompt(allowed, "inspect catalog")
    assert_receive {:ipse, ^allowed, {:done, :ok}}, 5_000
    id = Ipse.Session.info(allowed).id
    before = content_calls(ctx)
    assert length(before) == 2
    :ok = Ipse.Session.close(allowed)
    resumed = session(ctx, [approval: :allow], id)
    assert Ipse.Session.info(resumed).phase == :idle
    assert content_calls(ctx) == before
  end

  test "lost resource response stops the prompt batch and unknown resume does not retry", ctx do
    pid = session(ctx, scenario: "resource_disconnect", approval: :allow)
    :ok = Ipse.Session.prompt(pid, "inspect catalog")
    resource = Config.resource_id("notes", "notes://guide")

    # Catalog discovery includes a fresh VM, multiple RPCs and transport cleanup.
    # Wait for its explicit completion before measuring resource-call progress.
    assert_receive {:catalog_model_input, _, _}, 15_000
    assert_receive {:ipse, ^pid, {:tool, ^resource, %{}}}, 5_000
    # The configured 5s call lifetime and bounded cleanup remain separate.
    assert_receive {:ipse, ^pid, {:done, :error}}, 10_000
    assert Enum.map(content_calls(ctx), & &1["event"]) == ["read_resource"]
    id = Ipse.Session.info(pid).id
    {:ok, events} = Ipse.Journal.load(ctx.dir, id)

    outcomes =
      for e <- events,
          get_in(e, ["message", "role"]) == "tool",
          do: get_in(e, ["message", "ipse_tool_outcome", "status"])

    assert outcomes == ["unknown", "not_started"]
    :ok = Ipse.Session.close(pid)
    resumed = session(ctx, [scenario: "resource_disconnect", approval: :allow], id)
    assert Ipse.Session.info(resumed).phase == :idle
    assert length(content_calls(ctx)) == 1
  end

  defp content_calls(ctx) do
    case File.read(Path.join(ctx.root, "catalog.log")) do
      {:ok, bytes} ->
        bytes
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)
        |> Enum.filter(&(&1["event"] in ["read_resource", "get_prompt"]))

      _ ->
        []
    end
  end

  defp session(ctx, opts \\ [], id \\ nil) do
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
            Path.expand("../../support/mcp_catalog_server.exs", __DIR__),
            Keyword.get(opts, :scenario, "normal")
          ],
          "resources" => ["notes://guide"],
          "prompts" => ["summarize"],
          "env" => %{"PATH" => Path.join(to_string(:code.root_dir()), "bin") <> ":/usr/bin:/bin"},
          "timeout_ms" => 5_000
        }
      ]
    }

    path = Path.join(ctx.root, "mcp.json")
    File.write!(path, Jason.encode!(document))
    {:ok, servers} = Config.load(path)

    config = %{
      provider: :demo,
      model: "catalog-fixture",
      provider_module: Keyword.get(opts, :provider_module, Model),
      test_pid: self(),
      home: Path.join(ctx.root, "home"),
      mcp_servers: servers,
      approval: Keyword.get(opts, :approval, :ask)
    }

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Ipse.Session,
         config: config, cwd: ctx.root, state_dir: ctx.dir, id: id, subscriber: self()}
      )

    on_exit(fn -> if Process.alive?(pid), do: Ipse.Session.close(pid) end)
    pid
  end
end
