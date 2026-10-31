Code.require_file("../../support/managed_policy.exs", __DIR__)

defmodule Ipse.Session.SourceLockCapacityTest do
  use ExUnit.Case, async: false
  alias Ipse.{Journal, JSON, Runner, Usage}
  alias Ipse.Runner.Transaction
  alias Ipse.Session.{Input, Resources, Saved, SourceIndex, SourceWindow, StoredSources}
  alias Ipse.Test.ManagedPolicy, as: F

  @moduletag timeout: 90_000

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-source-lock-capacity-" <> Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    directory = Path.join(root, "sessions")
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)
    protected = Path.join(root, "protected")
    File.mkdir!(protected)
    File.chmod!(protected, 0o700)
    binding = F.binding()
    namespace = JSON.digest(["source lock capacity namespace"])
    {:ok, selectors} = Ipse.Extension.SemanticRoutes.selectors(F.policy()["settings"]["routes"])

    sources =
      for n <- 1..128 do
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

        assert Ipse.Extension.SemanticAdmission.valid?(admission, id)

        assert {:ok, ^id} =
                 Journal.create_with_id(directory, id, %{
                   "source_layout" => SourceWindow.layout(),
                   "source_origin_layout" => Ipse.Journal.SourceOrigin.layout(),
                   "semantic_admission" => admission
                 })

        text = "Synthetic retained source #{n}"

        assert :ok =
                 Journal.append(directory, id, Input.received(id, Usage.id(), text, text, nil))

        assert :ok =
                 Journal.append(directory, id, %{
                   "type" => "message",
                   "message" => %{"role" => "user", "content" => text}
                 })

        assert {:ok, events} = Journal.load(directory, id)
        assert {:ok, saved} = Saved.restore(events, id)

        assert {:ok, %{"sources" => [source]}} =
                 SourceIndex.list(saved.source_window.index, %{"limit" => 1})

        assert {:ok, %{"proof" => proof}} =
                 SourceIndex.resolve_proof(saved.source_window.index, %{
                   "handle" => source["read_handle"],
                   "quote" => text
                 })

        lock = Path.join(directory, id <> ".lock")
        File.write!(lock, "", [:exclusive])
        File.chmod!(lock, 0o600)

        %{
          proof: proof,
          lock: lock,
          journal: Path.join(directory, id <> ".jsonl"),
          admission: admission
        }
      end

    context = %{
      history_dir: directory,
      session_id: Usage.id(),
      config: %{semantic_admission: hd(sources).admission}
    }

    IO.puts("Synthetic source-lock fixture retained at #{root}")
    %{root: root, protected: protected, context: context, sources: sources}
  end

  @tag :source_lock_positive
  test "128 actual source leases coexist with shell and protected transaction; independent caps refuse excess",
       c do
    parent = self()
    {:ok, scope} = Resources.start(parent)

    task =
      Task.async(fn ->
        receive do
          :start -> :ok
        end

        Resources.bind(scope)

        assert {:ok, :admitted} =
                 Resources.controlled_owned_effect(
                   fn ->
                     child_scope = Resources.current()
                     assert child_scope != scope

                     owner = self()
                     gate = Path.join(c.root, "shell-gate")

                     shell =
                       Resources.async(fn ->
                         Runner.run(
                           "printf ready; while [ ! -f shell-gate ]; do sleep 0.05; done",
                           c.root,
                           timeout_ms: 60_000,
                           emit: fn
                             {:tool_output, "ready"} -> send(owner, :shell_ready)
                             _ -> :ok
                           end
                         )
                       end)

                     assert_receive :shell_ready, 5000

                     try do
                       proofs = Enum.map(c.sources, & &1.proof)

                       assert :admitted =
                                StoredSources.with_verified(c.context, nil, proofs, fn actual ->
                                  assert Enum.map(actual, & &1["proof"]) === proofs
                                  assert Enum.all?(actual, &(&1["unavailable"] != true))
                                  state = :sys.get_state(child_scope)

                                  assert Enum.count(state.resources, fn {_, r} ->
                                           r.kind == :source_lock
                                         end) == 128

                                  extra = Path.join(c.root, "extra-source.lock")
                                  File.write!(extra, "", [:exclusive])
                                  File.chmod!(extra, 0o600)

                                  assert {:error, :cleanup_scope_closed} =
                                           Runner.lock_source(extra)

                                  assert {:ok, cap} =
                                           Transaction.acquire(Path.join(c.protected, ".lock"))

                                  assert :ok = Transaction.check(cap)

                                  tickets =
                                    for _ <- 1..30,
                                        do:
                                          (
                                            assert {:ok, ticket} = Resources.register(:http)
                                            ticket
                                          )

                                  assert {:error, :cleanup_scope_closed} =
                                           Resources.register(:http)

                                  Enum.each(tickets, &Resources.closed(&1, :ok))
                                  assert :ok = Transaction.check(cap)
                                  assert :ok = Transaction.release(cap)
                                  :admitted
                                end)

                       :admitted
                     after
                       File.write!(gate, "done")
                       assert {:ok, _} = Task.await(shell, 5000)
                     end
                   end,
                   60_000
                 )

        assert :ok = Resources.finish(scope)
        :done
      end)

    assert :ok = Resources.attach(scope, task.pid)
    send(task.pid, :start)
    assert :done = Task.await(task, 75_000)
    assert :ok = Resources.close(scope)
    assert {:ok, free} = Runner.lock(Path.join(c.root, "extra-source.lock"))
    assert :ok = Runner.unlock(free)

    for source <- c.sources do
      assert {:ok, lease} = Runner.lock(source.lock)
      assert :ok = Runner.unlock(lease)
    end
  end

  test "owner death stops the controlled holder and releases distinct original leases", c do
    test = self()

    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, scope} = Resources.start(owner)
    sources = Enum.take(c.sources, 32)
    before = Map.new(sources, &{&1.journal, JSON.sha256(File.read!(&1.journal))})

    {worker, worker_ref} =
      spawn_monitor(fn ->
        receive do
          :start -> :ok
        end

        Resources.bind(scope)

        outcome =
          Resources.controlled_owned_effect(
            fn ->
              StoredSources.with_verified(c.context, nil, Enum.map(sources, & &1.proof), fn _ ->
                ports =
                  Enum.filter(Port.list(), &(Port.info(&1, :connected) == {:connected, self()}))

                assert length(ports) == 32
                send(test, {:source_leases_held, self(), ports})

                receive do
                  :release -> :should_not_escape
                end
              end)
            end,
            30_000
          )

        send(test, {:unexpected_effect_result, outcome})
      end)

    on_exit(fn ->
      if Process.alive?(owner), do: Process.exit(owner, :kill)
      if Process.alive?(worker), do: Process.exit(worker, :kill)
    end)

    assert :ok = Resources.attach(scope, worker)
    send(worker, :start)
    assert_receive {:source_leases_held, peer, ports}, 15_000
    peer_ref = Process.monitor(peer)
    port_refs = Enum.map(ports, &:erlang.monitor(:port, &1))
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^peer_ref, :process, ^peer, _}, 10_000
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, _}, 10_000
    for ref <- port_refs, do: assert_receive({:DOWN, ^ref, :port, _, _}, 10_000)
    refute_receive {:unexpected_effect_result, _}, 100

    for source <- sources do
      assert :ok = reacquire(source.lock, System.monotonic_time(:millisecond) + 5000)
      assert JSON.sha256(File.read!(source.journal)) == before[source.journal]
    end
  end

  defp reacquire(path, deadline) do
    case Runner.lock(path) do
      {:ok, lock} ->
        Runner.unlock(lock)

      error ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(10)
          reacquire(path, deadline)
        else
          error
        end
    end
  end
end
