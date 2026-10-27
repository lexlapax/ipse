Code.require_file(Path.expand("../../support/transaction_fixture.exs", __DIR__))
:ok = Ipse.Test.TransactionFixtureLoader.load_project()

defmodule Ipse.Extension.ProjectDomainAuthTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.ProjectIdentity, as: P
  alias Ipse.Extension.ProjectIdentity.DomainAuth, as: D
  alias Ipse.Runner.Transaction

  # Root witnesses below are explicit trusted callback fixtures. They test the
  # Identity contract, not actual Collection provenance or import adoption.
  setup do
    base = Path.join(System.tmp_dir!(), "ipse-domain-auth-" <> Ipse.Usage.id())

    Enum.each([base, base <> "/home", base <> "/work"], fn path ->
      File.mkdir!(path)
      File.chmod!(path, 0o700)
    end)

    {:ok, binding} = P.admit(base <> "/home", base <> "/work", :folder)
    on_exit(fn -> File.rm_rf!(base) end)

    %{
      home: base <> "/home",
      cwd: base <> "/work",
      base: base,
      binding: binding,
      scope: %{
        namespace: Ipse.JSON.sha256("namespace"),
        format: "managed-metadata-v3",
        operation_id: Ipse.Usage.id(),
        initialize: true
      }
    }
  end

  test "v1 reads stay keyless, denial writes nothing, and public binding stays identical", c do
    original = File.read!(index(c))
    assert {:ok, c.binding} == P.existing(c.home, c.cwd)
    assert {:error, :project_domain_unavailable} = existing(c, fn _, _ -> flunk("called") end)

    assert {:error, :denied} =
             publish(c, fn _ -> {:error, :denied} end, fn _, _ -> flunk("called") end)

    assert File.read!(index(c)) == original
    assert state(c)["version"] == 1
    assert {:ok, _} = initialize(c)
    assert {:ok, c.binding} == P.existing(c.home, c.cwd)
    assert {:ok, _} = P.preview(c.home, c.cwd)
    after_preview = File.read!(index(c))
    assert {:ok, c.binding} == P.existing(c.home, c.cwd)
    assert File.read!(index(c)) == after_preview
  end

  test "an absent identity is a refused verifier and creates no control state", c do
    scope = Map.take(c.scope, [:namespace, :format])
    absent = c.base <> "/absent-home"

    assert {:error, :project_domain_unavailable} =
             P.with_existing_domain_auth(absent, c.cwd, c.binding, scope, fn _, _ ->
               flunk("absent identity callback")
             end)

    refute File.exists?(absent)
    private(absent)

    assert {:error, :project_domain_unavailable} =
             P.with_existing_domain_auth(absent, c.cwd, c.binding, scope, fn _, _ ->
               flunk("missing index callback")
             end)

    assert File.ls!(absent) == []
  end

  test "prepared and active first-use transitions preserve private state on ordinary admission",
       c do
    original = state(c)
    assert {:ok, value} = initialize(c)
    next = state(c)
    assert next["version"] == 2 and next["revision"] == original["revision"] + 2
    assert next["projects"] == original["projects"] and next["bindings"] == original["bindings"]
    entry = entry(c)
    assert entry["state"] == "active" and entry["first_root_sha256"] == value.root_sha256
    assert entry["first_operation_id"] == c.scope.operation_id
    private(c.base <> "/other")
    assert {:ok, _} = P.admit(c.home, c.base <> "/other", :folder)
    assert state(c)["domain_keys"] == next["domain_keys"]
    master = next["domain_keys"][c.binding["project_id"]]["master"]
    refute Jason.encode!(c.binding) =~ master
    assert {:ok, binding} = P.existing(c.home, c.cwd)
    refute inspect(binding) =~ master
  end

  test "persistent verifier accepts exact binary bytes and cannot sign", c do
    assert {:ok, %{tag: tag}} = initialize(c, <<0, 255, 17>>)

    assert {:ok, :verified} =
             existing(c, fn cap, _ ->
               assert D.verify(cap, context(c.scope), <<0, 255, 17>>, tag) === true
               assert D.verify(cap, context(c.scope), <<0, 255, 18>>, tag) === false
               assert {:error, _} = D.seal(cap, context(c.scope), "x")
               assert inspect(cap) == "#ProjectIdentity.DomainAuth<private>"
               {:ok, :verified}
             end)
  end

  test "a later publication has no identity write and cannot sign a different operation", c do
    assert {:ok, _} = initialize(c)
    bytes = File.read!(index(c))
    scope = %{c.scope | operation_id: Ipse.Usage.id(), initialize: false}

    assert {:ok, :signed} =
             publish(%{c | scope: scope}, fn _ -> :ok end, fn cap, _ ->
               assert {:error, _} = D.seal(cap, context(c.scope), "body")
               assert {:ok, _} = D.seal(cap, context(scope), "body")
               {:ok, :signed}
             end)

    assert File.read!(index(c)) == bytes
  end

  test "interrupted first completion remains prepared and never automatically retries", c do
    assert {:unknown, :project_domain_initialization_unconfirmed} =
             publish(c, fn _ -> :ok end, fn cap, receipt ->
               assert receipt["state"] == "prepared"
               assert {:ok, _} = D.seal(cap, context(c.scope), "body")
               {:ok, :not_a_root_witness}
             end)

    assert entry(c)["state"] == "prepared"
    bytes = File.read!(index(c))

    assert {:error, :project_domain_initialization_pending} =
             publish(c, fn _ -> :ok end, fn _, _ -> flunk("replayed") end)

    assert {:error, :project_domain_unavailable} =
             existing(c, fn _, _ -> flunk("read prepared") end)

    assert File.read!(index(c)) == bytes
  end

  test "explicit reconciliation binds exact key fence operation and root witness", c do
    assert {:unknown, _} = publish(c, fn _ -> :ok end, fn _, _ -> :unknown end)
    expected = expected(c)

    assert {:error, :project_domain_reconciliation_refused} =
             P.reconcile_domain(
               c.home,
               c.cwd,
               c.binding,
               %{expected | operation_id: Ipse.Usage.id()},
               fn _ -> :ok end,
               fn _, _ -> flunk("wrong op") end
             )

    assert {:error, :project_domain_reconciliation_refused} =
             P.reconcile_domain(
               c.home,
               c.cwd,
               c.binding,
               expected,
               fn _ -> {:error, :revoked} end,
               fn _, _ -> flunk("revoked") end
             )

    assert entry(c)["state"] == "prepared"

    assert {:ok, %{"state" => "active"}} =
             P.reconcile_domain(c.home, c.cwd, c.binding, expected, fn _ -> :ok end, fn cap,
                                                                                        receipt ->
               assert {:error, _} = D.seal(cap, context(c.scope), "body")
               {:ok, witness(c.scope, receipt)}
             end)

    assert {:error, :project_domain_reconciliation_refused} =
             P.reconcile_domain(c.home, c.cwd, c.binding, expected, fn _ -> :ok end, fn _, _ ->
               flunk("replayed reconcile")
             end)
  end

  test "malformed first witness cannot activate prepared state", c do
    assert {:unknown, :project_domain_activation_unconfirmed} =
             publish(c, fn _ -> :ok end, fn _, receipt ->
               {:first_publication, %{witness(c.scope, receipt) | operation_id: Ipse.Usage.id()},
                :bad}
             end)

    assert entry(c)["state"] == "prepared"
  end

  test "wrong binding and invalid or keyless scopes have no initialization side effects", c do
    before = File.read!(index(c))

    assert {:error, :stale_project_identity} =
             P.with_domain_publication(
               c.home,
               c.cwd,
               %{c.binding | "project_id" => Ipse.JSON.sha256("wrong")},
               c.scope,
               fn _ -> flunk("authorized wrong binding") end,
               fn _, _ -> flunk("called") end
             )

    for scope <- [
          Map.put(c.scope, :unknown, true),
          %{c.scope | format: "other"},
          %{c.scope | operation_id: 1}
        ] do
      assert {:error, _} =
               publish(%{c | scope: scope}, fn _ -> flunk("invalid") end, fn _, _ ->
                 flunk("called")
               end)
    end

    assert {:error, :project_domain_unavailable} =
             publish(%{c | scope: %{c.scope | initialize: false}}, fn _ -> :ok end, fn _, _ ->
               flunk("keyless")
             end)

    assert File.read!(index(c)) == before
  end

  test "namespace format and closed MAC context are independently bound", c do
    assert {:ok, %{tag: tag}} = initialize(c)

    assert {:ok, :done} =
             existing(c, fn cap, _ ->
               context = context(c.scope)

               for {key, value} <- [
                     {"page_key", "host.validity.anchor.ff.0"},
                     {"kind", "live"},
                     {"operation_id", Ipse.Usage.id()},
                     {"revision", 2}
                   ] do
                 assert D.verify(cap, Map.put(context, key, value), "body", tag) === false
               end

               for invalid <- [
                     Map.put(context, "extra", 1),
                     Map.put(context, "revision", 1.0),
                     Map.put(context, "schema", 2),
                     Map.put(context, "page_key", "note.x"),
                     Map.put(context, "page_key", "host.validity." <> String.duplicate("x", 90))
                   ] do
                 assert {:error, _} = D.verify(cap, invalid, "body", tag)
               end

               assert {:error, _} = D.verify(cap, context, "body", binary_part(tag, 0, 31))
               {:ok, :done}
             end)

    other = %{
      c
      | scope: %{c.scope | namespace: Ipse.JSON.sha256("other"), operation_id: Ipse.Usage.id()}
    }

    assert {:ok, _} = initialize(other)

    assert {:ok, false} =
             existing(other, fn cap, _ -> {:ok, D.verify(cap, context(c.scope), "body", tag)} end)
  end

  test "callback failure invalidates escaped capability and leaves prepared state", c do
    parent = self()

    assert {:unknown, _} =
             publish(c, fn _ -> :ok end, fn cap, _ ->
               send(parent, {:escaped, cap})
               raise "fixture callback failure"
             end)

    assert_receive {:escaped, cap}
    assert {:error, _} = D.seal(cap, context(c.scope), "body")
    assert entry(c)["state"] == "prepared"
  end

  test "signer deadline and call counts are absolute, and retained same-owner handle expires",
       c do
    {record, entry} = pure_key()
    scope = c.scope

    assert {:ok, cap} =
             D.with_auth(record, entry, c.binding["project_id"], scope, :publish, fn cap, _ ->
               for _ <- 1..16, do: assert({:ok, _} = D.seal(cap, context(scope), "body"))
               assert {:error, _} = D.seal(cap, context(scope), "body")
               {:ok, cap}
             end)

    assert {:error, _} = D.seal(cap, context(scope), "body")

    assert {:unknown, :project_domain_callback_expired} =
             D.with_auth(record, entry, c.binding["project_id"], scope, :publish, fn cap, _ ->
               Process.sleep(5_010)
               assert {:error, _} = D.seal(cap, context(scope), "body")
               {:ok, :expired}
             end)
  end

  test "exact caller check rejects a copied capability and verify count is bounded", c do
    {record, entry} = pure_key()
    scope = c.scope

    assert {:ok, tag} =
             D.with_auth(record, entry, c.binding["project_id"], scope, :publish, fn cap, _ ->
               task = Task.async(fn -> D.seal(cap, context(scope), "body") end)
               assert {:error, _} = Task.await(task)
               D.seal(cap, context(scope), "body")
             end)

    assert :ok =
             D.with_auth(
               record,
               entry,
               c.binding["project_id"],
               Map.take(scope, [:namespace, :format]),
               :verify,
               fn cap, _ ->
                 for _ <- 1..128, do: assert(D.verify(cap, context(scope), "body", tag))
                 assert {:error, _} = D.verify(cap, context(scope), "body", tag)

                 assert {:error, _} =
                          D.verify(cap, context(scope), String.duplicate("x", 6145), tag)

                 :ok
               end
             )
  end

  test "fixed canonical domain/context digest and exact raw binary body have a stable tag" do
    {record, entry} = pure_key()
    project = Ipse.JSON.sha256("project")

    scope = %{
      namespace: Ipse.JSON.sha256("namespace"),
      format: "managed-metadata-v3",
      operation_id: String.duplicate("4", 32),
      initialize: false
    }

    assert {:ok, tag} =
             D.with_auth(record, entry, project, scope, :publish, fn cap, _ ->
               D.seal(cap, context(scope), <<0, 255>>)
             end)

    assert Base.encode16(tag, case: :lower) ==
             "e5437c81d4c45d87c01da3e7f2ac4c13fc4b92ef4e0934c350274f3f548791fd"

    for {other_record, other_entry, other_project} <- [
          {%{record | "key_id" => String.duplicate("9", 32)}, entry, project},
          {record, %{entry | "fence_id" => String.duplicate("9", 32)}, project},
          {record, entry, Ipse.JSON.sha256("other project")}
        ] do
      assert false ==
               D.with_auth(other_record, other_entry, other_project, scope, :verify, fn cap, _ ->
                 D.verify(cap, context(scope), <<0, 255>>, tag)
               end)
    end
  end

  test "index v2 rejects malformed keys without altering ordinary state", c do
    assert {:ok, _} = initialize(c)
    valid = state(c)
    project = c.binding["project_id"]

    for bad <- [
          put_in(valid, ["domain_keys", project, "master"], String.duplicate("!", 43)),
          put_in(
            valid,
            ["domain_keys", project, "namespaces", c.scope.namespace, "first_root_sha256"],
            nil
          ),
          put_in(valid, ["domain_keys", project, "extra"], true)
        ] do
      File.write!(index(c), Jason.encode!(bad))
      assert {:error, :project_identity_unavailable} = P.existing(c.home, c.cwd)
    end

    File.write!(index(c), Jason.encode!(valid))
    assert {:ok, c.binding} == P.existing(c.home, c.cwd)
  end

  test "global namespace and project bounds and per-project catalog are closed", _ do
    {record, entry} = pure_key()
    ids = Enum.map(1..257, &Ipse.JSON.sha256(Integer.to_string(&1)))
    projects = Map.new(ids, &{&1, %{}})

    keys =
      Map.new(Enum.take(ids, 256), fn id -> {id, %{record | "namespaces" => %{id => entry}}} end)

    assert D.valid_keys?(keys, projects)
    refute D.valid_keys?(Map.put(keys, List.last(ids), record), projects)
    single = %{hd(ids) => %{record | "namespaces" => Map.new(Enum.take(ids, 8), &{&1, entry})}}
    assert D.valid_keys?(single, projects)

    refute D.valid_keys?(
             put_in(single, [hd(ids), "namespaces", Enum.at(ids, 8)], entry),
             projects
           )

    extra = put_in(keys, [hd(ids), "namespaces", List.last(ids)], entry)
    refute D.valid_keys?(extra, projects)
    refute D.valid_keys?(keys, %{})
  end

  test "nested inline locks work and reverse/reentrant entry is refused before another worker",
       c do
    assert {:ok, _} = initialize(c)
    private(c.base <> "/nested")
    File.write!(c.base <> "/nested/.lock", "")
    File.chmod!(c.base <> "/nested/.lock", 0o600)

    assert {:ok, :checked} =
             existing(c, fn cap, _ ->
               assert {:error, :project_identity_lock_order} = P.assert_order()
               assert {:error, :project_identity_unavailable} = P.existing(c.home, c.cwd)
               {:ok, nested} = Transaction.acquire(c.base <> "/nested/.lock")
               assert {:error, _} = D.seal(cap, context(c.scope), "body")
               :ok = Transaction.release(nested)
               {:ok, :checked}
             end)

    Process.put({Ipse.Extension.Consent, :lock_held}, true)

    try do
      assert {:error, :project_identity_lock_order} = P.assert_order()

      assert {:error, :project_identity_unavailable} =
               existing(c, fn _, _ -> flunk("reverse") end)
    after
      Process.delete({Ipse.Extension.Consent, :lock_held})
    end
  end

  test "native controller loss withholds callback results and active completion", c do
    assert {:unknown, :project_identity_lock_lost} =
             publish(c, fn _ -> :ok end, fn cap, receipt ->
               assert {:ok, _} = D.seal(cap, context(c.scope), "body")
               controller = Process.get({Transaction, :controller})
               monitor = Process.monitor(controller)
               Process.exit(controller, :kill)
               assert_receive {:DOWN, ^monitor, :process, ^controller, _}, 2_000
               {:first_publication, witness(c.scope, receipt), :must_not_escape}
             end)

    assert entry(c)["state"] == "prepared"
    assert {:ok, c.binding} == P.existing(c.home, c.cwd)
  end

  test "actual current Consent authorization releases its child lock before key publication", c do
    alias Ipse.Extension.Consent
    now = System.system_time(:millisecond)
    project = c.binding["project_id"]
    control = c.home <> "/knowledge-control"

    policy = %{
      "version" => 1,
      "project" => project,
      "artifact_sha256" => Ipse.JSON.sha256("artifact"),
      "source_sha256" => Ipse.JSON.sha256("sources"),
      "operations" => ["publication"],
      "settings" => %{},
      "expires_at_ms" => now + 60_000,
      "period_ms" => 60_000,
      "headless" => true,
      "limits" => Map.put(Consent.zero(), "operations", 10)
    }

    assert {:ok, _} = Consent.replace(control, project, 0, policy, now)

    authorize = fn _ ->
      case Consent.with_existing_policy(
             control,
             project,
             1,
             Ipse.JSON.digest([policy]),
             now,
             fn _ -> {:ok, :authorized} end
           ) do
        {:ok, :authorized} -> :ok
        _ -> {:error, :revoked}
      end
    end

    assert {:ok, :first} =
             publish(c, authorize, fn _, receipt ->
               {:first_publication, witness(c.scope, receipt), :first}
             end)

    before = File.read!(index(c))
    assert {:ok, _} = Consent.revoke(control, project, 1)
    assert {:error, :revoked} = publish(c, authorize, fn _, _ -> flunk("revoked callback") end)
    assert File.read!(index(c)) == before
  end

  test "a late first-completion callback cannot activate after its crypto lease expires", c do
    assert {:unknown, :project_domain_initialization_unconfirmed} =
             publish(c, fn _ -> :ok end, fn cap, receipt ->
               assert {:ok, _} = D.seal(cap, context(c.scope), :binary.copy(<<0>>, 6144))
               assert {:error, _} = D.seal(cap, context(c.scope), :binary.copy(<<0>>, 6145))
               Process.sleep(5_010)
               {:first_publication, witness(c.scope, receipt), :late}
             end)

    assert entry(c)["state"] == "prepared"
  end

  test "upstream death fences a paused signer and native owner with and without scope", c do
    parent = self()

    for scoped <- [false, true] do
      scope = %{
        c.scope
        | namespace: Ipse.JSON.sha256("owner #{scoped}"),
          operation_id: Ipse.Usage.id()
      }

      child_c = %{c | scope: scope}

      owner =
        spawn(fn ->
          if scoped do
            {:ok, resource_scope} = Ipse.Session.Resources.start(self())
            Ipse.Session.Resources.bind(resource_scope)
          end

          publish(child_c, fn _ -> :ok end, fn cap, receipt ->
            send(parent, {:paused, self(), Process.get({Transaction, :controller})})

            receive do
              :continue -> :ok
            end

            send(parent, {:late_crypto, D.seal(cap, context(scope), "body")})
            {:first_publication, witness(scope, receipt), :must_not_escape}
          end)
        end)

      assert_receive {:paused, worker, controller}, 3_000
      monitor = Process.monitor(controller)
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^controller, _}, 3_000
      send(worker, :continue)
      assert_receive {:late_crypto, {:error, _}}, 3_000
      assert entry(child_c)["state"] == "prepared"
      assert {:ok, c.binding} == P.existing(c.home, c.cwd)
    end
  end

  test "scope cancellation withholds private crypto even while upstream remains alive", c do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, scope} = Ipse.Session.Resources.start(self())
        Ipse.Session.Resources.bind(scope)

        result =
          publish(c, fn _ -> :ok end, fn _, receipt ->
            send(parent, {:paused_scope, self(), scope, Process.get({Transaction, :controller})})

            receive do
              :continue -> :ok
            end

            {:first_publication, witness(c.scope, receipt), :must_not_escape}
          end)

        send(parent, {:cancelled_result, result})
      end)

    assert_receive {:paused_scope, worker, scope, controller}, 3_000
    monitor = Process.monitor(controller)
    Ipse.Session.Resources.stop_async(scope)
    assert_receive {:DOWN, ^monitor, :process, ^controller, _}, 3_000
    assert Process.alive?(owner)
    send(worker, :continue)
    assert_receive {:cancelled_result, {:unknown, _}}, 4_000
    assert entry(c)["state"] == "prepared"
    assert {:ok, c.binding} == P.existing(c.home, c.cwd)
  end

  test "a separate VM cannot initialize another master while first publication holds Identity",
       c do
    parent = self()

    task =
      Task.async(fn ->
        publish(c, fn _ -> :ok end, fn _, receipt ->
          send(parent, {:held_domain, self()})

          receive do
            :continue -> :ok
          end

          {:first_publication, witness(c.scope, receipt), :first}
        end)
      end)

    assert_receive {:held_domain, worker}, 3_000
    before = key(c)
    child_scope = %{c.scope | operation_id: Ipse.Usage.id()}

    code =
      "Application.ensure_all_started(:ipse); IO.inspect(Ipse.Extension.ProjectIdentity.with_domain_publication(#{inspect(c.home)}, #{inspect(c.cwd)}, #{inspect(c.binding)}, #{inspect(child_scope)}, fn _ -> :ok end, fn _, _ -> {:ok, :second} end))"

    paths =
      :code.get_path()
      |> Enum.reject(&(Path.basename(List.to_string(&1)) == "consolidated"))
      |> Enum.flat_map(&["-pa", List.to_string(&1)])

    assert {"{:error, :project_identity_unavailable}\n", 0} =
             System.cmd("elixir", paths ++ ["-e", code], stderr_to_stdout: true)

    send(worker, :continue)
    assert {:ok, :first} = Task.await(task)
    assert key(c)["key_id"] == before["key_id"] and key(c)["master"] == before["master"]

    assert {"{:ok, :second}\n", 0} =
             System.cmd("elixir", paths ++ ["-e", code], stderr_to_stdout: true)

    assert key(c)["master"] == before["master"]
  end

  test "actual native loss after prepared or active index rename returns unknown", c do
    root = Path.expand("../../..", __DIR__)
    mode = c.base <> "/kill-on"
    marker = c.base <> "/renamed"
    helper = c.base <> "/wire-fault"
    real = Application.app_dir(:ipse, "priv/ipse-runner")
    source = c.base <> "/wire-fault.rs"

    File.write!(source, """
    #[path=#{inspect(root <> "/native/ipse-transaction.rs")}] mod ipse_transaction;
    #[path=#{inspect(root <> "/native/ipse-storage.rs")}] mod ipse_storage;
    use std::{io::{self,Write},process::Command,sync::atomic::{AtomicUsize,Ordering}};
    use std::os::unix::process::CommandExt;
    unsafe extern "C"{fn kill(pid:i32,signal:i32)->i32;}
    static SWITCH:AtomicUsize=AtomicUsize::new(0);
    fn frame(kind:u8,bytes:&[u8])->io::Result<()>{
      if kind==b'S'{let n=SWITCH.fetch_add(1,Ordering::SeqCst)+1;
        if std::fs::read_to_string(#{inspect(mode)}).unwrap_or_default()==n.to_string(){
          std::fs::write(#{inspect(marker)},n.to_string())?;unsafe{kill(std::process::id() as i32,9);}}}
      let mut out=io::stdout().lock();out.write_all(&[kind])?;out.write_all(&(bytes.len() as u32).to_be_bytes())?;out.write_all(bytes)?;out.flush()
    }
    fn main(){let args:Vec<_>=std::env::args().collect();
      if args.get(1).is_some_and(|s|s=="--transaction-lock"){
        if ipse_transaction::run(&args).is_err(){std::process::exit(1)}
      }else{let _=Command::new(#{inspect(real)}).args(&args[1..]).exec();std::process::exit(70)}}
    """)

    assert {_, 0} =
             System.cmd("rustc", ["--edition=2021", "-A", "dead_code", source, "-o", helper],
               stderr_to_stdout: true
             )

    previous = System.get_env("IPSE_RUNNER_PATH")

    try do
      System.put_env("IPSE_RUNNER_PATH", helper)

      for nth <- [1, 2] do
        scope = %{
          c.scope
          | namespace: Ipse.JSON.sha256("switch #{nth}"),
            operation_id: Ipse.Usage.id()
        }

        File.write!(mode, Integer.to_string(nth))

        assert {:unknown, _} =
                 Ipse.Test.ProjectIdentityFixture.with_domain_publication(
                   c.home,
                   c.cwd,
                   c.binding,
                   scope,
                   fn _ -> :ok end,
                   fn _, receipt ->
                     {:first_publication, witness(scope, receipt), :must_not_escape}
                   end
                 )

        assert File.read!(marker) == Integer.to_string(nth)
        assert entry(%{c | scope: scope})["state"] == if(nth == 1, do: "prepared", else: "active")
      end
    after
      if previous,
        do: System.put_env("IPSE_RUNNER_PATH", previous),
        else: System.delete_env("IPSE_RUNNER_PATH")
    end

    assert {:ok, c.binding} == P.existing(c.home, c.cwd)
  end

  defp initialize(c, body \\ "body") do
    publish(c, fn _ -> :ok end, fn cap, receipt ->
      {:ok, tag} = D.seal(cap, context(c.scope), body)
      witness = witness(c.scope, receipt)
      {:first_publication, witness, %{tag: tag, root_sha256: witness.root_sha256}}
    end)
  end

  defp publish(c, authorize, fun),
    do: P.with_domain_publication(c.home, c.cwd, c.binding, c.scope, authorize, fun)

  defp existing(c, fun),
    do:
      P.with_existing_domain_auth(
        c.home,
        c.cwd,
        c.binding,
        Map.take(c.scope, [:namespace, :format]),
        fun
      )

  defp context(scope),
    do: %{
      "version" => 1,
      "schema" => 3,
      "page_key" => "host.validity.anchor.00.0",
      "kind" => "anchor",
      "operation_id" => scope.operation_id,
      "revision" => 1
    }

  defp witness(scope, receipt),
    do: %{
      version: 1,
      namespace: scope.namespace,
      format: scope.format,
      fence_id: receipt["fence_id"],
      operation_id: scope.operation_id,
      root_sha256: Ipse.JSON.sha256("synthetic first root")
    }

  defp expected(c),
    do:
      Map.merge(
        Map.take(c.scope, [:namespace, :format, :operation_id]),
        %{key_id: key(c)["key_id"], fence_id: entry(c)["fence_id"]}
      )

  defp index(c), do: c.home <> "/project-identities/index.json"
  defp state(c), do: index(c) |> File.read!() |> Jason.decode!()
  defp key(c), do: state(c)["domain_keys"][c.binding["project_id"]]
  defp entry(c), do: key(c)["namespaces"][c.scope.namespace]

  defp private(path),
    do:
      (
        File.mkdir!(path)
        File.chmod!(path, 0o700)
      )

  defp pure_key do
    {%{
       "version" => 1,
       "key_id" => String.duplicate("1", 32),
       "master" => Base.url_encode64(:binary.copy(<<17>>, 32), padding: false),
       "namespaces" => %{}
     },
     %{
       "version" => 1,
       "format" => "managed-metadata-v3",
       "fence_id" => String.duplicate("2", 32),
       "state" => "active",
       "first_operation_id" => String.duplicate("3", 32),
       "first_root_sha256" => Ipse.JSON.sha256("root")
     }}
  end
end
