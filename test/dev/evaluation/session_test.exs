Code.require_file("../../../dev/evaluation/session.exs", __DIR__)
Code.require_file("../../support/stdio_probe.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.Development.Evaluation.Session, as: Evaluation

  test "structured answer transport rejects mixed shapes before attempting a dispatch" do
    request = %{
      "op" => "model.complete",
      "version" => 2,
      "profile" => "p27_answer",
      "instruction" => "Return an object.",
      "input" => "input",
      "max_output_bytes" => 8192,
      "timeout_ms" => 120_000,
      "response_schema" => %{"type" => "object"}
    }

    assert :ok = Ipse.Extension.ModelCall.validate(request)
    run = %{}

    for params <- [
          request,
          %{"request" => Map.put(request, "version", 1)},
          %{"request" => Map.put(request, "profile", "other")},
          %{"request" => request, "extra" => true},
          %{"request" => Map.put(request, "response_schema", %{"type" => "array"})}
        ] do
      assert {:error, :invalid_answer, ^run} = Evaluation.invoke(run, "answer", params)
    end

    byte_overflow = Map.put(request, "input", String.duplicate("é", 2050))
    assert :ok = Ipse.Extension.ModelCall.validate(byte_overflow)

    assert {:error, :invalid_answer, ^run} =
             Evaluation.invoke(run, "answer", %{"request" => byte_overflow})
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-evaluation-fault-artifact-" <> Ipse.Usage.id())
    artifact = Path.join(root, "artifact")
    File.mkdir_p!(Path.join(artifact, "ebin"))
    capabilities = ["invoke.command", "invoke.result.pages"]

    descriptor = %{
      "id" => "source",
      "description" => "Synthetic evaluation-driver failure boundary",
      "arguments_schema" => %{
        "type" => "object",
        "required" => ~w(store action args),
        "additionalProperties" => false,
        "properties" => %{
          "store" => %{"type" => "string"},
          "action" => %{"type" => "string"},
          "args" => %{"type" => "object"}
        }
      },
      "result_schema" => %{"type" => "object"}
    }

    exports = %{"version" => 1, "commands" => [descriptor], "tools" => [], "services" => []}
    entrypoint = "Independent.EvaluationFaultFixture"

    source = """
    defmodule #{entrypoint} do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 2, "capabilities" => #{inspect(capabilities)}, "exports" => #{inspect(exports)}}
      def init(options) do
        if options["mode"] == "slow_start", do: Process.sleep(1500)
        {:ok, options}
      end
      def handle("invoke.command", payload, options) do
        args = payload["arguments"]
        action = args["action"]
        File.write!(options["log"], action <> "\\n", [:append])
        if action == "put" and options["mode"] == "hang" do
          File.write!(options["ready"], System.pid())
          Process.sleep(:infinity)
        end
        if action == "put" and options["mode"] == "fail", do: raise("PRIVATE_CALLBACK_DETAIL")
        continuation = case action do
          "open" -> %{"draft_id" => String.duplicate("a", 32), "expected_revision" => 1,
            "offset" => if(options["mode"] == "bad_open", do: 1, else: 0)}
          "append" -> %{"draft_id" => String.duplicate("a", 32), "expected_revision" => 2,
            "offset" => args["args"]["offset"] + byte_size(args["args"]["text"]) + 1}
          _ -> nil
        end
        value = %{"version" => 1, "status" => if(continuation, do: "draft", else: "ok"),
          "coverage" => %{}, "evidence" => [], "claims" => [], "gaps" => [],
          "continuation" => continuation}
        value = if options["mode"] == "large" do
          Map.put(value, "complete_evidence", [String.duplicate("a", 8192), String.duplicate("b", 8192)])
        else
          value
        end
        {:ok, publication} = Ipse.Extension.ResultPublication.prepare(value)
        {:ok, publication, options}
      end
    end
    """

    path = Path.join(root, "fixture.ex")
    File.write!(path, source)

    {output, status} =
      System.cmd(
        System.find_executable("elixirc"),
        ["-pa", Application.app_dir(:ipse, "ebin"), "-o", Path.join(artifact, "ebin"), path],
        stderr_to_stdout: true
      )

    assert status == 0, output
    File.write!(Path.join(artifact, "LICENSE"), "MIT synthetic fixture")

    manifest = %{
      "format" => 1,
      "id" => "fixture/evaluation-driver-faults",
      "version" => "0.1.0",
      "sdk" => 2,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => entrypoint,
      "license_file" => "LICENSE",
      "options_schema" => %{
        "type" => "object",
        "required" => ~w(mode log ready),
        "additionalProperties" => false,
        "properties" => %{
          "mode" => %{
            "type" => "string",
            "enum" => ~w(bad_open bad_append hang large fail slow_start)
          },
          "log" => %{"type" => "string"},
          "ready" => %{"type" => "string"}
        }
      },
      "capabilities" => capabilities,
      "exports" => exports,
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      },
      "files" =>
        for relative <- ["LICENSE", "ebin/Elixir.#{entrypoint}.beam"],
            bytes = File.read!(Path.join(artifact, relative)) do
          %{"path" => relative, "bytes" => byte_size(bytes), "sha256" => sha(bytes)}
        end
    }

    File.write!(Path.join(artifact, "extension.json"), JSON.encode!(manifest))
    on_exit(fn -> File.rm_rf!(root) end)
    %{artifact: artifact, digest: sha(JSON.encode!(manifest)), capabilities: capabilities}
  end

  for {mode, expected_actions} <- [
        {"bad_open", ["open"]},
        {"bad_append", ["open", "append"]}
      ] do
    test "#{mode} retains every real receipt and never publishes", ctx do
      {run, paths} = open(ctx, unquote(mode))
      source = source(String.duplicate("é", 4500))

      result =
        Evaluation.invoke(run, "ingest", %{
          "store" => "notes",
          "source" => source,
          "expected_revision" => 0
        })

      unless match?({:error, :invalid_draft_continuation, _}, result),
        do: diagnose_fault(result, paths, unquote(mode))

      assert {:error, :invalid_draft_continuation, next} = result

      assert actions(paths.log) == unquote(expected_actions)
      refute next.unsettled
      assert length(next.receipts) == length(unquote(expected_actions))

      assert Enum.all?(
               next.receipts,
               &(is_binary(&1["invocation_id"]) and is_binary(&1["result_sha256"]))
             )

      assert {:ok, snapshot} = Evaluation.snapshot(next)
      assert snapshot["accounting"]["request_count"] == 0

      assert {:ok, inspected, latest} =
               Evaluation.invoke(next, "inspect", %{
                 "store" => "notes",
                 "source_id" => source["source_id"]
               })

      assert inspected["status"] == "ok"
      assert actions(paths.log) == unquote(expected_actions) ++ ["inspect"]
      assert {:ok, %{"cleanup" => "confirmed"}} = Evaluation.close(latest)
    end
  end

  test "timeout before the command handler starts records cancellation without executing the action",
       ctx do
    {run, paths} = open(ctx, "slow_start")

    assert {:error, {:command_failed, "failed"}, next} =
             Evaluation.invoke(run, "ingest", %{
               "store" => "notes",
               "source" => source("fixture"),
               "expected_revision" => 0
             })

    [receipt] = next.receipts
    assert receipt["outcome"] =~ ":timeout"
    assert receipt["outcome"] =~ ":done"
    assert receipt["elapsed_ms"] >= 1000
    refute next.unsettled
    refute File.exists?(paths.log)

    assert {:ok, _, latest} =
             Evaluation.invoke(%{next | timeout_ms: 4000}, "inspect", %{
               "store" => "notes",
               "source_id" => "fixture:source"
             })

    assert actions(paths.log) == ["inspect"]
    assert {:ok, %{"cleanup" => "confirmed"}} = Evaluation.close(latest)
  end

  test "confirmed timeout after the command handler starts keeps its receipt and allows a later read",
       ctx do
    {run, paths} = open(ctx, "hang")
    run = %{run | timeout_ms: 4000}

    invocation =
      Task.async(fn ->
        Evaluation.invoke(run, "ingest", %{
          "store" => "notes",
          "source" => source("fixture"),
          "expected_revision" => 0
        })
      end)

    await(fn -> File.exists?(paths.ready) end)
    assert Ipse.Session.info(run.pid).phase == :extension_command
    assert actions(paths.log) == ["put"]
    pid = run.pid
    assert_receive {:ipse, ^pid, {:done, :cancelled}} = completed, 10_000
    send(invocation.pid, completed)

    assert {:error, {:command_failed, "failed"}, next} = Task.await(invocation, 10_000)

    [receipt] = next.receipts
    assert receipt["outcome"] =~ ":timeout"
    assert receipt["outcome"] =~ ":done"
    assert receipt["elapsed_ms"] >= 4000
    refute next.unsettled
    assert is_binary(receipt["invocation_id"])
    assert actions(paths.log) == ["put"]

    assert {:ok, _, latest} =
             Evaluation.invoke(next, "inspect", %{
               "store" => "notes",
               "source_id" => "fixture:source"
             })

    assert {:ok, snapshot} = Evaluation.snapshot(latest)
    assert snapshot["accounting"]["request_count"] == 0
    assert {:ok, %{"cleanup" => "confirmed"}} = Evaluation.close(latest)
    await_worker_exit(paths.ready)
  end

  test "complete-result deadline retains its notification code without error text", ctx do
    {run, paths} = open(ctx, "hang")
    run = %{run | timeout_ms: 10_000}

    invocation =
      Task.async(fn ->
        Evaluation.invoke(run, "ingest", %{
          "store" => "notes",
          "source" => source("fixture"),
          "expected_revision" => 0
        })
      end)

    await(fn -> File.exists?(paths.ready) end)
    state = :sys.get_state(run.pid)
    assert state.extension_output_clock != nil

    # Deliver the real timer message to exercise notification/receipt handling without a 120-second wait.
    send(run.pid, {:extension_output_deadline, state.job_ref})
    pid = run.pid
    assert_receive {:ipse, ^pid, {:error, message}} = notification, 10_000
    assert message == "Complete-result deadline exceeded. Inspect prior actions before retrying."
    send(invocation.pid, notification)
    assert_receive {:ipse, ^pid, {:done, :error}} = completed, 10_000
    send(invocation.pid, completed)

    assert {:error, {:command_failed, "failed"}, next} = Task.await(invocation, 10_000)
    assert [receipt] = next.receipts
    assert receipt["failure_codes"] == ["complete_result_deadline"]
    refute JSON.encode!(receipt) =~ message
    assert receipt["outcome"] == ":error"
    refute receipt["completion_confirmed"]
    assert actions(paths.log) == ["put"]
    refute next.unsettled
    assert {:ok, %{"cleanup" => "confirmed"}} = Evaluation.close(next)
    await_worker_exit(paths.ready)
  end

  test "unrecognized Session errors retain only a generic diagnostic code", ctx do
    {run, paths} = open(ctx, "fail")

    assert {:error, {:command_failed, "failed"}, next} =
             Evaluation.invoke(run, "ingest", %{
               "store" => "notes",
               "source" => source("fixture"),
               "expected_revision" => 0
             })

    assert [receipt] = next.receipts
    assert receipt["failure_codes"] == ["session_error"]
    refute JSON.encode!(receipt) =~ "PRIVATE_CALLBACK_DETAIL"
    assert actions(paths.log) == ["put"]
    assert {:ok, %{"cleanup" => "confirmed"}} = Evaluation.close(next)
  end

  test "Session loss retains intent, poisons further dispatch and cannot claim cleanup", ctx do
    {run, paths} = open(ctx, "hang")

    killer =
      Task.async(fn ->
        await(fn -> File.exists?(paths.ready) end)
        Process.exit(run.pid, :kill)
      end)

    assert {:error, {:command_failed, "failed"}, next} =
             Evaluation.invoke(run, "ingest", %{
               "store" => "notes",
               "source" => source("fixture"),
               "expected_revision" => 0
             })

    true = Task.await(killer)
    assert next.unsettled
    [receipt] = next.receipts
    assert is_binary(receipt["invocation_id"])
    assert receipt["result_sha256"] == nil
    assert receipt["outcome"] =~ "completion_unconfirmed"
    assert {:ok, snapshot} = Evaluation.snapshot(next)
    assert snapshot["phase"] == :unavailable
    assert snapshot["session_id"] == run.session_id
    assert snapshot["accounting"]["request_count"] == 0
    before = File.read!(snapshot["journal_path"])

    assert {:error, :completion_unconfirmed, ^next} =
             Evaluation.invoke(next, "inspect", %{
               "store" => "notes",
               "source_id" => "fixture:source"
             })

    assert File.read!(snapshot["journal_path"]) == before
    assert actions(paths.log) == ["put"]
    assert {:error, %{"cleanup" => "unconfirmed", "snapshot" => saved}} = Evaluation.close(next)
    assert saved["session_id"] == run.session_id
    await_worker_exit(paths.ready)
  end

  test "saved results are fully materialized before receipts expose a domain value", ctx do
    {run, paths} = open(ctx, "large")

    assert {:ok, receipt, next} =
             Evaluation.invoke(run, "inspect", %{
               "store" => "notes",
               "source_id" => "fixture:source"
             })

    assert receipt["completion_confirmed"]
    assert receipt["status"] == "ok"
    assert receipt["materialization_error"] == nil
    assert receipt["delivery"]["kind"] == "saved.result"
    proof = receipt["complete_result"]
    bytes = Base.decode64!(proof["bytes_base64"])
    assert byte_size(bytes) > 16_384
    assert byte_size(bytes) == proof["byte_count"]
    assert sha(bytes) == proof["sha256"]
    assert sha(bytes) == receipt["delivery"]["sha256"]
    assert JSON.decode!(bytes) == receipt["value"]

    assert receipt["value"]["complete_evidence"] == [
             String.duplicate("a", 8192),
             String.duplicate("b", 8192)
           ]

    assert proof["provenance"] == "historical_receipt"

    display = %{
      "delivery" => receipt["delivery"],
      "value" => %{"status" => "ok", "partial" => true}
    }

    forged = put_in(display, ["delivery", "sha256"], String.duplicate("0", 64))
    assert {:error, :complete_result_unavailable} = Evaluation.complete_result(run.pid, forged)

    :sys.replace_state(run.pid, fn state ->
      %{state | extension_result_sources: %Ipse.Extension.ResultSource.Index{}}
    end)

    assert {:error, :complete_result_unavailable} = Evaluation.complete_result(run.pid, display)
    assert actions(paths.log) == ["inspect"]
    assert {:ok, snapshot} = Evaluation.snapshot(next)
    assert snapshot["accounting"]["request_count"] == 0
    assert {:ok, %{"cleanup" => "confirmed"}} = Evaluation.close(next)
  end

  test "a lost saved source retains the completed first receipt as failed without retry", ctx do
    {run, paths} = open(ctx, "large")

    invocation =
      Task.async(fn ->
        Evaluation.invoke(run, "inspect", %{"store" => "notes", "source_id" => "fixture:source"})
      end)

    # Hold the completed notification until the immutable-source read is unavailable.
    pid = run.pid
    assert_receive {:ipse, ^pid, {:done, :ok}} = completed, 10_000

    :sys.replace_state(pid, fn state ->
      %{state | extension_result_sources: %Ipse.Extension.ResultSource.Index{}}
    end)

    send(invocation.pid, completed)

    assert {:error, {:command_failed, "failed"}, next} = Task.await(invocation, 10_000)
    [receipt] = next.receipts
    assert receipt["completion_confirmed"]
    assert receipt["observation_outcome"] == "completed"
    assert receipt["status"] == "failed"
    assert receipt["materialization_error"] == "complete_result_unavailable"
    assert receipt["delivery"]["kind"] == "saved.result"
    assert receipt["complete_result"] == nil
    assert receipt["value"] == nil
    assert actions(paths.log) == ["inspect"]
    assert {:ok, snapshot} = Evaluation.snapshot(next)
    assert snapshot["accounting"]["request_count"] == 0
    assert {:ok, %{"cleanup" => "confirmed"}} = Evaluation.close(next)
  end

  test "unexpected paging diagnostics exclude arguments and unrecognized receipt strings" do
    root = Path.join(System.tmp_dir!(), "ipse-evaluation-diagnostic-" <> Ipse.Usage.id())
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    path = Path.join(root, "actions")
    File.write!(path, "open\nappend\n")

    receipt = %{
      "elapsed_ms" => 1040,
      "completion_confirmed" => false,
      "observation_outcome" => "timeout",
      "status" => "PRIVATE_STATUS",
      "arguments" => %{"secret" => "PRIVATE_ARGUMENT"},
      "value" => "PRIVATE_RESULT"
    }

    result = {:error, "PRIVATE_REASON", %{receipts: [receipt]}}

    output =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        diagnose_fault(result, %{log: path}, "bad_append")
      end)

    refute output =~ "PRIVATE"
    report = JSON.decode!(String.trim(output))
    assert report["actions_reached"] == ["open", "append"]

    assert report["receipts"] == [
             %{
               "elapsed_ms" => 1040,
               "completion_confirmed" => false,
               "observation_outcome" => "timeout",
               "status" => "other"
             }
           ]

    assert report["arguments_captured"] == false and report["result_payloads_retained"] == false
  end

  defp open(ctx, mode) do
    root = Path.join(System.tmp_dir!(), "ipse-evaluation-driver-fault-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    paths = %{log: Path.join(root, "actions"), ready: Path.join(root, "worker-pid")}

    if mode in ~w(bad_open bad_append) and System.get_env("IPSE_TEST_STDIO_PROBE") == "1" do
      roots = [Process.whereis(Ipse.Sessions), Process.whereis(Ipse.Tasks)]
      probe = Ipse.Test.StdioProbe.start(roots, "evaluation-" <> mode)
      on_exit(fn -> Ipse.Test.StdioProbe.stop(probe) end)
    end

    spec = %{
      root: root,
      project: "synthetic",
      variant: "fault",
      artifacts: [
        %{
          instance: "fixture",
          path: ctx.artifact,
          digest: ctx.digest,
          options: %{"mode" => mode, "log" => paths.log, "ready" => paths.ready},
          order: 0,
          trust: %{
            "artifact" => ctx.digest,
            "capabilities" => ctx.capabilities,
            "allow_project" => false,
            "allow_children" => false
          }
        }
      ],
      runtime: %{
        provider: :demo,
        model: "unused",
        compact: false,
        budget: %{"version" => 1, "max_requests" => 1}
      },
      bindings: Map.new(~w(ingest inspect), &{&1, %{"instance" => "fixture", "id" => "source"}}),
      required_verbs: ~w(ingest inspect),
      approval_validator: fn _ -> {:deny, :unexpected_host_request} end,
      timeout_ms: 1000
    }

    assert {:ok, run} = Evaluation.open(spec)

    on_exit(fn ->
      if Process.alive?(run.pid), do: Evaluation.close(run)
      File.rm_rf!(root)
    end)

    {run, paths}
  end

  defp source(text),
    do: %{
      "source_id" => "fixture:source",
      "generation" => 1,
      "title" => "Fixture",
      "text" => text,
      "uri" => "local:fixture",
      "observed_at_ms" => 1,
      "event_at_ms" => nil,
      "expires_at_ms" => nil
    }

  defp diagnose_fault(result, paths, mode) do
    receipts =
      case result do
        {:error, _, %{receipts: receipts}} ->
          Enum.map(
            receipts,
            fn receipt ->
              elapsed = receipt["elapsed_ms"]
              outcome = receipt["observation_outcome"]
              status = receipt["status"]

              %{
                "elapsed_ms" => if(is_integer(elapsed) and elapsed >= 0, do: elapsed),
                "completion_confirmed" => receipt["completion_confirmed"] == true,
                "observation_outcome" =>
                  if(
                    outcome in ~w(completed timeout wait_failed submission_unconfirmed not_completed),
                    do: outcome,
                    else: "other"
                  ),
                "status" =>
                  if(status in ~w(ok draft failed refused partial abstain),
                    do: status,
                    else: "other"
                  )
              }
            end
          )

        _ ->
          []
      end

    actions =
      with {:ok, %{type: :regular, size: size}} when size <= 128 <- File.lstat(paths.log),
           {:ok, bytes} <- File.read(paths.log),
           rows = String.split(bytes, "\n", trim: true),
           true <-
             length(rows) <= 16 and Enum.all?(rows, &(&1 in ~w(open append publish put inspect))) do
        rows
      else
        _ -> "unavailable"
      end

    IO.puts(
      :stderr,
      JSON.encode!(%{
        "synthetic_evaluation_failure" =>
          if(mode in ~w(bad_open bad_append), do: mode, else: "other"),
        "actions_reached" => actions,
        "receipts" => receipts,
        "arguments_captured" => false,
        "result_payloads_retained" => false
      })
    )
  end

  defp actions(path), do: File.read!(path) |> String.split("\n", trim: true)
  defp sha(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp await_worker_exit(path) do
    pid = File.read!(path)
    assert Regex.match?(~r/\A[0-9]+\z/, pid)
    await(fn -> elem(System.cmd("kill", ["-0", pid], stderr_to_stdout: true), 1) != 0 end)
  end

  defp await(predicate, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 5000

    if predicate.() do
      :ok
    else
      assert System.monotonic_time(:millisecond) < deadline
      Process.sleep(10)
      await(predicate, deadline)
    end
  end
end
