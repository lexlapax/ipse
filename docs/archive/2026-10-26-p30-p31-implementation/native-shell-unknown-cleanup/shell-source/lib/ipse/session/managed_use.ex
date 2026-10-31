defmodule Ipse.Session.ManagedUse do
  @moduledoc """
  Current authority for host-admitted managed dependencies during a use callback.

  Historical receipts identify what to revalidate, never permission to send.
  Source ownership is acquired outside Identity/Consent; the final protected
  observation must reproduce the provisional records before entering the caller.
  The caller must put the actual send or bounded publication inside the callback.
  """
  alias Ipse.{JSON, Journal.Writer}

  alias Ipse.Extension.{
    Collection.ObservedRead,
    Consent,
    ManagedRecipe,
    Mode,
    ProjectIdentity,
    SemanticAdmission,
    SemanticConsent
  }

  alias Ipse.Session.{ManagedReference, StoredSources}
  @error {:error, :managed_dependency_unavailable}
  @max_sources 128

  def with_dependencies(_context, [], fun) when is_function(fun, 1), do: fun.([])

  def with_dependencies(context, dependencies, fun) when is_function(fun, 1) do
    with {:ok, ^dependencies} <- ManagedReference.union([dependencies]),
         true <- bounded?(dependencies),
         true <- Enum.all?(dependencies, &bound?(&1, context)),
         {:ok, first} <-
           protected(context, dependencies, fn cap, catalog, _ ->
             observe(context, dependencies, cap, catalog)
           end),
         true <- length(first.proofs) <= @max_sources do
      use = fn _ ->
        protected(context, dependencies, fn cap, catalog, policy ->
          checked_observation(
            use_deadline(policy, first.current),
            fn ->
              with {:ok, ^first} <- observe(context, dependencies, cap, catalog),
                   true <-
                     Enum.all?(Enum.zip(dependencies, first.current), fn {old, current} ->
                       ManagedReference.current?(old, current, System.system_time(:millisecond))
                     end) do
                {:ok, first.current}
              else
                _ -> @error
              end
            end,
            fun
          )
        end)
      end

      if first.proofs == [],
        do: use.([]),
        else: StoredSources.with_verified(context, nil, first.proofs, use)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  @doc "Historical preflight verdicts; actual use must acquire authority again."
  def verdicts(_context, []), do: []

  def verdicts(context, dependencies) do
    with {:ok, ^dependencies} <- ManagedReference.union([dependencies]),
         true <- bounded?(dependencies),
         true <- Enum.all?(dependencies, &bound?(&1, context)),
         {:ok, first} <-
           protected(context, dependencies, fn cap, catalog, _ ->
             observe_all(context, dependencies, cap, catalog)
           end),
         proofs =
           first
           |> Map.values()
           |> Enum.flat_map(fn
             {:ok, _, proofs} -> proofs
             _ -> []
           end)
           |> Enum.uniq(),
         true <- length(proofs) <= @max_sources,
         {:ok, statuses} <-
           if(proofs == [], do: {:ok, %{}}, else: StoredSources.snapshot(context, proofs)),
         {:ok, verdicts} <-
           protected(context, dependencies, fn cap, catalog, policy ->
             checked_observation(
               policy,
               fn -> observe_all(context, dependencies, cap, catalog) end,
               fn second ->
                 now = System.system_time(:millisecond)

                 {:ok,
                  Enum.map(dependencies, fn dependency ->
                    id = JSON.digest([dependency])

                    result =
                      with {:ok, prior, proofs} <- first[id],
                           {:ok, current, ^proofs} <- second[id],
                           true <- Enum.all?(proofs, &(statuses[JSON.digest([&1])] === true)),
                           true <- ManagedReference.current?(prior, current, now),
                           true <- ManagedReference.current?(dependency, current, now),
                           do: {:ok, current}

                    verdict(dependency, result)
                  end)}
               end
             )
           end) do
      verdicts
    else
      _ -> Enum.map(dependencies, &verdict(&1, @error))
    end
  rescue
    _ -> Enum.map(dependencies, &verdict(&1, @error))
  end

  @doc false
  def checked_observation(policy, observe, use)
      when is_function(observe, 0) and is_function(use, 1) do
    with {:ok, current} <- observe.(),
         deadline when is_integer(deadline) <- policy["expires_at_ms"],
         true <- System.system_time(:millisecond) < deadline do
      use.(current)
    else
      _ -> @error
    end
  end

  defp use_deadline(policy, dependencies) do
    deadline =
      Enum.reduce(dependencies, policy["expires_at_ms"], fn dependency, deadline ->
        case get_in(dependency, ["subject", "validity", "valid_until_ms"]) do
          value when is_integer(value) -> min(value, deadline)
          _ -> deadline
        end
      end)

    Map.put(policy, "expires_at_ms", deadline)
  end

  defp verdict(dependency, {:ok, current}),
    do: %{
      "dependency_sha256" => JSON.digest([dependency]),
      "status" => "eligible",
      "current" => current
    }

  defp verdict(dependency, _),
    do: %{
      "dependency_sha256" => JSON.digest([dependency]),
      "status" => "unavailable",
      "current" => nil
    }

  defp bounded?(dependencies) do
    records =
      for %{"version" => 4, "subject" => subject} <- dependencies,
          do: {subject["key"], get_in(subject, ["validity", "recipe_sha256"])}

    length(dependencies) <= 2048 and length(Enum.uniq(records)) <= @max_sources
  end

  @doc false
  def sources(s, caller, binding, proofs) do
    with %{pid: worker} <- s.task,
         true <- caller == worker or Ipse.Session.Resources.authorized_effect?(worker, caller),
         true <- binding_current?(s, binding),
         true <- is_list(proofs) and length(proofs) in 1..@max_sources,
         true <- Enum.all?(proofs, &(is_map(&1) and &1["session_id"] == s.id)),
         {:ok, origin} when is_map(origin) <- Writer.source_query(s.journal_writer, :origin) do
      result =
        Enum.reduce_while(proofs, {:ok, []}, fn proof, {:ok, acc} ->
          case Writer.source_query(s.journal_writer, {:stored_proof, proof}) do
            {:ok, checked} -> {:cont, {:ok, acc ++ [checked]}}
            _ -> {:halt, @error}
          end
        end)

      result
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp binding_current?(s, {:snapshot, phase, sha}) do
    case Ipse.Session.managed_dependencies(s, phase) do
      {:ok, %{sha256: ^sha}} -> true
      _ -> false
    end
  end

  defp binding_current?(s, {:inference, phase, expected}),
    do: Ipse.Session.InferenceDispatch.binding_current?(s, phase, expected)

  defp binding_current?(_, _), do: false

  defp bound?(dependency, c) do
    pin = c.config[:semantic_admission]["pin"]

    dependency["version"] in [3, 4] and
      dependency["namespace"] == pin["namespace"] and
      dependency["project_id"] == pin["project_id"] and
      dependency["policy_generation"] === pin["epoch"] and
      dependency["pin_sha256"] == JSON.digest([pin])
  end

  defp protected(c, dependencies, fun) do
    admission = c.config[:semantic_admission]
    pin = admission["pin"]

    callback = fn cap, catalog ->
      Consent.with_policy(
        SemanticAdmission.control_root(c.config[:home]),
        pin["project_id"],
        pin["epoch"],
        pin["policy_sha256"],
        System.system_time(:millisecond),
        fn snapshot ->
          with {:ok, _} <- SemanticAdmission.context(c.config, c.session_id, 0),
               {:ok, mode} <- Mode.capture(c.config),
               :ok <- Mode.knowledge(mode, "collection.read"),
               true <- not mode["headless"] or snapshot["policy"]["headless"] do
            {:ok, fun.(cap, catalog, snapshot["policy"])}
          else
            _ -> @error
          end
        end
      )
    end

    result =
      if Enum.any?(dependencies, &(&1["version"] == 4)) do
        ProjectIdentity.with_existing_domain_auth(
          c.config[:home],
          c.cwd,
          admission["binding"],
          %{namespace: pin["namespace"], format: "managed-metadata-v3"},
          callback
        )
      else
        ProjectIdentity.with_binding(c.config[:home], c.cwd, admission["binding"], fn _ ->
          callback.(nil, nil)
        end)
      end

    # Consent's read callback carries a pair; the owned-use callback may return
    # an opaque transport continuation result. Preserve it only after cleanup.
    case result do
      {:ok, value} -> value
      other -> other
    end
  end

  defp observe(c, dependencies, cap, catalog) do
    with {:ok, results} <- observe_all(c, dependencies, cap, catalog) do
      Enum.reduce_while(dependencies, {:ok, %{current: [], proofs: []}}, fn dependency,
                                                                            {:ok, acc} ->
        case results[JSON.digest([dependency])] do
          {:ok, current, proofs} ->
            {:cont,
             {:ok, %{current: acc.current ++ [current], proofs: Enum.uniq(acc.proofs ++ proofs)}}}

          _ ->
            {:halt, @error}
        end
      end)
    end
  end

  defp observe_all(c, dependencies, cap, catalog) do
    pin = c.config[:semantic_admission]["pin"]
    root = SemanticAdmission.collection_root(c.config[:home])

    {results, _} =
      Enum.reduce(dependencies, {%{}, %{}}, fn dependency, {results, cache} ->
        key =
          if dependency["version"] == 3,
            do: :root,
            else:
              {dependency["subject"]["key"],
               get_in(dependency, ["subject", "validity", "recipe_sha256"])}

        result =
          Map.get_lazy(cache, key, fn ->
            if key == :root,
              do: observe_root(root, pin),
              else: observe_dependency(c, root, pin, dependency, cap, catalog)
          end)

        checked =
          if key == :root do
            with {:ok, actual} <- result,
                 true <- actual === dependency["collection"],
                 do: {:ok, dependency, []}
          else
            result
          end

        {Map.put(results, JSON.digest([dependency]), checked), Map.put(cache, key, result)}
      end)

    {:ok, results}
  end

  defp observe_root(root, pin) do
    request = %{"op" => "snapshot"}

    with {:ok, observation} <- ObservedRead.read(root, pin["namespace"], request),
         {:ok, current} <- ObservedRead.root_dependency(request, observation, pin) do
      {:ok, current["collection"]}
    else
      _ -> @error
    end
  end

  defp observe_dependency(c, root, pin, %{"version" => 4} = dependency, cap, catalog) do
    settings = c.config[:semantic_admission]["policy"]["settings"]
    recipe_sha = get_in(dependency, ["subject", "validity", "recipe_sha256"])
    recipe = settings["recipes"][recipe_sha]
    request = %{"op" => "get_record", "key" => dependency["subject"]["key"]}

    with true <- ManagedRecipe.valid?(recipe) and JSON.digest([recipe]) == recipe_sha,
         true <- Enum.any?(settings["effects"], &(recipe_sha in Map.get(&1, "managed_read", []))),
         {:ok, managed} <-
           ObservedRead.managed_record(root, pin["namespace"], request, cap, catalog, recipe),
         value = managed["observation"]["value"]["record"]["value"],
         proofs when is_list(proofs) <-
           Enum.reduce(recipe["evidence_path"], value, fn key, value ->
             if is_map(value), do: value[key], else: nil
           end),
         :ok <-
           SemanticConsent.check_sources(
             c.config[:semantic_admission]["policy"],
             Enum.map(proofs, &%{"category" => &1["origin"], "path" => &1["path"]})
           ),
         {:ok, current} <-
           ObservedRead.managed_dependency(
             request,
             managed,
             pin,
             recipe,
             proofs,
             System.system_time(:millisecond)
           ) do
      {:ok, current, proofs}
    else
      _ -> @error
    end
  end
end
