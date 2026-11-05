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
  @digest_cache {__MODULE__, :digest_cache}
  @digest_cache_entries 128
  @digest_cache_value_bytes 8192
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
  @producer_kinds ~w(collection.result reference assistant assistant.ollama_text checkpoint)
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

  def dependency?(%{"version" => 3} = d) do
    keys?(d, @dependency_v2_keys) and
      Enum.all?(~w(project_id namespace pin_sha256), &JSON.sha256?(d[&1])) and
      uint?(d["policy_generation"]) and collection_v2?(d["collection"], d["namespace"]) and
      keys?(d["subject"], ~w(kind request_sha256 result_sha256)) and
      d["subject"]["kind"] == "root_observation" and
      Enum.all?(~w(request_sha256 result_sha256), &JSON.sha256?(d["subject"][&1])) and
      fits?(d, @dependency_bytes)
  rescue
    _ -> false
  end

  def dependency?(%{"version" => 4} = d) do
    subject = d["subject"]

    keys?(d, @dependency_v2_keys) and
      Enum.all?(~w(project_id namespace pin_sha256), &JSON.sha256?(d[&1])) and
      uint?(d["policy_generation"]) and collection_v2?(d["collection"], d["namespace"]) and
      keys?(
        subject,
        ~w(kind key request_sha256 result_sha256 publication_policy_sha256 record validity)
      ) and
      subject["kind"] == "record_observation" and key?(subject["key"]) and
      not String.starts_with?(subject["key"], "host.validity.") and
      subject["request_sha256"] == digest(%{"op" => "get_record", "key" => subject["key"]}) and
      JSON.sha256?(subject["result_sha256"]) and
      (is_nil(subject["publication_policy_sha256"]) or
         JSON.sha256?(subject["publication_policy_sha256"])) and
      record_observation?(subject, d["collection"]["root_state"]) and
      fits?(d, @dependency_bytes)
  rescue
    _ -> false
  end

  # Historical selections are distinct from current-record observations and
  # bind the authenticated retirement edge without requiring successor bytes.
  def dependency?(%{"version" => 5} = d) do
    subject = d["subject"]
    successor = subject["successor"]

    keys?(d, @dependency_v2_keys) and
      Enum.all?(~w(project_id namespace pin_sha256), &JSON.sha256?(d[&1])) and
      uint?(d["policy_generation"]) and collection_v2?(d["collection"], d["namespace"]) and
      keys?(
        subject,
        ~w(kind key request_sha256 result_sha256 publication_policy_sha256 record validity successor superseded_at_ms)
      ) and
      subject["kind"] == "historical_record_observation" and key?(subject["key"]) and
      subject["key"] == "note." <> subject["validity"]["lineage"] and
      subject["request_sha256"] == digest(%{"op" => "get_record", "key" => subject["key"]}) and
      JSON.sha256?(subject["result_sha256"]) and
      JSON.sha256?(subject["publication_policy_sha256"]) and
      d["collection"]["root_state"] == "present" and record?(subject["record"]) and
      subject["record"]["key"] == subject["key"] and validity?(subject["validity"]) and
      keys?(successor, ~w(key sha256)) and key?(successor["key"]) and
      history_key?(successor["key"]) and
      successor["key"] != subject["key"] and JSON.sha256?(successor["sha256"]) and
      uint?(subject["superseded_at_ms"]) and fits?(d, @dependency_bytes)
  rescue
    _ -> false
  end

  # Accepted decisions bind their original review journal and immutable link;
  # they are not interchangeable with literal-source or historical records.
  def dependency?(%{"version" => 6} = d) do
    subject = d["subject"]
    acceptance = subject["acceptance"]

    keys?(d, @dependency_v2_keys) and
      Enum.all?(~w(project_id namespace pin_sha256), &JSON.sha256?(d[&1])) and
      uint?(d["policy_generation"]) and collection_v2?(d["collection"], d["namespace"]) and
      d["collection"]["root_state"] == "present" and
      keys?(
        subject,
        ~w(kind key request_sha256 result_sha256 publication_policy_sha256 record validity acceptance)
      ) and
      subject["kind"] == "accepted_decision_observation" and
      subject["key"] == "note." <> subject["validity"]["lineage"] and
      subject["request_sha256"] == digest(%{"op" => "get_record", "key" => subject["key"]}) and
      JSON.sha256?(subject["result_sha256"]) and
      JSON.sha256?(subject["publication_policy_sha256"]) and
      record?(subject["record"]) and subject["record"]["key"] == subject["key"] and
      validity?(subject["validity"]) and
      keys?(
        acceptance,
        ~w(journal_id journal_kind event_sha256 link) ++
          if(Map.has_key?(acceptance, "retention"), do: ["retention"], else: [])
      ) and
      id?(acceptance["journal_id"]) and
      acceptance["journal_kind"] in ~w(knowledge_management session) and
      JSON.sha256?(acceptance["event_sha256"]) and record?(acceptance["link"]) and
      acceptance["link"]["key"] =~ ~r/\Aaccept\.[0-9a-f]{64}\z/ and
      acceptance["link"]["revision"] === subject["record"]["revision"] and
      (not Map.has_key?(acceptance, "retention") or
         accepted_retention?(acceptance["retention"], subject)) and
      length(subject["validity"]["source_versions"]) === 1 and
      subject["validity"]["dependencies"] === [acceptance["link"]] and
      fits?(d, @dependency_bytes)
  rescue
    _ -> false
  end

  # A pending proposal is assessment input, never an eligible saved fact.
  def dependency?(%{"version" => 7} = d) do
    subject = d["subject"]
    validity = subject["validity"]

    keys?(d, @dependency_v2_keys) and
      Enum.all?(~w(project_id namespace pin_sha256), &JSON.sha256?(d[&1])) and
      uint?(d["policy_generation"]) and collection_v2?(d["collection"], d["namespace"]) and
      d["collection"]["root_state"] == "present" and
      keys?(
        subject,
        ~w(kind key request_sha256 result_sha256 publication_policy_sha256 record validity assessment_sha256)
      ) and
      subject["kind"] == "pending_proposal_observation" and
      Regex.match?(~r/\Apending\.[0-9a-f]{64}\z/, subject["key"]) and
      subject["request_sha256"] == digest(%{"op" => "get_record", "key" => subject["key"]}) and
      JSON.sha256?(subject["result_sha256"]) and
      JSON.sha256?(subject["publication_policy_sha256"]) and
      JSON.sha256?(subject["assessment_sha256"]) and
      record?(subject["record"]) and subject["record"]["key"] === subject["key"] and
      keys?(validity, @validity_keys) and validity["status"] === "never_current" and
      validity?(Map.put(validity, "status", "eligible")) and
      length(validity["source_versions"]) === 1 and validity["dependencies"] === [] and
      is_integer(validity["valid_until_ms"]) and fits?(d, @dependency_bytes)
  rescue
    _ -> false
  end

  def dependency?(_), do: false

  defp accepted_retention?(retention, subject) do
    keys?(retention, ~w(version kind choice_sha256 policy observed_at_ms)) and
      retention["version"] === 1 and retention["kind"] === "native_retention_choice" and
      JSON.sha256?(retention["choice_sha256"]) and uint?(retention["observed_at_ms"]) and
      case Ipse.Extension.Collection.ManagedRetention.selected(
             retention["policy"],
             retention["observed_at_ms"]
           ) do
        {:ok, _, deadline} -> deadline === subject["validity"]["valid_until_ms"]
        _ -> false
      end
  end

  @doc "Check a host-refreshed receipt against the original dependency without extending its authority."
  def current?(old, current, now) do
    dependency?(old) and JSON.safe_uint?(now) and
      verdict_current?(old, %{"status" => "eligible", "current" => current}, now)
  rescue
    _ -> false
  end

  @doc "Canonical union with explicit refusal at the active-plan bound; never evicts lineage."
  def union(groups) when is_list(groups) and length(groups) <= @dependencies do
    Enum.reduce_while(groups, {:ok, %{}}, fn group, {:ok, acc} ->
      if is_list(group) and length(group) <= @dependencies and Enum.all?(group, &dependency?/1) do
        next = Enum.reduce(group, acc, &Map.put(&2, dependency_digest(&1), &1))
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

  @doc false
  def with_digest_cache(fun) when is_function(fun, 0) do
    missing = make_ref()
    previous = Process.get(@digest_cache, missing)
    Process.put(@digest_cache, %{})

    try do
      fun.()
    after
      if previous === missing,
        do: Process.delete(@digest_cache),
        else: Process.put(@digest_cache, previous)
    end
  end

  @doc false
  def dependency_digest(value) do
    case Process.get(@digest_cache) do
      cache when is_map(cache) ->
        # This caches a pure hash, not the validation or freshness of a
        # dependency. Exact term bytes avoid equality aliases such as -0.0.
        signature = :erlang.term_to_binary(value, [:deterministic])

        case Map.fetch(cache, signature) do
          {:ok, hash} ->
            hash

          :error ->
            hash = digest(value)

            if map_size(cache) < @digest_cache_entries and
                 byte_size(signature) <= @digest_cache_value_bytes do
              Process.put(@digest_cache, Map.put(cache, signature, hash))
            end

            hash
        end

      _ ->
        digest(value)
    end
  end

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

  @doc "Read complete active dependencies while a native tool sequence may still be unfinished."
  def dependencies(%State{} = state, messages) do
    with true <- state?(state) and is_list(messages),
         true <-
           Enum.all?(state.occurrences, fn {_, item} ->
             item.position < length(messages) and
               digest(Enum.at(messages, item.position)) == item.current_sha256
           end) do
      {:ok, ordered(state.dependencies)}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Rebuild exact host-projected messages, retaining every matching input and derived dependency."
  def rebuild_projection(%State{} = state, before, after_messages, producer, derived) do
    with {:ok, _} <- dependencies(state, before),
         {:ok, derived} <- union([derived]),
         {:ok, empty} <- new(state.session_id) do
      Enum.with_index(after_messages)
      |> Enum.reduce_while({:ok, empty}, fn {message, position}, {:ok, next} ->
        matching =
          Enum.filter(state.occurrences, fn {_, item} ->
            Enum.at(before, item.position) === message
          end)

        groups =
          Enum.map(matching, fn {_, item} ->
            Enum.map(item.dependency_ids, &Map.fetch!(state.dependencies, &1))
          end)

        groups = [derived | groups]

        with {:ok, deps} <- union(groups) do
          if deps == [] do
            {:cont, {:ok, next}}
          else
            selected =
              case matching do
                [{_, item} | _] -> item.producer
                [] -> producer
              end

            selected =
              Map.put(
                selected,
                "kind",
                case message["role"] do
                  "tool" ->
                    "collection.result"

                  "user" ->
                    "reference"

                  "assistant" ->
                    if selected["kind"] == "checkpoint", do: "checkpoint", else: "assistant"
                end
              )

            case admit(next, selected, position, message, deps) do
              {:ok, _, admitted} -> {:cont, {:ok, admitted}}
              _ -> {:halt, @error}
            end
          end
        else
          _ -> {:halt, @error}
        end
      end)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

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
  def project(plan, verdicts, binding, historical_writes \\ %{})

  def project(%Plan{} = plan, verdicts, binding, historical_writes)
      when is_map(historical_writes) do
    with true <- valid_plan?(plan) and binding?(binding, plan.state.session_id),
         {:ok, by_id} <- verdicts(plan.state.dependencies, verdicts, binding),
         {:ok, messages, entries, withdrawals} <- withdraw(plan, by_id, historical_writes),
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

  def project(_, _, _, _), do: @error

  @doc false
  def project_root_history(%Plan{} = plan, binding, evidence) when is_map(evidence) do
    with true <- valid_plan?(plan) and binding?(binding, plan.state.session_id),
         true <- Ipse.Session.Reference.safe_tail?(plan.messages),
         old = plan.dependencies,
         guard = evidence["fresh_dependency"],
         prior_dependencies = Enum.reject(old, &current_root_metadata?(&1, guard)),
         true <- root_history_evidence?(old, evidence),
         prior =
           Enum.filter(prior_dependencies, &(&1["version"] == 3))
           |> Enum.min_by(& &1["collection"]["generation"]),
         notice =
           root_history_notice(
             prior["collection"]["generation"],
             guard["collection"]["generation"],
             evidence["management"]
           ),
         messages = plan.messages ++ [notice],
         retained = Enum.reject(old, &prior_root_metadata?(&1, guard)),
         occurrences =
           Map.new(plan.state.occurrences, fn {id, item} ->
             ids =
               Enum.map(item.dependency_ids, fn dependency_id ->
                 if prior_root_metadata?(plan.state.dependencies[dependency_id], guard),
                   do: digest(guard),
                   else: dependency_id
               end)
               |> Enum.uniq()
               |> Enum.sort()

             {id, if(item.withdrawn, do: item, else: %{item | dependency_ids: ids})}
           end),
         {:ok, next} <- rebuild(plan.state, occurrences, [guard | retained]),
         producer = %{"kind" => "reference", "id" => evidence["operation_id"], "parent_id" => nil},
         {:ok, _, next} <- admit(next, producer, length(plan.messages), notice, [guard]),
         event = %{
           "type" => "managed_root_transition",
           "version" =>
             cond do
               evidence["management"] -> 2
               evidence["root_chain"] -> 3
               true -> 1
             end,
           "session_id" => plan.state.session_id,
           "binding" => binding,
           "plan_sha256" => plan.sha256,
           "before_sha256" => JSON.digest(plan.messages),
           "after_sha256" => JSON.digest(messages),
           "old_dependencies" => old,
           "old_dependencies_sha256" => JSON.digest(old),
           "own_action_sha256" => evidence["own_action_sha256"],
           "operation_id" => evidence["operation_id"],
           "receipt_sha256" => evidence["receipt_sha256"],
           "fresh_observation" => evidence["fresh_observation"],
           "inspection" => evidence["inspection"],
           "fresh_dependency" => guard,
           "notice_sha256" => digest(notice)
         },
         event =
           if(evidence["management"],
             do: Map.put(event, "management", evidence["management"]),
             else: event
           ),
         event =
           if(evidence["root_chain"],
             do: Map.put(event, "root_chain", evidence["root_chain"]),
             else: event
           ),
         true <- fits?(event, @event_bytes),
         true <-
           is_nil(evidence["root_chain"]) or
             fits?(
               %{
                 "type" => "managed_preflight_result",
                 "version" => 1,
                 "intent_id" => String.duplicate("0", 32),
                 "projection" => event,
                 "verdicts" => nil
               },
               65_536
             ) do
      {:ok, event, messages, next}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def project_root_history(_, _, _), do: @error

  @doc false
  # Structural historical metadata checks shared by model and Worker purposes.
  # Their owners must also authenticate the complete causal write and live root.
  def root_history_evidence?(old, evidence) do
    with true <- is_list(old) and old != [] and is_map(evidence),
         true <-
           Enum.sort(Map.keys(evidence)) ==
             Enum.sort(
               ~w(fresh_dependency fresh_observation inspection operation_id own_action_sha256 receipt_sha256) ++
                 if(evidence["management"], do: ["management"], else: []) ++
                 if(evidence["root_chain"], do: ["root_chain"], else: [])
             ),
         {:ok, ^old} <- union([old]),
         guard = evidence["fresh_dependency"],
         true <- dependency?(guard) and guard["version"] === 3,
         [first | _] = metadata <- Enum.filter(old, &prior_root_metadata?(&1, guard)),
         true <- Enum.all?(old, &(&1["version"] in [3, 4, 5, 6])),
         prior = first["collection"],
         identity = Map.take(first, ~w(project_id namespace pin_sha256 policy_generation)),
         true <-
           Enum.all?(metadata, fn dependency ->
             (evidence["management"] != nil or evidence["root_chain"] != nil or
                dependency["collection"] === prior) and
               Map.take(dependency, ~w(project_id namespace pin_sha256 policy_generation)) ===
                 identity
           end),
         true <- Enum.all?(old, &(Map.take(&1, Map.keys(identity)) === identity)),
         true <-
           Map.take(guard, ~w(project_id namespace pin_sha256 policy_generation)) === identity,
         true <-
           (cond do
              evidence["management"] ->
                is_nil(evidence["root_chain"]) and management_root_evidence?(old, evidence)

              evidence["root_chain"] ->
                root_chain_evidence?(old, evidence)

              true ->
                guard["collection"]["generation"] === prior["generation"] + 1
            end),
         true <-
           JSON.sha256?(evidence["own_action_sha256"]) and
             JSON.sha256?(evidence["receipt_sha256"]) and id?(evidence["operation_id"]),
         true <- is_map(evidence["fresh_observation"]),
         do: true,
         else: (_ -> false)
  rescue
    _ -> false
  end

  # Structural checks only. ManagedLineage independently rebuilds every edge
  # from authenticated cached actions and compares the complete replay event.
  defp root_chain_evidence?(old, evidence) do
    guard = evidence["fresh_dependency"]
    chain = evidence["root_chain"]
    metadata = Enum.filter(old, &(&1["version"] === 3))
    known = Map.new([guard | metadata], &{digest(&1), &1})

    with true <- is_nil(evidence["management"]),
         true <- is_list(chain) and length(chain) in 2..2048,
         true <- fits?(chain, 65_536),
         true <- length(Enum.uniq_by(chain, & &1["operation_id"])) === length(chain),
         prior = Enum.min_by(metadata, & &1["collection"]["generation"]),
         {:ok, final, roots} <-
           Enum.reduce_while(chain, {:ok, prior["collection"], []}, fn edge,
                                                                       {:ok, expected, roots} ->
             with true <-
                    is_map(edge) and
                      keys?(
                        edge,
                        ~w(operation_id own_action_sha256 receipt_sha256 from_dependency_sha256 to_dependency_sha256)
                      ),
                  true <- id?(edge["operation_id"]),
                  true <-
                    Enum.all?(
                      ~w(own_action_sha256 receipt_sha256 from_dependency_sha256 to_dependency_sha256),
                      &JSON.sha256?(edge[&1])
                    ),
                  from when is_map(from) <- known[edge["from_dependency_sha256"]],
                  to when is_map(to) <- known[edge["to_dependency_sha256"]],
                  true <- from["version"] === 3 and to["version"] === 3,
                  true <- from["collection"] === expected,
                  true <- to["collection"]["generation"] === expected["generation"] + 1,
                  true <- to["collection"]["floor"] === to["collection"]["generation"],
                  true <- to["collection"]["floor_anchor"] === edge["operation_id"] do
               {:cont, {:ok, to["collection"], [expected | roots]}}
             else
               _ -> {:halt, @error}
             end
           end),
         true <- final === guard["collection"],
         true <- Enum.all?(metadata, &(&1["collection"] in [final | roots])),
         last = List.last(chain),
         true <- last["to_dependency_sha256"] === digest(guard),
         true <- last["operation_id"] === evidence["operation_id"],
         true <- last["own_action_sha256"] === evidence["own_action_sha256"],
         true <- last["receipt_sha256"] === evidence["receipt_sha256"],
         do: true,
         else: (_ -> false)
  rescue
    _ -> false
  end

  defp current_root_metadata?(dependency, guard),
    do: dependency["version"] === 3 and dependency["collection"] === guard["collection"]

  defp prior_root_metadata?(dependency, guard),
    do: dependency["version"] === 3 and not current_root_metadata?(dependency, guard)

  defp management_root_evidence?(old, evidence) do
    management = evidence["management"]
    guard = evidence["fresh_dependency"]
    capture = evidence["inspection"]["operation"]

    with true <-
           is_map(management) and
             Enum.sort(Map.keys(management)) == ~w(event handoff intent result),
         %{"handoff" => handoff, "event" => accepted, "intent" => intent, "result" => result} <-
           management,
         true <- Ipse.Session.ChatReviewHandoff.matches_facts?(handoff, accepted["facts"]),
         {:ok, ^result} <-
           Ipse.Session.PendingAcceptance.committed_result(
             accepted,
             intent,
             result["normalized_request"],
             result["receipt"]
           ),
         true <- result["status"] === "committed",
         true <- capture["generation"] === result["normalized_request"]["expected_generation"],
         receipt = result["receipt"],
         true <- guard["collection"]["generation"] === capture["generation"] + 1,
         true <-
           guard["collection"]["generation"] === receipt["generation"] and
             guard["collection"]["floor"] === receipt["floor"] and
             guard["collection"]["floor_anchor"] === intent["operation_id"],
         true <- JSON.digest([handoff["event"]["pin"]]) === guard["pin_sha256"],
         true <-
           Enum.all?(old, fn dependency ->
             if dependency["version"] === 3 do
               root = dependency["collection"]

               root === guard["collection"] or root["generation"] === capture["generation"] - 1 or
                 (root["generation"] === capture["generation"] and
                    root["floor"] === capture["floor"] and
                    root["floor_anchor"] === evidence["operation_id"])
             else
               true
             end
           end),
         do: true,
         else: (_ -> false)
  rescue
    _ -> false
  end

  defp root_history_notice(old, current, nil) do
    %{
      "role" => "user",
      "ipse_root_history" => %{
        "version" => 1,
        "old_generation" => old,
        "new_generation" => current
      },
      "content" =>
        "Host historical metadata notice: Earlier collection root and absence observations describe generation #{old}, before this session's confirmed publication at generation #{current}. They are historical and do not establish current record eligibility. This notice is context, not an operator request or permission."
    }
  end

  defp root_history_notice(old, current, management) do
    %{
      "role" => "user",
      "ipse_root_history" => %{
        "version" => 2,
        "old_generation" => old,
        "new_generation" => current,
        "management_operation_id" => management["intent"]["operation_id"]
      },
      "content" =>
        "Host historical metadata notice: Earlier collection root and absence observations describe generation #{old}, before this conversation's capture and separate confirmed decision acceptance at generation #{current}. They are historical and do not establish current record eligibility. Original conversation and source provenance remain intact. This notice is context, not an operator request or permission."
    }
  end

  @doc "Refresh an opaque helper's complete union only when every dependency remains eligible."
  def refresh(dependencies, values, binding) do
    with {:ok, ^dependencies} <- union([dependencies]),
         true <- binding?(binding, binding["session_id"]),
         dictionary = Map.new(dependencies, &{digest(&1), &1}),
         {:ok, checked} <- verdicts(dictionary, values, binding),
         true <- Enum.all?(checked, fn {_, value} -> value["status"] == "eligible" end),
         {:ok, current} <- union([Enum.map(checked, fn {_, value} -> value["current"] end)]) do
      {:ok, current}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Pure historical verification. The independently admitted dispatch binding is mandatory."
  def replay(state, messages, event, expected_binding, historical_writes \\ %{})

  def replay(%State{} = state, messages, event, expected_binding, historical_writes) do
    with true <- is_map(event) and event["binding"] === expected_binding,
         {:ok, plan} <- plan(state, messages),
         {:ok, expected, projected, next} <-
           project(plan, event["verdicts"], expected_binding, historical_writes),
         true <- expected != nil and expected === event do
      {:ok, %{state: next, messages: projected, live_pending: true}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def replay(_, _, _, _, _), do: @error

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

  defp withdraw(plan, verdicts, historical_writes) do
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

          if safely_projectable?(original, item.producer, plan.state.session_id) do
            reason = invalid |> Enum.sort() |> hd() |> then(&verdicts[&1]["status"])

            text =
              "[Managed historical content withdrawn: #{reason}. Occurrence #{id}. Original transcript retained.]"

            historical =
              historical_writes[get_in(original, ["ipse_extension_result", "invocation_id"])]

            text =
              if is_list(historical) and historical != [],
                do:
                  text <>
                    "\nHost-recorded historical write outcomes (current eligibility was not established): " <>
                    Jason.encode!(historical),
                else: text

            projected =
              if Ipse.Session.Reference.reference?(original) do
                {:ok, retracted} = Ipse.Session.Reference.withdrawn_message(original, text)
                retracted
              else
                original
                |> Map.put("content", text)
                |> Map.delete("ipse_extension_result")
                |> Map.delete("provider_data")
              end

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

  defp safely_projectable?(message, producer, session_id) do
    producer["kind"] != "checkpoint" and not Map.has_key?(message, "ipse_checkpoint") and
      (not Map.has_key?(message, "ipse_reference") or
         (producer["kind"] == "reference" and Ipse.Session.Reference.reference?(message) and
            get_in(message, ["ipse_reference", "session_id"]) == session_id and
            match?(
              {:ok, _},
              Ipse.Session.Reference.selected_publishers(%{"content" => message["content"]})
            ))) and
      (not Map.has_key?(message, "provider_data") or
         (producer["kind"] == "assistant.ollama_text" and
            Ipse.Session.DraftNative.plain_text_only?(message))) and
      message["tool_calls"] in [nil, []] and
      not Map.has_key?(message, "ipse_result_excerpt") and
      safe_markers?(message) and safe_extension_marker?(message) and
      Enum.all?(
        Map.keys(message),
        &(&1 in ~w(role content tool_call_id tool_calls provider_data ipse_reference ipse_tool_outcome ipse_result_excerpt ipse_extension_result))
      )
  end

  defp safe_markers?(message) do
    not Map.has_key?(message, "ipse_tool_outcome") or
      (keys?(message["ipse_tool_outcome"], ~w(status approval)) and
         message["ipse_tool_outcome"]["status"] in ~w(ok failed denied unknown cancelled result_recorded error not_started invalid_arguments) and
         message["ipse_tool_outcome"]["approval"] in ~w(approved session_allow not_required saved_consent denied historical_unknown))
  end

  defp safe_extension_marker?(message) do
    case Map.fetch(message, "ipse_extension_result") do
      :error ->
        true

      {:ok, marker} ->
        keys?(marker, ~w(invocation_id artifact_sha256 result_sha256)) and
          id?(marker["invocation_id"]) and JSON.sha256?(marker["artifact_sha256"]) and
          JSON.sha256?(marker["result_sha256"])
    end
  end

  defp occurrence_fits?(%{"kind" => kind}, deps) when kind in ~w(assistant checkpoint),
    do: length(deps) <= @dependencies and fits?(deps, @bytes)

  defp occurrence_fits?(_, deps),
    do: length(deps) <= @occurrence_dependencies and fits?(deps, @occurrence_bytes)

  defp producer_message?(%{"kind" => kind}, %{"role" => role}) do
    case kind do
      "reference" ->
        role == "user"

      "collection.result" ->
        role == "tool"

      derived when derived in ~w(assistant assistant.ollama_text checkpoint) ->
        role == "assistant"
    end
  end

  defp verdicts(dependencies, values, binding) do
    with true <- is_list(values) and length(values) == map_size(dependencies),
         true <-
           Enum.all?(values, fn value ->
             keys?(value, @verdict_keys) and
               Map.has_key?(dependencies, value["dependency_sha256"]) and
               value["status"] in @reasons and
               verdict_current?(
                 dependencies[value["dependency_sha256"]],
                 value,
                 binding["checked_at_ms"]
               )
           end),
         by_id = Map.new(values, &{&1["dependency_sha256"], &1}),
         true <- map_size(by_id) == map_size(dependencies) do
      {:ok, by_id}
    else
      _ -> @error
    end
  end

  defp verdict_current?(old, %{"status" => "eligible", "current" => current}, now) do
    dependency?(current) and
      Map.take(old, ~w(version project_id namespace pin_sha256 policy_generation)) ===
        Map.take(current, ~w(version project_id namespace pin_sha256 policy_generation)) and
      same_subject?(old, current, now) and compatible_root?(old, current)
  end

  defp verdict_current?(_, %{"current" => nil}, _), do: true
  defp verdict_current?(_, _, _), do: false

  defp compatible_root?(%{"version" => version} = old, current) when version in [4, 5, 6, 7] do
    previous = old["collection"]
    next = current["collection"]

    next["generation"] >= previous["generation"] and next["floor"] >= previous["floor"] and
      (next["floor"] > previous["floor"] or next["floor_anchor"] === previous["floor_anchor"]) and
      (next["generation"] > previous["generation"] or next === previous)
  end

  defp compatible_root?(old, current), do: old["collection"] === current["collection"]

  defp same_subject?(%{"version" => 7, "subject" => old}, %{"subject" => current}, now) do
    Map.take(
      old,
      ~w(kind key request_sha256 result_sha256 publication_policy_sha256 record assessment_sha256)
    ) ===
      Map.take(
        current,
        ~w(kind key request_sha256 result_sha256 publication_policy_sha256 record assessment_sha256)
      ) and
      old["validity"]["status"] === "never_current" and
      current["validity"]["status"] === "never_current" and
      same_validity?(
        Map.put(old["validity"], "status", "eligible"),
        Map.put(current["validity"], "status", "eligible"),
        now
      )
  end

  defp same_subject?(%{"version" => 6, "subject" => old}, %{"subject" => current}, now) do
    Map.take(
      old,
      ~w(kind key request_sha256 result_sha256 publication_policy_sha256 record acceptance)
    ) ===
      Map.take(
        current,
        ~w(kind key request_sha256 result_sha256 publication_policy_sha256 record acceptance)
      ) and
      same_validity?(old["validity"], current["validity"], now)
  end

  defp same_subject?(%{"version" => 5, "subject" => old}, %{"subject" => current}, now) do
    Map.take(
      old,
      ~w(kind key request_sha256 result_sha256 publication_policy_sha256 record successor superseded_at_ms)
    ) ===
      Map.take(
        current,
        ~w(kind key request_sha256 result_sha256 publication_policy_sha256 record successor superseded_at_ms)
      ) and
      same_validity?(old["validity"], current["validity"], now)
  end

  defp same_subject?(%{"version" => 4, "subject" => old}, %{"subject" => current}, now) do
    Map.take(old, ~w(kind key request_sha256 result_sha256 publication_policy_sha256 record)) ===
      Map.take(
        current,
        ~w(kind key request_sha256 result_sha256 publication_policy_sha256 record)
      ) and
      case {old["validity"], current["validity"]} do
        {nil, nil} -> true
        {a, b} when is_map(a) and is_map(b) -> same_validity?(a, b, now)
        _ -> false
      end
  end

  defp same_subject?(%{"version" => 3} = old, current, _),
    do: old["subject"] === current["subject"] and old["collection"] === current["collection"]

  # Version 1 has no selector for a nil record: it can represent a whole-root
  # result rather than a particular absent key. Its content cannot be rebound
  # to a different root by comparing nil record identities.
  defp same_subject?(%{"version" => 1, "record" => nil} = old, current, now),
    do:
      is_nil(current["record"]) and old["collection"] === current["collection"] and
        same_validity?(old["validity"], current["validity"], now)

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
      Map.take(old, ~w(recipe_sha256 lineage source_versions dependencies)) ===
        Map.take(current, ~w(recipe_sha256 lineage source_versions dependencies)) and
        old["status"] == "eligible" and
        current["status"] == "eligible" and
        expiry_not_extended?(old["valid_until_ms"], current["valid_until_ms"]) and
        (is_nil(current["valid_until_ms"]) or current["valid_until_ms"] > now)

  defp expiry_not_extended?(nil, _), do: true

  defp expiry_not_extended?(old, current) when is_integer(old) and is_integer(current),
    do: current <= old

  defp expiry_not_extended?(_, _), do: false

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

  defp record_observation?(%{"record" => nil, "validity" => nil} = subject, _),
    do:
      is_nil(subject["publication_policy_sha256"]) and
        subject["result_sha256"] == digest(%{"record" => nil})

  defp record_observation?(%{"record" => record, "validity" => validity} = subject, "present"),
    do: record?(record) and record["key"] == subject["key"] and validity?(validity)

  defp record_observation?(_, _), do: false

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
  defp history_key?("note." <> lineage), do: JSON.sha256?(lineage)
  defp history_key?(_), do: false
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
