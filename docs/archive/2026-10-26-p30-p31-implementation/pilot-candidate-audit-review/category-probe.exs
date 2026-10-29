Code.require_file("dev/knowledge/pilot.exs")
alias Ipse.Development.Knowledge.Pilot
owner = self()
marker = "PRIVATE_SYNTHETIC_CANDIDATE_IN_INVALID_CATEGORY"
request = fn _, messages, _, _ ->
  source = JSON.decode!(List.last(messages)["content"])
  args = %{"items" => [%{"source_id" => source["source_id"], "quote" => source["text"], "text" => "bounded candidate", "category" => marker}]}
  {:ok, %{"role" => "assistant", "tool_calls" => [%{"id" => "category-probe", "type" => "function", "function" => %{"name" => "knowledge_capture", "arguments" => JSON.encode!(args)}}]}, %{}}
end
{:error, :pilot_call_contract_refused, records, 1} = Pilot.run(%{provider: :chatgpt}, request, fn r -> send(owner, {:progress, r}) end)
receive do
  {:progress, progress} -> IO.inspect(%{audit_enabled: false, raw_invalid_category_in_progress: String.contains?(inspect(progress), marker), raw_invalid_category_in_records: String.contains?(inspect(records), marker)}, label: "PILOT_PROGRESS_CATEGORY_COUNTEREXAMPLE")
after
  1000 -> raise "missing progress"
end
