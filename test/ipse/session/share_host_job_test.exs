if System.get_env("IPSE_BOUND_HOST_FIXTURE") do
  Code.require_file("test/support/accepted_lease_positive.exs")
end

unless Code.ensure_loaded?(Ipse.Test.ManagedPolicy),
  do: Code.require_file("test/support/managed_policy.exs")

Code.require_file("test/support/session_transaction_bridge.exs")

defmodule Ipse.Test.ShareHostProxy do
  def bind(coordinator), do: Process.put({__MODULE__, :coordinator}, coordinator)

  def take_terminal(port) do
    if Port.connect(port, Process.get({__MODULE__, :coordinator})), do: :ok, else: :error
  end

  def expiry_pause do
    if System.get_env("IPSE_BOUND_EXPIRE_BEFORE_ACTIVATION") == "1" do
      deadline = Process.get({AcceptedLeasePositive, :accepted_deadline})
      true = is_integer(deadline)
      IO.puts("BOUND_BEFORE_ACTIVATION")
      Process.sleep(max(deadline - System.system_time(:millisecond) + 20, 0))
    end

    if System.get_env("IPSE_BOUND_LOSE_SOURCE_BEFORE_ACTIVATION") == "1" do
      {:source, identity, _} =
        Enum.find(Process.get({Ipse.Test.ShareHostProbe, :extras}), fn {kind, _, _} ->
          kind == :source
        end)

      {_, 0} = System.cmd("/bin/kill", ["-KILL", Integer.to_string(identity.pid)])
      IO.puts("BOUND_SOURCE_OWNER_KILLED")
    end

    if System.get_env("IPSE_BOUND_LOSE_JOURNAL_BEFORE_ACTIVATION") == "1" do
      {:journal, identity, _} =
        Enum.find(Process.get({Ipse.Test.ShareHostProbe, :extras}), fn {kind, _, _} ->
          kind == :journal
        end)

      {_, 0} = System.cmd("/bin/kill", ["-KILL", Integer.to_string(identity.pid)])
      IO.puts("BOUND_JOURNAL_OWNER_KILLED")
    end

    :ok
  end

  def call(action) do
    ref = make_ref()
    send(Process.get({__MODULE__, :coordinator}), {:bridge_call, self(), ref, action})

    receive do
      {:bridge_reply, ^ref, result} -> result
    after
      6_000 -> {:error, :cleanup_unconfirmed}
    end
  end

  def begin_controlled_session_share(owner, job, intent), do: call({:begin, owner, job, intent})

  def begin_synthetic_notice_share(owner, job, intent),
    do: call({:begin_notice, owner, job, intent})

  def begin_synthetic_review_share(owner, job, intent),
    do: call({:begin_review, owner, job, intent})

  def begin_synthetic_supersession_review_share(owner, job, intent, sha),
    do: call({:begin_supersession_review, owner, job, intent, sha})

  def begin_synthetic_accepted_notice_share(owner, job, intent),
    do:
      call(
        {:begin_accepted_notice, owner, job, intent,
         Process.get({AcceptedLeasePositive, :accepted_deadline})}
      )

  def spawn_synthetic_notice_terminal(owner, job, cap) do
    case call({:spawn_notice, owner, job, cap}) do
      {:ok, port} = result ->
        Process.put({__MODULE__, :terminal}, port)
        result

      other ->
        other
    end
  end

  def send_synthetic_review_manifest(owner, job, cap, prefix) do
    port = Process.get({__MODULE__, :terminal})
    with :ok <- take_terminal(port), do: call({:review_manifest, owner, job, cap, prefix, port})
  end

  def thaw_synthetic_review(owner, job, cap, port) do
    with :ok <- take_terminal(port), do: call({:review_thaw, owner, job, cap, port})
  end

  def session_share_identity(owner, job, cap), do: call({:identity, owner, job, cap})

  def configure_session_control(owner, job, cap, pid, name, secret),
    do: call({:configure, owner, job, cap, pid, name, secret})

  def export_session_share(owner, job, cap, recipient),
    do: call({:export, owner, job, cap, recipient})

  def settle_session_share(owner, job, cap), do: call({:settle, owner, job, cap})

  def prepare_terminal_share_close(owner, job, cap, port),
    do: call({:prepare_close, owner, job, cap, port})

  def finish_session_share(owner, job, cap), do: call({:finish, owner, job, cap})

  def abort_controlled_session_share(owner, job, cap, port),
    do: call({:abort, owner, job, cap, port})

  def send_control(port, operation, pid, name, secret),
    do: call({:send_control, port, operation, pid, name, secret})

  def await_session(cap, phase), do: call({:await_session, cap, phase})
  def await_host_transfer(port, operation), do: call({:await_transfer, port, operation})
  def await_host_exit(port), do: call({:await_exit, port})
end

