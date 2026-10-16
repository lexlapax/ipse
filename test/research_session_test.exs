defmodule Ipse.ResearchSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal, Research, Compaction}
  import ExUnit.CaptureIO

  defmodule Model do
    def complete(config, messages, _tools, _emit) do
      send(config.test_pid, :research_inference)

      if List.last(messages)["role"] == "tool" do
        {:ok, %{"role" => "assistant", "content" => "Evidence saved"}, %{}}
      else
        name =
          if List.last(messages)["content"] == "ledger",
            do: "research_ledger",
            else: "research_source"

        args =
          if name == "research_ledger",
            do: %{},
            else: %{
              "tool_call_id" => "fetch",
              "url" => "https://example.com/page",
              "excerpt" => "Observed fixture fact."
            }

        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "native-#{name}",
               "type" => "function",
               "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
             }
           ]
         }, %{}}
      end
    end
  end

  test "native capture survives real compaction and idle resume; local export needs no inference" do
    root =
      Path.join(System.tmp_dir!(), "ipse-research-session-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    dir = Path.join(root, "sessions")
    {:ok, id} = Journal.create(dir, %{"provider" => "demo", "model" => "fixture", "cwd" => root})

    messages = [
      %{"role" => "user", "content" => "Research public fixture"},
      %{
        "role" => "assistant",
        "content" => "",
        "tool_calls" => [
          %{
            "id" => "fetch",
            "type" => "function",
            "function" => %{"name" => "mcp__fixture__fetch", "arguments" => "{}"}
          }
        ]
      },
      %{
        "role" => "tool",
        "tool_call_id" => "fetch",
        "content" =>
          "https://example.com/page Observed fixture fact. " <>
            String.duplicate("old source detail ", 400),
        "ipse_tool_outcome" => %{"status" => "result_recorded", "approval" => "approved"}
      },
      %{"role" => "assistant", "content" => "Evidence collected"},
      %{"role" => "user", "content" => "Continue"},
      %{"role" => "assistant", "content" => "Continuing"},
      %{"role" => "user", "content" => "Capture useful evidence"}
    ]

    for message <- messages do
      if message["role"] == "tool",
        do:
          Journal.append(dir, id, %{
            "type" => "tool_started",
            "name" => "mcp__fixture__fetch",
            "call_id" => "fetch"
          })

      :ok = Journal.append(dir, id, %{"type" => "message", "message" => message})
    end

    config = %{
      provider: :demo,
      model: "fixture",
      provider_module: Model,
      test_pid: self(),
      home: Path.join(root, "home"),
      approval: :deny
    }

    opts = [config: config, cwd: root, state_dir: dir, id: id, subscriber: self()]
    {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})
    :ok = Session.prompt(pid, "capture")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    :ok = Session.close(pid)
    {:ok, events} = Journal.load(dir, id)

    assert Enum.find_index(events, &(&1["type"] == "research_source")) <
             Enum.find_index(
               events,
               &(get_in(&1, ["message", "tool_call_id"]) == "native-research_source")
             )

    {:ok, ledger} = Research.load(dir, id)
    assert length(ledger["sources"]) == 1
    system = %{"role" => "system", "content" => "fixture rules"}
    limits = %{context_bytes: 20_000, compact_threshold_bytes: 2000}
    assert {:ok, plan} = Compaction.prepare(messages, limits, system)

    summary = %{
      "role" => "assistant",
      "content" =>
        Jason.encode!(%{
          "facts" => ["Details reduced"],
          "decisions" => [],
          "open_questions" => []
        })
    }

    assert {:ok, _, checkpoint, stats} = Compaction.finish(plan, summary, system, limits)

    :ok =
      Journal.append(dir, id, %{
        "type" => "context_compacted",
        "version" => 1,
        "covered_messages" => length(plan.prefix),
        "prefix_sha256" => Compaction.digest(plan.prefix),
        "checkpoint" => checkpoint,
        "before_bytes" => stats.before_bytes,
        "after_bytes" => stats.after_bytes
      })

    assert {:ok, ^ledger} = Research.load(dir, id)
    bytes = File.read!(Path.join(dir, id <> ".jsonl"))

    drain = fn drain ->
      receive do
        :research_inference -> drain.(drain)
      after
        0 -> :ok
      end
    end

    drain.(drain)
    {:ok, resumed} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})
    assert Session.info(resumed).phase == :idle
    refute_receive :research_inference, 50
    assert File.read!(Path.join(dir, id <> ".jsonl")) == bytes
    assert {:ok, ^ledger} = Research.load(dir, id)
    :ok = Session.prompt(resumed, "ledger")
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 3000
    {:ok, final_events} = Journal.load(dir, id)

    ledger_result =
      Enum.find(
        final_events,
        &(get_in(&1, ["message", "tool_call_id"]) == "native-research_ledger")
      )["message"]

    assert ledger_result["ipse_tool_outcome"]["status"] == "result_recorded"
    assert Jason.decode!(ledger_result["content"])["sources"] == ledger["sources"]

    assert [%{"tool_call_id" => "fetch"}] =
             Jason.decode!(ledger_result["content"])["available_results"]

    :ok = Session.close(resumed)

    output =
      capture_io(fn ->
        assert Ipse.CLI.run(["research", "--resume", id, "--state-dir", dir]) == 0
      end)

    assert Jason.decode!(output) == ledger
  end
end
