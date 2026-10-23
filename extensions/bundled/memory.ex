defmodule Ipse.Builtins.Memory do
  @moduledoc "Default-off explicit note tools implemented entirely through the public state SDK."
  @behaviour Ipse.Extension
  alias Ipse.Builtins.Memory.Records
  alias Ipse.JSON, as: Schema

  @caps ~w(invoke.tool invoke.command host.actions host.state.read host.state.scan host.state.write)
  @revision %{"type" => "integer", "minimum" => 0, "maximum" => 9_007_199_254_740_991}
  @source %{"type" => "string", "minLength" => 1, "maxLength" => 512}

  def capabilities, do: @caps

  def options_schema(scopes) do
    object(~w(scope retention_seconds), %{
      "scope" => %{"type" => "string", "enum" => scopes},
      "retention_seconds" => %{"type" => "integer", "minimum" => 60, "maximum" => 31_536_000}
    })
  end

  def exports do
    source_revision = %{"source" => @source, "expected_revision" => @revision}

    note_properties =
      Records.schema()["properties"]
      |> Map.take(~w(source source_generation title text kind provenance derived_from))

    remember =
      Map.merge(note_properties, %{
        "expected_revision" => @revision,
        "ttl_seconds" => %{"type" => "integer", "minimum" => 1, "maximum" => 31_536_000}
      })

    page = %{
      "after" => %{"type" => ["string", "null"], "minLength" => 64, "maxLength" => 64},
      "generation" => %{
        "type" => ["integer", "null"],
        "minimum" => 0,
        "maximum" => 9_007_199_254_740_991
      },
      "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 16}
    }

    export_page =
      Map.put(page, "sources", %{
        "type" => "array",
        "minItems" => 1,
        "maxItems" => 16,
        "items" => @source
      })

    tools = [
      descriptor(
        "remember",
        "Store a sourced note; each write needs separate approval.",
        object(
          ~w(source source_generation title text kind provenance expected_revision),
          remember
        )
      ),
      descriptor(
        "recall",
        "Recall live lexical excerpts with source, revision and span.",
        object(["query"], %{
          "query" => %{"type" => "string", "minLength" => 1, "maxLength" => 256},
          "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 5}
        })
      ),
      descriptor(
        "forget",
        "Suppress this source and derived recall; transcripts remain.",
        object(~w(source expected_revision), source_revision)
      ),
      descriptor(
        "inspect",
        "Read an eligible note; hidden notes expose metadata only.",
        object(["source"], %{"source" => @source})
      )
    ]

    commands = [
      descriptor(
        "export",
        "Export one bounded generation-pinned page including suppression records.",
        object([], export_page)
      ),
      descriptor(
        "inventory",
        "List one bounded page of note/derivative metadata, including expired and suppressed entries.",
        object([], page)
      ),
      descriptor(
        "import",
        "Explicitly merge one exported record; suppression wins and stale generations refuse.",
        object(~w(key value expected_revision), %{
          "key" => Records.schema()["properties"]["source_sha256"],
          "value" => Records.schema(),
          "expected_revision" => @revision
        })
      ),
      descriptor(
        "collect",
        "Suppress an expired note or a derivative of a suppressed/expired cause_source. Journals and backups remain.",
        object(~w(source expected_revision), Map.put(source_revision, "cause_source", @source))
      ),
      descriptor(
        "migrate",
        "Explicitly migrate one version-one note to version two without changing its expiry or suppression.",
        object(~w(source expected_revision), source_revision)
      )
    ]

    %{
      "version" => 1,
      "tools" => tools,
      "commands" => Enum.take(tools, 3) ++ commands,
      "services" => []
    }
  end

  defp descriptor(id, description, schema),
    do: %{
      "id" => id,
      "description" => description,
      "arguments_schema" => schema,
      "result_schema" => %{"type" => "object"}
    }

  defp object(required, properties),
    do: %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => required,
      "properties" => properties
    }

  @impl true
  def describe,
    do: %{"sdk" => 1, "capabilities" => ["host.state.bound" | @caps], "exports" => exports()}

  @impl true
  def init(options), do: initialize(options, ~w(project operator))

  def initialize(options, scopes) do
    case Schema.validate_arguments(options_schema(scopes), options) do
      :ok -> {:ok, %{options: options}}
      _ -> {:error, :invalid_memory_options}
    end
  end

  @impl true
  def handle(stage, %{"id" => id, "arguments" => args}, state)
      when stage in ~w(invoke.tool invoke.command) do
    group = if stage == "invoke.tool", do: "tools", else: "commands"
    descriptor = Enum.find(exports()[group], &(&1["id"] == id))

    with true <- descriptor != nil,
         :ok <- Schema.validate_arguments(descriptor["arguments_schema"], args),
         :ok <- Ipse.Extension.validate(args) do
      state =
        Map.merge(state, %{
          id: id,
          args: args,
          now: System.system_time(:millisecond),
          phase: :read
        })

      if id in ~w(recall export inventory),
        do: scan(Map.put(state, :records, []), nil, Map.get(args, "generation")),
        else:
          call(
            %{
              "op" => "state.get",
              "scope" => state.options["scope"],
              "key" => if(id == "import", do: args["key"], else: Records.key(args["source"]))
            },
            state
          )
    else
      _ -> result(%{"status" => "invalid_arguments"}, state)
    end
  end

  def handle(
        "host.actions",
        %{"outcome" => %{"status" => "ok", "value" => value}},
        %{phase: :write} = state
      ) do
    result(
      %{
        "status" => "stored",
        "key" => value["record"]["key"],
        "revision" => value["record"]["revision"],
        "generation" => value["generation"],
        "state" => value["record"]["value"]["state"],
        "retained_history" => true,
        "affected_session_policy" =>
          "close_sessions_with_prior_recall_then_start_fresh_without_importing_forgotten_text"
      },
      state
    )
  end

  def handle(
        "host.actions",
        %{
          "outcome" => %{
            "status" => "failed",
            "value" => %{"code" => "write_deadline_elapsed"} = details
          }
        },
        %{phase: :write, id: id} = state
      )
      when id in ~w(remember import),
      do: result(%{"status" => "source_expired", "details" => details}, state)

  def handle(
        "host.actions",
        %{"outcome" => %{"status" => "ok", "value" => page}},
        %{phase: :scan, id: id} = state
      )
      when id in ~w(recall export inventory inspect) do
    if Enum.all?(page["records"], &valid_record?/1) do
      records = state.records ++ page["records"]

      state =
        if page["next"] == nil,
          do: %{state | now: System.system_time(:millisecond)},
          else: state

      cond do
        page["next"] != nil ->
          scan(%{state | records: records}, page["next"], page["generation"])

        id == "inspect" ->
          record = state.inspect_record

          visible =
            Records.visible?(record["value"], state.now) and
              Enum.any?(exclude_derivatives(records, state.now), &(&1["key"] == record["key"]))

          record =
            if visible,
              do: record,
              else: Map.update!(record, "value", &Map.drop(&1, ~w(text title provenance)))

          result(
            %{
              "status" => "inspected",
              "record" => record,
              "visibility" => if(visible, do: "full", else: "metadata_only"),
              "generation" => page["generation"],
              "as_of_ms" => state.now
            },
            state
          )

        id == "recall" ->
          visible = exclude_derivatives(records, state.now)

          result(
            %{
              "status" => "recalled",
              "generation" => page["generation"],
              "matches" =>
                Records.recall(
                  visible,
                  state.args["query"],
                  Map.get(state.args, "limit", 5),
                  state.now
                ),
              "scanned" => length(records),
              "as_of_ms" => state.now
            },
            state
          )

        id == "export" ->
          records =
            if state.args["sources"],
              do:
                Enum.filter(
                  records,
                  &(&1["key"] in Enum.map(state.args["sources"], fn source ->
                      Records.key(source)
                    end))
                ),
              else: records

          {records, next} = page_records(records, state.args)

          result(
            %{
              "status" => "exported",
              "format" => "ipse-memory-v1",
              "scope" => state.options["scope"],
              "generation" => page["generation"],
              "next" => next,
              "records" => Enum.map(records, &Map.take(&1, ~w(key value)))
            },
            state
          )

        true ->
          {records, next} = page_records(records, state.args)

          result(
            %{
              "status" => "inventory",
              "generation" => page["generation"],
              "next" => next,
              "records" =>
                Enum.map(records, fn record ->
                  %{
                    "key" => record["key"],
                    "revision" => record["revision"],
                    "note" => Map.drop(record["value"], ~w(text title provenance)),
                    "expired" =>
                      record["value"]["state"] == "active" and
                        record["value"]["expires_at_ms"] <= state.now
                  }
                end)
            },
            state
          )
      end
    else
      result(%{"status" => "invalid_or_deleted_memory_record"}, state)
    end
  end

  def handle(
        "host.actions",
        %{"outcome" => %{"status" => "ok", "value" => %{"record" => cause}}},
        %{phase: :collect_dependency} = state
      ) do
    if valid_record?(cause) and
         (cause["value"]["state"] == "suppressed" or cause["value"]["expires_at_ms"] <= state.now) do
      record = state.collect_record

      write(
        record,
        Records.suppress(record["key"], record["value"]["source_generation"], state.now),
        state
      )
    else
      result(%{"status" => "cause_not_suppressed_or_expired"}, state)
    end
  end

  def handle(
        "host.actions",
        %{"outcome" => %{"status" => "ok", "value" => %{"record" => record} = value}},
        state
      ) do
    state = %{state | now: System.system_time(:millisecond)}

    cond do
      record["revision"] > 0 and not valid_record?(record) ->
        result(%{"status" => "invalid_or_deleted_memory_record"}, state)

      state.id == "inspect" ->
        if record["revision"] == 0 or record["value"]["state"] == "suppressed" do
          result(%{"status" => "inspected", "record" => record}, state)
        else
          scan(Map.merge(state, %{records: [], inspect_record: record}), nil, value["generation"])
        end

      record["revision"] != state.args["expected_revision"] ->
        result(%{"status" => "conflict", "revision" => record["revision"]}, state)

      state.id == "collect" and record["revision"] == 0 ->
        result(%{"status" => "not_found"}, state)

      true ->
        if state.id == "collect" and state.args["cause_source"] do
          if previous_dependency?(record["value"], state.args["cause_source"]) do
            call(
              %{
                "op" => "state.get",
                "scope" => state.options["scope"],
                "key" => Records.key(state.args["cause_source"])
              },
              Map.merge(state, %{phase: :collect_dependency, collect_record: record})
            )
          else
            result(%{"status" => "not_a_direct_derivative"}, state)
          end
        else
          prepare_write(record, state)
        end
    end
  end

  def handle("host.actions", %{"outcome" => outcome}, state),
    do: result(%{"status" => outcome["status"], "details" => outcome["value"]}, state)

  defp prepare_write(record, state) do
    previous = record["value"]

    note =
      case state.id do
        "remember" ->
          Records.build(state.args, previous, state.now, state.options["retention_seconds"])

        "forget" ->
          {:ok,
           Records.suppress(
             record["key"],
             if(previous, do: previous["source_generation"], else: 1),
             state.now
           )}

        "collect" ->
          if previous["state"] == "active" and previous["expires_at_ms"] <= state.now,
            do: {:ok, Records.suppress(record["key"], previous["source_generation"], state.now)},
            else: {:error, "not_expired"}

        "migrate" ->
          if previous && previous["version"] == 1,
            do:
              {:ok,
               if(previous["state"] == "active",
                 do: Map.put(previous, "derived_from", []),
                 else: previous
               )
               |> Map.put("version", 2)},
            else: {:error, "migration_not_required"}

        "import" ->
          if Records.valid?(state.args["value"], record["key"]),
            do:
              Records.import_note(
                state.args["value"],
                previous,
                state.now,
                state.options["retention_seconds"]
              ),
            else: {:error, "invalid_import"}
      end

    case note do
      {:ok, value} ->
        write(record, value, state)

      {:error, reason} ->
        result(%{"status" => reason}, state)
    end
  end

  defp previous_dependency?(note, source),
    do: is_map(note) and note["state"] == "active" and source in Map.get(note, "derived_from", [])

  defp write(record, value, state) do
    request = %{
      "op" => "state.put",
      "scope" => state.options["scope"],
      "key" => record["key"],
      "expected_revision" => record["revision"],
      "value" => value
    }

    request =
      if state.id in ~w(remember import) and record["value"] != nil and
           record["value"]["state"] == "active" and value["state"] == "active",
         do: Map.put(request, "write_before_ms", record["value"]["expires_at_ms"]),
         else: request

    call(request, %{state | phase: :write})
  end

  defp valid_record?(record),
    do: record["deleted"] == false and Records.valid?(record["value"], record["key"])

  defp exclude_derivatives(records, now) do
    present = MapSet.new(records, & &1["key"])

    blocked =
      records
      |> Enum.reject(&Records.visible?(&1["value"], now))
      |> MapSet.new(& &1["key"])

    blocked =
      Enum.reduce_while(1..256, blocked, fn _, blocked ->
        next =
          Enum.reduce(records, blocked, fn record, acc ->
            if Enum.any?(
                 Map.get(record["value"], "derived_from", []),
                 &(not MapSet.member?(present, Records.key(&1)) or
                     MapSet.member?(acc, Records.key(&1)))
               ) do
              MapSet.put(acc, record["key"])
            else
              acc
            end
          end)

        if next == blocked, do: {:halt, next}, else: {:cont, next}
      end)

    Enum.reject(records, &MapSet.member?(blocked, &1["key"]))
  end

  defp page_records(records, args) do
    remaining = Enum.filter(records, &(is_nil(args["after"]) or &1["key"] > args["after"]))

    selected =
      remaining
      |> Enum.take(Map.get(args, "limit", 2))
      |> Enum.reduce_while([], fn record, acc ->
        if byte_size(Jason.encode!(acc ++ [record])) <= 11_500,
          do: {:cont, acc ++ [record]},
          else: {:halt, acc}
      end)

    {selected, if(length(remaining) > length(selected), do: List.last(selected)["key"])}
  end

  defp scan(state, after_key, generation),
    do:
      call(
        %{
          "op" => "state.scan",
          "scope" => state.options["scope"],
          "after" => after_key,
          "generation" => generation,
          "limit" => 16
        },
        Map.put(state, :phase, :scan)
      )

  defp call(request, state),
    do: {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request}, state}

  defp result(value, state) do
    value =
      if byte_size(Jason.encode!(value)) <= 12_500,
        do: value,
        else: %{"status" => "result_bounds", "retry_with_smaller_limit" => true}

    {:ok, %{"api_version" => 1, "kind" => "result", "value" => value},
     Map.take(state, [:options])}
  end
