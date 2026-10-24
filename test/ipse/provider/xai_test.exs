Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule Ipse.Provider.XAITest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias Ipse.Provider.{OpenAI, Registry}
  alias Ipse.Test.ProviderFixture, as: Fixture

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-xai-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    previous = System.get_env("XAI_API_KEY")
    System.put_env("XAI_API_KEY", "fixture-xai-private-key")

    on_exit(fn ->
      if previous,
        do: System.put_env("XAI_API_KEY", previous),
        else: System.delete_env("XAI_API_KEY")

      File.rm_rf!(root)
    end)

    %{root: root}
  end

  defp config(extra \\ %{}),
    do: Map.merge(%{provider: :xai, model: "grok-4.7", timeout_ms: 3000}, extra)

  defp response(output, extra \\ %{}) do
    Fixture.sse(%{
      "type" => "response.completed",
      "response" =>
        Map.merge(
          %{
            "status" => "completed",
            "model" => "grok-fixture",
            "output" => output,
            "usage" => %{"input_tokens" => 7, "output_tokens" => 3, "total_tokens" => 10}
          },
          extra
        )
    })
  end

  defp text(value),
    do: %{
      "type" => "message",
      "role" => "assistant",
      "content" => [%{"type" => "output_text", "text" => value}]
    }

  test "registry selects billed Grok explicitly with an independent credential and destination" do
    spec = Registry.fetch!(:xai)
    assert spec.default_model == nil
    assert spec.credential == {:env, "XAI_API_KEY"}
    assert spec.billing_mode == "api"
    assert "XAI_API_KEY" in Registry.secret_env()
    refute Registry.embedding?(:xai)
    assert OpenAI.endpoint(config()) == "https://api.x.ai/v1/responses"
    assert {:ok, facts} = Ipse.Provider.destination(config())
    assert facts["origin"] == "https://api.x.ai"
    assert facts["target_sha256"] == Ipse.JSON.sha256("https://api.x.ai/v1/responses")

    for effort <- ~w(low medium high xhigh),
        do: assert(:ok == Registry.reasoning(:xai, "grok-4.7", effort))

    for {model, effort} <- [
          {"grok-4.5", "xhigh"},
          {"grok-4.7", "none"},
          {"grok-4.7", "max"},
          {"unknown", "high"}
        ],
        do: assert(match?({:error, _}, Registry.reasoning(:xai, model, effort)))
  end

  test "real request uses xAI key, stateless Responses and exact local tool definitions" do
    native = [
      %{"type" => "reasoning", "encrypted_content" => "XAI_PRIVATE_CIPHERTEXT", "summary" => []},
      text("done")
    ]

    {base, server} =
      Fixture.start(
        response(native, %{
          "usage" => %{"input_tokens" => 7, "output_tokens" => 3, "cost_in_usd_ticks" => 12345}
        })
      )

    tools = [
      %{
        "type" => "function",
        "function" => %{"name" => "read", "parameters" => %{"type" => "object"}}
      }
    ]

    selected = config(%{base_url: base, reasoning_effort: "low", max_output_tokens: 64})

    assert {:ok, answer, raw} =
             Ipse.Provider.request_complete(
               selected,
               [%{"role" => "user", "content" => "hi"}],
               tools,
               fn _ -> :ok end
             )

    {headers, request} = Task.await(server)
    assert headers =~ "POST /responses "
    assert headers =~ "authorization: Bearer fixture-xai-private-key"
    assert request["model"] == "grok-4.7"
    assert request["store"] == false
    assert request["stream"] == true
    assert request["reasoning"] == %{"effort" => "low"}
    assert request["max_output_tokens"] == 64

    assert request["tools"] == [
             %{"type" => "function", "name" => "read", "parameters" => %{"type" => "object"}}
           ]

    refute Map.has_key?(request, "previous_response_id")
    assert answer["content"] == "done"
    assert answer["provider_data"]["provider"] == "xai"
    assert answer["provider_data"]["reported_cost_usd_ticks"] == raw["cost_in_usd_ticks"]
    assert OpenAI.request_body(selected, [answer], [])["input"] == native

    assert_raise ArgumentError, fn ->
      OpenAI.request_body(%{selected | provider: :openai}, [answer], [])
    end

    foreign = put_in(answer, ["provider_data", "provider"], "openai")
    assert_raise ArgumentError, fn -> OpenAI.request_body(selected, [foreign], []) end
  end

  test "usage accepts one documented counter dialect and rejects contradictory aliases" do
    for raw <- [
          %{
            "input_tokens" => 7,
            "output_tokens" => 3,
            "output_tokens_details" => %{"reasoning_tokens" => 1}
          },
          %{
            "prompt_tokens" => 7,
            "completion_tokens" => 3,
            "total_tokens" => 11,
            "completion_tokens_details" => %{"reasoning_tokens" => 1}
          }
        ] do
      usage = Ipse.Usage.normalize(:xai, raw)
      assert usage["quality"] == "totals_known"
      assert usage["counts"]["input_tokens"] == 7

      assert usage["counts"]["output_tokens"] ==
               if(Map.has_key?(raw, "completion_tokens"), do: 4, else: 3)

      assert usage["counts"]["output_reasoning_tokens"] == 1

      assert usage["counts"]["total_tokens"] ==
               if(Map.has_key?(raw, "completion_tokens"), do: 11, else: 10)
    end

    assert Ipse.Usage.normalize(:xai, %{"input_tokens" => 7})["quality"] == "partial"
    assert Ipse.Usage.normalize(:xai, %{})["quality"] == "unavailable"

    for raw <- [
          %{"input_tokens" => 7, "prompt_tokens" => 8},
          %{"output_tokens" => -1},
          %{
            "input_tokens_details" => %{"cached_tokens" => 2},
            "prompt_tokens_details" => %{"cached_tokens" => 3}
          }
        ],
        do: assert(Ipse.Usage.normalize(:xai, raw)["quality"] == "invalid")
  end

  test "a visible-output cap cannot stand in for a total-output budget reservation" do
    for provider <- [:xai, :xai_oauth] do
      assert {:error, message} =
               Ipse.Usage.Budget.request_config(%{
                 provider: provider,
                 budget: %{"reserve_output_tokens" => 64}
               })

      assert message =~ "visible text only"

      assert {:ok, _} =
               Ipse.Usage.Budget.request_config(%{
                 provider: provider,
                 budget: %{"version" => 1, "max_requests" => 2}
               })
    end

    raw = %{
      "prompt_tokens" => 32,
      "completion_tokens" => 9,
      "completion_tokens_details" => %{"reasoning_tokens" => 94},
      "total_tokens" => 135
    }

    counts = Ipse.Usage.normalize(:xai, raw)["counts"]
    assert counts["output_tokens"] == 103
    assert counts["total_tokens"] == 135
    inclusive = %{raw | "completion_tokens" => 103}
    assert Ipse.Usage.normalize(:xai, inclusive)["counts"]["output_tokens"] == 103
    assert Ipse.Usage.normalize(:xai, Map.delete(raw, "total_tokens"))["quality"] == "partial"
  end

  test "real Session approval, native replay, accounting and idle resume preserve Grok identity",
       c do
    cipher = %{
      "type" => "reasoning",
      "encrypted_content" => "XAI_PRIVATE_CIPHERTEXT",
      "summary" => []
    }

    call = %{
      "type" => "function_call",
      "call_id" => "write-1",
      "name" => "write",
      "arguments" => Jason.encode!(%{"path" => "grok.txt", "content" => "approved"})
    }

    {base, server} =
      Fixture.sequence([response([cipher, call]), response([cipher, text("Finished")])])

    selected =
      config(%{base_url: base, home: Path.join(c.root, "home"), max_steps: 4, approval: :ask})

    state = Path.join(c.root, "sessions")

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Ipse.Session, config: selected, cwd: c.root, state_dir: state, subscriber: self()}
      )

    on_exit(fn -> if Process.alive?(pid), do: Ipse.Session.close(pid) end)
    :ok = Ipse.Session.prompt(pid, "Write the file")
    assert_receive {:ipse, ^pid, {:approval, ref, "write", _}}, 3000
    refute File.exists?(Path.join(c.root, "grok.txt"))
    assert :ok = Ipse.Session.approve(pid, ref, true)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5000
    assert File.read!(Path.join(c.root, "grok.txt")) == "approved"
    [{_, _first}, {_, next}] = Task.await(server)
    assert cipher in next["input"]

    assert Enum.any?(
             next["input"],
             &(&1["type"] == "function_call_output" and &1["call_id"] == "write-1")
           )

    id = Ipse.Session.info(pid).id
    assert :ok = Ipse.Session.close_confirmed(pid)
    assert {:ok, events} = Ipse.Journal.load(state, id)
    assert {:ok, ledger} = Ipse.Usage.restore(events, id)
    requests = Ipse.Usage.snapshot(ledger)["requests"]
    assert length(requests) == 2
    assert Enum.all?(requests, &(&1["provider"] == "xai" and &1["billing_mode"] == "api"))

    {:ok, resumed} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Ipse.Session,
         config: selected, cwd: c.root, state_dir: state, id: id, subscriber: self()}
      )

    on_exit(fn -> if Process.alive?(resumed), do: Ipse.Session.close(resumed) end)
    assert Ipse.Session.info(resumed).phase == :idle
    assert Ipse.Session.info(resumed).final == ""
    assert Ipse.Session.info(resumed).runtime.historical_reported_model == "grok-fixture"
    assert length(Ipse.Session.info(resumed).accounting["requests"]) == 2
  end

  test "setup preview and offline doctor disclose the selected key route without network or writes",
       c do
    home = Path.join(c.root, "home")

    output =
      capture_io(fn ->
        assert Ipse.CLI.Setup.run([provider: "xai", model: "grok-4.7"], home, c.root) == 0
      end)

    assert output =~ "XAI_API_KEY"
    assert output =~ "api billing"
    refute output =~ "fixture-xai-private-key"
    refute File.exists?(home)
    path = Path.join(c.root, "operator.json")

    File.write!(
      path,
      Jason.encode!(%{version: 1, settings: %{provider: "xai", model: "grok-4.7"}})
    )

    {0, report} = Ipse.CLI.Doctor.run([config: path, project_config: false], home, c.root)
    encoded = Jason.encode!(report)
    assert encoded =~ "xai"
    assert encoded =~ "XAI_API_KEY present"
    refute encoded =~ "fixture-xai-private-key"
    refute File.exists?(home)
  end
end
