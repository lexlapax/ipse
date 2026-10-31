ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)

for key <-
      ~w(IPSE_PROVIDER IPSE_MODEL IPSE_SANDBOX IPSE_MAX_STEPS IPSE_CONTEXT_BYTES IPSE_COMPACT IPSE_SUBAGENTS IPSE_SUBAGENT_CONCURRENCY IPSE_TIMEOUT_MS IPSE_MAX_OUTPUT_TOKENS IPSE_PROFILE IPSE_CONFIG),
    do: System.delete_env(key)

[root, mode] = System.argv()
home = Path.join(root, "home")
cwd = Path.join(root, "work")
fixture = root |> Path.join("pending-management.json") |> File.read!() |> Jason.decode!()
System.put_env("IPSE_HOME", home)
directory = Path.join(home, "knowledge-management")
before_management = Path.wildcard(Path.join(directory, "*.jsonl"))
before_sessions = Path.wildcard(Path.join(fixture["history_dir"], "*.jsonl"))
assert {:ok, binding} = Ipse.Extension.ProjectIdentity.existing(home, cwd)
control = Ipse.Extension.SemanticAdmission.control_root(home)

assert {:ok, before_control} =
         Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])

if mode == "host-orchestrated-owner-loss" do
  File.write!(Path.join(root, "public-review-pid"), System.pid(), [:exclusive])
end

options = [
  "--cwd",
  cwd,
  "--config",
  Path.join(home, "config.json"),
  "--no-project-config"
]

code =
  if mode == "index" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert 0 === Ipse.CLI.run(["knowledge", "review", "--json"] ++ options)
      end)

    assert {:ok, index} = Ipse.JSON.decode_unique(output)
    assert index["kind"] === "historical_pending_index"
    assert index["current_note_eligibility"] === "not_checked"
    assert Enum.any?(index["records"], &(&1["key"] === fixture["key"]))

    assert Enum.all?(
             index["records"],
             &(Enum.sort(Map.keys(&1)) === ~w(bytes key revision sha256))
           )

    IO.write(output)
    0
  else
    Ipse.CLI.run(
      [
        "knowledge",
        "review",
        fixture["key"],
        "--state-dir",
        fixture["history_dir"]
      ] ++ options
    )
  end

assert before_sessions === Path.wildcard(Path.join(fixture["history_dir"], "*.jsonl"))

assert {:ok, after_control} =
         Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])

if mode in ~w(index pipe budget) do
  assert code === if(mode == "index", do: 0, else: 1)
  assert before_management === Path.wildcard(Path.join(directory, "*.jsonl"))
  assert before_control === after_control
else
  [path] = Path.wildcard(Path.join(directory, "*.jsonl")) -- before_management
  assert {:ok, %{events: records, tail: :none}} = Ipse.Journal.read_path(path)
  new_ids = Map.keys(after_control["operations"]) -- Map.keys(before_control["operations"])
  assert [id] = new_ids
  operation = after_control["operations"][id]
  assert operation["status"] === "settled"
  assert operation["headless"] === false
  assert operation["operation"] === "notes.capture"

  if mode == "host-orchestrated" do
    assert code === 0
    [event] = Enum.filter(records, &(&1["type"] === "pending_proposal_accepted"))
    assert Ipse.Session.PendingAcceptance.valid_event?(event)
    assert event["facts"]["operation_id"] === id
    assert operation["actual"]["operations"] === 1
    assert operation["actual"]["input_bytes"] > 0
    assert operation["actual"]["output_bytes"] > 0
    assert operation["actual"]["model_calls"] === 0
    assert operation["receipt"]["event_sha256"] === Ipse.JSON.digest([event])

    assert {:ok, %{"control_status" => "settled", "journal_status" => "committed"}} =
             Ipse.CLI.Knowledge.Management.operation(
               %{home: home},
               cwd,
               event["facts"]["journal_id"]
             )

    assert {:ok, %{"control_status" => "settled", "journal_status" => "unavailable"}} =
             Ipse.CLI.Knowledge.Management.operation(%{home: home}, cwd, id)

    for {selected, journal_status} <- [
          {event["facts"]["journal_id"], "committed"},
          {id, "unavailable"}
        ] do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert 0 === Ipse.CLI.run(["knowledge", "operation", selected, "--json"] ++ options)
        end)

      assert {:ok, inspected} = Ipse.JSON.decode_unique(output)
      assert inspected["control_status"] === "settled"
      assert inspected["journal_status"] === journal_status
      assert inspected["replayed"] === false
    end

    assert {:ok, ^after_control} =
             Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])

    assert {:ok, %{event: ^event, result: %{"status" => "committed", "receipt" => receipt}}} =
             Ipse.Session.PendingAcceptance.resolve_committed(
               records,
               event["facts"]["journal_id"],
               Ipse.JSON.digest([event])
             )

    File.write!(
      Path.join(root, "pending-management-host-orchestrated.json"),
      Jason.encode!(%{"event" => event, "receipt" => receipt}),
      [:exclusive]
    )
  else
    assert code === 1
    assert operation["actual"] === Ipse.Extension.Consent.zero()

    refute Enum.any?(
             records,
             &(&1["type"] in ~w(pending_proposal_accepted pending_acceptance_intent pending_acceptance_result))
           )
  end
end

IO.puts("PUBLIC_PENDING_REVIEW_#{String.upcase(mode)}_PASSED")
