defmodule Ipse.Test.EgressMark do
  @moduledoc false
  # Disposable synthetic diagnostic; this module is never promoted.
  @name :ipse_synthetic_egress_mark
  @limit 4096
  @stages ~w(subject gate_enter gate_result gate_exception current_enter current_result current_exception send_enter send_result transport_connect transport_connected transport_admit transport_admit_result transport_state_pending transport_state_refused transport_state_sent transport_state_other transport_deadline_refused transport_request transport_request_ok transport_request_error)a
  @errors ~w(inference_dispatch_refused inference_request_refused inference_egress_refused inference_send_uncertain inference_connection_failed inference_timeout inference_cleanup_unconfirmed timeout)a

  def start(path) do
    owner = self()
    sink = spawn(fn -> collect(owner, path) end)
    receive do
      {:egress_mark_ready, ^sink} -> :ok
    after
      5_000 -> raise "synthetic egress sink did not start"
    end
    true = Process.register(sink, @name)
    sink
  end

  def emit(stage, owner \\ nil, job \\ nil, result \\ nil) when stage in @stages do
    if sink = Process.whereis(@name) do
      send(sink, {:mark, stage, self(), owner, job, System.monotonic_time(), classify(result)})
    end
    :ok
  end

  def subject(owner), do: emit(:subject, owner)

  def listener(event, bytes) when event in [:accepted, :initial_read, :closed, :request_body] and is_integer(bytes) and bytes >= 0 do
    case Process.whereis(@name) do
      nil -> :ok
      sink ->
        ref = make_ref()
        send(sink, {:listener, self(), ref, event, bytes, System.monotonic_time()})
        receive do
          {:listener_marked, ^ref} -> :ok
        after
          1_000 -> raise "synthetic listener marker unconfirmed"
        end
    end
  end

  # A same-producer barrier confirms that producer's earlier marks reached the sink.
  def barrier(stage) when stage in [:gate, :send, :transport] do
    case Process.whereis(@name) do
      nil -> :unavailable
      sink ->
        ref = make_ref()
        send(sink, {:producer_barrier, self(), ref, stage, System.monotonic_time()})
        receive do
          {:producer_marked, ^ref} -> :ok
        after
          1_000 -> :unconfirmed
        end
    end
  end

  def finish(sink) do
    ref = make_ref()
    send(sink, {:finish, self(), ref})
    receive do
      {:egress_mark_finished, ^ref, summary} -> summary
    after
      5_000 -> raise "synthetic egress sink did not finish"
    end
  end

  defp collect(owner, path) do
    {:ok, file} = :file.open(String.to_charlist(path), [:write, :exclusive, :binary, :raw])
    File.chmod!(path, 0o600)
    monitor = Process.monitor(owner)
    send(owner, {:egress_mark_ready, self()})
    loop(file, monitor, 0, 0)
  end

  defp loop(file, monitor, count, dropped) do
    receive do
      {:mark, stage, caller, owner, job, at, result} ->
        item = %{"kind" => "mark", "stage" => Atom.to_string(stage), "pid" => pid(caller), "owner_pid" => pid(owner), "job" => job(job), "at" => at, "class" => result}
        {count, dropped} = put(file, item, count, dropped)
        loop(file, monitor, count, dropped)
      {:listener, caller, ref, event, bytes, at} ->
        item = %{"kind" => "listener", "event" => Atom.to_string(event), "pid" => pid(caller), "bytes" => bytes, "at" => at}
        {count, dropped} = put(file, item, count, dropped)
        send(caller, {:listener_marked, ref})
        loop(file, monitor, count, dropped)
      {:producer_barrier, caller, ref, stage, at} ->
        item = %{"kind" => "producer_barrier", "stage" => Atom.to_string(stage), "pid" => pid(caller), "at" => at}
        {count, dropped} = put(file, item, count, dropped)
        send(caller, {:producer_marked, ref})
        loop(file, monitor, count, dropped)
      {:finish, from, ref} ->
        summary = %{"kind" => "summary", "events" => count, "dropped" => dropped, "closure" => "finish_received"}
        write(file, summary)
        :ok = :file.sync(file)
        :ok = :file.close(file)
        send(from, {:egress_mark_finished, ref, summary})
      {:DOWN, ^monitor, :process, _, _} ->
        write(file, %{"kind" => "summary", "events" => count, "dropped" => dropped, "closure" => "owner_exit"})
        :file.sync(file)
        :file.close(file)
    end
  end

  defp put(file, item, count, dropped) when count < @limit do
    write(file, item)
    {count + 1, dropped}
  end
  defp put(_file, _item, count, dropped), do: {count, dropped + 1}
  defp write(file, event), do: :ok = :file.write(file, [Jason.encode!(event), "\n"])
  defp pid(value) when is_pid(value), do: value |> :erlang.pid_to_list() |> List.to_string()
  defp pid(_), do: nil
  defp job(value) when is_reference(value), do: value |> :erlang.ref_to_list() |> List.to_string()
  defp job(_), do: nil
  defp classify(nil), do: nil
  defp classify(:ok), do: "ok"
  defp classify({:ok, _}), do: "ok"
  defp classify({:ok, _, _}), do: "ok"
  defp classify({:error, reason}) when reason in @errors, do: Atom.to_string(reason)
  defp classify({:error, _}), do: "other_error"
  defp classify({:unknown, _}), do: "unknown"
  defp classify(_), do: "other"
end
