[root] = System.argv()
intent = root |> Path.join("recall-one-shot-intent.json") |> File.read!() |> :json.decode()
id = intent["session_id"]
true = is_binary(id) and Regex.match?(~r/\A[a-f0-9]{32}\z/, id)
events = Path.join([root, "home", "sessions", id <> ".jsonl"]) |> File.stream!() |> Enum.map(&:json.decode/1)
allowed = ~w(ok error failed unknown partial complete final model text provider)
safe = fn x -> if is_binary(x) and x in allowed, do: x, else: if(is_nil(x), do: nil, else: "other") end
for e <- events, e["type"] in ~w(request_measured request_finished turn_finished) do
  IO.puts(:json.encode(%{"type" => e["type"], "duration_ms" => e["duration_ms"], "outcome" => safe.(e["outcome"]), "finality" => safe.(e["finality"]), "kind" => safe.(e["kind"]), "status" => safe.(e["status"])}))
end
