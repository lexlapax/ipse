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
    assert runtime.max_response_bytes == 65_536
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
          Map.put(proposed, "api_key", "synthetic")
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
