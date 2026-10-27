ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
root = List.last(System.argv())
multi = "multi" in System.argv()
question = "question" in System.argv()
cancel = "cancel" in System.argv()

original =
  if multi or question, do: "private initial request", else: "/enhance private initial request"

expected =
  cond do
    multi -> "first replacement line\nsecond replacement line"
    question -> "suggested request"
    true -> "accepted replacement"
  end

defmodule DraftCLIProvider do
  def complete(config, messages, _, _) do
    draft =
      Enum.any?(messages, fn m ->
        is_binary(m["content"]) and String.contains?(m["content"], "Draft a clearer version")
      end)

    answered =
      Enum.any?(messages, &(&1["role"] == "tool" and &1["tool_call_id"] == "draft-question-1"))

    effect_completed =
      Enum.any?(messages, &(&1["role"] == "tool" and &1["tool_call_id"] == "accepted-write"))

    cond do
      config[:draft_question] and draft and not answered ->
        args = %{
          "questions" => [%{"id" => "detail", "kind" => "text", "prompt" => "What detail?"}]
        }

        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "draft-question-1",
               "type" => "function",
               "function" => %{"name" => "ask_operator", "arguments" => Jason.encode!(args)}
             }
           ]
         }, %{}}

      config[:draft_question] and not draft and not effect_completed ->
        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "accepted-write",
               "type" => "function",
               "function" => %{
                 "name" => "write",
                 "arguments" =>
                   Jason.encode!(%{"path" => "question-effect.txt", "content" => "approved"})
               }
             }
           ]
         }, %{}}

      true ->
        {:ok, %{"role" => "assistant", "content" => "suggested request"}, %{}}
    end
  end
end

{:ok, session} =
  Ipse.Session.start_link(
    config: %{
      provider: :demo,
      model: "synthetic",
      provider_module: DraftCLIProvider,
      owner: self(),
      home: Path.join(root, "home"),
      approval: if(question, do: :allow, else: :deny),
      operator_questions: true,
      draft_question: question,
      compact: false
    },
    cwd: root,
    state_dir: Path.join(root, "state"),
    subscriber: self()
  )

id = Ipse.Session.info(session).id
monitor = Process.monitor(session)
assert 0 == Ipse.CLI.Terminal.interact(session, monitor, true, nil, root)
{:ok, events} = Ipse.Journal.load(Path.join(root, "state"), id)

assert Enum.any?(
         events,
         &(&1["type"] == "input_received" and &1["origin"] == "interactive_operator" and
             &1["text"] == original)
       )

input = Enum.find(events, &(&1["type"] == "input_received" and &1["text"] == original))
assert input["observation"]["text_sha256"] == Ipse.JSON.sha256(original)
assert input["effective_sha256"] == Ipse.JSON.sha256(Ipse.Session.Draft.effective(original))

assert Ipse.Session.Draft.effective(original) ==
         Ipse.Session.Draft.effective("private initial request")

if cancel do
  assert Enum.count(events, &(&1["type"] == "draft_started")) == 1
  refute Enum.any?(events, &(&1["type"] in ~w(draft_replaced draft_accepted draft_consumed)))
  assert Enum.any?(events, &(&1["type"] == "draft_cancelled"))
  assert %{draft: %{status: :cancelled, revision: 1}} = Ipse.Session.info(session)

  assert {:ok, %{draft: cancelled, messages: messages}} = Ipse.Session.Saved.restore(events, id)

  assert {:ok, projected} =
           Ipse.Session.Draft.project(
             cancelled,
             messages,
             Ipse.Session.Reference.occurrences(events)
           )

  refute inspect(projected) =~ "private initial request"
  assert Enum.any?(projected, &(&1["content"] == "ordinary before draft"))
  assert Enum.any?(projected, &(&1["content"] == "ordinary after cancellation"))
  assert :ok = Ipse.Session.close_confirmed(session)
  IO.puts("SYNTHETIC_ENHANCE_CANCEL_PASSED")
  System.halt(0)
end

if not question do
  assert Enum.any?(
           events,
           &(&1["type"] == "draft_replaced" and &1["version"] == if(multi, do: 3, else: 2) and
               &1["text"] == expected)
         )
end

assert Enum.any?(events, &(&1["type"] == "draft_accepted" and &1["version"] == 2))

if question do
  answer = Enum.find(events, &(&1["type"] == "operator_answer" and &1["version"] == 2))
  accepted = Enum.find(events, &(&1["type"] == "draft_accepted"))

  original =
    Enum.find(
      events,
      &(&1["type"] == "input_received" and &1["text"] == "private initial request")
    )

  assert accepted["question_ids"] == ["draft-question-1"]
  assert accepted["answer_source_ids"] == [answer["origin"]["source_id"]]
  assert accepted["input_source_id"] == original["source_id"]

  effect =
    Enum.find(
      events,
      &(&1["type"] == "draft_effect_intent" and &1["call_id"] == "accepted-write")
    )

  assert [lineage] = effect["possible_source_lineages"]
  assert lineage["question_ids"] == accepted["question_ids"]
  assert lineage["answer_source_ids"] == accepted["answer_source_ids"]
  assert lineage["input_source_id"] == accepted["input_source_id"]
  assert File.read!(Path.join(root, "question-effect.txt")) == "approved"

  forged =
    Enum.map(events, fn event ->
      if event == accepted, do: Map.put(event, "question_ids", []), else: event
    end)

  assert {:error, _} = Ipse.Session.Saved.restore(forged, id)
end

assert {:ok, %{draft: %{status: :consumed} = draft, messages: messages}} =
         Ipse.Session.Saved.restore(events, id)

assert {:ok, final} =
         Ipse.Session.Draft.project(draft, messages, Ipse.Session.Reference.occurrences(events))

assert Enum.any?(final, &(&1["content"] == expected))
refute inspect(final) =~ "private initial request"
refute inspect(final) =~ "private answer canary"
{:ok, page} = Ipse.Session.sources(session, "source.list", %{"limit" => 32})

for row <- page["sources"] do
  {:ok, source} = Ipse.Session.sources(session, "source.read", %{"handle" => row["read_handle"]})
  refute inspect(source) =~ "private initial request"
  refute inspect(source) =~ "private answer canary"
end

assert :ok = Ipse.Session.close_confirmed(session)
IO.puts("SYNTHETIC_DRAFT_CLI_PASSED")
