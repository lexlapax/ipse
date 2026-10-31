defmodule Ipse.MCP.ManagedRequestTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, MCP}

  test "actual tool name survives noninjective model-name normalization" do
    descriptor = descriptor(:tool, "notes.search", schema("query"))
    args = %{"query" => "retained source"}
    request = rpc("tools/call", %{"name" => "notes.search", "arguments" => args})
    assert MCP.managed_request?(descriptor, args, request)
    assert MCP.managed_request?(historical(descriptor), args, request)

    refute MCP.managed_request?(
             descriptor,
             args,
             put_in(request, ["params", "name"], "notes_search")
           )

    refute MCP.managed_request?(
             descriptor,
             args,
             put_in(request, ["params", "arguments", "query"], "changed")
           )

    refute MCP.managed_request?(descriptor, %{"query" => 1}, request)
  end

  test "resource and prompt requests bind their actual configured targets" do
    resource = descriptor(:resource, "notes://current", schema(nil))
    read = rpc("resources/read", %{"uri" => "notes://current"})
    assert MCP.managed_request?(resource, %{}, read)
    assert MCP.managed_request?(historical(resource), %{}, read)
    refute MCP.managed_request?(resource, %{"uri" => "notes://other"}, read)
    refute MCP.managed_request?(resource, %{}, put_in(read, ["params", "uri"], "notes://other"))

    prompt = descriptor(:prompt, "compose", schema("query"))
    args = %{"query" => "summarize"}
    get = rpc("prompts/get", %{"name" => "compose", "arguments" => args})
    assert MCP.managed_request?(prompt, args, get)
    assert MCP.managed_request?(historical(prompt), args, get)
    refute MCP.managed_request?(prompt, args, Map.put(get, "method", "tools/call"))
  end

  test "empty arguments follow the existing SDK's exact omitted-field encoding" do
    for {kind, method} <- [{:tool, "tools/call"}, {:prompt, "prompts/get"}] do
      descriptor = descriptor(kind, "empty", schema(nil))
      request = rpc(method, %{"name" => "empty"})
      assert MCP.managed_request?(descriptor, %{}, request)
      refute MCP.managed_request?(descriptor, %{}, put_in(request, ["params", "arguments"], %{}))
    end
  end

  test "extra routing fields, malformed RPC identity, foreign metadata and oversized bodies refuse" do
    descriptor = descriptor(:tool, "read", schema("query"))
    args = %{"query" => "test"}
    request = rpc("tools/call", %{"name" => "read", "arguments" => args})

    for changed <- [
          Map.put(request, "id", nil),
          Map.put(request, "id", -1),
          Map.put(request, "id", String.duplicate("x", 129)),
          Map.put(request, "jsonrpc", "1.0"),
          Map.put(request, "result", %{}),
          Map.put(request, "method", "prompts/get"),
          put_in(request, ["params", "_meta"], %{"other" => true})
        ] do
      refute MCP.managed_request?(descriptor, args, changed)
    end

    manifest = historical(descriptor)
    refute MCP.managed_request?(Map.put(manifest, "unexpected", true), args, request)
    refute MCP.managed_request?(Map.put(manifest, "descriptor_sha256", "bad"), args, request)
    refute MCP.managed_request?(Map.put(manifest, "risk", "read_only"), args, request)
    big = %{"query" => String.duplicate("a", 33_000)}

    refute MCP.managed_request?(
             manifest,
             big,
             rpc("tools/call", %{"name" => "read", "arguments" => big})
           )
  end

  defp schema(nil),
    do: %{"type" => "object", "properties" => %{}, "additionalProperties" => false}

  defp schema(field),
    do: %{
      "type" => "object",
      "properties" => %{field => %{"type" => "string"}},
      "required" => [field],
      "additionalProperties" => false
    }

  defp rpc(method, params),
    do: %{"jsonrpc" => "2.0", "id" => 7, "method" => method, "params" => params}

  defp historical(descriptor),
    do: descriptor |> MCP.manifest() |> Jason.encode!() |> Jason.decode!()

  defp descriptor(kind, target, schema) do
    server = %{
      id: "managed",
      fingerprint: JSON.sha256("configured MCP endpoint"),
      transport: :http,
      env: %{},
      redactions: [],
      sandbox: :off
    }

    descriptor = %{
      schema_version: 1,
      name: target,
      server: server,
      input_schema: schema,
      description: "Fixture",
      digest: JSON.digest([kind, target, schema])
    }

    case kind do
      :tool ->
        Map.put(descriptor, :tool_id, MCP.Config.tool_id(server.id, target))

      :resource ->
        Map.merge(descriptor, %{
          kind: kind,
          source: target,
          tool_id: MCP.Config.resource_id(server.id, target)
        })

      :prompt ->
        Map.merge(descriptor, %{
          kind: kind,
          source: target,
          tool_id: MCP.Config.prompt_id(server.id, target)
        })
    end
  end
end
