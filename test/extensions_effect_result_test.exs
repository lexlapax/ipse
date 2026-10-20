defmodule Ipse.Extensions.EffectResultTest do
  use ExUnit.Case, async: true
  alias Ipse.Extensions.{EffectResult, MCPCall}
  alias Ipse.MCP.Config

  test "MCP record capacity uses the attainable escaped source ceiling" do
    {intent, _} = intent()
    intent = Map.merge(intent, %{"step" => 1, "context_sha256" => nil, "service" => nil})
    assert {:ok, capacity} = Ipse.Extensions.EffectCapacity.mcp(intent)
    assert capacity.max_record_bytes == EffectResult.source_record_limit()

    {:ok, empty} = EffectResult.source(intent, "mcp.text", %{"text" => ""})
    target = capacity.max_record_bytes - byte_size(Jason.encode!(empty))
    controls = div(target - 65_536 + 4, 5)
    text = String.duplicate(<<0>>, controls) <> String.duplicate("x", target - controls * 6)
    assert byte_size(text) <= 65_536
    assert {:ok, source} = EffectResult.source(intent, "mcp.text", %{"text" => text})
    assert byte_size(Jason.encode!(source)) == capacity.max_record_bytes

    assert {:error, _} =
             Ipse.Journal.Limits.encode(source, %{
               "max_record_bytes" => capacity.max_record_bytes - 1
             })

    assert {:ok, _} =
             Ipse.Journal.Limits.encode(source, %{"max_record_bytes" => capacity.max_record_bytes})
  end

  test "complete source is private while its public descriptor stays within SDK bounds" do
    {intent, _server} = intent()
    text = String.duplicate("é🙂\n", 5000)
    assert byte_size(text) > 8192
    assert {:ok, source} = EffectResult.source(intent, "mcp.text", %{"text" => text})
    assert EffectResult.valid_source?(source, intent)
    descriptor = EffectResult.descriptor(source)
    assert descriptor["byte_count"] == byte_size(text)
    assert EffectResult.descriptor?(descriptor, intent["operation_id"])
    assert Ipse.Extension.validate(descriptor) == :ok
    refute Map.has_key?(descriptor, "text")
    refute Map.has_key?(descriptor, "data")
    refute Map.has_key?(descriptor, "identity_sha256")
    assert {:error, _} = Ipse.Extension.validate(source)
    assert MCPCall.valid_outcome?(intent["request"], "ok", descriptor, intent["operation_id"])
  end

  test "source creation requires approved MCP authority and exact contextual digests" do
    {intent, _} = intent()
    assert {:ok, source} = EffectResult.source(intent, "mcp.text", %{"text" => "answer"})

    changes = [
      {"approval", "denied"},
      {"approval", "not_required"},
      {"version", 1},
      {"namespace", id("a")},
      {"parent_invocation_id", id("b")},
      {"operation_id", id("c")},
      {"identity_sha256", digest("other identity")},
      {"request_sha256", digest("other request")},
      {"effect_binding", put_in(intent["effect_binding"], ["alias"], "other")}
    ]

    for {key, value} <- changes do
      refute EffectResult.valid_source?(source, Map.put(intent, key, value)), key
    end

    for approval <- ~w(denied not_required unknown),
        do:
          assert(
            {:error, _} =
              EffectResult.source(Map.put(intent, "approval", approval), "mcp.text", %{
                "text" => "answer"
              })
          )

    assert {:error, _} = EffectResult.source(intent, "arbitrary", %{"text" => "answer"})

    assert {:error, _} =
             EffectResult.source(intent, "mcp.text", %{"text" => "answer", "private" => "extra"})
  end

  test "source text and whole event have independent bounds" do
    {intent, _} = intent()

    assert {:ok, _} =
             EffectResult.source(intent, "mcp.text", %{"text" => String.duplicate("a", 65_536)})

    assert {:error, _} =
             EffectResult.source(intent, "mcp.text", %{"text" => String.duplicate("a", 65_537)})

    assert {:error, _} = EffectResult.source(intent, "mcp.text", %{"text" => <<255>>})

    assert {:error, _} =
             EffectResult.source(intent, "mcp.text", %{"text" => String.duplicate(<<0>>, 65_536)})
  end

  test "recomputed source hash cannot hide data or action binding tampering" do
    {intent, _} = intent()
    assert {:ok, source} = EffectResult.source(intent, "mcp.text", %{"text" => "original"})
    changed = put_in(source, ["data", "text"], "changed")
    refute EffectResult.valid_source?(changed, intent)
    changed = Map.put(changed, "source_sha256", digest(Map.delete(changed, "source_sha256")))
    refute EffectResult.valid_source?(changed, intent)
    changed = source |> Map.put("binding_sha256", digest("different binding")) |> rehash_source()
    refute EffectResult.valid_source?(changed, intent)
    changed = source |> Map.put("extra", "unrecognized") |> rehash_source()
    refute EffectResult.valid_source?(changed, intent)

    changed =
      source |> Map.put("identity_sha256", digest("different identity")) |> rehash_source()

    refute EffectResult.valid_source?(changed, intent)
  end

  test "UTF-8 byte windows reconstruct all of a complete source beyond ordinary result bounds" do
    {intent, _} = intent()
    text = String.duplicate("aé🙂", 2000)
    {:ok, source} = EffectResult.source(intent, "mcp.text", %{"text" => text})
    chunks = read_all(source, 0, [])
    assert Enum.join(chunks) == text
    assert length(chunks) > 16
    assert Enum.all?(chunks, &(String.valid?(&1) and byte_size(&1) <= 257))

    request = read_request(source, byte_size(text), 4)

    assert {:ok, %{"complete" => true, "next" => nil, "text" => ""}} =
             EffectResult.read(source, request)

    assert {:ok, empty} = EffectResult.source(intent, "mcp.text", %{"text" => ""})

    assert {:ok, %{"complete" => true, "text" => ""}} =
             EffectResult.read(empty, read_request(empty, 0, 1))
  end

  test "reader rejects codepoint interiors, nonadvancing limits and source substitution" do
    {intent, _} = intent()
    {:ok, source} = EffectResult.source(intent, "mcp.text", %{"text" => "é🙂end"})
    refused = {:failed, %{"code" => "result_refused"}}

    for offset <- [1, 3, 4, 5, 10],
        do: assert(EffectResult.read(source, read_request(source, offset, 4)) == refused)

    assert EffectResult.read(source, read_request(source, 0, 1)) == refused
    assert EffectResult.read(source, read_request(source, 2, 3)) == refused

    assert {:ok, %{"offset" => 0, "next" => 2, "text" => "é", "complete" => false}} =
             EffectResult.read(source, read_request(source, 0, 3))

    for request <- [
          Map.put(read_request(source, 0, 4), "source_sha256", digest("other source")),
          Map.put(read_request(source, 0, 4), "operation_id", id("b")),
          Map.put(read_request(source, 0, 4), "offset", 1.0),
          Map.put(read_request(source, 0, 4), "limit", 0),
          Map.put(read_request(source, 0, 4), "limit", 4097),
          Map.put(read_request(source, 0, 4), "extra", true)
        ],
        do: assert(EffectResult.read(source, request) == refused)

    assert EffectResult.read(
             put_in(source, ["data", "text"], "replacement"),
             read_request(source, 0, 4)
           ) == refused
  end

  test "syntactic window validation is followed by exact source recomputation" do
    {intent, _} = intent()
    {:ok, source} = EffectResult.source(intent, "mcp.text", %{"text" => "first second"})
    request = read_request(source, 0, 5)
    {:ok, value} = EffectResult.read(source, request)
    outcome = %{"status" => "ok", "value" => value}
    assert EffectResult.valid_outcome?(request, "ok", value, id("a"))
    assert EffectResult.bound_outcome?(source, request, outcome)

    for changed <- [
          %{value | "text" => "other"},
          %{value | "next" => nil, "complete" => true}
        ] do
      assert EffectResult.valid_outcome?(request, "ok", changed, id("a"))
      refute EffectResult.bound_outcome?(source, request, %{outcome | "value" => changed})
    end

    for changed <- [
          %{value | "offset" => 1},
          %{value | "next" => 6},
          %{value | "text" => <<255>>},
          Map.put(value, "extra", true)
        ],
        do: refute(EffectResult.valid_outcome?(request, "ok", changed, id("a")))

    assert EffectResult.binding(request) ==
             Map.take(source, ~w(operation_id source_sha256))
             |> Map.merge(%{"kind" => "result", "version" => 1})

    assert EffectResult.valid_outcome?(request, "unknown", %{}, id("a"))
    refute EffectResult.valid_outcome?(request, "unknown", %{"text" => "not empty"}, id("a"))
  end

  test "MCP request and trust bindings are closed and preserve current SDK limits" do
    {intent, _} = intent()
    request = intent["request"]
    assert MCPCall.validate(request) == :ok

    for changed <- [
          Map.put(request, "version", 1.0),
          Map.put(request, "binding", "Invalid"),
          Map.put(request, "arguments", []),
          Map.put(request, "arguments", %{"text" => String.duplicate("a", 8193)}),
          Map.put(request, "timeout_ms", 30_001),
          Map.put(request, "extra", nil)
        ],
        do: assert({:error, _} = MCPCall.validate(changed))

    entry = %{"instance" => "reader", "alias" => "fetch", "tool" => "mcp__fixture__fetch"}
    assert MCPCall.trust_bindings?([entry])
    refute MCPCall.trust_bindings?([entry, entry])
    refute MCPCall.trust_bindings?([Map.put(entry, "endpoint", "https://example.invalid")])
    refute MCPCall.trust_bindings?(List.duplicate(entry, 65))
    public = Map.delete(entry, "instance")
    assert MCPCall.public_bindings?([public])
    refute MCPCall.public_bindings?([public, public])
    refute MCPCall.public_bindings?([Map.put(public, "credential", "not allowed")])
    assert MCPCall.bindings(%{"mcp_bindings" => [entry]}, "reader") == [public]
    assert MCPCall.bindings(%{"mcp_bindings" => [entry]}, "other") == []
    assert MCPCall.bindings(nil, "reader") == []
  end

  test "MCP target selection is pure and refuses child, project and mismatched authority" do
    {intent, server} = intent()
    identity = identity(intent)
    config = %{mcp_servers: [server]}

    assert {:ok, ^server, "mcp__fixture__fetch"} =
             MCPCall.target(config, identity, intent["request"])

    for changed <- [
          Map.put(config, :parallel_child, true),
          Map.put(config, :delegation_origin, %{}),
          %{mcp_servers: []},
          %{mcp_servers: [server, server]}
        ],
        do: assert({:error, _} = MCPCall.target(changed, identity, intent["request"]))

    for changed <- [
          Map.put(identity, "scope", "project"),
          Map.put(identity, "capabilities", ["host.actions"]),
          Map.put(identity, "mcp_bindings", []),
          put_in(identity, ["mcp_bindings", Access.at(0), "tool"], "mcp__other__fetch")
        ],
        do: assert({:error, _} = MCPCall.target(config, changed, intent["request"]))
  end

  test "public MCP binding links schema, selected tool, server fingerprint and metadata" do
    {intent, server} = intent()
    request = intent["request"]
    identity = identity(intent)
    binding = intent["effect_binding"]
    metadata = %{"mcp_servers" => [server.fingerprint]}
    assert MCPCall.valid_binding?(binding, request, identity, metadata)
    refute MCPCall.valid_binding?(binding, request, identity, %{"mcp_servers" => []})

    refute MCPCall.valid_binding?(
             binding,
             %{request | "arguments" => %{"query" => 1}},
             identity,
             metadata
           )

    for changed <- [
          Map.put(binding, "extra", true),
          Map.put(binding, "alias", "other"),
          put_in(binding, ["manifest", "tool_id"], "mcp__other__fetch"),
          put_in(
            binding,
            ["manifest", "origin", "configured_endpoint_fingerprint"],
            digest("other")
          ),
          put_in(binding, ["server", "timeout_ms"], 1),
          put_in(binding, ["server", "env"], %{"SECRET" => "private"}),
          put_in(binding, ["schema", "additionalProperties"], %{"type" => "string"})
        ],
        do: refute(MCPCall.valid_binding?(changed, request, identity, metadata))
  end

  test "operator manifests redact private values without copying credentials into bindings" do
    server =
      server(%{
        "args" => ["--token=private-fixture-secret"],
        "env" => %{"FIXTURE_SECRET" => "private-fixture-secret"}
      })

    descriptor = descriptor(server)
    binding = MCPCall.binding(descriptor, "fetch")
    encoded = Jason.encode!(binding)
    refute encoded =~ "private-fixture-secret"
    assert encoded =~ "[redacted]"
    assert binding["server"]["env_names"] == ["FIXTURE_SECRET"]
    request = request()

    identity = %{
      "scope" => "operator",
      "capabilities" => ~w(host.actions host.mcp),
      "mcp_bindings" => [%{"alias" => "fetch", "tool" => descriptor.tool_id}]
    }

    assert MCPCall.valid_binding?(binding, request, identity, %{
             "mcp_servers" => [server.fingerprint]
           })

    refute MCPCall.valid_binding?(
             put_in(binding, ["server", "timeout_ms"], 1),
             request,
             identity,
             %{
               "mcp_servers" => [server.fingerprint]
             }
           )
  end

  test "HTTP public binding rejects endpoint drift without performing network IO" do
    server =
      load_servers([
        %{
          "id" => "remote",
          "transport" => "http",
          "url" => "http://127.0.0.1:9876/mcp",
          "allow_insecure_loopback" => true,
          "tools" => ["fetch"]
        }
      ])
      |> hd()

    descriptor = descriptor(server)
    binding = MCPCall.binding(descriptor, "fetch")

    identity = %{
      "scope" => "operator",
      "capabilities" => ~w(host.actions host.mcp),
      "mcp_bindings" => [%{"alias" => "fetch", "tool" => descriptor.tool_id}]
    }

    metadata = %{"mcp_servers" => [server.fingerprint]}
    assert MCPCall.valid_binding?(binding, request(), identity, metadata)
    changed = put_in(binding, ["server", "endpoint"], "http://127.0.0.1:9877/mcp")
    refute MCPCall.valid_binding?(changed, request(), identity, metadata)
    changed = put_in(binding, ["server", "allow_insecure_loopback"], false)
    refute MCPCall.valid_binding?(changed, request(), identity, metadata)
  end

  test "resource and prompt bindings retain configured sources rather than worker destinations" do
    server =
      server(%{
        "id" => String.duplicate("a", 24),
        "resources" => ["ipse://fixture/doc"],
        "prompts" => ["fetch-note"]
      })

    for {kind, source, tool_id} <- [
          {:resource, "ipse://fixture/doc", Config.resource_id(server.id, "ipse://fixture/doc")},
          {:prompt, "fetch-note", Config.prompt_id(server.id, "fetch-note")}
        ] do
      descriptor =
        %{
          descriptor(server)
          | name: source,
            tool_id: tool_id,
            input_schema: %{
              "type" => "object",
              "properties" => %{},
              "additionalProperties" => false
            }
        }
        |> Map.merge(%{kind: kind, source: source})

      request = %{request() | "arguments" => %{}}
      binding = MCPCall.binding(descriptor, "fetch")

      identity = %{
        "scope" => "operator",
        "capabilities" => ~w(host.actions host.mcp),
        "mcp_bindings" => [%{"alias" => "fetch", "tool" => tool_id}]
      }

      assert byte_size(tool_id) == 64
      assert MCPCall.public_bindings?(identity["mcp_bindings"])

      assert {:ok, ^server, ^tool_id} =
               MCPCall.target(%{mcp_servers: [server]}, identity, request)

      assert MCPCall.valid_binding?(binding, request, identity, %{
               "mcp_servers" => [server.fingerprint]
             })

      refute MCPCall.valid_binding?(
               put_in(binding, ["manifest", "source"], "other"),
               request,
               identity
             )
    end
  end

  test "configuration rejects cross-server secrets in another server public arguments" do
    path =
      Path.join(
        System.tmp_dir!(),
        "ipse-effect-cross-secret-#{System.unique_integer([:positive])}.json"
      )

    document = %{
      "servers" => [
        %{
          "id" => "fixture",
          "command" => System.find_executable("elixir"),
          "args" => ["cross-server-secret"],
          "tools" => ["fetch"]
        },
        %{
          "id" => "other",
          "command" => System.find_executable("elixir"),
          "tools" => ["fetch"],
          "env" => %{"FIXTURE_OTHER" => "cross-server-secret"}
        }
      ]
    }

    File.write!(path, Jason.encode!(document))

    try do
      assert {:error, "MCP configuration is invalid or unreadable."} = Config.load(path)
    after
      File.rm!(path)
    end
  end

  test "pure validators refuse malformed boundary values without raising" do
    {intent, _} = intent()

    for value <- [nil, [], 1, "text", %{atom: :private}, %{}] do
      assert {:error, _} = MCPCall.validate(value)

      if value == [] do
        assert MCPCall.trust_bindings?(value)
        assert MCPCall.public_bindings?(value)
      else
        refute MCPCall.trust_bindings?(value)
        refute MCPCall.public_bindings?(value)
      end

      refute MCPCall.valid_binding?(value, intent["request"], identity(intent))
      assert {:error, _} = EffectResult.validate(value)
      refute EffectResult.valid_source?(value, intent)
      refute EffectResult.descriptor?(value, intent["operation_id"])
      assert {:failed, %{"code" => "result_refused"}} = EffectResult.read(value, %{})
      refute EffectResult.bound_outcome?(value, %{}, %{})
    end
  end

  defp read_all(source, offset, acc) do
    request = read_request(source, offset, 257)
    {:ok, value} = EffectResult.read(source, request)
    assert EffectResult.valid_outcome?(request, "ok", value, id("e"))
    assert EffectResult.bound_outcome?(source, request, %{"status" => "ok", "value" => value})

    if value["complete"],
      do: Enum.reverse([value["text"] | acc]),
      else: read_all(source, value["next"], [value["text"] | acc])
  end

  defp read_request(source, offset, limit),
    do: %{
      "op" => "effect.result.read",
      "version" => 1,
      "operation_id" => source["operation_id"],
      "source_sha256" => source["source_sha256"],
      "offset" => offset,
      "limit" => limit
    }

  defp request,
    do: %{
      "op" => "mcp.call",
      "version" => 1,
      "binding" => "fetch",
      "arguments" => %{"query" => "question"},
      "timeout_ms" => 1000
    }

  defp intent do
    server = server()
    binding = MCPCall.binding(descriptor(server), "fetch")
    request = request()

    {%{
       "type" => "extension_action_intent",
       "version" => 2,
       "parent_invocation_id" => id("1"),
       "operation_id" => id("2"),
       "identity_sha256" => digest("identity"),
       "request_sha256" => digest(request),
       "request" => request,
       "effect_binding" => binding,
       "namespace" => nil,
       "approval" => "approved"
     }, server}
  end

  defp identity(intent),
    do: %{
      "scope" => "operator",
      "capabilities" => ~w(host.actions host.mcp),
      "mcp_bindings" => [
        %{"alias" => "fetch", "tool" => intent["effect_binding"]["manifest"]["tool_id"]}
      ]
    }

  defp server(extra \\ %{}) do
    [
      %{"id" => "fixture", "command" => System.find_executable("elixir"), "tools" => ["fetch"]}
      |> Map.merge(extra)
    ]
    |> load_servers()
    |> hd()
  end

  defp load_servers(entries) do
    path =
      Path.join(
        System.tmp_dir!(),
        "ipse-effect-config-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, Jason.encode!(%{"servers" => entries}))

    try do
      {:ok, servers} = Config.load(path)
      servers
    after
      File.rm!(path)
    end
  end

  defp descriptor(server),
    do: %{
      schema_version: 1,
      server: server,
      name: "fetch",
      tool_id: Config.tool_id(server.id, "fetch"),
      input_schema: %{
        "type" => "object",
        "properties" => %{"query" => %{"type" => "string"}},
        "required" => ["query"],
        "additionalProperties" => false
      },
      description: "Synthetic fetch tool",
      digest: digest("descriptor")
    }

  defp id(char), do: String.duplicate(char, 32)
  defp digest(value), do: Ipse.Compaction.digest([value])

  defp rehash_source(source),
    do: Map.put(source, "source_sha256", digest(Map.delete(source, "source_sha256")))
end
