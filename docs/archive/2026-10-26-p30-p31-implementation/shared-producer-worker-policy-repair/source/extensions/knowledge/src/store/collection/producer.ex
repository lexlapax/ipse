defmodule IpseKnowledge.Store.Collection.Producer do
  @moduledoc """
  Explicit first shared-vector-page production through registered embeddings.

  A durable pending claim precedes inference. Only the confirming volatile
  invocation proceeds; pending work never provides a retry or adoption token.
  This section does not complete facts, remaining pages or a generation group.
  """
  alias IpseKnowledge.{Adapters, Evidence, Profiles}
  alias IpseKnowledge.Store.Collection, as: C
  alias IpseKnowledge.Store.Collection.{Directory, Generation, Job, Projection}

  @fields ~w(version kind recipe partition job_id job_revision catalog_sha256 catalog_floor root_revision root_sha256 cursor embedding vector_selection fact_selection source_set_sha256 source_bindings inputs status page receipts)
  @recipe "ipse.evidence.shared_producer.first_page.v2"

  def start(resolved, profile, args) do
    with true <-
           exact?(
             args,
             ~w(version action embedding job_id job_revision vector_selection fact_selection)
           ),
         true <- args["version"] === 1 and args["action"] in ~w(page inspect),
         true <- is_binary(args["job_id"]) and Regex.match?(~r/\A[a-f0-9]{32}\z/, args["job_id"]),
         true <- Evidence.safe_uint?(args["job_revision"]),
         true <- Projection.valid_selection?(args["vector_selection"]),
         true <- args["vector_selection"]["dimensions"] === 1024,
         true <- Projection.valid_extraction?(args["fact_selection"]),
         {:ok, embedding} <- Profiles.lookup(resolved, "embedding", args["embedding"]),
         true <-
           embedding["kind"] == "embedding" and
             embedding["profile"] == args["vector_selection"]["profile"] do
      s = %{
        resolved: resolved,
        profile: profile,
        args: args,
        reads: 0,
        effects: 0,
        rows: %{},
        stages: [],
        vectors: [],
        receipts: [],
        pending_inputs: [],
        anchors: [],
        units: [],
        boot: nil,
        queue: ~w(catalog generation genjob genproducer)
      }

      read_next(s)
    else
      _ -> error(:invalid_shared_producer_request)
    end
  rescue
    _ -> error(:invalid_shared_producer_request)
  end

  def resume(%{producer: s, inner: inner}, outcome) do
    result =
      if s.child == :collection,
        do: C.resume(inner, outcome),
        else: Adapters.resume(inner, outcome)

    advance(result, s)
  end

  defp io(s, op, args, phase),
    do: advance(C.start(s.profile, op, args), Map.merge(s, %{phase: phase, child: :collection}))

  defp advance({:call, request, inner}, s) do
    read = C.read_request?(request) or request["op"] == "effect.result.read"

    s = %{
      s
      | reads: s.reads + if(read, do: 1, else: 0),
        effects: s.effects + if(read, do: 0, else: 1)
    }

    if s.reads <= 512 and s.effects <= 16,
      do: {:call, request, %{producer: s, inner: inner}},
      else: error(:shared_producer_budget)
  end

  defp advance({:done, {:ok, value}}, s) do
    done(s, value)
  rescue
    _ -> error(:shared_producer_changed)
  end

  defp advance({:stop, :unknown_effect}, _), do: {:stop, :unknown_effect}
  defp advance({:done, {:error, code}}, _), do: error(code)
  defp advance({:done, {:error, code, _}}, _), do: error(code)
  defp advance({:done, {:continue, _}}, _), do: error(:shared_producer_incomplete_stage)

  defp read_next(%{queue: [key | rest]} = s),
    do:
      io(
        Map.put(s, :queue, rest),
        :value_read,
        %{"key" => key <> "." <> s.profile["partition"]},
        {:anchor, key}
      )

  defp read_next(%{queue: []} = s) do
    catalog = s.rows["catalog"]
    root = s.rows["generation"]
    job = s.rows["genjob"]
    producer = s.rows["genproducer"]
    true = is_map(catalog) and C.valid_catalog?(catalog["value"], s.profile)
    true = is_map(job) and Job.valid?(job["value"], s.profile)
    j = job["value"]
    true = j["id"] === s.args["job_id"] and job["revision"] === s.args["job_revision"]
    true = j["status"] == "groups" and j["cursor"] < j["catalog"]["sources"]
    true = j["catalog_sha256"] === catalog["sha256"] and j["catalog"] === catalog["value"]
    true = j["root_revision"] === revision(root) and j["root_sha256"] === sha(root)

    true =
      j["vector_selection"] === s.args["vector_selection"] and
        j["fact_selection"] === s.args["fact_selection"]

    true =
      is_nil(producer) or
        Map.take(
          producer["value"],
          ~w(job_id job_revision catalog_sha256 root_revision root_sha256 vector_selection fact_selection)
        ) ===
          %{
            "job_id" => j["id"],
            "job_revision" => job["revision"],
            "catalog_sha256" => j["catalog_sha256"],
            "root_revision" => j["root_revision"],
            "root_sha256" => j["root_sha256"],
            "vector_selection" => j["vector_selection"],
            "fact_selection" => j["fact_selection"]
          }

    true =
      is_nil(root) or
        Directory.valid_root?(
          root["value"],
          Map.take(
            root["value"],
            ~w(generation catalog_sha256 catalog_generation floor vector_selection fact_selection)
          )
          |> Map.put("root_sha256", root["sha256"])
        )

    cond do
      producer != nil and not valid_record?(producer["value"]) ->
        error(:shared_producer_corrupt)

      s.args["action"] == "inspect" ->
        result(s, if(producer, do: producer["value"], else: nil))

      producer != nil and producer["value"]["status"] == "pending" ->
        error(:shared_producer_pending_unknown)

      producer != nil ->
        error(:shared_producer_page_already_completed)

      true ->
        page = div(j["cursor"], 16)

        anchors =
          for key <- ~w(catalog generation genjob),
              do: {key <> "." <> s.profile["partition"], s.rows[key]}

        s = Map.merge(s, %{job: j, anchors: anchors, catalog_page: page})
        io(s, :value_read, %{"key" => "catalog.#{s.profile["partition"]}.#{page}"}, :catalog_page)
    end
  end

  defp done(%{phase: {:anchor, key}} = s, value) do
    true = is_nil(s.boot) or s.boot === value["native_generation"]

    read_next(%{
      s
      | boot: value["native_generation"],
        rows: Map.put(s.rows, key, value["record"])
    })
  end

  defp done(%{phase: :catalog_page} = s, value) do
    true = value["native_generation"] === s.boot
    ref = Enum.at(s.job["catalog"]["pages"], s.catalog_page)
    true = C.valid_catalog_page?(value["record"], ref, s.catalog_page, s.profile)

    rows =
      Enum.slice(
        value["record"]["value"]["rows"],
        rem(s.job["cursor"], 16),
        min(8, s.job["catalog"]["sources"] - s.job["cursor"])
      )

    io(
      Map.put(s, :group_rows, rows),
      :source_bundles,
      %{
        "source_keys" => Enum.map(rows, & &1["source_key"]),
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

    s = Map.merge(s, %{bundles: bundles, source_pending: bundles, source_bindings: []})
    if eligible?(s), do: capture_sources(s), else: error(:shared_producer_ineligible)
  end

  defp done(%{phase: :source_binding, source_pending: [bundle | rest]} = s, value) do
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

    s = %{
      s
      | source_pending: rest,
        source_bindings: s.source_bindings ++ [binding],
        anchors: s.anchors ++ [{"source.#{s.profile["partition"]}.#{source["source_key"]}", row}]
    }

    capture_sources(s)
  end

  defp done(%{phase: :batch_pending} = s, value) do
    true = is_map(value["record"]) and value["record"]["value"] === s.claim
    true = value["record"]["revision"] === s.claim_revision

    check(
      Map.merge(s, %{
        checking: s.anchors,
        check_generation: value["native_generation"],
        after_check: :inference
      })
    )
  end

  defp done(%{phase: :prepared, preparing: [unit | rest]} = s, value) do
    s = %{s | stages: s.stages ++ [{value["stage"], unit}], preparing: rest}
    prepare_next(s)
  end

  defp done(%{phase: :verified, verifying: [{ref, {key, value, revision}} | rest]} = s, result) do
    stage = result["stage"]

    true =
      stage["slot"] === ref["slot"] and stage["epoch"] === ref["epoch"] and
        stage["state"] == "sealed"

    true = stage["key"] === key and stage["sha256"] === Evidence.sha256(json(value))

    true =
      stage["byte_count"] === byte_size(json(value)) and
        stage["offset"] === byte_size(json(value))

    true = stage["expected_revision"] === revision
    true = is_nil(s.check_generation) or s.check_generation === result["generation"]
    verify(%{s | check_generation: result["generation"], verifying: rest})
  end

  defp done(%{phase: :checked, checking: [{key, row} | rest]} = s, value) do
    true = value["generation"] === s.check_generation and value["key"] === key
    true = stamp(value["record"]) === stamp(row)
    check(%{s | checking: rest})
  end

  defp done(%{phase: :committed, after_commit: :infer} = s, value) do
    anchors =
      s.anchors ++
        [
          {key(s),
           %{"revision" => value["native_generation"], "sha256" => Evidence.sha256(json(s.claim))}}
        ]

    infer(
      Map.merge(s, %{anchors: anchors, claim_revision: value["native_generation"], stages: []})
    )
  end

  defp done(%{phase: :committed, after_commit: :finish} = s, _), do: result(s, s.ready)

  defp done(%{phase: :inference, batch: batch} = s, value) do
    vectors = value["vectors"]
    true = is_list(vectors) and length(vectors) == length(batch)

    true =
      Enum.zip(vectors, batch)
      |> Enum.all?(fn {v, i} ->
        Map.take(v, ~w(selection_sha256 profile model dimensions encoding)) ===
          s.args["vector_selection"] and
          Evidence.current_vector?(v) and Evidence.vector_input_matches_chunk?(v, i.value)
      end)

    receipt = value["receipt"]
    true = receipt["raw_input_sha256"] === Enum.map(batch, &Evidence.sha256(&1.value["text"]))
    true = receipt["input_sha256"] === Enum.map(vectors, & &1["input_sha256"])
    true = Evidence.sha256?(receipt["source_sha256"]) and is_binary(receipt["operation_id"])
    infer(%{s | vectors: s.vectors ++ vectors, receipts: s.receipts ++ [receipt]})
  end

  defp capture_sources(%{source_pending: [bundle | _]} = s),
    do:
      io(
        s,
        :value_read,
        %{"key" => "source.#{s.profile["partition"]}.#{bundle["source"]["source_key"]}"},
        :source_binding
      )

  defp capture_sources(%{source_pending: []} = s) do
    if eligible?(s), do: build_claim(s), else: error(:shared_producer_ineligible)
  end

  defp build_claim(s) do
    bundles = s.bundles

    inputs =
      bundles
      |> Enum.with_index()
      |> Enum.flat_map(fn {b, si} ->
        {:ok, chunks} = Evidence.chunks(b["source"])
        Enum.with_index(chunks) |> Enum.map(fn {c, ci} -> %{source: si, chunk: ci, value: c} end)
      end)
      |> Enum.take(8)

    true = inputs != []

    identities =
      Enum.map(bundles, &[&1["source"]["source_key"], Evidence.sha256(json(&1["source"]))])

    claim = %{
      "version" => 2,
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
      "source_set_sha256" => Evidence.sha256(json(%{"sources" => identities})),
      "source_bindings" => s.source_bindings,
      "inputs" =>
        Enum.map(inputs, fn i ->
          {:ok, canonical} = Ipse.Extension.canonical_digest([i.value["text"]])
          [i.source, i.chunk, i.value["chunk_id"], canonical, Evidence.sha256(i.value["text"])]
        end),
      "status" => "pending",
      "page" => nil,
      "receipts" => []
    }

    true = valid_record?(claim)
    true = s.reads + 128 <= 512 and s.effects + 14 <= 16

    s =
      Map.merge(s, %{claim: claim, bundles: bundles, pending_inputs: inputs, after_commit: :infer})

    prepare(s, [{key(s), claim, 0}])
  end

  defp prepare(s, units), do: prepare_next(Map.merge(s, %{preparing: units, stages: []}))

  defp prepare_next(%{preparing: [{key, value, revision} | _]} = s),
    do:
      io(
        s,
        :value_prepare,
        %{
          "key" => key,
          "value" => value,
          "expected_revision" => revision,
          "reuse" => false,
          "continuation" => nil
        },
        :prepared
      )

  defp prepare_next(%{preparing: []} = s),
    do: verify(Map.merge(s, %{verifying: s.stages, check_generation: nil}))

  defp verify(%{verifying: [{ref, _} | _]} = s),
    do: io(s, :stage_inspect, %{"ref" => ref}, :verified)

  defp verify(%{verifying: []} = s),
    do: check(Map.merge(s, %{checking: s.anchors, after_check: :commit}))

  defp check(%{checking: [{key, _} | _]} = s),
    do: io(s, :value_stat, %{"key" => key, "generation" => s.check_generation}, :checked)

  defp check(%{checking: [], after_check: :commit} = s) do
    if eligible?(s) do
      io(
        s,
        :value_commit_at,
        %{"stages" => Enum.map(s.stages, &elem(&1, 0)), "generation" => s.check_generation},
        :committed
      )
    else
      error(:shared_producer_ineligible)
    end
  end

  defp check(%{checking: [], after_check: :inference} = s) do
    if eligible?(s), do: next_inference(s), else: error(:shared_producer_ineligible)
  end

  defp infer(s) do
    if eligible?(s),
      do: io(s, :value_read, %{"key" => key(s)}, :batch_pending),
      else: error(:shared_producer_ineligible)
  end

  defp next_inference(%{pending_inputs: []} = s) do
    {:ok, page} =
      Generation.vector_page(
        s.profile["partition"],
        s.job["cursor"],
        s.bundles,
        s.vectors,
        s.args["vector_selection"],
        0
      )

    ready =
      s.claim
      |> Map.put("status", "ready")
      |> Map.put("page", %{
        "key" => page.key,
        "sha256" => page.sha256,
        "byte_count" => page.byte_count
      })
      |> Map.put("receipts", s.receipts)

    true = valid_record?(ready)
    s = Map.merge(s, %{ready: ready, after_commit: :finish})
    prepare(s, [{page.key, page.value, 0}, {key(s), ready, s.claim_revision}])
  end

  defp next_inference(s) do
    {batch, remaining} = Enum.split(s.pending_inputs, 2)

    args = %{
      "profile" => s.args["embedding"],
      "inputs" => Enum.map(batch, &Map.take(&1.value, ~w(chunk_id text)))
    }

    s =
      Map.merge(s, %{batch: batch, pending_inputs: remaining, phase: :inference, child: :adapter})

    advance(Adapters.start(s.resolved, :embed, args), s)
  end

  defp result(s, row),
    do:
      {:done,
       {:ok,
        %{
          "status" =>
            if(row,
              do: if(row["status"] == "pending", do: "pending_unknown", else: "page_ready"),
              else: "absent"
            ),
          "page" => if(row, do: row["page"], else: nil),
          "continuation" => nil,
          "coverage" => %{
            "recipe" => @recipe,
            "reads_used" => s.reads,
            "effects_used" => s.effects,
            "model_receipt_provenance" => false,
            "validated_inference_receipt_flow" =>
              Map.get(s, :after_commit) == :finish and s.phase == :committed,
            "retry_available" => false,
            "group_complete" => false,
            "selected_changed" => false
          }
        }}}

  def valid_record?(r) do
    exact?(r, @fields) and r["version"] === 2 and r["kind"] == "shared_projection_producer" and
      r["recipe"] == @recipe and
      is_binary(r["partition"]) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,15}\z/, r["partition"]) and
      is_binary(r["job_id"]) and Regex.match?(~r/\A[a-f0-9]{32}\z/, r["job_id"]) and
      Enum.all?(~w(job_revision catalog_floor root_revision cursor), &Evidence.safe_uint?(r[&1])) and
      Enum.all?(~w(catalog_sha256 source_set_sha256), &Evidence.sha256?(r[&1])) and
      (is_nil(r["root_sha256"]) or Evidence.sha256?(r["root_sha256"])) and
      Projection.valid_selection?(r["vector_selection"]) and
      r["vector_selection"]["dimensions"] === 1024 and
      Projection.valid_extraction?(r["fact_selection"]) and is_binary(r["embedding"]) and
      byte_size(r["embedding"]) in 1..64 and
      is_list(r["source_bindings"]) and length(r["source_bindings"]) in 1..8 and
      Enum.all?(r["source_bindings"], &source_binding?/1) and
      r["status"] in ~w(pending ready) and is_list(r["inputs"]) and length(r["inputs"]) in 1..8 and
      Enum.all?(r["inputs"], fn i ->
        is_list(i) and length(i) == 5 and Enum.at(i, 0) in 0..7 and Enum.at(i, 1) in 0..31 and
          Enum.all?(Enum.drop(i, 2), &Evidence.sha256?/1)
      end) and
      is_list(r["receipts"]) and length(r["receipts"]) <= 4 and byte_size(json(r)) <= 8192 and
      if(r["status"] == "pending",
        do: r["page"] == nil and r["receipts"] == [],
        else:
          exact?(r["page"], ~w(key sha256 byte_count)) and Evidence.sha256?(r["page"]["sha256"]) and
            r["page"]["key"] === "genvec.#{r["partition"]}." <> r["page"]["sha256"] and
            is_integer(r["page"]["byte_count"]) and r["page"]["byte_count"] in 2..49152 and
            length(r["receipts"]) == div(length(r["inputs"]) + 1, 2) and
            Enum.all?(r["receipts"], &receipt?/1) and
            length(Enum.uniq_by(r["receipts"], & &1["operation_id"])) == length(r["receipts"]) and
            Enum.flat_map(r["receipts"], & &1["input_sha256"]) ===
              Enum.map(r["inputs"], &Enum.at(&1, 3)) and
            Enum.flat_map(r["receipts"], & &1["raw_input_sha256"]) ===
              Enum.map(r["inputs"], &Enum.at(&1, 4))
      )
  rescue
    _ -> false
  end

  defp source_binding?(r),
    do:
      exact?(
        r,
        ~w(source_key head_revision head_sha256 bundle_sha256 observed_at_ms expires_at_ms historical chunking_sha256)
      ) and
        Enum.all?(
          ~w(source_key head_sha256 bundle_sha256 chunking_sha256),
          &Evidence.sha256?(r[&1])
        ) and
        Enum.all?(~w(head_revision observed_at_ms), &Evidence.safe_uint?(r[&1])) and
        (is_nil(r["expires_at_ms"]) or Evidence.safe_uint?(r["expires_at_ms"])) and
        r["historical"] === false

  defp eligible?(s) do
    now = System.system_time(:millisecond)
    Enum.all?(s.bundles, &Evidence.current?(&1["source"], now))
  end

  defp receipt?(r),
    do:
      exact?(r, ~w(operation_id source_sha256 input_sha256 raw_input_sha256)) and
        is_binary(r["operation_id"]) and Regex.match?(~r/\A[0-9a-fA-F]{32}\z/, r["operation_id"]) and
        Evidence.sha256?(r["source_sha256"]) and
        is_list(r["input_sha256"]) and length(r["input_sha256"]) in 1..2 and
        is_list(r["raw_input_sha256"]) and
        length(r["raw_input_sha256"]) == length(r["input_sha256"]) and
        Enum.all?(r["input_sha256"] ++ r["raw_input_sha256"], &Evidence.sha256?/1)

  defp key(s), do: "genproducer." <> s.profile["partition"]
  defp revision(nil), do: 0
  defp revision(r), do: r["revision"]
  defp sha(nil), do: nil
  defp sha(r), do: r["sha256"]
  defp stamp(nil), do: nil
  defp stamp(r), do: Map.take(r, ~w(revision sha256))
  defp exact?(r, fields), do: is_map(r) and Enum.sort(Map.keys(r)) == Enum.sort(fields)
  defp json(value), do: IO.iodata_to_binary(JSON.encode!(value))
  defp error(code), do: {:done, {:error, code, %{}}}
end
