defmodule Ipse.MemoryScopeTest do
  use ExUnit.Case, async: false

  test "exact measurement refuses before command execution outside its dedicated Linux service" do
    root =
      Path.join(System.tmp_dir!(), "ipse-scope-refusal-#{System.unique_integer([:positive])}")

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    output = Path.join(root, "measurement")
    marker = Path.join(root, "executed")
    id = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

    port =
      Port.open({:spawn_executable, Path.expand("priv/ipse-runner")}, [
        :binary,
        :exit_status,
        {:args,
         [
           "--measure-cgroup",
           "root",
           id,
           "1000",
           output,
           "--",
           "/bin/sh",
           "-c",
           "printf executed > \"$1\"",
           "ipse-fixture",
           marker
         ]}
      ])

    assert {bytes, 1} = read_result(port, "")

    assert <<?E, size::32, error::binary-size(size)>> = bytes

    assert error =~
             if(match?({:unix, :linux}, :os.type()),
               do: "dedicated delegated user service",
               else: "requires supported Linux"
             )

    refute File.exists?(output)
    refute File.exists?(marker)
  end

  @tag :memory_scope
  @tag timeout: 60_000
  test "owned kernel scopes preserve overlap, ERTS peaks and interrupted outcomes" do
    assert {bytes, 0} =
             System.cmd(
               "elixir",
               [
                 "dev/verify-memory-scope.exs",
                 Path.expand("priv/ipse-runner") | Ipse.Provider.Registry.secret_env()
               ],
               stderr_to_stdout: true
             )

    result = JSON.decode!(String.trim(bytes))
    assert result["checks"] == 11
    assert result["credential_filter_keys"] == length(Ipse.Provider.Registry.secret_env())
    assert result["inference_requests"] == 0
    assert result["timeout_cleanup"]
    assert result["owner_loss_cleanup"]
    assert result["collector_loss_incomplete"]
  end

  test "measured sequencing refuses outside an admitted hierarchy before reading commands" do
    root =
      Path.join(System.tmp_dir!(), "ipse-sequence-refusal-#{System.unique_integer([:positive])}")

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    bootstrap = Path.join(root, "must-not-read")

    port =
      Port.open({:spawn_executable, Path.expand("priv/ipse-runner")}, [
        :binary,
        :exit_status,
        {:args, ["--measure-sequence", bootstrap]},
        {:env, [{~c"IPSE_MEASURE_ROOT", false}]}
      ])

    assert {bytes, 1} = read_result(port, "")
    assert <<?E, size::32, error::binary-size(size)>> = bytes

    assert error =~
             if(match?({:unix, :linux}, :os.type()),
               do: "sequence requires measured root",
               else: "measured sequencing requires Linux"
             )

    refute File.exists?(bootstrap)
    assert File.ls!(root) == []
  end

  @tag :memory_scope
  @tag timeout: 60_000
  test "post-reap population drain includes late allocation and retains loss and deadline failures" do
    assert {bytes, 0} =
             System.cmd(
               "elixir",
               ["dev/verify-memory-drain.exs", Path.expand("priv/ipse-runner")],
               stderr_to_stdout: true
             )

    result = JSON.decode!(String.trim(bytes))
    assert result["checks"] == 12
    assert result["inference_requests"] == 0
    assert result["allocation_after_leader_exit_included"]
    assert result["nested_tail_and_parent_interval_included"]
    assert result["late_zero_exit_refused"]
    assert result["owner_loss_during_drain"] and result["owner_eof_during_drain"]
    assert result["anchor_loss_during_drain"] and result["collector_loss_during_drain_incomplete"]
    assert result["authority_loss_during_drain"]
  end

  @tag :memory_scope
  @tag timeout: 60_000
  test "terminal output decision observes ownership and original deadline after natural emptiness" do
    assert {bytes, 0} =
             System.cmd(
               "elixir",
               ["dev/verify-memory-terminal.exs", Path.expand("priv/ipse-runner")],
               stderr_to_stdout: true
             )

    result = JSON.decode!(String.trim(bytes))
    assert result["checks"] == 4 and result["inference_requests"] == 0
    assert result["terminal_owner_loss_refused"] and result["terminal_original_deadline_refused"]
    assert result["reversed_terminal_guard_accepts_cancel"] and result["diagnostic_copies_only"]
  end

  @tag :memory_scope
  @tag timeout: 60_000
  test "complete measured sequences retain first attempts and reject malformed descriptors" do
    assert {bytes, 0} =
             System.cmd(
               "elixir",
               ["dev/verify-memory-sequence.exs", Path.expand("priv/ipse-runner")],
               stderr_to_stdout: true
             )

    result = JSON.decode!(String.trim(bytes))
    assert result["checks"] == 6
    assert result["inference_requests"] == 0
    assert result["measured_preparation"] and result["measured_finalization"]
    assert result["no_replay"] and result["lost_collector_halts"]
    assert result["bootstrap_fifo_refused"] and result["cells_fifo_refused"]
  end

  defp read_result(port, bytes) do
    receive do
      {^port, {:data, more}} -> read_result(port, bytes <> more)
      {^port, {:exit_status, code}} -> {bytes, code}
    after
      5_000 -> raise "native refusal timed out"
    end
  end
end
