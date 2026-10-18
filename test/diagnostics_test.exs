defmodule Ipse.DiagnosticsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias Ipse.{Compaction, Diagnostics, Handoff, Journal, Session}

  defmodule Model do
    def complete(config, _messages, _tools, _emit) do
      send(config.test_pid, {:model_worker, self()})

      receive do
        :finish -> {:ok, %{"role" => "assistant", "content" => "finished"}, %{}}
      end
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-diagnostics-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    dir = Path.join(root, "sessions")
    {:ok, id} = Journal.create(dir, %{"provider" => "demo", "model" => "fixture", "cwd" => root})
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, dir: dir, id: id}
  end

  test "encoded categories add exactly and never return content, native secrets or arbitrary keys" do
    messages = [
      %{"role" => "user", "content" => "private-user 雪\n\""},
      %{
        "role" => "assistant",
        "content" => "private-answer",
        "provider_data" => %{"opaque" => "private-native"},
        "tool_calls" => [
          %{"id" => "1", "function" => %{"name" => "read", "arguments" => "private-args"}}
        ]
      },
      %{
        "role" => "tool",
        "tool_call_id" => "1",
        "content" => "private-result",
        "ipse_tool_outcome" => %{"status" => "result_recorded", "approval" => "not_required"}
      },
      %{
        "role" => "assistant",
        "content" => "private-checkpoint",
        "ipse_checkpoint" => %{"user_intents" => ["private-intent"]},
        "private-field" => "private-other"
      }
    ]

    system = %{"role" => "system", "content" => "private-instruction"}

    stats =
      Diagnostics.context(
        messages,
        %{context_bytes: 10000, compact_threshold_bytes: 9000, api_key: "private-key"},
        system
      )

    assert stats["encoded_bytes"] == byte_size(Jason.encode!([system | messages]))
    assert Enum.sum(Map.values(stats["categories"])) == stats["encoded_bytes"]
    assert stats["categories"]["native_continuation"] > 0
    assert stats["categories"]["recent_tool_results"] > 0
    assert stats["target_bytes"] == 8000
    refute Jason.encode!(stats) =~ "private-"
    assert Diagnostics.context([], %{})["encoded_bytes"] == 2
    reference = %{"role" => "user", "content" => "private-reference-context"}
    headers = [system, reference]
    referenced = Diagnostics.context(messages, %{context_bytes: 10_000}, headers)
    assert referenced["encoded_bytes"] == byte_size(Jason.encode!(headers ++ messages))
    assert referenced["categories"]["reference_context"] > 0
    refute Jason.encode!(referenced) =~ "private-reference-context"
  end

  test "P18-shaped long turn cannot reduce native continuation; diagnosis explains and history stays exact" do
    messages = [
      %{"role" => "user", "content" => "Preserve original intent"},
      %{
        "role" => "assistant",
        "content" => "",
        "provider_data" => %{"opaque" => String.duplicate("N", 20000)}
      }
    ]

    before = Jason.encode!(messages)

    assert {:error, _} =
             Compaction.prepare(messages, %{context_bytes: 8192}, %{
               "role" => "system",
               "content" => "rules"
             })

    stats = Diagnostics.context(messages, %{context_bytes: 8192})
    assert stats["categories"]["native_continuation"] > stats["limit_bytes"]
    assert Jason.encode!(messages) == before
  end

  test "saved inspection and explicit handoff exclude payloads, preserve unknowns and never repair a tail",
       c do
    append(c, %{"role" => "user", "content" => "synthetic-secret-user"})

    append(c, %{
      "role" => "assistant",
      "content" => "",
      "tool_calls" => [
        %{
          "id" => "pending-1",
          "function" => %{"name" => "write", "arguments" => "synthetic-secret-arguments"}
        }
      ]
    })

    path = Path.join(c.dir, c.id <> ".jsonl")
    File.write!(path, "{\"partial\":", [:append])
    before = File.read!(path)
    assert {:ok, result} = Diagnostics.saved(c.dir, c.id)
    assert result["unknown_tool_count"] == 1
    assert result["context"]["scope"] == "effective_transcript_without_system"
    assert result["limit_source"] == "default_not_recorded"
    refute Jason.encode!(result) =~ "synthetic-secret"

    assert {:ok, handoff} =
             Handoff.export(c.dir, c.id, "Inspect the pending write before continuing.")

    assert handoff["requires_effect_review"]
    assert handoff["unknown_call_ids"] == ["pending-1"]
    refute Jason.encode!(handoff) =~ "synthetic-secret"
    assert handoff["source_events_sha256"] =~ ~r/\A[0-9a-f]{64}\z/

    output =
      capture_io(fn ->
        assert Ipse.CLI.run([
                 "handoff",
                 "--resume",
                 c.id,
                 "--state-dir",
                 c.dir,
                 "--note",
                 "Inspect the pending write before continuing."
               ]) == 0
      end)

    assert Jason.decode!(output) == handoff
    assert File.read!(path) == before
    assert {:error, _} = Handoff.export(c.dir, c.id, nil)
    assert {:error, _} = Handoff.export(c.dir, c.id, String.duplicate("雪", 3000))
    assert {:error, _} = Handoff.export(c.dir, c.id, String.duplicate("\n", 8192))
  end

  test "damaged checkpoints refuse both local exports", c do
    :ok =
      Journal.append(c.dir, c.id, %{
        "type" => "context_compacted",
        "version" => 1,
        "covered_messages" => 1,
        "checkpoint" => %{},
        "prefix_sha256" => "wrong"
      })

    assert {:error, _} = Diagnostics.saved(c.dir, c.id)
    assert {:error, _} = Handoff.export(c.dir, c.id, "Continue")
  end

  test "a live compaction refusal journals content-free diagnosis without inference or replay",
       c do
    append(c, %{"role" => "user", "content" => "Keep this intent."})

    append(c, %{
      "role" => "assistant",
      "content" => "",
      "provider_data" => %{"opaque" => String.duplicate("synthetic-private-native", 1000)}
    })

    config = %{
      provider: :demo,
      model: "fixture",
      provider_module: Model,
      test_pid: self(),
      home: Path.join(c.root, "home"),
      approval: :deny,
      context_bytes: 8192
    }

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: c.root, state_dir: c.dir, id: c.id, subscriber: self()}
      )

    :ok = Session.prompt(pid, "Continue")
    assert_receive {:ipse, ^pid, {:done, :error}}, 3000
    refute_receive {:model_worker, _}, 50
    {:ok, events} = Journal.load(c.dir, c.id)
    refusal = Enum.find(events, &(&1["type"] == "compaction_failed"))
    assert refusal["diagnostics"]["categories"]["native_continuation"] > 8192
    refute Jason.encode!(refusal) =~ "synthetic-private-native"
    :ok = Session.close(pid)
  end

  test "forged measurement payloads cannot escape through diagnostics", c do
    :ok =
      Journal.append(c.dir, c.id, %{
        "type" => "request_measured",
        "kind" => "model",
        "outcome" => "completed",
        "duration_ms" => "synthetic-secret"
      })

    assert {:ok, result} = Diagnostics.saved(c.dir, c.id)
    assert result["request_measurements"] == []
    refute Jason.encode!(result) =~ "synthetic-secret"
  end

  test "live snapshot and request duration require no additional inference; idle resume is unchanged",
       c do
    config = %{
      provider: :demo,
      model: "fixture",
      provider_module: Model,
      test_pid: self(),
      home: Path.join(c.root, "home"),
      approval: :deny
    }

    opts = [config: config, cwd: c.root, state_dir: c.dir, id: c.id, subscriber: self()]
    {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})
    :ok = Session.prompt(pid, "synthetic-secret-task")
    assert_receive {:model_worker, worker}, 3000
    snapshot = Session.diagnostics(pid)
    assert snapshot["phase"] == "model"
    assert snapshot["active_worker"]
    refute Jason.encode!(snapshot) =~ "synthetic-secret"
    send(worker, :finish)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    :ok = Session.close(pid)
    {:ok, saved} = Diagnostics.saved(c.dir, c.id)

    assert [%{"kind" => "model", "outcome" => "completed", "duration_ms" => ms}] =
             saved["request_measurements"]

    assert is_integer(ms) and ms >= 0
    path = Path.join(c.dir, c.id <> ".jsonl")
    before = File.read!(path)
    {:ok, resumed} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})
    assert Session.diagnostics(resumed)["phase"] == "idle"
    refute_receive {:model_worker, _}, 50
    assert File.read!(path) == before
    :ok = Session.close(resumed)
  end

  test "cancelled provider work has a distinct bounded measurement", c do
    config = %{
      provider: :demo,
      model: "fixture",
      provider_module: Model,
      test_pid: self(),
      home: Path.join(c.root, "home"),
      approval: :deny
    }

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: c.root, state_dir: c.dir, id: c.id, subscriber: self()}
      )

    :ok = Session.prompt(pid, "task")
    assert_receive {:model_worker, worker}, 3000
    :ok = Session.cancel(pid)
    refute Process.alive?(worker)
    :ok = Session.close(pid)
    {:ok, result} = Diagnostics.saved(c.dir, c.id)
    assert [%{"outcome" => "cancelled"}] = result["request_measurements"]
  end

  defp append(c, message),
    do: Journal.append(c.dir, c.id, %{"type" => "message", "message" => message})
end
