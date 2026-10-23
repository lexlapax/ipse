defmodule Ipse.Session.LifecycleTest do
  use ExUnit.Case, async: false
  alias Ipse.{Journal, Session}
  alias Ipse.Journal
  alias Ipse.Session.Lifecycle
  alias Ipse.Extension.{Config, Registry}

  defmodule Model do
    def complete(_config, _messages, _tools, _emit) do
      {:ok,
       %{
         "role" => "assistant",
         "content" => "fixture answer",
         "provider_data" => %{"native" => "synthetic-native-secret"}
       }, %{}}
    end
  end

  describe "lifecycle" do
    setup do
      root = Path.join(System.tmp_dir!(), "ipse-lifecycle-#{Ipse.Usage.id()}")
      File.mkdir_p!(root)
      on_exit(fn -> File.rm_rf!(root) end)
      {:ok, id} = Journal.create(root, %{"provider" => "demo"})
      %{root: root, id: id, path: Path.join(root, id <> ".jsonl")}
    end

    test "append receipts and paged history retain occurrence identity, not text identity", ctx do
      record = %{
        "type" => "message",
        "message" => %{"role" => "user", "content" => "same λ\ntext"}
      }

      before = File.stat!(ctx.path).size
      assert {:ok, first} = Journal.append_with_source(ctx.root, ctx.id, record)
      assert first["byte_offset"] == before
      assert {:ok, second} = Journal.append_with_source(ctx.root, ctx.id, record)
      refute first["event_id"] == second["event_id"]
      assert Journal.source_matches?(first, record)

      assert {:ok, %{records: [header], next: cursor}} =
               Journal.source_page(ctx.root, ctx.id, 0, 1)

      assert header.source["byte_offset"] == 0
      assert header.record["type"] == "session"
      assert cursor == before
      assert {:ok, %{records: page, next: nil}} = Journal.source_page(ctx.root, ctx.id, cursor)
      assert Enum.map(page, & &1.source) == [first, second]
      assert Enum.map(page, & &1.record) == [record, record]
      assert {:ok, %{records: repeated}} = Journal.source_page(ctx.root, ctx.id, cursor)
      assert repeated == page
      refute String.contains?(File.read!(ctx.path), "event_id")
      assert {:ok, [_, ^record, ^record]} = Journal.load(ctx.root, ctx.id)
    end

    test "legacy appends and noncanonical JSON use actual byte positions without rewriting",
         ctx do
      raw = ~s( { "type": "message", "message": { "role": "user", "content": "λ" } }\n)
      offset = File.stat!(ctx.path).size
      File.write!(ctx.path, raw, [:append])
      record = %{"type" => "message", "message" => %{"role" => "user", "content" => "legacy"}}
      assert :ok = Journal.append(ctx.root, ctx.id, record)
      bytes = File.read!(ctx.path)

      assert {:ok, %{records: [first, second], next: nil}} =
               Journal.source_page(ctx.root, ctx.id, offset)

      assert first.source["byte_offset"] == offset
      assert second.source["byte_offset"] == offset + byte_size(raw)
      assert second.record == record
      assert Journal.source_matches?(first.source, first.record)
      assert File.read!(ctx.path) == bytes
    end

    test "pages bound record count and total bytes without skipping the next record", ctx do
      first = %{"type" => "fixture", "text" => String.duplicate("a", 650_000)}
      second = %{"type" => "fixture", "text" => String.duplicate("b", 450_000)}
      assert {:ok, _} = Journal.append_with_source(ctx.root, ctx.id, first)
      assert {:ok, second_source} = Journal.append_with_source(ctx.root, ctx.id, second)

      assert {:ok, %{records: [_, first_read], next: next}} =
               Journal.source_page(ctx.root, ctx.id, 0, 64)

      assert first_read.record == first
      assert next == second_source["byte_offset"]

      assert {:ok, %{records: [%{record: ^second, source: ^second_source}], next: nil}} =
               Journal.source_page(ctx.root, ctx.id, next, 64)

      assert {:error, :invalid_source_page} = Journal.source_page(ctx.root, ctx.id, 0, 65)
      assert {:error, :invalid_source_page} = Journal.source_page(ctx.root, ctx.id, -1)
      assert {:error, :invalid_source_cursor} = Journal.source_page(ctx.root, ctx.id, 1)

      assert {:error, :invalid_source_cursor} =
               Journal.source_page(ctx.root, ctx.id, File.stat!(ctx.path).size + 1)
    end

    test "unterminated tails are not published or repaired by source reads", ctx do
      offset = File.stat!(ctx.path).size

      tail =
        Jason.encode!(%{
          "type" => "message",
          "message" => %{"role" => "user", "content" => "tail"}
        })

      File.write!(ctx.path, tail, [:append])
      bytes = File.read!(ctx.path)
      assert {:error, :incomplete_source_record} = Journal.source_page(ctx.root, ctx.id, offset)

      assert {:error, :incomplete_journal} =
               Journal.append_with_source(ctx.root, ctx.id, %{"type" => "fixture"})

      assert File.read!(ctx.path) == bytes
      assert :ok = Journal.repair_tail(ctx.root, ctx.id)
      assert {:ok, %{records: [entry], next: nil}} = Journal.source_page(ctx.root, ctx.id, offset)
      assert entry.source["byte_offset"] == offset
      assert Journal.source_matches?(entry.source, entry.record)

      offset = File.stat!(ctx.path).size
      File.write!(ctx.path, "{\"unfinished\":", [:append])
      assert {:error, :incomplete_source_record} = Journal.source_page(ctx.root, ctx.id, offset)
      assert :ok = Journal.repair_tail(ctx.root, ctx.id)
      assert {:ok, %{records: [], next: nil}} = Journal.source_page(ctx.root, ctx.id, offset)
    end

    test "source reads refuse duplicate keys, scalar records and oversized lines without effects",
         ctx do
      offset = File.stat!(ctx.path).size

      for raw <- [~s({"type":"message","type":"forged"}\n), "false\n"] do
        prefix = binary_part(File.read!(ctx.path), 0, offset)
        File.write!(ctx.path, prefix <> raw)
        assert {:error, :invalid_source_record} = Journal.source_page(ctx.root, ctx.id, offset)
        assert File.read!(ctx.path) == prefix <> raw
      end

      prefix = binary_part(File.read!(ctx.path), 0, offset)
      raw = String.duplicate("x", Journal.source_record_bytes() + 1) <> "\n"
      File.write!(ctx.path, prefix <> raw)
      assert {:error, :source_record_too_large} = Journal.source_page(ctx.root, ctx.id, offset)
      assert File.read!(ctx.path) == prefix <> raw
    end

    test "source binding refuses changed content, private terms and forged references", ctx do
      record = %{"type" => "fixture", "text" => "synthetic-private"}
      assert {:ok, source} = Journal.source(ctx.id, 0, record)
      assert Journal.valid_source?(source)
      refute Journal.source_matches?(source, Map.put(record, "text", "changed"))
      refute Journal.valid_source?(Map.put(source, "session_id", Ipse.Usage.id()))
      refute Journal.valid_source?(Map.put(source, "byte_offset", 1))
      refute Journal.valid_source?(Map.put(source, "extra", true))
      refute Journal.valid_source?(Map.put(source, "version", 2))
      assert {:error, _} = Journal.source(ctx.id, 0, %{"pid" => self()})
      assert {:error, _} = Journal.source(ctx.id, 0, %{atom: "key"})
      assert {:ok, other} = Journal.source(Ipse.Usage.id(), 0, record)
      refute source["event_id"] == other["event_id"]
    end

    test "metadata and private prompt views share identity without sharing content or hashes",
         ctx do
      text = "synthetic-original-secret"

      record = %{
        "type" => "extension_prompt_received",
        "version" => 1,
        "original" => text,
        "original_sha256" => Ipse.JSON.sha256(text)
      }

      assert {:ok, source} = Journal.append_with_source(ctx.root, ctx.id, record)
      assert {:ok, metadata} = Lifecycle.project(source, record, "metadata")
      assert {:ok, private} = Lifecycle.project(source, record, "prompt.original")
      assert metadata["event_id"] == private["event_id"]
      assert metadata["type"] == "prompt.received"
      assert metadata["data"] == %{"input_bytes" => byte_size(text)}
      assert private["data"] == %{"text" => text}
      refute Map.has_key?(metadata["source"], "record_sha256")

      refute String.contains?(Jason.encode!(metadata), [
               text,
               Ipse.JSON.sha256(text),
               source["record_sha256"]
             ])

      assert {:error, :lifecycle_view_unavailable} =
               Lifecycle.project(source, record, "prompt.expanded")

      assert {:error, :invalid_lifecycle_event} =
               Lifecycle.project(source, Map.put(record, "original", "changed"), "metadata")

      malformed = Map.put(record, "original_sha256", String.duplicate("0", 64))
      assert {:ok, malformed_source} = Journal.source(ctx.id, 0, malformed)

      assert {:error, :invalid_lifecycle_event} =
               Lifecycle.project(malformed_source, malformed, "metadata")
    end

    test "private view overflow refuses instead of truncating; expanded text excludes native data",
         ctx do
      record = %{
        "type" => "message",
        "message" => %{
          "role" => "user",
          "content" => String.duplicate("a", 8_193),
          "provider_data" => %{"native" => "synthetic-native-secret"}
        }
      }

      assert {:ok, source} = Journal.source(ctx.id, 0, record)
      assert {:ok, metadata} = Lifecycle.project(source, record, "metadata")

      assert {:error, :private_lifecycle_view_too_large} =
               Lifecycle.project(source, record, "prompt.expanded")

      assert metadata["data"] == %{"input_bytes" => 8_193}
      refute String.contains?(Jason.encode!(metadata), "synthetic-native-secret")
      record = put_in(record, ["message", "content"], "visible only")
      assert {:ok, source} = Journal.source(ctx.id, 0, record)
      assert {:ok, private} = Lifecycle.project(source, record, "prompt.expanded")
      assert private["data"] == %{"text" => "visible only"}
    end

    test "a real transformed session exposes distinct committed stages and restores without delivery",
         ctx do
      home = Path.join(ctx.root, "home")
      artifact = "builtin:prompt-annotation:1"

      data = %{
        "extension_trust" => [
          %{
            "artifact" => artifact,
            "capabilities" => ["transform.prompt"],
            "allow_project" => false,
            "allow_children" => false
          }
        ],
        "extensions" => [
          %{
            "instance" => "annotation",
            "artifact" => artifact,
            "enabled" => true,
            "options" => %{"text" => "synthetic annotation"},
            "order" => 10,
            "lifetime" => "session"
          }
        ]
      }

      assert {:ok, catalog} =
               Config.resolve(
                 [%{scope: "operator", path: Path.join(home, "config.json"), data: data}],
                 []
               )

      assert {:ok, entries} = Registry.prepare(catalog, home)

      config = %{
        provider: :demo,
        model: "fixture",
        provider_module: Model,
        approval: :deny,
        home: home,
        extensions: entries,
        context_bytes: 65_536,
        max_steps: 3
      }

      directory = Path.join(ctx.root, "session")

      assert {:ok, session} =
               Session.start_link(
                 config: config,
                 cwd: ctx.root,
                 state_dir: directory,
                 subscriber: self()
               )

      assert :ok = Session.prompt(session, "synthetic operator prompt")
      assert_receive {:ipse, ^session, {:done, _}}, 15_000
      id = Session.info(session).id
      assert :ok = Session.close(session)
      path = Path.join(directory, id <> ".jsonl")
      bytes = File.read!(path)
      assert {:ok, %{records: records, next: nil}} = Journal.source_page(directory, id, 0, 64)

      events =
        for %{source: source, record: record} <- records,
            {:ok, event} <- [Lifecycle.project(source, record, "metadata")],
            do: event

      prompts = Enum.filter(events, &String.starts_with?(&1["type"], "prompt."))

      assert Enum.map(prompts, & &1["type"]) ==
               ~w(prompt.received prompt.expanded_committed prompt.projection_committed)

      assert Enum.any?(events, &(&1["type"] == "session.created"))
      assert Enum.any?(events, &(&1["type"] == "context.workspace_committed"))
      assert Enum.any?(events, &(&1["type"] == "model.admitted"))
      assert Enum.any?(events, &(&1["type"] == "model.finished"))
      assert Enum.any?(events, &(&1["type"] == "assistant.committed"))
      assert Enum.any?(events, &(&1["type"] == "turn.finished"))
      [_, _, projection] = prompts
      entry = Enum.find(records, &(&1.source["event_id"] == projection["event_id"]))
      assert {:ok, private} = Lifecycle.project(entry.source, entry.record, "prompt.projection")
      assert String.contains?(private["data"]["text"], "synthetic annotation")

      refute String.contains?(Jason.encode!(events), [
               "synthetic operator prompt",
               "synthetic annotation",
               "synthetic-native-secret"
             ])

      assert {:ok, resumed} =
               Session.start_link(
                 config: config,
                 cwd: ctx.root,
                 state_dir: directory,
                 subscriber: self(),
                 id: id
               )

      assert Session.info(resumed).id == id
      refute_receive {:ipse, ^resumed, {:done, _}}, 100
      assert File.read!(path) == bytes
      assert :ok = Session.close(resumed)
    end
  end

  describe "lifecycle metadata" do
    test "saved result finals expose completion metadata without source bodies or descriptors" do
      record = %{
        "type" => "extension_invocation_result",
        "version" => 2,
        "invocation_id" => Ipse.Usage.id(),
        "action_count" => 2,
        "delivery" => %{"output_id" => "private-output", "sha256" => "private-sha"},
        "text" => "private-descriptor",
        "payload" => %{"arguments" => %{"secret" => "private-input"}}
      }

      reference = source(record)
      assert {:ok, event} = Lifecycle.project(reference, record, "metadata")
      assert event["type"] == "extension.invocation_recorded"
      assert event["data"] == %{"action_count" => 2}
      assert event["correlations"] == %{"invocation_id" => record["invocation_id"]}
      refute Jason.encode!(event) =~ "private-"
      assert {:ok, observation} = Ipse.Observability.build_event(reference, record, 1, 0)
      assert observation["event"] == event

      for type <- ~w(extension_output_begin extension_output_chunk extension_output_seal),
          version <- [1, 2] do
        hidden = Map.merge(record, %{"type" => type, "version" => version})
        assert {:error, _} = Lifecycle.project(source(hidden), hidden, "metadata")
      end

      invalid = Map.put(record, "version", 3)
      assert {:error, _} = Lifecycle.project(source(invalid), invalid, "metadata")
    end

    test "version-two action metadata omits private bindings and keeps the closed vocabulary" do
      for {type, event_type} <- [
            {"extension_action_intent", "extension.action_admitted"},
            {"extension_action_result", "extension.action_recorded"}
          ] do
        record = %{
          "type" => type,
          "version" => 2,
          "parent_invocation_id" => Ipse.Usage.id(),
          "operation_id" => Ipse.Usage.id(),
          "effect_binding" => %{"alias" => "secret-route", "server" => "secret-server"},
          "request" => %{"arguments" => %{"query" => "secret-argument"}},
          "outcome" => %{"status" => "ok", "value" => %{"text" => "secret-result"}}
        }

        assert {:ok, event} =
                 Lifecycle.project(source(record, Ipse.Usage.id()), record, "metadata")

        assert event["type"] == event_type
        assert event["correlations"]["operation_id"] == record["operation_id"]
        refute Jason.encode!(event) =~ "secret-"
        invalid = Map.put(record, "type", "extension_question")

        assert {:error, _} =
                 Lifecycle.project(source(invalid, Ipse.Usage.id()), invalid, "metadata")
      end
    end

    test "request metadata keeps durable identity and causal links while excluding provider payloads" do
      session = Ipse.Usage.id()
      parent_session = Ipse.Usage.id()
      parent_request = Ipse.Usage.id()

      config = %{
        provider: :demo,
        model: "synthetic-model-secret",
        base_url: "https://synthetic-private-endpoint.invalid",
        delegation_origin: %{
          "parent_session_id" => parent_session,
          "parent_request_id" => parent_request
        }
      }

      record = Ipse.Usage.admission(session, config, "model", Ipse.Usage.id())
      source = source(record, session)
      assert {:ok, event} = Lifecycle.project(source, record, "metadata")
      assert event["type"] == "model.admitted"
      assert event["event_id"] == source["event_id"]
      assert event["data"] == %{"kind" => "model"}
      assert event["correlations"]["request_id"] == record["request_id"]
      assert event["correlations"]["parent_session_id"] == parent_session
      assert event["correlations"]["parent_request_id"] == parent_request

      refute String.contains?(Jason.encode!(event), [
               config.model,
               record["endpoint_sha256"],
               source["record_sha256"]
             ])

      assert {:error, :lifecycle_view_unavailable} =
               Lifecycle.project(source, record, "model.private")

      assert {:error, :invalid_lifecycle_event} = Lifecycle.project(source, record, nil)

      assert {:error, :invalid_lifecycle_event} =
               Lifecycle.project(source, Map.put(record, "attempt", 2), "metadata")
    end

    test "a closed vocabulary projects existing boundaries without exposing arbitrary fields" do
      records = [
        {%{"type" => "session", "metadata" => %{"secret" => "private"}}, "session.created"},
        {%{
           "type" => "tool_started",
           "approval" => "approved",
           "arguments" => %{"text" => "private"}
         }, "tool.started"},
        {%{
           "type" => "message",
           "message" => %{"role" => "tool", "content" => "private", "tool_call_id" => "private"}
         }, "tool.result_recorded"},
        {%{
           "type" => "message",
           "message" => %{
             "role" => "assistant",
             "content" => "private",
             "provider_data" => %{"native" => "private"}
           }
         }, "assistant.committed"},
        {%{
           "type" => "workspace_context_snapshot",
           "snapshot" => %{"sources" => [%{"path" => "private"}]}
         }, "context.workspace_committed"},
        {%{"type" => "mcp_catalog", "version" => 1, "tools" => [%{"description" => "private"}]},
         "context.catalog_committed"},
        {%{
           "type" => "extension_context_snapshot",
           "version" => 1,
           "request_id" => Ipse.Usage.id(),
           "content" => "private"
         }, "context.extensions_committed"},
        {%{"type" => "context_compacted", "summary" => "private"},
         "context.compaction_committed"},
        {%{"type" => "compaction_failed", "reason" => "private"}, "context.compaction_failed"},
        {%{"type" => "operator_question", "version" => 1, "arguments" => %{"text" => "private"}},
         "question.waiting"},
        {%{"type" => "operator_answer", "version" => 1, "message" => "private"},
         "question.answered"},
        {%{"type" => "operator_question_closed", "version" => 1, "reason" => "private"},
         "question.closed"},
        {%{"type" => "delegation_started", "child_id" => Ipse.Usage.id(), "call_id" => "private"},
         "child.started"},
        {%{
           "type" => "lifecycle_turn_settling",
           "version" => 1,
           "turn_id" => Ipse.Usage.id(),
           "final_sha256" => "private"
         }, "turn.settling"},
        {%{"type" => "turn_finished", "status" => "ok"}, "turn.finished"},
        {%{"type" => "cancelled"}, "turn.cancelled"}
      ]

      for {record, type} <- records do
        source = source(record)
        assert {:ok, event} = Lifecycle.project(source, record, "metadata")
        assert event["type"] == type
        refute String.contains?(Jason.encode!(event), ["private", source["record_sha256"]])
      end

      record = %{"type" => "extension_invented_intent", "version" => 1}

      assert {:error, :unsupported_lifecycle_record} =
               Lifecycle.project(source(record), record, "metadata")
    end

    test "invalid dimensions and identifiers refuse rather than exporting or coercing them" do
      for record <- [
            %{"type" => "tool_started", "approval" => "synthetic-secret"},
            %{"type" => "turn_finished", "status" => "synthetic-secret"},
            %{
              "type" => "request_measured",
              "kind" => "model",
              "outcome" => "completed",
              "duration_ms" => -1
            },
            %{
              "type" => "request_measured",
              "kind" => "model",
              "outcome" => "completed",
              "duration_ms" => 1.5
            },
            %{"type" => "delegation_started", "child_id" => "synthetic-secret"},
            %{
              "type" => "extension_event_result",
              "version" => 1,
              "delivery_id" => Ipse.Usage.id(),
              "turn_id" => Ipse.Usage.id(),
              "outcome" => "synthetic-secret"
            }
          ] do
        assert {:error, :invalid_lifecycle_event} =
                 Lifecycle.project(source(record), record, "metadata")
      end
    end

    test "extension receipts distinguish action results from arbitrary business assertions" do
      invocation = Ipse.Usage.id()
      operation = Ipse.Usage.id()

      record = %{
        "type" => "extension_action_result",
        "version" => 1,
        "parent_invocation_id" => invocation,
        "operation_id" => operation,
        "outcome" => %{"status" => "denied", "value" => %{"text" => "synthetic-private"}},
        "request" => %{"text" => "synthetic-private"}
      }

      assert {:ok, event} = Lifecycle.project(source(record), record, "metadata")
      assert event["data"] == %{"status" => "denied"}

      assert event["correlations"] == %{
               "parent_invocation_id" => invocation,
               "operation_id" => operation
             }

      result = %{
        "type" => "extension_invocation_result",
        "version" => 1,
        "invocation_id" => invocation,
        "action_count" => 1,
        "value" => %{"status" => "completed", "secret" => "synthetic-private"}
      }

      assert {:ok, event} = Lifecycle.project(source(result), result, "metadata")
      assert event["type"] == "extension.invocation_recorded"
      assert event["data"] == %{"action_count" => 1}
      refute String.contains?(Jason.encode!(event), ["synthetic-private", "completed"])
    end
  end

  describe "lifecycle answer" do
    test "one occurrence has private views and content-free shared diagnostic metadata" do
      id = Ipse.Usage.id()
      {:ok, effective} = Journal.source(id, 0, %{"type" => "synthetic"})

      record =
        Lifecycle.answer(
          Ipse.Usage.id(),
          Ipse.Usage.id(),
          %{
            "role" => "assistant",
            "content" => "private original",
            "provider_data" => %{"secret" => "native secret"}
          },
          "private presented",
          effective
        )

      assert Lifecycle.valid_answer?(record)
      {:ok, source} = Journal.source(id, 1, record)
      {:ok, original} = Lifecycle.project(source, record, "answer.original")
      {:ok, presented} = Lifecycle.project(source, record, "answer.presented")
      assert original["data"]["text"] == "private original"
      assert presented["data"]["text"] == "private presented"
      assert original["event_id"] == presented["event_id"]
      {:ok, wrapper} = Ipse.Observability.build_event(source, record, 1, 0)
      assert Ipse.Observability.valid_event?(wrapper)
      assert wrapper["group"] == "stream"
      assert wrapper["event"]["correlations"]["causing_event_id"] == effective["event_id"]
      refute Jason.encode!(wrapper) =~ "private"
      refute Jason.encode!(wrapper) =~ "sha256"
      refute Jason.encode!(original) =~ "native secret"
    end

    test "an unavailable private view keeps counts and hashes without a truncated substitute" do
      id = Ipse.Usage.id()
      {:ok, effective} = Journal.source(id, 0, %{"type" => "synthetic"})

      record =
        Lifecycle.answer(
          Ipse.Usage.id(),
          Ipse.Usage.id(),
          %{"role" => "assistant", "content" => String.duplicate("a", 8193)},
          "small",
          effective
        )

      assert Lifecycle.valid_answer?(record)
      {:ok, source} = Journal.source(id, 1, record)

      assert {:error, :private_lifecycle_view_too_large} =
               Lifecycle.project(source, record, "answer.original")

      assert {:ok, %{"data" => %{"text" => "small"}}} =
               Lifecycle.project(source, record, "answer.presented")

      assert {:ok, %{"data" => %{"original_bytes" => 8193}}} =
               Lifecycle.project(source, record, "metadata")

      refute Lifecycle.valid_answer?(Map.put(record, "original_bytes", 1))
      refute Lifecycle.valid_answer?(Map.put(record, "presented", "forged"))
      refute Lifecycle.valid_answer?(Map.put(record, "private_extra", "no"))
    end
  end

  defp source(record, session \\ Ipse.Usage.id()) do
    {:ok, source} = Journal.source(session, 0, record)
    source
  end
end
