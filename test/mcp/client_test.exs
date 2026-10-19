defmodule Ipse.MCP.ClientTest do
  use ExUnit.Case, async: false

  alias Ipse.MCP.{Client, Config}

  setup do
    cwd = Path.join(System.tmp_dir!(), "ipse-mcp-client-#{System.unique_integer([:positive])}")
    File.mkdir_p!(cwd)
    on_exit(fn -> File.rm_rf!(cwd) end)
    %{cwd: cwd}
  end

  test "discovers only configured tools, validates arguments, then calls the reviewed tool",
       ctx do
    server = server(ctx.cwd)
    descriptor = discover!(server, ctx.cwd)
    assert descriptor.tool_id == "mcp__notes__write_note"
    assert descriptor.name == "write_note"
    assert descriptor.input_schema["additionalProperties"] == false

    assert {:error, _} =
             Client.call(descriptor, %{"path" => 17, "content" => "x"}, ctx.cwd)

    refute File.exists?(Path.join(ctx.cwd, "calls.log"))

    assert {:ok, "wrote note"} =
             observed(ctx.cwd, "call", fn ->
               Client.call(descriptor, %{"path" => "note.txt", "content" => "hello"}, ctx.cwd)
             end)

    assert File.read!(Path.join(ctx.cwd, "note.txt")) == "hello"
    assert File.read!(Path.join(ctx.cwd, "calls.log")) == "write_note\n"
  end

  test "changed discovery blocks dispatch and reports a reviewable error", ctx do
    descriptor = discover!(server(ctx.cwd), ctx.cwd)
    File.write!(Path.join(ctx.cwd, "change-schema"), "changed")

    assert {:error, message} =
             Client.call(descriptor, %{"path" => "note.txt", "content" => "hello"}, ctx.cwd)

    assert message =~ "discovery changed"
    refute File.exists?(Path.join(ctx.cwd, "calls.log"))
    refute File.exists?(Path.join(ctx.cwd, "note.txt"))
  end

  test "dispatch uses the rediscovered identity and schema, not caller routing fields", ctx do
    descriptor = discover!(server(ctx.cwd), ctx.cwd)
    forged_schema = %{descriptor | input_schema: %{"type" => "object"}}
    assert {:error, _} = Client.call(forged_schema, %{"path" => 17, "content" => "x"}, ctx.cwd)
    refute File.exists?(Path.join(ctx.cwd, "calls.log"))
    forged_name = %{descriptor | name: "unconfigured_tool"}

    assert {:ok, "wrote note"} =
             Client.call(forged_name, %{"path" => "note.txt", "content" => "bound"}, ctx.cwd)

    assert File.read!(Path.join(ctx.cwd, "calls.log")) == "write_note\n"
    assert File.read!(Path.join(ctx.cwd, "note.txt")) == "bound"
  end

  test "post-dispatch RPC failure stays unknown while server details stay hidden", ctx do
    descriptor = discover!(server(ctx.cwd, "rpc_error"), ctx.cwd)

    assert {:unknown, message} =
             Client.call(descriptor, %{"path" => "note.txt", "content" => "hello"}, ctx.cwd)

    assert message =~ "outcome unknown"
    refute message =~ "private fixture detail"
    assert File.read!(Path.join(ctx.cwd, "calls.log")) == "write_note\n"
  end

  test "server-declared tool errors and oversized replies do not masquerade as success", ctx do
    descriptor = discover!(server(ctx.cwd, "is_error"), ctx.cwd)

    assert {:error, "fixture rejected"} =
             Client.call(descriptor, %{"path" => "note.txt", "content" => "hello"}, ctx.cwd)

    assert File.read!(Path.join(ctx.cwd, "calls.log")) == "write_note\n"

    oversized_cwd = Path.join(ctx.cwd, "oversized")
    File.mkdir_p!(oversized_cwd)
    descriptor = discover!(server(oversized_cwd, "oversized"), oversized_cwd)

    assert {:unknown, message} =
             Client.call(descriptor, %{"path" => "note.txt", "content" => "hello"}, oversized_cwd)

    assert message =~ "outcome unknown"
    assert File.read!(Path.join(oversized_cwd, "calls.log")) == "write_note\n"
  end

  test "configured environment secrets are redacted from descriptions and tool results", ctx do
    server = server(ctx.cwd, "secret_result", %{"FIXTURE_SECRET" => "fixture-secret-value"})
    descriptor = discover!(server, ctx.cwd)
    refute descriptor.description =~ "fixture-secret-value"

    assert {:ok, "[redacted]"} =
             observed(ctx.cwd, "call", fn ->
               Client.call(descriptor, %{"path" => "note.txt", "content" => "hello"}, ctx.cwd)
             end)
  end

  test "connection loss after dispatch produces unknown and records the effect only once", ctx do
    descriptor = discover!(server(ctx.cwd, "controlled_disconnect"), ctx.cwd)

    task =
      Task.async(fn ->
        Client.call(descriptor, %{"path" => "note.txt", "content" => "hello"}, ctx.cwd)
      end)

    try do
      await_effect(task, ctx.cwd, System.monotonic_time(:millisecond) + 5_000)
      assert File.read!(Path.join(ctx.cwd, "calls.log")) == "write_note\n"
      assert File.read!(Path.join(ctx.cwd, "note.txt")) == "hello"
      File.write!(Path.join(ctx.cwd, "disconnect-now"), "exit normally")
      assert {:unknown, message} = Task.await(task, 5_000)
      assert message =~ "outcome unknown"
    after
      File.write!(Path.join(ctx.cwd, "disconnect-now"), "exit normally")
      Task.shutdown(task, :brutal_kill)
    end

    assert File.read!(Path.join(ctx.cwd, "calls.log")) == "write_note\n"
    assert File.read!(Path.join(ctx.cwd, "note.txt")) == "hello"
  end

  defp await_effect(task, cwd, deadline) do
    ready = Path.join(cwd, "disconnect-ready")

    if File.exists?(ready) do
      assert Regex.match?(~r/\A[0-9]+\z/, File.read!(ready))
    else
      stages =
        File.ls!(cwd)
        |> Enum.filter(&String.starts_with?(&1, "mcp-stage-"))
        |> Enum.map(&File.read!(Path.join(cwd, &1)))

      case Task.yield(task, 0) do
        nil ->
          assert System.monotonic_time(:millisecond) < deadline,
                 "MCP fixture never dispatched; stages: #{inspect(stages)}"

          Process.sleep(10)
          await_effect(task, cwd, deadline)

        result ->
          flunk(
            "MCP call ended before its dispatch precondition: #{inspect(result)}; stages: #{inspect(stages)}"
          )
      end
    end
  end

  test "malformed or wrong-version servers fail closed without dispatch", ctx do
    for scenario <- ["malformed", "wrong_version", "duplicate"] do
      cwd = Path.join(ctx.cwd, scenario)
      File.mkdir_p!(cwd)
      assert {:error, _} = Client.discover(server(cwd, scenario), cwd)
      refute File.exists?(Path.join(cwd, "calls.log"))
    end
  end

  test "server initiated sampling is unsupported and cannot cause a tool effect", ctx do
    assert {:ok, [_]} = Client.discover(server(ctx.cwd, "sampling"), ctx.cwd)
    refute File.exists?(Path.join(ctx.cwd, "calls.log"))
  end

  test "tool pagination is followed within the client's bounded catalog", ctx do
    assert {:ok, [_]} = Client.discover(server(ctx.cwd, "pagination"), ctx.cwd)
    refute File.exists?(Path.join(ctx.cwd, "calls.log"))
  end

  test "mixed RPC envelopes fail before SDK decoding without logging private payloads", ctx do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        server = server(ctx.cwd, "mixed_envelope", %{"FIXTURE_SECRET" => "private-mixed-payload"})
        assert {:error, _} = Client.discover(server, ctx.cwd)
      end)

    refute log =~ "private-mixed-payload"
    refute log =~ "FunctionClauseError"
    refute File.exists?(Path.join(ctx.cwd, "calls.log"))
  end

  defp discover!(server, cwd) do
    assert {:ok, [descriptor]} = observed(cwd, "discover", fn -> Client.discover(server, cwd) end)
    descriptor
  end

  test "failure diagnostics retain only bounded fixed stages and integer times", ctx do
    previous = System.get_env("IPSE_TEST_STDIO_PROBE")
    System.put_env("IPSE_TEST_STDIO_PROBE", "1")

    on_exit(fn ->
      if previous,
        do: System.put_env("IPSE_TEST_STDIO_PROBE", previous),
        else: System.delete_env("IPSE_TEST_STDIO_PROBE")
    end)

    File.write!(Path.join(ctx.cwd, "mcp-diagnostic-123-boot"), "12345")
    File.write!(Path.join(ctx.cwd, "mcp-diagnostic-123-effect_written"), "private-stage-payload")

    File.write!(
      Path.join(ctx.cwd, "mcp-diagnostic-123-private-stage-name"),
      "private-stage-payload"
    )

    File.write!(Path.join(ctx.cwd, "unrelated"), "private-stage-payload")

    output =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert observed(ctx.cwd, "synthetic", fn -> {:error, :controlled} end) ==
                 {:error, :controlled}
      end)

    report = Jason.decode!(String.trim(output))
    assert report["stages"] == [%{"pid" => "123", "stage" => "boot", "at_ms" => 12345}]
    refute output =~ "private-stage"
    refute output =~ "unrelated"
  end

  defp observed(cwd, phase, fun) do
    started = System.monotonic_time(:millisecond)
    at = System.system_time(:millisecond)
    result = fun.()

    if System.get_env("IPSE_TEST_STDIO_PROBE") == "1" and not match?({:ok, _}, result) do
      paths = Path.wildcard(Path.join(cwd, "mcp-diagnostic-*"))

      stages =
        paths
        |> Enum.take(16)
        |> Enum.flat_map(fn path ->
          with [_, pid, stage] <-
                 Regex.run(
                   ~r/\Amcp-diagnostic-([0-9]{1,16})-(boot|initialize|list_tools|call_tool|effect_written)\z/,
                   Path.basename(path)
                 ),
               {:ok, bytes} when is_binary(bytes) <-
                 File.open(path, [:read, :binary], &IO.binread(&1, 32)),
               true <- Regex.match?(~r/\A[0-9]{1,16}\z/, bytes) do
            [%{"pid" => pid, "stage" => stage, "at_ms" => String.to_integer(bytes)}]
          else
            _ -> []
          end
        end)

      IO.puts(
        :stderr,
        Jason.encode!(%{
          "synthetic_mcp_failure" => phase,
          "started_at_ms" => at,
          "elapsed_ms" => System.monotonic_time(:millisecond) - started,
          "stages" => stages,
          "stage_files" => length(paths),
          "truncated" => length(paths) > 16
        })
      )
    end

    result
  end

  defp server(cwd, scenario \\ "normal", env \\ %{}) do
    elixir = System.find_executable("elixir")
    jason_beam = :code.which(Jason) |> List.to_string()
    jason_ebin = Path.dirname(jason_beam)
    script = Path.expand("../support/mcp_server.exs", __DIR__)

    diagnostics =
      if System.get_env("IPSE_TEST_STDIO_PROBE") == "1",
        do: ["--fixture-diagnostics"],
        else: []

    config = %{
      "servers" => [
        %{
          "id" => "notes",
          "command" => elixir,
          "args" => ["--erl", "+S 2:2", "-pa", jason_ebin, script, scenario] ++ diagnostics,
          "tools" => ["write_note"],
          "env" =>
            Map.put(
              env,
              "PATH",
              Path.join(to_string(:code.root_dir()), "bin") <> ":/usr/bin:/bin"
            ),
          "timeout_ms" => 5_000
        }
      ]
    }

    path = Path.join(cwd, "mcp.json")
    File.write!(path, Jason.encode!(config))
    assert {:ok, [server]} = Config.load(path)
    server
  end
end
