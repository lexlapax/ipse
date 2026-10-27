defmodule Ipse.Session.ManagedReference do
  @moduledoc """
  Pure, bounded lineage for host-admitted managed conversation projections.

  This module authenticates neither receipts nor callers. Session must validate
  each producer's committed publication and supply the union of all of its reads
  and inherited inputs. Workers must never choose this metadata. A dependency is
  a normalized host receipt, not an interpretation of arbitrary stored JSON.

  Live eligibility belongs to an owned host task. Replay verifies the recorded
  transformation without IO and always leaves current eligibility pending. The
  original journal is never rewritten. Opaque provider continuations, assistant
  calls and derived checkpoints require an independently proven projection; this
  initial generic projector refuses them when withdrawal would be necessary.
  """
  alias Ipse.JSON

  defmodule State do
    @moduledoc false
    @enforce_keys [:session_id]
    defstruct [:session_id, dependencies: %{}, occurrences: %{}, bytes: 2]
  end

  defmodule Plan do
    @moduledoc false
    @enforce_keys [:state, :messages, :dependencies, :sha256]
    defstruct [:state, :messages, :dependencies, :sha256]
  end

  @error {:error, :managed_reference_refused}
  @projection_error {:error, :managed_reference_projection_unsafe}
  @dependency_bytes 8192
  @occurrence_dependencies 128
  @occurrence_bytes 131_072
  @dependencies 2048
  @bytes 4_194_304
  @occurrences 1024
  @event_bytes 12_582_912
  @dependency_keys ~w(version project_id namespace pin_sha256 policy_generation collection record validity)
  @dependency_v2_keys ~w(version project_id namespace pin_sha256 policy_generation collection subject)
  @collection_keys ~w(project generation floor floor_anchor manifest_sha256)
  @collection_v2_keys ~w(project generation floor floor_anchor root_state root_sha256 manifest_sha256)
  @validity_keys ~w(recipe_sha256 lineage source_versions valid_until_ms status dependencies)
  @record_keys ~w(key revision value_sha256)
  @producer_keys ~w(kind id parent_id)
  @admission_keys ~w(type version session_id occurrence_id producer position message_sha256 dependencies dependencies_sha256)
  @binding_keys ~w(version session_id turn_id request_id phase route_sha256 tools_sha256 source_generation policy_generation checked_at_ms deadline_ms)
  @verdict_keys ~w(dependency_sha256 status current)
  @reasons ~w(eligible expired suppressed root_changed policy_changed source_changed unavailable)
  @producer_kinds ~w(collection.result reference assistant checkpoint)
  @phases ~w(model compaction model.complete embedding.create decision.create)

  def limits do
    %{
      "dependency_bytes" => @dependency_bytes,
      "occurrence_dependencies" => @occurrence_dependencies,
      "occurrence_dependency_bytes" => @occurrence_bytes,
      "dependencies" => @dependencies,
      "dictionary_bytes" => @bytes,
      "occurrences" => @occurrences,
      "occurrence_index_bytes" => @bytes
    }
  end

  def new(session_id) do
    if id?(session_id), do: {:ok, %State{session_id: session_id}}, else: @error
  end

  @doc "Validate an already normalized host dependency; this grants no freshness or permission."
  def dependency?(%{"version" => 1} = d) do
    keys?(d, @dependency_keys) and d["version"] === 1 and
      Enum.all?(~w(project_id namespace pin_sha256), &JSON.sha256?(d[&1])) and
      uint?(d["policy_generation"]) and collection?(d["collection"], d["namespace"]) and
      (is_nil(d["record"]) or record?(d["record"])) and validity?(d["validity"]) and
      fits?(d, @dependency_bytes)
  rescue
    _ -> false
  end

  def dependency?(%{"version" => 2} = d) do
    keys?(d, @dependency_v2_keys) and
      Enum.all?(~w(project_id namespace pin_sha256), &JSON.sha256?(d[&1])) and
      uint?(d["policy_generation"]) and collection_v2?(d["collection"], d["namespace"]) and
      subject?(d["subject"], d["collection"]["root_state"]) and fits?(d, @dependency_bytes)
  rescue
    _ -> false
  end

  def dependency?(_), do: false

  @doc "Canonical union with explicit refusal at the active-plan bound; never evicts lineage."
  def union(groups) when is_list(groups) and length(groups) <= @dependencies do
    Enum.reduce_while(groups, {:ok, %{}}, fn group, {:ok, acc} ->
      if is_list(group) and length(group) <= @dependencies and Enum.all?(group, &dependency?/1) do
        next = Enum.reduce(group, acc, &Map.put(&2, digest(&1), &1))
        if dictionary?(next), do: {:cont, {:ok, next}}, else: {:halt, @error}
      else
        {:halt, @error}
      end
    end)
    |> case do
      {:ok, dictionary} -> {:ok, ordered(dictionary)}
      error -> error
    end
  rescue
    _ -> @error
  end

  def union(_), do: @error

  @doc "Union inherited occurrences with additional host reads; missing or withdrawn parents refuse."
  def inherit(%State{} = state, ids, reads) when is_list(ids) and length(ids) <= @occurrences do
    with true <- state?(state) and length(Enum.uniq(ids)) == length(ids),
         {:ok, parents} <- parents(state, ids) do
      union([reads | parents])
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def inherit(_, _, _), do: @error

  @doc "Bind a committed producer's complete lineage union to an exact message position and hash."
  def admit(%State{} = state, producer, position, message, dependencies) do
    with true <- state?(state) and producer?(producer) and uint?(position),
         true <- message?(message) and producer_message?(producer, message),
         {:ok, deps} <- union([dependencies]),
         true <- deps != [] and occurrence_fits?(producer, deps),
         event = admission(state.session_id, producer, position, message, deps),
         false <- Map.has_key?(state.occurrences, event["occurrence_id"]),
         false <- Enum.any?(state.occurrences, fn {_, item} -> item.position == position end),
         entry = %{
           producer: producer,
           position: position,
           original_sha256: event["message_sha256"],
           current_sha256: event["message_sha256"],
           dependency_ids: Enum.map(deps, &digest/1),
           withdrawn: false
         },
         {:ok, next} <-
           rebuild(state, Map.put(state.occurrences, event["occurrence_id"], entry), deps) do
      {:ok, event, next}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def admit(_, _, _, _, _), do: @error

  @doc "Replay admission only after Session validates the actual committed producer and message."
  def replay_admission(%State{} = state, event, messages) do
    with true <- keys?(event, @admission_keys) and is_list(messages),
         true <- uint?(event["position"]) and event["position"] < length(messages),
         {:ok, expected, next} <-
           admit(
             state,
             event["producer"],
             event["position"],
             Enum.at(messages, event["position"]),
             event["dependencies"]
           ),
         true <- expected === event do
      {:ok, next}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def replay_admission(_, _, _), do: @error

  @doc "Select every active occurrence, including prior answers and tool results, for a live barrier."
  def plan(%State{} = state, messages) do
    with true <- state?(state) and is_list(messages),
         true <-
           Enum.all?(state.occurrences, fn {_, item} ->
             item.position < length(messages) and
               digest(Enum.at(messages, item.position)) == item.current_sha256
           end),
         true <- Ipse.Session.Reference.safe_tail?(messages),
         deps = ordered(state.dependencies),
         sha = plan_digest(state, messages) do
      {:ok, %Plan{state: state, messages: messages, dependencies: deps, sha256: sha}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def plan(_, _), do: @error

  @doc "Apply exact host verdicts. Fresh replacement receipts may clear an unchanged record at a newer root."
  def project(%Plan{} = plan, verdicts, binding) do
    with true <- valid_plan?(plan) and binding?(binding, plan.state.session_id),
         {:ok, by_id} <- verdicts(plan.state.dependencies, verdicts, binding),
         {:ok, messages, entries, withdrawals} <- withdraw(plan, by_id),
         current =
           Enum.flat_map(verdicts, fn v -> if v["current"], do: [v["current"]], else: [] end),
         {:ok, next} <- rebuild(plan.state, entries, current),
         event = projection(plan, verdicts, binding, messages, withdrawals),
         true <- is_nil(event) or fits?(event, @event_bytes) do
      {:ok, event, messages, next}
    else
      {:error, :managed_reference_projection_unsafe} -> @projection_error
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def project(_, _, _), do: @error

  @doc "Pure historical verification. The independently admitted dispatch binding is mandatory."
  def replay(%State{} = state, messages, event, expected_binding) do
    with true <- is_map(event) and event["binding"] === expected_binding,
         {:ok, plan} <- plan(state, messages),
         {:ok, expected, projected, next} <- project(plan, event["verdicts"], expected_binding),
         true <- expected != nil and expected === event do
      {:ok, %{state: next, messages: projected, live_pending: true}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def replay(_, _, _, _), do: @error

  @doc "Versioned compaction taint union; invalidation requires safe original reconstruction or refusal."
  def checkpoint(%Plan{} = plan, covered) do
    with true <- valid_plan?(plan) and covered?(covered, plan.messages),
         selected =
           Enum.filter(plan.state.occurrences, fn {_, item} -> item.position < covered end),
         ids =
           selected
           |> Enum.flat_map(fn {_, item} -> item.dependency_ids end)
           |> Enum.uniq()
           |> Enum.sort(),
         deps = Enum.map(ids, &Map.fetch!(plan.state.dependencies, &1)),
         receipt = %{
           "version" => 2,
           "session_id" => plan.state.session_id,
           "covered_messages" => covered,
           "prefix_sha256" => JSON.digest(Enum.take(plan.messages, covered)),
           "occurrence_ids" => selected |> Enum.map(&elem(&1, 0)) |> Enum.sort(),
           "dependencies" => deps,
           "dependencies_sha256" => JSON.digest(deps)
         },
         true <- fits?(deps, @bytes) do
      {:ok, receipt}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def checkpoint(_, _), do: @error

  defp covered?(count, messages),
    do: is_integer(count) and count > 0 and count <= length(messages)

  defp admission(session, producer, position, message, deps) do
    body = %{
      "type" => "managed_reference_admitted",
      "version" => 1,
      "session_id" => session,
      "producer" => producer,
      "position" => position,
      "message_sha256" => digest(message),
      "dependencies" => deps,
      "dependencies_sha256" => JSON.digest(deps)
    }

    Map.put(body, "occurrence_id", digest(body))
  end

  defp projection(%{dependencies: []}, _, _, _, _), do: nil

  defp projection(plan, verdicts, binding, messages, withdrawals) do
    %{
      "type" => "managed_reference_projected",
      "version" => 1,
      "session_id" => plan.state.session_id,
      "binding" => binding,
      "plan_sha256" => plan.sha256,
      "before_sha256" => JSON.digest(plan.messages),
      "after_sha256" => JSON.digest(messages),
      "verdicts" => Enum.sort_by(verdicts, & &1["dependency_sha256"]),
      "withdrawals" => Enum.sort_by(withdrawals, & &1["position"])
    }
  end

  defp withdraw(plan, verdicts) do
    Enum.reduce_while(plan.state.occurrences, {:ok, plan.messages, %{}, []}, fn {id, item},
                                                                                {:ok, messages,
                                                                                 entries,
                                                                                 withdrawals} ->
      invalid = Enum.filter(item.dependency_ids, &(verdicts[&1]["status"] != "eligible"))

      cond do
        item.withdrawn ->
          {:cont, {:ok, messages, Map.put(entries, id, item), withdrawals}}

        invalid == [] ->
          ids =
            Enum.map(item.dependency_ids, &digest(verdicts[&1]["current"]))
            |> Enum.uniq()
            |> Enum.sort()

          {:cont,
           {:ok, messages, Map.put(entries, id, %{item | dependency_ids: ids}), withdrawals}}

        true ->
          original = Enum.at(messages, item.position)

          if safely_projectable?(original, item.producer) do
            reason = invalid |> Enum.sort() |> hd() |> then(&verdicts[&1]["status"])

            text =
              "[Managed historical content withdrawn: #{reason}. Occurrence #{id}. Original transcript retained.]"

            projected = Map.put(original, "content", text)

            updated = %{
              item
              | current_sha256: digest(projected),
                dependency_ids: [],
                withdrawn: true
            }

            receipt = %{
              "occurrence_id" => id,
              "position" => item.position,
              "original_sha256" => item.original_sha256,
              "previous_sha256" => item.current_sha256,
              "projection_sha256" => digest(projected),
              "reason" => reason
            }

            {:cont,
             {:ok, List.replace_at(messages, item.position, projected),
              Map.put(entries, id, updated), [receipt | withdrawals]}}
          else
            {:halt, @projection_error}
          end
      end
    end)
  end

  defp safely_projectable?(message, producer) do
    producer["kind"] != "checkpoint" and not Map.has_key?(message, "ipse_checkpoint") and
      not Map.has_key?(message, "provider_data") and message["tool_calls"] in [nil, []] and
      not Map.has_key?(message, "ipse_result_excerpt") and
      safe_markers?(message) and
      Enum.all?(
        Map.keys(message),
        &(&1 in ~w(role content tool_call_id tool_calls ipse_reference ipse_tool_outcome ipse_result_excerpt))
      )
  end

  defp safe_markers?(message) do
    (not Map.has_key?(message, "ipse_reference") or
       Ipse.Session.Reference.reference?(message)) and
      (not Map.has_key?(message, "ipse_tool_outcome") or
         (keys?(message["ipse_tool_outcome"], ~w(status approval)) and
            message["ipse_tool_outcome"]["status"] in ~w(ok failed denied unknown cancelled) and
            message["ipse_tool_outcome"]["approval"] in ~w(approved session_allow not_required saved_consent denied historical_unknown)))
  end

  defp occurrence_fits?(%{"kind" => kind}, deps) when kind in ~w(assistant checkpoint),
    do: length(deps) <= @dependencies and fits?(deps, @bytes)

  defp occurrence_fits?(_, deps),
    do: length(deps) <= @occurrence_dependencies and fits?(deps, @occurrence_bytes)

  defp producer_message?(%{"kind" => kind}, %{"role" => role}) do
    case kind do
      "reference" -> role == "user"
      "collection.result" -> role == "tool"
      derived when derived in ~w(assistant checkpoint) -> role == "assistant"
    end
  end

  defp verdicts(dependencies, values, binding) do
    with true <- is_list(values) and length(values) == map_size(dependencies),
         true <-
           Enum.all?(values, fn value ->
             keys?(value, @verdict_keys) and
               Map.has_key?(dependencies, value["dependency_sha256"]) and
               value["status"] in @reasons and
               current?(dependencies[value["dependency_sha256"]], value, binding["checked_at_ms"])
           end),
         by_id = Map.new(values, &{&1["dependency_sha256"], &1}),
         true <- map_size(by_id) == map_size(dependencies) do
      {:ok, by_id}
    else
      _ -> @error
    end
  end

  defp current?(old, %{"status" => "eligible", "current" => current}, now) do
    dependency?(current) and
      Map.take(old, ~w(version project_id namespace pin_sha256 policy_generation)) ===
        Map.take(current, ~w(version project_id namespace pin_sha256 policy_generation)) and
      same_subject?(old, current, now) and
      current["collection"]["generation"] >= old["collection"]["generation"] and
      current["collection"]["floor"] >= old["collection"]["floor"] and
      (current["collection"]["generation"] > old["collection"]["generation"] or
         current["collection"] === old["collection"])
  end

  defp current?(_, %{"current" => nil}, _), do: true
  defp current?(_, _, _), do: false

  defp same_subject?(%{"version" => 1} = old, current, now),
    do:
      old["record"] === current["record"] and
        same_validity?(old["validity"], current["validity"], now)

  defp same_subject?(%{"subject" => %{"kind" => "record"} = old}, current, now),
    do:
      current["subject"]["kind"] == "record" and
        old["record"] === current["subject"]["record"] and
        same_validity?(old["validity"], current["subject"]["validity"], now)

  defp same_subject?(%{"subject" => %{"kind" => "absence"} = old}, current, _),
    do: old === current["subject"]

  defp same_validity?(old, current, now),
    do:
      Map.take(old, ~w(recipe_sha256 lineage source_versions)) ===
        Map.take(current, ~w(recipe_sha256 lineage source_versions)) and
        current["status"] == "eligible" and
        (is_nil(current["valid_until_ms"]) or current["valid_until_ms"] > now)

  defp binding?(b, session) do
    keys?(b, @binding_keys) and b["version"] === 1 and b["session_id"] == session and
      Enum.all?(~w(session_id turn_id request_id), &id?(b[&1])) and b["phase"] in @phases and
      Enum.all?(~w(route_sha256 tools_sha256), &JSON.sha256?(b[&1])) and
      Enum.all?(~w(source_generation policy_generation checked_at_ms deadline_ms), &uint?(b[&1])) and
      b["deadline_ms"] >= b["checked_at_ms"] and b["deadline_ms"] - b["checked_at_ms"] <= 120_000
  end

  defp collection?(c, namespace) do
    keys?(c, @collection_keys) and c["project"] == namespace and
      uint?(c["generation"]) and uint?(c["floor"]) and JSON.sha256?(c["manifest_sha256"]) and
      ((c["floor"] === 0 and is_nil(c["floor_anchor"])) or
         (c["floor"] > 0 and id?(c["floor_anchor"])))
  end

  defp collection_v2?(c, namespace) do
    keys?(c, @collection_v2_keys) and c["project"] == namespace and
      uint?(c["generation"]) and uint?(c["floor"]) and
      ((c["floor"] === 0 and is_nil(c["floor_anchor"])) or
         (c["floor"] > 0 and id?(c["floor_anchor"]))) and
      case c["root_state"] do
        "absent" ->
          c["generation"] === 0 and c["floor"] === 0 and is_nil(c["root_sha256"]) and
            is_nil(c["manifest_sha256"])

        "present" ->
          JSON.sha256?(c["root_sha256"]) and JSON.sha256?(c["manifest_sha256"])

        _ ->
          false
      end
  end

  defp subject?(%{"kind" => "record"} = subject, "present"),
    do:
      keys?(subject, ~w(kind record validity)) and record?(subject["record"]) and
        validity?(subject["validity"])

  defp subject?(%{"kind" => "absence"} = subject, _),
    do: keys?(subject, ~w(kind selector)) and selector?(subject["selector"])

  defp subject?(_, _), do: false

  defp selector?(%{"kind" => "record"} = selector),
    do: keys?(selector, ~w(kind key)) and key?(selector["key"])

  defp selector?(%{"kind" => "collection"} = selector),
    do: keys?(selector, ~w(kind))

  defp selector?(_), do: false

  defp validity?(v) do
    keys?(v, @validity_keys) and JSON.sha256?(v["recipe_sha256"]) and JSON.sha256?(v["lineage"]) and
      (is_nil(v["valid_until_ms"]) or uint?(v["valid_until_ms"])) and
      v["status"] in ~w(eligible suppressed unavailable) and
      is_list(v["source_versions"]) and length(v["source_versions"]) <= 32 and
      Enum.all?(v["source_versions"], fn row ->
        keys?(row, ~w(id version)) and source_id?(row["id"]) and source_id?(row["version"])
      end) and sorted_unique?(v["source_versions"]) and
      is_list(v["dependencies"]) and length(v["dependencies"]) <= 32 and
      Enum.all?(v["dependencies"], &record?/1) and sorted_unique?(v["dependencies"])
  end

  defp record?(r),
    do:
      keys?(r, @record_keys) and key?(r["key"]) and positive?(r["revision"]) and
        JSON.sha256?(r["value_sha256"])

  defp producer?(p),
    do:
      keys?(p, @producer_keys) and p["kind"] in @producer_kinds and producer_id?(p["id"]) and
        (is_nil(p["parent_id"]) or producer_id?(p["parent_id"]))

  defp message?(m),
    do:
      is_map(m) and m["role"] in ~w(user assistant tool) and is_binary(m["content"]) and
        String.valid?(m["content"]) and fits?(m, 1_048_576)

  defp id?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{32}\z/, v)
  defp source_id?(v), do: id?(v) or JSON.sha256?(v)

  defp producer_id?(v),
    do: is_binary(v) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,127}\z/, v)

  defp key?(v), do: is_binary(v) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,95}\z/, v)
  defp uint?(v), do: JSON.safe_uint?(v)
  defp positive?(v), do: uint?(v) and v > 0
  defp keys?(m, keys), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(keys)
  defp digest(value), do: JSON.digest([value])
  defp fits?(value, bytes), do: byte_size(Jason.encode!(value)) <= bytes
  defp ordered(dictionary), do: dictionary |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))

  defp sorted_unique?(items),
    do: Enum.map(items, &digest/1) == Enum.map(items, &digest/1) |> Enum.uniq() |> Enum.sort()

  defp dictionary?(d), do: map_size(d) <= @dependencies and fits?(ordered(d), @bytes)

  defp parents(state, ids) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, groups} ->
      case state.occurrences[id] do
        %{withdrawn: false, dependency_ids: deps} ->
          {:cont, {:ok, [Enum.map(deps, &Map.fetch!(state.dependencies, &1)) | groups]}}

        _ ->
          {:halt, @error}
      end
    end)
  end

  defp rebuild(state, occurrences, added) do
    dictionary = Enum.reduce(added, state.dependencies, &Map.put(&2, digest(&1), &1))
    ids = occurrences |> Enum.flat_map(fn {_, item} -> item.dependency_ids end) |> Enum.uniq()
    dictionary = Map.take(dictionary, ids)
    bytes = byte_size(Jason.encode!(ordered(dictionary)))

    if length(ids) == map_size(dictionary) and map_size(occurrences) <= @occurrences and
         dictionary?(dictionary) and index_bytes(occurrences) <= @bytes and
         occurrence_bounds?(occurrences, dictionary) do
      {:ok, %{state | occurrences: occurrences, dependencies: dictionary, bytes: bytes}}
    else
      @error
    end
  end

  defp index_bytes(occurrences) do
    occurrences
    |> Enum.map(fn {id, item} ->
      [id, Map.new(item, fn {key, value} -> {Atom.to_string(key), value} end)]
    end)
    |> Jason.encode!()
    |> byte_size()
  end

  defp occurrence_bounds?(occurrences, dictionary) do
    Enum.all?(occurrences, fn {_, item} ->
      occurrence_fits?(item.producer, Enum.map(item.dependency_ids, &Map.fetch!(dictionary, &1)))
    end)
  end

  defp state?(%State{} = state) do
    id?(state.session_id) and map_size(state.occurrences) <= @occurrences and
      dictionary?(state.dependencies) and
      Enum.all?(state.dependencies, fn {id, dep} -> dependency?(dep) and id == digest(dep) end) and
      state.bytes == byte_size(Jason.encode!(ordered(state.dependencies))) and
      index_bytes(state.occurrences) <= @bytes and
      occurrence_bounds?(state.occurrences, state.dependencies) and
      length(Enum.uniq_by(state.occurrences, fn {_, item} -> item.position end)) ==
        map_size(state.occurrences) and
      Enum.all?(state.occurrences, fn {id, item} ->
        JSON.sha256?(id) and
          keys?(item, [
            :producer,
            :position,
            :original_sha256,
            :current_sha256,
            :dependency_ids,
            :withdrawn
          ]) and
          producer?(item.producer) and uint?(item.position) and
          JSON.sha256?(item.original_sha256) and JSON.sha256?(item.current_sha256) and
          is_boolean(item.withdrawn) and
          is_list(item.dependency_ids) and length(item.dependency_ids) <= @dependencies and
          item.dependency_ids == Enum.sort(Enum.uniq(item.dependency_ids)) and
          Enum.all?(item.dependency_ids, &Map.has_key?(state.dependencies, &1)) and
          ((item.withdrawn and item.dependency_ids == []) or
             (not item.withdrawn and item.dependency_ids != []))
      end) and
      state.occurrences |> Enum.flat_map(fn {_, item} -> item.dependency_ids end) |> MapSet.new() ==
        MapSet.new(Map.keys(state.dependencies))
  rescue
    _ -> false
  end

  defp plan_digest(state, messages) do
    occurrences = state.occurrences |> Enum.sort() |> Enum.map(fn {id, item} -> [id, item] end)

    JSON.digest([
      state.session_id,
      JSON.digest(messages),
      occurrences,
      ordered(state.dependencies)
    ])
  end

  defp valid_plan?(plan) do
    case plan(plan.state, plan.messages) do
      {:ok, expected} -> expected == plan
      _ -> false
    end
  end
end
