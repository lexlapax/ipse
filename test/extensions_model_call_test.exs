defmodule Ipse.Extensions.ModelCallTest do
  use ExUnit.Case, async: true
  alias Ipse.Extensions.{ModelCall, Catalog, Operation}

  defp request do
    %{
      "op" => "model.complete",
      "version" => 1,
      "profile" => "extract",
      "instruction" => "Extract names.",
      "input" => "Synthetic input",
      "max_output_bytes" => 1024,
      "timeout_ms" => 5000
    }
  end

  defp config do
    %{
      provider: :openai,
      model: "main",
      max_output_tokens: 64,
      timeout_ms: 2000,
      extensions: [%{identity: %{"capabilities" => ["host.model"]}}],
      profiles: %{
        "extract" => %{
          "provider" => "ollama",
          "model" => "local",
          "max_output_tokens" => 32,
          "timeout_ms" => 4000,
          "base_url" => "http://localhost:1234"
        }
      },
      api_key: "synthetic-main-only",
      provider_module: __MODULE__,
      messages: [%{"content" => "unrelated private history"}]
    }
  end

  defp structured do
    Map.merge(request(), %{
      "version" => 2,
      "response_schema" => %{
        "type" => "object",
        "properties" => %{
          "names" => %{"type" => "array", "maxItems" => 1, "items" => %{"type" => "string"}}
        },
        "required" => ["names"],
        "additionalProperties" => false
      }
    })
  end

  test "structured requests use a closed v2 variant within the unchanged whole-request bounds" do
    assert :ok = ModelCall.validate(structured())

    for invalid <- [
          Map.delete(structured(), "response_schema"),
          Map.put(structured(), "version", 1),
          Map.put(structured(), "version", 2.0),
          Map.put(structured(), "version", 4),
          Map.put(structured(), "response_schema", nil),
          Map.put(structured(), "response_schema", %{
            "type" => "array",
            "items" => %{"type" => "string"}
          }),
          put_in(structured(), ["response_schema", "type"], ["object", "null"]),
          put_in(structured(), ["response_schema", "$ref"], "https://example.invalid/schema"),
          put_in(structured(), ["response_schema", "properties", "names", "uniqueItems"], true),
          put_in(structured(), ["response_schema", "description"], String.duplicate("x", 8193)),
          Map.put(structured(), "response_format", "json")
        ],
        do: assert({:error, _} = ModelCall.validate(invalid))

    # V2 holds schema alongside input; v1 retains its original ceiling.
    padded =
      structured()
      |> put_in(["response_schema", "description"], String.duplicate("x", 5000))
      |> Map.put("input", String.duplicate("x", 4096))
      |> Map.put("instruction", String.duplicate("x", 1900))

    assert :ok = ModelCall.validate(padded)
    room = 12_288 - byte_size(Jason.encode!(padded))

    exact =
      update_in(padded, ["response_schema", "description"], &(&1 <> String.duplicate("x", room)))

    assert byte_size(Jason.encode!(exact)) == 12_288
    assert :ok = ModelCall.validate(exact)

    assert {:error, _} =
             ModelCall.validate(
               update_in(exact, ["response_schema", "description"], &(&1 <> "x"))
             )
  end

  test "v3 extends only the structured deadline and retains legacy request limits" do
    long = Map.merge(structured(), %{"version" => 3, "timeout_ms" => 600_000})
    assert :ok = ModelCall.validate(long)

    for legacy <- [request(), structured()] do
      assert :ok = ModelCall.validate(Map.put(legacy, "timeout_ms", 120_000))
      assert {:error, _} = ModelCall.validate(Map.put(legacy, "timeout_ms", 120_001))
    end

    for invalid <- [
          Map.put(long, "timeout_ms", 600_001),
          Map.put(long, "timeout_ms", 999),
          Map.put(long, "version", 3.0),
          Map.delete(long, "response_schema"),
          Map.put(long, "input", String.duplicate("x", 4097)),
          Map.put(long, "max_output_bytes", 8193)
        ],
        do: assert({:error, _} = ModelCall.validate(invalid))

    assert {:ok, runtime, _} = ModelCall.prepare(config(), long)
    assert runtime.extension_response_schema == long["response_schema"]
    assert runtime.timeout_ms == 2000

    admission = %{"request_id" => Ipse.Usage.id(), "attempt_id" => Ipse.Usage.id()}
    record = %{"reported_model" => nil, "usage" => Ipse.Usage.Normalizer.normalize(:ollama, %{})}

    assert {:ok, value} =
             ModelCall.value_from_record(long, admission, record, %{
               "role" => "assistant",
               "content" => ~s({"names":["Ada"]})
             })

    assert ModelCall.valid_outcome?(long, "ok", value, admission["request_id"])

    refute ModelCall.valid_outcome?(
             long,
             "ok",
             Map.put(value, "text", ~s({"names":[1]})),
             admission["request_id"]
           )
  end

  test "explicit model-call override preserves legacy snapshots and narrows by root and request" do
    owner =
      config()
      |> Map.put(:timeout_ms, 600_000)
      |> put_in([:profiles, "extract", "timeout_ms"], 600_000)

    legacy = %{
      "id" => "extract",
      "provider" => "ollama",
      "model" => "local",
      "billing_mode" => "local",
      "endpoint_sha256" => Ipse.JSON.sha256("http://localhost:1234"),
      "reasoning_effort" => nil,
      "max_output_tokens" => 32,
      "timeout_ms" => 120_000
    }

    assert ModelCall.snapshot(owner) == %{"extract" => legacy}

    selected = put_in(owner, [:profiles, "extract", "model_call_timeout_ms"], 480_000)
    long = Map.merge(structured(), %{"version" => 3, "timeout_ms" => 600_000})
    assert {:ok, runtime, execution} = ModelCall.prepare(selected, long)
    assert runtime.timeout_ms == 480_000
    assert execution["timeout_ms"] == 480_000

    assert {:ok, %{timeout_ms: 200_000}, _} =
             ModelCall.prepare(Map.put(selected, :timeout_ms, 200_000), long)

    assert {:ok, %{timeout_ms: 120_000}, _} =
             ModelCall.prepare(Map.delete(selected, :timeout_ms), long)

    assert {:ok, %{timeout_ms: 150_000}, _} =
             ModelCall.prepare(selected, Map.put(long, "timeout_ms", 150_000))

    assert {:ok, %{timeout_ms: 5000}, _} = ModelCall.prepare(selected, structured())

    for invalid <- [nil, 0, 600_001, 120_000.0] do
      assert {:error, _} =
               ModelCall.prepare(
                 put_in(selected, [:profiles, "extract", "model_call_timeout_ms"], invalid),
                 long
               )
    end
  end

  test "structured output is an explicit native selection, never an inherited owner setting" do
    owner =
      config()
      |> Map.put(:extension_response_schema, %{"type" => "string"})
      |> Map.put(:summary_schema, %{})

    assert {:ok, text, original} = ModelCall.prepare(owner, request())
    refute Map.has_key?(text, :extension_response_schema)
    refute Map.has_key?(text, :summary_schema)
    assert {:ok, json, ^original} = ModelCall.prepare(owner, structured())
    assert json.extension_response_schema == structured()["response_schema"]
    assert Map.delete(json, :extension_response_schema) == text

    for provider <- ~w(chatgpt openai anthropic) do
      profile = %{"provider" => provider, "model" => "fixture"}

      selected =
        config() |> Map.delete(:max_output_tokens) |> put_in([:profiles, "extract"], profile)

      assert {:ok, _, _} = ModelCall.prepare(selected, request())
      scope = %{"model_profiles" => ModelCall.snapshot(selected)}
      assert {:error, _} = ModelCall.execution(scope, structured())
      assert {:error, _} = ModelCall.prepare(selected, structured())
    end
  end

  test "raw structured results are independently checked by live derivation and outcome validation" do
    admission = %{"request_id" => Ipse.Usage.id(), "attempt_id" => Ipse.Usage.id()}
    record = %{"reported_model" => nil, "usage" => Ipse.Usage.Normalizer.normalize(:ollama, %{})}

    result = fn text ->
      ModelCall.value_from_record(structured(), admission, record, %{
        "role" => "assistant",
        "content" => text
      })
    end

    raw = " \n{\"names\":[\"Ada\"]}\n"
    assert {:ok, value} = result.(raw)
    assert value["text"] == raw
    assert value["version"] == 1
    assert ModelCall.valid_outcome?(structured(), "ok", value, admission["request_id"])

    for raw <- [
          "",
          "[]",
          "null",
          "{names:[]}",
          ~s({"names":[]}{"names":[]}),
          ~s({"names":[],"names":["Ada"]}),
          ~S({"na\u006des":[],"names":[]}),
          ~s({"names":["Ada","Grace"]}),
          ~s({"names":[1]}),
          ~s({"other":[]}),
          ~s({"names":[],"extra":true}),
          String.duplicate("[", 20) <> String.duplicate("]", 20),
          <<255>>
        ] do
      assert {:failed, %{"code" => "model_response"}} = result.(raw)

      refute ModelCall.valid_outcome?(
               structured(),
               "ok",
               Map.put(value, "text", raw),
               admission["request_id"]
             )
    end
  end

  test "closed request rejects unsupported operations and direct routing or credential overrides" do
    assert :ok = ModelCall.validate(request())
    assert Operation.mutating?(request())
    assert Operation.capability(request()) == "host.model"

    for invalid <- [
          Map.put(request(), "op", "model.embed"),
          Map.put(request(), "version", 1.0),
          Map.put(request(), "version", 2),
          Map.put(request(), "input", ""),
          Map.put(request(), "timeout_ms", 999),
          Map.put(request(), "max_output_bytes", 8193),
          Map.put(request(), "profile", "../extract"),
          Map.put(request(), "profile", " bad"),
          Map.put(request(), "provider", "openai"),
          Map.put(request(), "api_key", "synthetic"),
          Map.put(request(), "base_url", "http://localhost:1234"),
          Map.put(request(), "instruction", String.duplicate("x", 2049)),
          Map.put(request(), "input", String.duplicate("\u0000", 4096))
        ],
        do: assert({:error, _} = ModelCall.validate(invalid))

    assert {:error, _} = Catalog.validate(Catalog.empty(), ["host.model"])
    assert :ok = Catalog.validate(Catalog.empty(), ~w(host.actions host.model))
  end

  test "selected profile narrows limits and never inherits main credentials, implementation or history" do
    selected =
      Map.put(config(), :budget, %{
        "version" => 1,
        "max_output_tokens" => 100,
        "reserve_output_tokens" => 16
      })

    assert {:ok, runtime, facts} = ModelCall.prepare(selected, request())
    assert runtime.provider == :ollama
    assert runtime.model == "local"
    assert runtime.max_output_tokens == 16
    assert runtime.timeout_ms == 2000
    assert runtime.max_response_bytes == 1_048_576
    assert facts["billing_mode"] == "local"
    assert facts["max_output_tokens"] == 16
    refute Map.has_key?(facts, "base_url")
    refute Enum.any?(~w(api_key provider_module messages)a, &Map.has_key?(runtime, &1))
    assert {:error, _} = ModelCall.prepare(config(), Map.put(request(), "profile", "missing"))
    assert nil == ModelCall.snapshot(Map.put(config(), :extensions, []))
  end

  test "delegated model approvals include a closed non-secret destination" do
    assert {:ok, runtime, execution} = ModelCall.prepare(config(), request())
    assert {:ok, destination} = Ipse.Provider.destination(runtime)

    proposed = %{
      "extension" => "fixture",
      "artifact_sha256" => String.duplicate("a", 64),
      "namespace" => Ipse.Usage.id(),
      "request" => request(),
      "execution" => execution,
      "destination" => destination
    }

    assert ModelCall.delegated_approval?("extension:model.complete", proposed)

    for invalid <- [
          Map.delete(proposed, "destination"),
          put_in(proposed, ["destination", "origin"], "https://name@example.invalid"),
          put_in(proposed, ["destination", "target_sha256"], "raw-url"),
          Map.put(proposed, "api_key", "synthetic"),
          put_in(proposed, ["execution", "timeout_ms"], proposed["request"]["timeout_ms"] + 1)
        ],
        do: refute(ModelCall.delegated_approval?("extension:model.complete", invalid))
  end

  test "subscription selection refuses an inherited unsupported output ceiling" do
    config =
      put_in(config(), [:profiles, "extract"], %{
        "provider" => "chatgpt",
        "model" => "gpt-6.1-sol"
      })

    assert {:error, _} = ModelCall.prepare(config, request())

    assert {:ok, runtime, _} =
             ModelCall.prepare(Map.delete(config, :max_output_tokens), request())

    assert runtime.provider == :chatgpt
    assert runtime.execution.role == "extension"
  end

  test "saved execution facts reject malformed types, extra fields and unsupported provider policy" do
    scope = %{"model_profiles" => ModelCall.snapshot(config()), "max_output_tokens" => 64}
    assert {:ok, _} = ModelCall.execution(scope, request())
    profile = scope["model_profiles"]["extract"]

    for invalid <- [
          Map.put(profile, "timeout_ms", "5000"),
          Map.put(profile, "timeout_ms", 0),
          Map.put(profile, "max_output_tokens", 1.0),
          Map.put(profile, "max_output_tokens", "32"),
          Map.put(profile, "billing_mode", "api"),
          Map.put(profile, "endpoint_sha256", "raw-url"),
          Map.put(profile, "provider", "unknown"),
          Map.put(profile, "model", nil),
          Map.put(profile, "reasoning_effort", "high"),
          Map.put(profile, "api_key", "synthetic")
        ] do
      assert {:error, _} =
               ModelCall.execution(
                 put_in(scope, ["model_profiles", "extract"], invalid),
                 request()
               )
    end
  end

  test "a selected local child retains only the host auth reference needed for an explicitly selected subscription helper" do
    config =
      config()
      |> Map.delete(:max_output_tokens)
      |> put_in([:profiles, "extract"], %{"provider" => "ollama", "model" => "local"})
      |> put_in([:profiles, "subscription"], %{"provider" => "chatgpt", "model" => "gpt-6.1-sol"})
      |> Map.put(:auth_dir, "/synthetic-operator-auth")
      |> Map.put(:extensions, [
        %{identity: %{"capabilities" => ["host.model"], "allow_children" => true}}
      ])

    origin = %{
      "parent_session_id" => Ipse.Usage.id(),
      "parent_request_id" => Ipse.Usage.id(),
      "call_id" => "fixture"
    }

    assert {:ok, child} = Ipse.Profiles.child_config(config, origin, %{"profile" => "extract"})
    assert child.provider == :ollama
    refute Map.has_key?(child, :auth_dir)

    assert {:ok, helper, _} =
             ModelCall.prepare(child, Map.put(request(), "profile", "subscription"))

    assert helper.provider == :chatgpt
    assert helper.auth_dir == "/synthetic-operator-auth"
    refute Map.has_key?(helper, :api_key)
    assert helper.delegation_origin == origin
  end
end
