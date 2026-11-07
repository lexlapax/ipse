Code.require_file("../../../dev/verification/scenarios.exs", __DIR__)
Code.require_file("../../../dev/verification/runtime.exs", __DIR__)

defmodule Ipse.CollectionRecipePublicTest do
  use ExUnit.Case, async: false
  alias Ipse.Development.Verification.Runtime

  setup_all do
    %{runtime: prepare_runtime()}
  end

  test "public result construction uses actual sealed codecs and selected 6144-byte owner replies",
       %{runtime: runtime} do
    model_test(runtime, ~S"""
    alias Ipse.CollectionRecipeModel, as: M
    rows = for n <- 1..32 do
      %{"subject" => String.duplicate("s", 64), "predicate" => String.duplicate("r", 60) <> Integer.to_string(n),
        "object" => String.duplicate("o", 64), "polarity" => "positive", "inferred" => false,
        "valid_from_ms" => nil, "valid_to_ms" => nil, "spans" => [[0, 0, 1]]}
    end
    args = %{"store" => "local", "action" => "fact_input", "args" => %{"input" =>
      %{"version" => 1, "mode" => "publish", "value" => %{"version" => 1,
        "kind" => "explicit_fact_group", "sources" => [%{"source_key" => String.duplicate("a", 64), "facts" => rows}]}}}}
    {{:published, ref}, model} = M.public(resolved, "source", args, M.new(%{}, 0))
    0 = model.generation
    %{"kind" => "saved.result", "historical_receipt" => true} = ref["delivery"]
    source = model.selected_inputs[Ipse.JSON.digest([ref])]
    true = source.event_count >= 5
    {:done, {:ok, selected}} = elem(M.run(C.start(profile, :selected_fact_result, %{"result_input" => ref}), M.reset(model)), 0)
    true = selected["owner"] === Map.delete(model.owner, "invocation_id")
    true = selected["raw_sha256"] === ref["delivery"]["sha256"]
    true = byte_size(source.bytes) > 6144 and byte_size(source.bytes) <= 12_288
    2 = selected["reads_used"]
    0 = map_size(model.operations)
    "explicit_fact_group" = selected["value"]["kind"]
    %{"sealed_codec" => true, "native_operations" => 0}
    """)
  end

  test "fresh Source public continuations and native progress derive revisions without an offset",
       %{runtime: runtime} do
    model_test(runtime, ~S"""
    alias Ipse.CollectionRecipeModel, as: M
    attrs = %{"source_id" => "fixture:recipe", "generation" => 1, "expected_revision" => 0,
      "title" => "Synthetic", "text" => "A bounded synthetic statement.", "uri" => "provided:recipe",
      "observed_at_ms" => 1, "event_at_ms" => nil, "expires_at_ms" => nil}
    args = %{"store" => "local", "action" => "put", "args" => attrs}
    loop = fn loop, args, model ->
      case M.public(resolved, "source", args, model) do
        {{:ok, %{"status" => "draft", "continuation" => next}}, model} -> loop.(loop, next["arguments"], model)
        {{:ok, %{"status" => "ok"}}, model} -> model
        other -> raise inspect(other)
      end
    end
    model = loop.(loop, args, M.new(%{}, 0, maintenance_epoch: 1))
    true = model.generation > 0
    true = model.generation === map_size(model.operations)
    true = Enum.all?(model.records, fn {_, row} -> row.revision > 0 and row.revision <= model.generation end)
    0 = map_size(model.stages)
    0 = map_size(model.heads)
    true = model.peaks.heads === 1 and model.peaks.stages > 0
    %{"zero_based" => true, "known_stage_free" => true}
    """)
  end

  test "full fact-group input refuses a real worker frame instead of dropping rows", %{
    runtime: runtime
  } do
    model_test(runtime, ~S"""
    alias Ipse.CollectionRecipeModel, as: M
    row = %{"subject" => String.duplicate("s", 64), "predicate" => String.duplicate("r", 64),
      "object" => String.duplicate("o", 64), "polarity" => "positive", "inferred" => false,
      "valid_from_ms" => nil, "valid_to_ms" => nil, "spans" => [[0, 0, 8]]}
    sources = for n <- 1..8, do: %{"source_key" => Ipse.JSON.sha256(Integer.to_string(n)), "facts" => List.duplicate(row, 20)}
    value = %{"version" => 1, "kind" => "explicit_fact_group", "sources" => sources}
    args = %{"store" => "local", "action" => "fact_input", "args" => %{"input" => %{"version" => 1, "mode" => "publish", "value" => value}}}
    original = M.new(%{}, 0)
    {{:blocked, :public_input_frame}, ^original} = M.public(resolved, "source", args, original)
    160 = Enum.sum(Enum.map(sources, &length(&1["facts"])))
    %{"frame_blocked" => true, "facts_retained" => 160}
    """)
  end

  test "unknown modeled effects retain the unmatched request and stop without a continuation", %{
    runtime: runtime
  } do
    model_test(runtime, ~S"""
    alias Ipse.CollectionRecipeModel, as: M
    {:call, request, _} = start = C.start(profile, :value_put_inline_at,
      %{"key" => "fixture.value", "value" => %{"version" => 1}, "generation" => 0, "expected_revision" => 0})
    {result, model} = M.run(start, M.new(%{}, 0), fn _, _ -> :unknown end)
    {:stop, :unknown_effect} = result
    [^request] = model.requests
    [%{"status" => "unknown", "value" => %{}}] = model.outcomes
    0 = map_size(model.operations)
    0 = model.generation
    1 = length(model.unknown)
    %{"unknown_stop" => true}
    """)
  end

  @tag :public_recipe_group
  test "one complete public group records input binding, pages, Native identities and codec events",
       %{runtime: runtime} do
    model_test(runtime, ~S"""
    file = ledger_source
    {:__block__, _, forms} = file |> File.read!() |> Code.string_to_quoted!()
    module = Enum.find(forms, &match?({:defmodule, _, _}, &1))
    {[_], []} = Code.with_diagnostics(fn -> Code.compile_quoted(module, file) end)
    out = Path.join(System.tmp_dir!(), "one-public-recipe-" <> Ipse.Usage.id())
    File.mkdir!(out)
    :ok = Ipse.CollectionRecipeLedger.run(1, out, [])
    report = out |> Path.join("summary.json") |> File.read!() |> Jason.decode!()
    %{"status" => "modeled_known", "value" => %{"coverage" => %{"status" => "selected"}}} = report["shared_result"]
    1 = report["sources"]
    10 = report["chunks"]
    0 = report["native_operations_executed"]
    nil = report["capacity_fit"]
    [published, assembled] = report["result_publications"]
    true = published["event_count"] >= 5 and assembled["event_count"] >= 5
    0 = published["action_event_count"]
    2 = assembled["action_event_count"]
    true = assembled["action_journal_bytes"] > 0
    rows = out |> Path.join("invocations.jsonl") |> File.stream!() |> Enum.map(&Jason.decode!/1)
    true = Enum.any?(rows, &(&1["section"] === "public_append" and &1["effects"] > 0))
    [assembly] = Enum.filter(rows, &(&1["section"] === "public_fact_assemble"))
    1 = assembly["reads"]
    1 = assembly["public_result"]["action_count"]
    true = is_binary(assembly["public_result"]["action_digest"])
    requests = Enum.flat_map(rows, & &1["requests"])
    true = Enum.any?(requests, &(&1["op"] === "restore.input.read" and &1["class"] === "collection_read"))
    true = Enum.any?(requests, &(&1["class"] === "embedding_attempt"))
    true = length(Enum.uniq_by(requests, & &1["action_id"])) === length(requests)
    0 = report["final_store"]["active_stages"]
    %{"public_group" => true, "fit_claimed" => false}
    """)
  end

  @tag :public_recipe_assembly
  test "eight published inputs retain real action-codec joins in the assembled result", %{
    runtime: runtime
  } do
    model_test(runtime, ~S"""
    alias Ipse.CollectionRecipeModel, as: M
    {refs, model} = Enum.map_reduce(1..8, M.new(%{}, 0), fn n, model ->
      rows = for i <- 1..20, do: %{"subject" => "entity#{n}", "predicate" => "relation#{i}",
        "object" => "entity#{n + 1}", "polarity" => "positive", "inferred" => false,
        "valid_from_ms" => nil, "valid_to_ms" => nil, "spans" => [[0, 0, 1]]}
      value = %{"version" => 1, "kind" => "explicit_fact_group", "sources" =>
        [%{"source_key" => Ipse.JSON.sha256(Integer.to_string(n)), "facts" => rows}]}
      args = %{"store" => "local", "action" => "fact_input", "args" =>
        %{"input" => %{"version" => 1, "mode" => "publish", "value" => value}}}
      {{:published, ref}, model} = M.public(resolved, "source", args, model)
      {ref, model}
    end)
    args = %{"store" => "local", "action" => "fact_input", "data_inputs" => refs,
      "args" => %{"input" => %{"version" => 1, "mode" => "assemble"}}}
    {{:published, assembled}, model} = M.public(resolved, "source", args, model)
    8 = model.reads
    0 = model.effects
    8 = length(model.action_ids)
    true = Enum.all?(model.action_intents, &is_map/1)
    publication = List.last(model.publications)
    16 = publication.action_event_count
    result = List.last(model.public_results)
    8 = result.action_count
    true = result.codec_events === publication.event_count
    true = result.codec_journal_bytes === publication.journal_bytes
    true = result.action_journal_bytes === publication.action_journal_bytes
    group = model.selected_inputs[Ipse.JSON.digest([assembled])].bytes |> Jason.decode!()
    true = Enum.map(group["sources"], & &1["source_key"]) ===
      Enum.map(1..8, &Ipse.JSON.sha256(Integer.to_string(&1)))
    160 = Enum.sum(Enum.map(group["sources"], &length(&1["facts"])))
    0 = map_size(model.operations)
    %{"assembled" => true, "read_actions" => 8, "native_operations" => 0}
    """)
  end

  @tag :public_recipe_legacy_helper
  test "legacy preparation diagnostic is zero-based and does not invent migration acceptance", %{
    runtime: runtime
  } do
    model_test(runtime, ~S"""
    {:__block__, _, forms} = ledger_source |> File.read!() |> Code.string_to_quoted!()
    module = Enum.find(forms, &match?({:defmodule, _, _}, &1))
    {[_], []} = Code.with_diagnostics(fn -> Code.compile_quoted(module, ledger_source) end)
    for {phase, options} <- [{"build", [response: "full"]}, {"transport", [phase: "transport"]}] do
      out = Path.join(System.tmp_dir!(), "recipe-phase-" <> Ipse.Usage.id())
      File.mkdir!(out)
      :ok = Ipse.CollectionRecipeLedger.run(1, out, options)
      summary = Path.join(out, "summary.json") |> File.read!() |> Jason.decode!()
      ^phase = summary["phase"]
      0 = summary["fresh_generation"]
      if phase === "build" do
        "full" = summary["requested_response"]
        "compact_v1" = summary["public_response"]
        "modeled_known" = summary["shared_result"]["status"]
      else
        transport = Path.join(out, "per-value-transport.json") |> File.read!() |> Jason.decode!()
        false = Map.has_key?(transport, "prepare_plus_proposed_accept_mutations")
        true = Enum.all?(transport["per_value"], fn row ->
          row["modeled_start_generation"] === 0 and
            row["modeled_final_generation"] === row["actual_prepare_mutations"] and
            not Map.has_key?(row, "prepare_plus_proposed_accept_mutations")
        end)
      end
    end
    %{"legacy_scope_explicit" => true, "proposed_accept_removed" => true}
    """)
  end

  @tag :public_recipe_trace_failure
  test "failed trace write stops before the next controller invocation or phase", %{
    runtime: runtime
  } do
    model_test(runtime, ~S"""
    {:__block__, _, forms} = ledger_source |> File.read!() |> Code.string_to_quoted!()
    module = Enum.find(forms, &match?({:defmodule, _, _}, &1))
    {[_], []} = Code.with_diagnostics(fn -> Code.compile_quoted(module, ledger_source) end)
    out = Path.join(System.tmp_dir!(), "recipe-trace-failure-" <> Ipse.Usage.id())
    File.mkdir!(out)
    writer = fn _device, bytes ->
      row = Jason.decode!(bytes)
      send(self(), {:attempted_row, Map.take(row, ~w(sequence section item effects))})
      Process.put(:failed_trace_attempts, Process.get(:failed_trace_attempts, 0) + 1)
      {:error, :enospc}
    end
    failed = try do
      Ipse.CollectionRecipeLedger.run(2, out, trace_write: writer)
      false
    rescue
      error in MatchError -> error.term === {:error, :enospc}
    after
      :ok = File.close(Process.get(:ledger))
    end
    true = failed
    1 = Process.get(:failed_trace_attempts)
    1 = Process.get(:sequence)
    1 = Process.get(:totals).invocations
    receive do
      {:attempted_row, %{"sequence" => 1, "section" => "source", "item" => 0, "effects" => effects}} when effects > 0 -> :ok
    after 0 -> raise "first modeled invocation was not observed"
    end
    receive do
      {:attempted_row, _} -> raise "later invocation was attempted"
    after 0 -> :ok
    end
    "" = File.read!(Path.join(out, "invocations.jsonl"))
    false = File.exists?(Path.join(out, "source-summary.json"))
    false = File.exists?(Path.join(out, "lexical-summary.json"))
    false = File.exists?(Path.join(out, "summary.json"))
    %{"trace_failure_stops" => true, "retained_rows" => 0, "native_operations" => 0}
    """)
  end

  @tag :public_recipe_stop_and_resume
  test "source stops retain the terminal trace and resumed summaries count only new publications",
       %{
         runtime: runtime
       } do
    model_test(runtime, ~S"""
    {:__block__, _, forms} = ledger_source |> File.read!() |> Code.string_to_quoted!()
    module = Enum.find(forms, &match?({:defmodule, _, _}, &1))
    {[_], []} = Code.with_diagnostics(fn -> Code.compile_quoted(module, ledger_source) end)
    for {terminal, status} <- [{{:refused, %{"status" => "refused"}}, "refused"},
                               {{:blocked, :public_input_frame}, "blocked"},
                               {{:stop, :unknown_effect}, "unknown"}] do
      out = Path.join(System.tmp_dir!(), "recipe-source-stop-" <> Ipse.Usage.id())
      File.mkdir!(out)
      hook = fn "source", {_result, model} ->
        model = if status === "unknown", do: %{model | unknown: ["injected-unknown"]}, else: model
        {terminal, model}
        _, result -> result
      end
      {:stopped, ^terminal} = Ipse.CollectionRecipeLedger.run(2, out, controller_result_hook: hook)
      [row] = Path.join(out, "invocations.jsonl") |> File.stream!() |> Enum.map(&Jason.decode!/1)
      ^status = row["terminal_status"]
      0 = row["item"]
      if status === "unknown", do: ["injected-unknown"] = row["unknown_requests"]
      false = File.exists?(Path.join(out, "source-summary.json"))
      false = File.exists?(Path.join(out, "summary.json"))
    end
    # Resume uses the completed model's selected input registry but must not
    # attribute its already-reported publications to the new diagnostic phase.
    first = Path.join(System.tmp_dir!(), "recipe-first-" <> Ipse.Usage.id())
    File.mkdir!(first)
    :ok = Ipse.CollectionRecipeLedger.run(1, first, [])
    first_summary = Path.join(first, "summary.json") |> File.read!() |> Jason.decode!()
    2 = length(first_summary["result_publications"])
    checkpoint = Path.expand("_build/recipe-resume-" <> Ipse.Usage.id() <> ".term")
    File.mkdir_p!(Path.dirname(checkpoint))
    File.cp!(Path.join(first, "final-model.term"), checkpoint)
    resumed = Path.join(System.tmp_dir!(), "recipe-resumed-" <> Ipse.Usage.id())
    File.mkdir!(resumed)
    try do
      :ok = Ipse.CollectionRecipeLedger.run(1, resumed, phase: "transport", resume: checkpoint)
      summary = Path.join(resumed, "summary.json") |> File.read!() |> Jason.decode!()
      [] = summary["result_publications"]
      restored = :erlang.binary_to_term(File.read!(Path.join(resumed, "final-model.term")), [:safe])
      2 = length(restored.publications)
      2 = map_size(restored.selected_inputs)
    after
      File.rm!(checkpoint)
    end
    %{"terminal_stops" => true, "resume_publications_are_phase_local" => true}
    """)
  end

  @tag :public_recipe_replacement
  test "resumed replacement preserves prior modeled receipts and selects the new source",
       %{runtime: runtime} do
    runtime = Map.update!(runtime, :env, &List.keystore(&1, "TZ", 0, {"TZ", "UTC-8"}))

    model_test(runtime, ~S"""
    {:__block__, _, forms} = ledger_source |> File.read!() |> Code.string_to_quoted!()
    module = Enum.find(forms, &match?({:defmodule, _, _}, &1))
    {[_], []} = Code.with_diagnostics(fn -> Code.compile_quoted(module, ledger_source) end)
    first = Path.join(System.tmp_dir!(), "recipe-replacement-first-" <> Ipse.Usage.id())
    File.mkdir!(first)
    :ok = Ipse.CollectionRecipeLedger.run(1, first, [])
    checkpoint = Path.expand("_build/recipe-replacement-" <> Ipse.Usage.id() <> ".term")
    File.mkdir_p!(Path.dirname(checkpoint))
    File.cp!(Path.join(first, "final-model.term"), checkpoint)
    {:ok, utc_stat} = File.lstat(checkpoint)
    {:ok, local_record} = :file.read_file_info(String.to_charlist(checkpoint))
    true = utc_stat.mtime != File.Stat.from_record(local_record).mtime
    checkpoint_sha = checkpoint |> File.read!() |> Ipse.JSON.sha256()
    output = Path.join(System.tmp_dir!(), "recipe-replacement-next-" <> Ipse.Usage.id())
    File.mkdir!(output)
    try do
      :ok = Ipse.CollectionRecipeLedger.run(1, output, phase: "replacement", resume: checkpoint, resume_sha256: checkpoint_sha)
      summary = Path.join(output, "summary.json") |> File.read!() |> Jason.decode!()
      "public_controller_replacement_model" = summary["kind"]
      ^checkpoint_sha = summary["checkpoint_sha256"]
      1 = summary["previous_source_generation"]
      2 = summary["new_source_generation"]
      1 = summary["previous_source_revision"]
      2 = summary["new_source_revision"]
      true = summary["prior_operation_ids_preserved"] > 0
      true = summary["retained_immutable_records"] > 0
      true = summary["intermediate_old_selection_checks"] > 0
      0 = summary["native_operations_executed"]
      false = summary["full_recipe_implemented"]
      nil = summary["capacity_fit"]
      0 = summary["after"]["active_stages"]
      rows = Path.join(output, "invocations.jsonl") |> File.stream!() |> Enum.map(&Jason.decode!/1)
      true = Enum.any?(rows, &(&1["section"] === "public_replacement" and &1["effects"] > 0))
      true = Enum.any?(rows, &(&1["section"] === "replacement_selection_intermediate"))

      seed_model = :erlang.binary_to_term(File.read!(checkpoint), [:safe])
      true = map_size(seed_model.operations) > 0
      bad_history = checkpoint <> ".missing-history"
      oversized = checkpoint <> ".oversized"
      trailing = checkpoint <> ".trailing"
      symlink = checkpoint <> ".symlink"
      linked_directory = checkpoint <> ".directory-link"
      File.write!(bad_history, :erlang.term_to_binary(%{seed_model | operations: %{}}, [:compressed]), [:exclusive])
      File.write!(oversized, <<131, 80, 536_870_913::unsigned-big-32, 0>>, [:exclusive])
      File.write!(trailing, File.read!(checkpoint) <> "trailing", [:exclusive])
      :ok = File.ln_s(checkpoint, symlink)
      :ok = File.ln_s(Path.dirname(checkpoint), linked_directory)
      try do
        for {path, pin} <- [
              {checkpoint, String.duplicate("0", 64)},
              {bad_history, bad_history |> File.read!() |> Ipse.JSON.sha256()},
              {oversized, oversized |> File.read!() |> Ipse.JSON.sha256()},
              {trailing, trailing |> File.read!() |> Ipse.JSON.sha256()},
              {symlink, checkpoint_sha},
              {Path.join(linked_directory, Path.basename(checkpoint)), checkpoint_sha}
            ] do
          refused_out = Path.join(System.tmp_dir!(), "recipe-replacement-invalid-" <> Ipse.Usage.id())
          File.mkdir!(refused_out)
          refused = try do
            Ipse.CollectionRecipeLedger.run(1, refused_out, phase: "replacement", resume: path, resume_sha256: pin)
            false
          rescue
            _ -> true
          end
          true = refused
          false = File.exists?(Path.join(refused_out, "invocations.jsonl"))
          false = File.exists?(Path.join(refused_out, "summary.json"))
        end
      after
        File.rm!(bad_history)
        File.rm!(oversized)
        File.rm!(trailing)
        File.rm!(symlink)
        File.rm!(linked_directory)
      end
    after
      File.rm!(checkpoint)
    end
    %{"replacement_modeled" => true, "native_claimed" => false}
    """)
  end

  @tag :public_recipe_replacement_stop
  test "replacement stops at unknown, malformed, refused and repeated continuations",
       %{runtime: runtime} do
    model_test(runtime, ~S"""
    {:__block__, _, forms} = ledger_source |> File.read!() |> Code.string_to_quoted!()
    module = Enum.find(forms, &match?({:defmodule, _, _}, &1))
    {[_], []} = Code.with_diagnostics(fn -> Code.compile_quoted(module, ledger_source) end)
    first = Path.join(System.tmp_dir!(), "recipe-replacement-stop-seed-" <> Ipse.Usage.id())
    File.mkdir!(first)
    :ok = Ipse.CollectionRecipeLedger.run(1, first, [])
    checkpoint = Path.expand("_build/recipe-replacement-stop-" <> Ipse.Usage.id() <> ".term")
    File.mkdir_p!(Path.dirname(checkpoint))
    File.cp!(Path.join(first, "final-model.term"), checkpoint)
    checkpoint_sha = checkpoint |> File.read!() |> Ipse.JSON.sha256()

    try do
      for scenario <- [:unknown, :unknown_status, :refused_with_continuation, :malformed, :foreign_route, :foreign_source, :repeated] do
        out = Path.join(System.tmp_dir!(), "recipe-replacement-stop-" <> Ipse.Usage.id())
        File.mkdir!(out)
        Process.delete(:replacement_first_continuation)
        hook = fn
          "public_replacement", {{:ok, %{"status" => "draft", "continuation" => continuation} = value}, model} ->
            case scenario do
              :unknown -> {{:ok, value}, %{model | unknown: ["injected-unknown"]}}
              :unknown_status -> {{:ok, %{value | "status" => "unknown"}}, model}
              :refused_with_continuation -> {{:ok, %{value | "status" => "refused"}}, model}
              :malformed -> {{:ok, put_in(value, ["continuation", "id"], "wrong")}, model}
              :foreign_route -> {{:ok, put_in(value, ["continuation", "arguments", "action"], "continue_collection_document")}, model}
              :foreign_source -> {{:ok, put_in(value, ["continuation", "arguments", "args", "input_args", "source_id"], "fixture:foreign")}, model}
              :repeated ->
                case Process.get(:replacement_first_continuation) do
                  nil -> Process.put(:replacement_first_continuation, continuation); {{:ok, value}, model}
                  previous -> {{:ok, %{value | "continuation" => previous}}, model}
                end
            end
          _, result -> result
        end
        result = Ipse.CollectionRecipeLedger.run(1, out, phase: "replacement", resume: checkpoint, resume_sha256: checkpoint_sha, controller_result_hook: hook)
        case scenario do
          :unknown -> {:stopped, {:stop, :unknown_effect}} = result
          :unknown_status -> {:stopped, {:ok, %{"status" => "unknown"}}} = result
          :refused_with_continuation -> {:stopped, {:ok, %{"status" => "refused"}}} = result
          :malformed -> {:stopped, {:blocked, :invalid_replacement_continuation}} = result
          :foreign_route -> {:stopped, {:blocked, :invalid_replacement_continuation}} = result
          :foreign_source -> {:stopped, {:blocked, :invalid_replacement_continuation}} = result
          :repeated -> {:stopped, {:blocked, :replacement_continuation_repeated}} = result
        end
        rows = Path.join(out, "invocations.jsonl") |> File.stream!() |> Enum.map(&Jason.decode!/1)
        sections = Enum.map(rows, & &1["section"])
        if scenario === :repeated do
          ["replacement_selection_before", "public_replacement", "replacement_selection_intermediate", "public_replacement"] = sections
        else
          ["replacement_selection_before", "public_replacement"] = sections
        end
        if scenario === :unknown, do: ["injected-unknown"] = List.last(rows)["unknown_requests"]
        terminal = Path.join(out, "terminal.json") |> File.read!() |> Jason.decode!()
        expected = if scenario in [:unknown, :unknown_status], do: "unknown", else: if(scenario === :refused_with_continuation, do: "refused", else: "blocked")
        ^expected = terminal["status"]
        0 = terminal["native_operations_executed"]
        false = File.exists?(Path.join(out, "final-model.term"))
        false = File.exists?(Path.join(out, "summary.json"))
      end
    after
      File.rm!(checkpoint)
    end
    %{"unsafe_continuations_stopped" => true, "native_operations" => 0}
    """)
  end

  @tag :public_recipe_lexical_stop
  test "a lexical terminal stops before the shared phase", %{runtime: runtime} do
    model_test(runtime, ~S"""
    {:__block__, _, forms} = ledger_source |> File.read!() |> Code.string_to_quoted!()
    module = Enum.find(forms, &match?({:defmodule, _, _}, &1))
    {[_], []} = Code.with_diagnostics(fn -> Code.compile_quoted(module, ledger_source) end)
    out = Path.join(System.tmp_dir!(), "recipe-lexical-stop-" <> Ipse.Usage.id())
    File.mkdir!(out)
    hook = fn
      "public_lexical", {_result, model} -> {{:stop, :unknown_effect}, %{model | unknown: ["lexical-unknown"]}}
      _, result -> result
    end
    {:stopped, {:stop, :unknown_effect}} = Ipse.CollectionRecipeLedger.run(1, out, controller_result_hook: hook)
    rows = Path.join(out, "invocations.jsonl") |> File.stream!() |> Enum.map(&Jason.decode!/1)
    last = List.last(rows)
    "public_lexical" = last["section"]
    "unknown" = last["terminal_status"]
    ["lexical-unknown"] = last["unknown_requests"]
    false = Enum.any?(rows, &(&1["section"] === "public_begin"))
    false = File.exists?(Path.join(out, "lexical-summary.json"))
    false = File.exists?(Path.join(out, "summary.json"))
    %{"lexical_unknown_stops" => true}
    """)
  end

  defp prepare_runtime do
    paths =
      ~w(profiles evidence store store/state store/mcp_cas store/collection
      store/collection/index store/collection/projection store/collection/generation
      store/collection/directory store/collection/selected store/collection/job
      store/collection/reduction store/collection/finalization store/collection/paged
      store/collection/producer store/collection/producer_progress adapters documents
      documents/zip documents/docx documents/parser_stage documents/pdf corpus)
      |> Enum.map(&Path.expand("../../../extensions/knowledge/src/#{&1}.ex", __DIR__))

    modules =
      Enum.flat_map(paths, fn path ->
        {_, modules} =
          path
          |> File.read!()
          |> Code.string_to_quoted!()
          |> Macro.prewalk([], fn
            {:defmodule, _, [{:__aliases__, _, parts}, _]} = node, found ->
              {node, [Module.concat(parts) | found]}

            node, found ->
              {node, found}
          end)

        modules
      end)

    spec = %{
      name: "public-recipe-model",
      source: hd(paths),
      sources: paths,
      module: IpseKnowledge.Corpus,
      modules: modules,
      retained: true
    }

    options = [
      sdk: Application.app_dir(:ipse, "ebin"),
      input: Path.expand("../../../examples/memory-corpus.json", __DIR__),
      output: Path.join(System.tmp_dir!(), "recipe-model-runtime-" <> Ipse.Usage.id())
    ]

    Runtime.with_runtime(spec, options, & &1)
  end

  defp model_test(runtime, body) do
    expression = """
    Code.require_file(#{inspect(Path.expand("../../../dev/knowledge/collection_recipe_model.ex", __DIR__))})
      ledger_source = #{inspect(Path.expand("../../../dev/knowledge/collection_recipe_ledger.exs", __DIR__))}
    alias IpseKnowledge.Store.Collection, as: C
    profile = %{"kind" => "collection", "scope" => "project", "partition" => "notes"}
    options = Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})
      |> Map.merge(%{"version" => 1, "stores" => %{"local" => profile},
        "retrieval" => %{"words" => %{"kind" => "bm25", "version" => 1}},
        "embedding" => %{"learned" => %{"kind" => "embedding", "profile" => "encoder"}}})
    {:ok, resolved} = IpseKnowledge.Profiles.validate("corpus", "collection-dense", options)
    #{body}
    """

    result = Runtime.eval!(runtime, expression)
    assert is_map(result)
  end
end
