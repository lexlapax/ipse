ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
[boundary, root] = System.argv()

assert boundary in ~w(entry_before entry_after exit_before exit_after mcp_entry_epoch mcp_exit_epoch)

defmodule PlanningCrashWriter do
  use GenServer

  def start(writer, target, phase, armed, observer),
    do: GenServer.start(__MODULE__, {writer, target, phase, armed, observer})

  def init(state), do: {:ok, state}

  def handle_call(
        {:append, _, %{"type" => type}} = request,
        _from,
        {writer, type, phase, true, observer} = state
      ) do
    if phase == :after, do: :ok = GenServer.call(writer, request, 5_000)
    send(observer, {:boundary_held, self()})
    {:noreply, state}
  end

  def handle_call(
        {:append, _, %{"type" => "planning_entry_observed"}} = request,
        _from,
        {writer, target, phase, false, observer}
      ) do
    result = GenServer.call(writer, request, 5_000)
    {:reply, result, {writer, target, phase, true, observer}}
  end

  def handle_call(request, _from, {writer, _, _, _, _} = state),
    do: {:reply, GenServer.call(writer, request, 5_000), state}
end

config = %{provider: :demo, model: "synthetic", home: Path.join(root, "home"), approval: :ask}

config =
  if String.starts_with?(boundary, "mcp_") do
    reads = %{
      "mcp__notes__lookup" => %{
        "version" => 1,
        "server_id" => "notes",
        "tool" => "lookup",
        "endpoint_sha256" => Ipse.JSON.sha256("endpoint"),
        "descriptor_sha256" => Ipse.JSON.sha256("descriptor")
      }
    }

    Map.merge(config, %{
      planning_mcp_reads: reads,
      configuration: %{
        fingerprint: Ipse.JSON.digest([reads]),
        planning_mcp_reads: reads,
        sources: []
      }
    })
  else
    config
  end

dir = Path.join(root, "state")
opts = [config: config, cwd: root, state_dir: dir, subscriber: self()]
{:ok, session} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
id = Ipse.Session.info(session).id
state = :sys.get_state(session)
owner_monitor = Process.monitor(session)
writer_monitor = Process.monitor(state.journal_writer)
guard_monitor = Process.monitor(state.lock_guard)
observer = self()

killer =
  spawn(fn ->
    receive do
      {:boundary_held, proxy} ->
        send(observer, {:boundary_reached, proxy})
        Process.exit(session, :kill)
    end
  end)

target =
  cond do
    String.ends_with?(boundary, "_epoch") -> "planning_mcp_epoch"
    String.starts_with?(boundary, "entry_") -> "planning_entry_observed"
    true -> "planning_exited"
  end

phase = if String.ends_with?(boundary, "_after"), do: :after, else: :before

{:ok, proxy} =
  PlanningCrashWriter.start(
    state.journal_writer,
    target,
    phase,
    boundary != "mcp_exit_epoch",
    killer
  )

:sys.replace_state(state.journal_writer, &%{&1 | owner: proxy})
:sys.replace_state(session, &%{&1 | journal_writer: proxy})

assert 1 == Ipse.CLI.Terminal.interact(session, owner_monitor, true, nil, root)
assert_receive {:boundary_reached, ^proxy}, 5_000
assert_receive {:DOWN, ^writer_monitor, :process, _, _}, 5_000
assert_receive {:DOWN, ^guard_monitor, :process, _, _}, 5_000

assert {:ok, events} = Ipse.Journal.load(dir, id)
assert Enum.count(events, &(&1["type"] == "execution_mode_resumed")) == 1
entry_count = if boundary in ~w(entry_before mcp_entry_epoch), do: 0, else: 1
exit_count = if boundary in ~w(exit_after mcp_exit_epoch), do: 1, else: 0
ceiling = if exit_count == 1, do: "normal", else: "planning"
assert Enum.count(events, &(&1["type"] == "planning_entry_observed")) == entry_count
assert Enum.count(events, &(&1["type"] == "planning_exited")) == exit_count
assert {:ok, mode, entry} = Ipse.Session.PlanningTransition.reconstruct(events, id)
assert mode["ceiling"] == ceiling
assert is_map(entry) == (entry_count == 1 and exit_count == 0)
assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
assert :ok = Ipse.Session.PlanningMCP.validate_events(events, id)
refute Enum.any?(events, &(&1["type"] in ~w(tool_started planning_mcp_read_intent)))

GenServer.stop(proxy)

{:ok, resumed} =
  DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, Keyword.put(opts, :id, id)})

assert Ipse.Session.info(resumed).execution_mode["ceiling"] == ceiling
assert :ok = Ipse.Session.close_confirmed(resumed)
assert {:ok, after_resume} = Ipse.Journal.load(dir, id)
assert Enum.count(after_resume, &(&1["type"] == "planning_entry_observed")) == entry_count
assert Enum.count(after_resume, &(&1["type"] == "planning_exited")) == exit_count
assert :ok = Ipse.Session.PlanningMCP.validate_events(after_resume, id)
refute Enum.any?(after_resume, &(&1["type"] in ~w(tool_started planning_mcp_read_intent)))
IO.puts("SYNTHETIC_PLANNING_CRASH_" <> String.upcase(boundary) <> "_PASSED")
