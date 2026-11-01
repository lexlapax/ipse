Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule IpseKnowledge.KnowledgeSessionTest do
  use ExUnit.Case, async: false
  @answer_attack_child "--ipse-native-answer-attack-child" in System.argv()
  @attack_child "--ipse-native-capture-attack-child" in System.argv() or @answer_attack_child
  @answer_child "--ipse-native-answer-capture-child" in System.argv() or @answer_attack_child
  @fragment_child "--ipse-native-capture-fragment-child" in System.argv() or
                    (@attack_child and not @answer_attack_child)
  @native_fixture_child "--ipse-native-capture-child" in System.argv() or @fragment_child or
                          @answer_child

  alias Ipse.Extension.{
    Artifact,
    Catalog,
    Registry,
    Consent,
    ProjectIdentity,
    SemanticConsent,
    SemanticAdmission
  }

  alias Ipse.{Session, JSON, Journal}

  defmodule Model do
    def complete(_, messages, _, _), do: complete_with(:whole, messages)

    def complete_with(mode, messages) do
      turn =
        Enum.count(messages, fn message ->
          message["role"] == "user" and not Ipse.Session.Reference.reference?(message)
        end)

      results =
        messages
        |> Enum.reject(&Ipse.Session.Reference.reference?/1)
        |> Enum.reverse()
        |> Enum.take_while(&(&1["role"] != "user"))
        |> Enum.reverse()
        |> Enum.filter(&(&1["role"] == "tool"))

      case results do
        [] ->
          tool("list-#{turn}", "source_list", %{"limit" => 32})

        [result] ->
          list = Jason.decode!(result["content"])
          source = Enum.find(Enum.reverse(list["sources"]), &(&1["kind"] == "input.original"))

          input =
            Enum.find(Enum.reverse(messages), fn message ->
              message["role"] == "user" and not Ipse.Session.Reference.reference?(message)
            end)["content"]

          input = if mode == :fragment, do: "café 日本語", else: input

          tool("capture-#{turn}", "ext__knowledge__capture", %{
            "text" => input,
            "category" => "ordinary",
            "reason" => "selected observation",
            "event_at_ms" => nil,
            "source" => %{"handle" => source["read_handle"], "quote" => input}
          })

        _ ->
          {:ok,
           %{"role" => "assistant", "content" => "The unattended observation is pending review."},
           %{}}
      end
    end

    defp tool(id, name, args),
      do:
        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => id,
               "type" => "function",
               "function" => %{
                 "name" => name,
                 "arguments" => Jason.encode!(args)
               }
             }
           ]
         }, %{}}
  end

  defmodule FragmentModel do
    def complete(_, messages, _, _), do: Model.complete_with(:fragment, messages)
  end

  defmodule AnswerModel do
    def complete(_, messages, _, _) do
      results = Enum.filter(messages, &(&1["role"] == "tool"))
      question = Enum.find(results, &(&1["tool_call_id"] == "native_question"))
      listed = Enum.find(results, &(&1["tool_call_id"] == "list"))
      captured = Enum.find(results, &(&1["tool_call_id"] == "capture"))

      cond do
        captured ->
          {:ok, %{"role" => "assistant", "content" => "Synthetic answer is pending."}, %{}}

        listed ->
          source =
            listed["content"]
            |> Jason.decode!()
            |> Map.fetch!("sources")
            |> Enum.find(&(&1["origin"] == "native_operator_answer"))

          tool("capture", "ext__knowledge__capture", %{
            "text" => "2",
            "category" => "ordinary",
            "reason" => "synthetic answer",
            "event_at_ms" => nil,
            "source" => %{"handle" => source["read_handle"], "quote" => "2"}
          })

        question ->
          tool("list", "source_list", %{"limit" => 32})

        true ->
          tool("native_question", "ask_operator", %{
            "questions" => [
              %{
                "id" => "choice",
                "kind" => "single",
                "prompt" => "Synthetic native choice",
                "options" => [%{"id" => "a", "label" => "A"}, %{"id" => "b", "label" => "B"}]
              },
              %{"id" => "text", "kind" => "text", "prompt" => "Synthetic native literal answer"}
            ]
          })
      end
    end

    defp tool(id, name, args),
      do:
        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => id,
               "type" => "function",
               "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
             }
           ]
         }, %{}}
  end

  @tag :capture_parent_case
  test "built native bundle captures an unattended source only as a protected pending proposal" do
    capture(false)
  end

  @tag :capture_parent_case
  @tag :genuine_pending_acceptance
  @tag timeout: 180_000
  @tag skip:
         if(System.get_env("IPSE_TEST_GENUINE_PENDING_ACCEPTANCE") == "1",
           do: false,
           else: "explicit native acceptance fixture required"
         )
  test "a main-model pending proposal reaches private native acceptance" do
    capture(false, false, false, false, false, true)
  end

  @tag :capture_parent_case
  @tag :genuine_pending_public_review
  @tag timeout: 180_000
  @tag skip:
         if(System.get_env("IPSE_TEST_GENUINE_PENDING_PUBLIC_REVIEW") == "1",
           do: false,
           else: "explicit native public review fixture required"
         )
  test "a main-model pending proposal reaches the public review CLI" do
    capture(false, false, false, false, false, :public)
  end

  @tag :capture_parent_case
  @tag :genuine_pending_accepted_recall
  @tag timeout: 180_000
  @tag skip:
         if(System.get_env("IPSE_TEST_GENUINE_PENDING_ACCEPTED_RECALL") == "1",
           do: false,
           else: "explicit native accepted-recall fixture required"
         )
  test "a public accepted decision reaches a fresh Session through typed current recall" do
    capture(false, false, false, false, false, :public_recall)
  end

  @tag :capture_parent_case
  @tag :genuine_pending_path_swap
  @tag timeout: 180_000
  @tag skip:
         if(System.get_env("IPSE_TEST_PENDING_PATH_SWAP") == "1",
           do: false,
           else: "explicit isolated source-unavailability fixture required"
         )
  test "historical review displays a pending card but unavailable source prevents acceptance" do
    capture(false, false, false, false, false, :path_swap)
  end

  @tag :capture_parent_case
  test "read-only recall job rechecks an empty Collection through the Session" do
    capture(false, false, false, false, true)
  end

  if @native_fixture_child do
    test "actual PTY capture obeys the selected literal, pending or refusal case" do
      capture(true, @fragment_child, @attack_child, @answer_child)
    end
  else
    test "actual PTY input exercises the separately built native capture artifact" do
      root = Path.join(System.tmp_dir!(), "ipse-knowledge-native-pty-" <> Ipse.Usage.id())
      File.mkdir!(root)
      File.chmod!(root, 0o700)
      on_exit(fn -> File.rm_rf!(root) end)
      driver = Path.join(root, "pty")

      assert {_, 0} =
               System.cmd(
                 "rustc",
                 [
                   "--edition=2021",
                   "-D",
                   "warnings",
                   "test/support/operator_pty.rs",
                   "-o",
                   driver
                 ],
                 stderr_to_stdout: true
               )

      paths =
        :code.get_path()
        |> Enum.map(&List.to_string/1)
        |> Enum.reject(&(&1 == "."))
        |> Enum.map(&Path.expand/1)
        |> Enum.reverse()
        |> Enum.flat_map(&["-pa", &1])

      for flag <- [
            "--ipse-native-capture-child",
            "--ipse-native-capture-fragment-child",
            "--ipse-native-capture-attack-child"
          ] do
        program =
          "ExUnit.start(exclude: [:capture_parent_case]); {:ok, _} = Application.ensure_all_started(:ipse); System.argv([#{inspect(flag)}]); Code.require_file(#{inspect(Path.expand(__ENV__.file))})"

        {output, status} =
          System.cmd(
            driver,
            [System.find_executable("elixir"), "--erl", "+S 2:2"] ++ paths ++ ["-e", program],
            stderr_to_stdout: true
          )

        assert status == 0, output
        assert output =~ "1 passed"
      end
    end

    test "native question answer reaches pending capture through the terminal and built worker" do
      root = Path.join(System.tmp_dir!(), "ipse-knowledge-answer-pty-" <> Ipse.Usage.id())
      File.mkdir!(root)
      File.chmod!(root, 0o700)
      on_exit(fn -> File.rm_rf!(root) end)
      driver = Path.join(root, "pty")

      assert {_, 0} =
               System.cmd(
                 "rustc",
                 [
                   "--edition=2021",
                   "-D",
                   "warnings",
                   "test/support/operator_cli_pty.rs",
                   "-o",
                   driver
                 ],
                 stderr_to_stdout: true
               )

      paths =
        :code.get_path()
        |> Enum.map(&List.to_string/1)
        |> Enum.reject(&(&1 == "."))
        |> Enum.map(&Path.expand/1)
        |> Enum.reverse()
        |> Enum.flat_map(&["-pa", &1])

      for flag <- ["--ipse-native-answer-capture-child", "--ipse-native-answer-attack-child"] do
        program =
          "ExUnit.start(exclude: [:capture_parent_case]); {:ok, _} = Application.ensure_all_started(:ipse); System.argv([#{inspect(flag)}]); Code.require_file(#{inspect(Path.expand(__ENV__.file))})"

        {output, status} =
          System.cmd(
            driver,
            [System.find_executable("elixir"), "--erl", "+S 2:2"] ++
              paths ++ ["-e", program, root],
            stderr_to_stdout: true
          )

        assert status == 0, output
        assert output =~ "1 passed"
      end
    end
  end

  defp capture(
         native?,
         fragment? \\ false,
         attack? \\ false,
         answer? \\ false,
         recall? \\ false,
         accept? \\ false
       ) do
    root = Path.join(System.tmp_dir!(), "ipse-native-knowledge-session-" <> Ipse.Usage.id())
    home = Path.join(root, "home")
    cwd = Path.join(root, if(accept?, do: "work", else: "project"))
    File.mkdir_p!(home)
    File.mkdir_p!(cwd)
    File.chmod!(home, 0o700)

    if accept? == :public_recall,
      do: IO.puts("ACCEPTED_RECALL_ROOT=" <> root),
      else: on_exit(fn -> File.rm_rf!(root) end)

    output = Path.join(root, "artifact")
    sdk = Application.app_dir(:ipse, "ebin")
    paths = Path.wildcard(Path.join(Path.dirname(Path.dirname(sdk)), "*/ebin"))

    builder =
      if attack? do
        fixture_root = Path.join(root, "fixture")
        fixture_extension = Path.join(fixture_root, "extensions/knowledge")
        File.mkdir_p!(Path.dirname(fixture_extension))
        File.cp_r!("extensions/knowledge", fixture_extension)
        File.cp!("LICENSE", Path.join(fixture_root, "LICENSE"))
        source = Path.join(fixture_extension, "src/knowledge/records.ex")
        original = File.read!(source)

        guard = ~r/  def direct\?\(attrs, proof\) do\n.*?\n  end/s
        assert length(Regex.scan(guard, original)) == 1

        File.write!(
          source,
          Regex.replace(guard, original, """
            def direct?(attrs, proof) do
              proof["origin"] in (@direct ++ ~w(interactive_operator native_operator_answer)) and
                attrs["text"] == proof["quote"]
            end
          """)
        )

        # A reviewed permissive worker still cannot grant literal authority.
        contracts = Path.join(fixture_extension, "src/knowledge/contracts.ex")
        data = File.read!(contracts)
        old = "Enum.sort(~w(native_operator_assertion typed_host_outcome))"
        assert length(:binary.matches(data, old)) == 1

        data =
          String.replace(
            data,
            old,
            "Enum.sort(~w(interactive_operator native_operator_answer native_operator_assertion typed_host_outcome))"
          )

        extra =
          "~w(interactive_operator native_operator_answer unattended_input assistant_proposal)"

        assert length(:binary.matches(data, extra)) == 1

        File.write!(
          contracts,
          String.replace(data, extra, "~w(unattended_input assistant_proposal)")
        )

        Path.join(fixture_extension, "build.exs")
      else
        "extensions/knowledge/build.exs"
      end

    args =
      Enum.flat_map(paths, &["-pa", &1]) ++
        [
          builder,
          "--sdk",
          sdk,
          "--output",
          output,
          "--package",
          "knowledge",
          "--preset",
          "native"
        ]

    assert {build, 0} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)
    assert build =~ "Built knowledge/native"

    if accept? != false and System.get_env("IPSE_TEST_FRESH_BUNDLE_ROOT"),
      do: stage_isolated_bundle(output, System.fetch_env!("IPSE_TEST_FRESH_BUNDLE_ROOT"))

    {:ok, artifact} =
      if accept?,
        do: Ipse.Extension.Bundles.install("knowledge", home),
        else: Artifact.import(output, Path.join(home, "extensions/artifacts"))

    if accept? != false and System.get_env("IPSE_TEST_FRESH_BUNDLE_ROOT"),
      do: assert(artifact.digest == JSON.sha256(File.read!(Path.join(output, "extension.json"))))

    options =
      Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})
      |> Map.put("version", 1)

    data = %{
      "extension_trust" => [
        %{
          "artifact" => artifact.digest,
          "capabilities" => artifact.manifest["capabilities"],
          "allow_project" => false,
          "allow_children" => false
        }
      ],
      "extensions" => [
        %{
          "instance" => "knowledge",
          "artifact" => artifact.digest,
          "enabled" => true,
          "options" => options,
          "order" => 0,
          "lifetime" => "session"
        }
      ]
    }

    {:ok, selected} =
      Ipse.Extension.Config.resolve(
        [%{scope: "operator", path: "/fixture/config.json", data: data}],
        []
      )

    {:ok, [entry] = entries} = Registry.prepare(selected, home)

    config = %{
      provider: :demo,
      provider_module:
        if(answer?, do: AnswerModel, else: if(fragment?, do: FragmentModel, else: Model)),
      model: "synthetic",
      home: home,
      approval: :deny,
      approval_origin: :default_headless,
      headless: true,
      operator_questions: answer?,
      extensions: entries
    }

    config =
      if native?,
        do: Map.merge(config, %{approval: :ask, approval_origin: :interactive, headless: false}),
        else: config

    {:ok, binding} = ProjectIdentity.admit(home, cwd, :folder)
    {:ok, namespace} = SemanticConsent.namespace(binding["project_id"], "knowledge")
    {:ok, catalog} = Catalog.snapshot(config)

    {:ok, sidecar_bytes} =
      Artifact.read_declared(
        Path.join(home, "extensions/artifacts"),
        artifact.digest,
        "operator.json",
        65_536
      )

    {:ok, sidecar} = JSON.decode_unique(sidecar_bytes)

    kind = if native? and attack?, do: "note", else: "pending"

    constraints = sidecar["publication"][kind]
    recipe = sidecar["recipes"][kind]
    constraints_sha = JSON.digest([constraints])
    recipe_sha = JSON.digest([recipe])

    note_recipe_sha = JSON.digest([sidecar["recipes"]["note"]])
    note_constraints_sha = JSON.digest([sidecar["publication"]["note"]])

    effects =
      Enum.flat_map(catalog["entries"], fn descriptor ->
        hash = JSON.digest([descriptor])

        publish =
          if descriptor["id"] == "capture" or not recall? do
            [
              %{
                "operation" => if(kind == "note", do: "notes.capture", else: "notes.propose"),
                "class" => "collection.publish",
                "outer_sha256" => hash,
                "inner_op" => "collection.managed",
                "constraints_sha256" => constraints_sha,
                "recipe_sha256" => recipe_sha
              }
            ]
          else
            []
          end

        note_publish =
          if accept? != false and descriptor["id"] == "capture" do
            [
              %{
                "operation" => "notes.capture",
                "class" => "collection.publish",
                "outer_sha256" => hash,
                "inner_op" => "collection.managed",
                "constraints_sha256" => note_constraints_sha,
                "recipe_sha256" => note_recipe_sha
              }
            ]
          else
            []
          end

        publish ++
          note_publish ++
          [
            %{
              "operation" => "notes.recall",
              "class" => "collection.read",
              "outer_sha256" => hash,
              "inner_op" => "collection.call",
              "managed_read" =>
                if(accept?, do: Enum.sort([recipe_sha, note_recipe_sha]), else: [recipe_sha])
            }
          ]
      end)
      |> Enum.sort_by(&{&1["operation"], &1["class"], &1["outer_sha256"], &1["inner_op"]})

    selection = %{
      "version" => 2,
      "constraints" =>
        if(accept?,
          do: %{
            constraints_sha => constraints,
            note_constraints_sha => sidecar["publication"]["note"]
          },
          else: %{constraints_sha => constraints}
        ),
      "recipes" =>
        if(accept?,
          do: %{recipe_sha => recipe, note_recipe_sha => sidecar["recipes"]["note"]},
          else: %{recipe_sha => recipe}
        ),
      "activation" => nil,
      "domain" => "knowledge",
      "namespace" => namespace,
      "scope" => %{"kind" => "project", "worktree_id" => nil},
      "sources" => %{
        "categories" => [
          if(answer?,
            do: "native_operator_answer",
            else: if(native?, do: "interactive_operator", else: "unattended_input")
          )
        ],
        "exclusions" => []
      },
      "storage" => %{"kind" => "local_collection", "collection" => "knowledge"},
      "retention" => %{"automatic" => 90, "manual" => 3650},
      "routes" => [
        %{
          "operation" => "main",
          "provider" => "demo",
          "profile" => nil,
          "model" => "synthetic",
          "endpoint" => "demo://local",
          "service_id" => "demo",
          "billing_mode" => "none",
          "processing_region" => nil,
          "storage_region" => nil,
          "cache_retention" => nil,
          "account_controls" => nil
        }
      ],
      "effects" => effects,
      "limits" =>
        Map.merge(Consent.zero(), %{
          "operations" => 8,
          "input_bytes" => if(accept? in [:public, :public_recall], do: 1_000_000, else: 100_000),
          "output_bytes" => 200_000
        }),
      "period_ms" => 86_400_000,
      "expires_at_ms" => System.system_time(:millisecond) + 600_000,
      "headless" => true
    }

    {config, selection} =
      if accept? == :public_recall do
        config = registered_capture_config(config)

        assert {:ok, routes} =
                 Ipse.Extension.SemanticRoutes.resolve(config, [
                   Map.merge(
                     Map.new(
                       ~w(processing_region storage_region cache_retention account_controls),
                       &{&1, nil}
                     ),
                     %{"operation" => "main", "profile" => nil}
                   )
                 ])

        {config, Map.put(selection, "routes", routes)}
      else
        {config, selection}
      end

    assert {:ok, policy} = SemanticConsent.prepare(binding, entry.identity, selection)
    control = SemanticAdmission.control_root(home)
    {:ok, before} = Consent.snapshot(control, binding["project_id"])

    {:ok, _} =
      Consent.replace(
        control,
        binding["project_id"],
        before["epoch"],
        policy,
        System.system_time(:millisecond)
      )

    {:ok, selection} = Ipse.Config.Semantics.selection(policy)
    config = Map.put(config, :semantic_selections, selection)
    dir = Path.join(root, "sessions")

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: cwd, state_dir: dir, subscriber: self()}
      )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)

    if answer? do
      monitor = Process.monitor(pid)
      assert 0 == Ipse.CLI.Terminal.interact(pid, monitor, true, nil, cwd)
    else
      if native? do
        {:ok, text, witness} = Session.observe_input(pid, "IPSE_FIXTURE_INPUT_1> ", 5000)
        assert text == "synthetic café 日本語 1"
        assert :ok = Session.prompt(pid, text, witness)
      else
        assert :ok = Session.prompt(pid, "Acme has owner Alex")
      end
    end

    unless answer? do
      assert_receive {:ipse, ^pid, {:done, status}}, 30_000
      expected = if(attack? or recall?, do: :error, else: :ok)

      if status != expected do
        assert {:ok, events} = Journal.load(dir, Session.info(pid).id)
        trace = Enum.map(events, &recall_trace/1)

        flunk(
          "Capture ended #{status}, expected #{expected}: #{inspect(trace, limit: :infinity)}"
        )
      end
    end

    {:ok, events} = Journal.load(dir, Session.info(pid).id)

    if recall? do
      assert_receive {:ipse, ^pid, {:error, reason}}, 5_000
      assert reason =~ "Managed history cannot be safely reused"

      indexes =
        Enum.filter(events, fn event ->
          event["type"] == "extension_action_result" and
            get_in(event, ["request", "op"]) == "collection.call" and
            get_in(event, ["request", "request", "op"]) == "index"
        end)

      assert Enum.map(indexes, &get_in(&1, ["request", "request", "limit"])) == [32, 1]
      assert Enum.all?(indexes, &(get_in(&1, ["outcome", "status"]) == "ok"))

      assert get_in(hd(indexes), ["outcome", "value", "generation"]) ==
               get_in(List.last(indexes), ["outcome", "value", "generation"])

      assert Enum.any?(
               events,
               &(&1["type"] == "extension_event_result" and &1["outcome"] == "completed")
             )

      refute Enum.any?(events, &(&1["type"] == "request_admitted"))
    else
      commit =
        Enum.find(
          events,
          &(&1["type"] == "extension_action_result" and
              get_in(&1, ["request", "request", "op"]) == "commit")
        )

      assert commit,
             "Capture produced no commit: #{inspect(Enum.map(events, &recall_trace/1), limit: :infinity)}"

      if attack? do
        assert commit["outcome"]["status"] == "failed"
        [change] = commit["request"]["request"]["changes"]
        assert String.starts_with?(change["key"], "note.")
        [proof] = change["value"]["evidence"]["sources"]

        if answer?,
          do: assert(proof["quote"] == "2" and proof["start_byte"] == 0),
          else: assert(proof["quote"] == "café 日本語" and proof["start_byte"] > 0)

        {:ok, after_refusal} = Consent.snapshot(control, binding["project_id"])
        assert map_size(after_refusal["operations"]) == 0

        {:ok, stored} =
          Ipse.Extension.Collection.execute(
            SemanticAdmission.collection_root(home),
            namespace,
            %{"op" => "status"},
            Ipse.Usage.id()
          )

        assert stored["generation"] == 0 and stored["records"] == 0
      else
        assert commit["outcome"]["status"] == "ok"
        assert commit["approval"] == "saved_consent"
        assert commit["version"] == 3
        assert commit["effect_binding"]["kind"] == "collection.managed"
        assert commit["effect_binding"]["version"] == 3
        assert commit["effect_binding"]["metadata_version"] == 3
        assert commit["request"]["metadata_version"] == 3
        assert commit["request"]["recipe_sha256"] == recipe_sha
        assert commit["request"]["request"]["advance_floor"] == true
        normalization = commit["outcome"]["value"]["normalization"]
        assert normalization["version"] == 3

        assert normalization["eligibility"] ==
                 if(kind == "note", do: "current", else: "never_current")

        assert is_integer(normalization["valid_until_ms"])
        [change] = commit["request"]["request"]["changes"]
        assert String.starts_with?(change["key"], kind <> ".")

        if kind == "note",
          do: assert(change["value"]["category"] == "ordinary"),
          else: assert(change["value"]["state"] == "pending")

        assert hd(change["value"]["evidence"]["sources"])["origin"] ==
                 if(answer?,
                   do: "native_operator_answer",
                   else: if(native?, do: "interactive_operator", else: "unattended_input")
                 )

        if fragment? do
          [proof] = change["value"]["evidence"]["sources"]
          assert proof["quote"] == "café 日本語"
          assert proof["start_byte"] > 0
          assert proof["content_sha256"] != proof["quote_sha256"]
        end

        assert {:ok, _} = Session.restore_context(events)
        {:ok, after_save} = Consent.snapshot(control, binding["project_id"])
        assert map_size(after_save["operations"]) == 1

        if kind == "pending" do
          session = Session.info(pid).id
          assert :ok = Ipse.Session.SourceWindow.validate_sources(dir, session, events)
          assert {:ok, saved} = Ipse.Session.Saved.restore(events, session)

          refute Enum.any?(events, fn event ->
                   event["type"] == "extension_action_result" and
                     get_in(event, ["request", "request", "op"]) == "scan"
                 end)

          assert {:ok, observed} =
                   ProjectIdentity.with_existing_domain_auth(
                     home,
                     cwd,
                     binding,
                     %{namespace: namespace, format: "managed-metadata-v3"},
                     fn cap, catalog ->
                       Ipse.Extension.Collection.ObservedRead.managed_proposal(
                         SemanticAdmission.collection_root(home),
                         namespace,
                         %{"op" => "get_record", "key" => change["key"]},
                         cap,
                         catalog,
                         recipe
                       )
                     end
                   )

          [proof] =
            get_in(observed, ["observation", "value", "record", "value", "evidence", "sources"])

          assert {:ok, checked} =
                   Ipse.Session.SourceIndex.revalidate_stored(saved.source_window.index, proof)

          assert checked["proof"] == proof

          copied_dir = Path.join(root, "copied-sessions")
          File.cp_r!(dir, copied_dir)
          assert {:ok, copied_events} = Journal.load(copied_dir, session)

          assert :ok =
                   Ipse.Session.SourceWindow.validate_sources(copied_dir, session, copied_events)

          assert {:ok, copied_saved} = Ipse.Session.Saved.restore(copied_events, session)

          assert {:ok, copied_check} =
                   Ipse.Session.SourceIndex.revalidate_stored(
                     copied_saved.source_window.index,
                     proof
                   )

          assert copied_check["proof"] == proof

          assert {:ok, redacted_index} =
                   Ipse.Session.SourceIndex.redact(
                     saved.source_window.index,
                     proof["occurrence_id"],
                     saved.source_window.index.policy_generation + 1
                   )

          assert {:error, :source_index_refused} =
                   Ipse.Session.SourceIndex.revalidate_stored(redacted_index, proof)

          assert {:ok, _} =
                   Ipse.Session.SourceIndex.revalidate_stored(
                     copied_saved.source_window.index,
                     proof
                   )

          assert {:error, :source_index_refused} =
                   Ipse.Session.SourceIndex.revalidate_stored(
                     saved.source_window.index,
                     Map.put(proof, "quote", "altered")
                   )

          assert observed["metadata"]["eligibility"] == "never_current"
          assert observed["metadata"]["valid_until_ms"] == normalization["valid_until_ms"]
          assert after_save["operations"][commit["operation_id"]]["status"] == "settled"
        end

        {:ok, stored} =
          Ipse.Extension.Collection.execute(
            SemanticAdmission.collection_root(home),
            namespace,
            %{"op" => "status"},
            Ipse.Usage.id()
          )

        assert stored["generation"] == 1 and stored["floor"] == 1
        assert stored["records"] == 4

        if not native? do
          id = Session.info(pid).id
          assert :ok = Session.close_confirmed(pid)

          assert {:ok, resumed} =
                   DynamicSupervisor.start_child(
                     Ipse.Sessions,
                     {Session,
                      config: config, cwd: cwd, state_dir: dir, subscriber: self(), id: id}
                   )

          on_exit(fn -> if Process.alive?(resumed), do: Session.close(resumed) end)
          assert Session.info(resumed).phase == :idle
          refute_receive {:ipse, ^resumed, {:tool, _, _}}, 100
          assert {:ok, after_resume} = Consent.snapshot(control, binding["project_id"])
          assert after_resume["operations"] == after_save["operations"]

          assert :ok = Session.prompt(resumed, "Beta has owner Mira")
          assert_receive {:ipse, ^resumed, {:done, :ok}}, 30_000
          assert {:ok, repeated_events} = Journal.load(dir, id)

          commits =
            Enum.filter(repeated_events, fn event ->
              event["type"] == "extension_action_result" and
                get_in(event, ["request", "op"]) == "collection.managed" and
                get_in(event, ["outcome", "status"]) == "ok"
            end)

          assert length(commits) == 2
          [_, second] = commits
          assert second["approval"] == "saved_consent"
          [second_change] = second["request"]["request"]["changes"]
          assert second_change["value"]["state"] == "pending"
          assert second_change["value"]["text"] == "Beta has owner Mira"
          refute second_change["key"] == change["key"]

          refute Enum.any?(repeated_events, fn event ->
                   event["type"] == "extension_action_result" and
                     get_in(event, ["request", "request", "op"]) == "scan"
                 end)

          assert {:ok, twice_saved} = Consent.snapshot(control, binding["project_id"])
          assert map_size(twice_saved["operations"]) == 2

          assert Enum.all?(twice_saved["operations"], fn {_, operation} ->
                   operation["status"] == "settled"
                 end)

          assert {:ok, restored} = Ipse.Session.Saved.restore(repeated_events, id)

          if accept? == :public_recall do
            assert Enum.any?(repeated_events, fn event ->
                     projection = event["projection"] || %{}

                     roots =
                       Enum.map(
                         projection["old_dependencies"] || [],
                         &get_in(&1, ["collection", "generation"])
                       )

                     projection["type"] == "managed_root_transition" and
                       Enum.sort(Enum.uniq(roots)) == [1, 2]
                   end)

            assert Enum.any?(restored.messages, fn message ->
                     message["ipse_root_history"] == %{
                       "version" => 1,
                       "old_generation" => 1,
                       "new_generation" => 2
                     }
                   end)
          end

          assert :ok = Session.close_confirmed(resumed)

          if accept? == :path_swap do
            exercise_pending_path_swap(root, home, dir, namespace, sidecar, change)
          else
            if accept?,
              do:
                exercise_pending_acceptance(
                  root,
                  home,
                  dir,
                  namespace,
                  sidecar,
                  change,
                  second_change,
                  %{
                    public?: accept? in [:public, :public_recall],
                    config: config,
                    recall_accepted?: accept? === :public_recall
                  }
                )
          end
        end
      end
    end
  end

  defp exercise_pending_path_swap(root, home, history_dir, namespace, sidecar, change) do
    driver = Path.join(root, "path-swap-pty")

    assert {_, 0} =
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

    [proof] = get_in(change, ["value", "evidence", "sources"])

    fixture = %{
      "namespace" => namespace,
      "collection_root" => SemanticAdmission.collection_root(home),
      "key" => change["key"],
      "recipe" => sidecar["recipes"]["pending"],
      "note_recipe" => sidecar["recipes"]["note"],
      "history_dir" => history_dir,
      "sources" => [proof]
    }

    File.write!(Path.join(root, "pending-management.json"), Jason.encode!(fixture), [:exclusive])

    args =
      ["--management-review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
        paths ++
        [
          Path.expand("test/support/pending_acceptance_management.exs"),
          root,
          "host-orchestrated-path-swap"
        ]

    source = Path.join(history_dir, proof["session_id"] <> ".lock")
    held = source <> ".path-swap-held"

    assert {:ok, before_review} =
             Ipse.Extension.Collection.execute(
               fixture["collection_root"],
               namespace,
               %{"op" => "get", "key" => change["key"]},
               Ipse.Usage.id()
             )

    assert :ok = File.rename(source, held)

    try do
      File.write!(source, "", [:exclusive])
      File.chmod!(source, 0o600)
      assert {:ok, contender} = Ipse.Runner.lock(source)

      {output, status} =
        try do
          System.cmd(driver, args, stderr_to_stdout: true)
        after
          Ipse.Runner.unlock(contender)
        end

      assert status == 0, output
      assert output =~ "PENDING_MANAGEMENT_REVIEW_HOST-ORCHESTRATED-PATH-SWAP_PASSED"
      assert output =~ "Historical pending candidate;"
      assert output =~ change["value"]["text"]

      assert {:ok, after_review} =
               Ipse.Extension.Collection.execute(
                 fixture["collection_root"],
                 namespace,
                 %{"op" => "get", "key" => change["key"]},
                 Ipse.Usage.id()
               )

      assert after_review === before_review
      "pending." <> id = change["key"]

      assert {:ok, link} =
               Ipse.Extension.Collection.execute(
                 fixture["collection_root"],
                 namespace,
                 %{"op" => "get", "key" => "accept." <> id},
                 Ipse.Usage.id()
               )

      assert is_nil(link["record"])
    after
      if File.exists?(held) do
        File.rm(source)
        File.rename!(held, source)
      end
    end
  end

  defp exercise_pending_acceptance(
         root,
         home,
         history_dir,
         namespace,
         sidecar,
         change,
         second_change,
         options
       ) do
    public? = options.public?
    driver = Path.join(root, "acceptance-pty")

    script =
      Path.expand(
        if(public?,
          do: "test/support/pending_acceptance_cli.exs",
          else: "test/support/pending_acceptance_management.exs"
        )
      )

    prefix = if(public?, do: "PUBLIC_PENDING_REVIEW", else: "PENDING_MANAGEMENT_REVIEW")

    if public? do
      File.write!(
        Path.join(home, "config.json"),
        Jason.encode!(%{
          "version" => 1,
          "settings" => %{"provider" => "demo", "model" => "synthetic"}
        }),
        [:exclusive]
      )

      File.chmod!(Path.join(home, "config.json"), 0o600)
    end

    assert {_, 0} =
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

    fixture = %{
      "namespace" => namespace,
      "collection_root" => SemanticAdmission.collection_root(home),
      "key" => change["key"],
      "recipe" => sidecar["recipes"]["pending"],
      "note_recipe" => sidecar["recipes"]["note"],
      "history_dir" => history_dir,
      "sources" => get_in(change, ["value", "evidence", "sources"])
    }

    File.write!(Path.join(root, "pending-management.json"), Jason.encode!(fixture), [:exclusive])

    assert {:ok, before_cancel} =
             Ipse.Extension.Collection.execute(
               fixture["collection_root"],
               namespace,
               %{"op" => "get", "key" => change["key"]},
               Ipse.Usage.id()
             )

    if public? do
      command = [System.find_executable("elixir"), "--erl", "+S 2:2"] ++ paths

      {index_output, index_status} =
        System.cmd(hd(command), tl(command) ++ [script, root, "index"], stderr_to_stdout: true)

      assert index_status == 0, index_output
      assert index_output =~ "PUBLIC_PENDING_REVIEW_INDEX_PASSED"
      refute index_output =~ change["value"]["text"]

      {pipe_output, pipe_status} =
        System.cmd(hd(command), tl(command) ++ [script, root, "pipe"], stderr_to_stdout: true)

      assert pipe_status == 0, pipe_output
      assert pipe_output =~ "PUBLIC_PENDING_REVIEW_PIPE_PASSED"
      refute pipe_output =~ "Historical pending candidate;"

      assert {:ok, binding} = ProjectIdentity.existing(home, Path.join(root, "work"))
      control = SemanticAdmission.control_root(home)
      assert {:ok, saved} = Consent.existing_snapshot(control, binding["project_id"])
      limited = put_in(saved["policy"], ["limits", "operations"], 1)
      assert SemanticConsent.policy?(limited)

      assert {:ok, _} =
               Consent.replace(
                 control,
                 binding["project_id"],
                 saved["epoch"],
                 limited,
                 System.system_time(:millisecond)
               )

      {budget_output, budget_status} =
        System.cmd(driver, ["--management-review"] ++ command ++ [script, root, "budget"],
          stderr_to_stdout: true
        )

      assert budget_status == 0, budget_output
      assert budget_output =~ "PUBLIC_PENDING_REVIEW_BUDGET_PASSED"
      refute budget_output =~ "Historical pending candidate;"
      assert {:ok, current} = Consent.existing_snapshot(control, binding["project_id"])

      assert {:ok, _} =
               Consent.replace(
                 control,
                 binding["project_id"],
                 current["epoch"],
                 saved["policy"],
                 System.system_time(:millisecond)
               )

      {stale_output, stale_status} =
        System.cmd(
          driver,
          ["--management-review-stale"] ++ command ++ [script, root, "host-orchestrated-stale"],
          stderr_to_stdout: true
        )

      assert stale_status == 0, stale_output
      assert stale_output =~ "PUBLIC_PENDING_REVIEW_HOST-ORCHESTRATED-STALE_PASSED"
    end

    cancel_args =
      ["--management-review-cancel", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
        paths ++
        [
          script,
          root,
          "host-orchestrated-cancel"
        ]

    {cancel_output, cancel_status} = System.cmd(driver, cancel_args, stderr_to_stdout: true)
    assert cancel_status == 0, cancel_output
    assert cancel_output =~ "#{prefix}_HOST-ORCHESTRATED-CANCEL_PASSED"

    assert {:ok, after_cancel} =
             Ipse.Extension.Collection.execute(
               fixture["collection_root"],
               namespace,
               %{"op" => "get", "key" => change["key"]},
               Ipse.Usage.id()
             )

    assert after_cancel == before_cancel

    args =
      ["--management-review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
        paths ++
        [script, root, "host-orchestrated"]

    {output, status} = System.cmd(driver, args, stderr_to_stdout: true)
    assert status == 0, output
    assert output =~ "#{prefix}_HOST-ORCHESTRATED_PASSED"

    if public? do
      assert output =~ "Accepted the selected proposal as your decision"
      assert output =~ "Proposed accepted-decision retention"
      assert output =~ "maximum_age_from_confirmation_ms"
    end

    result =
      root
      |> Path.join("pending-management-host-orchestrated.json")
      |> File.read!()
      |> Jason.decode!()

    assert result["event"]["facts"]["source_proof"] == hd(fixture["sources"])
    assert result["event"]["facts"]["text"] == change["value"]["text"]

    assert {:ok, pending} =
             Ipse.Extension.Collection.execute(
               fixture["collection_root"],
               namespace,
               %{"op" => "get", "key" => change["key"]},
               Ipse.Usage.id()
             )

    "pending." <> id = change["key"]

    assert {:ok, link} =
             Ipse.Extension.Collection.execute(
               fixture["collection_root"],
               namespace,
               %{"op" => "get", "key" => "accept." <> id},
               Ipse.Usage.id()
             )

    assert pending["record"] == nil
    assert link["record"]["value"]["kind"] == "candidate_acceptance_link"

    assert {:ok, note} =
             Ipse.Extension.Collection.execute(
               fixture["collection_root"],
               namespace,
               %{"op" => "get", "key" => link["record"]["value"]["accepted_note_key"]},
               Ipse.Usage.id()
             )

    assert note["record"]["value"]["kind"] == "accepted_decision"
    assert note["record"]["value"]["text"] == change["value"]["text"]

    if public? do
      assert result["accepted_note_key"] == note["record"]["key"]
      assert output =~ "\"accepted_note_key\":\"#{note["record"]["key"]}\""
    end

    duplicate_args =
      ["--management-review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
        paths ++
        [
          script,
          root,
          "host-orchestrated-missing"
        ]

    {duplicate_output, duplicate_status} =
      System.cmd(driver, duplicate_args, stderr_to_stdout: true)

    assert duplicate_status == 0, duplicate_output
    assert duplicate_output =~ "#{prefix}_HOST-ORCHESTRATED-MISSING_PASSED"
    refute duplicate_output =~ "Historical pending candidate;"

    assert {:ok, unchanged} =
             Ipse.Extension.Collection.execute(
               fixture["collection_root"],
               namespace,
               %{"op" => "get", "key" => "accept." <> id},
               Ipse.Usage.id()
             )

    assert unchanged == link

    if options.recall_accepted? do
      exercise_management_journal_budget(
        options.config,
        result["event"]["facts"]["project_id"],
        namespace,
        link["record"]["value"]
      )
    end

    if options.recall_accepted?,
      do:
        exercise_accepted_recall(
          options.config,
          Path.join(root, "work"),
          history_dir,
          result["event"]
        )

    assert {:ok, second_before} =
             Ipse.Extension.Collection.execute(
               fixture["collection_root"],
               namespace,
               %{"op" => "get", "key" => second_change["key"]},
               Ipse.Usage.id()
             )

    File.write!(
      Path.join(root, "pending-management.json"),
      Jason.encode!(%{fixture | "key" => second_change["key"]})
    )

    if public? do
      assert {:ok, binding} = ProjectIdentity.existing(home, Path.join(root, "work"))
      control = SemanticAdmission.control_root(home)
      management = Path.join(home, "knowledge-management")
      before_journals = Path.wildcard(Path.join(management, "*.jsonl"))
      assert {:ok, before_loss} = Consent.existing_snapshot(control, binding["project_id"])

      loss_args =
        ["--management-review-race", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++ [script, root, "host-orchestrated-owner-loss"]

      lost = Task.async(fn -> System.cmd(driver, loss_args, stderr_to_stdout: true) end)
      marker = Path.join(root, "management-review-input-ready")
      release = Path.join(root, "management-review-race-complete")

      {loss_output, loss_status} =
        try do
          assert :ok = wait_for_fixture(marker, System.monotonic_time(:millisecond) + 10_000)
          {pid, ""} = root |> Path.join("public-review-pid") |> File.read!() |> Integer.parse()
          assert {:ok, command} = File.read("/proc/#{pid}/cmdline")
          assert command =~ script and command =~ root
          assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(pid)])
          Task.await(lost, 15_000)
        after
          File.write!(release, "done")
          if Process.alive?(lost.pid), do: Task.yield(lost, 5000)
        end

      assert loss_status != 0, loss_output
      assert loss_output =~ "Historical pending candidate;"
      [journal] = Path.wildcard(Path.join(management, "*.jsonl")) -- before_journals
      assert {:ok, %{events: [header], tail: :none}} = Journal.read_path(journal)
      assert header["metadata"]["kind"] == "knowledge_management"
      lock_path = Path.rootname(journal) <> ".lock"

      assert {:ok, lock} =
               await_released_lock(lock_path, System.monotonic_time(:millisecond) + 5_000)

      assert :ok = Ipse.Runner.unlock(lock)
      assert {:ok, after_loss} = Consent.existing_snapshot(control, binding["project_id"])

      assert [operation_id] =
               Map.keys(after_loss["operations"]) -- Map.keys(before_loss["operations"])

      assert after_loss["operations"][operation_id]["status"] == "admitted"
      assert after_loss["operations"][operation_id]["actual"] == nil

      assert {:ok, %{"control_status" => "admitted", "replayed" => false}} =
               Ipse.CLI.Knowledge.Management.operation(
                 %{home: home},
                 Path.join(root, "work"),
                 operation_id
               )

      File.rm!(marker)
      File.rm!(release)

      assert {:ok, saved} = Consent.existing_snapshot(control, binding["project_id"])
      short = Map.put(saved["policy"], "expires_at_ms", System.system_time(:millisecond) + 8_000)

      assert {:ok, _} =
               Consent.replace(
                 control,
                 binding["project_id"],
                 saved["epoch"],
                 short,
                 System.system_time(:millisecond)
               )

      expiry_args =
        ["--management-review-race", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++ [script, root, "host-orchestrated-expired"]

      running = Task.async(fn -> System.cmd(driver, expiry_args, stderr_to_stdout: true) end)
      marker = Path.join(root, "management-review-input-ready")
      release = Path.join(root, "management-review-race-complete")

      {expired_output, expired_status} =
        try do
          assert :ok = wait_for_fixture(marker, System.monotonic_time(:millisecond) + 10_000)
          Process.sleep(max(short["expires_at_ms"] - System.system_time(:millisecond) + 50, 0))
          File.write!(release, "done")
          Task.await(running, 15_000)
        after
          File.write!(release, "done")
          if Process.alive?(running.pid), do: Task.yield(running, 5000)
        end

      assert expired_status == 0, expired_output
      assert expired_output =~ "PUBLIC_PENDING_REVIEW_HOST-ORCHESTRATED-EXPIRED_PASSED"
      File.rm!(marker)
      File.rm!(release)
      assert {:ok, current} = Consent.existing_snapshot(control, binding["project_id"])

      assert {:ok, _} =
               Consent.replace(
                 control,
                 binding["project_id"],
                 current["epoch"],
                 saved["policy"],
                 System.system_time(:millisecond)
               )
    end

    multi_policy =
      if options.recall_accepted? do
        assert {:ok, b} = ProjectIdentity.existing(home, Path.join(root, "work"))

        assert {:ok, snapshot} =
                 Consent.existing_snapshot(SemanticAdmission.control_root(home), b["project_id"])

        snapshot["policy"]
      end

    revoked_args =
      ["--management-review-race", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
        paths ++
        [
          script,
          root,
          "host-orchestrated-revoked"
        ]

    running = Task.async(fn -> System.cmd(driver, revoked_args, stderr_to_stdout: true) end)
    marker = Path.join(root, "management-review-input-ready")
    release = Path.join(root, "management-review-race-complete")

    {revoked_output, revoked_status} =
      try do
        assert :ok = wait_for_fixture(marker, System.monotonic_time(:millisecond) + 10_000)
        assert {:ok, binding} = ProjectIdentity.existing(home, Path.join(root, "work"))
        control = SemanticAdmission.control_root(home)
        assert {:ok, snapshot} = Consent.existing_snapshot(control, binding["project_id"])
        assert {:ok, _} = Consent.revoke(control, binding["project_id"], snapshot["epoch"])
        File.write!(release, "done")
        Task.await(running, 15_000)
      after
        File.write!(release, "done")
        if Process.alive?(running.pid), do: Task.yield(running, 5000)
      end

    assert revoked_status == 0, revoked_output
    assert revoked_output =~ "#{prefix}_HOST-ORCHESTRATED-REVOKED_PASSED"

    assert {:ok, second_after} =
             Ipse.Extension.Collection.execute(
               fixture["collection_root"],
               namespace,
               %{"op" => "get", "key" => second_change["key"]},
               Ipse.Usage.id()
             )

    assert second_after == second_before
    "pending." <> second_id = second_change["key"]

    assert {:ok, second_link} =
             Ipse.Extension.Collection.execute(
               fixture["collection_root"],
               namespace,
               %{"op" => "get", "key" => "accept." <> second_id},
               Ipse.Usage.id()
             )

    assert second_link["record"] == nil

    if public? do
      {index_output, index_status} =
        System.cmd(
          System.find_executable("elixir"),
          ["--erl", "+S 2:2"] ++ paths ++ [script, root, "index"],
          stderr_to_stdout: true
        )

      assert index_status == 0, index_output
      assert index_output =~ "PUBLIC_PENDING_REVIEW_INDEX_PASSED"
      refute index_output =~ second_change["value"]["text"]
    end

    if options.recall_accepted? do
      assert {:ok, b} = ProjectIdentity.existing(home, Path.join(root, "work"))
      control = SemanticAdmission.control_root(home)
      assert {:ok, revoked} = Consent.existing_snapshot(control, b["project_id"])

      assert {:ok, _} =
               Consent.replace(
                 control,
                 b["project_id"],
                 revoked["epoch"],
                 multi_policy,
                 System.system_time(:millisecond)
               )

      File.rename!(
        Path.join(root, "pending-management-host-orchestrated.json"),
        Path.join(root, "pending-management-first-receipt.json")
      )

      {output, status} =
        System.cmd(
          driver,
          ["--management-review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
            paths ++
            [script, root, "host-orchestrated"],
          stderr_to_stdout: true
        )

      assert status == 0, output
      assert output =~ "Accepted the selected proposal as your decision"

      second =
        root
        |> Path.join("pending-management-host-orchestrated.json")
        |> File.read!()
        |> Jason.decode!()

      assert second["event"]["facts"]["journal_id"] != result["event"]["facts"]["journal_id"]

      exercise_accepted_recall(options.config, Path.join(root, "work"), history_dir, [
        result["event"],
        second["event"]
      ])

      peer_key = second["accepted_note_key"]
      assert is_binary(peer_key)

      File.write!(
        Path.join(root, "accepted-forget.json"),
        Jason.encode!(%{
          "namespace" => namespace,
          "key" => result["accepted_note_key"],
          "link_key" => link["record"]["key"],
          "peer_key" => peer_key,
          "history_dir" => history_dir,
          "event" => result["event"],
          "note_recipe" => sidecar["recipes"]["note"]
        })
      )

      for {mode, driver_mode} <- [
            {"cancel", "--management-review-cancel"},
            {"forget", "--assertion"}
          ] do
        {output, status} =
          System.cmd(
            driver,
            [driver_mode, System.find_executable("elixir"), "--erl", "+S 2:2"] ++
              paths ++
              [Path.expand("test/support/accepted_decision_forget_cli.exs"), root, mode],
            stderr_to_stdout: true,
            cd: root
          )

        File.write!(Path.join(root, "accepted-#{mode}.log"), output)
        assert status == 0, output
        assert output =~ "NATIVE_ACCEPTED_DECISION_#{String.upcase(mode)}_PASSED"
      end
    end
  end

  defp wait_for_fixture(path, deadline) do
    cond do
      File.exists?(path) ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, :timeout}

      true ->
        Process.sleep(25)
        wait_for_fixture(path, deadline)
    end
  end

  defp await_released_lock(path, deadline) do
    case Ipse.Runner.lock(path) do
      {:ok, _} = acquired ->
        acquired

      error ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(20)
          await_released_lock(path, deadline)
        else
          error
        end
    end
  end

  defp exercise_management_journal_budget(config, project, namespace, link) do
    alias Ipse.Session.Resources

    assert {:ok, scope} = Resources.start(self())
    previous = Resources.bind(scope)

    try do
      assert {:ok, :checked} =
               Resources.file_effect(fn ->
                 tickets =
                   for _ <- 1..32 do
                     assert {:ok, ticket} = Resources.register(:http)
                     assert is_map(ticket)
                     ticket
                   end

                 try do
                   assert {:ok, :checked} =
                            Ipse.Session.PendingAcceptance.with_committed_management_journal(
                              config.home,
                              project,
                              namespace,
                              link,
                              fn checked ->
                                assert JSON.digest([checked.event]) ==
                                         link["acceptance_event_sha256"]

                                {:ok, :checked}
                              end
                            )

                   assert {:ok, token} =
                            Ipse.Session.PendingAcceptance.with_shareable_committed_management_journals(
                              config.home,
                              project,
                              namespace,
                              [link, link],
                              fn checked, [lease] ->
                                assert JSON.digest([checked[link["journal_id"]].event]) ==
                                         link["acceptance_event_sha256"]

                                assert {:ok, _} =
                                         Ipse.Session.PendingAcceptance.journal_share_verified_identity(
                                           lease.token,
                                           link
                                         )

                                assert {:error, _} =
                                         Ipse.Session.PendingAcceptance.journal_share_identity(
                                           make_ref()
                                         )

                                assert {:error, _} =
                                         Ipse.Session.PendingAcceptance.journal_share_verified_identity(
                                           lease.token,
                                           Map.put(
                                             link,
                                             "acceptance_event_sha256",
                                             String.duplicate("0", 64)
                                           )
                                         )

                                foreign =
                                  Task.async(fn ->
                                    Ipse.Session.PendingAcceptance.journal_share_identity(
                                      lease.token
                                    )
                                  end)

                                assert {:error, _} = Task.await(foreign, 5_000)
                                {:ok, lease.token}
                              end
                            )

                   assert {:error, _} =
                            Ipse.Session.PendingAcceptance.journal_share_identity(token)

                   assert {:error, _} =
                            Ipse.Session.PendingAcceptance.with_shareable_committed_management_journals(
                              config.home,
                              project,
                              namespace,
                              [
                                link,
                                Map.put(
                                  link,
                                  "acceptance_event_sha256",
                                  String.duplicate("0", 64)
                                )
                              ],
                              fn _, _ ->
                                flunk("conflicting journal identities reached a callback")
                              end
                            )

                   {:ok, :checked}
                 after
                   Enum.each(tickets, &Resources.closed(&1, :ok))
                 end
               end)
    after
      Resources.bind(previous)
      assert :ok = Resources.close(scope)
    end
  end

  defp exercise_accepted_recall(config, cwd, history_dir, event) do
    multiple = is_list(event)
    {base, listener, server} = accepted_recall_server(if(multiple, do: 1, else: 3))

    on_exit(fn ->
      :gen_tcp.close(listener)
      if Process.alive?(server.pid), do: Process.exit(server.pid, :kill)
    end)

    config =
      config
      |> Map.delete(:provider_module)
      |> Map.merge(%{
        provider: :ollama,
        base_url: base,
        timeout_ms: 5000,
        max_output_tokens: 64,
        inference_services: %{
          if(multiple, do: "multi_recall", else: "local") => %{
            "version" => 1,
            "origins" => [base]
          }
        }
      })

    assert {:ok, binding} = ProjectIdentity.existing(config.home, cwd)

    assert {:ok, snapshot} =
             Consent.existing_snapshot(
               SemanticAdmission.control_root(config.home),
               binding["project_id"]
             )

    assert {:ok, catalog} = Catalog.snapshot(config)

    jobs =
      for descriptor <- catalog["entries"],
          descriptor["stage"] == "event.job",
          do: JSON.digest([descriptor])

    policy =
      update_in(snapshot["policy"], ["settings", "effects"], fn effects ->
        Enum.reject(
          effects,
          &(&1["outer_sha256"] in jobs and &1["class"] == "collection.publish")
        )
      end)

    assert {:ok, selectors} =
             Ipse.Extension.SemanticRoutes.selectors(policy["settings"]["routes"])

    assert {:ok, routes} = Ipse.Extension.SemanticRoutes.resolve(config, selectors)
    policy = put_in(policy, ["settings", "routes"], routes)

    assert {:ok, _} =
             Consent.replace(
               SemanticAdmission.control_root(config.home),
               binding["project_id"],
               snapshot["epoch"],
               policy,
               System.system_time(:millisecond)
             )

    assert {:ok, selections} = Ipse.Config.Semantics.selection(policy)

    config = Map.put(config, :semantic_selections, selections)
    text = if multiple, do: Enum.map(event, & &1["facts"]["text"]), else: event["facts"]["text"]
    accepted_recall_session(config, cwd, history_dir, text, true)

    unless multiple do
      source_path =
        Path.join(history_dir, event["facts"]["source_proof"]["session_id"] <> ".jsonl")

      withheld_path = source_path <> ".withheld"
      File.rename!(source_path, withheld_path)

      try do
        accepted_recall_session(config, cwd, history_dir, text, false)
      after
        File.rename!(withheld_path, source_path)
      end

      journal_path =
        Path.join([config.home, "knowledge-management", event["facts"]["journal_id"] <> ".jsonl"])

      journal = File.read!(journal_path)
      corrupted = String.replace(journal, Jason.encode!(text), Jason.encode!(text <> " tampered"))
      assert corrupted != journal
      File.write!(journal_path, corrupted)

      try do
        accepted_recall_session(config, cwd, history_dir, text, false)
      after
        File.write!(journal_path, journal)
      end
    end

    assert :ok = Task.await(server, 1000)
  end

  defp accepted_recall_session(config, cwd, history_dir, text, eligible?) do
    assert {:ok, session} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, config: config, cwd: cwd, state_dir: history_dir, subscriber: self()}
             )

    try do
      input_owners =
        if eligible?, do: inspect_accepted_input_owners(session, config, history_dir, text)

      assert :ok = Session.prompt(session, "Which decision was accepted?")
      assert_receive {:ipse, ^session, {:done, status}}, 30_000

      if status != :ok do
        assert {:ok, events} = Journal.load(history_dir, Session.info(session).id)

        reason =
          receive do
            {:ipse, ^session, {:error, reason}} -> reason
          after
            0 -> :missing_error
          end

        flunk(
          "Accepted recall ended #{status} (#{inspect(reason)}): #{inspect(Enum.map(events, &recall_trace/1), limit: :infinity)}"
        )
      end

      assert_receive {:accepted_recall_request, messages}, 5_000
      rendered = Jason.encode!(messages)
      assert {:ok, events} = Journal.load(history_dir, Session.info(session).id)

      if eligible? and not String.contains?(rendered, "note_parts_v2") do
        trace =
          for event <- events,
              String.starts_with?(event["type"], ["extension", "managed", "reference", "context"]),
              do: recall_trace(event)

        flunk(
          "Fresh Session omitted typed accepted-decision recall: #{inspect(trace, limit: :infinity)}"
        )
      end

      accepted_read? =
        Enum.any?(events, fn event ->
          event["type"] == "managed_read_observed" and
            Enum.any?(event["dependencies"], &(&1["version"] === 6))
        end)

      assert accepted_read? == eligible?
      if input_owners, do: assert(:owners_checked == Task.await(input_owners, 5_000))

      if eligible? do
        assert rendered =~ "accepted_decision"
        for item <- List.wrap(text), do: assert(rendered =~ item)
      else
        refute rendered =~ "note_parts_v2"
        for item <- List.wrap(text), do: refute(rendered =~ item)

        assert Enum.any?(events, fn event ->
                 event["type"] == "extension_action_result" and
                   get_in(event, ["request", "request", "op"]) == "get" and
                   get_in(event, ["outcome", "status"]) == "failed"
               end)
      end

      assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(session).id)
      assert :ok = Session.close_confirmed(session)
    after
      if Process.alive?(session), do: Session.close(session)
    end
  end

  # Observe the actual importer under a one-use BEAM pause, before its unchanged
  # native write. The Session, publisher and Worker supply every real handle.
  defp inspect_accepted_input_owners(session, config, history, text) do
    expected = List.wrap(text)

    checker =
      Task.async(fn ->
        receive do
          {:accepted_pipe, controller, cap, frame} ->
            try do
              state = :sys.get_state(session)
              pending = state.invocation.worker_input
              barrier = state.share_barrier
              dependencies = Enum.filter(pending.snapshot.dependencies, &(&1["version"] == 6))
              assert length(dependencies) == length(expected)
              assert pending.binding.frame === frame and pending.caller == cap.owner
              <<size::32, bytes::binary-size(size)>> = frame
              assert %{"stage" => "host.actions", "payload" => payload} = Jason.decode!(bytes)
              record = get_in(payload, ["outcome", "value", "record", "value"])
              assert record["kind"] == "accepted_decision" and record["text"] in expected

              originals =
                Enum.map(dependencies, fn dependency ->
                  journal = dependency["subject"]["acceptance"]["journal_id"]

                  assert {:ok, %{events: events}} =
                           Journal.read_path(
                             Path.join([config.home, "knowledge-management", journal <> ".jsonl"])
                           )

                  [accepted] = Enum.filter(events, &(&1["type"] == "pending_proposal_accepted"))

                  assert JSON.digest([accepted]) ==
                           dependency["subject"]["acceptance"]["event_sha256"]

                  {journal, accepted["facts"]["source_proof"]["session_id"]}
                end)

              native = barrier.owner_recipient
              assert native == barrier.writer_recipient
              assert {:os_pid, supervisor} = Port.info(cap.port, :os_pid)
              assert native != supervisor
              helper = File.stat!("/proc/#{supervisor}/exe")
              actual = File.stat!("/proc/#{native}/exe")
              assert {helper.major_device, helper.inode} == {actual.major_device, actual.inode}

              identities =
                for fd <- File.ls!("/proc/#{native}/fd"),
                    {:ok, stat} <- [File.stat("/proc/#{native}/fd/#{fd}")],
                    do: {stat.major_device, stat.inode}

              pin = state.config.semantic_admission["pin"]

              paths =
                [
                  Path.join([config.home, "project-identities", ".lock"]),
                  Path.join([
                    SemanticAdmission.control_root(config.home),
                    pin["project_id"],
                    ".lock"
                  ]),
                  Path.join([
                    SemanticAdmission.collection_root(config.home),
                    pin["namespace"],
                    ".lock"
                  ]),
                  Path.join(history, state.id <> ".lock")
                ] ++
                  Enum.flat_map(originals, fn {journal, original} ->
                    [
                      Path.join(history, original <> ".lock"),
                      Path.join([config.home, "knowledge-management", journal <> ".lock"])
                    ]
                  end)

              for path <- paths do
                stat = File.stat!(path)
                assert {stat.major_device, stat.inode} in identities
                assert {:error, _} = Ipse.Runner.lock(path)
              end

              writer = :sys.get_state(state.journal_writer).share_barrier.writer_control
              assert {writer.device, writer.inode} in identities
              assert {:os_pid, owner} = Port.info(barrier.owner_port, :os_pid)
              control = File.stat!("/proc/#{owner}/fd/0")
              assert {control.major_device, control.inode} in identities
              worker = :sys.get_state(pending.worker)
              assert worker.input.phase == :exported

              assert {worker.input.binding.pipe.device, worker.input.binding.pipe.inode} in identities

              :owners_checked
            after
              send(controller, :release_accepted_pipe)
            end
        after
          20_000 -> flunk("accepted content never reached the actual native Worker writer")
        end
      end)

    hook = fn
      true, _, _ ->
        true

      _, {:in, {_, {publisher, _}, {:session_control_ticket_worker_input, _, _, _, proofs, _}}}, _
      when length(proofs) >= length(expected) ->
        {:dictionary, dictionary} = Process.info(publisher, :dictionary)
        {_, controller} = List.keyfind(dictionary, {Ipse.Runner.Transaction, :controller}, 0)

        gate = fn
          :released, _, _ ->
            :released

          _, {:in, {_, _, {:pipe_write, cap, _, frame}}}, _ ->
            send(checker.pid, {:accepted_pipe, self(), cap, frame})

            receive do
              :release_accepted_pipe -> :released
            after
              5_000 -> flunk("accepted-input owner inspection did not finish")
            end

          d, _, _ ->
            d
        end

        assert :ok = :sys.install(controller, {gate, nil})
        true

      d, _, _ ->
        d
    end

    assert :ok = :sys.install(session, {hook, false})
    checker
  end

  # Two ordinary capture turns, using the real registered Ollama adapter rather
  # than a provider-module override once managed dependencies enter history.
  defp registered_capture_config(config) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    base = "http://127.0.0.1:#{port}"

    server =
      Task.async(fn ->
        try do
          for number <- 1..6 do
            {:ok, socket} = :gen_tcp.accept(listener, 30_000)

            try do
              {_, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
              messages = Jason.decode!(bytes)["messages"]

              message =
                if rem(number, 3) == 0 do
                  %{
                    "role" => "assistant",
                    "content" => "The unattended observation is pending review."
                  }
                else
                  {name, arguments} =
                    if rem(number, 3) == 1 do
                      {"source_list", %{"limit" => 32}}
                    else
                      result = Enum.find(Enum.reverse(messages), &(&1["role"] == "tool"))
                      sources = Jason.decode!(result["content"])["sources"]
                      source = Enum.find(Enum.reverse(sources), &(&1["kind"] == "input.original"))

                      text =
                        Enum.at(
                          ["Acme has owner Alex", "Beta has owner Mira"],
                          div(number - 1, 3)
                        )

                      {"ext__knowledge__capture",
                       %{
                         "text" => text,
                         "category" => "ordinary",
                         "reason" => "selected observation",
                         "event_at_ms" => nil,
                         "source" => %{"handle" => source["read_handle"], "quote" => text}
                       }}
                    end

                  %{
                    "role" => "assistant",
                    "content" => "",
                    "tool_calls" => [%{"function" => %{"name" => name, "arguments" => arguments}}]
                  }
                end

              body =
                Jason.encode!(%{
                  "model" => "synthetic",
                  "message" => message,
                  "done" => true,
                  "prompt_eval_count" => 1,
                  "eval_count" => 1
                }) <> "\n"

              :ok =
                :gen_tcp.send(
                  socket,
                  "HTTP/1.1 200 Fixture\r\ncontent-type: application/x-ndjson\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                    body
                )
            after
              :gen_tcp.close(socket)
            end
          end
        after
          :gen_tcp.close(listener)
        end
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      if Process.alive?(server.pid), do: Process.exit(server.pid, :kill)
    end)

    config
    |> Map.delete(:provider_module)
    |> Map.merge(%{
      provider: :ollama,
      base_url: base,
      timeout_ms: 5000,
      max_output_tokens: 64,
      inference_services: %{"capture" => %{"version" => 1, "origins" => [base]}}
    })
  end

  defp accepted_recall_server(count) do
    owner = self()
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        for _ <- 1..count do
          {:ok, socket} = :gen_tcp.accept(listener, 30_000)

          try do
            {_, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
            send(owner, {:accepted_recall_request, Jason.decode!(bytes)["messages"]})

            body =
              Jason.encode!(%{
                "model" => "synthetic",
                "message" => %{
                  "role" => "assistant",
                  "content" => "The recorded decision remains attributed."
                },
                "done" => true,
                "prompt_eval_count" => 1,
                "eval_count" => 1
              }) <> "\n"

            :ok =
              :gen_tcp.send(
                socket,
                "HTTP/1.1 200 Fixture\r\ncontent-type: application/x-ndjson\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                  body
              )
          after
            :gen_tcp.close(socket)
          end
        end

        :ok
      end)

    Process.unlink(task.pid)
    {"http://127.0.0.1:#{port}", listener, task}
  end

  defp recall_trace(event) do
    request = if is_map(event["request"]), do: event["request"], else: %{}
    inner = if is_map(request["request"]), do: request["request"], else: %{}
    outcome = if is_map(event["outcome"]), do: event["outcome"], else: %{}
    value = if is_map(outcome["value"]), do: outcome["value"], else: %{}

    %{
      type: event["type"],
      operation: request["op"],
      inner: inner["op"],
      status: outcome["status"] || event["status"] || event["outcome"],
      code: value["code"],
      delivery:
        Map.take(event["delivery"] || event["value"] || %{}, ~w(status code included coverage)),
      decision: event["decision"]
    }
  end

  defp stage_isolated_bundle(output, requested) do
    bundle = Application.app_dir(:ipse, "priv/extension-bundles") |> Path.expand()
    assert Path.expand(requested) == bundle
    assert {:ok, parent} = Ipse.Workspace.canonical_path(Path.dirname(bundle))
    assert String.starts_with?(parent <> "/", Path.expand(System.tmp_dir!()) <> "/")
    assert {:error, :enoent} = File.lstat(bundle)
    File.mkdir!(bundle)
    File.cp_r!(output, Path.join(bundle, "knowledge"))
    digest = JSON.sha256(File.read!(Path.join(output, "extension.json")))

    catalog = %{
      "version" => 1,
      "artifacts" => [%{"id" => "knowledge", "path" => "knowledge", "manifest_sha256" => digest}]
    }

    File.write!(Path.join(bundle, "catalog.json"), Jason.encode!(catalog), [:exclusive])
    assert {:ok, [%{digest: ^digest}]} = Ipse.Extension.Bundles.inventory()
  end
end
