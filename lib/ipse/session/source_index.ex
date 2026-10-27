defmodule Ipse.Session.SourceIndex do
  @moduledoc """
  Host-owned immutable source occurrences and read-only, authenticated UTF-8 pages.

  Admission functions accept records already committed and validated by the owning
  Session. Structural validation here does not authenticate a caller or grant
  permission. Origin identifies the receipt, not truth or authority of quoted prose.
  Only list/read/quote requests are suitable for worker-facing tools.
  No function reads a path, repairs a journal, or runs an effect.
  """
  alias Ipse.{JSON, Journal}
  alias Ipse.Session.{Input, Lifecycle, ToolLifecycle}
  alias Ipse.Extension.{EffectResult, DecisionCall, Actions}
  @derive {Inspect, only: [:session_id, :window_id, :generation, :policy_generation, :bytes]}
  defstruct [
    :session_id,
    :window_id,
    :secret,
    policy_generation: 1,
    generation: 0,
    bytes: 0,
    entries: %{},
    order: []
  ]

  @error {:error, :source_index_refused}
  @source_bytes 1_048_576
  @total_bytes 8_388_608
  @entries 1024
  @list_bytes 4096
  @read_bytes 8192
  @token_keys ~w(version session window generation policy kind occurrence source_version offset)
  @tool_names ~w(read write edit shell)

  def new(session, policy_generation \\ 1) do
    if id?(session) and positive?(policy_generation),
      do:
        {:ok,
         %__MODULE__{
           session_id: session,
           window_id: Ipse.Usage.id(),
           secret: :crypto.strong_rand_bytes(32),
           policy_generation: policy_generation
         }},
      else: @error
  end

  def snapshot(%__MODULE__{} = index),
    do: %{
      "version" => 1,
      "session_id" => index.session_id,
      "window_id" => index.window_id,
      "generation" => index.generation,
      "policy_generation" => index.policy_generation,
      "count" => length(index.order)
    }

  @doc "Admit original input only with its matching committed effective user message."
  def admit_input(
        %__MODULE__{} = index,
        input,
        %{"type" => "message", "message" => %{"role" => "user", "content" => effective}} = message
      ) do
    with true <- is_binary(effective) and String.valid?(effective),
         :ok <- Input.validate_events([input, message], index.session_id),
         true <-
           input["type"] == "input_received" and
             input["effective_sha256"] == JSON.sha256(effective),
         true <- input["origin"] in ~w(interactive_operator unattended_input) do
      append(index, [
        entry(
          index,
          input["source_id"],
          "input.original",
          input["origin"],
          input["text"],
          "available",
          nil,
          %{"turn_id" => input["turn_id"], "receipt_sha256" => JSON.digest([input])}
        )
      ])
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def admit_input(_, _, _), do: @error

  @doc "Only an admitted original visible answer is indexed; presentation and reasoning are excluded."
  def admit_answer(index, answer, assistant \\ nil)

  def admit_answer(%__MODULE__{} = index, answer, assistant) do
    with true <- Lifecycle.valid_answer?(answer),
         true <- answer["effective_source"]["session_id"] == index.session_id,
         true <- assistant_matches?(answer, assistant) do
      coverage = if is_nil(answer["original"]), do: "unavailable", else: "available"

      value =
        entry(
          index,
          answer["request_id"],
          "answer.original",
          "assistant_proposal",
          answer["original"],
          coverage,
          if(coverage == "unavailable", do: "content_unavailable"),
          %{
            "turn_id" => answer["turn_id"],
            "request_id" => answer["request_id"],
            "receipt_sha256" => JSON.digest([answer])
          }
        )

      value = %{
        value
        | content_sha256: answer["original_sha256"],
          original_bytes: answer["original_bytes"]
      }

      append(index, [version(value)])
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def admit_answer(_, _, _), do: @error

  @doc "Legacy role labels establish no operator attestation. A host-validated journal occurrence is required."
  def admit_legacy(
        %__MODULE__{} = index,
        source,
        %{"type" => "message", "message" => %{"role" => "user"} = message} = record
      ) do
    with true <-
           Journal.source_matches?(source, record) and source["session_id"] == index.session_id,
         text = message["content"],
         true <- is_nil(text) or text?(text) do
      append(index, [
        entry(
          index,
          source["event_id"],
          "input.legacy",
          "legacy_unverified",
          text,
          if(is_nil(text), do: "unavailable", else: "available"),
          "unverified_origin",
          %{"receipt_sha256" => JSON.digest([record])}
        )
      ])
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def admit_legacy(_, _, _), do: @error

  @doc "Keep host outcome facts separate from untrusted read/shell/MCP content."
  def admit_tool(%__MODULE__{} = index, intent, outcome, message) do
    with true <- ToolLifecycle.valid?(intent) and ToolLifecycle.valid?(outcome),
         true <-
           intent["type"] == "lifecycle_tool_intent" and
             outcome["type"] == "lifecycle_tool_outcome",
         true <-
           intent["session_id"] == index.session_id and outcome["session_id"] == index.session_id,
         true <-
           Enum.all?(
             ~w(epoch_id tool_id turn_id request_id approval),
             &(intent[&1] == outcome[&1])
           ),
         true <- Journal.source_matches?(outcome["tool_source"], intent),
         true <- Journal.source_matches?(outcome["result_source"], message),
         %{
           "type" => "message",
           "message" => %{"role" => "tool", "content" => text, "ipse_tool_outcome" => status}
         } <- message,
         true <- text?(text) and status == Map.take(outcome, ~w(status approval)),
         true <- outcome["result_sha256"] == JSON.digest([%{"text" => text}]),
         name when is_binary(name) <- get_in(intent, ["input", "name"]),
         true <- name in @tool_names or mcp_tool?(name) do
      provenance =
        Map.take(outcome, ~w(tool_id turn_id request_id))
        |> Map.put("receipt_sha256", JSON.digest([outcome]))

      facts = Map.take(outcome, ~w(status approval duration_ms)) |> Map.put("tool", name)

      metadata =
        entry(
          index,
          outcome["tool_id"],
          "tool.outcome",
          "typed_host_outcome",
          Jason.encode!(facts),
          "available",
          nil,
          provenance
        )

      entries =
        if name in ~w(read shell) or mcp_tool?(name),
          do: [
            metadata,
            entry(
              index,
              outcome["tool_id"],
              "tool.content",
              "attributed_reference",
              text,
              "partial",
              "tool_output_only",
              provenance
            )
          ],
          else: [metadata]

      append(index, entries)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def admit_tool(_, _, _, _), do: @error

  @doc "Only a successfully published MCP/embedding action makes its private source readable."
  def admit_effect(index, result, source, parent \\ nil)

  def admit_effect(%__MODULE__{} = index, result, source, parent) do
    with true <- Actions.valid_result?(result) and result["outcome"]["status"] == "ok",
         intent = Actions.result_intent(result),
         true <- EffectResult.valid_source?(source, intent),
         true <- Actions.bound_effect?(result, %{intent["operation_id"] => source}, []),
         true <- effect_publication?(result, source),
         true <- effect_session?(index, intent, parent) do
      provenance = %{
        "operation_id" => source["operation_id"],
        "receipt_sha256" => source["source_sha256"]
      }

      case source["kind"] do
        "mcp.text" ->
          facts = %{"operation" => "mcp.call", "source_sha256" => source["source_sha256"]}

          append(index, [
            entry(
              index,
              source["operation_id"],
              "effect.outcome",
              "typed_host_outcome",
              Jason.encode!(facts),
              "available",
              nil,
              provenance
            ),
            entry(
              index,
              source["operation_id"],
              "effect.content",
              "attributed_reference",
              source["data"]["text"],
              "partial",
              "external_text_only",
              provenance
            )
          ])

        "embedding.f32le" ->
          facts = %{
            "operation" => "embedding.create",
            "reported_model" => source["inference"]["reported_model"],
            "dimensions" => source["data"]["dimensions"],
            "vector_count" => length(source["data"]["vectors"])
          }

          append(index, [
            entry(
              index,
              source["operation_id"],
              "effect.outcome",
              "typed_host_outcome",
              Jason.encode!(facts),
              "available",
              nil,
              provenance
            )
          ])

        _ ->
          @error
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def admit_effect(_, _, _, _), do: @error

  @doc "A typed decision receipt is advice, never a host attestation that its answer is true."
  def admit_decision(%__MODULE__{} = index, result, record, response) do
    with true <- Actions.valid_result?(result) and result["outcome"]["status"] == "ok",
         %{admission: admission, completion: completion} <- record,
         true <-
           is_map(completion) and completion["outcome"] == "completed" and
             completion["finality"] == "final",
         true <- Ipse.Usage.valid_request_record?(Ipse.Usage.request_record(record)),
         true <- DecisionCall.valid_result_source?(result, record, response),
         true <- DecisionCall.bound_response?(result, response),
         intent = Actions.result_intent(result),
         true <- admission["session_id"] == index.session_id do
      facts = %{
        "operation" => "decision.create",
        "reported_model" => response["payload"]["reported_model"],
        "subset" => response["payload"]["subset"]
      }

      provenance = %{
        "operation_id" => intent["operation_id"],
        "receipt_sha256" => JSON.digest([response])
      }

      append(index, [
        entry(
          index,
          intent["operation_id"],
          "effect.outcome",
          "typed_host_outcome",
          Jason.encode!(facts),
          "available",
          nil,
          provenance
        ),
        entry(
          index,
          intent["operation_id"],
          "decision.advice",
          "assistant_proposal",
          Jason.encode!(response["payload"]["result"]),
          "available",
          nil,
          provenance
        )
      ])
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def admit_decision(_, _, _, _), do: @error

  @doc "Host-only policy fencing. Existing tokens are invalidated without publishing content."
  def revalidate(%__MODULE__{} = index, generation) do
    if positive?(generation) and generation > index.policy_generation,
      do: {:ok, %{index | policy_generation: generation}},
      else: @error
  end

  @doc "Host-only redaction removes readable bytes and changes the source version."
  def redact(%__MODULE__{} = index, occurrence, policy_generation) do
    with {:ok, index} <- revalidate(index, policy_generation),
         %{text: text} = item <- index.entries[occurrence] do
      item = version(%{item | text: nil, coverage: "unavailable", reason: "redacted"})

      {:ok,
       %{
         index
         | generation: index.generation + 1,
           bytes: index.bytes - if(is_binary(text), do: byte_size(text), else: 0),
           entries: Map.put(index.entries, occurrence, item)
       }}
    else
      _ -> @error
    end
  end

  def list(%__MODULE__{} = index, request) do
    with true <-
           is_map(request) and keys?(Map.delete(request, "cursor"), ["limit"]) and
             is_integer(request["limit"]) and
             request["limit"] in 1..32,
         {:ok, offset} <- list_offset(index, request["cursor"]),
         true <- offset <= length(index.order) do
      base = list_page(index, offset, offset, [])

      Enum.reduce_while(
        Enum.take(Enum.drop(index.order, offset), request["limit"]),
        {base, offset},
        fn id, {page, position} ->
          row = row(index, index.entries[id])
          candidate = list_page(index, offset, position + 1, page["sources"] ++ [row])

          if fits?(candidate, @list_bytes),
            do: {:cont, {candidate, position + 1}},
            else: {:halt, {page, position}}
        end
      )
      |> then(fn {page, position} ->
        if position > offset or offset == length(index.order), do: {:ok, page}, else: @error
      end)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def list(_, _), do: @error

  def read(%__MODULE__{} = index, request) do
    with true <- keys?(request, ["handle"]),
         {:ok, token} <- decode(index, request["handle"], "read"),
         %{version_id: version} = item <- index.entries[token["occurrence"]],
         true <- version == token["source_version"],
         true <- token["offset"] <= if(is_binary(item.text), do: byte_size(item.text), else: 0) do
      {:ok, evidence(index, item, token["offset"])}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def read(_, _), do: @error

  @doc "Match exact bytes uniquely in the immutable source and within this evidence window."
  def quote(%__MODULE__{} = index, request) do
    with true <-
           keys?(request, ~w(handle quote)) and is_binary(request["quote"]) and
             String.valid?(request["quote"]) and byte_size(request["quote"]) in 1..8192,
         {:ok, page} <- read(index, Map.take(request, ["handle"])),
         true <- page["coverage"] != "unavailable",
         item = index.entries[page["occurrence_id"]],
         {:ok, {offset, length}} <- unique_match(item.text, request["quote"]),
         true <-
           offset >= page["offset"] and
             offset + length <= page["offset"] + byte_size(page["text"]) do
      {:ok,
       Map.take(page, ~w(occurrence_id version_id chunk_id origin coverage))
       |> Map.merge(%{
         "start_byte" => offset,
         "end_byte" => offset + length,
         "quote_sha256" => JSON.sha256(request["quote"]),
         "content_sha256" => item.content_sha256
       })}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def quote(_, _), do: @error

  defp assistant_matches?(_, nil), do: true

  defp assistant_matches?(answer, %{
         "type" => "message",
         "request_id" => request,
         "message" => %{"role" => "assistant", "content" => text} = assistant
       }) do
    request == answer["request_id"] and text?(text) and
      JSON.digest([assistant]) == answer["assistant_sha256"] and
      JSON.sha256(text) == answer["original_sha256"] and
      byte_size(text) == answer["original_bytes"]
  end

  defp assistant_matches?(_, _), do: false

  defp mcp_tool?(name),
    do:
      Ipse.MCP.external?(name) and
        Ipse.Extension.MCPCall.public_bindings?([%{"alias" => "source", "tool" => name}])

  defp entry(index, identity, kind, origin, text, coverage, reason, provenance) do
    occurrence = identifier(["ipse.source.occurrence", index.session_id, identity, kind])

    %{
      occurrence_id: occurrence,
      version_id: nil,
      kind: kind,
      origin: origin,
      text: text,
      content_sha256: if(is_binary(text), do: JSON.sha256(text)),
      original_bytes: if(is_binary(text), do: byte_size(text)),
      coverage: coverage,
      reason: reason,
      provenance: provenance
    }
    |> version()
  end

  defp version(item),
    do: %{
      item
      | version_id:
          identifier([
            "ipse.source.version",
            item.occurrence_id,
            item.content_sha256,
            item.original_bytes,
            item.origin,
            item.provenance,
            item.coverage,
            item.reason
          ])
    }

  defp append(index, entries) do
    bytes = Enum.sum(Enum.map(entries, &if(is_binary(&1.text), do: byte_size(&1.text), else: 0)))

    if length(index.order) + length(entries) <= @entries and index.bytes + bytes <= @total_bytes and
         Enum.all?(
           entries,
           &(id?(&1.occurrence_id) and (is_nil(&1.text) or text?(&1.text)) and
               not Map.has_key?(index.entries, &1.occurrence_id))
         ) do
      {:ok,
       %{
         index
         | generation: index.generation + 1,
           bytes: index.bytes + bytes,
           entries: Enum.reduce(entries, index.entries, &Map.put(&2, &1.occurrence_id, &1)),
           order: index.order ++ Enum.map(entries, & &1.occurrence_id)
       }}
    else
      @error
    end
  end

  defp effect_session?(index, %{"namespace" => session}, nil), do: session == index.session_id

  defp effect_session?(index, intent, parent) do
    Ipse.Extension.Invocation.validate_intent(parent) == :ok and
      parent["invocation_id"] == intent["parent_invocation_id"] and
      JSON.digest([parent["identity"]]) == intent["identity_sha256"] and
      "host.actions" in parent["identity"]["capabilities"] and
      Ipse.Extension.Actions.capability(intent["request"]) in parent["identity"]["capabilities"] and
      parent["payload"]["session_id"] == index.session_id and
      intent["namespace"] in [nil, index.session_id]
  end

  defp effect_publication?(result, %{"kind" => "embedding.f32le"} = source) do
    value = result["outcome"]["value"]
    inference = source["inference"]

    value["request_id"] == inference["request_id"] and
      value["attempt_id"] == inference["attempt_id"] and
      value["profile"] == inference["profile"] and
      value["reported_model"] == inference["reported_model"] and
      value["usage"] === inference["usage"]
  end

  defp effect_publication?(_, %{"kind" => "mcp.text"}), do: true
  defp effect_publication?(_, _), do: false

  defp row(index, item),
    do: %{
      "occurrence_id" => item.occurrence_id,
      "version_id" => item.version_id,
      "chunk_id" => evidence(index, item, 0)["chunk_id"],
      "kind" => item.kind,
      "origin" => item.origin,
      "coverage" => item.coverage,
      "reason" => item.reason,
      "read_handle" => token(index, "read", item, 0)
    }

  defp list_page(index, offset, next, rows),
    do: %{
      "version" => 1,
      "window" => snapshot(index),
      "offset" => offset,
      "next" => if(next < length(index.order), do: token(index, "list", nil, next)),
      "complete" => next == length(index.order),
      "sources" => rows
    }

  defp list_offset(_, nil), do: {:ok, 0}

  defp list_offset(index, cursor) do
    with {:ok, value} <- decode(index, cursor, "list"), do: {:ok, value["offset"]}
  end

  defp evidence(index, %{text: nil} = item, 0), do: evidence_page(index, item, 0, "", nil)

  defp evidence(index, item, offset) do
    remaining = binary_part(item.text, offset, byte_size(item.text) - offset)
    true = String.valid?(remaining)
    bytes = fit_text(index, item, offset, remaining, 0, min(byte_size(remaining), @read_bytes), 0)
    text = prefix(remaining, bytes)
    true = text != "" or remaining == ""
    next = if offset + byte_size(text) < byte_size(item.text), do: offset + byte_size(text)
    evidence_page(index, item, offset, text, next)
  end

  defp fit_text(_, _, _, _, low, high, best) when low > high, do: best

  defp fit_text(index, item, offset, remaining, low, high, best) do
    mid = div(low + high, 2)
    text = prefix(remaining, mid)
    next = if offset + byte_size(text) < byte_size(item.text), do: offset + byte_size(text)

    if fits?(evidence_page(index, item, offset, text, next), @read_bytes),
      do: fit_text(index, item, offset, remaining, mid + 1, high, byte_size(text)),
      else: fit_text(index, item, offset, remaining, low, mid - 1, best)
  end

  defp evidence_page(index, item, offset, text, next),
    do: %{
      "version" => 1,
      "window" => snapshot(index),
      "occurrence_id" => item.occurrence_id,
      "version_id" => item.version_id,
      "chunk_id" => chunk(item, offset, text),
      "origin" => item.origin,
      "kind" => item.kind,
      "coverage" => item.coverage,
      "reason" => item.reason,
      "content_sha256" => item.content_sha256,
      "original_bytes" => item.original_bytes,
      "provenance" => item.provenance,
      "offset" => offset,
      "text" => text,
      "handle" => token(index, "read", item, offset),
      "next" => if(next != nil, do: token(index, "read", item, next)),
      "complete" => next == nil
    }

  defp chunk(item, offset, text),
    do:
      identifier([
        "ipse.source.chunk",
        item.version_id,
        offset,
        byte_size(text),
        JSON.sha256(text)
      ])

  defp token(index, kind, item, offset) do
    payload =
      Jason.encode!(%{
        "version" => 1,
        "session" => index.session_id,
        "window" => index.window_id,
        "generation" => index.generation,
        "policy" => index.policy_generation,
        "kind" => kind,
        "occurrence" => if(item, do: item.occurrence_id),
        "source_version" => if(item, do: item.version_id),
        "offset" => offset
      })

    Base.url_encode64(payload, padding: false) <>
      "." <> Base.url_encode64(:crypto.mac(:hmac, :sha256, index.secret, payload), padding: false)
  end

  defp decode(index, token, kind) do
    with true <- is_binary(token) and byte_size(token) <= 2048,
         [body, signature] <- String.split(token, "."),
         {:ok, bytes} <- Base.url_decode64(body, padding: false),
         {:ok, mac} <- Base.url_decode64(signature, padding: false),
         true <- byte_size(bytes) <= 1024 and byte_size(mac) == 32,
         true <-
           Base.url_encode64(bytes, padding: false) == body and
             Base.url_encode64(mac, padding: false) == signature,
         true <- :crypto.hash_equals(mac, :crypto.mac(:hmac, :sha256, index.secret, bytes)),
         {:ok, value} <- JSON.decode_unique(bytes),
         true <-
           keys?(value, @token_keys) and value["version"] === 1 and
             value["session"] == index.session_id and value["window"] == index.window_id and
             value["generation"] === index.generation and
             value["policy"] === index.policy_generation and value["kind"] == kind,
         true <- JSON.safe_uint?(value["offset"]),
         true <-
           if(kind == "list",
             do: value["occurrence"] == nil and value["source_version"] == nil,
             else: id?(value["occurrence"]) and id?(value["source_version"])
           ) do
      {:ok, value}
    else
      _ -> @error
    end
  end

  defp unique_match(text, quote) do
    case :binary.match(text, quote) do
      {offset, length} ->
        start = offset + 1

        if :binary.match(text, quote, scope: {start, byte_size(text) - start}) == :nomatch,
          do: {:ok, {offset, length}},
          else: @error

      :nomatch ->
        @error
    end
  end

  defp prefix(_, 0), do: ""

  defp prefix(text, bytes) do
    value = binary_part(text, 0, bytes)
    if String.valid?(value), do: value, else: prefix(text, bytes - 1)
  end

  defp fits?(value, limit), do: byte_size(Jason.encode!(value)) <= limit
  defp identifier(value), do: binary_part(JSON.digest(value), 0, 32)

  defp text?(text),
    do: is_binary(text) and String.valid?(text) and byte_size(text) <= @source_bytes

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
  defp positive?(value), do: JSON.safe_uint?(value) and value > 0
  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
end
