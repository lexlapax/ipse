defmodule Ipse.Development.Verification.ModelService do
  @moduledoc false
  alias Ipse.Development.Evaluation.ModelService, as: Service

  def run(fixture, root) do
    %{type: :directory} = File.lstat!(root)
    {:ok, _} = Application.ensure_all_started(:ipse)

    if :os.type() == {:unix, :linux} do
      results = Enum.map(cases(), &verify_case(&1, fixture, Path.join(root, &1)))
      %{"synthetic" => true, "cases" => results}
    else
      config = configuration(fixture, root)
      output = Path.join(root, "unsupported-output")
      result = Service.run(config, output, fn -> raise("unexpected callback") end)
      :not_started = result.work
      false = File.exists?(output)
      %{"synthetic" => true, "unsupported_before_effects" => true}
    end
  end

  def cases do
    ~w(normal existing_output bad_blob source_symlink occupied_port forge forged_only flood traffic_limit bad_tags bad_show bad_thinking initial_resident changed_after gpu_after stall_tags wildcard exit_during_http callback_exception lifetime owner_death nvidia_full nvidia_partial nvidia_cpu nvidia_empty nvidia_malformed context_cpu nvidia_context context_wrong context_missing context_empty)
  end

  def configuration(fixture, root, mode \\ "normal") do
    source = Path.join(root, "source")
    cache = Path.join(source, "models")
    File.mkdir_p!(Path.join(cache, "blobs"))

    config =
      JSON.encode!(%{
        "architecture" => "fixture",
        "os" => "fixture",
        "rootfs" => %{"type" => "layers", "diff_ids" => []},
        "model_format" => "gguf",
        "model_family" => "fixture"
      })

    weights = "synthetic weights, no inference\n"

    descriptor = fn bytes, media ->
      digest = Ipse.JSON.sha256(bytes)
      File.write!(Path.join(cache, "blobs/sha256-" <> digest), bytes)
      %{"mediaType" => media, "digest" => "sha256:" <> digest, "size" => byte_size(bytes)}
    end

    manifest =
      JSON.encode!(%{
        "schemaVersion" => 2,
        "mediaType" => "application/vnd.docker.distribution.manifest.v2+json",
        "config" => descriptor.(config, "application/vnd.docker.container.image.v1+json"),
        "layers" => [descriptor.(weights, "application/vnd.ollama.image.model")]
      })

    model = if mode == "bad_thinking", do: "qwen3.5:9b", else: "fixture-model:latest"
    digest = Ipse.JSON.sha256(manifest)
    relative = "manifests/registry.ollama.ai/library/" <> String.replace(model, ":", "/")
    File.mkdir_p!(Path.dirname(Path.join(cache, relative)))
    File.write!(Path.join(cache, relative), manifest)
    tags = %{"models" => [%{"name" => model, "model" => model, "digest" => digest}]}

    resident = %{
      "models" => [
        %{
          "name" => model,
          "model" => model,
          "digest" => digest,
          "size_vram" => if(mode == "gpu_after", do: 1, else: 0)
        }
      ]
    }

    gpu = String.starts_with?(mode, "nvidia_")

    resident =
      if gpu do
        row = resident["models"] |> hd() |> Map.put("size", 8)

        vram =
          case mode do
            "nvidia_full" -> 8
            name when name in ~w(nvidia_partial nvidia_context) -> 4
            "nvidia_malformed" -> "4"
            _ -> 0
          end

        %{"models" => if(mode == "nvidia_empty", do: [], else: [Map.put(row, "size_vram", vram)])}
      else
        resident
      end

    explicit_context = String.starts_with?(mode, "context_") or mode == "nvidia_context"

    resident =
      if explicit_context do
        rows =
          if mode == "context_empty",
            do: [],
            else:
              Enum.map(resident["models"], fn row ->
                row = Map.put(row, "size", 8)

                if mode == "context_missing",
                  do: row,
                  else:
                    Map.put(
                      row,
                      "context_length",
                      if(mode == "context_wrong", do: 4096, else: 16_384)
                    )
              end)

        %{"models" => rows}
      else
        resident
      end

    changed = put_in(tags, ["models", Access.at(0), "digest"], String.duplicate("0", 64))
    control = Path.join(source, "control.txt")

    File.write!(
      control,
      Enum.join([mode, JSON.encode!(tags), JSON.encode!(resident), JSON.encode!(changed)], "\n") <>
        "\n"
    )

    {:ok, executable} = Ipse.WorkspaceContext.canonical_path(fixture)

    runtime_file = fn path, target, executable? ->
      %{
        "source" => path,
        "path" => target,
        "bytes" => File.stat!(path).size,
        "sha256" => Ipse.JSON.sha256(File.read!(path)),
        "executable" => executable?
      }
    end

    selection = %{
      "version" => 1,
      "origin" => "http://127.0.0.1:#{unused_port()}",
      "models" => %{model => digest},
      "manifests" => %{model => relative},
      "cache_source" => cache,
      "runtime" => %{
        "executable" => "bin/ollama",
        "files" => [
          runtime_file.(executable, "bin/ollama", true),
          runtime_file.(control, "lib/ollama/control.txt", false)
        ]
      },
      "limits" => %{"ready_ms" => 5000, "lifetime_ms" => 20000, "metadata_ms" => 1000},
      "cpu_policy" => "visibility_v1"
    }

    selection =
      if gpu do
        selection
        |> Map.delete("cpu_policy")
        |> Map.merge(%{
          "version" => 2,
          "device_selection" => %{
            "policy" => "nvidia_visible_mixed_v1",
            "uuid" => "GPU-00000000-0000-0000-0000-000000000001"
          }
        })
      else
        selection
      end

    if explicit_context do
      selection
      |> Map.delete("cpu_policy")
      |> Map.merge(%{
        "version" => 3,
        "context_tokens" => 16_384,
        "device_selection" =>
          if(gpu, do: selection["device_selection"], else: %{"policy" => "cpu_only"})
      })
    else
      selection
    end
  end

  def verify_case(name, fixture, root) do
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    config = configuration(fixture, root, name)
    check(Service.validate(config) == :ok, "valid synthetic configuration refused")
    output = Path.join(root, "output")
    counter = :atomics.new(1, [])

    work = fn ->
      :atomics.add_get(counter, 1, 1)
      {:synthetic, :returned}
    end

    {config, socket} = prepare(name, config, output)
    previous_sentinel = System.get_env("IPSE_MODEL_OWNER_INHERITED_TEST")
    System.put_env("IPSE_MODEL_OWNER_INHERITED_TEST", "synthetic-must-not-inherit")

    try do
      result =
        case name do
          "owner_death" ->
            owner_death(config, output)

          "callback_exception" ->
            Service.run(config, output, fn ->
              :atomics.add_get(counter, 1, 1)
              raise "private-fixture-exception"
            end)

          "lifetime" ->
            Service.run(config, output, fn ->
              :atomics.add_get(counter, 1, 1)
              File.write!(Path.join(output, "home/work-started"), "synthetic")
              Process.sleep(:infinity)
            end)

          "exit_during_http" ->
            Service.run(config, output, fn ->
              :atomics.add_get(counter, 1, 1)
              request(config["origin"] <> "/api/hold", 5000)
              Process.sleep(:infinity)
            end)

          _ ->
            Service.run(config, output, work)
        end

      verify_result(name, result, config, output, counter)

      if name == "normal" do
        before = File.read!(Path.join(output, "receipt.json"))
        again = Service.run(config, output, work)

        check(
          again.work == :not_started and again.receipt["status"] == "failed",
          "existing operation was renewed"
        )

        check(:atomics.get(counter, 1) == 1, "existing operation callback was repeated")

        check(
          File.read!(Path.join(output, "receipt.json")) == before,
          "existing receipt was overwritten"
        )
      end

      if socket, do: check(match?({:ok, _}, :inet.sockname(socket)), "unrelated listener closed")

      if socket do
        case :gen_tcp.accept(socket, 10) do
          {:error, :timeout} ->
            :ok

          {:ok, client} ->
            :gen_tcp.close(client)
            raise "metadata contacted unrelated listener before ownership"

          _ ->
            raise "unrelated listener became unavailable"
        end
      end

      summary = %{"case" => name, "synthetic" => true, "status" => "passed"}
      File.write!(Path.join(root, "verification.json"), JSON.encode!(summary))
      summary
    after
      if socket, do: :gen_tcp.close(socket)

      if previous_sentinel,
        do: System.put_env("IPSE_MODEL_OWNER_INHERITED_TEST", previous_sentinel),
        else: System.delete_env("IPSE_MODEL_OWNER_INHERITED_TEST")
    end
  end

  defp prepare("occupied_port", config, _) do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    {Map.put(config, "origin", "http://127.0.0.1:#{port}"), socket}
  end

  defp prepare("existing_output", config, output) do
    File.mkdir!(output)
    File.write!(Path.join(output, "preserve"), "keep")
    {config, nil}
  end

  defp prepare("bad_blob", config, _) do
    [blob | _] = Path.wildcard(Path.join(config["cache_source"], "blobs/*"))
    bytes = File.read!(blob)
    File.write!(blob, String.duplicate("!", byte_size(bytes)))
    {config, nil}
  end

  defp prepare("source_symlink", config, _) do
    control = get_in(config, ["runtime", "files", Access.at(1), "source"])
    File.rename!(control, control <> ".real")
    File.ln_s!(control <> ".real", control)
    {config, nil}
  end

  defp prepare("lifetime", config, _), do: {put_in(config, ["limits", "lifetime_ms"], 6000), nil}
  defp prepare(_, config, _), do: {config, nil}

  defp verify_result("owner_death", :owner_death_confirmed, _, _, _), do: :ok

  defp verify_result(name, %{work: work, receipt: receipt}, config, output, counter) do
    check(is_map(receipt), "missing receipt")
    encoded = JSON.encode!(receipt)

    check(
      not String.contains?(encoded, "private-fixture-exception"),
      "private exception escaped to diagnostics"
    )

    File.write!(Path.join(Path.dirname(output), "receipt.json"), encoded)

    positive? =
      name in ~w(normal forge flood nvidia_full nvidia_partial context_cpu nvidia_context)

    returned? =
      positive? or
        name in ~w(changed_after gpu_after nvidia_cpu nvidia_empty nvidia_malformed context_wrong context_missing context_empty)

    if returned? do
      check(
        work == {:returned, {:synthetic, :returned}},
        "callback result was lost: #{inspect(work)}"
      )

      check(:atomics.get(counter, 1) == 1, "callback count is not exactly one")
    else
      expected = if name in ~w(lifetime exit_during_http callback_exception), do: 1, else: 0
      check(:atomics.get(counter, 1) == expected, "wrong callback admission count")
    end

    check(
      receipt["status"] == if(positive?, do: "ok", else: "failed"),
      "wrong overall status: #{inspect(receipt)}"
    )

    if positive? do
      check(Service.verify_receipt(config, output, receipt) == :ok, "service evidence refused")
    end

    if name in ~w(nvidia_cpu nvidia_empty),
      do: check(receipt["code"] == "gpu_use_not_observed", "GPU absence was not reported")

    if name in ~w(context_wrong context_missing),
      do: check(receipt["code"] == "context_length", "wrong or missing context was not refused")

    if name == "context_empty",
      do:
        check(
          receipt["code"] == "context_not_observed",
          "missing completion evidence was not refused"
        )

    if name == "callback_exception",
      do:
        check(
          match?({:raised, :error, %RuntimeError{}, _}, work),
          "callback exception outcome lost"
        )

    if name == "callback_exception" do
      check(receipt["metadata_requests"] == 3, "metadata continued after callback exception")

      check(
        File.read!(Path.join(output, "home/requests.log")) == "/api/tags\n/api/show\n/api/ps\n",
        "HTTP continued after callback exception"
      )
    end

    if name in ~w(lifetime exit_during_http),
      do: check(match?({:interrupted, _}, work), "interrupted callback outcome lost")

    if name in ~w(existing_output bad_blob source_symlink occupied_port bad_tags bad_show bad_thinking initial_resident stall_tags wildcard forged_only),
      do: check(work == :not_started, "work should not start")

    if name in ~w(occupied_port wildcard forged_only) do
      check(
        receipt["metadata_requests"] == 0 and receipt["listener"] == nil,
        "unowned listener admitted metadata"
      )

      check(
        not File.exists?(Path.join(output, "home/requests.log")),
        "HTTP reached unowned fixture"
      )
    end

    if name == "lifetime",
      do:
        check(
          File.read!(Path.join(output, "home/work-started")) == "synthetic",
          "lifetime callback did not start"
        )

    if name == "exit_during_http",
      do:
        check(
          String.contains?(File.read!(Path.join(output, "home/requests.log")), "/api/hold\n"),
          "exit did not interrupt an actual HTTP request"
        )

    if name == "existing_output",
      do: check(File.read!(Path.join(output, "preserve")) == "keep", "existing output changed")

    if returned? do
      check(
        File.read!(Path.join(output, "home/environment-clean")) == "selected-only\n",
        "private environment fixture did not pass"
      )

      for file <- config["runtime"]["files"] do
        source = File.stat!(file["source"])
        private = Path.join(output, "runtime/" <> file["path"])
        target = File.stat!(private)

        check(
          {source.major_device, source.inode} != {target.major_device, target.inode},
          "runtime inode reused"
        )

        check(target.links == 1, "runtime file has multiple links")
        check(Ipse.JSON.sha256(File.read!(private)) == file["sha256"], "private runtime changed")
      end

      for source <- Path.wildcard(Path.join(config["cache_source"], "**/*")),
          File.regular?(source) do
        private = Path.join([output, "models", Path.relative_to(source, config["cache_source"])])
        original = File.stat!(source)
        copied = File.lstat!(private)

        check(
          copied.type == :regular and copied.links == 1,
          "private cache is not a single regular inode"
        )

        check(
          {original.major_device, original.inode} != {copied.major_device, copied.inode},
          "cache inode reused"
        )

        check(
          File.read!(source) == File.read!(private),
          "private cache closure is incomplete or changed"
        )
      end

      check(receipt["native_cleanup"] == "confirmed", "native cleanup was not confirmed")

      check(
        receipt["inventory_before"] != nil and
          (not positive? or receipt["inventory_after"] != nil),
        "inventory evidence missing"
      )
    end

    if name == "flood" do
      check(receipt["retained_log_payload_bytes"] <= 16_777_216, "log retention exceeded bound")

      check(
        is_integer(receipt["discarded_log_payload_bytes"]) and
          receipt["discarded_log_payload_bytes"] > 0,
        "flood did not exercise discarded log accounting"
      )
    end

    if name == "traffic_limit" do
      check(
        receipt["code"] == "native_traffic_limit" and work == :not_started,
        "native traffic cap did not refuse before work"
      )

      check(
        is_integer(receipt["discarded_log_payload_bytes"]) and
          receipt["discarded_log_payload_bytes"] > 100_000_000,
        "traffic cap was not exercised"
      )
    end

    log = Path.join(output, "daemon-prefix.bin")

    if name in ~w(flood traffic_limit),
      do: check(File.regular?(log), "bounded log artifact missing")

    if File.exists?(log) do
      check(File.stat!(log).size <= 16_777_216, "encoded log file exceeded bound")
      bytes = File.read!(log)
      check(byte_size(bytes) <= 16_777_216, "encoded log file exceeded bound")

      check(
        log_payload(bytes, 0) == receipt["retained_log_payload_bytes"],
        "retained log receipt disagrees with artifact"
      )
    end

    pidfile = Path.join(output, "home/daemon.pid")
    if File.exists?(pidfile), do: await_dead(File.read!(pidfile), 3000)
    :ok
  end

  defp verify_result(_, result, _, _, _),
    do: raise("unexpected service result: #{inspect(result)}")

  defp log_payload(<<>>, count), do: count

  defp log_payload(<<kind, size::32, rest::binary>>, count)
       when kind in [?O, ?S] and size <= 8192 and byte_size(rest) >= size do
    <<_::binary-size(^size), tail::binary>> = rest
    log_payload(tail, count + size)
  end

  defp log_payload(_, _), do: raise("retained log artifact contains malformed frames")

  defp owner_death(config, output) do
    observer = self()

    owner =
      spawn(fn ->
        result =
          Service.run(config, output, fn ->
            {:ok, session} =
              DynamicSupervisor.start_child(
                Ipse.Sessions,
                {Ipse.Session,
                 config: %{
                   provider: :demo,
                   model: "fixture",
                   home: Path.join(output, "session-home")
                 },
                 cwd: output,
                 state_dir: Path.join(output, "sessions"),
                 subscriber: self(),
                 owner: self()}
              )

            send(observer, {:running, self(), session})
            request(config["origin"] <> "/api/hold", 10000)
            Process.sleep(:infinity)
          end)

        send(observer, {:unexpected_final, result})
      end)

    owner_ref = Process.monitor(owner)

    try do
      {worker, session} =
        receive do
          {:running, worker, session} ->
            {worker, session}

          {:unexpected_final, result} ->
            raise("owner callback stopped before barrier: #{inspect(result.work)}")
        after
          10000 -> raise "owner callback did not start"
        end

      try do
        worker_ref = Process.monitor(worker)
        session_ref = Process.monitor(session)

        await(
          fn ->
            case File.read(Path.join(output, "home/requests.log")) do
              {:ok, bytes} -> String.contains?(bytes, "/api/hold\n")
              _ -> false
            end
          end,
          System.monotonic_time(:millisecond) + 3000,
          "HTTP borrower did not reach fixture"
        )

        Process.exit(owner, :kill)
        await_down(owner_ref, owner)
        await_down(worker_ref, worker)
        await_down(session_ref, session)
        await_dead(File.read!(Path.join(output, "home/daemon.pid")), 3000)

        receive do
          {:unexpected_final, _} -> raise "invented final receipt after owner death"
        after
          0 -> :ok
        end

        :owner_death_confirmed
      after
        stop_known(worker)
        stop_known(session)
      end
    after
      stop_known(owner)
    end
  end

  defp stop_known(pid) do
    ref = Process.monitor(pid)
    if Process.alive?(pid), do: Process.exit(pid, :kill)
    await_down(ref, pid)
  end

  defp await_down(ref, pid) do
    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      5000 -> raise "owned BEAM process did not stop"
    end
  end

  defp await_dead(pid, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    await(
      fn ->
        {_, status} = System.cmd("kill", ["-0", String.trim(pid)], stderr_to_stdout: true)
        status != 0
      end,
      deadline,
      "specifically owned daemon did not stop"
    )
  end

  defp await(fun, deadline, message) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline, do: raise(message)
      Process.sleep(10)
      await(fun, deadline, message)
    end
  end

  defp request(url, timeout),
    do: Ipse.HTTPProfile.bounded_request(Finch.build(:get, url), 1024, timeout)

  defp unused_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    :gen_tcp.close(socket)
    port
  end

  defp check(true, _), do: :ok
  defp check(false, message), do: raise(message)
end
