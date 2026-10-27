ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
root = hd(System.argv())

defmodule OperatorChannelProvider do
  def complete(config, _, _, _) do
    send(config.fixture_owner, {:fixture_model, self()})

    receive do: (:finish ->
                   {:ok, %{"role" => "assistant", "content" => "Synthetic completed."}, %{}})
  end
end

new = fn id ->
  {:ok, session} =
    Ipse.Session.start_link(
      config: %{
        provider: :demo,
        model: "synthetic",
        provider_module: OperatorChannelProvider,
        fixture_owner: self(),
        home: Path.join(root, "home"),
        approval: :deny
      },
      cwd: root,
      id: id,
      state_dir: Path.join(root, "state"),
      subscriber: self()
    )

  Process.unlink(session)
  session
end

reader = fn session ->
  owner = self()

  spawn(fn ->
    loop = fn loop ->
      receive do
        {:read, channel, request, id} ->
          send(
            owner,
            {:observed, id, Ipse.Session.observe_channel(session, channel, request, 30_000)}
          )

          loop.(loop)
      end
    end

    loop.(loop)
  end)
end

eventually = fn check ->
  loop = fn loop, left ->
    cond do
      check.() ->
        :ok

      left <= 0 ->
        flunk("native channel cleanup did not settle")

      true ->
        Process.sleep(5)
        loop.(loop, left - 1)
    end
  end

  loop.(loop, 1200)
end

observe = fn session, client, channel, n ->
  IO.write("IPSE_FIXTURE_INPUT_#{n}> ")
  send(client, {:read, channel, %{"kind" => "prompt"}, n})
  assert_receive {:observed, ^n, {:ok, text, witness}}, 5000
  assert text == "synthetic café 日本語 #{n}"

  assert {:error, :invalid_input_witness} =
           Ipse.Session.stage_input(session, Ipse.Usage.id(), text, witness)

  assert {:ok, ticket} = Ipse.Session.stage_input(session, channel, text, witness)
  {text, ticket}
end

complete = fn session ->
  assert_receive {:fixture_model, worker}, 5000
  send(worker, :finish)
  assert_receive {:ipse, ^session, {:done, :ok}}, 5000
end

wait_input = fn client, channel, n ->
  send(
    client,
    {:read, channel, %{"kind" => "control", "display" => "IPSE_CHANNEL_WAIT_#{n}> "}, {:wait, n}}
  )

  eventually.(fn -> File.exists?(Path.join(root, "native-wait-#{n}")) end)
end

session = new.(nil)
id = Ipse.Session.info(session).id
client = reader.(session)
{:ok, channel} = Ipse.Session.open_input_channel(session, client)

assert {:error, :operator_input_unavailable} =
         Task.async(fn -> Ipse.Session.open_input_channel(session, self()) end) |> Task.await()

{text1, ticket1} = observe.(session, client, channel, 1)
assert :ok = Ipse.Session.prompt(session, text1, ticket1)
assert_receive {:fixture_model, first}, 5000
{text2, ticket2} = observe.(session, client, channel, 2)
assert {:error, :busy} = Ipse.Session.prompt(session, text2, ticket2)
send(first, :finish)
assert_receive {:ipse, ^session, {:done, :ok}}, 5000
assert :ok = Ipse.Session.prompt(session, text2, ticket2)
assert_receive {:fixture_model, _}, 5000
{text3, ticket3} = observe.(session, client, channel, 3)
assert :ok = Ipse.Session.cancel(session)
assert_receive {:ipse, ^session, {:done, :cancelled}}, 5000
assert {:error, :invalid_input_witness} = Ipse.Session.prompt(session, text3, ticket3)
{text4, ticket4} = observe.(session, client, channel, 4)
assert :ok = Ipse.Session.prompt(session, text4, ticket4)
complete.(session)
{text5, ticket5} = observe.(session, client, channel, 5)
Process.exit(client, :kill)
eventually.(fn -> :sys.get_state(session).operator_channel == nil end)
assert {:error, :invalid_input_witness} = Ipse.Session.prompt(session, text5, ticket5)
client = reader.(session)
{:ok, channel} = Ipse.Session.open_input_channel(session, client)
{text6, ticket6} = observe.(session, client, channel, 6)
assert :ok = Ipse.Session.prompt(session, text6, ticket6)
complete.(session)

wait_input.(client, channel, 1)
service = Process.whereis(Ipse.Session.Input)
Process.exit(service, :kill)
assert_receive {:observed, {:wait, 1}, {:error, _}}, 5000

eventually.(fn ->
  Process.whereis(Ipse.Session.Input) not in [nil, service] and
    Ipse.Runner.operator_channel() == {:ok, :native}
end)

wait_input.(client, channel, 2)
assert :ok = Ipse.Session.close_confirmed(session)
assert_receive {:observed, {:wait, 2}, {:error, _}}, 5000
Process.exit(client, :kill)

session = new.(id)
client = reader.(session)
{:ok, channel} = Ipse.Session.open_input_channel(session, client)
wait_input.(client, channel, 3)
Process.exit(session, :kill)
assert_receive {:observed, {:wait, 3}, {:error, _}}, 5000

eventually.(fn ->
  Ipse.Session.Lock.for_owner(session) == nil and Ipse.Runner.operator_channel() == {:ok, :native}
end)

Process.exit(client, :kill)
{:ok, events} = Ipse.Journal.load(Path.join(root, "state"), id)
inputs = Enum.filter(events, &(&1["type"] == "input_received"))
assert Enum.map(inputs, & &1["text"]) == Enum.map([1, 2, 4, 6], &"synthetic café 日本語 #{&1}")
assert Enum.all?(inputs, &(&1["version"] === 2 and &1["origin"] == "interactive_operator"))
assert :ok = Ipse.Session.Input.validate_events(events, id)
assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
IO.puts("OPERATOR_CHANNEL_CHECKS_PASSED")
