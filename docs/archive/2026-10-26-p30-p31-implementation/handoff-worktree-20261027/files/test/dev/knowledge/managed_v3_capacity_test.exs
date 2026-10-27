for path <- ~w(notes.ex knowledge/records.ex knowledge/contracts.ex),
    do: Code.require_file("../../../extensions/knowledge/src/" <> path, __DIR__)

Code.require_file("../../../dev/knowledge/managed_v3_capacity.exs", __DIR__)

defmodule Ipse.Development.ManagedV3CapacityTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.ManagedV3Capacity, as: C
  alias Ipse.JSON
  alias Ipse.Development.ManagedV3Capacity.NativeFrames

  test "fixed bounds identify initial additions and leave turnover unimplemented" do
    assert C.limits() == %{
             "publications" => 4000,
             "segment_size" => 500,
             "segments" => 8,
             "soft_ms" => 360_000,
             "hard_ms" => 480_000,
             "beam_memory_limit" => 536_870_912,
             "max_heap_words" => 16_000_000,
             "turnover_implemented" => false
           }
  end

  test "timeout, truncation, nonzero exit and unknown supervision never confirm a process" do
    good = %{exit_code: 0, timed_out: false, output_truncated: false}
    assert C.process_status!({:ok, good}) == 0

    for result <- [
          {:unknown, "owner loss"},
          {:error, "refused"},
          {:ok, %{}},
          {:ok, Map.put(good, :exit_code, 86)},
          {:ok, Map.put(good, :timed_out, true)},
          {:ok, Map.put(good, :output_truncated, true)}
        ] do
      assert_raise RuntimeError, fn -> C.process_status!(result) end
    end
  end

  test "hostile helper configuration refuses without changing global environment" do
    assert :ok = C.check_configuration!(nil)

    for override <- ["", "/tmp/hostile-helper", "/tmp/missing-helper", "priv/ipse-runner"] do
      assert_raise RuntimeError, fn -> C.check_configuration!(override) end
    end
  end

  test "bootstrap and direct binding entry refuse an executable override before any path or helper access" do
    root = temp_root()
    hostile = root <> "/hostile-helper"
    File.write!(hostile, "#!/bin/sh\nexit 95\n", [:exclusive])
    File.chmod!(hostile, 0o700)
    script = Path.expand("../../../dev/knowledge/managed_v3_capacity.exs", __DIR__)
    repo = Path.expand("../../..", __DIR__)
    core = Ipse.JSON |> :code.which() |> List.to_string() |> Path.dirname()

    code = """
    Code.require_file(#{inspect(script)})
    for operation <- [&Ipse.Development.ManagedV3Capacity.bootstrap/1, &Ipse.Development.ManagedV3Capacity.bindings/1] do
      try do
        operation.("/missing-and-must-not-be-accessed")
        raise "override unexpectedly admitted"
      rescue
        error in RuntimeError -> true = Exception.message(error) == "capacity qualification refuses IPSE_RUNNER_PATH overrides"
      end
    end
    IO.puts("both entry points refused before path/helper access")
    """

    {output, 0} =
      System.cmd(
        System.find_executable("elixir"),
        ["-pa", repo <> "/_build/test/lib/*/ebin", "-pa", core, "-e", code],
        env: [{"IPSE_RUNNER_PATH", hostile}],
        stderr_to_stdout: true
      )

    assert output == "both entry points refused before path/helper access\n"
  end

  defp frame(kind, payload), do: <<kind, byte_size(payload)::unsigned-big-32, payload::binary>>

  test "protected transport handles every byte split and both output channels before terminal" do
    wire =
      frame(?O, "out") <> frame(?S, "err") <> frame(?X, ~s({"exit_code":0,"timed_out":false}))

    for split <- 0..byte_size(wire) do
      <<first::binary-size(^split), second::binary>> = wire
      {state, left} = NativeFrames.push(NativeFrames.new(), first)
      {state, right} = NativeFrames.push(state, second)
      assert IO.iodata_to_binary(left ++ right) == "outerr"
      assert :ok = NativeFrames.finish!(state)
    end
  end

  test "protected transport refuses incomplete, oversized, malformed and post-terminal data" do
    assert_raise RuntimeError, fn -> NativeFrames.finish!(NativeFrames.new()) end
    assert_raise MatchError, fn -> NativeFrames.push(NativeFrames.new(), <<?O, 8193::32>>) end

    assert_raise MatchError, fn ->
      NativeFrames.push(%{NativeFrames.new() | traffic: 8 * 1024 * 1024}, <<0>>)
    end

    assert_raise MatchError, fn ->
      NativeFrames.push(%{NativeFrames.new() | bytes: 4 * 1024 * 1024}, frame(?O, "x"))
    end

    for payload <- [
          ~s({"exit_code":0,"exit_code":1,"timed_out":false}),
          ~s({"exit_code":0,"timed_out":false,"extra":true}),
          "invalid"
        ] do
      assert_raise MatchError, fn -> NativeFrames.push(NativeFrames.new(), frame(?X, payload)) end
    end

    assert_raise RuntimeError, fn ->
      NativeFrames.push(NativeFrames.new(), frame(?E, "refused"))
    end

    for payload <- [~s({"exit_code":86,"timed_out":false}), ~s({"exit_code":0,"timed_out":true})] do
      {state, []} = NativeFrames.push(NativeFrames.new(), frame(?X, payload))
      assert_raise RuntimeError, fn -> NativeFrames.finish!(state) end
    end

    {state, []} =
      NativeFrames.push(NativeFrames.new(), frame(?X, ~s({"exit_code":0,"timed_out":false})))

    assert_raise RuntimeError, fn -> NativeFrames.push(state, <<?O>>) end
  end

  test "controller observes supervisor exit and refuses separately delivered data after terminal" do
    root = temp_root()
    {:ok, io} = File.open(root <> "/output", [:write, :binary, :exclusive])
    on_exit(fn -> File.close(io) end)
    terminal = frame(?X, ~s({"exit_code":0,"timed_out":false}))
    deadline = System.monotonic_time(:millisecond) + 1_000

    good = make_ref()
    send(self(), {good, {:data, frame(?O, "ok") <> terminal}})
    send(self(), {good, {:exit_status, 0}})
    assert %{terminal: %{exit_code: 0}} = C.collect_frames(good, io, NativeFrames.new(), deadline)

    trailing = make_ref()
    send(self(), {trailing, {:data, terminal}})
    send(self(), {trailing, {:data, frame(?O, "late")}})

    assert_raise RuntimeError, "native bytes after terminal result", fn ->
      C.collect_frames(trailing, io, NativeFrames.new(), deadline)
    end

    unconfirmed = make_ref()
    send(self(), {unconfirmed, {:exit_status, 0}})

    assert_raise RuntimeError, fn ->
      C.collect_frames(unconfirmed, io, NativeFrames.new(), deadline)
    end
  end

  test "controller reads a real port through its terminal frame and exit" do
    root = temp_root()
    {:ok, io} = File.open(root <> "/port-output", [:write, :binary, :exclusive])
    on_exit(fn -> File.close(io) end)
    wire = frame(?O, "port") <> frame(?X, ~s({"exit_code":0,"timed_out":false}))

    octal =
      for <<byte <- wire>>, into: "" do
        "\\" <> String.pad_leading(Integer.to_string(byte, 8), 3, "0")
      end

    port =
      Port.open({:spawn_executable, ~c"/bin/sh"}, [
        :binary,
        :exit_status,
        args: ["-c", "printf '" <> octal <> "'"]
      ])

    deadline = System.monotonic_time(:millisecond) + 2_000
    assert %{terminal: %{exit_code: 0}} = C.collect_frames(port, io, NativeFrames.new(), deadline)
    assert :ok = :file.sync(io)
    assert File.read!(root <> "/port-output") == "port"
  end

  defp temp_root do
    root =
      Path.join(System.tmp_dir!(), "ipse-capacity-source-#{System.unique_integer([:positive])}")

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  test "store admission requires private concrete paths, an isolated fresh leaf and fixed parent" do
    root = temp_root()
    graph = root <> "/graph"
    parent = root <> "/_build/storage-workloads"
    File.mkdir!(graph)
    File.chmod!(graph, 0o700)
    File.mkdir_p!(parent)
    store = parent <> "/ipse-managed-v3-capacity-source-control"
    location = C.location!(graph, store, :new)
    plan = %{"graph" => graph, "store" => store, "location" => location}
    assert :ok = C.check_location!(plan, :new)
    File.ln_s!(graph, store)
    assert_raise RuntimeError, fn -> C.location!(graph, store, :new) end
    File.rm!(store)
    File.mkdir!(store)
    File.chmod!(store, 0o700)

    for name <- ~w(home work oracle) do
      File.mkdir!(store <> "/" <> name)
      File.chmod!(store <> "/" <> name, 0o700)
    end

    assert C.location!(graph, store, :existing) == location
    assert_raise RuntimeError, fn -> C.location!(graph, store, :new) end
    File.rmdir!(store <> "/home")
    File.ln_s!(graph, store <> "/home")
    assert_raise MatchError, fn -> C.location!(graph, store, :existing) end
    File.ln_s!(root <> "/_build", root <> "/alias")

    assert_raise MatchError, fn ->
      C.location!(graph, root <> "/alias/storage-workloads/ipse-managed-v3-capacity-x", :new)
    end

    assert_raise MatchError, fn ->
      C.location!(graph, root <> "/ipse-managed-v3-capacity-x", :new)
    end

    File.mkdir_p!(graph <> "/_build/storage-workloads")

    assert_raise MatchError, fn ->
      C.location!(graph, graph <> "/_build/storage-workloads/ipse-managed-v3-capacity-x", :new)
    end

    File.rename!(parent, parent <> "-original")
    File.mkdir!(parent)
    assert_raise MatchError, fn -> C.check_location!(plan, :new) end
  end

  defp source_graph do
    graph = temp_root()

    for path <-
          [
            "test/support/managed_policy.exs",
            "test/ipse/extension/collection_normalizer_v3_test.exs",
            "test/ipse/extension/collection_normalizer_v3_integration_test.exs"
          ] ++
            Enum.map(
              ~w(notes.ex knowledge/records.ex knowledge/contracts.ex),
              &("extensions/knowledge/src/" <> &1)
            ) do
      target = graph <> "/project/" <> path
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, File.read!(Path.expand("../../../" <> path, __DIR__)), [:exclusive])
    end

    graph
  end

  test "all dynamic source bytes include managed policy and reject edits before compilation" do
    graph = source_graph()
    expected = C.source_inputs(graph)
    policy = graph <> "/project/test/support/managed_policy.exs"
    assert expected[policy] == JSON.sha256(File.read!(policy))
    assert map_size(expected) == 7
    assert :ok = C.check_source_inputs!(graph, expected)
    File.write!(policy, "raise \"must never execute\"\n")
    assert_raise MatchError, fn -> C.load_sources(graph, expected) end
    assert_raise MatchError, fn -> C.check_source_inputs!(graph, expected) end
  end

  test "non-native bootstrap loads the complete source graph with six exact module origins" do
    graph = source_graph()
    script = Path.expand("../../../dev/knowledge/managed_v3_capacity.exs", __DIR__)
    repo = Path.expand("../../..", __DIR__)
    core = Ipse.JSON |> :code.which() |> List.to_string() |> Path.dirname()

    code = """
    Code.require_file(#{inspect(script)})
    original_home = System.get_env("HOME")
    :ok = Ipse.Development.ManagedV3Capacity.bootstrap(#{inspect(graph)})
    true = System.get_env("HOME") == original_home
    origins = Ipse.Development.ManagedV3Capacity.dynamic_origins!(#{inspect(graph)})
    true = map_size(origins) == 6
    true = origins["Elixir.Ipse.Test.ManagedPolicy"] == #{inspect(graph <> "/project/test/support/managed_policy.exs")}
    IO.puts("complete source bootstrap; 6 module origins; HOME unchanged; no helper called")
    """

    {output, 0} =
      System.cmd(
        System.find_executable("elixir"),
        ["-pa", repo <> "/_build/test/lib/*/ebin", "-pa", core, "-e", code],
        env: [{"IPSE_RUNNER_PATH", nil}],
        stderr_to_stdout: true
      )

    assert output ==
             "complete source bootstrap; 6 module origins; HOME unchanged; no helper called\n"
  end

  test "only the reviewed private helper digest is admitted" do
    assert :ok = C.check_helper_sha256!(C.helper_sha256())

    for wrong <- [
          nil,
          String.upcase(C.helper_sha256()),
          JSON.sha256("unreviewed helper"),
          "108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29"
        ] do
      assert_raise MatchError, fn -> C.check_helper_sha256!(wrong) end
    end
  end

  test "the complete deterministic plan is checked before effects and legacy plans refuse" do
    rows = for n <- 1..4000, do: C.planned_row(n, C.options(n))
    opts = C.options(1)

    plan = %{
      "version" => 3,
      "graph" => "/tmp/declared-plan-fixture",
      "kind" => "author_actual_core3_normalizer3_capacity",
      "limits" => C.limits(),
      "targets" => [2000, 4000],
      "controls" => [201, 1201, 2201, 3201],
      "synthetic_sources" => true,
      "live_source_authority" => false,
      "annual_qualified" => false,
      "performance_qualified" => false,
      "actual_session_turns" => 0,
      "models" => 0,
      "rows" => rows,
      "recipe_sha256" => JSON.digest([opts.recipe]),
      "constraints_sha256" => JSON.digest([opts.constraints]),
      "policy_sha256" => opts.policy_sha256
    }

    assert :ok = C.check_plan!(plan, plan["graph"])

    for altered <- [
          Map.put(plan, "version", 2),
          Map.put(plan, "models", 1),
          Map.put(plan, "rows", Enum.reverse(rows)),
          put_in(plan, ["limits", "publications"], 4001)
        ] do
      assert_raise MatchError, fn -> C.check_plan!(altered, plan["graph"]) end
    end

    corrupted = List.update_at(rows, 12, &Map.put(&1, "policy_sha256", JSON.sha256("changed")))

    assert_raise MatchError, fn ->
      C.check_plan!(Map.put(plan, "rows", corrupted), plan["graph"])
    end
  end

  test "actual regenerated calls must match every frozen field before publication" do
    opts = C.options(201)
    row = C.planned_row(201, opts)
    assert row["value_bytes"] == 5588
    assert row["category"] == "ordinary"
    assert :ok = C.check_row!(row, 201, opts)

    for field <- Map.keys(row) do
      assert_raise MatchError, fn -> C.check_row!(Map.put(row, field, "changed"), 201, opts) end
    end

    assert_raise MatchError, fn -> C.check_row!(Map.put(row, "extra", true), 201, opts) end
    assert_raise MatchError, fn -> C.check_row!(row, 202, C.options(202)) end

    for key <- [:now_ms, :policy_sha256, :recipe, :constraints, :request, :verified_sources] do
      altered =
        case key do
          :now_ms ->
            Map.put(opts, key, opts.now_ms - 1)

          :policy_sha256 ->
            Map.put(opts, key, JSON.sha256("another policy"))

          :verified_sources ->
            Map.put(opts, key, [
              Map.put(hd(opts.verified_sources), "receipt_sha256", JSON.sha256("changed"))
            ])

          _ ->
            Map.put(opts, key, Map.put(opts[key], "changed", true))
        end

      assert_raise MatchError, fn -> C.check_row!(row, 201, altered) end
    end
  end

  defp completion do
    plan = %{"fixture" => "declared plan, no native execution"}
    binding = %{"fixture" => "declared runtime"}
    calls = Enum.map(1..500, &%{"n" => &1})

    report = %{
      "state" => "confirmed",
      "segment" => 1,
      "last" => 500,
      "checkpoint" => %{"notes" => 500, "status" => %{"generation" => 500, "operations" => 500}},
      "plan_sha256" => JSON.digest([plan]),
      "binding_sha256" => JSON.digest([binding]),
      "automatic_retries" => 0,
      "qualification_passed" => false,
      "performance_qualified" => false,
      "samples" => calls
    }

    {plan, binding, report, calls, JSON.sha256("declared process log")}
  end

  test "only an observed zero exit with identical terminal artifacts yields a clean record" do
    {p, b, r, calls, log} = completion()
    clean = C.clean_record!(1, p, b, r, r, calls, 0, log)
    assert clean["exit_status"] == 0
    assert clean["report_sha256"] == JSON.digest([r])
    assert clean["kind"] == "managed_v3_capacity_clean_exit"

    for status <- [1, 86, nil, "0"] do
      assert_raise MatchError, fn -> C.clean_record!(1, p, b, r, r, calls, status, log) end
    end

    for altered <- [
          Map.put(r, "state", "pending"),
          Map.put(r, "last", 499),
          Map.put(r, "automatic_retries", 1),
          Map.put(r, "qualification_passed", true),
          put_in(r, ["checkpoint", "status", "generation"], 499)
        ] do
      assert_raise MatchError, fn -> C.clean_record!(1, p, b, altered, altered, calls, 0, log) end
    end

    assert_raise MatchError, fn ->
      C.clean_record!(1, p, b, r, Map.put(r, "state", "pending"), calls, 0, log)
    end

    assert_raise MatchError, fn -> C.clean_record!(1, p, b, r, r, Enum.reverse(calls), 0, log) end
    assert_raise MatchError, fn -> C.clean_record!(1, p, b, r, r, calls, 0, nil) end
  end

  test "attempt markers and immutable outputs refuse overwrite" do
    dir =
      Path.join(
        System.tmp_dir!(),
        "ipse-capacity-source-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    path = dir <> "/attempt.json"
    record = C.attempt_record(1, %{}, %{})
    assert :ok = C.save_new(path, record)
    assert C.read(path) == record
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
    assert_raise MatchError, fn -> C.save_new(path, %{"replacement" => true}) end
    assert C.read(path) == record
  end

  test "only one child may enter an attempt, even without any native operation" do
    dir =
      Path.join(System.tmp_dir!(), "ipse-capacity-claim-#{System.unique_integer([:positive])}")

    File.mkdir!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    plan = %{"fixture" => "plan"}
    binding = %{"fixture" => "binding"}
    C.save_new(dir <> "/segment-1.attempt.json", C.attempt_record(1, plan, binding))
    assert_raise MatchError, fn -> C.claim_attempt!(dir, 1, %{}, binding) end
    assert :ok = C.claim_attempt!(dir, 1, plan, binding)
    assert_raise MatchError, fn -> C.claim_attempt!(dir, 1, plan, binding) end
  end

  test "a matching oracle/report without a controller exit receipt cannot continue" do
    {p, b, r, calls, _log} = completion()

    dir =
      Path.join(
        System.tmp_dir!(),
        "ipse-capacity-continuation-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir <> "/store/oracle/1")
    on_exit(fn -> File.rm_rf!(dir) end)
    r = Map.put(r, "store_identity", C.directory_identity!(dir <> "/store"))
    C.save_new(dir <> "/segment-1.report.json", r)
    C.save_new(dir <> "/store/oracle/1/root.json", r)

    File.write!(
      dir <> "/segment-1.calls.jsonl",
      Enum.map_join(calls, "\n", &Jason.encode!/1) <> "\n"
    )

    File.write!(dir <> "/segment-1.process.log", "declared process log")
    assert_raise File.Error, fn -> C.check_previous!(dir, dir <> "/store", 1, p, b) end
    clean = C.clean_record!(1, p, b, r, r, calls, 0, JSON.sha256("declared process log"))
    C.save_new(dir <> "/segment-1.clean.json", clean)
    assert :ok = C.check_previous!(dir, dir <> "/store", 1, p, b)
    File.write!(dir <> "/segment-1.process.log", "changed after controller")
    assert_raise MatchError, fn -> C.check_previous!(dir, dir <> "/store", 1, p, b) end
  end
end
