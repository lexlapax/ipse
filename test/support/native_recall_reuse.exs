defmodule NativeRecallReuse do
  @moduledoc false
  # Deliver worker input directly and report which records each native
  # managed-record batch read, so a control can tell a reused result from a
  # native one while every later check still decides the outcome. `traced/2`
  # also reports each domain-auth lease a pass held: how long it lasted, how many
  # verifications were asked of it and which distinct pages those named.
  import ExUnit.Assertions
  alias Ipse.Extension.Collection.ObservedRead
  alias Ipse.Extension.ProjectIdentity.DomainAuth
  alias Ipse.Session.{ManagedReference, ManagedUse}

  def start do
    Code.ensure_loaded!(ObservedRead)
    Code.ensure_loaded!(DomainAuth)
    counter = spawn_link(fn -> collect([], []) end)
    assert 1 == :erlang.trace_pattern({ObservedRead, :managed_records_coalesced, 5}, true, [])
    assert 1 == :erlang.trace_pattern({DomainAuth, :verify, 4}, true, [])
    returned = [{:_, [], [{:return_trace}]}]
    assert 1 == :erlang.trace_pattern({DomainAuth, :with_auth, 6}, returned, [])
    counter
  end

  defp collect(batches, leases) do
    receive do
      {:trace_ts, _, :call, {ObservedRead, :managed_records_coalesced, [_, _, requests, _, _]}, _} ->
        collect(
          [Enum.map(requests, fn {request, _recipe} -> request["key"] end) | batches],
          leases
        )

      {:trace_ts, pid, :call, {DomainAuth, :with_auth, _}, at} ->
        collect(batches, [{pid, :open, at} | leases])

      {:trace_ts, pid, :call, {DomainAuth, :verify, [_, context, body, tag]}, _} ->
        item = {context["kind"], context, :erlang.md5([tag, body]), byte_size(body)}
        collect(batches, [{pid, :verify, item} | leases])

      {:trace_ts, pid, :return_from, {DomainAuth, :with_auth, 6}, _, at} ->
        collect(batches, [{pid, :close, at} | leases])

      {:take, caller} ->
        send(caller, {:native_trace, Enum.reverse(batches), Enum.reverse(leases)})
        collect([], [])

      _ ->
        collect(batches, leases)
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

    {result, batches, _leases} =
      traced(counter, fn ->
        ManagedUse.with_worker_dependencies(context, dependencies, capture)
      end)

    entered =
      receive do
        {:reuse_input_delivered, ^ticket} -> true
      after
        0 -> false
      end

    {result, batches, entered}
  end

  @doc """
  Run `fun` and return its result, the record keys of each native batch and one
  map for each domain-auth lease in order: its milliseconds, the verifications
  asked of it, how many were distinct, and the distinct page count and body
  bytes of each page kind.
  """
  def traced(counter, fun) do
    flags = [:call, :set_on_spawn, :monotonic_timestamp]
    assert 1 == :erlang.trace(self(), true, [{:tracer, counter} | flags])
    result = fun.()
    assert 1 == :erlang.trace(self(), false, flags)
    delivered = :erlang.trace_delivered(:all)
    assert_receive {:trace_delivered, :all, ^delivered}, 5_000
    send(counter, {:take, self()})
    assert_receive {:native_trace, batches, events}, 5_000

    {leases, open} =
      Enum.reduce(events, {[], %{}}, fn
        {pid, :open, at}, {leases, open} ->
          {leases, Map.put(open, pid, {at, []})}

        {pid, :verify, item}, {leases, open} when is_map_key(open, pid) ->
          {leases, Map.update!(open, pid, fn {at, items} -> {at, [item | items]} end)}

        {pid, :close, at}, {leases, open} when is_map_key(open, pid) ->
          {{from, items}, open} = Map.pop!(open, pid)
          spent = System.convert_time_unit(at - from, :native, :millisecond)
          {[lease(spent, items) | leases], open}

        _, acc ->
          acc
      end)

    # A lease whose callback raised has no return; report it without a duration.
    unfinished = for {_, {_, items}} <- open, do: lease(nil, items)
    {result, batches, Enum.reverse(leases) ++ unfinished}
  end

  defp lease(spent, items) do
    distinct = Enum.uniq(items)

    pages =
      distinct
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 3))
      |> Map.new(fn {kind, sizes} -> {kind, [length(sizes), Enum.sum(sizes)]} end)

    %{
      "ms" => spent,
      "verifications" => length(items),
      "distinct" => length(distinct),
      "pages" => pages
    }
  end
end
