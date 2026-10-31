ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
alias Ipse.{Journal, Runner, Session}

root = Path.join(System.tmp_dir!(), "ipse-native-journal-loss-" <> Ipse.Usage.id())
File.mkdir!(root)
File.chmod!(root, 0o700)
dir = Path.join(root, "state")

opts = [
  config: %{provider: :demo, model: "fixture", home: root, approval: :deny},
  cwd: root,
  state_dir: dir,
  subscriber: self()
]

{:ok, first} = Session.start_link(opts)
Process.unlink(first)
id = Session.info(first).id
assert :ok = Session.close_confirmed(first)
{:ok, original} = Journal.load(dir, id)

source = File.read!("lib/ipse/session.ex")
target = "         :ok <- verify_resume_lock(actual_lock_mode, locked_events, id),"
assert length(String.split(source, target)) == 2

rendezvous = ~S'''
         :ok <- (send(:persistent_term.get({__MODULE__, :native_journal_observer}), {:native_journal_after_identity, self(), Ipse.Session.Lock.current()}); receive do :native_journal_continue -> :ok after 10_000 -> exit(:native_journal_timeout) end),
'''

copy = Path.join(root, "session-rendezvous.ex")

File.write!(
  copy,
  String.replace(source, target, target <> "\n" <> String.trim_trailing(rendezvous))
)

:persistent_term.put({Session, :native_journal_observer}, self())
Code.compiler_options(ignore_module_conflict: true)

assert {:ok, _, %{compile_warnings: [], runtime_warnings: []}} =
         Kernel.ParallelCompiler.compile([copy], return_diagnostics: true)

parent = self()

starter =
  spawn(fn ->
    Process.flag(:trap_exit, true)
    result = Session.start_link(Keyword.put(opts, :id, id))
    send(parent, {:resume_result, result})
  end)

assert_receive {:native_journal_after_identity, resumed, guard}, 5_000
lock = :sys.get_state(guard)
assert lock.mode == :resume_v1
{:os_pid, helper} = Port.info(lock.port, :os_pid)
assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(helper)])

wait = fn wait, n ->
  cond do
    :sys.get_state(guard).lost ->
      :ok

    n == 0 ->
      flunk("native helper loss not observed")

    true ->
      Process.sleep(10)
      wait.(wait, n - 1)
  end
end

wait.(wait, 500)
{:ok, contender} = Runner.protected_resume_lock(Path.join(dir, id <> ".lock"))
send(resumed, :native_journal_continue)
assert_receive {:resume_result, {:error, _}}, 5_000
assert {:ok, ^original} = Journal.load(dir, id)
assert {:error, _} = Runner.protected_resume_lock(Path.join(dir, id <> ".lock"))
assert :ok = Runner.unlock_export_candidate(contender)
assert not Process.alive?(starter)

IO.inspect(
  %{
    root: root,
    journal_unchanged_while_contender_holds: true,
    startup_refused: true,
    contender_retained_lock: true
  },
  label: "NATIVE_JOURNAL_LOCK_LOSS_CONTROL"
)
