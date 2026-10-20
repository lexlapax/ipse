defmodule Ipse.Extensions.ConformanceTest do
  use ExUnit.Case, async: false
  alias Ipse.Extensions.{Conformance, Config, Store}

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-conformance-artifact-#{Ipse.Usage.id()}")
    File.mkdir_p!(Path.join(root, "artifact/ebin"))
    marker = Path.join(root, "loaded")
    module = "Independent.Conformance#{System.unique_integer([:positive])}"

    capabilities =
      ~w(invoke.tool invoke.command invoke.service host.actions host.state.read host.state.write host.question host.context)

    descriptor = %{
      "id" => "exercise",
      "description" => "Synthetic SDK exercise",
      "arguments_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["mode"],
        "properties" => %{"mode" => %{"type" => "string"}, "text" => %{"type" => "string"}}
      },
      "result_schema" => %{"type" => "object"}
    }

    exports = %{
      "version" => 1,
      "tools" => [descriptor],
      "commands" => [descriptor],
      "services" => [descriptor]
    }

    code = """
    defmodule #{module} do
      @behaviour Ipse.Extension
      @on_load :loaded
      def loaded, do: (File.write!(#{inspect(marker)}, "loaded"); :ok)
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(capabilities)}, "exports" => #{inspect(exports)}}
      def init(options), do: {:ok, options}
      def handle(stage, payload, state) when stage in ~w(invoke.tool invoke.command invoke.service) do
        arguments = payload["arguments"]
        case arguments["mode"] do
          "echo" -> result(%{"echo" => arguments["text"], "secret" => state["secret"]}, state)
          "write" -> write(arguments["text"], state)
          "recall" -> call(%{"op" => "state.get", "scope" => "project", "key" => "note"}, Map.put(state, "phase", "recall"))
          "question" -> call(%{"op" => "operator.question", "arguments" => %{"questions" => [
            %{"id" => "choice", "prompt" => "Choose a synthetic option", "kind" => "single",
              "options" => [%{"id" => "yes", "label" => "Yes"}, %{"id" => "no", "label" => "No"}]}]},
            "checkpoint" => %{"text" => arguments["text"]}}, state)
          "hang" -> Process.sleep(:infinity)
          "bad" -> {:ok, %{"not" => "a result"}, state}
        end
      end
      def handle("host.actions", %{"outcome" => %{"status" => "answered"}} = payload, state), do: write(payload["checkpoint"]["text"], state)
      def handle("host.actions", payload, %{"phase" => "recall"} = state) do
        text = get_in(payload, ["outcome", "value", "record", "value", "text"])
        if is_binary(text) do
          call(%{"op" => "context.publish", "items" => [%{"id" => "note", "version" => "r1", "text" => text, "priority" => 0,
            "source" => %{"kind" => "receipt", "operation_id" => payload["operation_id"], "path" => ["record", "value", "text"]}}]}, Map.delete(state, "phase"))
        else
          result(%{"status" => "missing"}, state)
        end
      end
      def handle("host.actions", payload, state), do: result(%{"status" => payload["outcome"]["status"]}, state)
      defp write(text, state), do: call(%{"op" => "state.put", "scope" => "project", "key" => "note", "expected_revision" => 0, "value" => %{"text" => text}}, state)
      defp call(request, state), do: {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request}, state}
      defp result(value, state), do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => value}, state}
    end
    """

    file = Path.join(root, "fixture.ex")
    File.write!(file, code)

    {output, status} =
      System.cmd(
        System.find_executable("elixirc"),
        ["-pa", Application.app_dir(:ipse, "ebin"), "-o", Path.join(root, "artifact/ebin"), file],
        stderr_to_stdout: true
      )

    assert status == 0, output
    File.rm(marker)
    File.write!(Path.join(root, "artifact/LICENSE"), "MIT synthetic fixture")

    manifest = %{
      "format" => 1,
      "id" => "fixture/conformance",
      "version" => "0.1.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => module,
      "license_file" => "LICENSE",
      "capabilities" => capabilities,
      "exports" => exports,
      "options_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["secret"],
        "properties" => %{"secret" => %{"type" => "string"}}
      },
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      },
      "files" =>
        Enum.map(["LICENSE", "ebin/Elixir.#{module}.beam"], fn path ->
          bytes = File.read!(Path.join(root, "artifact/" <> path))
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
        end)
    }

    File.write!(Path.join(root, "artifact/extension.json"), Jason.encode!(manifest))
    on_exit(fn -> File.rm_rf!(root) end)
    %{artifact: Path.join(root, "artifact"), marker: marker, capabilities: capabilities}
  end

  setup c do
    root = Path.join(System.tmp_dir!(), "ipse-conformance-test-#{Ipse.Usage.id()}")
    home = Path.join(root, "operator")
    {:ok, installed} = Store.import(c.artifact, Path.join(home, "extensions/artifacts"))

    data = %{
      "extensions" => [
        %{
          "instance" => "candidate",
          "artifact" => installed.digest,
          "enabled" => true,
          "options" => %{"secret" => "synthetic-private-option"},
          "order" => 0,
          "lifetime" => "session"
        }
      ],
      "extension_trust" => [
        %{
          "artifact" => installed.digest,
          "capabilities" => c.capabilities,
          "allow_project" => false,
          "allow_children" => false
        }
      ]
    }

    {:ok, catalog} =
      Config.resolve([%{scope: "operator", path: "/fixture/operator.json", data: data}], [])

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, home: home, catalog: catalog, data: data}
  end

  defp fixture(cases, extras \\ %{}), do: Map.merge(%{"version" => 1, "cases" => cases}, extras)

  defp scenario(id, kind, mode, expect),
    do: %{
      "id" => id,
      "kind" => kind,
      "name" => "ext__candidate__exercise",
      "arguments" => %{"mode" => mode, "text" => "synthetic-private-value"},
      "expect" => expect
    }

  test "fixture data grants no trust or new capability and input reads are bounded", c do
    valid = fixture([scenario("echo", "command", "echo", %{"status" => "ok"})])

    assert Conformance.validate(Map.put(valid, "extension_trust", [])) ==
             {:error, :invalid_conformance_fixture}

    assert Conformance.validate(Map.put(valid, "files", %{"../escape" => "no"})) ==
             {:error, :invalid_conformance_fixture}

    File.mkdir_p!(c.root)
    path = Path.join(c.root, "large.json")
    File.write!(path, String.duplicate("x", 16_385))
    assert {:error, :invalid_conformance_fixture} = Conformance.read(path)
    denied = Map.put(c.catalog, "trust", [])
    assert {:ok, report} = Conformance.run(denied, c.home, valid)
    refute report["passed"]
    assert hd(report["cases"])["status"] == "refused"
  end

  test "commands and standalone services reuse schemas without exposing private values", c do
    value = %{"echo" => "synthetic-private-value", "secret" => "synthetic-private-option"}

    cases =
      for kind <- ~w(command service),
          do: scenario(kind, kind, "echo", %{"status" => "ok", "value" => value, "requests" => 0})

    assert {:ok, report} = Conformance.run(c.catalog, c.home, fixture(cases))
    assert report["passed"]
    refute Jason.encode!(report) =~ "synthetic-private"
    assert Enum.all?(report["cases"], & &1["journal_valid"])
  end

  test "tool execution retains headless denial without loading the artifact", c do
    File.rm(c.marker)

    case_data =
      scenario("denied", "tool", "echo", %{
        "status" => "ok",
        "requests" => 2,
        "records" => %{"extension_invocation_intent" => 0}
      })

    assert {:ok, report} = Conformance.run(c.catalog, c.home, fixture([case_data]))
    assert report["passed"]
    refute File.exists?(c.marker)
  end

  test "approved synthetic state persists between cases and recall reaches the next model request",
       c do
    cases = [
      scenario("write", "command", "write", %{"status" => "ok", "action_statuses" => ["ok"]}),
      scenario("recall", "tool", "recall", %{
        "status" => "ok",
        "requests" => 2,
        "context_contains" => "synthetic-private-value",
        "action_statuses" => ["ok", "ok"]
      })
    ]

    assert {:ok, report} =
             Conformance.run(c.catalog, c.home, fixture(cases), yes: true, keep: true)

    assert report["passed"]
    assert File.dir?(report["directory"])
    on_exit(fn -> File.rm_rf!(report["directory"]) end)
    refute File.exists?(Path.join(c.home, "extensions/state"))
    assert Bitwise.band(File.stat!(report["directory"]).mode, 0o077) == 0
  end

  test "explicit synthetic question answers never approve a later write", c do
    case_data =
      scenario("question", "command", "question", %{
        "status" => "ok",
        "action_statuses" => ["answered", "denied"]
      })
      |> Map.put("answers", [%{"choice" => "yes"}])

    assert {:ok, report} = Conformance.run(c.catalog, c.home, fixture([case_data]))
    assert report["passed"]
  end

  test "missing answers pause without a recommendation and invalid arguments refuse before code",
       c do
    question = scenario("question", "command", "question", %{"status" => "question"})

    invalid =
      scenario("invalid", "service", "echo", %{"status" => "refused", "requests" => 0})
      |> Map.put("arguments", %{"unexpected" => true})

    assert {:ok, report} = Conformance.run(c.catalog, c.home, fixture([question, invalid]))
    assert report["passed"]
  end

  test "compiled built-ins use the same checker and literal scratch placeholders", c do
    data = %{
      "extensions" => [
        %{
          "instance" => "annotation",
          "artifact" => "builtin:prompt-annotation:1",
          "enabled" => true,
          "options" => %{"text" => "placeholder"},
          "order" => 0,
          "lifetime" => "session"
        }
      ],
      "extension_trust" => [
        %{
          "artifact" => "builtin:prompt-annotation:1",
          "capabilities" => ["transform.prompt"],
          "allow_project" => false,
          "allow_children" => false
        }
      ]
    }

    {:ok, catalog} =
      Config.resolve([%{scope: "operator", path: "/fixture/builtin.json", data: data}], [])

    input =
      fixture(
        [
          %{
            "id" => "prompt",
            "kind" => "prompt",
            "text" => "synthetic-private-prompt",
            "expect" => %{
              "status" => "ok",
              "final" => "Conformance fixture completed.",
              "requests" => 1,
              "records" => %{"extension_transform_result" => 1},
              "user_contains" => "synthetic-private-annotation",
              "files" => %{"path.txt" => "{{workspace}}"}
            }
          }
        ],
        %{
          "options" => %{"annotation" => %{"text" => "synthetic-private-annotation"}},
          "files" => %{"path.txt" => "{{workspace}}"}
        }
      )

    assert {:ok, report} = Conformance.run(catalog, c.home, input)
    assert report["passed"]
    refute Jason.encode!(report) =~ "synthetic-private"
  end

  test "cancellation and assertion failures produce bounded honest reports", c do
    cancelled =
      scenario("cancel", "command", "hang", %{"status" => "cancelled"})
      |> Map.put("cancel_after_ms", 100)

    wrong =
      scenario("assertion", "command", "echo", %{"status" => "ok", "value" => %{"wrong" => true}})

    assert {:ok, report} = Conformance.run(c.catalog, c.home, fixture([cancelled, wrong]))
    refute report["passed"]
    [cancel, assertion] = report["cases"]
    assert cancel["passed"]
    assert assertion["status"] == "ok"
    refute assertion["checks"]["value"]
    refute Jason.encode!(report) =~ "synthetic-private"
  end

  test "the CLI needs no provider credentials and rejects live-request or replay options", c do
    previous = System.get_env("IPSE_HOME")
    System.put_env("IPSE_HOME", c.home)

    on_exit(fn ->
      if previous, do: System.put_env("IPSE_HOME", previous), else: System.delete_env("IPSE_HOME")
    end)

    file = Path.join(c.root, "operator.json")
    fixture_file = Path.join(c.root, "fixture.json")
    File.write!(file, Jason.encode!(Map.put(c.data, "version", 1)))

    File.write!(
      fixture_file,
      Jason.encode!(
        fixture([scenario("echo", "service", "echo", %{"status" => "ok", "requests" => 0})])
      )
    )

    args = [
      "extension",
      "check",
      "--config",
      file,
      "--fixture",
      fixture_file,
      "--no-project-config"
    ]

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        ExUnit.CaptureIO.capture_io(:stderr, fn -> assert Ipse.CLI.run(args) == 0 end)
      end)

    assert Jason.decode!(output)["passed"]
    refute output =~ "synthetic-private"

    traced =
      ExUnit.CaptureIO.capture_io(fn ->
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          assert Ipse.CLI.run(args ++ ["--developer-trace", "--trace-events", "1"]) == 0
        end)
      end)

    assert [%{"developer_trace" => %{"captured" => 1, "cleanup_confirmed" => true}}] =
             Jason.decode!(traced)["cases"]

    refute traced =~ "synthetic-private"

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      assert Ipse.CLI.run(args ++ ["--provider", "openai"]) == 1
      assert Ipse.CLI.run(args ++ ["--resume", Ipse.Usage.id()]) == 1
      assert Ipse.CLI.run(["config", "--fixture", fixture_file]) == 1
      assert Ipse.CLI.run(["demo", "--developer-trace"]) == 1
      assert Ipse.CLI.run(args ++ ["--trace-ms", "10"]) == 1
      assert Ipse.CLI.run(args ++ ["--developer-trace", "--trace-events", "129"]) == 1
    end)
  end

  test "trace policy stays outside fixture authority and cancellation cleans capture", c do
    cancelled =
      scenario("cancel-traced", "command", "hang", %{"status" => "cancelled"})
      |> Map.put("cancel_after_ms", 100)

    input = fixture([cancelled])

    assert {:error, :invalid_conformance_fixture} =
             Conformance.validate(Map.put(input, "developer_trace", true))

    assert {:error, :invalid_conformance_configuration} =
             Conformance.run(c.catalog, c.home, input, trace_ms: 10)

    assert {:ok, report} =
             Conformance.run(c.catalog, c.home, input, developer_trace: true, trace_ms: 5000)

    assert report["passed"]
    assert [%{"developer_trace" => trace}] = report["cases"]
    assert trace["cleanup_confirmed"]
    assert trace["captured"] in 1..32
  end

  test "an unexpected failure prevents later effectful cases", c do
    cases = [
      scenario("fail", "command", "echo", %{"status" => "ok", "value" => %{"wrong" => true}}),
      scenario("write", "command", "write", %{"status" => "ok"})
    ]

    assert {:ok, report} =
             Conformance.run(c.catalog, c.home, fixture(cases), yes: true, keep: true)

    on_exit(fn -> File.rm_rf!(report["directory"]) end)
    refute report["passed"]
    assert report["stopped_early"]
    assert report["case_count"] == 1 and report["declared_cases"] == 2
    refute File.exists?(Path.join(report["directory"], "home/extensions/state"))
  end
end
