# Runs on a synthetic PTY. Each line is typed while no child reader is waiting,
# so an eager VM standard-input reader would take it before the child reads.
{:ok, _} = Application.ensure_all_started(:ipse)
[root, mode] = System.argv()

if mode == "claim", do: :ok = Ipse.Runner.TerminalInput.claim()

for n <- 1..3 do
  out = Path.join(root, "line-#{n}")
  File.write!(out, "none")
  IO.write("IPSE_FIXTURE_INPUT_#{n}> ")
  # The PTY driver types the answer as soon as the marker appears.
  Process.sleep(500)

  port =
    Port.open({:spawn_executable, "/bin/sh"}, [
      :nouse_stdio,
      :exit_status,
      args: ["-c", ~S(if read -r line; then printf '%s' "$line" > "$1"; fi), "sh", out]
    ])

  {:os_pid, pid} = Port.info(port, :os_pid)

  receive do
    {^port, {:exit_status, _}} -> :ok
  after
    2_000 ->
      System.cmd("kill", [Integer.to_string(pid)])
      receive do: ({^port, {:exit_status, _}} -> :ok)
  end

  IO.puts("TERMINAL_CHILD_#{n}=" <> File.read!(out))
end

IO.puts("TERMINAL_INPUT_CLAIM_DONE")
