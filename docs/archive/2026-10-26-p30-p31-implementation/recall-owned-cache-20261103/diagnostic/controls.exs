root = Path.expand(__DIR__)
Code.prepend_paths(Path.wildcard("/dev/shm/ipse-json-current-20261103-01/_build/test/lib/*/ebin"))
Code.prepend_path(Path.join(root, "observer-beam"))

for module <- [Ipse.Test.RecallDiagnosticTrace, Ipse.Test.RecallDiagnostic] do
  Code.ensure_loaded!(module)
  expected = Path.join([root, "observer-beam", Atom.to_string(module) <> ".beam"])
  ^expected = module |> :code.which() |> List.to_string() |> Path.expand()
end

home = Path.join(root, "controls-home")
File.mkdir_p!(home)
File.chmod!(home, 0o700)
System.put_env("IPSE_HOME", home)
ExUnit.start()

defmodule Ipse.Test.RecallDiagnosticControls do
  use ExUnit.Case, async: false
  alias Ipse.Test.{RecallDiagnostic, RecallDiagnosticTrace}

  test "arity-only trace retains numeric deadlines, balanced returns and exact kill ancestry without payload" do
    {:ok, _} = Application.ensure_all_started(:ipse)
    {:ok, scope} = Ipse.Session.Resources.start(self())

    worker =
      spawn(fn ->
        receive do
          {:run, owner} ->
            Ipse.Session.Resources.bind(scope)

            result =
              Ipse.Session.Resources.controlled_owned_effect(
                fn ->
                  send(owner, {:controlled_peer, self()})

                  receive do
                    :never -> :ok
                  end
                end,
                1000
              )

            send(owner, {:controlled_result, result})
        end
      end)

    :ok = Ipse.Session.Resources.attach(scope, worker)
    trace = RecallDiagnosticTrace.start(self(), self(), true)

    on_exit(fn ->
      if Process.alive?(trace.pid), do: RecallDiagnosticTrace.finish(trace)
      if Process.alive?(worker), do: Process.exit(worker, :kill)
      if Process.alive?(scope), do: Ipse.Session.Resources.close(scope)
    end)

    private = "diagnostic-private-canary"

    for reason <- [
          :inference_connection_failed,
          :inference_request_failed,
          :source_replay_unavailable,
          :source_index_refused
        ] do
      assert RecallDiagnosticTrace.safe_error(reason) == %{"code" => Atom.to_string(reason)}
    end

    assert {:error, :inference_timeout} =
             RecallDiagnosticTrace.control(fn -> {:error, :inference_timeout} end)

    assert {:ok, %{private: ^private}} =
             RecallDiagnosticTrace.control(fn -> {:ok, %{private: private}} end)

    assert {:unknown, :cleanup_unconfirmed} = RecallDiagnosticTrace.numeric_control(private, 5000)

    reporter_alias = RecallDiagnosticTrace.identify(trace, worker)
    send(worker, {:run, self()})
    assert_receive {:controlled_peer, peer}, 3000
    peer_alias = RecallDiagnosticTrace.identify(trace, peer)
    assert_receive {:controlled_result, {:unknown, :effect_interrupted}}, 7000
    refute Process.alive?(peer)
    summary = RecallDiagnosticTrace.finish(trace)

    File.write!(Path.join(__DIR__, "controlled-wait-trace.json"), Jason.encode!(summary), [
      :exclusive
    ])

    refute summary["truncated"]
    assert summary["open_spans"] == []
    rows = summary["records"]
    assert Enum.count(rows, &(&1["event"] == "call")) >= 5

    assert Enum.count(rows, &(&1["event"] == "call")) ==
             Enum.count(rows, &(&1["event"] == "return"))

    assert Enum.any?(rows, &(&1["event"] == "call" and &1["timeout_ms"] == 5000))

    assert Enum.any?(
             rows,
             &(&1["event"] == "return" and &1["outcome"]["code"] == "inference_timeout")
           )

    assert [kill] = Enum.filter(rows, &(&1["event"] == "kill"))
    assert kill["pid"] == reporter_alias and kill["target"] == peer_alias

    assert [wait] =
             Enum.filter(
               rows,
               &(&1["event"] == "call" and
                   &1["mfa"] == "Elixir.Ipse.Session.Resources.controlled_wait/5")
             )

    assert wait["pid"] == reporter_alias

    assert [returned] =
             Enum.filter(rows, &(&1["event"] == "return" and &1["call_id"] == wait["call_id"]))

    assert returned["outcome"]["code"] == "effect_interrupted"
    assert wait["at_us"] < kill["at_us"] and kill["at_us"] < returned["at_us"]

    assert Enum.any?(
             summary["ancestry"],
             &(&1["parent"] == kill["pid"] and
                 &1["child"] == kill["target"])
           )

    refute Jason.encode!(summary) =~ private
  end

  test "trace pressure stops recording within fixed bounds and marks incomplete" do
    trace = RecallDiagnosticTrace.start(self(), self(), true)
    for _ <- 1..300, do: RecallDiagnosticTrace.control(fn -> :ok end)
    summary = RecallDiagnosticTrace.finish(trace)
    assert summary["truncated"]
    assert summary["record_count"] <= 512
    assert summary["participant_count"] <= 256
  end

  test "collector consumes actual error notification and retains listener phases before done" do
    control_root =
      Path.join(__DIR__, "control-error-" <> Integer.to_string(System.system_time(:microsecond)))

    File.mkdir!(control_root)
    File.chmod!(control_root, 0o700)

    session =
      spawn(fn ->
        receive do
          :finish -> :ok
        end
      end)

    server = Task.async(fn -> :closed end)

    send(
      self(),
      {:ipse, session,
       {:error, "Managed inference transport did not confirm native completion and cleanup."}}
    )

    RecallDiagnostic.listener(self(), "accepted", 0, nil)
    RecallDiagnostic.listener(self(), "first_read", 0, "closed")
    send(self(), {:ipse, session, {:done, :error}})

    assert {:ended, "error"} =
             RecallDiagnostic.request(
               session,
               server,
               control_root,
               nil,
               System.monotonic_time(:microsecond)
             )

    output =
      control_root |> Path.join("diagnostic-outcome.json") |> File.read!() |> Jason.decode!()

    assert [%{"reason" => %{"code" => "transport_completion_cleanup_unconfirmed"}}] =
             output["errors"]

    assert Enum.map(output["listener"], & &1["phase"]) == ["accepted", "first_read"]
    assert output["listener_task"]["class"] == "closed"
    refute_receive {:ipse, ^session, {:error, _}}
    send(session, :finish)
  end

  test "collector preserves positive request exactly and never writes request content" do
    control_root =
      Path.join(
        __DIR__,
        "control-positive-" <> Integer.to_string(System.system_time(:microsecond))
      )

    File.mkdir!(control_root)
    File.chmod!(control_root, 0o700)

    session =
      spawn(fn ->
        receive do
          :finish -> :ok
        end
      end)

    server = Task.async(fn -> :ok end)
    request = %{"private" => "positive-private-canary"}
    send(self(), {:recall_many_request, request})

    assert {:ok, ^request, state} =
             RecallDiagnostic.request(
               session,
               server,
               control_root,
               nil,
               System.monotonic_time(:microsecond)
             )

    send(self(), {:ipse, session, {:done, :ok}})
    assert :ok = RecallDiagnostic.complete(session, server, state)
    bytes = File.read!(Path.join(control_root, "diagnostic-outcome.json"))
    refute bytes =~ "positive-private-canary"
    send(session, :finish)
  end
end
