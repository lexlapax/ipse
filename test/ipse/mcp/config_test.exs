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

  test "new fingerprints use canonical JSON while legacy defaults preserve the P5 fingerprint",
       ctx do
    write(ctx.path, document())
    assert {:ok, [omitted]} = Config.load(ctx.path)
    assert omitted.sandbox == :off
    assert omitted.resources == []
    assert omitted.prompts == []

    legacy = Config.fingerprint_version(omitted, 1)

    assert legacy.fingerprint ==
             "d592c37a457a6ba4d79479a434840892a61dd079915713da16994d7d544aff62"

    refute Map.has_key?(Config.manifest(legacy), :fingerprint_version)

    canonical =
      ~s(["ipse.mcp.endpoint",2,{"args":["--serve"],"command":"/bin/echo","env_names":["NOTES_TOKEN"],"id":"notes","prompts":[],"resources":[],"sandbox":"off","timeout_ms":12000,"tools":["lookup","search.v2"]}])

    assert omitted.fingerprint == Ipse.JSON.sha256(canonical)
    assert Config.manifest(omitted).fingerprint_version === 2
    refute omitted.fingerprint == legacy.fingerprint

    explicit_server =
      server()
      |> Map.put("env", %{"NOTES_TOKEN" => "hidden-value"})
      |> Map.put("sandbox", "off")
      |> Map.put("resources", [])
      |> Map.put("prompts", [])

    write(ctx.path, %{"servers" => [explicit_server]})

    assert {:ok, [explicit]} = Config.load(ctx.path)
    assert explicit.fingerprint == omitted.fingerprint
    assert Config.manifest(explicit).sandbox == :off
    assert Config.fingerprint_version(explicit, 1).fingerprint == legacy.fingerprint
  end

  test "portable public fingerprints bind every public field and ignore map insertion order",
       ctx do
    write(ctx.path, document())
    {:ok, [selected]} = Config.load(ctx.path)
    public = Config.manifest(selected) |> Jason.encode!() |> Jason.decode!()

    assert Config.public_fingerprint(Map.new(Enum.reverse(Map.to_list(public)))) ==
             selected.fingerprint

    for field <- ~w(id command args tools resources prompts sandbox env_names timeout_ms) do
      changed =
        Map.update!(public, field, fn
          value when is_list(value) -> value ++ ["different"]
          value when is_integer(value) -> value + 1
          value -> value <> "different"
        end)

      refute Config.public_fingerprint(changed) == selected.fingerprint
    end
  end

  test "resources-only and prompts-only servers get stable bounded model IDs", ctx do
    uri = "file:///notes/current"
    write(ctx.path, %{"servers" => [with_options(%{"tools" => [], "resources" => [uri]})]})
    assert {:ok, [resource_server]} = Config.load(ctx.path)
    assert resource_server.tools == []
    assert resource_server.resources == [uri]
    assert resource_server.prompts == []
    assert Config.resource_id("notes", uri) == Config.resource_id("notes", uri)
    assert byte_size(Config.resource_id("notes", uri)) <= 64
    refute Config.resource_id("notes", uri) == Config.resource_id("notes", "file:///notes/other")
    assert Config.manifest(resource_server).resources == [uri]

    write(ctx.path, %{"servers" => [with_options(%{"tools" => [], "prompts" => ["summarize"]})]})
    assert {:ok, [prompt_server]} = Config.load(ctx.path)
    assert prompt_server.tools == []
    assert prompt_server.prompts == ["summarize"]
    assert prompt_server.resources == []
    assert byte_size(Config.prompt_id("notes", "summarize")) <= 64
    assert Config.manifest(prompt_server).prompts == ["summarize"]
  end

  test "new allowlists and sandbox are strict and bounded", ctx do
    write(ctx.path, %{"servers" => [server()]})
    assert {:ok, [base]} = Config.load(ctx.path)

    invalid = [
      with_options(%{"tools" => [], "resources" => [], "prompts" => []}),
      with_options(%{"sandbox" => "auto"}),
      with_options(%{"resources" => ["relative/path"]}),
      with_options(%{"resources" => ["file:///" <> String.duplicate("x", 2_048)]}),
      with_options(%{"resources" => ["https://user:secret@example.test/data"]}),
      with_options(%{"resources" => ["file:///same", "file:///same"]}),
      with_options(%{"prompts" => ["bad prompt"]}),
      with_options(%{"prompts" => ["same", "same"]}),
      with_options(%{"tools" => List.duplicate("x", 16), "prompts" => ["one"]}),
      Map.put(server(), "resources_extra", [])
    ]

    for value <- invalid do
      write(ctx.path, %{"servers" => [value]})
      assert {:error, "MCP configuration is invalid or unreadable."} = Config.load(ctx.path)
    end

    write(ctx.path, %{"servers" => [with_options(%{"sandbox" => "native"})]})
    assert {:ok, [native]} = Config.load(ctx.path)
    assert native.sandbox == :native
    assert Config.manifest(native).sandbox == :native
    refute native.fingerprint == base.fingerprint
  end

  test "rejects environment values embedded in public identifiers and allowlists", ctx do
    invalid_servers = [
      with_options(%{"env" => %{"TOKEN" => "note"}}),
      with_options(%{"env" => %{"TOKEN" => "echo"}}),
      with_options(%{"tools" => ["search"], "env" => %{"TOKEN" => "search"}}),
      with_options(%{
        "tools" => [],
        "resources" => ["file:///notes/secret"],
        "env" => %{"TOKEN" => "secret"}
      }),
      with_options(%{"tools" => [], "prompts" => ["summary"], "env" => %{"TOKEN" => "summary"}}),
      with_options(%{"tools" => [], "prompts" => ["safe"], "env" => %{"API_TOKEN" => "TOKEN"}})
    ]

    for value <- invalid_servers do
      write(ctx.path, %{"servers" => [value]})
      assert {:error, "MCP configuration is invalid or unreadable."} = Config.load(ctx.path)
    end
  end

  test "rejects a server public manifest that overlaps another server's secret", ctx do
    secret = "foreign-private-value"
    owner = %{server() | "id" => "owner", "env" => %{"OWNER_TOKEN" => secret}}

    foreign_public_fields = [
      %{"tools" => [secret]},
      %{"tools" => [], "resources" => ["notes://workspace/#{secret}"]},
      %{"tools" => [], "prompts" => [secret]},
      %{"args" => ["--token=#{secret}"]}
    ]

    for fields <- foreign_public_fields do
      foreign = server() |> Map.put("id", "foreign") |> Map.merge(fields)
      write(ctx.path, %{"servers" => [owner, foreign]})
      assert {:error, "MCP configuration is invalid or unreadable."} = Config.load(ctx.path)
    end
  end

  test "keeps child environments server-specific while redacting all configured secrets", ctx do
    first = %{server() | "id" => "first", "env" => %{"FIRST_TOKEN" => "first-private"}}
    second = %{server() | "id" => "second", "env" => %{"SECOND_TOKEN" => "second-private"}}
    write(ctx.path, %{"servers" => [first, second]})

    assert {:ok, [one, two]} = Config.load(ctx.path)
    assert one.env == %{"FIRST_TOKEN" => "first-private"}
    assert two.env == %{"SECOND_TOKEN" => "second-private"}
    assert one.redactions == ["second-private", "first-private"]
    assert two.redactions == one.redactions

    for current <- [one, two] do
      manifest = Config.manifest(current)
      refute inspect(manifest) =~ "first-private"
      refute inspect(manifest) =~ "second-private"

      assert Config.redact("first-private second-private", current) ==
               "[redacted] [redacted]"
    end
  end

  test "legacy server maps get defaults and synthetic IDs fit provider bounds" do
    legacy = %{
      id: "notes",
      command: "/bin/echo",
      args: [],
      tools: ["lookup"],
      env: %{},
      timeout_ms: 1,
      fingerprint: String.duplicate("a", 64)
    }

    manifest = Config.manifest(legacy)
    assert manifest.resources == []
    assert manifest.prompts == []
    assert manifest.sandbox == :off

    longest_id = "a" <> String.duplicate("a", 23)
    longest_tool = String.duplicate("x", 32)
    assert byte_size(Config.tool_id(longest_id, longest_tool)) <= 64
    assert byte_size(Config.resource_id(longest_id, "file:///resource")) <= 64
    assert byte_size(Config.prompt_id(longest_id, "prompt")) <= 64
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

  defp with_options(options), do: Map.merge(server(), options)

  defp write(path, value), do: File.write!(path, Jason.encode!(value))
end
