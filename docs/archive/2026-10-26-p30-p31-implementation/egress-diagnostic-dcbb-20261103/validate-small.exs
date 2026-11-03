# Offline validation of the first, fresh three-note diagnostic only.
[path] = System.argv()
events = path |> File.stream!() |> Enum.map(&Jason.decode!/1)
one = fn values ->
  case values do
    [value] -> value
    _ -> raise "diagnostic is inconclusive: expected exactly one matching event"
  end
end
where = fn kind, field, value -> Enum.filter(events, &(&1["kind"] == kind and &1[field] == value)) end
mark = fn stage -> where.("mark", "stage", stage) |> one.() end
listener = fn name -> where.("listener", "event", name) |> one.() end
barrier = fn stage -> where.("producer_barrier", "stage", stage) |> one.() end
summary = where.("summary", "closure", "finish_received") |> one.()
true = summary["dropped"] == 0
subject = mark.("subject")
gate_start = mark.("gate_enter")
gate_end = mark.("gate_result")
send_start = mark.("send_enter")
send_end = mark.("send_result")
gate_barrier = barrier.("gate")
send_barrier = barrier.("send")
transport_barrier = barrier.("transport")
true = is_binary(subject["owner_pid"])
true = is_binary(gate_start["job"])
for event <- [gate_start, gate_end, send_start, send_end] do
  true = event["owner_pid"] == subject["owner_pid"] and event["job"] == gate_start["job"]
end
true = gate_start["pid"] == gate_end["pid"] and gate_end["pid"] == gate_barrier["pid"]
true = send_start["pid"] == send_end["pid"] and send_end["pid"] == send_barrier["pid"] and send_end["pid"] == transport_barrier["pid"]
true = gate_end["class"] == "ok" and send_end["class"] == "ok"
true = gate_start["at"] <= gate_end["at"] and gate_end["at"] <= gate_barrier["at"]
true = send_start["at"] <= send_end["at"] and send_end["at"] <= send_barrier["at"]
for stage <- ~w(transport_connect transport_connected transport_admit transport_admit_result transport_state_sent transport_request transport_request_ok) do
  event = mark.(stage)
  true = event["pid"] == send_start["pid"]
end
connect = mark.("transport_connect")
connected = mark.("transport_connected")
admit = mark.("transport_admit")
request = mark.("transport_request")
request_ok = mark.("transport_request_ok")
true = gate_end["at"] <= connect["at"] and connect["at"] <= connected["at"] and connected["at"] <= admit["at"]
true = admit["at"] <= send_start["at"] and send_start["at"] <= request["at"] and request["at"] <= request_ok["at"] and request_ok["at"] <= send_end["at"]
true = mark.("transport_admit_result")["class"] == "ok"
true = send_end["at"] <= mark.("transport_admit_result")["at"] and mark.("transport_admit_result")["at"] <= mark.("transport_state_sent")["at"] and mark.("transport_state_sent")["at"] <= transport_barrier["at"]
current = Enum.filter(where.("mark", "stage", "current_enter"), &(&1["pid"] == send_start["pid"] and &1["owner_pid"] == subject["owner_pid"] and &1["job"] == gate_start["job"] and &1["at"] >= send_start["at"] and &1["at"] <= send_end["at"])) |> one.()
current_result = Enum.filter(where.("mark", "stage", "current_result"), &(&1["pid"] == send_start["pid"] and &1["owner_pid"] == subject["owner_pid"] and &1["job"] == gate_start["job"] and &1["at"] >= current["at"] and &1["at"] <= send_end["at"])) |> one.()
true = current_result["class"] == "ok"
accepted = listener.("accepted")
initial = listener.("initial_read")
body = listener.("request_body")
true = accepted["pid"] == initial["pid"] and initial["pid"] == body["pid"]
true = initial["bytes"] > 0 and body["bytes"] > 0
true = accepted["at"] <= initial["at"] and initial["at"] <= body["at"]
IO.puts("small diagnostic: one owner/job; gate and send barriers; matched transport PID; listener bytes observed; no dropped marks")
