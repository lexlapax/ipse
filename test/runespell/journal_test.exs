defmodule Runespell.JournalTest do
  use ExUnit.Case, async: true

  alias Runespell.Journal

  setup do
    dir = Path.join(System.tmp_dir!(), "runespell-journal-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "creates protected JSONL sessions, appends events, and lists metadata", %{dir: dir} do
    assert {:ok, id} = Journal.create(dir, %{"task" => "demo"})
    assert Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
    assert :ok = Journal.append(dir, id, %{"type" => "message", "text" => "hello"})
    assert {:ok, [session, message]} = Journal.load(dir, id)
    assert session["metadata"] == %{"task" => "demo"}
    assert message["text"] == "hello"
    assert [%{"id" => ^id, "metadata" => %{"task" => "demo"}}] = Journal.list(dir)
    assert {:ok, %{mode: directory_mode}} = File.stat(dir)
    assert Bitwise.band(directory_mode, 0o777) == 0o700
    assert {:ok, %{mode: file_mode}} = File.stat(Path.join(dir, id <> ".jsonl"))
    assert Bitwise.band(file_mode, 0o777) == 0o600
  end

  test "load tolerates a truncated last line, while append refuses to extend it", %{dir: dir} do
    assert {:ok, id} = Journal.create(dir, %{})
    path = Path.join(dir, id <> ".jsonl")
    File.write!(path, "{\"type\":", [:append])

    assert {:ok, [%{"type" => "session"}]} = Journal.load(dir, id)
    assert {:error, :incomplete_journal} = Journal.append(dir, id, %{"type" => "next"})
    assert :ok = Journal.repair_tail(dir, id)
    assert :ok = Journal.append(dir, id, %{"type" => "next"})
    assert {:ok, [%{"type" => "session"}, %{"type" => "next"}]} = Journal.load(dir, id)
  end

  test "rejects traversal IDs and corruption before the final line", %{dir: dir} do
    assert {:error, :invalid_id} = Journal.load(dir, "../outside")
    assert {:ok, id} = Journal.create(dir, %{})
    path = Path.join(dir, id <> ".jsonl")
    File.write!(path, "not-json\n{\"type\":\"last\"}\n")

    assert {:error, {:corrupt_journal, _}} = Journal.load(dir, id)
    assert {:error, {:corrupt_journal, _}} = Journal.append(dir, id, %{"type" => "next"})
    assert {:error, {:corrupt_journal, _}} = Journal.repair_tail(dir, id)
  end

  test "repair preserves a valid final record missing only its newline", %{dir: dir} do
    {:ok, id} = Journal.create(dir, %{})
    File.write!(Path.join(dir, id <> ".jsonl"), "{\"type\":\"valid\"}", [:append])
    assert :ok = Journal.repair_tail(dir, id)
    assert {:ok, [_, %{"type" => "valid"}]} = Journal.load(dir, id)
    assert :ok = Journal.append(dir, id, %{"type" => "next"})
  end
end
