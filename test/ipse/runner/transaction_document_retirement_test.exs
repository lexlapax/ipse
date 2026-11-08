defmodule Ipse.Runner.TransactionDocumentRetirementTest do
  use ExUnit.Case, async: false
  alias Ipse.Runner.Transaction, as: T
  @moduletag :native_sandbox

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-retirement-control-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    paths =
      for name <- ["project", "collection"] do
        dir = Path.join(root, name)
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
        Path.join(dir, ".lock")
      end

    # Keep synthetic state for an independent process/unknown-effect audit.
    IO.puts("RETIREMENT_CONTROL_FIXTURE #{root}")
    %{root: root, paths: paths}
  end

  test "the exact two native locks arm one restrictive mode and cannot rearm", %{paths: paths} do
    [project, collection] =
      Enum.map(paths, fn path ->
        {:ok, cap} = T.acquire(path)
        cap
      end)

    assert {:ok, [^project, ^collection]} = T.document_retirement_stack()

    identities =
      Enum.map([project, collection], fn cap ->
        {:ok, identity} = T.retained_share_identity(cap)
        {identity.device, identity.inode}
      end)

    operation = :crypto.strong_rand_bytes(16)
    deadline = System.monotonic_time(:millisecond) + 5_000
    assert :ok = T.document_retirement_arm(collection, operation, identities, deadline)
    assert :ok = T.document_retirement_disarm(collection, deadline)

    assert {:error, :invalid_transaction_capability} =
             T.document_retirement_arm(collection, operation, identities, deadline)

    assert :ok = T.release(collection)
    assert :ok = T.release(project)
  end

  test "a changed lock identity cannot arm a document retirement", %{paths: paths} do
    [project, collection] =
      Enum.map(paths, fn path ->
        {:ok, cap} = T.acquire(path)
        cap
      end)

    {:ok, first} = T.retained_share_identity(project)
    {:ok, second} = T.retained_share_identity(collection)
    operation = :crypto.strong_rand_bytes(16)
    deadline = System.monotonic_time(:millisecond) + 5_000
    bad = [{first.device, first.inode}, {second.device, second.inode + 1}]
    refute :ok == T.document_retirement_arm(collection, operation, bad, deadline)
  end

  test "a single-lock transaction cannot arm the two-lock mode", %{paths: [path | _]} do
    {:ok, cap} = T.acquire(path)
    {:ok, identity} = T.retained_share_identity(cap)
    deadline = System.monotonic_time(:millisecond) + 5_000

    assert {:error, :invalid_transaction_capability} =
             T.document_retirement_arm(
               cap,
               :crypto.strong_rand_bytes(16),
               [{identity.device, identity.inode}, {identity.device, identity.inode}],
               deadline
             )

    assert :ok = T.release(cap)
  end

  test "an unarmed or incompletely imported switch cannot select a new root", %{paths: paths} do
    [project, collection] =
      Enum.map(paths, fn path ->
        {:ok, cap} = T.acquire(path)
        cap
      end)

    stage = ".pending-" <> Ipse.Usage.id()
    assert :ok = T.stage(collection, ".", [{stage, "new"}])

    assert {:error, :invalid_transaction_capability} =
             T.document_retirement_switch(
               collection,
               stage,
               System.system_time(:millisecond) + 30_000
             )

    refute File.exists?(Path.join(Path.dirname(List.last(paths)), "root.json"))
    assert :ok = T.release(collection)
    assert :ok = T.release(project)
  end

  for kind <- [:writer, :session] do
    @tag String.to_atom("retirement_#{kind}_control_loss")
    test "loss of the imported #{kind} control stops the native owner before switch", %{
      paths: paths
    } do
      [project, collection] =
        Enum.map(paths, fn path ->
          {:ok, cap} = T.acquire(path)
          cap
        end)

      directory = Path.dirname(List.last(paths))
      File.write!(Path.join(directory, "root.json"), "old")
      File.chmod!(Path.join(directory, "root.json"), 0o600)
      stage = ".pending-" <> Ipse.Usage.id()
      assert :ok = T.stage(collection, ".", [{stage, "new"}])

      identities =
        Enum.map([project, collection], fn cap ->
          {:ok, identity} = T.retained_share_identity(cap)
          {identity.device, identity.inode}
        end)

      operation = :crypto.strong_rand_bytes(16)
      deadline = System.monotonic_time(:millisecond) + 5_000
      assert :ok = T.document_retirement_arm(collection, operation, identities, deadline)
      writer = import_control(collection, :writer, operation, deadline)
      session = import_control(collection, :session, operation, deadline)
      lost = if unquote(kind) == :writer, do: writer, else: session
      remaining = if unquote(kind) == :writer, do: session, else: writer
      lost_ref = :erlang.monitor(:port, lost)
      remaining_ref = :erlang.monitor(:port, remaining)
      controller = collection.controller
      controller_ref = Process.monitor(controller)

      assert :ok = Ipse.Runner.close_owner_control(lost)
      assert_receive {:DOWN, ^lost_ref, :port, ^lost, _}, 5_000
      assert {:unknown, _} = T.check(collection)
      assert_receive {:DOWN, ^controller_ref, :process, ^controller, _}, 5_000

      if Port.info(remaining) != nil do
        assert :ok = Ipse.Runner.close_owner_control(remaining)
      end

      assert_receive {:DOWN, ^remaining_ref, :port, ^remaining, _}, 5_000
      assert Port.info(writer) == nil and Port.info(session) == nil

      [project_check, collection_check] =
        Enum.map(paths, fn path ->
          {:ok, cap} = T.acquire(path)
          cap
        end)

      reacquired =
        Enum.map([project_check, collection_check], fn cap ->
          {:ok, identity} = T.retained_share_identity(cap)
          {identity.device, identity.inode}
        end)

      assert reacquired === identities
      assert File.read!(Path.join(directory, "root.json")) == "old"
      assert :ok = T.release(collection_check)
      assert :ok = T.release(project_check)
    end
  end

  defp import_control(cap, kind, operation, deadline) do
    {:ok, sender} = Ipse.Runner.open_owner_control()
    assert frame(sender, ?R) == "owner-control-v1"
    {:os_pid, sender_pid} = Port.info(sender, :os_pid)
    stat = File.stat!("/proc/#{sender_pid}/fd/0")
    {:ok, %{pid: recipient}} = T.retained_share_identity(cap)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)

    entry =
      <<sender_pid::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>

    tag =
      if kind == :writer,
        do: :retirement_writer_control_import,
        else: :retirement_session_control_import

    role = if kind == :writer, do: :host, else: :session
    request = :gen_server.send_request(cap.controller, {tag, cap, operation, entry, deadline})
    assert :ok = Ipse.Runner.send_owner_control(sender, operation, role, recipient, name, secret)
    id = if kind == :writer, do: 2, else: 1
    assert frame(sender, ?H) == <<operation::binary, id>>
    assert frame(sender, ?T) == <<operation::binary, id>>

    assert {:reply, :ok} =
             :gen_server.receive_response(
               request,
               max(deadline - System.monotonic_time(:millisecond), 0)
             )

    sender
  end

  defp frame(port, kind), do: frame(port, kind, Process.get({__MODULE__, port}, <<>>))

  defp frame(port, kind, buffer) do
    case buffer do
      <<^kind, size::32, body::binary-size(size), rest::binary>> ->
        Process.put({__MODULE__, port}, rest)
        body

      _ ->
        receive do
          {^port, {:data, bytes}} when byte_size(buffer) + byte_size(bytes) <= 128 ->
            frame(port, kind, buffer <> bytes)

          {^port, {:exit_status, status}} ->
            flunk("owner control exited: #{status}")
        after
          5_000 -> flunk("owner control timed out")
        end
    end
  end
end
