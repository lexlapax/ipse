defmodule Ipse.Extension.CollectionCall do
  @moduledoc "Bounded collection worker requests; protected host admission supplies all authority."
  alias Ipse.{JSON, Extension}
  alias Ipse.Extension.{Collection, SemanticAdmission, SemanticConsent}
  @reads ~w(status snapshot get inspect scan)
  @binding ~w(kind version namespace pin inner_op request_sha256)
  @summary ~w(version project generation floor floor_anchor)
  @failures ~w(collection_unavailable collection_consent_denied collection_source_refused collection_policy_refused collection_result_limit collection_capacity collection_filesystem_unsupported collection_writer_fenced collection_duplicate)
  @error {:error, :invalid_extension_collection_call}

  def operation?(request), do: is_map(request) and request["op"] == "collection.call"

  def mutating?(request),
    do: operation?(request) and get_in(request, ["request", "op"]) == "commit"

  def capability(request),
    do: if(mutating?(request), do: "host.collection.write", else: "host.collection.read")

  def validate(request) do
    with true <- keys?(Map.delete(request, "proofs"), ~w(op request)) and operation?(request),
         inner when is_map(inner) <- request["request"],
         true <- Collection.valid_request?(inner),
         true <- inner["op"] in (@reads ++ ["commit"]),
         true <- inner["op"] != "scan" or inner["limit"] in 1..4,
         true <- inner["op"] != "commit" or length(inner["changes"]) <= 8,
         true <- inner["op"] != "commit" or floor_required?(inner),
         true <- proof_requests?(request),
         :ok <- Extension.validate(request),
         true <- byte_size(Jason.encode!(request)) <= 8192 do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp floor_required?(inner) do
    inner["advance_floor"] or
      Enum.all?(inner["changes"], &(&1["expected_revision"] == 0 and not is_nil(&1["value"])))
  end

  defp proof_requests?(%{"proofs" => proofs} = request) do
    mutating?(request) and is_list(proofs) and length(proofs) in 1..8 and
      length(Enum.uniq(proofs)) == length(proofs) and
      Enum.all?(proofs, fn proof ->
        keys?(proof, ~w(handle quote)) and
          Ipse.Extension.SourceRead.validate(Map.put(proof, "op", "source.quote")) == :ok
      end)
  end

  defp proof_requests?(request), do: not mutating?(request)

  def binding(config, identity, request) do
    descriptor = config[:semantic_admission]

    with :ok <- validate(request),
         true <- SemanticAdmission.valid?(descriptor, nil),
         %{"pin" => pin, "instance" => instance} when is_map(pin) <- descriptor,
         true <-
           instance == identity["instance"] and pin["identity_sha256"] == JSON.digest([identity]) do
      {:ok,
       %{
         "kind" => "collection",
         "version" => 1,
         "namespace" => pin["namespace"],
         "pin" => pin,
         "inner_op" => request["request"]["op"],
         "request_sha256" => JSON.digest([request["request"]])
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def valid_binding?(binding, request, identity, metadata \\ nil) do
    with :ok <- validate(request),
         true <- keys?(binding, @binding),
         true <- binding["kind"] == "collection" and binding["version"] === 1,
         pin when is_map(pin) <- binding["pin"],
         true <- SemanticConsent.pin?(pin),
         true <- binding["namespace"] == pin["namespace"],
         true <- pin["identity_sha256"] == JSON.digest([identity]),
         true <- binding["inner_op"] == request["request"]["op"],
         true <- binding["request_sha256"] == JSON.digest([request["request"]]) do
      is_nil(metadata) or
        (SemanticAdmission.valid?(metadata["semantic_admission"], pin["session_id"]) and
           metadata["semantic_admission"]["pin"] === pin and
           metadata["semantic_admission"]["instance"] == identity["instance"])
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc "Run only after Session has durably recorded the exact action intent."
  def execute(context, intent) do
    with :ok <- validate(intent["request"]),
         true <- context.parent["version"] === 3,
         true <-
           SemanticAdmission.valid_outer_binding?(
             context.parent["semantic_binding"],
             context.parent["identity"],
             context.parent["descriptor"],
             context.session_id
           ),
         true <- valid_binding?(intent["effect_binding"], intent["request"], context.identity),
         true <- intent["effect_binding"]["pin"]["session_id"] == context.session_id,
         true <-
           get_in(context.parent, ["semantic_binding", "class"]) != "collection.read" or
             not mutating?(intent["request"]),
         true <- intent["namespace"] == intent["effect_binding"]["namespace"] do
      Ipse.Session.Resources.file_effect(fn -> protected_execute(context, intent) end)
    else
      _ -> failed("collection_consent_denied")
    end
  rescue
    _ -> failed("collection_unavailable")
  catch
    :exit, _ -> :unknown
  end

  defp protected_execute(context, intent) do
    admission = context.config[:semantic_admission]

    Ipse.Extension.ProjectIdentity.with_binding(
      context.config[:home],
      context.cwd,
      admission["binding"],
      fn _ ->
        with {:ok, current, proofs} <- current_sources(context, intent),
             {:ok, plan} <- plan(context, intent, current, proofs) do
          if mutating?(intent["request"]),
            do: publish(context, intent, current, proofs, plan),
            else: read(context, intent, current, plan)
        else
          _ -> failed("collection_consent_denied")
        end
      end
    )
    |> normalize()
  end

  defp current_sources(context, intent),
    do:
      GenServer.call(
        context.owner,
        {:extension_collection_sources, context.job_ref, intent},
        5000
      )

  defp plan(context, intent, current, proofs) do
    pin = intent["effect_binding"]["pin"]
    root = SemanticAdmission.control_root(context.config[:home])

    Ipse.Extension.Consent.with_policy(
      root,
      pin["project_id"],
      pin["epoch"],
      pin["policy_sha256"],
      now(),
      fn snapshot ->
        class = if mutating?(intent["request"]), do: "collection.publish", else: "collection.read"

        matches =
          Enum.filter(snapshot["policy"]["settings"]["effects"], fn mapping ->
            mapping["class"] == class and mapping["inner_op"] == "collection.call" and
              mapping["outer_sha256"] == JSON.digest([context.parent["descriptor"]]) and
              (class == "collection.read" or
                 Ipse.Extension.CollectionPolicy.check(
                   intent["request"]["request"],
                   mapping["constraints"],
                   Enum.map(proofs, & &1["proof"])
                 ) == :ok)
          end)

        case matches do
          [mapping] ->
            effect =
              Map.take(mapping, ~w(operation class outer_sha256 inner_op))
              |> Map.merge(%{
                "id" => intent["operation_id"],
                "request_sha256" => intent["request_sha256"],
                "source_generation" => current["source_generation"],
                "sources" =>
                  Enum.map(proofs, &Map.take(&1["proof"], ~w(path)))
                  |> Enum.zip(Enum.map(proofs, & &1["proof"]["origin"]))
                  |> Enum.map(fn {row, category} -> Map.put(row, "category", category) end),
                "reserved" => reserved(intent)
              })

            if class == "collection.publish" do
              with true <- intent["approval"] in ~w(saved_consent approved session_allow),
                   :ok <-
                     Ipse.Extension.CollectionPolicy.check(
                       intent["request"]["request"],
                       mapping["constraints"],
                       Enum.map(proofs, & &1["proof"])
                     ),
                   {:ok, reservation} <-
                     SemanticConsent.authorize(pin, snapshot, current, effect, now()) do
                {:ok, %{reservation: reservation, constraints: mapping["constraints"]}}
              else
                _ -> {:error, :collection_policy_refused}
              end
            else
              with :ok <- SemanticConsent.check(pin, snapshot, current, effect, now()),
                   do: {:ok, %{}}
            end

          _ ->
            {:error, :collection_consent_denied}
        end
      end
    )
  end

  defp read(context, intent, current, _) do
    pin = intent["effect_binding"]["pin"]

    Ipse.Extension.Consent.with_policy(
      SemanticAdmission.control_root(context.config[:home]),
      pin["project_id"],
      pin["epoch"],
      pin["policy_sha256"],
      now(),
      fn _ ->
        with {:ok, ^current, []} <- current_sources(context, intent),
             do: storage(context, intent)
      end
    )
  end

  defp publish(context, intent, current, proofs, plan) do
    alias Ipse.Extension.Consent
    pin = intent["effect_binding"]["pin"]
    root = SemanticAdmission.control_root(context.config[:home])
    project = pin["project_id"]

    with {:ok, ticket} <- Consent.reserve(root, project, plan.reservation, now()),
         false <- Map.has_key?(ticket, "existing"),
         {:ok, ^ticket} <- Consent.admit(root, project, ticket, now()) do
      case Consent.publish(root, project, ticket, now(), fn ->
             with {:ok, ^current, ^proofs} <- current_sources(context, intent),
                  :ok <-
                    Ipse.Extension.CollectionPolicy.check(
                      intent["request"]["request"],
                      plan.constraints,
                      Enum.map(proofs, & &1["proof"])
                    ) do
               case storage(context, intent) do
                 {status, value} when status in [:ok, :conflict, :failed] ->
                   {:ok, reserved(intent),
                    %{"status" => Atom.to_string(status), "value" => value}}

                 _ ->
                   :unknown
               end
             else
               _ ->
                 {:ok, reserved(intent),
                  %{"status" => "failed", "value" => %{"code" => "collection_source_refused"}}}
             end
           end) do
        {:ok, %{"status" => "settled", "receipt" => %{"status" => status, "value" => value}}}
        when status in ~w(ok conflict failed) ->
          {String.to_existing_atom(status), value}

        {:error, _} ->
          failed("collection_consent_denied")

        _ ->
          :unknown
      end
    else
      _ -> failed("collection_consent_denied")
    end
  end

  defp reserved(intent) do
    if mutating?(intent["request"]),
      do:
        Map.merge(Ipse.Extension.Consent.zero(), %{
          "operations" => 1,
          "input_bytes" => byte_size(Jason.encode!(intent["request"])),
          "output_bytes" => 16_384
        }),
      else: Ipse.Extension.Consent.zero()
  end

  defp storage(context, intent) do
    case Collection.execute(
           SemanticAdmission.collection_root(context.config[:home]),
           intent["namespace"],
           intent["request"]["request"],
           intent["operation_id"]
         ) do
      {:ok, value} ->
        if intent["request"]["request"]["op"] == "scan",
          do: bound_scan(intent, value),
          else:
            if(reply_fits?(intent, value),
              do: {:ok, value},
              else: failed("collection_result_limit")
            )

      {:conflict, value} ->
        {:conflict, value}

      {:existing, _} ->
        failed("collection_duplicate")

      {:error, reason}
      when reason in [
             :collection_capacity,
             :collection_filesystem_unsupported,
             :collection_writer_fenced
           ] ->
        failed(Atom.to_string(reason))

      {:error, _} ->
        failed("collection_unavailable")

      _ ->
        :unknown
    end
  end

  defp failed(code), do: {:failed, %{"code" => code}}
  defp normalize({status, _} = result) when status in [:ok, :conflict, :failed], do: result
  defp normalize({:error, _}), do: failed("collection_consent_denied")
  defp normalize(_), do: :unknown
  defp now, do: System.system_time(:millisecond)

  @doc "Keep complete records and make byte refusal visible through the actual continuation."
  def bound_scan(intent, %{"records" => records} = value) do
    Enum.reduce_while(records, [], fn record, selected ->
      candidate = scan_prefix(value, records, selected ++ [record])

      if reply_fits?(intent, candidate),
        do: {:cont, selected ++ [record]},
        else: {:halt, selected}
    end)
    |> then(fn selected ->
      candidate = scan_prefix(value, records, selected)

      if (selected != [] or records == []) and reply_fits?(intent, candidate),
        do: {:ok, candidate},
        else: {:failed, %{"code" => "collection_result_limit"}}
    end)
  end

  defp scan_prefix(value, records, selected) do
    next = if length(selected) < length(records), do: List.last(selected), else: nil

    value
    |> Map.put("records", selected)
    |> then(fn value -> if next, do: Map.put(value, "next", next["key"]), else: value end)
  end

  def reply_fits?(intent, value) do
    payload =
      Ipse.Extension.Actions.resume(
        Map.put(intent, "outcome", %{"status" => "ok", "value" => value})
      )

    Extension.validate(payload) == :ok and byte_size(Jason.encode!(payload)) <= 16_384
  rescue
    _ -> false
  end

  def valid_outcome?(request, status, value, _) when status in ~w(unknown denied),
    do: validate(request) == :ok and value == %{}

  def valid_outcome?(request, "failed", value, _),
    do: validate(request) == :ok and keys?(value, ["code"]) and value["code"] in @failures

  def valid_outcome?(request, status, value, _) when status in ~w(ok conflict) do
    validate(request) == :ok and Extension.validate(value) == :ok and
      if status == "conflict" do
        keys?(value, @summary) and summary?(value)
      else
        result?(request["request"], value)
      end
  rescue
    _ -> false
  end

  def valid_outcome?(_, _, _, _), do: false

  def bound_outcome?(event) do
    case event["outcome"] do
      %{"status" => "ok", "value" => value} ->
        request = event["request"]["request"]

        if request["op"] == "commit" do
          value["request_sha256"] == event["effect_binding"]["request_sha256"] and
            value["generation"] == request["expected_generation"] + 1
        else
          value["project"] == event["namespace"]
        end

      %{"status" => "conflict", "value" => value} ->
        value["project"] == event["namespace"]

      _ ->
        true
    end
  rescue
    _ -> false
  end

  defp result?(%{"op" => "commit"}, value),
    do: keys?(value, ~w(generation floor request_sha256)) and Collection.Migration.receipt?(value)

  defp result?(%{"op" => "snapshot"}, value), do: keys?(value, @summary) and summary?(value)

  defp result?(%{"op" => "get", "key" => key}, value),
    do:
      keys?(value, @summary ++ ["record"]) and summary?(value) and
        (is_nil(value["record"]) or
           (record?(value["record"], value["generation"]) and value["record"]["key"] == key))

  defp result?(%{"op" => "inspect"}, value),
    do:
      keys?(value, @summary ++ ["operation"]) and summary?(value) and
        (is_nil(value["operation"]) or Collection.Migration.receipt?(value["operation"]))

  defp result?(%{"op" => "scan"} = request, value) do
    keys?(value, @summary ++ ~w(records next)) and summary?(value) and
      value["generation"] == request["generation"] and is_list(value["records"]) and
      length(value["records"]) <= request["limit"] and
      Enum.all?(value["records"], &record?(&1, value["generation"])) and
      ordered?(value["records"], request["after"]) and
      (is_nil(value["next"]) or
         (value["records"] != [] and value["next"] == List.last(value["records"])["key"]))
  end

  defp result?(%{"op" => "status"}, value) do
    counts =
      ~w(records staged_records staged_data_bytes checkpoint_records checkpoint_data_bytes operations reserved_operation_slots data_bytes envelope_data_bytes disk_bytes accounted_total_bytes allocated_bytes accounted_allocated_bytes)

    keys?(value, @summary ++ counts ++ ~w(migration checkpoint notice limits)) and summary?(value) and
      Enum.all?(counts, &JSON.safe_uint?(value[&1])) and
      value["notice"] in [nil, "capacity_80_percent"] and value["limits"] == Collection.limits() and
      Enum.all?(~w(migration checkpoint), &(is_nil(value[&1]) or is_map(value[&1])))
  end

  defp result?(_, _), do: false

  defp summary?(value),
    do:
      value["version"] === 3 and JSON.sha256?(value["project"]) and
        JSON.safe_uint?(value["generation"]) and JSON.safe_uint?(value["floor"]) and
        if(value["floor"] == 0,
          do: is_nil(value["floor_anchor"]),
          else: id?(value["floor_anchor"])
        )

  defp record?(record, generation) do
    keys?(record, ~w(key revision sha256 bytes operation_id value)) and key?(record["key"]) and
      JSON.safe_uint?(record["revision"]) and record["revision"] > 0 and
      record["revision"] <= generation and
      id?(record["operation_id"]) and is_map(record["value"]) and
      byte_size(Collection.Migration.encode(record["value"])) == record["bytes"] and
      record["bytes"] in 2..6144 and
      JSON.sha256(Collection.Migration.encode(record["value"])) == record["sha256"]
  end

  defp ordered?(records, after_key) do
    keys = Enum.map(records, & &1["key"])
    keys == Enum.sort(Enum.uniq(keys)) and Enum.all?(keys, &(is_nil(after_key) or &1 > after_key))
  end

  defp key?(key),
    do: is_binary(key) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,95}\z/, key)

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
end
