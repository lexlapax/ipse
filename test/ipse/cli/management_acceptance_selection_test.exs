Code.require_file("../../support/managed_policy.exs", __DIR__)

defmodule Ipse.CLI.ManagementAcceptanceSelectionTest do
  use ExUnit.Case, async: false

  alias Ipse.{JSON, Usage}
  alias Ipse.CLI.Knowledge.Management

  alias Ipse.Extension.{
    Artifact,
    Bundles,
    Consent,
    ProjectIdentity,
    SemanticAdmission,
    SemanticConsent
  }

  alias Ipse.Test.ManagedPolicy, as: F

  test "acceptance source selection binds the installed artifact and current policy" do
    root = Path.join(System.tmp_dir!(), "ipse-acceptance-selection-" <> Usage.id())
    home = Path.join(root, "home")
    cwd = Path.join(root, "work")
    history = Path.join(home, "sessions")
    for path <- [root, home, cwd, history], do: File.mkdir!(path)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)

    assert {:ok, binding} = ProjectIdentity.admit(home, cwd, :folder)
    id = Usage.id()
    config = %{home: home}

    assert {:error, :knowledge_management_refused} =
             Management.acceptance_source_selection(config, cwd, history, id)

    assert {:ok, _} = Bundles.install("knowledge", home)
    assert {:ok, entries} = Bundles.inventory()
    %{digest: digest} = Enum.find(entries, &(&1.id == "knowledge"))

    assert {:ok, bytes} =
             Artifact.read_declared(
               Path.join(home, "extensions/artifacts"),
               digest,
               "operator.json",
               65_536
             )

    assert {:ok, sidecar} = JSON.decode_unique(bytes)
    note = sidecar["recipes"]["note"]
    proposal = sidecar["recipes"]["pending"]
    note_constraint = sidecar["publication"]["note"]
    proposal_constraint = sidecar["publication"]["pending"]
    {:ok, namespace} = SemanticConsent.namespace(binding["project_id"], "knowledge")

    policy =
      F.policy()
      |> Map.put("project", binding["project_id"])
      |> Map.put("artifact_sha256", digest)
      |> Map.put("expires_at_ms", System.system_time(:millisecond) + 60_000)
      |> put_in(["settings", "namespace"], namespace)
      |> put_in(["settings", "storage", "collection"], "knowledge")
      |> put_in(["settings", "activation", "artifact"], digest)
      |> put_in(["settings", "activation", "artifact_sha256"], digest)
      |> put_in(["settings", "constraints"], %{
        JSON.digest([note_constraint]) => note_constraint,
        JSON.digest([proposal_constraint]) => proposal_constraint
      })
      |> put_in(["settings", "recipes"], %{
        JSON.digest([note]) => note,
        JSON.digest([proposal]) => proposal
      })
      |> update_in(["settings", "effects"], fn effects ->
        Enum.map(effects, fn effect ->
          case effect["class"] do
            "collection.publish" ->
              {recipe, constraint} =
                if effect["operation"] == "notes.save",
                  do: {note, note_constraint},
                  else: {proposal, proposal_constraint}

              %{
                effect
                | "recipe_sha256" => JSON.digest([recipe]),
                  "constraints_sha256" => JSON.digest([constraint])
              }

            "collection.read" ->
              %{
                effect
                | "managed_read" => Enum.sort([JSON.digest([note]), JSON.digest([proposal])])
              }
          end
        end)
      end)

    assert SemanticConsent.policy?(policy)
    control = SemanticAdmission.control_root(home)

    assert {:ok, %{"epoch" => 1}} =
             Consent.replace(
               control,
               binding["project_id"],
               0,
               policy,
               System.system_time(:millisecond)
             )

    assert {:ok, selected} = Management.acceptance_source_selection(config, cwd, history, id)
    assert selected.selection.digest === digest
    assert selected.selection.recipe === note and selected.selection.proposal === proposal

    assert selected.context.config.semantic_admission["pin"]["policy_sha256"] ===
             JSON.digest([policy])

    pin = selected.context.config.semantic_admission["pin"]
    owned = %{id: id, journal_owner: self(), writer: self()}

    context = %{
      "operation_id" => Usage.id(),
      "journal_id" => id,
      "client_id" => Usage.id(),
      "session_id" => nil,
      "project_id" => binding["project_id"],
      "namespace" => namespace,
      "binding_sha256" => binding["binding_sha256"],
      "policy_sha256" => pin["policy_sha256"],
      "capture_epoch" => pin["epoch"],
      "render_revision" => 1,
      "recipe" => proposal
    }

    for invalid <- [false, Map.put(context, "policy_sha256", JSON.sha256("other"))] do
      assert {:error, :knowledge_management_refused} =
               Management.with_verified_acceptance_target(
                 config,
                 cwd,
                 history,
                 owned,
                 "pending." <> JSON.sha256("missing"),
                 invalid,
                 fn _, _, _, _, _ -> flunk("invalid context reached review") end
               )
    end

    assert {:error, :knowledge_management_refused} =
             Management.acceptance_source_selection(config, cwd, "relative", id)

    other = JSON.sha256("different installed artifact")

    foreign =
      policy
      |> Map.put("artifact_sha256", other)
      |> put_in(["settings", "activation", "artifact"], other)
      |> put_in(["settings", "activation", "artifact_sha256"], other)

    assert SemanticConsent.policy?(foreign)

    assert {:ok, %{"epoch" => 2}} =
             Consent.replace(
               control,
               binding["project_id"],
               1,
               foreign,
               System.system_time(:millisecond)
             )

    assert {:error, :knowledge_management_refused} =
             Management.acceptance_source_selection(config, cwd, history, id)

    assert {:ok, %{"epoch" => 3}} =
             Consent.replace(
               control,
               binding["project_id"],
               2,
               policy,
               System.system_time(:millisecond)
             )

    assert {:ok, _} = Management.acceptance_source_selection(config, cwd, history, id)
    sidecar_path = Path.join([home, "extensions", "artifacts", digest, "operator.json"])
    File.chmod!(sidecar_path, 0o600)
    File.write!(sidecar_path, bytes <> " ")

    assert {:error, :knowledge_management_refused} =
             Management.acceptance_source_selection(config, cwd, history, id)
  end
end
