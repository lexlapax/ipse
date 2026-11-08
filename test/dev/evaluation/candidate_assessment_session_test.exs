Code.require_file("../../../dev/evaluation/candidate_assessment_session.exs", __DIR__)

defmodule Ipse.Development.Evaluation.CandidateAssessmentSessionTest do
  use ExUnit.Case, async: true
  alias Ipse.JSON
  alias Ipse.Extension.{Invocation, ResultDocument, ResultSource}
  alias Ipse.Extension.{Actions, DecisionCall}
  alias Ipse.Config.Decisions
  alias Ipse.Session.ManagedOutput
  alias Ipse.Development.Evaluation.CandidateAssessment, as: A
  alias Ipse.Development.Evaluation.CandidateAssessmentSession, as: S

  test "a failed or interrupted close is never retried by cleanup" do
    for outcome <- [:unconfirmed, :exit] do
      owner = self()

      fake_close = fn pid ->
        send(owner, {:close_attempt, outcome, pid})

        case outcome do
          :unconfirmed -> {:error, :cleanup_unconfirmed}
          :exit -> exit(:synthetic_timeout)
        end
      end

      run = fn ->
        S.with_close_guard(self(), fn close -> :ok = close.() end, fake_close)
      end

      case outcome do
        :unconfirmed -> assert_raise MatchError, run
        :exit -> assert catch_exit(run.()) == :synthetic_timeout
      end

      assert_receive {:close_attempt, ^outcome, ^owner}
      refute_receive {:close_attempt, ^outcome, _}
    end
  end

  test "cleanup can make the first close and a confirmed close is not repeated" do
    owner = self()

    fake_close = fn pid ->
      send(owner, {:close_attempt, pid})
      :ok
    end

    assert :ok = S.with_close_guard(self(), fn close -> close.() end, fake_close)
    assert_receive {:close_attempt, ^owner}
    refute_receive {:close_attempt, _}
  end

  test "cleanup performs the first close when work fails before explicit close" do
    owner = self()

    fake_close = fn pid ->
      send(owner, {:close_attempt, pid})
      :ok
    end

    assert_raise RuntimeError, fn ->
      S.with_close_guard(self(), fn _close -> raise "synthetic failure" end, fake_close)
    end

    assert_receive {:close_attempt, ^owner}
    refute_receive {:close_attempt, _}
  end


  defmodule ReviewOwner do
    use GenServer

    def start_link(state), do: GenServer.start_link(__MODULE__, state)
    def init(state), do: {:ok, Map.put(state, :public_refusals, 0)}
    def handle_call(:info, _, state), do: {:reply, {:error, :session_share_frozen}, state}

    def handle_call({:approve, _, true}, _, state),
      do:
        {:reply, {:error, :session_share_frozen},
         %{state | public_refusals: state.public_refusals + 1}}
  end

  test "approval coordination observes the owned review state while public approval stays frozen" do
    owner =
      start_supervised!(
        {ReviewOwner,
         %{
           phase: :managed_approval,
           share_barrier: %{phase: :review_input},
           managed_approval: %{id: "fixture-only"}
         }}
      )

    assert {:error, :session_share_frozen} = Ipse.Session.info(owner)
    assert S.approval_control_ready?(owner, 10, 20)
    assert :sys.get_state(owner).public_refusals === 1
    :sys.replace_state(owner, &%{&1 | phase: :idle})
    refute S.approval_control_ready?(owner, 11, 20)
    assert :sys.get_state(owner).public_refusals === 1
    assert_raise ExUnit.AssertionError, fn -> S.approval_control_ready?(owner, 20, 20) end
  end

  defp fixture do
    id = String.duplicate("1", 32)
    artifact = JSON.sha256("constructed artifact")
    root = "/dev/shm/ipse-candidate-shadow-constructed"

    config = %{
      provider: :ollama,
      model: "constructed",
      base_url: "http://127.0.0.1:1",
      timeout_ms: 15_000,
      home: root <> "/home",
      approval: :ask,
      headless: false,
      accept_edits: false,
      extensions: [
        %{
          identity: %{
            "instance" => "knowledge",
            "artifact_sha256" => artifact,
            "capabilities" => ["host.decision"]
          }
        }
      ],
      decision_profiles: %{
        "advice" => %{
          "operation" => "decision",
          "provider" => "system_one_compatible",
          "model" => "constructed",
          "base_url" => "http://127.0.0.1:2",
          "service_id" => "fixture_service"
        }
      }
    }

    input =
      Jason.encode!(%{
        "candidate_id" => JSON.sha256("candidate"),
        "text" => "Constructed candidate",
        "assigned_category" => "ordinary",
        "reason" => "constructed"
      })

    source =
      Jason.encode!(%{
        "version" => 1,
        "session_id" => id,
        "journal_sha256" => JSON.sha256("constructed journal")
      })

    key = "pending." <> JSON.sha256("candidate")

    baseline =
      Jason.encode!(%{
        "version" => 1,
        "case_id" => id,
        "input_sha256" => JSON.sha256(input),
        "source_receipt_sha256" => JSON.sha256(source),
        "candidate_key" => key,
        "stratum" => "pending",
        "baseline" => "keep",
        "admission" => "pending",
        "journal_sha256" => JSON.sha256("constructed journal"),
        "operation_id" => id,
        "elapsed_ms" => nil,
        "cost_nanos" => nil
      })

    c = %{
      "id" => id,
      "stratum" => "pending",
      "candidate_key" => key,
      "input_sha256" => JSON.sha256(input),
      "baseline_sha256" => JSON.sha256(baseline),
      "source_receipt_sha256" => JSON.sha256(source)
    }

    spec = %{
      "version" => 2,
      "kind" => "candidate_shadow",
      "source_sha256" => JSON.sha256("source"),
      "runtime_sha256" => JSON.sha256("runtime"),
      "artifact_sha256" => artifact,
      "main_route_sha256" => S.route_digest(config),
      "policy_sha256" => JSON.sha256("policy"),
      "label_commitment" => JSON.sha256("unopened labels"),
      "decision_route" => %{
        "engine" => "compatible_loopback",
        "model" => "constructed",
        "rubric_sha256" => JSON.sha256("rubric"),
        "profile_sha256" => elem(S.decision_route_digest(config), 1),
        "availability" => "unverified_access"
      },
      "shared_limits" =>
        Map.new(
          ~w(operations model_calls input_bytes output_bytes download_bytes cost_nanos),
          &{&1, 1}
        ),
      "cases" => [c]
    }

    {:ok, declaration} = A.declare(spec)
    blobs = Map.new([input, source, baseline], &{JSON.sha256(&1), &1})

    %{
      declaration: declaration,
      sha: JSON.digest([declaration]),
      id: id,
      load: &Map.fetch(blobs, &1),
      options: %{
        enabled: false,
        root: root,
        output: Path.join([root, "cases", id]),
        cwd: root <> "/project",
        state_dir: root <> "/sessions",
        config: config
      }
    }
  end

  @tag :candidate_off_preflight
  test "matching OFF preflight starts no App or Session and grants nothing" do
    if System.get_env("IPSE_CANDIDATE_OFF_PREFLIGHT_CHILD") == "1" do
      f = fixture()
      refute Enum.any?(Application.started_applications(), &(elem(&1, 0) == :ipse))
      assert Process.whereis(Ipse.Sessions) === nil
      assert Process.whereis(Ipse.Session.Input) === nil
      ports = Port.list() |> Enum.sort()
      assert {:ok, p} = S.prepare(f.declaration, f.sha, f.id, f.load, f.options)
      assert p.recipe["status"] == "off" and p.recipe["note_mutation"] == "none"
      assert {:error, :execution_disabled} = S.run(f.declaration, f.sha, f.id, f.load, f.options)
      assert {:error, :execution_disabled} = S.main([])
      refute Enum.any?(Application.started_applications(), &(elem(&1, 0) == :ipse))
      assert Process.whereis(Ipse.Sessions) === nil
      assert Process.whereis(Ipse.Session.Input) === nil
      assert Enum.sort(Port.list()) === ports
    else
      paths =
        :code.get_path()
        |> Enum.map(&List.to_string/1)
        |> Enum.reject(&(&1 == "."))
        |> Enum.map(&Path.expand/1)
        |> Enum.reverse()
        |> Enum.flat_map(&["-pa", &1])

      expression = """
      ExUnit.start(autorun: false, exclude: [:test], include: [:candidate_off_preflight])
      Code.require_file(#{inspect(__ENV__.file)})
      result = ExUnit.run()
      if result.failures != 0 or result.skipped != 0 or result.total - result.excluded != 1,
        do: System.halt(1)
      IO.puts("OFF_PREFLIGHT_ISOLATED_PASS")
      """

      {output, status} =
        System.cmd(
          System.find_executable("elixir"),
          ["--erl", "+S 1:1 +A 1 +SDcpu 1 +SDio 1"] ++ paths ++ ["-e", expression],
          env: [{"IPSE_CANDIDATE_OFF_PREFLIGHT_CHILD", "1"}],
          stderr_to_stdout: true
        )

      assert status === 0, output
      assert output =~ "OFF_PREFLIGHT_ISOLATED_PASS"
    end
  end

  test "declaration mismatch refuses before even the read-only loader" do
    f = fixture()

    load = fn _ ->
      send(self(), :opened_input)
      {:error, :missing}
    end

    changed = put_in(f.declaration, ["spec", "artifact_sha256"], JSON.sha256("changed"))

    assert {:error, :candidate_execution_preflight} =
             S.prepare(changed, f.sha, f.id, load, f.options)

    refute_received :opened_input
  end

  @tag :route_preflight
  test "Ollama response schema changes the main route digest and request" do
    base = %{provider: :ollama, model: "fixture"}
    schema = %{"type" => "object", "properties" => %{"answer" => %{"type" => "string"}}}
    changed = Map.put(base, :extension_response_schema, schema)

    refute Map.has_key?(Ipse.Provider.Ollama.request_body(base, [], []), "format")
    assert Map.fetch!(Ipse.Provider.Ollama.request_body(changed, [], []), "format") == schema
    assert S.route_digest(base) != S.route_digest(changed)
  end

  @tag :route_preflight
  test "Anthropic fallback token limit changes the main route digest and request" do
    base = %{provider: :anthropic, model: "fixture", max_tokens: 256}
    changed = %{base | max_tokens: 512}

    assert Map.fetch!(Ipse.Provider.Anthropic.request_body(base, [], []), "max_tokens") == 256
    assert Map.fetch!(Ipse.Provider.Anthropic.request_body(changed, [], []), "max_tokens") == 512
    assert S.route_digest(base) != S.route_digest(changed)
  end

  @tag :route_preflight
  test "Ollama context and model pin change the main route digest" do
    pin = %{
      "version" => 1,
      "trust_boundary" => "cooperative_service_metadata",
      "manifest_sha256" => JSON.sha256("model"),
      "metadata_sha256" => JSON.sha256("metadata"),
      "runtime_version" => "0.1.0",
      "minimum_context_tokens" => 8192
    }

    base = %{
      provider: :ollama,
      model: "fixture",
      ollama_context_tokens: 8192,
      ollama_model_pin: pin
    }

    assert Ipse.Provider.Ollama.Models.valid_pin?(pin)
    assert S.route_digest(base) != S.route_digest(%{base | ollama_context_tokens: 16384})

    assert S.route_digest(base) !=
             S.route_digest(
               put_in(base, [:ollama_model_pin, "manifest_sha256"], JSON.sha256("other"))
             )
  end

  @tag :route_preflight
  test "changed route, artifact, scripted provider and decision model refuse before actors" do
    f = fixture()

    ollama_pin = %{
      "version" => 1,
      "trust_boundary" => "cooperative_service_metadata",
      "manifest_sha256" => JSON.sha256("model"),
      "metadata_sha256" => JSON.sha256("metadata"),
      "runtime_version" => "0.1.0",
      "minimum_context_tokens" => 8192
    }

    assert Ipse.Provider.Ollama.Models.valid_pin?(ollama_pin)

    for config <- [
          Map.put(f.options.config, :provider_module, Scripted),
          Map.put(f.options.config, :base_url, "http://127.0.0.1:2"),
          Map.put(f.options.config, :upstream, "other-upstream"),
          Map.put(f.options.config, :reasoning_effort, "high"),
          Map.put(f.options.config, :data_collection, "allow"),
          Map.put(f.options.config, :max_output_tokens, 128),
          Map.put(f.options.config, :max_tokens, 128),
          Map.put(f.options.config, :max_response_bytes, 4096),
          Map.put(f.options.config, :max_steps, 10),
          Map.put(f.options.config, :context_bytes, 4096),
          Map.put(f.options.config, :compact, false),
          Map.put(f.options.config, :compact_summary_bytes, 512),
          Map.put(f.options.config, :compact_threshold_bytes, 2048),
          Map.put(f.options.config, :ollama_context_tokens, 8192),
          Map.put(f.options.config, :ollama_model_pin, ollama_pin),
          Map.put(f.options.config, :extension_response_schema, %{"type" => "object"}),
          Map.put(f.options.config, :summary_schema, %{"type" => "object"}),
          put_in(
            f.options.config,
            [:decision_profiles, "other"],
            f.options.config.decision_profiles["advice"]
          ),
          put_in(
            f.options.config,
            [:extensions, Access.at(0), :identity, "artifact_sha256"],
            JSON.sha256("foreign")
          ),
          put_in(f.options.config, [:decision_profiles, "advice", "model"], "foreign"),
          put_in(
            f.options.config,
            [:decision_profiles, "advice", "base_url"],
            "http://127.0.0.1:3"
          ),
          put_in(f.options.config, [:decision_profiles, "advice", "service_id"], "other_service"),
          put_in(f.options.config, [:decision_profiles, "advice", "pricing"], "changed price"),
          put_in(f.options.config, [:decision_profiles, "advice", "timeout_ms"], 1000),
          put_in(f.options.config, [:decision_profiles, "advice", "expected_model"], "foreign"),
          f.options.config
          |> put_in([:decision_profiles, "advice", "expected_model"], "constructed")
          |> put_in([:decision_profiles, "advice", "model"], "foreign")
        ] do
      assert {:error, :candidate_execution_preflight} =
               S.prepare(f.declaration, f.sha, f.id, f.load, %{f.options | config: config})
    end
  end

  @tag :route_preflight
  test "exact reviewed advice profile is bound before any actor starts" do
    f = fixture()
    assert {:ok, _} = S.prepare(f.declaration, f.sha, f.id, f.load, f.options)

    changed_spec =
      put_in(f.declaration["spec"], ["decision_route", "profile_sha256"], JSON.sha256("other"))

    assert {:ok, changed} = A.declare(changed_spec)
    changed_sha = JSON.digest([changed])
    assert :ok = A.verify(changed, changed_sha)

    assert {:error, :candidate_execution_preflight} =
             S.prepare(changed, changed_sha, f.id, f.load, f.options)

    missing =
      update_in(f.declaration, ["spec", "decision_route"], &Map.delete(&1, "profile_sha256"))

    assert {:error, :invalid_candidate_experiment} = A.declare(missing["spec"])
  end

  @tag :route_preflight
  test "historical version-one declarations remain valid but cannot start new work" do
    f = fixture()

    spec =
      f.declaration["spec"]
      |> Map.put("version", 1)
      |> update_in(["decision_route"], &Map.delete(&1, "profile_sha256"))

    assert {:ok, legacy} = A.declare(spec)
    digest = JSON.digest([legacy])
    assert :ok = A.verify(legacy, digest)

    assert {:error, :candidate_execution_preflight} =
             S.prepare(legacy, digest, f.id, f.load, f.options)
  end

  test "outside paths, bare yes and headless contexts cannot select this native owner" do
    f = fixture()

    for options <- [
          %{f.options | output: "/tmp/outside"},
          %{f.options | state_dir: f.options.root <> "/../outside"},
          put_in(f.options, [:config, :approval], :allow),
          put_in(f.options, [:config, :headless], true),
          put_in(f.options, [:config, :accept_edits], true)
        ] do
      assert {:error, :candidate_execution_preflight} =
               S.prepare(f.declaration, f.sha, f.id, f.load, options)
    end
  end

  test "changed or malformed source commitments cannot reach a protected read" do
    f = fixture()

    bad = fn digest ->
      {:ok, bytes} = f.load.(digest)
      {:ok, bytes <> " "}
    end

    assert {:error, :candidate_execution_preflight} =
             S.prepare(f.declaration, f.sha, f.id, bad, f.options)

    assert {:error, :candidate_execution_preflight} =
             S.prepare(f.declaration, f.sha, String.duplicate("f", 32), f.load, f.options)
  end

  test "known row requires newly settled exact input and complete current release" do
    f = fixture()
    {:ok, p} = S.prepare(f.declaration, f.sha, f.id, f.load, f.options)
    {events, action, result} = delivery(p, :inline)
    {before, after_policy} = policies(action)
    row = S.result_row(p, events, before, after_policy, 110)
    assert row["status"] == "ok" and row["choice"] == "defer_candidate"
    assert row["input_sha256"] == p.recipe["input_sha256"]
    assert is_nil(row["cost_nanos"]) and is_nil(row["elapsed_ms"])
    assert row["response_sha256"] == JSON.digest([result["value"]])

    assert_raise ExUnit.AssertionError, fn ->
      S.result_row(p, events, after_policy, after_policy, 110)
    end

    changed =
      put_in(
        action,
        ["request", "input"],
        Jason.encode!(%{
          "candidates" => [
            %{"id" => "candidate", "input" => Jason.encode!(%{"different" => true})}
          ]
        })
      )

    assert_raise ExUnit.AssertionError, fn ->
      S.result_row(p, replace(events, action, changed), before, after_policy, 110)
    end
  end

  test "missing unknown foreign and forged cleanup cannot become known advice" do
    f = fixture()
    {:ok, p} = S.prepare(f.declaration, f.sha, f.id, f.load, f.options)
    {events, action, _} = delivery(p, :inline)
    {before, after_policy} = policies(action)
    cleanup = Enum.find(events, &(&1["type"] == "managed_output_release_cleanup"))

    for changed <- [
          nil,
          Map.put(cleanup, "status", "unknown"),
          Map.put(cleanup, "release_id", Ipse.Usage.id()),
          Map.put(cleanup, "result_sha256", JSON.sha256("foreign"))
        ] do
      assert_unknown(p, replace(events, cleanup, changed), before, after_policy)
    end
  end

  test "an observed decision must use the frozen profile and its effective execution" do
    f = fixture()
    {:ok, p} = S.prepare(f.declaration, f.sha, f.id, f.load, f.options)

    configs = [
      put_in(f.options.config, [:decision_profiles, "advice", "base_url"], "http://127.0.0.1:3"),
      put_in(f.options.config, [:decision_profiles, "advice", "service_id"], "other_service"),
      put_in(f.options.config, [:decision_profiles, "advice", "timeout_ms"], 1000)
    ]

    for config <- configs do
      {events, action, _} = delivery(p, :inline, config)
      {before, after_policy} = policies(action)
      assert_unknown(p, events, before, after_policy)
    end

    other =
      put_in(
        f.options.config,
        [:decision_profiles, "other"],
        f.options.config.decision_profiles["advice"]
      )

    {events, action, _} = delivery(p, :inline, other, %{"profile" => "other"})
    {before, after_policy} = policies(action)
    assert_unknown(p, events, before, after_policy)

    {events, action, _} = delivery(p, :inline, f.options.config, %{"timeout_ms" => 1000})
    {before, after_policy} = policies(action)
    assert S.result_row(p, events, before, after_policy, 10)["status"] === "ok"
  end

  test "assessment projection refuses changed and duplicated choice alternatives" do
    f = fixture()
    {:ok, p} = S.prepare(f.declaration, f.sha, f.id, f.load, f.options)
    {events, action, _} = delivery(p, :inline)
    {before, after_policy} = policies(action)

    for choices <- [
          ~w(keep_baseline defer_candidate),
          ~w(keep_baseline),
          ~w(defer_candidate defer_candidate),
          ~w(defer_candidate keep_baseline publish)
        ] do
      changed = put_in(action, ["request", "questions", Access.at(0), "choices"], choices)
      changed_events = replace(events, action, changed)

      if choices in [~w(keep_baseline defer_candidate), ~w(defer_candidate keep_baseline publish)] do
        assert_raise ExUnit.AssertionError, fn ->
          S.result_row(p, changed_events, before, after_policy, 110)
        end
      else
        assert_unknown(p, changed_events, before, after_policy)
      end
    end
  end

  test "cross invocation changed result and withdrawn admission remain unverified" do
    f = fixture()
    {:ok, p} = S.prepare(f.declaration, f.sha, f.id, f.load, f.options)
    {events, action, result} = delivery(p, :inline)
    {before, after_policy} = policies(action)
    admission = Enum.find(events, &(&1["type"] == "managed_output_release_result"))

    for {old, changed} <- [
          {action, Map.put(action, "parent_invocation_id", Ipse.Usage.id())},
          {result, put_in(result, ["value", "advice", "choice"], "keep_baseline")},
          {result, Map.put(result, "actions_sha256", JSON.sha256("foreign"))},
          {admission, Map.put(admission, "decision", "withdrawn")},
          {admission, Map.put(admission, "intent_sha256", JSON.sha256("foreign"))}
        ] do
      assert_unknown(p, replace(events, old, changed), before, after_policy)
    end

    unknown = put_in(action, ["outcome", "status"], "unknown")
    policy = put_in(after_policy, ["operations", action["operation_id"], "status"], "unknown")
    assert_unknown(p, [unknown], before, policy)
  end

  test "paged delivery materializes exact complete hash bound advice" do
    f = fixture()
    {:ok, p} = S.prepare(f.declaration, f.sha, f.id, f.load, f.options)
    {events, action, result} = delivery(p, :paged)
    {before, after_policy} = policies(action)
    row = S.result_row(p, events, before, after_policy, 500)
    assert row["status"] == "ok" and row["choice"] == "defer_candidate"
    assert is_nil(row["elapsed_ms"]) and is_nil(row["cost_nanos"])
    chunks = Enum.filter(events, &(&1["type"] == "extension_output_chunk"))
    assert length(chunks) >= 3
    chunk = Enum.at(chunks, 1)
    assert is_map(chunk)
    assert_unknown(p, replace(events, chunk, nil), before, after_policy)

    assert_unknown(
      p,
      replace(events, chunk, Map.put(chunk, "sha256", JSON.sha256("changed"))),
      before,
      after_policy
    )

    assert_unknown(
      p,
      replace(events, result, put_in(result, ["delivery", "byte_count"], 1)),
      before,
      after_policy
    )
  end

  test "qualified frozen info retries without resetting the absolute coordination budget" do
    assert S.phase_observed?(%{phase: :idle}, :idle, 109, 110)
    refute S.phase_observed?(%{phase: :managed_approval}, :idle, 109, 110)
    refute S.phase_observed?({:error, :session_share_frozen}, :idle, 109, 110)

    for response <- [%{phase: :idle}, {:error, :session_share_frozen}] do
      for now <- [110, 111],
          do:
            assert_raise(ExUnit.AssertionError, fn ->
              S.phase_observed?(response, :idle, now, 110)
            end)
    end

    assert_raise ExUnit.AssertionError, fn ->
      S.phase_observed?({:error, :not_owner}, :idle, 109, 110)
    end

    assert_raise ExUnit.AssertionError, fn -> S.phase_observed?(:unknown, :idle, 109, 110) end
  end

  test "authenticated native denial and pre-admission limit remain distinct without advice or refunds" do
    f = fixture()
    {:ok, p} = S.prepare(f.declaration, f.sha, f.id, f.load, f.options)

    for {kind, status} <- [{:denied, "denied"}, {:limit, "refused"}] do
      {events, _action} = causal_delivery(p, kind)
      policy = %{"operations" => %{}}
      row = S.result_row(p, events, policy, policy, 10)
      assert row["status"] === status and row["choice"] === nil
      assert is_nil(row["elapsed_ms"]) and is_nil(row["cost_nanos"])
    end
  end

  test "actual cancelled completion is distinct while partial response failure remains unknown" do
    f = fixture()
    {:ok, p} = S.prepare(f.declaration, f.sha, f.id, f.load, f.options)
    {events, action} = causal_delivery(p, :cancelled)
    before = %{"operations" => %{}}
    after_policy = %{"operations" => %{action["operation_id"] => %{"status" => "unknown"}}}
    row = S.result_row(p, events, before, after_policy, 10)
    assert row["status"] === "cancelled" and is_nil(row["choice"])
    assert after_policy["operations"][action["operation_id"]]["status"] === "unknown"
    assert is_nil(row["cost_nanos"]) and is_nil(row["elapsed_ms"])
    completion = Enum.find(events, &(&1["type"] === "request_finished"))

    for changed <- [
          nil,
          Map.put(completion, "attempt_id", Ipse.Usage.id()),
          Map.put(completion, "outcome", "failed")
        ] do
      assert_unknown(p, replace(events, completion, changed), before, after_policy)
    end

    for kind <- [:partial, :partial_response] do
      {partial, action} = causal_delivery(p, kind)
      after_policy = %{"operations" => %{action["operation_id"] => %{"status" => "unknown"}}}
      assert_unknown(p, partial, before, after_policy)
    end
  end

  test "denial still needs the exact current confirmed output closure" do
    f = fixture()
    {:ok, p} = S.prepare(f.declaration, f.sha, f.id, f.load, f.options)
    {events, _action} = causal_delivery(p, :denied)
    policy = %{"operations" => %{}}
    cleanup = Enum.find(events, &(&1["type"] === "managed_output_release_cleanup"))
    admission = Enum.find(events, &(&1["type"] === "managed_output_release_result"))

    for changed <- [
          nil,
          Map.put(cleanup, "status", "unknown"),
          Map.put(cleanup, "release_id", Ipse.Usage.id())
        ] do
      assert_unknown(p, replace(events, cleanup, changed), policy, policy)
    end

    assert_unknown(
      p,
      replace(events, admission, Map.put(admission, "decision", "withdrawn")),
      policy,
      policy
    )

    intent = Enum.find(events, &(&1["type"] === "extension_action_intent"))

    assert_unknown(
      p,
      replace(events, intent, Map.put(intent, "operation_id", Ipse.Usage.id())),
      policy,
      policy
    )
  end

  test "complete matched artifact refusal is observed but untyped outer error is unknown" do
    f = fixture()
    {:ok, p} = S.prepare(f.declaration, f.sha, f.id, f.load, f.options)
    parent = parent(p)
    value = %{"status" => "refused", "code" => "assessment_unavailable"}

    {:ok, result} =
      Invocation.build_result(parent, %{"api_version" => 1, "kind" => "result", "value" => value})

    events = [parent] ++ release(parent, result)
    policy = %{"operations" => %{}}
    assert S.result_row(p, events, policy, policy, 10)["status"] === "refused"

    assert_unknown(p, events, policy, %{
      "operations" => %{Ipse.Usage.id() => %{"status" => "unknown"}}
    })

    assert_unknown(p, [%{"type" => "turn_finished", "outcome" => "error"}], policy, policy)
  end

  defp causal_delivery(p, kind) do
    parent = parent(p)

    request = %{
      "op" => "decision.create",
      "version" => 1,
      "profile" => "advice",
      "timeout_ms" => 2000,
      "input" =>
        Jason.encode!(%{
          "candidates" => [%{"id" => "candidate", "input" => Jason.encode!(p.input)}]
        }),
      "questions" => [
        %{
          "id" => "candidate",
          "type" => "choice",
          "choices" => ~w(defer_candidate keep_baseline),
          "instructions" => "rubric"
        }
      ]
    }

    {:ok, binding} = DecisionCall.binding(p.options.config, request)
    approval = if kind === :denied, do: "denied", else: "approved"
    {:ok, intent} = Actions.intent(parent, request, 1, approval, p.options.cwd, nil, nil, binding)

    {outcome, inference} =
      case kind do
        :denied ->
          {%{"status" => "denied", "value" => %{}}, []}

        :limit ->
          {%{"status" => "failed", "value" => %{"code" => "decision_limit"}}, []}

        kind when kind in [:cancelled, :partial, :partial_response] ->
          {:ok, runtime, execution} = Decisions.prepare(p.options.config, request)

          admission =
            Ipse.Usage.admission(
              parent["payload"]["session_id"],
              runtime,
              "extension",
              parent["payload"]["turn_id"]
            )
            |> Map.put("request_id", intent["operation_id"])

          source = DecisionCall.source(intent, admission, execution)

          completion =
            Ipse.Usage.completion(
              admission,
              if(kind === :cancelled, do: :cancelled, else: :failed),
              5,
              nil
            )

          code =
            case kind do
              :cancelled -> "decision_cancelled"
              :partial -> "decision_request_failed"
              :partial_response -> "decision_response"
            end

          {%{"status" => "failed", "value" => %{"code" => code}}, [source, admission, completion]}
      end

    {:ok, action} = Actions.result(intent, outcome)

    value = %{
      "status" => "interrupted",
      "outcome" => outcome,
      "retry" => "inspect; never replay unknown work"
    }

    {:ok, result} =
      Invocation.build_result(
        parent,
        %{"api_version" => 1, "kind" => "result", "value" => value},
        [action]
      )

    metadata = %{
      "type" => "session",
      "metadata" => %{
        "usage_version" => 3,
        "decision_profiles" => Decisions.snapshot(p.options.config)
      }
    }

    events = [metadata, parent, intent] ++ inference ++ [action] ++ release(parent, result)
    assert {:ok, _} = Ipse.Usage.restore(events, parent["payload"]["session_id"])
    {events, action}
  end

  defp release(parent, result) do
    intent = ManagedOutput.intent(parent["payload"]["session_id"], parent, result, [], 100, 110)
    admission = ManagedOutput.admission(intent, result, "current", [], 101, 110)
    [intent, result, admission, ManagedOutput.cleanup(intent, admission, "confirmed")]
  end

  defp assert_unknown(p, events, before, after_policy) do
    row = S.result_row(p, events, before, after_policy, 110)
    assert row["status"] == "unknown"
    for key <- ~w(choice response_sha256 elapsed_ms cost_nanos), do: assert(is_nil(row[key]))
  end

  defp replace(events, old, nil), do: Enum.reject(events, &(&1 === old))

  defp replace(events, old, changed),
    do: Enum.map(events, fn event -> if event === old, do: changed, else: event end)

  defp policies(action),
    do:
      {%{"operations" => %{}},
       %{"operations" => %{action["operation_id"] => %{"status" => "settled"}}}}

  # Constructed public protocol rows test extraction only. They are not Saved
  # histories or native authority; execute/3 requires strict Saved first.
  defp delivery(p, kind, config \\ nil, overrides \\ %{}) do
    parent = parent(p)

    request =
      %{
        "op" => "decision.create",
        "version" => 1,
        "profile" => "advice",
        "timeout_ms" => 2000,
        "input" =>
          Jason.encode!(%{
            "candidates" => [%{"id" => "candidate", "input" => Jason.encode!(p.input)}]
          }),
        "questions" => [
          %{
            "id" => "candidate",
            "type" => "choice",
            "choices" => ~w(defer_candidate keep_baseline),
            "instructions" => "rubric"
          }
        ]
      }
      |> Map.merge(overrides)

    {:ok, binding} = DecisionCall.binding(config || p.options.config, request)

    action = %{
      "type" => "extension_action_result",
      "operation_id" => Ipse.Usage.id(),
      "parent_invocation_id" => parent["invocation_id"],
      "request" => request,
      "effect_binding" => binding,
      "outcome" => %{"status" => "ok"}
    }

    value = %{
      "status" => "assessed",
      "key" => p.recipe["arguments"]["key"],
      "advice" => %{"choice" => "defer_candidate", "reason" => "selected"}
    }

    {prefix, raw} = raw_result(parent, value, kind)
    result = Map.merge(raw, %{"action_count" => 1, "actions_sha256" => JSON.digest([action])})
    intent = ManagedOutput.intent(parent["payload"]["session_id"], parent, result, [], 100, 110)
    admission = ManagedOutput.admission(intent, result, "current", [], 101, 110)
    cleanup = ManagedOutput.cleanup(intent, admission, "confirmed")
    [^parent | producer_events] = prefix
    {[parent, action] ++ producer_events ++ [intent, result, admission, cleanup], action, result}
  end

  defp parent(p) do
    hash = p.recipe["artifact_sha256"]

    identity = %{
      "instance" => "knowledge",
      "artifact" => hash,
      "artifact_sha256" => hash,
      "options_sha256" => hash,
      "exports_sha256" => hash,
      "requires_sha256" => hash,
      "subscriptions_sha256" => hash,
      "services" => [],
      "scope" => "operator",
      "source_sha256" => hash,
      "sdk" => 2,
      "protocol" => 1,
      "capabilities" => ~w(invoke.command invoke.result.pages host.actions host.decision),
      "order" => 1,
      "lifetime" => "session",
      "expires_at" => nil,
      "runtime" => %{
        "architecture" => "fixture",
        "elixir" => "1.18.5",
        "erts" => "15",
        "otp" => "27"
      },
      "host_sha256" => hash,
      "generation" => 1,
      "allow_children" => false
    }

    descriptor = %{
      "id" => "assess",
      "description" => "Constructed assessment",
      "arguments_schema" => %{
        "type" => "object",
        "properties" => %{"key" => %{"type" => "string"}},
        "required" => ["key"],
        "additionalProperties" => false
      },
      "result_schema" => %{"type" => "object", "additionalProperties" => true},
      "instance" => "knowledge",
      "stage" => "invoke.command",
      "name" => "ext__knowledge__assess"
    }

    parent =
      Invocation.intent(
        identity,
        descriptor,
        p.recipe["arguments"],
        Ipse.Usage.id(),
        Ipse.Usage.id(),
        nil,
        nil,
        "operator_request"
      )

    assert :ok = Invocation.validate_intent(parent)
    parent
  end

  defp raw_result(parent, value, :inline) do
    {:ok, result} =
      Invocation.build_result(parent, %{"api_version" => 1, "kind" => "result", "value" => value})

    {[parent], result}
  end

  defp raw_result(parent, value, :paged) do
    value =
      Map.merge(value, %{
        "detail" => String.duplicate("é", 3000),
        "detail_tail" => String.duplicate("é", 3000)
      })

    {:ok, bytes} = ResultDocument.encode(value, parent["descriptor"]["result_schema"])

    offer = %{
      "api_version" => 1,
      "kind" => "result_producer",
      "output" => %{
        "version" => 1,
        "byte_count" => byte_size(bytes),
        "sha256" => JSON.sha256(bytes)
      }
    }

    {:ok, begin, source} = ResultSource.open(parent, offer, 10)
    {chunks, source} = chunks(source, bytes, [])
    {:ok, proof, source} = ResultSource.seal(source, 20)
    {:ok, result} = Invocation.build_saved_result(parent, ResultSource.descriptor(source), [], 21)
    {[parent, begin] ++ chunks ++ [proof.event], result}
  end

  defp chunks(%{offset: offset} = source, bytes, acc) when offset == byte_size(bytes),
    do: {Enum.reverse(acc), source}

  defp chunks(source, bytes, acc) do
    size = min(4096, byte_size(bytes) - source.offset)
    fragment = binary_part(bytes, source.offset, size)

    reply = %{
      "api_version" => 1,
      "kind" => "result_chunk",
      "output" => %{
        "version" => 1,
        "output_id" => source.begin["output_id"],
        "offset" => source.offset,
        "next" => source.offset + size,
        "complete" => source.offset + size == byte_size(bytes),
        "data_base64" => Base.encode64(fragment),
        "sha256" => JSON.sha256(fragment)
      }
    }

    {:ok, chunk, source} = ResultSource.push(source, reply)
    chunks(source, bytes, [chunk | acc])
  end
end
