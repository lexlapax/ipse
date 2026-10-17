defmodule Ipse.CostReportDemo do
  @moduledoc false
  alias Ipse.{Session, Usage}

  defmodule Model do
    def complete(config, _, _, _) do
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

  def config(home, enabled \\ true, rates \\ card()) do
    data = %{
      "extensions" => [
        %{
          "instance" => "costs",
          "artifact" => "builtin:cost-report:1",
          "enabled" => enabled,
          "options" => %{"rate_card" => rates},
          "order" => 0,
          "lifetime" => "persistent"
        }
      ],
      "extension_trust" => [
        %{
          "artifact" => "builtin:cost-report:1",
          "capabilities" => ~w(invoke.command host.actions host.usage),
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
      cfg = config(home)
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
      {:ok, resumed} = start(cfg, root, dir, id)
      :idle = Session.info(resumed).phase
      ^before = File.read!(path)
      :ok = Session.close(resumed)

      IO.puts(
        "Cost report fixture: explicit selection/rates, frozen own-session page and inert resume passed."
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
