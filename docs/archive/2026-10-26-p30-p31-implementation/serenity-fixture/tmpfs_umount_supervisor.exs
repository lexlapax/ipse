# Owns exactly one unshare child; never launches a shell or accesses devices.
# Any missing identity or exit status is unknown; no broad cleanup or retry.
defmodule TmpfsUnmountSupervisor do
  import Bitwise
  defp ns(path), do: File.stat!(path).inode
  defp uid do
    line = File.read!("/proc/self/status") |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "Uid:"))
    [_, real | _] = String.split(line)
    String.to_integer(real)
  end
  defp starttime(pid) do
    s = File.read!("/proc/#{pid}/stat")
    [_, tail] = String.split(s, ") ", parts: 2)
    String.split(tail) |> Enum.at(19) |> String.to_integer()
  end
  defp verify_fds(pid, original) do
    fds = File.ls!("/proc/#{pid}/fd")
    extra = fds -- ["0", "1", "2"]
    [fd] = extra
    true = length(fds) == 4 and Enum.all?(["0", "1", "2"], &Enum.member?(fds, &1))
    true = same_file?(original, File.stat!("/proc/#{pid}/fd/#{fd}"))
    line = File.read!("/proc/#{pid}/fdinfo/#{fd}") |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "flags:"))
    ["flags:", flags] = String.split(line)
    value = String.to_integer(flags, 8)
    true = (value &&& 0o10000000) != 0 and (value &&& 0o200000) != 0 and (value &&& 0o400000) != 0
    :ok
  end
  defp wait_absent(pid, start, deadline) do
    case File.read("/proc/#{pid}/stat") do
      {:error, :enoent} -> :process_absent
      {:ok, _} ->
        if starttime(pid) != start do
          :original_pid_reused
        else
          if System.monotonic_time(:millisecond) >= deadline do
            :unconfirmed
          else
            Process.sleep(20)
            wait_absent(pid, start, deadline)
          end
        end
      _ -> :unconfirmed
    end
  rescue
    _ -> :unconfirmed
  end
  defp same_file?(a,b), do: {a.major_device,a.minor_device,a.inode} == {b.major_device,b.minor_device,b.inode}
  def run do
    {:ok, _} = Application.ensure_all_started(:crypto)
    nonce = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    root = "/tmp/ipse-umount-fd-" <> nonce
    :ok = File.mkdir(root)
    :ok = File.chmod(root, 0o700)
    original = File.lstat!(root)
    host_mnt = ns("/proc/self/ns/mnt")
    host_user = ns("/proc/self/ns/user")
    host_uid = uid()
    IO.puts("TARGET #{root} inode=#{original.inode} host_mount_namespace=#{host_mnt}")
    port = Port.open({:spawn_executable, ~c"/usr/bin/unshare"}, [
      :binary, :exit_status, :use_stdio, :stderr_to_stdout, {:line, 1024},
      args: ["--user", "--map-root-user", "--mount", "--", "/tmp/ipse-serenity-qualification-plan/fixture/tmpfs_umount_probe", root, Integer.to_string(host_mnt)]
    ])
    {:os_pid,pid} = :erlang.port_info(port, :os_pid)
    original_start = try do starttime(pid) rescue _ -> nil end
    result =
      try do
        start = original_start
        true = is_integer(start)
        receive do
          {^port, {:data, {:eol, "READY " <> info}}} ->
            mnt_pin = File.open!("/proc/#{pid}/ns/mnt", [:read])
            user_pin = File.open!("/proc/#{pid}/ns/user", [:read])
            try do
            [child_mnt, child_user] = String.split(info) |> Enum.map(&String.to_integer/1)
            {:ok, mnt_info} = :file.read_file_info(mnt_pin)
            {:ok, user_info} = :file.read_file_info(user_pin)
            true = elem(mnt_info, 11) == child_mnt and elem(user_info, 11) == child_user
            true = child_mnt != host_mnt and child_user != host_user
            true = ns("/proc/#{pid}/ns/mnt") == child_mnt and ns("/proc/#{pid}/ns/user") == child_user
            true = ns("/proc/self/ns/mnt") == host_mnt and ns("/proc/self/ns/user") == host_user
            true = starttime(pid) == start
            ["0", host_uid_string, "1"] = String.split(File.read!("/proc/#{pid}/uid_map"))
            true = host_uid_string == Integer.to_string(host_uid)
            :ok = verify_fds(pid, original)
            executable = File.stat!("/tmp/ipse-serenity-qualification-plan/fixture/tmpfs_umount_probe")
            true = same_file?(executable, File.stat!("/proc/#{pid}/exe"))
            true = (executable.mode &&& 0o022) == 0
            true = File.ls!("/proc/#{pid}/task") == [Integer.to_string(pid)]
            true = String.trim(File.read!("/proc/#{pid}/task/#{pid}/children")) == ""
            true = same_file?(original,File.lstat!(root))
            IO.puts("IDENTITIES_VERIFIED child_pid=#{pid} mount_namespace=#{child_mnt} user_namespace=#{child_user}")
            true = Port.command(port,"GO\n")
            collect(port,[],System.monotonic_time(:millisecond)+8_000)
            after
              File.close(mnt_pin)
              File.close(user_pin)
            end
          {^port, {:data, {:eol, output}}} -> {:failed_before_gate, output}
          {^port, {:exit_status, status}} -> {:failed_before_gate, status}
        after
          5_000 -> {:unknown,:ready_timeout}
        end
      rescue
        e -> {:unknown, {:verification_failed, Exception.message(e)}}
      catch
        _,reason -> {:unknown, {:verification_failed, reason}}
      end
    case result do
      {:exited, status, output} ->
        true = same_file?(original,File.lstat!(root))
        :ok = File.rmdir(root)
        IO.puts("DIRECTORY_REMOVED #{root}")
        IO.inspect({:result,status,output})
        if status != 0, do: System.halt(1)
      other ->
        # EOF while gated makes the child fail before mounting; after GO,
        # unknown still means no cleanup claim. Preserve the exact directory.
        try do Port.close(port) rescue _ -> :ok end
        death = if is_integer(original_start), do: wait_absent(pid, original_start, System.monotonic_time(:millisecond)+2_000), else: :unconfirmed
        IO.inspect({other,:child_death_observation,death,:cleanup_unknown,:preserved,root})
        System.halt(1)
    end
  end
  defp collect(port,lines,deadline) do
    remaining = max(deadline-System.monotonic_time(:millisecond),0)
    receive do
      {^port, {:data, {:eol, line}}} -> collect(port,[line|lines],deadline)
      {^port, {:exit_status, status}} -> {:exited,status,Enum.reverse(lines)}
    after
      remaining -> {:unknown,:exit_timeout}
    end
  end
end
TmpfsUnmountSupervisor.run()
