# Offline analysis of redacted diagnostic markers; no recorded request content.
[path] = System.argv()
try do
  events = path |> File.stream!() |> Enum.map(&Jason.decode!/1)
  one = fn values -> case values do [value] -> value; _ -> raise "inconclusive" end end
  get = fn kind, field, value -> Enum.filter(events, &(&1["kind"] == kind and &1[field] == value)) end
  mark = fn stage -> get.("mark", "stage", stage) |> one.() end
  barrier = fn stage -> get.("producer_barrier", "stage", stage) |> one.() end
  summary = get.("summary", "closure", "finish_received") |> one.()
  true = summary["dropped"] == 0
  true = List.last(events) == summary and summary["events"] == length(events) - 1
  subject = mark.("subject")
  gate_start = mark.("gate_enter")
  gate_end = mark.("gate_result")
  gate_barrier = barrier.("gate")
  send_start = mark.("send_enter")
  send_end = mark.("send_result")
  send_barrier = barrier.("send")
  transport_barrier = barrier.("transport")
  true = is_binary(subject["owner_pid"]) and is_binary(gate_start["job"])
  for event <- [gate_start, gate_end, send_start, send_end] do
    true = event["owner_pid"] == subject["owner_pid"] and event["job"] == gate_start["job"]
  end
  true = gate_start["pid"] == gate_end["pid"] and gate_end["pid"] == gate_barrier["pid"]
  true = send_start["pid"] == send_end["pid"] and send_end["pid"] == send_barrier["pid"] and send_end["pid"] == transport_barrier["pid"]
  true = gate_end["class"] == "ok" and gate_start["at"] <= gate_end["at"] and gate_end["at"] <= gate_barrier["at"]
  true = send_start["at"] <= send_end["at"] and send_end["at"] <= send_barrier["at"]
  connect = mark.("transport_connect")
  connected = mark.("transport_connected")
  admit = mark.("transport_admit")
  admit_result = mark.("transport_admit_result")
  for event <- [connect, connected, admit, admit_result] do
    true = event["pid"] == send_start["pid"]
  end
  true = gate_end["at"] <= connect["at"] and connect["at"] <= connected["at"] and connected["at"] <= admit["at"]
  true = admit["at"] <= send_start["at"] and send_end["at"] <= admit_result["at"] and admit_result["at"] <= transport_barrier["at"]
  current_start = Enum.filter(get.("mark", "stage", "current_enter"), &(&1["pid"] == send_start["pid"] and &1["owner_pid"] == subject["owner_pid"] and &1["job"] == gate_start["job"] and &1["at"] >= send_start["at"] and &1["at"] <= send_end["at"])) |> one.()
  current_end = Enum.filter(events, &(&1["kind"] == "mark" and &1["stage"] in ["current_result", "current_exception"] and &1["pid"] == send_start["pid"] and &1["owner_pid"] == subject["owner_pid"] and &1["job"] == gate_start["job"] and &1["at"] >= current_start["at"] and &1["at"] <= send_end["at"])) |> one.()
  states = Enum.filter(events, &(&1["kind"] == "mark" and &1["stage"] in ~w(transport_state_pending transport_state_refused transport_state_sent transport_state_other)))
  state = one.(states)
  true = state["pid"] == send_start["pid"] and admit_result["at"] <= state["at"] and state["at"] <= transport_barrier["at"]
  accepted = get.("listener", "event", "accepted") |> one.()
  terminals = Enum.filter(events, &(&1["kind"] == "listener" and &1["event"] in ["closed", "request_body"]))
  terminal = one.(terminals)
  true = accepted["pid"] == terminal["pid"] and accepted["at"] <= terminal["at"]
  result = case state["stage"] do
    "transport_state_refused" ->
      refused = mark.("transport_deadline_refused")
      true = refused["pid"] == send_start["pid"] and refused["at"] >= current_start["at"] and refused["at"] <= send_end["at"]
      true = terminal["event"] == "closed"
      "explicit_transport_deadline_branch"
    "transport_state_pending" ->
      true = terminal["event"] == "closed"
      "callback_finished_without_owner_send_progress"
    "transport_state_sent" ->
      requested = mark.("transport_request")
      request_ok = mark.("transport_request_ok")
      true = requested["pid"] == send_start["pid"] and request_ok["pid"] == send_start["pid"]
      true = requested["at"] <= request_ok["at"] and request_ok["at"] <= send_end["at"]
      true = terminal["event"] == "request_body" and terminal["bytes"] > 0
      "local_send_returned_and_listener_received_body"
    "transport_state_other" ->
      local_error = mark.("transport_request_error")
      true = local_error["pid"] == send_start["pid"] and local_error["at"] <= send_end["at"]
      true = terminal["event"] == "closed"
      "local_send_error"
  end
  micros = fn start, stop -> System.convert_time_unit(stop - start, :native, :microsecond) end
  IO.puts("classification=" <> result)
  IO.puts("gate_elapsed_us=" <> Integer.to_string(micros.(gate_start["at"], gate_end["at"])))
  IO.puts("current_elapsed_us=" <> Integer.to_string(micros.(current_start["at"], current_end["at"])))
  IO.puts("connect_elapsed_us=" <> Integer.to_string(micros.(connect["at"], connected["at"])))
  IO.puts("send_elapsed_us=" <> Integer.to_string(micros.(send_start["at"], send_end["at"])))
  IO.puts("listener_terminal=" <> terminal["event"])
  IO.puts("listener_terminal_bytes=" <> Integer.to_string(terminal["bytes"]))
  IO.puts("admit_result_class=" <> (admit_result["class"] || "none"))
  IO.puts("current_result_class=" <> (current_end["class"] || current_end["stage"]))
  IO.puts("instrumented_timings_only=true")
rescue
  _ ->
    IO.puts("classification=inconclusive")
    System.halt(2)
catch
  _, _ ->
    IO.puts("classification=inconclusive")
    System.halt(2)
end
