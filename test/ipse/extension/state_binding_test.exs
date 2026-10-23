defmodule Ipse.Extension.StateBindingTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.{Config, Registry, State}

  defp source(binding, path \\ "/fixture/operator.json") do
    %{
      scope: "operator",
      path: path,
      data: %{
        "extensions" => [
          %{
            "instance" => "notes",
            "artifact" => "builtin:prompt-annotation:1",
            "enabled" => true,
            "options" => %{"text" => "fixture"},
            "order" => 1,
            "lifetime" => "persistent"
          }
        ],
        "extension_trust" => [
          %{
            "artifact" => "builtin:prompt-annotation:1",
            "capabilities" => ["transform.prompt"],
            "allow_project" => true,
            "allow_children" => false,
            "state_bindings" => [binding]
          }
        ]
      }
    }
  end

  defp policy_binding,
    do: %{
      "version" => 1,
      "instance" => "notes",
      "id" => "reviewed-project-notes",
      "scopes" => ["project"]
    }

  defp identity(binding \\ policy_binding(), path \\ "/fixture/operator.json") do
    assert {:ok, catalog} = Config.resolve([source(binding, path)], [])
    assert {:ok, [entry]} = Registry.prepare(catalog, "/fixture/home")
    entry.identity
  end

  test "explicit operator binding preserves CAS and suppression across code, instance and configuration versions" do
    first = identity()
    assert Registry.valid_identity?(first)
    assert first["state_binding"] == Map.delete(policy_binding(), "instance")

    changed =
      identity(policy_binding(), "/fixture/moved-config.json")
      |> Map.put("artifact_sha256", String.duplicate("b", 64))
      |> Map.put("instance", "reviewed-upgrade")

    session = String.duplicate("1", 32)
    assert {:ok, namespace} = State.namespace(first, "project", "/fixture/project", session)
    assert {:ok, ^namespace} = State.namespace(changed, "project", "/fixture/project", session)
    root = Path.join(System.tmp_dir!(), "ipse-bound-state-" <> Ipse.Usage.id())
    on_exit(fn -> File.rm_rf!(root) end)

    put = %{
      "op" => "state.put",
      "scope" => "project",
      "key" => "source",
      "expected_revision" => 0,
      "value" => %{"suppressed" => true}
    }

    assert {:ok, _} = State.execute(root, namespace, put, Ipse.Usage.id())

    assert {:ok, %{"record" => %{"revision" => 1, "value" => %{"suppressed" => true}}}} =
             State.execute(
               root,
               namespace,
               %{"op" => "state.get", "scope" => "project", "key" => "source"},
               Ipse.Usage.id()
             )

    assert {:conflict, _} = State.execute(root, namespace, put, Ipse.Usage.id())
  end

  test "scope ceilings and project/session isolation survive logical identity sharing" do
    ident = identity(%{policy_binding() | "scopes" => ~w(operator project session)})
    one = String.duplicate("1", 32)
    two = String.duplicate("2", 32)
    assert {:ok, global} = State.namespace(ident, "operator", "/fixture/one", one)
    assert {:ok, ^global} = State.namespace(ident, "operator", "/fixture/two", two)
    assert {:ok, project} = State.namespace(ident, "project", "/fixture/one", one)
    assert {:ok, ^project} = State.namespace(ident, "project", "/fixture/one", two)
    assert {:ok, other} = State.namespace(ident, "project", "/fixture/two", one)
    refute other == project
    assert {:ok, session} = State.namespace(ident, "session", "/fixture/one", one)
    assert {:ok, other_session} = State.namespace(ident, "session", "/fixture/one", two)
    refute session == other_session
    assert {:error, _} = State.namespace(identity(), "operator", "/fixture/one", one)
    refute Registry.valid_identity?(Map.put(ident, "scope", "project"))
    refute Registry.valid_identity?(put_in(ident, ["state_binding", "extra"], true))

    assert {:ok, isolated} =
             State.namespace(
               put_in(ident, ["state_binding", "id"], "other-store"),
               "project",
               "/fixture/one",
               one
             )

    refute isolated == project
  end

  test "project selections cannot acquire an operator binding through an instance override" do
    operator = source(policy_binding())

    project = %{
      scope: "project",
      path: "/fixture/project/.ipse/config.json",
      data: %{"extensions" => operator.data["extensions"]}
    }

    assert {:error, _} = Config.resolve([operator, project], [])

    project =
      put_in(
        project,
        [:data, "extensions", Access.at(0), "instance"],
        "isolated-project-instance"
      )

    assert {:ok, catalog} = Config.resolve([operator, project], [])
    assert {:ok, entries} = Registry.prepare(catalog, "/fixture/home")
    project_entry = Enum.find(entries, &(&1.identity["scope"] == "project"))
    refute Map.has_key?(project_entry.identity, "state_binding")
  end

  test "closed bounded versioned bindings reject ambiguous or widened operator policy" do
    for change <- [
          %{"id" => "../escape"},
          %{"version" => 2},
          %{"version" => 1.0},
          %{"scopes" => []},
          %{"scopes" => ["project", "project"]},
          %{"scopes" => ["global"]},
          %{"instance" => "../bad"},
          %{"extra" => true}
        ] do
      assert {:error, _} = Config.resolve([source(Map.merge(policy_binding(), change))], [])
    end

    operator = source(policy_binding())

    duplicate =
      update_in(operator, [:data, "extension_trust", Access.at(0), "state_bindings"], &(&1 ++ &1))

    assert {:error, _} = Config.resolve([duplicate], [])
  end

  test "legacy identities retain byte-identical namespaces and remain configuration isolated" do
    bound = identity()
    legacy = Map.delete(bound, "state_binding")
    assert Registry.valid_identity?(legacy)
    session = String.duplicate("1", 32)

    expected =
      Ipse.JSON.digest([
        %{
          "version" => 1,
          "instance" => legacy["instance"],
          "artifact_sha256" => legacy["artifact_sha256"],
          "source_sha256" => legacy["source_sha256"],
          "scope" => "project",
          "project" => Ipse.JSON.sha256("/fixture/project"),
          "session" => nil
        }
      ])

    assert {:ok, ^expected} = State.namespace(legacy, "project", "/fixture/project", session)
    changed = Map.put(legacy, "source_sha256", String.duplicate("b", 64))
    assert {:ok, other} = State.namespace(changed, "project", "/fixture/project", session)
    refute expected == other
  end
end
