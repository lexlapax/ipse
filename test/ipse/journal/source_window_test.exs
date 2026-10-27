defmodule Ipse.Journal.SourceWindowTest do
  use ExUnit.Case, async: false
  alias Ipse.Journal
  alias Ipse.Journal.Writer
  alias Ipse.Session.{Saved, Input}

  test "owner-only projection advances after append success, never after source refusal" do
    directory = Path.join(System.tmp_dir!(), "ipse-writer-sources-" <> Ipse.Usage.id())
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    {:ok, id} = Journal.create(directory, %{})
    {:ok, events} = Journal.load(directory, id)
    {:ok, saved} = Saved.restore(events, id)
    {:ok, writer} = Writer.start(directory, id, self())
    on_exit(fn -> if Process.alive?(writer), do: Writer.close(writer) end)
    assert :ok = Writer.install_source_window(writer, saved.source_window)
    assert {:ok, before} = Writer.source_query(writer, :snapshot)

    input =
      Input.received(id, Ipse.Usage.id(), String.duplicate("x", 1_048_576), "effective", nil)

    assert {:error, :journal_record_refused} = Writer.append_with_source(writer, input)
    assert {:ok, ^before} = Writer.source_query(writer, :snapshot)
    assert :sys.get_state(writer).source_window.pending == %{}
    input = Input.received(id, Ipse.Usage.id(), "admitted original", "effective", nil)
    assert :ok = Writer.append(writer, input)

    assert :ok =
             Writer.append(writer, %{
               "type" => "message",
               "message" => %{"role" => "user", "content" => "effective"}
             })

    assert {:ok, after_append} = Writer.source_query(writer, :snapshot)
    assert after_append["count"] == 1

    assert {:error, _} =
             Task.async(fn -> Writer.source_query(writer, {"source.list", %{"limit" => 1}}) end)
             |> Task.await()

    assert :ok = Writer.close(writer)
  end
end
