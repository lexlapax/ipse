defmodule Ipse.Tools.Sandbox do
  @moduledoc "Selects the fixed native shell sandbox policy."

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
         {:ok, canonical_cwd} <- Ipse.Workspace.canonical_path(cwd),
         true <- File.dir?(canonical_cwd) || {:error, "sandbox workspace does not exist"},
         :ok <- validate_workspace(canonical_cwd),
         {:ok, _helper} <- Ipse.Runner.native_helper(canonical_cwd) do
      {:ok, %{requested: :native, cwd: canonical_cwd, profile: profile()}}
    else
      {:error, _} = error -> error
      false -> {:error, "sandbox workspace is invalid"}
    end
  end

  def resolve(_, _), do: {:error, "sandbox must be :off or :native"}

  @doc false
  def helper_boundary(cwd, helper) do
    with {:ok, workspace} <- Ipse.Workspace.canonical_path(cwd),
         {:ok, app} <- Ipse.Workspace.canonical_path(Application.app_dir(:ipse)) do
      if Enum.any?([helper, app], &overlap?(workspace, &1)),
        do: {:error, "native sandbox workspace overlaps the active helper or application"},
        else: :ok
    else
      _ -> {:error, "cannot resolve native helper or application boundary"}
    end
  end

  @doc "Describe the requested policy and platform capability; this is not an activation claim."
  def info(mode \\ :off) do
    %{
      requested: mode,
      backend: if(mode == :native, do: profile(), else: nil),
      platform_supported: native_platform?(),
      visibility: visibility(mode),
      note:
        "This reports requested policy, not activation." <>
          if(mode == :native and :os.type() == {:unix, :darwin},
            do:
              " macOS descendant cleanup is best effort; detached children may survive cancellation while remaining sandboxed.",
            else: ""
          )
    }
  end

  @doc "Allowlisted shell visibility facts, not evidence that a command activated the policy."
  def visibility(mode, platform \\ :os.type())

  def visibility(:native, {:unix, :linux}) do
    [
      "Linux native workspace sandbox: only the selected workspace, private temporary storage, and fixed system tool/library/device paths are visible. Workspace and private temporary storage are writable; system paths are read-only.",
      "Sibling repositories and host home/configuration paths are not mounted. HOME and TMPDIR refer to private temporary storage, not the operator's home. There are no extra dependency roots.",
      "Host /proc is absent. /dev/fd and standard descriptor paths refer only to the job's private PID namespace; host process data is unavailable. Network sockets are denied.",
      "The shell receives only system PATH, LANG, and private HOME/TMPDIR. Host environment variables and credentials are not inherited. Do not assume USER is set; fixtures can use an explicit non-secret value.",
      visibility_warning()
    ]
  end

  def visibility(:native, {:unix, :darwin}) do
    [
      "macOS native workspace sandbox: the selected workspace and private temporary storage are writable. OS-required reads and fixed Homebrew roots are permitted by the signed App Sandbox profile; other host paths may be inaccessible.",
      "HOME and TMPDIR refer to private temporary storage, not the operator's home. The shell receives only system PATH, LANG, and private HOME/TMPDIR; host environment variables and credentials are not inherited. Do not assume USER is set.",
      "Network access is denied. This backend has no Linux PID namespace or private procfs view. Detached descendants may survive cancellation while remaining sandboxed.",
      visibility_warning()
    ]
  end

  def visibility(:native, _),
    do: ["The native workspace sandbox is unavailable on this platform; execution fails closed."]

  def visibility(_, _) do
    [
      "Trusted local execution uses the user's filesystem and network permissions without an OS sandbox. Shell execution removes the common provider-token variables; other inherited environment and accessible files may remain available."
    ]
  end

  @doc "Shared terminal/model description of requested shell policy and visibility."
  def describe(mode, platform \\ :os.type()) do
    Enum.join(
      [
        "Shell policy requested: #{mode}.",
        "Requested policy is not proof of activation; inspect each command result."
      ] ++ visibility(mode, platform),
      "\n"
    )
  end

  defp visibility_warning do
    "A path lookup failure describes this sandbox's view, not host absence. Report 'not visible or inaccessible in this sandbox' unless separate host-side evidence establishes absence. Do not silently switch to trusted mode, expand roots, or clone a replacement."
  end

  def profile do
    case :os.type() do
      {:unix, :linux} -> "linux-workspace-v1"
      {:unix, :darwin} -> "macos-workspace-v1"
      _ -> nil
    end
  end

  defp ensure_available do
    if native_platform?(),
      do: :ok,
      else: {:error, "native sandbox backend is unavailable on this platform"}
  end

  defp native_platform? do
    architecture = :erlang.system_info(:system_architecture) |> List.to_string()

    :os.type() in [{:unix, :linux}, {:unix, :darwin}] and
      (String.starts_with?(architecture, "x86_64-") or
         String.starts_with?(architecture, "aarch64-") or
         String.starts_with?(architecture, "arm64-"))
  end

  defp validate_workspace(cwd) do
    with true <- cwd != "/" || {:error, "sandbox workspace cannot be the filesystem root"},
         :ok <- reject_overlaps(cwd, system_paths()),
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

  defp system_paths do
    if :os.type() == {:unix, :darwin} do
      @system_paths ++
        [
          "/sbin",
          "/System",
          "/Library",
          "/Applications",
          "/opt",
          "/private/etc",
          "/private/var/db",
          "/private/var/root"
        ]
    else
      @system_paths
    end
  end

  defp canonical_homes do
    homes = Enum.uniq(Enum.filter([System.user_home(), System.get_env("HOME")], &is_binary/1))

    Enum.reduce_while(homes, {:ok, []}, fn home, {:ok, acc} ->
      case Ipse.Workspace.canonical_path(home) do
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
      case Ipse.Workspace.canonical_path(path) do
        {:ok, protected} ->
          if (path == "/tmp" and cwd == protected) or
               (path != "/tmp" and overlap?(cwd, protected)),
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
