defmodule Ipse.ToolRecoveryTest do
  use ExUnit.Case, async: false
  alias Ipse.{Journal, Session, Runner, Tools}

  defmodule Model do
    def complete(config, messages, _tools, _emit) do
      if Enum.any?(messages, &(&1["role"] == "tool")) do
        {:ok, %{"role" => "assistant", "content" => "Done"}, %{}}
      else
        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "provider_data" => %{"fixture" => "original-native"},
           "tool_calls" => config.fixture_calls
         }, %{}}
      end
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-tool-recovery-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, dir: Path.join(root, "sessions")}
  end

  defp call(id, name, args),
    do: %{
      "id" => id,
      "type" => "function",
      "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
    }

  defp start(c, calls, approval \\ :allow, id \\ nil) do
    config = %{
      provider: :demo,
      model: "fixture",
      provider_module: Model,
      fixture_calls: calls,
      home: Path.join(c.root, "home"),
      approval: approval
    }

    assert {:ok, pid} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: config, cwd: c.root, state_dir: c.dir, subscriber: self(), id: id}
             )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    pid
  end

  test "helper loss after a real filesystem effect records unknown and idle resume never replays",
       c do
    shell =
      call("effect", "shell", %{"command" => ~s(printf effected > effect; kill -KILL "$PPID")})

    pid = start(c, [shell])
    :ok = Session.prompt(pid, "Synthetic interrupted shell")
    assert_receive {:ipse, ^pid, {:done, :error}}, 5_000
    assert File.read!(Path.join(c.root, "effect")) == "effected"
    id = Session.info(pid).id
    assert {:ok, events} = Journal.load(c.dir, id)

    assert Enum.any?(events, fn e ->
             get_in(e, ["message", "ipse_tool_outcome", "status"]) == "unknown"
           end)

    assert :ok = Session.close(pid)
    File.write!(Path.join(c.root, "effect"), "operator edit")
    path = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(path)
    resumed = start(c, [shell], :allow, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(path) == before
    assert File.read!(Path.join(c.root, "effect")) == "operator edit"
  end

  test "an output-consumer exception after shell dispatch is unknown; validation stays definite",
       c do
    assert {:unknown, _} =
             Runner.run("printf effected > effect; printf ready", c.root,
               emit: fn _ -> raise "Synthetic output consumer failure" end
             )

    assert File.read!(Path.join(c.root, "effect")) == "effected"
    assert {:error, _} = Runner.run("true", Path.join(c.root, "missing"))
    assert {:error, _} = Tools.execute("shell", %{"command" => nil}, %{cwd: c.root})
  end

  test "duplicate call IDs refuse the entire response before approval or any built-in effect",
       c do
    calls = [
      call("same", "write", %{"path" => "first", "content" => "one"}),
      call("same", "write", %{"path" => "second", "content" => "two"})
    ]

    for approval <- [:ask, :allow] do
      pid = start(c, calls, approval)
      :ok = Session.prompt(pid, "Synthetic duplicate IDs")
      assert_receive {:ipse, ^pid, {:done, :error}}, 2_000
      refute_receive {:ipse, ^pid, {:approval, _, _, _}}, 20
      refute File.exists?(Path.join(c.root, "first"))
      refute File.exists?(Path.join(c.root, "second"))
      assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
      refute Enum.any?(events, &(&1["type"] == "tool_started"))

      assert Enum.any?(events, fn e ->
               e["type"] == "provider_response_refused" and
                 get_in(e, ["message", "tool_calls"]) == calls and
                 get_in(e, ["message", "provider_data", "fixture"]) == "original-native"
             end)

      assert {:ok, context} = Session.restore_context(events)
      refute Enum.any?(context, &(&1["tool_calls"] == calls))
      id = Session.info(pid).id
      assert :ok = Session.close(pid)
      resumed = start(c, calls, approval, id)
      assert Session.info(resumed).phase == :idle
      assert :ok = Session.close(resumed)
    end
  end

  test "incomplete and contradictory helper frames stay unknown while explicit setup refusal is known",
       c do
    previous = System.get_env("IPSE_RUNNER_PATH")

    on_exit(fn ->
      if previous,
        do: System.put_env("IPSE_RUNNER_PATH", previous),
        else: System.delete_env("IPSE_RUNNER_PATH")
    end)

    helper = Path.join(c.root, "protocol-helper")
    System.put_env("IPSE_RUNNER_PATH", helper)
    frame = fn kind, text -> <<kind, byte_size(text)::unsigned-big-32, text::binary>> end

    for {bytes, expected} <- [
          {frame.(?O, "partial"), :unknown},
          {<<?X, 20::unsigned-big-32, "{">>, :unknown},
          {<<?O, 1_048_577::unsigned-big-32>>, :unknown},
          {frame.(?X, "{}"), :unknown},
          {frame.(?E, "setup refused"), :error},
          {frame.(?U, "post-dispatch failure"), :unknown},
          {frame.(?O, "partial") <> frame.(?E, "late failure"), :unknown},
          {frame.(?U, "uncertain") <> frame.(?E, "late refusal"), :unknown}
        ] do
      octal =
        for <<byte <- bytes>>,
          into: "",
          do: "\\" <> String.pad_leading(Integer.to_string(byte, 8), 3, "0")

      File.write!(helper, "#!/bin/sh\nprintf '#{octal}'\n")
      File.chmod!(helper, 0o700)
      assert {^expected, _} = Runner.run("not executed by fixture", c.root)
    end
  end

  test "missing, empty and non-string tool identities never reach approval", c do
    for id <- [nil, "", 17] do
      pid = start(c, [call(id, "write", %{"path" => "invalid", "content" => "x"})], :ask)
      :ok = Session.prompt(pid, "Synthetic invalid ID")
      assert_receive {:ipse, ^pid, {:done, :error}}, 2_000
      refute_receive {:ipse, ^pid, {:approval, _, _, _}}, 20
      refute File.exists?(Path.join(c.root, "invalid"))
      assert :ok = Session.close(pid)
    end
  end

  test "malformed call collections retain private evidence without poisoning resumable context",
       c do
    for calls <- [false, "malformed", %{}, [nil], [17]] do
      pid = start(c, calls, :ask)
      :ok = Session.prompt(pid, "Synthetic malformed collection")
      assert_receive {:ipse, ^pid, {:done, :error}}, 2_000
      assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
      assert {:ok, context} = Session.restore_context(events)
      refute Enum.any?(context, &Map.has_key?(&1, "tool_calls"))
      assert :ok = Session.close(pid)
    end
  end

  test "historical duplicate IDs consume each recorded result once and preserve native evidence" do
    calls = [call("same", "write", %{}), call("same", "shell", %{})]

    assistant = %{
      "role" => "assistant",
      "content" => "",
      "tool_calls" => calls,
      "provider_data" => %{"fixture" => "original-native"}
    }

    first = %{
      "role" => "tool",
      "tool_call_id" => "same",
      "content" => "First completed",
      "ipse_tool_outcome" => %{"status" => "result_recorded", "approval" => "approved"}
    }

    wrap = fn message -> %{"type" => "message", "message" => message} end
    header = %{"type" => "session", "metadata" => %{}}

    assert {:ok, [^assistant, ^first, missing]} =
             Session.restore_context([header | Enum.map([assistant, first], wrap)])

    assert missing["ipse_tool_outcome"] == %{
             "status" => "unknown",
             "approval" => "historical_unknown"
           }

    second = %{first | "content" => "Second completed"}

    assert {:ok, [^assistant, ^first, ^second]} =
             Session.restore_context([header | Enum.map([assistant, first, second], wrap)])
  end
end
