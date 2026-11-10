defmodule Ipse.Extension.ValidatedMemo do
  @moduledoc """
  Bounded reuse of pure validation over exact, freshly read protected bytes.

  Protected owners still acquire their native locks and read and hash every
  byte they read before this memo is consulted. Only the deterministic work on
  those verified inputs is reused. Each owner names a slot and tags its value
  with the hash of the exact input:

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

  A slot holds one value. Admitting a value for a different tag replaces the
  previous one, so a superseded Collection state, including a record removed
  by a later generation, does not stay here after its successor validates.

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
