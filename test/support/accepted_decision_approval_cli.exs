ExUnit.start(autorun: false)
import ExUnit.Assertions
Code.require_file("provider_fixture.ex", __DIR__)
Code.require_file("resume_assertions.exs", __DIR__)
{:ok, _} = Application.ensure_all_started(:ipse)

[root, mode] = System.argv()

assert mode in ~w(save_managed_approval save_managed_approval_deny save_managed_approval_display_owners save_managed_approval_journal_loss)

alias Ipse.{Journal, JSON, Session}

alias Ipse.Extension.{
  Catalog,
  Consent,
  ProjectIdentity,
  Registry,
  SemanticAdmission,
  SemanticConsent,
  SemanticRoutes
}

alias Ipse.Test.{ProviderFixture, ResumeAssertions}

assert {:ok, fixture} =
         root |> Path.join("accepted-approval.json") |> File.read!() |> JSON.decode_unique()

home = Path.join(root, "home")
cwd = Path.join(root, "work")
dir = fixture["history_dir"]
note = fixture["record"]
link = fixture["link"]
text = note["value"]["text"]
path = "accepted-" <> mode <> ".txt"
lose? = mode == "save_managed_approval_journal_loss"
observed? = mode in ~w(save_managed_approval_display_owners save_managed_approval_journal_loss)
allowed? = mode in ~w(save_managed_approval save_managed_approval_display_owners)
System.put_env("IPSE_HOME", home)

if observed? do
  Code.require_file("accepted_approval_display.exs", __DIR__)
  Ipse.Test.AcceptedApprovalDisplay.install(Path.join(root, "display-" <> mode))
end

response =
  ProviderFixture.ndjson([
    %{
      "model" => "fixture",
      "message" => %{
        "role" => "assistant",
        "content" => "",
        "tool_calls" => [
          %{
            "function" => %{
              "name" => "write",
              "arguments" => %{"path" => path, "content" => text}
            }
          }
        ]
      },
      "done" => true,
      "prompt_eval_count" => 1,
      "eval_count" => 1
    }
  ])

final =
  ProviderFixture.ndjson([
    %{
      "model" => "fixture",
      "message" => %{"role" => "assistant", "content" => "ACCEPTED_APPROVAL_DONE"},
      "done" => true,
      "prompt_eval_count" => 1,
      "eval_count" => 1
    }
  ])

owner = self()

server =
  Task.async(fn ->
    {base, fixture_server} =
      ProviderFixture.sequence(if(lose?, do: [response], else: [response, final]), 30_000)

    send(owner, {:accepted_approval_provider, self(), base})
    requests = Task.await(fixture_server, 30_000)

    receive do
      {:requests, caller, ref} -> send(caller, {ref, requests})
    after
      30_000 -> flunk("accepted approval requests were not collected")
    end

    :collected
  end)

base =
  receive do
    {:accepted_approval_provider, provider, base} when provider == server.pid -> base
  after
    5_000 -> flunk("accepted approval provider did not start")
  end

assert {:ok, selected} =
         Ipse.Extension.Config.resolve(
           [
             %{scope: "operator", path: "/fixture/config.json", data: fixture["extension_config"]}
           ],
           []
         )

assert {:ok, entries} = Registry.prepare(selected, home)

config =
  %{home: home, extensions: entries, semantic_selections: fixture["semantic_selections"]}
  |> Map.merge(%{
    provider: :ollama,
    base_url: base,
    model: "fixture",
    timeout_ms: 15_000,
    approval: :ask,
    approval_origin: :interactive,
    headless: false,
    operator_questions: true,
    inference_services: %{
      ("accepted_" <> mode) => %{"version" => 1, "origins" => [base]}
    }
  })

assert {:ok, binding} = ProjectIdentity.existing(home, cwd)
control = SemanticAdmission.control_root(home)
assert {:ok, before} = Consent.existing_snapshot(control, binding["project_id"])
assert {:ok, catalog} = Catalog.snapshot(config)
jobs = for row <- catalog["entries"], row["stage"] == "event.job", do: JSON.digest([row])

