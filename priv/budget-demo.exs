defmodule Ipse.BudgetDemo do
  @moduledoc false
  alias Ipse.{Budget, Session, Usage}

  defmodule Model do
    def complete(config, messages, tools, emit) do
      Agent.update(config.fixture_counter, &(&1 + 1))
      Ipse.CostReportDemo.Model.complete(config, messages, tools, emit)
    end
  end

  def run do
    {:ok, _} = Application.ensure_all_started(:ipse)
    root = Path.join(System.tmp_dir!(), "ipse-budget-demo-#{Usage.id()}")
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    Process.put({__MODULE__, :sessions}, [])
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    try do
      dir = Path.join(root, "sessions")

      config = %{
        provider: :openai,
        model: "cost-fixture",
        provider_module: Model,
        fixture_counter: counter,
        fixture_delegate: true,
        home: Path.join(root, "home"),
        budget: %{"version" => 1, "max_requests" => 3},
        compact: false,
        approval: :allow,
        subagents: true,
        subagent_concurrency: 2
      }

      {:ok, pid} = start(config, root, dir)
      :ok = Session.prompt(pid, "Synthetic parallel budget admission")

      receive do
        {:ipse, ^pid, {:done, :error}} -> :ok
      after
        15_000 -> raise("Budget fixture did not finish with the expected admission refusal")
      end

      3 = Agent.get(counter, & &1)
      id = Session.info(pid).id
      :ok = Session.close(pid)
      {:ok, snapshot} = Budget.saved(dir, id)
      %{"scope" => "session_tree", "request_count" => 3, "overdrawn" => false} = snapshot
      true = snapshot["refused_count"] >= 1
      journal = Path.join(dir, id <> ".jsonl")
      ledger = Path.join([dir, "budgets", id <> ".jsonl"])
      original_journal = File.read!(journal)
      original_ledger = File.read!(ledger)
      {:ok, resumed} = start(config, root, dir, id)
      :idle = Session.info(resumed).phase
      ^original_journal = File.read!(journal)
      ^original_ledger = File.read!(ledger)
      3 = Agent.get(counter, & &1)
      :ok = Session.close(resumed)

      disabled_dir = Path.join(root, "disabled-sessions")
      {:ok, disabled} = start(Map.delete(config, :budget), root, disabled_dir)
      false = File.exists?(Path.join(disabled_dir, "budgets"))
      :ok = Session.close(disabled)
      3 = Agent.get(counter, & &1)

      IO.puts(
        "Budget fixture: shared parallel admission, refusal, default-off and inert resume passed."
      )

      :ok
    after
      Enum.each(Process.get({__MODULE__, :sessions}), fn pid ->
        if Process.alive?(pid), do: Session.close(pid)
      end)

      Agent.stop(counter)
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
end
