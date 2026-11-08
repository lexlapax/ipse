defmodule Ipse.Extension.DecisionExperiment do
  @moduledoc false

  alias Ipse.Extension.{
    Artifact,
    Bundles,
    Consent,
    DecisionCall,
    Mode,
    Registry,
    SemanticAdmission
  }

  alias Ipse.Provider.Decision.Transport
  alias Ipse.JSON

  @error {:error, :decision_experiment_refused}

  def numeric_loopback?(target) when is_binary(target),
    do: URI.parse(target).host in ["127.0.0.1", "::1"]

  def numeric_loopback?(_), do: false

  # The marker is read from the admitted artifact's digest-checked sidecar,
  # never from a worker request or a project-controlled option.
  def classify(context) do
    experiment_outer? =
      get_in(context, [:parent, "semantic_binding", "class"]) == "decision.create"

    with identity when is_map(identity) <- context[:identity],
         entries when is_list(entries) <- get_in(context, [:config, :extensions]),
         %{store: store} <- Enum.find(entries, &(&1.identity === identity)),
         {:ok, artifact} <- Registry.lookup(store, identity["artifact"]),
         true <- artifact.digest === identity["artifact_sha256"] do
      if artifact.manifest["id"] == "ipse-knowledge/knowledge" do
        with {:ok, bytes} <-
               Artifact.read_declared(store, artifact.digest, "operator.json", 65_536),
             {:ok, sidecar} <- JSON.decode_unique(bytes),
             true <- is_map(sidecar) and sidecar["domain"] == "knowledge" do
          cond do
            sidecar["preset"] == "decision-shadow" ->
              with {:ok, bundles} <- Bundles.inventory(),
                   true <-
                     Enum.any?(bundles, fn bundle ->
                       bundle.id == "knowledge-decision-shadow" and
                         bundle.digest == artifact.digest
                     end),
                   do: {:ok, :experiment},
                   else: (_ -> @error)

            experiment_outer? ->
              @error

            true ->
              {:ok, :ordinary}
          end
        else
          _ -> @error
        end
      else
        if experiment_outer?, do: @error, else: {:ok, :ordinary}
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def reserve(context, intent, runtime, dispatch) do
    config = context[:config]
    admission = config[:semantic_admission]
    pin = if is_map(admission), do: admission["pin"]
    outer = get_in(context, [:parent, "semantic_binding"])
    request = intent["request"]
    now = System.system_time(:millisecond)

    with true <- is_map(dispatch) and is_map(pin),
         true <- SemanticAdmission.valid?(admission, context[:session_id]),
         true <- SemanticAdmission.valid_outer_receipt?(outer, context[:session_id]),
         true <- outer["class"] == "decision.create",
         true <-
           outer["pin"] === pin and
             outer["artifact_sha256"] === context.identity["artifact_sha256"],
         true <- pin["identity_sha256"] === JSON.digest([context.identity]),
         true <- intent["approval"] === "approved" and DecisionCall.validate(request) == :ok,
         true <- match?(%{dependencies: [_ | _]}, dispatch[:managed]),
         true <- pending_input_bound?(dispatch.managed.dependencies, request),
         true <- JSON.safe_uint?(dispatch[:source_generation]),
         true <- runtime[:provider] == :system_one_compatible,
         {:ok, %{route: route}} <-
           Ipse.InferenceDispatch.selection(
             config,
             runtime,
             "decision.create",
             request["profile"]
           ),
         true <- route["billing_mode"] == "local",
         true <- numeric_loopback?(route["endpoint"]),
         {:ok, mode} <- Mode.capture(config),
         :ok <- Mode.knowledge(mode, "decision.create"),
         policy = admission["policy"],
         true <- is_map(get_in(policy, ["settings", "experiment"])),
         true <- route in policy["settings"]["routes"],
         [mapping] <-
           Enum.filter(policy["settings"]["effects"], fn mapping ->
             mapping["class"] == "decision.create" and mapping["inner_op"] == "decision.create" and
               mapping["outer_sha256"] == outer["descriptor_sha256"]
           end),
         {:ok, body} <-
           Ipse.Provider.Decision.encode(
             Transport.engine(runtime.provider),
             DecisionCall.neutral(request),
             runtime.model
           ),
         reserved =
           Map.merge(Consent.zero(), %{
             "operations" => 1,
             "model_calls" => 1,
             "input_bytes" => byte_size(Jason.encode!(body)),
             "output_bytes" => 65_536
           }),
         binding = %{
           "session_id" => context.session_id,
           "operation_id" => intent["operation_id"],
           "request_sha256" => intent["request_sha256"],
           "effect_binding" => intent["effect_binding"],
           "wire" => dispatch.wire,
           "dependencies_sha256" => dispatch.managed.sha256
         },
         reservation = %{
           "id" => intent["operation_id"],
           "operation" => mapping["operation"],
           "artifact_sha256" => context.identity["artifact_sha256"],
           "source_sha256" => pin["source_sha256"],
           "policy_sha256" => pin["policy_sha256"],
           "request_sha256" => JSON.digest([binding]),
           "source_generation" => dispatch.source_generation,
           "reserved" => reserved,
           "headless" => mode["headless"]
         },
         root = SemanticAdmission.control_root(config[:home]),
         {:ok, ticket} <- Consent.reserve_experiment(root, pin["project_id"], reservation, now),
         false <- Map.has_key?(ticket, "existing") do
      case Consent.admit(root, pin["project_id"], ticket, System.system_time(:millisecond)) do
        {:ok, ^ticket} ->
          expires_at = policy["expires_at_ms"]
          remaining = max(expires_at - System.system_time(:millisecond), 0)

          {:ok,
           %{
             root: root,
             project: pin["project_id"],
             ticket: ticket,
             reserved: reserved,
             issued_at: policy["settings"]["experiment"]["issued_at_ms"],
             expires_at: expires_at,
             deadline: System.monotonic_time(:millisecond) + remaining
           }}

        _ ->
          _ = Consent.settle(root, pin["project_id"], ticket, :unstarted)
          @error
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc false
  def pending_input_bound?(dependencies, request) when is_list(dependencies) do
    case Enum.filter(dependencies, &(&1["version"] === 7)) do
      [] ->
        true

      [dependency] ->
        with true <- Ipse.Session.ManagedReference.dependency?(dependency),
             {:ok, %{"candidates" => [%{"id" => "candidate", "input" => input} = row]} = outer} <-
               JSON.decode_unique(request["input"]),
             true <- Map.keys(outer) === ["candidates"],
             true <- Enum.sort(Map.keys(row)) === ~w(id input),
             {:ok, candidate} <- JSON.decode_unique(input),
             true <-
               Enum.sort(Map.keys(candidate)) === ~w(assigned_category candidate_id reason text),
             true <- JSON.digest([candidate]) === dependency["subject"]["assessment_sha256"],
             [%{"id" => "candidate", "type" => "choice", "choices" => choices}] <-
               request["questions"],
             true <- Enum.sort(choices) === ~w(defer_candidate keep_baseline) do
          true
        else
          _ -> false
        end

      _ ->
        false
    end
  rescue
    _ -> false
  end

  def pending_input_bound?(_, _), do: false

  def settle(claim, result) do
    outcome = if match?({:ok, _, _}, result), do: {:known, claim.reserved}, else: :unknown

    case Consent.settle(claim.root, claim.project, claim.ticket, outcome) do
      {:ok, _} -> :ok
      _ -> {:error, :decision_experiment_settlement_unconfirmed}
    end
  end
end
