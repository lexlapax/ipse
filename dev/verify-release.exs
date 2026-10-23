# Run from an extracted release: ./bin/ipse eval 'Code.require_file("verify-release.exs")'
Application.ensure_all_started(:ipse)

defmodule Ipse.BundledQuestionFixture do
  def complete(_config, messages, _tools, _emit) do
    if Enum.any?(messages, &(&1["role"] == "tool" and &1["tool_call_id"] == "bundle-question")) do
      {:ok, %{"role" => "assistant", "content" => "Explicit answer recorded"}, %{}}
    else
      args = %{
        "questions" => [
          %{
            "id" => "choice",
            "prompt" => "Select explicitly",
            "kind" => "single",
            "options" => [%{"id" => "one", "label" => "One"}, %{"id" => "two", "label" => "Two"}],
            "recommended" => "one"
          }
        ]
      }

      {:ok,
       %{
         "role" => "assistant",
         "content" => "",
         "tool_calls" => [
           %{
             "id" => "bundle-question",
             "function" => %{"name" => "ask_operator", "arguments" => Jason.encode!(args)}
           }
         ]
       }, %{}}
    end
  end
end

release_root = File.cwd!() |> Path.expand()
runtime_root = :code.root_dir() |> List.to_string() |> Path.expand()
app_root = Application.app_dir(:ipse) |> Path.expand()
true = runtime_root == release_root
true = String.starts_with?(app_root, release_root <> "/lib/")
true = File.regular?(Path.join(app_root, "priv/ipse-runner"))
true = File.regular?(Path.join(release_root, "SECURITY.md"))
System.delete_env("IPSE_RUNNER_PATH")

scratch =
  Path.join(
    System.tmp_dir!(),
    "ipse-release-check-#{Base.encode16(:crypto.strong_rand_bytes(8))}"
  )

File.mkdir_p!(scratch)

await_lock = fn await_lock, path, attempts ->
  case Ipse.Runner.lock(path) do
    {:ok, lock} ->
      {:ok, lock}

    {:error, _} when attempts > 0 ->
      Process.sleep(20)
      await_lock.(await_lock, path, attempts - 1)

    error ->
      error
  end
end

