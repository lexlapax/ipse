defmodule Ipse.Extension.ResultSource do
  @moduledoc """
  Pure source closure for immutable paged invocation results.

  Session owns append authority. These transitions validate source identity and
  progress; they do not authorize a caller or replace invocation/action checks.
  Full document validation belongs in the owned Host task or offline restore.
  """

  alias Ipse.Extension.{Invocation, ResultDocument}

  defmodule Sealed do
    @moduledoc false
    @enforce_keys [:begin_sha256, :event]
    defstruct [:begin_sha256, :event]
  end

  defmodule Index do
    @moduledoc false
    defstruct sources: %{}, committed: %{}, finals: %{}, begun_count: 0, source_bytes: 0
  end

  @enforce_keys [:intent, :begin, :bytes_hash, :chunks_hash]
  defstruct [
    :intent,
    :begin,
    :bytes_hash,
    :chunks_hash,
    :seal,
    phase: :draining,
    offset: 0,
    chunks: [],
    source_bytes: 0
  ]

  @types ~w(extension_output_begin extension_output_chunk extension_output_seal)
  @begin_keys ~w(type version invocation_id output_id intent_sha256 schema_sha256 byte_count sha256 elapsed_ms)
  @chunk_keys ~w(type version invocation_id output_id offset next byte_count sha256 data_base64)
  @seal_keys ~w(type version invocation_id output_id byte_count chunk_count sha256 chunks_sha256 elapsed_ms)
  @delivery_keys ~w(version kind output_id byte_count sha256 historical_receipt)
  @final_fields ~w(delivery text text_sha256 action_count actions_sha256 elapsed_ms)
  @error {:error, :invalid_extension_result_source}
  @byte_limit 4 * 1024 * 1024
  @source_limit 64
  @source_bytes_limit 64 * 1024 * 1024
  @page_bytes 4096
  @elapsed_limit 120_000
  @record_limit 131_072

  def types, do: @types

  def valid_descriptor?(delivery) do
    keys?(delivery, @delivery_keys) and delivery["version"] === 1 and
      delivery["kind"] == "saved.result" and hash?(delivery["output_id"]) and
      is_integer(delivery["byte_count"]) and delivery["byte_count"] in 1..@byte_limit and
      hash?(delivery["sha256"]) and delivery["historical_receipt"] === true
  end

  def published?(%Index{} = index, event) when is_map(event),
    do: index.finals[event["invocation_id"]] === event

  def published?(_, _), do: false

  def quota(%Index{} = index),
    do: %{begun_count: index.begun_count, source_bytes: index.source_bytes}

  def fits_reservation?(%Index{} = index, capacity) when is_map(capacity) do
    is_integer(index.begun_count) and index.begun_count in 0..(@source_limit - 1) and
      is_integer(index.source_bytes) and index.source_bytes in 0..@source_bytes_limit and
      is_integer(capacity[:source_bytes]) and capacity[:source_bytes] > 0 and
      index.source_bytes + capacity[:source_bytes] <= @source_bytes_limit
  end

  def fits_reservation?(_, _), do: false

  @doc "Recognize an exact previously recorded reply after Session checks its caller lease."
  def acknowledged?(%__MODULE__{} = source, reply) do
    Ipse.Extension.validate(reply) == :ok and byte_size(Jason.encode!(reply)) <= 12_000 and
      Enum.any?(source.chunks, fn event ->
        reply === %{
          "api_version" => 1,
          "kind" => "result_chunk",
          "output" => %{
            "version" => 1,
            "output_id" => event["output_id"],
            "offset" => event["offset"],
            "next" => event["next"],
            "complete" => event["next"] === source.begin["byte_count"],
            "data_base64" => event["data_base64"],
            "sha256" => event["sha256"]
          }
        }
      end)
  rescue
    _ -> false
  end

  def acknowledged?(_, _), do: false

  def source(%Index{} = index, output_id) do
    case index.sources[output_id] do
      %__MODULE__{} = source -> {:ok, source}
      _ -> @error
    end
  end

  @doc "Open a live source index after Session has checked its current caller lease."
  def index_open(%Index{} = index, intent, offer, elapsed_ms) do
    with true <- index.begun_count < @source_limit,
         false <-
           Enum.any?(index.sources, fn {_, source} ->
             source.intent["invocation_id"] == intent["invocation_id"]
           end),
         {:ok, event, source} <- open(intent, offer, elapsed_ms),
         {:ok, next} <- update_index(index, source, record_bytes(event), true) do
      {:ok, event, source, next}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def index_open(_, _, _, _), do: @error

  def index_push(%Index{} = index, output_id, reply) do
    with {:ok, source} <- source(index, output_id),
         {:ok, event, advanced} <- push(source, reply),
         {:ok, next} <- update_index(index, advanced, record_bytes(event)) do
      {:ok, event, advanced, next}
    else
      _ -> @error
    end
  end

  def index_push(_, _, _), do: @error

  def index_accept_verified(%Index{} = index, output_id, proof) do
    with {:ok, source} <- source(index, output_id),
         {:ok, event, advanced} <- accept_verified(source, proof),
         {:ok, next} <- update_index(index, advanced, record_bytes(event)) do
      {:ok, event, advanced, next}
    else
      _ -> @error
    end
  end

  def index_accept_verified(_, _, _), do: @error

  def publish(%Index{} = index, event) do
    with {:ok, source} <- source(index, get_in(event, ["delivery", "output_id"])),
         {:ok, committed} <- commit(source, event),
         {:ok, next} <- update_index(index, committed, 0) do
      {:ok,
       %{
         next
         | committed: Map.put(next.committed, committed.begin["output_id"], committed),
           finals: Map.put(next.finals, committed.intent["invocation_id"], event)
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def publish(_, _), do: @error

  @doc "Bind one producer offer to its original admitted invocation."
  def open(intent, offer, elapsed_ms) do
    with true <- eligible?(intent),
         true <- elapsed?(elapsed_ms),
         true <- keys?(offer, ~w(api_version kind output)),
         true <- offer["api_version"] === 1 and offer["kind"] == "result_producer",
         output = offer["output"],
         true <- keys?(output, ~w(version byte_count sha256)),
         true <- output["version"] === 1,
         true <- is_integer(output["byte_count"]) and output["byte_count"] in 1..@byte_limit,
         true <- hash?(output["sha256"]),
         true <- Ipse.Extension.validate(offer) == :ok do
      intent_hash = Ipse.JSON.digest([intent])

      binding = %{
        "intent_sha256" => intent_hash,
        "byte_count" => output["byte_count"],
        "sha256" => output["sha256"]
      }

      event = %{
        "type" => "extension_output_begin",
        "version" => 1,
        "invocation_id" => intent["invocation_id"],
        "output_id" => Ipse.JSON.digest([binding]),
        "intent_sha256" => intent_hash,
        "schema_sha256" => Ipse.JSON.digest([intent["descriptor"]["result_schema"]]),
        "byte_count" => output["byte_count"],
        "sha256" => output["sha256"],
        "elapsed_ms" => elapsed_ms
      }

      source = %__MODULE__{
        intent: intent,
        begin: event,
        bytes_hash: :crypto.hash_init(:sha256),
        chunks_hash: :crypto.hash_update(:crypto.hash_init(:sha256), "["),
        source_bytes: record_bytes(event)
      }

      {:ok, event, source}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Build the next fixed-stride worker request."
  def request(%__MODULE__{phase: :draining} = source) do
    if source.offset < source.begin["byte_count"] do
      {:ok,
       %{
         "api_version" => 1,
         "invocation_id" => source.intent["invocation_id"],
         "output_id" => source.begin["output_id"],
         "offset" => source.offset,
         "limit" => @page_bytes
       }}
    else
      @error
    end
  end

  def request(_), do: @error

  @doc "Validate one bounded SDK fragment and advance the private source."
  def push(%__MODULE__{phase: :draining} = source, reply) do
    with true <- keys?(reply, ~w(api_version kind output)),
         true <- reply["api_version"] === 1 and reply["kind"] == "result_chunk",
         true <- Ipse.Extension.validate(reply) == :ok,
         true <- byte_size(Jason.encode!(reply)) <= 12_000,
         output = reply["output"],
         true <- keys?(output, ~w(version output_id offset next complete data_base64 sha256)),
         true <- output["version"] === 1,
         true <-
           output["complete"] ===
             (source.offset + min(@page_bytes, source.begin["byte_count"] - source.offset) ==
                source.begin["byte_count"]),
         event = %{
           "type" => "extension_output_chunk",
           "version" => 1,
           "invocation_id" => source.intent["invocation_id"],
           "output_id" => output["output_id"],
           "offset" => output["offset"],
           "next" => output["next"],
           "byte_count" => output["next"] - output["offset"],
           "sha256" => output["sha256"],
           "data_base64" => output["data_base64"]
         },
         {:ok, next} <- advance(source, event) do
      {:ok, event, next}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def push(_, _), do: @error

  @doc "Validate the complete logical value outside Session and produce an internal proof."
  def seal(%__MODULE__{phase: :draining} = source, elapsed_ms) do
    with {:ok, event} <- seal_event(source, elapsed_ms),
         {:ok, _value} <-
           ResultDocument.decode(raw_bytes(source), source.intent["descriptor"]["result_schema"]) do
      proof = %Sealed{begin_sha256: Ipse.JSON.digest([source.begin]), event: event}

      {:ok, proof,
       %{
         source
         | phase: :sealed,
           seal: event,
           source_bytes: source.source_bytes + record_bytes(event)
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def seal(_, _), do: @error

  @doc "Accept only a trusted owned Host-task proof, without decoding the complete value again."
  def accept_verified(%__MODULE__{phase: :draining} = source, %Sealed{} = proof) do
    with true <- proof.begin_sha256 == Ipse.JSON.digest([source.begin]),
         true <- keys?(proof.event, @seal_keys),
         {:ok, expected} <- seal_event(source, proof.event["elapsed_ms"]),
         true <- expected === proof.event do
      {:ok, expected,
       %{
         source
         | phase: :sealed,
           seal: expected,
           source_bytes: source.source_bytes + record_bytes(expected)
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def accept_verified(_, _), do: @error

  def descriptor(%__MODULE__{} = source) do
    %{
      "version" => 1,
      "kind" => "saved.result",
      "output_id" => source.begin["output_id"],
      "byte_count" => source.begin["byte_count"],
      "sha256" => source.begin["sha256"],
      "historical_receipt" => true
    }
  end

  @doc "Validate final saved-result closure; origin and ordered action authority remain separate."
  def commit(%__MODULE__{phase: :sealed} = source, event) do
    with true <- is_map(event),
         true <- event["type"] == "extension_invocation_result" and event["version"] === 2,
         true <-
           Enum.sort(Map.keys(event)) == Enum.sort(Map.keys(source.intent) ++ @final_fields),
         original = Invocation.result_intent(event),
         true <- original === source.intent,
         delivery = descriptor(source),
         true <- valid_descriptor?(event["delivery"]) and event["delivery"] === delivery,
         true <- event["text"] === Jason.encode!(delivery),
         true <- event["text_sha256"] === Ipse.JSON.sha256(event["text"]),
         true <-
           elapsed?(event["elapsed_ms"]) and event["elapsed_ms"] >= source.seal["elapsed_ms"],
         true <-
           is_integer(event["action_count"]) and
             event["action_count"] in 0..Ipse.Extension.Actions.limit(source.intent["identity"]),
         true <- hash?(event["actions_sha256"]),
         true <- byte_size(Jason.encode!(event)) <= @record_limit do
      {:ok, %{source | phase: :committed}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def commit(_, _), do: @error

  @doc "Derive a pure read index, including charged unreadable interrupted prefixes."
  def restore(events) when is_list(events) do
    initial = %{index: %Index{}, intents: %{}, active: nil, recovered: MapSet.new()}

    Enum.reduce_while(events, {:ok, initial}, fn event, {:ok, state} ->
      case restore_event(event, state) do
        {:ok, next} -> {:cont, {:ok, next}}
        _ -> {:halt, @error}
      end
    end)
    |> case do
      {:ok, state} -> {:ok, state.index}
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def restore(_), do: @error

  @doc "Select one committed source after Session has authorized the caller."
  def readable_source(%Index{} = index, delivery) do
    with true <- valid_descriptor?(delivery),
         %__MODULE__{phase: :committed} = source <- index.committed[delivery["output_id"]],
         true <- delivery === descriptor(source) do
      {:ok, source}
    else
      _ -> @error
    end
  end

  def readable_source(_, _), do: @error

  @doc "Materialize complete bytes and value outside Session, after caller authorization."
  def materialize(%Index{} = index, delivery) do
    with {:ok, source} <- readable_source(index, delivery), do: materialize(source, delivery)
  end

  def materialize(%__MODULE__{phase: :committed} = source, delivery) do
    with true <- valid_descriptor?(delivery),
         true <- delivery === descriptor(source),
         bytes = raw_bytes(source),
         true <-
           byte_size(bytes) == delivery["byte_count"] and
             Ipse.JSON.sha256(bytes) == delivery["sha256"],
         {:ok, value} <-
           ResultDocument.decode(bytes, source.intent["descriptor"]["result_schema"]) do
      {:ok, %{bytes: bytes, value: value, provenance: "historical_receipt"}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def materialize(_, _), do: @error

  @doc "Pessimistic JSONL reservation for begin, fixed-stride chunks, seal and a final template."
  def reservation_size(%__MODULE__{offset: 0, phase: :draining} = source, final_template)
      when is_map(final_template) do
    total = source.begin["byte_count"]

    chunk_sizes =
      for offset <- 0..div(total - 1, @page_bytes),
          do: capacity_chunk_bytes(source, offset * @page_bytes)

    seal = %{
      "type" => "extension_output_seal",
      "version" => 1,
      "invocation_id" => source.intent["invocation_id"],
      "output_id" => source.begin["output_id"],
      "byte_count" => total,
      "chunk_count" => length(chunk_sizes),
      "sha256" => source.begin["sha256"],
      "chunks_sha256" => String.duplicate("0", 64),
      "elapsed_ms" => @elapsed_limit
    }

    source_sizes = [record_bytes(source.begin), record_bytes(seal) | chunk_sizes]
    sizes = [record_bytes(Map.put(final_template, "elapsed_ms", @elapsed_limit)) | source_sizes]

    if Enum.all?(sizes, &(&1 - 1 <= @record_limit)) do
      {:ok,
       %{
         bytes: Enum.sum(sizes),
         events: length(sizes),
         max_record_bytes: Enum.max(sizes) - 1,
         source_bytes: Enum.sum(source_sizes)
       }}
    else
      @error
    end
  rescue
    _ -> @error
  end

  def reservation_size(_, _), do: @error

  defp advance(%__MODULE__{phase: :draining} = source, event) do
    with true <- keys?(event, @chunk_keys),
         true <- event["type"] == "extension_output_chunk" and event["version"] === 1,
         true <-
           event["invocation_id"] === source.intent["invocation_id"] and
             event["output_id"] === source.begin["output_id"],
         true <- event["offset"] === source.offset and source.offset < source.begin["byte_count"],
         count = min(@page_bytes, source.begin["byte_count"] - source.offset),
         true <- event["byte_count"] === count and event["next"] === source.offset + count,
         true <- is_binary(event["data_base64"]) and byte_size(event["data_base64"]) <= 5464,
         {:ok, bytes} <- Base.decode64(event["data_base64"]),
         true <- byte_size(bytes) == count and Base.encode64(bytes) === event["data_base64"],
         true <- event["sha256"] === Ipse.JSON.sha256(bytes),
         true <- record_bytes(event) - 1 <= @record_limit do
      canonical =
        event |> Enum.sort_by(&elem(&1, 0)) |> Jason.OrderedObject.new() |> Jason.encode!()

      prefix = if source.offset == 0, do: "", else: ","

      {:ok,
       %{
         source
         | offset: event["next"],
           chunks: [event | source.chunks],
           bytes_hash: :crypto.hash_update(source.bytes_hash, bytes),
           chunks_hash: :crypto.hash_update(source.chunks_hash, [prefix, canonical]),
           source_bytes: source.source_bytes + record_bytes(event)
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp advance(_, _), do: @error

  defp seal_event(source, elapsed_ms) do
    with true <- source.offset == source.begin["byte_count"],
         true <- elapsed?(elapsed_ms) and elapsed_ms >= source.begin["elapsed_ms"],
         true <- hex(:crypto.hash_final(source.bytes_hash)) === source.begin["sha256"] do
      {:ok,
       %{
         "type" => "extension_output_seal",
         "version" => 1,
         "invocation_id" => source.intent["invocation_id"],
         "output_id" => source.begin["output_id"],
         "byte_count" => source.offset,
         "chunk_count" => length(source.chunks),
         "sha256" => source.begin["sha256"],
         "chunks_sha256" => hex(:crypto.hash_final(:crypto.hash_update(source.chunks_hash, "]"))),
         "elapsed_ms" => elapsed_ms
       }}
    else
      _ -> @error
    end
  end

  defp restore_event(%{"type" => "extension_invocation_intent"} = event, state) do
    with :ok <- Invocation.validate_intent(event),
         false <- active_producer?(state),
         false <- Map.has_key?(state.intents, event["invocation_id"]) do
      {:ok,
       %{
         state
         | active: event["invocation_id"],
           intents: Map.put(state.intents, event["invocation_id"], event)
       }}
    else
      _ -> @error
    end
  end

  defp restore_event(%{"type" => "extension_output_begin"} = event, state) do
    id = event["invocation_id"]

    offer = %{
      "api_version" => 1,
      "kind" => "result_producer",
      "output" => Map.take(event, ~w(version byte_count sha256))
    }

    with true <- keys?(event, @begin_keys),
         true <- state.active === id and not MapSet.member?(state.recovered, id),
         false <-
           Enum.any?(state.index.sources, fn {_, source} ->
             source.intent["invocation_id"] == id
           end),
         true <- state.index.begun_count < @source_limit,
         {:ok, expected, source} <- open(state.intents[id], offer, event["elapsed_ms"]),
         true <- event === expected do
      put_source(state, source, record_bytes(event), true)
    else
      _ -> @error
    end
  end

  defp restore_event(%{"type" => "extension_output_chunk"} = event, state) do
    with {:ok, source} <- active_source(state, event),
         {:ok, next} <- advance(source, event) do
      put_source(state, next, record_bytes(event))
    else
      _ -> @error
    end
  end

  defp restore_event(%{"type" => "extension_output_seal"} = event, state) do
    with true <- keys?(event, @seal_keys),
         {:ok, source} <- active_source(state, event),
         {:ok, proof, next} <- seal(source, event["elapsed_ms"]),
         true <- event === proof.event do
      put_source(state, next, record_bytes(event))
    else
      _ -> @error
    end
  end

  defp restore_event(%{"type" => "extension_invocation_result", "version" => 2} = event, state) do
    with {:ok, source} <-
           active_source(state, %{
             "invocation_id" => event["invocation_id"],
             "output_id" => get_in(event, ["delivery", "output_id"])
           }),
         {:ok, next} <- commit(source, event),
         {:ok, updated} <- put_source(state, next, 0) do
      index = %{
        updated.index
        | committed: Map.put(updated.index.committed, next.begin["output_id"], next),
          finals: Map.put(updated.index.finals, next.intent["invocation_id"], event)
      }

      {:ok, %{updated | index: index, active: nil}}
    else
      _ -> @error
    end
  end

  defp restore_event(%{"type" => "extension_invocation_result"} = event, state) do
    if Enum.any?(state.index.sources, fn {_, source} ->
         source.intent["invocation_id"] == event["invocation_id"]
       end),
       do: @error,
       else: {:ok, %{state | active: nil}}
  end

  defp restore_event(%{"type" => type} = event, state)
       when type in ~w(extension_question extension_continuation_intent) do
    id = event["parent_invocation_id"]

    if active_producer?(state) or
         Enum.any?(state.index.sources, fn {_, source} -> source.intent["invocation_id"] == id end),
       do: @error,
       else: {:ok, %{state | recovered: MapSet.put(state.recovered, id)}}
  end

  defp restore_event(%{"type" => type} = event, state)
       when type in ~w(extension_action_intent extension_action_result) do
    if active_producer?(state) or
         Enum.any?(state.index.sources, fn {_, source} ->
           source.intent["invocation_id"] == event["parent_invocation_id"]
         end),
       do: @error,
       else: {:ok, state}
  end

  defp restore_event(%{"type" => type}, state) when type in ~w(cancelled turn_finished),
    do: {:ok, %{state | active: nil}}

  defp restore_event(%{"type" => "message", "message" => %{"role" => "user"}}, state),
    do: {:ok, %{state | active: nil}}

  defp restore_event(%{"type" => type}, state) when is_binary(type) do
    if String.starts_with?(type, "extension_output_"), do: @error, else: {:ok, state}
  end

  defp restore_event(_, _), do: @error

  defp active_source(state, event) do
    source = state.index.sources[event["output_id"]]

    if state.active === event["invocation_id"] and match?(%__MODULE__{}, source) and
         source.intent["invocation_id"] === event["invocation_id"],
       do: {:ok, source},
       else: @error
  end

  defp active_producer?(state),
    do:
      Enum.any?(state.index.sources, fn {_, source} ->
        source.intent["invocation_id"] == state.active
      end)

  defp put_source(state, source, charged, begun \\ false) do
    with {:ok, index} <- update_index(state.index, source, charged, begun) do
      {:ok, %{state | index: index}}
    end
  end

  defp update_index(index, source, charged, begun \\ false) do
    if index.source_bytes + charged <= @source_bytes_limit do
      {:ok,
       %{
         index
         | sources: Map.put(index.sources, source.begin["output_id"], source),
           source_bytes: index.source_bytes + charged,
           begun_count: index.begun_count + if(begun, do: 1, else: 0)
       }}
    else
      @error
    end
  end

  defp capacity_chunk_bytes(source, offset) do
    count = min(@page_bytes, source.begin["byte_count"] - offset)

    %{
      "type" => "extension_output_chunk",
      "version" => 1,
      "invocation_id" => source.intent["invocation_id"],
      "output_id" => source.begin["output_id"],
      "offset" => offset,
      "next" => offset + count,
      "byte_count" => count,
      "sha256" => String.duplicate("0", 64),
      "data_base64" => ""
    }
    |> record_bytes()
    |> Kernel.+(4 * div(count + 2, 3))
  end

  defp eligible?(intent) do
    Invocation.validate_intent(intent) == :ok and intent["identity"]["sdk"] === 2 and
      "invoke.result.pages" in intent["identity"]["capabilities"] and
      intent["descriptor"]["stage"] in ~w(invoke.tool invoke.command)
  end

  defp raw_bytes(source),
    do:
      source.chunks
      |> Enum.reverse()
      |> Enum.map(fn event -> Base.decode64!(event["data_base64"]) end)
      |> IO.iodata_to_binary()

  defp record_bytes(record), do: byte_size(Jason.encode!(record)) + 1
  defp elapsed?(value), do: is_integer(value) and value in 0..@elapsed_limit
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[a-f0-9]{64}\z/, value)
  defp hex(value), do: Base.encode16(value, case: :lower)
  defp keys?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(keys)
  alias Ipse.Extension.ResultView

  def reader_definition do
    %{
      "type" => "function",
      "function" => %{
        "name" => "saved_result_read",
        "description" =>
          "Read a bounded historical view of a saved result already disclosed in this session. " <>
            "Start with output_id and path, or submit only the returned cursor. " <>
            "References preserve omitted subtrees and large names; complete applies to the requested target.",
        "parameters" => %{
          "type" => "object",
          "additionalProperties" => false,
          "properties" => %{
            "output_id" => %{"type" => "string"},
            "path" => %{"type" => "array", "maxItems" => 12, "items" => %{}},
            "offset" => %{"type" => "integer", "minimum" => 0},
            "cursor" => %{"type" => "object"}
          }
        }
      }
    }
  end

  def materialize_session(session, delivery) do
    with {:ok, source} <- call(session, {:saved_result_materialize, delivery}) do
      bounded(fn -> materialize(source, delivery) end)
    end
  end

  def read_saved(state_dir, session_id, output_id) do
    with {:ok, events} <- Ipse.Journal.load(state_dir, session_id),
         {:ok, _} <- Ipse.Session.restore_context(events),
         {:ok, index} <- restore(events),
         {:ok, source} <- source(index, output_id),
         delivery = descriptor(source),
         {:ok, source} <- readable_source(index, delivery) do
      bounded(fn -> materialize(source, delivery) end)
    else
      _ -> {:error, :saved_result_unavailable}
    end
  end

  def read_session(session, request) do
    with {:ok, source, delivery} <- call(session, {:saved_result_read, request}) do
      view(source, delivery, request)
    end
  end

  def read_model(session, job_ref, request) do
    with {:ok, source, delivery} <-
           call(session, {:saved_result_model_read, job_ref, request}),
         {:ok, result} <- view(source, delivery, request) do
      {:ok, Jason.encode!(result)}
    else
      _ -> {:error, "Saved result read refused or unavailable."}
    end
  end

  def request_output_id(%{"cursor" => %{"output_id" => id}}), do: id
  def request_output_id(%{"output_id" => id}), do: id
  def request_output_id(_), do: nil

  defp view(source, delivery, request) do
    bounded(fn ->
      with {:ok, %{value: value}} <- materialize(source, delivery),
           do: ResultView.read(value, delivery, request)
    end)
  end

  defp bounded(fun) do
    task =
      Task.async(fn ->
        try do
          fun.()
        rescue
          _ -> {:error, :saved_result_unavailable}
        catch
          _, _ -> {:error, :saved_result_unavailable}
        end
      end)

    case Task.yield(task, 5_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {:error, :saved_result_unavailable}
    end
  end

  defp call(session, request) do
    GenServer.call(session, request, 5_000)
  catch
    :exit, _ -> {:error, :saved_result_unavailable}
  end
end
