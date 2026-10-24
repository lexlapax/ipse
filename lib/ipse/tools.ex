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
        "Read a UTF-8 file in the workspace. Line offsets start at 1; output is bounded.",
        %{
          "path" => string("Workspace-relative file path"),
          "offset" => %{
            "type" => "integer",
            "minimum" => 1,
            "description" => "First line (default 1)"
          },
          "max_lines" => %{"type" => "integer", "minimum" => 1, "maximum" => 1000}
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
    dispatch(name, args, context)
  rescue
    error ->
      if mutating?(name),
        do: {:unknown, "Tool failed after possible dispatch. Inspect before retrying."},
        else: {:error, Exception.message(error) |> String.slice(0, 2_000)}
  end

  def execute(_, _, _), do: {:error, "tool arguments and context must be objects"}

  defp dispatch("read", args, context) do
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
             emit: Map.get(context, :emit)
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
