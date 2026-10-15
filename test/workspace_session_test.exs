defmodule Ipse.WorkspaceSessionTest do
  use ExUnit.Case, async: false

  defmodule Fixture do
    def complete(config, messages, _tools, _emit) do
      send(config.test_pid, {:model_input, messages})

      case config[:mode] do
        :scoped_write -> scoped_write(config, messages)
        _ -> {:ok, %{"role" => "assistant", "content" => "ok"}, %{}}
      end
    end

    defp scoped_write(config, _messages) do
      stage = Agent.get(config.agent, & &1)
      Agent.update(config.agent, &(&1 + 1))

      case stage do
        0 ->
          {:ok, write_calls([{"first", "premature"}, {"second", "also premature"}]), %{}}

        1 ->
          call = write_call("scoped-write", "nested/result.txt", "after review")
          {:ok, write_response([call]), %{}}

        _ ->
          {:ok, %{"role" => "assistant", "content" => "written"}, %{}}
      end
    end

    defp write_calls(items) do
      calls = Enum.map(items, fn {id, content} -> write_call(id, "nested/#{id}.txt", content) end)
      write_response(calls)
    end

    defp write_response(calls),
      do: %{"role" => "assistant", "content" => "", "tool_calls" => calls}

    defp write_call(id, path, content) do
      %{
        "id" => id,
        "type" => "function",
        "function" => %{
          "name" => "write",
          "arguments" => Jason.encode!(%{"path" => path, "content" => content})
        }
      }
    end
  end

  setup do
    root =
      Path.join(System.tmp_dir!(), "ipse-workspace-session-#{System.unique_integer([:positive])}")

    cwd = Path.join(root, "workspace")
    home = Path.join(root, "home")
    File.mkdir_p!(cwd)
    File.mkdir_p!(home)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, cwd: cwd, home: home, dir: Path.join(root, "state")}
  end

  defp config(ctx, extra \\ %{}) do
    Map.merge(
      %{
        provider: :demo,
        model: "context-test",
        provider_module: Fixture,
        test_pid: self(),
        approval: :ask,
        home: ctx.home
      },
      extra
    )
  end

  defp start(ctx, extra \\ %{}, id \\ nil) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Ipse.Session,
         config: config(ctx, extra), cwd: ctx.cwd, state_dir: ctx.dir, id: id, subscriber: self()}
      )

    on_exit(fn ->
      if Process.alive?(pid), do: DynamicSupervisor.terminate_child(Ipse.Sessions, pid)
    end)

    pid
  end

  test "startup snapshots instructions, resume uses saved content, and explicit refresh adopts changes",
       ctx do
    agents = Path.join(ctx.cwd, "AGENTS.md")
    global = Path.join(ctx.home, "AGENTS.md")
    File.write!(agents, "workspace-v1")
    File.write!(global, "global-v1")

    pid = start(ctx)
    info = Ipse.Session.info(pid)
    assert info.context["cwd"] == ctx.cwd
    assert Enum.any?(info.context["sources"], &(&1["path"] == agents))
    assert Enum.any?(info.context["sources"], &(&1["path"] == global))
    assert Enum.all?(info.context["sources"], &(not Map.has_key?(&1, "content")))
    id = info.id
    DynamicSupervisor.terminate_child(Ipse.Sessions, pid)

    File.write!(agents, "workspace-v2")
    File.write!(global, "global-v2")
    resumed = start(ctx, %{}, id)

    assert Ipse.Session.info(resumed).context["diagnostics"]
           |> Enum.any?(&String.contains?(&1, "changed:"))

    :ok = Ipse.Session.prompt(resumed, "show saved context")
    assert_receive {:model_input, [system | _]}, 2_000
    assert system["content"] =~ "workspace-v1"
    assert system["content"] =~ "global-v1"
    refute system["content"] =~ "workspace-v2"
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 2_000

    assert :ok = Ipse.Session.refresh_context(resumed)
    assert_receive {:ipse, ^resumed, {:context_refreshed, manifest}}, 2_000
    assert Enum.any?(manifest["sources"], &(&1["sha256"] != ""))
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 2_000
    :ok = Ipse.Session.prompt(resumed, "show refreshed context")
    assert_receive {:model_input, [system | _]}, 2_000
    assert system["content"] =~ "workspace-v2"
    assert system["content"] =~ "global-v2"
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 2_000
  end

  test "new nested guidance is journaled before pending file actions are replanned", ctx do
    nested = Path.join(ctx.cwd, "nested")
    File.mkdir_p!(nested)
    File.write!(Path.join(nested, "AGENTS.md"), "nested-scope-v1")
    {:ok, agent} = Agent.start_link(fn -> 0 end)
    pid = start(ctx, %{mode: :scoped_write, agent: agent})

    :ok = Ipse.Session.prompt(pid, "write the nested file")
    assert_receive {:model_input, _first_messages}, 2_000
    assert_receive {:model_input, [system | replanned_messages]}, 2_000
    assert system["content"] =~ "nested-scope-v1"

    assert Enum.count(
             replanned_messages,
             &(&1["role"] == "tool" and &1["ipse_tool_outcome"]["status"] == "not_started")
           ) == 2

    assert_receive {:ipse, ^pid,
                    {:approval, ref, "write",
                     %{"path" => "nested/result.txt", "content" => "after review"}}},
                   2_000

    refute File.exists?(Path.join(nested, "result.txt"))
    refute File.exists?(Path.join(nested, "first.txt"))
    refute File.exists?(Path.join(nested, "second.txt"))

    {:ok, events} = Ipse.Journal.load(ctx.dir, Ipse.Session.info(pid).id)
    assert Enum.count(events, &(&1["type"] == "workspace_context_snapshot")) == 2
    refute Enum.any?(events, &(&1["type"] == "tool_started"))

    assert Enum.count(events, fn event ->
             get_in(event, ["message", "ipse_tool_outcome", "status"]) == "not_started"
           end) == 2

    :ok = Ipse.Session.approve(pid, ref, true)
    assert_receive {:model_input, [system | _]}, 2_000
    assert system["content"] =~ "nested-scope-v1"
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2_000
    assert File.read!(Path.join(nested, "result.txt")) == "after review"
  end

  test "canonical cwd metadata remains resumable through a directory alias", ctx do
    alias_path = ctx.cwd <> "-alias"
    File.ln_s!(ctx.cwd, alias_path)

    pid = start(%{ctx | cwd: alias_path})
    assert Ipse.Session.info(pid).cwd == ctx.cwd
    id = Ipse.Session.info(pid).id
    DynamicSupervisor.terminate_child(Ipse.Sessions, pid)
    resumed = start(ctx, %{}, id)
    assert Ipse.Session.info(resumed).cwd == ctx.cwd
  end

  test "resume rejects an invalid latest saved context snapshot", ctx do
    pid = start(ctx)
    id = Ipse.Session.info(pid).id
    DynamicSupervisor.terminate_child(Ipse.Sessions, pid)

    assert :ok =
             Ipse.Journal.append(ctx.dir, id, %{
               "type" => "workspace_context_snapshot",
               "version" => 1,
               "snapshot" => %{"version" => 1, "cwd" => "/tmp/../../etc", "sources" => []}
             })

    assert {:error, _} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session,
                config: config(ctx), cwd: ctx.cwd, state_dir: ctx.dir, id: id, subscriber: self()}
             )
  end
end
