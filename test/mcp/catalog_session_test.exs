defmodule Ipse.MCP.CatalogSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.MCP.Config

  defmodule Model do
    def complete(config, messages, tools, _emit) do
      send(config.test_pid, {:catalog_model_input, messages, tools})

      if List.last(messages)["role"] == "tool" do
        {:ok, %{"role" => "assistant", "content" => "Fixture finished"}, %{}}
      else
        calls = [
          {Config.resource_id("notes", "notes://guide"), %{}},
          {Config.prompt_id("notes", "summarize"), %{"topic" => "approval boundaries"}}
        ]

        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" =>
             Enum.with_index(calls, fn {name, args}, index ->
               %{
                 "id" => "catalog-#{index}",
                 "type" => "function",
                 "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
               }
             end)
         }, %{}}
      end
    end
  end

  setup do
    root =
      Path.join(System.tmp_dir!(), "ipse-catalog-session-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, dir: Path.join(root, "state")}
  end

  test "resource and prompt content need separate exact approvals and stay tool data", ctx do
    pid = session(ctx)
    :ok = Ipse.Session.prompt(pid, "inspect catalog")
    assert_receive {:catalog_model_input, _, definitions}, 5_000

    assert length(
             Enum.filter(
               definitions,
               &String.starts_with?(get_in(&1, ["function", "name"]), "mcp__")
             )
           ) == 2

    resource = Config.resource_id("notes", "notes://guide")
    prompt = Config.prompt_id("notes", "summarize")

    assert_receive {:ipse, ^pid,
                    {:mcp_approval_context,
                     %{kind: "resource", source: "notes://guide", tool_id: ^resource}}},
                   5_000

    assert_receive {:ipse, ^pid, {:approval, ref, ^resource, %{}}}, 5_000
    assert content_calls(ctx) == []
    assert {:error, :no_pending_approval} = Ipse.Session.approve(pid, make_ref(), true)
    assert content_calls(ctx) == []
    :ok = Ipse.Session.approve(pid, ref, true)
    args = %{"topic" => "approval boundaries"}
    assert_receive {:ipse, ^pid, {:approval, ref, ^prompt, ^args}}, 5_000
    assert Enum.map(content_calls(ctx), & &1["event"]) == ["read_resource"]
    {:ok, before} = Ipse.Journal.load(ctx.dir, Ipse.Session.info(pid).id)
    assert Enum.any?(before, &(&1["type"] == "tool_started" and &1["name"] == resource))
    :ok = Ipse.Session.approve(pid, ref, true)
    assert_receive {:catalog_model_input, messages, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    results = Enum.filter(messages, &(&1["role"] == "tool"))
    assert length(results) == 2
    assert Enum.at(results, 0)["content"] =~ "A local fixture note."
    assert Enum.at(results, 1)["content"] =~ "[user]\nSummarize: approval boundaries"

    refute Enum.any?(
             messages,
             &(&1["role"] == "user" and String.contains?(&1["content"], "Summarize:"))
           )

    {:ok, events} = Ipse.Journal.load(ctx.dir, Ipse.Session.info(pid).id)
    intents = Enum.filter(events, &(&1["type"] == "tool_started"))
    assert Enum.map(intents, &get_in(&1, ["mcp", "kind"])) == ["resource", "prompt"]
    assert Enum.map(intents, &get_in(&1, ["mcp", "source"])) == ["notes://guide", "summarize"]
    assert Enum.all?(intents, &(&1["approval"] == "approved"))
  end

  test "headless denial reads no content; completed resume replays neither request", ctx do
    denied = session(ctx, approval: :deny)
    :ok = Ipse.Session.prompt(denied, "inspect catalog")
    assert_receive {:ipse, ^denied, {:done, :ok}}, 5_000
    assert content_calls(ctx) == []
    :ok = Ipse.Session.close(denied)
    allowed = session(ctx, approval: :allow)
    :ok = Ipse.Session.prompt(allowed, "inspect catalog")
    assert_receive {:ipse, ^allowed, {:done, :ok}}, 5_000
    id = Ipse.Session.info(allowed).id
    before = content_calls(ctx)
    assert length(before) == 2
    :ok = Ipse.Session.close(allowed)
    resumed = session(ctx, [approval: :allow], id)
    assert Ipse.Session.info(resumed).phase == :idle
    assert content_calls(ctx) == before
  end

  test "lost resource response stops the prompt batch and unknown resume does not retry", ctx do
    pid = session(ctx, scenario: "resource_disconnect", approval: :allow)
    :ok = Ipse.Session.prompt(pid, "inspect catalog")
    assert_receive {:ipse, ^pid, {:done, :error}}, 5_000
    assert Enum.map(content_calls(ctx), & &1["event"]) == ["read_resource"]
    id = Ipse.Session.info(pid).id
    {:ok, events} = Ipse.Journal.load(ctx.dir, id)

    outcomes =
      for e <- events,
          get_in(e, ["message", "role"]) == "tool",
          do: get_in(e, ["message", "ipse_tool_outcome", "status"])

    assert outcomes == ["unknown", "not_started"]
    :ok = Ipse.Session.close(pid)
    resumed = session(ctx, [scenario: "resource_disconnect", approval: :allow], id)
    assert Ipse.Session.info(resumed).phase == :idle
    assert length(content_calls(ctx)) == 1
  end

  defp content_calls(ctx) do
    case File.read(Path.join(ctx.root, "catalog.log")) do
      {:ok, bytes} ->
        bytes
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)
        |> Enum.filter(&(&1["event"] in ["read_resource", "get_prompt"]))

      _ ->
        []
    end
  end

  defp session(ctx, opts \\ [], id \\ nil) do
    document = %{
      "servers" => [
        %{
          "id" => "notes",
          "command" => System.find_executable("elixir"),
          "args" => [
            "--erl",
            "+S 2:2",
            "-pa",
            Path.dirname(to_string(:code.which(Jason))),
            Path.expand("../support/mcp_catalog_server.exs", __DIR__),
            Keyword.get(opts, :scenario, "normal")
          ],
          "resources" => ["notes://guide"],
          "prompts" => ["summarize"],
          "env" => %{"PATH" => Path.join(to_string(:code.root_dir()), "bin") <> ":/usr/bin:/bin"},
          "timeout_ms" => 5_000
        }
      ]
    }

    path = Path.join(ctx.root, "mcp.json")
    File.write!(path, Jason.encode!(document))
    {:ok, servers} = Config.load(path)

    config = %{
      provider: :demo,
      model: "catalog-fixture",
      provider_module: Model,
      test_pid: self(),
      home: Path.join(ctx.root, "home"),
      mcp_servers: servers,
      approval: Keyword.get(opts, :approval, :ask)
    }

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Ipse.Session,
         config: config, cwd: ctx.root, state_dir: ctx.dir, id: id, subscriber: self()}
      )

    on_exit(fn -> if Process.alive?(pid), do: Ipse.Session.close(pid) end)
    pid
  end
end
