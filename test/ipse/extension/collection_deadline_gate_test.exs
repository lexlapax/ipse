defmodule Ipse.Extension.CollectionDeadlineGateTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.Collection

  @tag gate_compatibility: true
  @tag :native_storage
  test "strict deadline entry refuses before callback/staging while ordinary storage remains available" do
    root = Path.join(System.tmp_dir!(), "ipse-deadline-gate-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    root = Path.join(root, "collections")
    namespace = Ipse.JSON.sha256("synthetic no-deadline store")
    deadline = System.system_time(:millisecond) + 60_000
    observer = self()

    assert {:error, :collection_deadline_fence_unavailable} =
             Collection.with_publication_deadline(deadline, fn ->
               send(observer, :callback_ran)
             end)

    refute_receive :callback_ran, 20

    request = %{
      "op" => "commit",
      "expected_generation" => 0,
      "advance_floor" => false,
      "changes" => [
        %{"key" => "ordinary", "expected_revision" => 0, "value" => %{"text" => "synthetic"}}
      ]
    }

    assert {:error, :collection_deadline_fence_unavailable} =
             Collection.execute_profile_before(
               root,
               namespace,
               request,
               Ipse.Usage.id(),
               Collection.Profile.notes(),
               deadline
             )

    refute File.exists?(Path.join(root, namespace))

    assert {:ok, %{"generation" => 1}} =
             Collection.execute(root, namespace, request, Ipse.Usage.id())

    assert {:ok, %{"record" => %{"value" => %{"text" => "synthetic"}}}} =
             Collection.execute(
               root,
               namespace,
               %{"op" => "get", "key" => "ordinary"},
               Ipse.Usage.id()
             )
  end

  test "unconfigured persistent retention refuses before native review" do
    for policy <- [
          %{"kind" => "pin"},
          %{"kind" => "ordinary"},
          %{"kind" => "duration", "duration_ms" => 1000}
        ] do
      assert {:error, :knowledge_management_refused} =
               Ipse.CLI.Knowledge.Management.retain(
                 %{},
                 "/unused",
                 "note." <> String.duplicate("0", 64),
                 policy
               )
    end

    assert Ipse.CLI.Errors.format(:collection_deadline_fence_unavailable) =~ "--yes cannot bypass"
  end

  @tag gate_cli: true
  test "unconfigured retention CLI reports no confirmed change" do
    root = Path.join(System.tmp_dir!(), "ipse-retention-gate-cli-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    home = Path.join(root, "home")
    File.mkdir!(home)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)

    output =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert Ipse.CLI.Knowledge.run_target(
                 "retention",
                 "note." <> String.duplicate("0", 64),
                 [policy: "pin"],
                 home,
                 root
               ) == 1
      end)

    assert output =~ "No successful retention change is confirmed"
    assert output =~ "knowledge_management_refused"
    refute output =~ "Saved the exact reviewed retention"
    refute File.exists?(Path.join(home, "knowledge-management"))
  end

  @tag reviewed_forget_gate: true
  test "unconfigured forget and session-only retention refuse without storage" do
    root = Path.join(System.tmp_dir!(), "ipse-forget-gate-cli-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    home = Path.join(root, "home")
    File.mkdir!(home)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)

    for {command, options} <- [{"forget", []}, {"retention", [policy: "session"]}] do
      output =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          assert Ipse.CLI.Knowledge.run_target(
                   command,
                   "note." <> String.duplicate("0", 64),
                   options,
                   home,
                   root
                 ) == 1
        end)

      if command == "forget" do
        assert output =~ "No successful forget is confirmed"
        assert output =~ "knowledge_management_refused"
      else
        assert output =~ "No successful retention change is confirmed"
        assert output =~ "knowledge_management_refused"
      end
    end

    refute File.exists?(Path.join(home, "knowledge-management"))
  end
end
