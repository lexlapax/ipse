Code.require_file("../../support/managed_policy.exs", __DIR__)

defmodule Ipse.Session.StoredSourcesTest do
  use ExUnit.Case, async: false
  alias Ipse.{Journal, JSON, Runner, Usage}
  alias Ipse.Session.{Input, Saved, SourceIndex, SourceWindow, StoredSources}
  alias Ipse.Test.ManagedPolicy, as: F

  defmodule LocalSourceOwner do
    use GenServer

    def start_link(mode), do: GenServer.start_link(__MODULE__, mode)
    def init(mode), do: {:ok, {mode, 0}}

    def handle_call(
          {:managed_sources, _, _, proofs},
          _from,
          {{:indexes, before, after_use}, count}
        ) do
      index = if count == 0, do: before, else: after_use

      result =
        Enum.reduce_while(proofs, {:ok, []}, fn proof, {:ok, rows} ->
          case SourceIndex.revalidate_stored(index, proof) do
            {:ok, row} -> {:cont, {:ok, rows ++ [row]}}
            error -> {:halt, error}
          end
        end)

      {:reply, result, {{:indexes, before, after_use}, count + 1}}
    end

    def handle_call({:managed_sources, _, _, proofs}, _from, {mode, count}) do
      result = Enum.map(proofs, &%{"proof" => &1})
      result = if mode == :change_after and count > 0, do: [], else: result
      {:reply, {:ok, result}, {mode, count + 1}}
    end
  end

  setup do
    directory = Path.join(System.tmp_dir!(), "ipse-retained-source-" <> Usage.id())
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)
    on_exit(fn -> File.rm_rf!(directory) end)
    id = Usage.id()
    binding = F.binding()
    namespace = JSON.digest(["synthetic source namespace"])

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

    assert {:ok, selectors} =
             Ipse.Extension.SemanticRoutes.selectors(F.policy()["settings"]["routes"])

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

    text = "Synthetic source retained during a read"
    assert :ok = Journal.append(directory, id, Input.received(id, Usage.id(), text, text, nil))

    assert :ok =
             Journal.append(directory, id, %{
               "type" => "message",
               "message" => %{"role" => "user", "content" => text}
             })

    assert {:ok, events} = Journal.load(directory, id)
    assert {:ok, saved} = Saved.restore(events, id)
    assert {:ok, page} = SourceIndex.list(saved.source_window.index, %{"limit" => 1})
    [source] = page["sources"]

    assert {:ok, %{"proof" => proof}} =
             SourceIndex.resolve_proof(saved.source_window.index, %{
               "handle" => source["read_handle"],
               "quote" => text
             })

    assert {:ok, %{"proof" => short_proof}} =
             SourceIndex.resolve_proof(saved.source_window.index, %{
               "handle" => source["read_handle"],
               "quote" => "Synthetic source"
             })

    lock_path = Path.join(directory, id <> ".lock")
    assert {:ok, lock} = Runner.lock(lock_path)
    assert :ok = Runner.unlock(lock)

    second_id = Usage.id()
    second_admission = put_in(admission, ["pin", "session_id"], second_id)

    assert {:ok, ^second_id} =
             Journal.create_with_id(directory, second_id, %{
               "source_layout" => SourceWindow.layout(),
               "source_origin_layout" => Ipse.Journal.SourceOrigin.layout(),
               "semantic_admission" => second_admission
             })

    second_text = "A separate synthetic original session"

    assert :ok =
             Journal.append(
               directory,
               second_id,
               Input.received(second_id, Usage.id(), second_text, second_text, nil)
             )

    assert :ok =
             Journal.append(directory, second_id, %{
               "type" => "message",
               "message" => %{"role" => "user", "content" => second_text}
             })

    assert {:ok, second_events} = Journal.load(directory, second_id)
    assert {:ok, second_saved} = Saved.restore(second_events, second_id)

    assert {:ok, second_page} =
             SourceIndex.list(second_saved.source_window.index, %{"limit" => 1})

    [second_source] = second_page["sources"]

    assert {:ok, %{"proof" => second_proof}} =
             SourceIndex.resolve_proof(second_saved.source_window.index, %{
               "handle" => second_source["read_handle"],
               "quote" => second_text
             })

    second_lock_path = Path.join(directory, second_id <> ".lock")
    assert {:ok, lock} = Runner.lock(second_lock_path)
    assert :ok = Runner.unlock(lock)

    context = %{
      history_dir: directory,
      session_id: Usage.id(),
      config: %{semantic_admission: admission}
    }

    %{
      context: context,
      proof: proof,
      short_proof: short_proof,
      second_proof: second_proof,
      second_lock_path: second_lock_path,
      lock_path: lock_path,
      journal_path: Path.join(directory, id <> ".jsonl"),
      index: saved.source_window.index
    }
  end

  test "bound result publication can append sources without invalidating selected originals", c do
    text = "A newly committed source"
    input = Input.received(c.proof["session_id"], Usage.id(), text, text, nil)
    message = %{"type" => "message", "message" => %{"role" => "user", "content" => text}}
    assert {:ok, appended} = SourceIndex.admit_input(c.index, input, message)
    assert appended.generation > c.index.generation
    assert {:ok, owner} = LocalSourceOwner.start_link({:indexes, c.index, appended})

    context = active_context(c, owner, "tool.result")

    assert :published =
             StoredSources.with_verified(context, nil, [c.proof], fn [_] -> :published end)
  end

  test "active result postcheck refuses policy fences, redaction, window replacement and rollback",
       c do
    assert {:ok, fenced} = SourceIndex.revalidate(c.index, c.index.policy_generation + 1)

    assert {:ok, redacted} =
             SourceIndex.redact(c.index, c.proof["occurrence_id"], c.index.policy_generation + 1)

    for changed <- [
          fenced,
          redacted,
          %{c.index | window_id: Usage.id()},
          %{c.index | generation: c.index.generation - 1}
        ] do
      assert {:ok, owner} = LocalSourceOwner.start_link({:indexes, c.index, changed})
      context = active_context(c, owner, "tool.result")

      assert {:error, :collection_source_refused} =
               StoredSources.with_verified(context, nil, [c.proof], fn [_] -> :must_not_escape end)

      GenServer.stop(owner)
    end
  end

  test "source append still invalidates approval and effect scopes", c do
    text = "Another committed source"
    input = Input.received(c.proof["session_id"], Usage.id(), text, text, nil)
    message = %{"type" => "message", "message" => %{"role" => "user", "content" => text}}
    assert {:ok, appended} = SourceIndex.admit_input(c.index, input, message)

    for purpose <- ["tool.approval", "tool.effect"] do
      assert {:ok, owner} = LocalSourceOwner.start_link({:indexes, c.index, appended})

      assert {:error, :collection_source_refused} =
               StoredSources.with_verified(active_context(c, owner, purpose), nil, [c.proof], fn [
                                                                                                   _
                                                                                                 ] ->
                 :must_not_escape
               end)

      GenServer.stop(owner)
    end
  end

  defp active_context(c, owner, purpose) do
    c.context
    |> Map.put(:session_id, c.proof["session_id"])
    |> Map.put(:owner, owner)
    |> Map.put(:job_ref, make_ref())
    |> Map.put(:source_binding, {:snapshot, purpose, JSON.sha256("bound result fixture")})
  end

  test "grouped source leases hold both inactive sessions and preserve proof order", c do
    assert :verified =
             StoredSources.with_shareable_groups(
               c.context,
               [c.second_proof, c.proof, c.short_proof],
               fn sources, tokens ->
                 assert Enum.map(sources, & &1["proof"]) == [
                          c.second_proof,
                          c.proof,
                          c.short_proof
                        ]

                 assert Enum.map(tokens, & &1.session_id) ==
                          Enum.sort([c.proof["session_id"], c.second_proof["session_id"]])

                 assert length(Enum.uniq_by(tokens, & &1.token)) == 2

                 for %{token: token} <- tokens,
                     do: assert({:ok, _} = StoredSources.share_identity(token))

                 assert {:error, _} = Runner.lock(c.lock_path)
                 assert {:error, _} = Runner.lock(c.second_lock_path)
                 :verified
               end
             )

    for path <- [c.lock_path, c.second_lock_path] do
      assert {:ok, lock} = Runner.lock(path)
      assert :ok = Runner.unlock(lock)
    end
  end

  test "active and inactive proof union preserves exact order and retains inactive owners", c do
    assert {:ok, owner} = LocalSourceOwner.start_link(:stable)

    context =
      c.context
      |> Map.put(:session_id, c.proof["session_id"])
      |> Map.put(:owner, owner)
      |> Map.put(:job_ref, make_ref())
      |> Map.put(:source_binding, {:supersession, JSON.sha256("fixture")})

    proofs = [c.second_proof, c.proof, c.short_proof]

    assert :verified =
             StoredSources.with_shareable_union(context, nil, proofs, fn sources,
                                                                         tokens,
                                                                         active? ->
               assert Enum.map(sources, & &1["proof"]) === proofs
               assert active?
               assert [%{session_id: id, token: token}] = tokens
               assert id === c.second_proof["session_id"]
               assert {:ok, _} = StoredSources.share_identity(token)
               assert {:error, _} = Runner.lock(c.second_lock_path)
               :verified
             end)

    assert {:ok, lock} = Runner.lock(c.second_lock_path)
    assert :ok = Runner.unlock(lock)
  end

  test "active proof change after a union callback withholds its result", c do
    assert {:ok, owner} = LocalSourceOwner.start_link(:change_after)

    context =
      c.context
      |> Map.put(:session_id, c.proof["session_id"])
      |> Map.put(:owner, owner)
      |> Map.put(:job_ref, make_ref())
      |> Map.put(:source_binding, {:supersession, JSON.sha256("fixture")})

    assert {:error, :collection_source_refused} =
             StoredSources.with_shareable_union(context, nil, [c.proof, c.second_proof], fn _,
                                                                                            _,
                                                                                            _ ->
               :must_not_escape
             end)

    assert {:ok, lock} = Runner.lock(c.second_lock_path)
    assert :ok = Runner.unlock(lock)
  end

  test "source union refuses duplicates and handles active-only and inactive-only sets", c do
    assert {:ok, owner} = LocalSourceOwner.start_link(:stable)

    active =
      c.context
      |> Map.put(:session_id, c.proof["session_id"])
      |> Map.put(:owner, owner)
      |> Map.put(:job_ref, make_ref())
      |> Map.put(:source_binding, {:supersession, JSON.sha256("fixture")})

    assert :active =
             StoredSources.with_shareable_union(active, nil, [c.proof], fn [source],
                                                                           tokens,
                                                                           active? ->
               assert source["proof"] === c.proof and tokens == [] and active?
               :active
             end)

    assert :inactive =
             StoredSources.with_shareable_union(active, nil, [c.second_proof], fn [source],
                                                                                  tokens,
                                                                                  active? ->
               assert source["proof"] === c.second_proof and length(tokens) == 1 and not active?
               :inactive
             end)

    assert {:error, :collection_source_refused} =
             StoredSources.with_shareable_union(active, nil, [c.proof, c.proof], fn _, _, _ ->
               flunk("duplicate proof admitted")
             end)
  end

  test "losing either grouped source owner withholds the callback result", c do
    for lost_id <- [c.proof["session_id"], c.second_proof["session_id"]] do
      assert {:error, :collection_source_refused} =
               StoredSources.with_shareable_groups(c.context, [c.proof, c.second_proof], fn _,
                                                                                            tokens ->
                 %{token: token} = Enum.find(tokens, &(&1.session_id == lost_id))
                 assert {:ok, %{pid: pid}} = StoredSources.share_identity(token)
                 port = Enum.find(Port.list(), &(Port.info(&1, :os_pid) == {:os_pid, pid}))
                 assert is_port(port)
                 monitor = :erlang.monitor(:port, port)

                 assert {_, 0} =
                          System.cmd("kill", ["-KILL", Integer.to_string(pid)],
                            stderr_to_stdout: true
                          )

                 assert_receive {:DOWN, ^monitor, :port, ^port, _}, 5_000
                 :must_not_escape
               end)

      for path <- [c.lock_path, c.second_lock_path] do
        assert {:ok, lock} = Runner.lock(path)
        assert :ok = Runner.unlock(lock)
      end
    end
  end

  test "two grouped sources transfer and settle through one native collector", c do
    assert :transferred =
             StoredSources.with_shareable_groups(c.context, [c.proof, c.second_proof], fn _,
                                                                                          tokens ->
               {collector, pid} = source_collector()
               operation = :crypto.strong_rand_bytes(16)

               bindings =
                 Enum.map(tokens, fn %{token: token} ->
                   assert {:ok, identity} = StoredSources.share_identity(token)
                   {token, identity, :crypto.strong_rand_bytes(16), :crypto.strong_rand_bytes(32)}
                 end)

               entries =
                 bindings
                 |> Enum.map(fn {_, identity, name, secret} ->
                   <<0, identity.pid::32, name::binary, secret::binary, identity.device::64,
                     identity.inode::64>>
                 end)
                 |> IO.iodata_to_binary()

               initial = <<5_000::64, operation::binary, 2, entries::binary>>
               assert Port.command(collector, <<?I, byte_size(initial)::32, initial::binary>>)
               assert source_frame(collector, ?H) == <<operation::binary, 2>>
               deadline = System.monotonic_time(:millisecond) + 5_000

               for {token, identity, name, secret} <- bindings do
                 recipient =
                   <<pid::32, name::binary, secret::binary, identity.device::64,
                     identity.inode::64>>

                 assert :ok = StoredSources.share_export(token, operation, recipient, deadline)
               end

               assert source_frame(collector, ?L) == <<operation::binary, 2>>
               assert Port.command(collector, <<?C, operation::binary>>)

               for {token, _, _, _} <- bindings,
                   do: assert(:ok = StoredSources.share_settle(token, operation, deadline))

               assert source_frame(collector, ?C) == <<operation::binary, 2>>
               assert_receive {^collector, {:exit_status, 0}}, 5_000
               :transferred
             end)
  end

  test "one shareable original lease covers exact proofs from the same session", c do
    assert :verified =
             StoredSources.with_shareable_verified_many(c.context, [c.proof, c.short_proof], fn
               sources, token ->
                 assert Enum.map(sources, & &1["proof"]) == [c.proof, c.short_proof]
                 assert {:ok, _} = StoredSources.share_identity(token)

                 assert {:ok, bound} =
                          StoredSources.share_verified_identity(token, [c.proof, c.short_proof])

                 assert bound.session_id == c.proof["session_id"]
                 assert bound.proofs_sha256 == JSON.digest([c.proof, c.short_proof])

                 assert {:error, _} =
                          StoredSources.share_verified_identity(token, [c.short_proof, c.proof])

                 assert {:error, _} = StoredSources.share_verified_identity(token, [c.proof])

                 assert {:error, _} =
                          StoredSources.share_verified_identity(token, [c.proof, c.second_proof])

                 assert {:error, _} =
                          Task.async(fn ->
                            StoredSources.share_verified_identity(token, [c.proof, c.short_proof])
                          end)
                          |> Task.await()

                 assert {:error, _} = Runner.lock(c.lock_path)
                 :verified
             end)

    assert {:ok, lock} = Runner.lock(c.lock_path)
    assert :ok = Runner.unlock(lock)
  end

  test "grouped source identities cannot be swapped between original sessions", c do
    assert :ok =
             StoredSources.with_shareable_groups(c.context, [c.proof, c.second_proof], fn _,
                                                                                          leases ->
               proofs = %{
                 c.proof["session_id"] => [c.proof],
                 c.second_proof["session_id"] => [c.second_proof]
               }

               for %{session_id: id, token: token} <- leases do
                 assert {:ok, %{session_id: ^id}} =
                          StoredSources.share_verified_identity(token, Map.fetch!(proofs, id))

                 other = if id == c.proof["session_id"], do: c.second_proof, else: c.proof
                 assert {:error, _} = StoredSources.share_verified_identity(token, [other])
               end

               :ok
             end)
  end

  test "display authority binds the retained transaction stack to exact source proofs", c do
    root = Path.join(c.context.history_dir, "source-display-authority")
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    caps =
      for n <- 1..3 do
        dir = Path.join(root, Integer.to_string(n))
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        {:ok, cap} = Ipse.Runner.Transaction.acquire(Path.join(dir, ".lock"))
        cap
      end

    active = Map.put(c.proof, "session_id", c.context.session_id)

    assert :ok =
             StoredSources.with_shareable_groups(c.context, [c.proof, c.second_proof], fn sources,
                                                                                          leases ->
               verified = [%{"proof" => active} | sources]

               assert {:ok, authority} =
                        Ipse.Session.ManagedSupersession.display_authority(
                          c.context,
                          verified,
                          leases,
                          true
                        )

               assert authority.active_session == c.context.session_id

               assert authority.facts_sources_sha256 ==
                        JSON.digest([active, c.proof, c.second_proof])

               assert Enum.map(authority.owners, & &1.slot) == [0, 1, 2]
               assert length(authority.inactive) == 2

               assert {:error, :managed_supersession_refused} =
                        Ipse.Session.ManagedSupersession.display_authority(
                          c.context,
                          sources,
                          leases,
                          true
                        )

               assert {:error, :managed_supersession_refused} =
                        Ipse.Session.ManagedSupersession.display_authority(
                          c.context,
                          [hd(verified) | verified],
                          leases,
                          true
                        )

               [a, b] = leases
               swapped = [%{a | token: b.token}, %{b | token: a.token}]

               assert {:error, :managed_supersession_refused} =
                        Ipse.Session.ManagedSupersession.display_authority(
                          c.context,
                          verified,
                          swapped,
                          true
                        )

               assert {:error, :managed_supersession_refused} =
                        Ipse.Session.ManagedSupersession.display_authority(
                          c.context,
                          verified,
                          leases,
                          false
                        )

               assert {:error, :managed_supersession_refused} =
                        Ipse.Session.ManagedSupersession.display_authority(
                          c.context,
                          verified,
                          tl(leases),
                          true
                        )

               :ok
             end)

    Enum.each(Enum.reverse(caps), fn cap -> assert :ok = Ipse.Runner.Transaction.release(cap) end)
  end

  test "a shared original lease refuses duplicate, cross-session and active-session proofs", c do
    callback = fn _, _ -> flunk("invalid source set reached the callback") end
    assert {:error, _} = StoredSources.with_shareable_verified_many(c.context, [], callback)

    assert {:error, _} =
             StoredSources.with_shareable_verified_many(c.context, [c.proof, c.proof], callback)

    other = Map.put(c.short_proof, "session_id", Usage.id())

    assert {:error, _} =
             StoredSources.with_shareable_verified_many(c.context, [c.proof, other], callback)

    active = Map.put(c.context, :session_id, c.proof["session_id"])
    assert {:error, _} = StoredSources.with_shareable_verified_many(active, [c.proof], callback)

    assert {:error, _} =
             StoredSources.with_shareable_groups(c.context, [c.proof, c.proof], callback)

    assert {:error, _} =
             StoredSources.with_shareable_groups(active, [c.proof, c.second_proof], callback)

    assert :outer =
             StoredSources.with_shareable_groups(c.context, [c.proof], fn _, _ ->
               assert {:error, _} =
                        StoredSources.with_shareable_groups(c.context, [c.second_proof], callback)

               :outer
             end)
  end

  test "the native retained lock is held through the source callback", c do
    assert :admitted =
             StoredSources.with_verified(c.context, %{}, [c.proof], fn [_] ->
               assert {:error, _} = Runner.lock(c.lock_path)
               :admitted
             end)

    assert {:ok, lock} = Runner.lock(c.lock_path)
    assert :ok = Runner.unlock(lock)
  end

  test "shareable source leases are bound to their owner and close with the source callback", c do
    assert {:ok, token} =
             StoredSources.with_shareable_verified(c.context, c.proof, fn source, token ->
               assert source["proof"] === c.proof

               assert {:ok, %{pid: pid, device: device, inode: inode}} =
                        StoredSources.share_identity(token)

               assert is_integer(pid) and pid > 0
               assert {:ok, stat} = File.stat(c.lock_path)
               assert device == stat.major_device and inode == stat.inode
               assert {:error, _} = Runner.lock(c.lock_path)

               assert {:error, :collection_source_refused} =
                        Task.async(fn -> StoredSources.share_identity(token) end) |> Task.await()

               {:ok, token}
             end)

    assert {:error, :collection_source_refused} = StoredSources.share_identity(token)
    assert {:ok, lock} = Runner.lock(c.lock_path)
    assert :ok = Runner.unlock(lock)

    assert {:error, :collection_source_refused} =
             StoredSources.with_shareable_verified(c.context, c.proof, fn _, token ->
               deadline = System.monotonic_time(:millisecond) + 1_000

               assert {:error, :collection_source_refused} =
                        StoredSources.share_export(token, "invalid", <<>>, deadline)

               assert {:error, :collection_source_refused} = StoredSources.share_identity(token)
               :must_not_escape
             end)

    assert {:ok, lock} = Runner.lock(c.lock_path)
    assert :ok = Runner.unlock(lock)
  end

  test "shareable original source settles an actual native lease transfer", c do
    assert :transferred =
             StoredSources.with_shareable_verified(c.context, c.proof, fn _, token ->
               assert {:ok, identity} = StoredSources.share_identity(token)
               {collector, pid} = source_collector()
               operation = :crypto.strong_rand_bytes(16)
               name = :crypto.strong_rand_bytes(16)
               secret = :crypto.strong_rand_bytes(32)

               entry =
                 <<0, identity.pid::32, name::binary, secret::binary, identity.device::64,
                   identity.inode::64>>

               initial = <<5_000::64, operation::binary, 1, entry::binary>>
               assert Port.command(collector, <<?I, byte_size(initial)::32, initial::binary>>)
               assert source_frame(collector, ?H) == <<operation::binary, 1>>

               recipient =
                 <<pid::32, name::binary, secret::binary, identity.device::64,
                   identity.inode::64>>

               deadline = System.monotonic_time(:millisecond) + 5_000
               assert :ok = StoredSources.share_export(token, operation, recipient, deadline)
               assert source_frame(collector, ?L) == <<operation::binary, 1>>
               assert {:error, _} = Runner.lock(c.lock_path)
               assert Port.command(collector, <<?C, operation::binary>>)
               assert :ok = StoredSources.share_settle(token, operation, deadline)
               assert source_frame(collector, ?C) == <<operation::binary, 1>>
               assert_receive {^collector, {:exit_status, 0}}, 5_000
               :transferred
             end)

    assert {:ok, lock} = Runner.lock(c.lock_path)
    assert :ok = Runner.unlock(lock)
  end

  test "native transaction retains the original source through a root decision", c do
    root = Path.join(c.context.history_dir, "transaction-source")
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    paths =
      for n <- 1..3 do
        dir = Path.join(root, Integer.to_string(n))
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    caps =
      Enum.map(paths, fn path ->
        assert {:ok, cap} = Ipse.Runner.Transaction.acquire(path)
        cap
      end)

    collection = List.last(caps)
    directory = Path.dirname(List.last(paths))
    File.write!(Path.join(directory, "root.json"), "old")
    File.chmod!(Path.join(directory, "root.json"), 0o600)
    stage = ".pending-" <> Usage.id()

    assert {:ok, :switched} =
             StoredSources.with_shareable_verified(c.context, c.proof, fn _, token ->
               Ipse.Runner.Transaction.with_source_lease(collection, token, fn ->
                 assert {:error, _} = Runner.lock(c.lock_path)
                 assert :ok = Ipse.Runner.Transaction.stage(collection, ".", [{stage, "new"}])

                 assert :ok =
                          Ipse.Runner.Transaction.switch_before(
                            collection,
                            stage,
                            "root.json",
                            System.system_time(:millisecond) + 10_000
                          )

                 {:ok, :switched}
               end)
             end)

    assert File.read!(Path.join(directory, "root.json")) == "new"

    Enum.reverse(caps)
    |> Enum.each(fn cap -> assert :ok = Ipse.Runner.Transaction.release(cap) end)

    assert {:ok, lock} = Runner.lock(c.lock_path)
    assert :ok = Runner.unlock(lock)
  end

  test "native transaction retains two original sessions through a root decision", c do
    root = Path.join(c.context.history_dir, "transaction-two-sources")
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    paths =
      for n <- 1..3 do
        dir = Path.join(root, Integer.to_string(n))
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    caps =
      Enum.map(paths, fn path ->
        assert {:ok, cap} = Ipse.Runner.Transaction.acquire(path)
        cap
      end)

    collection = List.last(caps)
    directory = Path.dirname(List.last(paths))
    File.write!(Path.join(directory, "root.json"), "old")
    File.chmod!(Path.join(directory, "root.json"), 0o600)
    stage = ".pending-" <> Usage.id()

    assert {:ok, :switched} =
             StoredSources.with_shareable_groups(c.context, [c.proof, c.second_proof], fn _,
                                                                                          leases ->
               tokens = Enum.map(leases, & &1.token)

               assert {:error, :invalid_transaction_request} =
                        Ipse.Runner.Transaction.with_source_leases(
                          collection,
                          tokens ++ tokens,
                          fn -> :invalid end
                        )

               Ipse.Runner.Transaction.with_source_leases(collection, tokens, fn ->
                 assert {:error, _} = Runner.lock(c.lock_path)
                 assert {:error, _} = Runner.lock(c.second_lock_path)
                 assert :ok = Ipse.Runner.Transaction.stage(collection, ".", [{stage, "new"}])

                 assert :ok =
                          Ipse.Runner.Transaction.switch_before(
                            collection,
                            stage,
                            "root.json",
                            System.system_time(:millisecond) + 10_000
                          )

                 {:ok, :switched}
               end)
             end)

    assert File.read!(Path.join(directory, "root.json")) == "new"

    Enum.reverse(caps)
    |> Enum.each(fn cap -> assert :ok = Ipse.Runner.Transaction.release(cap) end)
  end

  test "native transaction retains two original sources with both owner controls", c do
    root = Path.join(c.context.history_dir, "transaction-controlled-sources")
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    paths =
      for n <- 1..3 do
        dir = Path.join(root, Integer.to_string(n))
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    caps =
      Enum.map(paths, fn path ->
        {:ok, cap} = Ipse.Runner.Transaction.acquire(path)
        cap
      end)

    cap = List.last(caps)
    directory = Path.dirname(List.last(paths))
    File.write!(Path.join(directory, "root.json"), "old")
    File.chmod!(Path.join(directory, "root.json"), 0o600)
    writer = source_test_control(cap, :writer)
    session = source_test_control(cap, :session)

    assert {:ok, :switched} =
             StoredSources.with_shareable_groups(c.context, [c.proof, c.second_proof], fn _,
                                                                                          leases ->
               Ipse.Runner.Transaction.with_source_leases(cap, Enum.map(leases, & &1.token), fn ->
                 assert {:error, _} = Ipse.Runner.Transaction.acceptance_guard(cap)
                 stage = ".pending-" <> Usage.id()
                 assert :ok = Ipse.Runner.Transaction.stage(cap, ".", [{stage, "new"}])

                 assert :ok =
                          Ipse.Runner.Transaction.switch_before(
                            cap,
                            stage,
                            "root.json",
                            System.system_time(:millisecond) + 10_000
                          )

                 {:ok, :switched}
               end)
             end)

    assert File.read!(Path.join(directory, "root.json")) == "new"
    deadline = System.monotonic_time(:millisecond) + 5_000
    assert :ok = GenServer.call(cap.controller, {:session_control_close, cap, deadline})
    assert :ok = GenServer.call(cap.controller, {:writer_control_close, cap, deadline})
    assert_receive {^session, {:exit_status, 0}}, 5_000
    assert_receive {^writer, {:exit_status, 0}}, 5_000
    Enum.each(Enum.reverse(caps), fn c -> assert :ok = Ipse.Runner.Transaction.release(c) end)
  end

  defp source_test_control(cap, kind) do
    {:ok, port} = Runner.open_owner_control()
    assert source_control_frame(port, ?R) == "owner-control-v1"
    {:os_pid, sender} = Port.info(port, :os_pid)
    stat = File.stat!("/proc/#{sender}/fd/0")
    {:ok, %{pid: recipient}} = Ipse.Runner.Transaction.retained_share_identity(cap)
    operation = :crypto.strong_rand_bytes(16)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)
    entry = <<sender::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>
    deadline = System.monotonic_time(:millisecond) + 5_000
    tag = if kind == :writer, do: :writer_control_import, else: :session_control_import
    role = if kind == :writer, do: :host, else: :session
    request = :gen_server.send_request(cap.controller, {tag, cap, operation, entry, deadline})
    assert :ok = Runner.send_owner_control(port, operation, role, recipient, name, secret)
    id = if kind == :writer, do: 2, else: 1
    assert source_control_frame(port, ?H) == <<operation::binary, id>>
    assert source_control_frame(port, ?T) == <<operation::binary, id>>
    assert {:reply, :ok} = :gen_server.receive_response(request, 5_000)
    port
  end

  defp source_control_frame(port, tag),
    do: source_control_frame(port, tag, Process.get({__MODULE__, port}, <<>>))

  defp source_control_frame(port, tag, buffer) do
    case buffer do
      <<^tag, size::32, body::binary-size(size), rest::binary>> ->
        Process.put({__MODULE__, port}, rest)
        body

      _ ->
        receive do
          {^port, {:data, bytes}} when byte_size(buffer) + byte_size(bytes) <= 128 ->
            source_control_frame(port, tag, buffer <> bytes)

          {^port, {:exit_status, status}} ->
            flunk("source control exited: #{status}")
        after
          5_000 -> flunk("source control timed out")
        end
    end
  end

  if System.get_env("IPSE_TEST_MANY_SOURCE") == "1" do
    @tag :many_source_native
    @tag timeout: 300_000
    test "native root decision retains 128 distinct original Sessions", c do
      alias Ipse.Runner.Transaction
      assert {:ok, events} = Journal.load(c.context.history_dir, c.proof["session_id"])
      admission = hd(events)["metadata"]["semantic_admission"]

      extra =
        for n <- 1..126 do
          id = Usage.id()
          policy = put_in(admission, ["pin", "session_id"], id)

          assert {:ok, ^id} =
                   Journal.create_with_id(c.context.history_dir, id, %{
                     "source_layout" => SourceWindow.layout(),
                     "source_origin_layout" => Ipse.Journal.SourceOrigin.layout(),
                     "semantic_admission" => policy
                   })

          text = "Synthetic retained source #{n}"

          assert :ok =
                   Journal.append(
                     c.context.history_dir,
                     id,
                     Input.received(id, Usage.id(), text, text, nil)
                   )

          assert :ok =
                   Journal.append(c.context.history_dir, id, %{
                     "type" => "message",
                     "message" => %{"role" => "user", "content" => text}
                   })

          assert {:ok, saved_events} = Journal.load(c.context.history_dir, id)
          assert {:ok, saved} = Saved.restore(saved_events, id)
          assert {:ok, page} = SourceIndex.list(saved.source_window.index, %{"limit" => 1})
          [source] = page["sources"]

          assert {:ok, %{"proof" => proof}} =
                   SourceIndex.resolve_proof(saved.source_window.index, %{
                     "handle" => source["read_handle"],
                     "quote" => text
                   })

          path = Path.join(c.context.history_dir, id <> ".lock")
          assert {:ok, lock} = Runner.lock(path)
          assert :ok = Runner.unlock(lock)
          proof
        end

      proofs = [c.proof, c.second_proof | extra]
      alias Ipse.Journal.Writer
      alias Ipse.Session.Lock
      journal_id = Usage.id()

      assert {:ok, _} =
               Lock.acquire_share_header(Path.join(c.context.history_dir, journal_id <> ".lock"))

      guard = Lock.current()

      assert {:ok, ^journal_id} =
               Journal.create_with_locked_id(
                 c.context.history_dir,
                 journal_id,
                 %{
                   "kind" => "knowledge_management",
                   "version" => 1,
                   "native_journal_layout" => Journal.native_owner_layout(),
                   "source_origin_layout" => Ipse.Journal.SourceOrigin.layout()
                 },
                 nil,
                 guard
               )

      assert {:ok, writer} =
               Writer.start(c.context.history_dir, journal_id, self(), nil, :header_share_v2)

      assert :ok = Lock.track(writer, :writer)
      assert {:ok, reservation} = Writer.reserve(writer, %{bytes: 4096, events: 2})
      assert :ok = Writer.append_reserved(writer, reservation, %{"type" => "synthetic_intent"})
      owned = %{id: journal_id, writer: writer, guard: guard, journal_owner: self()}
      root = Path.join(c.context.history_dir, "transaction-128-sources")
      File.mkdir!(root)
      File.chmod!(root, 0o700)

      paths =
        for n <- 1..3 do
          dir = Path.join(root, Integer.to_string(n))
          File.mkdir!(dir)
          File.chmod!(dir, 0o700)
          Path.join(dir, ".lock")
        end

      caps =
        Enum.map(paths, fn path ->
          assert {:ok, cap} = Transaction.acquire(path)
          cap
        end)

      cap = List.last(caps)
      directory = Path.dirname(List.last(paths))
      File.write!(Path.join(directory, "root.json"), "old")
      File.chmod!(Path.join(directory, "root.json"), 0o600)
      stage = ".pending-" <> Usage.id()

      assert {:ok, :switched} =
               StoredSources.with_shareable_groups(c.context, proofs, fn sources, leases ->
                 assert length(sources) == 128 and length(leases) == 128
                 tokens = Enum.map(leases, & &1.token)

                 assert {:error, :invalid_transaction_request} =
                          Transaction.with_source_leases(cap, tokens ++ [hd(tokens)], fn ->
                            :invalid
                          end)

                 Transaction.with_journal_lease(cap, owned, fn ->
                   Transaction.with_source_leases(cap, tokens, fn ->
                     assert {:error, _} = Transaction.acceptance_guard(cap)

                     assert {:error, :journal_share_frozen} =
                              Writer.append_reserved(writer, reservation, %{"type" => "blocked"})

                     assert :ok = Transaction.stage(cap, ".", [{stage, "new"}])

                     assert :ok =
                              Transaction.switch_before(
                                cap,
                                stage,
                                "root.json",
                                System.system_time(:millisecond) + 30_000
                              )

                     {:ok, :switched}
                   end)
                 end)
               end)

      assert File.read!(Path.join(directory, "root.json")) == "new"
      assert :ok = Writer.append_reserved(writer, reservation, %{"type" => "synthetic_result"})
      assert :ok = Writer.release(writer, reservation)
      Enum.reverse(caps) |> Enum.each(fn cap -> assert :ok = Transaction.release(cap) end)
      assert :ok = Writer.close(writer)
      assert :ok = Lock.release(guard)
      Process.delete({Lock, :guard})

      loss_root = Path.join(c.context.history_dir, "transaction-128-source-loss")
      File.mkdir!(loss_root)
      File.chmod!(loss_root, 0o700)

      loss_paths =
        for n <- 1..3 do
          dir = Path.join(loss_root, Integer.to_string(n))
          File.mkdir!(dir)
          File.chmod!(dir, 0o700)
          Path.join(dir, ".lock")
        end

      loss_caps =
        Enum.map(loss_paths, fn path ->
          assert {:ok, item} = Transaction.acquire(path)
          item
        end)

      loss_cap = List.last(loss_caps)
      loss_directory = Path.dirname(List.last(loss_paths))
      File.write!(Path.join(loss_directory, "root.json"), "old")
      File.chmod!(Path.join(loss_directory, "root.json"), 0o600)
      loss_stage = ".pending-" <> Usage.id()

      assert {:error, :collection_source_refused} =
               StoredSources.with_shareable_groups(c.context, proofs, fn _, leases ->
                 %{token: lost_token} = Enum.at(leases, 64)
                 assert {:ok, identity} = StoredSources.share_identity(lost_token)

                 Transaction.with_source_leases(loss_cap, Enum.map(leases, & &1.token), fn ->
                   assert :ok = Transaction.stage(loss_cap, ".", [{loss_stage, "new"}])
                   assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(identity.pid)])

                   assert {:unknown, _} =
                            Transaction.switch_before(
                              loss_cap,
                              loss_stage,
                              "root.json",
                              System.system_time(:millisecond) + 30_000
                            )

                   {:unknown, :source_lost}
                 end)
               end)

      assert File.read!(Path.join(loss_directory, "root.json")) == "old"
    end
  end

  test "source owner loss before the native decision leaves the root unchanged", c do
    root = Path.join(c.context.history_dir, "transaction-source-loss")
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    paths =
      for n <- 1..3 do
        dir = Path.join(root, Integer.to_string(n))
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    caps =
      Enum.map(paths, fn path ->
        assert {:ok, cap} = Ipse.Runner.Transaction.acquire(path)
        cap
      end)

    collection = List.last(caps)
    directory = Path.dirname(List.last(paths))
    File.write!(Path.join(directory, "root.json"), "old")
    File.chmod!(Path.join(directory, "root.json"), 0o600)
    stage = ".pending-" <> Usage.id()

    assert {:error, :collection_source_refused} =
             StoredSources.with_shareable_verified(c.context, c.proof, fn _, token ->
               {:ok, identity} = StoredSources.share_identity(token)

               Ipse.Runner.Transaction.with_source_lease(collection, token, fn ->
                 assert :ok = Ipse.Runner.Transaction.stage(collection, ".", [{stage, "new"}])
                 assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(identity.pid)])

                 assert {:unknown, _} =
                          Ipse.Runner.Transaction.switch_before(
                            collection,
                            stage,
                            "root.json",
                            System.system_time(:millisecond) + 10_000
                          )

                 {:unknown, :source_lost}
               end)
             end)

    assert File.read!(Path.join(directory, "root.json")) == "old"
  end

  test "loss of either original session prevents a two-source root decision", c do
    for {lost_id, index} <- Enum.with_index([c.proof["session_id"], c.second_proof["session_id"]]) do
      root = Path.join(c.context.history_dir, "transaction-two-source-loss-#{index}")
      File.mkdir!(root)
      File.chmod!(root, 0o700)

      paths =
        for n <- 1..3 do
          dir = Path.join(root, Integer.to_string(n))
          File.mkdir!(dir)
          File.chmod!(dir, 0o700)
          Path.join(dir, ".lock")
        end

      caps =
        Enum.map(paths, fn path ->
          assert {:ok, cap} = Ipse.Runner.Transaction.acquire(path)
          cap
        end)

      collection = List.last(caps)
      directory = Path.dirname(List.last(paths))
      File.write!(Path.join(directory, "root.json"), "old")
      File.chmod!(Path.join(directory, "root.json"), 0o600)
      stage = ".pending-" <> Usage.id()

      assert {:error, :collection_source_refused} =
               StoredSources.with_shareable_groups(c.context, [c.proof, c.second_proof], fn _,
                                                                                            leases ->
                 %{token: lost_token} = Enum.find(leases, &(&1.session_id == lost_id))
                 assert {:ok, identity} = StoredSources.share_identity(lost_token)
                 tokens = Enum.map(leases, & &1.token)

                 Ipse.Runner.Transaction.with_source_leases(collection, tokens, fn ->
                   assert :ok = Ipse.Runner.Transaction.stage(collection, ".", [{stage, "new"}])
                   assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(identity.pid)])

                   assert {:unknown, _} =
                            Ipse.Runner.Transaction.switch_before(
                              collection,
                              stage,
                              "root.json",
                              System.system_time(:millisecond) + 10_000
                            )

                   {:unknown, :source_lost}
                 end)
               end)

      assert File.read!(Path.join(directory, "root.json")) == "old"
    end
  end

  @tag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux native lease transfer")
  test "journal and original source leases remain held through one native root decision", c do
    alias Ipse.Journal.Writer
    alias Ipse.Session.Lock
    alias Ipse.Runner.Transaction

    id = Usage.id()
    assert {:ok, _} = Lock.acquire_share_header(Path.join(c.context.history_dir, id <> ".lock"))
    guard = Lock.current()

    assert {:ok, ^id} =
             Journal.create_with_locked_id(
               c.context.history_dir,
               id,
               %{
                 "kind" => "knowledge_management",
                 "version" => 1,
                 "native_journal_layout" => Journal.native_owner_layout(),
                 "source_origin_layout" => Ipse.Journal.SourceOrigin.layout()
               },
               nil,
               guard
             )

    assert {:ok, writer} = Writer.start(c.context.history_dir, id, self(), nil, :header_share_v2)
    assert :ok = Lock.track(writer, :writer)
    assert {:ok, reservation} = Writer.reserve(writer, %{bytes: 4096, events: 2})
    assert :ok = Writer.append_reserved(writer, reservation, %{"type" => "synthetic_intent"})
    owned = %{id: id, writer: writer, guard: guard, journal_owner: self()}

    root = Path.join(c.context.history_dir, "dual-lease")
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    paths =
      for n <- 1..3 do
        dir = Path.join(root, Integer.to_string(n))
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    caps =
      Enum.map(paths, fn path ->
        assert {:ok, cap} = Transaction.acquire(path)
        cap
      end)

    cap = List.last(caps)
    directory = Path.dirname(List.last(paths))
    File.write!(Path.join(directory, "root.json"), "old")
    File.chmod!(Path.join(directory, "root.json"), 0o600)
    stage = ".pending-" <> Usage.id()

    assert {:error, :invalid_transaction_request} = Transaction.acceptance_guard(cap)

    assert {:ok, :switched} =
             StoredSources.with_shareable_verified(c.context, c.proof, fn _, token ->
               Transaction.with_journal_lease(cap, owned, fn ->
                 assert {:error, :invalid_transaction_request} = Transaction.acceptance_guard(cap)

                 Transaction.with_source_lease(cap, token, fn ->
                   assert :ok = Transaction.acceptance_guard(cap)

                   assert {:error, :invalid_transaction_capability} =
                            Transaction.acceptance_guard(cap, %{}, %{})

                   assert {:error, :journal_share_frozen} =
                            Writer.append_reserved(writer, reservation, %{"type" => "blocked"})

                   assert :ok = Transaction.stage(cap, ".", [{stage, "new"}])

                   assert :ok =
                            Transaction.switch_before(
                              cap,
                              stage,
                              "root.json",
                              System.system_time(:millisecond) + 10_000
                            )

                   {:ok, :switched}
                 end)
               end)
             end)

    assert File.read!(Path.join(directory, "root.json")) == "new"
    assert :ok = Writer.append_reserved(writer, reservation, %{"type" => "synthetic_result"})
    assert :ok = Writer.release(writer, reservation)
    Enum.reverse(caps) |> Enum.each(fn item -> assert :ok = Transaction.release(item) end)
    assert :ok = Writer.close(writer)
    assert :ok = Lock.release(guard)
    Process.delete({Lock, :guard})
    assert {:ok, events} = Journal.load(c.context.history_dir, id)
    assert Enum.map(Enum.drop(events, 1), & &1["type"]) == ~w(synthetic_intent synthetic_result)
  end

  @tag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux native lease transfer")
  test "journal writer loss before the native decision leaves the root unchanged", c do
    alias Ipse.Journal.Writer
    alias Ipse.Session.Lock
    alias Ipse.Runner.Transaction
    id = Usage.id()
    assert {:ok, _} = Lock.acquire_share_header(Path.join(c.context.history_dir, id <> ".lock"))
    guard = Lock.current()

    metadata = %{
      "kind" => "knowledge_management",
      "version" => 1,
      "native_journal_layout" => Journal.native_owner_layout(),
      "source_origin_layout" => Ipse.Journal.SourceOrigin.layout()
    }

    assert {:ok, ^id} =
             Journal.create_with_locked_id(c.context.history_dir, id, metadata, nil, guard)

    assert {:ok, writer} = Writer.start(c.context.history_dir, id, self(), nil, :header_share_v2)
    assert :ok = Lock.track(writer, :writer)
    Process.unlink(writer)
    assert {:ok, reservation} = Writer.reserve(writer, %{bytes: 4096, events: 2})
    assert :ok = Writer.append_reserved(writer, reservation, %{"type" => "synthetic_intent"})
    owned = %{id: id, writer: writer, guard: guard, journal_owner: self()}

    root = Path.join(c.context.history_dir, "writer-loss")
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    paths =
      for n <- 1..3 do
        dir = Path.join(root, Integer.to_string(n))
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    caps =
      Enum.map(paths, fn path ->
        assert {:ok, cap} = Transaction.acquire(path)
        cap
      end)

    cap = List.last(caps)
    directory = Path.dirname(List.last(paths))
    File.write!(Path.join(directory, "root.json"), "old")
    File.chmod!(Path.join(directory, "root.json"), 0o600)
    stage = ".pending-" <> Usage.id()

    result =
      StoredSources.with_shareable_verified(c.context, c.proof, fn _, token ->
        Transaction.with_journal_lease(cap, owned, fn ->
          Transaction.with_source_lease(cap, token, fn ->
            assert :ok = Transaction.stage(cap, ".", [{stage, "new"}])
            monitor = Process.monitor(writer)
            Process.exit(writer, :kill)
            assert_receive {:DOWN, ^monitor, :process, ^writer, :killed}, 5_000

            assert {:unknown, _} =
                     Transaction.switch_before(
                       cap,
                       stage,
                       "root.json",
                       System.system_time(:millisecond) + 10_000
                     )

            {:unknown, :writer_lost}
          end)
        end)
      end)

    assert match?({:error, _}, result) or match?({:unknown, _}, result)
    assert File.read!(Path.join(directory, "root.json")) == "old"
    Lock.release(guard)
    Process.delete({Lock, :guard})
  end

  if System.get_env("IPSE_TEST_SOURCE_SWITCH") == "1" do
    @tag :source_switch_hook
    test "source loss at the native decision never produces a confirmed switch", c do
      for {phase, expected} <- [{"before-decision", "old"}, {"after-decision", "new"}] do
        root = Path.join(c.context.history_dir, "source-switch-" <> phase)
        File.mkdir!(root)
        File.chmod!(root, 0o700)

        paths =
          for n <- 1..3 do
            dir = Path.join(root, Integer.to_string(n))
            File.mkdir!(dir)
            File.chmod!(dir, 0o700)
            Path.join(dir, ".lock")
          end

        hook = Path.dirname(hd(paths))
        File.write!(Path.join(hook, "source-switch-#{phase}.arm"), "armed")

        caps =
          Enum.map(paths, fn path ->
            assert {:ok, cap} = Ipse.Runner.Transaction.acquire(path)
            cap
          end)

        cap = List.last(caps)
        directory = Path.dirname(List.last(paths))
        File.write!(Path.join(directory, "root.json"), "old")
        File.chmod!(Path.join(directory, "root.json"), 0o600)
        stage = ".pending-" <> Usage.id()

        assert {:error, :collection_source_refused} =
                 StoredSources.with_shareable_verified(c.context, c.proof, fn _, token ->
                   {:ok, identity} = StoredSources.share_identity(token)

                   Ipse.Runner.Transaction.with_source_lease(cap, token, fn ->
                     assert :ok = Ipse.Runner.Transaction.stage(cap, ".", [{stage, "new"}])

                     watcher =
                       Task.async(fn ->
                         wait_for_hook(Path.join(hook, "source-switch-#{phase}.ready"), 500)

                         assert {_, 0} =
                                  System.cmd("kill", ["-KILL", Integer.to_string(identity.pid)])

                         File.write!(Path.join(hook, "source-switch-#{phase}.go"), "go")
                       end)

                     assert {:unknown, _} =
                              Ipse.Runner.Transaction.switch_before(
                                cap,
                                stage,
                                "root.json",
                                System.system_time(:millisecond) + 60_000
                              )

                     Task.await(watcher, 10_000)
                     {:unknown, :source_lost}
                   end)
                 end)

        assert File.read!(Path.join(directory, "root.json")) == expected
      end
    end

    @tag :source_switch_hook
    test "journal writer loss on both sides of the native decision is never confirmed", c do
      alias Ipse.Journal.Writer
      alias Ipse.Session.Lock
      alias Ipse.Runner.Transaction

      for {phase, expected} <- [{"before-decision", "old"}, {"after-decision", "new"}] do
        id = Usage.id()

        assert {:ok, _} =
                 Lock.acquire_share_header(Path.join(c.context.history_dir, id <> ".lock"))

        guard = Lock.current()

        metadata = %{
          "kind" => "knowledge_management",
          "version" => 1,
          "native_journal_layout" => Journal.native_owner_layout(),
          "source_origin_layout" => Ipse.Journal.SourceOrigin.layout()
        }

        assert {:ok, ^id} =
                 Journal.create_with_locked_id(c.context.history_dir, id, metadata, nil, guard)

        assert {:ok, writer} =
                 Writer.start(c.context.history_dir, id, self(), nil, :header_share_v2)

        assert :ok = Lock.track(writer, :writer)
        Process.unlink(writer)
        assert {:ok, reservation} = Writer.reserve(writer, %{bytes: 4096, events: 2})
        assert :ok = Writer.append_reserved(writer, reservation, %{"type" => "synthetic_intent"})
        owned = %{id: id, writer: writer, guard: guard, journal_owner: self()}
        root = Path.join(c.context.history_dir, "writer-switch-" <> phase)
        File.mkdir!(root)
        File.chmod!(root, 0o700)

        paths =
          for n <- 1..3 do
            dir = Path.join(root, Integer.to_string(n))
            File.mkdir!(dir)
            File.chmod!(dir, 0o700)
            Path.join(dir, ".lock")
          end

        hook = Path.dirname(hd(paths))
        File.write!(Path.join(hook, "source-switch-#{phase}.arm"), "armed")

        caps =
          Enum.map(paths, fn path ->
            assert {:ok, cap} = Transaction.acquire(path)
            cap
          end)

        cap = List.last(caps)
        directory = Path.dirname(List.last(paths))
        File.write!(Path.join(directory, "root.json"), "old")
        File.chmod!(Path.join(directory, "root.json"), 0o600)
        stage = ".pending-" <> Usage.id()

        result =
          StoredSources.with_shareable_verified(c.context, c.proof, fn _, token ->
            Transaction.with_journal_lease(cap, owned, fn ->
              Transaction.with_source_lease(cap, token, fn ->
                assert :ok = Transaction.stage(cap, ".", [{stage, "new"}])

                watcher =
                  Task.async(fn ->
                    wait_for_hook(Path.join(hook, "source-switch-#{phase}.ready"), 500)
                    monitor = Process.monitor(writer)
                    Process.exit(writer, :kill)
                    assert_receive {:DOWN, ^monitor, :process, ^writer, :killed}, 5_000
                    File.write!(Path.join(hook, "source-switch-#{phase}.go"), "go")
                  end)

                assert {:unknown, _} =
                         Transaction.switch_before(
                           cap,
                           stage,
                           "root.json",
                           System.system_time(:millisecond) + 60_000
                         )

                Task.await(watcher, 10_000)
                {:unknown, :writer_lost}
              end)
            end)
          end)

        assert match?({:error, _}, result) or match?({:unknown, _}, result)
        assert File.read!(Path.join(directory, "root.json")) == expected
        Lock.release(guard)
        Process.delete({Lock, :guard})
      end
    end

    defp wait_for_hook(path, attempts) when attempts > 0 do
      if File.exists?(path),
        do: :ok,
        else:
          (
            Process.sleep(10)
            wait_for_hook(path, attempts - 1)
          )
    end

    defp wait_for_hook(_, 0), do: flunk("native source switch hook did not fire")
  end

  test "shareable original source refuses after the lease recipient dies", c do
    assert {:error, :collection_source_refused} =
             StoredSources.with_shareable_verified(c.context, c.proof, fn _, token ->
               {:ok, identity} = StoredSources.share_identity(token)
               {collector, pid} = source_collector()
               operation = :crypto.strong_rand_bytes(16)
               name = :crypto.strong_rand_bytes(16)
               secret = :crypto.strong_rand_bytes(32)

               entry =
                 <<0, identity.pid::32, name::binary, secret::binary, identity.device::64,
                   identity.inode::64>>

               initial = <<5_000::64, operation::binary, 1, entry::binary>>
               assert Port.command(collector, <<?I, byte_size(initial)::32, initial::binary>>)
               assert source_frame(collector, ?H) == <<operation::binary, 1>>

               recipient =
                 <<pid::32, name::binary, secret::binary, identity.device::64,
                   identity.inode::64>>

               deadline = System.monotonic_time(:millisecond) + 5_000
               assert :ok = StoredSources.share_export(token, operation, recipient, deadline)
               assert source_frame(collector, ?L) == <<operation::binary, 1>>
               Port.close(collector)

               assert {:error, :collection_source_refused} =
                        StoredSources.share_settle(token, operation, deadline)

               :must_not_escape
             end)

    assert {:ok, lock} = Runner.lock(c.lock_path)
    assert :ok = Runner.unlock(lock)
  end

  test "pending acceptance retains and verifies its original source under the matching project",
       c do
    pin = c.context.config.semantic_admission["pin"]
    proof = c.proof
    text = "A synthetic accepted decision"
    {:ok, lineage} = Ipse.Extension.ManagedRecipe.source_identity(proof)
    {:ok, candidate} = Ipse.Extension.ManagedRecipe.proposal_identity(lineage, text)
    now = System.system_time(:millisecond)

    facts = %{
      "version" => 1,
      "kind" => "pending_proposal_card",
      "operation_id" => Usage.id(),
      "journal_id" => c.context.session_id,
      "client_id" => Usage.id(),
      "session_id" => c.context.session_id,
      "project_id" => pin["project_id"],
      "namespace" => pin["namespace"],
      "binding_sha256" => pin["binding_sha256"],
      "policy_sha256" => pin["policy_sha256"],
      "capture_epoch" => pin["epoch"],
      "render_revision" => 1,
      "pending_key" => "pending." <> candidate,
      "candidate_id" => candidate,
      "record_schema_version" => 1,
      "record_revision" => 1,
      "record_sha256" => JSON.sha256("record"),
      "lineage" => lineage,
      "text" => text,
      "text_sha256" => JSON.sha256(text),
      "assigned_category" => "ordinary",
      "reason" => "fixture",
      "source_proof" => proof,
      "recipe_sha256" => JSON.sha256("recipe"),
      "publication_policy_sha256" => JSON.sha256("publication policy"),
      "first_admitted_ms" => now - 1,
      "valid_until_ms" => now + 10_000,
      "root_sha256" => JSON.sha256("root")
    }

    assert Ipse.Session.PendingAcceptance.valid_facts?(facts)

    assert :verified =
             Ipse.Session.PendingAcceptance.with_verified_source(c.context, facts, fn source ->
               assert source["proof"] === proof
               assert {:error, _} = Runner.lock(c.lock_path)
               :verified
             end)

    assert :shareable =
             Ipse.Session.PendingAcceptance.with_shareable_source(c.context, facts, fn source,
                                                                                       lease ->
               assert source["proof"] === proof
               assert {:ok, _} = StoredSources.share_identity(lease)
               assert {:error, _} = Runner.lock(c.lock_path)
               :shareable
             end)

    assert {:error, :pending_acceptance_refused} =
             Ipse.Session.PendingAcceptance.with_verified_source(
               c.context,
               Map.put(facts, "policy_sha256", JSON.sha256("other policy")),
               fn _ -> flunk("different policy reached source") end
             )

    altered = Map.put(proof, "occurrence_id", Usage.id())
    {:ok, altered_lineage} = Ipse.Extension.ManagedRecipe.source_identity(altered)
    {:ok, altered_id} = Ipse.Extension.ManagedRecipe.proposal_identity(altered_lineage, text)

    missing = %{
      facts
      | "source_proof" => altered,
        "lineage" => altered_lineage,
        "candidate_id" => altered_id,
        "pending_key" => "pending." <> altered_id
    }

    assert Ipse.Session.PendingAcceptance.valid_facts?(missing)

    assert {:error, :collection_source_refused} =
             Ipse.Session.PendingAcceptance.with_verified_source(c.context, missing, fn _ ->
               flunk("missing original source reached callback")
             end)

    before = File.read!(c.journal_path)

    assert {:error, :collection_source_refused} =
             Ipse.Session.PendingAcceptance.with_verified_source(c.context, facts, fn _ ->
               [port] =
                 Port.list() |> Enum.filter(&(Port.info(&1, :connected) == {:connected, self()}))

               monitor = :erlang.monitor(:port, port)
               {:os_pid, pid} = Port.info(port, :os_pid)
               assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(pid)])
               assert_receive {:DOWN, ^monitor, :port, ^port, _}, 5000
               :must_not_escape
             end)

    assert File.read!(c.journal_path) == before
  end

  test "native lock-owner loss withholds the callback value without changing journal bytes", c do
    before = File.read!(c.journal_path)

    assert {:error, :collection_source_refused} =
             StoredSources.with_verified(c.context, %{}, [c.proof], fn [_] ->
               [port] =
                 Port.list() |> Enum.filter(&(Port.info(&1, :connected) == {:connected, self()}))

               monitor = :erlang.monitor(:port, port)
               {:os_pid, pid} = Port.info(port, :os_pid)

               assert {_, 0} =
                        System.cmd("kill", ["-KILL", Integer.to_string(pid)],
                          stderr_to_stdout: true
                        )

               assert_receive {:DOWN, ^monitor, :port, ^port, _}, 5000
               :must_not_escape
             end)

    assert File.read!(c.journal_path) == before

    assert {:ok, lock} = Runner.lock(c.lock_path)
    assert :ok = Runner.unlock(lock)

    assert :fresh_read =
             StoredSources.with_verified(c.context, %{}, [c.proof], fn [_] -> :fresh_read end)
  end

  defp source_collector do
    helper = Path.join(to_string(:code.priv_dir(:ipse)), "ipse-runner")

    port =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        args: ["--lease-collect-close-ready-v3"]
      ])

    {:os_pid, pid} = Port.info(port, :os_pid)
    {port, pid}
  end

  defp source_frame(port, tag, buffer \\ <<>>) do
    case buffer do
      <<^tag, size::32, body::binary-size(size)>> ->
        body

      _ ->
        receive do
          {^port, {:data, bytes}} when byte_size(buffer) + byte_size(bytes) <= 256 ->
            source_frame(port, tag, buffer <> bytes)

          {^port, {:exit_status, status}} ->
            flunk("collector exit #{status}")
        after
          5_000 -> flunk("collector timeout")
        end
    end
  end

  test "combined original-journal scans obey one byte budget across source Sessions", c do
    directory = c.context.history_dir
    id = Usage.id()
    admission = put_in(c.context.config.semantic_admission, ["pin", "session_id"], id)

    assert {:ok, ^id} =
             Journal.create_with_id(directory, id, %{
               "source_layout" => SourceWindow.layout(),
               "source_origin_layout" => Ipse.Journal.SourceOrigin.layout(),
               "semantic_admission" => admission
             })

    text = "Another synthetic source"
    assert :ok = Journal.append(directory, id, Input.received(id, Usage.id(), text, text, nil))

    assert :ok =
             Journal.append(directory, id, %{
               "type" => "message",
               "message" => %{"role" => "user", "content" => text}
             })

    assert {:ok, events} = Journal.load(directory, id)
    assert {:ok, saved} = Saved.restore(events, id)
    assert {:ok, page} = SourceIndex.list(saved.source_window.index, %{"limit" => 1})
    [source] = page["sources"]

    assert {:ok, %{"proof" => proof}} =
             SourceIndex.resolve_proof(
               saved.source_window.index,
               %{"handle" => source["read_handle"], "quote" => text}
             )

    assert {:ok, lock} = Runner.lock(Path.join(directory, id <> ".lock"))
    assert :ok = Runner.unlock(lock)

    largest =
      max(File.stat!(c.journal_path).size, File.stat!(Path.join(directory, id <> ".jsonl")).size)

    context =
      put_in(c.context, [:config, :journal], %{
        "max_bytes" => largest + 64,
        "max_record_bytes" => largest + 64
      })

    assert :one = StoredSources.with_verified(context, %{}, [c.proof], fn [_] -> :one end)
    assert :other = StoredSources.with_verified(context, %{}, [proof], fn [_] -> :other end)

    assert {:error, :collection_source_refused} =
             StoredSources.with_verified(context, %{}, [c.proof, proof], fn _ ->
               flunk("multiple source scans exceeded their aggregate byte budget")
             end)

    invalid = Map.put(c.proof, "version_id", Usage.id())
    assert {:ok, statuses} = StoredSources.snapshot(context, [c.proof, invalid])
    assert statuses[JSON.digest([c.proof])]
    refute statuses[JSON.digest([invalid])]
    assert {:ok, combined} = StoredSources.snapshot(context, [c.proof, proof])
    assert Enum.count(combined, fn {_, available} -> available end) == 1

    assert {:error, :collection_source_refused} =
             StoredSources.with_verified(
               Map.put(context, :stored_source_resolution, :partial),
               %{},
               [invalid],
               fn _ ->
                 flunk("strict use accepted partial preflight status")
               end
             )

    assert {:ok, lock} = Runner.lock(c.lock_path)
    assert :ok = Runner.unlock(lock)
  end
end
