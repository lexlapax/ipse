defmodule Ipse.Extensions.ConfigTest do
  use ExUnit.Case, async: true
  alias Ipse.Extensions.Config
  @artifact String.duplicate("a", 64)

  defp instance(changes \\ %{}) do
    Map.merge(
      %{
        "instance" => "annotator",
        "artifact" => @artifact,
        "enabled" => false,
        "options" => %{"text" => "private-synthetic-option"},
        "order" => 10,
        "lifetime" => "persistent"
      },
      changes
    )
  end

  defp trust(changes \\ %{}) do
    Map.merge(
      %{
        "artifact" => @artifact,
        "capabilities" => ["transform.prompt"],
        "allow_project" => false,
        "allow_children" => false
      },
      changes
    )
  end

  defp source(scope, data), do: %{scope: scope, path: "/fixture/#{scope}.json", data: data}

  test "empty and disabled selection never grant execution or require installed code" do
    assert {:ok, %{"instances" => [], "trust" => []}} = Config.resolve([], [])

    assert {:ok, config} =
             Config.resolve([source("operator", %{"extensions" => [instance()]})], [])

    assert [%{"enabled" => false}] = config["instances"]

    assert {:error, _} =
             Config.resolve(
               [source("operator", %{"extensions" => [instance(%{"enabled" => true})]})],
               []
             )
  end

  test "operator-only trust is a ceiling even after project settings are authorized" do
    operator = source("operator", %{"extension_trust" => [trust()]})
    project = source("project", %{"extensions" => [instance(%{"enabled" => true})]})
    assert {:error, _} = Config.resolve([operator, project], [])
    operator = source("operator", %{"extension_trust" => [trust(%{"allow_project" => true})]})
    assert {:ok, config} = Config.resolve([operator, project], [])
    assert [%{"scope" => "project", "source" => "/fixture/project.json"}] = config["instances"]

    for declaration <- [[], [trust(%{"allow_project" => true})]] do
      assert {:error, _} =
               Config.resolve(
                 [operator, source("project", %{"extension_trust" => declaration})],
                 []
               )
    end
  end

  test "CLI selection is a temporary lease and no-extensions is an explicit kill switch" do
    operator = source("operator", %{"extensions" => [instance()], "extension_trust" => [trust()]})
    assert {:ok, config} = Config.resolve([operator], extension: "annotator")
    assert [%{"enabled" => true, "lifetime" => "session"}] = config["instances"]
    assert {:ok, config} = Config.resolve([operator], extensions: false)
    assert [%{"enabled" => false}] = config["instances"]

    for opts <- [
          [extension: "unknown"],
          [extension: "annotator", extension: "annotator"],
          [extension: "annotator", extensions: false]
        ] do
      assert {:error, _} = Config.resolve([operator], opts)
    end
  end

  test "nearer scopes replace exact instances and tie ordering uses instance identity" do
    operator =
      source("operator", %{
        "extensions" => [instance(), instance(%{"instance" => "before", "order" => 1})]
      })

    project =
      source("project", %{"extensions" => [instance(%{"options" => %{"label" => "project"}})]})

    assert {:ok, config} = Config.resolve([operator, project], [])
    assert [first, second] = config["instances"]
    assert first["instance"] == "before"
    assert second["scope"] == "project"
    assert second["options"] == %{"label" => "project"}

    assert {:ok, config} =
             Config.resolve(
               [
                 source("operator", %{
                   "extensions" => [instance(), instance(%{"instance" => "aaa"})]
                 })
               ],
               []
             )

    assert Enum.map(config["instances"], & &1["instance"]) == ["aaa", "annotator"]
  end

  test "inspection omits option contents, preserves their identity and changes on drift" do
    operator = source("operator", %{"extensions" => [instance()]})
    assert {:ok, config} = Config.resolve([operator], [])
    inspected = Config.inspect_config(config)
    refute Jason.encode!(inspected) =~ "private-synthetic-option"
    assert [%{"options_sha256" => digest}] = inspected["instances"]
    assert digest == Ipse.Compaction.digest([instance()["options"]])

    changed =
      update_in(config, ["instances", Access.at(0), "options"], &Map.put(&1, "text", "changed"))

    refute Config.inspect_config(changed) == inspected
  end

  test "closed typed descriptors and bounded identifiers reject malformed configuration" do
    for change <- [
          %{"instance" => "../escape"},
          %{"order" => 1.0},
          %{"expires_at" => 1.0},
          %{"lifetime" => "forever"},
          %{"artifact" => "latest"},
          %{"extra" => true},
          %{"options" => %{"pid" => self()}}
        ] do
      assert {:error, _} = Config.validate(%{"extensions" => [instance(change)]})
    end

    assert {:error, _} = Config.validate(%{"extensions" => [instance(), instance()]})
    assert {:error, _} = Config.validate(%{"extension_trust" => [trust(), trust()]})

    assert {:error, _} =
             Config.validate(%{
               "extension_trust" => [
                 trust(%{"capabilities" => ["transform.prompt", "transform.prompt"]})
               ]
             })

    assert {:error, _} =
             Config.validate(%{
               "extensions" => Enum.map(1..9, &instance(%{"instance" => "instance#{&1}"}))
             })
  end
end
