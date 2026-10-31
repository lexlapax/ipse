defmodule Ipse.Runner.ProtectedLeaseTest do
  use ExUnit.Case, async: false
  alias Ipse.Runner

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-protected-lease-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    helper = Path.join(root, "forged-helper")
    marker = Path.join(root, "override-executed")

    File.write!(
      helper,
      "#!/bin/sh\nprintf forged > '#{marker}'\nprintf '\\114\\000\\000\\000\\006locked'\nexec /bin/cat >/dev/null\n"
    )

    File.chmod!(helper, 0o700)
    previous = System.get_env("IPSE_RUNNER_PATH")
    System.put_env("IPSE_RUNNER_PATH", helper)

    on_exit(fn ->
      if previous,
        do: System.put_env("IPSE_RUNNER_PATH", previous),
        else: System.delete_env("IPSE_RUNNER_PATH")

      File.rm_rf!(root)
    end)

    %{root: root, marker: marker}
  end

  test "retained source leases ignore a live forged locked frame and use real exclusion", c do
    # The ordinary override really can emit a live L frame without a kernel lock.
    assert {:ok, forged} = Runner.lock(Path.join(c.root, "ordinary.lock"))
    assert File.exists?(c.marker)
    assert Port.info(forged) != nil
    Port.close(forged)
    File.rm!(c.marker)

    path = Path.join(c.root, "source.lock")
    assert {:ok, source} = Runner.lock_source(path)
    refute File.exists?(c.marker)
    assert {:error, _} = Runner.lock_source(path)
    assert :ok = Runner.unlock(source)
    assert {:ok, reopened} = Runner.lock_source(path)
    assert :ok = Runner.unlock(reopened)
    refute File.exists?(c.marker)
  end

  test "the live original Session owner lock is pinned as well", c do
    path = Path.join(c.root, "session.lock")
    assert {:ok, _port} = Ipse.Session.Lock.acquire(path)
    guard = Ipse.Session.Lock.current()
    refute File.exists?(c.marker)
    assert {:error, _} = Runner.protected_lock(path)
    assert :ok = Ipse.Session.Lock.release(guard)
    assert {:ok, reopened} = Runner.protected_lock(path)
    assert :ok = Runner.unlock(reopened)
    refute File.exists?(c.marker)
  end

  test "managed shell admission ignores an alternate helper", c do
    assert {:ok, %{exit_code: 0}} =
             Runner.run("printf admitted > shell-result", c.root,
               admit: fn start -> start.(System.system_time(:millisecond) + 2000) end
             )

    assert File.read!(Path.join(c.root, "shell-result")) == "admitted"
    refute File.exists?(c.marker)
  end
end
