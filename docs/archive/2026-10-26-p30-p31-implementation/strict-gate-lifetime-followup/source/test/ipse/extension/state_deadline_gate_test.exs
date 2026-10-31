defmodule Ipse.Extension.StateDeadlineGateTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.State

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-state-time-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: Path.join(root, "state"), namespace: Ipse.JSON.sha256("synthetic-state")}
  end

  @tag state_deadline_probe: true
  test "diagnostic interposes the actual file-server rename after the State clock check", c do
    observer = self()
    token = make_ref()
    deadline = System.system_time(:millisecond) + 1000
    target = Path.join([c.root, c.namespace, "state.json"])

    debug = fn debug_state, event, _ ->
      case event do
        {:in, {:"$gen_call", _, {:rename, _from, destination}}} ->
          if to_string(destination) == target do
            send(observer, {:state_rename_held, self(), System.system_time(:millisecond)})

            receive do
              {:state_rename_release, ^token} -> :ok
            after
              5000 -> :ok
            end
          end

        _ ->
          :ok
      end

      debug_state
    end

    :ok = :sys.install(:file_server_2, {debug, nil})

    task =
      Task.async(fn -> State.execute(c.root, c.namespace, request(deadline), Ipse.Usage.id()) end)

    try do
      assert_receive {:state_rename_held, server, checked}, 3000
      assert checked < deadline
      Process.sleep(max(deadline - System.system_time(:millisecond) + 50, 0))
      send(server, {:state_rename_release, token})
      assert {:ok, %{"record" => %{"value" => %{"text" => "synthetic"}}}} = Task.await(task, 5000)
      assert System.system_time(:millisecond) > deadline
      assert File.exists?(target)
      IO.puts("LATE_STATE_RENAME_PROVED checked_before=true resumed_after=true result=ok")
    after
      if Process.alive?(task.pid),
        do: send(Process.whereis(:file_server_2), {:state_rename_release, token})

      :sys.remove(:file_server_2, debug)
      Task.shutdown(task, :brutal_kill)
    end
  end

  defp request(deadline),
    do: %{
      "op" => "state.put",
      "scope" => "session",
      "key" => "derived",
      "expected_revision" => 0,
      "value" => %{"text" => "synthetic"},
      "write_before_ms" => deadline
    }

  @tag state_lifetime_gate: true
  test "State deadline rejects before filesystem IO with a closed receipt; ordinary State remains available",
       c do
    operation = Ipse.Usage.id()
    request = request(System.system_time(:millisecond) + 60_000)
    assert {:failed, value} = State.execute(c.root, c.namespace, request, operation)
    assert value == %{"code" => "state_deadline_fence_unavailable"}
    assert State.valid_outcome?(request, "failed", value, operation)
    refute State.valid_outcome?(request, "failed", Map.put(value, "extra", true), operation)
    refute File.exists?(c.root)
    ordinary = Map.delete(request, "write_before_ms")

    assert {:ok, %{"generation" => 1}} =
             State.execute(c.root, c.namespace, ordinary, Ipse.Usage.id())

    assert {:ok, %{"record" => %{"value" => %{"text" => "synthetic"}}}} =
             State.execute(
               c.root,
               c.namespace,
               %{"op" => "state.get", "scope" => "session", "key" => "derived"},
               Ipse.Usage.id()
             )
  end
end
