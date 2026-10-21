# Synthetic local process fixtures only; no MCP server or model service is used.
defmodule Ipse.Development.Diagnostics.StdioCleanup do
  alias Ipse.Runner

  def main(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [iterations: :integer, concurrency: :integer, sandbox: :string]
      )

    iterations = Keyword.get(opts, :iterations, 100)
    concurrency = Keyword.get(opts, :concurrency, 4)
    sandbox = Keyword.get(opts, :sandbox, "off")

    unless rest == [] and invalid == [] and iterations in 1..1000 and
             concurrency in 1..16 and sandbox in ["off", "native"] do
      raise "usage: mix run scripts/diagnose-stdio-cleanup.exs " <>
              "[--iterations 1..1000] [--concurrency 1..16] [--sandbox off|native]"
    end

    id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    root = Path.join(System.tmp_dir!(), "ipse-stdio-load-#{id}")
    workspace = Path.join(root, "workspace")
    File.mkdir_p!(workspace)
    previous_home = System.get_env("IPSE_HOME")
    System.put_env("IPSE_HOME", Path.join(root, "home"))

    try do
      {:ok, workspace} = Ipse.WorkspaceContext.canonical_path(workspace)
      policy = if sandbox == "native", do: :native, else: :off

      # Warm the signed cache before concurrent launches. Setup must also pass.
      {:ok, port} =
        Runner.open_stdio("/bin/sh", ["-c", "printf warmup"], workspace, %{}, 5_000,
          sandbox: policy
        )

      warmup = collect(port, <<>>, [], now() + 7_000, nil)
      unless valid?(warmup, "warmup", ""), do: raise("warmup failed: #{inspect(warmup)}")

      results =
        1..iterations
        |> Task.async_stream(&trial(&1, workspace, policy),
          max_concurrency: concurrency,
          ordered: false,
          timeout: 15_000,
          on_timeout: :kill_task
        )
        |> Enum.map(fn
          {:ok, result} ->
            result

          {:exit, reason} ->
            failure = %{ok: false, category: "owner_failure", reason: inspect(reason)}
            IO.puts(Jason.encode!(failure))
            failure
        end)

      # Every child is bounded even if the helper fails. Check its actual effect.
      Process.sleep(850)
      effects = File.ls!(workspace) |> Enum.filter(&String.starts_with?(&1, "effect-"))
      failed = Enum.count(results, &(not &1.ok))

      IO.puts(
        Jason.encode!(%{
          summary: true,
          iterations: iterations,
          concurrency: concurrency,
          sandbox: sandbox,
          failures: failed,
          escaped_effects: effects,
          categories: Enum.frequencies_by(results, & &1.category)
        })
      )

      if failed != 0 or effects != [], do: raise("stdio cleanup diagnostic failed")
    after
      if previous_home,
        do: System.put_env("IPSE_HOME", previous_home),
        else: System.delete_env("IPSE_HOME")

      File.rm_rf!(root)
    end
  end

  defp trial(iteration, workspace, policy) do
    Process.flag(:trap_exit, true)
    started = now()
    scenario = Enum.at([:initial_exit, :burst, :delayed_reader], rem(iteration - 1, 3))
    burst = String.duplicate("0123456789abcdef", 512)

    {out, err} =
      if scenario == :initial_exit,
        do: {"done", ""},
        else: {String.duplicate(burst, 8), String.duplicate(burst, 8)}

    output =
      if scenario == :initial_exit,
        do: "printf done",
        else:
          ~S|i=0; while [ "$i" -lt 8 ]; do printf '%s' "$2"; printf '%s' "$2" >&2; i=$((i+1)); done|

    script = ~S[(sleep 0.7; printf escaped > "$1") & ] <> output

    launch = fn ->
      Runner.open_stdio(
        "/bin/sh",
        ["-c", script, "fixture", "effect-#{iteration}", burst],
        workspace,
        %{},
        5_000,
        sandbox: policy
      )
    end

    # Cache preparation uses a nonblocking cross-process lock. Serialize setup,
    # while the launched servers and their cleanup still run concurrently.
    opened =
      if policy == :native, do: :global.trans({__MODULE__, self()}, launch), else: launch.()

    result =
      case opened do
        {:ok, port} ->
          try do
            if scenario == :delayed_reader, do: Process.sleep(100)
            collect(port, <<>>, [], now() + 7_000, nil)
          after
            if Port.info(port), do: Port.close(port)
          end

        {:error, reason} ->
          %{frames: [], status: nil, transport: "launch: #{reason}", pending: ""}
      end

    ok = valid?(result, out, err)
    category = category(result, ok)

    report = %{
      iteration: iteration,
      scenario: scenario,
      elapsed_ms: now() - started,
      ok: ok,
      category: category,
      helper_status: result.status,
      transport: result.transport,
      pending_base64: Base.encode64(result.pending),
      frames:
        Enum.map(result.frames, fn {kind, data} ->
          %{kind: <<kind>>, bytes: byte_size(data), data: data}
        end)
    }

    IO.puts(Jason.encode!(report))
    Map.take(report, [:ok, :category])
  end

  defp collect(port, pending, frames, deadline, transport) do
    receive do
      {^port, {:data, bytes}} ->
        retained = Enum.sum(Enum.map(frames, &(byte_size(elem(&1, 1)) + 5)))
        combined = pending <> bytes

        if retained + byte_size(combined) > 262_144 do
          finish(binary_part(combined, 0, 262_144 - retained), frames, nil, "capture_limit")
        else
          case decode(combined, frames) do
            {:ok, tail, decoded} -> collect(port, tail, decoded, deadline, transport)
            :error -> finish(combined, frames, nil, "malformed_frame")
          end
        end

      {^port, {:exit_status, status}} ->
        finish(pending, frames, status, transport)

      {:EXIT, ^port, reason} ->
        collect(port, pending, frames, deadline, "port_exit: #{inspect(reason)}")
    after
      max(deadline - now(), 0) -> finish(pending, frames, nil, "collection_deadline")
    end
  end

  defp decode(<<kind, size::unsigned-big-32, rest::binary>> = bytes, frames) do
    cond do
      kind not in [?O, ?S, ?E, ?X] or size > 8192 ->
        :error

      byte_size(rest) < size ->
        {:ok, bytes, frames}

      true ->
        <<data::binary-size(^size), tail::binary>> = rest
        decode(tail, [{kind, data} | frames])
    end
  end

  defp decode(bytes, frames), do: {:ok, bytes, frames}

  defp finish(pending, frames, status, transport),
    do: %{pending: pending, frames: Enum.reverse(frames), status: status, transport: transport}

  defp valid?(result, out, err) do
    result.status == 0 and result.transport == nil and result.pending == "" and
      stream(result.frames, ?O) == out and stream(result.frames, ?S) == err and
      Enum.filter(result.frames, &(elem(&1, 0) == ?E)) == [] and
      Enum.filter(result.frames, &(elem(&1, 0) == ?X)) ==
        [{?X, ~s({"exit_code":0,"timed_out":false})}]
  end

  defp category(result, ok) do
    errors = stream(result.frames, ?E)

    cond do
      ok -> "passed"
      errors =~ "stdio output read failed" -> "output_read"
      errors =~ "stdio output did not drain" -> "drain_deadline"
      errors != "" -> "helper_error"
      result.transport != nil or result.status != 0 -> "transport_failure"
      stream(result.frames, ?X) == "" -> "missing_completion"
      true -> "unexpected_output"
    end
  end

  defp stream(frames, kind),
    do: frames |> Enum.filter(&(elem(&1, 0) == kind)) |> Enum.map_join(&elem(&1, 1))

  defp now, do: System.monotonic_time(:millisecond)
end

Ipse.Development.Diagnostics.StdioCleanup.main(System.argv())
