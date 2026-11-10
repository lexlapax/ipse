defmodule Ipse.Session.ProvidedSourceSet do
  @moduledoc """
  Host-owned fence for a declared provided-only source set.

  An export opts in with the exact catalog `source_contract` returned by
  `contract/0`. The Session derives the complete set from its own journaled
  invocation intent: every supplied source's identity, generation, body hash,
  observation/expiry times, origin and partition, plus the query, as-of time,
  artifact and options identity and the parent invocation. The worker supplies
  none of these facts and cannot extend the set: a fenced invocation may make
  only `model.complete` host calls, and only over a registered inference route.

  A content-free intent is appended with the invocation intent, against one
  journal reservation and before any feed or observation sees the parent, so it
  precedes every approval and send. The set is re-derived and compared, and the
  wall clock is checked against the recorded high-water and the earliest
  eligibility transition, before the dispatch intent, at the physical send, when
  model output returns to the worker and before inline delivery. Delivery also
  requires the result's reported `coverage.as_of_ms` to lie inside the fenced
  interval. Restore validates the same records and never redelivers a fenced
  result; it is historical only.
  """
  alias Ipse.JSON

  @contract Ipse.Extension.Catalog.source_contract()
  @domain "ipse.session.provided-source-set.v1"
  @intent_type "provided_source_set_intent"
  @release_type "provided_source_set_release"
  @intent_keys ~w(type version parent_invocation_id session_id parent_sha256 set_sha256 selected_at_ms as_of_ms transition_ms source_count)
  @release_keys ~w(type version parent_invocation_id intent_sha256 decision checked_at_ms result_sha256)
  @argument_keys ~w(search fetch retrieval rerank query limits sources)
  @source_keys ~w(source_id generation title text uri observed_at_ms event_at_ms expires_at_ms)
  @max_sources 10
  @partition "research-provided"

  def contract, do: @contract

  @doc "Whether a catalog descriptor declares the exact provided-set contract."
  def contract?(descriptor),
    do: is_map(descriptor) and descriptor["source_contract"] === @contract

  @doc """
  Derive the canonical set from an admitted invocation intent and host time.

  Only the closed provided-source argument shape is accepted, with between one
  and ten sources. Source positions are part of the set, so duplicate IDs remain
  distinct and reordering changes the digest.
  """
  def capture(intent, selected_at_ms) do
    descriptor = intent["descriptor"]
    identity = intent["identity"]
    payload = intent["payload"]
    args = payload["arguments"]

    with true <- contract?(descriptor) and descriptor["stage"] == "invoke.command",
         true <- JSON.safe_uint?(selected_at_ms),
         true <-
           id?(intent["invocation_id"]) and payload["invocation_id"] == intent["invocation_id"],
         true <- id?(payload["session_id"]),
         true <-
           JSON.sha256?(identity["artifact_sha256"]) and JSON.sha256?(identity["options_sha256"]),
         true <- arguments?(args) do
      explicit = Map.has_key?(args, "as_of_ms")

      {:ok,
       %{
         "version" => 1,
         "kind" => "provided_set",
         "parent_invocation_id" => intent["invocation_id"],
         "parent_sha256" => JSON.digest([intent]),
         "session_id" => payload["session_id"],
         "artifact_sha256" => identity["artifact_sha256"],
         "options_sha256" => identity["options_sha256"],
         "query" => args["query"],
         "as_of_ms" => if(explicit, do: args["as_of_ms"], else: selected_at_ms),
         "as_of_kind" => if(explicit, do: "explicit", else: "selected"),
         "selected_at_ms" => selected_at_ms,
         "sources" =>
           args["sources"]
           |> Enum.with_index()
           |> Enum.map(fn {source, position} ->
             %{
               "position" => position,
               "source_id" => source["source_id"],
               "generation" => source["generation"],
               "body_sha256" => JSON.sha256(source["text"]),
               "observed_at_ms" => source["observed_at_ms"],
               "expires_at_ms" => source["expires_at_ms"],
               "origin" => "provided",
               "partition" => @partition
             }
           end)
       }}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end

  @doc "Domain-separated canonical digest of a complete captured set."
  def digest(set) when is_map(set), do: JSON.digest([@domain, set])

  @doc """
  The earliest time after selection at which any source changes eligibility.

  Explicit as-of investigations fix eligibility and have no transition. Sources
  that expire at or before their observation never become eligible.
  """
  def transition(%{"as_of_kind" => "explicit"}), do: nil

  def transition(%{"selected_at_ms" => selected, "sources" => sources}) do
    sources
    |> Enum.flat_map(fn source ->
      observed = source["observed_at_ms"]
      expires = source["expires_at_ms"]

      cond do
        is_integer(expires) and expires <= observed -> []
        observed > selected -> [observed]
        is_integer(expires) and expires > selected -> [expires]
        true -> []
      end
    end)
    |> Enum.min(fn -> nil end)
  end

  @doc "Content-free intent journaled before the worker starts."
  def intent(set) do
    %{
      "type" => @intent_type,
      "version" => 1,
      "parent_invocation_id" => set["parent_invocation_id"],
      "session_id" => set["session_id"],
      "parent_sha256" => set["parent_sha256"],
      "set_sha256" => digest(set),
      "selected_at_ms" => set["selected_at_ms"],
      "as_of_ms" => set["as_of_ms"],
      "transition_ms" => transition(set),
      "source_count" => length(set["sources"])
    }
  end

  @doc "Re-derive the complete set from the journaled parent and compare the intent."
  def valid_intent?(event, parent) do
    with true <- keys?(event, @intent_keys),
         true <- event["type"] == @intent_type and event["version"] === 1,
         {:ok, set} <- capture(parent, event["selected_at_ms"]) do
      event === intent(set)
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc false
  # Session owner only: capture the set at host time before the worker starts.
  def begin(intent, now) do
    with {:ok, set} <- capture(intent, now) do
      event = intent(set)
      {:ok, event, %{intent: event, high_water: now}}
    end
  end

  @doc false
  # Session owner only. Re-derive the set from the journaled parent, then require
  # the clock to be at or after the high-water and before the earliest
  # transition. Success raises the high-water to this observation.
  def check(s), do: check(s, now(s))

  def check(%{invocation: %{provided_set: nil}} = s, _now), do: {:ok, s}

  def check(%{invocation: %{parent: parent, provided_set: fence} = invocation} = s, now)
      when is_map(parent) and is_map(fence) do
    if valid_intent?(fence.intent, parent) and current_at?(fence.intent, fence.high_water, now),
      do: {:ok, %{s | invocation: %{invocation | provided_set: %{fence | high_water: now}}}},
      else: :error
  rescue
    _ -> :error
  end

  def check(_, _), do: :error

  @doc false
  # The fence's wall clock. A production fence carries no clock, so this is the
  # system time; focused tests install a fixed clock in a fence to drive the
  # boundary checks deterministically.
  def now(%{invocation: %{provided_set: %{clock: clock}}}) when is_function(clock, 0),
    do: clock.()

  def now(_), do: System.system_time(:millisecond)

  @doc false
  def active?(%{invocation: %{provided_set: fence}}), do: is_map(fence)
  def active?(_), do: false

  @doc false
  # Only model.complete can run inside a fenced invocation; every other phase
  # is refused while a fence is active.
  def guard(s, "model.complete"), do: check(s)
  def guard(s, _phase), do: if(active?(s), do: :error, else: {:ok, s})

  @doc """
  Whether `now` may still use the set: at or after the recorded high-water and
  strictly before the earliest transition.
  """
  def current_at?(event, high_water, now),
    do:
      JSON.safe_uint?(now) and JSON.safe_uint?(high_water) and
        high_water >= event["selected_at_ms"] and now >= high_water and
        (is_nil(event["transition_ms"]) or now < event["transition_ms"])

  @doc """
  Whether a fenced result value reports an evidence time inside the fence.

  The value carries `coverage.as_of_ms`. With an explicit investigation time it
  must equal that time. Otherwise it must lie at or after selection, at or
  before the release check and strictly before the earliest transition. Only a
  refusal with no evidence and no claims, which carries no source content, may
  omit it.
  """
  def result_as_of?(parent, event, value, checked_at) do
    as_of = get_in(value, ["coverage", "as_of_ms"])

    cond do
      JSON.safe_uint?(as_of) and Map.has_key?(parent["payload"]["arguments"], "as_of_ms") ->
        as_of === event["as_of_ms"]

      JSON.safe_uint?(as_of) ->
        as_of >= event["selected_at_ms"] and as_of <= checked_at and
          (is_nil(event["transition_ms"]) or as_of < event["transition_ms"])

      is_nil(as_of) ->
        value["status"] == "refused" and value["evidence"] == [] and value["claims"] == []

      true ->
        false
    end
  rescue
    _ -> false
  end

  def release(event, decision, now, result) when decision in ~w(current withheld),
    do: %{
      "type" => @release_type,
      "version" => 1,
      "parent_invocation_id" => event["parent_invocation_id"],
      "intent_sha256" => JSON.digest([event]),
      "decision" => decision,
      "checked_at_ms" => now,
      "result_sha256" => if(decision == "current", do: JSON.digest([result]))
    }

  def valid_release?(release, event) do
    keys?(release, @release_keys) and release["type"] == @release_type and
      release["version"] === 1 and
      release["parent_invocation_id"] == event["parent_invocation_id"] and
      release["intent_sha256"] == JSON.digest([event]) and
      JSON.safe_uint?(release["checked_at_ms"]) and
      case release["decision"] do
        "current" ->
          release["checked_at_ms"] >= event["selected_at_ms"] and
            JSON.sha256?(release["result_sha256"]) and
            (is_nil(event["transition_ms"]) or release["checked_at_ms"] < event["transition_ms"])

        "withheld" ->
          is_nil(release["result_sha256"])

        _ ->
          false
      end
  rescue
    _ -> false
  end

  @doc "Historical display for a restored fenced result; its value is never redelivered."
  def display(raw),
    do: %{
      "name" => raw["descriptor"]["name"],
      "stage" => raw["descriptor"]["stage"],
      "value" => %{
        "status" => "withheld",
        "reason" => "provided_sources_historical",
        "historical_receipt" => true
      }
    }

  @doc """
  Validate fence records in journal order.

  A contract invocation intent is followed by its set intent before any action,
  release or result of that invocation; unrelated records, such as a feed
  delivery intent, may fall between them. A contract intent whose set intent
  never follows was interrupted before its worker started and may have no later
  action, release or result. A fenced invocation's only actions are
  `model.complete` calls, and its result must be inline, report a fenced as-of
  time and be bound by a current release. An intent without a result stays
  interrupted; it is never completed or replayed here.
  """
  def validate_events(events) when is_list(events) do
    events
    |> Enum.reduce_while(
      {:ok, %{expect: nil, active: nil, unstarted: MapSet.new()}},
      fn event, {:ok, state} ->
        case if(unstarted_use?(state, event), do: :error, else: step(state, event)) do
          {:ok, next} -> {:cont, {:ok, next}}
          :error -> {:halt, :error}
        end
      end
    )
    |> case do
      {:ok, _} -> :ok
      _ -> {:error, :invalid_provided_source_set}
    end
  rescue
    _ -> {:error, :invalid_provided_source_set}
  end

  def validate_events(_), do: {:error, :invalid_provided_source_set}

  # An action, release or result of a contract invocation whose set intent was
  # never journaled would mean its worker ran unfenced.
  defp unstarted_use?(state, event) do
    ids = unstarted(state)

    case event do
      %{"type" => type, "parent_invocation_id" => id}
      when type in ["extension_action_intent", @release_type] ->
        MapSet.member?(ids, id)

      %{"type" => "extension_invocation_result", "invocation_id" => id} ->
        MapSet.member?(ids, id)

      _ ->
        false
    end
  end

  defp unstarted(%{expect: nil, unstarted: ids}), do: ids
  defp unstarted(%{expect: parent, unstarted: ids}), do: MapSet.put(ids, parent["invocation_id"])

  defp step(%{expect: parent} = state, %{"type" => @intent_type} = event) when is_map(parent) do
    if event["parent_invocation_id"] == parent["invocation_id"] and valid_intent?(event, parent),
      do: {:ok, %{state | expect: nil, active: %{parent: parent, intent: event, release: nil}}},
      else: :error
  end

  # A new invocation ends any still-expected contract intent as never started.
  defp step(state, %{"type" => "extension_invocation_intent"} = event) do
    expect = if contract?(event["descriptor"]), do: event
    {:ok, %{state | expect: expect, active: nil, unstarted: unstarted(state)}}
  end

  defp step(_, %{"type" => @intent_type}), do: :error

  defp step(%{active: %{release: nil} = active} = state, %{"type" => @release_type} = event) do
    if valid_release?(event, active.intent),
      do: {:ok, %{state | active: %{active | release: event}}},
      else: :error
  end

  defp step(_, %{"type" => @release_type}), do: :error

  defp step(%{active: %{parent: parent}} = state, %{"type" => "extension_action_intent"} = event) do
    cond do
      event["parent_invocation_id"] != parent["invocation_id"] -> {:ok, state}
      get_in(event, ["request", "op"]) == "model.complete" -> {:ok, state}
      true -> :error
    end
  end

  defp step(
         %{active: %{parent: parent, intent: intent, release: release}} = state,
         %{"type" => "extension_invocation_result"} = event
       ) do
    cond do
      event["invocation_id"] != parent["invocation_id"] ->
        :error

      event["version"] in [1, 3] and is_map(release) and release["decision"] == "current" and
        release["result_sha256"] == JSON.digest([event]) and
          result_as_of?(parent, intent, event["value"], release["checked_at_ms"]) ->
        {:ok, %{state | active: nil}}

      true ->
        :error
    end
  end

  defp step(state, _), do: {:ok, state}

  defp arguments?(args) do
    is_map(args) and keys?(Map.delete(args, "as_of_ms"), @argument_keys) and
      (not Map.has_key?(args, "as_of_ms") or JSON.safe_uint?(args["as_of_ms"])) and
      Enum.all?(~w(search fetch retrieval), &text?(args[&1], 64)) and
      (is_nil(args["rerank"]) or text?(args["rerank"], 64)) and
      text?(args["query"], 1024) and is_map(args["limits"]) and
      is_list(args["sources"]) and length(args["sources"]) in 1..@max_sources and
      Enum.all?(args["sources"], &source?/1)
  end

  defp source?(source),
    do:
      keys?(source, @source_keys) and text?(source["source_id"], 256) and
        text?(source["title"], 128) and text?(source["text"], 65_536) and
        text?(source["uri"], 512) and is_integer(source["generation"]) and
        source["generation"] > 0 and JSON.safe_uint?(source["generation"]) and
        JSON.safe_uint?(source["observed_at_ms"]) and
        Enum.all?(
          ~w(event_at_ms expires_at_ms),
          &(is_nil(source[&1]) or JSON.safe_uint?(source[&1]))
        )

  defp text?(value, max),
    do: is_binary(value) and String.valid?(value) and byte_size(value) in 1..max

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
end
