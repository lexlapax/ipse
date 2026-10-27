defmodule Ipse.Extension.ConsentExistingTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Consent, as: C

  setup do
    home = Path.join(System.tmp_dir!(), "ipse-consent-existing-" <> Ipse.Usage.id())
    File.mkdir!(home)
    File.chmod!(home, 0o700)
    root = Path.join(home, "control")
    project = Ipse.JSON.sha256("existing project")
    now = System.system_time(:millisecond)

    policy = %{
      "version" => 1,
      "project" => project,
      "artifact_sha256" => Ipse.JSON.sha256("artifact"),
      "source_sha256" => Ipse.JSON.sha256("source"),
      "operations" => ["capture"],
      "settings" => %{},
      "limits" => Map.new(C.resources(), &{&1, 10}),
      "period_ms" => 1_000,
      "expires_at_ms" => now + 100_000,
      "headless" => true
    }

    on_exit(fn -> File.rm_rf!(home) end)
    %{home: home, root: root, project: project, policy: policy, now: now}
  end

  defp grant(c), do: C.replace(c.root, c.project, 0, c.policy, c.now)
  defp path(c), do: Path.join(c.root, c.project)

  defp pending(c) do
    path = Path.join(path(c), ".pending-" <> Ipse.Usage.id())
    File.write!(path, "untouched pending effect")
    File.chmod!(path, 0o600)
    path
  end

  test "absent state creates no root and cannot run an exact-policy callback", c do
    assert {:ok, nil} = C.existing_snapshot(c.root, c.project)
    refute File.exists?(c.root)

    assert {:error, :consent_read_refused} =
             C.with_existing_policy(
               c.root,
               c.project,
               0,
               Ipse.JSON.digest([c.policy]),
               c.now,
               fn _ ->
                 flunk("absence is not a policy witness")
               end
             )

    refute File.exists?(c.root)
  end

  test "valid and malformed existing reads preserve pending bytes; ordinary recovery still reclaims",
       c do
    assert {:ok, _} = grant(c)
    file = Path.join(path(c), "control.json")
    bytes = File.read!(file)
    pending = pending(c)
    assert {:ok, %{"policy" => policy}} = C.existing_snapshot(c.root, c.project)
    assert policy == c.policy

    assert {:ok, :reviewed} =
             C.with_existing_policy(
               c.root,
               c.project,
               1,
               Ipse.JSON.digest([c.policy]),
               c.now,
               fn _ ->
                 {:ok, :reviewed}
               end
             )

    assert File.read!(pending) == "untouched pending effect"
    assert File.read!(file) == bytes
    File.write!(file, "{}")
    assert {:error, _} = C.existing_snapshot(c.root, c.project)
    assert File.read!(file) == "{}"
    assert File.read!(pending) == "untouched pending effect"
    File.write!(file, bytes)
    assert {:ok, _} = C.snapshot(c.root, c.project)
    refute File.exists?(pending)
    assert File.read!(file) == bytes
  end

  test "missing retained lock and a changed control object refuse without repair", c do
    assert {:ok, _} = grant(c)
    file = Path.join(path(c), "control.json")
    bytes = File.read!(file)
    lock = Path.join(path(c), ".lock")

    assert {:error, _} =
             C.with_existing_policy(
               c.root,
               c.project,
               1,
               Ipse.JSON.digest([c.policy]),
               c.now,
               fn _ ->
                 File.rename!(file, file <> ".previous")
                 File.write!(file, bytes)
                 File.chmod!(file, 0o600)
                 {:ok, :not_a_current_read}
               end
             )

    File.rm!(file <> ".previous")
    File.rm!(lock)
    assert {:error, _} = C.existing_snapshot(c.root, c.project)
    refute File.exists?(lock)
    assert File.read!(file) == bytes
  end

  test "exact policy refuses changed pins, expiry, invalid callbacks and native owner loss", c do
    assert {:ok, _} = grant(c)
    sha = Ipse.JSON.digest([c.policy])

    for {epoch, hash, now} <- [
          {0, sha, c.now},
          {1, Ipse.JSON.sha256("wrong"), c.now},
          {1, sha, c.policy["expires_at_ms"]}
        ] do
      assert {:error, _} =
               C.with_existing_policy(c.root, c.project, epoch, hash, now, fn _ ->
                 flunk("stale policy")
               end)
    end

    assert {:error, :consent_read_refused} =
             C.with_existing_policy(c.root, c.project, 1, sha, c.now, fn _ -> :ok end)

    assert {:unknown, _} =
             C.with_existing_policy(c.root, c.project, 1, sha, c.now, fn _ ->
               controller = Process.get({Ipse.Runner.Transaction, :controller})
               ref = Process.monitor(controller)
               {:os_pid, pid} = :erlang.port_info(:sys.get_state(controller).port, :os_pid)
               assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(pid)])
               assert_receive {:DOWN, ^ref, :process, ^controller, _}, 5_000
               {:ok, :must_not_escape}
             end)
  end

  test "a valid but quarantined existing ledger cannot report a ready policy", c do
    assert {:ok, _} = grant(c)
    reserved = Map.put(C.zero(), "operations", 1)

    request = %{
      "id" => Ipse.Usage.id(),
      "operation" => "capture",
      "artifact_sha256" => c.policy["artifact_sha256"],
      "source_sha256" => c.policy["source_sha256"],
      "policy_sha256" => Ipse.JSON.digest([c.policy]),
      "request_sha256" => Ipse.JSON.sha256("request"),
      "source_generation" => 1,
      "reserved" => reserved,
      "headless" => true
    }

    assert {:ok, ticket} = C.reserve(c.root, c.project, request, c.now)
    assert {:ok, _} = C.admit(c.root, c.project, ticket, c.now)

    assert {:unknown, _} =
             C.settle(c.root, c.project, ticket, {:known, %{reserved | "operations" => 2}})

    assert {:ok, _} = C.existing_snapshot(c.root, c.project)

    assert {:error, :consent_read_refused} =
             C.with_existing_policy(
               c.root,
               c.project,
               1,
               Ipse.JSON.digest([c.policy]),
               c.now,
               fn _ ->
                 flunk("quarantined policy")
               end
             )
  end

  test "missing ancillary writer refuses unchanged, while an explicit mutation recreates it", c do
    assert {:ok, _} = grant(c)
    writer = Path.join(path(c), ".writer.lock")
    bytes = File.read!(Path.join(path(c), "control.json"))
    File.rm!(writer)
    assert {:error, _} = C.existing_snapshot(c.root, c.project)

    assert {:error, _} =
             C.with_existing_policy(
               c.root,
               c.project,
               1,
               Ipse.JSON.digest([c.policy]),
               c.now,
               fn _ -> flunk("missing writer") end
             )

    refute File.exists?(writer)
    assert File.read!(Path.join(path(c), "control.json")) == bytes
    assert {:ok, _} = C.revoke(c.root, c.project, 1)
    assert File.read!(writer) == ""
    assert {:ok, %{"policy" => nil}} = C.existing_snapshot(c.root, c.project)
  end

  test "unsafe or replaced ancillary writer refuses existing policy data", c do
    assert {:ok, _} = grant(c)
    writer = Path.join(path(c), ".writer.lock")
    control = Path.join(path(c), "control.json")
    bytes = File.read!(control)

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

      assert {:error, _} = C.existing_snapshot(c.root, c.project)
      assert File.read!(control) == bytes

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

    result =
      C.with_existing_policy(c.root, c.project, 1, Ipse.JSON.digest([c.policy]), c.now, fn _ ->
        File.rename!(writer, writer <> ".saved")
        File.write!(writer, "")
        File.chmod!(writer, 0o600)
        {:ok, :must_not_escape}
      end)

    assert elem(result, 0) in [:error, :unknown]
    assert File.read!(control) == bytes
  end
end
