defmodule Ipse.KnowledgeCollectionJobProgressTest do
  use ExUnit.Case, async: true
  alias IpseKnowledge.Store.Collection.{Job, Paged}
  alias Ipse.Extension.ResultPublication
  alias IpseKnowledge.Evidence, as: E

  defp json(value), do: IO.iodata_to_binary(JSON.encode!(value))

  defp maximum_job do
    partition = "abcdefghijklmnop"
    maximum = E.safe_integer_max()

    catalog = %{
      "version" => 1,
      "kind" => "catalog",
      "partition" => partition,
      "generation" => maximum,
      "floor" => maximum,
      "sources" => 1000,
      "extracted_bytes" => 20 * 1024 * 1024,
      "chunks" => 10_000,
      "entities" => 5000,
      "assertions" => 20_000,
      "pages" =>
        for(
          n <- 0..62,
          do: %{"key" => "catalog.#{partition}.#{n}", "sha256" => E.sha256("catalog#{n}")}
        )
    }

    %{
      "version" => 1,
      "kind" => "shared_generation_job",
      "id" => String.duplicate("f", 32),
      "partition" => partition,
      "status" => "manifests",
      "catalog" => catalog,
      "catalog_sha256" => E.sha256(json(catalog)),
      "generation" => maximum,
      "root_revision" => maximum,
      "root_sha256" => E.sha256("root"),
      "vector_selection" => %{
        "selection_sha256" => E.sha256("selection"),
        "profile" => String.duplicate(<<0>>, 128),
        "model" => String.duplicate(<<0>>, 128),
        "dimensions" => 4096,
        "encoding" => "float32le"
      },
      "fact_selection" => %{
        "kind" => "model_complete",
        "profile" => String.duplicate(<<0>>, 128),
        "version" => 1
      },
      "cursor" => 1000,
      "facts" => 20_000,
      "summaries" => for(n <- 0..124, do: reference(partition, "gensum", n))
    }
  end

  defp reference(partition, kind, n),
    do: %{
      "key" => "#{kind}.#{partition}." <> E.sha256("#{kind}#{n}"),
      "sha256" => E.sha256("#{kind}#{n}"),
      "byte_count" => 49_152
    }

  test "compact representation preserves exact continuations and absent or paused job state" do
    token = %{
      "version" => 1,
      "unit" => 3,
      "stages" => [%{"slot" => 15, "epoch" => String.duplicate("f", 32)}]
    }

    for value <- [
          %{
            "job" => nil,
            "continuation" => nil,
            "stale" => false,
            "coverage" => %{"reads_used" => 3}
          },
          %{
            "status" => "staged_generation",
            "continuation" => token,
            "coverage" => %{"effects_used" => 16}
          }
        ] do
      compact = Job.compact_result(value)
      assert compact["representation"] == "compact_v1"
      assert compact["job_progress"] == nil
      assert Map.drop(compact, ~w(representation job_progress)) == Map.delete(value, "job")
    end
  end

  test "maximum catalog and summaries become inline progress while binding every omitted byte" do
    job = maximum_job()
    assert Job.valid?(job, %{"partition" => job["partition"]})

    token = %{
      "version" => 1,
      "id" => job["id"],
      "job_revision" => E.safe_integer_max(),
      "root_revision" => E.safe_integer_max(),
      "catalog_sha256" => job["catalog_sha256"],
      "plan_sha256" => E.sha256("plan"),
      "unit" => E.safe_integer_max(),
      "write" => nil,
      "stages" => for(n <- 0..2, do: %{"slot" => n, "epoch" => String.duplicate("f", 32)})
    }

    value = %{
      "status" => "manifests",
      "job" => job,
      "continuation" => token,
      "coverage" => %{"model_receipt_provenance" => false, "selected_changed" => false}
    }

    compact = Job.compact_result(value)
    progress = compact["job_progress"]
    assert progress["value_sha256"] == E.sha256(json(job))
    assert progress["value_bytes"] == byte_size(json(job))
    assert progress["summary_count"] == 125 and progress["source_count"] == 1000
    assert compact["continuation"] === token and compact["coverage"] === value["coverage"]

    changed =
      put_in(
        value,
        ["job", "summaries", Access.at(124), "sha256"],
        E.sha256("different last summary")
      )

    assert Job.compact_result(changed)["job_progress"]["value_sha256"] != progress["value_sha256"]
    assert {:ok, %ResultPublication.Output{}} = ResultPublication.prepare(public(value, job))
    assert {:ok, %{"kind" => "result"}} = ResultPublication.prepare(public(compact, job))

    IO.puts(
      "GENERATION_PROGRESS_MAX " <>
        json(%{
          "full_bytes" => byte_size(json(public(value, job))),
          "compact_bytes" => byte_size(json(public(compact, job))),
          "model_calls" => 0
        })
    )
  end

  test "paged reduction reports exact scalar progress and counts instead of page arrays" do
    job = maximum_job()
    p = job["partition"]

    reduction = %{
      "phase" => "entity_digest",
      "recipe" => "ipse.evidence.shared_directory.v2",
      "batch" => 8,
      "manifests" => for(n <- 0..7, do: reference(p, "genman", n)),
      "runs" => [],
      "positions" => [],
      "entity_pages" => for(n <- 0..156, do: reference(p, "genent", n)),
      "entities" => 5000,
      "text_bytes" => job["catalog"]["extracted_bytes"],
      "chunks" => 10_000,
      "facts" => 20_000,
      "heads_sha256" => E.sha256("heads"),
      "entity_pages_sha256" => nil,
      "digest_cursor" => 156,
      "verified_entities" => 4992,
      "last_entity_id" => E.sha256("last")
    }

    job =
      job
      |> Map.merge(%{
        "version" => 3,
        "status" => "reducing",
        "summaries" => [],
        "reduction" => reduction
      })

    assert Job.valid?(job, %{"partition" => p})
    compact = Job.compact_result(%{"job" => job})
    progress = compact["job_progress"]
    assert progress["job_schema_version"] == 3
    assert progress["reduction"]["entity_pages_count"] == 157
    assert progress["reduction"]["digest_cursor"] == 156
    assert progress["reduction"]["verified_entities"] == 4992
    refute Map.has_key?(progress["reduction"], "entity_pages")
    refute Job.valid?(progress, %{"partition" => p})
    assert byte_size(json(compact)) < 4096

    assert_raise MatchError, fn ->
      Job.compact_result(%{"job" => Map.put(job, "version", 3.0)})
    end

    assert Paged.native_value?(job)
  end

  defp public(coverage, job),
    do: %{
      "version" => 1,
      "status" => "draft",
      "evidence" => [],
      "claims" => [],
      "gaps" => [],
      "coverage" => Map.delete(coverage, "continuation"),
      "continuation" => %{
        "id" => "generation_job",
        "arguments" => %{
          "store" => String.duplicate("s", 64),
          "action" => "finalize_paged",
          "response" => "compact_v1",
          "continuation" => coverage["continuation"],
          "vector_selection" => job["vector_selection"],
          "fact_selection" => job["fact_selection"]
        }
      }
    }
end
