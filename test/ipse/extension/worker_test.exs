Code.require_file("../../support/native_pipe_scope.exs", __DIR__)

defmodule Ipse.Extension.WorkerTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.{Artifact, Worker}

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-worker-#{System.unique_integer([:positive])}")
    source = Path.join(root, "source")
    File.mkdir_p!(Path.join(source, "ebin"))
    marker = Path.join(root, "loaded")
    entrypoint = "Independent.Fixture#{System.unique_integer([:positive])}"

    File.write!(Path.join(root, "fixture.ex"), """
    defmodule #{entrypoint} do
      @behaviour Ipse.Extension
      @on_load :loaded
      def loaded, do: (File.write!(#{inspect(marker)}, "explicit worker load"); :ok)
      def describe, do: %{"sdk" => 1, "capabilities" => ~w(fixture.echo fixture.crash fixture.hang fixture.bad fixture.output fixture.env fixture.wrong fixture.duplicate fixture.atoms)}
      def init(options), do: {:ok, options}
      def handle("fixture.echo", payload, state), do: {:ok, %{"echo" => payload, "options" => state, "pid" => System.pid()}, state}
      def handle("fixture.crash", _, _), do: raise("private-synthetic-error")
      def handle("fixture.hang", _, state), do: (Process.sleep(:infinity); {:ok, %{}, state})
      def handle("fixture.bad", _, state), do: {:ok, %{"pid" => self()}, state}
      def handle("fixture.atoms", _, state), do: {:ok, %{unsafe: "atom key"}, state}
      def handle("fixture.output", _, state), do: (IO.puts("unframed private output"); {:ok, %{}, state})
      def handle("fixture.env", _, state), do: {:ok, %{"secret" => System.get_env("IPSE_WORKER_SYNTHETIC_SECRET"),
        "ipse_started" => List.keymember?(Application.started_applications(), :ipse, 0)}, state}
      def handle("fixture.wrong", _, state) do
        bytes = ~s({"protocol":1,"id":999,"result":{}})
        IO.binwrite(:stdio, <<byte_size(bytes)::32, bytes::binary>>)
        Process.sleep(:infinity)
        {:ok, %{}, state}
      end
      def handle("fixture.duplicate", _, state) do
        bytes = ~s({"protocol":1,"id":2,"result":{"field":1,"field":2}})
        IO.binwrite(:stdio, <<byte_size(bytes)::32, bytes::binary>>)
        Process.sleep(:infinity)
        {:ok, %{}, state}
      end
    end
    """)

    {output, status} =
      System.cmd(
        System.find_executable("elixirc"),
        [
          "-pa",
          Application.app_dir(:ipse, "ebin"),
          "-o",
          Path.join(source, "ebin"),
          Path.join(root, "fixture.ex")
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    File.rm(marker)
    File.write!(Path.join(source, "LICENSE"), "MIT fixture")

    manifest = %{
      "format" => 1,
      "id" => "independent/fixture",
      "version" => "0.1.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => entrypoint,
      "license_file" => "LICENSE",
      "capabilities" =>
        ~w(fixture.echo fixture.crash fixture.hang fixture.bad fixture.output fixture.env fixture.wrong fixture.duplicate fixture.atoms),
      "options_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{"label" => %{"type" => "string"}}
      },
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      },
      "files" =>
        Enum.map(["LICENSE", "ebin/Elixir.#{entrypoint}.beam"], fn path ->
          bytes = File.read!(Path.join(source, path))
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
        end)
    }

    File.write!(Path.join(source, "extension.json"), Jason.encode!(manifest))
    store = Path.join(root, "installed")
    assert {:ok, installed} = Artifact.import(source, store)
    refute File.exists?(marker)
    on_exit(fn -> File.rm_rf!(root) end)
    %{store: store, digest: installed.digest, root: root, marker: marker, entrypoint: entrypoint}
  end

  defp start(c, owner, options \\ %{}) do
    Worker.start(
      owner: owner,
      store: c.store,
      digest: c.digest,
      trusted: c.digest,
      options: options
    )
  end

  defp ready(c, options \\ %{}) do
    assert {:ok, pid} = start(c, self(), options)
    assert {:ok, %{"sdk" => 1}} = Worker.call(pid, "initialize", options)
    pid
  end

  @tag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux stdin ownership")
  test "an actual prepared VM request stays private until native delivery settles", c do
    assert {:ok, worker} =
             Worker.start(
               owner: self(),
               store: c.store,
               digest: c.digest,
               trusted: c.digest,
               protected_input: true,
               input_session: self()
             )

    assert {:ok, %{"sdk" => 1}} = Worker.call(worker, "initialize", %{})
    payload = %{"text" => "SYNTHETIC_PROTECTED_WORKER_FRAME café"}

    assert {:error, :extension_input_unavailable} =
             Task.async(fn ->
               Worker.prepare_input(worker, "fixture.echo", payload)
             end)
             |> Task.await()

    assert :sys.get_state(worker).sequence == 1
    assert {:ok, handle, binding} = Worker.prepare_input(worker, "fixture.echo", payload)
    assert binding.sequence == 2
    assert <<2::64, _::binary-size(8)>> = binding.operation
    assert binding.frame_sha256 == Ipse.JSON.sha256(binding.frame)
    assert binding.payload_sha256 == Ipse.JSON.digest([payload])
    assert binding.worker == worker and binding.caller == self() and binding.owner == self()
    assert binding.artifact == c.digest
    assert {:ok, ^binding} = Worker.input_binding(worker, handle, "fixture.echo", payload)
    assert {:error, :extension_busy} = Worker.call(worker, "fixture.echo", %{})
    assert {:error, :extension_input_unavailable} = Worker.await_input(worker, handle)

    assert {:error, :extension_input_unavailable} =
             Worker.input_binding(worker, handle, "fixture.echo", %{})

    assert {:error, :extension_input_unavailable} =
             Task.async(fn ->
               Worker.input_binding(worker, handle, "fixture.echo", payload)
             end)
             |> Task.await()

    result =
      deliver_prepared(worker, handle, binding, c.root, fn ->
        await_input_buffer(worker, System.monotonic_time(:millisecond) + 1_000)
        assert {:error, :extension_input_unavailable} = Worker.await_input(worker, handle)
        assert :sys.get_state(worker).pending.id == binding.sequence
      end)

    assert {:ok, %{"echo" => ^payload, "pid" => child}} = result
    refute child == System.pid()
    assert {:error, :extension_input_unavailable} = Worker.await_input(worker, handle)
    assert {:ok, %{"echo" => %{}}} = Worker.call(worker, "fixture.echo", %{})
    assert :ok = Worker.close(worker)
  end

  @tag timeout: 180_000
  @tag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux stdin ownership")
  test "one actual worker settles more than 256 distinct native input handoffs", c do
    assert {:ok, worker} =
             Worker.start(
               owner: self(),
               store: c.store,
               digest: c.digest,
               trusted: c.digest,
               protected_input: true
             )

    assert {:ok, %{"sdk" => 1}} = Worker.call(worker, "initialize", %{})

    for step <- 1..257 do
      payload = %{"step" => step}
      assert {:ok, handle, binding} = Worker.prepare_input(worker, "fixture.echo", payload)
      assert binding.sequence == step + 1

      assert {:ok, %{"echo" => ^payload}} =
               deliver_prepared(worker, handle, binding, c.root, fn -> :ok end)
    end

    assert :sys.get_state(worker).sequence == 258
    assert :ok = Worker.close(worker)
  end

  defp deliver_prepared(worker, handle, binding, root, after_write) do
    {scope, bound} = bind_prepared(worker, handle, binding, root)

    assert :ok =
             GenServer.call(
               scope.cap.controller,
               {:pipe_write, scope.cap, bound.operation, bound.frame}
             )

    after_write.()

    closing =
      :gen_server.send_request(scope.cap.controller, {:pipe_close, scope.cap, bound.operation})

    assert :ok = Worker.settle_stdin(worker, handle)
    assert {:reply, :ok} = :gen_server.receive_response(closing, 5_000)
    Ipse.Test.NativePipeScope.close(scope)
    Worker.await_input(worker, handle)
  end

  defp bind_prepared(worker, handle, binding, root) do
    scope = Ipse.Test.NativePipeScope.open(Path.join(root, "controlled-" <> Ipse.Usage.id()))

    wall =
      System.system_time(:millisecond) +
        min(3_000, binding.deadline - System.monotonic_time(:millisecond) - 1)

    assert {:ok, bound} = Worker.bind_stdin(worker, handle, wall)
    assert bound.frame == binding.frame and bound.frame_sha256 == binding.frame_sha256
    assert bound.pipe.pid == binding.native_pid and bound.pipe.inode > 0
    {name, secret} = {:crypto.strong_rand_bytes(16), :crypto.strong_rand_bytes(32)}
    id = bound.pipe
    entry = <<id.pid::32, name::binary, secret::binary, id.device::64, id.inode::64>>
    recipient = <<scope.recipient::32, name::binary, secret::binary, id.device::64, id.inode::64>>

    deadline =
      System.monotonic_time(:millisecond) + min(3_000, wall - System.system_time(:millisecond))

    request =
      :gen_server.send_request(
        scope.cap.controller,
        {:pipe_import, scope.cap, bound.operation, entry, wall, deadline, bound.frame}
      )

    assert :ok = Worker.export_stdin(worker, handle, recipient)
    assert {:reply, :ok} = :gen_server.receive_response(request, 5_000)

    {scope, bound}
  end

  @tag :native_frame_binding
  @tag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux stdin ownership")
  test "the native writer cannot replace the actual reserved worker frame", c do
    assert {:ok, worker} =
             Worker.start(
               owner: self(),
               store: c.store,
               digest: c.digest,
               trusted: c.digest,
               protected_input: true
             )

    assert {:ok, %{"sdk" => 1}} = Worker.call(worker, "initialize", %{})

    assert {:ok, handle, binding} =
             Worker.prepare_input(worker, "fixture.echo", %{"expected" => true})

    {scope, bound} = bind_prepared(worker, handle, binding, c.root)
    <<size::32, body::binary-size(size)>> = bound.frame

    replacement =
      body |> Jason.decode!() |> Map.put("payload", %{"substituted" => true}) |> Jason.encode!()

    altered = <<byte_size(replacement)::32, replacement::binary>>

    assert {:unknown, :transaction_lost} =
             GenServer.call(
               scope.cap.controller,
               {:pipe_write, scope.cap, bound.operation, altered}
             )

    assert :ok = Worker.close(worker)
    Ipse.Test.NativePipeScope.close(scope)
  end

  test "ordinary workers do not acquire the private protected input interface", c do
    worker = ready(c)

    assert {:error, :extension_input_unavailable} =
             Worker.prepare_input(worker, "fixture.echo", %{})

    assert {:ok, %{"echo" => %{}}} = Worker.call(worker, "fixture.echo", %{})
    assert :ok = Worker.close(worker)
  end

  @tag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux stdin ownership")
  test "a protected pending input ignores an alternate supervisor", c do
    alternate = Path.join(c.root, "not-a-protected-supervisor")
    File.write!(alternate, "not executable")
    File.chmod!(alternate, 0o600)
    previous = System.get_env("IPSE_RUNNER_PATH")
    System.put_env("IPSE_RUNNER_PATH", alternate)

    try do
      assert {:ok, worker} =
               Worker.start(
                 owner: self(),
                 store: c.store,
                 digest: c.digest,
                 trusted: c.digest,
                 protected_input: true
               )

      assert {:ok, %{"sdk" => 1}} = Worker.call(worker, "initialize", %{})
      assert {:ok, _, binding} = Worker.prepare_input(worker, "fixture.echo", %{})
      assert {:ok, helper} = Ipse.Runner.protected_helper(c.root)
      selected = File.stat!(helper)
      actual = File.stat!("/proc/#{binding.native_pid}/exe")
      assert {actual.major_device, actual.inode} == {selected.major_device, selected.inode}
      assert :ok = Worker.close(worker)
    after
      if previous,
        do: System.put_env("IPSE_RUNNER_PATH", previous),
        else: System.delete_env("IPSE_RUNNER_PATH")
    end
  end

  @tag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux stdin ownership")
  test "a prepared request keeps its original timer and confirms native cleanup", c do
    counters = :atomics.new(9, signed: true)

    assert {:ok, worker} =
             Worker.start(
               owner: self(),
               store: c.store,
               digest: c.digest,
               trusted: c.digest,
               protected_input: true,
               cleanup_lease: counters
             )

    assert {:ok, %{"sdk" => 1}} = Worker.call(worker, "initialize", %{})
    ref = Process.monitor(worker)
    assert {:ok, handle, _} = Worker.prepare_input(worker, "fixture.echo", %{}, 100)
    assert_receive {:DOWN, ^ref, :process, ^worker, :normal}, 3_000
    assert :atomics.get(counters, 9) == 2
    assert {:error, :extension_input_unavailable} = Worker.await_input(worker, handle)
  end

  defp await_input_buffer(worker, deadline) do
    if is_binary(:sys.get_state(worker).input.response) do
      :ok
    else
      assert System.monotonic_time(:millisecond) < deadline
      Process.sleep(2)
      await_input_buffer(worker, deadline)
    end
  end

  test "explicit trust, options and compatibility are required before code loads", c do
    File.rm(c.marker)

    assert {:error, :extension_admission_refused} =
             Worker.start(owner: self(), store: c.store, digest: c.digest)

    assert {:error, :extension_admission_refused} = start(c, self(), %{"unknown" => true})
    refute File.exists?(c.marker)
    assert_raise ArgumentError, fn -> String.to_existing_atom("Elixir." <> c.entrypoint) end
  end

  test "a refused native launch retires its scope ticket without loading the artifact", c do
    File.rm(c.marker)
    path = Path.join(c.root, "nonexecutable-helper")
    File.write!(path, "fixture")
    File.chmod!(path, 0o600)
    previous = System.get_env("IPSE_RUNNER_PATH")
    {:ok, scope} = Ipse.Session.Resources.start(self())
    old_scope = Ipse.Session.Resources.bind(scope)
    System.put_env("IPSE_RUNNER_PATH", path)

    try do
      assert {:error, :extension_admission_refused} = start(c, self())
      assert :ok = Ipse.Session.Resources.finish(scope)
      refute File.exists?(c.marker)
    after
      Ipse.Session.Resources.bind(old_scope)
      Ipse.Session.Resources.close(scope)

      if previous,
        do: System.put_env("IPSE_RUNNER_PATH", previous),
        else: System.delete_env("IPSE_RUNNER_PATH")
    end
  end

  test "separate VM initializes once, preserves private state and validates capabilities", c do
    File.rm(c.marker)
    assert {:ok, pid} = start(c, self(), %{"label" => "fixture"})
    refute File.exists?(c.marker)
    assert {:ok, %{"sdk" => 1}} = Worker.call(pid, "initialize", %{"label" => "fixture"})
    assert File.read!(c.marker) == "explicit worker load"
    assert {:ok, result} = Worker.call(pid, "fixture.echo", %{"text" => "hello"})
    assert result["echo"] == %{"text" => "hello"}
    assert result["options"] == %{"label" => "fixture"}
    status = inspect(:sys.get_status(pid), limit: :infinity, printable_limit: :infinity)
    refute status =~ "inert bytes"
    refute status =~ "\"label\""
    refute result["pid"] == System.pid()
    assert_raise ArgumentError, fn -> String.to_existing_atom("Elixir." <> c.entrypoint) end
    assert {:error, :invalid_extension_request} = Worker.call(pid, "initialize", %{})
    assert {:error, :invalid_extension_request} = Worker.call(pid, "undeclared.feature", %{})

    assert {:error, :invalid_extension_request} =
             Worker.call(pid, "fixture.echo", %{"private" => self()})

    assert {:error, :invalid_extension_request} =
             Worker.call(pid, "fixture.echo", %{"text" => String.duplicate("a", 8193)})

    assert :ok = Worker.close(pid)
    refute Process.alive?(pid)
  end

  test "credentials and arbitrary operator environment do not reach the worker", c do
    System.put_env("IPSE_WORKER_SYNTHETIC_SECRET", "must-not-cross")

    try do
      pid = ready(c)

      assert {:ok, %{"secret" => nil, "ipse_started" => false}} =
               Worker.call(pid, "fixture.env", %{})

      assert :ok = Worker.close(pid)
    after
      System.delete_env("IPSE_WORKER_SYNTHETIC_SECRET")
    end
  end

  test "crash, non-JSON return and unframed output terminate instead of leaking diagnostics", c do
    for stage <-
          ~w(fixture.crash fixture.bad fixture.output fixture.wrong fixture.duplicate fixture.atoms) do
      pid = ready(c)
      ref = Process.monitor(pid)
      assert {:error, reason} = Worker.call(pid, stage, %{})
      assert reason in [:extension_exited, :invalid_extension_output]
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 3_000
    end
  end

  test "callback timeout kills the worker and concurrent invocation is refused", c do
    pid = ready(c)
    ref = Process.monitor(pid)
    task = Task.async(fn -> Worker.call(pid, "fixture.hang", %{}, 300) end)
    # The request is dispatched before checking contention, independent of VM scheduling.
    wait_pending(pid)
    assert {:error, :extension_busy} = Worker.call(pid, "fixture.echo", %{})
    assert {:error, :extension_timeout} = Task.await(task, 3_000)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 3_000
  end

  test "lease retains native confirmation after worker self-termination", c do
    for stage <- ["fixture.crash", "fixture.hang"] do
      counters = :atomics.new(9, signed: false)

      assert {:ok, pid} =
               Worker.start(
                 owner: self(),
                 store: c.store,
                 digest: c.digest,
                 trusted: c.digest,
                 cleanup_lease: counters
               )

      assert {:ok, _} = Worker.call(pid, "initialize", %{})
      ref = Process.monitor(pid)
      assert {:error, _} = Worker.call(pid, stage, %{}, 100)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 3_000
      assert :ok = Worker.close_lease(pid, counters)
      assert :ok = Worker.close_lease(pid, counters)
    end
  end

  test "worker death without a native receipt cannot confirm its lease", c do
    counters = :atomics.new(9, signed: false)

    assert {:ok, pid} =
             Worker.start(
               owner: self(),
               store: c.store,
               digest: c.digest,
               trusted: c.digest,
               cleanup_lease: counters
             )

    assert {:ok, _} = Worker.call(pid, "initialize", %{})
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 3_000
    assert {:error, :cleanup_unconfirmed} = Worker.close_lease(pid, counters)
  end

  test "owner death stops idle and active workers", c do
    for active <- [false, true] do
      owner =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      assert {:ok, pid} = start(c, owner)
      assert {:ok, _} = Worker.call(pid, "initialize", %{})
      ref = Process.monitor(pid)
      task = if active, do: Task.async(fn -> Worker.call(pid, "fixture.hang", %{}, 30_000) end)
      if active, do: wait_pending(pid)
      Process.exit(owner, :kill)
      if active, do: assert({:error, :owner_exited} = Task.await(task, 3_000))
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 3_000
    end
  end

  defp wait_pending(pid, attempts \\ 100)
  defp wait_pending(_pid, 0), do: flunk("callback was not dispatched")

  defp wait_pending(pid, attempts) do
    if :sys.get_state(pid).pending == nil do
      Process.sleep(5)
      wait_pending(pid, attempts - 1)
    end
  end
end
