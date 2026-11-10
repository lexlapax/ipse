defmodule Ipse.Session.RecallDependencyBudgetTest do
  use ExUnit.Case, async: true

  alias Ipse.JSON
  alias Ipse.Session.ManagedReference

  # The Notes worker cannot ask the host for its occurrence bounds, so it
  # carries its own copy of them and of the largest dependency encodings. This
  # test reads those constants from the package source, without loading the
  # package into the host VM, and holds them against the host's real validator
  # and encoder.
  @source Path.expand("../../../extensions/knowledge/src/knowledge.ex", __DIR__)
  @external_resource @source
  @max 9_007_199_254_740_991
  @page 32

  defp constant(name) do
    [_, digits] = Regex.run(~r/^  @#{name} ([0-9_]+)$/m, File.read!(@source))
    digits |> String.replace("_", "") |> String.to_integer()
  end

  defp constants do
    Map.new(
      ~w(recall_projection_limit recall_host_dependency_limit recall_host_dependency_bytes
         recall_root_dependency_bytes recall_literal_dependency_bytes
         recall_accepted_dependency_bytes recall_reserved_roots recall_candidates),
      &{&1, constant(&1)}
    )
  end

  defp sha(term), do: JSON.sha256(term)

  defp base do
    %{
      "project_id" => sha("project"),
      "namespace" => sha("namespace"),
      "pin_sha256" => sha("pin"),
      "policy_generation" => @max,
      "collection" => %{
        "project" => sha("namespace"),
        "generation" => @max,
        "floor" => @max,
        "floor_anchor" => String.duplicate("a", 32),
        "root_state" => "present",
        "root_sha256" => sha("root"),
        "manifest_sha256" => sha("manifest")
      }
    }
  end

  # A Notes record key is always "note." and a 64-character lineage, so the key
  # has one length. Every integer is the largest the host admits.
  defp literal(n) do
    key = "note." <> sha("note #{n}")

    Map.merge(base(), %{
      "version" => 4,
      "subject" => %{
        "kind" => "record_observation",
        "key" => key,
        "request_sha256" => JSON.digest([%{"op" => "get_record", "key" => key}]),
        "result_sha256" => sha("result #{n}"),
        "publication_policy_sha256" => sha("policy"),
        "record" => %{"key" => key, "revision" => @max, "value_sha256" => sha(key)},
        "validity" => %{
          "recipe_sha256" => sha("recipe"),
          "lineage" => sha("note #{n}"),
          "source_versions" => [
            %{"id" => sha("occurrence #{n}"), "version" => sha("version #{n}")}
          ],
          "valid_until_ms" => @max,
          "status" => "eligible",
          "dependencies" => []
        }
      }
    })
  end

  defp accepted(n) do
    lineage = sha("note #{n}")
    key = "note." <> lineage
    duration = 86_400_000

    link = %{
      "key" => "accept." <> sha("link #{n}"),
      "revision" => @max,
      "value_sha256" => sha("link value #{n}")
    }

    Map.merge(base(), %{
      "version" => 6,
      "subject" => %{
        "kind" => "accepted_decision_observation",
        "key" => key,
        "request_sha256" => JSON.digest([%{"op" => "get_record", "key" => key}]),
        "result_sha256" => sha("result #{n}"),
        "publication_policy_sha256" => sha("policy"),
        "record" => %{"key" => key, "revision" => @max, "value_sha256" => sha(key)},
        "validity" => %{
          "recipe_sha256" => sha("recipe"),
          "lineage" => lineage,
          "source_versions" => [
            %{"id" => sha("occurrence #{n}"), "version" => sha("version #{n}")}
          ],
          "valid_until_ms" => @max,
          "status" => "eligible",
          "dependencies" => [link]
        },
        "acceptance" => %{
          "journal_id" => String.duplicate("b", 32),
          "journal_kind" => "knowledge_management",
          "event_sha256" => sha("event #{n}"),
          "link" => link,
          "retention" => %{
            "version" => 1,
            "kind" => "native_retention_choice",
            "choice_sha256" => sha("choice #{n}"),
            "policy" => %{"kind" => "duration", "duration_ms" => duration},
            "observed_at_ms" => @max - duration
          }
        }
      }
    })
  end

  defp root(n) do
    Map.merge(base(), %{
      "version" => 3,
      "subject" => %{
        "kind" => "root_observation",
        "request_sha256" => sha("request #{n}"),
        "result_sha256" => sha("result #{n}")
      }
    })
  end

  # The worker's rule before a value read: the accounted bytes of what it has
  # read, one root per index page plus the reserve, and one more record of
  # unknown kind must fit. Records arrive in pages, as the worker reads them.
  defp admitted(c, record_bytes, available) do
    Enum.reduce_while(1..available, {0, 0}, fn n, {read, pages} ->
      pages = if rem(n - 1, @page) == 0, do: pages + 1, else: pages

      room? =
        read < c["recall_projection_limit"] and
          read + pages + 2 <= c["recall_host_dependency_limit"] and
          read * record_bytes +
            (pages + c["recall_reserved_roots"]) * c["recall_root_dependency_bytes"] +
            c["recall_accepted_dependency_bytes"] <= c["recall_host_dependency_bytes"]

      if room?, do: {:cont, {read + 1, pages}}, else: {:halt, {read, pages}}
    end)
  end

  defp fits?(dependencies) do
    limits = ManagedReference.limits()

    length(dependencies) <= limits["occurrence_dependencies"] and
      byte_size(Jason.encode!(dependencies)) <= limits["occurrence_dependency_bytes"]
  end

  test "the worker's copies of the occurrence bounds are the host's" do
    c = constants()
    limits = ManagedReference.limits()

    assert c["recall_host_dependency_bytes"] == limits["occurrence_dependency_bytes"]
    assert c["recall_host_dependency_limit"] == limits["occurrence_dependencies"]
    assert c["recall_candidates"] == @page
  end

  test "each accounted size covers the largest valid dependency of its kind and its separator" do
    c = constants()

    for {name, dependency} <- [
          {"recall_root_dependency_bytes", root(1)},
          {"recall_literal_dependency_bytes", literal(1)},
          {"recall_accepted_dependency_bytes", accepted(1)}
        ] do
      assert ManagedReference.dependency?(dependency)
      assert c[name] >= byte_size(Jason.encode!(dependency)) + 1, name
    end

    assert c["recall_accepted_dependency_bytes"] >= c["recall_literal_dependency_bytes"]
  end

  test "the most records one pass can read fit one reference occurrence" do
    c = constants()

    for {builder, bytes} <- [
          {&literal/1, c["recall_literal_dependency_bytes"]},
          {&accepted/1, c["recall_accepted_dependency_bytes"]}
        ] do
      {read, pages} = admitted(c, bytes, 128)
      assert read in 1..c["recall_projection_limit"]

      dependencies =
        Enum.map(1..read, builder) ++
          Enum.map(1..(pages + c["recall_reserved_roots"]), &root/1)

      assert Enum.all?(dependencies, &ManagedReference.dependency?/1)
      assert fits?(dependencies)

      # The rule is not slack by more than the reservation it documents: two
      # further records of this kind no longer fit.
      refute fits?(dependencies ++ Enum.map((read + 1)..(read + 2), builder))
    end

    assert {74, 3} == admitted(c, c["recall_literal_dependency_bytes"], 128)
    assert {50, 2} == admitted(c, c["recall_accepted_dependency_bytes"], 128)
  end

  test "the projection limit alone would not fit the largest dependencies" do
    c = constants()
    limit = c["recall_projection_limit"]
    pages = div(limit + @page - 1, @page)

    refute fits?(Enum.map(1..limit, &literal/1) ++ Enum.map(1..(pages + 1), &root/1))
  end
end
