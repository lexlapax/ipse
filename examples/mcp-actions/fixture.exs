defmodule IpseMCPExample.Fixture do
  @moduledoc false

  def text, do: String.duplicate("évidence λine 🌿\n", 900)

  def schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{"text" => %{"type" => "string"}},
      "required" => ["text"]
    }
  end

  def stdio(root, mode) do
    :ok = :io.setopts(:standard_io, binary: true, encoding: :latin1)
    loop(root, mode)
  end

  defp loop(root, mode) do
    case IO.binread(:stdio, :line) do
      line when is_binary(line) ->
        rpc = :json.decode(line)
        record(root, rpc)

        if rpc["id"] do
          if rpc["method"] == "tools/call" and mode == "disconnect" do
            System.halt(0)
          end

          if rpc["method"] == "tools/call" and mode == "hold" do
            receive do: (:never -> :ok)
          end

          changed = File.exists?(Path.join(root, "change-descriptor"))
          result = result(rpc, changed, text())

          IO.binwrite(
            :stdio,
            :json.encode(%{"jsonrpc" => "2.0", "id" => rpc["id"], "result" => result})
          )

          IO.binwrite(:stdio, "\n")
        end

        loop(root, mode)

      _ ->
        :ok
    end
  end

  def stdio_config(root, mode \\ "normal") do
    runtime = to_string(:code.root_dir())
    erl = Path.join([runtime, "erts-" <> to_string(:erlang.system_info(:version)), "bin", "erl"])
    boot = clean_boot(runtime)
    file = __ENV__.file

    expression =
      "application:ensure_all_started(elixir), 'Elixir.Code':require_file(" <>
        erlang_term(file) <>
        "), 'Elixir.IpseMCPExample.Fixture':stdio(" <>
        erlang_term(root) <> ", " <> erlang_term(mode) <> "), init:stop()."

    %{
      "id" => "fixture",
      "command" => erl,
      "args" => [
        "+S",
        "1:1",
        "+A",
        "1",
        "-noshell",
        "-boot",
        boot,
        "-boot_var",
        "RELEASE_LIB",
        Path.join(runtime, "lib"),
        "-pa",
        Application.app_dir(:elixir, "ebin"),
        "-eval",
        expression
      ],
      "tools" => ["fetch"],
      "timeout_ms" => 5000
    }
  end

  defp erlang_term(value), do: :io_lib.format(~c"~p", [value]) |> IO.iodata_to_binary()

  defp clean_boot(runtime) do
    current =
      case :init.get_argument(:boot) do
        {:ok, [[path]]} ->
          path = List.to_string(path)

          if Path.type(path) == :absolute and
               String.starts_with?(Path.expand(path), Path.join(runtime, "releases") <> "/"),
             do: Path.join(Path.dirname(path), "start_clean")

        _ ->
          nil
      end

    Enum.find([current, Path.join([runtime, "bin", "no_dot_erlang"])], fn path ->
      is_binary(path) and File.regular?(path <> ".boot")
    end) || raise "No clean bundled runtime boot file"
  end

  def record(root, rpc) do
    File.write!(
      Path.join(root, "transport.jsonl"),
      :json.encode(%{"method" => rpc["method"], "params" => rpc["params"]})
      |> IO.iodata_to_binary()
      |> Kernel.<>("\n"),
      [:append]
    )
  end

  def records(root) do
    case File.read(Path.join(root, "transport.jsonl")) do
      {:ok, bytes} -> bytes |> String.split("\n", trim: true) |> Enum.map(&:json.decode/1)
      {:error, :enoent} -> []
    end
  end

  def calls(root), do: Enum.count(records(root), &(&1["method"] == "tools/call"))
  def discoveries(root), do: Enum.count(records(root), &(&1["method"] == "tools/list"))

  def result(%{"method" => "initialize"}, _, _) do
    %{
      "protocolVersion" => "2025-11-25",
      "capabilities" => %{"tools" => %{}, "resources" => %{}, "prompts" => %{}},
      "serverInfo" => %{"name" => "synthetic-mcp-actions", "version" => "1"}
    }
  end

  def result(%{"method" => "tools/list"}, changed, _) do
    %{
      "tools" => [
        %{
          "name" => "fetch",
          "description" =>
            if(changed, do: "Changed descriptor", else: "Fetch synthetic public text"),
          "inputSchema" => schema()
        }
      ]
    }
  end

  def result(%{"method" => "tools/call"}, _, text),
    do: %{"content" => [%{"type" => "text", "text" => text}]}

  def result(%{"method" => "resources/list"}, _, _),
    do: %{"resources" => [%{"uri" => "fixture://document", "name" => "document"}]}

  def result(%{"method" => "resources/read"}, _, text),
    do: %{"contents" => [%{"uri" => "fixture://document", "text" => text}]}

  def result(%{"method" => "prompts/list"}, _, _),
    do: %{
      "prompts" => [
        %{"name" => "summary", "arguments" => [%{"name" => "text", "required" => true}]}
      ]
    }

  def result(%{"method" => "prompts/get"}, _, text),
    do: %{"messages" => [%{"role" => "user", "content" => %{"type" => "text", "text" => text}}]}

  def result(_, _, _), do: %{}

  def http(root, owner, mode \\ :normal) do
    {:ok, supervisor} = Task.Supervisor.start_link()
    Process.unlink(supervisor)

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    Task.Supervisor.start_child(supervisor, fn ->
      accept(listener, supervisor, root, owner, mode)
    end)

    entry = %{
      "id" => "fixture",
      "transport" => "http",
      "url" => "http://127.0.0.1:#{port}/mcp",
      "allow_insecure_loopback" => true,
      "tools" => ["fetch"],
      "timeout_ms" => 5000
    }

    {%{listener: listener, supervisor: supervisor}, entry}
  end

  def stop(%{listener: listener, supervisor: supervisor}) do
    monitor = Process.monitor(supervisor)
    :gen_tcp.close(listener)

    try do
      Supervisor.stop(supervisor)
    catch
      :exit, {:noproc, _} -> :ok
    end

    receive do
      {:DOWN, ^monitor, :process, ^supervisor, _} -> :ok
    after
      2000 -> raise "MCP fixture supervisor cleanup unconfirmed"
    end

    :ok
  end

  defp accept(listener, supervisor, root, owner, mode) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        {:ok, handler} =
          Task.Supervisor.start_child(supervisor, fn ->
            receive do: (:serve -> serve(socket, root, owner, mode))
          end)

        :ok = :gen_tcp.controlling_process(socket, handler)
        send(handler, :serve)
        accept(listener, supervisor, root, owner, mode)

      _ ->
        :ok
    end
  end

  defp serve(socket, root, owner, mode) do
    try do
      {method, rpc} = read_request(socket, "")
      record(root, rpc)

      cond do
        rpc["method"] == "tools/call" and mode == :disconnect ->
          send(owner, {:extension_mcp_fixture, :dispatched, self()})

        rpc["method"] == "tools/call" and mode == :hold ->
          send(owner, {:extension_mcp_fixture, :dispatched, self()})
          :gen_tcp.recv(socket, 0, 30_000)
          send(owner, {:extension_mcp_fixture, :closed, self()})

        true ->
          status = if method == "DELETE" or is_nil(rpc["id"]), do: 202, else: 200
          changed = File.exists?(Path.join(root, "change-descriptor"))

          body =
            if status == 202,
              do: "",
              else:
                :json.encode(%{
                  "jsonrpc" => "2.0",
                  "id" => rpc["id"],
                  "result" => result(rpc, changed, text())
                })
                |> IO.iodata_to_binary()

          :gen_tcp.send(
            socket,
            "HTTP/1.1 #{status} Fixture\r\ncontent-type: application/json\r\nmcp-session-id: synthetic-session\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
              body
          )
      end
    after
      :gen_tcp.close(socket)
    end
  end

  defp read_request(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [raw, body] ->
        [first | lines] = String.split(raw, "\r\n")

        headers =
          Map.new(lines, fn line ->
            [key, value] = String.split(line, ":", parts: 2)
            {String.downcase(key), String.trim(value)}
          end)

        size = String.to_integer(headers["content-length"] || "0")
        body = read_body(socket, body, size)
        {hd(String.split(first, " ")), if(body == "", do: %{}, else: :json.decode(body))}

      [_] ->
        {:ok, bytes} = :gen_tcp.recv(socket, 0, 5000)
        read_request(socket, buffer <> bytes)
    end
  end

  defp read_body(_, body, size) when byte_size(body) >= size, do: body

  defp read_body(socket, body, size) do
    {:ok, bytes} = :gen_tcp.recv(socket, 0, 5000)
    read_body(socket, body <> bytes, size)
  end
end
