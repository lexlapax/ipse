defmodule Ipse.JournalWriterTest do
  use ExUnit.Case, async: false
  alias Ipse.Journal
  alias Ipse.Journal.Writer

  defmodule WaitingModel do
    def complete(config, _, _, _) do
      send(config.test_pid, {:model_worker, self()})
      Process.sleep(:infinity)
    end
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "ipse-writer-#{Ipse.Usage.id()}")
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp create(c) do
    assert {:ok, id} = Journal.create(c.dir, %{})
    {id, Path.join(c.dir, id <> ".jsonl")}
  end

  test "durable acknowledgments retain exact offsets and optional source refusal still appends",
       c do
    {id, path} = create(c)
    assert {:ok, writer} = Writer.start(c.dir, id, self())
    before = File.stat!(path).size
    first = %{"type" => "first", "text" => "snow 雪"}
    assert {:ok, source} = Writer.append_with_source(writer, first)
    assert source["byte_offset"] == before

    assert {:ok, %{records: [%{source: ^source, record: ^first}]}} =
             Journal.source_page(c.dir, id, before, 1)

    large = %{"type" => "large", "text" => String.duplicate("x", 1_048_577)}
    assert {:ok, nil} = Writer.append_observed(writer, large)
    assert {:error, :journal_record_refused} = Writer.append_with_source(writer, large)
    assert :ok = Writer.append(writer, %{"type" => "last"})
    assert :ok = Writer.close(writer)
    assert {:ok, [_, ^first, ^large, %{"type" => "last"}]} = Journal.load(c.dir, id)
  end

  test "only the owner can append or close the writer", c do
    {id, path} = create(c)
    assert {:ok, writer} = Writer.start(c.dir, id, self())
    before = File.read!(path)

    task =
      Task.async(fn -> {Writer.append(writer, %{"type" => "foreign"}), Writer.close(writer)} end)

    assert {{:error, :journal_owner_or_record_invalid},
            {:error, :journal_owner_or_record_invalid}} = Task.await(task)

    assert File.read!(path) == before
    assert :ok = Writer.close(writer)
  end

  test "opening validates the complete journal rather than extending corrupt or torn history",
       c do
    for bytes <- ["not-json\n", "{\"type\":\"partial\"}", ""] do
      {id, path} = create(c)
      File.write!(path, bytes)
      assert {:error, :journal_unavailable} = Writer.start(c.dir, id, self())
      assert File.read!(path) == bytes
    end
  end

  test "foreign appends, replacement, truncation, symlinks, hardlinks and permissions stop appending",
       c do
    for mutation <- [:append, :replace, :truncate, :symlink, :hardlink, :permissions] do
      {id, path} = create(c)
      assert {:ok, writer} = Writer.start(c.dir, id, self())
      original = File.read!(path)
      target = path <> ".other"

      case mutation do
        :append ->
          File.write!(path, "{\"type\":\"foreign\"}\n", [:append])

        :replace ->
          File.rename!(path, target)
          File.write!(path, original)
          File.chmod!(path, 0o600)

        :truncate ->
          File.write!(path, "")

        :symlink ->
          File.rename!(path, target)
          File.ln_s!(target, path)

        :hardlink ->
          File.ln!(path, target)

        :permissions ->
          File.chmod!(path, 0o644)
      end

      before = File.read!(path)

      assert {:error, :journal_write_unconfirmed} =
               Writer.append(writer, %{"type" => "must-not-append"})

      assert File.read!(path) == before
      if mutation in [:replace, :symlink], do: assert(File.read!(target) == original)
    end
  end

  test "normal owner exit and abrupt owner death close the writer after acknowledged records",
       c do
    for reason <- [:normal, :kill] do
      {id, _path} = create(c)
      parent = self()

      owner =
        spawn(fn ->
          {:ok, writer} = Writer.start(c.dir, id, self())
          :ok = Writer.append(writer, %{"type" => "acknowledged"})
          send(parent, {:writer, writer})

          receive do
            :finish -> :ok
          end
        end)

      assert_receive {:writer, writer}, 5_000
      monitor = Process.monitor(writer)
      if reason == :normal, do: send(owner, :finish), else: Process.exit(owner, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^writer, _}, 5_000
      assert {:ok, [_, %{"type" => "acknowledged"}]} = Journal.load(c.dir, id)
    end
  end

  test "writer loss stops the session and its active provider before any new effects", c do
    config = %{
      provider: :demo,
      model: "fixture",
      provider_module: WaitingModel,
      test_pid: self(),
      home: Path.join(c.dir, "home"),
      approval: :deny
    }

    assert {:ok, session} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session, config: config, cwd: c.dir, state_dir: c.dir, subscriber: self()}
             )

    :ok = Ipse.Session.prompt(session, "Synthetic waiting request")
    assert_receive {:model_worker, worker}, 5_000
    owner_monitor = Process.monitor(session)
    worker_monitor = Process.monitor(worker)
    writer = :sys.get_state(session).journal_writer
    :ok = GenServer.stop(writer, :normal)
    assert_receive {:DOWN, ^owner_monitor, :process, ^session, :journal_unavailable}, 5_000
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _}, 5_000
  end

  test "steady append CPU and retained memory do not scale with 2 versus 64 MiB of history", c do
    record = %{"type" => "padding", "text" => String.duplicate("x", 2000)}
    line = Jason.encode!(record) <> "\n"

    [small, large] =
      for megabytes <- [2, 64] do
        {id, path} = create(c)

        File.write!(path, List.duplicate(line, div(megabytes * 1_048_576, byte_size(line))), [
          :append
        ])

        assert {:ok, writer} = Writer.start(c.dir, id, self())
        assert :ok = Writer.append(writer, record)
        :erlang.garbage_collect(writer)

        samples =
          for _ <- 1..5 do
            {:reductions, before} = Process.info(writer, :reductions)
            assert :ok = Writer.append(writer, record)
            {:reductions, after_count} = Process.info(writer, :reductions)
            after_count - before
          end

        :erlang.garbage_collect(writer)
        {:memory, memory} = Process.info(writer, :memory)
        assert memory < 4_194_304
        assert :ok = Writer.close(writer)
        Enum.at(Enum.sort(samples), 2)
      end

    assert large <= small * 4
  end
end
