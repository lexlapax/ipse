defmodule Ipse.Extensions.WorkerTest do
  use ExUnit.Case, async: false
  alias Ipse.Extensions.{Manifest, Store, Worker, WorkerLease}

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
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Manifest.sha256(bytes)}
        end)
    }

    File.write!(Path.join(source, "extension.json"), Jason.encode!(manifest))
    store = Path.join(root, "installed")
    assert {:ok, installed} = Store.import(source, store)
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
    {:ok, scope} = Ipse.TaskResources.start(self())
    old_scope = Ipse.TaskResources.bind(scope)
    System.put_env("IPSE_RUNNER_PATH", path)

    try do
      assert {:error, :extension_admission_refused} = start(c, self())
      assert :ok = Ipse.TaskResources.finish(scope)
      refute File.exists?(c.marker)
    after
      Ipse.TaskResources.bind(old_scope)
      Ipse.TaskResources.close(scope)

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
      assert :ok = WorkerLease.close(pid, counters)
      assert :ok = WorkerLease.close(pid, counters)
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
    assert {:error, :cleanup_unconfirmed} = WorkerLease.close(pid, counters)
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
