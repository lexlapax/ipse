defmodule Ipse.Runner.StateOwnerNativeTest do
  use ExUnit.Case, async: false
  @moduletag skip: System.get_env("IPSE_STATE_NATIVE_HOOK_TEST") != "1"

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-state-owner-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    File.write!(Path.join(root, "state.json"), "old")
    File.chmod!(Path.join(root, "state.json"), 0o600)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  defp open_owner(_root, hook \\ nil) do
    env = if hook, do: [{~c"IPSE_TEST_STATE_HOOK", String.to_charlist(hook)}], else: []

    helper = System.fetch_env!("IPSE_STATE_HOOK_HELPER") |> String.to_charlist()

    Port.open({:spawn_executable, helper}, [
      :binary,
      :exit_status,
      :use_stdio,
      :hide,
      args: [~c"--transaction-lock", ~c"15000"],
      env: env
    ])
  end

  defp send_command(port, tag, seq, depth, body \\ <<>>) do
    payload = <<seq::64, depth, body::binary>>
    assert Port.command(port, <<tag, byte_size(payload)::32, payload::binary>>)
  end

  defp reply(port, expected, seq, depth), do: reply(port, expected, seq, depth, <<>>)

  defp reply(port, expected, seq, depth, buffer) do
    case buffer do
      <<^expected, size::32, body::binary-size(size)>> ->
        <<^seq::64, ^depth, rest::binary>> = body
        rest

      _ ->
        receive do
          {^port, {:data, bytes}} -> reply(port, expected, seq, depth, buffer <> bytes)
          {^port, {:exit_status, status}} -> flunk("helper exited before reply: #{status}")
        after
          5_000 -> flunk("helper reply timed out")
        end
    end
  end

  defp prepare(root, hook) do
    File.write!(Path.join(root, "state-hook.arm"), "")
    port = open_owner(root, hook)
    send_command(port, ?A, 1, 0, Path.join(root, ".lock"))
    assert reply(port, ?A, 1, 1) == <<>>
    send_command(port, ?J, 2, 1, <<1>>)
    assert reply(port, ?J, 2, 1) == <<>>
    name = ".state-pending-" <> String.duplicate("a", 32)
    send_command(port, ?W, 3, 1, <<0, 1, name::binary, 3::32>>)
    assert reply(port, ?W, 3, 1) == <<>>
    send_command(port, ?D, 4, 1, "new")
    assert reply(port, ?D, 4, 1) == <<>>
    port
  end

  defp ready(path, tries \\ 300)
  defp ready(path, 0), do: flunk("hook did not become ready: #{path}")

  defp ready(path, tries) do
    if File.exists?(path),
      do: :ok,
      else:
        (
          Process.sleep(10)
          ready(path, tries - 1)
        )
  end

  defp release(port, seq) do
    send_command(port, ?R, seq, 1)
    assert reply(port, ?R, seq, 0) == <<>>
    assert_receive {^port, {:exit_status, 0}}, 5_000
  end

  test "staging held across deadline produces known elapsed without replacement", c do
    port = prepare(c.root, c.root)
    deadline = System.system_time(:millisecond) + 350
    send_command(port, ?V, 5, 1, <<1, deadline::64>>)
    ready(Path.join(c.root, "state-before-decision.ready"))
    Process.sleep(max(deadline - System.system_time(:millisecond) + 30, 0))
    File.write!(Path.join(c.root, "state-before-decision.go"), "")
    assert <<0, checked::64>> = reply(port, ?V, 5, 1)
    assert checked >= deadline
    assert File.read!(Path.join(c.root, "state.json")) == "old"
    refute File.exists?(Path.join(c.root, ".state-pending-" <> String.duplicate("a", 32)))
    release(port, 6)
  end

  test "a valid final decision can physically complete after the deadline", c do
    File.write!(Path.join(c.root, "state-before-decision.go"), "")
    File.write!(Path.join(c.root, "state-after-rename.go"), "")
    port = prepare(c.root, c.root)
    deadline = System.system_time(:millisecond) + 350
    send_command(port, ?V, 5, 1, <<1, deadline::64>>)
    ready(Path.join(c.root, "state-after-decision.ready"))
    Process.sleep(max(deadline - System.system_time(:millisecond) + 30, 0))
    assert File.read!(Path.join(c.root, "state.json")) == "old"
    File.write!(Path.join(c.root, "state-after-decision.go"), "")
    assert <<1, checked::64>> = reply(port, ?V, 5, 1)
    assert checked < deadline
    assert File.read!(Path.join(c.root, "state.json")) == "new"
    release(port, 6)
  end

  test "dead owner cannot replace state after an independent contender acquires", c do
    port = prepare(c.root, c.root)
    send_command(port, ?V, 5, 1, <<0, 0::64>>)
    ready(Path.join(c.root, "state-before-decision.ready"))
    {:os_pid, pid} = Port.info(port, :os_pid)
    assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(pid)])
    assert_receive {^port, {:exit_status, _}}, 5_000
    contender = open_owner(c.root)
    send_command(contender, ?A, 1, 0, Path.join(c.root, ".lock"))
    assert reply(contender, ?A, 1, 1) == <<>>
    File.write!(Path.join(c.root, "state-before-decision.go"), "")
    assert File.read!(Path.join(c.root, "state.json")) == "old"
    orphan = Path.join(c.root, ".state-pending-" <> String.duplicate("a", 32))
    assert File.exists?(orphan)
    send_command(contender, ?J, 2, 1, <<1>>)
    assert reply(contender, ?J, 2, 1) == <<>>
    refute File.exists?(orphan)
    release(contender, 3)
  end

  test "loss after rename leaves an actual effect with no successful acknowledgment", c do
    File.write!(Path.join(c.root, "state-before-decision.go"), "")
    File.write!(Path.join(c.root, "state-after-decision.go"), "")
    port = prepare(c.root, c.root)
    send_command(port, ?V, 5, 1, <<0, 0::64>>)
    ready(Path.join(c.root, "state-after-rename.ready"))
    assert File.read!(Path.join(c.root, "state.json")) == "new"
    {:os_pid, pid} = Port.info(port, :os_pid)
    assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(pid)])
    assert_receive {^port, {:exit_status, _}}, 5_000
    contender = open_owner(c.root)
    send_command(contender, ?A, 1, 0, Path.join(c.root, ".lock"))
    assert reply(contender, ?A, 1, 1) == <<>>
    assert File.read!(Path.join(c.root, "state.json")) == "new"
    release(contender, 2)
  end

  test "a substituted observed target cannot be committed", c do
    port = prepare(c.root, nil)
    File.rename!(Path.join(c.root, "state.json"), Path.join(c.root, "previous"))
    File.write!(Path.join(c.root, "state.json"), "other")
    File.chmod!(Path.join(c.root, "state.json"), 0o600)
    send_command(port, ?V, 5, 1, <<0, 0::64>>)
    assert reply(port, ?U, 5, 1) == <<2>>
    assert_receive {^port, {:exit_status, 0}}, 5_000
    assert File.read!(Path.join(c.root, "state.json")) == "other"
  end

  test "a replaced staged inode cannot be published", c do
    port = prepare(c.root, nil)
    stage = Path.join(c.root, ".state-pending-" <> String.duplicate("a", 32))
    File.rename!(stage, stage <> ".old")
    File.write!(stage, "bad")
    File.chmod!(stage, 0o600)
    send_command(port, ?V, 5, 1, <<0, 0::64>>)
    assert reply(port, ?E, 5, 1) == <<2>>
    assert File.read!(Path.join(c.root, "state.json")) == "old"
    release(port, 6)
  end

  test "zero deadline is a valid expired decision", c do
    port = prepare(c.root, nil)
    send_command(port, ?V, 5, 1, <<1, 0::64>>)
    assert <<0, checked::64>> = reply(port, ?V, 5, 1)
    assert checked > 0
    assert File.read!(Path.join(c.root, "state.json")) == "old"
    release(port, 6)
  end

  test "oversized staged body and a second finish fail closed", c do
    port = open_owner(c.root)
    send_command(port, ?A, 1, 0, Path.join(c.root, ".lock"))
    assert reply(port, ?A, 1, 1) == <<>>
    send_command(port, ?J, 2, 1, <<1>>)
    assert reply(port, ?J, 2, 1) == <<>>
    name = ".state-pending-" <> String.duplicate("b", 32)
    send_command(port, ?W, 3, 1, <<0, 1, name::binary, 1_048_577::32>>)
    assert reply(port, ?U, 3, 1) == <<2>>
    assert_receive {^port, {:exit_status, 0}}, 5_000
    assert File.read!(Path.join(c.root, "state.json")) == "old"

    port = prepare(c.root, nil)
    send_command(port, ?V, 5, 1, <<1, 0::64>>)
    assert <<0, _::64>> = reply(port, ?V, 5, 1)
    send_command(port, ?V, 6, 1, <<1, 0::64>>)
    assert_receive {^port, {:exit_status, status}}, 5_000
    refute status == 0
    assert File.read!(Path.join(c.root, "state.json")) == "old"
  end
end
