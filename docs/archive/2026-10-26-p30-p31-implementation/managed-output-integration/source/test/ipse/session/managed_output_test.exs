defmodule Ipse.Session.ManagedOutputTest do
  use ExUnit.Case, async: false
  alias Ipse.Journal
  alias Ipse.Journal.Writer
  alias Ipse.Session.{ManagedLineage, ManagedOutput, Turn}

  test "a real journal append crossing the release deadline cannot notify tool text" do
    directory = Path.join(System.tmp_dir!(), "ipse-output-clock-" <> Ipse.Usage.id())
    File.mkdir_p!(directory)
    File.chmod!(directory, 0o700)
    on_exit(fn -> File.rm_rf!(directory) end)
    assert {:ok, id} = Journal.create(directory, %{})
    assert {:ok, writer} = Writer.start(directory, id, self())
    {:ok, lineage} = ManagedLineage.new(id)
    call = %{"id" => "read", "function" => %{"name" => "fixture.read"}}
    message = %{"role" => "tool", "tool_call_id" => "read", "content" => "HELD_TEXT"}

    state = %{
      journal_writer: writer,
      subscriber: self(),
      draft_lineages: [],
      observation: nil,
      feeds: Ipse.Extension.Feeds.new([], id),
      draft: nil,
      tool_lifecycle: nil,
      messages: [],
      managed_lineage: lineage,
      calls: [call],
      tool_decision: "not_decided"
    }

    :ok = :sys.suspend(writer)
    deadline = System.system_time(:millisecond) + 100

    resumer =
      spawn_monitor(fn ->
        Process.sleep(150)
        :ok = :sys.resume(writer)
      end)

    assert {:error, withheld} = Turn.commit_tool_result(state, call, message, deadline)
    assert System.system_time(:millisecond) >= deadline
    assert withheld.calls == [call]
    assert withheld.messages == [message]
    refute_receive {:ipse, _, {:tool_result, _, _}}
    {pid, ref} = resumer
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert :ok = Writer.close(writer)

    assert {:ok, [_header, %{"type" => "message", "message" => ^message}]} =
             Journal.load(directory, id)
  end

  test "fresh output layout rejects null and unknown declarations" do
    assert {:ok, nil} = ManagedOutput.marker(%{})
    assert {:ok, _} = ManagedOutput.marker(%{"managed_output_layout" => ManagedOutput.layout()})

    for value <- [nil, "future", 1, %{}] do
      assert {:error, :managed_output_unavailable} =
               ManagedOutput.marker(%{"managed_output_layout" => value})
    end
  end
end
