defmodule Ipse.DocsCheckTest do
  use ExUnit.Case, async: false

  setup_all do
    source = File.read!("dev/check-docs.exs")
    Code.compile_string(String.replace_suffix(source, "Ipse.DocsCheck.run()\n", ""))
    :ok
  end

  test "raw snapshot origins require the pinned manifest and exact snapshot bytes" do
    root = Path.join(System.tmp_dir!(), "ipse-doc-check-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "source/docs"))
    on_exit(fn -> File.rm_rf!(root) end)

    # Manifest originals are repository-relative; use an existing manual as the base.
    original = "docs/operator/corpus.md"
    snapshot = Path.join(root, "source/" <> original)
    File.mkdir_p!(Path.dirname(snapshot))
    File.write!(snapshot, "# Frozen\n")
    hash = fn bytes -> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) end
    bytes = File.read!(snapshot)
    manifest = Path.join(root, "manifest.json")

    json =
      :json.encode(%{
        "source" => [
          %{
            "path" => snapshot,
            "original" => original,
            "bytes" => byte_size(bytes),
            "sha256" => hash.(bytes)
          }
        ]
      })
      |> IO.iodata_to_binary()

    File.write!(manifest, json)
    assert {origins, []} = apply(Ipse.DocsCheck, :raw_snapshot_origins, [manifest, hash.(json)])
    assert origins[Path.expand(snapshot)] == Path.expand(original)
    assert {%{}, [_]} = apply(Ipse.DocsCheck, :raw_snapshot_origins, [manifest, hash.("other")])
    File.write!(snapshot, "# Changed\n")
    assert {%{}, [_]} = apply(Ipse.DocsCheck, :raw_snapshot_origins, [manifest, hash.(json)])
  end
end
