defmodule Ipse.Session.ResearchCeilingTest do
  use ExUnit.Case, async: false
  alias Ipse.{Journal, Session, Usage}

  defmodule Model do
    def complete(_config, messages, _tools, _emit) do
      if List.last(messages)["role"] == "tool" do
        {:ok, %{"role" => "assistant", "content" => "done"}, %{}}
      else
        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "source",
               "type" => "function",
               "function" => %{
                 "name" => "research_source",
                 "arguments" =>
                   Jason.encode!(%{
                     "tool_call_id" => "fixture",
                     "url" => "https://invalid.example",
                     "excerpt" => "fixture"
                   })
               }
             },
             %{
               "id" => "claim",
               "type" => "function",
               "function" => %{
                 "name" => "research_claim",
                 "arguments" =>
                   Jason.encode!(%{
                     "statement" => "synthetic open question",
                     "kind" => "open",
                     "source_ids" => []
                   })
               }
             },
             %{
               "id" => "ledger",
               "type" => "function",
               "function" => %{"name" => "research_ledger", "arguments" => "{}"}
             }
           ]
         }, %{}}
      end
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-research-ceiling-" <> Usage.id())
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, dir: Path.join(root, "state")}
  end

  defp run(c, extra) do
    config =
      Map.merge(
        %{
          provider: :demo,
          model: "fixture",
          provider_module: Model,
          home: Path.join(c.root, "home"),
          approval: :allow,
          approval_origin: :yes,
          headless: true
        },
        extra
      )

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: c.root, state_dir: c.dir, subscriber: self()}
      )

    id = Session.info(pid).id
    assert :ok = Session.prompt(pid, "synthetic request")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    {:ok, events} = Journal.load(c.dir, id)
    assert :ok = Session.close_confirmed(pid)
    events
  end

  test "non-normal ceilings deny durable research claim publication despite yes", c do
    for {field, value} <- [
          execution_mode: :draft,
          execution_mode: :planning,
          execution_mode: :read_only,
          enclosing_mode: :draft,
          enclosing_mode: :planning,
          enclosing_mode: :read_only
        ] do
      events = run(c, %{field => value})
      refute Enum.any?(events, &(&1["type"] == "research_claim"))

      refute Enum.any?(
               events,
               &(&1["type"] == "tool_started" and &1["name"] in ~w(research_source research_claim))
             )

      for call_id <- ~w(source claim) do
        assert Enum.any?(events, fn event ->
                 get_in(event, ["message", "tool_call_id"]) == call_id and
                   get_in(event, ["message", "ipse_tool_outcome", "status"]) == "denied"
               end)
      end

      assert Enum.any?(
               events,
               &(&1["type"] == "tool_started" and &1["name"] == "research_ledger")
             )
    end
  end

  test "normal mode retains ordinary research claim behavior", c do
    for config <- [
          %{},
          %{approval: :ask, approval_origin: :explicit},
          %{approval: :deny, approval_origin: :explicit}
        ] do
      events = run(c, config)
      assert Enum.any?(events, &(&1["type"] == "research_claim"))
    end
  end
end
