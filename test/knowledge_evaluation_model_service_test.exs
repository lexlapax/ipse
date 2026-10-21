Code.require_file("../dev/evaluation/model_service.exs", __DIR__)
Code.require_file("../dev/verification/model_service.exs", __DIR__)
Code.require_file("../dev/verification/cli.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationModelServiceTest do
  use ExUnit.Case, async: false
  alias Ipse.Development.Evaluation.ModelService, as: Service
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
          Path.join(__DIR__, "../dev/fixtures/model_service_probe.rs"),
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

  test "GPU selection is explicit, closed and uses one complete physical UUID", c do
    root = Path.join(c.root, "gpu-selection")
    File.mkdir!(root)
    config = ModelServiceVerification.configuration(c.fixture, root, "nvidia_partial")
    assert Service.validate(config) == :ok
    assert Service.device_policy(config) == {:ok, "nvidia_visible_mixed_v1"}

    for invalid <-
          [
            Map.put(config, "cpu_policy", "visibility_v1"),
            Map.put(config, "version", 1),
            Map.delete(config, "device_selection"),
            put_in(config, ["device_selection", "policy"], "gpu_only"),
            put_in(config, ["device_selection", "extra"], true)
          ] ++
            for(
              uuid <- [
                nil,
                0,
                "0",
                "-1",
                "GPU-00000000",
                "MIG-GPU-00000000",
                "GPU-00000000-0000-0000-0000-00000000000A",
                "GPU-00000000-0000-0000-0000-000000000001,0",
                ["GPU-00000000-0000-0000-0000-000000000001"]
              ],
              do: put_in(config, ["device_selection", "uuid"], uuid)
            ) do
      assert {:error, :configuration} = Service.validate(invalid)
      assert {:error, :configuration} = Service.device_policy(invalid)
    end
  end

  test "saved GPU evidence rechecks frozen visibility and observed placement", c do
    root = Path.join(c.root, "gpu-evidence")
    File.mkdir!(root)
    config = ModelServiceVerification.configuration(c.fixture, root, "nvidia_partial")
    output = Path.join(root, "output")
    File.mkdir!(output)
    started = Path.join(output, "started.json")

    bytes =
      JSON.encode!(%{
        "version" => 1,
        "configuration_sha256" => Ipse.JSON.sha256(JSON.encode!(config))
      })

    File.write!(started, bytes)
    [{model, digest}] = Map.to_list(config["models"])

    inventory = %{
      "models" => [%{"name" => model, "digest" => digest, "capabilities" => ["completion"]}],
      "resident" => [],
      "placement_history_proven" => false
    }

    row = %{"name" => model, "digest" => digest, "size" => 8, "size_vram" => 4}

    environment = %{
      "PATH" => Path.join(output, "runtime/bin") <> ":/usr/bin:/bin",
      "LANG" => "C.UTF-8",
      "HOME" => Path.join(output, "home"),
      "TMPDIR" => Path.join(output, "tmp"),
      "OLLAMA_MODELS" => Path.join(output, "models"),
      "OLLAMA_HOST" => config["origin"],
      "LD_LIBRARY_PATH" => Path.join(output, "runtime/lib/ollama"),
      "OLLAMA_NO_CLOUD" => "1",
      "CUDA_VISIBLE_DEVICES" => config["device_selection"]["uuid"],
      "ROCR_VISIBLE_DEVICES" => "-1",
      "OLLAMA_VULKAN" => "0",
      "GGML_VK_VISIBLE_DEVICES" => "-1",
      "OLLAMA_NUM_PARALLEL" => "1",
      "OLLAMA_MAX_LOADED_MODELS" => "1",
      "OLLAMA_KEEP_ALIVE" => "-1"
    }

    receipt = %{
      "version" => 2,
      "status" => "ok",
      "code" => nil,
      "work_status" => "returned",
      "service_status" => "admitted",
      "native_cleanup" => "confirmed",
      "staging_cleanup" => "confirmed",
      "evidence" => output,
      "environment" => environment,
      "inventory_before" => inventory,
      "inventory_after" => Map.put(inventory, "resident", [row])
    }

    before = File.read!(started)
    assert Service.verify_receipt(config, output, receipt) == :ok

    malformed_rows = [
      [],
      [Map.put(row, "size_vram", 0)],
      [Map.put(row, "size_vram", 4.0)],
      [Map.put(row, "size_vram", "4")],
      [Map.put(row, "size_vram", -1)],
      [Map.put(row, "size_vram", 9)],
      [Map.delete(row, "size")],
      [Map.put(row, "size", 8.0)],
      [Map.put(row, "size", 0)],
      [Map.put(row, "size", 9_007_199_254_740_992)],
      [Map.put(row, "digest", String.duplicate("0", 64))],
      [Map.put(row, "name", "unknown:latest")],
      [row, row],
      [Map.put(row, "extra", true)]
    ]

    for rows <- malformed_rows do
      changed = put_in(receipt, ["inventory_after", "resident"], rows)
      assert {:error, :service_evidence} = Service.verify_receipt(config, output, changed)
    end

    [model_row] = inventory["models"]

    malformed_models =
      [Map.delete(model_row, "capabilities"), Map.put(model_row, "extra", true)] ++
        for caps <- [
              nil,
              [],
              123,
              ["tools"],
              ["completion", "completion"],
              [String.duplicate("x", 65)]
            ],
            do: Map.put(model_row, "capabilities", caps)

    for field <- ~w(inventory_before inventory_after), model_row <- malformed_models do
      changed = put_in(receipt, [field, "models"], [model_row])
      assert {:error, :service_evidence} = Service.verify_receipt(config, output, changed)
    end

    for changed <- [
          put_in(receipt, ["environment", "CUDA_VISIBLE_DEVICES"], "-1"),
          put_in(
            receipt,
            ["environment", "CUDA_VISIBLE_DEVICES"],
            "GPU-00000000-0000-0000-0000-000000000002"
          ),
          put_in(receipt, ["environment", "HTTP_PROXY"], "http://127.0.0.1:9"),
          put_in(receipt, ["environment", "PATH"], "/unselected/bin"),
          put_in(receipt, ["inventory_before", "resident"], [row]),
          put_in(receipt, ["inventory_after", "placement_history_proven"], true),
          put_in(
            receipt,
            ["inventory_before", "models", Access.at(0), "digest"],
            String.duplicate("0", 64)
          ),
          Map.put(receipt, "version", 1),
          Map.put(receipt, "evidence", root),
          Map.put(receipt, "native_cleanup", "unconfirmed")
        ] do
      assert {:error, :service_evidence} = Service.verify_receipt(config, output, changed)
    end

    constructor = fn home, tmp ->
      %{
        "PATH" => "/verified/bin",
        "LANG" => "C.UTF-8",
        "HOME" => home,
        "IPSE_HOME" => Path.join(home, ".ipse"),
        "TMPDIR" => tmp
      }
    end

    changed =
      receipt
      |> put_in(["environment", "PATH"], "/verified/bin")
      |> put_in(["environment", "IPSE_HOME"], Path.join(output, "home/.ipse"))

    assert Service.verify_receipt(config, output, changed, constructor) == :ok
    assert File.read!(started) == before

    File.write!(
      started,
      JSON.encode!(%{"version" => 1, "configuration_sha256" => String.duplicate("0", 64)})
    )

    assert {:error, :service_evidence} = Service.verify_receipt(config, output, receipt)
    File.write!(started, bytes)

    qwen =
      config
      |> Map.put("models", %{"qwen3.5:9b" => digest})
      |> Map.put("manifests", %{"qwen3.5:9b" => "manifests/registry.ollama.ai/library/qwen3.5/9b"})

    File.write!(
      started,
      JSON.encode!(%{
        "version" => 1,
        "configuration_sha256" => Ipse.JSON.sha256(JSON.encode!(qwen))
      })
    )

    qwen_row = %{
      "name" => "qwen3.5:9b",
      "digest" => digest,
      "capabilities" => ["completion", "tools"]
    }

    qwen_receipt =
      receipt
      |> put_in(["inventory_before", "models"], [qwen_row])
      |> put_in(["inventory_after", "models"], [qwen_row])
      |> put_in(["inventory_after", "resident", Access.at(0), "name"], "qwen3.5:9b")

    assert Service.verify_receipt(qwen, output, qwen_receipt) == :ok

    for caps <- [nil, [], ["embedding"], ["completion"], 123] do
      changed =
        put_in(qwen_receipt, ["inventory_before", "models", Access.at(0), "capabilities"], caps)

      assert {:error, :service_evidence} = Service.verify_receipt(qwen, output, changed)
    end

    embedding = "fixture-embedding:latest"
    embedding_digest = String.duplicate("e", 64)

    config =
      config
      |> put_in(["models", embedding], embedding_digest)
      |> put_in(
        ["manifests", embedding],
        "manifests/registry.ollama.ai/library/fixture-embedding/latest"
      )

    File.write!(
      started,
      JSON.encode!(%{
        "version" => 1,
        "configuration_sha256" => Ipse.JSON.sha256(JSON.encode!(config))
      })
    )

    embedding_model = %{
      "name" => embedding,
      "digest" => embedding_digest,
      "capabilities" => ["embedding"]
    }

    receipt =
      receipt
      |> put_in(["environment", "OLLAMA_MAX_LOADED_MODELS"], "2")
      |> update_in(
        ["inventory_before", "models"],
        &Enum.sort_by(&1 ++ [embedding_model], fn row -> row["name"] end)
      )
      |> update_in(
        ["inventory_after", "models"],
        &Enum.sort_by(&1 ++ [embedding_model], fn row -> row["name"] end)
      )

    embedding_row = %{
      "name" => embedding,
      "digest" => embedding_digest,
      "size" => 8,
      "size_vram" => 8
    }

    masked_cpu =
      put_in(receipt, ["inventory_after", "resident"], [
        Map.put(row, "size_vram", 0),
        embedding_row
      ])

    assert {:error, :service_evidence} = Service.verify_receipt(config, output, masked_cpu)
    all_partial = put_in(receipt, ["inventory_after", "resident"], [row, embedding_row])
    assert Service.verify_receipt(config, output, all_partial) == :ok
  end

  if match?({:unix, :linux}, :os.type()) do
    test "the public service proof accepts its complete population and rejects missing or duplicate cases" do
      alias Ipse.Development.Verification.Scenarios
      spec = Scenarios.fetch!("model-service")

      rows =
        for name <- ModelServiceVerification.cases(),
            do: %{"case" => name, "synthetic" => true, "status" => "passed"}

      assert Scenarios.validate!(spec, %{"synthetic" => true, "cases" => rows}, "default") == :ok

      for invalid <- [
            Enum.take(rows, 21),
            tl(rows),
            [hd(rows) | tl(tl(rows))] ++ [hd(rows)],
            List.replace_at(rows, 0, Map.put(hd(rows), "status", "failed"))
          ] do
        assert_raise MatchError, fn ->
          Scenarios.validate!(spec, %{"synthetic" => true, "cases" => invalid}, "default")
        end
      end
    end

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
