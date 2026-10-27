alias Ipse.Runner.Transaction, as: T
alias Ipse.Session.Resources
base = "/tmp/ipse-serenity-barrier-benign"
socket = Path.join(base, "control.sock")
root = Path.join(base, "peer-reject")
:ok = File.mkdir(root)
:ok = File.chmod(root, 0o700)
:ok = File.rm(socket)
helper = "/tmp/ipse-serenity-barrier-graph/project/priv/ipse-runner"
listener = Port.open({:spawn_executable, ~c"/tmp/ipse-serenity-qualification-plan/fixture/peer_listener"}, [:binary, :exit_status, {:line, 1024}, args: [socket, root, helper]])
receive do {^listener, {:data, {:eol, "LISTENING"}}} -> :ok after 5_000 -> raise "listener startup" end
parent = self()
owner = spawn(fn ->
  {:ok, scope} = Resources.start(self())
  Resources.bind(scope)
  result = Resources.file_effect(fn ->
    {:ok, cap} = T.acquire(Path.join(root, ".lock"), cwd: root, timeout_ms: 20_000)
    :ok = T.quota(cap, :flat, 67_108_864)
    send(parent, {:ready, scope, cap.controller})
    T.stage(cap, ".", [{".pending-" <> String.duplicate("b",32), :binary.copy("x",65536)}])
  end)
  send(parent, {:outcome, result})
end)
receive do {:ready,_,_} -> :ok after 5_000 -> raise "transaction startup" end
receive do {^listener, {:data, {:eol, "READY " <> _}}} -> :ok after 5_000 -> raise "peer missing" end
true = Port.command(listener, "1\n")
receive do {^listener, {:exit_status, status}} when status != 0 -> :ok after 5_000 -> raise "expected refusal" end
receive do {:outcome, {:unknown,_}} -> :ok after 5_000 -> raise "expected unknown" end
false = Process.alive?(owner)
IO.puts("private peer rejected mismatched Port OS pid; stage outcome unknown")
