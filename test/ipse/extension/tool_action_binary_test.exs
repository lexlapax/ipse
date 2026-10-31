defmodule Ipse.Extension.ToolActionBinaryTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.ToolAction

  test "binary read alone admits a complete envelope above the legacy text ceiling" do
    cwd = Path.join(System.tmp_dir!(), "ipse-binary-action-" <> Ipse.Usage.id())
    File.mkdir!(cwd)
    on_exit(fn -> File.rm_rf!(cwd) end)
    bytes = :binary.copy(<<0, 255, 128, 10>>, 1024)
    File.write!(Path.join(cwd, "source.docx"), bytes)

    request = %{
      "op" => "tool.call",
      "name" => "read",
      "timeout_ms" => 5000,
      "arguments" => %{"path" => "source.docx", "encoding" => "base64", "max_bytes" => 4096}
    }

    assert :ok = ToolAction.validate(request)

    assert {:ok, %{"text" => text} = value} =
             ToolAction.execute(request, %{cwd: cwd, sandbox: :off})

    assert byte_size(text) > 4096 and byte_size(text) <= 8192
    assert ToolAction.valid_outcome?(request, "ok", value)
    assert Base.decode64!(Jason.decode!(text)["data"]) == bytes

    refute ToolAction.valid_outcome?(
             put_in(request, ["arguments"], %{"path" => "source.docx"}),
             "ok",
             value
           )

    forged =
      Jason.decode!(text) |> Map.put("sha256", Ipse.JSON.sha256("other")) |> Jason.encode!()

    refute ToolAction.valid_outcome?(request, "ok", %{"text" => forged})
    File.write!(Path.join(cwd, "text"), String.duplicate("a", 5000))

    assert {:failed, %{"reason" => "result_limit"}} =
             ToolAction.execute(
               %{request | "arguments" => %{"path" => "text"}},
               %{cwd: cwd, sandbox: :off}
             )
  end
end
