defmodule Ipse.CLI.ManagementFullFactsTest do
  use ExUnit.Case, async: false
  alias Ipse.{JSON, Usage}
  @moduletag :native_sandbox
  @moduletag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux native candidate")

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-management-facts-wrapper-" <> Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    driver = Path.join(root, "driver")

    assert {"", 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", driver],
               stderr_to_stdout: true
             )

    %{root: root, driver: driver}
  end

  @tag :management_facts_positive
  test "actual retained signed target renders complete exact management facts without granting input",
       c do
    {output, status} = run(c, "large")
    assert status == 0, output
    output = String.replace(output, "\r\n", "\n")

    assert [_, display, json, _challenge, facts_sha, display_sha, key] =
             Regex.run(
               ~r/(Retained management target at [0-9]+: signed deadline elapsed\. Original source availability and current-use eligibility are not checked\.\nReview the complete proposed facts below\. This confirmation applies only to this exact review\.\n(\{.*?\})\nType forget ([0-9a-f]{16}) to confirm, or anything else to cancel\.\n> )\nMANAGEMENT_FULL_FACTS_DISPLAY_CLOSED ([0-9a-f]{64}) ([0-9a-f]{64}) (note\.[0-9a-f]{64})/s,
               output
             )

    assert {:ok, facts} = JSON.decode_unique(json)
    assert JSON.digest([facts]) == facts_sha
    assert JSON.sha256(display) == display_sha
    assert facts["target"]["key"] == key
    assert facts["target"]["value"]["text"] == String.duplicate("\\\"", 200)
    assert facts["metadata"]["valid_until_ms"] < System.system_time(:millisecond)
    assert facts["context"]["management_epoch"] == 1
    assert facts["target"]["revision"] == 1
    assert facts["target"]["value"]["evidence"]["sources"] != []
  end

  @tag :management_facts_stale
  test "changed management epoch refuses before native protected display", c do
    {output, status} = run(c, "stale")
    assert status == 0, output
    assert output =~ "MANAGEMENT_STALE_EPOCH_REFUSED_BEFORE_DISPLAY"
    refute output =~ "Review the complete proposed facts"
  end

  @tag :management_lifecycle_partial_tail
  @tag timeout: 120_000
  test "operation inspection does not confirm a lifecycle journal with an incomplete tail", c do
    {output, status} = run(c, "cli-success", ["--management-review"])
    assert status == 0, output
    assert output =~ "MANAGEMENT_PUBLIC_FORGET_SETTLED"
  end

  @tag :management_session_retention
  @tag timeout: 120_000
  test "public session retention reviews and removes the selected stored literal", c do
    {output, status} = run(c, "cli-session", ["--management-review"])
    assert status == 0, output
    assert output =~ "MANAGEMENT_PUBLIC_SESSION_RETENTION_SETTLED"
    assert output =~ "Removed the reviewed stored note for session-only retention."
  end

  @tag :management_session_retention
  @tag timeout: 120_000
  test "cancelled public session retention leaves the selected root unchanged", c do
    {output, status} = run(c, "cli-session-cancel", ["--management-review-cancel"])
    assert status == 0, output
    assert output =~ "MANAGEMENT_SESSION_CANCELLED"
  end

  @tag :management_public_retention
  @tag timeout: 120_000
  test "public persistent retention choices settle the reviewed policy", c do
    for policy <- ~w(pin automatic duration) do
      {output, status} = run(c, "cli-retention-" <> policy, ["--management-review"])
      assert status == 0, output
      assert output =~ "PUBLIC_RETENTION_SETTLED " <> policy
      assert output =~ "Saved the exact reviewed retention choice"
    end
  end

  @tag :management_public_retention
  @tag timeout: 120_000
  test "cancelled public persistent retention leaves the selected root unchanged", c do
    {output, status} = run(c, "cli-retention-cancel", ["--management-review-cancel"])
    assert status == 0, output
    assert output =~ "PUBLIC_RETENTION_CANCELLED"
  end

  @tag :management_public_retention
  @tag timeout: 120_000
  test "public retention reports unconfirmed after expiry at the staged root switch", c do
    {output, status} = run(c, "cli-retention-expiry", ["--management-review"])
    assert status == 0, output
    assert output =~ "No successful retention change is confirmed"
    assert output =~ "PUBLIC_RETENTION_EXPIRY_UNCONFIRMED"
  end

  @tag :management_public_retention
  @tag timeout: 120_000
  test "public retention reports unconfirmed after management writer loss before switch", c do
    {output, status} = run(c, "cli-retention-writer-loss", ["--management-review"])
    assert status == 0, output
    assert output =~ "No successful retention change is confirmed"
    assert output =~ "PUBLIC_RETENTION_WRITER_LOSS_UNCONFIRMED"
  end

  @tag :management_retention_review
  @tag timeout: 120_000
  test "native retention review binds each live signed policy without publishing", c do
    for mode <- ~w(retention-review retention-review-ordinary retention-review-duration) do
      {output, status} = run(c, mode, ["--management-review"])
      assert status == 0, output
      assert output =~ "MANAGEMENT_RETENTION_REVIEW_RESULT " <> mode
    end
  end

  @tag :management_retention_effect
  @tag timeout: 120_000
  test "private native retention effect settles under the reviewed journal owner", c do
    for mode <- ~w(retention-effect retention-effect-ordinary retention-effect-duration) do
      {output, status} = run(c, mode, ["--management-review"])
      assert status == 0, output
      assert output =~ "MANAGEMENT_RETENTION_EFFECT_SETTLED"
    end
  end

  @tag :management_retention_effect
  @tag timeout: 120_000
  test "retention expiry after staging leaves the selected root and an unknown result", c do
    {output, status} = run(c, "retention-effect-expiry", ["--management-review"])
    assert status == 0, output
    assert output =~ "MANAGEMENT_RETENTION_EFFECT_EXPIRED_UNKNOWN"
  end

  @tag :management_retention_effect
  @tag timeout: 120_000
  test "new shorter retention expiry after staging leaves the selected root and an unknown result",
       c do
    {output, status} = run(c, "retention-effect-new-expiry", ["--management-review"])
    assert status == 0, output
    assert output =~ "MANAGEMENT_RETENTION_EFFECT_EXPIRED_UNKNOWN"
  end

  @tag :management_retention_effect
  @tag timeout: 120_000
  test "retention writer loss before switch leaves the selected root and an unknown result", c do
    {output, status} = run(c, "retention-effect-writer-loss", ["--management-review"])
    assert status == 0, output
    assert output =~ "MANAGEMENT_RETENTION_WRITER_LOSS_UNKNOWN"
  end

  @tag :management_retention_race
  @tag timeout: 120_000
  test "retention review does not publish across an epoch or competing root change", c do
    for mode <- ~w(retention-effect-epoch-race retention-effect-root-race) do
      {output, status} = run(c, mode, ["--management-review-race"])
      assert status == 0, output
      assert output =~ "MANAGEMENT_RETENTION_RACE_NOT_SETTLED " <> mode
    end
  end

  @tag :management_retention_switch_hook
  @tag skip: System.get_env("IPSE_TEST_RETENTION_SWITCH") != "1"
  @tag timeout: 120_000
  test "writer loss after the retention root rename or sync leaves an unknown result", c do
    for mode <- ~w(retention-effect-writer-after-rename retention-effect-writer-after-sync) do
      {output, status} = run(c, mode, ["--management-review"])
      assert status == 0, output
      assert output =~ "MANAGEMENT_RETENTION_WRITER_LOSS_UNKNOWN " <> mode
    end
  end

  @tag :management_retention_review
  @tag timeout: 120_000
  test "native retention review refuses cancellation, expired and future targets", c do
    for {mode, driver} <- [
          {"retention-review-cancel", "--management-review-cancel"},
          {"retention-review-expired", "--management-review"},
          {"retention-review-future", "--management-review"},
          {"retention-review-expire-after-input", "--management-review"}
        ] do
      {output, status} = run(c, mode, [driver])
      assert status == 0, output
      assert output =~ "MANAGEMENT_RETENTION_REVIEW_RESULT " <> mode

      if mode in ~w(retention-review-expired retention-review-future),
        do: refute(output =~ "Type pin ")
    end
  end

  test "retention review binds command, deadline and complete facts" do
    now = System.system_time(:millisecond)

    body = %{
      "kind" => "managed_literal_retention",
      "policy" => %{"kind" => "duration", "duration_ms" => 86_400_000},
      "metadata" => %{"first_admitted_ms" => now, "valid_until_ms" => now + 10_000},
      "old_deadline_ms" => now + 10_000
    }

    facts = Map.put(body, "action_sha256", JSON.digest([body]))
    assert Ipse.Session.ManagedLifecycle.retention_review?("duration", facts, now)
    refute Ipse.Session.ManagedLifecycle.retention_review?("pin", facts, now)
    refute Ipse.Session.ManagedLifecycle.retention_review?("duration", facts, now + 10_000)
    refute Ipse.Session.ManagedLifecycle.retention_review?("duration", facts, now - 1)

    refute Ipse.Session.ManagedLifecycle.retention_review?(
             "duration",
             Map.put(facts, "old_deadline_ms", nil),
             now
           )

    refute Ipse.Session.ManagedLifecycle.retention_review?(
             "duration",
             put_in(facts, ["policy", "duration_ms"], 1),
             now
           )
  end

  defp run(c, mode, driver_args \\ []) do
    home = Path.join(c.root, "case-" <> mode)
    File.mkdir!(home)

    paths =
      :code.get_path()
      |> Enum.reject(&(&1 == ~c"."))
      |> Enum.flat_map(&["-pa", List.to_string(&1)])

    System.cmd(
      c.driver,
      driver_args ++
        [System.find_executable("elixir"), "--erl", "+S 2:2"] ++
        paths ++ ["test/support/management_full_facts.exs", home, mode],
      stderr_to_stdout: true
    )
  end
end
