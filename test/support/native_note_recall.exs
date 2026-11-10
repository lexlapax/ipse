ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file(Path.expand("provider_fixture.ex", __DIR__))
Code.require_file(Path.expand("native_recall_filler.exs", __DIR__))
Code.require_file(Path.expand("native_recall_reuse.exs", __DIR__))

for key <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
    do: System.delete_env(key)

defmodule NativeNoteRecall do
  import ExUnit.Assertions

  def server do
    owner = self()
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        try do
          for number <- 1..4 do
            {:ok, socket} = :gen_tcp.accept(listener, 40_000)

            try do
              {_, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
              send(owner, {:native_recall_body, number, self(), Jason.decode!(bytes)})
              if number == 4, do: receive(do: (:release -> :ok))

              body =
                Jason.encode!(%{
                  "model" => "synthetic",
                  "message" => %{
                    "role" => "assistant",
                    "content" => "Synthetic native recall answer #{number}."
                  },
                  "done" => true,
                  "prompt_eval_count" => 1,
                  "eval_count" => 1
                }) <> "\n"

              result =
                :gen_tcp.send(
                  socket,
                  "HTTP/1.1 200 Fixture\r\ncontent-type: application/x-ndjson\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                    body
                )

              assert result == :ok or
                       (number == 4 and result in [{:error, :closed}, {:error, :einval}])
            after
              :gen_tcp.close(socket)
            end
          end
        after
          :gen_tcp.close(listener)
        end
      end)

    {"http://127.0.0.1:#{port}", task}
  end

  def body(session, number, dir) do
    receive do
      {:native_recall_body, ^number, server, body} -> {server, body}
      {:ipse, ^session, {:error, reason}} -> flunk("native recall refused: " <> inspect(reason))
    after
      12_000 ->
        {:ok, events} = Ipse.Journal.load(dir, Ipse.Session.info(session).id)

        flunk(
          "native recall body #{number} unavailable; events=" <>
            Jason.encode!(diagnostics(events)) <>
            "; phase=" <> inspect(Ipse.Session.info(session).phase)
        )
    end
  end

  def diagnostics(events),
    do:
      Enum.map(events, fn e ->
        Map.take(e, ~w(type stage status error reason))
        |> Map.merge(%{
          "op" => get_in(e, ["request", "op"]),
          "inner" => get_in(e, ["request", "request", "op"]),
          "outcome" => if(is_map(e["outcome"]), do: e["outcome"]["status"], else: e["outcome"]),
          "code" => if(is_map(e["outcome"]), do: get_in(e, ["outcome", "value", "code"]))
        })
      end)

  def chronology(events, expected) do
    jobs =
      Enum.filter(
        events,
        &(&1["type"] == "extension_invocation_intent" and
            get_in(&1, ["descriptor", "stage"]) == "event.job")
      )

    assert length(jobs) == expected

    assert Enum.all?(
             jobs,
             &(&1["version"] == 3 and
                 get_in(&1, ["semantic_binding", "class"]) == "collection.read")
           )

    for dispatch <- Enum.filter(events, &(&1["type"] == "inference_dispatch_intent")) do
      before = Enum.take_while(events, &(&1 != dispatch))
      turn = dispatch["turn_id"]

      completed =
        Enum.flat_map(before, fn event ->
          if event["type"] == "extension_event_intent" and event["turn_id"] == turn do
            Enum.filter(
              before,
              &(&1["type"] == "extension_event_result" and
                  &1["delivery_id"] == event["delivery_id"] and
                  &1["outcome"] in ~w(completed failed) and &1["cleanup_confirmed"])
            )
          else
            []
          end
        end)

      assert length(completed) == 1
    end
  end

  def recall_reads(events, mode \\ :normal) do
    observed = Enum.filter(events, &(&1["type"] == "managed_read_observed"))
    assert length(observed) == if(mode == :too_small, do: 2, else: 5)

    indexes =
      Enum.filter(events, fn event ->
        event["type"] == "extension_action_result" and
          get_in(event, ["request", "op"]) == "collection.call" and
          get_in(event, ["request", "request", "op"]) == "index"
      end)

    assert Enum.map(indexes, &get_in(&1, ["request", "request", "limit"])) == [32, 1]
    assert Enum.all?(indexes, &(get_in(&1, ["outcome", "status"]) == "ok"))

    assert get_in(hd(indexes), ["outcome", "value", "generation"]) ==
             get_in(List.last(indexes), ["outcome", "value", "generation"])

    gets =
      Enum.filter(events, fn event ->
        event["type"] in ~w(extension_action_intent extension_action_result) and
          get_in(event, ["request", "op"]) == "collection.call" and
          get_in(event, ["request", "request", "op"]) == "get"
      end)

    if mode == :too_small do
      assert gets == []

      assert Enum.sort(Enum.map(observed, & &1["operation_id"])) ==
               Enum.sort(Enum.map(indexes, & &1["operation_id"]))
    else
      results = Enum.filter(gets, &(&1["type"] == "extension_action_result"))
      assert length(results) == 3
      assert Enum.all?(results, &(get_in(&1, ["outcome", "status"]) == "ok"))
    end
  end