try do
  {:ok, release_environment} =
    Ipse.Runner.run(
      ~s(test -z "${RELEASE_ROOT:-}" && test -z "${ROOTDIR:-}" && test -z "${BINDIR:-}" && printf release-env-clean),
      scratch
    )

  0 = release_environment.exit_code
  "release-env-clean" = release_environment.output

  {:ok, selected_erl} = Ipse.Runner.run("command -v erl || true", scratch)
  false = String.contains?(selected_erl.output, release_root)
  IO.puts("Bundled trusted shell excludes its launcher environment and bundled ERTS PATH.")

  config_home = Path.join(scratch, "config-home")
  File.mkdir_p!(config_home)
  File.mkdir_p!(Path.join(scratch, ".git"))

  File.write!(
    Path.join(config_home, "config.json"),
    Jason.encode!(%{
      version: 1,
      settings: %{subagents: true},
      profiles: %{
        strong: %{provider: "chatgpt", model: "gpt-6.1-sol", reasoning_effort: "high"},
        local: %{provider: "ollama", model: "fixture-local"}
      },
      roles: %{main: "strong", routine: "local"}
    })
  )

  {:ok, effective} = Ipse.Config.resolve(scratch, config_home, [], %{})
  "strong" = effective.execution.id
  "high" = Ipse.Config.Profiles.runtime(effective).reasoning_effort

  parent =
    Map.merge(
      %{provider: :chatgpt, model: "gpt-6.1-sol", api_key: "synthetic-parent-key"},
      Ipse.Config.Profiles.runtime(effective)
    )

  {:ok, local_child} = Ipse.Config.Profiles.child_config(parent, %{}, %{})
  :ollama = local_child.provider
  false = Map.has_key?(local_child, :api_key)

  %{"effort" => "high"} =
    Ipse.Provider.OpenAI.request_body(
      %{provider: :chatgpt, model: "gpt-6.1-sol", reasoning_effort: "high"},
      [],
      []
    )["reasoning"]

  IO.puts(
    "Bundled scoped configuration and model-profile verification passed without authentication/inference."
  )

  research_dir = Path.join(scratch, "research-state")

  {:ok, research_id} =
    Ipse.Journal.create(research_dir, %{
      "provider" => "demo",
      "model" => "scripted",
      "cwd" => scratch
    })

  :ok =
    Ipse.Journal.append(research_dir, research_id, %{
      "type" => "tool_started",
      "name" => "mcp__fixture__fetch",
      "call_id" => "bundled-fetch"
    })

  :ok =
    Ipse.Journal.append(research_dir, research_id, %{
      "type" => "message",
      "message" => %{
        "role" => "tool",
        "tool_call_id" => "bundled-fetch",
        "content" => "https://example.invalid/source Literal bundled evidence.",
        "ipse_tool_outcome" => %{"status" => "result_recorded", "approval" => "approved"}
      }
    })

  {:research_record, event, _} =
    Ipse.Tools.Research.call(research_dir, research_id, "research_source", %{
      "tool_call_id" => "bundled-fetch",
      "url" => "https://example.invalid/source",
      "excerpt" => "Literal bundled evidence."
    })

  :ok = Ipse.Journal.append(research_dir, research_id, event)
  {:ok, %{"sources" => [source]}} = Ipse.Tools.Research.load(research_dir, research_id)
  "Literal bundled evidence." = source["excerpt"]

  {:error, _} =
    Ipse.Tools.Research.call(research_dir, research_id, "research_claim", %{
      "statement" => "Unsupported",
      "kind" => "supported",
      "source_ids" => []
    })

  IO.puts("Bundled durable research ledger verification passed without network retrieval.")

  {:ok, diagnostic} = Ipse.Session.Saved.inspect_saved(research_dir, research_id)
  "effective_transcript_without_system" = diagnostic["context"]["scope"]

  {:ok, handoff} =
    Ipse.Session.Saved.export_handoff(
      research_dir,
      research_id,
      "Review recorded evidence before continuing."
    )

  true = handoff["requires_effect_review"]
  false = Map.has_key?(handoff, "messages")
  IO.puts("Bundled diagnostics and explicit handoff export passed without inference/replay.")

  artifact_bytes = Jason.encode!(handoff, pretty: true) <> "\n"
  {:ok, imported} = Ipse.Session.Saved.prepare_handoff(artifact_bytes)
  handoff_dir = Path.join(scratch, "handoff-state")

  handoff_config = %{
    provider: :demo,
    model: "scripted",
    approval: :deny,
    home: Path.join(scratch, "handoff-home"),
    sandbox: :off
  }

  handoff_opts = [
    config: handoff_config,
    cwd: scratch,
    state_dir: handoff_dir,
    subscriber: self()
  ]

  {:ok, fresh} =
    DynamicSupervisor.start_child(
      Ipse.Sessions,
      {Ipse.Session, handoff_opts ++ [handoff: artifact_bytes]}
    )

  %{phase: :idle, id: fresh_id} = Ipse.Session.info(fresh)
  :ok = Ipse.Session.close(fresh)
  path = Path.join(handoff_dir, fresh_id <> ".jsonl")
  saved = File.read!(path)
  {:ok, events} = Ipse.Journal.load(handoff_dir, fresh_id)
  [^imported] = Enum.filter(events, &(&1["type"] == "handoff_imported"))
  {:ok, [projection]} = Ipse.Session.restore_context(events)
  true = projection == imported["message"]
  false = Enum.any?(events, &(&1["type"] in ["request_measured", "tool_started"]))

  {:ok, resumed} =
    DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, handoff_opts ++ [id: fresh_id]})

  %{phase: :idle} = Ipse.Session.info(resumed)
  :ok = Ipse.Session.close(resumed)
  ^saved = File.read!(path)

  {:error, :invalid_handoff} =
    Ipse.Session.Saved.prepare_handoff(Jason.encode!(Map.put(handoff, "approval", "allow")))

  IO.puts(
    "Bundled fresh handoff import and unchanged idle resume passed without inference/replay."
  )

  Code.require_file(Path.join(Application.app_dir(:ipse, "priv"), "demo/extensions.exs"))
  :ok = Ipse.ExtensionDemo.run()

  Code.require_file(Path.join(Application.app_dir(:ipse, "priv"), "demo/usage.exs"))
  :ok = Ipse.UsageDemo.run_costs()

  Code.require_file(Path.join(Application.app_dir(:ipse, "priv"), "demo/usage.exs"))
  :ok = Ipse.UsageDemo.run_budget()

  Code.require_file(Path.join(Application.app_dir(:ipse, "priv"), "demo/self-development.exs"))
  Ipse.SelfDevelopmentDemo.run()

  {:ok, question_session} =
    DynamicSupervisor.start_child(
      Ipse.Sessions,
      {Ipse.Session,
       cwd: scratch,
       state_dir: Path.join(scratch, "question-state"),
       subscriber: self(),
       config: %{
         provider: :demo,
         model: "bundled-question",
         provider_module: Ipse.BundledQuestionFixture,
         home: Path.join(scratch, "question-home"),
         operator_questions: true,
         approval: :deny,
         max_steps: 3
       }}
    )

  try do
    :ok = Ipse.Session.prompt(question_session, "Ask for an explicit choice.")

    receive do
      {:ipse, ^question_session, {:question, id, _args}} ->
        true = :sys.get_state(question_session).task == nil
        {:error, :invalid_answer} = Ipse.Session.answer(question_session, id, %{})
        :ok = Ipse.Session.answer(question_session, id, %{"choice" => "two"})
    after
      10_000 -> raise("bundled question was not presented")
    end

    receive do
      {:ipse, ^question_session, {:done, :ok}} -> :ok
    after
      10_000 -> raise("bundled explicit answer did not complete")
    end

    IO.puts("Bundled structured operator question verification passed.")
  after
    :ok = Ipse.Session.close(question_session)
  end

  compaction_history =
    [%{"role" => "user", "content" => "Inspect synthetic evidence without repeating effects."}] ++
      Enum.flat_map(1..4, fn n ->
        [
          %{
            "role" => "assistant",
            "content" => "",
            "provider_data" => %{"opaque" => "native-#{n}"},
            "tool_calls" => [
              %{"id" => "read-#{n}", "function" => %{"name" => "read", "arguments" => "{}"}}
            ]
          },
          %{
            "role" => "tool",
            "tool_call_id" => "read-#{n}",
            "content" => String.duplicate("synthetic evidence ", 500),
            "ipse_tool_outcome" => %{"status" => "result_recorded", "approval" => "not_required"}
          }
        ]
      end)

  {:tool_results, projected, checkpoint} =
    Ipse.Session.Context.prepare_compaction(
      compaction_history,
      %{context_bytes: 100_000, compact_threshold_bytes: 28_000},
      %{"role" => "system", "content" => "rules"}
    )

  {:ok, ^projected} = Ipse.Session.Context.restore_tool_results(compaction_history, checkpoint)
  true = Enum.take(projected, -4) == Enum.take(compaction_history, -4)
  IO.puts("Bundled long-turn output checkpoint verification passed.")

  {:ok, result} =
    Ipse.Runner.run("(sleep 1; printf survived > timeout-marker) & printf ready; wait", scratch,
      timeout_ms: 200
    )

  true = result.timed_out
  true = result.output == "ready"
  Process.sleep(1_100)
  false = File.exists?(Path.join(scratch, "timeout-marker"))

  parent = self()

  owner =
    spawn(fn ->
      Ipse.Runner.run(
        "(sleep 1; printf survived > owner-marker) & printf ready; wait",
        scratch,
        emit: fn event -> send(parent, event) end
      )
    end)

  receive do
    {:tool_output, "ready"} -> :ok
  after
    5_000 -> raise "bundled helper did not start"
  end

  Process.exit(owner, :kill)
  Process.sleep(1_100)
  false = File.exists?(Path.join(scratch, "owner-marker"))

  path = Path.join(scratch, "session.lock")
  {:ok, lock} = Ipse.Runner.lock(path)
  inode = File.stat!(path).inode
  true = Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
  {:error, _} = Ipse.Runner.lock(path)
  :ok = Ipse.Runner.unlock(lock)
  {:ok, next} = await_lock.(await_lock, path, 100)
  true = File.stat!(path).inode == inode
  :ok = Ipse.Runner.unlock(next)

  lock_owner =
    spawn(fn ->
      {:ok, _} = await_lock.(await_lock, path, 100)
      send(parent, :locked)
      Process.sleep(:infinity)
    end)

  receive do
    :locked -> :ok
  after
    5_000 -> raise "bundled lock owner did not start"
  end

  {:error, _} = Ipse.Runner.lock(path)
  Process.exit(lock_owner, :kill)
  {:ok, final} = await_lock.(await_lock, path, 100)
  true = File.stat!(path).inode == inode
  :ok = Ipse.Runner.unlock(final)

  # Both peers use this extracted runtime; no system Elixir/Mix is involved.
  mcp_workspace = Path.join(scratch, "mcp workspace")
  File.mkdir!(mcp_workspace)
  server_script = Path.join(app_root, "priv/demo/mcp-notes.exs")
  config_path = Path.join(scratch, "mcp.json")

  File.write!(
    config_path,
    Jason.encode!(%{
      "servers" => [
        %{
          "id" => "bundled",
          "command" => Path.join(release_root, "bin/ipse"),
          "args" => ["eval", "Code.require_file(#{inspect(server_script)})"],
          "tools" => ["write_note"],
          "resources" => ["notes://guide"],
          "prompts" => ["summarize"],
          "env" => %{"ELIXIR_ERL_OPTIONS" => "+S 2:2"},
          "timeout_ms" => 15_000
        }
      ]
    })
  )

  {:ok, [server]} = Ipse.MCP.Config.load(config_path)
  {:ok, descriptors} = Ipse.MCP.discover_server(server, mcp_workspace)
  3 = length(descriptors)
  descriptor = Enum.find(descriptors, &(&1.name == "write_note"))

  {:ok, "Wrote mcp-note.txt."} =
    Ipse.MCP.call(descriptor, %{"content" => "bundled MCP verified"}, mcp_workspace)

  "bundled MCP verified" = File.read!(Path.join(mcp_workspace, "mcp-note.txt"))
  IO.puts("Bundled local MCP SDK round trip passed without a development toolchain.")

  resource = Enum.find(descriptors, &(Map.get(&1, :kind) == :resource))
  prompt = Enum.find(descriptors, &(Map.get(&1, :kind) == :prompt))
  {:ok, resource_text} = Ipse.MCP.call(resource, %{}, mcp_workspace)
  true = String.contains?(resource_text, "Example notes are plain UTF-8 text.")
  {:ok, prompt_text} = Ipse.MCP.call(prompt, %{"topic" => "bundled notes"}, mcp_workspace)
  true = String.contains?(prompt_text, "Summarize this topic: bundled notes")
  IO.puts("Bundled MCP resource and prompt round trips passed.")

  Code.require_file(Path.join(app_root, "priv/demo/mcp-http.exs"))
  :ok = Ipse.MCPHTTPDemo.run()
  IO.puts("Bundled Streamable HTTP MCP round trip passed.")

  Code.require_file(Path.join(app_root, "priv/demo/subagents.exs"))
  :ok = Ipse.DelegationDemo.run_serial()
  IO.puts("Bundled local delegation approvals and child journal verification passed.")
  Code.require_file(Path.join(app_root, "priv/demo/subagents.exs"))
  :ok = Ipse.DelegationDemo.run_parallel()
  IO.puts("Bundled parallel local delegation verification passed.")

  if :os.type() == {:unix, :darwin} do
    workspace = Path.join(scratch, "native workspace")
    File.mkdir!(workspace)
    secret = Path.join(scratch, "outside-fixture-key")
    File.write!(secret, "fixture-private-value")
    quote_shell = fn text -> "'" <> String.replace(text, "'", "'\\''") <> "'" end

    {:ok, native} =
      Ipse.Runner.run(
        "set -e; printf allowed > native-marker; if cat #{quote_shell.(secret)}; then exit 11; fi; if printf changed > #{quote_shell.(secret)}; then exit 12; fi; printf confined",
        workspace,
        sandbox: :native
      )

    0 = native.exit_code
    false = native.timed_out
    true = String.contains?(native.output, "confined")
    false = String.contains?(native.output, "fixture-private-value")
    "allowed" = File.read!(Path.join(workspace, "native-marker"))
    "fixture-private-value" = File.read!(secret)

    {:ok, timed} =
      Ipse.Runner.run(
        "(printf native-ready; sleep 1.7; printf survived > native-timeout-marker) & wait",
        workspace,
        sandbox: :native,
        timeout_ms: 1_000
      )

    true = timed.timed_out
    "native-ready" = timed.output
    Process.sleep(1_850)
    false = File.exists?(Path.join(workspace, "native-timeout-marker"))

    IO.puts(
      "Bundled macOS native workspace writes, outside-file denial, and ordinary timeout cleanup passed."
    )
  end

  IO.puts("Bundled runtime/helper, timeout cleanup, owner-death cleanup, and locks passed.")
after
  File.rm_rf!(scratch)
end
