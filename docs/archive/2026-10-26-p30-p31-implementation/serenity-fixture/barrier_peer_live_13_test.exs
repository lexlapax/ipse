alias Ipse.Runner.Transaction, as: T
alias Ipse.Session.Resources
base = "/tmp/ipse-serenity-barrier-benign"
socket = Path.join(base, "control.sock")
root = Path.join(base, "peer-live-13")
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
  outcome = Resources.file_effect(fn ->
    {:ok, cap} = T.acquire(Path.join(root, ".lock"), cwd: root, timeout_ms: 20_000)
    :ok = T.quota(cap, :flat, 67_108_864)
    {:os_pid, port_os_pid} = :erlang.port_info(cap.port, :os_pid)
    send(parent, {:ready, scope, cap.controller, cap.port, port_os_pid})
    value = T.stage(cap, ".", [{".pending-" <> String.duplicate("b",32), :binary.copy("x",65536)}])
    {value,T.check(cap),T.release(cap)}
  end)
  send(parent, {:outcome, outcome})
  receive do :finish -> send(parent, {:finish, Resources.finish(scope)}) end
end)
{scope, controller, port, pid} = receive do {:ready,s,c,port,p} -> {s,c,port,p} after 5_000 -> raise "transaction startup" end
true = is_pid(scope) and is_pid(controller)
receive do {^listener, {:data, {:eol, "READY " <> detail}}} -> IO.puts("observed private peer " <> detail) after 5_000 -> raise "peer missing" end
true = Process.alive?(scope) and Process.alive?(controller) and Process.alive?(owner)
%{owner: ^owner, resources: resources} = :sys.get_state(scope)
true = Enum.count(resources, fn {_, value} -> value.pid == controller and value.kind == :lock end) == 1
{:os_pid, ^pid} = :erlang.port_info(port, :os_pid)
true = Port.command(listener, Integer.to_string(pid) <> "\n")
receive do {^listener, {:data, {:eol, "REPORT W=0 S=0"}}} -> :ok after 5_000 -> raise "report missing" end
receive do {^listener, {:exit_status, 0}} -> :ok after 5_000 -> raise "listener exit" end
receive do {:outcome, {:ok,:ok,:ok}} -> :ok after 5_000 -> raise "stage outcome" end
send(owner,:finish)
receive do {:finish,:ok} -> :ok after 5_000 -> raise "scope receipt" end
IO.puts("private peer credential, port parent, pidfd, executable and pending FD checks passed")
