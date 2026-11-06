defmodule Ipse.Extension.CollectionJobInputGuardTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.CollectionStore
  alias Ipse.JSON

  defp legacy_job do
    catalog = %{
      "version" => 1,
      "kind" => "catalog",
      "partition" => "notes",
      "generation" => 1,
      "floor" => 0,
      "sources" => 1,
      "extracted_bytes" => 4,
      "chunks" => 1,
      "entities" => 0,
      "assertions" => 0,
      "pages" => [%{"key" => "catalog.notes.0", "sha256" => JSON.sha256("catalog page")}]
    }

    %{
      "version" => 1,
      "kind" => "shared_generation_job",
      "id" => String.duplicate("a", 32),
      "partition" => "notes",
      "status" => "groups",
      "catalog" => catalog,
      "catalog_sha256" => JSON.sha256(Jason.encode!(catalog)),
      "generation" => 1,
      "root_revision" => 0,
      "root_sha256" => nil,
      "vector_selection" => %{
        "profile" => "encoder",
        "model" => "fixture",
        "dimensions" => 1024,
        "encoding" => "float32le",
        "selection_sha256" => JSON.sha256("selection")
      },
      "fact_selection" => %{"version" => 1, "kind" => "explicit", "profile" => nil},
      "cursor" => 0,
      "summaries" => [],
      "facts" => 0
    }
  end

  defp job(7), do: legacy_job() |> Map.merge(%{"version" => 7, "input_binding" => nil})

  defp job(8),
    do: job(7) |> Map.merge(%{"version" => 8, "maintenance_epoch" => 2})

  defp input_binding do
    %{
      "version" => 1,
      "ref_sha256" => JSON.sha256("operator-selected reference"),
      "raw_sha256" => JSON.sha256("original selected bytes"),
      "source_set_sha256" => JSON.sha256("current source set"),
      "cursor" => 0,
      "vector_job_revision" => 12,
      "owner" => %{
        "project_id" => JSON.sha256("synthetic project"),
        "session_id" => String.duplicate("b", 32),
        "identity_sha256" => JSON.sha256("synthetic artifact")
      }
    }
  end

  defp allowed?(old, proposed, epoch) do
    # Actual DocumentStage.read_value decodes this physical native envelope;
    # the test substitutes only the retained read closure, with no filesystem IO.
    read = fn "genjob.notes" ->
      send(self(), :job_guard_read)

      if is_nil(old) do
        {:ok, nil}
      else
        bytes = Jason.encode!(old)

        {:ok,
         %{
           "revision" => 12,
           "operation_id" => String.duplicate("c", 32),
           "value" => %{
             "version" => 1,
             "kind" => "document_value",
             "sha256" => JSON.sha256(bytes),
             "byte_count" => byte_size(bytes),
             "parts" => [bytes]
           }
         }}
      end
    end

    result =
      CollectionStore.unguarded_group_job?(
        read,
        %{"key" => "genjob.notes", "value" => proposed},
        epoch
      )

    assert_receive :job_guard_read
    refute_receive :job_guard_read, 0
    result
  end

  test "ordinary initialization permits only unbound closed jobs at their actual epoch" do
    assert allowed?(nil, legacy_job(), 0)

    for {version, epoch} <- [{7, 0}, {8, 2}] do
      fresh = job(version)
      assert allowed?(nil, fresh, epoch)
      assert allowed?(Map.put(legacy_job(), "status", "aborted"), fresh, epoch)
      refute allowed?(nil, Map.put(fresh, "input_binding", input_binding()), epoch)
      refute allowed?(nil, Map.put(fresh, "extra", true), epoch)
      refute allowed?(nil, Map.put(fresh, "cursor", 8), epoch)
      refute allowed?(nil, fresh, epoch + 1)
    end

    refute allowed?(nil, put_in(job(8), ["maintenance_epoch"], 2.0), 2)
    refute allowed?(nil, Map.delete(job(8), "input_binding"), 2)
  end

  test "an unguarded request cannot bind or replace an existing live job" do
    for {version, epoch} <- [{7, 0}, {8, 2}] do
      old = job(version)
      refute allowed?(old, Map.put(old, "input_binding", input_binding()), epoch)
      refute allowed?(old, job(version), epoch)
      refute allowed?(legacy_job(), Map.put(old, "input_binding", input_binding()), epoch)
    end
  end

  test "a bound job cannot use ordinary abort even with an unchanged or foreign binding" do
    for {version, epoch} <- [{7, 0}, {8, 2}] do
      old = Map.put(job(version), "input_binding", input_binding())
      retained = Map.put(old, "status", "aborted")

      downgraded =
        old
        |> Map.delete("input_binding")
        |> Map.put("version", if(version === 7, do: 1, else: 4))
        |> Map.put("status", "aborted")

      refute allowed?(old, retained, epoch)
      refute allowed?(old, downgraded, epoch)

      refute allowed?(
               old,
               put_in(
                 retained,
                 ["input_binding", "owner", "session_id"],
                 String.duplicate("d", 32)
               ),
               epoch
             )

      refute allowed?(old, Map.put(job(version), "status", "aborted"), epoch)
    end
  end

  test "exact unbound abort downgrades once and cannot edit progress or move backwards in epoch" do
    for {version, opening} <- [{7, 0}, {8, 2}] do
      old = job(version)

      aborted =
        old
        |> Map.delete("input_binding")
        |> Map.put("version", if(version === 7, do: 1, else: 4))
        |> Map.put("status", "aborted")

      assert allowed?(old, aborted, opening)
      assert allowed?(old, aborted, opening + 1)
      refute allowed?(old, Map.put(aborted, "facts", 1), opening)
      refute allowed?(old, Map.put(aborted, "extra", true), opening)
      refute allowed?(old, Map.put(old, "status", "aborted"), opening)
    end

    aborted =
      job(8) |> Map.delete("input_binding") |> Map.merge(%{"version" => 4, "status" => "aborted"})

    refute allowed?(job(8), aborted, 1)
    refute allowed?(job(8), aborted, 2.0)
  end
end
