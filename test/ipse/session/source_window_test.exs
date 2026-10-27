defmodule Ipse.Session.SourceWindowTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal}
  alias Ipse.Session.SourceWindow

  defmodule Model do
    def complete(config, messages, tools, _emit) do
      send(config.test_pid, {:source_request, tools, messages})
      results = Enum.filter(messages, &(&1["role"] == "tool"))
      reads = Enum.count(results, &String.starts_with?(&1["tool_call_id"], "read-"))

      cond do
        config[:scenario] == :hold ->
          send(config.test_pid, {:source_worker, self()})
          Process.sleep(:infinity)

        config[:scenario] == :large ->
          {:ok, %{"role" => "assistant", "content" => String.duplicate("a", 8193)}, %{}}

        reads < 64 ->
          calls =
            for n <- reads..(reads + 31), do: call("read-#{n}", "read", %{"path" => "sample.txt"})

          reply(calls)

        not Enum.any?(results, &(&1["tool_call_id"] == "list")) ->
          reply([call("list", "source_list", %{"limit" => 32})])

        not Enum.any?(results, &(&1["tool_call_id"] == "evidence")) ->
          page =
            results
            |> Enum.find(&(&1["tool_call_id"] == "list"))
            |> Map.fetch!("content")
            |> Jason.decode!()

          row = Enum.find(page["sources"], &(&1["kind"] == "input.original"))
          reply([call("evidence", "source_read", %{"handle" => row["read_handle"]})])

        not Enum.any?(results, &(&1["tool_call_id"] == "quote")) ->
          page =
            results
            |> Enum.find(&(&1["tool_call_id"] == "evidence"))
            |> Map.fetch!("content")
            |> Jason.decode!()

          reply([call("quote", "source_quote", %{"handle" => page["handle"], "quote" => "雪"})])

        true ->
          {:ok,
           %{
             "role" => "assistant",
             "content" => "Visible synthetic answer.",
             "provider_data" => %{"hidden_reasoning" => "never-source-private"}
           }, %{}}
      end
    end

    defp call(id, name, args),
      do: %{
        "id" => id,
        "type" => "function",
        "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
      }

    defp reply(calls),
      do: {:ok, %{"role" => "assistant", "content" => "", "tool_calls" => calls}, %{}}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-source-window-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    File.write!(Path.join(root, "sample.txt"), "Untrusted café tool text 雪.\n")
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, dir: Path.join(root, "state")}
  end

  defp start(c, scenario \\ :read64, id \\ nil) do
    config = %{
      provider: :demo,
      provider_module: Model,
      model: "synthetic",
      test_pid: self(),
      scenario: scenario,
      home: Path.join(c.root, "home"),
      approval: :deny,
      max_steps: 12,
      context_bytes: c[:context_bytes] || 1_000_000,
      compact: false
    }

    {:ok, session} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: c.root, state_dir: c.dir, subscriber: self(), id: id}
      )

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)
    session
  end

  defp list_all(session, cursor \\ nil, acc \\ []) do
    assert {:ok, page} =
             Session.sources(session, "source.list", %{"cursor" => cursor, "limit" => 32})

    assert byte_size(Jason.encode!(page)) <= 4096

    if page["next"],
      do: list_all(session, page["next"], acc ++ page["sources"]),
      else: {page, acc ++ page["sources"]}
  end

  test "64 actual typed receipts remain readable with no extension inline context and replay exactly",
       c do
    session = start(c)
    original = "Original café 雪 repeated repeated"
    assert :ok = Session.prompt(session, original)
    assert_receive {:ipse, ^session, {:done, :ok}}, 10_000
    assert_receive {:source_request, tools, _}

    assert Enum.all?(~w(source_list source_read source_quote), fn name ->
             Enum.any?(tools, &(get_in(&1, ["function", "name"]) == name))
           end)

    assert :sys.get_state(session).extension_contributions == %{}
    {page, rows} = list_all(session)
    assert Enum.count(rows, &(&1["kind"] == "tool.outcome")) == 64
    assert Enum.count(rows, &(&1["kind"] == "tool.content")) == 64
    assert page["window"]["coverage"]["capacity_refused"] == 0
    assert page["window"]["coverage"]["indexed"] == 130

    assert Enum.all?(
             rows,
             &(&1["origin"] in ~w(unattended_input assistant_proposal typed_host_outcome attributed_reference))
           )

    input = Enum.find(rows, &(&1["kind"] == "input.original"))

    assert {:ok, evidence} =
             Session.sources(session, "source.read", %{"handle" => input["read_handle"]})

    assert evidence["text"] == original
    assert byte_size(Jason.encode!(evidence)) <= 8192

    assert {:ok, quote} =
             Session.sources(session, "source.quote", %{
               "handle" => evidence["handle"],
               "quote" => "雪"
             })

    assert quote["start_byte"] == byte_size("Original café ")
    assert quote["end_byte"] == byte_size("Original café 雪")

    assert {:error, _} =
             Session.sources(session, "source.quote", %{
               "handle" => evidence["handle"],
               "quote" => "repeated"
             })

    assert {:error, _} =
             Task.async(fn ->
               Session.sources(session, "source.read", %{"handle" => input["read_handle"]})
             end)
             |> Task.await()

    assert {:error, _} =
             GenServer.call(
               session,
               {:model_sources, make_ref(), "source.read", %{"handle" => input["read_handle"]}}
             )

    id = Session.info(session).id
    assert :ok = Session.close_confirmed(session)
    assert {:ok, events} = Journal.load(c.dir, id)
    assert {:ok, saved} = Session.Saved.restore(events, id)
    assert saved.source_window.coverage["indexed"] == 130

    native_pages =
      for %{
            "type" => "message",
            "message" => %{"role" => "tool", "tool_call_id" => name} = message
          } <- events,
          name in ~w(list evidence quote),
          do: Jason.decode!(message["content"])

    assert length(native_pages) == 3
    refute Enum.any?(rows, &String.contains?(Jason.encode!(&1), "never-source-private"))
    resumed = start(c, :read64, id)

    assert {:error, _} =
             Session.sources(resumed, "source.read", %{"handle" => input["read_handle"]})

    {_, restored_rows} = list_all(resumed)

    assert Enum.map(
             restored_rows,
             &Map.take(&1, ~w(occurrence_id version_id kind origin coverage))
           ) ==
             Enum.map(rows, &Map.take(&1, ~w(occurrence_id version_id kind origin coverage)))

    tampered =
      Enum.map(events, fn
        %{"type" => "message", "message" => %{"tool_call_id" => "evidence"} = m} = e ->
          value = Jason.decode!(m["content"]) |> Map.put("text", "forged source bytes")
          %{e | "message" => %{m | "content" => Jason.encode!(value)}}

        e ->
          e
      end)

    assert {:error, _} = Session.Saved.restore(tampered, id)
  end

  test "large visible answers are unavailable under the retained lifecycle bound", c do
    session = start(c, :large)
    assert :ok = Session.prompt(session, "Synthetic large answer")
    assert_receive {:ipse, ^session, {:done, :ok}}, 2000
    {page, rows} = list_all(session)
    row = Enum.find(rows, &(&1["kind"] == "answer.original"))
    assert row["coverage"] == "unavailable"
    assert page["window"]["coverage"]["unavailable"] == 1

    assert {:ok, evidence} =
             Session.sources(session, "source.read", %{"handle" => row["read_handle"]})

    assert evidence["text"] == ""
    assert evidence["original_bytes"] == 8193

    assert {:error, _} =
             Session.sources(session, "source.quote", %{
               "handle" => row["read_handle"],
               "quote" => "a"
             })
  end

  test "private source queries reject stolen active references and malformed requests", c do
    session = start(c, :hold)
    assert :ok = Session.prompt(session, "Held synthetic request")
    assert_receive {:source_worker, _}, 2000
    state = :sys.get_state(session)

    assert {:error, _} =
             GenServer.call(
               session,
               {:model_sources, state.job_ref, "source.list", %{"limit" => 1}}
             )

    assert {:error, _} =
             Session.sources(session, "source.list", %{
               "limit" => 1,
               "journal_path" => "/tmp/forged"
             })

    assert {:error, _} = Session.sources(session, "source.list", nil)
    assert {:error, _} = Ipse.Journal.Writer.source_query(state.journal_writer, :snapshot)
    assert :ok = Session.cancel(session)

    assert {:error, _} =
             GenServer.call(
               session,
               {:model_sources, state.job_ref, "source.list", %{"limit" => 1}}
             )
  end

  test "changed answer facts reject resume before torn-tail repair", c do
    session = start(c, :large)
    assert :ok = Session.prompt(session, "Original admitted prompt")
    assert_receive {:ipse, ^session, {:done, :ok}}, 2000
    config = :sys.get_state(session).config
    id = Session.info(session).id
    assert :ok = Session.close_confirmed(session)
    assert {:ok, events} = Journal.load(c.dir, id)

    tampered =
      Enum.map(events, fn
        %{"type" => "source_answer_committed"} = event ->
          put_in(event, ["answer", "original_sha256"], Ipse.JSON.sha256("changed original"))

        event ->
          event
      end)

    assert {:error, :invalid_source_window} = Session.Saved.restore(tampered, id)
    bytes = Enum.map_join(tampered, &(Jason.encode!(&1) <> "\n")) <> "{\"torn\":"
    path = Path.join(c.dir, id <> ".jsonl")
    File.write!(path, bytes)

    assert {:error, _} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: config, cwd: c.root, state_dir: c.dir, subscriber: self(), id: id}
             )

    assert File.read!(path) == bytes
  end

  test "bounded pending pairs and legacy roles retain explicit incomplete coverage" do
    id = Ipse.Usage.id()
    assert {:ok, window} = SourceWindow.restore([], id)

    legacy = %{
      "type" => "message",
      "message" => %{"role" => "user", "content" => "legacy is unverified"}
    }

    window = SourceWindow.advance(window, legacy)
    assert window.coverage["legacy_unverified"] == 1
    assert window.coverage["indexed"] == 0
    assert window.coverage["unavailable"] == 1

    window =
      Enum.reduce(1..200, window, fn n, w ->
        SourceWindow.advance(
          w,
          %{
            "type" => "extension_effect_result",
            "operation_id" => "#{n}",
            "text" => String.duplicate("x", 40_000)
          }
        )
      end)

    assert map_size(window.pending) <= 128
    assert window.pending_bytes <= 4_194_304
    assert window.coverage["pending_gaps"] > 0
  end

  test "one MiB admitted original input remains readable and resumable when a Journal source page cannot hold its wrapper",
       c do
    c = Map.put(c, :context_bytes, 2_500_000)
    session = start(c, :large)
    original = String.duplicate("a", 1_048_576)
    assert :ok = Session.prompt(session, original)
    assert_receive {:ipse, ^session, {:done, :ok}}, 5000
    {_, rows} = list_all(session)
    row = Enum.find(rows, &(&1["kind"] == "input.original"))

    assert {:ok, page} =
             Session.sources(session, "source.read", %{"handle" => row["read_handle"]})

    assert page["original_bytes"] == 1_048_576
    assert String.starts_with?(original, page["text"])
    id = Session.info(session).id
    assert :ok = Session.close_confirmed(session)
    resumed = start(c, :large, id)
    {_, restored} = list_all(resumed)

    assert Enum.find(restored, &(&1["kind"] == "input.original"))["version_id"] ==
             row["version_id"]
  end

  test "capacity refusal preserves the admitted prefix and reports the omitted source" do
    id = Ipse.Usage.id()
    {:ok, window} = SourceWindow.restore([], id)
    text = String.duplicate("x", 1_048_576)

    window =
      Enum.reduce(1..9, window, fn _, w ->
        input = Session.Input.received(id, Ipse.Usage.id(), text, text, nil)
        message = %{"type" => "message", "message" => %{"role" => "user", "content" => text}}
        w |> SourceWindow.advance(input) |> SourceWindow.advance(message)
      end)

    assert window.coverage["indexed"] == 8
    assert window.coverage["capacity_refused"] == 1
    assert window.coverage["unavailable"] == 1
    assert window.index.bytes == 8_388_608
    assert {:ok, page} = SourceWindow.execute(window, "source.list", %{"limit" => 32})
    assert byte_size(Jason.encode!(page)) <= 4096
    assert page["window"]["coverage"]["capacity_refused"] == 1
  end
end