end

[root, mode] = System.argv()
assert mode in ~w(save save_race save_reuse save_reuse_seed)
home = Path.join(root, "home")
cwd = Path.join(root, "work")

for path <- [home, cwd] do
  File.mkdir_p!(path)
  File.chmod!(path, 0o700)
end

System.put_env("IPSE_HOME", home)
{base, server} = NativeNoteRecall.server()
config_path = Path.join(home, "config.json")
{fillers, filler_config} = NativeRecallFiller.entries(root, home)

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
        "timeout_ms" => 5000
      }
    },
    "roles" => %{"main" => "recall"},
    "inference_services" => %{"local" => %{"version" => 1, "origins" => [base]}},
    "extensions" => filler_config["extensions"],
    "extension_trust" => filler_config["extension_trust"]
  })
)

File.chmod!(config_path, 0o600)
cli_args = ["--cwd", cwd, "--config", config_path, "--no-project-config"]
assert Ipse.CLI.run(["knowledge", "enable"] ++ cli_args) == 0

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
assert config.provider == :ollama and config.base_url == base
dir = Path.join(home, "sessions")
opts = [config: config, cwd: cwd, state_dir: dir, subscriber: self()]
assert {:ok, source} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
source_id = Ipse.Session.info(source).id
assert :sys.get_state(source).config.semantic_admission["status"] == "active"
IO.puts("IPSE_ASSERTION_CLI_READY")
assert Ipse.CLI.Terminal.interact(source, Process.monitor(source), true, nil, cwd) == 0
assert {:ok, source_events} = Ipse.Journal.load(dir, source_id)
assert Enum.count(source_events, &(&1["type"] == "operator_assertion")) == 3
refute Enum.any?(source_events, &(&1["type"] == "inference_dispatch_intent"))
pin = :sys.get_state(source).config.semantic_admission["pin"]
collection = Ipse.Extension.SemanticAdmission.collection_root(home)

{:ok, snapshot} =
  Ipse.Extension.Collection.execute(
    collection,
    pin["namespace"],
    %{"op" => "snapshot"},
    Ipse.Usage.id()
  )

{:ok, page} =
  Ipse.Extension.Collection.scan_visible(
    collection,
    pin["namespace"],
    %{
      "op" => "scan",
      "after" => nil,
      "generation" => snapshot["generation"],
      "limit" => 4
    },
    Ipse.Usage.id()
  )

assert length(page["records"]) == 3
assert :ok = Ipse.Session.close_confirmed(source)
assert {:ok, closed_source_events} = Ipse.Journal.load(dir, source_id)
assert Enum.take(closed_source_events, length(source_events)) == source_events
assert {:ok, session} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
id = Ipse.Session.info(session).id
assert :ok = Ipse.Session.prompt(session, "What current references are available?")
{_, first} = NativeNoteRecall.body(session, 1, dir)
for row <- page["records"], do: assert(Jason.encode!(first) =~ row["value"]["text"])
assert_receive {:ipse, ^session, {:done, :ok}}, 15_000

assert {:ok, consumer_sources} =
         Ipse.Session.sources(session, "source.list", %{"limit" => 32, "cursor" => nil})

refute Enum.any?(consumer_sources["sources"], &(&1["origin"] == "native_operator_assertion"))
assert {:ok, first_events} = Ipse.Journal.load(dir, id)
NativeNoteRecall.chronology(first_events, 1)
NativeNoteRecall.recall_reads(first_events)
refute Enum.any?(first_events, &(&1["type"] in ~w(extension_inference_intent decision_intent)))

