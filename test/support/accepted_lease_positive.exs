if System.get_env("IPSE_ACCEPTED_LEASE_MODULE_ONLY") != "1", do: ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("test/support/managed_policy.exs")

defmodule AcceptedLeasePositive do
  import ExUnit.Assertions
  alias Ipse.Runner
  alias Ipse.Runner.Transaction, as: T

  defmodule Model do
    def complete(_, _, _, _), do: {:ok, %{"role" => "assistant", "content" => "fixture"}, %{}}
  end

  def run(helper, root, mode, fixture) do
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    wide = String.starts_with?(mode, "group-wide")
    input = String.contains?(mode, "-input")
    notice = String.contains?(mode, "notice-input")
    input_loss = String.ends_with?(mode, "-owner-loss")
    paths = for n <- 1..if(wide, do: 132, else: 6), do: path(root, n)
    parent = self()
    bound = String.starts_with?(mode, "bound-")
    loss = String.contains?(mode, "loss-")

    extra_paths =
      if wide,
        do: [hd(paths) | Enum.drop(paths, 4)],
        else: [Enum.at(paths, 0), Enum.at(paths, 4), Enum.at(paths, 5)]

    extras =
      for {path, index} <- Enum.with_index(extra_paths) do
        Task.async(fn ->
          cond do
            (mode in ["actual-session", "actual-journal", "actual-source"] or bound) and
                index == 0 ->
              session_owner(parent, path)

            mode in ["actual-journal", "actual-source"] and index == 1 ->
              management_owner(parent, self(), path)

            mode == "actual-source" and index == 2 ->
              source_owner(parent, self(), path)

            bound and index == 1 ->
              acceptance_owner(parent, self(), fixture)

            bound and index == 2 ->
              bound_source_owner(parent, self(), fixture)

            true ->
              {:ok, cap} = T.acquire(path)
              {:ok, id} = T.retained_share_identity(cap)
              send(parent, {:extra_ready, self(), self(), id, nil})

              receive do
                {:export, operation, recipient, deadline, reply} ->
                  send(
                    reply,
                    {:exported, self(),
                     T.retained_share_export(cap, operation, recipient, deadline)}
                  )

                  receive do
                    :settle ->
                      result = T.retained_share_settle(cap, operation, deadline)
                      send(reply, {:settled, self(), result})

                      if result == :ok do
                        receive do
                          :release -> T.release(cap)
                        after
                          10_000 -> :timeout
                        end
                      else
                        result
                      end
                  after
                    10_000 -> :timeout
                  end
              after
                10_000 -> :timeout
              end
          end
        end)
      end

    prepared =
      for task <- extras do
        receive do
          {:extra_ready, pid, endpoint, id, transport} when pid == task.pid ->
            {id, transport, endpoint}
        after
          5_000 -> raise "extra lease unavailable"
        end
      end

    ids = Enum.map(prepared, &elem(&1, 0))
    endpoints = Enum.map(prepared, &elem(&1, 2))

    result =
      with_triad(mode, fixture, paths, fn caps, locally_acquired ->
        triad =
          Enum.map(caps, fn cap ->
            {:ok, id} = T.retained_share_identity(cap)
            id
          end)

        {:ok, session_control} =
          if notice do
            now = System.monotonic_time(:millisecond)
            job = make_ref()
            intent = %{"operation" => "synthetic grouped review"}

            {:ok, prepared} =
              Runner.prepare_owner_control(
                job,
                intent,
                make_ref(),
                :crypto.strong_rand_bytes(16),
                now + 4_500
              )

            Runner.open_review_notice_owner_control(prepared, self(), job, intent, now + 9_000)
          else
            Runner.open_owner_control()
          end

        {:ok, host_control} = Runner.open_owner_control()

        assert frame(session_control, ?R) ==
                 if(notice, do: "owner-control-v2", else: "owner-control-v1")

        assert frame(host_control, ?R) == "owner-control-v1"

        port =
          Port.open({:spawn_executable, String.to_charlist(helper)}, [
            :binary,
            :exit_status,
            :nouse_stdio,
            :hide,
            args: [
              "--operator-input",
              "5000",
              cond do
                notice -> "v12-synthetic-source-group-notice-input"
                input -> "v11-management-source-group-input"
                String.starts_with?(mode, "group") -> "v10-synthetic-source-group-display"
                true -> "v8-synthetic-accepted-display"
              end
            ]
          ])

        try do
          {:os_pid, pid} = Port.info(port, :os_pid)

          native_clock =
            if input do
              <<clock::64>> = frame(port, ?R)
              clock
            else
              nil
            end

          {:os_pid, spid} = Port.info(session_control, :os_pid)
          {:os_pid, hpid} = Port.info(host_control, :os_pid)
          {:ok, tty} = File.stat("/proc/#{pid}/fd/0")

          control_ids =
            Enum.map([spid, hpid], fn owner ->
              {:ok, stat} = File.stat("/proc/#{owner}/fd/0")
              %{pid: owner, device: stat.major_device, inode: stat.inode}
            end)

          operation = :crypto.strong_rand_bytes(16)
          distinct = elem(hd(prepared), 1) || :crypto.strong_rand_bytes(16)
          deadline = System.monotonic_time(:millisecond) + 4_000
          all_ids = [hd(ids)] ++ triad ++ Enum.drop(ids, 1)

          bindings =
            Enum.map(
              control_ids ++ all_ids,
              &{&1, :crypto.strong_rand_bytes(16), :crypto.strong_rand_bytes(32)}
            )

          [session_binding, host_binding | lease_bindings] = bindings
          count = length(all_ids)
          slots = [0, 0, 1, 2] ++ List.duplicate(0, count - 4)
          journal_transport = elem(Enum.at(prepared, 1), 1) || operation

          operations =
            [distinct, operation, operation, operation, journal_transport] ++
              List.duplicate(operation, count - 5)

          entries =
            Enum.zip([slots, operations, lease_bindings])
            |> Enum.map(fn {slot, op, binding} ->
              <<slot, op::binary, entry(binding)::binary>>
            end)
            |> IO.iodata_to_binary()

          marker =
            if input,
              do:
                "Synthetic grouped review.\nType pin 0123456789abcdef to confirm, or anything else to cancel.\n> ",
              else: "SYNTHETIC_ACCEPTED_LEASE_DISPLAY"

          expiry =
            min(
              System.system_time(:millisecond) + 4_000,
              Process.get({__MODULE__, :accepted_deadline}, 9_007_199_254_740_991)
            )

          suffix =
            if input,
              do:
                <<expiry::64, native_clock + 4_000::64, expiry::64, native_clock + 4_000::64,
                  byte_size(marker)::32, marker::binary>>,
              else: <<expiry::64, byte_size(marker)::32, marker::binary>>

          body =
            <<operation::binary, count, entry(session_binding)::binary,
              entry(host_binding)::binary, entries::binary, tty.major_device::64, tty.inode::64,
              tty.minor_device::64, suffix::binary>>

          :ok = send_frame(port, ?I, body)
          assert frame(port, ?H) == <<operation::binary, count>>
          :ok = configure(session_control, operation, :session, pid, session_binding)
          :ok = configure(host_control, operation, :host, pid, host_binding)
          {first, first_binding} = {hd(endpoints), hd(lease_bindings)}
          send(first, {:export, distinct, recipient(pid, first_binding), deadline, self()})
          assert_receive {:exported, ^first, :ok}, 5_000

          for {cap, binding} <- Enum.zip(caps, Enum.slice(lease_bindings, 1, 3)) do
            assert :ok =
                     T.retained_share_export(
                       cap,
                       operation,
                       recipient(pid, binding),
                       deadline
                     )
          end

          for {endpoint, binding, transfer} <-
                Enum.zip([
                  Enum.drop(endpoints, 1),
                  Enum.drop(lease_bindings, 4),
                  Enum.drop(operations, 4)
                ]) do
            send(endpoint, {:export, transfer, recipient(pid, binding), deadline, self()})
            assert_receive {:exported, ^endpoint, :ok}, 5_000
          end

          assert <<^operation::binary-size(16), ^count, _reader::32>> = frame(port, ?L)

          if loss do
            case mode
                 |> String.replace_prefix("bound-", "")
                 |> String.replace_prefix("group-", "")
                 |> String.replace_prefix("wide-", "") do
              "loss-session-control" ->
                :ok = Runner.close_owner_control(session_control)

              "loss-host-control" ->
                :ok = Runner.close_owner_control(host_control)

              owner ->
                lost =
                  case owner do
                    "loss-session" -> hd(ids).pid
                    "loss-collection" -> hd(triad).pid
                    "loss-journal" -> Enum.at(ids, 1).pid
                    "loss-source" -> List.last(ids).pid
                    "loss-middle" -> Enum.at(ids, 64).pid
                  end

                assert {_, 0} = System.cmd("/bin/kill", ["-KILL", Integer.to_string(lost)])
            end

            assert_receive {^port, {:exit_status, status}} when status != 0, 5_000
            IO.puts("SIX_LEASE_OWNER_LOSS_REFUSED")
          else
            :ok = send_frame(port, ?A, body)
            assert frame(port, ?D) == <<operation::binary, count>>
            assert Port.command(port, <<?C, operation::binary>>)
            send(first, :settle)
            assert_receive {:settled, ^first, :ok}, 5_000

            Enum.each(caps, fn cap ->
              assert :ok = T.retained_share_settle(cap, operation, deadline)
            end)

            for endpoint <- Enum.drop(endpoints, 1) do
              send(endpoint, :settle)
              assert_receive {:settled, ^endpoint, :ok}, 5_000
            end

            assert frame(port, ?C) == <<operation::binary, count>>

            if notice,
              do: assert(frame(session_control, ?N) == <<operation::binary, 1, expiry::64>>)

            assert Port.command(port, <<?U, operation::binary>>)
            if notice, do: assert(frame(session_control, ?F) == <<operation::binary, 1>>)

            if input_loss do
              wait_until = System.monotonic_time(:millisecond) + 3_000

              wait = fn wait ->
                cond do
                  File.exists?(Path.join(root, "group-input-ready")) ->
                    :ok

                  System.monotonic_time(:millisecond) >= wait_until ->
                    :timeout

                  true ->
                    Process.sleep(5)
                    wait.(wait)
                end
              end

              assert wait.(wait) == :ok
              :ok = Runner.close_owner_control(session_control)
              assert_receive {^port, {:exit_status, status}} when status != 0, 5_000
            else
              if input do
                assert frame(port, ?i) == operation <> "pin 0123456789abcdef"
                assert frame(port, ?z) == operation
              end

              assert_receive {^port, {:exit_status, 0}}, 5_000
            end

            if locally_acquired,
              do: Enum.each(Enum.reverse(caps), fn cap -> assert :ok = T.release(cap) end)

            Enum.each(endpoints, &send(&1, :release))

            IO.puts(
              if(input_loss,
                do: "GROUP_INPUT_OWNER_LOSS_REFUSED",
                else: "SIX_LEASE_SYNTHETIC_PASSED"
              )
            )
          end
        after
          if Port.info(port), do: Port.close(port)
          if Port.info(session_control), do: Runner.close_owner_control(session_control)
          if Port.info(host_control), do: Runner.close_owner_control(host_control)
        end

        {:ok, :finished}
      end)

    if bound and loss do
      assert match?({:unknown, _}, result) or match?({:error, _}, result)
    else
      assert {:ok, :finished} = result
    end

    unless loss do
      Enum.each(extras, fn task -> assert Task.await(task, 5_000) in [:ok, {:closed, :ok}] end)
    end
  end

  def with_triad("bound-" <> _, fixture, _paths, fun) do
    alias Ipse.Extension.{Consent, ProjectIdentity, SemanticAdmission}
    alias Ipse.Extension.Collection.ObservedRead
    alias Ipse.Session.PendingAcceptance

    event = fixture["event"]
    recipe = fixture["recipe"]
    scope = %{namespace: fixture["namespace"], format: "managed-metadata-v3"}

    ProjectIdentity.with_existing_domain_auth(
      fixture["home"],
      fixture["cwd"],
      fixture["binding"],
      scope,
      fn cap, catalog ->
        Consent.with_policy(
          SemanticAdmission.control_root(fixture["home"]),
          fixture["project"],
          fixture["current_epoch"] || event["facts"]["capture_epoch"],
          fixture["current_policy_sha256"] || event["facts"]["policy_sha256"],
          System.system_time(:millisecond),
          fn snapshot ->
            ObservedRead.with_accepted_decision(
              SemanticAdmission.collection_root(fixture["home"]),
              fixture["namespace"],
              event,
              cap,
              catalog,
              recipe,
              System.system_time(:millisecond),
              fn observed ->
                assert observed["link"]["value"] === fixture["link"]

                assert {:ok, accepted_deadline} =
                         PendingAcceptance.accepted_use_policy(
                           event,
                           observed["metadata"],
                           snapshot["policy"],
                           recipe,
                           System.system_time(:millisecond)
                         )

                {:ok, caps} = T.retained_share_stack()

                accepted_deadline =
                  if System.get_env("IPSE_BOUND_EXPIRE_BEFORE_ACTIVATION") == "1",
                    do: min(accepted_deadline, System.system_time(:millisecond) + 1_500),
                    else: accepted_deadline

                previous = Process.put({__MODULE__, :accepted_deadline}, accepted_deadline)

                try do
                  fun.(caps, false)
                after
                  if is_nil(previous),
                    do: Process.delete({__MODULE__, :accepted_deadline}),
                    else: Process.put({__MODULE__, :accepted_deadline}, previous)
                end
              end
            )
          end
        )
      end
    )
  end

  def with_triad(_, _, paths, fun) do
    caps =
      for path <- Enum.slice(paths, 1, 3) do
        {:ok, cap} = T.acquire(path)
        cap
      end

    fun.(caps, true)
  end

  def acceptance_owner(parent, caller, fixture) do
    alias Ipse.Session.PendingAcceptance, as: A

    A.with_shareable_committed_management_journal(
      fixture["home"],
      fixture["project"],
      fixture["namespace"],
      fixture["link"],
      fn resolved, token ->
        true = resolved.event === fixture["event"]
        {:ok, identity} = A.journal_share_identity(token)
        send(parent, {:extra_ready, caller, self(), identity, nil})
        share_token(parent, token, &A.journal_share_export/4, &A.journal_share_settle/3)
      end
    )
  end

  def bound_source_owner(parent, caller, fixture) do
    alias Ipse.Session.StoredSources, as: S

    context = %{
      history_dir: fixture["history_dir"],
      session_id: fixture["event"]["facts"]["journal_id"],
      config: %{semantic_admission: fixture["admission"]}
    }

    proof = fixture["event"]["facts"]["source_proof"]

    S.with_shareable_verified(context, proof, fn source, token ->
      true = source["proof"] === proof
      {:ok, identity} = S.share_identity(token)
      send(parent, {:extra_ready, caller, self(), identity, nil})
      share_token(parent, token, &S.share_export/4, &S.share_settle/3)
    end)
  end

  defp share_token(_parent, token, export, settle) do
    receive do
      {:export, operation, recipient, deadline, reply} ->
        result = export.(token, operation, recipient, deadline)
        send(reply, {:exported, self(), result})

        receive do
          :settle ->
            result = settle.(token, operation, deadline)
            send(reply, {:settled, self(), result})

            receive do
              :release -> :ok
            after
              10_000 -> :timeout
            end

          :release ->
            :cancelled
        after
          10_000 -> :timeout
        end
    after
      10_000 -> :timeout
    end
  end

  defp source_owner(parent, caller, path) do
    alias Ipse.{JSON, Journal, Usage}
    alias Ipse.Session.{Input, Saved, SourceIndex, SourceWindow, StoredSources}
    alias Ipse.Test.ManagedPolicy, as: F

    directory = Path.join(Path.dirname(path), "history")
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)
    id = Usage.id()
    binding = F.binding()

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
        "namespace" => JSON.digest(["synthetic source namespace"])
      })

    {:ok, selectors} = Ipse.Extension.SemanticRoutes.selectors(F.policy()["settings"]["routes"])

    admission = %{
      "version" => 1,
      "binding" => binding,
      "instance" => "knowledge",
      "pin" => pin,
      "selectors" => selectors,
      "status" => "active"
    }

    true = Ipse.Extension.SemanticAdmission.valid?(admission, id)

    {:ok, ^id} =
      Journal.create_with_id(directory, id, %{
        "source_layout" => SourceWindow.layout(),
        "source_origin_layout" => Ipse.Journal.SourceOrigin.layout(),
        "semantic_admission" => admission
      })

    text = "Synthetic original source for six-lease control"
    :ok = Journal.append(directory, id, Input.received(id, Usage.id(), text, text, nil))

    :ok =
      Journal.append(directory, id, %{
        "type" => "message",
        "message" => %{"role" => "user", "content" => text}
      })

    {:ok, events} = Journal.load(directory, id)
    {:ok, saved} = Saved.restore(events, id)
    {:ok, page} = SourceIndex.list(saved.source_window.index, %{"limit" => 1})
    [source] = page["sources"]

    {:ok, %{"proof" => proof}} =
      SourceIndex.resolve_proof(saved.source_window.index, %{
        "handle" => source["read_handle"],
        "quote" => text
      })

    {:ok, lock} = Runner.lock(Path.join(directory, id <> ".lock"))
    :ok = Runner.unlock(lock)

    context = %{
      history_dir: directory,
      session_id: Usage.id(),
      config: %{semantic_admission: admission}
    }

    StoredSources.with_shareable_verified(context, proof, fn source, token ->
      true = source["proof"] === proof
      {:ok, identity} = StoredSources.share_identity(token)
      send(parent, {:extra_ready, caller, self(), identity, nil})

      receive do
        {:export, operation, recipient, deadline, reply} ->
          result = StoredSources.share_export(token, operation, recipient, deadline)
          send(reply, {:exported, self(), result})

          receive do
            :settle ->
              result = StoredSources.share_settle(token, operation, deadline)
              send(reply, {:settled, self(), result})

              receive do
                :release -> :ok
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

  defp management_owner(parent, caller, path) do
    root = Path.dirname(path)
    home = Path.join(root, "home")
    cwd = Path.join(root, "work")
    File.mkdir!(home)
    File.chmod!(home, 0o700)
    File.mkdir!(cwd)
    {:ok, _} = Ipse.Extension.ProjectIdentity.admit(home, cwd, :folder)

    Ipse.CLI.Knowledge.Management.share_journal_candidate(%{home: home}, cwd, fn owned ->
      operation = :crypto.strong_rand_bytes(16)

      request =
        Ipse.Journal.Writer.request_share_barrier(owned.writer, operation, make_ref(), make_ref())

      {:reply, {:ok, token, _}} = :gen_server.receive_response(request, 5_000)
      arm = Ipse.Session.Lock.request_share_arm(owned.guard, owned.writer, token, operation)
      {:reply, {:ok, transport}} = :gen_server.receive_response(arm, 5_000)
      port = GenServer.call(owned.guard, :port)
      {:os_pid, native} = Port.info(port, :os_pid)
      stat = File.stat!(Path.join(owned.directory, owned.id <> ".lock"))
      id = %{pid: native, device: stat.major_device, inode: stat.inode}
      send(parent, {:extra_ready, caller, self(), id, transport})

      receive do
        {:export, ^transport, recipient, deadline, reply} ->
          request =
            Ipse.Session.Lock.request_share_export(
              owned.guard,
              token,
              operation,
              recipient,
              deadline
            )

          {:reply, result} = :gen_server.receive_response(request, 5_000)
          send(reply, {:exported, self(), result})

          receive do
            :settle ->
              request =
                Ipse.Session.Lock.request_share_settle(owned.guard, token, operation, deadline)

              {:reply, result} = :gen_server.receive_response(request, 5_000)
              send(reply, {:settled, self(), result})

              receive do
                :release -> Ipse.Journal.Writer.thaw_share_barrier(owned.writer, token, operation)
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

  defp session_owner(parent, path) do
    root = Path.dirname(path)
    dir = Path.join(root, "sessions")

    opts = [
      config: %{
        provider: :demo,
        provider_module: Model,
        model: "fixture",
        home: root,
        approval: :deny,
        observability: Map.put(Ipse.Observability.defaults(), "mode", "local")
      },
      cwd: root,
      state_dir: dir,
      subscriber: self()
    ]

    {:ok, session} = Ipse.Session.start_share_candidate_link(opts)
    Process.unlink(session)
    state = :sys.get_state(session)
    operation = :crypto.strong_rand_bytes(16)
    job = make_ref()
    generation = make_ref()
    owner = self()

    :sys.replace_state(session, fn s ->
      request =
        Ipse.Journal.Writer.request_share_barrier(s.journal_writer, operation, job, generation)

      {:reply, {:ok, token, _}} = :gen_server.receive_response(request, 5_000)
      arm = Ipse.Session.Lock.request_share_arm(s.lock_guard, s.journal_writer, token, operation)
      {:reply, {:ok, transport}} = :gen_server.receive_response(arm, 5_000)
      send(owner, {:armed, token, transport})
      s
    end)

    {token, transport} =
      receive do
        {:armed, token, transport} -> {token, transport}
      after
        5_000 -> raise "session share not armed"
      end

    {:os_pid, native} = Port.info(state.lock, :os_pid)
    stat = File.stat!(Path.join(dir, state.id <> ".lock"))
    id = %{pid: native, device: stat.major_device, inode: stat.inode}
    send(parent, {:extra_ready, self(), self(), id, transport})

    receive do
      {:export, ^transport, recipient, deadline, reply} ->
        :sys.replace_state(session, fn s ->
          request =
            Ipse.Session.Lock.request_share_export(
              s.lock_guard,
              token,
              operation,
              recipient,
              deadline
            )

          send(owner, {:export_response, :gen_server.receive_response(request, 5_000)})
          s
        end)

        receive do
          {:export_response, {:reply, result}} -> send(reply, {:exported, self(), result})
        after
          5_000 -> raise "session export unavailable"
        end

        receive do
          :settle ->
            :sys.replace_state(session, fn s ->
              request =
                Ipse.Session.Lock.request_share_settle(s.lock_guard, token, operation, deadline)

              result = :gen_server.receive_response(request, 5_000)
              send(owner, {:settle_response, result})
              s
            end)

            receive do
              {:settle_response, {:reply, result}} -> send(reply, {:settled, self(), result})
            after
              5_000 -> raise "session settlement unavailable"
            end

            receive do
              :release ->
                :sys.replace_state(session, fn s ->
                  result =
                    Ipse.Journal.Writer.thaw_share_barrier(s.journal_writer, token, operation)

                  send(owner, {:thawed, result})
                  s
                end)

                receive do
                  {:thawed, :ok} -> Ipse.Session.close_confirmed(session)
                after
                  5_000 -> :timeout
                end
            after
              10_000 -> :timeout
            end
        after
          10_000 -> :timeout
        end
    after
      10_000 -> :timeout
    end
  end

  defp path(root, n) do
    dir = Path.join(root, Integer.to_string(n))
    File.mkdir!(dir)
    File.chmod!(dir, 0o700)
    Path.join(dir, ".lock")
  end

  defp entry({id, name, secret}),
    do: <<id.pid::32, name::binary, secret::binary, id.device::64, id.inode::64>>

  defp recipient(pid, {id, name, secret}),
    do: <<pid::32, name::binary, secret::binary, id.device::64, id.inode::64>>

  defp configure(port, op, role, pid, {_, name, secret}) do
    :ok = Runner.send_owner_control(port, op, role, pid, name, secret)
    role_id = if role == :session, do: 1, else: 2
    assert frame(port, ?H) == <<op::binary, role_id>>
    assert frame(port, ?T) == <<op::binary, role_id>>
    :ok
  end

  defp send_frame(port, tag, body) do
    if Port.command(port, <<tag, byte_size(body)::32, body::binary>>), do: :ok, else: :error
  end

  defp frame(port, tag) do
    key = {__MODULE__, port}
    read_frame(port, tag, key, Process.get(key, <<>>))
  end

  defp read_frame(_port, tag, key, <<tag, size::32, body::binary-size(size), tail::binary>>) do
    Process.put(key, tail)
    body
  end

  defp read_frame(port, tag, key, buffer) do
    receive do
      {^port, {:data, bytes}} -> read_frame(port, tag, key, buffer <> bytes)
      {^port, other} -> raise "probe exited: #{inspect(other)}"
    after
      5_000 -> raise "probe frame #{tag} timed out"
    end
  end
end

if System.get_env("IPSE_ACCEPTED_LEASE_MODULE_ONLY") != "1" do
  [helper, root, original_ebin, mode | extra] = System.argv()
  isolated = Path.join(root <> "-runtime", "ipse")
  ebin = Path.join(isolated, "ebin")
  File.mkdir_p!(isolated)
  File.cp_r!(original_ebin, ebin)
  File.mkdir!(Path.join(isolated, "priv"))
  isolated_helper = Path.join(isolated, "priv/ipse-runner")
  File.cp!(helper, isolated_helper)
  source = File.read!("lib/ipse/runner.ex")
  source_path = Path.join(isolated, "lib/ipse/runner.ex")
  File.mkdir_p!(Path.dirname(source_path))
  File.write!(source_path, source)
  true = :code.replace_path(:ipse, String.to_charlist(ebin))
  Code.compiler_options(ignore_module_conflict: true)
  [{Ipse.Runner, beam}] = Code.compile_string(source, source_path)
  File.write!(Path.join(ebin, "Elixir.Ipse.Runner.beam"), beam)

  fixture =
    case extra do
      [path] -> path |> File.read!() |> Jason.decode!()
      [] -> nil
    end

  AcceptedLeasePositive.run(isolated_helper, root, mode, fixture)
end
