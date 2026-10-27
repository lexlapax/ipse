defmodule Ipse.Extension.SemanticRoutesTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.SemanticRoutes
  alias Ipse.Config.Semantics

  defp selector(operation, profile \\ nil),
    do: %{
      "operation" => operation,
      "profile" => profile,
      "processing_region" => nil,
      "storage_region" => nil,
      "cache_retention" => nil,
      "account_controls" => nil
    }

  defp config do
    %{
      provider: :ollama,
      model: "current-main",
      base_url: "http://127.0.0.1:11434",
      timeout_ms: 120_000,
      max_output_tokens: nil,
      extensions: [%{identity: %{"capabilities" => ~w(host.model host.embedding host.decision)}}],
      model_profiles: %{
        "answer" => %{
          "provider" => "ollama",
          "model" => "local-answer",
          "base_url" => "http://localhost:11434"
        }
      },
      embedding_profiles: %{
        "search" => %{
          "operation" => "embedding",
          "provider" => "ollama",
          "model" => "local-embedding",
          "base_url" => "http://127.0.0.1:11434",
          "dimensions" => 1024,
          "dimension_mode" => "native"
        }
      },
      decision_profiles: %{
        "choose" => %{
          "operation" => "decision",
          "provider" => "system_one_compatible",
          "model" => "selected-decision",
          "expected_model" => "selected-decision",
          "service_id" => "local",
          "base_url" => "http://127.0.0.1:11434/v1"
        }
      },
      inference_services: %{
        "local" => %{
          "version" => 1,
          "origins" => ["http://127.0.0.1:11434", "http://localhost:11434"]
        }
      }
    }
  end

  test "main and each selected named helper derive their actual endpoints without IO" do
    selectors = [
      selector("main"),
      selector("model.complete", "answer"),
      selector("embedding.create", "search"),
      selector("decision.create", "choose")
    ]

    assert {:ok, routes} = SemanticRoutes.resolve(config(), selectors)
    by_operation = Map.new(routes, &{&1["operation"], &1})
    assert by_operation["main"]["model"] == "current-main"
    assert by_operation["main"]["profile"] == nil
    assert by_operation["main"]["endpoint"] == "http://127.0.0.1:11434/api/chat"
    assert by_operation["model.complete"]["model"] == "local-answer"
    assert by_operation["model.complete"]["endpoint"] == "http://localhost:11434/api/chat"
    assert by_operation["embedding.create"]["endpoint"] == "http://127.0.0.1:11434/api/embed"
    assert by_operation["decision.create"]["endpoint"] == "http://127.0.0.1:11434/v1/systemone"
    assert Enum.all?(routes, &(&1["service_id"] == "local" and &1["billing_mode"] == "local"))

    assert {:ok, ^selectors} =
             SemanticRoutes.selectors(
               Enum.map(selectors, &Map.put(&1, "endpoint", "https://forged.invalid"))
             )

    assert {:ok, ^routes} = SemanticRoutes.resolve(config(), selectors)
  end

  test "pre-grant route review reuses aliases or derives exact origin identities without endpoints from JSON" do
    base = Map.put(config(), :inference_services, %{})
    selected = [selector("main")]
    assert {:ok, reviewed} = SemanticRoutes.review(base, selected)
    origin = "http://127.0.0.1:11434"
    id = "origin-" <> binary_part(Ipse.JSON.sha256(origin), 0, 56)
    assert reviewed.registry == %{id => %{"version" => 1, "origins" => [origin]}}
    assert [route] = reviewed.routes
    assert route["service_id"] == id
    assert route["endpoint"] == "http://127.0.0.1:11434/api/chat"
    assert base.inference_services == %{}

    assert {:ok, ^reviewed} =
             SemanticRoutes.review(Map.put(base, :model, "current-main"), selected)

    assert {:ok, aliased} = SemanticRoutes.review(config(), selected)
    assert hd(aliased.routes)["service_id"] == "local"
    assert aliased.registry == config().inference_services

    assert {:error, _} =
             SemanticRoutes.review(base, [
               Map.put(hd(selected), "endpoint", "https://forged.invalid")
             ])

    collision =
      Map.put(base, :inference_services, %{
        id => %{"version" => 1, "origins" => ["https://elsewhere.invalid"]}
      })

    assert {:error, _} = SemanticRoutes.review(collision, selected)
  end

  test "pre-grant review respects closed registry capacity and real named profile selection" do
    services =
      Map.new(
        1..8,
        &{"service-#{&1}", %{"version" => 1, "origins" => ["https://service#{&1}.invalid"]}}
      )

    assert {:error, _} =
             SemanticRoutes.review(Map.put(config(), :inference_services, services), [
               selector("main")
             ])

    assert {:error, _} = SemanticRoutes.review(config(), [selector("model.complete", "missing")])

    assert {:ok, reviewed} =
             SemanticRoutes.review(config(), [
               selector("main"),
               selector("model.complete", "answer")
             ])

    assert Enum.all?(reviewed.routes, &(&1["service_id"] == "local"))
  end

  test "unknown profile, changed current route and unadmitted service aliases fail closed" do
    for {config, selectors} <- [
          {config(), [selector("model.complete", "missing")]},
          {%{config() | inference_services: %{}}, [selector("main")]},
          {%{config() | base_url: "http://127.0.0.1:9999"}, [selector("main")]},
          {put_in(config(), [:decision_profiles, "choose", "service_id"], "other"),
           [selector("decision.create", "choose")]},
          {config(), [selector("main", "answer")]},
          {config(), [selector("main"), selector("main")]},
          {config(), [Map.put(selector("main"), "endpoint", "https://forged.invalid")]}
        ] do
      assert {:error, :semantic_route_unavailable} = SemanticRoutes.resolve(config, selectors)
    end

    config = %{config() | model: "changed-main"}
    assert {:ok, [route]} = SemanticRoutes.resolve(config, [selector("main")])
    assert route["model"] == "changed-main"
  end

  test "review disclosures are labels, and inert demo has no external service requirement" do
    selection = %{selector("main") | "processing_region" => "operator reviewed; unknown"}

    assert {:ok, [route]} =
             SemanticRoutes.resolve(%{provider: :demo, model: "fixture"}, [selection])

    assert route["endpoint"] == "demo://local" and route["billing_mode"] == "none"
    assert route["processing_region"] == "operator reviewed; unknown"
    assert route["service_id"] == "demo"
  end

  test "origin aliases are bounded, unique, canonical and never supplied by project config" do
    services = config().inference_services
    assert :ok = Semantics.validate_services(services)

    assert {:ok, ^services} =
             Semantics.resolve_services([
               %{scope: "operator", data: %{"inference_services" => services}}
             ])

    for entries <- [services, %{}] do
      assert {:error, :inference_services_operator_only} =
               Semantics.resolve_services([
                 %{scope: "project", data: %{"inference_services" => entries}}
               ])
    end

    for registry <- [
          Map.put(services, "duplicate", services["local"]),
          put_in(services, ["local", "version"], 1.0),
          put_in(services, ["local", "origins"], ["http://remote.invalid"]),
          put_in(services, ["local", "origins"], ["https://example.invalid/path"]),
          put_in(services, ["local", "origins"], ["https://user:secret@example.invalid"]),
          put_in(services, ["local", "origins"], ["https://example.invalid?key=secret"]),
          put_in(services, ["local", "origins"], List.duplicate("https://example.invalid", 9))
        ] do
      assert {:error, :invalid_inference_services} = Semantics.validate_services(registry)
    end
  end
end