policy =
  update_in(before["policy"], ["settings", "effects"], fn effects ->
    Enum.reject(effects, &(&1["outer_sha256"] in jobs and &1["class"] == "collection.publish"))
  end)

assert {:ok, selectors} = SemanticRoutes.selectors(policy["settings"]["routes"])
assert {:ok, routes} = SemanticRoutes.resolve(config, selectors)
policy = put_in(policy, ["settings", "routes"], routes)

# The observed child admits its disclosed host overlay before the consumer.
# Rebuild this trusted fixture's saved policy through normal preparation rather
# than borrowing the original host's identity or changing the runtime validator.
selection =
  policy["settings"]
  |> Map.drop(~w(instance identity_sha256))
  |> Map.merge(Map.take(policy, ~w(limits period_ms expires_at_ms headless)))

assert [entry] = entries
assert {:ok, policy} = SemanticConsent.prepare(binding, entry.identity, selection)

assert {:ok, _} =
         Consent.replace(
           control,
           binding["project_id"],
           before["epoch"],
           policy,
           System.system_time(:millisecond)
         )

assert {:ok, selection} = Ipse.Config.Semantics.selection(policy)
config = Map.put(config, :semantic_selections, selection)
originals = Map.new(Path.wildcard(dir <> "/*.jsonl"), &{&1, File.read!(&1)})
journal_path = Path.join([home, "knowledge-management", link["journal_id"] <> ".jsonl"])
management_before = File.read!(journal_path)

assert {:ok, consumer} =
         DynamicSupervisor.start_child(
           Ipse.Sessions,
           {Session, config: config, cwd: cwd, state_dir: dir, subscriber: self()}
         )

id = Session.info(consumer).id
actual = :sys.get_state(consumer).config
assert actual.semantic_admission["status"] == "active"
pin = actual.semantic_admission["pin"]
source_lock = Path.join(dir, note["value"]["source_proof"]["session_id"] <> ".lock")
journal_lock = Path.rootname(journal_path) <> ".lock"
marker = Path.join(root, "accepted-approval-display-checked")

for name <-
      ~w(managed-approval-input-ready managed-approval-control-checked managed-approval-exit-ready),
    do: File.rm(Path.join(root, name))

File.rm(marker)

display =
  if observed? do
    paths = [
      Path.join([home, "project-identities", ".lock"]),
      Path.join([control, binding["project_id"], ".lock"]),
      Path.join([SemanticAdmission.collection_root(home), pin["namespace"], ".lock"]),
      Path.join(dir, id <> ".lock"),
      source_lock,
      journal_lock
    ]

    Ipse.Test.AcceptedApprovalDisplay.observe(consumer, paths, link, lose?, marker)
  end

wait_for = fn path, deadline ->
  wait = fn wait ->
    unless File.exists?(path) do
      assert System.monotonic_time(:millisecond) < deadline, "missing control marker: #{path}"
      Process.sleep(5)
      wait.(wait)
    end
  end

  wait.(wait)
end

wait_idle = fn ->
  deadline = System.monotonic_time(:millisecond) + 20_000

  wait = fn wait ->
    unless :sys.get_state(consumer).phase == :idle do
      assert System.monotonic_time(:millisecond) < deadline
      Process.sleep(5)
      wait.(wait)
    end
  end

  wait.(wait)
end

