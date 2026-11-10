defmodule Ipse.Extension.ValidatedMemo do
  @moduledoc """
  Bounded reuse of pure validation over exact, freshly read protected bytes.

  Protected owners still acquire their native locks and read and hash every
  byte they read before this memo is consulted. Only the deterministic work on
  those verified inputs is reused:

    * Collection: block unpacking, canonical re-encoding and state validation,
      keyed by directory, project, storage profile and manifest SHA-256. The
      manifest commits to every block hash; the caller still reads and checks
      each block and compares the hash set with the stored one.
    * ReadView: record checks, key index, entry seals and the encoded bound,
      keyed by the SHA-256 of the installed cache's deterministic encoding.
    * Consent: control-ledger decoding and validation, keyed by project and the
      SHA-256 of the exact `control.json` bytes.

  A caller admits an entry only after its own complete validation succeeded;
  refusals are never stored. A missing table or process falls back to complete
  validation. This stores no lock, capability, consent decision, deadline or
  source authority. Entries are bounded in count and encoded size; there is no
  time-based expiry because each value is a deterministic function of its key.
  """
  use GenServer

  @table __MODULE__
  @entries 8
  @entry_bytes 32 * 1024 * 1024

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Return a previously admitted reconstruction for this exact key."
  def fetch(key) do
    case :ets.whereis(@table) do
      :undefined ->
        :error

      table ->
        case :ets.lookup(table, key) do
          [{^key, value}] -> {:ok, value}
          _ -> :error
        end
    end
  rescue
    ArgumentError -> :error
  end

  @doc "Offer one fully validated value; admission is optional and never fails the caller."
  def put(key, value) do
    if Process.whereis(__MODULE__) != nil and :erlang.external_size(value) <= @entry_bytes,
      do: GenServer.call(__MODULE__, {:put, key, value}, 5_000)

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
  def handle_call({:put, key, value}, _, order) do
    if :ets.insert_new(@table, {key, value}) do
      order = :queue.in(key, order)

      if :queue.len(order) > @entries do
        {{:value, oldest}, order} = :queue.out(order)
        :ets.delete(@table, oldest)
        {:reply, :ok, order}
      else
        {:reply, :ok, order}
      end
    else
      {:reply, :ok, order}
    end
  end

  @impl true
  def format_status(status) do
    Map.new(status, fn
      {:state, order} -> {:state, %{entries: :queue.len(order)}}
      {:message, _} -> {:message, :redacted}
      pair -> pair
    end)
  end
end
