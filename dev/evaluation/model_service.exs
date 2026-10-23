defmodule Ipse.Development.Evaluation.ModelService do
  @moduledoc """
  One explicitly configured, fresh local model daemon and complete work callback.

  The caller owns the daemon Port and remains responsive while a guarded Task
  stages private files, checks metadata and invokes the callback once. Returned
  work, service admission and native cleanup are separate outcomes. No execution
  claim, measurement scope, provider fallback or retry is supplied by this module.
  """
  alias Ipse.HTTP
  alias Ipse.Runner
  alias Ipse.Workspace

  @gib 68_719_476_736
  @json 1_048_576
  @traffic 134_217_728
  @logs 16_777_216
  @receipt_limit 4_194_304
  @config_keys ~w(version origin models manifests cache_source runtime limits cpu_policy)
  @gpu_policy "nvidia_visible_mixed_v1"
  @safe_integer 9_007_199_254_740_991
  @meta_keys ~w(device inode nlink bytes mode mtime_seconds mtime_nanoseconds ctime_seconds ctime_nanoseconds)

  @doc "Validate the closed selection without filesystem, process or network IO."
  def validate(config) do
    try do
      _ = device!(config)
      uri = URI.parse(config["origin"] || "")

      demand(
        is_integer(uri.port) and uri.port in 1..65_535 and uri.port != 11_434 and
          config["origin"] == "http://127.0.0.1:#{uri.port}",
        :origin
      )

      demand(absolute?(config["cache_source"]), :cache_source)
      models = config["models"]
      demand(is_map(models) and map_size(models) in 1..8, :models)

      demand(
        Enum.all?(models, fn {name, digest} -> model?(name) and Ipse.JSON.sha256?(digest) end),
        :models
      )

      manifests = config["manifests"]

      demand(
        is_map(manifests) and Enum.sort(Map.keys(manifests)) == Enum.sort(Map.keys(models)),
        :manifests
      )

      demand(
        Enum.all?(manifests, fn {name, path} ->
          relative?(path) and String.starts_with?(path, "manifests/") and
            Enum.take(String.split(path, "/"), -2) == String.split(name, ":")
        end),
        :manifests
      )

      demand(disjoint_files?(Map.values(manifests)), :manifests)
      runtime = config["runtime"]

      demand(
        exact?(runtime, ~w(executable files)) and runtime["executable"] == "bin/ollama",
        :runtime
      )

      files = runtime["files"]
      demand(is_list(files) and length(files) in 1..256, :runtime)

      demand(
        Enum.all?(files, fn file ->
          exact?(file, ~w(source path bytes sha256 executable)) and absolute?(file["source"]) and
            relative?(file["path"]) and
            (String.starts_with?(file["path"], "bin/") or
               String.starts_with?(file["path"], "lib/ollama/")) and
            uint?(file["bytes"], @gib) and Ipse.JSON.sha256?(file["sha256"]) and
            is_boolean(file["executable"]) and
            (not file["executable"] or file["path"] == "bin/ollama" or
               String.starts_with?(file["path"], "lib/ollama/"))
        end),
        :runtime
      )

      demand(
        Enum.count(files, &(&1["path"] == "bin/ollama" and &1["executable"])) == 1 and
          disjoint_files?(Enum.map(files, & &1["path"])) and
          Enum.sum(Enum.map(files, & &1["bytes"])) <= @gib,
        :runtime
      )

      limits = config["limits"]

      demand(
        exact?(limits, ~w(ready_ms lifetime_ms metadata_ms)) and
          positive?(limits["ready_ms"], 60_000) and positive?(limits["lifetime_ms"], 86_400_000) and
          positive?(limits["metadata_ms"], 10_000),
        :limits
      )

      demand(limits["ready_ms"] <= limits["lifetime_ms"], :limits)
      :ok
    rescue
      _ -> {:error, :configuration}
    catch
      {:model_service, code} -> {:error, code}
    end
  end

  @doc "Project a validated service selection into its portable device policy."
  def device_policy(config) do
    with :ok <- validate(config) do
      {:ok, if(device!(config) == :cpu_only, do: "cpu_only", else: @gpu_policy)}
    end
  end

  @doc "Verify selected device and context evidence without contacting a daemon."
  def verify_receipt(config, output, receipt, constructor \\ nil) do
    try do
      :ok = validate(config)

      if config["version"] in [2, 3] do
        demand(
          receipt["version"] === config["version"] and receipt["status"] == "ok" and
            receipt["code"] == nil and receipt["work_status"] == "returned" and
            receipt["service_status"] == "admitted" and
            receipt["native_cleanup"] == "confirmed" and
            receipt["staging_cleanup"] == "confirmed" and receipt["evidence"] == output,
          :service_evidence
        )

        demand(
          read_json(Path.join(output, "started.json")) == %{
            "version" => 1,
            "configuration_sha256" => Ipse.JSON.sha256(JSON.encode!(config))
          },
          :service_evidence
        )

        demand(
          receipt["environment"] == environment(config, paths(output), constructor),
          :service_evidence
        )

        for {field, initial} <- [{"inventory_before", true}, {"inventory_after", false}] do
          inventory = receipt[field]

          demand(
            exact?(inventory, ~w(models resident placement_history_proven)),
            :service_evidence
          )

          demand(inventory["placement_history_proven"] === false, :service_evidence)
          models = inventory["models"]

          demand(
            is_list(models) and length(models) == map_size(config["models"]) and
              Map.new(models, &{&1["name"], &1["digest"]}) == config["models"] and
              Enum.sort_by(Enum.map(models, &model_row!(config, &1)), & &1["name"]) == models,
            :service_evidence
          )

          rows = resident_rows!(config, inventory["resident"], initial, models)
          demand(rows == inventory["resident"], :service_evidence)
        end

        if config["version"] === 3,
          do:
            demand(
              receipt["inventory_before"]["models"] == receipt["inventory_after"]["models"],
              :service_evidence
            )
      end

      :ok
    rescue
      _ -> {:error, :service_evidence}
    catch
      _, _ -> {:error, :service_evidence}
    end
  end

  @doc "Run one fresh owned daemon lifetime; callback terms never enter diagnostics."
  def run(config, output, work), do: run(config, output, work, nil)

  @doc false
  def run(config, output, work, environment) do
    started = now()

    initial = %{
      work: :not_started,
      code: nil,
      stage: :starting,
      staged: nil,
      before: nil,
      after: nil,
      listener: nil,
      port: nil,
      exit_status: nil,
      finished: false,
      buffer: <<>>,
      traffic: 0,
      log_parts: [],
      log_tail: <<>>,
      log_encoded: 0,
      log_bytes: 0,
      discarded: 0,
      metadata_requests: 0,
      native_cleanup: "not_started",
      staging_cleanup: "not_started",
      output_created: false,
      staged_files: [],
      task_down: false,
      work_started: false
    }

    cond do
      validate(config) != :ok ->
        result(initial, :configuration, output, started)

      not absolute?(output) or not is_function(work, 0) or
          not (is_nil(environment) or is_function(environment, 2)) ->
        result(initial, :configuration, output, started)

      :os.type() != {:unix, :linux} ->
        result(initial, :unsupported_platform, output, started)

      true ->
        {:ok, _} = Application.ensure_all_started(:ipse)
        previous = Process.flag(:trap_exit, true)
        owner = self()
        token = make_ref()
        deadline = started + config["limits"]["lifetime_ms"]

        task =
          Task.Supervisor.async_nolink(Ipse.Tasks, fn ->
            guarded_operation(owner, token, config, output, work, deadline, environment)
          end)

        send(task.pid, {token, :start})

        state =
          Map.merge(initial, %{
            task: task,
            token: token,
            deadline: deadline,
            ready_deadline: nil,
            config: config,
            output: output
          })

        try do
          state = receive_loop(state)
          state = quiesce(state)
          state = close_daemon(state)
          persist(result(state, state.code, output, started), state, output)
        after
          Process.flag(:trap_exit, previous)
        end
    end
  end

  defp guarded_operation(owner, token, config, output, work, deadline, constructor) do
    worker = self()

    guard =
      spawn(fn ->
        owner_ref = Process.monitor(owner)
        worker_ref = Process.monitor(worker)
        send(worker, {token, :guard_ready})

        receive do
          {:DOWN, ^owner_ref, :process, _, _} -> Process.exit(worker, :kill)
          {:DOWN, ^worker_ref, :process, _, _} -> :ok
          {^token, :finished} -> :ok
        end
      end)

    Process.flag(:trap_exit, true)

    try do
      receive do
        {^token, :guard_ready} -> :ok
      after
        remaining(deadline) -> fail(:lifetime)
      end

      receive do
        {^token, :start} -> :ok
      after
        remaining(deadline) -> fail(:lifetime)
      end

      staged = stage(config, output, deadline, owner, token)
      staged = Map.put(staged, :environment, environment(config, staged.paths, constructor))
      send(owner, {token, :staged, staged})

      receive do
        {^token, :admitted} -> :ok
      after
        remaining(deadline) -> fail(:lifetime)
      end

      before = inventory(config, true, owner, token, deadline)
      send(owner, {token, :inventory_before, before})
      send(owner, {token, :work_started})

      outcome =
        try do
          {:returned, work.()}
        catch
          kind, reason -> {:raised, kind, reason, __STACKTRACE__}
        end

      send(owner, {token, :work, outcome})

      if match?({:raised, _, _, _}, outcome), do: fail(:callback_raised)

      after_inventory = inventory(config, false, owner, token, deadline)

      if config["version"] === 3,
        do: demand(before["models"] == after_inventory["models"], :model_inventory)

      recheck(staged.files)
      {:ok, after_inventory}
    rescue
      _ -> {:error, :operation_io_or_shape}
    catch
      {:model_service, code} -> {:error, code}
      _, _ -> {:error, :operation_failed}
    after
      send(guard, {token, :finished})
    end
  end

  defp receive_loop(%{code: code} = state) when code != nil, do: state
  defp receive_loop(%{stage: :settled} = state), do: state

  defp receive_loop(state) do
    until =
      if state.ready_deadline, do: min(state.deadline, state.ready_deadline), else: state.deadline

    if now() >= until do
      %{state | code: if(state.ready_deadline, do: :readiness_deadline, else: :lifetime)}
    else
      task_ref = state.task.ref
      token = state.token
      port = state.port

      receive do
        {^token, :output_created} ->
          receive_loop(%{state | output_created: true})

        {^token, :staging_file, evidence} ->
          receive_loop(%{state | staged_files: [evidence | state.staged_files]})

        {^token, :staged, staged} ->
          receive_loop(launch_daemon(%{state | staged: staged, staging_cleanup: "confirmed"}))

        {^token, :inventory_before, metadata} ->
          receive_loop(%{state | before: metadata, stage: :running})

        {^token, :work, outcome} ->
          receive_loop(%{state | work: outcome, stage: :inventory_after})

        {^token, :work_started} ->
          receive_loop(%{state | work_started: true})

        {^token, :metadata_request} ->
          receive_loop(%{state | metadata_requests: state.metadata_requests + 1})

        {^task_ref, {:ok, metadata}} ->
          receive_loop(%{state | after: metadata, stage: :settled})

        {^task_ref, {:error, code}} ->
          %{
            state
            | code: code,
              stage: :settled,
              staging_cleanup:
                if(code == :copy_cleanup_unconfirmed, do: "unconfirmed", else: "confirmed")
          }

        {:DOWN, ^task_ref, :process, _, _} ->
          %{
            state
            | code: :operation_lost,
              task_down: true,
              staging_cleanup: if(state.staged, do: "confirmed", else: "unconfirmed")
          }

        {^port, {:data, bytes}} when is_port(port) ->
          receive_loop(admit_bytes(state, bytes))

        {^port, {:exit_status, status}} when is_port(port) ->
          %{state | code: :service_exited, exit_status: status}

        {:EXIT, ^port, _} when is_port(port) ->
          %{state | code: :service_transport_lost}
      after
        max(until - now(), 0) ->
          %{state | code: if(state.ready_deadline, do: :readiness_deadline, else: :lifetime)}
      end
    end
  end

  defp launch_daemon(state) do
    timeout = state.deadline - now()
    env = state.staged.environment
    port_number = URI.parse(state.config["origin"]).port

    if timeout <= 0 do
      %{state | code: :lifetime}
    else
      case Runner.open_stdio(state.staged.paths.executable, ["serve"], state.output, env, timeout,
             owned_listener: {:ipv4_loopback, port_number}
           ) do
        {:ok, port} ->
          %{
            state
            | port: port,
              native_cleanup: "unconfirmed",
              stage: :awaiting_proof,
              ready_deadline: now() + state.config["limits"]["ready_ms"]
          }

        {:error, {:cleanup_unconfirmed, _}} ->
          %{state | code: :daemon_launch, native_cleanup: "unconfirmed"}

        {:error, _} ->
          %{state | code: :daemon_launch}
      end
    end
  end

  defp admit_bytes(state, bytes) do
    if state.traffic + byte_size(bytes) > @traffic do
      %{state | code: :native_traffic_limit}
    else
      next =
        decode(%{
          state
          | traffic: state.traffic + byte_size(bytes),
            buffer: state.buffer <> bytes
        })

      if next.code == nil and next.stage == :proof_observed do
        send(next.task.pid, {next.token, :admitted})
        %{next | stage: :inventory_before}
      else
        next
      end
    end
  end

  defp decode(%{code: code} = state) when code != nil, do: state
  defp decode(%{buffer: bytes} = state) when byte_size(bytes) < 5, do: state

  defp decode(%{buffer: <<kind, size::32, rest::binary>>} = state) do
    cond do
      kind not in [?O, ?S, ?P, ?X, ?E] or size > 8192 ->
        %{state | code: :native_protocol}

      byte_size(rest) < size ->
        state

      true ->
        <<payload::binary-size(^size), tail::binary>> = rest
        state = %{state | buffer: tail}

        next =
          case kind do
            kind when kind in [?O, ?S] -> log_prefix(state, kind, payload)
            ?P -> proof(state, payload)
            ?E -> %{state | code: :native_error}
            ?X -> %{state | code: :service_exited, finished: true}
          end

        decode(next)
    end
  end

  defp proof(
         %{listener: nil, stage: :awaiting_proof} = state,
         <<1, pid::32, port::16, inode::64>>
       )
       when pid > 0 and inode > 0 do
    if port == URI.parse(state.config["origin"]).port do
      %{
        state
        | listener: %{
            "version" => 1,
            "pid" => pid,
            "port" => port,
            "inode" => Integer.to_string(inode)
          },
          stage: :proof_observed,
          ready_deadline: nil
      }
    else
      %{state | code: :listener_mismatch}
    end
  end

  defp proof(state, _), do: %{state | code: :listener_invalid_or_duplicate}

  defp log_prefix(state, kind, bytes) do
    count = min(byte_size(bytes), max(@logs - state.log_encoded - 5, 0))

    {parts, tail} =
      if count > 0 do
        framed = <<state.log_tail::binary, kind, count::32, binary_part(bytes, 0, count)::binary>>

        if byte_size(framed) >= 65_536 do
          <<chunk::binary-size(65_536), tail::binary>> = framed
          {[chunk | state.log_parts], tail}
        else
          {state.log_parts, framed}
        end
      else
        {state.log_parts, state.log_tail}
      end

    %{
      state
      | log_parts: parts,
        log_tail: tail,
        log_encoded: state.log_encoded + if(count > 0, do: count + 5, else: 0),
        log_bytes: state.log_bytes + count,
        discarded: state.discarded + byte_size(bytes) - count
    }
  end

  defp quiesce(state) do
    if state.stage != :settled and not state.task_down, do: Process.exit(state.task.pid, :kill)
    ref = state.task.ref

    down =
      if state.task_down do
        true
      else
        receive do
          {:DOWN, ^ref, :process, _, _} -> true
        after
          2_000 ->
            Process.exit(state.task.pid, :kill)

            receive do
              {:DOWN, ^ref, :process, _, _} -> true
            after
              2_000 -> false
            end
        end
      end

    Process.demonitor(ref, [:flush])
    state = drain_operation(state)

    work =
      if state.work == :not_started and state.work_started,
        do: {:interrupted, state.code || :operation_lost},
        else: state.work

    cleanup =
      if down and (state.staged != nil or state.stage == :settled) and
           state.code != :copy_cleanup_unconfirmed do
        "confirmed"
      else
        "unconfirmed"
      end

    state = %{
      state
      | work: work,
        task_down: down,
        staging_cleanup: cleanup,
        code: if(down, do: state.code, else: :operation_cleanup_unconfirmed)
    }

    drain_available(state)
  end

  defp drain_operation(state) do
    token = state.token
    ref = state.task.ref

    receive do
      {^token, :output_created} ->
        drain_operation(%{state | output_created: true})

      {^token, :staging_file, evidence} ->
        drain_operation(%{state | staged_files: [evidence | state.staged_files]})

      {^token, :staged, staged} ->
        drain_operation(%{state | staged: staged})

      {^token, :inventory_before, metadata} ->
        drain_operation(%{state | before: metadata})

      {^token, :metadata_request} ->
        drain_operation(%{state | metadata_requests: state.metadata_requests + 1})

      {^token, :work_started} ->
        drain_operation(%{state | work_started: true})

      {^token, :work, outcome} ->
        drain_operation(%{state | work: outcome})

      {^ref, _} ->
        drain_operation(state)
    after
      0 -> state
    end
  end

  defp drain_available(%{port: nil} = state), do: state
  defp drain_available(%{code: code} = state) when code != nil, do: state

  defp drain_available(state) do
    port = state.port

    receive do
      {^port, {:data, bytes}} ->
        drain_available(admit_bytes(state, bytes))

      {^port, {:exit_status, status}} ->
        %{state | exit_status: status, code: :service_exited}

      {:EXIT, ^port, _} ->
        %{state | code: :service_transport_lost}
    after
      0 -> state
    end
  end

  defp close_daemon(%{port: nil} = state), do: state

  defp close_daemon(%{exit_status: status} = state) when is_integer(status),
    do: %{state | native_cleanup: if(status in [0, 1], do: "confirmed", else: "unconfirmed")}

  defp close_daemon(state) do
    mode = if state.finished, do: :completed, else: :cancel
    cleanup = close_port(state.port, mode)

    %{
      state
      | native_cleanup: if(cleanup == :ok, do: "confirmed", else: "unconfirmed"),
        code: state.code || if(cleanup == :ok, do: nil, else: :native_cleanup_unconfirmed)
    }
  end

  defp stage(config, output, deadline, owner, token) do
    demand(canonical(output) == output, :output_path)
    roots = [config["cache_source"] | Enum.map(config["runtime"]["files"], & &1["source"])]

    demand(
      Enum.all?(roots, &(canonical(&1) == &1 and not overlap?(output, &1))),
      :source_overlap_or_alias
    )

    demand(match?({:error, :enoent}, File.lstat(output)), :output_exists)
    File.mkdir!(output)
    File.chmod!(output, 0o700)
    send(owner, {token, :output_created})

    paths = paths(output)

    for path <- [
          paths.runtime,
          Path.join(paths.runtime, "bin"),
          Path.join(paths.runtime, "lib/ollama"),
          paths.home,
          paths.models,
          paths.tmp
        ],
        do: mkdir_private(path)

    write_private(
      Path.join(output, "started.json"),
      JSON.encode!(%{
        "version" => 1,
        "configuration_sha256" => Ipse.JSON.sha256(JSON.encode!(config))
      }) <> "\n"
    )

    {:ok, helper} = Runner.native_helper(output)
    context = %{helper: helper, output: output, deadline: deadline, owner: owner, token: token}

    runtime =
      Enum.map(config["runtime"]["files"], fn file ->
        target = Path.join(paths.runtime, file["path"])

        copy_file(
          context,
          file["source"],
          target,
          file["bytes"],
          file["sha256"],
          file["executable"]
        )
      end)

    manifests =
      Enum.map(Enum.sort(config["models"]), fn {name, digest} ->
        relative = config["manifests"][name]
        source = Path.join(config["cache_source"], relative)
        bytes = source_size(source, @json)
        file = copy_file(context, source, Path.join(paths.models, relative), bytes, digest, false)
        {name, file, decode_manifest(read_json(file.path))}
      end)

    descriptors =
      Enum.flat_map(manifests, fn {_, _, manifest} ->
        [manifest["config"] | manifest["layers"]]
      end)

    blobs =
      Enum.reduce(descriptors, %{}, fn descriptor, acc ->
        digest = descriptor["digest"]

        if Map.has_key?(acc, digest),
          do: demand(acc[digest] == descriptor["size"], :blob_size_conflict)

        Map.put(acc, digest, descriptor["size"])
      end)

    demand(
      map_size(blobs) <= 128 and
        Enum.sum(Map.values(blobs)) +
          Enum.sum(Enum.map(manifests, fn {_, file, _} -> file.bytes end)) <= @gib,
      :cache_limit
    )

    copied_blobs =
      Map.new(Enum.sort(blobs), fn {"sha256:" <> digest = full, bytes} ->
        relative = "blobs/sha256-" <> digest

        {full,
         copy_file(
           context,
           Path.join(config["cache_source"], relative),
           Path.join(paths.models, relative),
           bytes,
           digest,
           false
         )}
      end)

    Enum.each(manifests, fn {_, _, manifest} ->
      validate_model_config(read_json(copied_blobs[manifest["config"]["digest"]].path))
    end)

    checked_blobs =
      for {_, _, manifest} <- manifests, do: copied_blobs[manifest["config"]["digest"]]

    files =
      runtime ++
        Enum.map(manifests, fn {_, file, _} -> file end) ++ Enum.uniq_by(checked_blobs, & &1.path)

    all = runtime ++ Enum.map(manifests, fn {_, file, _} -> file end) ++ Map.values(copied_blobs)
    %{paths: paths, files: files, evidence: Enum.map(all, &file_evidence/1)}
  end

  defp copy_file(context, source, target, bytes, digest, executable) do
    demand(canonical(source) == source, :source_alias)
    mkdir_private(Path.dirname(target))

    port =
      case Runner.open_stdio(
             context.helper,
             ["--copy-regular", source, target, Integer.to_string(bytes)],
             context.output,
             %{},
             remaining(context.deadline)
           ) do
        {:ok, port} -> port
        {:error, {:cleanup_unconfirmed, _}} -> fail(:copy_cleanup_unconfirmed)
        {:error, _} -> fail(:copy_launch)
      end

    outcome =
      try do
        {:ok,
         copy_collect(port, context.deadline, %{buffer: <<>>, stdout: <<>>, bytes: 0, result: nil})}
      catch
        {:model_service, code} -> {:error, code}
        _, _ -> {:error, :copy_protocol}
      end

    cleanup = close_port(port, if(match?({:ok, _}, outcome), do: :completed, else: :cancel))
    demand(cleanup == :ok, :copy_cleanup_unconfirmed)

    terminal =
      case outcome do
        {:ok, terminal} -> terminal
        {:error, code} -> fail(code)
      end

    demand(terminal.result == %{"exit_code" => 0, "timed_out" => false}, :copy_failed)
    {:ok, receipt} = Ipse.JSON.decode_bounded(terminal.stdout, 2048)
    validate_copy_receipt(receipt, bytes)
    mkdir_private(Path.join(context.output, "copies"))

    write_private(
      Path.join([context.output, "copies", Ipse.JSON.sha256(target) <> ".json"]),
      JSON.encode!(%{"destination" => target, "expected_sha256" => digest, "receipt" => receipt}) <>
        "\n"
    )

    demand(hash_file(target, bytes) == digest, :file_hash)
    File.chmod!(target, if(executable, do: 0o500, else: 0o400))
    file = %{path: target, bytes: bytes, sha256: digest, copy: receipt, stat: identity(target)}
    send(context.owner, {context.token, :staging_file, file_evidence(file)})
    file
  end

  defp copy_collect(port, deadline, state) do
    receive do
      {^port, {:data, bytes}} ->
        demand(state.bytes + byte_size(bytes) <= 16_384, :copy_protocol)

        copy_decode(port, deadline, %{
          state
          | buffer: state.buffer <> bytes,
            bytes: state.bytes + byte_size(bytes)
        })

      {:EXIT, ^port, _} ->
        fail(:copy_transport)
    after
      remaining(deadline) -> fail(:copy_deadline)
    end
  end

  defp copy_decode(port, deadline, %{buffer: bytes} = state) when byte_size(bytes) < 5,
    do: copy_collect(port, deadline, state)

  defp copy_decode(port, deadline, %{buffer: <<kind, size::32, rest::binary>>} = state) do
    demand(kind in [?O, ?S, ?X, ?E] and size <= 8192, :copy_protocol)

    if byte_size(rest) < size do
      copy_collect(port, deadline, state)
    else
      <<payload::binary-size(^size), tail::binary>> = rest
      state = %{state | buffer: tail}

      case kind do
        ?O ->
          demand(byte_size(state.stdout) + size <= 2048, :copy_protocol)
          copy_decode(port, deadline, %{state | stdout: state.stdout <> payload})

        ?S ->
          copy_decode(port, deadline, state)

        ?E ->
          %{state | result: :failed}

        ?X ->
          {:ok, value} = Ipse.JSON.decode_bounded(payload, 8192)
          %{state | result: value}
      end
    end
  end

  defp validate_copy_receipt(receipt, bytes) do
    demand(
      exact?(receipt, ~w(version bytes source destination)) and receipt["version"] === 1 and
        receipt["bytes"] === bytes,
      :copy_receipt
    )

    Enum.each(~w(source destination), fn side ->
      item = receipt[side]

      demand(
        exact?(item, @meta_keys) and item["bytes"] === bytes and uint?(item["mode"], 131_071),
        :copy_receipt
      )

      demand(
        Enum.all?(~w(device inode nlink), &decimal?(item[&1], false)) and
          Enum.all?(~w(mtime_seconds ctime_seconds), &decimal?(item[&1], true)) and
          Enum.all?(~w(mtime_nanoseconds ctime_nanoseconds), &uint?(item[&1], 999_999_999)),
        :copy_receipt
      )

      demand(Bitwise.band(item["mode"], 0o170000) == 0o100000, :copy_receipt)
    end)

    demand(
      receipt["destination"]["nlink"] == "1" and
        {receipt["source"]["device"], receipt["source"]["inode"]} !=
          {receipt["destination"]["device"], receipt["destination"]["inode"]},
      :copy_receipt
    )
  end

  defp decode_manifest(manifest) do
    demand(
      exact?(manifest, ~w(schemaVersion mediaType config layers)) and
        manifest["schemaVersion"] === 2 and
        manifest["mediaType"] in [
          "application/vnd.docker.distribution.manifest.v2+json",
          "application/vnd.oci.image.manifest.v1+json"
        ],
      :model_manifest
    )

    layers = manifest["layers"]
    demand(is_list(layers) and length(layers) in 1..128, :model_manifest)
    descriptor(manifest["config"])

    demand(
      manifest["config"]["size"] <= @json and
        manifest["config"]["mediaType"] in [
          "application/vnd.docker.container.image.v1+json",
          "application/vnd.oci.image.config.v1+json"
        ],
      :model_manifest
    )

    Enum.each(layers, fn layer ->
      descriptor(layer)

      demand(
        layer["mediaType"] in Enum.map(
          ~w(model adapter projector template system params messages license),
          &("application/vnd.ollama.image." <> &1)
        ),
        :model_manifest
      )
    end)

    demand(
      Enum.any?(
        layers,
        &(&1["mediaType"] == "application/vnd.ollama.image.model" and &1["size"] > 0)
      ),
      :model_manifest
    )

    manifest
  end

  defp descriptor(value) do
    demand(
      (exact?(value, ~w(mediaType digest size)) or exact?(value, ~w(mediaType digest size from))) and
        is_binary(value["digest"]) and Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, value["digest"]) and
        uint?(value["size"], @gib) and is_binary(value["mediaType"]),
      :model_manifest
    )

    if Map.has_key?(value, "from"), do: demand(text?(value["from"], 1024), :model_manifest)
  end

  defp validate_model_config(config) do
    allowed =
      ~w(architecture os model_format model_family model_families model_type file_type rootfs parser renderer requires)

    demand(
      is_map(config) and Enum.all?(Map.keys(config), &(&1 in allowed)) and
        text?(config["architecture"], 128) and text?(config["os"], 128) and
        is_map(config["rootfs"]),
      :model_config
    )

    demand(local_json?(config, 0), :model_config)
  end

  defp local_json?(_, depth) when depth > 16, do: false

  defp local_json?(value, depth) when is_map(value),
    do:
      map_size(value) <= 128 and
        Enum.all?(value, fn {key, item} ->
          text?(key, 128) and not Regex.match?(~r/remote|cloud|url|host/i, key) and
            local_json?(item, depth + 1)
        end)

  defp local_json?(value, depth) when is_list(value),
    do: length(value) <= 128 and Enum.all?(value, &local_json?(&1, depth + 1))

  defp local_json?(value, _) when is_binary(value), do: text?(value, 4096)
  defp local_json?(value, _), do: is_number(value) or is_boolean(value) or is_nil(value)

  defp inventory(config, initial, owner, token, deadline) do
    tags = request(config, :get, "/api/tags", nil, owner, token, deadline)

    demand(
      exact?(tags, ["models"]) and is_list(tags["models"]) and
        length(tags["models"]) == map_size(config["models"]),
      :model_inventory
    )

    models =
      Enum.map(tags["models"], fn item ->
        name = item["name"]

        demand(
          Map.has_key?(config["models"], name) and item["digest"] == config["models"][name],
          :model_inventory
        )

        details = request(config, :post, "/api/show", %{"model" => name}, owner, token, deadline)
        caps = details["capabilities"]

        row =
          model_row!(config, %{"name" => name, "digest" => item["digest"], "capabilities" => caps})

        if name == "qwen3.5:9b",
          do:
            demand(
              is_list(get_in(details, ["thinking", "values"])) and
                false in details["thinking"]["values"],
              :thinking_control
            )

        row
      end)

    demand(
      Enum.sort(Enum.map(models, & &1["name"])) == Enum.sort(Map.keys(config["models"])),
      :model_inventory
    )

    resident = request(config, :get, "/api/ps", nil, owner, token, deadline)

    demand(
      exact?(resident, ["models"]) and is_list(resident["models"]) and
        length(resident["models"]) <= map_size(config["models"]),
      :resident_inventory
    )

    rows = resident_rows!(config, resident["models"], initial, models)

    inventory = %{
      "models" => Enum.sort_by(models, & &1["name"]),
      "resident" => rows
    }

    if config["version"] === 1,
      do: Map.put(inventory, "cpu_history_proven", false),
      else: Map.put(inventory, "placement_history_proven", false)
  end

  defp model_row!(config, row) do
    demand(exact?(row, ~w(name digest capabilities)), :model_inventory)
    name = row["name"]
    caps = row["capabilities"]

    demand(
      Map.has_key?(config["models"], name) and row["digest"] == config["models"][name],
      :model_inventory
    )

    demand(
      is_list(caps) and length(caps) in 1..32 and Enum.all?(caps, &text?(&1, 64)) and
        length(Enum.uniq(caps)) == length(caps) and
        Enum.any?(caps, &(&1 in ["completion", "embedding"])),
      :model_capabilities
    )

    if name == "qwen3.5:9b",
      do: demand("completion" in caps and "tools" in caps, :thinking_control)

    if name == "embeddinggemma:latest", do: demand("embedding" in caps, :model_capabilities)
    row
  end

  defp resident_rows!(config, items, initial, models) do
    demand(is_list(items) and length(items) <= map_size(config["models"]), :resident_inventory)
    if initial, do: demand(items == [], :initial_resident)
    completion = for model <- models, "completion" in model["capabilities"], do: model["name"]
    device = device!(config)

    rows =
      Enum.map(items, fn item ->
        demand(
          Map.has_key?(config["models"], item["name"]) and
            item["digest"] == config["models"][item["name"]],
          :resident_inventory
        )

        row =
          if config["version"] === 1 do
            demand(item["size_vram"] === 0, :resident_inventory)
            Map.take(item, ~w(name digest size_vram))
          else
            demand(
              positive?(item["size"], @safe_integer) and uint?(item["size_vram"], item["size"]),
              :resident_inventory
            )

            if device == :cpu_only,
              do: demand(item["size_vram"] === 0, :resident_inventory),
              else: demand(item["size_vram"] > 0, :gpu_use_not_observed)

            Map.take(item, ~w(name digest size size_vram))
          end

        if config["version"] === 3 do
          demand(positive?(item["context_length"], 1_048_576), :context_length)

          if item["name"] in completion,
            do: demand(item["context_length"] == config["context_tokens"], :context_length)

          Map.put(row, "context_length", item["context_length"])
        else
          row
        end
      end)

    demand(length(Enum.uniq_by(rows, & &1["name"])) == length(rows), :resident_inventory)

    if device != :cpu_only and not initial,
      do: demand(rows != [], :gpu_use_not_observed)

    if config["version"] === 3 and not initial,
      do:
        demand(
          Enum.all?(completion, fn name -> Enum.any?(rows, &(&1["name"] == name)) end),
          :context_not_observed
        )

    rows
  end

  defp request(config, method, path, body, owner, token, deadline) do
    timeout = min(config["limits"]["metadata_ms"], remaining(deadline))
    headers = if body, do: [{"content-type", "application/json"}], else: []
    payload = if body, do: JSON.encode!(body), else: nil
    send(owner, {token, :metadata_request})

    case HTTP.bounded_request(
           Finch.build(method, config["origin"] <> path, headers, payload),
           @json,
           timeout
         ) do
      {:ok, 200, bytes} ->
        case Ipse.JSON.decode_bounded(bytes, @json) do
          {:ok, value} when is_map(value) -> value
          _ -> fail(:metadata_json)
        end

      _ ->
        fail(:metadata_http)
    end
  end

  defp recheck(files) do
    Enum.each(files, fn file ->
      demand(
        identity(file.path) == file.stat and hash_file(file.path, file.bytes) == file.sha256,
        :private_file_changed
      )
    end)
  end

  defp identity(path) do
    %{type: :regular, links: 1} = stat = File.lstat!(path, time: :posix)

    Map.take(stat, [
      :size,
      :mode,
      :inode,
      :major_device,
      :minor_device,
      :uid,
      :gid,
      :mtime,
      :ctime
    ])
  end

  defp hash_file(path, bytes) do
    %{type: :regular, links: 1, size: ^bytes} = File.lstat!(path)

    {context, count} =
      Enum.reduce(File.stream!(path, 1_048_576, []), {:crypto.hash_init(:sha256), 0}, fn part,
                                                                                         {context,
                                                                                          count} ->
        demand(count + byte_size(part) <= bytes, :file_size)
        {:crypto.hash_update(context, part), count + byte_size(part)}
      end)

    demand(count == bytes, :file_size)
    :crypto.hash_final(context) |> Base.encode16(case: :lower)
  end

  defp source_size(path, limit) do
    %{type: :regular, size: size} = File.lstat!(path)
    demand(size <= limit, :file_size)
    size
  end

  defp read_json(path) do
    demand(source_size(path, @json) <= @json, :file_size)
    {:ok, bytes} = File.open(path, [:read, :binary], &IO.binread(&1, @json + 1))
    demand(is_binary(bytes) and byte_size(bytes) <= @json, :file_size)
    {:ok, value} = Ipse.JSON.decode_bounded(bytes, @json)
    value
  end

  defp file_evidence(file),
    do: %{
      "path" => file.path,
      "bytes" => file.bytes,
      "sha256" => file.sha256,
      "copy" => file.copy
    }

  defp environment(config, paths, constructor) do
    selected =
      if constructor do
        values = constructor.(paths.home, paths.tmp)
        demand(exact?(values, ~w(PATH LANG HOME IPSE_HOME TMPDIR)), :environment)
        demand(values["HOME"] == paths.home and values["TMPDIR"] == paths.tmp, :environment)
        demand(values["IPSE_HOME"] == Path.join(paths.home, ".ipse"), :environment)
        demand(values["LANG"] == "C.UTF-8" and is_binary(values["PATH"]), :environment)
        values
      else
        %{}
      end

    values =
      Map.merge(
        %{
          "PATH" => Path.join(paths.runtime, "bin") <> ":/usr/bin:/bin",
          "LANG" => "C.UTF-8",
          "HOME" => paths.home,
          "TMPDIR" => paths.tmp,
          "OLLAMA_MODELS" => paths.models,
          "OLLAMA_HOST" => config["origin"],
          "LD_LIBRARY_PATH" => Path.join(paths.runtime, "lib/ollama"),
          "OLLAMA_NO_CLOUD" => "1",
          "CUDA_VISIBLE_DEVICES" =>
            case device!(config) do
              :cpu_only -> "-1"
              {:nvidia, uuid} -> uuid
            end,
          "ROCR_VISIBLE_DEVICES" => "-1",
          "OLLAMA_VULKAN" => "0",
          "GGML_VK_VISIBLE_DEVICES" => "-1",
          "OLLAMA_NUM_PARALLEL" => "1",
          "OLLAMA_MAX_LOADED_MODELS" => Integer.to_string(map_size(config["models"])),
          "OLLAMA_KEEP_ALIVE" => "-1"
        },
        selected
      )

    if config["version"] === 3,
      do: Map.put(values, "OLLAMA_CONTEXT_LENGTH", Integer.to_string(config["context_tokens"])),
      else: values
  end

  defp device!(%{"version" => 1, "cpu_policy" => "visibility_v1"} = config) do
    demand(exact?(config, @config_keys), :configuration)
    :cpu_only
  end

  defp device!(%{"version" => 2, "device_selection" => selection} = config) do
    demand(
      exact?(config, List.delete(@config_keys, "cpu_policy") ++ ["device_selection"]),
      :configuration
    )

    nvidia_selection!(selection)
  end

  defp device!(%{"version" => 3, "device_selection" => selection} = config) do
    demand(
      exact?(
        config,
        List.delete(@config_keys, "cpu_policy") ++ ~w(device_selection context_tokens)
      ) and
        positive?(config["context_tokens"], 1_048_576),
      :configuration
    )

    if selection == %{"policy" => "cpu_only"},
      do: :cpu_only,
      else: nvidia_selection!(selection)
  end

  defp device!(_), do: fail(:configuration)

  defp nvidia_selection!(selection) do
    demand(
      exact?(selection, ~w(policy uuid)) and selection["policy"] == @gpu_policy,
      :configuration
    )

    uuid = selection["uuid"]

    demand(
      is_binary(uuid) and
        Regex.match?(
          ~r/\AGPU-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/,
          uuid
        ),
      :configuration
    )

    {:nvidia, uuid}
  end

  defp paths(output),
    do: %{
      runtime: Path.join(output, "runtime"),
      home: Path.join(output, "home"),
      models: Path.join(output, "models"),
      tmp: Path.join(output, "tmp"),
      executable: Path.join(output, "runtime/bin/ollama")
    }

  defp result(state, code, output, started) do
    work_status =
      case state.work do
        :not_started -> "not_started"
        {:returned, _} -> "returned"
        {:raised, _, _, _} -> "raised"
        {:interrupted, _} -> "interrupted"
      end

    code = code || if(work_status == "raised", do: :callback_raised)

    receipt = %{
      "version" =>
        if(get_in(state, [:config, "version"]) in [2, 3], do: state.config["version"], else: 1),
      "status" => if(code == nil, do: "ok", else: "failed"),
      "code" => if(code, do: Atom.to_string(code)),
      "work_status" => work_status,
      "service_status" =>
        if(
          state.listener != nil and state.before != nil and state.after != nil and
            state.code == nil,
          do: "admitted",
          else: "failed"
        ),
      "native_cleanup" => state.native_cleanup,
      "staging_cleanup" => state.staging_cleanup,
      "inventory_before" => state.before,
      "inventory_after" => state.after,
      "listener" => state.listener,
      "metadata_requests" => state.metadata_requests,
      "native_traffic_bytes" => state.traffic,
      "retained_log_payload_bytes" => state.log_bytes,
      "retained_log_encoded_bytes" => state.log_encoded,
      "discarded_log_payload_bytes" => state.discarded,
      "log_scope" =>
        "O/S framed prefix through operation quiescence; Runner close drains excluded",
      "files" => Enum.reverse(state.staged_files),
      "environment" => if(state.staged, do: state.staged.environment, else: nil),
      "elapsed_ms" => max(now() - started, 0),
      "evidence" => output,
      "domain_cleanup" => "callback_owned_not_inferred",
      "inference_requests" => "callback_canonical_accounting"
    }

    %{work: state.work, receipt: receipt}
  end

  defp persist(result, state, output) do
    if state.output_created and state.task_down do
      try do
        write_private(Path.join(output, "daemon-prefix.bin"), [
          Enum.reverse(state.log_parts),
          state.log_tail
        ])

        bytes = JSON.encode!(result.receipt) <> "\n"
        demand(byte_size(bytes) <= @receipt_limit, :receipt_limit)
        write_private(Path.join(output, "receipt.json"), bytes)
        result
      rescue
        _ ->
          %{result | receipt: %{result.receipt | "status" => "failed", "code" => "evidence_io"}}
      catch
        {:model_service, _} ->
          %{result | receipt: %{result.receipt | "status" => "failed", "code" => "evidence_io"}}
      end
    else
      result
    end
  end

  defp write_private(path, bytes) do
    File.write!(path, bytes, [:exclusive, :sync])
    File.chmod!(path, 0o600)
    {:ok, :ok} = File.open(Path.dirname(path), [:read, :raw, :directory], &:file.sync/1)
  end

  defp close_port(port, mode) do
    Runner.close_stdio(port, mode)
  catch
    _, _ -> {:error, :cleanup_unconfirmed}
  end

  defp mkdir_private(path) do
    File.mkdir_p!(path)
    File.chmod!(path, 0o700)
  end

  defp canonical(path) do
    {:ok, resolved} = Workspace.canonical_path(path)
    resolved
  end

  defp disjoint_files?(paths),
    do:
      length(Enum.uniq(paths)) == length(paths) and
        not Enum.any?(paths, fn left ->
          Enum.any?(paths, fn right -> left != right and within?(left, right) end)
        end)

  defp exact?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(keys)

  defp absolute?(value),
    do: text?(value, 4096) and Path.type(value) == :absolute and Path.expand(value) == value

  defp relative?(value),
    do:
      text?(value, 1024) and Regex.match?(~r/\A[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*\z/, value) and
        length(String.split(value, "/")) <= 16 and
        Enum.all?(String.split(value, "/"), &(&1 not in [".", ".."]))

  defp model?(value),
    do:
      text?(value, 257) and
        Regex.match?(~r/\A[a-z0-9][a-z0-9._-]{0,127}:[a-z0-9][a-z0-9._-]{0,127}\z/, value)

  defp decimal?(value, signed),
    do:
      is_binary(value) and byte_size(value) in 1..24 and
        Regex.match?(
          if(signed, do: ~r/\A-?(?:0|[1-9][0-9]*)\z/, else: ~r/\A(?:0|[1-9][0-9]*)\z/),
          value
        )

  defp text?(value, limit),
    do:
      is_binary(value) and String.valid?(value) and byte_size(value) in 1..limit and
        not String.contains?(value, <<0>>)

  defp uint?(value, limit), do: is_integer(value) and value in 0..limit
  defp positive?(value, limit), do: is_integer(value) and value in 1..limit
  defp overlap?(left, right), do: within?(left, right) or within?(right, left)

  defp within?(path, root),
    do: path == root or String.starts_with?(path, String.trim_trailing(root, "/") <> "/")

  defp remaining(deadline) do
    remaining = deadline - now()
    demand(remaining > 0, :lifetime)
    remaining
  end

  defp now, do: System.monotonic_time(:millisecond)
  defp demand(true, _), do: :ok
  defp demand(_, code), do: fail(code)
  defp fail(code), do: throw({:model_service, code})
end
