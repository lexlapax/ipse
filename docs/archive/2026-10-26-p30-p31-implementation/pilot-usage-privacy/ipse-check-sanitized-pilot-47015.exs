Path.wildcard("_build/literal-v4-ab-current2-sol-20261029/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
path = "docs/archive/2026-10-26-p30-p31-implementation/pilot-usage-privacy/sanitized-partial-receipt.json"
bytes = File.read!(path)
true = byte_size(bytes) <= 1_048_576
data = Jason.decode!(bytes)
true = data["status"] == "incomplete_unknown_termination"
true = length(data["progress"]) == 96
Enum.each(data["progress"], fn row ->
  true = row["source"] in Enum.map(1..20, &("pilot-" <> to_string(&1)))
  true = row["session"] in 1..3
  true = row["published"] == 0
  true = row["disposition"] in [nil, "ok"]
  true = Ipse.Usage.valid_usage?(row["usage"])
  Enum.each(row["proposals"] || [], fn proposal ->
    true = Enum.sort(Map.keys(proposal)) == ~w(category payload_bytes valid_source)
    true = proposal["category"] in ~w(automatic persistent temporal)
    true = proposal["valid_source"] == true
    true = is_integer(proposal["payload_bytes"]) and proposal["payload_bytes"] in 1..8192
  end)
end)
check = fn check, value ->
  cond do
    is_map(value) ->
      true = Enum.all?(Map.keys(value), &(&1 not in ~w(attribution content quote text api_key authorization)))
      Enum.each(Map.values(value), &check.(check, &1))
    is_list(value) -> Enum.each(value, &check.(check, &1))
    true -> :ok
  end
end
check.(check, data)
IO.puts("SANITIZED_PARTIAL_PILOT_OK responses=96 usage=closed no_content_fields=true incomplete=true")
