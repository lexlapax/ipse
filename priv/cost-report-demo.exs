defmodule Ipse.CostReportDemo do
  @moduledoc false
  alias Ipse.{Session, Usage}

  defmodule Model do
    def complete(config, messages, _, _) do
      if config[:fixture_delegate] == true and config[:delegation_origin] == nil and
           not Enum.any?(messages, &(&1["role"] == "tool")) do
        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "fixture-call",
               "type" => "function",
               "function" => %{
                 "name" => "delegate_parallel",
                 "arguments" =>
                   Jason.encode!(%{
                     "tasks" => [
                       %{"task" => "First synthetic child", "context" => "Synthetic"},
                       %{"task" => "Second synthetic child", "context" => "Synthetic"}
                     ]
                   })
               }
             }
           ]
         }, %{"input_tokens" => 100, "output_tokens" => 20}}
      else
        complete_fixture(config)
      end
    end

    defp complete_fixture(config) do
      if config[:fixture_fail],
        do: {:error, "Synthetic request refusal"},
        else:
          {:ok, %{"role" => "assistant", "content" => "Synthetic private answer"},
           config[:fixture_usage] || %{"input_tokens" => 100, "output_tokens" => 20}}
    end
  end

  def card do
    %{
      "version" => 1,
      "id" => "synthetic-only",
      "revision" => "fixture-1",
      "currency" => "USD",
      "source" => "operator:synthetic-fixture",
      "published_on" => "2026-10-17",
      "rows" => [
        %{
          "id" => "fixture",
          "provider" => "openai",
          "billing_mode" => "api",
          "basis" => "api_estimate",
          "model" => "cost-fixture",
          "endpoint_sha256" => nil,
          "from" => "2000-01-01",
          "until" => nil,
          "input_min" => 0,
          "input_max" => nil,
          "input_mode" => "flat",
          "rates" => %{"input" => "2", "output" => "10"}
        }
      ]
    }
  end

  def config(home, enabled \\ true, rates \\ card(), kind \\ :page) do
    {artifact, capabilities} =
      case kind do
        :tree ->
          {"builtin:cost-tree:1",
           ~w(invoke.command host.actions host.usage host.usage.scan host.usage.children)}

        :summary ->
          {"builtin:cost-summary:1", ~w(invoke.command host.actions host.usage host.usage.scan)}

        :page ->
          {"builtin:cost-report:1", ~w(invoke.command host.actions host.usage)}
      end

    data = %{
      "extensions" => [
        %{
          "instance" => "costs",
          "artifact" => artifact,
          "enabled" => enabled,
          "options" => %{"rate_card" => rates},
          "order" => 0,
          "lifetime" => "persistent"
        }
      ],
      "extension_trust" => [
        %{
          "artifact" => artifact,
          "capabilities" => capabilities,
          "allow_project" => false,
          "allow_children" => false
        }
      ]
    }

    {:ok, catalog} =
      Ipse.Extensions.Config.resolve(
        [%{scope: "operator", path: "/synthetic/costs.json", data: data}],
        []
      )

    {:ok, entries} = Ipse.Extensions.Registry.prepare(catalog, home)

    %{
      provider: :openai,
      model: "cost-fixture",
      provider_module: Model,
      home: home,
      extensions: entries,
      compact: false,
      approval: :deny
    }
  end

  def run do
    {:ok, _} = Application.ensure_all_started(:ipse)
    root = Path.join(System.tmp_dir!(), "ipse-cost-report-#{Usage.id()}")
    File.mkdir_p!(root)
    Process.put({__MODULE__, :sessions}, [])

    try do
      home = Path.join(root, "home")
      dir = Path.join(root, "sessions")
      {:ok, inactive} = start(config(home, false), root, dir)
      [] = Session.exports(inactive)["entries"]
      :ok = Session.close(inactive)
      cfg = Map.put(config(home), :max_output_tokens, 64)
      %{"max_output_tokens" => 64} = Ipse.Provider.OpenAI.request_body(cfg, [], [])

      %{"max_tokens" => 64} =
        Ipse.Provider.Anthropic.request_body(%{cfg | provider: :anthropic}, [], [])

      {:error, _} = Ipse.Provider.Limits.validate(%{cfg | provider: :chatgpt})
      {:ok, pid} = start(cfg, root, dir)
      :ok = Session.prompt(pid, "Synthetic private prompt")
      :ok = done(pid)
      value = report(pid)

      unless value["status"] == "reported",
        do: raise("Synthetic cost report refused: #{inspect(value)}")

      [%{"amount_nanos" => 400_000, "basis" => "api_estimate"}] = value["groups"]
      "page" = value["coverage"]
      1 = Session.info(pid).accounting["request_count"]
      false = Jason.encode!(value) =~ "Synthetic private"
      :ok = Session.prompt(pid, "A second synthetic prompt")
      :ok = done(pid)
      ^value = report(pid, %{"snapshot" => value["snapshot"]})
      id = Session.info(pid).id
      :ok = Session.close(pid)
      {:ok, _} = Ipse.Diagnostics.saved(dir, id)
      path = Path.join(dir, id <> ".jsonl")
      before = File.read!(path)

      {:error, :resume_configuration_mismatch} =
        start(Map.delete(cfg, :max_output_tokens), root, dir, id)

      ^before = File.read!(path)
      {:ok, resumed} = start(cfg, root, dir, id)
      :idle = Session.info(resumed).phase
      ^before = File.read!(path)
      :ok = Session.close(resumed)

      summary_config = config(home, true, card(), :summary)
      {:ok, summary} = start(summary_config, root, dir)

      for n <- 1..5 do
        :ok = Session.prompt(summary, "Synthetic summary input #{n}")
        :ok = done(summary)
      end

      :ok = Session.invoke_export(summary, :command, "ext__costs__summary", %{})
      :ok = done(summary)
      summarized = Session.info(summary).extension_result["value"]

      %{
        "status" => "summarized",
        "request_count" => 5,
        "enumeration_complete" => true,
        "cost_estimate_complete" => true,
        "groups" => [%{"amount_nanos" => 2_000_000}]
      } = summarized

      false = Jason.encode!(summarized) =~ "Synthetic summary input"
      summary_id = Session.info(summary).id
      :ok = Session.close(summary)
      {:ok, _} = Ipse.Diagnostics.saved(dir, summary_id)
      summary_path = Path.join(dir, summary_id <> ".jsonl")
      summary_bytes = File.read!(summary_path)
      {:ok, summary_resumed} = start(summary_config, root, dir, summary_id)
      ^summarized = Session.info(summary_resumed).extension_result["value"]
      ^summary_bytes = File.read!(summary_path)
      :ok = Session.close(summary_resumed)

      tree_config =
        config(home, true, card(), :tree)
        |> Map.merge(%{
          fixture_delegate: true,
          subagents: true,
          subagent_concurrency: 2,
          approval: :allow
        })

      {:ok, tree} = start(tree_config, root, dir)
      :ok = Session.prompt(tree, "Synthetic delegated accounting")
      :ok = done(tree)
      :ok = Session.invoke_export(tree, :command, "ext__costs__tree_summary", %{})
      :ok = done(tree)
      tree_value = Session.info(tree).extension_result["value"]

      %{
        "coverage" => "session_tree",
        "request_count" => 4,
        "child_count" => 2,
        "gap_count" => 0,
        "enumeration_complete" => true,
        "cost_estimate_complete" => true,
        "groups" => [%{"amount_nanos" => 1_600_000}]
      } = tree_value

      tree_id = Session.info(tree).id
      :ok = Session.close(tree)
      {:ok, _} = Ipse.Diagnostics.saved(dir, tree_id)
      tree_path = Path.join(dir, tree_id <> ".jsonl")
      tree_bytes = File.read!(tree_path)
      {:ok, tree_resumed} = start(tree_config, root, dir, tree_id)
      ^tree_value = Session.info(tree_resumed).extension_result["value"]
      ^tree_bytes = File.read!(tree_path)
      :ok = Session.close(tree_resumed)

      IO.puts(
        "Cost report fixture: configured pages, own-session/child summaries and inert resume passed."
      )

      :ok
    after
      Enum.each(Process.get({__MODULE__, :sessions}), fn pid ->
        if Process.alive?(pid), do: Session.close(pid)
      end)

      File.rm_rf!(root)
    end
  end

  defp start(config, cwd, dir, id \\ nil) do
    result =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: config, cwd: cwd, state_dir: dir, id: id, subscriber: self(), owner: self()}
      )

    if match?({:ok, _}, result) do
      {:ok, pid} = result
      Process.put({__MODULE__, :sessions}, [pid | Process.get({__MODULE__, :sessions})])
    end

    result
  end

  defp report(pid, args \\ %{}) do
    :ok = Session.invoke_export(pid, :command, "ext__costs__report", args)
    :ok = done(pid)
    Session.info(pid).extension_result["value"]
  end

  defp done(pid) do
    receive do
      {:ipse, ^pid, {:done, :ok}} -> :ok
      {:ipse, ^pid, {:done, other}} -> raise("Cost fixture operation failed: #{other}")
      {:ipse, ^pid, _} -> done(pid)
    after
      15_000 -> raise("Cost fixture operation timed out")
    end
  end
end
