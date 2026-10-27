# Harmless cgroup lifetime observation; no host devices, project mounts,
# network access, image pulls or filesystem faults. The container is created
# solely by this script and cleanup uses its returned exact identity.
defmodule IpseCgroupProbe do
  @image "sha256:757718cecb34fbe2c56e22b5f6299a45f149c7ce1c9b85def543a340bacdf7af"
  @docker "/usr/bin/docker"

  defp docker(args) do
    case System.cmd(@docker, args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, status} -> {:error, {status, String.slice(output, 0, 1000)}}
    end
  end

  defp event(fd) do
    case :file.position(fd, :bof) do
      {:ok, 0} -> read_event(fd)
      other -> {:error, other}
    end
  end

  defp read_event(fd) do
    case :file.read(fd, 1024) do
      {:ok, bytes} ->
        lines = String.split(bytes, "\n", trim: true)

        case Enum.filter(lines, &String.starts_with?(&1, "populated ")) do
          ["populated 1"] -> {:ok, 1}
          ["populated 0"] -> {:ok, 0}
          _ -> {:error, :malformed_events}
        end

      other ->
        {:error, other}
    end
  end

  defp watcher(dir, inode, parent, tag) do
    spawn_monitor(fn ->
      with {:ok, %File.Stat{inode: ^inode}} <- File.stat(dir),
           {:ok, fd} <-
             :file.open(String.to_charlist(Path.join(dir, "cgroup.events")), [
               :read,
               :binary,
               :raw
             ]),
           {:ok, %File.Stat{inode: ^inode}} <- File.stat(dir),
           {:ok, 1} <- event(fd) do
        send(parent, {tag, :watching})
        result = watch_loop(fd, System.monotonic_time(:millisecond) + 10_000)
        :file.close(fd)
        send(parent, {tag, :observed, result})
      else
        other -> send(parent, {tag, :failed, other})
      end
    end)
  end

  defp watch_loop(fd, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :watch_timeout}
    else
      case event(fd) do
        {:ok, 0} ->
          {:ok, 0}

        {:ok, 1} ->
          Process.sleep(1)
          watch_loop(fd, deadline)

        other ->
          other
      end
    end
  end

  defp cgroup(pid, id) do
    with {number, ""} when number > 0 <- Integer.parse(pid),
         {:ok, contents} <- File.read("/proc/#{number}/cgroup"),
         ["0::" <> group] <- String.split(contents, "\n", trim: true),
         true <- String.starts_with?(group, "/") and not String.contains?(group, ".."),
         true <- String.contains?(group, id),
         dir = Path.join("/sys/fs/cgroup", String.trim_leading(group, "/")),
         {:ok, stat} <- File.stat(dir),
         {:ok, fd} <-
           :file.open(String.to_charlist(Path.join(dir, "cgroup.events")), [:read, :binary, :raw]) do
      {:ok, dir, stat.inode, fd}
    else
      _ -> {:error, :cgroup_identity_unconfirmed}
    end
  end

  def run do
    nonce = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    name = "ipse-cgroup-observation-" <> nonce

    case docker(["inspect", name]) do
      {:ok, _} -> raise "fixture name collision"
      {:error, _} -> :ok
    end

    uid = System.get_env("IPSE_CGROUP_PROBE_UID") || raise "UID missing"
    gid = System.get_env("IPSE_CGROUP_PROBE_GID") || raise "GID missing"
    true = Regex.match?(~r/\A[0-9]{1,6}\z/, uid) and Regex.match?(~r/\A[0-9]{1,6}\z/, gid)

    {:ok, id} =
      docker([
        "run",
        "--detach",
        "--name",
        name,
        "--pull",
        "never",
        "--network",
        "none",
        "--read-only",
        "--cap-drop",
        "ALL",
        "--security-opt",
        "no-new-privileges:true",
        "--pids-limit",
        "16",
        "--memory",
        "64m",
        "--user",
        uid <> ":" <> gid,
        @image,
        "/usr/bin/sh",
        "-c",
        "/usr/bin/setsid /usr/bin/sleep 30 & wait"
      ])

    true = Regex.match?(~r/\A[0-9a-f]{64}\z/, id)

    try do
      {:ok, actual} = docker(["inspect", "--format", "{{.Id}} {{.Name}} {{.Image}}", id])
      true = actual == id <> " /" <> name <> " " <> @image
      {:ok, pid} = docker(["inspect", "--format", "{{.State.Pid}}", id])
      {:ok, dir, inode, fd} = cgroup(pid, id)

      try do
        {:ok, before} = event(fd)
        {:ok, top} = docker(["top", id, "-eo", "pid,pgid,sid,args"])
        true = before == 1
        tag = make_ref()
        {_, watch_ref} = watcher(dir, inode, self(), tag)

        receive do
          {^tag, :watching} -> :ok
          {^tag, :failed, reason} -> raise "watcher refused: #{inspect(reason)}"
          {:DOWN, ^watch_ref, :process, _, reason} -> raise "watcher died: #{inspect(reason)}"
        after
          5_000 -> raise "watcher startup timed out"
        end

        {:ok, _} = docker(["kill", id])
        {:ok, exit_code} = docker(["wait", id])
        after_event = event(fd)

        concurrent =
          receive do
            {^tag, :observed, value} -> value
            {:DOWN, ^watch_ref, :process, _, reason} -> {:error, {:watcher_down, reason}}
          after
            5_000 -> {:error, :watcher_timeout}
          end

        {:ok, state} = docker(["inspect", "--format", "{{.State.Running}}", id])

        IO.inspect(
          %{
            container_id: id,
            cgroup: dir,
            cgroup_inode: inode,
            before: before,
            after_event: after_event,
            concurrent: concurrent,
            running: state,
            exit_code: exit_code,
            top: top
          },
          limit: :infinity
        )

        if concurrent != {:ok, 0} or state != "false", do: raise("cgroup cleanup unconfirmed")
      after
        :file.close(fd)
      end
    after
      # Kill only if this exact returned ID still matches the expected image and
      # name; no wildcard/container-wide cleanup.
      case docker(["inspect", "--format", "{{.Id}} {{.Name}} {{.Image}}", id]) do
        {:ok, actual} ->
          if actual == id <> " /" <> name <> " " <> @image do
            _ = docker(["kill", id])

            case docker(["inspect", "--format", "{{.State.Running}}", id]) do
              {:ok, "false"} -> IO.inspect(docker(["rm", id]), label: "exact_container_removal")
              other -> IO.inspect(other, label: "manual_cleanup_required")
            end
          else
            IO.inspect(actual, label: "manual_cleanup_required")
          end

        other ->
          IO.inspect(other, label: "manual_cleanup_required")
      end
    end
  end
end

IpseCgroupProbe.run()
