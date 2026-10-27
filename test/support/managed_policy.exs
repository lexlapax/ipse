unless Code.ensure_loaded?(IpseKnowledge.Knowledge.Contracts) do
  Code.require_file(Path.expand("../../extensions/knowledge/src/knowledge/contracts.ex", __DIR__))
end

defmodule Ipse.Test.ManagedPolicy do
  @moduledoc false
  alias Ipse.JSON
  alias IpseKnowledge.Knowledge.Contracts

  def hash(value), do: JSON.digest([value])

  def recipe(kind, constraint) do
    proposal = kind == "proposal"

    rules =
      Enum.map(~w(current ordinary preference), fn category ->
        %{
          "category" => category,
          "max_age_ms" =>
            if(proposal, do: 604_800_000, else: if(category == "ordinary", do: 7_776_000_000)),
          "origins" => constraint["source_categories"]
        }
      end)

    %{
      "version" => 1,
      "kind" => kind,
      "key_prefix" => constraint["key_prefix"],
      "constraints_sha256" => hash(constraint),
      "evidence_path" => ["evidence", "sources"],
      "lineage_path" => ["lineage"],
      "text_path" => ["text"],
      "category_path" => [if(proposal, do: "assigned_category", else: "category")],
      "rules" => rules,
      "override_prefix" => "override."
    }
  end

  def activation do
    %{
      "version" => 1,
      "kind" => "reviewed.bundle",
      "artifact" => hash("artifact"),
      "artifact_sha256" => hash("artifact"),
      "sidecar_sha256" => hash("sidecar"),
      "instance" => "knowledge",
      "options" => %{"preset" => "native"},
      "capabilities" =>
        ~w(host.actions host.collection.read host.collection.write host.sources invoke.result.pages invoke.tool),
      "service_refs" => [%{"operation" => "main", "service_id" => "fixture", "profile" => nil}],
      "order" => 10,
      "lifetime" => "session",
      "allow_children" => false
    }
  end

  def identity do
    hashes =
      Map.new(
        ~w(options_sha256 exports_sha256 requires_sha256 subscriptions_sha256 source_sha256 host_sha256),
        &{&1, hash(&1)}
      )

    Map.merge(hashes, %{
      "instance" => "knowledge",
      "artifact" => hash("artifact"),
      "artifact_sha256" => hash("artifact"),
      "services" => [],
      "scope" => "operator",
      "sdk" => 2,
      "protocol" => 1,
      "capabilities" => activation()["capabilities"],
      "order" => 10,
      "lifetime" => "session",
      "expires_at" => nil,
      "runtime" => %{
        "architecture" => "fixture",
        "elixir" => "1.18.5",
        "erts" => "15",
        "otp" => "27"
      },
      "generation" => 1,
      "allow_children" => false
    })
  end

  def binding do
    %{
      "version" => 1,
      "project_id" => hash("project"),
      "worktree_id" => hash("tree"),
      "scope" => "folder",
      "root" => "/fixture/project",
      "primary_root" => "/fixture/project",
      "common_directory" => nil,
      "binding_sha256" => hash("binding")
    }
  end

  def policy do
    c = Contracts.operator()["publication"]
    note = c["note"]
    pending = c["pending"]
    nr = recipe("literal_source", note)
    pr = recipe("proposal", pending)

    mapping = fn operation, constraint, recipe ->
      %{
        "operation" => operation,
        "class" => "collection.publish",
        "outer_sha256" => hash("capture"),
        "inner_op" => "collection.managed",
        "constraints_sha256" => hash(constraint),
        "recipe_sha256" => hash(recipe)
      }
    end

    project = hash("project")
    namespace = elem(Ipse.Extension.SemanticConsent.namespace(project, "notes"), 1)

    effects =
      [
        mapping.("notes.save", note, nr),
        mapping.("notes.propose", pending, pr),
        %{
          "operation" => "notes.read",
          "class" => "collection.read",
          "outer_sha256" => hash("read"),
          "inner_op" => "collection.call",
          "managed_read" => Enum.sort([hash(nr), hash(pr)])
        }
      ]
      |> Enum.sort_by(&{&1["operation"], &1["class"], &1["outer_sha256"], &1["inner_op"]})

    settings = %{
      "version" => 2,
      "domain" => "knowledge",
      "instance" => "knowledge",
      "identity_sha256" => hash("identity"),
      "namespace" => namespace,
      "scope" => %{"kind" => "project", "worktree_id" => nil},
      "sources" => %{"categories" => pending["source_categories"], "exclusions" => []},
      "storage" => %{"kind" => "local_collection", "collection" => "notes"},
      "retention" => %{"ordinary" => 90},
      "routes" => [
        %{
          "operation" => "main",
          "provider" => "demo",
          "profile" => nil,
          "model" => "demo",
          "endpoint" => "demo://local",
          "service_id" => "fixture",
          "billing_mode" => "none",
          "processing_region" => nil,
          "storage_region" => nil,
          "cache_retention" => nil,
          "account_controls" => nil
        }
      ],
      "effects" => effects,
      "constraints" => %{hash(note) => note, hash(pending) => pending},
      "recipes" => %{hash(nr) => nr, hash(pr) => pr},
      "activation" => activation()
    }

    %{
      "version" => 1,
      "project" => project,
      "artifact_sha256" => hash("artifact"),
      "source_sha256" => hash(settings["sources"]),
      "operations" => ~w(notes.propose notes.read notes.save),
      "settings" => settings,
      "limits" => Map.new(Ipse.Extension.Consent.resources(), &{&1, 100_000}),
      "period_ms" => 86_400_000,
      "expires_at_ms" => 10_000_000,
      "headless" => true
    }
  end

  def proof(origin \\ "interactive_operator", text \\ "Exact café 雪") do
    kind =
      case origin do
        "native_operator_answer" -> "input.operator_answer"
        "assistant_proposal" -> "answer.original"
        "typed_host_outcome" -> "tool.outcome"
        _ -> "input.original"
      end

    %{
      "version" => 1,
      "session_id" => String.duplicate("a", 32),
      "occurrence_id" => String.duplicate("b", 32),
      "version_id" => String.duplicate("c", 32),
      "kind" => kind,
      "origin" => origin,
      "coverage" => "available",
      "path" => nil,
      "start_byte" => 0,
      "end_byte" => byte_size(text),
      "quote" => text,
      "quote_sha256" => JSON.sha256(text),
      "content_sha256" => JSON.sha256(text),
      "receipt_sha256" => hash("receipt")
    }
  end
end
