ExUnit.start(autorun: false)
import ExUnit.Assertions
alias Ipse.{InferenceSlots, JSON}
alias Ipse.InferenceSlots.{Ledger, Store}
{:ok, _} = Application.ensure_all_started(:ipse)
[root, scenario] = System.argv()
home = Path.join(root, "operator")
cwd = Path.join(root, "workspace")
File.mkdir!(home)
File.chmod!(home, 0o700)
File.mkdir!(cwd)
System.put_env("IPSE_HOME", home)
config = %{home: home}
{:ok, context} = Store.context(home, cwd)
{:ok, lease} = Store.acquire_service(context, 0, 1000)
:ok = Ipse.Runner.Transaction.release(lease)
id = Ipse.Usage.id()
now = System.system_time(:millisecond)
origins = ["http://127.0.0.1:11434", "http://localhost:11434"]

meta = %{
  "session_id" => Ipse.Usage.id(),
  "project_id" => JSON.sha256("synthetic project"),
  "request_sha256" => JSON.sha256("synthetic request"),
  "route_sha256" => JSON.sha256("synthetic route"),
  "priority" => "foreground",
  "dispatch_timeout_ms" => 5000
}

{:ok, _} =
  Store.transaction(context, fn state ->
    {:ok, queued, _} = Ledger.enqueue(state, "local", origins, id, meta, now, 5000)
    Ledger.admit(queued, id, now)
  end)

{:ok, before} = InferenceSlots.status(config, cwd: cwd)
control = Path.join(context.root, "control.json")
before_bytes = File.read!(control)
slot_lock = Path.join([context.root, "objects", "slot-0", ".lock"])
before_slot_inode = File.stat!(slot_lock).inode
before_ledger_inode = File.stat!(Path.join(context.root, ".lock")).inode

if scenario == "race" do
  spawn_link(fn ->
    wait = fn wait ->
      if File.exists?(Path.join(root, "reconciliation-review-ready")) do
        {:ok, _} =
          Store.transaction(context, fn state ->
            Ledger.enqueue(
              state,
              "local",
              origins,
              Ipse.Usage.id(),
              meta,
              System.system_time(:millisecond),
              5000
            )
          end)

        File.write!(Path.join(root, "guard-review-ready"), "ready")
      else
        Process.sleep(5)
        wait.(wait)
      end
    end

    wait.(wait)
  end)
end

args = [
  "inference",
  "reconcile",
  "local",
  id,
  Integer.to_string(before["revision"]),
  "--cwd",
  cwd
]

result = Ipse.CLI.run(args)
{:ok, after_state} = InferenceSlots.status(config, cwd: cwd)

if scenario == "confirm" do
  assert result == 0
  assert is_nil(after_state["services"]["local"]["active"])
  [receipt] = after_state["recent"]
  assert receipt["id"] == id and receipt["status"] == "reconciled"
  assert Ledger.receipt?(receipt["receipt"])
  assert receipt["receipt"]["reason"] == "shared_service_reconciled"
  assert receipt["receipt"]["expected_revision"] == before["revision"]
  assert Ipse.CLI.run(args) == 1
  IO.puts("INFERENCE_RECONCILIATION_CONFIRMED")
else
  assert result == 1
  assert after_state["services"]["local"]["active"] == before["services"]["local"]["active"]
  assert after_state["recent"] == []

  if scenario == "race" do
    assert after_state["revision"] > before["revision"]
  else
    assert File.read!(control) == before_bytes
  end

  IO.puts("INFERENCE_RECONCILIATION_REFUSED")
end

assert File.stat!(Path.join(context.root, ".lock")).inode == before_ledger_inode
assert File.stat!(slot_lock).inode == before_slot_inode

refute File.exists?(Path.join(home, "config.json"))
refute File.exists?(Path.join(home, "sessions"))
