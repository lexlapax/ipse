Code.require_file("../../../extensions/knowledge/src/knowledge/decision_policy.ex", __DIR__)

defmodule IpseKnowledge.Knowledge.DecisionPolicyTest do
  use ExUnit.Case, async: false
  alias IpseKnowledge.Knowledge.DecisionPolicy, as: P

  defp policy(consumer \\ "notes.select"),
    do: P.default(consumer) |> Map.merge(%{"strategy" => "decision", "profile" => "advice"})

  defp selection do
    %{
      "version" => 1,
      "availability" => "available",
      "coverage" => "complete",
      "allocation_bytes" => 100,
      "eligible_count" => 2000,
      "eligible_rendered_bytes" => 100_000,
      "budget_available" => true,
      "query" => "Who owns Acme?",
      "candidates" => Enum.map(~w(a b c), &%{"id" => &1, "rendered" => String.duplicate(&1, 70)}),
      "alternatives" => [
        %{"id" => "first", "members" => ["a"]},
        %{"id" => "second", "members" => ["b"]}
      ],
      "baseline_id" => "first"
    }
  end

  defp assessment do
    %{
      "version" => 1,
      "availability" => "available",
      "budget_available" => true,
      "candidates" => [
        %{"id" => "a", "input" => "Exact original candidate, café."},
        %{"id" => "b", "input" => "Second exact original candidate."}
      ],
      "alternatives" => ~w(keep_baseline defer_candidate)
    }
  end

  defp plan(facts \\ selection(), consumer \\ "notes.select") do
    assert {:ok, p} = P.plan(policy(consumer), facts, :development_experiment)
    p
  end

  defp result(p, choice \\ nil, probability \\ 0.9) do
    %{
      "version" => 1,
      "answers" =>
        Enum.map(p.request["questions"], fn q ->
          choice = choice || hd(q["choices"])

          %{
            "id" => q["id"],
            "type" => "choice",
            "choice" => choice,
            "confidence" => 0.01,
            "probabilities" =>
              Enum.map(q["choices"], fn id ->
                %{
                  "id" => id,
                  "probability" =>
                    if(id == choice,
                      do: probability,
                      else: (1 - probability) / (length(q["choices"]) - 1)
                    )
                }
              end)
          }
        end)
    }
  end

  test "production remains zero-call even with a worker's qualification digest" do
    assert P.limits()["minimum_probability"] == 0.8
    assert P.limits()["minimum_margin"] == 0.2
    assert P.limits()["selection_candidates"] == 16
    assert P.limits()["assessment_candidates"] == 8

    for p <- [
          P.default("notes.select"),
          policy(),
          Map.put(policy(), "qualification_sha256", String.duplicate("a", 64))
        ] do
      assert {:ok, planned} = P.plan(p, selection())
      assert is_nil(planned.request)
      assert planned.reason in ~w(strategy_none no_qualified_strategy)
      assert {:ok, %{"receipt" => %{"source_facts" => "untrusted"}}} = P.apply(planned, nil)
    end
  end

  test "encoded source facts respect the published size bound in both modes" do
    for {consumer, base, field} <- [
          {"notes.select", selection(), "rendered"},
          {"notes.assess", assessment(), "input"}
        ] do
      rows = Enum.map(~w(a b c), &%{"id" => &1, field => String.duplicate("x", 5300)})
      facts = Map.put(base, "candidates", rows)

      facts =
        if consumer == "notes.select",
          do: Map.merge(facts, %{"eligible_count" => 3, "eligible_rendered_bytes" => 15_900}),
          else: facts

      extra = P.limits()["facts_bytes"] - byte_size(JSON.encode!(facts))
      assert extra > 0 and extra < 844

      facts =
        update_in(
          facts,
          ["candidates", Access.at(0), field],
          &(&1 <> String.duplicate("x", extra))
        )

      facts =
        if consumer == "notes.select",
          do: Map.put(facts, "eligible_rendered_bytes", 15_900 + extra),
          else: facts

      assert byte_size(JSON.encode!(facts)) == P.limits()["facts_bytes"]
      oversized = update_in(facts, ["candidates", Access.at(0), field], &(&1 <> "x"))

      oversized =
        if consumer == "notes.select",
          do: Map.update!(oversized, "eligible_rendered_bytes", &(&1 + 1)),
          else: oversized

      assert byte_size(JSON.encode!(oversized)) == P.limits()["facts_bytes"] + 1

      for mode <- [:production, :development_experiment] do
        assert {:ok, _} = P.plan(policy(consumer), facts, mode)
        assert {:error, :invalid_decision_policy} = P.plan(policy(consumer), oversized, mode)
      end
    end
  end

  test "each applicability bypass has no request or usable unsolicited advice" do
    unknown =
      selection()
      |> Map.merge(%{
        "availability" => "unknown",
        "coverage" => "unknown",
        "eligible_count" => nil,
        "eligible_rendered_bytes" => nil
      })

    empty =
      selection()
      |> Map.merge(%{
        "candidates" => [],
        "alternatives" => [],
        "baseline_id" => nil,
        "eligible_count" => 0,
        "eligible_rendered_bytes" => 0
      })

    one = put_in(selection(), ["alternatives", Access.at(1), "members"], ["a"])

    for {f, reason} <- [
          {unknown, "eligibility_unknown"},
          {Map.put(selection(), "availability", "unavailable"), "eligibility_unavailable"},
          {Map.put(selection(), "coverage", "partial"), "coverage_incomplete"},
          {empty, "empty_eligible_set"},
          {Map.put(selection(), "allocation_bytes", 0), "zero_allocation"},
          {Map.merge(empty, %{"eligible_count" => 4, "eligible_rendered_bytes" => 400}),
           "no_candidates"},
          {Map.put(selection(), "allocation_bytes", 1), "no_alternatives"},
          {one, "one_alternative"},
          {Map.put(selection(), "budget_available", false), "budget_unavailable"}
        ] do
      p = plan(f)
      assert p.reason == reason
      assert p.request == nil
      assert {:error, :unsolicited_decision_advice} = P.apply(p, %{"version" => 1})
    end
  end

  test "only the complete set fits bypass includes every rendered record, beyond pack limits" do
    f =
      selection()
      |> Map.merge(%{
        "candidates" =>
          Enum.map(~w(a b c d e), &%{"id" => &1, "rendered" => String.duplicate(&1, 70)}),
        "eligible_count" => 5,
        "eligible_rendered_bytes" => 350,
        "allocation_bytes" => 350
      })

    p = plan(f)
    assert p.reason == "complete_set_fits"
    assert p.baseline == %{"pack" => nil, "members" => ~w(a b c d e)}
    assert {:ok, %{"action" => %{"members" => ~w(a b c d e)}}} = P.apply(p, nil)
    assert {:ok, none} = P.plan(P.default("notes.select"), f)
    assert none.reason == "strategy_none" and none.baseline == p.baseline

    partial_pool =
      Map.merge(f, %{
        "eligible_count" => 2000,
        "eligible_rendered_bytes" => 3000,
        "allocation_bytes" => 6144
      })

    assert plan(partial_pool).request == nil
    assert plan(partial_pool).reason == "fit_coverage_unavailable"

    assert {:ok, %{"action" => nil, "receipt" => %{"reason" => "fit_coverage_unavailable"}}} =
             partial_pool |> plan() |> P.apply(nil)

    for {facts, reason} <- [
          {Map.put(f, "availability", "unknown"), "eligibility_unknown"},
          {Map.put(f, "availability", "unavailable"), "eligibility_unavailable"},
          {Map.put(f, "coverage", "partial"), "coverage_incomplete"},
          {partial_pool, "fit_coverage_unavailable"}
        ],
        {selected_policy, mode} <- [
          {policy(), :development_experiment},
          {policy(), :production},
          {P.default("notes.select"), :production}
        ] do
      assert {:ok, unavailable} = P.plan(selected_policy, facts, mode)
      assert unavailable.request == nil and unavailable.baseline == nil
      assert unavailable.reason == reason

      assert {:ok, %{"action" => nil, "receipt" => %{"reason" => ^reason}}} =
               P.apply(unavailable, nil)

      forged = %{unavailable | baseline: %{"pack" => "first", "members" => ["a"]}}
      assert {:error, :invalid_decision_policy} = P.apply(forged, nil)
    end

    assert plan(Map.put(f, "coverage", "partial")).reason == "coverage_incomplete"

    assert {:error, _} =
             P.plan(policy(), Map.put(f, "eligible_rendered_bytes", 349), :development_experiment)
  end

  test "unavailable candidate assessment yields no action in either mode" do
    for availability <- ~w(unknown unavailable),
        mode <- [:production, :development_experiment] do
      facts = Map.put(assessment(), "availability", availability)
      assert {:ok, planned} = P.plan(policy("notes.assess"), facts, mode)
      assert planned.baseline == nil and planned.request == nil
      assert planned.reason == "eligibility_" <> availability
      assert {:ok, %{"action" => nil}} = P.apply(planned, nil)
    end
  end

  test "missing candidates or packs do not assert that a nonempty eligible set is empty" do
    no_candidates =
      Map.merge(selection(), %{"candidates" => [], "alternatives" => [], "baseline_id" => nil})

    no_packs = Map.merge(selection(), %{"alternatives" => [], "baseline_id" => nil})

    for facts <- [no_candidates, no_packs],
        mode <- [:production, :development_experiment] do
      assert {:ok, planned} = P.plan(policy(), facts, mode)
      assert planned.request == nil
      assert {:ok, %{"action" => nil}} = P.apply(planned, nil)
    end

    zero = Map.put(no_packs, "allocation_bytes", 0)
    assert {:ok, planned} = P.plan(policy(), zero, :development_experiment)
    assert {:ok, %{"action" => %{"pack" => nil, "members" => []}}} = P.apply(planned, nil)

    fitting =
      Map.merge(no_packs, %{
        "allocation_bytes" => 210,
        "eligible_count" => 3,
        "eligible_rendered_bytes" => 210
      })

    assert {:ok, planned} = P.plan(policy(), fitting, :development_experiment)
    assert {:ok, %{"action" => %{"members" => ~w(a b c)}}} = P.apply(planned, nil)
  end

  test "complete aggregate metadata accounts for the minimum bytes of omitted records" do
    facts = Map.merge(selection(), %{"eligible_count" => 4, "eligible_rendered_bytes" => 210})

    assert {:error, :invalid_decision_policy} =
             P.plan(policy(), facts, :development_experiment)

    assert {:ok, planned} =
             P.plan(
               policy(),
               Map.put(facts, "eligible_rendered_bytes", 211),
               :development_experiment
             )

    assert planned.request != nil
  end

  test "pack filtering uses actual UTF8 rendered bytes and deterministic duplicate identity" do
    f = selection() |> put_in(["candidates", Access.at(0), "rendered"], String.duplicate("雪", 34))
    p = plan(f)
    assert p.reason == "one_alternative"
    assert p.baseline["pack"] == "second"
    duplicate = put_in(selection(), ["alternatives", Access.at(1), "members"], ["a"])
    assert plan(duplicate).baseline["pack"] == "first"

    permuted =
      selection()
      |> Map.put("allocation_bytes", 140)
      |> put_in(["alternatives", Access.at(0), "members"], ~w(a b))
      |> put_in(["alternatives", Access.at(1), "members"], ~w(b a))

    assert plan(permuted).reason == "one_alternative"
    assert plan(permuted).baseline == %{"pack" => "first", "members" => ~w(a b)}

    framed =
      selection()
      |> Map.put("candidates", [
        %{"id" => "a", "rendered" => "A\n"},
        %{"id" => "b", "rendered" => "B\n"}
      ])
      |> Map.put("allocation_bytes", 3)
      |> put_in(["alternatives", Access.at(0), "members"], ~w(a b))

    assert plan(framed).reason == "one_alternative"
    assert plan(framed).baseline["members"] == ["b"]
    assert plan(Map.put(framed, "allocation_bytes", 4)).request != nil

    assert {:error, _} =
             P.plan(
               policy(),
               Map.put(selection(), "baseline_id", "absent"),
               :development_experiment
             )

    assert {:error, _} =
             P.plan(Map.put(policy(), "profile", "1bad"), selection(), :development_experiment)

    assert plan().request["profile"] == "advice"
  end

  test "version 2 selection filters complete measured projections rather than raw text sums" do
    facts =
      selection()
      |> Map.merge(%{
        "version" => 2,
        "source_binding_sha256" => String.duplicate("a", 64),
        "eligible_count" => 3,
        "eligible_rendered_bytes" => nil,
        "alternatives" => [
          %{"id" => "first", "members" => ["a"], "rendered_bytes" => 99},
          %{"id" => "second", "members" => ["a", "b"], "rendered_bytes" => 100},
          %{"id" => "large", "members" => ["c"], "rendered_bytes" => 101}
        ]
      })

    assert {:ok, p} = P.plan(policy(), facts, :development_experiment)
    assert p.request != nil
    assert Enum.map(p.mapping, & &1["id"]) == ~w(first second)

    assert {:ok, %{"action" => %{"pack" => "second", "members" => ~w(a b)}}} =
             P.apply(p, result(p, "second"))

    assert {:ok, fits} =
             P.plan(
               policy(),
               Map.put(facts, "eligible_rendered_bytes", 100),
               :development_experiment
             )

    assert fits.reason == "complete_set_fits" and is_nil(fits.request)
    assert {:ok, %{"action" => %{"members" => ~w(a b c)}}} = P.apply(fits, nil)

    assert {:ok, incomplete} =
             P.plan(policy(), Map.put(facts, "coverage", "partial"), :development_experiment)

    assert incomplete.reason == "coverage_incomplete" and incomplete.baseline == nil

    duplicates = put_in(facts, ["alternatives", Access.at(2), "members"], ["a"])

    assert {:error, :invalid_decision_policy} =
             P.plan(policy(), duplicates, :development_experiment)

    assert {:error, :invalid_decision_policy} =
             P.apply(%{p | facts: duplicates}, result(p, "second"))

    assert {:ok, production} = P.plan(policy(), facts, :production)
    assert production.reason == "no_qualified_strategy" and is_nil(production.request)

    assert {:ok, _} =
             P.plan(policy(), Map.put(facts, "allocation_bytes", 8192), :development_experiment)

    assert {:error, :invalid_decision_policy} =
             P.plan(policy(), Map.put(facts, "allocation_bytes", 8193), :development_experiment)

    assert {:error, :invalid_decision_policy} =
             P.plan(
               policy(),
               Map.put(selection(), "allocation_bytes", 8192),
               :development_experiment
             )
  end

  test "a fitting complete set bypasses decisions even without a baseline pack" do
    version1 =
      selection()
      |> Map.merge(%{
        "allocation_bytes" => 210,
        "eligible_count" => 3,
        "eligible_rendered_bytes" => 210,
        "baseline_id" => nil
      })

    version2 =
      version1
      |> Map.put("version", 2)
      |> Map.put("source_binding_sha256", String.duplicate("a", 64))
      |> Map.update!("alternatives", fn alternatives ->
        Enum.map(alternatives, &Map.put(&1, "rendered_bytes", 150))
      end)

    for facts <- [version1, version2] do
      assert {:ok, plan} = P.plan(policy(), facts, :development_experiment)
      assert plan.reason == "complete_set_fits" and is_nil(plan.request)
      assert {:ok, %{"action" => %{"members" => ~w(a b c)}}} = P.apply(plan, nil)

      for {field, value, reason} <- [
            {"availability", "unavailable", "eligibility_unavailable"},
            {"coverage", "partial", "coverage_incomplete"}
          ] do
        assert {:ok, withheld} =
                 P.plan(policy(), Map.put(facts, field, value), :development_experiment)

        assert withheld.reason == reason and withheld.baseline == nil and withheld.request == nil
        assert {:ok, %{"action" => nil}} = P.apply(withheld, nil)
      end
    end
  end

  test "selection request marks bounded UTF8 excerpts, and mapping returns only permitted IDs" do
    f =
      put_in(selection(), ["candidates", Access.at(0), "rendered"], String.duplicate("雪", 100))
      |> Map.put("allocation_bytes", 400)

    p = plan(f)
    rows = JSON.decode!(p.request["input"])["candidates"]
    [a | _] = rows
    assert String.valid?(a["text"]) and a["shown_bytes"] == 255
    assert a["original_bytes"] == 300 and a["coverage"] == "partial"
    assert byte_size(p.request["input"]) <= 8192

    assert Ipse.Extension.validate_decision_request(
             Map.take(p.request, ~w(version profile input questions))
           ) == :ok

    assert {:ok, %{"action" => %{"pack" => "second", "members" => ["b"]}}} =
             P.apply(p, result(p, "second"))
  end

  test "probability threshold is inclusive; raw confidence never supplies the threshold" do
    p = plan()
    assert {:ok, %{"receipt" => %{"reason" => "selected"}}} = P.apply(p, result(p, "second", 0.8))

    assert {:ok, %{"receipt" => %{"reason" => "low_probability"}}} =
             P.apply(p, result(p, "second", 0.799999))

    assert {:ok, %{"receipt" => %{"reason" => "low_probability"}}} =
             P.apply(p, result(p, "second", 0.5))

    # At p>=0.8 a normalized distribution already has margin>=0.6, so the
    # separately frozen0.2 margin is redundant but still checked by the mapper.
  end

  test "refusal and structural corruption fall back without negative semantic claims" do
    p = plan()
    refusal = %{"version" => 1, "answers" => [%{"id" => "pack", "type" => "refusal"}]}

    assert {:ok, %{"receipt" => %{"reason" => "refusal"}, "action" => action}} =
             P.apply(p, refusal)

    assert action == p.baseline
    valid = result(p)

    for bad <- [
          Map.put(valid, "authority", true),
          Map.put(valid, "answers", []),
          put_in(valid, ["answers", Access.at(0), "choice"], "unpermitted"),
          put_in(valid, ["answers", Access.at(0), "type"], "predicate"),
          put_in(
            valid,
            ["answers", Access.at(0), "probabilities", Access.at(0), "probability"],
            1.1
          )
        ] do
      assert {:ok, %{"receipt" => %{"reason" => "malformed_advice"}, "action" => ^action}} =
               P.apply(p, bad)
    end

    assert {:error, _} = P.apply(%{p | mapping: []}, valid)
  end

  test "assessment preserves original input and can only keep or defer each candidate" do
    p = plan(assessment(), "notes.assess")
    assert JSON.decode!(p.request["input"])["candidates"] == assessment()["candidates"]
    r = result(p, "defer_candidate")
    r = put_in(r, ["answers", Access.at(1)], %{"id" => "b", "type" => "refusal"})
    assert {:ok, %{"action" => %{"candidates" => [a, b]}}} = P.apply(p, r)
    assert a == %{"id" => "a", "choice" => "defer_candidate", "reason" => "selected"}
    assert b == %{"id" => "b", "choice" => "keep_baseline", "reason" => "refusal"}
    malformed = put_in(r, ["answers", Access.at(0), "choice"], "publish_literal")

    assert {:ok, %{"receipt" => %{"reason" => "malformed_advice"}, "action" => action}} =
             P.apply(p, malformed)

    assert action == p.baseline

    assert {:error, _} =
             P.plan(
               policy("notes.assess"),
               Map.put(assessment(), "alternatives", ["publish_literal"]),
               :development_experiment
             )
  end

  test "absent assessment candidates and unavailable budgets require no extra call" do
    for {f, reason} <- [
          {Map.put(assessment(), "candidates", []), "no_candidates"},
          {Map.put(assessment(), "alternatives", []), "no_alternatives"},
          {Map.put(assessment(), "alternatives", ["keep_baseline"]), "one_alternative"},
          {Map.put(assessment(), "budget_available", false), "budget_unavailable"}
        ] do
      assert %P.Plan{reason: ^reason, request: nil} = plan(f, "notes.assess")
    end
  end

  test "all schemas and aggregate wire bytes refuse instead of truncating assessment" do
    for f <- [
          Map.put(selection(), "origin", "host"),
          Map.put(selection(), "allocation_bytes", 6145),
          put_in(selection(), ["candidates", Access.at(0), "rendered"], <<255>>),
          Map.put(selection(), "query", String.duplicate("q", 1025)),
          Map.put(selection(), "candidates", List.duplicate(hd(selection()["candidates"]), 17)),
          put_in(selection(), ["alternatives", Access.at(0), "members"], ~w(a a))
        ] do
      assert {:error, _} = P.plan(policy(), f, :development_experiment)
    end

    assert {:error, _} =
             P.plan(
               Map.put(policy(), "minimum_probability", 0),
               selection(),
               :development_experiment
             )

    f =
      Map.put(
        assessment(),
        "candidates",
        Enum.map(1..3, &%{"id" => "c#{&1}", "input" => String.duplicate("\"", 2048)})
      )

    p = plan(f, "notes.assess")
    assert p.reason == "request_limit" and p.request == nil
    assert p.facts["candidates"] == f["candidates"]

    assert {:error, _} =
             P.plan(
               policy("notes.assess"),
               Map.put(
                 f,
                 "candidates",
                 Enum.map(1..8, &%{"id" => "c#{&1}", "input" => String.duplicate("x", 6144)})
               ),
               :development_experiment
             )
  end

  test "separately built artifact uses only the minimal public SDK closure" do
    root =
      Path.join(
        System.tmp_dir!(),
        "ipse-decision-policy-sdk-#{System.unique_integer([:positive])}"
      )

    sdk = Path.join(root, "lib/ipse/ebin")
    File.mkdir_p!(sdk)
    on_exit(fn -> File.rm_rf!(root) end)

    # The public SDK delegates context sizing to the host framing modules.
    # Include those actual beams in the isolated SDK and exercise the call in
    # the separate VM, so this check catches a missing runtime closure.
    for module <- [
          Ipse.Extension.Context,
          Ipse.Extension.Catalog,
          Ipse.Extension.History,
          Ipse.Session.Reference
        ] do
      beam = module |> :code.which() |> List.to_string()
      File.cp!(beam, Path.join(sdk, Path.basename(beam)))
    end

    dependencies =
      for dep <- ~w(jason jsonschex ex_json_pointer)a do
        target = Path.join([root, "lib", Atom.to_string(dep), "ebin"])
        File.mkdir_p!(Path.dirname(target))
        File.cp_r!(Application.app_dir(dep, "ebin"), target)
        target
      end

    args = Enum.flat_map([sdk | dependencies], &["-pa", &1])

    code =
      "case Kernel.ParallelCompiler.compile_to_path(~w(lib/ipse/json.ex lib/ipse/decision.ex lib/ipse/extension.ex), #{inspect(sdk)}, return_diagnostics: true) do {:ok,_,%{compile_warnings: [], runtime_warnings: []}} -> :ok; {:ok,_,[]} -> :ok; bad -> raise inspect(bad) end"

    assert {_, 0} =
             System.cmd(System.find_executable("elixir"), args ++ ["-e", code],
               stderr_to_stdout: true
             )

    artifact = Path.join(root, "artifact")

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "extensions/knowledge/build.exs",
          "--sdk",
          sdk,
          "--output",
          artifact,
          "--package",
          "knowledge",
          "--preset",
          "native"
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    manifest = JSON.decode!(File.read!(Path.join(artifact, "extension.json")))
    refute "host.decision" in manifest["capabilities"]

    assert Enum.map(manifest["exports"]["tools"], & &1["id"]) ==
             ~w(capture index read search)

    assert File.regular?(
             Path.join(artifact, "ebin/Elixir.IpseKnowledge.Knowledge.DecisionPolicy.beam")
           )

    code =
      "import ExUnit.Assertions\nfalse=Code.ensure_loaded?(Ipse.Session)\nfalse=Code.ensure_loaded?(Ipse.Extension.Artifact)\n" <>
        "assert is_integer(Ipse.Extension.context_rendered_bytes([%{\"id\"=>\"x\",\"text\"=>\"note\",\"priority\"=>0,\"source\"=>%{\"kind\"=>\"assertion\"}}],\"knowledge\"))\n" <>
        "p=#{inspect(policy())}\nf=#{inspect(selection())}\n" <>
        "assert {:ok, plan}=IpseKnowledge.Knowledge.DecisionPolicy.plan(p,f,:development_experiment)\nassert plan.request != nil\nassert Ipse.Extension.validate_decision_request(Map.take(plan.request,~w(version profile input questions)))==:ok\n" <>
        "r=#{inspect(result(plan()))}\nneutral=Map.take(plan.request,~w(version profile input questions))\nassert Ipse.Extension.validate_decision_result(neutral,r)==:ok\nassert {:ok,\"first\"}=Ipse.Extension.select_decision(neutral,r,\"pack\",~w(first second),0.8)\nassert {:ok,%{\"action\"=>%{\"pack\"=>\"first\"}}}=IpseKnowledge.Knowledge.DecisionPolicy.apply(plan,r)\n" <>
        "assert {:ok,none}=IpseKnowledge.Knowledge.DecisionPolicy.plan(p,f)\nassert none.request==nil\n" <>
        "gap=Map.merge(f,%{\"eligible_rendered_bytes\"=>2207,\"allocation_bytes\"=>6144})\n" <>
        "for mode <- [:production,:development_experiment] do\n" <>
        "  assert {:ok,missing}=IpseKnowledge.Knowledge.DecisionPolicy.plan(p,gap,mode)\n" <>
        "  assert missing.reason==\"fit_coverage_unavailable\" and missing.request==nil\n" <>
        "  assert {:ok,%{\"action\"=>nil}}=IpseKnowledge.Knowledge.DecisionPolicy.apply(missing,nil)\n" <>
        "  absent=Map.merge(f,%{\"alternatives\"=>[],\"baseline_id\"=>nil})\n" <>
        "  assert {:ok,no_pack}=IpseKnowledge.Knowledge.DecisionPolicy.plan(p,absent,mode)\n" <>
        "  assert {:ok,%{\"action\"=>nil}}=IpseKnowledge.Knowledge.DecisionPolicy.apply(no_pack,nil)\n" <>
        "  impossible=Map.merge(f,%{\"eligible_count\"=>4,\"eligible_rendered_bytes\"=>210})\n" <>
        "  assert {:error,:invalid_decision_policy}=IpseKnowledge.Knowledge.DecisionPolicy.plan(p,impossible,mode)\n" <>
        "end\nIO.puts(\"minimal-public-sdk-decision-policy-ok\")"

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        args ++ ["-pa", sdk, "-pa", Path.join(artifact, "ebin"), "-e", code],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "minimal-public-sdk-decision-policy-ok"
  end
end
