[helper] = System.argv()

for {count, payload} <- [
      {5, "SYNTHETIC_ACCEPTED_LEASE_DISPLAY"},
      {6, "PRIVATE_TEXT_MUST_NOT_BE_DISPLAYED"}
    ] do
  port =
    Port.open({:spawn_executable, String.to_charlist(helper)}, [
      :binary,
      :exit_status,
      :nouse_stdio,
      :hide,
      args: ["--operator-input", "5000", "v8-synthetic-accepted-display"]
    ])

  {:os_pid, pid} = Port.info(port, :os_pid)
  {:ok, tty} = File.stat("/proc/#{pid}/fd/0")
  operation = :crypto.strong_rand_bytes(16)
  controls = :crypto.strong_rand_bytes(136)

  entries =
    Enum.map(1..count, fn _ -> <<0, :crypto.strong_rand_bytes(84)::binary>> end)
    |> IO.iodata_to_binary()

  expiry = System.system_time(:millisecond) + 4_000

  body =
    <<operation::binary, count, controls::binary, entries::binary, tty.major_device::64,
      tty.inode::64, tty.minor_device::64, expiry::64, byte_size(payload)::32, payload::binary>>

  true = Port.command(port, <<?I, byte_size(body)::32, body::binary>>)

  receive do
    {^port, {:exit_status, status}} when status != 0 -> :ok
    other -> raise "unexpected reply: #{inspect(other)}"
  after
    10_000 -> raise "probe did not refuse"
  end
end

IO.puts("SIX_LEASE_INVALID_REFUSED")

for slots <- [[0, 0, 1, 2], [0, 0, 1, 2, 1], [0, 0, 1, 2] ++ List.duplicate(0, 129)] do
  port =
    Port.open({:spawn_executable, String.to_charlist(helper)}, [
      :binary,
      :exit_status,
      :nouse_stdio,
      :hide,
      args: ["--operator-input", "5000", "v10-synthetic-source-group-display"]
    ])

  {:os_pid, pid} = Port.info(port, :os_pid)
  {:ok, tty} = File.stat("/proc/#{pid}/fd/0")
  operation = :crypto.strong_rand_bytes(16)
  controls = :crypto.strong_rand_bytes(136)

  entries =
    Enum.map(slots, fn slot -> <<slot, :crypto.strong_rand_bytes(84)::binary>> end)
    |> IO.iodata_to_binary()

  payload = "PRIVATE_TEXT_MUST_NOT_BE_DISPLAYED"
  expiry = System.system_time(:millisecond) + 4_000

  body =
    <<operation::binary, length(slots), controls::binary, entries::binary, tty.major_device::64,
      tty.inode::64, tty.minor_device::64, expiry::64, byte_size(payload)::32, payload::binary>>

  true = Port.command(port, <<?I, byte_size(body)::32, body::binary>>)

  receive do
    {^port, {:exit_status, status}} when status != 0 -> :ok
    other -> raise "unexpected grouped-source reply: #{inspect(other)}"
  after
    10_000 -> raise "grouped-source probe did not refuse"
  end
end

IO.puts("GROUP_LEASE_INVALID_REFUSED")

port =
  Port.open({:spawn_executable, String.to_charlist(helper)}, [
    :binary,
    :exit_status,
    :nouse_stdio,
    :hide,
    args: ["--operator-input", "5000", "v12-synthetic-source-group-notice-input"]
  ])

native_clock =
  receive do
    {^port, {:data, <<?R, 8::32, clock::64>>}} -> clock
    other -> raise "unexpected synthetic review greeting: #{inspect(other)}"
  after
    5_000 -> raise "synthetic review greeting timed out"
  end

{:os_pid, pid} = Port.info(port, :os_pid)
{:ok, tty} = File.stat("/proc/#{pid}/fd/0")
operation = :crypto.strong_rand_bytes(16)
controls = :crypto.strong_rand_bytes(136)

entries =
  for(slot <- [0, 0, 1, 2, 0], into: <<>>, do: <<slot, :crypto.strong_rand_bytes(84)::binary>>)

expiry = System.system_time(:millisecond) + 4_000
payload = "PRIVATE_TEXT_MUST_NOT_BE_DISPLAYED"

body =
  <<operation::binary, 5, controls::binary, entries::binary, tty.major_device::64, tty.inode::64,
    tty.minor_device::64, expiry::64, native_clock + 4_000::64, expiry::64,
    native_clock + 4_000::64, byte_size(payload)::32, payload::binary>>

true = Port.command(port, <<?I, byte_size(body)::32, body::binary>>)

receive do
  {^port, {:exit_status, status}} when status != 0 -> :ok
  other -> raise "unexpected synthetic review reply: #{inspect(other)}"
after
  10_000 -> raise "synthetic review probe did not refuse"
end

IO.puts("SYNTHETIC_REVIEW_CONTENT_REFUSED")
