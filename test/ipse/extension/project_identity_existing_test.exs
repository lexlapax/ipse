defmodule Ipse.Extension.ProjectIdentityExistingTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.ProjectIdentity, as: Identity

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-existing-identity-" <> Ipse.Usage.id())
    home = Path.join(root, "home")
    primary = Path.join(root, "primary")
    linked = Path.join(root, "linked")
    File.mkdir_p!(home)
    File.chmod!(home, 0o700)
    File.mkdir_p!(Path.join(primary, ".git/worktrees/linked"))
    File.mkdir!(linked)
    admin = Path.join(primary, ".git/worktrees/linked")
    File.write!(Path.join(linked, ".git"), "gitdir: #{admin}\n")
    File.write!(Path.join(admin, "commondir"), "../..\n")
    File.write!(Path.join(admin, "gitdir"), Path.join(linked, ".git") <> "\n")
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, home: home, primary: primary, linked: linked}
  end

  defp inventory(path) do
    case File.lstat(path) do
      {:ok, %{type: :directory, mode: mode, inode: inode}} ->
        {:directory, mode, inode,
         path |> File.ls!() |> Enum.sort() |> Enum.map(&{&1, inventory(Path.join(path, &1))})}

      {:ok, %{type: :regular, mode: mode, inode: inode}} ->
        {:file, mode, inode, File.read!(path)}

      {:ok, %{type: type}} ->
        type

      {:error, :enoent} ->
        :absent
    end
  end

  test "empty ordinary home and unadmitted linked/folder probes create nothing", c do
    before = inventory(c.home)
    assert {:ok, nil} = Identity.existing(c.home, c.primary)
    assert {:ok, nil} = Identity.existing(c.home, c.linked)
    assert inventory(c.home) == before
    File.chmod!(c.home, 0o755)
    before = inventory(c.home)
    assert {:ok, nil} = Identity.existing(c.home, c.primary)
    assert inventory(c.home) == before
    missing = Path.join(c.root, "absent-home")
    assert {:ok, nil} = Identity.existing(missing, c.primary)
    refute File.exists?(missing)
  end

  test "existing primary is unchanged and unadmitted linked worktree is never joined", c do
    assert {:ok, binding} = Identity.admit(c.home, c.primary, :repository)
    before = inventory(c.home)
    assert {:ok, ^binding} = Identity.existing(c.home, c.primary)
    assert {:ok, nil} = Identity.existing(c.home, c.linked)
    assert inventory(c.home) == before
  end

  test "admitted linked revalidation preserves exact native witnesses and cleans its transient capture",
       c do
    assert {:ok, _} = Identity.admit(c.home, c.primary, :repository)
    assert {:ok, binding} = Identity.resolve(c.home, c.linked)
    before = inventory(c.home)
    assert {:ok, ^binding} = Identity.existing(c.home, c.linked)
    assert inventory(c.home) == before
    refute File.exists?(Path.join(c.home, "project-identities/.metadata-active"))
    File.write!(Path.join(c.linked, ".git"), "gitdir: /unrelated\n")
    assert {:error, _} = Identity.existing(c.home, c.linked)
  end

  test "unsafe present state or missing retained lock refuses without repair", c do
    assert {:ok, _} = Identity.admit(c.home, c.primary, :folder)
    path = Path.join(c.home, "project-identities/index.json")
    bytes = File.read!(path)
    File.write!(path, "{}")
    before = inventory(c.home)
    assert {:error, _} = Identity.existing(c.home, c.primary)
    assert inventory(c.home) == before
    File.write!(path, bytes)
    File.chmod!(path, 0o644)
    before = inventory(c.home)
    assert {:error, _} = Identity.existing(c.home, c.primary)
    assert inventory(c.home) == before
    File.chmod!(path, 0o600)
    File.rm!(Path.join(c.home, "project-identities/.lock"))
    before = inventory(c.home)
    assert {:error, _} = Identity.existing(c.home, c.primary)
    assert inventory(c.home) == before
  end

  test "a checked candidate is published only after exact host authorization", c do
    assert {:ok, primary} = Identity.admit(c.home, c.primary, :repository)
    before = inventory(c.home)

    assert {:ok, nil} =
             Identity.join_existing(c.home, c.linked, fn candidate ->
               assert candidate["project_id"] == primary["project_id"]
               assert candidate["scope"] == "repository" and candidate["root"] == c.linked
               assert inventory(c.home) == before
               :deny
             end)

    assert inventory(c.home) == before

    assert {:ok, linked} =
             Identity.join_existing(c.home, c.linked, fn candidate ->
               assert candidate["project_id"] == primary["project_id"]
               assert inventory(c.home) == before
               :ok
             end)

    assert linked["project_id"] == primary["project_id"]
    assert {:ok, ^linked} = Identity.existing(c.home, c.linked)
  end

  test "existing-bound callback preserves pending data and refuses stale identity; ordinary recovery reclaims",
       c do
    assert {:ok, binding} = Identity.admit(c.home, c.primary, :repository)
    root = Path.join(c.home, "project-identities")
    pending = Path.join(root, ".pending-" <> Ipse.Usage.id())
    File.write!(pending, "retained pending data")
    File.chmod!(pending, 0o600)
    before = inventory(c.home)

    assert {:ok, ^binding} =
             Identity.with_existing_binding(c.home, c.primary, binding, &{:ok, &1})

    assert inventory(c.home) == before

    assert {:error, :stale_project_identity} =
             Identity.with_existing_binding(
               c.home,
               c.primary,
               Map.put(binding, "scope", "folder"),
               fn _ ->
                 flunk("forged binding")
               end
             )

    assert inventory(c.home) == before
    assert {:ok, ^binding} = Identity.with_binding(c.home, c.primary, binding, &{:ok, &1})
    refute File.exists?(pending)
  end

  test "an existing-bound advisory result cannot escape after native owner loss", c do
    assert {:ok, binding} = Identity.admit(c.home, c.primary, :repository)
    before = inventory(c.home)

    assert {:unknown, _} =
             Identity.with_existing_binding(c.home, c.primary, binding, fn _ ->
               controller = Process.get({Ipse.Runner.Transaction, :controller})
               ref = Process.monitor(controller)
               {:os_pid, pid} = :erlang.port_info(:sys.get_state(controller).port, :os_pid)
               assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(pid)])
               assert_receive {:DOWN, ^ref, :process, ^controller, _}, 5_000
               {:ok, :must_not_escape}
             end)

    assert inventory(c.home) == before
  end

  test "missing ancillary writer refuses every existing path unchanged; ordinary resolve recreates it",
       c do
    assert {:ok, binding} = Identity.admit(c.home, c.primary, :repository)
    writer = Path.join(c.home, "project-identities/.writer.lock")
    File.rm!(writer)
    before = inventory(c.home)
    assert {:error, _} = Identity.existing(c.home, c.primary)

    assert {:error, _} =
             Identity.with_existing_binding(c.home, c.primary, binding, fn _ ->
               flunk("missing writer")
             end)

    assert {:error, _} =
             Identity.join_existing(c.home, c.linked, fn _ -> flunk("missing writer") end)

    assert inventory(c.home) == before
    refute File.exists?(writer)
    assert {:ok, ^binding} = Identity.resolve(c.home, c.primary)
    assert File.read!(writer) == ""
    assert {:ok, ^binding} = Identity.existing(c.home, c.primary)
  end

  test "unsafe or replaced ancillary writer never yields advisory data", c do
    assert {:ok, binding} = Identity.admit(c.home, c.primary, :repository)
    writer = Path.join(c.home, "project-identities/.writer.lock")

    for unsafe <- [:mode, :nonempty, :hardlink, :symlink] do
      saved = writer <> ".saved"

      case unsafe do
        :mode ->
          File.chmod!(writer, 0o644)

        :nonempty ->
          File.write!(writer, "nonempty")

        :hardlink ->
          File.ln!(writer, saved)

        :symlink ->
          File.rename!(writer, saved)
          File.ln_s!(saved, writer)
      end

      before = inventory(c.home)
      assert {:error, _} = Identity.existing(c.home, c.primary)
      assert inventory(c.home) == before

      case unsafe do
        :mode ->
          File.chmod!(writer, 0o600)

        :nonempty ->
          File.write!(writer, "")

        :hardlink ->
          File.rm!(saved)

        :symlink ->
          File.rm!(writer)
          File.rename!(saved, writer)
      end
    end

    index = File.read!(Path.join(c.home, "project-identities/index.json"))

    result =
      Identity.with_existing_binding(c.home, c.primary, binding, fn _ ->
        File.rename!(writer, writer <> ".saved")
        File.write!(writer, "")
        File.chmod!(writer, 0o600)
        {:ok, :must_not_escape}
      end)

    assert elem(result, 0) in [:error, :unknown]
    assert File.read!(Path.join(c.home, "project-identities/index.json")) == index
  end

  test "ordinary roots and a foreign clone never call authorization or gain membership", c do
    assert {:ok, _} = Identity.admit(c.home, c.primary, :repository)
    folder = Path.join(c.root, "folder")
    clone = Path.join(c.root, "clone")
    File.mkdir!(folder)
    File.mkdir_p!(Path.join(clone, ".git"))
    before = inventory(c.home)

    for cwd <- [folder, clone] do
      assert {:ok, nil} =
               Identity.join_existing(c.home, cwd, fn _ -> flunk("not a candidate") end)

      assert inventory(c.home) == before
    end

    admin = Path.join(clone, ".git/worktrees/foreign")
    File.mkdir_p!(admin)
    File.write!(Path.join(c.linked, ".git"), "gitdir: #{admin}\n")

    assert {:ok, nil} =
             Identity.join_existing(c.home, c.linked, fn _ -> flunk("foreign project") end)

    assert inventory(c.home) == before
  end

  test "a poisoned reciprocal backlink refuses before authorization", c do
    assert {:ok, _} = Identity.admit(c.home, c.primary, :repository)
    before = inventory(c.home)
    path = Path.join(c.primary, ".git/worktrees/linked/gitdir")
    File.write!(path, Path.join(c.primary, ".git") <> "\n")

    assert {:error, _} =
             Identity.join_existing(c.home, c.linked, fn _ -> flunk("unsafe backlink") end)

    assert inventory(c.home) == before
  end

  test "native owner loss after authorization cannot publish a candidate", c do
    assert {:ok, _} = Identity.admit(c.home, c.primary, :repository)
    before = inventory(c.home)

    assert {:unknown, _} =
             Identity.join_existing(c.home, c.linked, fn _ ->
               controller = Process.get({Ipse.Runner.Transaction, :controller})
               ref = Process.monitor(controller)
               {:os_pid, pid} = :erlang.port_info(:sys.get_state(controller).port, :os_pid)
               assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(pid)])
               assert_receive {:DOWN, ^ref, :process, ^controller, _}, 5_000
               :ok
             end)

    assert inventory(c.home) == before
    assert {:ok, nil} = Identity.existing(c.home, c.linked)
  end

  test "caller death or scope cancellation while host authorization is paused cannot join", c do
    assert {:ok, _} = Identity.admit(c.home, c.primary, :repository)
    before = inventory(c.home)
    test = self()

    for mode <- [:owner_death, :cancel] do
      {:ok, scope} = Ipse.Session.Resources.start(self())

      caller =
        spawn(fn ->
          Ipse.Session.Resources.bind(scope)
          receive do: (:start -> :ok)

          Identity.join_existing(c.home, c.linked, fn _ ->
            send(
              test,
              {:authorization, self(), Process.get({Ipse.Runner.Transaction, :controller})}
            )

            receive do: (:continue -> :ok)
          end)
        end)

      assert :ok = Ipse.Session.Resources.attach(scope, caller)
      send(caller, :start)
      assert_receive {:authorization, effect, controller}, 5_000
      ref = Process.monitor(controller)

      if mode == :owner_death,
        do: Process.exit(caller, :kill),
        else: Ipse.Session.Resources.stop_async(scope)

      assert_receive {:DOWN, ^ref, :process, ^controller, _}, 5_000
      send(effect, :continue)
      assert inventory(c.home) == before
      assert {:ok, nil} = Identity.existing(c.home, c.linked)
    end
  end
end
