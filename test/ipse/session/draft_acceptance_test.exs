defmodule Ipse.Session.DraftAcceptanceTest do
  use ExUnit.Case, async: true
  alias Ipse.Session.DraftAcceptance
  alias Ipse.{JSON, Usage}

  test "receipt binds exact proposal, rendered display, channel, revision and native observation" do
    draft = %{id: Usage.id(), revision: 1, proposal: "Keep the original requirement."}
    assert {:ok, render} = DraftAcceptance.render(draft, Usage.id())
    text = "accept " <> render["code"]

    observation = %{
      "version" => 2,
      "event_id" => Usage.id(),
      "display_limit" => 16_777_216,
      "input_limit" => 1_048_576,
      "display_sha256" => JSON.sha256(render["display"]),
      "text_sha256" => JSON.sha256(text)
    }

    assert {:ok, receipt} = DraftAcceptance.receipt(draft, render, text, observation)
    assert DraftAcceptance.valid_receipt?(draft, receipt)
    refute DraftAcceptance.valid_receipt?(%{draft | revision: 2}, receipt)
    refute DraftAcceptance.valid_receipt?(%{draft | proposal: "changed"}, receipt)

    assert {:error, :invalid_draft_acceptance} =
             DraftAcceptance.receipt(draft, render, "yes", observation)

    assert {:error, :invalid_draft_acceptance} =
             DraftAcceptance.receipt(
               draft,
               render,
               text,
               Map.put(observation, "display_sha256", String.duplicate("0", 64))
             )

    event = %{"type" => "draft_accepted", "version" => 2, "receipt" => receipt}
    assert :ok = DraftAcceptance.validate_observation_uniqueness([event])

    assert {:error, :duplicate_operator_observation} =
             DraftAcceptance.validate_observation_uniqueness([event, event])

    input = %{"type" => "input_received", "observation" => observation}

    assert {:error, :duplicate_operator_observation} =
             DraftAcceptance.validate_observation_uniqueness([event, input])
  end

  test "synthetic PTY display and input produce an actual bound acceptance witness" do
    root = Path.join(System.tmp_dir!(), "ipse-draft-witness-" <> Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    driver = Path.join(root, "pty")

    assert {_, 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 "test/support/operator_cli_pty.rs",
                 "-o",
                 driver
               ],
               stderr_to_stdout: true
             )

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    {output, status} =
      System.cmd(
        driver,
        ["--draft", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++ [Path.expand("test/support/draft_operator_pty.exs"), root],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "SYNTHETIC_DRAFT_OPERATOR_WITNESS_PASSED"
  end

  test "native enhance command retains exact input and rejects a stale ID before acceptance" do
    root = Path.join(System.tmp_dir!(), "ipse-draft-cli-" <> Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    driver = Path.join(root, "pty")

    assert {_, 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 "test/support/operator_cli_pty.rs",
                 "-o",
                 driver
               ],
               stderr_to_stdout: true
             )

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    {output, status} =
      System.cmd(
        driver,
        ["--draft-cli", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++ [Path.expand("test/support/draft_cli_pty.exs"), root],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "SYNTHETIC_DRAFT_CLI_PASSED"
  end

  test "synthetic native terminal binds every line in a multiline replacement" do
    root = Path.join(System.tmp_dir!(), "ipse-draft-multiline-" <> Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    driver = Path.join(root, "pty")

    assert {_, 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 "test/support/operator_cli_pty.rs",
                 "-o",
                 driver
               ],
               stderr_to_stdout: true
             )

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    {output, status} =
      System.cmd(
        driver,
        ["--draft-multi", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++ [Path.expand("test/support/draft_cli_pty.exs"), "multi", root],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "SYNTHETIC_DRAFT_CLI_PASSED"
  end

  test "synthetic native draft question binds answer provenance to accepted intent" do
    root = Path.join(System.tmp_dir!(), "ipse-draft-question-" <> Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    driver = Path.join(root, "pty")

    assert {_, 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 "test/support/operator_cli_pty.rs",
                 "-o",
                 driver
               ],
               stderr_to_stdout: true
             )

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    {output, status} =
      System.cmd(
        driver,
        ["--draft-question", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++ [Path.expand("test/support/draft_cli_pty.exs"), "question", root],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "SYNTHETIC_DRAFT_CLI_PASSED"
  end

  test "cancel clears draft entry and replacement, and abandons a rendered acceptance" do
    root = Path.join(System.tmp_dir!(), "ipse-enhance-cancel-" <> Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    driver = Path.join(root, "pty")

    assert {_, 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 "test/support/operator_cli_pty.rs",
                 "-o",
                 driver
               ],
               stderr_to_stdout: true
             )

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    {output, status} =
      System.cmd(
        driver,
        ["--enhance-cancel", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++ [Path.expand("test/support/draft_cli_pty.exs"), "cancel", root],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "SYNTHETIC_ENHANCE_CANCEL_PASSED"
  end
end
