defmodule Ipse.Extension.WorkspaceSnapshot do
  @moduledoc false

  # This private slot lives only in the Host task that owns the Worker.  Its
  # opaque handle is not authority outside that task and invocation.
  @key {__MODULE__, :snapshot}
  @max_bytes 1_048_576
  @page_bytes 4096
  @error {:error, :workspace_snapshot_refused}

  def request?(request) when is_map(request) do
    args = request["arguments"]

    with true <- Enum.sort(Map.keys(request)) == ~w(arguments name op timeout_ms),
         true <- request["op"] === "tool.call" and request["name"] === "read",
         true <- request["timeout_ms"] === 5_000 and is_map(args),
         true <- is_binary(args["path"]) and byte_size(args["path"]) in 1..4096,
         :ok <- Ipse.Extension.validate(request) do
      case args["snapshot"] do
        "start" ->
          keys = Enum.sort(Map.keys(args))

          keys in [~w(path snapshot), ~w(expected_sha256 path snapshot)] and
            (is_nil(args["expected_sha256"]) or Ipse.JSON.sha256?(args["expected_sha256"]))

        "verify" ->
          Enum.sort(Map.keys(args)) == ~w(expected_sha256 path snapshot) and
            Ipse.JSON.sha256?(args["expected_sha256"])

        "page" ->
          Enum.sort(Map.keys(args)) ==
            ~w(byte_offset expected_sha256 path snapshot snapshot_handle) and
            is_integer(args["byte_offset"]) and args["byte_offset"] in 0..(@max_bytes - 1) and
            Ipse.JSON.sha256?(args["expected_sha256"]) and
            is_binary(args["snapshot_handle"]) and
            Regex.match?(~r/\A[0-9a-f]{32}\z/, args["snapshot_handle"])

        _ ->
          false
      end
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def request?(_), do: false

  def page_request?(request),
    do: request?(request) and request["arguments"]["snapshot"] === "page"

  def retained_request?(request),
    do: request?(request) and request["arguments"]["snapshot"] in ~w(start page)

  # The action has already passed Session tool-context admission. The file
  # effect and managed current-use callback run in the existing owned scope.
  def execute(context, intent) do
    request = intent["request"]
    args = request["arguments"]
    deadline = System.monotonic_time(:millisecond) + request["timeout_ms"]

    case args["snapshot"] do
      "start" ->
        case guarded(
               context,
               request,
               fn ->
                 Ipse.Tools.workspace_binary_snapshot(
                   args["path"],
                   args["expected_sha256"],
                   context
                 )
               end,
               deadline
             ) do
          {:ok, bytes, metadata} ->
            with {:ok, value} <- retain(context, intent, bytes, metadata, deadline),
                 do: result(request, value, deadline)

          {:error, _} ->
            {:failed, %{"reason" => "tool_failed"}}

          _ ->
            {:unknown, %{}}
        end

      "verify" ->
        case guarded(
               context,
               request,
               fn ->
                 Ipse.Tools.workspace_binary_snapshot(
                   args["path"],
                   args["expected_sha256"],
                   context
                 )
               end,
               deadline
             ) do
          {:ok, _bytes, metadata} -> result(request, metadata, deadline)
          {:error, _} -> {:failed, %{"reason" => "tool_failed"}}
          _ -> {:unknown, %{}}
        end

      "page" ->
        with {:ok, prepared} <-
               prepare_page(
                 context,
                 intent,
                 args["snapshot_handle"],
                 args["byte_offset"],
                 args["path"],
                 args["expected_sha256"],
                 deadline
               ),
             {:ok, ^prepared} <- guarded(context, request, fn -> {:ok, prepared} end, deadline),
             :ok <-
               commit_page(
                 context,
                 intent,
                 args["snapshot_handle"],
                 args["byte_offset"],
                 args["path"],
                 args["expected_sha256"],
                 prepared,
                 deadline
               ),
             {:ok, value} <- result(request, prepared, deadline) do
          {:ok, value}
        else
          _ -> {:unknown, %{}}
        end

      _ ->
        {:unknown, %{}}
    end
  rescue
    _ -> {:unknown, %{}}
  catch
    _, _ -> {:unknown, %{}}
  end

  defp guarded(context, request, callback, deadline) do
    if System.monotonic_time(:millisecond) >= deadline, do: throw(:workspace_snapshot_deadline)

    task =
      Ipse.Session.Resources.async(fn ->
        Ipse.Session.Resources.file_effect(fn ->
          Ipse.Session.ManagedToolUse.with_effect(
            context.managed_tool,
            Ipse.Session.ManagedToolUse.native_binding("read", request["arguments"]),
            fn _deadline -> callback.() end
          )
        end)
      end)

    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    case Task.yield(task, remaining) do
      {:ok, result} ->
        result

      _ ->
        Task.shutdown(task, :brutal_kill)
        {:unknown, :workspace_snapshot_unconfirmed}
    end
  end

  defp result(request, value, deadline) do
    text = Jason.encode!(value)

    if System.monotonic_time(:millisecond) < deadline and
         byte_size(text) <= 8192 and valid_result?(request, text) and
         Ipse.Extension.validate(%{
           "api_version" => 1,
           "invocation_id" => String.duplicate("0", 32),
           "operation_id" => String.duplicate("0", 32),
           "step" => 16,
           "outcome" => %{"status" => "ok", "value" => %{"text" => text}}
         }) == :ok and System.monotonic_time(:millisecond) < deadline,
       do: {:ok, %{"text" => text}},
       else: {:unknown, %{}}
  end

  def valid_result?(request, text) do
    with true <- request?(request),
         {:ok, value} <- Ipse.JSON.decode_bounded(text, 8192),
         args = request["arguments"],
         count when is_integer(count) and count in 1..@max_bytes <- value["byte_count"],
         true <- value["path"] === args["path"],
         true <- Ipse.JSON.sha256?(value["sha256"]),
         true <- is_nil(args["expected_sha256"]) or args["expected_sha256"] === value["sha256"] do
      case args["snapshot"] do
        "verify" ->
          Enum.sort(Map.keys(value)) == ~w(byte_count path sha256)

        "start" ->
          Enum.sort(Map.keys(value)) == ~w(byte_count handle path sha256) and
            valid_handle?(value["handle"])

        "page" ->
          handle = value["handle"]

          with true <- valid_handle?(handle),
               true <-
                 Enum.sort(Map.keys(value)) ==
                   ~w(byte_count data handle next offset page_sha256 path sha256),
               true <-
                 handle === args["snapshot_handle"] and value["offset"] === args["byte_offset"],
               offset when is_integer(offset) and offset >= 0 and offset < count <-
                 value["offset"],
               {:ok, bytes} <- Base.decode64(value["data"]),
               true <- byte_size(bytes) === min(@page_bytes, count - offset),
               true <- value["page_sha256"] === Ipse.JSON.sha256(bytes),
               finish = offset + byte_size(bytes) do
            value["next"] === if(finish < count, do: finish, else: nil)
          else
            _ -> false
          end
      end
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp valid_handle?(handle),
    do: is_binary(handle) and Regex.match?(~r/\A[0-9a-f]{32}\z/, handle)

  def retain(context, intent, bytes, metadata, deadline)
      when is_binary(bytes) and is_map(metadata) do
    with nil <- Process.get(@key),
         true <-
           request?(intent["request"]) and
             get_in(intent, ["request", "arguments", "snapshot"]) === "start",
         {:ok, binding} <- binding(context, intent),
         true <- byte_size(bytes) in 1..@max_bytes,
         true <- metadata["byte_count"] === byte_size(bytes),
         true <- metadata["sha256"] === Ipse.JSON.sha256(bytes),
         true <- Enum.sort(Map.keys(metadata)) == ~w(byte_count path sha256),
         true <-
           is_binary(metadata["path"]) and
             metadata["path"] === get_in(intent, ["request", "arguments", "path"]),
         expected = get_in(intent, ["request", "arguments", "expected_sha256"]),
         true <- is_nil(expected) or expected === metadata["sha256"],
         true <- active_before_deadline?(deadline) do
      handle = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
      monitors = Enum.map([binding.worker, binding.owner, binding.scope], &Process.monitor/1)

      state = %{
        binding: binding,
        bytes: bytes,
        metadata: metadata,
        handle: handle,
        next: 0,
        monitors: monitors
      }

      Process.put(@key, state)
      {:ok, Map.put(metadata, "handle", handle)}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def retain(_, _, _, _, _), do: @error

  def prepare_page(context, intent, handle, offset, path, sha256, deadline) do
    with true <- page_request?(intent["request"]),
         %{binding: binding, bytes: bytes, metadata: metadata, handle: ^handle, next: ^offset} <-
           Process.get(@key),
         {:ok, ^binding} <- binding(context, intent),
         true <- metadata["path"] === path and metadata["sha256"] === sha256,
         true <- get_in(intent, ["request", "arguments", "snapshot_handle"]) === handle,
         true <- get_in(intent, ["request", "arguments", "byte_offset"]) === offset,
         true <- get_in(intent, ["request", "arguments", "path"]) === path,
         true <- get_in(intent, ["request", "arguments", "expected_sha256"]) === sha256,
         true <- is_integer(offset) and offset >= 0 and offset < byte_size(bytes),
         true <- active_before_deadline?(deadline) do
      size = min(@page_bytes, byte_size(bytes) - offset)
      part = binary_part(bytes, offset, size)
      next = offset + size

      {:ok,
       metadata
       |> Map.merge(%{
         "handle" => handle,
         "offset" => offset,
         "data" => Base.encode64(part),
         "page_sha256" => Ipse.JSON.sha256(part),
         "next" => if(next < byte_size(bytes), do: next, else: nil)
       })}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  # The caller may advance only after the guarded callback and its cleanup
  # return confirmed success. A failed journal or delivery ends the invocation.
  def commit_page(context, intent, handle, offset, path, sha256, confirmed, deadline) do
    with {:ok, ^confirmed} <-
           prepare_page(context, intent, handle, offset, path, sha256, deadline),
         %{next: ^offset} = state <- Process.get(@key),
         {:ok, bytes} <- Base.decode64(confirmed["data"]) do
      Process.put(@key, %{state | next: offset + byte_size(bytes)})
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp active_before_deadline?(deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    remaining > 0 and Ipse.Session.Resources.active?(min(remaining, 5_000)) and
      System.monotonic_time(:millisecond) < deadline
  end

  def clear do
    case Process.delete(@key) do
      %{monitors: monitors} -> Enum.each(monitors, &Process.demonitor(&1, [:flush]))
      _ -> :ok
    end

    :ok
  end

  defp binding(context, intent) do
    with %{worker: worker, managed_tool: %{owner: owner, job_ref: job}} <- context,
         scope when is_pid(scope) <- Ipse.Session.Resources.current(),
         true <- is_pid(worker) and is_pid(owner) and is_reference(job),
         true <- Process.alive?(worker) and Process.alive?(owner) and Process.alive?(scope),
         parent when is_binary(parent) <- intent["parent_invocation_id"],
         identity when is_binary(identity) <- intent["identity_sha256"],
         cwd when is_binary(cwd) <- context[:cwd] do
      {:ok,
       %{
         worker: worker,
         owner: owner,
         job: job,
         scope: scope,
         parent: parent,
         identity: identity,
         cwd: cwd
       }}
    else
      _ -> @error
    end
  end
end
