# Second runtime of the worker-input reuse control. The first runtime saved
# three reviewed notes and the dependencies a Session recorded for them. This
# one starts with its wall clock just before the only note deadline, so that
# note expires between two worker inputs while the Collection root stays put.
ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file(Path.expand("native_recall_reuse.exs", __DIR__))

for key <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
    do: System.delete_env(key)

[root] = System.argv()
home = Path.join(root, "home")
cwd = Path.join(root, "work")
System.put_env("IPSE_HOME", home)
config_path = Path.join(home, "config.json")

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

%{"session" => id, "dependencies" => dependencies} =
  root |> Path.join("reuse-expiry.json") |> File.read!() |> Jason.decode!()

# The dependencies name the pin of the Session that recorded them.
opts = [config: config, cwd: cwd, state_dir: dir, subscriber: self(), id: id]
assert {:ok, session} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
state = :sys.get_state(session)
assert state.config.semantic_admission["status"] == "active"
context = %{config: state.config, cwd: cwd, session_id: state.id, history_dir: dir}
pin = state.config.semantic_admission["pin"]
collection = Ipse.Extension.SemanticAdmission.collection_root(home)

generation = fn ->
  assert {:ok, snapshot} =
           Ipse.Extension.Collection.execute(
             collection,
             pin["namespace"],
             %{"op" => "snapshot"},
             Ipse.Usage.id()
           )

  snapshot["generation"]
end

deadline_of = &get_in(&1, ["subject", "validity", "valid_until_ms"])
assert {[dated], [open, later]} = Enum.split_with(dependencies, &is_integer(deadline_of.(&1)))
deadline = deadline_of.(dated)
key = & &1["subject"]["key"]
union = &NativeRecallReuse.union/1
counter = NativeRecallReuse.start()
input = &NativeRecallReuse.input_keys(counter, &1, &2)
before = generation.()

# Before the deadline both records are read natively once and then reused.
assert System.system_time(:millisecond) < deadline - 5_000
pair = union.([dated, open])
assert {{:ok, expected}, [first, [_]], true} = input.(context, pair)
assert Enum.sort(first) == Enum.sort(Enum.map(pair, key))
assert {{:ok, ^expected}, [[_], [_]], true} = input.(context, pair)
assert System.system_time(:millisecond) < deadline

Process.sleep(max(deadline - System.system_time(:millisecond), 0) + 50)
assert System.system_time(:millisecond) > deadline

# The pass natively reads only the record it does not hold. The remembered
# record is checked against the current time and withholds the whole input.
assert {refused, [[unheld]], false} = input.(context, union.([dated, open, later]))
refute match?({:ok, _}, refused)
assert unheld == key.(later)

# The root did not move and the unexpired records remain deliverable.
assert {{:ok, kept}, [[_], [_]], true} = input.(context, union.([open, later]))
assert length(kept.current) == 2
assert Enum.map(kept.current, & &1["collection"]) |> Enum.uniq() |> length() == 1
assert generation.() == before

# A native read of the expired record refuses in the same way.
assert {refused, [[probed]], false} = input.(context, union.([dated]))
refute match?({:ok, _}, refused)
assert probed == key.(dated)

if Process.alive?(session), do: Ipse.Session.close(session)
IO.puts("NATIVE_NOTE_RECALL_REUSE_EXPIRY_PASSED")
System.halt(0)
