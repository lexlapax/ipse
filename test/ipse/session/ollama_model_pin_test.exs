Code.require_file("../../support/provider_fixture.ex", __DIR__)
Code.require_file("../../support/ollama_metadata_fixture.ex", __DIR__)

defmodule Ipse.Session.OllamaModelPinTest do
  use ExUnit.Case, async: false
  alias Ipse.{InferenceSlots, Journal, Session, Usage}
  alias Ipse.Test.ProviderFixture

  @available_host :os.type() == {:unix, :linux} and
                    System.cmd("uname", ["-r"]) == {"7.2.11-arch1-1\n", 0} and
                    System.cmd("stat", ["-f", "-c", "%T", System.tmp_dir!()]) == {"tmpfs\n", 0}
  @moduletag skip:
               if(@available_host,
                 do: false,
                 else: "requires the qualified native tmpfs service ledger profile"
               )

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-pinned-job-" <> Usage.id())
    home = Path.join(root, "operator")
    cwd = Path.join(root, "workspace")
    File.mkdir_p!(home)
    File.mkdir!(cwd)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, home: home, cwd: cwd, dir: Path.join(root, "sessions")}
  end

  defp metadata(opts \\ []), do: Ipse.Test.OllamaMetadataFixture.scan(opts)

  defp body do
    ProviderFixture.ndjson([
      %{
        "model" => "fixture",
        "message" => %{"role" => "assistant", "content" => "PINNED_RESULT"},
        "done" => true,
        "prompt_eval_count" => 1,
        "eval_count" => 1
      }
    ])
  end

  defp start(c, before, after_bodies, response \\ body(), extra \\ %{}) do
    {pre, pin} = metadata(before)
    responses = if is_nil(response), do: pre, else: pre ++ [response] ++ after_bodies
    {base, server} = ProviderFixture.sequence(responses)

    config = %{
      provider: :ollama,
      model: "fixture",
      base_url: base,
      timeout_ms: 15000,
      home: c.home,
      approval: :deny,
      compact: false,
      ollama_context_tokens: 8192,
      ollama_model_pin: pin,
      budget: %{"version" => 1, "max_requests" => 1},
      inference_services: %{"local" => %{"version" => 1, "origins" => [base]}}
    }

    config = Map.merge(config, extra)

    profile = %{
      "provider" => "ollama",
      "model" => "fixture",
      "base_url" => base,
      "ollama_context_tokens" => 8192,
      "ollama_model_pin" => config.ollama_model_pin
    }

    config =
      Map.merge(config, %{
        execution: Ipse.Config.Profiles.manifest("local", profile),
        profiles: %{"local" => profile}
      })

    assert {:ok, _} = InferenceSlots.status(config, cwd: c.cwd)

    assert {:ok, pid} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, config: config, cwd: c.cwd, state_dir: c.dir, subscriber: self()}
             )

    on_exit(fn ->
      if Process.alive?(pid), do: Session.close_confirmed(pid)
      if Process.alive?(server.pid), do: Process.exit(server.pid, :kill)
    end)

    {pid, server, config}
  end

  defp finish(c, pid, config, expected_unknown_liabilities \\ 0) do
    id = Session.info(pid).id
    assert :ok = Session.close_confirmed(pid)
    assert {:ok, events} = Journal.load(c.dir, id)
    assert {:ok, _} = Session.Saved.restore(events, id)
    assert {:ok, budget} = Usage.Budget.saved(c.dir, id)
    assert budget["unknown_liability_count"] == expected_unknown_liabilities
    assert {:ok, ledger} = InferenceSlots.status(config, cwd: c.cwd)
    assert ledger["services"]["local"]["active"] == nil
    refute Enum.any?(events, &(&1["type"] == "tool_started"))
    {events, budget}
  end

  test "a real registered Session checks metadata around inference before releasing text", c do
    {post, _} = metadata()
    {pid, server, config} = start(c, [context: 4096], post)
    assert :ok = Session.prompt(pid, "Return the synthetic fixture")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 20000
    assert Session.info(pid).final == "PINNED_RESULT"
    requests = Task.await(server)
    assert length(requests) == 13

    assert [{_, request}] =
             Enum.filter(requests, fn {headers, _} ->
               String.starts_with?(headers, "POST /api/chat ")
             end)

    assert request["options"]["num_ctx"] == 8192
    assert request["options"]["num_predict"] == nil
    id = Session.info(pid).id
    {events, budget} = finish(c, pid, config)
    assert budget["request_count"] == 1

    assert [%{"outcome" => "completed"}] =
             Enum.filter(events, &(&1["type"] == "request_finished"))

    path = Path.join(c.dir, id <> ".jsonl")
    original = File.read!(path)

    assert {:error, _} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: Map.delete(config, :ollama_model_pin),
                cwd: c.cwd,
                state_dir: c.dir,
                id: id,
                subscriber: self()}
             )

    assert File.read!(path) == original

    dropped =
      config
      |> Map.delete(:ollama_model_pin)
      |> update_in([:execution], &Map.delete(&1, :ollama_model_pin))

    assert {:error, _} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: dropped, cwd: c.cwd, state_dir: c.dir, id: id, subscriber: self()}
             )

    assert File.read!(path) == original

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, config: config, cwd: c.cwd, state_dir: c.dir, id: id, subscriber: self()}
             )

    assert Session.info(resumed).phase == :idle
    assert :ok = Session.close_confirmed(resumed)
  end

  test "a changed pin withholds a native write batch even under existing allow authority", c do
    {post, _} = metadata(digest: String.duplicate("c", 64))

    response =
      ProviderFixture.ndjson([
        %{
          "model" => "fixture",
          "message" => %{
            "role" => "assistant",
            "content" => "UNVERIFIED_TOOL_BATCH",
            "tool_calls" => [
              %{
                "function" => %{
                  "name" => "write",
                  "arguments" => %{"path" => "forbidden.txt", "content" => "forbidden"}
                }
              }
            ]
          },
          "done" => true,
          "prompt_eval_count" => 1,
          "eval_count" => 1
        }
      ])

    {pid, server, config} =
      start(c, [], post, response, %{approval: :allow, approval_origin: :yes})

    assert :ok = Session.prompt(pid, "Return the synthetic fixture")
    assert_receive {:ipse, ^pid, {:done, :error}}, 20000
    assert length(Task.await(server)) == 13
    {events, _} = finish(c, pid, config)
    refute File.exists?(Path.join(c.cwd, "forbidden.txt"))

    refute Enum.any?(
             events,
             &(&1["type"] == "message" and
                 (get_in(&1, ["message", "content"]) == "UNVERIFIED_TOOL_BATCH" or
                    get_in(&1, ["message", "tool_calls"]) not in [nil, []]))
           )
  end

  test "a preflight mismatch sends no input and retains its unstarted budget booking", c do
    {_, pin} = metadata()
    bad = Map.put(pin, "metadata_sha256", String.duplicate("f", 64))
    {pid, server, config} = start(c, [], [], nil, %{ollama_model_pin: bad})
    assert :ok = Session.prompt(pid, "PRIVATE_PREFLIGHT_CANARY")
    assert_receive {:ipse, ^pid, {:done, :error}}, 20000
    requests = Task.await(server)
    assert length(requests) == 6
    refute inspect(requests) =~ "PRIVATE_PREFLIGHT_CANARY"

    refute Enum.any?(requests, fn {headers, _} ->
             String.starts_with?(headers, "POST /api/chat ")
           end)

    {events, budget} = finish(c, pid, config, 1)
    assert budget["request_count"] == 1
    assert budget["unsettled_count"] == 1
    assert budget["refused_count"] == 0
    assert [%{"unit" => "requests", "booked" => 1}] = budget["dimensions"]
    assert Enum.count(events, &(&1["type"] == "request_admitted")) == 1
    refute Enum.any?(events, &(&1["type"] == "request_usage_observed"))
  end

  test "postcheck refusal keeps measured token charges and resumes idle without replay", c do
    {post, _} = metadata(context: 4096)

    policy = %{
      "version" => 1,
      "max_requests" => 1,
      "max_input_tokens" => 8,
      "reserve_input_tokens" => 8,
      "max_output_tokens" => 8,
      "reserve_output_tokens" => 8
    }

    {pid, server, config} = start(c, [], post, body(), %{budget: policy})
    assert :ok = Session.prompt(pid, "Return the synthetic fixture")
    assert_receive {:ipse, ^pid, {:done, :error}}, 20000
    assert length(Task.await(server)) == 13
    id = Session.info(pid).id
    {events, budget} = finish(c, pid, config)
    for dimension <- budget["dimensions"], do: assert(dimension["booked"] == 1)
    assert Enum.any?(events, &(&1["type"] == "request_usage_observed"))

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, config: config, cwd: c.cwd, state_dir: c.dir, id: id, subscriber: self()}
             )

    assert Session.info(resumed).phase == :idle
    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, after_events} = Journal.load(c.dir, id)
    assert Enum.count(after_events, &(&1["type"] == "request_admitted")) == 1
  end

  for {label, options} <- [
        {"changed manifest", [digest: String.duplicate("c", 64)]},
        {"changed runtime", [version: "0.40.14"]},
        {"changed template", [template: "different"]},
        {"insufficient context", [context: 4096]},
        {"unloaded result", [context: nil]}
      ] do
    @label label
    @options options
    test "#{@label} after inference withholds generated text and tools", c do
      {post, _} = metadata(@options)
      {pid, server, config} = start(c, [], post)
      assert :ok = Session.prompt(pid, "Return the synthetic fixture")
      assert_receive {:ipse, ^pid, {:error, error}}, 20000
      assert error =~ "model pin or loaded context"
      assert_receive {:ipse, ^pid, {:done, :error}}, 5000
      refute_receive {:ipse, ^pid, {:text, "PINNED_RESULT"}}, 20
      assert length(Task.await(server)) == 13
      {events, budget} = finish(c, pid, config)
      assert budget["request_count"] == 1
      refute Enum.any?(events, &(get_in(&1, ["message", "content"]) == "PINNED_RESULT"))
    end
  end
end
