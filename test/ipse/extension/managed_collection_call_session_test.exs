Code.require_file("../../support/provider_fixture.ex", __DIR__)
Code.require_file("../../support/managed_mcp_http.exs", __DIR__)
Code.require_file("../../support/managed_delivery_sink.exs", __DIR__)

defmodule Ipse.Extension.ManagedCollectionCallSessionTest do
  use ExUnit.Case, async: false
  @native_root_approval System.get_env("IPSE_TEST_NATIVE_ROOT_APPROVAL") == "1"
  alias Ipse.{Session, Journal, JSON}
  import Ipse.Test.ResumeAssertions

  alias Ipse.Extension.{
    Artifact,
    Catalog,
    Registry,
    SemanticAdmission,
    SemanticConsent,
    Consent,
    ProjectIdentity
  }

  defmodule Model do
    def complete(config, messages, _, _) do
      if config[:legacy_question_fixture] do
        args = %{
          "questions" => [
            %{"id" => "detail", "kind" => "text", "prompt" => "SYNTHETIC_LEGACY_MANAGED_QUESTION"}
          ]
        }

        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "legacy_question",
               "function" => %{"name" => "ask_operator", "arguments" => Jason.encode!(args)}
             }
           ]
         }, %{}}
      else
        if Enum.any?(messages, &(&1["role"] == "tool")) do
          {:ok, %{"role" => "assistant", "content" => "Synthetic capture finished."}, %{}}
        else
          {:ok,
           %{
             "role" => "assistant",
             "content" => "",
             "tool_calls" => [
               %{
                 "id" => "capture",
                 "type" => "function",
                 "function" => %{
                   "name" => "ext__capture__" <> (config[:fixture_export] || "capture"),
                   "arguments" => Jason.encode!(%{"mode" => config[:fixture_mode] || "capture"})
                 }
               }
             ]
           }, %{}}
        end
      end
    end
  end

  defmodule PresentationModel do
    def complete(_, _, _, _),
      do: {:ok, %{"role" => "assistant", "content" => "Synthetic ordinary answer."}, %{}}
  end

  defmodule OrdinaryDeliveryModel do
    def complete(_, messages, _, emit) do
      if Enum.any?(messages, &(&1["role"] == "tool")) do
        emit.({:text, "Synthetic ordinary delivery answer."})
        {:ok, %{"role" => "assistant", "content" => "Synthetic ordinary delivery answer."}, %{}}
      else
        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "ordinary_delivery",
               "function" => %{
                 "name" => "write",
                 "arguments" =>
                   Jason.encode!(%{
                     "path" => "ordinary-delivery.txt",
                     "content" => "SYNTHETIC_ORDINARY_DELIVERY"
                   })
               }
             }
           ]
         }, %{}}
      end
    end
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-collection-sdk-artifact-" <> Ipse.Usage.id())
    File.mkdir_p!(Path.join(root, "ebin"))
    on_exit(fn -> File.rm_rf!(root) end)
    name = "Independent.Collection#{System.unique_integer([:positive])}"

    capabilities =
      ~w(invoke.tool invoke.command invoke.service invoke.result.pages host.actions host.sources host.collection.read host.collection.write host.collection.managed host.context host.tools host.model host.decision host.embedding host.mcp host.state.read host.state.write host.question)

    service = %{
      "id" => "observe",
      "description" => "Synthetic marker",
      "arguments_schema" => %{"type" => "object"},
      "result_schema" => %{"type" => "object"}
    }

    exports =
      Catalog.empty()
      |> Map.put("tools", [
        %{
          "id" => "capture",
          "description" => "Synthetic constrained capture",
          "arguments_schema" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["mode"],
            "properties" => %{"mode" => %{"type" => "string"}}
          },
          "result_schema" => %{"type" => "object"}
        }
      ])
      |> then(fn exports ->
        Map.update!(exports, "tools", fn [capture] ->
          [capture, %{capture | "id" => "inspect"}]
        end)
      end)
      |> then(fn exports -> Map.put(exports, "commands", exports["tools"]) end)
      |> Map.put("services", [service])

    source = """
    defmodule #{name} do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 2, "capabilities" => #{inspect(capabilities)}, "exports" => #{inspect(exports)}}
      def init(options), do: {:ok, options}
      def handle("invoke.service", payload, state) do
        File.write!(state["trace"] <> ".service", Jason.encode!(payload))
        {:ok, %{"api_version" => 1, "kind" => "result", "value" => %{}}, state}
      end
      def handle(stage, payload, state) when stage in ["invoke.tool", "invoke.command"] do
        File.write!(state["trace"], "entered\\n", [:append])
        state = Map.put(state, "mode", payload["arguments"]["mode"])
        cond do
        String.starts_with?(state["mode"], "legacy_get:") ->
          key = String.replace_prefix(state["mode"], "legacy_get:", "")
          call(%{"op" => "collection.call", "request" => %{"op" => "get", "key" => key}}, Map.put(state, "step", "done"))
        state["mode"] == "ordinary" ->
          call(%{"op" => "tool.call", "name" => "write", "timeout_ms" => 1000, "arguments" => %{"path" => "forbidden", "content" => "denied"}}, Map.put(state, "step", "done"))
        state["mode"] in ["capture_ab", "capture_ab_publication"] ->
          call(%{"op" => "collection.call", "request" => %{"op" => "snapshot"}}, Map.put(state, "step", "ab_snapshot"))
        state["mode"] in ["capture_ab_literal", "capture_ab_literal_publication", "capture_ab_literal_publication_hold"] ->
          call(%{"op" => "collection.call", "request" => %{"op" => "get", "key" => state["literal_key"]}}, Map.put(state, "step", "ab_literal_read"))
        String.starts_with?(state["mode"], "host_ordinary:") ->
          advance("nested_host", nil, state)
        String.starts_with?(state["mode"], "host_managed:") ->
          call(%{"op" => "collection.call", "request" => %{"op" => "snapshot"}}, Map.put(state, "step", "nested_host"))
        state["mode"] in ["read", "read_hold", "paged_read"] ->
          call(%{"op" => "collection.call", "request" => %{"op" => "snapshot"}}, Map.put(state, "step", "done"))
        state["mode"] == "helper" ->
          call(%{"op" => "collection.call", "request" => %{"op" => "snapshot"}}, Map.put(state, "step", "helper_read"))
        state["mode"] == "embedding_helper" ->
          call(%{"op" => "collection.call", "request" => %{"op" => "snapshot"}}, Map.put(state, "step", "embedding_read"))
        state["mode"] == "decision_helper" ->
          call(%{"op" => "collection.call", "request" => %{"op" => "snapshot"}}, Map.put(state, "step", "decision_read"))
        state["mode"] == "decision_literal" ->
          call(%{"op" => "collection.call", "request" => %{"op" => "get", "key" => state["literal_key"]}}, Map.put(state, "step", "decision_literal_read"))
        state["mode"] == "decision_pack" ->
          call(%{"op" => "collection.call", "request" => %{"op" => "index", "prefix" => "note.", "cursor" => nil, "limit" => 32}}, Map.put(state, "step", "pack_index"))
        state["mode"] == "decision_pack_actual" ->
          call(%{"op" => "context.available"}, Map.put(state, "step", "pack_budget"))
        state["mode"] == "decision_pack_wide" ->
          call(%{"op" => "source.list", "limit" => 32}, Map.put(state, "step", "wide_query_list"))
        state["mode"] == "nested_mcp" ->
          call(%{"op" => "collection.call", "request" => %{"op" => "snapshot"}}, Map.put(state, "step", "nested_mcp"))
        state["mode"] == "nested_native" ->
          call(%{"op" => "collection.call", "request" => %{"op" => "snapshot"}}, Map.put(state, "step", "nested_native"))
        state["mode"] in ["nested_document", "nested_document_hold"] ->
          call(%{"op" => "collection.call", "request" => %{"op" => "snapshot"}}, Map.put(state, "step", "nested_document"))
        true ->
          call(%{"op" => "source.list", "limit" => 32}, Map.put(state, "step", "list"))
        end
      end
      def handle("host.actions", %{"outcome" => outcome} = payload, state) do
        File.write!(state["trace"], Jason.encode!(outcome) <> "\\n", [:append])
        advance(state["step"], outcome, Map.put(state, "last_operation", payload["operation_id"]))
      end
      defp advance("helper_read", outcome, state) do
        call(%{"op" => "model.complete", "version" => 1, "profile" => "extract", "instruction" => "Summarize the supplied observation", "input" => Jason.encode!(outcome), "max_output_bytes" => 1024, "timeout_ms" => 3000}, Map.put(state, "step", "done"))
      end
      defp advance("embedding_read", outcome, state) do
        call(%{"op" => "embedding.create", "version" => 2, "profile" => "embed", "inputs" => [Jason.encode!(outcome)], "timeout_ms" => 3000}, Map.put(state, "step", "done"))
      end
      defp advance("decision_read", outcome, state) do
        call(%{"op" => "decision.create", "version" => 1, "profile" => "advice", "input" => Jason.encode!(outcome), "questions" => [%{"id" => "relevant", "type" => "predicate", "instructions" => "Synthetic fixture"}], "timeout_ms" => 3000}, Map.put(state, "step", "done"))
      end
      defp advance("decision_literal_read", %{"status" => "ok", "value" => %{"record" => %{"value" => _}}} = outcome, state), do: advance("decision_read", outcome, state)
      defp advance("wide_query_list", %{"status" => "ok", "value" => %{"sources" => sources}}, state) do
        row = Enum.find(Enum.reverse(sources), &(&1["kind"] == "input.original"))
        call(%{"op" => "source.read", "handle" => row["read_handle"]}, Map.put(state, "step", "wide_query_read"))
      end
      defp advance("wide_query_read", %{"status" => "ok", "value" => %{"text" => query, "complete" => true}}, state) when is_binary(query) and byte_size(query) <= 1024 do
        call(%{"op" => "context.available"}, state |> Map.put("step", "pack_budget") |> Map.put("wide_query", query))
      end
      defp advance("pack_budget", %{"status" => "ok", "value" => %{"instance" => "capture", "available_bytes" => available}}, state) do
        step = if state["mode"] == "decision_pack_wide", do: "wide_index", else: "pack_index"
        call(%{"op" => "collection.call", "request" => %{"op" => "index", "prefix" => "note.", "cursor" => nil, "limit" => 32}}, state |> Map.put("step", step) |> Map.put("actual_available", min(available, 8192)))
      end
      defp advance("wide_index", %{"status" => "ok", "value" => %{"records" => rows, "next" => nil, "count" => 8, "generation" => generation}}, state) when length(rows) == 8 do
        [first | rest] = rows
        call(%{"op" => "collection.call", "request" => %{"op" => "get", "key" => first["key"]}}, state |> Map.put("step", "wide_read") |> Map.put("wide_index", rows) |> Map.put("wide_expected", first) |> Map.put("wide_pending", rest) |> Map.put("wide_generation", generation) |> Map.put("wide_notes", []))
      end
      defp advance("wide_read", %{"status" => "ok", "value" => %{"record" => record, "generation" => generation}}, state) do
        true = generation == state["wide_generation"] and record["key"] == state["wide_expected"]["key"]
        state = Map.update!(state, "wide_notes", &(&1 ++ [{record, state["last_operation"]}]))
        case state["wide_pending"] do
          [next | rest] -> call(%{"op" => "collection.call", "request" => %{"op" => "get", "key" => next["key"]}}, state |> Map.put("wide_expected", next) |> Map.put("wide_pending", rest))
          [] -> call(%{"op" => "collection.call", "request" => %{"op" => "index", "prefix" => "note.", "cursor" => nil, "limit" => 1}}, Map.put(state, "step", "wide_verify"))
        end
      end
      defp advance("wide_verify", %{"status" => "ok", "value" => %{"generation" => generation, "count" => 8}}, state) do
        true = generation == state["wide_generation"]
        notes = state["wide_notes"]
        ctx = %{notes: notes, index: state["wide_index"], total: 8, generation: generation, verified: true, coverage: "complete", next: nil, start_cursor: nil, unavailable: 0}
        [first, second | _] = Enum.map(notes, fn {row, _} -> row["key"] end)
        packs = [%{"id" => "first", "members" => [first]}, %{"id" => "second", "members" => [second]}]
        knowledge = Module.concat(["IpseKnowledge", "Knowledge"])
        policy_module = Module.concat(["IpseKnowledge", "Knowledge", "DecisionPolicy"])
        budget = state["actual_available"]
        {:ok, full} = apply(knowledge, :recall_projection, [ctx, notes, "capture", budget])
        false = full.fits
        {:ok, facts, binding} = apply(knowledge, :recall_decision_facts, [ctx, packs, "capture", budget, state["wide_query"], true, "first"])
        policy = apply(policy_module, :default, ["notes.select"]) |> Map.merge(%{"strategy" => "decision", "profile" => "advice"})
        {:ok, plan} = apply(policy_module, :plan, [policy, facts, :development_experiment])
        true = is_map(plan.request)
        call(plan.request, state |> Map.put("step", "pack_advice") |> Map.put("pack_ctx", ctx) |> Map.put("pack_binding", binding) |> Map.put("pack_plan", plan))
      end
      defp advance("pack_index", %{"status" => "ok", "value" => %{"records" => [first, second], "next" => nil, "count" => 2, "generation" => generation}}, state) do
        call(%{"op" => "collection.call", "request" => %{"op" => "get", "key" => first["key"]}}, state |> Map.put("step", "pack_first") |> Map.put("pack_index", [first, second]) |> Map.put("pack_generation", generation))
      end
      defp advance("pack_first", %{"status" => "ok", "value" => %{"record" => record, "generation" => generation}}, state) do
        true = generation == state["pack_generation"] and record["key"] == hd(state["pack_index"])["key"]
        call(%{"op" => "collection.call", "request" => %{"op" => "get", "key" => List.last(state["pack_index"])["key"]}}, state |> Map.put("step", "pack_second") |> Map.put("pack_first", {record, state["last_operation"]}))
      end
      defp advance("pack_second", %{"status" => "ok", "value" => %{"record" => record, "generation" => generation}}, state) do
        true = generation == state["pack_generation"] and record["key"] == List.last(state["pack_index"])["key"]
        call(%{"op" => "collection.call", "request" => %{"op" => "index", "prefix" => "note.", "cursor" => nil, "limit" => 1}}, state |> Map.put("step", "pack_verify") |> Map.put("pack_second", {record, state["last_operation"]}))
      end
      defp advance("pack_verify", %{"status" => "ok", "value" => %{"generation" => generation, "count" => 2}}, state) do
        true = generation == state["pack_generation"]
        notes = [state["pack_first"], state["pack_second"]]
        ctx = %{notes: notes, index: state["pack_index"], total: 2, generation: generation, verified: true, coverage: "complete", next: nil, start_cursor: nil, unavailable: 0}
        [first, second] = Enum.map(notes, fn {row, _} -> row["key"] end)
        packs = [%{"id" => "first", "members" => [first]}, %{"id" => "second", "members" => [second]}]
        knowledge = Module.concat(["IpseKnowledge", "Knowledge"])
        policy_module = Module.concat(["IpseKnowledge", "Knowledge", "DecisionPolicy"])
        {:ok, projections} = apply(knowledge, :recall_pack_projections, [ctx, packs, "capture", 6144])
        budget = if state["mode"] == "decision_pack_actual", do: state["actual_available"], else: Enum.max(Enum.map(projections, & &1.projection.rendered_bytes)) + 20
        {:ok, facts, binding} = apply(knowledge, :recall_decision_facts, [ctx, packs, "capture", budget, "synthetic query", true, "first"])
        policy = apply(policy_module, :default, ["notes.select"]) |> Map.merge(%{"strategy" => "decision", "profile" => "advice"})
        {:ok, plan} = apply(policy_module, :plan, [policy, facts, :development_experiment])
        if plan.request do
          call(plan.request, state |> Map.put("step", "pack_advice") |> Map.put("pack_ctx", ctx) |> Map.put("pack_binding", binding) |> Map.put("pack_plan", plan))
        else
          {:ok, %{outcome: outcome, projection: projection}} = apply(knowledge, :recall_decision_projection, [ctx, plan, binding, nil, "capture"])
          File.write!(state["trace"], "pack-bypass\\n", [:append])
          {:ok, reply} = Ipse.Extension.ResultPublication.prepare(%{"status" => "shadow_only", "reason" => outcome["receipt"]["reason"], "fits" => projection.fits})
          {:ok, reply, state}
        end
      end
      defp advance("pack_advice", %{"status" => "ok", "value" => %{"result" => result}}, state) do
        knowledge = Module.concat(["IpseKnowledge", "Knowledge"])
        {:ok, %{outcome: outcome, projection: projection}} = apply(knowledge, :recall_decision_projection, [state["pack_ctx"], state["pack_plan"], state["pack_binding"], result, "capture"])
        if state["mode"] == "decision_pack_wide" do
          {:ok, comparison} = apply(knowledge, :recall_shadow_comparison, [state["pack_ctx"], state["pack_plan"], state["pack_binding"], result, "capture"])
          true = comparison.baseline.fits
          true = if outcome["receipt"]["reason"] == "selected", do: comparison.shadow == projection, else: is_nil(comparison.shadow)
          File.write!(state["trace"], "baseline-compared:" <> Integer.to_string(comparison.baseline.included) <> "\\n", [:append])
          if is_nil(comparison.shadow) do
            true = comparison.ordinary.items == comparison.baseline.items
            File.write!(state["trace"], "pack-baseline-only:" <> outcome["receipt"]["reason"] <> "\\n", [:append])
          end
        end
        if outcome["receipt"]["reason"] == "selected", do: File.write!(state["trace"], "pack-reprojected\\n", [:append])
        {:ok, reply} = Ipse.Extension.ResultPublication.prepare(%{"status" => "shadow_only", "choice" => if(outcome["receipt"]["reason"] == "selected", do: outcome["action"]["pack"]), "fits" => projection.fits})
        {:ok, reply, state}
      end
      defp advance("pack_advice", %{"status" => status} = failure, state) when status in ["failed", "unknown", "denied"] do
        knowledge = Module.concat(["IpseKnowledge", "Knowledge"])
        {:ok, comparison} = apply(knowledge, :recall_shadow_failure, [state["pack_ctx"], state["pack_plan"], state["pack_binding"], failure, "capture"])
        true = is_nil(comparison.shadow)
        File.write!(state["trace"], "pack-host-failure:" <> comparison.outcome["receipt"]["reason"] <> "\\n", [:append])
        {:ok, reply} = Ipse.Extension.ResultPublication.prepare(%{"status" => "shadow_only", "reason" => comparison.outcome["receipt"]["reason"]})
        {:ok, reply, state}
      end
      defp advance("ab_snapshot", %{"status" => "ok", "value" => snapshot}, state) do
        call(%{"op" => "collection.call", "request" => %{"op" => "scan", "after" => nil, "generation" => snapshot["generation"], "limit" => 4}}, Map.put(state, "step", "ab_read"))
      end
      defp advance("ab_literal_read", %{"status" => "ok", "value" => %{"record" => %{"value" => _}}} = outcome, state) do
        advance("ab_read", outcome, state)
      end
      defp advance("ab_read", %{"status" => "ok", "value" => %{"record" => %{"value" => _}}} = outcome, state) do
        value = outcome["value"] |> Map.put("records", [outcome["value"]["record"]]) |> Map.delete("record")
        advance("ab_read", Map.put(outcome, "value", value), state)
      end
      defp advance("ab_read", %{"status" => "ok", "value" => %{"records" => [_ | _]}} = outcome, state) do
        if state["mode"] not in ["capture_ab_publication", "capture_ab_literal_publication", "capture_ab_literal_publication_hold"] do
        File.write!(state["trace"], "ab-held\\n", [:append])
        wait = fn wait, n ->
          cond do
            File.exists?(state["trace"] <> ".ab-release") -> :ok
            n == 0 -> raise "ab wait expired"
            true -> Process.sleep(10); wait.(wait, n - 1)
          end
        end
        wait.(wait, 1000)
        end
        call(%{"op" => "source.list", "limit" => 32}, state |> Map.put("step", "list") |> Map.put("prior_a", outcome))
      end
      defp advance("nested_host", _, state) do
        if String.starts_with?(state["mode"], "host_managed:") do
          File.write!(state["trace"], "host-held\\n", [:append])
          wait = fn wait, n ->
            cond do
              File.exists?(state["trace"] <> ".host-release") -> :ok
              n == 0 -> raise "host wait expired"
              true -> Process.sleep(10); wait.(wait, n - 1)
            end
          end
          wait.(wait, 1000)
        end
        op = state["mode"] |> String.split(":") |> List.last()
        request = case op do
          "state.put_deadline" -> %{"op" => "state.put", "scope" => "session", "key" => "deadline_derived", "expected_revision" => 0, "value" => %{"text" => "SYNTHETIC_DEADLINE_STATE"}, "write_before_ms" => 9000000000000000}
          "operator.question" -> %{"op" => op, "arguments" => %{"questions" => [%{"id" => "detail", "kind" => "text", "prompt" => "SYNTHETIC_EXTENSION_MANAGED_QUESTION"}]}, "checkpoint" => %{}}
          "service.call" -> %{"op" => op, "alias" => "marker", "arguments" => %{"text" => "SYNTHETIC_MANAGED_HOST"}, "checkpoint" => %{}}
          "state.put" -> %{"op" => op, "scope" => "session", "key" => "derived", "expected_revision" => 0, "value" => %{"text" => "SYNTHETIC_MANAGED_HOST"}}
          "state.delete" -> %{"op" => op, "scope" => "session", "key" => "derived", "expected_revision" => 0}
        end
        call(request, Map.put(state, "step", "done"))
      end
      defp advance("nested_mcp", _, state) do
        call(%{"op" => "mcp.call", "version" => 1, "binding" => "notes", "arguments" => %{"path" => "nested-mcp.txt", "content" => "SYNTHETIC_NESTED_MCP"}, "timeout_ms" => 5000}, Map.put(state, "step", "done"))
      end
      defp advance("nested_native", _, state) do
        call(%{"op" => "tool.call", "name" => "write", "arguments" => %{"path" => "nested-native.txt", "content" => "SYNTHETIC_NESTED_NATIVE"}, "timeout_ms" => 5000}, Map.put(state, "step", "done"))
      end
      defp advance("nested_document", _, state) do
        if state["mode"] == "nested_document_hold" do
          File.write!(state["trace"], "nested-document-held\\n", [:append])
          wait = fn wait, remaining ->
            cond do
              File.exists?(state["trace"] <> ".host-release") -> :ok
              remaining == 0 -> raise "fixture host barrier timed out"
              true -> Process.sleep(10); wait.(wait, remaining - 1)
            end
          end
          wait.(wait, 1000)
        end
        bytes = Jason.encode!(%{"value" => "SYNTHETIC_MANAGED_DOCUMENT"})
        sha = Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
        call(%{"op" => "collection.store", "scope" => "project", "request" => %{
          "op" => "value.put_inline", "key" => "derived.fixture", "generation" => 0, "expected_revision" => 0,
          "data" => bytes, "byte_count" => byte_size(bytes), "sha256" => sha}}, Map.put(state, "step", "done"))
      end
      defp advance("list", %{"status" => "ok", "value" => value}, state) do
        row = Enum.find(value["sources"], &(&1["kind"] == "input.original"))
        call(%{"op" => "source.read", "handle" => row["read_handle"]}, Map.put(state, "step", "read"))
      end
      defp advance("read", %{"status" => "ok", "value" => page}, state) do
        call(%{"op" => "source.quote", "handle" => page["handle"], "quote" => "Synthetic café observation"}, state |> Map.put("step", "quote") |> Map.put("page", page))
      end
      defp advance("quote", %{"status" => "ok", "value" => quote}, state) do
        {:ok, proof} = Ipse.Extension.source_proof(state["page"], quote, "Synthetic café observation")
        state = state |> Map.put("step", "snapshot") |> Map.put("proof", proof)
        if state["mode"] in ["capture_ab_publication", "capture_ab_literal_publication_hold"] do
          File.write!(state["trace"], "candidate-held\\n", [:append])
          wait = fn wait, n ->
            cond do
              File.exists?(state["trace"] <> ".candidate-release") -> :ok
              n == 0 -> raise "candidate wait expired"
              true -> Process.sleep(10); wait.(wait, n - 1)
            end
          end
          wait.(wait, 1000)
        end
        cond do
          state["mode"] in ["capture_unobserved", "conflict_unobserved"] ->
            advance("snapshot", %{"status" => "ok", "value" => %{"generation" => 0}}, state)
          state["mode"] in ["capture_ab_literal", "capture_ab_publication", "capture_ab_literal_publication", "capture_ab_literal_publication_hold"] ->
            advance("snapshot", %{"status" => "ok", "value" => state["prior_a"]["value"]}, state)
          true ->
            call(%{"op" => "collection.call", "request" => %{"op" => "snapshot"}}, state)
        end
      end
      defp advance("snapshot", %{"status" => "ok", "value" => snapshot}, state) do
        if state["mode"] == "hold", do: (File.write!(state["trace"], "held\\n", [:append]); Process.sleep(600))
        if state["mode"] == "barrier" do
          File.write!(state["trace"], "barrier\\n", [:append])
          wait = fn wait, remaining ->
            cond do
              File.exists?(state["trace"] <> ".release") -> :ok
              remaining == 0 -> raise "fixture barrier timed out"
              true -> Process.sleep(10); wait.(wait, remaining - 1)
            end
          end
          wait.(wait, 1500)
        end
        fields = ~w(session_id occurrence_id version_id start_byte end_byte quote_sha256 content_sha256)
        lineage = state["proof"] |> Map.take(fields) |> Enum.map(fn {k,v} -> [k,v] end) |> Enum.sort() |> Jason.encode!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
        text = "Synthetic café observation"
        suffix = [["lineage", lineage], ["text", text]] |> Jason.encode!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
        key = "pending." <> suffix
        value = %{"lineage" => lineage, "text" => text, "assigned_category" => "ordinary", "evidence" => %{"sources" => [state["proof"]]}}
        commit = %{"op" => "collection.managed", "recipe_sha256" => state["recipe"], "request" => %{"op" => "commit", "expected_generation" => if(state["mode"] in ["conflict", "conflict_unobserved"], do: 0, else: snapshot["generation"]), "advance_floor" => true,
          "changes" => [%{"key" => key, "expected_revision" => 0, "value" => value}]},
          "proofs" => [%{"handle" => state["page"]["handle"], "quote" => "Synthetic café observation"}]}
        commit = if state["metadata_version"] == 3, do: Map.put(commit, "metadata_version", 3), else: commit
        commit = if state["mode"] == "legacy_commit", do: %{"op" => "collection.call", "request" => commit["request"], "proofs" => commit["proofs"]}, else: commit
        call(commit, Map.put(state, "step", "done"))
      end
      defp advance(_, outcome, state) do
        if state["mode"] == "read_hold" do
          File.write!(state["trace"], "read-held\\n", [:append])
          wait = fn wait, remaining ->
            cond do
              File.exists?(state["trace"] <> ".release") -> :ok
              remaining == 0 -> raise "fixture read barrier timed out"
              true -> Process.sleep(10); wait.(wait, remaining - 1)
            end
          end
          wait.(wait, 1000)
          File.write!(state["trace"], "read-returned\\n", [:append])
        end
        value = cond do
          state["mode"] in ["paged", "paged_read"] -> %{"items" => List.duplicate(String.duplicate("é", 3000), 4)}
          state["mode"] == "read_hold" -> Map.put(outcome, "worker_payload", "SYNTHETIC_MANAGED_WORKER_TEXT")
          true -> outcome
        end
        {:ok, reply} = Ipse.Extension.ResultPublication.prepare(value)
        {:ok, reply, state}
      end
      defp call(request, state), do: {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request}, state}
    end
    """

    path = Path.join(root, "fixture.ex")
    File.write!(path, source)

    assert {"", 0} =
             System.cmd(
               System.find_executable("elixirc"),
               [
                 "--erl",
                 "+S 2:2",
                 "-pa",
                 Application.app_dir(:ipse, "ebin"),
                 "-pa",
                 Application.app_dir(:jason, "ebin"),
                 "-o",
                 Path.join(root, "ebin"),
                 path
               ],
               stderr_to_stdout: true
             )

    if System.get_env("IPSE_TEST_MANAGED_PACK") == "1" do
      knowledge = root <> "-knowledge"
      on_exit(fn -> File.rm_rf!(knowledge) end)

      {output, status} =
        System.cmd(
          System.find_executable("elixir"),
          [
            "extensions/knowledge/build.exs",
            "--sdk",
            Application.app_dir(:ipse, "ebin"),
            "--output",
            knowledge,
            "--package",
            "knowledge",
            "--preset",
            "native"
          ],
          stderr_to_stdout: true
        )

      assert status == 0, output

      for beam <- Path.wildcard(Path.join(knowledge, "ebin/*.beam")),
          do: File.cp!(beam, Path.join(root, "ebin/" <> Path.basename(beam)))
    end

    File.write!(Path.join(root, "LICENSE"), "MIT synthetic fixture")

    files =
      for path <- [
            "LICENSE"
            | Enum.map(Path.wildcard(Path.join(root, "ebin/*.beam")), &Path.relative_to(&1, root))
          ] do
        bytes = File.read!(Path.join(root, path))
        %{"path" => path, "bytes" => byte_size(bytes), "sha256" => JSON.sha256(bytes)}
      end

    manifest = %{
      "format" => 1,
      "id" => "fixture/collection",
      "version" => "0.1.0",
      "sdk" => 2,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => name,
      "license_file" => "LICENSE",
      "files" => files,
      "capabilities" => capabilities,
      "exports" => exports,
      "options_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["trace", "recipe"],
        "properties" => %{
          "trace" => %{"type" => "string"},
          "recipe" => %{"type" => "string"},
          "literal_key" => %{"type" => "string"},
          "metadata_version" => %{"type" => "integer", "enum" => [3]}
        }
      },
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      }
    }

    File.write!(Path.join(root, "extension.json"), Jason.encode!(manifest))
    File.rm!(path)
    document_root = root <> "-document"
    document_name = name <> "Document"
    document_caps = capabilities ++ ["host.collection.store"]
    File.mkdir_p!(Path.join(document_root, "ebin"))
    on_exit(fn -> File.rm_rf!(document_root) end)

    document_source =
      source
      |> String.replace("defmodule #{name} do", "defmodule #{document_name} do")
      |> String.replace(inspect(capabilities), inspect(document_caps))

    document_path = Path.join(document_root, "fixture.ex")
    File.write!(document_path, document_source)

    assert {"", 0} =
             System.cmd(
               System.find_executable("elixirc"),
               [
                 "--erl",
                 "+S 2:2",
                 "-pa",
                 Application.app_dir(:ipse, "ebin"),
                 "-pa",
                 Application.app_dir(:jason, "ebin"),
                 "-o",
                 Path.join(document_root, "ebin"),
                 document_path
               ],
               stderr_to_stdout: true
             )

    File.rm!(document_path)
    File.cp!(Path.join(root, "LICENSE"), Path.join(document_root, "LICENSE"))

    document_files =
      for relative <- ["LICENSE", "ebin/Elixir.#{document_name}.beam"] do
        bytes = File.read!(Path.join(document_root, relative))
        %{"path" => relative, "bytes" => byte_size(bytes), "sha256" => JSON.sha256(bytes)}
      end

    document_manifest =
      root
      |> Path.join("extension.json")
      |> File.read!()
      |> Jason.decode!()
      |> Map.merge(%{
        "entrypoint" => document_name,
        "capabilities" => document_caps,
        "files" => document_files
      })

    File.write!(Path.join(document_root, "extension.json"), Jason.encode!(document_manifest))
    service_root = root <> "-service"
    on_exit(fn -> File.rm_rf!(service_root) end)
    service_caps = capabilities ++ ["host.services"]

    requires = %{
      "version" => 1,
      "services" => [
        service
        |> Map.drop(~w(id description))
        |> Map.merge(%{"alias" => "marker", "contract" => 1})
      ]
    }

    service_source =
      source
      |> String.replace("defmodule #{name} do", "defmodule #{name}Service do")
      |> String.replace(inspect(capabilities), inspect(service_caps))
      |> String.replace(
        "\"exports\" => #{inspect(exports)}}",
        "\"exports\" => #{inspect(exports)}, \"requires\" => #{inspect(requires)}}"
      )

    build_variant(
      service_root,
      name <> "Service",
      service_source,
      manifest |> Map.put("capabilities", service_caps) |> Map.put("requires", requires)
    )

    %{artifact: root, document_artifact: document_root, service_artifact: service_root}
  end

  if @native_root_approval do
    setup c do
      setup_collection(c)
    end
  else
    setup c do
      if c[:native_root_approval], do: %{}, else: setup_collection(c)
    end
  end

  defp setup_collection(c) do
    root =
      cond do
        c[:native_root_approval] ->
          System.fetch_env!("IPSE_TEST_NATIVE_ROOT_APPROVAL_ROOT")

        c[:worker_inherited_union] ->
          Path.join(System.tmp_dir!(), "ipse-worker-inherited-" <> Ipse.Usage.id())

        c[:literal_v4_ab] ->
          System.fetch_env!("IPSE_LITERAL_AB_ROOT")

        true ->
          Path.join(System.tmp_dir!(), "ipse-collection-sdk-" <> Ipse.Usage.id())
      end

    if c[:worker_inherited_union], do: native_literal_seed(root)

    literal_seed =
      if c[:literal_v4_ab],
        do: root |> Path.join("literal-ab-seed.json") |> File.read!() |> Jason.decode!()

    home = Path.join(root, "home")
    cwd = Path.join(root, "project")
    File.mkdir_p!(home)
    File.mkdir_p!(cwd)
    File.chmod!(home, 0o700)

    unless c[:native_root_approval] || c[:literal_v4_ab] || c[:worker_input_capacity] ||
             c[:registered_capture_sequence] ||
             c[:registered_competing],
           do: on_exit(fn -> File.rm_rf!(root) end)

    if c[:registered_capture_sequence], do: IO.puts("REGISTERED_CAPTURE_ROOT=" <> root)
    if c[:registered_competing], do: IO.puts("COMPETING_CAPTURE_ROOT=" <> root)

    trace = Path.join(root, "trace")

    if literal_seed do
      File.write!(trace, "")
      File.rm(trace <> ".ab-release")
    end

    {:ok, artifact} =
      Artifact.import(
        cond do
          c[:managed_host_service] -> c.service_artifact
          c[:nested_document] -> c.document_artifact
          true -> c.artifact
        end,
        Path.join(home, "extensions/artifacts")
      )

    data = %{
      "extension_trust" => [
        Map.merge(
          %{
            "artifact" => artifact.digest,
            "capabilities" => artifact.manifest["capabilities"],
            "allow_project" => false,
            "allow_children" => false
          },
          if(c[:nested_mcp],
            do: %{
              "mcp_bindings" => [
                %{"instance" => "capture", "alias" => "notes", "tool" => "mcp__notes__write_note"}
              ]
            },
            else: %{}
          )
        )
      ],
      "extensions" => [
        %{
          "instance" => "capture",
          "artifact" => artifact.digest,
          "enabled" => true,
          "options" =>
            Map.merge(
              %{"trace" => trace, "recipe" => JSON.digest([recipe()])},
              if(c[:metadata_version] == 3, do: %{"metadata_version" => 3}, else: %{})
            ),
          "order" => 0,
          "lifetime" => "session"
        }
      ]
    }

    data =
      if c[:managed_host_service] do
        {:ok, target} = Artifact.import(c.artifact, Path.join(home, "extensions/artifacts"))

        binding = %{
          "caller" => "capture",
          "alias" => "marker",
          "target" => "target",
          "artifact" => target.digest,
          "service" => "observe"
        }

        data
        |> Map.update!("extension_trust", fn [trust] ->
          [
            Map.put(trust, "service_bindings", [binding]),
            %{
              "artifact" => target.digest,
              "capabilities" => target.manifest["capabilities"],
              "allow_project" => false,
              "allow_children" => false
            }
          ]
        end)
        |> Map.update!("extensions", fn [entry] ->
          [entry, %{entry | "instance" => "target", "artifact" => target.digest, "order" => 1}]
        end)
      else
        data
      end

    data =
      if c[:nested_document] do
        Map.update!(data, "extension_trust", fn [trust] ->
          [
            Map.put(trust, "collection_bindings", [
              %{
                "instance" => "capture",
                "version" => 1,
                "id" => "documents",
                "scope" => "project",
                "profile" => Ipse.Extension.Collection.Profile.documents()
              }
            ])
          ]
        end)
      else
        data
      end

    data =
      if literal_seed do
        update_in(data, ["extensions", Access.at(0), "options"], fn options ->
          Map.put(options, "literal_key", literal_seed["key"])
        end)
      else
        data
      end

    data =
      if c[:private_presentation] do
        data
        |> Map.update!("extension_trust", fn trust ->
          trust ++
            [
              %{
                "artifact" => "builtin:answer-format:1",
                "capabilities" => ["transform.presentation"],
                "allow_project" => false,
                "allow_children" => false
              }
            ]
        end)
        |> Map.update!("extensions", fn entries ->
          entries ++
            [
              %{
                "instance" => "formatter",
                "artifact" => "builtin:answer-format:1",
                "enabled" => true,
                "options" => %{"prefix" => "<answer>", "suffix" => "</answer>"},
                "order" => 10,
                "lifetime" => "persistent"
              }
            ]
        end)
      else
        data
      end

    data =
      if c[:managed_sink_role],
        do: Ipse.Test.ManagedDeliverySink.select(data, home, root, c.managed_sink_role),
        else: data

    {:ok, selected} =
      Ipse.Extension.Config.resolve(
        [%{scope: "operator", path: "/fixture/config.json", data: data}],
        []
      )

    {:ok, entries} = Registry.prepare(selected, home)
    entry = Enum.find(entries, &(&1.identity["instance"] == "capture"))

    config = %{
      provider: :demo,
      provider_module: Model,
      model: "synthetic",
      home: home,
      approval: :deny,
      approval_origin: :default_headless,
      headless: true,
      extensions: entries
    }

    config =
      if c[:managed_mcp] do
        server =
          if c[:managed_http] do
            url =
              if c[:managed_mcp_tls] do
                {url, task, listener, restore} = Ipse.Test.ManagedMCPHTTP.start_tls(cwd)

                on_exit(fn ->
                  :ssl.close(listener)
                  Process.exit(task.pid, :kill)
                  restore.()
                end)

                url
              else
                {url, task, listener} = Ipse.Test.ManagedMCPHTTP.start(cwd)

                on_exit(fn ->
                  :gen_tcp.close(listener)
                  Process.exit(task.pid, :kill)
                end)

                url
              end

            %{
              "id" => "notes",
              "transport" => "http",
              "url" => url,
              "allow_insecure_loopback" => true,
              "tools" => ["write_note"],
              "timeout_ms" => 10_000
            }
          else
            %{
              "id" => "notes",
              "command" => System.find_executable("elixir"),
              "args" => [
                "--erl",
                "+S 2:2",
                "-pa",
                Path.dirname(to_string(:code.which(Jason))),
                Path.expand("../../support/mcp_server.exs", __DIR__),
                cond do
                  c[:managed_gate] -> "managed_gate"
                  c[:managed_held] -> "controlled_disconnect"
                  true -> "normal"
                end
              ],
              "tools" => ["write_note"],
              "env" => %{
                "PATH" => Path.join(to_string(:code.root_dir()), "bin") <> ":/usr/bin:/bin"
              },
              "timeout_ms" => 10_000
            }
          end

        config_path = Path.join(root, "managed-mcp.json")
        File.write!(config_path, Jason.encode!(%{"servers" => [server]}))
        {:ok, servers} = Ipse.MCP.Config.load(config_path)
        Map.put(config, :mcp_servers, servers)
      else
        config
      end

    provider_requests =
      if c[:native_root_approval], do: start_supervised!({Agent, fn -> [] end})

    {config, provider_server} =
      if c[:registered_main] do
        body = fn message ->
          if c[:tls_main],
            do: subscription_body(message),
            else:
              Jason.encode!(%{
                "model" => "synthetic",
                "message" => message,
                "done" => true,
                "done_reason" => "stop",
                "prompt_eval_count" => 1,
                "eval_count" => 1
              }) <> "\n"
        end

        responses =
          [
            body.(%{
              "role" => "assistant",
              "content" => "",
              "tool_calls" =>
                [
                  %{
                    "function" => %{
                      "name" =>
                        if(c[:capture_write] || c[:managed_helper],
                          do: "ext__capture__capture",
                          else: "ext__capture__inspect"
                        ),
                      "arguments" => %{
                        "mode" =>
                          cond do
                            c[:managed_pack_wide] -> "decision_pack_wide"
                            c[:managed_pack_actual] -> "decision_pack_actual"
                            c[:managed_pack] -> "decision_pack"
                            c[:managed_decision_literal] -> "decision_literal"
                            c[:managed_embedding] -> "embedding_helper"
                            c[:managed_decision] -> "decision_helper"
                            c[:managed_helper] -> "helper"
                            c[:capture_write] -> c[:registered_capture_mode] || "capture"
                            c[:postjournal_expiry] -> "read_hold"
                            true -> "read"
                          end
                      }
                    }
                  }
                ] ++
                  if(c[:postjournal_expiry],
                    do: [
                      %{
                        "function" => %{
                          "name" => "read",
                          "arguments" => %{"path" => "never-started"}
                        }
                      }
                    ],
                    else: []
                  )
            }),
            body.(
              if c[:ordinary_effect],
                do: %{
                  "role" => "assistant",
                  "content" => "",
                  "tool_calls" => [
                    %{
                      "function" =>
                        if(c[:managed_host_operation],
                          do: %{
                            "name" => c.managed_host_operation,
                            "arguments" => %{"limit" => 8}
                          },
                          else:
                            if(c[:managed_mcp],
                              do: %{
                                "name" => "mcp__notes__write_note",
                                "arguments" => %{
                                  "path" => "managed-mcp.txt",
                                  "content" => "SYNTHETIC_MANAGED_MCP"
                                }
                              },
                              else:
                                if(c[:managed_shell],
                                  do: %{
                                    "name" => "shell",
                                    "arguments" => managed_shell_arguments(c)
                                  },
                                  else: %{
                                    "name" => "write",
                                    "arguments" => %{
                                      "path" => "managed-output.txt",
                                      "content" => "SYNTHETIC_MANAGED_WRITE"
                                    }
                                  }
                                )
                            )
                        )
                    }
                  ]
                },
                else:
                  if(c[:opaque_refusal],
                    do: %{
                      "role" => "assistant",
                      "content" => "Synthetic protected read complete.",
                      "thinking" => "synthetic opaque continuation canary"
                    },
                    else: %{
                      "role" => "assistant",
                      "content" => "Synthetic protected read complete."
                    }
                  )
            )
          ] ++
            if(c[:ordinary_effect],
              do: [
                body.(%{"role" => "assistant", "content" => "Synthetic ordinary tool complete."})
              ],
              else: []
            )

        responses =
          cond do
            c[:registered_ab_publication] ->
              candidate =
                hd(responses)
                |> Jason.decode!()
                |> put_in(
                  ["message", "tool_calls", Access.at(0), "function", "arguments", "mode"],
                  "capture_ab_publication"
                )
                |> Jason.encode!()

              [
                hd(responses),
                List.last(responses),
                candidate <> "\n",
                hd(responses),
                List.last(responses)
              ]

            c[:registered_capture_modes] ->
              Enum.flat_map(c.registered_capture_modes, fn mode ->
                request =
                  hd(responses)
                  |> Jason.decode!()
                  |> put_in(
                    ["message", "tool_calls", Access.at(0), "function", "arguments", "mode"],
                    mode
                  )
                  |> Jason.encode!()

                [request <> "\n", List.last(responses)]
              end)

            c[:registered_capture_count] ->
              List.duplicate(responses, c.registered_capture_count) |> List.flatten()

            c[:registered_capture_no_continuation] ->
              Enum.take(responses, 1)

            c[:registered_competing] ->
              barrier =
                hd(responses)
                |> Jason.decode!()
                |> put_in(
                  ["message", "tool_calls", Access.at(0), "function", "arguments", "mode"],
                  "barrier"
                )
                |> Jason.encode!()

              [
                hd(responses),
                List.last(responses),
                barrier <> "\n",
                barrier <> "\n",
                List.last(responses)
              ]

            c[:managed_pack_actual] ->
              responses

            c[:managed_pack] && !c[:helper_stale] ->
              [
                hd(responses),
                Jason.encode!(%{
                  "model" => "synthetic",
                  "answers" => %{
                    "pack" => %{
                      "type" => "choice",
                      "choice" => "second",
                      "confidence" => if(c[:low_confidence], do: 0.51, else: 0.9),
                      "probabilities" =>
                        cond do
                          c[:malformed_decision] -> %{"first" => 0.1, "second" => 1.5}
                          c[:low_confidence] -> %{"first" => 0.49, "second" => 0.51}
                          true -> %{"first" => 0.1, "second" => 0.9}
                        end
                    }
                  },
                  "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
                }),
                List.last(responses)
              ]

            c[:native_inference_boundary] == :deny ->
              responses

            c[:managed_embedding] ->
              [
                hd(responses),
                Jason.encode!(%{
                  "model" => "synthetic",
                  "embeddings" => [[0.1, 0.2, 0.3]],
                  "prompt_eval_count" => 1
                }),
                List.last(responses)
              ]

            c[:managed_decision] && !c[:helper_stale] ->
              [
                hd(responses),
                Jason.encode!(%{
                  "model" => "synthetic",
                  "answers" => %{"relevant" => %{"type" => "noul", "noul" => 0.8}},
                  "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
                }),
                List.last(responses)
              ]

            c[:managed_helper] && !c[:helper_stale] ->
              responses ++ [List.last(responses)]

            c[:ordinary_registered_text] ->
              [
                body.(%{
                  "role" => "assistant",
                  "content" => "Synthetic ordinary registered answer."
                })
              ]

            true ->
              responses
          end

        {base, server} =
          cond do
            c[:native_root_approval] ->
              observed_provider(responses, nil, 10_000, provider_requests)

            c[:tls_main] ->
              tls_provider(responses, c[:tls_gate])

            c[:managed_pack_wide] && c[:response_change] ->
              observed_provider(responses, :second_response, 30_000)

            c[:managed_pack_wide] && c[:helper_stale] ->
              observed_provider(responses, nil, 30_000)

            c[:managed_pack_wide] && c[:malformed_decision] ->
              observed_provider(responses, nil, 30_000)

            c[:managed_pack_wide] ->
              Ipse.Test.ProviderFixture.sequence(responses, 30_000)

            c[:opaque_refusal] || c[:plain_stale] || c[:helper_stale] || c[:response_change] ||
              c[:managed_pack_actual] ||
                c[:ordinary_effect] ->
              observed_provider(responses, if(c[:response_change], do: :second_response))

            true ->
              Ipse.Test.ProviderFixture.sequence(responses)
          end

        config =
          config
          |> Map.delete(:provider_module)
          |> Map.merge(%{
            provider: if(c[:tls_main], do: :chatgpt, else: :ollama),
            base_url: base,
            timeout_ms: if(c[:wire_expiry], do: 10_000, else: 3000),
            inference_services: %{"local" => %{"version" => 1, "origins" => [base]}}
          })

        config = if c[:tls_main], do: subscription_credentials(config, root), else: config

        config =
          if c[:managed_decision],
            do:
              Map.put(config, :decision_profiles, %{
                "advice" => %{
                  "operation" => "decision",
                  "provider" => "system_one_compatible",
                  "model" => "synthetic",
                  "expected_model" => "synthetic",
                  "service_id" => "local",
                  "base_url" => base,
                  "timeout_ms" => 3000
                }
              }),
            else: config

        config =
          if c[:managed_embedding],
            do:
              Map.put(config, :embedding_profiles, %{
                "embed" => %{
                  "operation" => "embedding",
                  "provider" => "ollama",
                  "model" => "synthetic",
                  "dimensions" => 3,
                  "dimension_mode" => "native",
                  "base_url" => base,
                  "timeout_ms" => 3000
                }
              }),
            else: config

        config =
          if c[:managed_helper],
            do:
              Map.put(config, :profiles, %{
                "extract" => %{
                  "provider" => "ollama",
                  "model" => "synthetic",
                  "base_url" => base,
                  "timeout_ms" => 3000
                }
              }),
            else: config

        {config, server}
      else
        {config, nil}
      end

    {:ok, binding} = ProjectIdentity.admit(home, cwd, :folder)
    {:ok, ordinary_namespace} = SemanticConsent.namespace(binding["project_id"], "capture")
    namespace = if literal_seed, do: literal_seed["namespace"], else: ordinary_namespace
    {:ok, catalog} = Catalog.snapshot(config)
    descriptors = catalog["entries"]

    constraints = constraints()

    selection = %{
      "version" => 2,
      "constraints" => %{JSON.digest([constraints]) => constraints},
      "recipes" => %{JSON.digest([recipe()]) => recipe()},
      "activation" => nil,
      "domain" => "knowledge",
      "namespace" => namespace,
      "scope" => %{"kind" => "project", "worktree_id" => nil},
      "sources" => %{"categories" => ["unattended_input"], "exclusions" => []},
      "storage" => %{"kind" => "local_collection", "collection" => "capture"},
      "retention" => %{"automatic" => 90, "manual" => 3650},
      "routes" => [
        %{
          "operation" => "main",
          "provider" => to_string(config.provider),
          "profile" => nil,
          "model" => "synthetic",
          "endpoint" =>
            if(provider_server,
              do: config.base_url <> if(c[:tls_main], do: "/responses", else: "/api/chat"),
              else: "demo://local"
            ),
          "service_id" => if(provider_server, do: "local", else: "demo"),
          "billing_mode" => Ipse.Usage.billing_mode(config.provider),
          "processing_region" => nil,
          "storage_region" => nil,
          "cache_retention" => nil,
          "account_controls" => nil
        }
      ],
      "effects" =>
        Enum.flat_map(descriptors, fn descriptor ->
          publish =
            if descriptor["id"] == "capture",
              do: [
                %{
                  "operation" => "notes.propose",
                  "class" => "collection.publish",
                  "outer_sha256" => JSON.digest([descriptor]),
                  "inner_op" => "collection.managed",
                  "constraints_sha256" => JSON.digest([constraints]),
                  "recipe_sha256" => JSON.digest([recipe()])
                }
              ],
              else: []

          publish ++
            [
              %{
                "operation" => "notes.recall",
                "class" => "collection.read",
                "outer_sha256" => JSON.digest([descriptor]),
                "inner_op" => "collection.call",
                "managed_read" => [JSON.digest([recipe()])]
              }
            ]
        end),
      "limits" =>
        Map.merge(Consent.zero(), %{
          "operations" => 8,
          "input_bytes" => 100_000,
          "output_bytes" => 100_000
        }),
      "period_ms" => 86_400_000,
      "expires_at_ms" =>
        System.system_time(:millisecond) +
          cond do
            c[:publication_deadline] -> 4000
            c[:wire_expiry] -> 6000
            true -> 600_000
          end,
      "headless" => true
    }

    selection =
      if c[:managed_decision] do
        labels = %{
          "processing_region" => nil,
          "storage_region" => nil,
          "cache_retention" => nil,
          "account_controls" => nil
        }

        selectors =
          for {operation, profile} <- [{"main", nil}, {"decision.create", "advice"}],
              do: Map.merge(labels, %{"operation" => operation, "profile" => profile})

        {:ok, routes} = Ipse.Extension.SemanticRoutes.resolve(config, selectors)
        Map.put(selection, "routes", routes)
      else
        if c[:managed_helper] do
          [main] = selection["routes"]

          helper =
            if c[:managed_embedding],
              do:
                main
                |> Map.put("operation", "embedding.create")
                |> Map.put("profile", "embed")
                |> Map.put("endpoint", config.base_url <> "/api/embed"),
              else:
                main |> Map.put("operation", "model.complete") |> Map.put("profile", "extract")

          {:ok, selectors} = Ipse.Extension.SemanticRoutes.selectors([main, helper])
          {:ok, routes} = Ipse.Extension.SemanticRoutes.resolve(config, selectors)
          Map.put(selection, "routes", routes)
        else
          selection
        end
      end

    selection = Map.update!(selection, "effects", &sort_mappings/1)

    selection =
      if literal_seed do
        old = literal_seed["policy"]["settings"]
        read_recipes = Map.keys(old["recipes"]) ++ Map.keys(selection["recipes"])

        selection
        |> Map.put("storage", old["storage"])
        |> Map.put("sources", %{
          "categories" =>
            Enum.sort(Enum.uniq(old["sources"]["categories"] ++ ["unattended_input"])),
          "exclusions" => old["sources"]["exclusions"]
        })
        |> Map.update!("constraints", &Map.merge(&1, old["constraints"]))
        |> Map.update!("recipes", &Map.merge(&1, old["recipes"]))
        |> Map.update!("effects", fn effects ->
          Enum.map(effects, fn effect ->
            if effect["class"] == "collection.read",
              do: Map.put(effect, "managed_read", Enum.sort(Enum.uniq(read_recipes))),
              else: effect
          end)
        end)
      else
        selection
      end

    assert {:ok, policy} = SemanticConsent.prepare(binding, entry.identity, selection)
    control = SemanticAdmission.control_root(home)
    {:ok, snapshot} = Consent.snapshot(control, binding["project_id"])

    {:ok, _} =
      Consent.replace(
        control,
        binding["project_id"],
        snapshot["epoch"],
        policy,
        System.system_time(:millisecond)
      )

    {:ok, selection} = Ipse.Config.Semantics.selection(policy)
    config = Map.put(config, :semantic_selections, selection)

    %{
      root: root,
      home: home,
      cwd: cwd,
      trace: trace,
      config: config,
      provider_server: provider_server,
      provider_requests: provider_requests,
      dir: if(literal_seed, do: Path.join(home, "sessions"), else: Path.join(root, "sessions")),
      literal_seed: literal_seed,
      control: control,
      binding: binding,
      namespace: namespace
    }
  end

  defp constraints do
    object = fn properties ->
      %{
        "type" => "object",
        "properties" => properties,
        "required" => Map.keys(properties),
        "additionalProperties" => false
      }
    end

    proof =
      Map.new(
        ~w(version session_id occurrence_id version_id kind origin coverage path start_byte end_byte quote quote_sha256 content_sha256 receipt_sha256),
        fn k ->
          {k,
           %{
             "type" =>
               cond do
                 k in ~w(version start_byte end_byte) -> "integer"
                 k == "path" -> "null"
                 true -> "string"
               end
           }}
        end
      )

    %{
      "version" => 1,
      "key_prefix" => "pending.",
      "allow_delete" => false,
      "source_categories" => ["unattended_input"],
      "evidence_path" => ["evidence", "sources"],
      "value_schema" =>
        object.(%{
          "lineage" => %{"type" => "string"},
          "text" => %{"type" => "string"},
          "assigned_category" => %{"type" => "string"},
          "evidence" =>
            object.(%{
              "sources" => %{
                "type" => "array",
                "items" => object.(proof),
                "minItems" => 1,
                "maxItems" => 8
              }
            })
        })
    }
  end

  defp recipe do
    %{
      "version" => 1,
      "kind" => "proposal",
      "key_prefix" => "pending.",
      "constraints_sha256" => JSON.digest([constraints()]),
      "evidence_path" => ["evidence", "sources"],
      "lineage_path" => ["lineage"],
      "text_path" => ["text"],
      "category_path" => ["assigned_category"],
      "rules" => [
        %{
          "category" => "ordinary",
          "max_age_ms" => 604_800_000,
          "origins" => ["unattended_input"]
        }
      ],
      "override_prefix" => "override."
    }
  end

  defp build_variant(root, name, source, manifest) do
    File.mkdir_p!(Path.join(root, "ebin"))
    path = Path.join(root, "fixture.ex")
    File.write!(path, source)

    {output, status} =
      System.cmd(
        System.find_executable("elixirc"),
        [
          "--erl",
          "+S 2:2",
          "-pa",
          Application.app_dir(:ipse, "ebin"),
          "-pa",
          Application.app_dir(:jason, "ebin"),
          "-o",
          Path.join(root, "ebin"),
          path
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    File.rm!(path)
    File.write!(Path.join(root, "LICENSE"), "MIT synthetic fixture")

    files =
      for relative <- ["LICENSE", "ebin/Elixir.#{name}.beam"] do
        bytes = File.read!(Path.join(root, relative))
        %{"path" => relative, "bytes" => byte_size(bytes), "sha256" => JSON.sha256(bytes)}
      end

    File.write!(
      Path.join(root, "extension.json"),
      Jason.encode!(Map.merge(manifest, %{"entrypoint" => name, "files" => files}))
    )
  end

  defp start(c, extra \\ %{}, id \\ nil) do
    opts = [
      config: Map.merge(c.config, extra),
      cwd: c.cwd,
      state_dir: c.dir,
      subscriber: self(),
      id: id
    ]

    {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})
    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    pid
  end

  @tag managed_display_owner: true
  test "display preparation retains the actual Identity Consent and Collection owners", c do
    alias Ipse.Runner.Transaction
    alias Ipse.Session.ManagedUse
    alias Ipse.Extension.Collection.ObservedRead
    pid = start(c)
    state = :sys.get_state(pid)
    context = %{config: state.config, cwd: c.cwd, session_id: state.id, history_dir: c.dir}
    root = SemanticAdmission.collection_root(c.home)
    request = %{"op" => "snapshot"}
    pin = state.config.semantic_admission["pin"]
    assert {:ok, observation} = ObservedRead.read(root, c.namespace, request)
    assert {:ok, dependency} = ObservedRead.root_dependency(request, observation, pin)

    assert {:ok, caps} =
             ManagedUse.with_display_dependencies(context, [dependency], fn [current], held ->
               assert current == dependency
               assert held.owner == self()
               assert held.source_proofs == [] and held.source_leases == []
               assert held.active_sources == false
               assert held.deadline_ms > System.system_time(:millisecond)
               assert held.deadline_ms <= System.system_time(:millisecond) + 5_000
               caps = [held.identity, held.consent, held.collection]
               assert {:ok, ^caps} = Transaction.retained_share_stack()

               ids =
                 Enum.map(caps, fn cap ->
                   assert {:ok, id} = Transaction.retained_share_identity(cap)
                   id
                 end)

               assert Enum.map(ids, & &1.slot) == [0, 1, 2]
               assert length(Enum.uniq(Enum.map(ids, & &1.pid))) == 1
               assert length(Enum.uniq(Enum.map(ids, &{&1.device, &1.inode}))) == 3

               assert {:error, _} =
                        Task.async(fn ->
                          Transaction.retained_share_identity(held.collection)
                        end)
                        |> Task.await()

               {:ok, caps}
             end)

    for cap <- caps, do: assert(match?({:error, _}, Transaction.retained_share_identity(cap)))

    for callback <- [
          fn _, _ -> {:error, :synthetic_sink_refused} end,
          fn _, _ -> raise "synthetic sink interruption" end,
          fn _, held ->
            Process.sleep(max(held.deadline - System.monotonic_time(:millisecond) + 1, 0))
            {:ok, :late}
          end,
          fn _, held ->
            monitor = Process.monitor(held.collection.controller)
            Process.exit(held.collection.controller, :kill)
            assert_receive {:DOWN, ^monitor, :process, _, _}, 2_000
            {:ok, :lost_owner}
          end
        ] do
      assert {:unknown, :managed_display_ownership_unconfirmed} =
               ManagedUse.with_display_dependencies(context, [dependency], callback)
    end

    assert :ok = Session.close_confirmed(pid)
  end

  @tag managed_display_owner: true
  test "a changed current root refuses display preparation before entering its adapter", c do
    alias Ipse.Extension.Collection
    alias Ipse.Extension.Collection.ObservedRead
    pid = start(c)
    state = :sys.get_state(pid)
    context = %{config: state.config, cwd: c.cwd, session_id: state.id, history_dir: c.dir}
    root = SemanticAdmission.collection_root(c.home)
    request = %{"op" => "snapshot"}
    pin = state.config.semantic_admission["pin"]
    assert {:ok, observation} = ObservedRead.read(root, c.namespace, request)
    assert {:ok, dependency} = ObservedRead.root_dependency(request, observation, pin)

    assert {:ok, _} =
             Collection.execute(
               root,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => true,
                 "changes" => [
                   %{
                     "key" => "fixture",
                     "expected_revision" => 0,
                     "value" => %{"changed" => true}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    assert {:error, _} =
             Ipse.Session.ManagedUse.with_display_dependencies(context, [dependency], fn _, _ ->
               flunk("stale display preparation entered the adapter")
             end)

    assert :ok = Session.close_confirmed(pid)
  end

  for kind <- [:managed, :unmanaged] do
    @tag strict_deadline_gate: true,
         metadata_version: 3,
         registered_main: kind == :managed,
         capture_write: kind == :managed
    test "protected #{kind} publication applies its admitted deadline policy", c do
      c = if unquote(kind) == :unmanaged, do: legacy_publisher(c), else: c
      mode = if unquote(kind) == :managed, do: "capture", else: "legacy_commit"
      pid = start(c, %{fixture_mode: mode})
      assert :ok = Session.prompt(pid, "Synthetic café observation")
      assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
      assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

      assert {:ok, control} = Consent.snapshot(c.control, c.binding["project_id"])

      assert {:ok, snapshot} =
               Ipse.Extension.Collection.execute(
                 SemanticAdmission.collection_root(c.home),
                 c.namespace,
                 %{"op" => "snapshot"},
                 Ipse.Usage.id()
               )

      [result] =
        Enum.filter(events, fn event ->
          event["type"] == "extension_action_result" and
            get_in(event, ["request", "request", "op"]) == "commit"
        end)

      assert result["approval"] == "saved_consent"
      assert result["outcome"]["status"] == "ok"
      assert control["operations"][result["operation_id"]]["status"] == "settled"
      assert snapshot["generation"] == 1

      assert {:ok, _} = Session.Saved.restore(events, Session.info(pid).id)
      assert :ok = Session.close_confirmed(pid)
    end
  end

  @tag state_lifetime_gate: true
  test "ordinary extension State deadline and ordinary no-deadline State both work",
       c do
    pid = start(c, %{approval: :allow, approval_origin: :yes, headless: true})

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__capture", %{
               "mode" => "host_ordinary:state.put_deadline"
             })

    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    id = Session.info(pid).id
    assert {:ok, events} = Journal.load(c.dir, id)

    assert Enum.any?(
             events,
             &(&1["type"] == "extension_action_intent" and
                 get_in(&1, ["request", "op"]) == "state.put" and
                 get_in(&1, ["request", "write_before_ms"]) == 9_000_000_000_000_000)
           )

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__capture", %{
               "mode" => "host_ordinary:state.put"
             })

    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    assert {:ok, events} = Journal.load(c.dir, id)

    assert Enum.count(
             events,
             &(&1["type"] == "extension_action_result" and
                 get_in(&1, ["request", "op"]) == "state.put" and
                 get_in(&1, ["outcome", "status"]) == "ok")
           ) == 2

    assert {:ok, _} = Session.Saved.restore(events, id)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag state_lifetime_gate: true
  test "managed extension timed State remains refused before its intent", c do
    pid = start(c, %{approval: :allow, approval_origin: :yes, headless: true})

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__capture", %{
               "mode" => "host_managed:state.put_deadline"
             })

    await_marker(c.trace, "host-held", 500)
    File.write!(c.trace <> ".host-release", "release")
    assert_receive {:ipse, ^pid, {:done, :error}}, 10_000
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
    assert Enum.any?(events, &(&1["type"] == "managed_read_observed"))

    refute Enum.any?(
             events,
             &(&1["type"] == "extension_action_intent" and
                 get_in(&1, ["request", "op"]) == "state.put")
           )

    assert {:ok, _} = Session.Saved.restore(events, Session.info(pid).id)
    assert :ok = Session.close_confirmed(pid)
  end

  for boundary <- [:revoke, :expiry] do
    @tag extension_question_recovery: true, wire_expiry: boundary == :expiry
    test "interrupted legacy extension question withholds arguments after #{boundary}", c do
      pid = start(c, %{operator_questions: true})

      assert :ok =
               Session.invoke_export(pid, :command, "ext__capture__capture", %{
                 "mode" => "host_managed:operator.question"
               })

      await_marker(c.trace, "host-held", 500)
      await_worker_input_settlement(pid, 500)
      id = Session.info(pid).id
      # Model only the old producer's missing managed tracking. The actual
      # extension action, checkpoint, wait and source events are emitted by Session.
      :sys.replace_state(pid, fn s ->
        invocation_id = s.invocation.parent["invocation_id"]
        entry = %{s.managed_lineage.invocations[invocation_id] | input: [], reads: []}

        %{
          s
          | invocation: %{s.invocation | managed_reads: []},
            managed_lineage: %{
              s.managed_lineage
              | invocations: Map.put(s.managed_lineage.invocations, invocation_id, entry)
            }
        }
      end)

      File.write!(c.trace <> ".host-release", "release")
      assert_receive {:ipse, ^pid, {:question, question_id, _}}, 10_000
      writer = :sys.get_state(pid).journal_writer
      monitor = Process.monitor(pid)
      writer_monitor = Process.monitor(writer)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5000
      assert_receive {:DOWN, ^writer_monitor, :process, ^writer, _}, 5000
      assert {:ok, events} = Journal.load(c.dir, id)
      assert Enum.any?(events, &(&1["type"] == "extension_question"))
      assert Enum.any?(events, &(&1["type"] == "managed_read_observed"))
      legacy = legacy_tracking_prefix(c.dir, id, events)
      assert {:ok, reconstructed} = Session.Saved.restore(legacy, id)
      assert reconstructed.extension_state.question != nil
      assert reconstructed.question == nil
      assert reconstructed.question_recovery == :managed_question_withheld
      assert {:ok, policy} = Consent.snapshot(c.control, c.binding["project_id"])

      if unquote(boundary) == :revoke do
        assert {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], policy["epoch"])
      else
        Process.sleep(
          max(policy["policy"]["expires_at_ms"] - System.system_time(:millisecond) + 10, 0)
        )
      end

      resumed = start(c, %{operator_questions: true}, id)
      assert Session.info(resumed).question == nil
      assert Session.info(resumed).question_recovery == :managed_question_withheld
      refute_receive {:ipse, ^resumed, {:question, _, _}}, 50

      assert {:error, :no_pending_question} =
               Session.answer(resumed, question_id, %{"detail" => "unused"})

      assert :ok = Session.close_confirmed(resumed)
      assert {:ok, after_events} = Journal.load(c.dir, id)
      assert Enum.take(after_events, length(legacy)) == legacy
      refute Enum.any?(after_events, &(&1["type"] == "extension_continuation_intent"))
    end
  end

  @tag extension_question_ordinary: true
  test "ordinary extension question resumes with its exact full parent", c do
    pid = start(c, %{operator_questions: true})

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__capture", %{
               "mode" => "host_ordinary:operator.question"
             })

    assert_receive {:ipse, ^pid, {:question, question_id, arguments}}, 10_000
    id = Session.info(pid).id
    writer = :sys.get_state(pid).journal_writer
    monitor = Process.monitor(pid)
    writer_monitor = Process.monitor(writer)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5000
    assert_receive {:DOWN, ^writer_monitor, :process, ^writer, _}, 5000
    resumed = start(c, %{operator_questions: true}, id)
    assert_receive {:ipse, ^resumed, {:question, ^question_id, ^arguments}}, 5000
    assert Session.info(resumed).question.arguments == arguments
    assert :ok = Session.answer(resumed, question_id, %{"detail" => "ordinary"})
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(resumed)
  end

  defp legacy_tracking_prefix(dir, id, events) do
    legacy =
      Enum.map(events, fn
        %{"type" => "session", "metadata" => metadata} = event ->
          %{event | "metadata" => Map.delete(metadata, "managed_read_layout")}

        %{"type" => "managed_read_observed"} ->
          %{"type" => "legacy_untracked_observation"}

        event ->
          event
      end)

    path = Path.join(dir, id <> ".jsonl")
    original_lines = File.read!(path) |> String.split("\n", trim: true)

    lines =
      Enum.zip([events, legacy, original_lines])
      |> Enum.map(fn {before, after_event, line} ->
        encoded = if before == after_event, do: line, else: Jason.encode!(after_event)
        assert byte_size(encoded) <= byte_size(line)
        [encoded, String.duplicate(" ", byte_size(line) - byte_size(encoded)), "\n"]
      end)

    File.write!(path, lines)
    legacy
  end

  for kind <- [:managed, :unmanaged], boundary <- [:current, :delayed_stage, :stopped_native] do
    @tag ordinary_publication_deadline: true, publication_deadline: true, metadata_version: 3
    test "#{kind} ordinary publication fences #{boundary} at the actual native switch", c do
      c = if unquote(kind) == :unmanaged, do: legacy_publisher(c), else: c
      pid = start(c)
      observer = self()
      handler = "ordinary-publication-deadline-" <> Ipse.Usage.id()

      :ok =
        :telemetry.attach(
          handler,
          [:ipse, :extension, :collection, :staged],
          fn _, _, _, _ ->
            if Process.get({Ipse.Extension.Collection, :directory}) ==
                 Path.join(SemanticAdmission.collection_root(c.home), c.namespace) do
              deadline = Process.get({Ipse.Extension.Collection, :switch_deadline})
              cap = Process.get({Ipse.Extension.Collection, :lock_held})
              send(observer, {:ordinary_publication_staged, self(), deadline, cap.port})

              receive do
                {:ordinary_publication_release, ^handler} -> :ok
              after
                8000 -> :ok
              end
            end
          end,
          nil
        )

      try do
        mode = if unquote(kind) == :managed, do: "capture", else: "legacy_commit"
        :sys.replace_state(pid, &%{&1 | config: Map.put(&1.config, :fixture_mode, mode)})
        assert :ok = Session.prompt(pid, "Synthetic café observation")
        assert_receive {:ordinary_publication_staged, peer, deadline, port}, 5000
        assert is_integer(deadline)
        assert System.system_time(:millisecond) < deadline
        {:os_pid, native} = Port.info(port, :os_pid)

        if unquote(boundary) == :stopped_native do
          assert {_, 0} = System.cmd("/bin/kill", ["-STOP", Integer.to_string(native)])
          send(peer, {:ordinary_publication_release, handler})
        end

        try do
          if unquote(boundary) != :current,
            do: Process.sleep(max(deadline - System.system_time(:millisecond) + 20, 0))
        after
          if unquote(boundary) == :stopped_native,
            do:
              System.cmd("/bin/kill", ["-CONT", Integer.to_string(native)],
                stderr_to_stdout: true
              )
        end

        if unquote(boundary) != :stopped_native,
          do: send(peer, {:ordinary_publication_release, handler})

        assert_receive {:ipse, ^pid, {:done, _}}, 15_000
        id = Session.info(pid).id
        assert {:ok, events} = Journal.load(c.dir, id)

        operation =
          if unquote(kind) == :managed, do: "collection.managed", else: "collection.call"

        [intent] =
          Enum.filter(
            events,
            &(&1["type"] == "extension_action_intent" and &1["request"]["op"] == operation and
                get_in(&1, ["request", "request", "op"]) == "commit")
          )

        [result] =
          Enum.filter(
            events,
            &(&1["type"] == "extension_action_result" and
                &1["operation_id"] == intent["operation_id"])
          )

        assert {:ok, snapshot} =
                 Ipse.Extension.Collection.execute(
                   SemanticAdmission.collection_root(c.home),
                   c.namespace,
                   %{"op" => "snapshot"},
                   Ipse.Usage.id()
                 )

        if unquote(boundary) == :current do
          assert result["outcome"]["status"] == "ok"
          assert snapshot["generation"] == 1
        else
          refute result["outcome"]["status"] == "ok"
          assert snapshot["generation"] == 0

          assert {:ok, page} =
                   Ipse.Extension.Collection.scan_visible(
                     SemanticAdmission.collection_root(c.home),
                     c.namespace,
                     %{"op" => "scan", "after" => nil, "generation" => 0, "limit" => 4},
                     Ipse.Usage.id()
                   )

          assert page["records"] == []
        end

        assert {:ok, _} = Session.Saved.restore(events, id)
        assert :ok = Session.close_confirmed(pid)
      after
        :telemetry.detach(handler)
      end
    end
  end

  defp legacy_publisher(c) do
    assert {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    policy = snapshot["policy"]

    selection =
      policy["settings"]
      |> Map.drop(~w(version instance identity_sha256 constraints recipes activation))
      |> Map.merge(Map.take(policy, ~w(limits period_ms expires_at_ms headless)))
      |> Map.update!("effects", fn effects ->
        Enum.map(effects, fn mapping ->
          base = Map.take(mapping, ~w(operation class outer_sha256 inner_op))

          if mapping["class"] == "collection.publish",
            do:
              base
              |> Map.put("inner_op", "collection.call")
              |> Map.put("constraints", constraints()),
            else: base
        end)
      end)

    [entry] = c.config.extensions
    assert {:ok, policy} = SemanticConsent.prepare(c.binding, entry.identity, selection)

    assert {:ok, _} =
             Consent.replace(
               c.control,
               c.binding["project_id"],
               snapshot["epoch"],
               policy,
               System.system_time(:millisecond)
             )

    assert {:ok, selected} = Ipse.Config.Semantics.selection(policy)
    put_in(c, [:config, :semantic_selections], selected)
  end

  for op <- ["state.put", "state.delete", "service.call"], boundary <- [:revoke, :expiry] do
    @tag managed_host_repair: true,
         managed_host_service: op == "service.call",
         wire_expiry: boundary == :expiry
    test "managed #{op} refuses #{boundary} with --yes before host publication", c do
      pid = start(c, %{approval: :allow, approval_origin: :yes, headless: true})

      assert :ok =
               Session.invoke_export(pid, :command, "ext__capture__capture", %{
                 "mode" => "host_managed:" <> unquote(op)
               })

      await_marker(c.trace, "host-held", 500)
      assert {:ok, policy} = Consent.snapshot(c.control, c.binding["project_id"])

      if unquote(boundary) == :revoke do
        assert {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], policy["epoch"])
      else
        Process.sleep(
          max(policy["policy"]["expires_at_ms"] - System.system_time(:millisecond) + 10, 0)
        )
      end

      File.write!(c.trace <> ".host-release", "release")
      assert_receive {:ipse, ^pid, {:done, :error}}, 10_000
      refute File.exists?(c.trace <> ".service")
      assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
      assert Enum.any?(events, &(&1["type"] == "managed_read_observed"))
      refute Enum.any?(events, &(get_in(&1, ["request", "op"]) == unquote(op)))
      assert {:ok, _} = Session.Saved.restore(events, Session.info(pid).id)
      assert :ok = Session.close_confirmed(pid)
    end
  end

  for op <- ["state.put", "state.delete", "service.call"] do
    @tag managed_host_repair: true, managed_host_service: op == "service.call"
    test "ordinary #{op} remains available with --yes", c do
      pid = start(c, %{approval: :allow, approval_origin: :yes, headless: true})

      assert :ok =
               Session.invoke_export(pid, :command, "ext__capture__capture", %{
                 "mode" => "host_ordinary:" <> unquote(op)
               })

      assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
      assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

      assert Enum.any?(
               events,
               &(&1["type"] == "extension_action_result" and
                   get_in(&1, ["request", "op"]) == unquote(op) and
                   get_in(&1, ["outcome", "status"]) == "ok")
             )

      if unquote(op) == "service.call", do: assert(File.exists?(c.trace <> ".service"))
      assert {:ok, _} = Session.Saved.restore(events, Session.info(pid).id)
      assert :ok = Session.close_confirmed(pid)
    end
  end

  @tag :worker_inherited_union
  @tag literal_v4_ab: true, metadata_version: 3
  test "fresh B quote cannot discard genuine inherited A at the actual next Worker frame", c do
    seed = c.literal_seed
    generation = collection_read(c, %{"op" => "snapshot"})["generation"]
    File.write!(c.trace <> ".ab-release", "release")
    pid = start(c, %{fixture_mode: "capture_ab_literal"})
    owner = self()

    hook = fn
      :released, _, _ ->
        :released

      d, {:out, {:ok, payload}, _, state}, _ ->
        action = List.last(state.invocation.results)

        if get_in(action || %{}, ["request", "op"]) == "source.quote" and
             get_in(action || %{}, ["outcome", "status"]) == "ok" and
             payload["operation_id"] == action["operation_id"] do
          {:ok, dependencies} =
            Session.ManagedLineage.invocation_dependencies(
              state.managed_lineage,
              state.invocation.parent["invocation_id"],
              state.invocation.managed_reads
            )

          send(owner, {:fresh_quote_committed, self(), action, dependencies})
          receive do: (:release_fresh_quote -> :released)
        else
          d
        end

      d, _, _ ->
        d
    end

    assert :ok = :sys.install(pid, {hook, nil})
    on_exit(fn -> send(pid, :release_fresh_quote) end)
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:fresh_quote_committed, ^pid, quote, dependencies}, 15_000
    assert quote["outcome"]["value"]["origin"] == "unattended_input"
    assert quote["request"]["quote"] == "Synthetic café observation"
    assert quote["outcome"]["value"]["quote_sha256"] == JSON.sha256("Synthetic café observation")

    assert Enum.any?(
             dependencies,
             &(&1["version"] == 4 and get_in(&1, ["subject", "key"]) == seed["key"])
           )

    trace = File.read!(c.trace)
    source = seed["source_journal"]
    held = source <> ".held-for-worker-input"
    assert JSON.sha256(File.read!(source)) == seed["source_sha256"]
    File.rename!(source, held)

    try do
      send(pid, :release_fresh_quote)
      assert_receive {:ipse, ^pid, {:done, :error}}, 10_000
      assert File.read!(c.trace) == trace
      refute trace =~ Jason.encode!(quote["outcome"])
      assert collection_read(c, %{"op" => "snapshot"})["generation"] == generation
      id = Session.info(pid).id
      assert {:ok, events} = Journal.load(c.dir, id)
      assert quote in events

      refute Enum.any?(
               events,
               &(&1["type"] == "extension_action_intent" and
                   get_in(&1, ["request", "op"]) == "collection.managed")
             )

      input = events |> Enum.filter(&(&1["type"] == "worker_input_intent")) |> List.last()
      assert input["payload_sha256"] == JSON.digest([Ipse.Extension.Actions.resume(quote)])
      assert input["dependencies_sha256"] == JSON.digest(dependencies)

      assert Enum.any?(
               events,
               &(&1["type"] == "worker_input_result" and &1["input_id"] == input["input_id"] and
                   &1["status"] == "unknown")
             )

      assert {:ok, saved} = Session.Saved.restore(events, id)
      assert saved.managed_lineage.unavailable
      assert input["input_id"] in saved.worker_input_unknown
      assert :ok = Session.close_confirmed(pid)
      journal = Path.join(c.dir, id <> ".jsonl")
      before = File.read!(journal)
      resumed = start(c, %{fixture_mode: "capture_ab_literal"}, id)
      assert Session.info(resumed).phase == :idle
      assert File.read!(c.trace) == trace
      assert_idle_resume_journal(journal, before, id)
      assert :ok = Session.close_confirmed(resumed)
    after
      send(pid, :release_fresh_quote)
      File.rename!(held, source)
      assert JSON.sha256(File.read!(source)) == seed["source_sha256"]
    end
  end

  @tag :worker_inherited_union
  @tag literal_v4_ab: true, metadata_version: 3, registered_main: true, capture_write: true
  test "independent current B completes capture while unread A's original journal is unavailable",
       c do
    seed = c.literal_seed
    source = seed["source_journal"]
    held = source <> ".held-for-independent-b"
    assert JSON.sha256(File.read!(source)) == seed["source_sha256"]
    File.rename!(source, held)

    try do
      pid = start(c)
      assert :ok = Session.prompt(pid, "Synthetic café observation")
      assert_receive {:ipse, ^pid, {:done, status}}, 15_000
      id = Session.info(pid).id
      assert {:ok, events} = Journal.load(c.dir, id)
      assert status == :ok

      [publication] =
        Enum.filter(
          events,
          &(&1["type"] == "extension_action_result" and
              get_in(&1, ["request", "op"]) == "collection.managed")
        )

      assert publication["outcome"]["status"] == "ok"
      [change] = get_in(publication, ["request", "request", "changes"])
      record = collection_read(c, %{"op" => "get", "key" => change["key"]})["record"]
      assert record["value"]["text"] == "Synthetic café observation"
      assert [proof] = get_in(record, ["value", "evidence", "sources"])
      assert proof["session_id"] == id and proof["origin"] == "unattended_input"

      refute Enum.any?(events, fn event ->
               event["type"] == "managed_read_observed" and
                 Enum.any?(
                   event["dependencies"],
                   &(&1["version"] == 4 and get_in(&1, ["subject", "key"]) == seed["key"])
                 )
             end)

      assert {:ok, saved} = Session.Saved.restore(events, id)
      assert saved.worker_input_unknown == []
      assert :ok = Session.close_confirmed(pid)
      trace = File.read!(c.trace)
      journal = Path.join(c.dir, id <> ".jsonl")
      before = File.read!(journal)
      resumed = start(c, %{}, id)
      assert Session.info(resumed).phase == :idle
      assert File.read!(c.trace) == trace
      assert_idle_resume_journal(journal, before, id)
      assert :ok = Session.close_confirmed(resumed)
      assert [_, _] = requests = Task.await(c.provider_server, 1000)
      refute inspect(requests) =~ seed["text"]
    after
      File.rename!(held, source)
      assert JSON.sha256(File.read!(source)) == seed["source_sha256"]
    end
  end

  @tag literal_v4_ab: true, metadata_version: 3
  test "upgraded literal v4 A cannot be discarded while candidate cites independent current B",
       c do
    seed = c.literal_seed
    assert File.read!(seed["source_journal"]) |> JSON.sha256() == seed["source_sha256"]
    assert seed["closed_at_ms"] < seed["policy"]["settings"]["expires_at_ms"]
    baseline = collection_read(c, %{"op" => "snapshot"})

    consumer = start(c, %{fixture_mode: "capture_ab_literal"})
    id = Session.info(consumer).id
    assert id != seed["session_id"]
    assert :ok = Session.prompt(consumer, "Synthetic café observation")
    await_marker(c.trace, "ab-held", 1000)
    assert {:ok, before_events} = Journal.load(c.dir, id)

    literals =
      for event <- before_events,
          event["type"] == "managed_read_observed",
          dependency <- event["dependencies"],
          dependency["version"] == 4,
          do: dependency

    assert [literal] = literals
    assert literal["subject"]["record"] != nil
    assert literal["subject"]["key"] == seed["key"]

    [source_a] =
      before_events
      |> Enum.find(
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["outcome", "value", "record", "key"]) == seed["key"])
      )
      |> get_in(["outcome", "value", "record", "value", "evidence", "sources"])

    assert source_a["origin"] == "native_operator_assertion"
    assert source_a["session_id"] == seed["session_id"]
    IO.puts("LITERAL_V4_AB_REAL_READ=true inherited_union=true")

    module = Ipse.Session.ManagedToolUse

    assert :erlang.trace_pattern(
             {module, :publication_prerequisites?, 3},
             [{:_, [], [{:return_trace}]}],
             [:local]
           ) > 0

    :erlang.trace(consumer, true, [:call])
    held_path = seed["source_journal"] <> ".held-for-ab"
    File.rename!(seed["source_journal"], held_path)

    try do
      File.write!(c.trace <> ".ab-release", "release")

      assert_receive {:trace, ^consumer, :return_from, {^module, :publication_prerequisites?, 3},
                      false},
                     15_000

      assert_receive {:ipse, ^consumer, {:done, :error}}, 15_000
      assert {:ok, events} = Journal.load(c.dir, id)

      quotes =
        Enum.filter(
          events,
          &(&1["type"] == "extension_action_result" and
              get_in(&1, ["request", "op"]) == "source.quote")
        )

      assert [%{"outcome" => %{"status" => "ok", "value" => quote}}] = quotes
      assert quote["origin"] == "unattended_input"

      assert Enum.any?(
               events,
               &(&1["type"] == "message" and
                   get_in(&1, ["message", "content"]) == "Synthetic café observation")
             )

      refute Enum.any?(
               events,
               &(&1["type"] == "extension_action_intent" and
                   get_in(&1, ["request", "op"]) == "collection.managed")
             )

      notifications = drain_literal_ab_notifications(consumer, [])
      refute inspect(notifications) =~ seed["text"]
      refute inspect(Session.info(consumer)) =~ seed["text"]

      refute inspect(notifications) =~
               "Protected collection publication is temporarily unavailable"

      assert {:ok, restored} = Session.Saved.restore(events, id)
      refute inspect(restored.messages) =~ seed["text"]
      assert collection_read(c, %{"op" => "snapshot"})["generation"] == baseline["generation"]

      IO.puts(
        "LITERAL_V4_AB_INHERITANCE_REFUSED=true candidate_intents=0 current_B_quote=true raw_subscriber_leak=false blanket_gate_reached=false"
      )

      assert :ok = Session.close_confirmed(consumer)
    after
      :erlang.trace_pattern({module, :publication_prerequisites?, 3}, false, [:local])
      if Process.alive?(consumer), do: :erlang.trace(consumer, false, [:call])
      if File.exists?(held_path), do: File.rename!(held_path, seed["source_journal"])
    end

    assert File.read!(seed["source_journal"]) |> JSON.sha256() == seed["source_sha256"]
  end

  @tag current_literal_publication: true,
       worker_inherited_union: true,
       literal_v4_ab: true,
       metadata_version: 3,
       registered_main: true,
       capture_write: true,
       registered_capture_mode: "capture_ab_literal_publication"
  test "current literal A remains in the causal union while a new B proposal publishes", c do
    seed = c.literal_seed
    before = collection_read(c, %{"op" => "snapshot"})
    pid = start(c)
    id = Session.info(pid).id
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    assert {:ok, events} = Journal.load(c.dir, id)

    [literal] =
      for event <- events,
          event["type"] == "managed_read_observed",
          dependency <- event["dependencies"],
          dependency["version"] == 4,
          do: dependency

    assert literal["subject"]["key"] == seed["key"]
    [publication] = capture_results(events)
    assert publication["outcome"]["status"] == "ok"
    assert publication["outcome"]["value"]["normalization"]["eligibility"] == "never_current"
    [change] = publication["request"]["request"]["changes"]
    [proof] = change["value"]["evidence"]["sources"]
    assert proof["session_id"] == id and id != seed["session_id"]
    assert proof["origin"] == "unattended_input"

    assert collection_read(c, %{"op" => "get", "key" => change["key"]})["record"]["value"] ==
             change["value"]

    assert collection_read(c, %{"op" => "snapshot"})["generation"] == before["generation"] + 1
    assert JSON.sha256(File.read!(seed["source_journal"])) == seed["source_sha256"]
    assert {:ok, saved} = Session.Saved.restore(events, id)
    refute saved.managed_lineage.unavailable
    assert saved.managed_lineage.dictionary[JSON.digest([literal])] == literal

    assert JSON.digest([literal]) in saved.managed_lineage.outputs[
             publication["parent_invocation_id"]
           ]

    assert saved.worker_input_unknown == []
    assert {:ok, ledger} = Consent.snapshot(c.control, c.binding["project_id"])
    operation = ledger["operations"][publication["operation_id"]]
    assert operation["status"] == "settled"
    assert operation["actual"]["input_bytes"] < operation["reserved"]["input_bytes"]
    assert :ok = Session.close_confirmed(pid)
    assert_capture_idle_resume(c, id, saved)
    assert [_, _] = Task.await(c.provider_server, 5000)
  end

  for boundary <- [:source, :policy] do
    @tag current_literal_publication: true,
         worker_inherited_union: true,
         literal_v4_ab: true,
         metadata_version: 3,
         registered_main: true,
         capture_write: true,
         registered_capture_no_continuation: true,
         registered_capture_mode: "capture_ab_literal_publication_hold"
    test "current-literal capture refuses #{boundary} loss after B input before publication", c do
      seed = c.literal_seed
      before = collection_read(c, %{"op" => "snapshot"})
      assert {:ok, ledger} = Consent.snapshot(c.control, c.binding["project_id"])
      pid = start(c)
      id = Session.info(pid).id
      assert :ok = Session.prompt(pid, "Synthetic café observation")
      await_marker(c.trace, "candidate-held", 1500)
      held = seed["source_journal"] <> ".capture-held"

      try do
        case unquote(boundary) do
          :source ->
            File.rename!(seed["source_journal"], held)

          :policy ->
            assert {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], ledger["epoch"])
        end

        File.write!(c.trace <> ".candidate-release", "release")
        assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
        assert {:ok, events} = Journal.load(c.dir, id)
        refute Enum.any?(capture_results(events), &(&1["outcome"]["status"] == "ok"))

        assert Enum.any?(
                 events,
                 &(&1["type"] == "extension_action_result" and
                     get_in(&1, ["request", "op"]) == "source.quote" and
                     get_in(&1, ["outcome", "status"]) == "ok")
               )

        assert collection_read(c, %{"op" => "snapshot"}) == before
        assert {:ok, after_ledger} = Consent.snapshot(c.control, c.binding["project_id"])
        assert after_ledger["operations"] == ledger["operations"]
        assert {:ok, saved} = Session.Saved.restore(events, id)
        assert :ok = Session.close_confirmed(pid)
        assert_capture_idle_resume(c, id, saved)
      after
        File.write!(c.trace <> ".candidate-release", "release")
        if File.exists?(held), do: File.rename!(held, seed["source_journal"])
      end
    end
  end

  @tag current_literal_publication: true,
       worker_inherited_union: true,
       literal_v4_ab: true,
       metadata_version: 3,
       registered_main: true,
       capture_write: true,
       registered_capture_no_continuation: true,
       registered_capture_mode: "capture_ab_literal_publication"
  test "original A owner loss after staging prevents the native B publication and refunds nothing",
       c do
    owner = self()
    handler = {__MODULE__, make_ref()}
    before = collection_read(c, %{"op" => "snapshot"})

    :ok =
      :telemetry.attach(
        handler,
        [:ipse, :extension, :collection, :staged],
        &__MODULE__.lose_capture_source/4,
        {owner, c.literal_seed["session_id"]}
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    pid = start(c)
    monitor = Process.monitor(pid)
    id = Session.info(pid).id
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:capture_source_owner_closed, true}, 15_000
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 15_000
    assert {:ok, events} = Journal.load(c.dir, id)
    assert capture_results(events) == []

    [publication] =
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_intent" and
            get_in(&1, ["request", "op"]) == "collection.managed")
      )

    assert collection_read(c, %{"op" => "snapshot"}) == before
    assert {:ok, ledger} = Consent.snapshot(c.control, c.binding["project_id"])
    operation = ledger["operations"][publication["operation_id"]]
    assert operation["status"] in ~w(publishing unknown)
    assert operation["actual"] == nil and operation["receipt"] == nil

    assert operation["reserved"] ==
             Ipse.Extension.ManagedCollectionCall.reservation(publication["request"])

    assert {:ok, saved} = Session.Saved.restore(events, id)
    assert saved.extension_state.unknown or is_map(saved.extension_state.action)
    assert_capture_idle_resume(c, id, saved)
    assert {:ok, after_ledger} = Consent.snapshot(c.control, c.binding["project_id"])
    assert after_ledger["operations"][publication["operation_id"]] == operation
  end

  def lose_capture_source(_, _, _, {owner, id}) do
    shares = Process.get({Ipse.Session.StoredSources, :shareable_source}) || %{}

    case Enum.find(shares, fn {_, share} -> share.session_id == id and share.phase == :shared end) do
      {_, %{port: port}} -> send(owner, {:capture_source_owner_closed, Port.close(port)})
      _ -> :ok
    end
  end

  defp capture_results(events),
    do:
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "op"]) == "collection.managed")
      )

  defp assert_capture_idle_resume(c, id, saved) do
    path = Path.join(c.dir, id <> ".jsonl")
    journal = File.read!(path)
    trace = File.read!(c.trace)
    resumed = start(c, %{}, id)
    assert Session.info(resumed).phase == :idle
    assert :sys.get_state(resumed).messages == saved.messages
    assert_idle_resume_journal(path, journal, id)
    assert :ok = Session.close_confirmed(resumed)
    assert File.read!(c.trace) == trace
  end

  defp drain_literal_ab_notifications(pid, acc) do
    receive do
      {:ipse, ^pid, notification} -> drain_literal_ab_notifications(pid, [notification | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  @tag managed_ab_probe: true,
       metadata_version: 3,
       registered_main: true,
       capture_write: true,
       registered_ab_publication: true
  test "publication cannot discard an earlier stale managed A while citing current source B", c do
    seed = start(c)
    assert :ok = Session.prompt(seed, "Synthetic café observation")
    assert_receive {:ipse, ^seed, {:done, :ok}}, 15_000
    seed_id = Session.info(seed).id
    assert :ok = Session.close_confirmed(seed)
    assert {:ok, initial} = Journal.load(c.dir, seed_id)

    assert Enum.any?(
             initial,
             &(&1["type"] == "extension_action_result" and
                 &1["request"]["op"] == "collection.managed" and &1["outcome"]["status"] == "ok")
           )

    consumer = start(c, %{fixture_mode: "capture_ab_publication"})
    assert :ok = Session.prompt(consumer, "Synthetic café observation")
    await_marker(c.trace, "candidate-held", 500)
    id = Session.info(consumer).id
    assert {:ok, before_events} = Journal.load(c.dir, id)

    [scan] =
      Enum.filter(before_events, fn event ->
        event["type"] == "extension_action_result" and
          get_in(event, ["request", "request", "op"]) == "scan"
      end)

    assert scan["outcome"]["status"] == "ok"
    [record_a] = get_in(scan, ["outcome", "value", "records"])
    [source_a] = get_in(record_a, ["value", "evidence", "sources"])
    assert source_a["session_id"] == seed_id

    read_a =
      Enum.find(
        before_events,
        &(&1["type"] == "managed_read_observed" and &1["operation_id"] == scan["operation_id"])
      )

    assert read_a["dependencies"] != []

    [quote_b] =
      Enum.filter(before_events, fn event ->
        event["type"] == "extension_action_result" and
          get_in(event, ["request", "op"]) == "source.quote"
      end)

    assert quote_b["outcome"]["status"] == "ok"
    assert quote_b["outcome"]["value"]["origin"] == "unattended_input"
    assert quote_b["request"]["quote"] == "Synthetic café observation"

    [read_b] =
      Enum.filter(before_events, fn event ->
        event["type"] == "extension_action_result" and
          get_in(event, ["request", "op"]) == "source.read"
      end)

    page_b = read_b["outcome"]["value"]
    assert page_b["window"]["session_id"] == id

    assert {:ok, proof_b} =
             Ipse.Extension.source_proof(
               page_b,
               quote_b["outcome"]["value"],
               "Synthetic café observation"
             )

    assert proof_b["session_id"] == id and id != source_a["session_id"]
    state = :sys.get_state(consumer)
    assert {:ok, dependencies} = Session.ManagedToolUse.invocation_dependencies(state)
    assert dependencies != []
    assert Enum.all?(read_a["dependencies"], &(&1 in dependencies))

    module = Session.ManagedToolUse

    assert :erlang.trace_pattern(
             {module, :publication_prerequisites?, 3},
             [{:_, [], [{:return_trace}]}],
             [:local]
           ) == 1

    :erlang.trace(consumer, true, [:call])

    on_exit(fn ->
      :erlang.trace_pattern({module, :publication_prerequisites?, 3}, false, [:local])
      if Process.alive?(consumer), do: :erlang.trace(consumer, false, [:call])
      File.write!(c.trace <> ".candidate-release", "release")
    end)

    concurrent = start(c)
    assert :ok = Session.prompt(concurrent, "Synthetic café observation")
    assert_receive {:ipse, ^concurrent, {:done, :ok}}, 15_000
    assert :ok = Session.close_confirmed(concurrent)
    after_winner = collection_read(c, %{"op" => "snapshot"})
    assert after_winner["generation"] == 2
    File.write!(c.trace <> ".candidate-release", "release")

    assert_receive {:trace, ^consumer, :call,
                    {^module, :publication_prerequisites?, [at_call, candidate, _binding]}},
                   15_000

    assert {:ok, ^dependencies} = Session.ManagedToolUse.invocation_dependencies(at_call)
    [change] = candidate["request"]["changes"]
    assert change["value"]["evidence"]["sources"] == [proof_b]

    assert candidate["proofs"] == [
             %{"handle" => page_b["handle"], "quote" => "Synthetic café observation"}
           ]

    # Shape admission preserves the full union; the retained current-use
    # check must still reject A before reservation or native publication.
    assert_receive {:trace, ^consumer, :return_from, {^module, :publication_prerequisites?, 3},
                    true},
                   15_000

    assert_receive {:ipse, ^consumer, {:done, :error}}, 15_000
    assert {:ok, events} = Journal.load(c.dir, id)

    writes =
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "collection.managed")
      )

    assert [intent] =
             Enum.filter(
               events,
               &(&1["type"] == "extension_action_intent" and
                   get_in(&1, ["request", "op"]) == "collection.managed")
             )

    assert intent["request"] == candidate

    refute Enum.any?(writes, &(&1["outcome"]["status"] == "ok"))
    assert quote_b in events
    assert collection_read(c, %{"op" => "snapshot"}) == after_winner
    assert {:ok, saved} = Session.Saved.restore(events, id)
    assert :ok = Session.close_confirmed(consumer)
    path = Path.join(c.dir, id <> ".jsonl")
    journal = File.read!(path)
    trace = File.read!(c.trace)
    resumed = start(c, %{}, id)
    assert Session.info(resumed).phase == :idle
    assert :sys.get_state(resumed).messages == saved.messages
    assert_idle_resume_journal(path, journal, id)
    assert :ok = Session.close_confirmed(resumed)
    assert File.read!(c.trace) == trace
    assert {:ok, ledger} = Consent.snapshot(c.control, c.binding["project_id"])
    assert map_size(ledger["operations"]) == 2

    assert Enum.all?(ledger["operations"], fn {_, operation} ->
             operation["status"] == "settled"
           end)

    assert length(Task.await(c.provider_server, 5000)) == 5
  end

  @tag managed_question_ordinary: true
  test "ordinary pending question still resumes with its complete arguments", c do
    pid = start(c, %{operator_questions: true, legacy_question_fixture: true})
    assert :ok = Session.prompt(pid, "An ordinary synthetic question")
    assert_receive {:ipse, ^pid, {:question, "legacy_question", arguments}}, 10_000
    id = Session.info(pid).id
    writer = :sys.get_state(pid).journal_writer
    monitor = Process.monitor(pid)
    writer_monitor = Process.monitor(writer)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5000
    assert_receive {:DOWN, ^writer_monitor, :process, ^writer, _}, 5000
    resumed = start(c, %{operator_questions: true}, id)
    assert_receive {:ipse, ^resumed, {:question, "legacy_question", ^arguments}}, 5000
    assert Session.info(resumed).question.arguments == arguments
    assert Session.info(resumed).question_recovery == nil
    assert :ok = Session.answer(resumed, "legacy_question", %{"detail" => "ordinary answer"})
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, events} = Journal.load(c.dir, id)
    assert Enum.count(events, &(&1["type"] == "operator_answer")) == 1
  end

  for boundary <- [:revoke, :expiry] do
    @tag managed_question_recovery: true, wire_expiry: boundary == :expiry
    test "legacy managed pending question is inert after #{boundary} on real resume", c do
      pid = start(c, %{operator_questions: true, legacy_question_fixture: true})

      assert :ok =
               Session.invoke_export(pid, :command, "ext__capture__inspect", %{"mode" => "read"})

      assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
      id = Session.info(pid).id
      # Model the historical producer that lacked managed-read tracking. All
      # request, usage and question records still come from the actual Session.
      {:ok, untracked} = Session.ManagedLineage.new(id)
      :sys.replace_state(pid, &%{&1 | managed_lineage: untracked})
      assert :ok = Session.prompt(pid, "Continue the historical question")
      assert_receive {:ipse, ^pid, {:question, "legacy_question", _}}, 10_000
      writer = :sys.get_state(pid).journal_writer
      monitor = Process.monitor(pid)
      writer_monitor = Process.monitor(writer)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5000
      assert_receive {:DOWN, ^writer_monitor, :process, ^writer, _}, 5000
      assert {:ok, events} = Journal.load(c.dir, id)
      assert Enum.any?(events, &(&1["type"] == "managed_read_observed"))

      legacy =
        events
        |> Enum.map(fn
          %{"type" => "session", "metadata" => metadata} = event ->
            %{event | "metadata" => Map.delete(metadata, "managed_read_layout")}

          %{"type" => "managed_read_observed"} ->
            %{"type" => "legacy_untracked_observation"}

          event ->
            event
        end)

      assert {:ok, saved} = Session.Saved.restore(legacy, id)
      assert saved.managed_lineage.unavailable
      assert {:ok, restored} = Session.Saved.restore(legacy, id)
      assert restored.question == nil
      assert restored.question_recovery == :managed_question_withheld
      path = Path.join(c.dir, id <> ".jsonl")
      original_lines = File.read!(path) |> String.split("\n", trim: true)
      # Keep the genuine historical source byte ranges/line ordinals intact.
      # Only absent tracking metadata/observations are modeled as the old layout.
      lines =
        Enum.zip([events, legacy, original_lines])
        |> Enum.map(fn {before, after_event, line} ->
          encoded = if before == after_event, do: line, else: Jason.encode!(after_event)
          assert byte_size(encoded) <= byte_size(line)
          [encoded, String.duplicate(" ", byte_size(line) - byte_size(encoded)), "\n"]
        end)

      File.write!(path, lines)
      assert {:ok, policy} = Consent.snapshot(c.control, c.binding["project_id"])

      if unquote(boundary) == :revoke do
        assert {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], policy["epoch"])
      else
        Process.sleep(
          max(policy["policy"]["expires_at_ms"] - System.system_time(:millisecond) + 10, 0)
        )
      end

      resumed = start(c, %{operator_questions: true}, id)
      assert Session.info(resumed).question == nil
      assert Session.info(resumed).question_recovery == :managed_question_withheld
      refute_receive {:ipse, ^resumed, {:question, _, _}}, 50

      assert {:error, :no_pending_question} =
               Session.answer(resumed, "legacy_question", %{"detail" => "unused"})

      assert :ok = Session.close_confirmed(resumed)
      assert {:ok, after_events} = Journal.load(c.dir, id)

      refute Enum.any?(
               after_events,
               &(&1["type"] in ["operator_answer", "operator_question_closed"])
             )

      assert Enum.take(after_events, length(legacy)) == legacy
    end
  end

  for boundary <- [:current, :root_change, :writer_loss] do
    @tag managed_host_display: true, nested_document: true
    test "managed extension approval refuses full argument display after #{boundary}", c do
      pid = start(c, %{approval: :ask, approval_origin: :interactive, headless: false})

      assert :ok =
               Session.invoke_export(pid, :command, "ext__capture__capture", %{
                 "mode" =>
                   if(unquote(boundary) == :current,
                     do: "nested_document",
                     else: "nested_document_hold"
                   )
               })

      id = Session.info(pid).id

      if unquote(boundary) != :current do
        await_marker(c.trace, "nested-document-held", 500)

        if unquote(boundary) == :writer_loss do
          monitor = Process.monitor(pid)
          Process.exit(:sys.get_state(pid).journal_writer, :kill)
          assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 6000
        else
          assert {:ok, _} =
                   Ipse.Extension.Collection.execute(
                     SemanticAdmission.collection_root(c.home),
                     c.namespace,
                     %{
                       "op" => "commit",
                       "expected_generation" => 0,
                       "advance_floor" => false,
                       "changes" => [
                         %{
                           "key" => "changed.before.display",
                           "expected_revision" => 0,
                           "value" => %{}
                         }
                       ]
                     },
                     Ipse.Usage.id()
                   )

          File.write!(c.trace <> ".host-release", "release")
        end
      end

      if unquote(boundary) != :writer_loss,
        do: assert_receive({:ipse, ^pid, {:done, :error}}, 10_000)

      refute_receive {:ipse, ^pid, {:approval, _, _, _}}, 50
      refute_receive {:ipse, ^pid, {:tool, "extension:tool.call", _}}, 50
      assert {:ok, events} = Journal.load(c.dir, id)
      assert Enum.any?(events, &(&1["type"] == "managed_read_observed"))
      refute Enum.any?(events, &(get_in(&1, ["request", "op"]) == "collection.store"))
      refute Enum.any?(events, &(&1["type"] == "managed_tool_effect_admitted"))
      assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
      if Process.alive?(pid), do: assert(:ok = Session.close_confirmed(pid))
    end
  end

  @tag managed_host_display: true, managed_host_non_document: true
  test "ordinary untainted extension approval still shows complete proposed arguments", c do
    pid = start(c, %{approval: :ask, approval_origin: :interactive, headless: false})

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__capture", %{"mode" => "ordinary"})

    assert_receive {:ipse, ^pid, {:approval, approval, "extension:tool.call", proposed}}, 10_000

    assert proposed["request"] == %{
             "op" => "tool.call",
             "name" => "write",
             "timeout_ms" => 1000,
             "arguments" => %{"path" => "forbidden", "content" => "denied"}
           }

    assert :ok = Session.approve(pid, approval, false)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    refute File.exists?(Path.join(c.cwd, "forbidden"))
    assert :ok = Session.close_confirmed(pid)
  end

  for operation <- [nil, "source_list"] do
    @tag managed_host_display: true,
         managed_host_non_document: true,
         registered_main: true,
         ordinary_effect: true,
         managed_host_operation: operation
    test "managed model call #{operation || "write approval"} cannot queue raw arguments or enter unqualified host IO",
         c do
      pid = start(c, %{approval: :ask, approval_origin: :interactive, headless: false})
      assert :ok = Session.prompt(pid, "Use the synthetic managed observation.")
      assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
      name = unquote(operation || "write")
      refute_receive {:ipse, ^pid, {:approval, _, _, _}}, 50
      refute File.exists?(Path.join(c.cwd, "managed-output.txt"))
      state = :sys.get_state(pid)
      assert {:ok, events} = Journal.load(c.dir, state.id)

      if name == "source_list" do
        assert_receive {:ipse, ^pid, {:tool, "source_list", %{}}}, 50

        assert_receive {:ipse, ^pid,
                        {:tool_result, "source_list",
                         "Source tool result withheld from terminal preview."}},
                       50

        assert %{"call_id" => call_id} =
                 Enum.find(events, &(&1["type"] == "tool_started" and &1["name"] == name))

        assert Enum.any?(events, fn event ->
                 event["type"] == "managed_source_lookup_prepared" and
                   event["call_id"] == call_id and event["operation"] == "source.list"
               end)

        assert Enum.any?(state.messages, fn message ->
                 message["role"] == "tool" and message["tool_call_id"] == call_id and
                   get_in(message, ["ipse_tool_outcome", "status"]) == "result_recorded"
               end)
      else
        refute_receive {:ipse, ^pid, {:tool, ^name, _}}, 50
        refute Enum.any?(events, &(&1["type"] == "tool_started" and &1["name"] == name))

        assert Enum.any?(
                 state.messages,
                 &(get_in(&1, ["ipse_tool_outcome", "status"]) == "denied")
               )
      end

      assert {:ok, _} = Ipse.Session.Saved.restore(events, state.id)
      assert :ok = Session.close_confirmed(pid)
      Task.shutdown(c.provider_server, :brutal_kill)
    end
  end

  for approval <- [:allow, :ask] do
    @tag document_decision_gate: true, nested_document: true
    test "managed document mutation refuses before intent under #{approval}", c do
      pid =
        start(c, %{approval: unquote(approval), approval_origin: :interactive, headless: false})

      namespace = Ipse.Extension.CollectionStore.namespace(c.binding["project_id"])
      directory = Path.join(Ipse.Extension.CollectionStore.root(c.home), namespace)

      assert :ok =
               Session.invoke_export(pid, :command, "ext__capture__capture", %{
                 "mode" => "nested_document"
               })

      assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
      refute_receive {:ipse, ^pid, {:approval, _, _, _}}, 50
      refute_receive {:ipse, ^pid, {:tool, "extension:collection.store", _}}, 50
      id = Session.info(pid).id
      assert {:ok, events} = Journal.load(c.dir, id)
      assert Enum.any?(events, &(&1["type"] == "managed_read_observed"))
      refute Enum.any?(events, &(get_in(&1, ["request", "op"]) == "collection.store"))
      refute Enum.any?(events, &(&1["type"] == "managed_tool_effect_admitted"))
      refute File.exists?(directory)
      assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
      assert :ok = Session.close_confirmed(pid)
    end
  end

  for kind <- [:native, :mcp] do
    @tag :managed_nested_result
    @tag nested_mcp: kind == :mcp, managed_mcp: kind == :mcp
    test "an explicitly allowed nested #{kind} effect returns through its actual managed Worker input",
         c do
      pid = start(c, %{approval: :allow, approval_origin: :yes, headless: true})
      mode = "nested_#{unquote(kind)}"
      operation = if unquote(kind) == :native, do: "tool.call", else: "mcp.call"
      marker = "SYNTHETIC_NESTED_#{String.upcase(to_string(unquote(kind)))}"

      assert :ok =
               Session.invoke_export(pid, :command, "ext__capture__capture", %{"mode" => mode})

      assert_receive {:ipse, ^pid, {:done, status}}, 15_000
      assert File.read!(Path.join(c.cwd, "nested-#{unquote(kind)}.txt")) == marker
      id = Session.info(pid).id
      assert {:ok, events} = Journal.load(c.dir, id)

      assert status == :ok,
             "physical nested effect settled but result continuation ended #{status}"

      [action] =
        Enum.filter(
          events,
          &(get_in(&1, ["request", "op"]) == operation and
              &1["type"] == "extension_action_result")
        )

      assert action["outcome"]["status"] == "ok"
      refute Enum.any?(events, &(&1["type"] == "managed_action_output_withheld"))
      actions = Enum.filter(events, &(&1["type"] == "extension_action_result"))
      input = events |> Enum.filter(&(&1["type"] == "worker_input_intent")) |> List.last()
      assert input["actions_sha256"] == JSON.digest(actions)
      assert input["payload_sha256"] == JSON.digest([Ipse.Extension.Actions.resume(action)])

      assert Enum.any?(
               events,
               &(&1["type"] == "worker_input_result" and &1["input_id"] == input["input_id"] and
                   &1["status"] == "delivered")
             )

      trace = File.read!(c.trace)
      assert trace =~ Jason.encode!(action["outcome"])

      if unquote(kind) == :native do
        assert_receive {:ipse, ^pid, {:tool_result, "extension:tool.call", preview}}, 50
        assert preview == "Managed tool result withheld from terminal preview."
      else
        refute_receive {:ipse, ^pid, {:tool_result, "extension:tool.call", _}}, 50
      end

      assert {:ok, saved} = Session.Saved.restore(events, id)
      refute saved.managed_lineage.unavailable
      assert :ok = Session.close_confirmed(pid)
      journal = Path.join(c.dir, id <> ".jsonl")
      before = File.read!(journal)
      resumed = start(c, %{approval: :allow, approval_origin: :yes, headless: true}, id)
      assert Session.info(resumed).phase == :idle
      assert File.read!(c.trace) == trace
      assert_idle_resume_journal(journal, before, id)
      assert :ok = Session.close_confirmed(resumed)
    end
  end

  for kind <- [:native, :mcp], boundary <- [:root_change, :revoke] do
    @tag :managed_nested_result
    @tag nested_mcp: kind == :mcp, managed_mcp: kind == :mcp
    test "nested #{kind} result is withheld after #{boundary} between committed effect and Worker input",
         c do
      pid = start(c, %{approval: :allow, approval_origin: :yes, headless: true})
      operation = if unquote(kind) == :native, do: "tool.call", else: "mcp.call"
      owner = self()

      hook = fn
        :released, _, _ ->
          :released

        d, {:out, {:ok, payload}, _, %{invocation: %{results: results}}}, _ ->
          action = List.last(results)

          if get_in(action || %{}, ["request", "op"]) == operation and
               get_in(action || %{}, ["outcome", "status"]) == "ok" and
               payload["operation_id"] == action["operation_id"] do
            send(owner, {:nested_result_committed, self(), action})
            receive do: (:release_nested_result -> :released)
          else
            d
          end

        d, _, _ ->
          d
      end

      assert :ok = :sys.install(pid, {hook, nil})

      assert :ok =
               Session.invoke_export(pid, :command, "ext__capture__capture", %{
                 "mode" => "nested_#{unquote(kind)}"
               })

      assert_receive {:nested_result_committed, ^pid, action}, 15_000
      trace = File.read!(c.trace)
      target = Path.join(c.cwd, "nested-#{unquote(kind)}.txt")
      assert File.read!(target) == "SYNTHETIC_NESTED_#{String.upcase(to_string(unquote(kind)))}"

      try do
        if unquote(boundary) == :revoke do
          assert {:ok, policy} = Consent.snapshot(c.control, c.binding["project_id"])
          assert {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], policy["epoch"])
        else
          assert {:ok, _} =
                   Ipse.Extension.Collection.execute(
                     SemanticAdmission.collection_root(c.home),
                     c.namespace,
                     %{
                       "op" => "commit",
                       "expected_generation" => 0,
                       "advance_floor" => false,
                       "changes" => [
                         %{
                           "key" => "changed.before.result.input",
                           "expected_revision" => 0,
                           "value" => %{}
                         }
                       ]
                     },
                     Ipse.Usage.id()
                   )
        end
      after
        send(pid, :release_nested_result)
      end

      assert_receive {:ipse, ^pid, {:done, :error}}, 10_000
      refute_receive {:ipse, ^pid, {:extension_result, _}}, 50
      assert File.read!(c.trace) == trace
      refute trace =~ Jason.encode!(action["outcome"])
      id = Session.info(pid).id
      assert {:ok, events} = Journal.load(c.dir, id)
      assert action in events
      refute Enum.any?(events, &(&1["type"] == "managed_action_output_withheld"))
      input = events |> Enum.filter(&(&1["type"] == "worker_input_intent")) |> List.last()
      assert input["payload_sha256"] == JSON.digest([Ipse.Extension.Actions.resume(action)])

      assert Enum.any?(
               events,
               &(&1["type"] == "worker_input_result" and &1["input_id"] == input["input_id"] and
                   &1["status"] == "unknown")
             )

      assert {:ok, saved} = Session.Saved.restore(events, id)
      assert saved.managed_lineage.unavailable
      assert input["input_id"] in saved.worker_input_unknown
      assert :ok = Session.close_confirmed(pid)
      journal = Path.join(c.dir, id <> ".jsonl")
      before = File.read!(journal)
      resumed = start(c, %{approval: :allow, approval_origin: :yes, headless: true}, id)
      assert Session.info(resumed).phase == :idle
      assert File.read!(c.trace) == trace
      assert_idle_resume_journal(journal, before, id)
      assert File.read!(target) == "SYNTHETIC_NESTED_#{String.upcase(to_string(unquote(kind)))}"
      assert :ok = Session.close_confirmed(resumed)
    end
  end

  for boundary <- [:current, :root_change, :revoke, :deny, :stale_token, :cancel, :owner_loss] do
    @tag nested_discovery: true, nested_mcp: true, managed_mcp: true
    @tag native_root_approval:
           if(boundary == :current, do: "nested_mcp", else: "nested_mcp_" <> to_string(boundary)),
         timeout: 90_000
    test "nested managed MCP discovery is admitted before approval and #{boundary} is checked at effect entry",
         c do
      if @native_root_approval,
        do: native_nested_effect_approval(c, :mcp, unquote(boundary)),
        else: native_root_terminal("nested_mcp", unquote(boundary))
    end
  end

  for boundary <- [:current, :deny, :root_change] do
    @tag native_nested_tool: true
    @tag native_root_approval:
           "nested_native" <> if(boundary == :current, do: "", else: "_" <> to_string(boundary)),
         timeout: 90_000
    test "native approval of a nested file tool preserves #{boundary} effect and recovery", c do
      if @native_root_approval,
        do: native_nested_effect_approval(c, :native, unquote(boundary)),
        else: native_root_terminal("nested_native", unquote(boundary))
    end
  end

  @tag nested_discovery: true, nested_mcp: true, managed_mcp: true
  test "a subscriber without the native channel cannot display nested managed approval arguments",
       c do
    pid = start(c, %{approval: :ask, approval_origin: :interactive, headless: false})

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__capture", %{
               "mode" => "nested_mcp"
             })

    assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
    refute_receive {:ipse, ^pid, {:approval, _, _, _}}, 50
    refute File.exists?(Path.join(c.cwd, "nested-mcp.txt"))
    refute File.exists?(Path.join(c.cwd, "calls.log"))
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
    assert Enum.count(events, &(&1["type"] == "managed_mcp_discovery_intent")) == 1

    refute Enum.any?(
             events,
             &(&1["type"] == "extension_action_intent" and
                 get_in(&1, ["request", "op"]) == "mcp.call")
           )

    assert {:ok, _} = Session.Saved.restore(events, Session.info(pid).id)
    assert :ok = Session.close_confirmed(pid)
  end

  defp native_nested_effect_approval(c, kind, boundary) do
    mode = "nested_#{kind}"
    operation = if kind == :mcp, do: "mcp.call", else: "tool.call"
    marker = "SYNTHETIC_NESTED_#{String.upcase(to_string(kind))}"
    pid = start(c, %{approval: :ask, approval_origin: :interactive, headless: false})
    id = Session.info(pid).id
    path = Path.join(c.cwd, "nested-#{kind}.txt")
    refute File.exists?(path)

    watcher =
      Task.async(fn ->
        try do
          native_nested_channel(pid, 500)

          assert :ok =
                   Session.invoke_export(pid, :command, "ext__capture__capture", %{
                     "mode" => mode
                   })

          await_marker(Path.join(c.root, "managed-approval-input-ready"), "ready", 1500)
          state = :sys.get_state(pid)
          assert state.phase == :managed_approval and state.share_barrier.phase == :review_input
          spec = state.managed_approval
          assert spec.input["kind"] == "extension.action.approval"

          assert spec.arguments["request"]["arguments"] == %{
                   "path" => "nested-#{kind}.txt",
                   "content" => marker
                 }

          assert spec.dependencies != [] and Enum.all?(spec.dependencies, &(&1["version"] == 3))
          assert Session.ManagedApproval.current?(state, spec.input)

          refute Session.ManagedApproval.current?(
                   state,
                   Map.put(spec.input, "action_sha256", JSON.sha256("foreign action"))
                 )

          [{scope, _}] =
            Elixir.Registry.lookup(Ipse.Registry, {Session.Resources, state.task.pid})

          resource_state = :sys.get_state(scope)
          assert resource_state.owner == pid and resource_state.worker == state.task.pid
          assert Map.has_key?(resource_state.effects, state.share_barrier.caller)
          assert {:error, :session_share_frozen} = Session.approve(pid, spec.id, true)

          assert {:error, :session_share_frozen} =
                   GenServer.call(
                     pid,
                     {:extension_managed_approval_finish, state.job_ref,
                      {:managed_approval, spec.id, spec.sha256, true}}
                   )

          assert {:ok, discovered} = Journal.load(c.dir, id)
          effects = Enum.filter(discovered, &(&1["type"] == "managed_tool_effect_admitted"))

          if kind == :mcp do
            assert Enum.count(discovered, &(&1["type"] == "managed_mcp_discovery_intent")) == 1
            assert Enum.count(discovered, &(&1["type"] == "managed_mcp_discovery_result")) == 1
            assert length(effects) >= 4 and Enum.all?(effects, &(&1["version"] == 3))
          else
            refute Enum.any?(discovered, &(&1["type"] == "managed_mcp_discovery_intent"))
            assert effects == []
          end

          assert {:ok, _} = Session.Saved.restore(discovered, id)
          refute File.exists?(path)
          refute File.exists?(Path.join(c.cwd, "calls.log"))

          File.write!(
            Path.join(c.root, "nested-approval-dependencies.json"),
            Jason.encode!(spec.dependencies)
          )

          if boundary in [:current, :root_change, :revoke, :owner_loss],
            do: native_root_boundary(c, pid, mode, boundary)

          File.write!(Path.join(c.root, "managed-approval-control-checked"), "checked")

          if boundary == :owner_loss,
            do: native_root_released(Path.join(c.dir, id <> ".lock"), 500),
            else: native_root_idle(pid, 1500)

          File.write!(Path.join(c.root, "managed-approval-exit-ready"), "ready")
          File.write!(Path.join(c.root, "native-root-checked"), "checked")
        after
          File.write!(Path.join(c.root, "managed-approval-exit-ready"), "ready")
        end
      end)

    IO.puts("IPSE_MANAGED_APPROVAL_CLI_READY")

    assert if(boundary == :owner_loss, do: 1, else: 0) ==
             Ipse.CLI.Terminal.interact(pid, Process.monitor(pid), true, nil, c.cwd)

    await_marker(Path.join(c.root, "native-root-checked"), "checked", 100)
    Process.demonitor(watcher.ref, [:flush])
    monitor = Process.monitor(watcher.pid)
    assert_receive {:DOWN, ^monitor, :process, _, reason}, 1000
    assert reason in [:normal, :noproc]
    assert {:ok, events} = Journal.load(c.dir, id)

    actions =
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_result" and get_in(&1, ["request", "op"]) == operation)
      )

    effects =
      Enum.filter(events, &(&1["type"] == "managed_tool_effect_admitted" and &1["version"] == 2))

    input = events |> Enum.filter(&(&1["type"] == "worker_input_intent")) |> List.last()
    assert {:ok, saved} = Session.Saved.restore(events, id)

    if boundary in [:cancel, :owner_loss] do
      assert actions == [] and effects == []

      refute Enum.any?(
               events,
               &(&1["type"] == "extension_action_intent" and
                   get_in(&1, ["request", "op"]) == operation)
             )

      assert Enum.count(events, &(&1["type"] == "worker_input_intent")) == 1
      refute File.exists?(path)
      refute File.exists?(Path.join(c.cwd, "calls.log"))
      assert saved.worker_input_unknown == []
      if boundary == :owner_loss, do: refute(Process.alive?(pid))
    else
      assert [action] = actions
      expected_approval = if boundary in [:deny, :stale_token], do: "denied", else: "approved"
      assert action["approval"] == expected_approval

      unless kind == :native and boundary == :root_change,
        do:
          assert(input["payload_sha256"] == JSON.digest([Ipse.Extension.Actions.resume(action)]))

      cond do
        boundary == :current ->
          assert File.read!(path) == marker
          if kind == :mcp, do: assert(File.read!(Path.join(c.cwd, "calls.log")) == "write_note\n")
          assert action["outcome"]["status"] == "ok"
          assert length(effects) == if(kind == :mcp, do: 2, else: 1)
          refute Enum.any?(events, &(&1["type"] == "managed_action_output_withheld"))
          assert File.read!(c.trace) =~ Jason.encode!(action["outcome"])
          assert saved.worker_input_unknown == []
          refute saved.managed_lineage.unavailable

        boundary in [:deny, :stale_token] ->
          assert action["outcome"] == %{"status" => "denied", "value" => %{}}
          assert effects == []
          assert File.read!(c.trace) =~ Jason.encode!(action["outcome"])
          assert saved.worker_input_unknown == []
          refute saved.managed_lineage.unavailable
          refute File.exists?(path)
          refute File.exists?(Path.join(c.cwd, "calls.log"))

        kind == :native and boundary == :root_change ->
          assert action["outcome"] == %{"status" => "unknown", "value" => %{}}
          assert effects == []
          assert Enum.count(events, &(&1["type"] == "worker_input_intent")) == 1

          [root_action] =
            Enum.filter(
              events,
              &(&1["type"] == "extension_action_result" and
                  get_in(&1, ["request", "op"]) == "collection.call")
            )

          assert input["payload_sha256"] ==
                   JSON.digest([Ipse.Extension.Actions.resume(root_action)])

          assert [%{"status" => "delivered"}] =
                   Enum.filter(events, &(&1["type"] == "worker_input_result"))
                   |> Enum.map(&Map.take(&1, ["status"]))

          assert saved.worker_input_unknown == []
          refute saved.managed_lineage.unavailable
          refute File.exists?(path)
          refute File.read!(c.trace) =~ Jason.encode!(action["outcome"])

        true ->
          refute File.exists?(path)
          refute File.exists?(Path.join(c.cwd, "calls.log"))
          assert effects == []
          assert saved.worker_input_unknown == [input["input_id"]]
          assert saved.managed_lineage.unavailable
          refute File.read!(c.trace) =~ Jason.encode!(action["outcome"])
      end

      expected_status = if boundary in [:current, :deny, :stale_token], do: "ok", else: "error"

      assert Enum.filter(events, &(&1["type"] == "turn_finished")) == [
               %{"type" => "turn_finished", "status" => expected_status}
             ]
    end

    assert Enum.count(events, &(&1["type"] == "request_admitted")) == 0

    dependencies =
      Path.join(c.root, "nested-approval-dependencies.json") |> File.read!() |> Jason.decode!()

    assert input["dependencies_sha256"] == JSON.digest(dependencies)
    trace = File.read!(c.trace)
    if boundary != :owner_loss, do: assert(:ok = Session.close_confirmed(pid))
    journal = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(journal)
    resumed = start(c, %{approval: :ask, approval_origin: :interactive, headless: false}, id)
    assert Session.info(resumed).phase == :idle
    assert :sys.get_state(resumed).messages == saved.messages

    assert :sys.get_state(resumed).managed_lineage.unavailable ==
             saved.managed_lineage.unavailable

    assert_idle_resume_journal(journal, before, id)
    assert File.read!(c.trace) == trace
    assert :ok = Session.close_confirmed(resumed)

    assert {:ok, %{"release_claim" => "signed_release_claim"}} =
             Session.Saved.inspect_saved(c.dir, id)

    if boundary == :current do
      assert File.read!(path) == marker
      if kind == :mcp, do: assert(File.read!(Path.join(c.cwd, "calls.log")) == "write_note\n")
    else
      refute File.exists?(path)
    end
  end

  defp native_nested_channel(_, 0), do: flunk("native operator channel did not start")

  defp native_nested_channel(pid, remaining) do
    if :sys.get_state(pid).operator_channel == nil do
      Process.sleep(10)
      native_nested_channel(pid, remaining - 1)
    end
  end

  for kind <- [:model, :decision, :embedding], boundary <- [:current, :deny, :root_change] do
    @tag native_inference_approval: true, registered_main: true, managed_helper: true
    @tag managed_decision: kind == :decision,
         managed_embedding: kind == :embedding,
         native_inference_boundary: boundary
    @tag native_root_approval:
           "helper_" <>
             to_string(kind) <> if(boundary == :current, do: "", else: "_" <> to_string(boundary)),
         timeout: 90_000
    test "native approval of a managed #{kind} helper preserves #{boundary} dispatch and recovery",
         c do
      if @native_root_approval,
        do: native_inference_approval(c, unquote(kind), unquote(boundary)),
        else: native_root_terminal("helper_#{unquote(kind)}", unquote(boundary))
    end
  end

  defp native_inference_approval(c, kind, boundary) do
    {operation, profile} =
      case kind do
        :decision -> {"decision.create", "advice"}
        :model -> {"model.complete", "extract"}
        :embedding -> {"embedding.create", "embed"}
      end

    pid = start(c, %{approval: :ask, approval_origin: :interactive, headless: false})
    id = Session.info(pid).id

    watcher =
      Task.async(fn ->
        await_marker(Path.join(c.root, "managed-approval-input-ready"), "ready", 1500)
        state = :sys.get_state(pid)
        assert state.phase == :managed_approval and state.share_barrier.phase == :review_input
        spec = state.managed_approval
        assert spec.previous_phase == :tool
        assert spec.input["kind"] == "extension.action.approval"
        assert spec.arguments["request"]["op"] == operation
        assert spec.arguments["request"]["profile"] == profile

        helper_input =
          if kind == :embedding,
            do: hd(spec.arguments["request"]["inputs"]),
            else: spec.arguments["request"]["input"]

        assert helper_input =~ "generation"
        assert spec.arguments["destination"]["origin"] == c.config.base_url
        assert spec.dependencies != [] and Enum.all?(spec.dependencies, &(&1["version"] == 3))
        assert Session.ManagedApproval.current?(state, spec.input)
        assert length(Agent.get(c.provider_requests, & &1)) == 1
        assert {:error, :session_share_frozen} = Session.approve(pid, spec.id, true)

        File.write!(
          Path.join(c.root, "native-helper-dependencies.json"),
          Jason.encode!(spec.dependencies)
        )

        if boundary == :root_change, do: native_root_boundary(c, pid, "helper_#{kind}", boundary)
        File.write!(Path.join(c.root, "managed-approval-control-checked"), "checked")
        native_root_idle(pid, 1500)
        File.write!(Path.join(c.root, "managed-approval-exit-ready"), "ready")
        File.write!(Path.join(c.root, "native-helper-checked"), "checked")
      end)

    try do
      IO.puts("IPSE_MANAGED_APPROVAL_CLI_READY")

      assert 0 ==
               Ipse.CLI.Terminal.interact(
                 pid,
                 Process.monitor(pid),
                 true,
                 "Use the synthetic managed observation in the selected #{kind} helper.",
                 c.cwd
               )

      await_marker(Path.join(c.root, "native-helper-checked"), "checked", 100)
      Process.demonitor(watcher.ref, [:flush])
      monitor = Process.monitor(watcher.pid)
      assert_receive {:DOWN, ^monitor, :process, _, reason}, 1000
      assert reason in [:normal, :noproc]
      assert {:ok, events} = Journal.load(c.dir, id)

      [action] =
        Enum.filter(
          events,
          &(&1["type"] == "extension_action_result" and get_in(&1, ["request", "op"]) == operation)
        )

      inputs = Enum.filter(events, &(&1["type"] == "worker_input_intent"))
      assert [read_input, result_input] = inputs

      dependencies =
        Path.join(c.root, "native-helper-dependencies.json") |> File.read!() |> Jason.decode!()

      assert Enum.all?(inputs, &(&1["dependencies_sha256"] == JSON.digest(dependencies)))

      assert result_input["payload_sha256"] ==
               JSON.digest([Ipse.Extension.Actions.resume(action)])

      admissions = Enum.filter(events, &(&1["type"] == "request_admitted"))
      finishes = Enum.filter(events, &(&1["type"] == "request_finished"))
      phases = for e <- events, e["type"] == "inference_dispatch_intent", do: e["phase"]
      trace = File.read!(c.trace)
      assert {:ok, saved} = Session.Saved.restore(events, id)

      case boundary do
        :current ->
          assert action["approval"] == "approved" and action["outcome"]["status"] == "ok"
          assert phases == ["model", operation, "model"]
          assert length(admissions) == 3 and length(finishes) == 3

          assert Enum.all?(
                   finishes,
                   &(&1["outcome"] == "completed" and &1["finality"] == "final")
                 )

          assert trace =~ Jason.encode!(action["outcome"])
          assert saved.worker_input_unknown == []
          refute saved.managed_lineage.unavailable

          wire = c.provider_requests |> Agent.get(& &1) |> Enum.at(1)
          request = action["request"]

          case kind do
            :model ->
              assert wire["messages"] ==
                       Session.Context.helper_messages(request["instruction"], request["input"])

              assert wire["tools"] == []

            :decision ->
              assert {:ok, expected} =
                       Ipse.Provider.Decision.encode(
                         :system_one,
                         Ipse.Extension.DecisionCall.neutral(request),
                         "synthetic"
                       )

              assert wire == expected

            :embedding ->
              assert wire == %{
                       "model" => "synthetic",
                       "input" => request["inputs"],
                       "truncate" => false
                     }
          end

        :deny ->
          assert action["approval"] == "denied"
          assert action["outcome"] == %{"status" => "denied", "value" => %{}}
          assert phases == ["model", "model"]
          assert length(admissions) == 2 and length(finishes) == 2

          assert Enum.all?(
                   finishes,
                   &(&1["outcome"] == "completed" and &1["finality"] == "final")
                 )

          assert trace =~ Jason.encode!(action["outcome"])
          assert saved.worker_input_unknown == []
          refute saved.managed_lineage.unavailable

        :root_change ->
          assert action["approval"] == "approved" and action["outcome"]["status"] == "failed"
          assert phases == ["model"]
          assert [main, helper] = admissions
          assert helper["request_id"] == action["operation_id"]
          assert [main_finish, helper_finish] = finishes
          assert main_finish["request_id"] == main["request_id"]

          assert Map.take(main_finish, ~w(outcome finality)) == %{
                   "outcome" => "completed",
                   "finality" => "final"
                 }

          assert Map.take(helper_finish, ~w(request_id outcome finality)) == %{
                   "request_id" => helper["request_id"],
                   "outcome" => "failed",
                   "finality" => "partial"
                 }

          assert saved.worker_input_unknown == [result_input["input_id"]]
          assert saved.managed_lineage.unavailable
          refute trace =~ Jason.encode!(action["outcome"])
      end

      expected_status = if boundary == :root_change, do: "error", else: "ok"

      assert Enum.filter(events, &(&1["type"] == "turn_finished")) == [
               %{"type" => "turn_finished", "status" => expected_status}
             ]

      assert Enum.map(
               Enum.filter(events, &(&1["type"] == "worker_input_result")),
               &{&1["input_id"], &1["status"]}
             ) == [
               {read_input["input_id"], "delivered"},
               {result_input["input_id"],
                if(boundary == :root_change, do: "unknown", else: "delivered")}
             ]

      count =
        case boundary do
          :current -> 3
          :deny -> 2
          :root_change -> 1
        end

      assert length(Agent.get(c.provider_requests, & &1)) == count
      assert :ok = Session.close_confirmed(pid)
      journal = Path.join(c.dir, id <> ".jsonl")
      closed = File.read!(journal)
      resumed = start(c, %{approval: :ask, approval_origin: :interactive, headless: false}, id)
      assert Session.info(resumed).phase == :idle
      assert :sys.get_state(resumed).messages == saved.messages

      assert :sys.get_state(resumed).managed_lineage.unavailable ==
               saved.managed_lineage.unavailable

      assert_idle_resume_journal(journal, closed, id)
      assert File.read!(c.trace) == trace
      assert :ok = Session.close_confirmed(resumed)

      assert {:ok, %{"release_claim" => "signed_release_claim"}} =
               Session.Saved.inspect_saved(c.dir, id)

      assert length(Agent.get(c.provider_requests, & &1)) == count
    after
      Task.shutdown(c.provider_server, :brutal_kill)
    end
  end

  @tag :registered_capture_sequence
  @tag metadata_version: 3, registered_main: true, capture_write: true
  test "a newly reviewed legacy reader cannot expose an existing managed namespace", c do
    capture = start(c)
    assert :ok = Session.prompt(capture, "Synthetic café observation")
    assert_receive {:ipse, ^capture, {:done, :ok}}, 15_000
    assert :ok = Session.close_confirmed(capture)
    root = SemanticAdmission.collection_root(c.home)

    assert {:ok, snapshot} =
             Ipse.Extension.Collection.execute(
               root,
               c.namespace,
               %{"op" => "snapshot"},
               Ipse.Usage.id()
             )

    assert {:ok, page} =
             Ipse.Extension.Collection.scan_visible(
               root,
               c.namespace,
               %{
                 "op" => "scan",
                 "generation" => snapshot["generation"],
                 "after" => nil,
                 "limit" => 4
               },
               Ipse.Usage.id()
             )

    [record] = page["records"]
    assert record["value"]["text"] == "Synthetic café observation"
    assert length(Task.await(c.provider_server, 5000)) == 2
    c = legacy_reader(c)
    reader = start(c)

    assert :ok =
             Session.invoke_export(reader, :command, "ext__capture__inspect", %{
               "mode" => "legacy_get:" <> record["key"]
             })

    assert_receive {:ipse, ^reader, {:done, :ok}}, 10_000
    assert {:ok, events} = Journal.load(c.dir, Session.info(reader).id)
    result = Enum.find(events, &(&1["type"] == "extension_action_result"))

    assert result["outcome"] == %{
             "status" => "failed",
             "value" => %{"code" => "collection_consent_denied"}
           }

    refute Jason.encode!(result) =~ "Synthetic café observation"
    refute Enum.any?(events, &(&1["type"] == "managed_read_observed"))
    assert {:ok, _} = Session.restore_context(events)
  end

  test "a live legacy reader rechecks managed namespace conversion at each actual operation", c do
    c = legacy_reader(c)
    root = SemanticAdmission.collection_root(c.home)

    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               root,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [
                   %{
                     "key" => "legacy",
                     "expected_revision" => 0,
                     "value" => %{"text" => "ordinary legacy value"}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    reader = start(c)

    assert :ok =
             Session.invoke_export(reader, :command, "ext__capture__inspect", %{
               "mode" => "legacy_get:legacy"
             })

    assert_receive {:ipse, ^reader, {:done, :ok}}, 10_000
    assert {:ok, events} = Journal.load(c.dir, Session.info(reader).id)
    first = Enum.find(events, &(&1["type"] == "extension_action_result"))

    assert get_in(first, ["outcome", "value", "record", "value", "text"]) ==
             "ordinary legacy value"

    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               root,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 1,
                 "advance_floor" => false,
                 "changes" => [
                   %{
                     "key" => "host.validity.format",
                     "expected_revision" => 0,
                     "value" => %{"fixture" => "late protected-format introduction"}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    assert :ok =
             Session.invoke_export(reader, :command, "ext__capture__inspect", %{
               "mode" => "legacy_get:legacy"
             })

    assert_receive {:ipse, ^reader, {:done, :ok}}, 10_000
    assert {:ok, events} = Journal.load(c.dir, Session.info(reader).id)
    result = events |> Enum.filter(&(&1["type"] == "extension_action_result")) |> List.last()

    assert result["outcome"] == %{
             "status" => "failed",
             "value" => %{"code" => "collection_consent_denied"}
           }

    assert {:ok, _} = Session.restore_context(events)
  end

  defp legacy_reader(c) do
    assert {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    policy = snapshot["policy"]

    selection =
      policy["settings"]
      |> Map.drop(~w(version instance identity_sha256 constraints recipes activation))
      |> Map.merge(Map.take(policy, ~w(limits period_ms expires_at_ms headless)))
      |> Map.update!("effects", fn effects ->
        effects
        |> Enum.filter(&(&1["class"] == "collection.read"))
        |> Enum.map(&Map.take(&1, ~w(operation class outer_sha256 inner_op)))
      end)

    [entry] = c.config.extensions
    assert {:ok, policy} = SemanticConsent.prepare(c.binding, entry.identity, selection)
    assert policy["settings"]["version"] == 1

    assert {:ok, _} =
             Consent.replace(
               c.control,
               c.binding["project_id"],
               snapshot["epoch"],
               policy,
               System.system_time(:millisecond)
             )

    assert {:ok, selected} = Ipse.Config.Semantics.selection(policy)
    put_in(c, [:config, :semantic_selections], selected)
  end

  @tag :registered_capture_lifecycle
  @tag metadata_version: 3,
       registered_main: true,
       capture_write: true,
       registered_capture_count: 2
  test "explicit V3 activates only after actual first publication and resumes without replay",
       c do
    pid = start(c)
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    id = Session.info(pid).id
    {:ok, events} = Journal.load(c.dir, id)

    result =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "collection.managed")
      )

    assert result["outcome"]["status"] == "ok"
    assert result["effect_binding"]["version"] == 3
    assert result["effect_binding"]["metadata_version"] == 3
    assert result["outcome"]["value"]["normalization"]["version"] == 3

    state =
      c.home |> Path.join("project-identities/index.json") |> File.read!() |> Jason.decode!()

    entry = state["domain_keys"][c.binding["project_id"]]["namespaces"][c.namespace]
    assert entry["state"] == "active" and JSON.sha256?(entry["first_root_sha256"])
    assert entry["first_operation_id"] == result["operation_id"]
    assert :ok = Ipse.Extension.Actions.validate_events(events)
    assert :ok = Ipse.Extension.Invocation.validate_events(events)
    assert {:ok, _} = Session.restore_context(events)
    assert {:ok, _} = Session.Saved.restore(events, id)

    for changed <- [
          Map.delete(result["request"], "metadata_version"),
          Map.put(result["request"], "metadata_version", 2)
        ] do
      refute Ipse.Extension.ManagedCollectionCall.valid_binding?(
               result["effect_binding"],
               changed,
               hd(c.config.extensions).identity
             )
    end

    {:ok, ledger} = Consent.snapshot(c.control, c.binding["project_id"])
    operation = ledger["operations"][result["operation_id"]]
    assert operation["status"] == "settled"
    assert operation["actual"]["input_bytes"] < operation["reserved"]["input_bytes"]
    assert :ok = Session.close_confirmed(pid)
    path = Path.join(c.dir, id <> ".jsonl")
    closed = File.read!(path)
    before = File.read!(c.trace)
    resumed = start(c, %{}, id)
    assert Session.info(resumed).phase == :idle
    assert_idle_resume_journal(path, closed, id)
    assert :ok = Session.close_confirmed(resumed)
    assert File.read!(c.trace) == before

    next = start(c)
    assert :ok = Session.prompt(next, "Synthetic café observation")
    assert_receive {:ipse, ^next, {:done, :ok}}, 15_000
    {:ok, later} = Journal.load(c.dir, Session.info(next).id)

    follow_on =
      Enum.find(
        later,
        &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "collection.managed")
      )

    assert follow_on["outcome"]["status"] == "ok"
    assert follow_on["outcome"]["value"]["receipt"]["generation"] == 2
    assert {:ok, _} = Session.Saved.restore(later, Session.info(next).id)

    for captured <- [events, later] do
      assert Enum.count(captured, &(&1["type"] == "request_admitted")) == 2

      assert Enum.count(
               captured,
               &(&1["type"] == "request_finished" and &1["outcome"] == "completed" and
                   &1["finality"] == "final")
             ) == 2
    end

    assert :ok = Session.close_confirmed(next)
    assert length(Task.await(c.provider_server, 5000)) == 4

    state =
      c.home |> Path.join("project-identities/index.json") |> File.read!() |> Jason.decode!()

    assert state["domain_keys"][c.binding["project_id"]]["namespaces"][c.namespace] == entry
  end

  @tag :registered_capture_lifecycle
  @tag metadata_version: 3,
       registered_main: true,
       capture_write: true,
       registered_capture_count: 3
  test "saved-consent V3 publication refuses a full pending queue and settles its action", c do
    first = start(c)
    assert :ok = Session.prompt(first, "Synthetic café observation")
    assert_receive {:ipse, ^first, {:done, :ok}}, 15_000
    assert :ok = Session.close_confirmed(first)

    root = SemanticAdmission.collection_root(c.home)

    seed_pending(c, 62)

    below = start(c)
    assert :ok = Session.prompt(below, "Synthetic café observation")
    assert_receive {:ipse, ^below, {:done, :ok}}, 15_000
    assert {:ok, below_events} = Journal.load(c.dir, Session.info(below).id)

    below_result =
      Enum.find(below_events, fn event ->
        event["type"] == "extension_action_result" and
          event["request"]["op"] == "collection.managed"
      end)

    assert below_result["outcome"]["status"] == "ok"
    assert :ok = Session.close_confirmed(below)

    assert {:ok, before} =
             Ipse.Extension.Collection.execute(
               root,
               c.namespace,
               %{"op" => "snapshot"},
               Ipse.Usage.id()
             )

    before_witness = collection_witness(root, c.namespace)

    pid = start(c)
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    id = Session.info(pid).id
    assert {:ok, events} = Journal.load(c.dir, id)
    assert :ok = Ipse.Extension.Actions.validate_events(events)
    assert {:ok, _} = Session.restore_context(events)
    assert {:ok, _} = Session.Saved.restore(events, id)
    assert Enum.count(events, &(&1["type"] == "request_admitted")) == 2

    assert Enum.count(
             events,
             &(&1["type"] == "request_finished" and &1["outcome"] == "completed" and
                 &1["finality"] == "final")
           ) == 2

    result =
      Enum.find(events, fn event ->
        event["type"] == "extension_action_result" and
          event["request"]["op"] == "collection.managed"
      end)

    assert result["approval"] == "saved_consent"
    assert result["effect_binding"]["metadata_version"] == 3
    assert result["outcome"]["status"] == "failed"
    assert result["outcome"]["value"]["code"] == "collection_unavailable"

    assert {:ok, after_snapshot} =
             Ipse.Extension.Collection.execute(
               root,
               c.namespace,
               %{"op" => "snapshot"},
               Ipse.Usage.id()
             )

    assert after_snapshot == before
    assert collection_witness(root, c.namespace) == before_witness
    assert {:ok, ledger} = Consent.snapshot(c.control, c.binding["project_id"])
    assert ledger["operations"][result["operation_id"]]["status"] == "settled"
    assert :ok = Session.close_confirmed(pid)
    path = Path.join(c.dir, id <> ".jsonl")
    closed = File.read!(path)
    trace = File.read!(c.trace)
    resumed = start(c, %{}, id)
    assert Session.info(resumed).phase == :idle
    assert_idle_resume_journal(path, closed, id)
    assert :ok = Session.close_confirmed(resumed)
    assert File.read!(c.trace) == trace
    assert length(Task.await(c.provider_server, 5000)) == 6
  end

  test "legacy saved-consent publication refuses a full pending queue", c do
    first = start(c)
    assert :ok = Session.prompt(first, "Synthetic café observation")
    assert_receive {:ipse, ^first, {:done, :ok}}, 15_000
    assert :ok = Session.close_confirmed(first)
    seed_pending(c, 63)

    root = SemanticAdmission.collection_root(c.home)
    before = collection_witness(root, c.namespace)
    pid = start(c)
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    id = Session.info(pid).id
    assert {:ok, events} = Journal.load(c.dir, id)
    assert :ok = Ipse.Extension.Actions.validate_events(events)
    assert {:ok, _} = Session.restore_context(events)

    result =
      Enum.find(events, fn event ->
        event["type"] == "extension_action_result" and
          event["request"]["op"] == "collection.managed"
      end)

    assert result["approval"] == "saved_consent"
    assert result["effect_binding"]["version"] == 2

    assert result["outcome"] == %{
             "status" => "failed",
             "value" => %{"code" => "collection_unavailable"}
           }

    assert collection_witness(root, c.namespace) == before
    assert {:ok, ledger} = Consent.snapshot(c.control, c.binding["project_id"])
    assert ledger["operations"][result["operation_id"]]["status"] == "settled"
    assert :ok = Session.close_confirmed(pid)
    trace = File.read!(c.trace)
    resumed = start(c, %{}, id)
    assert :ok = Session.close_confirmed(resumed)
    assert File.read!(c.trace) == trace
  end

  @tag metadata_version: 3, registered_main: true, capture_write: true, registered_competing: true
  test "competing V3 saved-consent Sessions cannot both publish at 63 pending records", c do
    competing_pending(c)
  end

  test "competing legacy saved-consent Sessions cannot both publish at 63 pending records", c do
    competing_pending(c)
  end

  defp competing_pending(c) do
    first = start(c)
    assert :ok = Session.prompt(first, "Synthetic café observation")
    assert_receive {:ipse, ^first, {:done, :ok}}, 15_000
    assert :ok = Session.close_confirmed(first)
    setup_started = System.monotonic_time(:millisecond)
    seed_pending(c, 62)

    if c[:registered_competing],
      do:
        IO.puts(
          "COMPETING_PENDING_SETUP_MS=#{System.monotonic_time(:millisecond) - setup_started}"
        )

    left = start(c, %{fixture_mode: "barrier"})
    right = start(c, %{fixture_mode: "barrier"})
    assert :ok = Session.prompt(left, "Synthetic café observation")
    await_marker_count(c.trace, "barrier\n", 1, 1000)
    assert :ok = Session.prompt(right, "Synthetic café observation")
    await_marker_count(c.trace, "barrier\n", 2, 1000)
    File.write!(c.trace <> ".release", "go")

    outcomes =
      Map.new([left, right], fn pid ->
        assert_receive {:ipse, ^pid, {:done, outcome}}, 20_000
        {pid, outcome}
      end)

    unless c[:registered_competing], do: assert(Enum.all?(outcomes, fn {_, v} -> v == :ok end))

    results =
      for pid <- [left, right] do
        assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
        assert :ok = Ipse.Extension.Actions.validate_events(events)
        assert {:ok, _} = Session.restore_context(events)

        Enum.find(events, fn event ->
          event["type"] == "extension_action_result" and
            event["request"]["op"] == "collection.managed"
        end)
      end

    statuses = Enum.map(results, & &1["outcome"]["status"])
    assert Enum.all?(statuses, &(&1 in ["failed", "ok"]))
    assert Enum.count(statuses, &(&1 == "ok")) <= 1
    assert Enum.all?(results, &(&1["approval"] == "saved_consent"))
    assert {:ok, ledger} = Consent.snapshot(c.control, c.binding["project_id"])

    for result <- results do
      case ledger["operations"][result["operation_id"]] do
        nil -> assert result["outcome"]["status"] == "failed"
        operation -> assert operation["status"] == "settled"
      end
    end

    root = SemanticAdmission.collection_root(c.home)

    assert {:ok, snapshot} =
             Ipse.Extension.Collection.execute(
               root,
               c.namespace,
               %{"op" => "snapshot"},
               Ipse.Usage.id()
             )

    successes = Enum.count(statuses, &(&1 == "ok"))
    assert snapshot["generation"] == 9 + successes

    if c[:registered_competing] do
      assert successes == 1
      assert length(Task.await(c.provider_server, 5000)) == 5

      for {pid, result} <- Enum.zip([left, right], results) do
        id = Session.info(pid).id
        assert {:ok, events} = Journal.load(c.dir, id)

        if result["outcome"]["status"] == "ok" do
          assert outcomes[pid] == :ok
          assert Enum.count(events, &(&1["type"] == "request_admitted")) == 2

          refute Enum.any?(
                   events,
                   &(&1["type"] == "worker_input_result" and &1["status"] == "unknown")
                 )
        else
          # The winner changed the root read by both Workers. The known failed
          # action remains recorded; its next input cannot discard that old read.
          assert outcomes[pid] == :error
          assert result["outcome"]["value"]["code"] == "collection_consent_denied"
          assert Enum.count(events, &(&1["type"] == "request_admitted")) == 1

          assert Enum.any?(
                   events,
                   &(&1["type"] == "worker_input_result" and &1["status"] == "unknown")
                 )

          assert {:ok, saved} = Ipse.Session.Saved.restore(events, id)
          assert saved.managed_lineage.unavailable
        end

        assert :ok = Session.close_confirmed(pid)
        path = Path.join(c.dir, id <> ".jsonl")
        closed = File.read!(path)
        trace = File.read!(c.trace)
        resumed = start(c, %{}, id)
        assert Session.info(resumed).phase == :idle
        assert_idle_resume_journal(path, closed, id)
        assert :ok = Session.close_confirmed(resumed)
        assert File.read!(c.trace) == trace
      end
    end

    if successes == 0 do
      retry = start(c)
      assert :ok = Session.prompt(retry, "Synthetic café observation")
      assert_receive {:ipse, ^retry, {:done, :ok}}, 15_000
      assert {:ok, events} = Journal.load(c.dir, Session.info(retry).id)

      result =
        Enum.find(events, fn event ->
          event["type"] == "extension_action_result" and
            event["request"]["op"] == "collection.managed"
        end)

      assert result["outcome"]["status"] == "ok"
    end
  end

  defp seed_pending(c, count) do
    root = SemanticAdmission.collection_root(c.home)

    for batch <- 0..div(count - 1, 8) do
      size = min(8, count - batch * 8)

      changes =
        for offset <- 1..size do
          n = batch * 8 + offset
          key = "pending." <> (n |> Integer.to_string(16) |> String.pad_leading(64, "0"))
          %{"key" => key, "expected_revision" => 0, "value" => %{"synthetic" => n}}
        end

      assert {:ok, _} =
               Ipse.Extension.Collection.execute(
                 root,
                 c.namespace,
                 %{
                   "op" => "commit",
                   "expected_generation" => batch + 1,
                   "advance_floor" => false,
                   "changes" => changes
                 },
                 Ipse.Usage.id()
               )
    end
  end

  defp collection_witness(root, namespace) do
    assert {:ok, view} = Ipse.Extension.Collection.open_view(root, namespace)

    try do
      assert {:ok, result} = Ipse.Extension.Collection.view_read(view, %{"op" => "snapshot"})
      assert result["witness"]["root_state"] == "present"
      result["witness"]
    after
      assert :ok = Ipse.Extension.Collection.close_view(view)
    end
  end

  @tag metadata_version: 3
  test "V3 cannot initialize over an existing unsigned store or silently adopt V2 metadata", c do
    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => true,
                 "changes" => [
                   %{
                     "key" => "host.validity.anchor.00.0",
                     "expected_revision" => 0,
                     "value" => %{"version" => 2, "kind" => "anchor", "entries" => %{}}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    pid = start(c)
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
    {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    result =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "collection.managed")
      )

    assert result["outcome"]["status"] == "failed"

    state =
      c.home |> Path.join("project-identities/index.json") |> File.read!() |> Jason.decode!()

    assert get_in(state, ["domain_keys", c.binding["project_id"], "namespaces", c.namespace]) ==
             nil

    {:ok, ledger} = Consent.snapshot(c.control, c.binding["project_id"])
    assert ledger["operations"] == %{}
    assert collection_read(c, %{"op" => "snapshot"})["generation"] == 1
  end

  @tag :registered_capture_sequence
  @tag metadata_version: 3,
       registered_main: true,
       capture_write: true,
       registered_capture_count: 27
  @tag timeout: 180_000
  test "V3 actual Session publications validate a nonzero live split fence", c do
    {:ok, initial} = Consent.snapshot(c.control, c.binding["project_id"])

    policy =
      Map.put(
        initial["policy"],
        "limits",
        Map.merge(Consent.zero(), %{
          "operations" => 40,
          "input_bytes" => 2_000_000,
          "output_bytes" => 2_000_000
        })
      )

    assert {:ok, _} =
             Consent.replace(
               c.control,
               c.binding["project_id"],
               initial["epoch"],
               policy,
               System.system_time(:millisecond)
             )

    assert {:ok, selection} = Ipse.Config.Semantics.selection(policy)
    c = put_in(c, [:config, :semantic_selections], selection)

    nonzero? =
      Enum.reduce(1..27, false, fn generation, seen ->
        pid = start(c)
        assert :ok = Session.prompt(pid, "Synthetic café observation")
        assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
        {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

        result =
          Enum.find(
            events,
            &(&1["type"] == "extension_action_result" and
                &1["request"]["op"] == "collection.managed")
          )

        assert result["outcome"]["status"] == "ok"
        value = result["outcome"]["value"]
        assert value["receipt"]["generation"] == generation

        assert Ipse.Extension.ManagedCollectionCall.valid_outcome?(
                 result["request"],
                 "ok",
                 value,
                 result["operation_id"]
               )

        assert {:ok, _} = Session.restore_context(events)
        assert Enum.count(events, &(&1["type"] == "request_admitted")) == 2

        assert Enum.count(
                 events,
                 &(&1["type"] == "request_finished" and &1["outcome"] == "completed" and
                     &1["finality"] == "final")
               ) == 2

        id = Session.info(pid).id
        assert :ok = Session.close_confirmed(pid)

        path = Path.join(c.dir, id <> ".jsonl")
        closed = File.read!(path)
        trace = File.read!(c.trace)
        resumed = start(c, %{}, id)
        assert Session.info(resumed).phase == :idle
        assert_idle_resume_journal(path, closed, id)
        assert :ok = Session.close_confirmed(resumed)
        assert File.read!(c.trace) == trace

        seen or
          Enum.any?(value["normalization"]["metadata_changes"], fn extra ->
            String.starts_with?(extra["key"], "host.validity.l.") and
              extra["key"] !=
                Ipse.Extension.Collection.ManagedPages.page_key(
                  :live,
                  Ipse.Extension.Collection.ManagedPages.zero(:live)
                )
          end)
      end)

    assert nonzero?
    assert length(Task.await(c.provider_server, 5000)) == 54
    assert {:ok, final} = Consent.snapshot(c.control, c.binding["project_id"])
    assert map_size(final["operations"]) == 27

    assert Enum.all?(final["operations"], fn {_, operation} ->
             operation["status"] == "settled"
           end)

    snapshot = collection_read(c, %{"op" => "snapshot"})
    assert snapshot["generation"] == 27

    assert {:ok, page} =
             Ipse.Extension.Collection.scan_visible(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{
                 "op" => "scan",
                 "generation" => snapshot["generation"],
                 "after" => nil,
                 "limit" => 32
               },
               Ipse.Usage.id()
             )

    assert length(page["records"]) == 27
    assert page["next"] == nil
    assert Enum.all?(page["records"], &(&1["value"]["text"] == "Synthetic café observation"))

    sources =
      Enum.map(page["records"], fn record ->
        assert String.starts_with?(record["key"], "pending.")
        [source] = record["value"]["evidence"]["sources"]
        assert source["quote"] == record["value"]["text"]
        assert File.regular?(Path.join(c.dir, source["session_id"] <> ".jsonl"))
        source["session_id"]
      end)

    assert length(Enum.uniq(sources)) == 27
  end

  @tag publication_binding: true,
       metadata_version: 3,
       registered_main: true,
       capture_write: true
  test "headless protected capture journals exact outer and inner bindings and settles once", c do
    pid = start(c)
    assert :sys.get_state(pid).config.semantic_admission["status"] == "active"
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    id = Session.info(pid).id
    {:ok, events} = Journal.load(c.dir, id)
    assert :ok = Ipse.Extension.Invocation.validate_events(events)
    assert :ok = Ipse.Extension.Actions.validate_events(events)
    assert {:ok, _} = Session.restore_context(events)

    for mutate <- [
          fn event -> put_in(event, ["semantic_binding", "pin", "epoch"], 999) end,
          fn event ->
            put_in(event, ["semantic_binding", "descriptor_sha256"], JSON.sha256("changed"))
          end,
          fn event -> Map.put(event, "version", 1) end
        ] do
      changed =
        Enum.map(events, fn event ->
          if event["type"] == "extension_invocation_intent", do: mutate.(event), else: event
        end)

      assert {:error, _} = Session.restore_context(changed)
    end

    started = Enum.find(events, &(&1["type"] == "tool_started"))
    assert started["version"] == 2

    changed_start =
      Enum.map(events, fn event ->
        if event == started,
          do: put_in(event, ["semantic_binding", "pin", "epoch"], 999),
          else: event
      end)

    assert {:error, _} = Session.restore_context(changed_start)

    downgraded =
      Enum.map(events, fn event ->
        if Map.has_key?(event, "semantic_binding"),
          do: put_in(event, ["semantic_binding", "class"], "collection.read"),
          else: event
      end)

    assert {:error, _} = Session.restore_context(downgraded)
    [header | tail] = events

    changed_policy =
      put_in(header, ["metadata", "semantic_admission", "policy", "headless"], false)

    assert {:error, _} = Session.restore_context([changed_policy | tail])
    outer = Enum.find(events, &(&1["type"] == "extension_invocation_intent"))
    assert outer["version"] == 3 and outer["approval"] == "saved_consent"

    commit =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "request", "op"]) == "commit")
      )

    assert commit["outcome"]["status"] == "ok"
    assert commit["version"] == 3 and commit["approval"] == "saved_consent"
    assert commit["namespace"] == c.namespace
    assert commit["effect_binding"]["kind"] == "collection.managed"
    assert commit["effect_binding"]["version"] == 3
    assert commit["effect_binding"]["metadata_version"] == 3
    assert commit["outcome"]["value"]["normalization"]["version"] == 3
    assert commit["outcome"]["value"]["normalization"]["eligibility"] == "never_current"
    metadata = get_in(commit, ["outcome", "value", "normalization", "metadata_changes"])
    anchor_at = Enum.find_index(metadata, &String.starts_with?(&1["key"], "host.validity.a."))
    current_anchor = Enum.at(metadata, anchor_at)["key"]

    foreign_anchor =
      "host.validity.a." <>
        if(String.ends_with?(current_anchor, String.duplicate("0", 64)),
          do: String.duplicate("f", 64),
          else: String.duplicate("0", 64)
        )

    for changed <- [
          Map.put(commit, "version", 2),
          put_in(commit, ["effect_binding", "metadata_version"], 2),
          put_in(commit, ["effect_binding", "recipe_sha256"], JSON.sha256("different recipe")),
          put_in(commit, ["effect_binding", "request_sha256"], JSON.sha256("different original")),
          put_in(commit, ["outcome", "value", "normalization", "version"], 1),
          put_in(
            commit,
            [
              "outcome",
              "value",
              "normalization",
              "metadata_changes",
              Access.at(anchor_at),
              "key"
            ],
            foreign_anchor
          ),
          put_in(commit, ["outcome", "value", "normalization", "valid_until_ms"], nil),
          put_in(
            commit,
            ["outcome", "value", "receipt", "managed_binding_sha256"],
            JSON.sha256("foreign receipt")
          )
        ] do
      changed = Map.put(changed, "outcome_sha256", JSON.digest([changed["outcome"]]))
      refute Ipse.Extension.Actions.valid_result?(changed)

      assert {:error, _} =
               Session.restore_context(Enum.map(events, &if(&1 == commit, do: changed, else: &1)))
    end

    {:ok, current} =
      Ipse.Extension.Collection.execute(
        SemanticAdmission.collection_root(c.home),
        c.namespace,
        %{"op" => "snapshot"},
        Ipse.Usage.id()
      )

    assert current["generation"] == 1 and current["floor"] == 1

    assert {:ok, visible} =
             Ipse.Extension.Collection.scan_visible(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{"op" => "scan", "generation" => 1, "after" => nil, "limit" => 4},
               Ipse.Usage.id()
             )

    assert length(visible["records"]) == 1
    refute Enum.any?(visible["records"], &String.starts_with?(&1["key"], "host.validity."))

    legacy_outer =
      outer
      |> Map.delete("semantic_binding")
      |> Map.merge(%{"version" => 1, "approval" => "approved"})

    assert :ok = Ipse.Extension.Invocation.validate_intent(legacy_outer)

    assert {:error, _} =
             Ipse.Extension.Actions.intent(
               legacy_outer,
               commit["request"],
               1,
               "saved_consent",
               c.cwd,
               nil,
               nil,
               commit["effect_binding"]
             )

    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    assert map_size(snapshot["operations"]) == 1
    assert snapshot["operations"][commit["operation_id"]]["status"] == "settled"
    assert :ok = Session.close_confirmed(pid)
    resumed = start(c, %{}, id)
    assert :ok = Session.close_confirmed(resumed)
    assert File.read!(c.trace) |> String.split("entered\n") |> length() == 2
    assert [_, _] = Task.await(c.provider_server, 5000)
  end

  test "revoked outer permission refuses before worker entry", c do
    pid = start(c)
    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], snapshot["epoch"])
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    refute File.exists?(c.trace)
  end

  test "legacy active admission resumes inertly without adopting a new protected outer", c do
    pid = start(c)
    id = Session.info(pid).id
    assert :ok = Session.close_confirmed(pid)
    {:ok, [header | tail]} = Journal.load(c.dir, id)

    legacy =
      header["metadata"]["semantic_admission"] |> Map.delete("policy") |> Map.put("version", 1)

    header = put_in(header, ["metadata", "semantic_admission"], legacy)

    File.write!(
      Path.join(c.dir, id <> ".jsonl"),
      Enum.map_join([header | tail], "\n", &Jason.encode!/1) <> "\n"
    )

    resumed = start(c, %{}, id)
    assert :sys.get_state(resumed).config.semantic_admission["version"] == 1
    assert :ok = Session.prompt(resumed, "Synthetic café observation")
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 10_000
    refute File.exists?(c.trace)
  end

  for metadata_version <- [2, 3] do
    @tag metadata_version: metadata_version, legacy_origin: true
    test "legacy journal origin cannot publish managed metadata V#{metadata_version}", c do
      pid = start(c)
      id = Session.info(pid).id
      assert :ok = Session.close_confirmed(pid)
      assert {:ok, [header | tail]} = Journal.load(c.dir, id)

      # An explicitly constructed legacy fixture has history but no recorded
      # original file binding. Resume must not manufacture that authority.
      metadata =
        Map.drop(
          header["metadata"],
          ~w(source_origin_layout source_origin native_journal_layout release_receipt_layout session_lock_identity)
        )

      header = Map.put(header, "metadata", metadata)

      tail =
        Enum.reject(
          tail,
          &(&1["type"] in ~w(session_release_owner_started session_release_intent))
        )

      File.write!(
        Path.join(c.dir, id <> ".jsonl"),
        Enum.map_join([header | tail], "\n", &Jason.encode!/1) <> "\n"
      )

      assert {:ok, before} = Consent.snapshot(c.control, c.binding["project_id"])
      resumed = start(c, %{fixture_mode: "capture_unobserved"}, id)
      assert :ok = Session.prompt(resumed, "Synthetic café observation")
      expected = if c.metadata_version == 3, do: :ok, else: :error
      assert_receive {:ipse, ^resumed, {:done, ^expected}}, 15_000
      assert :ok = Session.close_confirmed(resumed)
      assert {:ok, ^before} = Consent.snapshot(c.control, c.binding["project_id"])
      assert {:ok, [saved_header | events]} = Journal.load(c.dir, id)
      refute Map.has_key?(saved_header["metadata"], "source_origin")

      commits =
        Enum.filter(events, fn event ->
          event["type"] == "extension_action_result" and
            get_in(event, ["request", "request", "op"]) == "commit"
        end)

      if c.metadata_version == 2 do
        assert commits == []

        refute Enum.any?(events, fn event ->
                 event["type"] == "extension_action_intent" and
                   get_in(event, ["request", "request", "op"]) == "commit"
               end)
      else
        assert [commit] = commits

        assert commit["outcome"] == %{
                 "status" => "failed",
                 "value" => %{"code" => "collection_consent_denied"}
               }

        assert commit["approval"] == "saved_consent"
      end

      assert {:ok, _} = Session.restore_context([saved_header | events])
      refute Enum.any?(events, &(&1["type"] == "managed_read_observed"))
      assert %{"generation" => 0, "floor" => 0} = collection_read(c, %{"op" => "snapshot"})

      path = Path.join(c.dir, id <> ".jsonl")
      closed = File.read!(path)
      trace = File.read!(c.trace)
      idle = start(c, %{}, id)
      assert Session.info(idle).phase == :idle
      assert File.read!(path) == closed
      assert :ok = Session.close_confirmed(idle)
      assert File.read!(c.trace) == trace
      assert {:ok, ^before} = Consent.snapshot(c.control, c.binding["project_id"])
      assert {:ok, %{"release_claim" => "unknown"}} = Ipse.Session.Saved.inspect_saved(c.dir, id)
    end
  end

  @tag legacy_origin: true,
       metadata_version: 3,
       registered_main: true,
       capture_write: true,
       registered_capture_mode: "capture_unobserved"
  test "a current source can publish a new V3 candidate without a prior managed snapshot", c do
    pid = start(c)
    id = Session.info(pid).id
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    assert :ok = Session.close_confirmed(pid)
    assert {:ok, [header | events]} = Journal.load(c.dir, id)
    assert is_map(header["metadata"]["source_origin"])

    [commit] =
      Enum.filter(events, fn event ->
        event["type"] == "extension_action_result" and
          get_in(event, ["request", "op"]) == "collection.managed"
      end)

    assert commit["approval"] == "saved_consent"
    assert commit["outcome"]["status"] == "ok"
    assert commit["outcome"]["value"]["normalization"]["version"] == 3
    refute Enum.any?(events, &(&1["type"] == "managed_read_observed"))
    assert {:ok, saved} = Ipse.Session.Saved.restore([header | events], id)
    assert {:ok, control} = Consent.snapshot(c.control, c.binding["project_id"])
    assert map_size(control["operations"]) == 1
    assert control["operations"][commit["operation_id"]]["status"] == "settled"
    assert %{"generation" => 1, "floor" => 1} = collection_read(c, %{"op" => "snapshot"})
    assert [_, _] = Task.await(c.provider_server, 5000)

    before = File.read!(c.trace)
    path = Path.join(c.dir, id <> ".jsonl")
    journal = File.read!(path)
    resumed = start(c, %{}, id)
    assert :sys.get_state(resumed).messages == saved.messages
    assert_idle_resume_journal(path, journal, id)
    assert :ok = Session.close_confirmed(resumed)
    assert File.read!(c.trace) == before
    assert {:ok, ^control} = Consent.snapshot(c.control, c.binding["project_id"])

    assert {:ok, %{"release_claim" => "signed_release_claim"}} =
             Ipse.Session.Saved.inspect_saved(c.dir, id)
  end

  test "the policy snapshot stays bounded and a low enclosing journal limit refuses before worker entry",
       c do
    pid = start(c)
    id = Session.info(pid).id
    {:ok, [header | _]} = Journal.load(c.dir, id)
    admission = header["metadata"]["semantic_admission"]
    assert admission["version"] == 2
    assert byte_size(Jason.encode!(admission)) <= 65_536
    assert {:error, _} = JSON.decode_unique(Jason.encode!(admission), 12)
    assert SemanticAdmission.valid?(admission, id)
    refute SemanticAdmission.valid?(put_in(admission, ["policy", "settings", "effects"], []), id)
    assert :ok = Session.close_confirmed(pid)
    config = Map.put(c.config, :journal, %{"max_record_bytes" => 4096})

    assert {:error, _} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, config: config, cwd: c.cwd, state_dir: c.dir, subscriber: self()}
             )

    refute File.exists?(c.trace)

    assert Ipse.Extension.validate(%{"payload" => String.duplicate("x", 8193)}) ==
             {:error, :invalid_extension_value}
  end

  @tag read_only_export: true, metadata_version: 3
  test "a read-only export enters headless planning but cannot publish or lend ordinary approval",
       c do
    read = start(c, %{execution_mode: :planning, fixture_export: "inspect", fixture_mode: "read"})
    assert :ok = Session.prompt(read, "Synthetic café observation")
    assert_receive {:ipse, ^read, {:done, :error}}, 10_000
    {:ok, events} = Journal.load(c.dir, Session.info(read).id)
    outer = Enum.find(events, &(&1["type"] == "extension_invocation_intent"))
    assert outer["semantic_binding"]["class"] == "collection.read"
    assert {:ok, _} = Session.restore_context(events)
    state = :sys.get_state(read)

    assert {:ok, dependencies} =
             Ipse.Session.ManagedLineage.dependencies(state.managed_lineage, state.messages)

    assert dependencies != [] and Enum.all?(dependencies, &(&1["version"] == 3))

    producers =
      Enum.map(state.managed_lineage.reference.occurrences, fn {_, occurrence} ->
        occurrence.producer["kind"]
      end)

    assert "collection.result" in producers
    refute "assistant" in producers
    assert {:ok, saved} = Ipse.Session.Saved.restore(events, state.id)

    [release] = Enum.filter(events, &(&1["type"] == "managed_output_release_intent"))
    [admitted] = Enum.filter(events, &(&1["type"] == "managed_output_release_result"))
    [cleanup] = Enum.filter(events, &(&1["type"] == "managed_output_release_cleanup"))
    assert admitted["decision"] == "current" and cleanup["status"] == "confirmed"
    release_at = Enum.find_index(events, &(&1 == release))
    admitted_at = Enum.find_index(events, &(&1 == admitted))
    assert release_at < admitted_at

    prefix = Enum.take_while(events, &(&1 != cleanup))
    assert {:ok, interrupted} = Ipse.Session.Saved.restore(prefix, state.id)

    assert List.last(interrupted.messages)["content"] |> Jason.decode!() |> Map.fetch!("status") ==
             "withheld"

    assert interrupted.managed_lineage.unavailable

    uncertain =
      Enum.map(events, fn event ->
        if event == cleanup, do: Map.put(event, "status", "unknown"), else: event
      end)

    assert {:ok, uncertain} = Ipse.Session.Saved.restore(uncertain, state.id)

    assert List.last(uncertain.messages)["content"] |> Jason.decode!() |> Map.fetch!("status") ==
             "withheld"

    assert uncertain.managed_lineage.unavailable

    for changed <- [
          Enum.reject(events, &(&1 == release)),
          Enum.reject(events, &(&1 == admitted)),
          Enum.reject(events, &(&1 == cleanup)),
          List.insert_at(events, admitted_at, admitted),
          List.replace_at(
            events,
            release_at,
            Map.put(release, "dependencies_sha256", JSON.sha256("foreign union"))
          ),
          List.replace_at(events, admitted_at, Map.put(admitted, "release_id", Ipse.Usage.id()))
        ] do
      case Ipse.Session.Saved.restore(changed, state.id) do
        {:error, _} ->
          :ok

        {:ok, reconstructed} ->
          assert {:error, :managed_lineage_unavailable} =
                   Ipse.Session.ManagedLineage.dependencies(
                     reconstructed.managed_lineage,
                     reconstructed.messages
                   )
      end
    end

    assert {:ok, ^dependencies} =
             Ipse.Session.ManagedLineage.dependencies(saved.managed_lineage, saved.messages)

    legacy =
      events
      |> Enum.reject(&(&1["type"] == "managed_read_observed"))
      |> Enum.map(fn
        %{"type" => "session", "metadata" => metadata} = event ->
          %{event | "metadata" => Map.delete(metadata, "managed_read_layout")}

        event ->
          event
      end)

    assert {:ok, old_saved} = Ipse.Session.Saved.restore(legacy, state.id)
    assert old_saved.messages == saved.messages
    assert old_saved.managed_lineage.unavailable

    assert {:error, :managed_lineage_unavailable} =
             Session.managed_dependencies(
               %{state | managed_lineage: old_saved.managed_lineage},
               "model"
             )

    upgraded =
      Enum.map(events, fn event ->
        if Map.has_key?(event, "semantic_binding"),
          do: put_in(event, ["semantic_binding", "class"], "collection.publish"),
          else: event
      end)

    assert {:error, _} = Session.restore_context(upgraded)
    assert :ok = Session.close_confirmed(read)

    publish = start(c, %{approval: :allow, approval_origin: :yes, fixture_export: "inspect"})
    assert :ok = Session.prompt(publish, "Synthetic café observation")
    assert_receive {:ipse, ^publish, {:done, :error}}, 10_000
    {:ok, events} = Journal.load(c.dir, Session.info(publish).id)

    commit =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "request", "op"]) == "commit")
      )

    assert commit["approval"] == "denied" and commit["outcome"]["status"] == "denied"
    assert {:ok, _} = Session.restore_context(events)
    assert :ok = Session.close_confirmed(publish)

    ordinary = start(c, %{approval: :allow, approval_origin: :yes})

    assert :ok =
             Session.invoke_export(ordinary, :command, "ext__capture__inspect", %{
               "mode" => "ordinary"
             })

    assert_receive {:ipse, ^ordinary, {:done, :ok}}, 10_000
    refute File.exists?(Path.join(c.cwd, "forbidden"))
    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    assert snapshot["operations"] == %{}
    assert %{"generation" => 0, "floor" => 0} = collection_read(c, %{"op" => "snapshot"})
  end

  @tag registered_main: true
  test "a registered native transport carries managed worker lineage into assistant output and replay",
       c do
    read = start(c, %{execution_mode: :planning, fixture_export: "inspect", fixture_mode: "read"})
    assert :ok = Session.prompt(read, "Synthetic registered read")
    assert_receive {:ipse, ^read, {:done, :ok}}, 10_000
    requests = Task.await(c.provider_server, 5000)
    assert length(requests) == 2
    [{_, first}, {_, second}] = requests
    refute Enum.any?(first["messages"], &(&1["role"] == "tool"))
    assert Enum.any?(second["messages"], &(&1["role"] == "tool"))
    state = :sys.get_state(read)

    assert {:ok, dependencies} =
             Ipse.Session.ManagedLineage.dependencies(state.managed_lineage, state.messages)

    assert dependencies != []

    producers =
      Enum.map(state.managed_lineage.reference.occurrences, fn {_, occurrence} ->
        occurrence.producer["kind"]
      end)

    assert "collection.result" in producers and
             Enum.any?(producers, &(&1 in ~w(assistant assistant.ollama_text)))

    assert {:ok, events} = Journal.load(c.dir, state.id)
    assert Enum.count(events, &(&1["type"] == "inference_dispatch_intent")) == 2
    assert {:ok, saved} = Ipse.Session.Saved.restore(events, state.id)

    assert {:ok, ^dependencies} =
             Ipse.Session.ManagedLineage.dependencies(saved.managed_lineage, saved.messages)

    assert :ok = Session.close_confirmed(read)
  end

  @tag registered_main: true, opaque_refusal: true
  test "a stale managed assistant with opaque continuation refuses before a third provider request",
       c do
    read = start(c, %{execution_mode: :planning, fixture_export: "inspect", fixture_mode: "read"})
    assert :ok = Session.prompt(read, "Synthetic opaque managed answer")
    assert_receive {:ipse, ^read, {:done, :ok}}, 10_000
    server = c.provider_server.pid
    assert_receive {:observed_provider_request, ^server, _}, 1000
    assert_receive {:observed_provider_request, ^server, _}, 1000
    state = :sys.get_state(read)

    assert Enum.any?(
             state.messages,
             &(&1["role"] == "assistant" and
                 get_in(&1, ["provider_data", "message", "thinking"]) ==
                   "synthetic opaque continuation canary")
           )

    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [
                   %{
                     "key" => "synthetic.changed",
                     "expected_revision" => 0,
                     "value" => %{"text" => "changed"}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    assert :ok = Session.prompt(read, "Use the previous managed answer")
    assert_receive {:ipse, ^read, {:done, :error}}, 10_000
    refute_receive {:observed_provider_request, ^server, _}, 200
    assert {:ok, events} = Journal.load(c.dir, state.id)
    assert Enum.count(events, &(&1["type"] == "inference_dispatch_intent")) == 2
    assert Enum.count(events, &(&1["type"] == "managed_preflight_intent")) == 2
    assert Enum.count(events, &(&1["type"] == "managed_preflight_result")) == 1
    assert {:ok, _} = Ipse.Session.Saved.restore(events, state.id)
    Task.shutdown(c.provider_server, :brutal_kill)
    assert :ok = Session.close_confirmed(read)
  end

  @tag registered_main: true, plain_stale: true
  test "a stale plain Ollama answer is withdrawn before the next provider request", c do
    read = start(c, %{execution_mode: :planning, fixture_export: "inspect", fixture_mode: "read"})
    assert :ok = Session.prompt(read, "Synthetic plain managed answer")
    assert_receive {:ipse, ^read, {:done, :ok}}, 10_000
    server = c.provider_server.pid
    assert_receive {:observed_provider_request, ^server, _}, 1000
    assert_receive {:observed_provider_request, ^server, _}, 1000
    state = :sys.get_state(read)

    assert Enum.any?(state.messages, fn message ->
             message["content"] == "Synthetic protected read complete." and
               Ipse.Session.DraftNative.plain_text_only?(message)
           end)

    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [
                   %{
                     "key" => "synthetic.changed",
                     "expected_revision" => 0,
                     "value" => %{"text" => "changed"}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    assert :ok = Session.prompt(read, "Use the previous managed answer")
    assert_receive {:observed_provider_request, ^server, request}, 10_000
    wire = Jason.encode!(request["messages"])
    assert wire =~ "Managed historical content withdrawn"
    refute wire =~ "Synthetic protected read complete."
    assert_receive {:ipse, ^read, {:done, :error}}, 10_000
    assert {:ok, events} = Journal.load(c.dir, state.id)
    assert Enum.count(events, &(&1["type"] == "inference_dispatch_intent")) == 3
    assert {:ok, _} = Ipse.Session.Saved.restore(events, state.id)
    Task.shutdown(c.provider_server, :brutal_kill)
    assert :ok = Session.close_confirmed(read)
  end

  @tag metadata_version: 3, registered_main: true, capture_write: true
  test "a self-writing V3 capture retains raw reads and binds its result to the authenticated successor",
       c do
    pid = start(c)
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    [_, {_, request}] = Task.await(c.provider_server, 5000)
    [tool] = Enum.filter(request["messages"], &(&1["role"] == "tool"))
    historical = Jason.decode!(tool["content"])
    assert historical["status"] == "ok"
    refute tool["content"] =~ "Synthetic café observation"
    state = :sys.get_state(pid)

    assert {:ok, [current]} =
             Ipse.Session.ManagedLineage.dependencies(state.managed_lineage, state.messages)

    assert current["version"] == 3 and current["collection"]["generation"] == 1

    assert {:ok, events} = Journal.load(c.dir, state.id)
    result = Enum.find(events, &(&1["type"] == "extension_invocation_result"))
    assert tool["content"] === result["text"]

    action =
      Enum.find(
        events,
        &(get_in(&1, ["request", "op"]) == "collection.managed" and
            &1["type"] == "extension_action_result")
      )

    [fact] = state.managed_lineage.write_facts[result["invocation_id"]]
    assert fact["operation_id"] == action["operation_id"]
    assert fact["action_sha256"] == JSON.digest([action])
    assert fact["generation"] == 1
    assert JSON.digest([historical["value"]["receipt"]]) == fact["receipt_sha256"]

    transition = Enum.find(events, &(&1["type"] == "worker_input_root_transition"))
    projection = transition["evidence"]

    assert projection["operation_id"] == fact["operation_id"]
    assert projection["own_action_sha256"] == fact["action_sha256"]
    assert projection["receipt_sha256"] == fact["receipt_sha256"]
    assert projection["fresh_dependency"] == current

    reads =
      for event <- events,
          event["type"] == "managed_read_observed",
          event["parent_invocation_id"] == result["invocation_id"],
          do: event["dependencies"]

    assert {:ok, old} = Ipse.Session.ManagedReference.union(reads)
    assert old != []
    assert Enum.all?(old, &(&1["version"] == 3 and &1["collection"]["generation"] == 0))

    input =
      Enum.find(
        events,
        &(&1["input_id"] == transition["input_id"] and
            &1["type"] == "worker_input_intent")
      )

    assert input["dependencies_sha256"] == JSON.digest(old)
    assert transition["intent_sha256"] == JSON.digest([input])

    assert {:ok, saved} = Ipse.Session.Saved.restore(events, state.id)
    assert saved.messages == state.messages
    assert saved.managed_reads.outputs[result["invocation_id"]] != []
    assert :ok = Session.close_confirmed(pid)
  end

  for role <- [:notify, :text, :feed, :notify_required, :text_required] do
    @tag :managed_sink_input
    @tag managed_sink_role: role
    test "ordinary #{role} private delivery retains its actual callback", c do
      pid =
        start(c, %{
          provider_module: OrdinaryDeliveryModel,
          approval: :allow,
          approval_origin: :yes
        })

      assert :ok = Session.prompt(pid, "Write the synthetic ordinary file, then answer.")
      assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000

      marker =
        if unquote(role) in [:text, :text_required],
          do: "Synthetic ordinary delivery answer.",
          else: "payload"

      await_marker(Path.join(c.root, "delivery.jsonl"), marker, 300)
      id = Session.info(pid).id

      if unquote(role) in [:notify, :notify_required, :feed],
        do: assert(:ok == Ipse.Test.ManagedDeliverySink.await_ack(c.dir, id, unquote(role)))

      assert :ok = Session.close_confirmed(pid)
      deliveries = Ipse.Test.ManagedDeliverySink.read(c.root)
      assert deliveries != []

      assert File.read!(Path.join(c.cwd, "ordinary-delivery.txt")) ==
               "SYNTHETIC_ORDINARY_DELIVERY"

      if unquote(role) in [:text, :text_required] do
        assert Enum.any?(
                 deliveries,
                 &(get_in(&1, ["payload", "frame", "text"]) ==
                     "Synthetic ordinary delivery answer.")
               )
      end

      assert {:ok, events} = Journal.load(c.dir, id)
      assert {:ok, _} = Session.Saved.restore(events, id)
    end

    @tag :managed_sink_input
    @tag managed_sink_role: role, registered_main: true, ordinary_effect: true
    test "managed #{role} private delivery refuses before its unqualified callback", c do
      pid = start(c, %{approval: :allow, approval_origin: :yes, headless: true})
      assert :ok = Session.prompt(pid, "Read the protected root and complete the synthetic work.")
      assert_receive {:ipse, ^pid, {:done, status}}, 15_000
      server = c.provider_server.pid
      assert_receive {:observed_provider_request, ^server, _}, 1000

      try do
        assert status ==
                 if(unquote(role) in [:text, :text_required, :notify_required],
                   do: :error,
                   else: :ok
                 )

        id = Session.info(pid).id
        assert :ok = Session.close_confirmed(pid)
        assert {:ok, events} = Journal.load(c.dir, id)
        assert Enum.any?(events, &(&1["type"] == "managed_read_observed"))
        deliveries = Ipse.Test.ManagedDeliverySink.read(c.root)

        if unquote(role) in [:text, :text_required] do
          refute_receive {:observed_provider_request, ^server, _}, 100
          refute Enum.any?(deliveries, &(get_in(&1, ["payload", "frame", "kind"]) == "text"))
          refute File.exists?(Path.join(c.cwd, "managed-output.txt"))
        else
          assert deliveries == []

          assert File.read!(Path.join(c.cwd, "managed-output.txt")) == "SYNTHETIC_MANAGED_WRITE"
          assert_receive {:observed_provider_request, ^server, _}, 1000
          assert_receive {:observed_provider_request, ^server, _}, 1000
          refute_receive {:observed_provider_request, ^server, _}, 100

          if unquote(role) in [:notify, :notify_required] do
            assert Enum.any?(
                     events,
                     &(&1["type"] == "extension_event_result" and &1["outcome"] == "not_started")
                   )
          else
            refute Enum.any?(events, &(&1["type"] == "extension_feed_delivery_intent"))

            assert Enum.any?(
                     events,
                     &(&1["type"] == "extension_feed_closed" and
                         &1["reason"] == "view_unavailable")
                   )
          end
        end

        assert {:ok, _} = Session.Saved.restore(events, id)
        before = File.read!(Path.join(c.dir, id <> ".jsonl"))
        trace = File.read!(c.trace)
        resumed = start(c, %{approval: :allow, approval_origin: :yes, headless: true}, id)
        assert Session.info(resumed).phase == :idle
        assert Ipse.Test.ManagedDeliverySink.read(c.root) == deliveries
        assert File.read!(c.trace) == trace

        if unquote(role) == :feed do
          after_resume = File.read!(Path.join(c.dir, id <> ".jsonl"))
          assert String.starts_with?(after_resume, before)

          suffix =
            binary_part(
              after_resume,
              byte_size(before),
              byte_size(after_resume) - byte_size(before)
            )

          assert [owner, epoch] =
                   suffix |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

          assert Session.ReleaseReceipt.valid_owner_marker?(owner, id)
          assert Session.RuntimeLifecycle.valid_record?(epoch)
          assert epoch["mode"] == "resume" and epoch["previous_state"] == "closed"
          closed = events |> Enum.filter(&(&1["type"] == "lifecycle_epoch_closed")) |> List.last()
          assert epoch["session_id"] == id and epoch["previous_epoch_id"] == closed["epoch_id"]
        else
          assert_idle_resume_journal(Path.join(c.dir, id <> ".jsonl"), before, id)
        end

        assert {:ok, resumed_events} = Journal.load(c.dir, id)
        assert {:ok, _} = Session.Saved.restore(resumed_events, id)
        assert :ok = Session.close_confirmed(resumed)
      after
        Task.shutdown(c.provider_server, :brutal_kill)
      end
    end
  end

  @tag :managed_sink_input
  @tag managed_sink_role: :text_required, registered_main: true, ordinary_registered_text: true
  test "a required text consumer acknowledges an ordinary registered model answer", c do
    pid = start(c)
    assert :ok = Session.prompt(pid, "Return the synthetic ordinary registered answer.")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    id = Session.info(pid).id
    assert :ok = Session.close_confirmed(pid)

    assert Enum.any?(
             Ipse.Test.ManagedDeliverySink.read(c.root),
             &(get_in(&1, ["payload", "frame", "text"]) == "Synthetic ordinary registered answer.")
           )

    assert [_] = Task.await(c.provider_server, 1000)
    assert {:ok, events} = Journal.load(c.dir, id)
    refute Enum.any?(events, &(&1["type"] == "managed_read_observed"))
    assert {:ok, _} = Session.Saved.restore(events, id)
  end

  for role <- [:notify_metadata, :feed_metadata] do
    @tag :managed_sink_input
    @tag managed_sink_role: role, registered_main: true, ordinary_effect: true
    test "managed #{role} delivery remains metadata only and acknowledged", c do
      pid = start(c, %{approval: :allow, approval_origin: :yes, headless: true})

      try do
        assert :ok =
                 Session.prompt(pid, "Read the protected root and complete the synthetic work.")

        assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
        await_marker(Path.join(c.root, "delivery.jsonl"), "payload", 300)
        id = Session.info(pid).id
        assert :ok == Ipse.Test.ManagedDeliverySink.await_ack(c.dir, id, unquote(role))
        assert :ok = Session.close_confirmed(pid)
        deliveries = Ipse.Test.ManagedDeliverySink.read(c.root)
        assert deliveries != []
        assert Enum.all?(deliveries, &(get_in(&1, ["payload", "event", "view"]) == "metadata"))
        refute inspect(deliveries) =~ "Synthetic ordinary tool complete."
        assert {:ok, events} = Journal.load(c.dir, id)
        assert {:ok, _} = Session.Saved.restore(events, id)
      after
        Task.shutdown(c.provider_server, :brutal_kill)
      end
    end
  end

  @tag :managed_presentation_input
  @tag private_presentation: true
  test "an ordinary answer still reaches its selected presentation callback", c do
    pid = start(c, %{provider_module: PresentationModel})
    assert :ok = Session.prompt(pid, "Return a synthetic ordinary answer.")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    assert Enum.any?(events, fn event ->
             event["type"] == "extension_transform_result" and
               event["stage"] == "transform.presentation" and
               event["input"] == "Synthetic ordinary answer." and
               event["output"] == "<answer>Synthetic ordinary answer.</answer>"
           end)

    assert {:ok, _} = Session.Saved.restore(events, Session.info(pid).id)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag :managed_presentation_input
  @tag private_presentation: true, registered_main: true
  test "managed answers refuse an unqualified presentation input before its Worker starts", c do
    pid = start(c)
    assert :ok = Session.prompt(pid, "Read the synthetic protected root and answer.")
    assert_receive {:ipse, ^pid, {:done, status}}, 15_000
    id = Session.info(pid).id
    assert {:ok, events} = Journal.load(c.dir, id)

    assert Enum.any?(events, &(&1["type"] == "managed_read_observed"))

    assert Enum.filter(events, fn event ->
             event["type"] in ~w(extension_transform_intent extension_transform_result) and
               event["stage"] == "transform.presentation"
           end) == []

    assert status == :error
    assert_receive {:ipse, ^pid, {:error, message}}, 50
    assert message =~ "Managed answers cannot enter this formatter."
    assert {:ok, saved} = Session.Saved.restore(events, id)
    assert saved.worker_input_unknown == []
    assert :ok = Session.close_confirmed(pid)
    before = File.read!(Path.join(c.dir, id <> ".jsonl"))
    trace = File.read!(c.trace)
    resumed = start(c, %{}, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(c.trace) == trace
    assert_idle_resume_journal(Path.join(c.dir, id <> ".jsonl"), before, id)
    assert :ok = Session.close_confirmed(resumed)
  end

  @tag :managed_output_boundary
  test "a root change during worker processing withholds the actual direct command payload", c do
    pid = start(c)

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__inspect", %{
               "mode" => "read_hold"
             })

    await_marker(c.trace, "read-held\n", 300)

    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [
                   %{"key" => "unrelated.changed", "expected_revision" => 0, "value" => %{}}
                 ]
               },
               Ipse.Usage.id()
             )

    File.write!(c.trace <> ".release", "go")
    assert_receive {:ipse, ^pid, {:extension_result, display}}, 10_000
    assert display["value"]["status"] == "withheld"
    refute Jason.encode!(display) =~ "SYNTHETIC_MANAGED_WORKER_TEXT"
    assert_receive {:ipse, ^pid, {:done, :error}}, 5000
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    assert Enum.any?(
             events,
             &(&1["type"] == "managed_output_release_result" and &1["decision"] == "withdrawn")
           )

    assert {:ok, saved} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
    assert saved.extension_state.last_display["value"]["status"] == "withheld"
    assert saved.managed_reads.outputs |> Map.values() |> Enum.any?(&(&1 != []))
  end

  @tag native_root_approval: "write", timeout: 90_000
  @tag registered_main: true, ordinary_effect: true
  test "current managed native write starts after approval and releases one bound result", c do
    native_root_approval(c, "write")
  end

  for boundary <- [:root_change, :revoke, :expiry, :owner_loss] do
    @tag native_root_approval: "write_#{boundary}", native_root_fault: true, timeout: 90_000
    @tag registered_main: true, ordinary_effect: true, wire_expiry: boundary == :expiry
    test "managed native write waiting on approval refuses #{boundary} without effect", c do
      native_root_approval(c, "write", unquote(boundary))
    end
  end

  @tag native_root_approval: "shell", timeout: 90_000
  @tag registered_main: true, ordinary_effect: true, managed_shell: true
  test "current managed shell admits the native spawn and releases one bound result", c do
    native_root_approval(c, "shell")
  end

  for boundary <- [:root_change, :revoke, :expiry, :owner_loss] do
    @tag native_root_approval: "shell_#{boundary}", native_root_fault: true, timeout: 90_000
    @tag registered_main: true,
         ordinary_effect: true,
         managed_shell: true,
         shell_pregrant_refusal: boundary != :owner_loss,
         wire_expiry: boundary == :expiry
    test "managed shell waiting on approval refuses #{boundary} before native spawn", c do
      native_root_approval(c, "shell", unquote(boundary))
    end
  end

  @tag native_root_approval: "shell_running_revoke", native_root_running: true, timeout: 90_000
  @tag registered_main: true,
       ordinary_effect: true,
       managed_shell: true,
       managed_shell_delay: true
  test "source revocation while a managed shell runs withholds its buffered result", c do
    native_root_approval(c, "shell", :running_revoke)
  end

  @tag native_root_approval: "shell_running_kill", native_root_running: true, timeout: 90_000
  @tag registered_main: true,
       ordinary_effect: true,
       managed_shell: true,
       managed_shell_delay: true
  test "managed shell owner loss after spawn stops the process group and resumes inertly", c do
    native_root_approval(c, "shell", :running_kill)
  end

  @tag :root_subscriber_refusal
  @tag registered_main: true, ordinary_effect: true, managed_mcp: true
  test "managed MCP approval arguments are withheld when source ownership cannot be displayed",
       c do
    pid = start(c, %{approval: :ask, approval_origin: :interactive, headless: false})
    assert :ok = Session.prompt(pid, "Use the synthetic managed observation in an MCP write.")

    assert_receive {:ipse, ^pid,
                    {:tool_result, "mcp__notes__write_note",
                     "Managed approval arguments cannot be displayed under current source ownership; no tool was started."}},
                   15_000

    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    refute_receive {:ipse, ^pid, {:approval, _, "mcp__notes__write_note", _}}, 50
    refute File.exists?(Path.join(c.cwd, "managed-mcp.txt"))
    refute File.exists?(Path.join(c.cwd, "calls.log"))
    id = Session.info(pid).id
    assert {:ok, events} = Journal.load(c.dir, id)
    refute Enum.any?(events, &(&1["type"] == "managed_tool_effect_admitted"))
    assert {:ok, _} = Session.Saved.restore(events, id)
    assert :ok = Session.close_confirmed(pid)
    journal = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(journal)
    resumed = start(c, %{approval: :ask, approval_origin: :interactive, headless: false}, id)
    assert_idle_resume_journal(journal, before, id)
    refute File.exists?(Path.join(c.cwd, "managed-mcp.txt"))
    refute File.exists?(Path.join(c.cwd, "calls.log"))
    refute_receive {:ipse, ^resumed, {:approval, _, "mcp__notes__write_note", _}}, 50
    assert :ok = Session.close_confirmed(resumed)
  end

  @tag native_root_approval: "mcp", native_root_mcp_boundary: true, timeout: 90_000
  @tag registered_main: true, ordinary_effect: true, managed_mcp: true
  test "current managed MCP call admits server start and its exact request", c do
    native_root_approval(c, "mcp")
  end

  for boundary <- [:root_change, :revoke, :expiry, :owner_loss] do
    @tag native_root_approval: "mcp_#{boundary}", native_root_fault: true, timeout: 90_000
    @tag registered_main: true,
         ordinary_effect: true,
         managed_mcp: true,
         wire_expiry: boundary == :expiry
    test "managed MCP call waiting on approval refuses #{boundary} without effect", c do
      native_root_approval(c, "mcp", unquote(boundary))
    end
  end

  @tag native_root_approval: "mcp_start_revoke", native_root_mcp_boundary: true, timeout: 90_000
  @tag registered_main: true, ordinary_effect: true, managed_mcp: true, managed_gate: true
  test "managed MCP request refuses revocation after admitted server start", c do
    native_root_approval(c, "mcp", :start_revoke)
  end

  @tag native_root_approval: "http",
       native_root_mcp_boundary: true,
       native_root_http: true,
       timeout: 90_000
  @tag registered_main: true, ordinary_effect: true, managed_mcp: true, managed_http: true
  test "current managed HTTP MCP call admits connection and exact request", c do
    native_root_approval(c, "http")
  end

  @tag native_root_approval: "http_start_revoke",
       native_root_mcp_boundary: true,
       native_root_http: true,
       timeout: 90_000
  @tag registered_main: true, ordinary_effect: true, managed_mcp: true, managed_http: true
  test "managed HTTP MCP request refuses revocation after admitted connection", c do
    native_root_approval(c, "http", :start_revoke)
  end

  for boundary <- [:revoke, :expiry] do
    @tag native_root_approval: "http_#{boundary}", native_root_prestart: true, timeout: 90_000
    @tag registered_main: true,
         ordinary_effect: true,
         managed_mcp: true,
         managed_http: true,
         managed_http_prestart: true,
         wire_expiry: boundary == :expiry
    test "managed HTTP MCP #{boundary} before approval opens no further connection", c do
      native_root_approval(c, "http", unquote(boundary))
    end
  end

  @tag native_root_approval: "http_lost_start", native_root_loss: true, timeout: 90_000
  @tag registered_main: true,
       ordinary_effect: true,
       managed_mcp: true,
       managed_http: true,
       managed_start_unknown: true
  test "lost HTTP initialization response preserves possible startup as unknown", c do
    native_root_approval(c, "http", :lost_start)
  end

  @tag native_root_approval: "http_held_loss", native_root_loss: true, timeout: 90_000
  @tag registered_main: true,
       ordinary_effect: true,
       managed_mcp: true,
       managed_http: true,
       managed_http_owner_loss: true
  test "managed HTTP owner loss closes a held effect socket without replay", c do
    native_root_approval(c, "http", :held_loss)
  end

  for loss <- [:session, :transport] do
    @tag nested_mcp: true,
         managed_mcp: true,
         managed_http: true,
         managed_mcp_tls: true,
         managed_mcp_tls_loss: loss
    test "managed HTTPS #{loss} loss closes the held effect socket without replay", c do
      pid = start(c, %{approval: :allow, approval_origin: :interactive, headless: false})
      id = Session.info(pid).id
      owner_ref = Process.monitor(pid)
      path = Path.join(c.cwd, "nested-mcp.txt")
      File.write!(Path.join(c.cwd, "managed-mcp-hold-call"), "hold")

      assert :ok =
               Session.invoke_export(pid, :command, "ext__capture__capture", %{
                 "mode" => "nested_mcp"
               })

      await_marker(Path.join(c.cwd, "managed-mcp-call-held"), "held", 500)
      assert File.read!(path) == "SYNTHETIC_NESTED_MCP"
      assert {:ok, before_loss} = Journal.load(c.dir, id)
      assert Enum.any?(before_loss, &(&1["type"] == "managed_read_observed"))

      assert Enum.any?(
               before_loss,
               &(&1["type"] == "managed_tool_effect_admitted" and
                   get_in(&1, ["binding", "kind"]) == "mcp.send")
             )

      if unquote(loss) == :session do
        Process.exit(pid, :kill)
        assert_receive {:DOWN, ^owner_ref, :process, ^pid, :killed}, 5000
      else
        [transport] = :sys.get_state(pid).mcp_resources |> Map.keys()
        transport_ref = Process.monitor(transport)
        Process.exit(transport, :kill)
        assert_receive {:DOWN, ^transport_ref, :process, ^transport, :killed}, 5000
        assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
        assert_receive {:DOWN, ^owner_ref, :process, ^pid, _}, 5000
      end

      await_marker(Path.join(c.cwd, "managed-mcp-call-closed"), "{:error, :closed}", 500)
      assert File.read!(Path.join(c.cwd, "calls.log")) == "write_note\n"
      assert {:ok, events} = Journal.load(c.dir, id)
      assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
      resumed = start(c, %{approval: :allow, approval_origin: :interactive, headless: false}, id)
      assert Session.info(resumed).phase == :idle
      assert File.read!(Path.join(c.cwd, "calls.log")) == "write_note\n"
      assert :ok = Session.close_confirmed(resumed)
    end
  end

  @tag nested_mcp: true,
       managed_mcp: true,
       managed_http: true,
       managed_mcp_tls: true,
       managed_mcp_tls_discovery_loss: true
  test "nested managed HTTPS discovery loss stays incomplete and does not replay", c do
    pid = start(c, %{approval: :allow, approval_origin: :interactive, headless: false})
    id = Session.info(pid).id
    owner_ref = Process.monitor(pid)
    File.write!(Path.join(c.cwd, "managed-mcp-drop-start"), "drop")

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__capture", %{
               "mode" => "nested_mcp"
             })

    assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
    assert_receive {:DOWN, ^owner_ref, :process, ^pid, _}, 5000
    assert File.read!(Path.join(c.cwd, "managed-mcp-start-received")) == "received"
    refute File.exists?(Path.join(c.cwd, "nested-mcp.txt"))
    refute File.exists?(Path.join(c.cwd, "calls.log"))
    assert {:ok, events} = Journal.load(c.dir, id)
    assert Enum.any?(events, &(&1["type"] == "managed_mcp_discovery_intent"))
    refute Enum.any?(events, &(&1["type"] == "managed_mcp_discovery_result"))

    assert Enum.any?(
             events,
             &(&1["type"] == "managed_tool_effect_admitted" and
                 get_in(&1, ["binding", "kind"]) == "mcp.discovery.start")
           )

    assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
    connections = File.read!(Path.join(c.cwd, "managed-mcp-connections.log"))
    resumed = start(c, %{approval: :allow, approval_origin: :interactive, headless: false}, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(Path.join(c.cwd, "managed-mcp-connections.log")) == connections
    assert :ok = Session.close_confirmed(resumed)
  end

  @tag nested_mcp: true,
       managed_mcp: true,
       managed_http: true,
       managed_mcp_tls: true,
       managed_mcp_tls_effect_drop: true
  test "nested managed HTTPS lost effect response remains unknown without replay", c do
    pid = start(c, %{approval: :allow, approval_origin: :interactive, headless: false})
    id = Session.info(pid).id
    owner_ref = Process.monitor(pid)
    File.write!(Path.join(c.cwd, "managed-mcp-drop-call"), "drop")

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__capture", %{
               "mode" => "nested_mcp"
             })

    assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
    assert_receive {:DOWN, ^owner_ref, :process, ^pid, _}, 5000
    assert File.read!(Path.join(c.cwd, "managed-mcp-call-dropped")) == "dropped"
    assert File.read!(Path.join(c.cwd, "nested-mcp.txt")) == "SYNTHETIC_NESTED_MCP"
    assert File.read!(Path.join(c.cwd, "calls.log")) == "write_note\n"
    assert {:ok, events} = Journal.load(c.dir, id)

    assert Enum.any?(
             events,
             &(&1["type"] == "managed_tool_effect_admitted" and
                 get_in(&1, ["binding", "kind"]) == "mcp.send")
           )

    assert {:ok, saved} = Ipse.Session.Saved.restore(events, id)

    assert saved.extension_state.unknown or is_map(saved.extension_state.action) or
             saved.managed_lineage.unavailable

    connections = File.read!(Path.join(c.cwd, "managed-mcp-connections.log"))
    resumed = start(c, %{approval: :allow, approval_origin: :interactive, headless: false}, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(Path.join(c.cwd, "managed-mcp-connections.log")) == connections
    assert File.read!(Path.join(c.cwd, "calls.log")) == "write_note\n"
    assert :ok = Session.close_confirmed(resumed)
  end

  @tag nested_mcp: true,
       managed_mcp: true,
       managed_http: true,
       managed_mcp_tls: true,
       managed_mcp_tls_untrusted: true
  test "nested managed HTTPS rejects an untrusted server without effect or replay", c do
    pid = start(c, %{approval: :allow, approval_origin: :interactive, headless: false})
    id = Session.info(pid).id
    owner_ref = Process.monitor(pid)
    :ok = :public_key.cacerts_load()

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__capture", %{
               "mode" => "nested_mcp"
             })

    assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
    assert_receive {:DOWN, ^owner_ref, :process, ^pid, _}, 5000
    refute File.exists?(Path.join(c.cwd, "nested-mcp.txt"))
    refute File.exists?(Path.join(c.cwd, "calls.log"))
    assert {:ok, events} = Journal.load(c.dir, id)
    assert Enum.any?(events, &(&1["type"] == "managed_mcp_discovery_intent"))
    refute Enum.any?(events, &(&1["type"] == "managed_mcp_discovery_result"))

    assert Enum.any?(
             events,
             &(&1["type"] == "managed_tool_effect_admitted" and
                 get_in(&1, ["binding", "kind"]) == "mcp.discovery.start")
           )

    assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
    resumed = start(c, %{approval: :allow, approval_origin: :interactive, headless: false}, id)
    assert Session.info(resumed).phase == :idle
    refute File.exists?(Path.join(c.cwd, "calls.log"))
    assert :ok = Session.close_confirmed(resumed)
  end

  @tag native_root_approval: "mcp_held_loss", native_root_loss: true, timeout: 90_000
  @tag registered_main: true,
       ordinary_effect: true,
       managed_mcp: true,
       managed_held: true,
       managed_stdio_owner_loss: true
  test "managed stdio owner loss stops a held server without replay", c do
    native_root_approval(c, "mcp", :held_loss)
  end

  defp await_os_process_exit(_, 0), do: flunk("synthetic MCP server remained alive")

  defp await_os_process_exit(pid, remaining) do
    case System.cmd("/bin/kill", ["-0", pid], stderr_to_stdout: true) do
      {_, 0} ->
        Process.sleep(10)
        await_os_process_exit(pid, remaining - 1)

      {_, _} ->
        :ok
    end
  end

  @tag native_root_approval: "mcp_pinned", native_root_prestart: true, timeout: 90_000
  @tag registered_main: true,
       ordinary_effect: true,
       managed_mcp: true,
       managed_helper_identity: true
  test "managed stdio uses the build-pinned helper despite an override", c do
    native_root_approval(c, "mcp_pinned")
  end

  defp managed_shell_arguments(c) do
    command =
      if c[:managed_shell_delay],
        do:
          "printf begun > shell-started; sleep 0.6; printf SYNTHETIC_MANAGED_SHELL; printf finished > managed-output.txt",
        else: "printf SYNTHETIC_MANAGED_SHELL > managed-output.txt"

    %{"command" => command, "timeout_ms" => 2000}
  end

  @tag registered_main: true, postjournal_expiry: true
  test "expiry during actual tool-message journal IO settles each call once and resumes withheld",
       c do
    pid = start(c, %{execution_mode: :planning})
    owner = self()
    writer = :sys.get_state(pid).journal_writer

    gate = fn
      _, {:in, {_, _, {:append, _, %{"type" => "managed_output_release_result"} = event}}}, _ ->
        event["deadline_ms"]

      deadline,
      {:in,
       {_, _, {:append, _, %{"type" => "message", "message" => %{"role" => "tool"} = message}}}},
      _
      when is_integer(deadline) ->
        send(owner, {:managed_tool_append_waiting, self(), deadline, message["tool_call_id"]})
        receive do: (:release_tool_append -> :released)

      state, _, _ ->
        state
    end

    assert :ok = :sys.install(writer, {gate, nil})
    assert :ok = Session.prompt(pid, "Synthetic post-journal tool expiry")
    await_marker(c.trace, "read-held\n", 300)

    :sys.replace_state(pid, fn state ->
      put_in(
        state.extension_output_clock.started_ms,
        System.monotonic_time(:millisecond) - 118_500
      )
    end)

    File.write!(c.trace <> ".release", "go")
    assert_receive {:managed_tool_append_waiting, ^writer, deadline, first_call}, 5000
    assert System.system_time(:millisecond) < deadline
    Process.sleep(max(deadline - System.system_time(:millisecond) + 10, 0))
    send(writer, :release_tool_append)
    assert_receive {:ipse, ^pid, {:done, :error}}, 5000
    refute_receive {:ipse, ^pid, {:tool_result, "ext__capture__inspect", _}}, 100
    state = :sys.get_state(pid)
    assert {:ok, events} = Journal.load(c.dir, state.id)

    tools =
      Enum.filter(
        events,
        &(&1["type"] == "message" and get_in(&1, ["message", "role"]) == "tool")
      )

    assert length(tools) == 2
    assert Enum.count(tools, &(get_in(&1, ["message", "tool_call_id"]) == first_call)) == 1
    assert get_in(List.last(tools), ["message", "ipse_tool_outcome", "status"]) == "not_started"
    [cleanup] = Enum.filter(events, &(&1["type"] == "managed_output_release_cleanup"))
    assert cleanup["status"] == "unknown"
    assert {:ok, saved} = Ipse.Session.Saved.restore(events, state.id)
    assert saved.messages == state.messages
    [first, _queued] = Enum.filter(saved.messages, &(&1["role"] == "tool"))
    assert Jason.decode!(first["content"])["status"] == "withheld"
    assert :ok = Session.close_confirmed(pid)
    Task.shutdown(c.provider_server, :brutal_kill)
  end

  @tag :managed_output_boundary
  test "revocation during worker processing withholds the actual direct command payload", c do
    pid = start(c)

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__inspect", %{
               "mode" => "read_hold"
             })

    await_marker(c.trace, "read-held\n", 300)
    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    assert {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], snapshot["epoch"])
    File.write!(c.trace <> ".release", "go")
    assert_receive {:ipse, ^pid, {:extension_result, display}}, 10_000
    assert display["value"]["status"] == "withheld"
    refute Jason.encode!(display) =~ "SYNTHETIC_MANAGED_WORKER_TEXT"
    assert_receive {:ipse, ^pid, {:done, :error}}, 5000
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
    assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
  end

  @tag :worker_input_capacity
  test "managed page-input capacity refuses before source begin when its full reservation cannot fit",
       c do
    pid = start(c, %{journal: %{"max_bytes" => 65_536}})

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__inspect", %{
               "mode" => "paged_read"
             })

    assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
    id = Session.info(pid).id
    assert {:ok, events} = Journal.load(c.dir, id)
    refute Enum.any?(events, &(&1["type"] in Ipse.Extension.ResultSource.types()))
    refute Enum.any?(events, &(&1["type"] == "journal_limit_reached"))
    state = :sys.get_state(pid)
    assert state.extension_output == nil
    writer = :sys.get_state(state.journal_writer)
    assert writer.reservations == %{}
    assert writer.reserved_bytes == 0 and writer.reserved_events == 0
    assert {:ok, saved} = Session.Saved.restore(events, id)
    assert saved.worker_input_unknown == []
    assert :ok = Session.close_confirmed(pid)
  end

  for dimension <- [:events, :bytes] do
    @tag :worker_input_capacity
    test "managed output reservation covers its page inputs with competing #{dimension} capacity",
         c do
      pid = start(c)
      id = Session.info(pid).id
      owner = self()
      monitor = Process.monitor(pid)
      IO.puts("WORKER_CAPACITY_ROOT=" <> c.root)

      hook = fn
        :reserved, _, _ ->
          :reserved

        _d, {:out, {:ok, %{"type" => "extension_output_begin"}}, _, state}, _ ->
          writer = :sys.get_state(state.journal_writer)

          capacity =
            if unquote(dimension) == :events do
              events = writer.limits["max_events"] - writer.count - writer.reserved_events - 1 - 8
              %{events: events, bytes: events * 3}
            else
              bytes =
                writer.limits["max_bytes"] - writer.offset - writer.reserved_bytes -
                  Journal.reserve_bytes() - 4096

              maximum = writer.limits["max_record_bytes"]
              %{bytes: bytes, events: div(bytes + maximum - 1, maximum)}
            end

          assert {:ok, token} = Journal.Writer.reserve(state.journal_writer, capacity)
          send(owner, {:output_competing_reservation, token, capacity})
          :reserved

        d, _, _ ->
          d
      end

      assert :ok = :sys.install(pid, {hook, nil})

      assert :ok =
               Session.invoke_export(pid, :command, "ext__capture__inspect", %{
                 "mode" => "paged_read"
               })

      assert_receive {:output_competing_reservation, token, capacity}, 10_000

      release = fn ->
        if Process.alive?(pid) do
          :sys.replace_state(pid, fn state ->
            assert :ok = Journal.Writer.release(state.journal_writer, token)
            state
          end)
        end
      end

      try do
        receive do
          {:ipse, ^pid, {:done, :ok}} ->
            :ok

          {:ipse, ^pid, {:done, status}} ->
            flunk("admitted output ended #{status}")

          {:DOWN, ^monitor, :process, ^pid, reason} ->
            flunk("admitted output lost journal capacity: #{inspect(reason)}")
        after
          15_000 -> flunk("admitted output did not complete")
        end

        assert_receive {:ipse, ^pid, {:extension_result, display}}, 1000

        assert {:ok, %{value: %{"items" => items}}} =
                 Session.materialize_result(pid, display["delivery"])

        assert length(items) == 4
        state = :sys.get_state(pid)
        writer = :sys.get_state(state.journal_writer)
        assert writer.reservations == %{token => capacity}
        assert {:ok, events} = Journal.load(c.dir, id)
        refute Enum.any?(events, &(&1["type"] == "journal_limit_reached"))
        assert {:ok, saved} = Session.Saved.restore(events, id)
        assert saved.worker_input_unknown == []
      after
        release.()
        Process.demonitor(monitor, [:flush])
      end

      assert :ok = Session.close_confirmed(pid)
      trace = File.read!(c.trace)
      before = File.read!(Path.join(c.dir, id <> ".jsonl"))
      resumed = start(c, %{}, id)
      assert Session.info(resumed).phase == :idle
      assert File.read!(c.trace) == trace
      assert_idle_resume_journal(Path.join(c.dir, id <> ".jsonl"), before, id)
      assert :ok = Session.close_confirmed(resumed)
    end
  end

  @tag :managed_output_boundary
  @tag :worker_input_boundary
  test "current managed paged command output becomes readable only after its causal release", c do
    pid = start(c)

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__inspect", %{
               "mode" => "paged_read"
             })

    assert_receive {:ipse, ^pid, {:extension_result, display}}, 10_000
    assert display["delivery"]["historical_receipt"] == true
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5000

    assert {:ok, %{value: %{"items" => items}}} =
             Session.materialize_result(pid, display["delivery"])

    assert length(items) == 4
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
    assert {:ok, saved} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
    assert saved.extension_state.last_display == display
    inputs = Enum.filter(events, &(&1["type"] == "worker_input_intent"))
    assert Enum.any?(inputs, &(&1["stage"] == "host.actions"))
    assert Enum.any?(inputs, &(&1["stage"] == "result.output"))

    assert inputs |> Enum.map(& &1["protocol_id"]) |> Enum.sort() ==
             Enum.map(inputs, & &1["protocol_id"])

    for input <- inputs do
      assert Enum.any?(events, fn result ->
               result["type"] == "worker_input_result" and result["status"] == "delivered" and
                 Ipse.Session.WorkerInput.bound_result?(result, input)
             end)
    end

    assert saved.worker_input_unknown == []

    for field <- ~w(parent_sha256 actions_sha256 payload_sha256 frame_sha256 dependencies_sha256) do
      bad =
        Enum.map(events, fn event ->
          if event === hd(inputs),
            do: Map.put(event, field, String.duplicate("0", 64)),
            else: event
        end)

      assert {:error, _} = Ipse.Session.Saved.restore(bad, Session.info(pid).id)
    end

    first_input = Enum.find_index(events, &(&1 === hd(inputs)))
    prefix = Enum.take(events, first_input + 1)
    assert {:ok, interrupted} = Ipse.Session.Saved.restore(prefix, Session.info(pid).id)
    assert interrupted.worker_input_unknown == [hd(inputs)["input_id"]]
    assert interrupted.managed_lineage.unavailable

    uncertain =
      Enum.map(events, fn event ->
        if event["type"] == "managed_output_release_cleanup",
          do: Map.put(event, "status", "unknown"),
          else: event
      end)

    assert {:ok, uncertain} = Ipse.Session.Saved.restore(uncertain, Session.info(pid).id)
    assert uncertain.extension_state.last_display["value"]["status"] == "withheld"

    refute Ipse.Extension.ResultSource.published?(
             uncertain.result_sources,
             Enum.find(events, &(&1["type"] == "extension_invocation_result"))
           )

    raw = Enum.find(events, &(&1["type"] == "extension_invocation_result"))
    assert Ipse.Extension.ResultSource.published?(saved.result_sources, raw)
    admission_at = Enum.find_index(events, &(&1["type"] == "managed_output_release_result"))
    assert {:ok, private} = Ipse.Extension.ResultSource.restore(Enum.take(events, admission_at))
    refute Ipse.Extension.ResultSource.published?(private, raw)
    assert {:error, _} = Ipse.Extension.ResultSource.readable_source(private, display["delivery"])
    cleanup_at = Enum.find_index(events, &(&1["type"] == "managed_output_release_cleanup"))
    assert {:ok, unconfirmed} = Ipse.Extension.ResultSource.restore(Enum.take(events, cleanup_at))
    refute Ipse.Extension.ResultSource.published?(unconfirmed, raw)

    assert {:error, _} =
             Ipse.Extension.ResultSource.readable_source(unconfirmed, display["delivery"])

    id = Session.info(pid).id
    assert :ok = Session.close_confirmed(pid)
    journal = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(journal)
    trace = File.read!(c.trace)
    resumed = start(c, %{}, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(c.trace) == trace
    assert_idle_resume_journal(journal, before, id)
    assert :ok = Session.close_confirmed(resumed)
  end

  @tag :worker_input_boundary
  test "revocation after the committed read prevents the actual next VM callback", c do
    pid = start(c)
    owner = self()

    gate = fn
      :released, _, _ ->
        :released

      _, {:in, {_, _, {:worker_input_select, _, "host.actions", _}}}, _ ->
        send(owner, {:worker_input_waiting, self()})
        receive do: (:release_worker_input -> :released)

      state, _, _ ->
        state
    end

    assert :ok = :sys.install(pid, {gate, nil})

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__inspect", %{"mode" => "read"})

    assert_receive {:worker_input_waiting, ^pid}, 5_000
    assert {:ok, policy} = Consent.snapshot(c.control, c.binding["project_id"])
    assert {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], policy["epoch"])
    send(pid, :release_worker_input)
    assert_receive {:ipse, ^pid, {:done, :error}}, 10_000
    refute_receive {:ipse, ^pid, {:extension_result, _}}, 50
    assert File.read!(c.trace) == "entered\n"
    id = Session.info(pid).id
    assert {:ok, events} = Journal.load(c.dir, id)

    assert Enum.any?(events, fn event ->
             event["type"] == "extension_action_result" and event["outcome"]["status"] == "ok" and
               get_in(event, ["request", "op"]) == "collection.call"
           end)

    [input] = Enum.filter(events, &(&1["type"] == "worker_input_intent"))
    [outcome] = Enum.filter(events, &(&1["type"] == "worker_input_result"))
    assert outcome["status"] == "unknown"
    assert Ipse.Session.WorkerInput.bound_result?(outcome, input)
    assert {:ok, saved} = Session.Saved.restore(events, id)
    assert saved.worker_input_unknown == [input["input_id"]]
    assert saved.managed_lineage.unavailable
    assert :ok = Session.close_confirmed(pid)
    journal = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(journal)
    resumed = start(c, %{}, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(c.trace) == "entered\n"
    assert_idle_resume_journal(journal, before, id)
    assert :ok = Session.close_confirmed(resumed)
  end

  @tag :managed_output_owner_loss
  test "owner loss during managed worker processing cannot release its payload", c do
    pid = start(c)

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__inspect", %{
               "mode" => "read_hold"
             })

    await_marker(c.trace, "read-held\n", 300)
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5000
    File.write!(c.trace <> ".release", "go")
    refute_receive {:ipse, ^pid, {:extension_result, _}}, 300
    refute File.read!(c.trace) =~ "read-returned\n"
  end

  defp native_root_approval(c, kind, boundary \\ :current) do
    if @native_root_approval,
      do: native_root_effect(c, kind, boundary),
      else: native_root_terminal(kind, boundary)
  end

  defp native_root_terminal(kind, boundary) do
    selection = if boundary == :current, do: kind, else: kind <> "_" <> Atom.to_string(boundary)

    scenario =
      cond do
        boundary == :owner_loss ->
          "save_managed_approval_owner_loss"

        kind in ~w(nested_mcp nested_native helper_model helper_decision helper_embedding) and
            boundary in [:deny, :stale_token, :cancel] ->
          "save_managed_approval_" <> to_string(boundary)

        true ->
          "save_managed_approval_root_" <> selection
      end

    root = Path.join(System.tmp_dir!(), "ipse-root-approval-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    IO.puts("NATIVE_ROOT_APPROVAL_ROOT=" <> root)
    driver = Path.join(root, "pty")

    assert {output, 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", driver],
               stderr_to_stdout: true
             )

    assert output == ""

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    assert {output, status} =
             System.cmd(
               driver,
               ["--assertion", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
                 paths ++
                 [
                   Path.expand("../../support/root_approval_cli.exs", __DIR__),
                   selection,
                   root,
                   scenario
                 ],
               stderr_to_stdout: true
             )

    assert status == 0, output
    assert output =~ "NATIVE_ROOT_APPROVAL_#{String.upcase(selection)}_PASSED"

    if boundary == :running_revoke do
      refute output =~ "← shell: Exit code: 0"
      assert output =~ "withheld"
    end
  end

  defp native_root_effect(c, "shell", boundary)
       when boundary in [:running_revoke, :running_kill] do
    lost? = boundary == :running_kill
    path = Path.join(c.cwd, "managed-output.txt")

    try do
      pid = start(c, %{approval: :ask, approval_origin: :interactive, headless: false})
      id = Session.info(pid).id
      refute File.exists?(path)

      {:ok, watcher} =
        Task.start(fn ->
          await_marker(Path.join(c.root, "managed-approval-input-ready"), "ready", 1500)
          state = :sys.get_state(pid)
          assert state.phase == :managed_approval and state.share_barrier.phase == :review_input
          assert state.managed_approval.arguments == managed_shell_arguments(c)
          assert state.managed_approval.dependencies != []
          assert Enum.all?(state.managed_approval.dependencies, &(&1["version"] == 3))
          assert {:error, _} = Session.approve(pid, make_ref(), true)
          refute File.exists?(path)

          File.write!(
            Path.join(c.root, "native-root-loss-dependencies.json"),
            Jason.encode!(state.managed_approval.dependencies)
          )

          File.write!(Path.join(c.root, "managed-approval-control-checked"), "checked")
          await_marker(Path.join(c.cwd, "shell-started"), "begun", 500)
          refute File.exists?(path)

          if lost? do
            task = :sys.get_state(pid).task.pid
            [{scope, _}] = Elixir.Registry.lookup(Ipse.Registry, {Session.Resources, task})

            [%{pid: effect}] =
              :sys.get_state(scope).resources
              |> Map.values()
              |> Enum.filter(&(&1.kind == :shell))

            {:links, links} = Process.info(effect, :links)
            [port] = Enum.filter(links, &is_port/1)
            {:os_pid, helper} = Port.info(port, :os_pid)
            direct = native_root_children(helper)
            assert length(direct) == 2

            [{_shell, children}] =
              for child <- direct,
                  descendants = native_root_children(child),
                  descendants != [],
                  do: {child, descendants}

            processes = [helper] ++ direct ++ children
            native_root_boundary(c, pid, "shell", :owner_loss)
            native_root_processes_stopped(processes, 500)
            Process.sleep(800)
            refute File.exists?(path)
          else
            native_root_boundary(c, pid, "shell", :revoke)
            native_root_idle(pid, 1500)
            File.write!(Path.join(c.root, "managed-approval-exit-ready"), "ready")
          end

          File.write!(Path.join(c.root, "native-root-checked"), "checked")
        end)

      IO.puts("IPSE_MANAGED_APPROVAL_CLI_READY")

      assert if(lost?, do: 1, else: 0) ==
               Ipse.CLI.Terminal.interact(
                 pid,
                 Process.monitor(pid),
                 true,
                 "Use the synthetic managed observation in the exact shell call.",
                 c.cwd
               )

      await_marker(Path.join(c.root, "native-root-checked"), "checked", 600)
      monitor = Process.monitor(watcher)
      assert_receive {:DOWN, ^monitor, :process, ^watcher, reason}, 1000
      assert reason in [:normal, :noproc]
      assert {:ok, events} = Journal.load(c.dir, id)

      assert [
               %{"name" => "ext__capture__inspect", "approval" => "saved_consent"},
               %{"name" => "shell", "approval" => "approved"}
             ] = Enum.filter(events, &(&1["type"] == "tool_started"))

      assert [admitted] = Enum.filter(events, &(&1["type"] == "managed_tool_effect_admitted"))
      assert admitted["binding"]["name"] == "shell"
      observed = Enum.filter(events, &(&1["type"] == "managed_tool_result_observed"))
      releases = Enum.filter(events, &(&1["type"] == "managed_tool_result_release"))

      if lost? do
        refute Process.alive?(pid)
        refute File.exists?(path)
        assert observed == [] and releases == []
        native_root_released(Path.join(c.dir, id <> ".lock"), 500)
      else
        assert File.read!(path) == "finished"
        assert [result] = observed
        assert get_in(result, ["message", "content"]) =~ "SYNTHETIC_MANAGED_SHELL"
        assert [%{"decision" => "withdrawn"}] = releases

        assert [%{"status" => "confirmed"}] =
                 Enum.filter(events, fn event ->
                   event["type"] == "managed_tool_effect_cleanup" and
                     event["effect_id"] == admitted["effect_id"]
                 end)
      end

      assert {:ok, saved} = Session.Saved.restore(events, id)

      if !lost? do
        assert saved.messages == :sys.get_state(pid).messages
        assert List.last(saved.messages)["content"] =~ "withheld"
        assert :ok = Session.close_confirmed(pid)
      end

      unconfirmed? = native_root_loss_lineage(c, saved)
      assert Enum.count(events, &(&1["type"] == "request_admitted")) == 2

      assert Enum.count(
               events,
               &(&1["type"] == "request_finished" and &1["outcome"] == "completed" and
                   &1["finality"] == "final")
             ) == 2

      assert length(Agent.get(c.provider_requests, & &1)) == 2
      journal = Path.join(c.dir, id <> ".jsonl")
      closed = File.read!(journal)
      resumed = start(c, %{approval: :ask, approval_origin: :interactive, headless: false}, id)
      assert Session.info(resumed).phase == :idle
      assert :sys.get_state(resumed).messages == saved.messages
      assert :sys.get_state(resumed).managed_lineage.unavailable == unconfirmed?
      assert_idle_resume_journal(journal, closed, id)
      assert :ok = Session.close_confirmed(resumed)

      assert {:ok, %{"release_claim" => "signed_release_claim"}} =
               Session.Saved.inspect_saved(c.dir, id)

      if lost?, do: refute(File.exists?(path)), else: assert(File.read!(path) == "finished")
      assert length(Agent.get(c.provider_requests, & &1)) == 2
    after
      Task.shutdown(c.provider_server, :brutal_kill)
    end
  end

  defp native_root_effect(c, kind, boundary)
       when kind in ["mcp", "http"] and boundary in [:lost_start, :held_loss] do
    lost_start? = boundary == :lost_start
    path = Path.join(c.cwd, "managed-mcp.txt")

    try do
      pid = start(c, %{approval: :ask, approval_origin: :interactive, headless: false})
      id = Session.info(pid).id
      refute File.exists?(path)

      {:ok, watcher} =
        Task.start(fn ->
          await_marker(Path.join(c.root, "managed-approval-input-ready"), "ready", 1500)
          state = :sys.get_state(pid)
          assert state.phase == :managed_approval and state.share_barrier.phase == :review_input

          assert state.managed_approval.arguments == %{
                   "path" => "managed-mcp.txt",
                   "content" => "SYNTHETIC_MANAGED_MCP"
                 }

          assert state.managed_approval.dependencies != []
          assert Enum.all?(state.managed_approval.dependencies, &(&1["version"] == 3))
          assert {:error, _} = Session.approve(pid, make_ref(), true)
          refute File.exists?(path)

          File.write!(
            Path.join(c.root, "native-root-loss-dependencies.json"),
            Jason.encode!(state.managed_approval.dependencies)
          )

          owner_ref = Process.monitor(pid)

          if kind == "http" do
            flag = if lost_start?, do: "managed-mcp-drop-start", else: "managed-mcp-hold-call"
            File.write!(Path.join(c.cwd, flag), if(lost_start?, do: "drop", else: "hold"))
          end

          File.write!(Path.join(c.root, "managed-approval-control-checked"), "checked")

          if lost_start? do
            await_marker(Path.join(c.cwd, "managed-mcp-start-received"), "received", 500)
            assert_receive {:DOWN, ^owner_ref, :process, ^pid, _}, 15_000
            refute File.exists?(path)
            refute File.exists?(Path.join(c.cwd, "calls.log"))
          else
            ready =
              Path.join(
                c.cwd,
                if(kind == "http", do: "managed-mcp-call-held", else: "disconnect-ready")
              )

            await_marker(ready, if(kind == "http", do: "held", else: ""), 500)
            assert File.read!(path) == "SYNTHETIC_MANAGED_MCP"
            assert File.read!(Path.join(c.cwd, "calls.log")) == "write_note\n"
            [transport] = :sys.get_state(pid).mcp_resources |> Map.keys()
            transport_ref = Process.monitor(transport)
            server_pid = if kind == "mcp", do: File.read!(ready)
            if server_pid, do: assert(Regex.match?(~r/\A[0-9]+\z/, server_pid))
            assert {:ok, started} = Journal.load(c.dir, id)

            assert Enum.map(
                     Enum.filter(started, &(&1["type"] == "managed_tool_effect_admitted")),
                     &get_in(&1, ["binding", "kind"])
                   ) == ["mcp.start", "mcp.send"]

            Process.exit(pid, :kill)
            assert_receive {:DOWN, ^owner_ref, :process, ^pid, :killed}, 5000
            assert_receive {:DOWN, ^transport_ref, :process, ^transport, _}, 5000

            if kind == "http",
              do:
                await_marker(
                  Path.join(c.cwd, "managed-mcp-call-closed"),
                  "{:error, :closed}",
                  500
                ),
              else: await_os_process_exit(server_pid, 500)
          end

          File.write!(Path.join(c.root, "native-root-checked"), "checked")
        end)

      IO.puts("IPSE_MANAGED_APPROVAL_CLI_READY")

      assert 1 ==
               Ipse.CLI.Terminal.interact(
                 pid,
                 Process.monitor(pid),
                 true,
                 "Use the synthetic managed observation in an MCP write.",
                 c.cwd
               )

      await_marker(Path.join(c.root, "native-root-checked"), "checked", 600)
      monitor = Process.monitor(watcher)
      assert_receive {:DOWN, ^monitor, :process, ^watcher, reason}, 1000
      assert reason in [:normal, :noproc]
      refute Process.alive?(pid)
      native_root_released(Path.join(c.dir, id <> ".lock"), 500)
      assert {:ok, events} = Journal.load(c.dir, id)

      assert [
               %{"name" => "ext__capture__inspect", "approval" => "saved_consent"},
               %{"name" => "mcp__notes__write_note", "approval" => "approved"}
             ] = Enum.filter(events, &(&1["type"] == "tool_started"))

      kinds =
        events
        |> Enum.filter(&(&1["type"] == "managed_tool_effect_admitted"))
        |> Enum.map(&get_in(&1, ["binding", "kind"]))

      assert kinds == if(lost_start?, do: ["mcp.start"], else: ["mcp.start", "mcp.send"])

      if lost_start? do
        assert File.read!(Path.join(c.cwd, "managed-mcp-start-received")) == "received"
        refute File.exists?(path)
        refute File.exists?(Path.join(c.cwd, "calls.log"))

        assert Enum.any?(
                 events,
                 &(get_in(&1, ["message", "ipse_tool_outcome", "status"]) == "unknown")
               )
      else
        assert File.read!(path) == "SYNTHETIC_MANAGED_MCP"
        assert File.read!(Path.join(c.cwd, "calls.log")) == "write_note\n"
        refute Enum.any?(events, &(&1["type"] == "managed_tool_result_observed"))
        refute Enum.any?(events, &(&1["type"] == "managed_tool_result_release"))
      end

      assert {:ok, saved} = Session.Saved.restore(events, id)

      unconfirmed? = native_root_loss_lineage(c, saved)

      assert Enum.count(events, &(&1["type"] == "request_admitted")) == 2

      assert Enum.count(
               events,
               &(&1["type"] == "request_finished" and &1["outcome"] == "completed" and
                   &1["finality"] == "final")
             ) == 2

      assert length(Agent.get(c.provider_requests, & &1)) == 2

      connections =
        if kind == "http", do: File.read!(Path.join(c.cwd, "managed-mcp-connections.log"))

      journal = Path.join(c.dir, id <> ".jsonl")
      closed = File.read!(journal)
      resumed = start(c, %{approval: :ask, approval_origin: :interactive, headless: false}, id)
      assert Session.info(resumed).phase == :idle
      assert :sys.get_state(resumed).messages == saved.messages
      assert :sys.get_state(resumed).managed_lineage.unavailable == unconfirmed?
      assert_idle_resume_journal(journal, closed, id)
      assert :ok = Session.close_confirmed(resumed)

      assert {:ok, %{"release_claim" => "signed_release_claim"}} =
               Session.Saved.inspect_saved(c.dir, id)

      if lost_start? do
        refute File.exists?(path)
        refute File.exists?(Path.join(c.cwd, "calls.log"))
      else
        assert File.read!(path) == "SYNTHETIC_MANAGED_MCP"
        assert File.read!(Path.join(c.cwd, "calls.log")) == "write_note\n"
      end

      assert length(Agent.get(c.provider_requests, & &1)) == 2

      if kind == "http" do
        assert File.read!(Path.join(c.cwd, "managed-mcp-connections.log")) == connections
      end
    after
      Task.shutdown(c.provider_server, :brutal_kill)
    end
  end

  defp native_root_effect(c, kind, boundary) do
    {tool, relative, content, arguments} =
      case kind do
        "write" ->
          {"write", "managed-output.txt", "SYNTHETIC_MANAGED_WRITE",
           %{"path" => "managed-output.txt", "content" => "SYNTHETIC_MANAGED_WRITE"}}

        "shell" ->
          {"shell", "managed-output.txt", "SYNTHETIC_MANAGED_SHELL", managed_shell_arguments(c)}

        protocol when protocol in ["mcp", "http", "mcp_pinned"] ->
          {"mcp__notes__write_note", "managed-mcp.txt", "SYNTHETIC_MANAGED_MCP",
           %{"path" => "managed-mcp.txt", "content" => "SYNTHETIC_MANAGED_MCP"}}
      end

    old_helper = System.get_env("IPSE_RUNNER_PATH")
    substitute_marker = Path.join(c.cwd, "substitute-helper-used")

    try do
      pid = start(c, %{approval: :ask, approval_origin: :interactive, headless: false})
      id = Session.info(pid).id
      path = Path.join(c.cwd, relative)
      refute File.exists?(path)

      {:ok, watcher} =
        Task.start(fn ->
          await_marker(Path.join(c.root, "managed-approval-input-ready"), "ready", 1500)
          state = :sys.get_state(pid)
          assert state.phase == :managed_approval and state.share_barrier.phase == :review_input
          assert state.managed_approval.arguments == arguments
          assert state.managed_approval.dependencies != []
          assert Enum.all?(state.managed_approval.dependencies, &(&1["version"] == 3))
          assert {:error, _} = Session.approve(pid, make_ref(), true)
          refute File.exists?(path)

          if kind == "mcp_pinned" do
            substitute = Path.join(c.root, "substitute-helper")
            helper = Path.join(to_string(:code.priv_dir(:ipse)), "ipse-runner")

            File.write!(
              substitute,
              "#!/bin/sh\nif [ \"$1\" = \"--admitted-stdio\" ]; then printf invoked > #{inspect(substitute_marker)}; fi\nexec #{inspect(helper)} \"$@\"\n"
            )

            File.chmod!(substitute, 0o700)
            System.put_env("IPSE_RUNNER_PATH", substitute)
          end

          if kind == "http" and boundary in [:revoke, :expiry] do
            before = File.read!(Path.join(c.cwd, "managed-mcp-connections.log"))
            File.write!(Path.join(c.root, "native-root-prestart-connections"), before)
          end

          if boundary == :start_revoke,
            do: File.write!(Path.join(c.cwd, "managed-mcp-gate"), "gate"),
            else: native_root_boundary(c, pid, kind, boundary)

          File.write!(Path.join(c.root, "managed-approval-control-checked"), "checked")

          if boundary == :start_revoke do
            marker = if kind == "http", do: "ready", else: ""
            await_marker(Path.join(c.cwd, "managed-mcp-list-ready"), marker, 500)
            assert {:ok, started} = Journal.load(c.dir, id)

            assert [admitted] =
                     Enum.filter(started, &(&1["type"] == "managed_tool_effect_admitted"))

            assert admitted["binding"]["kind"] == "mcp.start"
            refute File.exists?(path)
            refute File.exists?(Path.join(c.cwd, "calls.log"))
            native_root_boundary(c, pid, kind, :revoke)
            File.write!(Path.join(c.cwd, "managed-mcp-list-release"), "release")
          end

          if boundary != :owner_loss do
            native_root_idle(pid, 1500)
            File.write!(Path.join(c.root, "managed-approval-exit-ready"), "ready")
          end

          File.write!(Path.join(c.root, "native-root-checked"), "checked")
        end)

      IO.puts("IPSE_MANAGED_APPROVAL_CLI_READY")

      assert if(boundary == :owner_loss, do: 1, else: 0) ==
               Ipse.CLI.Terminal.interact(
                 pid,
                 Process.monitor(pid),
                 true,
                 "Use the synthetic managed observation in the proposed #{kind} effect.",
                 c.cwd
               )

      await_marker(Path.join(c.root, "native-root-checked"), "checked", 100)
      watcher_ref = Process.monitor(watcher)
      assert_receive {:DOWN, ^watcher_ref, :process, ^watcher, reason}, 1000
      assert reason in [:normal, :noproc]

      if boundary == :current,
        do: assert(File.read!(path) == content),
        else: refute(File.exists?(path))

      if kind == "http" and boundary in [:revoke, :expiry] do
        assert File.read!(Path.join(c.cwd, "managed-mcp-connections.log")) ==
                 File.read!(Path.join(c.root, "native-root-prestart-connections"))
      end

      if kind == "mcp_pinned", do: refute(File.exists?(substitute_marker))

      state = if boundary != :owner_loss, do: :sys.get_state(pid)
      assert {:ok, events} = Journal.load(c.dir, id)

      starts = Enum.filter(events, &(&1["type"] == "tool_started"))

      if boundary == :owner_loss do
        refute Process.alive?(pid)
        assert [%{"name" => "ext__capture__inspect", "approval" => "saved_consent"}] = starts
      else
        assert [
                 %{"name" => "ext__capture__inspect", "approval" => "saved_consent"},
                 %{"name" => ^tool, "approval" => "approved"}
               ] = starts
      end

      admissions = Enum.filter(events, &(&1["type"] == "managed_tool_effect_admitted"))

      cond do
        boundary == :start_revoke ->
          assert [admitted] = admissions
          assert admitted["binding"]["kind"] == "mcp.start"

        boundary != :current ->
          assert admissions == []

        kind in ["mcp", "http", "mcp_pinned"] ->
          assert Enum.map(admissions, &get_in(&1, ["binding", "kind"])) == [
                   "mcp.start",
                   "mcp.send"
                 ]

          assert File.read!(Path.join(c.cwd, "calls.log")) == "write_note\n"

        true ->
          assert [admitted] = admissions
          assert admitted["binding"]["name"] == tool
      end

      for admitted <- admissions do
        assert [%{"status" => "confirmed"}] =
                 Enum.filter(events, fn event ->
                   event["type"] == "managed_tool_effect_cleanup" and
                     event["effect_id"] == admitted["effect_id"]
                 end)
      end

      observed = Enum.filter(events, &(&1["type"] == "managed_tool_result_observed"))
      releases = Enum.filter(events, &(&1["type"] == "managed_tool_result_release"))

      if boundary == :owner_loss do
        assert observed == [] and releases == []
      else
        assert [_] = observed
        decision = if boundary == :current, do: "current", else: "withdrawn"
        assert [%{"decision" => ^decision}] = releases
      end

      assert {:ok, saved} = Session.Saved.restore(events, id)
      if state, do: assert(saved.messages == state.messages)

      assert {:ok, dependencies} =
               Session.ManagedLineage.dependencies(saved.managed_lineage, saved.messages)

      assert dependencies != [] and Enum.all?(dependencies, &(&1["version"] == 3))
      count = if boundary == :current, do: 3, else: 2
      assert Enum.count(events, &(&1["type"] == "request_admitted")) == count

      assert Enum.count(
               events,
               &(&1["type"] == "request_finished" and &1["outcome"] == "completed" and
                   &1["finality"] == "final")
             ) == count

      assert length(Agent.get(c.provider_requests, & &1)) == count

      if boundary == :owner_loss,
        do: native_root_released(Path.join(c.dir, id <> ".lock"), 500),
        else: assert(:ok = Session.close_confirmed(pid))

      connections =
        if kind == "http", do: File.read!(Path.join(c.cwd, "managed-mcp-connections.log"))

      journal = Path.join(c.dir, id <> ".jsonl")
      closed = File.read!(journal)
      resumed = start(c, %{approval: :ask, approval_origin: :interactive, headless: false}, id)
      assert Session.info(resumed).phase == :idle
      assert :sys.get_state(resumed).messages == saved.messages
      assert_idle_resume_journal(journal, closed, id)
      assert :ok = Session.close_confirmed(resumed)

      assert {:ok, %{"release_claim" => "signed_release_claim"}} =
               Session.Saved.inspect_saved(c.dir, id)

      if boundary == :current,
        do: assert(File.read!(path) == content),
        else: refute(File.exists?(path))

      assert length(Agent.get(c.provider_requests, & &1)) == count

      if kind == "http" do
        assert File.read!(Path.join(c.cwd, "managed-mcp-connections.log")) == connections
      end

      if kind == "mcp_pinned", do: refute(File.exists?(substitute_marker))

      if kind in ["mcp", "http", "mcp_pinned"] do
        if boundary == :current,
          do: assert(File.read!(Path.join(c.cwd, "calls.log")) == "write_note\n"),
          else: refute(File.exists?(Path.join(c.cwd, "calls.log")))
      end
    after
      if kind == "mcp_pinned" do
        if old_helper,
          do: System.put_env("IPSE_RUNNER_PATH", old_helper),
          else: System.delete_env("IPSE_RUNNER_PATH")
      end

      Task.shutdown(c.provider_server, :brutal_kill)
    end
  end

  defp native_root_loss_lineage(c, saved) do
    assert {:ok, dependencies} =
             Session.ManagedReference.dependencies(
               saved.managed_lineage.reference,
               saved.messages
             )

    reviewed =
      c.root
      |> Path.join("native-root-loss-dependencies.json")
      |> File.read!()
      |> Jason.decode!()

    assert dependencies != [] and Enum.all?(dependencies, &(&1["version"] == 3))
    assert dependencies == reviewed

    unconfirmed? =
      Enum.any?(saved.managed_lineage.tool_effect_inputs, fn {_, effect} ->
        effect.cleanup != "confirmed"
      end)

    assert saved.managed_lineage.unavailable == unconfirmed?

    expected =
      if unconfirmed?,
        do: {:error, :managed_lineage_unavailable},
        else: {:ok, dependencies}

    assert Session.ManagedLineage.dependencies(saved.managed_lineage, saved.messages) == expected
    unconfirmed?
  end

  defp native_root_children(pid) do
    File.read!("/proc/#{pid}/task/#{pid}/children")
    |> String.split()
    |> Enum.map(&String.to_integer/1)
  end

  defp native_root_processes_stopped(_, 0), do: flunk("native shell group remained live")

  defp native_root_processes_stopped(pids, remaining) do
    stopped? = fn pid ->
      case File.read("/proc/#{pid}/stat") do
        {:error, :enoent} -> true
        {:ok, stat} -> Regex.match?(~r/\) [ZX] /, stat)
        _ -> false
      end
    end

    unless Enum.all?(pids, stopped?) do
      Process.sleep(10)
      native_root_processes_stopped(pids, remaining - 1)
    end
  end

  defp native_root_boundary(_, _, _, :current), do: :ok

  defp native_root_boundary(c, _, kind, :root_change) do
    key =
      Map.fetch!(
        %{
          "write" => "changed.before.approval",
          "shell" => "changed.before.shell",
          "mcp" => "changed.before.mcp",
          "nested_mcp" => "changed.before.nested.mcp",
          "helper_model" => "changed.before.helper.model",
          "helper_decision" => "changed.before.helper.decision",
          "helper_embedding" => "changed.before.helper.embedding",
          "nested_native" => "changed.before.nested.native"
        },
        kind
      )

    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [
                   %{"key" => key, "expected_revision" => 0, "value" => %{}}
                 ]
               },
               Ipse.Usage.id()
             )
  end

  defp native_root_boundary(c, _, _, :revoke) do
    assert {:ok, policy} = Consent.snapshot(c.control, c.binding["project_id"])
    assert {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], policy["epoch"])
  end

  defp native_root_boundary(c, _, _, :expiry) do
    assert {:ok, policy} = Consent.snapshot(c.control, c.binding["project_id"])
    deadline = policy["policy"]["expires_at_ms"]
    Process.sleep(max(deadline - System.system_time(:millisecond) + 10, 0))
    assert System.system_time(:millisecond) >= deadline
  end

  defp native_root_boundary(_, pid, _, :owner_loss) do
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 3000
  end

  defp native_root_released(_, 0), do: flunk("native root owner's original lock did not release")

  defp native_root_released(path, remaining) do
    case Ipse.Runner.lock_source(path) do
      {:ok, lock} ->
        assert :ok = Ipse.Runner.unlock(lock)

      {:error, _} ->
        Process.sleep(10)
        native_root_released(path, remaining - 1)
    end
  end

  defp native_root_idle(_, 0), do: flunk("native root consumer did not become idle")

  defp native_root_idle(pid, remaining) do
    if :sys.get_state(pid).phase != :idle do
      Process.sleep(10)
      native_root_idle(pid, remaining - 1)
    end
  end

  defp assert_stale_helper_recovery(c, pid, operation, code) do
    assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
    server = c.provider_server.pid
    assert_receive {:observed_provider_request, ^server, _}, 1000
    refute_receive {:observed_provider_request, ^server, _}, 100
    id = Session.info(pid).id
    assert {:ok, events} = Journal.load(c.dir, id)
    observations = Enum.filter(events, &(&1["type"] == "managed_read_observed"))
    assert observations != []

    assert {:ok, dependencies} =
             Session.ManagedReference.union(Enum.map(observations, & &1["dependencies"]))

    assert dependencies != []

    [intent] =
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_intent" and
            get_in(&1, ["request", "op"]) == operation)
      )

    [action] =
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "op"]) == operation)
      )

    assert action["outcome"] == %{"status" => "failed", "value" => %{"code" => code}}
    assert Map.drop(action, ~w(type outcome outcome_sha256)) == Map.delete(intent, "type")
    [dispatch] = Enum.filter(events, &(&1["type"] == "inference_dispatch_intent"))
    assert dispatch["phase"] == "model"
    [main, helper] = Enum.filter(events, &(&1["type"] == "request_admitted"))
    assert helper["request_id"] == action["operation_id"]
    [main_finish, helper_finish] = Enum.filter(events, &(&1["type"] == "request_finished"))
    assert main_finish["request_id"] == main["request_id"]

    assert Map.take(main_finish, ~w(outcome finality)) == %{
             "outcome" => "completed",
             "finality" => "final"
           }

    assert helper_finish["request_id"] == helper["request_id"]

    assert Map.take(helper_finish, ~w(outcome finality)) == %{
             "outcome" => "failed",
             "finality" => "partial"
           }

    [delivered, unknown] = Enum.filter(events, &(&1["type"] == "worker_input_intent"))
    assert delivered["dependencies_sha256"] == JSON.digest(dependencies)
    assert unknown["dependencies_sha256"] == delivered["dependencies_sha256"]
    assert unknown["payload_sha256"] == JSON.digest([Ipse.Extension.Actions.resume(action)])
    results = Enum.filter(events, &(&1["type"] == "worker_input_result"))

    assert Enum.map(results, &{&1["input_id"], &1["status"]}) == [
             {delivered["input_id"], "delivered"},
             {unknown["input_id"], "unknown"}
           ]

    assert {:ok, saved} = Session.Saved.restore(events, id)
    assert saved.worker_input_unknown == [unknown["input_id"]]
    assert saved.managed_lineage.unavailable
    trace = File.read!(c.trace)
    refute trace =~ Jason.encode!(action["outcome"])
    assert :ok = Session.close_confirmed(pid)
    journal = Path.join(c.dir, id <> ".jsonl")
    closed = File.read!(journal)
    resumed = start(c, %{approval: :allow, approval_origin: :yes}, id)
    assert Session.info(resumed).phase == :idle
    state = :sys.get_state(resumed)
    assert state.messages == saved.messages
    assert state.managed_lineage.unavailable
    assert {:ok, recovered} = Journal.load(c.dir, id)
    assert {:ok, restored} = Session.Saved.restore(recovered, id)
    assert restored.worker_input_unknown == saved.worker_input_unknown
    assert_idle_resume_journal(journal, closed, id)
    assert File.read!(c.trace) == trace
    refute_receive {:observed_provider_request, ^server, _}, 100
    assert :ok = Session.close_confirmed(resumed)
    refute_receive {:observed_provider_request, ^server, _}, 100
    assert File.read!(c.trace) == trace
  end

  defp observed_provider(bodies, gate, timeout \\ 10_000, collector \\ nil) do
    owner = self()

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        try do
          for {body, index} <- Enum.with_index(bodies ++ ["unexpected request"]) do
            {:ok, socket} = :gen_tcp.accept(listener, timeout)

            try do
              {_, payload} = Ipse.Test.ProviderFixture.request(socket, "")
              decoded = Jason.decode!(payload)

              if is_pid(collector),
                do: Agent.update(collector, &(&1 ++ [decoded])),
                else: send(owner, {:observed_provider_request, self(), decoded})

              if gate == :second_response and index == 1 do
                send(owner, {:managed_body_sent, self()})
                receive do: (:release_managed_body -> :ok)
              end

              :ok =
                :gen_tcp.send(
                  socket,
                  "HTTP/1.1 200 Fixture\r\ncontent-type: application/x-ndjson\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                    body
                )
            after
              :gen_tcp.close(socket)
            end
          end
        after
          :gen_tcp.close(listener)
        end
      end)

    {"http://127.0.0.1:#{port}", task}
  end

  defp subscription_body(message) do
    output =
      if message["tool_calls"] do
        Enum.map(message["tool_calls"], fn call ->
          %{
            "type" => "function_call",
            "call_id" => "capture",
            "name" => call["function"]["name"],
            "arguments" => Jason.encode!(call["function"]["arguments"])
          }
        end)
      else
        [
          %{
            "type" => "message",
            "role" => "assistant",
            "content" => [%{"type" => "output_text", "text" => message["content"]}]
          }
        ]
      end

    delta =
      if message["content"] != "",
        do: [%{"type" => "response.output_text.delta", "delta" => message["content"]}],
        else: []

    completed = %{
      "type" => "response.completed",
      "response" => %{
        "status" => "completed",
        "model" => "synthetic",
        "output" => output,
        "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
      }
    }

    Enum.map_join(delta ++ [completed], &("data: " <> Jason.encode!(&1) <> "\n\n"))
  end

  defp subscription_credentials(config, root) do
    directory = Path.join(root, "synthetic-auth")

    token = %{
      "access_token" => "subscription-fixture-token",
      "refresh_token" => "subscription-fixture-refresh",
      "id_token" => "subscription-fixture-id",
      "client_id" => "oaiapp_subscription_fixture",
      "ext_agent_host_id" => "urn:uuid:00112233-4455-4677-8899-aabbccddeeff",
      "subject" => "subscription-fixture-account",
      "email" => "subscription@example.test",
      "issuer" => "https://auth.openai.com",
      "token_type" => "Bearer",
      "expires_in" => 3600,
      "expires_at" => System.system_time(:second) + 3600,
      "saved_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "scopes" => ["openid", "offline_access", "chatgpt.tokens.use.direct"]
    }

    assert :ok =
             Ipse.Auth.with_credential_lock(directory, fn ->
               Ipse.Auth.write_credentials(directory, token)
             end)

    Map.put(config, :auth_dir, directory)
  end

  defp tls_provider(bodies, gate) do
    directory = Path.join(System.tmp_dir!(), "ipse-provider-tls-" <> Ipse.Usage.id())
    File.mkdir!(directory)

    certificate =
      :public_key.pkix_test_data(%{
        root: [digest: :sha256, key: {:rsa, 2048, 65537}],
        peer: [
          digest: :sha256,
          key: {:rsa, 2048, 65537},
          extensions: [{:Extension, {2, 5, 29, 17}, false, [{:dNSName, ~c"localhost"}]}]
        ]
      })

    original =
      Enum.map(:public_key.cacerts_get(), fn
        {:cert, der, _} -> der
        der when is_binary(der) -> der
      end)

    pem = fn values ->
      :public_key.pem_encode(Enum.map(values, &{:Certificate, &1, :not_encrypted}))
    end

    saved = Path.join(directory, "original.pem")
    trusted = Path.join(directory, "fixture.pem")
    File.write!(saved, pem.(original))
    File.write!(trusted, pem.(certificate[:cacerts]))
    :ok = :public_key.cacerts_load(trusted)

    on_exit(fn ->
      :ok = :public_key.cacerts_load(saved)
      File.rm_rf!(directory)
    end)

    {:ok, listener} = :ssl.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}] ++ certificate)
    {:ok, {_, port}} = :ssl.sockname(listener)
    owner = self()

    task =
      Task.async(fn ->
        try do
          for {body, index} <- Enum.with_index(bodies) do
            {:ok, socket} = :ssl.transport_accept(listener, 10_000)

            if gate == :connect and index == 1 do
              send(owner, {:managed_tls_connected, self()})
              receive do: (:continue_managed_tls -> :ok)
            end

            {:ok, tls} = :ssl.handshake(socket, 5000)

            try do
              case tls_request(tls, "") do
                {:ok, headers, payload} ->
                  send(owner, {:tls_provider_request, self(), Jason.decode!(payload)})

                  if gate in [:response, :owner_loss] and index == 1 do
                    send(owner, {:managed_tls_body_sent, self()})

                    if gate == :owner_loss do
                      closed = :ssl.recv(tls, 0, 5000)
                      throw({:expected_tls_close, closed})
                    end

                    receive do: (:release_managed_tls_body -> :ok)
                  end

                  :ok =
                    :ssl.send(
                      tls,
                      "HTTP/1.1 200 Fixture\r\ncontent-type: text/event-stream\r\ncontent-length: #{byte_size(body)}\r\nconnection: keep-alive\r\n\r\n" <>
                        body
                    )

                  assert {:error, :closed} = :ssl.recv(tls, 0, 5000)
                  {headers, Jason.decode!(payload)}

                {:error, :closed} ->
                  throw({:expected_tls_close, {:error, :closed}})
              end
            after
              :ssl.close(tls)
            end
          end
        catch
          {:expected_tls_close, result} -> {:closed, result}
        after
          :ssl.close(listener)
        end
      end)

    {"https://localhost:#{port}", task}
  end

  defp tls_request(socket, buffer) when byte_size(buffer) <= 1_048_576 do
    case :binary.split(buffer, "\r\n\r\n") do
      [headers, body] ->
        [_, length] = Regex.run(~r/content-length:\s*(\d+)/i, headers)

        if byte_size(body) >= String.to_integer(length),
          do: {:ok, headers, body},
          else: tls_more(socket, buffer)

      _ ->
        tls_more(socket, buffer)
    end
  end

  defp tls_more(socket, buffer) do
    case :ssl.recv(socket, 0, 5000) do
      {:ok, bytes} -> tls_request(socket, buffer <> bytes)
      error -> error
    end
  end

  @tag registered_main: true, tls_main: true
  test "managed ChatGPT subscription input uses the actual verified TLS adapter and owned publication",
       c do
    pid = start(c, %{execution_mode: :planning})
    assert :ok = Session.prompt(pid, "Synthetic TLS subscription read")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    requests = Task.await(c.provider_server, 5000)
    assert length(requests) == 2

    for {headers, body} <- requests do
      assert headers =~ "POST /responses HTTP/1.1"
      assert String.downcase(headers) =~ "authorization: bearer subscription-fixture-token"
      assert body["model"] == "synthetic"
    end

    {_, second} = List.last(requests)
    assert Enum.any?(second["input"], &(&1["type"] == "function_call_output"))
    state = :sys.get_state(pid)
    assert state.managed_result_seal == nil
    assert {:ok, events} = Journal.load(c.dir, state.id)

    assert Enum.all?(
             Enum.filter(events, &(&1["type"] == "request_admitted")),
             &(&1["provider"] == "chatgpt" and &1["billing_mode"] == "subscription")
           )

    assert {:ok, saved} = Ipse.Session.Saved.restore(events, state.id)
    assert saved.messages == state.messages
    assert :ok = Session.close_confirmed(pid)
  end

  @tag registered_main: true, tls_main: true, tls_gate: :connect
  test "revocation during actual ChatGPT TLS setup refuses before inference headers or body", c do
    pid = start(c, %{execution_mode: :planning})
    assert :ok = Session.prompt(pid, "Synthetic TLS revocation")
    assert_receive {:managed_tls_connected, server}, 10_000
    assert {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    assert {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], snapshot["epoch"])
    send(server, :continue_managed_tls)
    assert_receive {:ipse, ^pid, {:done, :error}}, 10_000
    assert {:closed, {:error, :closed}} = Task.await(c.provider_server, 5000)
    assert_receive {:tls_provider_request, ^server, _}, 1000
    refute_receive {:tls_provider_request, ^server, _}, 100
    refute_receive {:ipse, ^pid, {:text, _}}, 100
    assert :ok = Session.close_confirmed(pid)
  end

  @tag registered_main: true, tls_main: true, tls_gate: :response
  test "actual TLS generation releases policy locks and withholds managed text after root invalidation",
       c do
    pid = start(c, %{execution_mode: :planning})
    assert :ok = Session.prompt(pid, "Synthetic TLS response check")
    assert_receive {:managed_tls_body_sent, server}, 10_000

    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [
                   %{
                     "key" => "synthetic.changed",
                     "expected_revision" => 0,
                     "value" => %{"text" => "changed"}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    send(server, :release_managed_tls_body)
    assert_receive {:ipse, ^pid, {:done, :error}}, 10_000
    assert length(Task.await(c.provider_server, 5000)) == 2
    refute_receive {:ipse, ^pid, {:text, _}}, 100
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    refute Enum.any?(
             events,
             &(get_in(&1, ["message", "content"]) == "Synthetic protected read complete.")
           )

    assert :sys.get_state(pid).managed_result_seal == nil
    assert :ok = Session.close_confirmed(pid)
  end

  @tag registered_main: true, tls_main: true, tls_gate: :owner_loss
  test "killing the actual Session owner closes its managed TLS transport and releases no output",
       c do
    pid = start(c, %{execution_mode: :planning})
    assert :ok = Session.prompt(pid, "Synthetic TLS owner loss")
    assert_receive {:managed_tls_body_sent, _server}, 10_000
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5000
    assert {:closed, {:error, :closed}} = Task.await(c.provider_server, 5000)
    refute_receive {:ipse, ^pid, {:text, _}}, 100
  end

  @tag registered_main: true, response_change: true
  test "a root change during generation withholds buffered native output without retaining policy locks",
       c do
    pid = start(c, %{execution_mode: :planning, fixture_export: "inspect", fixture_mode: "read"})
    assert :ok = Session.prompt(pid, "Synthetic response barrier")
    assert_receive {:managed_body_sent, server}, 10_000

    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [
                   %{
                     "key" => "synthetic.changed",
                     "expected_revision" => 0,
                     "value" => %{"text" => "changed"}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    send(server, :release_managed_body)
    assert_receive {:ipse, ^pid, {:done, :error}}, 10_000
    refute_receive {:ipse, ^pid, {:text, _}}, 100
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    refute Enum.any?(
             events,
             &(get_in(&1, ["message", "content"]) == "Synthetic protected read complete.")
           )

    assert Enum.count(events, &(&1["type"] == "inference_dispatch_intent")) == 2
    assert :sys.get_state(pid).managed_result_seal == nil
    Task.shutdown(c.provider_server, :brutal_kill)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag registered_main: true, response_change: true, wire_expiry: true
  test "an actual managed inference response crossing the saved policy deadline releases no output",
       c do
    pid = start(c, %{execution_mode: :planning})
    assert :ok = Session.prompt(pid, "Synthetic native expiry boundary")
    assert_receive {:managed_body_sent, server}, 10_000
    assert {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    deadline = snapshot["policy"]["expires_at_ms"]
    assert System.system_time(:millisecond) < deadline
    Process.sleep(max(deadline - System.system_time(:millisecond) + 20, 0))
    send(server, :release_managed_body)
    assert_receive {:ipse, ^pid, {:done, :error}}, 10_000
    refute_receive {:ipse, ^pid, {:text, _}}, 100
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    refute Enum.any?(
             events,
             &(get_in(&1, ["message", "content"]) == "Synthetic protected read complete.")
           )

    Task.shutdown(c.provider_server, :brutal_kill)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag registered_main: true, wire_budget: true
  test "the managed wire barrier binds the actual output cap narrowed by the existing shared budget",
       c do
    pid =
      start(c, %{
        execution_mode: :planning,
        max_output_tokens: 64,
        budget: %{
          "version" => 1,
          "max_requests" => 3,
          "max_output_tokens" => 128,
          "reserve_output_tokens" => 32
        }
      })

    assert :ok = Session.prompt(pid, "Synthetic managed budget")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    requests = Task.await(c.provider_server, 5000)
    assert length(requests) == 2
    assert Enum.all?(requests, fn {_, body} -> get_in(body, ["options", "num_predict"]) == 32 end)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag registered_main: true, managed_helper: true
  @tag helper_withdrawal_boundary: true
  test "a registered helper revalidates inherited worker reads before its actual native request",
       c do
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    assert :ok = Session.prompt(pid, "Synthetic current helper")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    requests = Task.await(c.provider_server, 5000)
    assert length(requests) == 3
    {_, helper} = Enum.at(requests, 1)
    assert length(helper["messages"]) == 2
    assert List.last(helper["messages"])["content"] =~ "generation"
    state = :sys.get_state(pid)
    assert {:ok, events} = Journal.load(c.dir, state.id)

    assert Enum.any?(
             events,
             &(&1["type"] == "managed_preflight_intent" and &1["phase"] == "model.complete")
           )

    assert {:ok, saved} = Ipse.Session.Saved.restore(events, state.id)
    assert saved.messages == state.messages
    assert :ok = Session.close_confirmed(pid)
  end

  @tag literal_v4_ab: true,
       registered_main: true,
       managed_helper: true,
       managed_decision: true,
       managed_pack: true,
       managed_pack_wide: true,
       response_change: true,
       malformed_decision: true
  @tag :managed_split_malformed_lost
  @tag skip:
         if(
           System.get_env("IPSE_LITERAL_AB_ROOT") &&
             System.get_env("IPSE_TEST_MANAGED_PACK") == "1",
           do: false,
           else: "split managed pack fixture required"
         )
  test "source loss during a malformed decision does not release a shadow result", c do
    seed = c.literal_seed
    assert length(seed["source_journals"]) == 2
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    assert :ok = Session.prompt(pid, "Synthetic malformed stale query")
    assert_receive {:managed_body_sent, server}, 30_000
    assert_receive {:observed_provider_request, ^server, _}, 1000
    assert_receive {:observed_provider_request, ^server, _}, 1000
    source_index = if System.get_env("IPSE_TEST_SOURCE_INDEX") == "1", do: 1, else: 0
    source = Enum.fetch!(seed["source_journals"], source_index)["path"]
    held = source <> ".held-malformed-response"
    File.rename!(source, held)

    try do
      send(server, :release_managed_body)
      assert_receive {:ipse, ^pid, {:done, :error}}, 20_000
      refute File.read!(c.trace) =~ "pack-reprojected\n"
      assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
      refute Enum.any?(events, &(&1["type"] == "extension_decision_response"))

      observed =
        for event <- events,
            event["type"] == "managed_read_observed",
            dependency <- event["dependencies"],
            dependency["version"] == 4,
            do: get_in(dependency, ["subject", "key"])

      assert MapSet.subset?(MapSet.new(seed["keys"]), MapSet.new(observed))

      refute Enum.any?(events, fn event ->
               event["type"] == "extension_action_intent" and
                 get_in(event, ["request", "op"]) == "context.publish"
             end)

      assert_receive {:ipse, ^pid, {:tool_result, "ext__capture__capture", withheld}}, 1000

      assert Jason.decode!(withheld) == %{
               "historical_receipt" => true,
               "reason" => "managed_dependencies_unavailable",
               "status" => "withheld"
             }

      refute_receive {:observed_provider_request, ^server, _}, 100

      assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
      Task.shutdown(c.provider_server, :brutal_kill)
      assert :ok = Session.close_confirmed(pid)
    after
      if File.exists?(held), do: File.rename!(held, source)
    end

    for original <- seed["source_journals"] do
      assert File.read!(original["path"]) |> JSON.sha256() == original["sha256"]
    end
  end

  @tag literal_v4_ab: true,
       registered_main: true,
       managed_helper: true,
       managed_decision: true,
       managed_pack: true,
       managed_pack_wide: true,
       helper_stale: true
  @tag :managed_pack_approval_display_refused
  @tag skip:
         if(
           System.get_env("IPSE_LITERAL_AB_ROOT") &&
             System.get_env("IPSE_TEST_MANAGED_PACK") == "1",
           do: false,
           else: "split managed pack fixture required"
         )
  test "managed pack approval display refusal prevents decision egress", c do
    seed = c.literal_seed
    assert length(seed["source_journals"]) == 2
    pid = start(c, %{approval: :ask, approval_origin: :interactive, headless: false})
    assert :ok = Session.prompt(pid, "Synthetic denied two-source query")

    assert_receive {:ipse, ^pid,
                    {:error,
                     "Managed approval or question arguments cannot be displayed under current source ownership; no action was started."}},
                   30_000

    assert_receive {:ipse, ^pid, {:done, :error}}, 20_000
    server = c.provider_server.pid
    assert_receive {:observed_provider_request, ^server, _}, 1000
    refute_receive {:observed_provider_request, ^server, _}, 100
    refute_receive {:ipse, ^pid, {:approval, _, "extension:decision.create", _}}, 100
    refute File.read!(c.trace) =~ "pack-reprojected\n"
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    observed =
      for event <- events,
          event["type"] == "managed_read_observed",
          dependency <- event["dependencies"],
          dependency["version"] == 4,
          do: get_in(dependency, ["subject", "key"])

    assert MapSet.subset?(MapSet.new(seed["keys"]), MapSet.new(observed))

    refute Enum.any?(
             events,
             &(&1["type"] == "inference_dispatch_intent" and &1["phase"] == "decision.create")
           )

    refute Enum.any?(
             events,
             &(&1["type"] == "request_admitted" and Ipse.Usage.operation(&1) == "decision")
           )

    assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
    Task.shutdown(c.provider_server, :brutal_kill)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag literal_v4_ab: true,
       registered_main: true,
       managed_helper: true,
       managed_decision: true,
       managed_pack: true,
       managed_pack_wide: true,
       response_change: true
  @tag :managed_split_response_current
  @tag skip:
         if(
           System.get_env("IPSE_LITERAL_AB_ROOT") &&
             System.get_env("IPSE_TEST_MANAGED_PACK") == "1",
           do: false,
           else: "split managed pack fixture required"
         )
  test "current two-source pack permits its held decision response", c do
    assert length(c.literal_seed["source_journals"]) == 2
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    assert :ok = Session.prompt(pid, "Synthetic held two-source query")
    assert_receive {:managed_body_sent, server}, 30_000
    assert_receive {:observed_provider_request, ^server, _}, 1000
    assert_receive {:observed_provider_request, ^server, request}, 1000
    assert Jason.encode!(request) =~ "Synthetic held two-source query"
    send(server, :release_managed_body)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 20_000
    assert File.read!(c.trace) =~ "pack-reprojected\n"
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    observed =
      for event <- events,
          event["type"] == "managed_read_observed",
          dependency <- event["dependencies"],
          dependency["version"] == 4,
          do: get_in(dependency, ["subject", "key"])

    assert MapSet.subset?(MapSet.new(c.literal_seed["keys"]), MapSet.new(observed))

    assert Enum.any?(events, fn event ->
             event["type"] == "extension_action_result" and
               get_in(event, ["request", "op"]) == "decision.create" and
               get_in(event, ["outcome", "status"]) == "ok"
           end)

    assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
    Task.shutdown(c.provider_server, :brutal_kill)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag literal_v4_ab: true,
       registered_main: true,
       managed_helper: true,
       managed_decision: true,
       managed_pack: true,
       managed_pack_wide: true,
       response_change: true
  @tag :managed_split_response_lost
  @tag skip:
         if(
           System.get_env("IPSE_LITERAL_AB_ROOT") &&
             System.get_env("IPSE_TEST_MANAGED_PACK") == "1",
           do: false,
           else: "split managed pack fixture required"
         )
  test "loss of either original source withholds a held pack response", c do
    seed = c.literal_seed
    assert length(seed["source_journals"]) == 2
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    assert :ok = Session.prompt(pid, "Synthetic held stale two-source query")
    assert_receive {:managed_body_sent, server}, 30_000
    assert_receive {:observed_provider_request, ^server, _}, 1000
    assert_receive {:observed_provider_request, ^server, request}, 1000
    assert Jason.encode!(request) =~ "Synthetic held stale two-source query"
    source_index = if System.get_env("IPSE_TEST_SOURCE_INDEX") == "1", do: 1, else: 0
    selected_source = Enum.fetch!(seed["source_journals"], source_index)
    source = selected_source["path"]
    held = source <> ".held-pack-response"
    File.rename!(source, held)

    try do
      send(server, :release_managed_body)
      assert_receive {:ipse, ^pid, {:done, status}}, 20_000
      assert status in [:ok, :error]
      refute File.read!(c.trace) =~ "pack-reprojected\n"
      assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

      observed =
        for event <- events,
            event["type"] == "managed_read_observed",
            dependency <- event["dependencies"],
            dependency["version"] == 4,
            do: get_in(dependency, ["subject", "key"])

      assert MapSet.subset?(MapSet.new(seed["keys"]), MapSet.new(observed))

      assert Enum.any?(events, fn event ->
               event["type"] == "inference_dispatch_intent" and
                 event["phase"] == "decision.create"
             end)

      refute Enum.any?(events, fn event ->
               event["type"] == "extension_action_result" and
                 get_in(event, ["request", "op"]) == "decision.create" and
                 get_in(event, ["outcome", "status"]) == "ok"
             end)

      assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
      Task.shutdown(c.provider_server, :brutal_kill)
      assert :ok = Session.close_confirmed(pid)
    after
      if File.exists?(held), do: File.rename!(held, source)
    end

    for original <- seed["source_journals"] do
      assert File.read!(original["path"]) |> JSON.sha256() == original["sha256"]
    end
  end

  @tag literal_v4_ab: true,
       registered_main: true,
       managed_helper: true,
       managed_decision: true,
       managed_pack: true,
       managed_pack_wide: true,
       helper_stale: true
  @tag :managed_pack_actual_overflow_stale
  @tag skip:
         if(
           System.get_env("IPSE_LITERAL_AB_ROOT") &&
             System.get_env("IPSE_TEST_MANAGED_PACK") == "1",
           do: false,
           else: "wide managed pack fixture required"
         )
  test "source loss prevents an actual-budget wide shadow decision", c do
    seed = c.literal_seed
    assert length(seed["keys"]) == 8

    for source <- seed["source_journals"] do
      assert File.read!(source["path"]) |> JSON.sha256() == source["sha256"]
    end

    pid = start(c, %{approval: :allow, approval_origin: :yes})
    owner = self()

    gate = fn
      count, {:in, {:"$gen_call", _, {:managed_preflight_begin, _, "decision.create"}}}, _ ->
        send(owner, {:wide_preflight_blocked, self()})
        receive do: (:release_wide_preflight -> :ok)
        count + 1

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(pid, {gate, 0})
    assert :ok = Session.prompt(pid, "Synthetic stale wide selection")
    assert_receive {:wide_preflight_blocked, ^pid}, 30_000
    source_index = if System.get_env("IPSE_TEST_SOURCE_INDEX") == "1", do: 1, else: 0
    selected_source = Enum.fetch!(seed["source_journals"], source_index)
    source = selected_source["path"]
    held = source <> ".wide-pack-fixture-held"
    File.rename!(source, held)

    try do
      send(pid, :release_wide_preflight)
      assert_receive {:ipse, ^pid, {:done, :ok}}, 20_000
      server = c.provider_server.pid
      assert_receive {:observed_provider_request, ^server, _}, 1000
      assert_receive {:observed_provider_request, ^server, _}, 1000
      refute_receive {:observed_provider_request, ^server, _}, 100
      refute File.read!(c.trace) =~ "pack-reprojected\n"
      assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

      observed =
        for event <- events,
            event["type"] == "managed_read_observed",
            dependency <- event["dependencies"],
            dependency["version"] == 4,
            do: get_in(dependency, ["subject", "key"])

      assert MapSet.subset?(MapSet.new(seed["keys"]), MapSet.new(observed))

      intent =
        Enum.find(events, fn event ->
          event["type"] == "extension_action_intent" and
            get_in(event, ["request", "op"]) == "decision.create"
        end)

      assert Jason.decode!(intent["request"]["input"])["query"] ==
               "Synthetic stale wide selection"

      refute Enum.any?(
               events,
               &(&1["type"] == "inference_dispatch_intent" and &1["phase"] == "decision.create")
             )

      assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
      Task.shutdown(c.provider_server, :brutal_kill)
      assert :ok = Session.close_confirmed(pid)
    after
      if File.exists?(held), do: File.rename!(held, source)
    end

    assert File.read!(source) |> JSON.sha256() == selected_source["sha256"]

    for original <- seed["source_journals"] do
      assert File.read!(original["path"]) |> JSON.sha256() == original["sha256"]
    end
  end

  @tag literal_v4_ab: true,
       registered_main: true,
       managed_helper: true,
       managed_decision: true,
       managed_pack: true,
       managed_pack_wide: true
  @tag :managed_pack_malformed_response
  @tag malformed_decision: true
  @tag skip:
         if(
           System.get_env("IPSE_LITERAL_AB_ROOT") &&
             System.get_env("IPSE_TEST_MANAGED_PACK") == "1",
           do: false,
           else: "wide managed pack fixture required"
         )
  test "malformed two-source decision response preserves the host failure class", c do
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    assert :ok = Session.prompt(pid, "Synthetic malformed decision query")
    assert_receive {:ipse, ^pid, {:done, :error}}, 30_000
    assert_receive {:ipse, ^pid, {:error, service_error}}, 1000
    assert service_error =~ "unknown outcome"
    server = c.provider_server.pid
    assert_receive {:observed_provider_request, ^server, _}, 1000
    assert_receive {:observed_provider_request, ^server, _}, 1000
    refute_receive {:observed_provider_request, ^server, _}, 100
    trace = File.read!(c.trace)
    assert trace =~ "pack-host-failure:decision_response\n"
    refute trace =~ "pack-reprojected\n"
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    assert Enum.any?(
             events,
             &(&1["type"] == "extension_action_result" and
                 get_in(&1, ["request", "op"]) == "decision.create" and
                 get_in(&1, ["outcome", "status"]) == "failed" and
                 get_in(&1, ["outcome", "value", "code"]) == "decision_response")
           )

    refute Enum.any?(events, &(&1["type"] == "extension_decision_response"))

    decision_admission =
      Enum.find(
        events,
        &(&1["type"] == "request_admitted" and Ipse.Usage.operation(&1) == "decision")
      )

    assert is_map(decision_admission)

    decision_finished =
      Enum.find(
        events,
        &(&1["type"] == "request_finished" and
            &1["request_id"] == decision_admission["request_id"])
      )

    assert decision_finished["outcome"] == "failed" and decision_finished["finality"] == "partial"
    id = Session.info(pid).id
    assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
    assert :ok = Session.close_confirmed(pid)
    resumed = start(c, %{approval: :allow, approval_origin: :yes}, id)
    assert Session.info(resumed).phase == :idle
    refute_receive {:observed_provider_request, ^server, _}, 300
    assert :ok = Session.close_confirmed(resumed)
    Task.shutdown(c.provider_server, :brutal_kill)
  end

  @tag literal_v4_ab: true,
       registered_main: true,
       managed_helper: true,
       managed_decision: true,
       managed_pack: true,
       managed_pack_wide: true,
       low_confidence: true
  @tag :managed_pack_low_confidence
  @tag skip:
         if(
           System.get_env("IPSE_LITERAL_AB_ROOT") &&
             System.get_env("IPSE_TEST_MANAGED_PACK") == "1",
           do: false,
           else: "wide managed pack fixture required"
         )
  test "low-confidence two-source advice retains the ordinary baseline in shadow mode", c do
    assert length(c.literal_seed["source_journals"]) == 2
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    assert :ok = Session.prompt(pid, "Synthetic low confidence query")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 30_000
    assert [_, {headers, payload}, _] = Task.await(c.provider_server, 30_000)
    assert headers =~ "POST /systemone"
    assert Jason.encode!(payload) =~ "Synthetic low confidence query"
    trace = File.read!(c.trace)
    assert trace =~ ~r/baseline-compared:[1-8]\n/
    assert trace =~ "pack-baseline-only:low_probability\n"
    refute trace =~ "pack-reprojected\n"
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    observed =
      for event <- events,
          event["type"] == "managed_read_observed",
          dependency <- event["dependencies"],
          dependency["version"] == 4,
          do: get_in(dependency, ["subject", "key"])

    assert MapSet.subset?(MapSet.new(c.literal_seed["keys"]), MapSet.new(observed))

    assert Enum.any?(
             events,
             &(&1["type"] == "inference_dispatch_intent" and &1["phase"] == "decision.create")
           )

    refute Enum.any?(events, fn event ->
             event["type"] == "extension_action_intent" and
               (get_in(event, ["request", "op"]) in ~w(collection.managed state.put state.delete context.publish) or
                  (get_in(event, ["request", "op"]) == "collection.call" and
                     get_in(event, ["request", "request", "op"]) == "commit"))
           end)

    assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag literal_v4_ab: true,
       registered_main: true,
       managed_helper: true,
       managed_decision: true,
       managed_pack: true,
       managed_pack_wide: true
  @tag :managed_pack_actual_overflow
  @tag skip:
         if(
           System.get_env("IPSE_LITERAL_AB_ROOT") &&
             System.get_env("IPSE_TEST_MANAGED_PACK") == "1",
           do: false,
           else: "wide managed pack fixture required"
         )
  test "over-budget managed notes use the actual context allocation for a shadow decision", c do
    seed = c.literal_seed
    assert length(seed["keys"]) == 8

    for source <- seed["source_journals"] do
      assert File.read!(source["path"]) |> JSON.sha256() == source["sha256"]
    end

    pid = start(c, %{approval: :allow, approval_origin: :yes})
    assert :ok = Session.prompt(pid, "Synthetic wide note selection")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 30_000
    assert [_, {headers, payload}, _] = Task.await(c.provider_server, 30_000)
    assert headers =~ "POST /systemone"
    assert Jason.encode!(payload) =~ "Synthetic wide note selection"
    assert File.read!(c.trace) =~ "pack-reprojected\n"
    assert File.read!(c.trace) =~ ~r/baseline-compared:[1-8]\n/
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    assert Enum.any?(events, fn event ->
             event["type"] == "extension_action_result" and
               get_in(event, ["request", "op"]) == "context.available" and
               get_in(event, ["outcome", "status"]) == "ok"
           end)

    for op <- ~w(source.list source.read) do
      assert Enum.any?(events, fn event ->
               event["type"] == "extension_action_result" and
                 get_in(event, ["request", "op"]) == op and
                 get_in(event, ["outcome", "status"]) == "ok"
             end)
    end

    observed =
      for event <- events,
          event["type"] == "managed_read_observed",
          dependency <- event["dependencies"],
          dependency["version"] == 4,
          do: get_in(dependency, ["subject", "key"])

    assert MapSet.subset?(MapSet.new(seed["keys"]), MapSet.new(observed))

    assert Enum.any?(
             events,
             &(&1["type"] == "inference_dispatch_intent" and &1["phase"] == "decision.create")
           )

    refute Enum.any?(events, fn event ->
             event["type"] == "extension_action_intent" and
               (get_in(event, ["request", "op"]) in ~w(collection.managed state.put state.delete) or
                  (get_in(event, ["request", "op"]) == "collection.call" and
                     get_in(event, ["request", "request", "op"]) == "commit"))
           end)

    assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag literal_v4_ab: true,
       registered_main: true,
       managed_helper: true,
       managed_decision: true,
       managed_pack_actual: true
  @tag :managed_pack_actual_budget
  @tag skip:
         if(
           System.get_env("IPSE_LITERAL_AB_ROOT") &&
             System.get_env("IPSE_TEST_MANAGED_PACK") == "1",
           do: false,
           else: "two-note managed pack fixture required"
         )
  test "a fitting actual context allocation bypasses shadow decision egress", c do
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    assert :ok = Session.prompt(pid, "Synthetic actual-budget note selection")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 20_000
    server = c.provider_server.pid
    assert_receive {:observed_provider_request, ^server, _}, 1000
    assert_receive {:observed_provider_request, ^server, _}, 1000
    refute_receive {:observed_provider_request, ^server, _}, 100
    assert File.read!(c.trace) =~ "pack-bypass\n"
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    assert Enum.any?(events, fn event ->
             event["type"] == "extension_action_result" and
               get_in(event, ["request", "op"]) == "context.available" and
               get_in(event, ["outcome", "status"]) == "ok"
           end)

    refute Enum.any?(events, fn event ->
             event["type"] == "extension_action_intent" and
               get_in(event, ["request", "op"]) == "decision.create"
           end)

    assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
    Task.shutdown(c.provider_server, :brutal_kill)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag literal_v4_ab: true,
       registered_main: true,
       managed_helper: true,
       managed_decision: true,
       managed_pack: true,
       helper_stale: true
  @tag :managed_pack_decision_stale
  @tag skip:
         if(
           System.get_env("IPSE_LITERAL_AB_ROOT") &&
             System.get_env("IPSE_TEST_MANAGED_PACK") == "1",
           do: false,
           else: "two-note managed pack fixture required"
         )
  test "loss of a source prevents a measured shadow pack decision", c do
    seed = c.literal_seed
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    owner = self()

    gate = fn
      count, {:in, {:"$gen_call", _, {:managed_preflight_begin, _, "decision.create"}}}, _ ->
        send(owner, {:pack_preflight_blocked, self()})
        receive do: (:release_pack_preflight -> :ok)
        count + 1

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(pid, {gate, 0})
    assert :ok = Session.prompt(pid, "Synthetic stale note pack selection")
    assert_receive {:pack_preflight_blocked, ^pid}, 15_000
    source = seed["source_journal"]
    held = source <> ".pack-fixture-held"
    File.rename!(source, held)

    try do
      send(pid, :release_pack_preflight)
      assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
      server = c.provider_server.pid
      assert_receive {:observed_provider_request, ^server, _}, 1000
      assert_receive {:observed_provider_request, ^server, _}, 1000
      refute_receive {:observed_provider_request, ^server, _}, 100
      refute File.read!(c.trace) =~ "pack-reprojected\n"
      assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

      observed =
        for event <- events,
            event["type"] == "managed_read_observed",
            dependency <- event["dependencies"],
            dependency["version"] == 4,
            do: get_in(dependency, ["subject", "key"])

      assert MapSet.subset?(MapSet.new([seed["key"], seed["other_key"]]), MapSet.new(observed))

      assert Enum.any?(events, fn event ->
               event["type"] == "extension_action_intent" and
                 get_in(event, ["request", "op"]) == "decision.create"
             end)

      refute Enum.any?(
               events,
               &(&1["type"] == "inference_dispatch_intent" and &1["phase"] == "decision.create")
             )

      assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
      Task.shutdown(c.provider_server, :brutal_kill)
      assert :ok = Session.close_confirmed(pid)
    after
      if File.exists?(held), do: File.rename!(held, source)
    end

    assert File.read!(source) |> JSON.sha256() == seed["source_sha256"]
  end

  @tag literal_v4_ab: true,
       registered_main: true,
       managed_helper: true,
       managed_decision: true,
       managed_pack: true
  @tag :managed_pack_decision
  @tag skip:
         if(
           System.get_env("IPSE_LITERAL_AB_ROOT") &&
             System.get_env("IPSE_TEST_MANAGED_PACK") == "1",
           do: false,
           else: "two-note managed pack fixture required"
         )
  test "actual managed note reads produce a measured shadow decision", c do
    seed = c.literal_seed
    assert is_binary(seed["other_key"])
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    assert :ok = Session.prompt(pid, "Synthetic note pack selection")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 20_000
    assert [_, {headers, payload}, _] = Task.await(c.provider_server, 5000)
    assert headers =~ "POST /systemone"
    assert Jason.encode!(payload) =~ "SYNTHETIC_LITERAL_A_PRIVATE"
    assert Jason.encode!(payload) =~ "SYNTHETIC_LITERAL_B_PRIVATE"
    assert File.read!(c.trace) =~ "pack-reprojected\n"
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    observed =
      for event <- events,
          event["type"] == "managed_read_observed",
          dependency <- event["dependencies"],
          dependency["version"] == 4,
          do: get_in(dependency, ["subject", "key"])

    assert MapSet.subset?(MapSet.new([seed["key"], seed["other_key"]]), MapSet.new(observed))

    assert Enum.any?(
             events,
             &(&1["type"] == "inference_dispatch_intent" and &1["phase"] == "decision.create")
           )

    assert Enum.any?(events, fn event ->
             event["type"] == "extension_action_result" and
               get_in(event, ["request", "op"]) == "decision.create" and
               get_in(event, ["outcome", "status"]) == "ok"
           end)

    refute Enum.any?(events, fn event ->
             event["type"] == "extension_action_intent" and
               (get_in(event, ["request", "op"]) in ~w(collection.managed state.put state.delete) or
                  (get_in(event, ["request", "op"]) == "collection.call" and
                     get_in(event, ["request", "request", "op"]) == "commit"))
           end)

    assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag literal_v4_ab: true,
       registered_main: true,
       managed_helper: true,
       managed_decision: true,
       managed_decision_literal: true
  @tag :managed_literal_decision
  @tag skip:
         if(System.get_env("IPSE_LITERAL_AB_ROOT"),
           do: false,
           else: "historical literal fixture required"
         )
  test "a current recorded literal can be checked before a decision helper", c do
    seed = c.literal_seed
    assert File.read!(seed["source_journal"]) |> JSON.sha256() == seed["source_sha256"]
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    assert :ok = Session.prompt(pid, "Synthetic literal decision")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    assert [_, {headers, payload}, _] = Task.await(c.provider_server, 5000)
    assert headers =~ "POST /systemone"
    assert Jason.encode!(payload) =~ "SYNTHETIC_LITERAL_A_PRIVATE"
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    assert Enum.any?(events, fn event ->
             event["type"] == "managed_read_observed" and
               Enum.any?(event["dependencies"], fn dependency ->
                 dependency["version"] == 4 and
                   get_in(dependency, ["subject", "key"]) == seed["key"]
               end)
           end)

    assert Enum.any?(
             events,
             &(&1["type"] == "inference_dispatch_intent" and &1["phase"] == "decision.create")
           )

    assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag literal_v4_ab: true,
       registered_main: true,
       managed_helper: true,
       managed_decision: true,
       managed_decision_literal: true,
       helper_stale: true
  @tag :managed_literal_decision_stale
  @tag skip:
         if(System.get_env("IPSE_LITERAL_AB_ROOT"),
           do: false,
           else: "historical literal fixture required"
         )
  test "loss of a recorded literal source prevents decision helper egress", c do
    seed = c.literal_seed
    assert File.read!(seed["source_journal"]) |> JSON.sha256() == seed["source_sha256"]
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    owner = self()

    gate = fn
      count, {:in, {:"$gen_call", _, {:managed_preflight_begin, _, "decision.create"}}}, _ ->
        send(owner, {:literal_decision_preflight, self()})
        receive do: (:release_literal_decision -> :ok)
        count + 1

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(pid, {gate, 0})
    assert :ok = Session.prompt(pid, "Synthetic stale literal decision")
    assert_receive {:literal_decision_preflight, ^pid}, 10_000
    source = seed["source_journal"]
    held = source <> ".decision-fixture-held"
    File.rename!(source, held)

    try do
      send(pid, :release_literal_decision)
      assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
      server = c.provider_server.pid
      assert_receive {:observed_provider_request, ^server, _}, 1000
      assert_receive {:observed_provider_request, ^server, _}, 1000
      refute_receive {:observed_provider_request, ^server, _}, 100
      assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

      assert Enum.any?(events, fn event ->
               event["type"] == "managed_read_observed" and
                 Enum.any?(event["dependencies"], fn dependency ->
                   dependency["version"] == 4 and
                     get_in(dependency, ["subject", "key"]) == seed["key"]
                 end)
             end)

      assert Enum.any?(events, fn event ->
               event["type"] == "extension_action_intent" and
                 get_in(event, ["request", "op"]) == "decision.create"
             end)

      assert Enum.any?(events, fn event ->
               event["type"] == "managed_preflight_intent" and event["phase"] == "decision.create" and
                 event["dependencies_sha256"] != JSON.digest([])
             end)

      refute Enum.any?(events, fn event ->
               event["type"] == "inference_dispatch_intent" and
                 event["phase"] == "decision.create"
             end)

      assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
      Task.shutdown(c.provider_server, :brutal_kill)
      assert :ok = Session.close_confirmed(pid)
    after
      if File.exists?(held), do: File.rename!(held, source)
    end

    assert File.read!(source) |> JSON.sha256() == seed["source_sha256"]
  end

  @tag literal_v4_ab: true,
       registered_main: true,
       managed_helper: true,
       managed_decision: true,
       managed_decision_literal: true,
       response_change: true
  @tag :managed_literal_response_current
  @tag skip:
         if(System.get_env("IPSE_LITERAL_AB_ROOT"),
           do: false,
           else: "historical literal fixture required"
         )
  test "a current literal permits its held decision response", c do
    seed = c.literal_seed
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    assert :ok = Session.prompt(pid, "Synthetic held literal decision")
    assert_receive {:managed_body_sent, server}, 10_000
    assert_receive {:observed_provider_request, ^server, _}, 1000
    assert_receive {:observed_provider_request, ^server, decision}, 1000
    assert Jason.encode!(decision) =~ "SYNTHETIC_LITERAL_A_PRIVATE"
    send(server, :release_managed_body)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    assert File.read!(c.trace) =~ "\"relevant\""
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    assert Enum.any?(events, fn event ->
             event["type"] == "managed_read_observed" and
               Enum.any?(event["dependencies"], fn dependency ->
                 dependency["version"] == 4 and
                   get_in(dependency, ["subject", "key"]) == seed["key"]
               end)
           end)

    assert Enum.any?(events, fn event ->
             event["type"] == "extension_action_result" and
               get_in(event, ["request", "op"]) == "decision.create" and
               get_in(event, ["outcome", "status"]) == "ok"
           end)

    assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
    Task.shutdown(c.provider_server, :brutal_kill)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag literal_v4_ab: true,
       registered_main: true,
       managed_helper: true,
       managed_decision: true,
       managed_decision_literal: true,
       response_change: true
  @tag :managed_literal_response_lost
  @tag skip:
         if(System.get_env("IPSE_LITERAL_AB_ROOT"),
           do: false,
           else: "historical literal fixture required"
         )
  test "loss of a literal source during decision inference withholds its response", c do
    seed = c.literal_seed
    assert File.read!(seed["source_journal"]) |> JSON.sha256() == seed["source_sha256"]
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    assert :ok = Session.prompt(pid, "Synthetic held stale literal decision")
    assert_receive {:managed_body_sent, server}, 10_000
    assert_receive {:observed_provider_request, ^server, _}, 1000
    assert_receive {:observed_provider_request, ^server, decision}, 1000
    assert Jason.encode!(decision) =~ "SYNTHETIC_LITERAL_A_PRIVATE"
    source = seed["source_journal"]
    held = source <> ".decision-response-fixture-held"
    File.rename!(source, held)

    try do
      send(server, :release_managed_body)
      assert_receive {:ipse, ^pid, {:done, status}}, 15_000
      assert status in [:ok, :error]
      refute File.read!(c.trace) =~ "\"relevant\""
      assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

      assert Enum.any?(events, fn event ->
               event["type"] == "managed_read_observed" and
                 Enum.any?(event["dependencies"], fn dependency ->
                   dependency["version"] == 4 and
                     get_in(dependency, ["subject", "key"]) == seed["key"]
                 end)
             end)

      assert Enum.any?(events, fn event ->
               event["type"] == "inference_dispatch_intent" and
                 event["phase"] == "decision.create"
             end)

      refute Enum.any?(events, fn event ->
               event["type"] == "extension_action_result" and
                 get_in(event, ["request", "op"]) == "decision.create" and
                 get_in(event, ["outcome", "status"]) == "ok"
             end)

      assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
      Task.shutdown(c.provider_server, :brutal_kill)
      assert :ok = Session.close_confirmed(pid)
    after
      if File.exists?(held), do: File.rename!(held, source)
    end

    assert File.read!(source) |> JSON.sha256() == seed["source_sha256"]
  end

  @tag registered_main: true, managed_helper: true, managed_decision: true
  @tag helper_withdrawal_boundary: true
  @tag :managed_current_decision
  test "a current managed root permits the selected decision helper", c do
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    assert :ok = Session.prompt(pid, "Synthetic current decision")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    assert [_, {headers, _}, _] = Task.await(c.provider_server, 5000)
    assert headers =~ "POST /systemone"
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
    assert Enum.any?(events, &(&1["type"] == "managed_read_observed"))

    assert Enum.any?(
             events,
             &(&1["type"] == "managed_preflight_intent" and &1["phase"] == "decision.create" and
                 &1["dependencies_sha256"] != JSON.digest([]))
           )

    assert Enum.any?(
             events,
             &(&1["type"] == "inference_dispatch_intent" and &1["phase"] == "decision.create")
           )

    assert Enum.any?(events, fn event ->
             event["type"] == "extension_action_result" and
               get_in(event, ["request", "op"]) == "decision.create" and
               get_in(event, ["outcome", "status"]) == "ok"
           end)

    assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag registered_main: true, managed_helper: true, managed_decision: true, helper_stale: true
  @tag helper_withdrawal_boundary: true
  @tag :managed_stale_decision
  test "a changed managed root prevents decision helper egress", c do
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    owner = self()

    gate = fn
      count, {:in, {:"$gen_call", _, {:managed_preflight_begin, _, "decision.create"}}}, _ ->
        send(owner, {:decision_preflight_blocked, self()})
        receive do: (:release_decision_preflight -> :ok)
        count + 1

      count, _, _ ->
        count
    end

    on_exit(fn -> send(pid, :release_decision_preflight) end)

    try do
      assert :ok = :sys.install(pid, {gate, 0})
      assert :ok = Session.prompt(pid, "Synthetic stale decision")
      assert_receive {:decision_preflight_blocked, ^pid}, 10_000

      assert {:ok, _} =
               Ipse.Extension.Collection.execute(
                 SemanticAdmission.collection_root(c.home),
                 c.namespace,
                 %{
                   "op" => "commit",
                   "expected_generation" => 0,
                   "advance_floor" => false,
                   "changes" => [
                     %{
                       "key" => "synthetic.changed",
                       "expected_revision" => 0,
                       "value" => %{"text" => "changed"}
                     }
                   ]
                 },
                 Ipse.Usage.id()
               )

      send(pid, :release_decision_preflight)
      assert_stale_helper_recovery(c, pid, "decision.create", "decision_request_failed")
    after
      send(pid, :release_decision_preflight)
      Task.shutdown(c.provider_server, :brutal_kill)
    end
  end

  @tag registered_main: true, managed_helper: true, managed_decision: true, response_change: true
  @tag :managed_decision_response_current
  test "a current root accepts the held decision response", c do
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    assert :ok = Session.prompt(pid, "Synthetic current held decision")
    assert_receive {:managed_body_sent, server}, 10_000
    send(server, :release_managed_body)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    assert Enum.any?(events, fn event ->
             event["type"] == "extension_action_result" and
               get_in(event, ["request", "op"]) == "decision.create" and
               get_in(event, ["outcome", "status"]) == "ok"
           end)

    assert File.read!(c.trace) =~ "\"relevant\""
    assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
    Task.shutdown(c.provider_server, :brutal_kill)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag registered_main: true, managed_helper: true, managed_decision: true, response_change: true
  @tag :managed_decision_response_change
  test "a root change during decision inference withholds the result", c do
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    assert :ok = Session.prompt(pid, "Synthetic decision response boundary")
    assert_receive {:managed_body_sent, server}, 10_000

    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [
                   %{
                     "key" => "synthetic.changed",
                     "expected_revision" => 0,
                     "value" => %{"text" => "changed"}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    send(server, :release_managed_body)
    assert_receive {:ipse, ^pid, {:done, status}}, 15_000
    assert status in [:ok, :error]
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    assert Enum.any?(
             events,
             &(&1["type"] == "inference_dispatch_intent" and &1["phase"] == "decision.create")
           )

    refute Enum.any?(events, fn event ->
             event["type"] == "extension_action_result" and
               get_in(event, ["request", "op"]) == "decision.create" and
               get_in(event, ["outcome", "status"]) == "ok"
           end)

    refute File.read!(c.trace) =~ "\"relevant\""
    assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
    Task.shutdown(c.provider_server, :brutal_kill)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag registered_main: true, managed_helper: true, managed_decision: true, response_change: true
  @tag :managed_decision_response_revoke
  test "policy revocation during decision inference withholds the result", c do
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    assert :ok = Session.prompt(pid, "Synthetic decision policy boundary")
    assert_receive {:managed_body_sent, server}, 10_000
    assert {:ok, policy} = Consent.snapshot(c.control, c.binding["project_id"])
    assert {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], policy["epoch"])
    send(server, :release_managed_body)
    assert_receive {:ipse, ^pid, {:done, status}}, 15_000
    assert status in [:ok, :error]
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    assert Enum.any?(
             events,
             &(&1["type"] == "inference_dispatch_intent" and &1["phase"] == "decision.create")
           )

    refute Enum.any?(events, fn event ->
             event["type"] == "extension_action_result" and
               get_in(event, ["request", "op"]) == "decision.create" and
               get_in(event, ["outcome", "status"]) == "ok"
           end)

    refute File.read!(c.trace) =~ "\"relevant\""
    assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
    Task.shutdown(c.provider_server, :brutal_kill)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag registered_main: true, managed_helper: true, helper_stale: true
  @tag helper_withdrawal_boundary: true
  test "a stale helper input refuses helper egress and leaves its continuation unknown",
       c do
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    owner = self()

    gate = fn
      count, {:in, {:"$gen_call", _, {:managed_preflight_begin, _, "model.complete"}}}, _ ->
        send(owner, {:helper_preflight_blocked, self()})
        receive do: (:release_helper_preflight -> :ok)
        count + 1

      count, _, _ ->
        count
    end

    on_exit(fn -> send(pid, :release_helper_preflight) end)

    try do
      assert :ok = :sys.install(pid, {gate, 0})
      assert :ok = Session.prompt(pid, "Synthetic stale helper")
      assert_receive {:helper_preflight_blocked, ^pid}, 10_000

      assert {:ok, _} =
               Ipse.Extension.Collection.execute(
                 SemanticAdmission.collection_root(c.home),
                 c.namespace,
                 %{
                   "op" => "commit",
                   "expected_generation" => 0,
                   "advance_floor" => false,
                   "changes" => [
                     %{
                       "key" => "synthetic.changed",
                       "expected_revision" => 0,
                       "value" => %{"text" => "changed"}
                     }
                   ]
                 },
                 Ipse.Usage.id()
               )

      send(pid, :release_helper_preflight)
      assert_stale_helper_recovery(c, pid, "model.complete", "model_request_failed")
    after
      send(pid, :release_helper_preflight)
      Task.shutdown(c.provider_server, :brutal_kill)
    end
  end

  @tag registered_main: true
  @tag helper_withdrawal_boundary: true
  test "a changed managed root withdraws actual worker text before native provider bytes and replays from its prior intent",
       c do
    read = start(c, %{execution_mode: :planning, fixture_export: "inspect", fixture_mode: "read"})
    owner = self()

    gate = fn
      count, {:in, {:"$gen_call", _, {:managed_preflight_begin, _, "model"}}}, _ ->
        if count == 1 do
          send(owner, {:managed_preflight_blocked, self()})
          receive do: (:release_managed_preflight -> :ok)
        end

        count + 1

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(read, {gate, 0})
    assert :ok = Session.prompt(read, "Synthetic changed-root read")
    assert_receive {:managed_preflight_blocked, ^read}, 10_000

    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [
                   %{
                     "key" => "synthetic.changed",
                     "expected_revision" => 0,
                     "value" => %{"text" => "changed"}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    send(read, :release_managed_preflight)
    assert_receive {:ipse, ^read, {:done, :ok}}, 10_000
    [_, {_, request}] = Task.await(c.provider_server, 5000)
    [tool] = Enum.filter(request["messages"], &(&1["role"] == "tool"))
    assert tool["content"] =~ "Managed historical content withdrawn"
    refute tool["content"] =~ "generation"
    state = :sys.get_state(read)

    assert {:ok, []} =
             Ipse.Session.ManagedLineage.dependencies(state.managed_lineage, state.messages)

    assert {:ok, events} = Journal.load(c.dir, state.id)
    intent = Enum.find(events, &(&1["type"] == "managed_preflight_intent"))
    result = Enum.find(events, &(&1["type"] == "managed_preflight_result"))
    assert result["intent_id"] == intent["intent_id"]
    original = Enum.find(events, &(&1["type"] == "extension_invocation_result"))
    refute Ipse.Extension.Invocation.tool_message(original)["content"] =~ "withdrawn"
    assert {:ok, saved} = Ipse.Session.Saved.restore(events, state.id)
    assert saved.messages == state.messages

    tampered =
      Enum.map(events, fn event ->
        if event["type"] == "managed_preflight_result",
          do:
            put_in(event, ["projection", "binding", "tools_sha256"], JSON.sha256("foreign tools")),
          else: event
      end)

    assert {:error, _} = Ipse.Session.Saved.restore(tampered, state.id)
    assert :ok = Session.close_confirmed(read)
  end

  test "a saved grant never admits an ordinary workspace write", c do
    pid = start(c, %{fixture_mode: "ordinary"})
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    refute File.exists?(Path.join(c.cwd, "forbidden"))
    {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
    denied = Enum.find(events, &(&1["type"] == "extension_action_result"))
    assert denied["approval"] == "denied" and denied["outcome"]["status"] == "denied"
  end

  @tag metadata_version: 3,
       registered_main: true,
       capture_write: true,
       registered_capture: true,
       registered_capture_mode: "paged"
  test "SDK2 protected output retains version4 and the same original binding", c do
    pid = start(c, %{fixture_mode: "paged"})
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
    intent = Enum.find(events, &(&1["type"] == "extension_invocation_intent"))
    result = Enum.find(events, &(&1["type"] == "extension_invocation_result"))
    assert result["version"] == 4
    assert result["semantic_binding"] == intent["semantic_binding"]

    publication =
      Enum.find(events, fn event ->
        event["type"] == "extension_action_result" and
          get_in(event, ["request", "op"]) == "collection.managed"
      end)

    assert publication["outcome"]["status"] == "ok"
    assert publication["effect_binding"]["metadata_version"] == 3
    assert :ok = Ipse.Extension.Invocation.validate_events(events)
    assert {:ok, _} = Session.restore_context(events)
    assert [_, {_, continuation}] = Task.await(c.provider_server, 5000)
    assert Enum.any?(continuation["messages"], &(&1["role"] == "tool"))
  end

  test "a selected operator command uses its own protected outer receipt", c do
    pid = start(c)

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__capture", %{"mode" => "ordinary"})

    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
    intent = Enum.find(events, &(&1["type"] == "extension_invocation_intent"))
    assert intent["version"] == 3 and intent["approval"] == "saved_consent"
    assert intent["descriptor"]["stage"] == "invoke.command"
    assert intent["parent_call_id"] == nil
    assert :ok = Ipse.Extension.Invocation.validate_events(events)
    assert {:ok, _} = Session.restore_context(events)
    refute File.exists?(Path.join(c.cwd, "forbidden"))
  end

  @tag metadata_version: 3,
       registered_main: true,
       capture_write: true,
       registered_capture: true,
       registered_capture_no_continuation: true,
       registered_capture_mode: "hold"
  test "revocation after worker entry is rechecked before collection reservation", c do
    pid = start(c, %{fixture_mode: "hold"})
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    await_marker(c.trace, "held\n", 300)
    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], snapshot["epoch"])
    assert_receive {:ipse, ^pid, {:done, :error}}, 10_000
    {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    commit =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "request", "op"]) == "commit")
      )

    assert commit["outcome"] == %{
             "status" => "failed",
             "value" => %{"code" => "collection_consent_denied"}
           }

    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    assert snapshot["operations"] == %{}
    assert Enum.count(events, &(&1["type"] == "inference_dispatch_intent")) == 1
    assert :ok = Ipse.Extension.Actions.validate_events(events)
    assert {:ok, _} = Session.restore_context(events)
    assert [_] = Task.await(c.provider_server, 5000)
  end

  test "interrupted protected outer remains unknown and never replays on resume", c do
    pid = start(c, %{fixture_mode: "hold"})
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    await_marker(c.trace, "held\n", 300)
    id = Session.info(pid).id
    assert :ok = Session.cancel(pid)
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.dir, id)

    assert Enum.any?(
             events,
             &(&1["type"] == "extension_invocation_intent" and &1["version"] == 3)
           )

    refute Enum.any?(events, &(&1["type"] == "extension_invocation_result"))
    assert {:ok, _} = Session.restore_context(events)
    before = File.read!(c.trace)
    resumed = start(c, %{}, id)
    assert File.read!(c.trace) == before
    assert :ok = Session.close_confirmed(resumed)
  end

  @tag metadata_version: 3,
       registered_main: true,
       capture_write: true,
       registered_capture: true
  test "ambiguous reviewed publication mappings refuse rather than choosing a stronger operation",
       c do
    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    policy = snapshot["policy"]
    {:ok, _, descriptor} = Catalog.lookup(c.config, "invoke.tool", "ext__capture__capture")

    mapping =
      Enum.find(
        policy["settings"]["effects"],
        &(&1["class"] == "collection.publish" and &1["outer_sha256"] == JSON.digest([descriptor]))
      )

    effects =
      sort_mappings(
        policy["settings"]["effects"] ++ [Map.put(mapping, "operation", "notes.ambiguous")]
      )

    policy =
      policy
      |> put_in(["settings", "effects"], effects)
      |> Map.put(
        "operations",
        effects |> Enum.map(& &1["operation"]) |> Enum.uniq() |> Enum.sort()
      )

    assert SemanticConsent.policy?(policy)

    {:ok, _} =
      Consent.replace(
        c.control,
        c.binding["project_id"],
        snapshot["epoch"],
        policy,
        System.system_time(:millisecond)
      )

    {:ok, selected} = Ipse.Config.Semantics.selection(policy)
    pid = start(c, %{semantic_selections: selected})
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    commit =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "request", "op"]) == "commit")
      )

    assert commit["outcome"] == %{
             "status" => "failed",
             "value" => %{"code" => "collection_consent_denied"}
           }

    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    assert snapshot["operations"] == %{}
    assert [_, _] = Task.await(c.provider_server, 5000)
  end

  @tag publication_accounting: true,
       metadata_version: 3,
       registered_main: true,
       capture_write: true,
       registered_capture_modes: ["capture", "conflict_unobserved"]
  test "a known conflict is recorded and conservatively settled once without retry", c do
    first = start(c)
    assert :ok = Session.prompt(first, "Synthetic café observation")
    assert_receive {:ipse, ^first, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(first)
    second = start(c, %{fixture_mode: "conflict_unobserved"})
    assert :ok = Session.prompt(second, "Synthetic café observation")
    assert_receive {:ipse, ^second, {:done, :ok}}, 10_000
    {:ok, events} = Journal.load(c.dir, Session.info(second).id)

    commits =
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "request", "op"]) == "commit")
      )

    assert [commit] = commits
    assert commit["outcome"]["status"] == "conflict"
    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    assert snapshot["operations"][commit["operation_id"]]["status"] == "settled"

    assert snapshot["operations"][commit["operation_id"]]["actual"] ==
             Ipse.Extension.ManagedCollectionCall.reservation(commit["request"])

    assert map_size(snapshot["operations"]) == 2
    assert %{"generation" => 1, "floor" => 1} = collection_read(c, %{"op" => "snapshot"})
    assert length(Task.await(c.provider_server, 5000)) == 4
    assert {:ok, _} = Session.restore_context(events)
    assert :ok = Session.close_confirmed(second)
  end

  @tag publication_accounting: true,
       metadata_version: 3,
       registered_main: true,
       capture_write: true,
       registered_capture_count: 2
  test "successive protected saves settle measured input and release only verified unused input",
       c do
    {:ok, initial} = Consent.snapshot(c.control, c.binding["project_id"])
    policy = put_in(initial["policy"], ["limits", "input_bytes"], 40_000)

    assert {:ok, _} =
             Consent.replace(
               c.control,
               c.binding["project_id"],
               initial["epoch"],
               policy,
               System.system_time(:millisecond)
             )

    assert {:ok, selection} = Ipse.Config.Semantics.selection(policy)
    c = put_in(c, [:config, :semantic_selections], selection)

    saves =
      for _ <- 1..2 do
        before = collection_read(c, %{"op" => "snapshot"})

        previous =
          collection_read(c, %{
            "op" => "scan",
            "generation" => before["generation"],
            "after" => nil,
            "limit" => 32
          })

        revisions = Map.new(previous["records"], &{&1["key"], &1["revision"]})
        pid = start(c)
        assert :ok = Session.prompt(pid, "Synthetic café observation")
        assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
        {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

        [commit] =
          Enum.filter(
            events,
            &(&1["type"] == "extension_action_result" and
                get_in(&1, ["request", "op"]) == "collection.managed")
          )

        assert commit["outcome"]["status"] == "ok"
        value = commit["outcome"]["value"]
        normalization = value["normalization"]

        assert normalization["version"] == 3

        extra =
          for metadata <- normalization["metadata_changes"] do
            key = metadata["key"]
            stored = collection_read(c, %{"op" => "get", "key" => key})["record"]
            assert metadata["expected_revision"] == Map.get(revisions, key, 0)
            value = if stored, do: stored["value"]

            assert metadata["value_sha256"] ==
                     if(value, do: JSON.sha256(Jason.encode!(value)))

            %{
              "key" => key,
              "expected_revision" => Map.get(revisions, key, 0),
              "value" => value
            }
          end

        normalized = Map.update!(commit["request"]["request"], "changes", &(&1 ++ extra))
        assert value["receipt"]["request_sha256"] == JSON.digest([normalized])

        expected =
          byte_size(Jason.encode!(commit["request"])) + byte_size(Jason.encode!(normalized)) -
            byte_size(Jason.encode!(commit["request"]["request"])) +
            byte_size(Jason.encode!(normalization))

        {:ok, control} = Consent.snapshot(c.control, c.binding["project_id"])
        settled = control["operations"][commit["operation_id"]]
        assert settled["status"] == "settled"
        assert settled["actual"]["input_bytes"] == expected
        reserved = Ipse.Extension.ManagedCollectionCall.reservation(commit["request"])
        assert expected < reserved["input_bytes"]
        assert Map.delete(settled["actual"], "input_bytes") == Map.delete(reserved, "input_bytes")
        assert :ok = Session.close_confirmed(pid)
        {expected, reserved["input_bytes"]}
      end

    [{first_actual, first_reserved}, {_, second_reserved}] = saves
    assert first_actual + second_reserved <= 40_000
    assert first_reserved + second_reserved > 40_000
    assert length(Task.await(c.provider_server, 5000)) == 4
  end

  @tag publication_fault: true, metadata_version: 3
  test "native loss after normalization does not refund or publish a successful managed result",
       c do
    owner = self()
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:ipse, :extension, :collection, :staged],
        &__MODULE__.fence_native_publication/4,
        owner
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    pid = start(c)
    id = Session.info(pid).id
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive :native_publication_fenced, 10_000
    assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
    {:ok, events} = Journal.load(c.dir, id)

    [commit] =
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "op"]) == "collection.managed")
      )

    assert commit["outcome"]["status"] == "unknown"
    {:ok, control} = Consent.snapshot(c.control, c.binding["project_id"])
    operation = control["operations"][commit["operation_id"]]
    assert operation["status"] in ~w(publishing unknown)
    assert operation["actual"] == nil

    assert operation["reserved"] ==
             Ipse.Extension.ManagedCollectionCall.reservation(commit["request"])

    assert collection_read(c, %{"op" => "snapshot"})["generation"] == 0
  end

  def fence_native_publication(_, _, _, owner) do
    case Process.get({Ipse.Extension.Collection, :lock_held}) do
      %{port: port} ->
        send(owner, :native_publication_fenced)
        Port.close(port)

      _ ->
        :ok
    end
  end

  @tag metadata_version: 3
  test "V3 loss of the native owner during first-publication postproof keeps the outcome unknown",
       c do
    owner = self()
    handler = {__MODULE__, make_ref()}
    stage = :atomics.new(1, [])

    :ok =
      :telemetry.attach_many(
        handler,
        [
          [:ipse, :extension, :collection, :staged],
          [:ipse, :extension, :collection, :view_read]
        ],
        &__MODULE__.fence_first_postproof/4,
        {owner, stage}
      )

    try do
      pid = start(c)
      id = Session.info(pid).id
      assert :ok = Session.prompt(pid, "Synthetic café observation")
      assert_receive {:first_postproof_fenced, true}, 15_000
      assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
      {:ok, events} = Journal.load(c.dir, id)

      [event] =
        Enum.filter(
          events,
          &(&1["type"] == "extension_action_result" and
              get_in(&1, ["request", "op"]) == "collection.managed")
        )

      assert event["outcome"]["status"] == "unknown"
      {:ok, control} = Consent.snapshot(c.control, c.binding["project_id"])
      operation = control["operations"][event["operation_id"]]
      assert operation["status"] in ~w(publishing unknown)
      assert operation["actual"] == nil and operation["receipt"] == nil

      assert operation["reserved"] ==
               Ipse.Extension.ManagedCollectionCall.reservation(event["request"])

      assert collection_read(c, %{"op" => "snapshot"})["generation"] == 1

      state =
        c.home |> Path.join("project-identities/index.json") |> File.read!() |> Jason.decode!()

      assert state["domain_keys"][c.binding["project_id"]]["namespaces"][c.namespace]["state"] ==
               "prepared"

      before = File.read!(c.trace)
      assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(pid)
      refute Process.alive?(pid)
      resumed = start(c, %{}, id)
      assert :ok = Session.close_confirmed(resumed)
      assert File.read!(c.trace) == before
      {:ok, after_control} = Consent.snapshot(c.control, c.binding["project_id"])
      assert after_control["operations"][event["operation_id"]] == operation
    after
      :telemetry.detach(handler)
    end
  end

  def fence_first_postproof(
        [:ipse, :extension, :collection, :staged],
        _,
        _,
        {_, stage}
      ) do
    :atomics.put(stage, 1, 1)
  end

  def fence_first_postproof(
        [:ipse, :extension, :collection, :view_read],
        %{records: records},
        _,
        {owner, stage}
      )
      when records >= 3 do
    if :atomics.compare_exchange(stage, 1, 1, 2) == :ok do
      case Process.get({Ipse.Extension.Collection, :lock_held}) do
        %{port: port} -> send(owner, {:first_postproof_fenced, Port.close(port)})
        _ -> send(owner, {:first_postproof_fenced, false})
      end
    end
  end

  def fence_first_postproof(_, _, _, _), do: :ok

  for version <- [2, 3] do
    @tag metadata_version: version
    test "V#{version} outer Identity loss after checked deferred publication retains full liability across inert resume",
         c do
      owner = self()

      tracer =
        spawn_link(fn ->
          Process.flag(:priority, :high)
          send(owner, :settlement_tracer_ready)
          trace_identity_completion(owner, %{})
        end)

      assert_receive :settlement_tracer_ready

      assert :erlang.trace_pattern(
               {Consent, :publish_deferred, 5},
               [{:_, [], [{:return_trace}]}],
               [
                 :local
               ]
             ) == 1

      :erlang.trace(:all, true, [:call, {:tracer, tracer}])
      handler = {__MODULE__, make_ref()}

      :ok =
        :telemetry.attach(
          handler,
          [:ipse, :extension, :collection, :staged],
          &__MODULE__.observe_settlement_port/4,
          tracer
        )

      try do
        pid = start(c)
        id = Session.info(pid).id
        assert :ok = Session.prompt(pid, "Synthetic café observation")
        assert_receive {:identity_completion_fenced, true, packet}, 15_000
        assert packet["version"] === 1
        assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
        {:ok, events} = Journal.load(c.dir, id)

        [event] =
          Enum.filter(
            events,
            &(&1["type"] == "extension_action_result" and
                get_in(&1, ["request", "op"]) == "collection.managed")
          )

        assert event["outcome"]["status"] == "unknown"
        {:ok, control} = Consent.snapshot(c.control, c.binding["project_id"])
        operation = control["operations"][event["operation_id"]]
        assert operation["status"] in ~w(publishing unknown)
        assert operation["actual"] == nil and operation["receipt"] == nil

        assert operation["reserved"] ==
                 Ipse.Extension.ManagedCollectionCall.reservation(event["request"])

        assert packet["actual"]["input_bytes"] < operation["reserved"]["input_bytes"]
        assert collection_read(c, %{"op" => "snapshot"})["generation"] == 1

        if c[:metadata_version] == 3 do
          state =
            c.home
            |> Path.join("project-identities/index.json")
            |> File.read!()
            |> Jason.decode!()

          assert state["domain_keys"][c.binding["project_id"]]["namespaces"][c.namespace]["state"] ==
                   "prepared"
        end

        before = File.read!(c.trace)
        assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(pid)
        refute Process.alive?(pid)
        resumed = start(c, %{}, id)
        assert :ok = Session.close_confirmed(resumed)
        assert File.read!(c.trace) == before
        {:ok, after_control} = Consent.snapshot(c.control, c.binding["project_id"])
        assert after_control["operations"][event["operation_id"]] == operation
      after
        :telemetry.detach(handler)
        :erlang.trace(:all, false, [:call])
        :erlang.trace_pattern({Consent, :publish_deferred, 5}, false, [:local])
        if Process.alive?(tracer), do: send(tracer, :stop)
      end
    end
  end

  def observe_settlement_port(_, _, _, tracer) do
    case Process.get({Ipse.Extension.Collection, :lock_held}) do
      %{port: port} -> send(tracer, {:settlement_native_port, self(), port})
      _ -> :ok
    end
  end

  defp trace_identity_completion(owner, ports) do
    receive do
      {:settlement_native_port, pid, port} ->
        trace_identity_completion(owner, Map.put(ports, pid, port))

      {:trace, pid, :return_from, {Consent, :publish_deferred, 5},
       {:ok, %{"version" => 1} = packet}} ->
        case Map.fetch(ports, pid) do
          {:ok, port} -> send(owner, {:identity_completion_fenced, Port.close(port), packet})
          :error -> send(owner, :missing_settlement_native_port)
        end

      :stop ->
        :ok

      _ ->
        trace_identity_completion(owner, ports)
    after
      30_000 -> exit(:settlement_trace_timeout)
    end
  end

  defp collection_read(c, request) do
    assert {:ok, value} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               request,
               Ipse.Usage.id()
             )

    value
  end

  @tag publication_fault: true, metadata_version: 3
  test "owner loss during protected publication retains liability and cannot publish after cleanup",
       c do
    pid = start(c, %{fixture_mode: "hold"})
    state = :sys.get_state(pid)
    guard = Process.monitor(state.lock_guard)
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    await_marker(c.trace, "held\n", 300)
    owner = self()

    assert :ok = :sys.install(pid, {publication_gate(owner, 3), 0})
    assert_receive {:publication_query_blocked, _, _}, 5000
    control_file = Path.join([c.control, c.binding["project_id"], "control.json"])
    publishing = await_publication(control_file, 300)
    assert publishing["status"] == "publishing"
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 2000
    assert_receive {:DOWN, ^guard, :process, _, _}, 10_000
    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    operation = snapshot["operations"][publishing["id"]]
    assert operation["status"] in ~w(publishing unknown)
    assert operation["actual"] == nil and operation["receipt"] == nil
    assert operation["reserved"] == publishing["reserved"]
    assert operation["reserved"]["operations"] == 1

    assert {:ok, stored} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{"op" => "snapshot"},
               Ipse.Usage.id()
             )

    assert stored["generation"] == 0 and stored["floor"] == 0
    assert {:ok, events} = Journal.load(c.dir, state.id)
    assert {:ok, saved} = Ipse.Session.Saved.restore(events, state.id)
    before = File.read!(c.trace)
    path = Path.join(c.dir, state.id <> ".jsonl")
    journal = File.read!(path)
    resumed = start(c, %{}, state.id)
    assert Session.info(resumed).phase == :idle
    assert :sys.get_state(resumed).messages == saved.messages
    assert_idle_resume_journal(path, journal, state.id)
    assert :ok = Session.close_confirmed(resumed)
    assert File.read!(c.trace) == before
    assert {:ok, after_resume} = Consent.snapshot(c.control, c.binding["project_id"])
    assert after_resume["operations"][publishing["id"]] == operation
  end

  @tag publication_fault: true,
       metadata_version: 3,
       registered_main: true,
       capture_write: true,
       registered_capture_mode: "hold"
  test "an unrelated caller cannot use the actual current collection action or stale job reference",
       c do
    pid = start(c, %{fixture_mode: "hold"})
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    await_marker(c.trace, "held\n", 300)
    assert :ok = :sys.install(pid, {publication_gate(self()), 0})
    assert_receive {:publication_query_blocked, ref, intent}, 5000

    foreign =
      Task.async(fn ->
        GenServer.call(pid, {:extension_collection_sources, ref, intent}, 5000)
      end)

    stale =
      Task.async(fn ->
        GenServer.call(pid, {:extension_collection_sources, make_ref(), intent}, 5000)
      end)

    changed =
      Task.async(fn ->
        GenServer.call(
          pid,
          {:extension_collection_sources, ref, Map.put(intent, "operation_id", Ipse.Usage.id())},
          5000
        )
      end)

    await_queued(pid, [foreign.pid, stale.pid, changed.pid], 300)
    send(pid, :release_publication)

    for task <- [foreign, stale, changed],
        do: assert({:error, :collection_source_refused} = Task.await(task, 5000))

    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    result =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and &1["operation_id"] == intent["operation_id"])
      )

    assert result["outcome"]["status"] == "ok"
  end

  defp publication_gate(owner, query \\ 2) do
    fn
      count, {:in, {:"$gen_call", _, {:extension_collection_sources, ref, intent}}}, _ ->
        if get_in(intent, ["request", "request", "op"]) == "commit" do
          if count + 1 == query do
            send(owner, {:publication_query_blocked, ref, intent})
            receive do: (:release_publication -> :ok)
          end

          count + 1
        else
          count
        end

      count, _, _ ->
        count
    end
  end

  defp await_queued(_, _, 0),
    do: flunk("foreign proof queries did not reach the actual Session queue")

  defp await_queued(pid, callers, remaining) do
    {:messages, messages} = Process.info(pid, :messages)

    queued =
      Enum.flat_map(messages, fn
        {:"$gen_call", {caller, _}, {:extension_collection_sources, _, _}} -> [caller]
        _ -> []
      end)

    if Enum.all?(callers, &(&1 in queued)),
      do: :ok,
      else:
        (
          Process.sleep(10)
          await_queued(pid, callers, remaining - 1)
        )
  end

  defp sort_mappings(effects),
    do: Enum.sort_by(effects, &{&1["operation"], &1["class"], &1["outer_sha256"], &1["inner_op"]})

  defp await_publication(path, 0) do
    value =
      case File.read(path) do
        {:ok, bytes} -> Jason.decode!(bytes)
        error -> error
      end

    flunk("protected publishing receipt was not reached: #{inspect(value, limit: 20)}")
  end

  defp await_publication(path, remaining) do
    receipt =
      with {:ok, bytes} <- File.read(path),
           {:ok, value} <- Jason.decode(bytes),
           do:
             Enum.find_value(value["operations"], fn {_, receipt} ->
               if receipt["status"] == "publishing", do: receipt
             end)

    if is_map(receipt),
      do: receipt,
      else:
        (
          Process.sleep(10)
          await_publication(path, remaining - 1)
        )
  end

  defp await_marker_count(_, _, _, 0), do: flunk("synthetic worker barriers were not reached")

  defp await_marker_count(path, marker, count, remaining) do
    if File.exists?(path) and length(String.split(File.read!(path), marker)) - 1 >= count do
      :ok
    else
      Process.sleep(10)
      await_marker_count(path, marker, count, remaining - 1)
    end
  end

  defp native_literal_seed(root) do
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    driver = Path.join(root, "pty")

    assert {"", 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 Path.expand("test/support/operator_pty.rs"),
                 "-o",
                 driver
               ],
               stderr_to_stdout: true
             )

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    {output, status} =
      System.cmd(
        driver,
        ["--assertion", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++ [Path.expand("test/support/managed_literal_ab_seed.exs"), root, "seed"],
        cd: root,
        stderr_to_stdout: true
      )

    File.write!(Path.join(root, "native-seed.log"), output)
    IO.puts("WORKER_INHERITED_ROOT=" <> root)
    assert status == 0, output
    assert File.regular?(Path.join(root, "literal-ab-seed.json"))
  end

  defp await_worker_input_settlement(_, 0),
    do: flunk("the held worker's original read input did not settle")

  defp await_worker_input_settlement(pid, remaining) do
    state = :sys.get_state(pid)

    if state.invocation.worker_input == nil and state.share_barrier == nil do
      result = List.last(state.invocation.results)
      assert result["request"]["op"] == "collection.call"
      assert {:ok, events} = Journal.load(state.dir, state.id)
      payload_sha = JSON.digest([Ipse.Extension.Actions.resume(result)])

      [input] =
        Enum.filter(
          events,
          &(&1["type"] == "worker_input_intent" and
              &1["payload_sha256"] == payload_sha)
        )

      assert Enum.any?(
               events,
               &(&1["type"] == "worker_input_result" and
                   &1["input_id"] == input["input_id"] and &1["status"] == "delivered")
             )

      :ok
    else
      Process.sleep(10)
      await_worker_input_settlement(pid, remaining - 1)
    end
  end

  defp await_marker(_, _, 0), do: flunk("synthetic worker marker was not reached")

  defp await_marker(path, marker, remaining) do
    if File.exists?(path) and String.contains?(File.read!(path), marker),
      do: :ok,
      else:
        (
          Process.sleep(10)
          await_marker(path, marker, remaining - 1)
        )
  end
end
