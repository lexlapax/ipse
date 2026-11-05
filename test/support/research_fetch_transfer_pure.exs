ExUnit.start(autorun: false, max_cases: 1)
Code.require_file("dev/fixtures/knowledge.exs", Path.expand("../..", __DIR__))
Code.require_file("extensions/knowledge/src/corpus.ex", Path.expand("../..", __DIR__))

defmodule ResearchFetchTransferTest do
  use ExUnit.Case, async: false
  alias IpseKnowledge.{Research, Corpus, Store, Evidence}
  alias Ipse.Development.Fixtures.Knowledge, as: F
  @root Path.expand("../..", __DIR__)
  @body "Résumé 雪: Ada owns release after audit."
  @quote "Ada owns release after audit."
  @uri "fixture:release"

  defp opts,
    do:
      JSON.decode!(
        File.read!(Path.join(@root, "extensions/knowledge/options/research-state-fetched.json"))
      )

  defp args,
    do: %{
      "store" => "notes",
      "fetch" => "web",
      "uri" => @uri,
      "title" => "Release",
      "quote" => @quote,
      "timeout_ms" => 3000
    }

  defp db(text \\ @body) do
    page = %{
      "text" => text,
      "observed_uri" => "fixture:observed-release",
      "media_type" => "text/plain",
      "observed_at_ms" => 10
    }

    {:ok, db} =
      F.configure_web(F.new("research-notes"), %{
        "searches" => %{},
        "pages" => %{@uri => page, "fixture:alias" => page}
      })

    db
  end

  defp start(module) do
    options = if module == Corpus, do: opts() |> Map.put("fetch", %{}), else: opts()
    {:ok, state} = module.init(options)
    refute Map.has_key?(state, :invalid)
    state
  end

  defp value(%Ipse.Extension.ResultPublication.Output{bytes: bytes}), do: JSON.decode!(bytes)
  defp value(%{"kind" => "result", "value" => value}), do: value

  defp host(db, request) do
    {outcome, next} = F.host(db, request)
    payload = %{"invocation_id" => String.duplicate("0", 32), "outcome" => outcome}
    assert :ok = Ipse.Extension.validate(payload)

    Process.put(
      :max_payload_bytes,
      max(Process.get(:max_payload_bytes, 0), byte_size(Jason.encode!(payload)))
    )

    {outcome, next}
  end

  defp run(module, {:ok, %{"kind" => "host_call", "request" => request}, state}, db, stop) do
    reply = %{"api_version" => 1, "kind" => "host_call", "request" => request}
    assert :ok = Ipse.Extension.validate(reply)

    Process.put(
      :max_reply_bytes,
      max(Process.get(:max_reply_bytes, 0), byte_size(Jason.encode!(reply)))
    )

    case {request["op"], stop} do
      {"state.put", mode}
      when mode in [:deny_selector, :unknown_selector, :unknown_selector_before] ->
        if get_in(request, ["value", "kind"]) == "fetch_origin" do
          {outcome, next} =
            if mode == :unknown_selector,
              do: host(db, request),
              else: {%{}, db}

          status = if mode == :deny_selector, do: "denied", else: "unknown"

          run(
            module,
            module.handle(
              "host.actions",
              %{"outcome" => Map.put(outcome, "status", status)},
              state
            ),
            next,
            :none
          )
        else
          {outcome, db} = host(db, request)
          run(module, module.handle("host.actions", %{"outcome" => outcome}, state), db, stop)
        end

      {"state.put", :denied} ->
        run(
          module,
          module.handle(
            "host.actions",
            %{"outcome" => %{"status" => "denied", "value" => %{}}},
            state
          ),
          db,
          :none
        )

      {"state.put", :unknown_after} ->
        {_outcome, db} = host(db, request)

        run(
          module,
          module.handle(
            "host.actions",
            %{"outcome" => %{"status" => "unknown", "value" => %{}}},
            state
          ),
          db,
          :none
        )

      _ ->
        {outcome, db} = host(db, request)
        run(module, module.handle("host.actions", %{"outcome" => outcome}, state), db, stop)
    end
  end

  defp run(_, {:ok, result, _}, db, _) do
    reply =
      case result do
        %Ipse.Extension.ResultPublication.Output{} ->
          {:ok, offer} = Ipse.Extension.ResultPublication.offer(result)
          offer

        _ ->
          result
      end

    assert :ok = Ipse.Extension.validate(reply)
    {value(result), db}
  end

  defp run(_, {:stop, :unknown_effect}, db, _), do: {:unknown, db}

  defp call(module, id, args, db, stop \\ :none),
    do:
      run(
        module,
        module.handle("invoke.command", %{"id" => id, "arguments" => args}, start(module)),
        db,
        stop
      )

  defp store_run({:call, request, cont}, db) do
    {outcome, db} = F.host(db, request)
    store_run(Store.resume(cont, outcome), db)
  end

  defp store_run(result, db), do: {result, db}

  test "actual fetch protocol precedes the attributed canonical Store write and Corpus query" do
    {result, db} = call(Research, "fetch_retain", args(), db())
    assert result["status"] == "ok"
    assert result["coverage"]["native_receipt"] == false
    assert result["coverage"]["source_id"] == Store.provided_transfer_id(@body)
    requests = F.requests(db)
    assert hd(requests)["op"] == "mcp.call"

    assert Enum.find_index(requests, &(&1["op"] == "effect.result.read")) <
             Enum.find_index(requests, &(&1["op"] == "state.put"))

    {query, _} =
      call(
        Corpus,
        "query",
        %{
          "store" => "notes",
          "retrieval" => "words",
          "rerank" => nil,
          "query" => "release",
          "top_k" => 3,
          "as_of_ms" => 20
        },
        db
      )

    assert [evidence] = query["evidence"]
    citation = evidence["citation"]
    assert citation["quote"] == @body
    assert citation["content_sha256"] == Evidence.sha256(@body)
    assert citation["origin"]["kind"] == "fetch"
    receipt = citation["origin"]["receipt"]
    assert receipt == result["coverage"]["derivation"]
    assert receipt["body_sha256"] == Evidence.sha256(@body)

    assert receipt["requested_uri"] == @uri and
             receipt["observed_uri"] == "fixture:observed-release"

    assert receipt["quote"] == @quote and receipt["start_byte"] == byte_size("Résumé 雪: ")
    assert receipt["end_byte"] == byte_size(@body)
    assert receipt["descriptor"]["kind"] == "mcp.text"
  end

  test "forget blocks same-body URI and quote aliases in fresh Research states" do
    {retained, db} = call(Research, "fetch_retain", args(), db())
    id = retained["coverage"]["source_id"]

    {inspected, db} =
      call(
        Corpus,
        "source",
        %{"store" => "notes", "action" => "inspect", "args" => %{"source_id" => id}},
        db
      )

    {forgotten, db} =
      call(
        Corpus,
        "source",
        %{
          "store" => "notes",
          "action" => "forget",
          "args" => %{"source_id" => id, "expected_revision" => inspected["coverage"]["revision"]}
        },
        db
      )

    assert forgotten["status"] == "ok"
    records = F.records(db)

    for uri <- [@uri, "fixture:alias"], quote <- [@quote, "Résumé 雪"] do
      {refused, after_db} =
        call(
          Research,
          "fetch_retain",
          args() |> Map.put("uri", uri) |> Map.put("quote", quote),
          db
        )

      assert refused["status"] == "refused"
      assert F.records(after_db) == records
    end
  end

  test "malformed and denied fetches never reach State mutation" do
    for mode <- [
          :fetch_partial,
          :fetch_changed_body,
          :fetch_forged_hash,
          :fetch_forged_receipt,
          :fetch_wrong_uri,
          :denied
        ] do
      {refused, db} = call(Research, "fetch_retain", args(), F.barrier(db(), "fetch", mode))
      assert refused["status"] == "refused"
      refute Enum.any?(F.requests(db), &(&1["op"] == "state.put"))
      assert F.records(db) == %{}
    end

    {refused, db} =
      call(Research, "fetch_retain", Map.put(args(), "uri", "fixture:missing"), db())

    assert refused["status"] == "refused" and F.records(db) == %{}
  end

  test "quote and body constraints refuse before any write" do
    for {text, quote} <- [
          {@body, "missing"},
          {"aaa", "aa"},
          {"x" <> String.duplicate("z", 4096), "x"}
        ] do
      {refused, db} = call(Research, "fetch_retain", Map.put(args(), "quote", quote), db(text))
      assert refused["status"] == "refused" and F.records(db) == %{}
      refute Enum.any?(F.requests(db), &(&1["op"] == "state.put"))
    end
  end

  test "caller cannot supply bytes, fetch receipt, destination identity or historical authority" do
    for extra <- [
          %{"text" => @body},
          %{"source" => %{}},
          %{"receipt" => %{}},
          %{"source_id" => "fake"},
          %{"generation" => 2},
          %{"expected_revision" => 9},
          %{"origin" => %{"kind" => "fetch"}},
          %{"historical_import" => %{}}
        ] do
      {refused, db} = call(Research, "fetch_retain", Map.merge(args(), extra), db())
      assert refused["status"] == "refused" and F.requests(db) == []

      assert {:done, {:error, :invalid_fetch_transfer, _}} =
               Store.start_fetch_transfer(
                 "notes",
                 opts()["stores"]["notes"],
                 opts()["fetch"]["web"],
                 Map.merge(Map.take(args(), ~w(uri title quote timeout_ms)), extra)
               )
    end
  end

  test "State denial changes no records and interrupted writes stop unknown" do
    {refused, denied} = call(Research, "fetch_retain", args(), db(), :denied)
    assert refused["status"] == "refused" and F.records(denied) == %{}
    assert {:unknown, after_db} = call(Research, "fetch_retain", args(), db(), :unknown_after)
    assert map_size(F.records(after_db)) == 1
  end

  test "same body cannot silently rewrite fetch attribution" do
    {retained, db} = call(Research, "fetch_retain", args(), db())
    {refused, same} = call(Research, "fetch_retain", Map.put(args(), "uri", "fixture:alias"), db)
    assert retained["status"] == "ok" and refused["status"] == "refused"
    assert F.records(same) == F.records(db)
  end

  test "a provided-body tombstone also blocks re-fetching those bytes" do
    put = %{
      "source_id" => Store.provided_transfer_id(@body),
      "generation" => 1,
      "expected_revision" => 0,
      "title" => "Provided",
      "text" => @body,
      "uri" => "provided:release",
      "observed_at_ms" => 10,
      "event_at_ms" => nil,
      "expires_at_ms" => nil
    }

    assert {{:done, {:ok, stored}}, db} =
             store_run(Store.start("notes", opts()["stores"]["notes"], :put, put), db())

    id = stored["source_id"]

    {forgotten, db} =
      call(
        Corpus,
        "source",
        %{
          "store" => "notes",
          "action" => "forget",
          "args" => %{"source_id" => id, "expected_revision" => stored["revision"]}
        },
        db
      )

    assert forgotten["status"] == "ok"

    {refused, after_db} =
      call(Research, "fetch_retain", Map.put(args(), "uri", "fixture:alias"), db)

    assert refused["status"] == "refused" and F.records(after_db) == F.records(db)
  end

  test "ordinary Store and Corpus put cannot forward a fabricated fetched capture" do
    put = %{
      "source_id" => "provided:ordinary",
      "generation" => 1,
      "expected_revision" => 0,
      "title" => "Provided",
      "text" => @body,
      "uri" => @uri,
      "observed_at_ms" => 10,
      "event_at_ms" => nil,
      "expires_at_ms" => nil,
      "fetched_capture" => %{"descriptor" => %{"operation_id" => String.duplicate("0", 32)}}
    }

    assert {:done, {:error, :invalid_store_arguments, _}} =
             Store.start("notes", opts()["stores"]["notes"], :put, put)

    {refused, unchanged} =
      call(Corpus, "source", %{"store" => "notes", "action" => "put", "args" => put}, db())

    assert refused["status"] == "refused" and F.records(unchanged) == %{}
  end

  test "an uncertain actual fetch stops without State IO" do
    assert {:unknown, unchanged} =
             call(Research, "fetch_retain", args(), F.barrier(db(), "fetch", :unknown))

    refute Enum.any?(F.requests(unchanged), &(&1["op"] in ~w(state.put state.scan state.get)))
  end

  defp changed(db, body, observed) do
    {:ok, db} =
      F.configure_web(db, %{
        "searches" => %{},
        "pages" => %{
          @uri => %{
            "text" => body,
            "observed_uri" => "fixture:observed-release",
            "media_type" => "text/plain",
            "observed_at_ms" => observed
          }
        }
      })

    db
  end

  defp query(db) do
    call(
      Corpus,
      "query",
      %{
        "store" => "notes",
        "retrieval" => "words",
        "rerank" => nil,
        "query" => "release",
        "top_k" => 3,
        "as_of_ms" => 30
      },
      db
    )
  end

  defp inspect_source(db, id),
    do:
      call(
        Corpus,
        "source",
        %{"store" => "notes", "action" => "inspect", "args" => %{"source_id" => id}},
        db
      )

  defp pause_selector({:ok, %{"kind" => "host_call", "request" => request}, state}, db) do
    if request["op"] == "state.put" and get_in(request, ["value", "kind"]) == "fetch_origin" do
      {request, state, db}
    else
      {outcome, db} = host(db, request)
      pause_selector(Research.handle("host.actions", %{"outcome" => outcome}, state), db)
    end
  end

  defp selection_args(db, id) do
    {inspected, db} = inspect_source(db, id)

    args = %{
      "store" => "notes",
      "fetch" => "web",
      "uri" => @uri,
      "source_id" => id,
      "source_revision" => inspected["coverage"]["revision"],
      "expected_selection_revision" =>
        get_in(inspected, ["coverage", "fetch_version", "revision"]) || 0
    }

    {args, db}
  end

  defp unselected(body, observed, mode \\ :deny_selector) do
    {_, db} = call(Research, "fetch_retain", args(), db())

    {outcome, db} =
      call(
        Research,
        "fetch_retain",
        Map.put(args(), "quote", body),
        changed(db, body, observed),
        mode
      )

    {outcome, db, Store.provided_transfer_id(body)}
  end

  test "changed body advances one stable origin while prior bytes and captured attribution stay immutable" do
    {first, db} = call(Research, "fetch_retain", args(), db())
    {prior_query, db} = query(db)
    [prior] = prior_query["evidence"]
    first_id = first["coverage"]["source_id"]

    old_root =
      Enum.find_value(F.records(db), fn {_, row} ->
        if get_in(row, ["value", "source_id"]) == first_id and
             get_in(row, ["value", "kind"]) == "root",
           do: row
      end)

    body = "Résumé 雪: Babbage owns release after audit."
    db = changed(db, body, 20)

    {second, db} =
      call(
        Research,
        "fetch_retain",
        Map.put(args(), "quote", "Babbage owns release after audit."),
        db
      )

    assert second["status"] == "ok"
    assert second["coverage"]["source_id"] != first_id

    assert second["coverage"]["selected_version"]["origin_key"] ==
             first["coverage"]["selected_version"]["origin_key"]

    assert second["coverage"]["selected_version"]["generation"] == 2
    assert F.records(db)[old_root["key"]] === old_root
    assert prior["citation"]["quote"] == @body
    assert prior["citation"]["origin"]["receipt"] === first["coverage"]["derivation"]
    {now, db} = query(db)
    assert [current] = now["evidence"]
    assert current["citation"]["quote"] == body
    {old, db} = inspect_source(db, first_id)
    assert old["coverage"]["fetch_version"]["status"] == "historical"
    {fresh, _} = inspect_source(db, second["coverage"]["source_id"])
    assert fresh["coverage"]["fetch_version"]["status"] == "current"

    {repeat, after_db} =
      call(
        Research,
        "fetch_retain",
        Map.put(args(), "quote", "Babbage owns release after audit."),
        db
      )

    assert repeat["status"] == "refused" and F.records(after_db) === F.records(db)
  end

  test "forgetting selected changed bytes neither resurrects the prior body nor bypasses its tombstone" do
    {_, db} = call(Research, "fetch_retain", args(), db())
    body = "Babbage owns release after audit."

    {second, db} =
      call(Research, "fetch_retain", Map.put(args(), "quote", body), changed(db, body, 20))

    id = second["coverage"]["source_id"]
    {inspected, db} = inspect_source(db, id)

    {forgotten, db} =
      call(
        Corpus,
        "source",
        %{
          "store" => "notes",
          "action" => "forget",
          "args" => %{"source_id" => id, "expected_revision" => inspected["coverage"]["revision"]}
        },
        db
      )

    assert forgotten["status"] == "ok"
    {now, db} = query(db)
    assert now["evidence"] == []
    {refused, after_db} = call(Research, "fetch_retain", Map.put(args(), "quote", body), db)
    assert refused["status"] == "refused" and F.records(after_db) === F.records(db)
  end

  test "selector changes invalidate earlier tokens while upstream time does not order publication" do
    {_, db} = call(Research, "fetch_retain", args(), db())
    profile = opts()["stores"]["notes"]
    {{:done, {:ok, snapshot}}, db} = store_run(Store.start("notes", profile, :snapshot, %{}), db)
    body = "Babbage owns release after audit."

    {second, db} =
      call(Research, "fetch_retain", Map.put(args(), "quote", body), changed(db, body, 20))

    assert second["status"] == "ok"

    {{:done, {:ok, checked}}, db} =
      store_run(Store.start("notes", profile, :revalidate, %{"tokens" => snapshot["tokens"]}), db)

    assert checked["valid"] == false
    before = F.records(db)
    text = "Charles owns release after audit."

    {next, db} =
      call(Research, "fetch_retain", Map.put(args(), "quote", text), changed(db, text, 15))

    assert next["status"] == "ok" and F.records(db) !== before
    assert next["coverage"]["selected_version"]["generation"] == 3
  end

  test "denied or uncertain selector CAS never invents a selected version or retries a body publication" do
    {first, db} = call(Research, "fetch_retain", args(), db())
    body = "Babbage owns release after audit."
    next = changed(db, body, 20)

    {refused, denied} =
      call(Research, "fetch_retain", Map.put(args(), "quote", body), next, :deny_selector)

    assert refused["status"] == "refused"
    assert refused["coverage"]["body_publication"] == "known"
    assert refused["coverage"]["source_id"] == Store.provided_transfer_id(body)
    assert refused["coverage"]["selection_publication"] == "not_confirmed"
    assert refused["coverage"]["recovery"] == "inspect_then_select_retained"
    {visible, _} = query(denied)
    assert [evidence] = visible["evidence"]
    assert evidence["citation"]["quote"] == @body
    key = first["coverage"]["selected_version"]["origin_key"]
    assert F.records(denied)[key] === F.records(db)[key]
    {again, unchanged} = call(Research, "fetch_retain", Map.put(args(), "quote", body), denied)
    assert again["status"] == "refused" and F.records(unchanged) === F.records(denied)
    {historical, _} = inspect_source(denied, Store.provided_transfer_id(body))
    assert historical["coverage"]["fetch_version"]["status"] == "historical"

    assert {:unknown, uncertain} =
             call(
               Research,
               "fetch_retain",
               Map.put(args(), "quote", body),
               next,
               :unknown_selector
             )

    assert F.records(uncertain)[key]["revision"] == 2
    {observed, inspected} = inspect_source(uncertain, Store.provided_transfer_id(body))
    assert observed["coverage"]["fetch_version"]["status"] == "current"
    assert F.records(inspected) === F.records(uncertain)

    assert {:unknown, before} =
             call(
               Research,
               "fetch_retain",
               Map.put(args(), "quote", body),
               next,
               :unknown_selector_before
             )

    {not_selected, inspected} = inspect_source(before, Store.provided_transfer_id(body))
    assert not_selected["coverage"]["fetch_version"]["status"] == "historical"
    assert F.records(inspected) === F.records(before)
  end

  test "maximum32 sources plus32 selectors revalidate through existing32-token chunks and bounded actual envelopes" do
    database =
      Enum.reduce(1..32, db(), fn number, db ->
        uri = "fixture:release/" <> Integer.to_string(number)
        prefix = "release version #{number}: "
        body = prefix <> String.duplicate("x", 4096 - byte_size(prefix))

        {:ok, db} =
          F.configure_web(db, %{
            "searches" => %{},
            "pages" => %{
              uri => %{
                "text" => body,
                "observed_uri" => uri,
                "media_type" => "text/plain",
                "observed_at_ms" => 10
              }
            }
          })

        {stored, db} =
          call(
            Research,
            "fetch_retain",
            args()
            |> Map.put("uri", uri)
            |> Map.put("quote", prefix),
            db
          )

        assert stored["status"] == "ok"
        db
      end)

    profile = opts()["stores"]["notes"]

    {{:done, {:ok, snapshot}}, database} =
      store_run(Store.start("notes", profile, :snapshot, %{}), database)

    assert length(snapshot["tokens"]) == 64

    assert {:done, {:error, :invalid_store_arguments, _}} =
             Store.start("notes", profile, :revalidate, %{"tokens" => snapshot["tokens"]})

    initial = Store.start_revalidation("notes", profile, %{"tokens" => snapshot["tokens"]})
    {:call, request, continuation} = initial
    assert byte_size(Jason.encode!(continuation)) > 16_384
    wire = %{"api_version" => 1, "kind" => "host_call", "request" => request}
    assert :ok = Ipse.Extension.validate(wire)

    assert {:error, :invalid_extension_value} =
             Ipse.Extension.validate(
               Map.put(wire, "leaked_continuation", Jason.decode!(Jason.encode!(continuation)))
             )

    {{:done, {:ok, checked}}, database} = store_run(initial, database)
    assert checked["valid"]
    assert checked["coverage"]["reads_used"] == 64

    assert {:done, {:error, :invalid_snapshot, _}} =
             Store.start_revalidation("notes", profile, %{
               "tokens" => snapshot["tokens"] ++ [hd(snapshot["tokens"])]
             })

    {{:done, {:error, :effect_limit, _}}, _} =
      store_run(
        Store.start_revalidation("notes", profile, %{
          "tokens" => snapshot["tokens"],
          "reads_used" => 500
        }),
        database
      )

    {second_chunk, database} =
      Enum.reduce(1..32, {initial, database}, fn _, {{:call, req, cont}, db} ->
        {outcome, db} = F.host(db, req)
        {Store.resume(cont, outcome), db}
      end)

    {_, changed_generation} =
      F.host(database, %{
        "op" => "state.put",
        "scope" => "project",
        "key" => Evidence.sha256("unrelated concurrent write"),
        "expected_revision" => 0,
        "value" => %{"test" => true}
      })

    assert {{:done, {:error, :snapshot_changed, _}}, _} =
             store_run(second_chunk, changed_generation)

    {result, _} =
      call(
        Corpus,
        "query",
        %{
          "store" => "notes",
          "retrieval" => "words",
          "rerank" => nil,
          "query" => "release",
          "top_k" => 10,
          "as_of_ms" => 30
        },
        database
      )

    assert result["status"] == "ok" and length(result["evidence"]) == 10
    assert result["coverage"]["final_validation"]["reads_used"] > 64
    assert Process.get(:max_payload_bytes) <= 16_384
    assert Process.get(:max_reply_bytes) <= 16_384
    overhead = byte_size(Jason.encode!(%{"first" => "", "second" => ""}))

    at_limit = %{
      "first" => String.duplicate("x", 8192),
      "second" => String.duplicate("x", 16_384 - overhead - 8192)
    }

    assert byte_size(Jason.encode!(at_limit)) == 16_384
    assert :ok = Ipse.Extension.validate(at_limit)

    assert {:error, :invalid_extension_value} =
             Ipse.Extension.validate(Map.update!(at_limit, "second", &(&1 <> "x")))

    IO.puts(
      "maximum_fetch_state_envelopes=" <>
        Jason.encode!(%{
          sources: 32,
          tokens: 64,
          max_payload_bytes: Process.get(:max_payload_bytes),
          max_host_reply_bytes: Process.get(:max_reply_bytes)
        })
    )
  end

  test "individually maximal metadata still respects the existing encoded Store value bound" do
    uri = "fixture:" <> String.duplicate("u", 504)
    prefix = "release: "
    body = prefix <> String.duplicate("x", 4096 - byte_size(prefix))

    {:ok, database} =
      F.configure_web(db(), %{
        "searches" => %{},
        "pages" => %{
          uri => %{
            "text" => body,
            "observed_uri" => uri,
            "media_type" => "text/plain",
            "observed_at_ms" => 10
          }
        }
      })

    {refused, after_db} =
      call(
        Research,
        "fetch_retain",
        args()
        |> Map.put("uri", uri)
        |> Map.put("title", String.duplicate("t", 128))
        |> Map.put("quote", binary_part(body, 0, 1024)),
        database
      )

    assert refused["status"] == "refused"
    assert F.records(after_db) == %{}
    refute Enum.any?(F.requests(after_db), &(&1["op"] == "state.put"))
  end

  test "legacy untracked fetches stay historical and forged selector receipt bindings withhold the store" do
    {stored, db} = call(Research, "fetch_retain", args(), db())
    key = stored["coverage"]["selected_version"]["origin_key"]

    root_key =
      Store.root_key(
        opts()["stores"]["notes"]["partition"],
        Evidence.sha256(stored["coverage"]["source_id"])
      )

    legacy =
      %{db | records: Map.delete(db.records, key)}
      |> put_in([:records, root_key, "value", "format"], 1)
      |> update_in(
        [:records, root_key, "value", "origin", "receipt"],
        &(Map.delete(&1, "selection_base_revision") |> Map.put("version", 1))
      )

    {old, _} = inspect_source(legacy, stored["coverage"]["source_id"])
    assert old["coverage"]["fetch_version"] == %{"status" => "untracked"}
    {hidden, _} = query(legacy)
    assert hidden["evidence"] == []
    {select, legacy} = selection_args(legacy, stored["coverage"]["source_id"])
    {refused, unchanged} = call(Research, "select_retained", select, legacy)
    assert refused["status"] == "refused" and F.records(unchanged) === F.records(legacy)

    for field <- ~w(capture_sha256 source_id binding requested_uri) do
      forged = put_in(db, [:records, key, "value", field], "forged")
      {refused, unchanged} = query(forged)
      assert refused["status"] == "refused"
      assert F.records(unchanged) === F.records(forged)
    end
  end

  test "a competing refresh cannot overwrite a newer selector or reclassify its immutable body" do
    {_, db} = call(Research, "fetch_retain", args(), db())
    second = "Babbage owns release after audit."
    db = changed(db, second, 20)

    started =
      Research.handle(
        "invoke.command",
        %{"id" => "fetch_retain", "arguments" => Map.put(args(), "quote", second)},
        start(Research)
      )

    {request, waiting, db} = pause_selector(started, db)
    third = "Charles owns release after audit."

    {newest, db} =
      call(Research, "fetch_retain", Map.put(args(), "quote", third), changed(db, third, 30))

    assert newest["status"] == "ok"
    {outcome, db} = host(db, request)
    assert outcome["status"] == "conflict"

    {refused, db} =
      run(Research, Research.handle("host.actions", %{"outcome" => outcome}, waiting), db, :none)

    assert refused["status"] == "refused"
    {current, _} = query(db)
    assert [evidence] = current["evidence"]
    assert evidence["citation"]["quote"] == third
  end

  test "explicit retained selection recovers a known body without repeating fetch or body publication" do
    commands = Research.describe()["exports"]["commands"]
    assert Enum.any?(commands, &(&1["id"] == "select_retained"))
    refute Enum.any?(Research.describe()["exports"]["tools"], &(&1["id"] == "select_retained"))
    body = "Babbage owns release after audit."

    for mode <- [:deny_selector, :unknown_selector_before] do
      {original, db, id} = unselected(body, 20, mode)

      if mode == :deny_selector,
        do: assert(original["status"] == "refused"),
        else: assert(original == :unknown)

      {select, db} = selection_args(db, id)
      old = F.records(db)
      calls = length(F.requests(db))
      {recovered, db} = call(Research, "select_retained", select, db)
      assert recovered["status"] == "ok"
      assert recovered["coverage"]["selection_status"] == "selected"
      assert recovered["coverage"]["fresh_fetch"] == false
      assert recovered["coverage"]["body_republished"] == false
      assert recovered["coverage"]["native_receipt"] == false
      new_calls = Enum.drop(F.requests(db), calls)
      refute Enum.any?(new_calls, &(&1["op"] == "mcp.call"))
      assert [write] = Enum.filter(new_calls, &(&1["op"] == "state.put"))
      assert write["value"]["kind"] == "fetch_origin"
      changed = Enum.filter(F.records(db), fn {key, row} -> old[key] !== row end)
      assert [{_, %{"value" => %{"kind" => "fetch_origin"}}}] = changed
      {now, _} = query(db)
      assert [evidence] = now["evidence"]
      assert evidence["citation"]["quote"] == body
    end
  end

  test "already-applied unknown selector is observed without replay, body write or settlement" do
    body = "Babbage owns release after audit."
    {:unknown, db, id} = unselected(body, 20, :unknown_selector)
    {select, db} = selection_args(db, id)
    old = F.records(db)
    calls = length(F.requests(db))
    {observed, db} = call(Research, "select_retained", select, db)
    assert observed["status"] == "ok"
    assert observed["coverage"]["selection_status"] == "already_selected"
    assert F.records(db) === old

    refute Enum.any?(
             Enum.drop(F.requests(db), calls),
             &(&1["op"] in ~w(state.put state.delete mcp.call))
           )
  end

  test "host selector base revision rejects later conflicts regardless of skewed gateway time" do
    body = "Babbage owns release after audit."
    {_, db, id} = unselected(body, 5000)
    third = "Charles owns release after audit."

    {newer, db} =
      call(Research, "fetch_retain", Map.put(args(), "quote", third), changed(db, third, 5))

    assert newer["status"] == "ok"
    {select, db} = selection_args(db, id)
    assert select["expected_selection_revision"] == 2
    old = F.records(db)
    {refused, db} = call(Research, "select_retained", select, db)
    assert refused["status"] == "refused" and F.records(db) === old
    future = System.system_time(:millisecond) + 60_000
    {_, db, id} = unselected(body, future)
    {select, db} = selection_args(db, id)
    old = F.records(db)
    {refused, db} = call(Research, "select_retained", select, db)
    assert refused["status"] == "refused" and F.records(db) === old
  end

  test "retained selection checks expiry, tombstones, exact bytes, original binding and fresh revisions" do
    body = "Babbage owns release after audit."
    {_, db, id} = unselected(body, 20)
    {select, db} = selection_args(db, id)
    root_key = Store.root_key(opts()["stores"]["notes"]["partition"], Evidence.sha256(id))

    expired =
      put_in(
        db,
        [:records, root_key, "value", "expires_at_ms"],
        System.system_time(:millisecond) - 1
      )

    for invalid <- [
          expired,
          put_in(db, [:records, root_key, "value", "origin", "receipt", "version"], 2.0),
          put_in(
            db,
            [:records, root_key, "value", "origin", "receipt", "descriptor", "version"],
            1.0
          ),
          put_in(db, [:records, root_key, "value", "content_sha256"], Evidence.sha256("changed")),
          put_in(db, [:records, root_key, "value", "origin", "kind"], "provided"),
          put_in(db, [:records, root_key, "value", "origin", "receipt", "binding"], "other"),
          put_in(
            db,
            [:records, root_key, "value", "origin", "receipt", "requested_uri"],
            "fixture:other"
          ),
          put_in(db, [:records, root_key, "value", "origin", "receipt", "quote"], "fabricated"),
          put_in(
            db,
            [:records, root_key, "value", "origin", "receipt", "selection_base_revision"],
            9
          )
        ] do
      {refused, after_db} = call(Research, "select_retained", select, invalid)
      assert refused["status"] == "refused" and F.records(after_db) === F.records(invalid)
    end

    for invalid <- [
          Map.put(select, "source_revision", select["source_revision"] + 1),
          Map.put(select, "expected_selection_revision", 0),
          Map.put(select, "receipt", %{}),
          Map.put(select, "text", body),
          Map.put(select, "historical_import", %{})
        ] do
      {refused, after_db} = call(Research, "select_retained", invalid, db)
      assert refused["status"] == "refused" and F.records(after_db) === F.records(db)
    end

    {forgotten, suppressed} =
      call(
        Corpus,
        "source",
        %{
          "store" => "notes",
          "action" => "forget",
          "args" => %{"source_id" => id, "expected_revision" => select["source_revision"]}
        },
        db
      )

    assert forgotten["status"] == "ok"

    {refused, after_db} =
      call(
        Research,
        "select_retained",
        %{select | "source_revision" => select["source_revision"] + 1},
        suppressed
      )

    assert refused["status"] == "refused" and F.records(after_db) === F.records(suppressed)
    deadline = System.system_time(:millisecond) + 60_000
    bounded = put_in(db, [:records, root_key, "value", "expires_at_ms"], deadline)
    {selected, bounded} = call(Research, "select_retained", select, bounded)
    assert selected["status"] == "ok"

    [write] =
      Enum.filter(
        F.requests(bounded),
        &(&1["op"] == "state.put" and &1["write_before_ms"] == deadline)
      )

    assert write["value"]["kind"] == "fetch_origin"
  end

  test "new fetched roots are explicitly format2 from claim through tombstone and cannot rewrite their body" do
    body = "Babbage owns release after audit."
    {_, db, id} = unselected(body, 20)
    key = Store.root_key(opts()["stores"]["notes"]["partition"], Evidence.sha256(id))
    root = F.records(db)[key]
    assert root["value"]["format"] == 2
    assert root["value"]["origin"]["receipt"]["version"] == 2
    assert root["value"]["origin"]["receipt"]["selection_base_revision"] == 1
    claims = Enum.filter(F.requests(db), &(&1["op"] == "state.put" and &1["key"] == key))
    assert length(claims) == 2
    assert Enum.all?(claims, &(get_in(&1, ["value", "format"]) == 2))

    for format <- [1, 3, 2.0] do
      invalid = put_in(db, [:records, key, "value", "format"], format)
      {refused, after_db} = query(invalid)
      assert refused["status"] == "refused" and F.records(after_db) === F.records(invalid)
    end

    put = %{
      "source_id" => id,
      "generation" => 2,
      "expected_revision" => root["revision"],
      "title" => "Replacement",
      "text" => "Changed bytes",
      "uri" => @uri,
      "observed_at_ms" => 30,
      "event_at_ms" => nil,
      "expires_at_ms" => nil
    }

    {refused, unchanged} =
      call(Corpus, "source", %{"store" => "notes", "action" => "put", "args" => put}, db)

    assert refused["status"] == "refused" and F.records(unchanged) === F.records(db)

    {forgotten, after_db} =
      call(
        Corpus,
        "source",
        %{
          "store" => "notes",
          "action" => "forget",
          "args" => %{"source_id" => id, "expected_revision" => root["revision"]}
        },
        db
      )

    assert forgotten["status"] == "ok"
    assert F.records(after_db)[key]["value"]["format"] == 2
  end
end

result = ExUnit.run()
System.halt(if result.failures == 0, do: 0, else: 1)
