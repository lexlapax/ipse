Code.require_file("../../test/support/provider_registry_fixture.ex", __DIR__)
{:ok, _} = Application.ensure_all_started(:ipse)
[output] = System.argv()
File.mkdir_p!(output)
root = Path.join(System.tmp_dir!(), "ipse-registry-baseline-" <> Ipse.Usage.id())
cwd = Path.join(root, "workspace")
home = Path.join(root, "home")
File.mkdir_p!(cwd)
File.mkdir_p!(home)
System.put_env("HOME", home)
System.put_env("IPSE_HOME", home)
facts = Ipse.Test.ProviderRegistryFixture.facts(cwd, home)
File.write!(Path.join(output, "equivalence.json"), Jason.encode!(facts, pretty: true) <> "\n")

for id <- ~w(chatgpt openai ollama anthropic demo) do
  provider = String.to_existing_atom(id)
  model = facts[id]["manifest"]["settings"]["model"]

  config = %{
    provider: provider,
    model: model,
    approval: :deny,
    home: home,
    sandbox: :off,
    extensions: []
  }

  state = Path.join(root, "state-" <> id)

  {:ok, pid} =
    DynamicSupervisor.start_child(
      Ipse.Sessions,
      {Ipse.Session, config: config, cwd: cwd, state_dir: state, subscriber: self()}
    )

  session = Ipse.Session.info(pid).id
  :ok = Ipse.Session.close(pid)
  admitted = Ipse.Usage.admission(session, config, "model", Ipse.Usage.id())

  observation =
    Ipse.Usage.observation(admitted, Ipse.Test.ProviderRegistryFixture.raw(provider), 1)

  finished =
    Ipse.Usage.completion(
      admitted,
      {:ok, %{"provider_data" => %{}}, Ipse.Test.ProviderRegistryFixture.raw(provider)},
      1,
      nil
    )

  for event <- [admitted, observation, finished],
      do: :ok = Ipse.Journal.append(state, session, event)

  bytes = File.read!(Path.join(state, session <> ".jsonl"))
  File.write!(Path.join(output, id <> ".jsonl"), bytes)
  events = bytes |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
  {:ok, restored} = Ipse.Usage.restore(events, session)

  File.write!(
    Path.join(output, id <> "-usage.json"),
    Jason.encode!(Ipse.Test.ProviderRegistryFixture.portable(restored), pretty: true) <> "\n"
  )

  [header | rest] = events
  legacy = update_in(header, ["metadata"], &Map.delete(&1, "provider_destination"))

  legacy_rest =
    Enum.reject(
      rest,
      &(&1["type"] in ~w(request_admitted request_usage_observed request_finished))
    )

  File.write!(
    Path.join(output, id <> "-legacy.jsonl"),
    Enum.map_join([legacy | legacy_rest], "\n", &Jason.encode!/1) <> "\n"
  )
end

File.rm_rf!(root)
