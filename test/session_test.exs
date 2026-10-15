defmodule Runespell.SessionTest do
  use ExUnit.Case, async: false

  defmodule Fake do
    def complete(config, messages, _tools, _emit) do
      send(config.test_pid, {:model_input, messages})

      case config[:scenario] do
        :wait ->
          send(config.test_pid, {:worker, self()})
          Process.sleep(:infinity)

        :write ->
          if List.last(messages)["role"] == "tool" do
            {:ok, %{"role" => "assistant", "content" => "Done"}, %{}}
          else
            {:ok,
             %{
               "role" => "assistant",
               "content" => "",
               "tool_calls" => [
                 %{
                   "id" => "call-1",
                   "type" => "function",
                   "function" => %{
                     "name" => "write",
                     "arguments" => ~s({"path":"file.txt","content":"hello"})
                   }
                 }
               ]
             }, %{}}
          end

        _ ->
          {:ok, %{"role" => "assistant", "content" => "Done"}, %{}}
      end
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "runespell-session-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, dir: Path.join(root, "state")}
  end

  defp session(ctx, config, id \\ nil) do
    config =
      Map.merge(
        %{
          provider: :demo,
          model: "test",
          provider_module: Fake,
          test_pid: self(),
          approval: :ask
        },
        config
      )

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Runespell.Sessions,
        {Runespell.Session,
         config: config, cwd: ctx.root, state_dir: ctx.dir, id: id, subscriber: self()}
      )

    on_exit(fn ->
      if Process.alive?(pid), do: DynamicSupervisor.terminate_child(Runespell.Sessions, pid)
    end)

    pid
  end

  test "writes wait for approval; denied actions remain in transcript", ctx do
    pid = session(ctx, %{scenario: :write})
    assert :ok = Runespell.Session.prompt(pid, "write")
    assert_receive {:runespell, ^pid, {:approval, ref, "write", _}}, 2000
    refute File.exists?(Path.join(ctx.root, "file.txt"))
    assert :ok = Runespell.Session.approve(pid, ref, false)
    assert_receive {:runespell, ^pid, {:done, :ok}}, 2000
    refute File.exists?(Path.join(ctx.root, "file.txt"))
    id = Runespell.Session.info(pid).id
    {:ok, events} = Runespell.Journal.load(ctx.dir, id)

    assert Enum.any?(events, fn e ->
             String.contains?(get_in(e, ["message", "content"]) || "", "Denied by user")
           end)
  end

  test "approved writes execute, survive resume, and do not rerun on startup", ctx do
    pid = session(ctx, %{scenario: :write, approval: :allow})
    Runespell.Session.prompt(pid, "write")
    assert_receive {:runespell, ^pid, {:done, :ok}}, 2000
    assert File.read!(Path.join(ctx.root, "file.txt")) == "hello"
    id = Runespell.Session.info(pid).id
    DynamicSupervisor.terminate_child(Runespell.Sessions, pid)
    File.write!(Path.join(ctx.root, "file.txt"), "user edit")
    resumed = session(ctx, %{}, id)
    assert Runespell.Session.info(resumed).phase == :idle
    assert File.read!(Path.join(ctx.root, "file.txt")) == "user edit"
    Runespell.Session.prompt(resumed, "what happened?")
    assert_receive {:runespell, ^resumed, {:done, :ok}}, 2000
  end

  test "model can be cancelled and another turn started", ctx do
    pid = session(ctx, %{scenario: :wait})
    Runespell.Session.prompt(pid, "wait")
    assert_receive {:model_input, _}, 2000
    assert Runespell.Session.prompt(pid, "another") == {:error, :busy}
    assert :ok = Runespell.Session.cancel(pid)
    assert_receive {:runespell, ^pid, {:done, :cancelled}}
    assert Runespell.Session.info(pid).phase == :idle
  end

  test "session death stops its worker and permits resume in the same BEAM", ctx do
    pid = session(ctx, %{scenario: :wait})
    id = Runespell.Session.info(pid).id
    Runespell.Session.prompt(pid, "wait")
    assert_receive {:worker, worker}, 2000
    worker_ref = Process.monitor(worker)
    owner_ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^owner_ref, :process, ^pid, :killed}, 2000
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}, 2000
    resumed = session(ctx, %{}, id)
    assert Runespell.Session.info(resumed).phase == :idle
  end

  test "loss of the OS lock stops the session and active worker", ctx do
    pid = session(ctx, %{scenario: :wait})
    id = Runespell.Session.info(pid).id
    Runespell.Session.prompt(pid, "wait")
    assert_receive {:worker, worker}, 2000
    worker_ref = Process.monitor(worker)
    owner_ref = Process.monitor(pid)
    lock = :sys.get_state(pid).lock
    {:os_pid, os_pid} = Port.info(lock, :os_pid)
    {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(os_pid)])
    assert_receive {:runespell, ^pid, {:done, :error}}, 2000
    assert_receive {:DOWN, ^owner_ref, :process, ^pid, :normal}, 2000
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}, 2000
    resumed = session(ctx, %{}, id)
    assert Runespell.Session.info(resumed).phase == :idle
  end

  test "resume repairs a crash-truncated journal tail before accepting input", ctx do
    pid = session(ctx, %{})
    id = Runespell.Session.info(pid).id
    DynamicSupervisor.terminate_child(Runespell.Sessions, pid)
    File.write!(Path.join(ctx.dir, id <> ".jsonl"), "{\"type\":", [:append])
    resumed = session(ctx, %{}, id)
    assert :ok = Runespell.Session.prompt(resumed, "continue")
    assert_receive {:runespell, ^resumed, {:done, :ok}}, 2000
  end

  test "unresolved historical tool calls become unknown, never dispatched", ctx do
    {:ok, id} =
      Runespell.Journal.create(ctx.dir, %{
        "cwd" => ctx.root,
        "provider" => "demo",
        "model" => "test"
      })

    Runespell.Journal.append(ctx.dir, id, %{
      "type" => "message",
      "message" => %{
        "role" => "assistant",
        "content" => "",
        "tool_calls" => [
          %{
            "id" => "old-call",
            "type" => "function",
            "function" => %{
              "name" => "write",
              "arguments" => ~s({"path":"should-not-exist","content":"bad"})
            }
          }
        ]
      }
    })

    pid = session(ctx, %{}, id)
    Runespell.Session.prompt(pid, "inspect")
    assert_receive {:model_input, messages}, 2000

    assert Enum.any?(
             messages,
             &(&1["role"] == "tool" and String.contains?(&1["content"], "Outcome unknown"))
           )

    assert_receive {:runespell, ^pid, {:done, :ok}}, 2000
    refute File.exists?(Path.join(ctx.root, "should-not-exist"))
  end

  test "demo exercises skills, writes, reads and real shell", ctx do
    pid = session(ctx, %{provider_module: Runespell.Provider.Demo, approval: :allow})
    Runespell.Session.prompt(pid, "demo")
    assert_receive {:runespell, ^pid, {:done, :ok}}, 5000
    assert File.read!(Path.join(ctx.root, "runespell-demo.txt")) == "Hello from Runespell!\n"
    assert Runespell.Session.info(pid).final =~ "scripted demo"
  end
end