defmodule Ipse.Test.ShareHostProbe do
  # Compiled only into this isolated fixture's Host, immediately after the
  # real Session has admitted and journaled the worker's action.
  def pause(owner, job, worker, intent) do
    test = Process.whereis(:ipse_share_host_fixture)
    send(test, {:host_ready, self(), owner, job, worker, intent})
    loop(test, owner, job, intent)
  end

  defp loop(test, owner, job, intent) do
    receive do
      {:probe, command} ->
        result =
          case command do
            {:begin, candidate} ->
              Ipse.Extension.Host.begin_session_share(owner, job, candidate)

            {:controlled_begin, candidate} ->
              Ipse.Extension.Host.begin_controlled_session_share(owner, job, candidate)

            {:controlled_notice_begin, candidate} ->
              Ipse.Extension.Host.begin_synthetic_notice_share(owner, job, candidate)

            {:controlled_review_begin, candidate} ->
              Ipse.Extension.Host.begin_synthetic_review_share(owner, job, candidate)

            {:supersession_source_begin, sha} ->
              Ipse.Extension.Host.begin_supersession_source_share(owner, job, intent, sha)

            {:supersession_display_begin, sha} ->
              Ipse.Extension.Host.begin_synthetic_supersession_review_share(
                owner,
                job,
                intent,
                sha
              )

            {:supersession_record_fixture, sha, event} ->
              GenServer.call(owner, {:supersession_record, job, sha, event})

            {:supersession_display_fixture, candidate, sha} ->
              Ipse.Extension.Host.begin_synthetic_supersession_review_share(
                owner,
                job,
                candidate,
                sha
              )

            {:supersession_display_ticket, candidate, sha} ->
              GenServer.call(
                owner,
                {:session_control_ticket_supersession_display_fixture, job, candidate, sha}
              )

            {:source_ticket, proofs} ->
              GenServer.call(owner, {:session_control_ticket_source_fixture, job, intent, proofs})

            {:source_begin, ticket, operation, deadline} ->
              Ipse.Test.SessionTransactionBridge.begin_prepared(
                owner,
                job,
                intent,
                ticket,
                operation,
                deadline
              )

            {:source_begin_candidate, candidate, ticket, operation, deadline} ->
              Ipse.Test.SessionTransactionBridge.begin_prepared(
                owner,
                job,
                candidate,
                ticket,
                operation,
                deadline
              )

            {:controlled_accepted_notice_begin, candidate, cutoff} ->
              Ipse.Extension.Host.begin_synthetic_accepted_notice_share(
                owner,
                job,
                candidate,
                cutoff
              )

            {:effect_controlled_begin, candidate} ->
              Ipse.Session.Resources.file_effect(fn ->
                Ipse.Extension.Host.begin_controlled_session_share(owner, job, candidate)
              end)

            {:stale_preparation, candidate} ->
              stale_preparation(owner, job, candidate)

            {:synthetic_tty, paths} ->
              caps =
                Enum.map(paths, fn path ->
                  {:ok, cap} = Ipse.Runner.Transaction.acquire(path)
                  cap
                end)

              result =
                Ipse.Runner.LeasedTerminal.exercise(
                  owner,
                  job,
                  intent,
                  caps,
                  Path.dirname(hd(paths))
                )

              Enum.each(Enum.reverse(caps), &Ipse.Runner.Transaction.release/1)
              result

            {:synthetic_notice_tty, paths} ->
              caps =
                Enum.map(paths, fn path ->
                  {:ok, cap} = Ipse.Runner.Transaction.acquire(path)
                  cap
                end)

              result =
                Ipse.Runner.LeasedTerminal.exercise_notice(
                  owner,
                  job,
                  intent,
                  caps,
                  Path.dirname(hd(paths))
                )

              Enum.each(Enum.reverse(caps), &Ipse.Runner.Transaction.release/1)
              result

            {:session_transaction, paths} ->
              Ipse.Test.SessionTransactionBridge.run(owner, job, intent, paths)

            {:session_transaction_hold, paths} ->
              Ipse.Test.SessionTransactionBridge.run(owner, job, intent, paths, true)

            {:session_transaction_wrong_recipient, paths} ->
              Ipse.Test.SessionTransactionBridge.run(owner, job, intent, paths, :wrong_recipient)

            {:session_transaction_source, paths, proofs} ->
              Ipse.Test.SessionTransactionBridge.run(owner, job, intent, paths, {:source, proofs})

            {:session_transaction_source_hold, paths, proofs} ->
              Ipse.Test.SessionTransactionBridge.run(
                owner,
                job,
                intent,
                paths,
                {:source_hold, proofs}
              )

            {:session_transaction_sources, paths, active, context, inactive} ->
              Ipse.Session.StoredSources.with_shareable_groups(context, inactive, fn _, leases ->
                Ipse.Test.SessionTransactionBridge.run(
                  owner,
                  job,
                  intent,
                  paths,
                  {:source_group, [active], Enum.map(leases, & &1.token)}
                )
              end)

            {:session_transaction_source_loss, paths, active, context, inactive} ->
              Ipse.Session.StoredSources.with_shareable_groups(context, inactive, fn _, leases ->
                Ipse.Test.SessionTransactionBridge.run(
                  owner,
                  job,
                  intent,
                  paths,
                  {:source_group_loss, [active], Enum.map(leases, & &1.token)}
                )
              end)

            {:synthetic_group_tty, paths, context, proofs} ->
              caps =
                Enum.map(paths, fn path ->
                  {:ok, cap} = Ipse.Runner.Transaction.acquire(path)
                  cap
                end)

              result =
                Ipse.Session.StoredSources.with_shareable_groups(context, proofs, fn _, leases ->
                  Ipse.Runner.LeasedTerminal.exercise_group(
                    owner,
                    job,
                    intent,
                    caps,
                    Path.dirname(hd(paths)),
                    Enum.map(leases, & &1.token)
                  )
                end)

              Enum.each(Enum.reverse(caps), &Ipse.Runner.Transaction.release/1)
              result

            {:synthetic_review_tty, paths, context, proofs} ->
              caps =
                Enum.map(paths, fn path ->
                  {:ok, cap} = Ipse.Runner.Transaction.acquire(path)
                  cap
                end)

              result =
                Ipse.Session.StoredSources.with_shareable_groups(context, proofs, fn _, leases ->
                  Ipse.Runner.LeasedTerminal.exercise_review(
                    owner,
                    job,
                    intent,
                    caps,
                    Path.dirname(hd(paths)),
                    leases,
                    proofs
                  )
                end)

              Enum.each(Enum.reverse(caps), &Ipse.Runner.Transaction.release/1)
              result

            {:synthetic_review_swapped, paths, context, proofs} ->
              caps =
                Enum.map(paths, fn path ->
                  {:ok, cap} = Ipse.Runner.Transaction.acquire(path)
                  cap
                end)

              result =
                Ipse.Session.StoredSources.with_shareable_groups(context, proofs, fn _, [a, b] ->
                  swapped = [%{a | token: b.token}, %{b | token: a.token}]

                  Ipse.Runner.LeasedTerminal.exercise_review(
                    owner,
                    job,
                    intent,
                    caps,
                    Path.dirname(hd(paths)),
                    swapped,
                    proofs
                  )
                end)

              Enum.each(Enum.reverse(caps), &Ipse.Runner.Transaction.release/1)
              result

            {:synthetic_union_tty, paths, context, proofs, candidate} ->
              caps =
                Enum.map(paths, fn path ->
                  {:ok, cap} = Ipse.Runner.Transaction.acquire(path)
                  cap
                end)

              result =
                Ipse.Session.StoredSources.with_shareable_union(
                  context,
                  candidate,
                  proofs,
                  fn sources, leases, active? ->
                    true = active? and Enum.map(sources, & &1["proof"]) === proofs

                    Ipse.Runner.LeasedTerminal.exercise_group(
                      owner,
                      job,
                      candidate,
                      caps,
                      Path.dirname(hd(paths)),
                      Enum.map(leases, & &1.token)
                    )
                  end
                )

              Enum.each(Enum.reverse(caps), &Ipse.Runner.Transaction.release/1)
              result

            {kind, paths, context, proofs, candidate}
            when kind in [:synthetic_union_review, :synthetic_supersession_review] ->
              caps =
                Enum.map(paths, fn path ->
                  {:ok, cap} = Ipse.Runner.Transaction.acquire(path)
                  cap
                end)

              result =
                Ipse.Session.StoredSources.with_shareable_union(
                  context,
                  candidate,
                  proofs,
                  fn sources, leases, active? ->
                    true = active? and Enum.map(sources, & &1["proof"]) === proofs

                    inactive = Enum.filter(proofs, &(&1["session_id"] != context.session_id))

                    result =
                      if kind == :synthetic_union_review do
                        Ipse.Runner.LeasedTerminal.exercise_review(
                          owner,
                          job,
                          candidate,
                          caps,
                          Path.dirname(hd(paths)),
                          leases,
                          inactive
                        )
                      else
                        Ipse.Runner.LeasedTerminal.exercise_supersession_review(
                          owner,
                          job,
                          candidate,
                          caps,
                          Path.dirname(hd(paths)),
                          leases,
                          inactive,
                          Ipse.JSON.sha256("unrecorded relation")
                        )
                      end

                    if result == :ok and System.get_env("IPSE_SHARE_TTY_UNION_RACE") == "1",
                      do: send(test, :synthetic_review_callback_completed)

                    result
                  end
                )

              Enum.each(Enum.reverse(caps), &Ipse.Runner.Transaction.release/1)
              result

            {kind, paths, context, proofs, candidate, sha}
            when kind in [:synthetic_supersession_positive, :synthetic_supersession_omit] ->
              caps =
                Enum.map(paths, fn path ->
                  {:ok, cap} = Ipse.Runner.Transaction.acquire(path)
                  cap
                end)

              result =
                Ipse.Session.StoredSources.with_shareable_union(
                  context,
                  candidate,
                  proofs,
                  fn sources, leases, active? ->
                    true = active? and Enum.map(sources, & &1["proof"]) === proofs

                    {selected_leases, selected_proofs} =
                      if kind == :synthetic_supersession_omit,
                        do: {[], []},
                        else:
                          {leases, Enum.filter(proofs, &(&1["session_id"] != context.session_id))}

                    Ipse.Runner.LeasedTerminal.exercise_supersession_review(
                      owner,
                      job,
                      candidate,
                      caps,
                      Path.dirname(hd(paths)),
                      selected_leases,
                      selected_proofs,
                      sha
                    )
                  end
                )

              Enum.each(Enum.reverse(caps), &Ipse.Runner.Transaction.release/1)
              result

            {:coordinated_supersession_review, paths, context, proofs, candidate, sha} ->
              coordinator = self()

              effect =
                Ipse.Session.Resources.async(fn ->
                  Ipse.Session.Resources.file_effect(fn ->
                    Ipse.Test.ShareHostProxy.bind(coordinator)

                    send(
                      Process.whereis(:ipse_share_host_fixture),
                      {:coordinated_review_owners, coordinator, self()}
                    )

                    send(coordinator, {:bridge_worker, self()})

                    caps =
                      Enum.map(paths, fn path ->
                        {:ok, cap} = Ipse.Runner.Transaction.acquire(path)
                        cap
                      end)

                    result =
                      Ipse.Session.StoredSources.with_shareable_union(
                        context,
                        candidate,
                        proofs,
                        fn sources, leases, active? ->
                          true = active? and Enum.map(sources, & &1["proof"]) === proofs

                          if System.get_env("IPSE_SHARE_COORDINATED_INPUT_LOSS") == "1" do
                            [%{token: token}] = leases
                            {:ok, identity} = Ipse.Session.StoredSources.share_identity(token)

                            send(
                              Process.whereis(:ipse_share_host_fixture),
                              {:coordinated_review_source, self(), identity.pid}
                            )
                          end

                          apply(
                            Ipse.Test.CoordinatedReviewTerminal,
                            :exercise_supersession_review,
                            [
                              owner,
                              job,
                              candidate,
                              caps,
                              Path.dirname(hd(paths)),
                              leases,
                              Enum.filter(proofs, &(&1["session_id"] != context.session_id)),
                              sha
                            ]
                          )
                        end
                      )

                    Enum.each(Enum.reverse(caps), &Ipse.Runner.Transaction.release/1)
                    result
                  end)
                end)

              coordinate(effect)

            {kind, paths} when kind in [:synthetic_tty_six, :synthetic_tty_six_notice] ->
              {main, extra} = Enum.split(paths, 3)

              caps =
                Enum.map(main, fn path ->
                  {:ok, cap} = Ipse.Runner.Transaction.acquire(path)
                  cap
                end)

              tasks = Enum.map(extra, &extra_start/1)

              ids =
                Enum.map(tasks, fn task ->
                  receive do
                    {:extra_ready, pid, id} when pid == task.pid -> id
                  after
                    5_000 -> raise "extra lease unavailable"
                  end
                end)

              Process.put({__MODULE__, :extras}, Enum.zip(tasks, ids))

              result =
                apply(
                  Ipse.Test.AcceptedLeasedTerminal,
                  if(kind == :synthetic_tty_six_notice, do: :exercise_notice, else: :exercise),
                  [
                    owner,
                    job,
                    intent,
                    caps,
                    Path.dirname(hd(paths))
                  ]
                )

              Enum.each(Enum.reverse(caps), &Ipse.Runner.Transaction.release/1)
              Enum.each(tasks, &send(&1.pid, :release))
              Enum.each(tasks, &Task.await(&1, 5_000))
              Process.delete({__MODULE__, :extras})
              result

            {kind, paths} when kind in [:coordinated_tty_six, :coordinated_tty_six_notice] ->
              {main, extra} = Enum.split(paths, 3)
              tasks = Enum.map(extra, &extra_start/1)

              ids =
                Enum.map(tasks, fn task ->
                  receive do
                    {:extra_ready, pid, id} when pid == task.pid -> id
                  after
                    5_000 -> raise "extra lease unavailable"
                  end
                end)

              coordinator = self()

              effect =
                Task.async(fn ->
                  Ipse.Session.Resources.file_effect(fn ->
                    Ipse.Test.ShareHostProxy.bind(coordinator)
                    Process.put({__MODULE__, :extras}, Enum.zip(tasks, ids))
                    send(coordinator, {:bridge_worker, self()})

                    caps =
                      Enum.map(main, fn path ->
                        {:ok, cap} = Ipse.Runner.Transaction.acquire(path)
                        cap
                      end)

                    result =
                      apply(
                        Ipse.Test.CoordinatedAcceptedTerminal,
                        if(kind == :coordinated_tty_six_notice,
                          do: :exercise_notice,
                          else: :exercise
                        ),
                        [
                          owner,
                          job,
                          intent,
                          caps,
                          Path.dirname(hd(paths))
                        ]
                      )

                    Enum.each(Enum.reverse(caps), &Ipse.Runner.Transaction.release/1)
                    result
                  end)
                end)

              result = coordinate(effect)
              Enum.each(tasks, &send(&1.pid, :release))
              Enum.each(tasks, &Task.await(&1, 5_000))
              result

            {:coordinated_bound_six, fixture} ->
              coordinator = self()

              tasks = [
                Task.async(fn ->
                  apply(AcceptedLeasePositive, :acceptance_owner, [coordinator, self(), fixture])
                end),
                Task.async(fn ->
                  apply(AcceptedLeasePositive, :bound_source_owner, [coordinator, self(), fixture])
                end)
              ]

              extras =
                Enum.map(tasks, fn task ->
                  receive do
                    {:extra_ready, pid, endpoint, id, nil} when pid == task.pid ->
                      {task, id, endpoint}
                  after
                    5_000 -> raise "bound lease unavailable"
                  end
                end)

              effect =
                Task.async(fn ->
                  Ipse.Session.Resources.file_effect(fn ->
                    Ipse.Test.ShareHostProxy.bind(coordinator)
                    Process.put({__MODULE__, :extras}, extras)

                    apply(AcceptedLeasePositive, :with_triad, [
                      "bound-acceptance",
                      fixture,
                      [],
                      fn caps, _ ->
                        send(coordinator, {:bridge_worker, self()})

                        result =
                          apply(
                            Ipse.Test.CoordinatedAcceptedTerminal,
                            if(System.get_env("IPSE_BOUND_HOST_NOTICE") == "1",
                              do: :exercise_notice,
                              else: :exercise
                            ),
                            [
                              owner,
                              job,
                              intent,
                              caps,
                              fixture["cwd"]
                            ]
                          )

                        {:ok, result}
                      end
                    ])
                  end)
                end)

              result = coordinate(effect)
              Enum.each(extras, fn {_, _, endpoint} -> send(endpoint, :release) end)
              Enum.each(tasks, &Task.await(&1, 5_000))

              case result do
                {:ok, :ok} -> :ok
                _ -> result
              end

            {:coordinated_reference_six, fixture} ->
              coordinator = self()
              state = :sys.get_state(owner)

              context = %{
                config: state.config,
                session_id: state.id,
                cwd: fixture["cwd"],
                history_dir: fixture["history_dir"]
              }

              effect =
                Task.async(fn ->
                  Ipse.Session.Resources.file_effect(fn ->
                    {:ok, inspection} =
                      Ipse.Session.ManagedUse.inspect_accepted(
                        context,
                        fixture["link"],
                        Ipse.JSON.digest([fixture["recipe"]])
                      )

                    dependency = inspection["dependency"]

                    ordinary_entered = :atomics.new(1, signed: false)

                    {:error, _} =
                      Ipse.Session.ManagedUse.with_dependencies(context, [dependency], fn _ ->
                        :atomics.put(ordinary_entered, 1, 1)
                        {:ok, :unexpected_delivery}
                      end)

                    0 = :atomics.get(ordinary_entered, 1)

                    for callback <- [
                          fn _, _, _ -> {:error, :fixture_interrupted} end,
                          fn _, _, _ -> raise "synthetic retained callback interruption" end
                        ] do
                      {:unknown, :accepted_reference_unconfirmed} =
                        Ipse.Session.ManagedUse.with_accepted_reference(
                          context,
                          dependency,
                          callback
                        )
                    end

                    {:error, _} =
                      Ipse.Session.ManagedUse.with_accepted_reference(
                        context,
                        put_in(
                          dependency,
                          ["subject", "acceptance", "event_sha256"],
                          Ipse.JSON.sha256("other")
                        ),
                        fn _, _, _ -> raise "changed acceptance reached callback" end
                      )

                    Ipse.Session.ManagedUse.with_accepted_reference(
                      context,
                      dependency,
                      fn current, journal, source ->
                        true = current["dependency"] === dependency

                        {:ok, journal_id} =
                          Ipse.Session.PendingAcceptance.journal_share_identity(journal)

                        {:ok, source_id} = Ipse.Session.StoredSources.share_identity(source)
                        {:ok, caps} = Ipse.Runner.Transaction.retained_share_stack()
                        Ipse.Test.ShareHostProxy.bind(coordinator)

                        Process.put({__MODULE__, :extras}, [
                          {:journal, journal_id, journal},
                          {:source, source_id, source}
                        ])

                        deadline =
                          if System.get_env("IPSE_BOUND_EXPIRE_BEFORE_ACTIVATION") == "1",
                            do:
                              min(
                                current["valid_until_ms"],
                                System.system_time(:millisecond) + 1_500
                              ),
                            else: current["valid_until_ms"]

                        Process.put({AcceptedLeasePositive, :accepted_deadline}, deadline)

                        send(coordinator, {:bridge_worker, self()})

                        result =
                          apply(
                            Ipse.Test.CoordinatedAcceptedTerminal,
                            if(System.get_env("IPSE_BOUND_HOST_NOTICE") == "1",
                              do: :exercise_notice,
                              else: :exercise
                            ),
                            [
                              owner,
                              job,
                              intent,
                              caps,
                              fixture["cwd"]
                            ]
                          )

                        if result == :ok, do: {:ok, :ok}, else: {:error, :cleanup_unconfirmed}
                      end
                    )
                  end)
                end)

              case coordinate(effect) do
                {:ok, :ok} -> :ok
                result -> result
              end

            {:configure_session, cap, recipient, name, secret} ->
              Ipse.Extension.Host.configure_session_control(
                owner,
                job,
                cap,
                recipient,
                name,
                secret
              )

            {:share_identity, cap} ->
              Ipse.Extension.Host.session_share_identity(owner, job, cap)

            {:spawn_synthetic_terminal, cap} ->
              Ipse.Extension.Host.spawn_synthetic_notice_terminal(owner, job, cap)

            {:prepare_terminal_close, cap, terminal_port} ->
              Ipse.Extension.Host.prepare_terminal_share_close(owner, job, cap, terminal_port)

            {:review_thaw, cap, terminal_port} ->
              Ipse.Extension.Host.thaw_synthetic_review(owner, job, cap, terminal_port)

            {:review_manifest, cap, prefix} ->
              Ipse.Extension.Host.send_synthetic_review_manifest(owner, job, cap, prefix)

            {:configure_host, port, operation, recipient, name, secret} ->
              Ipse.Runner.send_owner_control(port, operation, :host, recipient, name, secret)

            {:controlled_abort, cap, port} ->
              Ipse.Extension.Host.abort_controlled_session_share(owner, job, cap, port)

            {:close_host_control, port} ->
              Ipse.Runner.close_owner_control(port)

            {:export, cap, request} ->
              Ipse.Extension.Host.export_session_share(owner, job, cap, request)

            {:settle, cap} ->
              Ipse.Extension.Host.settle_session_share(owner, job, cap)

            {:finish, cap} ->
              Ipse.Extension.Host.finish_session_share(owner, job, cap)

            {:abort, cap} ->
              Ipse.Extension.Host.abort_session_share(owner, job, cap)

            :open_owner_control ->
              Ipse.Runner.open_owner_control()

            {:await_owner_control, port} ->
              await_owner_control(port)

            {:send_owner_control, port, operation, role, recipient, name, secret} ->
              Ipse.Runner.send_owner_control(port, operation, role, recipient, name, secret)
          end

        send(test, {:probe_result, command, result})
        loop(test, owner, job, intent)

      :continue ->
        :ok
    after
      20_000 -> exit(:fixture_timeout)
    end
  end

  defp extra_start(path) do
    parent = self()

    Task.async(fn ->
      {:ok, cap} = Ipse.Runner.Transaction.acquire(path)
      {:ok, id} = Ipse.Runner.Transaction.retained_share_identity(cap)
      send(parent, {:extra_ready, self(), id})

      receive do
        {:export, operation, request, deadline, reply} ->
          send(
            reply,
            {:extra_export, self(),
             Ipse.Runner.Transaction.retained_share_export(cap, operation, request, deadline)}
          )

          receive do
            {:settle, operation, deadline} ->
              send(
                reply,
                {:extra_settle, self(),
                 Ipse.Runner.Transaction.retained_share_settle(cap, operation, deadline)}
              )

              receive do
                :release -> Ipse.Runner.Transaction.release(cap)
              after
                10_000 -> :timeout
              end
          after
            10_000 -> :timeout
          end
      after
        10_000 -> :timeout
      end
    end)
  end

  def extra_ids, do: Enum.map(Process.get({__MODULE__, :extras}), &elem(&1, 1))

  def extra_export(pid, operation, pairs, deadline) do
    Enum.zip(Process.get({__MODULE__, :extras}), pairs)
    |> Enum.reduce_while(:ok, fn {extra, {name, secret}}, :ok ->
      case extra do
        {kind, id, token} when kind in [:journal, :source] ->
          request = <<pid::32, name::binary, secret::binary, id.device::64, id.inode::64>>

          result =
            if kind == :journal,
              do:
                Ipse.Session.PendingAcceptance.journal_share_export(
                  token,
                  operation,
                  request,
                  deadline
                ),
              else: Ipse.Session.StoredSources.share_export(token, operation, request, deadline)

          if result == :ok, do: {:cont, :ok}, else: {:halt, :error}

        other ->
          {task, id, endpoint} =
            case other do
              {task, id} -> {task, id, task.pid}
              {task, id, endpoint} -> {task, id, endpoint}
            end

          request = <<pid::32, name::binary, secret::binary, id.device::64, id.inode::64>>
          send(endpoint, {:export, operation, request, deadline, self()})

          receive do
            {:extra_export, owner, :ok} when owner == task.pid -> {:cont, :ok}
            {:extra_export, owner, _} when owner == task.pid -> {:halt, :error}
            {:exported, ^endpoint, :ok} -> {:cont, :ok}
            {:exported, ^endpoint, _} -> {:halt, :error}
          after
            5_000 -> {:halt, :error}
          end
      end
    end)
  end

  def extra_settle(operation, deadline) do
    Enum.reduce_while(Process.get({__MODULE__, :extras}), :ok, fn extra, :ok ->
      case extra do
        {kind, _, token} when kind in [:journal, :source] ->
          result =
            if kind == :journal,
              do: Ipse.Session.PendingAcceptance.journal_share_settle(token, operation, deadline),
              else: Ipse.Session.StoredSources.share_settle(token, operation, deadline)

          if result == :ok, do: {:cont, :ok}, else: {:halt, :error}

        other ->
          {task, endpoint, bound} =
            case other do
              {task, _} -> {task, task.pid, false}
              {task, _, endpoint} -> {task, endpoint, true}
            end

          if bound,
            do: send(endpoint, :settle),
            else: send(endpoint, {:settle, operation, deadline})

          receive do
            {:extra_settle, owner, :ok} when owner == task.pid -> {:cont, :ok}
            {:extra_settle, owner, _} when owner == task.pid -> {:halt, :error}
            {:settled, ^endpoint, :ok} -> {:cont, :ok}
            {:settled, ^endpoint, _} -> {:halt, :error}
          after
            5_000 -> {:halt, :error}
          end
      end
    end)
  end

  defp coordinate(task) do
    receive do
      {:bridge_worker, worker} -> coordinate(task, worker)
    after
      5_000 -> {:error, :bridge_worker_unavailable}
    end
  end

  defp coordinate(task, worker) do
    receive do
      {:bridge_call, ^worker, ref, action} ->
        result = bridge_action(action)

        result =
          case {action, result} do
            {{:spawn_notice, _, _, _}, {:ok, port}} ->
              if Port.connect(port, worker), do: {:ok, port}, else: {:error, :cleanup_unconfirmed}

            {{:review_manifest, _, _, _, _, port}, result} ->
              if Port.connect(port, worker), do: result, else: {:error, :cleanup_unconfirmed}

            {{:review_thaw, _, _, _, port}, result} ->
              if Port.connect(port, worker), do: result, else: {:error, :cleanup_unconfirmed}

            _ ->
              result
          end

        send(worker, {:bridge_reply, ref, result})
        coordinate(task, worker)

      {ref, result} when ref == task.ref ->
        Process.demonitor(ref, [:flush])
        result

      {:DOWN, ref, :process, _, reason} when ref == task.ref ->
        {:error, reason}
    after
      15_000 -> {:error, :bridge_timeout}
    end
  end

  defp bridge_action(action) do
    alias Ipse.Extension.Host

    case action do
      {:begin, owner, job, intent} ->
        Host.begin_controlled_session_share(owner, job, intent)

      {:begin_notice, owner, job, intent} ->
        Host.begin_synthetic_notice_share(owner, job, intent)

      {:begin_review, owner, job, intent} ->
        Host.begin_synthetic_review_share(owner, job, intent)

      {:begin_supersession_review, owner, job, intent, sha} ->
        Host.begin_synthetic_supersession_review_share(owner, job, intent, sha)

      {:begin_accepted_notice, owner, job, intent, cutoff} ->
        Host.begin_synthetic_accepted_notice_share(owner, job, intent, cutoff)

      {:spawn_notice, owner, job, cap} ->
        Host.spawn_synthetic_notice_terminal(owner, job, cap)

      {:review_manifest, owner, job, cap, prefix, _port} ->
        Host.send_synthetic_review_manifest(owner, job, cap, prefix)

      {:review_thaw, owner, job, cap, port} ->
        Host.thaw_synthetic_review(owner, job, cap, port)

      {:identity, owner, job, cap} ->
        Host.session_share_identity(owner, job, cap)

      {:configure, owner, job, cap, pid, name, secret} ->
        Host.configure_session_control(owner, job, cap, pid, name, secret)

      {:export, owner, job, cap, recipient} ->
        Host.export_session_share(owner, job, cap, recipient)

      {:settle, owner, job, cap} ->
        Host.settle_session_share(owner, job, cap)

      {:prepare_close, owner, job, cap, port} ->
        Host.prepare_terminal_share_close(owner, job, cap, port)

      {:finish, owner, job, cap} ->
        Host.finish_session_share(owner, job, cap)

      {:abort, owner, job, cap, port} ->
        Host.abort_controlled_session_share(owner, job, cap, port)

      {:send_control, port, operation, pid, name, secret} ->
        Ipse.Runner.send_owner_control(port, operation, :host, pid, name, secret)

      {:await_session, cap, phase} ->
        receive do
          {:session_owner_control, ^cap, ^phase} -> :ok
        after
          5_000 -> :error
        end

      {:await_transfer, port, operation} ->
        expected = <<?H, 17::32, operation::binary, 2, ?T, 17::32, operation::binary, 2>>
        await_control_bytes(port, expected, <<>>)

      {:await_exit, port} ->
        receive do
          {^port, {:exit_status, 0}} -> :ok
          {^port, _} -> :error
        after
          5_000 -> :error
        end
    end
  end

  defp await_control_bytes(_port, expected, expected), do: :ok

  defp await_control_bytes(port, expected, buffer) when byte_size(buffer) < byte_size(expected) do
    receive do
      {^port, {:data, bytes}} -> await_control_bytes(port, expected, buffer <> bytes)
      {^port, _} -> :error
    after
      5_000 -> :error
    end
  end

  defp await_control_bytes(_, _, _), do: :error

  defp await_owner_control(port, buffer \\ <<>>) do
    case buffer do
      <<?R, 16::32, "owner-control-v1">> ->
        :ok

      _ ->
        receive do
          {^port, {:data, bytes}} when byte_size(buffer) + byte_size(bytes) <= 64 ->
            await_owner_control(port, buffer <> bytes)

          {^port, {:exit_status, _}} ->
            {:error, :owner_control_unavailable}
        after
          5_000 -> {:error, :owner_control_unavailable}
        end
    end
  end

  defp stale_preparation(owner, job, intent) do
    {:ok, ticket, operation, deadline} =
      GenServer.call(owner, {:session_control_ticket, job, intent})

    {:ok, prepared} = Ipse.Runner.prepare_owner_control(job, intent, ticket, operation, deadline)
    {:ok, port} = Ipse.Runner.open_prepared_owner_control(prepared, self(), job, intent)
    :ok = await_owner_control(port)
    changed = Map.put(prepared, :helper, "/tmp/not-the-pinned-helper")
    first = GenServer.call(owner, {:session_share_begin_controlled, job, intent, changed, port})
    replay = GenServer.call(owner, {:session_share_begin_controlled, job, intent, prepared, port})
    :ok = Ipse.Runner.close_owner_control(port)
    {first, replay}
  end

  def tty_pause(owner, port, identities, session_identity) do
    test = Process.whereis(:ipse_share_host_fixture)
    send(test, {:tty_paused, self(), owner, port, identities, session_identity})

    receive do
      :tty_continue -> :ok
    after
      10_000 -> :error
    end
  end

  def tty_pause_group(owner, port, identities, session_identity, sources) do
    test = Process.whereis(:ipse_share_host_fixture)
    send(test, {:tty_group_paused, self(), owner, port, identities, session_identity, sources})

    receive do
      :tty_continue -> :ok
    after
      10_000 -> :error
    end
  end
end

