ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
root = hd(System.argv())

defmodule OperatorCliProvider do
  def complete(_, messages, _, _) do
    if Enum.any?(messages, &(&1["role"] == "tool" and &1["tool_call_id"] == "native_question")) do
      {:ok, %{"role" => "assistant", "content" => "Synthetic native answer committed."}, %{}}
    else
      args = %{
        "questions" => [
          %{
            "id" => "choice",
            "kind" => "single",
            "prompt" => "Synthetic native choice",
            "options" => [%{"id" => "a", "label" => "A"}, %{"id" => "b", "label" => "B"}]
          },
          %{"id" => "text", "kind" => "text", "prompt" => "Synthetic native literal answer"}
        ]
      }

      {:ok,
       %{
         "role" => "assistant",
         "content" => "",
         "tool_calls" => [
           %{
             "id" => "native_question",
             "type" => "function",
             "function" => %{
               "name" => "ask_operator",
               "arguments" => Jason.encode!(args)
             }
           }
         ]
       }, %{}}
    end
  end
end

{:ok, session} =
  Ipse.Session.start_link(
    config: %{
      provider: :demo,
      model: "synthetic",
      provider_module: OperatorCliProvider,
      home: Path.join(root, "home"),
      approval: :ask,
      operator_questions: true
    },
    cwd: root,
    state_dir: Path.join(root, "state"),
    subscriber: self()
  )

id = Ipse.Session.info(session).id
monitor = Process.monitor(session)
assert 0 == Ipse.CLI.Terminal.interact(session, monitor, true, nil, root)
{:ok, events} = Ipse.Journal.load(Path.join(root, "state"), id)
input = Enum.find(events, &(&1["type"] == "input_received"))
assert input["version"] === 2
assert input["origin"] == "interactive_operator"
assert input["text"] == "  synthetic café original  "
assert input["observation"]["version"] === 2
assert :ok = Ipse.Session.Input.validate_events(events, id)
answer = Enum.find(events, &(&1["type"] == "operator_answer"))
assert answer["version"] === 2
assert answer["origin"]["origin"] == "native_operator_answer"
assert length(answer["origin"]["pieces"]) == 2
assert Enum.at(answer["origin"]["pieces"], 1)["text"] == "=/exit 雪 café  "

assert Jason.decode!(answer["message"]["content"])["answers"] == %{
         "choice" => "b",
         "text" => "/exit 雪 café  "
       }

assert :ok = Ipse.Session.OperatorAnswer.validate_events(events, id)
assert {:ok, _} = Ipse.Session.Saved.restore(events, id)

list_sources = fn list_sources, cursor, rows ->
  assert {:ok, page} =
           Ipse.Session.sources(session, "source.list", %{"limit" => 32, "cursor" => cursor})

  assert byte_size(Jason.encode!(page)) <= 4096

  if page["next"],
    do: list_sources.(list_sources, page["next"], rows ++ page["sources"]),
    else: rows ++ page["sources"]
end

sources = list_sources.(list_sources, nil, [])
assert Enum.count(sources, &(&1["origin"] == "native_operator_answer")) == 2
assert Enum.count(sources, &(&1["kind"] == "operator.question")) == 2
original = Enum.find(sources, &(&1["kind"] == "input.original"))
assert original["origin"] == "interactive_operator"

assert {:ok, original_page} =
         Ipse.Session.sources(session, "source.read", %{"handle" => original["read_handle"]})

assert original_page["text"] == input["text"]

answer_pages =
  for source <- sources, source["origin"] == "native_operator_answer" do
    assert {:ok, page} =
             Ipse.Session.sources(session, "source.read", %{"handle" => source["read_handle"]})

    page
  end

assert Enum.any?(answer_pages, &(&1["text"] == "=/exit 雪 café  "))

refute Enum.any?(events, &(&1["type"] == "tool_started" and &1["name"] != "ask_operator"))
assert :ok = Ipse.Session.close_confirmed(session)
IO.puts("OPERATOR_CLI_CHECKS_PASSED")
