defmodule Ipse.Extension.DecisionCapabilityTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.{Artifact, Catalog, Config, Registry}

  test "decision grant requires host actions and remains separate from model and embedding authority" do
    assert "host.decision" in Catalog.capabilities()
    assert {:error, _} = Catalog.validate(Catalog.empty(), ["host.decision"])
    assert :ok = Catalog.validate(Catalog.empty(), ~w(host.actions host.decision))
    assert :ok = Catalog.validate(Catalog.empty(), ~w(host.actions host.model))
    assert :ok = Catalog.validate(Catalog.empty(), ~w(host.actions host.embedding))
  end

  test "artifact capability, operator trust and explicit children permission all remain necessary" do
    root = Path.join(System.tmp_dir!(), "ipse-decision-capability-" <> Ipse.Usage.id())
    artifact = Path.join(root, "artifact")
    home = Path.join(root, "home")
    File.mkdir_p!(Path.join(artifact, "ebin"))
    on_exit(fn -> File.rm_rf!(root) end)
    source = Path.join(root, "fixture.ex")
    module = "Fixture.DecisionCapability#{System.unique_integer([:positive])}"
    File.write!(source, "defmodule #{module} do\n def inert, do: :ok\nend\n")

    {log, status} =
      System.cmd(System.find_executable("elixirc"), ["-o", Path.join(artifact, "ebin"), source],
        stderr_to_stdout: true
      )

    assert status == 0, log
    File.write!(Path.join(artifact, "LICENSE"), "MIT synthetic fixture")
    caps = ~w(host.actions host.decision)
    paths = ["LICENSE", "ebin/Elixir.#{module}.beam"]

    manifest = %{
      "format" => 1,
      "id" => "fixture/decision-capability",
      "version" => "0.1.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => module,
      "license_file" => "LICENSE",
      "options_schema" => %{"type" => "object", "additionalProperties" => false},
      "capabilities" => caps,
      "exports" => Catalog.empty(),
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      },
      "files" =>
        Enum.map(paths, fn path ->
          bytes = File.read!(Path.join(artifact, path))
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
        end)
    }

    File.write!(Path.join(artifact, "extension.json"), Jason.encode!(manifest))
    assert {:ok, installed} = Artifact.import(artifact, Path.join(home, "extensions/artifacts"))

    instance = %{
      "instance" => "advice",
      "artifact" => installed.digest,
      "enabled" => true,
      "options" => %{},
      "order" => 1,
      "lifetime" => "persistent"
    }

    trust = %{
      "artifact" => installed.digest,
      "capabilities" => caps,
      "allow_project" => false,
      "allow_children" => false
    }

    selection = fn ceiling ->
      Config.resolve(
        [
          %{
            scope: "operator",
            path: Path.join(home, "config.json"),
            data: %{"extensions" => [instance], "extension_trust" => [ceiling]}
          }
        ],
        []
      )
    end

    assert {:ok, catalog} = selection.(trust)
    assert {:ok, [entry]} = Registry.prepare(catalog, home)
    assert entry.identity["capabilities"] == caps
    assert Registry.valid_entries?(%{extensions: [entry]})
    assert {:error, _} = Registry.prepare(catalog, home, true)

    profiles = %{
      "advice" => %{
        "operation" => "decision",
        "provider" => "system_one",
        "model" => "jev-latest",
        "service_id" => "typesafe"
      }
    }

    parent = %{extensions: [entry], decision_profiles: profiles}
    assert Ipse.Tools.Delegation.child_config(parent, %{}).decision_profiles == %{}
    assert {:ok, narrow} = selection.(%{trust | "capabilities" => ["host.actions"]})
    assert {:error, _} = Registry.prepare(narrow, home)
    assert {:ok, granted} = selection.(%{trust | "allow_children" => true})
    assert {:ok, [child_entry]} = Registry.prepare(granted, home, true)
    child = Ipse.Tools.Delegation.child_config(%{parent | extensions: [child_entry]}, %{})
    assert child.decision_profiles == profiles
    assert child.extensions == [child_entry]
    assert child.approval == :ask
    assert child.subagents == false and child.mcp_servers == []

    assert {:ok, named} =
             Ipse.Config.Profiles.child_config(
               Map.merge(parent, %{
                 extensions: [child_entry],
                 profiles: %{"routine" => %{"provider" => "ollama", "model" => "fixture"}},
                 roles: %{"routine" => "routine"}
               }),
               %{},
               %{}
             )

    assert named.decision_profiles == profiles and named.extensions == [child_entry]
  end
end
