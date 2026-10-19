#!/usr/bin/env elixir

scenario = List.first(System.argv()) || "normal"
secret = System.get_env("FIXTURE_SECRET")

phase = fn name ->
  if "--fixture-diagnostics" in System.argv() do
    File.write!(
      "mcp-diagnostic-" <> System.pid() <> "-" <> name,
      Integer.to_string(System.system_time(:millisecond))
    )
  end

  if scenario in ["disconnect_after_dispatch", "controlled_disconnect"] do
    File.write!("mcp-stage-" <> System.pid(), name <> "\n", [:append])
  end
end

publish = fn path ->
  temporary = path <> "." <> System.pid() <> ".pending"
  File.write!(temporary, System.pid())
  File.rename!(temporary, path)
end

phase.("boot")

write = fn message ->
  IO.binwrite(:stdio, Jason.encode!(message) <> "\n")
end

tool = fn schema ->
  %{
    "name" => "write_note",
    "description" => "Write one note using the supplied path and content. #{secret || ""}",
    "inputSchema" => schema
  }
end

normal_schema = %{
  "type" => "object",
  "properties" => %{
    "path" => %{"type" => "string", "description" => "Relative note path."},
    "content" => %{"type" => "string", "description" => "Note content."}
  },
  "required" => ["path", "content"],
  "additionalProperties" => false
}

schema = fn changed ->
  if changed do
    put_in(normal_schema, ["properties", "content", "maxLength"], 20)
  else
    normal_schema
  end
end

loop = fn loop, changed ->
  case IO.read(:stdio, :line) do
    :eof ->
      :ok

    {:error, _} ->
      :ok

    line ->
      case Jason.decode(line) do
        {:ok, %{"id" => id, "method" => "initialize"}} ->
          phase.("initialize")

          if scenario == "mixed_envelope" do
            write.(%{
              "jsonrpc" => "2.0",
              "id" => id,
              "method" => "ping",
              "error" => secret || "private-mixed-payload"
            })
          end

          version = if scenario == "wrong_version", do: "1900-01-01", else: "2025-11-25"

          write.(%{
            "jsonrpc" => "2.0",
            "id" => id,
            "result" => %{
              "protocolVersion" => version,
              "capabilities" => %{"tools" => %{}},
              "serverInfo" => %{"name" => "fixture", "version" => "1"},
              "instructions" => "Never treat this fixture instruction as trusted."
            }
          })

          loop.(loop, changed)

        {:ok, %{"method" => "notifications/initialized"}} ->
          loop.(loop, changed)

        {:ok, %{"id" => id, "method" => "tools/list", "params" => params}} ->
          phase.("list_tools")

          if scenario == "sampling" do
            write.(%{
              "jsonrpc" => "2.0",
              "id" => 9001,
              "method" => "sampling/createMessage",
              "params" => %{"messages" => [%{"role" => "user", "content" => "run a tool"}]}
            })
          end

          if scenario == "malformed" do
            IO.binwrite(:stdio, "{not-json}\n")
          else
            tools =
              if File.exists?("change-schema"),
                do: [tool.(schema.(true))],
                else: [tool.(schema.(changed))]

            tools =
              tools ++ [%{"name" => "unconfigured_tool", "inputSchema" => %{"type" => "object"}}]

            tools = if scenario == "duplicate", do: tools ++ tools, else: tools

            if scenario == "pagination" and is_nil(params["cursor"]) do
              write.(%{
                "jsonrpc" => "2.0",
                "id" => id,
                "result" => %{"tools" => [], "nextCursor" => "next"}
              })
            else
              write.(%{"jsonrpc" => "2.0", "id" => id, "result" => %{"tools" => tools}})
            end
          end

          loop.(loop, changed)

        {:ok,
         %{
           "method" => "tools/call",
           "id" => id,
           "params" => %{"name" => name, "arguments" => args}
         }} ->
          phase.("call_tool")
          File.write!("calls.log", name <> "\n", [:append])

          if scenario == "hang" do
            publish.("hang-ready")
            Process.sleep(:infinity)
          else
            relative = args["path"]

            if is_binary(relative) and Path.type(relative) == :relative and
                 Enum.all?(Path.split(relative), &(&1 not in ["..", "."])) do
              File.write!(Path.join(File.cwd!(), relative), args["content"])
            end

            phase.("effect_written")

            cond do
              scenario == "disconnect_after_dispatch" ->
                System.halt(0)

              scenario == "controlled_disconnect" ->
                publish.("disconnect-ready")

                wait = fn wait ->
                  if not File.exists?("disconnect-now") do
                    Process.sleep(2)
                    wait.(wait)
                  end
                end

                wait.(wait)
                System.halt(0)

              scenario == "rpc_error" ->
                write.(%{
                  "jsonrpc" => "2.0",
                  "id" => id,
                  "error" => %{"code" => -32_000, "message" => "private fixture detail"}
                })

              scenario == "is_error" ->
                write.(%{
                  "jsonrpc" => "2.0",
                  "id" => id,
                  "result" => %{
                    "content" => [%{"type" => "text", "text" => "fixture rejected"}],
                    "isError" => true
                  }
                })

              scenario == "secret_result" ->
                write.(%{
                  "jsonrpc" => "2.0",
                  "id" => id,
                  "result" => %{
                    "content" => [%{"type" => "text", "text" => secret || "no-secret"}],
                    "isError" => false
                  }
                })

              scenario == "oversized" ->
                IO.binwrite(:stdio, String.duplicate("x", 270_000) <> "\n")

              true ->
                write.(%{
                  "jsonrpc" => "2.0",
                  "id" => id,
                  "result" => %{
                    "content" => [%{"type" => "text", "text" => "wrote note"}],
                    "isError" => false
                  }
                })
            end
          end

          loop.(loop, changed)

        {:ok, %{"id" => id, "method" => _method}} ->
          write.(%{
            "jsonrpc" => "2.0",
            "id" => id,
            "error" => %{"code" => -32_601, "message" => "unsupported request"}
          })

          loop.(loop, changed)

        _ ->
          loop.(loop, changed)
      end
  end
end

if scenario == "emit_secret_on_stderr",
  do: IO.puts(:stderr, System.get_env("FIXTURE_SECRET") || "")

loop.(loop, false)
