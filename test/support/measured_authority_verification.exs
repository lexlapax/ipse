defmodule MeasuredAuthorityVerification do
  @moduledoc "Fresh-seal loss and live authority controls; never retries an interrupted attempt."
  alias Ipse.Runner
  alias Ipse.Extensions.Manifest
  alias IpseKnowledgeExample.EvaluationMeasuredExecution, as: Measured
  @wait_ms 60_000
  @cleanup_ms 15_000
  @limit 1_048_576

  def verify(repository, artifacts, root) do
    true = :os.type() == {:unix, :linux}
    true = Path.type(root) == :absolute and Path.expand(root) == root
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    {:ok, _} = Application.ensure_all_started(:ipse)

    checks =
      for kind <-
            ~w(owner_loss collector_loss service_stop registry_replacement model_service_loss) do
        control(kind, repository, artifacts, root)
      end

    summary = %{
      "version" => 1,
      "checks" => length(checks),
      "controls" => checks,
      "cleanup_confirmed" => true,
      "fresh_attempt_per_control" => true,
      "model_service_only_loss" => "owned_daemon_exit_on_first_answer",
      "quality_measured" => false,
      "evidence" => root
    }

    save!(Path.join(root, "summary.json"), summary)
    summary
  end

  defp control(kind, repository, artifacts, root) do
    run =
      if kind == "model_service_loss",
        do:
          MeasuredKnowledgeVerification.prepare(
            Path.join(root, kind),
            repository,
            artifacts,
            :exit_on_answer
          ),
        else: MeasuredKnowledgeVerification.prepare(Path.join(root, kind), repository, artifacts)

    manifest = json!(run.seal["path"])

    if kind == "model_service_loss" do
      [control] =
        Enum.filter(
          manifest["resolution"]["model_service"]["runtime"]["files"],
          &(&1["path"] == "lib/ollama/control.json")
        )

      true = json!(control["source"])["fault"] == "exit_on_answer"
    end

    freeze = Path.dirname(run.seal["path"])
    native = Path.join(freeze, "native-root")
    unit = "ipse-measure-" <> manifest["execution_id"] <> ".service"
    token = make_ref()
    parent = self()

    {owner, monitor} =
      spawn_monitor(fn ->
        outcome = Measured.run(freeze: run.seal["path"], freeze_sha256: run.seal["sha256"])
        send(parent, {token, outcome})
      end)

    try do
      observed = wait(fn -> preparation(native, freeze, manifest, token) end, now() + @wait_ms)
      save!(Path.join(run.root, "preparation-observation.json"), observed)
      true = Process.alive?(owner)

      isolated =
        if kind == "service_stop" do
          value = wait(fn -> daemon(run, observed) end, now() + @wait_ms)
          save!(Path.join(run.root, "daemon-observation.json"), value)
          value
        end

      claims = claims(native)
      main = observed["collector_pid"]

      if kind != "model_service_loss" do
        true =
          systemctl!(["show", unit, "--property=MainPID", "--value"], run.root) |> String.trim() ==
            Integer.to_string(main)

        true = alive?(main)
      end

      save!(Path.join(run.root, "before-fault.json"), %{
        "kind" => kind,
        "claims" => claims,
        "collector_pid" => main
      })

      case kind do
        "owner_loss" ->
          Process.exit(owner, :kill)

        "collector_loss" ->
          systemctl!(["kill", "--kill-whom=main", "--signal=KILL", unit], run.root)

        "service_stop" ->
          systemctl!(["stop", unit], run.root)

        "registry_replacement" ->
          registry = Path.join(freeze, "attempts")
          File.rename!(registry, registry <> "-retained")
          File.mkdir!(registry)
          File.chmod!(registry, 0o700)

        "model_service_loss" ->
          wait(fn -> answer_exit_observed?(run) end, now() + @wait_ms)
      end

      settle_ms =
        if kind == "model_service_loss",
          do: min(manifest["launch_recipe"]["timeouts"]["root_ms"] + 20_000, 600_000),
          else: @cleanup_ms

      outcome = await_owner(token, owner, monitor, kind, now() + settle_ms)
      wait(fn -> scope_closed?(observed["whole_scope_path"]) end, now() + @cleanup_ms)

      wait(
        fn -> process_identity(main) != observed["collector_identity"] end,
        now() + @cleanup_ms
      )

      if kind == "model_service_loss" do
        verify_service_failure!(run, native)
      else
        true = claims(native) == claims
        false = File.exists?(Path.join(native, "sequence/sequence.json"))
      end

      if kind == "collector_loss", do: false = File.exists?(Path.join(native, "receipt.json"))

      if kind == "registry_replacement" do
        receipt = json!(Path.join(native, "receipt.json"))
        true = receipt["reason"] == "authority_lost" and receipt["cleanup_confirmed"]
        false = receipt["complete"]
      end

      if isolated do
        wait(
          fn ->
            process_identity(isolated["daemon_pid"]) != isolated["daemon_identity"] and
              process_identity(isolated["native_parent_pid"]) !=
                isolated["native_parent_identity"]
          end,
          now() + @cleanup_ms
        )
      end

      retained = snapshot(native)
      {:error, _} = Measured.run(freeze: run.seal["path"], freeze_sha256: run.seal["sha256"])
      true = snapshot(native) == retained

      result = %{
        "control" => kind,
        "trigger_observed" => true,
        "erts_fds_4_through_8_verified" => true,
        "ordinary_native_and_daemon_fd_isolation" =>
          if(isolated, do: true, else: "not_checked_this_control"),
        "cleanup_confirmed" => true,
        "no_later_stage_claim" =>
          if(kind == "model_service_loss",
            do: "later_cells_allowed_after_confirmed_cleanup",
            else: true
          ),
        "reentry_refused" => true,
        "outcome" => outcome
      }

      save!(Path.join(run.root, "control.json"), result)
      result
    rescue
      error ->
        save!(Path.join(run.root, "failure.json"), %{
          "control" => kind,
          "exception" => inspect(error.__struct__),
          "message" => Exception.message(error),
          "verification_complete" => false
        })

        reraise error, __STACKTRACE__
    after
      if Process.alive?(owner), do: Process.exit(owner, :kill)

      receive do
        {:DOWN, ^monitor, :process, ^owner, _} -> :ok
      after
        1000 -> :ok
      end

      case systemctl(["stop", unit], run.root) do
        {:ok, _} ->
          :ok

        {:error, _} ->
          true =
            systemctl!(["show", unit, "--property=LoadState", "--value"], run.root)
            |> String.trim() == "not-found"
      end

      if path = Process.delete({__MODULE__, token}),
        do: wait(fn -> scope_closed?(path) end, now() + @cleanup_ms)

      Process.demonitor(monitor, [:flush])
    end
  end

  defp preparation(native, freeze, manifest, token) do
    with started when is_map(started) <- optional_json(Path.join(native, "started.json")),
         claim when is_map(claim) <- optional_json(Path.join(native, "domain-prepare.claim")),
         stage when is_map(stage) <-
           optional_json(Path.join(native, "metric-prepare/started.json")) do
      whole = whole_scope(started, manifest["execution_id"])
      Process.put({__MODULE__, token}, whole)
      scope = Path.join(whole, "cell-" <> stage["token"])

      expected = [
        identity(native),
        identity(Path.join(freeze, "attempts")),
        identity(whole),
        identity(scope),
        identity(Path.join(native, "sequence"))
      ]

      true = claim["whole_scope"] == Enum.at(expected, 2)
      true = claim["scope"] == Enum.at(expected, 3)
      pids = pids(scope)
      matches = Enum.filter(pids, &(fd_identities(&1) == expected))

      case matches do
        [pid] ->
          launch = manifest["runtime"]["launch"]
          beam = Path.join(Path.dirname(launch["executable"]), "beam.smp")
          [file] = Enum.filter(launch["files"], &(&1["path"] == beam))
          true = File.stat!(beam).size == file["bytes"]
          true = file_sha(beam) == file["sha256"]
          true = identity("/proc/#{pid}/exe") == identity(beam)
          true = member?(pid, scope)
          true = fd_identities(pid) == expected
          collector_identity = process_identity(started["collector_pid"])
          true = is_map(collector_identity)

          %{
            "erts_pid" => pid,
            "collector_pid" => started["collector_pid"],
            "collector_identity" => collector_identity,
            "whole_scope_path" => whole,
            "stage_scope_path" => scope,
            "fd_identities" => expected,
            "native_root" => native
          }

        _ ->
          false
      end
    else
      _ -> false
    end
  end

  defp daemon(run, observed) do
    home = Path.join(run.reports, "cells/cell-000/model-service/home")

    with {:ok, bytes} <- bounded(Path.join(home, "fixture-requests.jsonl"), 16_777_216),
         true <- String.contains?(bytes, "/api/tags"),
         {:ok, raw} <- bounded(Path.join(home, "fixture-daemon.pid"), 32),
         {pid, ""} <- Integer.parse(String.trim(raw)),
         true <- pid > 0 and alive?(pid) do
      parent = parent_pid(pid)
      true = parent > 0 and alive?(parent)
      daemon_identity = process_identity(pid)
      parent_identity = process_identity(parent)
      status = bounded!("/proc/#{pid}/status", 65_536)
      true = String.contains?(status, "PPid:\t#{parent}\n")
      whole = observed["whole_scope_path"]
      true = member_below?(pid, whole) and member_below?(parent, whole)
      command = bounded!("/proc/#{parent}/cmdline", 65_536)
      true = String.contains?(command, "--stdio-listener")

      true =
        identity("/proc/#{parent}/exe") ==
          identity(Application.app_dir(:ipse, "priv/ipse-runner"))

      cell_path = membership(bounded!("/proc/#{pid}/cgroup", 8192))
      started = json!(Path.join(observed["native_root"], "metric-cell-000/started.json"))
      true = cell_path == Path.join(whole, "cell-" <> started["token"])
      cell_identity = identity(cell_path)

      true =
        cell_identity == %{"device" => started["scope_device"], "inode" => started["scope_inode"]}

      identities = [cell_identity | observed["fd_identities"]]
      isolated!(pid, identities)
      isolated!(parent, identities)

      for name <-
            ~w(IPSE_BOUND_ROOT_FD IPSE_BOUND_REGISTRY_FD IPSE_MEASURE_ROOT_FD IPSE_MEASURE_SCOPE_FD IPSE_BOUND_SEQUENCE_FD) do
        false = String.contains?(bounded!("/proc/#{pid}/environ", 262_144), name <> "=")
      end

      true =
        process_identity(pid) == daemon_identity and process_identity(parent) == parent_identity

      %{
        "daemon_pid" => pid,
        "native_parent_pid" => parent,
        "daemon_identity" => daemon_identity,
        "native_parent_identity" => parent_identity,
        "metadata_request_observed" => true,
        "authority_objects_absent_from_all_fds" => true
      }
    else
      _ -> false
    end
  end

  defp answer_exit_observed?(run) do
    path = Path.join(run.reports, "cells/cell-000/model-service/home/fixture-requests.jsonl")

    case bounded(path, 16_777_216) do
      {:ok, bytes} ->
        rows = bytes |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
        Enum.count(rows, &(&1["operation"] == "answer")) == 1

      {:error, :enoent} ->
        false
    end
  end

  defp verify_service_failure!(run, native) do
    true = answer_exit_observed?(run)
    cell = json!(Path.join(run.reports, "cells/cell-000/cell-result.json"))
    false = cell["complete"]
    true = cell["service"]["status"] == "failed" and cell["service"]["code"] == "service_exited"
    true = cell["service"]["native_cleanup"] == "confirmed"
    <<0, 1>> = bounded!(Path.join(native, "sequence/stage-001.status"), 2)
    root = json!(Path.join(native, "receipt.json"))
    true = root["cleanup_confirmed"]
    false = root["complete"]
    domain = cell["domain"]
    true = domain == nil or domain["complete"] == false
    sessions = Path.join(run.reports, "cells/cell-000/domain/alpha/lexical/sessions")
    [journal] = Path.wildcard(Path.join(sessions, "*.jsonl"))
    bounded!(journal, @limit)
    session_id = Path.basename(journal, ".jsonl")
    {:ok, events} = Ipse.Journal.load(sessions, session_id)
    {:ok, ledger} = Ipse.Usage.restore(events, session_id)

    [first | _] =
      Enum.map(Ipse.Usage.order(ledger), &Ipse.Usage.request_record(ledger.requests[&1]))

    true = Ipse.Usage.valid_request_record?(first)
    true = first["outcome"] in ~w(unknown failed cancelled)

    save!(Path.join(run.root, "model-service-failure.json"), %{
      "actual_first_answer_before_exit" => true,
      "service_code" => cell["service"]["code"],
      "domain_accounting" =>
        if(domain, do: "failed_retained_report", else: "unavailable_never_reported_as_success"),
      "work_status" => cell["service"]["work_status"],
      "canonical_first_request" => first,
      "cleanup_confirmed" => true
    })
  end

  defp isolated!(pid, authority) do
    paths = Path.wildcard("/proc/#{pid}/fd/*")
    true = length(paths) in 1..4096

    for path <- paths do
      case File.stat(path) do
        {:ok, stat} ->
          false = %{"device" => stat.major_device, "inode" => stat.inode} in authority

        {:error, :enoent} ->
          :ok
      end
    end

    true = alive?(pid)
  end

  defp fd_identities(pid) do
    try do
      for fd <- 4..8, do: identity("/proc/#{pid}/fd/#{fd}")
    rescue
      _ -> nil
    end
  end

  defp whole_scope(started, id) do
    pid = started["collector_pid"]
    text = bounded!("/proc/#{pid}/cgroup", 8192)
    path = membership(text)
    true = Path.basename(path) == "collector-" <> id
    service = Path.dirname(path)
    true = Path.basename(service) == "ipse-measure-" <> id <> ".service"
    root = Path.join(service, "ipse-run-" <> id)

    true =
      identity(root) == %{"device" => started["scope_device"], "inode" => started["scope_inode"]}

    root
  end

  defp scope_closed?(path) do
    case bounded(Path.join(path, "cgroup.events"), 8192) do
      {:error, :enoent} -> true
      {:ok, text} -> "populated 0" in String.split(text, "\n", trim: true)
      _ -> false
    end
  end

  defp pids(scope),
    do:
      bounded!(Path.join(scope, "cgroup.procs"), 8192)
      |> String.split()
      |> Enum.map(&String.to_integer/1)

  defp member?(pid, path), do: membership(bounded!("/proc/#{pid}/cgroup", 8192)) == path

  defp member_below?(pid, path),
    do: String.starts_with?(membership(bounded!("/proc/#{pid}/cgroup", 8192)), path <> "/")

  defp membership(text) do
    [relative] =
      for line <- String.split(text, "\n"),
          String.starts_with?(line, "0::"),
          do: String.replace_prefix(line, "0::", "")

    true = String.starts_with?(relative, "/") and Path.expand(relative) == relative
    "/sys/fs/cgroup" <> relative
  end

  defp identity(path) do
    s = File.stat!(path)
    %{"device" => s.major_device, "inode" => s.inode}
  end

  defp parent_pid(pid) do
    [line] =
      bounded!("/proc/#{pid}/status", 65_536)
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "PPid:"))

    line |> String.replace_prefix("PPid:", "") |> String.trim() |> String.to_integer()
  end

  defp alive?(pid) do
    case bounded("/proc/#{pid}/status", 65_536) do
      {:ok, text} -> not String.contains?(text, "State:\tZ")
      {:error, :enoent} -> false
      _ -> false
    end
  end

  defp process_identity(pid) do
    case bounded("/proc/#{pid}/stat", 65_536) do
      {:ok, bytes} ->
        {at, 2} = List.last(:binary.matches(bytes, ") "))
        fields = binary_part(bytes, at + 2, byte_size(bytes) - at - 2) |> String.split()

        if hd(fields) == "Z",
          do: nil,
          else: %{"pid" => pid, "starttime_ticks" => Enum.at(fields, 19)}

      {:error, :enoent} ->
        nil
    end
  end

  defp await_owner(token, owner, monitor, kind, deadline) do
    receive do
      {^token, {:error, value}} ->
        receive do
          {:DOWN, ^monitor, :process, ^owner, :normal} -> %{"result" => value}
        after
          max(deadline - now(), 0) -> raise("owned evaluator did not exit")
        end

      {^token, {:ok, _}} ->
        raise("loss control completed successfully before its fault")

      {:DOWN, ^monitor, :process, ^owner, :killed} when kind == "owner_loss" ->
        %{"owner_down" => "killed"}

      {:DOWN, ^monitor, :process, ^owner, reason} ->
        raise("unexpected evaluator exit: #{inspect(reason)}")
    after
      max(deadline - now(), 0) -> raise("owned evaluator did not settle after fault")
    end
  end

  defp claims(native),
    do:
      Path.wildcard(Path.join(native, "sequence/stage-*.claim"))
      |> Enum.map(&Path.basename/1)
      |> Enum.sort()

  defp snapshot(root),
    do:
      Path.wildcard(Path.join(root, "**/*"))
      |> Enum.filter(&File.regular?/1)
      |> Map.new(&{&1, file_sha(&1)})

  defp file_sha(path),
    do:
      File.stream!(path, 1_048_576, [])
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)

  defp optional_json(path) do
    case bounded(path, @limit) do
      {:ok, bytes} ->
        case Manifest.decode_json(bytes, @limit) do
          {:ok, value} -> value
          _ -> nil
        end

      {:error, :enoent} ->
        nil
    end
  end

  defp json!(path), do: bounded!(path, @limit) |> JSON.decode!()

  defp bounded!(path, limit) do
    {:ok, bytes} = bounded(path, limit)
    bytes
  end

  defp bounded(path, limit) do
    case File.open(path, [:read, :binary, :raw]) do
      {:ok, file} ->
        try do
          read_file(file, limit, 0, [])
        after
          File.close(file)
        end

      error ->
        error
    end
  end

  defp read_file(file, limit, size, parts) do
    case :file.read(file, min(65_536, limit + 1 - size)) do
      :eof ->
        {:ok, parts |> Enum.reverse() |> IO.iodata_to_binary()}

      {:ok, bytes} when byte_size(bytes) > 0 and size + byte_size(bytes) <= limit ->
        read_file(file, limit, size + byte_size(bytes), [bytes | parts])

      _ ->
        raise("control evidence exceeds read bound")
    end
  end

  defp save!(path, value),
    do: MeasuredKnowledgeVerification.save!(path, JSON.encode!(value) <> "\n")

  defp wait(fun, deadline) do
    case fun.() do
      value when value not in [false, nil] ->
        value

      _ ->
        if now() >= deadline, do: raise("authority control did not reach its actual boundary")
        Process.sleep(10)
        wait(fun, deadline)
    end
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp systemctl!(args, cwd) do
    {:ok, text} = systemctl(args, cwd)
    text
  end

  defp systemctl(args, cwd) do
    executable = System.find_executable("systemctl") || raise("systemctl unavailable")

    env =
      System.get_env() |> Map.take(~w(PATH HOME LANG XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS))

    {:ok, port} =
      Runner.open_stdio(executable, ["--user", "--no-ask-password" | args], cwd, env, 5_000)

    try do
      {text, result} = command_result(port, <<>>, <<>>, now() + 7_000)
      :ok = Runner.close_stdio(port, :completed)

      if result["exit_code"] == 0 and result["timed_out"] == false,
        do: {:ok, text},
        else: {:error, result}
    after
      if Port.info(port), do: Runner.close_stdio(port, :cancel)
    end
  end

  defp command_result(port, buffer, text, deadline) do
    true = byte_size(buffer) + byte_size(text) <= 16_384

    case buffer do
      <<kind, size::32, rest::binary>> when size <= 8192 and byte_size(rest) >= size ->
        <<payload::binary-size(^size), remaining::binary>> = rest

        case kind do
          ?O -> command_result(port, remaining, text <> payload, deadline)
          ?S -> command_result(port, remaining, text, deadline)
          ?X -> {text, JSON.decode!(payload)}
          ?E -> raise("owned systemctl supervisor refused: " <> payload)
        end

      <<_, size::32, _::binary>> when size > 8192 ->
        raise("oversized systemctl frame")

      _ ->
        true = byte_size(buffer) + byte_size(text) <= 16_384

        receive do
          {^port, {:data, more}} ->
            command_result(port, buffer <> more, text, deadline)

          {^port, {:exit_status, status}} ->
            raise("systemctl ended before terminal frame: #{status}")
        after
          max(deadline - now(), 0) -> raise("owned systemctl command exceeded deadline")
        end
    end
  end
end
