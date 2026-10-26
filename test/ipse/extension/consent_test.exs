defmodule Ipse.Extension.ConsentTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Consent, as: C

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-consent-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    project = Ipse.JSON.sha256("admitted project")
    root = Path.join(parent, "control")
    limits = C.zero() |> Map.merge(%{"operations" => 3, "model_calls" => 2, "input_bytes" => 128})

    p = %{
      "version" => 1,
      "project" => project,
      "artifact_sha256" => Ipse.JSON.sha256("artifact"),
      "source_sha256" => Ipse.JSON.sha256("source"),
      "operations" => ["knowledge.capture"],
      "settings" => %{"storage" => "selected project only"},
      "limits" => limits,
      "period_ms" => 1_000,
      "expires_at_ms" => 10_000,
      "headless" => true
    }

    %{parent: parent, root: root, project: project, policy: p}
  end

  defp grant(c), do: C.replace(c.root, c.project, 0, c.policy, 1)

  defp request(c, changes \\ %{}) do
    %{
      "id" => Ipse.Usage.id(),
      "operation" => "knowledge.capture",
      "artifact_sha256" => c.policy["artifact_sha256"],
      "source_sha256" => c.policy["source_sha256"],
      "policy_sha256" => Ipse.JSON.digest([c.policy]),
      "request_sha256" => Ipse.JSON.sha256("request"),
      "source_generation" => 1,
      "reserved" =>
        C.zero() |> Map.merge(%{"operations" => 1, "model_calls" => 1, "input_bytes" => 64}),
      "headless" => true
    }
    |> Map.merge(changes)
  end

  test "only closed finite policies can be persisted by the reviewing host", c do
    assert C.valid_policy?(c.policy)

    for p <- [
          Map.put(c.policy, "unknown", true),
          put_in(c.policy, ["limits", "operations"], 0),
          put_in(c.policy, ["limits", "model_calls"], 1.0),
          %{c.policy | "operations" => ["shell", "shell"]}
        ] do
      refute C.valid_policy?(p)
      assert {:error, :invalid_consent} = C.replace(c.root, c.project, 0, p, 1)
    end

    assert {:error, :invalid_consent} = C.replace(c.root, c.project, 0, c.policy, 10_000)
    assert {:ok, %{"epoch" => 1}} = grant(c)
    assert {:error, :consent_conflict} = grant(c)
    assert {:ok, state} = C.snapshot(c.root, c.project)
    assert state["policy"] == c.policy
    file = Path.join([c.root, c.project, "control.json"])
    assert Bitwise.band(File.stat!(file).mode, 0o777) == 0o600
  end

  test "no policy, wrong artifact, source, operation, headless or expired policy admits work",
       c do
    assert {:error, :consent_denied} = C.reserve(c.root, c.project, request(c), 1)
    assert {:ok, _} = grant(c)

    for changes <- [
          %{"artifact_sha256" => Ipse.JSON.sha256("substitution")},
          %{"source_sha256" => Ipse.JSON.sha256("changed")},
          %{"operation" => "shell"},
          %{"policy_sha256" => Ipse.JSON.sha256("stale")}
        ] do
      assert {:error, :consent_denied} = C.reserve(c.root, c.project, request(c, changes), 1)
    end

    assert {:error, :consent_denied} = C.reserve(c.root, c.project, request(c), 10_000)
    p = %{c.policy | "headless" => false}
    assert {:ok, _} = C.replace(c.root, c.project, 1, p, 1)
    changed = %{c | policy: p}
    assert {:error, :consent_denied} = C.reserve(c.root, c.project, request(changed), 1)
    assert {:ok, _} = C.reserve(c.root, c.project, request(changed, %{"headless" => false}), 1)
  end

  test "nested policy and receipt values cannot publish an unreadable control ledger", c do
    nested = fn depth -> Enum.reduce(1..depth, %{}, fn _, value -> %{"nested" => value} end) end
    p = %{c.policy | "settings" => nested.(12)}
    assert C.valid_policy?(p)
    assert {:ok, _} = C.replace(c.root, c.project, 0, p, 1)
    assert {:ok, %{"policy" => ^p}} = C.snapshot(c.root, c.project)

    for depth <- 13..17 do
      bad = %{c.policy | "settings" => nested.(depth)}
      refute C.valid_policy?(bad)
      assert {:error, :invalid_consent} = C.replace(c.root, c.project, 1, bad, 1)
    end

    c = %{c | policy: p}
    r = request(c)
    assert {:ok, t} = C.reserve(c.root, c.project, r, 1)

    assert {:ok, _} =
             C.publish(c.root, c.project, t, 1, fn -> {:ok, r["reserved"], nested.(12)} end)

    assert {:ok, s} = C.snapshot(c.root, c.project)
    assert s["operations"][r["id"]]["receipt"] == nested.(12)
    r = request(c)
    assert {:ok, t} = C.reserve(c.root, c.project, r, 1)

    assert {:unknown, _} =
             C.publish(c.root, c.project, t, 1, fn -> {:ok, r["reserved"], nested.(13)} end)

    assert {:ok, s} = C.snapshot(c.root, c.project)
    assert s["operations"][r["id"]]["status"] == "publishing"
    assert {:ok, _} = C.revoke(c.root, c.project, 1)
  end

  test "reservations consume every finite dimension and duplicate IDs never dispatch twice", c do
    assert {:ok, _} = grant(c)
    r = request(c)
    assert {:ok, t} = C.reserve(c.root, c.project, r, 1)
    assert {:ok, %{"existing" => %{"status" => "reserved"}}} = C.reserve(c.root, c.project, r, 1)
    assert {:ok, ^t} = C.admit(c.root, c.project, t, 1)
    assert {:error, :consent_admission_refused} = C.admit(c.root, c.project, t, 1)
    assert {:ok, _} = C.reserve(c.root, c.project, request(c), 1)
    assert {:error, :consent_reservation_refused} = C.reserve(c.root, c.project, request(c), 1)
    assert {:ok, _} = C.settle(c.root, c.project, t, {:known, r["reserved"]})
    assert {:ok, %{"existing" => %{"status" => "settled"}}} = C.reserve(c.root, c.project, r, 1)
    assert {:error, :consent_settlement_refused} = C.settle(c.root, c.project, t, :unknown)
  end

  test "revocation is durable and refuses publication before executing its callback", c do
    assert {:ok, _} = grant(c)
    r = request(c)
    assert {:ok, t} = C.reserve(c.root, c.project, r, 1)
    assert {:ok, _} = C.admit(c.root, c.project, t, 1)
    assert {:ok, %{"epoch" => 2, "in_flight" => 1}} = C.revoke(c.root, c.project, 1)
    refute File.exists?(Path.join(c.parent, "effect"))

    assert {:error, :consent_publication_refused} =
             C.publish(c.root, c.project, t, 1, fn ->
               File.write!(Path.join(c.parent, "effect"), "unexpected")
               {:ok, r["reserved"], %{}}
             end)

    refute File.exists?(Path.join(c.parent, "effect"))
    assert {:ok, s} = C.snapshot(c.root, c.project)
    assert s["policy"] == nil
    assert s["operations"][r["id"]]["status"] == "admitted"
    assert {:ok, _} = C.settle(c.root, c.project, t, :unknown)
    assert {:ok, _} = C.replace(c.root, c.project, 2, c.policy, 1)

    assert {:error, :consent_publication_refused} =
             C.publish(c.root, c.project, t, 1, fn -> flunk("stale callback") end)
  end

  test "unknown effects retain liability across time periods and require explicit reconciliation",
       c do
    assert {:ok, _} = grant(c)
    r = request(c)
    assert {:ok, t} = C.reserve(c.root, c.project, r, 1)
    assert {:ok, _} = C.admit(c.root, c.project, t, 1)
    assert {:ok, _} = C.settle(c.root, c.project, t, :unknown)

    assert {:error, :consent_settlement_refused} =
             C.settle(c.root, c.project, t, {:known, C.zero()})

    assert {:ok, _} = C.reserve(c.root, c.project, request(c), 2_000)

    assert {:error, :consent_reservation_refused} =
             C.reserve(c.root, c.project, request(c), 2_000)

    assert {:ok, _} = C.settle(c.root, c.project, t, {:reconciled, r["reserved"]})
    assert {:ok, _} = C.reserve(c.root, c.project, request(c), 2_000)
  end

  test "unstarted cancellation releases only unadmitted work and settles exactly once", c do
    assert {:ok, _} = grant(c)
    assert {:ok, t} = C.reserve(c.root, c.project, request(c), 1)
    assert {:ok, _} = C.settle(c.root, c.project, t, :unstarted)
    assert {:error, :consent_settlement_refused} = C.settle(c.root, c.project, t, :unstarted)
    assert {:error, :consent_admission_refused} = C.admit(c.root, c.project, t, 1)
    assert {:ok, _} = C.reserve(c.root, c.project, request(c), 1)
  end

  test "successful publication runs under the control lock and closes its reservation", c do
    assert {:ok, _} = grant(c)
    r = request(c)
    assert {:ok, t} = C.reserve(c.root, c.project, r, 1)

    assert {:ok, %{"receipt" => %{"record" => "saved"}}} =
             C.publish(c.root, c.project, t, 1, fn ->
               assert {:error, :consent_unavailable} = C.revoke(c.root, c.project, 1)
               {:ok, r["reserved"], %{"record" => "saved"}}
             end)

    assert {:error, :consent_publication_refused} =
             C.publish(c.root, c.project, t, 1, fn -> flunk("replayed") end)

    assert {:ok, _} = C.revoke(c.root, c.project, 1)
  end

  test "forged tickets and measured overruns never become settled success", c do
    assert {:ok, _} = grant(c)
    r = request(c)
    assert {:ok, t} = C.reserve(c.root, c.project, r, 1)

    assert {:error, :consent_admission_refused} =
             C.admit(c.root, c.project, %{t | "sequence" => 2}, 1)

    for field <- ~w(sequence epoch) do
      forged = Map.update!(t, field, &(&1 * 1.0))
      assert {:error, :consent_admission_refused} = C.admit(c.root, c.project, forged, 1)
    end

    assert {:error, :consent_admission_refused} = C.admit(c.root, Ipse.JSON.sha256("other"), t, 1)
    assert {:ok, _} = C.admit(c.root, c.project, t, 1)
    over = %{r["reserved"] | "output_bytes" => 1}

    assert {:unknown, :consent_settlement_exceeds_reservation} =
             C.settle(c.root, c.project, t, {:known, over})

    assert {:ok, s} = C.snapshot(c.root, c.project)
    assert s["operations"][r["id"]]["status"] == "overrun"
    assert s["operations"][r["id"]]["actual"] == over

    assert {:error, :consent_reservation_refused} =
             C.reserve(c.root, c.project, request(c), 2_000)

    assert {:error, :consent_settlement_refused} =
             C.settle(c.root, c.project, t, {:reconciled, r["reserved"]})

    assert {:ok, %{"status" => "reconciled_overrun"}} =
             C.settle(c.root, c.project, t, {:reconciled, over})

    assert {:ok, _} = C.reserve(c.root, c.project, request(c), 2_000)
  end

  test "a callback exception or process loss cannot replay a possible publication", c do
    assert {:ok, _} = grant(c)
    r = request(c)
    assert {:ok, t} = C.reserve(c.root, c.project, r, 1)
    effect = Path.join(c.parent, "effect")

    assert {:unknown, :publication_unconfirmed} =
             C.publish(c.root, c.project, t, 1, fn ->
               File.write!(effect, "happened", [:sync])
               raise "lost receipt"
             end)

    assert File.read!(effect) == "happened"

    assert {:error, :consent_publication_refused} =
             C.publish(c.root, c.project, t, 1, fn -> flunk("replayed") end)

    assert {:ok, _} = C.settle(c.root, c.project, t, :unknown)

    r = request(c)
    assert {:ok, t} = C.reserve(c.root, c.project, r, 1)
    payload = Path.join(c.parent, "ticket.json")
    File.write!(payload, Jason.encode!(t))

    code = ~S'''
    {:ok, _} = Application.ensure_all_started(:ipse)
    [root, project, payload, effect] = System.argv()
    t = Jason.decode!(File.read!(payload))
    Ipse.Extension.Consent.publish(root, project, t, 1, fn ->
      File.write!(effect, "possible publication", [:sync])
      System.halt(73)
    end)
    '''

    {output, status} = separate_vm(code, [c.root, c.project, payload, effect])
    assert status == 73, output
    assert File.read!(effect) == "possible publication"
    assert {:ok, s} = await_snapshot(c, System.monotonic_time(:millisecond) + 5_000)
    assert s["operations"][r["id"]]["status"] == "publishing"

    assert {:error, :consent_publication_refused} =
             C.publish(c.root, c.project, t, 1, fn -> flunk("replayed after VM death") end)

    assert {:ok, _} = C.settle(c.root, c.project, t, :unknown)
  end

  test "measured overruns quarantine existing reservations and retain reconciled period usage",
       c do
    assert {:ok, _} = grant(c)
    r = request(c)
    assert {:ok, t} = C.reserve(c.root, c.project, r, 1)
    assert {:ok, other} = C.reserve(c.root, c.project, request(c), 1)
    assert {:ok, _} = C.admit(c.root, c.project, t, 1)
    actual = %{r["reserved"] | "model_calls" => 2}

    assert {:unknown, :consent_settlement_exceeds_reservation} =
             C.settle(c.root, c.project, t, {:known, actual})

    assert {:error, :consent_admission_refused} = C.admit(c.root, c.project, other, 1)

    assert {:error, :consent_publication_refused} =
             C.publish(c.root, c.project, other, 1, fn -> flunk("quarantined") end)

    assert {:ok, _} = C.settle(c.root, c.project, other, :unstarted)
    assert {:error, :consent_reservation_refused} = C.reserve(c.root, c.project, request(c), 1)
    assert {:ok, _} = C.settle(c.root, c.project, t, {:reconciled, actual})
    assert {:error, :consent_reservation_refused} = C.reserve(c.root, c.project, request(c), 1)
    assert {:ok, _} = C.reserve(c.root, c.project, request(c), 1_000)
  end

  test "a callback's error after possible storage mutation remains unknown", c do
    assert {:ok, _} = grant(c)
    assert {:ok, t} = C.reserve(c.root, c.project, request(c), 1)
    effect = Path.join(c.parent, "effect")

    assert {:unknown, :publication_unconfirmed} =
             C.publish(c.root, c.project, t, 1, fn ->
               File.write!(effect, "happened", [:sync])
               {:error, :receipt_failed}
             end)

    assert File.read!(effect) == "happened"

    assert {:error, :consent_publication_refused} =
             C.publish(c.root, c.project, t, 1, fn -> flunk("replayed") end)
  end

  test "independent VMs share one finite ceiling and retain lock inode identity", c do
    p = put_in(c.policy, ["limits", "model_calls"], 1)
    c = %{c | policy: p}
    assert {:ok, _} = grant(c)
    lock = Path.join([c.root, c.project, ".lock"])
    inode = File.stat!(lock).inode
    barrier = Path.join(c.parent, "release")

    code = ~S'''
    {:ok, _} = Application.ensure_all_started(:ipse)
    [root, project, payload, barrier, name] = System.argv()
    request = Jason.decode!(File.read!(payload))
    File.write!(barrier <> "." <> name, "ready")
    deadline = System.monotonic_time(:millisecond) + 15_000
    wait = fn wait ->
      unless File.exists?(barrier) do
        if System.monotonic_time(:millisecond) > deadline, do: raise("barrier timeout")
        Process.sleep(5)
        wait.(wait)
      end
    end
    wait.(wait)
    result = Ipse.Extension.Consent.reserve(root, project, request, 1)
    IO.puts(Jason.encode!(%{"ok" => match?({:ok, %{"sequence" => _}}, result)}))
    '''

    tasks =
      for name <- ~w(first second) do
        payload = Path.join(c.parent, name <> ".json")
        File.write!(payload, Jason.encode!(request(c)))

        task =
          Task.async(fn -> separate_vm(code, [c.root, c.project, payload, barrier, name]) end)

        await_file(barrier <> "." <> name, System.monotonic_time(:millisecond) + 20_000)
        task
      end

    try do
      File.write!(barrier, "release")

      results =
        Enum.map(tasks, fn task ->
          {output, status} = Task.await(task, 20_000)
          assert status == 0, output
          Jason.decode!(String.trim(output))
        end)

      assert Enum.count(results, & &1["ok"]) == 1
      assert {:ok, s} = C.snapshot(c.root, c.project)
      assert map_size(s["operations"]) == 1
      assert File.stat!(lock).inode == inode
    after
      File.write!(barrier, "release")
      Enum.each(tasks, &Task.shutdown(&1, 20_000))
    end
  end

  defp separate_vm(code, args) do
    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    System.cmd(
      System.find_executable("elixir"),
      ["--erl", "+S 2:2"] ++ paths ++ ["-e", code, "--"] ++ args,
      stderr_to_stdout: true,
      cd: Path.dirname(hd(args))
    )
  end

  defp await_file(path, deadline) do
    unless File.exists?(path) do
      assert System.monotonic_time(:millisecond) < deadline, "consent barrier timed out"
      Process.sleep(5)
      await_file(path, deadline)
    end
  end

  defp await_snapshot(c, deadline) do
    case C.snapshot(c.root, c.project) do
      {:ok, _} = ok ->
        ok

      _ ->
        assert System.monotonic_time(:millisecond) < deadline,
               "consent lock not released after VM exit"

        Process.sleep(5)
        await_snapshot(c, deadline)
    end
  end

  test "unsafe paths, symlinks, hard links and duplicate-key or torn ledgers fail closed", c do
    assert {:ok, _} = grant(c)
    file = Path.join([c.root, c.project, "control.json"])
    original = File.read!(file)

    for bytes <- ["{", "{\"version\":1,\"version\":1}", String.duplicate(" ", 8_388_609)] do
      File.write!(file, bytes)
      assert {:error, :consent_unavailable} = C.snapshot(c.root, c.project)
    end

    File.write!(file, original)
    File.chmod!(file, 0o644)
    assert {:error, :consent_unavailable} = C.snapshot(c.root, c.project)
    File.chmod!(file, 0o600)
    File.ln!(file, Path.join(c.parent, "hard-link"))
    assert {:error, :consent_unavailable} = C.snapshot(c.root, c.project)
    File.rm!(Path.join(c.parent, "hard-link"))
    File.rename!(file, file <> ".original")
    File.ln_s!(file <> ".original", file)
    assert {:error, :consent_unavailable} = C.snapshot(c.root, c.project)
    File.ln_s!(c.root, Path.join(c.parent, "alias"))
    assert {:error, :consent_unavailable} = C.snapshot(Path.join(c.parent, "alias"), c.project)
    File.chmod!(c.parent, 0o755)
    assert {:error, :consent_unavailable} = C.snapshot(c.root, c.project)
    assert {:error, :directory_sync_unavailable} = Ipse.Runner.sync_directory(c.parent)
  end
end
