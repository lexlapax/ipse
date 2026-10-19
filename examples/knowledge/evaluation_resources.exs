defmodule IpseKnowledgeExample.EvaluationResources do
  @moduledoc "Sample the harness VM and count files, without claiming model or OS peak memory."

  def start(path, interval) when interval in 10..1000 do
    owner = self()
    token = make_ref()

    {pid, monitor} =
      spawn_monitor(fn ->
        reference = Process.monitor(owner)
        loop(path, interval, reference, owner, token, nil, 0, nil)
      end)

    %{pid: pid, monitor: monitor, token: token}
  end

  def stop(sampler) do
    send(sampler.pid, {:stop, sampler.token})

    receive do
      {token, report} when token == sampler.token ->
        receive do
          {:DOWN, ref, :process, _, :normal} when ref == sampler.monitor -> {:ok, report}
        after
          5000 -> {:error, :sampler_cleanup_unconfirmed}
        end

      {:DOWN, ref, :process, _, _} when ref == sampler.monitor ->
        {:error, :sampler_failed}
    after
      5000 -> {:error, :sampler_cleanup_unconfirmed}
    end
  end

  def storage(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reduce(%{}, fn path, counts ->
      relative = Path.relative_to(path, root)

      category =
        cond do
          String.starts_with?(relative, "home/extension-state-v1/") -> "store"
          String.starts_with?(relative, "home/extensions/artifacts/") -> "artifacts"
          String.starts_with?(relative, "sessions/") -> "journals_and_budgets"
          true -> "other"
        end

      case File.lstat!(path) do
        %{type: :regular, size: bytes} ->
          Map.update(
            counts,
            category,
            %{"files" => 1, "bytes" => bytes},
            &%{"files" => &1["files"] + 1, "bytes" => &1["bytes"] + bytes}
          )

        _ ->
          counts
      end
    end)
  end

  defp loop(path, interval, reference, owner, token, peak, count, first) do
    memory = :erlang.memory()

    sample = %{
      "at_monotonic_ms" => System.monotonic_time(:millisecond),
      "beam_total_bytes" => memory[:total],
      "beam_process_bytes" => memory[:processes]
    }

    File.write!(path, JSON.encode!(sample) <> "\n", [:append])
    peak = max(peak || 0, sample["beam_total_bytes"])
    first = first || sample

    receive do
      {:stop, ^token} ->
        send(
          owner,
          {token,
           %{
             "interval_ms" => interval,
             "samples" => count + 1,
             "sampled_beam_max_bytes" => peak,
             "start" => first,
             "end" => sample,
             "worker_rss" => nil,
             "model_rss" => nil,
             "whole_system_peak" => nil
           }}
        )

      {:DOWN, ^reference, :process, _, _} ->
        :ok
    after
      interval -> loop(path, interval, reference, owner, token, peak, count + 1, first)
    end
  end
end
