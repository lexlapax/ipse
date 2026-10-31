defmodule Ipse.Session.QuestionEOFTest do
  use ExUnit.Case, async: false
  alias Ipse.Session

  defmodule Provider do
    def complete(_config, _messages, _tools, _emit) do
      arguments = %{
        "questions" => [%{"id" => "detail", "kind" => "text", "prompt" => "Synthetic detail?"}]
      }

      {:ok,
       %{
         "role" => "assistant",
         "content" => "",
         "tool_calls" => [
           %{
             "id" => Ipse.Usage.id(),
             "function" => %{"name" => "ask_operator", "arguments" => Jason.encode!(arguments)}
           }
         ]
       }, %{}}
    end
  end

  # Test-only proxy: the real writer still writes and syncs the checkpoint,
  # while the next append remains held so the actual Session can be killed.
  defmodule BoundaryWriter do
    use GenServer

    def start(writer, target, observer),
      do: GenServer.start(__MODULE__, {writer, target, observer})

    @impl true
    def init(state), do: {:ok, state}

    @impl true
    def handle_call(
          {:append, _, %{"type" => type}} = request,
          _from,
          {writer, {:after, type}, observer} = state
        ) do
      :ok = GenServer.call(writer, request, 5_000)
      send(observer, {:append_committed, self(), type})
      {:noreply, state}
    end

    def handle_call({:append, _, %{"type" => type}}, _from, {_, type, observer} = state) do
      send(observer, {:append_held, self(), type})
      {:noreply, state}
    end

    def handle_call(request, _from, {writer, _, _} = state),
      do: {:reply, GenServer.call(writer, request, 5_000), state}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-question-eof-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    config = %{
      provider: :demo,
      provider_module: Provider,
      model: "synthetic",
      home: Path.join(root, "home"),
      approval: :ask,
      operator_questions: true
    }

    {:ok, session} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: config, cwd: root, state_dir: Path.join(root, "state"), subscriber: self()}
      )

    reader = spawn(fn -> receive do: (:stop -> :ok) end)

    on_exit(fn ->
      if Process.alive?(session), do: Session.close(session)
      Process.exit(reader, :kill)
    end)

    {:ok, channel} = Session.open_input_channel(session, reader)
    %{session: session, reader: reader, channel: channel, root: root}
  end

  # This host-state fixture exercises ticket ownership, not terminal attestation.
  # Actual native observation and cleanup have separate serial PTY fixtures.
  defp observed(c, text) do
    state = :sys.get_state(c.session)
    witness = make_ref()

    binding = %{
      session_id: state.id,
      cwd: state.cwd,
      generation: state.operator_channel.generation,
      channel_id: c.channel,
      purpose: "prompt",
      render_id: nil
    }

    observation = %{
      "version" => 2,
      "event_id" => Ipse.Usage.id(),
      "text" => text,
      "text_sha256" => Ipse.JSON.sha256(text),
      "display_sha256" => Ipse.JSON.sha256("you> "),
      "input_limit" => 1_048_576,
      "display_limit" => 16_777_216
    }

    :sys.replace_state(Session.Input, fn s ->
      entry = %{
        target: c.session,
        kind: :observation,
        client: c.reader,
        target_monitor: Process.monitor(c.session),
        client_monitor: Process.monitor(c.reader),
        task: nil,
        from: nil,
        cancelled: false,
        binding: binding,
        display_sha256: observation["display_sha256"],
        observation: observation,
        expires: System.monotonic_time(:millisecond) + 300_000,
        timer: nil
      }

      put_in(s.entries[witness], entry)
    end)

    witness
  end

  defp staged(c, text) do
    witness = observed(c, text)
    assert {:ok, ticket} = Session.stage_input(c.session, c.channel, text, witness)
    ticket
  end

  defp await_question(session) do
    assert_receive {:ipse, ^session, {:question, _, _}}, 2_000
    assert :sys.get_state(session).phase == :question
  end

  test "replacing an operator channel fences old staged and unstaged inputs", c do
    staged_ticket = staged(c, "queued before channel replacement")
    unstaged_witness = observed(c, "observed before channel replacement")
    assert {:ok, new_channel} = Session.open_input_channel(c.session, c.reader)
    refute new_channel == c.channel

    assert {:error, :invalid_input_witness} =
             Session.prompt(c.session, "queued before channel replacement", staged_ticket)

    assert {:error, :invalid_input_witness} =
             Session.stage_input(
               c.session,
               c.channel,
               "observed before channel replacement",
               unstaged_witness
             )

    assert {:error, :invalid_input_witness} =
             Session.stage_input(
               c.session,
               new_channel,
               "observed before channel replacement",
               unstaged_witness
             )

    next = %{c | channel: new_channel}
    new_ticket = staged(next, "submitted after channel replacement")
    assert :ok = Session.prompt(c.session, "submitted after channel replacement", new_ticket)
    await_question(c.session)
    assert :ok = Session.question_eof(c.session, new_channel)
    assert_receive {:ipse, _, {:done, :cancelled}}, 2_000

    id = Session.info(c.session).id
    assert :ok = Session.close_confirmed(c.session)
    assert {:ok, events} = Ipse.Journal.load(Path.join(c.root, "state"), id)
    assert {:ok, _} = Session.Saved.restore(events, id)

    assert Enum.map(Enum.filter(events, &(&1["type"] == "input_received")), & &1["text"]) ==
             ["submitted after channel replacement"]
  end

  test "witnessed planning entry records its checkpoint and fences queued prompts", c do
    stale = staged(c, "queued before planning")
    ticket = staged(c, "/plan")
    assert :ok = Session.enter_planning_observed(c.session, c.channel, ticket)
    assert Session.info(c.session).execution_mode["ceiling"] == "planning"

    assert {:error, :invalid_input_witness} =
             Session.prompt(c.session, "queued before planning", stale)

    assert {:error, :planning_entry_unavailable} =
             Session.enter_planning_observed(c.session, c.channel, ticket)

    id = Session.info(c.session).id
    assert :ok = Session.close_confirmed(c.session)
    assert {:ok, events} = Ipse.Journal.load(Path.join(c.root, "state"), id)
    assert {:ok, mode} = Session.Saved.execution_mode(events, id)
    assert mode["ceiling"] == "planning"
    assert {:ok, _} = Session.Saved.restore(events, id)
    assert Enum.count(events, &(&1["type"] == "planning_entry_observed")) == 1

    forged =
      Enum.map(events, fn event ->
        if event["type"] == "planning_entry_observed",
          do: put_in(event, ["observation", "text_sha256"], Ipse.JSON.sha256("other")),
          else: event
      end)

    assert {:error, :invalid_planning_transition} = Session.Saved.restore(forged, id)

    config = %{
      provider: :demo,
      provider_module: Provider,
      model: "synthetic",
      home: Path.join(c.root, "home"),
      approval: :ask,
      operator_questions: true
    }

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                id: id,
                config: config,
                cwd: c.root,
                state_dir: Path.join(c.root, "state"),
                subscriber: self()}
             )

    assert Session.info(resumed).execution_mode["ceiling"] == "planning"
    assert :deny = Ipse.Extension.Mode.ordinary(Session.info(resumed).execution_mode, true)
    assert {:ok, resumed_channel} = Session.open_input_channel(resumed, c.reader)
    resumed_ctx = %{c | session: resumed, channel: resumed_channel}
    stale = staged(resumed_ctx, "queued before exit")

    assert :ok =
             Session.exit_planning_observed(
               resumed,
               resumed_channel,
               staged(resumed_ctx, "/plan exit")
             )

    assert Session.info(resumed).execution_mode["ceiling"] == "normal"
    assert {:error, :invalid_input_witness} = Session.prompt(resumed, "queued before exit", stale)
    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, after_exit} = Ipse.Journal.load(Path.join(c.root, "state"), id)
    assert {:ok, _} = Session.Saved.restore(after_exit, id)
    assert {:ok, exited_mode} = Session.Saved.execution_mode(after_exit, id)
    assert exited_mode["ceiling"] == "normal"
  end

  test "journal exhaustion after a planning checkpoint preserves the restriction without an entry",
       c do
    id = Session.info(c.session).id
    ticket = staged(c, "/plan")
    writer = :sys.get_state(c.session).journal_writer
    monitor = Process.monitor(c.session)

    # Leave space for exactly one normal event and the mandatory limit receipt.
    :sys.replace_state(writer, fn state ->
      put_in(state.limits["max_events"], state.count + 2)
    end)

    assert catch_exit(Session.enter_planning_observed(c.session, c.channel, ticket))
    assert_receive {:DOWN, ^monitor, :process, _, :journal_limit_reached}, 5_000
    assert {:ok, events} = Ipse.Journal.load(Path.join(c.root, "state"), id)
    assert Enum.count(events, &(&1["type"] == "execution_mode_resumed")) == 1
    refute Enum.any?(events, &(&1["type"] == "planning_entry_observed"))
    assert List.last(events)["type"] == "journal_limit_reached"
    assert {:ok, mode, nil} = Session.PlanningTransition.reconstruct(events, id)
    assert mode["ceiling"] == "planning"
    assert {:ok, _} = Session.Saved.restore(events, id)
    assert {:error, :journal_limit_reached} = Ipse.Journal.writable_events(events)
  end

  test "Session death after a durable planning checkpoint cannot create exit provenance", c do
    session = c.session
    id = Session.info(session).id
    stale = staged(c, "queued before interrupted planning")
    ticket = staged(c, "/plan")
    state = :sys.get_state(session)
    owner_monitor = Process.monitor(session)
    writer_monitor = Process.monitor(state.journal_writer)
    guard_monitor = Process.monitor(state.lock_guard)
    test_owner = self()

    killer =
      spawn(fn ->
        receive do
          {:append_held, proxy, "planning_entry_observed"} ->
            send(test_owner, {:boundary_reached, proxy})
            Process.exit(session, :kill)
        end
      end)

    {:ok, proxy} = BoundaryWriter.start(state.journal_writer, "planning_entry_observed", killer)

    on_exit(fn ->
      if Process.alive?(proxy), do: GenServer.stop(proxy)
      if Process.alive?(killer), do: Process.exit(killer, :kill)
    end)

    # The proxy is admitted as the test writer's caller, but the writer retains
    # its real Session monitor, file descriptor, lock guard and sync behavior.
    :sys.replace_state(state.journal_writer, &%{&1 | owner: proxy})
    :sys.replace_state(session, &%{&1 | journal_writer: proxy})

    assert catch_exit(Session.enter_planning_observed(session, c.channel, ticket))
    assert_receive {:boundary_reached, ^proxy}, 5_000
    assert_receive {:DOWN, ^owner_monitor, :process, ^session, :killed}, 5_000
    assert_receive {:DOWN, ^writer_monitor, :process, _, _}, 5_000
    assert_receive {:DOWN, ^guard_monitor, :process, _, _}, 5_000

    assert {:ok, events} = Ipse.Journal.load(Path.join(c.root, "state"), id)
    assert Enum.count(events, &(&1["type"] == "execution_mode_resumed")) == 1
    refute Enum.any?(events, &(&1["type"] == "planning_entry_observed"))
    assert {:ok, mode, nil} = Session.PlanningTransition.reconstruct(events, id)
    assert mode["ceiling"] == "planning"
    assert {:ok, _} = Session.Saved.restore(events, id)

    config = %{
      provider: :demo,
      provider_module: Provider,
      model: "synthetic",
      home: Path.join(c.root, "home"),
      approval: :ask,
      operator_questions: true
    }

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                id: id,
                config: config,
                cwd: c.root,
                state_dir: Path.join(c.root, "state"),
                subscriber: self()}
             )

    on_exit(fn -> if Process.alive?(resumed), do: Session.close_confirmed(resumed) end)
    assert Session.info(resumed).execution_mode["ceiling"] == "planning"

    assert {:error, :invalid_input_witness} =
             Session.prompt(resumed, "queued before interrupted planning", stale)

    assert {:ok, channel} = Session.open_input_channel(resumed, c.reader)
    next = %{c | session: resumed, channel: channel}

    assert {:error, :planning_exit_unavailable} =
             Session.exit_planning_observed(resumed, channel, staged(next, "/plan exit"))

    assert :deny = Ipse.Extension.Mode.ordinary(Session.info(resumed).execution_mode, true)
    assert :ok = Session.close_confirmed(resumed)
  end

  test "Session death after durable planning entry retains its witnessed exit provenance", c do
    session = c.session
    stale = staged(c, "queued before committed entry")
    ticket = staged(c, "/plan")
    id = Session.info(session).id
    state = :sys.get_state(session)
    owner_monitor = Process.monitor(session)
    writer_monitor = Process.monitor(state.journal_writer)
    guard_monitor = Process.monitor(state.lock_guard)
    observer = self()

    killer =
      spawn(fn ->
        receive do
          {:append_committed, proxy, "planning_entry_observed"} ->
            send(observer, {:entry_committed, proxy})
            Process.exit(session, :kill)
        end
      end)

    {:ok, proxy} =
      BoundaryWriter.start(state.journal_writer, {:after, "planning_entry_observed"}, killer)

    on_exit(fn ->
      if Process.alive?(proxy), do: GenServer.stop(proxy)
      if Process.alive?(killer), do: Process.exit(killer, :kill)
    end)

    :sys.replace_state(state.journal_writer, &%{&1 | owner: proxy})
    :sys.replace_state(session, &%{&1 | journal_writer: proxy})
    assert catch_exit(Session.enter_planning_observed(session, c.channel, ticket))
    assert_receive {:entry_committed, ^proxy}, 5_000
    assert_receive {:DOWN, ^owner_monitor, :process, ^session, :killed}, 5_000
    assert_receive {:DOWN, ^writer_monitor, :process, _, _}, 5_000
    assert_receive {:DOWN, ^guard_monitor, :process, _, _}, 5_000

    state_dir = Path.join(c.root, "state")
    assert {:ok, events} = Ipse.Journal.load(state_dir, id)
    assert Enum.count(events, &(&1["type"] == "planning_entry_observed")) == 1
    assert {:ok, mode, entry} = Session.PlanningTransition.reconstruct(events, id)
    assert mode["ceiling"] == "planning" and is_map(entry)
    assert {:ok, _} = Session.Saved.restore(events, id)

    config = %{
      provider: :demo,
      provider_module: Provider,
      model: "synthetic",
      home: Path.join(c.root, "home"),
      approval: :ask,
      operator_questions: true
    }

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                id: id, config: config, cwd: c.root, state_dir: state_dir, subscriber: self()}
             )

    on_exit(fn -> if Process.alive?(resumed), do: Session.close_confirmed(resumed) end)
    assert Session.info(resumed).execution_mode["ceiling"] == "planning"

    assert {:error, :invalid_input_witness} =
             Session.prompt(resumed, "queued before committed entry", stale)

    assert {:ok, channel} = Session.open_input_channel(resumed, c.reader)
    next = %{c | session: resumed, channel: channel}
    assert :ok = Session.exit_planning_observed(resumed, channel, staged(next, "/plan exit"))
    assert Session.info(resumed).execution_mode["ceiling"] == "normal"
    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, final_events} = Ipse.Journal.load(state_dir, id)
    assert Enum.count(final_events, &(&1["type"] == "planning_entry_observed")) == 1
    assert Enum.count(final_events, &(&1["type"] == "planning_exited")) == 1
    refute Enum.any?(final_events, &(&1["type"] in ~w(tool_started planning_mcp_read_intent)))
  end

  test "Session death after a durable exit before acknowledgement restores the exited mode", c do
    session = c.session
    assert :ok = Session.enter_planning_observed(session, c.channel, staged(c, "/plan"))
    stale = staged(c, "queued before interrupted exit")
    ticket = staged(c, "/plan exit")
    id = Session.info(session).id
    state = :sys.get_state(session)
    owner_monitor = Process.monitor(session)
    writer_monitor = Process.monitor(state.journal_writer)
    guard_monitor = Process.monitor(state.lock_guard)
    observer = self()

    killer =
      spawn(fn ->
        receive do
          {:append_committed, proxy, "planning_exited"} ->
            send(observer, {:exit_committed, proxy})
            Process.exit(session, :kill)
        end
      end)

    {:ok, proxy} = BoundaryWriter.start(state.journal_writer, {:after, "planning_exited"}, killer)

    on_exit(fn ->
      if Process.alive?(proxy), do: GenServer.stop(proxy)
      if Process.alive?(killer), do: Process.exit(killer, :kill)
    end)

    :sys.replace_state(state.journal_writer, &%{&1 | owner: proxy})
    :sys.replace_state(session, &%{&1 | journal_writer: proxy})
    assert catch_exit(Session.exit_planning_observed(session, c.channel, ticket))
    assert_receive {:exit_committed, ^proxy}, 5_000
    assert_receive {:DOWN, ^owner_monitor, :process, ^session, :killed}, 5_000
    assert_receive {:DOWN, ^writer_monitor, :process, _, _}, 5_000
    assert_receive {:DOWN, ^guard_monitor, :process, _, _}, 5_000

    state_dir = Path.join(c.root, "state")
    assert {:ok, events} = Ipse.Journal.load(state_dir, id)
    assert Enum.count(events, &(&1["type"] == "planning_exited")) == 1
    assert {:ok, mode, nil} = Session.PlanningTransition.reconstruct(events, id)
    assert mode["ceiling"] == "normal"
    assert {:ok, _} = Session.Saved.restore(events, id)

    config = %{
      provider: :demo,
      provider_module: Provider,
      model: "synthetic",
      home: Path.join(c.root, "home"),
      approval: :ask,
      operator_questions: true
    }

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                id: id, config: config, cwd: c.root, state_dir: state_dir, subscriber: self()}
             )

    on_exit(fn -> if Process.alive?(resumed), do: Session.close_confirmed(resumed) end)
    assert Session.info(resumed).execution_mode["ceiling"] == "normal"

    assert {:error, :invalid_input_witness} =
             Session.prompt(resumed, "queued before interrupted exit", stale)

    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, final_events} = Ipse.Journal.load(state_dir, id)
    assert Enum.count(final_events, &(&1["type"] == "planning_exited")) == 1
    refute Enum.any?(final_events, &(&1["type"] in ~w(tool_started planning_mcp_read_intent)))
  end

  test "Session death at declared-read epoch boundaries recovers without reusing an old epoch",
       c do
    reads = %{
      "mcp__notes__lookup" => %{
        "version" => 1,
        "server_id" => "notes",
        "tool" => "lookup",
        "endpoint_sha256" => Ipse.JSON.sha256("endpoint"),
        "descriptor_sha256" => Ipse.JSON.sha256("descriptor")
      }
    }

    config = %{
      provider: :demo,
      provider_module: Provider,
      model: "synthetic",
      home: Path.join(c.root, "home"),
      approval: :ask,
      operator_questions: true,
      planning_mcp_reads: reads,
      configuration: %{
        fingerprint: Ipse.JSON.digest([reads]),
        planning_mcp_reads: reads,
        sources: []
      }
    }

    for {transition, held} <- [
          {:entry, "planning_mcp_epoch"},
          {:entry, "planning_entry_observed"},
          {:entry, {:after, "planning_entry_observed"}},
          {:exit, "planning_exited"},
          {:exit, "planning_mcp_epoch"},
          {:exit, {:after, "planning_exited"}}
        ] do
      {:ok, session} =
        DynamicSupervisor.start_child(
          Ipse.Sessions,
          {Session,
           config: config, cwd: c.root, state_dir: Path.join(c.root, "state"), subscriber: self()}
        )

      on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)
      {:ok, channel} = Session.open_input_channel(session, c.reader)
      context = %{c | session: session, channel: channel}

      if transition == :exit,
        do:
          assert(
            :ok = Session.enter_planning_observed(session, channel, staged(context, "/plan"))
          )

      id = Session.info(session).id
      ticket = staged(context, if(transition == :entry, do: "/plan", else: "/plan exit"))
      state = :sys.get_state(session)
      owner_monitor = Process.monitor(session)
      writer_monitor = Process.monitor(state.journal_writer)
      guard_monitor = Process.monitor(state.lock_guard)
      test_owner = self()

      killer =
        spawn(fn ->
          receive do
            {:append_held, proxy, ^held} ->
              send(test_owner, {:boundary_reached, proxy, held})
              Process.exit(session, :kill)

            {:append_committed, proxy, type} when held == {:after, type} ->
              send(test_owner, {:boundary_reached, proxy, held})
              Process.exit(session, :kill)
          end
        end)

      {:ok, proxy} = BoundaryWriter.start(state.journal_writer, held, killer)

      on_exit(fn ->
        if Process.alive?(proxy), do: GenServer.stop(proxy)
        if Process.alive?(killer), do: Process.exit(killer, :kill)
      end)

      :sys.replace_state(state.journal_writer, &%{&1 | owner: proxy})
      :sys.replace_state(session, &%{&1 | journal_writer: proxy})

      if transition == :entry,
        do: assert(catch_exit(Session.enter_planning_observed(session, channel, ticket))),
        else: assert(catch_exit(Session.exit_planning_observed(session, channel, ticket)))

      assert_receive {:boundary_reached, ^proxy, ^held}, 5_000
      assert_receive {:DOWN, ^owner_monitor, :process, ^session, :killed}, 5_000
      assert_receive {:DOWN, ^writer_monitor, :process, _, _}, 5_000
      assert_receive {:DOWN, ^guard_monitor, :process, _, _}, 5_000
      assert {:ok, events} = Ipse.Journal.load(Path.join(c.root, "state"), id)
      assert {:ok, _} = Session.Saved.restore(events, id)
      assert :ok = Session.PlanningMCP.validate_events(events, id)
      assert {:ok, mode, entry} = Session.PlanningTransition.reconstruct(events, id)

      if held in [{:after, "planning_entry_observed"}, "planning_exited"],
        do: assert(is_map(entry)),
        else: assert(is_nil(entry))

      expected_ceiling =
        if transition == :entry or held == "planning_exited", do: "planning", else: "normal"

      assert mode["ceiling"] == expected_ceiling
      refute Enum.any?(events, &(&1["type"] in ~w(tool_started planning_mcp_read_intent)))

      assert {:ok, resumed} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Session,
                  id: id,
                  config: config,
                  cwd: c.root,
                  state_dir: Path.join(c.root, "state"),
                  subscriber: self()}
               )

      on_exit(fn -> if Process.alive?(resumed), do: Session.close_confirmed(resumed) end)
      assert Session.info(resumed).execution_mode["ceiling"] == mode["ceiling"]

      if transition == :entry and is_nil(entry) do
        {:ok, next_channel} = Session.open_input_channel(resumed, c.reader)
        next = %{c | session: resumed, channel: next_channel}

        assert {:error, :planning_exit_unavailable} =
                 Session.exit_planning_observed(resumed, next_channel, staged(next, "/plan exit"))
      end

      assert :ok = Session.close_confirmed(resumed)
      assert {:ok, recovered} = Ipse.Journal.load(Path.join(c.root, "state"), id)
      assert {:ok, _} = Session.Saved.restore(recovered, id)
      prior_epochs = Enum.filter(events, &(&1["type"] == "planning_mcp_epoch"))
      epochs = Enum.filter(recovered, &(&1["type"] == "planning_mcp_epoch"))
      assert length(epochs) == length(prior_epochs) + 1
      assert List.last(epochs)["previous_epoch_id"] == List.last(prior_epochs)["epoch_id"]
      refute List.last(epochs)["epoch_id"] == List.last(prior_epochs)["epoch_id"]
      assert List.last(epochs)["execution_mode"]["ceiling"] == mode["ceiling"]
      refute Enum.any?(recovered, &(&1["type"] in ~w(tool_started planning_mcp_read_intent)))

      assert {:ok, resumed_again} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Session,
                  id: id,
                  config: config,
                  cwd: c.root,
                  state_dir: Path.join(c.root, "state"),
                  subscriber: self()}
               )

      on_exit(fn ->
        if Process.alive?(resumed_again), do: Session.close_confirmed(resumed_again)
      end)

      assert Session.info(resumed_again).execution_mode["ceiling"] == mode["ceiling"]

      if is_map(entry) do
        {:ok, next_channel} = Session.open_input_channel(resumed_again, c.reader)
        next = %{c | session: resumed_again, channel: next_channel}

        assert :ok =
                 Session.exit_planning_observed(
                   resumed_again,
                   next_channel,
                   staged(next, "/plan exit")
                 )

        assert Session.info(resumed_again).execution_mode["ceiling"] == "normal"
      end

      assert :ok = Session.close_confirmed(resumed_again)
      assert {:ok, twice} = Ipse.Journal.load(Path.join(c.root, "state"), id)
      assert {:ok, _} = Session.Saved.restore(twice, id)
      epochs_again = Enum.filter(twice, &(&1["type"] == "planning_mcp_epoch"))
      assert length(epochs_again) == length(epochs) + if(is_map(entry), do: 2, else: 1)
      resumed_epoch = Enum.at(epochs_again, length(epochs))
      assert resumed_epoch["previous_epoch_id"] == List.last(epochs)["epoch_id"]

      if is_map(entry) do
        assert List.last(epochs_again)["previous_epoch_id"] == resumed_epoch["epoch_id"]
        assert List.last(epochs_again)["execution_mode"]["ceiling"] == "normal"
      end

      refute Enum.any?(twice, &(&1["type"] in ~w(tool_started planning_mcp_read_intent)))
    end
  end

  test "journal exhaustion between a planning transition and its declared-read epoch preserves a valid sealed prefix",
       c do
    reads = %{
      "mcp__notes__lookup" => %{
        "version" => 1,
        "server_id" => "notes",
        "tool" => "lookup",
        "endpoint_sha256" => Ipse.JSON.sha256("endpoint"),
        "descriptor_sha256" => Ipse.JSON.sha256("descriptor")
      }
    }

    config = %{
      provider: :demo,
      provider_module: Provider,
      model: "synthetic",
      home: Path.join(c.root, "home"),
      approval: :ask,
      operator_questions: true,
      planning_mcp_reads: reads,
      configuration: %{
        fingerprint: Ipse.JSON.digest([reads]),
        planning_mcp_reads: reads,
        sources: []
      }
    }

    for transition <- [:entry, :exit] do
      {:ok, session} =
        DynamicSupervisor.start_child(
          Ipse.Sessions,
          {Session,
           config: config, cwd: c.root, state_dir: Path.join(c.root, "state"), subscriber: self()}
        )

      on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)
      {:ok, channel} = Session.open_input_channel(session, c.reader)
      next = %{c | session: session, channel: channel}

      if transition == :exit,
        do: assert(:ok = Session.enter_planning_observed(session, channel, staged(next, "/plan")))

      id = Session.info(session).id
      ticket = staged(next, if(transition == :entry, do: "/plan", else: "/plan exit"))
      writer = :sys.get_state(session).journal_writer
      monitor = Process.monitor(session)

      :sys.replace_state(writer, fn state ->
        put_in(state.limits["max_events"], state.count + 2)
      end)

      if transition == :entry,
        do: assert(catch_exit(Session.enter_planning_observed(session, channel, ticket))),
        else: assert(catch_exit(Session.exit_planning_observed(session, channel, ticket)))

      assert_receive {:DOWN, ^monitor, :process, ^session, :journal_limit_reached}, 5_000
      assert {:ok, events} = Ipse.Journal.load(Path.join(c.root, "state"), id)
      assert List.last(events)["type"] == "journal_limit_reached"
      assert :ok = Session.PlanningMCP.validate_events(events, id)
      assert {:ok, _} = Session.Saved.restore(events, id)
      assert {:ok, mode, entry} = Session.PlanningTransition.reconstruct(events, id)
      assert mode["ceiling"] == if(transition == :entry, do: "planning", else: "normal")
      assert is_nil(entry)
      assert {:error, :journal_limit_reached} = Ipse.Journal.writable_events(events)

      assert {:error, :journal_limit_reached} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Session,
                  id: id,
                  config: config,
                  cwd: c.root,
                  state_dir: Path.join(c.root, "state"),
                  subscriber: self()}
               )

      assert {:error, :invalid_planning_mcp_history} =
               Session.PlanningMCP.validate_events(events ++ [%{"type" => "tool_started"}], id)

      invalid_count =
        List.update_at(events, -1, &Map.update!(&1, "event_count", fn n -> n - 1 end))

      invalid_reason = List.update_at(events, -1, &Map.put(&1, "reason", "synthetic"))

      for invalid <- [invalid_count, invalid_reason] do
        assert {:error, :invalid_planning_mcp_history} =
                 Session.PlanningMCP.validate_events(invalid, id)
      end
    end
  end

  test "planning entry during an active question refuses and invalidates its ticket", c do
    assert :ok = Session.prompt(c.session, "first synthetic question")
    await_question(c.session)
    ticket = staged(c, "/plan")

    assert {:error, :planning_entry_unavailable} =
             Session.enter_planning_observed(c.session, c.channel, ticket)

    assert :ok = Session.question_eof(c.session, c.channel)
    assert_receive {:ipse, _, {:done, :cancelled}}, 2_000

    assert {:error, :planning_entry_unavailable} =
             Session.enter_planning_observed(c.session, c.channel, ticket)

    assert Session.info(c.session).execution_mode["ceiling"] == "normal"
    assert :ok = Session.enter_planning_observed(c.session, c.channel, staged(c, "/plan"))
  end

  test "a cancelled draft does not prevent later witnessed planning transitions", c do
    assert :ok = Session.start_draft(c.session, "synthetic request to refine")
    await_question(c.session)
    assert :ok = Session.cancel_draft(c.session)
    assert_receive {:ipse, _, {:done, :cancelled}}, 2_000
    assert :ok = Session.enter_planning_observed(c.session, c.channel, staged(c, "/plan"))
    assert :ok = Session.exit_planning_observed(c.session, c.channel, staged(c, "/plan exit"))
    id = Session.info(c.session).id
    assert :ok = Session.close_confirmed(c.session)
    assert {:ok, events} = Ipse.Journal.load(Path.join(c.root, "state"), id)
    assert {:ok, _} = Session.Saved.restore(events, id)
  end

  test "planning entry rebinds a declared-read MCP epoch before its receipt", c do
    reads = %{
      "mcp__notes__lookup" => %{
        "version" => 1,
        "server_id" => "notes",
        "tool" => "lookup",
        "endpoint_sha256" => Ipse.JSON.sha256("endpoint"),
        "descriptor_sha256" => Ipse.JSON.sha256("descriptor")
      }
    }

    config = %{
      provider: :demo,
      provider_module: Provider,
      model: "synthetic",
      home: Path.join(c.root, "home"),
      approval: :ask,
      operator_questions: true,
      planning_mcp_reads: reads,
      configuration: %{
        fingerprint: Ipse.JSON.digest([reads]),
        planning_mcp_reads: reads,
        sources: []
      }
    }

    assert {:ok, session} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: config,
                cwd: c.root,
                state_dir: Path.join(c.root, "state"),
                subscriber: self()}
             )

    assert {:ok, channel} = Session.open_input_channel(session, c.reader)
    next = %{c | session: session, channel: channel}
    assert :ok = Session.enter_planning_observed(session, channel, staged(next, "/plan"))
    assert :ok = Session.exit_planning_observed(session, channel, staged(next, "/plan exit"))
    id = Session.info(session).id
    assert :ok = Session.close_confirmed(session)
    assert {:ok, events} = Ipse.Journal.load(Path.join(c.root, "state"), id)
    assert {:ok, _} = Session.Saved.restore(events, id)
    epochs = Enum.filter(events, &(&1["type"] == "planning_mcp_epoch"))
    assert [first, second, third] = epochs
    assert second["previous_epoch_id"] == first["epoch_id"]
    assert second["execution_mode"]["ceiling"] == "planning"
    assert third["previous_epoch_id"] == second["epoch_id"]
    assert third["execution_mode"]["ceiling"] == "normal"
    assert Enum.count(events, &(&1["type"] == "planning_entry_observed")) == 1

    exit_index = Enum.find_index(events, &(&1["type"] == "planning_exited"))
    prefix = Enum.take(events, exit_index + 1)
    assert :ok = Session.PlanningMCP.validate_events(prefix, id)

    assert {:error, :invalid_planning_mcp_history} =
             Session.PlanningMCP.validate_events(prefix ++ [%{"type" => "tool_started"}], id)

    journal = Path.join([c.root, "state", id <> ".jsonl"])
    lines = File.read!(journal) |> String.split("\n", trim: true)
    File.write!(journal, Enum.join(Enum.take(lines, exit_index + 1), "\n") <> "\n")

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                id: id,
                config: config,
                cwd: c.root,
                state_dir: Path.join(c.root, "state"),
                subscriber: self()}
             )

    assert Session.info(resumed).execution_mode["ceiling"] == "normal"
    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, recovered} = Ipse.Journal.load(Path.join(c.root, "state"), id)
    assert {:ok, _} = Session.Saved.restore(recovered, id)
    assert Enum.count(recovered, &(&1["type"] == "planning_exited")) == 1

    assert {:ok, selected} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                id: id,
                config: Map.merge(config, %{execution_mode: :planning, planning_cli_start: true}),
                cwd: c.root,
                state_dir: Path.join(c.root, "state"),
                subscriber: self()}
             )

    assert {:ok, selected_channel} = Session.open_input_channel(selected, c.reader)
    selected_ctx = %{c | session: selected, channel: selected_channel}

    assert :ok =
             Session.exit_planning_observed(
               selected,
               selected_channel,
               staged(selected_ctx, "/plan exit")
             )

    assert :ok = Session.close_confirmed(selected)
    assert {:ok, selected_events} = Ipse.Journal.load(Path.join(c.root, "state"), id)
    assert Enum.count(selected_events, &(&1["type"] == "planning_start_selected")) == 1
    assert {:ok, _} = Session.Saved.restore(selected_events, id)
  end

  test "planning started without witnessed local entry cannot be exited", c do
    config = %{
      provider: :demo,
      provider_module: Provider,
      model: "synthetic",
      home: Path.join(c.root, "home"),
      approval: :ask,
      execution_mode: :planning,
      operator_questions: true
    }

    assert {:ok, session} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: config,
                cwd: c.root,
                state_dir: Path.join(c.root, "state"),
                subscriber: self()}
             )

    assert {:ok, channel} = Session.open_input_channel(session, c.reader)
    next = %{c | session: session, channel: channel}

    assert {:error, :planning_exit_unavailable} =
             Session.exit_planning_observed(session, channel, staged(next, "/plan exit"))

    assert Session.info(session).execution_mode["ceiling"] == "planning"
    id = Session.info(session).id
    assert :ok = Session.close_confirmed(session)

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                id: id,
                config: Map.put(config, :planning_cli_start, true),
                cwd: c.root,
                state_dir: Path.join(c.root, "state"),
                subscriber: self()}
             )

    assert {:ok, resumed_channel} = Session.open_input_channel(resumed, c.reader)
    resumed_ctx = %{c | session: resumed, channel: resumed_channel}

    assert {:error, :planning_exit_unavailable} =
             Session.exit_planning_observed(
               resumed,
               resumed_channel,
               staged(resumed_ctx, "/plan exit")
             )

    assert :ok = Session.close_confirmed(resumed)
  end

  test "an explicit local CLI startup selection can be exited after fresh start or normal resume",
       c do
    base = %{
      provider: :demo,
      provider_module: Provider,
      model: "synthetic",
      home: Path.join(c.root, "home"),
      approval: :ask,
      operator_questions: true
    }

    original_id = Session.info(c.session).id
    assert :ok = Session.close_confirmed(c.session)

    for id <- [nil, original_id] do
      config = Map.merge(base, %{execution_mode: :planning, planning_cli_start: true})

      assert {:ok, session} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Session,
                  id: id,
                  config: config,
                  cwd: c.root,
                  state_dir: Path.join(c.root, "state"),
                  subscriber: self()}
               )

      actual_id = Session.info(session).id

      session =
        if id == nil do
          assert :ok = Session.close_confirmed(session)

          assert {:ok, resumed} =
                   DynamicSupervisor.start_child(
                     Ipse.Sessions,
                     {Session,
                      id: actual_id,
                      config: base,
                      cwd: c.root,
                      state_dir: Path.join(c.root, "state"),
                      subscriber: self()}
                   )

          resumed
        else
          session
        end

      assert {:ok, channel} = Session.open_input_channel(session, c.reader)
      next = %{c | session: session, channel: channel}
      assert :ok = Session.exit_planning_observed(session, channel, staged(next, "/plan exit"))
      assert Session.info(session).execution_mode["ceiling"] == "normal"
      assert :ok = Session.close_confirmed(session)
      assert {:ok, events} = Ipse.Journal.load(Path.join(c.root, "state"), actual_id)
      assert {:ok, _} = Session.Saved.restore(events, actual_id)

      if id == nil do
        assert hd(events)["metadata"]["planning_local_start"]["origin"] == "cli_flag"
      else
        assert Enum.any?(events, &(&1["type"] == "planning_start_selected"))
      end
    end
  end

  test "local exit after resume retains a newly inherited read-only ceiling", c do
    assert :ok = Session.enter_planning_observed(c.session, c.channel, staged(c, "/plan"))
    id = Session.info(c.session).id
    assert :ok = Session.close_confirmed(c.session)

    config = %{
      provider: :demo,
      provider_module: Provider,
      model: "synthetic",
      home: Path.join(c.root, "home"),
      approval: :ask,
      enclosing_mode: :read_only,
      operator_questions: true
    }

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                id: id,
                config: config,
                cwd: c.root,
                state_dir: Path.join(c.root, "state"),
                subscriber: self()}
             )

    assert {:ok, channel} = Session.open_input_channel(resumed, c.reader)
    next = %{c | session: resumed, channel: channel}
    assert :ok = Session.exit_planning_observed(resumed, channel, staged(next, "/plan exit"))
    mode = Session.info(resumed).execution_mode
    assert mode["ceiling"] == "normal" and mode["enclosing_ceiling"] == "read_only"
    assert :deny = Ipse.Extension.Mode.ordinary(mode, true)
    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, events} = Ipse.Journal.load(Path.join(c.root, "state"), id)
    assert {:ok, _} = Session.Saved.restore(events, id)
  end

  test "unwitnessed and wrong-client planning entry cannot alter the ceiling", c do
    ticket = staged(c, "/plan")

    assert {:error, :planning_entry_unavailable} =
             Task.async(fn -> Session.enter_planning_observed(c.session, c.channel, ticket) end)
             |> Task.await()

    assert {:error, :planning_entry_unavailable} =
             Session.enter_planning_observed(c.session, c.channel, make_ref())

    assert Session.info(c.session).execution_mode["ceiling"] == "normal"
    assert :ok = Session.enter_planning_observed(c.session, c.channel, ticket)
  end

  test "question EOF preserves only existing staged prompts for the current client", c do
    session = c.session
    assert :ok = Session.prompt(session, "first synthetic question")
    await_question(session)
    first = staged(c, "queued café one")
    second = staged(c, "queued 日本語 two")
    third = staged(c, "explicit cancel invalidates this")
    assert {:ok, render} = Session.render_question(session, c.channel, "detail")
    unstaged = observed(c, "not queued before EOF")

    assert {:error, :no_pending_question} = Session.question_eof(session, Ipse.Usage.id())

    assert {:error, :no_pending_question} =
             Task.async(fn -> Session.question_eof(session, c.channel) end) |> Task.await()

    assert :sys.get_state(session).operator_render == render
    assert :ok = Session.question_eof(session, c.channel)
    assert_receive {:ipse, ^session, {:done, :cancelled}}, 2_000
    state = :sys.get_state(session)
    assert state.phase == :idle
    assert state.question == nil
    assert state.operator_render == nil
    assert state.operator_answers == %{}
    assert state.operator_pieces == []

    assert {:error, :invalid_input_witness} =
             Session.stage_input(session, c.channel, "not queued before EOF", unstaged)

    assert :ok = Session.prompt(session, "queued café one", first)
    await_question(session)
    assert :ok = Session.question_eof(session, c.channel)
    assert_receive {:ipse, ^session, {:done, :cancelled}}, 2_000
    assert :ok = Session.prompt(session, "queued 日本語 two", second)
    await_question(session)
    assert :ok = Session.cancel(session)
    assert_receive {:ipse, ^session, {:done, :cancelled}}, 2_000

    assert {:error, :invalid_input_witness} =
             Session.prompt(session, "explicit cancel invalidates this", third)

    assert {:error, :no_pending_question} = Session.question_eof(session, c.channel)
    id = Session.info(session).id
    assert :ok = Session.close_confirmed(session)
    assert {:ok, events} = Ipse.Journal.load(Path.join(c.root, "state"), id)
    assert :ok = Session.Input.validate_events(events, id)
    assert {:ok, _} = Session.Saved.restore(events, id)
    refute Enum.any?(events, &(&1["type"] == "operator_answer"))

    assert Enum.map(Enum.filter(events, &(&1["type"] == "input_received")), & &1["text"]) ==
             ["first synthetic question", "queued café one", "queued 日本語 two"]
  end
end
