defmodule NativeRecallReuse do
  @moduledoc false
  # Deliver worker input directly and report which records each native
  # managed-record batch read, so a control can tell a reused result from a
  # native one while every later check still decides the outcome.
  import ExUnit.Assertions
  alias Ipse.Extension.Collection.ObservedRead
  alias Ipse.Session.{ManagedReference, ManagedUse}

  def start do
    Code.ensure_loaded!(ObservedRead)
    counter = spawn_link(fn -> collect([]) end)
    assert 1 == :erlang.trace_pattern({ObservedRead, :managed_records_coalesced, 5}, true, [])
    counter
  end

  defp collect(batches) do
    receive do
      {:trace, _, :call, {ObservedRead, :managed_records_coalesced, [_, _, requests, _, _]}} ->
        collect([Enum.map(requests, fn {request, _recipe} -> request["key"] end) | batches])

      {:take, caller} ->
        send(caller, {:native_batches, Enum.reverse(batches)})
        collect([])

      _ ->
        collect(batches)
    end
  end

  @doc "The distinct literal dependencies a Session recorded for its managed reads."
  def literals(events) do
    literals =
      for event <- events,
          event["type"] == "managed_read_observed",
          dependency <- event["dependencies"],
          dependency["version"] == 4,
          do: dependency

    union(Enum.uniq_by(literals, & &1["subject"]["key"]))
  end

  def union(dependencies) do
    assert {:ok, dependencies} = ManagedReference.union([dependencies])
    dependencies
  end

  @doc "Return the result, the record count of each native batch and whether input was delivered."
  def input(counter, context, dependencies) do
    {result, batches, entered} = input_keys(counter, context, dependencies)
    {result, Enum.map(batches, &length/1), entered}
  end

  @doc "Like `input/3`, naming the record keys each native batch read."
  def input_keys(counter, context, dependencies) do
    owner = self()
    ticket = make_ref()

    capture = fn current, held ->
      send(owner, {:reuse_input_delivered, ticket})
      {:ok, %{current: current, proofs: held.source_proofs}}
    end

    assert 1 == :erlang.trace(self(), true, [:call, :set_on_spawn, {:tracer, counter}])
    result = ManagedUse.with_worker_dependencies(context, dependencies, capture)
    assert 1 == :erlang.trace(self(), false, [:call, :set_on_spawn])
    delivered = :erlang.trace_delivered(:all)
    assert_receive {:trace_delivered, :all, ^delivered}, 5_000
    send(counter, {:take, self()})
    assert_receive {:native_batches, batches}, 5_000

    entered =
      receive do
        {:reuse_input_delivered, ^ticket} -> true
      after
        0 -> false
      end

    {result, batches, entered}
  end
end
