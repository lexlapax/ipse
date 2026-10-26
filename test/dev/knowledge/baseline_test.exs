defmodule Ipse.Development.Knowledge.BaselineTest do
  use ExUnit.Case, async: true

  test "the frozen proposal reverses mechanically to its exact source hash" do
    root = "docs/archive/2026-10-26-p30-p31-implementation"
    manifest = JSON.decode!(File.read!(Path.join(root, "manual-provenance.json")))
    assert manifest["source_commit"] == "fbb207d"
    [file] = manifest["files"]
    snapshot = File.read!(Path.join(root, file["snapshot"]))
    assert sha(snapshot) == file["snapshot_sha256"]
    [_, body] = String.split(snapshot, "# Knowledge and decision delivery design\n", parts: 2)
    original = "# Knowledge and decision delivery design\n" <> body
    original = Regex.replace(~r/\]\(\.\.\/\.\.\/([^)]+)\)/, original, "](\\1)")
    assert sha(original) == file["source_sha256"]
    assert File.read!("docs/knowledge-design.md") =~ "frozen implementation baseline"
  end

  defp sha(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
