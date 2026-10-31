defmodule Ipse.Extension.StateOwnerLossTest do
  use ExUnit.Case, async: false
  @moduletag skip: System.get_env("IPSE_STATE_NATIVE_HOOK_TEST") != "1"
  alias Ipse.Extension.State
  alias Ipse.Runner.Transaction

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-state-loss-" <> Ipse.Usage.id())
    namespace = Ipse.JSON.sha256("state-loss-fixture")
    on_exit(fn -> File.rm_rf!(root) end)

    put = %{
      "op" => "state.put",
      "scope" => "project",
      "key" => "note",
      "expected_revision" => 0,
      "value" => %{"text" => "old"}
    }

    assert {:ok, _} = State.execute(root, namespace, put, Ipse.Usage.id())
    path = Path.join(root, namespace)

    %{
      root: root,
      namespace: namespace,
      path: path,
      put: %{put | "expected_revision" => 1, "value" => %{"text" => "new"}}
    }
  end

  defp ready(path, remaining \\ 300)
  defp ready(path, 0), do: flunk("native hook did not become ready: #{path}")

  defp ready(path, remaining) do
    if File.exists?(path),
      do: :ok,
      else:
        (
          Process.sleep(10)
          ready(path, remaining - 1)
        )
  end

  defp read(c, remaining \\ 300)
  defp read(_, 0), do: flunk("namespace lock was not released")

  defp read(c, remaining) do
    request = %{"op" => "state.get", "scope" => "project", "key" => "note"}

    case State.execute(c.root, c.namespace, request, Ipse.Usage.id()) do
      {:ok, result} ->
        result

      _ ->
        Process.sleep(10)
        read(c, remaining - 1)
    end
  end

  test "owner loss while native write is held does not publish under a contender", c do
    File.write!(Path.join(c.path, "state-hook.arm"), "")
    task = Task.async(fn -> State.execute(c.root, c.namespace, c.put, Ipse.Usage.id()) end)
    ready(Path.join(c.path, "state-before-decision.ready"))

    assert {:error, :transaction_busy} =
             Transaction.acquire(Path.join(c.path, ".lock"), cwd: c.path)

    assert Task.shutdown(task, :brutal_kill) == nil
    assert %{"record" => %{"value" => %{"text" => "old"}}} = read(c)
  end

  test "owner loss after rename leaves a truthful unknown effect", c do
    File.write!(Path.join(c.path, "state-hook.arm"), "")
    File.write!(Path.join(c.path, "state-before-decision.go"), "")
    File.write!(Path.join(c.path, "state-after-decision.go"), "")
    task = Task.async(fn -> State.execute(c.root, c.namespace, c.put, Ipse.Usage.id()) end)
    ready(Path.join(c.path, "state-after-rename.ready"))

    assert {:error, :transaction_busy} =
             Transaction.acquire(Path.join(c.path, ".lock"), cwd: c.path)

    assert Task.shutdown(task, :brutal_kill) == nil
    assert %{"record" => %{"value" => %{"text" => "new"}}} = read(c)
  end

  test "a malformed native completion cannot become known success", c do
    File.write!(Path.join(c.path, "state-malformed-reply"), "")
    assert {:unknown, %{}} = State.execute(c.root, c.namespace, c.put, Ipse.Usage.id())
    assert %{"record" => %{"value" => %{"text" => "new"}}} = read(c)
  end

  test "State returns the native elapsed receipt when staged output crosses expiry", c do
    File.write!(Path.join(c.path, "state-hook.arm"), "")
    deadline = System.system_time(:millisecond) + 500
    request = Map.put(c.put, "write_before_ms", deadline)
    operation = Ipse.Usage.id()
    task = Task.async(fn -> State.execute(c.root, c.namespace, request, operation) end)
    ready(Path.join(c.path, "state-before-decision.ready"))
    Process.sleep(max(deadline - System.system_time(:millisecond) + 20, 0))
    File.write!(Path.join(c.path, "state-before-decision.go"), "")

    assert {:failed, %{"code" => "write_deadline_elapsed", "checked_at_ms" => checked} = result} =
             Task.await(task, 5_000)

    assert checked >= deadline
    assert State.valid_outcome?(request, "failed", result, operation)
    assert %{"record" => %{"value" => %{"text" => "old"}}} = read(c)
  end
end
