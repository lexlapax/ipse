defmodule Ipse.Test.ManagedSupersessionUnknown do
  import ExUnit.Assertions

  def run(session, opts, root, cwd, dir, id, ordinary, collection, pin, before, mode) do
    assert mode in [:input, :after_effect]
    parent = self()
    observer = spawn(fn -> observe(parent, session, %{ready: 0, prompts: 0}) end)
    :erlang.trace_pattern({Ipse.Session.Input, :start, 5}, true, [:local])
    :erlang.trace_pattern({Ipse.Session, :notify, 2}, true, [:local])
    :erlang.trace(session, true, [:call, {:tracer, observer}])

    {:ok, watcher} =
      Task.start(fn ->
        Process.register(self(), :ipse_supersession_effect_control)
        send(parent, {:loss_watcher_ready, self()})

        publisher =
          if mode == :input do
            wait_file(
              Path.join(root, "supersession-unknown-input-ready"),
              System.monotonic_time(:millisecond) + 20_000
            )

            nil
          else
            assert_receive {:supersession_effect_published, publisher}, 20_000
            assert Process.alive?(publisher)

            pointer =
              File.read!(Path.join([collection, pin["namespace"], "root.json"]))
              |> Jason.decode!()

            assert pointer["generation"] == before["generation"] + 1
            publisher
          end

        state = :sys.get_state(session)
        barrier = state.share_barrier

        port =
          if mode == :input do
            assert barrier.owner_protocol == :managed_relation_review and
                     barrier.phase == :review_input

            assert barrier.notice_received and barrier.manifest_issued
            barrier.issued_terminal.port
          else
            assert barrier.owner_protocol == :legacy and barrier.relation_publisher
            assert barrier.writer_control == :transferred
            barrier.owner_port
          end

        assert {:os_pid, native} = Port.info(port, :os_pid)

        assert {_, 0} =
                 System.cmd("/bin/kill", ["-KILL", Integer.to_string(native)],
                   stderr_to_stdout: true
                 )

        if publisher, do: send(publisher, :release_effect_control)

        File.write!(Path.join(root, "supersession-unknown-native-killed"), "killed")
      end)

    assert_receive {:loss_watcher_ready, ^watcher}, 1000

    try do
      File.write!(
        Path.join(root, "supersession-terminal-command"),
        "/correct " <> ordinary["key"] <> " My corrected ordinary value"
      )

      IO.puts("IPSE_SUPERSESSION_TERMINAL_READY")
      assert Ipse.CLI.Terminal.interact(session, Process.monitor(session), true, nil, cwd) == 1
      refute Process.alive?(session)

      wait_file(
        Path.join(root, "supersession-unknown-native-killed"),
        System.monotonic_time(:millisecond) + 1000
      )

      monitor = Process.monitor(watcher)
      assert_receive {:DOWN, ^monitor, :process, ^watcher, reason}, 1000
      assert reason in [:normal, :noproc]
      send(observer, :report)
      assert_receive {:unknown_review_report, %{ready: 0, prompts: 1}}, 5000
    after
      for {module, name, arity} <- [{Ipse.Session.Input, :start, 5}, {Ipse.Session, :notify, 2}],
          do: :erlang.trace_pattern({module, name, arity}, false, [:local])

      send(observer, :stop)
    end

    assert {:ok, events} = Ipse.Journal.load(dir, id)
    assert Enum.any?(events, &(&1["type"] == "managed_supersession_intent"))

    refute Enum.any?(events, &(&1["type"] == "managed_supersession_delivered"))

    assert Enum.count(events, &(&1["type"] == "managed_supersession_review")) ==
             if(mode == :input, do: 0, else: 1)

    assert {:ok, actual} =
             Ipse.Extension.Collection.execute(
               collection,
               pin["namespace"],
               %{"op" => "snapshot"},
               Ipse.Usage.id()
             )

    if mode == :input,
      do: assert(actual == before),
      else: assert(actual["generation"] == before["generation"] + 1)

    assert {:ok, _} = Ipse.Session.Saved.restore(events, id)

    intent = Enum.find(events, &(&1["type"] == "managed_supersession_intent"))

    altered =
      Enum.map(events, fn event ->
        if event === intent,
          do: Map.put(event, "candidate_operation_id", Ipse.Usage.id()),
          else: event
      end)

    assert {:error, :invalid_extension_action} = Ipse.Session.Saved.restore(altered, id)

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session, Keyword.put(opts, :id, id)}
             )

    assert Ipse.Session.info(resumed).phase == :idle
    assert :ok = Ipse.Session.close_confirmed(resumed)
    assert {:ok, after_resume} = Ipse.Journal.load(dir, id)
    assert Enum.take(after_resume, length(events)) === events

    refute Enum.any?(
             Enum.drop(after_resume, length(events)),
             &(&1["type"] in ~w(extension_invocation_intent extension_action_intent request_admitted))
           )

    assert {:ok, ^actual} =
             Ipse.Extension.Collection.execute(
               collection,
               pin["namespace"],
               %{"op" => "snapshot"},
               Ipse.Usage.id()
             )

    assert {:ok, _} = Ipse.Session.Saved.restore(after_resume, id)
    refute File.exists?(Path.join(root, "unexpected-model"))
  end

  def interpose_after_effect(root) do
    source = File.read!("lib/ipse/runner/session_source.ex")
    anchor = "            case settle(cap, context, binding, transport, controls) do"
    assert String.contains?(source, anchor)

    pause = """
                send(Process.whereis(:ipse_supersession_effect_control), {:supersession_effect_published, self()})
                receive do
                  :release_effect_control -> :ok
                after
                  5_000 -> throw(:effect_control_not_released)
                end
    """

    instrumented = String.replace(source, anchor, pause <> anchor, global: false)
    IO.puts("AFTER_EFFECT_CONTROL_SOURCE_SHA256=" <> Ipse.JSON.sha256(instrumented))
    [{module, beam}] = Code.compile_string(instrumented, "session-source-after-effect-control.ex")
    path = Path.join(root, "Elixir.Ipse.Runner.SessionSource.beam")
    File.write!(path, beam)
    assert {:module, ^module} = :code.load_binary(module, String.to_charlist(path), beam)
  end

  defp observe(parent, session, counts) do
    receive do
      {:trace, ^session, :call, {Ipse.Session.Input, :start, [binding | _]}} ->
        observe(
          parent,
          session,
          if(binding[:purpose] == "prompt",
            do: %{counts | prompts: counts.prompts + 1},
            else: counts
          )
        )

      {:trace, ^session, :call, {Ipse.Session, :notify, [_, :native_relation_ready]}} ->
        observe(parent, session, %{counts | ready: counts.ready + 1})

      :report ->
        send(parent, {:unknown_review_report, counts})
        observe(parent, session, counts)

      :stop ->
        :ok

      _ ->
        observe(parent, session, counts)
    end
  end

  defp wait_file(path, deadline) do
    unless File.exists?(path) do
      assert System.monotonic_time(:millisecond) < deadline
      Process.sleep(5)
      wait_file(path, deadline)
    end
  end
end
