defmodule Ipse.Extension.SemanticAdmission do
  @moduledoc """
  Host-only fresh/resumed Session semantic pins, with no worker or inference IO.

  One reviewed artifact policy is active per protected project ledger. Domain
  bundles may compose feature operations; separate same-project artifact policies
  cannot silently coexist or multiply the project's control allocation ceiling.
  An unavailable fresh selection returns a bounded inactive status, never another
  provider, artifact or permission. The client must show that status. Every live
  read/effect still revalidates identity, policy and source/suppression generation
  at its own control/storage boundary; an admission descriptor is not a ticket.
  """
  alias Ipse.Extension.{Consent, ProjectIdentity, SemanticConsent, SemanticRoutes, Mode}
  alias Ipse.Config.Semantics
  @keys ~w(version binding instance pin selectors status)
  @statuses ~w(off active identity_unavailable consent_unavailable permission_missing permission_mismatch artifact_unavailable route_unavailable)
  @error {:error, :invalid_semantic_admission}

  def control_root(home), do: Path.join(home, "knowledge-control")
  def collection_root(home), do: Path.join(home, "knowledge-collections")

  @doc "Build only new-Session authority from protected state and actual admitted routes."
  def fresh(config, cwd, session_id) do
    selections = Map.get(config, :semantic_selections, %{})

    with :ok <- Semantics.validate(selections), true <- session_id?(session_id) do
      if Enum.any?(selections, fn {_, entry} -> entry["enabled"] end) do
        case ProjectIdentity.resolve(config[:home], cwd) do
          {:ok, binding} -> fresh_bound(config, cwd, session_id, binding, selections)
          _ -> {:ok, inactive("identity_unavailable")}
        end
      else
        {:ok, inactive("off")}
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp fresh_bound(config, cwd, id, binding, selections) do
    case ProjectIdentity.with_binding(config[:home], cwd, binding, fn _ ->
           Consent.snapshot(control_root(config.home), binding["project_id"])
         end) do
      {:ok, %{"policy" => nil}} ->
        {:ok, inactive("permission_missing")}

      {:ok, %{"policy" => policy} = snapshot} ->
        instance = if is_map(policy), do: get_in(policy, ["settings", "instance"])

        cond do
          not Semantics.selected?(selections, instance, policy) ->
            {:ok, inactive("permission_mismatch")}

          is_nil(identity(config, instance)) ->
            {:ok, inactive("artifact_unavailable")}

          true ->
            with {:ok, selectors} <- SemanticRoutes.selectors(policy["settings"]["routes"]),
                 {:ok, namespace} <-
                   SemanticConsent.namespace(
                     binding["project_id"],
                     policy["settings"]["storage"]["collection"]
                   ),
                 {:ok, context} <-
                   context_for(config, binding, instance, selectors, namespace, id, 0),
                 {:ok, pin} when not is_nil(pin) <-
                   Semantics.admit(
                     selections,
                     snapshot,
                     context,
                     System.system_time(:millisecond)
                   ) do
              descriptor = %{
                "version" => 1,
                "binding" => binding,
                "instance" => instance,
                "pin" => pin,
                "selectors" => selectors,
                "status" => "active"
              }

              if valid?(descriptor, id), do: {:ok, descriptor}, else: @error
            else
              _ -> {:ok, inactive("route_unavailable")}
            end
        end

      _ ->
        {:ok, inactive("consent_unavailable")}
    end
  end

  @doc "Resume only the original descriptor; nil/legacy admission never activates a new grant."
  def resume(config, cwd, session_id, descriptor) do
    cond do
      is_nil(descriptor) ->
        {:ok, inactive("off")}

      not valid?(descriptor, session_id) ->
        @error

      is_nil(descriptor["pin"]) ->
        {:ok, descriptor}

      true ->
        with {:ok, context} <-
               context_for(
                 config,
                 descriptor["binding"],
                 descriptor["instance"],
                 descriptor["selectors"],
                 descriptor["pin"]["namespace"],
                 session_id,
                 0
               ),
             {:ok, _pin} <- SemanticConsent.resume(descriptor["pin"], context),
             :ok <-
               ProjectIdentity.with_binding(config[:home], cwd, descriptor["binding"], fn _ ->
                 :ok
               end) do
          {:ok, descriptor}
        else
          _ -> @error
        end
    end
  rescue
    _ -> @error
  end

  @doc "Construct current host context; the caller must still revalidate protected binding and source generation."
  def context(config, session_id, generation) do
    descriptor = config[:semantic_admission]

    if valid?(descriptor, session_id) and descriptor["pin"] != nil do
      result =
        context_for(
          config,
          descriptor["binding"],
          descriptor["instance"],
          descriptor["selectors"],
          descriptor["pin"]["namespace"],
          session_id,
          generation
        )

      with {:ok, context} <- result,
           {:ok, _} <- SemanticConsent.resume(descriptor["pin"], context),
           do: {:ok, context}
    else
      {:error, :semantic_consent_denied}
    end
  rescue
    _ -> {:error, :semantic_consent_denied}
  end

  def valid?(descriptor, session_id) do
    (is_nil(session_id) or session_id?(session_id)) and
      is_map(descriptor) and Enum.sort(Map.keys(descriptor)) == Enum.sort(@keys) and
      descriptor["version"] === 1 and descriptor["status"] in @statuses and bounded?(descriptor) and
      if is_nil(descriptor["pin"]) do
        is_nil(descriptor["binding"]) and is_nil(descriptor["instance"]) and
          descriptor["selectors"] === [] and descriptor["status"] != "active"
      else
        pin = descriptor["pin"]

        SemanticConsent.pin?(pin) and (is_nil(session_id) or pin["session_id"] == session_id) and
          SemanticConsent.binding?(descriptor["binding"]) and
          pin["project_id"] == descriptor["binding"]["project_id"] and
          pin["worktree_id"] == descriptor["binding"]["worktree_id"] and
          pin["binding_sha256"] == descriptor["binding"]["binding_sha256"] and
          is_binary(descriptor["instance"]) and descriptor["status"] == "active" and
          SemanticRoutes.selectors(descriptor["selectors"]) === {:ok, descriptor["selectors"]} and
          Enum.any?(descriptor["selectors"], &(&1["operation"] == "main"))
      end
  rescue
    _ -> false
  end

  defp context_for(config, binding, instance, selectors, namespace, id, generation) do
    with identity when is_map(identity) <- identity(config, instance),
         {:ok, routes} <- SemanticRoutes.resolve(config, selectors),
         {:ok, mode} <- Mode.capture(config),
         context = %{
           "session_id" => id,
           "binding" => binding,
           "identity" => identity,
           "namespace" => namespace,
           "routes" => routes,
           "mode" => mode,
           "source_generation" => generation
         },
         true <- SemanticConsent.context?(context) do
      {:ok, context}
    else
      _ -> @error
    end
  end

  defp identity(config, instance) do
    Enum.find_value(Map.get(config, :extensions, []), fn entry ->
      if entry.identity["instance"] == instance, do: entry.identity
    end)
  end

  defp inactive(status),
    do: %{
      "version" => 1,
      "binding" => nil,
      "instance" => nil,
      "pin" => nil,
      "selectors" => [],
      "status" => status
    }

  defp session_id?(s), do: is_binary(s) and Regex.match?(~r/\A[0-9a-f]{32}\z/, s)

  defp bounded?(value) do
    bytes = Jason.encode!(value)
    byte_size(bytes) <= 32_768 and Ipse.JSON.decode_unique(bytes, 12) === {:ok, value}
  end
end
