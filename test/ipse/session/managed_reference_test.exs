defmodule Ipse.Session.ManagedReferenceTest do
  use ExUnit.Case, async: true
  import Kernel, except: [binding: 0, binding: 1]
  alias Ipse.Session.ManagedReference, as: Managed
  alias Ipse.JSON

  @session String.duplicate("a", 32)
  @turn String.duplicate("b", 32)
  @request String.duplicate("c", 32)
  @error {:error, :managed_reference_refused}
  @unsafe {:error, :managed_reference_projection_unsafe}

  defp sha(value), do: JSON.digest([value])
  defp ordered(values), do: Enum.sort_by(values, &sha/1)

  defp dependency(n \\ 0) do
    %{
      "version" => 1,
      "project_id" => sha("actual-project"),
      "namespace" => sha("collection"),
      "pin_sha256" => sha("original-session-pin"),
      "policy_generation" => 4,
      "collection" => %{
        "project" => sha("collection"),
        "generation" => 10,
        "floor" => 0,
        "floor_anchor" => nil,
        "manifest_sha256" => sha("manifest")
      },
      "record" => %{"key" => "record.#{n}", "revision" => 1, "value_sha256" => sha(n)},
      "validity" => %{
        "recipe_sha256" => sha("operator-reviewed-generic-path-recipe"),
        "lineage" => sha(["lineage", n]),
        "source_versions" => [%{"id" => sha("source"), "version" => sha(1)}],
        "valid_until_ms" => 2000,
        "status" => "eligible",
        "dependencies" => []
      }
    }
  end

  defp producer(kind, n \\ 0),
    do: %{"kind" => kind, "id" => "producer.#{n}", "parent_id" => nil}

  defp record_v2 do
    old = dependency()

    old
    |> Map.drop(~w(record validity))
    |> Map.put("version", 2)
    |> Map.put("subject", %{
      "kind" => "record",
      "record" => old["record"],
      "validity" => old["validity"]
    })
    |> update_in(
      ["collection"],
      &Map.merge(&1, %{
        "root_state" => "present",
        "root_sha256" => sha("actual-root-bytes")
      })
    )
  end

  defp absence_v2(selector \\ %{"kind" => "record", "key" => "record.0"}) do
    record_v2()
    |> Map.put("subject", %{"kind" => "absence", "selector" => selector})
    |> update_in(
      ["collection"],
      &Map.merge(&1, %{
        "root_state" => "absent",
        "generation" => 0,
        "floor" => 0,
        "floor_anchor" => nil,
        "root_sha256" => nil,
        "manifest_sha256" => nil
      })
    )
  end

  defp binding(changes \\ %{}) do
    Map.merge(
      %{
        "version" => 1,
        "session_id" => @session,
        "turn_id" => @turn,
        "request_id" => @request,
        "phase" => "model",
        "route_sha256" => sha("actual-route"),
        "tools_sha256" => JSON.digest([]),
        "source_generation" => 12,
        "policy_generation" => 4,
        "checked_at_ms" => 1000,
        "deadline_ms" => 1500
      },
      changes
    )
  end

  defp verdict(d, status \\ "eligible", current \\ :same),
    do: %{
      "dependency_sha256" => sha(d),
      "status" => status,
      "current" => if(current == :same, do: if(status == "eligible", do: d), else: current)
    }

  defp user(text \\ "managed excerpt"), do: %{"role" => "user", "content" => text}

  defp admitted(message \\ user(), deps \\ [dependency()], kind \\ "reference") do
    {:ok, state} = Managed.new(@session)
    {:ok, event, state} = Managed.admit(state, producer(kind), 0, message, deps)
    {:ok, plan} = Managed.plan(state, [message])
    {event, state, plan}
  end

  test "no managed domain preserves exact messages and produces no projection event" do
    {:ok, state} = Managed.new(@session)
    messages = [user("native input"), %{"role" => "assistant", "content" => "ordinary answer"}]
    assert {:ok, plan} = Managed.plan(state, messages)
    assert {:ok, nil, ^messages, ^state} = Managed.project(plan, [], binding())
    assert @error == Managed.new("worker-selected-session")
  end

  test "dependencies are closed and separate actual project from Collection namespace" do
    d = dependency()
    assert Managed.dependency?(d)
    refute d["project_id"] == d["collection"]["project"]

    for key <- Map.keys(d), do: refute(Managed.dependency?(Map.delete(d, key)))

    for key <- Map.keys(d["validity"]),
        do: refute(Managed.dependency?(update_in(d["validity"], &Map.delete(&1, key))))

    for bad <- [
          Map.put(d, "origin", "operator"),
          put_in(d, ["collection", "project"], sha("wrong-namespace")),
          put_in(d, ["record", "key"], "../root.json"),
          put_in(d, ["record", "revision"], 0),
          put_in(d, ["validity", "valid_until_ms"], 1.0),
          put_in(d, ["policy_generation"], 9_007_199_254_740_992),
          put_in(d, ["validity", "source_versions"], [%{"id" => sha(1), "version" => "path"}]),
          put_in(d, ["validity", "dependencies"], [Map.put(d["record"], "value", "untrusted")])
        ],
        do: refute(Managed.dependency?(bad))
  end

  test "root-only absent and empty reads retain taint; imported floors may exceed local generation" do
    root = dependency() |> Map.put("record", nil)

    imported =
      put_in(root, ["collection", "floor"], 100)
      |> put_in(["collection", "floor_anchor"], @request)

    assert Managed.dependency?(root)
    assert Managed.dependency?(imported)
    refute Managed.dependency?(put_in(imported, ["collection", "floor_anchor"], nil))
    refute Managed.dependency?(put_in(root, ["collection", "floor_anchor"], @request))
    {_, _, plan} = admitted(user("record absent"), [root])

    assert {:ok, _, [withdrawn], _} =
             Managed.project(plan, [verdict(root, "root_changed")], binding())

    refute withdrawn["content"] =~ "record absent"
  end

  test "v2 absence identifies the actual selector without invented validity or root hashes" do
    absent = absence_v2()
    empty = absence_v2(%{"kind" => "collection"})
    assert Managed.dependency?(absent)
    assert Managed.dependency?(empty)
    assert Managed.dependency?(record_v2())

    for d <- [absent, empty, record_v2()],
        key <- Map.keys(d),
        do: refute(Managed.dependency?(Map.delete(d, key)))

    for bad <- [
          Map.put(absent, "validity", dependency()["validity"]),
          Map.put(absent, "record", nil),
          put_in(absent, ["collection", "root_sha256"], sha("invented")),
          put_in(absent, ["collection", "manifest_sha256"], sha("invented")),
          put_in(absent, ["collection", "generation"], 1),
          put_in(absent, ["collection", "floor"], 1),
          put_in(absent, ["collection", "root_state"], "present"),
          put_in(absent, ["subject", "selector", "key"], "../root.json"),
          put_in(empty, ["subject", "selector", "limit"], 4),
          put_in(empty, ["subject", "selector", "kind"], "scan"),
          put_in(empty, ["subject", "selector", "kind"], "filtered_empty"),
          Map.put(absent, "subject", record_v2()["subject"]),
          put_in(record_v2(), ["subject", "record"], nil),
          put_in(record_v2(), ["subject", "kind"], "absence"),
          put_in(record_v2(), ["collection", "root_sha256"], nil),
          put_in(record_v2(), ["version"], 1)
        ],
        do: refute(Managed.dependency?(bad))
  end

  test "v2 absent read survives replay and withdraws its whole occurrence on first publication" do
    d = absence_v2()
    message = user("No matching record exists")
    {event, state, plan} = admitted(message, [d])
    {:ok, empty} = Managed.new(@session)
    assert {:ok, ^state} = Managed.replay_admission(empty, event, [message])

    assert {:ok, _, [withdrawn], _} =
             Managed.project(plan, [verdict(d, "root_changed")], binding())

    refute withdrawn["content"] =~ "No matching record"
    assert {:ok, nil_event, [^message], ^state} = Managed.project(plan, [verdict(d)], binding())
    assert nil_event != nil

    present =
      d
      |> Map.put("collection", record_v2()["collection"])

    assert Managed.dependency?(present)

    assert {:ok, projected, [^message], next} =
             Managed.project(plan, [verdict(d, "eligible", present)], binding())

    assert {:ok, %{state: ^next, messages: [^message], live_pending: true}} =
             Managed.replay(state, [message], projected, binding())

    assert Map.values(next.dependencies) == [present]

    for substituted <- [
          record_v2(),
          Map.put(present, "subject", absence_v2(%{"kind" => "collection"})["subject"]),
          put_in(present, ["subject", "selector", "key"], "other.record"),
          put_in(present, ["collection", "generation"], 0),
          Map.put(dependency(), "record", nil)
        ],
        do:
          assert(
            @error == Managed.project(plan, [verdict(d, "eligible", substituted)], binding())
          )
  end

  test "v2 present record refresh preserves subject provenance and exclusive expiry" do
    d = record_v2()
    {_, _, plan} = admitted(user(), [d])

    current =
      d
      |> put_in(["collection", "generation"], 11)
      |> put_in(["collection", "root_sha256"], sha("new root"))
      |> put_in(["collection", "manifest_sha256"], sha("new manifest"))

    assert {:ok, _, _, _} = Managed.project(plan, [verdict(d, "eligible", current)], binding())

    for substituted <- [
          put_in(current, ["subject", "record", "value_sha256"], sha("changed")),
          put_in(current, ["subject", "validity", "lineage"], sha("changed")),
          put_in(current, ["subject", "validity", "recipe_sha256"], sha("changed")),
          put_in(current, ["subject", "validity", "source_versions"], []),
          put_in(current, ["subject", "validity", "status"], "suppressed"),
          put_in(current, ["subject", "validity", "valid_until_ms"], 1000),
          put_in(current, ["collection", "generation"], 10),
          dependency()
        ],
        do:
          assert(
            @error == Managed.project(plan, [verdict(d, "eligible", substituted)], binding())
          )
  end

  test "v2 materialized empty and imported floors retain exact native root identity" do
    d = absence_v2(%{"kind" => "collection"}) |> Map.put("collection", record_v2()["collection"])

    d =
      d |> put_in(["collection", "floor"], 20) |> put_in(["collection", "floor_anchor"], @request)

    assert Managed.dependency?(d)
    {_, _, plan} = admitted(user("Collection is empty"), [d])
    assert {:ok, _, _, _} = Managed.project(plan, [verdict(d)], binding())

    for key <- ~w(root_sha256 manifest_sha256),
        do:
          assert(
            @error ==
              Managed.project(
                plan,
                [verdict(d, "eligible", put_in(d, ["collection", key], sha("changed")))],
                binding()
              )
          )

    refute Managed.dependency?(put_in(d, ["collection", "floor_anchor"], nil))
  end

  test "admission binds original message, producer, position, Session and exact dependency union" do
    message = user()
    {event, state, _} = admitted(message)
    {:ok, empty} = Managed.new(@session)
    assert {:ok, ^state} = Managed.replay_admission(empty, event, [message])
    assert @error == Managed.replay_admission(empty, event, [user("changed")])

    for changed <- [
          Map.put(event, "position", 1),
          Map.put(event, "message_sha256", sha("different")),
          Map.put(event, "dependencies_sha256", sha([])),
          put_in(event, ["producer", "id"], "foreign"),
          Map.put(event, "extra", true),
          Map.put(event, "version", 2),
          Map.put(event, "session_id", @request)
        ],
        do: assert(@error == Managed.replay_admission(empty, changed, [message, message]))

    foreign = Map.put(event, "session_id", @request)
    foreign = Map.put(foreign, "occurrence_id", sha(Map.delete(foreign, "occurrence_id")))
    assert @error == Managed.replay_admission(empty, foreign, [message])
    assert @error == Managed.admit(state, producer("reference", 1), 0, message, [dependency(1)])
  end

  test "all read and inherited dependencies survive worker reformatting and deduplicate canonically" do
    {event, state, _} = admitted(user(), [dependency(1), dependency(0), dependency(1)])
    assert length(event["dependencies"]) == 2
    assert {:ok, deps} = Managed.inherit(state, [event["occurrence_id"]], [dependency(2)])
    assert deps == ordered([dependency(0), dependency(1), dependency(2)])
    assert @error == Managed.inherit(state, [sha("unknown")], [])
    assert @error == Managed.inherit(state, [event["occurrence_id"], event["occurrence_id"]], [])
    assert @error == Managed.union([[Map.put(dependency(), "worker_selected", true)]])

    answer = %{
      "role" => "assistant",
      "content" => "a free paraphrase without any original quotation"
    }

    assert {:ok, _, derived} = Managed.admit(state, producer("assistant"), 1, answer, deps)
    assert {:ok, plan} = Managed.plan(derived, [user(), answer])
    values = Enum.map(plan.dependencies, &verdict(&1, "suppressed"))
    assert {:ok, _, [first, second], next} = Managed.project(plan, values, binding())
    refute first["content"] =~ "managed excerpt"
    refute second["content"] =~ "paraphrase"
    assert next.dependencies == %{}
    assert @error == Managed.inherit(next, [event["occurrence_id"]], [])
  end

  test "native result withdrawal preserves call IDs, result order, counts and untouched continuation" do
    call = %{
      "role" => "assistant",
      "content" => "",
      "provider_data" => %{"opaque" => "unchanged"},
      "tool_calls" => [
        %{"id" => "a", "function" => %{"name" => "lookup", "arguments" => "{}"}},
        %{"id" => "b", "function" => %{"name" => "other", "arguments" => "{}"}}
      ]
    }

    result = %{
      "role" => "tool",
      "tool_call_id" => "a",
      "content" => "managed secret",
      "ipse_tool_outcome" => %{"status" => "ok", "approval" => "not_required"}
    }

    other = %{"role" => "tool", "tool_call_id" => "b", "content" => "unmanaged"}
    messages = [call, result, other]
    {:ok, empty} = Managed.new(@session)

    {:ok, _, state} =
      Managed.admit(empty, producer("collection.result"), 1, result, [dependency()])

    {:ok, plan} = Managed.plan(state, messages)

    assert {:ok, event, projected, next} =
             Managed.project(plan, [verdict(dependency(), "suppressed")], binding())

    assert length(projected) == length(messages)
    assert hd(projected) == call
    assert List.last(projected) == other
    assert Map.delete(Enum.at(projected, 1), "content") == Map.delete(result, "content")
    assert Ipse.Session.Reference.safe_tail?(projected)

    assert {:ok, %{state: ^next, messages: ^projected, live_pending: true}} =
             Managed.replay(state, messages, event, binding())

    assert {:ok, next_plan} = Managed.plan(next, projected)
    assert {:ok, nil, ^projected, ^next} = Managed.project(next_plan, [], binding())
    assert messages == [call, result, other]
  end

  test "verdict set must cover exactly every dependency once" do
    {_, _, plan} = admitted(user(), [dependency(0), dependency(1)])
    values = Enum.map(plan.dependencies, &verdict/1)
    assert {:ok, _, _, _} = Managed.project(plan, Enum.reverse(values), binding())

    for invalid <- [
          [],
          tl(values),
          [hd(values), hd(values)],
          values ++ [verdict(dependency(2))],
          [Map.put(hd(values), "origin", "host") | tl(values)]
        ],
        do: assert(@error == Managed.project(plan, invalid, binding()))
  end

  test "expiry is exclusive at actual admission time and cannot be hidden by eligible verdict" do
    {_, _, plan} = admitted()

    assert {:ok, _, _, _} =
             Managed.project(
               plan,
               [verdict(dependency())],
               binding(%{"checked_at_ms" => 1999, "deadline_ms" => 2000})
             )

    assert @error ==
             Managed.project(
               plan,
               [verdict(dependency())],
               binding(%{"checked_at_ms" => 2000, "deadline_ms" => 2001})
             )

    assert {:ok, _, [message], _} =
             Managed.project(
               plan,
               [verdict(dependency(), "expired")],
               binding(%{"checked_at_ms" => 2000, "deadline_ms" => 2001})
             )

    assert message["content"] =~ "expired"
  end

  test "host fresh clearance at a newer root preserves byte-identical unchanged content" do
    {_, state, plan} = admitted()
    old = dependency()

    current =
      old
      |> put_in(["collection", "generation"], 11)
      |> put_in(["collection", "manifest_sha256"], sha("new unrelated root"))

    values = [verdict(old, "eligible", current)]
    assert {:ok, event, messages, next} = Managed.project(plan, values, binding())
    assert messages == plan.messages
    assert event["withdrawals"] == []
    assert event["before_sha256"] == event["after_sha256"]
    assert next.dependencies == %{sha(current) => current}
    refute Map.has_key?(next.dependencies, sha(old))

    assert {:ok, %{state: ^next, live_pending: true}} =
             Managed.replay(state, plan.messages, event, binding())

    assert {:ok, next_plan} = Managed.plan(next, messages)
    assert next_plan.dependencies == [current]
  end

  test "withdrawal releases only unreferenced dependencies and never revives a withdrawn parent" do
    {:ok, empty} = Managed.new(@session)

    {:ok, first, state} =
      Managed.admit(empty, producer("reference", 0), 0, user("first"), [dependency(0)])

    {:ok, second, state} =
      Managed.admit(state, producer("reference", 1), 1, user("second"), [
        dependency(0),
        dependency(1)
      ])

    {:ok, plan} = Managed.plan(state, [user("first"), user("second")])
    values = [verdict(dependency(0)), verdict(dependency(1), "suppressed")]

    assert {:ok, event, [first_message, second_message], next} =
             Managed.project(plan, values, binding())

    assert first_message == user("first")
    refute second_message["content"] == "second"
    assert length(event["withdrawals"]) == 1
    assert next.dependencies == %{sha(dependency(0)) => dependency(0)}
    assert {:ok, [remaining]} = Managed.inherit(next, [first["occurrence_id"]], [])
    assert remaining == dependency(0)
    assert @error == Managed.inherit(next, [second["occurrence_id"]], [])
  end

  test "fresh clearance cannot substitute record, project, namespace, pin or reviewed recipe" do
    {_, _, plan} = admitted()
    old = dependency()

    for changed <- [
          put_in(old, ["record", "value_sha256"], sha("changed value")),
          put_in(old, ["record", "revision"], 2),
          Map.put(old, "project_id", sha("foreign project")),
          Map.put(old, "pin_sha256", sha("new pin")),
          Map.put(old, "policy_generation", 5),
          put_in(old, ["validity", "recipe_sha256"], sha("worker recipe")),
          put_in(old, ["validity", "lineage"], sha("new claim lineage")),
          put_in(old, ["validity", "source_versions"], []),
          put_in(old, ["collection", "generation"], 9),
          put_in(old, ["collection", "manifest_sha256"], sha("changed without generation")),
          put_in(old, ["validity", "status"], "suppressed")
        ],
        do:
          assert(@error == Managed.project(plan, [verdict(old, "eligible", changed)], binding()))

    assert @error == Managed.project(plan, [verdict(old, "suppressed", old)], binding())
    assert @error == Managed.project(plan, [verdict(old, "eligible", nil)], binding())
  end

  test "closed dispatch binding rejects stale, cross-session and malformed controls" do
    {_, _, plan} = admitted()

    for bad <- [
          %{},
          Map.put(binding(), "session_id", @request),
          Map.put(binding(), "request_id", "request"),
          Map.put(binding(), "phase", "worker_claim"),
          Map.put(binding(), "route_sha256", "url"),
          Map.put(binding(), "deadline_ms", 999),
          Map.put(binding(), "deadline_ms", 121_001),
          Map.put(binding(), "source_generation", -1),
          Map.put(binding(), "job_ref", "forged")
        ],
        do: assert(@error == Managed.project(plan, [verdict(dependency())], bad))
  end

  test "opaque provider copies, reasoning and managed call arguments refuse unsafe withdrawal" do
    base = %{"role" => "assistant", "content" => "managed prose"}

    native = [
      Map.put(base, "provider_data", %{
        "provider" => "anthropic",
        "content" => [%{"type" => "text", "text" => "managed prose"}]
      }),
      Map.put(base, "provider_data", %{
        "provider" => "openai",
        "output" => [%{"type" => "reasoning", "encrypted_content" => "managed prose"}]
      }),
      Map.put(base, "provider_data", %{
        "provider" => "ollama",
        "message" => %{"content" => "managed prose"}
      }),
      Map.put(base, "reasoning", "managed prose"),
      Map.put(base, "ipse_result_excerpt", %{"excerpt" => "managed prose"})
    ]

    for message <- native do
      {_, _, plan} = admitted(message, [dependency()], "assistant")
      assert {:ok, _, [^message], _} = Managed.project(plan, [verdict(dependency())], binding())
      assert @unsafe == Managed.project(plan, [verdict(dependency(), "suppressed")], binding())
    end

    call =
      Map.put(base, "tool_calls", [
        %{
          "id" => "x",
          "function" => %{"name" => "write", "arguments" => ~s({"value":"managed prose"})}
        }
      ])

    result = %{"role" => "tool", "tool_call_id" => "x", "content" => "done"}
    {:ok, empty} = Managed.new(@session)
    {:ok, _, state} = Managed.admit(empty, producer("assistant"), 0, call, [dependency()])
    {:ok, plan} = Managed.plan(state, [call, result])
    assert @unsafe == Managed.project(plan, [verdict(dependency(), "suppressed")], binding())
    assert @error == Managed.plan(state, [call])
  end

  test "host-looking extra metadata cannot preserve stale text through content-only withdrawal" do
    message =
      user()
      |> Map.put("ipse_tool_outcome", %{
        "status" => "ok",
        "approval" => "not_required",
        "copy" => "managed excerpt"
      })

    {_, _, plan} = admitted(message)
    assert @unsafe == Managed.project(plan, [verdict(dependency(), "unavailable")], binding())
  end

  test "pure replay rejects coherent crossbinding, changed plan and forged projection hashes" do
    {_, state, plan} = admitted()
    {:ok, event, _, _} = Managed.project(plan, [verdict(dependency(), "suppressed")], binding())

    for changed <- [
          Map.put(event, "after_sha256", sha("invented")),
          Map.put(event, "plan_sha256", sha("invented")),
          put_in(event, ["withdrawals", Access.at(0), "position"], 1),
          put_in(event, ["withdrawals", Access.at(0), "reason"], "expired"),
          Map.put(event, "version", 2),
          Map.put(event, "extra", true)
        ],
        do: assert(@error == Managed.replay(state, plan.messages, changed, binding()))

    other = binding(%{"request_id" => @turn, "phase" => "compaction"})
    {:ok, coherent, _, _} = Managed.project(plan, [verdict(dependency(), "suppressed")], other)
    assert @error == Managed.replay(state, plan.messages, coherent, binding())

    assert @error ==
             Managed.project(%{plan | sha256: sha("forged")}, [verdict(dependency())], binding())

    assert @error == Managed.plan(state, [user("changed history")])

    assert @error ==
             Managed.plan(
               %{
                 state
                 | dependencies: Map.put(state.dependencies, sha(dependency(2)), dependency(2))
               },
               plan.messages
             )
  end

  test "forty four-read turns retain all160 dependencies in derived answers and checkpoint union" do
    {:ok, empty} = Managed.new(@session)

    {state, events, messages} =
      Enum.reduce(0..39, {empty, [], []}, fn turn, {state, events, messages} ->
        message = user("turn #{turn} reads")
        deps = Enum.map(0..3, &dependency(turn * 4 + &1))

        {:ok, event, state} =
          Managed.admit(state, producer("reference", turn), turn, message, deps)

        {state, events ++ [event], messages ++ [message]}
      end)

    assert map_size(state.dependencies) == 160
    assert {:ok, inherited} = Managed.inherit(state, Enum.map(events, & &1["occurrence_id"]), [])
    assert length(inherited) == 160
    answer = %{"role" => "assistant", "content" => "all earlier material influenced this"}
    assert {:ok, _, state} = Managed.admit(state, producer("assistant"), 40, answer, inherited)
    assert {:ok, plan} = Managed.plan(state, messages ++ [answer])
    assert {:ok, checkpoint} = Managed.checkpoint(plan, 41)
    assert checkpoint["version"] == 2
    assert length(checkpoint["dependencies"]) == 160
    assert checkpoint["dependencies_sha256"] == JSON.digest(inherited)

    assert @error ==
             Managed.admit(
               empty,
               producer("reference"),
               0,
               user(),
               Enum.map(0..128, &dependency/1)
             )

    assert {:ok, _, _} =
             Managed.admit(empty, producer("checkpoint"), 0, answer, checkpoint["dependencies"])

    {_, _, checkpoint_plan} = admitted(answer, inherited, "checkpoint")
    values = Enum.map(inherited, &verdict(&1, "suppressed"))

    assert @unsafe ==
             Managed.project(checkpoint_plan, values, binding(%{"phase" => "compaction"}))

    assert @error == Managed.checkpoint(plan, 42)
  end

  test "active dictionary reaches2048 canonical entries and refuses2049 without eviction" do
    deps = Enum.map(0..2047, &dependency/1)
    assert {:ok, result} = Managed.union([deps])
    assert length(result) == 2048
    assert @error == Managed.union([deps ++ [dependency(2048)]])
    assert {:ok, duplicate} = Managed.union([deps, deps])
    assert result == duplicate
  end

  test "each dependency has an actual encoded8KiB ceiling and dictionaries count all bytes" do
    exact = sized_dependency(8192)
    assert byte_size(Jason.encode!(exact)) == 8192
    assert Managed.dependency?(exact)
    refute Managed.dependency?(sized_dependency(8193))
    deps = Enum.map(0..511, &sized_dependency(8192, &1))
    assert {:ok, fitting} = Managed.union([Enum.take(deps, 511)])
    assert length(fitting) == 511
    assert @error == Managed.union([deps])
  end

  test "direct publications honor both128-reference and128KiB encoded union limits" do
    {:ok, state} = Managed.new(@session)
    compact = fn n -> put_in(dependency(n), ["validity", "source_versions"], []) end

    assert {:ok, _, _} =
             Managed.admit(
               state,
               producer("reference"),
               0,
               user(),
               Enum.map(0..127, compact)
             )

    assert @error ==
             Managed.admit(
               state,
               producer("reference"),
               0,
               user(),
               Enum.map(0..128, compact)
             )

    assert @error ==
             Managed.admit(
               state,
               producer("assistant"),
               0,
               user(),
               Enum.map(0..128, &dependency/1)
             )

    large = Enum.map(0..15, &sized_dependency(8192, &1))
    assert @error == Managed.admit(state, producer("reference"), 0, user(), large)

    assert {:ok, _, _} =
             Managed.admit(state, producer("reference"), 0, user(), Enum.take(large, 15))
  end

  test "occurrence index reaches1024 and refuses another admission without eviction" do
    {:ok, empty} = Managed.new(@session)

    {state, messages} =
      Enum.reduce(0..1023, {empty, []}, fn n, {state, messages} ->
        message = user("managed occurrence #{n}")

        {:ok, _, state} =
          Managed.admit(state, producer("reference", n), n, message, [dependency()])

        {state, [message | messages]}
      end)

    assert map_size(state.occurrences) == 1024
    assert map_size(state.dependencies) == 1

    assert @error ==
             Managed.admit(state, producer("reference", 1024), 1024, user(), [dependency()])

    assert {:ok, _} = Managed.plan(state, Enum.reverse(messages))
  end

  defp sized_dependency(bytes, n \\ 0) do
    d = dependency(n)
    sources = ordered(Enum.map(0..5, &%{"id" => sha(["source", &1]), "version" => sha(&1)}))
    records = Enum.map(0..31, &%{"key" => "r.#{&1}", "revision" => 1, "value_sha256" => sha(&1)})

    d =
      d
      |> put_in(["validity", "source_versions"], sources)
      |> put_in(["validity", "dependencies"], records)

    extra = bytes - byte_size(Jason.encode!(d))
    assert extra >= 0

    {records, remaining} =
      Enum.map_reduce(records, extra, fn record, remaining ->
        add = min(96 - byte_size(record["key"]), remaining)
        {Map.update!(record, "key", &(&1 <> String.duplicate("a", add))), remaining - add}
      end)

    assert remaining == 0
    put_in(d, ["validity", "dependencies"], ordered(records))
  end
end
