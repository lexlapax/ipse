defmodule Ipse.Session.PermissionsTest do
  use ExUnit.Case, async: false
  alias Ipse.Session
  alias Ipse.Session.Permissions

  defmodule Fixture do
    def complete(_config, messages, _tools, _emit) do
      if List.last(messages)["role"] == "tool" do
        {:ok, %{"role" => "assistant", "content" => "Done"}, %{}}
      else
        calls = List.last(messages)["content"] |> Jason.decode!()
        {:ok, %{"role" => "assistant", "content" => "", "tool_calls" => calls}, %{}}
      end
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-permissions-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, dir: Path.join(root, "state")}
  end

  defp start(ctx, extra \\ %{}, id \\ nil) do
    config =
      Map.merge(
        %{
          provider: :demo,
          model: "fixture",
          provider_module: Fixture,
          home: Path.join(ctx.root, "home")
        },
        extra
      )

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: ctx.root, state_dir: ctx.dir, id: id, subscriber: self()}
      )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    pid
  end

  defp call(name, args, id \\ "call") do
    %{
      "id" => id,
      "type" => "function",
      "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
    }
  end

  defp prompt(pid, calls), do: Session.prompt(pid, Jason.encode!(calls))

  test "fixed seven-effect task reduces seven prompts to two explicit session grants", ctx do
    calls =
      for n <- 1..4, do: call("write", %{"path" => "file#{n}", "content" => "hello"}, "w#{n}")

    calls = calls ++ for n <- 1..3, do: call("shell", %{"command" => "printf fixture"}, "s#{n}")

    for reuse <- [false, true] do
      pid = start(ctx)
      :ok = prompt(pid, calls)
      count = approve_until_done(pid, reuse, 0)
      assert count == if(reuse, do: 2, else: 7)
      assert File.read!(Path.join(ctx.root, "file4")) == "hello"
      {:ok, events} = Ipse.Journal.load(ctx.dir, Session.info(pid).id)
      starts = Enum.filter(events, &(&1["type"] == "tool_started"))
      assert length(starts) == 7

      if reuse do
        assert Enum.count(starts, &(&1["approval_source"] == "workspace_edits")) == 4
        assert Enum.count(starts, &(&1["approval_source"] == "exact_command")) == 3
      end

      :ok = Session.close_confirmed(pid)
    end
  end

  defp approve_until_done(pid, reuse, count) do
    receive do
      {:ipse, ^pid, {:approval, ref, name, _}} ->
        choice =
          if reuse,
            do: if(name == "shell", do: :session_command, else: :session_edits),
            else: true

        assert :ok = Session.approve(pid, ref, choice)
        approve_until_done(pid, reuse, count + 1)

      {:ipse, ^pid, {:done, :ok}} ->
        count

      _ ->
        approve_until_done(pid, reuse, count)
    after
      5_000 -> flunk("task did not complete")
    end
  end

  test "grants revoke, expire on resume, and cannot revive a cancelled proposal", ctx do
    pid = start(ctx)
    calls = [call("write", %{"path" => "file", "content" => "hello"})]
    :ok = prompt(pid, calls)
    assert_receive {:ipse, ^pid, {:approval, ref, "write", _}}, 2000
    assert :ok = Session.approve(pid, ref, :session_edits)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    assert Session.permissions(pid)["workspace_edits"]
    :ok = prompt(pid, calls)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    refute_received {:ipse, ^pid, {:approval, _, _, _}}
    :ok = Session.clear_permissions(pid)
    refute Session.permissions(pid)["workspace_edits"]
    :ok = prompt(pid, calls)
    assert_receive {:ipse, ^pid, {:approval, pending, "write", _}}, 2000
    :ok = Session.cancel(pid)
    assert {:error, _} = Session.approve(pid, pending, :session_edits)
    refute Session.permissions(pid)["workspace_edits"]
    assert_receive {:ipse, ^pid, {:done, _}}, 2000
    :ok = prompt(pid, calls)
    assert_receive {:ipse, ^pid, {:approval, fresh, "write", _}}, 2000
    :ok = Session.approve(pid, fresh, :session_edits)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    id = Session.info(pid).id
    :ok = Session.close_confirmed(pid)
    resumed = start(ctx, %{}, id)
    refute Session.permissions(resumed)["workspace_edits"]
    assert Session.info(resumed).phase == :idle
    :ok = prompt(resumed, calls)
    assert_receive {:ipse, ^resumed, {:approval, denied, "write", _}}, 2000
    :ok = Session.approve(resumed, denied, false)
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 2000
  end

  test "accept edits leaves shell approvals and all native path checks active", ctx do
    outside = Path.join(System.tmp_dir!(), "ipse-outside-#{System.unique_integer([:positive])}")
    File.write!(outside, "private")
    on_exit(fn -> File.rm(outside) end)
    File.mkdir_p!(Path.join(ctx.root, ".git"))
    File.ln_s!(outside, Path.join(ctx.root, "link"))
    File.ln!(outside, Path.join(ctx.root, "hardlink"))
    pid = start(ctx, %{accept_edits: true})

    calls =
      for {path, i} <- Enum.with_index([outside, ".git/config", "link", "hardlink"]),
          do: call("write", %{"path" => path, "content" => "changed"}, "w#{i}")

    :ok = prompt(pid, calls)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    refute_received {:ipse, ^pid, {:approval, _, _, _}}
    assert File.read!(outside) == "private"
    refute File.exists?(Path.join(ctx.root, ".git/config"))

    :ok =
      prompt(pid, [
        call("write", %{"path" => "editable", "content" => "before"}, "write"),
        call("edit", %{"path" => "editable", "old" => "before", "new" => "after"}, "edit")
      ])

    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    assert File.read!(Path.join(ctx.root, "editable")) == "after"
    refute_received {:ipse, ^pid, {:approval, _, _, _}}
    :ok = prompt(pid, [call("shell", %{"command" => "printf shell"})])
    assert_receive {:ipse, ^pid, {:approval, ref, "shell", _}}, 2000
    assert {:error, :grant_unavailable} = Session.approve(pid, ref, :session_edits)
    assert Session.info(pid).phase == :approval
    :ok = Session.approve(pid, ref, false)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
  end

  test "headless deny wins over accept edits", ctx do
    pid = start(ctx, %{approval: :deny, accept_edits: true})
    :ok = prompt(pid, [call("write", %{"path" => "denied", "content" => "no"})])
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    refute File.exists?(Path.join(ctx.root, "denied"))
    refute Session.permissions(pid)["workspace_edits"]
  end

  test "cancel retains existing edit and command grants for later work", ctx do
    pid = start(ctx)
    write = call("write", %{"path" => "kept", "content" => "yes"}, "w")
    shell = call("shell", %{"command" => "printf retained"}, "s")
    :ok = prompt(pid, [write, shell])
    assert approve_until_done(pid, true, 0) == 2
    grants = Session.permissions(pid)
    :ok = prompt(pid, [call("shell", %{"command" => "printf different"})])
    assert_receive {:ipse, ^pid, {:approval, _, "shell", _}}, 2000
    :ok = Session.cancel(pid)
    assert_receive {:ipse, ^pid, {:done, _}}, 2000
    assert Session.permissions(pid) == grants
    :ok = prompt(pid, [write, shell])
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    refute_received {:ipse, ^pid, {:approval, _, _, _}}
    assert File.read!(Path.join(ctx.root, "kept")) == "yes"
  end

  test "shell reuse matches entire arguments, cwd and sandbox, with bounded grants" do
    config = %{approval: :ask}
    s = %{config: config, cwd: "/workspace", permissions: Permissions.new(config)}
    args = %{"command" => "printf safe"}
    {:ok, grants, _} = Permissions.grant(s, "shell", args, :session_command)
    s = %{s | permissions: grants}
    assert Permissions.source(s, "shell", args) == "exact_command"

    for changed <- [
          %{"command" => "printf safe; touch elsewhere"},
          Map.put(args, "timeout_ms", 1000),
          %{"command" => "printf $(touch elsewhere)"}
        ] do
      refute Permissions.source(s, "shell", changed)
    end

    refute Permissions.source(%{s | cwd: "/other"}, "shell", args)
    refute Permissions.source(%{s | config: %{approval: :ask, sandbox: :native}}, "shell", args)
    refute Permissions.source(s, "extension:shell", args)
    refute Permissions.source(s, "child 1/shell", args)
    child = %{s | config: %{approval: :ask, delegation_origin: %{}}}
    refute Permissions.source(child, "shell", args)
    assert {:error, _} = Permissions.grant(child, "write", %{}, :session_edits)
    refute Permissions.new(%{approval: :ask, accept_edits: true, delegation_origin: %{}}).edits

    assert {:error, _} =
             Permissions.grant(
               s,
               "shell",
               %{"command" => String.duplicate("a", 16_384)},
               :session_command
             )

    full = %{
      s
      | permissions: %{edits: false, commands: List.duplicate({"/workspace", :off, args}, 32)}
    }

    assert {:error, _} = Permissions.grant(full, "shell", args, :session_command)
  end
end
