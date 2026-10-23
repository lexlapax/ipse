defmodule Ipse.EgressPolicyTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  setup do
    names =
      ~w(HTTP_PROXY http_proxy HTTPS_PROXY https_proxy NO_PROXY no_proxy IPSE_MCP_PROXY_FIXTURE_TOKEN)

    previous = Map.new(names, &{&1, System.get_env(&1)})
    Enum.each(names, &System.delete_env/1)
    System.put_env("IPSE_MCP_PROXY_FIXTURE_TOKEN", "synthetic-mcp-bearer")
    root = Path.join(System.tmp_dir!(), "ipse-egress-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)

    on_exit(fn ->
      Enum.each(previous, fn {name, value} ->
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end)

      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "unsupported configured proxies refuse auth, inference and MCP before direct egress", c do
    System.put_env("HTTPS_PROXY", "https://127.0.0.1:1")

    assert_raise ArgumentError, "Unsupported proxy URL", fn ->
      Ipse.HTTP.finch_options(URI.parse("https://mcp.example.invalid"))
    end

    assert {:error, _} = Ipse.Auth.auth_request(:get, "https://auth.openai.com/")

    assert {:error, _} =
             Ipse.Provider.complete(
               %{
                 provider: :openai,
                 model: "fixture",
                 base_url: "https://model.example.invalid",
                 api_key: "fixture",
                 timeout_ms: 1000
               },
               [],
               [],
               fn _ -> :ok end
             )

    server = mcp(c.root)
    assert {:error, _} = Ipse.MCP.discover_server(server, c.root)
  end

  test "a remote hostname beginning with 127 does not silently bypass the proxy" do
    System.put_env("HTTPS_PROXY", "http://127.0.0.1:4321")
    refute Ipse.HTTP.bypass?("127.0.0.1.attacker.invalid")

    assert [{:proxy, {:http, "127.0.0.1", 4321, []}}, {:proxy_headers, []}] =
             Ipse.HTTP.finch_options(URI.parse("https://127.0.0.1.attacker.invalid"))
  end

  test "MCP routes through its configured authenticated proxy without leaking bearer headers",
       c do
    {proxy, task} = proxy_fixture()
    System.put_env("HTTPS_PROXY", "http://fixture-user:fixture-password@" <> proxy)
    assert {:error, _} = Ipse.MCP.discover_server(mcp(c.root), c.root)
    request = Task.await(task, 4000)
    assert request =~ "CONNECT mcp.example.invalid:443"

    assert String.downcase(request) =~
             "proxy-authorization: basic " <>
               String.downcase(Base.encode64("fixture-user:fixture-password"))

    refute String.downcase(request) =~ "authorization: bearer"
    refute request =~ "synthetic-mcp-bearer"
  end

  test "auth and inference use the same HTTP CONNECT proxy and fail without fallback" do
    for kind <- [:auth, :provider] do
      {proxy, task} = proxy_fixture()
      System.put_env("HTTPS_PROXY", "http://" <> proxy)

      result =
        case kind do
          :auth ->
            Ipse.Auth.auth_request(:get, "https://auth.openai.com/")

          :provider ->
            Ipse.Provider.complete(
              %{
                provider: :openai,
                model: "fixture",
                base_url: "https://model.example.invalid",
                api_key: "synthetic-model-bearer",
                timeout_ms: 1500
              },
              [],
              [],
              fn _ -> :ok end
            )
        end

      assert {:error, _} = result
      request = Task.await(task, 4000)
      assert request =~ "CONNECT "
      refute request =~ "synthetic-model-bearer"
    end
  end

  test "CLI rejects remote cleartext base URLs before credential acquisition or dispatch" do
    output =
      capture_io(:stderr, fn ->
        assert 1 ==
                 Ipse.CLI.run([
                   "run",
                   "--provider",
                   "openai",
                   "--base-url",
                   "http://example.test/v1",
                   "fixture"
                 ])
      end)

    assert output =~ "Provider endpoint requires HTTPS"
    refute output =~ "OPENAI_API_KEY"

    for provider <- [:openai, :anthropic, :ollama] do
      assert_raise ArgumentError, fn ->
        Ipse.Provider.endpoint(
          %{provider: provider, base_url: "http://example.test"},
          "https://example.test",
          "/fixture"
        )
      end

      assert Ipse.Provider.valid_base_url?(provider, "http://127.0.0.1:1234")
      refute Ipse.Provider.valid_base_url?(provider, "https://example.test/?secret=value")
    end
  end

  defp mcp(root) do
    path = Path.join(root, "mcp.json")

    File.write!(
      path,
      Jason.encode!(%{
        "servers" => [
          %{
            "id" => "proxy",
            "transport" => "http",
            "url" => "https://mcp.example.invalid/mcp",
            "tools" => ["fixture"],
            "timeout_ms" => 1500,
            "bearer_env" => "IPSE_MCP_PROXY_FIXTURE_TOKEN"
          }
        ]
      })
    )

    {:ok, [server]} = Ipse.MCP.Config.load(path)
    server
  end

  defp proxy_fixture do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        try do
          {:ok, socket} = :gen_tcp.accept(listener, 3000)

          try do
            request = headers(socket, "")

            :ok =
              :gen_tcp.send(
                socket,
                "HTTP/1.1 502 Bad Gateway\r\ncontent-length: 0\r\nconnection: close\r\n\r\n"
              )

            request
          after
            :gen_tcp.close(socket)
          end
        after
          :gen_tcp.close(listener)
        end
      end)

    {"127.0.0.1:#{port}", task}
  end

  defp headers(socket, buffer) do
    if String.contains?(buffer, "\r\n\r\n") do
      buffer
    else
      {:ok, bytes} = :gen_tcp.recv(socket, 0, 2000)
      headers(socket, buffer <> bytes)
    end
  end
end
