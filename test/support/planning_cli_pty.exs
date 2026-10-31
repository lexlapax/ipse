ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
root = List.last(System.argv())
startup = "startup" in System.argv()

config = %{provider: :demo, model: "synthetic", home: Path.join(root, "home"), approval: :ask}

config =
  if startup,
    do: Map.merge(config, %{execution_mode: :planning, planning_cli_start: true}),
    else: config

{:ok, session} =
  Ipse.Session.start_link(
    config: config,
    cwd: root,
    state_dir: Path.join(root, "state"),
    subscriber: self()
  )

id = Ipse.Session.info(session).id
monitor = Process.monitor(session)
assert 0 == Ipse.CLI.Terminal.interact(session, monitor, true, nil, root)
assert Ipse.Session.info(session).execution_mode["ceiling"] == "normal"
assert :ok = Ipse.Session.close_confirmed(session)
assert {:ok, events} = Ipse.Journal.load(Path.join(root, "state"), id)
assert {:ok, _} = Ipse.Session.Saved.restore(events, id)

if startup do
  assert hd(events)["metadata"]["planning_local_start"]["origin"] == "cli_flag"
else
  assert [%{"observation" => observation}] =
           Enum.filter(events, &(&1["type"] == "planning_entry_observed"))

  assert Ipse.Session.Input.valid_observation?(observation, "/plan", 2)
end

assert [%{"observation" => exit_observation}] =
         Enum.filter(events, &(&1["type"] == "planning_exited"))

assert Ipse.Session.Input.valid_observation?(exit_observation, "/plan exit", 2)
IO.puts("SYNTHETIC_PLANNING_ENTRY_PASSED")