defmodule Ipse.Session.ShareHostJobTest do
  use ExUnit.Case, async: false
  @moduletag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux native share")
  alias Ipse.{JSON, Runner, Session, Usage}
  alias Ipse.Extension.{Artifact, Catalog, Config, Registry}

  setup_all do
    # This source-only hook runs in the real Host task; it is never present in
    # the production Host BEAM. Refuse if the exact insertion point changes.
    original_app = Application.app_dir(:ipse)
    original_ebin = Path.join(original_app, "ebin")
    root = Path.join(System.tmp_dir!(), "ipse-share-host-build-" <> Usage.id())
    isolated_app = Path.join(root, "ipse")
    isolated_ebin = Path.join(isolated_app, "ebin")
    File.mkdir_p!(isolated_app)
    File.cp_r!(original_ebin, isolated_ebin)
    File.ln_s!(Path.join(original_app, "priv"), Path.join(isolated_app, "priv"))

    host_name = "Elixir.Ipse.Extension.Host.beam"
    terminal_name = "Elixir.Ipse.Runner.LeasedTerminal.beam"
    path = Path.join(isolated_ebin, host_name)
    terminal_path = Path.join(isolated_ebin, terminal_name)
    original_host = File.read!(Path.join(original_ebin, host_name))
    original_terminal = File.read!(Path.join(original_ebin, terminal_name))
    previous_compiler_options = Code.compiler_options()

    on_exit(fn ->
      true = :code.replace_path(:ipse, String.to_charlist(original_ebin))

      for {module, file, original} <- [
            {Ipse.Extension.Host, Path.join(original_ebin, host_name), original_host},
            {Ipse.Runner.LeasedTerminal, Path.join(original_ebin, terminal_name),
             original_terminal}
          ] do
        :code.purge(module)
        :code.delete(module)
        {:module, ^module} = :code.load_binary(module, String.to_charlist(file), original)
      end

      Code.compiler_options(previous_compiler_options)
      File.rm_rf!(root)
    end)

    true = :code.replace_path(:ipse, String.to_charlist(isolated_ebin))

    source = File.read!("lib/ipse/extension/host.ex")
    needle = "case execute_admitted_action(context, worker, intent, request) do"
    assert length(String.split(source, needle)) == 2

    instrumented =
      String.replace(
        source,
        needle,
        "Ipse.Test.ShareHostProbe.pause(owner, job_ref, worker, intent)\n        " <> needle
      )

    Code.compiler_options(ignore_module_conflict: true)

    [{Ipse.Extension.Host, beam}] =
      Code.compile_string(instrumented, "share-host-instrumented.ex")

    if System.get_env("IPSE_SHARE_TTY_SIX") == "1" do
      terminal = File.read!("lib/ipse/runner/leased_terminal.ex")

      replacements = [
        {"defmodule Ipse.Runner.LeasedTerminal do",
         "defmodule Ipse.Test.AcceptedLeasedTerminal do"},
        {"SYNTHETIC_LEASED_DISPLAY", "SYNTHETIC_ACCEPTED_LEASE_DISPLAY"},
        {"v4-synthetic-lease-display", "v8-synthetic-accepted-display"},
        {"Host.begin_synthetic_notice_share(", "Host.begin_synthetic_accepted_notice_share("},
        {"count = 4 + length(sources),", "count = 6,"},
        {"leases = [session_identity | identities] ++ Enum.map(sources, &elem(&1, 1)),",
         "leases = [session_identity | identities] ++ Ipse.Test.ShareHostProbe.extra_ids(),"},
        {"slots = [0, 0, 1, 2] ++ List.duplicate(0, length(sources)),",
         "slots = [0, 0, 1, 2, 0, 0],"},
        {"List.duplicate(controls.operation, length(sources)),",
         "List.duplicate(controls.operation, 2),"},
        {":ok <- export_all(owner, job, cap, controls, pid, caps, leases, lease_pairs, deadline),",
         ":ok <- export_all(owner, job, cap, controls, pid, caps, leases, lease_pairs, deadline),\n           :ok <- Ipse.Test.ShareHostProbe.extra_export(pid, controls.operation, Enum.drop(lease_pairs, 4), deadline),"},
        {"export_sources(sources, Enum.drop(lease_pairs, 4), pid, controls.operation, deadline),",
         "export_sources(sources, [], pid, controls.operation, deadline),"},
        {":ok <- settle_sources(sources, controls.operation, deadline),",
         ":ok <- settle_sources(sources, controls.operation, deadline),\n           :ok <- Ipse.Test.ShareHostProbe.extra_settle(controls.operation, deadline),"}
      ]

      terminal =
        Enum.reduce(replacements, terminal, fn {before, after_text}, source ->
          assert String.contains?(source, before)
          String.replace(source, before, after_text)
        end)

      [{Ipse.Test.AcceptedLeasedTerminal, _}] =
        Code.compile_string(terminal, "accepted-terminal-fixture.ex")

      control_call =
        ~S'''
        Ipse.Runner.send_owner_control(
                     controls.host_port,
                     controls.operation,
                     :host,
                     pid,
                     hn,
                     hs
                   )
        '''
        |> String.trim()

      coordinated_replacements = [
        {"defmodule Ipse.Test.AcceptedLeasedTerminal do",
         "defmodule Ipse.Test.CoordinatedAcceptedTerminal do"},
        {"alias Ipse.Extension.Host", "alias Ipse.Test.ShareHostProxy, as: Host"},
        {control_call, "Host.send_control(controls.host_port, controls.operation, pid, hn, hs)"},
        {"await_session_transfer(owner, cap, deadline)", "Host.await_session(cap, :transferred)"},
        {"host_transfer(controls.host_port, owner, controls.operation, deadline, <<>>)",
         "Host.await_host_transfer(controls.host_port, controls.operation)"},
        {"await_exit(controls.host_port, owner, deadline)",
         "Host.await_host_exit(controls.host_port)"},
        {":ok <- Host.prepare_terminal_share_close(owner, job, cap, port),",
         ":ok <- Host.take_terminal(port),\n           :ok <- Host.prepare_terminal_share_close(owner, job, cap, port),"},
        {":ok <- await_exit(port, owner, deadline),", ":ok <- Host.await_host_exit(port),"},
        {"await_session_closed(owner, cap, deadline)", "Host.await_session(cap, :closed)"},
        {"defp await_session_notice(owner, cap, deadline) do\n    ref = Process.monitor(owner)\n\n    try do\n      receive do\n        {:session_owner_control, ^cap, :notice} -> :ok\n        {:DOWN, ^ref, :process, _, _} -> :error\n      after\n        max(deadline - System.monotonic_time(:millisecond), 0) -> :error\n      end\n    after\n      Process.demonitor(ref, [:flush])\n    end\n  end",
         "defp await_session_notice(_owner, cap, _deadline), do: Host.await_session(cap, :notice)"},
        {":ok <- send_frame(port, ?A, body),",
         ":ok <- Ipse.Test.ShareHostProxy.expiry_pause(),\n           :ok <- send_frame(port, ?A, body),"},
        {"System.system_time(:millisecond) +\n               max(deadline - System.monotonic_time(:millisecond), 0)",
         "min(System.system_time(:millisecond) + max(deadline - System.monotonic_time(:millisecond), 0), Process.get({AcceptedLeasePositive, :accepted_deadline}, 9_007_199_254_740_991))"}
      ]

      coordinated =
        Enum.reduce(coordinated_replacements, terminal, fn {before, after_text}, source ->
          assert String.contains?(source, before)
          String.replace(source, before, after_text, global: false)
        end)

      coordinated =
        Enum.reduce(
          ~w(host_transfer await_session_transfer await_session_closed await_exit),
          coordinated,
          fn name, source -> String.replace(source, "defp #{name}(", "def #{name}(") end
        )
        |> String.replace(
          "defp configure_controls(owner, job, cap, controls, pid, {sn, ss}, {hn, hs}, deadline)",
          "defp configure_controls(owner, job, cap, controls, pid, {sn, ss}, {hn, hs}, _deadline)"
        )

      [{Ipse.Test.CoordinatedAcceptedTerminal, _}] =
        Code.compile_string(coordinated, "coordinated-accepted-terminal.ex")
    end

    File.write!(path, beam)
    :code.purge(Ipse.Extension.Host)
    :code.delete(Ipse.Extension.Host)

    if System.get_env("IPSE_SHARE_TTY_PAUSE") == "1" or
         System.get_env("IPSE_SHARE_TTY_GROUP_LOSS") == "1" do
      source = File.read!("lib/ipse/runner/leased_terminal.ex")
      needle = ":ok <- send_frame(port, ?A, body),"
      assert length(String.split(source, needle)) == 2

      pause =
        if System.get_env("IPSE_SHARE_TTY_GROUP_LOSS") == "1",
          do:
            "Ipse.Test.ShareHostProbe.tty_pause_group(owner, port, identities, session_identity, sources)",
          else: "Ipse.Test.ShareHostProbe.tty_pause(owner, port, identities, session_identity)"

      injected =
        String.replace(
          source,
          needle,
          ":ok <- " <>
            pause <>
            ",\n           " <>
            needle
        )

      [{Ipse.Runner.LeasedTerminal, beam}] =
        Code.compile_string(injected, "leased-terminal-instrumented.ex")

      File.write!(terminal_path, beam)
      :code.purge(Ipse.Runner.LeasedTerminal)
      :code.delete(Ipse.Runner.LeasedTerminal)
    end

    if System.get_env("IPSE_REVIEW_MANIFEST_INJECT") == "1" do
      source = File.read!("lib/ipse/runner/leased_terminal.ex")
      needle = "do: Host.send_synthetic_review_manifest(owner, job, cap, prefix),"
      assert length(String.split(source, needle)) == 2
      attack = "INJECTED_DISPLAY_MUST_NOT_APPEAR"

      replacement =
        "do: (:ok = send_frame(port, ?I, <<prefix::binary, #{byte_size(attack)}::32, #{inspect(attack)}::binary>>); send(Process.whereis(:ipse_share_host_fixture), :review_manifest_injected); Host.send_synthetic_review_manifest(owner, job, cap, prefix)),"

      [{Ipse.Runner.LeasedTerminal, instrumented_terminal}] =
        Code.compile_string(
          String.replace(source, needle, replacement),
          "review-manifest-injection.ex"
        )

      File.write!(terminal_path, instrumented_terminal)
      :code.purge(Ipse.Runner.LeasedTerminal)
      :code.delete(Ipse.Runner.LeasedTerminal)
    end

    if System.get_env("IPSE_TEST_SUPERSESSION_MANIFEST_COUNT") == "1" do
      source = File.read!("lib/ipse/runner/leased_terminal.ex")
      needle = "if relation_sources_match?(mode, controls),"
      assert length(String.split(source, needle)) == 2

      instrumented =
        source
        |> String.replace(needle, "if true,")
        |> String.replace("defp relation_sources_match?(", "def relation_sources_match?(")

      [{Ipse.Runner.LeasedTerminal, beam}] =
        Code.compile_string(instrumented, "synthetic-manifest-count-adversary.ex")

      File.write!(terminal_path, beam)
      :code.purge(Ipse.Runner.LeasedTerminal)
      :code.delete(Ipse.Runner.LeasedTerminal)
    end

    if System.get_env("IPSE_SHARE_COORDINATED_REVIEW") == "1" do
      terminal = File.read!("lib/ipse/runner/leased_terminal.ex")

      control_call =
        ~S'''
        Ipse.Runner.send_owner_control(
                     controls.host_port,
                     controls.operation,
                     :host,
                     pid,
                     hn,
                     hs
                   )
        '''
        |> String.trim()

      replacements = [
        {"defmodule Ipse.Runner.LeasedTerminal do",
         "defmodule Ipse.Test.CoordinatedReviewTerminal do"},
        {"alias Ipse.Extension.Host", "alias Ipse.Test.ShareHostProxy, as: Host"},
        {"defp configure_controls(owner, job, cap, controls, pid, {sn, ss}, {hn, hs}, deadline) do",
         "defp configure_controls(owner, job, cap, controls, pid, {sn, ss}, {hn, hs}, _deadline) do"},
        {control_call, "Host.send_control(controls.host_port, controls.operation, pid, hn, hs)"},
        {"await_session_transfer(owner, cap, deadline)", "Host.await_session(cap, :transferred)"},
        {"host_transfer(controls.host_port, owner, controls.operation, deadline, <<>>)",
         "Host.await_host_transfer(controls.host_port, controls.operation)"},
        {"await_session_notice(owner, cap, deadline)", "Host.await_session(cap, :notice)"},
        {"await_exit(controls.host_port, owner, controls.overall_deadline)",
         "Host.await_host_exit(controls.host_port)"},
        {"await_session_closed(owner, cap, controls.overall_deadline)",
         "Host.await_session(cap, :closed)"}
      ]

      coordinated =
        Enum.reduce(replacements, terminal, fn {before, after_text}, source ->
          assert String.contains?(source, before)
          String.replace(source, before, after_text, global: false)
        end)

      coordinated =
        if System.get_env("IPSE_SHARE_COORDINATED_LOSS") == "1" do
          needle = ":ok <- send_frame(port, ?A, body),"
          assert length(String.split(coordinated, needle)) == 2

          String.replace(
            coordinated,
            needle,
            ":ok <- Ipse.Test.ShareHostProbe.tty_pause_group(owner, port, identities, session_identity, sources),\n           " <>
              needle
          )
        else
          coordinated
        end

      coordinated =
        Enum.reduce(
          ~w(host_transfer await_session_transfer await_session_closed await_session_notice),
          coordinated,
          fn name, source -> String.replace(source, "defp #{name}(", "def #{name}(") end
        )

      [{Ipse.Test.CoordinatedReviewTerminal, _}] =
        Code.compile_string(coordinated, "coordinated-review-fixture.ex")
    end

    assert {:module, Ipse.Extension.Host} =
             :code.load_abs(String.to_charlist(Path.rootname(path)))

    if evidence = System.get_env("IPSE_SHARE_HOST_SOURCE_EVIDENCE"),
      do: File.write!(evidence, instrumented)

    root = Path.join(System.tmp_dir!(), "ipse-share-host-artifact-" <> Usage.id())
    File.mkdir_p!(Path.join(root, "ebin"))
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)

    paths =
      :code.get_path()
      |> Enum.reject(&(&1 == ~c"."))
      |> Enum.flat_map(&["-pa", List.to_string(&1)])

    {out, status} =
      System.cmd(
        System.find_executable("elixirc"),
        ["--erl", "+S 2:2"] ++
          paths ++ ["-o", Path.join(root, "ebin"), "test/support/share_host_worker.exs"],
        stderr_to_stdout: true
      )

    assert status == 0, out
    File.write!(Path.join(root, "LICENSE"), "Apache-2.0 synthetic fixture")

    descriptor = %{
      "id" => "share",
      "description" => "Synthetic Session share action",
      "arguments_schema" => %{"type" => "object"},
      "result_schema" => %{"type" => "object"}
    }

    exports = Catalog.empty() |> Map.put("commands", [descriptor])
    capabilities = ~w(invoke.command host.actions host.context)

    files =
      for path <- ["LICENSE", "ebin/Elixir.IpseTest.ShareHostWorker.beam"] do
        bytes = File.read!(Path.join(root, path))
        %{"path" => path, "bytes" => byte_size(bytes), "sha256" => JSON.sha256(bytes)}
      end

    manifest = %{
      "format" => 1,
      "id" => "fixture/share-host",
      "version" => "0.1.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => "IpseTest.ShareHostWorker",
      "license_file" => "LICENSE",
      "files" => files,
      "capabilities" => capabilities,
      "exports" => exports,
      "options_schema" => %{"type" => "object"},
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      }
    }

    File.write!(Path.join(root, "extension.json"), Jason.encode!(manifest))

    if evidence = System.get_env("IPSE_SHARE_HOST_ARTIFACT_EVIDENCE") do
      refute File.exists?(evidence)
      assert {:ok, _} = File.cp_r(root, evidence)
    end

    %{artifact: root, capabilities: capabilities}
  end

  setup c do
    root = Path.join(System.tmp_dir!(), "ipse-share-host-" <> Usage.id())

    bound_fixture =
      if System.get_env("IPSE_BOUND_HOST_SAME_PROJECT") == "1",
        do: System.fetch_env!("IPSE_BOUND_HOST_FIXTURE") |> File.read!() |> Jason.decode!()

    home = if bound_fixture, do: bound_fixture["home"], else: Path.join(root, "home")
    cwd = if bound_fixture, do: bound_fixture["cwd"], else: Path.join(root, "cwd")
    File.mkdir_p!(home)
    File.mkdir_p!(cwd)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, artifact} = Artifact.import(c.artifact, Path.join(home, "extensions/artifacts"))

    data = %{
      "extensions" => [
        %{
          "instance" => "fixture",
          "artifact" => artifact.digest,
          "enabled" => true,
          "options" => %{},
          "order" => 0,
          "lifetime" => "session"
        }
      ],
      "extension_trust" => [
        %{
          "artifact" => artifact.digest,
          "capabilities" => c.capabilities,
          "allow_project" => false,
          "allow_children" => false
        }
      ]
    }

    {:ok, selected} = Config.resolve([%{scope: "operator", path: "/fixture", data: data}], [])
    assert Artifact.compatible?(artifact.manifest)
    assert {:ok, _} = Registry.lookup(Path.join(home, "extensions/artifacts"), artifact.digest)
    {:ok, entries} = Registry.prepare(selected, home)
    assert Registry.valid_identity?(hd(entries).identity)

    config = %{
      provider: :demo,
      model: if(bound_fixture, do: "scripted", else: "fixture"),
      home: home,
      extensions: entries,
      approval: :deny
    }

    config =
      if bound_fixture do
        config_path = Path.join(home, "bound-host-config.json")

        File.write!(
          config_path,
          Jason.encode!(
            Map.merge(data, %{
              "version" => 1,
              "settings" => %{"provider" => "demo", "model" => "scripted"}
            })
          )
        )

        File.chmod!(config_path, 0o600)
        System.put_env("IPSE_HOME", home)

        assert 0 ==
                 Ipse.CLI.run([
                   "knowledge",
                   "enable",
                   "--cwd",
                   cwd,
                   "--config",
                   config_path,
                   "--no-project-config"
                 ])

        {:ok, snapshot} =
          Ipse.Extension.Consent.existing_snapshot(
            Ipse.Extension.SemanticAdmission.control_root(home),
            bound_fixture["project"]
          )

        bound_fixture =
          Map.merge(bound_fixture, %{
            "current_epoch" => snapshot["epoch"],
            "current_policy_sha256" => JSON.digest([snapshot["policy"]])
          })

        File.write!(System.fetch_env!("IPSE_BOUND_HOST_FIXTURE"), Jason.encode!(bound_fixture))

        {:ok, effective} =
          Ipse.Config.resolve(cwd, home, [config: config_path, project_config: false], %{})

        client = %{
          workspace: cwd,
          home: home,
          auth_dir: Path.join(home, "auth"),
          operator_home: root,
          mcp_config: nil,
          base_url: nil,
          operator_questions: true,
          accept_edits: false,
          approval: :ask,
          approval_origin: :interactive,
          headless: false
        }

        {:ok, config} = Ipse.Config.runtime(effective, client)
        policy = snapshot["policy"]
        {:ok, overlay} = Ipse.Extension.Activation.derive(policy, config.base_extension_catalog)
        {:ok, activated} = Registry.prepare(overlay.catalog, home)
        knowledge = Enum.find(activated, &(&1.identity["instance"] == "knowledge"))
        assert JSON.digest([knowledge.identity]) == policy["settings"]["identity_sha256"]

        assert Enum.reject(activated, &(&1.identity["instance"] == "knowledge")) ===
                 config.extensions

        assert {:ok, selectors} =
                 Ipse.Extension.SemanticRoutes.selectors(policy["settings"]["routes"])

        assert {:ok, reviewed} =
                 Ipse.Extension.SemanticRoutes.review(
                   Map.put(config, :extensions, activated),
                   selectors
                 )

        assert reviewed.routes === policy["settings"]["routes"]
        config
      else
        config
      end

    opts = [config: config, cwd: cwd, state_dir: Path.join(home, "sessions"), subscriber: self()]
    {:ok, session} = Session.start_share_candidate_link(opts)
    Process.unlink(session)

    if bound_fixture do
      admission = :sys.get_state(session).config.semantic_admission
      assert admission["status"] == "active"
      assert admission["pin"]["project_id"] == bound_fixture["project"]
      current = System.fetch_env!("IPSE_BOUND_HOST_FIXTURE") |> File.read!() |> Jason.decode!()
      assert admission["pin"]["epoch"] == current["current_epoch"]
      assert admission["pin"]["policy_sha256"] == current["current_policy_sha256"]
    end

    on_exit(fn -> if Process.alive?(session), do: Process.exit(session, :kill) end)
    Process.register(self(), :ipse_share_host_fixture)

    reader =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> if Process.alive?(reader), do: Process.exit(reader, :kill) end)
    assert {:ok, _channel} = Session.open_input_channel(session, reader)

    on_exit(fn ->
      if Process.whereis(:ipse_share_host_fixture) == self(),
        do: Process.unregister(:ipse_share_host_fixture)
    end)

    if System.get_env("IPSE_SHARE_TTY_UNION") == "1" do
      assert :ok = Session.prompt(session, "Synthetic active Session source")
      assert_receive {:ipse, ^session, {:done, :ok}}, 10_000
    end

    assert :ok = Session.invoke_export(session, :command, "ext__fixture__share", %{})
    assert_receive {:host_ready, host, ^session, job, worker, intent}, 10_000
    assert Process.alive?(worker)
    assert :sys.get_state(session).invocation.action.intent == intent

    %{
      session: session,
      host: host,
      job: job,
      worker: worker,
      intent: intent,
      root: root,
      reader: reader
    }
  end

  test "actual Host, selected artifact and worker bind the sealed action and reject foreign controls",
       c do
    assert {:error, :session_share_refused} =
             GenServer.call(c.session, {:session_share_begin, c.job, c.intent})

    probe(
      c.host,
      {:begin, Map.put(c.intent, "operation_id", "wrong")},
      {:error, :session_share_refused}
    )

    send(c.host, {:probe, {:begin, c.intent}})
    assert_receive {:probe_result, {:begin, _}, {:ok, cap, _transport, snapshot}}, 5_000
    assert snapshot.job_ref == c.job

    assert {:error, :session_share_frozen} =
             GenServer.call(c.session, {:managed_sources, c.job, nil, []})

    assert {:error, :session_share_frozen} =
             GenServer.call(c.session, {:session_share_abort, c.job, cap})

    probe(c.host, {:abort, cap}, :ok)
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  test "cancellation kills the real Host and worker while its Writer drain is suspended", c do
    writer = :sys.get_state(c.session).journal_writer
    :ok = :sys.suspend(writer)
    host_ref = Process.monitor(c.host)
    worker_ref = Process.monitor(c.worker)
    send(c.host, {:probe, {:begin, c.intent}})
    await_phase(c.session, :draining)
    assert {:error, :cleanup_unconfirmed} = Session.cancel(c.session)
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert_receive {:DOWN, ^worker_ref, :process, _, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    :ok = :sys.resume(writer)
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :share_late_reply
  test "a Writer reply after the setup deadline cannot arm the real Host", c do
    writer = :sys.get_state(c.session).journal_writer
    :ok = :sys.suspend(writer)
    host_ref = Process.monitor(c.host)
    send(c.host, {:probe, {:begin, c.intent}})
    await_phase(c.session, :draining)

    :sys.replace_state(c.session, fn s ->
      put_in(s, [:share_barrier, :deadline], System.monotonic_time(:millisecond) - 1)
    end)

    :ok = :sys.resume(writer)
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :native_sandbox
  @tag :host_share_positive
  test "real Host settles the native recipient before Writer and Session thaw", c do
    send(c.host, {:probe, {:begin, c.intent}})
    assert_receive {:probe_result, {:begin, _}, {:ok, cap, transport, _snapshot}}, 5_000
    state = :sys.get_state(c.session)
    helper = Path.join(to_string(:code.priv_dir(:ipse)), "ipse-runner")

    collector =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        args: ["--lease-collect-close-ready-v3"]
      ])

    {:os_pid, collector_pid} = Port.info(collector, :os_pid)
    {:os_pid, exporter_pid} = Port.info(state.lock, :os_pid)
    path = Path.join(state.dir, state.id <> ".lock")
    stat = File.stat!(path)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)

    entry =
      <<exporter_pid::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>

    init = <<10_000::64, transport::binary, 1, 0, entry::binary>>
    assert Port.command(collector, <<?I, byte_size(init)::32, init::binary>>)
    assert receive_frame(collector, ?H) == <<transport::binary, 1>>

    request =
      <<collector_pid::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>

    probe(c.host, {:export, cap, request}, :ok)
    assert receive_frame(collector, ?L) == <<transport::binary, 1>>
    assert {:error, _} = Runner.protected_lock(path)
    probe(c.host, {:finish, cap}, {:error, :session_share_frozen})

    assert {:error, :session_share_frozen} =
             GenServer.call(c.session, {:session_share_finish, c.job, cap})

    assert {:error, :session_share_frozen} =
             GenServer.call(c.session, {:session_sources, :snapshot, %{}})

    assert Port.command(collector, <<?C, transport::binary>>)
    probe(c.host, {:settle, cap}, :ok)
    assert receive_frame(collector, ?C) == <<transport::binary, 1>>
    assert_receive {^collector, {:exit_status, 0}}, 8_000
    probe(c.host, {:finish, cap}, :ok)
    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :native_sandbox
  @tag :host_share_lost
  test "post-transfer cancellation is unknown and recipient remains the last holder", c do
    send(c.host, {:probe, {:begin, c.intent}})
    assert_receive {:probe_result, {:begin, _}, {:ok, cap, transport, _snapshot}}, 5_000
    state = :sys.get_state(c.session)
    helper = Path.join(to_string(:code.priv_dir(:ipse)), "ipse-runner")

    collector =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        args: ["--lease-collect-close-ready-v3"]
      ])

    {:os_pid, collector_pid} = Port.info(collector, :os_pid)

    on_exit(fn ->
      if Port.info(collector), do: System.cmd("kill", ["-CONT", Integer.to_string(collector_pid)])
    end)

    {:os_pid, exporter_pid} = Port.info(state.lock, :os_pid)
    path = Path.join(state.dir, state.id <> ".lock")
    stat = File.stat!(path)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)

    entry =
      <<exporter_pid::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>

    init = <<10_000::64, transport::binary, 1, 0, entry::binary>>
    assert Port.command(collector, <<?I, byte_size(init)::32, init::binary>>)
    assert receive_frame(collector, ?H) == <<transport::binary, 1>>

    request =
      <<collector_pid::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>

    probe(c.host, {:export, cap, request}, :ok)
    assert receive_frame(collector, ?L) == <<transport::binary, 1>>
    assert {_, 0} = System.cmd("kill", ["-STOP", Integer.to_string(collector_pid)])
    host_ref = Process.monitor(c.host)
    assert {:error, :cleanup_unconfirmed} = Session.cancel(c.session)
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
    assert {:error, _} = Runner.protected_lock(path)
    assert {_, 0} = System.cmd("kill", ["-CONT", Integer.to_string(collector_pid)])
    assert_receive {^collector, {:exit_status, _}}, 8_000
    assert {:ok, contender} = Runner.protected_lock(path)
    assert :ok = Runner.unlock(contender)
  end

  @tag :native_sandbox
  @tag :host_share_wrong_inode
  test "wrong lock identity poisons the actual Host export", c do
    send(c.host, {:probe, {:begin, c.intent}})
    assert_receive {:probe_result, {:begin, _}, {:ok, cap, transport, _snapshot}}, 5_000
    state = :sys.get_state(c.session)
    helper = Path.join(to_string(:code.priv_dir(:ipse)), "ipse-runner")

    collector =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        args: ["--lease-collect-close-ready-v3"]
      ])

    {:os_pid, collector_pid} = Port.info(collector, :os_pid)
    {:os_pid, exporter_pid} = Port.info(state.lock, :os_pid)
    path = Path.join(state.dir, state.id <> ".lock")
    stat = File.stat!(path)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)

    entry =
      <<exporter_pid::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>

    init = <<10_000::64, transport::binary, 1, 0, entry::binary>>
    assert Port.command(collector, <<?I, byte_size(init)::32, init::binary>>)
    assert receive_frame(collector, ?H) == <<transport::binary, 1>>

    request =
      <<collector_pid::32, name::binary, secret::binary, stat.major_device::64,
        stat.inode + 1::64>>

    host_ref = Process.monitor(c.host)
    send(c.host, {:probe, {:export, cap, request}})
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
    assert_receive {^collector, {:exit_status, _}}, 8_000
  end

  @tag :native_sandbox
  @tag :owner_control_host
  test "cancellation closes a control Port owned by the actual Host task", c do
    send(c.host, {:probe, :open_owner_control})
    assert_receive {:probe_result, :open_owner_control, {:ok, port}}, 5_000
    assert Port.info(port, :connected) == {:connected, c.host}
    probe(c.host, {:await_owner_control, port}, :ok)
    {:os_pid, sender} = Port.info(port, :os_pid)
    info = File.stat!("/proc/#{sender}/fd/0")
    helper = Path.join(to_string(:code.priv_dir(:ipse)), "ipse-runner")

    observer =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        args: ["--owner-control-observe-v1"]
      ])

    assert receive_frame(observer, ?H) == "owner-observer-v1"
    {:os_pid, recipient} = Port.info(observer, :os_pid)
    operation = :crypto.strong_rand_bytes(16)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)
    entry = <<sender::32, name::binary, secret::binary, info.major_device::64, info.inode::64>>
    request = <<operation::binary, 2, entry::binary, 30_000::64>>
    assert Port.command(observer, <<?I, byte_size(request)::32, request::binary>>)

    assert {:error, :owner_control_unavailable} =
             Runner.send_owner_control(port, operation, :host, recipient, name, secret)

    probe(c.host, {:send_owner_control, port, operation, :host, recipient, name, secret}, :ok)
    assert receive_frame(observer, ?L) == <<operation::binary, 2>>
    host_ref = Process.monitor(c.host)
    assert :ok = Session.cancel(c.session)
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert receive_frame(observer, ?D) == <<operation::binary, 2>>
    assert_receive {^observer, {:exit_status, 0}}, 5_000
    assert Process.alive?(c.session)
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_partial
  test "real Session cancellation closes both owner Ports before suspended Writer drains", c do
    writer = :sys.get_state(c.session).journal_writer
    :ok = :sys.suspend(writer)
    send(c.host, {:probe, {:controlled_begin, c.intent}})
    await_phase(c.session, :draining)
    b = :sys.get_state(c.session).share_barrier
    assert b.controlled and Port.info(b.owner_port, :connected) == {:connected, c.session}
    assert Port.info(b.host_port, :connected) == {:connected, c.host}
    host_ref = Process.monitor(c.host)
    assert {:error, :cleanup_unconfirmed} = Session.cancel(c.session)
    assert Port.info(b.owner_port) == nil
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert Port.info(b.host_port) == nil
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    :ok = :sys.resume(writer)
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :controlled_timeout
  test "the original setup deadline closes both controls while Writer is suspended", c do
    writer = :sys.get_state(c.session).journal_writer
    :ok = :sys.suspend(writer)
    send(c.host, {:probe, {:controlled_begin, c.intent}})
    await_phase(c.session, :draining)
    b = :sys.get_state(c.session).share_barrier
    host_ref = Process.monitor(c.host)
    await_phase(c.session, :poisoned, 700)
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert Port.info(b.owner_port) == nil
    assert Port.info(b.host_port) == nil
    :ok = :sys.resume(writer)
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :controlled_client_loss
  test "loss of the bound actual input reader poisons both controls", c do
    send(c.host, {:probe, {:controlled_begin, c.intent}})

    assert_receive {:probe_result, {:controlled_begin, _},
                    {:ok, _cap, _transport, snapshot, controls}},
                   5_000

    assert snapshot.job_ref == c.job
    b = :sys.get_state(c.session).share_barrier
    assert controls.channel_id == b.channel.id
    host_ref = Process.monitor(c.host)
    Process.exit(c.reader, :kill)
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert Port.info(b.owner_port) == nil
    assert Port.info(b.host_port) == nil
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :controlled_stale
  test "altered helper preparation and its replay refuse before the seal", c do
    expected = {{:error, :session_share_refused}, {:error, :session_share_refused}}
    probe(c.host, {:stale_preparation, c.intent}, expected)
    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_abort
  test "the matching Host closes both controls before pre-export thaw", c do
    send(c.host, {:probe, {:controlled_begin, c.intent}})

    assert_receive {:probe_result, {:controlled_begin, _},
                    {:ok, cap, _transport, _snapshot, controls}},
                   5_000

    b = :sys.get_state(c.session).share_barrier
    probe(c.host, {:controlled_abort, cap, controls.host_port}, :ok)
    assert Port.info(b.owner_port) == nil
    assert Port.info(b.host_port) == nil
    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_bad_frame
  test "an out-of-order control frame poisons the bound operation", c do
    send(c.host, {:probe, {:controlled_begin, c.intent}})

    assert_receive {:probe_result, {:controlled_begin, _},
                    {:ok, _cap, _transport, _snapshot, controls}},
                   5_000

    b = :sys.get_state(c.session).share_barrier
    host_ref = Process.monitor(c.host)
    send(c.session, {b.owner_port, {:data, <<?T, 17::32, controls.operation::binary, 1>>}})
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert Port.info(b.owner_port) == nil
    assert Port.info(b.host_port) == nil
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :controlled_late_control
  test "a control frame processed after the setup deadline cannot report transfer", c do
    send(c.host, {:probe, {:controlled_begin, c.intent}})

    assert_receive {:probe_result, {:controlled_begin, _},
                    {:ok, _cap, _transport, _snapshot, controls}},
                   5_000

    b = :sys.get_state(c.session).share_barrier

    :sys.replace_state(c.session, fn s ->
      s
      |> put_in([:share_barrier, :deadline], System.monotonic_time(:millisecond) - 1)
      |> put_in([:share_barrier, :owner_phase], :bound)
    end)

    host_ref = Process.monitor(c.host)
    send(c.session, {b.owner_port, {:data, <<?T, 17::32, controls.operation::binary, 1>>}})
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    assert Port.info(b.owner_port) == nil
    assert Port.info(b.host_port) == nil
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :controlled_poison_sticky
  test "a delayed transfer frame cannot change a poisoned control", c do
    send(c.host, {:probe, {:controlled_begin, c.intent}})

    assert_receive {:probe_result, {:controlled_begin, _},
                    {:ok, _cap, _transport, _snapshot, controls}},
                   5_000

    :sys.replace_state(c.session, fn s -> put_in(s, [:share_barrier, :owner_phase], :bound) end)
    b = :sys.get_state(c.session).share_barrier
    assert {:error, :cleanup_unconfirmed} = Session.cancel(c.session)
    send(c.session, {b.owner_port, {:data, <<?T, 17::32, controls.operation::binary, 1>>}})
    poisoned = :sys.get_state(c.session).share_barrier
    assert poisoned.phase == :poisoned and poisoned.owner_phase == :bound
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :native_sandbox
  @tag :controlled_both_transfer
  test "actual Session cancellation closes both transferred controls before Writer drains", c do
    send(c.host, {:probe, {:controlled_begin, c.intent}})

    assert_receive {:probe_result, {:controlled_begin, _},
                    {:ok, cap, transport, _snapshot, controls}},
                   5_000

    {:os_pid, host_pid} = Port.info(controls.host_port, :os_pid)

    {session_observer, session_recipient, session_name, session_secret} =
      control_observer(controls.session_pid, controls.operation, 1)

    {host_observer, host_recipient, host_name, host_secret} =
      control_observer(host_pid, controls.operation, 2)

    assert {:error, :session_share_frozen} =
             GenServer.call(
               c.session,
               {:session_control_configure, c.job, cap, session_recipient, session_name,
                session_secret}
             )

    probe(c.host, {:configure_session, cap, session_recipient, session_name, session_secret}, :ok)

    probe(
      c.host,
      {:configure_host, controls.host_port, controls.operation, host_recipient, host_name,
       host_secret},
      :ok
    )

    assert receive_frame(session_observer, ?L) == <<controls.operation::binary, 1>>
    assert receive_frame(host_observer, ?L) == <<controls.operation::binary, 2>>
    await_control_phase(c.session, :transferred)
    state = :sys.get_state(c.session)
    assert state.share_barrier.owner_recipient == session_recipient
    path = Path.join(state.dir, state.id <> ".lock")
    stat = File.stat!(path)
    {:os_pid, exporter} = Port.info(state.lock, :os_pid)
    helper = Path.join(to_string(:code.priv_dir(:ipse)), "ipse-runner")

    collector =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        args: ["--lease-collect-close-ready-v3"]
      ])

    {:os_pid, collector_pid} = Port.info(collector, :os_pid)

    on_exit(fn ->
      if Port.info(collector), do: System.cmd("kill", ["-CONT", Integer.to_string(collector_pid)])
    end)

    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)
    entry = <<exporter::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>
    initial = <<10_000::64, transport::binary, 1, 0, entry::binary>>
    assert Port.command(collector, <<?I, byte_size(initial)::32, initial::binary>>)
    assert receive_frame(collector, ?H) == <<transport::binary, 1>>

    request =
      <<collector_pid::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>

    probe(c.host, {:export, cap, request}, :ok)
    assert receive_frame(collector, ?L) == <<transport::binary, 1>>
    assert {_, 0} = System.cmd("kill", ["-STOP", Integer.to_string(collector_pid)])
    writer = state.journal_writer
    :ok = :sys.suspend(writer)
    host_ref = Process.monitor(c.host)
    started = System.monotonic_time(:millisecond)
    assert {:error, :cleanup_unconfirmed} = Session.cancel(c.session)
    assert System.monotonic_time(:millisecond) - started < 1_000
    assert receive_frame(session_observer, ?D) == <<controls.operation::binary, 1>>
    assert receive_frame(host_observer, ?D) == <<controls.operation::binary, 2>>
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert_receive {^session_observer, {:exit_status, 0}}, 5_000
    assert_receive {^host_observer, {:exit_status, 0}}, 5_000
    :ok = :sys.resume(writer)
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
    assert {:error, _} = Runner.protected_lock(path)
    assert {_, 0} = System.cmd("kill", ["-CONT", Integer.to_string(collector_pid)])
    assert_receive {^collector, {:exit_status, _}}, 8_000
    assert {:ok, contender} = Runner.protected_lock(path)
    assert :ok = Runner.unlock(contender)
  end

  @tag :controlled_tty_bridge
  test "actual Session and Host own native synthetic tty controls and settle before thaw", c do
    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "tty-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    probe(c.host, {:synthetic_tty, paths}, :ok)
    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_bridge
  test "Session receives the fixed synthetic terminal notice before thaw", c do
    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "tty-notice-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    probe(c.host, {:synthetic_notice_tty, paths}, :ok)

    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_bridge
  @tag timeout: 20_000
  test "an actual final notice processed after Session expiry cannot thaw", c do
    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "tty-notice-expiry-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    test = self()

    trace = fn
      false, {:in, {port, {:data, <<?F, _::binary>>}}}, _ when is_port(port) ->
        send(test, :actual_final_notice_held)
        receive do: (:release_actual_final_notice -> :ok)
        true

      state, _, _ ->
        state
    end

    assert :ok = :sys.install(c.session, {trace, false})
    host_ref = Process.monitor(c.host)
    command = {:synthetic_notice_tty, paths}
    send(c.host, {:probe, command})
    assert_receive :actual_final_notice_held, 5_000
    Process.sleep(5_100)
    send(c.session, :release_actual_final_notice)
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_bridge
  @tag :controlled_notice_final_stop
  @tag timeout: 20_000
  @tag skip:
         if(System.get_env("IPSE_NOTICE_FINAL_HOOK_TEST") == "1",
           do: false,
           else: "isolated native test-hook helper required"
         )
  test "stopped native final notice cannot thaw Session after expiry", c do
    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "tty-notice-stop-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    host_ref = Process.monitor(c.host)
    command = {:synthetic_notice_tty, paths}
    send(c.host, {:probe, command})

    stopped =
      Enum.reduce_while(1..800, nil, fn _, _ ->
        barrier = :sys.get_state(c.session).share_barrier

        with %{phase: :terminal_closing, issued_terminal: %{pid: pid}} <- barrier,
             {:ok, status} <- File.read("/proc/#{pid}/status"),
             true <-
               Enum.any?(
                 String.split(status, "\n"),
                 &(String.starts_with?(&1, "State:") and String.contains?(&1, "stopped"))
               ) do
          {:halt, {pid, barrier.wall_deadline}}
        else
          _ ->
            Process.sleep(5)
            {:cont, nil}
        end
      end)

    assert {pid, deadline} = stopped

    on_exit(fn ->
      System.cmd("kill", ["-CONT", Integer.to_string(pid)], stderr_to_stdout: true)
    end)

    Process.sleep(max(deadline - System.system_time(:millisecond) + 50, 0))
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert {_, 0} = System.cmd("kill", ["-CONT", Integer.to_string(pid)], stderr_to_stdout: true)

    stopped =
      Enum.reduce_while(1..500, false, fn _, _ ->
        if File.exists?("/proc/#{pid}") do
          Process.sleep(10)
          {:cont, false}
        else
          {:halt, true}
        end
      end)

    assert stopped
    refute_receive {:probe_result, ^command, :ok}, 50
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)

    for path <- paths do
      acquired =
        Enum.reduce_while(1..150, nil, fn _, _ ->
          case Runner.protected_lock(path) do
            {:ok, lock} ->
              {:halt, lock}

            _ ->
              Process.sleep(10)
              {:cont, nil}
          end
        end)

      assert is_port(acquired)
      assert :ok = Runner.unlock(acquired)
    end
  end

  @tag :controlled_tty_bridge
  test "Session issues one fixed-mode synthetic terminal to its current Host", c do
    send(c.host, {:probe, {:controlled_begin, c.intent}})
    assert_receive {:probe_result, {:controlled_begin, _}, {:ok, cap, _, _, _}}, 5_000

    assert {:error, :session_share_frozen} =
             GenServer.call(c.session, {:session_share_spawn_synthetic_terminal, c.job, cap})

    send(c.host, {:probe, {:spawn_synthetic_terminal, cap}})
    assert_receive {:probe_result, {:spawn_synthetic_terminal, ^cap}, {:ok, port}}, 5_000
    assert Port.info(port, :connected) == {:connected, c.host}
    assert {:os_pid, pid} = Port.info(port, :os_pid)
    assert :sys.get_state(c.session).share_barrier.issued_terminal == %{port: port, pid: pid}

    command =
      Enum.reduce_while(1..200, "", fn _, _ ->
        case File.read("/proc/#{pid}/cmdline") do
          {:ok, command} ->
            if command =~ "v9-synthetic-notice-display" do
              {:halt, command}
            else
              Process.sleep(5)
              {:cont, command}
            end

          _ ->
            {:halt, ""}
        end
      end)

    assert command =~ "v9-synthetic-notice-display"
    probe(c.host, {:spawn_synthetic_terminal, cap}, {:error, :session_share_refused})
    monitor = :erlang.monitor(:port, port)
    assert {:error, :cleanup_unconfirmed} = Session.cancel(c.session)
    assert_receive {:DOWN, ^monitor, :port, ^port, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
  end

  @tag :controlled_tty_bridge
  test "Session loss stops its issued synthetic terminal", c do
    send(c.host, {:probe, {:controlled_begin, c.intent}})
    assert_receive {:probe_result, {:controlled_begin, _}, {:ok, cap, _, _, _}}, 5_000
    send(c.host, {:probe, {:spawn_synthetic_terminal, cap}})
    assert_receive {:probe_result, {:spawn_synthetic_terminal, ^cap}, {:ok, port}}, 5_000
    terminal_ref = :erlang.monitor(:port, port)
    host_ref = Process.monitor(c.host)
    session_ref = Process.monitor(c.session)
    Process.exit(c.session, :kill)
    assert_receive {:DOWN, ^session_ref, :process, _, :killed}, 5_000
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert_receive {:DOWN, ^terminal_ref, :port, ^port, _}, 5_000
  end

  @tag :controlled_tty_bridge
  test "synthetic close refuses before the Session receives its notice", c do
    send(c.host, {:probe, {:controlled_notice_begin, c.intent}})
    assert_receive {:probe_result, {:controlled_notice_begin, _}, {:ok, cap, _, _, _}}, 5_000
    send(c.host, {:probe, {:spawn_synthetic_terminal, cap}})
    assert_receive {:probe_result, {:spawn_synthetic_terminal, ^cap}, {:ok, port}}, 5_000
    assert {:os_pid, pid} = Port.info(port, :os_pid)

    :sys.replace_state(c.session, fn s ->
      update_in(
        s.share_barrier,
        &Map.merge(&1, %{phase: :settled, owner_phase: :transferred, owner_recipient: pid})
      )
    end)

    host_ref = Process.monitor(c.host)
    send(c.host, {:probe, {:prepare_terminal_close, cap, port}})
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
  end

  @tag :controlled_tty_bridge
  test "synthetic owner closure without the final notice poisons the share", c do
    send(c.host, {:probe, {:controlled_notice_begin, c.intent}})
    assert_receive {:probe_result, {:controlled_notice_begin, _}, {:ok, cap, _, _, _}}, 5_000
    send(c.host, {:probe, {:spawn_synthetic_terminal, cap}})
    assert_receive {:probe_result, {:spawn_synthetic_terminal, ^cap}, {:ok, _port}}, 5_000

    :sys.replace_state(c.session, fn s ->
      update_in(
        s.share_barrier,
        &Map.merge(&1, %{
          phase: :terminal_closing,
          owner_phase: :transferred,
          notice_received: true
        })
      )
    end)

    barrier = :sys.get_state(c.session).share_barrier
    host_ref = Process.monitor(c.host)
    send(c.session, {barrier.owner_port, {:exit_status, 0}})
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
  end

  @tag :controlled_tty_bridge
  test "Session refuses to spawn a synthetic terminal after its wall deadline", c do
    cutoff = System.system_time(:millisecond) + 3_000
    command = {:controlled_accepted_notice_begin, c.intent, cutoff}
    send(c.host, {:probe, command})
    assert_receive {:probe_result, ^command, {:ok, cap, _, _, _}}, 5_000
    barrier = :sys.get_state(c.session).share_barrier
    assert barrier.wall_deadline == cutoff
    Process.sleep(max(cutoff - System.system_time(:millisecond) + 25, 0))
    assert System.monotonic_time(:millisecond) < barrier.deadline

    send(c.host, {:probe, {:spawn_synthetic_terminal, cap}})

    assert_receive {:probe_result, {:spawn_synthetic_terminal, ^cap},
                    {:error, :session_share_refused}},
                   5_000

    refute Map.has_key?(:sys.get_state(c.session).share_barrier, :issued_terminal)
  end

  @tag :controlled_tty_bridge
  test "Session rejects a final notice after the synthetic wall deadline", c do
    send(c.host, {:probe, {:controlled_notice_begin, c.intent}})

    assert_receive {:probe_result, {:controlled_notice_begin, _}, {:ok, cap, _, _, controls}},
                   5_000

    send(c.host, {:probe, {:spawn_synthetic_terminal, cap}})
    assert_receive {:probe_result, {:spawn_synthetic_terminal, ^cap}, {:ok, _port}}, 5_000

    :sys.replace_state(c.session, fn s ->
      update_in(s.share_barrier, fn b ->
        Map.merge(b, %{
          phase: :terminal_closing,
          owner_phase: :transferred,
          notice_received: true,
          wall_deadline: System.system_time(:millisecond) - 1
        })
      end)
    end)

    barrier = :sys.get_state(c.session).share_barrier
    host_ref = Process.monitor(c.host)
    send(c.session, {barrier.owner_port, {:data, <<?F, 17::32, controls.operation::binary, 1>>}})
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
  end

  @tag :controlled_tty_bridge
  test "Session rejects a synthetic notice with a different wall deadline", c do
    send(c.host, {:probe, {:controlled_notice_begin, c.intent}})

    assert_receive {:probe_result, {:controlled_notice_begin, _}, {:ok, cap, _, _, controls}},
                   5_000

    send(c.host, {:probe, {:spawn_synthetic_terminal, cap}})
    assert_receive {:probe_result, {:spawn_synthetic_terminal, ^cap}, {:ok, port}}, 5_000
    assert {:os_pid, pid} = Port.info(port, :os_pid)

    :sys.replace_state(c.session, fn s ->
      update_in(
        s.share_barrier,
        &Map.merge(&1, %{phase: :settled, owner_phase: :transferred, owner_recipient: pid})
      )
    end)

    barrier = :sys.get_state(c.session).share_barrier
    host_ref = Process.monitor(c.host)
    forged = <<?N, 25::32, controls.operation::binary, 1, controls.wall_deadline + 1::64>>
    send(c.session, {barrier.owner_port, {:data, forged}})
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
  end

  @tag :controlled_tty_bridge
  test "synthetic share cannot thaw directly from settled", c do
    send(c.host, {:probe, {:controlled_notice_begin, c.intent}})
    assert_receive {:probe_result, {:controlled_notice_begin, _}, {:ok, cap, _, _, _}}, 5_000
    send(c.host, {:probe, {:spawn_synthetic_terminal, cap}})
    assert_receive {:probe_result, {:spawn_synthetic_terminal, ^cap}, {:ok, _port}}, 5_000
    :sys.replace_state(c.session, fn s -> put_in(s, [:share_barrier, :phase], :settled) end)
    host_ref = Process.monitor(c.host)
    send(c.host, {:probe, {:finish, cap}})
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
  end

  @tag :controlled_tty_bridge
  test "synthetic share cannot thaw while its issued terminal Port is alive", c do
    send(c.host, {:probe, {:controlled_notice_begin, c.intent}})

    assert_receive {:probe_result, {:controlled_notice_begin, _}, {:ok, cap, _, _, controls}},
                   5_000

    send(c.host, {:probe, {:spawn_synthetic_terminal, cap}})
    assert_receive {:probe_result, {:spawn_synthetic_terminal, ^cap}, {:ok, port}}, 5_000
    probe(c.host, {:close_host_control, controls.host_port}, :ok)

    :sys.replace_state(c.session, fn s ->
      Port.close(s.share_barrier.owner_port)
      update_in(s.share_barrier, &Map.merge(&1, %{phase: :terminal_closed, owner_phase: :closed}))
    end)

    assert Port.info(port) != nil
    host_ref = Process.monitor(c.host)
    send(c.host, {:probe, {:finish, cap}})
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
  end

  @tag :controlled_tty_bridge
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_SIX") == "1",
           do: false,
           else: "six-lease helper required"
         )
  test "actual Session and Host settle a six-lease synthetic terminal display", c do
    paths =
      for n <- 1..5 do
        dir = Path.join(c.root, "tty-six-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    probe(c.host, {:synthetic_tty_six, paths}, :ok)
    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  test "Writer control loss before native switch preserves the old root", c do
    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "session-switch-loss-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    host_ref = Process.monitor(c.host)
    send(c.host, {:probe, {:session_transaction_hold, paths}})
    assert_receive {:session_switch_ready, _, root}, 5_000
    writer = :sys.get_state(c.session).journal_writer
    control = :sys.get_state(writer).share_barrier.writer_control
    assert {_, 0} = System.cmd("/bin/kill", ["-KILL", Integer.to_string(control.pid)])
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert File.read!(Path.join(root, "root.json")) == "old"
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  test "Session loss before native switch preserves the old root", c do
    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "session-switch-owner-loss-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    host_ref = Process.monitor(c.host)
    session_ref = Process.monitor(c.session)
    send(c.host, {:probe, {:session_transaction_hold, paths}})
    assert_receive {:session_switch_ready, _, root}, 5_000
    Process.exit(c.session, :kill)
    assert_receive {:DOWN, ^session_ref, :process, _, _}, 5_000
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert File.read!(Path.join(root, "root.json")) == "old"
  end

  test "different Session and Writer recipients cannot enter the switch", c do
    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "session-switch-recipient-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    host_ref = Process.monitor(c.host)
    send(c.host, {:probe, {:session_transaction_wrong_recipient, paths}})
    assert_receive {:session_switch_ready, _, root}, 5_000
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert File.read!(Path.join(root, "root.json")) == "old"
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_group
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_GROUP") == "1",
           do: false,
           else: "group helper required"
         )
  test "active Session and two original sources share a synthetic terminal", c do
    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "group-tty-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    {context, proofs} = synthetic_original_sources(c, 2)
    probe(c.host, {:synthetic_group_tty, paths, context, proofs}, :ok)
    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_group
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_GROUP") == "1",
           do: false,
           else: "group helper required"
         )
  test "active Session thaws its writer before synthetic grouped review input", c do
    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "group-review-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    {context, proofs} = synthetic_original_sources(c, 2)
    probe(c.host, {:synthetic_review_tty, paths, context, proofs}, :ok)
    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_group
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_GROUP") == "1",
           do: false,
           else: "group helper required"
         )
  test "swapped original-source leases refuse before Session review", c do
    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "review-swapped-source-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    {context, proofs} = synthetic_original_sources(c, 2)

    probe(
      c.host,
      {:synthetic_review_swapped, paths, context, proofs},
      {:error, :cleanup_unconfirmed}
    )

    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_group
  @tag skip:
         if(System.get_env("IPSE_REVIEW_MANIFEST_INJECT") == "1",
           do: false,
           else: "instrumented review manifest required"
         )
  test "injected initial review text cannot reach the terminal", c do
    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "review-injection-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    {context, proofs} = synthetic_original_sources(c, 2)
    host_ref = Process.monitor(c.host)
    command = {:synthetic_review_tty, paths, context, proofs}
    send(c.host, {:probe, command})
    assert_receive :review_manifest_injected, 5_000

    receive do
      {:probe_result, ^command, {:error, _}} ->
        assert :sys.get_state(c.session).share_barrier == nil
        send(c.host, :continue)
        assert_receive {:ipse, _, {:done, :error}}, 10_000
        assert Session.close_confirmed(c.session) in [:ok, {:error, :cleanup_unconfirmed}]

      {:DOWN, ^host_ref, :process, _, _} ->
        assert :sys.get_state(c.session).share_barrier.phase == :poisoned
        assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
    after
      7_000 -> flunk("injected review did not refuse")
    end
  end

  @tag :controlled_tty_bridge
  test "Session refuses a malformed review manifest before handing off control", c do
    send(c.host, {:probe, {:controlled_review_begin, c.intent}})
    assert_receive {:probe_result, {:controlled_review_begin, _}, {:ok, cap, _, _, _}}, 5_000
    send(c.host, {:probe, {:spawn_synthetic_terminal, cap}})
    assert_receive {:probe_result, {:spawn_synthetic_terminal, ^cap}, {:ok, _}}, 5_000
    host_ref = Process.monitor(c.host)
    send(c.host, {:probe, {:review_manifest, cap, <<0, 1, 2>>}})
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  test "Session and Writer controls fence a native root switch", c do
    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "session-switch-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    probe(c.host, {:session_transaction, paths}, :ok)
    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  test "a Session without a recorded relation cannot open its source fence", c do
    sha = JSON.sha256("unrelated relation")

    assert {:error, :session_share_refused} =
             GenServer.call(
               c.session,
               {:session_control_ticket_supersession, c.job, c.intent, sha}
             )

    probe(c.host, {:supersession_source_begin, sha}, {:error, :owner_control_unavailable})

    assert {:error, :session_share_refused} =
             GenServer.call(
               c.session,
               {:session_control_ticket_supersession_display_fixture, c.job, c.intent, sha}
             )

    probe(c.host, {:supersession_display_begin, sha}, {:error, :owner_control_unavailable})
    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_union
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_UNION") == "1",
           do: false,
           else: "active source fixture required"
         )
  @tag :supersession_ticket_positive
  test "a recorded synthetic relation binds an actual active source to the review ticket", c do
    {candidate, prepared, event, proof, sha} = synthetic_recorded_relation(c)

    :sys.replace_state(c.session, fn s ->
      s =
        put_in(s.config[:managed_supersession_layout], Ipse.Session.ManagedSupersession.layout())

      s = put_in(s.invocation.action.intent, candidate)

      Map.put(s, :managed_supersession, %{
        prepared: prepared,
        candidate: candidate,
        proof: proof,
        source: %{},
        records: [],
        token: nil
      })
    end)

    probe(c.host, {:supersession_record_fixture, sha, event}, :ok)
    state = :sys.get_state(c.session)
    assert state.managed_supersession.records == [event]
    assert {:ok, events} = Ipse.Journal.load(state.dir, state.id)
    assert event in events

    command = {:supersession_display_fixture, candidate, sha}
    send(c.host, {:probe, command})

    assert_receive {:probe_result, ^command, {:ok, cap, _transport, snapshot, controls}}, 5_000
    assert Enum.map(snapshot.verified_sources, & &1["proof"]) == [proof]

    assert :sys.get_state(c.session).share_barrier.relation_display_facts_sha256 ==
             JSON.digest([event["facts"]])

    probe(c.host, {:controlled_abort, cap, controls.host_port}, :ok)
    assert :sys.get_state(c.session).share_barrier == nil
  end

  @tag :controlled_tty_union
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_UNION") == "1",
           do: false,
           else: "active source fixture required"
         )
  @tag :supersession_ticket_terminal
  test "a recorded synthetic relation reaches fixed-text review with the active source retained",
       c do
    {candidate, prepared, event, proof, sha} = synthetic_recorded_relation(c)

    :sys.replace_state(c.session, fn s ->
      s =
        put_in(s.config[:managed_supersession_layout], Ipse.Session.ManagedSupersession.layout())

      s = put_in(s.invocation.action.intent, candidate)

      Map.put(s, :managed_supersession, %{
        prepared: prepared,
        candidate: candidate,
        proof: proof,
        source: %{},
        records: [],
        token: nil
      })
    end)

    probe(c.host, {:supersession_record_fixture, sha, event}, :ok)

    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "recorded-review-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    {context, _inactive} = synthetic_original_sources(c, 1)

    context =
      context
      |> Map.put(:owner, c.session)
      |> Map.put(:job_ref, c.job)
      |> Map.put(:source_binding, {:supersession, sha})

    probe(
      c.host,
      {:synthetic_supersession_positive, paths, context, [proof], candidate, sha},
      :ok
    )

    assert :sys.get_state(c.session).share_barrier == nil

    assert {:ok, events} =
             Ipse.Journal.load(:sys.get_state(c.session).dir, prepared["session_id"])

    assert event in events
  end

  @tag :controlled_tty_union
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_UNION") == "1",
           do: false,
           else: "active source fixture required"
         )
  @tag :supersession_ticket_terminal
  test "recorded synthetic relation retains active and original sources through review", c do
    {context, [inactive]} = synthetic_original_sources(c, 1, :session)
    {candidate, prepared, event, proof, sha} = synthetic_recorded_relation(c, inactive)

    :sys.replace_state(c.session, fn s ->
      s =
        put_in(s.config[:managed_supersession_layout], Ipse.Session.ManagedSupersession.layout())

      s = put_in(s.invocation.action.intent, candidate)

      Map.put(s, :managed_supersession, %{
        prepared: prepared,
        candidate: candidate,
        proof: proof,
        source: %{},
        records: [],
        token: nil
      })
    end)

    probe(c.host, {:supersession_record_fixture, sha, event}, :ok)

    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "recorded-union-review-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    context =
      context
      |> Map.put(:owner, c.session)
      |> Map.put(:job_ref, c.job)
      |> Map.put(:source_binding, {:supersession, sha})

    probe(
      c.host,
      {:synthetic_supersession_positive, paths, context, [inactive, proof], candidate, sha},
      :ok
    )

    assert :sys.get_state(c.session).share_barrier == nil

    assert {:ok, events} =
             Ipse.Journal.load(:sys.get_state(c.session).dir, prepared["session_id"])

    assert event in events
  end

  @tag :controlled_tty_union
  @tag :supersession_missing_owner
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_UNION") == "1",
           do: false,
           else: "active source fixture required"
         )
  test "a recorded relation cannot omit its inactive source from synthetic review", c do
    {context, [inactive]} = synthetic_original_sources(c, 1, :session)
    {candidate, prepared, event, proof, sha} = synthetic_recorded_relation(c, inactive)

    :sys.replace_state(c.session, fn s ->
      s =
        put_in(s.config[:managed_supersession_layout], Ipse.Session.ManagedSupersession.layout())

      s = put_in(s.invocation.action.intent, candidate)

      Map.put(s, :managed_supersession, %{
        prepared: prepared,
        candidate: candidate,
        proof: proof,
        source: %{},
        records: [],
        token: nil
      })
    end)

    probe(c.host, {:supersession_record_fixture, sha, event}, :ok)

    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "recorded-missing-owner-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    context =
      context
      |> Map.put(:owner, c.session)
      |> Map.put(:job_ref, c.job)
      |> Map.put(:source_binding, {:supersession, sha})

    command = {:synthetic_supersession_omit, paths, context, [inactive, proof], candidate, sha}
    host_ref = Process.monitor(c.host)
    send(c.host, {:probe, command})

    receive do
      {:probe_result, ^command, {:error, _}} -> :ok
      {:probe_result, ^command, :ok} -> flunk("review accepted a missing original source owner")
      {:DOWN, ^host_ref, :process, _, _} -> :ok
    after
      10_000 -> flunk("missing source owner did not refuse")
    end

    if System.get_env("IPSE_TEST_SUPERSESSION_MANIFEST_COUNT") == "1" do
      assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    end
  end

  @tag :controlled_tty_union
  @tag :supersession_wrong_owner
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_UNION") == "1",
           do: false,
           else: "active source fixture required"
         )
  test "a recorded relation cannot substitute a different original source owner", c do
    {context, [inactive, other]} = synthetic_original_sources(c, 2, :session)
    {candidate, prepared, event, proof, sha} = synthetic_recorded_relation(c, inactive)

    :sys.replace_state(c.session, fn s ->
      s =
        put_in(s.config[:managed_supersession_layout], Ipse.Session.ManagedSupersession.layout())

      s = put_in(s.invocation.action.intent, candidate)

      Map.put(s, :managed_supersession, %{
        prepared: prepared,
        candidate: candidate,
        proof: proof,
        source: %{},
        records: [],
        token: nil
      })
    end)

    probe(c.host, {:supersession_record_fixture, sha, event}, :ok)

    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "recorded-wrong-owner-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    context =
      context
      |> Map.put(:owner, c.session)
      |> Map.put(:job_ref, c.job)
      |> Map.put(:source_binding, {:supersession, sha})

    command = {:synthetic_supersession_positive, paths, context, [other, proof], candidate, sha}
    host_ref = Process.monitor(c.host)
    send(c.host, {:probe, command})

    receive do
      {:probe_result, ^command, {:error, _}} -> :ok
      {:probe_result, ^command, :ok} -> flunk("review accepted a different source owner")
      {:DOWN, ^host_ref, :process, _, _} -> :ok
    after
      10_000 -> flunk("wrong source owner did not refuse")
    end

    if System.get_env("IPSE_TEST_SUPERSESSION_MANIFEST_COUNT") == "1" do
      assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    end
  end

  @tag :controlled_tty_union
  @tag :supersession_coordinated_terminal
  @tag skip:
         if(
           System.get_env("IPSE_SHARE_TTY_UNION") == "1" and
             System.get_env("IPSE_SHARE_COORDINATED_REVIEW") == "1",
           do: false,
           else: "coordinated review fixture required"
         )
  test "tracked publisher and Host retain recorded synthetic source union through review", c do
    {context, [inactive]} = synthetic_original_sources(c, 1, :session)
    {candidate, prepared, event, proof, sha} = synthetic_recorded_relation(c, inactive)

    :sys.replace_state(c.session, fn s ->
      s =
        put_in(s.config[:managed_supersession_layout], Ipse.Session.ManagedSupersession.layout())

      s = put_in(s.invocation.action.intent, candidate)

      Map.put(s, :managed_supersession, %{
        prepared: prepared,
        candidate: candidate,
        proof: proof,
        source: %{},
        records: [],
        token: nil
      })
    end)

    probe(c.host, {:supersession_record_fixture, sha, event}, :ok)

    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "coordinated-recorded-review-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    context =
      context
      |> Map.put(:owner, c.session)
      |> Map.put(:job_ref, c.job)
      |> Map.put(:source_binding, {:supersession, sha})

    probe(
      c.host,
      {:coordinated_supersession_review, paths, context, [inactive, proof], candidate, sha},
      :ok
    )

    assert_receive {:coordinated_review_owners, host, publisher}, 5_000
    assert host == c.host and host != publisher
    assert :sys.get_state(c.session).share_barrier == nil
  end

  for loss <- [:publisher, :source] do
    @tag :controlled_tty_union
    @tag :supersession_coordinated_loss
    @tag coordinated_owner_loss: loss
    @tag skip:
           if(
             System.get_env("IPSE_SHARE_TTY_UNION") == "1" and
               System.get_env("IPSE_SHARE_COORDINATED_REVIEW") == "1" and
               System.get_env("IPSE_SHARE_COORDINATED_LOSS") == "1",
             do: false,
             else: "coordinated loss fixture required"
           )
    test "coordinated synthetic review refuses #{loss} loss before display", c do
      {context, [inactive]} = synthetic_original_sources(c, 1, :session)
      {candidate, prepared, event, proof, sha} = synthetic_recorded_relation(c, inactive)

      :sys.replace_state(c.session, fn s ->
        s =
          put_in(
            s.config[:managed_supersession_layout],
            Ipse.Session.ManagedSupersession.layout()
          )

        s = put_in(s.invocation.action.intent, candidate)

        Map.put(s, :managed_supersession, %{
          prepared: prepared,
          candidate: candidate,
          proof: proof,
          source: %{},
          records: [],
          token: nil
        })
      end)

      probe(c.host, {:supersession_record_fixture, sha, event}, :ok)

      paths =
        for n <- 1..3 do
          dir = Path.join(c.root, "coordinated-loss-#{n}")
          File.mkdir!(dir)
          File.chmod!(dir, 0o700)
          Path.join(dir, ".lock")
        end

      context =
        context
        |> Map.put(:owner, c.session)
        |> Map.put(:job_ref, c.job)
        |> Map.put(:source_binding, {:supersession, sha})

      command =
        {:coordinated_supersession_review, paths, context, [inactive, proof], candidate, sha}

      host_ref = Process.monitor(c.host)
      send(c.host, {:probe, command})
      assert_receive {:coordinated_review_owners, host, publisher}, 5_000
      assert host == c.host and host != publisher
      assert_receive {:tty_group_paused, ^publisher, session, _port, _, _, [{_, original}]}, 5_000
      assert session == c.session

      if unquote(loss) == :publisher do
        Process.exit(publisher, :kill)
      else
        assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(original.pid)])
        send(publisher, :tty_continue)
      end

      receive do
        {:probe_result, ^command, {:error, _}} -> :ok
        {:DOWN, ^host_ref, :process, _, _} -> :ok
      after
        10_000 -> flunk("coordinated owner loss did not refuse")
      end
    end
  end

  for loss <- [:publisher, :source] do
    @tag :controlled_tty_union
    @tag :supersession_coordinated_input_loss
    @tag coordinated_input_loss: Atom.to_string(loss)
    @tag timeout: 30_000
    @tag skip:
           if(
             System.get_env("IPSE_SHARE_TTY_UNION") == "1" and
               System.get_env("IPSE_SHARE_COORDINATED_REVIEW") == "1" and
               System.get_env("IPSE_SHARE_COORDINATED_INPUT_LOSS") == "1",
             do: false,
             else: "coordinated held-input fixture required"
           )
    test "coordinated synthetic review refuses #{loss} loss while awaiting input", c do
      signal_dir = System.fetch_env!("IPSE_REVIEW_TEST_SIGNAL_DIR")
      File.rm(Path.join(signal_dir, "release"))
      {context, [inactive]} = synthetic_original_sources(c, 1, :session)
      {candidate, prepared, event, proof, sha} = synthetic_recorded_relation(c, inactive)

      :sys.replace_state(c.session, fn s ->
        s =
          put_in(
            s.config[:managed_supersession_layout],
            Ipse.Session.ManagedSupersession.layout()
          )

        s = put_in(s.invocation.action.intent, candidate)

        Map.put(s, :managed_supersession, %{
          prepared: prepared,
          candidate: candidate,
          proof: proof,
          source: %{},
          records: [],
          token: nil
        })
      end)

      probe(c.host, {:supersession_record_fixture, sha, event}, :ok)

      paths =
        for n <- 1..3 do
          dir = Path.join(c.root, "coordinated-input-loss-#{n}")
          File.mkdir!(dir)
          File.chmod!(dir, 0o700)
          Path.join(dir, ".lock")
        end

      context =
        context
        |> Map.put(:owner, c.session)
        |> Map.put(:job_ref, c.job)
        |> Map.put(:source_binding, {:supersession, sha})

      command =
        {:coordinated_supersession_review, paths, context, [inactive, proof], candidate, sha}

      host_ref = Process.monitor(c.host)
      send(c.host, {:probe, command})
      assert_receive {:coordinated_review_owners, host, publisher}, 5_000
      assert host == c.host and host != publisher
      assert_receive {:coordinated_review_source, ^publisher, source_pid}, 5_000
      session_ref = Process.monitor(c.session)
      await_phase(c.session, :review_input)
      assert :sys.get_state(:sys.get_state(c.session).journal_writer).share_barrier == nil

      if unquote(loss) == :publisher,
        do: Process.exit(publisher, :kill),
        else: assert({_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(source_pid)]))

      File.write!(Path.join(signal_dir, "release"), "release")

      outcome =
        receive do
          {:probe_result, ^command, {:error, _} = error} -> error
          {:DOWN, ^host_ref, :process, _, _} -> :host_down
        after
          10_000 ->
            state = :sys.get_state(c.session)

            flunk(
              "coordinated held-input owner loss did not refuse: " <>
                inspect(%{
                  barrier: state.share_barrier && state.share_barrier.phase,
                  owner_phase: state.share_barrier && state.share_barrier.owner_phase,
                  terminal:
                    state.share_barrier && Port.info(state.share_barrier.issued_terminal.port),
                  host: Process.info(c.host, [:current_function, :message_queue_len]),
                  publisher: Process.info(publisher, [:current_function, :message_queue_len]),
                  publisher_messages:
                    case Process.info(publisher, :messages) do
                      {:messages, messages} ->
                        Enum.map(messages, fn message ->
                          case message do
                            {port, tag} when is_port(port) ->
                              {:port, port, if(is_tuple(tag), do: elem(tag, 0), else: tag)}

                            tuple when is_tuple(tuple) ->
                              {:tuple, elem(tuple, 0)}

                            other ->
                              other
                          end
                        end)

                      _ ->
                        nil
                    end
                })
            )
        end

      if unquote(loss) == :publisher do
        assert outcome == :host_down or match?({:error, _}, outcome)
        assert :sys.get_state(c.session).share_barrier.phase == :poisoned
        assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
      else
        assert outcome == {:error, :collection_source_refused}
        assert_receive {:DOWN, ^session_ref, :process, _, _}, 5_000
      end
    end
  end

  @tag :controlled_tty_union
  @tag :supersession_lock_path_replaced
  @tag skip:
         if(
           System.get_env("IPSE_SHARE_TTY_UNION") == "1" and
             System.get_env("IPSE_SHARE_TTY_GROUP_LOSS") == "1",
           do: false,
           else: "instrumented source-path review required"
         )
  test "synthetic review refuses a replaced original lock path after display", c do
    {context, [inactive]} = synthetic_original_sources(c, 1, :session)
    {candidate, prepared, event, proof, sha} = synthetic_recorded_relation(c, inactive)

    :sys.replace_state(c.session, fn s ->
      s =
        put_in(s.config[:managed_supersession_layout], Ipse.Session.ManagedSupersession.layout())

      s = put_in(s.invocation.action.intent, candidate)

      Map.put(s, :managed_supersession, %{
        prepared: prepared,
        candidate: candidate,
        proof: proof,
        source: %{},
        records: [],
        token: nil
      })
    end)

    probe(c.host, {:supersession_record_fixture, sha, event}, :ok)

    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "replaced-source-lock-review-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    context =
      context
      |> Map.put(:owner, c.session)
      |> Map.put(:job_ref, c.job)
      |> Map.put(:source_binding, {:supersession, sha})

    command =
      {:synthetic_supersession_positive, paths, context, [inactive, proof], candidate, sha}

    host_ref = Process.monitor(c.host)
    send(c.host, {:probe, command})
    assert_receive {:tty_group_paused, host, session, _port, _, _, [{_, _}]}, 5_000
    assert host == c.host and session == c.session
    lock_path = Path.join(context.history_dir, inactive["session_id"] <> ".lock")
    File.rename!(lock_path, lock_path <> ".displaced")
    File.write!(lock_path, "")
    File.chmod!(lock_path, 0o600)
    assert {:ok, contender} = Ipse.Runner.lock_source(lock_path)
    send(host, :tty_continue)

    receive do
      {:probe_result, ^command, {:error, _}} -> :ok
      {:DOWN, ^host_ref, :process, _, _} -> :ok
    after
      10_000 -> flunk("replaced original lock path did not refuse synthetic review")
    end

    assert :ok = Ipse.Runner.unlock(contender)
  end

  @tag :controlled_tty_union
  @tag :supersession_ticket_terminal_loss
  @tag skip:
         if(
           System.get_env("IPSE_SHARE_TTY_UNION") == "1" and
             System.get_env("IPSE_SHARE_TTY_GROUP_LOSS") == "1",
           do: false,
           else: "instrumented source-loss review required"
         )
  test "recorded synthetic relation refuses review after original source owner loss", c do
    {context, [inactive]} = synthetic_original_sources(c, 1, :session)
    {candidate, prepared, event, proof, sha} = synthetic_recorded_relation(c, inactive)

    :sys.replace_state(c.session, fn s ->
      s =
        put_in(s.config[:managed_supersession_layout], Ipse.Session.ManagedSupersession.layout())

      s = put_in(s.invocation.action.intent, candidate)

      Map.put(s, :managed_supersession, %{
        prepared: prepared,
        candidate: candidate,
        proof: proof,
        source: %{},
        records: [],
        token: nil
      })
    end)

    probe(c.host, {:supersession_record_fixture, sha, event}, :ok)

    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "recorded-union-loss-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    context =
      context
      |> Map.put(:owner, c.session)
      |> Map.put(:job_ref, c.job)
      |> Map.put(:source_binding, {:supersession, sha})

    command =
      {:synthetic_supersession_positive, paths, context, [inactive, proof], candidate, sha}

    host_ref = Process.monitor(c.host)
    send(c.host, {:probe, command})
    assert_receive {:tty_group_paused, host, session, _port, _, _, [{_, original}]}, 5_000
    assert host == c.host and session == c.session
    assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(original.pid)])
    send(host, :tty_continue)

    receive do
      {:probe_result, ^command, {:error, _}} -> :ok
      {:DOWN, ^host_ref, :process, _, _} -> :ok
    after
      10_000 -> flunk("source owner loss did not refuse synthetic review")
    end
  end

  @tag :controlled_tty_union
  @tag :supersession_ticket_positive
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_UNION") == "1",
           do: false,
           else: "active source fixture required"
         )
  test "a changed recorded relation is refused at the actual Writer drain", c do
    {candidate, prepared, event, proof, sha} = synthetic_recorded_relation(c)

    :sys.replace_state(c.session, fn s ->
      s =
        put_in(s.config[:managed_supersession_layout], Ipse.Session.ManagedSupersession.layout())

      s = put_in(s.invocation.action.intent, candidate)

      Map.put(s, :managed_supersession, %{
        prepared: prepared,
        candidate: candidate,
        proof: proof,
        source: %{},
        records: [],
        token: nil
      })
    end)

    probe(c.host, {:supersession_record_fixture, sha, event}, :ok)
    command = {:supersession_display_ticket, candidate, sha}
    send(c.host, {:probe, command})
    assert_receive {:probe_result, ^command, {:ok, ticket, operation, deadline, _overall}}, 5_000
    writer = :sys.get_state(c.session).journal_writer
    host_ref = Process.monitor(c.host)
    :ok = :sys.suspend(writer)

    try do
      send(c.host, {:probe, {:source_begin_candidate, candidate, ticket, operation, deadline}})
      await_phase(c.session, :draining)

      :sys.replace_state(c.session, fn s ->
        put_in(s.managed_supersession.records, [put_in(event, ["facts", "reason"], "changed")])
      end)
    after
      :ok = :sys.resume(writer)
    end

    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_union
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_UNION") == "1",
           do: false,
           else: "active source fixture required"
         )
  test "active source proof is revalidated in the frozen Writer snapshot", c do
    proof = active_source(c)

    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "source-bound-switch-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    probe(c.host, {:session_transaction_source, paths, [proof]}, :ok)
    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_union
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_UNION") == "1",
           do: false,
           else: "active source fixture required"
         )
  test "active and inactive original sources remain held through the native switch", c do
    active = active_source(c)
    {context, inactive} = synthetic_original_sources(c, 2)

    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "active-inactive-switch-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    probe(c.host, {:session_transaction_sources, paths, active, context, inactive}, :ok)
    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_union
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_UNION") == "1",
           do: false,
           else: "active source fixture required"
         )
  test "inactive source owner loss refuses the active Session switch", c do
    active = active_source(c)
    {context, inactive} = synthetic_original_sources(c, 2)

    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "active-inactive-loss-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    host_ref = Process.monitor(c.host)
    send(c.host, {:probe, {:session_transaction_source_loss, paths, active, context, inactive}})
    assert_receive {:source_switch_ready, host, root, pid}, 5_000
    assert {_, 0} = System.cmd("/bin/kill", ["-KILL", Integer.to_string(pid)])
    send(host, :continue_session_switch)
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    refute_receive {:source_switch_result, :ok}, 100
    assert File.read!(Path.join(root, "root.json")) == "old"
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_union
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_UNION") == "1",
           do: false,
           else: "active source fixture required"
         )
  test "source redacted after ticket cannot enter the Writer barrier", c do
    proof = active_source(c)
    command = {:source_ticket, [proof]}
    send(c.host, {:probe, command})
    assert_receive {:probe_result, ^command, {:ok, ticket, operation, deadline}}, 5_000
    writer = :sys.get_state(c.session).journal_writer

    :sys.replace_state(writer, fn s ->
      index = s.source_window.index

      {:ok, redacted} =
        Ipse.Session.SourceIndex.redact(
          index,
          proof["occurrence_id"],
          index.policy_generation + 1
        )

      put_in(s.source_window.index, redacted)
    end)

    host_ref = Process.monitor(c.host)
    send(c.host, {:probe, {:source_begin, ticket, operation, deadline}})
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    assert :sys.get_state(writer).share_barrier == nil
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_union
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_UNION") == "1",
           do: false,
           else: "active source fixture required"
         )
  @tag :supersession_ticket_drain
  test "a synthetic display ticket with a missing recorded relation cannot start a Writer drain",
       c do
    proof = active_source(c)
    command = {:source_ticket, [proof]}
    send(c.host, {:probe, command})
    assert_receive {:probe_result, ^command, {:ok, ticket, operation, deadline}}, 5_000
    writer = :sys.get_state(c.session).journal_writer

    # Trusted fixture instrumentation simulates a relation disappearing after
    # the source ticket was created; it does not construct a real relation.
    :sys.replace_state(c.session, fn s ->
      update_in(s.share_ticket, fn binding ->
        Map.merge(binding, %{
          relation_display_purpose_sha256: JSON.sha256("synthetic relation"),
          relation_display_facts_sha256: JSON.sha256("synthetic facts"),
          relation_display_inactive_sources: []
        })
      end)
    end)

    probe(c.host, {:source_begin, ticket, operation, deadline}, {:error, :session_share_refused})
    assert :sys.get_state(c.session).share_barrier == nil
    assert :sys.get_state(writer).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_union
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_UNION") == "1",
           do: false,
           else: "active source fixture required"
         )
  @tag :supersession_ticket_drain
  test "a missing display relation at Writer drain poisons the Session before transfer", c do
    proof = active_source(c)
    command = {:source_ticket, [proof]}
    send(c.host, {:probe, command})
    assert_receive {:probe_result, ^command, {:ok, ticket, operation, deadline}}, 5_000
    writer = :sys.get_state(c.session).journal_writer
    host_ref = Process.monitor(c.host)
    :ok = :sys.suspend(writer)

    try do
      send(c.host, {:probe, {:source_begin, ticket, operation, deadline}})
      await_phase(c.session, :draining)

      # Inject only the display binding into the actual pending barrier. With
      # no matching recorded relation, the drain response must be refused.
      :sys.replace_state(c.session, fn s ->
        update_in(s.share_barrier, fn barrier ->
          Map.merge(barrier, %{
            relation_display_purpose_sha256: JSON.sha256("synthetic relation"),
            relation_display_facts_sha256: JSON.sha256("synthetic facts"),
            relation_display_inactive_sources: []
          })
        end)
      end)
    after
      :ok = :sys.resume(writer)
    end

    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_union
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_UNION") == "1",
           do: false,
           else: "active source fixture required"
         )
  test "source-bound barrier fences journal operations until native switch settles", c do
    proof = active_source(c)

    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "source-bound-frozen-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    command = {:session_transaction_source_hold, paths, [proof]}
    send(c.host, {:probe, command})
    assert_receive {:session_switch_ready, host, root}, 5_000
    state = :sys.get_state(c.session)
    writer = state.journal_writer

    assert Enum.map(:sys.get_state(writer).share_barrier.snapshot.verified_sources, & &1["proof"]) ===
             [proof]

    assert {:error, :journal_share_frozen} =
             Ipse.Journal.Writer.append(writer, %{"type" => "blocked"})

    assert {:error, :session_share_frozen} = GenServer.call(c.session, :unrelated_probe)
    assert File.read!(Path.join(root, "root.json")) == "old"
    send(host, :continue_session_switch)
    assert_receive {:probe_result, ^command, :ok}, 5_000
    assert File.read!(Path.join(root, "root.json")) == "new"
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  test "Writer close waits for its native owner exit before thaw", c do
    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "session-switch-close-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    writer = :sys.get_state(c.session).journal_writer
    test = self()

    trace = fn
      false, {:in, {port, {:exit_status, 0}}}, _ when is_port(port) ->
        send(test, :writer_owner_exit_held)
        receive do: (:release_writer_owner_exit -> :ok)
        true

      state, _, _ ->
        state
    end

    assert :ok = :sys.install(writer, {trace, false})
    command = {:session_transaction, paths}
    send(c.host, {:probe, command})
    assert_receive :writer_owner_exit_held, 5_000
    await_phase(c.session, :writer_closing)
    send(writer, :release_writer_owner_exit)
    assert_receive {:probe_result, ^command, :ok}, 5_000
    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_group
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_GROUP") == "1",
           do: false,
           else: "group helper required"
         )
  test "review cannot thaw before the authenticated display notice", c do
    send(c.host, {:probe, {:controlled_review_begin, c.intent}})
    assert_receive {:probe_result, {:controlled_review_begin, _}, {:ok, cap, _, _, _}}, 5_000
    send(c.host, {:probe, {:spawn_synthetic_terminal, cap}})
    assert_receive {:probe_result, {:spawn_synthetic_terminal, ^cap}, {:ok, port}}, 5_000

    :sys.replace_state(c.session, fn s ->
      update_in(s.share_barrier, &Map.merge(&1, %{phase: :settled, owner_phase: :transferred}))
    end)

    writer = :sys.get_state(c.session).journal_writer
    host_ref = Process.monitor(c.host)
    send(c.host, {:probe, {:review_thaw, cap, port}})
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    assert :sys.get_state(writer).share_barrier != nil
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_group
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_GROUP_HOLD") == "1",
           do: false,
           else: "held synthetic review required"
         )
  test "terminal loss during grouped input poisons the thawed Session", c do
    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "group-review-loss-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    {context, proofs} = synthetic_original_sources(c, 2)
    host_ref = Process.monitor(c.host)
    send(c.host, {:probe, {:synthetic_review_tty, paths, context, proofs}})
    await_phase(c.session, :review_input)
    state = :sys.get_state(c.session)
    assert :sys.get_state(state.journal_writer).share_barrier == nil
    assert {:error, :session_share_frozen} = GenServer.call(c.session, :unrelated_probe)

    Process.sleep(5_200)
    state = :sys.get_state(c.session)
    assert state.share_barrier.phase == :review_input
    assert state.share_barrier.notice_final

    assert {_, 0} =
             System.cmd("/bin/kill", [
               "-KILL",
               Integer.to_string(state.share_barrier.issued_terminal.pid)
             ])

    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_group
  @tag timeout: 25_000
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_GROUP_HOLD") == "1",
           do: false,
           else: "held synthetic review required"
         )
  test "grouped review expires while waiting for input", c do
    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "group-review-expiry-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    {context, proofs} = synthetic_original_sources(c, 2)
    host_ref = Process.monitor(c.host)
    send(c.host, {:probe, {:synthetic_review_tty, paths, context, proofs}})
    await_phase(c.session, :review_input)
    state = :sys.get_state(c.session)
    assert :sys.get_state(state.journal_writer).share_barrier == nil
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 17_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_union
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_UNION") == "1",
           do: false,
           else: "active source fixture required"
         )
  test "real active source and inactive originals remain verified through the synthetic bridge",
       c do
    active = active_source(c)

    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "union-tty-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    {context, inactive} = synthetic_original_sources(c, 2)
    context = context |> Map.put(:owner, c.session) |> Map.put(:job_ref, c.job)
    candidate = put_in(c.intent, ["request", "op"], "collection.call")
    :sys.replace_state(c.session, fn s -> put_in(s.invocation.action.intent, candidate) end)

    probe(
      c.host,
      {:synthetic_union_tty, paths, context, [hd(inactive), active, List.last(inactive)],
       candidate},
      :ok
    )

    :sys.replace_state(c.session, fn s -> put_in(s.invocation.action.intent, c.intent) end)
    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_union
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_UNION") == "1",
           do: false,
           else: "active source fixture required"
         )
  @tag :supersession_union_refusal
  test "synthetic supersession review refuses a source union without a recorded relation", c do
    active = active_source(c)

    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "supersession-review-refusal-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    {context, inactive} = synthetic_original_sources(c, 2)
    context = context |> Map.put(:owner, c.session) |> Map.put(:job_ref, c.job)
    candidate = put_in(c.intent, ["request", "op"], "collection.call")
    :sys.replace_state(c.session, fn s -> put_in(s.invocation.action.intent, candidate) end)

    probe(
      c.host,
      {:synthetic_supersession_review, paths, context,
       [hd(inactive), active, List.last(inactive)], candidate},
      {:error, :cleanup_unconfirmed}
    )

    :sys.replace_state(c.session, fn s -> put_in(s.invocation.action.intent, c.intent) end)
    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :error}}, 10_000
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_union
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_UNION") == "1",
           do: false,
           else: "active source fixture required"
         )
  test "active and inactive source union remains valid across synthetic review input", c do
    active = active_source(c)

    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "union-review-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    {context, inactive} = synthetic_original_sources(c, 2)
    context = context |> Map.put(:owner, c.session) |> Map.put(:job_ref, c.job)
    candidate = put_in(c.intent, ["request", "op"], "collection.call")
    :sys.replace_state(c.session, fn s -> put_in(s.invocation.action.intent, candidate) end)

    probe(
      c.host,
      {:synthetic_union_review, paths, context, [hd(inactive), active, List.last(inactive)],
       candidate},
      :ok
    )

    :sys.replace_state(c.session, fn s -> put_in(s.invocation.action.intent, c.intent) end)
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_union
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_UNION") == "1",
           do: false,
           else: "active source fixture required"
         )
  test "an active-only source union remains valid across synthetic review input", c do
    active = active_source(c)

    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "active-only-review-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    {context, _inactive} = synthetic_original_sources(c, 1)
    context = context |> Map.put(:owner, c.session) |> Map.put(:job_ref, c.job)
    candidate = put_in(c.intent, ["request", "op"], "collection.call")
    :sys.replace_state(c.session, fn s -> put_in(s.invocation.action.intent, candidate) end)

    probe(c.host, {:synthetic_union_review, paths, context, [active], candidate}, :ok)
    :sys.replace_state(c.session, fn s -> put_in(s.invocation.action.intent, c.intent) end)
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_union
  @tag skip:
         if(
           System.get_env("IPSE_SHARE_TTY_UNION") == "1" and
             System.get_env("IPSE_REVIEW_MANIFEST_INJECT") == "1",
           do: false,
           else: "instrumented active-only review required"
         )
  test "injected active-only review text cannot reach the terminal", c do
    active = active_source(c)

    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "active-only-injection-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    {context, _inactive} = synthetic_original_sources(c, 1)
    context = context |> Map.put(:owner, c.session) |> Map.put(:job_ref, c.job)
    candidate = put_in(c.intent, ["request", "op"], "collection.call")
    :sys.replace_state(c.session, fn s -> put_in(s.invocation.action.intent, candidate) end)
    host_ref = Process.monitor(c.host)
    command = {:synthetic_union_review, paths, context, [active], candidate}
    send(c.host, {:probe, command})
    assert_receive :review_manifest_injected, 5_000

    receive do
      {:probe_result, ^command, {:error, _}} ->
        assert :sys.get_state(c.session).share_barrier == nil
        :sys.replace_state(c.session, fn s -> put_in(s.invocation.action.intent, c.intent) end)
        send(c.host, :continue)
        assert_receive {:ipse, _, {:done, :error}}, 10_000
        assert Session.close_confirmed(c.session) in [:ok, {:error, :cleanup_unconfirmed}]

      {:DOWN, ^host_ref, :process, _, _} ->
        assert :sys.get_state(c.session).share_barrier.phase == :poisoned
        assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
    after
      7_000 -> flunk("injected active-only review did not refuse")
    end
  end

  @tag :controlled_tty_union
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_UNION_RACE") == "1",
           do: false,
           else: "held active source review required"
         )
  test "active source redaction during review prevents a verified result", c do
    active = active_source(c)

    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "union-review-redact-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    {context, inactive} = synthetic_original_sources(c, 2)
    context = context |> Map.put(:owner, c.session) |> Map.put(:job_ref, c.job)
    candidate = put_in(c.intent, ["request", "op"], "collection.call")
    :sys.replace_state(c.session, fn s -> put_in(s.invocation.action.intent, candidate) end)

    command =
      {:synthetic_union_review, paths, context, [hd(inactive), active, List.last(inactive)],
       candidate}

    send(c.host, {:probe, command})
    await_phase(c.session, :review_input)
    writer = :sys.get_state(c.session).journal_writer

    :sys.replace_state(writer, fn s ->
      index = s.source_window.index

      {:ok, redacted} =
        Ipse.Session.SourceIndex.redact(
          index,
          active["occurrence_id"],
          index.policy_generation + 1
        )

      put_in(s.source_window.index, redacted)
    end)

    File.write!(Path.join(System.fetch_env!("IPSE_REVIEW_TEST_SIGNAL_DIR"), "release"), "release")
    assert_receive :synthetic_review_callback_completed, 10_000
    assert_receive {:probe_result, ^command, {:error, :collection_source_refused}}, 10_000
    :sys.replace_state(c.session, fn s -> put_in(s.invocation.action.intent, c.intent) end)
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_union_refusal
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_UNION") == "1",
           do: false,
           else: "active source fixture required"
         )
  test "forged active proof refuses the Session union before terminal display", c do
    active = Map.put(active_source(c), "receipt_sha256", JSON.sha256("forged active receipt"))

    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "union-refusal-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    {context, inactive} = synthetic_original_sources(c, 2)
    context = context |> Map.put(:owner, c.session) |> Map.put(:job_ref, c.job)
    candidate = put_in(c.intent, ["request", "op"], "collection.call")
    :sys.replace_state(c.session, fn s -> put_in(s.invocation.action.intent, candidate) end)

    probe(
      c.host,
      {:synthetic_union_tty, paths, context, [active | inactive], candidate},
      {:error, :collection_source_refused}
    )

    :sys.replace_state(c.session, fn s -> put_in(s.invocation.action.intent, c.intent) end)
    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_group_loss
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_GROUP_LOSS") == "1",
           do: false,
           else: "group loss hook required"
         )
  test "loss of an original source before display refuses the active Session bridge", c do
    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "group-loss-tty-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    {context, proofs} = synthetic_original_sources(c, 2)
    command = {:synthetic_group_tty, paths, context, proofs}
    host_monitor = Process.monitor(c.host)
    send(c.host, {:probe, command})
    assert_receive {:tty_group_paused, host, session, _port, _, _, sources}, 5_000
    assert host == c.host and session == c.session
    assert length(sources) == 2
    {_, lost} = hd(sources)
    assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(lost.pid)])
    send(host, :tty_continue)

    receive do
      {:probe_result, ^command, {:error, :collection_source_refused}} -> :ok
      {:DOWN, ^host_monitor, :process, _, _} -> :ok
    after
      10_000 -> flunk("group source loss did not terminate or refuse the Host")
    end
  end

  @tag :controlled_tty_group_session_loss
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_GROUP_LOSS") == "1",
           do: false,
           else: "group loss hook required"
         )
  test "loss of the active Session before display terminates the grouped bridge", c do
    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "group-session-loss-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    {context, proofs} = synthetic_original_sources(c, 2)
    command = {:synthetic_group_tty, paths, context, proofs}
    host_monitor = Process.monitor(c.host)
    session_monitor = Process.monitor(c.session)
    send(c.host, {:probe, command})
    assert_receive {:tty_group_paused, host, session, _port, _, _, sources}, 5_000
    assert host == c.host and session == c.session and length(sources) == 2
    Process.exit(c.session, :kill)
    assert_receive {:DOWN, ^session_monitor, :process, _, _}, 5_000
    send(host, :tty_continue)
    assert_receive {:DOWN, ^host_monitor, :process, _, _}, 5_000
  end

  @tag :controlled_tty_bridge
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_SIX") == "1",
           do: false,
           else: "six-lease helper required"
         )
  test "Session receives notices after six synthetic owners settle", c do
    paths =
      for n <- 1..5 do
        dir = Path.join(c.root, "tty-six-notice-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    probe(c.host, {:synthetic_tty_six_notice, paths}, :ok)
    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_bridge
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_SIX") == "1",
           do: false,
           else: "six-lease helper required"
         )
  test "Host coordinates a protected worker's six-lease terminal display", c do
    paths =
      for n <- 1..5 do
        dir = Path.join(c.root, "tty-coordinated-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    probe(c.host, {:coordinated_tty_six, paths}, :ok)
    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_bridge
  @tag skip:
         if(System.get_env("IPSE_SHARE_TTY_SIX") == "1",
           do: false,
           else: "six-lease helper required"
         )
  test "Host coordinates six-owner synthetic notices from a protected worker", c do
    paths =
      for n <- 1..5 do
        dir = Path.join(c.root, "tty-coordinated-notice-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    probe(c.host, {:coordinated_tty_six_notice, paths}, :ok)
    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_bridge
  @tag :bound_host
  @tag skip:
         if(System.get_env("IPSE_BOUND_HOST_FIXTURE"),
           do: false,
           else: "bound acceptance fixture required"
         )
  test "Host coordinates a bound acceptance's six retained owners", c do
    fixture = System.fetch_env!("IPSE_BOUND_HOST_FIXTURE") |> File.read!() |> Jason.decode!()

    command =
      if System.get_env("IPSE_BOUND_HOST_REFERENCE") == "1",
        do: {:coordinated_reference_six, fixture},
        else: {:coordinated_bound_six, fixture}

    if System.get_env("IPSE_BOUND_EXPIRE_BEFORE_ACTIVATION") == "1" or
         System.get_env("IPSE_BOUND_LOSE_SOURCE_BEFORE_ACTIVATION") == "1" or
         System.get_env("IPSE_BOUND_LOSE_JOURNAL_BEFORE_ACTIVATION") == "1" do
      host_monitor = Process.monitor(c.host)
      send(c.host, {:probe, command})

      receive do
        {:probe_result, ^command, result} ->
          assert match?({:unknown, _}, result) or match?({:error, _}, result)
          IO.puts("BOUND_CLEANUP_UNCONFIRMED")

        {:DOWN, ^host_monitor, :process, _, _} ->
          IO.puts("BOUND_HOST_TERMINATED")
          :ok
      after
        30_000 -> flunk("Host cleanup outcome was not observed")
      end

      Process.demonitor(host_monitor, [:flush])
    else
      probe(c.host, command, :ok)
      assert :sys.get_state(c.session).share_barrier == nil
      send(c.host, :continue)
      assert_receive {:ipse, _, {:done, :ok}}, 10_000
      assert :ok = Session.close_confirmed(c.session)
    end
  end

  @tag :controlled_tty_identity
  test "Session lock identity and close preparation require the actual armed Host", c do
    send(c.host, {:probe, {:controlled_begin, c.intent}})
    assert_receive {:probe_result, {:controlled_begin, _}, {:ok, cap, _, _, controls}}, 5_000

    assert {:error, :session_share_frozen} =
             GenServer.call(c.session, {:session_share_identity, c.job, cap})

    send(c.host, {:probe, {:share_identity, cap}})
    assert_receive {:probe_result, {:share_identity, ^cap}, {:ok, identity}}, 5_000
    state = :sys.get_state(c.session)
    stat = File.stat!(Path.join(state.dir, state.id <> ".lock"))
    assert {identity.device, identity.inode} == {stat.major_device, stat.inode}
    assert {:os_pid, pid} = Port.info(state.lock, :os_pid)
    assert identity.pid == pid

    probe(
      c.host,
      {:prepare_terminal_close, cap, controls.host_port},
      {:error, :session_share_frozen}
    )

    probe(c.host, {:controlled_abort, cap, controls.host_port}, :ok)
    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_recipient
  test "terminal close cannot substitute a different Host-owned native port", c do
    send(c.host, {:probe, {:controlled_begin, c.intent}})
    assert_receive {:probe_result, {:controlled_begin, _}, {:ok, cap, _, _, controls}}, 5_000
    assert {:os_pid, other_pid} = Port.info(controls.host_port, :os_pid)

    # Exercise the close boundary without asserting a completed native handoff.
    :sys.replace_state(c.session, fn s ->
      update_in(s.share_barrier, fn b ->
        Map.merge(b, %{phase: :settled, owner_phase: :transferred, owner_recipient: other_pid + 1})
      end)
    end)

    monitor = Process.monitor(c.host)
    send(c.host, {:probe, {:prepare_terminal_close, cap, controls.host_port}})
    assert_receive {:DOWN, ^monitor, :process, _, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_recipient
  test "terminal close accepts the selected Host-owned port at the settled boundary", c do
    send(c.host, {:probe, {:controlled_begin, c.intent}})
    assert_receive {:probe_result, {:controlled_begin, _}, {:ok, cap, _, _, controls}}, 5_000
    assert {:os_pid, recipient} = Port.info(controls.host_port, :os_pid)

    # The boundary is simulated; the separate tty fixture exercises real transfer.
    :sys.replace_state(c.session, fn s ->
      update_in(s.share_barrier, fn b ->
        Map.merge(b, %{phase: :settled, owner_phase: :transferred, owner_recipient: recipient})
      end)
    end)

    probe(c.host, {:prepare_terminal_close, cap, controls.host_port}, :ok)
    assert :sys.get_state(c.session).share_barrier.phase == :terminal_closing
    assert {:error, :cleanup_unconfirmed} = Session.cancel(c.session)
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
  end

  @tag :native_sandbox
  @tag :controlled_tty_recipient_transfer
  test "a real transferred owner control rejects a different Host port", c do
    send(c.host, {:probe, {:controlled_begin, c.intent}})
    assert_receive {:probe_result, {:controlled_begin, _}, {:ok, cap, _, _, controls}}, 5_000

    {observer, recipient, name, secret} =
      control_observer(controls.session_pid, controls.operation, 1)

    probe(c.host, {:configure_session, cap, recipient, name, secret}, :ok)
    assert receive_frame(observer, ?L) == <<controls.operation::binary, 1>>
    await_control_phase(c.session, :transferred)
    assert :sys.get_state(c.session).share_barrier.owner_recipient == recipient
    assert {:os_pid, other_pid} = Port.info(controls.host_port, :os_pid)
    refute other_pid == recipient

    # Only settlement is simulated; the owner-control transfer above is native.
    :sys.replace_state(c.session, fn s -> put_in(s, [:share_barrier, :phase], :settled) end)
    monitor = Process.monitor(c.host)
    send(c.host, {:probe, {:prepare_terminal_close, cap, controls.host_port}})
    assert_receive {:DOWN, ^monitor, :process, _, _}, 5_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    assert_receive {^observer, {:exit_status, 0}}, 5_000
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  test "a separate protected effect cannot impersonate the Host Session owner", c do
    probe(
      c.host,
      {:effect_controlled_begin, c.intent},
      {:error, :owner_control_unavailable}
    )

    assert :sys.get_state(c.session).share_barrier == nil
    send(c.host, :continue)
    assert_receive {:ipse, _, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(c.session)
  end

  @tag :controlled_tty_loss
  test "actual Session cancellation leaves stopped native writer holding all leases", c do
    paths =
      for n <- 1..3 do
        dir = Path.join(c.root, "tty-loss-lock-#{n}")
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    send(c.host, {:probe, {:synthetic_tty, paths}})
    assert_receive {:tty_paused, host, session, port, identities, session_identity}, 5_000
    assert host == c.host and session == c.session
    {:os_pid, guardian} = Port.info(port, :os_pid)
    child_path = "/proc/#{guardian}/task/#{guardian}/children"
    reader = child_path |> File.read!() |> String.trim() |> String.to_integer()

    on_exit(fn ->
      System.cmd("kill", ["-CONT", Integer.to_string(reader)], stderr_to_stdout: true)
      System.cmd("kill", ["-KILL", Integer.to_string(reader)], stderr_to_stdout: true)
      System.cmd("kill", ["-CONT", Integer.to_string(guardian)], stderr_to_stdout: true)
      System.cmd("kill", ["-KILL", Integer.to_string(guardian)], stderr_to_stdout: true)
    end)

    assert {_, 0} = System.cmd("kill", ["-STOP", Integer.to_string(reader)])
    assert {_, 0} = System.cmd("kill", ["-STOP", Integer.to_string(guardian)])
    state = :sys.get_state(c.session)
    session_path = Path.join(state.dir, state.id <> ".lock")
    :ok = :sys.suspend(state.journal_writer)
    host_ref = Process.monitor(c.host)
    before_cancel = System.monotonic_time(:millisecond)
    assert {:error, :cleanup_unconfirmed} = Session.cancel(c.session)
    assert System.monotonic_time(:millisecond) - before_cancel < 1_000
    assert_receive {:DOWN, ^host_ref, :process, _, _}, 5_000
    :ok = :sys.resume(state.journal_writer)
    session_ref = Process.monitor(c.session)
    Process.exit(c.session, :kill)
    assert_receive {:DOWN, ^session_ref, :process, _, _}, 5_000
    assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(guardian)])

    for {kind, pid} <- [{:session, session_identity.pid}, {:transaction, hd(identities).pid}] do
      assert process_gone?(pid, 600),
             "#{kind} owner still live: #{inspect(File.read("/proc/#{pid}/status"))}"
    end

    for path <- [session_path | paths], do: assert({:error, _} = Runner.protected_lock(path))
    assert {_, 0} = System.cmd("kill", ["-CONT", Integer.to_string(reader)])

    for path <- [session_path | paths] do
      assert {:ok, contender} = acquire_eventually(path, 150)
      assert :ok = Runner.unlock(contender)
    end
  end

  defp process_gone?(_pid, 0), do: false

  defp process_gone?(pid, attempts) do
    case File.read("/proc/#{pid}/stat") do
      {:error, :enoent} ->
        true

      {:ok, stat} ->
        if Regex.match?(~r/\) Z /, stat),
          do: true,
          else:
            (
              Process.sleep(10)
              process_gone?(pid, attempts - 1)
            )

      _ ->
        false
    end
  end

  defp acquire_eventually(_path, 0), do: {:error, :still_locked}

  defp acquire_eventually(path, attempts) do
    case Runner.protected_lock(path) do
      {:ok, _} = result ->
        result

      _ ->
        Process.sleep(10)
        acquire_eventually(path, attempts - 1)
    end
  end

  defp control_observer(sender, operation, role) do
    info = File.stat!("/proc/#{sender}/fd/0")
    helper = Path.join(to_string(:code.priv_dir(:ipse)), "ipse-runner")

    observer =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        args: ["--owner-control-observe-v1"]
      ])

    assert receive_frame(observer, ?H) == "owner-observer-v1"
    {:os_pid, recipient} = Port.info(observer, :os_pid)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)
    entry = <<sender::32, name::binary, secret::binary, info.major_device::64, info.inode::64>>
    request = <<operation::binary, role, entry::binary, 30_000::64>>
    assert Port.command(observer, <<?I, byte_size(request)::32, request::binary>>)
    {observer, recipient, name, secret}
  end

  defp receive_frame(port, kind, buffer \\ <<>>) do
    case buffer do
      <<^kind, length::32, body::binary-size(length)>> ->
        body

      _ ->
        receive do
          {^port, {:data, bytes}} when byte_size(buffer) + byte_size(bytes) <= 256 ->
            receive_frame(port, kind, buffer <> bytes)

          {^port, {:exit_status, status}} ->
            flunk("collector exited before reply: #{status}")
        after
          8_000 -> flunk("collector response timed out")
        end
    end
  end

  defp active_source(c) do
    state = :sys.get_state(c.session)
    writer = :sys.get_state(state.journal_writer)

    assert {:ok, page} =
             Ipse.Session.SourceIndex.list(writer.source_window.index, %{"limit" => 32})

    active =
      Enum.find_value(page["sources"], fn source ->
        case Ipse.Session.SourceIndex.resolve_proof(writer.source_window.index, %{
               "handle" => source["read_handle"],
               "quote" => "Synthetic active Session source"
             }) do
          {:ok, %{"proof" => proof}} -> proof
          _ -> nil
        end
      end)

    assert is_map(active) and active["session_id"] == state.id
    active
  end

  # Trusted test construction: the active proof is issued by this Session's
  # Writer, but the relation values and pending purpose are synthetic.
  defp synthetic_recorded_relation(c, old_proof \\ nil) do
    state = :sys.get_state(c.session)
    writer = :sys.get_state(state.journal_writer)
    {:ok, page} = Ipse.Session.SourceIndex.list(writer.source_window.index, %{"limit" => 32})
    quote = "Synthetic active Session source"

    {request_proof, proof} =
      Enum.find_value(page["sources"], fn source ->
        request = %{"handle" => source["read_handle"], "quote" => quote}

        case Ipse.Session.SourceIndex.resolve_proof(writer.source_window.index, request) do
          {:ok, %{"proof" => proof}} -> {request, proof}
          _ -> nil
        end
      end)

    recipe =
      Ipse.Test.ManagedPolicy.policy()["settings"]["recipes"]
      |> Map.values()
      |> Enum.find(&(&1["kind"] == "literal_source"))

    hash = &JSON.sha256/1
    old_key = "note." <> hash.("synthetic predecessor")
    new_key = "note." <> hash.("synthetic successor")
    old_value = %{"evidence" => %{"sources" => [old_proof || proof]}}
    new_value = %{"evidence" => %{"sources" => [proof]}}
    now = System.system_time(:millisecond)
    deadline = now + 60_000
    pin = %{"policy_sha256" => hash.("synthetic policy")}
    descriptor_sha = JSON.digest([state.invocation.parent["descriptor"]])

    capture = %{
      "op" => "collection.managed",
      "metadata_version" => 3,
      "recipe_sha256" => JSON.digest([recipe]),
      "proofs" => [request_proof],
      "request" => %{
        "op" => "commit",
        "expected_generation" => 1,
        "advance_floor" => true,
        "changes" => [%{"key" => new_key, "expected_revision" => 0, "value" => new_value}]
      }
    }

    candidate =
      c.intent
      |> Map.put("request", capture)
      |> Map.put("effect_binding", %{"pin" => pin, "outer_sha256" => descriptor_sha})

    prepared = %{
      "type" => "managed_supersession_prepared",
      "version" => 1,
      "id" => Usage.id(),
      "session_id" => state.id,
      "assertion_id" => Usage.id(),
      "mode" => "ordinary",
      "target_key" => old_key,
      "pin_sha256" => JSON.digest([pin]),
      "descriptor_sha256" => descriptor_sha
    }

    context = %{
      "session_id" => state.id,
      "job_id" => Usage.id(),
      "client_id" => Usage.id(),
      "project_id" => hash.("synthetic project"),
      "namespace" => hash.("synthetic namespace"),
      "binding_sha256" => hash.("synthetic binding"),
      "management_epoch" => 1,
      "management_sha256" => hash.("synthetic management"),
      "original_pin" => nil,
      "recipe" => recipe
    }

    metadata = %{
      "lineage" => String.replace_prefix(old_key, "note.", ""),
      "category" => "ordinary",
      "first_admitted_ms" => now - 1,
      "valid_until_ms" => deadline
    }

    target = %{"key" => old_key, "revision" => 1, "value" => old_value}
    old_change = %{"key" => old_key, "expected_revision" => 1, "value" => old_value}

    request =
      put_in(capture, ["request", "changes"], [old_change | capture["request"]["changes"]])[
        "request"
      ]

    operation = Usage.id()

    body = %{
      "version" => 1,
      "kind" => "managed_literal_supersession",
      "operation_id" => operation,
      "context" => context,
      "collection" => %{"root" => %{"generation" => 1}},
      "target" => target,
      "metadata" => metadata,
      "replacement" => %{"key" => new_key, "value" => new_value},
      "mode" => "ordinary",
      "history_rule" => %{"basis" => "existing_deadline", "at_ms" => deadline},
      "new_source_sha256" => JSON.digest([[proof]]),
      "new_policy_sha256" => pin["policy_sha256"],
      "checked_at_ms" => now,
      "reason" => "synthetic test relation",
      "request_sha256" => JSON.digest([request]),
      "scope" => "synthetic fixture"
    }

    facts = Map.put(body, "action_sha256", JSON.digest([body]))
    sha = JSON.digest([prepared, candidate])

    event = %{
      "type" => "managed_supersession_intent",
      "version" => 1,
      "purpose_sha256" => sha,
      "candidate_operation_id" => candidate["operation_id"],
      "candidate_request_sha256" => JSON.digest([capture]),
      "operation_id" => operation,
      "facts" => facts
    }

    assert :ok = Ipse.Extension.ManagedCollectionCall.validate(capture)
    assert Ipse.Session.ManagedSupersession.record?(event, prepared, candidate, [])

    assert {:ok, _} =
             Ipse.Session.ManagedSupersession.reviewed_display_sources(facts, state.id, now)

    {candidate, prepared, event, proof, sha}
  end

  defp synthetic_original_sources(c, count, location \\ :separate) do
    alias Ipse.Session.{Input, Saved, SourceIndex, SourceWindow}
    alias Ipse.Test.ManagedPolicy, as: F

    directory =
      if location == :session do
        :sys.get_state(c.session).dir
      else
        path = Path.join(c.root, "group-original-sessions")
        File.mkdir!(path)
        File.chmod!(path, 0o700)
        path
      end

    binding = F.binding()
    namespace = JSON.digest(["synthetic group source namespace"])
    {:ok, selectors} = Ipse.Extension.SemanticRoutes.selectors(F.policy()["settings"]["routes"])

    proofs =
      for index <- 1..count do
        id = Usage.id()

        pin =
          Map.new(
            ~w(policy_sha256 identity_sha256 routes_sha256 source_sha256),
            &{&1, JSON.digest([&1])}
          )
          |> Map.merge(%{
            "version" => 1,
            "session_id" => id,
            "epoch" => 1,
            "project_id" => binding["project_id"],
            "worktree_id" => binding["worktree_id"],
            "binding_sha256" => binding["binding_sha256"],
            "namespace" => namespace
          })

        admission = %{
          "version" => 1,
          "binding" => binding,
          "instance" => "knowledge",
          "pin" => pin,
          "selectors" => selectors,
          "status" => "active"
        }

        assert {:ok, ^id} =
                 Ipse.Journal.create_with_id(directory, id, %{
                   "source_layout" => SourceWindow.layout(),
                   "source_origin_layout" => Ipse.Journal.SourceOrigin.layout(),
                   "semantic_admission" => admission
                 })

        text = "Synthetic grouped source #{index}"

        assert :ok =
                 Ipse.Journal.append(
                   directory,
                   id,
                   Input.received(id, Usage.id(), text, text, nil)
                 )

        assert :ok =
                 Ipse.Journal.append(directory, id, %{
                   "type" => "message",
                   "message" => %{"role" => "user", "content" => text}
                 })

        assert {:ok, events} = Ipse.Journal.load(directory, id)
        assert {:ok, saved} = Saved.restore(events, id)
        assert {:ok, page} = SourceIndex.list(saved.source_window.index, %{"limit" => 1})
        [source] = page["sources"]

        assert {:ok, %{"proof" => proof}} =
                 SourceIndex.resolve_proof(saved.source_window.index, %{
                   "handle" => source["read_handle"],
                   "quote" => text
                 })

        assert {:ok, lock} = Runner.lock(Path.join(directory, id <> ".lock"))
        assert :ok = Runner.unlock(lock)
        {proof, admission}
      end

    [{_, admission} | _] = proofs

    context = %{
      history_dir: directory,
      session_id: Session.info(c.session).id,
      config: %{semantic_admission: admission}
    }

    {context, Enum.map(proofs, &elem(&1, 0))}
  end

  defp probe(host, command, expected) do
    send(host, {:probe, command})
    assert_receive {:probe_result, ^command, ^expected}, 5_000
  end

  defp await_phase(session, phase, attempts \\ 100)

  defp await_phase(session, phase, 0),
    do: assert(%{phase: ^phase} = :sys.get_state(session).share_barrier)

  defp await_phase(session, phase, attempts) do
    case :sys.get_state(session).share_barrier do
      %{phase: ^phase} ->
        :ok

      _ ->
        Process.sleep(10)
        await_phase(session, phase, attempts - 1)
    end
  end

  defp await_control_phase(session, phase, attempts \\ 100)

  defp await_control_phase(session, phase, 0),
    do: assert(%{owner_phase: ^phase} = :sys.get_state(session).share_barrier)

  defp await_control_phase(session, phase, attempts) do
    case :sys.get_state(session).share_barrier do
      %{owner_phase: ^phase} ->
        :ok

      _ ->
        Process.sleep(10)
        await_control_phase(session, phase, attempts - 1)
    end
  end
end
