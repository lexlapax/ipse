defmodule Ipse.Config.RouterIntegrationTest do
  use ExUnit.Case, async: false
  alias Ipse.Config.Profiles
  alias Ipse.Extension.ModelCall
  alias Ipse.Usage.{Budget, Costs}

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-router-profile-" <> Ipse.Usage.id())
    cwd = Path.join(root, "workspace")
    home = Path.join(root, "operator")
    for path <- [cwd, home], do: File.mkdir_p!(path)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      cwd: cwd,
      home: home,
      path: Path.join(home, "config.json"),
      state: Path.join(root, "sessions")
    }
  end

  defp route(extra \\ %{}),
    do:
      Map.merge(
        %{
          "provider" => "openrouter",
          "model" => "org/model",
          "upstream" => "openai",
          "base_url" => "http://127.0.0.1:9",
          "max_output_tokens" => 64
        },
        extra
      )

  defp resolved(c, route) do
    File.write!(
      c.path,
      Jason.encode!(%{
        "version" => 1,
        "profiles" => %{"pinned" => route},
        "roles" => %{"main" => "pinned"}
      })
    )

    File.chmod!(c.path, 0o600)
    {:ok, effective} = Ipse.Config.resolve(c.cwd, c.home, [project_config: false], %{})

    client = %{
      workspace: c.cwd,
      home: c.home,
      auth_dir: Path.join(c.home, "auth"),
      operator_home: c.home,
      mcp_config: nil,
      base_url: nil,
      operator_questions: false,
      approval: :deny
    }

    {:ok, runtime} = Ipse.Config.runtime(effective, client)
    {effective, runtime}
  end

  test "configuration requires a pinned profile and preserves policy in main, child and helper facts",
       c do
    assert {:error, error} =
             Ipse.Config.resolve(
               c.cwd,
               c.home,
               [provider: "openrouter", model: "org/model", project_config: false],
               %{}
             )

    assert error =~ "requires a profile with a pinned upstream"
    {effective, runtime} = resolved(c, route())
    assert effective.execution.upstream == "openai"
    assert effective.execution.data_collection == "deny"
    assert runtime.upstream == "openai"
    assert runtime.data_collection == "deny"
    assert :ok = Ipse.Provider.Registry.validate_request(runtime)

    assert {:ok, child} =
             Profiles.child_config(Map.put(runtime, :api_key, "parent-only-key"), %{}, %{
               "profile" => "pinned"
             })

    assert child.upstream == "openai"
    assert child.data_collection == "deny"
    assert child.execution.upstream == "openai"
    refute Map.has_key?(child, :api_key)
    assert :ok = Ipse.Provider.Registry.validate_request(child)
    owner = Map.put(runtime, :extensions, [%{identity: %{"capabilities" => ["host.model"]}}])

    request = %{
      "op" => "model.complete",
      "version" => 1,
      "profile" => "pinned",
      "instruction" => "Extract",
      "input" => "fixture",
      "max_output_bytes" => 512,
      "timeout_ms" => 5000
    }

    assert {:ok, prepared, execution} =
             ModelCall.prepare(Map.put(owner, :api_key, "parent-only-key"), request)

    assert execution["upstream"] == "openai"
    assert execution["data_collection"] == "deny"
    assert prepared.upstream == "openai"
    assert prepared.max_output_tokens == 64
    refute Map.has_key?(prepared, :api_key)
    assert ModelCall.valid_profile?(execution)
    refute ModelCall.valid_profile?(Map.put(execution, "upstream", "bad/slug"))
    structured = Map.merge(request, %{"version" => 2, "response_schema" => %{"type" => "object"}})
    assert {:error, _} = ModelCall.prepare(owner, structured)
  end

  test "an operator-owned local compatible profile resolves without a credential or remote fallback",
       c do
    {_, runtime} =
      resolved(c, %{
        "provider" => "openai_compatible",
        "model" => "local",
        "base_url" => "http://127.0.0.1:9/v1"
      })

    assert runtime.provider == :openai_compatible
    assert runtime.base_url == "http://127.0.0.1:9/v1"
    assert :ok = Ipse.Provider.Registry.validate_request(runtime)

    assert {:error, _} =
             Ipse.Config.resolve(
               c.cwd,
               Path.join(c.root, "absent"),
               [provider: "openai_compatible", model: "local", project_config: false],
               %{}
             )
  end

  test "idle OpenRouter resume preserves bytes and a changed upstream or data policy refuses before repair",
       c do
    {_, config} = resolved(c, route())
    opts = [cwd: c.cwd, state_dir: c.state, subscriber: self()]

    assert {:ok, pid} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session, [config: config] ++ opts}
             )

    id = Ipse.Session.info(pid).id
    assert :ok = Ipse.Session.close(pid)
    path = Path.join(c.state, id <> ".jsonl")
    bytes = File.read!(path)

    assert {:ok, pid} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session, [config: config, id: id] ++ opts}
             )

    assert Ipse.Session.info(pid).phase == :idle
    assert :ok = Ipse.Session.close(pid)
    assert File.read!(path) == bytes
    File.write!(path, "{\"type\"", [:append])
    torn = File.read!(path)

    for changed <- [route(%{"upstream" => "anthropic"}), route(%{"data_collection" => "allow"})] do
      {_, changed_config} = resolved(c, changed)

      assert {:error, :resume_configuration_mismatch} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Ipse.Session, [config: changed_config, id: id] ++ opts}
               )

      assert File.read!(path) == torn
    end
  end

  test "API billing stays explicit, shared admission refuses a second request, and unknown price is never zero",
       c do
    {_, config} = resolved(c, route())
    session = Ipse.Usage.id()
    admitted = Ipse.Usage.admission(session, config, "model", Ipse.Usage.id())
    assert admitted["provider"] == "openrouter"
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

    assert {:ok, ledger} =
             Budget.restore_ledger([Budget.ledger_header(root, policy)], root, policy)

    assert {:ok, _, reserved} = Budget.reserve_request(ledger, admitted)

    assert {:error, :budget_exhausted} =
             Budget.reserve_request(
               reserved,
               Ipse.Usage.admission(session, config, "model", Ipse.Usage.id())
             )

    raw = %{
      "prompt_tokens" => 7,
      "completion_tokens" => 3,
      "total_tokens" => 10,
      "cost" => 123.45
    }

    completed =
      Ipse.Usage.completion(
        admitted,
        {:ok, %{"provider_data" => %{"reported_model" => "org/model"}}, raw},
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
             Costs.estimate(
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
