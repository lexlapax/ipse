defmodule Ipse.KnowledgeBuildSpecTest do
  use ExUnit.Case, async: false
  alias Ipse.Extensions.Config
  @root Path.expand("..", __DIR__)

  defp isolated(body) do
    {text, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "-r",
          Path.join(@root, "extensions/knowledge/src/profiles.ex"),
          "-r",
          Path.join(@root, "extensions/knowledge/spec.exs"),
          "-e",
          "import ExUnit.Assertions\nalias IpseKnowledge.BuildSpec, as: S\n" <> body
        ],
        stderr_to_stdout: true
      )

    assert status == 0, text
    text
  end

  test "generated State configuration has exact trust, disabled selection and explicit logical binding" do
    path = Path.join(@root, "extensions/knowledge/options/corpus-lexical.json")

    json =
      isolated(
        "options=S.read_json!(#{inspect(path)},16_384)\n" <>
          ~S'''
          m=%{"id"=>"ipse-knowledge/corpus","entrypoint"=>"IpseKnowledge.Corpus",
            "capabilities"=>IpseKnowledge.Profiles.capabilities("corpus","state-lexical"),
          "options_schema"=>S.options_schema(), "exports"=>%{"commands"=>[%{"id"=>"source"}],"tools"=>[],"services"=>[]}}
          bytes=IO.iodata_to_binary(JSON.encode!(m))
          c=S.operator(bytes,"corpus","state-lexical","corpus",options,"knowledge",%{})
          [instance]=c["extensions"]; [trust]=c["extension_trust"]
          assert instance["enabled"]==false and instance["artifact"]==S.digest(bytes)
          assert trust["allow_project"]==false and trust["allow_children"]==false
          assert trust["state_bindings"]==[%{"version"=>1,"instance"=>"corpus","id"=>"knowledge","scopes"=>["project"]}]
          assert_raise ArgumentError,fn -> S.operator(bytes,"corpus","state-lexical","corpus",options,nil,%{}) end
          assert_raise ArgumentError,fn -> S.operator(bytes,"corpus","state-semantic","corpus",options,"knowledge",%{}) end
          assert_raise ArgumentError,fn -> S.operator(bytes,"corpus","state-lexical",String.duplicate("a",64),options,"knowledge",%{}) end
          IO.puts(JSON.encode!(c))
          '''
      )

    assert Config.validate(Jason.decode!(json)) == :ok
    refute :code.is_loaded(IpseKnowledge.Profiles)
    refute :code.is_loaded(IpseKnowledge.Corpus)
  end

  test "MCP selection cannot add aliases outside the checked profile registry" do
    path = Path.join(@root, "extensions/knowledge/options/corpus-lexical.json")

    json =
      isolated(
        "options=S.read_json!(#{inspect(path)},16_384)\n" <>
          ~S'''
          options=put_in(options,["stores","notes"],%{"kind"=>"mcp_cas","binding"=>"reviewed","partition"=>"project-a","contract"=>"ipse-cas-v1"})
          m=%{"id"=>"ipse-knowledge/corpus","entrypoint"=>"IpseKnowledge.Corpus",
          "capabilities"=>IpseKnowledge.Profiles.capabilities("corpus","mcp-lexical"),"options_schema"=>S.options_schema(),"exports"=>%{"commands"=>[%{"id"=>"source"}],"tools"=>[],"services"=>[]}}
          bytes=IO.iodata_to_binary(JSON.encode!(m))
          bindings=%{"reviewed"=>"mcp__local__cas"}
          assert_raise ArgumentError,fn -> S.operator(bytes,"corpus","mcp-lexical","corpus",options,nil,%{}) end
          assert_raise ArgumentError,fn -> S.operator(bytes,"corpus","mcp-lexical","corpus",options,"unnecessary",bindings) end
          assert_raise ArgumentError,fn -> S.operator(bytes,"corpus","mcp-lexical","corpus",options,nil,Map.put(bindings,"extra","mcp__other__cas")) end
          c=S.operator(bytes,"corpus","mcp-lexical","corpus",options,nil,bindings)
          assert hd(c["extension_trust"])["state_bindings"]==[]
          many=Map.put(options,"stores",Map.new(1..8,fn n -> {"store#{n}",%{"kind"=>"mcp_cas","binding"=>"cas#{n}","partition"=>"notes","contract"=>"ipse-cas-v1"}} end))
          many=put_in(many,["retrieval","remote"],%{"kind"=>"mcp_query","binding"=>"query","partition"=>"notes","contract"=>"query-v1"})
          too_many=Map.new(1..8,fn n -> {"cas#{n}","mcp__local__cas"} end)|>Map.put("query","mcp__local__query")
          assert_raise ArgumentError,fn -> S.operator(bytes,"corpus","mcp-lexical","corpus",many,nil,too_many) end
          IO.puts(JSON.encode!(c))
          '''
      )

    assert Config.validate(Jason.decode!(json)) == :ok
  end

  test "offline research and explicit graph options match their own closed presets" do
    directory = Path.join(@root, "extensions/knowledge/options")

    isolated(
      "directory=#{inspect(directory)}\n" <>
        ~S'''
        for {package,preset,file} <- [{"research","offline","research-offline.json"},{"graph","state-explicit","graph-explicit.json"}] do
          options=S.read_json!(Path.join(directory,file),16_384)
          assert {:ok,_}=IpseKnowledge.Profiles.validate(package,preset,options)
        end
        assert_raise ArgumentError,fn -> S.selection!("corpus","invented") end
        assert_raise ArgumentError,fn -> S.selection!("arbitrary-module","offline") end
        '''
    )
  end

  test "semantic configuration requires and retains explicit host profiles and shared budget" do
    path = Path.join(@root, "extensions/knowledge/options/corpus-lexical.json")

    json =
      isolated(
        "options=S.read_json!(#{inspect(path)},16_384)\n" <>
          ~S'''
          options=put_in(options,["embedding","encoder"],%{"kind"=>"embedding","profile"=>"local-encoder"})
          options=put_in(options,["rerank","judge"],%{"kind"=>"model_complete","profile"=>"local-ranker","max_candidates"=>16,"quote_bytes"=>128})
          m=%{"id"=>"ipse-knowledge/corpus","entrypoint"=>"IpseKnowledge.Corpus",
            "capabilities"=>IpseKnowledge.Profiles.capabilities("corpus","state-semantic"),
            "options_schema"=>S.options_schema(),"exports"=>%{"commands"=>[%{"id"=>"source"}],"tools"=>[],"services"=>[]}}
          bytes=IO.iodata_to_binary(JSON.encode!(m))
          assert_raise ArgumentError,fn -> S.operator(bytes,"corpus","state-semantic","corpus",options,"knowledge",%{}) end
          inference=%{"profiles"=>%{"local-ranker"=>%{"provider"=>"ollama","model"=>"explicit-ranker","credential"=>"none","base_url"=>"http://127.0.0.1:11434","max_output_tokens"=>2048}},
            "embedding_profiles"=>%{"local-encoder"=>%{"operation"=>"embedding","provider"=>"ollama","model"=>"explicit-encoder","dimensions"=>768,"dimension_mode"=>"native","credential"=>"none","base_url"=>"http://127.0.0.1:11434"}},
            "budget"=>%{"version"=>1,"max_requests"=>10}}
          c=S.operator(bytes,"corpus","state-semantic","corpus",options,"knowledge",%{},inference)
          assert c["profiles"]==inference["profiles"] and c["embedding_profiles"]==inference["embedding_profiles"] and c["budget"]==inference["budget"]
          assert_raise ArgumentError,fn -> S.operator(bytes,"corpus","state-semantic","corpus",options,"knowledge",%{},Map.put(inference,"settings",%{})) end
          IO.puts(JSON.encode!(c))
          '''
      )

    config = Jason.decode!(json)
    assert Config.validate(config) == :ok
    assert Ipse.Profiles.validate(config["profiles"], %{}) == :ok
    assert Ipse.EmbeddingProfiles.validate(config["embedding_profiles"]) == :ok
  end
end
