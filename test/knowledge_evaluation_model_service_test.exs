Code.require_file("../examples/knowledge/evaluation_model_service.exs", __DIR__)
Code.require_file("support/model_service_verification.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationModelServiceTest do
  use ExUnit.Case, async: false
  alias IpseKnowledgeExample.EvaluationModelService, as: Service

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-model-service-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    fixture = Path.join(root, "probe")

    {diagnostic, status} =
      System.cmd(
        "rustc",
        [
          "--edition=2021",
          "-D",
          "warnings",
          Path.join(__DIR__, "support/model_service_probe.rs"),
          "-o",
          fixture
        ],
        stderr_to_stdout: true
      )

    assert status == 0, diagnostic
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, fixture: fixture}
  end

  test "closed configuration refuses invalid authority and unbounded inputs", c do
    root = Path.join(c.root, "validation")
    File.mkdir!(root)
    config = ModelServiceVerification.configuration(c.fixture, root)
    assert Service.validate(config) == :ok

    for invalid <- [
          Map.put(config, "extra", true),
          Map.delete(config, "runtime"),
          Map.put(config, "version", 2),
          Map.put(config, "cpu_policy", "ambient"),
          Map.put(config, "origin", "http://127.0.0.1:11434"),
          Map.put(config, "origin", "http://localhost:12456"),
          Map.put(config, "origin", "http://127.0.0.1:12456/path"),
          Map.put(config, "cache_source", "relative"),
          Map.put(config, "models", %{}),
          put_in(config, ["runtime", "executable"], "bin/other"),
          put_in(config, ["runtime", "files", Access.at(0), "path"], "../escape"),
          put_in(config, ["runtime", "files", Access.at(0), "bytes"], 68_719_476_737),
          put_in(config, ["runtime", "files", Access.at(0), "sha256"], "bad"),
          put_in(config, ["limits", "metadata_ms"], 0),
          put_in(config, ["limits", "ready_ms"], 60001),
          put_in(config, ["limits", "lifetime_ms"], 1)
        ] do
      assert {:error, _} = Service.validate(invalid)
    end
  end

  if match?({:unix, :linux}, :os.type()) do
    for name <- ModelServiceVerification.cases() do
      @case_name name
      test "owned synthetic model service: #{name}", c do
        name = @case_name

        assert ModelServiceVerification.verify_case(name, c.fixture, Path.join(c.root, name))[
                 "status"
               ] == "passed"
      end
    end
  else
    test "unsupported owned-listener backend refuses before staging or callback", c do
      root = Path.join(c.root, "unsupported")
      File.mkdir!(root)
      config = ModelServiceVerification.configuration(c.fixture, root)
      output = Path.join(root, "output")
      caller = self()
      result = Service.run(config, output, fn -> send(caller, :unexpected_work) end)
      assert result.work == :not_started
      refute File.exists?(output)
      refute_received :unexpected_work
    end
  end
end
