ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file(Path.expand("provider_fixture.ex", __DIR__))
Code.ensure_loaded!(Ipse.Test.RecallDiagnosticTrace)
Code.ensure_loaded!(Ipse.Test.RecallDiagnostic)
{:flags, []} = :erlang.trace_info(self(), :flags)

[root, "recall-many"] = System.argv()
sparse = System.get_env("IPSE_TEST_RECALL_SPARSE") == "1"
reappear = System.get_env("IPSE_TEST_RECALL_REAPPEAR") == "1"
assert not reappear or sparse
require_single = System.get_env("IPSE_TEST_RECALL_REQUIRE_SINGLE") == "1"
assert not require_single or (sparse and reappear)

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
      if (require_single and step > 1) or (sparse and step == 2) do
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

# In strict one-shot mode, preserve the identity and bytes of both original
# Session sources and their persistent lock inodes across loss and reappearance.
source_fingerprints = fn ->
  Enum.map(source_ids, fn id ->
    journal = Path.join(dir, id <> ".jsonl")
    lock = Path.join(dir, id <> ".lock")
    journal_stat = File.stat!(journal)
    lock_stat = File.stat!(lock)

    %{
      id: id,
      journal_identity: [
        journal_stat.major_device,
        journal_stat.minor_device,
        journal_stat.inode,
        journal_stat.uid
      ],
      journal_sha256: Ipse.JSON.sha256(File.read!(journal)),
      lock_identity: [
        lock_stat.major_device,
        lock_stat.minor_device,
        lock_stat.inode,
        lock_stat.uid
      ]
    }
  end)
end

source_before = if require_single, do: source_fingerprints.()

if require_single do
  File.write!(Path.join(root, "recall-source-before.json"), Jason.encode!(source_before), [
    :exclusive
  ])
end

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
      if require_single do
        assert length(source_ids) == 33 and length(Enum.uniq(source_ids)) == 33

        actual_sources =
          Enum.map(
            rows,
            &(get_in(&1, ["value", "evidence", "sources"]) |> hd() |> Map.fetch!("session_id"))
          )

        assert MapSet.new(actual_sources) == MapSet.new(source_ids)
        hd(rows)
      else
        Enum.find(
          rows,
          &(get_in(&1, ["value", "evidence", "sources"])
            |> List.first()
            |> Map.fetch!("session_id") ==
              source_id)
        )
      end

    assert is_map(first_source)

    unavailable_id =
      if require_single do
        first_source["value"]["evidence"]["sources"] |> hd() |> Map.fetch!("session_id")
      else
        if List.last(rows)["key"] == first_source["key"],
          do: List.last(source_ids),
          else: source_id
      end

    expected =
      Enum.reject(rows, fn row ->
        get_in(row, ["value", "evidence", "sources"]) |> List.first() |> Map.fetch!("session_id") ==
          unavailable_id
      end)

    assert Enum.any?(Enum.drop(rows, 32), &(&1 in expected))
    if require_single, do: assert(length(expected) == 32)
    journal = Path.join(dir, unavailable_id <> ".jsonl")
    refute File.exists?(journal <> ".held")
    File.rename!(journal, journal <> ".held")

    {
      journal,
      Enum.map(expected, & &1["value"]["text"]),
      first_source["value"]["text"],
      Map.new(expected, &{&1["key"], %{text: &1["value"]["text"], revision: &1["revision"]}}),
      first_source["key"]
    }
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

prompt = "Which synthetic notes are available?"

if require_single do
  intent = %{
    "version" => 1,
    "session_id" => session_id,
    "source_ids" => source_ids,
    "missing_source_id" => Path.basename(held_journal, ".jsonl"),
    "expected_later_notes" => length(expected_texts),
    "prompt_sha256" => Ipse.JSON.sha256(prompt),
    "scenario" => "singleton_missing_then_reappears"
  }

  File.write!(Path.join(root, "recall-one-shot-intent.json"), Jason.encode!(intent), [:exclusive])
end

