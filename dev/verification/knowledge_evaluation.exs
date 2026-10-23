Code.require_file("../evaluation/session.exs", __DIR__)

defmodule IpseKnowledgeExample.EvaluationProof do
  alias Ipse.Development.Evaluation.Session, as: Evaluation

  @options JSON.decode!(
             File.read!(
               Path.expand("../../extensions/knowledge/options/corpus-lexical.json", __DIR__)
             )
           )

  defmodule NoModel do
    def complete(_, _, _, _), do: raise("Evaluation driver proof called a model")
  end

  def run(artifact) do
    {:ok, _} = Application.ensure_all_started(:ipse)
    root = Path.join(System.tmp_dir!(), "ipse-evaluation-proof-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    manifest = JSON.decode!(File.read!(Path.join(artifact, "extension.json")))
    digest = Ipse.JSON.sha256(File.read!(Path.join(artifact, "extension.json")))

    options =
      @options
      |> Map.put("stores", %{"notes.v1" => @options["stores"]["notes"]})
      |> Map.put("retrieval", %{"words.v1" => @options["retrieval"]["words"]})

    validator = fn review ->
      true = review.verb == "ingest"
      true = review.name == "extension:state.put"
      true = review.proposed["request"]["scope"] == "project"
      true = review.arguments["store"] == "notes.v1"
      {:approve, %{name: review.name, proposed: review.proposed}}
    end

    spec = %{
      root: root,
      project: "synthetic",
      variant: "lexical",
      artifacts: [
        %{
          instance: "corpus",
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
                "instance" => "corpus",
                "id" => "evaluation-proof",
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
        budget: %{"version" => 1, "max_requests" => 1}
      },
      bindings:
        Map.new(~w(ingest inspect query), fn verb ->
          {verb,
           %{"instance" => "corpus", "id" => if(verb == "query", do: "query", else: "source")}}
        end),
      required_verbs: ~w(ingest inspect query),
      approval_validator: validator,
      timeout_ms: 60_000
    }

    try do
      {:error, :invalid_session_spec} =
        Evaluation.open(put_in(spec, [:runtime, :budget_root], %{}))

      {:ok, run} = Evaluation.open(spec)
      Process.put(:evaluation_proof_run, run)
      text = "Quiescence prevents release races. " <> String.duplicate("é", 4300)

      source = %{
        "source_id" => "proof:large",
        "generation" => 1,
        "title" => "Proof source",
        "text" => text,
        "uri" => "local:proof",
        "observed_at_ms" => 1,
        "event_at_ms" => nil,
        "expires_at_ms" => nil
      }

      {:ok, stored, run} =
        Evaluation.invoke(run, "ingest", %{
          "store" => "notes.v1",
          "source" => source,
          "expected_revision" => 0
        })

      Process.put(:evaluation_proof_run, run)
      true = length(stored["steps"]) >= 4
      "ok" = stored["status"]

      {:ok, inspected, run} =
        Evaluation.invoke(run, "inspect", %{
          "store" => "notes.v1",
          "source_id" => source["source_id"]
        })

      Process.put(:evaluation_proof_run, run)
      "ok" = inspected["status"]

      {:ok, found, run} =
        Evaluation.invoke(run, "query", %{
          "store" => "notes.v1",
          "retrieval" => "words.v1",
          "rerank" => nil,
          "query" => "quiescence",
          "top_k" => 10,
          "as_of_ms" => 10
        })

      Process.put(:evaluation_proof_run, run)
      "ok" = found["status"]
      [candidate] = found["value"]["evidence"]

      true =
        candidate["citation"]["content_sha256"] ==
          Ipse.JSON.sha256(text)

      {:ok, snapshot} = Evaluation.snapshot(run)
      true = length(snapshot["receipts"]) == length(stored["steps"]) + 2

      true =
        Enum.all?(
          snapshot["receipts"],
          &(is_binary(&1["invocation_id"]) and is_binary(&1["result_sha256"]))
        )

      true = Ipse.Session.info(run.pid).accounting["request_count"] == 0
      {:ok, %{"cleanup" => "confirmed"}} = Evaluation.close(run)
      Process.delete(:evaluation_proof_run)

      %{
        "checks" => 5,
        "model_requests" => 0,
        "paged_ingest" => true,
        "profile_names" => "dotted",
        "durable_receipts" => length(snapshot["receipts"])
      }
    after
      if run = Process.get(:evaluation_proof_run) do
        if Process.alive?(run.pid), do: {:ok, _} = Evaluation.close(run)
      end

      File.rm_rf!(root)
    end
  end
end