# Worker input may reuse a native record result only at the identical root.
# Count the records each native batch reads; every check that follows the
# read still decides the outcome.
if mode in ~w(save_reuse save_reuse_seed) do
  alias Ipse.Extension.{Collection, Consent, SemanticAdmission}
  state = :sys.get_state(session)
  context = %{config: state.config, cwd: cwd, session_id: state.id, history_dir: dir}
  keys = Enum.map(page["records"], & &1["key"])
  dependencies = NativeRecallReuse.literals(first_events)
  assert Enum.sort(Enum.map(dependencies, & &1["subject"]["key"])) == Enum.sort(keys)

  # The expiry control continues from this state in a second runtime whose
  # wall clock starts just before the only note deadline.
  if mode == "save_reuse_seed" do
    facts = Path.join(root, "reuse-expiry.json")
    saved = %{"session" => id, "dependencies" => dependencies}
    File.write!(facts, Jason.encode!(saved), [:exclusive])
    File.chmod!(facts, 0o600)
    assert :ok = Ipse.Session.close_confirmed(session)
    Task.shutdown(server, :brutal_kill)
    IO.puts("NATIVE_NOTE_RECALL_REUSE_SEEDED")
    System.halt(0)
  end

  counter = NativeRecallReuse.start()
  input = &NativeRecallReuse.input(counter, &1, &2)
  root_of = fn result -> result.current |> Enum.map(& &1["collection"]) |> Enum.uniq() end

  # At an unchanged root each protected pass natively reads one record and
  # reproduces the complete earlier result.
  assert {{:ok, expected}, _, true} = input.(context, dependencies)
  assert length(expected.current) == 3
  assert [before_root] = root_of.(expected)
  assert {{:ok, ^expected}, [1, 1], true} = input.(context, dependencies)

  # An unrelated commit changes the root. The first pass finds the difference
  # with its one native read and reads the other records again.
  assert {:ok, current} =
           Collection.execute(
             collection,
             pin["namespace"],
             %{"op" => "snapshot"},
             Ipse.Usage.id()
           )

  assert {:ok, _} =
           Collection.execute(
             collection,
             pin["namespace"],
             %{
               "op" => "commit",
               "expected_generation" => current["generation"],
               "advance_floor" => false,
               "changes" => [
                 %{
                   "key" => "fixture.post_recall_change",
                   "expected_revision" => 0,
                   "value" => %{"synthetic" => true}
                 }
               ]
             },
             Ipse.Usage.id()
           )

  assert {{:ok, changed}, [1, 2, 1], true} = input.(context, dependencies)
  assert [changed_root] = root_of.(changed)
  assert changed_root["generation"] == current["generation"] + 1
  assert changed_root != before_root
  assert changed.proofs == expected.proofs

  assert Enum.map(changed.current, &Map.delete(&1, "collection")) ==
           Enum.map(expected.current, &Map.delete(&1, "collection"))

  assert {{:ok, ^changed}, [1, 1], true} = input.(context, dependencies)

  # Reused records still need their original source. Withdrawing it at the
  # unchanged root withholds the input after the same single native read.
  journal = Path.join(dir, source_id <> ".jsonl")
  File.rename!(journal, journal <> ".held")

  try do
    assert {refused, [1], false} = input.(context, dependencies)
    refute match?({:ok, _}, refused)
  after
    File.rename!(journal <> ".held", journal)
  end

  assert {{:ok, ^changed}, [1, 1], true} = input.(context, dependencies)

  # A Session policy that no longer matches the protected one refuses before
  # any record is read or reused, and leaves the remembered results usable.
  narrowed =
    put_in(
      context,
      [:config, :semantic_admission, "policy", "settings", "sources", "categories"],
      []
    )

  assert {refused, [], false} = input.(narrowed, dependencies)
  refute match?({:ok, _}, refused)
  assert {{:ok, ^changed}, [1, 1], true} = input.(context, dependencies)

  # Forgetting a note changes the root and removes a dependency. The old set
  # refuses; the remaining records are natively read again at the new root.
  preference = Enum.find(page["records"], &(&1["value"]["category"] == "preference"))
  assert Ipse.CLI.run(["knowledge", "forget", preference["key"]] ++ cli_args) == 0
  assert {refused, forgotten_batches, false} = input.(context, dependencies)
  refute match?({:ok, _}, refused)
  assert forgotten_batches in [[1], [1, 2]]

  remaining =
    NativeRecallReuse.union(
      Enum.reject(dependencies, &(&1["subject"]["key"] == preference["key"]))
    )

  assert {{:ok, kept}, [1, 1, 1], true} = input.(context, remaining)
  assert [kept_root] = root_of.(kept)
  assert kept_root["generation"] > changed_root["generation"]
  assert length(kept.current) == 2
  assert {{:ok, ^kept}, [1, 1], true} = input.(context, remaining)

  # Revoked consent refuses before any record is read or reused.
  control = SemanticAdmission.control_root(home)
  assert {:ok, policy} = Consent.snapshot(control, pin["project_id"])
  assert {:ok, _} = Consent.revoke(control, pin["project_id"], policy["epoch"])
  assert {refused, [], false} = input.(context, remaining)
  refute match?({:ok, _}, refused)
  if Process.alive?(session), do: Ipse.Session.close(session)
  Task.shutdown(server, :brutal_kill)
  IO.puts("NATIVE_NOTE_RECALL_REUSE_PASSED")
  System.halt(0)
