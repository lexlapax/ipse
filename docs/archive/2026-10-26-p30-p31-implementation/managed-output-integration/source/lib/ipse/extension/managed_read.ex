defmodule Ipse.Extension.ManagedRead do
  @moduledoc """
  Current-source admission of literal records returned by protected collection reads.

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

  alias Ipse.Session.StoredSources
  @error {:error, :collection_source_refused}

  def execute(c, i, recipes, protect, admit \\ fn value, _ -> {:ok, value} end) do
    with {:ok, first} <- protect.(false, fn _, _ -> observe(c, i, recipes) end) do
      case first.notes do
        [] ->
          with {:ok, dependency} <- root_dependency(i, first),
               do: admit.(first.observation["value"], [dependency])

        notes ->
          proofs = Enum.flat_map(notes, & &1.proofs) |> Enum.uniq()

          StoredSources.with_verified(c, i, proofs, fn verified ->
            protect.(true, fn cap, catalog ->
              with {:ok, ^first} <- observe(c, i, recipes),
                   {:ok, dependencies} <- authenticate(c, i, notes, first, verified, cap, catalog),
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
    end
  rescue
    _ -> @error
  end

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
           ) do
      {:ok, %{observation: observation, notes: notes}}
    end
  end

  defp select_notes(value, recipes) do
    records =
      if Map.has_key?(value, "records"), do: value["records"], else: List.wrap(value["record"])

    Enum.reduce_while(records, {:ok, []}, fn record, {:ok, acc} ->
      selected =
        Enum.filter(
          recipes,
          &(&1["kind"] == "literal_source" and
              String.starts_with?(record["key"], &1["key_prefix"]))
        )

      case selected do
        [] ->
          {:cont, {:ok, acc}}

        [recipe] ->
          proofs =
            Enum.reduce(recipe["evidence_path"], record["value"], fn key, value ->
              if is_map(value), do: value[key], else: nil
            end)

          if is_list(proofs) and length(proofs) in 1..8 and
               Enum.all?(proofs, &match?({:ok, _}, ManagedRecipe.source_identity(&1))) do
            {:cont, {:ok, acc ++ [%{record: record, recipe: recipe, proofs: proofs}]}}
          else
            {:halt, @error}
          end

        _ ->
          {:halt, @error}
      end
    end)
  end

  defp authenticate(c, i, notes, first, verified, cap, catalog) do
    Enum.reduce_while(notes, {:ok, []}, fn note, {:ok, dependencies} ->
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
        {:cont, {:ok, dependencies ++ [dependency]}}
      else
        _ -> {:halt, @error}
      end
    end)
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
