defmodule Ipse.Auth.XAITest do
  use ExUnit.Case, async: false
  alias Ipse.Auth.XAI

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-xai-auth-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    previous = System.get_env("IPSE_XAI_CLIENT_ID")
    System.put_env("IPSE_XAI_CLIENT_ID", "ipse-registered-fixture")

    on_exit(fn ->
      if previous,
        do: System.put_env("IPSE_XAI_CLIENT_ID", previous),
        else: System.delete_env("IPSE_XAI_CLIENT_ID")

      File.rm_rf!(root)
    end)

    %{root: root, dir: Path.join(root, "auth")}
  end

  defp device(extra \\ %{}),
    do:
      Map.merge(
        %{
          "verification_uri" => "https://accounts.x.ai/oauth2/device",
          "device_code" => "PRIVATE_DEVICE_CODE",
          "user_code" => "ABCD-EFGH",
          "expires_in" => 300,
          "interval" => 1
        },
        extra
      )

  defp tokens(extra \\ %{}),
    do:
      Map.merge(
        %{
          "token_type" => "Bearer",
          "access_token" => "PRIVATE_ACCESS",
          "refresh_token" => "PRIVATE_REFRESH",
          "expires_in" => 3600,
          "scope" => "api:access offline_access"
        },
        extra
      )

  defp saved(extra \\ %{}),
    do:
      Map.merge(
        %{
          "version" => 1,
          "issuer" => "https://auth.x.ai",
          "client_id" => "ipse-registered-fixture",
          "access_token" => "PRIVATE_OLD_ACCESS",
          "refresh_token" => "PRIVATE_OLD_REFRESH",
          "expires_at" => System.system_time(:second) - 1,
          "scope" => "api:access offline_access"
        },
        extra
      )

  defp save(c, record) do
    File.mkdir_p!(c.dir)
    File.chmod!(c.dir, 0o700)
    :ok = Ipse.Auth.write_credentials(c.dir, record, :xai)
  end

  defp fixture(responses, fun) do
    Process.put(:xai_test_responses, responses)
    Process.put(:xai_test_calls, [])
    Process.put(:xai_test_sleeps, [])

    transport = fn url, fields ->
      Process.put(:xai_test_calls, Process.get(:xai_test_calls) ++ [{url, fields}])
      [next | rest] = Process.get(:xai_test_responses)
      Process.put(:xai_test_responses, rest)
      next
    end

    XAI.with_fixture(
      transport,
      fn ms -> Process.put(:xai_test_sleeps, Process.get(:xai_test_sleeps) ++ [ms]) end,
      fun
    )
  end

  test "missing registration refuses before requests, directory creation or API fallback", c do
    System.delete_env("IPSE_XAI_CLIENT_ID")

    fixture([], fn ->
      assert {:error, message} = XAI.login(c.dir)
      assert message =~ "approved Ipse client registration"
      assert Process.get(:xai_test_calls) == []
      refute File.exists?(c.dir)
    end)
  end

  test "device grant honors pending and slow-down, binds the client and writes private tokens",
       c do
    fixture(
      [
        {:ok, device()},
        {:oauth_error, "authorization_pending"},
        {:oauth_error, "slow_down"},
        {:ok, tokens()}
      ],
      fn ->
        assert :ok = XAI.login(c.dir, output: &Process.put(:xai_output, &1))
        assert Process.get(:xai_test_sleeps) == [1000, 1000, 6000]
        [{first_url, first} | polls] = Process.get(:xai_test_calls)
        assert first_url == "https://auth.x.ai/oauth2/device/code"

        assert first == %{
                 "client_id" => "ipse-registered-fixture",
                 "scope" => "api:access offline_access"
               }

        assert Enum.all?(polls, fn {url, fields} ->
                 url == "https://auth.x.ai/oauth2/token" and
                   fields["grant_type"] == "urn:ietf:params:oauth:grant-type:device_code" and
                   fields["client_id"] == first["client_id"]
               end)

        output = Process.get(:xai_output)
        assert output =~ "https://accounts.x.ai/oauth2/device"
        assert output =~ "ABCD-EFGH"

        for private <- ~w(PRIVATE_DEVICE_CODE PRIVATE_ACCESS PRIVATE_REFRESH),
            do: refute(output =~ private)

        assert {:ok, status} = XAI.status(c.dir)
        refute Jason.encode!(status) =~ "PRIVATE"
        assert status.client_id == "ipse-registered-fixture"
        assert {:ok, "PRIVATE_ACCESS"} = XAI.token(c.dir)
        assert Bitwise.band(File.stat!(Path.join(c.dir, "xai.json")).mode, 0o777) == 0o600
        assert File.exists?(Path.join(c.dir, ".xai.lock"))
        refute File.exists?(Path.join(c.dir, "chatgpt.json"))
      end
    )
  end

  test "denial, expiry, invalid browser destinations and bad token grants preserve existing credentials",
       c do
    save(c, saved(%{"expires_at" => System.system_time(:second) + 3600}))
    path = Path.join(c.dir, "xai.json")
    before = File.read!(path)

    for responses <- [
          [{:ok, device()}, {:oauth_error, "access_denied"}],
          [{:ok, device()}, {:oauth_error, "expired_token"}],
          [{:ok, device(%{"expires_in" => 1})}],
          [{:ok, device(%{"verification_uri" => "https://evil.example/device"})}],
          [{:ok, device(%{"verification_uri" => "https://accounts.x.ai/device?token=private"})}],
          [{:ok, device()}, {:ok, tokens(%{"scope" => "api:access billing:write"})}],
          [{:ok, device()}, {:ok, tokens(%{"access_token" => "bad\nvalue"})}]
        ] do
      fixture(responses, fn -> assert {:error, _} = XAI.login(c.dir, output: fn _ -> :ok end) end)
      assert File.read!(path) == before
    end
  end

  test "rotation is serialized and refreshed tokens retain their issued client", c do
    save(c, saved())
    System.put_env("IPSE_XAI_CLIENT_ID", "different-new-client")
    {:ok, calls} = Agent.start_link(fn -> [] end)

    transport = fn url, fields ->
      Agent.update(calls, &(&1 ++ [{url, fields}]))
      Process.sleep(30)

      {:ok,
       tokens(%{
         "access_token" => "PRIVATE_ROTATED_ACCESS",
         "refresh_token" => "PRIVATE_ROTATED_REFRESH"
       })}
    end

    jobs =
      for _ <- 1..2,
          do:
            Task.async(fn ->
              XAI.with_fixture(transport, fn _ -> :ok end, fn -> XAI.token(c.dir) end)
            end)

    assert Enum.map(jobs, &Task.await(&1, 5000)) == [
             {:ok, "PRIVATE_ROTATED_ACCESS"},
             {:ok, "PRIVATE_ROTATED_ACCESS"}
           ]

    [{_, fields}] = Agent.get(calls, & &1)
    assert fields["client_id"] == "ipse-registered-fixture"
    assert fields["refresh_token"] == "PRIVATE_OLD_REFRESH"
    Agent.stop(calls)
    assert {:ok, record} = Ipse.Auth.read_credentials(c.dir, :xai)
    assert record["refresh_token"] == "PRIVATE_ROTATED_REFRESH"
    refute Map.has_key?(record, "refresh_pending")
  end

  test "ambiguous refresh is never replayed, while explicit rejection has a recorded outcome",
       c do
    save(c, saved())

    fixture([{:error, "connection interrupted"}], fn ->
      assert {:error, message} = XAI.token(c.dir)
      assert message =~ "unknown"
      assert {:error, message} = XAI.token(c.dir)
      assert message =~ "will not be replayed"
      assert length(Process.get(:xai_test_calls)) == 1
    end)

    assert {:ok, %{refresh_pending: true}} = XAI.status(c.dir)
    save(c, saved())
    fixture([{:oauth_error, "invalid_grant"}], fn -> assert {:error, _} = XAI.token(c.dir) end)
    assert {:ok, %{}} = Ipse.Auth.read_credentials(c.dir, :xai)
  end

  test "offline status preserves expired bytes, unsafe files refuse, and logout reports remote uncertainty",
       c do
    save(c, saved())
    path = Path.join(c.dir, "xai.json")
    before = File.read!(path)

    fixture([], fn ->
      assert {:ok, _} = XAI.status(c.dir)
      assert Process.get(:xai_test_calls) == []
    end)

    assert File.read!(path) == before
    File.chmod!(path, 0o644)
    assert {:error, _} = XAI.status(c.dir)
    File.chmod!(path, 0o600)

    fixture([{:error, "remote unavailable"}], fn ->
      assert {:error, message} = XAI.logout(c.dir)
      assert message =~ "remote revocation is unconfirmed"
    end)

    assert {:ok, %{}} = Ipse.Auth.read_credentials(c.dir, :xai)
    assert File.exists?(Path.join(c.dir, ".xai.lock"))
    File.rm!(path)
    target = Path.join(c.root, "outside")
    File.write!(target, before)
    File.chmod!(target, 0o600)
    File.ln_s!(target, path)
    assert {:error, _} = XAI.status(c.dir)
    assert File.read!(target) == before
  end

  test "refresh without a scope response preserves the actual narrower grant", c do
    save(c, saved(%{"scope" => "api:access"}))

    fixture([{:ok, Map.delete(tokens(), "scope")}], fn ->
      assert {:ok, "PRIVATE_ACCESS"} = XAI.token(c.dir)
      [{_, fields}] = Process.get(:xai_test_calls)
      assert fields["scope"] == "api:access"
    end)

    assert {:ok, record} = Ipse.Auth.read_credentials(c.dir, :xai)
    assert record["scope"] == "api:access"
    save(c, saved(%{"scope" => "api:access"}))
    fixture([{:ok, tokens()}], fn -> assert {:error, _} = XAI.token(c.dir) end)
    assert {:ok, record} = Ipse.Auth.read_credentials(c.dir, :xai)
    assert record["refresh_pending"] == true
    assert record["scope"] == "api:access"
  end

  test "bounded decoding exposes no server-provided descriptions or credentials" do
    assert {:oauth_error, "access_denied"} =
             XAI.decode(400, ~s({"error":"access_denied","error_description":"PRIVATE"}))

    for {status, body} <- [{500, "PRIVATE"}, {200, "[]"}, {200, String.duplicate("x", 65_537)}] do
      assert {:error, error} = XAI.decode(status, body)
      refute error =~ "PRIVATE"
    end
  end
end
