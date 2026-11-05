defmodule Ipse.CLI.Knowledge do
  @moduledoc "Standalone native review of protected knowledge permission; no worker or inference is started."
  alias Ipse.CLI.Terminal

  alias Ipse.Extension.{
    Activation,
    Artifact,
    Bundles,
    Catalog,
    Collection,
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
          value when value in ~w(enable setup) ->
            enable(config, cwd, fn -> runtime(opts, home, cwd) end)

          "disable" ->
            disable(config, cwd)

          _ ->
            status(config, cwd, command, opts[:json] == true)
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

  def run("review", opts, home, cwd) do
    with true <- Enum.all?(Keyword.keys(opts), &(&1 in (@options ++ [:after]))),
         {:ok, cwd} <- Ipse.Workspace.canonical_path(cwd),
         {:ok, config} <- runtime(Keyword.delete(opts, :after), home, cwd),
         {:ok, index} <- Ipse.CLI.Knowledge.Management.pending_metadata(config, cwd, opts[:after]) do
      unless opts[:json],
        do:
          Terminal.puts(
            "Historical pending keys only; source eligibility and signed deadlines are not checked. Use knowledge review PENDING_KEY for native review."
          )

      Terminal.puts(Jason.encode!(index, pretty: opts[:json] != true))
      0
    else
      _ -> fail(:knowledge_management_refused)
    end
  end

  def run(_, _, _, _), do: fail(:unknown_knowledge_command)

  def run_experiment(profile, calls_text, seconds_text, opts, home, cwd) do
    with true <-
           Enum.all?(Keyword.keys(opts), &(&1 in (@options ++ [:helper_profile]))) and
             opts[:json] != true,
         true <- length(Keyword.get_values(opts, :helper_profile)) <= 1,
         helper = opts[:helper_profile],
         true <- helper_profile?(helper),
         runtime_opts = Keyword.delete(opts, :helper_profile),
         {calls, ""} when calls in 1..100 <- Integer.parse(calls_text),
         {seconds, ""} when seconds in 1..1800 <- Integer.parse(seconds_text),
         {:ok, cwd} <- Ipse.Workspace.canonical_path(cwd),
         {:ok, :native} <- Ipse.Runner.operator_channel(),
         {:ok, config} <- runtime(runtime_opts, home, cwd),
         :ok <- private_home(config.home),
         {:ok, binding} <- admit_project(config.home, cwd),
         {:ok, artifact} <- Bundles.install("knowledge-decision-shadow", config.home),
         now = System.system_time(:millisecond),
         {:ok, proposal} <-
           prepare_experiment(
             config,
             binding,
             artifact.digest,
             now,
             profile,
             calls,
             seconds,
             helper
           ),
         {:ok, before} <- current_snapshot(config.home, binding["project_id"]),
         :ok <- confirm("experiment", experiment_review(binding, proposal.policy)),
         {:ok, _} <-
           ProjectIdentity.with_binding(config.home, cwd, binding, fn _ ->
             with {:ok, current} <-
                    refresh_configuration(config, fn -> runtime(runtime_opts, home, cwd) end),
                  {:ok, repeated} <-
                    prepare_experiment(
                      current,
                      binding,
                      artifact.digest,
                      now,
                      profile,
                      calls,
                      seconds,
                      helper
                    ),
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
      Terminal.puts("Saved finite shadow experiment permission. Start a new Session to use it.")
      0
    else
      {:error, reason} -> fail(reason)
      _ -> fail(:knowledge_setup_refused)
    end
  rescue
    _ -> fail(:knowledge_setup_refused)
  end

  def run_correction(key, text, opts, home, cwd) do
    with true <-
           Enum.all?(Keyword.keys(opts), &(&1 in (@options ++ [:state_dir]))) and
             opts[:json] != true,
         {:ok, cwd} <- Ipse.Workspace.canonical_path(cwd),
         {:ok, config} <- runtime(Keyword.delete(opts, :state_dir), home, cwd) do
      history_dir = Path.expand(opts[:state_dir] || Path.join(home, "sessions"))

      case Ipse.CLI.Knowledge.Correction.run(config, cwd, history_dir, key, text) do
        {:ok, result} ->
          Terminal.puts(
            "Saved the corrected pending proposal; review its new key separately for acceptance. Original provenance and expiry remain."
          )

          Terminal.puts(Jason.encode!(result))
          0

        result ->
          Terminal.puts(
            :stderr,
            "No successful pending correction is confirmed: #{inspect(result)}. Inspect the management journal and actual storage before new work; unknown effects never replay."
          )

          1
      end
    else
      _ ->
        Terminal.puts(
          :stderr,
          "Use knowledge correct PENDING_KEY 'NEW TEXT' in a native terminal with the saved configuration and original sessions directory; provider overrides, --yes and --json are unsupported."
        )

        1
    end
  end

  def run_batch(keys, opts, home, cwd) do
    with true <- Ipse.Session.PendingBatch.keys?(keys),
         true <-
           Enum.all?(Keyword.keys(opts), &(&1 in (@options ++ [:state_dir]))) and
             opts[:json] != true,
         {:ok, cwd} <- Ipse.Workspace.canonical_path(cwd),
         {:ok, config} <- runtime(Keyword.delete(opts, :state_dir), home, cwd) do
      history_dir = Path.expand(opts[:state_dir] || Path.join(home, "sessions"))

      case Ipse.CLI.Knowledge.Batch.run(config, cwd, history_dir, keys) do
        {:ok, result} ->
          Terminal.puts(Jason.encode!(result))
          0

        result ->
          Terminal.puts(
            :stderr,
            "Batch review stopped: #{inspect(result)}. Earlier confirmed items remain saved. Keep printed journal/reservation IDs, inspect uncertain outcomes, and begin fresh review for remaining candidates; nothing is replayed."
          )

          1
      end
    else
      _ ->
        Terminal.puts(
          :stderr,
          "Select two to eight distinct pending keys for knowledge review KEY KEY [...]. A manifest over 8 KiB refuses; native per-item acceptance is required. Provider overrides, --yes and --json are unsupported."
        )

        1
    end
  end

  def run_target("defer", key, opts, home, cwd) do
    with true <- Enum.all?(Keyword.keys(opts), &(&1 in @options)),
         {:ok, cwd} <- Ipse.Workspace.canonical_path(cwd),
         {:ok, config} <- runtime(opts, home, cwd),
         {:ok, result} <- Ipse.CLI.Knowledge.Management.defer(config, cwd, key) do
      unless opts[:json] do
        Terminal.puts(
          if(result["status"] == "expired",
            do: "This proposal has expired; deferral cannot renew it. Nothing was changed.",
            else:
              "Left this proposal pending for later review. Its original expiry is unchanged; acceptance requires fresh native review."
          )
        )
      end

      Terminal.puts(Jason.encode!(result, pretty: opts[:json] != true))
      0
    else
      _ -> fail(:knowledge_management_refused)
    end
  end

  def run_target("review", key, opts, home, cwd) do
    with true <-
           Enum.all?(Keyword.keys(opts), &(&1 in (@options ++ [:state_dir]))) and
             opts[:json] != true,
         {:ok, cwd} <- Ipse.Workspace.canonical_path(cwd),
         {:ok, config} <- runtime(Keyword.delete(opts, :state_dir), home, cwd) do
      history_dir = Path.expand(opts[:state_dir] || Path.join(home, "sessions"))

      case Ipse.CLI.Knowledge.Management.review(config, cwd, history_dir, key) do
        {:ok, result} ->
          Terminal.puts(
            "Accepted the selected proposal as your decision; original provenance remains."
          )

          Terminal.puts(Jason.encode!(result))
          0

        result ->
          Terminal.puts(
            :stderr,
            "No successful acceptance is confirmed: #{inspect(result)}. Inspect the management journal and stored state before new work; unknown effects never replay."
          )

          1
      end
    else
      _ ->
        Terminal.puts(
          :stderr,
          "Use knowledge review PENDING_KEY in a native terminal with the saved configuration. Select the original --state-dir when needed; provider overrides, --yes and --json are unsupported."
        )

        1
    end
  end

  def run_target("forget", key, opts, home, cwd) do
    with true <- Enum.all?(Keyword.keys(opts), &(&1 in @options)) and opts[:json] != true,
         {:ok, cwd} <- Ipse.Workspace.canonical_path(cwd),
         {:ok, config} <- runtime(opts, home, cwd) do
      case Ipse.CLI.Knowledge.Management.forget(config, cwd, key) do
        {:error, :native_review_publication_fence_unavailable} ->
          Terminal.puts(
            :stderr,
            Ipse.CLI.Errors.format(:native_review_publication_fence_unavailable)
          )

          1

        {:ok, result} ->
          Terminal.puts("Forgot the selected note; signed suppression remains.")
          Terminal.puts(Jason.encode!(result))
          0

        other ->
          Terminal.puts(
            :stderr,
            "No successful forget is confirmed: #{inspect(other)}. Inspect the management journal and protected operation before retrying; unknown effects never replay."
          )

          1
      end
    else
      _ ->
        Terminal.puts(
          :stderr,
          "Use knowledge forget NOTE_KEY from a native terminal with the saved configuration; provider overrides, --yes and --json are unsupported."
        )

        1
    end
  end

  def run_target("reject", key, opts, home, cwd) do
    with true <- Enum.all?(Keyword.keys(opts), &(&1 in @options)) and opts[:json] != true,
         {:ok, cwd} <- Ipse.Workspace.canonical_path(cwd),
         {:ok, config} <- runtime(opts, home, cwd) do
      case Ipse.CLI.Knowledge.Management.reject(config, cwd, key) do
        {:ok, result} ->
          Terminal.puts("Rejected the selected proposal; exact candidate suppression remains.")
          Terminal.puts(Jason.encode!(result))
          0

        result ->
          Terminal.puts(
            :stderr,
            "No successful rejection is confirmed: #{inspect(result)}. Inspect the management journal and stored state before new work; unknown effects never replay."
          )

          1
      end
    else
      _ ->
        Terminal.puts(
          :stderr,
          "Use knowledge reject PENDING_KEY in a native terminal with the saved configuration; provider overrides, --yes and --json are unsupported."
        )

        1
    end
  end

  def run_target("retention", key, opts, home, cwd) do
    with true <-
           Enum.all?(Keyword.keys(opts), &(&1 in (@options ++ [:policy, :days]))) and
             opts[:json] != true,
         {:ok, policy} <- retention_policy(opts),
         {:ok, cwd} <- Ipse.Workspace.canonical_path(cwd),
         {:ok, config} <- runtime(Keyword.drop(opts, [:policy, :days]), home, cwd) do
      case Ipse.CLI.Knowledge.Management.retain(config, cwd, key, policy) do
        {:error, :native_review_publication_fence_unavailable} ->
          Terminal.puts(
            :stderr,
            Ipse.CLI.Errors.format(:native_review_publication_fence_unavailable)
          )

          1

        {:error, :collection_deadline_fence_unavailable} ->
          Terminal.puts(:stderr, Ipse.CLI.Errors.format(:collection_deadline_fence_unavailable))
          1

        {:ok, result} ->
          Terminal.puts(
            if(policy["kind"] == "session",
              do: "Removed the reviewed stored note for session-only retention.",
              else: "Saved the exact reviewed retention choice; original admission clocks remain."
            )
          )

          Terminal.puts(Jason.encode!(result))
          0

        other ->
          Terminal.puts(
            :stderr,
            "No successful retention change is confirmed: #{inspect(other)}. Inspect the management operation before retrying; unknown effects never replay."
          )

          1
      end
    else
      _ ->
        Terminal.puts(
          :stderr,
          "Use knowledge retention NOTE_KEY --policy automatic|pin|session, or --policy duration --days POSITIVE_DAYS, in a native terminal. Provider overrides, --yes and --json are unsupported."
        )

        1
    end
  end

  def run_target("expire", key, opts, home, cwd) do
    with true <- Enum.all?(Keyword.keys(opts), &(&1 in @options)) and opts[:json] != true,
         {:ok, cwd} <- Ipse.Workspace.canonical_path(cwd),
         {:ok, config} <- runtime(opts, home, cwd) do
      case Ipse.CLI.Knowledge.Management.expire(config, cwd, key) do
        {:ok, result} ->
          Terminal.puts(
            "Reclaimed the selected expired note or history; original admission clocks remain."
          )

          Terminal.puts(Jason.encode!(result))
          0

        other ->
          Terminal.puts(
            :stderr,
            "No successful expiry reclamation is confirmed: #{inspect(other)}. Inspect the management operation before retrying; unknown effects never replay."
          )

          1
      end
    else
      _ ->
        Terminal.puts(
          :stderr,
          "Use knowledge expire NOTE_KEY for an already expired signed ordinary note or history in a native terminal. Provider overrides, --yes and --json are unsupported."
        )

        1
    end
  end

  def run_target("operation", id, opts, home, cwd) do
    with true <- Enum.all?(Keyword.keys(opts), &(&1 in @options)),
         {:ok, cwd} <- Ipse.Workspace.canonical_path(cwd),
         {:ok, config} <- runtime(opts, home, cwd),
         {:ok, result} <- Ipse.CLI.Knowledge.Management.operation(config, cwd, id) do
      Terminal.puts(Jason.encode!(result, pretty: true))
      0
    else
      _ ->
        Terminal.puts(
          :stderr,
          "Management operation unavailable for this project. Preserve the original management journal and protected state; no action was replayed."
        )

        1
    end
  end

  def run_target(_, _, _, _, _), do: fail(:unknown_knowledge_command)

  defp retention_policy(opts) do
    case {opts[:policy], opts[:days]} do
      {kind, days} when kind in ["automatic", "ordinary"] and days in [nil, 90] ->
        {:ok, %{"kind" => "ordinary"}}

      {"duration", days} when is_integer(days) and days > 0 ->
        duration = days * @day

        if JSON.safe_uint?(duration),
          do: {:ok, %{"kind" => "duration", "duration_ms" => duration}},
          else: @error

      {kind, nil} when kind in ["pin", "session"] ->
        {:ok, %{"kind" => kind}}

      _ ->
        @error
    end
  end

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
      publication = Collection.publication_support()

      value = %{
        "activation_ready_now" => Map.get(current, :ready),
        "publication_supported_now" => publication["supported"],
        "capture_ready_now" => Map.get(current, :ready) == true and publication["supported"],
        "publication_unavailable_reason" => publication["reason"],
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
              if publication["supported"] do
                "Saved knowledge selection is ready for the next new session."
              else
                "Saved knowledge selection matches the next new session."
              end

            is_nil(current.binding) ->
              "This folder is not admitted. A new session can join a reciprocally verified worktree when its existing repository grant permits it."

            true ->
              "No ready knowledge selection is saved for this folder."
          end
        )

        Terminal.puts(
          "Existing sessions retain their catalog and check current permission before each effect."
        )

        unless publication["supported"], do: Terminal.puts(publication_notice())
      end

      :ok
    end
  end

  defp enable(config, cwd, refresh) do
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
             with {:ok, current} <- refresh_configuration(config, refresh),
                  {:ok, repeated} <- prepare(current, binding, artifact.digest, now),
                  true <- repeated === proposal do
               Consent.replace(
                 SemanticAdmission.control_root(config.home),
                 binding["project_id"],
                 before["epoch"],
                 proposal.policy,
                 System.system_time(:millisecond)
               )
             else
               {:error, :knowledge_configuration_changed} = error -> error
               _ -> @error
             end
           end) do
      Terminal.puts(
        "Saved knowledge permission. Start a new chat or run to adopt this selection."
      )

      unless Collection.publication_support()["supported"],
        do: Terminal.puts(publication_notice())

      :ok
    else
      {:ok, :pipe} -> {:error, :knowledge_requires_native_terminal}
      {:error, _} = error -> error
      _ -> @error
    end
  end

  defp refresh_configuration(original, refresh) do
    with {:ok, current} <- refresh.(),
         true <- current.configuration.fingerprint === original.configuration.fingerprint do
      {:ok, current}
    else
      _ -> {:error, :knowledge_configuration_changed}
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
  def prepare(config, binding, digest, now),
    do: prepare_selection(config, binding, digest, now, nil)

  @doc "Prepare a finite local shadow experiment; this does not grant permission."
  def prepare_experiment(config, binding, digest, now, "advice", calls)
      when is_integer(calls) and calls in 1..100,
      do: prepare_experiment(config, binding, digest, now, "advice", calls, 1800, nil)

  def prepare_experiment(_, _, _, _, _, _), do: @error

  def prepare_experiment(config, binding, digest, now, "advice", calls, seconds)
      when is_integer(calls) and calls in 1..100 and
             is_integer(seconds) and seconds in 1..1800,
      do: prepare_experiment(config, binding, digest, now, "advice", calls, seconds, nil)

  def prepare_experiment(_, _, _, _, _, _, _), do: @error

  def prepare_experiment(config, binding, digest, now, "advice", calls, seconds, helper)
      when is_integer(calls) and calls in 1..100 and
             is_integer(seconds) and seconds in 1..1800 do
    if helper_profile?(helper) do
      prepare_selection(config, binding, digest, now, %{
        profile: "advice",
        calls: calls,
        seconds: seconds,
        helper_profile: helper
      })
    else
      @error
    end
  end

  def prepare_experiment(_, _, _, _, _, _, _, _), do: @error

  defp prepare_selection(config, binding, digest, now, experiment) do
    with true <- JSON.safe_uint?(now),
         {:ok, bundled} <- Bundles.inventory(),
         bundle_id = if(experiment, do: "knowledge-decision-shadow", else: "knowledge"),
         true <- Enum.any?(bundled, &(&1.id == bundle_id and &1.digest == digest)),
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
             sidecar["preset"] == if(experiment, do: "decision-shadow", else: "native"),
         true <- artifact.manifest["id"] == "ipse-knowledge/knowledge",
         true <- is_nil(experiment) or "host.decision" in artifact.manifest["capabilities"],
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
         selectors =
           if(experiment,
             do:
               [decision_selector(experiment.profile), main_selector()] ++
                 helper_selectors(experiment.helper_profile),
             else: [main_selector()]
           ),
         {:ok, reviewed} <- SemanticRoutes.review(selected, selectors),
         true <- is_nil(experiment) or local_decision_route?(reviewed.routes, experiment.profile),
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
                 ~w(interactive_operator native_operator_answer native_operator_assertion typed_host_outcome unattended_input assistant_proposal)
               ),
             "exclusions" => []
           },
           "storage" => %{"kind" => "local_collection", "collection" => "knowledge"},
           "retention" => %{"automatic" => 90, "manual" => 3650},
           "routes" => reviewed.routes,
           "effects" => effects(catalog, sidecar, experiment),
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
           "expires_at_ms" =>
             if(experiment,
               do: min(now + experiment.seconds * 1000, (div(now, @day) + 1) * @day),
               else: now + 365 * @day
             ),
           "headless" => true
         },
         selection = experiment_selection(selection, experiment, now),
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

  defp effects(catalog, sidecar, experiment) do
    recipe_shas =
      Enum.map(~w(note pending), &JSON.digest([sidecar["recipes"][&1]])) |> Enum.sort()

    catalog["entries"]
    |> Enum.filter(fn descriptor ->
      descriptor["instance"] == "knowledge" and
        ((descriptor["stage"] in ["invoke.tool", "invoke.command"] and
            descriptor["id"] == "capture") or
           (descriptor["stage"] == "invoke.tool" and
              (descriptor["id"] in ~w(index read search) or
                 (not is_nil(experiment) and descriptor["id"] in ~w(assess select_shadow)))) or
           (descriptor["stage"] == "event.job" and descriptor["id"] == "recall"))
    end)
    |> Enum.flat_map(fn descriptor ->
      outer = JSON.digest([descriptor])

      publish =
        if descriptor["id"] == "capture" do
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
        else
          []
        end

      decision =
        if experiment && descriptor["id"] in ~w(assess select_shadow) do
          [
            %{
              "operation" =>
                if(descriptor["id"] == "assess", do: "notes.assess", else: "notes.select"),
              "class" => "decision.create",
              "outer_sha256" => outer,
              "inner_op" => "decision.create"
            }
          ]
        else
          []
        end

      publish ++
        decision ++
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

  defp decision_selector(profile),
    do: Map.put(main_selector(), "operation", "decision.create") |> Map.put("profile", profile)

  defp helper_profile?(nil), do: true

  defp helper_profile?(profile) when is_binary(profile),
    do: Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/, profile)

  defp helper_profile?(_), do: false

  defp helper_selectors(nil), do: []

  defp helper_selectors(profile),
    do: [Map.put(main_selector(), "operation", "model.complete") |> Map.put("profile", profile)]

  defp local_decision_route?(routes, profile),
    do:
      profile == "advice" and
        Enum.any?(
          routes,
          &(&1["operation"] == "decision.create" and &1["profile"] == profile and
              &1["provider"] == "system_one_compatible" and &1["billing_mode"] == "local" and
              Ipse.Extension.DecisionExperiment.numeric_loopback?(&1["endpoint"]))
        )

  defp experiment_selection(selection, nil, _now), do: selection

  defp experiment_selection(selection, experiment, now) do
    selection
    |> Map.put("experiment", %{"version" => 1, "issued_at_ms" => now})
    |> put_in(["limits", "model_calls"], experiment.calls)
    |> update_in(["limits", "operations"], &(&1 + experiment.calls))
    |> update_in(["limits", "output_bytes"], &(&1 + experiment.calls * 65_536))
  end

  defp experiment_review(binding, policy) do
    "Review a finite local shadow experiment for #{binding["root"]}.\n" <>
      "This replaces the current project knowledge permission immediately; existing Sessions " <>
      "lose that permission, and the shadow selection applies to new Sessions. " <>
      "After expiry, run knowledge enable to review and restore ordinary permission. " <>
      "The assess tool reads a previously saved eligible note for shadow advice; " <>
      "capturing a note does not start an assessment. " <>
      "The select_shadow tool compares complete current note packs against the actual context " <>
      "allocation and ordinary recall without changing context or stored notes. Fitting sets " <>
      "make no decision call. Neither experiment qualifies a default strategy. " <>
      "The optional model.complete route requires a separately trusted host.model extension and " <>
      "ordinary per-call native approval. CALLS counts decisions only, not main/helper usage or money. " <>
      "Each decision still needs native approval. Admitted requests may finish after expiry; " <>
      "unknown work retains its full reservation.\n" <> Jason.encode!(policy, pretty: true)
  end

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
      if(Collection.publication_support()["supported"],
        do: "",
        else: publication_notice() <> "\n"
      ) <>
      "Literal notes require a separate native statement/category review or a typed host outcome; other inputs remain pending.\n" <>
      "Ordinary notes: 90 days; pending proposals: 7 days. Current/preferences may persist.\n" <>
      "No secondary model calls are authorized. Ordinary tool approvals remain separate.\n" <>
      "Exact permission, route, retention, artifact and daily limits:\n" <>
      Jason.encode!(policy, pretty: true)
  end

  defp publication_notice,
    do:
      "Broad protected note saving is not ready. A new statement may be saved through separate native review when permission is active; saved permission is retained."

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

        :knowledge_configuration_changed ->
          "Saved configuration changed during review. Inspect the current configuration and begin a fresh review."

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
