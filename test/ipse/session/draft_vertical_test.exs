defmodule Ipse.Session.DraftVerticalTest do
  use ExUnit.Case, async: false
  alias Ipse.{Journal, Session, Usage}

  defmodule Model do
    def complete(config, messages, tools, _) do
      send(config.test_owner, {:request, config.test_label, self(), tools, messages})
      last = messages |> Enum.reject(&Ipse.Session.Reference.reference?/1) |> List.last()

      cond do
        tools == [] ->
          {:ok,
           %{
             "role" => "assistant",
             "content" =>
               Jason.encode!(%{
                 "decisions" => [],
                 "facts" => ["unrelated history"],
                 "open_questions" => []
               })
           }, %{}}

        config[:poison] ->
          {:ok,
           %{
             "role" => "assistant",
             "content" => "proposal",
             "provider_data" => %{"reported_model" => "draft-derived-model-canary"}
           }, %{}}

        last["content"] == "ordinary" ->
          {:ok, %{"role" => "assistant", "content" => "ordinary result"}, %{}}

        is_binary(last["content"]) and String.starts_with?(last["content"], "history:") ->
          {:ok, %{"role" => "assistant", "content" => String.duplicate("history response ", 160)},
           %{}}

        config[:hold] ->
          receive do
            :continue -> {:ok, %{"role" => "assistant", "content" => "late"}, %{}}
          end

        last["role"] == "tool" ->
          {:ok, %{"role" => "assistant", "content" => "A proposed task."}, %{}}

        config[:draft_read] == true and is_binary(last["content"]) and
            String.starts_with?(last["content"], "Draft a clearer version") ->
          {:ok,
           %{
             "role" => "assistant",
             "content" => "",
             "tool_calls" => [
               %{
                 "id" => "read-evidence",
                 "type" => "function",
                 "function" => %{
                   "name" => "read",
                   "arguments" => Jason.encode!(%{"path" => "evidence.txt"})
                 }
               }
             ]
           }, %{}}

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

  defmodule QuestionModel do
    def complete(config, _, _, _) do
      send(config.test_owner, {:question_model, config.test_label})
      args = %{"questions" => [%{"id" => "detail", "kind" => "text", "prompt" => "Detail?"}]}

      {:ok,
       %{
         "role" => "assistant",
         "content" => "",
         "tool_calls" => [
           %{
             "id" => "draft-q",
             "type" => "function",
             "function" => %{"name" => "ask_operator", "arguments" => Jason.encode!(args)}
           }
         ]
       }, %{}}
    end
  end

  defmodule NativeModel do
    def complete(config, messages, tools, _) do
      send(config.test_owner, {:native_request, config.test_label, messages, tools})
      last = messages |> Enum.reject(&Ipse.Session.Reference.reference?/1) |> List.last()

      if last["content"] == "ordinary" do
        {:ok, %{"role" => "assistant", "content" => "ordinary result"}, %{}}
      else
        {:ok,
         %{
           "role" => "assistant",
           "content" => "native draft answer canary",
           "provider_data" => %{
             "provider" => "openai",
             "reported_model" => "draft-model-canary",
             "output" => [
               %{
                 "type" => "reasoning",
                 "id" => "rs_draft",
                 "summary" => [],
                 "content" => nil,
                 "encrypted_content" => "encrypted native canary"
               },
               %{
                 "type" => "message",
                 "id" => "msg_draft",
                 "role" => "assistant",
                 "status" => "completed",
                 "phase" => "final_answer",
                 "content" => [
                   %{
                     "type" => "output_text",
                     "text" => "native draft answer canary",
                     "annotations" => [],
                     "logprobs" => []
                   }
                 ]
               }
             ]
           }
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

  # Tests replay and authority after acceptance. A separate PTY test proves the
  # witness; this synthetic journal fixture does not claim terminal origin.
  defp synthetic_accepted_resume(c, pid, extra \\ %{}) do
    id = Session.info(pid).id
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.dir, id)
    {:ok, draft} = Ipse.Session.Draft.restore(events, id)
    {:ok, render} = Ipse.Session.DraftAcceptance.render(draft, Usage.id())
    text = "accept " <> render["code"]

    observation = %{
      "version" => 2,
      "event_id" => Usage.id(),
      "display_limit" => 16_777_216,
      "input_limit" => 1_048_576,
      "display_sha256" => Ipse.JSON.sha256(render["display"]),
      "text_sha256" => Ipse.JSON.sha256(text)
    }

    {:ok, receipt} = Ipse.Session.DraftAcceptance.receipt(draft, render, text, observation)
    assert :ok = Journal.append(c.dir, id, Ipse.Session.Draft.accepted(draft, receipt))
    {resumed, label} = start(c, extra, id)
    assert :ok = Session.consume_draft(resumed, draft.id, draft.revision)
    {resumed, label}
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

    {before, [marker | _]} = Enum.split_while(events, &(&1["type"] != "draft_cancelled"))
    crash_dir = Path.join(c.root, "cancel-before-notice")
    File.mkdir_p!(crash_dir)
    crash_file = Path.join(crash_dir, id <> ".jsonl")
    File.write!(crash_file, Enum.map_join(before ++ [marker], "\n", &Jason.encode!/1) <> "\n")
    File.chmod!(crash_file, 0o600)
    {crashed, crash_label} = start(%{c | dir: crash_dir}, %{}, id)
    refute_receive {:request, ^crash_label, _, _, _}, 100
    assert {:error, :draft_recovery_required} = Session.prompt(crashed, "ordinary")
    assert :ok = Session.cancel_draft(crashed)
    assert :ok = Session.prompt(crashed, "ordinary")
    assert_receive {:request, ^crash_label, _, _, recovered_messages}, 5_000
    refute inspect(recovered_messages) =~ "canary secret requirement"
    assert_receive {:ipse, ^crashed, {:done, :ok}}, 5_000
    assert :ok = Session.close_confirmed(crashed)

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
    assert {:error, :native_draft_acceptance_required} = Session.accept_draft(pid, draft_id, 1)
    assert {:error, :native_draft_acceptance_required} = Session.accept_draft(pid, draft_id, 2)
    {pid, label} = synthetic_accepted_resume(c, pid)
    assert_receive {:request, ^label, _, _, accepted_messages}, 5_000

    assert accepted_messages
           |> Enum.reject(&Ipse.Session.Reference.reference?/1)
           |> List.last()
           |> Map.get("content") == "ordinary"

    refute inspect(accepted_messages) =~ "private draft requirement"
    refute inspect(accepted_messages) =~ "draft-only canary"
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert {:error, :native_draft_acceptance_required} = Session.accept_draft(pid, draft_id, 2)
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
    id = Session.info(pid).id
    assert :ok = Session.start_draft(pid, "private requirement")
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    refute File.exists?(Path.join(c.root, "forbidden"))
    assert {:ok, %{id: draft_id, revision: 1}} = Session.draft(pid)
    assert :ok = Session.replace_draft(pid, draft_id, 1, "implement this request")
    {pid, label} = synthetic_accepted_resume(c, pid)
    assert_receive {:request, ^label, _, _, accepted}, 5_000
    refute inspect(accepted) =~ "private requirement"
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert File.read!(Path.join(c.root, "forbidden")) == "bad"
    assert :ok = Session.prompt(pid, "later unrelated task")
    assert_receive {:request, ^label, _, _, later_input}, 5_000
    refute inspect(later_input) =~ "private requirement"
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.dir, id)
    accepted = Enum.find(events, &(&1["type"] == "draft_accepted"))
    effect = Enum.find(events, &(&1["type"] == "draft_effect_intent" and &1["call_id"] == "w"))

    assert Enum.count(events, &(&1["type"] == "draft_effect_intent" and &1["call_id"] == "w")) ==
             2

    assert [lineage] = effect["possible_source_lineages"]
    assert lineage["input_source_id"] == accepted["input_source_id"]
    assert lineage["question_ids"] == accepted["question_ids"]
    assert lineage["answer_source_ids"] == accepted["answer_source_ids"]
    assert lineage["tool_evidence"] == accepted["tool_evidence"]
    assert {:ok, _} = Session.Saved.restore(events, id)

    corrupt =
      Enum.map(events, fn event ->
        if event == effect,
          do: Map.put(event, "call_sha256", String.duplicate("0", 64)),
          else: event
      end)

    assert {:error, _} = Session.Saved.restore(corrupt, id)
    missing_link = Enum.reject(events, &(&1 == effect))
    assert {:error, _} = Session.Saved.restore(missing_link, id)
  end

  test "acceptance retains an enclosing read-only ceiling", c do
    {pid, label} = start(c, %{enclosing_mode: :read_only})
    assert :ok = Session.start_draft(pid, "private requirement")
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert {:ok, %{id: draft_id, revision: 1}} = Session.draft(pid)
    assert :ok = Session.replace_draft(pid, draft_id, 1, "implement this request")
    {pid, label} = synthetic_accepted_resume(c, pid, %{enclosing_mode: :read_only})
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    refute File.exists?(Path.join(c.root, "forbidden"))
  end

  test "multiple cancelled drafts stay withdrawn during later drafts and replay", c do
    {pid, label} = start(c)
    id = Session.info(pid).id

    for {text, prior} <- [
          {"first private requirement", nil},
          {"second private requirement", "first private requirement"}
        ] do
      assert :ok = Session.start_draft(pid, text)
      assert_receive {:request, ^label, _, _, first}, 5_000
      if prior, do: refute(inspect(first) =~ prior)
      assert_receive {:request, ^label, _, _, _}, 5_000
      assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
      assert :ok = Session.cancel_draft(pid)
    end

    assert :ok = Session.rebase_draft(pid)
    assert {:error, :draft_unavailable} = Session.rebase_draft(pid)
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.dir, id)
    assert Enum.any?(events, &(&1["type"] == "draft_rebased"))
    assert {:ok, %{draft: nil, messages: rebased}} = Session.Saved.restore(events, id)
    refute inspect(rebased) =~ "first private requirement"
    refute inspect(rebased) =~ "second private requirement"

    for field <- ["before_sha256", "after_sha256"] do
      corrupt =
        Enum.map(events, fn e ->
          if e["type"] == "draft_rebased",
            do: Map.put(e, field, String.duplicate("0", 64)),
            else: e
        end)

      assert {:error, _} = Session.Saved.restore(corrupt, id)
    end

    {before, [boundary | _]} = Enum.split_while(events, &(&1["type"] != "draft_rebased"))
    recovery_dir = Path.join(c.root, "rebased-crash")
    File.mkdir_p!(recovery_dir)
    recovery_file = Path.join(recovery_dir, id <> ".jsonl")

    File.write!(
      recovery_file,
      Enum.map_join(before ++ [boundary], "\n", &Jason.encode!/1) <> "\n"
    )

    File.chmod!(recovery_file, 0o600)
    {recovered, recovered_label} = start(%{c | dir: recovery_dir}, %{}, id)
    refute_receive {:request, ^recovered_label, _, _, _}, 100
    assert :ok = Session.prompt(recovered, "ordinary")
    assert_receive {:request, ^recovered_label, _, _, recovered_messages}, 5_000
    refute inspect(recovered_messages) =~ "first private requirement"
    refute inspect(recovered_messages) =~ "second private requirement"
    assert_receive {:ipse, ^recovered, {:done, :ok}}, 5_000
    assert :ok = Session.close_confirmed(recovered)

    assert Enum.any?(events, &(&1["type"] == "reference_envelope"))

    forged =
      Enum.map(events, fn event ->
        if event["type"] == "reference_envelope",
          do: %{"type" => "message", "message" => Ipse.Session.Reference.message(event)},
          else: event
      end)

    assert {:error, _} = Session.Saved.restore(forged, id)
    {resumed, resumed_label} = start(c, %{}, id)
    assert :ok = Session.prompt(resumed, "ordinary")
    assert_receive {:request, ^resumed_label, _, _, messages}, 5_000
    refute inspect(messages) =~ "first private requirement"
    refute inspect(messages) =~ "second private requirement"
    refute inspect(messages) =~ "draft-only canary"
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 5_000
  end

  test "draft-derived provider metadata prevents any later dispatch and replay", c do
    {pid, label} = start(c, %{poison: true})
    id = Session.info(pid).id
    assert :ok = Session.start_draft(pid, "sensitive draft")
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert :ok = Session.cancel_draft(pid)
    assert :ok = Session.prompt(pid, "ordinary")
    assert_receive {:ipse, ^pid, {:done, :error}}, 5_000
    refute_receive {:request, ^label, _, _, _}, 100
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.dir, id)
    assert {:error, :draft_projection_unsafe} = Session.Saved.restore(events, id)
  end

  test "ChatGPT-native interval is withdrawn intact without model-metadata carryover", c do
    auth = Path.join(c.root, "synthetic-auth")

    record = %{
      "access_token" => "fixture-access",
      "refresh_token" => "fixture-refresh",
      "id_token" => "fixture-id",
      "client_id" => "oaiapp_fixture",
      "ext_agent_host_id" => "urn:uuid:00112233-4455-4677-8899-aabbccddeeff",
      "subject" => "fixture",
      "issuer" => "https://auth.openai.com",
      "email" => "fixture@example.test",
      "expires_at" => System.system_time(:second) + 3600,
      "scopes" => ["chatgpt.tokens.use.direct"]
    }

    assert :ok =
             Ipse.Auth.with_credential_lock(auth, fn ->
               Ipse.Auth.write_credentials(auth, record)
             end)

    cfg = %{
      provider: :chatgpt,
      provider_module: NativeModel,
      max_output_tokens: nil,
      auth_dir: auth
    }

    {pid, label} = start(c, cfg)
    id = Session.info(pid).id
    assert :ok = Session.start_draft(pid, "native private draft")
    assert_receive {:native_request, ^label, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert :ok = Session.cancel_draft(pid)
    assert :ok = Session.prompt(pid, "ordinary")
    assert_receive {:native_request, ^label, input, _}, 5_000

    for canary <- [
          "native private draft",
          "native draft answer canary",
          "encrypted native canary",
          "draft-model-canary"
        ],
        do: refute(inspect(input) =~ canary)

    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.dir, id)
    assert {:ok, %{historical_model: nil}} = Session.Saved.restore(events, id)

    forged =
      Enum.map(events, fn event ->
        if event["type"] == "draft_started",
          do: Map.put(event, "prior_reported_model", "draft-model-canary"),
          else: event
      end)

    assert {:error, _} = Session.Saved.restore(forged, id)
    {resumed, resumed_label} = start(c, cfg, id)
    assert :ok = Session.prompt(resumed, "ordinary")
    assert_receive {:native_request, ^resumed_label, input, _}, 5_000
    refute inspect(input) =~ "draft-model-canary"
    refute inspect(input) =~ "encrypted native canary"
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 5_000
    assert :ok = Session.close_confirmed(resumed)

    c2 = %{c | dir: Path.join(c.root, "native-accepted")}
    {second, second_label} = start(c2, cfg)
    second_id = Session.info(second).id
    assert :ok = Session.start_draft(second, "another native private draft")
    assert_receive {:native_request, ^second_label, _, _}, 5_000
    assert_receive {:ipse, ^second, {:done, :ok}}, 5_000
    {:ok, %{id: draft_id, revision: 1}} = Session.draft(second)
    assert :ok = Session.replace_draft(second, draft_id, 1, "ordinary")
    {accepted, accepted_label} = synthetic_accepted_resume(c2, second, cfg)
    assert_receive {:native_request, ^accepted_label, accepted_input, _}, 5_000
    refute inspect(accepted_input) =~ "native draft answer canary"
    refute inspect(accepted_input) =~ "draft-model-canary"
    assert_receive {:ipse, ^accepted, {:done, :ok}}, 5_000
    assert :ok = Session.close_confirmed(accepted)
    {:ok, accepted_events} = Journal.load(c2.dir, second_id)

    assert {:ok, %{draft: %{status: :consumed}}} =
             Session.Saved.restore(accepted_events, second_id)
  end

  test "accepted intent binds tool evidence and withdraws its bytes", c do
    File.write!(Path.join(c.root, "evidence.txt"), "private evidence canary")
    {pid, label} = start(c, %{draft_read: true})
    id = Session.info(pid).id
    assert :ok = Session.start_draft(pid, "read evidence")
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert {:ok, %{id: draft_id, revision: 1}} = Session.draft(pid)
    assert :ok = Session.replace_draft(pid, draft_id, 1, "implement this request")
    {pid, label} = synthetic_accepted_resume(c, pid, %{draft_read: true})
    assert_receive {:request, ^label, _, _, accepted_input}, 5_000
    refute inspect(accepted_input) =~ "private evidence canary"
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.dir, id)
    accepted = Enum.find(events, &(&1["type"] == "draft_accepted"))
    assert [evidence] = accepted["tool_evidence"]
    assert is_map(evidence) and is_integer(evidence["byte_offset"])
    effect = Enum.find(events, &(&1["type"] == "draft_effect_intent" and &1["call_id"] == "w"))
    assert [%{"tool_evidence" => [^evidence]}] = effect["possible_source_lineages"]
    assert File.read!(Path.join(c.root, "forbidden")) == "bad"
    assert {:ok, _} = Session.Saved.restore(events, id)

    missing =
      Enum.reject(
        events,
        &(&1["type"] == "lifecycle_tool_outcome" and &1["status"] == "result_recorded")
      )

    assert {:error, _} = Session.Saved.restore(missing, id)

    forged =
      Enum.map(events, fn event ->
        if event["type"] == "draft_accepted", do: Map.put(event, "tool_evidence", []), else: event
      end)

    assert {:error, _} = Session.Saved.restore(forged, id)
  end

  test "a failed draft read is not asserted as successful evidence", c do
    {pid, label} = start(c, %{draft_read: true})
    id = Session.info(pid).id
    assert :ok = Session.start_draft(pid, "try the missing evidence")
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    {:ok, %{id: draft_id, revision: 1}} = Session.draft(pid)
    assert :ok = Session.replace_draft(pid, draft_id, 1, "ordinary")
    {pid, label} = synthetic_accepted_resume(c, pid, %{draft_read: true})
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.dir, id)
    accepted = Enum.find(events, &(&1["type"] == "draft_accepted"))
    assert accepted["tool_evidence"] == []

    assert Enum.any?(
             events,
             &(get_in(&1, ["message", "tool_call_id"]) == "read-evidence" and
                 get_in(&1, ["message", "ipse_tool_outcome", "status"]) == "error")
           )

    assert {:ok, _} = Session.Saved.restore(events, id)
  end

  test "a successful read without recorded lifecycle evidence cannot be accepted", c do
    File.write!(Path.join(c.root, "evidence.txt"), "legacy read")

    {:ok, id} =
      Journal.create(c.dir, %{"cwd" => c.root, "provider" => "demo", "model" => "fixture"})

    {pid, label} = start(c, %{draft_read: true}, id)
    assert :ok = Session.start_draft(pid, "read evidence")
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    state = :sys.get_state(pid)
    assert state.draft.tool_success_count == 1
    assert state.draft.tool_evidence == []

    refute Ipse.Session.Draft.withdrawable?(
             state.draft,
             state.messages,
             state.reference_occurrences
           )

    assert :ok = Session.cancel_draft(pid)
  end

  test "pending draft question resumes under its temporary ceiling without unwitnessed answers",
       c do
    config = %{
      provider_module: QuestionModel,
      operator_questions: true,
      enclosing_mode: :read_only
    }

    {pid, label} = start(c, config)
    id = Session.info(pid).id
    assert :ok = Session.start_draft(pid, "private requirement")
    assert_receive {:question_model, ^label}, 5_000
    assert_receive {:ipse, ^pid, {:question, "draft-q", _}}, 5_000
    upper = File.stat!(Path.join(c.dir, id <> ".jsonl")).size
    assert {:error, :pending_draft_history} = Ipse.Session.DraftHistory.withheld(c.dir, id, upper)

    assert {:error, :native_draft_answer_required} =
             Session.answer(pid, "draft-q", %{"detail" => "unverified"})

    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 5_000
    {resumed, _} = start(c, config, id)
    assert :sys.get_state(resumed).config.execution_mode == :draft
    assert :sys.get_state(resumed).config.enclosing_mode == "read_only"

    assert {:error, :native_draft_answer_required} =
             Session.answer(resumed, "draft-q", %{"detail" => "unverified"})

    assert :ok = Session.cancel_draft(resumed)
  end

  test "rebased draft stays absent from actual compaction and replay", c do
    {pid, label} =
      start(c, %{compact: true, context_bytes: 60_000, compact_threshold_bytes: 20_000})

    id = Session.info(pid).id
    assert :ok = Session.start_draft(pid, "compaction-secret-canary")
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert :ok = Session.cancel_draft(pid)
    assert :ok = Session.rebase_draft(pid)
    assert :ok = Session.refresh_context(pid)
    assert_receive {:ipse, ^pid, {:context_refreshed, _}}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000

    for n <- 1..10 do
      assert :ok = Session.prompt(pid, "history:#{n}")

      collect = fn collect ->
        receive do
          {:request, ^label, _, _, messages} ->
            refute inspect(messages) =~ "compaction-secret-canary"
            refute inspect(messages) =~ "draft-only canary"
            collect.(collect)

          {:ipse, ^pid, {:done, :ok}} ->
            :ok

          {:ipse, ^pid, {:error, reason}} ->
            flunk("compaction error: #{inspect(reason)}")

          {:ipse, ^pid, {:done, :error}} ->
            flunk("compaction failed")

          _ ->
            collect.(collect)
        after
          5_000 -> flunk("turn did not finish")
        end
      end

      collect.(collect)
    end

    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.dir, id)
    assert Enum.any?(events, &(&1["type"] == "context_compacted"))
    assert Enum.any?(events, &(&1["type"] == "reference_refresh"))
    assert Enum.any?(events, &(&1["type"] == "reference_epoch"))
    assert {:ok, %{messages: messages}} = Session.Saved.restore(events, id)
    refute inspect(messages) =~ "compaction-secret-canary"
    refute inspect(messages) =~ "draft-only canary"

    {resumed, resumed_label} =
      start(c, %{compact: true, context_bytes: 60_000, compact_threshold_bytes: 20_000}, id)

    assert :ok = Session.prompt(resumed, "ordinary")
    assert_receive {:request, ^resumed_label, _, _, resumed_messages}, 5_000
    refute inspect(resumed_messages) =~ "compaction-secret-canary"
    refute inspect(resumed_messages) =~ "draft-only canary"
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 5_000
    assert {:ok, page} = Session.sources(resumed, "source.list", %{"limit" => 32})

    for row <- page["sources"] do
      assert {:ok, source} =
               Session.sources(resumed, "source.read", %{"handle" => row["read_handle"]})

      refute inspect(source) =~ "compaction-secret-canary"
      refute inspect(source) =~ "draft-only canary"
    end
  end

  test "accepted source lineage survives rebase, compaction and restart", c do
    cfg = %{compact: true, context_bytes: 60_000, compact_threshold_bytes: 20_000}
    {pid, label} = start(c, cfg)
    id = Session.info(pid).id
    assert :ok = Session.start_draft(pid, "inherited private requirement")
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    {:ok, %{id: draft_id, revision: 1}} = Session.draft(pid)
    assert :ok = Session.replace_draft(pid, draft_id, 1, "ordinary")
    {pid, label} = synthetic_accepted_resume(c, pid, cfg)
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert :ok = Session.rebase_draft(pid)

    for n <- 1..10 do
      assert :ok = Session.prompt(pid, "history:#{n}")

      collect = fn collect ->
        receive do
          {:request, ^label, _, _, messages} ->
            refute inspect(messages) =~ "inherited private requirement"
            collect.(collect)

          {:ipse, ^pid, {:done, :ok}} ->
            :ok

          {:ipse, ^pid, {:done, :error}} ->
            flunk("compaction failed")

          _ ->
            collect.(collect)
        after
          5_000 -> flunk("turn did not finish")
        end
      end

      collect.(collect)
    end

    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.dir, id)
    assert Enum.any?(events, &(&1["type"] == "context_compacted"))
    assert {:ok, %{draft: nil, draft_lineages: [_]}} = Session.Saved.restore(events, id)

    compaction_lineage =
      Enum.find(events, &(&1["type"] == "draft_inference_intent" and &1["phase"] == "compaction"))

    assert is_map(compaction_lineage) and
             length(compaction_lineage["possible_source_lineages"]) == 1

    missing = Enum.reject(events, &(&1 == compaction_lineage))
    assert {:error, _} = Session.Saved.restore(missing, id)

    altered =
      Enum.map(events, fn event ->
        if event == compaction_lineage,
          do: Map.put(event, "possible_source_lineages", []),
          else: event
      end)

    assert {:error, _} = Session.Saved.restore(altered, id)
    {resumed, resumed_label} = start(c, cfg, id)
    assert :ok = Session.prompt(resumed, "later unrelated task")
    assert_receive {:request, ^resumed_label, _, _, messages}, 5_000
    refute inspect(messages) =~ "inherited private requirement"
    assert_receive {:request, ^resumed_label, _, _, _}, 5_000
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 5_000
    assert :ok = Session.close_confirmed(resumed)
    {:ok, events} = Journal.load(c.dir, id)

    assert Enum.any?(
             events,
             &(&1["type"] == "draft_effect_intent" and &1["call_id"] == "w" and
                 length(&1["possible_source_lineages"]) == 1)
           )

    assert {:ok, %{draft_lineages: [_]}} = Session.Saved.restore(events, id)
  end

  test "multiple accepted draft lineages survive rebase and follow-up effects", c do
    {pid, label} = start(c)
    id = Session.info(pid).id

    {pid, _label} =
      Enum.reduce(["first private draft", "second private draft"], {pid, label}, fn text,
                                                                                    {owner,
                                                                                     current_label} ->
        assert :ok = Session.start_draft(owner, text)
        assert_receive {:request, ^current_label, _, _, _}, 5_000
        assert_receive {:request, ^current_label, _, _, _}, 5_000
        assert_receive {:ipse, ^owner, {:done, :ok}}, 5_000
        {:ok, %{id: draft_id, revision: revision}} = Session.draft(owner)
        assert :ok = Session.replace_draft(owner, draft_id, revision, "ordinary")
        {next, next_label} = synthetic_accepted_resume(c, owner)
        assert_receive {:request, ^next_label, _, _, messages}, 5_000
        refute inspect(messages) =~ "first private draft"
        refute inspect(messages) =~ "second private draft"
        assert_receive {:ipse, ^next, {:done, :ok}}, 5_000
        {next, next_label}
      end)

    assert :ok = Session.rebase_draft(pid)
    assert :ok = Session.close_confirmed(pid)
    {resumed, resumed_label} = start(c, %{}, id)
    assert :ok = Session.prompt(resumed, "later unrelated task")
    assert_receive {:request, ^resumed_label, _, _, messages}, 5_000
    refute inspect(messages) =~ "first private draft"
    refute inspect(messages) =~ "second private draft"
    assert_receive {:request, ^resumed_label, _, _, _}, 5_000
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 5_000
    assert :ok = Session.close_confirmed(resumed)
    {:ok, events} = Journal.load(c.dir, id)
    effect = Enum.find(events, &(&1["type"] == "draft_effect_intent" and &1["call_id"] == "w"))
    assert length(effect["possible_source_lineages"]) == 2
    assert {:ok, %{draft_lineages: [_, _]}} = Session.Saved.restore(events, id)
  end

  test "cancelled later inference retains accepted lineage without replay", c do
    {pid, label} = start(c)
    id = Session.info(pid).id
    assert :ok = Session.start_draft(pid, "private prior draft")
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    {:ok, %{id: draft_id, revision: revision}} = Session.draft(pid)
    assert :ok = Session.replace_draft(pid, draft_id, revision, "ordinary")
    {pid, label} = synthetic_accepted_resume(c, pid)
    assert_receive {:request, ^label, _, _, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert :ok = Session.close_confirmed(pid)

    {held, held_label} = start(c, %{hold: true}, id)
    assert :ok = Session.prompt(held, "held continuation")
    assert_receive {:request, ^held_label, worker, _, held_input}, 5_000
    refute inspect(held_input) =~ "private prior draft"
    assert :ok = Session.cancel(held)
    refute Process.alive?(worker)
    assert_receive {:ipse, ^held, {:done, :cancelled}}, 5_000
    assert :ok = Session.close_confirmed(held)
    {resumed, resumed_label} = start(c, %{}, id)
    refute_receive {:request, ^resumed_label, _, _, _}, 100
    assert :ok = Session.prompt(resumed, "later unrelated task")
    assert_receive {:request, ^resumed_label, _, _, input}, 5_000
    refute inspect(input) =~ "private prior draft"
    assert_receive {:request, ^resumed_label, _, _, _}, 5_000
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 5_000
    assert :ok = Session.close_confirmed(resumed)
    {:ok, events} = Journal.load(c.dir, id)
    assert {:ok, %{draft_lineages: [_]}} = Session.Saved.restore(events, id)
  end
end
