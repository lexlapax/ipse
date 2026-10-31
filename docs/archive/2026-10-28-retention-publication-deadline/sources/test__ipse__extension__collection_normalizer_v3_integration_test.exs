unless Code.ensure_loaded?(Ipse.Test.NormalizerV3Fixture) do
  Code.require_file("collection_normalizer_v3_test.exs", __DIR__)
end

defmodule Ipse.Extension.CollectionNormalizerV3IntegrationTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.Collection, as: C
  alias Ipse.Extension.Collection.{ManagedPages, Migration, NormalizerV3, ObservedRead}
  alias Ipse.Extension.ProjectIdentity, as: Identity
  alias Ipse.Session.ManagedReference
  alias Ipse.Test.NormalizerV3Fixture, as: F
  alias IpseKnowledge.Knowledge.Records
  alias Ipse.{JSON, Runner}
  @moduletag timeout: 120_000

  # Author integration controls, not independent qualification. Source members
  # are explicit trusted fixtures. Every Collection record/witness comes from
  # actual publication or checked actual read views; F.read/F.witness are unused.
  # Retain isolated stores, including failures, for read-only diagnostics.
  setup do
    base = Path.join(System.tmp_dir!(), "ipse-normalizer-v3-actual-" <> Ipse.Usage.id())

    for path <- [base, base <> "/home", base <> "/work"] do
      File.mkdir!(path)
      File.chmod!(path, 0o700)
    end

    {:ok, binding} = Identity.admit(base <> "/home", base <> "/work", :folder)
    {:ok, helper} = Runner.protected_helper(base <> "/work")

    assert JSON.sha256(File.read!(helper)) ==
             JSON.sha256(File.read!(Application.app_dir(:ipse, "priv/ipse-runner")))

    %{
      base: base,
      home: base <> "/home",
      cwd: base <> "/work",
      binding: binding,
      root: base <> "/collections",
      namespace: F.namespace()
    }
  end

  test "native absence initializes then actual active literal/proposal publications retain MAC provenance",
       c do
    assert {:ok, first} = publish(c, options(1, 0), scope(c), first: true)
    assert first.read_units == 19
    assert length(first.core["normalization"]["metadata_changes"]) == 3
    assert entry(c)["state"] == "active"
    first_format = first.format
    assert first_format["revision"] == 1

    assert {:ok, second} =
             publish(c, options(2, 1, "literal_source", "preference"), scope(c, false))

    assert second.read_units == 23
    assert second.format == first_format
    assert second.core["normalization"]["valid_until_ms"] == nil
    assert {:ok, third} = publish(c, options(3, 2, "proposal"), scope(c, false))
    assert third.format == first_format
    assert third.core["normalization"]["eligibility"] == "never_current"
    assert third.core["receipt"]["generation"] == 3
    assert third.live_revision == 3 and second.live_revision == 2
  end

  test "a forged literal native answer is refused under the actual V3 publication lock", c do
    assert {:ok, _} = publish(c, options(1, 0), scope(c), first: true)
    before = snapshot(c, [ManagedPages.format_key()])
    opts = options(2, 1)
    [original] = opts.verified_sources
    source = %{original | "origin" => "native_operator_answer", "kind" => "input.operator_answer"}
    assert {:ok, lineage} = Ipse.Extension.ManagedRecipe.source_identity(source)
    [change] = opts.request["changes"]

    value =
      change["value"]
      |> Map.put("id", lineage)
      |> Map.put("lineage", lineage)
      |> put_in(["evidence", "sources"], [source])

    request =
      put_in(opts.request, ["changes"], [
        %{change | "key" => "note." <> lineage, "value" => value}
      ])

    opts = %{opts | request: request, verified_sources: [source]}

    assert {:error, :managed_normalization_refused} = publish(c, opts, scope(c, false))
    assert snapshot(c, [ManagedPages.format_key()]) == before

    assert {:ok, pending_key, pending_value} =
             Records.capture(
               %{
                 "text" => source["quote"],
                 "category" => "ordinary",
                 "reason" => "synthetic answer",
                 "event_at_ms" => nil
               },
               source,
               10 * 86_400_000
             )

    pending = options(2, 1, "proposal")

    pending_request =
      put_in(pending.request, ["changes"], [
        %{"key" => pending_key, "expected_revision" => 0, "value" => pending_value}
      ])

    pending = %{pending | request: pending_request, verified_sources: [source]}
    assert {:ok, result} = publish(c, pending, scope(c, false))
    assert result.core["normalization"]["eligibility"] == "never_current"
  end

  test "historical signed native answers and fragments are refused after recipe guards change" do
    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2"] ++ paths ++ ["test/support/historical_answer_observation.exs"],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "HISTORICAL_SIGNED_RECORDS_REFUSED"
  end

  test "signed literal observation follows the selected recipe evidence path", c do
    {opts, value} = relocated_evidence(options(1, 0))
    assert {:ok, _} = publish(c, opts, scope(c), first: true)
    selected = %{"op" => "get_record", "key" => hd(opts.request["changes"])["key"]}

    assert {:ok, observed} =
             Identity.with_existing_domain_auth(
               c.home,
               c.cwd,
               c.binding,
               Map.take(scope(c, false), [:namespace, :format]),
               fn cap, catalog ->
                 ObservedRead.managed_record(
                   c.root,
                   c.namespace,
                   selected,
                   cap,
                   catalog,
                   opts.recipe
                 )
               end
             )

    assert observed["observation"]["value"]["record"]["value"] == value
  end

  for field <- ~w(lineage category) do
    test "signed literal observation follows the selected #{field} path", c do
      {opts, value} = relocated_field(options(1, 0), unquote(field))
      assert {:ok, _} = publish(c, opts, scope(c), first: true)
      selected = %{"op" => "get_record", "key" => hd(opts.request["changes"])["key"]}

      assert {:ok, observed} =
               Identity.with_existing_domain_auth(
                 c.home,
                 c.cwd,
                 c.binding,
                 Map.take(scope(c, false), [:namespace, :format]),
                 fn cap, catalog ->
                   ObservedRead.managed_record(
                     c.root,
                     c.namespace,
                     selected,
                     cap,
                     catalog,
                     opts.recipe
                   )
                 end
               )

      assert observed["observation"]["value"]["record"]["value"] == value

      pin =
        Map.new(
          ~w(project_id worktree_id binding_sha256 policy_sha256 identity_sha256 routes_sha256 source_sha256),
          &{&1, JSON.sha256(&1)}
        )
        |> Map.merge(%{
          "version" => 1,
          "session_id" => String.duplicate("a", 32),
          "epoch" => 4,
          "namespace" => c.namespace
        })

      assert {:ok, dependency} =
               ObservedRead.managed_dependency(
                 selected,
                 observed,
                 pin,
                 opts.recipe,
                 opts.verified_sources,
                 opts.now_ms + 1
               )

      assert dependency["subject"]["validity"]["lineage"] == observed["metadata"]["lineage"]
    end
  end

  test "signed proposal observation follows the selected recipe evidence path", c do
    {opts, value} = relocated_evidence(options(1, 0, "proposal"))
    assert {:ok, _} = publish(c, opts, scope(c), first: true)
    selected = %{"op" => "get_record", "key" => hd(opts.request["changes"])["key"]}

    assert {:ok, observed} =
             Identity.with_existing_domain_auth(
               c.home,
               c.cwd,
               c.binding,
               Map.take(scope(c, false), [:namespace, :format]),
               fn cap, catalog ->
                 ObservedRead.managed_proposal(
                   c.root,
                   c.namespace,
                   selected,
                   cap,
                   catalog,
                   opts.recipe
                 )
               end
             )

    assert observed["observation"]["value"]["record"]["value"] == value
    assert observed["metadata"]["eligibility"] == "never_current"
  end

  test "signed proposal observation follows the selected lineage path", c do
    {opts, value} = relocated_field(options(1, 0, "proposal"), "lineage")
    assert {:ok, _} = publish(c, opts, scope(c), first: true)
    selected = %{"op" => "get_record", "key" => hd(opts.request["changes"])["key"]}

    assert {:ok, observed} =
             Identity.with_existing_domain_auth(
               c.home,
               c.cwd,
               c.binding,
               Map.take(scope(c, false), [:namespace, :format]),
               fn cap, catalog ->
                 ObservedRead.managed_proposal(
                   c.root,
                   c.namespace,
                   selected,
                   cap,
                   catalog,
                   opts.recipe
                 )
               end
             )

    assert observed["observation"]["value"]["record"]["value"] == value
    assert observed["metadata"]["eligibility"] == "never_current"
  end

  test "small actual series crosses the live leaf split without synthetic metadata seeding", c do
    assert {:ok, first} = publish(c, options(1, 0), scope(c), first: true)

    {last, split?} =
      Enum.reduce(2..27, {first, false}, fn n, {_, split?} ->
        assert {:ok, result} = publish(c, options(n, n - 1), scope(c, false))
        extras = result.core["normalization"]["metadata_changes"]

        split? =
          split? or
            Enum.count(extras, &String.starts_with?(&1["key"], ManagedPages.prefix(:live))) == 2

        assert result.read_units <= 24
        {result, split?}
      end)

    assert split?
    assert last.core["receipt"]["generation"] == 27
    assert last.format["revision"] == 1
  end

  test "actual managed proposal refuses a full pending queue without changing the root", c do
    assert {:ok, _} = publish(c, options(1, 0), scope(c), first: true)

    for batch <- 0..7 do
      changes =
        for offset <- 1..8 do
          n = batch * 8 + offset

          %{
            "key" => "pending." <> F.id(n),
            "expected_revision" => 0,
            "value" => %{"synthetic" => n}
          }
        end

      assert {:ok, _} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{
                   "op" => "commit",
                   "expected_generation" => batch + 1,
                   "advance_floor" => false,
                   "changes" => changes
                 },
                 Ipse.Usage.id()
               )
    end

    before = snapshot(c, [ManagedPages.format_key()])

    assert {:error, :managed_normalization_refused} =
             publish(c, options(2, 9, "proposal"), scope(c, false))

    assert snapshot(c, [ManagedPages.format_key()]) == before

    assert {:ok, _} =
             C.execute(
               c.root,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 9,
                 "advance_floor" => true,
                 "changes" => [
                   %{"key" => "pending." <> F.id(64), "expected_revision" => 9, "value" => nil}
                 ]
               },
               Ipse.Usage.id()
             )

    assert {:ok, result} = publish(c, options(2, 10, "proposal"), scope(c, false))
    assert result.read_units <= 32
  end

  test "actual managed proposal refuses pending bytes beyond the queue ceiling", c do
    assert {:ok, _} = publish(c, options(1, 0), scope(c), first: true)

    for batch <- 0..7 do
      count = if batch == 7, do: 7, else: 8

      changes =
        for offset <- 1..count do
          n = batch * 8 + offset

          %{
            "key" => "pending." <> F.id(n),
            "expected_revision" => 0,
            "value" => %{"text" => String.duplicate("x", 4200)}
          }
        end

      assert {:ok, _} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{
                   "op" => "commit",
                   "expected_generation" => batch + 1,
                   "advance_floor" => false,
                   "changes" => changes
                 },
                 Ipse.Usage.id()
               )
    end

    before = snapshot(c, [ManagedPages.format_key()])

    assert {:error, :managed_normalization_refused} =
             publish(c, options(2, 9, "proposal"), scope(c, false))

    assert snapshot(c, [ManagedPages.format_key()]) == before
  end

  test "concurrent proposals cannot both pass a 63-record queue boundary", c do
    assert {:ok, _} = publish(c, options(1, 0), scope(c), first: true)

    for batch <- 0..7 do
      count = if batch == 7, do: 7, else: 8

      changes =
        for offset <- 1..count do
          n = batch * 8 + offset

          %{
            "key" => "pending." <> F.id(n),
            "expected_revision" => 0,
            "value" => %{"synthetic" => n}
          }
        end

      assert {:ok, _} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{
                   "op" => "commit",
                   "expected_generation" => batch + 1,
                   "advance_floor" => false,
                   "changes" => changes
                 },
                 Ipse.Usage.id()
               )
    end

    tasks =
      for n <- [2, 3] do
        Task.async(fn -> publish(c, options(n, 9, "proposal"), scope(c, false)) end)
      end

    outcomes = Enum.map(tasks, &Task.await(&1, 30_000))
    assert Enum.count(outcomes, &match?({:ok, _}, &1)) == 1

    assert Enum.any?(outcomes, fn outcome ->
             match?({:conflict, _}, outcome) or outcome == {:error, :project_identity_unavailable}
           end)

    assert snapshot(c, [ManagedPages.format_key()])["summary"]["generation"] == 10

    assert {:error, :managed_normalization_refused} =
             publish(c, options(4, 10, "proposal"), scope(c, false))
  end

  test "a separate VM cannot publish past a signed-domain pending boundary", c do
    assert {:ok, _} = publish(c, options(1, 0), scope(c), first: true)

    for batch <- 0..7 do
      count = if batch == 7, do: 7, else: 8

      changes =
        for offset <- 1..count do
          n = batch * 8 + offset

          %{
            "key" => "pending." <> F.id(n),
            "expected_revision" => 0,
            "value" => %{"synthetic" => n}
          }
        end

      assert {:ok, _} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{
                   "op" => "commit",
                   "expected_generation" => batch + 1,
                   "advance_floor" => false,
                   "changes" => changes
                 },
                 Ipse.Usage.id()
               )
    end

    parent = self()
    first = options(2, 9, "proposal")
    first_scope = scope(c, false)

    owner =
      Task.async(fn ->
        Identity.with_domain_publication(
          c.home,
          c.cwd,
          c.binding,
          first_scope,
          fn _ -> :ok end,
          fn cap, catalog ->
            C.execute_managed_v3(
              c.root,
              c.namespace,
              first.request,
              first_scope.operation_id,
              JSON.digest([first.recipe]),
              fn witness, read ->
                send(parent, {:domain_locked, self()})
                receive do: (:release -> :ok)

                NormalizerV3.normalize(
                  witness,
                  read,
                  Map.merge(first, %{domain_cap: cap, catalog: catalog})
                )
              end
            )
          end
        )
      end)

    assert_receive {:domain_locked, callback}, 5_000
    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    invoke = fn opts, child_scope ->
      program = """
      {:ok, _} = Application.ensure_all_started(:ipse)
      opts = #{inspect(opts, limit: :infinity, printable_limit: :infinity)}
      scope = #{inspect(child_scope)}
      result = Ipse.Extension.ProjectIdentity.with_domain_publication(
        #{inspect(c.home)}, #{inspect(c.cwd)}, #{inspect(c.binding)}, scope, fn _ -> :ok end,
        fn cap, catalog ->
          IO.puts("CALLBACK")
          Ipse.Extension.Collection.execute_managed_v3(
            #{inspect(c.root)}, #{inspect(c.namespace)}, opts.request, scope.operation_id,
            Ipse.JSON.digest([opts.recipe]), fn witness, read ->
              Ipse.Extension.Collection.NormalizerV3.normalize(
                witness, read, Map.merge(opts, %{domain_cap: cap, catalog: catalog}))
            end)
        end)
      case result do
        {:error, :project_identity_unavailable} -> IO.puts("BUSY")
        {:conflict, _} -> IO.puts("CONFLICT")
        {:error, :managed_normalization_refused} -> IO.puts("FULL")
        _ -> System.halt(2)
      end
      """

      System.cmd("elixir", ["--erl", "+S 2:2"] ++ paths ++ ["-e", program],
        stderr_to_stdout: true
      )
    end

    second_scope = scope(c, false)
    assert {"BUSY\n", 0} = invoke.(options(3, 9, "proposal"), second_scope)
    send(callback, :release)
    assert {:ok, _} = Task.await(owner, 10_000)
    assert {"CALLBACK\nCONFLICT\n", 0} = invoke.(options(3, 9, "proposal"), second_scope)
    assert {"CALLBACK\nFULL\n", 0} = invoke.(options(4, 10, "proposal"), scope(c, false))
    assert snapshot(c, [ManagedPages.format_key()])["summary"]["generation"] == 10
  end

  test "pending observation binds the proposal to signed pages at one checked root", c do
    opts = options(1, 0, "proposal")
    assert {:ok, publication} = publish(c, opts, scope(c), first: true)
    key = hd(opts.request["changes"])["key"]
    request = %{"op" => "get_record", "key" => key}

    read = fn recipe ->
      Identity.with_existing_domain_auth(
        c.home,
        c.cwd,
        c.binding,
        Map.take(scope(c, false), [:namespace, :format]),
        fn cap, catalog ->
          ObservedRead.managed_proposal(c.root, c.namespace, request, cap, catalog, recipe)
        end
      )
    end

    assert {:ok, observed} = read.(opts.recipe)
    assert observed["observation"]["witness"]["root_sha256"] == publication.root_sha

    assert observed["observation"]["value"]["record"]["value"] ==
             hd(opts.request["changes"])["value"]

    assert observed["metadata"]["lineage"] == publication.core["normalization"]["lineage"]

    assert observed["metadata"]["valid_until_ms"] ==
             publication.core["normalization"]["valid_until_ms"]

    assert observed["metadata"]["eligibility"] == "never_current"
    assert observed["metadata"]["recipe_sha256"] == JSON.digest([opts.recipe])

    refute observed["observation"]["value"]["record"]["value"]["expires_at_ms"] ==
             observed["metadata"]["valid_until_ms"]

    assert {:error, :collection_observation_refused} =
             read.(Map.put(opts.recipe, "override_prefix", "alternate."))

    override_key = opts.recipe["override_prefix"] <> observed["metadata"]["lineage"]

    assert {:ok, _} =
             C.execute(
               c.root,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 1,
                 "advance_floor" => true,
                 "changes" => [
                   %{
                     "key" => override_key,
                     "expected_revision" => 0,
                     "value" => %{"synthetic" => true}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    assert {:error, :collection_observation_refused} = read.(opts.recipe)

    assert {:ok, _} =
             C.execute(
               c.root,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 2,
                 "advance_floor" => true,
                 "changes" => [%{"key" => override_key, "expected_revision" => 2, "value" => nil}]
               },
               Ipse.Usage.id()
             )

    original = hd(opts.request["changes"])["value"]
    changed = Map.put(original, "text", original["text"] <> " changed")

    assert {:ok, _} =
             C.execute(
               c.root,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 3,
                 "advance_floor" => true,
                 "changes" => [%{"key" => key, "expected_revision" => 1, "value" => changed}]
               },
               Ipse.Usage.id()
             )

    assert {:error, :collection_observation_refused} = read.(opts.recipe)
  end

  test "one checked view binds the literal record to its authenticated live and anchor pages",
       c do
    opts = options(1, 0)
    assert {:ok, publication} = publish(c, opts, scope(c), first: true)
    key = hd(opts.request["changes"])["key"]
    request = %{"op" => "get_record", "key" => key}

    read = fn selected ->
      Identity.with_existing_domain_auth(
        c.home,
        c.cwd,
        c.binding,
        Map.take(scope(c, false), [:namespace, :format]),
        fn cap, catalog ->
          ObservedRead.managed_record(c.root, c.namespace, selected, cap, catalog, opts.recipe)
        end
      )
    end

    assert {:ok, first} = read.(request)

    assert first["observation"]["value"]["record"]["value"] ==
             hd(opts.request["changes"])["value"]

    assert first["observation"]["witness"]["root_sha256"] == publication.root_sha
    assert first["metadata"]["lineage"] == publication.core["normalization"]["lineage"]

    assert first["metadata"]["valid_until_ms"] ==
             publication.core["normalization"]["valid_until_ms"]

    assert first["metadata"]["recipe_sha256"] == JSON.digest([opts.recipe])
    assert first["metadata"]["policy_sha256"] == opts.policy_sha256
    assert first["metadata"]["category"] == "ordinary"

    assert {:error, :collection_observation_refused} =
             Identity.with_existing_domain_auth(
               c.home,
               c.cwd,
               c.binding,
               Map.take(scope(c, false), [:namespace, :format]),
               fn cap, catalog ->
                 ObservedRead.managed_record(
                   c.root,
                   c.namespace,
                   request,
                   cap,
                   catalog,
                   Map.put(opts.recipe, "override_prefix", "alternate.")
                 )
               end
             )

    session = String.duplicate("a", 32)

    pin =
      Map.new(
        ~w(project_id worktree_id binding_sha256 policy_sha256 identity_sha256 routes_sha256 source_sha256),
        &{&1, JSON.sha256(&1)}
      )
      |> Map.merge(%{
        "version" => 1,
        "session_id" => session,
        "epoch" => 4,
        "namespace" => c.namespace
      })

    assert {:ok, old} =
             ObservedRead.managed_dependency(
               request,
               first,
               pin,
               opts.recipe,
               opts.verified_sources,
               opts.now_ms + 1
             )

    assert old["subject"]["validity"]["lineage"] == first["metadata"]["lineage"]
    assert old["subject"]["publication_policy_sha256"] == first["metadata"]["policy_sha256"]

    assert old["subject"]["validity"]["source_versions"] == [
             %{
               "id" => hd(opts.verified_sources)["occurrence_id"],
               "version" => hd(opts.verified_sources)["version_id"]
             }
           ]

    assert {:error, :collection_observation_refused} =
             ObservedRead.managed_dependency(
               request,
               first,
               pin,
               opts.recipe,
               [],
               opts.now_ms + 1
             )

    assert {:error, :collection_observation_refused} =
             ObservedRead.managed_dependency(
               request,
               first,
               pin,
               opts.recipe,
               opts.verified_sources,
               first["metadata"]["valid_until_ms"]
             )

    assert {:error, :collection_observation_refused} =
             ObservedRead.managed_dependency(
               request,
               put_in(first, ["metadata", "lineage"], JSON.sha256("foreign")),
               pin,
               opts.recipe,
               opts.verified_sources,
               opts.now_ms + 1
             )

    assert {:error, :collection_observation_refused} =
             ObservedRead.managed_dependency(
               request,
               first,
               pin,
               Map.put(opts.recipe, "key_prefix", "other."),
               opts.verified_sources,
               opts.now_ms + 1
             )

    assert {:error, :collection_observation_refused} =
             ObservedRead.managed_dependency(
               request,
               put_in(
                 first,
                 ["metadata", "valid_until_ms"],
                 first["metadata"]["valid_until_ms"] + 1
               ),
               pin,
               opts.recipe,
               opts.verified_sources,
               opts.now_ms + 1
             )

    assert {:error, :collection_observation_refused} =
             ObservedRead.managed_dependency(
               request,
               first,
               Map.put(pin, "namespace", JSON.sha256("foreign namespace")),
               opts.recipe,
               opts.verified_sources,
               opts.now_ms + 1
             )

    assert {:error, _} =
             read.(%{"op" => "get_record", "key" => "note." <> String.duplicate("f", 64)})

    assert {:error, _} =
             ObservedRead.managed_record(c.root, c.namespace, request, nil, %{}, opts.recipe)

    assert {:ok, _} = publish(c, options(2, 1), scope(c, false))
    assert {:ok, later} = read.(request)
    assert later["observation"]["value"] == first["observation"]["value"]
    assert later["metadata"] == first["metadata"]

    assert {:ok, current} =
             ObservedRead.managed_dependency(
               request,
               later,
               pin,
               opts.recipe,
               opts.verified_sources,
               opts.now_ms + 1
             )

    message = %{"role" => "user", "content" => "Derived from the selected literal"}
    {:ok, state} = ManagedReference.new(session)

    {:ok, _, state} =
      ManagedReference.admit(
        state,
        %{"kind" => "reference", "id" => "fixture", "parent_id" => nil},
        0,
        message,
        [old]
      )

    {:ok, plan} = ManagedReference.plan(state, [message])

    verdict = %{
      "dependency_sha256" => JSON.digest([old]),
      "status" => "eligible",
      "current" => current
    }

    binding = %{
      "version" => 1,
      "session_id" => session,
      "turn_id" => String.duplicate("b", 32),
      "request_id" => String.duplicate("c", 32),
      "phase" => "model",
      "route_sha256" => JSON.sha256("route"),
      "tools_sha256" => JSON.sha256("tools"),
      "source_generation" => 1,
      "policy_generation" => 4,
      "checked_at_ms" => opts.now_ms + 1,
      "deadline_ms" => opts.now_ms + 1000
    }

    assert {:ok, _, [^message], _} = ManagedReference.project(plan, [verdict], binding)

    changed_policy =
      put_in(
        current,
        ["subject", "publication_policy_sha256"],
        JSON.sha256("other historical policy")
      )

    assert {:error, :managed_reference_refused} =
             ManagedReference.project(plan, [%{verdict | "current" => changed_policy}], binding)

    refute later["observation"]["witness"]["root_sha256"] ==
             first["observation"]["witness"]["root_sha256"]

    {:ok, view} = C.open_view(c.root, c.namespace)

    {:ok, neighbors} =
      C.view_neighbors(view, %{
        "version" => 1,
        "prefix" => ManagedPages.prefix(:live),
        "fence_bytes" => ManagedPages.width(:live),
        "needle" => ManagedPages.live_identity(key)
      })

    page_key = neighbors["neighbors"]["selected"]["key"]
    :ok = C.close_view(view)

    {:ok, %{"record" => page}} =
      C.execute(c.root, c.namespace, %{"op" => "get", "key" => page_key}, Ipse.Usage.id())

    mac = page["value"]["mac"]
    <<first_byte, rest::binary>> = mac
    changed_mac = <<if(first_byte == ?A, do: ?B, else: ?A)>> <> rest
    changed = put_in(page["value"], ["mac"], changed_mac)

    assert {:ok, _} =
             C.execute(
               c.root,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 2,
                 "advance_floor" => true,
                 "changes" => [
                   %{
                     "key" => page_key,
                     "expected_revision" => page["revision"],
                     "value" => changed
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    assert {:error, :collection_observation_refused} = read.(request)
  end

  test "managed record observation with a lost native owner returns no data", c do
    opts = options(1, 0)
    assert {:ok, _} = publish(c, opts, scope(c), first: true)
    request = %{"op" => "get_record", "key" => hd(opts.request["changes"])["key"]}
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:ipse, :extension, :collection, :view_read],
        &__MODULE__.break_view/4,
        self()
      )

    try do
      assert {:unknown, :project_identity_lock_lost} =
               Identity.with_existing_domain_auth(
                 c.home,
                 c.cwd,
                 c.binding,
                 Map.take(scope(c, false), [:namespace, :format]),
                 fn cap, catalog ->
                   ObservedRead.managed_record(
                     c.root,
                     c.namespace,
                     request,
                     cap,
                     catalog,
                     opts.recipe
                   )
                 end
               )

      assert_receive {:managed_record_owner_closed, true}
    after
      :telemetry.detach(handler)
    end
  end

  test "managed record observation rejects an altered anchor MAC", c do
    opts = options(1, 0)
    assert {:ok, _} = publish(c, opts, scope(c), first: true)
    key = hd(opts.request["changes"])["key"]
    lineage = String.replace_prefix(key, "note.", "")
    {:ok, view} = C.open_view(c.root, c.namespace)

    {:ok, neighbors} =
      C.view_neighbors(view, %{
        "version" => 1,
        "prefix" => ManagedPages.prefix(:anchor),
        "fence_bytes" => ManagedPages.width(:anchor),
        "needle" => lineage
      })

    page_key = neighbors["neighbors"]["selected"]["key"]
    :ok = C.close_view(view)

    {:ok, %{"record" => page}} =
      C.execute(c.root, c.namespace, %{"op" => "get", "key" => page_key}, Ipse.Usage.id())

    <<first_byte, rest::binary>> = page["value"]["mac"]
    changed = put_in(page["value"], ["mac"], <<if(first_byte == ?A, do: ?B, else: ?A)>> <> rest)

    assert {:ok, _} =
             C.execute(
               c.root,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 1,
                 "advance_floor" => true,
                 "changes" => [
                   %{
                     "key" => page_key,
                     "expected_revision" => page["revision"],
                     "value" => changed
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    assert {:error, :collection_observation_refused} =
             Identity.with_existing_domain_auth(
               c.home,
               c.cwd,
               c.binding,
               Map.take(scope(c, false), [:namespace, :format]),
               fn cap, catalog ->
                 ObservedRead.managed_record(
                   c.root,
                   c.namespace,
                   %{"op" => "get_record", "key" => key},
                   cap,
                   catalog,
                   opts.recipe
                 )
               end
             )
  end

  test "managed record observation refuses a same-view retention override", c do
    opts = options(1, 0)
    opts = %{opts | recipe: Map.put(opts.recipe, "override_prefix", "suppression.")}
    assert {:ok, _} = publish(c, opts, scope(c), first: true)
    key = hd(opts.request["changes"])["key"]
    lineage = String.replace_prefix(key, "note.", "")

    assert {:ok, _} =
             Identity.with_existing_domain_auth(
               c.home,
               c.cwd,
               c.binding,
               Map.take(scope(c, false), [:namespace, :format]),
               fn cap, catalog ->
                 ObservedRead.managed_record(
                   c.root,
                   c.namespace,
                   %{"op" => "get_record", "key" => key},
                   cap,
                   catalog,
                   opts.recipe
                 )
               end
             )

    assert {:ok, _} =
             C.execute(
               c.root,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 1,
                 "advance_floor" => false,
                 "changes" => [
                   %{
                     "key" => "suppression." <> lineage,
                     "expected_revision" => 0,
                     "value" => %{"kind" => "synthetic suppression"}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    assert {:error, :collection_observation_refused} =
             Identity.with_existing_domain_auth(
               c.home,
               c.cwd,
               c.binding,
               Map.take(scope(c, false), [:namespace, :format]),
               fn cap, catalog ->
                 ObservedRead.managed_record(
                   c.root,
                   c.namespace,
                   %{"op" => "get_record", "key" => key},
                   cap,
                   catalog,
                   opts.recipe
                 )
               end
             )
  end

  test "journal-owned plain source survives replay but remains a never-current proposal", c do
    alias Ipse.Journal
    alias Ipse.Journal.Writer
    alias Ipse.Session.{Input, Saved}

    journal = c.base <> "/journal"
    File.mkdir!(journal)
    {:ok, session} = Journal.create(journal, %{})
    {:ok, events} = Journal.load(journal, session)
    {:ok, saved} = Saved.restore(events, session)
    {:ok, writer} = Writer.start(journal, session, self())
    assert :ok = Writer.install_source_window(writer, saved.source_window)

    text = "Acme has owner Alex"

    # This is a synthetic receipt, not an observation from an operator terminal.
    observation = %{
      "version" => 1,
      "event_id" => Ipse.Usage.id(),
      "display_sha256" => JSON.sha256("synthetic display"),
      "text_sha256" => JSON.sha256(text)
    }

    assert :ok =
             Writer.append(
               writer,
               Input.received(session, Ipse.Usage.id(), text, text, observation)
             )

    assert :ok =
             Writer.append(writer, %{
               "type" => "message",
               "message" => %{"role" => "user", "content" => text}
             })

    assert {:ok, page} = Writer.source_query(writer, {"source.list", %{"limit" => 1}})
    [row] = page["sources"]

    assert {:ok, resolved} =
             Writer.source_query(
               writer,
               {:proof, %{"handle" => row["read_handle"], "quote" => text}}
             )

    proof = resolved["proof"]
    opts = options(1, 0, "proposal")

    assert {:ok, key, value} =
             Records.capture(
               %{
                 "text" => text,
                 "category" => "ordinary",
                 "reason" => "synthetic",
                 "event_at_ms" => nil
               },
               proof,
               10 * 86_400_000
             )

    request =
      put_in(opts.request, ["changes"], [
        %{"key" => key, "expected_revision" => 0, "value" => value}
      ])

    opts = %{opts | request: request, verified_sources: [proof]}
    assert {:ok, _} = publish(c, opts, scope(c), first: true)
    assert :ok = Writer.close(writer)

    assert {:ok, events} = Journal.load(journal, session)
    assert {:ok, saved} = Saved.restore(events, session)
    assert {:ok, writer} = Writer.start(journal, session, self())
    on_exit(fn -> if Process.alive?(writer), do: Writer.close(writer) end)
    assert :ok = Writer.install_source_window(writer, saved.source_window)
    assert {:ok, replay_page} = Writer.source_query(writer, {"source.list", %{"limit" => 1}})
    [replay_row] = replay_page["sources"]

    assert {:ok, replay_proof} =
             Writer.source_query(
               writer,
               {:proof, %{"handle" => replay_row["read_handle"], "quote" => text}}
             )

    assert replay_proof["proof"] == proof
    assert {:ok, checked} = Writer.source_query(writer, {:stored_proof, proof})
    assert checked["proof"] == proof
    refute checked["window_id"] == resolved["window_id"]

    request = %{"op" => "get_record", "key" => key}

    assert {:ok, managed} =
             Identity.with_existing_domain_auth(
               c.home,
               c.cwd,
               c.binding,
               Map.take(scope(c, false), [:namespace, :format]),
               fn cap, catalog ->
                 ObservedRead.managed_proposal(
                   c.root,
                   c.namespace,
                   request,
                   cap,
                   catalog,
                   opts.recipe
                 )
               end
             )

    pin =
      Map.new(
        ~w(project_id worktree_id binding_sha256 policy_sha256 identity_sha256 routes_sha256 source_sha256),
        &{&1, JSON.sha256(&1)}
      )
      |> Map.merge(%{
        "version" => 1,
        "session_id" => session,
        "epoch" => 4,
        "namespace" => c.namespace
      })

    assert {:error, :collection_observation_refused} =
             ObservedRead.managed_dependency(
               request,
               managed,
               pin,
               opts.recipe,
               [checked["proof"]],
               opts.now_ms + 1
             )

    assert managed["metadata"]["eligibility"] == "never_current"

    assert get_in(managed, ["observation", "value", "record", "value", "evidence", "sources"]) ==
             [proof]

    assert {:error, :source_index_refused} =
             Writer.source_query(writer, {:stored_proof, Map.put(proof, "quote", "changed")})

    assert :ok = Writer.close(writer)
  end

  def break_view(_, _, _, owner) do
    case Process.get({C, :lock_held}) do
      %{port: port} -> send(owner, {:managed_record_owner_closed, Port.close(port)})
      _ -> send(owner, {:managed_record_owner_closed, false})
    end
  end

  test "actual stale generation and immutable operation identity bypass the normalizer callback",
       c do
    opts = options(1, 0)
    first_scope = scope(c)
    assert {:ok, first} = publish(c, opts, first_scope, first: true)
    root_sha = first.root_sha
    conflict_scope = scope(c, false)

    assert {:conflict, _} =
             Identity.with_domain_publication(
               c.home,
               c.cwd,
               c.binding,
               conflict_scope,
               fn _ -> :ok end,
               fn _cap, _catalog ->
                 C.execute_managed_v3(
                   c.root,
                   c.namespace,
                   options(2, 0).request,
                   conflict_scope.operation_id,
                   JSON.digest([opts.recipe]),
                   fn _, _ -> flunk("CAS conflict entered callback") end
                 )
               end
             )

    assert {:existing, _} =
             Identity.with_domain_publication(
               c.home,
               c.cwd,
               c.binding,
               %{first_scope | initialize: false},
               fn _ -> :ok end,
               fn _cap, _catalog ->
                 C.execute_managed_v3(
                   c.root,
                   c.namespace,
                   opts.request,
                   first_scope.operation_id,
                   JSON.digest([opts.recipe]),
                   fn _, _ -> flunk("immutable ID replay entered callback") end
                 )
               end
             )

    assert snapshot(c, [ManagedPages.format_key()])["witness"]["root_sha256"] == root_sha
  end

  test "an active namespace cannot reset metadata against an actually absent other store", c do
    assert {:ok, first} = publish(c, options(1, 0), scope(c), first: true)
    other = %{c | root: c.base <> "/other-collections"}

    assert {:error, :managed_normalization_refused} =
             publish(other, options(2, 0), scope(c, false))

    result = snapshot(other, [ManagedPages.format_key()])
    assert result["witness"]["root_state"] == "absent"
    assert result["records"] == [nil]
    assert entry(c)["state"] == "active"
    assert snapshot(c, [ManagedPages.format_key()])["witness"]["root_sha256"] == first.root_sha
  end

  test "actual present missing format and unsigned V2 pages cannot acquire V3 authority", c do
    assert {:ok, _} = publish(c, options(1, 0), scope(c), first: true)
    other = %{c | root: c.base <> "/unsigned-collections"}

    unsigned = %{
      "key" => "host.validity.anchor.00.0",
      "expected_revision" => 0,
      "value" => %{
        "version" => 2,
        "kind" => "anchor",
        "shard" => "00",
        "page" => 0,
        "entries" => %{}
      }
    }

    assert {:ok, _} =
             C.execute(
               other.root,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [unsigned]
               },
               Ipse.Usage.id()
             )

    before = snapshot(other, [ManagedPages.format_key(), unsigned["key"]])
    assert before["witness"]["root_state"] == "present" and hd(before["records"]) == nil

    assert {:error, :managed_normalization_refused} =
             publish(other, options(2, 1), scope(c, false))

    after_result = snapshot(other, [ManagedPages.format_key(), unsigned["key"]])
    assert after_result == before
    assert entry(c)["state"] == "active"
  end

  test "native owner loss after committed verified C result leaves Identity prepared and outcome unknown",
       c do
    first_scope = scope(c)
    assert {:unknown, _} = publish(c, options(1, 0), first_scope, first: true, lose_owner: true)
    assert entry(c)["state"] == "prepared"
    result = snapshot(c, [ManagedPages.format_key()])
    assert result["summary"]["generation"] == 1
    assert hd(result["records"])["operation_id"] == first_scope.operation_id

    assert {:ok, inspect_result} =
             C.execute(
               c.root,
               c.namespace,
               %{"op" => "inspect", "operation_id" => first_scope.operation_id},
               Ipse.Usage.id()
             )

    assert inspect_result["operation"]["generation"] == 1
    assert {:ok, c.binding} == Identity.existing(c.home, c.cwd)

    assert {:error, _} =
             Identity.with_domain_publication(
               c.home,
               c.cwd,
               c.binding,
               scope(c, false),
               fn _ -> :ok end,
               fn _, _ -> flunk("prepared unknown auto-replayed/reconciled") end
             )

    assert entry(c)["state"] == "prepared"

    assert snapshot(c, [ManagedPages.format_key()])["witness"]["root_sha256"] ==
             result["witness"]["root_sha256"]
  end

  defp relocated_field(opts, field) do
    [change] = opts.request["changes"]
    replacement = "selected_" <> field
    value = change["value"] |> Map.put(replacement, change["value"][field]) |> Map.delete(field)
    schema = opts.constraints["value_schema"]

    properties =
      schema["properties"]
      |> Map.put(replacement, schema["properties"][field])
      |> Map.delete(field)

    required =
      schema["required"] |> Enum.map(&if(&1 == field, do: replacement, else: &1)) |> Enum.sort()

    constraints =
      put_in(opts.constraints, ["value_schema"], %{
        schema
        | "properties" => properties,
          "required" => required
      })

    recipe =
      opts.recipe
      |> Map.put(field <> "_path", [replacement])
      |> Map.put("constraints_sha256", JSON.digest([constraints]))

    request = put_in(opts.request, ["changes"], [%{change | "value" => value}])
    {%{opts | request: request, constraints: constraints, recipe: recipe}, value}
  end

  defp relocated_evidence(opts) do
    [change] = opts.request["changes"]
    evidence = change["value"]["evidence"]
    value = change["value"] |> Map.delete("evidence") |> Map.put("citation", evidence)
    schema = opts.constraints["value_schema"]

    properties =
      schema["properties"]
      |> Map.delete("evidence")
      |> Map.put("citation", schema["properties"]["evidence"])

    required =
      schema["required"]
      |> Enum.map(&if(&1 == "evidence", do: "citation", else: &1))
      |> Enum.sort()

    schema = %{schema | "properties" => properties, "required" => required}

    constraints = %{
      opts.constraints
      | "value_schema" => schema,
        "evidence_path" => ["citation", "sources"]
    }

    recipe = %{
      opts.recipe
      | "evidence_path" => ["citation", "sources"],
        "constraints_sha256" => JSON.digest([constraints])
    }

    request = put_in(opts.request, ["changes"], [%{change | "value" => value}])
    {%{opts | request: request, constraints: constraints, recipe: recipe}, value}
  end

  def options(n, generation, kind \\ "literal_source", category \\ "ordinary") do
    opts = F.options(kind, category, 86_400_000)

    source =
      F.proof(category)
      |> Map.put(
        "occurrence_id",
        Integer.to_string(n, 16) |> String.downcase() |> String.pad_leading(32, "0")
      )
      |> Map.put("receipt_sha256", F.hash("actual C synthetic source #{n}"))

    text = if kind == "proposal", do: "Acme may appoint Alex", else: source["quote"]

    {:ok, key, value} =
      Records.capture(
        %{
          "text" => text,
          "category" => category,
          "reason" => "trusted fixture source",
          "event_at_ms" => nil
        },
        source,
        10 * 86_400_000
      )

    %{
      opts
      | request: %{
          "op" => "commit",
          "expected_generation" => generation,
          "advance_floor" => true,
          "changes" => [%{"key" => key, "expected_revision" => 0, "value" => value}]
        },
        verified_sources: [source]
    }
  end

  defp scope(c, initialize \\ true),
    do: %{
      namespace: c.namespace,
      format: "managed-metadata-v3",
      operation_id: Ipse.Usage.id(),
      initialize: initialize
    }

  def publish(c, opts, scope, flags \\ []) do
    authorize = fn _binding ->
      if flags[:first] do
        absent = snapshot(c, [ManagedPages.format_key()])
        assert absent["witness"]["root_state"] == "absent"
        assert absent["witness"]["root"] == nil and absent["records"] == [nil]
      end

      :ok
    end

    Identity.with_domain_publication(c.home, c.cwd, c.binding, scope, authorize, fn cap,
                                                                                    catalog ->
      result =
        C.execute_managed_v3(
          c.root,
          c.namespace,
          opts.request,
          scope.operation_id,
          JSON.digest([opts.recipe]),
          fn witness, read ->
            outcome =
              NormalizerV3.normalize(
                witness,
                read,
                Map.merge(opts, %{domain_cap: cap, catalog: catalog})
              )

            {_, units, _} = Process.get({C, :managed_read})
            Process.put(:actual_v3_read_units, units)
            outcome
          end
        )

      case result do
        {:ok, core} ->
          verified = verify_publication(c, opts, scope, cap, core)

          value =
            Map.merge(verified, %{core: core, read_units: Process.get(:actual_v3_read_units)})

          if flags[:lose_owner] do
            controller = Process.get({Ipse.Runner.Transaction, :controller})
            assert is_pid(controller)
            monitor = Process.monitor(controller)
            Process.exit(controller, :kill)
            assert_receive {:DOWN, ^monitor, :process, ^controller, _}, 2000
          end

          if catalog["state"] == "prepared" do
            witness = %{
              version: 1,
              namespace: scope.namespace,
              format: scope.format,
              fence_id: catalog["fence_id"],
              operation_id: scope.operation_id,
              root_sha256: value.root_sha
            }

            {:first_publication, witness, value}
          else
            {:ok, value}
          end

        other ->
          other
      end
    end)
  end

  defp verify_publication(c, opts, scope, cap, core) do
    receipt = core["receipt"]
    normalization = core["normalization"]
    key = hd(opts.request["changes"])["key"]

    keys =
      Enum.uniq(
        [ManagedPages.format_key(), key] ++
          Enum.map(normalization["metadata_changes"], & &1["key"])
      )

    assert length(keys) <= 8
    {:ok, view} = C.open_view(c.root, c.namespace)

    try do
      {:ok, result} = C.view_read(view, %{"op" => "get_many", "keys" => keys})
      assert result["witness"]["root_state"] == "present"
      assert result["summary"]["generation"] == receipt["generation"]
      assert result["summary"]["floor"] == receipt["floor"]
      assert result["witness"]["root"]["generation"] == receipt["generation"]
      assert result["witness"]["root"]["manifest"] == result["witness"]["manifest_sha256"]
      assert receipt["generation"] == opts.request["expected_generation"] + 1
      records = Map.new(Enum.zip(keys, result["records"]))

      extras =
        Enum.map(normalization["metadata_changes"], fn change ->
          stored = records[change["key"]]

          %{
            "key" => change["key"],
            "expected_revision" => change["expected_revision"],
            "value" => if(stored, do: stored["value"])
          }
        end)

      normalized = Map.update!(opts.request, "changes", &(&1 ++ extras))
      assert receipt["request_sha256"] == JSON.digest([normalized])
      assert core["binding"]["original_request_sha256"] == JSON.digest([opts.request])
      assert core["binding"]["normalization_sha256"] == JSON.digest([normalization])
      assert core["binding"]["recipe_sha256"] == JSON.digest([opts.recipe])
      assert receipt["managed_binding_sha256"] == JSON.digest([core["binding"]])
      record = records[key]
      assert record["value"] == hd(opts.request["changes"])["value"]

      assert record["revision"] == receipt["generation"] and
               record["operation_id"] == scope.operation_id

      assert record["sha256"] == JSON.sha256(Migration.encode(record["value"]))
      assert {:ok, _} = ManagedPages.open_format(cap, records[ManagedPages.format_key()])
      assert normalization["format_value_sha256"] == records[ManagedPages.format_key()]["sha256"]

      Enum.each(normalization["metadata_changes"], fn change ->
        current = records[change["key"]]

        if is_nil(change["value_sha256"]) do
          assert current == nil and change["expected_revision"] > 0
        else
          assert current["revision"] == receipt["generation"] and
                   current["operation_id"] == scope.operation_id

          assert current["sha256"] == change["value_sha256"]

          if current["key"] != ManagedPages.format_key(),
            do: checked_page(view, cap, current, result)
        end
      end)

      live_id = ManagedPages.live_identity(key)

      {:ok, neighbors} =
        C.view_neighbors(view, %{
          "version" => 1,
          "prefix" => ManagedPages.prefix(:live),
          "fence_bytes" => 33,
          "needle" => live_id
        })

      live_key = neighbors["neighbors"]["selected"]["key"]
      {:ok, selected} = C.view_read(view, %{"op" => "get_many", "keys" => [live_key]})
      assert selected["witness"] == result["witness"]
      [live_record] = selected["records"]
      assert {:ok, page} = ManagedPages.open(cap, live_record, neighbors)

      [lineage, value, recipe, policy, first, deadline, category, eligibility] =
        page.entries[live_id]

      assert lineage == packed(normalization["lineage"]) and value == packed(record["sha256"])
      assert recipe == packed(JSON.digest([opts.recipe])) and policy == packed(opts.policy_sha256)
      assert String.to_integer(first, 36) == normalization["first_admitted_ms"]
      assert if(deadline, do: String.to_integer(deadline, 36)) == normalization["valid_until_ms"]

      assert category ==
               %{"ordinary" => 0, "preference" => 1, "current" => 2}[normalization["category"]]

      assert eligibility == if(normalization["eligibility"] == "current", do: 0, else: 1)

      %{
        format: records[ManagedPages.format_key()],
        root_sha: result["witness"]["root_sha256"],
        live_revision: live_record["revision"]
      }
    after
      assert :ok = C.close_view(view)
    end
  end

  defp checked_page(view, cap, record, snapshot) do
    kind =
      if String.starts_with?(record["key"], ManagedPages.prefix(:anchor)),
        do: :anchor,
        else: :live

    fence = String.replace_prefix(record["key"], ManagedPages.prefix(kind), "")

    {:ok, neighbors} =
      C.view_neighbors(view, %{
        "version" => 1,
        "prefix" => ManagedPages.prefix(kind),
        "fence_bytes" => ManagedPages.width(kind),
        "needle" => fence
      })

    assert neighbors["witness"] == snapshot["witness"]
    assert {:ok, _} = ManagedPages.open(cap, record, neighbors)
  end

  defp snapshot(c, keys) do
    {:ok, view} = C.open_view(c.root, c.namespace)

    try do
      {:ok, result} = C.view_read(view, %{"op" => "get_many", "keys" => keys})
      result
    after
      assert :ok = C.close_view(view)
    end
  end

  defp packed(hash), do: Base.url_encode64(Base.decode16!(hash, case: :lower), padding: false)

  defp entry(c) do
    state = (c.home <> "/project-identities/index.json") |> File.read!() |> Jason.decode!()
    state["domain_keys"][c.binding["project_id"]]["namespaces"][c.namespace]
  end
end
