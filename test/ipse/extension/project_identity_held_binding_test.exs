defmodule Ipse.Extension.ProjectIdentityHeldBindingTest do
  use ExUnit.Case, async: false
  @moduletag :native_storage
  alias Ipse.Extension.ProjectIdentity

  test "only the exact same callback can reuse the retained native binding" do
    root = Path.join(System.tmp_dir!(), "ipse-held-binding-" <> Ipse.Usage.id())
    home = Path.join(root, "home")
    cwd = Path.join(root, "workspace")
    File.mkdir_p!(home)
    File.mkdir!(cwd)
    nested = Path.join(home, "retained-child")
    File.mkdir!(nested)
    File.chmod!(nested, 0o700)
    lock_path = Path.join(nested, ".lock")
    File.write!(lock_path, "")
    File.chmod!(lock_path, 0o600)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    assert {:ok, binding} = ProjectIdentity.admit(home, cwd, :folder)

    assert {:error, :project_identity_unavailable} =
             ProjectIdentity.with_held_binding(home, cwd, binding, fn _ ->
               flunk("unleased callback")
             end)

    assert {:ok, :reused} =
             ProjectIdentity.with_binding(home, cwd, binding, fn current ->
               assert current == binding
               parent_cap = Process.get({ProjectIdentity, :retained_binding}).context.lock
               assert {:ok, child_cap} = Ipse.Runner.Transaction.acquire(lock_path, cwd: cwd)

               try do
                 assert {:error, :invalid_transaction_capability} =
                          Ipse.Runner.Transaction.check(parent_cap)

                 assert :ok = Ipse.Runner.Transaction.check_retained(parent_cap)

                 assert {:error, :invalid_transaction_capability} =
                          Ipse.Runner.Transaction.check_retained(
                            Map.put(parent_cap, :generation, make_ref())
                          )

                 assert {:error, :invalid_transaction_capability} =
                          Ipse.Runner.Transaction.release(parent_cap)

                 ProjectIdentity.with_held_binding(home, cwd, binding, fn ^binding ->
                   {:ok, :reused}
                 end)
               after
                 assert :ok = Ipse.Runner.Transaction.release(child_cap)
               end
             end)

    assert {:ok, :reused} =
             ProjectIdentity.with_existing_binding(home, cwd, binding, fn _ ->
               ProjectIdentity.with_held_binding(home, cwd, binding, fn _ -> {:ok, :reused} end)
             end)

    assert {:error, :project_identity_unavailable} =
             ProjectIdentity.with_binding(home, cwd, binding, fn _ ->
               ProjectIdentity.with_held_binding(
                 home,
                 cwd,
                 Map.put(binding, "binding_sha256", Ipse.JSON.sha256("foreign")),
                 fn _ -> flunk("changed binding") end
               )
             end)
  end
end
