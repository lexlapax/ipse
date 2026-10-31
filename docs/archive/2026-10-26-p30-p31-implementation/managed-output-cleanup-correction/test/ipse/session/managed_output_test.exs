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
    assert withheld.calls == []
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

  test "unknown cleanup withdraws the retained command display and publisher" do
    directory = Path.join(System.tmp_dir!(), "ipse-output-cleanup-" <> Ipse.Usage.id())
    File.mkdir_p!(directory)
    File.chmod!(directory, 0o700)
    on_exit(fn -> File.rm_rf!(directory) end)
    assert {:ok, id} = Journal.create(directory, %{})
    assert {:ok, writer} = Writer.start(directory, id, self())
    {:ok, lineage} = ManagedLineage.new(id)
    job = make_ref()

    for {phase, stage} <- [
          extension_command: "invoke.command",
          extension_service: "invoke.service"
        ] do
      parent = %{"invocation_id" => Ipse.Usage.id(), "identity" => %{"instance" => "knowledge"}}

      raw = %{
        "invocation_id" => parent["invocation_id"],
        "version" => 3,
        "actions_sha256" => Ipse.JSON.digest([]),
        "descriptor" => %{"stage" => stage, "name" => "ext__knowledge__fixture"},
        "value" => %{"text" => "MANAGED_COMMAND_TEXT"}
      }

      now = System.system_time(:millisecond)
      intent = ManagedOutput.intent(id, parent, raw, [], now, now + 1000)
      admission = ManagedOutput.admission(intent, raw, "current", [], now, now + 1000)
      current = ManagedOutput.display(raw, "current", [])

      state = %{
        id: id,
        phase: phase,
        journal_writer: writer,
        draft_lineages: [],
        observation: nil,
        feeds: Ipse.Extension.Feeds.new([], id),
        messages: [],
        draft: nil,
        managed_lineage: %{lineage | unavailable: true},
        task: %{pid: self()},
        job_ref: job,
        invocation: %Ipse.Session.Invocation{parent: parent},
        extension_result: current,
        extension_result_sources: %Ipse.Extension.ResultSource.Index{},
        extension_contributions: %{"knowledge" => %{"text" => "MANAGED_COMMAND_TEXT"}},
        managed_output_release: %{
          intent: intent,
          raw: raw,
          index: nil,
          job: job,
          worker: self(),
          parent: parent,
          actions_sha: Ipse.JSON.digest([]),
          admission: admission,
          cleanup: nil
        }
      }

      assert {:reply, :ok, next} =
               ManagedOutput.finish(state, self(), intent["release_id"], "unknown")

      assert next.extension_result == ManagedOutput.display(raw, "withdrawn", [])
      refute Jason.encode!(next.extension_result) =~ "MANAGED_COMMAND_TEXT"
      assert next.extension_contributions == %{}
      assert next.managed_output_release.cleanup == "unknown"
    end

    assert :ok = Writer.close(writer)
    assert {:ok, [_header | events]} = Journal.load(directory, id)
    assert length(events) == 2

    assert Enum.all?(
             events,
             &(&1["type"] == "managed_output_release_cleanup" and &1["status"] == "unknown")
           )
  end
end
