defmodule Ipse.SessionTest do
  use ExUnit.Case, async: false

  defmodule Fake do
    def complete(config, messages, _tools, _emit) do
      send(config.test_pid, {:model_input, messages})

      case config[:scenario] do
        :identity ->
          reported =
            if List.last(messages)["content"] == "missing", do: nil, else: config[:reported]

          {:ok,
           %{
             "role" => "assistant",
             "content" => "Identity fixture",
             "provider_data" => %{"reported_model" => reported}
           }, %{}}

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
    root = Path.join(System.tmp_dir!(), "ipse-session-#{System.unique_integer([:positive])}")
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
          home: Path.join(ctx.root, "home"),
          test_pid: self(),
          approval: :ask
        },
        config
      )

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Ipse.Session,
         config: config, cwd: ctx.root, state_dir: ctx.dir, id: id, subscriber: self()}
      )

    on_exit(fn ->
      if Process.alive?(pid), do: DynamicSupervisor.terminate_child(Ipse.Sessions, pid)
    end)

    pid
  end

  test "writes wait for approval; denied actions remain in transcript", ctx do
    pid = session(ctx, %{scenario: :write})
    assert :ok = Ipse.Session.prompt(pid, "write")
    assert_receive {:ipse, ^pid, {:approval, ref, "write", _}}, 2000
    refute File.exists?(Path.join(ctx.root, "file.txt"))
    assert :ok = Ipse.Session.approve(pid, ref, false)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    refute File.exists?(Path.join(ctx.root, "file.txt"))
    id = Ipse.Session.info(pid).id
    {:ok, events} = Ipse.Journal.load(ctx.dir, id)

    assert Enum.any?(events, fn e ->
             String.contains?(get_in(e, ["message", "content"]) || "", "Denied by user")
           end)

    assert Enum.any?(events, fn e ->
             get_in(e, ["message", "ipse_tool_outcome"]) ==
               %{"status" => "denied", "approval" => "denied"}
           end)
  end

  test "invalid and oversized prompts refuse before changing the conversation", ctx do
    pid = session(ctx, %{})
    id = Ipse.Session.info(pid).id
    path = Path.join(ctx.dir, id <> ".jsonl")
    before = File.read!(path)

    for {prompt, expected} <- [
          {<<255>>, :invalid_prompt},
          {String.duplicate("a", 1_048_577), :prompt_too_large}
        ] do
      result =
        try do
          Ipse.Session.prompt(pid, prompt)
        catch
          :exit, _ -> :session_exited
        end

      assert result == {:error, expected}
      assert Ipse.Session.info(pid).phase == :idle
      assert File.read!(path) == before
      refute_received {:model_input, _}
    end

    assert :ok = Ipse.Session.prompt(pid, "valid later input")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
  end

  test "skill expansion cannot bypass prompt admission bounds", ctx do
    for n <- 1..17 do
      path = Path.join([ctx.root, ".agents", "skills", "large#{n}"])
      File.mkdir_p!(path)

      File.write!(
        Path.join(path, "SKILL.md"),
        "---\nname: large#{n}\ndescription: Fixture\n---\n" <> String.duplicate("a", 64_000)
      )
    end

    pid = session(ctx, %{})
    path = Path.join(ctx.dir, Ipse.Session.info(pid).id <> ".jsonl")
    before = File.read!(path)
    prompt = Enum.map_join(1..17, " ", &"$large#{&1}")
    assert {:error, :prompt_too_large} = Ipse.Session.prompt(pid, prompt)
    assert Ipse.Session.info(pid).phase == :idle
    assert File.read!(path) == before
    refute_received {:model_input, _}
  end

  test "skill expansion reads outside the owner and rejects a skill replaced with a FIFO", ctx do
    path = Path.join(ctx.root, ".agents/skills/review/SKILL.md")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "---\nname: review\ndescription: Fixture\n---\nReview text")
    pid = session(ctx, %{})
    :erlang.trace_pattern({Ipse.Workspace, :expand_skills, 2}, true, [])
    :erlang.trace(:new, true, [:call, {:tracer, self()}])

    try do
      assert :ok = Ipse.Session.prompt(pid, "$review")

      assert_receive {:trace, reader, :call, {Ipse.Workspace, :expand_skills, _}}, 2000
      refute reader == pid
      assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    after
      :erlang.trace(:new, false, [:call])
      :erlang.trace_pattern({Ipse.Workspace, :expand_skills, 2}, false, [])
    end

    File.rm!(path)
    :ok = Ipse.Test.FileEffectProbe.fifo!(path)
    assert {:error, :skill_catalog_changed} = Ipse.Session.prompt(pid, "$review")
    assert :ok = Ipse.Session.cancel(pid)
    assert Ipse.Session.info(pid).phase == :idle
    assert :ok = Ipse.Session.close_confirmed(pid)
    fresh = session(ctx, %{})
    refute Enum.any?(:sys.get_state(fresh).skills, &(&1["path"] == path))
  end

  test "cancellation settles a pending skill preflight caller and kills its owned task", ctx do
    pid = session(ctx, %{})
    ref = make_ref()
    caller = self()

    state =
      :sys.replace_state(pid, fn s ->
        task = Ipse.Session.owned_task(fn -> Process.sleep(:infinity) end)
        %{s | phase: :prompt_preflight, task: task, prompt_from: {caller, ref}}
      end)

    assert :ok = Ipse.Session.cancel(pid)
    assert_receive {^ref, {:error, :cancelled}}, 2000
    refute Process.alive?(state.task.pid)
    assert Ipse.Session.info(pid).phase == :idle
    assert :ok = Ipse.Session.prompt(pid, "another turn")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
  end

  test "failed skill preflight settles the caller without terminating the owner", ctx do
    pid = session(ctx, %{})
    ref = make_ref()
    caller = self()

    :sys.replace_state(pid, fn s ->
      task = Ipse.Session.owned_task(fn -> raise "synthetic skill read failure" end)
      %{s | phase: :prompt_preflight, task: task, prompt_from: {caller, ref}}
    end)

    assert_receive {^ref, {:error, :skill_catalog_changed}}, 2000
    assert_receive {:ipse, ^pid, {:done, :error}}, 2000
    assert Ipse.Session.info(pid).phase == :idle
    assert :ok = Ipse.Session.prompt(pid, "another turn")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
  end

  test "approved writes execute, survive resume, and do not rerun on startup", ctx do
    pid = session(ctx, %{scenario: :write, approval: :allow})
    Ipse.Session.prompt(pid, "write")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    assert File.read!(Path.join(ctx.root, "file.txt")) == "hello"
    id = Ipse.Session.info(pid).id
    {:ok, events} = Ipse.Journal.load(ctx.dir, id)

    assert Enum.any?(events, fn e ->
             get_in(e, ["message", "ipse_tool_outcome"]) ==
               %{"status" => "result_recorded", "approval" => "session_allow"}
           end)

    DynamicSupervisor.terminate_child(Ipse.Sessions, pid)
    File.write!(Path.join(ctx.root, "file.txt"), "user edit")
    resumed = session(ctx, %{}, id)
    assert Ipse.Session.info(resumed).phase == :idle
    assert File.read!(Path.join(ctx.root, "file.txt")) == "user edit"
    Ipse.Session.prompt(resumed, "what happened?")
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 2000
  end

  test "model can be cancelled and another turn started", ctx do
    pid = session(ctx, %{scenario: :wait})
    Ipse.Session.prompt(pid, "wait")
    assert_receive {:model_input, _}, 2000
    assert Ipse.Session.prompt(pid, "another") == {:error, :busy}
    assert :ok = Ipse.Session.cancel(pid)
    assert_receive {:ipse, ^pid, {:done, :cancelled}}
    assert Ipse.Session.info(pid).phase == :idle
  end

  test "cancelling a pending approval records that its effect never started", ctx do
    pid = session(ctx, %{scenario: :write})
    :ok = Ipse.Session.prompt(pid, "write")
    assert_receive {:ipse, ^pid, {:approval, _, "write", _}}, 2_000
    :ok = Ipse.Session.cancel(pid)
    assert_receive {:ipse, ^pid, {:done, :cancelled}}, 2_000
    {:ok, events} = Ipse.Journal.load(ctx.dir, Ipse.Session.info(pid).id)
    refute Enum.any?(events, &(&1["type"] == "tool_started"))

    assert Enum.any?(events, fn e ->
             get_in(e, ["message", "ipse_tool_outcome"]) ==
               %{"status" => "not_started", "approval" => "not_decided"}
           end)

    refute File.exists?(Path.join(ctx.root, "file.txt"))
  end

  test "session death stops its worker and permits resume in the same BEAM", ctx do
    pid = session(ctx, %{scenario: :wait})
    id = Ipse.Session.info(pid).id
    Ipse.Session.prompt(pid, "wait")
    assert_receive {:worker, worker}, 2000
    worker_ref = Process.monitor(worker)
    owner_ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^owner_ref, :process, ^pid, :killed}, 2000
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}, 2000
    resumed = session(ctx, %{}, id)
    assert Ipse.Session.info(resumed).phase == :idle
  end

  test "loss of the OS lock stops the session and active worker", ctx do
    pid = session(ctx, %{scenario: :wait})
    id = Ipse.Session.info(pid).id
    Ipse.Session.prompt(pid, "wait")
    assert_receive {:worker, worker}, 2000
    worker_ref = Process.monitor(worker)
    owner_ref = Process.monitor(pid)
    lock = :sys.get_state(pid).lock
    {:os_pid, os_pid} = Port.info(lock, :os_pid)
    {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(os_pid)])
    assert_receive {:ipse, ^pid, {:done, :error}}, 2000
    assert_receive {:DOWN, ^owner_ref, :process, ^pid, :normal}, 2000
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}, 2000
    resumed = session(ctx, %{}, id)
    assert Ipse.Session.info(resumed).phase == :idle
  end

  test "resume repairs a crash-truncated journal tail before accepting input", ctx do
    pid = session(ctx, %{})
    id = Ipse.Session.info(pid).id
    DynamicSupervisor.terminate_child(Ipse.Sessions, pid)
    File.write!(Path.join(ctx.dir, id <> ".jsonl"), "{\"type\":", [:append])
    resumed = session(ctx, %{}, id)
    assert :ok = Ipse.Session.prompt(resumed, "continue")
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 2000
  end

  test "unresolved historical tool calls become unknown, never dispatched", ctx do
    {:ok, id} =
      Ipse.Journal.create(ctx.dir, %{
        "cwd" => ctx.root,
        "provider" => "demo",
        "model" => "test"
      })

    Ipse.Journal.append(ctx.dir, id, %{
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
    Ipse.Session.prompt(pid, "inspect")
    assert_receive {:model_input, messages}, 2000

    assert Enum.any?(
             messages,
             &(&1["role"] == "tool" and String.contains?(&1["content"], "Outcome unknown"))
           )

    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    refute File.exists?(Path.join(ctx.root, "should-not-exist"))
  end

  test "demo exercises skills, writes, reads and real shell", ctx do
    pid = session(ctx, %{provider_module: Ipse.Provider.Demo, approval: :allow})
    Ipse.Session.prompt(pid, "demo")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5000
    assert File.read!(Path.join(ctx.root, "ipse-demo.txt")) == "Hello from Ipse!\n"
    assert Ipse.Session.info(pid).final =~ "scripted demo"
  end

  test "runtime identity reaches each turn and missing reports clear the last response", ctx do
    pid =
      session(ctx, %{
        provider: :ollama,
        model: "chosen:alias",
        scenario: :identity,
        reported: "reported-snapshot",
        api_key: "private-token"
      })

    assert Ipse.Session.info(pid).runtime.reported_model == nil
    Ipse.Session.prompt(pid, "identity")
    assert_receive {:model_input, [system | _]}, 2000
    assert system["content"] =~ "Configured provider: ollama"
    assert system["content"] =~ "Requested model: chosen:alias"
    refute system["content"] =~ "private-token"
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    assert Ipse.Session.info(pid).runtime.reported_model == "reported-snapshot"
    refute inspect(Ipse.Session.info(pid)) =~ "private-token"

    Ipse.Session.prompt(pid, "missing")
    assert_receive {:model_input, [system | _]}, 2000
    assert system["content"] =~ "Last response model (current run): reported-snapshot"
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    assert Ipse.Session.info(pid).runtime.reported_model == nil
  end

  test "resume refuses silently weakening the saved shell sandbox policy", ctx do
    pid = session(ctx, %{sandbox: :native, scenario: :identity})
    id = Ipse.Session.info(pid).id
    assert Ipse.Session.info(pid).sandbox.requested == :native
    DynamicSupervisor.terminate_child(Ipse.Sessions, pid)

    config = %{provider: :demo, model: "test", sandbox: :off, approval: :ask}

    assert {:error, :resume_configuration_mismatch} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session,
                config: config, cwd: ctx.root, state_dir: ctx.dir, id: id, subscriber: self()}
             )

    resumed = session(ctx, %{sandbox: :native, scenario: :identity}, id)
    assert Ipse.Session.info(resumed).sandbox.requested == :native
    :ok = Ipse.Session.prompt(resumed, "show policy")
    assert_receive {:model_input, [system | _]}, 2000
    assert system["content"] =~ "native workspace sandbox"

    assert Enum.all?(
             Ipse.Session.info(resumed).sandbox.visibility,
             &String.contains?(system["content"], &1)
           )

    assert_receive {:ipse, ^resumed, {:done, :ok}}, 2000
  end

  test "resume labels saved reported identity separately from the active runtime", ctx do
    config = %{scenario: :identity, reported: "saved-snapshot"}
    pid = session(ctx, config)
    Ipse.Session.prompt(pid, "identity")
    assert_receive {:model_input, _}, 2000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    id = Ipse.Session.info(pid).id
    DynamicSupervisor.terminate_child(Ipse.Sessions, pid)
    resumed = session(ctx, %{scenario: :identity, reported: "new-snapshot"}, id)
    info = Ipse.Session.info(resumed).runtime
    assert info.version == Application.spec(:ipse, :vsn) |> to_string()
    assert info.reported_model == nil
    assert info.historical_reported_model == "saved-snapshot"
    Ipse.Session.prompt(resumed, "identity again")
    assert_receive {:model_input, [system | _]}, 2000
    assert system["content"] =~ "Last response model (current run): unavailable"
    assert system["content"] =~ "Saved session's last response model: saved-snapshot"
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 2000
    assert Ipse.Session.info(resumed).runtime.reported_model == "new-snapshot"
  end
end
