defmodule Ipse.Extension.ValidatedMemo do
  @moduledoc """
  Bounded reuse of deterministic results over exact, freshly established inputs.

  The validating owners still acquire their native locks and read and hash
  every byte they read before this memo is consulted. Only the deterministic
  work on those verified inputs is reused. Each owner names a slot and tags its
  value with the hash of the exact input:

    * Collection: block unpacking, canonical re-encoding and state validation.
      The slot is the directory, project and storage profile; the tag is the
      manifest SHA-256. The manifest commits to every block hash; the caller
      still reads and checks each block and compares the hash set with the
      stored one.
    * ReadView: record checks, key index, entry seals and the encoded bound.
      The slot is the Collection root, project and storage profile; the tag is
      the SHA-256 of the installed cache's deterministic encoding.
    * Consent: control-ledger decoding and validation. The slot is the project;
      the tag is the SHA-256 of the exact `control.json` bytes.

  One owner reuses the result of an authenticated native read instead of a
  validation of bytes it has just read:

    * Worker-input managed records (`Ipse.Session.ManagedUse`): the exact
      native record results of the dependencies delivered to a worker, by
      observation key. The slot is the Collection root path, project and pin;
      the tag is the Collection root identity and the authenticated catalog.
      The root identity commits to every stored page and value, so a result
      read at that identity is what a new read would return. The owner never
      takes the root from here: each protected pass natively reads at least
      one record with its own capability and uses a remembered result only
      when that read names this tag. Time, policy and source checks run on
      every result in every pass, and the final native owner rechecks the
      root while it holds the Collection.

  A slot holds one value. Admitting a value for a different tag replaces the
  previous one. A validating owner admits on every successful validation, so
  a superseded Collection state does not stay in its slot after its successor
  validates. The worker-input slot is replaced only by the next worker-input
  pass for that pin. A record removed by a later commit can therefore stay in
  host memory until that pass or until eviction. It is never delivered: the
  pass's own native read names a different root, so the remembered results
  are not used.

  A caller admits a value only after its own complete validation succeeded;
  refusals are never stored. A missing table or process falls back to complete
  validation. This stores no lock, capability, consent decision, deadline or
  source authority. Slots are bounded in count and encoded size; there is no
  time-based expiry because each value is a deterministic function of its tag.
  """
  use GenServer

  @table __MODULE__
  @slots 8
  @entry_bytes 32 * 1024 * 1024

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Return the value admitted for this slot if it was admitted for this exact tag."
  def fetch(slot, tag) do
    case :ets.whereis(@table) do
      :undefined ->
        :error

      table ->
        case :ets.lookup(table, slot) do
          [{^slot, ^tag, value}] -> {:ok, value}
          _ -> :error
        end
    end
  rescue
    ArgumentError -> :error
  end

  @doc """
  Return the slot's tag and value so an owner can plan which inputs to read.

  The value is not yet usable: the owner must establish the same tag from a
  fresh protected read before relying on it.
  """
  def fetch(slot) do
    case :ets.whereis(@table) do
      :undefined ->
        :error

      table ->
        case :ets.lookup(table, slot) do
          [{^slot, tag, value}] -> {:ok, tag, value}
          _ -> :error
        end
    end
  rescue
    ArgumentError -> :error
  end

  @doc "Offer one fully validated value; admission is optional and never fails the caller."
  def put(slot, tag, value) do
    if Process.whereis(__MODULE__) != nil and :erlang.external_size(value) <= @entry_bytes,
      do: GenServer.call(__MODULE__, {:put, slot, tag, value}, 5_000)

    :ok
  catch
    :exit, _ -> :ok
  end

  @impl true
  def init(nil) do
    :ets.new(@table, [:set, :protected, :named_table, read_concurrency: true])
    {:ok, :queue.new()}
  end

  @impl true
  def handle_call({:put, slot, tag, value}, _, order) do
    known = :ets.member(@table, slot)
    :ets.insert(@table, {slot, tag, value})

    cond do
      known ->
        {:reply, :ok, order}

      :queue.len(order) >= @slots ->
        {{:value, oldest}, order} = :queue.out(order)
        :ets.delete(@table, oldest)
        {:reply, :ok, :queue.in(slot, order)}

      true ->
        {:reply, :ok, :queue.in(slot, order)}
    end
  end

  @impl true
  def format_status(status) do
    Map.new(status, fn
      {:state, order} -> {:state, %{slots: :queue.len(order)}}
      {:message, _} -> {:message, :redacted}
      pair -> pair
    end)
  end
end
