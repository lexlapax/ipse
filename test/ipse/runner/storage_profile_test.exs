defmodule Ipse.Runner.StorageProfileTest do
  use ExUnit.Case, async: false
  alias Ipse.{JSON, Runner, Usage}
  alias Ipse.Extension.Collection
  alias Ipse.Runner.Transaction
  alias Ipse.Session.Resources

  @available_host :os.type() == {:unix, :linux} and
                    System.cmd("uname", ["-r"]) == {"7.2.11-arch1-1\n", 0}
  @explicit_btrfs System.get_env("IPSE_TEST_BTRFS_ROOT")
  @btrfs_root Path.expand(@explicit_btrfs || File.cwd!())
  @btrfs_available @available_host and
                     System.cmd("stat", ["-f", "-c", "%T", @btrfs_root]) == {"btrfs\n", 0}
  @moduletag skip: not @available_host

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-qualified-tmpfs-" <> Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    previous = System.get_env("IPSE_RUNNER_PATH")

    on_exit(fn ->
      if previous,
        do: System.put_env("IPSE_RUNNER_PATH", previous),
        else: System.delete_env("IPSE_RUNNER_PATH")

      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "the pinned production helper admits tmpfs quota and a protected publication without ambient bypass",
       c do
    # General shell helper selection must not widen protected storage admission.
    System.put_env("IPSE_RUNNER_PATH", Path.join(c.root, "absent-untrusted-helper"))
    assert {:ok, helper} = Runner.protected_helper(c.root)

    assert JSON.sha256(File.read!(helper)) ==
             JSON.sha256(File.read!(Application.app_dir(:ipse, "priv/ipse-runner")))

    assert :ok =
             Resources.file_effect(fn ->
               assert {:ok, cap} = Transaction.acquire(Path.join(c.root, ".lock"))
               assert :ok = Transaction.quota(cap, :flat, 65_536)
               assert :ok = Transaction.preflight(cap, [6144])

               assert {:error, :invalid_transaction_capability} =
                        Task.async(fn -> Transaction.check(cap) end) |> Task.await()

               name = ".pending-" <> Usage.id()
               assert :ok = Transaction.stage(cap, ".", [{name, :binary.copy(<<1, 2, 3>>, 2048)}])
               assert {:ok, %{allocated: allocated}} = Transaction.allocation(cap, :flat)
               assert allocated >= 6144 and allocated <= 16_384
               assert :ok = Transaction.switch(cap, name, "control.json")
               assert :ok = Transaction.release(cap)
               assert {:error, :invalid_transaction_capability} = Transaction.check(cap)
               :ok
             end)

    project = JSON.sha256("qualified tmpfs collection")
    operation = Usage.id()

    request = %{
      "op" => "commit",
      "expected_generation" => 0,
      "advance_floor" => true,
      "changes" => [
        %{
          "key" => "fixture",
          "expected_revision" => 0,
          "value" => %{"text" => "bounded native qualification"}
        }
      ]
    }

    assert {:ok, receipt} =
             Collection.execute(c.root <> "/collections", project, request, operation)

    assert receipt["generation"] == 1

    assert {:existing, %{"operation" => ^receipt}} =
             Collection.execute(c.root <> "/collections", project, request, operation)

    assert {:ok, %{"record" => %{"value" => %{"text" => "bounded native qualification"}}}} =
             Collection.execute(
               c.root <> "/collections",
               project,
               %{"op" => "get", "key" => "fixture"},
               Usage.id()
             )
  end

  @tag skip:
         (cond do
            not @available_host ->
              "requires exact qualified kernel 7.2.11-arch1-1"

            not @btrfs_available and is_nil(@explicit_btrfs) ->
              "requires a Btrfs checkout or explicit IPSE_TEST_BTRFS_ROOT"

            true ->
              false
          end)
  test "the exact new kernel still refuses declared Btrfs before protected publication" do
    assert {"btrfs\n", 0} = System.cmd("stat", ["-f", "-c", "%T", @btrfs_root])
    root = Path.join(@btrfs_root, ".ipse-unqualified-btrfs-" <> Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)

    assert :ok =
             Resources.file_effect(fn ->
               assert {:ok, cap} = Transaction.acquire(Path.join(root, ".lock"))

               assert {:error, :transaction_filesystem_unsupported} =
                        Transaction.quota(cap, :flat, 65_536)

               assert :ok = Transaction.release(cap)
               :ok
             end)

    project = JSON.sha256("unqualified Btrfs collection")

    request = %{
      "op" => "commit",
      "expected_generation" => 0,
      "advance_floor" => true,
      "changes" => [
        %{
          "key" => "fixture",
          "expected_revision" => 0,
          "value" => %{"text" => "must not publish"}
        }
      ]
    }

    assert {:error, :collection_filesystem_unsupported} =
             Collection.execute(root <> "/collections", project, request, Usage.id())

    refute File.exists?(Path.join([root, "collections", project, "root.json"]))
  end
end
