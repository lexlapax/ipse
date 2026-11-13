defmodule IpseKnowledge.KnowledgeRecallTest do
  use ExUnit.Case, async: false

  @suite ~S"""
  ExUnit.start(autorun: false)
  if artifact = System.get_env("IPSE_KNOWLEDGE_RECALL_ARTIFACT") do
    for module <- [IpseKnowledge.Profiles, IpseKnowledge.Notes, IpseKnowledge.Knowledge.Records,
                   IpseKnowledge.Knowledge.Contracts, IpseKnowledge.Knowledge.DecisionPolicy,
                   IpseKnowledge.Knowledge] do
      Code.ensure_loaded!(module)
      true = Path.dirname(to_string(:code.which(module))) == Path.join(Path.expand(artifact), "ebin")
    end
  else
    for path <- ~w(profiles notes knowledge/contracts knowledge/records knowledge/decision_policy knowledge),
      do: Code.require_file(Path.join("extensions/knowledge/src", path <> ".ex"))
  end

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
        "evidence" => %{"sources" => [%{"fixture" => "synthetic-only"}]},
        "category" => "ordinary", "reason" => "admitted fixture",
        "observed_at_ms" => 0, "event_at_ms" => nil
      }
      {:ok, note} = IpseKnowledge.Notes.new(attrs, 0)
      bytes = Ipse.Extension.Collection.Migration.encode(note)
      %{"key" => "note." <> hash, "revision" => 1, "value" => note,
        "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
    end

    defp start do
      {:ok, state} = K.init(options())
      K.handle("event.job", %{
        "id" => "recall", "arguments" => %{"event" => %{
          "event" => %{"view" => "metadata", "type" => "prompt.effective_committed"}
        }}
      }, state)
    end

    defp accepted_record(text) do
      quote = "Original assistant suggestion"
      proof = %{"version" => 1, "session_id" => String.duplicate("1", 32),
        "occurrence_id" => String.duplicate("2", 32), "version_id" => String.duplicate("3", 32),
        "kind" => "answer.original", "origin" => "assistant_proposal", "coverage" => "available",
        "path" => nil, "start_byte" => 0, "end_byte" => byte_size(quote), "quote" => quote,
        "quote_sha256" => Ipse.JSON.sha256(quote), "content_sha256" => Ipse.JSON.sha256(quote),
        "receipt_sha256" => Ipse.JSON.sha256("synthetic recorded proof")}
      attrs = %{"text" => text, "category" => "ordinary", "reason" => "selected decision", "event_at_ms" => nil}
      {:ok, _, pending} = IpseKnowledge.Knowledge.Records.capture(attrs, proof, 0)
      {:ok, lineage} = Ipse.Extension.canonical_digest(["ipse-knowledge", 1, "accepted_decision", pending["id"], pending["lineage"]])
      value = %{"version" => 1, "kind" => "accepted_decision", "lineage" => lineage,
        "candidate_id" => pending["id"], "text" => text, "category" => "ordinary",
        "reason" => "selected decision", "source_proof" => proof,
        "acceptance_event_sha256" => Ipse.JSON.sha256("synthetic event claim"),
        "acceptance_link_sha256" => Ipse.JSON.sha256("synthetic link claim"),
        "accepted_at_ms" => 1, "valid_until_ms" => 100_000}
      bytes = Ipse.Extension.Collection.Migration.encode(value)
      %{"key" => "note." <> lineage, "revision" => 1, "value" => value,
        "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
    end

    defp drive(result, records, opts \\ [], calls \\ [], items \\ [])
    defp drive({:ok, %Ipse.Extension.ResultPublication.Output{bytes: bytes}, state}, _, _, calls, items),
      do: {JSON.decode!(bytes), state, Enum.reverse(calls), items}
    defp drive({:ok, %{"kind" => "result", "value" => value}, state}, _, _, calls, items),
      do: {value, state, Enum.reverse(calls), items}
    defp drive({:ok, %{"kind" => "host_call", "request" => request}, state}, records, opts, calls, items) do
      assert length(calls) < 600
      {outcome, items} = case request do
        %{"op" => "context.publish", "items" => published} ->
          if Keyword.get(opts, :capture_projection_context, false) and state.phase == :recall_published,
            do: Process.put(:recall_projection_context, state.ctx)
          {%{"status" => "ok", "value" => %{}}, published}
        %{"op" => "context.available"} ->
          budget=Ipse.Extension.Context.available(%{}, "knowledge", Ipse.Session.Reference.layout())
          budget=if Keyword.has_key?(opts,:available_bytes), do: Map.put(budget,"available_bytes",opts[:available_bytes]), else: budget
          {%{"status" => "ok", "value" => budget}, items}
        %{"op" => "collection.call", "request" => %{"op" => "index", "limit" => limit, "cursor" => cursor}} ->
          if (state.phase == :recall_verify and Keyword.get(opts, :fail_verify, false)) or
               (Keyword.has_key?(opts, :fail_index_cursor) and cursor == opts[:fail_index_cursor]) do
            {%{"status" => "failed", "value" => %{"code" => "collection_source_refused"}}, items}
          else
            offset = if Keyword.has_key?(opts, :page_size) and is_binary(cursor), do: String.to_integer(String.replace_prefix(cursor, "page:", "")), else: 0
            page_size = min(limit, Keyword.get(opts, :page_size, limit))
            rows = records |> Enum.drop(offset) |> Enum.take(page_size) |> Enum.map(&Map.take(&1, ~w(key revision bytes sha256)))
            next_offset = offset + length(rows)
            next = if next_offset < length(records), do: if(Keyword.has_key?(opts, :page_size), do: "page:#{next_offset}", else: "opaque-next")
            {%{"status" => "ok", "value" => %{"records" => rows,
              "generation" => cond do
                state.phase == :recall_verify -> Keyword.get(opts, :verify_generation, 1)
                Keyword.has_key?(opts, :changed_index_cursor) and cursor == opts[:changed_index_cursor] -> 2
                true -> 1
              end, "count" => length(records), "next" => next}}, items}
          end
        %{"op" => "collection.call", "request" => %{"op" => "get", "key" => key}} ->
          cond do
            key in Keyword.get(opts, :denied_keys, []) ->
              {%{"status" => "failed", "value" => %{"code" => "collection_consent_denied"}}, items}
            key in Keyword.get(opts, :refused_keys, []) ->
              {%{"status" => "failed", "value" => %{"code" => "collection_source_refused"}}, items}
            key in Keyword.get(opts, :expired_keys, []) ->
              {%{"status" => "failed", "value" => %{"code" => "collection_record_expired"}}, items}
            Keyword.get(opts, :unavailable, false) or key in Keyword.get(opts, :unavailable_keys, []) ->
              {%{"status" => "failed", "value" => %{"code" => "collection_original_source_missing"}}, items}
            true ->
              {%{"status" => "ok", "value" => %{"generation" => if(key in Keyword.get(opts, :changed_generation_keys, []), do: 2, else: 1), "record" =>
              Enum.find(records, &(&1["key"] == key))
              |> then(fn row -> if key in Keyword.get(opts, :changed_keys, []), do: Map.update!(row, "revision", &(&1 + 1)), else: row end)
              |> then(fn row -> if replacement = opts[:replacement], do: if(key == replacement["key"], do: replacement, else: row), else: row end)}}, items}
          end
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

    test "mixed recall labels accepted decisions separately and preserves complete UTF8 spans" do
      records = [record(1, "literal reference"), accepted_record(String.duplicate("café 日本語 ", 125))]
      {result, _, _, items} = drive(start(), records)
      assert result["included"] == 2 and result["coverage"] == "complete"
      groups = items |> Enum.filter(&String.starts_with?(&1["id"], "note_text_")) |> Enum.map(&JSON.decode!(&1["text"]))
      assert Enum.all?(groups, &(&1["format"] == "note_parts_v2"))
      parts = Enum.flat_map(groups, fn group -> Enum.map(group["records"], &Map.new(Enum.zip(group["fields"], &1))) end)
      for record <- records do
        selected = Enum.filter(parts, &(&1["key"] == record["key"]))
        kind = if record["value"]["kind"] == "accepted_decision", do: "accepted_decision", else: "literal_claim"
        {text, offset} = Enum.reduce(selected, {"", 0}, fn part, {text, offset} ->
          assert part["claim_kind"] == kind
          assert part["offset_bytes"] == offset
          assert part["total_bytes"] == byte_size(record["value"]["text"])
          assert String.valid?(part["text"])
          {text <> part["text"], offset + byte_size(part["text"])}
        end)
        assert text == record["value"]["text"] and offset == byte_size(text)
      end
      coverage = items |> Enum.find(&(&1["id"] == "note_coverage")) |> Map.fetch!("text") |> JSON.decode!()
      assert coverage["accepted_decisions"] =~ "unverified claims"
      assert Ipse.Extension.context_rendered_bytes(items, "knowledge") <= 8192
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

    @tag :typed_expiry
    test "known expiry skips to a live neighbor but preserves bounds and final generation checks" do
      records = for n <- 1..34, do: record(n, "synthetic eligible neighbor #{n}")
      expired = records |> Enum.take(33) |> Enum.map(& &1["key"])
      live = List.last(records)
      {result, _, calls, items} = drive(start(), records, expired_keys: expired, page_size: 32)
      assert result["coverage"] == "partial" and result["unavailable"] == 33
      assert result["included"] == 1 and decoded_notes(items) == %{live["key"] => live["value"]["text"]}
      assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "get")) == 34
      assert length(calls) < 512
      assert List.last(Enum.filter(calls, &(get_in(&1, ["request", "op"]) == "index")))["request"]["limit"] == 1

      {changed, _, _, changed_items} = drive(start(), records, expired_keys: expired,
        page_size: 32, verify_generation: 2)
      assert changed["coverage"] == "unavailable" and changed["included"] == 0
      refute Map.has_key?(decoded_notes(changed_items), live["key"])

      for opts <- [[denied_keys: [hd(records)["key"]]], [refused_keys: [hd(records)["key"]]]] do
        {failed, _, failed_calls, failed_items} = drive(start(), records, opts)
        assert failed["coverage"] == "unavailable" and failed["included"] == 0
        assert Enum.count(failed_calls, &(get_in(&1, ["request", "op"]) == "get")) == 1
        assert decoded_notes(failed_items) == %{}
      end
    end

    test "search coverage is partial when any indexed record is unavailable or pages remain" do
      {:ok, state} = K.init(options())
      search = fn -> K.handle("invoke.tool", %{"id" => "search", "arguments" => %{"query" => "note", "cursor" => nil}}, state) end
      records = [record(1, "note one"), record(2, "note two")]
      {complete, _, _, _} = drive(search.(), records)
      assert complete["coverage"] == "complete" and length(complete["records"]) == 2
      {unavailable, _, _, _} = drive(search.(), records, unavailable: true)
      assert unavailable["coverage"] == "partial" and unavailable["unavailable"] == 2
      assert unavailable["records"] == []
      {mixed, _, _, _} = drive(search.(), records, unavailable_keys: [hd(records)["key"]])
      assert mixed["coverage"] == "partial" and mixed["unavailable"] == 1
      assert Enum.map(mixed["records"], & &1["key"]) == [List.last(records)["key"]]
      {paged, _, _, _} = drive(search.(), for(n <- 1..40, do: record(n, "note #{n}")))
      assert paged["coverage"] == "partial" and paged["next"] == "opaque-next"

      later = K.handle("invoke.tool", %{"id" => "search", "arguments" => %{"query" => "note", "cursor" => "prior-page"}}, state)
      {last_page, _, calls, _} = drive(later, records)
      assert get_in(hd(calls), ["request", "cursor"]) == "prior-page"
      assert last_page["next"] == nil
      assert length(last_page["records"]) == 2
      assert last_page["coverage"] == "partial"

      for query <- [" ", "?!", "… —", "___"] do
        empty = K.handle("invoke.tool", %{"id" => "search", "arguments" => %{"query" => query, "cursor" => nil}}, state)
        {result, _, calls, _} = drive(empty, records)
        assert result == %{"status" => "refused", "code" => "invalid_search"}
        assert calls == []
      end

      accented = [record(3, "Café release"), record(4, "other note")]
      query = K.handle("invoke.tool", %{"id" => "search", "arguments" => %{"query" => "CAFÉ", "cursor" => nil}}, state)
      {matched, _, _, _} = drive(query, accented)
      assert Enum.map(matched["records"], & &1["key"]) == [hd(accented)["key"]]

      identifier = [record(5, "release_plan approved"), record(6, "release plan approved")]
      query = K.handle("invoke.tool", %{"id" => "search", "arguments" => %{"query" => "release_plan ___", "cursor" => nil}}, state)
      {matched, _, _, _} = drive(query, identifier)
      assert Enum.map(matched["records"], & &1["key"]) == [hd(identifier)["key"]]
    end

    test "small context budgets publish no oversized framing or notes" do
      records = [record(1, "synthetic note")]
      for available <- [0,1,128] do
        {result, _, calls, items} = drive(start(), records, available_bytes: available)
        assert result["included"] == 0 and result["coverage"] == "partial"
        assert items == []
        assert List.last(calls) == %{"op" => "context.publish", "items" => []}
        if available == 0 do
          assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "get")) == 0
          drive(start(), records, available_bytes: 8192, capture_projection_context: true)
          ctx = Process.delete(:recall_projection_context)
          assert {:ok, facts, binding} = K.recall_decision_facts(ctx, [], "knowledge", available, "query", true, nil)
          policy = IpseKnowledge.Knowledge.DecisionPolicy.default("notes.select")
          assert {:ok, plan} = IpseKnowledge.Knowledge.DecisionPolicy.plan(policy, facts, :development_experiment)
          assert {:ok, comparison} = K.recall_shadow_comparison(ctx, plan, binding, nil, "knowledge")
          assert comparison.ordinary == %{items: [], coverage: "partial", included: 0}
          assert comparison.shadow == nil and comparison.outcome["receipt"]["reason"] == "strategy_none"
        end
      end
    end

    test "zero allocation skips protected values and still verifies the root" do
      records = for n <- 1..80, do: record(n, "synthetic note #{n}")
      {result, _, calls, items} = drive(start(), records, page_size: 32, available_bytes: 0)
      assert result["coverage"] == "partial" and result["included"] == 0
      assert items == []
      assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "get")) == 0
      assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "index")) == 2

      {changed, _, _, changed_items} =
        drive(start(), records, page_size: 32, available_bytes: 0, verify_generation: 2)
      assert changed["coverage"] == "unavailable" and changed["included"] == 0
      assert changed_items == []
    end

    test "allocations below the host-framed note lower bound skip protected values" do
      item = %{
        "id" => "note_text_0", "version" => "1", "text" => "", "priority" => 70,
        "source" => %{"kind" => "assertion", "uri" => nil}
      }
      minimum = Ipse.Extension.context_rendered_bytes([item], "knowledge")
      assert minimum > 1
      records = [record(1, "synthetic note")]

      for available <- [1, minimum - 1] do
        {result, _, calls, items} = drive(start(), records, available_bytes: available)
        assert result["coverage"] == "partial" and result["included"] == 0
        assert items == []
        assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "get")) == 0
        assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "index")) == 2
      end

      {_, _, calls, _} = drive(start(), records, available_bytes: minimum)
      assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "get")) == 1
    end

    test "index continuation must advance and contain records" do
      {:ok, state} = K.init(options())
      start = fn cursor ->
        K.handle("invoke.tool", %{"id" => "search", "arguments" => %{"query" => "note", "cursor" => cursor}}, state)
      end
      reply = fn continuation, rows, next ->
        {:ok, %{"kind" => "host_call"}, current} = continuation
        K.handle("host.actions", %{"operation_id" => "synthetic", "outcome" => %{
          "status" => "ok", "value" => %{"records" => rows, "generation" => 1, "count" => 4, "next" => next}
        }}, current)
      end
      row = %{"key" => record(1, "note")["key"], "revision" => 1}
      assert {%{"status" => "refused", "code" => "invalid_index_progress"}, _, _, _} =
        drive(reply.(start.(nil), [row], nil), [])
      assert {%{"coverage" => "partial", "records" => [], "candidates" => 4}, _, [_], _} =
        drive(reply.(start.("earlier"), [], nil), for(n <- 1..4, do: record(n, "note")))
      assert {%{"status" => "refused", "code" => "invalid_index_progress"}, _, _, _} =
        drive(reply.(start.(nil), [], "cursor-a"), [])
      assert {%{"status" => "refused", "code" => "invalid_index_progress"}, _, _, _} =
        drive(reply.(start.("cursor-a"), [row], "cursor-a"), [])
      first = reply.(start.(nil), [row], "cursor-a")
      {:ok, %{"kind" => "host_call"}, first_state} = first
      changed_total = K.handle("host.actions", %{"operation_id" => "synthetic", "outcome" => %{
        "status" => "ok", "value" => %{"records" => [%{"key" => record(2, "note")["key"], "revision" => 1}], "generation" => 1, "count" => 5, "next" => "cursor-b"}
      }}, first_state)
      assert {%{"status" => "refused", "code" => "invalid_index_progress"}, _, _, _} = drive(changed_total, [])
      assert {%{"status" => "refused", "code" => "invalid_index_progress"}, _, _, _} =
        drive(reply.(first, [row], "cursor-b"), [])
      second = reply.(first, [%{"key" => record(2, "note")["key"], "revision" => 1}], "cursor-b")
      assert {%{"status" => "refused", "code" => "invalid_index_progress"}, _, _, _} =
        drive(reply.(second, [%{"key" => record(3, "note")["key"], "revision" => 1}], "cursor-a"), [])

      {:ok, %{"kind" => "host_call", "request" => %{"op" => "context.publish", "items" => []}}, seed} = start()
      {:ok, %{"kind" => "host_call"}, seed} = K.handle("host.actions", %{"operation_id" => "clear", "outcome" => %{"status" => "ok", "value" => %{}}}, seed)
      budget = Ipse.Extension.Context.available(%{}, "knowledge", Ipse.Session.Reference.layout())
      index = K.handle("host.actions", %{"operation_id" => "budget", "outcome" => %{"status" => "ok", "value" => budget}}, seed)
      assert {%{"status" => "refused", "code" => "invalid_index_progress"}, _, [], _} =
        drive(reply.(index, [], "cursor-a"), [])
    end

    test "valid short index pages produce complete recall and search" do
      records = for n <- 1..5, do: record(n, "note #{n}")
      {recalled, _, recall_calls, items} = drive(start(), records, page_size: 2)
      assert recalled["coverage"] == "complete" and recalled["included"] == 5
      assert decoded_notes(items) == Map.new(records, &{&1["key"], &1["value"]["text"]})
      assert Enum.map(Enum.filter(recall_calls, &(get_in(&1, ["request", "op"]) == "index")), &get_in(&1, ["request", "cursor"])) == [nil, "page:2", "page:4", nil]

      {:ok, state} = K.init(options())
      search = K.handle("invoke.tool", %{"id" => "search", "arguments" => %{"query" => "note", "cursor" => nil}}, state)
      {result, _, _, _} = drive(search, records, page_size: 2)
      assert result["coverage"] == "complete" and length(result["records"]) == 5
    end

    test "failed later index page publishes unavailable coverage without stale metadata" do
      records = for n <- 1..5, do: record(n, "note #{n}")
      {result, _, calls, items} = drive(start(), records, page_size: 2, fail_index_cursor: "page:2")
      assert result["coverage"] == "unavailable" and result["candidates"] == nil
      assert result["included"] == 0
      assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "index")) == 2
      assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "get")) == 2
      assert hd(calls) == %{"op" => "context.publish", "items" => []}
      index = Enum.find(items, &(&1["id"] == "note_index")) |> Map.fetch!("text") |> JSON.decode!()
      assert index["keys"] == [] and index["candidates"] == nil
      refute Enum.any?(records, &(String.contains?(JSON.encode!(items) |> IO.iodata_to_binary(), &1["key"])))
    end

    test "host Collection cursors drive a complete multi-page search" do
      {:ok, _} = Application.ensure_all_started(:ipse)
      home = Path.join(System.tmp_dir!(), "ipse-recall-real-index-" <> Ipse.Usage.id())
      File.mkdir!(home)
      File.chmod!(home, 0o700)
      on_exit(fn -> File.rm_rf!(home) end)
      root = Ipse.Extension.SemanticAdmission.collection_root(home)
      assert {:ok, _} = Ipse.Runner.protected_helper(home)
      namespace = Ipse.JSON.sha256("recall real index fixture")
      records = for n <- 1..32, do: record(n, "note #{n}")
      changes = for row <- records, do: %{"key" => row["key"], "expected_revision" => 0, "value" => row["value"]}
      assert {:ok, _} = Ipse.Extension.Collection.execute(root, namespace, %{
        "op" => "commit", "expected_generation" => 0, "advance_floor" => false, "changes" => changes
      }, Ipse.Usage.id())
      context = %{config: %{home: home}, session_id: Ipse.Usage.id(),
        index_scope: %{secret: :crypto.strong_rand_bytes(32), window: Ipse.Usage.id(), generation: 1}}
      {:ok, state} = K.init(options())
      initial = K.handle("invoke.tool", %{"id" => "search", "arguments" => %{"query" => "note", "cursor" => nil}}, state)
      walk = fn walk, result, cursors, mutate ->
        case result do
          {:ok, %Ipse.Extension.ResultPublication.Output{bytes: bytes}, _} -> {JSON.decode!(bytes), Enum.reverse(cursors)}
          {:ok, %{"kind" => "result", "value" => value}, _} -> {value, Enum.reverse(cursors)}
          {:ok, %{"kind" => "host_call", "request" => %{"op" => "context.publish", "items" => items}}, current} ->
            Process.put(:real_index_publications, Process.get(:real_index_publications, []) ++ [items])
            if current.phase == :recall_published, do: Process.put(:real_recall_context, current.ctx)
            next = K.handle("host.actions", %{"operation_id" => Ipse.Usage.id(), "outcome" => %{"status" => "ok", "value" => %{}}}, current)
            walk.(walk, next, cursors, mutate)
          {:ok, %{"kind" => "host_call", "request" => %{"op" => "context.available"}}, current} ->
            budget = Ipse.Extension.Context.available(%{}, "knowledge", Ipse.Session.Reference.layout())
            next = K.handle("host.actions", %{"operation_id" => Ipse.Usage.id(), "outcome" => %{"status" => "ok", "value" => budget}}, current)
            walk.(walk, next, cursors, mutate)
          {:ok, %{"kind" => "host_call", "request" => %{"op" => "collection.call", "request" => request} = outer}, current} ->
            {outcome, cursors} =
              case request["op"] do
                "index" ->
                  intent = %{"request" => outer, "namespace" => namespace, "effect_binding" => %{"pin" => %{"synthetic" => true}}}
                  outcome = case Ipse.Extension.CollectionCall.index_observation(context, intent) do
                    {:ok, observation} ->
                      if mutate != nil and is_nil(request["cursor"]) do
                        assert is_binary(observation["value"]["next"])
                        {generation, number} = mutate
                        extra = record(number, "note added after indexing")
                        assert {:ok, _} = Ipse.Extension.Collection.execute(root, namespace, %{
                          "op" => "commit", "expected_generation" => generation, "advance_floor" => false,
                          "changes" => [%{"key" => extra["key"], "expected_revision" => 0, "value" => extra["value"]}]
                        }, Ipse.Usage.id())
                      end
                      %{"status" => "ok", "value" => observation["value"]}
                    {:error, :collection_source_refused} ->
                      %{"status" => "failed", "value" => %{"code" => "collection_source_refused"}}
                  end
                  {outcome, [request["cursor"] | cursors]}
                "get" ->
                  assert {:ok, observation} = Ipse.Extension.Collection.ObservedRead.read(root, namespace, request)
                  {%{"status" => "ok", "value" => observation["value"]}, cursors}
              end
            next = K.handle("host.actions", %{"operation_id" => Ipse.Usage.id(), "outcome" => outcome}, current)
            walk.(walk, next, cursors, mutate)
        end
      end
      {result, cursors} = walk.(walk, initial, [], nil)
      assert length(cursors) > 1 and hd(cursors) == nil
      assert List.last(cursors) == nil and Enum.all?(cursors |> tl() |> Enum.drop(-1), &is_binary/1)
      assert result["coverage"] == "complete" and result["candidates"] == 32
      assert MapSet.new(Enum.map(result["records"], & &1["key"])) == MapSet.new(Enum.map(records, & &1["key"]))
      {recalled, _} = walk.(walk, start(), [], nil)
      assert recalled["coverage"] == "complete"
      ctx = Process.delete(:real_recall_context)
      assert ctx.verified and length(ctx.notes) == 32
      [first, second | _] = Enum.map(ctx.notes, fn {row, _} -> row["key"] end)
      packs = [%{"id" => "first", "members" => [first]}, %{"id" => "second", "members" => [second]}]
      assert {:ok, measured} = K.recall_pack_projections(ctx, packs, "knowledge", 6144)
      budget = Enum.max(Enum.map(measured, & &1.projection.rendered_bytes)) + 20
      assert {:ok, facts, binding} = K.recall_decision_facts(ctx, packs, "knowledge", budget, "note", true, "first")
      policy = IpseKnowledge.Knowledge.DecisionPolicy.default("notes.select") |> Map.merge(%{"strategy" => "decision", "profile" => "fixture"})
      assert {:ok, plan} = IpseKnowledge.Knowledge.DecisionPolicy.plan(policy, facts, :development_experiment)
      assert plan.request != nil
      advice = %{"version" => 1, "answers" => [%{"id" => "pack", "type" => "choice", "choice" => "second", "confidence" => 0.1,
        "probabilities" => [%{"id" => "first", "probability" => 0.1}, %{"id" => "second", "probability" => 0.9}]}]}
      assert {:ok, %{projection: %{fits: true}}} = K.recall_decision_projection(ctx, plan, binding, advice, "knowledge")
      {interrupted, interrupted_cursors} = walk.(walk, initial, [], {1, 99})
      assert length(interrupted_cursors) == 2
      assert interrupted["status"] == "interrupted"
      assert get_in(interrupted, ["outcome", "value", "code"]) == "collection_source_refused"
      refute Map.has_key?(interrupted, "records")
      # This pure helper sees only its retained input; the real collection is
      # now generation 2. Host freshness must be checked separately.
      current_index = %{"op" => "collection.call", "request" => %{"op" => "index", "prefix" => "note.", "cursor" => nil, "limit" => 1}}
      current_intent = %{"request" => current_index, "namespace" => namespace, "effect_binding" => %{"pin" => %{"synthetic" => true}}}
      assert {:ok, %{"value" => %{"generation" => 2}}} = Ipse.Extension.CollectionCall.index_observation(context, current_intent)
      assert {:ok, %{projection: %{fits: true}}} = K.recall_decision_projection(ctx, plan, binding, advice, "knowledge")
      Process.put(:real_index_publications, [])
      {unavailable, recall_cursors} = walk.(walk, start(), [], {2, 100})
      assert length(recall_cursors) == 1
      assert unavailable["coverage"] == "unavailable" and unavailable["candidates"] == nil
      assert [[], published] = Process.get(:real_index_publications)
      index = Enum.find(published, &(&1["id"] == "note_index")) |> Map.fetch!("text") |> JSON.decode!()
      assert index["keys"] == [] and index["candidates"] == nil
      refute Enum.any?(records, &(String.contains?(JSON.encode!(published) |> IO.iodata_to_binary(), &1["key"])))
    end

    test "final generation check withholds notes and an empty index after a change" do
      for records <- [[], [record(1, "secret note")]] do
        {result, _, calls, items} = drive(start(), records, verify_generation: 2)
        assert result["coverage"] == "unavailable" and result["included"] == 0
        assert result["candidates"] == nil
        assert List.last(Enum.filter(calls, &(get_in(&1, ["request", "op"]) == "index")))["request"]["limit"] == 1
        refute String.contains?(IO.iodata_to_binary(JSON.encode!(items)), "secret note")
      end
      {failed, _, _, items} = drive(start(), [record(1, "secret note")], fail_verify: true)
      assert failed["coverage"] == "unavailable" and failed["included"] == 0
      refute String.contains?(IO.iodata_to_binary(JSON.encode!(items)), "secret note")
    end

    test "native collection change after a single index page withholds search" do
      {:ok, _} = Application.ensure_all_started(:ipse)
      home = Path.join(System.tmp_dir!(), "ipse-recall-generation-" <> Ipse.Usage.id())
      File.mkdir!(home)
      File.chmod!(home, 0o700)
      on_exit(fn -> File.rm_rf!(home) end)
      root = Ipse.Extension.SemanticAdmission.collection_root(home)
      namespace = Ipse.JSON.sha256("recall generation fixture")
      first = record(1, "original note")
      put = fn generation, row ->
        Ipse.Extension.Collection.execute(root, namespace, %{
          "op" => "commit", "expected_generation" => generation, "advance_floor" => false,
          "changes" => [%{"key" => row["key"], "expected_revision" => 0, "value" => row["value"]}]
        }, Ipse.Usage.id())
      end
      assert {:ok, _} = put.(0, first)
      context = %{config: %{home: home}, session_id: Ipse.Usage.id(),
        index_scope: %{secret: :crypto.strong_rand_bytes(32), window: Ipse.Usage.id(), generation: 1}}
      {:ok, state} = K.init(options())
      {:ok, %{"request" => outer}, state} = K.handle("invoke.tool", %{
        "id" => "search", "arguments" => %{"query" => "note", "cursor" => nil}}, state)
      intent = %{"request" => outer, "namespace" => namespace, "effect_binding" => %{"pin" => %{"synthetic" => true}}}
      assert {:ok, index} = Ipse.Extension.CollectionCall.index_observation(context, intent)
      assert index["value"]["next"] == nil
      assert {:ok, _} = put.(1, record(2, "new note"))
      {:ok, %{"request" => %{"request" => get}}, state} = K.handle("host.actions", %{
        "operation_id" => Ipse.Usage.id(), "outcome" => %{"status" => "ok", "value" => index["value"]}}, state)
      assert {:ok, observed} = Ipse.Extension.Collection.ObservedRead.read(root, namespace, get)
      response = K.handle("host.actions", %{"operation_id" => Ipse.Usage.id(),
        "outcome" => %{"status" => "ok", "value" => observed["value"]}}, state)
      {result, _, _, _} = drive(response, [])
      assert result["coverage"] == "unavailable" and result["records"] == []
      assert result["candidates"] == nil and result["next"] == nil

      {:ok, state} = K.init(options())
      {:ok, %{"request" => outer}, state} = K.handle("invoke.tool", %{
        "id" => "search", "arguments" => %{"query" => "note", "cursor" => nil}}, state)
      intent = %{intent | "request" => outer}
      assert {:ok, current_index} = Ipse.Extension.CollectionCall.index_observation(context, intent)
      next = K.handle("host.actions", %{"operation_id" => Ipse.Usage.id(),
        "outcome" => %{"status" => "ok", "value" => current_index["value"]}}, state)
      verify = Enum.reduce(1..2, next, fn _, {:ok, %{"request" => %{"request" => get}}, current} ->
        assert {:ok, read} = Ipse.Extension.Collection.ObservedRead.read(root, namespace, get)
        K.handle("host.actions", %{"operation_id" => Ipse.Usage.id(),
          "outcome" => %{"status" => "ok", "value" => read["value"]}}, current)
      end)
      assert {:ok, %{"request" => verify_outer}, verify_state} = verify
      assert verify_outer["request"]["op"] == "index" and verify_outer["request"]["limit"] == 1
      assert {:ok, _} = put.(2, record(3, "later note"))
      assert {:ok, latest} = Ipse.Extension.CollectionCall.index_observation(context, %{intent | "request" => verify_outer})
      response = K.handle("host.actions", %{"operation_id" => Ipse.Usage.id(),
        "outcome" => %{"status" => "ok", "value" => latest["value"]}}, verify_state)
      {result, _, _, _} = drive(response, [])
      assert result["coverage"] == "unavailable" and result["records"] == []
      assert result["candidates"] == nil and result["next"] == nil
    end

    test "a changed collection generation withholds earlier recall and search records" do
      records = [record(1, "first secret note"), record(2, "second secret note")]
      changed = List.last(records)["key"]
      {recall, _, _, items} = drive(start(), records, changed_generation_keys: [changed])
      assert recall["coverage"] == "unavailable" and recall["included"] == 0
      assert recall["candidates"] == nil
      refute Enum.any?(records, &(String.contains?(IO.iodata_to_binary(JSON.encode!(items)), &1["key"])))
      refute String.contains?(IO.iodata_to_binary(JSON.encode!(items)), "secret note")

      {:ok, state} = K.init(options())
      search = K.handle("invoke.tool", %{"id" => "search", "arguments" => %{"query" => "note", "cursor" => nil}}, state)
      {result, _, _, _} = drive(search, records, changed_generation_keys: [changed])
      assert result["coverage"] == "unavailable" and result["records"] == []
      assert result["candidates"] == nil and result["next"] == nil
    end

    test "a record replaced after indexing is excluded and makes recall and search partial" do
      records = [record(1, "note one"), record(2, "note two")]
      changed = hd(records)["key"]
      {recall, _, _, items} = drive(start(), records, changed_keys: [changed])
      assert recall["coverage"] == "partial" and recall["unavailable"] == 1
      assert Map.keys(decoded_notes(items)) == [List.last(records)["key"]]
      {:ok, state} = K.init(options())
      search = K.handle("invoke.tool", %{"id" => "search", "arguments" => %{"query" => "note", "cursor" => nil}}, state)
      {result, _, _, _} = drive(search, records, changed_keys: [changed])
      assert result["coverage"] == "partial" and result["unavailable"] == 1
      assert Enum.map(result["records"], & &1["key"]) == [List.last(records)["key"]]
    end

    test "same-revision content mismatch is excluded from recall and search" do
      records = [record(1, "note original"), record(2, "note unchanged")]
      replacement = record(1, "note inconsistent replacement")
      assert replacement["revision"] == hd(records)["revision"]
      refute replacement["sha256"] == hd(records)["sha256"]
      for inconsistent <- [replacement, Map.update!(hd(records), "bytes", &(&1 + 1))] do
        {recall, _, _, items} = drive(start(), records, replacement: inconsistent)
        assert recall["coverage"] == "partial" and recall["unavailable"] == 1
        assert Map.keys(decoded_notes(items)) == [List.last(records)["key"]]
        {:ok, state} = K.init(options())
        search = K.handle("invoke.tool", %{"id" => "search", "arguments" => %{"query" => "note", "cursor" => nil}}, state)
        {result, _, _, _} = drive(search, records, replacement: inconsistent)
        assert result["coverage"] == "partial" and result["unavailable"] == 1
        assert Enum.map(result["records"], & &1["key"]) == [List.last(records)["key"]]
      end
    end

    test "large sets bound work, retain whole notes, and disclose explicit paging" do
      records = for n <- 1..80, do: record(n, String.duplicate("complete note #{n} ", 80))
      {result, _, calls, items} = drive(start(), records, page_size: 32)
      assert result["coverage"] == "partial"
      assert result["candidates"] == 80
      assert result["included"] in 1..31
      assert length(calls) == 66
      assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "get")) == 60
      assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "index")) == 3
      assert Ipse.Extension.context_rendered_bytes(items, "knowledge") <= 8192
      assert Enum.any?(items, &(&1["id"] == "note_index" and &1["text"] =~ "remaining_pages"))
      for {key, text} <- decoded_notes(items),
        do: assert(Enum.any?(records, &(&1["key"] == key and &1["value"]["text"] == text)))
    end

    test "a later small note is considered after an over-budget first page" do
      later_number = Enum.max_by(1..33, &Ipse.JSON.sha256(Integer.to_string(&1)))
      records =
        for n <- 1..33 do
          record(n, if(n == later_number, do: "later fitting note", else: String.duplicate("x", 2048)))
        end
        |> Enum.sort_by(& &1["key"])
      later = List.last(records)
      drive(start(), records, page_size: 32, capture_projection_context: true)
      ctx = Process.delete(:recall_projection_context)
      assert {:ok, small} = K.recall_projection(ctx, [List.last(ctx.notes)], "knowledge", 8192)
      budget = small.rendered_bytes + 16
      assert budget < 8192
      assert {:ok, %{fits: true}} = K.recall_projection(ctx, [List.last(ctx.notes)], "knowledge", budget)
      assert {:ok, %{fits: false}} = K.recall_projection(ctx, [hd(ctx.notes)], "knowledge", budget)
      {result, _, calls, items} =
        drive(start(), records, page_size: 32, available_bytes: budget)

      assert result["coverage"] == "partial"
      assert result["candidates"] == 33
      assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "get")) == 33
      assert decoded_notes(items) == %{later["key"] => "later fitting note"}
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

    test "fitting notes continue across the first index page" do
      records = for n <- 1..33, do: record(n, "~N#{n}~")
      {result, _, calls, items} = drive(start(), records, page_size: 32)
      assert result["coverage"] == "complete" and result["included"] == 33
      assert decoded_notes(items) == Map.new(records, &{&1["key"], &1["value"]["text"]})
      assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "get")) == 33
      assert Enum.map(Enum.filter(calls, &(get_in(&1, ["request", "op"]) == "index")),
               &get_in(&1, ["request", "cursor"])) == [nil, "page:32", nil]
    end

    test "unavailable earlier records do not hide a later fitting note" do
      records = for n <- 1..97, do: record(n, "~N#{n}~")
      unavailable = records |> Enum.take(96) |> Enum.map(& &1["key"])
      {result, _, calls, items} =
        drive(start(), records, page_size: 32, unavailable_keys: unavailable)

      assert result["coverage"] == "partial" and result["unavailable"] == 96
      assert result["included"] == 1
      assert decoded_notes(items) == %{List.last(records)["key"] => "~N97~"}
      assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "get")) == 97
    end

    test "an ambiguous source or consent failure aborts paging and withholds earlier notes" do
      records = for n <- 1..40, do: record(n, "~N#{n}~")
      denied = Enum.at(records, 34)["key"]

      for failure <- [denied_keys: [denied], refused_keys: [denied]] do
        {result, _, calls, items} = drive(start(), records, [{:page_size, 32}, failure])
        assert result["coverage"] == "unavailable" and result["included"] == 0
        assert decoded_notes(items) == %{}
        assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "get")) == 35
      end
    end

    test "a changed root between pages refuses the accumulated recall" do
      records = for n <- 1..33, do: record(n, "~N#{n}~")
      {result, _, calls, _} = drive(start(), records, page_size: 32, changed_index_cursor: "page:32")
      assert result == %{"status" => "refused", "code" => "invalid_index_progress"}
      assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "get")) == 32
      refute Enum.any?(calls, &(&1["op"] == "context.publish" and &1["items"] != []))
    end

    test "the verified dependency allowance stops literal reads without claiming complete coverage" do
      records = for n <- 1..60, do: record(n, "~N#{n}~")
      {result, _, calls, _items} =
        drive(start(), records, page_size: 32, capture_projection_context: true)
      fitting = Process.delete(:recall_projection_context)
      # Every indexed note is read; only this fixture's model context budget,
      # not the dependency allowance, limits what is rendered.
      assert length(fitting.index) == 60 and length(fitting.notes) == 60 and fitting.read == 60
      assert fitting.index_pages == 2 and fitting.next == nil and result["candidates"] == 60

      records = for n <- 1..61, do: record(n, "~N#{n}~")
      {result, _, calls_over, items} =
        drive(start(), records, page_size: 32, capture_projection_context: true)
      ctx = Process.delete(:recall_projection_context)

      # Two pages, the reads so far and two reserved root observations stay
      # within 63 verified dependencies for 60 reads: the 61st remains unstarted
      # even though it is on the last indexed page.
      assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "get")) == 60
      assert Enum.count(calls_over, &(get_in(&1, ["request", "op"]) == "get")) == 60
      assert Enum.count(calls_over, &(get_in(&1, ["request", "op"]) == "index")) == 3
      assert ctx.read == 60 and ctx.successful_reads == 60 and ctx.dependency_bytes == 60 * 1_671
      assert length(ctx.index) == 61 and length(ctx.notes) == 60
      assert ctx.next == nil and ctx.verified
      assert result["candidates"] == 61 and result["unavailable"] == 0
      assert result["coverage"] == "partial" and result["included"] <= 60
      refute Map.has_key?(decoded_notes(items), List.last(records)["key"])
    end

    test "accepted decisions reach the dependency byte allowance sooner than literal notes" do
      records = for n <- 1..60, do: accepted_record("~D#{n}~")
      assert length(Enum.uniq_by(records, & &1["key"])) == 60
      {result, _, calls, _} =
        drive(start(), records, page_size: 32, capture_projection_context: true)
      ctx = Process.delete(:recall_projection_context)

      assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "get")) == 50
      assert ctx.successful_reads == 50 and ctx.dependency_bytes == 50 * 2_483
      assert length(ctx.notes) == 50
      assert result["candidates"] == 60 and result["coverage"] == "partial"
    end

    test "sparse discovery stops at the real host read bound with partial coverage" do
      records = for n <- 1..600, do: record(n, "~N#{n}~")
      {result, _, calls, _} = drive(start(), records, page_size: 32, unavailable: true)
      host_reads = Enum.count(calls, &(get_in(&1, ["request", "op"]) in ~w(index get)))
      assert result["coverage"] == "partial" and result["included"] == 0
      assert result["unavailable"] > 32 and result["unavailable"] < 600
      assert host_reads <= 512
    end

    test "recall reserves all proofs in each successful causal read" do
      records = for n <- 1..25 do
        row = record(n, "~N#{n}~")
        value = put_in(row, ["value", "evidence", "sources"], for(i <- 1..8, do: %{"proof" => i}))
        bytes = Ipse.Extension.Collection.Migration.encode(value["value"])
        %{value | "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
      end

      {result, _, calls, _} = drive(start(), records, page_size: 25)
      assert result["coverage"] == "partial"
      assert result["included"] <= 15
      assert Enum.count(calls, &(get_in(&1, ["request", "op"]) == "get")) <= 15
    end

    test "all32 tiny notes fitting the actual envelope are included without arbitrary item caps" do
      records = for n <- 1..32, do: record(n, "note #{n}")
      {result, _, calls, items} = drive(start(), records, capture_projection_context: true)
      assert result["coverage"] == "complete"
      assert result["included"] == 32
      assert length(items) <= 8
      assert length(calls) <= 37
      assert Ipse.Extension.context_rendered_bytes(items, "knowledge") <= 8192
      assert decoded_notes(items) == Map.new(records, &{&1["key"], &1["value"]["text"]})
      ctx = Process.delete(:recall_projection_context)
      assert {:ok, baseline} = K.recall_baseline_projection(ctx, "knowledge", 8192)
      assert baseline.items == items and baseline.included == 32 and baseline.fits
      assert {:ok, facts, binding} = K.recall_decision_facts(ctx, [], "knowledge", 6144, "note", true, nil)
      assert facts["eligible_count"] == 32 and length(facts["candidates"]) == 16
      assert map_size(binding) == 16
      policy = IpseKnowledge.Knowledge.DecisionPolicy.default("notes.select") |> Map.merge(%{"strategy" => "decision", "profile" => "fixture"})
      assert {:ok, plan} = IpseKnowledge.Knowledge.DecisionPolicy.plan(policy, facts, :development_experiment)
      expected = if is_integer(facts["eligible_rendered_bytes"]) and facts["eligible_rendered_bytes"] <= 6144,
        do: "fit_coverage_unavailable", else: "no_alternatives"
      assert plan.reason == expected and plan.baseline == nil and plan.request == nil
    end

    test "engine-free baseline skips an oversized note and keeps later fitting notes" do
      records = [record(1, String.duplicate("x", 2048)), record(2, "second"), record(3, "third")]
      {result, _, _, items} = drive(start(), records, available_bytes: 2500, capture_projection_context: true)
      ctx = Process.delete(:recall_projection_context)
      assert result["coverage"] == "partial"
      assert result["included"] == 2
      assert {:ok, baseline} = K.recall_baseline_projection(ctx, "knowledge", 2500)
      assert baseline.items == items and baseline.included == 2 and baseline.fits
      assert decoded_notes(items) == Map.new(tl(records), &{&1["key"], &1["value"]["text"]})
    end

    test "recall projections measure the real context envelope for read subsets" do
      records = [record(1, String.duplicate("é", 300)), record(2, "other note")]
      {_, _, _, published} = drive(start(), records, capture_projection_context: true)
      ctx = Process.delete(:recall_projection_context)
      assert length(ctx.notes) == 2
      available = min(ctx.budget["available_bytes"], 8192)

      assert {:ok, full} = K.recall_projection(ctx, ctx.notes, "knowledge", available)
      assert full.items == published
      assert {:ok, baseline} = K.recall_baseline_projection(ctx, "knowledge", available)
      assert baseline == full
      assert full.rendered_bytes == Ipse.Extension.context_rendered_bytes(published, "knowledge")
      assert full.fits and full.coverage == "complete" and full.included == 2

      assert {:ok, partial} = K.recall_projection(ctx, [hd(ctx.notes)], "knowledge", 8192)
      assert partial.rendered_bytes == Ipse.Extension.context_rendered_bytes(partial.items, "knowledge")
      assert partial.coverage == "partial" and partial.included == 1
      assert decoded_notes(partial.items) == %{hd(records)["key"] => hd(records)["value"]["text"]}
      assert {:ok, narrow} = K.recall_projection(ctx, [hd(ctx.notes)], "knowledge", 1)
      refute narrow.fits
      assert {:error, :invalid_recall_projection} = K.recall_projection(ctx, Enum.reverse(ctx.notes), "knowledge", 8192)
      assert {:error, :invalid_recall_projection} = K.recall_projection(ctx, [hd(ctx.notes), hd(ctx.notes)], "knowledge", 8192)
      assert {:error, :invalid_recall_projection} = K.recall_projection(ctx, [{hd(records), "foreign"}], "knowledge", 8192)
      duplicate_ctx = %{ctx | notes: [hd(ctx.notes), hd(ctx.notes)]}
      assert {:error, :invalid_recall_projection} = K.recall_projection(duplicate_ctx, duplicate_ctx.notes, "knowledge", 8192)
      {same_row, _} = hd(ctx.notes)
      duplicate_key_ctx = %{ctx | notes: [hd(ctx.notes), {same_row, "other-operation"}]}
      assert {:error, :invalid_recall_projection} = K.recall_projection(duplicate_key_ctx, [], "knowledge", 8192)

      [first, second] = Enum.map(ctx.notes, fn {row, _} -> row["key"] end)
      packs = [%{"id" => "z", "members" => [second]}, %{"id" => "a", "members" => [second, first]}]
      assert {:ok, [all_pack, second_pack]} = K.recall_pack_projections(ctx, packs, "knowledge", available)
      assert all_pack.id == "a" and all_pack.members == [first, second]
      assert all_pack.projection == full
      assert second_pack.id == "z" and second_pack.members == [second]
      assert {:ok, second_only} = K.recall_projection(ctx, [List.last(ctx.notes)], "knowledge", available)
      assert second_pack.projection == second_only
      assert {:error, :invalid_recall_projection} = K.recall_pack_projections(ctx, [%{"id" => "a", "members" => ["foreign"]}], "knowledge", available)
      assert {:error, :invalid_recall_projection} = K.recall_pack_projections(ctx, [%{"id" => "a", "members" => [first, first]}], "knowledge", available)
      assert {:error, :invalid_recall_projection} = K.recall_pack_projections(ctx, [%{"id" => "a", "members" => [first, second]}, %{"id" => "b", "members" => [second, first]}], "knowledge", available)
      assert {:error, :invalid_recall_projection} = K.recall_pack_projections(ctx, [%{"id" => "a", "members" => [first]}, %{"id" => "a", "members" => [second]}], "knowledge", available)
      assert {:error, :invalid_recall_projection} = K.recall_pack_projections(ctx, for(n <- 1..9, do: %{"id" => "p#{n}", "members" => [first]}), "knowledge", available)
      assert {:error, :invalid_recall_projection} = K.recall_pack_projections(ctx, packs, "knowledge", 8193)

      alternatives = [%{"id" => "first", "members" => [first]}, %{"id" => "second", "members" => [second]}]
      assert {:ok, singles} = K.recall_pack_projections(ctx, alternatives, "knowledge", 6144)
      selection_budget = Enum.max(Enum.map(singles, & &1.projection.rendered_bytes)) + 20
      assert selection_budget < full.rendered_bytes
      assert {:ok, facts, binding} = K.recall_decision_facts(ctx, alternatives, "knowledge", selection_budget, "note", true, "first")
      policy = IpseKnowledge.Knowledge.DecisionPolicy.default("notes.select") |> Map.merge(%{"strategy" => "decision", "profile" => "fixture"})
      assert {:ok, plan} = IpseKnowledge.Knowledge.DecisionPolicy.plan(policy, facts, :development_experiment)
      assert plan.request != nil
      assert Enum.map(plan.mapping, & &1["id"]) == ~w(first second)
      assert Enum.map(facts["alternatives"], & &1["rendered_bytes"]) == Enum.map(singles, & &1.projection.rendered_bytes)
      assert Map.values(binding) |> Enum.sort() == Enum.sort([first, second])
      assert {:ok, production} = IpseKnowledge.Knowledge.DecisionPolicy.plan(policy, facts, :production)
      assert production.reason == "no_qualified_strategy" and production.request == nil
      advice = %{"version" => 1, "answers" => [%{"id" => "pack", "type" => "choice", "choice" => "second", "confidence" => 0.1,
        "probabilities" => [%{"id" => "first", "probability" => 0.1}, %{"id" => "second", "probability" => 0.9}]}]}
      assert {:ok, selected} = K.recall_decision_projection(ctx, plan, binding, advice, "knowledge")
      assert {:ok, selected_again} = K.recall_projection(ctx, [List.last(ctx.notes)], "knowledge", selection_budget)
      assert selected.projection == selected_again
      assert {:ok, fallback} = K.recall_decision_projection(ctx, plan, binding, %{"version" => 1, "answers" => []}, "knowledge")
      assert fallback.outcome["receipt"]["reason"] == "malformed_advice"
      assert {:ok, first_again} = K.recall_projection(ctx, [hd(ctx.notes)], "knowledge", selection_budget)
      assert fallback.projection == first_again
      assert {:ok, engine_free} = K.recall_baseline_projection(ctx, "knowledge", selection_budget)
      assert engine_free == first_again
      assert {:error, :invalid_recall_projection} = K.recall_baseline_projection(ctx, "knowledge", 8193)
      {row, operation} = hd(ctx.notes)
      changed_receipt = %{ctx | notes: [{row, operation <> "changed"} | tl(ctx.notes)]}
      assert {:error, :invalid_recall_projection} = K.recall_decision_projection(changed_receipt, plan, binding, advice, "knowledge")
      assert {:error, :invalid_recall_projection} = K.recall_decision_projection(%{ctx | generation: ctx.generation + 1}, plan, binding, advice, "knowledge")
      changed_index = update_in(ctx.index, [Access.at(0), "sha256"], fn _ -> String.duplicate("0", 64) end)
      assert {:error, :invalid_recall_projection} = K.recall_decision_projection(%{ctx | index: changed_index}, plan, binding, advice, "knowledge")
      assert {:error, :invalid_recall_projection} = K.recall_decision_projection(ctx, plan, Map.put(binding, hd(Map.keys(binding)), "other-key"), advice, "knowledge")
      assert {:error, :invalid_recall_projection} = K.recall_decision_projection(%{ctx | verified: false}, plan, binding, advice, "knowledge")
      assert {:error, :invalid_recall_projection} = K.recall_decision_facts(%{ctx | verified: false}, alternatives, "knowledge", selection_budget, "note", true, "first")
      assert {:error, :invalid_recall_projection} = K.recall_decision_facts(%{ctx | next: "next"}, alternatives, "knowledge", selection_budget, "note", true, "first")

      large = for n <- 1..6, do: record(n, String.duplicate("x", 2048))
      drive(start(), large, capture_projection_context: true)
      large_ctx = Process.delete(:recall_projection_context)
      assert {:ok, oversized} = K.recall_projection(large_ctx, large_ctx.notes, "knowledge", 8192)
      assert oversized.rendered_bytes == nil and not oversized.fits
    end

    test "shadow comparison retains the complete engine-free baseline beyond pack limits" do
      records = for n <- 1..8, do: record(n, String.duplicate("x", 700))
      {result, _, _, items} = drive(start(), records, capture_projection_context: true)
      ctx = %{Process.delete(:recall_projection_context) | coverage: "complete"}
      budget = min(ctx.budget["available_bytes"], 8192)
      assert result["coverage"] == "partial"
      assert result["included"] > 4
      keys = Enum.map(ctx.notes, fn {row, _} -> row["key"] end)
      packs = [%{"id" => "first", "members" => Enum.take(keys, 4)},
               %{"id" => "second", "members" => Enum.drop(keys, 4)}]
      assert {:ok, facts, binding} = K.recall_decision_facts(ctx, packs, "knowledge", budget, "query", true, "first")
      policy = IpseKnowledge.Knowledge.DecisionPolicy.default("notes.select") |> Map.merge(%{"strategy" => "decision", "profile" => "fixture"})
      assert {:ok, plan} = IpseKnowledge.Knowledge.DecisionPolicy.plan(policy, facts, :development_experiment)
      assert is_map(plan.request)
      advice = %{"version" => 1, "answers" => [%{"id" => "pack", "type" => "choice", "choice" => "second", "confidence" => 0.1,
        "probabilities" => [%{"id" => "first", "probability" => 0.1}, %{"id" => "second", "probability" => 0.9}]}]}
      assert {:ok, comparison} = K.recall_shadow_comparison(ctx, plan, binding, advice, "knowledge")
      assert comparison.baseline.items == items and comparison.baseline.included == result["included"]
      assert comparison.ordinary == %{items: items, coverage: result["coverage"], included: result["included"]}
      assert comparison.shadow.included == 4 and comparison.outcome["receipt"]["reason"] == "selected"
      assert {:ok, refusal} = K.recall_shadow_comparison(ctx, plan, binding, %{"version" => 1, "answers" => []}, "knowledge")
      assert refusal.baseline == comparison.baseline and refusal.shadow == nil
      assert refusal.ordinary == comparison.ordinary
      assert refusal.outcome["receipt"]["reason"] == "malformed_advice"
      answer_refusal = %{"version" => 1, "answers" => [%{"id" => "pack", "type" => "refusal"}]}
      assert {:ok, refused} = K.recall_shadow_comparison(ctx, plan, binding, answer_refusal, "knowledge")
      assert refused.ordinary == comparison.ordinary and refused.shadow == nil
      assert refused.outcome["receipt"]["reason"] == "refusal"
      for {status, value, reason} <- [
            {"unknown", %{}, "decision_unknown"},
            {"denied", %{}, "decision_denied"},
            {"failed", %{"code" => "decision_response"}, "decision_response"},
            {"failed", %{"code" => "decision_timeout"}, "decision_timeout"},
            {"failed", %{"code" => "decision_cancelled"}, "decision_cancelled"},
            {"failed", %{"code" => "decision_request_failed"}, "decision_request_failed"},
            {"failed", %{"code" => "decision_limit"}, "decision_limit"}
          ] do
        failure = %{"status" => status, "value" => value}
        assert {:ok, failed} = K.recall_shadow_failure(ctx, plan, binding, failure, "knowledge")
        assert failed.ordinary == comparison.ordinary and failed.shadow == nil
        assert failed.outcome["receipt"]["reason"] == reason
      end
      assert {:error, :invalid_recall_projection} = K.recall_shadow_failure(ctx, plan, binding, %{"status" => "unknown", "value" => %{}, "extra" => 1}, "knowledge")
      assert {:error, :invalid_recall_projection} = K.recall_shadow_failure(ctx, plan, binding, %{"status" => "failed", "value" => %{"code" => "forged"}}, "knowledge")
      assert {:error, :invalid_recall_projection} = K.recall_shadow_failure(%{ctx | generation: ctx.generation + 1}, plan, binding, %{"status" => "unknown", "value" => %{}}, "knowledge")
      assert {:error, :invalid_recall_projection} = K.recall_shadow_comparison(%{ctx | generation: ctx.generation + 1}, plan, binding, advice, "knowledge")
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
      assert Enum.map(description["exports"]["tools"], & &1["id"]) == ~w(capture nominate index read search)
      assert description["subscriptions"] |> hd() |> Map.take(~w(view schedule mode)) ==
        %{"view" => "metadata", "schedule" => "before_request", "mode" => "job"}
      refute "host.model" in description["capabilities"]
    end
  end
  result = ExUnit.run()
  if Map.take(result, [:total, :failures, :skipped, :excluded]) !=
       %{total: 33, failures: 0, skipped: 0, excluded: 0}, do: System.halt(1)
  IO.puts("KNOWLEDGE_RECALL_CONTROL_PASS")
  """

  @tag :exunit_output_contract
  @tag :native_storage
  test "bounded turn-local recall runs in an independent worker VM" do
    sdk = Application.app_dir(:ipse, "ebin")
    paths = Path.wildcard(Path.join(Path.dirname(Path.dirname(sdk)), "*/ebin"))

    {artifact_args, child_artifact} =
      case System.get_env("IPSE_KNOWLEDGE_RECALL_ARTIFACT") do
        nil ->
          {[], nil}

        artifact ->
          root = Path.join(System.tmp_dir!(), "recall-worker-fixture-" <> Ipse.Usage.id())
          copy = Path.join(root, "knowledge")
          File.mkdir_p!(root)
          File.cp_r!(Path.expand(artifact), copy)
          on_exit(fn -> File.rm_rf!(root) end)
          {["-pa", Path.join(copy, "ebin")], copy}
      end

    args =
      ["--erl", "+S 2:2"] ++ Enum.flat_map(paths, &["-pa", &1]) ++ artifact_args ++ ["-e", @suite]

    {output, status} =
      System.cmd(System.find_executable("elixir"), args,
        env: [{"IPSE_KNOWLEDGE_RECALL_ARTIFACT", child_artifact}],
        stderr_to_stdout: true
      )

    assert status == 0, output

    assert Enum.count(String.split(output, ~r/\r?\n/), &(&1 === "KNOWLEDGE_RECALL_CONTROL_PASS")) ===
             1

    refute :code.is_loaded(IpseKnowledge.Knowledge)
  end
end
