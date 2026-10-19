Code.require_file("support/stdio_probe.exs", __DIR__)

defmodule Ipse.StdioProbeTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  defmodule Responder do
    use GenServer
    def init(_), do: {:ok, nil}

    def handle_call({:invoke, "initialize", _, _}, _, state),
      do: {:reply, {:ok, %{"private" => "RESPONSE_SENTINEL"}}, state}

    def handle_call({:invoke, _, _, _}, _, state),
      do: {:reply, {:error, :extension_timeout}, state}
  end

  test "synthetic probes classify returns without retaining arguments or response payloads" do
    before = MapSet.new(:trace.session_info(:all))

    output =
      capture_io(:stderr, fn ->
        {:ok, responder} = GenServer.start_link(Responder, nil)
        probe = Ipse.Test.StdioProbe.start(self(), "synthetic")

        assert {:ok, _} =
                 Ipse.Extensions.Worker.call(responder, "initialize", %{
                   "secret" => "ARG_SENTINEL"
                 })

        task =
          Task.async(fn ->
            Ipse.Extensions.Worker.call(responder, "event.feed", %{"secret" => "ARG_SENTINEL"})
          end)

        assert {:error, :extension_timeout} = Task.await(task)
        assert :ok = Ipse.Test.StdioProbe.stop(probe)
        GenServer.stop(responder)
      end)

    refute output =~ "ARG_SENTINEL"
    refute output =~ "RESPONSE_SENTINEL"
    report = Jason.decode!(String.trim(output))
    assert report["arguments_captured"] == false
    assert report["result_payloads_retained"] == false
    assert Enum.map(report["samples"], & &1["result"]) == ["ok", "extension_timeout"]
    assert Enum.all?(report["samples"], &is_integer(&1["elapsed_ms"]))
    assert MapSet.new(:trace.session_info(:all)) == before
  end

  test "owner loss removes the synthetic trace session" do
    before = MapSet.new(:trace.session_info(:all))
    parent = self()

    output =
      capture_io(:stderr, fn ->
        spawn(fn ->
          probe = Ipse.Test.StdioProbe.start(parent, "owner-loss")
          send(parent, {:probe, probe})
        end)

        assert_receive {:probe, probe}, 1000
        monitor = Process.monitor(probe)
        assert_receive {:DOWN, ^monitor, :process, ^probe, _}, 1000
      end)

    assert Jason.decode!(String.trim(output))["reason"] == "owner_down"
    assert MapSet.new(:trace.session_info(:all)) == before
  end

  test "trace file snapshots contain only bounded path metadata" do
    root = Path.join(System.tmp_dir!(), "ipse-probe-#{Ipse.Usage.id()}")
    File.mkdir_p!(Path.join(root, "trace-ring-v1"))
    File.write!(Path.join(root, "trace-ring-v1/catalog.json"), "PRIVATE_CATALOG_SENTINEL")
    File.write!(Path.join(root, "UNRELATED_NAME_SENTINEL"), "PRIVATE_CONTENT_SENTINEL")
    on_exit(fn -> File.rm_rf!(root) end)
    output = capture_io(:stderr, fn -> Ipse.Test.StdioProbe.trace_files(root) end)
    refute output =~ "SENTINEL"
    files = Jason.decode!(String.trim(output))["synthetic_trace_files"]
    assert map_size(files) == 4
    assert files["trace-ring-v1/catalog.json"]["type"] == "regular"
    assert files["trace-ring-v1/.catalog.next"]["error"] == "enoent"
  end
end
