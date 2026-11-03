defmodule Ipse.Extension.ManagedRead do
  @moduledoc """
  Current-source admission of managed records returned by protected collection reads.

  The first read only discovers bounded candidates. Source ownership is acquired
  outside Identity/Consent; the final protected read must match that observation
  and authenticate each managed record before any value is returned. This does
  not authorize a later inference or delivery of derived content.
  """
  alias Ipse.Extension.{
    Collection.ObservedRead,
    ManagedRecipe,
    SemanticAdmission,
    SemanticConsent
  }

  alias Ipse.Session.{PendingAcceptance, StoredSources}
  @error {:error, :collection_source_refused}

  def execute(c, i, recipes, protect, admit \\ fn value, _ -> {:ok, value} end) do
    with {:ok, first} <- protect.(false, fn _, _ -> observe(c, i, recipes) end) do
      case first.notes do
        [] ->
          with {:ok, dependency} <- root_dependency(i, first),
               do: admit.(first.observation["value"], [dependency])

        notes ->
          proofs = Enum.flat_map(notes, & &1.proofs) |> Enum.uniq()
          links = for %{kind: :accepted, link: link} <- notes, do: link["value"]
          pin = i["effect_binding"]["pin"]

          case missing_original(c, i, recipes, first, protect) do
            {:error, :collection_original_source_missing} = missing ->
              missing

            _ ->
              PendingAcceptance.with_committed_management_journals(
                c.config[:home],
                pin["project_id"],
                i["namespace"],
                links,
                fn journals ->
                  StoredSources.with_verified(c, i, proofs, fn verified ->
                    protect.(true, fn cap, catalog ->
                      with {:ok, ^first} <- observe(c, i, recipes),
                           {:ok, dependencies} <-
                             authenticate(c, i, notes, first, verified, cap, catalog, journals),
                           {:ok, root} <- root_dependency(i, first) do
                        dependencies =
                          if i["request"]["request"]["op"] == "scan",
                            do: [root | dependencies],
                            else: dependencies

                        admit.(first.observation["value"], dependencies)
                      else
                        _ -> @error
                      end
                    end)
                  end)
                end
              )
          end
      end
    end
  rescue
    _ -> @error
  end

  # This distinct outcome applies only to a single literal record whose one
  # original inactive Session journal is absent under its source lock. The
  # root, signed managed metadata, current source policy and recipe are checked
  # again while that absence is held; no record or dependency is returned.
  defp missing_original(
         c,
         i,
         recipes,
         %{notes: [%{kind: :literal, proofs: [proof]} = note]} = first,
         protect
       ) do
    if i["request"]["request"]["op"] == "get" do
      StoredSources.with_missing_original(c, proof, fn ->
        protect.(true, fn cap, catalog ->
          with {:ok, ^first} <- observe(c, i, recipes),
               {:ok, _} <-
                 authenticate_record(c, i, note, first, [%{"proof" => proof}], cap, catalog, %{}) do
            {:error, :collection_original_source_missing}
          else
            _ -> @error
          end
        end)
      end)
    else
      @error
    end
  end

  defp missing_original(_, _, _, _, _), do: @error

  defp observe(c, i, recipes) do
    request = i["request"]["request"]

    observed =
      if request["op"] == "index",
        do: Ipse.Extension.CollectionCall.index_observation(c, i),
        else: ObservedRead.read(root(c), i["namespace"], request)

    with {:ok, observation} <- observed,
         {:ok, value} <- bound(i, observation["value"]),
         observation = %{
           observation
           | "value" => value,
             "result_sha256" => Ipse.JSON.digest([value])
         },
         {:ok, notes} <-
           if(request["op"] == "index",
             do: {:ok, []},
             else: select_notes(observation["value"], recipes)
           ),
         {:ok, notes} <- acceptance_links(c, i, observation, notes) do
      {:ok, %{observation: observation, notes: notes}}
    end
  end

  defp select_notes(value, recipes) do
    records =
      if Map.has_key?(value, "records"), do: value["records"], else: List.wrap(value["record"])

    if Enum.any?(records, &match?(%{"value" => %{"kind" => "candidate_acceptance_link"}}, &1)) do
      @error
    else
      select_records(records, recipes)
    end
  end

  defp select_records(records, recipes) do
    Enum.reduce_while(records, {:ok, []}, fn record, {:ok, acc} ->
      selected =
        Enum.filter(
          recipes,
          &(&1["kind"] == "literal_source" and
              String.starts_with?(record["key"], &1["key_prefix"]))
        )

      case selected do
        [] ->
          if match?(%{"value" => %{"kind" => "accepted_decision"}}, record),
            do: {:halt, @error},
            else: {:cont, {:ok, acc}}

        [recipe] ->
          accepted? = match?(%{"value" => %{"kind" => "accepted_decision"}}, record)

          proofs =
            if accepted?,
              do: [record["value"]["source_proof"]],
              else:
                Enum.reduce(recipe["evidence_path"], record["value"], fn key, value ->
                  if is_map(value), do: value[key], else: nil
                end)

          if is_list(proofs) and length(proofs) in 1..8 and
               Enum.all?(proofs, &match?({:ok, _}, ManagedRecipe.source_identity(&1))) do
            {:cont,
             {:ok,
              acc ++
                [
                  %{
                    kind: if(accepted?, do: :accepted, else: :literal),
                    record: record,
                    recipe: recipe,
                    proofs: proofs,
                    link: nil
                  }
                ]}}
          else
            {:halt, @error}
          end

        _ ->
          {:halt, @error}
      end
    end)
  end

  defp acceptance_links(c, i, observation, notes) do
    Enum.reduce_while(notes, {:ok, []}, fn note, {:ok, acc} ->
      if note.kind == :accepted do
        id = note.record["value"]["candidate_id"]

        with true <- Ipse.JSON.sha256?(id),
             {:ok, link} <-
               ObservedRead.read(root(c), i["namespace"], %{
                 "op" => "get_record",
                 "key" => "accept." <> id
               }),
             true <- link["witness"] === observation["witness"],
             %{"value" => %{"kind" => "candidate_acceptance_link"}} = record <-
               link["value"]["record"] do
          {:cont, {:ok, acc ++ [%{note | link: record}]}}
        else
          _ -> {:halt, @error}
        end
      else
        {:cont, {:ok, acc ++ [note]}}
      end
    end)
  end

  defp authenticate(c, i, notes, first, verified, cap, catalog, journals) do
    Enum.reduce_while(notes, {:ok, []}, fn note, {:ok, dependencies} ->
      case authenticate_record(c, i, note, first, verified, cap, catalog, journals) do
        {:ok, dependency} -> {:cont, {:ok, dependencies ++ [dependency]}}
        _ -> {:halt, @error}
      end
    end)
  end

  defp authenticate_record(c, i, %{kind: :literal} = note, first, verified, cap, catalog, _) do
    request = %{"op" => "get_record", "key" => note.record["key"]}

    with :ok <-
           SemanticConsent.check_sources(
             c.config[:semantic_admission]["policy"],
             Enum.map(note.proofs, &%{"category" => &1["origin"], "path" => &1["path"]})
           ),
         {:ok, managed} <-
           ObservedRead.managed_record(
             root(c),
             i["namespace"],
             request,
             cap,
             catalog,
             note.recipe
           ),
         true <- managed["observation"]["witness"] === first.observation["witness"],
         true <- managed["observation"]["value"]["record"] === note.record,
         {:ok, dependency} <-
           ObservedRead.managed_dependency(
             request,
             managed,
             i["effect_binding"]["pin"],
             note.recipe,
             Enum.map(verified, & &1["proof"]),
             System.system_time(:millisecond)
           ) do
      {:ok, dependency}
    else
      _ -> @error
    end
  end

  defp authenticate_record(
         c,
         i,
         %{kind: :accepted} = note,
         first,
         verified,
         cap,
         catalog,
         journals
       ) do
    with %{event: event} <- journals[note.link["value"]["journal_id"]],
         true <- Enum.any?(verified, &(&1["proof"] === event["facts"]["source_proof"])) do
      ObservedRead.with_accepted_decision(
        root(c),
        i["namespace"],
        event,
        cap,
        catalog,
        note.recipe,
        System.system_time(:millisecond),
        fn observed ->
          with true <- observed["record"] === note.record and observed["link"] === note.link,
               true <- observed["witness"] === first.observation["witness"],
               {:ok, _} <-
                 PendingAcceptance.accepted_use_policy(
                   event,
                   observed["metadata"],
                   c.config[:semantic_admission]["policy"],
                   note.recipe,
                   System.system_time(:millisecond)
                 ) do
            ObservedRead.accepted_dependency(
              event,
              observed,
              i["effect_binding"]["pin"],
              note.recipe,
              event["facts"]["source_proof"],
              System.system_time(:millisecond)
            )
          else
            _ -> @error
          end
        end
      )
    else
      _ -> @error
    end
  end

  defp root(c), do: SemanticAdmission.collection_root(c.config[:home])

  defp root_dependency(i, first),
    do:
      ObservedRead.root_dependency(
        i["request"]["request"],
        first.observation,
        i["effect_binding"]["pin"]
      )

  defp bound(i, value) do
    if i["request"]["request"]["op"] == "scan",
      do: Ipse.Extension.CollectionCall.bound_scan(i, value),
      else: {:ok, value}
  end
end
