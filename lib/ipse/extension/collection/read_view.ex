defmodule Ipse.Extension.Collection.ReadView do
  @moduledoc """
  Internal owner-task cache of an already validated immutable Collection index.

  A view grants no policy, source, Session or managed-record authority. It retains
  no file descriptor. Each selected read still runs through Collection's actual
  native owner and exact current root check. Version 2 distinguishes a native
  absent-root observation from a present root; absence has no fabricated hash
  and must be reconfirmed on every read. The 4 MiB bound is encoded metadata;
  bounded maps, seals and process/heap overhead are additional. At most 16 caches,
  one per original task, live for 60 seconds and admit at most 512 reads each.

  Trusted core processes and cooperative protected storage are assumed. Opaque
  references and exact original file-effect-owner checks prevent JSON handles or
  accidental cross-task use; they do not isolate hostile code in the same BEAM.
  Closing or expiry invalidates the cache, not proof that in-flight IO finished.
  The actual resource owner remains responsible for cancellation/cleanup.
  """
  use GenServer
  alias Ipse.{JSON, Session.Resources}
  alias Ipse.Extension.Collection.Directory
  @bytes 4_194_304
  @reads 512
  @observations 512
  @lifetime 60_000
  @records 8192
  @error {:error, :collection_view_unavailable}
  @cache_keys ~w(version collection_root project root_state root_bytes root_sha256 manifest_sha256 summary records)
  @summary_keys ~w(version project generation floor floor_anchor)
  @record_keys ~w(key revision sha256 bytes operation_id)
  @effect_owner {Resources, :effect_owner}
  @active_effect {Resources, :active}

  defstruct [:owner, :server, :ref]

  defimpl Inspect do
    def inspect(_, _), do: "#Collection.ReadView<private>"
  end

  def limits,
    do: %{
      cache_bytes: @bytes,
      records: @records,
      reads: @reads,
      observation_units: @observations,
      lifetime_ms: @lifetime,
      caches: 16,
      batch: 8,
      reply_bytes: 65_536
    }

  @doc false
  def begin do
    owner = Resources.file_effect_owner()

    with true <- is_pid(owner) and Process.alive?(owner),
         true <- owner === self() or Process.get(@active_effect) === true,
         {:ok, server} <- GenServer.start(__MODULE__, owner),
         {:ok, handle} <- GenServer.call(server, :handle) do
      {:ok, handle}
    else
      {:error, {:already_started, _}} ->
        {:error, :collection_view_exists}

      {:error, reason} when reason in [:collection_view_exists, :collection_view_capacity] ->
        {:error, reason}

      _ ->
        @error
    end
  catch
    :exit, _ -> @error
  end

  @doc false
  def install(view, cache), do: call(view, {:install, cache})
  @doc false
  def borrow(view, request), do: call(view, {:borrow, request})
  @doc false
  def finish(view, token, result), do: call(view, {:finish, token, result})

  def close(%__MODULE__{server: server} = view) when is_pid(server) do
    monitor = Process.monitor(server)

    try do
      case call(view, :close) do
        :ok ->
          receive do
            {:DOWN, ^monitor, :process, ^server, _} -> :ok
          after
            5_000 -> @error
          end

        error ->
          error
      end
    after
      Process.demonitor(monitor, [:flush])
    end
  end

  def close(_), do: @error

  defp call(%__MODULE__{owner: owner, server: server, ref: ref}, operation) do
    with true <- is_pid(owner) and is_pid(server) and is_reference(ref),
         true <- Resources.file_effect_owner() === owner,
         [{^server, _}] <- Registry.lookup(Ipse.Registry, {__MODULE__, owner}),
         true <- Process.alive?(server) do
      GenServer.call(server, {ref, operation}, 5_000)
    else
      _ -> @error
    end
  catch
    :exit, _ -> @error
  end

  defp call(_, _), do: @error

  @impl true
  def init(owner) do
    with {:ok, _} <- Registry.register(Ipse.Registry, {__MODULE__, owner}, nil),
         slot when is_integer(slot) <-
           Enum.find(0..15, fn slot ->
             match?({:ok, _}, Registry.register(Ipse.Registry, {__MODULE__, :slot, slot}, nil))
           end) do
      ref = make_ref()
      Process.send_after(self(), :expire, @lifetime)

      {:ok,
       %{
         owner: owner,
         owner_monitor: Process.monitor(owner),
         ref: ref,
         deadline: now() + @lifetime,
         cache: nil,
         header_seal: nil,
         entry_seals: nil,
         index: nil,
         keys_seal: nil,
         reads: 0,
         observations: 0,
         busy: nil,
         slot: slot
       }}
    else
      {:error, {:already_registered, _}} -> {:stop, :collection_view_exists}
      _ -> {:stop, :collection_view_capacity}
    end
  end

  @impl true
  def handle_call(:handle, {caller, _}, state) do
    if authorized?(state, caller),
      do: {:reply, {:ok, %__MODULE__{owner: state.owner, server: self(), ref: state.ref}}, state},
      else: {:reply, @error, state}
  end

  def handle_call({ref, operation}, {caller, _}, %{ref: ref} = state) do
    cond do
      not authorized?(state, caller) -> {:reply, @error, state}
      now() >= state.deadline -> {:stop, :normal, {:error, :collection_view_expired}, state}
      true -> operate(operation, caller, state)
    end
  end

  def handle_call(_, _, state), do: {:reply, @error, state}

  defp operate({:install, cache}, _, %{cache: nil, busy: nil} = state) do
    with true <- cache?(cache),
         keys = cache["records"] |> Map.keys() |> Enum.sort(),
         {:ok, index} <- Directory.index(keys),
         seals = Map.new(cache["records"], fn {key, ref} -> {key, JSON.digest([ref])} end),
         true <-
           byte_size(Jason.encode!(%{"cache" => cache, "keys" => keys, "seals" => seals})) <=
             @bytes do
      header = Map.delete(cache, "records")

      {:reply, :ok,
       %{
         state
         | cache: cache,
           header_seal: JSON.digest([header]),
           entry_seals: seals,
           index: index,
           keys_seal: JSON.digest([keys])
       }}
    else
      _ -> {:stop, :normal, {:error, :collection_view_capacity}, state}
    end
  rescue
    _ -> {:stop, :normal, @error, state}
  end

  defp operate({:borrow, request}, caller, %{busy: nil, cache: cache} = state)
       when not is_nil(cache) do
    case Directory.cost(request) do
      {:ok, cost} when state.reads < @reads and state.observations + cost <= @observations ->
        charged = %{state | reads: state.reads + 1, observations: state.observations + cost}
        borrow_selected(request, caller, charged)

      {:ok, _} ->
        {:stop, :normal, {:error, :collection_view_capacity}, state}

      _ ->
        {:reply, {:error, :invalid_collection_view_request}, state}
    end
  end

  defp operate({:borrow, _}, _, state), do: {:reply, {:error, :collection_view_busy}, state}

  defp operate(
         {:finish, token, :ok},
         caller,
         %{busy: %{caller: caller, token: token, monitor: monitor}} = state
       ) do
    Process.demonitor(monitor, [:flush])
    {:reply, :ok, %{state | busy: nil}}
  end

  defp operate({:finish, token, _}, caller, %{busy: %{caller: caller, token: token}} = state),
    do: {:stop, :normal, :ok, state}

  defp operate(:close, _, state), do: {:stop, :normal, :ok, state}
  defp operate(_, _, state), do: {:reply, @error, state}

  defp borrow_selected(request, caller, %{cache: cache} = state) do
    with true <- JSON.digest([Map.delete(cache, "records")]) === state.header_seal,
         keys = Directory.keys(state.index),
         true <- JSON.digest([keys]) === state.keys_seal,
         true <- keys === Enum.sort(Map.keys(cache["records"])),
         true <- matching_seals?(state, request),
         {:ok, selected, next, neighbors} <-
           Directory.select(state.index, request, cache["root_state"]),
         true <- Enum.all?(selected, &entry_sealed?(state, &1)) do
      token = make_ref()

      payload =
        cache
        |> Map.put("records", Map.take(cache["records"], selected))
        |> Map.put("selected", selected)
        |> Map.put("next", next)
        |> Map.put("neighbors", neighbors)
        |> Map.put(
          "expected_generation",
          if(request["op"] == "visible_scan", do: request["generation"])
        )
        |> Map.put("neighbor_request", if(neighbors, do: request["request"]))

      {:reply, {:ok, token, payload},
       %{state | busy: %{caller: caller, token: token, monitor: Process.monitor(caller)}}}
    else
      _ -> {:stop, :normal, {:error, :collection_view_corrupt}, state}
    end
  rescue
    _ -> {:stop, :normal, {:error, :collection_view_corrupt}, state}
  end

  defp matching_seals?(state, %{"op" => "neighbors", "request" => %{"prefix" => prefix}}),
    do: Enum.all?(Directory.matching(state.index, prefix), &entry_sealed?(state, &1))

  defp matching_seals?(_, _), do: true

  defp entry_sealed?(state, key) do
    case state.cache["records"][key] do
      nil -> not Map.has_key?(state.entry_seals, key)
      ref -> JSON.digest([ref]) === state.entry_seals[key]
    end
  end

  def valid_request?(request), do: Directory.read_request?(request)

  defp cache?(cache) do
    keys?(cache, @cache_keys) and cache["version"] === 2 and
      is_binary(cache["collection_root"]) and byte_size(cache["collection_root"]) <= 4096 and
      Path.type(cache["collection_root"]) == :absolute and
      JSON.sha256?(cache["project"]) and root_matches?(cache) and
      keys?(cache["summary"], @summary_keys) and cache["summary"]["version"] === 3 and
      cache["summary"]["project"] === cache["project"] and
      JSON.safe_uint?(cache["summary"]["generation"]) and
      JSON.safe_uint?(cache["summary"]["floor"]) and
      ((cache["summary"]["floor"] === 0 and is_nil(cache["summary"]["floor_anchor"])) or
         (cache["summary"]["floor"] > 0 and id?(cache["summary"]["floor_anchor"]))) and
      is_map(cache["records"]) and map_size(cache["records"]) <= @records and
      Enum.all?(cache["records"], fn {key, ref} ->
        key?(key) and keys?(ref, @record_keys) and ref["key"] === key and
          JSON.safe_uint?(ref["revision"]) and ref["revision"] > 0 and
          ref["revision"] <= cache["summary"]["generation"] and
          JSON.sha256?(ref["sha256"]) and is_integer(ref["bytes"]) and ref["bytes"] in 2..6144 and
          id?(ref["operation_id"])
      end)
  rescue
    _ -> false
  end

  defp root_matches?(%{"root_state" => "absent"} = cache) do
    is_nil(cache["root_bytes"]) and is_nil(cache["root_sha256"]) and
      is_nil(cache["manifest_sha256"]) and cache["records"] === %{} and
      cache["summary"] === %{
        "version" => 3,
        "project" => cache["project"],
        "generation" => 0,
        "floor" => 0,
        "floor_anchor" => nil
      }
  end

  defp root_matches?(%{"root_state" => "present"} = cache) do
    with true <- is_binary(cache["root_bytes"]) and byte_size(cache["root_bytes"]) <= 1024,
         true <- JSON.sha256(cache["root_bytes"]) === cache["root_sha256"],
         true <- JSON.sha256?(cache["manifest_sha256"]),
         {:ok, pointer} <- JSON.decode_unique(cache["root_bytes"]),
         true <- keys?(pointer, ~w(version project generation floor floor_anchor manifest)),
         true <- pointer["version"] in [4, 5],
         true <- pointer["manifest"] === cache["manifest_sha256"] do
      pointer |> Map.delete("manifest") |> Map.put("version", 3) === cache["summary"]
    else
      _ -> false
    end
  end

  defp root_matches?(_), do: false

  defp authorized?(state, caller) do
    Process.alive?(state.owner) and
      (caller === state.owner or effect_origin?(caller, state.owner))
  end

  # Inspect only the actual caller's two private lifetime markers. No supplied
  # owner argument, descendant chain or serialized value substitutes for these.
  defp effect_origin?(caller, owner) do
    case Process.info(caller, :dictionary) do
      {:dictionary, dictionary} ->
        List.keyfind(dictionary, @effect_owner, 0) === {@effect_owner, owner} and
          List.keyfind(dictionary, @active_effect, 0) === {@active_effect, true}

      _ ->
        false
    end
  end

  @impl true
  def handle_info(:expire, state), do: {:stop, :normal, state}

  def handle_info({:DOWN, monitor, :process, _, _}, state) when monitor == state.owner_monitor,
    do: {:stop, :normal, state}

  def handle_info({:DOWN, monitor, :process, _, _}, %{busy: %{monitor: monitor}} = state),
    do: {:stop, :normal, state}

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(_, state) do
    Registry.unregister(Ipse.Registry, {__MODULE__, state.owner})
    Registry.unregister(Ipse.Registry, {__MODULE__, :slot, state.slot})
    :ok
  end

  @impl true
  def format_status(%{state: _} = status) do
    Map.new(status, fn
      {key, _} when key in [:state, :message, :reason] -> {key, :redacted}
      {:log, _} -> {:log, []}
      pair -> pair
    end)
  end

  defp keys?(map, expected), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(expected)

  defp key?(key), do: Directory.key?(key)

  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)

  defp now, do: System.monotonic_time(:millisecond)
end
