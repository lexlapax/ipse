defmodule Ipse.Session.QuestionEOFTest do
  use ExUnit.Case, async: false
  alias Ipse.Session

  defmodule Provider do
    def complete(_config, _messages, _tools, _emit) do
      arguments = %{
        "questions" => [%{"id" => "detail", "kind" => "text", "prompt" => "Synthetic detail?"}]
      }

      {:ok,
       %{
         "role" => "assistant",
         "content" => "",
         "tool_calls" => [
           %{
             "id" => Ipse.Usage.id(),
             "function" => %{"name" => "ask_operator", "arguments" => Jason.encode!(arguments)}
           }
         ]
       }, %{}}
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-question-eof-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    config = %{
      provider: :demo,
      provider_module: Provider,
      model: "synthetic",
      home: Path.join(root, "home"),
      approval: :ask,
      operator_questions: true
    }

    {:ok, session} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: config, cwd: root, state_dir: Path.join(root, "state"), subscriber: self()}
      )

    reader = spawn(fn -> receive do: (:stop -> :ok) end)

    on_exit(fn ->
      if Process.alive?(session), do: Session.close(session)
      Process.exit(reader, :kill)
    end)

    {:ok, channel} = Session.open_input_channel(session, reader)
    %{session: session, reader: reader, channel: channel, root: root}
  end

  # This host-state fixture exercises ticket ownership, not terminal attestation.
  # Actual native observation and cleanup have separate serial PTY fixtures.
  defp observed(c, text) do
    state = :sys.get_state(c.session)
    witness = make_ref()

    binding = %{
      session_id: state.id,
      cwd: state.cwd,
      generation: state.operator_channel.generation,
      channel_id: c.channel,
      purpose: "prompt",
      render_id: nil
    }

    observation = %{
      "version" => 2,
      "event_id" => Ipse.Usage.id(),
      "text" => text,
      "text_sha256" => Ipse.JSON.sha256(text),
      "display_sha256" => Ipse.JSON.sha256("you> "),
      "input_limit" => 1_048_576,
      "display_limit" => 16_777_216
    }

    :sys.replace_state(Session.Input, fn s ->
      entry = %{
        target: c.session,
        kind: :observation,
        client: c.reader,
        target_monitor: Process.monitor(c.session),
        client_monitor: Process.monitor(c.reader),
        task: nil,
        from: nil,
        cancelled: false,
        binding: binding,
        display_sha256: observation["display_sha256"],
        observation: observation,
        expires: System.monotonic_time(:millisecond) + 300_000,
        timer: nil
      }

      put_in(s.entries[witness], entry)
    end)

    witness
  end

  defp staged(c, text) do
    witness = observed(c, text)
    assert {:ok, ticket} = Session.stage_input(c.session, c.channel, text, witness)
    ticket
  end

  defp await_question(session) do
    assert_receive {:ipse, ^session, {:question, _, _}}, 2_000
    assert :sys.get_state(session).phase == :question
  end

  test "question EOF preserves only existing staged prompts for the current client", c do
    session = c.session
    assert :ok = Session.prompt(session, "first synthetic question")
    await_question(session)
    first = staged(c, "queued café one")
    second = staged(c, "queued 日本語 two")
    third = staged(c, "explicit cancel invalidates this")
    assert {:ok, render} = Session.render_question(session, c.channel, "detail")
    unstaged = observed(c, "not queued before EOF")

    assert {:error, :no_pending_question} = Session.question_eof(session, Ipse.Usage.id())

    assert {:error, :no_pending_question} =
             Task.async(fn -> Session.question_eof(session, c.channel) end) |> Task.await()

    assert :sys.get_state(session).operator_render == render
    assert :ok = Session.question_eof(session, c.channel)
    assert_receive {:ipse, ^session, {:done, :cancelled}}, 2_000
    state = :sys.get_state(session)
    assert state.phase == :idle
    assert state.question == nil
    assert state.operator_render == nil
    assert state.operator_answers == %{}
    assert state.operator_pieces == []

    assert {:error, :invalid_input_witness} =
             Session.stage_input(session, c.channel, "not queued before EOF", unstaged)

    assert :ok = Session.prompt(session, "queued café one", first)
    await_question(session)
    assert :ok = Session.question_eof(session, c.channel)
    assert_receive {:ipse, ^session, {:done, :cancelled}}, 2_000
    assert :ok = Session.prompt(session, "queued 日本語 two", second)
    await_question(session)
    assert :ok = Session.cancel(session)
    assert_receive {:ipse, ^session, {:done, :cancelled}}, 2_000

    assert {:error, :invalid_input_witness} =
             Session.prompt(session, "explicit cancel invalidates this", third)

    assert {:error, :no_pending_question} = Session.question_eof(session, c.channel)
    id = Session.info(session).id
    assert :ok = Session.close_confirmed(session)
    assert {:ok, events} = Ipse.Journal.load(Path.join(c.root, "state"), id)
    assert :ok = Session.Input.validate_events(events, id)
    assert {:ok, _} = Session.Saved.restore(events, id)
    refute Enum.any?(events, &(&1["type"] == "operator_answer"))

    assert Enum.map(Enum.filter(events, &(&1["type"] == "input_received")), & &1["text"]) ==
             ["first synthetic question", "queued café one", "queued 日本語 two"]
  end
end
