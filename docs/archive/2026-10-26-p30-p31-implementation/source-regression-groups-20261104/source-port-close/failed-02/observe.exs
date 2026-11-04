base = __DIR__
:ok = Application.load(:ipse)
app = Path.expand("../ipse-p30-pending-current-use-20261104-01/execution-01/lib/ipse", base)
true = Application.app_dir(:ipse) == app
helper = Path.join(app, "priv/ipse-runner")
helper_sha = Base.encode16(:crypto.hash(:sha256, File.read!(helper)), case: :lower)
true = helper_sha == "ac424d10e2ce6809cedcb157acd70092b00ca68aa7a48201a6007ac5dccbf33b"
helper_stat = File.stat!(helper)
Code.require_file("test/support/native_pipe_scope.exs", File.cwd!())
false = Enum.any?(Application.started_applications(), &(elem(&1, 0) == :ipse))
owned = Path.join(base, "owned-locks")
File.mkdir!(owned)
File.chmod!(owned, 0o700)

observations =
  for index <- 1..64 do
    directory = Path.join(owned, Integer.to_string(index))
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)
    lock = Path.join(directory, String.pad_leading(Integer.to_string(index, 16), 32, "0") <> ".lock")
    File.write!(lock, "", [:exclusive, :sync])
    File.chmod!(lock, 0o600)
    {:ok, port} = Ipse.Runner.share_source_lock(lock)
    {:os_pid, pid} = Port.info(port, :os_pid)
    executable = "/proc/#{pid}/exe"
    {:ok, ^helper} = File.read_link(executable)
    executable_stat = File.stat!(executable)
    true = {executable_stat.major_device, executable_stat.inode} ==
             {helper_stat.major_device, helper_stat.inode}
    before_close = System.monotonic_time(:microsecond)
    true = Port.close(port)
    close_returned = System.monotonic_time(:microsecond)
    immediate = File.read_link(executable)
    immediate_at = System.monotonic_time(:microsecond)
    immediate_state = case immediate do
      {:ok, ^helper} -> "same_helper_executable_still_present"
      {:error, :enoent} -> "executable_missing_exit_not_yet_confirmed"
      {:error, _} -> "unknown_executable_observation"
    end
    :ok = Ipse.Test.NativePipeScope.await_native_exit(pid)
    confirmed = System.monotonic_time(:microsecond)
    %{index: index, native_pid: pid, before_executable_identity: "exact_private_helper",
      port_close_return: true, immediate_state: immediate_state,
      close_duration_us: close_returned - before_close,
      observation_after_return_us: immediate_at - close_returned,
      exit_confirmation_after_return_us: confirmed - close_returned,
      native_exit_confirmed: true}
  end

false = Enum.any?(Application.started_applications(), &(elem(&1, 0) == :ipse))
receipt = %{version: 1, batch_size: 64, helper_sha256: helper_sha,
  immediate_same_helper_present: Enum.count(observations, &(&1.immediate_state == "same_helper_executable_still_present")),
  immediate_missing: Enum.count(observations, &(&1.immediate_state == "executable_missing_exit_not_yet_confirmed")),
  immediate_unknown: Enum.count(observations, &(&1.immediate_state == "unknown_executable_observation")),
  confirmed_exits: Enum.count(observations, & &1.native_exit_confirmed),
  application_started: false, input_tty_consent_or_model: false,
  scope: "port_close_vs_actual_native_exit_premise_only_not_publication_guard_qualification",
  observations: observations}
File.write!(Path.join(base, "observations.json"), Jason.encode!(receipt) <> "\n", [:exclusive, :sync])
File.chmod!(Path.join(base, "observations.json"), 0o600)
IO.puts(Jason.encode!(Map.drop(receipt, [:observations])))
