alias Ipse.{JSON, Session.Saved}
alias Ipse.Extension.Mode
session = String.duplicate("a", 32)
{:ok, planning} = Mode.capture(%{approval: :ask, execution_mode: :planning})
marker = %{"version" => 1, "origin" => "cli_flag", "session_id" => session, "mode_sha256" => JSON.digest([planning])}
header = %{"metadata" => %{"execution_mode" => planning, "planning_local_start" => marker}}
exit_event = %{"type" => "planning_exited", "mode" => Map.put(planning, "ceiling", "normal")}
{:ok, ^planning} = Saved.execution_mode([header, exit_event], session)
:deny = Mode.ordinary(planning, true)
IO.puts("OLD_READER_RETAINS_STARTUP_PLANNING")
