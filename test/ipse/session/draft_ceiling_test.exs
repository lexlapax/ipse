defmodule Ipse.Session.DraftCeilingTest do
  use ExUnit.Case, async: false

  alias Ipse.{Journal, Session, Usage}

  # A local scripted provider: no actual draft workflow or model service is used.
  defmodule Provider do
    def complete(config, messages, tools, _emit) do
      send(config.test_owner, {:fixture_tools, config.test_label, Jason.encode!(tools)})

      last = messages |> Enum.reject(&Ipse.Session.Reference.reference?/1) |> List.last()

      if last["role"] == "tool" do
        {:ok, %{"role" => "assistant", "content" => "fixture complete"}, %{}}
      else
        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => Jason.decode!(last["content"])
         }, %{}}
      end
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-draft-ceiling-" <> Usage.id())
    File.mkdir_p!(root)
    File.write!(Path.join(root, "input.txt"), "fixture readable content")
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, state: Path.join(root, "sessions")}
  end

  defp start(c, extra, id \\ nil) do
    label = make_ref()

    config =
      Map.merge(
        %{
          provider: :demo,
          model: "fixture",
          provider_module: Provider,
          home: Path.join(c.root, "home"),
          test_owner: self(),
          test_label: label,
          approval: :allow,
          approval_origin: :yes,
          headless: true
        },
        extra
      )

    opts = [config: config, cwd: c.root, state_dir: c.state, subscriber: self()]
    opts = if id, do: Keyword.put(opts, :id, id), else: opts
    {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})
    Process.put({__MODULE__, pid}, label)
    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    pid
  end

  defp call(id, name, args) do
    %{
      "id" => id,
      "type" => "function",
      "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
    }
  end

  defp prompt(pid, calls) do
    label = Process.get({__MODULE__, pid})
    assert :ok = Session.prompt(pid, Jason.encode!(calls))
    assert_receive {:fixture_tools, ^label, tools}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    assert_receive {:fixture_tools, ^label, ^tools}, 5_000
    tools
  end

  test "static draft ceiling preserves declarations, allows reads, and denies mutations despite yes",
       c do
    normal = start(c, %{})
    draft = start(c, %{execution_mode: :draft, accept_edits: true})
    read = call("r", "read", %{"path" => "input.txt"})
    normal_tools = prompt(normal, [read])

    tools =
      prompt(draft, [
        read,
        call("w", "write", %{"path" => "forbidden.txt", "content" => "forbidden"}),
        call("s", "shell", %{"command" => "touch forbidden-shell.txt"})
      ])

    assert tools == normal_tools
    refute File.exists?(Path.join(c.root, "forbidden.txt"))
    refute File.exists?(Path.join(c.root, "forbidden-shell.txt"))
    refute_received {:ipse, ^draft, {:approval, _, _, _}}

    {:ok, events} = Journal.load(c.state, Session.info(draft).id)

    messages =
      events
      |> Enum.filter(&(&1["type"] == "message" and get_in(&1, ["message", "role"]) == "tool"))
      |> Map.new(fn %{"message" => message} -> {message["tool_call_id"], message} end)

    assert messages["r"]["content"] =~ "fixture readable content"
    assert get_in(messages, ["w", "ipse_tool_outcome", "status"]) == "denied"
    assert get_in(messages, ["s", "ipse_tool_outcome", "status"]) == "denied"

    assert :ok = Session.close_confirmed(normal)
    assert :ok = Session.close_confirmed(draft)
  end

  test "resuming a statically draft-constrained Session cannot widen effects using yes", c do
    draft = start(c, %{execution_mode: :draft})
    id = Session.info(draft).id
    assert :ok = Session.close_confirmed(draft)
    resumed = start(c, %{}, id)

    _ =
      prompt(resumed, [
        call("resume-write", "write", %{"path" => "resumed.txt", "content" => "no"})
      ])

    refute File.exists?(Path.join(c.root, "resumed.txt"))
    refute_received {:ipse, ^resumed, {:approval, _, _, _}}
    {:ok, events} = Journal.load(c.state, id)

    assert Enum.any?(events, fn event ->
             get_in(event, ["message", "tool_call_id"]) == "resume-write" and
               get_in(event, ["message", "ipse_tool_outcome", "status"]) == "denied"
           end)

    assert :ok = Session.close_confirmed(resumed)
  end
end
