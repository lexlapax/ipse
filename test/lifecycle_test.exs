defmodule Ipse.LifecycleTest do
  use ExUnit.Case, async: false
  alias Ipse.{Journal, Session}
  alias Ipse.Lifecycle.{Source, Event}
  alias Ipse.Extensions.{Config, Registry}

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

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-lifecycle-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, id} = Journal.create(root, %{"provider" => "demo"})
    %{root: root, id: id, path: Path.join(root, id <> ".jsonl")}
  end

  test "append receipts and paged history retain occurrence identity, not text identity", ctx do
    record = %{"type" => "message", "message" => %{"role" => "user", "content" => "same λ\ntext"}}
    before = File.stat!(ctx.path).size
    assert {:ok, first} = Journal.append_with_source(ctx.root, ctx.id, record)
    assert first["byte_offset"] == before
    assert {:ok, second} = Journal.append_with_source(ctx.root, ctx.id, record)
    refute first["event_id"] == second["event_id"]
    assert Source.matches?(first, record)

    assert {:ok, %{records: [header], next: cursor}} = Journal.source_page(ctx.root, ctx.id, 0, 1)
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

  test "legacy appends and noncanonical JSON use actual byte positions without rewriting", ctx do
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
    assert Source.matches?(first.source, first.record)
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
      Jason.encode!(%{"type" => "message", "message" => %{"role" => "user", "content" => "tail"}})

    File.write!(ctx.path, tail, [:append])
    bytes = File.read!(ctx.path)
    assert {:error, :incomplete_source_record} = Journal.source_page(ctx.root, ctx.id, offset)

    assert {:error, :incomplete_journal} =
             Journal.append_with_source(ctx.root, ctx.id, %{"type" => "fixture"})

    assert File.read!(ctx.path) == bytes
    assert :ok = Journal.repair_tail(ctx.root, ctx.id)
    assert {:ok, %{records: [entry], next: nil}} = Journal.source_page(ctx.root, ctx.id, offset)
    assert entry.source["byte_offset"] == offset
    assert Source.matches?(entry.source, entry.record)

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
    raw = String.duplicate("x", Source.record_bytes() + 1) <> "\n"
    File.write!(ctx.path, prefix <> raw)
    assert {:error, :source_record_too_large} = Journal.source_page(ctx.root, ctx.id, offset)
    assert File.read!(ctx.path) == prefix <> raw
  end

  test "source binding refuses changed content, private terms and forged references", ctx do
    record = %{"type" => "fixture", "text" => "synthetic-private"}
    assert {:ok, source} = Source.build(ctx.id, 0, record)
    assert Source.valid?(source)
    refute Source.matches?(source, Map.put(record, "text", "changed"))
    refute Source.valid?(Map.put(source, "session_id", Ipse.Usage.id()))
    refute Source.valid?(Map.put(source, "byte_offset", 1))
    refute Source.valid?(Map.put(source, "extra", true))
    refute Source.valid?(Map.put(source, "version", 2))
    assert {:error, _} = Source.build(ctx.id, 0, %{"pid" => self()})
    assert {:error, _} = Source.build(ctx.id, 0, %{atom: "key"})
    assert {:ok, other} = Source.build(Ipse.Usage.id(), 0, record)
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
    assert {:ok, metadata} = Event.project(source, record, "metadata")
    assert {:ok, private} = Event.project(source, record, "prompt.original")
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
             Event.project(source, record, "prompt.expanded")

    assert {:error, :invalid_lifecycle_event} =
             Event.project(source, Map.put(record, "original", "changed"), "metadata")

    malformed = Map.put(record, "original_sha256", String.duplicate("0", 64))
    assert {:ok, malformed_source} = Source.build(ctx.id, 0, malformed)

    assert {:error, :invalid_lifecycle_event} =
             Event.project(malformed_source, malformed, "metadata")
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

    assert {:ok, source} = Source.build(ctx.id, 0, record)
    assert {:ok, metadata} = Event.project(source, record, "metadata")

    assert {:error, :private_lifecycle_view_too_large} =
             Event.project(source, record, "prompt.expanded")

    assert metadata["data"] == %{"input_bytes" => 8_193}
    refute String.contains?(Jason.encode!(metadata), "synthetic-native-secret")
    record = put_in(record, ["message", "content"], "visible only")
    assert {:ok, source} = Source.build(ctx.id, 0, record)
    assert {:ok, private} = Event.project(source, record, "prompt.expanded")
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
          {:ok, event} <- [Event.project(source, record, "metadata")],
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
    assert {:ok, private} = Event.project(entry.source, entry.record, "prompt.projection")
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
