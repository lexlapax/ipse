ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file(Path.expand("provider_fixture.ex", __DIR__))

[root, "recall-many"] = System.argv()
sparse = System.get_env("IPSE_TEST_RECALL_SPARSE") == "1"
reappear = System.get_env("IPSE_TEST_RECALL_REAPPEAR") == "1"
strict_sources = System.get_env("IPSE_TEST_RECALL_STRICT_SOURCES") == "1"
assert not reappear or sparse
assert not strict_sources or (sparse and reappear)

provider_timeout =
  System.get_env("IPSE_TEST_RECALL_PROVIDER_TIMEOUT_MS", "5000") |> String.to_integer()

assert provider_timeout in 1..100_000
assert not strict_sources or provider_timeout == 5_000
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
      if (sparse and step == 2) or (strict_sources and step > 1) do
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

original_snapshot =
  if strict_sources do
    assert length(source_ids) == 33 and length(Enum.uniq(source_ids)) == 33

    Map.new(Enum.zip(source_ids, texts), fn {id, text} ->
      assert {:ok, events} = Ipse.Journal.load(dir, id)
      assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
      assert [assertion] = Enum.filter(events, &(&1["type"] == "operator_assertion"))
      assert assertion["text"] == text
      refute Enum.any?(events, &(&1["type"] == "inference_dispatch_intent"))

      pins =
        for extension <- ~w(jsonl lock), into: %{} do
          path = Path.join(dir, id <> "." <> extension)
          assert {:ok, %{type: :regular, links: 1} = stat} = File.lstat(path)
          assert stat.inode > 0

          {extension,
           {Map.take(stat, [:major_device, :minor_device, :inode, :uid, :gid, :mode, :size]),
            Ipse.JSON.sha256(File.read!(path))}}
        end

      {id, pins}
    end)
  else
    %{}
  end

if strict_sources do
  metadata =
    Map.new(original_snapshot, fn {id, files} ->
      {id,
       Map.new(files, fn {extension, {identity, sha}} ->
         {extension,
          %{
            "identity" => Map.new(identity, fn {key, value} -> {Atom.to_string(key), value} end),
            "sha256" => sha
          }}
       end)}
    end)

  path = Path.join(root, "original-source-pins.json")
  File.write!(path, Jason.encode!(metadata), [:binary, :exclusive, :sync])
  File.chmod!(path, 0o600)
end

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
         if(sparse or strict_sources, do: 1, else: 33)

refute Enum.any?(source_events, &(&1["type"] == "inference_dispatch_intent"))

{held_journal, expected_texts, missing_text, expected_notes, missing_key} =
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
      if strict_sources do
        sources =
          Enum.map(rows, fn row ->
            [proof] = get_in(row, ["value", "evidence", "sources"])
            proof["session_id"]
          end)

        assert MapSet.new(sources) == MapSet.new(source_ids)
        hd(rows)
      else
        Enum.find(
          rows,
          &(get_in(&1, ["value", "evidence", "sources"])
            |> List.first()
            |> Map.fetch!("session_id") == source_id)
        )
      end

    assert is_map(first_source)

    unavailable_id =
      if strict_sources,
        do: first_source["value"]["evidence"]["sources"] |> hd() |> Map.fetch!("session_id"),
        else:
          if(List.last(rows)["key"] == first_source["key"],
            do: List.last(source_ids),
            else: source_id
          )

    expected =
      Enum.reject(rows, fn row ->
        get_in(row, ["value", "evidence", "sources"]) |> List.first() |> Map.fetch!("session_id") ==
          unavailable_id
      end)

    assert Enum.any?(Enum.drop(rows, 32), &(&1 in expected))
    if strict_sources, do: assert(length(expected) == 32)
    journal = Path.join(dir, unavailable_id <> ".jsonl")
    refute File.exists?(journal <> ".held")
    File.rename!(journal, journal <> ".held")

    {journal, Enum.map(expected, & &1["value"]["text"]), first_source["value"]["text"],
     Map.new(expected, &{&1["key"], %{text: &1["value"]["text"], revision: &1["revision"]}}),
     first_source["key"]}
  else
    {nil, texts, nil, %{}, nil}
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

