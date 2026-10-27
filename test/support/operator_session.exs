ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
root = hd(System.argv())

defmodule InputProviderFixture do
  def complete(_, _, _, _), do: {:ok, %{"role" => "assistant", "content" => "fixture"}, %{}}
end

new = fn id ->
  {:ok, pid} =
    DynamicSupervisor.start_child(
      Ipse.Sessions,
      {Ipse.Session,
       config: %{
         provider: :demo,
         model: "test",
         provider_module: InputProviderFixture,
         home: Path.join(root, "home"),
         approval: :deny
       },
       cwd: root,
       id: id,
       state_dir: Path.join(root, "state"),
       subscriber: self()}
    )

  pid
end

read = fn pid, n ->
  {:ok, text, witness} = Ipse.Session.observe_input(pid, "IPSE_FIXTURE_INPUT_#{n}> ", 5000)
  assert is_reference(witness)
  assert text == "synthetic café 日本語 #{n}"
  {text, witness}
end

done = fn pid -> assert_receive {:ipse, ^pid, {:done, :ok}}, 5000 end

eventually = fn check ->
  loop = fn loop, left ->
    cond do
      check.() ->
        :ok

      left == 0 ->
        flunk("input lifecycle did not settle")

      true ->
        Process.sleep(5)
        loop.(loop, left - 1)
    end
  end

  loop.(loop, 1000)
end

pid = new.(nil)
other = new.(nil)

{text, witness} = read.(pid, 1)
assert {:error, :invalid_input_witness} = Ipse.Session.prompt(other, text, witness)
assert {:error, :invalid_input_witness} = Ipse.Session.Input.consume(witness, text, %{})
assert :ok = Ipse.Session.prompt(pid, text, witness)
done.(pid)
assert {:error, :invalid_input_witness} = Ipse.Session.prompt(pid, text, witness)
id = Ipse.Session.info(pid).id
{:ok, events} = Ipse.Journal.load(Path.join(root, "state"), id)
receipt = Enum.find(events, &(&1["type"] == "input_received"))
assert receipt["origin"] == "interactive_operator"
assert receipt["observation"]["version"] === 1
assert receipt["text"] == text
assert receipt["observation"]["text_sha256"] == Ipse.JSON.sha256(text)
assert :ok = Ipse.Session.Input.validate_events(events, id)

{text, witness} = read.(pid, 2)

assert {:error, :invalid_input_witness} =
         Ipse.Session.prompt(pid, String.trim_trailing(text, "2") <> "3", witness)

assert {:error, :invalid_input_witness} = Ipse.Session.prompt(pid, text, witness)

{text, witness} = read.(pid, 3)
assert :ok = Ipse.Session.cancel(pid)
assert_receive {:ipse, ^pid, {:done, :cancelled}}, 5000
assert {:error, :invalid_input_witness} = Ipse.Session.prompt(pid, text, witness)

{text, witness} = read.(pid, 4)
assert :ok = Ipse.Session.prompt(pid, "plain prompt")
done.(pid)
assert {:error, :invalid_input_witness} = Ipse.Session.prompt(pid, text, witness)

for forged <- [
      receipt["observation"],
      %{"text" => text, "origin" => "interactive_operator"},
      make_ref()
    ] do
  assert {:error, :invalid_input_witness} = Ipse.Session.prompt(pid, text, forged)
end

{text, witness} = read.(pid, 5)

:sys.replace_state(Ipse.Session.Input, fn s ->
  put_in(s.entries[witness].expires, System.monotonic_time(:millisecond) - 1)
end)

assert {:error, :invalid_input_witness} = Ipse.Session.prompt(pid, text, witness)

{text, witness} = read.(pid, 6)
assert :ok = Ipse.Session.close_confirmed(pid)
resumed = new.(id)
assert {:error, :invalid_input_witness} = Ipse.Session.prompt(resumed, text, witness)
refute Map.has_key?(:sys.get_state(Ipse.Session.Input).entries, witness)

{text, witness} = read.(resumed, 7)
service = Process.whereis(Ipse.Session.Input)
Process.exit(service, :kill)

wait = fn wait, n ->
  cond do
    n == 0 ->
      flunk("input service did not restart")

    Process.whereis(Ipse.Session.Input) in [nil, service] ->
      Process.sleep(5)
      wait.(wait, n - 1)

    true ->
      :ok
  end
