defmodule Ipse.Session.InputTest do
  use ExUnit.Case, async: false
  alias Ipse.Session.Input

  test "origin receipts validate exact bytes, versions, uniqueness and session identity" do
    id = Ipse.Usage.id()
    turn = Ipse.Usage.id()
    e = Input.received(id, turn, "café", "expanded café", nil)
    assert :ok = Input.validate_events([e], id)
    header = %{"type" => "session", "metadata" => %{}}
    assert {:ok, []} = Ipse.Session.restore_context([header, e])

    for damaged <- [
          Map.put(e, "version", 1.0),
          Map.put(e, "text", "cafe"),
          Map.put(e, "origin", "interactive_operator"),
          Map.put(e, "observation", %{}),
          Map.put(e, "observation", "forged"),
          Map.put(e, "observation", [1]),
          Map.put(e, "effective_sha256", "forged"),
          Map.put(e, "extra", true)
        ] do
      assert {:error, :invalid_input_origin} = Input.validate_events([damaged], id)
      assert {:error, :invalid_input_origin} = Ipse.Session.restore_context([damaged])
    end

    assert {:error, :invalid_input_origin} = Input.validate_events([e, e], id)

    assert {:error, :invalid_input_origin} =
             Input.validate_events([e, Map.put(e, "source_id", Ipse.Usage.id())], id)

    assert {:error, :invalid_input_origin} = Input.validate_events([e], Ipse.Usage.id())

    message = %{
      "type" => "message",
      "message" => %{"role" => "user", "content" => "expanded café"}
    }

    assert :ok = Input.validate_events([e, message], id)
    assert :ok = Input.validate_events([message, e], id)

    assert {:error, :invalid_input_origin} =
             Input.validate_events([e, put_in(message["message"]["content"], "different")], id)

    observation = %{
      "version" => 1,
      "event_id" => Ipse.Usage.id(),
      "display_sha256" => Ipse.JSON.sha256("display"),
      "text_sha256" => e["text_sha256"]
    }

    observed = %{e | "origin" => "interactive_operator", "observation" => observation}
    assert :ok = Input.validate_events([observed], id)

    assert {:error, :invalid_input_origin} =
             Input.validate_events(
               [
                 observed,
                 %{observed | "source_id" => Ipse.Usage.id(), "turn_id" => Ipse.Usage.id()}
               ],
               id
             )

    assert :ok =
             Input.validate_events([
               %{"type" => "message", "message" => %{"role" => "user", "content" => "legacy"}}
             ])
  end

  test "actual terminal observations bind Session, exact text and generation, then consume once" do
    root = Path.join(System.tmp_dir!(), "ipse-input-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    driver = Path.join(root, "pty")

    assert {_, 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", driver],
               stderr_to_stdout: true
             )

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    script = Path.expand("test/support/operator_session.exs")

    {output, status} =
      System.cmd(
        driver,
        [System.find_executable("elixir"), "--erl", "+S 2:2"] ++ paths ++ [script, root],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "SESSION_INPUT_CHECKS_PASSED"
  end
end
