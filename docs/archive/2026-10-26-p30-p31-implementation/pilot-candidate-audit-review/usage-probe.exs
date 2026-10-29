Code.require_file("dev/knowledge/pilot.exs")
alias Ipse.Development.Knowledge.Pilot
marker = "PRIVATE_SYNTHETIC_USAGE_CONTENT"
owner = self()

for provider <- [:chatgpt, :ollama],
    raw <- [
      %{"input_tokens" => 5, "output_tokens" => 2, "total_tokens" => 7, "provider_duration_ns" => 123, "attribution" => %{"items" => [%{"content" => [marker]}]}},
      %{"input_tokens" => %{"content" => marker}, "output_tokens" => 2, "attribution" => marker}
    ] do
  request = fn _, messages, _, _ ->
    last = List.last(messages)
    cond do
      last["role"] == "tool" -> {:ok, %{"role" => "assistant", "content" => "synthetic continuation"}, raw}
      JSON.decode!(last["content"])["source_id"] == "pilot-1" ->
        {:ok, %{"role" => "assistant", "tool_calls" => [%{"id" => "usage-probe", "type" => "function", "function" => %{"name" => "knowledge_capture", "arguments" => ~s({"items":[]})}}]}, raw}
      true -> {:error, :synthetic_stop}
    end
  end
  {:error, :provider_request_failed, [first, second] = records, 3} = Pilot.run(%{provider: provider}, request, fn row -> send(owner, {:progress, row}) end)
  false = first.continuation
  true = second.continuation
  for record <- records do
    true = Ipse.Usage.valid_usage?(record.usage)
    false = String.contains?(inspect(record), marker)
    false = Map.has_key?(record.usage, "attribution")
    receive do
      {:progress, ^record} -> :ok
    after
      1000 -> raise "missing synthetic progress"
    end
  end
  if is_integer(raw["input_tokens"]) do
    5 = first.usage["counts"]["input_tokens"]
    2 = first.usage["counts"]["output_tokens"]
    7 = first.usage["counts"]["total_tokens"]
  else
    "invalid" = first.usage["quality"]
  end
  IO.inspect(%{provider: provider, records: 2, attempted_requests: 3, valid_counters: is_integer(raw["input_tokens"]), raw_content_exposed: false}, label: "PILOT_USAGE_REVIEW_OK")
end