parts =
  if strict_sources do
    prefix =
      Ipse.Extension.render_context(%{"knowledge" => []}) |> String.replace_suffix("[]", "")

    items =
      Enum.flat_map(request["messages"], fn
        %{"role" => "user"} = message ->
          case Ipse.Session.Reference.selected_publishers(message) do
            {:ok, %{"extensions" => text}} when is_binary(text) ->
              if String.starts_with?(text, prefix) do
                assert {:ok, items} = Jason.decode(String.replace_prefix(text, prefix, ""))
                assert is_list(items)
                items
              else
                []
              end

            _ ->
              []
          end

        _ ->
          []
      end)

    parts =
      items
      |> Enum.filter(
        &(get_in(&1, ["provenance", "instance"]) == "knowledge" and is_binary(&1["id"]) and
            String.starts_with?(&1["id"], "note_text_"))
      )
      |> Enum.flat_map(fn item ->
        assert {:ok, group} = Jason.decode(item["text"])
        assert group["format"] == "note_parts_v1"
        assert group["fields"] == ~w(key revision read_operation_id offset_bytes total_bytes text)
        assert Enum.all?(group["records"], &(is_list(&1) and length(&1) == 6))
        Enum.map(group["records"], &Map.new(Enum.zip(group["fields"], &1)))
      end)

    assert MapSet.new(Enum.map(parts, & &1["key"])) == MapSet.new(Map.keys(expected_notes))
    refute Enum.any?(parts, &(&1["key"] == missing_key or &1["text"] == missing_text))
    refute String.contains?(wire, missing_text)

    for {key, expected} <- expected_notes do
      selected = Enum.filter(parts, &(&1["key"] == key))
      assert selected != []

      {text, offset} =
        Enum.reduce(selected, {"", 0}, fn part, {text, offset} ->
          assert part["revision"] == expected.revision
          assert is_binary(part["read_operation_id"])

          assert part["offset_bytes"] == offset and
                   part["total_bytes"] == byte_size(expected.text)

          assert is_binary(part["text"]) and String.valid?(part["text"])
          {text <> part["text"], offset + byte_size(part["text"])}
        end)

      assert text == expected.text and offset == byte_size(expected.text)
    end

    parts
  else
    []
  end

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

if strict_sources do
  for part <- parts do
    assert Enum.any?(reads, fn event ->
             record = get_in(event, ["outcome", "value", "record"])

             event["operation_id"] == part["read_operation_id"] and
               get_in(event, ["request", "request", "key"]) == part["key"] and
               is_map(record) and record["key"] == part["key"] and
               record["revision"] == part["revision"] and
               get_in(record, ["value", "text"]) == expected_notes[part["key"]].text
           end)
  end
end

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

if strict_sources do
  assert length(reads) == 32
  assert length(Enum.uniq_by(reads, &get_in(&1, ["request", "request", "key"]))) == 32
  assert included == 32 and coverage["coverage"] == "partial" and coverage["unavailable"] == 1
  refute File.exists?(held_journal <> ".held")

  for {id, pins} <- original_snapshot do
    assert {:ok, events} = Ipse.Journal.load(dir, id)
    assert {:ok, _} = Ipse.Session.Saved.restore(events, id)

    for {extension, {expected_stat, expected_sha}} <- pins do
      path = Path.join(dir, id <> "." <> extension)
      assert {:ok, %{type: :regular, links: 1} = stat} = File.lstat(path)
      assert Map.take(stat, Map.keys(expected_stat)) == expected_stat
      assert Ipse.JSON.sha256(File.read!(path)) == expected_sha
    end
  end

  {:ok, before_resume} = Ipse.Journal.load(dir, session_id)

  effect_types =
    ~w(input_received extension_invocation_intent extension_action_intent worker_input_intent inference_dispatch_intent)

  intents = Enum.filter(before_resume, &(&1["type"] in effect_types))

  refute Enum.any?(
           before_resume,
           &(&1["type"] == "worker_input_result" and &1["status"] == "unknown")
         )

  assert {:ok, resumed} =
           DynamicSupervisor.start_child(
             Ipse.Sessions,
             {Ipse.Session, Keyword.put(opts, :id, session_id)}
           )

  assert Ipse.Session.info(resumed).phase == :idle
  assert :ok = Ipse.Session.close_confirmed(resumed)
  assert {:ok, after_resume} = Ipse.Journal.load(dir, session_id)
  assert {:ok, _} = Ipse.Session.Saved.restore(after_resume, session_id)
  assert Enum.filter(after_resume, &(&1["type"] in effect_types)) == intents

  for {id, pins} <- original_snapshot, {extension, {identity, sha}} <- pins do
    path = Path.join(dir, id <> "." <> extension)
    assert {:ok, stat} = File.lstat(path)
    assert Map.take(stat, Map.keys(identity)) == identity
    assert Ipse.JSON.sha256(File.read!(path)) == sha
  end

  File.write!(
    Path.join(root, "strict-recall-result.json"),
    Jason.encode!(%{
      "originals" => 33,
      "eligible" => 32,
      "unavailable" => 1,
      "coverage" => "partial",
      "structured_parts" => length(parts),
      "committed_reads" => length(reads),
      "source_identities_unchanged" => true,
      "same_id_idle_intents_unchanged" => true
    }),
    [:exclusive, :sync]
  )

  IO.puts(
    "NATIVE_NOTE_RECALL_STRICT_SOURCES_PASSED originals=33 unavailable=1 reads=32 included=32 structured_parts=verified original_bytes_and_lock_identity=unchanged idle_intents=unchanged"
  )
end

if held_journal && File.exists?(held_journal <> ".held"),
  do: File.rename!(held_journal <> ".held", held_journal)

IO.puts("NATIVE_NOTE_RECALL_MANY_PASSED")
