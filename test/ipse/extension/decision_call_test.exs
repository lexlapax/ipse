defmodule Ipse.Extension.DecisionCallTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.DecisionCall
  alias Ipse.Config.Decisions

  defp request,
    do: %{
      "op" => "decision.create",
      "version" => 1,
      "profile" => "test",
      "input" => "fresh development fixture",
      "questions" => [
        %{"id" => "relevant", "type" => "predicate", "instructions" => "Is this relevant?"}
      ],
      "timeout_ms" => 2000
    }

  defp config,
    do: %{
      extensions: [%{identity: %{"capabilities" => ["host.decision"]}}],
      decision_profiles: %{
        "test" => %{
          "operation" => "decision",
          "provider" => "openai",
          "model" => "gpt-6-luna",
          "service_id" => "openai"
        }
      }
    }

  test "effect request and binding refuse authority fields and out-of-subset requests" do
    assert :ok = DecisionCall.validate(request())
    assert {:ok, binding} = DecisionCall.binding(config(), request())
    assert DecisionCall.valid_binding?(binding, request())

    assert DecisionCall.valid_binding?(binding, request(), %{
             "decision_profiles" => Decisions.snapshot(config())
           })

    refute DecisionCall.valid_binding?(
             put_in(binding, ["execution", "model"], "replacement"),
             request()
           )

    refute DecisionCall.valid_binding?(binding, %{request() | "profile" => "other"})
    assert {:error, _} = DecisionCall.validate(Map.put(request(), "approved", true))
    oversized = %{request() | "input" => String.duplicate("a", 8193)}
    assert :ok = Ipse.Decision.validate_request(DecisionCall.neutral(oversized))
    assert {:error, _} = DecisionCall.validate(oversized)
    assert {:error, _} = DecisionCall.validate(%{request() | "timeout_ms" => 0})

    score = %{
      request()
      | "questions" => [
          %{
            "id" => "score",
            "type" => "score",
            "instructions" => "Evaluate.",
            "levels" => Enum.map(1..11, &Integer.to_string/1)
          }
        ]
    }

    assert :ok = DecisionCall.validate(score)
    assert {:error, _} = DecisionCall.binding(config(), score)
  end

  test "approval binds the complete operation and disclosures to one effect" do
    {:ok, binding} = DecisionCall.binding(config(), request())

    proposed = %{
      "extension" => "fixture",
      "artifact_sha256" => String.duplicate("a", 64),
      "namespace" => String.duplicate("b", 32),
      "request" => request(),
      "execution" => binding["execution"],
      "destination" => binding["destination"],
      "effect_binding" => binding
    }

    assert DecisionCall.delegated_approval?("extension:decision.create", proposed)
    refute DecisionCall.delegated_approval?("extension:model.complete", proposed)

    refute DecisionCall.delegated_approval?(
             "extension:decision.create",
             put_in(proposed, ["execution", "service_id"], "replacement")
           )

    refute DecisionCall.delegated_approval?(
             "extension:decision.create",
             Map.put(proposed, "extra", true)
           )
  end
end
