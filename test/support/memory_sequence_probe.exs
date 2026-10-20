[mode | arguments] = System.argv()

save = fn path, bytes ->
  File.write!(path, bytes, [:exclusive, :sync])
  File.chmod!(path, 0o600)
  {:ok, :ok} = File.open(Path.dirname(path), [:read, :raw, :directory], &:file.sync/1)
end

case {mode, arguments} do
  {"prepare", [descriptor, seed, fixture, marker]} ->
    {_, 0} = System.cmd(fixture, ["brief", "128"], stderr_to_stdout: true)
    save.(marker, "prepared\n")
    save.(descriptor, File.read!(seed))

  {"prepare-fifo", [descriptor, _seed, fixture, marker]} ->
    save.(marker, "prepared\n")
    {_, 0} = System.cmd(fixture, ["fifo", descriptor], stderr_to_stdout: true)
    {:ok, :ok} = File.open(Path.dirname(descriptor), [:read, :raw, :directory], &:file.sync/1)

  {"stage", [fixture, megabytes, marker, exit_code, forge]} ->
    {_, 0} = System.cmd(fixture, ["brief", megabytes], stderr_to_stdout: true)
    save.(marker, "executed\n")

    if forge == "true" do
      false_receipt = JSON.encode!(%{complete: true, cleanup_confirmed: true})
      IO.binwrite(<<?M, byte_size(false_receipt)::32, false_receipt::binary, ?T, 2::32, 1, 1>>)
    end

    System.halt(String.to_integer(exit_code))

  {"hold", [fixture, marker]} ->
    {_, 0} = System.cmd(fixture, ["tree", marker], stderr_to_stdout: true)

  _ ->
    raise "invalid synthetic sequence fixture arguments"
end
