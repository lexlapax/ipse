ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
root = hd(System.argv())

defmodule OperatorEOFProvider do
  def complete(config, messages, _, _) do
    native = Enum.reject(messages, &Ipse.Session.Reference.reference?/1)
    text = List.last(native)["content"]
    if text == "first café original", do: await_release(config.fixture_root, 2000)

    call = %{
      "id" => Ipse.Usage.id(),
      "type" => "function",
      "function" => %{
        "name" => "ask_operator",
        "arguments" =>
          Jason.encode!(%{
            "questions" => [
              %{"id" => "detail", "kind" => "text", "prompt" => "Synthetic EOF question"}
            ]
          })
      }
    }

    {:ok, %{"role" => "assistant", "content" => "", "tool_calls" => [call]}, %{}}
  end

  defp await_release(_, 0), do: raise("synthetic queue was not staged")

  defp await_release(root, remaining) do
    if File.exists?(Path.join(root, "release-model")),
      do: :ok,
      else:
        (
          Process.sleep(5)
          await_release(root, remaining - 1)
        )
  end
end

{:ok, session} =
  Ipse.Session.start_link(
    config: %{
      provider: :demo,
      model: "synthetic",
      provider_module: OperatorEOFProvider,
      fixture_root: root,
      home: Path.join(root, "home"),
      approval: :ask,
      operator_questions: true
    },
    cwd: root,
    state_dir: Path.join(root, "state"),
    subscriber: self()
  )

id = Ipse.Session.info(session).id
assert 0 == Ipse.CLI.Terminal.interact(session, Process.monitor(session), true, nil, root)
assert Ipse.Session.info(session).phase == :idle
{:ok, events} = Ipse.Journal.load(Path.join(root, "state"), id)
inputs = Enum.filter(events, &(&1["type"] == "input_received"))
expected = ["first café original", "queued 雪 one", "queued café two"]
assert Enum.map(inputs, & &1["text"]) == expected
assert Enum.all?(inputs, &(&1["origin"] == "interactive_operator" and &1["version"] === 2))
assert Enum.count(events, &(&1["type"] == "operator_question")) == 3
refute Enum.any?(events, &(&1["type"] == "operator_answer"))
assert :ok = Ipse.Session.Input.validate_events(events, id)
assert {:ok, saved} = Ipse.Session.Saved.restore(events, id)
assert saved.question == nil

list = fn list, cursor, rows ->
  assert {:ok, page} =
           Ipse.Session.sources(session, "source.list", %{"limit" => 32, "cursor" => cursor})

  if page["next"],
    do: list.(list, page["next"], rows ++ page["sources"]),
    else: rows ++ page["sources"]
end

sources = list.(list, nil, [])

assert Enum.count(
         sources,
         &(&1["kind"] == "input.original" and &1["origin"] == "interactive_operator")
       ) == 3

refute Enum.any?(sources, &(&1["origin"] == "native_operator_answer"))

texts =
  Enum.map(sources, fn source ->
    assert {:ok, page} =
             Ipse.Session.sources(session, "source.read", %{"handle" => source["read_handle"]})

    page["text"]
  end)

assert texts == expected
assert :ok = Ipse.Session.close_confirmed(session)
IO.puts("OPERATOR_QUEUED_EOF_CHECKS_PASSED")
