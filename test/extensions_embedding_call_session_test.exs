defmodule Ipse.Extensions.EmbeddingCallSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal, Usage, Budget}
  alias Ipse.Extensions.{Actions, Config, Registry, Store, Manifest, ChildUsage}

  defmodule NoModel do
    def complete(config, _, _, _) do
      send(config.test_pid, :unexpected_embedding_conversation_call)
      {:error, "Explicit embedding commands must not invoke the conversation provider"}
    end
  end

  defmodule DelegateModel do
    def complete(config, messages, _, _) do
      send(config.test_pid, {:embedding_conversation, config[:delegation_origin]})

      assistant =
        if config[:delegation_origin] == nil and not Enum.any?(messages, &(&1["role"] == "tool")) do
          %{
            "role" => "assistant",
            "content" => "",
            "tool_calls" => [
              %{
                "id" => "child",
                "type" => "function",
                "function" => %{
                  "name" => "delegate",
                  "arguments" =>
                    Jason.encode!(%{
                      "task" => "Complete the synthetic child task",
                      "context" => "Public synthetic context"
                    })
                }
              }
            ]
          }
        else
          %{"role" => "assistant", "content" => "Synthetic task completed"}
        end

      {:ok, assistant, %{"input_tokens" => 3, "output_tokens" => 1}}
    end
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-embedding-artifacts-" <> Usage.id())
    File.mkdir_p!(root)

    artifacts =
      Map.new([:mixed, :ungranted, :jobs], fn variant ->
        {variant, build_artifact(root, variant)}
      end)

    on_exit(fn -> File.rm_rf!(root) end)
    %{artifacts: artifacts}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-embedding-session-" <> Usage.id())
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, home: Path.join(root, "home"), dir: Path.join(root, "sessions")}
  end

  for {dimensions, count} <- [{768, 1}, {4096, 4}] do
    test "#{dimensions} dimensions: exact approval, typed canonical receipt and complete SDK worker pages",
         ctx do
      dimensions = unquote(dimensions)
      count = unquote(count)
      http = http(ctx, dimensions)
      cfg = config(ctx, http.base, dimensions) |> Map.put(:approval, :ask)
      pid = start(ctx, cfg)
      request = request(count)
      invoke(pid, request)

      assert_receive {:ipse, ^pid, {:approval, ref, "extension:embedding.create", proposed}},
                     10_000

      assert proposed["request"] == request
      assert proposed["namespace"] == Session.info(pid).id
      assert proposed["execution"]["dimensions"] == dimensions
      assert proposed["execution"]["operation"] == "embedding"
      assert proposed["effect_binding"]["kind"] == "embedding"
      assert proposed["effect_binding"]["execution"] == proposed["execution"]

      assert proposed["destination"]["target_sha256"] ==
               Manifest.sha256(http.base <> "/api/embed")

      assert calls(ctx) == []
      assert :ok = Session.approve(pid, ref, true)
      assert_receive {:embedding_http, tag, handler, wire}, 5000
      assert tag == http.tag
      assert wire["input"] == request["inputs"]
      assert wire["truncate"] === false
      refute Map.has_key?(wire, "max_output_tokens")
      refute Map.has_key?(wire, "options")
      send(handler, :respond)
      done(pid)
      refute_receive :unexpected_embedding_conversation_call
      ev = events(ctx, pid)
      assert_canonical_order(ev)
      [admission] = Enum.filter(ev, &(&1["type"] == "request_admitted"))
      [completion] = Enum.filter(ev, &(&1["type"] == "request_finished"))
      assert admission["version"] === 2 and admission["operation"] == "embedding"
      assert completion["version"] === 2 and completion["operation"] == "embedding"
      assert completion["outcome"] == "completed" and completion["finality"] == "final"
      assert completion["usage"]["version"] === 2
      assert completion["usage"]["counts"]["input_tokens"] == 23
      assert completion["usage"]["counts"]["output_tokens"] == nil
      assert completion["usage"]["not_applicable_fields"] == ["output_tokens"]
      source = Enum.find(ev, &(&1["type"] == "extension_effect_result"))
      embedding = Enum.find(results(ev), &(&1["request"]["op"] == "embedding.create"))
      assert embedding["version"] === 2

      assert embedding["outcome"]["value"]["result"] ==
               Ipse.Extensions.EffectResult.descriptor(source)

      assert source["inference"]["usage"] == completion["usage"]
      assert source["inference"]["attempt_id"] == admission["attempt_id"]

      refute Enum.any?(
               ev,
               &(&1["type"] == "extension_model_response" or
                   get_in(&1, ["message", "role"]) == "assistant")
             )

      pages = Enum.filter(results(ev), &(&1["request"]["op"] == "effect.result.read"))
      assert length(pages) == count * div(dimensions + 767, 768)

      assert Enum.all?(
               pages,
               &(&1["namespace"] == Session.info(pid).id and &1["request"]["version"] === 2 and
                   &1["outcome"]["status"] == "ok")
             )

      if dimensions == 4096, do: assert(length(pages) > 16)
      bytes = Enum.map_join(pages, &Base.decode64!(&1["outcome"]["value"]["values"]))
      expected = Enum.map_join(source["data"]["vectors"], &Base.decode64!(&1["values"]))
      assert bytes == expected
      assert byte_size(bytes) == count * dimensions * 4
      summary = Session.info(pid).extension_result["value"]
      assert summary["bytes"] == byte_size(bytes)
      assert summary["sha256"] == sha256(bytes)
      assert summary["reads"] == length(pages)
      assert Enum.all?(pages, &(Ipse.Extension.validate(&1["outcome"]["value"]) == :ok))
      assert length(calls(ctx)) == 1
      assert_idle_resume(ctx, pid, cfg, http)
    end
  end

  test "denied exact egress performs no HTTP request, inference admission or source publication",
       ctx do
    http = http(ctx, 768)
    cfg = config(ctx, http.base, 768) |> Map.put(:approval, :ask)
    pid = start(ctx, cfg)
    invoke(pid, request())
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:embedding.create", _}}, 10_000
    assert calls(ctx) == []
    assert :ok = Session.approve(pid, ref, false)
    done(pid)
    ev = events(ctx, pid)
    assert [%{"outcome" => %{"status" => "denied", "value" => %{}}}] = results(ev)

    refute Enum.any?(
             ev,
             &(&1["type"] in ~w(request_admitted extension_embedding_request extension_effect_result request_finished))
           )

    assert calls(ctx) == []
    refute_receive {:embedding_http, _, _, _}
    refute_receive :unexpected_embedding_conversation_call
  end

  test "ungranted embedding and unknown selected profile refuse before approval or HTTP", ctx do
    http = http(ctx, 768)

    for {cfg, request} <- [
          {config(ctx, http.base, 768, :ungranted), request()},
          {config(ctx, http.base, 768), Map.put(request(), "profile", "missing")}
        ] do
      pid = start(ctx, cfg)
      invoke(pid, request)
      done(pid, :error)
      ev = events(ctx, pid)
      assert results(ev) == []
      refute Enum.any?(ev, &(&1["type"] == "request_admitted"))
      assert calls(ctx) == []
      refute_receive {:ipse, ^pid, {:approval, _, _, _}}
      assert :ok = Session.close_confirmed(pid)
    end
  end

  test "successful vector readers cannot address an earlier invocation or alter coordinate bindings",
       ctx do
    http = http(ctx, 768)
    cfg = config(ctx, http.base, 768)
    pid = start(ctx, cfg)
    invoke(pid, request())
    assert_receive {:embedding_http, _, handler, _}, 5000
    send(handler, :respond)
    done(pid)
    source = Enum.find(events(ctx, pid), &(&1["type"] == "extension_effect_result"))

    old = %{
      "op" => "effect.result.read",
      "version" => 2,
      "operation_id" => source["operation_id"],
      "source_sha256" => source["source_sha256"],
      "vector_index" => 0,
      "offset" => 0,
      "limit" => 768
    }

    invoke(pid, old, %{"read" => false})
    done(pid, :error)
    assert length(calls(ctx)) == 1
    assert :ok = Session.close_confirmed(pid)

    for override <- [
          %{"source_sha256" => String.duplicate("0", 64)},
          %{"vector_index" => 1},
          %{"offset" => 769}
        ] do
      fresh = start(ctx, cfg)
      invoke(fresh, request(), %{"read_override" => override})
      assert_receive {:embedding_http, _, handler, _}, 5000
      send(handler, :respond)
      done_any(fresh)

      readers =
        Enum.filter(results(events(ctx, fresh)), &(&1["request"]["op"] == "effect.result.read"))

      assert Enum.all?(readers, &(&1["outcome"]["status"] != "ok"))

      assert Session.info(fresh).extension_result == nil or
               Session.info(fresh).extension_result["value"]["bytes"] == 0

      assert :ok = Session.close_confirmed(fresh)
    end
  end

  test "source/attempt/namespace/operation and recomputed page corruption refuse before tail repair",
       ctx do
    http = http(ctx, 768)
    cfg = config(ctx, http.base, 768)
    pid = start(ctx, cfg)
    invoke(pid, request())
    assert_receive {:embedding_http, _, handler, _}, 5000
    send(handler, :respond)
    done(pid)
    ev = events(ctx, pid)
    id = Session.info(pid).id
    assert :ok = Session.close_confirmed(pid)
    source = Enum.find(ev, &(&1["type"] == "extension_effect_result"))
    page = Enum.find(results(ev), &(&1["request"]["op"] == "effect.result.read"))
    forged_outcome = put_in(page["outcome"], ["value", "input_sha256"], digest("different input"))

    forged_page =
      page
      |> Map.put("outcome", forged_outcome)
      |> Map.put("outcome_sha256", digest(forged_outcome))

    assert Actions.valid_result?(forged_page)

    changes = [
      Enum.reject(ev, &(&1 == source)),
      replace(ev, source, put_in(source, ["data", "vectors", Access.at(0), "values"], "forged")),
      replace(ev, source, source |> put_in(["inference", "attempt_id"], Usage.id()) |> rehash()),
      replace(ev, source, source |> Map.put("parent_invocation_id", Usage.id()) |> rehash()),
      Enum.map(ev, fn event ->
        if event["type"] == "request_admitted",
          do: Map.put(event, "operation", "text"),
          else: event
      end),
      Enum.map(ev, fn event ->
        if event["type"] in ~w(extension_action_intent extension_action_result) and
             event["request"]["op"] == "effect.result.read",
           do: Map.put(event, "namespace", Usage.id()),
           else: event
      end),
      replace(ev, page, forged_page)
    ]

    path = Path.join(ctx.dir, id <> ".jsonl")

    for corrupted <- changes do
      assert {:error, _} = Session.restore_context(corrupted)
      bytes = Enum.map_join(corrupted, "", &(Jason.encode!(&1) <> "\n")) <> "{partial"
      File.write!(path, bytes)

      assert {:error, _} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Session,
                  config: cfg, cwd: ctx.root, state_dir: ctx.dir, subscriber: self(), id: id}
               )

      assert File.read!(path) == bytes
      assert length(calls(ctx)) == 1
    end
  end

  for interruption <- [:timeout, :cancel, :owner_loss] do
    test "#{interruption}: dispatched embedding retains uncertainty and idle resume never replays",
         ctx do
      http = http(ctx, 768)
      cfg = config(ctx, http.base, 768) |> Map.put(:budget, quota())
      pid = start(ctx, cfg)
      id = Session.info(pid).id
      monitor = Process.monitor(pid)
      guard = Ipse.Session.Lock.for_owner(pid)
      guard_monitor = Process.monitor(guard)

      request =
        if unquote(interruption) == :timeout,
          do: Map.put(request(), "timeout_ms", 1000),
          else: request()

      invoke(pid, request)
      assert_receive {:embedding_http, tag, handler, _}, 5000
      assert tag == http.tag

      case unquote(interruption) do
        :cancel -> assert :ok = Session.cancel(pid)
        :owner_loss -> Process.exit(pid, :kill)
        _ -> :ok
      end

      if unquote(interruption) == :owner_loss do
        assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5000
        assert_receive {:DOWN, ^guard_monitor, :process, ^guard, _}, 10_000
      else
        done(pid, if(unquote(interruption) == :cancel, do: :cancelled, else: :ok))
        assert :ok = Session.close_confirmed(pid)
      end

      assert_receive {:embedding_http_closed, ^tag, ^handler}, 5000
      assert {:ok, ev} = Journal.load(ctx.dir, id)
      assert {:ok, _} = Session.restore_context(ev)
      refute Enum.any?(ev, &(&1["type"] == "extension_effect_result"))
      assert Enum.any?(ev, &(&1["type"] == "request_admitted" and &1["operation"] == "embedding"))
      assert Enum.all?(results(ev), &(&1["outcome"]["status"] != "ok"))
      assert {:ok, snapshot} = Budget.saved(ctx.dir, id)
      assert snapshot["unsettled_count"] >= 1 or snapshot["partial_count"] >= 1
      assert booked(snapshot)["input_tokens"] >= 8
      assert booked(snapshot)["output_tokens"] == 0
      before = calls(ctx)
      resumed = start(ctx, cfg, id)
      assert Session.info(resumed).phase == :idle
      assert calls(ctx) == before
      refute_receive {:embedding_http, ^tag, _, _}, 100
      refute_receive :unexpected_embedding_conversation_call
    end
  end

  test "unconfirmed budget publication preserves final metering and refuses vectors and uncovered resume",
       ctx do
    http = http(ctx, 768)
    cfg = config(ctx, http.base, 768) |> Map.put(:budget, quota())
    pid = start(ctx, cfg)
    id = Session.info(pid).id
    invoke(pid, request())
    assert_receive {:embedding_http, tag, handler, _}, 5000
    assert tag == http.tag
    lock_path = Path.join([ctx.dir, "budgets", id <> ".lock"])
    assert {:ok, lock} = Ipse.Runner.lock(lock_path)

    try do
      send(handler, :respond)
      done(pid)
      assert :ok = Session.close_confirmed(pid)
    after
      assert :ok = Ipse.Runner.unlock(lock)
    end

    assert {:ok, ev} = Journal.load(ctx.dir, id)
    assert {:ok, _} = Session.restore_context(ev)
    [observed] = Enum.filter(ev, &(&1["type"] == "request_usage_observed"))
    assert observed["usage"]["counts"]["input_tokens"] == 23
    [completion] = Enum.filter(ev, &(&1["type"] == "request_finished"))
    assert completion["outcome"] == "failed" and completion["finality"] == "partial"
    assert completion["reported_model"] == nil
    assert completion["usage"] == observed["usage"]
    refute Enum.any?(ev, &(&1["type"] == "extension_effect_result"))
    assert Enum.all?(results(ev), &(&1["outcome"]["status"] != "ok"))
    assert {:ok, snapshot} = Budget.saved(ctx.dir, id)
    assert snapshot["unsettled_count"] == 1
    assert booked(snapshot)["input_tokens"] == 8
    assert booked(snapshot)["output_tokens"] == 0
    path = Path.join(ctx.dir, id <> ".jsonl")
    File.write!(path, "{partial", [:append])
    before = File.read!(path)

    assert {:error, _} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: cfg, cwd: ctx.root, state_dir: ctx.dir, subscriber: self(), id: id}
             )

    assert File.read!(path) == before
    assert length(calls(ctx)) == 1
  end

  test "observed overdraw retains actual liability and prevents vector publication", ctx do
    http = http(ctx, 768)

    cfg =
      config(ctx, http.base, 768) |> Map.put(:budget, Map.put(quota(), "max_input_tokens", 20))

    pid = start(ctx, cfg)
    invoke(pid, request())
    assert_receive {:embedding_http, _, handler, _}, 5000
    send(handler, :respond)
    done(pid)
    ev = events(ctx, pid)
    refute Enum.any?(ev, &(&1["type"] == "extension_effect_result"))

    assert Enum.any?(
             ev,
             &(&1["type"] == "request_usage_observed" and
                 &1["usage"]["counts"]["input_tokens"] == 23)
           )

    assert Enum.all?(results(ev), &(&1["outcome"]["status"] != "ok"))
    assert {:ok, snapshot} = Budget.saved(ctx.dir, Session.info(pid).id)
    assert snapshot["overdrawn"]
    assert booked(snapshot)["input_tokens"] == 23
    assert booked(snapshot)["output_tokens"] == 0
  end

  test "explicit child embedding uses separate approvals and the same durable parent quota",
       ctx do
    http = http(ctx, 768)

    cfg =
      config(ctx, http.base, 768, :jobs)
      |> Map.merge(%{
        provider_module: DelegateModel,
        approval: :ask,
        subagents: true,
        budget: %{"version" => 1, "max_requests" => 6}
      })

    pid = start(ctx, cfg)
    assert :ok = Session.prompt(pid, "Run the synthetic delegated task")
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:embedding.create", _}}, 10_000
    assert :ok = Session.approve(pid, ref, true)
    assert_receive {:embedding_http, _, root_http, _}, 5000
    send(root_http, :respond)
    assert_receive {:ipse, ^pid, {:approval, delegate_ref, "delegate", _}}, 10_000
    assert :ok = Session.approve(pid, delegate_ref, true)
    assert_receive {:ipse, ^pid, {:approval, child_ref, name, proposed}}, 10_000

    assert String.starts_with?(name, "child ") and
             String.ends_with?(name, "/extension:embedding.create")

    assert proposed["request"] == request()
    assert proposed["execution"]["provider"] == "ollama"
    assert :ok = Session.approve(pid, child_ref, true)
    assert_receive {:embedding_http, _, child_http, _}, 5000
    send(child_http, :respond)
    done(pid)
    ev = events(ctx, pid)
    id = Session.info(pid).id
    assert {:ok, index} = ChildUsage.restore(ev)
    assert length(index.order) == 1
    [child] = Map.values(index.index)
    assert child["cleanup_confirmed"]
    assert {:ok, ledger, _, _, accounting_events} = ChildUsage.read_for_budget(ctx.dir, id, child)

    embedding =
      ledger.requests |> Map.values() |> Enum.find(&(&1.admission["operation"] == "embedding"))

    assert embedding != nil
    assert embedding.admission["parent_session_id"] == id
    assert embedding.admission["selected_profile"] == "vectors"
    assert embedding.completion["outcome"] == "completed"

    assert {:ok, child_events} =
             Journal.load(Path.join([ctx.dir, "subagents", id]), child["child_id"])

    assert Enum.any?(
             accounting_events,
             &(&1["type"] == "request_admitted" and &1["operation"] == "embedding")
           )

    assert Enum.any?(
             child_events,
             &(&1["type"] == "extension_effect_result" and &1["kind"] == "embedding.f32le")
           )

    metadata = hd(child_events)["metadata"]
    assert metadata["mcp_servers"] == []
    assert {:ok, snapshot} = Budget.saved(ctx.dir, id)
    assert snapshot["request_count"] == 5
    assert snapshot["unsettled_count"] == 0
    assert snapshot["refused_count"] == 0
    assert length(calls(ctx)) == 2
    assert_idle_resume(ctx, pid, cfg, http)
  end

  defp config(ctx, base, dimensions, variant \\ :mixed) do
    assert {:ok, installed} =
             Store.import(ctx.artifacts[variant], Path.join(ctx.home, "extensions/artifacts"))

    manifest = Jason.decode!(File.read!(Path.join(ctx.artifacts[variant], "extension.json")))

    data = %{
      "extensions" => [
        %{
          "instance" => "vectors",
          "artifact" => installed.digest,
          "enabled" => true,
          "options" => %{"request" => request()},
          "order" => 1,
          "lifetime" => "persistent"
        }
      ],
      "extension_trust" => [
        %{
          "artifact" => installed.digest,
          "capabilities" => manifest["capabilities"],
          "allow_project" => false,
          "allow_children" => true
        }
      ]
    }

    assert {:ok, selections} =
             Config.resolve(
               [%{scope: "operator", path: Path.join(ctx.root, "operator.json"), data: data}],
               []
             )

    assert {:ok, entries} = Registry.prepare(selections, ctx.home)

    %{
      provider: :ollama,
      model: "unused-main",
      provider_module: NoModel,
      test_pid: self(),
      home: ctx.home,
      operator_home: nil,
      extensions: entries,
      approval: :allow,
      compact: false,
      embedding_profiles: %{
        "vectors" => %{
          "operation" => "embedding",
          "provider" => "ollama",
          "model" => "fixture",
          "dimensions" => dimensions,
          "dimension_mode" => "native",
          "base_url" => base,
          "timeout_ms" => 20_000
        }
      }
    }
  end

  defp start(ctx, config, id \\ nil) do
    assert {:ok, pid} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: config, cwd: ctx.root, state_dir: ctx.dir, id: id, subscriber: self()}
             )

    on_exit(fn -> if Process.alive?(pid), do: Session.close_confirmed(pid) end)
    pid
  end

  defp request(count \\ 1),
    do: %{
      "op" => "embedding.create",
      "version" => 1,
      "profile" => "vectors",
      "inputs" => Enum.map(1..count, &"Synthetic chunk #{&1}"),
      "timeout_ms" => 10_000
    }

  defp invoke(pid, request, extra \\ %{}),
    do:
      assert(
        :ok =
          Session.invoke_export(
            pid,
            :command,
            "ext__vectors__embed",
            Map.merge(%{"request" => request}, extra)
          )
      )

  defp done(pid, status \\ :ok), do: assert_receive({:ipse, ^pid, {:done, ^status}}, 20_000)
  defp done_any(pid), do: assert_receive({:ipse, ^pid, {:done, _}}, 20_000)
  defp results(ev), do: Enum.filter(ev, &(&1["type"] == "extension_action_result"))

  defp events(ctx, pid) do
    assert {:ok, ev} = Journal.load(ctx.dir, Session.info(pid).id)
    assert {:ok, _} = Session.restore_context(ev)
    ev
  end

  defp assert_canonical_order(ev) do
    types =
      ~w(extension_action_intent extension_embedding_request request_admitted request_usage_observed extension_effect_result request_finished extension_action_result)

    positions = Enum.map(types, fn type -> Enum.find_index(ev, &(&1["type"] == type)) end)
    assert Enum.all?(positions, &is_integer/1)
    assert positions == Enum.sort(positions)
  end

  defp assert_idle_resume(ctx, pid, cfg, http) do
    id = Session.info(pid).id
    assert :ok = Session.close_confirmed(pid)
    path = Path.join(ctx.dir, id <> ".jsonl")
    before = File.read!(path)
    calls_before = calls(ctx)
    resumed = start(ctx, cfg, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(path) == before
    assert calls(ctx) == calls_before
    tag = http.tag
    refute_receive {:embedding_http, ^tag, _, _}, 100
    refute_receive :unexpected_embedding_conversation_call
  end

  defp quota,
    do: %{
      "version" => 1,
      "max_requests" => 2,
      "max_input_tokens" => 100,
      "reserve_input_tokens" => 8,
      "max_output_tokens" => 4,
      "reserve_output_tokens" => 1
    }

  defp booked(snapshot), do: Map.new(snapshot["dimensions"], &{&1["unit"], &1["booked"]})

  defp replace(events, before, after_event),
    do: Enum.map(events, fn event -> if event == before, do: after_event, else: event end)

  defp rehash(event),
    do: Map.put(event, "source_sha256", digest(Map.delete(event, "source_sha256")))

  defp digest(value), do: Ipse.Compaction.digest([value])
  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp calls(ctx) do
    case File.read(Path.join(ctx.root, "embedding-http.jsonl")) do
      {:ok, bytes} -> bytes |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
      {:error, :enoent} -> []
    end
  end

  defp http(ctx, dimensions) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    owner = self()
    tag = make_ref()
    pid = spawn(fn -> accept_http(listener, ctx.root, dimensions, owner, tag) end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      Process.exit(pid, :kill)
    end)

    %{base: "http://127.0.0.1:#{port}", tag: tag, pid: pid}
  end

  defp accept_http(listener, root, dimensions, owner, tag) do
    case :gen_tcp.accept(listener, 30_000) do
      {:ok, socket} ->
        try do
          payload = read_http(socket, "")

          File.write!(Path.join(root, "embedding-http.jsonl"), Jason.encode!(payload) <> "\n", [
            :append
          ])

          :ok = :inet.setopts(socket, active: :once)
          send(owner, {:embedding_http, tag, self(), payload})

          receive do
            :respond ->
              body =
                Jason.encode!(%{
                  "model" => "fixture-resolved",
                  "embeddings" =>
                    Enum.with_index(payload["input"], fn _, index ->
                      [index + 1.0 | List.duplicate(-0.25, dimensions - 1)]
                    end),
                  "prompt_eval_count" => 23,
                  "total_duration" => 500_000
                })

              :gen_tcp.send(socket, [
                "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n",
                body
              ])

            {:tcp_closed, ^socket} ->
              send(owner, {:embedding_http_closed, tag, self()})

            {:tcp_error, ^socket, _} ->
              send(owner, {:embedding_http_closed, tag, self()})
          after
            30_000 -> :ok
          end
        after
          :gen_tcp.close(socket)
        end

        accept_http(listener, root, dimensions, owner, tag)

      _ ->
        :ok
    end
  end

  defp read_http(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [headers, body] ->
        [_, size] = Regex.run(~r/content-length:\s*(\d+)/i, headers)
        read_http_body(socket, body, String.to_integer(size)) |> Jason.decode!()

      _ ->
        {:ok, more} = :gen_tcp.recv(socket, 0, 10_000)
        read_http(socket, buffer <> more)
    end
  end

  defp read_http_body(_, body, size) when byte_size(body) >= size, do: binary_part(body, 0, size)

  defp read_http_body(socket, body, size) do
    {:ok, more} = :gen_tcp.recv(socket, 0, 10_000)
    read_http_body(socket, body <> more, size)
  end

  defp build_artifact(root, variant) do
    output = Path.join(root, Atom.to_string(variant))
    File.mkdir_p!(Path.join(output, "ebin"))
    module = "Independent.EmbeddingProbe#{System.unique_integer([:positive])}"
    caps = ~w(invoke.command host.actions host.embedding host.results host.actions.mixed)
    caps = if variant == :ungranted, do: caps -- ["host.embedding"], else: caps
    caps = if variant == :jobs, do: caps ++ ["event.job"], else: caps

    schema = %{
      "type" => "object",
      "required" => ~w(status reads bytes sha256 code),
      "additionalProperties" => false,
      "properties" => %{
        "status" => %{"type" => "string"},
        "reads" => %{"type" => "integer"},
        "bytes" => %{"type" => "integer"},
        "sha256" => %{"type" => "string"},
        "code" => %{"type" => "string"}
      }
    }

    command = %{
      "id" => "embed",
      "description" => "Synthetic embedding and typed result paging",
      "arguments_schema" => %{
        "type" => "object",
        "required" => ["request"],
        "additionalProperties" => false,
        "properties" => %{
          "request" => %{"type" => "object"},
          "read" => %{"type" => "boolean"},
          "read_override" => %{"type" => "object"}
        }
      },
      "result_schema" => schema
    }

    exports = Map.put(Ipse.Extensions.Catalog.empty(), "commands", [command])

    jobs = [
      %{
        "id" => "embed",
        "description" => "Explicit accounted synthetic embedding",
        "arguments_schema" => %{
          "type" => "object",
          "required" => ["event"],
          "additionalProperties" => false,
          "properties" => %{"event" => %{"type" => "object"}}
        },
        "result_schema" => schema
      }
    ]

    exports = if variant == :jobs, do: Map.put(exports, "jobs", jobs), else: exports

    subscriptions =
      if variant == :jobs,
        do: [
          %{
            "id" => "embed",
            "handler" => "embed",
            "event" => "prompt.effective_committed",
            "event_version" => 1,
            "view" => "metadata",
            "mode" => "job",
            "schedule" => "before_request",
            "required" => true
          }
        ],
        else: []

    source = """
    defmodule #{module} do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(caps)}, "exports" => #{inspect(exports)}, "subscriptions" => #{inspect(subscriptions)}}
      def init(options), do: {:ok, options}
      def handle("invoke.command", payload, _), do: begin(payload["arguments"])
      def handle("event.job", _, options), do: begin(%{"request" => options["request"], "read" => false})
      def handle("host.actions", payload, state) do
        outcome = payload["outcome"]
        state = %{state | status: outcome["status"], code: outcome["value"]["code"] || ""}
        case state.phase do
          :call ->
            if outcome["status"] == "ok" and state.args["read"] != false,
              do: page(state, outcome["value"]["result"], 0, 0), else: finish(state)
          {:read, descriptor, index} ->
            if outcome["status"] == "ok" do
              value = outcome["value"]
              state = %{state | reads: state.reads + 1, data: state.data <> Base.decode64!(value["values"])}
              cond do
                not value["complete"] -> page(state, descriptor, index, value["next"])
                index + 1 < descriptor["vector_count"] -> page(state, descriptor, index + 1, 0)
                true -> finish(state)
              end
            else
              finish(state)
            end
        end
      end
      defp begin(args), do: call(args["request"], %{args: args, phase: :call, status: "", code: "", reads: 0, data: ""})
      defp page(state, descriptor, index, offset) do
        request = %{"op" => "effect.result.read", "version" => 2, "operation_id" => descriptor["operation_id"], "source_sha256" => descriptor["source_sha256"], "vector_index" => index, "offset" => offset, "limit" => 768}
        call(Map.merge(request, state.args["read_override"] || %{}), %{state | phase: {:read, descriptor, index}})
      end
      defp call(request, state), do: {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request}, state}
      defp finish(state), do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => %{"status" => state.status, "reads" => state.reads, "bytes" => byte_size(state.data), "sha256" => Base.encode16(:crypto.hash(:sha256, state.data), case: :lower), "code" => state.code}}, state}
    end
    """

    source_path = Path.join(root, Atom.to_string(variant) <> ".ex")
    File.write!(source_path, source)

    {log, status} =
      System.cmd(
        System.find_executable("elixirc"),
        ["-pa", Application.app_dir(:ipse, "ebin"), "-o", Path.join(output, "ebin"), source_path],
        stderr_to_stdout: true
      )

    assert status == 0, log
    File.write!(Path.join(output, "LICENSE"), "MIT synthetic fixture")
    paths = ["LICENSE", "ebin/Elixir.#{module}.beam"]

    manifest = %{
      "format" => 1,
      "id" => "fixture/embedding-probe",
      "version" => "0.1.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => module,
      "license_file" => "LICENSE",
      "options_schema" => %{
        "type" => "object",
        "required" => ["request"],
        "additionalProperties" => false,
        "properties" => %{"request" => %{"type" => "object"}}
      },
      "capabilities" => caps,
      "exports" => exports,
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      },
      "files" =>
        Enum.map(paths, fn path ->
          bytes = File.read!(Path.join(output, path))
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Manifest.sha256(bytes)}
        end)
    }

    manifest =
      if subscriptions == [],
        do: manifest,
        else: Map.put(manifest, "subscriptions", subscriptions)

    File.write!(Path.join(output, "extension.json"), Jason.encode!(manifest))
    output
  end
end
