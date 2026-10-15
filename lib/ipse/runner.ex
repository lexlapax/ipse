defmodule Ipse.Runner do
  @moduledoc """
  Streams trusted local shell commands through the Unix Rust supervisor.

  This is process cleanup and output bounding, not a filesystem/network sandbox.
  `emit` receives `{:tool_output, utf8_chunk}`; retained and streamed output share
  the `output_limit` byte budget. Remaining child output is continuously drained.
  """
  @root Path.expand("../..", __DIR__)
  @default_limit 65_536

  @doc "Acquire a persistent advisory lock. Its Port must remain owned by the session."
  def lock(path) when is_binary(path) do
    with {:ok, helper} <- helper_path() do
      port =
        Port.open({:spawn_executable, String.to_charlist(helper)}, [
          :binary,
          :exit_status,
          :use_stdio,
          :hide,
          args: ["--lock", Path.expand(path)]
        ])

      result = receive_lock(port, <<>>, System.monotonic_time(:millisecond) + 5_000)
      if match?({:error, _}, result) and Port.info(port), do: Port.close(port)
      result
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  def lock(_), do: {:error, "lock path must be a string"}

  @doc "Release an owned lock Port. The lock file remains to preserve inode identity."
  def unlock(port) when is_port(port) do
    if Port.info(port), do: Port.close(port)

    :ok
  rescue
    ArgumentError -> :ok
  end

  def unlock(_), do: :ok

  defp receive_lock(port, buffer, deadline) do
    case buffer do
      <<_kind, size::unsigned-big-32, _::binary>> when size > 1_048_576 ->
        {:error, "invalid session lock response"}

      <<?L, size::unsigned-big-32, _payload::binary-size(size), _::binary>> ->
        {:ok, port}

      <<?E, size::unsigned-big-32, error::binary-size(size), _::binary>> ->
        {:error, sanitize(error)}

      _ ->
        receive do
          {^port, {:data, bytes}} -> receive_lock(port, buffer <> bytes, deadline)
          {^port, {:exit_status, _}} -> {:error, "session lock helper exited unexpectedly"}
        after
          max(deadline - System.monotonic_time(:millisecond), 0) ->
            {:error, "session lock helper stopped responding"}
        end
    end
  end

  def run(command, cwd, opts \\ []) do
    timeout = Keyword.get(opts, :timeout_ms, 120_000)
    limit = Keyword.get(opts, :output_limit, @default_limit)

    cond do
      not is_binary(command) or not is_binary(cwd) -> {:error, "command and cwd must be strings"}
      not is_integer(timeout) or timeout < 1 -> {:error, "timeout_ms must be a positive integer"}
      not is_integer(limit) or limit < 0 -> {:error, "output_limit must be a nonnegative integer"}
      not File.dir?(cwd) -> {:error, "working directory does not exist"}
      true -> run_supervised(command, cwd, timeout, limit, Keyword.get(opts, :emit))
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp run_supervised(command, cwd, timeout, limit, emit) do
    with {:ok, helper} <- helper_path() do
      port =
        Port.open({:spawn_executable, String.to_charlist(helper)}, [
          :binary,
          :exit_status,
          :use_stdio,
          :hide,
          args: [cwd, Integer.to_string(timeout), command]
        ])

      state = %{
        buffer: <<>>,
        output: <<>>,
        pending: <<>>,
        remaining: limit,
        emit: emit,
        result: nil,
        error: nil
      }

      deadline = System.monotonic_time(:millisecond) + timeout + 5_000

      try do
        receive_output(port, state, deadline)
      after
        if Port.info(port), do: Port.close(port)
      end
    end
  end

  defp receive_output(port, state, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, bytes}} ->
        case frames(%{state | buffer: state.buffer <> bytes}) do
          {:ok, next} -> receive_output(port, next, deadline)
          {:error, reason} -> {:error, reason}
        end

      {^port, {:exit_status, _code}} ->
        cond do
          state.error -> {:error, state.error}
          state.buffer != <<>> -> {:error, "shell supervisor sent an incomplete frame"}
          state.result == nil -> {:error, "shell supervisor exited without a result"}
          true -> {:ok, Map.put(state.result, :output, state.output)}
        end
    after
      remaining -> {:error, "shell supervisor stopped responding"}
    end
  end

  defp frames(%{buffer: <<kind, size::unsigned-big-32, rest::binary>>} = state) do
    cond do
      size > 1_048_576 ->
        {:error, "shell supervisor frame too large"}

      byte_size(rest) < size ->
        {:ok, state}

      true ->
        <<payload::binary-size(^size), tail::binary>> = rest

        case accept_frame(kind, payload, %{state | buffer: tail}) do
          {:ok, next} -> frames(next)
          error -> error
        end
    end
  end

  defp frames(state), do: {:ok, state}

  defp accept_frame(?O, bytes, state) do
    count = min(byte_size(bytes), state.remaining)
    selected = binary_part(bytes, 0, count)
    {text, pending} = decode_utf8(state.pending <> selected)
    if text != "" and is_function(state.emit, 1), do: state.emit.({:tool_output, text})

    {:ok,
     %{state | output: state.output <> text, pending: pending, remaining: state.remaining - count}}
  end

  defp accept_frame(?X, bytes, state) do
    case Jason.decode(bytes) do
      {:ok, %{"exit_code" => code, "timed_out" => timeout}}
      when is_integer(code) and is_boolean(timeout) ->
        {:ok, %{state | result: %{exit_code: code, timed_out: timeout}}}

      _ ->
        {:error, "invalid shell supervisor result"}
    end
  end

  defp accept_frame(?E, bytes, state), do: {:ok, %{state | error: sanitize(bytes)}}
  defp accept_frame(_, _, _), do: {:error, "unknown shell supervisor frame"}

  # Keep incomplete multibyte sequences across frames. Incomplete trailing bytes
  # at the output budget boundary are discarded, preserving a valid byte bound.
  defp decode_utf8(bytes) do
    case :unicode.characters_to_binary(bytes, :utf8, :utf8) do
      text when is_binary(text) ->
        {text, <<>>}

      {:incomplete, good, rest} ->
        {good, rest}

      {:error, good, <<_bad, rest::binary>>} ->
        {tail, pending} = decode_utf8(rest)
        {good <> "?" <> tail, pending}
    end
  end

  defp sanitize(bytes) do
    {text, _} = decode_utf8(bytes)
    text
  end

  defp helper_path do
    configured = System.get_env("IPSE_RUNNER_PATH")
    paths = [configured, app_helper(), Path.join(@root, "priv/ipse-runner")]

    case Enum.find(paths, &(is_binary(&1) and File.regular?(&1))) do
      nil -> build_helper()
      path -> {:ok, Path.expand(path)}
    end
  end

  defp app_helper do
    case :code.priv_dir(:ipse) do
      path when is_list(path) -> Path.join(List.to_string(path), "ipse-runner")
      _ -> nil
    end
  end

  defp build_helper do
    source = Path.join(@root, "native/ipse-runner.rs")
    rustc = System.find_executable("rustc")

    if rustc && File.regular?(source) do
      :global.trans({{__MODULE__, :build}, self()}, fn ->
        target = Path.join(@root, "priv/ipse-runner")

        if File.regular?(target) do
          {:ok, target}
        else
          File.mkdir_p!(Path.dirname(target))
          temp = target <> ".#{System.unique_integer([:positive])}"

          case System.cmd(
                 rustc,
                 [
                   "--edition=2021",
                   "-C",
                   "opt-level=z",
                   "-C",
                   "strip=symbols",
                   "-C",
                   "panic=abort",
                   source,
                   "-o",
                   temp
                 ],
                 stderr_to_stdout: true
               ) do
            {_, 0} ->
              File.rename!(temp, target)
              {:ok, target}

            {message, _} ->
              File.rm(temp)
              {:error, "could not build shell supervisor: " <> String.slice(message, 0, 2_000)}
          end
        end
      end)
    else
      {:error, "shell supervisor missing; run native/build.sh with rustc installed"}
    end
  end
end
