defmodule IpseKnowledge.Test.CASFixture do
  @moduledoc false

  def new(partition \\ "notes"),
    do: %{
      partition: partition,
      generation: 0,
      records: %{},
      requests: [],
      results: %{},
      barriers: %{},
      seen: MapSet.new()
    }

  def barrier(state, action, mode), do: put_in(state.barriers[action], mode)
  def records(state), do: state.records
  def requests(state), do: Enum.reverse(state.requests)

  def host(state, request) do
    state = %{state | requests: [request | state.requests]}

    case request["op"] do
      "mcp.call" ->
        envelope = request["arguments"]

        action =
          case envelope["contract"] do
            "query-v1" -> "query"
            "search-v1" -> "search"
            "fetch-v1" -> "fetch"
            _ -> envelope["action"]
          end

        mode = state.barriers[action]
        state = %{state | barriers: Map.delete(state.barriers, action)}

        case mode do
          :denied ->
            {%{"status" => "denied", "value" => %{}}, state}

          :unknown ->
            {%{"status" => "unknown", "value" => %{}}, state}

          _ ->
            {reply, state} =
              case action do
                "query" -> query(state, envelope)
                "search" -> search(state, envelope)
                "fetch" -> fetch(state, envelope)
                _ -> handle(state, envelope)
              end

            if mode == :unknown_after do
              {%{"status" => "unknown", "value" => %{}}, state}
            else
              reply =
                case mode do
                  :wrong_partition ->
                    Map.put(reply, "partition", "foreign")

                  :wrong_action ->
                    Map.put(reply, "action", "collect")

                  :wrong_request ->
                    Map.put(reply, "request_id", String.duplicate("0", 32))

                  :drift_generation ->
                    Map.update!(reply, "generation", &(&1 + 1))

                  :partial ->
                    Map.put(reply, "complete", false)

                  :forged_ref ->
                    Map.update!(
                      reply,
                      "refs",
                      &Enum.map(&1, fn ref ->
                        Map.put(ref, "content_sha256", String.duplicate("f", 64))
                      end)
                    )

                  _ ->
                    reply
                end

              reply =
                if action in ~w(search fetch),
                  do:
                    web_mode(
                      reply,
                      action,
                      if(is_atom(mode), do: Atom.to_string(mode), else: mode)
                    ),
                  else: reply

              text = json(reply)
              operation = id32(length(state.requests))

              descriptor = %{
                "version" => 1,
                "operation_id" => operation,
                "kind" => "mcp.text",
                "source_sha256" => sha(text),
                "byte_count" => byte_size(text)
              }

              state =
                put_in(state.results[operation], %{
                  text: text,
                  descriptor: descriptor,
                  corrupt: mode == :corrupt_window
                })

              {%{"status" => "ok", "value" => descriptor}, state}
            end
        end

      "effect.result.read" ->
        result = Map.fetch!(state.results, request["operation_id"])
        offset = request["offset"]

        text =
          prefix(
            binary_part(result.text, offset, byte_size(result.text) - offset),
            request["limit"]
          )

        next = offset + byte_size(text)

        page =
          result.descriptor
          |> Map.drop(["byte_count"])
          |> Map.merge(%{
            "offset" => offset,
            "next" => if(next < byte_size(result.text), do: next),
            "complete" => next == byte_size(result.text),
            "text" => text
          })

        page =
          if result.corrupt,
            do: Map.put(page, "source_sha256", String.duplicate("f", 64)),
            else: page

        {%{"status" => "ok", "value" => page}, state}

      operation when operation in ~w(state.scan state.get state.put state.delete) ->
        state_host(state, request)
    end
  end

  def handle(state, envelope) do
    valid =
      keys?(envelope, ~w(version contract partition request_id action args)) and
        ((envelope["version"] === 1 and envelope["contract"] == "ipse-cas-v1") or
           (envelope["version"] === 2 and envelope["contract"] == "ipse-cas-v2")) and
        envelope["partition"] == state.partition and is_map(envelope["args"]) and
        hash?(envelope["request_id"], 32) and
        not MapSet.member?(state.seen, envelope["request_id"])

    state = %{state | seen: MapSet.put(state.seen, envelope["request_id"])}

    {status, value, next} =
      if valid,
        do: apply_action(state, envelope["action"], envelope["args"], envelope["version"]),
        else: {"refused", %{}, state}

    reply =
      envelope
      |> Map.take(~w(version contract partition request_id action))
      |> Map.merge(%{"status" => status, "generation" => next.generation, "value" => value})

    {reply, next}
  rescue
    _ ->
      {Map.take(envelope, ~w(version contract partition request_id action))
       |> Map.merge(%{"status" => "refused", "generation" => state.generation, "value" => %{}}),
       state}
  end

  def query(state, envelope) do
    valid =
      keys?(envelope, ~w(version contract partition request_id query top_k as_of_ms)) and
        envelope["version"] === 1 and envelope["contract"] == "query-v1" and
        envelope["partition"] == state.partition and
        hash?(envelope["request_id"], 32) and
        not MapSet.member?(state.seen, envelope["request_id"]) and
        is_binary(envelope["query"]) and String.valid?(envelope["query"]) and
        byte_size(envelope["query"]) <= 1024 and
        is_integer(envelope["top_k"]) and envelope["top_k"] in 1..10 and
        is_integer(envelope["as_of_ms"]) and envelope["as_of_ms"] in 0..9_007_199_254_740_991

    state = %{state | seen: MapSet.put(state.seen, envelope["request_id"])}

    roots =
      state.records
      |> Map.values()
      |> Enum.filter(fn row ->
        root = row["value"]

        not row["deleted"] and is_map(root) and root["kind"] == "root" and
          root["partition"] == state.partition and root["state"] == "active"
      end)

    terms =
      if valid,
        do:
          String.split(String.downcase(envelope["query"]), ~r/[^[:alnum:]_]+/u, trim: true)
          |> Enum.uniq(),
        else: []

    chunks =
      if valid,
        do: Enum.flat_map(roots, &query_chunks(state, &1["value"], envelope["as_of_ms"])),
        else: []

    refs =
      for {root, chunk, text} <- chunks,
          score = Enum.count(terms, &String.contains?(String.downcase(text), &1)),
          score > 0,
          do: %{
            "source_id" => root["source_id"],
            "source_key" => root["source_key"],
            "generation" => root["generation"],
            "content_sha256" => root["content_sha256"],
            "chunk_id" => chunk["chunk_id"],
            "score" => score * 1.0
          }

    refs =
      refs
      |> Enum.sort_by(&{-&1["score"], &1["source_key"], &1["chunk_id"]})
      |> Enum.take(if(valid, do: envelope["top_k"], else: 0))

    reply = %{
      "version" => 1,
      "contract" => "query-v1",
      "partition" => envelope["partition"],
      "request_id" => envelope["request_id"],
      "status" => if(valid, do: "ok", else: "refused"),
      "generation" => state.generation,
      "algorithm" => "fixture_terms",
      "algorithm_version" => 1,
      "scanned_sources" => length(roots),
      "scanned_chunks" => length(chunks),
      "complete" => true,
      "refs" => refs
    }

    {reply, state}
  end

  def configure_web(state, spec) do
    with true <-
           keys?(spec, ~w(searches pages)) and is_map(spec["searches"]) and is_map(spec["pages"]),
         true <- map_size(spec["searches"]) <= 8 and map_size(spec["pages"]) <= 8,
         true <-
           Enum.all?(spec["searches"], fn {query, hits} ->
             fixture_text?(query, 1024) and is_list(hits) and length(hits) <= 10 and
               Enum.all?(hits, &fixture_hit?/1)
           end),
         true <-
           Enum.all?(spec["pages"], fn {uri, page} ->
             fixture_text?(uri, 512) and
               keys?(page, ~w(text observed_uri media_type observed_at_ms)) and
               fixture_text?(page["text"], 16384) and fixture_text?(page["observed_uri"], 512) and
               fixture_text?(page["media_type"], 128) and is_integer(page["observed_at_ms"]) and
               page["observed_at_ms"] in 0..9_007_199_254_740_991 and
               byte_size(json(fetch_reply(uri, page, "ok"))) <= 59_000
           end),
         true <- Enum.sum(for {_, page} <- spec["pages"], do: byte_size(page["text"])) <= 49_152 do
      {:ok, state |> Map.put(:web, spec) |> Map.put_new(:web_calls, [])}
    else
      _ -> {:error, :invalid_web_fixture}
    end
  rescue
    _ -> {:error, :invalid_web_fixture}
  end

  def search(state, args) do
    {recorded, state} = record_web(state, "search", args)

    valid =
      recorded and keys?(args, ~w(version contract query limit)) and args["version"] === 1 and
        args["contract"] == "search-v1" and fixture_text?(args["query"], 1024) and
        is_integer(args["limit"]) and args["limit"] in 1..10

    route = if valid, do: get_in(Map.get(state, :web, %{}), ["searches", args["query"]])
    found = is_list(route)

    reply = %{
      "version" => 1,
      "contract" => "search-v1",
      "status" => if(found, do: "ok", else: "refused"),
      "hits" => if(found, do: Enum.take(route, args["limit"]), else: []),
      "coverage" => %{"complete" => found, "kind" => "fixture_exact_query", "configured" => found},
      "next" => nil
    }

    {reply, state}
  end

  def fetch(state, args) do
    {recorded, state} = record_web(state, "fetch", args)

    valid =
      recorded and keys?(args, ~w(version contract uri)) and args["version"] === 1 and
        args["contract"] == "fetch-v1" and fixture_text?(args["uri"], 512)

    page = if valid, do: get_in(Map.get(state, :web, %{}), ["pages", args["uri"]])

    fallback = %{
      "text" => "",
      "observed_uri" =>
        if(fixture_text?(args["uri"], 512), do: args["uri"], else: "fixture:refused"),
      "media_type" => "text/plain",
      "observed_at_ms" => 0
    }

    reply =
      fetch_reply(
        if(fixture_text?(args["uri"], 512), do: args["uri"], else: "fixture:refused"),
        page || fallback,
        if(is_map(page), do: "ok", else: "refused")
      )

    {reply, state}
  end

  defp fetch_reply(uri, page, status),
    do: %{
      "version" => 1,
      "contract" => "fetch-v1",
      "status" => status,
      "requested_uri" => uri,
      "observed_uri" => page["observed_uri"],
      "media_type" => page["media_type"],
      "observed_at_ms" => page["observed_at_ms"],
      "text" => page["text"],
      "body_sha256" => sha(page["text"]),
      "complete" => status == "ok",
      "start_byte" => 0,
      "end_byte" => byte_size(page["text"])
    }

  defp fixture_text?(text, limit),
    do: is_binary(text) and String.valid?(text) and byte_size(text) in 1..limit

  defp fixture_hit?(hit),
    do:
      keys?(hit, ~w(source_id uri title snippet)) and fixture_text?(hit["source_id"], 256) and
        fixture_text?(hit["uri"], 512) and fixture_text?(hit["title"], 128) and
        fixture_text?(hit["snippet"], 1024)

  defp record_web(state, tool, args) do
    calls = Map.get(state, :web_calls, [])

    if length(calls) < 128,
      do: {true, Map.put(state, :web_calls, calls ++ [%{"tool" => tool, "arguments" => args}])},
      else: {false, state}
  end

  defp web_mode(reply, "search", mode) do
    case mode do
      "search_partial" ->
        put_in(reply, ["coverage", "complete"], false)

      "search_forged_hit" ->
        Map.put(reply, "hits", [
          %{
            "source_id" => "forged",
            "uri" => "fixture:forged",
            "title" => "Forged",
            "snippet" => "Forged fixture hit",
            "binding" => "forged"
          }
        ])

      mode when mode in ~w(search_refused deny_search) ->
        reply |> Map.put("status", "refused") |> put_in(["coverage", "complete"], false)

      _ ->
        reply
    end
  end

  defp web_mode(reply, "fetch", mode) do
    case mode do
      "fetch_partial" ->
        Map.put(reply, "complete", false)

      "fetch_changed_body" ->
        reply
        |> Map.put("text", reply["text"] <> " changed")
        |> Map.put("end_byte", byte_size(reply["text"]) + 8)

      "fetch_forged_hash" ->
        Map.put(reply, "body_sha256", sha("forged:" <> reply["text"]))

      "fetch_forged_receipt" ->
        Map.put(reply, "receipt", %{"operation_id" => String.duplicate("0", 32), "native" => true})

      "fetch_wrong_uri" ->
        Map.put(reply, "requested_uri", "fixture:wrong-requested-uri")

      "fetch_future" ->
        Map.put(reply, "observed_at_ms", 9_007_199_254_740_991)

      mode when mode in ~w(fetch_refused deny_fetch) ->
        reply |> Map.put("status", "refused") |> Map.put("complete", false)

      _ ->
        reply
    end
  end

  defp web_mode(reply, _, _), do: reply

  defp query_chunks(state, root, now) do
    if root["observed_at_ms"] <= now and
         (root["expires_at_ms"] == nil or root["expires_at_ms"] > now) and
         not root["origin"]["historical"] do
      text = fixture_text(state, root["content_ref"], MapSet.new())

      chunks =
        Enum.flat_map(root["chunks_ref"], fn ref ->
          get_in(state.records, [ref["key"], "value", "body", "chunks"])
        end)

      if sha(text) == root["content_sha256"],
        do:
          Enum.map(chunks, fn chunk ->
            {root, chunk,
             binary_part(text, chunk["start_byte"], chunk["end_byte"] - chunk["start_byte"])}
          end),
        else: []
    else
      []
    end
  rescue
    _ -> []
  end

  defp fixture_text(_state, nil, _seen), do: ""

  defp fixture_text(state, ref, seen) do
    if MapSet.member?(seen, ref["key"]) or MapSet.size(seen) >= 128,
      do: raise("invalid fixture progress")

    page = state.records[ref["key"]]["value"]
    true = ref["sha256"] == digest("page-record", [ordered(page)])
    body = page["body"]

    fixture_text(state, body["previous"], MapSet.put(seen, ref["key"])) <>
      Enum.map_join(body["pieces"], fn piece ->
        row = state.records[piece["key"]]["value"]
        true = piece["sha256"] == digest("page-record", [ordered(row)])
        row["body"]["text"]
      end)
  end

  defp apply_action(state, "cas_root", args, version), do: root_cas(state, args, version)
  defp apply_action(state, action, args, _version), do: apply_action(state, action, args)

  defp apply_action(state, "snapshot", args) when map_size(args) == 0 do
    rows =
      state.records
      |> Map.values()
      |> Enum.sort_by(& &1["key"])
      |> Enum.map(fn row ->
        row
        |> Map.take(~w(key revision deleted))
        |> Map.put("kind", if(row["deleted"], do: "tombstone", else: row["value"]["kind"]))
      end)

    {"ok",
     %{
       "records" => rows,
       "count" => length(rows),
       "bytes" => byte_size(json(state.records)),
       "complete" => true
     }, state}
  end

  defp apply_action(state, "get_many", %{"keys" => keys} = args) do
    if keys?(args, ["keys"]) and is_list(keys) and length(keys) in 1..8 and
         Enum.all?(keys, &hash?(&1, 64)) do
      {"ok", %{"records" => Enum.map(keys, &record(state, &1)), "complete" => true}, state}
    else
      {"refused", %{}, state}
    end
  end

  defp apply_action(state, "put_immutable_many", %{"pages" => pages} = args) do
    valid =
      keys?(args, ["pages"]) and is_list(pages) and length(pages) in 1..2 and
        length(Enum.uniq_by(pages, & &1["key"])) == length(pages) and
        Enum.all?(pages, fn p ->
          keys?(p, ~w(key value expected_revision)) and p["expected_revision"] === 0 and
            not Map.has_key?(state.records, p["key"]) and valid_page?(p, state)
        end)

    if valid do
      rows =
        Enum.map(pages, fn p ->
          %{"key" => p["key"], "revision" => 1, "deleted" => false, "value" => p["value"]}
        end)

      next = %{
        state
        | records: Enum.reduce(rows, state.records, &Map.put(&2, &1["key"], &1)),
          generation: state.generation + 1
      }

      if quota?(next), do: {"ok", %{"records" => rows}, next}, else: {"refused", %{}, state}
    else
      {"refused", %{}, state}
    end
  end

  defp apply_action(
         state,
         "collect",
         %{"keys" => keys, "snapshot_generation" => generation} = args
       ) do
    protected = protected(state)

    cond do
      not keys?(args, ~w(keys snapshot_generation)) or not is_list(keys) or
        length(keys) not in 1..12 or length(Enum.uniq(keys)) != length(keys) ->
        {"refused", %{}, state}

      generation != state.generation ->
        {"conflict", %{}, state}

      not Enum.all?(keys, fn key ->
        row = record(state, key)

        not row["deleted"] and row["value"]["kind"] == "page" and
            not MapSet.member?(protected, key)
      end) ->
        {"refused", %{}, state}

      true ->
        rows =
          Enum.map(keys, fn key ->
            row = record(state, key)
            %{row | "revision" => row["revision"] + 1, "deleted" => true, "value" => nil}
          end)

        next = %{
          state
          | records: Enum.reduce(rows, state.records, &Map.put(&2, &1["key"], &1)),
            generation: state.generation + 1
        }

        {"ok", %{"records" => rows}, next}
    end
  end

  defp apply_action(state, _, _), do: {"refused", %{}, state}

  defp root_cas(state, args, version) do
    key = args["key"]
    root = args["next_root"]
    old = record(state, key)

    fields =
      ~w(key expected_revision expected_source_generation expected_content_sha256 draft_id next_root)

    fields = if version == 2, do: ["expected_generation" | fields], else: fields

    valid =
      keys?(args, fields) and hash?(key, 64) and is_map(root) and
        (version == 1 or
           ((args["expected_generation"] == nil or uint?(args["expected_generation"])) and
              (old["revision"] > 0 or uint?(args["expected_generation"])))) and
        root["kind"] == "root" and root["partition"] == state.partition and
        byte_size(json(root)) <= 6000 and
        key == digest("root", [state.partition, root["source_key"]])

    cond do
      not valid ->
        {"refused", %{}, state}

      version == 2 and old["deleted"] and old["revision"] > 0 ->
        {"refused", %{}, state}

      old["revision"] != args["expected_revision"] ->
        root_conflict(state, old, version)

      version == 2 and args["expected_generation"] != nil and
          args["expected_generation"] != state.generation ->
        root_conflict(state, old, version)

      args["expected_source_generation"] != get_in(old, ["value", "generation"]) or
        args["expected_content_sha256"] != get_in(old, ["value", "content_sha256"]) or
          args["draft_id"] != get_in(old, ["value", "draft", "id"]) ->
        root_conflict(state, old, version)

      old["value"] && old["value"]["state"] == "suppressed" ->
        {"refused", %{}, state}

      not selected_refs?(root, state.records) ->
        {"refused", %{}, state}

      true ->
        row = %{
          "key" => key,
          "revision" => old["revision"] + 1,
          "deleted" => false,
          "value" => root
        }

        next = %{
          state
          | records: Map.put(state.records, key, row),
            generation: state.generation + 1
        }

        if quota?(next), do: {"ok", %{"record" => row}, next}, else: {"refused", %{}, state}
    end
  end

  defp root_conflict(state, _old, 1), do: {"conflict", %{}, state}

  defp root_conflict(state, old, 2) do
    summary = %{
      "key" => old["key"],
      "revision" => old["revision"],
      "deleted" => old["deleted"],
      "source_generation" => get_in(old, ["value", "generation"]),
      "content_sha256" => get_in(old, ["value", "content_sha256"]),
      "draft_id" => get_in(old, ["value", "draft", "id"])
    }

    {"conflict", %{"record" => summary}, state}
  end

  defp state_host(state, request) do
    operation = request["op"]
    key = request["key"]
    old = state_record(state, key)

    case operation do
      "state.scan" ->
        if request["generation"] == nil or request["generation"] == state.generation do
          keys =
            state.records
            |> Map.keys()
            |> Enum.sort()
            |> Enum.filter(&(request["after"] == nil or &1 > request["after"]))

          rows =
            keys
            |> Enum.take(request["limit"])
            |> Enum.reduce_while([], fn key, rows ->
              next = rows ++ [state_record(state, key)]
              if byte_size(json(next)) <= 12000, do: {:cont, next}, else: {:halt, rows}
            end)

          {%{
             "status" => "ok",
             "value" => %{
               "generation" => state.generation,
               "records" => rows,
               "next" => if(length(keys) > length(rows), do: List.last(rows)["key"])
             }
           }, state}
        else
          {%{"status" => "conflict", "value" => %{}}, state}
        end

      "state.get" ->
        {%{"status" => "ok", "value" => %{"generation" => state.generation, "record" => old}},
         state}

      _ ->
        cond do
          Map.has_key?(request, "expected_generation") and
              not uint?(request["expected_generation"]) ->
            {%{"status" => "denied", "value" => %{}}, state}

          old["revision"] != request["expected_revision"] ->
            {%{"status" => "conflict", "value" => %{}}, state}

          Map.has_key?(request, "expected_generation") and
              request["expected_generation"] != state.generation ->
            {%{"status" => "conflict", "value" => %{}}, state}

          true ->
            row = %{
              "key" => key,
              "revision" => old["revision"] + 1,
              "deleted" => operation == "state.delete",
              "value" => if(operation == "state.put", do: request["value"]),
              "operation_id" => id32(length(state.requests))
            }

            next = %{
              state
              | records: Map.put(state.records, key, row),
                generation: state.generation + 1
            }

            if quota?(next) and (row["deleted"] or byte_size(json(row["value"])) <= 6000),
              do:
                {%{
                   "status" => "ok",
                   "value" => %{"generation" => next.generation, "record" => row}
                 }, next},
              else: {%{"status" => "denied", "value" => %{}}, state}
        end
    end
  end

  defp state_record(state, key),
    do:
      Map.put_new(
        record(state, key),
        "operation_id",
        if(Map.has_key?(state.records, key), do: id32(1))
      )

  defp record(state, key),
    do:
      Map.get(state.records, key, %{
        "key" => key,
        "revision" => 0,
        "deleted" => true,
        "value" => nil
      })

  defp valid_page?(%{"key" => key, "value" => p}, state) do
    root =
      Enum.find(Map.values(state.records), fn row ->
        value = row["value"]

        is_map(value) and value["kind"] == "root" and value["source_key"] == p["source_key"] and
          value["state"] != "suppressed" and is_map(value["draft"]) and
          value["draft"]["id"] == p["draft_id"]
      end)

    is_map(root) and
      p["generation"] ==
        (get_in(root, ["value", "draft", "target", "generation"]) ||
           get_in(root, ["value", "generation"])) and
      keys?(
        p,
        ~w(format kind partition source_key generation draft_id page_kind ordinal body body_sha256)
      ) and p["format"] === 1 and p["kind"] == "page" and p["partition"] == state.partition and
      byte_size(json(p)) <= 6000 and
      p["body_sha256"] == digest("page-body", [p["page_kind"], ordered(p["body"])]) and
      key ==
        digest("page", [
          p["partition"],
          p["source_key"],
          p["generation"],
          p["draft_id"],
          p["page_kind"],
          p["ordinal"],
          p["body_sha256"]
        ])
  end

  defp selected_refs?(root, records) do
    selected = verify_refs(Map.drop(root, ["draft"]), records, root, MapSet.new())
    draft = root["draft"]

    owner =
      if is_map(draft) and is_map(draft["target"]),
        do: Map.put(root, "generation", draft["target"]["generation"]),
        else: root

    selected and
      (not is_map(draft) or verify_refs(draft["progress"], records, owner, MapSet.new()))
  end

  defp verify_refs(value, records, owner, seen) do
    MapSet.size(seen) <= 256 and
      Enum.all?(refs(value), fn ref ->
        row = records[ref["key"]]

        is_map(row) and not row["deleted"] and row["revision"] == 1 and
          Enum.all?(~w(partition source_key generation), &(row["value"][&1] == owner[&1])) and
          ref["sha256"] == digest("page-record", [ordered(row["value"])]) and
          (MapSet.member?(seen, ref["key"]) or
             verify_refs(row["value"], records, owner, MapSet.put(seen, ref["key"])))
      end)
  end

  defp protected(state) do
    roots =
      Enum.filter(Map.values(state.records), fn r ->
        not r["deleted"] and r["value"]["kind"] == "root"
      end)

    Enum.reduce(roots, MapSet.new(), fn row, acc ->
      root = row["value"]
      acc = walk_refs(root, state.records, acc)

      if is_map(root["draft"]),
        do:
          Enum.reduce(state.records, acc, fn {key, r}, set ->
            if is_map(r["value"]) and r["value"]["draft_id"] == root["draft"]["id"],
              do: MapSet.put(set, key),
              else: set
          end),
        else: acc
    end)
  end

  defp walk_refs(value, records, seen),
    do:
      Enum.reduce(refs(value), seen, fn ref, seen ->
        if MapSet.member?(seen, ref["key"]),
          do: seen,
          else:
            walk_refs(
              get_in(records, [ref["key"], "value"]),
              records,
              MapSet.put(seen, ref["key"])
            )
      end)

  defp refs(map) when is_map(map),
    do: if(keys?(map, ~w(key sha256)), do: [map], else: Enum.flat_map(Map.values(map), &refs/1))

  defp refs(list) when is_list(list), do: Enum.flat_map(list, &refs/1)
  defp refs(_), do: []

  defp quota?(state),
    do:
      map_size(state.records) <= 256 and
        byte_size(
          json(%{
            "version" => 1,
            "namespace" => String.duplicate("0", 64),
            "generation" => state.generation,
            "records" => state.records
          })
        ) <= 1_048_576

  defp prefix(text, limit) do
    part = binary_part(text, 0, min(byte_size(text), limit))
    if String.valid?(part), do: part, else: prefix(text, byte_size(part) - 1)
  end

  defp ordered(map) when is_map(map),
    do: ["map", map |> Enum.sort() |> Enum.map(fn {k, v} -> [k, ordered(v)] end)]

  defp ordered(list) when is_list(list), do: ["list", Enum.map(list, &ordered/1)]
  defp ordered(value), do: value
  defp digest(tag, parts), do: sha(json(["ipse-knowledge", 1, tag, parts]))
  defp sha(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp id32(value),
    do: value |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")

  defp hash?(value, n),
    do: is_binary(value) and Regex.match?(Regex.compile!("\\A[0-9a-f]{#{n}}\\z"), value)

  defp uint?(value), do: is_integer(value) and value in 0..9_007_199_254_740_991
  defp keys?(value, fields), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(fields)
  defp json(value), do: JSON.encode!(value) |> IO.iodata_to_binary()

  def schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "version" => %{"type" => "integer"},
        "contract" => %{"type" => "string"},
        "partition" => %{"type" => "string"},
        "request_id" => %{"type" => "string"},
        "action" => %{"type" => "string"},
        "args" => %{"type" => "object"}
      },
      "required" => ~w(version contract partition request_id action args)
    }
  end

  def start_backend(partition \\ "notes") do
    case GenServer.start(__MODULE__.Backend, {self(), partition}) do
      {:ok, pid} -> {:ok, %{pid: pid, port: GenServer.call(pid, :port), partition: partition}}
      other -> other
    end
  end

  def backend_state(%{pid: pid}), do: GenServer.call(pid, :snapshot)
  def configure_web_backend(%{pid: pid}, spec), do: GenServer.call(pid, {:configure_web, spec})

  def stop_backend(%{pid: pid}) do
    monitor = Process.monitor(pid)

    try do
      GenServer.stop(pid, :normal, 5000)
    catch
      :exit, _ -> :ok
    end

    receive do
      {:DOWN, ^monitor, :process, ^pid, _} -> :ok
    after
      1000 ->
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^monitor, :process, ^pid, _} -> :ok
        after
          1000 -> {:error, :fixture_stop_timeout}
        end
    end
  end

  def backend_request(port, partition, tool, arguments, mode \\ "normal")
      when is_integer(port) and port in 1..65535 and tool in ~w(cas query search fetch) do
    wrapper = %{
      "version" => 1,
      "partition" => partition,
      "tool" => tool,
      "arguments" => arguments
    }

    wrapper = if mode == "fetch_current", do: Map.put(wrapper, "mode", mode), else: wrapper
    request = json(wrapper)

    true = byte_size(request) <= 32_768

    {:ok, socket} =
      :gen_tcp.connect(
        {127, 0, 0, 1},
        port,
        [:binary, packet: 4, packet_size: 60_000, active: false],
        2000
      )

    try do
      :ok = :gen_tcp.send(socket, request)
      {:ok, bytes} = :gen_tcp.recv(socket, 0, 5000)
      true = byte_size(bytes) <= 60_000
      JSON.decode!(bytes)
    after
      :gen_tcp.close(socket)
    end
  end

  def web_stdio_config(partition \\ "notes", mode \\ "normal", backend_port \\ nil),
    do: stdio_config(partition, mode, backend_port, "web")

  def stdio_config(
        partition \\ "notes",
        mode \\ "normal",
        backend_port \\ nil,
        toolset \\ "store"
      ) do
    runtime = to_string(:code.root_dir())
    erl = Path.join([runtime, "erts-" <> to_string(:erlang.system_info(:version)), "bin", "erl"])

    current =
      case :init.get_argument(:boot) do
        {:ok, [[path]]} ->
          path = List.to_string(path)

          if Path.type(path) == :absolute and
               String.starts_with?(Path.expand(path), Path.join(runtime, "releases") <> "/"),
             do: Path.join(Path.dirname(path), "start_clean")

        _ ->
          nil
      end

    boot =
      Enum.find(
        [current, Path.join([runtime, "bin", "no_dot_erlang"])],
        &(is_binary(&1) and File.regular?(&1 <> ".boot"))
      ) || raise "No clean bundled runtime boot file"

    term = fn value -> :io_lib.format(~c"~p", [value]) |> IO.iodata_to_binary() end

    expression =
      "application:ensure_all_started(elixir), 'Elixir.Code':require_file(" <>
        term.(__ENV__.file) <>
        "), 'Elixir.IpseKnowledge.Test.CASFixture':stdio(" <>
        term.(partition) <>
        ", " <>
        term.(mode) <> ", " <> term.(backend_port) <> ", " <> term.(toolset) <> "), init:stop()."

    %{
      "id" => "knowledge_cas",
      "command" => erl,
      "args" => [
        "+S",
        "1:1",
        "+A",
        "1",
        "-noshell",
        "-boot",
        boot,
        "-boot_var",
        "RELEASE_LIB",
        Path.join(runtime, "lib"),
        "-pa",
        Application.app_dir(:elixir, "ebin"),
        "-eval",
        expression
      ],
      "tools" => if(toolset == "web", do: ["search", "fetch"], else: ["cas", "query"]),
      "timeout_ms" => 5000
    }
  end

  def stdio(partition \\ "notes", mode \\ "normal", backend_port \\ nil, toolset \\ "store") do
    :ok = :io.setopts(:standard_io, binary: true, encoding: :latin1)

    loop(
      Map.merge(new(partition), %{stdio_mode: mode, backend_port: backend_port, toolset: toolset})
    )
  end

  def query_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "version" => %{"type" => "integer"},
        "contract" => %{"type" => "string"},
        "partition" => %{"type" => "string"},
        "request_id" => %{"type" => "string"},
        "query" => %{"type" => "string"},
        "top_k" => %{"type" => "integer"},
        "as_of_ms" => %{"type" => "integer"}
      },
      "required" => ~w(version contract partition request_id query top_k as_of_ms)
    }
  end

  def search_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "version" => %{"type" => "integer", "enum" => [1]},
        "contract" => %{"type" => "string", "enum" => ["search-v1"]},
        "query" => %{"type" => "string", "minLength" => 1, "maxLength" => 1024},
        "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 10}
      },
      "required" => ~w(version contract query limit)
    }
  end

  def fetch_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "version" => %{"type" => "integer", "enum" => [1]},
        "contract" => %{"type" => "string", "enum" => ["fetch-v1"]},
        "uri" => %{"type" => "string", "minLength" => 1, "maxLength" => 512}
      },
      "required" => ~w(version contract uri)
    }
  end

  defp loop(state) do
    case IO.binread(:stdio, :line) do
      line when is_binary(line) ->
        rpc = JSON.decode!(line)

        {result, state} =
          case rpc["method"] do
            "initialize" ->
              {%{
                 "protocolVersion" => rpc["params"]["protocolVersion"],
                 "capabilities" => %{"tools" => %{}},
                 "serverInfo" => %{"name" => "independent-cas", "version" => "1"}
               }, state}

            "tools/list" ->
              if state.toolset == "web" do
                {%{
                   "tools" => [
                     %{
                       "name" => "search",
                       "description" => "Independent exact-query search fixture",
                       "inputSchema" => search_schema()
                     },
                     %{
                       "name" => "fetch",
                       "description" => "Independent captured-text fetch fixture",
                       "inputSchema" => fetch_schema()
                     }
                   ]
                 }, state}
              else
                {%{
                   "tools" => [
                     %{
                       "name" => "cas",
                       "description" => "Partitioned immutable evidence CAS fixture",
                       "inputSchema" => schema()
                     },
                     %{
                       "name" => "query",
                       "description" => "Independent selected-reference query fixture",
                       "inputSchema" => query_schema()
                     }
                   ]
                 }, state}
              end

            "tools/call" ->
              is_query = rpc["params"]["name"] == "query"
              tool = rpc["params"]["name"]

              if tool in ~w(search fetch) and state.stdio_mode == "hold_" <> tool do
                IO.binwrite(:stdio, [
                  json(%{
                    "jsonrpc" => "2.0",
                    "method" => "notifications/message",
                    "params" => %{"level" => "info", "data" => tool <> " barrier entered"}
                  }),
                  "\n"
                ])

                receive do: (:release_fixture -> :ok)
              end

              if state.stdio_mode == "hold_query" and is_query do
                IO.binwrite(:stdio, [
                  json(%{
                    "jsonrpc" => "2.0",
                    "method" => "notifications/message",
                    "params" => %{"level" => "info", "data" => "query barrier entered"}
                  }),
                  "\n"
                ])

                receive do: (:release_fixture -> :ok)
              end

              if state.stdio_mode == "hold_cas" and
                   rpc["params"]["arguments"]["action"] == "cas_root" do
                IO.binwrite(:stdio, [
                  json(%{
                    "jsonrpc" => "2.0",
                    "method" => "notifications/message",
                    "params" => %{"level" => "info", "data" => "cas_root barrier entered"}
                  }),
                  "\n"
                ])

                receive do: (:release_fixture -> :ok)
              end

              {reply, state} =
                cond do
                  state.backend_port != nil ->
                    {backend_request(
                       state.backend_port,
                       state.partition,
                       rpc["params"]["name"],
                       rpc["params"]["arguments"],
                       state.stdio_mode
                     ), state}

                  is_query ->
                    query(state, rpc["params"]["arguments"])

                  tool == "search" ->
                    search(state, rpc["params"]["arguments"])

                  tool == "fetch" ->
                    fetch(state, rpc["params"]["arguments"])

                  true ->
                    handle(state, rpc["params"]["arguments"])
                end

              if state.stdio_mode == "disconnect_after_cas" and
                   rpc["params"]["arguments"]["action"] == "cas_root",
                 do: System.halt(0)

              if state.stdio_mode == "disconnect_after_query" and is_query, do: System.halt(0)

              if tool in ~w(search fetch) and state.stdio_mode == "disconnect_after_" <> tool,
                do: System.halt(0)

              reply =
                if is_query do
                  case state.stdio_mode do
                    "query_wrong_partition" ->
                      Map.put(reply, "partition", "foreign")

                    "query_partial" ->
                      Map.put(reply, "complete", false)

                    "query_empty" ->
                      Map.put(reply, "refs", [])

                    "query_forged_hash" ->
                      Map.update!(
                        reply,
                        "refs",
                        &Enum.map(&1, fn ref ->
                          Map.put(ref, "content_sha256", String.duplicate("f", 64))
                        end)
                      )

                    "query_stale_generation" ->
                      Map.update!(reply, "generation", &(&1 + 1))

                    _ ->
                      reply
                  end
                else
                  web_mode(reply, tool, state.stdio_mode)
                end

              {%{"content" => [%{"type" => "text", "text" => json(reply)}], "isError" => false},
               state}

            _ ->
              {%{}, state}
          end

        if rpc["id"] != nil,
          do:
            IO.binwrite(:stdio, [
              json(%{"jsonrpc" => "2.0", "id" => rpc["id"], "result" => result}),
              "\n"
            ])

        loop(state)

      _ ->
        :ok
    end
  end
