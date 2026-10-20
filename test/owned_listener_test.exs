Code.require_file("support/owned_listener_verification.exs", __DIR__)

defmodule Ipse.OwnedListenerTest do
  use ExUnit.Case, async: false
  alias Ipse.Runner

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-owned-listener-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, marker: Path.join(root, "must-not-execute")}
  end

  test "malformed listener selections refuse before executing the chosen command", ctx do
    for selection <- [
          false,
          0,
          21434,
          {:ipv4_loopback, 0},
          {:ipv4_loopback, -1},
          {:ipv4_loopback, 65536},
          {:ipv4_loopback, "21434"},
          {:ipv6_loopback, 21434},
          {{127, 0, 0, 1}, 21434}
        ] do
      assert {:error, "owned_listener must be an IPv4 loopback port from 1 to 65535"} =
               Runner.open_stdio(
                 "/bin/sh",
                 ["-c", "printf executed > \"$1\"", "fixture", ctx.marker],
                 ctx.root,
                 %{},
                 1_000,
                 owned_listener: selection
               )
    end

    refute File.exists?(ctx.marker)
  end

  test "listener mode refuses incompatible policy and unsupported platforms before launch", ctx do
    command = ["-c", "printf executed > \"$1\"", "fixture", ctx.marker]

    assert {:error, "owned_listener requires sandbox :off"} =
             Runner.open_stdio("/bin/sh", command, ctx.root, %{}, 1_000,
               owned_listener: {:ipv4_loopback, 21434},
               sandbox: :native
             )

    if match?({:unix, :linux}, :os.type()) do
      assert {:error, "owned_listener executable must be absolute"} =
               Runner.open_stdio("sh", command, ctx.root, %{}, 1_000,
                 owned_listener: {:ipv4_loopback, 21434}
               )
    else
      assert {:error, "owned_listener requires Linux"} =
               Runner.open_stdio("/bin/sh", command, ctx.root, %{}, 1_000,
                 owned_listener: {:ipv4_loopback, 21434}
               )
    end

    refute File.exists?(ctx.marker)
  end

  @tag skip: not match?({:unix, :linux}, :os.type())
  test "public ownership facts distinguish owned listeners from opaque output and other processes",
       ctx do
    fixture = Path.join(ctx.root, "listener-fixture")

    assert {_, 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 Path.expand("support/owned_listener_probe.rs", __DIR__),
                 "-o",
                 fixture
               ],
               stderr_to_stdout: true
             )

    result = OwnedListenerVerification.verify(fixture, ctx.root)
    assert result["checks"] == 7
    assert result["inference_requests"] == 0
  end
end
