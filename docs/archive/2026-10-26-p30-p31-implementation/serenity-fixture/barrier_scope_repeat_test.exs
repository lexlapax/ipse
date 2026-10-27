alias Ipse.Runner.Transaction, as: T
alias Ipse.Session.Resources
base = "/tmp/ipse-serenity-barrier-benign"
socket = Path.join(base, "control.sock")
root = Path.join(base, "scope-repeat")
:ok = File.mkdir(root)
:ok = File.chmod(root, 0o700)
:ok = File.rm(socket)
{:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ifaddr: {:local, socket}])
parent = self()
_owner = spawn(fn ->
  {:ok, scope} = Resources.start(self())
  Resources.bind(scope)
  Resources.file_effect(fn ->
    {:ok, cap} = T.acquire(Path.join(root, ".lock"), cwd: root, timeout_ms: 20_000)
    :ok = T.quota(cap, :flat, 67_108_864)
    send(parent, {:ready, scope, cap.controller})
    result = T.stage(cap, ".", [{".pending-" <> String.duplicate("b", 32), :binary.copy("x", 65_536)}])
    send(parent, {:stage, result})
  end)
end)
{scope, controller} = receive do
  {:ready, scope, controller} -> {scope, controller}
after 10_000 -> raise "acquire timed out"
end
monitor = Process.monitor(controller)
{:ok, peer} = :gen_tcp.accept(listener, 10_000)
{:ok, "R"} = :gen_tcp.recv(peer, 1, 5_000)
pending = Path.join(root, ".pending-" <> String.duplicate("b", 32))
{:ok, before} = File.lstat(pending)
true = before.type == :regular and before.links == 1 and before.size > 0 and before.size < 65_536
finish = Task.async(fn -> Resources.finish(scope) end)
receive do
  {:DOWN, ^monitor, :process, ^controller, _} -> :ok
after 5_000 -> raise "controller did not terminate"
end
{:error, :closed} = :gen_tcp.recv(peer, 1, 5_000)
receive do
  {:stage, {:unknown, _}} -> :ok
  {:stage, other} -> raise "unexpected stage #{inspect(other)}"
after 5_000 -> raise "stage outcome missing"
end
:ok = Task.await(finish, 5_000)
{:ok, after_} = File.lstat(pending)
true = {before.major_device, before.minor_device, before.inode, before.size} == {after_.major_device, after_.minor_device, after_.inode, after_.size}
{:ok, cap} = T.acquire(Path.join(root, ".lock"), cwd: root, timeout_ms: 5_000)
:ok = T.release(cap)
:ok = :gen_tcp.close(peer)
:ok = :gen_tcp.close(listener)
IO.puts("private scoped cancellation: controller down, receipt ok, stable pending inode, fresh lock acquired")
