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
               ["scripts/verify-memory-scope.exs", Path.expand("priv/ipse-runner")],
               stderr_to_stdout: true
             )

    result = JSON.decode!(String.trim(bytes))
    assert result["checks"] == 10
    assert result["inference_requests"] == 0
    assert result["timeout_cleanup"]
    assert result["owner_loss_cleanup"]
    assert result["collector_loss_incomplete"]
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