server =
  Task.async(fn ->
    try do
      {:ok, socket} = :gen_tcp.accept(listener, 180_000)
      Ipse.Test.RecallDiagnostic.listener(owner, "accepted", 0, nil)

      try do
        request =
          case :gen_tcp.recv(socket, 0, provider_timeout + 1_000) do
            {:ok, first} ->
              Ipse.Test.RecallDiagnostic.listener(owner, "first_read", byte_size(first), "ok")
              {:ok, Ipse.Test.ProviderFixture.request(socket, first)}

            {:error, :closed} ->
              Ipse.Test.RecallDiagnostic.listener(owner, "first_read", 0, "closed")
              :closed

            other ->
              flunk("Synthetic provider initial read failed: #{inspect(other)}")
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

diagnostic_started = System.monotonic_time(:microsecond)
assert :ok = Ipse.Session.prompt(session, prompt)

{request, diagnostic} =
  case Ipse.Test.RecallDiagnostic.request(session, server, root, nil, diagnostic_started) do
    {:ok, request, diagnostic} ->
      {request, diagnostic}

    {:ended, status} ->
      flunk("Recall ended " <> status <> " before dispatch; bounded outcome saved")
  end

wire = Jason.encode!(request["messages"])

parts =
  if require_single do
    # The selected user-role wrapper contains host-rendered extension items.
    # Decode literal note_parts_v1 and reconstruct each key's exact full text.
    prefix =
      Ipse.Extension.render_context(%{"knowledge" => []})
      |> String.replace_suffix("[]", "")

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
      |> Enum.filter(fn item ->
        get_in(item, ["provenance", "instance"]) == "knowledge" and
          is_binary(item["id"]) and String.starts_with?(item["id"], "note_text_")
      end)
      |> Enum.flat_map(fn item ->
        assert {:ok, group} = Jason.decode(item["text"])
        assert group["format"] == "note_parts_v1"
        assert group["fields"] == ~w(key revision read_operation_id offset_bytes total_bytes text)
        assert Enum.all?(group["records"], &(is_list(&1) and length(&1) == 6))
        Enum.map(group["records"], &Map.new(Enum.zip(group["fields"], &1)))
      end)

    assert MapSet.new(Enum.map(parts, & &1["key"])) == MapSet.new(Map.keys(expected_notes))
    refute Enum.any?(parts, &(&1["key"] == missing_key or &1["text"] == missing_text))

    for {key, expected} <- expected_notes do
      expected_text = expected.text
      selected = Enum.filter(parts, &(&1["key"] == key))
      assert selected != []

      {text, offset} =
        Enum.reduce(selected, {"", 0}, fn part, {text, offset} ->
          assert part["revision"] == expected.revision
          assert is_binary(part["read_operation_id"])
          assert part["offset_bytes"] == offset
          assert part["total_bytes"] == byte_size(expected_text)
          assert is_binary(part["text"]) and String.valid?(part["text"])
          {text <> part["text"], offset + byte_size(part["text"])}
        end)

      assert text == expected_text and offset == byte_size(expected_text)
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
assert :ok = Ipse.Test.RecallDiagnostic.complete(session, server, diagnostic)

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

if require_single do
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

if require_single do
  assert source_before == source_fingerprints.()
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
  {:ok, after_resume} = Ipse.Journal.load(dir, session_id)
  assert Enum.filter(after_resume, &(&1["type"] in effect_types)) == intents
  source_after = source_fingerprints.()
  assert source_before == source_after

  File.write!(Path.join(root, "recall-source-after.json"), Jason.encode!(source_after), [
    :exclusive
  ])

  result = %{
    "version" => 1,
    "session_id" => session_id,
    "included" => included,
    "expected" => expected_count,
    "coverage" => coverage["coverage"],
    "request_sha256" => Ipse.JSON.digest([request]),
    "source_identities_unchanged" => true,
    "same_session_reopened_without_new_intent" => true
  }

  File.write!(Path.join(root, "recall-one-shot-result.json"), Jason.encode!(result), [:exclusive])
end

if held_journal && File.exists?(held_journal <> ".held"),
  do: File.rename!(held_journal <> ".held", held_journal)

IO.puts("NATIVE_NOTE_RECALL_MANY_PASSED")
