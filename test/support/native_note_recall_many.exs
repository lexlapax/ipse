ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file(Path.expand("provider_fixture.ex", __DIR__))

[root, "recall-many"] = System.argv()
sparse = System.get_env("IPSE_TEST_RECALL_SPARSE") == "1"
reappear = System.get_env("IPSE_TEST_RECALL_REAPPEAR") == "1"
assert not reappear or sparse

provider_timeout =
  System.get_env("IPSE_TEST_RECALL_PROVIDER_TIMEOUT_MS", "5000") |> String.to_integer()

assert provider_timeout in 1..100_000
home = Path.join(root, "home")
cwd = Path.join(root, "work")

for key <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
    do: System.delete_env(key)

for path <- [home, cwd] do
  File.mkdir_p!(path)
  File.chmod!(path, 0o700)
end

System.put_env("IPSE_HOME", home)
owner = self()
{:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
{:ok, {_, port}} = :inet.sockname(listener)
base = "http://127.0.0.1:#{port}"

server =
  Task.async(fn ->
    try do
      {:ok, socket} = :gen_tcp.accept(listener, 180_000)

      try do
        request =
          case :gen_tcp.recv(socket, 0, provider_timeout + 1_000) do
            {:ok, first} -> {:ok, Ipse.Test.ProviderFixture.request(socket, first)}
            {:error, :closed} -> :closed
            other -> flunk("Synthetic provider initial read failed: #{inspect(other)}")
          end

        case request do
          {:ok, {_, bytes}} ->
            send(owner, {:recall_many_request, Jason.decode!(bytes)})

            body =
              Jason.encode!(%{
                "model" => "synthetic",
                "message" => %{"role" => "assistant", "content" => "Synthetic answer."},
                "done" => true,
                "prompt_eval_count" => 1,
                "eval_count" => 1
              }) <> "\n"

            :ok =
              :gen_tcp.send(
                socket,
                "HTTP/1.1 200 Fixture\r\ncontent-type: application/x-ndjson\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                  body
              )

          :closed ->
            send(owner, :recall_provider_closed_without_request)
            :closed
        end
      after
        :gen_tcp.close(socket)
      end
    after
      :gen_tcp.close(listener)
    end
  end)

config_path = Path.join(home, "config.json")

File.write!(
  config_path,
  Jason.encode!(%{
    "version" => 1,
    "profiles" => %{
      "recall" => %{
        "provider" => "ollama",
        "model" => "synthetic",
        "base_url" => base,
        "max_output_tokens" => 64,
        "timeout_ms" => provider_timeout
      }
    },
    "roles" => %{"main" => "recall"},
    "inference_services" => %{"local" => %{"version" => 1, "origins" => [base]}}
  })
)

File.chmod!(config_path, 0o600)

assert Ipse.CLI.run([
         "knowledge",
         "enable",
         "--cwd",
         cwd,
         "--config",
         config_path,
         "--no-project-config"
       ]) == 0

client = %{
  workspace: cwd,
  home: home,
  auth_dir: Path.join(home, "auth"),
  operator_home: root,
  mcp_config: nil,
  base_url: nil,
  operator_questions: true,
  accept_edits: false,
  approval: :ask,
  approval_origin: :interactive,
  headless: false
}

{:ok, effective} =
  Ipse.Config.resolve(cwd, home, [config: config_path, project_config: false], %{})

{:ok, config} = Ipse.Config.runtime(effective, client)
dir = Path.join(home, "sessions")
opts = [config: config, cwd: cwd, state_dir: dir, subscriber: self()]
assert {:ok, source} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
source_id = Ipse.Session.info(source).id
pin = :sys.get_state(source).config.semantic_admission["pin"]
assert {:ok, channel} = Ipse.Session.open_input_channel(source, self())

{texts, source, source_ids} =
  Enum.reduce(1..33, {[], source, channel, [source_id]}, fn step,
                                                            {texts, current, channel, ids} ->
    {current, channel, ids} =
      if sparse and step == 2 do
        assert :ok = Ipse.Session.close_confirmed(current)
        assert {:ok, other} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
        assert {:ok, next_channel} = Ipse.Session.open_input_channel(other, self())
        {other, next_channel, ids ++ [Ipse.Session.info(other).id]}
      else
        {current, channel, ids}
      end

    text = "~N" <> String.pad_leading(Integer.to_string(step), 2, "0") <> "~"
    command = "/remember ordinary " <> text
    File.write!(Path.join(root, "supersession-input-#{step}"), command)
    IO.write("IPSE_SUPERSESSION_READ_#{step}> ")

    assert {:ok, ^command, witness} =
             Ipse.Session.observe_channel(current, channel, %{"kind" => "prompt"}, 30_000)

    assert {:ok, ticket} = Ipse.Session.stage_input(current, channel, command, witness)

    assert {:ok, %{"render_id" => render}} =
             Ipse.Session.prepare_assertion(current, channel, command, ticket)

    assert {:ok, input, observed} =
             Ipse.Session.observe_channel(
               current,
               channel,
               %{"kind" => "assertion", "render_id" => render},
               30_000
             )

    assert :ok = Ipse.Session.accept_assertion_observed(current, channel, render, input, observed)
    assert_receive {:ipse, ^current, {:done, :ok}}, 30_000
    {texts ++ [text], current, channel, ids}
  end)
  |> then(fn {texts, current, _, ids} -> {texts, current, ids} end)

assert :ok = Ipse.Session.close_confirmed(source)
assert {:ok, source_events} = Ipse.Journal.load(dir, source_id)
{restore_us, restored} = :timer.tc(fn -> Ipse.Session.Saved.restore(source_events, source_id) end)
assert {:ok, _} = restored

if System.get_env("IPSE_TEST_RECALL_TIMING") == "1",
  do: IO.puts("RECALL_SOURCE_RESTORE_TIMING_US=" <> Integer.to_string(restore_us))

if System.get_env("IPSE_TEST_RECALL_TIMING") == "1" do
  copy = Path.join(System.tmp_dir!(), "ipse-recall-profile-source-" <> source_id <> ".jsonl")
  File.cp!(Path.join(dir, source_id <> ".jsonl"), copy)
  File.chmod!(copy, 0o600)
  IO.puts("RECALL_PROFILE_SOURCE=" <> copy)

  checks = [
    {"actions", fn -> Ipse.Extension.Actions.restore(source_events) end},
    {"invocations", fn -> Ipse.Extension.Invocation.validate_events(source_events) end},
    {"context", fn -> Ipse.Session.Saved.context(source_events) end},
    {"source_window", fn -> Ipse.Session.SourceWindow.restore(source_events, source_id) end},
    {"usage", fn -> Ipse.Usage.restore(source_events, source_id) end}
  ]

  for {name, check} <- checks do
    {elapsed, result} = :timer.tc(check)
    assert result == :ok or match?({:ok, _}, result)
    IO.puts("RECALL_COMPONENT_TIMING_US " <> name <> "=" <> Integer.to_string(elapsed))
  end
end

assert Enum.count(source_events, &(&1["type"] == "operator_assertion")) ==
         if(sparse, do: 1, else: 33)

refute Enum.any?(source_events, &(&1["type"] == "inference_dispatch_intent"))

{held_journal, expected_texts} =
  if sparse do
    collection = Ipse.Extension.SemanticAdmission.collection_root(home)

    {:ok, snapshot} =
      Ipse.Extension.Collection.execute(
        collection,
        pin["namespace"],
        %{"op" => "snapshot"},
        Ipse.Usage.id()
      )

    scan = fn scan, after_key, acc ->
      {:ok, page} =
        Ipse.Extension.Collection.scan_visible(
          collection,
          pin["namespace"],
          %{
            "op" => "scan",
            "after" => after_key,
            "generation" => snapshot["generation"],
            "limit" => 4
          },
          Ipse.Usage.id()
        )

      rows = acc ++ Enum.filter(page["records"], &String.starts_with?(&1["key"], "note."))
      if is_nil(page["next"]), do: rows, else: scan.(scan, page["next"], rows)
    end

    rows = scan.(scan, nil, [])
    assert length(rows) == 33

    first_source =
      Enum.find(
        rows,
        &(get_in(&1, ["value", "evidence", "sources"]) |> List.first() |> Map.fetch!("session_id") ==
            source_id)
      )

    assert is_map(first_source)

    unavailable_id =
      if List.last(rows)["key"] == first_source["key"], do: List.last(source_ids), else: source_id

    expected =
      Enum.reject(rows, fn row ->
        get_in(row, ["value", "evidence", "sources"]) |> List.first() |> Map.fetch!("session_id") ==
          unavailable_id
      end)

    assert Enum.any?(Enum.drop(rows, 32), &(&1 in expected))
    journal = Path.join(dir, unavailable_id <> ".jsonl")
    File.rename!(journal, journal <> ".held")
    {journal, Enum.map(expected, & &1["value"]["text"])}
  else
    {nil, texts}
  end

assert {:ok, session} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
session_id = Ipse.Session.info(session).id

if reappear do
  owner = self()

  hook = fn
    false, {:in, {:"$gen_call", _, {:managed_preflight_begin, _, "model"}}}, _ ->
      assert File.regular?(held_journal <> ".held")
      refute File.exists?(held_journal)
      File.rename!(held_journal <> ".held", held_journal)
      send(owner, {:recall_source_reappeared_before_preflight, session})
      true

    state, _, _ ->
      state
  end

  assert :ok = :sys.install(session, {hook, false})
end

assert :ok = Ipse.Session.prompt(session, "Which synthetic notes are available?")

request =
  receive do
    {:recall_many_request, request} ->
      request

    {:ipse, ^session, {:done, status}} ->
      {:ok, events} = Ipse.Journal.load(dir, session_id)
      counts = Enum.frequencies_by(events, & &1["type"])

      inputs =
        events
        |> Enum.filter(&(&1["type"] == "worker_input_result"))
        |> Enum.frequencies_by(& &1["status"])

      tail =
        events
        |> Enum.take(-25)
        |> Enum.map(&Map.take(&1, ~w(type status reason closure cleanup_confirmed)))

      closed =
        receive do
          :recall_provider_closed_without_request -> true
        after
          0 -> false
        end

      flunk(
        "Recall ended #{inspect(status)} before dispatch, provider_closed=#{closed}, counts=#{inspect(counts)}, worker_inputs=#{inspect(inputs)}, tail=#{inspect(tail, limit: :infinity)}"
      )
  after
    120_000 -> flunk("Recall did not dispatch or finish within the fixture bound")
  end

wire = Jason.encode!(request["messages"])

if reappear do
  assert_receive {:recall_source_reappeared_before_preflight, ^session}, 5_000
  assert File.regular?(held_journal)
end

included = Enum.count(texts, &String.contains?(wire, &1))
assert_receive {:ipse, ^session, {:done, :ok}}, 30_000
assert :ok = Task.await(server, 5_000)

assert {:ok, events} = Ipse.Journal.load(dir, session_id)
assert {:ok, _} = Ipse.Session.Saved.restore(events, session_id)

if reappear do
  {before_dispatch, dispatch} =
    Enum.split_while(events, &(&1["type"] != "inference_dispatch_intent"))

  assert dispatch != []

  assert Enum.any?(before_dispatch, fn event ->
           event["type"] == "extension_action_result" and
             get_in(event, ["outcome", "value", "code"]) == "collection_original_source_missing"
         end)
end

reads =
  Enum.filter(events, fn event ->
    event["type"] == "extension_action_result" and
      get_in(event, ["request", "op"]) == "collection.call" and
      get_in(event, ["request", "request", "op"]) == "get" and
      get_in(event, ["outcome", "status"]) == "ok"
  end)

coverage =
  events
  |> Enum.flat_map(fn event ->
    if event["type"] == "extension_action_intent" and
         get_in(event, ["request", "op"]) == "context.publish",
       do: get_in(event, ["request", "items"]) || [],
       else: []
  end)
  |> Enum.find(&(&1["id"] == "note_coverage"))
  |> Map.fetch!("text")
  |> Jason.decode!()

IO.puts(
  "NATIVE_NOTE_RECALL_OBSERVED " <>
    Jason.encode!(%{
      "included" => included,
      "reads" => length(reads),
      "coverage" => coverage["coverage"],
      "coverage_included" => coverage["included"],
      "allocation_bytes" => coverage["allocation_bytes"]
    })
)

expected_count = length(expected_texts)
assert included == expected_count
assert length(reads) == expected_count
assert Enum.all?(expected_texts, &String.contains?(wire, &1))
assert coverage["coverage"] == if(sparse, do: "partial", else: "complete")
assert coverage["included"] == included
assert :ok = Ipse.Session.close_confirmed(session)

if held_journal && File.exists?(held_journal <> ".held"),
  do: File.rename!(held_journal <> ".held", held_journal)

IO.puts("NATIVE_NOTE_RECALL_MANY_PASSED")
