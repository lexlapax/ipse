# Private diagnostic only: a source-derived test helper gates a supervised
# Transaction stage. This is not a Session journey or production binary test.
alias Ipse.Runner.Transaction, as: Transaction
alias Ipse.Session.Resources
root = "/work/mount/transaction"
parent = self()
owner = spawn(fn ->
  {:ok, scope} = Resources.start(self())
  Resources.bind(scope)
  outcome = Resources.file_effect(fn ->
    {:ok, cap} = Transaction.acquire(Path.join(root, ".lock"), cwd: root, timeout_ms: 20_000)
    :ok = Transaction.quota(cap, :flat, 67_108_864)
    {:os_pid, pid} = :erlang.port_info(cap.port, :os_pid)
    send(parent, {:ready, self(), scope, cap.controller, cap.port, pid})
    receive do
      :stage ->
        value = Transaction.stage(cap, ".", [{".pending-" <> String.duplicate("b", 32), :binary.copy("x", 65_536)}])
        {value, Transaction.check(cap), Transaction.release(cap)}
    after
      15_000 -> {:error, :stage_not_authorized}
    end
  end)
  send(parent, {:outcome, outcome})
  receive do
    :finish -> send(parent, {:finished, Resources.finish(scope)})
  after
    5_000 -> :ok
  end
end)
{worker, scope, controller, port, pid} =
  receive do
    {:ready, w, s, c, p, os_pid} -> {w, s, c, p, os_pid}
  after
    10_000 -> raise "owner startup unknown"
  end
true = Process.alive?(owner) and Process.alive?(scope) and Process.alive?(controller)
%{owner: ^owner, resources: resources} = :sys.get_state(scope)
true = Enum.count(resources, fn {_, value} -> value.pid == controller and value.kind == :lock end) == 1
{:os_pid, ^pid} = :erlang.port_info(port, :os_pid)
IO.puts("OWNER #{pid}")
if IO.read(:line) != "GO\n", do: raise("stage gate unknown")
true = Process.alive?(owner) and Process.alive?(scope) and Process.alive?(controller)
{:os_pid, ^pid} = :erlang.port_info(port, :os_pid)
send(worker, :stage)
result = receive do {:outcome, value} -> value after 25_000 -> raise "stage outcome unknown" end
send(owner, :finish)
finish = receive do {:finished, value} -> value after 5_000 -> raise "scope cleanup unknown" end
case {result, finish} do
  {{:ok, :ok, :ok}, :ok} -> IO.puts("STAGE_OK SCOPE_OK")
  {{{:error, _}, _, _}, :ok} -> IO.puts("STAGE_ERROR SCOPE_OK")
  _ -> IO.puts("STAGE_UNKNOWN")
end
