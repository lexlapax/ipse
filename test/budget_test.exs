Code.require_file("../priv/cost-report-demo.exs", __DIR__)
Code.require_file("../priv/budget-demo.exs", __DIR__)

defmodule Ipse.BudgetTest do
  use ExUnit.Case, async: false
  alias Ipse.{Budget, Usage, Session}
  alias Ipse.Budget.{Ledger, Policy, Store}

  defmodule Model do
    def complete(config, messages, tools, emit) do
      send(
        config.test_pid,
        {:budget_provider, self(), config[:delegation_origin], config[:max_output_tokens]}
      )

      cond do
        config[:fixture_observation_gate] ->
          receive do
            :observe ->
              emit.({:provider_usage, %{"input_tokens" => 60, "output_tokens" => 3}})

              {:ok, %{"role" => "assistant", "content" => "done"},
               %{"input_tokens" => 60, "output_tokens" => 3}}
          end

        config[:fixture_summary] == true and tools == [] ->
          {:ok,
           %{
             "role" => "assistant",
             "content" =>
               Jason.encode!(%{
                 "decisions" => [],
                 "facts" => ["Synthetic earlier findings"],
                 "open_questions" => []
               })
           }, %{"input_tokens" => 7, "output_tokens" => 3}}

        config[:fixture_summary] == true ->
          {:ok, %{"role" => "assistant", "content" => String.duplicate("synthetic ", 600)},
           %{"input_tokens" => 7, "output_tokens" => 3}}

        config[:fixture_wait] ->
          receive do
            :finish ->
              {:ok, %{"role" => "assistant", "content" => "done"},
               %{"input_tokens" => 7, "output_tokens" => 3}}
          end

        config[:fixture_delegate] == true and config[:delegation_origin] == nil and
            not Enum.any?(messages, &(&1["role"] == "tool")) ->
          {:ok,
           %{
             "role" => "assistant",
             "content" => "",
             "tool_calls" => [
               %{
                 "id" => "two",
                 "type" => "function",
                 "function" => %{
                   "name" => "delegate_parallel",
                   "arguments" =>
                     Jason.encode!(%{
                       "tasks" => [
                         %{"task" => "First", "context" => "Synthetic"},
                         %{"task" => "Second", "context" => "Synthetic"}
                       ]
                     })
                 }
               }
             ]
           }, %{"input_tokens" => 7, "output_tokens" => 3}}

        true ->
          if config[:fixture_peak] == true do
            emit.({:provider_usage, %{"input_tokens" => 60, "output_tokens" => 2}})
          end

          emit.({:provider_usage, %{"input_tokens" => 7, "output_tokens" => 3}})

          {:ok, %{"role" => "assistant", "content" => "done"},
           %{"input_tokens" => 7, "output_tokens" => 3}}
      end
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-budget-#{Usage.id()}")
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    dir = Path.join(root, "sessions")
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, dir: dir}
  end

  defp policy,
    do: %{
      "version" => 1,
      "max_requests" => 2,
      "max_input_tokens" => 100,
      "reserve_input_tokens" => 40,
      "max_output_tokens" => 100,
      "reserve_output_tokens" => 32
    }

  defp attached(c, policy \\ policy()) do
    id = Usage.id()
    config = %{provider: :openai, model: "cost-fixture", budget: policy}
    assert {:ok, config} = Store.attach(config, c.dir, id, true)
    {id, config}
  end

  defp admission(config, id), do: Usage.admission(id, config, "model", Usage.id())

  defp response(input, output),
    do:
      {:ok, %{"role" => "assistant", "content" => "synthetic"},
       %{"input_tokens" => input, "output_tokens" => output}}

  defp booked(snapshot), do: Map.new(snapshot["dimensions"], &{&1["unit"], &1["booked"]})

  defp start(c, config, id \\ nil) do
    opts = [config: config, cwd: c.root, state_dir: c.dir, id: id, subscriber: self()]
    result = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})

    if match?({:ok, _}, result) do
      {:ok, pid} = result
      on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    end

    result
  end

  defp done(pid) do
    receive do
      {:ipse, ^pid, {:done, outcome}} -> outcome
      {:ipse, ^pid, _} -> done(pid)
    after
      15_000 -> flunk("budget session did not finish")
    end
  end

  test "the source and bundled runtime exercise the same shared-budget fixture" do
    assert :ok = Ipse.BudgetDemo.run()
  end

  test "closed policies reject missing reservations, unsafe prices, project replacement and unsupported output bounds",
       c do
    assert :ok = Policy.validate(policy())

    for value <- [
          %{"version" => 1},
          Map.delete(policy(), "reserve_input_tokens"),
          Map.put(policy(), "max_requests", 2.0),
          Map.put(policy(), "unknown", "zero"),
          Map.put(policy(), "money", []),
          Map.put(policy(), "reserve_output_tokens", -1)
        ] do
      assert {:error, _} = Policy.validate(value)
    end

    assert {:error, _} = Policy.runtime(%{provider: :chatgpt, budget: policy()})

    assert :ok =
             Policy.runtime(%{provider: :chatgpt, budget: %{"version" => 1, "max_requests" => 2}})

    assert {:error, _} = Policy.resolve([%{scope: "project", data: %{"budget" => policy()}}])
    home = Path.join(c.root, "home")
    File.mkdir_p!(home)

    File.write!(
      Path.join(home, "config.json"),
      Jason.encode!(%{
        "version" => 1,
        "settings" => %{"provider" => "openai"},
        "budget" => policy()
      })
    )

    assert {:ok, effective} = Ipse.Config.resolve(c.root, home, [project_config: false], %{})
    assert effective.budget == policy()
    assert Ipse.Config.manifest(effective).budget == policy()
  end

  test "full known usage releases unused bookings; failure holds reservations and refusal never calls a provider",
       c do
    {id, config} = attached(c)
    a = admission(config, id)

    assert {:ok, _, _} =
             Budget.run(config, a, fn _ -> :ok end, fn cfg, _ ->
               assert cfg.max_output_tokens == 32
               response(7, 3)
             end)

    assert {:ok, snap} = Budget.snapshot(config)
    assert booked(snap) == %{"requests" => 1, "input_tokens" => 7, "output_tokens" => 3}

    assert {:error, "synthetic refusal"} =
             Budget.run(config, admission(config, id), fn _ -> :ok end, fn _, emit ->
               emit.({:provider_usage, %{"input_tokens" => 9, "output_tokens" => 4}})
               {:error, "synthetic refusal"}
             end)

    assert {:ok, snap} = Budget.snapshot(config)
    assert booked(snap) == %{"requests" => 2, "input_tokens" => 47, "output_tokens" => 35}
    assert snap["partial_count"] == 1

    assert {:error, error} =
             Budget.run(config, admission(config, id), fn _ -> :ok end, fn _, _ ->
               send(self(), :unexpected_budget_dispatch)
               response(7, 3)
             end)

    assert error =~ "no provider request was dispatched"
    assert {:ok, %{"refused_count" => 1}} = Budget.snapshot(config)
    refute_receive :unexpected_budget_dispatch, 20
  end

  test "parallel processes atomically book one remaining request and keep the lock inode", c do
    {id, config} = attached(c, %{"version" => 1, "max_requests" => 1})
    lockpath = Path.join([c.dir, "budgets", id <> ".lock"])
    {:ok, before} = File.stat(lockpath)

    results =
      for _ <- 1..12 do
        Task.async(fn -> Budget.decide(config, admission(config, id)) end)
      end
      |> Enum.map(&Task.await(&1, 20_000))

    assert Enum.count(results, &(&1 == {:ok, :reserved})) == 1
    assert Enum.count(results, &(&1 == {:ok, :refused})) == 11
    {:ok, after_stat} = File.stat(lockpath)
    assert before.inode == after_stat.inode
    assert {:ok, snap} = Budget.snapshot(config)
    assert booked(snap)["requests"] == 1
    assert snap["refused_count"] == 11
  end

  test "killed request ownership leaves durable unknown liability and no automatic refund", c do
    {id, config} = attached(c)
    owner = self()

    task =
      Task.Supervisor.async_nolink(Ipse.Tasks, fn ->
        Budget.run(config, admission(config, id), fn _ -> :ok end, fn _, emit ->
          emit.({:provider_usage, %{"input_tokens" => 9, "output_tokens" => 4}})
          send(owner, :budget_waiting)

          receive do
            :never -> response(9, 4)
          end
        end)
      end)

    assert_receive :budget_waiting, 5_000
    Task.shutdown(task, :brutal_kill)
    assert {:ok, snap} = Budget.snapshot(config)
    assert snap["unsettled_count"] == 1
    assert booked(snap) == %{"requests" => 1, "input_tokens" => 40, "output_tokens" => 32}
    assert {:ok, _} = Store.attach(Map.delete(config, :budget_root), c.dir, id, false)
    assert {:ok, ^snap} = Budget.snapshot(config)
  end

  test "monetary estimates reconcile fixed-point values without mixing subscription and API bases",
       c do
    card = Ipse.CostReportDemo.card()

    money = %{
      "version" => 1,
      "money" => [
        %{"basis" => "api_estimate", "limit_nanos" => 500_000, "reserve_nanos" => 450_000},
        %{"basis" => "api_equivalent", "limit_nanos" => 900_000, "reserve_nanos" => 800_000}
      ],
      "rate_card" => card
    }

    {id, config} = attached(c, money)

    assert {:ok, _, _} =
             Budget.run(config, admission(config, id), fn _ -> :ok end, fn _, _ ->
               response(100, 20)
             end)

    assert {:ok, snap} = Budget.snapshot(config)
    assert booked(snap) == %{"money:api_estimate" => 400_000, "money:api_equivalent" => 0}

    subscription =
      Usage.admission(
        Usage.id(),
        %{provider: :chatgpt, model: "cost-fixture"},
        "model",
        Usage.id()
      )

    assert Policy.reservation(money, subscription) == %{
             "money:api_estimate" => 0,
             "money:api_equivalent" => 800_000
           }

    assert {:error, _} =
             Budget.run(config, admission(config, id), fn _ -> :ok end, fn _, _ ->
               send(self(), :unexpected_budget_dispatch)
               response(7, 3)
             end)

    refute_receive :unexpected_budget_dispatch, 20
  end

  test "live cached state folds a valid external tail and still rejects invalid tails or same-size rewrites",
       c do
    {id, config} = attached(c)
    first = admission(config, id)
    assert {:ok, :reserved} = Budget.decide(config, first)
    assert {:ok, %{"request_count" => 1}} = Budget.snapshot(config)
    second = admission(config, id)

    assert {:ok, :reserved} =
             Store.transaction(config.budget_root, config.budget, fn state ->
               assert {:ok, event, _, :reserved} = Ledger.decide(state, second)
               {:append, event, :reserved}
             end)

    assert {:ok, %{"request_count" => 2}} = Budget.snapshot(config)
    assert {:ok, :refused} = Budget.decide(config, admission(config, id))

    ledger = Path.join([c.dir, "budgets", id <> ".jsonl"])
    bytes = File.read!(ledger)
    changed = String.replace(bytes, "cost-fixture", "lost-fixture")
    assert byte_size(changed) == byte_size(bytes) and changed != bytes
    File.write!(ledger, changed)
    assert {:error, _} = Budget.snapshot(config)

    {other_id, other} = attached(c)
    assert {:ok, :reserved} = Budget.decide(other, admission(other, other_id))
    assert {:ok, _} = Budget.snapshot(other)
    path = Path.join([c.dir, "budgets", other_id <> ".jsonl"])
    File.write!(path, "{\"type\":\"unsupported\"}\n", [:append])
    invalid = File.read!(path)
    assert {:error, _} = Budget.snapshot(other)
    assert File.read!(path) == invalid
  end

  test "session resume is inert; a valid-prefix ledger rollback refuses before tail repair", c do
    config = %{
      provider: :openai,
      model: "cost-fixture",
      provider_module: Model,
      test_pid: self(),
      home: Path.join(c.root, "home"),
      budget: policy(),
      approval: :deny
    }

    assert {:ok, pid} = start(c, config)
    :ok = Session.prompt(pid, "synthetic task")
    assert done(pid) == :ok
    assert_receive {:budget_provider, _, nil, 32}, 5_000
    id = Session.info(pid).id
    assert :ok = Session.close(pid)
    journal = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(journal)
    assert {:ok, resumed} = start(c, config, id)
    assert File.read!(journal) == before
    assert :ok = Session.close(resumed)
    ledger = Path.join([c.dir, "budgets", id <> ".jsonl"])
    [header | _] = File.read!(ledger) |> String.split("\n", trim: true)
    File.write!(ledger, header <> "\n")
    File.write!(journal, "{torn", [:append])
    broken = File.read!(journal)
    assert {:error, :budget_sources_unavailable} = start(c, config, id)
    assert File.read!(journal) == broken
    refute_receive {:budget_provider, _, _, _}, 20
  end

  test "real parallel children share the parent's remaining admission quota", c do
    config = %{
      provider: :openai,
      model: "cost-fixture",
      provider_module: Model,
      test_pid: self(),
      home: Path.join(c.root, "home"),
      budget: %{"version" => 1, "max_requests" => 3},
      fixture_delegate: true,
      subagents: true,
      subagent_concurrency: 2,
      approval: :allow,
      compact: false
    }

    assert {:ok, pid} = start(c, config)
    :ok = Session.prompt(pid, "Delegate the two synthetic tasks")
    assert done(pid) == :error
    id = Session.info(pid).id
    assert_receive {:budget_provider, _, nil, nil}, 5_000
    assert_receive {:budget_provider, _, %{"parent_session_id" => ^id}, nil}, 5_000
    assert_receive {:budget_provider, _, %{"parent_session_id" => ^id}, nil}, 5_000

    refute_receive {:budget_provider, _, _, _}, 20
    assert :ok = Session.close(pid)
    assert {:ok, snap} = Budget.saved(c.dir, id)
    assert snap["request_count"] == 3
    assert snap["refused_count"] >= 1
    assert {:ok, resumed} = start(c, config, id)
    assert :ok = Session.close(resumed)
  end

  test "last-slot child contention retains its booking even if sibling failure cancels dispatch",
       c do
    config = %{
      provider: :openai,
      model: "cost-fixture",
      provider_module: Model,
      test_pid: self(),
      home: Path.join(c.root, "home"),
      budget: %{"version" => 1, "max_requests" => 2},
      fixture_delegate: true,
      subagents: true,
      subagent_concurrency: 2,
      approval: :allow,
      compact: false
    }

    assert {:ok, pid} = start(c, config)
    :ok = Session.prompt(pid, "Contend for the final shared slot")
    assert done(pid) == :error
    id = Session.info(pid).id
    assert_receive {:budget_provider, _, nil, nil}, 5_000

    receive do
      {:budget_provider, _, %{"parent_session_id" => ^id}, nil} -> :ok
    after
      20 -> :ok
    end

    refute_receive {:budget_provider, _, _, _}, 20
    assert :ok = Session.close(pid)
    assert {:ok, snapshot} = Budget.saved(c.dir, id)
    assert snapshot["request_count"] == 2
    assert snapshot["refused_count"] >= 1
    assert booked(snapshot)["requests"] == 2
    refute snapshot["overdrawn"]
  end

  test "resume checks earlier own-source peaks instead of trusting the latest smaller counters",
       c do
    config = %{
      provider: :openai,
      model: "cost-fixture",
      provider_module: Model,
      test_pid: self(),
      fixture_peak: true,
      home: Path.join(c.root, "home"),
      budget: policy(),
      approval: :deny
    }

    assert {:ok, pid} = start(c, config)
    :ok = Session.prompt(pid, "Synthetic nonmonotonic observations")
    assert done(pid) == :ok
    id = Session.info(pid).id
    assert :ok = Session.close(pid)
    assert {:ok, before} = Budget.saved(c.dir, id)
    assert booked(before)["input_tokens"] == 60
    ledger = Path.join([c.dir, "budgets", id <> ".jsonl"])
    prefix = File.read!(ledger) |> String.split("\n", trim: true) |> Enum.take(3)
    File.write!(ledger, Enum.join(prefix, "\n") <> "\n")
    journal = Path.join(c.dir, id <> ".jsonl")
    File.write!(journal, "{torn", [:append])
    original = File.read!(journal)
    assert {:error, :budget_sources_unavailable} = start(c, config, id)
    assert File.read!(journal) == original
  end

  test "resume checks historical child peaks without granting child transcript access", c do
    limits = policy() |> Map.put("max_requests", 10) |> Map.put("max_input_tokens", 1000)

    config = %{
      provider: :openai,
      model: "cost-fixture",
      provider_module: Model,
      test_pid: self(),
      fixture_peak: true,
      fixture_delegate: true,
      home: Path.join(c.root, "home"),
      budget: limits,
      approval: :allow,
      subagents: true,
      subagent_concurrency: 2,
      compact: false
    }

    assert {:ok, pid} = start(c, config)
    :ok = Session.prompt(pid, "Synthetic child observation peaks")
    assert done(pid) == :ok
    id = Session.info(pid).id
    assert :ok = Session.close(pid)
    ledger = Path.join([c.dir, "budgets", id <> ".jsonl"])
    records = File.read!(ledger) |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    child =
      Enum.find(records, &(&1["type"] == "reserved" and &1["admission"]["session_id"] != id))

    request = child["admission"]["request_id"]

    filtered =
      Enum.reject(
        records,
        &(&1["type"] == "observed" and &1["request_id"] == request and
            &1["usage"]["counts"]["input_tokens"] == 60)
      )

    assert length(filtered) == length(records) - 1
    File.write!(ledger, Enum.map(filtered, &(Jason.encode!(&1) <> "\n")))
    journal = Path.join(c.dir, id <> ".jsonl")
    File.write!(journal, "{torn", [:append])
    original = File.read!(journal)
    assert {:error, :budget_sources_unavailable} = start(c, config, id)
    assert File.read!(journal) == original
  end

  test "a budget refusal cannot conceal canonical usage evidence", c do
    config = %{
      provider: :openai,
      model: "cost-fixture",
      provider_module: Model,
      test_pid: self(),
      home: Path.join(c.root, "home"),
      budget: %{"version" => 1, "max_requests" => 0},
      approval: :deny
    }

    assert {:ok, pid} = start(c, config)
    :ok = Session.prompt(pid, "Synthetic refusal")
    assert done(pid) == :error
    id = Session.info(pid).id
    assert :ok = Session.close(pid)
    refute_receive {:budget_provider, _, _, _}, 20
    assert {:ok, events} = Ipse.Journal.load(c.dir, id)
    usage = Ipse.Usage.Normalizer.normalize(:openai, %{"input_tokens" => 7, "output_tokens" => 3})

    forged =
      Enum.map(events, fn event ->
        if event["type"] == "request_finished", do: %{event | "usage" => usage}, else: event
      end)

    journal = Path.join(c.dir, id <> ".jsonl")
    File.write!(journal, Enum.map(forged, &(Jason.encode!(&1) <> "\n")))
    File.write!(journal, "{torn", [:append])
    original = File.read!(journal)
    assert {:error, :budget_sources_unavailable} = start(c, config, id)
    assert File.read!(journal) == original
  end

  test "compaction and main requests consume the same durable quota", c do
    config = %{
      provider: :openai,
      model: "cost-fixture",
      provider_module: Model,
      test_pid: self(),
      fixture_summary: true,
      approval: :deny,
      home: Path.join(c.root, "home"),
      context_bytes: 80_000,
      compact_threshold_bytes: 20_000,
      budget: Map.put(policy(), "max_requests", 5)
    }

    assert {:ok, pid} = start(c, config)

    outcome =
      Enum.reduce_while(1..8, nil, fn index, _ ->
        :ok = Session.prompt(pid, "Synthetic bounded turn #{index}")

        case done(pid) do
          :ok -> {:cont, :ok}
          :error -> {:halt, :error}
        end
      end)

    assert outcome == :error
    id = Session.info(pid).id
    assert :ok = Session.close(pid)
    assert {:ok, %{"request_count" => 5}} = Budget.saved(c.dir, id)
    assert {:ok, events} = Ipse.Journal.load(c.dir, id)
    assert Enum.any?(events, &(&1["type"] == "request_admitted" and &1["kind"] == "compaction"))
    assert Enum.any?(events, &(&1["type"] == "context_compacted"))
  end

  test "usage reaches the canonical consumer only after the ledger covers it", c do
    {id, config} = attached(c)

    assert {:ok, _, _} =
             Budget.run(
               config,
               admission(config, id),
               fn {:provider_usage, %{"input_tokens" => 60}} ->
                 assert {:ok, snapshot} = Budget.snapshot(config)
                 assert booked(snapshot)["input_tokens"] == 60
               end,
               fn _, emit ->
                 emit.({:provider_usage, %{"input_tokens" => 60, "output_tokens" => 3}})
                 response(60, 3)
               end
             )
  end

  test "observation lock refusal does not strand an honest session on resume", c do
    config = %{
      provider: :openai,
      model: "cost-fixture",
      provider_module: Model,
      test_pid: self(),
      fixture_observation_gate: true,
      home: Path.join(c.root, "home"),
      budget: policy(),
      approval: :deny
    }

    assert {:ok, pid} = start(c, config)
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "Synthetic observation above reservation")
    assert_receive {:budget_provider, provider, nil, 32}, 5_000
    assert {:ok, lock} = Ipse.Runner.lock(Path.join([c.dir, "budgets", id <> ".lock"]))

    try do
      send(provider, :observe)
      assert done(pid) == :error
    after
      Ipse.Runner.unlock(lock)
    end

    assert {:ok, snapshot} = Budget.saved(c.dir, id)
    assert booked(snapshot)["input_tokens"] == 40
    assert snapshot["unknown_liability_count"] == 1
    assert {:ok, events} = Ipse.Journal.load(c.dir, id)
    refute Enum.any?(events, &(&1["type"] == "request_usage_observed"))
    assert {:ok, usage} = Usage.restore(events, id)
    [request] = Map.values(usage.requests)
    assert request.completion["outcome"] == "failed"
    assert request.completion["usage"]["quality"] == "unavailable"
    assert :ok = Session.close(pid)
    journal = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(journal)
    assert {:ok, resumed} = start(c, config, id)
    assert File.read!(journal) == before
    refute_receive {:budget_provider, _, _, _}, 50
    assert :ok = Session.close(resumed)
  end

  test "worker loss after ledger commit cannot leave canonical usage ahead of liability", c do
    {id, config} = attached(c)
    admitted = admission(config, id)

    {worker, monitor} =
      spawn_monitor(fn ->
        Budget.run(
          config,
          admitted,
          fn {:provider_usage, _} -> Process.exit(self(), :kill) end,
          fn _, emit ->
            emit.({:provider_usage, %{"input_tokens" => 60, "output_tokens" => 3}})
            response(60, 3)
          end
        )
      end)

    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}, 5_000
    assert {:ok, snapshot} = Budget.snapshot(config)
    assert snapshot["unsettled_count"] == 1
    assert booked(snapshot)["input_tokens"] == 60
    assert :ok = Budget.validate_sources(config, id, [admitted])
  end

  test "observed overdraw persists liability and prevents further dispatch", c do
    limits = policy() |> Map.put("max_input_tokens", 50)
    {id, config} = attached(c, limits)

    owner = self()

    assert {:error, _} =
             Budget.run(config, admission(config, id), &send(owner, &1), fn _, emit ->
               emit.({:provider_usage, %{"input_tokens" => 60, "output_tokens" => 1}})
               send(self(), :unexpected_budget_dispatch)
               response(7, 3)
             end)

    assert {:ok, snapshot} = Budget.snapshot(config)
    assert snapshot["overdrawn"]
    assert booked(snapshot)["input_tokens"] == 60
    assert snapshot["unknown_liability_count"] == 1
    assert_receive {:provider_usage, %{"input_tokens" => 60, "output_tokens" => 1}}

    assert {:error, _} =
             Budget.run(config, admission(config, id), fn _ -> :ok end, fn _, _ ->
               send(self(), :unexpected_budget_dispatch)
               response(7, 3)
             end)

    refute_receive :unexpected_budget_dispatch, 20
  end

  test "final-only overdraw keeps actual counters and refuses assistant admission", c do
    {id, config} = attached(c, Map.put(policy(), "max_input_tokens", 50))
    owner = self()

    assert {:error, error} =
             Budget.run(config, admission(config, id), &send(owner, &1), fn _, _ ->
               response(60, 3)
             end)

    assert error =~ "exceeds the shared limit"
    assert_receive {:provider_usage, %{"input_tokens" => 60, "output_tokens" => 3}}
    assert {:ok, snapshot} = Budget.snapshot(config)
    assert snapshot["overdrawn"]
    assert booked(snapshot)["input_tokens"] == 60
  end

  test "unconfirmed settlement cannot publish uncovered final usage and retains unknown liability",
       c do
    {id, config} = attached(c)
    ledger = Path.join([c.dir, "budgets", id <> ".jsonl"])
    owner = self()

    assert {:error, error} =
             Budget.run(config, admission(config, id), &send(owner, &1), fn _, _ ->
               File.chmod!(ledger, 0o644)
               response(60, 3)
             end)

    assert error =~ "settlement is unconfirmed"
    refute_receive {:provider_usage, _}, 20
    File.chmod!(ledger, 0o600)
    assert {:ok, snapshot} = Budget.snapshot(config)
    assert snapshot["unsettled_count"] == 1
    assert booked(snapshot)["input_tokens"] == 40
  end

  test "completed missing metering and unavailable rates retain explicitly unknown reservations",
       c do
    {id, config} = attached(c)

    assert {:ok, _, _} =
             Budget.run(config, admission(config, id), fn _ -> :ok end, fn _, _ ->
               {:ok, %{"role" => "assistant", "content" => "done"}, %{}}
             end)

    assert {:ok, snapshot} = Budget.snapshot(config)
    assert snapshot["unknown_liability_count"] == 1
    assert booked(snapshot)["input_tokens"] == 40
    assert booked(snapshot)["output_tokens"] == 32

    card = %{Ipse.CostReportDemo.card() | "rows" => []}

    money = %{
      "version" => 1,
      "money" => [%{"basis" => "api_estimate", "limit_nanos" => 1000, "reserve_nanos" => 700}],
      "rate_card" => card
    }

    {other, config} = attached(c, money)

    assert {:ok, _, _} =
             Budget.run(config, admission(config, other), fn _ -> :ok end, fn _, _ ->
               response(7, 3)
             end)

    assert {:ok, snapshot} = Budget.snapshot(config)
    assert booked(snapshot)["money:api_estimate"] == 700
    assert snapshot["currency"] == "USD"
    assert snapshot["currency_scale"] == 9
    assert snapshot["unknown_liability_count"] == 1
  end

  test "pure replay rejects unsupported completions, duplicate attempts and foreign source scope",
       c do
    {id, config} = attached(c)
    a = admission(config, id)
    root = Store.identity(config.budget_root)
    header = Ledger.header(root, policy())
    assert {:ok, initial} = Ledger.restore([header], root, policy())
    assert {:ok, event, reserved} = Ledger.reserve(initial, a)
    assert {:error, _} = Ledger.reserve(reserved, %{a | "request_id" => Usage.id()})
    assert {:error, _} = Ledger.reserve(initial, %{a | "session_id" => Usage.id()})
    completion = Usage.completion(a, response(7, 3), 0, nil)
    settled = %{"type" => "settled", "completion" => completion}
    assert {:error, _} = Ledger.restore([header, event, settled], root, policy())

    dispatch = %{
      "type" => "dispatch_intent",
      "request_id" => a["request_id"],
      "attempt_id" => a["attempt_id"]
    }

    assert {:ok, _} = Ledger.restore([header, event, dispatch, settled], root, policy())

    assert {:error, _} =
             Ledger.restore(
               [header, event, dispatch, put_in(settled, ["completion", "version"], 2)],
               root,
               policy()
             )
  end

  test "cancelled sessions retain booking and resume without changing either ledger", c do
    config = %{
      provider: :openai,
      model: "cost-fixture",
      provider_module: Model,
      test_pid: self(),
      home: Path.join(c.root, "home"),
      budget: policy(),
      approval: :deny,
      fixture_wait: true
    }

    assert {:ok, pid} = start(c, config)
    :ok = Session.prompt(pid, "wait")
    assert_receive {:budget_provider, provider, nil, 32}, 5_000
    :ok = Session.cancel(pid)
    refute Process.alive?(provider)
    id = Session.info(pid).id
    assert :ok = Session.close(pid)

    assert {:ok, %{"unsettled_count" => 1, "unknown_liability_count" => 1}} =
             Budget.saved(c.dir, id)

    path = Path.join([c.dir, "budgets", id <> ".jsonl"])
    before = File.read!(path)
    assert {:ok, resumed} = start(c, config, id)
    assert File.read!(path) == before
    refute_receive {:budget_provider, _, _, _}, 20
    assert :ok = Session.close(resumed)
  end

  test "live prefix rollback and loss of the root owner prevent further dispatch", c do
    {id, config} = attached(c)
    path = Path.join([c.dir, "budgets", id <> ".jsonl"])
    original = File.read!(path)

    assert {:ok, _, _} =
             Budget.run(config, admission(config, id), fn _ -> :ok end, fn _, _ ->
               response(7, 3)
             end)

    File.write!(path, original)

    assert {:error, _} =
             Budget.run(config, admission(config, id), fn _ -> :ok end, fn _, _ ->
               send(self(), :unexpected_budget_dispatch)
               response(7, 3)
             end)

    owner = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        {other, cfg} = attached(c)
        send(owner, {:owned_budget, other, cfg})
      end)

    assert_receive {:owned_budget, other, orphan}, 5_000
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 5_000

    assert {:error, _} =
             Budget.run(orphan, admission(orphan, other), fn _ -> :ok end, fn _, _ ->
               send(self(), :unexpected_budget_dispatch)
               response(7, 3)
             end)

    refute_receive :unexpected_budget_dispatch, 20
  end

  test "money overflow persists an overdraw instead of becoming zero or unknown", c do
    card = Ipse.CostReportDemo.card()
    [row] = card["rows"]

    card = %{
      card
      | "rows" => [%{row | "rates" => %{"input" => "1000000", "output" => "1000000"}}]
    }

    limits = %{
      "version" => 1,
      "money" => [
        %{"basis" => "api_estimate", "limit_nanos" => 9_007_199_254_740_991, "reserve_nanos" => 1}
      ],
      "rate_card" => card
    }

    {id, config} = attached(c, limits)

    assert {:error, _} =
             Budget.run(config, admission(config, id), fn _ -> :ok end, fn _, emit ->
               emit.(
                 {:provider_usage, %{"input_tokens" => 100_000_000_000, "output_tokens" => 1}}
               )

               send(self(), :unexpected_budget_dispatch)
               response(7, 3)
             end)

    assert {:ok, snapshot} = Budget.snapshot(config)
    assert snapshot["overdrawn"]
    assert [%{"booked" => nil, "overflow" => true}] = snapshot["dimensions"]
    refute_receive :unexpected_budget_dispatch, 20
  end

  test "selected profiles preserve private shared-budget authority and refuse unsupported caps",
       c do
    {_id, config} = attached(c)

    profile = %{
      "provider" => "openai",
      "model" => "cost-fixture",
      "max_steps" => 4,
      "timeout_ms" => 120_000
    }

    config = Map.merge(config, %{profiles: %{"routine" => profile}, roles: %{}})
    assert {:ok, child} = Ipse.Profiles.child_config(config, %{}, %{"profile" => "routine"})
    assert child.budget === config.budget
    assert child.budget_root === config.budget_root
    assert child.budget_checkpoint === config.budget_checkpoint

    config = put_in(config, [:profiles, "routine", "provider"], "chatgpt")
    assert {:error, _} = Ipse.Profiles.child_config(config, %{}, %{"profile" => "routine"})
  end

  test "missing and unsafe budget state refuses resume without repair or recreating lock inodes",
       c do
    config = %{provider: :openai, model: "cost-fixture", budget: policy(), approval: :deny}
    assert {:ok, pid} = start(c, config)
    id = Session.info(pid).id
    assert :ok = Session.close(pid)
    lock = Path.join([c.dir, "budgets", id <> ".lock"])
    ledger = Path.join([c.dir, "budgets", id <> ".jsonl"])
    journal = Path.join(c.dir, id <> ".jsonl")
    File.write!(journal, "{torn", [:append])
    before = File.read!(journal)
    File.rm!(lock)
    assert {:error, _} = start(c, config, id)
    refute File.exists?(lock)
    assert File.read!(journal) == before
    File.write!(lock, "")
    File.chmod!(lock, 0o600)
    File.chmod!(ledger, 0o644)
    assert {:error, _} = start(c, config, id)
    assert File.read!(journal) == before
    File.chmod!(ledger, 0o600)
    File.rm!(ledger)
    assert {:error, _} = start(c, config, id)
    refute File.exists?(ledger)
    assert File.read!(journal) == before
  end
end
