defmodule IpseKnowledge.Store.Collection.Index do
  @moduledoc "Catalog-bound lossless namespace lexical generations over bounded Collection values."
  alias IpseKnowledge.Evidence, as: E
  alias IpseKnowledge.Store.Collection, as: C
  @group 8
  @page_bytes 6144
  @object_bytes 48 * 1024
  @reads 512
  @effects 16

  @doc false
  def completed_job?(job, root, profile) when is_map(job) and is_map(profile) do
    state = %{profile: profile}

    job?(job, state) and
      case job["status"] do
        "aborted" ->
          true

        "building" ->
          catalog = job["catalog"]

          job["cursor"] === catalog["sources"] and job["unit"] === 0 and root?(root, state) and
            root === %{
              "version" => 1,
              "kind" => "lexical_index",
              "recipe" => E.lexical_recipe(),
              "job_id" => job["id"],
              "generation" => job["index_generation"],
              "catalog_sha256" => job["catalog_sha256"],
              "catalog_generation" => catalog["generation"],
              "floor" => catalog["floor"],
              "sources" => catalog["sources"],
              "chunks" => catalog["chunks"],
              "groups" => job["groups"]
            }

        _ ->
          false
      end
  rescue
    _ -> false
  end

  def completed_job?(_, _, _), do: false

  @doc false
  def validated_epoch(job, profile) do
    if job?(job, %{profile: profile}),
      do: {:ok, job_epoch(job)},
      else: {:error, :invalid_lexical_job}
  rescue
    _ -> {:error, :invalid_lexical_job}
  end

  @doc false
  def completed_backup?(profile, root, groups, bundles, values) do
    state = %{profile: profile}

    with true <- root?(root, state) and length(groups) === length(root["groups"]),
         true <- Enum.map(groups, &elem(&1, 0)) === root["groups"],
         true <- length(bundles) === root["sources"],
         true <-
           Enum.all?(bundles, &(&1["head"]["version"] === 2 and is_map(&1["head"]["lexical"]))),
         true <-
           Enum.sum(Enum.map(bundles, fn b -> length(elem(E.chunks(b["source"]), 1)) end)) ===
             root["chunks"] do
      Enum.with_index(groups)
      |> Enum.all?(fn {{ref, header}, n} ->
        selected = Enum.slice(bundles, n * @group, @group)
        sources = Enum.map(selected, & &1["source"])

        entries =
          Enum.map(selected, fn b ->
            {:ok, run} = E.lexical_run(b["source"])

            %{
              "run" => run,
              "source_bundle_sha256" => E.sha256(json(b["source"])),
              "source_revision" => b["head"]["revision"]
            }
          end)

        {:ok, expected} = storage_plan(profile, sources, entries, n * @group)

        header === Map.fetch!(values, ref["key"]) and ref === expected.header and
          Enum.all?(expected.values, fn unit -> Map.fetch!(values, unit.key) === unit.value end)
      end)
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def start(profile, operation, args) when operation in [:lexical_build, :lexical_query] do
    with true <-
           is_map(profile) and profile["kind"] == "collection" and profile["scope"] == "project",
         true <- is_binary(profile["partition"]),
         true <- valid_args?(operation, args) do
      s = %{
        profile: profile,
        operation: operation,
        args: args,
        phase: nil,
        reads: 0,
        effects: 0,
        inner: nil,
        maintenance_epoch: nil,
        native_generation: nil,
        job: nil,
        job_row: nil,
        catalog_row: nil,
        root_row: nil,
        token: args["continuation"],
        work: "unit",
        stages: %{},
        plan: nil
      }

      io(s, :snapshot, %{}, :maintenance_snapshot)
    else
      _ -> error(:invalid_lexical_index_request)
    end
  rescue
    _ -> error(:invalid_lexical_index_request)
  end

  def resume(%{index_state: s, inner: inner}, outcome) do
    advance(C.resume(inner, outcome), s)
  end

  defp valid_args?(:lexical_build, a) do
    exact?(a, ~w(action continuation)) and a["action"] in ~w(begin next inspect abort) and
      (is_nil(a["continuation"]) or token?(a["continuation"])) and
      (not is_map(a["continuation"]) or a["continuation"]["version"] !== 4 or
         a["action"] == "abort") and
      (a["action"] not in ~w(next abort) or is_map(a["continuation"]))
  end

  defp valid_args?(:lexical_query, a) do
    exact?(a, ~w(query top_k as_of_ms)) and is_binary(a["query"]) and
      byte_size(a["query"]) in 1..1024 and a["top_k"] in 1..10 and E.safe_uint?(a["as_of_ms"])
  end

  defp io(s, op, args, phase) do
    result =
      if is_nil(s.maintenance_epoch),
        do: C.start(s.profile, op, args),
        else: C.start_with_epoch(s.profile, op, args, s.maintenance_epoch)

    advance(result, %{s | phase: phase})
  end

  defp advance({:call, request, inner}, s) do
    read = C.read_request?(request)

    reads =
      s.reads +
        if read do
          1
        else
          0
        end

    effects =
      s.effects +
        if read do
          0
        else
          1
        end

    cond do
      reads > @reads ->
        error(:lexical_read_budget)

      effects > @effects and s.work == "publish" ->
        ready(s, nil)

      effects > @effects ->
        error(:lexical_effect_budget)

      true ->
        {:call, request, %{index_state: %{s | reads: reads, effects: effects}, inner: inner}}
    end
  end

  defp advance({:done, {:ok, value}}, s) do
    done(s, value)
  end

  defp advance({:done, {:continue, value}}, s) do
    ready(s, value["continuation"])
  end

  defp advance({:stop, :unknown_effect}, _) do
    {:stop, :unknown_effect}
  end

  defp advance({:done, {:error, code, _}}, _) do
    error(code)
  end

  defp done(%{phase: :maintenance_snapshot} = s, value) do
    with {:ok, epoch, status} <- C.snapshot_epoch(value),
         true <-
           s.operation == :lexical_query or s.args["action"] == "inspect" or status == "idle",
         true <- continuation_epoch?(s.token, s.args["action"], epoch) do
      io(%{s | maintenance_epoch: epoch}, :value_read, %{"key" => catalog_key(s)}, :catalog)
    else
      _ -> error(:lexical_maintenance_changed)
    end
  end

  defp done(%{phase: :catalog} = s, value) do
    row = value["record"]

    with true <- is_map(row) and C.valid_catalog?(row["value"], s.profile) do
      s = %{s | catalog_row: row, native_generation: value["native_generation"]}
      io(s, :value_read, %{"key" => root_key(s)}, :root)
    else
      _ -> error(:lexical_catalog_missing)
    end
  end

  defp done(%{phase: :root} = s, value) do
    row = value["record"]

    with true <- row == nil or root?(row["value"], s),
         true <- s.operation != :lexical_query or row != nil do
      s = %{s | root_row: row, native_generation: value["native_generation"]}

      if s.operation == :lexical_query do
        query_begin(s)
      else
        io(s, :value_read, %{"key" => job_key(s)}, :job)
      end
    else
      _ -> error(:lexical_namespace_index_unavailable)
    end
  end

  defp done(%{phase: :job} = s, value) do
    row = value["record"]

    with true <- row == nil or job?(row["value"], s) do
      s = %{
        s
        | job_row: row,
          job:
            if row do
              row["value"]
            end,
          native_generation: value["native_generation"]
      }

      case s.args["action"] do
        "inspect" ->
          inspect_result(s)

        "begin" ->
          begin_job(s)

        action when action in ~w(next abort) ->
          t = s.token

          with true <-
                 row != nil and t["job_id"] == s.job["id"] and
                   t["job_revision"] == row["revision"],
               true <- job_epoch(s.job) === token_epoch(t),
               true <- s.job["status"] == "building",
               selected = s.root_row && s.root_row["value"],
               true <- not completed_job?(s.job, selected, s.profile),
               true <- is_nil(selected) or selected["job_id"] !== s.job["id"] do
            s = %{s | work: t["work"], stages: t["stages"]}

            if action == "abort" do
              write_job(
                %{
                  s
                  | work: "retire",
                    token: if(t["version"] === 4, do: t, else: nil),
                    stages: %{}
                },
                Map.put(s.job, "status", "aborted"),
                :aborted
              )
            else
              continue_job(s)
            end
          else
            _ -> error(:lexical_continuation_conflict)
          end
      end
    else
      _ -> error(:lexical_job_corrupt)
    end
  end

  defp done(%{phase: {:catalog_page, ordinal, ref}} = s, value) do
    row = value["record"]

    with true <- C.valid_catalog_page?(row, ref, ordinal, s.profile),
         rows = row["value"]["rows"] |> Enum.drop(rem(s.job["cursor"], 16)) |> Enum.take(@group),
         true <- rows != [] do
      keys = Enum.map(rows, & &1["source_key"])
      s = Map.put(s, :group_keys, keys)

      io(
        s,
        :source_keys,
        %{"source_keys" => keys, "as_of_ms" => E.safe_integer_max()},
        :group_sources
      )
    else
      _ -> error(:lexical_catalog_page_corrupt)
    end
  end

  defp done(%{phase: :group_sources} = s, value) do
    s = Map.put(s, :group_sources, value["sources"])

    io(
      s,
      :lexical_keys,
      %{"source_keys" => s.group_keys, "as_of_ms" => E.safe_integer_max()},
      :group_runs
    )
  end

  defp done(%{phase: :group_runs} = s, value) do
    with true <- value["catalog_generation"] == s.job["catalog"]["generation"],
         true <- value["catalog_floor"] == s.job["catalog"]["floor"],
         true <- length(value["runs"]) == length(s.group_sources),
         true <-
           Enum.zip(s.group_sources, value["runs"])
           |> Enum.all?(fn {source, entry} ->
             {:ok, run} = E.lexical_run(source)
             run === entry["run"] and E.sha256(json(source)) == entry["source_bundle_sha256"]
           end),
         true <-
           Enum.reduce(value["runs"], 0, &(byte_size(json(&1["run"])) + &2)) <= 2 * 1024 * 1024,
         {:ok, plan} <- group_plan(s, s.group_sources, value["runs"]),
         unit = if(s.token, do: s.token["unit"], else: 0),
         true <- is_integer(unit) and unit >= 0 and unit < length(plan.values) do
      count = unit + if(s.work == "job", do: 1, else: 0)

      s =
        Map.merge(s, %{
          plan: plan,
          unit: unit,
          native_generation: value["native_generation"],
          verify_units: Enum.take(plan.values, count)
        })

      verify_units(s)
    else
      _ -> error(:lexical_group_preflight_refused)
    end
  end

  defp done(%{phase: :known_unit} = s, value) do
    [unit | rest] = s.verify_units
    row = value["record"]

    if row != nil and row["sha256"] == unit.sha256 and row["byte_count"] == unit.byte_count do
      verify_units(%{s | verify_units: rest})
    else
      error(:lexical_unit_missing)
    end
  end

  defp done(%{phase: :unit_written} = s, _) do
    if s.unit == length(s.plan.values) - 1,
      do: update_progress(s),
      else: ready(%{s | unit: s.unit + 1, token: nil}, nil)
  end

  defp done(%{phase: :root_prepared} = s, value) do
    publication(
      Map.merge(s, %{
        stages: Map.put(s.stages, "root", value["stage"]),
        token: nil,
        root_verified: true
      })
    )
  end

  defp done(%{phase: :catalog_prepared} = s, value) do
    publication(%{s | stages: Map.put(s.stages, "catalog", value["stage"]), token: nil})
  end

  defp done(%{phase: {:verify_stage, which}} = s, value) do
    {key, body, revision} =
      if which == "root" do
        {root_key(s), s.new_root, s.job["root_revision"]}
      else
        {catalog_key(s), s.job["catalog"], s.catalog_row["revision"]}
      end

    stage = value["stage"]

    with true <-
           stage["state"] == "sealed" and Map.take(stage, ~w(slot epoch)) === s.stages[which],
         true <- stage["key"] == key and stage["expected_revision"] == revision,
         true <-
           stage["byte_count"] == byte_size(json(body)) and
             stage["offset"] == byte_size(json(body)),
         true <- stage["sha256"] == E.sha256(json(body)) do
      if Map.get(s, :verify_next) == :publication,
        do: publication(Map.merge(s, %{root_verified: true, verify_next: nil})),
        else: verify_publication(s, s.verify_rest)
    else
      _ -> error(:lexical_publication_stage_mismatch)
    end
  end

  defp done(%{phase: :published} = s, _) do
    {:done,
     {:ok,
      %{
        "status" => "indexed",
        "index_generation" => s.job["index_generation"],
        "catalog_generation" => s.job["catalog"]["generation"],
        "catalog_floor" => s.job["catalog"]["floor"],
        "coverage" => Map.put(coverage(s), "index_complete", true)
      }}}
  end

  defp done(%{phase: :query_group} = s, value) do
    header = value["value"]

    with true <- run_header?(header, s),
         true <- header["cursor"] == length(s.summaries),
         true <- length(s.summaries) + length(header["sources"]) <= s.index_root["sources"],
         true <-
           length(Enum.uniq_by(s.summaries ++ header["sources"], &hd/1)) ==
             length(s.summaries) + length(header["sources"]) do
      base = length(s.summaries)

      pages =
        for [object_hash, _, refs] <- header["packs"],
            [ordinal, offset, bytes, sha, first, last] <- refs,
            first != nil and Enum.any?(s.terms, &(&1 >= first and &1 <= last)) do
          %{
            "key" => "lexp." <> s.profile["partition"] <> "." <> object_hash,
            "object_sha256" => object_hash,
            "offset" => offset,
            "byte_count" => bytes,
            "sha256" => sha,
            "ordinal" => ordinal,
            "first" => first,
            "last" => last
          }
        end

      s =
        Map.merge(s, %{
          summaries: s.summaries ++ header["sources"],
          pending_pages: pages,
          query_group: base,
          group_size: length(header["sources"])
        })

      query_page(s)
    else
      _ -> error(:lexical_run_directory_corrupt)
    end
  end

  defp done(%{phase: :query_page} = s, value) do
    page = value["value"]

    with true <-
           exact?(page, ~w(version kind ordinal rows)) and page["version"] === 1 and
             page["kind"] == "lexical_postings",
         true <- is_list(page["rows"]) and length(page["rows"]) <= 128,
         true <- Enum.all?(page["rows"], &posting_row?(&1, s.group_size)),
         true <- page["ordinal"] == s.page_expected["ordinal"],
         terms = Enum.map(page["rows"], &hd/1),
         true <- terms == Enum.sort(terms),
         true <-
           List.first(terms) == s.page_expected["first"] and
             List.last(terms) == s.page_expected["last"] do
      Enum.reduce_while(page["rows"], {:ok, s.postings}, fn [term, rows], {:ok, acc} ->
        if term in s.terms do
          Enum.reduce_while(rows, {:ok, acc}, fn [source, chunk, tf, length], {:ok, acc} ->
            key = {s.query_group + source, chunk}
            existing = Map.get(acc, key, %{length: length, terms: %{}})

            summary = Enum.at(s.summaries, s.query_group + source)

            if existing.length == length and not Map.has_key?(existing.terms, term) and
                 chunk < Enum.at(summary, 9) and length <= Enum.at(summary, 10) do
              {:cont,
               {:ok, Map.put(acc, key, %{existing | terms: Map.put(existing.terms, term, tf)})}}
            else
              {:halt, {:error, :lexical_duplicate_posting}}
            end
          end)
          |> case do
            {:ok, acc} -> {:cont, {:ok, acc}}
            error -> {:halt, error}
          end
        else
          {:cont, {:ok, acc}}
        end
      end)
      |> case do
        {:ok, postings} -> query_page(%{s | postings: postings})
        {:error, code} -> error(code)
      end
    else
      _ -> error(:lexical_postings_corrupt)
    end
  end

  defp done(%{phase: :hydrated} = s, value) do
    with true <-
           value["catalog_generation"] == s.index_root["catalog_generation"] and
             value["catalog_floor"] == s.index_root["floor"],
         true <-
           Enum.all?(value["sources"], fn source ->
             summary = Enum.find(s.summaries, &(hd(&1) == source["source_key"]))

             source["generation"] == Enum.at(summary, 2) and
               source["content_sha256"] == Enum.at(summary, 3) and
               E.sha256(json(source)) == Enum.at(summary, 4)
           end) do
      hydrate(%{s | selected_sources: s.selected_sources ++ value["sources"]})
    else
      _ -> error(:lexical_selected_source_changed)
    end
  end

  defp done(%{phase: :query_final} = s, value) do
    with true <-
           value["record"] != nil and value["record"]["sha256"] == s.index_root["catalog_sha256"],
         {:ok, rank} <-
           E.rank_indexed(
             s.selected_sources,
             s.ranked,
             s.args["query"],
             s.query_stats,
             s.args["top_k"],
             s.args["as_of_ms"]
           ) do
      selected_ids = Enum.map(s.selected_sources, & &1["source_id"])

      partial =
        s.active
        |> Map.values()
        |> Enum.map(&Enum.at(&1, 11))
        |> Enum.reject(&is_nil/1)
        |> Enum.reject(&(&1["source_id"] in selected_ids))

      excluded =
        s.summaries
        |> Enum.reject(&eligible?(&1, s.args["as_of_ms"]))
        |> Enum.map(&%{"code" => "stale_source", "source_id" => Enum.at(&1, 1)})

      rank = E.query_scope(rank, s.selected_sources, partial ++ excluded, s.args["as_of_ms"])

      coverage =
        rank["coverage"]
        |> Map.merge(coverage(s))
        |> Map.put("namespace_complete", true)
        |> Map.put("eligible_sources", map_size(s.active))
        |> Map.put("sources", map_size(s.active))
        |> Map.put("hydrated_sources", length(s.selected_sources))
        |> Map.put("indexed_sources", s.index_root["sources"])
        |> Map.put("indexed_chunks", s.index_root["chunks"])
        |> Map.put("index_generation", s.index_root["generation"])
        |> Map.put("catalog_generation", s.index_root["catalog_generation"])
        |> Map.put("catalog_floor", s.index_root["floor"])

      {:done,
       {:ok,
        rank
        |> Map.put("coverage", coverage)
        |> Map.put("native_generation", value["native_generation"])
        |> Map.put("selected_sources", s.selected_sources)}}
    else
      _ -> error(:lexical_selection_changed)
    end
  end

  defp done(%{phase: phase} = s, value) when phase in [:begun, :progressed, :aborted] do
    row = value["record"]

    s =
      Map.merge(s, %{
        job: s.next_job,
        job_row: row,
        work: "unit",
        stages: %{},
        token: nil,
        unit: 0
      })

    if phase == :aborted do
      {:done, {:ok, %{"status" => "aborted", "coverage" => coverage(s)}}}
    else
      ready(s, nil)
    end
  end

  defp begin_job(s) do
    completed =
      not is_nil(s.job) and not is_nil(s.root_row) and
        s.root_row["value"]["job_id"] == s.job["id"]

    cond do
      s.root_row &&
          (s.catalog_row["value"]["floor"] < s.root_row["value"]["floor"] or
             s.catalog_row["value"]["generation"] < s.root_row["value"]["catalog_generation"]) ->
        error(:lexical_floor_regression)

      s.job && s.job["status"] == "building" && not completed ->
        error(:lexical_build_exists)

      true ->
        job = %{
          "version" => 1,
          "kind" => "lexical_job",
          "id" => random_id(),
          "status" => "building",
          "catalog" => s.catalog_row["value"],
          "catalog_sha256" => s.catalog_row["sha256"],
          "cursor" => 0,
          "unit" => 0,
          "groups" => [],
          "root_revision" => revision(s.root_row),
          "index_generation" =>
            if s.root_row do
              s.root_row["value"]["generation"] + 1
            else
              1
            end
        }

        job =
          if s.maintenance_epoch == 0,
            do: job,
            else: Map.merge(job, %{"version" => 2, "maintenance_epoch" => s.maintenance_epoch})

        write_job(%{s | job: job, work: "job"}, job, :begun)
    end
  end

  defp continue_job(s) do
    with true <- s.job["catalog_sha256"] == s.catalog_row["sha256"],
         true <- s.job["catalog"] === s.catalog_row["value"],
         true <- revision(s.root_row) == s.job["root_revision"],
         true <- continuation_phase?(s) do
      if s.job["cursor"] == s.job["catalog"]["sources"] do
        publication(s)
      else
        group_begin(s)
      end
    else
      _ -> error(:lexical_catalog_changed)
    end
  end

  defp continuation_phase?(s) do
    if s.job["cursor"] < s.job["catalog"]["sources"] do
      s.work in ~w(unit job) and s.stages == %{}
    else
      s.token["unit"] == 0 and
        case s.work do
          "unit" ->
            s.stages == %{} and s.token["write"] == nil

          "root" ->
            s.stages == %{}

          "catalog" ->
            Map.keys(s.stages) == ["root"]

          "publish" ->
            Enum.sort(Map.keys(s.stages)) == ~w(catalog root) and s.token["write"] == nil

          _ ->
            false
        end
    end
  end

  defp group_begin(s) do
    page = div(s.job["cursor"], 16)
    ref = Enum.at(s.job["catalog"]["pages"], page)
    io(s, :value_read, %{"key" => ref["key"]}, {:catalog_page, page, ref})
  end

  defp write_unit(s, unit) do
    write(s, :value_write, unit.key, unit.value, 0, true, :unit_written)
  end

  defp verify_units(%{verify_units: []} = s) do
    if s.work == "job",
      do: update_progress(s),
      else: write_unit(%{s | work: "unit"}, Enum.at(s.plan.values, s.unit))
  end

  defp verify_units(%{verify_units: [unit | _]} = s),
    do: io(s, :value_stat, %{"key" => unit.key, "generation" => s.native_generation}, :known_unit)

  defp update_progress(s) do
    job =
      s.job
      |> Map.put("cursor", s.job["cursor"] + length(s.group_sources))
      |> Map.put("unit", 0)
      |> Map.update!("groups", &(&1 ++ [s.plan.header]))

    write_job(%{s | work: "job"}, job, :progressed)
  end

  defp write_job(s, job, phase) do
    write(
      Map.put(s, :next_job, job),
      :value_write,
      job_key(s),
      job,
      revision(s.job_row),
      false,
      phase
    )
  end

  defp publication(s) do
    root = %{
      "version" => 1,
      "kind" => "lexical_index",
      "recipe" => E.lexical_recipe(),
      "job_id" => s.job["id"],
      "generation" => s.job["index_generation"],
      "catalog_sha256" => s.job["catalog_sha256"],
      "catalog_generation" => s.job["catalog"]["generation"],
      "floor" => s.job["catalog"]["floor"],
      "sources" => s.job["catalog"]["sources"],
      "chunks" => s.job["catalog"]["chunks"],
      "groups" => s.job["groups"]
    }

    s = Map.put(s, :new_root, root)

    cond do
      s.stages["root"] == nil ->
        write(
          %{s | work: "root"},
          :value_prepare,
          root_key(s),
          root,
          s.job["root_revision"],
          false,
          :root_prepared
        )

      not Map.get(s, :root_verified, false) ->
        io(
          Map.put(s, :verify_next, :publication),
          :stage_inspect,
          %{"ref" => s.stages["root"]},
          {:verify_stage, "root"}
        )

      s.stages["catalog"] == nil ->
        write(
          %{s | work: "catalog"},
          :value_prepare,
          catalog_key(s),
          s.job["catalog"],
          s.catalog_row["revision"],
          false,
          :catalog_prepared
        )

      true ->
        verify_publication(s, ["root", "catalog"])
    end
  end

  defp verify_publication(s, []) do
    io(
      %{s | work: "publish"},
      :value_commit,
      %{"stages" => [s.stages["root"], s.stages["catalog"]]},
      :published
    )
  end

  defp verify_publication(s, [which | rest]) do
    io(
      Map.merge(s, %{verify_rest: rest, verify_next: :commit}),
      :stage_inspect,
      %{"ref" => s.stages[which]},
      {:verify_stage, which}
    )
  end

  defp write(s, operation, key, value, revision, reuse, phase) do
    if s.effects > 12 do
      ready(s, nil)
    else
      cp =
        if s.token && s.token["work"] == s.work do
          s.token["write"]
        end

      io(
        s,
        operation,
        %{
          "key" => key,
          "value" => value,
          "expected_revision" => revision,
          "reuse" => reuse,
          "continuation" => cp,
          "effects_used" => s.effects,
          "reads_used" => s.reads
        },
        phase
      )
    end
  end

  defp ready(s, write) do
    token = %{
      "version" => 2,
      "job_id" => s.job["id"],
      "job_revision" => revision(s.job_row),
      "work" => s.work,
      "write" => write,
      "unit" => Map.get(s, :unit, 0),
      "stages" => s.stages
    }

    token =
      cond do
        s.work == "retire" ->
          Map.merge(token, %{
            "version" => 4,
            "maintenance_epoch" => job_epoch(s.job),
            "retirement_epoch" => s.maintenance_epoch
          })

        s.maintenance_epoch == 0 ->
          token

        true ->
          Map.merge(token, %{"version" => 3, "maintenance_epoch" => s.maintenance_epoch})
      end

    {:done,
     {:continue,
      %{
        "status" => if(s.work == "retire", do: "aborting", else: "building"),
        "continuation" => token,
        "source_cursor" => s.job["cursor"],
        "coverage" => coverage(s)
      }}}
  end

  defp inspect_result(s) do
    selected = s.root_row && s.root_row["value"]

    status =
      cond do
        selected == nil -> "unbuilt"
        selected["catalog_sha256"] != s.catalog_row["sha256"] -> "stale"
        true -> "current"
      end

    job =
      if s.job do
        %{
          "id" => s.job["id"],
          "revision" => revision(s.job_row),
          "status" => s.job["status"],
          "source_cursor" => s.job["cursor"],
          "unit" => s.job["unit"],
          "resume_requires_known_continuation" => true
        }
      end

    {:done,
     {:ok,
      %{
        "status" => status,
        "job" => job,
        "index_generation" =>
          if selected do
            selected["generation"]
          end,
        "coverage" => coverage(s)
      }}}
  end

  @doc false
  def storage_plan(profile, sources, entries, cursor) do
    with true <-
           exact?(profile, ~w(kind scope partition)) and profile["kind"] == "collection" and
             profile["scope"] == "project",
         true <-
           is_binary(profile["partition"]) and
             Regex.match?(~r/\A[a-z][a-z0-9_-]{0,15}\z/, profile["partition"]),
         true <-
           is_list(sources) and length(sources) in 1..8 and is_list(entries) and
             length(entries) == length(sources),
         true <- E.safe_uint?(cursor) and rem(cursor, 8) == 0,
         true <-
           Enum.zip(sources, entries)
           |> Enum.all?(fn {source, entry} ->
             with true <- E.valid_source?(source) and source["partition"] == profile["partition"],
                  {:ok, run} <- E.lexical_run(source),
                  true <-
                    entry["run"] === run and
                      entry["source_bundle_sha256"] == E.sha256(json(source)) and
                      E.safe_positive?(entry["source_revision"]) do
               true
             else
               _ -> false
             end
           end) do
      group_plan(%{profile: profile, job: %{"cursor" => cursor}}, sources, entries)
    else
      _ -> {:error, :invalid_lexical_storage_plan}
    end
  rescue
    _ -> {:error, :invalid_lexical_storage_plan}
  end

  defp group_plan(s, sources, entries) do
    summaries =
      Enum.zip(sources, entries)
      |> Enum.map(fn {source, entry} ->
        run = entry["run"]
        receipt = E.document_receipt(source)

        gap =
          if is_map(receipt) and receipt["status"] == "partial" do
            %{
              "code" => "partial_document",
              "source_id" => source["source_id"],
              "warning_count" => length(receipt["warnings"]),
              "warnings_sha256" => E.sha256(json(%{"warnings" => receipt["warnings"]}))
            }
          else
            nil
          end

        [
          source["source_key"],
          source["source_id"],
          source["generation"],
          source["content_sha256"],
          entry["source_bundle_sha256"],
          entry["source_revision"],
          source["observed_at_ms"],
          source["expires_at_ms"],
          source["origin"]["historical"],
          length(run["chunks"]),
          Enum.reduce(run["chunks"], 0, &(Enum.at(&1, 3) + &2)),
          gap
        ]
      end)

    terms =
      entries
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {entry, source_ordinal}, acc ->
        run = entry["run"]

        Enum.reduce(run["terms"], acc, fn [term, postings], acc ->
          rows =
            Enum.map(postings, fn [chunk, tf] ->
              [source_ordinal, chunk, tf, run["chunks"] |> Enum.at(chunk) |> Enum.at(3)]
            end)

          Map.update(acc, term, rows, &(&1 ++ rows))
        end)
      end)

    rows =
      terms
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.flat_map(fn {term, postings} ->
        Enum.chunk_every(postings, 32) |> Enum.map(&[term, &1])
      end)

    with {:ok, pages} <- semantic_pages(rows), {:ok, packs} <- pack_pages(s, pages) do
      header = %{
        "version" => 1,
        "kind" => "lexical_run_index",
        "recipe" => E.lexical_recipe(),
        "cursor" => s.job["cursor"],
        "page_count" => length(pages),
        "sources" => summaries,
        "packs" => Enum.map(packs, & &1.directory)
      }

      unit = unit(s, "lexr", header)

      if byte_size(json(header)) <= @object_bytes do
        {:ok, %{values: Enum.map(packs, & &1.unit) ++ [unit], header: descriptor(unit)}}
      else
        {:error, :lexical_directory_bound}
      end
    end
  end

  defp semantic_pages(rows) do
    rows =
      if rows == [] do
        [[]]
      else
        rows
      end

    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, pages} ->
      initial = %{
        "version" => 1,
        "kind" => "lexical_postings",
        "ordinal" => length(pages),
        "rows" =>
          if row == [] do
            []
          else
            [row]
          end
      }

      candidate =
        if pages == [] do
          initial
        else
          Map.update!(List.last(pages), "rows", &(&1 ++ [row]))
        end

      cond do
        byte_size(json(initial)) > @page_bytes ->
          {:halt, {:error, :lexical_term_bound}}

        pages == [] ->
          {:cont, {:ok, [initial]}}

        byte_size(json(candidate)) <= @page_bytes and length(candidate["rows"]) <= 128 ->
          {:cont, {:ok, List.replace_at(pages, -1, candidate)}}

        true ->
          {:cont, {:ok, pages ++ [initial]}}
      end
    end)
  end

  defp pack_pages(s, pages) do
    groups =
      Enum.reduce(pages, [], fn page, groups ->
        next =
          if groups == [] do
            [page]
          else
            List.last(groups) ++ [page]
          end

        body = %{"version" => 1, "kind" => "lexical_pack", "pages" => next}

        if groups == [] or byte_size(json(body)) > @object_bytes do
          groups ++ [[page]]
        else
          List.replace_at(groups, -1, next)
        end
      end)

    packs =
      Enum.map(groups, fn pages ->
        body = %{"version" => 1, "kind" => "lexical_pack", "pages" => pages}
        bytes = json(body)

        {refs, _} =
          Enum.map_reduce(pages, 0, fn page, cursor ->
            encoded = json(page)

            {offset, count} =
              :binary.match(bytes, encoded, scope: {cursor, byte_size(bytes) - cursor})

            terms = Enum.map(page["rows"], &hd/1)

            {[
               page["ordinal"],
               offset,
               count,
               E.sha256(encoded),
               List.first(terms),
               List.last(terms)
             ], offset + count}
          end)

        unit = unit(s, "lexp", body)
        %{unit: unit, directory: [unit.sha256, byte_size(bytes), refs]}
      end)

    {:ok, packs}
  end

  defp unit(s, family, body) do
    bytes = json(body)
    hash = E.sha256(bytes)

    %{
      key: family <> "." <> s.profile["partition"] <> "." <> hash,
      value: body,
      sha256: hash,
      byte_count: byte_size(bytes)
    }
  end

  defp descriptor(unit) do
    Map.take(unit, [:key, :sha256, :byte_count])
    |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
  end

  defp query_begin(s) do
    root = s.root_row["value"]

    with true <-
           root["catalog_sha256"] == s.catalog_row["sha256"] and
             root["floor"] == s.catalog_row["value"]["floor"],
         {:ok, terms} <- E.lexical_query_terms(s.args["query"]) do
      s =
        Map.merge(s, %{
          terms: terms,
          pending_groups: root["groups"],
          summaries: [],
          postings: %{},
          index_root: root,
          selected_sources: [],
          pending_pages: [],
          query_group: 0
        })

      query_group(s)
    else
      _ -> error(:lexical_index_stale)
    end
  end

  defp query_group(%{pending_groups: []} = s) do
    rank_postings(s)
  end

  defp query_group(%{pending_groups: [ref | rest]} = s) do
    io(
      %{s | pending_groups: rest},
      :object_read,
      Map.put(ref, "generation", s.native_generation),
      :query_group
    )
  end

  defp query_page(%{pending_pages: []} = s) do
    query_group(s)
  end

  defp query_page(%{pending_pages: [ref | rest]} = s) do
    io(
      Map.merge(s, %{pending_pages: rest, page_expected: ref}),
      :page_read,
      %{
        "ref" => Map.take(ref, ~w(key object_sha256 offset byte_count sha256)),
        "generation" => s.native_generation
      },
      :query_page
    )
  end

  defp rank_postings(s) do
    if length(s.summaries) != s.index_root["sources"] or
         Enum.reduce(s.summaries, 0, &(Enum.at(&1, 9) + &2)) != s.index_root["chunks"] do
      error(:lexical_population_mismatch)
    else
      active =
        s.summaries
        |> Enum.with_index()
        |> Enum.filter(fn {summary, _} -> eligible?(summary, s.args["as_of_ms"]) end)
        |> Map.new(fn {summary, i} -> {i, summary} end)

      n = Enum.reduce(active, 0, fn {_, summary}, n -> n + Enum.at(summary, 9) end)
      tokens = Enum.reduce(active, 0, fn {_, summary}, n -> n + Enum.at(summary, 10) end)

      avg =
        if n == 0 do
          1.0
        else
          max(tokens / n, 1.0)
        end

      dfs =
        Map.new(s.terms, fn term ->
          {term,
           Enum.count(s.postings, fn {{source, _}, p} ->
             Map.has_key?(active, source) and Map.has_key?(p.terms, term)
           end)}
        end)

      ranked =
        s.postings
        |> Enum.filter(fn {{source, _}, _} -> Map.has_key?(active, source) end)
        |> Enum.map(fn {{source, chunk}, p} ->
          summary = active[source]

          %{
            source: source,
            chunk: chunk,
            score: score(s.terms, p.terms, p.length, n, avg, dfs),
            length: p.length,
            terms: Map.new(s.terms, &{&1, Map.get(p.terms, &1, 0)}),
            summary: summary
          }
        end)
        |> Enum.filter(&(&1.score > 0))
        |> Enum.sort_by(&{-&1.score, Enum.at(&1.summary, 0), &1.chunk})
        |> Enum.take(s.args["top_k"])

      keys = Enum.map(ranked, &Enum.at(&1.summary, 0)) |> Enum.uniq()

      s =
        Map.merge(s, %{
          ranked: ranked,
          query_stats: %{"chunks" => n, "tokens" => tokens, "dfs" => dfs},
          pending_selections: Enum.chunk_every(keys, 8),
          active: active
        })

      hydrate(s)
    end
  end

  defp hydrate(%{pending_selections: []} = s) do
    io(s, :value_read, %{"key" => catalog_key(s)}, :query_final)
  end

  defp hydrate(%{pending_selections: [keys | rest]} = s) do
    io(
      %{s | pending_selections: rest},
      :selected_keys,
      %{"source_keys" => keys, "as_of_ms" => s.args["as_of_ms"]},
      :hydrated
    )
  end

  defp score(terms, tf, length, n, avg, dfs) do
    Enum.reduce(terms, 0.0, fn term, total ->
      count = Map.get(tf, term, 0)

      total +
        :math.log(1.0 + (n - dfs[term] + 0.5) / (dfs[term] + 0.5)) * count * 2.2 /
          (count + 1.2 * (0.25 + 0.75 * length / avg))
    end)
  end

  defp eligible?(s, now) do
    Enum.at(s, 6) <= now and (Enum.at(s, 7) == nil or Enum.at(s, 7) > now) and not Enum.at(s, 8)
  end

  defp posting_row?([term, rows], sources) do
    is_binary(term) and term != "" and is_list(rows) and length(rows) in 1..32 and
      Enum.all?(rows, fn
        [source, chunk, tf, length] ->
          is_integer(source) and source in 0..(sources - 1) and is_integer(chunk) and
            chunk in 0..31 and E.safe_positive?(tf) and E.safe_positive?(length) and tf <= length and
            length <= 65536

        _ ->
          false
      end)
  end

  defp posting_row?(_, _) do
    false
  end

  defp run_header?(h, s) do
    exact?(h, ~w(version kind recipe cursor page_count sources packs)) and h["version"] === 1 and
      h["kind"] == "lexical_run_index" and h["recipe"] == E.lexical_recipe() and
      E.safe_uint?(h["cursor"]) and is_list(h["sources"]) and length(h["sources"]) in 1..@group and
      Enum.all?(h["sources"], &summary?/1) and is_list(h["packs"]) and
      length(h["packs"]) in 1..128 and Enum.all?(h["packs"], &pack_ref?/1) and
      is_integer(h["page_count"]) and h["page_count"] in 1..16_384 and
      Enum.flat_map(h["packs"], fn [_, _, refs] -> Enum.map(refs, &hd/1) end) ==
        Enum.to_list(0..(h["page_count"] - 1)) and
      ordered_ranges?(Enum.flat_map(h["packs"], &Enum.at(&1, 2))) and
      Enum.all?(h["sources"], &(Enum.at(&1, 0) != nil and s.profile["partition"] != ""))
  end

  defp summary?([
         key,
         id,
         generation,
         content,
         bundle,
         revision,
         observed,
         expiry,
         historical,
         chunks,
         tokens,
         gap
       ]) do
    E.sha256?(key) and is_binary(id) and E.sha256(id) == key and E.safe_positive?(generation) and
      E.sha256?(content) and E.sha256?(bundle) and E.safe_positive?(revision) and
      E.safe_uint?(observed) and (is_nil(expiry) or E.safe_uint?(expiry)) and
      is_boolean(historical) and chunks in 1..32 and E.safe_uint?(tokens) and
      (gap == nil or is_map(gap))
  end

  defp summary?(_) do
    false
  end

  defp pack_ref?([hash, bytes, refs]) do
    E.sha256?(hash) and is_integer(bytes) and bytes in 2..@object_bytes and is_list(refs) and
      length(refs) in 1..128 and
      Enum.all?(refs, fn
        [ordinal, offset, count, sha, first, last] ->
          E.safe_uint?(ordinal) and E.safe_uint?(offset) and is_integer(count) and
            count in 2..@page_bytes and
            offset + count <= bytes and E.sha256?(sha) and
            ((first == nil and last == nil) or
               (is_binary(first) and is_binary(last) and first <= last))

        _ ->
          false
      end)
  end

  defp pack_ref?(_) do
    false
  end

  defp ordered_ranges?([[_ordinal, _offset, _bytes, _hash, first, last]]),
    do: (is_nil(first) and is_nil(last)) or (is_binary(first) and is_binary(last))

  defp ordered_ranges?([[_, _, _, _, first, last], [_, _, _, _, next_first, _] = next | rest]),
    do:
      is_binary(first) and is_binary(last) and is_binary(next_first) and last <= next_first and
        ordered_ranges?([next | rest])

  defp root?(r, s) do
    exact?(
      r,
      ~w(version kind recipe job_id generation catalog_sha256 catalog_generation floor sources chunks groups)
    ) and r["version"] === 1 and r["kind"] == "lexical_index" and
      r["recipe"] == E.lexical_recipe() and id?(r["job_id"]) and E.safe_positive?(r["generation"]) and
      E.sha256?(r["catalog_sha256"]) and
      Enum.all?(~w(catalog_generation floor sources chunks), &E.safe_uint?(r[&1])) and
      r["sources"] <= 1000 and r["chunks"] <= 10000 and is_list(r["groups"]) and
      length(r["groups"]) == div(r["sources"] + @group - 1, @group) and
      Enum.all?(r["groups"], &object_ref?(&1, s, "lexr"))
  end

  defp job?(j, s) do
    epoch_fields = if j["version"] === 2, do: ["maintenance_epoch"], else: []

    exact?(
      j,
      ~w(version kind id status catalog catalog_sha256 cursor unit groups root_revision index_generation) ++
        epoch_fields
    ) and job_epoch_valid?(j) and j["kind"] == "lexical_job" and id?(j["id"]) and
      j["status"] in ~w(building aborted) and C.valid_catalog?(j["catalog"], s.profile) and
      E.sha256?(j["catalog_sha256"]) and E.sha256(json(j["catalog"])) == j["catalog_sha256"] and
      E.safe_uint?(j["cursor"]) and j["cursor"] <= j["catalog"]["sources"] and
      (rem(j["cursor"], @group) == 0 or j["cursor"] == j["catalog"]["sources"]) and
      E.safe_uint?(j["unit"]) and E.safe_uint?(j["root_revision"]) and
      E.safe_positive?(j["index_generation"]) and is_list(j["groups"]) and
      length(j["groups"]) == div(j["cursor"] + @group - 1, @group) and
      Enum.all?(j["groups"], &object_ref?(&1, s, "lexr"))
  end

  defp object_ref?(r, s, family) do
    exact?(r, ~w(key sha256 byte_count)) and E.sha256?(r["sha256"]) and
      r["key"] == family <> "." <> s.profile["partition"] <> "." <> r["sha256"] and
      is_integer(r["byte_count"]) and r["byte_count"] in 2..@object_bytes
  end

  defp token?(t) do
    epoch_fields =
      case t["version"] do
        3 -> ["maintenance_epoch"]
        4 -> ~w(maintenance_epoch retirement_epoch)
        _ -> []
      end

    exact?(t, ~w(version job_id job_revision work write stages unit) ++ epoch_fields) and
      token_epoch_valid?(t) and
      E.safe_uint?(t["unit"]) and t["unit"] <= 128 and
      id?(t["job_id"]) and E.safe_positive?(t["job_revision"]) and
      ((t["version"] in [2, 3] and t["work"] in ~w(unit job root catalog publish)) or
         (t["version"] === 4 and t["work"] == "retire" and t["stages"] === %{} and
            t["unit"] === 0 and is_map(t["write"]))) and
      (is_nil(t["write"]) or is_map(t["write"])) and is_map(t["stages"]) and
      Enum.all?(Map.keys(t["stages"]), &(&1 in ~w(root catalog)))
  end

  defp job_epoch_valid?(%{"version" => 1}), do: true

  defp job_epoch_valid?(%{"version" => 2, "maintenance_epoch" => epoch}),
    do: E.safe_positive?(epoch)

  defp job_epoch_valid?(_), do: false

  defp token_epoch_valid?(%{"version" => 2}), do: true

  defp token_epoch_valid?(%{"version" => 3, "maintenance_epoch" => epoch}),
    do: E.safe_positive?(epoch)

  defp token_epoch_valid?(%{
         "version" => 4,
         "maintenance_epoch" => epoch,
         "retirement_epoch" => retirement
       }),
       do: E.safe_uint?(epoch) and E.safe_uint?(retirement) and retirement >= epoch

  defp token_epoch_valid?(_), do: false

  defp continuation_epoch?(nil, _, _), do: true

  defp continuation_epoch?(%{"version" => 4} = token, "abort", epoch),
    do: token["retirement_epoch"] === epoch

  defp continuation_epoch?(%{"version" => 4}, _, _), do: false

  defp continuation_epoch?(token, action, epoch),
    do: token_epoch(token) === epoch or (action == "abort" and token_epoch(token) < epoch)

  defp job_epoch(job), do: Map.get(job, "maintenance_epoch", 0)
  defp token_epoch(token), do: Map.get(token, "maintenance_epoch", 0)

  defp coverage(s) do
    %{
      "reads_used" => s.reads,
      "effects_used" => s.effects,
      "namespace_complete" => false,
      "population_qualified" => false,
      "method" => "bm25"
    }
  end

  defp catalog_key(s) do
    "catalog." <> s.profile["partition"]
  end

  defp root_key(s) do
    "lexical." <> s.profile["partition"]
  end

  defp job_key(s) do
    "lexjob." <> s.profile["partition"]
  end

  defp random_id do
    Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end

  defp id?(s) do
    is_binary(s) and Regex.match?(~r/\A[0-9a-f]{32}\z/, s)
  end

  defp revision(nil) do
    0
  end

  defp revision(row) do
    row["revision"]
  end

  defp json(value) do
    IO.iodata_to_binary(JSON.encode!(value))
  end

  defp exact?(map, keys) do
    is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
  end

  defp error(code) do
    {:done, {:error, code, %{}}}
  end
end
