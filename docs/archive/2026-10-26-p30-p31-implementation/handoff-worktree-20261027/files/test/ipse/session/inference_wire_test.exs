defmodule Ipse.Session.InferenceWireTest do
  use ExUnit.Case, async: true
  alias Ipse.Session.InferenceWire

  defp text_runtime do
    %{provider: :ollama, model: "fixture", base_url: "http://127.0.0.1:11434", timeout_ms: 4000}
  end

  defp embed_request do
    %{
      "op" => "embedding.create",
      "version" => 1,
      "profile" => "embed",
      "inputs" => ["alpha"],
      "timeout_ms" => 4000
    }
  end

  defp decision_request do
    %{
      "op" => "decision.create",
      "version" => 1,
      "profile" => "decision",
      "input" => "fresh fixture",
      "questions" => [
        %{"id" => "relevant", "type" => "predicate", "instructions" => "Is this relevant?"}
      ],
      "timeout_ms" => 4000
    }
  end

  test "main, compaction, and helper text derive exact native hashes from their host view" do
    input = [%{"role" => "user", "content" => "alpha"}]
    config = text_runtime()
    {:ok, body} = Jason.encode(Ipse.Provider.Ollama.request_body(config, input, []))

    expected = %{
      "kind" => "text",
      "provider" => "ollama",
      "model" => "fixture",
      "target_sha256" => Ipse.JSON.sha256(config.base_url <> "/api/chat"),
      "body_sha256" => Ipse.JSON.sha256(body)
    }

    for phase <- ["model", "compaction", "model.complete"] do
      assert {:ok, ^expected} = InferenceWire.derive(phase, config, input, [])
    end

    assert {:ok, altered} =
             InferenceWire.derive("model", config, [%{"role" => "user", "content" => "beta"}], [])

    refute InferenceWire.matches?(expected, altered)

    for key <- Map.keys(expected),
        do: refute(InferenceWire.matches?(expected, Map.put(expected, key, "forged")))

    refute InferenceWire.matches?(expected, Map.put(expected, "extra", true))
    refute InferenceWire.matches?(%{}, %{})
    assert InferenceWire.matches?(expected, expected)
  end

  test "compaction and helper cannot acquire tool definitions, and invalid routes fail closed" do
    input = [%{"role" => "user", "content" => "alpha"}]
    config = text_runtime()

    for phase <- ["compaction", "model.complete"] do
      assert {:error, _} = InferenceWire.derive(phase, config, input, [%{"type" => "function"}])
    end

    for bad <- [
          %{config | provider: :openai},
          Map.put(config, :api_key, "secret"),
          %{config | base_url: "http://example.com"},
          %{config | timeout_ms: 0},
          Map.put(config, :max_response_bytes, 0)
        ] do
      assert {:error, _} = InferenceWire.derive("model", bad, input, [])
    end

    assert {:error, _} = InferenceWire.derive("unrecognized", config, input, [])
  end

  test "embedding and decision helper facts derive from validated host requests" do
    er = embed_request()

    ec =
      Map.merge(text_runtime(), %{operation: :embedding, dimensions: 2, dimension_mode: "native"})

    assert {:ok, ef} = InferenceWire.derive("embedding.create", ec, er, [])
    {:ok, eb} = Ipse.Provider.Embedding.request_body(ec, er["inputs"])
    assert ef["body_sha256"] == Ipse.JSON.sha256(Jason.encode!(eb))
    assert ef["target_sha256"] == Ipse.JSON.sha256(ec.base_url <> "/api/embed")

    assert {:error, _} =
             InferenceWire.derive("embedding.create", ec, Map.put(er, "inputs", []), [])

    assert {:error, _} = InferenceWire.derive("embedding.create", ec, er, [%{}])

    dr = decision_request()

    dc = %{
      provider: :system_one_compatible,
      model: "fixture",
      expected_model: "fixture",
      base_url: "http://127.0.0.1:8080",
      timeout_ms: 4000
    }

    assert {:ok, df} = InferenceWire.derive("decision.create", dc, dr, [])

    {:ok, db} =
      Ipse.Provider.Decision.encode(
        :system_one,
        Ipse.Extension.DecisionCall.neutral(dr),
        dc.model
      )

    assert df["body_sha256"] == Ipse.JSON.sha256(Jason.encode!(db))
    assert df["target_sha256"] == Ipse.JSON.sha256(dc.base_url <> "/systemone")

    assert {:error, _} =
             InferenceWire.derive(
               "decision.create",
               %{dc | base_url: "https://example.com"},
               dr,
               []
             )

    assert {:error, _} =
             InferenceWire.derive("decision.create", dc, Map.put(dr, "op", "model.complete"), [])
  end

  test "wire equality alone does not bind phase, native dimensions or timeout" do
    config = text_runtime()
    messages = [%{"role" => "user", "content" => "alpha"}]
    assert {:ok, main} = InferenceWire.derive("model", config, messages, [])
    assert {:ok, helper} = InferenceWire.derive("model.complete", config, messages, [])
    assert InferenceWire.matches?(main, helper)

    embedding =
      Map.merge(config, %{operation: :embedding, dimensions: 2, dimension_mode: "native"})

    assert {:ok, first} = InferenceWire.derive("embedding.create", embedding, embed_request(), [])

    assert {:ok, changed} =
             InferenceWire.derive(
               "embedding.create",
               %{embedding | dimensions: 3, timeout_ms: 3000},
               embed_request(),
               []
             )

    assert InferenceWire.matches?(first, changed)
  end

  test "compaction derives from the Session's reconstructed dispatch view" do
    runtime = text_runtime()
    messages = [%{"role" => "user", "content" => "summarize the retained prefix"}]
    admission = %{"request_id" => "synthetic"}

    state = %{
      phase: :compaction,
      active_request: admission,
      config: runtime,
      compaction: %{summary_messages: messages}
    }

    assert {:ok, selected, ^messages, [], ^admission} =
             Ipse.Session.Turn.dispatch_view(state, "compaction")

    assert {:ok, facts} = InferenceWire.derive("compaction", selected, messages, [])
    {:ok, bytes} = Jason.encode(Ipse.Provider.Ollama.request_body(selected, messages, []))
    assert facts["body_sha256"] == Ipse.JSON.sha256(bytes)
    refute selected == runtime
  end
end
