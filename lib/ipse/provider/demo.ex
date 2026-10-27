defmodule Ipse.Provider.Demo do
  @moduledoc "Deterministic fixture provider; never represents itself as a real model."

  def complete(_config, messages, _tools, emit) do
    turn =
      messages
      |> Enum.reject(&Ipse.Session.Reference.reference?/1)
      |> Enum.reverse()
      |> Enum.take_while(&(&1["role"] != "user"))
      |> Enum.reverse()

    results = Enum.filter(turn, &(&1["role"] == "tool"))

    case length(results) do
      0 ->
        call("demo-skill", "load_skill", %{"name" => "review"})

      1 ->
        call("demo-resource", "load_skill_resource", %{
          "name" => "review",
          "path" => "references/checklist.md"
        })

      2 ->
        call("demo-write", "write", %{
          "path" => "ipse-demo.txt",
          "content" => "Hello from Ipse!\n"
        })

      3 ->
        call("demo-read", "read", %{"path" => "ipse-demo.txt"})

      4 ->
        call("demo-shell", "shell", %{"command" => "printf 'Runner works\\n'"})

      _ ->
        text =
          "Demo finished. I requested a skill and its checklist resource, wrote and read ipse-demo.txt, and ran a command. Inspect the tool results for approvals or failures. This is a scripted demo, not an AI response."

        emit.({:text, text})
        {:ok, %{"role" => "assistant", "content" => text}, %{}}
    end
  end

  defp call(id, name, args) do
    {:ok,
     %{
       "role" => "assistant",
       "content" => "",
       "tool_calls" => [
         %{
           "id" => id,
           "type" => "function",
           "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
         }
       ]
     }, %{}}
  end
end
