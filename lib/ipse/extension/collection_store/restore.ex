defmodule Ipse.Extension.CollectionStore.Restore do
  @moduledoc false
  alias Ipse.JSON
  alias Ipse.Extension.{CollectionStore, ResultSource}
  alias Ipse.Extension.Collection.{DocumentMigration, DocumentStage}
  alias Ipse.Extension.{ProjectIdentity, Registry, ResultDocument}
  alias Ipse.Session.{ManagedToolUse, Resources, StoredSources}
  @error {:error, :document_store_refused}
  @reads ~w(backup.describe backup.metadata restore.input.read)
  @reduced ~w(restore.abort restore.checkpoint_drop)
  @empty_union JSON.digest([[]])
  @chunk_bytes 6144
  @observed_key {__MODULE__, :native_outcome}

  def operation?(request) do
    is_map(request) and request["op"] === "collection.store" and
      is_map(request["request"]) and
      request["request"]["op"] in (@reads ++
                                     ~w(restore.open restore.page restore.commit restore.abort restore.rollback restore.checkpoint_drop))
  end

  def mutating?(request), do: operation?(request) and request["request"]["op"] not in @reads

  def selected?(reference) do
    exact?(reference, ~w(version session_id delivery)) and reference["version"] === 1 and
      is_binary(reference["session_id"]) and
      Regex.match?(~r/\A[0-9a-f]{32}\z/, reference["session_id"]) and
      ResultSource.valid_descriptor?(reference["delivery"])
  rescue
    _ -> false
  end

  def policy?(policy),
    do:
      exact?(policy, ~w(command_id action export_action plan_action)) and
        Enum.all?(Map.values(policy), fn value ->
          is_binary(value) and Regex.match?(~r/\A[a-z][a-z0-9_.-]{0,63}\z/, value)
        end)

  def validate(request) do
    inner = request["request"]
    keys = ~w(op scope request) ++ reference_fields(request)

    with true <- operation?(request) and exact?(request, keys),
         true <- request["scope"] === "project",
         true <- Enum.all?(reference_fields(request), &selected?(request[&1])),
         true <- Ipse.Extension.validate(request) === :ok,
         true <-
           if(inner["op"] === "restore.input.read",
             do: exact?(inner, ~w(op offset)) and JSON.safe_uint?(inner["offset"]),
             else: DocumentMigration.request?(inner)
           ),
         true <- not mutating?(request) or inner["dependency_union_sha256"] === @empty_union,
         true <-
           inner["op"] in (@reads ++ @reduced) or
             inner["plan_binding_sha256"] === JSON.digest([plan_reference(request)]) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  # Historical data selection is captured in an actual operator command. A
  # worker cannot manufacture that selection in a later host-call argument.
  def allowed?(request, parent) do
    not operation?(request) or
      (get_in(parent, ["descriptor", "stage"]) === "invoke.command" and
         if(request["request"]["op"] === "restore.input.read",
           do: selected_read?(request, get_in(parent, ["payload", "arguments"])),
           else:
             Enum.all?(reference_fields(request), fn key ->
               get_in(parent, ["payload", "arguments", key]) === request[key]
             end)
         ))
  rescue
    _ -> false
  end

  def input_fields(%{"op" => "restore.input.read"}), do: ["result_input"]
  def input_fields(%{"op" => "restore.open"}), do: ["result_input"]
  def input_fields(%{"op" => "restore.page"}), do: ~w(result_input plan_input)

  def input_fields(%{"op" => op}) when op in ~w(restore.commit restore.rollback),
    do: ["plan_input"]

  def input_fields(_), do: []

  defp reference_fields(request) do
    input_fields(request["request"]) ++
      if(
        request["request"]["op"] === "restore.input.read" and
          Map.has_key?(request, "plan_input"),
        do: ["plan_input"],
        else: []
      )
  end

  defp selected_read?(request, arguments) when is_map(arguments) do
    if Map.has_key?(request, "plan_input") do
      request["plan_input"] === arguments["plan_input"]
    else
      request["result_input"] === arguments["result_input"] or
        request["result_input"] === arguments["plan_input"] or
        (is_list(arguments["data_inputs"]) and length(arguments["data_inputs"]) <= 8192 and
           request["result_input"] in arguments["data_inputs"])
    end
  end

  defp selected_read?(_, _), do: false

  def plan_reference(%{"request" => %{"op" => "restore.open"}} = request),
    do: request["result_input"]

  def plan_reference(request), do: request["plan_input"]

  def actual_owner(binding, invocation_id) do
    %{
      "project_id" => get_in(binding, ["project", "project_id"]),
      "session_id" => binding["session_id"],
      "identity_sha256" => binding["identity_sha256"],
      "invocation_id" => invocation_id
    }
  end

  def execute(context, intent) do
    binding = intent["effect_binding"]

    with true <- CollectionStore.valid_binding?(binding, intent["request"], context.identity),
         true <- binding["session_id"] === context.session_id,
         true <- intent["parent_invocation_id"] === context.parent["invocation_id"],
         true <- allowed?(intent["request"], context.parent),
         true <- Registry.live?(context.identity),
         :ok <- current(context, intent) do
      Resources.file_effect(fn ->
        if Process.get(@observed_key) do
          @error
        else
          Process.put(@observed_key, :none)

          try do
            result =
              ManagedToolUse.with_effect(
                context.managed_tool,
                ManagedToolUse.document_binding(intent),
                fn deadline ->
                  # Protected document mutations remain unsupported. Historical
                  # result provenance is never a new current-use permission.
                  if is_nil(deadline), do: execute_owned(context, intent, binding), else: @error
                end
              )

            settle_observed_result(result, Process.get(@observed_key))
          after
            Process.delete(@observed_key)
          end
        end
      end)
      |> normalize(intent)
    else
      _ -> {:failed, %{"code" => "document_store_refused"}}
    end
  rescue
    _ -> :unknown
  catch
    :exit, _ -> :unknown
  end

  defp execute_owned(context, intent, binding) do
    request = intent["request"]
    inner = request["request"]
    owner = actual_owner(binding, intent["parent_invocation_id"])

    cond do
      inner["op"] === "restore.input.read" ->
        with_selected_read(context, request, fn input, guard ->
          offset = inner["offset"]

          with true <- input.dependencies === [],
               true <- offset <= byte_size(input.bytes),
               :ok <- current(context, intent),
               :ok <- guard.() do
            size = min(@chunk_bytes, byte_size(input.bytes) - offset)
            bytes = binary_part(input.bytes, offset, size)

            {:ok,
             %{
               "delivery" => input.delivery,
               "offset" => offset,
               "next" => if(offset + size < byte_size(input.bytes), do: offset + size),
               "data_base64" => Base.encode64(bytes),
               "sha256" => JSON.sha256(bytes),
               "origin" =>
                 case source_origin(input) do
                   {:ok, origin} -> origin
                   _ -> nil
                 end
             }}
          else
            _ -> @error
          end
        end)

      inner["op"] in (@reads ++ @reduced) ->
        ProjectIdentity.with_existing_binding(
          context.config.home,
          context.cwd,
          binding["project"],
          fn _ ->
            native(context, intent, owner, nil, fn -> current(context, intent) end)
          end
        )

      true ->
        plan_ref = plan_reference(request)

        StoredSources.with_result(context, plan_ref, fn plan, plan_guard ->
          with true <- plan.dependencies === [] and plan.project_binding === binding["project"],
               {:ok, origin} <- source_origin(plan),
               true <-
                 origin["command_id"] ===
                   binding["operator_binding"]["input_validation"]["command_id"],
               true <-
                 origin["action"] ===
                   binding["operator_binding"]["input_validation"]["plan_action"],
               true <- plan.value["plan"]["dependency_union_sha256"] === @empty_union,
               true <- JSON.digest([plan_ref]) === inner["plan_binding_sha256"],
               :ok <-
                 validate_pages(context, plan, binding["operator_binding"]["input_validation"]) do
            guard = fn ->
              with :ok <- plan_guard.(), do: current(context, intent)
            end

            if inner["op"] === "restore.page" do
              with true <- request["result_input"] in plan.value["plan"]["data_inputs"] do
                held = Map.put(context, :held_document_project, plan.project_binding)

                StoredSources.with_result(held, request["result_input"], fn page, page_guard ->
                  with :ok <-
                         classified_page(
                           page,
                           binding["operator_binding"]["input_validation"],
                           context.identity
                         ),
                       true <- page.value["descriptor"] === plan.value["descriptor"] do
                    native(context, intent, owner, page.value, fn ->
                      with :ok <- guard.(), do: page_guard.()
                    end)
                  end
                end)
              else
                _ -> @error
              end
            else
              input = if inner["op"] === "restore.open", do: plan.value
              native(context, intent, owner, input, guard)
            end
          else
            _ -> @error
          end
        end)
    end
  end

  defp with_selected_read(context, request, fun) do
    if Map.has_key?(request, "plan_input") do
      StoredSources.with_result(context, request["plan_input"], fn plan, plan_guard ->
        with true <- plan.dependencies === [],
             inputs when is_list(inputs) and length(inputs) <= 8192 <-
               plan.value["plan"]["data_inputs"],
             true <- request["result_input"] in inputs do
          held = Map.put(context, :held_document_project, plan.project_binding)

          StoredSources.with_result(held, request["result_input"], fn input, input_guard ->
            fun.(input, fn -> with :ok <- plan_guard.(), do: input_guard.() end)
          end)
        else
          _ -> @error
        end
      end)
    else
      StoredSources.with_result(context, request["result_input"], fun)
    end
  end

  defp native(context, intent, owner, input, guard) do
    request = intent["request"]
    inner = request["request"]

    opts = [
      publication_guard: guard,
      plan_binding_sha256: inner["plan_binding_sha256"],
      dependency_union_sha256: inner["dependency_union_sha256"]
    ]

    opts =
      if DocumentMigration.input?(inner) do
        [
          with_input: fn accept -> accept.(input) end,
          input_binding_sha256: JSON.digest([request["result_input"]])
        ] ++ opts
      else
        opts
      end

    with :ok <- guard.() do
      if mutating?(request), do: Process.put(@observed_key, :attempting)

      result =
        Ipse.Extension.Collection.document_migration(
          CollectionStore.root(context.config.home),
          intent["effect_binding"]["namespace"],
          inner,
          intent["operation_id"],
          owner,
          opts
        )

      if mutating?(request), do: Process.put(@observed_key, result)
      result
    end
  end

  @doc false
  def settle_observed_result(result, observed) do
    case observed do
      state when state in [:none, nil] -> result
      :attempting -> :unknown
      {:ok, _} -> if result === observed, do: result, else: :unknown
      {:existing, _} -> if result === observed, do: result, else: :unknown
      {:unknown, _} -> :unknown
      :unknown -> :unknown
      _ -> result
    end
  end

  defp current(context, intent),
    do: GenServer.call(context.owner, {:extension_document_current, context.job_ref, intent})

  defp normalize({status, result}, intent) when status in [:ok, :conflict] do
    value = %{
      "version" => 3,
      "owner" => actual_owner(intent["effect_binding"], intent["parent_invocation_id"]),
      "operation_id" => intent["operation_id"],
      "request_sha256" => JSON.digest([intent["request"]]),
      "result" => result
    }

    if valid_outcome?(intent["request"], Atom.to_string(status), value, intent["operation_id"]),
      do: {status, value},
      else: :unknown
  end

  defp normalize({:existing, %{"operation" => receipt}}, intent),
    do: normalize({:ok, receipt}, intent)

  defp normalize({:unknown, _}, _), do: :unknown
  defp normalize(:unknown, _), do: :unknown
  defp normalize(_, _), do: {:failed, %{"code" => "document_store_refused"}}

  defp validate_pages(context, plan, policy) do
    with inputs when is_list(inputs) and length(inputs) <= 8192 <-
           plan.value["plan"]["data_inputs"],
         true <- Enum.all?(inputs, &selected?/1),
         true <- plan.value["plan"]["data_bindings"] === Enum.map(inputs, &JSON.digest([&1])) do
      held = Map.put(context, :held_document_project, plan.project_binding)

      Enum.reduce_while(inputs, :ok, fn selected, :ok ->
        case StoredSources.with_result(held, selected, fn page, guard ->
               with :ok <- classified_page(page, policy, context.identity),
                    true <- page.value["descriptor"] === plan.value["descriptor"],
                    do: guard.()
             end) do
          :ok -> {:cont, :ok}
          _ -> {:halt, @error}
        end
      end)
    else
      _ -> @error
    end
  end

  @doc false
  def classified_page(page, policy, identity) do
    intent = page.source_intent
    original = get_in(intent, ["payload", "arguments", "result_input"])

    with true <- page.dependencies === [] and policy?(policy),
         true <- JSON.sha256?(identity["artifact_sha256"]),
         true <- intent["identity"]["artifact_sha256"] === identity["artifact_sha256"],
         true <- get_in(intent, ["descriptor", "stage"]) === "invoke.command",
         true <- get_in(intent, ["descriptor", "id"]) === policy["command_id"],
         true <- get_in(intent, ["payload", "arguments", "action"]) === policy["action"],
         true <- selected?(original),
         {:ok, bytes, origin} <- validated_input_bytes(page.action_results, original),
         true <- origin?(origin),
         true <- origin["command_id"] === policy["command_id"],
         true <- origin["action"] === policy["export_action"],
         {:ok, value} <- ResultDocument.decode(bytes, %{"type" => "object"}),
         true <- value === page.value and descriptor_origin?(value, origin) do
      :ok
    else
      _ -> @error
    end
  end

  @doc false
  def validated_input_bytes(actions, selected) do
    actions
    |> Enum.filter(fn event ->
      get_in(event, ["request", "request", "op"]) === "restore.input.read" and
        get_in(event, ["request", "result_input"]) === selected and
        get_in(event, ["outcome", "status"]) === "ok"
    end)
    |> Enum.reduce_while({:ok, 0, [], nil}, fn event, {:ok, offset, chunks, origin} ->
      request = event["request"]
      value = get_in(event, ["outcome", "value", "result"])

      if request["request"]["offset"] === offset and read_result?(request, value) and
           (chunks === [] or value["origin"] === origin) do
        bytes = Base.decode64!(value["data_base64"])
        {:cont, {:ok, offset + byte_size(bytes), [bytes | chunks], value["origin"]}}
      else
        {:halt, @error}
      end
    end)
    |> case do
      {:ok, count, chunks, origin} when chunks != [] ->
        bytes = chunks |> Enum.reverse() |> IO.iodata_to_binary()

        if count === selected["delivery"]["byte_count"] and
             JSON.sha256(bytes) === selected["delivery"]["sha256"],
           do: {:ok, bytes, origin},
           else: @error

      _ ->
        @error
    end
  end

  def valid_outcome?(request, status, value, operation_id) do
    validate(request) === :ok and Ipse.Extension.validate(value) === :ok and
      case status do
        state when state in ~w(unknown denied) ->
          value === %{}

        "failed" ->
          value === %{"code" => "document_store_refused"}

        state when state in ~w(ok conflict) ->
          exact?(value, ~w(version owner operation_id request_sha256 result)) and
            value["version"] === 3 and DocumentStage.owner?(value["owner"]) and
            value["operation_id"] === operation_id and
            value["request_sha256"] === JSON.digest([request]) and
            if(request["request"]["op"] === "restore.input.read",
              do: state === "ok" and read_result?(request, value["result"]),
              else:
                DocumentMigration.valid_result?(
                  request["request"],
                  state,
                  value["result"],
                  operation_id,
                  value["owner"]
                )
            )

        _ ->
          false
      end
  rescue
    _ -> false
  end

  def bound_outcome?(event) do
    get_in(event, ["outcome", "status"]) not in ~w(ok conflict) or
      get_in(event, ["outcome", "value", "owner"]) ===
        actual_owner(event["effect_binding"], event["parent_invocation_id"])
  end

  defp read_result?(request, value) do
    delivery = request["result_input"]["delivery"]
    offset = request["request"]["offset"]

    with true <- exact?(value, ~w(delivery offset next data_base64 sha256 origin)),
         true <- is_nil(value["origin"]) or origin?(value["origin"]),
         true <- value["delivery"] === delivery and value["offset"] === offset,
         {:ok, bytes} <- Base.decode64(value["data_base64"]),
         true <- Base.encode64(bytes) === value["data_base64"],
         true <- offset <= delivery["byte_count"],
         size = min(@chunk_bytes, delivery["byte_count"] - offset),
         true <- byte_size(bytes) === size and JSON.sha256(bytes) === value["sha256"],
         true <- value["next"] === if(offset + size < delivery["byte_count"], do: offset + size) do
      true
    else
      _ -> false
    end
  end

  # The caller supplies only an already leased Saved result. The native action
  # records, rather than the worker's JSON, authenticate its snapshot descriptor.
  @doc false
  def source_origin(input) do
    intent = input.source_intent
    descriptor = input.value["descriptor"]

    events =
      Enum.filter(input.action_results, fn event ->
        get_in(event, ["request", "request", "op"]) in ~w(backup.describe backup.metadata) and
          get_in(event, ["outcome", "status"]) === "ok"
      end)

    with true <- get_in(intent, ["descriptor", "stage"]) === "invoke.command",
         true <- DocumentMigration.descriptor?(descriptor),
         true <- events !== [],
         true <-
           Enum.all?(events, fn event ->
             request = event["request"]
             result = get_in(event, ["outcome", "value", "result"])
             owner = actual_owner(event["effect_binding"], event["parent_invocation_id"])

             event["parent_invocation_id"] === intent["invocation_id"] and
               event["effect_binding"]["project"] === input.project_binding and
               request["op"] === "collection.store" and request["scope"] === "project" and
               DocumentMigration.request?(request["request"]) and
               DocumentMigration.valid_result?(
                 request["request"],
                 "ok",
                 result,
                 event["operation_id"],
                 owner
               ) and
               result["descriptor"] === compact(descriptor)
           end) do
      [first | _] = events

      origin = %{
        "version" => 1,
        "artifact_sha256" => intent["identity"]["artifact_sha256"],
        "invocation_id" => intent["invocation_id"],
        "command_id" => intent["descriptor"]["id"],
        "action" => get_in(intent, ["payload", "arguments", "action"]),
        "owner" => actual_owner(first["effect_binding"], intent["invocation_id"]),
        "descriptor" => compact(descriptor),
        "metadata_sha256" => JSON.digest([events])
      }

      if origin?(origin), do: {:ok, origin}, else: @error
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp compact(descriptor),
    do:
      descriptor
      |> Map.delete("floor_lineage")
      |> Map.put("floor_lineage_count", length(descriptor["floor_lineage"]))

  defp descriptor_origin?(value, origin),
    do:
      DocumentMigration.descriptor?(value["descriptor"]) and
        compact(value["descriptor"]) === origin["descriptor"]

  defp origin?(origin) do
    exact?(
      origin,
      ~w(version artifact_sha256 invocation_id command_id action owner descriptor metadata_sha256)
    ) and
      origin["version"] === 1 and JSON.sha256?(origin["artifact_sha256"]) and
      JSON.sha256?(origin["metadata_sha256"]) and DocumentStage.owner?(origin["owner"]) and
      origin["invocation_id"] === origin["owner"]["invocation_id"] and
      Enum.all?([origin["command_id"], origin["action"]], fn id ->
        is_binary(id) and Regex.match?(~r/\A[a-z][a-z0-9_.-]{0,63}\z/, id)
      end) and
      DocumentMigration.valid_result?(
        %{"op" => "backup.describe", "generation" => origin["descriptor"]["generation"]},
        "ok",
        %{"descriptor" => origin["descriptor"]},
        nil,
        origin["owner"]
      )
  rescue
    _ -> false
  end

  defp exact?(map, keys),
    do: is_map(map) and Enum.sort(Map.keys(map)) === Enum.sort(keys)
end
