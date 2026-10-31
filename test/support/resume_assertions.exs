defmodule Ipse.Test.ResumeAssertions do
  import ExUnit.Assertions

  def assert_idle_resume_journal(path, before, id) do
    after_resume = File.read!(path)
    assert String.starts_with?(after_resume, before)

    suffix =
      binary_part(after_resume, byte_size(before), byte_size(after_resume) - byte_size(before))

    [header | _] = String.split(before, "\n", trim: true)
    metadata = Jason.decode!(header)["metadata"]

    if metadata["release_receipt_layout"] == Ipse.Session.ReleaseReceipt.layout() do
      assert [line] = String.split(suffix, "\n", trim: true)
      assert Ipse.Session.ReleaseReceipt.valid_owner_marker?(Jason.decode!(line), id)
      assert suffix == line <> "\n"
    else
      assert suffix == ""
    end
  end
end
