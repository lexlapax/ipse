defmodule Ipse.CLI.Doctor do
  @moduledoc "Offline configuration and storage checks, with explicitly requested provider probes."
  import Bitwise, only: [band: 2]
  alias Ipse.CLI.{Errors, Terminal}

  @recovery "docs/operator/recovery.md#diagnose-startup-and-service-errors"

  def run(opts, home, cwd) do
    uid = current_uid()
    resolved = Ipse.Config.resolve(cwd, home, opts)

    checks = [
      check("runtime.build", "ok", "Ipse #{Ipse.version()} runtime", Ipse.build_info()),
      home_layout(home, uid),
      config_files(resolved),
      config_provider(resolved, opts),
      credentials(resolved, home, uid),
      native(cwd, resolved),
      mcp(opts[:mcp_config]),
      extensions(resolved, home),
      sessions(opts[:state_dir] || Path.join(home, "sessions"), uid),
      reachability(resolved, opts, home)
    ]

    report = %{"version" => 1, "build" => Ipse.build_info(), "checks" => checks}
    {if(Enum.any?(checks, &(&1["status"] == "fail")), do: 1, else: 0), report}
  end

  def print(report, json?) do
    if json? do
      Terminal.puts(Jason.encode!(report, pretty: true))
    else
      for row <- report["checks"] do
        Terminal.puts(
          String.pad_trailing(row["status"], 5) <>
            " " <> String.pad_trailing(row["id"], 23) <> " " <> row["summary"]
        )

        print_detail(row["detail"])

        if row["status"] in ["warn", "fail", "skip"],
          do: Terminal.puts("      " <> row["recovery"])
      end
    end
  end

  defp print_detail(nil), do: :ok
  defp print_detail(detail) when is_binary(detail), do: Terminal.puts("      " <> detail)

  defp print_detail(detail) when is_map(detail),
    do: Terminal.puts("      " <> Jason.encode!(detail))

  defp print_detail(rows) when is_list(rows) do
    for row <- rows do
      if is_map(row) do
        label = row["path"] || row["provider"] || ""
        Terminal.puts("      #{row["status"]} #{label}: #{row["summary"]}")
      else
        Terminal.puts("      " <> row)
      end
    end
  end

  defp check(id, status, summary, detail \\ nil, recovery \\ @recovery) do
    %{"id" => id, "status" => status, "summary" => summary, "recovery" => recovery}
    |> then(fn row -> if is_nil(detail), do: row, else: Map.put(row, "detail", detail) end)
  end

  defp current_uid do
    with {:ok, uid} <- Ipse.Runner.current_uid() do
      uid
    else
      _ -> nil
    end
  end

  defp home_layout(home, uid) do
    rows =
      for {path, private?} <- [
            {home, false},
            {Path.join(home, "auth"), true},
            {Path.join(home, "sessions"), false}
          ],
          do: directory(path, uid, private?)

    status = aggregate(rows)
    check("home.layout", status, "Operator home, auth and session directory permissions", rows)
  end

  defp directory(path, uid, private?) do
    {status, summary} =
      case File.lstat(path) do
        {:error, :enoent} ->
          {"ok", "Missing; created on first use"}

        {:ok, %{type: :directory, uid: owner, mode: mode}} ->
          cond do
            not is_nil(uid) and owner != uid ->
              {"fail", "Directory belongs to another user"}

            band(mode, 0o022) != 0 ->
              {"fail", "Directory is group/other writable"}

            private? and band(mode, 0o077) != 0 ->
              {"fail", "Authentication directory must be owner-only"}

            is_nil(uid) ->
              {"warn", "Permissions checked; current-user identity unavailable"}

            true ->
              {"ok", "Owner and permissions checked"}
          end

        _ ->
          {"fail", "Not a readable regular directory; symlinks are refused"}
      end

    %{"path" => path, "status" => status, "summary" => summary}
  end

  defp config_files({:error, reason}), do: check("config.files", "fail", Errors.format(reason))

  defp config_files({:ok, effective}) do
    rows =
      for source <- effective.sources do
        status =
          case File.stat(source.path) do
            {:ok, %{mode: mode}} when source.scope == "operator" ->
              if band(mode, 0o077) != 0, do: "warn", else: "ok"

            {:ok, _} ->
              "ok"

            _ ->
              "fail"
          end

        %{
          "path" => source.path,
          "scope" => source.scope,
          "trusted" => true,
          "parsed" => true,
          "status" => status,
          "summary" => "Parsed and admitted; project sources require explicit trust"
        }
      end

    check("config.files", aggregate(rows), "#{length(rows)} admitted configuration files", rows)
  end

  defp config_provider({:error, _}, _opts),
    do: check("config.provider", "skip", "Resolve configuration first")

  defp config_provider({:ok, effective}, opts) do
    provider = effective.settings["provider"]
    default? = effective.provenance["provider"] == "built-in"
    endpoint = if effective.execution, do: effective.execution.base_url, else: opts[:base_url]

    valid? =
      Ipse.Provider.valid_base_url?(provider, endpoint) and
        not (Ipse.Provider.Registry.auth?(provider) and not is_nil(opts[:base_url]))

    if not valid? do
      check("config.provider", "fail", Errors.format(:invalid_provider_endpoint))
    else
      check(
        "config.provider",
        if(default?, do: "warn", else: "ok"),
        "#{provider}/#{effective.settings["model"]}; #{billing(provider)} billing" <>
          if(default?, do: "; built-in default, choose explicitly with --provider", else: "")
      )
    end
  end

  defp routes(effective, opts \\ []) do
    main =
      if effective.execution,
        do: effective.profiles[effective.execution.id],
        else: %{
          "provider" => effective.settings["provider"],
          "model" => effective.settings["model"],
          "base_url" => opts[:base_url]
        }

    roles =
      for {role, id} <- effective.roles, role in ["routine", "review"], do: effective.profiles[id]

    [main | roles] |> Enum.uniq_by(&{&1["provider"], &1["base_url"]})
  end

  defp credentials({:error, _}, _, _),
    do: check("credentials.selected", "skip", "Resolve configuration first")

  defp credentials({:ok, effective}, home, uid) do
    rows =
      for route <- routes(effective) do
        provider = route["provider"]

        {status, summary} =
          case Ipse.Provider.Registry.fetch!(provider).credential do
            :chatgpt_auth ->
              with {:ok, %{type: :regular, uid: owner, mode: mode}} <-
                     File.lstat(Path.join(home, "auth/chatgpt.json")),
                   true <- not is_nil(uid) and owner == uid and band(mode, 0o077) == 0,
                   {:ok, %{expires_at: expiry}} when is_integer(expiry) <-
                     Ipse.Auth.status(Path.join(home, "auth")),
                   true <- expiry > System.system_time(:second) do
                {"ok", "Protected unexpired local subscription credentials; no refresh attempted"}
              else
                _ ->
                  {"fail", "Subscription credentials missing, expired or unsafe; run ipse login"}
              end

            {:env, name} ->
              if System.get_env(name) not in [nil, ""],
                do: {"ok", "#{name} present"},
                else: {"fail", "Set #{name} privately"}

            _ ->
              {"ok", "No credential required"}
          end

        %{"provider" => provider, "status" => status, "summary" => summary}
      end

    check(
      "credentials.selected",
      aggregate(rows),
      "Selected profile and role credential sources",
      rows
    )
  end

  defp native(cwd, resolved) do
    requested =
      case resolved do
        {:ok, effective} -> effective.settings["sandbox"]
        _ -> "unknown"
      end

    case :os.type() do
      {:unix, os} when os in [:linux, :darwin] ->
        case Ipse.Tools.Sandbox.resolve(:native, cwd) do
          {:ok, _} ->
            check(
              "sandbox.native",
              if(os == :darwin, do: "warn", else: "ok"),
              "Requested #{requested}; native helper and workspace policy checks pass",
              "Policy availability only; kernel enforcement was not probed." <>
                if(os == :darwin, do: " macOS is experimental.", else: ""),
              "docs/operator/usage.md#choose-shell-confinement"
            )

          {:error, _} ->
            check(
              "sandbox.native",
              if(requested == "native", do: "fail", else: "warn"),
              "Requested #{requested}; native helper or workspace policy unavailable",
              nil,
              "docs/operator/usage.md#choose-shell-confinement"
            )
        end

      _ ->
        check("sandbox.native", "skip", "Native policy unavailable on this platform")
    end
  end

  defp mcp(path) do
    case Ipse.MCP.Config.load(path) do
      {:ok, servers} ->
        check("mcp.config", "ok", "#{length(servers)} configured MCP servers; none launched")

      {:error, reason} ->
        check("mcp.config", "fail", Errors.format(reason))
    end
  end

  defp extensions({:error, _}, _),
    do: check("extensions.selection", "skip", "Resolve configuration first")

  defp extensions({:ok, effective}, home) do
    case Ipse.Extension.Registry.prepare(effective.extensions, home) do
      {:ok, entries} ->
        check(
          "extensions.selection",
          "ok",
          "#{length(entries)} selected extension artifacts verified; no workers started",
          Enum.map(entries, & &1.identity["instance"])
        )

      {:error, _} ->
        check(
          "extensions.selection",
          "fail",
          "Selected extension trust, artifact or compatibility refused",
          nil,
          "docs/operator/extensions.md#recover-without-replaying-unknown-work"
        )
    end
  end

  defp sessions(path, uid) do
    layout = directory(path, uid, false)

    listing = if layout["status"] == "fail", do: {:error, :unsafe}, else: File.ls(path)

    case listing do
      {:error, :enoent} ->
        check("sessions.store", "ok", "Session store missing; created on first use")

      {:ok, names} ->
        ids =
          names
          |> Enum.filter(&Regex.match?(~r/\A[0-9a-f]{32}\.jsonl\z/, &1))
          |> Enum.map(&String.trim_trailing(&1, ".jsonl"))

        valid = Ipse.Journal.list(path)
        invalid = length(ids) - length(valid)

        check(
          "sessions.store",
          if(invalid > 0, do: "warn", else: layout["status"]),
          "#{length(valid)} readable session headers; #{invalid} unreadable, malformed or oversized; no locks tested",
          nil,
          "docs/operator/recovery.md#find-the-original-session"
        )

      _ ->
        check(
          "sessions.store",
          "fail",
          "Session directory is unreadable or unsafe",
          nil,
          "docs/operator/recovery.md#respect-active-ownership"
        )
    end
  end

  defp reachability({:error, _}, _, _),
    do: check("provider.reachability", "skip", "Resolve configuration first")

  defp reachability({:ok, effective}, opts, _home) do
    if opts[:probe_provider] do
      rows = for route <- routes(effective, opts), do: probe(route)

      check(
        "provider.reachability",
        aggregate(rows),
        "Explicit provider reachability probes",
        rows
      )
    else
      check(
        "provider.reachability",
        "skip",
        "Pass --probe-provider to request bounded non-inference GET probes"
      )
    end
  end

  defp probe(route) do
    spec = Ipse.Provider.Registry.fetch!(route["provider"])

    case spec.probe do
      :subscription ->
        %{
          "provider" => spec.id,
          "status" => "skip",
          "summary" => "Subscription reachability is verified by a real session"
        }

      :demo ->
        %{
          "provider" => spec.id,
          "status" => "skip",
          "summary" => "Scripted demo uses no model service"
        }

      {suffix, authentication} ->
        probe_route(
          route,
          spec.probe_base_url || spec.default_base_url,
          suffix,
          probe_headers(spec, authentication)
        )
    end
  end

  defp probe_headers(_spec, :none), do: []

  defp probe_headers(spec, authentication) do
    {:env, name} = spec.credential
    key = System.get_env(name) || ""

    case authentication do
      :bearer -> [{"authorization", "Bearer " <> key}]
      :anthropic -> [{"x-api-key", key}, {"anthropic-version", "2023-06-01"}]
      :gemini -> [{"x-goog-api-key", key}]
    end
  end

  defp probe_route(route, default, suffix, headers) do
    provider = route["provider"]

    {status, summary} =
      if Ipse.Provider.valid_base_url?(provider, route["base_url"]) do
        url = String.trim_trailing(route["base_url"] || default, "/") <> suffix

        case probe_get(url, headers) do
          {:ok, code} when code in 200..299 ->
            {"ok", "GET succeeded"}

          {:ok, code} when code in [401, 403] ->
            {"fail", "Credential rejected; inspect the selected credential source"}

          {:ok, _} ->
            {"fail", "GET refused; inspect endpoint and account access; no redirect or retry"}

          _ ->
            {"fail", "Provider unreachable within the probe deadline; no retry"}
        end
      else
        {"fail", "Invalid provider endpoint; no probe sent"}
      end

    %{"provider" => provider, "status" => status, "summary" => summary}
  end

  defp probe_get(url, headers) do
    deadline = System.monotonic_time(:millisecond) + 10_000
    task = Task.Supervisor.async_nolink(Ipse.Tasks, fn -> do_probe_get(url, headers) end)

    case Task.yield(task, max(deadline - System.monotonic_time(:millisecond), 0)) do
      {:ok, result} ->
        if System.monotonic_time(:millisecond) < deadline,
          do: result,
          else: {:error, :unreachable}

      _ ->
        Task.shutdown(task, :brutal_kill)
        {:error, :unreachable}
    end
  end

  defp do_probe_get(url, headers) do
    uri = URI.parse(url)

    Ipse.HTTP.with_finch(
      fn finch ->
        case Finch.stream_while(
               Finch.build(:get, url, headers),
               finch,
               nil,
               fn
                 {:status, status}, _ -> {:halt, status}
                 _, acc -> {:cont, acc}
               end,
               receive_timeout: 10_000,
               request_timeout: 10_000,
               pool_timeout: 2_000
             ) do
          {:ok, status} when is_integer(status) -> {:ok, status}
          _ -> {:error, :unreachable}
        end
      end,
      [transport_opts: [timeout: 10_000]] ++ Ipse.HTTP.finch_options(uri)
    )
  rescue
    _ -> {:error, :unreachable}
  end

  defp billing(provider), do: Ipse.Usage.billing_mode(String.to_existing_atom(provider))

  defp aggregate(rows) do
    cond do
      Enum.any?(rows, &(&1["status"] == "fail")) -> "fail"
      Enum.any?(rows, &(&1["status"] == "warn")) -> "warn"
      rows != [] and Enum.all?(rows, &(&1["status"] == "skip")) -> "skip"
      true -> "ok"
    end
  end
end
