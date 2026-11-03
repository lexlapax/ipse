defmodule Ipse.Test.SourceTiming do
  @moduledoc false
  # Disposable synthetic diagnostic only. Never promote this module.
  @name :ipse_synthetic_source_timing
  @context {__MODULE__, :context}
  @limit 8192
  @stages ~w(egress observe_first observe_second source_lock source_scan source_index source_validate source_resolve source_origin_final source_unchanged source_lock_final source_live_final source_file_close source_unlock)a

  def start(path) do
    owner = self()
    sink = spawn(fn -> collect(owner, path) end)
    receive do
      {:source_timing_ready, ^sink} -> :ok
    after
      5_000 -> raise "source timing sink unavailable"
    end
    true = Process.register(sink, @name)
    sink
  end

  def scope(phase, fun) when is_function(fun, 0) do
    if phase == "model" and is_pid(Process.whereis(@name)) and is_pid(Ipse.Session.Resources.current()) do
      previous = Process.get(@context)
      token = make_ref()
      Process.put(@context, token)
      try do
        timed(:egress, fun)
      after
        barrier(token)
        if is_nil(previous), do: Process.delete(@context), else: Process.put(@context, previous)
      end
    else
      fun.()
    end
  end

  def shape(dependencies, proofs) when is_list(dependencies) and is_list(proofs) do
    if token = Process.get(@context) do
      versions = Map.new(3..7, fn version -> {Integer.to_string(version), Enum.count(dependencies, &(&1["version"] == version))} end)
      v4 = Enum.filter(dependencies, &(&1["version"] == 4))
      pairs = v4 |> Enum.map(&[get_in(&1, ["subject", "key"]), get_in(&1, ["subject", "record", "revision"])]) |> Enum.sort()
      unique_records = pairs |> Enum.uniq() |> length()
      sources = proofs |> Enum.map(& &1["session_id"]) |> Enum.uniq() |> length()
      send_event(token, %{"kind" => "shape", "at_us" => System.monotonic_time(:microsecond), "key_revision_sha256" => Ipse.JSON.digest([pairs]), "dependencies" => length(dependencies), "versions" => versions, "v4_records" => unique_records, "proofs" => length(proofs), "source_sessions" => sources})
    end
    :ok
  end

  def journal(bytes, event_count) when is_integer(bytes) and is_integer(event_count) do
    if token = Process.get(@context), do: send_event(token, %{"kind" => "journal", "bytes" => bytes, "events" => event_count})
    :ok
  end

  def cache(mode) when mode in [:none, :scoped, :unavailable] do
    if token = Process.get(@context), do: send_event(token, %{"kind" => "cache", "mode" => Atom.to_string(mode)})
    :ok
  end

  def timed(stage, fun) when stage in @stages and is_function(fun, 0) do
    case Process.get(@context) do
      nil -> fun.()
      token ->
        started = System.monotonic_time(:microsecond)
        send_event(token, %{"kind" => "start", "stage" => Atom.to_string(stage), "at_us" => started})
        try do
          result = fun.()
          send_event(token, %{"kind" => "finish", "stage" => Atom.to_string(stage), "at_us" => System.monotonic_time(:microsecond), "class" => classify(result)})
          result
        rescue
          error ->
            send_event(token, %{"kind" => "finish", "stage" => Atom.to_string(stage), "at_us" => System.monotonic_time(:microsecond), "class" => "exception"})
            reraise error, __STACKTRACE__
        catch
          kind, value ->
            send_event(token, %{"kind" => "finish", "stage" => Atom.to_string(stage), "at_us" => System.monotonic_time(:microsecond), "class" => "exception"})
            :erlang.raise(kind, value, __STACKTRACE__)
        end
    end
  end

  def stop(sink) do
    ref = make_ref()
    send(sink, {:stop, self(), ref})
    receive do
      {:source_timing_stopped, ^ref, summary} -> summary
    after
      5_000 -> raise "source timing sink did not stop"
    end
  end

  defp barrier(token) do
    case Process.whereis(@name) do
      nil -> :unavailable
      sink ->
        ref = make_ref()
        send(sink, {:barrier, self(), ref, token})
        receive do
          {:source_timing_barrier, ^ref} -> :ok
        after
          500 -> :unconfirmed
        end
    end
  end

  defp send_event(token, event) do
    if sink = Process.whereis(@name), do: send(sink, {:event, self(), token, event})
    :ok
  end

  defp collect(owner, path) do
    {:ok, file} = :file.open(String.to_charlist(path), [:write, :exclusive, :binary, :raw])
    File.chmod!(path, 0o600)
    monitor = Process.monitor(owner)
    send(owner, {:source_timing_ready, self()})
    loop(file, monitor, 0, 0)
  end

  defp loop(file, monitor, count, dropped) do
    receive do
      {:event, caller, token, event} ->
        entry = Map.merge(event, %{"pid" => inspect(caller), "token" => inspect(token)})
        {count, dropped} = put(file, entry, count, dropped)
        loop(file, monitor, count, dropped)
      {:barrier, caller, ref, token} ->
        {count, dropped} = put(file, %{"kind" => "barrier", "pid" => inspect(caller), "token" => inspect(token)}, count, dropped)
        send(caller, {:source_timing_barrier, ref})
        loop(file, monitor, count, dropped)
      {:stop, caller, ref} ->
        summary = %{"kind" => "summary", "events" => count, "dropped" => dropped, "closure" => "stop_received"}
        write(file, summary)
        :ok = :file.sync(file)
        :ok = :file.close(file)
        send(caller, {:source_timing_stopped, ref, summary})
      {:DOWN, ^monitor, :process, _, _} ->
        write(file, %{"kind" => "summary", "events" => count, "dropped" => dropped, "closure" => "owner_exit"})
        :file.sync(file)
        :file.close(file)
    end
  end

  defp put(file, event, count, dropped) when count < @limit do
    write(file, event)
    {count + 1, dropped}
  end
  defp put(_file, _event, count, dropped), do: {count, dropped + 1}
  defp write(file, event), do: :ok = :file.write(file, [Jason.encode!(event), "\n"])
  defp classify(:ok), do: "ok"
  defp classify(true), do: "ok"
  defp classify({:ok, _}), do: "ok"
  defp classify({:ok, _, _}), do: "ok"
  defp classify(false), do: "refused"
  defp classify({:error, _}), do: "refused"
  defp classify({:unknown, _}), do: "unknown"
  defp classify(_), do: "other"
end
