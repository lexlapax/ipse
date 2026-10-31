alias Ipse.{JSON, Session.Saved}
alias Ipse.Extension.Mode
session = String.duplicate("a", 32)
{:ok, normal} = Mode.capture(%{approval: :ask})
planning = Map.put(normal, "ceiling", "planning")
header = %{"metadata" => %{"execution_mode" => normal}}
checkpoint = %{"type" => "execution_mode_resumed", "version" => 2, "session_id" => session, "previous_sha256" => JSON.digest([normal]), "mode" => planning}
entry = %{"type" => "planning_entry_observed"}
exit_event = %{"type" => "planning_exited", "mode" => normal}
{:ok, ^planning} = Saved.execution_mode([header, checkpoint, entry, exit_event], session)
:deny = Mode.ordinary(planning, true)
reads = %{"mcp__notes__lookup" => %{"version" => 1, "server_id" => "notes", "tool" => "lookup", "endpoint_sha256" => JSON.sha256("endpoint"), "descriptor_sha256" => JSON.sha256("descriptor")}}
header = %{"metadata" => %{"execution_mode" => normal, "planning_mcp_protocol" => 1, "configuration" => %{"planning_mcp_reads" => reads}}}
first = Ipse.Session.PlanningMCP.epoch(session, String.duplicate("1", 32), nil, "fresh", normal, reads)
second = Ipse.Session.PlanningMCP.epoch(session, String.duplicate("2", 32), first["epoch_id"], "resume", planning, reads)
third = Ipse.Session.PlanningMCP.epoch(session, String.duplicate("3", 32), second["epoch_id"], "resume", normal, reads)
{:error, :invalid_planning_mcp_history} = Ipse.Session.PlanningMCP.validate_events([header, first, checkpoint, second, entry, exit_event, third], session)
IO.puts("OLD_READER_RETAINS_PLANNING")
