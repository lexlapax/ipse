#!/usr/bin/env elixir

scenario = List.first(System.argv()) || "normal"
secret = System.get_env("FIXTURE_SECRET")
log = fn event -> File.write!("catalog.log", Jason.encode!(event) <> "\n", [:append]) end
write = fn message -> IO.binwrite(:stdio, Jason.encode!(message) <> "\n") end

resource = fn drift ->
  %{
    "uri" => "notes://guide",
    "name" => if(drift, do: "Guide changed", else: "Guide"),
    "description" => if(drift, do: "changed", else: "Read the local guide."),
    "mimeType" => "text/plain"
  }
end

prompt = fn ->
  %{
    "name" => "summarize",
    "description" => "Summarize supplied text.",
    "arguments" => [
      %{"name" => "topic", "description" => "Topic to summarize", "required" => true},
      %{"name" => "tone", "description" => "Optional tone", "required" => false}
    ]
  }
end

loop = fn loop, changed ->
  case IO.read(:stdio, :line) do
    line when is_binary(line) ->
      case Jason.decode(line) do
        {:ok, %{"id" => id, "method" => "initialize"}} ->
          capabilities =
            case scenario do
              "resources_only" -> %{"resources" => %{}}
              "prompts_only" -> %{"prompts" => %{}}
              _ -> %{"tools" => %{}, "resources" => %{}, "prompts" => %{}}
            end

          write.(%{
            "jsonrpc" => "2.0",
            "id" => id,
            "result" => %{
              "protocolVersion" => "2025-11-25",
              "capabilities" => capabilities,
              "serverInfo" => %{"name" => "ipse-catalog-fixture", "version" => "1"}
            }
          })

          loop.(loop, changed)

        {:ok, %{"method" => "notifications/initialized"}} ->
          loop.(loop, changed)

        {:ok, %{"id" => id, "method" => "tools/list"}} ->
          log.(%{"event" => "list_tools"})
          write.(%{"jsonrpc" => "2.0", "id" => id, "result" => %{"tools" => []}})
          loop.(loop, changed)

        {:ok, %{"id" => id, "method" => "resources/list", "params" => params}} ->
          drift_now = scenario == "metadata_drift" and File.exists?("catalog-force-drift")

          log.(%{"event" => "list_resources", "cursor" => params["cursor"]})

          result =
            if params["cursor"] == nil,
              do: %{
                "resources" => [resource.(changed or drift_now)],
                "nextCursor" => "resource-page-2"
              },
              else: %{"resources" => []}

          write.(%{"jsonrpc" => "2.0", "id" => id, "result" => result})
          loop.(loop, changed)

        {:ok, %{"id" => id, "method" => "prompts/list"}} ->
          log.(%{"event" => "list_prompts"})
          write.(%{"jsonrpc" => "2.0", "id" => id, "result" => %{"prompts" => [prompt.()]}})
          loop.(loop, changed)

        {:ok, %{"id" => id, "method" => "resources/read", "params" => %{"uri" => uri}}} ->
          log.(%{"event" => "read_resource", "uri" => uri})

          cond do
            scenario == "resource_disconnect" ->
              System.halt(0)

            scenario == "resource_protocol_error" ->
              write.(%{
                "jsonrpc" => "2.0",
                "id" => id,
                "error" => %{"code" => -32000, "message" => secret || "private fixture detail"}
              })

            scenario == "resource_wrong_uri" ->
              write.(%{
                "jsonrpc" => "2.0",
                "id" => id,
                "result" => %{"contents" => [%{"uri" => "notes://wrong", "text" => "wrong URI"}]}
              })

            scenario == "resource_blob" ->
              write.(%{
                "jsonrpc" => "2.0",
                "id" => id,
                "result" => %{
                  "contents" => [
                    %{"uri" => uri, "mimeType" => "application/octet-stream", "blob" => "AA=="}
                  ]
                }
              })

            scenario == "resource_oversized" ->
              write.(%{
                "jsonrpc" => "2.0",
                "id" => id,
                "result" => %{
                  "contents" => [%{"uri" => uri, "text" => String.duplicate("x", 65_537)}]
                }
              })

            true ->
              write.(%{
                "jsonrpc" => "2.0",
                "id" => id,
                "result" => %{
                  "contents" => [
                    %{"uri" => uri, "mimeType" => "text/plain", "text" => "A local fixture note."}
                  ]
                }
              })
          end

          loop.(loop, changed)

        {:ok,
         %{
           "id" => id,
           "method" => "prompts/get",
           "params" => %{"name" => name, "arguments" => args}
         }} ->
          log.(%{"event" => "get_prompt", "name" => name, "arguments" => args})

          result =
            cond do
              scenario == "prompt_embedded" ->
                %{
                  "messages" => [
                    %{
                      "role" => "user",
                      "content" => %{
                        "type" => "resource",
                        "resource" => %{"uri" => "notes://guide"}
                      }
                    }
                  ]
                }

              scenario == "prompt_invalid_role" ->
                %{
                  "messages" => [
                    %{
                      "role" => "system",
                      "content" => %{"type" => "text", "text" => "untrusted role"}
                    }
                  ]
                }

              true ->
                %{
                  "messages" => [
                    %{
                      "role" => "user",
                      "content" => %{"type" => "text", "text" => "Summarize: " <> args["topic"]}
                    },
                    %{
                      "role" => "assistant",
                      "content" => %{"type" => "text", "text" => "A concise summary."}
                    }
                  ]
                }
            end

          write.(%{"jsonrpc" => "2.0", "id" => id, "result" => result})
          loop.(loop, changed)

        {:ok, %{"id" => id, "method" => _method}} ->
          write.(%{
            "jsonrpc" => "2.0",
            "id" => id,
            "error" => %{"code" => -32601, "message" => "unsupported"}
          })

          loop.(loop, changed)

        _ ->
          loop.(loop, changed)
      end

    _ ->
      :ok
  end
end

loop.(loop, false)
