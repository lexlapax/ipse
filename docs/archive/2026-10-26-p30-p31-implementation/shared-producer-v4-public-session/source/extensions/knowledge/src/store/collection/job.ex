defmodule IpseKnowledge.Store.Collection.Job do
  @moduledoc """
  Explicit bounded shared-generation jobs using existing Collection stages.

  Each continuation consumes at most one immutable value, or prepares the two
  metadata values and switches job plus captured catalog atomically. No metadata
  write falls back to untimed inline publication. Interrupted effects return no
  continuation and are never replayed. Explicit finalization reduces bounded
  manifest batches and entity runs before selecting root/job/catalog together.
  """
  alias IpseKnowledge.Evidence, as: E
  alias IpseKnowledge.Store.Collection, as: C
  alias IpseKnowledge.Store.Collection.Directory
  alias IpseKnowledge.Store.Collection.Finalization

  @fields ~w(version kind id partition status catalog catalog_sha256 generation root_revision root_sha256 vector_selection fact_selection cursor summaries facts)
  @token ~w(version id plan_sha256 job_revision root_revision catalog_sha256 unit write stages)

  def start(profile, args) do
    with true <- exact?(args, ~w(action vector_selection fact_selection continuation group)),
         true <- args["action"] in ~w(begin inspect append abort finalize finalize_paged),
         true <-
           IpseKnowledge.Store.Collection.Projection.valid_selection?(args["vector_selection"]) and
             IpseKnowledge.Store.Collection.Projection.valid_extraction?(args["fact_selection"]),
         true <- is_nil(args["continuation"]) or token?(args["continuation"]),
         true <-
           args["action"] not in ~w(append abort finalize finalize_paged) or
             is_map(args["continuation"]),
         true <-
           if(args["action"] == "append", do: is_map(args["group"]), else: is_nil(args["group"])) do
      s = %{profile: profile, args: args, reads: 0, effects: 0, stages: [], unit: 0, write: nil}
      io(s, :value_read, %{"key" => catalog_key(profile)}, :catalog)
    else
      _ -> error(:invalid_generation_job_request)
    end
  rescue
    _ -> error(:invalid_generation_job_request)
  end

  def resume(%{generation_job: s, inner: inner}, outcome),
    do: advance(C.resume(inner, outcome), s)

  @doc """
  Project a validated job result without repeating its complete durable value.

  This is presentation only. The logical value digest covers the entire job;
  it is not a physical packed-record hash, read capability or replay permission.
  Continuations and existing outcome/coverage fields remain exact. Invalid
  internal job data raises rather than reporting a known refusal after an effect.
  """
  def compact_result(value) when is_map(value) do
    progress =
      case value["job"] do
        nil ->
          nil

        job ->
          true = valid?(job, %{"partition" => job["partition"]})
          bytes = json(job)
          reduction = job["reduction"]

          reduction =
            if reduction do
              Map.take(
                reduction,
                ~w(phase batch entities text_bytes chunks facts digest_cursor verified_entities)
              )
              |> Map.merge(
                Map.new(~w(manifests runs entity_pages positions), fn key ->
                  {key <> "_count", length(Map.get(reduction, key, []))}
                end)
              )
            end

          job
          |> Map.take(
            ~w(id partition status generation catalog_sha256 root_revision root_sha256 cursor facts)
          )
          |> Map.merge(%{
            "version" => 1,
            "kind" => "shared_generation_progress",
            "job_schema_version" => job["version"],
            "value_sha256" => E.sha256(bytes),
            "value_bytes" => byte_size(bytes),
            "vector_selection_sha256" => E.sha256(json(job["vector_selection"])),
            "fact_selection_sha256" => E.sha256(json(job["fact_selection"])),
            "source_count" => job["catalog"]["sources"],
            "summary_count" => length(job["summaries"]),
            "reduction" => reduction
          })
      end

    value
    |> Map.delete("job")
    |> Map.put("job_progress", progress)
    |> Map.put("representation", "compact_v1")
  end

  @doc false
  def append_plan(job, plan, bundles, page) do
    profile = %{"kind" => "collection", "scope" => "project", "partition" => job["partition"]}

    with true <-
           valid?(job, profile) and job["status"] == "groups" and
             job["cursor"] < job["catalog"]["sources"],
         cursor = job["cursor"],
         expected = %{
           "cursor" => cursor,
           "vector_selection" => job["vector_selection"],
           "fact_selection" => job["fact_selection"]
         },
         {:ok, summary} <- Directory.capture(job["partition"], plan, bundles, expected),
         true <- summary["header"]["sources"] == min(8, job["catalog"]["sources"] - cursor),
         page_no = div(cursor, 16),
         true <-
           C.valid_catalog_page?(
             %{"value" => page, "sha256" => E.sha256(json(page))},
             Enum.at(job["catalog"]["pages"], page_no),
             page_no,
             profile
           ),
         rows = Enum.slice(page["rows"], rem(cursor, 16), summary["header"]["sources"]),
         true <- Enum.map(summary["sources"], &Map.take(&1, ~w(source_key head_sha256))) === rows,
         bytes = json(summary),
         true <- byte_size(bytes) <= 48 * 1024,
         sha = E.sha256(bytes),
         ref = %{
           "key" => "gensum.#{job["partition"]}." <> sha,
           "sha256" => sha,
           "byte_count" => byte_size(bytes)
         },
         next =
           job
           |> Map.put("cursor", cursor + length(rows))
           |> Map.update!("summaries", &(&1 ++ [ref]))
           |> Map.update!("facts", &(&1 + summary["header"]["facts"])),
         next =
           if(next["cursor"] == job["catalog"]["sources"],
             do: Map.put(next, "status", "manifests"),
             else: next
           ),
         true <- valid?(next, profile) do
      values =
        Enum.map(plan.values ++ [plan.header_unit], &%{key: &1.key, value: &1.value}) ++
          [%{key: ref["key"], value: summary}]

      {:ok, %{job: next, values: values}}
    else
      _ -> {:error, :invalid_generation_group}
    end
  rescue
    _ -> {:error, :invalid_generation_group}
  end

  defp io(s, op, args, phase),
    do: advance(C.start(s.profile, op, args), Map.put(s, :phase, phase))

  defp advance({:call, request, inner}, s) do
    read = C.read_request?(request)
    reads = s.reads + if(read, do: 1, else: 0)
    effects = s.effects + if(read, do: 0, else: 1)

    if reads <= 512 and effects <= 16 do
      {:call, request, %{generation_job: %{s | reads: reads, effects: effects}, inner: inner}}
    else
      error(:generation_job_budget)
    end
  end

  defp advance({:done, {:ok, value}}, s) do
    done(s, value)
  rescue
    _ -> error(:generation_job_changed)
  end

  defp advance({:done, {:continue, value}}, s), do: pause(%{s | write: value["continuation"]})
  defp advance({:done, {:error, code, _}}, _), do: error(code)
  defp advance({:stop, :unknown_effect}, _), do: {:stop, :unknown_effect}

  defp done(%{phase: :catalog} = s, value) do
    row = value["record"]
    true = is_map(row) and C.valid_catalog?(row["value"], s.profile)

    io(
      Map.merge(s, %{catalog_row: row, boot_generation: value["native_generation"]}),
      :value_read,
      %{"key" => root_key(s.profile)},
      :root
    )
  end

  defp done(%{phase: :root} = s, value) do
    true = value["native_generation"] === s.boot_generation
    row = value["record"]

    true =
      is_nil(row) or
        Directory.valid_root?(
          row["value"],
          Map.take(
            row["value"],
            ~w(generation catalog_sha256 catalog_generation floor vector_selection fact_selection)
          )
          |> Map.put("root_sha256", row["sha256"])
        )

    io(Map.put(s, :root_row, row), :value_read, %{"key" => job_key(s.profile)}, :job)
  end

  defp done(%{phase: :job} = s, value) do
    true = value["native_generation"] === s.boot_generation
    row = value["record"]
    true = is_nil(row) or valid?(row["value"], s.profile)
    s = Map.put(s, :job_row, row)

    if s.args["action"] == "inspect" do
      {:done,
       {:ok,
        %{
          "job" => if(row, do: row["value"], else: nil),
          "continuation" =>
            if(row, do: inspection_token(row["value"], row["revision"]), else: nil),
          "stale" =>
            row != nil and
              (row["value"]["catalog_sha256"] != s.catalog_row["sha256"] or
                 not current_root?(row["value"], s.root_row)),
          "coverage" => coverage(s)
        }}}
    else
      plan(s)
    end
  end

  defp done(%{phase: :existing} = s, value) do
    row = value["record"]
    unit = Enum.at(s.units, s.unit)

    cond do
      row == nil ->
        prepare(s, unit, 0)

      row["value"] === unit.value and row["sha256"] === E.sha256(json(unit.value)) ->
        pause(%{s | unit: s.unit + 1, write: nil})

      true ->
        error(:generation_value_conflict)
    end
  end

  defp done(%{phase: :prepared} = s, value) do
    ref = value["stage"]
    true = is_map(ref)

    if s.unit < s.immutable do
      io(Map.put(s, :consuming, ref), :value_commit, %{"stages" => [ref]}, :consumed)
    else
      prepare_next(%{s | stages: s.stages ++ [ref], unit: s.unit + 1, write: nil})
    end
  end

  defp done(%{phase: :consumed} = s, _), do: pause(%{s | unit: s.unit + 1, write: nil})

  defp done(%{phase: :verified, verify: [{ref, unit} | tail]} = s, value) do
    stage = value["stage"]
    bytes = json(unit.value)

    true =
      stage["slot"] === ref["slot"] and stage["epoch"] === ref["epoch"] and
        stage["state"] == "sealed" and stage["key"] === unit.key

    true =
      stage["sha256"] === E.sha256(bytes) and stage["byte_count"] === byte_size(bytes) and
        stage["offset"] === byte_size(bytes) and stage["expected_revision"] === unit.revision

    epoch = Map.get(s, :final_generation, value["generation"])
    true = value["generation"] === epoch
    verify(s |> Map.put(:final_generation, epoch) |> Map.put(:verify, tail))
  end

  defp done(%{phase: :prerequisite, prerequisites: [unit | tail]} = s, value) do
    row = value["record"]
    proof = unit_proof(unit)

    if value["generation"] === s.check_generation and value["key"] === unit.key and is_map(row) and
         row["sha256"] === proof.sha256 and row["byte_count"] === proof.byte_count do
      prerequisites(%{s | prerequisites: tail})
    else
      error(:generation_prerequisite_missing)
    end
  end

  defp done(%{phase: :reduction_input, needed: ref} = s, value) do
    row = value["record"]
    true = value["native_generation"] === s.boot_generation and is_map(row)
    true = row["sha256"] === ref["sha256"]

    true =
      not Map.has_key?(ref, "byte_count") or byte_size(json(row["value"])) === ref["byte_count"]

    plan(Map.update!(s, :reduction_values, &Map.put(&1, ref["key"], row["value"])))
  end

  defp done(%{phase: :committed} = s, value) do
    {:done,
     {:ok,
      %{
        "status" => s.next_job["status"],
        "job" => s.next_job,
        "continuation" => base_token(s, value["native_generation"], 0, nil, []),
        "coverage" => Map.put(coverage(s), "selected_changed", s.metadata_count == 3)
      }}}
  end

  defp plan(%{args: %{"action" => action}} = s) when action in ~w(finalize finalize_paged) do
    row = s.job_row
    token = s.args["continuation"]

    true =
      is_map(row) and token["id"] === row["value"]["id"] and
        token["job_revision"] === revision(row)

    true =
      token["root_revision"] === row["value"]["root_revision"] and
        token["catalog_sha256"] === row["value"]["catalog_sha256"]

    true = row["value"]["catalog_sha256"] === s.catalog_row["sha256"]

    true =
      row["value"]["root_revision"] === revision(s.root_row) and
        row["value"]["root_sha256"] === if(s.root_row, do: s.root_row["sha256"], else: nil)

    true =
      row["value"]["vector_selection"] === s.args["vector_selection"] and
        row["value"]["fact_selection"] === s.args["fact_selection"]

    s = Map.put_new(s, :reduction_values, %{})

    case Finalization.plan(row["value"], s.reduction_values, action == "finalize_paged") do
      {:need, ref} ->
        io(Map.put(s, :needed, ref), :value_read, %{"key" => ref["key"]}, :reduction_input)

      {:ok, planned} ->
        extra =
          if planned.root,
            do: [%{key: root_key(s.profile), value: planned.root, revision: revision(s.root_row)}],
            else: []

        proofs =
          Enum.map(planned.prerequisites, fn r ->
            %{key: r["key"], sha256: r["sha256"], byte_count: r["byte_count"]}
          end)

        finish_plan(s, planned.job, planned.values, extra, proofs)

      {:error, code} ->
        error(code)
    end
  end

  defp plan(s) do
    token = s.args["continuation"]
    action = s.args["action"]
    row = s.job_row

    {next, immutable} =
      cond do
        action == "begin" ->
          true = is_nil(row) or row["value"]["status"] in ~w(aborted selected)

          true =
            is_nil(token) or
              (is_binary(token["plan_sha256"]) and token["job_revision"] === revision(row))

          id =
            if(token,
              do: token["id"],
              else: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
            )

          job = %{
            "version" => 1,
            "kind" => "shared_generation_job",
            "id" => id,
            "partition" => s.profile["partition"],
            "status" => "groups",
            "catalog" => s.catalog_row["value"],
            "catalog_sha256" => s.catalog_row["sha256"],
            "generation" => if(s.root_row, do: s.root_row["value"]["generation"] + 1, else: 1),
            "root_revision" => revision(s.root_row),
            "root_sha256" => if(s.root_row, do: s.root_row["sha256"], else: nil),
            "vector_selection" => s.args["vector_selection"],
            "fact_selection" => s.args["fact_selection"],
            "cursor" => 0,
            "summaries" => [],
            "facts" => 0
          }

          {job, []}

        action in ~w(append abort) ->
          true =
            is_map(row) and token["id"] == row["value"]["id"] and
              token["job_revision"] == revision(row)

          true =
            token["root_revision"] === row["value"]["root_revision"] and
              token["catalog_sha256"] === row["value"]["catalog_sha256"]

          true =
            row["value"]["vector_selection"] === s.args["vector_selection"] and
              row["value"]["fact_selection"] === s.args["fact_selection"]

          if action == "abort" do
            true = row["value"]["status"] not in ~w(aborted selected)
            {Map.put(row["value"], "status", "aborted"), []}
          else
            true = row["value"]["catalog_sha256"] === s.catalog_row["sha256"]

            true =
              row["value"]["root_revision"] === revision(s.root_row) and
                row["value"]["root_sha256"] ===
                  if(s.root_row, do: s.root_row["sha256"], else: nil)

            group = s.args["group"]
            true = exact?(group, ~w(plan bundles catalog_page))

            {:ok, planned} =
              append_plan(row["value"], group["plan"], group["bundles"], group["catalog_page"])

            {planned.job, planned.values}
          end
      end

    finish_plan(s, next, immutable, [], [])
  end

  defp finish_plan(s, next, immutable, extra, proofs) do
    token = s.args["continuation"]
    action = s.args["action"]
    row = s.job_row
    true = valid?(next, s.profile)

    units =
      immutable ++
        [
          %{key: job_key(s.profile), value: next, revision: revision(row)},
          %{
            key: catalog_key(s.profile),
            value: s.catalog_row["value"],
            revision: s.catalog_row["revision"]
          }
        ] ++ extra

    plan_body =
      %{
        "units" =>
          Enum.map(units, fn u ->
            %{"key" => u.key, "value" => u.value, "revision" => Map.get(u, :revision, 0)}
          end)
      }

    plan_body =
      if proofs == [],
        do: plan_body,
        else:
          Map.put(
            plan_body,
            "prerequisites",
            Enum.map(
              proofs,
              &%{"key" => &1.key, "sha256" => &1.sha256, "byte_count" => &1.byte_count}
            )
          )

    plan_sha =
      E.sha256(json(plan_body))

    s =
      Map.merge(s, %{
        next_job: next,
        units: units,
        immutable: length(immutable),
        metadata_count: 2 + length(extra),
        prerequisite_refs: proofs,
        plan_sha: plan_sha,
        job_revision: revision(row)
      })

    if token && token["plan_sha256"] != nil &&
         (action != "abort" or token["plan_sha256"] === plan_sha) do
      true =
        token["plan_sha256"] === plan_sha and token["root_revision"] === next["root_revision"] and
          token["catalog_sha256"] === s.catalog_row["sha256"]

      true = token["unit"] <= length(units)
      s = %{s | unit: token["unit"], write: token["write"], stages: token["stages"]}
      true = length(s.stages) == max(s.unit - length(immutable), 0)
      prepare_next(s)
    else
      prepare_next(s)
    end
  end

  defp prepare_next(s) do
    if s.unit >= s.immutable and not Map.get(s, :prerequisites_checked, false) do
      prerequisites(
        Map.merge(s, %{
          prerequisites: Enum.take(s.units, s.immutable) ++ s.prerequisite_refs,
          check_generation: s.boot_generation,
          after_prerequisites: :metadata
        })
      )
    else
      continue_prepare(s)
    end
  end

  defp continue_prepare(%{unit: unit, units: units} = s) when unit == length(units),
    do: verify(Map.put(s, :verify, Enum.zip(s.stages, Enum.drop(units, s.immutable))))

  defp continue_prepare(s) do
    unit = Enum.at(s.units, s.unit)

    if s.unit < s.immutable and s.write == nil do
      io(s, :value_read, %{"key" => unit.key}, :existing)
    else
      prepare(s, unit, Map.get(unit, :revision, 0))
    end
  end

  defp prepare(s, unit, revision) do
    io(
      s,
      :value_prepare,
      %{
        "key" => unit.key,
        "value" => unit.value,
        "expected_revision" => revision,
        "reuse" => false,
        "continuation" => s.write,
        "reads_used" => s.reads,
        "effects_used" => s.effects
      },
      :prepared
    )
  end

  defp verify(%{verify: [{ref, _} | _]} = s),
    do: io(s, :stage_inspect, %{"ref" => ref}, :verified)

  defp verify(%{verify: []} = s) do
    true = length(s.stages) == s.metadata_count

    prerequisites(
      Map.merge(s, %{
        prerequisites: Enum.take(s.units, s.immutable) ++ s.prerequisite_refs,
        check_generation: s.final_generation,
        after_prerequisites: :commit
      })
    )
  end

  defp prerequisites(%{prerequisites: [unit | _]} = s),
    do:
      io(s, :value_stat, %{"key" => unit.key, "generation" => s.check_generation}, :prerequisite)

  defp prerequisites(%{prerequisites: [], after_prerequisites: :metadata} = s),
    do: continue_prepare(Map.put(s, :prerequisites_checked, true))

  defp prerequisites(%{prerequisites: [], after_prerequisites: :commit} = s),
    do:
      io(
        s,
        :value_commit_at,
        %{"stages" => s.stages, "generation" => s.check_generation},
        :committed
      )

  defp pause(s),
    do:
      {:done,
       {:continue,
        %{
          "status" => "staged_generation",
          "continuation" => base_token(s, s.job_revision, s.unit, s.write, s.stages),
          "coverage" => coverage(s)
        }}}

  defp base_token(s, revision, unit, write, stages),
    do: %{
      "version" => 1,
      "id" => s.next_job["id"],
      "plan_sha256" => if(revision == s.job_revision, do: s.plan_sha, else: nil),
      "job_revision" => revision,
      "root_revision" => s.next_job["root_revision"],
      "catalog_sha256" => s.next_job["catalog_sha256"],
      "unit" => unit,
      "write" => write,
      "stages" => stages
    }

  defp inspection_token(job, revision),
    do: %{
      "version" => 1,
      "id" => job["id"],
      "plan_sha256" => nil,
      "job_revision" => revision,
      "root_revision" => job["root_revision"],
      "catalog_sha256" => job["catalog_sha256"],
      "unit" => 0,
      "write" => nil,
      "stages" => []
    }

  def valid?(job, profile) do
    ((exact?(job, @fields) and job["version"] === 1) or
       (exact?(job, @fields ++ ["reduction"]) and job["version"] in [2, 3] and
          Finalization.valid?(job["reduction"], job["version"] === 3))) and
      job["kind"] == "shared_generation_job" and
      job["partition"] == profile["partition"] and
      is_binary(job["id"]) and Regex.match?(~r/\A[0-9a-f]{32}\z/, job["id"]) and
      job["status"] in ~w(groups manifests reducing aborted selected) and
      C.valid_catalog?(job["catalog"], profile) and job["catalog"]["sources"] > 0 and
      job["catalog_sha256"] == E.sha256(json(job["catalog"])) and
      E.safe_uint?(job["generation"]) and job["generation"] > 0 and
      E.safe_uint?(job["root_revision"]) and
      (is_nil(job["root_sha256"]) or E.sha256?(job["root_sha256"])) and
      IpseKnowledge.Store.Collection.Projection.valid_selection?(job["vector_selection"]) and
      IpseKnowledge.Store.Collection.Projection.valid_extraction?(job["fact_selection"]) and
      E.safe_uint?(job["cursor"]) and job["cursor"] <= job["catalog"]["sources"] and
      (rem(job["cursor"], 8) == 0 or job["cursor"] == job["catalog"]["sources"]) and
      E.safe_uint?(job["facts"]) and job["facts"] <= 20_000 and is_list(job["summaries"]) and
      length(job["summaries"]) ==
        if(job["version"] in [2, 3] and job["reduction"]["phase"] != "manifests",
          do: 0,
          else: div(job["cursor"] + 7, 8)
        ) and
      Enum.all?(job["summaries"], &reference?/1) and
      (job["status"] != "manifests" or job["cursor"] == job["catalog"]["sources"]) and
      version_shape?(job) and paged_shape?(job) and
      byte_size(json(job)) <= 48 * 1024
  rescue
    _ -> false
  end

  defp token?(t),
    do:
      exact?(t, @token) and t["version"] === 1 and is_binary(t["id"]) and
        Regex.match?(~r/\A[0-9a-f]{32}\z/, t["id"]) and
        (is_nil(t["plan_sha256"]) or E.sha256?(t["plan_sha256"])) and
        E.sha256?(t["catalog_sha256"]) and
        Enum.all?(~w(job_revision root_revision unit), &E.safe_uint?(t[&1])) and
        is_list(t["stages"]) and length(t["stages"]) <= 3 and
        (is_nil(t["write"]) or is_map(t["write"]))

  defp reference?(r),
    do:
      exact?(r, ~w(key sha256 byte_count)) and is_binary(r["key"]) and E.sha256?(r["sha256"]) and
        is_integer(r["byte_count"]) and r["byte_count"] in 2..49_152

  defp revision(nil), do: 0
  defp revision(row), do: row["revision"]
  defp catalog_key(p), do: "catalog." <> p["partition"]
  defp root_key(p), do: "generation." <> p["partition"]
  defp job_key(p), do: "genjob." <> p["partition"]

  defp coverage(s),
    do: %{
      "reads_used" => s.reads,
      "effects_used" => s.effects,
      "selected_changed" => false,
      "model_receipt_provenance" => false,
      "finalization_available" => true
    }

  defp unit_proof(%{value: value}),
    do: %{sha256: E.sha256(json(value)), byte_count: byte_size(json(value))}

  defp unit_proof(unit), do: unit

  defp version_shape?(%{"version" => 1} = job),
    do: job["status"] in ~w(groups manifests aborted selected)

  defp version_shape?(job) do
    r = job["reduction"]

    job["cursor"] == job["catalog"]["sources"] and job["status"] in ~w(reducing aborted selected) and
      r["batch"] <= div(length(job["catalog"]["pages"]) + 7, 8) and
      (r["phase"] == "manifests" or
         (r["batch"] == div(job["cursor"] + 127, 128) and
            r["text_bytes"] == job["catalog"]["extracted_bytes"] and
            r["chunks"] == job["catalog"]["chunks"] and r["facts"] == job["facts"])) and
      (job["status"] == "aborted" or job["status"] == "selected" == (r["phase"] == "selected"))
  end

  defp current_root?(%{"version" => version, "status" => "selected"} = job, row)
       when version in [2, 3] do
    case Finalization.selected_root(job) do
      {:ok, root} ->
        is_map(row) and row["value"] === root and row["sha256"] === E.sha256(json(root))

      _ ->
        false
    end
  end

  defp current_root?(job, row),
    do:
      job["root_revision"] === revision(row) and
        job["root_sha256"] === if(row, do: row["sha256"], else: nil)

  defp paged_shape?(%{"version" => 3} = job) do
    r = job["reduction"]
    p = job["partition"]
    groups = div(job["catalog"]["sources"] + 7, 8)

    Enum.all?(r["manifests"], &IpseKnowledge.Store.Collection.Paged.reference?(p, "genman", &1)) and
      Enum.all?(r["runs"], &IpseKnowledge.Store.Collection.Paged.reference?(p, "genruns", &1)) and
      Enum.all?(
        r["entity_pages"],
        &IpseKnowledge.Store.Collection.Paged.reference?(p, "genent", &1)
      ) and
      (r["phase"] not in ~w(select selected) or
         r["entity_pages_sha256"] ===
           IpseKnowledge.Store.Collection.Paged.commitment(
             r["entity_pages"],
             r["entities"],
             groups
           )) and
      IpseKnowledge.Store.Collection.Paged.native_value?(job)
  end

  defp paged_shape?(_), do: true

  defp exact?(m, keys), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(keys)
  defp json(value), do: IO.iodata_to_binary(JSON.encode!(value))
  defp error(code), do: {:done, {:error, code, %{}}}
end
