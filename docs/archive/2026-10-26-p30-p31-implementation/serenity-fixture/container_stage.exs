# Review-only container transaction driver. It is disabled and must not be
# enabled until the private helper, cgroup, mount and cleanup are independently
# reviewed. No workspace, device or network side effects occur when disabled.
defmodule IpsePrivateContainerStage do
  alias Ipse.Runner.Transaction, as: T
  alias Ipse.Session.Resources
  @enabled false
  @root "/work/mount/transaction"
  @pending ".pending-" <> String.duplicate("b", 32)
  @size 8_388_608

  def run do
    if @enabled, do: run_review_only(), else: {:error, :fixture_disabled}
  end

  defp run_review_only do
    {:ok, scope} = Resources.start(self())
    Resources.bind(scope)

    result =
      Resources.file_effect(fn ->
        with {:ok, cap} <- T.acquire(Path.join(@root, ".lock"), cwd: @root, timeout_ms: 90_000),
             :ok <- T.quota(cap, :flat, 67_108_864),
             {:os_pid, pid} when is_integer(pid) and pid > 0 <- :erlang.port_info(cap.port, :os_pid) do
          # The controller must correlate this live Port with its peer, scope,
          # process identity, exact pending FD and bounded pause deadline.
          IO.puts("PORT #{pid}")
          result = T.stage(cap, ".", [{@pending, :binary.copy("x", @size)}])

          case result do
            :ok -> {result, T.check(cap), T.release(cap)}
            {:unknown, _} -> {result, :not_checked, :not_released}
            other -> {other, :not_checked, :not_released}
          end
        end
      end)

    receipt = Resources.finish(scope)
    {result, receipt}
  end
end

case IpsePrivateContainerStage.run() do
  {:error, :fixture_disabled} ->
    IO.puts(:stderr, "Private container stage is disabled pending independent review.")
    System.halt(2)

  result ->
    IO.inspect(result, label: "Private stage result", limit: 10)
end
