defmodule Ipse.MCP.ConfigTest do
  use ExUnit.Case, async: true

  alias Ipse.MCP.Config

  setup do
    path =
      Path.join(System.tmp_dir!(), "ipse-mcp-config-#{System.unique_integer([:positive])}.json")

    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  test "nil disables MCP and a valid explicit file yields a redacted manifest", ctx do
    assert {:ok, []} = Config.load(nil)
    write(ctx.path, document())

    assert {:ok, [server]} = Config.load(ctx.path)
    assert server.id == "notes"
    assert server.command == "/bin/echo"
    assert server.args == ["--serve"]
    assert server.tools == ["lookup", "search.v2"]
    assert Config.tool_id(server.id, "search.v2") == "mcp__notes__search_v2"
    assert server.env == %{"NOTES_TOKEN" => "hidden-value"}
    assert server.timeout_ms == 12_000
    assert byte_size(server.fingerprint) == 64

    manifest = Config.manifest(server)
    refute inspect(manifest) =~ "hidden-value"
    assert manifest.env_names == ["NOTES_TOKEN"]
    assert Config.redact("value=hidden-value", server) == "value=[redacted]"
    secret_arg = %{server | args: ["--token=hidden-value"]}
    assert Config.manifest(secret_arg).args == ["--token=[redacted]"]
  end

  test "rejects unknown keys, bad schemas, duplicate identifiers, and tool name overflow", ctx do
    invalid = [
      %{
        "servers" => [
          %{"id" => "notes", "command" => "/bin/echo", "tools" => ["x"], "extra" => true}
        ]
      },
      %{"servers" => [%{"id" => "Notes", "command" => "/bin/echo", "tools" => ["x"]}]},
      %{
        "servers" => [
          %{"id" => "notes", "command" => "/bin/echo", "tools" => [String.duplicate("x", 33)]}
        ]
      },
      %{"servers" => [server(), server()]},
      %{"servers" => [%{server() | "tools" => ["search.v2", "search_v2"]}]},
      %{
        "servers" => [
          %{server() | "id" => "a", "tools" => ["b__c"]},
          %{server() | "id" => "a__b", "tools" => ["c"]}
        ]
      }
    ]

    for value <- invalid do
      write(ctx.path, value)
      assert {:error, "MCP configuration is invalid or unreadable."} = Config.load(ctx.path)
    end
  end

  test "rejects credential environment names, inherited secrets are never accepted", ctx do
    for key <- ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "IPSE_CHATGPT_ACCESS_TOKEN"] do
      write(ctx.path, %{"servers" => [%{server() | "env" => %{key => "secret"}}]})
      assert {:error, _} = Config.load(ctx.path)
    end
  end

  test "enforces executable, argument, environment, and timeout bounds", ctx do
    bad_servers = [
      %{server() | "command" => "echo"},
      %{server() | "command" => "/etc/passwd"},
      %{server() | "args" => List.duplicate("x", 17)},
      %{server() | "env" => %{"BAD-name" => "x"}},
      %{server() | "timeout_ms" => 0},
      %{server() | "timeout_ms" => 120_001}
    ]

    for value <- bad_servers do
      write(ctx.path, %{"servers" => [value]})
      assert {:error, _} = Config.load(ctx.path)
    end
  end

  test "rejects symlinked and oversized config files", ctx do
    target = ctx.path <> ".target"
    File.write!(target, Jason.encode!(document()))
    File.ln_s!(target, ctx.path)
    assert {:error, _} = Config.load(ctx.path)
    File.rm!(ctx.path)
    File.write!(ctx.path, :binary.copy("x", 65_537))
    assert {:error, _} = Config.load(ctx.path)
    File.rm(target)
  end

  test "top-level and per-server counts are bounded", ctx do
    write(ctx.path, %{"servers" => List.duplicate(server(), 5)})
    assert {:error, _} = Config.load(ctx.path)

    write(ctx.path, %{"servers" => [Map.put(server(), "tools", List.duplicate("x", 17))]})
    assert {:error, _} = Config.load(ctx.path)
  end

  test "private JSON string values are detected before encoding and excluded from persistent fingerprints",
       ctx do
    for secret <- ["line\nsecret", "quoted\"secret", "slash\\secret"] do
      write(ctx.path, %{"servers" => [%{server() | "env" => %{"TOKEN" => secret}}]})
      assert {:ok, [selected]} = Config.load(ctx.path)
      assert Config.contains_private?(%{"nested" => [%{"title" => secret}]}, selected)
      descriptor = %{input_schema: %{"type" => "object"}, server: selected}
      assert {:error, _} = Ipse.MCP.validate_call(descriptor, %{"content" => secret})

      write(ctx.path, %{"servers" => [%{server() | "env" => %{"TOKEN" => "rotated"}}]})
      assert {:ok, [rotated]} = Config.load(ctx.path)
      assert selected.fingerprint == rotated.fingerprint
    end
  end

  defp document, do: %{"servers" => [%{server() | "env" => %{"NOTES_TOKEN" => "hidden-value"}}]}

  defp server do
    %{
      "id" => "notes",
      "command" => "/bin/echo",
      "args" => ["--serve"],
      "tools" => ["lookup", "search.v2"],
      "env" => %{},
      "timeout_ms" => 12_000
    }
  end

  defp write(path, value), do: File.write!(path, Jason.encode!(value))
end
