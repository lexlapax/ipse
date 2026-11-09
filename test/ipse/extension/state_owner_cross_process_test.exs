defmodule Ipse.Extension.StateOwnerCrossProcessTest do
  use ExUnit.Case, async: false

  test "independent VMs sharing the native namespace cannot both commit the same generation" do
    root = Path.join(System.tmp_dir!(), "ipse-state-vms-" <> Ipse.Usage.id())
    namespace = Ipse.JSON.sha256("independent-state-owners")
    on_exit(fn -> File.rm_rf!(root) end)
    read = %{"op" => "state.get", "scope" => "project", "key" => "probe"}
    assert {:ok, _} = Ipse.Extension.State.execute(root, namespace, read, Ipse.Usage.id())
    barrier = Path.join(root, "go")
    libs = :code.lib_dir(:ipse) |> List.to_string() |> Path.dirname()

    code = ~S'''
    {:ok, _} = Application.ensure_all_started(:ipse)
    [root, namespace, key, barrier] = System.argv()
    get = %{"op" => "state.get", "scope" => "project", "key" => key}
    {:ok, %{"generation" => 0}} = Ipse.Extension.State.execute(root, namespace, get, Ipse.Usage.id())
    File.write!(barrier <> "." <> key, "ready")
    deadline = System.monotonic_time(:millisecond) + 10_000
    wait = fn wait ->
      unless File.exists?(barrier) do
        if System.monotonic_time(:millisecond) >= deadline, do: raise("barrier timeout")
        Process.sleep(5)
        wait.(wait)
      end
    end
    wait.(wait)
    put = %{"op" => "state.put", "scope" => "project", "key" => key, "expected_revision" => 0, "expected_generation" => 0, "value" => %{"v" => key}}
    result = Ipse.Extension.State.execute(root, namespace, put, Ipse.Usage.id())
    status = case result do
      {:ok, _} -> "ok"
      {:conflict, _} -> "conflict"
      {:failed, %{"code" => "extension_state_unavailable"}} -> "contended"
      other -> raise(inspect(other))
    end
    IO.puts(status)
    '''

    tasks =
      for key <- ~w(first second) do
        task =
          Task.async(fn ->
            System.cmd(
              System.find_executable("elixir"),
              ["-e", code, "--", root, namespace, key, barrier],
              env: [{"ERL_LIBS", libs}],
              stderr_to_stdout: true
            )
          end)

        wait_for(barrier <> "." <> key)
        task
      end

    try do
      File.write!(barrier, "go")

      results =
        Enum.map(tasks, fn task ->
          {out, status} = Task.await(task, 15_000)
          assert status == 0, out
          String.trim(out)
        end)

      assert Enum.count(results, &(&1 == "ok")) == 1
      assert Enum.all?(results, &(&1 in ~w(ok conflict contended)))

      assert {:ok, %{"generation" => 1}} =
               Ipse.Extension.State.execute(root, namespace, read, Ipse.Usage.id())
    after
      File.write!(barrier, "go")
      Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
    end
  end

  defp wait_for(path, attempts \\ 1000)
  defp wait_for(_, 0), do: flunk("independent VM did not reach its barrier")

  defp wait_for(path, attempts) do
    if File.exists?(path),
      do: :ok,
      else:
        (
          Process.sleep(10)
          wait_for(path, attempts - 1)
        )
  end
end
