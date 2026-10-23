Code.require_file("../evaluation/session.exs", __DIR__)

defmodule IpseKnowledgeExample.RecoveryProof do
  @moduledoc false
  alias Ipse.Development.Evaluation.Session, as: Evaluation
  @source_id "proof:graph-recovery"
  @text "Release requires quiescence."

  defmodule NoModel do
    def complete(_, _, _, _), do: raise("Graph recovery proof called a model")
  end

  def run(artifact) do
    root = Path.join(System.tmp_dir!(), "ipse-graph-recovery-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    origin = "http://127.0.0.1:#{port}"
    bytes = File.read!(Path.join(artifact, "extension.json"))
    manifest = JSON.decode!(bytes)
    digest = sha(bytes)

    options = %{
      "version" => 1,
      "stores" => %{
        "notes" => %{"kind" => "state", "scope" => "project", "partition" => "recovery"}
      },
      "search" => %{},
      "fetch" => %{},
      "retrieval" => %{},
      "embedding" => %{},
      "rerank" => %{},
      "extraction" => %{
        "assisted" => %{"kind" => "model_complete", "profile" => "p27_extract", "version" => 1}
      }
    }

    spec = %{
      root: root,
      project: "synthetic",
      variant: "graph",
      artifacts: [
        %{
          instance: "graph",
          path: artifact,
          digest: digest,
          options: options,
          order: 0,
          trust: %{
            "artifact" => digest,
            "capabilities" => manifest["capabilities"],
            "allow_project" => false,
            "allow_children" => false,
            "state_bindings" => [
              %{
                "version" => 1,
                "instance" => "graph",
                "id" => "recovery-proof",
                "scopes" => ["project"]
              }
            ]
          }
        }
      ],
      runtime: %{
        provider: :demo,
        model: "unused",
        provider_module: NoModel,
        compact: false,
        profiles: %{
          "p27_extract" => %{
            "provider" => "ollama",
            "model" => "unused-fixture",
            "base_url" => origin,
            "credential" => "none",
            "max_output_tokens" => 32
          }
        },
        budget: %{"version" => 1, "max_requests" => 1}
      },
      bindings:
        Map.new(~w(ingest inspect extract abort), fn verb ->
          {verb,
           %{"instance" => "graph", "id" => if(verb == "extract", do: "extract", else: "source")}}
        end),
      required_verbs: ~w(ingest inspect extract abort),
      approval_validator: &approve(&1, digest, origin),
      timeout_ms: 15_000
    }

    Process.put(:graph_recovery_run, nil)

    try do
      {:ok, run} = Evaluation.open(spec)
      keep(run)
      true = Enum.all?(run.catalog["entries"], &(&1["instance"] == "graph"))

      source = %{
        "source_id" => @source_id,
        "generation" => 1,
        "title" => "Release policy",
        "text" => @text,
        "uri" => "local:recovery-proof",
        "observed_at_ms" => 1,
        "event_at_ms" => nil,
        "expires_at_ms" => nil
      }

      {:ok, _, run} =
        Evaluation.invoke(run, "ingest", %{
          "source" => source,
          "store" => "notes",
          "expected_revision" => 0
        })

      keep(run)
      {:ok, inspected, run} = inspect_source(run)
      keep(run)
      coverage = inspected["value"]["coverage"]
      [chunk] = coverage["chunks"]
      Process.put(:graph_recovery_revision, coverage["revision"])

      extraction = %{
        "store" => "notes",
        "extraction" => "assisted",
        "source_id" => @source_id,
        "generation" => 1,
        "max_edges" => 1,
        "chunks" => [chunk["chunk_id"]],
        "facts" => []
      }

      {:error, {:command_failed, "refused"}, run} = Evaluation.invoke(run, "extract", extraction)
      keep(run)
      denied = List.last(run.receipts)

      true =
        Enum.any?(
          denied["approvals"],
          &(&1["name"] == "extension:model.complete" and &1["decision"] == "denied")
        )

      {:ok, inspected, run} = inspect_source(run)
      keep(run)
      current = inspected["value"]["coverage"]
      "facts" = current["draft"]["kind"]
      first_id = current["draft"]["id"]

      abort = %{
        "store" => "notes",
        "source_id" => @source_id,
        "draft_id" => first_id,
        "expected_revision" => current["revision"]
      }

      Process.put(:graph_recovery_revision, current["revision"])
      before = state_writes(run)

      {:error, {:command_failed, "refused"}, run} =
        Evaluation.invoke(run, "abort", Map.put(abort, "draft_id", String.duplicate("0", 32)))

      keep(run)
      true = state_writes(run) == before
      {:ok, _, run} = Evaluation.invoke(run, "abort", abort)
      keep(run)
      true = state_writes(run) == before + 1
      {:ok, inspected, run} = inspect_source(run)
      keep(run)
      cleared = inspected["value"]["coverage"]
      nil = cleared["draft"]
      "active" = cleared["state"]
      1 = cleared["generation"]
      before = state_writes(run)
      {:error, {:command_failed, "refused"}, run} = Evaluation.invoke(run, "abort", abort)
      keep(run)
      true = state_writes(run) == before
      Process.put(:graph_recovery_revision, cleared["revision"])
      {:error, {:command_failed, "refused"}, run} = Evaluation.invoke(run, "extract", extraction)
      keep(run)
      {:ok, inspected, run} = inspect_source(run)
      keep(run)
      next = inspected["value"]["coverage"]
      true = next["draft"]["id"] != first_id
      Process.put(:graph_recovery_revision, next["revision"])

      {:ok, _, run} =
        Evaluation.invoke(run, "abort", %{
          abort
          | "draft_id" => next["draft"]["id"],
            "expected_revision" => next["revision"]
        })

      keep(run)
      {:ok, snapshot} = Evaluation.snapshot(run)
      0 = snapshot["accounting"]["request_count"]
      {:error, :timeout} = :gen_tcp.accept(listener, 0)

      for module <- [IpseKnowledge.Graph, IpseKnowledge.Store, IpseKnowledge.Adapters],
          do: false = :code.is_loaded(module)

      {:ok, %{"cleanup" => "confirmed"}} = Evaluation.close(run)
      Process.delete(:graph_recovery_run)

      %{
        "checks" => 8,
        "graph_only" => true,
        "exact_abort" => true,
        "stale_abort_zero_writes" => true,
        "explicit_new_draft" => true,
        "denied_model_dispatches" => 0,
        "model_requests" => 0,
        "host_loaded_domain_modules" => false,
        "cleanup" => "confirmed"
      }
    after
      if run = Process.get(:graph_recovery_run), do: {:ok, _} = Evaluation.close(run)
      Process.delete(:graph_recovery_run)
      Process.delete(:graph_recovery_revision)
      :gen_tcp.close(listener)
      File.rm_rf!(root)
    end
  end

  defp inspect_source(run),
    do: Evaluation.invoke(run, "inspect", %{"store" => "notes", "source_id" => @source_id})

  defp keep(run), do: Process.put(:graph_recovery_run, run)
  defp sha(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp state_writes(run) do
    {:ok, events} = Ipse.Journal.load(run.state_dir, run.session_id)

    Enum.count(
      events,
      &(&1["type"] == "extension_action_intent" and get_in(&1, ["request", "op"]) == "state.put")
    )
  end

  defp approve(review, digest, origin) do
    proposed = review.proposed
    request = proposed["request"]
    true = proposed["extension"] == "graph" and proposed["artifact_sha256"] == digest

    case review.name do
      "extension:model.complete" ->
        "extract" = review.verb
        "p27_extract" = request["profile"]

        true =
          proposed["destination"] == %{
            "origin" => origin,
            "target_sha256" => sha(origin <> "/api/chat")
          }

        %{"max_facts" => 1, "chunks" => [%{"text" => @text}]} = JSON.decode!(request["input"])
        {:deny, :synthetic_egress_control}

      "extension:state.put" ->
        true = review.verb in ~w(ingest extract abort)
        "project" = request["scope"]
        "notes" = review.arguments["store"]
        value = request["value"]
        "recovery" = value["partition"]
        true = value["source_key"] == sha(@source_id)

        if review.verb in ~w(extract abort) do
          true = request["expected_revision"] == Process.get(:graph_recovery_revision)

          true =
            request["key"] ==
              sha(JSON.encode!(["ipse-knowledge", 1, "root", ["recovery", sha(@source_id)]]))

          true = value["content_sha256"] == sha(@text)

          if review.verb == "abort",
            do: nil = value["draft"],
            else: "facts" = value["draft"]["kind"]
        end

        {:approve, %{name: review.name, proposed: proposed}}

      _ ->
        {:deny, :unselected_action}
    end
  end
end
