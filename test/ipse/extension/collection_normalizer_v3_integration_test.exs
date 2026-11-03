unless Code.ensure_loaded?(Ipse.Test.NormalizerV3Fixture) do
  Code.require_file("collection_normalizer_v3_test.exs", __DIR__)
end

defmodule Ipse.Extension.CollectionNormalizerV3IntegrationTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.Collection, as: C
  alias Ipse.Extension.Collection.{ManagedPages, Migration, NormalizerV3, ObservedRead}
  alias Ipse.Extension.ManagedRecipe
  alias Ipse.Extension.ProjectIdentity, as: Identity
  alias Ipse.Session.ManagedReference
  alias Ipse.Test.NormalizerV3Fixture, as: F
  alias IpseKnowledge.Knowledge.Records
  alias Ipse.{JSON, Runner, Usage}
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

  test "accepted records cannot leave a managed read as root-only data", c do
    root = Ipse.Extension.SemanticAdmission.collection_root(c.home)
    key = "note." <> JSON.sha256("accepted read control")
    value = %{"kind" => "accepted_decision", "text" => "private synthetic decision"}

    assert {:ok, _} =
             C.execute(
               root,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => true,
                 "changes" => [%{"key" => key, "expected_revision" => 0, "value" => value}]
               },
               Ipse.Usage.id()
             )

    context = %{config: %{home: c.home}}

    intent = %{
      "namespace" => c.namespace,
      "request" => %{"request" => %{"op" => "get", "key" => key}}
    }

    for recipe <- [options(1, 0, "proposal").recipe, options(1, 0).recipe] do
      assert {:error, :collection_source_refused} =
               Ipse.Extension.ManagedRead.execute(
                 context,
                 intent,
                 [recipe],
                 fn false, fun -> fun.(nil, nil) end,
                 fn _, _ -> flunk("accepted data reached read admission") end
               )
    end
  end

  test "native absence initializes then actual active literal/proposal publications retain MAC provenance",
       c do
    assert {:ok, first} = publish(c, options(1, 0), scope(c), first: true)
    assert first.read_units == 11
    assert length(first.core["normalization"]["metadata_changes"]) == 3
    assert entry(c)["state"] == "active"
    first_format = first.format
    assert first_format["revision"] == 1

    assert {:ok, second} =
             publish(c, options(2, 1, "literal_source", "preference"), scope(c, false))

    assert second.read_units == 13
    assert second.format == first_format
    assert second.core["normalization"]["valid_until_ms"] == nil
    assert {:ok, third} = publish(c, options(3, 2, "proposal"), scope(c, false))
    assert third.format == first_format
    assert third.core["normalization"]["eligibility"] == "never_current"
    assert third.core["receipt"]["generation"] == 3
    assert third.live_revision == 3 and second.live_revision == 2
  end

  test "held acceptance publication refuses forged inputs and spends the same-owner attempt", c do
    assert {:ok, _} = publish(c, options(1, 0), scope(c), first: true)
    before = snapshot(c, [ManagedPages.format_key()])

    assert {:ok, :checked} =
             C.with_notes_publication_deadline(System.system_time(:millisecond) + 60_000, fn ->
               C.with_managed_acceptance_read(c.root, c.namespace, fn _witness,
                                                                      _read,
                                                                      alive,
                                                                      publish ->
                 assert :ok = alive.()

                 assert {:error, :pending_acceptance_refused} =
                          Task.async(fn -> publish.(%{}, %{}, %{}, %{}) end) |> Task.await()

                 assert {:error, :pending_acceptance_refused} = publish.(%{}, %{}, %{}, %{})
                 assert {:error, :pending_acceptance_refused} = publish.(%{}, %{}, %{}, %{})
                 {:ok, :checked}
               end)
             end)

    assert snapshot(c, [ManagedPages.format_key()]) == before
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

  @tag :held_target_regression
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

  @tag :held_pending_proposal
  test "retained pending observation preserves signed metadata and exact original source", c do
    test_owner = self()
    opts = options(1, 0, "proposal")
    assert {:ok, publication} = publish(c, opts, scope(c), first: true)
    key = hd(opts.request["changes"])["key"]
    request = %{"op" => "get_record", "key" => key}
    domain = Map.take(scope(c, false), [:namespace, :format])

    assert {:ok, prior} =
             Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                     catalog ->
               ObservedRead.managed_proposal(
                 c.root,
                 c.namespace,
                 request,
                 cap,
                 catalog,
                 opts.recipe
               )
             end)

    assert {:ok, ^prior} =
             Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                     catalog ->
               ObservedRead.with_managed_proposal_plan(
                 c.root,
                 c.namespace,
                 request,
                 cap,
                 catalog,
                 opts.recipe,
                 fn observed, held_read ->
                   assert Process.get({C, :lock_held}) != nil
                   assert observed === prior
                   record = observed["observation"]["value"]["record"]
                   assert record["key"] === key and record["revision"] === 1
                   assert record["value"]["evidence"]["sources"] === opts.verified_sources

                   assert observed["metadata"]["valid_until_ms"] ===
                            publication.core["normalization"]["valid_until_ms"]

                   assert observed["metadata"]["eligibility"] === "never_current"

                   context = %{
                     "operation_id" => Ipse.Usage.id(),
                     "journal_id" => Ipse.Usage.id(),
                     "client_id" => Ipse.Usage.id(),
                     "session_id" => nil,
                     "project_id" => c.binding["project_id"],
                     "namespace" => c.namespace,
                     "binding_sha256" => JSON.sha256("binding"),
                     "policy_sha256" => JSON.sha256("active-policy"),
                     "capture_epoch" => 1,
                     "render_revision" => 1,
                     "recipe" => opts.recipe
                   }

                   now = observed["metadata"]["first_admitted_ms"] + 1

                   assert {:ok, facts} =
                            Ipse.Session.PendingAcceptance.prepare(
                              context,
                              observed,
                              opts.verified_sources,
                              now
                            )

                   assert facts["source_proof"] === hd(opts.verified_sources)

                   assert facts["pending_key"] === key and
                            facts["record_revision"] === record["revision"]

                   assert facts["record_sha256"] === record["sha256"]
                   assert facts["valid_until_ms"] === observed["metadata"]["valid_until_ms"]
                   assert facts["session_id"] === nil

                   # A structural fixture is deliberately not a native permit.
                   challenge = "0123456789abcdef"

                   event = %{
                     "type" => "pending_proposal_accepted",
                     "version" => 1,
                     "facts" => facts,
                     "review" => %{
                       "version" => 1,
                       "kind" => "native_review",
                       "command" => "accept",
                       "event_id" => Ipse.Usage.id(),
                       "display_sha256" => JSON.sha256("synthetic display"),
                       "challenge" => challenge,
                       "input_sha256" => JSON.sha256("accept " <> challenge),
                       "observed_at_ms" => now,
                       "facts_sha256" => JSON.digest([facts])
                     }
                   }

                   assert Ipse.Session.PendingAcceptance.valid_event?(event)
                   journal_id = facts["journal_id"]

                   header = %{
                     "type" => "session",
                     "metadata" => %{
                       "kind" => "knowledge_management",
                       "project_id" => facts["project_id"],
                       "namespace" => facts["namespace"],
                       "pending_acceptance_layout" => Ipse.Session.PendingAcceptance.layout()
                     }
                   }

                   assert :ok =
                            Ipse.Session.PendingAcceptance.validate_events(
                              [header, event],
                              journal_id
                            )

                   for invalid <- [
                         [header, event, event],
                         [put_in(header, ["metadata", "namespace"], JSON.sha256("wrong")), event],
                         [
                           put_in(header, ["metadata", "pending_acceptance_layout"], "unknown"),
                           event
                         ],
                         [put_in(header, ["metadata", "pending_acceptance_layout"], nil), event],
                         [header, put_in(event, ["facts", "text"], "changed")]
                       ] do
                     assert {:error, :pending_acceptance_refused} =
                              Ipse.Session.PendingAcceptance.validate_events(invalid, journal_id)
                   end

                   other_text = "A different synthetic candidate"
                   {:ok, other_id} = ManagedRecipe.proposal_identity(facts["lineage"], other_text)

                   other_facts =
                     facts
                     |> Map.put("candidate_id", other_id)
                     |> Map.put("pending_key", "pending." <> other_id)
                     |> Map.put("text", other_text)
                     |> Map.put("text_sha256", JSON.sha256(other_text))
                     |> Map.put("operation_id", Ipse.Usage.id())

                   other_event =
                     event
                     |> Map.put("facts", other_facts)
                     |> put_in(["review", "facts_sha256"], JSON.digest([other_facts]))
                     |> put_in(["review", "event_id"], Ipse.Usage.id())
                     |> put_in(["review", "observed_at_ms"], now + 1)

                   assert :ok =
                            Ipse.Session.PendingAcceptance.validate_events(
                              [header, event, other_event],
                              journal_id
                            )

                   reused_operation_facts =
                     Map.put(other_facts, "operation_id", facts["operation_id"])

                   reused_operation =
                     other_event
                     |> Map.put("facts", reused_operation_facts)
                     |> put_in(["review", "facts_sha256"], JSON.digest([reused_operation_facts]))

                   repeated_candidate_facts = Map.put(facts, "operation_id", Ipse.Usage.id())

                   repeated_candidate =
                     event
                     |> Map.put("facts", repeated_candidate_facts)
                     |> put_in(
                       ["review", "facts_sha256"],
                       JSON.digest([repeated_candidate_facts])
                     )
                     |> put_in(["review", "event_id"], Ipse.Usage.id())

                   for invalid <- [
                         put_in(other_event, ["review", "event_id"], event["review"]["event_id"]),
                         put_in(other_event, ["review", "observed_at_ms"], now - 1),
                         reused_operation,
                         repeated_candidate
                       ] do
                     assert {:error, :pending_acceptance_refused} =
                              Ipse.Session.PendingAcceptance.validate_events(
                                [header, event, invalid],
                                journal_id
                              )
                   end

                   send(test_owner, {:synthetic_pending_event, event, now})
                   deadline = now + 90 * 86_400_000

                   assert {:ok, values} =
                            Ipse.Session.PendingAcceptance.accepted_values(event, deadline)

                   note_recipe = IpseKnowledge.Knowledge.Contracts.recipe("note")

                   assert {:ok, fresh_retention} =
                            Ipse.Session.PendingAcceptance.retention_plan(
                              event,
                              note_recipe,
                              nil,
                              nil,
                              now
                            )

                   assert fresh_retention["values"] === values
                   assert fresh_retention["anchor"]["clocks"] === [now, deadline, nil, nil]

                   prior = %{
                     "clocks" => [now - 100, now + 500, now - 200, now + 200],
                     "choice" => nil,
                     "retirement" => nil
                   }

                   assert {:ok, preserved} =
                            Ipse.Session.PendingAcceptance.retention_plan(
                              event,
                              note_recipe,
                              prior,
                              now + 250,
                              now
                            )

                   assert preserved["first_admitted_ms"] === now - 100
                   assert preserved["valid_until_ms"] === now + 250
                   assert preserved["anchor"]["clocks"] === prior["clocks"]
                   assert preserved["values"]["note"]["valid_until_ms"] === now + 250

                   pending_only = %{
                     "clocks" => [nil, nil, now - 200, now + 200],
                     "choice" => nil,
                     "retirement" => nil
                   }

                   assert {:ok, pending_preserved} =
                            Ipse.Session.PendingAcceptance.retention_plan(
                              event,
                              note_recipe,
                              pending_only,
                              nil,
                              now
                            )

                   assert pending_preserved["anchor"]["clocks"] === [
                            now,
                            deadline,
                            now - 200,
                            now + 200
                          ]

                   for suppressed <- [
                         %{prior | "choice" => %{"kind" => "suppressed"}},
                         %{prior | "retirement" => %{"kind" => "retired"}},
                         %{prior | "clocks" => [now - 100, now - 1, nil, nil]},
                         %{prior | "clocks" => [now + 1, now + 500, nil, nil]}
                       ] do
                     assert {:error, :pending_acceptance_refused} =
                              Ipse.Session.PendingAcceptance.retention_plan(
                                event,
                                note_recipe,
                                suppressed,
                                nil,
                                now
                              )
                   end

                   assert {:error, :pending_acceptance_refused} =
                            Ipse.Session.PendingAcceptance.retention_plan(
                              event,
                              note_recipe,
                              prior,
                              now,
                              now
                            )

                   expected_lineage =
                     JSON.digest([
                       "ipse-knowledge",
                       1,
                       "accepted_decision",
                       facts["candidate_id"],
                       facts["lineage"]
                     ])

                   assert values["note_key"] == "note." <> expected_lineage
                   assert values["link_key"] == "accept." <> facts["candidate_id"]
                   assert values["note"]["source_proof"] === hd(opts.verified_sources)
                   assert values["link"]["pending_revision"] === record["revision"]
                   assert values["link"]["pending_value_sha256"] === record["sha256"]
                   assert values["link"]["acceptance_event_sha256"] === JSON.digest([event])

                   assert values["note"]["acceptance_link_sha256"] ===
                            JSON.sha256(Migration.encode(values["link"]))

                   assert values["note_sha256"] === JSON.sha256(Migration.encode(values["note"]))
                   assert Ipse.Session.PendingAcceptance.valid_accepted_values?(event, values)

                   # The two destination checks use the same retained root.
                   absent = held_read

                   assert {:error, :managed_read_refused} =
                            Task.async(fn -> held_read.(values["note_key"]) end) |> Task.await()

                   assert {:ok, public_plan} =
                            Ipse.Session.PendingAcceptance.public_plan(
                              event,
                              values,
                              observed,
                              now,
                              absent
                            )

                   assert public_plan["request"]["changes"] == [
                            %{
                              "key" => key,
                              "expected_revision" => record["revision"],
                              "value" => nil
                            },
                            %{
                              "key" => values["note_key"],
                              "expected_revision" => 0,
                              "value" => values["note"]
                            },
                            %{
                              "key" => values["link_key"],
                              "expected_revision" => 0,
                              "value" => values["link"]
                            }
                          ]

                   assert public_plan["request_sha256"] === JSON.digest([public_plan["request"]])

                   assert public_plan["root_sha256"] ===
                            observed["observation"]["witness"]["root_sha256"]

                   # Provisional row solely measures page geometry. It is not
                   # an accepted-decision recipe or an authorization to publish.
                   accepted_lineage = values["note"]["lineage"]

                   pack_hash = fn hash ->
                     Base.url_encode64(Base.decode16!(hash, case: :lower), padding: false)
                   end

                   accepted_anchor = %{
                     "clocks" => [now, deadline, nil, nil],
                     "choice" => nil,
                     "retirement" => nil
                   }

                   accepted_live =
                     Enum.map(
                       [
                         accepted_lineage,
                         values["note_sha256"],
                         facts["recipe_sha256"],
                         facts["policy_sha256"]
                       ],
                       pack_hash
                     ) ++
                       [
                         String.downcase(Integer.to_string(now, 36)),
                         String.downcase(Integer.to_string(deadline, 36)),
                         0,
                         0
                       ]

                   assert {:ok, anchor_plan} =
                            ManagedPages.Planner.plan(
                              cap,
                              :anchor,
                              [{accepted_lineage, accepted_anchor}],
                              held_read
                            )

                   assert {:ok, live_plan} =
                            ManagedPages.Planner.plan(
                              cap,
                              :live,
                              [
                                {ManagedPages.live_identity(key), nil},
                                {ManagedPages.live_identity(values["note_key"]), accepted_live}
                              ],
                              held_read
                            )

                   assert anchor_plan.witness["root_sha256"] == facts["root_sha256"]
                   assert live_plan.witness["root_sha256"] == facts["root_sha256"]
                   sidecars = anchor_plan.changes ++ live_plan.changes
                   assert length(sidecars) <= 5
                   assert Enum.count(sidecars, &is_nil(&1.body)) <= 1
                   assert Enum.count(sidecars, &(not is_nil(&1.body))) <= 4

                   {_, read_units, _} = Process.get({C, :managed_read})
                   assert read_units <= 32

                   IO.puts(
                     "PENDING_GEOMETRY reads=#{read_units} anchor_changes=#{length(anchor_plan.changes)} live_changes=#{length(live_plan.changes)} " <>
                       "bodies=#{inspect(Enum.map(sidecars, &if(&1.body, do: ManagedPages.encoded_size(&1.body), else: nil)))}"
                   )

                   assert {:error, :pending_acceptance_refused} =
                            Ipse.Session.PendingAcceptance.public_plan(
                              event,
                              values,
                              observed,
                              now,
                              fn _ -> {:ok, %{}} end
                            )

                   assert {:error, :pending_acceptance_refused} =
                            Ipse.Session.PendingAcceptance.public_plan(
                              event,
                              values,
                              put_in(
                                observed,
                                ["observation", "witness", "root_sha256"],
                                JSON.sha256("changed root")
                              ),
                              now,
                              absent
                            )

                   assert {:error, :pending_acceptance_refused} =
                            Ipse.Session.PendingAcceptance.public_plan(
                              event,
                              values,
                              observed,
                              facts["valid_until_ms"],
                              absent
                            )

                   refute Ipse.Session.PendingAcceptance.valid_accepted_values?(
                            event,
                            Map.put(values, "permission", "forged")
                          )

                   refute Ipse.Session.PendingAcceptance.valid_accepted_values?(
                            event,
                            put_in(values, ["link", "pending_revision"], record["revision"] + 1)
                          )

                   refute Ipse.Session.PendingAcceptance.valid_accepted_values?(
                            event,
                            put_in(
                              values,
                              ["note", "source_proof", "origin"],
                              "interactive_operator"
                            )
                          )

                   assert {:error, :pending_acceptance_refused} =
                            Ipse.Session.PendingAcceptance.accepted_values(event, now)

                   assert {:error, :pending_acceptance_refused} =
                            Ipse.Session.PendingAcceptance.accepted_values(event, nil)

                   preference_facts = Map.put(facts, "assigned_category", "preference")

                   preference_event =
                     event
                     |> Map.put("facts", preference_facts)
                     |> put_in(["review", "facts_sha256"], JSON.digest([preference_facts]))

                   assert {:ok, preference_values} =
                            Ipse.Session.PendingAcceptance.accepted_values(preference_event, nil)

                   assert preference_values["note"]["valid_until_ms"] == nil

                   assert {:ok, preference_retention} =
                            Ipse.Session.PendingAcceptance.retention_plan(
                              preference_event,
                              note_recipe,
                              nil,
                              nil,
                              now
                            )

                   assert preference_retention["values"] === preference_values
                   assert preference_retention["anchor"]["clocks"] === [now, nil, nil, nil]

                   assert Ipse.Session.PendingAcceptance.valid_accepted_values?(
                            preference_event,
                            preference_values
                          )

                   assert {:error, :pending_acceptance_refused} =
                            Ipse.Session.PendingAcceptance.accepted_values(
                              put_in(event, ["facts", "text"], "changed"),
                              deadline
                            )

                   later_event = put_in(event, ["review", "event_id"], Ipse.Usage.id())

                   assert {:ok, later_values} =
                            Ipse.Session.PendingAcceptance.accepted_values(later_event, deadline)

                   assert later_values["note_key"] == values["note_key"]
                   assert later_values["link_key"] == values["link_key"]
                   refute later_values["link_sha256"] == values["link_sha256"]

                   wide_text = String.duplicate("\"", 2048)
                   {:ok, wide_id} = ManagedRecipe.proposal_identity(facts["lineage"], wide_text)

                   wide_facts =
                     facts
                     |> Map.put("text", wide_text)
                     |> Map.put("text_sha256", JSON.sha256(wide_text))
                     |> Map.put("candidate_id", wide_id)
                     |> Map.put("pending_key", "pending." <> wide_id)
                     |> Map.put("reason", String.duplicate(<<1>>, 256))

                   wide_event =
                     event
                     |> Map.put("facts", wide_facts)
                     |> put_in(["review", "facts_sha256"], JSON.digest([wide_facts]))

                   assert Ipse.Session.PendingAcceptance.valid_event?(wide_event)

                   assert {:error, :pending_acceptance_refused} =
                            Ipse.Session.PendingAcceptance.accepted_values(wide_event, deadline)

                   assert {:error, :pending_acceptance_refused} =
                            Ipse.Session.PendingAcceptance.prepare(
                              context,
                              observed,
                              opts.verified_sources,
                              facts["valid_until_ms"]
                            )

                   assert {:error, :pending_acceptance_refused} =
                            Ipse.Session.PendingAcceptance.prepare(context, observed, [], now)

                   assert {:error, :pending_acceptance_refused} =
                            Ipse.Session.PendingAcceptance.consume(nil, facts, now)

                   {:ok, observed}
                 end
               )
             end)

    assert_receive {:synthetic_pending_event, event, now}

    assert {:ok, :prepared} =
             Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                     catalog ->
               ObservedRead.with_managed_proposal_plan(
                 c.root,
                 c.namespace,
                 request,
                 cap,
                 catalog,
                 opts.recipe,
                 fn observed, read ->
                   recipe = IpseKnowledge.Knowledge.Contracts.recipe("note")

                   assert {:ok, prepared} =
                            Ipse.Session.PendingAcceptance.prepare_storage(
                              event,
                              recipe,
                              nil,
                              observed,
                              cap,
                              now,
                              read
                            )

                   assert prepared["prior_anchor"] === nil
                   retention = prepared["retention"]
                   assert retention["anchor"]["clocks"] === [now, now + 90 * 86_400_000, nil, nil]

                   assert {:error, :pending_acceptance_refused} =
                            Ipse.Session.PendingAcceptance.with_sidecar_plan(
                              event,
                              prepared,
                              cap,
                              read,
                              fn _, _ ->
                                flunk("verify-only Identity capability reached signing")
                              end
                            )

                   assert {:ok, sidecars} =
                            Ipse.Session.PendingAcceptance.plan_sidecars(
                              event,
                              prepared,
                              cap,
                              read
                            )

                   assert length(sidecars.anchor.changes) + length(sidecars.live.changes) <= 5
                   assert [%{key: live_key, body: live_body}] = sidecars.live.changes
                   fence = String.replace_prefix(live_key, ManagedPages.prefix(:live), "")

                   assert {:ok, %{entries: live_entries}} =
                            ManagedPages.unpack(:live, fence, live_body)

                   pending_identity = ManagedPages.live_identity(key)
                   accepted_identity = ManagedPages.live_identity(retention["values"]["note_key"])
                   refute Map.has_key?(live_entries, pending_identity)
                   assert [_, _, _, _, _, _, 0, 3] = live_entries[accepted_identity]

                   {_, units, :open} = Process.get({C, :managed_read})
                   assert units <= 32
                   {:ok, :prepared}
                 end
               )
             end)

    assert {:error, :collection_observation_refused} =
             Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                     catalog ->
               ObservedRead.with_managed_proposal(
                 c.root,
                 c.namespace,
                 request,
                 cap,
                 catalog,
                 Map.put(opts.recipe, "override_prefix", "foreign."),
                 fn _ -> flunk("substituted recipe reached held callback") end
               )
             end)
  end

  @tag :pending_native_review
  @tag timeout: 180_000
  test "a retained pending card uses a real one-use accept input after locks are released", c do
    {:ok, namespace} =
      Ipse.Extension.SemanticConsent.namespace(c.binding["project_id"], "knowledge")

    c = %{
      c
      | namespace: namespace,
        root: Ipse.Extension.SemanticAdmission.collection_root(c.home)
    }

    assert {:ok, _} = Ipse.Extension.Bundles.install("knowledge", c.home)
    assert {:ok, bundles} = Ipse.Extension.Bundles.inventory()
    %{digest: installed_digest} = Enum.find(bundles, &(&1.id == "knowledge"))

    assert {:ok, sidecar_bytes} =
             Ipse.Extension.Artifact.read_declared(
               Path.join(c.home, "extensions/artifacts"),
               installed_digest,
               "operator.json",
               65_536
             )

    assert {:ok, sidecar} = JSON.decode_unique(sidecar_bytes)

    now = System.system_time(:millisecond)
    {proof, source_admission, history_dir} = acceptance_source_fixture(c)

    group_source =
      if System.get_env("IPSE_TEST_GROUP_REVIEW") == "1" do
        {other, _, ^history_dir} = acceptance_source_fixture(c, history_dir)
        other
      end

    base_opts = %{
      options(1, 0, "proposal")
      | recipe: sidecar["recipes"]["pending"],
        constraints: sidecar["publication"]["pending"]
    }

    proposal_text = String.duplicate("P", 1_400) <> "ACCEPTANCE_PRIVATE_TAIL"

    {:ok, proposal_key, proposal_value} =
      Records.capture(
        %{
          "text" => proposal_text,
          "category" => "ordinary",
          "reason" => String.duplicate("R", 256),
          "event_at_ms" => nil
        },
        proof,
        now
      )

    opts = %{
      base_opts
      | now_ms: now,
        verified_sources: [proof],
        request:
          put_in(base_opts.request, ["changes"], [
            %{"key" => proposal_key, "expected_revision" => 0, "value" => proposal_value}
          ])
    }

    assert {:ok, _} = publish(c, opts, scope(c), first: true)
    key = hd(opts.request["changes"])["key"]
    request = %{"op" => "get_record", "key" => key}
    domain = Map.take(scope(c, false), [:namespace, :format])

    context = %{
      "operation_id" => Ipse.Usage.id(),
      "journal_id" => Ipse.Usage.id(),
      "client_id" => Ipse.Usage.id(),
      "session_id" => nil,
      "project_id" => c.binding["project_id"],
      "namespace" => c.namespace,
      "binding_sha256" => c.binding["binding_sha256"],
      "policy_sha256" => JSON.sha256("synthetic active policy"),
      "capture_epoch" => 1,
      "render_revision" => 1,
      "recipe" => opts.recipe
    }

    assert {:ok, {facts, before}} =
             Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                     catalog ->
               ObservedRead.with_managed_proposal(
                 c.root,
                 c.namespace,
                 request,
                 cap,
                 catalog,
                 opts.recipe,
                 fn observed ->
                   assert Process.get({C, :lock_held}) != nil

                   assert {:ok, facts} =
                            Ipse.Session.PendingAcceptance.prepare(
                              context,
                              observed,
                              opts.verified_sources,
                              System.system_time(:millisecond)
                            )

                   {:ok, {facts, observed}}
                 end
               )
             end)

    # This direct Review control does not retain the source or use the
    # owner-held display bridge. The Collection owner is released before input.
    assert Process.get({C, :lock_held}) == nil
    {:ok, review_display, _} = Ipse.Runner.Review.preview_display("accept", facts)

    review_display =
      "Historical pending candidate; current source eligibility requires revalidation before publication.\n" <>
        review_display

    assert byte_size(review_display) > 4096
    assert {tail_offset, _} = :binary.match(review_display, "ACCEPTANCE_PRIVATE_TAIL")
    assert tail_offset >= 4096
    File.write!(Path.join(c.base, "pending-card.json"), Jason.encode!(facts), [:exclusive])
    File.chmod!(Path.join(c.base, "pending-card.json"), 0o600)
    driver = Path.join(c.base, "review-pty")

    assert {"", 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", driver],
               stderr_to_stdout: true
             )

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    for {mode, flag} <- [
          {"cancel", "--review-cancel"},
          {"stale", "--review-stale"},
          {"changed", "--review"},
          {"expired", "--review"},
          {"valid", "--review"}
        ] do
      args =
        [flag, System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [Path.expand("test/support/pending_acceptance_review.exs"), c.base, mode]

      {output, status} = System.cmd(driver, args, stderr_to_stdout: true)
      assert status == 0, output
      assert output =~ "PENDING_NATIVE_REVIEW_#{String.upcase(mode)}_PASSED"
    end

    event = c.base |> Path.join("pending-accept-event.json") |> File.read!() |> Jason.decode!()
    assert Ipse.Session.PendingAcceptance.valid_event?(event)
    assert event["facts"] === facts

    control = Ipse.Extension.SemanticAdmission.control_root(c.home)

    identity =
      Ipse.Test.ManagedPolicy.identity()
      |> Map.put("artifact", installed_digest)
      |> Map.put("artifact_sha256", installed_digest)

    policy =
      Ipse.Test.ManagedPolicy.policy()
      |> Map.put("project", c.binding["project_id"])
      |> Map.put("artifact_sha256", installed_digest)
      |> Map.put("expires_at_ms", System.system_time(:millisecond) + 120_000)
      |> Map.put("headless", false)
      |> put_in(["settings", "namespace"], c.namespace)
      |> put_in(["settings", "storage", "collection"], "knowledge")
      |> put_in(["settings", "activation", "artifact"], installed_digest)
      |> put_in(["settings", "activation", "artifact_sha256"], installed_digest)
      |> put_in(["settings", "constraints"], %{
        JSON.digest([sidecar["publication"]["note"]]) => sidecar["publication"]["note"],
        JSON.digest([sidecar["publication"]["pending"]]) => sidecar["publication"]["pending"]
      })
      |> put_in(["settings", "recipes"], %{
        JSON.digest([sidecar["recipes"]["note"]]) => sidecar["recipes"]["note"],
        JSON.digest([sidecar["recipes"]["pending"]]) => sidecar["recipes"]["pending"]
      })
      |> update_in(["settings", "effects"], fn effects ->
        Enum.map(effects, fn effect ->
          case effect["class"] do
            "collection.publish" ->
              kind = if effect["operation"] == "notes.save", do: "note", else: "pending"

              %{
                effect
                | "recipe_sha256" => JSON.digest([sidecar["recipes"][kind]]),
                  "constraints_sha256" => JSON.digest([sidecar["publication"][kind]])
              }

            "collection.read" ->
              %{
                effect
                | "managed_read" =>
                    Enum.sort([
                      JSON.digest([sidecar["recipes"]["note"]]),
                      JSON.digest([sidecar["recipes"]["pending"]])
                    ])
              }
          end
        end)
      end)
      |> put_in(["settings", "identity_sha256"], JSON.digest([identity]))
      |> put_in(["settings", "routes", Access.at(0), "service_id"], "demo")
      |> put_in(["settings", "activation", "service_refs", Access.at(0), "service_id"], "demo")

    assert Ipse.Extension.SemanticConsent.policy?(policy)

    [note_recipe] =
      policy["settings"]["recipes"]
      |> Map.values()
      |> Enum.filter(&(&1["kind"] == "literal_source"))

    management_snapshot = %{"epoch" => 1, "policy" => policy}
    management_id = Ipse.Usage.id()
    now = System.system_time(:millisecond)

    admission_args = [
      c.home,
      history_dir,
      c.binding,
      management_snapshot,
      management_id,
      policy["artifact_sha256"],
      note_recipe,
      opts.recipe,
      now
    ]

    assert {:ok, management_context} =
             apply(Ipse.Session.PendingAcceptance, :management_source_context, admission_args)

    assert management_context.config.semantic_admission["pin"]["session_id"] === management_id

    assert management_context.config.semantic_admission["pin"]["policy_sha256"] ===
             JSON.digest([policy])

    for changed <- [
          List.replace_at(admission_args, 5, JSON.sha256("other artifact")),
          List.replace_at(admission_args, 6, Map.put(note_recipe, "override_prefix", "other.")),
          List.replace_at(admission_args, 7, Map.put(opts.recipe, "override_prefix", "other.")),
          List.replace_at(admission_args, 8, policy["expires_at_ms"])
        ] do
      assert {:error, :pending_acceptance_refused} =
               apply(Ipse.Session.PendingAcceptance, :management_source_context, changed)
    end

    assert {:ok, %{"epoch" => 1}} =
             Ipse.Extension.Consent.replace(
               control,
               c.binding["project_id"],
               0,
               policy,
               System.system_time(:millisecond)
             )

    File.write!(
      Path.join(c.base, "pending-management.json"),
      Jason.encode!(%{
        "namespace" => c.namespace,
        "collection_root" => c.root,
        "key" => key,
        "recipe" => opts.recipe,
        "note_recipe" => note_recipe,
        "history_dir" => history_dir,
        "group_source" => group_source,
        "sources" => opts.verified_sources
      }),
      [:exclusive]
    )

    managed_modes =
      [
        {"cancel", "--management-review-cancel"},
        {"stale", "--management-review-stale"},
        {"wrong-purpose", "--management-review"},
        {"premature-seal", "--management-review"},
        {"wrong-intent", "--management-review"},
        {"valid", "--management-review"}
      ] ++
        if(System.get_env("IPSE_TEST_GROUP_REVIEW") == "1",
          do: [{"group-valid", "--management-review"}],
          else: []
        )

    for {mode, flag} <- managed_modes do
      managed_args =
        [flag, System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++ [Path.expand("test/support/pending_acceptance_management.exs"), c.base, mode]

      {managed_output, managed_status} = System.cmd(driver, managed_args, stderr_to_stdout: true)
      assert managed_status == 0, managed_output

      assert managed_output =~
               "Historical pending candidate; current source eligibility requires revalidation"

      assert managed_output =~ "PENDING_MANAGEMENT_REVIEW_#{String.upcase(mode)}_PASSED"

      if mode in ~w(valid group-valid) do
        normalized = String.replace(managed_output, "\r\n", "\n")

        assert [_, display] =
                 Regex.run(
                   ~r/((?:Acceptance records your decision, not independent truth or permission for other effects\.\nProposed accepted-decision retention \(null maximum age means no category age limit\):\n\{.*?\}\n)?Historical pending candidate; current source eligibility requires revalidation before publication\.\nReview the complete proposed facts below\. This confirmation applies only to this exact review\.\n\{.*?\}\nType accept [0-9a-f]{16} to confirm, or anything else to cancel\.\n> )/s,
                   normalized
                 )

        if mode == "valid" do
          assert String.starts_with?(display, "Acceptance records your decision,")
          assert display =~ "\"earlier_lineage_limits_apply\": true"
        end

        event_file =
          if mode == "group-valid",
            do: "pending-management-group-event.json",
            else: "pending-management-event.json"

        reviewed = c.base |> Path.join(event_file) |> File.read!() |> Jason.decode!()

        assert reviewed["review"]["display_sha256"] === JSON.sha256(display)
      end
    end

    managed_event =
      c.base |> Path.join("pending-management-event.json") |> File.read!() |> Jason.decode!()

    assert managed_event["facts"]["source_proof"] === hd(opts.verified_sources)
    assert managed_event["facts"]["policy_sha256"] === JSON.digest([policy])

    File.rename!(
      Path.join(c.base, "pending-management-event.json"),
      Path.join(c.base, "pending-management-valid-event.json")
    )

    denied_sources =
      update_in(policy, ["settings", "sources", "categories"], fn categories ->
        List.delete(categories, proof["origin"])
      end)

    denied_sources =
      Map.put(
        denied_sources,
        "source_sha256",
        JSON.digest([denied_sources["settings"]["sources"]])
      )

    assert Ipse.Extension.SemanticConsent.policy?(denied_sources)

    denied_read =
      update_in(policy, ["settings", "effects"], fn effects ->
        Enum.map(effects, fn mapping ->
          if mapping["class"] == "collection.read" do
            update_in(mapping, ["managed_read"], &List.delete(&1, JSON.digest([note_recipe])))
          else
            mapping
          end
        end)
      end)

    assert Ipse.Extension.SemanticConsent.policy?(denied_read)

    assert {:ok, %{"epoch" => 2}} =
             Ipse.Extension.Consent.replace(
               control,
               c.binding["project_id"],
               1,
               denied_sources,
               System.system_time(:millisecond)
             )

    denied_args =
      ["--management-review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
        paths ++
        [Path.expand("test/support/pending_acceptance_management.exs"), c.base, "denied-source"]

    {denied_output, denied_status} = System.cmd(driver, denied_args, stderr_to_stdout: true)
    assert denied_status == 0, denied_output
    assert denied_output =~ "PENDING_MANAGEMENT_REVIEW_DENIED-SOURCE_PASSED"
    refute denied_output =~ "Historical pending candidate"

    assert {:ok, %{"epoch" => 3}} =
             Ipse.Extension.Consent.replace(
               control,
               c.binding["project_id"],
               2,
               policy,
               System.system_time(:millisecond)
             )

    if System.get_env("IPSE_TEST_V7_SOURCE_LOSS") == "1" do
      for phase <- ["prewrite", "partial"] do
        loss_args =
          ["--management-review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
            paths ++
            [
              Path.expand("test/support/pending_acceptance_management.exs"),
              c.base,
              "source-loss-display-" <> phase
            ]

        loss =
          Task.async(fn ->
            System.cmd(driver, loss_args,
              stderr_to_stdout: true,
              env: [
                {if(phase == "partial",
                   do: "IPSE_TEST_TTY_PARTIAL_STOP",
                   else: "IPSE_TEST_TTY_PREWRITE_STOP"
                 ), "1"}
              ]
            )
          end)

        source_pid_file = Path.join(c.base, "pending-source-owner-pid-" <> phase)
        deadline = System.monotonic_time(:millisecond) + 10_000

        wait_for_loss = fn wait_for_loss ->
          stopped =
            File.ls!("/proc")
            |> Enum.find_value(fn entry ->
              with {pid, ""} <- Integer.parse(entry),
                   {:ok, status} <- File.read("/proc/#{pid}/status"),
                   true <- String.contains?(status, "State:\tT"),
                   {:ok, command} <- File.read("/proc/#{pid}/cmdline"),
                   true <- String.contains?(command, "v7-management-source-lease-input") do
                pid
              else
                _ -> nil
              end
            end)

          cond do
            stopped && File.exists?(source_pid_file) ->
              {:ok, stopped}

            System.monotonic_time(:millisecond) >= deadline ->
              :timeout

            true ->
              Process.sleep(10)
              wait_for_loss.(wait_for_loss)
          end
        end

        assert {:ok, reader_pid} = wait_for_loss.(wait_for_loss)
        source_pid = source_pid_file |> File.read!() |> String.to_integer()
        assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(source_pid)])
        {loss_output, loss_status} = Task.await(loss, 15_000)
        assert loss_status == 0, loss_output

        assert loss_output =~
                 "PENDING_MANAGEMENT_REVIEW_SOURCE-LOSS-DISPLAY-#{String.upcase(phase)}_PASSED"

        if phase == "partial", do: assert(loss_output =~ "Historical pending candidate")
        refute loss_output =~ "ACCEPTANCE_PRIVATE_TAIL"
        refute loss_output =~ "Type accept "
        refute File.exists?("/proc/#{reader_pid}")
      end
    end

    ready = Path.join(c.base, "management-review-input-ready")

    wait = fn wait, wait_until ->
      cond do
        File.exists?(ready) ->
          :ok

        System.monotonic_time(:millisecond) >= wait_until ->
          :timeout

        true ->
          Process.sleep(10)
          wait.(wait, wait_until)
      end
    end

    for mode <- ~w(source-race host-source-race) do
      source_race_args =
        ["--management-review-race", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++ [Path.expand("test/support/pending_acceptance_management.exs"), c.base, mode]

      source_race =
        Task.async(fn -> System.cmd(driver, source_race_args, stderr_to_stdout: true) end)

      assert :ok = wait.(wait, System.monotonic_time(:millisecond) + 10_000)

      assert {:ok, source_lock} =
               Runner.lock(Path.join(history_dir, proof["session_id"] <> ".lock"))

      File.write!(Path.join(c.base, "management-review-race-complete"), "done")
      {source_output, source_status} = Task.await(source_race, 15_000)
      assert :ok = Runner.unlock(source_lock)
      assert source_status == 0, source_output
      assert source_output =~ "PENDING_MANAGEMENT_REVIEW_#{String.upcase(mode)}_PASSED"
      File.rm!(ready)
      File.rm!(Path.join(c.base, "management-review-race-complete"))
    end

    if System.get_env("IPSE_TEST_ACCEPTANCE_SWITCH") == "1" do
      File.write!(Path.join(c.cwd, "source-switch-before-decision.arm"), "armed")

      writer_args =
        ["--management-review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [
            Path.expand("test/support/pending_acceptance_management.exs"),
            c.base,
            "host-writer-before"
          ]

      {writer_output, writer_status} = System.cmd(driver, writer_args, stderr_to_stdout: true)
      assert writer_status == 0, writer_output
      assert writer_output =~ "PENDING_MANAGEMENT_REVIEW_HOST-WRITER-BEFORE_PASSED"
      assert File.exists?(Path.join(c.base, "pending-host-writer-before-writer-killed"))

      assert {:ok, unchanged} =
               C.execute(c.root, c.namespace, %{"op" => "get", "key" => key}, Ipse.Usage.id())

      assert unchanged["record"]["value"]["text"] === proposal_text
      File.rm!(Path.join(c.cwd, "source-switch-before-decision.ready"))
      File.rm!(Path.join(c.cwd, "source-switch-before-decision.go"))

      args =
        ["--management-review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [
            Path.expand("test/support/pending_acceptance_management.exs"),
            c.base,
            "host-loss-before"
          ]

      running = Task.async(fn -> System.cmd(driver, args, stderr_to_stdout: true) end)
      marker = Path.join(c.cwd, "source-switch-before-decision.ready")
      assert :ok = wait_file(marker, System.monotonic_time(:millisecond) + 15_000)
      source_lock_path = Path.join(history_dir, proof["session_id"] <> ".lock")

      source_pid = source_holder(source_lock_path)

      assert is_integer(source_pid)
      assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(source_pid)])
      File.write!(Path.join(c.cwd, "source-switch-before-decision.go"), "go")
      {output, status} = Task.await(running, 20_000)
      assert status == 0, output
      assert output =~ "PENDING_MANAGEMENT_REVIEW_HOST-LOSS-BEFORE_PASSED"

      assert {:ok, still_pending} =
               C.execute(c.root, c.namespace, %{"op" => "get", "key" => key}, Ipse.Usage.id())

      assert still_pending["record"]["value"]["text"] === proposal_text
      File.rm!(Path.join(c.cwd, "source-switch-before-decision.arm"))
    end

    race_args =
      ["--management-review-race", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
        paths ++ [Path.expand("test/support/pending_acceptance_management.exs"), c.base, "race"]

    race = Task.async(fn -> System.cmd(driver, race_args, stderr_to_stdout: true) end)
    assert :ok = wait.(wait, System.monotonic_time(:millisecond) + 10_000)

    assert {:ok, %{"epoch" => 4}} =
             Ipse.Extension.Consent.revoke(control, c.binding["project_id"], 3)

    File.write!(Path.join(c.base, "management-review-race-complete"), "done")
    {race_output, race_status} = Task.await(race, 15_000)
    assert race_status == 0, race_output
    assert race_output =~ "PENDING_MANAGEMENT_REVIEW_RACE_PASSED"

    assert {:ok, ^before} =
             Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                     catalog ->
               ObservedRead.managed_proposal(
                 c.root,
                 c.namespace,
                 request,
                 cap,
                 catalog,
                 opts.recipe
               )
             end)

    assert {:ok, %{"epoch" => 5}} =
             Ipse.Extension.Consent.replace(
               control,
               c.binding["project_id"],
               4,
               policy,
               System.system_time(:millisecond)
             )

    for mode <- ["publish-tampered", "publish"] do
      publish_args =
        ["--management-review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++ [Path.expand("test/support/pending_acceptance_management.exs"), c.base, mode]

      {output, status} = System.cmd(driver, publish_args, stderr_to_stdout: true)
      assert status == 0, output
      assert output =~ "PENDING_MANAGEMENT_REVIEW_#{String.upcase(mode)}_PASSED"

      if mode == "publish-tampered" do
        assert {:ok, current} =
                 C.execute(c.root, c.namespace, %{"op" => "get", "key" => key}, Ipse.Usage.id())

        assert current["record"]["value"]["text"] === proposal_text
      end
    end

    published =
      c.base |> Path.join("pending-management-publish.json") |> File.read!() |> Jason.decode!()

    event = published["event"]
    candidate = event["facts"]["candidate_id"]

    for {mode, expected} <- [{"publish", "committed"}, {"publish-tampered", "unknown"}] do
      recorded =
        c.base
        |> Path.join("pending-management-#{mode}.json")
        |> File.read!()
        |> Jason.decode!()

      recorded_event = recorded["event"]

      assert {:ok, operation} =
               Ipse.CLI.Knowledge.Management.operation(
                 %{home: c.home},
                 c.cwd,
                 recorded_event["facts"]["journal_id"]
               )

      assert operation["journal_status"] === expected
      assert operation["operation_id"] === recorded_event["facts"]["operation_id"]
      assert operation["record_key"] === recorded_event["facts"]["pending_key"]
      assert operation["replayed"] === false
      assert operation["current_note_eligibility"] === "not_checked"
      refute Jason.encode!(operation) =~ proposal_text
    end

    valid_review =
      c.base
      |> Path.join("pending-management-valid-event.json")
      |> File.read!()
      |> Jason.decode!()

    assert {:ok, %{"journal_status" => "refused", "replayed" => false}} =
             Ipse.CLI.Knowledge.Management.operation(
               %{home: c.home},
               c.cwd,
               valid_review["facts"]["journal_id"]
             )

    journal_id = event["facts"]["journal_id"]
    journal_path = Path.join([c.home, "knowledge-management", journal_id <> ".jsonl"])
    journal_lock_path = Path.join([c.home, "knowledge-management", journal_id <> ".lock"])
    original_journal = File.read!(journal_path)
    lines = String.split(original_journal, "\n", trim: true)
    interrupted = Enum.join(Enum.drop(lines, -1), "\n") <> "\n"
    assert {:ok, journal_lock} = Runner.protected_resume_lock(journal_lock_path)
    File.write!(journal_path, interrupted)
    assert :ok = Runner.unlock_export_candidate(journal_lock)

    assert {:ok, %{"journal_status" => "unknown", "replayed" => false}} =
             Ipse.CLI.Knowledge.Management.operation(%{home: c.home}, c.cwd, journal_id)

    assert File.read!(journal_path) === interrupted

    complete_card = Enum.join(Enum.take(lines, 2), "\n") <> "\n"
    assert {:ok, journal_lock} = Runner.protected_resume_lock(journal_lock_path)
    File.write!(journal_path, complete_card)
    assert :ok = Runner.unlock_export_candidate(journal_lock)

    assert {:ok, %{"journal_status" => "not_started", "replayed" => false}} =
             Ipse.CLI.Knowledge.Management.operation(%{home: c.home}, c.cwd, journal_id)

    partial_intent = complete_card <> "{\"type\":\"pending_acceptance_intent\""

    assert {:ok, journal_lock} = Runner.protected_resume_lock(journal_lock_path)
    File.write!(journal_path, partial_intent)
    assert :ok = Runner.unlock_export_candidate(journal_lock)

    assert {:ok, %{"journal_status" => "unknown", "replayed" => false}} =
             Ipse.CLI.Knowledge.Management.operation(%{home: c.home}, c.cwd, journal_id)

    assert File.read!(journal_path) === partial_intent
    assert {:ok, journal_lock} = Runner.protected_resume_lock(journal_lock_path)
    File.write!(journal_path, original_journal)
    assert :ok = Runner.unlock_export_candidate(journal_lock)

    lineage =
      JSON.digest([
        "ipse-knowledge",
        1,
        "accepted_decision",
        candidate,
        event["facts"]["lineage"]
      ])

    assert {:ok, pending} =
             C.execute(c.root, c.namespace, %{"op" => "get", "key" => key}, Ipse.Usage.id())

    assert pending["record"] == nil

    assert {:ok, note} =
             C.execute(
               c.root,
               c.namespace,
               %{"op" => "get", "key" => "note." <> lineage},
               Ipse.Usage.id()
             )

    assert note["record"]["value"]["text"] === proposal_text

    # Even a read mapping that registers only proposals must not return the
    # accepted note as an ordinary root-only observation.
    read_context = %{config: %{home: c.home}}

    read_intent = %{
      "namespace" => c.namespace,
      "request" => %{"request" => %{"op" => "get", "key" => "note." <> lineage}}
    }

    assert {:error, :collection_source_refused} =
             Ipse.Extension.ManagedRead.execute(
               read_context,
               read_intent,
               [opts.recipe],
               fn false, fun -> fun.(nil, nil) end,
               fn _, _ -> flunk("accepted note reached managed read admission") end
             )

    assert {:ok, link} =
             C.execute(
               c.root,
               c.namespace,
               %{"op" => "get", "key" => "accept." <> candidate},
               Ipse.Usage.id()
             )

    assert link["record"]["value"]["acceptance_event_sha256"] === JSON.digest([event])
    assert link["record"]["value"]["journal_id"] === event["facts"]["journal_id"]
    assert link["record"]["value"]["journal_kind"] === "knowledge_management"

    current_admission =
      source_admission
      |> put_in(["pin", "session_id"], event["facts"]["journal_id"])
      |> put_in(["pin", "epoch"], event["facts"]["capture_epoch"])
      |> put_in(["pin", "policy_sha256"], event["facts"]["policy_sha256"])

    source_context = %{
      history_dir: history_dir,
      session_id: event["facts"]["journal_id"],
      config: %{semantic_admission: current_admission}
    }

    session_id = Ipse.Usage.id()
    config = %{home: c.home, provider: :demo, model: "demo", extensions: [%{identity: identity}]}
    {:ok, selectors} = Ipse.Extension.SemanticRoutes.selectors(policy["settings"]["routes"])
    {:ok, routes} = Ipse.Extension.SemanticRoutes.resolve(config, selectors)
    {:ok, mode} = Ipse.Extension.Mode.capture(config)

    semantic_context = %{
      "session_id" => session_id,
      "binding" => c.binding,
      "identity" => identity,
      "namespace" => c.namespace,
      "routes" => routes,
      "mode" => mode,
      "source_generation" => 0
    }

    assert {:ok, pin} =
             Ipse.Extension.SemanticConsent.admit(
               %{"epoch" => 5, "policy" => policy},
               semantic_context,
               System.system_time(:millisecond)
             )

    admission = %{
      "version" => 2,
      "binding" => c.binding,
      "instance" => "knowledge",
      "pin" => pin,
      "selectors" => selectors,
      "status" => "active",
      "policy" => policy
    }

    use_context = %{
      history_dir: history_dir,
      session_id: session_id,
      cwd: c.cwd,
      config: Map.put(config, :semantic_admission, admission)
    }

    assert {:ok, inspection} =
             Ipse.Session.ManagedUse.inspect_accepted(
               use_context,
               link["record"]["value"],
               JSON.digest([note_recipe])
             )

    assert inspection["acceptance_event_sha256"] === JSON.digest([event])
    assert inspection["record_sha256"] === note["record"]["sha256"]
    assert inspection["link_sha256"] === link["record"]["sha256"]
    refute Map.has_key?(inspection, "text")

    dependency = inspection["dependency"]
    assert dependency["version"] === 6
    assert ManagedReference.dependency?(dependency)
    assert ManagedReference.current?(dependency, dependency, System.system_time(:millisecond))

    assert {:ok, ^inspection} =
             Ipse.Session.ManagedUse.inspect_accepted_reference(use_context, dependency)

    assert {:ok, :held} =
             Ipse.Session.ManagedUse.with_accepted_reference(
               use_context,
               dependency,
               fn current, journal_lease, source_lease ->
                 assert current === inspection
                 refute Map.has_key?(current, "text")

                 assert {:ok, _} =
                          Ipse.Session.PendingAcceptance.journal_share_identity(journal_lease)

                 assert {:ok, _} = Ipse.Session.StoredSources.share_identity(source_lease)
                 assert {:ok, [_, _, _]} = Ipse.Runner.Transaction.retained_share_stack()

                 assert {:error, _} =
                          Task.async(fn ->
                            Ipse.Session.StoredSources.share_identity(source_lease)
                          end)
                          |> Task.await()

                 assert {:ok, :collected} =
                          collect_accepted_leases(c.cwd, journal_lease, source_lease)

                 {:ok, :held}
               end
             )

    assert {:error, _} =
             Ipse.Session.ManagedUse.with_accepted_reference(
               use_context,
               put_in(
                 dependency,
                 ["subject", "acceptance", "event_sha256"],
                 JSON.sha256("other")
               ),
               fn _, _, _ -> flunk("changed acceptance reached retained callback") end
             )

    for callback <- [
          fn _, _, _ -> {:error, :fixture_interrupted} end,
          fn _, _, _ -> raise "synthetic retained callback interruption" end
        ] do
      assert {:unknown, :accepted_reference_unconfirmed} =
               Ipse.Session.ManagedUse.with_accepted_reference(use_context, dependency, callback)
    end

    assert {:error, _} =
             Ipse.Session.ManagedUse.inspect_accepted_reference(
               use_context,
               put_in(dependency, ["subject", "acceptance", "event_sha256"], JSON.sha256("other"))
             )

    refute ManagedReference.current?(
             dependency,
             put_in(dependency, ["subject", "acceptance", "event_sha256"], JSON.sha256("other")),
             System.system_time(:millisecond)
           )

    assert {:ok, :delivered} =
             Ipse.Session.ManagedUse.with_dependencies(use_context, [dependency], fn [current] ->
               assert ManagedReference.current?(
                        dependency,
                        current,
                        System.system_time(:millisecond)
                      )

               assert {:error, _} =
                        Runner.lock(Path.join(history_dir, proof["session_id"] <> ".lock"))

               assert {:error, _} =
                        Runner.protected_resume_lock(
                          Path.join([
                            c.home,
                            "knowledge-management",
                            event["facts"]["journal_id"] <> ".lock"
                          ])
                        )

               {:ok, :delivered}
             end)

    assert {:error, _} =
             Ipse.Session.ManagedUse.with_dependencies(
               use_context,
               [
                 put_in(
                   dependency,
                   ["subject", "acceptance", "event_sha256"],
                   JSON.sha256("other")
                 )
               ],
               fn _ -> flunk("changed acceptance reached current-use delivery") end
             )

    assert {:error, _} =
             Ipse.Session.ManagedUse.inspect_accepted(
               use_context,
               Map.put(link["record"]["value"], "candidate_id", JSON.sha256("other")),
               JSON.digest([note_recipe])
             )

    assert {:ok, :checked} =
             Ipse.Session.Resources.file_effect(fn ->
               Ipse.Session.PendingAcceptance.with_shareable_committed_management_journal(
                 c.home,
                 c.binding["project_id"],
                 c.namespace,
                 link["record"]["value"],
                 fn resolved, journal_lease ->
                   assert resolved.event === event

                   assert {:ok, _} =
                            Ipse.Session.PendingAcceptance.journal_share_identity(journal_lease)

                   assert {:error, :pending_acceptance_refused} =
                            Task.async(fn ->
                              Ipse.Session.PendingAcceptance.journal_share_identity(journal_lease)
                            end)
                            |> Task.await()

                   assert {:error, _} =
                            Runner.protected_resume_lock(
                              Path.join([
                                c.home,
                                "knowledge-management",
                                event["facts"]["journal_id"] <> ".lock"
                              ])
                            )

                   Ipse.Session.PendingAcceptance.with_shareable_source(
                     source_context,
                     event["facts"],
                     fn source, source_lease ->
                       assert source["proof"] === event["facts"]["source_proof"]

                       assert {:error, _} =
                                Runner.lock(
                                  Path.join(history_dir, proof["session_id"] <> ".lock")
                                )

                       Identity.with_existing_domain_auth(
                         c.home,
                         c.cwd,
                         c.binding,
                         domain,
                         fn cap, catalog ->
                           Ipse.Extension.Consent.with_policy(
                             control,
                             c.binding["project_id"],
                             event["facts"]["capture_epoch"],
                             event["facts"]["policy_sha256"],
                             System.system_time(:millisecond),
                             fn current_policy ->
                               assert {:ok, :matched} =
                                        ObservedRead.with_accepted_decision(
                                          c.root,
                                          c.namespace,
                                          event,
                                          cap,
                                          catalog,
                                          note_recipe,
                                          System.system_time(:millisecond),
                                          fn observed ->
                                            assert observed["record"] === note["record"]
                                            assert observed["link"] === link["record"]

                                            now = System.system_time(:millisecond)

                                            assert {:ok, ^dependency} =
                                                     ObservedRead.accepted_dependency(
                                                       event,
                                                       observed,
                                                       pin,
                                                       note_recipe,
                                                       proof,
                                                       now
                                                     )

                                            for changed <- [
                                                  put_in(
                                                    observed,
                                                    ["record", "value", "text"],
                                                    "changed"
                                                  ),
                                                  put_in(
                                                    observed,
                                                    ["link", "value", "journal_id"],
                                                    Ipse.Usage.id()
                                                  ),
                                                  put_in(
                                                    observed,
                                                    ["metadata", "acceptance_event_sha256"],
                                                    JSON.sha256("other")
                                                  )
                                                ] do
                                              assert {:error, :collection_observation_refused} =
                                                       ObservedRead.accepted_dependency(
                                                         event,
                                                         changed,
                                                         pin,
                                                         note_recipe,
                                                         proof,
                                                         now
                                                       )
                                            end

                                            assert {:error, :collection_observation_refused} =
                                                     ObservedRead.accepted_dependency(
                                                       event,
                                                       observed,
                                                       pin,
                                                       note_recipe,
                                                       Map.put(
                                                         proof,
                                                         "version_id",
                                                         Ipse.Usage.id()
                                                       ),
                                                       now
                                                     )

                                            cap = Process.get({C, :lock_held})

                                            lease_result =
                                              Ipse.Runner.Transaction.with_inactive_acceptance_journal_lease(
                                                cap,
                                                journal_lease,
                                                fn ->
                                                  Ipse.Runner.Transaction.with_source_lease(
                                                    cap,
                                                    source_lease,
                                                    fn ->
                                                      assert {:error, _} =
                                                               Runner.protected_resume_lock(
                                                                 Path.join([
                                                                   c.home,
                                                                   "knowledge-management",
                                                                   event["facts"]["journal_id"] <>
                                                                     ".lock"
                                                                 ])
                                                               )

                                                      assert {:error, _} =
                                                               Runner.lock(
                                                                 Path.join(
                                                                   history_dir,
                                                                   proof["session_id"] <> ".lock"
                                                                 )
                                                               )

                                                      Ipse.Runner.Transaction.check(cap)
                                                    end
                                                  )
                                                end
                                              )

                                            assert :ok = lease_result

                                            assert {:error, :pending_acceptance_refused} =
                                                     Ipse.Session.PendingAcceptance.journal_share_identity(
                                                       journal_lease
                                                     )

                                            assert observed["metadata"]["acceptance_event_sha256"] ===
                                                     JSON.digest([event])

                                            assert observed["metadata"]["source_proof"] ===
                                                     event["facts"]["source_proof"]

                                            assert {:ok, deadline} =
                                                     Ipse.Session.PendingAcceptance.accepted_use_policy(
                                                       event,
                                                       observed["metadata"],
                                                       current_policy["policy"],
                                                       note_recipe,
                                                       System.system_time(:millisecond)
                                                     )

                                            assert deadline <=
                                                     current_policy["policy"]["expires_at_ms"]

                                            assert {:error, :pending_acceptance_refused} =
                                                     Ipse.Session.PendingAcceptance.accepted_use_policy(
                                                       event,
                                                       observed["metadata"],
                                                       denied_sources,
                                                       note_recipe,
                                                       System.system_time(:millisecond)
                                                     )

                                            assert {:error, :pending_acceptance_refused} =
                                                     Ipse.Session.PendingAcceptance.accepted_use_policy(
                                                       event,
                                                       observed["metadata"],
                                                       denied_read,
                                                       note_recipe,
                                                       System.system_time(:millisecond)
                                                     )

                                            {:ok, :matched}
                                          end
                                        )

                               assert {:error, :collection_observation_refused} =
                                        ObservedRead.with_accepted_decision(
                                          c.root,
                                          c.namespace,
                                          event,
                                          cap,
                                          catalog,
                                          note_recipe,
                                          note["record"]["value"]["valid_until_ms"],
                                          fn _ -> flunk("expired acceptance disclosed") end
                                        )

                               assert {:error, :collection_observation_refused} =
                                        ObservedRead.with_accepted_decision(
                                          c.root,
                                          c.namespace,
                                          put_in(event, ["facts", "text"], "changed"),
                                          cap,
                                          catalog,
                                          note_recipe,
                                          System.system_time(:millisecond),
                                          fn _ -> flunk("changed event accepted") end
                                        )

                               assert {:error, :collection_observation_refused} =
                                        Task.async(fn ->
                                          ObservedRead.with_accepted_decision(
                                            c.root,
                                            c.namespace,
                                            event,
                                            cap,
                                            catalog,
                                            note_recipe,
                                            System.system_time(:millisecond),
                                            fn _ -> flunk("cross-process capability accepted") end
                                          )
                                        end)
                                        |> Task.await()

                               {:ok, :checked}
                             end
                           )
                         end
                       )
                     end
                   )
                 end
               )
             end)

    assert {:ok, :collected} =
             Ipse.Session.Resources.file_effect(fn ->
               Ipse.Session.PendingAcceptance.with_shareable_committed_management_journal(
                 c.home,
                 c.binding["project_id"],
                 c.namespace,
                 link["record"]["value"],
                 fn _, journal_lease ->
                   Ipse.Session.PendingAcceptance.with_shareable_source(
                     source_context,
                     event["facts"],
                     fn _, source_lease ->
                       Identity.with_existing_domain_auth(
                         c.home,
                         c.cwd,
                         c.binding,
                         domain,
                         fn cap, catalog ->
                           Ipse.Extension.Consent.with_policy(
                             control,
                             c.binding["project_id"],
                             event["facts"]["capture_epoch"],
                             event["facts"]["policy_sha256"],
                             System.system_time(:millisecond),
                             fn _ ->
                               ObservedRead.with_accepted_decision(
                                 c.root,
                                 c.namespace,
                                 event,
                                 cap,
                                 catalog,
                                 note_recipe,
                                 System.system_time(:millisecond),
                                 fn _ ->
                                   collect_accepted_leases(c.cwd, journal_lease, source_lease)
                                 end
                               )
                             end
                           )
                         end
                       )
                     end
                   )
                 end
               )
             end)

    if helper = System.get_env("IPSE_TEST_BOUND_ACCEPTANCE_HELPER") do
      fixture_path = Path.join(c.base, "bound-acceptance-fixture.json")

      File.write!(
        fixture_path,
        Jason.encode!(%{
          "home" => c.home,
          "cwd" => c.cwd,
          "binding" => c.binding,
          "project" => c.binding["project_id"],
          "namespace" => c.namespace,
          "link" => link["record"]["value"],
          "event" => event,
          "recipe" => note_recipe,
          "history_dir" => history_dir,
          "admission" => current_admission
        })
      )

      modes =
        if System.get_env("IPSE_TEST_BOUND_HOST_ONLY") == "1",
          do: ~w(bound-acceptance),
          else:
            ~w(bound-acceptance bound-loss-session bound-loss-collection bound-loss-journal bound-loss-source bound-loss-session-control bound-loss-host-control)

      for mode <- modes do
        args =
          [System.find_executable("elixir"), "--erl", "+S 2:2"] ++
            paths ++
            [
              Path.expand("test/support/accepted_lease_positive.exs"),
              helper,
              Path.join(c.base, "six-" <> mode),
              Path.join(Application.app_dir(:ipse), "ebin"),
              mode,
              fixture_path
            ]

        {output, status} = System.cmd(driver, args, stderr_to_stdout: true)
        assert status == 0, output

        if mode == "bound-acceptance" do
          assert output =~ "SIX_LEASE_SYNTHETIC_PASSED"
        else
          assert output =~ "SIX_LEASE_OWNER_LOSS_REFUSED"
          refute output =~ "SYNTHETIC_ACCEPTED_LEASE_DISPLAY"
        end
      end

      if runtime = System.get_env("IPSE_TEST_BOUND_HOST_RUNTIME") do
        args =
          [System.find_executable("elixir"), "--erl", "+S 2:2"] ++
            paths ++
            [
              "-pa",
              Path.join(runtime, "_build/test/lib/ipse/ebin"),
              "test/support/bound_host_entry.exs"
            ]

        for expire <- ["0", "1"] do
          {output, status} =
            System.cmd(driver, args,
              cd: runtime,
              env: [
                {"IPSE_BOUND_HOST_FIXTURE", fixture_path},
                {"IPSE_BOUND_EXPIRE_BEFORE_ACTIVATION", expire},
                {"IPSE_ACCEPTED_LEASE_MODULE_ONLY", "1"},
                {"IPSE_SHARE_TTY_SIX", "1"},
                {"ERL_FLAGS", "+S 2:2"}
              ],
              stderr_to_stdout: true
            )

          assert status == 0, output
          assert output =~ "1 passed"

          if expire == "0" do
            assert output =~ "SYNTHETIC_ACCEPTED_LEASE_DISPLAY"
          else
            assert output =~ "BOUND_BEFORE_ACTIVATION"
            refute output =~ "SYNTHETIC_ACCEPTED_LEASE_DISPLAY"
            assert output =~ "BOUND_CLEANUP_UNCONFIRMED" or output =~ "BOUND_HOST_TERMINATED"
          end
        end
      end
    end

    test_owner = self()

    for lost <- [:journal, :source] do
      result =
        try do
          Ipse.Session.Resources.file_effect(fn ->
            Ipse.Session.PendingAcceptance.with_shareable_committed_management_journal(
              c.home,
              c.binding["project_id"],
              c.namespace,
              link["record"]["value"],
              fn _, journal_lease ->
                {:ok, journal_identity} =
                  Ipse.Session.PendingAcceptance.journal_share_identity(journal_lease)

                Ipse.Session.PendingAcceptance.with_shareable_source(
                  source_context,
                  event["facts"],
                  fn _, source_lease ->
                    {:ok, source_identity} =
                      Ipse.Session.StoredSources.share_identity(source_lease)

                    Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                            catalog ->
                      Ipse.Extension.Consent.with_policy(
                        control,
                        c.binding["project_id"],
                        event["facts"]["capture_epoch"],
                        event["facts"]["policy_sha256"],
                        System.system_time(:millisecond),
                        fn _ ->
                          ObservedRead.with_accepted_decision(
                            c.root,
                            c.namespace,
                            event,
                            cap,
                            catalog,
                            note_recipe,
                            System.system_time(:millisecond),
                            fn _ ->
                              transaction = Process.get({C, :lock_held})

                              Ipse.Runner.Transaction.with_inactive_acceptance_journal_lease(
                                transaction,
                                journal_lease,
                                fn ->
                                  Ipse.Runner.Transaction.with_source_lease(
                                    transaction,
                                    source_lease,
                                    fn ->
                                      victim =
                                        if lost == :journal,
                                          do: journal_identity.pid,
                                          else: source_identity.pid

                                      send(test_owner, {:lease_loss_entered, lost})

                                      {_, 0} =
                                        System.cmd("kill", ["-KILL", Integer.to_string(victim)])

                                      deadline = System.monotonic_time(:millisecond) + 2_000

                                      wait_for_death = fn wait_for_death ->
                                        case File.read("/proc/#{victim}/status") do
                                          {:error, :enoent} ->
                                            :ok

                                          {:ok, status} ->
                                            cond do
                                              String.contains?(status, "State:\tZ") ->
                                                :ok

                                              System.monotonic_time(:millisecond) >= deadline ->
                                                :timeout

                                              true ->
                                                Process.sleep(5)
                                                wait_for_death.(wait_for_death)
                                            end
                                        end
                                      end

                                      :ok = wait_for_death.(wait_for_death)
                                      checked = Ipse.Runner.Transaction.check(transaction)
                                      send(test_owner, {:lease_loss_check, lost, checked})
                                      checked
                                    end
                                  )
                                end
                              )
                            end
                          )
                        end
                      )
                    end)
                  end
                )
              end
            )
          end)
        catch
          :exit, :file_effect_unconfirmed -> {:unknown, :file_effect_unconfirmed}
        end

      assert_receive {:lease_loss_entered, ^lost}, 1_000

      receive do
        {:lease_loss_check, ^lost, checked} -> refute checked == :ok
      after
        100 -> :ok
      end

      refute match?({:ok, _}, result)
    end

    assert {:error, :pending_acceptance_refused} =
             Ipse.Session.PendingAcceptance.with_committed_management_journal(
               c.home,
               c.binding["project_id"],
               c.namespace,
               Map.put(link["record"]["value"], "candidate_id", JSON.sha256("other")),
               fn _ -> flunk("changed link accepted") end
             )

    assert {:error, :pending_acceptance_refused} =
             Ipse.Session.PendingAcceptance.with_committed_management_journal(
               c.home,
               JSON.sha256("other project"),
               c.namespace,
               link["record"]["value"],
               fn _ -> flunk("other project accepted") end
             )

    copied_home = Path.join(c.base, "copied-home")
    copied_directory = Path.join(copied_home, "knowledge-management")
    File.mkdir!(copied_home)
    File.chmod!(copied_home, 0o700)
    File.mkdir!(copied_directory)
    File.chmod!(copied_directory, 0o700)

    for suffix <- [".lock", ".jsonl"] do
      name = event["facts"]["journal_id"] <> suffix

      File.cp!(
        Path.join([c.home, "knowledge-management", name]),
        Path.join(copied_directory, name)
      )
    end

    assert {:error, :pending_acceptance_refused} =
             Ipse.Session.PendingAcceptance.with_committed_management_journal(
               copied_home,
               c.binding["project_id"],
               c.namespace,
               link["record"]["value"],
               fn _ -> flunk("copied journal accepted") end
             )

    assert {:ok, changed_root} =
             C.execute(
               c.root,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => dependency["collection"]["generation"],
                 "advance_floor" => true,
                 "changes" => [
                   %{
                     "key" => "unrelated-fixture",
                     "expected_revision" => 0,
                     "value" => %{"kind" => "fixture"}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    assert {:ok, advanced} =
             Ipse.Session.ManagedUse.inspect_accepted_reference(use_context, dependency)

    assert advanced["dependency"]["collection"]["generation"] === changed_root["generation"]
    assert advanced["record_sha256"] === inspection["record_sha256"]

    source_path = Path.join(history_dir, proof["session_id"] <> ".jsonl")
    source_lock_path = Path.join(history_dir, proof["session_id"] <> ".lock")
    original_source = File.read!(source_path)
    assert {:ok, source_lock} = Runner.lock(source_lock_path)
    File.write!(source_path, "incomplete", [:append])
    assert :ok = Runner.unlock(source_lock)

    assert {:error, _} =
             Ipse.Session.ManagedUse.inspect_accepted_reference(use_context, dependency)

    assert {:error, _} =
             Ipse.Session.ManagedUse.with_accepted_reference(
               use_context,
               dependency,
               fn _, _, _ -> flunk("changed source reached retained callback") end
             )

    assert {:ok, source_lock} = Runner.lock(source_lock_path)
    File.write!(source_path, original_source)
    assert :ok = Runner.unlock(source_lock)
    assert {:ok, _} = Ipse.Session.ManagedUse.inspect_accepted_reference(use_context, dependency)

    if System.get_env("IPSE_TEST_ACCEPTANCE_ORCHESTRATION") == "1" do
      fixture_path = Path.join(c.base, "pending-management.json")
      fixture = fixture_path |> File.read!() |> Jason.decode!()

      for {mode, flag} <- [
            {"host-orchestrated", "--management-review"},
            {"host-orchestrated-cancel", "--management-review-cancel"},
            {"host-orchestrated-race", "--management-review-race"},
            {"host-orchestrated-expired", "--management-review-race"}
          ] do
        now = System.system_time(:millisecond)

        assert {:ok, candidate_key, candidate_value} =
                 Records.capture(
                   %{
                     "text" => "Synthetic production-helper acceptance #{mode}",
                     "category" => "ordinary",
                     "reason" => "synthetic host orchestration",
                     "event_at_ms" => nil
                   },
                   proof,
                   now
                 )

        assert {:ok, before} =
                 C.execute(c.root, c.namespace, %{"op" => "snapshot"}, Ipse.Usage.id())

        candidate_opts = %{
          opts
          | now_ms: now,
            request: %{
              "op" => "commit",
              "expected_generation" => before["generation"],
              "advance_floor" => true,
              "changes" => [
                %{"key" => candidate_key, "expected_revision" => 0, "value" => candidate_value}
              ]
            }
        }

        assert {:ok, _} = publish(c, candidate_opts, scope(c, false))

        assert {:ok, original} =
                 C.execute(
                   c.root,
                   c.namespace,
                   %{"op" => "get", "key" => candidate_key},
                   Ipse.Usage.id()
                 )

        File.write!(fixture_path, Jason.encode!(Map.put(fixture, "key", candidate_key)))

        args =
          [flag, System.find_executable("elixir"), "--erl", "+S 2:2"] ++
            paths ++
            [Path.expand("test/support/pending_acceptance_management.exs"), c.base, mode]

        {output, status} =
          if mode in ~w(host-orchestrated-race host-orchestrated-expired) do
            running = Task.async(fn -> System.cmd(driver, args, stderr_to_stdout: true) end)
            marker = Path.join(c.base, "management-review-input-ready")
            release = Path.join(c.base, "management-review-race-complete")

            try do
              assert :ok = wait_file(marker, System.monotonic_time(:millisecond) + 10_000)

              if mode == "host-orchestrated-expired" do
                Task.await(running, 15_000)
              else
                assert {:ok, held} = Runner.lock(source_lock_path)

                try do
                  File.write!(release, "done")
                  Task.await(running, 15_000)
                after
                  assert :ok = Runner.unlock(held)
                end
              end
            after
              File.write!(release, "done")
              if Process.alive?(running.pid), do: Task.yield(running, 5_000)
              File.rm(marker)
              File.rm(release)
            end
          else
            System.cmd(driver, args, stderr_to_stdout: true)
          end

        assert status == 0, output
        assert output =~ "PENDING_MANAGEMENT_REVIEW_#{String.upcase(mode)}_PASSED"

        assert {:ok, current} =
                 C.execute(
                   c.root,
                   c.namespace,
                   %{"op" => "get", "key" => candidate_key},
                   Ipse.Usage.id()
                 )

        "pending." <> candidate_id = candidate_key

        assert {:ok, link} =
                 C.execute(
                   c.root,
                   c.namespace,
                   %{"op" => "get", "key" => "accept." <> candidate_id},
                   Ipse.Usage.id()
                 )

        if mode == "host-orchestrated" do
          assert current["record"] == nil
          assert link["record"]["value"]["kind"] == "candidate_acceptance_link"
        else
          assert current == original
          assert link["record"] == nil

          if mode == "host-orchestrated-cancel",
            do: File.write!(Path.join(c.base, "orchestrated-revoke-key"), candidate_key)
        end
      end
    end

    if System.get_env("IPSE_TEST_ACCEPTANCE_SWITCH") == "1" do
      second_text = "A distinct synthetic candidate after the first decision"
      now = System.system_time(:millisecond)

      assert {:ok, second_key, second_value} =
               Records.capture(
                 %{
                   "text" => second_text,
                   "category" => "ordinary",
                   "reason" => "synthetic switch control",
                   "event_at_ms" => nil
                 },
                 proof,
                 now
               )

      second_opts = %{
        opts
        | now_ms: now,
          request: %{
            "op" => "commit",
            "expected_generation" => changed_root["generation"],
            "advance_floor" => true,
            "changes" => [
              %{"key" => second_key, "expected_revision" => 0, "value" => second_value}
            ]
          }
      }

      assert {:ok, _} = publish(c, second_opts, scope(c, false))
      fixture_path = Path.join(c.base, "pending-management.json")
      fixture = fixture_path |> File.read!() |> Jason.decode!() |> Map.put("key", second_key)
      File.write!(fixture_path, Jason.encode!(fixture))
      File.write!(Path.join(c.cwd, "source-switch-after-decision.arm"), "armed")

      args =
        ["--management-review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [
            Path.expand("test/support/pending_acceptance_management.exs"),
            c.base,
            "host-loss-after"
          ]

      running = Task.async(fn -> System.cmd(driver, args, stderr_to_stdout: true) end)
      marker = Path.join(c.cwd, "source-switch-after-decision.ready")
      assert :ok = wait_file(marker, System.monotonic_time(:millisecond) + 15_000)
      source_pid = source_holder(source_lock_path)
      assert is_integer(source_pid)
      assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(source_pid)])
      File.write!(Path.join(c.cwd, "source-switch-after-decision.go"), "go")
      {output, status} = Task.await(running, 20_000)
      assert status == 0, output
      assert output =~ "PENDING_MANAGEMENT_REVIEW_HOST-LOSS-AFTER_PASSED"

      assert {:ok, removed} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => second_key},
                 Ipse.Usage.id()
               )

      assert removed["record"] === nil
      "pending." <> second_id = second_key

      assert {:ok, linked} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => "accept." <> second_id},
                 Ipse.Usage.id()
               )

      assert linked["record"]["value"]["kind"] === "candidate_acceptance_link"
      File.rm!(Path.join(c.cwd, "source-switch-after-decision.arm"))
      File.rm!(Path.join(c.cwd, "source-switch-after-decision.ready"))
      File.rm!(Path.join(c.cwd, "source-switch-after-decision.go"))

      third_text = "A third synthetic candidate for writer loss"
      now = System.system_time(:millisecond)

      assert {:ok, third_key, third_value} =
               Records.capture(
                 %{
                   "text" => third_text,
                   "category" => "ordinary",
                   "reason" => "synthetic writer control",
                   "event_at_ms" => nil
                 },
                 proof,
                 now
               )

      third_opts = %{
        opts
        | now_ms: now,
          request: %{
            "op" => "commit",
            "expected_generation" => linked["generation"],
            "advance_floor" => true,
            "changes" => [%{"key" => third_key, "expected_revision" => 0, "value" => third_value}]
          }
      }

      assert {:ok, _} = publish(c, third_opts, scope(c, false))
      File.write!(fixture_path, Jason.encode!(Map.put(fixture, "key", third_key)))
      File.write!(Path.join(c.cwd, "source-switch-after-decision.arm"), "armed")

      writer_args =
        ["--management-review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [
            Path.expand("test/support/pending_acceptance_management.exs"),
            c.base,
            "host-writer-after"
          ]

      {writer_output, writer_status} = System.cmd(driver, writer_args, stderr_to_stdout: true)
      assert writer_status == 0, writer_output
      assert writer_output =~ "PENDING_MANAGEMENT_REVIEW_HOST-WRITER-AFTER_PASSED"
      assert File.exists?(Path.join(c.base, "pending-host-writer-after-writer-killed"))

      assert {:ok, third_pending} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => third_key},
                 Ipse.Usage.id()
               )

      "pending." <> third_id = third_key

      assert {:ok, third_link} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => "accept." <> third_id},
                 Ipse.Usage.id()
               )

      assert is_nil(third_pending["record"]) != is_nil(third_link["record"])
      File.rm!(Path.join(c.cwd, "source-switch-after-decision.arm"))

      now = System.system_time(:millisecond)

      assert {:ok, fourth_key, fourth_value} =
               Records.capture(
                 %{
                   "text" => "A fourth synthetic candidate for post-rename writer loss",
                   "category" => "ordinary",
                   "reason" => "synthetic writer control",
                   "event_at_ms" => nil
                 },
                 proof,
                 now
               )

      fourth_opts = %{
        opts
        | now_ms: now,
          request: %{
            "op" => "commit",
            "expected_generation" => third_link["generation"],
            "advance_floor" => true,
            "changes" => [
              %{"key" => fourth_key, "expected_revision" => 0, "value" => fourth_value}
            ]
          }
      }

      assert {:ok, _} = publish(c, fourth_opts, scope(c, false))
      File.write!(fixture_path, Jason.encode!(Map.put(fixture, "key", fourth_key)))
      File.write!(Path.join(c.cwd, "source-switch-after-rename.arm"), "armed")

      renamed_args =
        ["--management-review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [
            Path.expand("test/support/pending_acceptance_management.exs"),
            c.base,
            "host-writer-renamed"
          ]

      {renamed_output, renamed_status} = System.cmd(driver, renamed_args, stderr_to_stdout: true)
      assert renamed_status == 0, renamed_output
      assert renamed_output =~ "PENDING_MANAGEMENT_REVIEW_HOST-WRITER-RENAMED_PASSED"
      assert File.exists?(Path.join(c.base, "pending-host-writer-renamed-writer-killed"))

      assert {:ok, fourth_pending} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => fourth_key},
                 Ipse.Usage.id()
               )

      "pending." <> fourth_id = fourth_key

      assert {:ok, fourth_link} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => "accept." <> fourth_id},
                 Ipse.Usage.id()
               )

      assert fourth_pending["record"] == nil
      assert fourth_link["record"]["value"]["kind"] == "candidate_acceptance_link"
      File.rm!(Path.join(c.cwd, "source-switch-after-rename.arm"))

      now = System.system_time(:millisecond)

      assert {:ok, fifth_key, fifth_value} =
               Records.capture(
                 %{
                   "text" => "A fifth synthetic candidate for post-sync writer loss",
                   "category" => "ordinary",
                   "reason" => "synthetic writer control",
                   "event_at_ms" => nil
                 },
                 proof,
                 now
               )

      fifth_opts = %{
        opts
        | now_ms: now,
          request: %{
            "op" => "commit",
            "expected_generation" => fourth_link["generation"],
            "advance_floor" => true,
            "changes" => [
              %{"key" => fifth_key, "expected_revision" => 0, "value" => fifth_value}
            ]
          }
      }

      assert {:ok, _} = publish(c, fifth_opts, scope(c, false))
      File.write!(fixture_path, Jason.encode!(Map.put(fixture, "key", fifth_key)))
      File.write!(Path.join(c.cwd, "source-switch-after-sync.arm"), "armed")

      synced_args =
        ["--management-review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [
            Path.expand("test/support/pending_acceptance_management.exs"),
            c.base,
            "host-writer-synced"
          ]

      {synced_output, synced_status} = System.cmd(driver, synced_args, stderr_to_stdout: true)
      assert synced_status == 0, synced_output
      assert synced_output =~ "PENDING_MANAGEMENT_REVIEW_HOST-WRITER-SYNCED_PASSED"
      assert File.exists?(Path.join(c.base, "pending-host-writer-synced-writer-killed"))

      assert {:ok, fifth_pending} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => fifth_key},
                 Ipse.Usage.id()
               )

      "pending." <> fifth_id = fifth_key

      assert {:ok, fifth_link} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => "accept." <> fifth_id},
                 Ipse.Usage.id()
               )

      assert fifth_pending["record"] == nil
      assert fifth_link["record"]["value"]["kind"] == "candidate_acceptance_link"
      File.rm!(Path.join(c.cwd, "source-switch-after-sync.arm"))
      File.rm!(Path.join(c.cwd, "source-switch-after-sync.ready"))
      File.rm!(Path.join(c.cwd, "source-switch-after-sync.go"))

      now = System.system_time(:millisecond)

      assert {:ok, sixth_key, sixth_value} =
               Records.capture(
                 %{
                   "text" => "A sixth synthetic candidate for post-sync source loss",
                   "category" => "ordinary",
                   "reason" => "synthetic source owner control",
                   "event_at_ms" => nil
                 },
                 proof,
                 now
               )

      sixth_opts = %{
        opts
        | now_ms: now,
          request: %{
            "op" => "commit",
            "expected_generation" => fifth_link["generation"],
            "advance_floor" => true,
            "changes" => [
              %{"key" => sixth_key, "expected_revision" => 0, "value" => sixth_value}
            ]
          }
      }

      assert {:ok, _} = publish(c, sixth_opts, scope(c, false))
      File.write!(fixture_path, Jason.encode!(Map.put(fixture, "key", sixth_key)))
      File.write!(Path.join(c.cwd, "source-switch-after-sync.arm"), "armed")

      source_args =
        ["--management-review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [
            Path.expand("test/support/pending_acceptance_management.exs"),
            c.base,
            "host-loss-synced"
          ]

      running = Task.async(fn -> System.cmd(driver, source_args, stderr_to_stdout: true) end)
      marker = Path.join(c.cwd, "source-switch-after-sync.ready")
      assert :ok = wait_file(marker, System.monotonic_time(:millisecond) + 15_000)
      source_pid = source_holder(source_lock_path)
      assert is_integer(source_pid)
      assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(source_pid)])
      File.write!(Path.join(c.cwd, "source-switch-after-sync.go"), "go")
      {source_output, source_status} = Task.await(running, 20_000)
      assert source_status == 0, source_output
      assert source_output =~ "PENDING_MANAGEMENT_REVIEW_HOST-LOSS-SYNCED_PASSED"

      assert {:ok, sixth_pending} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => sixth_key},
                 Ipse.Usage.id()
               )

      "pending." <> sixth_id = sixth_key

      assert {:ok, sixth_link} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => "accept." <> sixth_id},
                 Ipse.Usage.id()
               )

      assert sixth_pending["record"] == nil
      assert sixth_link["record"]["value"]["kind"] == "candidate_acceptance_link"
      File.rm!(Path.join(c.cwd, "source-switch-after-sync.arm"))

      now = System.system_time(:millisecond)

      assert {:ok, seventh_key, seventh_value} =
               Records.capture(
                 %{
                   "text" => "A seventh synthetic candidate for result journal loss",
                   "category" => "ordinary",
                   "reason" => "synthetic result control",
                   "event_at_ms" => nil
                 },
                 proof,
                 now
               )

      seventh_opts = %{
        opts
        | now_ms: now,
          request: %{
            "op" => "commit",
            "expected_generation" => sixth_link["generation"],
            "advance_floor" => true,
            "changes" => [
              %{"key" => seventh_key, "expected_revision" => 0, "value" => seventh_value}
            ]
          }
      }

      assert {:ok, _} = publish(c, seventh_opts, scope(c, false))
      File.write!(fixture_path, Jason.encode!(Map.put(fixture, "key", seventh_key)))

      result_args =
        ["--management-review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [
            Path.expand("test/support/pending_acceptance_management.exs"),
            c.base,
            "host-writer-result"
          ]

      {result_output, result_status} = System.cmd(driver, result_args, stderr_to_stdout: true)
      assert result_status == 0, result_output
      assert result_output =~ "PENDING_MANAGEMENT_REVIEW_HOST-WRITER-RESULT_PASSED"
      assert File.exists?(Path.join(c.base, "pending-host-writer-result-writer-killed"))

      assert {:ok, seventh_pending} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => seventh_key},
                 Ipse.Usage.id()
               )

      "pending." <> seventh_id = seventh_key

      assert {:ok, seventh_link} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => "accept." <> seventh_id},
                 Ipse.Usage.id()
               )

      assert seventh_pending["record"] == nil
      assert seventh_link["record"]["value"]["kind"] == "candidate_acceptance_link"

      now = System.system_time(:millisecond)

      assert {:ok, eighth_key, eighth_value} =
               Records.capture(
                 %{
                   "text" => "An eighth synthetic candidate for interrupted result append",
                   "category" => "ordinary",
                   "reason" => "synthetic append control",
                   "event_at_ms" => nil
                 },
                 proof,
                 now
               )

      eighth_opts = %{
        opts
        | now_ms: now,
          request: %{
            "op" => "commit",
            "expected_generation" => seventh_link["generation"],
            "advance_floor" => true,
            "changes" => [
              %{"key" => eighth_key, "expected_revision" => 0, "value" => eighth_value}
            ]
          }
      }

      assert {:ok, _} = publish(c, eighth_opts, scope(c, false))
      File.write!(fixture_path, Jason.encode!(Map.put(fixture, "key", eighth_key)))

      write_args =
        ["--management-review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [
            Path.expand("test/support/pending_acceptance_management.exs"),
            c.base,
            "host-writer-result-after-write"
          ]

      {write_output, write_status} = System.cmd(driver, write_args, stderr_to_stdout: true)
      assert write_status == 0, write_output
      assert write_output =~ "PENDING_MANAGEMENT_REVIEW_HOST-WRITER-RESULT-AFTER-WRITE_PASSED"
      assert File.exists?(Path.join(c.base, "pending-host-writer-result-after-write-killed"))

      assert {:ok, eighth_pending} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => eighth_key},
                 Ipse.Usage.id()
               )

      "pending." <> eighth_id = eighth_key

      assert {:ok, eighth_link} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => "accept." <> eighth_id},
                 Ipse.Usage.id()
               )

      assert eighth_pending["record"] == nil
      assert eighth_link["record"]["value"]["kind"] == "candidate_acceptance_link"

      now = System.system_time(:millisecond)

      assert {:ok, ninth_key, ninth_value} =
               Records.capture(
                 %{
                   "text" => "A ninth synthetic candidate for a torn result append",
                   "category" => "ordinary",
                   "reason" => "synthetic partial append control",
                   "event_at_ms" => nil
                 },
                 proof,
                 now
               )

      ninth_opts = %{
        opts
        | now_ms: now,
          request: %{
            "op" => "commit",
            "expected_generation" => eighth_link["generation"],
            "advance_floor" => true,
            "changes" => [
              %{"key" => ninth_key, "expected_revision" => 0, "value" => ninth_value}
            ]
          }
      }

      assert {:ok, _} = publish(c, ninth_opts, scope(c, false))
      File.write!(fixture_path, Jason.encode!(Map.put(fixture, "key", ninth_key)))

      partial_args =
        ["--management-review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [
            Path.expand("test/support/pending_acceptance_management.exs"),
            c.base,
            "host-writer-result-partial"
          ]

      {partial_output, partial_status} = System.cmd(driver, partial_args, stderr_to_stdout: true)
      assert partial_status == 0, partial_output
      assert partial_output =~ "PENDING_MANAGEMENT_REVIEW_HOST-WRITER-RESULT-PARTIAL_PASSED"
      assert File.exists?(Path.join(c.base, "pending-host-writer-result-partial-killed"))

      assert {:ok, ninth_pending} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => ninth_key},
                 Ipse.Usage.id()
               )

      "pending." <> ninth_id = ninth_key

      assert {:ok, ninth_link} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => "accept." <> ninth_id},
                 Ipse.Usage.id()
               )

      assert ninth_pending["record"] == nil
      assert ninth_link["record"]["value"]["kind"] == "candidate_acceptance_link"

      now = System.system_time(:millisecond)

      assert {:ok, tenth_key, tenth_value} =
               Records.capture(
                 %{
                   "text" => "A tenth synthetic candidate for host orchestration",
                   "category" => "ordinary",
                   "reason" => "synthetic orchestration control",
                   "event_at_ms" => nil
                 },
                 proof,
                 now
               )

      tenth_opts = %{
        opts
        | now_ms: now,
          request: %{
            "op" => "commit",
            "expected_generation" => ninth_link["generation"],
            "advance_floor" => true,
            "changes" => [
              %{"key" => tenth_key, "expected_revision" => 0, "value" => tenth_value}
            ]
          }
      }

      assert {:ok, _} = publish(c, tenth_opts, scope(c, false))
      File.write!(fixture_path, Jason.encode!(Map.put(fixture, "key", tenth_key)))

      orchestration_args =
        ["--management-review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [
            Path.expand("test/support/pending_acceptance_management.exs"),
            c.base,
            "host-orchestrated"
          ]

      {orchestration_output, orchestration_status} =
        System.cmd(driver, orchestration_args, stderr_to_stdout: true)

      assert orchestration_status == 0, orchestration_output
      assert orchestration_output =~ "PENDING_MANAGEMENT_REVIEW_HOST-ORCHESTRATED_PASSED"

      assert {:ok, tenth_pending} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => tenth_key},
                 Ipse.Usage.id()
               )

      "pending." <> tenth_id = tenth_key

      assert {:ok, tenth_link} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => "accept." <> tenth_id},
                 Ipse.Usage.id()
               )

      assert tenth_pending["record"] == nil
      assert tenth_link["record"]["value"]["kind"] == "candidate_acceptance_link"

      now = System.system_time(:millisecond)

      assert {:ok, cancelled_key, cancelled_value} =
               Records.capture(
                 %{
                   "text" => "A synthetic candidate for cancelled host review",
                   "category" => "ordinary",
                   "reason" => "synthetic cancellation control",
                   "event_at_ms" => nil
                 },
                 proof,
                 now
               )

      cancelled_opts = %{
        opts
        | now_ms: now,
          request: %{
            "op" => "commit",
            "expected_generation" => tenth_link["generation"],
            "advance_floor" => true,
            "changes" => [
              %{"key" => cancelled_key, "expected_revision" => 0, "value" => cancelled_value}
            ]
          }
      }

      assert {:ok, _} = publish(c, cancelled_opts, scope(c, false))

      assert {:ok, before_cancel} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => cancelled_key},
                 Ipse.Usage.id()
               )

      File.write!(fixture_path, Jason.encode!(Map.put(fixture, "key", cancelled_key)))

      cancel_args =
        ["--management-review-cancel", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [
            Path.expand("test/support/pending_acceptance_management.exs"),
            c.base,
            "host-orchestrated-cancel"
          ]

      {cancel_output, cancel_status} = System.cmd(driver, cancel_args, stderr_to_stdout: true)
      assert cancel_status == 0, cancel_output
      assert cancel_output =~ "PENDING_MANAGEMENT_REVIEW_HOST-ORCHESTRATED-CANCEL_PASSED"

      assert {:ok, cancelled} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => cancelled_key},
                 Ipse.Usage.id()
               )

      assert cancelled == before_cancel
      "pending." <> cancelled_id = cancelled_key

      assert {:ok, absent_link} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => "accept." <> cancelled_id},
                 Ipse.Usage.id()
               )

      assert absent_link["record"] == nil
    end

    assert {:ok, %{"epoch" => 6}} =
             Ipse.Extension.Consent.replace(
               control,
               c.binding["project_id"],
               5,
               denied_sources,
               System.system_time(:millisecond)
             )

    assert {:ok, denied_pin} =
             Ipse.Extension.SemanticConsent.admit(
               %{"epoch" => 6, "policy" => denied_sources},
               semantic_context,
               System.system_time(:millisecond)
             )

    denied_admission = %{admission | "pin" => denied_pin, "policy" => denied_sources}
    denied_context = put_in(use_context, [:config, :semantic_admission], denied_admission)

    assert {:error, _} =
             Ipse.Session.ManagedUse.inspect_accepted(
               denied_context,
               link["record"]["value"],
               JSON.digest([note_recipe])
             )

    assert {:ok, %{"epoch" => 7}} =
             Ipse.Extension.Consent.replace(
               control,
               c.binding["project_id"],
               6,
               denied_read,
               System.system_time(:millisecond)
             )

    assert {:ok, denied_read_pin} =
             Ipse.Extension.SemanticConsent.admit(
               %{"epoch" => 7, "policy" => denied_read},
               semantic_context,
               System.system_time(:millisecond)
             )

    read_denied = %{admission | "pin" => denied_read_pin, "policy" => denied_read}
    read_denied_context = put_in(use_context, [:config, :semantic_admission], read_denied)

    assert {:error, _} =
             Ipse.Session.ManagedUse.inspect_accepted(
               read_denied_context,
               link["record"]["value"],
               JSON.digest([note_recipe])
             )

    assert {:ok, %{"epoch" => 8}} =
             Ipse.Extension.Consent.replace(
               control,
               c.binding["project_id"],
               7,
               policy,
               System.system_time(:millisecond)
             )

    assert {:ok, renewed_pin} =
             Ipse.Extension.SemanticConsent.admit(
               %{"epoch" => 8, "policy" => policy},
               semantic_context,
               System.system_time(:millisecond)
             )

    renewed_admission = %{admission | "pin" => renewed_pin}
    renewed_context = put_in(use_context, [:config, :semantic_admission], renewed_admission)

    assert {:ok, _} =
             Ipse.Session.ManagedUse.inspect_accepted(
               renewed_context,
               link["record"]["value"],
               JSON.digest([note_recipe])
             )

    if System.get_env("IPSE_TEST_ACCEPTANCE_ORCHESTRATION") == "1" do
      candidate_key = File.read!(Path.join(c.base, "orchestrated-revoke-key"))

      assert {:ok, original} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => candidate_key},
                 Ipse.Usage.id()
               )

      fixture_path = Path.join(c.base, "pending-management.json")
      fixture = fixture_path |> File.read!() |> Jason.decode!() |> Map.put("key", candidate_key)
      File.write!(fixture_path, Jason.encode!(fixture))

      args =
        ["--management-review-race", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [
            Path.expand("test/support/pending_acceptance_management.exs"),
            c.base,
            "host-orchestrated-revoked"
          ]

      running = Task.async(fn -> System.cmd(driver, args, stderr_to_stdout: true) end)
      marker = Path.join(c.base, "management-review-input-ready")
      release = Path.join(c.base, "management-review-race-complete")

      {output, status} =
        try do
          assert :ok = wait_file(marker, System.monotonic_time(:millisecond) + 10_000)

          assert {:ok, %{"epoch" => 9}} =
                   Ipse.Extension.Consent.revoke(control, c.binding["project_id"], 8)

          File.write!(release, "done")
          Task.await(running, 15_000)
        after
          File.write!(release, "done")
          if Process.alive?(running.pid), do: Task.yield(running, 5_000)
        end

      assert status == 0, output
      assert output =~ "PENDING_MANAGEMENT_REVIEW_HOST-ORCHESTRATED-REVOKED_PASSED"

      assert {:ok, current} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => candidate_key},
                 Ipse.Usage.id()
               )

      assert current == original
      "pending." <> candidate_id = candidate_key

      assert {:ok, absent} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{"op" => "get", "key" => "accept." <> candidate_id},
                 Ipse.Usage.id()
               )

      assert absent["record"] == nil
    else
      assert {:ok, %{"epoch" => 9}} =
               Ipse.Extension.Consent.revoke(control, c.binding["project_id"], 8)
    end

    assert {:error, _} =
             Ipse.Session.ManagedUse.inspect_accepted(
               use_context,
               link["record"]["value"],
               JSON.digest([note_recipe])
             )

    assert {:error, _} =
             Ipse.Session.ManagedUse.inspect_accepted_reference(use_context, dependency)

    assert {:error, _} =
             Ipse.Session.ManagedUse.with_accepted_reference(
               use_context,
               dependency,
               fn _, _, _ -> flunk("revoked acceptance reached retained callback") end
             )

    assert {:error, _} =
             Ipse.Session.ManagedUse.inspect_accepted(
               renewed_context,
               link["record"]["value"],
               JSON.digest([note_recipe])
             )

    if System.get_env("IPSE_TEST_REAL_ACCEPTANCE_POLICY") == "1" do
      args =
        ["--knowledge", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++ [Path.expand("test/support/acceptance_reenable.exs"), c.home, c.cwd]

      {output, status} = System.cmd(driver, args, stderr_to_stdout: true)
      assert status == 0, output
      assert output =~ "ACCEPTANCE_REAL_CONSENT_ENABLED"

      assert {:ok, snapshot} =
               Ipse.Extension.Consent.existing_snapshot(control, c.binding["project_id"])

      assert snapshot["epoch"] > 9
      assert Ipse.Extension.SemanticConsent.policy?(snapshot["policy"])

      assert {:ok, _} =
               Identity.with_existing_domain_auth(
                 c.home,
                 c.cwd,
                 c.binding,
                 domain,
                 fn cap, catalog ->
                   Ipse.Extension.Consent.with_policy(
                     control,
                     c.binding["project_id"],
                     snapshot["epoch"],
                     JSON.digest([snapshot["policy"]]),
                     System.system_time(:millisecond),
                     fn current ->
                       ObservedRead.with_accepted_decision(
                         c.root,
                         c.namespace,
                         event,
                         cap,
                         catalog,
                         note_recipe,
                         System.system_time(:millisecond),
                         fn observed ->
                           Ipse.Session.PendingAcceptance.accepted_use_policy(
                             event,
                             observed["metadata"],
                             current["policy"],
                             note_recipe,
                             System.system_time(:millisecond)
                           )
                         end
                       )
                     end
                   )
                 end
               )

      if runtime = System.get_env("IPSE_TEST_BOUND_HOST_RUNTIME") do
        fixture_path = Path.join(c.base, "real-policy-bound-fixture.json")

        File.write!(
          fixture_path,
          Jason.encode!(%{
            "home" => c.home,
            "cwd" => c.cwd,
            "binding" => c.binding,
            "project" => c.binding["project_id"],
            "namespace" => c.namespace,
            "link" => link["record"]["value"],
            "event" => event,
            "recipe" => note_recipe,
            "history_dir" => history_dir,
            "admission" => current_admission,
            "current_epoch" => snapshot["epoch"],
            "current_policy_sha256" => JSON.digest([snapshot["policy"]])
          })
        )

        args =
          ["--knowledge", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
            paths ++
            [
              "-pa",
              Path.join(runtime, "_build/test/lib/ipse/ebin"),
              "test/support/bound_host_entry.exs"
            ]

        for {expire, lose_source, lose_journal} <-
              [
                {"0", "0", "0"},
                {"1", "0", "0"},
                {"0", "0", "0"},
                {"0", "1", "0"},
                {"0", "0", "0"},
                {"0", "0", "1"},
                {"0", "0", "0"}
              ] do
          {output, status} =
            System.cmd(driver, args,
              cd: runtime,
              env: [
                {"IPSE_BOUND_HOST_FIXTURE", fixture_path},
                {"IPSE_BOUND_HOST_SAME_PROJECT", "1"},
                {"IPSE_BOUND_HOST_REFERENCE", "1"},
                {"IPSE_BOUND_HOST_NOTICE", System.get_env("IPSE_TEST_BOUND_HOST_NOTICE") || "0"},
                {"IPSE_BOUND_EXPIRE_BEFORE_ACTIVATION", expire},
                {"IPSE_BOUND_LOSE_SOURCE_BEFORE_ACTIVATION", lose_source},
                {"IPSE_BOUND_LOSE_JOURNAL_BEFORE_ACTIVATION", lose_journal},
                {"IPSE_ACCEPTED_LEASE_MODULE_ONLY", "1"},
                {"IPSE_SHARE_TTY_SIX", "1"},
                {"ERL_FLAGS", "+S 2:2"}
              ],
              stderr_to_stdout: true
            )

          assert status == 0, output
          assert output =~ "1 passed"

          if expire == "0" and lose_source == "0" and lose_journal == "0" do
            assert output =~ "SYNTHETIC_ACCEPTED_LEASE_DISPLAY"
          else
            if expire == "1", do: assert(output =~ "BOUND_BEFORE_ACTIVATION")
            if lose_source == "1", do: assert(output =~ "BOUND_SOURCE_OWNER_KILLED")
            if lose_journal == "1", do: assert(output =~ "BOUND_JOURNAL_OWNER_KILLED")
            refute output =~ "SYNTHETIC_ACCEPTED_LEASE_DISPLAY"
            assert output =~ "BOUND_CLEANUP_UNCONFIRMED" or output =~ "BOUND_HOST_TERMINATED"
          end
        end
      end
    end
  end

  for count <- [27, 60, 120] do
    @tag :pending_split_geometry
    test "acceptance page geometry with #{count} signed rows", c do
      test_owner = self()

      Enum.each(1..unquote(count), fn n ->
        assert {:ok, _} = publish(c, options(n, n - 1), scope(c, n == 1), first: n == 1)
      end)

      opts = options(200, unquote(count), "proposal")
      assert {:ok, _} = publish(c, opts, scope(c, false))
      key = hd(opts.request["changes"])["key"]
      request = %{"op" => "get_record", "key" => key}

      assert {:ok, geometry} =
               Identity.with_existing_domain_auth(
                 c.home,
                 c.cwd,
                 c.binding,
                 Map.take(scope(c, false), [:namespace, :format]),
                 fn cap, catalog ->
                   ObservedRead.with_managed_proposal_plan(
                     c.root,
                     c.namespace,
                     request,
                     cap,
                     catalog,
                     opts.recipe,
                     fn observed, read ->
                       {_, observed_units, _} = Process.get({C, :managed_read})

                       cached_request = %{
                         "op" => "neighbors",
                         "request" => %{
                           "version" => 1,
                           "prefix" => ManagedPages.prefix(:live),
                           "fence_bytes" => ManagedPages.width(:live),
                           "needle" => ManagedPages.live_identity(key)
                         }
                       }

                       assert {:error, :managed_read_refused} =
                                Task.async(fn -> read.(cached_request) end) |> Task.await()

                       send(test_owner, {:pending_geometry_escaped, read, cached_request})
                       record = observed["observation"]["value"]["record"]
                       original = observed["metadata"]["lineage"]
                       candidate = record["value"]["id"]

                       lineage =
                         JSON.digest([
                           "ipse-knowledge",
                           1,
                           "accepted_decision",
                           candidate,
                           original
                         ])

                       note_key = "note." <> lineage
                       link_key = "accept." <> candidate
                       assert {:ok, nil} = read.(note_key)
                       assert {:ok, nil} = read.(link_key)
                       {_, destination_units, _} = Process.get({C, :managed_read})
                       at = observed["metadata"]["first_admitted_ms"] + 1
                       deadline = at + 90 * 86_400_000

                       anchor = %{
                         "clocks" => [at, deadline, nil, nil],
                         "choice" => nil,
                         "retirement" => nil
                       }

                       hashes = [
                         lineage,
                         JSON.sha256("synthetic accepted value"),
                         observed["metadata"]["recipe_sha256"],
                         observed["metadata"]["policy_sha256"]
                       ]

                       live =
                         Enum.map(
                           hashes,
                           &Base.url_encode64(Base.decode16!(&1, case: :lower), padding: false)
                         ) ++
                           [
                             String.downcase(Integer.to_string(at, 36)),
                             String.downcase(Integer.to_string(deadline, 36)),
                             0,
                             0
                           ]

                       assert {:ok, anchor_plan} =
                                ManagedPages.Planner.plan(cap, :anchor, [{lineage, anchor}], read)

                       {_, anchor_units, _} = Process.get({C, :managed_read})

                       assert {:ok, live_plan} =
                                ManagedPages.Planner.plan(
                                  cap,
                                  :live,
                                  [
                                    {ManagedPages.live_identity(key), nil},
                                    {ManagedPages.live_identity(note_key), live}
                                  ],
                                  read
                                )

                       {_, units, _} = Process.get({C, :managed_read})
                       changes = anchor_plan.changes ++ live_plan.changes

                       {:ok,
                        %{
                          units: units,
                          phases: [observed_units, destination_units, anchor_units, units],
                          changes: length(changes),
                          sizes:
                            Enum.map(
                              changes,
                              &if(&1.body, do: ManagedPages.encoded_size(&1.body), else: nil)
                            )
                        }}
                     end
                   )
                 end
               )

      IO.puts("PENDING_POPULATED_GEOMETRY rows=#{unquote(count)} #{inspect(geometry)}")
      assert geometry.units <= 28 and geometry.changes <= 5
      assert_receive {:pending_geometry_escaped, escaped, cached_request}
      assert {:error, :managed_read_refused} = escaped.(cached_request)
    end
  end

  @tag :pending_reuse_lease
  test "reused pending-page evidence refuses after read-budget exhaustion", c do
    opts = options(1, 0, "proposal")
    assert {:ok, _} = publish(c, opts, scope(c), first: true)
    key = hd(opts.request["changes"])["key"]
    request = %{"op" => "get_record", "key" => key}

    live_request = %{
      "op" => "neighbors",
      "request" => %{
        "version" => 1,
        "prefix" => ManagedPages.prefix(:live),
        "fence_bytes" => ManagedPages.width(:live),
        "needle" => ManagedPages.live_identity(key)
      }
    }

    assert {:error, _} =
             Identity.with_existing_domain_auth(
               c.home,
               c.cwd,
               c.binding,
               Map.take(scope(c, false), [:namespace, :format]),
               fn cap, catalog ->
                 ObservedRead.with_managed_proposal_plan(
                   c.root,
                   c.namespace,
                   request,
                   cap,
                   catalog,
                   opts.recipe,
                   fn _, read ->
                     for _ <- 1..33, do: read.("missing")
                     assert {:error, :managed_read_refused} = read.(live_request)
                     {:ok, :must_not_escape}
                   end
                 )
               end
             )
  end

  @tag :pending_reuse_lease
  test "reused pending-page evidence refuses after native Collection owner loss", c do
    opts = options(1, 0, "proposal")
    assert {:ok, _} = publish(c, opts, scope(c), first: true)
    key = hd(opts.request["changes"])["key"]
    request = %{"op" => "get_record", "key" => key}

    live_request = %{
      "op" => "neighbors",
      "request" => %{
        "version" => 1,
        "prefix" => ManagedPages.prefix(:live),
        "fence_bytes" => ManagedPages.width(:live),
        "needle" => ManagedPages.live_identity(key)
      }
    }

    assert {:unknown, _} =
             Identity.with_existing_domain_auth(
               c.home,
               c.cwd,
               c.binding,
               Map.take(scope(c, false), [:namespace, :format]),
               fn cap, catalog ->
                 ObservedRead.with_managed_proposal_plan(
                   c.root,
                   c.namespace,
                   request,
                   cap,
                   catalog,
                   opts.recipe,
                   fn _, read ->
                     owner = Process.get({C, :lock_held})
                     {:os_pid, native} = Port.info(owner.port, :os_pid)
                     assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(native)])
                     assert {:error, :managed_read_refused} = read.(live_request)
                     {:ok, :must_not_escape}
                   end
                 )
               end
             )
  end

  @tag :held_target_read
  test "live policy keeps the exact signed target and all three owners during review continuation",
       c do
    alias Ipse.Extension.Consent
    opts = options(1, 0)
    assert {:ok, _} = publish(c, opts, scope(c), first: true)
    selected = %{"op" => "get_record", "key" => hd(opts.request["changes"])["key"]}
    domain = Map.take(scope(c, false), [:namespace, :format])
    control = c.base <> "/review-control"
    project = c.binding["project_id"]
    now = System.system_time(:millisecond)

    policy = %{
      "version" => 1,
      "project" => project,
      "artifact_sha256" => JSON.sha256("artifact"),
      "source_sha256" => JSON.sha256("source"),
      "operations" => ["knowledge.capture"],
      "settings" => %{},
      "limits" => Map.new(Consent.resources(), &{&1, 5}),
      "period_ms" => 1000,
      "expires_at_ms" => now + 60_000,
      "headless" => false
    }

    assert {:ok, _} = Consent.replace(control, project, 0, policy, now)
    hash = JSON.digest([policy])

    assert {:ok, prior} =
             Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                     catalog ->
               ObservedRead.managed_record(
                 c.root,
                 c.namespace,
                 selected,
                 cap,
                 catalog,
                 opts.recipe
               )
             end)

    assert {:ok, :displayed} =
             Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                     catalog ->
               Consent.with_existing_policy(control, project, 1, hash, now, fn snapshot ->
                 assert snapshot["policy"] === policy

                 ObservedRead.with_managed_record(
                   c.root,
                   c.namespace,
                   selected,
                   cap,
                   catalog,
                   opts.recipe,
                   fn observed ->
                     assert observed === prior
                     assert Process.get({Identity, :lock_held}) === true
                     assert Process.get({Consent, :lock_held}) != nil
                     assert Process.get({C, :lock_held}) != nil
                     assert {:ok, caps} = Ipse.Runner.Transaction.retained_share_stack()
                     assert Enum.map(caps, & &1.depth) == [1, 2, 3]
                     {:ok, :displayed}
                   end
                 )
               end)
             end)

    assert {:error, :consent_read_refused} =
             Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn _, _ ->
               Consent.with_existing_policy(
                 control,
                 project,
                 1,
                 JSON.sha256("wrong policy"),
                 now,
                 fn _ ->
                   flunk("mismatched consent reached the continuation")
                 end
               )
             end)
  end

  @tag :held_target_read
  test "revoked management retains Identity Consent and Collection around the same signed target",
       c do
    alias Ipse.Extension.Consent
    opts = options(1, 0)
    assert {:ok, _} = publish(c, opts, scope(c), first: true)
    key = hd(opts.request["changes"])["key"]
    selected = %{"op" => "get_record", "key" => key}
    domain = Map.take(scope(c, false), [:namespace, :format])
    control = c.base <> "/control"
    project = c.binding["project_id"]

    policy = %{
      "version" => 1,
      "project" => project,
      "artifact_sha256" => JSON.sha256("artifact"),
      "source_sha256" => JSON.sha256("source"),
      "operations" => ["knowledge.capture"],
      "settings" => %{},
      "limits" => Map.new(Consent.resources(), &{&1, 5}),
      "period_ms" => 1000,
      "expires_at_ms" => 10_000,
      "headless" => false
    }

    assert {:ok, _} = Consent.replace(control, project, 0, policy, 1)
    assert {:ok, %{"epoch" => 2}} = Consent.revoke(control, project, 1)
    fingerprint = Consent.management_sha256(project, 2, nil)

    assert {:ok, prior} =
             Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                     catalog ->
               ObservedRead.managed_record(
                 c.root,
                 c.namespace,
                 selected,
                 cap,
                 catalog,
                 opts.recipe
               )
             end)

    assert {:ok, ^prior} =
             Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                     catalog ->
               Consent.with_existing_management_snapshot(control, project, 2, fingerprint, fn %{
                                                                                                "policy" =>
                                                                                                  nil
                                                                                              } ->
                 ObservedRead.with_managed_record(
                   c.root,
                   c.namespace,
                   selected,
                   cap,
                   catalog,
                   opts.recipe,
                   fn observed ->
                     assert Process.get({C, :lock_held}) != nil
                     assert Process.get({Consent, :lock_held}) != nil
                     assert observed == prior

                     assert observed["metadata"]["valid_until_ms"] <
                              System.system_time(:millisecond)

                     {:ok, observed}
                   end
                 )
               end)
             end)

    assert {:ok, %{"epoch" => 2, "policy" => nil, "sequence" => 0}} =
             Consent.existing_snapshot(control, project)
  end

  @tag :held_target_read
  test "held signed-target callbacks refuse changed bytes and recipe substitution before continuation",
       c do
    opts = options(1, 0)
    assert {:ok, _} = publish(c, opts, scope(c), first: true)
    key = hd(opts.request["changes"])["key"]
    selected = %{"op" => "get_record", "key" => key}

    invoke = fn recipe ->
      Identity.with_existing_domain_auth(
        c.home,
        c.cwd,
        c.binding,
        Map.take(scope(c, false), [:namespace, :format]),
        fn cap, catalog ->
          ObservedRead.with_managed_record(
            c.root,
            c.namespace,
            selected,
            cap,
            catalog,
            recipe,
            fn _ -> flunk("invalid signed target reached continuation") end
          )
        end
      )
    end

    assert {:error, :collection_observation_refused} =
             invoke.(Map.put(opts.recipe, "override_prefix", "other."))

    value = hd(opts.request["changes"])["value"] |> Map.put("text", "substituted")

    assert {:ok, _} =
             C.execute(
               c.root,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 1,
                 "advance_floor" => true,
                 "changes" => [%{"key" => key, "expected_revision" => 1, "value" => value}]
               },
               Ipse.Usage.id()
             )

    assert {:error, :collection_observation_refused} = invoke.(opts.recipe)
  end

  @tag :held_target_regression
  @tag :managed_v4_batch
  test "distinct signed literals share a view without changing their observations", c do
    one = options(1, 0)
    two = options(2, 1)
    assert {:ok, _} = publish(c, one, scope(c), first: true)
    assert {:ok, _} = publish(c, two, scope(c, false))
    first = %{"op" => "get_record", "key" => hd(one.request["changes"])["key"]}
    second = %{"op" => "get_record", "key" => hd(two.request["changes"])["key"]}
    refute first["key"] == second["key"]
    domain = Map.take(scope(c, false), [:namespace, :format])

    assert {:ok, [a, b]} =
             Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                     catalog ->
               ObservedRead.managed_records(
                 c.root,
                 c.namespace,
                 [{first, one.recipe}, {second, two.recipe}],
                 cap,
                 catalog
               )
             end)

    for {request, recipe, expected} <- [{first, one.recipe, a}, {second, two.recipe, b}] do
      assert {:ok, ^expected} =
               Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                       catalog ->
                 ObservedRead.managed_record(c.root, c.namespace, request, cap, catalog, recipe)
               end)
    end

    assert a["observation"]["value"]["record"]["key"] == first["key"]
    assert b["observation"]["value"]["record"]["key"] == second["key"]
  end

  @tag :managed_v4_33_distinct
  @tag timeout: 360_000
  test "33 distinct signed synthetic literals retain order across the 32-record batch boundary",
       c do
    # These trusted synthetic source proofs exercise signed Collection storage,
    # not live Session source ownership or the private Worker scheduler.
    options =
      for n <- 1..33 do
        opts = options(n, n - 1)
        assert {:ok, _} = publish(c, opts, scope(c, n == 1), first: n == 1)
        opts
      end

    selected = Enum.reverse(options)

    requests =
      Enum.map(selected, fn opts ->
        change = hd(opts.request["changes"])
        {%{"op" => "get_record", "key" => change["key"]}, opts.recipe}
      end)

    assert length(Enum.uniq_by(requests, fn {request, _} -> request["key"] end)) == 33
    domain = Map.take(scope(c, false), [:namespace, :format])

    assert {:error, :collection_observation_refused} =
             ObservedRead.managed_records(c.root, c.namespace, requests, nil, %{})

    assert {:ok, observations} =
             Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                     catalog ->
               with {:ok, first} <-
                      ObservedRead.managed_records(
                        c.root,
                        c.namespace,
                        Enum.take(requests, 32),
                        cap,
                        catalog
                      ),
                    {:ok, last} <-
                      ObservedRead.managed_records(
                        c.root,
                        c.namespace,
                        Enum.drop(requests, 32),
                        cap,
                        catalog
                      ) do
                 {:ok, first ++ last}
               end
             end)

    assert length(observations) == 33

    assert Enum.map(observations, &get_in(&1, ["observation", "value", "record", "key"])) ==
             Enum.map(requests, fn {request, _} -> request["key"] end)

    assert Enum.map(observations, &get_in(&1, ["observation", "value", "record", "value"])) ==
             Enum.map(selected, &hd(&1.request["changes"])["value"])

    assert observations
           |> Enum.map(&get_in(&1, ["observation", "witness"]))
           |> Enum.uniq()
           |> length() == 1
  end

  @tag :managed_v4_batch_fence
  test "a lost native owner cannot return any batched literal", c do
    opts = options(1, 0)
    assert {:ok, _} = publish(c, opts, scope(c), first: true)
    request = %{"op" => "get_record", "key" => hd(opts.request["changes"])["key"]}
    domain = Map.take(scope(c, false), [:namespace, :format])
    handler = {__MODULE__, make_ref()}
    owner = self()

    :ok =
      :telemetry.attach(
        handler,
        [:ipse, :extension, :collection, :view_read],
        &__MODULE__.batch_owner_fence/4,
        owner
      )

    try do
      assert {:unknown, :project_identity_lock_lost} =
               Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                       catalog ->
                 result =
                   ObservedRead.managed_records(
                     c.root,
                     c.namespace,
                     [{request, opts.recipe}, {request, opts.recipe}],
                     cap,
                     catalog
                   )

                 send(owner, {:batch_inner_result, result})
                 result
               end)

      assert_receive {:batch_owner_closed, true, true}
      assert_receive {:batch_inner_result, {:error, :collection_observation_refused}}
      assert [] == Registry.lookup(Ipse.Registry, {C.ReadView, owner})
    after
      :telemetry.detach(handler)
    end
  end

  @tag :managed_v4_batch_fence
  test "a root change between two literal reads refuses the entire batch", c do
    one = options(1, 0)
    two = options(2, 1)
    assert {:ok, _} = publish(c, one, scope(c), first: true)
    assert {:ok, _} = publish(c, two, scope(c, false))
    first = %{"op" => "get_record", "key" => hd(one.request["changes"])["key"]}
    second = %{"op" => "get_record", "key" => hd(two.request["changes"])["key"]}
    refute first["key"] == second["key"]
    domain = Map.take(scope(c, false), [:namespace, :format])
    handler = {__MODULE__, make_ref()}
    flag = :atomics.new(1, [])
    owner = self()

    :ok =
      :telemetry.attach(
        handler,
        [:ipse, :extension, :collection, :view_read],
        &__MODULE__.install_batch_root_gate/4,
        {owner, flag}
      )

    task =
      Task.async(fn ->
        Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap, catalog ->
          ObservedRead.managed_records(
            c.root,
            c.namespace,
            [{first, one.recipe}, {second, two.recipe}],
            cap,
            catalog
          )
        end)
      end)

    try do
      assert_receive {:batch_second_record_gate, view}, 10_000

      assert {:ok, _} =
               C.execute(
                 c.root,
                 c.namespace,
                 %{
                   "op" => "commit",
                   "expected_generation" => 2,
                   "advance_floor" => false,
                   "changes" => [
                     %{
                       "key" => "unrelated.root-change",
                       "expected_revision" => 0,
                       "value" => %{"text" => "synthetic changed root"}
                     }
                   ]
                 },
                 Usage.id()
               )

      send(view, :release_batch_second_record)
      assert {:error, :collection_observation_refused} = Task.await(task, 10_000)
      assert [] == Registry.lookup(Ipse.Registry, {C.ReadView, task.pid})
    after
      :telemetry.detach(handler)
      if Process.alive?(task.pid), do: Task.shutdown(task, :brutal_kill)
    end
  end

  def batch_owner_fence(_, _, _, owner) do
    case Process.get({C, :lock_held}) do
      %{port: port, controller: controller} ->
        shared =
          Process.get({Identity, :lock_held}) === true and
            Process.get({Ipse.Runner.Transaction, :controller}) === controller

        send(owner, {:batch_owner_closed, Port.close(port), shared})

      _ ->
        send(owner, {:batch_owner_closed, false, false})
    end
  end

  def install_batch_root_gate(_, _, _, {owner, flag}) do
    if :atomics.compare_exchange(flag, 1, 0, 1) == :ok do
      effect_owner = Ipse.Session.Resources.file_effect_owner()
      [{view, _}] = Registry.lookup(Ipse.Registry, {C.ReadView, effect_owner})

      gate = fn
        4, {:in, {:"$gen_call", _, {_ref, {:borrow, _}}}}, _ ->
          send(owner, {:batch_second_record_gate, self()})
          receive do: (:release_batch_second_record -> :ok)
          5

        count, {:in, {:"$gen_call", _, {_ref, {:borrow, _}}}}, _ ->
          count + 1

        count, _, _ ->
          count
      end

      :ok = :sys.install(view, {gate, 0})
    end
  end

  @tag :managed_v4_batch
  test "bounded literal batch matches independent signed observations and rejects invalid members",
       c do
    opts = options(1, 0)
    assert {:ok, _} = publish(c, opts, scope(c), first: true)
    key = hd(opts.request["changes"])["key"]
    request = %{"op" => "get_record", "key" => key}
    domain = Map.take(scope(c, false), [:namespace, :format])

    assert {:ok, [first, second]} =
             Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                     catalog ->
               ObservedRead.managed_records(
                 c.root,
                 c.namespace,
                 [{request, opts.recipe}, {request, opts.recipe}],
                 cap,
                 catalog
               )
             end)

    assert first === second

    assert {:ok, ^first} =
             Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                     catalog ->
               ObservedRead.managed_record(
                 c.root,
                 c.namespace,
                 request,
                 cap,
                 catalog,
                 opts.recipe
               )
             end)

    assert {:ok, records} =
             Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                     catalog ->
               ObservedRead.managed_records(
                 c.root,
                 c.namespace,
                 List.duplicate({request, opts.recipe}, 32),
                 cap,
                 catalog
               )
             end)

    assert records == List.duplicate(first, 32)

    assert {:error, :collection_observation_refused} =
             ObservedRead.managed_records(c.root, c.namespace, [], nil, %{})

    assert {:error, :collection_observation_refused} =
             ObservedRead.managed_records(
               c.root,
               c.namespace,
               List.duplicate({request, opts.recipe}, 33),
               nil,
               %{}
             )

    missing = %{"op" => "get_record", "key" => "note." <> JSON.sha256("missing batch member")}

    assert {:error, :collection_observation_refused} =
             Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                     catalog ->
               ObservedRead.managed_records(
                 c.root,
                 c.namespace,
                 [{request, opts.recipe}, {missing, opts.recipe}],
                 cap,
                 catalog
               )
             end)

    # A failed read closes its view and cannot poison a later fresh owner scope.
    assert {:ok, [^first]} =
             Identity.with_existing_domain_auth(c.home, c.cwd, c.binding, domain, fn cap,
                                                                                     catalog ->
               ObservedRead.managed_records(
                 c.root,
                 c.namespace,
                 [{request, opts.recipe}],
                 cap,
                 catalog
               )
             end)
  end

  @tag :held_target_regression
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

  defp acceptance_source_fixture(c, directory \\ nil) do
    directory = directory || Path.join(c.base, "source-history")
    File.mkdir_p!(directory)
    File.chmod!(directory, 0o700)
    session = Ipse.Usage.id()

    pin =
      Map.new(
        ~w(policy_sha256 identity_sha256 routes_sha256 source_sha256),
        &{&1, JSON.digest([&1])}
      )
      |> Map.merge(%{
        "version" => 1,
        "session_id" => session,
        "epoch" => 1,
        "project_id" => c.binding["project_id"],
        "worktree_id" => c.binding["worktree_id"],
        "binding_sha256" => c.binding["binding_sha256"],
        "namespace" => c.namespace
      })

    {:ok, selectors} =
      Ipse.Extension.SemanticRoutes.selectors(
        Ipse.Test.ManagedPolicy.policy()["settings"]["routes"]
      )

    admission = %{
      "version" => 1,
      "binding" => c.binding,
      "instance" => "knowledge",
      "pin" => pin,
      "selectors" => selectors,
      "status" => "active"
    }

    assert Ipse.Extension.SemanticAdmission.valid?(admission, session)

    assert {:ok, ^session} =
             Ipse.Journal.create_with_id(directory, session, %{
               "source_layout" => Ipse.Session.SourceWindow.layout(),
               "source_origin_layout" => Ipse.Journal.SourceOrigin.layout(),
               "semantic_admission" => admission
             })

    text = String.duplicate("Source ", 137)

    assert :ok =
             Ipse.Journal.append(
               directory,
               session,
               Ipse.Session.Input.received(session, Ipse.Usage.id(), text, text, nil)
             )

    assert :ok =
             Ipse.Journal.append(directory, session, %{
               "type" => "message",
               "message" => %{"role" => "user", "content" => text}
             })

    assert {:ok, events} = Ipse.Journal.load(directory, session)
    assert {:ok, saved} = Ipse.Session.Saved.restore(events, session)
    assert {:ok, page} = Ipse.Session.SourceIndex.list(saved.source_window.index, %{"limit" => 1})
    [source] = page["sources"]

    assert {:ok, %{"proof" => proof}} =
             Ipse.Session.SourceIndex.resolve_proof(saved.source_window.index, %{
               "handle" => source["read_handle"],
               "quote" => text
             })

    assert {:ok, lock} = Ipse.Runner.lock(Path.join(directory, session <> ".lock"))
    assert :ok = Ipse.Runner.unlock(lock)
    {proof, admission, directory}
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

  @tag :accepted_retention_generic_guard
  test "generic V3 cannot publish an accepted retention receipt or omit its public target", c do
    opts = options(1, 0)

    assert {:ok, _} =
             publish(
               c,
               opts,
               %{
                 namespace: c.namespace,
                 format: "managed-metadata-v3",
                 operation_id: Usage.id(),
                 initialize: true
               },
               first: true
             )

    before = File.read!(Path.join([c.root, c.namespace, "root.json"]))
    next = options(2, 1)

    for omit_target? <- [false, true] do
      operation = Usage.id()

      result =
        Identity.with_domain_publication(
          c.home,
          c.cwd,
          c.binding,
          %{
            namespace: c.namespace,
            format: "managed-metadata-v3",
            operation_id: operation,
            initialize: false
          },
          fn _ -> :ok end,
          fn cap, catalog ->
            C.execute_managed_v3(
              c.root,
              c.namespace,
              next.request,
              operation,
              JSON.digest([next.recipe]),
              fn witness, read ->
                with {:ok, normalized, receipt} <-
                       NormalizerV3.normalize(
                         witness,
                         read,
                         Map.merge(next, %{domain_cap: cap, catalog: catalog})
                       ) do
                  changed =
                    if omit_target?,
                      do: Map.update!(normalized, "changes", &tl/1),
                      else: normalized

                  {:ok, changed, Map.put(receipt, "kind", "native_accepted_decision_retention")}
                end
              end
            )
          end
        )

      expected =
        if omit_target?,
          do: :managed_normalization_refused,
          else: :native_review_publication_fence_unavailable

      assert result == {:error, expected}
      assert File.read!(Path.join([c.root, c.namespace, "root.json"])) == before
    end
  end

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

  defp collect_accepted_leases(cwd, journal_lease, source_lease) do
    alias Ipse.Runner.Transaction
    alias Ipse.Session.{PendingAcceptance, StoredSources}

    {:ok, caps} = Transaction.retained_share_stack()

    identities =
      Enum.map(caps, fn cap ->
        {:ok, id} = Transaction.retained_share_identity(cap)
        id
      end)

    {:ok, journal} = PendingAcceptance.journal_share_identity(journal_lease)
    {:ok, source} = StoredSources.share_identity(source_lease)
    {:ok, helper} = Ipse.Runner.protected_helper(cwd)

    port =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        args: ["--lease-collect-accepted-v4"]
      ])

    try do
      {:os_pid, pid} = Port.info(port, :os_pid)
      operation = :crypto.strong_rand_bytes(16)
      deadline = System.monotonic_time(:millisecond) + 5_000
      ids = identities ++ [journal, source]
      slots = [0, 1, 2, 0, 0]

      bindings =
        Enum.map(ids, &{&1, :crypto.strong_rand_bytes(16), :crypto.strong_rand_bytes(32)})

      bad_entries =
        Enum.zip([1, 0, 2, 0, 0], bindings)
        |> Enum.map(fn {slot, {id, name, secret}} ->
          <<slot, id.pid::32, name::binary, secret::binary, id.device::64, id.inode::64>>
        end)
        |> IO.iodata_to_binary()

      bad =
        Port.open({:spawn_executable, String.to_charlist(helper)}, [
          :binary,
          :exit_status,
          :use_stdio,
          :hide,
          args: ["--lease-collect-accepted-v4"]
        ])

      bad_body = <<5_000::64, operation::binary, 5, bad_entries::binary>>
      assert Port.command(bad, <<?I, byte_size(bad_body)::32, bad_body::binary>>)
      assert_receive {^bad, {:exit_status, bad_status}}, 5_000
      assert bad_status != 0

      entries =
        Enum.zip(slots, bindings)
        |> Enum.map(fn {slot, {id, name, secret}} ->
          <<slot, id.pid::32, name::binary, secret::binary, id.device::64, id.inode::64>>
        end)
        |> IO.iodata_to_binary()

      body = <<5_000::64, operation::binary, 5, entries::binary>>
      assert Port.command(port, <<?I, byte_size(body)::32, body::binary>>)
      assert collector_frame(port, ?H) == <<operation::binary, 5>>

      for {cap, {id, name, secret}} <- Enum.zip(caps, Enum.take(bindings, 3)) do
        recipient = <<pid::32, name::binary, secret::binary, id.device::64, id.inode::64>>
        assert :ok = Transaction.retained_share_export(cap, operation, recipient, deadline)
      end

      {id, name, secret} = Enum.at(bindings, 3)
      recipient = <<pid::32, name::binary, secret::binary, id.device::64, id.inode::64>>

      assert :ok =
               PendingAcceptance.journal_share_export(
                 journal_lease,
                 operation,
                 recipient,
                 deadline
               )

      {id, name, secret} = Enum.at(bindings, 4)
      recipient = <<pid::32, name::binary, secret::binary, id.device::64, id.inode::64>>
      assert :ok = StoredSources.share_export(source_lease, operation, recipient, deadline)
      assert collector_frame(port, ?L) == <<operation::binary, 5>>

      assert Port.command(port, <<?C, operation::binary>>)

      Enum.each(caps, fn cap ->
        assert :ok = Transaction.retained_share_settle(cap, operation, deadline)
      end)

      assert :ok = PendingAcceptance.journal_share_settle(journal_lease, operation, deadline)
      assert :ok = StoredSources.share_settle(source_lease, operation, deadline)
      assert collector_frame(port, ?C) == <<operation::binary, 5>>
      assert_receive {^port, {:exit_status, 0}}, 5_000
      {:ok, :collected}
    after
      if Port.info(port), do: Port.close(port)
    end
  end

  defp collector_frame(port, tag, buffer \\ <<>>) do
    case buffer do
      <<^tag, size::32, body::binary-size(size)>> ->
        body

      _ ->
        receive do
          {^port, {:data, bytes}} when byte_size(buffer) + byte_size(bytes) <= 256 ->
            collector_frame(port, tag, buffer <> bytes)

          {^port, {:exit_status, status}} ->
            flunk("collector exit #{status}")
        after
          5_000 -> flunk("collector timeout")
        end
    end
  end

  defp wait_file(path, deadline) do
    cond do
      File.exists?(path) ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        :timeout

      true ->
        Process.sleep(10)
        wait_file(path, deadline)
    end
  end

  defp source_holder(lock_path) do
    File.ls!("/proc")
    |> Enum.find_value(fn entry ->
      with {pid, ""} <- Integer.parse(entry),
           {:ok, bytes} <- File.read("/proc/#{pid}/cmdline"),
           args = :binary.split(bytes, <<0>>, [:global]),
           true <- "--session-resume-share-v2" in args and lock_path in args do
        pid
      else
        _ -> nil
      end
    end)
  end

  defp packed(hash), do: Base.url_encode64(Base.decode16!(hash, case: :lower), padding: false)

  defp entry(c) do
    state = (c.home <> "/project-identities/index.json") |> File.read!() |> Jason.decode!()
    state["domain_keys"][c.binding["project_id"]]["namespaces"][c.namespace]
  end
end
