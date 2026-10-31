defmodule Ipse.Extension.ConsentManagementReadTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.Consent
  alias Ipse.JSON

  @moduletag :management_snapshot_read

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-management-snapshot-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    root = Path.join(parent, "control")
    project = JSON.sha256("synthetic management snapshot")

    policy = %{
      "version" => 1,
      "project" => project,
      "artifact_sha256" => JSON.sha256("artifact"),
      "source_sha256" => JSON.sha256("sources"),
      "operations" => ["knowledge.capture"],
      "settings" => %{},
      "limits" => Map.new(Consent.resources(), &{&1, 5}),
      "period_ms" => 1000,
      "expires_at_ms" => 10_000,
      "headless" => false
    }

    assert {:ok, _} = Consent.replace(root, project, 0, policy, 1)

    %{
      parent: parent,
      root: root,
      project: project,
      policy: policy,
      fingerprint: Consent.management_sha256(project, 1, policy),
      control_file: Path.join([root, project, "control.json"])
    }
  end

  test "expired capture remains ineligible while its exact management snapshot retains the native lock",
       c do
    assert System.system_time(:millisecond) > c.policy["expires_at_ms"]

    assert {:error, :consent_read_refused} =
             Consent.with_existing_policy(
               c.root,
               c.project,
               1,
               JSON.digest([c.policy]),
               System.system_time(:millisecond),
               fn _ -> flunk("expired policy authorized consumer reading") end
             )

    before = File.read!(c.control_file)
    parent = self()

    task =
      Task.async(fn ->
        Consent.with_existing_management_snapshot(
          c.root,
          c.project,
          1,
          c.fingerprint,
          fn snapshot ->
            send(parent, {:snapshot_locked, self(), snapshot})
            receive do: (:return_snapshot -> {:ok, snapshot})
          end
        )
      end)

    assert_receive {:snapshot_locked, callback, snapshot}, 5000
    assert snapshot == %{"epoch" => 1, "policy" => c.policy}
    assert {:error, _} = Consent.revoke(c.root, c.project, 1)
    assert File.read!(c.control_file) == before
    send(callback, :return_snapshot)
    assert {:ok, ^snapshot} = Task.await(task, 5000)
    assert File.read!(c.control_file) == before
    assert {:ok, %{"epoch" => 2}} = Consent.revoke(c.root, c.project, 1)
  end

  test "revoked snapshot can be inspected but stale and substituted management pins cannot enter",
       c do
    assert {:ok, %{"epoch" => 2}} = Consent.revoke(c.root, c.project, 1)
    before = File.read!(c.control_file)
    revoked = Consent.management_sha256(c.project, 2, nil)

    assert {:ok, %{"epoch" => 2, "policy" => nil}} =
             Consent.with_existing_management_snapshot(c.root, c.project, 2, revoked, &{:ok, &1})

    for {epoch, fingerprint} <- [
          {1, c.fingerprint},
          {2, c.fingerprint},
          {2.0, revoked},
          {0, revoked},
          {2, JSON.sha256("different")}
        ] do
      assert {:error, :consent_read_refused} =
               Consent.with_existing_management_snapshot(
                 c.root,
                 c.project,
                 epoch,
                 fingerprint,
                 fn _ ->
                   flunk("wrong management pin entered callback")
                 end
               )
    end

    assert File.read!(c.control_file) == before
  end

  test "existing-only management inspection leaves missing and pending state unchanged", c do
    missing = Path.join(c.parent, "missing")

    assert {:error, :consent_read_refused} =
             Consent.with_existing_management_snapshot(
               missing,
               c.project,
               1,
               c.fingerprint,
               fn _ ->
                 flunk("missing control entered callback")
               end
             )

    refute File.exists?(missing)
    pending = Path.join([c.root, c.project, ".pending-" <> Ipse.Usage.id()])
    File.write!(pending, "preserve synthetic pending bytes")
    File.chmod!(pending, 0o600)
    before = File.read!(c.control_file)

    assert {:ok, :inspected} =
             Consent.with_existing_management_snapshot(
               c.root,
               c.project,
               1,
               c.fingerprint,
               fn _ ->
                 {:ok, :inspected}
               end
             )

    assert File.read!(pending) == "preserve synthetic pending bytes"
    assert File.read!(c.control_file) == before

    assert {:ok, %{"sequence" => 0, "operations" => %{}, "compacted" => %{}}} =
             Consent.existing_snapshot(c.root, c.project)
  end

  test "helper loss with a new owner cannot publish the old callback snapshot", c do
    parent = self()

    task =
      Task.async(fn ->
        Consent.with_existing_management_snapshot(
          c.root,
          c.project,
          1,
          c.fingerprint,
          fn snapshot ->
            cap = Process.get({Consent, :lock_held})
            {:os_pid, native} = Port.info(cap.port, :os_pid)
            send(parent, {:snapshot_native, self(), native})
            receive do: (:return_snapshot -> {:ok, snapshot})
          end
        )
      end)

    assert_receive {:snapshot_native, callback, native}, 5000
    assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(native)])
    assert {:ok, %{"epoch" => 2}} = Consent.revoke(c.root, c.project, 1)
    send(callback, :return_snapshot)
    assert {:unknown, _} = Task.await(task, 5000)
    assert {:ok, %{"epoch" => 2, "policy" => nil}} = Consent.existing_snapshot(c.root, c.project)
  end

  test "uncertain callbacks stay unknown and nested control mutation is refused", c do
    before = File.read!(c.control_file)
    unknown = {:unknown, :synthetic_callback_unconfirmed}

    assert ^unknown =
             Consent.with_existing_management_snapshot(
               c.root,
               c.project,
               1,
               c.fingerprint,
               fn _ ->
                 unknown
               end
             )

    assert ^unknown =
             Consent.with_existing_policy(
               c.root,
               c.project,
               1,
               JSON.digest([c.policy]),
               1,
               fn _ ->
                 unknown
               end
             )

    assert {:error, :consent_unavailable} =
             Consent.with_existing_management_snapshot(
               c.root,
               c.project,
               1,
               c.fingerprint,
               fn _ ->
                 Consent.revoke(c.root, c.project, 1)
               end
             )

    assert File.read!(c.control_file) == before
  end
end
