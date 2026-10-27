defmodule Ipse.CLI.Knowledge do
  @moduledoc "Standalone native review of protected knowledge permission; no worker or inference is started."
  alias Ipse.CLI.Terminal

  alias Ipse.Extension.{
    Activation,
    Artifact,
    Bundles,
    Catalog,
    CollectionPolicy,
    Consent,
    ManagedRecipe,
    ProjectIdentity,
    Registry,
    SemanticAdmission,
    SemanticConsent,
    SemanticRoutes
  }

  alias Ipse.JSON
  @options ~w(cwd config project_config trust_project_config json)a
  @day 86_400_000
  @error {:error, :knowledge_setup_refused}

  def run(command, opts, home, cwd) when command in ~w(enable setup status permissions disable) do
    with true <- Enum.all?(Keyword.keys(opts), &(&1 in @options)),
         true <- command in ~w(status permissions) or opts[:json] != true,
         {:ok, cwd} <- Ipse.Workspace.canonical_path(cwd),
         {:ok, config} <- runtime(opts, home, cwd) do
      result =
        case command do
          value when value in ~w(enable setup) -> enable(config, cwd)
          "disable" -> disable(config, cwd)
          _ -> status(config, cwd, command, opts[:json] == true)
        end

      case result do
        :ok -> 0
        {:error, reason} -> fail(reason)
        _ -> fail(:knowledge_setup_unconfirmed)
      end
    else
      false -> fail(:unsupported_knowledge_options)
      {:error, reason} -> fail(reason)
      _ -> fail(:knowledge_setup_refused)
    end
  rescue
    _ -> fail(:knowledge_setup_refused)
  end

  def run(_, _, _, _), do: fail(:unknown_knowledge_command)

  defp runtime(opts, home, cwd) do
    client = %{
      workspace: cwd,
      home: home,
      auth_dir: Path.join(home, "auth"),
      operator_home: Ipse.Workspace.operator_home(),
      mcp_config: nil,
      base_url: nil,
      operator_questions: false,
      accept_edits: false,
      approval: :ask,
      approval_origin: :interactive,
      headless: false
    }

    with {:ok, effective} <- Ipse.Config.resolve(cwd, home, Keyword.delete(opts, :json)),
         do: Ipse.Config.runtime(effective, client)
  end

  defp status(config, cwd, command, json?) do
    inspect =
      if command == "permissions",
        do: &Ipse.Config.Activation.current/2,
        else: &Ipse.Config.Activation.readiness/2

    with {:ok, current} <- inspect.(config, cwd) do
      policy = if current.snapshot, do: current.snapshot["policy"]

      value = %{
        "activation_ready_now" => Map.get(current, :ready),
        "worktree_admitted" => not is_nil(current.binding),
        "project" => current.binding,
        "epoch" => if(current.snapshot, do: current.snapshot["epoch"], else: nil),
        "policy_sha256" => if(policy, do: JSON.digest([policy]), else: nil),
        "headless" => if(policy, do: policy["headless"], else: false),
        "expires_at_ms" => if(policy, do: policy["expires_at_ms"], else: nil)
      }

      value = if command == "permissions", do: Map.put(value, "policy", policy), else: value

      if json? or command == "permissions" do
        Terminal.puts(Jason.encode!(value, pretty: true))
      else
        Terminal.puts(
          cond do
            current.ready ->
              "Saved knowledge selection is ready for the next new session."

            is_nil(current.binding) ->
              "This folder is not admitted. A new session can join a reciprocally verified worktree when its existing repository grant permits it."

            true ->
              "No ready knowledge selection is saved for this folder."
          end
        )

        Terminal.puts(
          "Existing sessions retain their catalog and check current permission before each effect."
        )
      end

      :ok
    end
  end

  defp enable(config, cwd) do
    with {:ok, :native} <- Ipse.Runner.operator_channel(),
         :ok <- private_home(config.home),
         {:ok, binding} <- admit_project(config.home, cwd),
         {:ok, artifact} <- Bundles.install("knowledge", config.home),
         now = System.system_time(:millisecond),
         {:ok, proposal} <- prepare(config, binding, artifact.digest, now),
         {:ok, before} <- current_snapshot(config.home, binding["project_id"]),
         :ok <- confirm("enable", review(binding, proposal.policy)),
         {:ok, _} <-
           ProjectIdentity.with_binding(config.home, cwd, binding, fn _ ->
             with {:ok, repeated} <- prepare(config, binding, artifact.digest, now),
                  true <- repeated === proposal do
               Consent.replace(
                 SemanticAdmission.control_root(config.home),
                 binding["project_id"],
                 before["epoch"],
                 proposal.policy,
                 System.system_time(:millisecond)
               )
             else
               _ -> @error
             end
           end) do
      Terminal.puts(
        "Saved knowledge permission. Start a new chat or run to adopt this selection."
      )

      :ok
    else
      {:ok, :pipe} -> {:error, :knowledge_requires_native_terminal}
      {:error, _} = error -> error
      _ -> @error
    end
  end

  defp disable(config, cwd) do
    with {:ok, current} <- Ipse.Config.Activation.current(config, cwd) do
      if is_nil(current.binding) or is_nil(current.snapshot) or is_nil(current.snapshot["policy"]) do
        Terminal.puts("Knowledge permission is already off.")
        :ok
      else
        binding = current.binding

        with :ok <-
               confirm(
                 "disable",
                 "Revoke knowledge permission for #{binding["root"]}.\nProject #{binding["project_id"]}; epoch #{current.snapshot["epoch"]}.\nLater effects will be denied. Already admitted work may have started. Stored records remain available for management.\n"
               ),
             {:ok, _} <-
               ProjectIdentity.with_binding(config.home, cwd, binding, fn _ ->
                 Consent.revoke(
                   SemanticAdmission.control_root(config.home),
                   binding["project_id"],
                   current.snapshot["epoch"]
                 )
               end) do
          Terminal.puts("Knowledge permission revoked. New sessions use the ordinary catalog.")
          :ok
        end
      end
    end
  end

  @doc "Build review data from actual installed bytes and configuration; grants no permission."
  def prepare(config, binding, digest, now) do
    with true <- JSON.safe_uint?(now),
         {:ok, bundled} <- Bundles.inventory(),
         true <- Enum.any?(bundled, &(&1.id == "knowledge" and &1.digest == digest)),
         {:ok, artifact} <-
           Artifact.lookup(Path.join(config.home, "extensions/artifacts"), digest),
         {:ok, sidecar_bytes} <-
           Artifact.read_declared(
             Path.join(config.home, "extensions/artifacts"),
             digest,
             "operator.json",
             65_536
           ),
         {:ok, sidecar} <- JSON.decode_unique(sidecar_bytes),
         true <- Enum.sort(Map.keys(sidecar)) == ~w(domain preset publication recipes version),
         true <-
           sidecar["version"] === 1 and sidecar["domain"] == "knowledge" and
             sidecar["preset"] == "native",
         {:ok, constraints, recipes} <- recipes(sidecar),
         true <- is_map(config[:base_extension_catalog]),
         true <- is_integer(config[:timeout_ms]) and config[:timeout_ms] >= 1000,
         a = %{
           "version" => 1,
           "kind" => "reviewed.bundle",
           "artifact" => digest,
           "artifact_sha256" => digest,
           "sidecar_sha256" => JSON.sha256(sidecar_bytes),
           "instance" => "knowledge",
           "options" => empty_options(),
           "capabilities" => artifact.manifest["capabilities"],
           "service_refs" => [],
           "order" => 100,
           "lifetime" => "session",
           "allow_children" => false,
           "main_timeout_ms" => min(config[:timeout_ms], 90_000)
         },
         {:ok, drafted} <-
           Activation.draft(binding["project_id"], a, config.base_extension_catalog),
         {:ok, entries} <- Registry.prepare(drafted.catalog, config.home),
         selected = Map.put(config, :extensions, entries),
         {:ok, reviewed} <- SemanticRoutes.review(selected, [main_selector()]),
         a = %{
           a
           | "service_refs" =>
               Enum.map(reviewed.routes, &Map.take(&1, ~w(operation service_id profile)))
         },
         {:ok, final_draft} <-
           Activation.draft(binding["project_id"], a, config.base_extension_catalog),
         {:ok, final_entries} <- Registry.prepare(final_draft.catalog, config.home),
         entry when is_map(entry) <-
           Enum.find(final_entries, &(&1.identity["instance"] == "knowledge")),
         {:ok, catalog} <- Catalog.snapshot(Map.put(config, :extensions, final_entries)),
         {:ok, namespace} <- SemanticConsent.namespace(binding["project_id"], "knowledge"),
         selection = %{
           "version" => 2,
           "domain" => "knowledge",
           "namespace" => namespace,
           "scope" => %{"kind" => "project", "worktree_id" => nil},
           "sources" => %{
             "categories" =>
               Enum.sort(
                 ~w(interactive_operator native_operator_answer typed_host_outcome unattended_input assistant_proposal)
               ),
             "exclusions" => []
           },
           "storage" => %{"kind" => "local_collection", "collection" => "knowledge"},
           "retention" => %{"automatic" => 90, "manual" => 3650},
           "routes" => reviewed.routes,
           "effects" => effects(catalog, sidecar),
           "constraints" => constraints,
           "recipes" => recipes,
           "activation" => a,
           "limits" =>
             Map.merge(Consent.zero(), %{
               "operations" => 100,
               "input_bytes" => 2_097_152,
               "output_bytes" => 4_194_304
             }),
           "period_ms" => @day,
           "expires_at_ms" => now + 365 * @day,
           "headless" => true
         },
         {:ok, policy} <- SemanticConsent.prepare(binding, entry.identity, selection) do
      {:ok, %{policy: policy}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp recipes(sidecar) do
    rows =
      for kind <- ~w(note pending), do: {sidecar["publication"][kind], sidecar["recipes"][kind]}

    if Enum.all?(rows, fn {c, r} ->
         CollectionPolicy.valid_constraints?(c) and ManagedRecipe.valid?(r) and
           r["constraints_sha256"] == JSON.digest([c])
       end) do
      {:ok, Map.new(rows, fn {c, _} -> {JSON.digest([c]), c} end),
       Map.new(rows, fn {_, r} -> {JSON.digest([r]), r} end)}
    else
      @error
    end
  end

  defp effects(catalog, sidecar) do
    recipe_shas =
      Enum.map(~w(note pending), &JSON.digest([sidecar["recipes"][&1]])) |> Enum.sort()

    catalog["entries"]
    |> Enum.filter(&(&1["instance"] == "knowledge" and &1["id"] == "capture"))
    |> Enum.flat_map(fn descriptor ->
      outer = JSON.digest([descriptor])

      publish =
        Enum.map(~w(note pending), fn kind ->
          %{
            "operation" => if(kind == "note", do: "notes.capture", else: "notes.propose"),
            "class" => "collection.publish",
            "outer_sha256" => outer,
            "inner_op" => "collection.managed",
            "constraints_sha256" => JSON.digest([sidecar["publication"][kind]]),
            "recipe_sha256" => JSON.digest([sidecar["recipes"][kind]])
          }
        end)

      publish ++
        [
          %{
            "operation" => "notes.recall",
            "class" => "collection.read",
            "outer_sha256" => outer,
            "inner_op" => "collection.call",
            "managed_read" => recipe_shas
          }
        ]
    end)
    |> Enum.sort_by(&{&1["operation"], &1["class"], &1["outer_sha256"], &1["inner_op"]})
  end

  defp empty_options,
    do:
      Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})
      |> Map.put("version", 1)

  defp main_selector,
    do:
      Map.new(~w(processing_region storage_region cache_retention account_controls), &{&1, nil})
      |> Map.merge(%{"operation" => "main", "profile" => nil})

  defp admit_project(home, cwd) do
    with {:ok, existing} <- ProjectIdentity.existing(home, cwd) do
      if existing do
        {:ok, existing}
      else
        with {:ok, candidate} <- ProjectIdentity.preview(home, cwd),
             {:ok, scope} <- scope_choice(candidate),
             do: ProjectIdentity.admit(home, cwd, scope)
      end
    end
  end

  defp scope_choice(%{"kind" => kind, "root" => root})
       when kind in ~w(primary_repository folder) do
    code = code()
    choices = if kind == "primary_repository", do: ["repository", "folder"], else: ["folder"]

    display =
      "Choose the knowledge identity for #{root}.\nRepository shares only with reciprocally verified worktrees; folder means only this canonical folder.\nType one exact choice: " <>
        Enum.map_join(choices, " or ", &(&1 <> " " <> code)) <> "\n> "

    with {:ok, text} <- observe(display),
         [scope, ^code] <- String.split(text, " "),
         true <- scope in choices do
      {:ok, if(scope == "repository", do: :repository, else: :folder)}
    else
      _ -> {:error, :knowledge_setup_cancelled}
    end
  end

  defp scope_choice(_), do: {:error, :knowledge_primary_admission_required}

  defp current_snapshot(home, project),
    do: Consent.snapshot(SemanticAdmission.control_root(home), project)

  defp confirm(action, display) do
    code = code()

    with {:ok, text} <-
           observe(
             display <>
               "\nType #{action} #{code} to confirm this exact review, or anything else to cancel.\n> "
           ),
         true <- text == action <> " " <> code do
      :ok
    else
      _ -> {:error, :knowledge_setup_cancelled}
    end
  end

  defp observe(display) do
    display = Terminal.escape(display)

    with {:ok, observation} <- Ipse.Runner.operator_input(display, 120_000, 2),
         true <- observation["display_sha256"] == JSON.sha256(display),
         true <- observation["text_sha256"] == JSON.sha256(observation["text"]) do
      {:ok, observation["text"]}
    else
      _ -> {:error, :knowledge_requires_native_terminal}
    end
  end

  defp review(binding, policy) do
    "Enable native notes for #{binding["root"]} (#{binding["scope"]}).\n" <>
      "This selection takes effect in the next new session, including headless run.\n" <>
      "Literal native observations may become notes; unattended and assistant claims remain pending.\n" <>
      "Ordinary notes: 90 days; pending proposals: 7 days. Current/preferences may persist.\n" <>
      "No secondary model calls are authorized. Ordinary tool approvals remain separate.\n" <>
      "Exact permission, route, retention, artifact and daily limits:\n" <>
      Jason.encode!(policy, pretty: true)
  end

  defp private_home(home) do
    with true <- is_binary(home) and Path.type(home) == :absolute,
         {:ok, uid} <- Ipse.Runner.protected_current_uid() do
      case File.lstat(home) do
        {:error, :enoent} ->
          with :ok <- File.mkdir(home), do: File.chmod(home, 0o700)

        {:ok, %{type: :directory, uid: ^uid, mode: mode}} ->
          if Bitwise.band(mode, 0o077) == 0, do: :ok, else: @error

        _ ->
          @error
      end
    else
      _ -> @error
    end
  end

  defp code, do: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

  defp fail(reason) do
    detail =
      case reason do
        :knowledge_setup_cancelled ->
          "Review cancelled; no new permission was saved."

        value when value in [:knowledge_requires_native_terminal, :operator_input_unavailable] ->
          "A matching native input and display terminal is required."

        :unsupported_knowledge_options ->
          "Use the saved provider configuration and native confirmation; these options are unsupported."

        :unknown_knowledge_command ->
          "Use knowledge enable, status, permissions or disable."

        :knowledge_primary_admission_required ->
          "Admit the primary repository first, then start a new session in the linked worktree."

        :consent_conflict ->
          "Permission changed during review. Inspect knowledge permissions and begin a fresh review."

        value
        when value in [
               :knowledge_setup_refused,
               :extension_activation_refused,
               :project_identity_unavailable,
               :consent_unavailable
             ] ->
          "Protected selection, project identity or consent could not be verified. Inspect the saved configuration and retained locks; preserve protected state for diagnosis."

        :knowledge_setup_unconfirmed ->
          "The permission outcome is unconfirmed. Inspect saved permissions before retrying."

        _ ->
          Ipse.CLI.Errors.format(reason)
      end

    Terminal.puts(
      :stderr,
      "Knowledge command refused. " <> detail <> " No successful permission change is confirmed."
    )

    1
  end
end
