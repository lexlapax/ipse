defmodule Ipse.Session.ReferenceReplayTest do
  use ExUnit.Case, async: true
  alias Ipse.Session.{Context, Reference, Saved}

  @session String.duplicate("a", 32)
  @turn String.duplicate("b", 32)
  @next String.duplicate("c", 32)
  @metadata %{"type" => "session", "metadata" => %{"reference_layout" => "turn_reference_v1"}}
  @header [
    %{"role" => "system", "content" => "rules"},
    %{"role" => "user", "content" => "admitted sources"}
  ]
  @publishers %{"runtime" => %{}, "workspace" => "", "skills" => "", "extensions" => ""}
  @user %{"role" => "user", "content" => "initial request"}
  @resume %{"role" => "user", "content" => "inspect before continuing"}
  @call %{
    "role" => "assistant",
    "content" => "",
    "tool_calls" => [%{"id" => "one", "function" => %{"name" => "read", "arguments" => "{}"}}],
    "provider_data" => %{"opaque" => "retained native continuation"}
  }
  @result %{"role" => "tool", "tool_call_id" => "one", "content" => "actual result"}

  defp message(value), do: %{"type" => "message", "message" => value}

  defp input(message, turn),
    do: Ipse.Session.Input.received(@session, turn, message["content"], message["content"], nil)

  defp admitted do
    {:ok, initial} = Reference.restore([@metadata], @session)
    initial = Reference.seed(initial, @header, @publishers)

    {:ok, [admission], state, []} =
      Reference.prepare(initial, @session, @turn, @publishers, [], [@user])

    {[@metadata, admission, input(@user, @next)], state}
  end

  defp envelope(state, messages, turn \\ @next) do
    {:ok, [event], _, [reference]} =
      Reference.prepare(
        state,
        @session,
        turn,
        Map.put(@publishers, "extensions", "current reference"),
        [],
        messages
      )

    {event, reference}
  end

  test "a reference cannot synthesize a missing result at its own insertion boundary" do
    {journal, state} = admitted()
    {event, _} = envelope(state, [@user, @call, @result])
    incomplete = journal ++ Enum.map([@user, @call], &message/1)

    assert {:error, :invalid_reference_context} = Saved.context(incomplete ++ [event])

    assert {:error, :invalid_reference_context} =
             Saved.context(incomplete ++ [event, message(@result)])
  end

  test "a genuine resumed user closes unknown history before its new reference" do
    {journal, state} = admitted()
    interrupted = journal ++ Enum.map([@user, @call], &message/1)
    assert {:ok, [@user, @call, unknown]} = Saved.context(interrupted)
    assert unknown["ipse_tool_outcome"]["status"] == "unknown"
    effective = [@user, @call, unknown, @resume]
    {event, reference} = envelope(state, effective, @turn)

    assert {:ok, projected} =
             Saved.context(interrupted ++ [input(@resume, @turn), message(@resume), event])

    assert projected == effective ++ [reference]
    assert Reference.safe_tail?(projected)
    assert Enum.at(projected, 1) == @call
  end

  test "a real result cannot arrive after a user recovery boundary closed that call" do
    {journal, _} = admitted()

    assert {:error, :invalid_reference_context} =
             Saved.context(journal ++ Enum.map([@user, @call, @resume, @result], &message/1))
  end

  test "complete parallel groups retain all real results and native continuation" do
    {journal, state} = admitted()
    two = %{"id" => "two", "function" => %{"name" => "read", "arguments" => "{}"}}
    call = Map.update!(@call, "tool_calls", &(&1 ++ [two]))
    result = Map.put(@result, "tool_call_id", "two")
    history = [@user, call, result, @result]
    {event, reference} = envelope(state, history)

    assert {:ok, [@user, ^call, ^result, @result, ^reference]} =
             Saved.context(journal ++ Enum.map(history, &message/1) ++ [event])
  end

  test "an interrupted parallel group appends unknowns after recorded results" do
    {journal, _} = admitted()
    two = %{"id" => "two", "function" => %{"name" => "read", "arguments" => "{}"}}
    call = Map.update!(@call, "tool_calls", &(&1 ++ [two]))
    result = Map.put(@result, "tool_call_id", "two")

    assert {:ok, [@user, ^call, ^result, unknown]} =
             Saved.context(journal ++ Enum.map([@user, call, result], &message/1))

    assert unknown["tool_call_id"] == "one"
    assert unknown["ipse_tool_outcome"]["status"] == "unknown"
  end

  test "orphan, duplicate, malformed and interrupted-by-assistant groups refuse without an envelope" do
    {journal, _} = admitted()

    for history <- [
          [@user, @result],
          [@user, @call, @result, @result],
          [@user, @call, %{"role" => "assistant", "content" => "split"}],
          [@user, Map.put(@call, "tool_calls", false)],
          [@user, @call, Map.delete(@result, "tool_call_id")]
        ] do
      assert {:error, :invalid_reference_context} =
               Saved.context(journal ++ Enum.map(history, &message/1))
    end
  end

  test "a rehashed checkpoint cannot cut through a complete native group" do
    {journal, _} = admitted()

    plan = %{
      prefix: [@user],
      tail: [],
      user_intents: [@user["content"]],
      actions: [],
      before_bytes: 10_000,
      target_bytes: 9_000
    }

    summary = %{
      "role" => "assistant",
      "content" => Jason.encode!(%{"decisions" => [], "facts" => [], "open_questions" => []})
    }

    assert {:ok, _, checkpoint, _} = Context.finish_compaction(plan, summary, @header, %{})
    history = [@user, @call, @result]

    event = %{
      "type" => "context_compacted",
      "version" => 1,
      "covered_messages" => 2,
      "prefix_sha256" => Ipse.JSON.digest(Enum.take(history, 2)),
      "checkpoint" => checkpoint
    }

    assert {:error, :invalid_reference_context} =
             Saved.context(journal ++ Enum.map(history, &message/1) ++ [event])
  end

  test "legacy interrupted reconstruction retains its prior projection" do
    legacy = %{"type" => "session", "metadata" => %{}}

    assert {:ok, [@user, @call, unknown, @resume]} =
             Saved.context([legacy | Enum.map([@user, @call, @resume], &message/1)])

    assert unknown["ipse_tool_outcome"]["status"] == "unknown"
  end
