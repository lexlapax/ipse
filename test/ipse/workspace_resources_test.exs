defmodule Ipse.SkillResourceSessionTest do
  use ExUnit.Case, async: false

  defmodule Provider do
    def complete(config, messages, _tools, _emit) do
      send(config.test_pid, {:resource_messages, messages})

      if Enum.any?(messages, &(&1["role"] == "tool")) do
        {:ok, %{"role" => "assistant", "content" => "Reviewed saved resource"}, %{}}
      else
        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "resource",
               "type" => "function",
               "function" => %{
                 "name" => "load_skill_resource",
                 "arguments" => Jason.encode!(%{"name" => "fixture", "path" => "guide.txt"})
               }
             }
           ]
         }, %{}}
      end
    end
  end

  test "isolated session homes do not implicitly enable shared discovery" do
    root =
      Path.join(System.tmp_dir!(), "ipse-shared-session-#{System.unique_integer([:positive])}")

    cwd = Path.join(root, "workspace")
    operator = Path.join(root, "operator")
    shared = Path.join(operator, ".agents/skills/private-fixture")
    File.mkdir_p!(cwd)
    File.mkdir_p!(shared)

    File.write!(
      Path.join(shared, "SKILL.md"),
      "---\nname: private-fixture\ndescription: synthetic\n---\nInert"
    )

    previous = System.get_env("HOME")
    System.put_env("HOME", operator)

    on_exit(fn ->
      System.put_env("HOME", previous)
      File.rm_rf!(root)
    end)

    for {label, extra} <- [
          {:explicit_home, %{home: Path.join(root, "isolated")}},
          {:environment_home, %{}},
          {:injected, %{home: Path.join(root, "isolated"), operator_home: operator}},
          {:disabled,
           %{home: Path.join(root, "isolated"), operator_home: operator, shared_root: nil}}
        ] do
      config = Map.merge(%{provider: :demo, model: "scripted", approval: :deny}, extra)

      {:ok, pid} =
        DynamicSupervisor.start_child(
          Ipse.Sessions,
          {Ipse.Session,
           cwd: cwd, state_dir: Path.join(root, "state"), config: config, subscriber: self()}
        )

      skills = :sys.get_state(pid).skills
      assert Enum.any?(skills, &(&1["name"] == "private-fixture")) == (label == :injected)
      DynamicSupervisor.terminate_child(Ipse.Sessions, pid)
    end
  end

  for source <- [:user, :shared] do
    @source source
    test "#{source} outside-workspace resources are journaled and resume retains original content without reloading" do
      root =
        Path.join(
          System.tmp_dir!(),
          "ipse-resource-session-#{System.unique_integer([:positive])}"
        )

      cwd = Path.join(root, "workspace")
      home = Path.join(root, "home")
      operator_home = Path.join(root, "operator")

      skill =
        if @source == :user,
          do: Path.join(home, "skills/fixture"),
          else: Path.join(operator_home, ".agents/skills/fixture")

      File.mkdir_p!(cwd)
      File.mkdir_p!(skill)

      File.write!(
        Path.join(skill, "SKILL.md"),
        "---\nname: fixture\ndescription: Fixture\n---\nRead guide.txt"
      )

      resource = Path.join(skill, "guide.txt")
      File.write!(resource, "Original supporting resource.")
      on_exit(fn -> File.rm_rf!(root) end)
      state = Path.join(root, "state")

      opts = [
        cwd: cwd,
        state_dir: state,
        subscriber: self(),
        config: %{
          provider: :demo,
          model: "fixture",
          provider_module: Provider,
          test_pid: self(),
          home: home,
          operator_home: operator_home,
          approval: :deny
        }
      ]

      {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
      :ok = Ipse.Session.prompt(pid, "Review using the supporting resource.")
      assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
      id = Ipse.Session.info(pid).id
      {:ok, events} = Ipse.Journal.load(state, id)
      result = Enum.find(events, &(get_in(&1, ["message", "role"]) == "tool"))["message"]
      assert result["content"] =~ "Original supporting resource."
      assert result["content"] =~ "SHA-256:"

      assert result["ipse_tool_outcome"] == %{
               "status" => "result_recorded",
               "approval" => "not_required"
             }

      :ok = Ipse.Session.close(pid)
      {:ok, closed_events} = Ipse.Journal.load(state, id)
      assert Enum.take(closed_events, length(events)) == events

      assert [
               %{
                 "type" => "lifecycle_epoch_closed",
                 "session_id" => ^id,
                 "closure" => "close",
                 "cleanup_confirmed" => true
               }
             ] = Enum.drop(closed_events, length(events))

      File.write!(resource, "Changed resource must not replace history.")

      {:ok, resumed} =
        DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, Keyword.put(opts, :id, id)})

      on_exit(fn -> if Process.alive?(resumed), do: Ipse.Session.close(resumed) end)
      assert {:ok, ^closed_events} = Ipse.Journal.load(state, id)
      :ok = Ipse.Session.prompt(resumed, "Continue from saved evidence.")
      assert_receive {:ipse, ^resumed, {:done, :ok}}, 3000
      {:ok, final_events} = Ipse.Journal.load(state, id)
      assert Enum.count(final_events, &(&1["type"] == "tool_started")) == 1
      assert Enum.any?(final_events, &(&1["message"] == result))
    end
  end
end
