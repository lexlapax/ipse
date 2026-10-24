defmodule Ipse.Runner do
  @moduledoc """
  Streams trusted local shell commands through the Rust supervisor.

  By default, this provides process cleanup and output bounding only. The fixed
  `:native` profile is opt-in on supported Linux and macOS hosts. macOS uses a
  verified signed worker and provides best-effort process-group cleanup.
  `emit` receives `{:tool_output, utf8_chunk}`; retained and streamed output
  share the `output_limit` byte budget. Remaining child output is continuously
  drained. Known validation/setup refusals return `:error`; loss of supervision
  after possible shell dispatch returns `:unknown` and must not be replayed.
  """
  @root Path.expand("../..", __DIR__)
  @default_limit 65_536

  @doc false
  def native_helper(cwd) do
    with {:ok, helper} <- verified_helper(),
         :ok <- Ipse.Tools.Sandbox.helper_boundary(cwd, helper),
         do: {:ok, helper}
  end

  defp verified_helper do
    with {:ok, helper} <- helper_path(false),
         {:ok, %{type: :regular, links: 1, mode: mode, size: size}} <- File.lstat(helper),
         true <- Bitwise.band(mode, 0o022) == 0 and Bitwise.band(mode, 0o111) != 0,
         true <- size <= 32 * 1024 * 1024,
         {:ok, canonical} <- Ipse.Workspace.canonical_path(helper) do
      {:ok, canonical}
    else
      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      _ ->
        {:error, "native helper must be a bounded, single-link, non-writable regular executable"}
    end
  end

  @doc "Read the current OS user from the verified host helper, without launching a shell."
  def current_uid do
    with {:ok, helper} <- verified_helper() do
      port =
        Port.open(
          {:spawn_executable, String.to_charlist(helper)},
          [:binary, :exit_status, :use_stdio, :hide, args: ["--uid"]]
        )

      try do
        receive_uid(port, "", System.monotonic_time(:millisecond) + 2_000)
      after
        if Port.info(port), do: Port.close(port)
      end
    end
  rescue
    _ -> {:error, :uid_unavailable}
  end

  defp receive_uid(port, bytes, deadline) do
    receive do
      {^port, {:data, data}} when byte_size(bytes) + byte_size(data) <= 64 ->
        receive_uid(port, bytes <> data, deadline)

      {^port, {:exit_status, 0}} ->
        case Integer.parse(String.trim(bytes)) do
          {uid, ""} when uid >= 0 -> {:ok, uid}
          _ -> {:error, :invalid_uid}
        end

      {^port, _} ->
        {:error, :uid_unavailable}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> {:error, :uid_unavailable}
    end
  end

  defp selected_helper(nil, _cwd), do: helper_path()
  defp selected_helper(_profile, cwd), do: native_helper(cwd)

  @doc "Acquire a persistent advisory lock. Its Port must remain owned by the session."
  def lock(path) when is_binary(path) do
    with :ok <- launch_text(path),
         {:ok, helper} <- helper_path(),
         {:ok, port, ticket} <-
           owned_port(:lock, helper, [
             :binary,
             :exit_status,
             :use_stdio,
             :hide,
             args: ["--lock", Path.expand(path)]
           ]) do
      Process.put({__MODULE__, port}, ticket)
      result = receive_lock(port, <<>>, System.monotonic_time(:millisecond) + 5_000, ticket)
      if match?({:error, _}, result), do: unlock(port)
      result
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  def lock(_), do: {:error, "lock path must be a string"}

  @doc "Release an owned lock Port. The lock file remains to preserve inode identity."
  def unlock(port) when is_port(port) do
    ticket = Process.delete({__MODULE__, port})

    result =
      if Port.info(port) do
        close_process(port, true)
      else
        receive do
          {^port, {:exit_status, _}} -> :ok
        after
          0 -> if is_nil(ticket), do: :ok, else: {:error, :cleanup_unconfirmed}
        end
      end

    Ipse.Session.Resources.closed(ticket, result)
    result
  rescue
    ArgumentError -> :ok
  end

  def unlock(_), do: :ok

  defp receive_lock(port, buffer, deadline, ticket) do
    case buffer do
      <<_kind, size::unsigned-big-32, _::binary>> when size > 1_048_576 ->
        {:error, "invalid session lock response"}

      <<?L, size::unsigned-big-32, _payload::binary-size(size), _::binary>> ->
        {:ok, port}

      <<?E, size::unsigned-big-32, error::binary-size(size), _::binary>> ->
        Ipse.Session.Resources.closed(
          ticket,
          await_stdio_exit(port, System.monotonic_time(:millisecond) + 2_000, true)
        )

        {:error, sanitize(error)}

      _ ->
        receive do
          {^port, {:data, bytes}} ->
            receive_lock(port, buffer <> bytes, deadline, ticket)

          {^port, {:exit_status, _}} ->
            Ipse.Session.Resources.closed(ticket, :ok)
            {:error, "session lock helper exited unexpectedly"}

          {:ipse_cancel_resource, id} when ticket != nil and ticket.id == id ->
            Ipse.Session.Resources.closed(ticket, close_process(port, true))
            {:error, "session lock acquisition cancelled"}
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

      not valid_text?(command) or not valid_text?(cwd) ->
        {:error, "command and cwd must be valid UTF-8 without NUL bytes"}

      not is_integer(timeout) or timeout < 1 ->
        {:error, "timeout_ms must be a positive integer"}

      not is_integer(limit) or limit < 0 ->
        {:error, "output_limit must be a nonnegative integer"}

      not File.dir?(cwd) ->
        {:error, "working directory does not exist"}

      true ->
        with {:ok, policy} <- Ipse.Tools.Sandbox.resolve(sandbox, cwd) do
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
  On Linux with sandbox :off, :owned_listener may be {:ipv4_loopback, port}.
  It adds one native P frame after observing that the retained direct child owns
  the caller's exact 127.0.0.1 listener. Its 15-byte payload is version 1, a u32
  diagnostic child PID, u16 port and u64 socket inode, all unsigned big-endian.
  This observation is not a promise of future availability or signaling authority.
  Selected values are installed only in the server's environment. The supervisor
  relays the private launch data without installing it in its own environment.
  """
  def open_stdio(executable, args, cwd, selected_env \\ %{}, timeout_ms \\ 120_000, opts \\ []) do
    valid_text = &valid_text?/1
    listener = Keyword.get(opts, :owned_listener)

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

      listener != nil and
          not match?(
            {:ipv4_loopback, port} when is_integer(port) and port in 1..65_535,
            listener
          ) ->
        {:error, "owned_listener must be an IPv4 loopback port from 1 to 65535"}

      listener != nil and Keyword.get(opts, :sandbox, :off) != :off ->
        {:error, "owned_listener requires sandbox :off"}

      listener != nil and not match?({:unix, :linux}, :os.type()) ->
        {:error, "owned_listener requires Linux"}

      listener != nil and Path.type(executable) != :absolute ->
        {:error, "owned_listener executable must be absolute"}

      true ->
        with {:ok, policy} <- Ipse.Tools.Sandbox.resolve(Keyword.get(opts, :sandbox, :off), cwd),
             {:ok, helper} <- selected_helper(policy.profile, policy.cwd),
             {:ok, launch} <-
               stdio_launch_args(helper, policy, timeout_ms, executable, args, listener) do
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

          send_launch(port, payload, Keyword.get(opts, :cleanup_ticket))
        end
    end
  rescue
    _ -> {:error, "could not open stdio server"}
  end

  @doc false
  def open_owned_stdio(kind, scope, executable, args, cwd, env, timeout, opts \\ [])
      when kind in [:mcp, :extension] do
    with {:ok, ticket} <- Ipse.Session.Resources.register(kind, scope) do
      case open_stdio(
             executable,
             args,
             cwd,
             env,
             timeout,
             Keyword.put(opts, :cleanup_ticket, ticket)
           ) do
        {:ok, port} ->
          {:ok, port, ticket}

        {:error, {:cleanup_unconfirmed, _}} = error ->
          Ipse.Session.Resources.closed(ticket, {:error, :cleanup_unconfirmed})
          error

        {:error, _} = error ->
          Ipse.Session.Resources.closed(ticket, :ok)
          error
      end
    end
  end

  defp send_launch(port, payload, ticket) do
    if Port.command(port, <<?L, byte_size(payload)::unsigned-big-32, payload::binary>>, [
         :nosuspend
       ]),
       do: await_launch_flush(port, System.monotonic_time(:millisecond) + 5_000, ticket),
       else: failed_launch(port)
  rescue
    _ -> failed_launch(port)
  end

  defp await_launch_flush(port, deadline, ticket) do
    cond do
      System.monotonic_time(:millisecond) >= deadline ->
        failed_launch(port)

      Port.command(port, <<>>, [:nosuspend]) ->
        {:ok, port}

      true ->
        receive do
          {:ipse_cancel_resource, id} when ticket != nil and ticket.id == id ->
            failed_launch(port)
        after
          5 -> await_launch_flush(port, deadline, ticket)
        end
    end
  end

  defp failed_launch(port) do
    cleanup =
      try do
        close_stdio(port)
      rescue
        _ -> {:error, :cleanup_unconfirmed}
      catch
        _, _ -> {:error, :cleanup_unconfirmed}
      end

    if cleanup == :ok,
      do: {:error, "could not send stdio launch environment"},
      else: {:error, {:cleanup_unconfirmed, "could not send stdio launch environment"}}
  end

  defp owned_port(kind, helper, options) do
    with {:ok, ticket} <- Ipse.Session.Resources.register(kind) do
      try do
        {:ok, Port.open({:spawn_executable, String.to_charlist(helper)}, options), ticket}
      rescue
        _ ->
          Ipse.Session.Resources.closed(ticket, :ok)
          {:error, "could not start OS helper"}
      end
    end
  end

  defp valid_text?(value),
    do: is_binary(value) and String.valid?(value) and not String.contains?(value, <<0>>)

  defp launch_text(value),
    do:
      if(valid_text?(value),
        do: :ok,
        else: {:error, "lock path must be valid UTF-8 without NUL bytes"}
      )

  defp stdio_launch_args(
         _helper,
         %{profile: nil, cwd: cwd},
         timeout,
         executable,
         args,
         {:ipv4_loopback, port}
       ) do
    {:ok,
     [
       "--stdio-listener",
       cwd,
       Integer.to_string(timeout),
       Integer.to_string(port),
       "--",
       executable | args
     ]}
  end

  defp stdio_launch_args(
         helper,
         %{profile: "macos-workspace-v1", cwd: cwd},
         timeout,
         executable,
         args,
         nil
       ) do
    with {:ok, policy} <- Ipse.Tools.MacOSSandbox.prepare(helper, cwd) do
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

  defp stdio_launch_args(_helper, %{profile: profile, cwd: cwd}, timeout, executable, args, nil) do
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

  @doc "Await supervisor exit within two seconds; cancel only if no terminal frame was observed."
  def close_stdio(port, mode \\ :cancel)

  def close_stdio(port, mode) when is_port(port) and mode in [:cancel, :completed],
    do: close_process(port, false, mode)

  def close_stdio(_, _), do: {:error, "stdio cleanup unconfirmed"}

  defp close_process(port, lock?, mode \\ :cancel) do
    if Process.info(self(), :trap_exit) == {:trap_exit, true} do
      try do
        finish_stdio(port, System.monotonic_time(:millisecond) + 2_000, lock?, mode)
      after
        close_stdio_port(port)
      end
    else
      close_guarded(port, lock?, mode)
    end
  end

  defp close_guarded(port, lock?, mode) do
    owner = self()
    reference = make_ref()
    deadline = System.monotonic_time(:millisecond) + 2_000

    {guard, monitor} =
      spawn_monitor(fn ->
        Process.flag(:trap_exit, true)
        guard = self()

        spawn(fn ->
          owner_ref = Process.monitor(owner)
          guard_ref = Process.monitor(guard)

          receive do
            {:DOWN, ^owner_ref, :process, _, _} -> Process.exit(guard, :kill)
            {:DOWN, ^guard_ref, :process, _, _} -> :ok
          end
        end)

        result =
          try do
            Process.link(port)
            send(owner, {reference, :close_ready})

            receive do
              {^reference, :close} ->
                finish_stdio(port, System.monotonic_time(:millisecond) + 2_000, lock?, mode)
            after
              2_500 -> {:error, "stdio cleanup unconfirmed"}
            end
          rescue
            _ -> {:error, "stdio cleanup unconfirmed"}
          after
            close_stdio_port(port)
          end

        send(owner, {reference, result})
      end)

    result =
      receive do
        {^reference, :close_ready} ->
          try do
            Port.connect(port, guard)
            Process.unlink(port)
            send(guard, {reference, :close})

            receive do
              {^reference, result} -> result
              {:DOWN, ^monitor, :process, ^guard, _} -> {:error, "stdio cleanup unconfirmed"}
            after
              2_500 -> {:error, "stdio cleanup unconfirmed"}
            end
          rescue
            _ -> {:error, "stdio cleanup unconfirmed"}
          end

        {^reference, result} ->
          result

        {:DOWN, ^monitor, :process, ^guard, _} ->
          {:error, "stdio cleanup unconfirmed"}
      after
        3_000 -> {:error, "stdio cleanup unconfirmed"}
      end

    Process.demonitor(monitor, [:flush])
    if Process.alive?(guard), do: Process.exit(guard, :kill)
    close_stdio_port(port)

    if result == :ok do
      :ok
    else
      await_stdio_exit(port, deadline, lock?)
    end
  end

  defp finish_stdio(port, deadline, lock?, :completed),
    do: await_stdio_exit(port, deadline, lock?)

  defp finish_stdio(port, deadline, lock?, :cancel), do: cancel_stdio(port, deadline, lock?)

  defp cancel_stdio(port, deadline, lock?) do
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
          await_stdio_exit(port, deadline, lock?)

        :gone ->
          await_stdio_exit(port, deadline, lock?)

        false ->
          # A rejected nosuspend command was not queued. Retry only cancel,
          # never server bytes, and retain the original cleanup deadline.
          receive do
            {^port, {:data, _bytes}} -> cancel_stdio(port, deadline, lock?)
            {^port, {:exit_status, status}} -> cleanup_status(status, lock?)
            {:EXIT, ^port, _reason} -> await_stdio_exit(port, deadline, lock?)
          after
            min(remaining, 5) -> cancel_stdio(port, deadline, lock?)
          end
      end
    end
  end

  defp await_stdio_exit(port, deadline, lock?) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, "stdio cleanup unconfirmed"}
    else
      receive do
        {^port, {:data, _bytes}} -> await_stdio_exit(port, deadline, lock?)
        {^port, {:exit_status, status}} -> cleanup_status(status, lock?)
        {:EXIT, ^port, _reason} -> await_stdio_exit(port, deadline, lock?)
      after
        remaining -> {:error, "stdio cleanup unconfirmed"}
      end
    end
  end

  defp cleanup_status(status, lock?) do
    if lock? or status in [0, 1], do: :ok, else: {:error, "stdio cleanup unconfirmed"}
  end

  defp close_stdio_port(port) do
    if Port.info(port), do: Port.close(port)
    :ok
  rescue
    _ -> :ok
  end

  defp run_supervised(command, cwd, timeout, limit, emit, profile) do
    with {:ok, helper} <- selected_helper(profile, cwd),
         {:ok, args} <- launch_args(helper, profile, cwd, timeout, command),
         {:ok, port, ticket} <-
           owned_port(:shell, helper, [
             :binary,
             :exit_status,
             :use_stdio,
             :hide,
             env: bundled_shell_environment(),
             args: args
           ]) do
      state = %{
        buffer: <<>>,
        output: <<>>,
        pending: <<>>,
        remaining: limit,
        output_limit: limit,
        output_bytes: 0,
        emit: emit,
        result: nil,
        error: nil,
        cleanup_ticket: ticket
      }

      setup_allowance = if profile == "macos-workspace-v1", do: 25_000, else: 5_000
      deadline = System.monotonic_time(:millisecond) + timeout + setup_allowance

      try do
        receive_output(port, state, deadline)
      rescue
        _ ->
          {:unknown, "Shell supervision failed after possible dispatch. Inspect before retrying."}
      catch
        _, _ ->
          {:unknown,
           "Shell supervision was interrupted after possible dispatch. Inspect before retrying."}
      after
        cleanup = if Port.info(port), do: close_stdio(port), else: {:error, :cleanup_unconfirmed}
        Ipse.Session.Resources.closed(ticket, cleanup)
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
    with {:ok, policy} <- Ipse.Tools.MacOSSandbox.prepare(helper, cwd) do
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
          {:error, reason} -> {:unknown, reason}
        end

      {^port, {:exit_status, code}} ->
        cleanup =
          if code == 0 or (code == 1 and match?({:error, _}, state.error)),
            do: :ok,
            else: {:error, :cleanup_unconfirmed}

        Ipse.Session.Resources.closed(state.cleanup_ticket, cleanup)

        cond do
          state.error ->
            state.error

          state.buffer != <<>> ->
            {:unknown, "shell supervisor sent an incomplete frame"}

          state.result == nil ->
            {:unknown, "shell supervisor exited without a result"}

          true ->
            {:ok,
             Map.merge(state.result, %{
               output: state.output,
               output_bytes: state.output_bytes,
               output_truncated: state.output_bytes > state.output_limit or state.pending != <<>>
             })}
        end

      {:ipse_cancel_resource, id}
      when state.cleanup_ticket != nil and state.cleanup_ticket.id == id ->
        Ipse.Session.Resources.closed(state.cleanup_ticket, close_stdio(port))
        {:unknown, "Shell cancelled; started effects may have occurred. Inspect before retrying."}
    after
      remaining -> {:unknown, "shell supervisor stopped responding"}
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
     %{
       state
       | output: state.output <> text,
         pending: pending,
         remaining: state.remaining - count,
         output_bytes: state.output_bytes + byte_size(bytes)
     }}
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

  defp accept_frame(?E, bytes, state) do
    status =
      if state.output_bytes > 0 or state.result != nil or match?({:unknown, _}, state.error),
        do: :unknown,
        else: :error

    {:ok, %{state | error: {status, sanitize(bytes)}}}
  end

  defp accept_frame(?U, bytes, state), do: {:ok, %{state | error: {:unknown, sanitize(bytes)}}}
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
      nil -> {:error, "native helper missing; run dev/build.sh before starting Ipse"}
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
      {:error, "shell supervisor missing; run dev/build-native.sh with rustc installed"}
    end
  end
end
