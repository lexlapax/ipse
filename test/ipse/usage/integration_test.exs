defmodule Ipse.UsageSessionTest do
  use ExUnit.Case, async: false

  defmodule Metered do
    def complete(config, _messages, _tools, emit) do
      send(config.test_pid, {:usage_worker, self()})

      receive do
        {:emit, raw} ->
          emit.({:provider_usage, raw})
          emit.({:provider_usage, raw})
          send(config.test_pid, :usage_emitted)
      end

      receive do
        :finish ->
          {:ok,
           %{
             "role" => "assistant",
             "content" => "visible",
             "provider_data" => %{
               "reported_model" => "actual-model",
               "private" => "synthetic-native-secret"
             }
           }, %{"input_tokens" => 10, "output_tokens" => 4}}

        :fail ->
          {:error, "fixture failure"}
      end
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-metering-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    config = %{
      provider: :openai,
      model: "requested-model",
      provider_module: Metered,
      home: Path.join(root, "home"),
      test_pid: self(),
      approval: :ask
    }

    %{root: root, dir: Path.join(root, "state"), config: config}
  end

  defp start(ctx, id \\ nil) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Ipse.Session,
         config: ctx.config, cwd: ctx.root, state_dir: ctx.dir, id: id, subscriber: self()}
      )

    on_exit(fn -> if Process.alive?(pid), do: Ipse.Session.close(pid) end)
    pid
  end

  defp observe(pid, raw) do
    send(pid, {:emit, raw})
    assert_receive :usage_emitted, 2_000
  end

  test "intent precedes dispatch; final facts exclude source/native text and resume is inert",
       ctx do
    pid = start(ctx)
    :ok = Ipse.Session.prompt(pid, "synthetic-private-prompt")
    assert_receive {:usage_worker, worker}, 2_000
    info = Ipse.Session.info(pid)
    assert [%{"outcome" => "unknown", "billing_mode" => "api"}] = info.accounting["requests"]
    {:ok, before} = Ipse.Journal.load(ctx.dir, info.id)
    assert Enum.any?(before, &(&1["type"] == "request_admitted"))

    observe(worker, %{
      "input_tokens" => 10,
      "output_tokens" => 2,
      "private" => "synthetic-usage-secret"
    })

    send(worker, :finish)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2_000
    accounting = Ipse.Session.info(pid).accounting

    assert [
             %{
               "reported_model" => "actual-model",
               "usage" => %{"counts" => %{"total_tokens" => 14}}
             }
           ] = accounting["requests"]

    refute Jason.encode!(accounting) =~ "synthetic-"
    {:ok, events} = Ipse.Journal.load(ctx.dir, info.id)
    assert Enum.count(events, &(&1["type"] == "request_usage_observed")) == 1

    assert Enum.find(
             events,
             &(&1["type"] == "message" and get_in(&1, ["message", "role"]) == "assistant")
           )["message"]["provider_data"]["private"] == "synthetic-native-secret"

    :ok = Ipse.Session.close(pid)
    bytes = File.read!(Path.join(ctx.dir, info.id <> ".jsonl"))
    resumed = start(ctx, info.id)
    assert Ipse.Session.info(resumed).accounting == accounting
    assert File.read!(Path.join(ctx.dir, info.id <> ".jsonl")) == bytes
    refute_receive {:usage_worker, _}, 30
    refute_receive {:ipse, _, {:provider_usage, _}}, 0
  end

  test "cancel and failure retain partial observed counters without treating them as final",
       ctx do
    for action <- [:cancel, :fail] do
      pid = start(ctx)
      :ok = Ipse.Session.prompt(pid, "metered fixture")
      assert_receive {:usage_worker, worker}, 2_000
      observe(worker, %{"input_tokens" => 10})
      # A call to this worker is ordered after both progress messages.
      if action == :cancel, do: Ipse.Session.cancel(pid), else: send(worker, :fail)
      assert_receive {:ipse, ^pid, {:done, _}}, 2_000

      assert [
               %{
                 "finality" => "partial",
                 "usage" => %{"counts" => %{"input_tokens" => 10, "output_tokens" => nil}}
               }
             ] = Ipse.Session.info(pid).accounting["requests"]

      :ok = Ipse.Session.close(pid)
    end
  end

  test "owner crash leaves unknown outcome and corrupt accounting is refused before tail repair",
       ctx do
    pid = start(ctx)
    :ok = Ipse.Session.prompt(pid, "metered fixture")
    assert_receive {:usage_worker, worker}, 2_000
    observe(worker, %{"input_tokens" => 10})
    info = Ipse.Session.info(pid)
    # Synchronize durable progress before killing the owner.
    assert Ipse.Session.info(pid).accounting["request_count"] == 1
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 2_000
    resumed = start(ctx, info.id)
    assert [%{"outcome" => "unknown"}] = Ipse.Session.info(resumed).accounting["requests"]
    :ok = Ipse.Session.close(resumed)
    path = Path.join(ctx.dir, info.id <> ".jsonl")
    {:ok, events} = Ipse.Journal.load(ctx.dir, info.id)

    broken =
      Enum.map(events, fn
        %{"type" => "request_admitted"} = event -> Map.put(event, "billing_mode", "subscription")
        event -> event
      end)

    bytes = Enum.map_join(broken, "\n", &Jason.encode!/1) <> "\n{partial"
    File.write!(path, bytes)

    assert {:error, :invalid_usage_journal} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session,
                config: ctx.config,
                cwd: ctx.root,
                state_dir: ctx.dir,
                id: info.id,
                subscriber: self()}
             )

    assert File.read!(path) == bytes
  end
end
