# Run with MIX_ENV=test mix run dev/measure-session-startup.exs.
# Synthetic legacy histories exercise startup without inference or tool effects.
alias Ipse.Session
alias Ipse.Journal
root = Path.join(System.tmp_dir!(), "ipse-startup-measure-#{Ipse.Usage.id()}")
File.mkdir_p!(root)
config = %{provider: :demo, model: "measure", approval: :ask, home: Path.join(root, "home")}
dir = Path.join(root, "sessions")

{:ok, fresh} =
  DynamicSupervisor.start_child(
    Ipse.Sessions,
    {Session, config: config, cwd: root, state_dir: dir, subscriber: self()}
  )

fresh_id = Session.info(fresh).id
:ok = Session.close(fresh)
{:ok, [header | _]} = Journal.load(dir, fresh_id)
metadata = Map.delete(header["metadata"], "usage_version")

args = %{
  "questions" => [
    %{
      "id" => "choice",
      "kind" => "single",
      "prompt" => "Synthetic choice",
      "options" => [%{"id" => "one", "label" => "One"}, %{"id" => "two", "label" => "Two"}]
    }
  ]
}

try do
  for {megabytes, questions} <- [{8, 50}, {32, 100}, {64, 200}] do
    {:ok, id} = Journal.create(dir, metadata)
    path = Path.join(dir, id <> ".jsonl")
    block = String.duplicate("x", div(megabytes * 1_048_576, questions))
    {:ok, file} = File.open(path, [:append, :binary])

    Enum.reduce(1..questions, [], fn n, messages ->
      call = %{
        "id" => "q#{n}",
        "function" => %{"name" => "ask_operator", "arguments" => Jason.encode!(args)}
      }

      user = %{"role" => "user", "content" => block}
      assistant = %{"role" => "assistant", "content" => "", "tool_calls" => [call]}
      messages = messages ++ [user, assistant]

      checkpoint = %{
        "type" => "operator_question",
        "version" => 1,
        "id" => call["id"],
        "call" => call,
        "arguments" => args,
        "steps" => 1,
        "covered_messages" => length(messages),
        "prefix_sha256" => Ipse.JSON.digest(messages)
      }

      answer = %{
        "role" => "tool",
        "tool_call_id" => call["id"],
        "content" =>
          Jason.encode!(%{
            "answers" => %{"choice" => "one"},
            "notice" => "Clarification only; no action permission."
          }),
        "ipse_tool_outcome" => %{"status" => "result_recorded", "approval" => "not_required"}
      }

      for event <- [
            %{"type" => "message", "message" => user},
            %{"type" => "message", "message" => assistant},
            checkpoint,
            %{
              "type" => "operator_answer",
              "version" => 1,
              "id" => call["id"],
              "message" => answer
            }
          ] do
        :ok = IO.binwrite(file, [Jason.encode!(event), "\n"])
      end

      messages ++ [answer]
    end)

    File.close(file)
    :erlang.garbage_collect()

    {microseconds, result} =
      :timer.tc(fn ->
        DynamicSupervisor.start_child(
          Ipse.Sessions,
          {Session, config: config, cwd: root, state_dir: dir, id: id, subscriber: self()}
        )
      end)

    {:ok, session} = result
    :idle = Session.info(session).phase
    :ok = Session.close(session)

    IO.puts(
      Jason.encode!(%{
        megabytes: megabytes,
        bytes: File.stat!(path).size,
        historical_questions: questions,
        open_ms: Float.round(microseconds / 1000, 1)
      })
    )

    File.rm!(path)
  end
after
  File.rm_rf!(root)
end
