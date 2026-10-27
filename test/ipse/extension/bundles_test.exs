defmodule Ipse.Extension.BundlesTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.{Bundles, Catalog}

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-bundle-fixture-" <> Ipse.Usage.id())
    path = Path.join(root, "package")
    File.mkdir_p!(Path.join(path, "ebin"))
    on_exit(fn -> File.rm_rf!(root) end)
    File.write!(Path.join(path, "LICENSE"), "Apache-2.0 synthetic inert fixture")
    File.write!(Path.join(path, "ebin/Elixir.BundledFixture.beam"), "inert fixture bytes")

    files =
      for name <- ["LICENSE", "ebin/Elixir.BundledFixture.beam"] do
        bytes = File.read!(Path.join(path, name))
        %{"path" => name, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
      end

    manifest = %{
      "format" => 1,
      "id" => "fixture/bundled",
      "version" => "0.1.0",
      "sdk" => 2,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => "BundledFixture",
      "license_file" => "LICENSE",
      "files" => files,
      "capabilities" => ~w(invoke.result.pages invoke.tool),
      "exports" =>
        Map.put(Catalog.empty(), "tools", [
          %{
            "id" => "inspect",
            "description" => "Inert fixture",
            "arguments_schema" => %{"type" => "object"},
            "result_schema" => %{"type" => "object"}
          }
        ]),
      "options_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => [],
        "properties" => %{}
      },
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      }
    }

    bytes = Jason.encode!(manifest)
    File.write!(Path.join(path, "extension.json"), bytes)

    catalog = %{
      "version" => 1,
      "artifacts" => [
        %{"id" => "fixture", "path" => "package", "manifest_sha256" => Ipse.JSON.sha256(bytes)}
      ]
    }

    File.write!(Path.join(root, "catalog.json"), Jason.encode!(catalog))
    %{root: root, path: path, catalog: catalog}
  end

  test "inventory is inert and install only copies the exact compatible manifest", c do
    assert {:ok, [entry]} = Bundles.inventory(c.root)
    assert entry.id == "fixture"
    refute File.exists?(Path.join(c.root, "home"))
    assert {:ok, artifact} = Bundles.install(c.root, "fixture", Path.join(c.root, "home"))
    assert artifact.digest == entry.digest
    refute :code.is_loaded(BundledFixture)
    refute File.exists?(Path.join(c.root, "home/config.json"))

    assert {:error, :extension_bundle_unavailable} =
             Bundles.install(c.root, "unknown", Path.join(c.root, "home"))
  end

  test "foreign, duplicate, unsafe and rehashed malformed entries refuse the complete inventory",
       c do
    [entry] = c.catalog["artifacts"]

    for entries <- [
          [entry, entry],
          [Map.put(entry, "path", "../package")],
          [Map.put(entry, "id", "MODEL")],
          [Map.put(entry, "manifest_sha256", Ipse.JSON.sha256("changed"))],
          [Map.put(entry, "permission", true)]
        ] do
      File.write!(
        Path.join(c.root, "catalog.json"),
        Jason.encode!(%{c.catalog | "artifacts" => entries})
      )

      assert {:error, :extension_bundle_unavailable} = Bundles.inventory(c.root)
    end

    File.write!(Path.join(c.root, "catalog.json"), Jason.encode!(c.catalog))
    File.write!(Path.join(c.path, "extension.json"), String.duplicate("x", 16385))
    assert {:error, :extension_bundle_unavailable} = Bundles.inventory(c.root)
  end

  test "changed declared payloads are refused at explicit import without running code", c do
    assert {:ok, [_]} = Bundles.inventory(c.root)

    File.write!(
      Path.join(c.path, "ebin/Elixir.BundledFixture.beam"),
      "different executable bytes"
    )

    assert {:error, :extension_bundle_unavailable} =
             Bundles.install(c.root, "fixture", Path.join(c.root, "home"))

    refute :code.is_loaded(BundledFixture)
  end

  test "catalog and manifest symbolic links refuse", c do
    bytes = File.read!(Path.join(c.root, "catalog.json"))
    File.write!(Path.join(c.root, "other.json"), bytes)
    File.rm!(Path.join(c.root, "catalog.json"))
    File.ln_s!("other.json", Path.join(c.root, "catalog.json"))
    assert {:error, :extension_bundle_unavailable} = Bundles.inventory(c.root)
    File.rm!(Path.join(c.root, "catalog.json"))
    File.write!(Path.join(c.root, "catalog.json"), bytes)
    File.rename!(Path.join(c.path, "extension.json"), Path.join(c.path, "other.json"))
    File.ln_s!("other.json", Path.join(c.path, "extension.json"))
    assert {:error, :extension_bundle_unavailable} = Bundles.inventory(c.root)
  end
end
