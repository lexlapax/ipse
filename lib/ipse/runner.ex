defmodule Ipse.Runner do
  @moduledoc """
  Streams trusted local shell commands through the Rust supervisor.

  By default, this provides process cleanup and output bounding only. The fixed
  `:native` profile is opt-in on supported Linux and macOS hosts. macOS uses a
  verified signed worker and provides best-effort process-group cleanup.
  `emit` receives `{:tool_output, utf8_chunk}`; retained and streamed output
  share the `output_limit` byte budget. Remaining child output is continuously
  drained.
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
    sandbox = Keyword.get(opts, :sandbox, :off)

    cond do
      not is_binary(command) or not is_binary(cwd) ->
        {:error, "command and cwd must be strings"}

      not is_integer(timeout) or timeout < 1 ->
        {:error, "timeout_ms must be a positive integer"}

      not is_integer(limit) or limit < 0 ->
        {:error, "output_limit must be a nonnegative integer"}

      not File.dir?(cwd) ->
        {:error, "working directory does not exist"}

      true ->
        with {:ok, policy} <- Ipse.Sandbox.resolve(sandbox, cwd) do
          run_supervised(
            command,
            policy.cwd,
            timeout,
            limit,
            Keyword.get(opts, :emit),
            policy.profile
          )
        end
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  @doc """
  Open a directly executed stdio server owned by the calling process.

  Use send_stdio/2 for server stdin and close_stdio/1 for confirmed cancellation.
  The returned Port emits native O/S/X/E frames; its owner must handle Port exits.
  Closing it or killing its owner stops the server's ordinary process group.
  The :sandbox option selects :off (default) or the fixed native workspace policy.
  Selected environment values reach only the server, never the OS supervisor.
  """
  def open_stdio(executable, args, cwd, selected_env \\ %{}, timeout_ms \\ 120_000, opts \\ []) do
    valid_text = fn value ->
      is_binary(value) and String.valid?(value) and not String.contains?(value, <<0>>)
    end

    valid_args =
      is_list(args) and length(args) <= 256 and Enum.all?(args, valid_text) and
        Enum.reduce(args, 0, &(byte_size(&1) + &2)) <= 65_536

    valid_env =
      is_map(selected_env) and map_size(selected_env) <= 128 and
        Enum.all?(selected_env, fn {key, value} ->
          valid_text.(key) and Regex.match?(~r/\A[A-Za-z_][A-Za-z0-9_]*\z/, key) and
            valid_text.(value)
        end) and
        Enum.reduce(selected_env, 0, fn {key, value}, size ->
          size + byte_size(key) + byte_size(value)
        end) <= 131_072

    cond do
      not valid_text.(executable) or executable == "" or byte_size(executable) > 4096 ->
        {:error, "invalid stdio executable"}

      not valid_args ->
        {:error, "invalid or oversized stdio arguments"}

      not valid_env ->
        {:error, "invalid or oversized stdio environment"}

      not valid_text.(cwd) or not File.dir?(cwd) ->
        {:error, "stdio working directory does not exist"}

      not is_integer(timeout_ms) or timeout_ms < 1 or timeout_ms > 86_400_000 ->
        {:error, "stdio timeout must be between 1 and 86400000 ms"}

      true ->
        with {:ok, policy} <- Ipse.Sandbox.resolve(Keyword.get(opts, :sandbox, :off), cwd),
             {:ok, helper} <- helper_path(policy.profile != "macos-workspace-v1"),
             {:ok, launch} <- stdio_launch_args(helper, policy, timeout_ms, executable, args) do
          selected = Map.merge(%{"PATH" => "/usr/bin:/bin", "LANG" => "C.UTF-8"}, selected_env)
          supervisor = %{"PATH" => "/usr/bin:/bin", "LANG" => "C.UTF-8"}
          # Port env uses false to unset inherited values. No values are logged
          # or copied into process arguments or the journal. Selected values
          # travel only in the private binary launch frame on the helper pipe.
          removed =
            System.get_env()
            |> Map.keys()
            |> Enum.reject(&Map.has_key?(supervisor, &1))
            |> Enum.map(&{String.to_charlist(&1), false})

          environment =
            removed ++
              Enum.map(supervisor, fn {key, value} ->
                {String.to_charlist(key), String.to_charlist(value)}
              end)

          port =
            Port.open({:spawn_executable, String.to_charlist(helper)}, [
              :binary,
              :exit_status,
              :use_stdio,
              :hide,
              cd: String.to_charlist(Path.expand(cwd)),
              env: environment,
              args: launch
            ])

          payload =
            [
              <<map_size(selected)::unsigned-big-32>>
              | Enum.map(selected, fn {key, value} ->
                  [
                    <<byte_size(key)::unsigned-big-32>>,
                    key,
                    <<byte_size(value)::unsigned-big-32>>,
                    value
                  ]
                end)
            ]
            |> IO.iodata_to_binary()

          if Port.command(port, <<?L, byte_size(payload)::unsigned-big-32, payload::binary>>, [
               :nosuspend
             ]) do
            {:ok, port}
          else
            Port.close(port)
            {:error, "could not send stdio launch environment"}
          end
        end
    end
  rescue
    _ -> {:error, "could not open stdio server"}
  end

  defp stdio_launch_args(
         helper,
         %{profile: "macos-workspace-v1", cwd: cwd},
         timeout,
         executable,
         args
       ) do
    with {:ok, policy} <- Ipse.MacOSSandbox.prepare(helper, cwd) do
      {:ok,
       [
         "--stdio",
         cwd,
         Integer.to_string(timeout),
         "--sandbox",
         "macos-workspace-v1",
         policy.worker,
         policy.data,
         executable | args
       ]}
    end
  end

  defp stdio_launch_args(_helper, %{profile: profile, cwd: cwd}, timeout, executable, args) do
    prefix = if profile, do: ["--sandbox", profile], else: []
    {:ok, ["--stdio", cwd, Integer.to_string(timeout)] ++ prefix ++ [executable | args]}
  end

  @doc "Send at most one MiB of server bytes without suspending on a busy Port."
  def send_stdio(port, bytes)
      when is_port(port) and is_binary(bytes) and byte_size(bytes) <= 1_048_576 do
    if Port.command(port, [<<?I, byte_size(bytes)::unsigned-big-32>>, bytes], [:nosuspend]),
      do: :ok,
      else: {:error, "stdio input is backpressured"}
  rescue
    _ -> {:error, "stdio transport is closed"}
  end

  def send_stdio(_, _), do: {:error, "invalid or oversized stdio input"}

  @doc "Cancel and await supervisor exit for at most two seconds before closing its Port."
  def close_stdio(port) when is_port(port) do
    result =
      try do
        cancel_stdio(port, System.monotonic_time(:millisecond) + 2_000)
      rescue
        _ -> {:error, "stdio cleanup unconfirmed"}
      end

    close_stdio_port(port)
    result
  end

  def close_stdio(_), do: {:error, "stdio cleanup unconfirmed"}

  defp cancel_stdio(port, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, "stdio cleanup unconfirmed"}
    else
      sent =
        try do
          if Port.info(port), do: Port.command(port, <<?C, 0::32>>, [:nosuspend]), else: :gone
        rescue
          _ -> :gone
        end

      case sent do
        true ->
          await_stdio_exit(port, deadline)

        :gone ->
          await_stdio_exit(port, deadline)

        false ->
          # A rejected nosuspend command was not queued. Retry only cancel,
          # never server bytes, and retain the original cleanup deadline.
          receive do
            {^port, {:data, _bytes}} -> cancel_stdio(port, deadline)
            {^port, {:exit_status, _status}} -> :ok
            {:EXIT, ^port, _reason} -> await_stdio_exit(port, deadline)
          after
            min(remaining, 5) -> cancel_stdio(port, deadline)
          end
      end
    end
  end

  defp await_stdio_exit(port, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, "stdio cleanup unconfirmed"}
    else
      receive do
        {^port, {:data, _bytes}} -> await_stdio_exit(port, deadline)
        {^port, {:exit_status, _status}} -> :ok
        {:EXIT, ^port, _reason} -> await_stdio_exit(port, deadline)
      after
        remaining -> {:error, "stdio cleanup unconfirmed"}
      end
    end
  end

  defp close_stdio_port(port) do
    if Port.info(port), do: Port.close(port)
    :ok
  rescue
    _ -> :ok
  end

  defp run_supervised(command, cwd, timeout, limit, emit, profile) do
    with {:ok, helper} <- helper_path(profile != "macos-workspace-v1"),
         {:ok, args} <- launch_args(helper, profile, cwd, timeout, command) do
      port =
        Port.open({:spawn_executable, String.to_charlist(helper)}, [
          :binary,
          :exit_status,
          :use_stdio,
          :hide,
          env: bundled_shell_environment(),
          args: args
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

      setup_allowance = if profile == "macos-workspace-v1", do: 25_000, else: 5_000
      deadline = System.monotonic_time(:millisecond) + timeout + setup_allowance

      try do
        receive_output(port, state, deadline)
      after
        if Port.info(port), do: Port.close(port)
      end
    end
  end

  # A bundled release prepends its own ERTS and exports launcher variables. They
  # must not select the release's boot files when trusted shell tools invoke the
  # operator's independently installed Erlang/Elixir toolchain.
  defp bundled_shell_environment do
    root = System.get_env("RELEASE_ROOT")
    runtime = :code.root_dir() |> List.to_string()
    app = Application.app_dir(:ipse)

    if is_binary(root) and Path.expand(root) == Path.expand(runtime) and
         String.starts_with?(app, Path.join(root, "lib") <> "/") do
      runtime_bin =
        Path.join([root, "erts-" <> List.to_string(:erlang.system_info(:version)), "bin"])

      path =
        System.get_env("PATH", "/usr/bin:/bin")
        |> String.split(":")
        |> Enum.reject(&(Path.expand(&1) == Path.expand(runtime_bin)))
        |> Enum.join(":")

      keys =
        ~w(ROOTDIR BINDIR EMU PROGNAME ERL_ROOTDIR ERL_LIBS ERL_FLAGS ERL_AFLAGS ERL_ZFLAGS) ++
          (System.get_env() |> Map.keys() |> Enum.filter(&String.starts_with?(&1, "RELEASE_")))

      [
        {~c"PATH", String.to_charlist(path)}
        | Enum.map(Enum.uniq(keys), &{String.to_charlist(&1), false})
      ]
    else
      []
    end
  end

  defp launch_args(helper, "macos-workspace-v1" = profile, cwd, timeout, command) do
    with {:ok, policy} <- Ipse.MacOSSandbox.prepare(helper, cwd) do
      {:ok,
       [
         "--sandbox",
         profile,
         policy.worker,
         policy.data,
         cwd,
         Integer.to_string(timeout),
         command
       ]}
    end
  end

  defp launch_args(_helper, nil, cwd, timeout, command),
    do: {:ok, [cwd, Integer.to_string(timeout), command]}

  defp launch_args(_helper, profile, cwd, timeout, command),
    do: {:ok, ["--sandbox", profile, cwd, Integer.to_string(timeout), command]}

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

  defp helper_path(allow_build \\ true) do
    configured = System.get_env("IPSE_RUNNER_PATH")
    paths = [configured, app_helper(), Path.join(@root, "priv/ipse-runner")]

    case Enum.find(paths, &(is_binary(&1) and File.regular?(&1))) do
      nil when allow_build -> build_helper()
      nil -> {:error, "native macOS helper missing; run scripts/build.sh before starting Ipse"}
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
