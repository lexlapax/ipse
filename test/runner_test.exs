defmodule Ipse.RunnerTest do
  use ExUnit.Case, async: false
  alias Ipse.Runner

  setup do
    cwd =
      Path.join(System.tmp_dir!(), "ipse-runner-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(cwd)
    on_exit(fn -> File.rm_rf!(cwd) end)
    %{cwd: cwd}
  end

  test "advisory lock excludes another owner and unlocks without deleting its inode", %{cwd: cwd} do
    path = Path.join(cwd, "session.lock")
    assert {:ok, lock} = Runner.lock(path)
    inode = File.stat!(path).inode
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
    assert {:error, _} = Runner.lock(path)
    assert :ok = Runner.unlock(lock)
    assert :ok = Runner.unlock(lock)
    assert File.stat!(path).inode == inode
    assert {:ok, next} = await_lock(path, 50)
    assert :ok = Runner.unlock(next)
  end

  test "advisory lock releases when its owner dies", %{cwd: cwd} do
    path = Path.join(cwd, "session.lock")
    parent = self()

    owner =
      spawn(fn ->
        assert {:ok, _lock} = Runner.lock(path)
        send(parent, :locked)
        Process.sleep(:infinity)
      end)

    assert_receive :locked, 5_000
    assert {:error, _} = Runner.lock(path)
    Process.exit(owner, :kill)
    assert {:ok, next} = await_lock(path, 50)
    Runner.unlock(next)
  end

  test "advisory lock rejects symbolic links", %{cwd: cwd} do
    target = Path.join(cwd, "target")
    File.write!(target, "keep")
    link = Path.join(cwd, "lock")
    File.ln_s!(target, link)
    assert {:error, _} = Runner.lock(link)
    assert File.read!(target) == "keep"
  end

  defp await_lock(_path, 0), do: {:error, "lock was not released"}

  defp await_lock(path, attempts) do
    case Runner.lock(path) do
      {:ok, lock} ->
        {:ok, lock}

      {:error, _} ->
        Process.sleep(20)
        await_lock(path, attempts - 1)
    end
  end

  test "captures both streams, exit status, and incremental events", %{cwd: cwd} do
    owner = self()

    assert {:ok, result} =
             Runner.run("printf hello; printf error >&2; exit 7", cwd,
               emit: fn event -> send(owner, event) end
             )

    assert result.exit_code == 7
    refute result.timed_out
    assert result.output =~ "hello"
    assert result.output =~ "error"
    assert_receive {:tool_output, chunk}
    assert String.valid?(chunk)
  end

  test "bounds output while draining a much larger stream", %{cwd: cwd} do
    assert {:ok, result} =
             Runner.run("head -c 1000000 /dev/zero | tr '\\000' x", cwd,
               output_limit: 101,
               timeout_ms: 5_000
             )

    assert result.exit_code == 0
    assert result.output == String.duplicate("x", 101)
  end

  test "keeps UTF-8 valid at the byte boundary", %{cwd: cwd} do
    assert {:ok, result} = Runner.run("printf '€€€'", cwd, output_limit: 7)
    assert result.output == "€€"
    assert String.valid?(result.output)
  end

  test "times out and terminates a descendant before it can write", %{cwd: cwd} do
    assert {:ok, result} =
             Runner.run("(sleep 0.5; printf survived > survived) & wait", cwd, timeout_ms: 60)

    assert result.timed_out
    Process.sleep(600)
    refute File.exists?(Path.join(cwd, "survived"))
  end

  test "owner death closes port and terminates descendants", %{cwd: cwd} do
    owner = self()

    pid =
      spawn(fn ->
        Runner.run("printf ready; (sleep 0.5; printf survived > orphan) & wait", cwd,
          emit: fn event -> send(owner, event) end
        )
      end)

    assert_receive {:tool_output, "ready"}, 5_000
    Process.exit(pid, :kill)
    Process.sleep(650)
    refute File.exists?(Path.join(cwd, "orphan"))
  end

  test "provider credentials do not reach the shell", %{cwd: cwd} do
    keys = ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "IPSE_CHATGPT_ACCESS_TOKEN"]
    previous = Map.new(keys, &{&1, System.get_env(&1)})
    Enum.each(keys, &System.put_env(&1, "must-not-leak"))

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end)

    assert {:ok, result} =
             Runner.run(
               "printf '%s%s%s' \"$OPENAI_API_KEY\" \"$ANTHROPIC_API_KEY\" \"$IPSE_CHATGPT_ACCESS_TOKEN\"",
               cwd
             )

    assert result.output == ""
  end
end
