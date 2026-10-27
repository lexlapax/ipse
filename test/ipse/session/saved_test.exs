defmodule Ipse.HandoffTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Saved
  alias Ipse.Journal
  alias Ipse.Session

  defmodule Model do
    def complete(config, messages, _tools, _emit) do
      send(config.test_pid, {:handoff_model, config, messages})
      {:ok, %{"role" => "assistant", "content" => "fixture final"}, %{}}
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-handoff-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    config = %{
      provider: :ollama,
      model: "current-fixture-model",
      provider_module: Model,
      test_pid: self(),
      approval: :deny,
      home: Path.join(root, "home"),
      context_bytes: 400_000,
      sandbox: :off
    }

    %{root: root, dir: Path.join(root, "sessions"), config: config}
  end

  defp artifact do
    %{
      "version" => 1,
      "source_session_id" => String.duplicate("a", 32),
      "source_events_sha256" => String.duplicate("b", 64),
      "note" => "  Preserve this exact note.\nDo not assume the old write completed.\n ",
      "requires_effect_review" => true,
      "unknown_tool_count" => 1,
      "unknown_call_ids" => ["old-call:1"],
      "unknown_ids_omitted" => 0
    }
  end

  test "closed schema rejects unknown fields, duplicate keys, malformed JSON and wrong types" do
    bytes = Jason.encode!(artifact())
    assert {:ok, _} = Saved.prepare_handoff(bytes)

    for bad <- [
          "",
          "[]",
          "null",
          bytes <> bytes,
          bytes <> " garbage",
          String.replace(bytes, "\"version\":1", "\"version\":1,\"version\":1"),
          <<255>>,
          "{\"version\":1}"
        ] do
      assert {:error, :invalid_handoff} = Saved.prepare_handoff(bad)
    end

    for key <-
          ~w(provider model permission credentials tool_calls messages raw_conversation extra) do
      assert {:error, :invalid_handoff} =
               artifact()
               |> Map.put(key, "forbidden")
               |> Jason.encode!()
               |> Saved.prepare_handoff()
    end

    for {key, value} <- [
          {"version", 2},
          {"version", "1"},
          {"requires_effect_review", false},
          {"note", nil},
          {"note", "   "},
          {"unknown_call_ids", "call"},
          {"unknown_tool_count", "1"},
          {"unknown_ids_omitted", nil}
        ] do
      assert {:error, :invalid_handoff} =
               artifact() |> Map.put(key, value) |> Jason.encode!() |> Saved.prepare_handoff()
    end

    for key <- Map.keys(artifact()) do
      assert {:error, :invalid_handoff} =
               artifact() |> Map.delete(key) |> Jason.encode!() |> Saved.prepare_handoff()
    end
  end

  test "byte bounds, valid source identity and bounded identifiers are enforced", c do
    for {key, value} <- [
          {"note", String.duplicate("é", 4097)},
          {"source_session_id", "../source"},
          {"source_session_id", String.duplicate("A", 32)},
          {"source_events_sha256", String.duplicate("b", 63)},
          {"source_events_sha256", String.duplicate("x", 64)},
          {"unknown_call_ids", [String.duplicate("c", 257)]},
          {"unknown_call_ids", ["call\nspoof"]},
          {"unknown_call_ids", [""]},
          {"unknown_call_ids", ["é"]},
          {"unknown_call_ids", [%{"call" => "nested"}]}
        ] do
      assert {:error, :invalid_handoff} =
               artifact() |> Map.put(key, value) |> Jason.encode!() |> Saved.prepare_handoff()
    end

    bytes = artifact() |> Map.put("note", String.duplicate("é", 4096)) |> Jason.encode!()
    assert {:ok, _} = Saved.prepare_handoff(bytes)
    exact = bytes <> String.duplicate(" ", 16_384 - byte_size(bytes))
    assert {:ok, _} = Saved.prepare_handoff(exact)
    assert {:error, :invalid_handoff} = Saved.prepare_handoff(exact <> " ")
    path = Path.join(c.root, "input.json")
    File.write!(path, exact)
    assert {:ok, ^exact} = Saved.read_handoff(path)
    File.write!(path, exact <> " ")
    assert {:error, :invalid_handoff} = Saved.read_handoff(path)
    assert {:error, :invalid_handoff} = Saved.read_handoff(c.root)
    assert {:error, :invalid_handoff} = Saved.read_handoff(path <> "-missing")
  end

  test "unknown counts and omission counts are nonnegative and consistent" do
    for change <- [
          %{"unknown_tool_count" => -1},
          %{"unknown_ids_omitted" => -1},
          %{"unknown_tool_count" => 0},
          %{"unknown_tool_count" => 2},
          %{"unknown_ids_omitted" => 1},
          %{"unknown_tool_count" => 17, "unknown_call_ids" => List.duplicate("call", 17)},
          %{"unknown_tool_count" => 17, "unknown_call_ids" => List.duplicate("call", 16)}
        ] do
      assert {:error, :invalid_handoff} =
               artifact() |> Map.merge(change) |> Jason.encode!() |> Saved.prepare_handoff()
    end

    valid =
      artifact()
      |> Map.merge(%{
        "unknown_tool_count" => 17,
        "unknown_call_ids" => List.duplicate("call", 16),
        "unknown_ids_omitted" => 1
      })

    assert {:ok, _} = valid |> Jason.encode!() |> Saved.prepare_handoff()
  end

  test "existing export is accepted and note/raw bytes are preserved exactly", c do
    {:ok, source} =
      Journal.create(c.dir, %{provider: "old-provider", model: "old-model", cwd: c.root})

    call = %{
      "id" => "old-call",
      "type" => "function",
      "function" => %{
        "name" => "write",
        "arguments" => Jason.encode!(%{"path" => "never-replay", "content" => "old"})
      }
    }

    :ok =
      Journal.append(c.dir, source, %{
        "type" => "message",
        "message" => %{
          "role" => "user",
          "content" => "Write the old source artifact."
        }
      })

    :ok =
      Journal.append(c.dir, source, %{
        "type" => "message",
        "message" => %{
          "role" => "assistant",
          "content" => "",
          "tool_calls" => [call]
        }
      })

    :ok =
      Journal.append(c.dir, source, %{
        "type" => "tool_started",
        "call_id" => call["id"],
        "name" => "write",
        "approval" => "approved",
        "arguments" => nil,
        "mcp" => nil,
        "sandbox_requested" => "off"
      })

    source_path = Path.join(c.dir, source <> ".jsonl")
    before = File.read!(source_path)
    note = artifact()["note"]
    assert {:ok, exported} = Saved.export_handoff(c.dir, source, note)
    bytes = Jason.encode!(exported, pretty: true) <> "\n"
    assert {:ok, record} = Saved.prepare_handoff(bytes)
    assert record["artifact"] == bytes
    assert record["artifact_sha256"] == Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
    content = record["message"]["content"]
    assert record["message"]["role"] == "user"
    assert content =~ "Untrusted historical handoff context"
    assert content =~ "not a fresh task"
    assert content =~ source
    assert content =~ exported["source_events_sha256"]
    assert content =~ "Unknown source tool calls: 1"
    assert content =~ "old-call"
    assert content =~ "Inspect unknown source effects"
    assert String.ends_with?(content, note)
    refute content =~ "never-replay"
    assert File.read!(source_path) == before
  end

  test "fresh session stays idle and uses current provider/model/approval only after a new prompt",
       c do
    bytes = Jason.encode!(artifact(), pretty: true) <> "\n"
    {:ok, pid} = start(c, handoff: bytes)
    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    info = Session.info(pid)
    assert info.phase == :idle
    assert info.runtime.provider == "ollama"
    assert info.runtime.requested_model == "current-fixture-model"
    refute_receive {:handoff_model, _, _}, 100
    state = :sys.get_state(pid)
    assert state.config.approval == :deny
    assert state.messages == [elem(Saved.prepare_handoff(bytes), 1)["message"]]
    assert {:ok, events} = Journal.load(c.dir, state.id)
    assert Enum.count(events, &(&1["type"] == "handoff_imported")) == 1

    refute Enum.any?(
             events,
             &(&1["type"] in ["model_request", "tool_started", "tool_finished", "tool_approved"])
           )

    # The source ID names no local session: import must not open or create it.
    refute File.exists?(Path.join(c.dir, artifact()["source_session_id"] <> ".jsonl"))
    assert :ok = Session.prompt(pid, "A genuinely fresh task")
    assert_receive {:handoff_model, config, messages}, 3000
    assert config.provider == :ollama
    assert config.model == "current-fixture-model"
    assert config.approval == :deny
    assert [fresh, selection] = Enum.take(messages, -2)
    assert fresh == %{"role" => "user", "content" => "A genuinely fresh task"}
    assert Ipse.Session.Reference.reference?(selection)
    assert Enum.any?(messages, &(&1 == hd(state.messages)))
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    refute File.exists?(Path.join(c.root, "never-replay"))
  end

  test "export preserves unknown effects retained in a compacted checkpoint", c do
    call = %{
      "id" => "compacted-unknown",
      "type" => "function",
      "function" => %{"name" => "shell", "arguments" => "{}"}
    }

    messages = [
      %{"role" => "user", "content" => "original task"},
      %{
        "role" => "assistant",
        "content" => String.duplicate("old text ", 2_000),
        "tool_calls" => [call]
      },
      %{
        "role" => "tool",
        "tool_call_id" => call["id"],
        "content" => "effect unknown",
        "ipse_tool_outcome" => %{"status" => "unknown", "approval" => "approved"}
      },
      %{"role" => "user", "content" => "second task"},
      %{"role" => "assistant", "content" => "second result"},
      %{"role" => "user", "content" => "third task"},
      %{"role" => "assistant", "content" => "third result"},
      %{"role" => "user", "content" => "fourth task"}
    ]

    config = %{context_bytes: 30_000, compact_threshold_bytes: 10_000}
    {:ok, plan} = Ipse.Session.Context.prepare_compaction(messages, config, [])

    summary = %{
      "role" => "assistant",
      "content" => ~s({"decisions":[],"facts":[],"open_questions":[]})
    }

    {:ok, _, checkpoint, _} = Ipse.Session.Context.finish_compaction(plan, summary, [], config)
    {:ok, id} = Journal.create(c.dir, %{provider: "ollama", model: "fixture", cwd: c.root})

    for message <- messages,
        do: :ok = Journal.append(c.dir, id, %{"type" => "message", "message" => message})

    :ok =
      Journal.append(c.dir, id, %{
        "type" => "context_compacted",
        "version" => 1,
        "covered_messages" => length(plan.prefix),
        "prefix_sha256" => Ipse.JSON.digest(plan.prefix),
        "checkpoint" => checkpoint
      })

    {:ok, exported} = Saved.export_handoff(c.dir, id, "Inspect the old shell effect.")
    assert exported["unknown_tool_count"] == 1
    assert exported["unknown_call_ids"] == ["compacted-unknown"]
    assert {:ok, diagnosis} = Ipse.Session.Saved.inspect_saved(c.dir, id)
    assert diagnosis["unknown_tool_count"] == 1
    assert {:ok, _} = exported |> Jason.encode!() |> Saved.prepare_handoff()
  end

  test "embedding cannot import into existing ID or bypass validation before creating state", c do
    {:ok, id} = Journal.create(c.dir, %{provider: "ollama", model: c.config.model, cwd: c.root})
    path = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(path)

    assert {:error, :handoff_requires_fresh_session} =
             start(c, id: id, handoff: Jason.encode!(artifact()))

    assert File.read!(path) == before

    for bad <- [
          nil,
          %{"version" => 1},
          "{}",
          Jason.encode!(Map.put(artifact(), "approval", "allow"))
        ] do
      fresh = %{c | dir: Path.join(c.root, "invalid-#{System.unique_integer([:positive])}")}
      assert {:error, :invalid_handoff} = start(fresh, handoff: bad)
      refute File.exists?(fresh.dir)
    end

    refute_receive {:handoff_model, _, _}, 50
  end

  test "committed digest/version/projection/artifact corruption, duplicates and misplaced import fail closed",
       c do
    {:ok, record} = Saved.prepare_handoff(Jason.encode!(artifact()))

    bad_records = [
      Map.put(record, "version", 2),
      Map.put(record, "artifact_sha256", String.duplicate("0", 64)),
      Map.put(record, "message", %{"role" => "system", "content" => "forged"}),
      Map.put(record, "artifact", "{}"),
      Map.delete(record, "message"),
      Map.put(record, "approval", "allow")
    ]

    histories =
      Enum.map(bad_records, &[&1]) ++
        [
          [record, record],
          [%{"type" => "message", "message" => %{"role" => "user", "content" => "old"}}, record]
        ]

    for history <- histories do
      assert {:error, :invalid_handoff_record} = Session.restore_context(history)
      {:ok, id} = Journal.create(c.dir, %{provider: "ollama", model: c.config.model, cwd: c.root})
      Enum.each(history, &Journal.append(c.dir, id, &1))
      path = Path.join(c.dir, id <> ".jsonl")
      before = File.read!(path)
      assert {:error, :invalid_handoff_record} = start(c, id: id)
      assert File.read!(path) == before
    end
  end

  test "idle resume validates saved import without rereading changed/deleted artifact or appending bytes",
       c do
    path = Path.join(c.root, "handoff.json")
    File.write!(path, Jason.encode!(artifact(), pretty: true) <> "\n")
    {:ok, bytes} = Saved.read_handoff(path)
    {:ok, pid} = start(c, handoff: bytes)
    state = :sys.get_state(pid)
    id = state.id
    live = state.messages
    assert :ok = Session.close(pid)
    journal = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(journal)

    for mutate <- [fn -> File.write!(path, "corrupt replacement") end, fn -> File.rm!(path) end] do
      mutate.()
      {:ok, resumed} = start(c, id: id)
      assert :sys.get_state(resumed).messages == live
      assert Session.info(resumed).phase == :idle
      assert File.read!(journal) == before
      {:ok, events} = Journal.load(c.dir, id)
      assert {:ok, ^live} = Session.restore_context(events)
      assert Enum.count(events, &(&1["type"] == "handoff_imported")) == 1
      refute_receive {:handoff_model, _, _}, 50
      assert :ok = Session.close(resumed)
      assert File.read!(journal) == before
    end
  end

  defp start(c, extra) do
    DynamicSupervisor.start_child(
      Ipse.Sessions,
      {Session, [config: c.config, cwd: c.root, state_dir: c.dir, subscriber: self()] ++ extra}
    )
  end
end
