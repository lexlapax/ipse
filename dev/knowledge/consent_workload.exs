defmodule Ipse.Development.ConsentWorkload do
  @moduledoc false
  alias Ipse.Extension.Consent, as: C
  @day 86_400_000
  @target 20_950

  def run(args) do
    true = :os.type() == {:unix, :linux}

    {options, [], []} =
      OptionParser.parse(args,
        strict: [operations: :integer, parent: :string, output: :string]
      )

    count = Keyword.get(options, :operations, @target)
    true = count in 1..@target

    {:ok, parent} =
      Ipse.Workspace.canonical_path(Path.expand(options[:parent] || System.tmp_dir!()))

    directory = Path.join(parent, "ipse-consent-workload-" <> Ipse.Usage.id())
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)
    root = Path.join(directory, "control")
    project = Ipse.JSON.sha256("development control ledger turnover v1")
    provenance = provenance(directory)
    policy = policy(project)
    {:ok, _} = C.replace(root, project, 0, policy, 1)
    driver = self()
    guard = spawn_link(fn -> guard(driver, System.monotonic_time(:millisecond)) end)

    state = %{
      root: root,
      project: project,
      policy: policy,
      epoch: 1,
      completed: 0,
      samples: [],
      zero_charge: 0,
      overrun_extra: 0
    }

    IO.puts(:stderr, "control development store retained at #{root}")

    try do
      final =
        Enum.reduce(1..count, state, fn index, state ->
          started = System.monotonic_time(:microsecond)
          now = min(div(index - 1, 30), 364) * @day + 1
          request = request(state, index)
          {:ok, ticket} = C.reserve(root, project, request, now)

          state =
            cond do
              rem(index, 101) == 0 ->
                {:ok, _} = C.settle(root, project, ticket, :unstarted)
                %{state | zero_charge: state.zero_charge + 1}

              rem(index, 997) == 0 ->
                {:ok, _} = C.admit(root, project, ticket, now)
                actual = Map.put(request["reserved"], "model_calls", 2)

                {:unknown, :consent_settlement_exceeds_reservation} =
                  C.settle(root, project, ticket, {:known, actual})

                {:error, :consent_reservation_refused} =
                  C.reserve(root, project, request(state, @target + index), now)

                {:ok, _} = C.settle(root, project, ticket, {:reconciled, actual})
                %{state | overrun_extra: state.overrun_extra + 1}

              rem(index, 37) == 0 ->
                {:ok, _} = C.admit(root, project, ticket, now)
                {:ok, _} = C.settle(root, project, ticket, :unknown)
                {:ok, _} = C.settle(root, project, ticket, {:reconciled, request["reserved"]})
                state

              true ->
                {:ok, _} =
                  C.publish(root, project, ticket, now, fn ->
                    {:ok, request["reserved"], %{"development_operation" => index}}
                  end)

                state
            end

          elapsed = div(System.monotonic_time(:microsecond) - started, 1_000)
          state = %{state | completed: index, samples: [elapsed | state.samples]}

          state =
            if rem(index, 1_000) == 0 do
              {:ok, %{"existing" => existing}} = C.reserve(root, project, request, now)
              true = existing["sequence"] == index
              {:ok, _} = C.revoke(root, project, state.epoch)
              {:ok, _} = C.replace(root, project, state.epoch + 1, policy, now)
              %{state | epoch: state.epoch + 2}
            else
              state
            end

          if rem(index, 1_000) == 0 or index == count do
            report = report(state, count, directory, provenance)
            save(options[:output], report)
            IO.puts(:stderr, "control development operations #{index}/#{count}")
          end

          state
        end)

      report = report(final, count, directory, provenance)
      save(options[:output], report)
      IO.puts(Jason.encode!(report, pretty: true))
    after
      Process.unlink(guard)
      Process.exit(guard, :kill)
    end
  end

  defp policy(project) do
    %{
      "version" => 1,
      "project" => project,
      "artifact_sha256" => Ipse.JSON.sha256("development artifact"),
      "source_sha256" => Ipse.JSON.sha256("development sources"),
      "operations" => ["knowledge.capture"],
      "settings" => %{},
      "limits" => Map.new(C.resources(), &{&1, 100_000}),
      "period_ms" => 365 * @day,
      "expires_at_ms" => 366 * @day,
      "headless" => true
    }
  end

  defp request(state, index) do
    %{
      "id" => Ipse.Usage.id(),
      "operation" => "knowledge.capture",
      "artifact_sha256" => state.policy["artifact_sha256"],
      "source_sha256" => state.policy["source_sha256"],
      "policy_sha256" => Ipse.JSON.digest([state.policy]),
      "request_sha256" => Ipse.JSON.digest([%{"development_operation" => index}]),
      "source_generation" => index,
      "reserved" => C.zero() |> Map.merge(%{"operations" => 1, "model_calls" => 1}),
      "headless" => true
    }
  end

  defp report(state, requested, directory, provenance) do
    {:ok, ledger} = C.snapshot(state.root, state.project)
    true = ledger["sequence"] == state.completed
    true = map_size(ledger["operations"]) + map_size(ledger["compacted"]) == state.completed

    totals =
      Enum.reduce(ledger["operations"], C.zero(), fn {_, operation}, sum ->
        add(sum, operation["actual"])
      end)

    totals =
      Enum.reduce(ledger["compacted"], totals, fn {_, [_, _, _, _, _, actual, _]}, sum ->
        add(sum, Map.new(Enum.zip(C.resources(), actual)))
      end)

    expected = state.completed - state.zero_charge
    true = totals["operations"] == expected
    true = totals["model_calls"] == expected + state.overrun_extra
    samples = Enum.sort(state.samples)

    %{
      "kind" => "development_authored_control_turnover_v1",
      "requested" => requested,
      "completed" => state.completed,
      "annual_target" => @target,
      "actual_individual_reservations" => state.completed,
      "simulated_resource_charges" => totals,
      "actual_model_calls" => 0,
      "seeded_receipts" => 0,
      "zero_charge_settlements" => state.zero_charge,
      "reconciled_overruns" => state.overrun_extra,
      "retained_full" => map_size(ledger["operations"]),
      "retained_compact" => map_size(ledger["compacted"]),
      "control_file_bytes" =>
        File.stat!(Path.join([state.root, state.project, "control.json"])).size,
      "operation_ms_p50" => Enum.at(samples, div(length(samples) - 1, 2)),
      "operation_ms_p95" =>
        Enum.at(samples, min(ceil(length(samples) * 0.95) - 1, length(samples) - 1)),
      "operation_ms_max" => List.last(samples),
      "retained_store" => directory,
      "provenance" => provenance,
      "control_turnover_passed" => state.completed == @target,
      "qualification_passed" => false,
      "limits" =>
        "Control-only development workload; no notes, Session, native input, semantic quality, independent-human or platform qualification. All IDs use actual individual writes; resource counters are synthetic."
    }
  end

  defp add(left, right), do: Map.new(C.resources(), &{&1, left[&1] + right[&1]})
  defp save(nil, _report), do: :ok
  defp save(path, report), do: File.write!(path, Jason.encode!(report, pretty: true) <> "\n")

  defp provenance(parent) do
    {:ok, helper} = Ipse.Runner.protected_helper(parent)

    {:ok, kernel} =
      File.open("/proc/sys/kernel/osrelease", [:read, :binary], &IO.binread(&1, 257))

    true = is_binary(kernel) and byte_size(kernel) <= 256

    %{
      "elixir" => System.version(),
      "otp" => to_string(:erlang.system_info(:otp_release)),
      "kernel" => String.trim(kernel),
      "native_sha256" => Ipse.JSON.sha256(File.read!(helper)),
      "source_sha256" =>
        Map.new(
          ~w(lib/ipse/extension/consent.ex lib/ipse/runner/transaction.ex lib/ipse/session/resources.ex dev/knowledge/consent_workload.exs),
          &{&1, Ipse.JSON.sha256(File.read!(&1))}
        ),
      "loaded_beam_sha256" =>
        Map.new([C, Ipse.Runner.Transaction, Ipse.Session.Resources], fn module ->
          {^module, bytes, _file} = :code.get_object_code(module)
          {Atom.to_string(module), Ipse.JSON.sha256(bytes)}
        end),
      "filesystem_parent" => parent,
      "filesystem" => filesystem(parent)
    }
  end

  defp filesystem(parent) do
    {:ok, bytes} =
      File.open("/proc/self/mountinfo", [:read, :binary], &IO.binread(&1, 1_048_577))

    true = is_binary(bytes) and byte_size(bytes) <= 1_048_576

    {_, type, options} =
      bytes
      |> String.split("\n", trim: true)
      |> Enum.flat_map(fn line ->
        [left, right] = String.split(line, " - ", parts: 2)
        fields = String.split(left)
        [type, _source, super_options | _] = String.split(right)

        mount =
          Enum.at(fields, 4)
          |> String.replace("\\040", " ")
          |> String.replace("\\134", "\\")

        if parent == mount or String.starts_with?(parent, String.trim_trailing(mount, "/") <> "/"),
          do: [{byte_size(mount), type, Enum.at(fields, 5) <> "," <> super_options}],
          else: []
      end)
      |> Enum.max_by(&elem(&1, 0))

    selected =
      options
      |> String.split(",")
      |> Enum.filter(
        &(&1 in ~w(rw ro nosuid nodev noexec) or String.starts_with?(&1, "compress=") or
            String.starts_with?(&1, "huge="))
      )
      |> Enum.uniq()

    %{"type" => type, "selected_mount_options" => selected}
  end

  defp guard(driver, started) do
    receive do
    after
      1_000 ->
        cond do
          not Process.alive?(driver) ->
            :ok

          System.monotonic_time(:millisecond) - started > 10_800_000 ->
            Process.exit(driver, :kill)

          :erlang.memory(:total) > 536_870_912 ->
            Process.exit(driver, :kill)

          true ->
            guard(driver, started)
        end
    end
  end
end

Ipse.Development.ConsentWorkload.run(System.argv())
