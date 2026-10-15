# Run from an extracted release: ./bin/ipse eval 'Code.require_file("verify-release.exs")'
Application.ensure_all_started(:ipse)

release_root = File.cwd!() |> Path.expand()
runtime_root = :code.root_dir() |> List.to_string() |> Path.expand()
app_root = Application.app_dir(:ipse) |> Path.expand()
true = runtime_root == release_root
true = String.starts_with?(app_root, release_root <> "/lib/")
true = File.regular?(Path.join(app_root, "priv/ipse-runner"))
System.delete_env("IPSE_RUNNER_PATH")

scratch =
  Path.join(
    System.tmp_dir!(),
    "ipse-release-check-#{Base.encode16(:crypto.strong_rand_bytes(8))}"
  )

File.mkdir_p!(scratch)

await_lock = fn await_lock, path, attempts ->
  case Ipse.Runner.lock(path) do
    {:ok, lock} ->
      {:ok, lock}

    {:error, _} when attempts > 0 ->
      Process.sleep(20)
      await_lock.(await_lock, path, attempts - 1)

    error ->
      error
  end
end

try do
  {:ok, result} =
    Ipse.Runner.run("(sleep 1; printf survived > timeout-marker) & printf ready; wait", scratch,
      timeout_ms: 200
    )

  true = result.timed_out
  true = result.output == "ready"
  Process.sleep(1_100)
  false = File.exists?(Path.join(scratch, "timeout-marker"))

  parent = self()

  owner =
    spawn(fn ->
      Ipse.Runner.run(
        "(sleep 1; printf survived > owner-marker) & printf ready; wait",
        scratch,
        emit: fn event -> send(parent, event) end
      )
    end)

  receive do
    {:tool_output, "ready"} -> :ok
  after
    5_000 -> raise "bundled helper did not start"
  end

  Process.exit(owner, :kill)
  Process.sleep(1_100)
  false = File.exists?(Path.join(scratch, "owner-marker"))

  path = Path.join(scratch, "session.lock")
  {:ok, lock} = Ipse.Runner.lock(path)
  inode = File.stat!(path).inode
  true = Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
  {:error, _} = Ipse.Runner.lock(path)
  :ok = Ipse.Runner.unlock(lock)
  {:ok, next} = await_lock.(await_lock, path, 100)
  true = File.stat!(path).inode == inode
  :ok = Ipse.Runner.unlock(next)

  lock_owner =
    spawn(fn ->
      {:ok, _} = await_lock.(await_lock, path, 100)
      send(parent, :locked)
      Process.sleep(:infinity)
    end)

  receive do
    :locked -> :ok
  after
    5_000 -> raise "bundled lock owner did not start"
  end

  {:error, _} = Ipse.Runner.lock(path)
  Process.exit(lock_owner, :kill)
  {:ok, final} = await_lock.(await_lock, path, 100)
  true = File.stat!(path).inode == inode
  :ok = Ipse.Runner.unlock(final)

  if :os.type() == {:unix, :darwin} do
    workspace = Path.join(scratch, "native workspace")
    File.mkdir!(workspace)
    secret = Path.join(scratch, "outside-fixture-key")
    File.write!(secret, "fixture-private-value")
    quote_shell = fn text -> "'" <> String.replace(text, "'", "'\\''") <> "'" end

    {:ok, native} =
      Ipse.Runner.run(
        "set -e; printf allowed > native-marker; if cat #{quote_shell.(secret)}; then exit 11; fi; if printf changed > #{quote_shell.(secret)}; then exit 12; fi; printf confined",
        workspace,
        sandbox: :native
      )

    0 = native.exit_code
    false = native.timed_out
    true = String.contains?(native.output, "confined")
    false = String.contains?(native.output, "fixture-private-value")
    "allowed" = File.read!(Path.join(workspace, "native-marker"))
    "fixture-private-value" = File.read!(secret)

    {:ok, timed} =
      Ipse.Runner.run(
        "(printf native-ready; sleep 1.7; printf survived > native-timeout-marker) & wait",
        workspace,
        sandbox: :native,
        timeout_ms: 1_000
      )

    true = timed.timed_out
    "native-ready" = timed.output
    Process.sleep(1_850)
    false = File.exists?(Path.join(workspace, "native-timeout-marker"))

    IO.puts(
      "Bundled macOS native workspace writes, outside-file denial, and ordinary timeout cleanup passed."
    )
  end

  IO.puts("Bundled runtime/helper, timeout cleanup, owner-death cleanup, and locks passed.")
after
  File.rm_rf!(scratch)
end