end

if mode == "save_race" do
  assert {:ok, raced} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
  raced_id = Ipse.Session.info(raced).id
  owner = self()
  ticket = make_ref()

  gate = fn
    :armed, {:in, {:"$gen_call", _, {:managed_output_event_complete, _, _}}}, _ ->
      send(owner, {:recall_ready_for_root_change, ticket, self()})

      receive do
        {:resume_recall, ^ticket} -> :done
      after
        15_000 -> :timed_out
      end

    state, _, _ ->
      state
  end

  assert :ok = :sys.install(raced, {gate, :armed})
  assert :ok = Ipse.Session.prompt(raced, "Check the current synthetic references.")
  assert_receive {:recall_ready_for_root_change, ^ticket, ^raced}, 10_000

  assert {:ok, current} =
           Ipse.Extension.Collection.execute(
             collection,
             pin["namespace"],
             %{"op" => "snapshot"},
             Ipse.Usage.id()
           )

  assert {:ok, _} =
           Ipse.Extension.Collection.execute(
             collection,
             pin["namespace"],
             %{
               "op" => "commit",
               "expected_generation" => current["generation"],
               "advance_floor" => false,
               "changes" => [
                 %{
                   "key" => "fixture.post_recall_change",
                   "expected_revision" => 0,
                   "value" => %{"synthetic" => true}
                 }
               ]
             },
             Ipse.Usage.id()
           )

  send(raced, {:resume_recall, ticket})

  outcome =
    receive do
      {:native_recall_body, 2, _, body} ->
        for row <- page["records"], do: refute(Jason.encode!(body) =~ row["value"]["text"])
        assert_receive {:ipse, ^raced, {:done, _}}, 15_000
        "provider-withheld"

      {:ipse, ^raced, {:done, :error}} ->
        refute_receive {:native_recall_body, 2, _, _}, 500
        "no-dispatch"
    after
      15_000 -> flunk("post-recall root-change control did not settle")
    end

  assert {:ok, raced_events} = Ipse.Journal.load(dir, raced_id)
  NativeNoteRecall.recall_reads(raced_events)
  if Process.alive?(raced), do: Ipse.Session.close(raced)
  if Process.alive?(session), do: Ipse.Session.close(session)
  Task.shutdown(server, :brutal_kill)
  IO.puts("NATIVE_NOTE_RECALL_RACE_PASSED " <> outcome)
  System.halt(0)
end

# A second, independently admitted publisher consumes almost all host context.
# Compute its final size using the same admission contract, then verify the
# actual Session state and registered-provider body after both publications.
assert {:ok, low} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
NativeRecallFiller.invoke(low, "fill", 8, 1300)
contexts = :sys.get_state(low).extension_contributions
spill = Enum.find(fillers, &(&1.identity["instance"] == "spill"))
knowledge_instance = :sys.get_state(low).config.semantic_admission["instance"]

knowledge_identity =
  Enum.find(
    :sys.get_state(low).config.extensions,
    &(&1.identity["instance"] == knowledge_instance)
  ).identity

layout = Ipse.Session.Reference.layout()

size = NativeRecallFiller.max_size(contexts, spill.identity, layout)

assert is_integer(size)
NativeRecallFiller.invoke(low, "spill", 2, size)
low_state = :sys.get_state(low)

available =
  Ipse.Extension.Context.available(low_state.extension_contributions, knowledge_instance, layout)

assert available["available_bytes"] in 0..128

empty_note = %{
  "id" => "note_text_0",
  "version" => "1",
  "text" => "",
  "priority" => 70,
  "source" => %{"kind" => "assertion", "uri" => nil}
}

assert available["available_bytes"] <
         Ipse.Extension.context_rendered_bytes([empty_note], knowledge_instance)

assert :ok =
         Ipse.Session.prompt(
           low,
           "Show the current synthetic references under a tight context budget."
         )

