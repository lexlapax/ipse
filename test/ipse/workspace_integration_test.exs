defmodule Ipse.WorkspaceSessionTest do
  use ExUnit.Case, async: false

  defmodule Fixture do
    def complete(config, messages, _tools, _emit) do
      send(config.test_pid, {:model_input, messages})

      case config[:mode] do
        :scoped_write -> scoped_write(config, messages)
        :calls -> fixture_calls(config)
        _ -> {:ok, %{"role" => "assistant", "content" => "ok"}, %{}}
      end
    end

    defp fixture_calls(config) do
      stage = Agent.get_and_update(config.agent, &{&1, &1 + 1})

      if stage == 0,
        do: {:ok, write_response(config.fixture_calls), %{}},
        else: {:ok, %{"role" => "assistant", "content" => "reconsidered"}, %{}}
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

  test "resume retains the skill catalog, detects new shadows and requires refresh for changed bodies",
       ctx do
    user = Path.join(ctx.home, "skills/review/SKILL.md")
    project = Path.join(ctx.cwd, ".agents/skills/review/SKILL.md")
    File.mkdir_p!(Path.dirname(user))

    File.write!(
      user,
      "---\nname: review\ndescription: saved-catalog-description\n---\nsaved-body"
    )

    session = start(ctx)
    id = Ipse.Session.info(session).id
    assert :ok = Ipse.Session.close(session)
    bytes = File.read!(Path.join(ctx.dir, id <> ".jsonl"))
    File.mkdir_p!(Path.dirname(project))

    File.write!(
      project,
      "---\nname: review\ndescription: new-shadow-description\n---\nnew-shadow-body"
    )

    resumed = start(ctx, %{}, id)
    assert File.read!(Path.join(ctx.dir, id <> ".jsonl")) == bytes

    assert Enum.any?(
             Ipse.Session.info(resumed).context["diagnostics"],
             &String.contains?(&1, "Skill catalog changed")
           )

    assert :ok = Ipse.Session.prompt(resumed, "$review")
    assert_receive {:model_input, [system, reference, user_message]}, 2_000
    assert reference["role"] == "user"
    assert reference["content"] =~ "saved-catalog-description"
    refute system["content"] =~ "saved-catalog-description"
    refute system["content"] =~ "new-shadow-description"
    assert user_message["content"] =~ "saved-body"
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 2_000
    File.write!(user, "---\nname: review\ndescription: changed-selected\n---\nchanged-body")
    assert {:error, :skill_catalog_changed} = Ipse.Session.prompt(resumed, "$review")
    assert_receive {:ipse, ^resumed, {:done, :error}}, 2_000
    refute_receive {:model_input, _}, 50
    assert :ok = Ipse.Session.refresh_context(resumed)
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 2_000
    assert :ok = Ipse.Session.prompt(resumed, "$review")
    assert_receive {:model_input, messages}, 2_000
    assert Enum.at(messages, 1)["content"] =~ "new-shadow-description"
    refute hd(messages)["content"] =~ "new-shadow-description"
    assert List.last(messages)["content"] =~ "new-shadow-body"
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 2_000
    assert :ok = Ipse.Session.close(resumed)
    again = start(ctx, %{}, id)
    assert Ipse.Session.info(again).phase == :idle
    assert :ok = Ipse.Session.close(again)
  end

  test "corrupt skill metadata refuses recovery before tail repair", ctx do
    session = start(ctx)
    id = Ipse.Session.info(session).id
    assert :ok = Ipse.Session.close(session)
    path = Path.join(ctx.dir, id <> ".jsonl")

    checkpoint =
      Ipse.Workspace.skill_checkpoint([]) |> Map.put("sha256", String.duplicate("0", 64))

    bytes = File.read!(path) <> Jason.encode!(checkpoint) <> "\npartial-tail"
    File.write!(path, bytes)

    assert {:error, :invalid_skill_catalog_snapshot} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session,
                config: config(ctx), cwd: ctx.cwd, state_dir: ctx.dir, id: id, subscriber: self()}
             )

    assert File.read!(path) == bytes
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
    assert_receive {:model_input, [system, reference | _]}, 2_000
    assert reference["content"] =~ "workspace-v1"
    assert reference["content"] =~ "global-v1"
    refute reference["content"] =~ "workspace-v2"
    refute system["content"] =~ "workspace-v1"
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 2_000

    assert :ok = Ipse.Session.refresh_context(resumed)
    assert_receive {:ipse, ^resumed, {:context_refreshed, manifest}}, 2_000
    assert Enum.any?(manifest["sources"], &(&1["sha256"] != ""))
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 2_000
    :ok = Ipse.Session.prompt(resumed, "show refreshed context")
    assert_receive {:model_input, [system, reference | _]}, 2_000
    assert reference["content"] =~ "workspace-v2"
    assert reference["content"] =~ "global-v2"
    refute system["content"] =~ "workspace-v2"
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
    assert_receive {:model_input, [system, admitted | replanned_messages]}, 2_000
    reference = List.last(replanned_messages)
    assert Ipse.Session.Reference.reference?(reference)
    refute admitted["content"] =~ "nested-scope-v1"
    assert reference["content"] =~ "nested-scope-v1"
    refute system["content"] =~ "nested-scope-v1"

    assert Enum.count(
             replanned_messages,
             &(&1["role"] == "tool" and &1["ipse_tool_outcome"]["status"] == "not_started")
           ) == 2

    assert [first, second] = tool_messages(replanned_messages)
    assert first["tool_call_id"] == "first"

    assert first["content"] ==
             "Not executed: new scoped workspace context was loaded. Review it before retrying this action."

    assert second["tool_call_id"] == "second"
    assert second["content"] == "Not executed: work stopped before this call started."

    for message <- [first, second] do
      assert message["ipse_tool_outcome"] == %{
               "status" => "not_started",
               "approval" => "not_decided"
             }
    end

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

    snapshot_index =
      Enum.find_index(events, fn event ->
        event["type"] == "workspace_context_snapshot" and
          Enum.any?(event["snapshot"]["sources"], &(&1["content"] == "nested-scope-v1"))
      end)

    refusal_index = Enum.find_index(events, &(get_in(&1, ["message", "tool_call_id"]) == "first"))
    assert is_integer(snapshot_index)
    assert snapshot_index < refusal_index
    assert get_in(Enum.at(events, refusal_index + 1), ["message"]) == second
    settled_prefix = Enum.take(events, refusal_index + 2)
    assert {:ok, restored_before_approval} = Ipse.Session.restore_context(settled_prefix)
    assert tool_messages(restored_before_approval) == [first, second]

    :ok = Ipse.Session.approve(pid, ref, true)
    assert_receive {:model_input, [_system, _admitted | messages]}, 2_000
    reference = Enum.find(Enum.reverse(messages), &Ipse.Session.Reference.reference?/1)
    assert Ipse.Session.Reference.reference?(reference)
    assert reference["content"] =~ "nested-scope-v1"
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2_000
    assert File.read!(Path.join(nested, "result.txt")) == "after review"
    {:ok, completed_events} = Ipse.Journal.load(ctx.dir, Ipse.Session.info(pid).id)

    assert [^first, ^second, written] =
             completed_events
             |> Enum.map(& &1["message"])
             |> Enum.reject(&is_nil/1)
             |> tool_messages()

    assert written["tool_call_id"] == "scoped-write"

    assert written["ipse_tool_outcome"] == %{
             "status" => "result_recorded",
             "approval" => "approved"
           }

    File.write!(Path.join(nested, "result.txt"), "operator edit")

    resumed =
      assert_idle_restoration(ctx, pid, %{mode: :scoped_write, agent: agent}, [
        first,
        second,
        written
      ])

    assert File.read!(Path.join(nested, "result.txt")) == "operator edit"
    refute File.exists?(Path.join(nested, "first.txt"))
    refute File.exists?(Path.join(nested, "second.txt"))
    assert :ok = Ipse.Session.close(resumed)
  end

  defp tool_call(id, name, args) do
    %{
      "id" => id,
      "type" => "function",
      "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
    }
  end

  defp tool_messages(messages), do: Enum.filter(messages, &(&1["role"] == "tool"))

  defp assert_idle_restoration(ctx, pid, extra, expected_tools) do
    id = Ipse.Session.info(pid).id
    assert :ok = Ipse.Session.close(pid)
    path = Path.join(ctx.dir, id <> ".jsonl")
    bytes = File.read!(path)
    assert {:ok, events} = Ipse.Journal.load(ctx.dir, id)
    assert {:ok, restored} = Ipse.Session.restore_context(events)
    assert tool_messages(restored) == expected_tools

    resumed = start(ctx, extra, id)
    assert Ipse.Session.info(resumed).phase == :idle
    assert File.read!(path) == bytes
    refute_receive {:model_input, _}, 50
    refute_receive {:ipse, ^resumed, {:tool, _, _}}, 50
    refute_receive {:ipse, ^resumed, {:approval, _, _, _}}, 50
    resumed
  end

  test "preflight refusal retains its reason only on the affected call and restores without replay",
       ctx do
    File.write!(Path.join(ctx.cwd, "known.txt"), "queued read must not run")

    for {target, reason} <- [
          {"missing/result.txt", "target does not exist"},
          {nil, "invalid nested context request"},
          {"/absolute.txt", "target must be workspace-relative"},
          {"../outside.txt", "target is outside the workspace"}
        ] do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      extra = %{
        mode: :calls,
        agent: agent,
        fixture_calls: [
          tool_call("affected", "read", %{"path" => target}),
          tool_call("queued", "read", %{"path" => "known.txt"})
        ]
      }

      pid = start(ctx, extra)
      assert :ok = Ipse.Session.prompt(pid, "inspect proposed paths")
      assert_receive {:model_input, _}, 2_000
      assert_receive {:model_input, messages}, 2_000
      assert_receive {:ipse, ^pid, {:done, :ok}}, 2_000
      assert [affected, queued] = tool_messages(messages)
      assert affected["tool_call_id"] == "affected"
      assert affected["content"] =~ "scoped context could not be loaded"
      assert affected["content"] =~ reason
      assert affected["content"] =~ "Check this call's target path"
      assert queued["tool_call_id"] == "queued"
      assert queued["content"] == "Not executed: work stopped before this call started."

      for message <- [affected, queued] do
        assert message["ipse_tool_outcome"] == %{
                 "status" => "not_started",
                 "approval" => "not_decided"
               }
      end

      assert {:ok, events} = Ipse.Journal.load(ctx.dir, Ipse.Session.info(pid).id)
      refute Enum.any?(events, &(&1["type"] == "tool_started"))
      refute_receive {:ipse, ^pid, {:tool, _, _}}, 50
      refute_receive {:ipse, ^pid, {:approval, _, _, _}}, 50
      resumed = assert_idle_restoration(ctx, pid, extra, [affected, queued])
      assert :ok = Ipse.Session.prompt(resumed, "reconsider without repeating the reads")
      assert_receive {:model_input, restored_messages}, 2_000
      assert tool_messages(restored_messages) == [affected, queued]
      assert_receive {:ipse, ^resumed, {:done, :ok}}, 2_000
      assert :ok = Ipse.Session.close(resumed)
    end
  end

  test "cancelling a started effect leaves only that call unknown and never replays queued calls",
       ctx do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    extra = %{
      mode: :calls,
      agent: agent,
      fixture_calls: [
        tool_call("started", "shell", %{
          "command" => "printf effected > effect.txt; printf ready; sleep 30"
        }),
        tool_call("queued", "write", %{"path" => "queued.txt", "content" => "must not run"})
      ]
    }

    pid = start(ctx, extra)
    assert :ok = Ipse.Session.prompt(pid, "start a cancellable synthetic effect")
    assert_receive {:model_input, _}, 2_000
    assert_receive {:ipse, ^pid, {:approval, ref, "shell", _}}, 2_000
    assert :ok = Ipse.Session.approve(pid, ref, true)
    assert_receive {:ipse, ^pid, {:tool_output, "ready"}}, 5_000
    assert File.read!(Path.join(ctx.cwd, "effect.txt")) == "effected"
    assert :ok = Ipse.Session.cancel(pid)
    assert_receive {:ipse, ^pid, {:done, :cancelled}}, 5_000
    assert {:ok, events} = Ipse.Journal.load(ctx.dir, Ipse.Session.info(pid).id)

    assert [started, queued] =
             events |> Enum.map(& &1["message"]) |> Enum.reject(&is_nil/1) |> tool_messages()

    assert started["tool_call_id"] == "started"
    assert started["ipse_tool_outcome"] == %{"status" => "unknown", "approval" => "approved"}
    assert started["content"] =~ "effects may have occurred"
    assert queued["tool_call_id"] == "queued"

    assert queued["ipse_tool_outcome"] == %{
             "status" => "not_started",
             "approval" => "not_decided"
           }

    assert queued["content"] == "Not executed: work stopped before this call started."

    assert Enum.map(Enum.filter(events, &(&1["type"] == "tool_started")), & &1["call_id"]) == [
             "started"
           ]

    refute File.exists?(Path.join(ctx.cwd, "queued.txt"))
    File.write!(Path.join(ctx.cwd, "effect.txt"), "operator edit")
    resumed = assert_idle_restoration(ctx, pid, extra, [started, queued])
    assert File.read!(Path.join(ctx.cwd, "effect.txt")) == "operator edit"
    refute File.exists?(Path.join(ctx.cwd, "queued.txt"))
    assert :ok = Ipse.Session.close(resumed)
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
