defmodule Ipse.CompactionSessionTest do
  use ExUnit.Case, async: false

  defmodule Fake do
    def complete(config, messages, tools, emit) do
      if tools == [] do
        send(config.test_pid, {:summary_request, self(), messages})

        case config[:summary_mode] do
          :wait ->
            Process.sleep(:infinity)

          :invalid ->
            {:ok, %{"role" => "assistant", "content" => "not JSON"},
             %{"input_tokens" => 11, "output_tokens" => 7}}

          _ ->
            emit.({:text, "private summary stream must not appear"})

            {:ok,
             %{
               "role" => "assistant",
               "content" =>
                 Jason.encode!(%{
                   "decisions" => ["Keep MIT license"],
                   "facts" => ["Earlier write completed; inspect current file before changing it"],
                   "open_questions" => ["Next task remains open"]
                 })
             }, %{}}
        end
      else
        send(config.test_pid, {:normal_request, messages})

        if config[:normal_mode] == :wait do
          send(config.test_pid, {:normal_worker, self()})
          Process.sleep(:infinity)
        end

        {:ok, %{"role" => "assistant", "content" => "Done"}, %{}}
      end
    end
  end

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "ipse-compact-session-#{Base.encode16(:crypto.strong_rand_bytes(8))}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    dir = Path.join(root, "state")

    {:ok, id} =
      Ipse.Journal.create(dir, %{"cwd" => root, "provider" => "demo", "model" => "test"})

    call = %{
      "id" => "past-write",
      "type" => "function",
      "function" => %{
        "name" => "write",
        "arguments" => Jason.encode!(%{"path" => "kept.txt", "content" => "before"})
      }
    }

    messages = [
      %{"role" => "user", "content" => "Keep the MIT license and preserve my manual edits."},
      %{"role" => "assistant", "content" => "", "tool_calls" => [call]},
      %{
        "role" => "tool",
        "tool_call_id" => "past-write",
        "content" => "Wrote 6 bytes.",
        "ipse_tool_outcome" => %{"status" => "result_recorded", "approval" => "approved"}
      },
      %{"role" => "assistant", "content" => String.duplicate("old useful findings ", 300)},
      %{"role" => "user", "content" => "Record earlier decisions."},
      %{"role" => "assistant", "content" => String.duplicate("more useful findings ", 300)},
      %{"role" => "user", "content" => "Keep recent exchanges intact."},
      %{"role" => "assistant", "content" => "Recent result"}
    ]

    for message <- messages,
        do: :ok = Ipse.Journal.append(dir, id, %{"type" => "message", "message" => message})

    :ok =
      Ipse.Journal.append(dir, id, %{
        "type" => "tool_started",
        "call_id" => "past-write",
        "name" => "write"
      })

    File.write!(Path.join(root, "kept.txt"), "manual edit")
    %{root: root, dir: dir, id: id, original: messages}
  end

  defp start(ctx, extra \\ %{}) do
    config =
      Map.merge(
        %{
          provider: :demo,
          model: "test",
          provider_module: Fake,
          home: Path.join(ctx.root, "home"),
          test_pid: self(),
          approval: :ask,
          context_bytes: 24_000,
          compact_threshold_bytes: 10_000
        },
        extra
      )

    result =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Ipse.Session,
         config: config, cwd: ctx.root, state_dir: ctx.dir, id: ctx.id, subscriber: self()}
      )

    case result do
      {:ok, pid} ->
        on_exit(fn ->
          if Process.alive?(pid), do: DynamicSupervisor.terminate_child(Ipse.Sessions, pid)
        end)

      _ ->
        :ok
    end

    result
  end

  test "checkpoint commits before continuation, retains original journal, and resumes without tool replay",
       ctx do
    {:ok, pid} = start(ctx)
    :ok = Ipse.Session.prompt(pid, "Continue the next task.")
    assert_receive {:ipse, ^pid, {:status, :compacting}}, 2_000
    assert_receive {:summary_request, _, [%{"role" => "system"}, %{"role" => "user"}]}, 2_000
    assert_receive {:ipse, ^pid, {:compacted, before_bytes, after_bytes}}, 2_000
    assert after_bytes < before_bytes
    assert_receive {:normal_request, [_system, checkpoint | _]}, 2_000

    assert checkpoint["ipse_checkpoint"]["user_intents"] == [
             "Keep the MIT license and preserve my manual edits.",
             "Record earlier decisions."
           ]

    assert [%{"call_id" => "past-write", "status" => "result_recorded"}] =
             checkpoint["ipse_checkpoint"]["actions"]

    assert_receive {:ipse, ^pid, {:done, :ok}}, 2_000
    refute_receive {:ipse, ^pid, {:text, "private summary stream must not appear"}}, 50
    {:ok, events} = Ipse.Journal.load(ctx.dir, ctx.id)
    for original <- ctx.original, do: assert(Enum.any?(events, &(&1["message"] == original)))
    assert Enum.count(events, &(&1["type"] == "context_compacted")) == 1
    assert File.read!(Path.join(ctx.root, "kept.txt")) == "manual edit"
    DynamicSupervisor.terminate_child(Ipse.Sessions, pid)

    {:ok, resumed} = start(ctx)
    refute_receive {:summary_request, _, _}, 50
    :ok = Ipse.Session.prompt(resumed, "What remains?")
    assert_receive {:normal_request, [_system, ^checkpoint | _]}, 2_000
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 2_000
    refute_receive {:summary_request, _, _}, 50
    {:ok, events} = Ipse.Journal.load(ctx.dir, ctx.id)
    assert Enum.count(events, &(&1["type"] == "tool_started")) == 1
    assert File.read!(Path.join(ctx.root, "kept.txt")) == "manual edit"
  end

  test "private text excludes summary streams and identifies only the main request", ctx do
    {:ok, pid} = start(ctx)
    {:ok, handle} = Ipse.Session.subscribe_text(pid)
    :ok = Ipse.Session.prompt(pid, "Continue.")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    {:ok, events} = Ipse.Journal.load(ctx.dir, ctx.id)
    model = Enum.find(events, &(&1["type"] == "request_admitted" and &1["kind"] == "model"))

    assert_receive {:ipse_text, _, %{"kind" => "start", "request_id" => id, "sequence" => 1}},
                   1000

    assert id == model["request_id"]
    :ok = Ipse.TextStream.ack(handle, 1)
    assert_receive {:ipse_text, _, %{"kind" => "end", "request_id" => ^id, "sequence" => 2}}, 1000
    :ok = Ipse.TextStream.ack(handle, 2)
    refute_receive {:ipse_text, _, %{"kind" => "text"}}, 20
  end

  test "cancelled compaction stops its worker without saving a partial checkpoint", ctx do
    {:ok, pid} = start(ctx, %{summary_mode: :wait})
    :ok = Ipse.Session.prompt(pid, "Continue.")
    assert_receive {:summary_request, worker, _}, 2_000
    ref = Process.monitor(worker)
    :ok = Ipse.Session.cancel(pid)
    assert_receive {:DOWN, ^ref, :process, ^worker, :killed}, 2_000
    assert_receive {:ipse, ^pid, {:done, :cancelled}}, 2_000
    assert Ipse.Session.info(pid).phase == :idle
    {:ok, events} = Ipse.Journal.load(ctx.dir, ctx.id)
    refute Enum.any?(events, &(&1["type"] == "context_compacted"))
    assert File.read!(Path.join(ctx.root, "kept.txt")) == "manual edit"
  end

  test "owner death after checkpoint commit resumes the checkpoint without restarting work",
       ctx do
    {:ok, pid} = start(ctx, %{normal_mode: :wait})
    :ok = Ipse.Session.prompt(pid, "Continue.")
    assert_receive {:ipse, ^pid, {:compacted, _, _}}, 2_000
    assert_receive {:normal_request, [_system, checkpoint | _]}, 2_000
    assert_receive {:normal_worker, worker}, 2_000
    owner_ref = Process.monitor(pid)
    worker_ref = Process.monitor(worker)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^owner_ref, :process, ^pid, :killed}, 2_000
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}, 2_000
    {:ok, resumed} = start(ctx)
    refute_receive {:normal_worker, _}, 50
    :ok = Ipse.Session.prompt(resumed, "Recover without repeating effects.")
    assert_receive {:normal_request, [_system, ^checkpoint | _]}, 2_000
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 2_000
    {:ok, events} = Ipse.Journal.load(ctx.dir, ctx.id)
    assert Enum.count(events, &(&1["type"] == "context_compacted")) == 1
    assert Enum.count(events, &(&1["type"] == "tool_started")) == 1
    assert File.read!(Path.join(ctx.root, "kept.txt")) == "manual edit"
  end

  test "invalid summary fails with recovery guidance and keeps original context", ctx do
    {:ok, pid} = start(ctx, %{summary_mode: :invalid})
    :ok = Ipse.Session.prompt(pid, "Continue.")
    assert_receive {:ipse, ^pid, {:error, message}}, 2_000
    assert message =~ "Original history is retained"
    assert_receive {:ipse, ^pid, {:done, :error}}, 2_000
    {:ok, events} = Ipse.Journal.load(ctx.dir, ctx.id)
    refute Enum.any?(events, &(&1["type"] == "context_compacted"))
    assert Enum.count(events, &(&1["type"] == "message")) == length(ctx.original) + 1
    refute_receive {:normal_request, _}, 50
  end

  test "rejected summary retains completed provider usage rather than losing its cost facts",
       ctx do
    {:ok, events} = Ipse.Journal.load(ctx.dir, ctx.id)
    [session | tail] = events
    session = put_in(session, ["metadata", "provider"], "openai")
    path = Path.join(ctx.dir, ctx.id <> ".jsonl")
    File.write!(path, Enum.map_join([session | tail], "\n", &Jason.encode!/1) <> "\n")
    {:ok, pid} = start(ctx, %{summary_mode: :invalid, provider: :openai})
    :ok = Ipse.Session.prompt(pid, "Continue.")
    assert_receive {:ipse, ^pid, {:done, :error}}, 2_000

    assert [
             %{
               "kind" => "compaction",
               "outcome" => "completed",
               "finality" => "final",
               "usage" => %{"counts" => %{"total_tokens" => 18}}
             }
           ] = Ipse.Session.info(pid).accounting["requests"]

    :ok = Ipse.Session.close(pid)
    {:ok, resumed} = start(ctx, %{summary_mode: :invalid, provider: :openai})
    assert Ipse.Session.info(resumed).accounting["legacy_unmetered"]
    refute_receive {:normal_request, _}, 20
  end

  test "a corrupt checkpoint is rejected rather than silently changing resumed context", ctx do
    :ok =
      Ipse.Journal.append(ctx.dir, ctx.id, %{
        "type" => "context_compacted",
        "version" => 1,
        "covered_messages" => 1,
        "prefix_sha256" => "wrong",
        "checkpoint" => %{}
      })

    assert {:error, :invalid_compaction_checkpoint} = start(ctx)
    refute_receive {:normal_request, _}, 50
    assert File.read!(Path.join(ctx.root, "kept.txt")) == "manual edit"
  end

  defp long_turn(ctx) do
    {:ok, id} =
      Ipse.Journal.create(ctx.dir, %{"cwd" => ctx.root, "provider" => "demo", "model" => "test"})

    initial = Enum.take(ctx.original, 3)

    messages =
      initial ++
        Enum.flat_map(1..5, fn n ->
          [
            %{
              "role" => "assistant",
              "content" => "",
              "provider_data" => %{"opaque" => "continuation-#{n}"},
              "tool_calls" => [
                %{
                  "id" => "read-#{n}",
                  "function" => %{"name" => "read", "arguments" => ~s({"path":"evidence.txt"})}
                }
              ]
            },
            %{
              "role" => "tool",
              "tool_call_id" => "read-#{n}",
              "content" => String.duplicate("synthetic evidence ", 500),
              "ipse_tool_outcome" => %{
                "status" => "result_recorded",
                "approval" => "not_required"
              }
            }
          ]
        end)

    for message <- messages,
        do: :ok = Ipse.Journal.append(ctx.dir, id, %{"type" => "message", "message" => message})

    :ok =
      Ipse.Journal.append(ctx.dir, id, %{
        "type" => "tool_started",
        "call_id" => "past-write",
        "name" => "write"
      })

    %{ctx | id: id, original: messages}
  end

  test "a long turn journals excerpts before continuation and resumes without replay", ctx do
    ctx = long_turn(ctx)
    config = %{context_bytes: 100_000, compact_threshold_bytes: 36_000}
    {:ok, pid} = start(ctx, config)
    :ok = Ipse.Session.prompt(pid, "Continue the same task without repeating effects.")
    assert_receive {:ipse, ^pid, {:compacted, before_bytes, after_bytes}}, 2000
    assert after_bytes < before_bytes
    assert_receive {:normal_request, [_system | projected]}, 2000
    assert Enum.any?(projected, &Map.has_key?(&1, "ipse_result_excerpt"))
    {:ok, events} = Ipse.Journal.load(ctx.dir, ctx.id)
    assert Enum.count(events, &(&1["type"] == "tool_results_compacted")) == 1
    for original <- ctx.original, do: assert(Enum.any?(events, &(&1["message"] == original)))
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    refute_receive {:summary_request, _, _}, 30
    :ok = Ipse.Session.close(pid)

    {:ok, resumed} = start(ctx, config)
    :ok = Ipse.Session.prompt(resumed, "Report remaining work.")
    assert_receive {:normal_request, [_system | restored]}, 2000
    assert Enum.take(restored, length(projected)) == projected
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 2000
    {:ok, events} = Ipse.Journal.load(ctx.dir, ctx.id)
    assert Enum.count(events, &(&1["type"] == "tool_results_compacted")) == 1
    assert Enum.count(events, &(&1["type"] == "tool_started")) == 1
    assert File.read!(Path.join(ctx.root, "kept.txt")) == "manual edit"
  end

  test "owner death after a tool-output checkpoint keeps the projection on idle resume", ctx do
    ctx = long_turn(ctx)
    config = %{context_bytes: 100_000, compact_threshold_bytes: 36_000}
    {:ok, pid} = start(ctx, Map.put(config, :normal_mode, :wait))
    :ok = Ipse.Session.prompt(pid, "Continue.")
    assert_receive {:normal_request, [_system | projected]}, 2000
    assert_receive {:normal_worker, worker}, 2000
    owner_ref = Process.monitor(pid)
    worker_ref = Process.monitor(worker)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^owner_ref, :process, ^pid, :killed}, 2000
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}, 2000
    {:ok, resumed} = start(ctx, config)
    refute_receive {:normal_request, _}, 30
    :ok = Ipse.Session.prompt(resumed, "Recover without replay.")
    assert_receive {:normal_request, [_system | restored]}, 2000
    assert Enum.take(restored, length(projected)) == projected
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 2000
    assert File.read!(Path.join(ctx.root, "kept.txt")) == "manual edit"
  end

  test "corrupt excerpt checkpoints fail closed and reduction failures retain specific causes",
       ctx do
    ctx = long_turn(ctx)

    {:tool_results, _, event} =
      Ipse.Compaction.prepare(
        ctx.original,
        %{context_bytes: 100_000, compact_threshold_bytes: 36_000},
        %{"role" => "system", "content" => "rules"}
      )

    :ok = Ipse.Journal.append(ctx.dir, ctx.id, Map.put(event, "projection_sha256", "bad"))
    assert {:error, :invalid_tool_result_checkpoint} = start(ctx)

    ctx = long_turn(ctx)
    {:ok, pid} = start(ctx, %{context_bytes: 20_000, compact_threshold_bytes: 8_000})
    :ok = Ipse.Session.prompt(pid, "Continue.")
    assert_receive {:ipse, ^pid, {:error, message}}, 2000
    assert message =~ "retained user requests"
    assert_receive {:ipse, ^pid, {:done, :error}}, 2000
    {:ok, events} = Ipse.Journal.load(ctx.dir, ctx.id)
    assert Enum.any?(events, &(&1["type"] == "compaction_failed" and &1["stage"] == "prepare"))
    refute Enum.any?(events, &(&1["type"] == "tool_results_compacted"))
    refute_receive {:normal_request, _}, 30
  end
end
