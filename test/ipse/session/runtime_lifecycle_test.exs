defmodule Ipse.LifecycleRuntimeTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.RuntimeLifecycle
  alias Ipse.Journal
  alias Ipse.Session.Lifecycle
  alias Ipse.Session

  defmodule Model do
    def complete(config, messages, _tools, _emit) do
      send(config.test_pid, :runtime_model)

      if config[:scenario] == :blocked_model, do: Process.sleep(:infinity)

      if List.last(messages)["role"] == "tool" do
        {:ok, %{"role" => "assistant", "content" => "done"}, %{}}
      else
        {name, arguments} =
          case config[:scenario] do
            :question ->
              {"ask_operator",
               %{
                 "questions" => [
                   %{"id" => "choice", "kind" => "text", "prompt" => "Synthetic private question"}
                 ]
               }}

            :shell ->
              {"shell", %{"command" => "printf started > started; sleep 30"}}

            _ ->
              {"write", %{"path" => "effect.txt", "content" => "Synthetic private arguments"}}
          end

        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "private-provider-call",
               "function" => %{"name" => name, "arguments" => Jason.encode!(arguments)}
             }
           ]
         }, %{}}
      end
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-runtime-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, dir: Path.join(root, "sessions")}
  end

  defp policy, do: %{"mode" => "local"}

  defp open(events \\ [], session \\ Ipse.Usage.id(), resumed \\ false),
    do: RuntimeLifecycle.open(%{}, policy(), events, session, resumed)

  defp links, do: %{"turn_id" => Ipse.Usage.id(), "request_id" => Ipse.Usage.id()}
  defp load(c, id), do: elem(Journal.load(c.dir, id), 1)
  defp facts(events), do: Enum.filter(events, &(&1["type"] in RuntimeLifecycle.types()))

  defp start(c, options \\ [], id \\ nil) do
    config = %{
      provider: :demo,
      model: "fixture",
      provider_module: Model,
      test_pid: self(),
      home: Path.join(c.root, "home"),
      approval: :ask,
      scenario: options[:scenario],
      observability: Map.put(Ipse.Observability.defaults(), "mode", options[:mode] || "local")
    }

    result =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: config,
         cwd: c.root,
         state_dir: c.dir,
         subscriber: self(),
         owner: options[:owner],
         id: id}
      )

    case result do
      {:ok, pid} -> on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
      _ -> :ok
    end

    result
  end

  defp kill(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 2_000
  end

  defp resume(c, opts, id, n \\ 100) do
    case start(c, opts, id) do
      {:error, :session_locked} when n > 0 ->
        Process.sleep(10)
        resume(c, opts, id, n - 1)

      other ->
        other
    end
  end

  test "epochs preserve incomplete prior waits without manufacturing a resolution" do
    {ctx, [started]} = open()
    {ctx, [wait]} = RuntimeLifecycle.begin_wait(ctx, "tool", links())
    {resumed, [restart]} = open([started, wait], ctx.session, true)
    assert restart["previous_state"] == "unclosed"
    assert restart["previous_epoch_id"] == started["epoch_id"]
    refute restart["epoch_id"] == started["epoch_id"]
    {_, [closed]} = RuntimeLifecycle.close(resumed, "close", true)
    assert {:ok, saved} = RuntimeLifecycle.restore([started, wait, restart, closed])
    assert saved.closed and saved.wait == nil

    assert {:error, _} =
             RuntimeLifecycle.restore([
               started,
               wait,
               Map.put(restart, "previous_state", "closed")
             ])

    assert {:error, _} = RuntimeLifecycle.restore([started, started])
    assert {:error, _} = RuntimeLifecycle.restore([closed])
  end

  test "wait outcomes and content-free metadata bind exact starts and source identity" do
    {ctx, [started]} = open()
    {ctx, [wait]} = RuntimeLifecycle.begin_wait(ctx, "tool", links())
    {ctx, [done]} = RuntimeLifecycle.finish_wait(ctx, "denied")
    {_, [closed]} = RuntimeLifecycle.close(ctx, "close", true)
    assert {:ok, _} = RuntimeLifecycle.restore([started, wait, done, closed])
    assert done["duration_ms"] >= 0

    for record <- [started, wait, done, closed] do
      {:ok, source} = Journal.source(ctx.session, 0, record)
      assert {:ok, projected} = Lifecycle.project(source, record, "metadata")
      assert Lifecycle.valid_metadata?(projected)
      assert projected["event_id"] == source["event_id"]
      refute Jason.encode!(projected) =~ "record_sha256"
      assert {:ok, diagnostic} = Ipse.Observability.build_event(source, record, 1, 0)
      assert diagnostic["group"] == "session"
      assert Ipse.Observability.valid_event?(diagnostic)
    end

    for corrupt <- [
          Map.put(done, "wait_id", Ipse.Usage.id()),
          Map.put(done, "duration_ms", -1),
          Map.put(done, "outcome", "answered"),
          Map.put(done, "private", "secret")
        ] do
      assert {:error, _} = RuntimeLifecycle.restore([started, wait, corrupt, closed])
    end

    assert {:error, _} = RuntimeLifecycle.restore([started, wait, closed])
    assert {:error, _} = RuntimeLifecycle.restore([started, wait, done, done])
    {ctx, [legacy]} = RuntimeLifecycle.begin_wait(ctx, "native_question", %{})
    {:ok, source} = Journal.source(ctx.session, 0, legacy)
    assert {:ok, projected} = Lifecycle.project(source, legacy, "metadata")
    refute Map.has_key?(projected["correlations"], "turn_id")
    refute Map.has_key?(projected["correlations"], "request_id")
  end

  test "recording bounds reserve closure and leave a durable stop rather than silently dropping" do
    session = Ipse.Usage.id()
    {_, [template]} = open([], session)

    events =
      Enum.flat_map(1..div(RuntimeLifecycle.limit(), 2), fn i ->
        epoch = String.pad_leading(Integer.to_string(i, 16), 32, "0") |> String.downcase()

        previous =
          if i == 1,
            do: nil,
            else: String.pad_leading(Integer.to_string(i - 1, 16), 32, "0") |> String.downcase()

        [
          %{
            template
            | "epoch_id" => epoch,
              "previous_epoch_id" => previous,
              "mode" => if(i == 1, do: "fresh", else: "resume"),
              "previous_state" => if(i == 1, do: "none", else: "closed")
          },
          %{
            "type" => "lifecycle_epoch_closed",
            "version" => 1,
            "session_id" => session,
            "epoch_id" => epoch,
            "closure" => "close",
            "cleanup_confirmed" => true
          }
        ]
      end)

    assert {:ok, saved} = RuntimeLifecycle.restore(events)
    assert saved.count == RuntimeLifecycle.limit()
    {ctx, [stop]} = open(events, session, true)
    assert stop["type"] == "lifecycle_recording_stopped"
    assert {:ok, %{stopped: true}} = RuntimeLifecycle.restore(events ++ [stop])
    assert {nil, []} = open(events ++ [stop], session, true)
    assert {^ctx, []} = RuntimeLifecycle.begin_wait(ctx, "tool", links())
    assert {:error, _} = RuntimeLifecycle.restore(events ++ [List.last(events)])
    nearly_full = Enum.drop(events, -1)
    assert {_, [stop]} = open(nearly_full, session, true)
    assert stop["type"] == "lifecycle_recording_stopped"
    assert {:ok, _} = RuntimeLifecycle.restore(nearly_full ++ [stop])
  end

  test "native approval is recorded before publication and only accepted decisions close its wait",
       c do
    {:ok, pid} = start(c)
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "Synthetic private prompt")
    assert_receive :runtime_model, 2_000
    assert_receive {:ipse, ^pid, {:approval, ref, "write", _}}, 2_000
    [started, wait] = facts(load(c, id))
    assert wait["domain"] == "tool" and wait["epoch_id"] == started["epoch_id"]
    assert {:error, :no_pending_approval} = Session.approve(pid, make_ref(), true)
    assert length(facts(load(c, id))) == 2
    :ok = Session.approve(pid, ref, false)
    assert_receive :runtime_model, 2_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2_000
    :ok = Session.close(pid)
    records = facts(load(c, id))
    assert [_, ^wait, %{"outcome" => "denied"}, %{"cleanup_confirmed" => true}] = records
    assert {:ok, _} = RuntimeLifecycle.restore(records, id)
    refute File.exists?(Path.join(c.root, "effect.txt"))
    refute Jason.encode!(records) =~ "private"
    {:ok, resumed} = resume(c, [], id)
    assert List.last(facts(load(c, id)))["previous_state"] == "closed"
    refute_receive :runtime_model, 50
    :ok = Session.close(resumed)
  end

  test "question recovery uses a fresh wait and actual saved source without rerunning inference",
       c do
    {:ok, pid} = start(c, scenario: :question)
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "Ask")
    assert_receive :runtime_model, 2_000
    assert_receive {:ipse, ^pid, {:question, question, _}}, 2_000
    [_, wait] = facts(load(c, id))
    source = wait["subject_source"]
    assert Journal.valid_source?(source)
    assert :ok = RuntimeLifecycle.validate_sources(c.dir, id, load(c, id))
    kill(pid)
    {:ok, resumed} = resume(c, [scenario: :question], id)
    assert_receive {:ipse, ^resumed, {:question, ^question, _}}, 2_000
    [_, ^wait, restart, next_wait] = facts(load(c, id))
    assert restart["previous_state"] == "unclosed"
    assert next_wait["subject_source"] == source
    refute next_wait["wait_id"] == wait["wait_id"]
    refute next_wait["epoch_id"] == wait["epoch_id"]
    refute_receive :runtime_model, 50
    assert {:error, :invalid_answer} = Session.answer(resumed, question, %{})
    assert length(facts(load(c, id))) == 4
    :ok = Session.answer(resumed, question, %{"choice" => "Explicit synthetic answer"})
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 2_000
    :ok = Session.close(resumed)
    records = facts(load(c, id))
    assert Enum.count(records, &(&1["type"] == "lifecycle_wait_finished")) == 1
    assert Enum.at(records, -2)["wait_id"] == next_wait["wait_id"]
    assert Enum.at(records, -2)["outcome"] == "answered"
    assert :ok = RuntimeLifecycle.validate_sources(c.dir, id, load(c, id))
  end

  test "cancel closes a wait but retains its epoch; owner death interrupts without claiming cleanup",
       c do
    {:ok, pid} = start(c)
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "write")
    assert_receive {:ipse, ^pid, {:approval, _, "write", _}}, 2_000
    :ok = Session.cancel(pid)
    assert List.last(facts(load(c, id)))["outcome"] == "cancelled"
    assert Session.info(pid).phase == :idle
    :ok = Session.close(pid)

    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, other} = start(c, owner: owner, scenario: :question)
    other_id = Session.info(other).id
    :ok = Session.prompt(other, "ask")
    assert_receive {:ipse, ^other, {:question, question, _}}, 2_000
    ref = Process.monitor(other)
    send(owner, :stop)
    assert_receive {:DOWN, ^ref, :process, ^other, :normal}, 2_000

    assert [
             _,
             _,
             %{"outcome" => "interrupted"},
             %{"closure" => "owner_down", "cleanup_confirmed" => false}
           ] = facts(load(c, other_id))

    {:ok, resumed} = resume(c, [scenario: :question], other_id)
    assert_receive {:ipse, ^resumed, {:question, ^question, _}}, 2_000
    :ok = Session.close(resumed)
    assert :ok = RuntimeLifecycle.validate_sources(c.dir, other_id, load(c, other_id))
  end

  test "recording off preserves an idle resume and starts no lifecycle facts", c do
    {:ok, pid} = start(c, mode: "off")
    id = Session.info(pid).id
    :ok = Session.close(pid)
    bytes = File.read!(Path.join(c.dir, id <> ".jsonl"))
    {:ok, resumed} = resume(c, [mode: "off"], id)
    :ok = Session.close(resumed)
    assert File.read!(Path.join(c.dir, id <> ".jsonl")) == bytes
    assert facts(load(c, id)) == []
  end

  for phase <- [:model, :tool] do
    test "unexpected #{phase} task death closes a recorded epoch conservatively", c do
      check_interrupted_task(c, unquote(phase))
    end
  end

  defp check_interrupted_task(c, phase) do
    scenario = if phase == :model, do: :blocked_model, else: :shell
    {:ok, pid} = start(c, scenario: scenario)
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "Synthetic interrupted work")
    assert_receive :runtime_model, 2000

    if phase == :tool do
      assert_receive {:ipse, ^pid, {:approval, approval, "shell", _}}, 2000
      :ok = Session.approve(pid, approval, true)
      assert :tool == Session.info(pid).phase
    end

    task = :sys.get_state(pid).task.pid
    monitor = Process.monitor(pid)
    Process.exit(task, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 5000
    events = load(c, id)

    assert %{"closure" => "cleanup_failure", "cleanup_confirmed" => false} =
             List.last(facts(events))

    assert {:ok, _} = Session.restore_context(events)
    {:ok, resumed} = resume(c, [scenario: scenario], id)
    assert List.last(facts(load(c, id)))["previous_state"] == "closed"
    refute_receive :runtime_model, 50
    :ok = Session.close(resumed)
  end

  test "question source positions are resolved before tail repair or resumed publication", c do
    {:ok, pid} = start(c, scenario: :question)
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "ask")
    assert_receive {:ipse, ^pid, {:question, _, _}}, 2_000
    events = load(c, id)
    question = Enum.find(events, &(&1["type"] == "operator_question"))
    {:ok, false_source} = Journal.source(id, 0, question)

    forged =
      Enum.map(events, fn
        %{"type" => "lifecycle_wait_started"} = wait ->
          Map.put(wait, "subject_source", false_source)

        event ->
          event
      end)

    assert {:ok, _} = RuntimeLifecycle.restore(forged, id)

    assert {:error, :invalid_runtime_lifecycle_source} =
             RuntimeLifecycle.validate_sources(c.dir, id, forged)

    kill(pid)
    path = Path.join(c.dir, id <> ".jsonl")
    contents = Enum.map_join(forged, "\n", &Jason.encode!/1) <> "\n{"
    File.write!(path, contents)
    assert {:error, :invalid_runtime_lifecycle_source} = resume(c, [scenario: :question], id)
    assert File.read!(path) == contents
    refute_receive {:ipse, _, {:question, _, _}}, 50
  end
end
