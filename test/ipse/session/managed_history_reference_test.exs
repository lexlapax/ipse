defmodule Ipse.Session.ManagedHistoryReferenceTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Session.ManagedReference}

  test "historical dependencies remain distinct, bind the successor edge, and cannot renew their deadline" do
    sha = &JSON.sha256/1
    key = "note." <> sha.("old")

    dependency = %{
      "version" => 5,
      "project_id" => sha.("project"),
      "namespace" => sha.("namespace"),
      "pin_sha256" => sha.("pin"),
      "policy_generation" => 1,
      "collection" => %{
        "project" => sha.("namespace"),
        "generation" => 3,
        "floor" => 0,
        "floor_anchor" => nil,
        "root_state" => "present",
        "root_sha256" => sha.("root"),
        "manifest_sha256" => sha.("manifest")
      },
      "subject" => %{
        "kind" => "historical_record_observation",
        "key" => key,
        "request_sha256" => JSON.digest([%{"op" => "get_record", "key" => key}]),
        "result_sha256" => sha.("result"),
        "publication_policy_sha256" => sha.("policy"),
        "record" => %{"key" => key, "revision" => 1, "value_sha256" => sha.("value")},
        "validity" => %{
          "recipe_sha256" => sha.("recipe"),
          "lineage" => sha.("old"),
          "source_versions" => [%{"id" => sha.("occurrence"), "version" => sha.("version")}],
          "valid_until_ms" => 2000,
          "status" => "eligible",
          "dependencies" => []
        },
        "successor" => %{"key" => "note." <> sha.("new"), "sha256" => sha.("new value")},
        "superseded_at_ms" => 1000
      }
    }

    assert ManagedReference.dependency?(dependency)
    assert ManagedReference.current?(dependency, dependency, 1999)
    refute ManagedReference.current?(dependency, dependency, 2000)
    changed_edge = put_in(dependency, ["subject", "successor", "sha256"], sha.("other"))
    refute ManagedReference.current?(dependency, changed_edge, 1500)

    refute ManagedReference.dependency?(
             put_in(dependency, ["subject", "successor", "key"], "note.invalid")
           )

    refute ManagedReference.dependency?(
             put_in(dependency, ["subject", "validity", "lineage"], sha.("other lineage"))
           )

    extended = put_in(dependency, ["subject", "validity", "valid_until_ms"], 2001)
    refute ManagedReference.current?(dependency, extended, 1500)
    refute ManagedReference.dependency?(Map.put(dependency, "version", 4))

    newer =
      dependency
      |> put_in(["collection", "generation"], 4)
      |> put_in(["collection", "root_sha256"], sha.("new root"))

    assert ManagedReference.current?(dependency, newer, 1500)
  end
end
