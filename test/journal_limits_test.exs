defmodule Ipse.JournalLimitsTest do
  use ExUnit.Case, async: false
  alias Ipse.Journal
  alias Ipse.Journal.{Limits, Reader, Writer}

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-journal-bounds-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  defmodule LargeModel do
    def complete(_, messages, _, _) do
      if Enum.any?(messages, &(&1["role"] == "tool")) do
        {:ok, %{"role" => "assistant", "content" => "done"}, %{}}
      else
        {:ok,
         %{
           "role" => "assistant",
           "content" => String.duplicate("synthetic padding ", 4_096),
           "tool_calls" => [
             %{
               "id" => "bounded-effect",
               "function" => %{
                 "name" => "write",
                 "arguments" => Jason.encode!(%{"path" => "effect", "content" => "must not run"})
               }
             }
           ]
         }, %{}}
      end
    end
  end

  defmodule QuestionModel do
    def complete(_, _, _, _) do
      {:ok,
       %{
         "role" => "assistant",
         "content" => "",
         "tool_calls" => [
           %{
             "id" => "fixture-question",
             "function" => %{
               "name" => "ask_operator",
               "arguments" =>
                 Jason.encode!(%{
                   "questions" => [
                     %{
                       "id" => "choice",
                       "kind" => "single",
                       "prompt" => "Choose a synthetic fixture option",
                       "options" => [
                         %{"id" => "a", "label" => "A"},
                         %{"id" => "b", "label" => "B"}
                       ]
                     }
                   ]
                 })
             }
           }
         ]
       }, %{}}
    end
  end

  defmodule EffectModel do
    def complete(_, _, _, _) do
      {:ok,
       %{
         "role" => "assistant",
         "content" => "",
         "tool_calls" => [
           %{
             "id" => "started-effect",
             "function" => %{
               "name" => "shell",
               "arguments" =>
                 Jason.encode!(%{"command" => "printf effected > effect; printf '%40000s' x"})
             }
           }
         ]
       }, %{}}
    end
  end

  test "byte, event and record exhaustion each seal once within the admitted limits", c do
    for policy <- [%{"max_bytes" => 1_024}, %{"max_events" => 4}, %{"max_record_bytes" => 512}] do
      {:ok, id} = Journal.create(c.root, %{})
      {:ok, writer} = Writer.start(c.root, id, self(), policy)

      event = %{
        "type" => "padding",
        "value" => String.duplicate("x", if(policy["max_record_bytes"], do: 600, else: 180))
      }

      written =
        Enum.reduce_while(1..100, 0, fn _, count ->
          case Writer.append(writer, event) do
            :ok -> {:cont, count + 1}
            {:error, :journal_limit_reached} -> {:halt, count}
          end
        end)

      assert written < 100
      path = Path.join(c.root, id <> ".jsonl")
      bytes = File.read!(path)
      assert {:error, :journal_limit_reached} = Writer.append(writer, %{"type" => "later"})
      assert File.read!(path) == bytes
      assert :ok = Writer.close(writer)
      assert {:ok, events} = Journal.load(c.root, id)
      assert length(events) == written + 2
      receipt = List.last(events)
      assert Limits.valid_receipt?(receipt)
      assert receipt["event_count"] == written + 1
      assert byte_size(bytes) <= receipt["limits"]["max_bytes"]
      assert length(events) <= receipt["limits"]["max_events"]
      assert {:ok, _} = Ipse.Session.restore_context(events)
      assert {:error, :journal_limit_reached} = Writer.start(c.root, id, self(), policy)
      assert {:error, :journal_limit_reached} = Journal.append(c.root, id, event)
      assert File.read!(path) == bytes
      assert {:error, _} = Ipse.Session.restore_context(events ++ [%{"type" => "later"}])

      assert {:error, _} =
               Ipse.Session.restore_context(
                 List.replace_at(events, -1, Map.put(receipt, "event_count", 0))
               )
    end
  end

  test "oversized legacy files refuse before loading while listing only reads their header", c do
    {:ok, id} = Journal.create(c.root, %{"task" => "bounded header"})
    path = Path.join(c.root, id <> ".jsonl")
    header = File.read!(path)
    {:ok, file} = :file.open(String.to_charlist(path), [:read, :write, :raw, :binary])
    {:ok, _} = :file.position(file, Limits.defaults()["max_bytes"])
    :ok = :file.write(file, "\n")
    :ok = :file.close(file)
    size = File.stat!(path).size
    assert {:error, :journal_limit_reached} = Journal.load(c.root, id)
    assert {:error, :journal_limit_reached} = Journal.repair_tail(c.root, id)
    assert {:error, :journal_limit_reached} = Writer.start(c.root, id, self())
    assert [%{"id" => ^id, "metadata" => %{"task" => "bounded header"}}] = Journal.list(c.root)

    assert {:ok, %{header: %{"metadata" => %{"task" => "bounded header"}}}} =
             Reader.path(path, %{"max_record_bytes" => 512}, :header)

    assert {:ok, %{records: [%{record: %{"type" => "session"}}]}} =
             Journal.source_page(c.root, id, 0, 1)

    assert File.stat!(path).size == size
    {:ok, read} = :file.open(String.to_charlist(path), [:read, :raw, :binary])
    assert {:ok, ^header} = :file.pread(read, 0, byte_size(header))
    :file.close(read)
  end

  test "incremental readers reject event and line excess without repairing or changing evidence",
       c do
    {:ok, id} = Journal.create(c.root, %{})
    path = Path.join(c.root, id <> ".jsonl")
    header = File.read!(path)
    File.write!(path, header <> String.duplicate("{\"type\":\"padding\"}\n", 3))
    bytes = File.read!(path)
    assert {:error, :journal_limit_reached} = Journal.load(c.root, id, %{"max_events" => 2})

    assert {:error, :journal_limit_reached} =
             Journal.repair_tail(c.root, id, %{"max_events" => 2})

    assert File.read!(path) == bytes
    File.write!(path, header <> String.duplicate("x", 513))
    bytes = File.read!(path)
    assert {:error, :journal_limit_reached} = Reader.path(path, %{"max_record_bytes" => 512})

    assert {:error, :journal_limit_reached} =
             Journal.repair_tail(c.root, id, %{"max_record_bytes" => 512})

    assert File.read!(path) == bytes
    tail = Jason.encode!(%{"tail" => ""})

    tail =
      Jason.encode!(%{
        "tail" => String.duplicate("x", 1_024 - byte_size(header) - byte_size(tail))
      })

    File.write!(path, header <> tail)
    assert File.stat!(path).size == 1_024

    assert {:error, :journal_limit_reached} =
             Journal.repair_tail(c.root, id, %{"max_bytes" => 1_024})

    assert File.read!(path) == header <> tail
  end

  test "a pending native question remains readable after quota sealing", c do
    config = %{
      provider: :demo,
      model: "fixture",
      provider_module: QuestionModel,
      home: c.root <> "/home",
      operator_home: c.root,
      operator_questions: true,
      approval: :deny,
      journal: %{"max_record_bytes" => 32_768}
    }

    {:ok, session} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Ipse.Session, config: config, cwd: c.root, state_dir: c.root, subscriber: self()}
      )

    id = Ipse.Session.info(session).id
    :ok = Ipse.Session.prompt(session, "Synthetic question")
    assert_receive {:ipse, ^session, {:question, question, _}}, 5_000

    :sys.replace_state(session, fn state ->
      assert {:error, :journal_limit_reached} =
               Writer.append(
                 state.journal_writer,
                 %{"type" => "padding", "value" => String.duplicate("x", 32_769)}
               )

      state
    end)

    monitor = Process.monitor(session)
    assert catch_exit(Ipse.Session.answer(session, question, %{"choice" => "a"}))
    assert_receive {:DOWN, ^monitor, :process, ^session, :journal_limit_reached}, 5_000
    path = Path.join(c.root, id <> ".jsonl")
    bytes = File.read!(path)
    assert {:ok, _} = Ipse.Diagnostics.saved(c.root, id)
    {:ok, events} = Journal.load(c.root, id)
    refute Enum.any?(events, &(&1["type"] == "operator_answer"))

    assert {:ok, _} =
             Ipse.Handoff.export(
               c.root,
               id,
               "Ask the unanswered question again in a fresh session."
             )

    assert {:error, :journal_limit_reached} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session,
                config: config, cwd: c.root, state_dir: c.root, subscriber: self(), id: id}
             )

    assert File.read!(path) == bytes
  end

  test "quota loss of a started effect result retains unknown outcome without replay", c do
    config = %{
      provider: :demo,
      model: "fixture",
      provider_module: EffectModel,
      home: c.root <> "/home",
      approval: :allow,
      journal: %{"max_record_bytes" => 32_768}
    }

    {:ok, session} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Ipse.Session, config: config, cwd: c.root, state_dir: c.root, subscriber: self()}
      )

    id = Ipse.Session.info(session).id
    monitor = Process.monitor(session)
    :ok = Ipse.Session.prompt(session, "Synthetic started effect")
    assert_receive {:DOWN, ^monitor, :process, ^session, :journal_limit_reached}, 5_000
    assert File.read!(Path.join(c.root, "effect")) == "effected"
    File.write!(Path.join(c.root, "effect"), "operator edit")
    assert {:ok, events} = Journal.load(c.root, id)
    assert {:ok, messages} = Ipse.Session.restore_context(events)
    assert Enum.any?(messages, &(get_in(&1, ["ipse_tool_outcome", "status"]) == "unknown"))
    assert {:ok, _} = Ipse.Diagnostics.saved(c.root, id)

    assert {:ok, _} =
             Ipse.Handoff.export(c.root, id, "Inspect the unknown shell effect before any retry.")

    assert File.read!(Path.join(c.root, "effect")) == "operator edit"
  end

  test "durable quota stops before an oversized response can dispatch its effect" do
    root = Path.join(System.tmp_dir!(), "ipse-quota-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)

    config = %{
      provider: :demo,
      model: "fixture",
      provider_module: LargeModel,
      home: root <> "/home",
      approval: :allow,
      max_steps: 3,
      journal: %{"max_bytes" => 32_768}
    }

    {:ok, session} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Ipse.Session, config: config, cwd: root, state_dir: root, subscriber: self()}
      )

    id = Ipse.Session.info(session).id
    monitor = Process.monitor(session)

    try do
      :ok = Ipse.Session.prompt(session, "Synthetic oversized durable response")

      outcome =
        receive do
          {:DOWN, ^monitor, :process, ^session, reason} -> {:stopped, reason}
          {:ipse, ^session, {:done, status}} -> {:done, status}
        after
          5_000 -> :timeout
        end

      assert outcome == {:stopped, :journal_limit_reached}
      refute File.exists?(Path.join(root, "effect"))
      assert File.stat!(Path.join(root, id <> ".jsonl")).size <= 32_768
      assert {:ok, events} = Ipse.Journal.load(root, id)
      assert List.last(events)["type"] == "journal_limit_reached"
      assert {:ok, _} = Ipse.Session.restore_context(events)
      bytes = File.read!(Path.join(root, id <> ".jsonl"))

      assert {:error, :journal_limit_reached} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Ipse.Session,
                  config: config, cwd: root, state_dir: root, subscriber: self(), id: id}
               )

      assert File.read!(Path.join(root, id <> ".jsonl")) == bytes
      assert {:ok, diagnostics} = Ipse.Diagnostics.saved(root, id)
      assert diagnostics["journal_limit"]["status"] == "sealed"
      assert diagnostics["journal_limit"]["reason"] == "bytes"

      assert {:ok, _} =
               Ipse.Handoff.export(
                 root,
                 id,
                 "Inspect the preserved refusal before starting a new task."
               )
    after
      if Process.alive?(session), do: Ipse.Session.close(session)
    end
  end
end
