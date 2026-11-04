defmodule Ipse.Tools do
  @moduledoc "Workspace file tools and trusted local shell execution."
  alias Ipse.Runner
  @output_limit 65_536
  @file_limit 1_048_576
  @scan_limit 8_388_608

  @doc false
  def path_key(path) when is_binary(path) do
    if String.valid?(path) do
      path
      |> String.normalize(:nfd)
      |> :string.casefold()
      |> IO.chardata_to_string()
      |> String.replace(~r/[\p{Cf}\x{034F}\x{FE00}-\x{FE0F}\x{E0100}-\x{E01EF}]/u, "")
      |> String.normalize(:nfc)
    end
  end

  def path_key(_), do: nil

  def definitions(sandbox \\ :off) do
    [
      tool(
        "read",
        "Read workspace UTF-8 lines or explicit base64 bytes (up to 4096 bytes/reply). Binary byte_offset selects hash-bound pages of a complete file up to file_max_bytes (maximum 32768).",
        %{
          "path" => string("Workspace-relative file path"),
          "offset" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "First line (default 1)"
          },
          "max_lines" => %{"type" => "integer", "minimum" => 1, "maximum" => 1000},
          "encoding" => %{"type" => "string", "enum" => ["base64"]},
          "max_bytes" => %{"type" => "integer", "minimum" => 1, "maximum" => 4096},
          "byte_offset" => %{
            "type" => "integer",
            "minimum" => 0,
            "maximum" => 32768,
            "description" =>
              "Select binary page offset; offsets above zero require the complete-file expected_sha256."
          },
          "file_max_bytes" => %{
            "type" => "integer",
            "minimum" => 1,
            "maximum" => 32768,
            "description" =>
              "Complete file ceiling for binary pages; requires byte_offset (default 32768)."
          },
          "expected_sha256" => %{"type" => "string", "minLength" => 64, "maxLength" => 64}
        },
        ["path"]
      ),
      tool(
        "write",
        "Create or replace a workspace file (maximum 1 MiB). Parent directories must exist.",
        %{
          "path" => string("Workspace-relative file path"),
          "content" => string("Complete UTF-8 file contents")
        },
        ["path", "content"]
      ),
      tool(
        "edit",
        "Replace one unique exact occurrence in a workspace file. Fails if old is absent or occurs more than once.",
        %{
          "path" => string("Workspace-relative file path"),
          "old" => string("Unique exact text to replace"),
          "new" => string("Replacement text")
        },
        ["path", "old", "new"]
      ),
      tool(
        "shell",
        shell_description(sandbox),
        %{
          "command" => string("Command for /bin/sh -c"),
          "timeout_ms" => %{"type" => "integer", "minimum" => 1, "maximum" => 600_000}
        },
        ["command"]
      )
    ]
  end

  def mutating?(name), do: name in ["write", "edit", "shell"]

  def execute(name, args, context) when is_map(args) and is_map(context) do
    if name in ~w(read write edit) and is_map(context[:managed_tool]) do
      Ipse.Session.ManagedToolUse.with_effect(
        context.managed_tool,
        Ipse.Session.ManagedToolUse.native_binding(name, args),
        fn _deadline -> dispatch(name, args, context) end
      )
    else
      dispatch(name, args, context)
    end
  rescue
    error ->
      if mutating?(name),
        do: {:unknown, "Tool failed after possible dispatch. Inspect before retrying."},
        else: {:error, Exception.message(error) |> String.slice(0, 2_000)}
  end

  def execute(_, _, _), do: {:error, "tool arguments and context must be objects"}

  defp dispatch("read", %{"encoding" => "base64"} = args, context), do: read_binary(args, context)

  defp dispatch("read", args, context) do
    with true <-
           not Enum.any?(
             ~w(encoding max_bytes byte_offset file_max_bytes expected_sha256),
             &Map.has_key?(args, &1)
           ) ||
             {:error, "binary read options require encoding base64"},
         do: read_text(args, context)
  end

  defp dispatch("write", args, context) do
    with {:ok, path} <- checked_path(args["path"], context, true),
         :ok <- text_arg(args["content"], "content"),
         :ok <- size_ok(args["content"]),
         :ok <- write_effect(path, args["content"]) do
      {:ok, "Wrote #{byte_size(args["content"])} bytes."}
    else
      {:error, reason} -> {:error, message(reason)}
      {:unknown, _} = unknown -> unknown
    end
  end

  defp dispatch("edit", args, context) do
    with {:ok, path} <- checked_path(args["path"], context, true),
         :ok <- text_arg(args["old"], "old"),
         :ok <- text_arg(args["new"], "new"),
         :ok <- nonempty(args["old"]),
         {:ok, original} <- read_edit_file(path),
         :ok <- unique_match(original, args["old"]),
         updated = String.replace(original, args["old"], args["new"], global: false),
         :ok <- size_ok(updated),
         :ok <- write_effect(path, updated) do
      {:ok, "Replaced one occurrence."}
    else
      {:error, reason} -> {:error, message(reason)}
      {:unknown, _} = unknown -> unknown
    end
  end

  defp dispatch("shell", args, context) do
    with :ok <- text_arg(args["command"], "command"),
         {:ok, timeout} <- integer_arg(args, "timeout_ms", 120_000, 1, 600_000),
         {:ok, result} <-
           Runner.run(args["command"], Map.get(context, :cwd, File.cwd!()),
             timeout_ms: timeout,
             output_limit: @output_limit,
             sandbox: Map.get(context, :sandbox, :off),
             emit: Map.get(context, :emit),
             admit:
               if(is_map(context[:managed_tool]),
                 do: fn start ->
                   Ipse.Session.ManagedToolUse.with_effect(
                     context.managed_tool,
                     Ipse.Session.ManagedToolUse.native_binding("shell", args),
                     start
                   )
                 end
               )
           ) do
      suffix = if result.timed_out, do: " (timed out)", else: ""
      {:ok, "Exit code: #{result.exit_code}#{suffix}\n" <> result.output}
    else
      {:error, reason} -> {:error, message(reason)}
      {:unknown, _} = unknown -> unknown
    end
  end

  defp dispatch(name, _, _),
    do: {:error, "unknown tool: #{inspect(name, limit: 20, printable_limit: 100)}"}

  defp read_text(args, context) do
    with {:ok, path} <- checked_path(args["path"], context, false),
         {:ok, offset} <- integer_arg(args, "offset", 1, 1, 100_000),
         {:ok, max_lines} <- integer_arg(args, "max_lines", 200, 1, 1000),
         {:ok, file} <- File.open(path, [:read, :binary]) do
      try do
        case read_chunks(file, offset, offset + max_lines, 1, @output_limit, @scan_limit, []) do
          {:ok, chunks} -> {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary() |> utf8()}
          error -> error
        end
      after
        File.close(file)
      end
    else
      {:error, reason} -> {:error, message(reason)}
    end
  end

  defp read_binary(args, context) do
    with true <-
           not Enum.any?(~w(offset max_lines), &Map.has_key?(args, &1)) ||
             {:error, "binary reads do not accept line options"},
         {:ok, limit} <- integer_arg(args, "max_bytes", 4096, 1, 4096),
         {:ok, file_limit, offset} <- binary_range(args, limit),
         true <-
           (is_nil(args["expected_sha256"]) or Ipse.JSON.sha256?(args["expected_sha256"])) ||
             {:error, "expected_sha256 must be a lowercase SHA-256"},
         {:ok, path} <- checked_path(args["path"], context, false),
         {:ok, before} <- File.lstat(path, time: :posix),
         true <-
           (before.type == :regular and before.links == 1 and before.size <= file_limit and
              offset <= before.size) ||
             {:error, "binary read requires a complete regular single-link file within max_bytes"},
         true <- Ipse.Session.Resources.active?() || {:error, "read owner is unavailable"},
         {:ok, file} <- :file.open(String.to_charlist(path), [:read, :binary, :raw]) do
      try do
        with {:ok, info} <- :file.read_file_info(file, time: :posix),
             true <- binary_identity(before) == binary_identity(File.Stat.from_record(info)),
             {:ok, bytes} <- binary_bytes(file, file_limit),
             true <- byte_size(bytes) == before.size,
             {:ok, ^bytes} <- binary_bytes(file, file_limit),
             {:ok, after_info} <- :file.read_file_info(file, time: :posix),
             true <- binary_identity(before) == binary_identity(File.Stat.from_record(after_info)),
             {:ok, ^path} <- checked_path(args["path"], context, false),
             {:ok, after_path} <- File.lstat(path, time: :posix),
             true <- binary_identity(before) == binary_identity(after_path),
             sha = Ipse.JSON.sha256(bytes),
             true <- is_nil(args["expected_sha256"]) or args["expected_sha256"] == sha,
             true <- Ipse.Session.Resources.active?() do
          value = %{
            "version" => 1,
            "encoding" => "base64",
            "path" => args["path"],
            "byte_count" => byte_size(bytes),
            "sha256" => sha,
            "data" => Base.encode64(bytes),
            "complete" => true
          }

          value =
            if Map.has_key?(args, "byte_offset") do
              part = binary_part(bytes, offset, min(limit, byte_size(bytes) - offset))
              finish = offset + byte_size(part)

              value
              |> Map.drop(["complete"])
              |> Map.merge(%{
                "version" => 2,
                "offset" => offset,
                "data" => Base.encode64(part),
                "page_sha256" => Ipse.JSON.sha256(part),
                "next" => if(finish < byte_size(bytes), do: finish, else: nil)
              })
            else
              value
            end

          {:ok, Jason.encode!(value)}
        else
          _ ->
            {:error,
             "binary source changed, exceeded max_bytes, or differed from expected_sha256"}
        end
      after
        :file.close(file)
      end
    else
      {:error, reason} -> {:error, message(reason)}
      _ -> {:error, "binary source unavailable"}
    end
  end

  defp binary_range(args, limit) do
    if Map.has_key?(args, "byte_offset") do
      with {:ok, offset} <- integer_arg(args, "byte_offset", 0, 0, 32768),
           {:ok, file_limit} <- integer_arg(args, "file_max_bytes", 32768, 1, 32768),
           true <- offset == 0 or Ipse.JSON.sha256?(args["expected_sha256"]) do
        {:ok, file_limit, offset}
      else
        _ -> {:error, "binary pages after offset zero require the complete file SHA-256"}
      end
    else
      if Map.has_key?(args, "file_max_bytes"),
        do: {:error, "file_max_bytes requires byte_offset"},
        else: {:ok, limit, 0}
    end
  end

  @doc false
  def workspace_binary_snapshot(path, expected_sha256, context)
      when is_binary(path) and is_map(context) do
    with true <- is_nil(expected_sha256) or Ipse.JSON.sha256?(expected_sha256),
         {:ok, resolved} <- checked_path(path, context, false),
         {:ok, before} <- File.lstat(resolved, time: :posix),
         true <- before.type == :regular and before.links == 1 and before.size in 1..@file_limit,
         true <- Ipse.Session.Resources.active?(),
         {:ok, file} <- :file.open(String.to_charlist(resolved), [:read, :binary, :raw]) do
      result =
        try do
          with {:ok, info} <- :file.read_file_info(file, time: :posix),
               true <- binary_identity(before) == binary_identity(File.Stat.from_record(info)),
               {:ok, bytes} <- binary_bytes(file, @file_limit),
               true <- byte_size(bytes) == before.size,
               {:ok, ^bytes} <- binary_bytes(file, @file_limit),
               {:ok, after_info} <- :file.read_file_info(file, time: :posix),
               true <-
                 binary_identity(before) == binary_identity(File.Stat.from_record(after_info)),
               {:ok, ^resolved} <- checked_path(path, context, false),
               {:ok, after_path} <- File.lstat(resolved, time: :posix),
               true <- binary_identity(before) == binary_identity(after_path),
               sha = Ipse.JSON.sha256(bytes),
               true <- is_nil(expected_sha256) or expected_sha256 == sha,
               true <- Ipse.Session.Resources.active?() do
            {:ok, bytes, %{"path" => path, "byte_count" => byte_size(bytes), "sha256" => sha}}
          else
            _ -> {:error, :workspace_snapshot_refused}
          end
        rescue
          _ -> {:error, :workspace_snapshot_refused}
        catch
          _, _ -> {:error, :workspace_snapshot_refused}
        end

      case :file.close(file) do
        :ok -> result
        _ -> {:unknown, :workspace_snapshot_cleanup_unconfirmed}
      end
    else
      _ -> {:error, :workspace_snapshot_refused}
    end
  end

  def workspace_binary_snapshot(_, _, _), do: {:error, :workspace_snapshot_refused}

  defp binary_bytes(file, limit) do
    case :file.pread(file, 0, limit + 1) do
      {:ok, bytes} when byte_size(bytes) <= limit -> {:ok, bytes}
      :eof -> {:ok, ""}
      _ -> {:error, :binary_read_limit}
    end
  end

  defp binary_identity(stat),
    do:
      Map.take(
        stat,
        ~w(type links size inode major_device minor_device uid gid mode mtime ctime)a
      )

  @doc false
  def binary_read_result?(text, args) do
    with true <-
           args["encoding"] == "base64" and
             not Enum.any?(~w(offset max_lines), &Map.has_key?(args, &1)),
         {:ok, limit} <- integer_arg(args, "max_bytes", 4096, 1, 4096),
         {:ok, _, _} <- binary_range(args, limit),
         {:ok, value} <- Ipse.JSON.decode_bounded(text, 8192),
         true <- binary_envelope?(value, args),
         true <- value["path"] === args["path"],
         {:ok, bytes} <- Base.decode64(value["data"]),
         true <- byte_size(bytes) <= limit,
         true <- binary_payload?(value, bytes, args, limit),
         true <- is_nil(args["expected_sha256"]) or args["expected_sha256"] == value["sha256"] do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp binary_envelope?(value, args) do
    if Map.has_key?(args, "byte_offset"),
      do:
        Enum.sort(Map.keys(value)) ==
          ~w(byte_count data encoding next offset page_sha256 path sha256 version) and
          value["version"] === 2 and value["encoding"] == "base64",
      else:
        Enum.sort(Map.keys(value)) == ~w(byte_count complete data encoding path sha256 version) and
          value["version"] === 1 and value["encoding"] == "base64" and value["complete"] === true
  end

  defp binary_payload?(%{"version" => 1} = value, bytes, _, _),
    do: value["byte_count"] === byte_size(bytes) and value["sha256"] === Ipse.JSON.sha256(bytes)

  defp binary_payload?(%{"version" => 2} = value, bytes, args, limit) do
    with {:ok, maximum, offset} <- binary_range(args, limit),
         count when is_integer(count) and count >= 0 and count <= maximum <- value["byte_count"],
         true <- value["offset"] === offset and offset <= count,
         true <- byte_size(bytes) == min(limit, count - offset),
         true <- value["page_sha256"] === Ipse.JSON.sha256(bytes),
         true <- Ipse.JSON.sha256?(value["sha256"]),
         finish = offset + byte_size(bytes),
         true <- value["next"] === if(finish < count, do: finish, else: nil) do
      true
    else
      _ -> false
    end
  end

  defp write_effect(path, content) do
    Ipse.Session.Resources.file_effect(fn -> write_file(path, content) end)
  end

  defp write_file(path, content) do
    with {:ok, %File.Stat{type: :directory}} <- File.stat(Path.dirname(path)) do
      case File.write(path, content) do
        :ok -> :ok
        {:error, reason} -> {:unknown, "Write may have changed the file: " <> message(reason)}
      end
    else
      {:ok, _} -> {:error, "Write parent must be an existing directory"}
      {:error, reason} -> {:error, message(reason)}
    end
  end

  defp shell_description(:native),
    do:
      "Request a local shell command under the native workspace sandbox. Files and network are restricted; setup fails closed. macOS descendant cleanup is best effort: detached children may continue changing the workspace after cancellation. Output and execution time are bounded."

  defp shell_description(_),
    do:
      "Run a trusted local shell command in the workspace with the user's filesystem and network permissions. Shell execution is unsandboxed unless the fixed native policy is explicitly selected. Output is bounded and execution times out."

  defp checked_path(path, context, mutation) do
    with :ok <- text_arg(path, "path"),
         true <-
           (path != "" and byte_size(path) <= 4096 and not String.contains?(path, <<0>>)) ||
             {:error, "invalid path"} do
      cwd = Path.expand(Map.get(context, :cwd, File.cwd!()))
      expanded = Path.expand(path, cwd)

      cond do
        expanded != cwd and
            not String.starts_with?(expanded, String.trim_trailing(cwd, "/") <> "/") ->
          {:error, "path is outside the workspace"}

        mutation and Enum.any?(Path.split(expanded), &(path_key(&1) == ".git")) ->
          {:error, "writing .git paths is forbidden"}

        true ->
          with {:ok, path} <- reject_symlinks(expanded),
               :ok <- reject_parallel_hardlinks(path, mutation, context) do
            {:ok, path}
          end
      end
    end
  end

  defp reject_parallel_hardlinks(path, true, %{parallel_child: true}) do
    reject_hardlinks(path)
  end

  defp reject_parallel_hardlinks(path, true, %{workspace_edit_grant: true}) do
    reject_hardlinks(path)
  end

  defp reject_parallel_hardlinks(_, _, _), do: :ok

  defp reject_hardlinks(path) do
    case File.stat(path) do
      {:ok, %{links: links}} when links > 1 ->
        {:error, "scoped workspace edits cannot mutate hardlinked files"}

      _ ->
        :ok
    end
  end

  defp reject_symlinks(path) do
    result =
      Enum.reduce_while(Path.split(path), "", fn part, acc ->
        current = if acc == "", do: part, else: Path.join(acc, part)

        case File.lstat(current) do
          {:ok, %{type: :symlink}} -> {:halt, {:error, "symlink paths are forbidden"}}
          {:ok, _} -> {:cont, current}
          {:error, :enoent} -> {:cont, current}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:error, _} = error -> error
      _ -> {:ok, path}
    end
  end

  defp read_chunks(_file, _start, finish, line, remaining, _scan, chunks)
       when line >= finish or remaining <= 0,
       do: {:ok, chunks}

  defp read_chunks(_file, _start, _finish, _line, _remaining, scan, _chunks)
       when scan <= 0,
       do: {:error, "read scan limit exceeded (8 MiB); choose an earlier offset"}

  defp read_chunks(file, start, finish, line, remaining, scan, chunks) do
    case IO.binread(file, min(8192, scan)) do
      :eof ->
        {:ok, chunks}

      {:error, reason} ->
        {:error, reason}

      bytes ->
        {next_line, next_remaining, next_chunks} =
          select_lines(bytes, start, finish, line, remaining, chunks)

        read_chunks(
          file,
          start,
          finish,
          next_line,
          next_remaining,
          scan - byte_size(bytes),
          next_chunks
        )
    end
  end

  defp select_lines(<<>>, _start, _finish, line, remaining, chunks), do: {line, remaining, chunks}

  defp select_lines(_bytes, _start, finish, line, remaining, chunks)
       when line >= finish or remaining <= 0,
       do: {line, remaining, chunks}

  defp select_lines(bytes, start, finish, line, remaining, chunks) do
    {segment, rest, increment} =
      case :binary.match(bytes, "\n") do
        :nomatch ->
          {bytes, <<>>, 0}

        {index, 1} ->
          size = index + 1
          {binary_part(bytes, 0, size), binary_part(bytes, size, byte_size(bytes) - size), 1}
      end

    {remaining, chunks} =
      if line >= start do
        count = min(byte_size(segment), remaining)
        {remaining - count, [binary_part(segment, 0, count) | chunks]}
      else
        {remaining, chunks}
      end

    select_lines(rest, start, finish, line + increment, remaining, chunks)
  end

  defp read_edit_file(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, file} ->
        try do
          case IO.binread(file, @file_limit + 1) do
            :eof ->
              {:ok, ""}

            {:error, reason} ->
              {:error, reason}

            bytes ->
              with :ok <- size_ok(bytes),
                   :ok <- text_arg(bytes, "file contents"),
                   do: {:ok, bytes}
          end
        after
          File.close(file)
        end

      error ->
        error
    end
  end

  defp unique_match(original, old) do
    case :binary.match(original, old) do
      :nomatch ->
        {:error, "old text was not found"}

      {index, _length} ->
        rest = binary_part(original, index + 1, byte_size(original) - index - 1)

        case :binary.match(rest, old) do
          :nomatch -> :ok
          _ -> {:error, "old text occurs more than once; include more surrounding context"}
        end
    end
  end

  defp nonempty(""), do: {:error, "old text must not be empty"}
  defp nonempty(_), do: :ok
  defp size_ok(bytes) when byte_size(bytes) <= @file_limit, do: :ok
  defp size_ok(_), do: {:error, "file size exceeds the 1 MiB limit"}

  defp text_arg(value, name) do
    if is_binary(value) and String.valid?(value),
      do: :ok,
      else: {:error, "#{name} must be a UTF-8 string"}
  end

  defp integer_arg(args, name, default, low, high) do
    value = Map.get(args, name, default)

    if is_integer(value) and value >= low and value <= high,
      do: {:ok, value},
      else: {:error, "#{name} must be an integer between #{low} and #{high}"}
  end

  defp utf8(bytes) do
    case :unicode.characters_to_binary(bytes, :utf8, :utf8) do
      valid when is_binary(valid) -> valid
      {:incomplete, good, _} -> good
      {:error, good, <<_bad, rest::binary>>} -> good <> "?" <> utf8(rest)
    end
  end

  defp message(reason) when is_atom(reason), do: :file.format_error(reason) |> List.to_string()
  defp message(reason) when is_binary(reason), do: reason
  defp message(reason), do: inspect(reason, limit: 20)
  defp string(description), do: %{"type" => "string", "description" => description}

  defp tool(name, description, properties, required) do
    %{
      "type" => "function",
      "function" => %{
        "name" => name,
        "description" => description,
        "parameters" => %{
          "type" => "object",
          "properties" => properties,
          "required" => required,
          "additionalProperties" => false
        }
      }
    }
  end

  @response_calls 32
  @turn_calls 128
  @response_arguments 2 * 1024 * 1024
  @turn_arguments 8 * 1024 * 1024

  def empty_call_budget, do: %{calls: 0, argument_bytes: 0}

  def restore_call_budget(messages) do
    Enum.reduce(messages, empty_call_budget(), fn
      %{"role" => "user"}, _ ->
        empty_call_budget()

      %{"role" => "assistant", "tool_calls" => calls}, used when is_list(calls) ->
        charge(used, calls)

      _, used ->
        used
    end)
  end

  def admit_calls(calls, used) when is_list(calls) do
    bounded = Enum.take(calls, @response_calls + 1)
    next = charge(used, bounded)

    cond do
      length(bounded) > @response_calls or next.calls > @turn_calls or
        next.argument_bytes - used.argument_bytes > @response_arguments or
          next.argument_bytes > @turn_arguments ->
        {:error, :tool_call_limit}

      not valid_calls?(bounded) ->
        {:error, :tool_call_identity}

      true ->
        {:ok, next}
    end
  end

  def admit_calls(_, _), do: {:error, :tool_call_identity}

  defp valid_calls?(calls) do
    Enum.all?(calls, fn
      %{"id" => id} = call ->
        valid_call_id?(id) and (is_nil(call["function"]) or is_map(call["function"]))

      _ ->
        false
    end) and length(Enum.uniq_by(calls, & &1["id"])) == length(calls)
  end

  defp charge(used, calls) do
    %{
      calls: used.calls + length(calls),
      argument_bytes: used.argument_bytes + Enum.reduce(calls, 0, &(argument_bytes(&1) + &2))
    }
  end

  defp argument_bytes(%{"function" => %{"arguments" => args}}) when is_binary(args),
    do: byte_size(args)

  defp argument_bytes(_), do: 0

  def valid_call_id?(id) when is_binary(id),
    do: byte_size(id) in 1..256 and String.valid?(id)

  def valid_call_id?(_), do: false
end
