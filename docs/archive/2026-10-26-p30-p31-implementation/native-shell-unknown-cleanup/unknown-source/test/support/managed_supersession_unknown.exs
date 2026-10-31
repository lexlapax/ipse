defmodule Ipse.Test.ManagedSupersessionUnknown do
  import ExUnit.Assertions

  def run(session, opts, root, cwd, dir, id, ordinary, collection, pin, before) do
    parent = self()

    observer =
      spawn(fn ->
        observe(%{
          parent: parent,
          session: session,
          review: nil,
          controller: nil,
          native: nil,
          ready: 0,
          prompts: 0,
          stopped: false
        })
      end)

    :erlang.trace_pattern({Ipse.Runner.Operator, :run_guarded, 4}, true, [:local])
    :erlang.trace_pattern({Ipse.Session.Input, :start, 5}, true, [:local])
    :erlang.trace_pattern({Ipse.Session, :notify, 2}, true, [:local])
    :erlang.trace(:all, true, [:call, :procs, :set_on_spawn, {:tracer, observer}])

    try do
      File.write!(
        Path.join(root, "supersession-terminal-command"),
        "/correct " <> ordinary["key"] <> " My corrected ordinary value"
      )

      IO.puts("IPSE_SUPERSESSION_TERMINAL_READY")
      assert Ipse.CLI.Terminal.interact(session, Process.monitor(session), true, nil, cwd) == 1
      refute Process.alive?(session)
      Process.sleep(50)
      send(observer, :report)

      receive do
        {:unknown_review_report, report} ->
          assert report.stopped
          assert report.ready == 0
          assert report.prompts == 1
      after
        8000 -> flunk("actual guarded native cleanup interruption was not reported")
      end
    after
      :erlang.trace(:all, false, [:call, :procs, :set_on_spawn])

      for {module, name, arity} <- [
            {Ipse.Runner.Operator, :run_guarded, 4},
            {Ipse.Session.Input, :start, 5},
            {Ipse.Session, :notify, 2}
          ] do
        :erlang.trace_pattern({module, name, arity}, false, [:local])
      end

      send(observer, :restore)
    end

    assert {:ok, events} = Ipse.Journal.load(dir, id)
    assert Enum.any?(events, &(&1["type"] == "managed_supersession_intent"))
    refute Enum.any?(events, &(&1["type"] == "managed_supersession_delivered"))

    assert {:ok, after_snapshot} =
             Ipse.Extension.Collection.execute(
               collection,
               pin["namespace"],
               %{"op" => "snapshot"},
               Ipse.Usage.id()
             )

    assert before == after_snapshot
    assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
    lifecycle = Enum.find(events, &(&1["type"] == "managed_supersession_intent"))

    candidate_result =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and
            &1["operation_id"] == lifecycle["candidate_operation_id"])
      )

    assert candidate_result["outcome"] == %{
             "status" => "failed",
             "value" => %{"code" => "collection_policy_refused"}
           }

    changed =
      Enum.map(events, fn event ->
        if event === candidate_result,
          do: Map.put(event, "request_sha256", Ipse.JSON.sha256("unrelated candidate prefix")),
          else: event
      end)

    assert {:error, :invalid_extension_action} = Ipse.Session.Saved.restore(changed, id)

    changed =
      Enum.map(events, fn event ->
        if event === lifecycle,
          do: Map.put(event, "candidate_operation_id", Ipse.Usage.id()),
          else: event
      end)

    assert {:error, :invalid_extension_action} = Ipse.Session.Saved.restore(changed, id)

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session, Keyword.put(opts, :id, id)}
             )

    assert Ipse.Session.info(resumed).phase == :idle
    assert :ok = Ipse.Session.close_confirmed(resumed)
    assert {:ok, ^events} = Ipse.Journal.load(dir, id)
    refute File.exists?(Path.join(root, "unexpected-model"))
  end

  defp observe(state) do
    receive do
      {:trace, owner, :call, {Ipse.Runner.Operator, :run_guarded, _}} ->
        observe(%{state | review: owner})

      {:trace, session, :call, {Ipse.Session.Input, :start, [binding | _]}}
      when session == state.session ->
        observe(
          if(binding[:purpose] == "prompt",
            do: %{state | prompts: state.prompts + 1},
            else: state
          )
        )

      {:trace, session, :call, {Ipse.Session, :notify, [_, :native_relation_ready]}}
      when session == state.session ->
        observe(%{state | ready: state.ready + 1})

      {:trace, owner, :spawn, controller, _}
      when owner == state.review and state.controller == nil ->
        send(self(), {:find_native, 1000})
        observe(%{state | controller: controller})

      {:find_native, remaining} ->
        case Enum.find(
               :erlang.ports(),
               &(Port.info(&1, :connected) == {:connected, state.controller})
             ) do
          nil when remaining > 0 ->
            Process.send_after(self(), {:find_native, remaining - 1}, 5)
            observe(state)

          nil ->
            send(state.parent, {:unknown_review_report, state})
            observe(state)

          port ->
            {:os_pid, native} = Port.info(port, :os_pid)
            {_, 0} = System.cmd("/bin/kill", ["-STOP", Integer.to_string(native)])
            monitor = Process.monitor(state.session)

            try do
              Process.exit(state.review, :kill)

              receive do
                {:DOWN, ^monitor, :process, _, _} -> :ok
              after
                12_000 -> :ok
              end
            after
              System.cmd("/bin/kill", ["-CONT", Integer.to_string(native)],
                stderr_to_stdout: true
              )

              Process.demonitor(monitor, [:flush])
            end

            observe(%{state | native: native, stopped: true})
        end

      :report ->
        send(
          state.parent,
          {:unknown_review_report, Map.take(state, [:ready, :prompts, :stopped])}
        )

        observe(state)

      :restore ->
        if state.native,
          do:
            System.cmd("/bin/kill", ["-CONT", Integer.to_string(state.native)],
              stderr_to_stdout: true
            )

        :ok

      _ ->
        observe(state)
    after
      40_000 ->
        if state.native,
          do:
            System.cmd("/bin/kill", ["-CONT", Integer.to_string(state.native)],
              stderr_to_stdout: true
            )
    end
  end
end