end

wait.(wait, 200)
assert {:error, :invalid_input_witness} = Ipse.Session.prompt(resumed, text, witness)

{text, witness} = read.(resumed, 8)
assert :ok = Ipse.Session.prompt(resumed, text, witness)
done.(resumed)
{:ok, events} = Ipse.Journal.load(Path.join(root, "state"), id)
plain = Enum.find(events, &(&1["type"] == "input_received" and &1["text"] == "plain prompt"))
assert plain["origin"] == "unattended_input" and plain["observation"] == nil

targets =
  for n <- 9..72 do
    target = new.(nil)
    {_text, _witness} = read.(target, n)

    assert {:error, :operator_input_busy} =
             Ipse.Session.observe_input(target, "never displayed> ", 1000)

    target
  end

assert map_size(:sys.get_state(Ipse.Session.Input).entries) == 64

assert {:error, :operator_input_busy} =
         Ipse.Session.observe_input(resumed, "never displayed> ", 1000)

Enum.each(targets, &Ipse.Session.close_confirmed/1)
eventually.(fn -> :sys.get_state(Ipse.Session.Input).entries == %{} end)

owner = self()

client =
  spawn(fn ->
    result = Ipse.Session.observe_input(resumed, "IPSE_FIXTURE_INPUT_73> ", 5000)
    send(owner, {:client_result, result})

    receive do
      :finish -> :ok
    end
  end)

assert_receive {:client_result, {:ok, text, witness}}, 5000
Process.exit(client, :kill)
eventually.(fn -> :sys.get_state(Ipse.Session.Input).entries == %{} end)
assert {:error, :invalid_input_witness} = Ipse.Session.prompt(resumed, text, witness)

for event <- [:target_death, :target_close, :client_death, :service_death, :worker_death, :cancel] do
  target = if event in [:target_death, :target_close], do: new.(nil), else: resumed

  client =
    spawn(fn ->
      send(
        owner,
        {:waiting_result, self(),
         Ipse.Session.observe_input(target, "IPSE_FIXTURE_WAIT> ", 10_000)}
      )
    end)

  eventually.(fn ->
    Enum.any?(:sys.get_state(Ipse.Session.Input).entries, fn {_, e} ->
      e.target == target and e.task != nil
    end)
  end)

  [{_, entry}] = Map.to_list(:sys.get_state(Ipse.Session.Input).entries)
  worker_ref = Process.monitor(entry.task.pid)

  assert {:error, :operator_input_busy} =
           Ipse.Session.observe_input(other, "concurrent never displayed> ", 1000)

  case event do
    :target_death ->
      Process.exit(target, :kill)

    :target_close ->
      assert :ok = Ipse.Session.close_confirmed(target)

    :client_death ->
      Process.exit(client, :kill)

    :service_death ->
      service = Process.whereis(Ipse.Session.Input)
      Process.exit(service, :kill)
      eventually.(fn -> Process.whereis(Ipse.Session.Input) not in [nil, service] end)

    :worker_death ->
      Process.exit(entry.task.pid, :kill)

    :cancel ->
      assert :ok = Ipse.Session.cancel(target)
      assert_receive {:ipse, ^target, {:done, :cancelled}}, 5000
  end

  assert_receive {:DOWN, ^worker_ref, :process, _, _}, 5000

  if event != :client_death,
    do: assert_receive({:waiting_result, ^client, {:error, :operator_input_unavailable}}, 5000)

  eventually.(fn -> :sys.get_state(Ipse.Session.Input).entries == %{} end)
end

{:ok, stale_lease} = GenServer.call(resumed, {:observe_input, "IPSE_FIXTURE_WAIT> ", 5000})
assert :ok = Ipse.Session.cancel(resumed)
assert_receive {:ipse, ^resumed, {:done, :cancelled}}, 5000
assert {:error, :operator_input_unavailable} = Ipse.Session.Input.await(stale_lease, 5000)
eventually.(fn -> :sys.get_state(Ipse.Session.Input).entries == %{} end)

{text, witness} = read.(resumed, 74)
assert :ok = Ipse.Session.prompt(resumed, text, witness)
done.(resumed)

assert {:error, :operator_input_unavailable} =
         Ipse.Session.observe_input(resumed, "IPSE_FIXTURE_EMPTY_75> ", 5000)

