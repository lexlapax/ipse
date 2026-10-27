alias Ipse.Runner.Transaction, as: T
base = "/tmp/ipse-serenity-barrier-benign"
socket = Path.join(base, "control.sock")
root = Path.join(base, "transaction")
:ok = File.mkdir(root)
:ok = File.chmod(root, 0o700)
{:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ifaddr: {:local, socket}])
parent = self()
task = Task.async(fn ->
  Ipse.Session.Resources.file_effect(fn ->
    with {:ok, cap} <- T.acquire(Path.join(root, ".lock"), cwd: root, timeout_ms: 20_000),
         :ok <- T.quota(cap, :flat, 67_108_864) do
      send(parent, :acquired)
      result = T.stage(cap, ".", [{".pending-" <> String.duplicate("b", 32), :binary.copy("x", 65_536)}])
      {result, T.check(cap), T.release(cap)}
    end
  end)
end)
receive do
  :acquired -> :ok
  {ref, value} when ref == task.ref -> raise "transaction stopped early: #{inspect(value)}"
after 10_000 -> raise "acquire timed out"
end
{:ok, peer} = :gen_tcp.accept(listener, 10_000)
{:ok, "R"} = :gen_tcp.recv(peer, 1, 5_000)
nil = Task.yield(task, 100)
:ok = :gen_tcp.send(peer, "G")
{:ok, <<?W, 0::signed-big-32, ?S, 0::signed-big-32>>} = :gen_tcp.recv(peer, 10, 5_000)
{:ok, {:ok, :ok, :ok}} = Task.yield(task, 5_000)
65_536 = File.stat!(Path.join(root, ".pending-" <> String.duplicate("b", 32))).size
:ok = :gen_tcp.close(peer)
:ok = :gen_tcp.close(listener)
IO.puts("private supervised benign final-chunk handshake, write and sync passed")