end

defmodule Ipse.Builtins.WorkingMemory do
  @moduledoc "Independently selected session/task notes; no automatic promotion."
  @behaviour Ipse.Extension
  def describe,
    do: %{
      "sdk" => 1,
      "capabilities" => Ipse.Builtins.Memory.capabilities(),
      "exports" => Ipse.Builtins.Memory.exports()
    }

  def init(options), do: Ipse.Builtins.Memory.initialize(options, ["session"])
  defdelegate handle(stage, payload, state), to: Ipse.Builtins.Memory
end

defmodule Ipse.Builtins.Memory.Records do
  @moduledoc "Explicit note versions, irreversible source suppression and bounded lexical ranking."
  alias Ipse.JSON, as: Schema
  @safe 9_007_199_254_740_991
  @string %{"type" => "string", "minLength" => 1, "maxLength" => 512}
  @integer %{"type" => "integer", "minimum" => 0, "maximum" => @safe}

  def key(source), do: Ipse.JSON.sha256(source)

  def schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ~w(version state source_sha256 source_generation updated_at_ms),
      "properties" => %{
        "version" => %{"type" => "integer", "enum" => [1, 2]},
        "state" => %{"type" => "string", "enum" => ~w(active suppressed)},
        "source_sha256" => %{"type" => "string", "minLength" => 64, "maxLength" => 64},
        "source_generation" => %{"type" => "integer", "minimum" => 1, "maximum" => @safe},
        "updated_at_ms" => @integer,
        "created_at_ms" => @integer,
        "expires_at_ms" => @integer,
        "source" => @string,
        "provenance" => @string,
        "kind" => %{"type" => "string", "enum" => ~w(task_card project_fact)},
        "title" => %{"type" => "string", "minLength" => 1, "maxLength" => 128},
        "text" => %{"type" => "string", "minLength" => 1, "maxLength" => 2048},
        "derived_from" => %{"type" => "array", "maxItems" => 8, "items" => @string}
      }
    }
  end

  def valid?(note, key) do
    with :ok <- Schema.validate_arguments(schema(), note),
         true <- byte_size(Jason.encode!(note)) <= 8192,
         true <- is_binary(key) and Regex.match?(~r/\A[a-f0-9]{64}\z/, key),
         true <- note["source_sha256"] == key,
         true <- note["version"] in [1, 2],
         true <- Enum.all?(~w(source_generation updated_at_ms), &is_integer(note[&1])) do
      case note["state"] do
        "suppressed" ->
          Enum.sort(Map.keys(note)) ==
            ~w(source_generation source_sha256 state updated_at_ms version)

        "active" ->
          required =
            ~w(created_at_ms expires_at_ms kind provenance source source_generation source_sha256 state text title updated_at_ms version)

          required = if note["version"] == 2, do: ["derived_from" | required], else: required

          Enum.sort(Map.keys(note)) == Enum.sort(required) and key(note["source"]) == key and
            Enum.all?(~w(created_at_ms expires_at_ms), &is_integer(note[&1])) and
            note["created_at_ms"] <= note["updated_at_ms"] and
            note["expires_at_ms"] > note["updated_at_ms"] and
            byte_size(note["text"]) <= 2048 and byte_size(note["source"]) <= 512 and
            byte_size(note["title"]) <= 128 and byte_size(note["provenance"]) <= 512 and
            Enum.all?(Map.get(note, "derived_from", []), &(byte_size(&1) <= 512))
      end
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def build(args, previous, now, retention) do
    ttl = Map.get(args, "ttl_seconds", retention)

    note = %{
      "version" => 2,
      "state" => "active",
      "source_sha256" => key(args["source"]),
      "source" => args["source"],
      "source_generation" => args["source_generation"],
      "provenance" => args["provenance"],
      "kind" => args["kind"],
      "title" => args["title"],
      "text" => args["text"],
      "derived_from" => Map.get(args, "derived_from", []),
      "created_at_ms" => if(previous, do: previous["created_at_ms"], else: now),
      "updated_at_ms" => now,
      "expires_at_ms" => now + ttl * 1000
    }

    cond do
      previous && previous["state"] == "suppressed" ->
        {:error, "source_suppressed"}

      previous && previous["version"] != 2 ->
        {:error, "migration_required"}

      previous && previous["expires_at_ms"] <= now ->
        {:error, "source_expired"}

      previous && args["source_generation"] <= previous["source_generation"] ->
        {:error, "stale_source_generation"}

      ttl > retention or not valid?(note, note["source_sha256"]) ->
        {:error, "invalid_note"}

      true ->
        {:ok, note}
    end
  end

  def suppress(key, generation, now),
    do: %{
      "version" => 2,
      "state" => "suppressed",
      "source_sha256" => key,
      "source_generation" => generation,
      "updated_at_ms" => now
    }

  def visible?(note, now),
    do: note["version"] == 2 and note["state"] == "active" and note["expires_at_ms"] > now

  def import_note(incoming, previous, now, retention) do
    cond do
      previous && previous["state"] == "suppressed" ->
        {:error, "source_suppressed"}

      incoming["state"] == "suppressed" ->
        {:ok, Map.put(incoming, "version", 2)}

      previous && previous["version"] != 2 ->
        {:error, "migration_required"}

      incoming["expires_at_ms"] > now + retention * 1000 ->
        {:error, "retention_exceeded"}

      previous && previous["expires_at_ms"] <= now ->
        {:error, "source_expired"}

      previous && incoming["source_generation"] <= previous["source_generation"] ->
        {:error, "stale_source_generation"}

      true ->
        {:ok, incoming}
    end
  end

  def recall(records, query, limit, now) do
    terms = tokens(query) |> MapSet.new()

    records
    |> Enum.filter(&visible?(&1["value"], now))
    |> Enum.flat_map(fn record ->
      note = record["value"]
      words = tokens(note["title"] <> " " <> note["text"]) |> MapSet.new()
      hits = MapSet.size(MapSet.intersection(terms, words))
      if hits == 0, do: [], else: [{hits / max(MapSet.size(terms), 1), record}]
    end)
    |> Enum.sort_by(fn {score, record} -> {-score, record["key"]} end)
    |> Enum.take(limit)
    |> Enum.map(fn {score, record} ->
      note = record["value"]
      excerpt = note["text"] |> String.graphemes() |> Enum.take(256) |> Enum.join()

      %{
        "key" => record["key"],
        "revision" => record["revision"],
        "score" => score,
        "source" => note["source"],
        "source_generation" => note["source_generation"],
        "title" => note["title"],
        "provenance" => note["provenance"],
        "excerpt" => excerpt,
        "span" => %{"start_byte" => 0, "end_byte" => byte_size(excerpt)},
        "text_sha256" => Ipse.JSON.sha256(note["text"])
      }
    end)
  end

  defp tokens(text), do: Regex.scan(~r/[\p{L}\p{N}_]+/u, String.downcase(text)) |> List.flatten()
end