end

defmodule IpseKnowledge.Test.CASFixture.Backend do
  @moduledoc false
  use GenServer
  alias IpseKnowledge.Test.CASFixture, as: F

  @impl true
  def init({owner, partition}) do
    Process.flag(:trap_exit, true)
    owner_ref = Process.monitor(owner)

    case :gen_tcp.listen(0, [
           :binary,
           packet: 4,
           packet_size: 32_768,
           active: false,
           ip: {127, 0, 0, 1},
           reuseaddr: true,
           backlog: 8
         ]) do
      {:ok, listener} ->
        {:ok, {_, port}} = :inet.sockname(listener)
        server = self()
        acceptor = spawn_link(fn -> accept(listener, server) end)

        {:ok,
         %{
           owner_ref: owner_ref,
           listener: listener,
           acceptor: acceptor,
           port: port,
           db: Map.put(F.new(partition), :web_calls, [])
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:port, _from, state), do: {:reply, state.port, state}
  def handle_call(:snapshot, _from, state), do: {:reply, state.db, state}

  def handle_call({:configure_web, spec}, _from, state) do
    case F.configure_web(state.db, spec) do
      {:ok, db} -> {:reply, :ok, %{state | db: db}}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:request, request}, _from, state) do
    if is_map(request) and
         Enum.sort(Map.keys(Map.drop(request, ["mode"]))) ==
           Enum.sort(~w(version partition tool arguments)) and
         Map.get(request, "mode", "normal") in ~w(normal fetch_current) and
         request["version"] === 1 and request["partition"] == state.db.partition and
         request["tool"] in ~w(cas query search fetch) and is_map(request["arguments"]) do
      arguments = request["arguments"]

      db = %{
        state.db
        | requests: [
            %{"op" => "mcp.call", "arguments" => arguments, "fixture_tool" => request["tool"]}
            | state.db.requests
          ]
      }

      {reply, db} =
        case request["tool"] do
          "cas" -> F.handle(db, arguments)
          "query" -> F.query(db, arguments)
          "search" -> F.search(db, arguments)
          "fetch" -> F.fetch(db, arguments)
        end

      reply =
        if request["tool"] == "fetch" and request["mode"] == "fetch_current" and
             reply["status"] == "ok",
           do: Map.put(reply, "observed_at_ms", System.system_time(:millisecond)),
           else: reply

      {:reply, JSON.encode!(reply), %{state | db: db}}
    else
      {:reply, JSON.encode!(%{"fixture_error" => "invalid_request"}), state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _, _}, %{owner_ref: ref} = state),
    do: {:stop, :normal, state}

  def handle_info({:EXIT, pid, reason}, %{acceptor: pid} = state),
    do: {:stop, {:acceptor_exit, reason}, state}

  @impl true
  def terminate(_reason, state) do
    :gen_tcp.close(state.listener)
    ref = Process.monitor(state.acceptor)
    Process.exit(state.acceptor, :kill)

    receive do
      {:DOWN, ^ref, :process, _, _} -> :ok
    after
      1000 -> Process.demonitor(ref, [:flush])
    end

    :ok
  end

  defp accept(listener, server) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        try do
          with {:ok, bytes} <- :gen_tcp.recv(socket, 0, 5000),
               true <- byte_size(bytes) <= 32_768 do
            response = GenServer.call(server, {:request, JSON.decode!(bytes)}, 5000)
            if byte_size(response) <= 60_000, do: :gen_tcp.send(socket, response)
          end
        rescue
          _ -> :ok
        catch
          :exit, _ -> :ok
        after
          :gen_tcp.close(socket)
        end

        accept(listener, server)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        exit({:accept_failed, reason})
    end
  end
end
