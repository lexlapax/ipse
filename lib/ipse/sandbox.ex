defmodule Ipse.Sandbox do
  @moduledoc "Selects the fixed native shell sandbox policy."

  @profile "linux-workspace-v1"
  @system_paths [
    "/tmp",
    "/usr",
    "/bin",
    "/lib",
    "/lib64",
    "/etc",
    "/dev",
    "/proc",
    "/sys",
    "/run"
  ]
  @credential_dirs [".ipse", ".ssh", ".aws", ".codex"]

  def resolve(:off, cwd) when is_binary(cwd) do
    {:ok, %{requested: :off, cwd: Path.expand(cwd), profile: nil}}
  end

  def resolve(:native, cwd) when is_binary(cwd) do
    with :ok <- ensure_available(),
         {:ok, canonical_cwd} <- Ipse.WorkspaceContext.canonical_path(cwd),
         true <- File.dir?(canonical_cwd) || {:error, "sandbox workspace does not exist"},
         :ok <- validate_workspace(canonical_cwd) do
      {:ok, %{requested: :native, cwd: canonical_cwd, profile: @profile}}
    else
      {:error, _} = error -> error
      false -> {:error, "sandbox workspace is invalid"}
    end
  end

  def resolve(_, _), do: {:error, "sandbox must be :off or :native"}

  @doc "Describe the requested policy and platform capability; this is not an activation claim."
  def info(mode \\ :off) do
    %{
      requested: mode,
      backend: if(mode == :native, do: @profile, else: nil),
      platform_supported: native_platform?(),
      note:
        "This reports the requested mode and platform support. A native helper must still accept each workspace and command before execution."
    }
  end

  def profile, do: @profile

  defp ensure_available do
    if native_platform?(),
      do: :ok,
      else: {:error, "native sandbox backend is unavailable on this platform"}
  end

  defp native_platform? do
    architecture = :erlang.system_info(:system_architecture) |> List.to_string()

    :os.type() == {:unix, :linux} and
      (String.starts_with?(architecture, "x86_64-") or
         String.starts_with?(architecture, "aarch64-"))
  end

  defp validate_workspace(cwd) do
    with true <- cwd != "/" || {:error, "sandbox workspace cannot be the filesystem root"},
         :ok <- reject_overlaps(cwd, @system_paths),
         {:ok, homes} <- canonical_homes(),
         true <-
           Enum.all?(homes, &(not within?(&1, cwd))) ||
             {:error, "sandbox workspace includes a home directory"},
         :ok <-
           reject_overlaps(
             cwd,
             Enum.flat_map(homes, &Enum.map(@credential_dirs, fn dir -> Path.join(&1, dir) end)) ++
               ipse_home()
           ) do
      :ok
    else
      {:error, _} = error -> error
      false -> {:error, "sandbox workspace overlaps a protected path"}
    end
  end

  defp canonical_homes do
    homes = Enum.uniq(Enum.filter([System.user_home(), System.get_env("HOME")], &is_binary/1))

    Enum.reduce_while(homes, {:ok, []}, fn home, {:ok, acc} ->
      case Ipse.WorkspaceContext.canonical_path(home) do
        {:ok, canonical} -> {:cont, {:ok, [canonical | acc]}}
        {:error, reason} -> {:halt, {:error, "cannot resolve home directory: #{inspect(reason)}"}}
      end
    end)
    |> case do
      {:ok, []} -> {:error, "cannot resolve home directory"}
      {:ok, resolved} -> {:ok, Enum.uniq(resolved)}
      error -> error
    end
  end

  defp ipse_home do
    case System.get_env("IPSE_HOME") do
      path when is_binary(path) and path != "" -> [path]
      _ -> []
    end
  end

  defp reject_overlaps(cwd, paths) do
    Enum.reduce_while(paths, :ok, fn path, :ok ->
      case Ipse.WorkspaceContext.canonical_path(path) do
        {:ok, protected} ->
          if (protected == "/tmp" and cwd == protected) or
               (protected != "/tmp" and overlap?(cwd, protected)),
             do: {:halt, {:error, "sandbox workspace overlaps a protected path: #{protected}"}},
             else: {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, "cannot resolve protected path #{path}: #{inspect(reason)}"}}
      end
    end)
  end

  defp overlap?(left, right), do: within?(left, right) or within?(right, left)

  defp within?(path, root) do
    path == root or String.starts_with?(path, String.trim_trailing(root, "/") <> "/")
  end
end
