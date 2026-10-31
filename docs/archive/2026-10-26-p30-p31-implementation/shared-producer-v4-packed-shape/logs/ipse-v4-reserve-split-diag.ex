defmodule IpseKnowledge.Store.Collection.Producer.Progress do
  @moduledoc """
  Bounded vector-page work items and canonical group assembly.

  Fixed ready slots are progress, never inference authority. Every new work item
  confirms its own pending claim, and unknown effects offer no continuation.
  Facts must be supplied by a separate validated producer before group append.
  """
  alias IpseKnowledge.{Adapters, Evidence, Profiles}
  alias IpseKnowledge.Store.Collection, as: C
  alias IpseKnowledge.Store.Collection.{Directory, Generation, Job, Producer, Projection}
  @recipe "ipse.evidence.shared_producer.pages.v4"
  @common ~w(version kind recipe partition job_id job_revision catalog_sha256 catalog_floor root_revision root_sha256 cursor embedding vector_selection fact_selection source_set_sha256 vector_cursor vector_count previous_ready status page receipts)
  @pending @common ++ ~w(source_bindings inputs)
  @ready @common ++ ~w(claim input_count input_refs_sha256)
  @args ~w(version action embedding job_id job_revision vector_selection fact_selection vector_cursor previous_ready)
  @bound ~w(job_id job_revision catalog_sha256 catalog_floor root_revision root_sha256 cursor embedding vector_selection fact_selection source_set_sha256 vector_count)
  def start(resolved, profile, args) do
    init(resolved, profile, args, :page, nil, nil)
  end

  @doc "Private complete-vector hydration; no unbounded value is returned through Corpus."
  def assemble(resolved, profile, args) do
    init(resolved, profile, args, :assemble, nil, nil)
  end

  @doc "Append one bounded Job unit using explicit validated facts, without a public group payload."
  def append(resolved, profile, args, facts, continuation) do
    init(resolved, profile, args, :append, facts, continuation)
  end

  defp init(resolved, profile, args, mode, facts, token) do
    with true <- exact?(args, @args),
         true <- args["version"] === 2 and args["action"] in ~w(page inspect),
         true <- id?(args["job_id"]) and Evidence.safe_uint?(args["job_revision"]),
         true <- offset?(args["vector_cursor"]),
         true <- previous?(args["previous_ready"], profile["partition"], args["vector_cursor"]),
         true <- Projection.valid_selection?(args["vector_selection"]),
         true <- args["vector_selection"]["dimensions"] === 1024,
         true <- Projection.valid_extraction?(args["fact_selection"]),
         {:ok, embedding} <- Profiles.lookup(resolved, "embedding", args["embedding"]),
         true <-
           embedding["kind"] == "embedding" and
             embedding["profile"] === args["vector_selection"]["profile"] do
      queue =
        ~w(catalog generation genjob) ++
          if mode == :page do
            ["slot"]
          else
            []
          end

      s = %{
        resolved: resolved,
        profile: profile,
        args: args,
        mode: mode,
        facts: facts,
        token: token,
        reads: 0,
        effects: 0,
        rows: %{},
        boot: nil,
        queue: queue,
        anchors: [],
        proofs: [],
        vectors: [],
        receipts: [],
        child: :collection,
        source_bindings: [],
        slots: [],
        pages: []
      }

      read_next(s)
    else
      _ -> error(:invalid_shared_producer_request)
    end
  rescue
    _ -> error(:invalid_shared_producer_request)
  end

  def resume(%{progress: s, inner: inner}, outcome) do
    result =
      if s.child == :adapter do
        Adapters.resume(inner, outcome)
      else
        C.resume(inner, outcome)
      end

    advance(result, s)
  end

  defp io(s, op, args, phase) do
    advance(C.start(s.profile, op, args), Map.merge(s, %{phase: phase, child: :collection}))
  end

  defp object(s, ref, phase) do
    io(s, :object_read, Map.put(ref, "generation", s.boot), phase)
  end

  defp read_at(%{boot: nil} = s, key, phase), do: io(s, :value_read, %{"key" => key}, phase)

  defp read_at(s, key, phase),
    do: io(s, :value_read_at, %{"key" => key, "generation" => s.boot}, phase)

  defp advance({:call, request, inner}, s) do
    read = C.read_request?(request) or request["op"] in ~w(effect.result.read embedding.profile)

    s = %{
      s
      | reads:
          s.reads +
            if read do
              1
            else
              0
            end,
        effects:
          s.effects +
            if read do
              0
            else
              1
            end
    }

    if s.reads <= 512 and s.effects <= 16 do
      {:call, request, %{progress: s, inner: inner}}
    else
      error(:shared_producer_budget)
    end
  end

  defp advance({:done, {:ok, value}}, s) do
    done(s, value)
  rescue
    _ -> error(:shared_producer_changed)
  end

  defp advance({:done, {:continue, value}}, %{phase: :append_unit} = s) do
    {:done, {:continue, Map.put(value, "producer_coverage", coverage(s))}}
  end

  defp advance({:stop, :unknown_effect}, _) do
    {:stop, :unknown_effect}
  end

  defp advance({:done, {:error, code}}, _) do
    error(code)
  end

  defp advance({:done, {:error, code, _}}, _) do
    error(code)
  end

  defp advance(_, _) do
    error(:shared_producer_incomplete_stage)
  end

  defp read_next(%{queue: [name | rest]} = s) do
    key =
      if name == "slot" do
        slot_key(s.profile["partition"], div(s.args["vector_cursor"], 8))
      else
        name <> "." <> s.profile["partition"]
      end

    read_at(%{s | queue: rest}, key, {:anchor, name})
  end

  defp read_next(%{queue: []} = s) do
    catalog = s.rows["catalog"]
    root = s.rows["generation"]
    row = s.rows["genjob"]
    true = is_map(catalog) and C.valid_catalog?(catalog["value"], s.profile)
    true = is_map(row) and Job.valid?(row["value"], s.profile)
    job = row["value"]
    true = job["id"] === s.args["job_id"] and row["revision"] === s.args["job_revision"]
    true = job["status"] == "groups" and job["cursor"] < job["catalog"]["sources"]
    true = job["catalog_sha256"] === catalog["sha256"] and job["catalog"] === catalog["value"]
    true = job["root_revision"] === revision(root) and job["root_sha256"] === sha(root)

    true =
      job["vector_selection"] === s.args["vector_selection"] and
        job["fact_selection"] === s.args["fact_selection"]

    true = is_nil(root) or Directory.valid_root?(root["value"], root_expected(root))

    anchors =
      for name <- ~w(catalog generation genjob) do
        {name <> "." <> s.profile["partition"], s.rows[name]}
      end

    s = Map.merge(s, %{job: job, anchors: anchors, catalog_page: div(job["cursor"], 16)})
    slot = s.rows["slot"]

    cond do
      s.mode == :page and args_inspect?(s) ->
        inspect_slot(s, slot)

      s.mode == :page and slot != nil and pending?(slot["value"], slot_key(s)) ->
        error(:shared_producer_pending_unknown)

      s.mode == :page and slot != nil and not ready?(slot["value"], slot_key(s)) ->
        error(:shared_producer_corrupt)

      s.mode == :page and slot != nil and slot["value"]["job_id"] === job["id"] and
          slot["value"]["cursor"] === job["cursor"] ->
        error(:shared_producer_page_already_completed)

      true ->
        io(
          s,
          :value_read_ref_at,
          Map.put(Enum.at(s.job["catalog"]["pages"], s.catalog_page), "generation", s.boot),
          :catalog_page
        )
    end
  end

  defp done(%{phase: {:anchor, name}} = s, value) do
    true = is_nil(s.boot) or s.boot === value["native_generation"]

    read_next(%{
      s
      | boot: value["native_generation"],
        rows: Map.put(s.rows, name, value["record"])
    })
  end

  defp done(%{phase: :catalog_page} = s, value) do
    true = value["native_generation"] === s.boot

    true =
      C.valid_catalog_page?(
        value["record"],
        Enum.at(s.job["catalog"]["pages"], s.catalog_page),
        s.catalog_page,
        s.profile
      )

    rows =
      Enum.slice(
        value["record"]["value"]["rows"],
        rem(s.job["cursor"], 16),
        min(8, s.job["catalog"]["sources"] - s.job["cursor"])
      )

    s = Map.merge(s, %{group_rows: rows, catalog_value: value["record"]["value"]})

    io(
      s,
      :source_bundles_bound,
      %{
        "source_keys" => Enum.map(rows, & &1["source_key"]),
        "head_hashes" => Map.new(rows, &{&1["source_key"], &1["head_sha256"]}),
        "generation" => s.boot,
        "catalog_record" => s.rows["catalog"],
        "as_of_ms" => System.system_time(:millisecond)
      },
      :bundles
    )
  end

  defp done(%{phase: :bundles} = s, value) do
    true = value["native_generation"] === s.boot
    bundles = value["bundles"]

    true =
      Enum.map(
        bundles,
        &%{
          "source_key" => &1["source"]["source_key"],
          "head_sha256" => Evidence.sha256(json(&1["head"]))
        }
      ) === s.group_rows

    stamps = value["head_stamps"]
    true = is_list(stamps) and length(stamps) === length(bundles)
    s = Map.merge(s, %{bundles: bundles, source_pending: bundles, source_stamps: stamps})

    if eligible?(s) do
      source_next(s)
    else
      error(:shared_producer_ineligible)
    end
  end

  defp done(
         %{phase: :source_binding, source_pending: [bundle | rest], source_stamps: [_ | stamps]} =
           s,
         value
       ) do
    true = value["native_generation"] === s.boot
    row = value["record"]
    true = is_map(row) and row["value"] === bundle["head"]
    source = bundle["source"]

    binding = %{
      "source_key" => source["source_key"],
      "head_revision" => row["revision"],
      "head_sha256" => row["sha256"],
      "bundle_sha256" => bundle["head"]["bundle_sha256"],
      "observed_at_ms" => source["observed_at_ms"],
      "expires_at_ms" => source["expires_at_ms"],
      "historical" => source["origin"]["historical"],
      "chunking_sha256" => Evidence.sha256(json(Map.take(source, ~w(version chunking))))
    }

    source_next(%{
      s
      | source_pending: rest,
        source_stamps: stamps,
        source_bindings: s.source_bindings ++ [binding],
        anchors: s.anchors ++ [{"source.#{s.profile["partition"]}.#{source["source_key"]}", row}]
    })
  end

  defp done(%{phase: :previous_ready} = s, value) do
    true = value["native_generation"] === s.boot
    row = Map.put(value["record"], "key", s.args["previous_ready"]["key"])

    true =
      descriptor(row) === s.args["previous_ready"] and
        ready_work?(row, s, s.args["vector_cursor"] - 8)

    object(
      Map.merge(s, %{previous: row, proofs: s.proofs ++ [row["value"]["page"]]}),
      row["value"]["page"],
      :previous_page
    )
  end

  defp done(%{phase: :previous_page} = s, value) do
    {:ok, _} =
      Generation.unpack_vector_page(
        s.profile["partition"],
        s.job["cursor"],
        s.bundles,
        value["value"],
        s.args["vector_selection"],
        s.args["vector_cursor"] - 8
      )

    reuse(s)
  end

  defp done(%{phase: :reuse_summary} = s, value) do
    old = s.rows["slot"]["value"]
    summary = value["value"]
    true = Directory.valid_summary?(s.profile["partition"], summary, old["cursor"])
    true = terminal_header?(summary["header"], old)
    claim(%{s | proofs: s.proofs ++ [s.reuse_ref]})
  end

  defp done(%{phase: :reuse_manifest} = s, value) do
    reuse_manifest(%{
      s
      | reuse_values: Map.put(s.reuse_values, s.reuse_ref["key"], value["value"]),
        proofs: s.proofs ++ [s.reuse_ref]
    })
  end

  defp done(%{phase: :reuse_header} = s, value) do
    values = Map.put(s.reuse_values, s.reuse_row["header"]["key"], value["value"])

    {:ok, found} =
      Directory.lookup(
        s.reuse_root,
        values,
        Enum.map(s.reuse_row["sources"], &hd/1),
        root_expected(s.rows["generation"])
      )

    [group] = found["groups"]
    true = terminal_header?(group["header_value"], s.rows["slot"]["value"])
    claim(%{s | proofs: s.proofs ++ [s.reuse_row["header"]]})
  end

  defp done(%{phase: :check_row} = s, value) do
    expected =
      if s.after_check == :claim do
        s.rows["slot"]
      else
        s.claim_row
      end

    true = stamp(value["record"]) === stamp(expected)

    s =
      Map.merge(s, %{
        check_generation: value["native_generation"],
        checking: s.anchors ++ [{slot_key(s), expected}] ++ Enum.map(s.proofs, &{&1["key"], &1})
      })

    check(s)
  end

  defp done(%{phase: :checked, checking: [{_, expected} | rest]} = s, value) do
    true = value["generation"] === s.check_generation
    true = match_stamp?(value["record"], expected)
    check(%{s | checking: rest})
  end

  defp done(%{phase: :claimed} = s, value) do
    row = value["record"]

    true =
      row["sha256"] === Evidence.sha256(json(s.claim)) and
        row["revision"] === value["native_generation"]

    infer(Map.put(s, :claim_row, row))
  end

  defp done(%{phase: :inference} = s, value) do
    vectors = value["vectors"]
    true = is_list(vectors) and length(vectors) === length(s.batch)

    true =
      Enum.zip(vectors, s.batch)
      |> Enum.all?(fn {v, i} ->
        Map.take(v, ~w(selection_sha256 profile model dimensions encoding)) ===
          s.args["vector_selection"] and Evidence.current_vector?(v) and
          Evidence.vector_input_matches_chunk?(v, i.value)
      end)

    receipt = value["receipt"]

    true =
      receipt?(receipt) and
        receipt["raw_input_sha256"] === Enum.map(s.batch, &Evidence.sha256(&1.value["text"])) and
        receipt["input_sha256"] === Enum.map(vectors, & &1["input_sha256"])

    infer(%{s | vectors: s.vectors ++ vectors, receipts: s.receipts ++ [receipt]})
  end

  defp done(%{phase: :page_written} = s, value) do
    page = %{
      "key" => s.page_unit.key,
      "sha256" => s.page_unit.sha256,
      "byte_count" => s.page_unit.byte_count
    }

    record = Map.put_new(value["record"], "key", s.page_unit.key)
    true = Map.take(record, ~w(key sha256 byte_count)) === page

    ready =
      ready_value(
        s.claim,
        Map.take(s.claim_row, ~w(revision sha256 operation_id)),
        page,
        s.receipts
      )

    true = ready?(ready, slot_key(s))
    check_row(Map.merge(s, %{ready: ready, proofs: s.proofs ++ [page]}), :ready)
  end

  defp done(%{phase: :ready_written} = s, value) do
    row = value["record"]
    true = row["sha256"] === Evidence.sha256(json(s.ready))
    next = s.args["vector_cursor"] + s.ready["input_count"]

    continuation =
      if next < s.ready["vector_count"] do
        %{s.args | "vector_cursor" => next, "previous_ready" => descriptor(row)}
      else
        nil
      end

    {:done,
     {:ok,
      %{
        "status" => "page_ready",
        "page" => s.ready["page"],
        "ready" => descriptor(row),
        "continuation" => continuation,
        "coverage" =>
          Map.merge(coverage(s), %{
            "all_pages_ready" => next === s.ready["vector_count"],
            "group_complete" => false,
            "fact_production_required" => true
          })
      }}}
  end

  defp done(%{phase: :collect_last_stat} = s, value) do
    true = value["generation"] === s.boot
    ref = Map.put(value["record"], "key", slot_key(s.profile["partition"], s.collect_ordinal))
    true = ref?(ref)
    object(Map.put(s, :collect_ref, ref), ref, :collect_previous_value)
  end

  defp done(%{phase: :collect_previous_value} = s, value) do
    true = value["native_generation"] === s.boot
    collect_ready(s, Map.put(s.collect_ref, "value", value["value"]))
  end

  defp done(%{phase: :collect_page} = s, value) do
    collect_page(%{s | pages: s.pages ++ [value["value"]]})
  end

  defp done(%{phase: :append_inspect} = s, value) do
    io(s, :generation_job, job_args(s, "append", value["continuation"]), :append_unit)
  end

  defp done(%{phase: :append_unit} = s, value) do
    {:done, {:ok, Map.put(value, "producer_coverage", coverage(s))}}
  end

  defp source_next(%{source_pending: [bundle | _], source_stamps: [stamp | _]} = s) do
    row = Map.put(stamp, "value", bundle["head"])
    true = exact?(stamp, ~w(revision sha256 byte_count))
    true = stamp["sha256"] === Evidence.sha256(json(bundle["head"]))
    true = stamp["byte_count"] === byte_size(json(bundle["head"]))
    true = Evidence.safe_uint?(stamp["revision"]) and stamp["revision"] in 1..s.boot
    done(Map.put(s, :phase, :source_binding), %{"record" => row, "native_generation" => s.boot})
  end

  defp source_next(s) do
    true = eligible?(s)
    inputs = group_inputs(s.bundles)

    identities =
      Enum.map(s.bundles, &[&1["source"]["source_key"], Evidence.sha256(json(&1["source"]))])

    s =
      Map.merge(s, %{
        all_inputs: inputs,
        source_set: Evidence.sha256(json(%{"sources" => identities}))
      })

    if s.mode == :page do
      true = s.args["vector_cursor"] < length(inputs)

      if s.args["vector_cursor"] > 0 do
        read_at(s, s.args["previous_ready"]["key"], :previous_ready)
      else
        reuse(s)
      end
    else
      ordinal = div(length(inputs) - 1, 8)

      io(
        Map.put(s, :collect_ordinal, ordinal),
        :value_stat,
        %{"key" => slot_key(s.profile["partition"], ordinal), "generation" => s.boot},
        :collect_last_stat
      )
    end
  end

  defp reuse(s) do
    case s.rows["slot"] do
      nil ->
        claim(s)

      row ->
        old = row["value"]

        cond do
          old["job_id"] === s.job["id"] and old["cursor"] < s.job["cursor"] ->
            ref = Enum.at(s.job["summaries"], div(old["cursor"], 8))
            true = is_map(ref)
            object(Map.put(s, :reuse_ref, ref), ref, :reuse_summary)

          old["job_id"] !== s.job["id"] and s.rows["generation"] != nil ->
            root = s.rows["generation"]["value"]

            s =
              Map.merge(s, %{
                reuse_root: root,
                reuse_values: %{},
                reuse_remaining: root["manifests"]
              })

            reuse_manifest(s)

          true ->
            error(:shared_producer_slot_not_terminal)
        end
    end
  end

  defp reuse_manifest(%{reuse_remaining: [ref | rest]} = s) do
    object(%{s | reuse_remaining: rest} |> Map.put(:reuse_ref, ref), ref, :reuse_manifest)
  end

  defp reuse_manifest(s) do
    old = s.rows["slot"]["value"]
    rows = Enum.flat_map(s.reuse_root["manifests"], &s.reuse_values[&1["key"]]["rows"])
    row = Enum.find(rows, &(&1["cursor"] === old["cursor"]))
    true = is_map(row)
    object(Map.put(s, :reuse_row, row), row["header"], :reuse_header)
  end

  defp claim(s) do
    inputs = Enum.slice(s.all_inputs, s.args["vector_cursor"], 8)

    pending =
      base(s)
      |> Map.merge(%{
        "status" => "pending",
        "page" => nil,
        "receipts" => [],
        "source_bindings" => s.source_bindings,
        "inputs" => refs(inputs)
      })

    true = pending?(pending, slot_key(s))
    true = s.reads + 128 <= 512 and s.effects + 10 <= 16

    placeholder =
      ready_value(
        pending,
        %{
          "revision" => Evidence.safe_integer_max(),
          "sha256" => Evidence.sha256(json(pending)),
          "operation_id" => String.duplicate("a", 32)
        },
        %{
          "key" => "genvec.#{s.profile["partition"]}." <> String.duplicate("a", 64),
          "sha256" => String.duplicate("a", 64),
          "byte_count" => 49152
        },
        Enum.map(Enum.with_index(Enum.chunk_every(pending["inputs"], 2)), fn {rows, index} ->
          %{
            "operation_id" => Integer.to_string(index + 1, 16) |> String.pad_leading(32, "0"),
            "source_sha256" => String.duplicate("a", 64),
            "input_sha256" => Enum.map(rows, &Enum.at(&1, 3)),
            "raw_input_sha256" => Enum.map(rows, &Enum.at(&1, 4))
          }
        end)
      )

    true =
      ready?(placeholder, slot_key(s)) and inline_frame?(slot_key(s), pending) and
        inline_frame?(slot_key(s), placeholder)

    s = Map.merge(s, %{claim: pending, pending_inputs: inputs})
    check_row(s, :claim)
  end

  defp check_row(s, after_check) do
    io(Map.put(s, :after_check, after_check), :value_read, %{"key" => slot_key(s)}, :check_row)
  end

  defp check(%{checking: [{key, _} | _]} = s) do
    io(s, :value_stat, %{"key" => key, "generation" => s.check_generation}, :checked)
  end

  defp check(%{checking: []} = s) do
    if eligible?(s) do
      case s.after_check do
        :claim ->
          io(
            s,
            :value_put_inline_at,
            %{
              "key" => slot_key(s),
              "value" => s.claim,
              "expected_revision" => revision(s.rows["slot"]),
              "generation" => s.check_generation
            },
            :claimed
          )

        :inference ->
          next_inference(s)

        :ready ->
          io(
            s,
            :value_put_inline_at,
            %{
              "key" => slot_key(s),
              "value" => s.ready,
              "expected_revision" => s.claim_row["revision"],
              "generation" => s.check_generation
            },
            :ready_written
          )
      end
    else
      error(:shared_producer_ineligible)
    end
  end

  defp infer(s) do
    check_row(s, :inference)
  end

  defp next_inference(%{pending_inputs: []} = s) do
    {:ok, page} =
      Generation.vector_page(
        s.profile["partition"],
        s.job["cursor"],
        s.bundles,
        s.vectors,
        s.args["vector_selection"],
        s.args["vector_cursor"]
      )

    io(
      Map.put(s, :page_unit, page),
      :value_write,
      %{
        "key" => page.key,
        "value" => page.value,
        "expected_revision" => 0,
        "reuse" => true,
        "continuation" => nil
      },
      :page_written
    )
  end

  defp next_inference(s) do
    {batch, remaining} = Enum.split(s.pending_inputs, 2)

    args = %{
      "profile" => s.args["embedding"],
      "expected_selection_sha256" => s.args["vector_selection"]["selection_sha256"],
      "source_guard" => %{
        "version" => 2,
        "claim_key" => slot_key(s),
        "claim_revision" => s.claim_row["revision"],
        "claim_sha256" => s.claim_row["sha256"],
        "batch_index" => length(s.receipts)
      },
      "inputs" => Enum.map(batch, &Map.take(&1.value, ~w(chunk_id text)))
    }

    advance(
      Adapters.start(s.resolved, :embed, args),
      Map.merge(s, %{batch: batch, pending_inputs: remaining, phase: :inference, child: :adapter})
    )
  end

  defp collect_ready(s, row) do
    true = ready_work?(row, s, s.collect_ordinal * 8)
    s = %{s | slots: [row | s.slots]}
    previous = row["value"]["previous_ready"]

    if s.collect_ordinal == 0 do
      true = is_nil(previous)
      remaining = Enum.map(s.slots, & &1["value"]["page"])
      collect_page(Map.put(s, :remaining_pages, remaining))
    else
      true = ref?(previous)
      true = previous["key"] === slot_key(s.profile["partition"], s.collect_ordinal - 1)
      s = Map.merge(s, %{collect_ordinal: s.collect_ordinal - 1, collect_ref: previous})

      object(s, previous, :collect_previous_value)
    end
  end

  defp collect_page(%{remaining_pages: [ref | rest]} = s) do
    object(%{s | remaining_pages: rest}, ref, :collect_page)
  end

  defp collect_page(s) do
    {:ok, vectors} =
      Generation.unpack_vector_pages(
        s.profile["partition"],
        s.job["cursor"],
        s.bundles,
        s.pages,
        s.args["vector_selection"]
      )

    if s.mode == :assemble do
      {:done,
       {:ok, %{bundles: s.bundles, vectors: vectors, pages: s.pages, coverage: coverage(s)}}}
    else
      true = is_list(s.facts) and length(s.facts) === length(s.bundles)

      {supplied, []} =
        Enum.zip(s.bundles, s.facts)
        |> Enum.map_reduce(vectors, fn {bundle, facts}, remaining ->
          {:ok, chunks} = Evidence.chunks(bundle["source"])
          {selected, remaining} = Enum.split(remaining, length(chunks))

          true =
            exact?(facts, ~w(source_key facts)) and
              facts["source_key"] === bundle["source"]["source_key"]

          {%{
             "source_key" => facts["source_key"],
             "source_bundle_sha256" => Evidence.sha256(json(bundle["source"])),
             "vectors" => selected,
             "facts" => facts["facts"]
           }, remaining}
        end)

      {:ok, plan} =
        Generation.pack_group(
          s.profile["partition"],
          s.job["cursor"],
          s.bundles,
          supplied,
          s.args["vector_selection"],
          s.args["fact_selection"]
        )

      true =
        Enum.filter(plan.values, &(&1.value["kind"] == "shared_vectors")) |> Enum.map(& &1.value) ===
          s.pages

      s =
        Map.put(s, :group, %{
          "plan" => plan,
          "bundles" => s.bundles,
          "catalog_page" => s.catalog_value
        })

      # Job verifies each immutable prerequisite before metadata preparation and
      # again before commit. Reserve both passes and bounded control reads before
      # allowing a stage-producing call, rather than stranding a known stage.
      reserve =
        2 * (length(plan.values) + 2) + 24 +
          anchor_read_extra(Enum.map(~w(catalog generation genjob), &s.rows[&1]), s.token == nil)

      IO.puts("V4_RESERVE_DIAG values=" <> Integer.to_string(length(plan.values)) <> " reads=" <> Integer.to_string(s.reads) <> " reserve=" <> Integer.to_string(reserve))
      if s.reads + reserve > 512 or s.effects + 8 > 16 do
        error(:shared_producer_budget)
      else
        if s.token == nil do
          io(s, :generation_job, job_args(s, "inspect", nil), :append_inspect)
        else
          io(s, :generation_job, job_args(s, "append", s.token), :append_unit)
        end
      end
    end
  end

  defp job_args(s, action, token) do
    %{
      "action" => action,
      "vector_selection" => s.args["vector_selection"],
      "fact_selection" => s.args["fact_selection"],
      "continuation" => token,
      "group" =>
        if action == "append" do
          s.group
        else
          nil
        end
    }
  end

  @doc false
  def anchor_read_extra(rows, inspect_first?) when is_list(rows) and is_boolean(inspect_first?) do
    extra =
      Enum.reduce(rows, 0, fn
        nil, count -> count
        %{"value" => value}, count -> count + max(logical_read_pages(json(value), 0) - 1, 0)
      end)

    extra * if(inspect_first?, do: 2, else: 1)
  end

  defp logical_read_pages("", pages), do: pages

  defp logical_read_pages(bytes, pages) do
    size = read_slice_size(bytes, 0, min(byte_size(bytes), 6144))
    true = size > 0
    logical_read_pages(binary_part(bytes, size, byte_size(bytes) - size), pages + 1)
  end

  defp read_slice_size(bytes, low, high) when low == high, do: utf8_prefix_size(bytes, low)

  defp read_slice_size(bytes, low, high) do
    mid = div(low + high + 1, 2)
    size = utf8_prefix_size(bytes, mid)
    prefix = binary_part(bytes, 0, size)

    if byte_size(Jason.encode!(prefix)) <= 8192,
      do: read_slice_size(bytes, mid, high),
      else: read_slice_size(bytes, low, mid - 1)
  end

  defp utf8_prefix_size(_bytes, 0), do: 0

  defp utf8_prefix_size(bytes, size) do
    if String.valid?(binary_part(bytes, 0, size)),
      do: size,
      else: utf8_prefix_size(bytes, size - 1)
  end

  defp inspect_slot(s, nil) do
    {:done, {:ok, %{"status" => "absent", "continuation" => nil, "coverage" => coverage(s)}}}
  end

  defp inspect_slot(s, row) do
    row = Map.put(row, "key", slot_key(s))
    true = pending?(row["value"], slot_key(s)) or ready?(row["value"], slot_key(s))

    {:done,
     {:ok,
      %{
        "status" =>
          if row["value"]["status"] == "pending" do
            "pending_unknown"
          else
            "page_ready"
          end,
        "ready" => descriptor(row),
        "continuation" => nil,
        "coverage" => coverage(s)
      }}}
  end

  defp base(s) do
    %{
      "version" => 4,
      "kind" => "shared_projection_producer",
      "recipe" => @recipe,
      "partition" => s.profile["partition"],
      "job_id" => s.job["id"],
      "job_revision" => s.rows["genjob"]["revision"],
      "catalog_sha256" => s.job["catalog_sha256"],
      "catalog_floor" => s.job["catalog"]["floor"],
      "root_revision" => s.job["root_revision"],
      "root_sha256" => s.job["root_sha256"],
      "cursor" => s.job["cursor"],
      "embedding" => s.args["embedding"],
      "vector_selection" => s.args["vector_selection"],
      "fact_selection" => s.args["fact_selection"],
      "source_set_sha256" => s.source_set,
      "vector_cursor" => s.args["vector_cursor"],
      "vector_count" => length(s.all_inputs),
      "previous_ready" => s.args["previous_ready"]
    }
  end

  defp ready_value(pending, claim, page, receipts) do
    pending
    |> Map.drop(~w(source_bindings inputs))
    |> Map.merge(%{
      "status" => "ready",
      "claim" => claim,
      "page" => page,
      "receipts" => receipts,
      "input_count" => length(pending["inputs"]),
      "input_refs_sha256" => Evidence.sha256(json(pending["inputs"]))
    })
  end

  defp ready_work?(row, s, offset) do
    value = row && row["value"]
    inputs = Enum.slice(s.all_inputs, offset, 8)

    ready?(value, slot_key(s.profile["partition"], div(offset, 8))) and
      Map.take(value, @bound) === Map.take(base(s), @bound) and value["vector_cursor"] === offset and
      value["input_count"] === length(inputs) and
      value["input_refs_sha256"] === Evidence.sha256(json(refs(inputs))) and
      Enum.flat_map(value["receipts"], & &1["input_sha256"]) ===
        Enum.map(refs(inputs), &Enum.at(&1, 3)) and
      Enum.flat_map(value["receipts"], & &1["raw_input_sha256"]) ===
        Enum.map(refs(inputs), &Enum.at(&1, 4))
  end

  defp terminal_header?(header, ready) do
    Map.take(header, ~w(cursor source_set_sha256 vector_selection fact_selection)) ===
      Map.take(ready, ~w(cursor source_set_sha256 vector_selection fact_selection)) and
      ready["page"] in header["vector_pages"]
  end

  defp group_inputs(bundles) do
    bundles
    |> Enum.with_index()
    |> Enum.flat_map(fn {b, si} ->
      {:ok, chunks} = Evidence.chunks(b["source"])

      Enum.with_index(chunks)
      |> Enum.map(fn {c, ci} ->
        raw = binary_part(b["source"]["text"], c["start_byte"], c["end_byte"] - c["start_byte"])
        true = raw === c["text"]
        %{source: si, chunk: ci, value: c}
      end)
    end)
  end

  defp refs(inputs) do
    Enum.map(inputs, fn i ->
      {:ok, canonical} = Ipse.Extension.canonical_digest([i.value["text"]])

      [
        i.source,
        i.chunk,
        i.value["chunk_id"],
        canonical,
        Evidence.sha256(i.value["text"]),
        i.value["start_byte"],
        i.value["end_byte"]
      ]
    end)
  end

  defp eligible?(s) do
    Enum.all?(s.bundles, &Evidence.current?(&1["source"], System.system_time(:millisecond)))
  end

  defp root_expected(row) do
    Map.take(
      row["value"],
      ~w(generation catalog_sha256 catalog_generation floor vector_selection fact_selection)
    )
    |> Map.put("root_sha256", row["sha256"])
  end

  defp descriptor(nil) do
    nil
  end

  defp descriptor(row) do
    Map.take(row, ~w(key revision sha256 byte_count))
  end

  defp stamp(nil) do
    nil
  end

  defp stamp(row) do
    Map.take(row, ~w(revision sha256 byte_count))
  end

  defp match_stamp?(nil, nil) do
    true
  end

  defp match_stamp?(actual, %{"revision" => _} = expected) do
    stamp(actual) === stamp(expected)
  end

  defp match_stamp?(actual, expected) do
    is_map(actual) and
      Map.take(actual, ~w(sha256 byte_count)) === Map.take(expected, ~w(sha256 byte_count))
  end

  defp revision(nil) do
    0
  end

  defp revision(row) do
    row["revision"]
  end

  defp sha(nil) do
    nil
  end

  defp sha(row) do
    row["sha256"]
  end

  def slot_key(partition, ordinal) do
    "genproducer4.#{partition}.#{ordinal}"
  end

  defp slot_key(s) do
    slot_key(s.profile["partition"], div(s.args["vector_cursor"], 8))
  end

  defp args_inspect?(s) do
    s.args["action"] == "inspect"
  end

  defp offset?(n) do
    is_integer(n) and n in 0..248 and rem(n, 8) == 0
  end

  defp previous?(nil, _, 0) do
    true
  end

  defp previous?(r, partition, offset) do
    offset > 0 and ref?(r) and r["key"] === slot_key(partition, div(offset, 8) - 1)
  end

  defp ref?(r) do
    exact?(r, ~w(key revision sha256 byte_count)) and is_binary(r["key"]) and
      byte_size(r["key"]) <= 96 and Evidence.safe_uint?(r["revision"]) and r["revision"] > 0 and
      Evidence.sha256?(r["sha256"]) and is_integer(r["byte_count"]) and r["byte_count"] in 2..8192
  end

  defp page?(r, partition) do
    exact?(r, ~w(key sha256 byte_count)) and Evidence.sha256?(r["sha256"]) and
      r["key"] === "genvec.#{partition}." <> r["sha256"] and is_integer(r["byte_count"]) and
      r["byte_count"] in 2..49152
  end

  defp id?(v) do
    is_binary(v) and Regex.match?(~r/\A[0-9a-fA-F]{32}\z/, v)
  end

  defp receipt?(r) do
    exact?(r, ~w(operation_id source_sha256 input_sha256 raw_input_sha256)) and
      id?(r["operation_id"]) and Evidence.sha256?(r["source_sha256"]) and
      is_list(r["input_sha256"]) and length(r["input_sha256"]) in 1..2 and
      is_list(r["raw_input_sha256"]) and
      length(r["raw_input_sha256"]) === length(r["input_sha256"]) and
      Enum.all?(r["input_sha256"] ++ r["raw_input_sha256"], &Evidence.sha256?/1)
  end

  defp inline_frame?(key, value) do
    byte_size(json(value)) <= 8192 and
      Ipse.Extension.validate(%{
        "api_version" => 1,
        "kind" => "host_call",
        "request" => %{
          "op" => "collection.store",
          "scope" => "project",
          "request" => %{
            "op" => "value.put_inline",
            "key" => key,
            "expected_revision" => Evidence.safe_integer_max(),
            "byte_count" => byte_size(json(value)),
            "sha256" => Evidence.sha256(json(value)),
            "data" => json(value),
            "generation" => Evidence.safe_integer_max()
          }
        }
      }) == :ok
  end

  def pending?(r, key) do
    exact?(r, @pending) and common?(r, key) and r["status"] == "pending" and
      Producer.valid_record?(
        r
        |> Map.drop(~w(vector_cursor vector_count previous_ready))
        |> Map.put("version", 3)
        |> Map.put("recipe", "ipse.evidence.shared_producer.first_page.v3")
      ) and length(r["inputs"]) === min(8, r["vector_count"] - r["vector_cursor"])
  rescue
    _ -> false
  end

  def ready?(r, key) do
    exact?(r, @ready) and common?(r, key) and r["status"] == "ready" and
      page?(r["page"], r["partition"]) and exact?(r["claim"], ~w(revision sha256 operation_id)) and
      Evidence.safe_uint?(r["claim"]["revision"]) and r["claim"]["revision"] > 0 and
      Evidence.sha256?(r["claim"]["sha256"]) and id?(r["claim"]["operation_id"]) and
      is_integer(r["input_count"]) and
      r["input_count"] === min(8, r["vector_count"] - r["vector_cursor"]) and
      Evidence.sha256?(r["input_refs_sha256"]) and is_list(r["receipts"]) and
      length(r["receipts"]) === div(r["input_count"] + 1, 2) and
      Enum.all?(r["receipts"], &receipt?/1) and
      Enum.map(r["receipts"], &length(&1["input_sha256"])) ===
        Enum.map(Enum.chunk_every(Enum.to_list(1..r["input_count"]), 2), &length/1) and
      length(Enum.uniq_by(r["receipts"], & &1["operation_id"])) === length(r["receipts"])
  rescue
    _ -> false
  end

  defp common?(r, key) do
    r["version"] === 4 and r["kind"] == "shared_projection_producer" and r["recipe"] == @recipe and
      is_binary(r["partition"]) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,15}\z/, r["partition"]) and
      offset?(r["vector_cursor"]) and key === slot_key(r["partition"], div(r["vector_cursor"], 8)) and
      is_integer(r["vector_count"]) and r["vector_count"] in 1..256 and
      r["vector_cursor"] < r["vector_count"] and
      previous?(r["previous_ready"], r["partition"], r["vector_cursor"]) and id?(r["job_id"]) and
      Enum.all?(
        ~w(job_revision catalog_floor root_revision cursor),
        &Evidence.safe_uint?(r[&1])
      ) and rem(r["cursor"], 8) == 0 and r["cursor"] <= 992 and
      Enum.all?(~w(catalog_sha256 source_set_sha256), &Evidence.sha256?(r[&1])) and
      (is_nil(r["root_sha256"]) or Evidence.sha256?(r["root_sha256"])) and
      Projection.valid_selection?(r["vector_selection"]) and
      r["vector_selection"]["dimensions"] === 1024 and
      Projection.valid_extraction?(r["fact_selection"]) and is_binary(r["embedding"]) and
      byte_size(r["embedding"]) in 1..64 and byte_size(json(r)) <= 8192
  end

  defp coverage(s) do
    %{
      "recipe" => @recipe,
      "reads_used" => s.reads,
      "effects_used" => s.effects,
      "model_receipt_provenance" => false,
      "group_complete" => false,
      "selected_changed" => false,
      "retry_available" => false
    }
  end

  defp exact?(r, fields) do
    is_map(r) and Enum.sort(Map.keys(r)) === Enum.sort(fields)
  end

  defp json(v) do
    IO.iodata_to_binary(JSON.encode!(v))
  end

  defp error(code) do
    {:done, {:error, code, %{}}}
  end
end
