defmodule Ipse.JournalReservationsTest do
  use ExUnit.Case, async: false
  alias Ipse.Journal
  alias Ipse.Journal.{Limits, Writer}

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-journal-reservations-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  defp create(c, policy \\ nil) do
    assert {:ok, id} = Journal.create(c.root, %{})
    assert {:ok, writer} = Writer.start(c.root, id, self(), policy)
    {writer, id, Path.join(c.root, id <> ".jsonl")}
  end

  defp bytes(event), do: byte_size(Jason.encode!(event)) + 1

  test "reserved appends charge exact UTF-8 JSONL bytes and events", c do
    {writer, id, path} = create(c)
    first = %{"type" => "first", "value" => "雪\n\""}
    second = %{"type" => "second"}
    before = File.stat!(path).size

    assert {:ok, token} =
             Writer.reserve(writer, %{bytes: bytes(first) + bytes(second), events: 2})

    assert is_reference(token)
    assert :ok = Writer.append_reserved(writer, token, first)
    assert File.stat!(path).size == before + bytes(first)
    assert :ok = Writer.append_reserved(writer, token, second)
    assert File.stat!(path).size == before + bytes(first) + bytes(second)

    assert {:error, :journal_reservation_exhausted} =
             Writer.append_reserved(writer, token, %{})

    assert :ok = Writer.release(writer, token)
    assert :ok = Writer.close(writer)
    assert {:ok, [_, ^first, ^second]} = Journal.load(c.root, id)
  end

  test "ordinary appends cannot consume reserved byte capacity or seal the writer", c do
    {writer, id, path} = create(c, %{"max_bytes" => 1_024})
    remaining = 1_024 - File.stat!(path).size - Limits.reserve_bytes()
    event = %{"type" => "reserved", "value" => String.duplicate("x", remaining - 31)}
    assert bytes(event) == remaining
    before = File.read!(path)
    assert {:ok, token} = Writer.reserve(writer, %{bytes: remaining, events: 1})

    assert {:error, :journal_reservation_unavailable} =
             Writer.append(writer, %{"type" => "ordinary"})

    assert File.read!(path) == before
    assert :ok = Writer.append_reserved(writer, token, event)
    assert :ok = Writer.release(writer, token)
    assert {:error, :journal_limit_reached} = Writer.append(writer, %{})
    assert :ok = Writer.close(writer)
    assert {:ok, [_, ^event, receipt]} = Journal.load(c.root, id)
    assert Limits.valid_receipt?(receipt)
    assert File.stat!(path).size <= 1_024
  end

  test "ordinary appends cannot consume reserved event capacity", c do
    {writer, id, path} = create(c, %{"max_events" => 4})
    event = %{"type" => "reserved"}
    assert {:ok, token} = Writer.reserve(writer, %{bytes: bytes(event) * 2, events: 2})
    before = File.read!(path)

    assert {:error, :journal_reservation_unavailable} = Writer.append(writer, %{})
    assert File.read!(path) == before
    assert :ok = Writer.append_reserved(writer, token, event)
    assert :ok = Writer.append_reserved(writer, token, event)
    assert :ok = Writer.release(writer, token)
    assert {:error, :journal_limit_reached} = Writer.append(writer, %{})
    assert :ok = Writer.close(writer)
    assert {:ok, [_, ^event, ^event, receipt]} = Journal.load(c.root, id)
    assert Limits.valid_receipt?(receipt)
  end

  test "ordinary appends use unreserved capacity without moving source offsets", c do
    {writer, _, path} = create(c)
    reserved = %{"type" => "reserved"}
    ordinary = %{"type" => "ordinary"}
    assert {:ok, token} = Writer.reserve(writer, %{bytes: bytes(reserved), events: 1})
    before = File.stat!(path).size
    assert {:ok, source} = Writer.append_with_source(writer, ordinary)
    assert source["byte_offset"] == before
    assert :ok = Writer.append_reserved(writer, token, reserved)
    assert :ok = Writer.release(writer, token)
    assert :ok = Writer.close(writer)
  end

  test "cancellation releases unused capacity but retains physically written bytes", c do
    {writer, id, path} = create(c, %{"max_events" => 5})
    event = %{"type" => "orphan"}
    assert {:ok, token} = Writer.reserve(writer, %{bytes: bytes(event) * 3, events: 3})
    assert :ok = Writer.append_reserved(writer, token, event)
    before = File.read!(path)
    assert :ok = Writer.release(writer, token)
    assert File.read!(path) == before
    assert :ok = Writer.append(writer, %{"type" => "cancelled"})
    assert :ok = Writer.append(writer, %{"type" => "later"})
    assert :ok = Writer.close(writer)

    assert {:ok, [_, ^event, %{"type" => "cancelled"}, %{"type" => "later"}]} =
             Journal.load(c.root, id)
  end

  test "a reserved final receipt can be observed at its actual physical offset", c do
    {writer, _, path} = create(c)
    private = %{"type" => "private_source_chunk", "data" => "unobserved"}
    receipt = %{"type" => "public_receipt", "output_id" => "fixture"}
    before = File.stat!(path).size

    assert {:ok, token} =
             Writer.reserve(writer, %{bytes: bytes(private) + bytes(receipt), events: 2})

    assert :ok = Writer.append_reserved(writer, token, private)
    assert {:ok, reference} = Writer.append_reserved_observed(writer, token, receipt)
    assert reference["byte_offset"] == before + bytes(private)
    assert :ok = Writer.release(writer, token)
    assert :ok = Writer.close(writer)
  end

  test "malformed and excessive reservations refuse without writing or sealing", c do
    {writer, _, path} = create(c, %{"max_bytes" => 1_024, "max_events" => 4})
    before = File.read!(path)

    for capacity <- [
          nil,
          %{},
          %{bytes: 1, events: 1},
          %{bytes: 3, events: 0},
          %{bytes: 3.0, events: 1},
          %{bytes: 3, events: 1, extra: true}
        ] do
      assert {:error, :journal_reservation_invalid} = Writer.reserve(writer, capacity)
    end

    for capacity <- [%{bytes: 1_024, events: 1}, %{bytes: 9, events: 3}] do
      assert {:error, :journal_reservation_unavailable} = Writer.reserve(writer, capacity)
    end

    assert File.read!(path) == before
    assert :ok = Writer.append(writer, %{"type" => "still writable"})
    assert :ok = Writer.close(writer)
  end

  test "every reservation is included in admission and released independently", c do
    {writer, _, _} = create(c, %{"max_events" => 4})
    event = %{}
    assert {:ok, first} = Writer.reserve(writer, %{bytes: bytes(event), events: 1})
    assert {:ok, second} = Writer.reserve(writer, %{bytes: bytes(event), events: 1})

    assert {:error, :journal_reservation_unavailable} =
             Writer.reserve(writer, %{bytes: bytes(event), events: 1})

    assert :ok = Writer.release(writer, first)
    assert :ok = Writer.append(writer, event)
    assert :ok = Writer.append_reserved(writer, second, event)
    assert :ok = Writer.release(writer, second)
    assert :ok = Writer.close(writer)
  end

  test "token, byte, event and record errors leave reservation capacity intact", c do
    {writer, _, path} = create(c, %{"max_record_bytes" => 512})
    event = %{"type" => "reserved"}
    assert {:ok, token} = Writer.reserve(writer, %{bytes: 1_000, events: 1})
    before = File.read!(path)

    assert {:error, :journal_reservation_invalid} =
             Writer.append_reserved(writer, make_ref(), event)

    assert {:error, :journal_reservation_invalid} = Writer.release(writer, make_ref())

    assert {:error, :journal_record_refused} =
             Writer.append_reserved(writer, token, %{"padding" => String.duplicate("x", 513)})

    assert {:error, :journal_record_refused} =
             Writer.append_reserved(writer, token, %{"type" => "journal_limit_reached"})

    assert {:error, :journal_record_refused} =
             Writer.append_reserved(writer, token, %{"invalid" => self()})

    assert File.read!(path) == before
    assert :ok = Writer.append_reserved(writer, token, event)
    assert {:error, :journal_reservation_exhausted} = Writer.append_reserved(writer, token, %{})
    assert :ok = Writer.release(writer, token)
    assert {:ok, small} = Writer.reserve(writer, %{bytes: 3, events: 1})
    assert {:error, :journal_reservation_exhausted} = Writer.append_reserved(writer, small, event)
    assert :ok = Writer.append_reserved(writer, small, %{})
    assert :ok = Writer.release(writer, small)
    assert :ok = Writer.close(writer)
  end

  test "all reservation methods reject callers other than the writer owner", c do
    {writer, _, path} = create(c)
    assert {:ok, token} = Writer.reserve(writer, %{bytes: 3, events: 1})
    before = File.read!(path)

    task =
      Task.async(fn ->
        [
          Writer.reserve(writer, %{bytes: 3, events: 1}),
          Writer.append_reserved(writer, token, %{}),
          Writer.release(writer, token)
        ]
      end)

    assert Task.await(task) == List.duplicate({:error, :journal_owner_or_record_invalid}, 3)
    assert File.read!(path) == before
    assert :ok = Writer.append_reserved(writer, token, %{})
    assert :ok = Writer.release(writer, token)
    assert :ok = Writer.close(writer)
  end

  test "reservation tokens do not survive writer restart", c do
    {writer, id, _} = create(c, %{"max_events" => 3})
    assert {:ok, token} = Writer.reserve(writer, %{bytes: 3, events: 1})
    assert :ok = Writer.close(writer)
    assert {:ok, restarted} = Writer.start(c.root, id, self(), %{"max_events" => 3})
    assert {:error, :journal_reservation_invalid} = Writer.append_reserved(restarted, token, %{})
    assert {:error, :journal_reservation_invalid} = Writer.release(restarted, token)
    assert :ok = Writer.append(restarted, %{})
    assert :ok = Writer.close(restarted)
  end

  test "changed journals retain the existing unconfirmed-write boundary", c do
    {writer, _, path} = create(c)
    assert {:ok, token} = Writer.reserve(writer, %{bytes: 3, events: 1})
    File.write!(path, "{}\n", [:append])
    before = File.read!(path)
    assert {:error, :journal_write_unconfirmed} = Writer.append_reserved(writer, token, %{})
    assert File.read!(path) == before
  end
end
