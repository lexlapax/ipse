Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule Ipse.Config.GeminiIntegrationTest do
  use ExUnit.Case, async: false
  alias Ipse.Test.ProviderFixture, as: Fixture
  alias Ipse.{Session, Journal}

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-gemini-session-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, state: Path.join(root, "sessions"), home: Path.join(root, "home")}
  end

  defp resolved(c, base, model \\ "gemini-fixture") do
    File.mkdir_p!(c.home)

    File.write!(
      Path.join(c.home, "config.json"),
      Jason.encode!(%{
        "version" => 1,
        "profiles" => %{
          "native" => %{
            "provider" => "gemini",
            "model" => model,
            "base_url" => base,
            "reasoning_effort" => "low",
            "max_output_tokens" => 64
          }
        },
        "roles" => %{"main" => "native"}
      })
    )

    {:ok, effective} = Ipse.Config.resolve(c.root, c.home, [project_config: false], %{})

    client = %{
      workspace: c.root,
      home: c.home,
      auth_dir: Path.join(c.home, "auth"),
      operator_home: c.home,
      mcp_config: nil,
      base_url: nil,
      operator_questions: false,
      approval: :deny
    }

    {:ok, runtime} = Ipse.Config.runtime(effective, client)
    Map.put(runtime, :api_key, "fixture-gemini-key")
  end

  defp start(c, config, id \\ nil) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: c.root, state_dir: c.state, subscriber: self(), id: id}
      )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    pid
  end

  defp response(parts),
    do:
      Fixture.sse(%{
        "modelVersion" => "gemini-fixture-001",
        "candidates" => [
          %{"content" => %{"role" => "model", "parts" => parts}, "finishReason" => "STOP"}
        ],
        "usageMetadata" => %{
          "promptTokenCount" => 3,
          "toolUsePromptTokenCount" => 0,
          "candidatesTokenCount" => 2,
          "thoughtsTokenCount" => 1,
          "totalTokenCount" => 6
        }
      })

  test "signed tool loop journals native parts, hides thoughts in diagnosis and resumes without replay",
       c do
    File.write!(Path.join(c.root, "evidence.txt"), "fixture-evidence")

    parts = [
      %{"text" => "PRIVATE_GEMINI_THOUGHT", "thought" => true},
      %{
        "functionCall" => %{"name" => "read", "args" => %{"path" => "evidence.txt"}},
        "thoughtSignature" => "PRIVATE_GEMINI_SIGNATURE"
      }
    ]

    {base, server} = Fixture.sequence([response(parts), response([%{"text" => "done"}])])
    config = resolved(c, base)
    pid = start(c, config)
    assert :ok = Session.prompt(pid, "Read the evidence")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5000
    [first, second] = Task.await(server)

    for {headers, body} <- [first, second] do
      assert headers =~ "x-goog-api-key: fixture-gemini-key"
      assert body["generationConfig"]["maxOutputTokens"] == 64
    end

    {_, body} = second
    signed = Enum.find(body["contents"], &(&1["role"] == "model"))
    assert signed == %{"role" => "model", "parts" => parts}
    assert Jason.encode!(List.last(body["contents"])) =~ "fixture-evidence"
    assert Session.info(pid).final == "done"
    diagnosis = Jason.encode!(Session.diagnostics(pid))
    refute diagnosis =~ "PRIVATE_GEMINI_THOUGHT"
    refute diagnosis =~ "PRIVATE_GEMINI_SIGNATURE"
    refute diagnosis =~ "fixture-gemini-key"
    id = Session.info(pid).id
    assert {:ok, events} = Journal.load(c.state, id)
    assert {:ok, ledger} = Ipse.Usage.restore(events, id)
    requests = Ipse.Usage.snapshot(ledger)["requests"]
    assert length(requests) == 2

    assert Enum.all?(
             requests,
             &(&1["billing_mode"] == "api" and &1["usage"]["counts"]["output_tokens"] == 3)
           )

    assert :ok = Session.close(pid)
    path = Path.join(c.state, id <> ".jsonl")
    before = File.read!(path)
    assert before =~ "PRIVATE_GEMINI_SIGNATURE"
    resumed = start(c, config, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(path) == before
    assert :ok = Session.close(resumed)
    File.write!(path, "{\"type\"", [:append])
    torn = File.read!(path)
    changed = resolved(c, base, "different-model")

    assert {:error, :resume_configuration_mismatch} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: changed, cwd: c.root, state_dir: c.state, id: id, subscriber: self()}
             )

    assert File.read!(path) == torn
  end

  test "main, child and helper route to the native adapter without retaining parent credentials",
       c do
    config = resolved(c, "http://127.0.0.1:9")
    assert {:ok, child} = Ipse.Config.Profiles.child_config(config, %{}, %{"profile" => "native"})
    assert child.provider == :gemini
    assert child.execution.provider == "gemini"
    refute Map.has_key?(child, :api_key)
    assert :ok = Ipse.Provider.Registry.validate_request(child)
    owner = Map.put(config, :extensions, [%{identity: %{"capabilities" => ["host.model"]}}])

    request = %{
      "op" => "model.complete",
      "version" => 1,
      "profile" => "native",
      "instruction" => "Extract",
      "input" => "fixture",
      "max_output_bytes" => 512,
      "timeout_ms" => 5000
    }

    assert {:ok, helper, execution} = Ipse.Extension.ModelCall.prepare(owner, request)
    assert helper.provider == :gemini
    refute Map.has_key?(helper, :api_key)
    assert Ipse.Extension.ModelCall.valid_profile?(execution)
    refute Ipse.Extension.ModelCall.valid_profile?(Map.put(execution, "model", "bad/path"))

    assert {:error, _} =
             Ipse.Extension.ModelCall.prepare(
               owner,
               Map.merge(
                 request,
                 %{"version" => 2, "response_schema" => %{"type" => "object"}}
               )
             )

    assert {:ok, %{"origin" => "http://127.0.0.1:9"}} = Ipse.Provider.destination(helper)
  end

  test "Gemini API admission respects shared reservations and absent prices stay unpriced", c do
    config = resolved(c, "http://127.0.0.1:9")
    session = Ipse.Usage.id()
    admitted = Ipse.Usage.admission(session, config, "model", Ipse.Usage.id())
    assert admitted["provider"] == "gemini"
    assert admitted["billing_mode"] == "api"

    policy = %{
      "version" => 1,
      "max_requests" => 1,
      "max_input_tokens" => 100,
      "reserve_input_tokens" => 10,
      "max_output_tokens" => 64,
      "reserve_output_tokens" => 64
    }

    root = %{"session_id" => session}
    alias Ipse.Usage.Budget

    assert {:ok, ledger} =
             Budget.restore_ledger([Budget.ledger_header(root, policy)], root, policy)

    assert {:ok, _, reserved} = Budget.reserve_request(ledger, admitted)

    assert {:error, :budget_exhausted} =
             Budget.reserve_request(
               reserved,
               Ipse.Usage.admission(session, config, "model", Ipse.Usage.id())
             )

    raw = %{
      "promptTokenCount" => 3,
      "toolUsePromptTokenCount" => 0,
      "candidatesTokenCount" => 2,
      "thoughtsTokenCount" => 1,
      "totalTokenCount" => 6
    }

    completed =
      Ipse.Usage.completion(
        admitted,
        {:ok, %{"provider_data" => %{"reported_model" => "gemini-fixture-001"}}, raw},
        1,
        nil
      )

    record =
      Ipse.Usage.request_record(%{admission: admitted, observation: nil, completion: completed})

    card = %{
      "version" => 1,
      "id" => "no-rates",
      "revision" => "fixture",
      "currency" => "USD",
      "source" => "operator:fixture",
      "published_on" => "2026-10-23",
      "rows" => []
    }

    assert {:ok, quote} =
             Ipse.Usage.Costs.estimate(
               card,
               Map.take(
                 record,
                 ~w(provider billing_mode model reported_model endpoint_sha256 admitted_at_ms outcome finality usage)
               )
             )

    assert quote["status"] == "unpriced"
    assert quote["amount_nanos"] == nil
  end
end
