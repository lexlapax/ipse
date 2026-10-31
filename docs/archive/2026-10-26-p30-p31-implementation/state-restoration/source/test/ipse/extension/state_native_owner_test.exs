defmodule Ipse.Extension.StateNativeOwnerTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.State
  alias Ipse.Runner.Transaction

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-state-owned-" <> Ipse.Usage.id())
    namespace = Ipse.JSON.sha256("owned-state-fixture")
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, namespace: namespace}
  end

  defp request(value),
    do: %{
      "op" => "state.put",
      "scope" => "project",
      "key" => "note",
      "expected_revision" => 0,
      "value" => value
    }

  test "native decision reply is closed and agrees with its original deadline" do
    assert :ok = Transaction.state_decision_reply(nil, <<1, 123::64>>)
    assert :ok = Transaction.state_decision_reply(100, <<1, 99::64>>)
    assert {:elapsed, 100} = Transaction.state_decision_reply(100, <<0, 100::64>>)
    assert {:elapsed, 0} = Transaction.state_decision_reply(0, <<0, 0::64>>)

    for {deadline, payload} <- [
          {nil, <<>>},
          {nil, <<0, 100::64>>},
          {100, <<1, 100::64>>},
          {100, <<0, 99::64>>},
          {100, <<2, 100::64>>},
          {nil, <<1, 9_007_199_254_740_992::64>>},
          {-1, <<0, 0::64>>},
          {100, <<1, 99::64, 0>>}
        ] do
      assert {:unknown, :transaction_protocol} =
               Transaction.state_decision_reply(deadline, payload)
    end
  end

  test "ordinary state retains schema and reads an owner-private legacy file", c do
    assert {:ok, %{"generation" => 1}} =
             State.execute(c.root, c.namespace, request(%{"text" => "one"}), Ipse.Usage.id())

    file = Path.join([c.root, c.namespace, "state.json"])
    File.chmod!(file, 0o400)
    get = %{"op" => "state.get", "scope" => "project", "key" => "note"}

    assert {:ok, %{"record" => %{"value" => %{"text" => "one"}}}} =
             State.execute(c.root, c.namespace, get, Ipse.Usage.id())

    assert {:conflict, _} =
             State.execute(c.root, c.namespace, request(%{"text" => "two"}), Ipse.Usage.id())

    assert {:ok, %{"generation" => 2}} =
             State.execute(
               c.root,
               c.namespace,
               %{request(%{"text" => "two"}) | "expected_revision" => 1},
               Ipse.Usage.id()
             )
  end

  test "private State decision returns exact elapsed and release acknowledgment", c do
    path = Path.join(c.root, c.namespace)
    File.mkdir_p!(path)
    File.chmod!(c.root, 0o700)
    File.chmod!(path, 0o700)

    Ipse.Session.Resources.file_effect(fn ->
      assert {:ok, cap} = Transaction.acquire(Path.join(path, ".lock"), cwd: path)
      assert :ok = Transaction.state_begin(cap, true)
      assert :absent = Transaction.state_read(cap)
      assert :ok = Transaction.state_stage(cap, ".state-pending-" <> Ipse.Usage.id(), "body")
      assert {:elapsed, checked} = Transaction.state_commit(cap, 0)
      assert checked > 0
      assert :ok = Transaction.release(cap)
      refute File.exists?(Path.join(path, "state.json"))
    end)
  end

  test "timed public put uses native decision with an expired deadline", c do
    timed = Map.put(request(%{}), "write_before_ms", 0)
    operation_id = Ipse.Usage.id()

    assert {:failed, %{"code" => "write_deadline_elapsed"} = failure} =
             State.execute(c.root, c.namespace, timed, operation_id)

    assert State.valid_outcome?(timed, "failed", failure, operation_id)
    refute File.exists?(Path.join([c.root, c.namespace, "state.json"]))
  end

  test "revision conflict precedes expiry and expiry precedes exhausted revision quota", c do
    get = %{"op" => "state.get", "scope" => "project", "key" => "note"}
    assert {:ok, _} = State.execute(c.root, c.namespace, get, Ipse.Usage.id())
    maximum = 9_007_199_254_740_991

    record = %{
      "key" => "note",
      "revision" => maximum,
      "deleted" => false,
      "value" => %{},
      "operation_id" => Ipse.Usage.id()
    }

    state = %{
      "version" => 1,
      "namespace" => c.namespace,
      "generation" => maximum,
      "records" => %{"note" => record}
    }

    file = Path.join([c.root, c.namespace, "state.json"])
    File.write!(file, Jason.encode!(state))
    File.chmod!(file, 0o600)
    expired = request(%{}) |> Map.put("write_before_ms", 0)
    assert {:conflict, _} = State.execute(c.root, c.namespace, expired, Ipse.Usage.id())
    matching = Map.put(expired, "expected_revision", maximum)

    assert {:failed, %{"code" => "write_deadline_elapsed"}} =
             State.execute(c.root, c.namespace, matching, Ipse.Usage.id())

    live = Map.put(matching, "write_before_ms", System.system_time(:millisecond) + 60_000)

    assert {:failed, %{"code" => "extension_state_quota"}} =
             State.execute(c.root, c.namespace, live, Ipse.Usage.id())

    assert Jason.decode!(File.read!(file)) == state
  end

  test "reads never clean abandoned stages; mutations remove only private State stages", c do
    assert {:ok, _} = State.execute(c.root, c.namespace, request(%{"v" => 1}), Ipse.Usage.id())
    path = Path.join(c.root, c.namespace)
    orphan = Path.join(path, ".state-pending-" <> String.duplicate("a", 32))
    unrelated = Path.join(path, ".pending-" <> String.duplicate("b", 32))
    File.write!(orphan, "orphan")
    File.chmod!(orphan, 0o600)
    File.write!(unrelated, "operator data")
    File.chmod!(unrelated, 0o600)
    get = %{"op" => "state.get", "scope" => "project", "key" => "note"}
    assert {:ok, _} = State.execute(c.root, c.namespace, get, Ipse.Usage.id())
    assert File.exists?(orphan)

    assert {:ok, _} =
             State.execute(
               c.root,
               c.namespace,
               %{request(%{"v" => 2}) | "expected_revision" => 1},
               Ipse.Usage.id()
             )

    refute File.exists?(orphan)
    assert File.read!(unrelated) == "operator data"
  end

  test "an unsafe reserved stage refuses mutation without touching it", c do
    assert {:ok, _} = State.execute(c.root, c.namespace, request(%{"v" => 1}), Ipse.Usage.id())
    path = Path.join(c.root, c.namespace)
    orphan = Path.join(path, ".state-pending-" <> String.duplicate("a", 32))
    File.ln_s!("missing", orphan)

    assert {:error, :extension_state_unavailable} =
             State.execute(
               c.root,
               c.namespace,
               %{request(%{"v" => 2}) | "expected_revision" => 1},
               Ipse.Usage.id()
             )

    assert {:ok, %{type: :symlink}} = File.lstat(orphan)
  end
end