{text, witness} = read.(resumed, 76)
assert :ok = Supervisor.terminate_child(Ipse.Supervisor, Ipse.Session.Input)
assert {:error, :invalid_input_witness} = Ipse.Session.prompt(resumed, text, witness)

assert {:error, :operator_input_unavailable} =
         Ipse.Session.observe_input(resumed, "absent never displayed> ", 1000)

assert :ok = Ipse.Session.prompt(resumed, "unattended during input service restart")
done.(resumed)
assert :ok = Ipse.Session.cancel(resumed)
assert_receive {:ipse, ^resumed, {:done, :cancelled}}, 5000
assert :ok = Ipse.Session.close_confirmed(other)
assert {:ok, _} = Supervisor.restart_child(Ipse.Supervisor, Ipse.Session.Input)

{text, witness} = read.(resumed, 77)
service = Process.whereis(Ipse.Session.Input)
startup_target = new.(nil)
guardian = Ipse.Session.Lock.for_owner(startup_target)
:ok = :sys.suspend(service)

{startup_client, startup_client_ref} =
  spawn_monitor(fn ->
    send(
      owner,
      {:startup_result,
       Ipse.Session.observe_input(
         startup_target,
         "never displayed during failed attachment> ",
         5000
       )}
    )
  end)

scope_for = fn ->
  :sys.get_state(guardian).dependents
  |> Enum.find_value(fn
    {_, {pid, :scope}} -> pid
    _ -> nil
  end)
end

eventually.(fn -> is_pid(scope_for.()) end)
startup_scope = scope_for.()
:ok = :sys.suspend(startup_scope)
:ok = :sys.resume(service)

eventually.(fn ->
  {:messages, messages} = Process.info(startup_scope, :messages)

  Enum.any?(messages, fn
    {:"$gen_call", {^service, _}, {:attach, _}} -> true
    _ -> false
  end)
end)

Process.exit(startup_scope, :kill)
assert_receive {:startup_result, {:error, :operator_input_unavailable}}, 5000
assert_receive {:DOWN, ^startup_client_ref, :process, ^startup_client, :normal}, 5000
assert Process.whereis(Ipse.Session.Input) == service
assert :ok = Ipse.Session.prompt(resumed, text, witness)
done.(resumed)
assert :ok = Ipse.Session.close_confirmed(startup_target)

:erlang.trace_pattern({Ipse.Session.Resources, :closed, 2}, true, [:local])
:erlang.trace(:new, true, [:call, {:tracer, self()}])

try do
  {text, witness} = read.(resumed, 78)

  assert_receive {:trace, worker, :call,
                  {Ipse.Session.Resources, :closed, [%{scope: scope}, :ok]}},
                 1000

  assert is_pid(worker) and is_pid(scope)
  assert :ok = Ipse.Session.prompt(resumed, text, witness)
  done.(resumed)
after
  :erlang.trace(:new, false, [:call])
  :erlang.trace_pattern({Ipse.Session.Resources, :closed, 2}, false, [:local])
end

skill = Path.join(root, ".agents/skills/sample/SKILL.md")
File.mkdir_p!(Path.dirname(skill))

File.write!(
  skill,
  "---\nname: sample\ndescription: Synthetic input provenance exercise\n---\nSynthetic instructions"
)

skill_session = new.(nil)
assert :ok = Ipse.Session.prompt(skill_session, "$sample")
done.(skill_session)

{:ok, skill_events} =
  Ipse.Journal.load(Path.join(root, "state"), Ipse.Session.info(skill_session).id)

skill_receipt = Enum.find(skill_events, &(&1["type"] == "input_received"))

skill_message =
  Enum.find(
    skill_events,
    &(&1["type"] == "message" and get_in(&1, ["message", "role"]) == "user")
  )

assert skill_receipt["text"] == "$sample"
assert skill_receipt["effective_sha256"] == Ipse.JSON.sha256(skill_message["message"]["content"])
refute skill_receipt["text_sha256"] == skill_receipt["effective_sha256"]
assert :ok = Ipse.Session.Input.validate_events(skill_events)
assert :ok = Ipse.Session.close_confirmed(skill_session)
assert :ok = Ipse.Session.close_confirmed(resumed)
IO.puts("SESSION_INPUT_CHECKS_PASSED")
