defmodule Ipse.Extension.ExpectedManagementRecordTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Collection.{Migration, ObservedRead}
  alias Ipse.JSON

  test "the expected record fence refuses substitutions and malformed identities" do
    namespace = JSON.sha256("namespace")
    value = %{"text" => "fictional note"}

    record = %{
      "key" => "note." <> JSON.sha256("lineage"),
      "revision" => 7,
      "sha256" => JSON.sha256(Migration.encode(value)),
      "operation_id" => String.duplicate("a", 32),
      "value" => value
    }

    root = JSON.sha256("root")

    managed = %{
      "observation" => %{
        "value" => %{"record" => record},
        "witness" => %{"root" => %{"project" => namespace}, "root_sha256" => root}
      }
    }

    expected = %{
      "version" => 1,
      "project_id" => JSON.sha256("project"),
      "namespace" => namespace,
      "root_sha256" => root,
      "control_sha256" => JSON.sha256("control"),
      "key" => record["key"],
      "revision" => record["revision"],
      "value_sha256" => record["sha256"],
      "operation_id" => record["operation_id"]
    }

    assert ObservedRead.expected_management_record?(expected, namespace, managed)

    for {key, changed} <- [
          {"version", 2},
          {"project_id", "bad"},
          {"namespace", JSON.sha256("other")},
          {"root_sha256", JSON.sha256("other")},
          {"control_sha256", "bad"},
          {"key", "note." <> JSON.sha256("other")},
          {"revision", 8},
          {"value_sha256", JSON.sha256("other")},
          {"operation_id", String.duplicate("b", 32)}
        ] do
      refute ObservedRead.expected_management_record?(
               Map.put(expected, key, changed),
               namespace,
               managed
             )
    end

    refute ObservedRead.expected_management_record?(
             Map.put(expected, "extra", true),
             namespace,
             managed
           )

    refute ObservedRead.expected_management_record?(
             expected,
             namespace,
             put_in(managed, ["observation", "value", "record", "value"], %{"text" => "changed"})
           )

    refute ObservedRead.expected_management_record?(
             expected,
             namespace,
             put_in(managed, ["observation", "value", "record"], nil)
           )
  end
end
