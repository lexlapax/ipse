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
  @operator_helper Path.join(@root, "priv/ipse-runner")
  @external_resource @operator_helper
  @operator_helper_sha256 (case File.read(@operator_helper) do
                             {:ok, bytes} when byte_size(bytes) <= 32 * 1024 * 1024 ->
                               :crypto.hash(:sha256, bytes)

                             _ ->
                               nil
                           end)

  @doc false
  def native_helper(cwd) do
    with {:ok, helper} <- verified_helper(),
         :ok <- Ipse.Tools.Sandbox.helper_boundary(cwd, helper),
         do: {:ok, helper}
  end

  @doc false
  def protected_helper(cwd) do
    with {:ok, helper} <- verified_operator_helper(),
         :ok <- Ipse.Tools.Sandbox.helper_boundary(cwd, helper),
         do: {:ok, helper}
  end

  @doc false
  def protected_helper_digest do
    with {:ok, _} <- verified_operator_helper(),
         do: {:ok, Base.encode16(@operator_helper_sha256, case: :lower)}
  end

  @doc false
  # Session chooses the recipient purpose and sends its own checked payload.
  # The returned Port must be transferred to the exact current host owner.
  def open_synthetic_notice_terminal(cwd, remaining, purpose \\ :ordinary)

  def open_synthetic_notice_terminal(cwd, remaining, purpose)
      when is_binary(cwd) and is_integer(remaining) and remaining in 1..120_000 and
             purpose in [:ordinary, :accepted, :review, :approval] and
             (purpose in [:review, :approval] or remaining <= 5_000) do
    with {:unix, :linux} <- :os.type(),
         {:ok, helper} <- protected_helper(cwd) do
      {:ok,
       Port.open({:spawn_executable, String.to_charlist(helper)}, [
         :binary,
         :exit_status,
         :nouse_stdio,
         :hide,
         args: [
           "--operator-input",
           Integer.to_string(remaining),
           case purpose do
             :accepted -> "v10-synthetic-accepted-notice-display"
             :review -> "v13-session-review-group-input"
             :approval -> "v13-session-review-group-input"
             :ordinary -> "v9-synthetic-notice-display"
           end
         ]
       ])}
    else
      _ -> {:error, :terminal_unavailable}
    end
  rescue
    _ -> {:error, :terminal_unavailable}
  end

  def open_synthetic_notice_terminal(_, _, _), do: {:error, :terminal_unavailable}

  @doc false
  def open_owner_control do
    with {:unix, :linux} <- :os.type(),
         {:ok, helper} <- verified_operator_helper() do
      port =
        Port.open({:spawn_executable, String.to_charlist(helper)}, [
          :binary,
          :exit_status,
          :use_stdio,
          :hide,
          args: ["--owner-control-send-v1"]
        ])

      {:ok, port}
    else
      _ -> {:error, :owner_control_unavailable}
    end
  rescue
    _ -> {:error, :owner_control_unavailable}
  end

  @doc false
  def prepare_owner_control(job_ref, intent, ticket, operation, deadline)
      when is_reference(job_ref) and is_map(intent) and is_reference(ticket) and
             is_binary(operation) and byte_size(operation) == 16 and is_integer(deadline) do
    with {:unix, :linux} <- :os.type(),
         {:ok, _} <- verified_operator_helper(),
         true <- deadline > System.monotonic_time(:millisecond),
         true <- deadline <= System.monotonic_time(:millisecond) + 5_000,
         true <- operation != <<0::128>> do
      {:ok,
       %{
         owner: self(),
         job_ref: job_ref,
         intent_sha256: Ipse.JSON.digest([intent]),
         ticket: ticket,
         operation: operation,
         deadline: deadline,
         helper: Path.expand(app_helper()),
         helper_sha256: @operator_helper_sha256
       }}
    else
      _ -> {:error, :owner_control_unavailable}
    end
  rescue
    _ -> {:error, :owner_control_unavailable}
  end

  def prepare_owner_control(_, _, _, _, _), do: {:error, :owner_control_unavailable}

  @doc false
  def valid_owner_preparation?(prepared, owner, job_ref, intent) do
    is_map(prepared) and
      Enum.sort(Map.keys(prepared)) ==
        Enum.sort(~w(owner job_ref intent_sha256 ticket operation deadline helper helper_sha256)a) and
      prepared.owner == owner and prepared.job_ref == job_ref and is_reference(job_ref) and
      is_map(intent) and prepared.intent_sha256 == Ipse.JSON.digest([intent]) and
      is_reference(prepared.ticket) and
      is_binary(prepared.operation) and byte_size(prepared.operation) == 16 and
      prepared.operation != <<0::128>> and is_integer(prepared.deadline) and
      prepared.deadline > System.monotonic_time(:millisecond) and
      prepared.deadline <= System.monotonic_time(:millisecond) + 5_000 and
      is_binary(app_helper()) and prepared.helper == Path.expand(app_helper()) and
      is_binary(@operator_helper_sha256) and prepared.helper_sha256 == @operator_helper_sha256
  rescue
    _ -> false
  end

  @doc false
  def open_prepared_owner_control(prepared, owner, job_ref, intent, mode \\ :legacy) do
    if mode in [:legacy, :synthetic_notice] and
         valid_owner_preparation?(prepared, owner, job_ref, intent) do
      {:ok,
       Port.open({:spawn_executable, String.to_charlist(prepared.helper)}, [
         :binary,
         :exit_status,
         :use_stdio,
         :hide,
         args: [
           if(mode == :synthetic_notice,
             do: "--owner-control-send-v2",
             else: "--owner-control-send-v1"
           )
         ]
       ])}
    else
      {:error, :owner_control_unavailable}
    end
  rescue
    _ -> {:error, :owner_control_unavailable}
  end

  @doc false
  def open_review_owner_control(prepared, owner, job_ref, intent, overall_deadline)
      when is_integer(overall_deadline),
      do: open_review_owner_control(prepared, owner, job_ref, intent, overall_deadline, :eof)

  def open_review_owner_control(_, _, _, _, _), do: {:error, :owner_control_unavailable}

  @doc false
  def open_review_notice_owner_control(prepared, owner, job_ref, intent, overall_deadline)
      when is_integer(overall_deadline),
      do: open_review_owner_control(prepared, owner, job_ref, intent, overall_deadline, :notice)

  def open_review_notice_owner_control(_, _, _, _, _),
    do: {:error, :owner_control_unavailable}

  @doc false
  # Session uses this only after checking its own ticket and current Host.
  def open_prepared_review_notice_owner_control(
        prepared,
        owner,
        job_ref,
        intent,
        overall_deadline
      )
      when is_integer(overall_deadline),
      do:
        open_review_owner_control(
          prepared,
          owner,
          job_ref,
          intent,
          overall_deadline,
          :session_notice
        )

  def open_prepared_review_notice_owner_control(_, _, _, _, _),
    do: {:error, :owner_control_unavailable}

  defp open_review_owner_control(prepared, owner, job_ref, intent, overall_deadline, mode)
       when is_integer(overall_deadline) do
    now = System.monotonic_time(:millisecond)
    remaining = overall_deadline - now

    with true <- mode == :session_notice or owner == self(),
         true <- valid_owner_preparation?(prepared, owner, job_ref, intent),
         {:ok, _} <- verified_operator_helper(),
         true <- overall_deadline >= prepared.deadline,
         true <- remaining in 5_000..120_000 do
      {:ok,
       Port.open({:spawn_executable, String.to_charlist(prepared.helper)}, [
         :binary,
         :exit_status,
         :use_stdio,
         :hide,
         args: [
           if(mode in [:notice, :session_notice],
             do: "--owner-control-send-review-notice-v4",
             else: "--owner-control-send-review-v3"
           ),
           Integer.to_string(remaining)
         ]
       ])}
    else
      _ -> {:error, :owner_control_unavailable}
    end
  rescue
    _ -> {:error, :owner_control_unavailable}
  end

  @doc false
  # The Port owner must first observe its bounded R/owner-control-v1 frame.
  # A queued request is not a transfer or an owner-liveness acknowledgment.
  def send_owner_control(port, operation, role, recipient, name, secret)
      when is_port(port) and is_binary(operation) and byte_size(operation) == 16 and
             role in [:session, :host, :management_cli, :management_journal] and
             is_integer(recipient) and recipient in 1..4_294_967_295 and
             is_binary(name) and byte_size(name) == 16 and is_binary(secret) and
             byte_size(secret) == 32 do
    if Port.info(port, :connected) == {:connected, self()} and operation != <<0::128>> and
         name != <<0::128>> and secret != <<0::256>> do
      role_id = if role in [:session, :management_cli], do: 1, else: 2
      body = <<operation::binary, role_id, recipient::32, name::binary, secret::binary>>

      if Port.command(port, <<?I, byte_size(body)::32, body::binary>>, [:nosuspend]),
        do: :ok,
        else: {:error, :owner_control_unconfirmed}
    else
      {:error, :owner_control_unavailable}
    end
  rescue
    _ -> {:error, :owner_control_unconfirmed}
  end

  def send_owner_control(_, _, _, _, _, _), do: {:error, :owner_control_unavailable}

  @doc false
  def close_owner_control(port) when is_port(port) do
    if Port.info(port, :connected) == {:connected, self()} do
      Port.close(port)
      :ok
    else
      {:error, :owner_control_unavailable}
    end
  rescue
    _ -> {:error, :owner_control_unconfirmed}
  end

  def close_owner_control(_), do: {:error, :owner_control_unavailable}

  @doc false
  def cancel_unused_owner_control(port, deadline) when is_port(port) and is_integer(deadline) do
    with {:connected, owner} when owner == self() <- Port.info(port, :connected),
         true <- deadline > System.monotonic_time(:millisecond),
         true <- Port.command(port, <<?C, 0::32>>, [:nosuspend]),
         :ok <- owner_control_cancel_receipt(port, deadline, <<>>) do
      :ok
    else
      _ -> {:error, :owner_control_unconfirmed}
    end
  rescue
    _ -> {:error, :owner_control_unconfirmed}
  end

  def cancel_unused_owner_control(_, _), do: {:error, :owner_control_unconfirmed}

  defp owner_control_cancel_receipt(port, deadline, buffer) do
    expected = <<?C, 9::32, "cancelled">>

    cond do
      System.monotonic_time(:millisecond) >= deadline ->
        {:error, :owner_control_unconfirmed}

      byte_size(buffer) > byte_size(expected) or
          binary_part(expected, 0, min(byte_size(buffer), byte_size(expected))) != buffer ->
        {:error, :owner_control_unconfirmed}

      true ->
        receive do
          {^port, {:data, bytes}} -> owner_control_cancel_receipt(port, deadline, buffer <> bytes)
          {^port, {:exit_status, 0}} when buffer == expected -> :ok
          {^port, {:exit_status, _}} -> {:error, :owner_control_unconfirmed}
          {:EXIT, ^port, _} -> owner_control_cancel_receipt(port, deadline, buffer)
        after
          max(deadline - System.monotonic_time(:millisecond), 0) ->
            {:error, :owner_control_unconfirmed}
        end
    end
  end

  defp verified_helper do
    with {:ok, helper} <- helper_path(false), do: verify_helper_path(helper)
  end

  defp verify_helper_path(helper) do
    with true <- is_binary(helper),
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

  defp verified_operator_helper do
    with true <- is_binary(@operator_helper_sha256),
         {:ok, helper} <- verify_helper_path(app_helper()),
         {:ok, bytes} <- File.read(helper),
         true <- :crypto.hash(:sha256, bytes) == @operator_helper_sha256 do
      {:ok, helper}
    else
      _ -> {:error, :operator_helper_identity_unavailable}
    end
  end

  @doc "Read the current OS user from the verified host helper, without launching a shell."
  def current_uid, do: read_uid(&verified_helper/0)

  @doc false
  def protected_current_uid, do: read_uid(&verified_operator_helper/0)

  defp read_uid(select_helper) do
    with {:ok, helper} <- select_helper.() do
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

  @doc "Sync an existing owner-only directory after atomic publication; grants no write authority."
  def sync_directory(path), do: sync_selected_directory(path, &verified_helper/0)

  @doc false
  def protected_sync_directory(path),
    do: sync_selected_directory(path, &verified_operator_helper/0)

  defp sync_selected_directory(path, select_helper) when is_binary(path) do
    with :ok <- launch_text(path),
         true <- Path.type(path) == :absolute,
         {:ok, helper} <- select_helper.(),
         {:ok, port, ticket} <-
           owned_port(:lock, helper, [
             :binary,
             :exit_status,
             :use_stdio,
             :hide,
             args: ["--sync-directory", path]
           ]) do
      try do
        receive_directory_sync(port, ticket, System.monotonic_time(:millisecond) + 2_000, 0)
      after
        result = if Port.info(port), do: close_process(port, true), else: :ok
        Ipse.Session.Resources.closed(ticket, result)
      end
    else
      _ -> {:error, :directory_sync_unavailable}
    end
  rescue
    _ -> {:error, :directory_sync_unavailable}
  end

  defp sync_selected_directory(_, _), do: {:error, :directory_sync_unavailable}

  @doc "Inspect bounded protected storage allocation, including directory and pending-file blocks."
  def storage_allocation(path) when is_binary(path) do
    with :ok <- launch_text(path),
         true <- Path.type(path) == :absolute,
         {:ok, helper} <- verified_helper(),
         {:ok, port, ticket} <-
           owned_port(:lock, helper, [
             :binary,
             :exit_status,
             :use_stdio,
             :hide,
             args: ["--storage-allocation", path]
           ]) do
      try do
        receive_allocation(port, ticket, System.monotonic_time(:millisecond) + 5_000, "")
      after
        result = if Port.info(port), do: close_process(port, true), else: :ok
        Ipse.Session.Resources.closed(ticket, result)
      end
    else
      _ -> {:error, :storage_allocation_unavailable}
    end
  rescue
    _ -> {:error, :storage_allocation_unavailable}
  end

  def storage_allocation(_), do: {:error, :storage_allocation_unavailable}

  @doc "Create and sync one private exclusive staging file; caller owns admission, cleanup and publication."
  def protected_staging_write(path, bytes) when is_binary(path) and is_binary(bytes) do
    with :ok <- launch_text(path),
         true <- Path.type(path) == :absolute,
         true <- byte_size(bytes) in 1..8_388_608,
         true <- Regex.match?(~r/\A\.pending-[a-f0-9]{32}\z/, Path.basename(path)),
         {:ok, helper} <- verified_helper() do
      staging_exchange(
        helper,
        ["--storage-write", path, Integer.to_string(byte_size(bytes))],
        Path.dirname(path),
        bytes
      )
    else
      _ -> {:error, :protected_staging_write_unavailable}
    end
  rescue
    _ -> {:error, :protected_staging_write_unavailable}
  end

  def protected_staging_write(_, _), do: {:error, :protected_staging_write_unavailable}

  @doc "Create and sync up to 128 private staging files with at most 8 MiB aggregate bytes."
  def protected_staging_write_many(directory, files)
      when is_binary(directory) and is_list(files) do
    with :ok <- launch_text(directory),
         true <- Path.type(directory) == :absolute,
         true <- length(files) in 1..128,
         true <-
           Enum.all?(files, fn {name, bytes} ->
             is_binary(name) and Regex.match?(~r/\A\.pending-[a-f0-9]{32}\z/, name) and
               is_binary(bytes) and byte_size(bytes) in 1..8_388_608
           end),
         true <- Enum.sum(Enum.map(files, fn {_, bytes} -> byte_size(bytes) end)) <= 8_388_608,
         true <- length(Enum.uniq_by(files, &elem(&1, 0))) == length(files),
         {:ok, helper} <- verified_helper() do
      payload =
        Enum.map(files, fn {".pending-" <> id, bytes} ->
          [id, <<byte_size(bytes)::unsigned-big-32>>, bytes]
        end)

      staging_exchange(
        helper,
        ["--storage-write-many", directory, Integer.to_string(length(files))],
        directory,
        IO.iodata_to_binary(payload)
      )
    else
      _ -> {:error, :protected_staging_write_unavailable}
    end
  rescue
    _ -> {:error, :protected_staging_write_unavailable}
  end

  def protected_staging_write_many(_, _), do: {:error, :protected_staging_write_unavailable}

  defp staging_exchange(helper, args, directory, payload) do
    deadline = System.monotonic_time(:millisecond) + 5_000

    with {:ok, ticket} <- Ipse.Session.Resources.register(:lock) do
      case open_stdio(helper, args, directory, %{}, 5_000, cleanup_ticket: ticket) do
        {:ok, port} ->
          result =
            try do
              with {:ok, buffer} <- staging_control(port, deadline, ticket, "", ?R),
                   {:ok, buffer} <- staging_send(port, payload, deadline, ticket, buffer),
                   :ok <- staging_receive(port, deadline, ticket, buffer),
                   do: :ok
            rescue
              _ -> {:error, :protected_staging_write_unavailable}
            end

          cleanup = staging_cleanup(port)
          Ipse.Session.Resources.closed(ticket, cleanup)

          if cleanup == :ok,
            do: result,
            else: {:error, {:cleanup_unconfirmed, :protected_staging_write_unavailable}}

        {:error, {:cleanup_unconfirmed, _}} ->
          Ipse.Session.Resources.closed(ticket, {:error, :cleanup_unconfirmed})
          {:error, {:cleanup_unconfirmed, :protected_staging_write_unavailable}}

        _ ->
          Ipse.Session.Resources.closed(ticket, :ok)
          {:error, :protected_staging_write_unavailable}
      end
    end
  end

  defp staging_cleanup(port) do
    # Keep terminal evidence in this owner's mailbox. Transferring a port after
    # it has emitted exit_status can strand that evidence in the old mailbox.
    previous = Process.flag(:trap_exit, true)

    try do
      close_stdio(port)
    after
      Process.flag(:trap_exit, previous)
    end
  end

  defp staging_control(_, _, _, <<?O, 1::unsigned-big-32, expected, rest::binary>>, expected) do
    {:ok, rest}
  end

  defp staging_control(port, deadline, ticket, bytes, expected) when byte_size(bytes) < 6 do
    receive do
      {^port, {:data, data}} when byte_size(bytes) + byte_size(data) <= 4096 ->
        staging_control(port, deadline, ticket, bytes <> data, expected)

      {:ipse_cancel_resource, id} when ticket != nil and ticket.id == id ->
        {:error, :protected_staging_write_unavailable}

      {^port, {:exit_status, _}} = terminal ->
        send(self(), terminal)
        {:error, :protected_staging_write_unavailable}

      {^port, _} ->
        {:error, :protected_staging_write_unavailable}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        {:error, :protected_staging_write_unavailable}
    end
  end

  defp staging_control(_, _, _, _, _), do: {:error, :protected_staging_write_unavailable}

  defp staging_send(_, <<>>, _, _, buffer), do: {:ok, buffer}

  defp staging_send(port, bytes, deadline, ticket, buffer) do
    receive do
      {:ipse_cancel_resource, id} when ticket != nil and ticket.id == id ->
        {:error, :protected_staging_write_unavailable}
    after
      0 -> staging_send_chunk(port, bytes, deadline, ticket, buffer)
    end
  end

  defp staging_send_chunk(port, bytes, deadline, ticket, buffer) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, :protected_staging_write_unavailable}
    else
      size = min(byte_size(bytes), 16_384)
      <<chunk::binary-size(^size), rest::binary>> = bytes

      case send_stdio(port, <<size::unsigned-big-32, chunk::binary>>) do
        :ok ->
          with {:ok, buffer} <- staging_control(port, deadline, ticket, buffer, ?A),
               do: staging_send(port, rest, deadline, ticket, buffer)

        {:error, "stdio input is backpressured"} ->
          receive do
            {:ipse_cancel_resource, id} when ticket != nil and ticket.id == id ->
              {:error, :protected_staging_write_unavailable}

            {^port, {:exit_status, _}} = terminal ->
              send(self(), terminal)
              {:error, :protected_staging_write_unavailable}

            {^port, _} ->
              {:error, :protected_staging_write_unavailable}
          after
            min(remaining, 5) -> staging_send(port, bytes, deadline, ticket, buffer)
          end

        _ ->
          {:error, :protected_staging_write_unavailable}
      end
    end
  end

  defp staging_receive(port, deadline, ticket, bytes) do
    receive do
      {^port, {:data, data}} when byte_size(bytes) + byte_size(data) <= 4096 ->
        staging_receive(port, deadline, ticket, bytes <> data)

      {^port, {:exit_status, 0}} ->
        send(self(), {port, {:exit_status, 0}})
        staging_result(bytes)

      {^port, {:exit_status, _}} = terminal ->
        send(self(), terminal)
        {:error, :protected_staging_write_unavailable}

      {:ipse_cancel_resource, id} when ticket != nil and ticket.id == id ->
        {:error, :protected_staging_write_unavailable}

      {^port, _} ->
        {:error, :protected_staging_write_unavailable}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        {:error, :protected_staging_write_unavailable}
    end
  end

  defp staging_result(<<?X, size::unsigned-big-32, body::binary-size(size)>>) when size <= 4096 do
    case Ipse.JSON.decode_unique(body) do
      {:ok, %{"exit_code" => 0, "timed_out" => false} = result} when map_size(result) == 2 -> :ok
      _ -> {:error, :protected_staging_write_unavailable}
    end
  end

  defp staging_result(_), do: {:error, :protected_staging_write_unavailable}

  defp receive_allocation(port, ticket, deadline, bytes) do
    receive do
      {^port, {:data, data}} when byte_size(bytes) + byte_size(data) <= 128 ->
        receive_allocation(port, ticket, deadline, bytes <> data)

      {^port, {:exit_status, 0}} ->
        case String.split(String.trim(bytes), " ") do
          [logical, allocated, entries] ->
            with {logical, ""} <- Integer.parse(logical),
                 {allocated, ""} <- Integer.parse(allocated),
                 {entries, ""} <- Integer.parse(entries),
                 true <-
                   Ipse.JSON.safe_uint?(logical) and Ipse.JSON.safe_uint?(allocated) and
                     entries in 1..40_000 do
              {:ok,
               %{"logical_bytes" => logical, "allocated_bytes" => allocated, "entries" => entries}}
            else
              _ -> {:error, :storage_allocation_unavailable}
            end

          _ ->
            {:error, :storage_allocation_unavailable}
        end

      {:ipse_cancel_resource, id} when ticket != nil and ticket.id == id ->
        {:error, :storage_allocation_unavailable}

      {^port, _} ->
        {:error, :storage_allocation_unavailable}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        {:error, :storage_allocation_unavailable}
    end
  end

  @doc """
  Display an escaped prompt and read one line through matching inherited terminals.

  This host-only primitive returns a display/input observation, never permission
  or a claim that PTY automation was a human. Clients must bind the observation
  to their actual pending version and consume it once at Session admission.
  """
  def operator_input(prompt, timeout_ms \\ 120_000) do
    with true <- is_binary(prompt) and String.valid?(prompt) and byte_size(prompt) in 1..8_192,
         true <- is_integer(timeout_ms) and timeout_ms in 1_000..600_000,
         true <- Ipse.CLI.Terminal.escape(prompt) == prompt,
         {:ok, helper} <- verified_operator_helper(),
         {:ok, port, ticket} <-
           owned_port(:lock, helper, [
             :binary,
             :exit_status,
             :nouse_stdio,
             :hide,
             args: ["--operator-input", Integer.to_string(timeout_ms)]
           ]) do
      nonce = :crypto.strong_rand_bytes(16)

      {result, cleanup} =
        case operator_read(port, ticket, prompt, nonce, timeout_ms) do
          {:exited, result} ->
            close_stdio_port(port)
            {result, :ok}

          {:pending, result} ->
            {result, close_process(port, true)}
        end

      Ipse.Session.Resources.closed(ticket, cleanup)

      case result do
        {:ok, text} ->
          {:ok,
           %{
             "version" => 1,
             "text" => text,
             "event_id" => Base.encode16(nonce, case: :lower),
             "display_sha256" => Ipse.JSON.sha256(prompt),
             "text_sha256" => Ipse.JSON.sha256(text)
           }}

        error ->
          error
      end
    else
      _ -> {:error, :operator_input_unavailable}
    end
  rescue
    _ -> {:error, :operator_input_unavailable}
  end

  defp operator_read(port, ticket, prompt, nonce, timeout_ms) do
    body = nonce <> prompt
    true = Port.command(port, <<?D, byte_size(body)::unsigned-big-32, body::binary>>)
    state = %{phase: :initial, text: nil, nonce: nonce}

    case receive_operator(
           port,
           ticket,
           <<>>,
           state,
           System.monotonic_time(:millisecond) + timeout_ms + 2_000
         ) do
      {:exited, _} = result -> result
      error -> {:pending, error}
    end
  rescue
    _ -> {:pending, {:error, :operator_input_unavailable}}
  catch
    _, _ -> {:pending, {:error, :operator_input_unavailable}}
  end

  @doc false
  def operator_channel do
    with {:ok, helper} <- verified_operator_helper(), do: Ipse.Runner.Operator.probe(helper)
  end

  @doc false
  def operator_input(prompt, timeout_ms, 2) do
    with true <- is_binary(prompt) and String.valid?(prompt),
         true <- byte_size(prompt) in 1..16_777_216,
         true <- is_integer(timeout_ms) and timeout_ms in 1_000..600_000,
         true <- Ipse.CLI.Terminal.escape(prompt) == prompt,
         {:ok, helper} <- verified_operator_helper() do
      Ipse.Runner.Operator.run(helper, prompt, timeout_ms)
    else
      _ -> {:error, :operator_input_unavailable}
    end
  end

  @doc false
  def operator_input(prompt, timeout_ms, 2, guard) when is_function(guard, 1) do
    with true <- is_binary(prompt) and String.valid?(prompt),
         true <- byte_size(prompt) in 1..16_777_216,
         true <- is_integer(timeout_ms) and timeout_ms in 1_000..600_000,
         true <- Ipse.CLI.Terminal.escape(prompt) == prompt,
         {:ok, helper} <- verified_operator_helper() do
      Ipse.Runner.Operator.run_guarded(helper, prompt, timeout_ms, guard)
    else
      _ -> {:error, :operator_input_unavailable}
    end
  end

  def operator_input(_, _, _, _), do: {:error, :operator_input_unavailable}

  defp receive_operator(port, ticket, buffer, state, deadline) do
    case buffer do
      <<_kind, size::unsigned-big-32, _::binary>> when size > 8_208 ->
        {:error, :operator_input_unavailable}

      <<kind, size::unsigned-big-32, value::binary-size(size), rest::binary>> ->
        case operator_frame(state, kind, value) do
          {:ok, state} -> receive_operator(port, ticket, rest, state, deadline)
          error -> error
        end

      _ ->
        receive do
          {^port, {:data, data}} when byte_size(buffer) + byte_size(data) <= 16_384 ->
            receive_operator(port, ticket, buffer <> data, state, deadline)

          {^port, {:exit_status, 0}} when buffer == <<>> and state.phase == :input ->
            {:exited, {:ok, state.text}}

          {^port, {:exit_status, _}} ->
            {:exited, {:error, :operator_input_unavailable}}

          {:ipse_cancel_resource, id} when ticket != nil and ticket.id == id ->
            {:error, :operator_input_cancelled}

          :ipse_cancel_operator_input ->
            {:error, :operator_input_cancelled}

          {^port, _} ->
            {:error, :operator_input_unavailable}
        after
          max(deadline - System.monotonic_time(:millisecond), 0) ->
            {:error, :operator_input_unavailable}
        end
    end
  end

  defp operator_frame(%{phase: :initial, nonce: nonce} = state, ?Y, nonce),
    do: {:ok, %{state | phase: :displayed}}

  defp operator_frame(
         %{phase: :displayed, nonce: nonce} = state,
         ?I,
         <<nonce::binary-size(16), text::binary>>
       )
       when byte_size(text) <= 8_192 do
    if String.valid?(text),
      do: {:ok, %{state | phase: :input, text: text}},
      else: {:error, :operator_input_unavailable}
  end

  defp operator_frame(%{phase: :displayed, nonce: nonce}, ?C, nonce),
    do: {:error, :operator_input_cancelled}

  defp operator_frame(_, _, _), do: {:error, :operator_input_unavailable}

  defp receive_directory_sync(port, ticket, deadline, bytes) do
    receive do
      {^port, {:exit_status, 0}} when bytes == 0 ->
        :ok

      {^port, {:exit_status, _}} ->
        {:error, :directory_sync_unavailable}

      {^port, {:data, data}} when bytes + byte_size(data) <= 4_096 ->
        receive_directory_sync(port, ticket, deadline, bytes + byte_size(data))

      {:ipse_cancel_resource, id} when ticket != nil and ticket.id == id ->
        {:error, :directory_sync_unavailable}

      {^port, _} ->
        {:error, :directory_sync_unavailable}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        {:error, :directory_sync_unavailable}
    end
  end

  @doc "Acquire a persistent advisory lock. Its Port must remain owned by the session."
  def lock(path), do: acquire_lock(path, :lock, false)

  @doc false
  def protected_lock(path), do: acquire_lock(path, :lock, true)

  @doc false
  # Internal candidate only; there is no active Session/export caller.
  def protected_export_lock(path) do
    if :os.type() == {:unix, :linux},
      do: acquire_lock(path, :lock, true, :export_v1),
      else: {:error, :export_lock_unavailable}
  end

  @doc false
  def protected_header_lock(path) do
    if :os.type() == {:unix, :linux},
      do: acquire_lock(path, :lock, true, :header_v1),
      else: {:error, :header_lock_unavailable}
  end

  @doc false
  def protected_resume_lock(path) do
    if :os.type() == {:unix, :linux},
      do: acquire_lock(path, :lock, true, :resume_v1),
      else: {:error, :header_lock_unavailable}
  end

  @doc false
  def protected_share_header_lock(path) do
    if :os.type() == {:unix, :linux},
      do: acquire_lock(path, :lock, true, :header_share_v2),
      else: {:error, :header_lock_unavailable}
  end

  @doc false
  def protected_share_resume_lock(path) do
    if :os.type() == {:unix, :linux},
      do: acquire_lock(path, :lock, true, :resume_share_v2),
      else: {:error, :header_lock_unavailable}
  end

  @doc false
  # Reserved for inactive original journal readers after journal/lock checks.
  def lock_source(path), do: acquire_lock(path, :source_lock, true)

  defp acquire_lock(path, kind, protected, mode \\ :legacy)

  defp acquire_lock(path, kind, protected, mode)
       when is_binary(path) and
              mode in [
                :legacy,
                :export_v1,
                :header_v1,
                :resume_v1,
                :header_share_v2,
                :resume_share_v2
              ] do
    with :ok <- launch_text(path),
         {:ok, helper} <- if(protected, do: verified_operator_helper(), else: helper_path()),
         {:ok, port, ticket} <-
           owned_port(kind, helper, [
             :binary,
             :exit_status,
             :use_stdio,
             :hide,
             args: [
               case mode do
                 :export_v1 -> "--lock-export-v1"
                 :header_v1 -> "--session-header-v1"
                 :resume_v1 -> "--session-resume-v1"
                 :header_share_v2 -> "--session-header-share-v2"
                 :resume_share_v2 -> "--session-resume-share-v2"
                 :legacy -> "--lock"
               end,
               Path.expand(path)
             ]
           ]) do
      Process.put({__MODULE__, port}, ticket)
      result = receive_lock(port, <<>>, System.monotonic_time(:millisecond) + 5_000, ticket)
      if match?({:error, _}, result), do: unlock(port)
      result
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp acquire_lock(_, _, _, _), do: {:error, "lock path must be a string"}

  @doc false
  def session_header_begin(port, deadline) when is_integer(deadline) do
    case session_header_request(port, ?B, 1, <<0::32>>, deadline) do
      {:ok, <<1::64, 1, dev::64, inode::64, uid::32>>} ->
        {:ok, %{device: dev, inode: inode, uid: uid}}

      _ ->
        {:error, :header_unconfirmed}
    end
  end

  @doc false
  def session_header_write(port, bytes, owner, deadline)
      when is_binary(bytes) and byte_size(bytes) in 1..16_777_217 and is_pid(owner) and
             is_integer(deadline) do
    with {:ok, <<2::64, 1>>} <-
           session_header_request(port, ?H, 2, <<byte_size(bytes)::32>>, deadline),
         {:ok, seq} <- session_header_chunks(port, bytes, owner, 3, deadline),
         true <- Process.alive?(owner),
         {:ok, <<^seq::64, 1>>} <- session_header_request(port, ?F, seq, <<>>, deadline) do
      :ok
    else
      _ -> {:error, :header_unconfirmed}
    end
  end

  def session_header_write(_, _, _, _), do: {:error, :header_unconfirmed}

  @doc false
  def session_share_export(port, seq, ordinal, operation, request, deadline)
      when is_port(port) and seq in 1..18_446_744_073_709_551_615 and
             ordinal in 1..18_446_744_073_709_551_615 and
             is_binary(operation) and byte_size(operation) == 16 and is_binary(request) and
             byte_size(request) == 68 and is_integer(deadline) do
    remaining = min(max(deadline - System.monotonic_time(:millisecond), 0), 5_000)

    case session_header_request(
           port,
           ?Y,
           seq,
           <<ordinal::64, operation::binary, remaining::32, request::binary>>,
           deadline
         ) do
      {:ok, <<^seq::64, 1, ^ordinal::64, ^operation::binary-size(16)>>} -> :ok
      _ -> {:error, :session_share_unconfirmed}
    end
  end

  def session_share_export(_, _, _, _, _, _), do: {:error, :session_share_unconfirmed}

  @doc false
  def session_share_settle(port, seq, ordinal, operation, deadline)
      when is_port(port) and seq in 1..18_446_744_073_709_551_615 and
             ordinal in 1..18_446_744_073_709_551_615 and
             is_binary(operation) and byte_size(operation) == 16 and is_integer(deadline) do
    case session_header_request(port, ?K, seq, <<ordinal::64, operation::binary>>, deadline) do
      {:ok, <<^seq::64, 1, ^ordinal::64, ^operation::binary-size(16)>>} -> :ok
      _ -> {:error, :session_share_unconfirmed}
    end
  end

  def session_share_settle(_, _, _, _, _), do: {:error, :session_share_unconfirmed}

  @doc false
  def session_header_lock_identity(port, deadline) when is_port(port) and is_integer(deadline) do
    with {:connected, owner} when owner == self() <- Port.info(port, :connected),
         {:ok, <<device::64, inode::64>>} <- session_header_send(port, ?I, <<>>, deadline),
         true <- inode > 0 do
      {:ok, %{device: device, inode: inode}}
    else
      _ -> {:error, :header_unconfirmed}
    end
  rescue
    _ -> {:error, :header_unconfirmed}
  end

  def session_header_lock_identity(_, _), do: {:error, :header_unconfirmed}

  @doc false
  def session_journal_append(port, %{device: device, inode: inode}, offset, line, deadline)
      when is_port(port) and is_integer(device) and device >= 0 and is_integer(inode) and
             inode > 0 and
             is_integer(offset) and offset > 0 and is_binary(line) and
             byte_size(line) in 1..16_777_217 and is_integer(deadline) do
    with {:connected, owner} when owner == self() <- Port.info(port, :connected),
         {:ok, "ready"} <-
           session_header_send(
             port,
             ?Q,
             <<device::64, inode::64, offset::64, byte_size(line)::64>>,
             deadline
           ),
         :ok <- session_journal_chunks(port, line, deadline),
         {:ok, "synced"} <- session_header_send(port, ?E, <<>>, deadline) do
      :ok
    else
      _ -> {:error, :journal_write_unconfirmed}
    end
  rescue
    _ -> {:error, :journal_write_unconfirmed}
  end

  def session_journal_append(_, _, _, _, _), do: {:error, :journal_write_unconfirmed}

  defp session_journal_chunks(_, <<>>, _), do: :ok

  defp session_journal_chunks(port, line, deadline) do
    size = min(byte_size(line), 16_384)
    <<chunk::binary-size(^size), rest::binary>> = line

    with {:ok, "staged"} <- session_header_send(port, ?W, chunk, deadline),
         do: session_journal_chunks(port, rest, deadline)
  end

  @doc false
  def session_journal_repair(
        port,
        %{device: device, inode: inode},
        offset,
        target,
        action,
        deadline
      )
      when is_port(port) and is_integer(device) and device >= 0 and is_integer(inode) and
             inode > 0 and
             is_integer(offset) and offset > 0 and is_integer(target) and target > 0 and
             action in [0, 1] and is_integer(deadline) do
    with {:connected, owner} when owner == self() <- Port.info(port, :connected),
         {:ok, "synced"} <-
           session_header_send(
             port,
             ?T,
             <<device::64, inode::64, offset::64, target::64, action>>,
             deadline
           ) do
      :ok
    else
      _ -> {:error, :journal_write_unconfirmed}
    end
  rescue
    _ -> {:error, :journal_write_unconfirmed}
  end

  def session_journal_repair(_, _, _, _, _, _), do: {:error, :journal_write_unconfirmed}

  @doc false
  def publish_session_release(dir, session, operation, origin, lock, bytes)
      when is_binary(dir) and is_binary(session) and is_binary(operation) and is_map(origin) and
             is_map(lock) and is_binary(bytes) and byte_size(bytes) in 1..2_048 do
    with true <- :os.type() == {:unix, :linux},
         :ok <- launch_text(dir),
         true <- origin["directory"] == dir,
         true <-
           Enum.all?(
             [origin["major_device"], origin["inode"], lock[:device], lock[:inode]],
             &Ipse.JSON.safe_uint?/1
           ),
         true <- byte_size(session) == 32 and byte_size(operation) == 32,
         {:ok, helper} <- verified_operator_helper(),
         args = [
           "--session-release-v1",
           dir,
           session,
           operation,
           Integer.to_string(origin["major_device"]),
           Integer.to_string(origin["inode"]),
           Integer.to_string(lock.device),
           Integer.to_string(lock.inode),
           Integer.to_string(byte_size(bytes))
         ],
         {:ok, port, ticket} <-
           owned_port(:lock, helper, [:binary, :exit_status, :use_stdio, :hide, args: args]) do
      deadline = System.monotonic_time(:millisecond) + 5_000

      result =
        try do
          release_publish_send(port, bytes, deadline)
        after
          close_stdio_port(port)
        end

      Ipse.Session.Resources.closed(ticket, result)
      result
    else
      _ -> {:error, :cleanup_unconfirmed}
    end
  rescue
    _ -> {:error, :cleanup_unconfirmed}
  end

  def publish_session_release(_, _, _, _, _, _), do: {:error, :cleanup_unconfirmed}

  defp release_publish_send(port, bytes, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :cleanup_unconfirmed}
    else
      case Port.command(port, bytes, [:nosuspend]) do
        true ->
          release_publish_result(port, <<>>, deadline)

        false ->
          receive do
            {^port, _} -> {:error, :cleanup_unconfirmed}
          after
            5 -> release_publish_send(port, bytes, deadline)
          end
      end
    end
  end

  defp release_publish_result(port, buffer, deadline) do
    expected = <<?P, 9::32, "published">>

    if byte_size(buffer) > byte_size(expected) or
         binary_part(expected, 0, byte_size(buffer)) != buffer do
      {:error, :cleanup_unconfirmed}
    else
      receive do
        {^port, {:data, bytes}}
        when byte_size(buffer) + byte_size(bytes) <= byte_size(expected) ->
          release_publish_result(port, buffer <> bytes, deadline)

        {^port, {:exit_status, 0}} when buffer == expected ->
          :ok

        {^port, {:exit_status, _}} ->
          {:error, :cleanup_unconfirmed}

        {:EXIT, ^port, _} ->
          release_publish_result(port, buffer, deadline)

        {^port, _} ->
          {:error, :cleanup_unconfirmed}
      after
        max(deadline - System.monotonic_time(:millisecond), 0) -> {:error, :cleanup_unconfirmed}
      end
    end
  end

  defp session_header_chunks(_port, <<>>, _owner, seq, _deadline), do: {:ok, seq}

  defp session_header_chunks(port, bytes, owner, seq, deadline) do
    count = min(byte_size(bytes), 16_384)
    <<chunk::binary-size(^count), rest::binary>> = bytes

    with true <- Process.alive?(owner),
         {:ok, <<^seq::64, 1>>} <- session_header_request(port, ?D, seq, chunk, deadline),
         do: session_header_chunks(port, rest, owner, seq + 1, deadline)
  end

  defp session_header_request(port, kind, seq, body, deadline) when is_port(port) do
    if Port.info(port, :connected) == {:connected, self()} do
      payload = <<seq::64, 1, body::binary>>
      session_header_send(port, kind, payload, deadline)
    else
      {:error, :header_unconfirmed}
    end
  rescue
    _ -> {:error, :header_unconfirmed}
  end

  defp session_header_send(port, kind, payload, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :header_unconfirmed}
    else
      case Port.command(port, <<kind, byte_size(payload)::32, payload::binary>>, [:nosuspend]) do
        true ->
          session_header_receive(port, kind, <<>>, deadline)

        false ->
          receive do
            {^port, _} -> {:error, :header_unconfirmed}
          after
            5 -> session_header_send(port, kind, payload, deadline)
          end
      end
    end
  end

  defp session_header_receive(
         _port,
         kind,
         <<kind, size::32, body::binary-size(size)>>,
         deadline
       ) do
    if System.monotonic_time(:millisecond) < deadline,
      do: {:ok, body},
      else: {:error, :header_unconfirmed}
  end

  defp session_header_receive(port, kind, bytes, deadline) when byte_size(bytes) <= 64 do
    receive do
      {^port, {:data, data}} when byte_size(bytes) + byte_size(data) <= 64 ->
        session_header_receive(port, kind, bytes <> data, deadline)

      {^port, _} ->
        {:error, :header_unconfirmed}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> {:error, :header_unconfirmed}
    end
  end

  defp session_header_receive(_, _, _, _), do: {:error, :header_unconfirmed}

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

  @doc false
  # The candidate protocol distinguishes confirmed local release from an
  # exported or otherwise uncertain description. Never use generic unlock here:
  # it intentionally discards frames for the legacy lock protocol.
  def unlock_export_candidate(port) when is_port(port) do
    if Port.info(port, :connected) == {:connected, self()} do
      ticket = Process.delete({__MODULE__, port})

      result =
        try do
          export_cancel(port, System.monotonic_time(:millisecond) + 2_000)
        rescue
          ArgumentError -> {:error, :cleanup_unconfirmed}
        after
          close_stdio_port(port)
        end

      Ipse.Session.Resources.closed(ticket, result)
      result
    else
      {:error, :cleanup_unconfirmed}
    end
  rescue
    ArgumentError -> {:error, :cleanup_unconfirmed}
  end

  def unlock_export_candidate(_), do: {:error, :cleanup_unconfirmed}

  defp export_cancel(port, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :cleanup_unconfirmed}
    else
      case Port.command(port, <<?C, 0::32>>, [:nosuspend]) do
        true ->
          export_release_result(port, <<>>, deadline)

        false ->
          receive do
            {^port, {:data, _}} -> {:error, :cleanup_unconfirmed}
            {^port, {:exit_status, _}} -> {:error, :cleanup_unconfirmed}
            {:EXIT, ^port, _} -> {:error, :cleanup_unconfirmed}
          after
            5 -> export_cancel(port, deadline)
          end
      end
    end
  end

  defp export_release_result(port, buffer, deadline) do
    expected = <<?U, 8::unsigned-big-32, "unlocked">>

    if byte_size(buffer) > byte_size(expected) or
         binary_part(expected, 0, byte_size(buffer)) != buffer do
      {:error, :cleanup_unconfirmed}
    else
      receive do
        {^port, {:data, bytes}}
        when byte_size(buffer) + byte_size(bytes) <= byte_size(expected) ->
          export_release_result(port, buffer <> bytes, deadline)

        {^port, {:data, _}} ->
          {:error, :cleanup_unconfirmed}

        {^port, {:exit_status, 0}} when buffer == expected ->
          :ok

        {^port, {:exit_status, _}} ->
          {:error, :cleanup_unconfirmed}

        {:EXIT, ^port, _} ->
          export_release_result(port, buffer, deadline)
      after
        max(deadline - System.monotonic_time(:millisecond), 0) ->
          {:error, :cleanup_unconfirmed}
      end
    end
  end

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
          invoke = fn ->
            run_supervised(
              command,
              policy.cwd,
              timeout,
              limit,
              Keyword.get(opts, :emit),
              policy.profile,
              Keyword.get(opts, :admit)
            )
          end

          if is_function(Keyword.get(opts, :admit), 1),
            do: Ipse.Session.Resources.file_effect(invoke),
            else: invoke.()
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
    protected = Keyword.get(opts, :protected_supervisor, false)
    admit_start = Keyword.get(opts, :admit_start, false)

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
      not is_boolean(protected) ->
        {:error, "protected_supervisor must be a boolean"}

      not is_boolean(admit_start) or (admit_start and listener != nil) ->
        {:error, "invalid managed stdio startup"}

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
             {:ok, helper} <- stdio_helper(policy.profile, policy.cwd, protected),
             {:ok, launch} <-
               stdio_launch_args(helper, policy, timeout_ms, executable, args, listener) do
          launch =
            if admit_start, do: List.replace_at(launch, 0, "--admitted-stdio"), else: launch

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
  def open_protected_stdio(
        executable,
        args,
        cwd,
        selected_env \\ %{},
        timeout_ms \\ 120_000,
        opts \\ []
      ) do
    open_stdio(
      executable,
      args,
      cwd,
      selected_env,
      timeout_ms,
      Keyword.put(opts, :protected_supervisor, true)
    )
  end

  defp stdio_helper(_, cwd, true), do: protected_helper(cwd)
  defp stdio_helper(profile, cwd, false), do: selected_helper(profile, cwd)

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

  @doc false
  def grant_stdio_start(port, deadline)
      when is_port(port) and is_integer(deadline) and deadline in 1..9_007_199_254_740_991 do
    if Port.command(port, <<?G, 8::unsigned-big-32, deadline::unsigned-big-64>>, [:nosuspend]),
      do: :ok,
      else: {:error, "stdio startup is backpressured"}
  rescue
    _ -> {:error, "stdio transport is closed"}
  end

  def grant_stdio_start(_, _), do: {:error, "invalid managed stdio grant"}

  @doc false
  # The native owner checks the actual wall deadline immediately before each
  # pipe write and acknowledges the complete nonce-bound frame. The caller
  # must keep its admission lease until that acknowledgement arrives.
  def send_stdio_before(port, bytes, deadline, nonce)
      when is_port(port) and is_binary(bytes) and byte_size(bytes) in 1..32_768 and
             is_integer(deadline) and deadline in 1..9_007_199_254_740_991 and
             is_binary(nonce) and byte_size(nonce) == 16 do
    payload = <<deadline::unsigned-big-64, nonce::binary, bytes::binary>>

    if Port.command(port, [<<?D, byte_size(payload)::unsigned-big-32>>, payload], [:nosuspend]),
      do: :ok,
      else: {:error, "stdio input is backpressured"}
  rescue
    _ -> {:error, "stdio transport is closed"}
  end

  def send_stdio_before(_, _, _, _), do: {:error, "invalid managed stdio input"}

  @doc false
  # These frames lend the supervisor's actual stdin description to a protected
  # transaction. Queueing is not admission or delivery: await B/F/K receipts.
  # No extension-worker or Session delivery route is admitted by this adapter.
  def prepare_stdio_share(port, operation, expiry)
      when is_port(port) and is_binary(operation) and byte_size(operation) == 16 and
             is_integer(expiry) and expiry in 1..9_007_199_254_740_991 do
    stdio_share_frame(port, ?B, <<operation::binary, expiry::64>>)
  end

  def prepare_stdio_share(_, _, _), do: {:error, :invalid_stdio_share}

  @doc false
  def export_stdio_share(port, operation, recipient, frame)
      when is_port(port) and is_binary(operation) and byte_size(operation) == 16 and
             is_binary(recipient) and byte_size(recipient) == 68 and
             is_binary(frame) and byte_size(frame) in 1..32_772,
      do:
        stdio_share_frame(
          port,
          ?F,
          <<operation::binary, recipient::binary, byte_size(frame)::32, frame::binary>>
        )

  def export_stdio_share(_, _, _, _), do: {:error, :invalid_stdio_share}

  @doc false
  def settle_stdio_share(port, operation)
      when is_port(port) and is_binary(operation) and byte_size(operation) == 16,
      do: stdio_share_frame(port, ?K, operation)

  def settle_stdio_share(_, _), do: {:error, :invalid_stdio_share}

  defp stdio_share_frame(port, tag, body) do
    cond do
      :os.type() != {:unix, :linux} -> {:error, :stdio_share_unavailable}
      Port.command(port, <<tag, byte_size(body)::32, body::binary>>, [:nosuspend]) -> :ok
      true -> {:error, :stdio_share_backpressured}
    end
  rescue
    _ -> {:error, :stdio_share_closed}
  end

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

  defp run_supervised(command, cwd, timeout, limit, emit, profile, admit) do
    with {:ok, helper} <-
           if(is_function(admit, 1),
             do: protected_helper(cwd),
             else: selected_helper(profile, cwd)
           ),
         {:ok, args} <- launch_args(helper, profile, cwd, timeout, command),
         true <- is_nil(admit) or is_function(admit, 1),
         args = if(is_function(admit, 1), do: ["--admitted-shell" | args], else: args),
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
        case shell_admission(port, ticket, admit) do
          {:ok, buffer} ->
            case frames(%{state | buffer: buffer}) do
              {:ok, ready} -> receive_output(port, ready, deadline)
              {:error, reason} -> {:unknown, reason}
            end

          other ->
            other
        end
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

  defp shell_admission(_port, _ticket, nil), do: {:ok, <<>>}

  defp shell_admission(port, ticket, admit) do
    with {:ok, <<>>} <- await_shell_boundary(port, ticket, ?R, "shell-ready-v1", <<>>) do
      case admit.(fn deadline ->
             # Ordinary effects have no source-lease deadline, but the native
             # handshake still requires a bounded grant for starting the shell.
             deadline =
               if is_nil(deadline), do: System.system_time(:millisecond) + 10_000, else: deadline

             with true <-
                    Ipse.JSON.safe_uint?(deadline) and
                      System.system_time(:millisecond) < deadline,
                  true <- Ipse.Session.Resources.active?(),
                  true <-
                    Port.command(port, <<?G, 8::unsigned-big-32, deadline::unsigned-big-64>>, [
                      :nosuspend
                    ]),
                  {:ok, tail} <- await_shell_boundary(port, ticket, ?A, "shell-started-v1", <<>>) do
               {:shell_started, tail}
             else
               {:error, _} = refusal -> refusal
               _ -> {:unknown, "Shell start was not confirmed; inspect before retrying."}
             end
           end) do
        {:shell_started, tail} -> {:ok, tail}
        {:error, _} = refusal -> refusal
        {:unknown, _} = uncertain -> uncertain
        _ -> {:unknown, "Shell start admission was not confirmed; inspect before retrying."}
      end
    end
  end

  defp await_shell_boundary(port, ticket, expected, payload, buffer) do
    case buffer do
      <<^expected, size::unsigned-big-32, rest::binary>> when byte_size(rest) >= size ->
        <<observed::binary-size(^size), tail::binary>> = rest

        if observed == payload,
          do: {:ok, tail},
          else: {:unknown, "Invalid shell admission receipt."}

      <<?E, size::unsigned-big-32, rest::binary>> when byte_size(rest) >= size ->
        <<reason::binary-size(^size), _::binary>> = rest
        {:error, sanitize(reason)}

      _ when byte_size(buffer) > 65_536 ->
        {:unknown, "Shell admission exceeded its bound."}

      _ ->
        receive do
          {^port, {:data, bytes}} ->
            await_shell_boundary(port, ticket, expected, payload, buffer <> bytes)

          {^port, {:exit_status, _}} ->
            {:unknown, "Shell supervisor exited before confirming admission."}

          {:ipse_cancel_resource, id} when ticket != nil and ticket.id == id ->
            {:unknown, "Shell admission was cancelled; inspect before retrying."}
        after
          10_000 -> {:unknown, "Shell admission timed out; inspect before retrying."}
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