{_, constrained} = NativeNoteRecall.body(low, 2, dir)
assert Jason.encode!(constrained) =~ String.duplicate("F", 500)
for row <- page["records"], do: refute(Jason.encode!(constrained) =~ row["value"]["text"])
assert_receive {:ipse, ^low, {:done, :ok}}, 15_000
assert Map.keys(:sys.get_state(low).extension_contributions) |> Enum.sort() == ["fill", "spill"]
assert {:ok, low_events} = Ipse.Journal.load(dir, Ipse.Session.info(low).id)
NativeNoteRecall.recall_reads(low_events, :too_small)

after_budget =
  Enum.drop_while(low_events, fn event ->
    event["type"] != "extension_action_result" or event["request"]["op"] != "context.available"
  end)

assert Enum.any?(after_budget, fn event ->
         event["type"] == "extension_action_result" and
           event["request"]["op"] == "context.available" and
           get_in(event, ["outcome", "value", "available_bytes"]) == available["available_bytes"]
       end)

assert Enum.any?(after_budget, fn event ->
         event["type"] == "extension_action_result" and
           event["request"] == %{"op" => "context.publish", "items" => []} and
           event["outcome"]["status"] == "ok" and
           event["identity_sha256"] == Ipse.JSON.digest([knowledge_identity])
       end)

assert Enum.any?(
         low_events,
         &(&1["type"] == "extension_event_result" and &1["outcome"] == "completed")
       )

assert :ok = Ipse.Session.close_confirmed(low)

preference = Enum.find(page["records"], &(&1["value"]["category"] == "preference"))
assert Ipse.CLI.run(["knowledge", "forget", preference["key"]] ++ cli_args) == 0
assert :ok = Ipse.Session.prompt(session, "Refresh the available current references.")
{_, second} = NativeNoteRecall.body(session, 3, dir)
refute Jason.encode!(second) =~ preference["value"]["text"]

for row <- page["records"],
    row != preference,
    do: assert(Jason.encode!(second) =~ row["value"]["text"])

assert hd(first["messages"]) === hd(second["messages"])
assert first["tools"] === second["tools"]
assert_receive {:ipse, ^session, {:done, :ok}}, 15_000
assert {:ok, second_events} = Ipse.Journal.load(dir, id)
NativeNoteRecall.chronology(second_events, 2)
assert Enum.any?(second_events, &(&1["type"] == "managed_preflight_result"))
assert {:ok, restored} = Ipse.Session.Saved.restore(second_events, id)
assert restored.messages === :sys.get_state(session).messages

journal = Path.join(dir, source_id <> ".jsonl")
File.rename!(journal, journal <> ".held")
assert :ok = Ipse.Session.prompt(session, "Continue with unavailable original sources.")
{held, third} = NativeNoteRecall.body(session, 4, dir)
for row <- page["records"], do: refute(Jason.encode!(third) =~ row["value"]["text"])
assert hd(first["messages"]) === hd(third["messages"])
assert first["tools"] === third["tools"]
assert :ok = Ipse.Session.cancel(session)
assert_receive {:ipse, ^session, {:done, :cancelled}}, 5000
send(held, :release)
Task.await(server, 5000)
File.rename!(journal <> ".held", journal)
assert :ok = Ipse.Session.close_confirmed(session)
assert {:ok, before_resume} = Ipse.Journal.load(dir, id)
NativeNoteRecall.chronology(before_resume, 3)

refute Enum.any?(
         before_resume,
         &(get_in(&1, ["message", "content"]) == "Synthetic native recall answer 4.")
       )

assert {:ok, resumed} =
         DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, Keyword.put(opts, :id, id)})

assert {:ok, after_resume} = Ipse.Journal.load(dir, id)
assert Enum.take(after_resume, length(before_resume)) == before_resume
[owner_marker] = Enum.drop(after_resume, length(before_resume))
assert Ipse.Session.ReleaseReceipt.valid_owner_marker?(owner_marker, id)
assert :ok = Ipse.Session.close_confirmed(resumed)
assert {:ok, after_close} = Ipse.Journal.load(dir, id)
assert Enum.take(after_close, length(after_resume)) == after_resume

refute Enum.any?(
         Enum.drop(after_close, length(before_resume)),
         &(&1["type"] == "inference_dispatch_intent")
       )

assert {:ok, ^closed_source_events} = Ipse.Journal.load(dir, source_id)
IO.puts("NATIVE_NOTE_RECALL_PASSED")
