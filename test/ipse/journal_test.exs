defmodule Ipse.JournalTest do
  use ExUnit.Case, async: false
  alias Ipse.Journal
  alias Ipse.Journal.Writer

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

  describe "ipse/journal" do
    setup do
      dir = Path.join(System.tmp_dir!(), "ipse-journal-#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(dir) end)
      %{dir: dir}
    end

    test "creates protected JSONL sessions, appends events, and lists metadata", %{dir: dir} do
      assert {:ok, id} = Journal.create(dir, %{"task" => "demo"})
      assert Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
      assert :ok = Journal.append(dir, id, %{"type" => "message", "text" => "hello"})
      assert {:ok, [session, message]} = Journal.load(dir, id)
      assert session["metadata"] == %{"task" => "demo"}
      assert message["text"] == "hello"
      assert [%{"id" => ^id, "metadata" => %{"task" => "demo"}}] = Journal.list(dir)
      assert {:ok, %{mode: directory_mode}} = File.stat(dir)
      assert Bitwise.band(directory_mode, 0o777) == 0o700
      assert {:ok, %{mode: file_mode}} = File.stat(Path.join(dir, id <> ".jsonl"))
      assert Bitwise.band(file_mode, 0o777) == 0o600
    end

    test "inactive append rejects hardlinks before changing protection or contents", %{dir: dir} do
      {:ok, id} = Journal.create(dir, %{})
      path = Path.join(dir, id <> ".jsonl")
      other = path <> ".linked"
      File.chmod!(path, 0o644)
      File.ln!(path, other)
      before = File.read!(path)
      mode = File.stat!(path).mode
      assert {:error, :journal_unavailable} = Journal.append(dir, id, %{"type" => "no"})
      assert File.read!(path) == before
      assert File.read!(other) == before
      assert File.stat!(path).mode == mode
    end

    test "load tolerates a truncated last line, while append refuses to extend it", %{dir: dir} do
      assert {:ok, id} = Journal.create(dir, %{})
      path = Path.join(dir, id <> ".jsonl")
      File.write!(path, "{\"type\":", [:append])

      assert {:ok, [%{"type" => "session"}]} = Journal.load(dir, id)
      assert {:error, :incomplete_journal} = Journal.append(dir, id, %{"type" => "next"})
      assert :ok = Journal.repair_tail(dir, id)
      assert :ok = Journal.append(dir, id, %{"type" => "next"})
      assert {:ok, [%{"type" => "session"}, %{"type" => "next"}]} = Journal.load(dir, id)
    end

    test "rejects traversal IDs and corruption before the final line", %{dir: dir} do
      assert {:error, :invalid_id} = Journal.load(dir, "../outside")
      assert {:ok, id} = Journal.create(dir, %{})
      path = Path.join(dir, id <> ".jsonl")
      File.write!(path, "not-json\n{\"type\":\"last\"}\n")

      assert {:error, {:corrupt_journal, _}} = Journal.load(dir, id)
      assert {:error, {:corrupt_journal, _}} = Journal.append(dir, id, %{"type" => "next"})
      assert {:error, {:corrupt_journal, _}} = Journal.repair_tail(dir, id)
    end

    test "repair preserves a valid final record missing only its newline", %{dir: dir} do
      {:ok, id} = Journal.create(dir, %{})
      File.write!(Path.join(dir, id <> ".jsonl"), "{\"type\":\"valid\"}", [:append])
      assert :ok = Journal.repair_tail(dir, id)
      assert {:ok, [_, %{"type" => "valid"}]} = Journal.load(dir, id)
      assert :ok = Journal.append(dir, id, %{"type" => "next"})
    end
  end

  describe "journal limits" do
    setup do
      root = Path.join(System.tmp_dir!(), "ipse-journal-bounds-#{Ipse.Usage.id()}")
      File.mkdir_p!(root)
      File.chmod!(root, 0o700)
      on_exit(fn -> File.rm_rf!(root) end)
      %{root: root}
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
        assert Journal.valid_limit_receipt?(receipt)
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

    test "oversized legacy files refuse before loading while listing only reads their header",
         c do
      {:ok, id} = Journal.create(c.root, %{"task" => "bounded header"})
      path = Path.join(c.root, id <> ".jsonl")
      header = File.read!(path)
      {:ok, file} = :file.open(String.to_charlist(path), [:read, :write, :raw, :binary])
      {:ok, _} = :file.position(file, Journal.limits()["max_bytes"])
      :ok = :file.write(file, "\n")
      :ok = :file.close(file)
      size = File.stat!(path).size
      assert {:error, :journal_limit_reached} = Journal.load(c.root, id)
      assert {:error, :journal_limit_reached} = Journal.repair_tail(c.root, id)
      assert {:error, :journal_limit_reached} = Writer.start(c.root, id, self())
      assert [%{"id" => ^id, "metadata" => %{"task" => "bounded header"}}] = Journal.list(c.root)

      assert {:ok, %{header: %{"metadata" => %{"task" => "bounded header"}}}} =
               Journal.read_path(path, %{"max_record_bytes" => 512}, :header)

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

      assert {:error, :journal_limit_reached} =
               Journal.read_path(path, %{"max_record_bytes" => 512})

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
      assert {:ok, _} = Ipse.Session.Saved.inspect_saved(c.root, id)
      {:ok, events} = Journal.load(c.root, id)
      refute Enum.any?(events, &(&1["type"] == "operator_answer"))

      assert {:ok, _} =
               Ipse.Session.Saved.export_handoff(
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
      assert {:ok, _} = Ipse.Session.Saved.inspect_saved(c.root, id)

      assert {:ok, _} =
               Ipse.Session.Saved.export_handoff(
                 c.root,
                 id,
                 "Inspect the unknown shell effect before any retry."
               )

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
        assert {:ok, diagnostics} = Ipse.Session.Saved.inspect_saved(root, id)
        assert diagnostics["journal_limit"]["status"] == "sealed"
        assert diagnostics["journal_limit"]["reason"] == "bytes"

        assert {:ok, _} =
                 Ipse.Session.Saved.export_handoff(
                   root,
                   id,
                   "Inspect the preserved refusal before starting a new task."
                 )
      after
        if Process.alive?(session), do: Ipse.Session.close(session)
      end
    end
  end

  describe "inactive journal" do
    setup do
      root = Path.join(System.tmp_dir!(), "ipse-inactive-journal-#{Ipse.Usage.id()}")
      File.mkdir_p!(root)
      File.chmod!(root, 0o700)
      Code.ensure_loaded!(Journal)
      previous_priority = Process.flag(:priority, :high)
      :erlang.trace_pattern({Journal, :encode_event, 2}, true, [:local])

      on_exit(fn ->
        :erlang.trace_pattern({Journal, :encode_event, 2}, false, [:local])
        File.rm_rf!(root)
      end)

      %{root: root, previous_priority: previous_priority}
    end

    test "inactive append cannot release its real lock ahead of a delayed mutation", c do
      try do
        for mode <- [:append, :append_observed, :append_with_source] do
          {:ok, id} = Journal.create(c.root, %{})
          path = Path.join(c.root, id <> ".jsonl")
          lock = Path.join(c.root, id <> ".lock")
          before = File.read!(path)
          parent = self()
          event = %{"type" => "inactive_gate", "items" => List.duplicate(%{"a" => 1}, 60_000)}

          caller =
            spawn(fn ->
              {:ok, port} = Ipse.Runner.lock(lock)
              send(parent, {:lock_ready, self()})
              receive do: (:go -> :ok)
              result = apply(Journal, mode, [c.root, id, event])
              :ok = Ipse.Runner.unlock(port)
              send(parent, {:append_returned, self(), result})
              receive do: (:finish -> :ok)
            end)

          assert_receive {:lock_ready, ^caller}, 5_000
          encoder = gate(caller)

          try do
            assert File.read!(path) == before
            assert {:error, _} = Ipse.Runner.lock(lock)
            refute_receive {:append_returned, ^caller, _}, 10_500
            assert File.read!(path) == before
            assert {:error, _} = Ipse.Runner.lock(lock)
            true = :erlang.resume_process(encoder)
            assert_receive {:append_returned, ^caller, result}, 5_000

            if mode == :append,
              do: assert(result == :ok),
              else: assert(match?({:ok, %{}}, result))

            assert {:ok, [_, ^event]} = Journal.load(c.root, id)
            assert {:ok, next} = Ipse.Runner.lock(lock)
            assert :ok = Ipse.Runner.unlock(next)
          after
            resume(encoder)
            send(caller, :finish)
            if Process.alive?(caller), do: Process.exit(caller, :kill)
          end
        end
      after
        Process.flag(:priority, c.previous_priority)
      end
    end

    test "a tracked inactive append retains its lock after its caller dies", c do
      {:ok, id} = Journal.create(c.root, %{})
      path = Path.join(c.root, id <> ".jsonl")
      lock = Path.join(c.root, id <> ".lock")
      before = File.read!(path)
      parent = self()
      event = %{"type" => "inactive_gate", "items" => List.duplicate(%{"a" => 1}, 60_000)}

      caller =
        spawn(fn ->
          {:ok, _} = Ipse.Session.Lock.acquire(lock)
          send(parent, {:lock_ready, self(), Ipse.Session.Lock.current()})
          receive do: (:go -> :ok)
          Journal.append(c.root, id, event)
        end)

      assert_receive {:lock_ready, ^caller, guard}, 5_000
      encoder = gate(caller)
      guard_monitor = Process.monitor(guard)

      try do
        caller_monitor = Process.monitor(caller)
        Process.exit(caller, :kill)
        assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :killed}, 5_000
        assert Process.alive?(encoder)
        assert File.read!(path) == before
        assert {:error, _} = Ipse.Runner.lock(lock)
        refute_receive {:DOWN, ^guard_monitor, :process, ^guard, _}, 100
        true = :erlang.resume_process(encoder)
        assert_receive {:DOWN, ^guard_monitor, :process, ^guard, :normal}, 5_000
        assert {:ok, [_, ^event]} = Journal.load(c.root, id)
        assert {:ok, next} = Ipse.Runner.lock(lock)
        assert :ok = Ipse.Runner.unlock(next)
      after
        resume(encoder)
        if Process.alive?(caller), do: Process.exit(caller, :kill)
        Process.flag(:priority, c.previous_priority)
      end
    end
  end

  defp gate(caller) do
    :erlang.trace(caller, true, [:call, :set_on_spawn, {:tracer, self()}])
    send(caller, :go)

    receive do
      {:trace, encoder, :call, {Journal, :encode_event, [%{"type" => "inactive_gate"}, _]}} ->
        true = :erlang.suspend_process(encoder)
        encoder
    after
      5_000 -> flunk("Inactive append did not reach the controlled encoding gate")
    end
  end

  defp resume(pid) do
    :erlang.resume_process(pid)
  catch
    :error, :badarg -> :ok
  end
end
