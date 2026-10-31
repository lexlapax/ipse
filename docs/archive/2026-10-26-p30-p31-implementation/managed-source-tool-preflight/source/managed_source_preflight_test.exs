defmodule Ipse.Session.ManagedSourcePreflightTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Session}
  alias Ipse.Session.{ManagedLineage, ManagedToolUse, SourceWindow}

  defmodule OrdinaryProvider do
    def complete(_config, messages, _tools, _emit) do
      if Enum.any?(messages, &(&1["role"] == "tool")) do
        {:ok, %{"role" => "assistant", "content" => "Synthetic completion."}, %{}}
      else
        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "ordinary_source",
               "type" => "function",
               "function" => %{"name" => "source_list", "arguments" => ~s({"limit":32})}
             }
           ]
         }, %{}}
      end
    end
  end

  @journal "docs/archive/2026-10-26-p30-p31-implementation/managed-source-tool-preflight/session.jsonl"

  defp events do
    {:ok, bytes} = File.read(@journal)
    events = bytes |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
    {events, get_in(hd(events), ["metadata", "source_origin", "session_id"])}
  end

  test "prepared source query and selected result replay in exact original order" do
    {events, id} = events()
    assert {:ok, _} = Session.Saved.restore(events, id)

    indexes =
      for {event, i} <- Enum.with_index(events),
          event["type"] == "managed_source_lookup_prepared",
          do: i

    assert length(indexes) == 2

    observed =
      Enum.find_index(
        events,
        &(&1["type"] == "managed_tool_result_observed" and &1["version"] == 2)
      )

    assert is_integer(observed)

    for index <- indexes do
      event = Enum.at(events, index)

      for key <- ~w(request_sha256 selection_sha256 dependencies_sha256) do
        altered = List.replace_at(events, index, Map.put(event, key, JSON.sha256("forged")))
        assert {:error, _} = Session.Saved.restore(altered, id)
      end

      assert {:error, _} = Session.Saved.restore(List.delete_at(events, index), id)
      assert {:error, _} = Session.Saved.restore(List.insert_at(events, index, event), id)
    end

    result = Enum.at(events, observed)

    assert {:error, _} =
             Session.Saved.restore(
               List.replace_at(
                 events,
                 observed,
                 Map.put(result, "source_selection_sha256", JSON.sha256("foreign"))
               ),
               id
             )
  end

  test "an initially empty call retains the selected producer's root dependency" do
    {events, id} = events()

    index =
      Enum.find_index(
        events,
        &(&1["type"] == "managed_source_lookup_prepared" and &1["operation"] == "source.read")
      )

    event = Enum.at(events, index)
    prefix = Enum.take(events, index)
    assert {:ok, saved} = Session.Saved.restore(prefix, id)
    assert {:ok, window} = SourceWindow.restore(prefix, id)
    lineage = saved.managed_lineage
    call = lineage.call_bindings[event["call_id"]].call
    {:ok, args} = JSON.decode_unique(get_in(call, ["function", "arguments"]))

    assert {:ok, [row]} =
             SourceWindow.tool_query_provenances(window, call["id"], "source.read", args, :replay)

    assert row["origin"] == "typed_host_outcome"
    request_id = row["provenance"]["request_id"]
    initially_empty = %{lineage | calls: Map.put(lineage.calls, call["id"], [])}

    assert {:ok, updated, dependencies} =
             ManagedLineage.add_selected_source_dependencies(initially_empty, call["id"], [row])

    assert dependencies != []
    assert {:ok, ^dependencies} = ManagedLineage.tool_dependencies(updated, call["id"])

    assert ManagedToolUse.root_only?(
             %{managed_lineage: updated, config: %{semantic_admission: updated.admission}},
             dependencies
           )

    missing_cache = %{updated | root_observations: %{}}

    refute ManagedToolUse.root_only?(
             %{
               managed_lineage: missing_cache,
               config: %{semantic_admission: missing_cache.admission}
             },
             dependencies
           )

    unknown = %{
      initially_empty
      | source_producers: Map.delete(initially_empty.source_producers, "requests:#{request_id}")
    }

    assert {:error, _} =
             ManagedLineage.add_selected_source_dependencies(unknown, call["id"], [row])

    known_empty = %{initially_empty | requests: Map.delete(initially_empty.requests, request_id)}

    assert {:ok, _, []} =
             ManagedLineage.add_selected_source_dependencies(known_empty, call["id"], [row])
  end

  @tag ordinary_source_control: true
  test "ordinary source query retains the full model result with a status-only preview" do
    root = Path.join(System.tmp_dir!(), "ipse-ordinary-source-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    IO.puts("ORDINARY_SOURCE_ROOT #{root}")

    config = %{
      provider: :demo,
      provider_module: OrdinaryProvider,
      model: "synthetic",
      home: Path.join(root, "home"),
      approval: :deny,
      approval_origin: :default_headless,
      headless: true,
      compact: false
    }

    directory = Path.join(root, "sessions")

    assert {:ok, session} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, config: config, cwd: root, state_dir: directory, subscriber: self()}
             )

    id = Session.info(session).id
    assert :ok = Session.prompt(session, "Synthetic ordinary input")
    assert_receive {:ipse, ^session, {:tool, "source_list", %{}}}, 10_000
    assert_receive {:ipse, ^session, {:done, outcome}}, 10_000
    assert {:ok, interim} = Ipse.Journal.load(directory, id)

    IO.puts(
      "ORDINARY_SOURCE_EVENTS " <>
        Jason.encode!(Enum.map(interim, &Map.take(&1, ~w(type status reason))))
    )

    assert outcome == :ok

    assert_receive {:ipse, ^session,
                    {:tool_result, "source_list",
                     "Source tool result withheld from terminal preview."}},
                   1000

    assert :ok = Session.close_confirmed(session)
    assert {:ok, events} = Ipse.Journal.load(directory, id)
    assert Enum.any?(events, &(&1["type"] == "managed_source_lookup_prepared"))
    message = Enum.find(events, &(get_in(&1, ["message", "tool_call_id"]) == "ordinary_source"))
    assert Jason.decode!(message["message"]["content"])["sources"] != []
    assert {:ok, _} = Session.Saved.restore(events, id)
  end
end
