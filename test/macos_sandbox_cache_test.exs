defmodule Ipse.MacOSSandboxCacheTest do
  use ExUnit.Case, async: false

  alias Ipse.MacOSSandbox

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-macos-cache-#{System.unique_integer([:positive])}")
    cwd = Path.join(root, "workspace")
    home = Path.join(root, "home")
    File.mkdir_p!(cwd)
    File.mkdir!(home)
    File.chmod!(home, 0o700)
    uid = File.stat!(home).uid
    helper = Path.join(root, "fixture-helper")
    File.write!(helper, fixture_helper(uid))
    File.chmod!(helper, 0o700)
    previous = System.get_env("IPSE_HOME")
    System.put_env("IPSE_HOME", home)

    on_exit(fn ->
      if previous, do: System.put_env("IPSE_HOME", previous), else: System.delete_env("IPSE_HOME")
      File.rm_rf!(root)
    end)

    %{root: root, cwd: cwd, home: home, helper: helper}
  end

  test "publishes a private immutable generation and reuses its exact signature", ctx do
    assert {:ok, prepared} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)
    assert String.starts_with?(prepared.worker, ctx.home <> "/sandbox/macos/")
    assert String.starts_with?(prepared.data, ctx.home <> "/sandbox/macos/data/")
    assert File.stat!(prepared.worker).mode |> Bitwise.band(0o777) == 0o700
    assert File.stat!(prepared.data).mode |> Bitwise.band(0o777) == 0o700
    assert {:ok, ^prepared} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)
    assert File.read!(ctx.helper <> ".signs") == "signed\n"
  end

  test "rejects a workspace containing the helper before executing setup", ctx do
    assert {:error, reason} = MacOSSandbox.prepare(ctx.helper, ctx.root)
    assert reason =~ "overlaps the active helper"
    refute File.exists?(Path.join(ctx.home, "sandbox"))
  end

  test "rejects a workspace containing the active compiled application", ctx do
    app = :code.lib_dir(:ipse) |> List.to_string()
    assert {:error, reason} = MacOSSandbox.prepare(ctx.helper, app)
    assert reason =~ "overlaps the active helper or application"
  end

  test "rejects cache paths granted to the workspace", ctx do
    System.put_env("IPSE_HOME", Path.join(ctx.cwd, "cache-home"))
    assert {:error, reason} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)
    assert reason =~ "overlaps its protected cache"
    refute File.exists?(Path.join(ctx.cwd, "cache-home"))
  end

  test "rejects a symlinked cache ancestor without touching its destination", ctx do
    outside = Path.join(ctx.root, "outside")
    File.mkdir!(outside)
    File.chmod!(outside, 0o700)
    File.ln_s!(outside, Path.join(ctx.home, "sandbox"))
    assert {:error, reason} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)
    assert reason =~ "unsafe ownership, permissions, or links"
    assert File.ls!(outside) == []
  end

  test "rejects a cache home with permissive access rather than correcting it", ctx do
    File.chmod!(ctx.home, 0o755)
    assert {:error, reason} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)
    assert reason =~ "unsafe ownership, permissions, or links"
    assert Bitwise.band(File.stat!(ctx.home).mode, 0o777) == 0o755
  end

  test "rejects a symlink lock and preserves the target", ctx do
    cache = create_cache(ctx.home)
    outside = Path.join(ctx.root, "outside-lock")
    File.write!(outside, "sentinel")
    File.ln_s!(outside, Path.join(cache, "cache.lock"))
    assert {:error, reason} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)
    assert reason =~ "unsafe ownership, permissions, or links"
    assert File.read!(outside) == "sentinel"
  end

  test "rejects a helper with a writable workspace hard link", ctx do
    File.ln!(ctx.helper, Path.join(ctx.cwd, "helper-link"))
    assert {:error, reason} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)
    assert reason =~ "regular executable"
    refute File.exists?(Path.join(ctx.home, "sandbox"))
  end

  test "does not repair a tampered published worker", ctx do
    assert {:ok, prepared} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)
    File.write!(prepared.worker, "tampered")
    assert {:error, reason} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)
    assert reason =~ "do not match"
    assert File.read!(ctx.helper <> ".signs") == "signed\n"
    assert File.read!(prepared.worker) == "tampered"
  end

  test "rejects an extra signed entitlement even if verification reports success", ctx do
    assert {:ok, prepared} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)

    signature =
      Path.join([Path.dirname(Path.dirname(prepared.worker)), "_CodeSignature", "CodeResources"])

    File.write!(
      signature,
      "<plist version=\"1.0\"><dict><key>com.apple.security.network.client</key><true/></dict></plist>\n"
    )

    assert {:error, reason} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)
    assert reason =~ "do not match"
  end

  test "compares serialized policies despite key order and public DTD normalization", ctx do
    assert {:ok, prepared} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)

    signature =
      Path.join([
        Path.dirname(Path.dirname(prepared.worker)),
        "_CodeSignature",
        "CodeResources"
      ])

    File.write!(signature, """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict><key>data</key><string>#{prepared.data}</string><key>workspace</key><string>#{ctx.cwd}</string></dict></plist>
    """)

    assert {:ok, ^prepared} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)
  end

  test "rejects duplicate policy keys and external entity declarations", ctx do
    assert {:ok, prepared} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)

    signature =
      Path.join([
        Path.dirname(Path.dirname(prepared.worker)),
        "_CodeSignature",
        "CodeResources"
      ])

    File.write!(signature, """
    <plist version="1.0"><dict><key>workspace</key><string>#{ctx.cwd}</string><key>workspace</key><string>#{ctx.cwd}</string><key>data</key><string>#{prepared.data}</string></dict></plist>
    """)

    assert {:error, reason} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)
    assert reason =~ "duplicate keys"

    File.write!(signature, """
    <!DOCTYPE plist [<!ENTITY probe SYSTEM "file:///fixture-never-read">]>
    <plist version="1.0"><dict><key>workspace</key><string>&probe;</string></dict></plist>
    """)

    assert {:error, reason} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)
    assert reason =~ "unexpected plist schema"
  end

  test "removes only owned safe abandoned stages and retains the lock inode", ctx do
    assert {:ok, _} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)
    cache = Path.join([ctx.home, "sandbox", "macos"])
    lock_inode = File.stat!(Path.join(cache, "cache.lock")).inode
    stage = Path.join(cache, ".stage-" <> String.duplicate("a", 32))
    File.mkdir!(stage)
    File.chmod!(stage, 0o700)
    File.write!(Path.join(stage, "partial"), "interrupted signing")
    File.chmod!(Path.join(stage, "partial"), 0o600)
    assert {:ok, _} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)
    refute File.exists?(stage)
    assert File.stat!(Path.join(cache, "cache.lock")).inode == lock_inode
  end

  test "a competing setup lock prevents publication or re-signing", ctx do
    assert {:ok, _} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)
    lock_path = Path.join([ctx.home, "sandbox", "macos", "cache.lock"])
    assert {:ok, lock} = Ipse.Runner.lock(lock_path)

    try do
      assert {:error, reason} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)
      assert reason =~ "cannot acquire session lock"
      assert File.read!(ctx.helper <> ".signs") == "signed\n"
    after
      Ipse.Runner.unlock(lock)
    end
  end

  test "fails closed on a staged symlink without deleting outside files", ctx do
    cache = create_cache(ctx.home)
    stage = Path.join(cache, ".stage-" <> String.duplicate("b", 32))
    File.mkdir!(stage)
    File.chmod!(stage, 0o700)
    outside = Path.join(ctx.root, "outside-sentinel")
    File.write!(outside, "sentinel")
    File.ln_s!(outside, Path.join(stage, "link"))
    assert {:error, reason} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)
    assert reason =~ "unsafe ownership, permissions, or links"
    assert File.read!(outside) == "sentinel"
    assert File.lstat!(Path.join(stage, "link")).type == :symlink
  end

  test "enforces the generation bound before creating data or signing", ctx do
    cache = create_cache(ctx.home)

    for index <- 1..32 do
      key = index |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(64, "0")
      path = Path.join(cache, key)
      File.mkdir!(path)
      File.chmod!(path, 0o700)
    end

    assert {:error, reason} = MacOSSandbox.prepare(ctx.helper, ctx.cwd)
    assert reason =~ "32-generation limit"
    refute File.exists?(ctx.helper <> ".signs")
    assert File.ls!(Path.join(cache, "data")) == []
  end

  defp create_cache(home) do
    cache = Path.join([home, "sandbox", "macos"])
    File.mkdir_p!(Path.join(cache, "data"))

    Enum.each(
      [Path.join(home, "sandbox"), cache, Path.join(cache, "data")],
      &File.chmod!(&1, 0o700)
    )

    cache
  end

  # This fixture tests cache orchestration, never native enforcement or Apple's signature format.
  defp fixture_helper(uid) do
    """
    #!/bin/sh
    set -eu
    case "$1" in
      --uid) printf '#{uid}\\n' ;;
      --macos-entitlements)
        printf '<plist version="1.0"><dict><key>workspace</key><string>%s</string><key>data</key><string>%s</string></dict></plist>\\n' "$2" "$3"
        ;;
      --codesign)
        case "$2" in
          --force)
            mkdir "$8/Contents/_CodeSignature"
            cp "$6" "$8/Contents/_CodeSignature/CodeResources"
            printf 'signed\\n' >> "$0.signs"
            ;;
          --verify) test -f "$5/Contents/_CodeSignature/CodeResources" ;;
          --display)
            printf 'Executable=%s/Contents/MacOS/ipse-runner\\n' "$5"
            cat "$5/Contents/_CodeSignature/CodeResources"
            ;;
          *) exit 21 ;;
        esac
        ;;
      *) exit 22 ;;
    esac
    """
  end
end
