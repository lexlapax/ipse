Code.require_file("candidate_assessment_session.exs", __DIR__)

defmodule Ipse.Development.Evaluation.CandidateAssessmentRecipe do
  @moduledoc "Synthetic standalone assessment materialization; labels are deliberately non-independent."
  import ExUnit.Assertions
  alias Ipse.{JSON, Journal, Session}
  alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission, SemanticConsent}
  alias Ipse.Development.Evaluation.CandidateAssessment, as: Assessment
  alias Ipse.Development.Evaluation.CandidateAssessmentSession, as: Owner

  @rubric "Choose keep_baseline or defer_candidate for this already proposed candidate. Defer only when ambiguity, conflict or low durability warrants omitting this capture. Advice cannot change evidence, origin, text, category, retention or permission."

  # Called only after the ordinary main-tool fixture has captured and closed its source.
  def freeze(root, runtime, source_id, key, capture_operation, config_path, base) do
    root = Path.expand(root)
    assert String.starts_with?(Path.basename(root), "ipse-candidate-shadow-")
    assert {:ok, project} = ProjectIdentity.existing(runtime.home, Path.join(root, "project"))
    assert is_map(project)
    assert {:ok, runtime} = Ipse.Config.Activation.fresh(runtime, Path.join(root, "project"))

    assert {:ok, policy} =
             Consent.existing_snapshot(
               SemanticAdmission.control_root(runtime.home),
               project["project_id"]
             )

    assert {:ok, namespace} = SemanticConsent.namespace(project["project_id"], "knowledge")

    assert {:ok, %{"record" => record}} =
             Collection.execute(
               SemanticAdmission.collection_root(runtime.home),
               namespace,
               %{"op" => "get", "key" => key},
               Ipse.Usage.id()
             )

    source_path = Path.join([root, "sessions", source_id <> ".jsonl"])
    assert {:ok, events} = Journal.load(Path.dirname(source_path), source_id)
    assert {:ok, _} = Session.Saved.restore(events, source_id)
    journal_sha = JSON.sha256(File.read!(source_path))

    input = %{
      "candidate_id" => record["value"]["id"],
      "text" => record["value"]["text"],
      "assigned_category" => record["value"]["assigned_category"],
      "reason" => record["value"]["reason"]
    }

    source = %{"version" => 1, "session_id" => source_id, "journal_sha256" => journal_sha}
    input_sha = blob(root, input)
    source_sha = blob(root, source)

    baseline_sha =
      blob(root, %{
        "version" => 1,
        "case_id" => source_id,
        "input_sha256" => input_sha,
        "source_receipt_sha256" => source_sha,
        "candidate_key" => key,
        "stratum" => "pending",
        "baseline" => "keep",
        "admission" => "pending",
        "journal_sha256" => journal_sha,
        "operation_id" => capture_operation,
        "elapsed_ms" => nil,
        "cost_nanos" => nil
      })

    labels = %{
      "version" => 1,
      "reviewer_id" => "scripted-protocol-only",
      "independent" => false,
      "rows" => [
        %{"case_id" => source_id, "false" => false, "useful" => false, "critical" => false}
      ]
    }

    labels_sha = blob(root, labels)

    [entry] =
      Enum.filter(runtime.extensions, &(get_in(&1, [:identity, "instance"]) === "knowledge"))

    sources = source_commitment()
    objects = runtime_commitment()

    assert {:ok, declaration} =
             Assessment.declare(%{
               "version" => 1,
               "kind" => "candidate_shadow",
               "source_sha256" => JSON.digest([sources]),
               "runtime_sha256" => JSON.digest([objects]),
               "artifact_sha256" => entry.identity["artifact_sha256"],
               "main_route_sha256" => Owner.route_digest(runtime),
               "policy_sha256" => JSON.digest([policy["policy"]]),
               "decision_route" => %{
                 "engine" => "compatible_loopback",
                 "model" => "synthetic",
                 "rubric_sha256" => JSON.sha256(@rubric),
                 "availability" => "unverified_access"
               },
               "label_commitment" => labels_sha,
               "shared_limits" => policy["policy"]["limits"],
               "cases" => [
                 %{
                   "id" => source_id,
                   "stratum" => "pending",
                   "candidate_key" => key,
                   "input_sha256" => input_sha,
                   "source_receipt_sha256" => source_sha,
                   "baseline_sha256" => baseline_sha
                 }
               ]
             })

    assert policy["policy"]["limits"]["model_calls"] === 1
    save(root, "declaration.json", declaration)

    save(root, "recipe.json", %{
      "version" => 1,
      "root" => root,
      "case_id" => source_id,
      "key" => key,
      "config_path" => config_path,
      "config_sha256" => file_sha(config_path),
      "base_url" => base,
      "declaration_sha256" => JSON.digest([declaration]),
      "candidate_record_sha256" => JSON.digest([record]),
      "ledger_ids" => Enum.sort(Map.keys(policy["operations"])),
      "policy_epoch" => policy["epoch"],
      "source_commitment" => sources,
      "runtime_commitment" => objects,
      "expected_main_requests" => 2,
      "expected_decision_requests" => 1,
      "quality" => "unverified",
      "matched_elapsed_ms" => nil,
      "whole_cost_nanos" => nil
    })
  end

  # The caller must use this exact case output as the existing native PTY root.
  def run(recipe_path, output) do
    recipe = read(recipe_path)
    root = recipe["root"]
    assert recipe_path === Path.join(root, "recipe.json")
    assert output === Path.join([root, "cases", recipe["case_id"]])
    assert recipe["config_path"] === Path.join([root, "home", "config.json"])
    assert file_sha(recipe["config_path"]) === recipe["config_sha256"]
    assert source_commitment() === recipe["source_commitment"]
    assert runtime_commitment() === recipe["runtime_commitment"]

    for key <-
          ~w(IPSE_PROVIDER IPSE_MODEL IPSE_SANDBOX IPSE_MAX_STEPS IPSE_CONTEXT_BYTES IPSE_COMPACT IPSE_SUBAGENTS IPSE_SUBAGENT_CONCURRENCY IPSE_TIMEOUT_MS IPSE_MAX_OUTPUT_TOKENS IPSE_PROFILE IPSE_CONFIG),
        do: System.delete_env(key)

    System.put_env("IPSE_HOME", Path.join(root, "home"))

    assert {:ok, effective} =
             Ipse.Config.resolve(
               Path.join(root, "project"),
               Path.join(root, "home"),
               [config: recipe["config_path"], project_config: false],
               %{}
             )

    client = %{
      workspace: Path.join(root, "project"),
      home: Path.join(root, "home"),
      auth_dir: Path.join([root, "home", "auth"]),
      operator_home: root,
      mcp_config: nil,
      base_url: nil,
      operator_questions: false,
      accept_edits: false,
      approval: :ask,
      approval_origin: :interactive,
      headless: false
    }

    assert {:ok, runtime} = Ipse.Config.runtime(effective, client)
    assert {:ok, existing_project} = ProjectIdentity.existing(runtime.home, client.workspace)
    assert is_map(existing_project)
    assert {:ok, runtime} = Ipse.Config.Activation.fresh(runtime, client.workspace)
    assert runtime.provider === :ollama and runtime.model === "synthetic"
    assert runtime.base_url === recipe["base_url"]
    assert get_in(runtime, [:decision_profiles, "advice", "base_url"]) === recipe["base_url"]
    declaration = read(Path.join(root, "declaration.json"))
    load = fn sha -> File.read(Path.join([root, "blobs", sha <> ".json"])) end

    options = %{
      enabled: true,
      root: root,
      output: output,
      cwd: client.workspace,
      state_dir: Path.join(root, "sessions"),
      config: runtime
    }

    assert {:ok, _} =
             Owner.prepare(
               declaration,
               recipe["declaration_sha256"],
               recipe["case_id"],
               load,
               options
             )

    {listener, server} = server(recipe["base_url"], recipe["key"], root)

    try do
      assert {:ok, row} =
               Owner.run(
                 declaration,
                 recipe["declaration_sha256"],
                 recipe["case_id"],
                 load,
                 options
               )

      assert row["status"] === "ok" and row["choice"] === "keep_baseline"
      assert is_nil(row["elapsed_ms"]) and is_nil(row["cost_nanos"])

      assert {:ok, first} =
               Assessment.freeze_rows(declaration, recipe["declaration_sha256"], [row])

      save(root, "first-rows.json", first)
      first_sha = JSON.digest([first])
      save(root, "first-rows-commitment.json", %{"sha256" => first_sha})
      # Read labels only after reopening the durable first-row commitment.
      label_marker = make_ref()

      labels = fn ->
        assert read(Path.join(root, "first-rows.json")) === first
        assert read(Path.join(root, "first-rows-commitment.json"))["sha256"] === first_sha
        assert {:ok, bytes} = load.(declaration["spec"]["label_commitment"])
        assert Jason.decode!(bytes)["independent"] === false
        send(self(), {:synthetic_labels_opened, label_marker})
        {:ok, bytes}
      end

      assert {:error, :invalid_candidate_experiment} =
               Assessment.score(
                 declaration,
                 recipe["declaration_sha256"],
                 first,
                 first_sha,
                 labels,
                 load
               )

      assert_receive {:synthetic_labels_opened, ^label_marker}
      complete = read(Path.join(output, "complete.json"))

      assert complete["collection_unchanged"] === true and
               complete["strict_saved_idle_no_replay"] === true

      assert complete["row_sha256"] === JSON.digest([row])
      assert {:ok, project} = ProjectIdentity.existing(runtime.home, client.workspace)

      assert {:ok, after_policy} =
               Consent.existing_snapshot(
                 SemanticAdmission.control_root(runtime.home),
                 project["project_id"]
               )

      assert after_policy["epoch"] === recipe["policy_epoch"]
      assert JSON.digest([after_policy]) === complete["ledger_snapshot_sha256"]
      [settled_id] = Map.keys(after_policy["operations"]) -- recipe["ledger_ids"]
      assert after_policy["operations"][settled_id]["status"] === "settled"
      assert {:ok, namespace} = SemanticConsent.namespace(project["project_id"], "knowledge")

      assert {:ok, %{"record" => current_candidate}} =
               Collection.execute(
                 SemanticAdmission.collection_root(runtime.home),
                 namespace,
                 %{"op" => "get", "key" => recipe["key"]},
                 Ipse.Usage.id()
               )

      assert JSON.digest([current_candidate]) === recipe["candidate_record_sha256"]
      send(server.pid, :assessment_returned)
      requests = Task.await(server, 5000)
      assert Enum.map(requests, & &1["kind"]) === ["main", "decision", "main"]

      save(root, "protocol-result.json", %{
        "version" => 1,
        "materialized_row_status" => row["status"],
        "declaration_sha256" => recipe["declaration_sha256"],
        "first_rows_sha256" => first_sha,
        "main_requests" => 2,
        "seed_main_requests" => 5,
        "total_main_requests" => 7,
        "decision_requests" => 1,
        "known_settled_decision_calls" => 1,
        "synthetic_labels_rejected" => true,
        "labels_loader_invoked" => true,
        "quality" => "unverified",
        "disposition" => "unverified",
        "qualified_default" => false,
        "matched_elapsed_ms" => nil,
        "whole_cost_nanos" => nil
      })

      assert source_commitment() === recipe["source_commitment"]
      assert runtime_commitment() === recipe["runtime_commitment"]
      :ok
    after
      :gen_tcp.close(listener)
      Task.shutdown(server, :brutal_kill)
    end
  end

  defp server(base, key, root) do
    uri = URI.parse(base)

    assert uri.scheme === "http" and uri.host === "127.0.0.1" and is_integer(uri.port) and
             uri.port > 0

    assert {:ok, listener} =
             :gen_tcp.listen(uri.port, [
               :binary,
               active: false,
               reuseaddr: true,
               ip: {127, 0, 0, 1}
             ])

    task =
      Task.async(fn ->
        requests =
          Enum.with_index([:main, :decision, :main], 1)
          |> Enum.map(fn {kind, index} ->
            assert {:ok, socket} = :gen_tcp.accept(listener, 30_000)

            try do
              {headers, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
              request = Jason.decode!(bytes)

              save(root, "wire-#{index}.json", %{
                "kind" => Atom.to_string(kind),
                "request" => request
              })

              assert String.starts_with?(
                       headers,
                       if(kind === :decision, do: "POST /systemone ", else: "POST /api/chat ")
                     )

              response =
                if kind === :decision do
                  %{
                    "model" => "synthetic",
                    "answers" => %{
                      "candidate" => %{
                        "type" => "choice",
                        "choice" => "keep_baseline",
                        "confidence" => 0.9,
                        "probabilities" => %{"keep_baseline" => 0.9, "defer_candidate" => 0.1}
                      }
                    },
                    "usage" => %{"input_tokens" => 10, "output_tokens" => 2}
                  }
                else
                  assessed =
                    Enum.any?(
                      request["messages"],
                      &(&1["role"] === "tool" and &1["tool_name"] === "ext__knowledge__assess")
                    )

                  message =
                    if assessed,
                      do: %{"role" => "assistant", "content" => "Fixture finished."},
                      else: %{
                        "role" => "assistant",
                        "content" => "",
                        "tool_calls" => [
                          %{
                            "function" => %{
                              "name" => "ext__knowledge__assess",
                              "arguments" => %{"key" => key}
                            }
                          }
                        ]
                      }

                  %{
                    "model" => "synthetic",
                    "message" => message,
                    "done" => true,
                    "prompt_eval_count" => 1,
                    "eval_count" => 1
                  }
                end

              body = Jason.encode!(response) <> if(kind === :main, do: "\n", else: "")

              assert :ok =
                       :gen_tcp.send(
                         socket,
                         "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                           body
                       )

              %{"kind" => Atom.to_string(kind), "request_sha256" => JSON.digest([request])}
            after
              :gen_tcp.close(socket)
            end
          end)

        # Terminal consumes client messages; withhold the Task reply until it has returned.
        receive do
          :assessment_returned -> requests
        after
          60_000 -> raise("Assessment owner did not return before fixture coordination expired")
        end
      end)

    {listener, task}
  end

  defp source_commitment do
    paths =
      Enum.map(
        ~w(candidate_assessment_recipe candidate_assessment_session candidate_assessment decision_metrics metrics),
        &Path.join(__DIR__, &1 <> ".exs")
      ) ++
        Enum.map(
          ~w(shadow_pending_candidate_cli.exs candidate_assessment_evaluation_cli.exs provider_fixture.ex operator_pty.rs),
          &Path.expand("../../test/support/" <> &1, __DIR__)
        )

    Map.new(paths, &{Path.relative_to_cwd(&1), file_sha(&1)})
  end

  defp runtime_commitment do
    library = Path.dirname(Application.app_dir(:ipse))

    paths =
      Path.wildcard(library <> "/*/ebin/*.beam") ++ Path.wildcard(library <> "/*/ebin/*.app")

    assert paths !== []
    assert {:ok, helper} = Ipse.Runner.protected_helper_digest()

    %{
      "ebin_files" => Map.new(paths, &{Path.relative_to(&1, library), file_sha(&1)}),
      "protected_helper_sha256" => helper,
      "otp" => System.otp_release(),
      "elixir" => System.version()
    }
  end

  defp blob(root, value) do
    bytes = Jason.encode!(value)
    sha = JSON.sha256(bytes)
    File.mkdir_p!(Path.join(root, "blobs"))
    path = Path.join([root, "blobs", sha <> ".json"])
    File.write!(path, bytes, [:exclusive, :sync])
    File.chmod!(path, 0o600)
    sha
  end

  defp file_sha(path), do: JSON.sha256(File.read!(path))
  defp read(path), do: path |> File.read!() |> Jason.decode!()

  defp save(root, name, value) do
    path = Path.join(root, name)
    File.write!(path, Jason.encode!(value) <> "\n", [:exclusive, :sync])
    File.chmod!(path, 0o600)
  end
end
