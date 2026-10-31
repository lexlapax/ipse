defmodule IpseKnowledge.Store.Collection.Finalization do
  @moduledoc """
  Durable shared-generation reduction phases for the Collection job controller.

  This planner consumes authenticated immutable inputs. Its proposed values use
  the ordinary bounded stage protocol; it never dispatches or retries effects.
  The original action retains Job2/directory1 bytes. The explicit paged action
  uses Job3/directory2 and durable per-page semantic verification.
  """
  alias IpseKnowledge.Evidence, as: E
  alias IpseKnowledge.Store.Collection.Directory, as: D
  alias IpseKnowledge.Store.Collection.Reduction, as: R
  alias IpseKnowledge.Store.Collection.Paged

  @fields ~w(phase batch manifests runs positions entity_pages entities text_bytes chunks facts heads_sha256 entities_sha256)

  def plan(job, values), do: plan(job, values, false)

  def plan(job, values, paged) do
    job = initialize(job, paged)
    reduction = job["reduction"]
    profile = %{"kind" => "collection", "scope" => "project", "partition" => job["partition"]}
    true = valid?(reduction, paged)

    case reduction["phase"] do
      "manifests" ->
        refs = Enum.slice(job["summaries"], reduction["batch"] * 16, 16)
        summaries = Enum.map(refs, &fetch!(&1, values))
        first = reduction["batch"] * 8
        count = div(length(summaries) + 1, 2)

        pages =
          for n <- first..(first + count - 1), into: %{} do
            ref = Enum.fetch!(job["catalog"]["pages"], n)
            {n, fetch!(ref, values)}
          end

        codec = if paged, do: Paged, else: R

        {:ok, batch} =
          codec.batch(
            profile,
            job["catalog"],
            summaries,
            pages,
            reduction["batch"],
            job["vector_selection"],
            job["fact_selection"]
          )

        next =
          reduction
          |> Map.update!("batch", &(&1 + 1))
          |> Map.update!("manifests", &(&1 ++ [D.reference(batch.manifest)]))
          |> Map.update!("runs", &(&1 ++ [D.reference(batch.run)]))
          |> Map.update!("text_bytes", &(&1 + batch.text_bytes))
          |> Map.update!("chunks", &(&1 + batch.chunks))
          |> Map.update!("facts", &(&1 + batch.facts))

        complete = next["batch"] == div(length(job["summaries"]) + 15, 16)

        next =
          if complete do
            true =
              next["text_bytes"] == job["catalog"]["extracted_bytes"] and
                next["chunks"] == job["catalog"]["chunks"] and next["facts"] == job["facts"]

            next
            |> Map.put("phase", "entities")
            |> Map.put("positions", List.duplicate(0, length(next["runs"])))
          else
            next
          end

        result(if(complete, do: Map.put(job, "summaries", []), else: job), next, batch.values)

      "entities" ->
        merged =
          if paged do
            Paged.merge(
              job["partition"],
              reduction["runs"],
              reduction["positions"],
              values,
              length(reduction["entity_pages"]),
              div(job["catalog"]["sources"] + 7, 8)
            )
          else
            R.merge(
              job["partition"],
              reduction["runs"],
              reduction["positions"],
              values,
              length(reduction["entity_pages"])
            )
          end

        case merged do
          {:need, ref} ->
            throw({:need, ref})

          {:ok, merged} ->
            next =
              reduction
              |> Map.put("positions", merged.positions)
              |> Map.update!("entities", &(&1 + merged.entities))

            true = next["entities"] <= 5000

            next =
              if merged.unit,
                do: Map.update!(next, "entity_pages", &(&1 ++ [D.reference(merged.unit)])),
                else: next

            next =
              if merged.complete,
                do:
                  next
                  |> Map.put("phase", "heads")
                  |> Map.put("runs", [])
                  |> Map.put("positions", []),
                else: next

            result(job, next, if(merged.unit, do: [merged.unit], else: []))

          _ ->
            raise "invalid entity merge"
        end

      "heads" ->
        case R.manifests(
               profile,
               job["catalog"],
               reduction["manifests"],
               values,
               job["vector_selection"],
               job["fact_selection"]
             ) do
          {:need, ref} ->
            throw({:need, ref})

          {:ok, digest} ->
            result(
              job,
              reduction
              |> Map.put("heads_sha256", digest.sha256)
              |> Map.put("phase", "entity_digest"),
              []
            )

          _ ->
            raise "invalid head reduction"
        end

      "entity_digest" ->
        if paged do
          case Paged.verify(
                 job["partition"],
                 reduction["entity_pages"],
                 values,
                 reduction["entities"],
                 div(job["catalog"]["sources"] + 7, 8),
                 reduction["digest_cursor"],
                 reduction["last_entity_id"]
               ) do
            {:need, ref} ->
              throw({:need, ref})

            {:ok, verified} ->
              next =
                reduction
                |> Map.update!("digest_cursor", &(&1 + 1))
                |> Map.update!("verified_entities", &(&1 + verified.rows))
                |> Map.put("last_entity_id", verified.last)

              next =
                if next["digest_cursor"] == length(next["entity_pages"]) do
                  true = next["verified_entities"] == next["entities"]

                  next
                  |> Map.put("phase", "select")
                  |> Map.put(
                    "entity_pages_sha256",
                    Paged.commitment(
                      next["entity_pages"],
                      next["entities"],
                      div(job["catalog"]["sources"] + 7, 8)
                    )
                  )
                else
                  next
                end

              result(job, next, [])

            _ ->
              raise "invalid paged entity verification"
          end
        else
          case R.entities(
                 job["partition"],
                 reduction["entity_pages"],
                 values,
                 reduction["entities"],
                 div(job["catalog"]["sources"] + 7, 8)
               ) do
            {:need, ref} ->
              throw({:need, ref})

            {:ok, digest} ->
              result(
                job,
                reduction
                |> Map.put("entities_sha256", digest.sha256)
                |> Map.put("phase", "select"),
                []
              )

            _ ->
              raise "invalid entity reduction"
          end
        end

      "select" ->
        {:ok, root} = selected_root(job)

        {:ok,
         %{
           job:
             job
             |> Map.put("status", "selected")
             |> Map.put("reduction", Map.put(reduction, "phase", "selected")),
           values: [],
           root: root,
           prerequisites: reduction["manifests"] ++ reduction["entity_pages"]
         }}
    end
  rescue
    _ -> {:error, :invalid_generation_finalization}
  catch
    {:need, ref} -> {:need, ref}
  end

  def selected_root(job) do
    reduction = job["reduction"]

    true =
      job["version"] in [2, 3] and reduction["phase"] in ~w(select selected) and
        valid?(reduction, job["version"] === 3)

    codec = if job["version"] === 3, do: Paged, else: R

    codec.root(
      %{"kind" => "collection", "scope" => "project", "partition" => job["partition"]},
      job["catalog"],
      job["generation"],
      job["vector_selection"],
      job["fact_selection"],
      %{manifests: reduction["manifests"], entities: reduction["entity_pages"]},
      %{facts: reduction["facts"], entities: reduction["entities"]},
      %{
        heads: reduction["heads_sha256"],
        entities:
          reduction[if(job["version"] === 3, do: "entity_pages_sha256", else: "entities_sha256")]
      }
    )
  rescue
    _ -> {:error, :invalid_generation_finalization}
  end

  def valid?(r), do: valid?(r, false)

  def valid?(r, paged) do
    hash = if paged, do: "entity_pages_sha256", else: "entities_sha256"

    fields =
      if paged,
        do:
          (@fields -- ["entities_sha256"]) ++
            ~w(recipe entity_pages_sha256 digest_cursor verified_entities last_entity_id),
        else: @fields

    exact?(r, fields) and
      r["phase"] in ~w(manifests entities heads entity_digest select selected) and
      is_integer(r["batch"]) and r["batch"] in 0..8 and
      Enum.all?(~w(manifests runs entity_pages), fn f ->
        is_list(r[f]) and Enum.all?(r[f], &reference?/1)
      end) and
      length(r["manifests"]) == r["batch"] and length(r["runs"]) <= 8 and
      length(r["entity_pages"]) <= if(paged, do: 157, else: 79) and
      is_list(r["positions"]) and
      length(r["positions"]) == if(r["phase"] == "manifests", do: 0, else: length(r["runs"])) and
      Enum.all?(r["positions"], &(is_integer(&1) and &1 in 0..5000)) and
      Enum.all?(~w(entities text_bytes chunks facts), &E.safe_uint?(r[&1])) and
      r["entities"] <= 5000 and r["text_bytes"] <= 20 * 1024 * 1024 and r["chunks"] <= 10_000 and
      r["facts"] <= 20_000 and
      (is_nil(r["heads_sha256"]) or E.sha256?(r["heads_sha256"])) and
      (is_nil(r[hash]) or E.sha256?(r[hash])) and phase_shape?(r, paged, hash) and
      (not paged or paged_progress?(r))
  rescue
    _ -> false
  end

  defp phase_shape?(%{"phase" => "manifests"} = r, _, hash),
    do:
      length(r["runs"]) == r["batch"] and r["entity_pages"] == [] and r["entities"] == 0 and
        r["heads_sha256"] == nil and r[hash] == nil

  defp phase_shape?(%{"phase" => "entities"} = r, paged, hash),
    do:
      length(r["runs"]) == r["batch"] and r["runs"] != [] and
        r["entities"] == length(r["entity_pages"]) * if(paged, do: 32, else: 64) and
        r["heads_sha256"] == nil and
        r[hash] == nil

  defp phase_shape?(r, paged, hash),
    do:
      r["runs"] == [] and r["positions"] == [] and r["entities"] in 1..5000 and
        length(r["entity_pages"]) ==
          div(r["entities"] + if(paged, do: 31, else: 63), if(paged, do: 32, else: 64)) and
        (r["phase"] == "heads" or E.sha256?(r["heads_sha256"])) and
        (r["phase"] in ~w(heads entity_digest) or E.sha256?(r[hash]))

  defp paged_progress?(r) do
    r["recipe"] == "ipse.evidence.shared_directory.v2" and
      is_integer(r["digest_cursor"]) and r["digest_cursor"] in 0..length(r["entity_pages"]) and
      r["verified_entities"] === min(r["digest_cursor"] * 32, r["entities"]) and
      if(r["digest_cursor"] == 0,
        do: r["last_entity_id"] == nil,
        else: E.sha256?(r["last_entity_id"])
      ) and
      cond do
        r["phase"] in ~w(manifests entities heads) ->
          r["digest_cursor"] == 0 and r["verified_entities"] == 0 and
            r["entity_pages_sha256"] == nil and
            (r["phase"] != "heads" or r["heads_sha256"] == nil)

        r["phase"] == "entity_digest" ->
          r["digest_cursor"] < length(r["entity_pages"]) and r["entity_pages_sha256"] == nil

        true ->
          r["digest_cursor"] == length(r["entity_pages"]) and
            r["verified_entities"] == r["entities"] and E.sha256?(r["entity_pages_sha256"])
      end
  end

  defp initialize(%{"version" => 1, "status" => "manifests"} = job, paged) do
    initialized =
      job
      |> Map.put("version", 2)
      |> Map.put("status", "reducing")
      |> Map.put("reduction", %{
        "phase" => "manifests",
        "batch" => 0,
        "manifests" => [],
        "runs" => [],
        "positions" => [],
        "entity_pages" => [],
        "entities" => 0,
        "text_bytes" => 0,
        "chunks" => 0,
        "facts" => 0,
        "heads_sha256" => nil,
        "entities_sha256" => nil
      })

    if paged do
      initialized
      |> Map.put("version", 3)
      |> Map.update!("reduction", fn r ->
        r
        |> Map.delete("entities_sha256")
        |> Map.merge(%{
          "recipe" => "ipse.evidence.shared_directory.v2",
          "entity_pages_sha256" => nil,
          "digest_cursor" => 0,
          "verified_entities" => 0,
          "last_entity_id" => nil
        })
      end)
    else
      initialized
    end
  end

  defp initialize(%{"version" => 2, "status" => "reducing"} = job, false), do: job
  defp initialize(%{"version" => 3, "status" => "reducing"} = job, true), do: job

  defp result(job, reduction, values),
    do:
      {:ok,
       %{job: Map.put(job, "reduction", reduction), values: values, root: nil, prerequisites: []}}

  defp fetch!(ref, values) do
    value =
      case Map.fetch(values, ref["key"]) do
        {:ok, value} -> value
        :error -> throw({:need, ref})
      end

    bytes = IO.iodata_to_binary(JSON.encode!(value))
    true = E.sha256(bytes) === ref["sha256"]
    true = not Map.has_key?(ref, "byte_count") or byte_size(bytes) === ref["byte_count"]
    value
  end

  defp reference?(r),
    do:
      exact?(r, ~w(key sha256 byte_count)) and is_binary(r["key"]) and byte_size(r["key"]) <= 96 and
        E.sha256?(r["sha256"]) and is_integer(r["byte_count"]) and r["byte_count"] in 2..49_152

  defp exact?(m, keys), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(keys)
end
