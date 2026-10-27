[root] = System.argv()
true = Path.expand(Application.app_dir(:ipse)) == Path.join(root, "ipse")
Code.require_file("test/support/managed_policy.exs")
{:ok, _} = Application.ensure_all_started(:ipse)
Application.put_env(:ipse, :activation_test_root, root)
ExUnit.start(seed: 20_261_026)

defmodule Ipse.Test.ActivationOverlayVM do
  use ExUnit.Case, async: false
  alias Ipse.{Config, JSON, Journal, Session}
  alias Ipse.Config.Activation, as: Host

  alias Ipse.Extension.{
    Activation,
    Artifact,
    Bundles,
    Catalog,
    Consent,
    ProjectIdentity,
    Registry,
    SemanticAdmission,
    SemanticConsent,
    SemanticRoutes
  }

  alias Ipse.Test.ManagedPolicy, as: F

  setup_all do
    root = Application.fetch_env!(:ipse, :activation_test_root)
    artifact = Path.join(root, "fixture")
    File.mkdir_p!(Path.join(artifact, "ebin"))

    capabilities =
      ~w(invoke.tool invoke.command invoke.result.pages host.actions host.sources host.collection.read host.collection.managed)

    item = %{
      "id" => "capture",
      "description" => "Inert activation fixture",
      "arguments_schema" => %{
        "type" => "object",
        "properties" => %{},
        "additionalProperties" => false
      },
      "result_schema" => %{
        "type" => "object",
        "properties" => %{"ready" => %{"type" => "boolean"}},
        "required" => ["ready"],
        "additionalProperties" => false
      }
    }

    exports =
      Catalog.empty()
      |> Map.put("tools", [item])
      |> Map.put("commands", [%{item | "id" => "inspect"}])

    source = """
    defmodule Independent.ActivationFixture do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk"=>2,"capabilities"=>#{inspect(capabilities)},"exports"=>#{inspect(exports)}}
      def init(options), do: {:ok, options}
      def handle(_stage, _payload, state) do
        {:ok, reply} = Ipse.Extension.ResultPublication.prepare(%{"ready"=>true})
        {:ok, reply, state}
      end
    end
    """

    File.write!(Path.join(root, "fixture.ex"), source)

    assert {"", 0} =
             System.cmd(
               System.find_executable("elixirc"),
               [
                 "--erl",
                 "+S 2:2",
                 "-pa",
                 Application.app_dir(:ipse, "ebin"),
                 "-pa",
                 Application.app_dir(:jason, "ebin"),
                 "-o",
                 Path.join(artifact, "ebin"),
                 Path.join(root, "fixture.ex")
               ],
               stderr_to_stdout: true
             )

    File.write!(Path.join(artifact, "LICENSE"), "MIT synthetic activation fixture")

    File.write!(
      Path.join(artifact, "operator.json"),
      Jason.encode!(IpseKnowledge.Knowledge.Contracts.operator())
    )

    files =
      for path <- ["LICENSE", "operator.json", "ebin/Elixir.Independent.ActivationFixture.beam"],
          do: %{
            "path" => path,
            "bytes" => File.stat!(Path.join(artifact, path)).size,
            "sha256" => JSON.sha256(File.read!(Path.join(artifact, path)))
          }

    manifest = %{
      "format" => 1,
      "id" => "fixture/activation",
      "version" => "0.1.0",
      "sdk" => 2,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => "Independent.ActivationFixture",
      "license_file" => "LICENSE",
      "files" => files,
      "capabilities" => capabilities,
      "exports" => exports,
      "options_schema" => %{
        "type" => "object",
        "properties" => %{},
        "additionalProperties" => false
      },
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      }
    }

    File.write!(Path.join(artifact, "extension.json"), Jason.encode!(manifest))
    bundles = Application.app_dir(:ipse, "priv/extension-bundles")
    File.rm_rf!(bundles)
    File.mkdir_p!(bundles)
    File.cp_r!(artifact, Path.join(bundles, "fixture"))
    digest = JSON.sha256(Jason.encode!(manifest))

    catalog =
      Jason.encode!(%{
        "version" => 1,
        "artifacts" => [
          %{"id" => "activation-fixture", "path" => "fixture", "manifest_sha256" => digest}
        ]
      })

    File.write!(Path.join(bundles, "catalog.json"), catalog)
    assert {:ok, [_]} = Bundles.inventory()
    %{artifact: artifact, bundles: bundles, catalog: catalog}
  end

  setup c do
    root = Path.join(Application.fetch_env!(:ipse, :activation_test_root), Ipse.Usage.id())
    home = Path.join(root, "home")
    cwd = Path.join(root, "project")
    File.mkdir_p!(home)
    File.chmod!(home, 0o700)
    File.mkdir!(cwd)
    File.write!(Path.join(c.bundles, "catalog.json"), c.catalog)

    assert {:ok, effective} =
             Config.resolve(
               cwd,
               home,
               [provider: "ollama", model: "synthetic", project_config: false],
               %{}
             )

    client = %{
      base_url: nil,
      home: home,
      auth_dir: nil,
      operator_home: nil,
      workspace: cwd,
      mcp_config: nil,
      operator_questions: false,
      approval: :deny,
      approval_origin: :default_headless,
      headless: true
    }

    assert {:ok, config} = Config.runtime(effective, client)

    %{
      root: root,
      home: home,
      cwd: cwd,
      effective: effective,
      config: config,
      client: client,
      dir: Path.join(root, "sessions")
    }
  end

  defp grant(c, modifications \\ fn x -> x end) do
    assert {:ok, binding} = ProjectIdentity.admit(c.home, c.cwd, Map.get(c, :scope, :folder))

    assert {:ok, artifact} =
             Artifact.import(c.artifact, Path.join(c.home, "extensions/artifacts"))

    p = F.policy()
    assert {:ok, selectors} = SemanticRoutes.selectors(p["settings"]["routes"])
    assert {:ok, preview} = SemanticRoutes.review(c.config, selectors)

    a =
      F.activation()
      |> Map.merge(%{
        "artifact" => artifact.digest,
        "artifact_sha256" => artifact.digest,
        "sidecar_sha256" => JSON.sha256(File.read!(Path.join(c.artifact, "operator.json"))),
        "options" => %{},
        "capabilities" => Enum.sort(artifact.manifest["capabilities"]),
        "main_timeout_ms" => 90_000,
        "service_refs" =>
          Enum.map(preview.routes, &Map.take(&1, ~w(operation profile service_id)))
      })

    assert {:ok, draft} = Activation.draft(binding["project_id"], a, c.effective.extensions)
    assert {:ok, [entry] = entries} = Registry.prepare(draft.catalog, c.home)
    cfg = Map.put(c.config, :extensions, entries)
    assert {:ok, catalog} = Catalog.snapshot(cfg)
    capture = Enum.find(catalog["entries"], &(&1["id"] == "capture"))
    inspect = Enum.find(catalog["entries"], &(&1["id"] == "inspect"))
    assert {:ok, reviewed} = SemanticRoutes.review(cfg, selectors)
    assert reviewed == preview
    assert {:ok, namespace} = SemanticConsent.namespace(binding["project_id"], "notes")

    selection =
      p["settings"]
      |> Map.drop(~w(instance identity_sha256))
      |> Map.merge(%{
        "namespace" => namespace,
        "routes" => reviewed.routes,
        "activation" => a,
        "effects" =>
          Enum.map(p["settings"]["effects"], fn m ->
            Map.put(
              m,
              "outer_sha256",
              JSON.digest([if(m["class"] == "collection.read", do: inspect, else: capture)])
            )
          end)
      })
      |> Map.merge(Map.take(p, ~w(limits period_ms headless)))
      |> Map.put("expires_at_ms", System.system_time(:millisecond) + 600_000)
      |> modifications.()

    assert {:ok, policy} = SemanticConsent.prepare(binding, entry.identity, selection)
    control = SemanticAdmission.control_root(c.home)
    assert {:ok, snapshot} = Consent.snapshot(control, binding["project_id"])

    assert {:ok, _} =
             Consent.replace(
               control,
               binding["project_id"],
               snapshot["epoch"],
               policy,
               System.system_time(:millisecond)
             )

    %{binding: binding, policy: policy, artifact: artifact, control: control, a: a}
  end

  defp start(c, config \\ nil, id \\ nil) do
    result =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: config || c.config, cwd: c.cwd, state_dir: c.dir, subscriber: self(), id: id}
      )

    case result do
      {:ok, pid} ->
        on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
        {:ok, pid}

      other ->
        other
    end
  end

  defp revoke(g) do
    {:ok, s} = Consent.snapshot(g.control, g.binding["project_id"])
    assert {:ok, _} = Consent.revoke(g.control, g.binding["project_id"], s["epoch"])
  end

  defp worktree(c) do
    linked = Path.join(c.root, "linked")
    admin = Path.join(c.cwd, ".git/worktrees/linked")
    File.mkdir_p!(admin)
    File.mkdir!(linked)
    File.write!(Path.join(linked, ".git"), "gitdir: #{admin}\n")
    File.write!(Path.join(admin, "commondir"), "../..\n")
    File.write!(Path.join(admin, "gitdir"), Path.join(linked, ".git") <> "\n")

    assert {:ok, effective} =
             Config.resolve(
               linked,
               c.home,
               [provider: "ollama", model: "synthetic", project_config: false],
               %{}
             )

    client = Map.put(c.client, :workspace, linked)
    assert {:ok, config} = Config.runtime(effective, client)

    {Map.put(c, :scope, :repository),
     %{c | cwd: linked, client: client, config: config, effective: effective}}
  end

  test "ordinary no-project startup/current probe writes no control state", c do
    assert {:ok, %{binding: nil, snapshot: nil}} = Host.current(c.config, c.cwd)
    assert File.ls!(c.home) == []
    assert {:ok, pid} = start(c)
    assert :sys.get_state(pid).config.semantic_admission["status"] == "off"
    assert :ok = Session.close_confirmed(pid)
    assert File.ls!(c.home) == []
  end

  test "fresh protected overlay leaves base config bytes/fingerprint unchanged and runs only explicit work",
       c do
    g = grant(c)

    assert {:ok, %{binding: binding, snapshot: %{"policy" => policy}}} =
             Host.current(c.config, c.cwd)

    assert binding == g.binding and policy == g.policy
    assert {:ok, pid} = start(c)
    s = :sys.get_state(pid)
    assert s.config.configuration == c.config.configuration
    assert s.config.timeout_ms == 90_000 and c.config.timeout_ms == 120_000
    assert s.config.semantic_admission["status"] == "active"
    assert length(s.config.extensions) == 1 and c.config.extensions == []
    assert map_size(s.config.inference_services) == 1
    assert c.config.inference_services == %{}
    refute File.exists?(Path.join(c.home, "config.json"))

    assert {:ok, again} =
             Config.resolve(
               c.cwd,
               c.home,
               [provider: "ollama", model: "synthetic", project_config: false],
               %{}
             )

    assert again.fingerprint == c.effective.fingerprint
    assert :ok = Session.invoke_export(pid, :command, "ext__knowledge__inspect", %{})
    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
    assert Enum.any?(events, &(&1["type"] == "extension_invocation_result"))
    assert {:ok, _} = Session.restore_context(events)
  end

  test "revocation disables fresh selection but saved resume preserves exact old catalog and idle bytes",
       c do
    g = grant(c)
    assert {:ok, pid} = start(c)
    old = :sys.get_state(pid).config
    id = Session.info(pid).id
    assert :ok = Session.close_confirmed(pid)
    journal = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(journal)
    revoke(g)
    assert {:ok, fresh} = start(c)
    assert :sys.get_state(fresh).config.extensions == []
    assert :ok = Session.close_confirmed(fresh)
    File.rm!(Path.join(c.bundles, "catalog.json"))
    assert {:ok, resumed} = start(c, nil, id)
    actual = :sys.get_state(resumed).config
    assert Registry.manifests(actual) == Registry.manifests(old)
    assert actual.timeout_ms == 90_000
    assert File.read!(journal) == before
    assert :ok = Session.invoke_export(resumed, :command, "ext__knowledge__inspect", %{})
    assert_receive {:ipse, ^resumed, {:done, :error}}, 10_000
    assert :ok = Session.close_confirmed(resumed)
  end

  test "a Session saved before enable stays unselected and an explicit opt-out refuses saved activation",
       c do
    assert {:ok, old} = start(c)
    id = Session.info(old).id
    assert :ok = Session.close_confirmed(old)
    grant(c)
    assert {:ok, resumed} = start(c, nil, id)
    assert :sys.get_state(resumed).config.extensions == []
    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, active} = start(c)
    active_id = Session.info(active).id
    assert :ok = Session.close_confirmed(active)

    assert {:ok, disabled_effective} =
             Config.resolve(
               c.cwd,
               c.home,
               [provider: "ollama", model: "synthetic", extensions: false, project_config: false],
               %{}
             )

    assert {:ok, disabled} = Config.runtime(disabled_effective, c.client)
    assert {:ok, fresh} = start(c, disabled)
    assert :sys.get_state(fresh).config.extensions == []
    assert {:error, _} = start(c, disabled, active_id)
  end

  test "selection cannot widen a shorter base timeout, shadow ordinary entries or trust changed sidecar bytes",
       c do
    g = grant(c)
    assert {:error, _} = Host.fresh(Map.put(c.config, :timeout_ms, 30_000), c.cwd)
    assert {:error, _} = Host.fresh(Map.delete(c.config, :base_extension_catalog), c.cwd)

    collision =
      put_in(c.config, [:base_extension_catalog, "instances"], [%{"instance" => "knowledge"}])

    assert {:error, _} = Host.fresh(collision, c.cwd)
    File.write!(Path.join(g.artifact.path, "operator.json"), "changed")
    assert {:error, _} = start(c)
  end

  test "children restore base timeout/services/entries before applying their independent filters",
       c do
    grant(c)
    assert {:ok, parent} = Host.fresh(c.config, c.cwd)
    assert parent.timeout_ms == 90_000
    assert map_size(parent.inference_services) == 1
    assert {:ok, mode} = Ipse.Extension.Mode.capture(parent)
    child = Ipse.Tools.Delegation.child_config(parent, %{"fixture" => true})
    assert child.timeout_ms == c.config.timeout_ms
    assert child.inference_services == c.config.inference_services
    assert child.extensions == []
    refute Map.has_key?(child, :base_extension_catalog)
    assert {:ok, ^child} = Host.fresh(child, c.cwd)
    assert mode["approval"] == "deny"
  end

  test "present malformed protected control and missing retained lock refuse without repair", c do
    g = grant(c)
    control = Path.join([g.control, g.binding["project_id"], "control.json"])
    bytes = File.read!(control)
    File.write!(control, "{}")
    assert {:error, _} = Host.current(c.config, c.cwd)
    assert File.read!(control) == "{}"
    File.write!(control, bytes)
    lock = Path.join(Path.dirname(control), ".lock")
    File.rm!(lock)
    assert {:error, _} = Host.current(c.config, c.cwd)
    refute File.exists?(lock)
    assert File.read!(control) == bytes
  end

  test "fresh selection requires the current bundled digest and saved routes match the actual base",
       c do
    grant(c)
    File.rm!(Path.join(c.bundles, "catalog.json"))
    assert {:error, _} = Host.fresh(c.config, c.cwd)
    File.write!(Path.join(c.bundles, "catalog.json"), c.catalog)
    assert {:error, _} = Host.fresh(Map.put(c.config, :model, "changed-model"), c.cwd)
    assert {:error, _} = Host.fresh(Map.put(c.config, :base_url, "http://localhost:11435"), c.cwd)
  end

  test "a new reciprocal worktree joins only the active protected repository selection", c do
    {primary, linked} = worktree(c)
    g = grant(primary)
    assert {:ok, nil} = ProjectIdentity.existing(c.home, linked.cwd)
    assert {:ok, pid} = start(linked)
    actual = :sys.get_state(pid).config
    assert actual.semantic_admission["status"] == "active"
    binding = actual.semantic_admission["binding"]
    assert binding["project_id"] == g.binding["project_id"]
    assert binding["worktree_id"] != g.binding["worktree_id"]
    assert {:ok, ^binding} = ProjectIdentity.existing(c.home, linked.cwd)
    assert actual.configuration == linked.config.configuration
    assert actual.timeout_ms == 90_000
    refute File.exists?(Path.join(c.home, "config.json"))
  end

  test "repository membership is not joined by an absent or revoked project grant", c do
    {primary, linked} = worktree(c)
    assert {:ok, _} = ProjectIdentity.admit(c.home, c.cwd, :repository)
    assert {:ok, off} = Host.fresh(linked.config, linked.cwd)
    assert off.extensions == []
    assert {:ok, nil} = ProjectIdentity.existing(c.home, linked.cwd)
    g = grant(primary)
    revoke(g)
    assert {:ok, off} = Host.fresh(linked.config, linked.cwd)
    assert off.extensions == []
    assert {:ok, nil} = ProjectIdentity.existing(c.home, linked.cwd)
  end

  test "worktree-scoped activation and invalid artifact bytes cannot authorize a new join", c do
    {primary, linked} = worktree(c)

    grant(primary, fn selection ->
      {:ok, binding} = ProjectIdentity.existing(c.home, c.cwd)

      Map.put(selection, "scope", %{"kind" => "worktree", "worktree_id" => binding["worktree_id"]})
    end)

    assert {:ok, off} = Host.fresh(linked.config, linked.cwd)
    assert off.extensions == []
    assert {:ok, nil} = ProjectIdentity.existing(c.home, linked.cwd)
    g = grant(primary)
    File.write!(Path.join(g.artifact.path, "operator.json"), "changed")
    assert {:error, _} = Host.fresh(linked.config, linked.cwd)
    assert {:ok, nil} = ProjectIdentity.existing(c.home, linked.cwd)
  end

  test "a grant revoked after candidate authorization leaves no Session execution permission",
       c do
    {primary, linked} = worktree(c)
    g = grant(primary)

    assert {:ok, joined} =
             ProjectIdentity.join_existing(c.home, linked.cwd, fn _ ->
               revoke(g)
               :ok
             end)

    assert joined["project_id"] == g.binding["project_id"]
    assert {:ok, pid} = start(linked)
    actual = :sys.get_state(pid).config
    assert actual.extensions == []
    assert actual.semantic_admission["status"] == "off"
  end

  test "status and readiness preserve both ledgers' pending bytes even on a malformed read", c do
    g = grant(c)
    identity = Path.join(c.home, "project-identities")
    control = Path.join(g.control, g.binding["project_id"])

    pending =
      Enum.map([identity, control], fn directory ->
        path = Path.join(directory, ".pending-" <> Ipse.Usage.id())
        File.write!(path, "preserved pending state")
        File.chmod!(path, 0o600)
        path
      end)

    index = File.read!(Path.join(identity, "index.json"))
    bytes = File.read!(Path.join(control, "control.json"))
    assert {:ok, %{ready: true, binding: binding}} = Host.readiness(c.config, c.cwd)
    assert binding == g.binding
    assert {:ok, _} = Host.current(c.config, c.cwd)
    for path <- pending, do: assert(File.read!(path) == "preserved pending state")
    assert File.read!(Path.join(identity, "index.json")) == index
    assert File.read!(Path.join(control, "control.json")) == bytes
    File.write!(Path.join(control, "control.json"), "{}")
    assert {:error, _} = Host.current(c.config, c.cwd)
    assert {:error, _} = Host.readiness(c.config, c.cwd)
    for path <- pending, do: assert(File.read!(path) == "preserved pending state")
    assert File.read!(Path.join(control, "control.json")) == "{}"
    assert File.read!(Path.join(identity, "index.json")) == index
  end

  test "readiness is advisory, never joins, and applies the actual base route and mode ceilings",
       c do
    {primary, linked} = worktree(c)
    g = grant(primary)
    assert {:ok, %{ready: false, binding: nil}} = Host.readiness(linked.config, linked.cwd)
    assert {:ok, nil} = ProjectIdentity.existing(c.home, linked.cwd)
    assert {:ok, %{ready: true}} = Host.readiness(c.config, c.cwd)

    assert {:ok, %{ready: false}} =
             Host.readiness(Map.put(c.config, :extensions_disabled, true), c.cwd)

    assert {:ok, %{ready: false}} =
             Host.readiness(Map.put(c.config, :parallel_child, true), c.cwd)

    assert {:error, _} = Host.readiness(Map.put(c.config, :timeout_ms, 30_000), c.cwd)
    assert {:error, _} = Host.readiness(Map.put(c.config, :model, "changed-model"), c.cwd)

    wrong_identity =
      put_in(g.policy, ["settings", "identity_sha256"], JSON.sha256("stale identity"))

    assert SemanticConsent.policy?(wrong_identity)

    assert {:ok, _} =
             Consent.replace(
               g.control,
               g.binding["project_id"],
               1,
               wrong_identity,
               System.system_time(:millisecond)
             )

    assert {:ok, %{snapshot: %{"policy" => ^wrong_identity}}} = Host.current(c.config, c.cwd)
    assert {:error, _} = Host.readiness(c.config, c.cwd)
    assert {:error, _} = Host.fresh(c.config, c.cwd)
    revoke(g)
    assert {:ok, %{ready: false}} = Host.readiness(c.config, c.cwd)
  end

  test "current and readiness never create a missing ancillary writer in either ledger", c do
    g = grant(c)
    identity_writer = Path.join(c.home, "project-identities/.writer.lock")
    control_writer = Path.join([g.control, g.binding["project_id"], ".writer.lock"])
    File.rm!(identity_writer)
    assert {:error, _} = Host.current(c.config, c.cwd)
    assert {:error, _} = Host.readiness(c.config, c.cwd)
    refute File.exists?(identity_writer)
    assert {:ok, _} = ProjectIdentity.resolve(c.home, c.cwd)
    assert {:ok, %{ready: true}} = Host.readiness(c.config, c.cwd)
    File.rm!(control_writer)
    assert {:error, _} = Host.current(c.config, c.cwd)
    assert {:error, _} = Host.readiness(c.config, c.cwd)
    refute File.exists?(control_writer)
    assert {:ok, _} = Consent.revoke(g.control, g.binding["project_id"], 1)
    assert {:ok, %{ready: false}} = Host.readiness(c.config, c.cwd)
  end
end

ExUnit.after_suite(fn %{failures: failures} ->
  if failures == 0, do: IO.puts("activation overlay child controls complete")
end)
