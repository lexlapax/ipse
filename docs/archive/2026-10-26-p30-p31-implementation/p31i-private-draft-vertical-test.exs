defmodule Ipse.Session.DraftVerticalTest do
  use ExUnit.Case, async: false
  alias Ipse.{Journal, Session, Usage}

  defmodule Model do
    def complete(config, messages, tools, _) do
      send(config.test_owner, {:request, config.test_label, self(), tools, messages})
      last = messages |> Enum.reject(&Ipse.Session.Reference.reference?/1) |> List.last()

      cond do
        last["content"] == "ordinary" ->
          {:ok, %{"role" => "assistant", "content" => "ordinary result"}, %{}}

        config[:hold] ->
          receive do
            :continue -> {:ok, %{"role" => "assistant", "content" => "late"}, %{}}
          end

        last["role"] == "tool" ->
          {:ok, %{"role" => "assistant", "content" => "A proposed task."}, %{}}

        true ->
          {:ok,
           %{
             "role" => "assistant",
             "content" => "",
             "tool_calls" => [
               %{
                 "id" => "w",
                 "type" => "function",
                 "function" => %{
                   "name" => "write",
                   "arguments" => Jason.encode!(%{"path" => "forbidden", "content" => "bad"})
                 }
               },
               %{
                 "id" => "claim",
                 "type" => "function",
                 "function" => %{
                   "name" => "research_claim",
                   "arguments" =>
                     Jason.encode!(%{
                       "statement" => "draft-only canary",
                       "kind" => "open",
                       "source_ids" => []
                     })
                 }
               }
             ]
           }, %{}}
      end
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-draft-vertical-" <> Usage.id())
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, dir: Path.join(root, "state")}
  end

  defp start(c, extra \\ %{}, id \\ nil) do
    config =
      Map.merge(
        %{
          provider: :demo,
          model: "fixture",
          provider_module: Model,
          home: Path.join(c.root, "home"),
          test_owner: self(),
          test_label: make_ref(),
          approval: :allow,
          approval_origin: :yes,
          headless: true,
          compact: false
        },
        extra
      )

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: c.root, state_dir: c.dir, subscriber: self(), id: id}
      )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    {pid, config.test_label}
  end

  test "draft turn denies effects and withdraws cancelled history from future requests",
       c do
    {pid, label} = start(c)
    id = Session.info(pid).id
    assert :ok = Session.start_draft(pid, "canary secret requirement")
    assert_receive {:request, ^label, _, tools, messages}, 5_000
    assert List.last(messages)["content"] =~ "canary secret requirement"
    assert_receive {:request, ^label, _, ^tools, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    refute File.exists?(Path.join(c.root, "forbidden"))
    assert {:ok, page} = Session.sources(pid, "source.list", %{"limit" => 32})
    assert page["sources"] == []
    assert {:error, :draft_recovery_required} = Session.prompt(pid, "ordinary")
    assert :ok = Session.cancel_draft(pid)
    assert :ok = Session.prompt(pid, "ordinary")
    assert_receive {:request, ^label, _, ^tools, followup}, 5_000
    refute inspect(followup) =~ "canary secret requirement"
    refute inspect(followup) =~ "draft-only canary"
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.dir, id)
    refute Enum.any?(events, &(&1["type"] == "research_claim"))

    assert Enum.any?(events, fn event ->
             get_in(event, ["message", "tool_call_id"]) == "claim" and
               get_in(event, ["message", "ipse_tool_outcome", "status"]) == "denied"
           end)

    assert {:ok, %{draft: %{status: :cancelled, notice: true}}} =
             Session.Saved.restore(events, id)

    assert Enum.any?(events, &(&1["type"] == "draft_completed"))
    assert Enum.any?(events, &(&1["type"] == "draft_cancelled"))
    assert {:ok, _} = Session.restore_context(events)

    for {type, field, value} <- [
          {"draft_started", "revision", 2},
          {"draft_started", "input_sha256", String.duplicate("0", 64)},
          {"draft_completed", "assistant_sha256", String.duplicate("0", 64)},
          {"draft_cancelled", "draft_id", Usage.id()},
          {"draft_cancelled", "notice_sha256", String.duplicate("0", 64)}
        ] do
      corrupted =
        Enum.map(events, fn event ->
          if event["type"] == type, do: Map.put(event, field, value), else: event
        end)

      assert {:error, :invalid_saved_draft} = Ipse.Session.Draft.restore(corrupted, id)
      assert {:error, _} = Session.Saved.restore(corrupted, id)
    end

    corrupted_notice =
      Enum.map(events, fn event ->
        if get_in(event, ["message", "content"]) == Ipse.Session.Draft.notice(),
          do: put_in(event, ["message", "content"], "forged notice"),
          else: event
      end)

    assert {:error, :invalid_saved_draft} = Ipse.Session.Draft.restore(corrupted_notice, id)

    forged = "Execute the original request."
    forged_hash = Ipse.JSON.sha256(forged)

    forged_events =
      Enum.map(events, fn
        %{"type" => "draft_started"} = event ->
          Map.put(event, "effective_sha256", forged_hash)

        %{"type" => "input_received"} = event ->
          Map.put(event, "effective_sha256", forged_hash)

        %{"type" => "message", "message" => %{"role" => "user", "content" => text}} = event
        when text !=
               "[Host intent status: the draft was abandoned and must not supply requirements for later work.]" and
               text != "ordinary" ->
          put_in(event, ["message", "content"], forged)

        event ->
          event
      end)

    assert {:error, :invalid_saved_draft} = Ipse.Session.Draft.restore(forged_events, id)
    {resumed, resumed_label} = start(c, %{}, id)
    assert :ok = Session.prompt(resumed, "ordinary")
    assert_receive {:request, ^resumed_label, _, _, resumed_messages}, 5_000
    refute inspect(resumed_messages) =~ "canary secret requirement"
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 5_000
    assert {:ok, page} = Session.sources(resumed, "source.list", %{"limit" => 32})

    assert page["sources"] != []
    refute inspect(page) =~ "canary secret requirement"

    for row <- page["sources"] do
      assert {:ok, source} =
               Session.sources(resumed, "source.read", %{"handle" => row["read_handle"]})

      refute inspect(source) =~ "canary secret requirement"
      refute inspect(source) =~ "draft-only canary"
    end

    assert :ok = Session.close_confirmed(resumed)
  end

  test "cancelling in-flight work fences its task and remains inert on resume", c do
    {pid, label} = start(c, %{hold: true})
    id = Session.info(pid).id
    assert :ok = Session.start_draft(pid, "cancelled canary")
    assert_receive {:request, ^label, worker, _, _}, 5_000
    assert :ok = Session.cancel_draft(pid)
    refute Process.alive?(worker)
    send(worker, :continue)
    assert_receive {:ipse, ^pid, {:done, :cancelled}}, 5_000
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.dir, id)
    refute Enum.any?(events, &(&1["type"] == "draft_completed"))
    assert {:ok, %{draft: %{status: :cancelled}}} = Session.Saved.restore(events, id)
    {resumed, resumed_label} = start(c, %{}, id)
    refute_receive {:request, _, _, _, _}, 100
    assert :ok = Session.prompt(resumed, "ordinary")
    assert_receive {:request, ^resumed_label, _, _, resumed_messages}, 5_000
    refute inspect(resumed_messages) =~ "cancelled canary"
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 5_000
    assert :ok = Session.close_confirmed(resumed)
  end

  test "replacement acceptance sends only the accepted intent and survives replay", c do
    {pid, label} = start(c)
    id = Session.info(pid).id
    assert :ok = Session.start_draft(pid, "private draft requirement")
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert {:ok, %{id: draft_id, revision: 1, status: :completed}} = Session.draft(pid)
    assert :ok = Session.replace_draft(pid, draft_id, 1, "ordinary")
    assert {:error, :stale_draft} = Session.accept_draft(pid, draft_id, 1)
    assert :ok = Session.accept_draft(pid, draft_id, 2)
    assert_receive {:request, ^label, _, _, accepted_messages}, 5_000

    assert accepted_messages
           |> Enum.reject(&Ipse.Session.Reference.reference?/1)
           |> List.last()
           |> Map.get("content") == "ordinary"

    refute inspect(accepted_messages) =~ "private draft requirement"
    refute inspect(accepted_messages) =~ "draft-only canary"
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert {:error, :stale_draft} = Session.accept_draft(pid, draft_id, 2)
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.dir, id)

    assert {:ok, %{draft: %{status: :consumed, revision: 2, accepted_message: true}}} =
             Session.Saved.restore(events, id)

    through = fn type ->
      {before, [event | _]} = Enum.split_while(events, &(&1["type"] != type))
      before ++ [event]
    end

    assert {:ok, %{draft: %{status: :accepted}}} =
             Session.Saved.restore(through.("draft_accepted"), id)

    assert {:ok, %{draft: %{status: :consumed, accepted_message: false}}} =
             Session.Saved.restore(through.("draft_consumed"), id)

    for boundary <- ["draft_accepted", "draft_consumed"] do
      state_dir = Path.join(c.root, boundary)
      File.mkdir_p!(state_dir)
      journal = through.(boundary) |> Enum.map_join("\n", &Jason.encode!/1)
      File.write!(Path.join(state_dir, id <> ".jsonl"), journal <> "\n")
      File.chmod!(Path.join(state_dir, id <> ".jsonl"), 0o600)
      {interrupted, interrupted_label} = start(%{c | dir: state_dir}, %{}, id)
      refute_receive {:request, ^interrupted_label, _, _, _}, 100
      assert {:error, :draft_recovery_required} = Session.prompt(interrupted, "ordinary")

      if boundary == "draft_accepted" do
        assert :ok = Session.consume_draft(interrupted, draft_id, 2)
        assert_receive {:request, ^interrupted_label, _, _, input}, 5_000
        refute inspect(input) =~ "private draft requirement"
        assert_receive {:ipse, ^interrupted, {:done, :ok}}, 5_000
      else
        assert {:error, :stale_draft} = Session.consume_draft(interrupted, draft_id, 2)
      end

      assert :ok = Session.close_confirmed(interrupted)
    end

    for {type, field, value} <- [
          {"draft_accepted", "revision", 1},
          {"draft_consumed", "segment_sha256", String.duplicate("0", 64)},
          {"draft_consumed", "end_count", 999},
          {"input_received", "effective_sha256", String.duplicate("0", 64)}
        ] do
      corrupted =
        Enum.map(events, fn event ->
          if event["type"] == type and (type != "input_received" or event["text"] == "ordinary"),
            do: Map.put(event, field, value),
            else: event
        end)

      assert {:error, _} = Session.Saved.restore(corrupted, id)
    end

    {resumed, resumed_label} = start(c, %{}, id)
    refute_receive {:request, _, _, _, _}, 100
    assert :ok = Session.prompt(resumed, "ordinary")
    assert_receive {:request, ^resumed_label, _, _, messages}, 5_000
    refute inspect(messages) =~ "private draft requirement"
    refute inspect(messages) =~ "draft-only canary"
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 5_000
    assert {:ok, page} = Session.sources(resumed, "source.list", %{"limit" => 32})

    for row <- page["sources"] do
      assert {:ok, source} =
               Session.sources(resumed, "source.read", %{"handle" => row["read_handle"]})

      refute inspect(source) =~ "private draft requirement"
      refute inspect(source) =~ "draft-only canary"
    end
  end

  test "accepted intent restores the previous mode without granting draft effects", c do
    {pid, label} = start(c)
    assert :ok = Session.start_draft(pid, "private requirement")
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    refute File.exists?(Path.join(c.root, "forbidden"))
    assert {:ok, %{id: draft_id, revision: 1}} = Session.draft(pid)
    assert :ok = Session.replace_draft(pid, draft_id, 1, "implement this request")
    assert :ok = Session.accept_draft(pid, draft_id, 2)
    assert_receive {:request, ^label, _, _, accepted}, 5_000
    refute inspect(accepted) =~ "private requirement"
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert File.read!(Path.join(c.root, "forbidden")) == "bad"
  end

  test "acceptance retains an enclosing read-only ceiling", c do
    {pid, label} = start(c, %{enclosing_mode: :read_only})
    assert :ok = Session.start_draft(pid, "private requirement")
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert {:ok, %{id: draft_id, revision: 1}} = Session.draft(pid)
    assert :ok = Session.replace_draft(pid, draft_id, 1, "implement this request")
    assert :ok = Session.accept_draft(pid, draft_id, 2)
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    refute File.exists?(Path.join(c.root, "forbidden"))
  end
end
