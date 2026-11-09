defmodule Ipse.Runner.TransactionRetainedShareTest do
  use ExUnit.Case, async: false
  # Retained-share identity and transfer are compiled only into the Linux helper.
  @moduletag skip:
               if(:os.type() == {:unix, :linux}, do: false, else: "Linux native retained share")
  alias Ipse.Runner.Transaction, as: T

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-transaction-retained-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    paths =
      for n <- 1..3 do
        dir = Path.join(root, Integer.to_string(n))
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    on_exit(fn -> File.rm_rf!(root) end)
    %{paths: paths}
  end

  test "exact same-owner three retained descriptions settle in manifest order", %{paths: paths} do
    caps =
      Enum.map(paths, fn path ->
        assert {:ok, cap} = T.acquire(path)
        cap
      end)

    identities =
      Enum.map(caps, fn cap ->
        assert {:ok, identity} = T.retained_share_identity(cap)
        identity
      end)

    assert Enum.map(identities, & &1.slot) == [0, 1, 2]
    assert length(Enum.uniq(Enum.map(identities, & &1.pid))) == 1

    Enum.zip(paths, identities)
    |> Enum.each(fn {path, identity} ->
      stat = File.stat!(path)
      assert {identity.device, identity.inode} == {stat.major_device, stat.inode}
    end)

    assert {:error, :invalid_transaction_capability} =
             Task.await(Task.async(fn -> T.retained_share_identity(hd(caps)) end))

    operation = :crypto.strong_rand_bytes(16)
    deadline = System.monotonic_time(:millisecond) + 5_000
    {collector, pid} = collector()
    on_exit(fn -> if Port.info(collector), do: Port.close(collector) end)

    bindings =
      Enum.map(identities, fn id ->
        {id, :crypto.strong_rand_bytes(16), :crypto.strong_rand_bytes(32)}
      end)

    entries =
      Enum.map(bindings, fn {id, name, secret} ->
        <<id.slot, id.pid::32, name::binary, secret::binary, id.device::64, id.inode::64>>
      end)
      |> IO.iodata_to_binary()

    initial = <<5_000::64, operation::binary, 3, entries::binary>>
    assert Port.command(collector, <<?I, byte_size(initial)::32, initial::binary>>)
    assert frame(collector, ?H) == <<operation::binary, 3>>

    Enum.zip(caps, bindings)
    |> Enum.each(fn {cap, {id, name, secret}} ->
      recipient = <<pid::32, name::binary, secret::binary, id.device::64, id.inode::64>>
      assert :ok = T.retained_share_export(cap, operation, recipient, deadline)
    end)

    assert frame(collector, ?L) == <<operation::binary, 3>>
    assert {:error, :transaction_share_frozen} = T.check(List.last(caps))
    assert {:error, :transaction_share_frozen} = T.release(List.last(caps))

    assert {:error, :invalid_transaction_capability} =
             T.retained_share_settle(Enum.at(caps, 1), operation, deadline)

    assert Port.command(collector, <<?C, operation::binary>>)
    Enum.each(caps, fn cap -> assert :ok = T.retained_share_settle(cap, operation, deadline) end)
    assert frame(collector, ?C) == <<operation::binary, 3>>
    assert_receive {^collector, {:exit_status, 0}}, 5_000
    Enum.reverse(caps) |> Enum.each(fn cap -> assert :ok = T.release(cap) end)
  end

  test "recipient loss after transfer is unknown and never thaws", %{paths: [path | _]} do
    assert {:ok, cap} = T.acquire(path)
    assert {:ok, id} = T.retained_share_identity(cap)
    operation = :crypto.strong_rand_bytes(16)
    deadline = System.monotonic_time(:millisecond) + 5_000
    {collector, pid} = collector()
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)
    entry = <<0, id.pid::32, name::binary, secret::binary, id.device::64, id.inode::64>>
    initial = <<5_000::64, operation::binary, 1, entry::binary>>
    assert Port.command(collector, <<?I, byte_size(initial)::32, initial::binary>>)
    assert frame(collector, ?H) == <<operation::binary, 1>>
    request = <<pid::32, name::binary, secret::binary, id.device::64, id.inode::64>>
    assert :ok = T.retained_share_export(cap, operation, request, deadline)
    assert frame(collector, ?L) == <<operation::binary, 1>>
    Port.close(collector)
    assert {:unknown, :transaction_lost} = T.retained_share_settle(cap, operation, deadline)
    assert {:error, :invalid_transaction_capability} = T.check(cap)
  end

  defp collector do
    helper = Path.join(to_string(:code.priv_dir(:ipse)), "ipse-runner")

    port =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        args: ["--lease-collect-close-ready-v3"]
      ])

    {:os_pid, pid} = Port.info(port, :os_pid)
    {port, pid}
  end

  defp frame(port, tag, buffer \\ <<>>) do
    case buffer do
      <<^tag, size::32, body::binary-size(size)>> ->
        body

      _ ->
        receive do
          {^port, {:data, bytes}} when byte_size(buffer) + byte_size(bytes) <= 256 ->
            frame(port, tag, buffer <> bytes)

          {^port, {:exit_status, status}} ->
            flunk("collector exit #{status}")
        after
          5_000 -> flunk("collector timeout")
        end
    end
  end
end
