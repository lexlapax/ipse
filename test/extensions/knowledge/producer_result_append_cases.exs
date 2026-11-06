defmodule IpseKnowledge.ProducerResultAppendCases do
  use ExUnit.Case, async: false
  alias Ipse.CollectionRecipeModel, as: M
  alias IpseKnowledge.{Evidence, Profiles}
  alias IpseKnowledge.Store.Collection, as: C
  alias IpseKnowledge.Store.Collection.{Job, Producer}
  alias IpseKnowledge.Store.Collection.Producer.Progress

  @profile %{"kind" => "collection", "scope" => "project", "partition" => "notes"}
  @selection %{
    "profile" => "encoder",
    "model" => "fixture-model",
    "dimensions" => 1024,
    "encoding" => "float32le",
    "selection_sha256" => String.duplicate("a", 64)
  }
  @facts %{"kind" => "explicit", "profile" => nil, "version" => 1}
  @owner %{
    "project_id" => String.duplicate("b", 64),
    "session_id" => String.duplicate("b", 32),
    "identity_sha256" => String.duplicate("c", 64)
  }

  defp json(value), do: IO.iodata_to_binary(JSON.encode!(value))

  defp initial do
    source = %{
      "source_id" => "fixture:result",
      "partition" => "notes",
      "generation" => 1,
      "title" => "Supplied facts",
      "text" => "Ada supports review.",
      "uri" => "provided:result",
      "observed_at_ms" => 10,
      "event_at_ms" => nil,
      "expires_at_ms" => nil,
      "origin" => %{
        "kind" => "provided",
        "store_profile" => "local",
        "partition_or_scope" => "notes",
        "receipt" => nil,
        "historical" => false
      }
    }

    model = put_source(source, M.new(%{}, 1000), nil)

    {{:done, {:ok, _}}, model} =
      M.run(Job.start_bound(@profile, job_args("begin", nil)), M.reset(model))

    options =
      Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})
      |> Map.merge(%{
        "version" => 1,
        "stores" => %{"local" => @profile},
        "retrieval" => %{"words" => %{"kind" => "bm25", "version" => 1}},
        "embedding" => %{"learned" => %{"kind" => "embedding", "profile" => "encoder"}}
      })

    {:ok, resolved} = Profiles.validate("corpus", "collection-dense", options)
    row = model.records["genjob.notes"]

    args = %{
      "version" => 2,
      "action" => "page",
      "embedding" => "learned",
      "job_id" => row.value["id"],
      "job_revision" => row.revision,
      "vector_selection" => @selection,
      "fact_selection" => @facts,
      "vector_cursor" => 0,
      "previous_ready" => nil
    }

    state = %{model: model, pages: %{}, calls: 0, requests: [], unknown_commit: false}
    {{:done, {:ok, _}}, state} = invoke(Progress.start(resolved, @profile, args), state)
    {resolved, args, source, state}
  end

  defp put_source(source, model, token) do
    case M.run(
           C.start(@profile, :put, %{
             "source" => source,
             "expected_revision" => 0,
             "continuation" => token
           }),
           M.reset(model)
         ) do
      {{:done, {:continue, value}}, model} -> put_source(source, model, value["continuation"])
      {{:done, {:ok, _}}, model} -> model
    end
  end

  defp job_args(action, token),
    do: %{
      "action" => action,
      "vector_selection" => @selection,
      "fact_selection" => @facts,
      "continuation" => token,
      "group" => nil
    }

  defp selected(source, rows \\ nil) do
    rows =
      rows ||
        [
          %{
            "subject" => "Ada",
            "predicate" => "supports",
            "object" => "review",
            "polarity" => "positive",
            "inferred" => false,
            "valid_from_ms" => nil,
            "valid_to_ms" => nil,
            "spans" => [[0, 0, 3]]
          }
        ]

    value = %{
      "version" => 1,
      "kind" => "explicit_fact_group",
      "sources" => [%{"source_key" => Evidence.sha256(source["source_id"]), "facts" => rows}]
    }

    bytes = json(value)

    delivery = %{
      "version" => 1,
      "kind" => "saved.result",
      "output_id" => Evidence.sha256("output"),
      "byte_count" => byte_size(bytes),
      "sha256" => Evidence.sha256(bytes),
      "historical_receipt" => true
    }

    %{
      "result_input" => %{
        "version" => 1,
        "session_id" => String.duplicate("d", 32),
        "delivery" => delivery
      },
      "value" => value,
      "raw_sha256" => delivery["sha256"],
      "byte_count" => byte_size(bytes),
      "owner" => @owner,
      "reads_used" => 1
    }
  end

  defp invoke(result, state),
    do: drive(result, %{state | model: M.reset(state.model), requests: []})

  defp drive({:call, request, token}, state) do
    :ok =
      Ipse.Extension.validate(%{"api_version" => 1, "kind" => "host_call", "request" => request})

    {outcome, state} = host(request, %{state | requests: state.requests ++ [request]})
    drive(Producer.resume(token, outcome), state)
  end

  defp drive(result, state), do: {result, state}

  defp host(%{"op" => "collection.store"} = request, state) do
    {outcome, model} =
      if request["request"]["op"] == "value.read" and
           not Map.has_key?(state.model.records, request["request"]["key"]),
         do:
           {%{"status" => "failed", "value" => %{"code" => "document_store_refused"}},
            state.model},
         else: M.host(request, state.model)

    unknown = state.unknown_commit and request["request"]["op"] == "commit"
    {if(unknown, do: %{"status" => "unknown"}, else: outcome), %{state | model: model}}
  end

  defp host(%{"op" => "embedding.create"} = request, state) do
    id = String.pad_leading(Integer.to_string(state.calls + 1, 16), 32, "0")
    bytes = for _ <- 1..1024, into: <<>>, do: <<1.0::float-little-32>>
    source = Evidence.sha256("response:" <> id)

    pages =
      Enum.with_index(request["inputs"])
      |> Map.new(fn {text, index} ->
        {:ok, canonical} = Ipse.Extension.canonical_digest([text])
        {{id, index}, %{bytes: bytes, input: canonical, source: source}}
      end)

    value = %{
      "version" => 2,
      "request_id" => id,
      "attempt_id" => id,
      "profile" => request["profile"],
      "reported_model" => "fixture-model",
      "selection_sha256" => @selection["selection_sha256"],
      "usage" => nil,
      "result" => %{
        "version" => 2,
        "operation_id" => id,
        "source_sha256" => source,
        "kind" => "embedding.f32le",
        "encoding" => "float32le.base64",
        "dimensions" => 1024,
        "vector_count" => length(request["inputs"])
      }
    }

    {%{"status" => "ok", "value" => value},
     %{state | calls: state.calls + 1, pages: Map.merge(state.pages, pages)}}
  end

  defp host(%{"op" => "effect.result.read"} = request, state) do
    page = state.pages[{request["operation_id"], request["vector_index"]}]
    count = min(request["limit"], 1024 - request["offset"])
    next = request["offset"] + count

    value = %{
      "version" => 2,
      "operation_id" => request["operation_id"],
      "source_sha256" => page.source,
      "kind" => "embedding.f32le",
      "encoding" => "float32le.base64",
      "vector_index" => request["vector_index"],
      "dimensions" => 1024,
      "offset" => request["offset"],
      "complete" => next == 1024,
      "next" => if(next == 1024, do: nil, else: next),
      "input_sha256" => page.input,
      "vector_sha256" => Evidence.sha256(page.bytes),
      "values" => Base.encode64(binary_part(page.bytes, request["offset"] * 4, count * 4))
    }

    {%{"status" => "ok", "value" => value}, state}
  end

  defp append(resolved, args, selected, token, state, remaining \\ 20)
  defp append(_, _, _, _, _, 0), do: flunk("bounded append did not finish")

  defp append(resolved, args, selected, token, state, remaining) do
    case invoke(Progress.append_result(resolved, @profile, args, selected, token), state) do
      {{:done, {:continue, value}}, state} ->
        assert value["continuation"]["phase"] === "append"
        assert state.calls === 1
        append(resolved, args, selected, value["continuation"], state, remaining - 1)

      terminal ->
        terminal
    end
  end

  test "binding is a separate known stage-free commit; later units use its original vector revision" do
    {resolved, args, source, state} = initial()
    selected = selected(source)
    before = state.model.records

    {{:done, {:continue, bound}}, state} =
      invoke(Progress.append_result(resolved, @profile, args, selected, nil), state)

    assert bound["status"] === "input_bound"
    token = bound["continuation"]
    assert token["phase"] === "append" and token["job"]["unit"] === 0
    assert token["job"]["stages"] === [] and token["job"]["write"] === nil
    row = state.model.records["genjob.notes"]
    assert row.value["input_binding"]["vector_job_revision"] === args["job_revision"]
    assert row.revision > args["job_revision"]
    assert row.value["input_binding"]["owner"] === @owner
    assert Enum.sort(Map.keys(state.model.records)) === Enum.sort(Map.keys(before))
    assert map_size(state.model.stages) === 0
    assert bound["producer_coverage"]["reads_used"] === state.model.reads + selected["reads_used"]
    assert state.calls === 1
    {{:done, {:ok, final}}, state} = append(resolved, args, selected, token, state)
    assert final["job"]["version"] === 1 and final["job"]["status"] === "manifests"
    refute Map.has_key?(final["job"], "input_binding")
    assert final["job"]["facts"] === 1 and state.calls === 1
  end

  test "an explicit empty fact set remains empty through binding and append" do
    {resolved, args, source, state} = initial()
    selected = selected(source, [])

    {{:done, {:continue, bound}}, state} =
      invoke(Progress.append_result(resolved, @profile, args, selected, nil), state)

    {{:done, {:ok, final}}, _} = append(resolved, args, selected, bound["continuation"], state)
    assert final["job"]["facts"] === 0
  end

  test "malformed spans, source membership, input envelope and legacy Jobs refuse before effects" do
    {resolved, args, source, state} = initial()
    selected = selected(source)

    mutations = [
      put_in(selected, ["value", "sources", Access.at(0), "facts", Access.at(0), "spans"], [
        [0, 0, 999]
      ]),
      put_in(
        selected,
        ["value", "sources", Access.at(0), "source_key"],
        String.duplicate("f", 64)
      ),
      Map.put(selected, "extra", true),
      Map.put(selected, "byte_count", selected["byte_count"] + 1)
    ]

    for changed <- mutations do
      assert {{:done, {:error, _, _}}, after_state} =
               invoke(Progress.append_result(resolved, @profile, args, changed, nil), state)

      assert after_state.model.effects === 0 and after_state.model.records === state.model.records
    end

    row = state.model.records["genjob.notes"]
    legacy = %{row | value: row.value |> Map.delete("input_binding") |> Map.put("version", 1)}
    changed = put_in(state, [:model, :records, "genjob.notes"], legacy)

    assert {{:done, {:error, _, _}}, after_state} =
             invoke(Progress.append_result(resolved, @profile, args, selected, nil), changed)

    assert after_state.model.effects === 0
  end

  test "a bound group refuses changed original reference, bytes, owner or copied token before effects" do
    {resolved, args, source, state} = initial()
    selected = selected(source)

    {{:done, {:continue, bound}}, state} =
      invoke(Progress.append_result(resolved, @profile, args, selected, nil), state)

    token = bound["continuation"]

    changed_raw =
      selected
      |> Map.put("raw_sha256", String.duplicate("f", 64))
      |> put_in(["result_input", "delivery", "sha256"], String.duplicate("f", 64))

    mutations = [
      {put_in(selected, ["result_input", "delivery", "output_id"], String.duplicate("e", 64)),
       token},
      {changed_raw, token},
      {put_in(selected, ["owner", "session_id"], String.duplicate("e", 32)), token},
      {selected,
       put_in(token, ["input_binding", "vector_job_revision"], args["job_revision"] + 1)}
    ]

    for {input, continuation} <- mutations do
      assert {{:done, {:error, _, _}}, after_state} =
               invoke(
                 Progress.append_result(resolved, @profile, args, input, continuation),
                 state
               )

      assert after_state.model.effects === 0 and after_state.model.records === state.model.records
    end

    current_args = Map.put(args, "job_revision", state.model.records["genjob.notes"].revision)

    assert {{:done, {:error, _, _}}, after_state} =
             invoke(Progress.start(resolved, @profile, current_args), state)

    assert after_state.model.effects === 0 and after_state.calls === 1
  end

  test "selected input reads share the 512 ceiling and cannot bind after exhaustion" do
    {resolved, args, source, state} = initial()
    input = Map.put(selected(source), "reads_used", 512)

    assert {:done, {:error, :shared_producer_budget, _}} =
             Progress.append_result(resolved, @profile, args, input, nil)

    input = Map.put(input, "reads_used", 500)

    assert {{:done, {:error, _, _}}, after_state} =
             invoke(Progress.append_result(resolved, @profile, args, input, nil), state)

    assert after_state.model.effects === 0 and after_state.model.records === state.model.records
  end

  test "an unknown binding commit has no append or adoption continuation" do
    {resolved, args, source, state} = initial()

    assert {{:stop, :unknown_effect}, after_state} =
             invoke(Progress.append_result(resolved, @profile, args, selected(source), nil), %{
               state
               | unknown_commit: true
             })

    assert after_state.model.effects > 0
    assert is_map(after_state.model.records["genjob.notes"].value["input_binding"])
  end

  test "125-summary metadata and escaped UTF-8 use bounded staged frames rather than whole-value inline" do
    # The maximum Job/catalog geometry also used by collection_job_progress.exs.
    # These are metadata preflight values, not a claim of 1,000 actual sources.
    partition = "abcdefghijklmnop"
    maximum = Evidence.safe_integer_max()

    catalog = %{
      "version" => 1,
      "kind" => "catalog",
      "partition" => partition,
      "generation" => maximum,
      "floor" => maximum,
      "sources" => 1000,
      "extracted_bytes" => 20 * 1024 * 1024,
      "chunks" => 10_000,
      "entities" => 5000,
      "assertions" => 20_000,
      "pages" =>
        for(
          n <- 0..62,
          do: %{"key" => "catalog.#{partition}.#{n}", "sha256" => Evidence.sha256("catalog#{n}")}
        )
    }

    selection = %{
      @selection
      | "profile" => String.duplicate("\u0000é", 32),
        "model" => String.duplicate("\u0000é", 32)
    }

    job = %{
      "version" => 4,
      "maintenance_epoch" => 2,
      "kind" => "shared_generation_job",
      "id" => String.duplicate("f", 32),
      "partition" => partition,
      "status" => "manifests",
      "catalog" => catalog,
      "catalog_sha256" => Evidence.sha256(json(catalog)),
      "generation" => maximum,
      "root_revision" => maximum,
      "root_sha256" => Evidence.sha256("root"),
      "vector_selection" => selection,
      "fact_selection" => @facts,
      "cursor" => 1000,
      "facts" => 20_000,
      "summaries" =>
        for(
          n <- 0..124,
          do: %{
            "key" => "gensum.#{partition}." <> Evidence.sha256("summary#{n}"),
            "sha256" => Evidence.sha256("summary#{n}"),
            "byte_count" => 49_152
          }
        )
    }

    assert Job.valid?(job, %{"partition" => partition})
    assert length(job["summaries"]) === 125 and length(catalog["pages"]) === 63
    assert byte_size(json(job)) > 16_384
    assert {:ok, effects} = Progress.binding_reservation(job, catalog, 2)
    assert effects in 1..16

    # New binding only exists in the preceding groups phase (124 summaries).
    {resolved, args, source, state} = initial()
    input = selected(source)

    binding = %{
      "version" => 1,
      "ref_sha256" => Evidence.sha256("ref"),
      "raw_sha256" => input["raw_sha256"],
      "source_set_sha256" => Evidence.sha256("sources"),
      "cursor" => 992,
      "vector_job_revision" => 1,
      "owner" => @owner
    }

    bound =
      job
      |> Map.put("version", 8)
      |> Map.put("status", "groups")
      |> Map.put("cursor", 992)
      |> Map.put("summaries", Enum.take(job["summaries"], 124))
      |> Map.put("input_binding", binding)

    assert Job.valid?(bound, %{"partition" => partition})
    assert {:ok, effects} = Progress.binding_reservation(bound, catalog, 2)
    assert effects in 1..16
    assert {:error, :shared_producer_budget} = Progress.binding_reservation(bound, catalog, 3)

    assert {:error, :shared_producer_budget} =
             Progress.binding_reservation(
               put_in(bound, ["vector_selection", "profile"], String.duplicate("\u0000é", 8192)),
               catalog,
               2
             )

    # A valid encoded input can still leave too few reads for the same preflight.
    assert {{:done, {:error, _, _}}, refused} =
             invoke(
               Progress.append_result(
                 resolved,
                 @profile,
                 args,
                 Map.put(input, "reads_used", 500),
                 nil
               ),
               state
             )

    assert refused.model.effects === 0 and refused.model.records === state.model.records
  end
end