end

defmodule Ipse.Session.ReferenceReplaySessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{Journal, Session}

  defmodule Provider do
    def complete(config, messages, _tools, _emit) do
      send(config.test_pid, {:reference_replay_request, messages})

      calls =
        if Enum.any?(messages, &(&1["role"] == "tool" and &1["tool_call_id"] == "ask")) do
          []
        else
          questions = %{
            "questions" => [
              %{"id" => "choice", "kind" => "text", "prompt" => "What should be inspected?"}
            ]
          }

          [
            %{
              "id" => "ask",
              "function" => %{"name" => "ask_operator", "arguments" => Jason.encode!(questions)}
            },
            %{
              "id" => "later",
              "function" => %{"name" => "read", "arguments" => ~s({"path":"never-read.txt"})}
            }
          ]
        end

      {:ok,
       %{
         "role" => "assistant",
         "content" => if(calls == [], do: "Done", else: ""),
         "tool_calls" => calls,
         "provider_data" => %{"opaque" => "native continuation"}
       }, %{}}
    end
  end

  test "native ask_operator delayed result order stays byte-identical across resume" do
    root =
      Path.join(System.tmp_dir!(), "ipse-reference-replay-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    dir = Path.join(root, "state")

    config = %{
      provider: :demo,
      model: "reference-replay-fixture",
      provider_module: Provider,
      home: Path.join(root, "home"),
      test_pid: self(),
      approval: :ask,
      operator_questions: true
    }

    options = [cwd: root, state_dir: dir, subscriber: self(), config: config]
    assert {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, options})
    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    assert :ok = Session.prompt(pid, "Ask before inspecting")
    assert_receive {:reference_replay_request, _}, 2000
    assert_receive {:ipse, ^pid, {:question, "ask", _}}, 2000
    assert :ok = Session.answer(pid, "ask", %{"choice" => "inspect outcomes"})
    assert_receive {:reference_replay_request, continuation}, 2000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000

    assert Enum.map(Enum.filter(continuation, &(&1["role"] == "tool")), & &1["tool_call_id"]) ==
             ["later", "ask"]

    id = Session.info(pid).id
    assert :ok = Session.close(pid)
    assert {:ok, events} = Journal.load(dir, id)
    assert {:ok, restored} = Session.Saved.context(events)

    assert Jason.encode!(Enum.take(restored, length(continuation) - 2)) ==
             Jason.encode!(Enum.drop(continuation, 2))

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, Keyword.put(options, :id, id)}
             )

    on_exit(fn -> if Process.alive?(resumed), do: Session.close(resumed) end)
    assert :ok = Session.prompt(resumed, "Continue from the saved answer")
    assert_receive {:reference_replay_request, next}, 2000
    assert Enum.take(next, length(continuation)) == continuation
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 2000
  end
end
