defmodule IpseKnowledge.KnowledgeRecallTest do
  use ExUnit.Case, async: false

  @suite ~S"""
  ExUnit.start(autorun: false)
  for path <- ~w(profiles notes knowledge/records knowledge/contracts knowledge),
    do: Code.require_file(Path.join("extensions/knowledge/src", path <> ".ex"))

  defmodule IpseKnowledge.RecallSuite do
    use ExUnit.Case, async: true
    alias IpseKnowledge.Knowledge, as: K

    defp options,
      do: Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})
          |> Map.put("version", 1)

    defp record(number, text) do
      hash = Ipse.JSON.sha256(Integer.to_string(number))
      attrs = %{
        "id" => hash, "lineage" => hash, "text" => text,
        "evidence" => %{"quote" => text, "source" => "synthetic-only"},
        "category" => "ordinary", "reason" => "admitted fixture",
        "observed_at_ms" => 0, "event_at_ms" => nil
      }
      {:ok, note} = IpseKnowledge.Notes.new(attrs, 0)
      %{"key" => "note." <> hash, "revision" => 1, "value" => note}
    end

    defp start do
      {:ok, state} = K.init(options())
      K.handle("event.job", %{
        "id" => "recall", "arguments" => %{"event" => %{
          "event" => %{"view" => "metadata", "type" => "prompt.effective_committed"}
        }}
      }, state)
    end

    defp drive(result, records, opts \\ [], calls \\ [], items \\ [])
    defp drive({:ok, %Ipse.Extension.ResultPublication.Output{bytes: bytes}, state}, _, _, calls, items),
      do: {JSON.decode!(bytes), state, Enum.reverse(calls), items}
    defp drive({:ok, %{"kind" => "result", "value" => value}, state}, _, _, calls, items),
      do: {value, state, Enum.reverse(calls), items}
    defp drive({:ok, %{"kind" => "host_call", "request" => request}, state}, records, opts, calls, items) do
      assert length(calls) < 40
      {outcome, items} = case request do
        %{"op" => "context.publish", "items" => published} ->
          {%{"status" => "ok", "value" => %{}}, published}
        %{"op" => "context.available"} ->
          {%{"status" => "ok", "value" => Ipse.Extension.Context.available(%{}, "knowledge", Ipse.Session.Reference.layout())}, items}
        %{"op" => "collection.call", "request" => %{"op" => "index", "limit" => limit}} ->
          rows = records |> Enum.take(limit) |> Enum.map(&Map.take(&1, ~w(key revision)))
          {%{"status" => "ok", "value" => %{"records" => rows,
            "count" => length(records), "next" => if(length(records) > limit, do: "opaque-next")}}, items}
        %{"op" => "collection.call", "request" => %{"op" => "get", "key" => key}} ->
          if Keyword.get(opts, :unavailable, false),
            do: {%{"status" => "failed", "value" => %{"code" => "collection_source_refused"}}, items},
            else: {%{"status" => "ok", "value" => %{"record" => Enum.find(records, &(&1["key"] == key))}}, items}
      end
      operation = :crypto.hash(:md5, Integer.to_string(length(calls))) |> Base.encode16(case: :lower)
      next = K.handle("host.actions", %{"operation_id" => operation, "outcome" => outcome}, state)
      drive(next, records, opts, [request | calls], items)
    end

    test "small sets publish complete current-read excerpts without a helper or prompt rewrite" do
      records = for n <- 1..3, do: record(n, "complete synthetic note #{n}")
      {result, %{phase: :idle}, calls, items} = drive(start(), records)
      assert result == %{"status" => "recalled", "included" => 3,
        "candidates" => 3, "unavailable" => 0, "coverage" => "complete"}
      assert hd(calls) == %{"op" => "context.publish", "items" => []}
      assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "get")) == 3
      assert Enum.all?(calls, &(&1["op"] in ~w(context.publish context.available collection.call)))
      assert Enum.all?(items, &(get_in(&1, ["source", "kind"]) == "assertion"))
      assert decoded_notes(items) == Map.new(records, &{&1["key"], &1["value"]["text"]})
      assert Ipse.Extension.context_rendered_bytes(items, "knowledge") <= 8192
      assert Ipse.Extension.Context.validate(%{"op" => "context.publish", "items" => items}) == :ok
    end

    test "missing current sources clear old context and disclose unavailable coverage" do
      records = [record(1, "withheld source text")]
      {result, _, calls, items} = drive(start(), records, unavailable: true)
      assert result["included"] == 0
      assert result["unavailable"] == 1
      assert result["coverage"] == "partial"
      assert hd(calls)["items"] == []
      refute JSON.encode!(items) |> IO.iodata_to_binary() |> String.contains?("withheld source text")
      assert Enum.all?(items, &(get_in(&1, ["source", "kind"]) == "assertion"))
    end

    test "large sets bound work, retain whole notes, and disclose explicit paging" do
      records = for n <- 1..80, do: record(n, String.duplicate("complete note #{n} ", 80))
      {result, _, calls, items} = drive(start(), records)
      assert result["coverage"] == "partial"
      assert result["candidates"] == 80
      assert result["included"] in 1..31
      assert length(calls) <= 36
      assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "get")) == 32
      assert Ipse.Extension.context_rendered_bytes(items, "knowledge") <= 8192
      assert Enum.any?(items, &(&1["id"] == "note_index" and &1["text"] =~ "remaining_pages"))
      for {key, text} <- decoded_notes(items),
        do: assert(Enum.any?(records, &(&1["key"] == key and &1["value"]["text"] == text)))
    end

    defp decoded_notes(items) do
      items
      |> Enum.filter(&String.starts_with?(&1["id"], "note_text_"))
      |> Enum.flat_map(&(JSON.decode!(&1["text"])["records"]))
      |> Enum.group_by(&hd/1)
      |> Map.new(fn {key, parts} ->
        {text, expected} = Enum.reduce(parts, {"", 0}, fn [^key, revision, operation, offset, total, text], {joined, expected} ->
          assert revision == 1
          assert byte_size(operation) == 32
          assert offset == expected
          assert total >= offset + byte_size(text)
          {joined <> text, expected + byte_size(text)}
        end)
        assert byte_size(text) == expected
        assert Enum.all?(parts, &(Enum.at(&1, 4) == expected))
        {key, text}
      end)
    end

    test "all32 tiny notes fitting the actual envelope are included without arbitrary item caps" do
      records = for n <- 1..32, do: record(n, "note #{n}")
      {result, _, calls, items} = drive(start(), records)
      assert result["coverage"] == "complete"
      assert result["included"] == 32
      assert length(items) <= 8
      assert length(calls) <= 36
      assert Ipse.Extension.context_rendered_bytes(items, "knowledge") <= 8192
      assert decoded_notes(items) == Map.new(records, &{&1["key"], &1["value"]["text"]})
    end

    test "a full UTF8 note beyond the per-item framing limit is split losslessly with offsets" do
      records = [record(1, String.duplicate("é", 1024))]
      {result, _, _, items} = drive(start(), records)
      assert result["coverage"] == "complete"
      assert result["included"] == 1
      assert decoded_notes(items) == Map.new(records, &{&1["key"], &1["value"]["text"]})
      assert Enum.all?(items, &(byte_size(&1["text"]) <= 2048))
      assert Ipse.Extension.Context.validate(%{"op" => "context.publish", "items" => items}) == :ok
    end

    test "recall only handles its exact metadata-only job and fixed declared surface" do
      {:ok, state} = K.init(options())
      assert {:ok, %{"kind" => "result", "value" => refused}, _} =
        K.handle("event.job", %{"id" => "recall", "arguments" => %{"event" => %{
          "event" => %{"view" => "full", "type" => "prompt.effective_committed"}
        }}}, state)
      assert refused["status"] == "refused"
      description = K.describe()
      assert Enum.map(description["exports"]["tools"], & &1["id"]) == ~w(capture index read search)
      assert description["subscriptions"] |> hd() |> Map.take(~w(view schedule mode)) ==
        %{"view" => "metadata", "schedule" => "before_request", "mode" => "job"}
      refute "host.model" in description["capabilities"]
    end
  end
  result = ExUnit.run()
  if result.failures > 0, do: System.halt(1)
  """

  test "bounded turn-local recall runs in an independent worker VM" do
    sdk = Application.app_dir(:ipse, "ebin")
    paths = Path.wildcard(Path.join(Path.dirname(Path.dirname(sdk)), "*/ebin"))
    args = ["--erl", "+S 2:2"] ++ Enum.flat_map(paths, &["-pa", &1]) ++ ["-e", @suite]
    {output, status} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)
    assert status == 0, output
    assert output =~ "6 passed"
    refute :code.is_loaded(IpseKnowledge.Knowledge)
  end
end
