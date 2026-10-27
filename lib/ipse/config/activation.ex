defmodule Ipse.Config.Activation do
  @moduledoc "Host-only protected activation overlays after ordinary configuration fingerprinting."
  alias Ipse.Extension.{
    Activation,
    Artifact,
    Bundles,
    Consent,
    ProjectIdentity,
    Registry,
    SemanticAdmission,
    SemanticConsent,
    SemanticRoutes
  }

  alias Ipse.JSON
  @fields ~w(extensions inference_services semantic_selections timeout_ms)a
  @error {:error, :extension_activation_refused}

  def fresh(config, cwd) do
    config = restore_base(config)

    cond do
      child?(config) or config[:extensions_disabled] === true ->
        {:ok, config}

      true ->
        with {:ok, %{binding: binding, snapshot: snapshot}} <- current(config, cwd) do
          if is_nil(binding),
            do: fresh_join(config, cwd),
            else: fresh_bound(config, cwd, binding, snapshot)
        end
    end
  rescue
    _ -> @error
  end

  defp fresh_join(config, cwd) do
    with {:ok, joined} <-
           ProjectIdentity.join_existing(config[:home], cwd, fn binding ->
             authorize_join(config, binding)
           end) do
      if is_nil(joined) do
        {:ok, config}
      else
        with {:ok, %{binding: ^joined, snapshot: snapshot}} <- current(config, cwd),
             do: fresh_bound(config, cwd, joined, snapshot)
      end
    end
  end

  defp authorize_join(config, binding) do
    with {:ok, snapshot} <- existing_snapshot(config[:home], binding["project_id"]) do
      policy = if is_map(snapshot), do: snapshot["policy"]

      cond do
        is_nil(policy) ->
          :deny

        not SemanticConsent.policy?(policy) ->
          @error

        is_nil(get_in(policy, ["settings", "activation"])) or
          get_in(policy, ["settings", "scope", "kind"]) != "project" or
            policy["expires_at_ms"] <= System.system_time(:millisecond) ->
          :deny

        true ->
          Consent.with_policy(
            SemanticAdmission.control_root(config[:home]),
            binding["project_id"],
            snapshot["epoch"],
            JSON.digest([policy]),
            System.system_time(:millisecond),
            fn _ -> apply_overlay(config, policy, :fresh) end
          )
          |> case do
            {:ok, _} -> :ok
            other -> other
          end
      end
    end
  end

  @doc "Read existing protected state without activating code or creating a project; grants no authority."
  def current(config, cwd) do
    with {:ok, binding} <- ProjectIdentity.existing(config[:home], cwd) do
      if is_nil(binding) do
        {:ok, %{binding: nil, snapshot: nil}}
      else
        ProjectIdentity.with_binding(config[:home], cwd, binding, fn _ ->
          with {:ok, snapshot} <- existing_snapshot(config[:home], binding["project_id"]),
               do: {:ok, %{binding: binding, snapshot: snapshot}}
        end)
      end
    end
  rescue
    _ -> @error
  end

  defp fresh_bound(config, cwd, binding, snapshot) do
    ProjectIdentity.with_binding(config[:home], cwd, binding, fn _ ->
      policy = if is_map(snapshot), do: snapshot["policy"]

      cond do
        is_nil(policy) ->
          {:ok, config}

        not SemanticConsent.policy?(policy) ->
          @error

        is_nil(get_in(policy, ["settings", "activation"])) ->
          {:ok, config}

        policy["expires_at_ms"] <= System.system_time(:millisecond) ->
          {:ok, config}

        not scope_matches?(policy, binding) ->
          {:ok, config}

        true ->
          Consent.with_policy(
            SemanticAdmission.control_root(config[:home]),
            binding["project_id"],
            snapshot["epoch"],
            JSON.digest([policy]),
            System.system_time(:millisecond),
            fn _ ->
              apply_overlay(config, policy, :fresh)
            end
          )
      end
    end)
  end

  def resume(config, _cwd, id, admission) do
    config = restore_base(config)

    with true <- is_nil(admission) or SemanticAdmission.valid?(admission, id) do
      a = if is_map(admission), do: get_in(admission, ["policy", "settings", "activation"])

      cond do
        is_nil(a) -> {:ok, config}
        child?(config) or config[:extensions_disabled] === true -> @error
        true -> apply_overlay(config, admission["policy"], :resume)
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc false
  def admitted(config, admission) do
    case config[:activation_policy_sha256] do
      nil ->
        :ok

      sha ->
        if is_map(admission) and admission["status"] == "active" and admission["version"] === 2 and
             JSON.digest([admission["policy"]]) == sha do
          :ok
        else
          @error
        end
    end
  rescue
    _ -> @error
  end

  @doc false
  def restore_base(config) do
    case config[:activation_base] do
      %{fields: fields, absent: absent} ->
        config
        |> Map.drop(absent ++ [:activation_base, :activation_policy_sha256])
        |> Map.merge(fields)

      nil ->
        config
    end
  end

  @doc false
  def child_base(config), do: config |> restore_base() |> Map.delete(:base_extension_catalog)

  defp apply_overlay(config, policy, phase) do
    a = policy["settings"]["activation"]

    with true <- is_map(config[:base_extension_catalog]),
         true <-
           not Map.has_key?(a, "main_timeout_ms") or
             (is_integer(config[:timeout_ms]) and a["main_timeout_ms"] <= config[:timeout_ms]),
         true <- phase == :resume or current_bundle?(a),
         {:ok, artifact} <-
           Artifact.lookup(Path.join(config[:home], "extensions/artifacts"), a["artifact"]),
         :ok <- sidecar(artifact, a),
         {:ok, overlay} <- Activation.derive(policy, config[:base_extension_catalog]),
         true <- Enum.sort(artifact.manifest["capabilities"]) == a["capabilities"],
         {:ok, entries} <- Registry.prepare(overlay.catalog, config[:home]),
         true <-
           Enum.reject(entries, &(&1.identity["instance"] == a["instance"])) ===
             Map.get(config, :extensions, []),
         {:ok, selectors} <- SemanticRoutes.selectors(policy["settings"]["routes"]),
         selected_config = Map.put(config, :extensions, entries),
         {:ok, reviewed} <- SemanticRoutes.review(selected_config, selectors),
         true <- reviewed.routes === policy["settings"]["routes"],
         {:ok, selections} <- Ipse.Config.Semantics.selection(policy),
         true <- not conflicting_selection?(config[:semantic_selections] || %{}, selections),
         selected_config =
           selected_config
           |> Map.put(:inference_services, reviewed.registry)
           |> Map.put(
             :semantic_selections,
             Map.merge(config[:semantic_selections] || %{}, selections)
           ),
         selected_config =
           if(Map.has_key?(overlay, :main_timeout_ms),
             do: Map.put(selected_config, :timeout_ms, overlay.main_timeout_ms),
             else: selected_config
           ),
         true <- Registry.valid_entries?(selected_config),
         :ok <- Ipse.Extension.ModelCall.configuration(selected_config),
         :ok <- Ipse.Config.Profiles.embedding_configuration(selected_config),
         :ok <- Ipse.Config.Decisions.configuration(selected_config) do
      {:ok,
       selected_config
       |> Map.put(:activation_base, %{
         fields: Map.take(config, @fields),
         absent: @fields -- Map.keys(config)
       })
       |> Map.put(:activation_policy_sha256, JSON.digest([policy]))}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp conflicting_selection?(base, selected),
    do: Enum.any?(selected, fn {id, entry} -> Map.has_key?(base, id) and base[id] !== entry end)

  defp current_bundle?(a) do
    with {:ok, entries} <- Bundles.inventory(),
         do: Enum.any?(entries, &(&1.digest == a["artifact_sha256"]))
  end

  defp sidecar(artifact, a) do
    case Enum.find(artifact.manifest["files"], &(&1["path"] == "operator.json")) do
      %{"sha256" => sha, "bytes" => bytes} when bytes <= 65_536 ->
        if sha == a["sidecar_sha256"], do: :ok, else: @error

      _ ->
        @error
    end
  end

  defp existing_snapshot(home, project) do
    root = SemanticAdmission.control_root(home)
    directory = Path.join(root, project)
    uid = File.lstat!(home).uid

    with :ok <- present_directory(root, uid),
         :ok <- present_directory(directory, uid),
         {:ok, _} <- present_file(Path.join(directory, "control.json"), uid),
         {:ok, %{size: 0} = retained} <- present_file(Path.join(directory, ".lock"), uid, false),
         {:ok, snapshot} <- Consent.snapshot(root, project),
         {:ok, after_lock} <- File.lstat(Path.join(directory, ".lock")),
         true <-
           Map.take(retained, ~w(major_device inode uid mode links size)a) ==
             Map.take(after_lock, ~w(major_device inode uid mode links size)a) do
      {:ok, snapshot}
    else
      :absent -> {:ok, nil}
      _ -> @error
    end
  end

  defp present_directory(path, uid) do
    case File.lstat(path) do
      {:error, :enoent} ->
        :absent

      {:ok, %{type: :directory, uid: ^uid, mode: mode}} ->
        if Bitwise.band(mode, 0o077) == 0, do: :ok, else: @error

      _ ->
        @error
    end
  end

  defp present_file(path, uid, absent? \\ true) do
    case File.lstat(path) do
      {:error, :enoent} when absent? ->
        :absent

      {:ok, %{type: :regular, uid: ^uid, links: 1, mode: mode} = stat} ->
        if Bitwise.band(mode, 0o7777) == 0o600, do: {:ok, stat}, else: @error

      _ ->
        @error
    end
  end

  defp scope_matches?(policy, binding) do
    scope = policy["settings"]["scope"]

    policy["project"] == binding["project_id"] and
      (scope["kind"] == "project" or scope["worktree_id"] == binding["worktree_id"])
  end

  defp child?(c), do: c[:parallel_child] === true or not is_nil(c[:delegation_origin])
end
