# Native assertion/publication seed. Record the caller's actual runtime cohort;
# dated upgrade evidence retains its original matched runtime separately.
ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
[root, mode] = System.argv()
true = mode in ["seed", "pair", "wide", "split"]

for key <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
    do: System.delete_env(key)

home = Path.join(root, "home")
cwd = Path.join(root, "project")

for path <- [home, cwd] do
  File.mkdir_p!(path)
  File.chmod!(path, 0o700)
end

System.put_env("IPSE_HOME", home)
config_path = Path.join(home, "config.json")

File.write!(
  config_path,
  Jason.encode!(%{"version" => 1, "settings" => %{"provider" => "demo", "model" => "scripted"}})
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

assert {:ok, session} =
         DynamicSupervisor.start_child(
           Ipse.Sessions,
           {Ipse.Session, [config: config, cwd: cwd, state_dir: dir, subscriber: self()]}
         )

id = Ipse.Session.info(session).id
admission = :sys.get_state(session).config.semantic_admission
assert admission["status"] == "active"
assert {:ok, channel} = Ipse.Session.open_input_channel(session, self())

texts =
  case mode do
    "seed" ->
      ["SYNTHETIC_LITERAL_A_PRIVATE"]

    "pair" ->
      ["SYNTHETIC_LITERAL_A_PRIVATE", "SYNTHETIC_LITERAL_B_PRIVATE"]

    mode when mode in ["wide", "split"] ->
      for n <- 1..8,
          do: "SYNTHETIC_WIDE_NOTE_#{n}_" <> String.duplicate(<<96 + n>>, 950)
  end

text = hd(texts)

{session, _channel, session_ids} =
  Enum.reduce(Enum.with_index(texts, 1), {session, channel, [id]}, fn {statement, number},
                                                                      {current, input_channel,
                                                                       ids} ->
    {current, input_channel, ids} =
      if mode == "split" and number == 5 do
        assert :ok = Ipse.Session.close_confirmed(current)

        assert {:ok, next} =
                 DynamicSupervisor.start_child(
                   Ipse.Sessions,
                   {Ipse.Session, [config: config, cwd: cwd, state_dir: dir, subscriber: self()]}
                 )

        assert {:ok, next_channel} = Ipse.Session.open_input_channel(next, self())
        {next, next_channel, ids ++ [Ipse.Session.info(next).id]}
      else
        {current, input_channel, ids}
      end

    command = "/remember ordinary " <> statement
    File.write!(Path.join(root, "supersession-input-#{number}"), command)
    IO.write("IPSE_SUPERSESSION_READ_#{number}> ")

    assert {:ok, ^command, witness} =
             Ipse.Session.observe_channel(current, input_channel, %{"kind" => "prompt"}, 30_000)

    assert {:ok, ticket} = Ipse.Session.stage_input(current, input_channel, command, witness)

    assert {:ok, %{"render_id" => render}} =
             Ipse.Session.prepare_assertion(current, input_channel, command, ticket)

    assert {:ok, input, answer_witness} =
             Ipse.Session.observe_channel(
               current,
               input_channel,
               %{"kind" => "assertion", "render_id" => render},
               30_000
             )

    assert :ok =
             Ipse.Session.accept_assertion_observed(
               current,
               input_channel,
               render,
               input,
               answer_witness
             )

    assert_receive {:ipse, ^current, {:done, :ok}}, 15_000
    {current, input_channel, ids}
  end)

assert :ok = Ipse.Session.close_confirmed(session)
closed_at = System.system_time(:millisecond)
assert closed_at < admission["policy"]["settings"]["expires_at_ms"]

events =
  Enum.flat_map(session_ids, fn session_id ->
    assert {:ok, current_events} = Ipse.Journal.load(dir, session_id)
    current_events
  end)

assert Enum.map(Enum.filter(events, &(&1["type"] == "operator_assertion")), & &1["text"]) == texts

publications =
  Enum.filter(
    events,
    &(&1["type"] == "extension_action_result" and
        get_in(&1, ["request", "op"]) == "collection.managed")
  )

assert length(publications) == length(texts)
assert Enum.all?(publications, &(get_in(&1, ["outcome", "status"]) == "ok"))

refute Enum.any?(events, &(&1["type"] == "inference_dispatch_intent"))
collection = Ipse.Extension.SemanticAdmission.collection_root(home)
namespace = admission["pin"]["namespace"]

assert {:ok, snapshot} =
         Ipse.Extension.Collection.execute(
           collection,
           namespace,
           %{"op" => "snapshot"},
           Ipse.Usage.id()
         )

assert {:ok, page} =
         Ipse.Extension.Collection.scan_visible(
           collection,
           namespace,
           %{
             "op" => "scan",
             "after" => nil,
             "generation" => snapshot["generation"],
             "limit" => 4
           },
           Ipse.Usage.id()
         )

records =
  if page["next"] do
    assert {:ok, next} =
             Ipse.Extension.Collection.scan_visible(
               collection,
               namespace,
               %{
                 "op" => "scan",
                 "after" => page["next"],
                 "generation" => snapshot["generation"],
                 "limit" => 4
               },
               Ipse.Usage.id()
             )

    assert is_nil(next["next"])
    page["records"] ++ next["records"]
  else
    page["records"]
  end

assert length(records) == length(texts)

record_sources =
  Enum.map(records, fn row ->
    assert [proof] = row["value"]["evidence"]["sources"]
    assert proof["origin"] == "native_operator_assertion" and proof["session_id"] in session_ids
    proof["session_id"]
  end)

if mode == "split", do: assert(Enum.frequencies(record_sources) == Map.new(session_ids, &{&1, 4}))
record = Enum.find(records, &(&1["value"]["text"] == text))
assert record["value"]["text"] == text
assert [proof] = record["value"]["evidence"]["sources"]
assert proof["origin"] == "native_operator_assertion" and proof["session_id"] == id

other =
  if mode == "pair" do
    other = Enum.find(records, &(&1["value"]["text"] == "SYNTHETIC_LITERAL_B_PRIVATE"))
    assert [other_proof] = other["value"]["evidence"]["sources"]

    assert other_proof["origin"] == "native_operator_assertion" and
             other_proof["session_id"] == id

    other
  end

File.write!(
  Path.join(root, "literal-ab-seed.json"),
  Jason.encode!(
    Map.merge(
      %{
        "session_id" => id,
        "namespace" => namespace,
        "key" => record["key"],
        "text" => text,
        "policy" => admission["policy"],
        "closed_at_ms" => closed_at,
        "generation" => snapshot["generation"],
        "source_journal" => Path.join(dir, id <> ".jsonl"),
        "source_sha256" => Ipse.JSON.sha256(File.read!(Path.join(dir, id <> ".jsonl")))
      },
      cond do
        other ->
          %{"other_key" => other["key"]}

        mode in ["wide", "split"] ->
          %{
            "keys" => Enum.map(records, & &1["key"]),
            "source_journals" =>
              Enum.map(session_ids, fn session_id ->
                path = Path.join(dir, session_id <> ".jsonl")

                %{
                  "session_id" => session_id,
                  "path" => path,
                  "sha256" => Ipse.JSON.sha256(File.read!(path))
                }
              end)
          }

        true ->
          %{}
      end
    )
  )
)

IO.puts(
  "GENUINE_LITERAL_AB_HISTORICAL_SEED_PASSED consent_future_at_shutdown=true generation=" <>
    to_string(snapshot["generation"])
)
