defmodule Ipse.Tools.MacOSSandbox do
  @moduledoc "Prepares immutable signed macOS workers outside their writable grants."

  import Bitwise, only: [band: 2]

  @profile "macos-workspace-v1"
  @source_limit 32 * 1024 * 1024
  @metadata_limit 65_536
  @entry_limit 32

  @spec prepare(String.t(), String.t()) ::
          {:ok, %{worker: String.t(), data: String.t()}} | {:error, String.t()}
  def prepare(helper, cwd) when is_binary(helper) and is_binary(cwd) do
    case do_prepare(helper, cwd) do
      {:error, reason} when not is_binary(reason) -> failure("macOS sandbox cache", reason)
      result -> result
    end
  rescue
    error -> {:error, "macOS sandbox cache: #{Exception.message(error)}"}
  end

  def prepare(_, _), do: {:error, "macOS sandbox helper and workspace must be strings"}

  defp do_prepare(helper, cwd) do
    with {:ok, helper} <- regular_helper(helper),
         {:ok, cwd} <- Ipse.Workspace.canonical_path(cwd),
         :ok <- workspace_boundary(cwd, helper),
         {:ok, uid_text} <- command(helper, ["--uid"], cwd),
         {:ok, uid} <- parse_uid(uid_text),
         {:ok, root} <- cache_root(cwd, uid),
         :ok <- lock_path(root, uid),
         {:ok, lock} <- Ipse.Runner.lock(Path.join(root, "cache.lock")) do
      try do
        prepare_locked(helper, cwd, root, uid)
      after
        Ipse.Runner.unlock(lock)
      end
    end
  end

  defp prepare_locked(helper, cwd, root, uid) do
    with :ok <- inspect_entries(root, uid),
         {:ok, source} <- read_bounded(helper, @source_limit),
         digest = sha256(source),
         key = sha256(:erlang.term_to_binary({@profile, digest, cwd, root})),
         data = Path.join([root, "data", key]),
         generation = Path.join(root, key),
         :ok <- generation_capacity(root, generation),
         :ok <- ensure_data(root, data, uid),
         {:ok, xml} <- command(helper, ["--macos-entitlements", cwd, data], root) do
      expected = %{
        "profile" => @profile,
        "helper_sha256" => digest,
        "cwd" => cwd,
        "data" => data,
        "key" => key
      }

      case File.lstat(generation) do
        {:ok, _} -> validate_generation(helper, generation, expected, xml, uid)
        {:error, :enoent} -> build_generation(helper, source, generation, expected, xml, uid)
        {:error, reason} -> failure("cannot inspect generation", reason)
      end
    end
  end

  defp regular_helper(path) do
    with {:ok, %{type: :regular, mode: mode, size: size, links: 1}} <- File.lstat(path),
         true <- band(mode, 0o022) == 0 and band(mode, 0o111) != 0,
         true <- size <= @source_limit,
         {:ok, canonical} <- Ipse.Workspace.canonical_path(path) do
      {:ok, canonical}
    else
      _ -> {:error, "macOS sandbox helper must be a bounded, non-writable regular executable"}
    end
  end

  defp workspace_boundary(cwd, helper) do
    app = :code.lib_dir(:ipse)

    roots =
      if is_list(app),
        do: [helper, app |> List.to_string() |> physical!()],
        else: [helper]

    cond do
      not File.dir?(cwd) ->
        {:error, "macOS sandbox workspace does not exist"}

      Enum.any?(roots, &overlap?(cwd, &1)) ->
        {:error, "macOS sandbox workspace overlaps the active helper or application"}

      true ->
        :ok
    end
  end

  defp cache_root(cwd, uid) do
    home = System.get_env("IPSE_HOME") || Path.join(System.user_home!(), ".ipse")

    with :ok <- reject_link(home),
         {:ok, home} <- Ipse.Workspace.canonical_path(home),
         root = Path.join([home, "sandbox", "macos"]),
         false <- overlap?(cwd, root),
         :ok <- ensure_directory(home, uid),
         :ok <- ensure_directory(Path.join(home, "sandbox"), uid),
         :ok <- ensure_directory(root, uid),
         :ok <- ensure_directory(Path.join(root, "data"), uid) do
      {:ok, root}
    else
      true -> {:error, "macOS sandbox workspace overlaps its protected cache"}
      {:error, _} = error -> error
    end
  end

  defp reject_link(path) do
    case File.lstat(path) do
      {:ok, %{type: :symlink}} -> {:error, "macOS sandbox cache home cannot be a symlink"}
      {:ok, _} -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> failure("cannot inspect cache home", reason)
    end
  end

  defp ensure_directory(path, uid) do
    case File.mkdir(path) do
      :ok ->
        with :ok <- File.chmod(path, 0o700), do: check_path(path, :directory, 0o700, uid)

      {:error, :eexist} ->
        check_path(path, :directory, 0o700, uid)

      {:error, reason} ->
        failure("cannot create protected directory #{path}", reason)
    end
  end

  defp lock_path(root, uid) do
    path = Path.join(root, "cache.lock")

    case File.open(path, [:write, :binary, :exclusive]) do
      {:ok, file} ->
        File.close(file)
        with :ok <- File.chmod(path, 0o600), do: check_path(path, :regular, 0o600, uid)

      {:error, :eexist} ->
        check_path(path, :regular, 0o600, uid)

      {:error, reason} ->
        failure("cannot create cache lock", reason)
    end
  end

  defp inspect_entries(root, uid) do
    with {:ok, names} <- File.ls(root),
         entries = names -- ["data", "cache.lock"],
         true <- length(entries) <= @entry_limit,
         :ok <- inspect_cache_entries(root, entries, uid) do
      :ok
    else
      false -> {:error, "macOS sandbox cache exceeds its 32-generation limit"}
      {:error, _} = error -> error
    end
  end

  defp inspect_cache_entries(root, entries, uid) do
    Enum.reduce_while(entries, :ok, fn name, :ok ->
      path = Path.join(root, name)

      result =
        cond do
          Regex.match?(~r/\A[0-9a-f]{64}\z/, name) -> check_path(path, :directory, 0o700, uid)
          Regex.match?(~r/\A\.stage-[0-9a-f]{32}\z/, name) -> prune_stage(path, uid)
          true -> {:error, "macOS sandbox cache contains an unexpected entry"}
        end

      if result == :ok, do: {:cont, :ok}, else: {:halt, result}
    end)
  end

  defp generation_capacity(root, generation) do
    with {:error, :enoent} <- File.lstat(generation),
         {:ok, names} <- File.ls(root) do
      if length(names -- ["data", "cache.lock"]) < @entry_limit,
        do: :ok,
        else: {:error, "macOS sandbox cache has reached its 32-generation limit"}
    else
      {:ok, _} -> :ok
      {:error, reason} -> failure("cannot inspect generation capacity", reason)
    end
  end

  defp prune_stage(path, uid) do
    with {:ok, _count} <- safe_stage(path, uid, 0),
         {:ok, _} <- File.rm_rf(path) do
      :ok
    else
      {:error, reason, _} -> failure("cannot remove abandoned signing stage", reason)
      {:error, _} = error -> error
    end
  end

  defp safe_stage(_path, _uid, depth) when depth > 4,
    do: {:error, "macOS signing stage exceeds its depth bound"}

  defp safe_stage(path, uid, depth) do
    case File.lstat(path) do
      {:ok, %{uid: ^uid, type: :regular, size: size, mode: mode}}
      when size <= @source_limit and band(mode, 0o022) == 0 ->
        {:ok, 1}

      {:ok, %{uid: ^uid, type: :directory, mode: mode}} when band(mode, 0o022) == 0 ->
        with {:ok, names} <- File.ls(path),
             true <- length(names) <= 16 do
          Enum.reduce_while(names, {:ok, 1}, fn name, {:ok, count} ->
            case safe_stage(Path.join(path, name), uid, depth + 1) do
              {:ok, child_count} when count + child_count <= 32 ->
                {:cont, {:ok, count + child_count}}

              {:ok, _} ->
                {:halt, {:error, "macOS signing stage exceeds its entry bound"}}

              error ->
                {:halt, error}
            end
          end)
        else
          _ -> {:error, "macOS signing stage exceeds its entry bound"}
        end

      _ ->
        {:error, "macOS signing stage contains unsafe ownership, permissions, or links"}
    end
  end

  defp ensure_data(root, data, uid) do
    with {:ok, names} <- File.ls(Path.join(root, "data")),
         true <- Enum.all?(names, &Regex.match?(~r/\A[0-9a-f]{64}\z/, &1)),
         true <- length(names) <= @entry_limit,
         true <- length(names) < @entry_limit or Path.basename(data) in names,
         :ok <- ensure_directory(data, uid) do
      :ok
    else
      false -> {:error, "macOS sandbox data cache is invalid or full"}
      {:error, _} = error -> error
    end
  end

  defp build_generation(helper, source, generation, expected, xml, uid) do
    root = Path.dirname(generation)

    stage =
      Path.join(root, ".stage-" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower))

    with {:ok, names} <- File.ls(root),
         true <- length(names -- ["data", "cache.lock"]) < @entry_limit,
         :ok <- ensure_directory(stage, uid) do
      try do
        build_stage(helper, source, stage, generation, expected, xml, uid)
      after
        # Retain unsafe or unexpectedly changed stages for fail-closed inspection.
        if File.exists?(stage), do: prune_stage(stage, uid)
      end
    else
      false -> {:error, "macOS sandbox cache has reached its 32-generation limit"}
      {:error, _} = error -> error
    end
  end

  defp build_stage(helper, source, stage, generation, expected, xml, uid) do
    app = app_path(stage)
    contents = Path.join(app, "Contents")
    worker = worker_path(stage)
    entitlements = Path.join(stage, "entitlements.plist")

    with :ok <- ensure_directory(app, uid),
         :ok <- ensure_directory(contents, uid),
         :ok <- ensure_directory(Path.dirname(worker), uid),
         :ok <- write_private(worker, source, 0o700),
         :ok <- write_private(Path.join(contents, "Info.plist"), info_plist(expected["key"])),
         :ok <- write_private(entitlements, xml),
         {:ok, _} <-
           codesign(
             helper,
             ["--force", "--sign", "-", "--entitlements", entitlements, "--timestamp=none", app],
             stage
           ),
         :ok <- secure_signature(stage, uid),
         {:ok, signed} <- read_bounded(worker, @source_limit),
         manifest = Map.put(expected, "worker_sha256", sha256(signed)),
         :ok <- write_private(Path.join(stage, "manifest.json"), Jason.encode!(manifest)),
         {:ok, _} <- validate_generation(helper, stage, expected, xml, uid),
         :ok <- File.rename(stage, generation) do
      {:ok, %{worker: worker_path(generation), data: expected["data"]}}
    end
  end

  defp secure_signature(stage, uid) do
    directory = Path.join([app_path(stage), "Contents", "_CodeSignature"])
    resources = Path.join(directory, "CodeResources")

    with {:ok, %{type: :directory, uid: ^uid}} <- File.lstat(directory),
         {:ok, %{type: :regular, uid: ^uid, size: size}} <- File.lstat(resources),
         true <- size <= @metadata_limit,
         :ok <- File.chmod(directory, 0o700),
         :ok <- File.chmod(resources, 0o600) do
      :ok
    else
      _ -> {:error, "macOS codesign produced an unsafe signature directory"}
    end
  end

  defp validate_generation(helper, generation, expected, xml, uid) do
    entitlements_path = Path.join(generation, "entitlements.plist")

    with :ok <- validate_tree(generation, uid),
         {:ok, bytes} <- read_bounded(Path.join(generation, "manifest.json"), @metadata_limit),
         {:ok, manifest} <- Jason.decode(bytes),
         true <- is_map(manifest),
         true <- Map.delete(manifest, "worker_sha256") == expected,
         {:ok, worker} <- read_bounded(worker_path(generation), @source_limit),
         true <- manifest["worker_sha256"] == sha256(worker),
         {:ok, ^xml} <- read_bounded(entitlements_path, @metadata_limit),
         {:ok, info} <-
           read_bounded(
             Path.join([app_path(generation), "Contents", "Info.plist"]),
             @metadata_limit
           ),
         true <- info == info_plist(expected["key"]),
         {:ok, _} <-
           codesign(
             helper,
             ["--verify", "--strict", "--verbose=2", app_path(generation)],
             generation
           ),
         {:ok, displayed} <-
           codesign(
             helper,
             ["--display", "--entitlements", ":-", app_path(generation)],
             generation
           ),
         {:ok, actual_policy} <- policy_xml(displayed_xml(displayed, worker_path(generation))),
         {:ok, expected_policy} <- policy_xml(xml),
         true <- actual_policy == expected_policy do
      {:ok, %{worker: worker_path(generation), data: expected["data"]}}
    else
      {:error, _} = error -> error
      _ -> {:error, "macOS sandbox cached signature, manifest, or entitlements do not match"}
    end
  end

  defp validate_tree(generation, uid) do
    directories = [
      "",
      "IpseRunner.app",
      "IpseRunner.app/Contents",
      "IpseRunner.app/Contents/MacOS",
      "IpseRunner.app/Contents/_CodeSignature"
    ]

    files = [
      "manifest.json",
      "entitlements.plist",
      "IpseRunner.app/Contents/Info.plist",
      "IpseRunner.app/Contents/_CodeSignature/CodeResources",
      "IpseRunner.app/Contents/MacOS/ipse-runner"
    ]

    Enum.reduce_while(directories ++ files, :ok, fn relative, :ok ->
      path = if relative == "", do: generation, else: Path.join(generation, relative)
      directory? = relative in directories
      mode = if directory? or relative == List.last(files), do: 0o700, else: 0o600
      type = if directory?, do: :directory, else: :regular

      result =
        with :ok <- check_path(path, type, mode, uid),
             :ok <- check_size(path, directory?, relative == List.last(files)) do
          if directory? do
            {:ok, names} = File.ls(path)

            expected =
              for entry <- directories ++ files,
                  entry != "",
                  Path.dirname(entry) == if(relative == "", do: ".", else: relative),
                  do: Path.basename(entry)

            if Enum.sort(names) == Enum.sort(expected),
              do: :ok,
              else: {:error, "macOS cache contains unexpected files"}
          else
            :ok
          end
        end

      if result == :ok, do: {:cont, :ok}, else: {:halt, result}
    end)
  end

  defp displayed_xml(output, worker) do
    output
    |> String.split("\n")
    |> Enum.reject(
      &(&1 == "Executable=#{worker}" or
          &1 ==
            "warning: Specifying ':' in the path is deprecated and will not work in a future release")
    )
    |> Enum.join("\n")
    |> String.trim()
  end

  # codesign sorts keys and rewrites whitespace and the public DTD URL.
  # Parse only the entitlement value forms we emit; never resolve external entities.
  defp policy_xml(xml) do
    xml = xml |> String.trim() |> strip_prefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")

    dtds =
      Enum.map(["http", "https"], fn scheme ->
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"#{scheme}://www.apple.com/DTDs/PropertyList-1.0.dtd\">"
      end)

    dtd = Enum.find(dtds, &String.starts_with?(xml, &1))
    xml = if dtd, do: strip_prefix(xml, dtd), else: xml

    case Regex.run(~r/\A<plist version="1\.0">\s*<dict>(.*)<\/dict>\s*<\/plist>\z/s, xml) do
      [_, body] -> policy_entries(String.trim(body), %{})
      _ -> {:error, "macOS sandbox entitlements have an unexpected plist schema"}
    end
  end

  defp policy_entries("", entries), do: {:ok, entries}

  defp policy_entries(body, entries) when map_size(entries) < 16 do
    with {:ok, key, rest} <- xml_text(body, "key"),
         false <- Map.has_key?(entries, key),
         {:ok, value, rest} <- policy_value(String.trim_leading(rest)) do
      policy_entries(String.trim_leading(rest), Map.put(entries, key, value))
    else
      _ -> {:error, "macOS sandbox entitlements contain invalid or duplicate keys"}
    end
  end

  defp policy_entries(_, _), do: {:error, "macOS sandbox entitlements exceed their entry bound"}

  defp policy_value("<true/>" <> rest), do: {:ok, true, rest}
  defp policy_value("<false/>" <> rest), do: {:ok, false, rest}
  defp policy_value("<array>" <> rest), do: policy_strings(String.trim_leading(rest), [])
  defp policy_value(body), do: xml_text(body, "string")

  defp policy_strings("</array>" <> rest, strings), do: {:ok, Enum.reverse(strings), rest}

  defp policy_strings(body, strings) when length(strings) < 16 do
    with {:ok, string, rest} <- xml_text(body, "string") do
      policy_strings(String.trim_leading(rest), [string | strings])
    end
  end

  defp policy_strings(_, _), do: {:error, "macOS sandbox entitlement array exceeds its bound"}

  defp xml_text(body, tag) do
    case Regex.run(Regex.compile!("\\A<#{tag}>([^<]*)</#{tag}>(.*)\\z", "s"), body) do
      [_, text, rest] ->
        with {:ok, decoded} <- xml_unescape(text), do: {:ok, decoded, rest}

      _ ->
        {:error, "macOS sandbox entitlement value is invalid"}
    end
  end

  defp xml_unescape(text) do
    entity = ~r/&(amp|lt|gt|quot|apos|#[0-9]+|#x[0-9a-fA-F]+);/

    if String.contains?(Regex.replace(entity, text, ""), "&") do
      {:error, "macOS sandbox entitlement contains an unsupported XML entity"}
    else
      decoded =
        Regex.replace(entity, text, fn _, name ->
          case name do
            "amp" -> "&"
            "lt" -> "<"
            "gt" -> ">"
            "quot" -> "\""
            "apos" -> "'"
            "#x" <> number -> <<String.to_integer(number, 16)::utf8>>
            "#" <> number -> <<String.to_integer(number)::utf8>>
          end
        end)

      {:ok, decoded}
    end
  end

  defp strip_prefix(xml, prefix) do
    if String.starts_with?(xml, prefix),
      do: xml |> String.replace_prefix(prefix, "") |> String.trim_leading(),
      else: xml
  end

  defp check_size(_path, true, _worker?), do: :ok

  defp check_size(path, false, worker?) do
    limit = if worker?, do: @source_limit, else: @metadata_limit

    case File.lstat(path) do
      {:ok, %{size: size}} when size <= limit -> :ok
      _ -> {:error, "macOS sandbox cache file exceeds its size limit"}
    end
  end

  defp codesign(helper, args, cwd), do: command(helper, ["--codesign" | args], cwd)

  defp command(helper, args, cwd) do
    command = Enum.map_join([helper | args], " ", &shell_quote/1)

    case Ipse.Runner.run(command, cwd,
           sandbox: :off,
           timeout_ms: 10_000,
           output_limit: @metadata_limit
         ) do
      {:ok, %{exit_code: 0, timed_out: false, output: output}}
      when byte_size(output) < @metadata_limit ->
        {:ok, output}

      {:ok, %{timed_out: true}} ->
        {:error, "macOS sandbox setup command timed out"}

      {:ok, %{exit_code: code}} ->
        {:error, "macOS sandbox setup command failed with status #{code}"}

      {:error, _} = error ->
        error
    end
  end

  defp parse_uid(text) do
    case Integer.parse(String.trim(text)) do
      {uid, ""} when uid > 0 -> {:ok, uid}
      _ -> {:error, "macOS sandbox requires a non-root owner"}
    end
  end

  defp check_path(path, type, mode, uid) do
    case File.lstat(path) do
      {:ok, %{type: ^type, uid: ^uid, mode: actual, links: links}}
      when band(actual, 0o7777) == mode and (type == :directory or links == 1) ->
        :ok

      _ ->
        {:error, "macOS sandbox cache has unsafe ownership, permissions, or links: #{path}"}
    end
  end

  defp read_bounded(path, limit) do
    with {:ok, file} <- File.open(path, [:read, :binary]) do
      try do
        case IO.binread(file, limit + 1) do
          bytes when is_binary(bytes) and byte_size(bytes) <= limit -> {:ok, bytes}
          :eof -> {:ok, ""}
          _ -> {:error, "macOS sandbox cache input exceeds its size limit"}
        end
      after
        File.close(file)
      end
    end
  end

  defp write_private(path, bytes, mode \\ 0o600) do
    with :ok <- File.write(path, bytes, [:binary, :exclusive]), do: File.chmod(path, mode)
  end

  defp info_plist(key) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>ipse-runner</string>
    <key>CFBundleIdentifier</key><string>org.ipse.runner.#{key}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleName</key><string>IpseRunner</string>
    <key>CFBundleVersion</key><string>1</string>
    </dict></plist>
    """
  end

  defp app_path(generation), do: Path.join(generation, "IpseRunner.app")

  defp worker_path(generation),
    do: Path.join([app_path(generation), "Contents", "MacOS", "ipse-runner"])

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  defp physical!(path), do: elem(Ipse.Workspace.canonical_path(path), 1)

  defp within?(path, root),
    do: path == root or String.starts_with?(path, String.trim_trailing(root, "/") <> "/")

  defp overlap?(left, right), do: within?(left, right) or within?(right, left)
  defp shell_quote(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"
  defp failure(context, reason), do: {:error, "#{context}: #{inspect(reason)}"}
end
