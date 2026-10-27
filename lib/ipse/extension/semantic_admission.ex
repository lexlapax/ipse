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

  @doc "Check a reviewed outer publication export outside Session before entering its worker."
  def outer(config, cwd, session_id, identity, descriptor) do
    with {:ok, context} <- context(config, session_id, 0),
         true <- config[:semantic_admission]["version"] === 2,
         true <- context["identity"] === identity,
         true <- descriptor["stage"] in ~w(invoke.tool invoke.command),
         true <- descriptor["instance"] == identity["instance"],
         true <- Ipse.Extension.Registry.live?(identity),
         admission = config[:semantic_admission],
         pin = admission["pin"] do
      base = %{
        "kind" => "semantic.outer",
        "version" => 1,
        "namespace" => pin["namespace"],
        "pin" => pin,
        "artifact_sha256" => identity["artifact_sha256"],
        "descriptor_sha256" => Ipse.JSON.digest([descriptor])
      }

      ProjectIdentity.with_binding(config[:home], cwd, admission["binding"], fn _ ->
        Consent.with_policy(
          control_root(config[:home]),
          pin["project_id"],
          pin["epoch"],
          pin["policy_sha256"],
          System.system_time(:millisecond),
          fn snapshot ->
            policy = snapshot["policy"]

            with true <- SemanticConsent.policy?(policy),
                 true <- not context["mode"]["headless"] or policy["headless"],
                 {:ok, class} <- outer_class(policy, base["descriptor_sha256"]),
                 :ok <- Mode.knowledge(context["mode"], class) do
              {:ok, Map.put(base, "class", class)}
            else
              _ -> {:error, :semantic_outer_denied}
            end
          end
        )
      end)
    else
      _ -> {:error, :semantic_outer_denied}
    end
  rescue
    _ -> {:error, :semantic_outer_denied}
  end

  @doc "Structural replay binding only; this never substitutes for the current protected outer check."
  def valid_outer_receipt?(binding, session_id) do
    is_map(binding) and
      Enum.sort(Map.keys(binding)) ==
        ~w(artifact_sha256 class descriptor_sha256 kind namespace pin version) and
      binding["kind"] == "semantic.outer" and binding["version"] === 1 and
      binding["class"] in ~w(collection.read collection.publish) and
      SemanticConsent.pin?(binding["pin"]) and binding["pin"]["session_id"] == session_id and
      binding["namespace"] == binding["pin"]["namespace"] and
      Ipse.JSON.sha256?(binding["artifact_sha256"]) and
      Ipse.JSON.sha256?(binding["descriptor_sha256"])
  rescue
    _ -> false
  end

  def valid_outer_binding?(binding, identity, descriptor, session_id, metadata \\ nil) do
    pin = if is_map(binding), do: binding["pin"]

    valid_outer_receipt?(binding, session_id) and
      pin["identity_sha256"] == Ipse.JSON.digest([identity]) and
      binding["artifact_sha256"] == identity["artifact_sha256"] and
      binding["descriptor_sha256"] == Ipse.JSON.digest([descriptor]) and
      descriptor["instance"] == identity["instance"] and
      descriptor["stage"] in ~w(invoke.tool invoke.command) and
      binding["namespace"] == pin["namespace"] and
      (is_nil(metadata) or
         (valid?(metadata["semantic_admission"], session_id) and
            metadata["semantic_admission"]["version"] === 2 and
            metadata["semantic_admission"]["pin"] === pin and
            metadata["semantic_admission"]["instance"] == identity["instance"] and
            metadata["semantic_admission"]["policy"]["artifact_sha256"] ==
              identity["artifact_sha256"] and
            outer_class(metadata["semantic_admission"]["policy"], binding["descriptor_sha256"]) ===
              {:ok, binding["class"]} and
            Mode.knowledge(metadata["execution_mode"], binding["class"]) == :ok))
  rescue
    _ -> false
  end

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
                "version" => 2,
                "binding" => binding,
                "instance" => instance,
                "pin" => pin,
                "selectors" => selectors,
                "status" => "active",
                "policy" => policy
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
      is_map(descriptor) and admission_keys?(descriptor) and
      descriptor["status"] in @statuses and bounded?(descriptor) and
      if is_nil(descriptor["pin"]) do
        is_nil(descriptor["binding"]) and is_nil(descriptor["instance"]) and
          descriptor["selectors"] === [] and descriptor["status"] != "active"
      else
        pin = descriptor["pin"]

        SemanticConsent.pin?(pin) and (is_nil(session_id) or pin["session_id"] == session_id) and
          original_policy?(descriptor) and
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

  defp admission_keys?(%{"version" => 1} = d), do: Enum.sort(Map.keys(d)) == Enum.sort(@keys)

  defp admission_keys?(%{"version" => 2} = d),
    do: Enum.sort(Map.keys(d)) == Enum.sort(["policy" | @keys]) and is_map(d["pin"])

  defp admission_keys?(_), do: false

  defp original_policy?(%{"version" => 1}), do: true

  defp original_policy?(d) do
    p = d["policy"]
    pin = d["pin"]

    SemanticConsent.policy?(p) and Ipse.JSON.digest([p]) == pin["policy_sha256"] and
      p["project"] == pin["project_id"] and p["source_sha256"] == pin["source_sha256"] and
      p["settings"]["identity_sha256"] == pin["identity_sha256"] and
      p["settings"]["namespace"] == pin["namespace"] and
      p["settings"]["instance"] == d["instance"] and
      SemanticRoutes.selectors(p["settings"]["routes"]) === {:ok, d["selectors"]} and
      (p["settings"]["scope"]["kind"] == "project" or
         p["settings"]["scope"]["worktree_id"] == pin["worktree_id"]) and
      Ipse.JSON.digest([p["settings"]["routes"]]) == pin["routes_sha256"]
  end

  def outer_class(policy, descriptor_sha256) do
    effects =
      Enum.filter(
        policy["settings"]["effects"],
        &(&1["outer_sha256"] == descriptor_sha256 and
            &1["inner_op"] in ~w(collection.call collection.managed))
      )

    publish = Enum.filter(effects, &(&1["class"] == "collection.publish"))

    cond do
      publish != [] and
          Enum.any?(
            publish,
            &match?({:ok, _}, Ipse.Extension.SemanticConsent.constraints(policy["settings"], &1))
          ) ->
        {:ok, "collection.publish"}

      publish != [] ->
        {:error, :semantic_outer_denied}

      Enum.any?(effects, &(&1["class"] == "collection.read")) ->
        {:ok, "collection.read"}

      true ->
        {:error, :semantic_outer_denied}
    end
  rescue
    _ -> {:error, :semantic_outer_denied}
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
    {max_bytes, depth} = if value["version"] === 2, do: {65_536, 16}, else: {32_768, 12}
    byte_size(bytes) <= max_bytes and Ipse.JSON.decode_unique(bytes, depth) === {:ok, value}
  end
end
