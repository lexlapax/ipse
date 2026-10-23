Code.require_file("../../../dev/verification/knowledge.exs", __DIR__)

defmodule Ipse.KnowledgeIndependenceTest do
  use ExUnit.Case, async: false

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-independence-artifacts-" <> Ipse.Usage.id())
    on_exit(fn -> File.rm_rf!(root) end)

    for {package, preset} <- [
          {"corpus", "state-lexical"},
          {"graph", "state-explicit"},
          {"research", "offline"}
        ] do
      {output, status} =
        System.cmd(
          System.find_executable("elixir"),
          [
            "extensions/knowledge/build.exs",
            "--sdk",
            Application.app_dir(:ipse, "ebin"),
            "--output",
            Path.join(root, package),
            "--package",
            package,
            "--preset",
            preset
          ],
          stderr_to_stdout: true
        )

      assert status == 0, output
    end

    %{artifacts: root}
  end

  for {kind, scope} <- [
        {"working", "session"},
        {"persistent", "project"},
        {"persistent", "operator"}
      ],
      package <- ~w(corpus graph research) do
    @tag selection: {kind, scope, package}
    test "#{scope} memory and #{package} remain independent through real Sessions", ctx do
      report = IpseKnowledgeExample.Proof.independence(ctx.artifacts, ctx.selection)
      assert report["checks"] == 2
      assert report["catalog_bound_refused"] and report["cleanup"] == "confirmed"
      assert report["model_requests"] == 0 and report["payloads_traced"] == false
      assert report["host_loaded_domain_modules"] == false
      [row] = report["cases"]
      assert {row["memory"], row["scope"], row["package"]} == ctx.selection

      assert row["note_isolation"] and row["forget_isolation"]
      assert row["state_files"] == if(row["package"] == "research", do: 1, else: 2)

      for phase <- ~w(disabled_calls idle_calls resume_calls) do
        assert Enum.all?(Map.values(row[phase]), &(&1 == 0))
      end

      assert row["operation_calls"]["extension_worker_starts"] > 0
      assert row["operation_calls"]["state_operations"] > 0
    end
  end

  for {package, presets} <- [
        {"corpus",
         ~w(state-dense state-rerank state-semantic mcp-lexical mcp-dense mcp-rerank mcp-semantic)},
        {"graph", ~w(state-model mcp-explicit mcp-model)},
        {"research", ~w(mcp mcp-model)}
      ],
      preset <- presets do
    test "#{package}/#{preset} capability grants remain inert when disabled, idle and resumed",
         ctx do
      package = unquote(package)
      preset = unquote(preset)
      root = Path.join(ctx.artifacts, package <> "-" <> preset)
      artifact = Path.join(root, "artifact")
      File.mkdir_p!(root)

      {output, status} =
        System.cmd(
          System.find_executable("elixir"),
          [
            "extensions/knowledge/build.exs",
            "--sdk",
            Application.app_dir(:ipse, "ebin"),
            "--output",
            artifact,
            "--package",
            package,
            "--preset",
            preset
          ],
          stderr_to_stdout: true
        )

      assert status == 0, output

      {:ok, imported} =
        Ipse.Extension.Artifact.import(artifact, Path.join(root, "home/extensions/artifacts"))

      manifest = Jason.decode!(File.read!(Path.join(artifact, "extension.json")))

      base = %{
        "corpus" => "corpus-lexical",
        "graph" => "graph-explicit",
        "research" => "research-offline"
      }

      options =
        Jason.decode!(File.read!("extensions/knowledge/options/" <> base[package] <> ".json"))

      remote = String.starts_with?(preset, "mcp") and package != "research"

      options =
        if remote,
          do:
            put_in(options, ["stores", "notes"], %{
              "kind" => "mcp_cas",
              "binding" => "records",
              "partition" => "manual",
              "contract" => "ipse-cas-v3"
            }),
          else: options

      trust = %{
        "artifact" => imported.digest,
        "capabilities" => manifest["capabilities"],
        "allow_project" => false,
        "allow_children" => false,
        "state_bindings" =>
          if(package != "research" and not remote,
            do: [
              %{
                "version" => 1,
                "instance" => package,
                "id" => "knowledge-proof",
                "scopes" => ["project"]
              }
            ],
            else: []
          ),
        "mcp_bindings" =>
          if(remote,
            do: [%{"instance" => package, "alias" => "records", "tool" => "mcp__fixture__store"}],
            else: []
          )
      }

      points = [
        {Ipse.Extension.Worker, :start, 1},
        {Ipse.Extension.State, :execute, 4},
        {Ipse.Extension.MCPCall, :execute, 2},
        {Ipse.Extension.EmbeddingCall, :execute, 2},
        {Ipse.Extension.ModelCall, :execute, 2}
      ]

      trace = :trace.session_create(:knowledge_preset_inert, self(), [])

      try do
        for point = {module, _, _} <- points do
          Code.ensure_loaded!(module)
          assert :trace.function(trace, point, true, [:call_count]) == 1
        end

        for enabled <- [false, true] do
          source = %{
            scope: "operator",
            path: Path.join(root, "operator.json"),
            data: %{
              "extensions" => [
                %{
                  "instance" => package,
                  "artifact" => imported.digest,
                  "enabled" => enabled,
                  "options" => options,
                  "order" => 0,
                  "lifetime" => "persistent"
                }
              ],
              "extension_trust" => [trust]
            }
          }

          assert {:ok, selected} = Ipse.Extension.Config.resolve([source], [])

          assert {:ok, entries} =
                   Ipse.Extension.Registry.prepare(selected, Path.join(root, "home"))

          config = %{
            provider: :demo,
            model: "unused",
            provider_module: IpseKnowledgeExample.Proof.NoModel,
            home: Path.join(root, "home"),
            approval: :deny,
            extensions: entries
          }

          args = [
            config: config,
            cwd: root,
            state_dir: Path.join(root, "sessions"),
            subscriber: self(),
            owner: self()
          ]

          assert {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, args})
          id = Ipse.Session.info(pid).id
          assert Ipse.Session.exports(pid)["entries"] != [] == enabled
          assert Ipse.Session.info(pid).accounting["request_count"] == 0
          assert :ok = Ipse.Session.close_confirmed(pid)

          assert {:ok, resumed} =
                   DynamicSupervisor.start_child(
                     Ipse.Sessions,
                     {Ipse.Session, Keyword.put(args, :id, id)}
                   )

          assert Ipse.Session.info(resumed).phase == :idle
          assert :ok = Ipse.Session.close_confirmed(resumed)
        end

        for point <- points,
            do: assert(:trace.info(trace, point, :call_count) == {:call_count, 0})
      after
        :trace.session_destroy(trace)
      end

      for module <- [IpseKnowledge.Corpus, IpseKnowledge.Graph, IpseKnowledge.Research],
          do: refute(:code.is_loaded(module))
    end
  end
end
