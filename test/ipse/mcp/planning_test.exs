defmodule Ipse.MCP.PlanningTest do
  use ExUnit.Case, async: true
  alias Ipse.MCP.{Config, Planning}

  test "operator data matches only the exact discovered tool and selected endpoint" do
    path = Path.join(System.tmp_dir!(), "ipse-planning-mcp-" <> Ipse.Usage.id())
    on_exit(fn -> File.rm(path) end)

    server = %{
      "id" => "notes",
      "transport" => "http",
      "url" => "http://127.0.0.1:3456/mcp",
      "allow_insecure_loopback" => true,
      "tools" => ["lookup"]
    }

    File.write!(path, Jason.encode!(%{"servers" => [server]}))
    assert {:ok, [selected]} = Config.load(path)
    digest = Ipse.JSON.sha256("descriptor")
    tool_id = Config.tool_id(selected.id, "lookup")
    descriptor = %{server: selected, name: "lookup", tool_id: tool_id, digest: digest}

    entry = %{
      "version" => 1,
      "server_id" => "notes",
      "tool" => "lookup",
      "endpoint_sha256" => selected.fingerprint,
      "descriptor_sha256" => digest
    }

    reads = %{tool_id => entry}
    assert :ok = Planning.validate(reads)
    assert Planning.declared?(descriptor, reads)
    refute Planning.declared?(descriptor, %{})
    refute Planning.declared?(%{descriptor | digest: Ipse.JSON.sha256("changed")}, reads)
    refute Planning.declared?(Map.put(descriptor, :kind, :resource), reads)

    refute Planning.declared?(
             %{descriptor | server: Config.fingerprint_version(selected, 1)},
             reads
           )

    refute Planning.declared?(
             %{descriptor | server: %{selected | url: "http://127.0.0.1:3457/mcp"}},
             reads
           )

    File.write!(
      path,
      Jason.encode!(%{"servers" => [Map.put(server, "url", "http://127.0.0.1:3457/mcp")]})
    )

    assert {:ok, [changed]} = Config.load(path)
    refute Planning.declared?(%{descriptor | server: changed}, reads)

    for invalid <- [
          %{tool_id => Map.put(entry, "descriptor_sha256", "bad")},
          %{tool_id => Map.put(entry, "endpoint_sha256", "bad")},
          %{tool_id => Map.put(entry, "extra", true)},
          %{"mcp__notes__other" => entry}
        ] do
      assert {:error, :invalid_planning_mcp_reads} = Planning.validate(invalid)
    end
  end

  test "runtime and saved configuration must carry the same complete declaration" do
    entry = %{
      "version" => 1,
      "server_id" => "notes",
      "tool" => "lookup",
      "endpoint_sha256" => Ipse.JSON.sha256("endpoint"),
      "descriptor_sha256" => Ipse.JSON.sha256("descriptor")
    }

    reads = %{"mcp__notes__lookup" => entry}

    config = %{
      planning_mcp_reads: reads,
      configuration: %{fingerprint: "unchanged", planning_mcp_reads: reads}
    }

    assert :ok = Planning.runtime_configuration(config)

    assert Planning.saved_configuration?(
             %{"fingerprint" => "unchanged", "planning_mcp_reads" => reads},
             config
           )

    refute Planning.saved_configuration?(%{"fingerprint" => "unchanged"}, config)

    refute Planning.saved_configuration?(
             %{"fingerprint" => "unchanged", "planning_mcp_reads" => nil},
             config
           )

    refute Planning.saved_configuration?(
             %{"fingerprint" => "unchanged", "planning_mcp_reads" => %{}},
             config
           )

    assert {:error, :invalid_planning_mcp_configuration} =
             Planning.runtime_configuration(%{config | configuration: nil})

    assert :ok = Planning.runtime_configuration(%{})
    assert Planning.saved_configuration?(nil, %{})
  end
end
