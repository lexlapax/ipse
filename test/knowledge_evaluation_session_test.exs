Code.require_file("../examples/knowledge/evaluation_session.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationSessionTest do
  use ExUnit.Case, async: false
  alias IpseKnowledgeExample.EvaluationSession, as: Evaluation

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-evaluation-fault-artifact-" <> Ipse.Usage.id())
    artifact = Path.join(root, "artifact")
    File.mkdir_p!(Path.join(artifact, "ebin"))
    capabilities = ["invoke.command"]

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
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(capabilities)}, "exports" => #{inspect(exports)}}
      def init(options), do: {:ok, options}
      def handle("invoke.command", payload, options) do
        args = payload["arguments"]
        action = args["action"]
        File.write!(options["log"], action <> "\\n", [:append])
        if action == "put" and options["mode"] == "hang" do
          File.write!(options["ready"], System.pid())
          Process.sleep(:infinity)
        end
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
        {:ok, %{"api_version" => 1, "kind" => "result", "value" => value}, options}
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
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => entrypoint,
      "license_file" => "LICENSE",
      "options_schema" => %{
        "type" => "object",
        "required" => ~w(mode log ready),
        "additionalProperties" => false,
        "properties" => %{
          "mode" => %{"type" => "string", "enum" => ~w(bad_open bad_append hang)},
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

      assert {:error, :invalid_draft_continuation, next} =
               Evaluation.invoke(run, "ingest", %{
                 "store" => "notes",
                 "source" => source,
                 "expected_revision" => 0
               })

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

  test "confirmed timeout cancellation keeps its receipt and allows a later read", ctx do
    {run, paths} = open(ctx, "hang")

    assert {:error, {:command_failed, "failed"}, next} =
             Evaluation.invoke(run, "ingest", %{
               "store" => "notes",
               "source" => source("fixture"),
               "expected_revision" => 0
             })

    [receipt] = next.receipts
    assert receipt["outcome"] =~ ":timeout"
    assert receipt["outcome"] =~ ":done"
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

  defp open(ctx, mode) do
    root = Path.join(System.tmp_dir!(), "ipse-evaluation-driver-fault-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    paths = %{log: Path.join(root, "actions"), ready: Path.join(root, "worker-pid")}

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
