defmodule Ipse.Extensions.StoreTest do
  use ExUnit.Case, async: false
  alias Ipse.Extensions.{Manifest, Store}

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-artifacts-#{System.unique_integer([:positive])}")
    source = Path.join(root, "source")
    File.mkdir_p!(Path.join(source, "ebin"))

    contents = [
      {"ebin/Elixir.Fixture.Extension.beam", "inert bytes, not executable BEAM"},
      {"LICENSE", "MIT fixture"}
    ]

    for {path, bytes} <- contents, do: File.write!(Path.join(source, path), bytes)

    manifest = %{
      "format" => 1,
      "id" => "fixture/extension",
      "version" => "0.1.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => "Fixture.Extension",
      "license_file" => "LICENSE",
      "capabilities" => ["transform.prompt"],
      "options_schema" => %{"type" => "object", "additionalProperties" => false},
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      },
      "files" =>
        Enum.map(contents, fn {path, bytes} ->
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Manifest.sha256(bytes)}
        end)
    }

    bytes = Jason.encode!(manifest)
    File.write!(Path.join(source, "extension.json"), bytes)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      source: source,
      store: Path.join(root, "installed"),
      manifest: manifest,
      bytes: bytes
    }
  end

  test "closed bounded descriptor, nested duplicate keys and schema references fail", c do
    assert {:ok, manifest} = Manifest.decode(c.bytes)
    assert Manifest.compatible?(manifest)

    for bytes <- [
          "[]",
          "null",
          "{",
          c.bytes <> c.bytes,
          <<255>>,
          c.bytes <> String.duplicate(" ", 16_385),
          String.replace(c.bytes, "\"sdk\":1", "\"sdk\":1,\"sdk\":1"),
          String.replace(
            c.bytes,
            "\"type\":\"object\"",
            "\"type\":\"object\",\"type\":\"object\""
          )
        ] do
      assert {:error, :invalid_extension_manifest} = Manifest.decode(bytes)
    end

    for {key, value} <- [
          {"format", 2},
          {"format", 1.0},
          {"sdk", 2},
          {"sdk", 1.0},
          {"protocol", 2},
          {"backend", "builtin"},
          {"id", "../bad"},
          {"id", "Fixture/extension"},
          {"version", "latest"},
          {"entrypoint", "erlang:halt()"},
          {"license_file", "absent"},
          {"extra", true},
          {"capabilities", ["transform.prompt", "transform.prompt"]},
          {"options_schema", %{"type" => "object", "$ref" => "https://example.invalid/schema"}}
        ] do
      assert {:error, :invalid_extension_manifest} =
               c.manifest |> Map.put(key, value) |> Jason.encode!() |> Manifest.decode()
    end

    for key <- Map.keys(c.manifest) do
      assert {:error, :invalid_extension_manifest} =
               c.manifest |> Map.delete(key) |> Jason.encode!() |> Manifest.decode()
    end

    refute Manifest.compatible?(put_in(c.manifest, ["runtime", "elixir"], ">= 999.0.0"))
    refute Manifest.compatible?(put_in(c.manifest, ["runtime", "otp"], [255]))
    refute Manifest.compatible?(put_in(c.manifest, ["runtime", "platforms"], ["different-host"]))
  end

  test "portable paths, unique inventory, byte budgets and reserved manifest", c do
    for path <- [
          "../evil",
          "/absolute",
          "a/../b",
          "a/./b",
          "a//b",
          "a\\b",
          "a\n",
          "extension.json",
          "a/",
          "",
          String.duplicate("a", 257)
        ] do
      refute Manifest.safe_path?(path)

      bad =
        update_in(c.manifest, ["files"], fn [file | rest] ->
          [Map.put(file, "path", path) | rest]
        end)

      assert {:error, :invalid_extension_manifest} = Manifest.decode(Jason.encode!(bad))
    end

    for files <- [
          c.manifest["files"] ++ c.manifest["files"],
          Enum.map(c.manifest["files"], &Map.put(&1, "bytes", 8_388_609)),
          Enum.map(c.manifest["files"], &Map.put(&1, "sha256", String.duplicate("X", 64)))
        ] do
      assert {:error, :invalid_extension_manifest} =
               Manifest.decode(Jason.encode!(Map.put(c.manifest, "files", files)))
    end
  end

  test "import copies declared inert bytes, is pinned, private and idempotent", c do
    File.write!(Path.join(c.source, "unlisted.exs"), "raise \"must never execute\"")
    assert {:ok, installed} = Store.import(c.source, c.store)
    assert installed.digest == Manifest.sha256(c.bytes)
    assert installed.manifest == c.manifest
    assert {:ok, ^installed} = Store.lookup(c.store, installed.digest)
    assert {:ok, ^installed} = Store.import(c.source, c.store)
    refute File.exists?(Path.join(installed.path, "unlisted.exs"))
    assert Bitwise.band(File.stat!(c.store).mode, 0o077) == 0
    assert Bitwise.band(File.stat!(Path.join(installed.path, "LICENSE")).mode, 0o077) == 0
    File.write!(Path.join(c.source, "LICENSE"), "changed")
    assert {:error, :invalid_extension_artifact} = Store.import(c.source, c.store)
    assert {:ok, ^installed} = Store.lookup(c.store, installed.digest)
    File.write!(Path.join(installed.path, "LICENSE"), "tampered")
    assert {:error, :invalid_extension_artifact} = Store.lookup(c.store, installed.digest)
  end

  test "reject symlinks in manifest, source file, parent directory and root", c do
    license = Path.join(c.source, "LICENSE")
    other = Path.join(c.root, "external")
    File.rename!(license, other)
    File.ln_s!(other, license)
    assert {:error, :invalid_extension_artifact} = Store.import(c.source, c.store)
    File.rm!(license)
    File.rename!(other, license)
    ebin = Path.join(c.source, "ebin")
    File.rename!(ebin, other)
    File.ln_s!(other, ebin)
    assert {:error, :invalid_extension_artifact} = Store.import(c.source, c.store)
    File.rm!(ebin)
    File.rename!(other, ebin)
    link = Path.join(c.root, "link")
    File.ln_s!(c.source, link)
    assert {:error, :invalid_extension_artifact} = Store.import(link, c.store)
    manifest_path = Path.join(c.source, "extension.json")
    File.rename!(manifest_path, other)
    File.ln_s!(other, manifest_path)
    assert {:error, :invalid_extension_artifact} = Store.import(c.source, c.store)
  end

  test "corrupt, extra or symlinked installed content refuses lookup and overwrite", c do
    assert {:ok, installed} = Store.import(c.source, c.store)
    extra = Path.join(installed.path, "extra.beam")
    File.write!(extra, "unlisted")
    assert {:error, :invalid_extension_artifact} = Store.lookup(c.store, installed.digest)
    assert {:error, :invalid_extension_artifact} = Store.import(c.source, c.store)
    assert File.read!(extra) == "unlisted"
    File.rm!(extra)
    manifest_path = Path.join(installed.path, "extension.json")
    File.write!(manifest_path, c.bytes <> " ")
    assert {:error, :invalid_extension_artifact} = Store.lookup(c.store, installed.digest)

    for digest <- ["../evil", "", String.duplicate("A", 64), String.duplicate("a", 64)] do
      assert {:error, :invalid_extension_artifact} = Store.lookup(c.store, digest)
    end
  end

  test "source size mismatch and directory substitution never publish", c do
    File.write!(Path.join(c.source, "LICENSE"), String.duplicate("x", 100))
    assert {:error, :invalid_extension_artifact} = Store.import(c.source, c.store)
    refute File.exists?(c.store)
    File.rm!(Path.join(c.source, "LICENSE"))
    File.mkdir!(Path.join(c.source, "LICENSE"))
    assert {:error, :invalid_extension_artifact} = Store.import(c.source, c.store)
  end

  test "an abandoned stage is inert and an invalid existing lock is refused", c do
    File.mkdir_p!(c.store)
    File.chmod!(c.store, 0o700)
    abandoned = Path.join(c.store, ".staging-abandoned")
    File.mkdir!(abandoned)
    File.write!(Path.join(abandoned, "extension.json"), c.bytes)
    assert {:error, :invalid_extension_artifact} = Store.lookup(c.store, "../.staging-abandoned")
    lock_path = Path.join(c.store, ".import-#{Manifest.sha256(c.bytes)}.lock")
    File.ln_s!(Path.join(c.source, "LICENSE"), lock_path)
    assert {:error, :invalid_extension_artifact} = Store.import(c.source, c.store)
    assert File.read!(Path.join(c.source, "LICENSE")) == "MIT fixture"
    File.rm!(lock_path)
    assert {:ok, _} = Store.import(c.source, c.store)
    assert File.read!(Path.join(abandoned, "extension.json")) == c.bytes
  end

  test "advisory lock refuses a concurrent publisher and preserves lock inode", c do
    File.mkdir_p!(c.store)
    File.chmod!(c.store, 0o700)
    lock_path = Path.join(c.store, ".import-#{Manifest.sha256(c.bytes)}.lock")
    assert {:ok, lock} = Ipse.Runner.lock(lock_path)
    inode = File.stat!(lock_path).inode

    try do
      assert {:error, _} = Store.import(c.source, c.store)
      refute File.exists?(Path.join(c.store, Manifest.sha256(c.bytes)))
    after
      Ipse.Runner.unlock(lock)
    end

    assert {:ok, installed} = Store.import(c.source, c.store)
    assert File.stat!(lock_path).inode == inode
    assert {:ok, ^installed} = Store.lookup(c.store, installed.digest)
    refute Enum.any?(File.ls!(c.store), &String.starts_with?(&1, ".staging-"))
  end
end
