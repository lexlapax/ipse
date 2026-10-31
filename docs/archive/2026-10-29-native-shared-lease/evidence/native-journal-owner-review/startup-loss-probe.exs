ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
alias Ipse.{Session, Journal, Runner}
root = Path.join(System.tmp_dir!(), "ipse-release-startup-loss-review-" <> Ipse.Usage.id())
File.mkdir!(root)
File.chmod!(root, 0o700)
dir = Path.join(root, "state")
opts = [config: %{provider: :demo, model: "fixture", home: root, approval: :deny}, cwd: root, state_dir: dir, subscriber: self()]
{:ok, first} = Session.start_link(opts)
Process.unlink(first)
id = Session.info(first).id
assert :ok = Session.close_confirmed(first)
{:ok, original_events} = Journal.load(dir, id)
assert Enum.count(original_events, &(&1["type"] == "session_release_owner_started")) == 1

source = File.read!("/tmp/ipse-native-journal-review/lib/ipse/session.ex")
target = "         :ok <- verify_resume_lock(actual_lock_mode, locked_events, id),"
assert length(String.split(source, target)) == 2
rendezvous = ~S'''
         :ok <- (send(:persistent_term.get({__MODULE__, :release_review_observer}), {:release_review_after_identity, self(), Ipse.Session.Lock.current()}); receive do :release_review_continue -> :ok after 10_000 -> exit(:release_review_timeout) end),
'''
source = String.replace(source, target, target <> "\n" <> String.trim_trailing(rendezvous))
copy = Path.join(root, "session-rendezvous.ex")
File.write!(copy, source)
:persistent_term.put({Session, :release_review_observer}, self())
Code.compiler_options(ignore_module_conflict: true)
case Kernel.ParallelCompiler.compile([copy], return_diagnostics: true) do
  {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> :ok
  result -> raise inspect(result)
end

parent = self()
starter = spawn(fn -> Process.flag(:trap_exit, true); result = Session.start_link(Keyword.put(opts, :id, id)); send(parent, {:resume_result, result}); receive do :stop -> :ok after 10_000 -> :ok end end)
assert_receive {:release_review_after_identity, resumed, guard}, 5_000
lock_state = :sys.get_state(guard)
assert lock_state.mode == :resume_v1
{:os_pid, helper} = Port.info(lock_state.port, :os_pid)
assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(helper)])
wait = fn wait, check, n ->
  if check.() do :ok else
    assert n > 0
    Process.sleep(10)
    wait.(wait, check, n - 1)
  end
end
wait.(wait, fn -> :sys.get_state(guard).lost end, 500)
{:ok, contender} = Runner.protected_resume_lock(Path.join(dir, id <> ".lock"))
{:ok, before_resume} = Journal.load(dir, id)
assert before_resume == original_events
send(resumed, :release_review_continue)
assert_receive {:resume_result, start_result}, 5_000
{:ok, after_resume} = Journal.load(dir, id)
{:error, _} = Runner.protected_resume_lock(Path.join(dir, id <> ".lock"))
markers = Enum.count(after_resume, &(&1["type"] == "session_release_owner_started"))
IO.inspect(%{root: root, starting_owner_marker_count: 1, owner_markers_while_contender_holds: markers, journal_changed_while_contender_holds: after_resume != before_resume, startup_returned_ok: match?({:ok, _}, start_result), contender_lock_retained: true}, label: "RELEASE_STARTUP_HELPER_LOSS_REVIEW")
if Process.alive?(resumed), do: Process.exit(resumed, :kill)
assert :ok = Runner.unlock_export_candidate(contender)
send(starter, :stop)
