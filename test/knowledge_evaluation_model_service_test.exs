Code.require_file("../examples/knowledge/evaluation_model_service.exs", __DIR__)
Code.require_file("../dev/verification/model_service.exs", __DIR__)
Code.require_file("../dev/verification/cli.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationModelServiceTest do
  use ExUnit.Case, async: false
  alias IpseKnowledgeExample.EvaluationModelService, as: Service
  alias Ipse.Development.Verification.ModelService, as: ModelServiceVerification

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

  test "the precompiled proof runs after its copied source is removed", c do
    alias Ipse.Development.Verification.{Runtime, Scenarios}
    copied = Path.join(c.root, "owned-proof-source")
    File.mkdir!(copied)
    spec = Scenarios.fetch!("model-service")

    sources =
      for {source, index} <- Enum.with_index(spec.sources) do
        target = Path.join(copied, Integer.to_string(index) <> ".exs")
        File.cp!(source, target)
        target
      end

    output = Path.join(c.root, "source-absent-proof")
    spec = %{spec | sources: sources}

    Runtime.with_runtime(
      spec,
      [sdk: Application.app_dir(:ipse, "ebin"), input: c.fixture, output: output],
      fn runtime ->
        for source <- sources, do: File.rename!(source, source <> ".absent")
        owner = "Ipse.Development.Verification.ModelService"

        expression =
          if :os.type() == {:unix, :linux},
            do:
              "#{owner}.verify_case(\"normal\", #{inspect(c.fixture)}, #{inspect(Path.join(output, "normal"))})",
            else: "#{owner}.run(#{inspect(c.fixture)}, #{inspect(output)})"

        report = Runtime.eval!(runtime, expression)

        if :os.type() == {:unix, :linux} do
          assert report == %{"case" => "normal", "synthetic" => true, "status" => "passed"}
        else
          assert report["unsupported_before_effects"]
        end
      end
    )
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
    test "the environment constructor runs once and receipt retains the launched map", c do
      root = Path.join(c.root, "environment-once")
      File.mkdir!(root)
      config = ModelServiceVerification.configuration(c.fixture, root)
      output = Path.join(root, "output")
      counter = :atomics.new(1, [])
      owner = self()

      constructor = fn home, tmp ->
        assert :atomics.add_get(counter, 1, 1) == 1

        values = %{
          "PATH" => "/usr/bin:/bin",
          "LANG" => "C.UTF-8",
          "HOME" => home,
          "IPSE_HOME" => Path.join(home, ".ipse"),
          "TMPDIR" => tmp
        }

        send(owner, {:selected_environment, values})
        values
      end

      result = Service.run(config, output, fn -> :ready end, constructor)
      assert result.work == {:returned, :ready}
      assert result.receipt["status"] == "ok"
      assert result.receipt["native_cleanup"] == "confirmed"
      assert_receive {:selected_environment, values}
      assert Map.take(result.receipt["environment"], Map.keys(values)) == values
      assert File.read!(Path.join(output, "home/environment-path")) == values["PATH"]
      assert :atomics.get(counter, 1) == 1
      assert JSON.decode!(File.read!(Path.join(output, "receipt.json"))) == result.receipt
    end

    test "environment constructor failures remain inside the owned lifetime", c do
      for mode <- [:raise, :throw, :block, :invalid] do
        root = Path.join(c.root, "environment-" <> Atom.to_string(mode))
        File.mkdir!(root)
        config = ModelServiceVerification.configuration(c.fixture, root)

        config =
          put_in(config, ["limits"], %{
            "ready_ms" => 1000,
            "lifetime_ms" => 1000,
            "metadata_ms" => 500
          })

        output = Path.join(root, "output")
        owner = self()

        constructor = fn _, _ ->
          send(owner, {:constructor_entered, mode, self()})

          case mode do
            :raise -> raise "synthetic constructor failure"
            :throw -> throw(:synthetic_constructor_failure)
            :block -> Process.sleep(:infinity)
            :invalid -> %{"CUDA_VISIBLE_DEVICES" => "0"}
          end
        end

        started = System.monotonic_time(:millisecond)
        result = Service.run(config, output, fn -> send(owner, :must_not_run) end, constructor)
        assert System.monotonic_time(:millisecond) - started < 4000
        assert_receive {:constructor_entered, ^mode, worker}
        refute Process.alive?(worker)
        refute_received :must_not_run
        assert result.work == :not_started
        assert result.receipt["status"] == "failed"
        assert result.receipt["native_cleanup"] == "not_started"
        assert result.receipt["environment"] == nil
        refute File.exists?(Path.join(output, "home/daemon.pid"))
        assert JSON.decode!(File.read!(Path.join(output, "receipt.json"))) == result.receipt

        assert result.receipt["staging_cleanup"] ==
                 if(mode == :block, do: "unconfirmed", else: "confirmed")
      end
    end

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