watcher =
  Task.async(fn ->
    monitor = if lose?, do: Process.monitor(consumer)

    if lose? do
      wait_for.(marker, System.monotonic_time(:millisecond) + 20_000)
      assert_receive {:DOWN, ^monitor, :process, ^consumer, :normal}, 20_000
    else
      wait_for.(
        Path.join(root, "managed-approval-input-ready"),
        System.monotonic_time(:millisecond) + 20_000
      )

      state = :sys.get_state(consumer)
      assert state.phase == :managed_approval and state.share_barrier.phase == :review_input
      assert Enum.any?(state.managed_approval.dependencies, &(&1["version"] === 6))
      assert {:error, _} = Session.approve(consumer, make_ref(), true)

      for lock_path <- [source_lock, journal_lock] do
        assert {:ok, lock} = Ipse.Runner.lock(lock_path)
        assert :ok = Ipse.Runner.unlock(lock)
      end

      File.write!(Path.join(root, "managed-approval-control-checked"), "checked")
    end

    unless lose?, do: wait_idle.()
    File.write!(Path.join(root, "managed-approval-exit-ready"), "ready")

    receive do
      {:inspection_result, caller, ref} -> send(caller, {ref, :input_checked})
    after
      30_000 -> flunk("accepted approval input result was not collected")
    end

    :input_checked
  end)

IO.puts("IPSE_MANAGED_APPROVAL_CLI_READY")

assert if(lose?, do: 1, else: 0) ==
         Ipse.CLI.Terminal.interact(
           consumer,
           Process.monitor(consumer),
           true,
           "Write the accepted decision to the proposed file after my approval, then finish.",
           cwd
         )

for {task, expected} <-
      [{watcher, :input_checked}] ++ if(display, do: [{display, :owners_checked}], else: []) do
  ref = make_ref()
  send(task.pid, {:inspection_result, self(), ref})
  assert_receive {^ref, ^expected}, 5_000
  assert Task.await(task, 5_000) == expected
end

if allowed?,
  do: assert(File.read!(Path.join(cwd, path)) == text),
  else: refute(File.exists?(Path.join(cwd, path)))

assert File.read!(journal_path) == management_before
for {path, bytes} <- originals, do: assert(File.read!(path) == bytes)
assert {:ok, events} = Journal.load(dir, id)
assert {:ok, _} = Session.Saved.restore(events, id)

assert Enum.any?(events, fn event ->
         event["type"] == "managed_read_observed" and
           Enum.any?(event["dependencies"], &(&1["version"] === 6))
       end)

starts = Enum.filter(events, &(&1["type"] == "tool_started"))

if allowed? do
  assert [%{"name" => "write", "approval" => "approved"}] = starts
  assert Enum.count(events, &(&1["type"] == "managed_tool_effect_admitted")) == 1
  assert Enum.count(events, &(&1["type"] == "managed_tool_result_observed")) == 1
else
  assert starts == []
  refute Enum.any?(events, &(&1["type"] == "managed_tool_effect_admitted"))
end

request_ref = make_ref()
send(server.pid, {:requests, self(), request_ref})
assert_receive {^request_ref, requests}, 5_000
assert :collected == Task.await(server, 5_000)
assert length(requests) == if(lose?, do: 1, else: 2)
assert Enum.count(events, &(&1["type"] == "request_admitted")) == length(requests)

assert Enum.all?(
         Enum.filter(events, &(&1["type"] == "request_finished")),
         &(&1["outcome"] == "completed" and &1["finality"] == "final")
       )

rendered = requests |> hd() |> elem(1) |> Jason.encode!()
assert rendered =~ "accepted_decision" and rendered =~ text

if lose?,
  do: refute(Process.alive?(consumer)),
  else: assert(:ok = Session.close_confirmed(consumer))

saved_path = Path.join(dir, id <> ".jsonl")
saved_bytes = File.read!(saved_path)

assert {:ok, resumed} =
         DynamicSupervisor.start_child(
           Ipse.Sessions,
           {Session, config: config, cwd: cwd, state_dir: dir, id: id, subscriber: self()}
         )

ResumeAssertions.assert_idle_resume_journal(saved_path, saved_bytes, id)
assert :sys.get_state(resumed).phase == :idle
assert :ok = Session.close_confirmed(resumed)
IO.puts("NATIVE_ACCEPTED_APPROVAL_#{String.upcase(mode)}_PASSED")
