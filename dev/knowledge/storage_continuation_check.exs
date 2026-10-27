Code.require_file("storage_continuation.exs", __DIR__)

defmodule Ipse.Development.StorageContinuationCheck do
  @moduledoc false
  alias Ipse.Development.StorageContinuation, as: O
  alias Ipse.Runner.Transaction, as: T

  def run([mode, report_path, output]) when mode in ~w(refusals corrupt) do
    Process.flag(:max_heap_size, %{size: 8_000_000, kill: true, error_logger: true})
    report_bytes = File.read!(report_path)
    true = byte_size(report_bytes) <= 2 * 1024 * 1024
    report = Jason.decode!(report_bytes)
    reference = report["continuation"]
    directory = Path.dirname(reference["path"])
    location = report["retained_store"]
    before = status(location)

    controls =
      if mode == "refusals" do
        {:ok, checkpoint, _} = O.read(reference["path"], reference["sha256"])

        {:error, :continuation_binding_or_progress} =
          O.validate(checkpoint, String.duplicate("0", 64), report["options"])

        {:error, :continuation_binding_or_progress} =
          O.validate(Map.put(checkpoint, "segment", 4), checkpoint["binding"], report["options"])

        {:error, :continuation_unclean_or_corrupt} =
          O.read(reference["path"], String.duplicate("0", 64))

        extra = Path.join(Path.dirname(directory), "segment-#{checkpoint["segment"] + 1}")
        :ok = File.mkdir(extra)
        :ok = File.chmod(extra, 0o700)
        resume_refused(report, output <> ".extra-segment")
        :ok = File.rmdir(extra)

        marker = ".pending-" <> Ipse.Usage.id()

        oracle(directory, fn cap ->
          :ok = T.stage(cap, ".", [{marker, "known fixture injection"}])
        end)

        {:error, :continuation_unclean_or_corrupt} =
          O.read(reference["path"], reference["sha256"])

        resume_refused(report, output <> ".pending")
        # Only this known, confirmed fixture injection is removed. The driver
        # contains no repair or automatic cleanup for an unclean boundary.
        oracle(directory, fn cap -> :ok = T.reclaim(cap, ".", [marker]) end)
        {:ok, ^checkpoint, _} = O.read(reference["path"], reference["sha256"])
        ~w(source_binding segment_limit checksum extra_segment pending_marker)
      else
        oracle(directory, fn cap ->
          pending = ".pending-" <> Ipse.Usage.id()
          :ok = T.stage(cap, ".", [{pending, "{corrupt benchmark checkpoint"}])
          :ok = T.switch(cap, pending, "root.json")
        end)

        {:error, :continuation_unclean_or_corrupt} =
          O.read(reference["path"], reference["sha256"])

        ["corrupted_checkpoint"]
      end

    after_status = status(location)
    true = before == after_status

    proof = %{
      "kind" => "development_continuation_controls",
      "controls_passed" => controls,
      "collection_unchanged" => true,
      "collection_status" => after_status,
      "retained_store" => location,
      "checkpoint" => reference,
      "known_injection_cleanup_is_fixture_only" => true,
      "live_calls" => 0,
      "qualification_passed" => false
    }

    File.write!(output, Jason.encode!(proof, pretty: true) <> "\n")
    IO.puts(Jason.encode!(proof, pretty: true))
  end

  defp resume_refused(report, output) do
    reference = report["continuation"]
    opts = report["options"]

    args = [
      "--resume",
      reference["path"],
      "--resume-sha256",
      reference["sha256"],
      "--days",
      to_string(opts["days"]),
      "--cycles",
      to_string(opts["cycles"]),
      "--payload",
      opts["payload"],
      "--segment-publications",
      to_string(opts["segment_publications"]),
      "--output",
      output
    ]

    paths =
      :code.get_path()
      |> Enum.reject(&(&1 == ~c"."))
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", List.to_string(&1)])

    code =
      ~s|{:ok,_}=Application.ensure_all_started(:ipse); Code.require_file("dev/knowledge/storage_workload.exs")|

    {log, exit} =
      System.cmd(System.find_executable("elixir"), paths ++ ["-e", code, "--"] ++ args,
        env: [{"ERL_FLAGS", "+S 2:2"}],
        stderr_to_stdout: true
      )

    File.write!(output <> ".log", log)
    true = exit != 0
    failure = Jason.decode!(File.read!(output <> ".failure.json"))
    true = failure["calls"] == %{} and failure["automatic_retries"] == 0
  end

  defp oracle(directory, function) do
    {:ok, cap} = T.acquire(Path.join(directory, ".lock"), cwd: directory)

    try do
      :ok = T.quota(cap, :flat, 8 * 1024 * 1024)
      function.(cap)
      :ok = T.check(cap)
    after
      :ok = T.release(cap)
    end
  end

  defp status(location) do
    {:ok, status} =
      Ipse.Extension.Collection.execute(
        location["root"],
        location["project"],
        %{"op" => "status"},
        Ipse.Usage.id()
      )

    status
  end
end

Ipse.Development.StorageContinuationCheck.run(System.argv())
