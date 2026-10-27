defmodule Ipse.Runner.ProtectedHelperTest do
  use ExUnit.Case, async: false
  alias Ipse.Runner

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-protected-helper-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    cwd = Path.join(parent, "workspace")
    File.mkdir!(cwd)
    File.chmod!(cwd, 0o700)
    marker = Path.join(parent, "invoked")
    poison = Path.join(parent, "poison")
    quoted = "'" <> String.replace(marker, "'", "'\\''") <> "'"
    File.write!(poison, "#!/bin/sh\nprintf invoked > " <> quoted <> "\nexit 97\n")
    File.chmod!(poison, 0o700)
    previous = System.get_env("IPSE_RUNNER_PATH")
    System.put_env("IPSE_RUNNER_PATH", poison)

    on_exit(fn ->
      if previous,
        do: System.put_env("IPSE_RUNNER_PATH", previous),
        else: System.delete_env("IPSE_RUNNER_PATH")

      File.rm_rf!(parent)
    end)

    %{parent: parent, cwd: cwd, marker: marker, poison: poison}
  end

  test "protected identity queries and durability sync never invoke the ambient helper", c do
    assert {:error, _} = Runner.current_uid()
    assert File.read!(c.marker) == "invoked"
    File.rm!(c.marker)
    assert {:ok, uid} = Runner.protected_current_uid()
    assert uid == File.stat!(c.parent).uid
    assert {:ok, helper} = Runner.protected_helper(c.cwd)
    refute helper == c.poison
    assert :ok = Runner.protected_sync_directory(c.cwd)
    refute File.exists?(c.marker)
  end

  test "protected stdio binds its supervisor as well as its selected child", c do
    assert {:ok, helper} = Runner.protected_helper(c.cwd)

    assert {:error, "protected_supervisor must be a boolean"} =
             Runner.open_stdio(helper, ["--uid"], c.cwd, %{}, 2_000, protected_supervisor: "true")

    assert {:ok, port} =
             Runner.open_protected_stdio(helper, ["--uid"], c.cwd, %{}, 2_000,
               protected_supervisor: false
             )

    try do
      frames = await_completion(port, <<>>, System.monotonic_time(:millisecond) + 5_000)
      rows = decode_frames(frames, [])
      output = for {?O, bytes} <- rows, into: <<>>, do: bytes
      assert Integer.parse(String.trim(output)) == {File.stat!(c.parent).uid, ""}
      assert [{?X, completion}] = Enum.filter(rows, &(elem(&1, 0) == ?X))

      assert {:ok, %{"exit_code" => 0, "timed_out" => false}} =
               Ipse.JSON.decode_unique(completion)

      refute File.exists?(c.marker)
    after
      assert :ok = Runner.close_stdio(port, :completed)
    end
  end

  defp await_completion(port, bytes, deadline) do
    receive do
      {^port, {:data, data}} when byte_size(bytes) + byte_size(data) <= 4096 ->
        frames = bytes <> data

        if terminal_frame?(frames),
          do: frames,
          else: await_completion(port, frames, deadline)
    after
      max(0, deadline - System.monotonic_time(:millisecond)) ->
        flunk("protected supervisor did not exit")
    end
  end

  defp terminal_frame?(<<?X, size::32, _completion::binary-size(size)>>), do: true

  defp terminal_frame?(<<_tag, size::32, _bytes::binary-size(size), tail::binary>>),
    do: terminal_frame?(tail)

  defp terminal_frame?(_partial), do: false

  defp decode_frames(<<>>, rows), do: Enum.reverse(rows)

  defp decode_frames(<<tag, size::32, bytes::binary-size(size), tail::binary>>, rows),
    do: decode_frames(tail, [{tag, bytes} | rows])
end
