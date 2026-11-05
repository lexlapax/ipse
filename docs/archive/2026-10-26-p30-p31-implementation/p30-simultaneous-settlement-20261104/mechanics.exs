ExUnit.start(autorun: false)
Code.require_file("source/test/support/shadow_concurrent_trace.exs", __DIR__)

defmodule Ipse.Test.TargetedErrorProbe do
  def call(value), do: local_error(value)
  defp local_error(value), do: {:private_return, value}
  def legacy(value), do: {:legacy_return, value}
end

defmodule Ipse.Test.TargetedErrorMechanics do
  use ExUnit.Case, async: false
  alias Ipse.Test.{ShadowConcurrentTrace, TargetedErrorProbe}

  defp captured(
         values,
         function \\ :local_error,
         pattern \\ ShadowConcurrentTrace.dispatch_error_pattern()
       ) do
    parent = self()
    receiver = spawn(fn -> collect(parent, []) end)

    worker =
      spawn(fn ->
        receive do
          {:run, inputs} ->
            Enum.each(inputs, fn value ->
              if function == :local_error,
                do: TargetedErrorProbe.call(value),
                else: TargetedErrorProbe.legacy(value)
            end)

            send(parent, :ran)

            receive do
              :stop -> :ok
            end
        end
      end)

    mfa = {TargetedErrorProbe, function, 1}
    1 = :erlang.trace_pattern(mfa, pattern, [:local])
    1 = :erlang.trace(worker, true, [:call, :arity, :monotonic_timestamp, {:tracer, receiver}])
    send(worker, {:run, values})

    receive do
      :ran -> :ok
    after
      1000 -> flunk("probe did not complete")
    end

    delivery = :erlang.trace_delivered(worker)

    receive do
      {:trace_delivered, ^worker, ^delivery} -> :ok
    after
      1000 -> flunk("delivery unconfirmed")
    end

    send(receiver, :collect)

    rows =
      receive do
        {:rows, rows} -> rows
      after
        1000 -> flunk("collection unconfirmed")
      end

    1 = :erlang.trace(worker, false, [:call, :arity, :monotonic_timestamp])
    1 = :erlang.trace_pattern(mfa, false, [:local])
    send(worker, :stop)
    rows
  end

  defp collect(parent, rows) do
    receive do
      :collect -> send(parent, {:rows, Enum.reverse(rows)})
      row -> collect(parent, [row | rows])
    end
  end

  test "source-backed gate, cancel, wait and filesystem errors emit only constant labels" do
    gates =
      ~w(managed_dependency_unavailable inference_dispatch_refused consent_unavailable dispatch_owner_lost dispatch_gate_timeout invalid_service_gate service_gate_unavailable service_gate_timeout inference_route_changed)a

    inputs =
      Enum.map(gates, &{:service_gate_refused, &1}) ++
        ~w(service_wait_timeout service_cancelled service_filesystem_unsupported)a

    rows = captured(inputs)
    assert length(rows) == length(inputs)

    labels =
      Enum.map(rows, fn {:trace_ts, pid, :call, {TargetedErrorProbe, :local_error, 1}, label, at} ->
        assert is_pid(pid) and is_integer(at)
        label
      end)

    assert labels ==
             List.delete(ShadowConcurrentTrace.dispatch_error_labels(), :unknown_dispatch_error)

    refute Enum.any?(rows, &match?({:trace_ts, _, :return_from, _, _, _}, &1))
  end

  test "binary, maps, nested tuples and unknown atoms never enter new trace messages" do
    canary = "PRIVATE_PAYLOAD_MUST_NOT_BE_TRACED_47b673"

    values = [
      canary,
      %{canary => [canary]},
      {:service_gate_refused, %{canary => canary}},
      {:private, canary},
      {:service_gate_refused, :unknown_private_gate}
    ]

    rows = captured(values)
    assert length(rows) == length(values)

    assert Enum.all?(
             rows,
             &match?(
               {:trace_ts, _, :call, {TargetedErrorProbe, :local_error, 1},
                :unknown_dispatch_error, _},
               &1
             )
           )

    refute :binary.match(:erlang.term_to_binary(rows), canary) != :nomatch
    refute :binary.match(:erlang.term_to_binary(rows), "unknown_private_gate") != :nomatch
  end

  test "new label storage is bounded and malformed labels cannot be retained" do
    for module <- [Ipse.Extension.Consent, Ipse.Runner.Transaction],
        do: {:module, ^module} = Code.ensure_loaded(module)

    :code.purge(Ipse.InferenceDispatch)
    :code.delete(Ipse.InferenceDispatch)
    assert :code.is_loaded(Ipse.InferenceDispatch) == false
    tracer = ShadowConcurrentTrace.start("pure-root", "pure-project")
    assert match?({:file, _}, :code.is_loaded(Ipse.InferenceDispatch))

    for _ <- 1..17 do
      send(
        tracer,
        {:trace_ts, self(), :call, {Ipse.InferenceDispatch, :local_error, 1},
         :unknown_dispatch_error, 1}
      )
    end

    send(
      tracer,
      {:trace_ts, self(), :call, {Ipse.InferenceDispatch, :local_error, 1},
       %{"private_canary" => "must_not_persist"}, 1}
    )

    summary = ShadowConcurrentTrace.finish(tracer)
    assert length(summary.dispatch_errors) == 16
    assert Enum.all?(summary.dispatch_errors, &(&1 == :unknown_dispatch_error))
    assert summary.dispatch_errors_overflow
    refute :binary.match(:erlang.term_to_binary(summary), "must_not_persist") != :nomatch
    refute :ipse in Enum.map(Application.started_applications(), &elem(&1, 0))
  end

  test "matchspec validates fallback and never requests a return trace" do
    ms = ShadowConcurrentTrace.dispatch_error_pattern()

    assert {:ok, :unknown_dispatch_error, [], _} =
             :erlang.match_spec_test([%{"private" => "secret"}], ms, :trace)

    refute inspect(ms) =~ "return_trace"
    refute inspect(ms) =~ "$1"
  end

  test "real legacy calls retain the same argument and return observations under arity" do
    value = %{"legacy_fixture" => "safe"}
    ms = [{:"$1", [], [{:message, :"$1"}, {:return_trace}]}]
    rows = captured([value], :legacy, ms)

    assert [
             {:trace_ts, caller, :call, {TargetedErrorProbe, :legacy, 1}, [^value], first_at},
             {:trace_ts, caller, :return_from, {TargetedErrorProbe, :legacy, 1},
              {:legacy_return, ^value}, last_at}
           ] = rows

    assert first_at < last_at
  end

  test "legacy explicit argument message works with arity tracing" do
    ms = [{:"$1", [], [{:message, :"$1"}, {:return_trace}]}]

    assert {:ok, ["legacy", 1], [:return_trace], _} =
             :erlang.match_spec_test(["legacy", 1], ms, :trace)
  end
end

result = ExUnit.run()
if result.failures != 0, do: System.halt(1)
