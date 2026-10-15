defmodule Ipse.AuthPendingRefreshTest do
  use ExUnit.Case, async: false
  alias Ipse.Auth
  alias Ipse.Auth.{HTTP, Store}

  setup_all do
    key = :public_key.generate_key({:rsa, 2048, 65_537})

    jwk = %{
      "kty" => "RSA",
      "kid" => "pending-fixture",
      "alg" => "RS256",
      "use" => "sig",
      "n" => Base.url_encode64(:binary.encode_unsigned(elem(key, 2)), padding: false),
      "e" => Base.url_encode64(:binary.encode_unsigned(elem(key, 3)), padding: false)
    }

    %{key: key, jwks: %{"keys" => [jwk]}}
  end

  setup do
    dir =
      Path.join(System.tmp_dir!(), "ipse-pending-refresh-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "rotation is durable before discovery and retry preserves receipt-time expiry", ctx do
    saved = record()
    save(ctx.dir, saved)
    response = response(sign(ctx.key, claims()))

    transport = fn
      :post, "https://auth.openai.com/api/accounts/oauth/token", fields ->
        assert fields["refresh_token"] == "old-fixture-refresh"
        {:ok, response}

      :get, "https://auth.openai.com/.well-known/openid-configuration", _ ->
        {:ok, pending} = Store.read(ctx.dir)
        assert pending["access_token"] == saved["access_token"]
        assert pending["pending_refresh"]["response"] == response
        assert Bitwise.band(File.stat!(Path.join(ctx.dir, "chatgpt.json")).mode, 0o777) == 0o600
        {:error, "fixture temporary discovery failure"}
    end

    assert {:error, "fixture temporary discovery failure"} =
             HTTP.with_transport(transport, fn -> Auth.token(ctx.dir) end)

    {:ok, pending} = Store.read(ctx.dir)
    # Represent a retry after elapsed time without changing the system clock.
    pending =
      update_in(pending, ["pending_refresh"], fn value ->
        value |> Map.update!("received_at", &(&1 - 30)) |> Map.update!("expires_at", &(&1 - 30))
      end)

    expiry = pending["pending_refresh"]["expires_at"]
    save(ctx.dir, pending)

    assert {:ok, "rotated-fixture-access"} =
             HTTP.with_transport(identity_transport(ctx), fn -> Auth.token(ctx.dir) end)

    assert {:ok, resolved} = Store.read(ctx.dir)
    assert resolved["expires_at"] == expiry
    assert resolved["refresh_token"] == "rotated-fixture-refresh"
    assert resolved["subject"] == saved["subject"]
    refute Map.has_key?(resolved, "pending_refresh")
  end

  test "owner death during identity fetching resumes without replaying the consumed refresh",
       ctx do
    save(ctx.dir, record())
    parent = self()
    response = response(sign(ctx.key, claims()))

    {owner, monitor} =
      spawn_monitor(fn ->
        HTTP.with_transport(
          fn
            :post, "https://auth.openai.com/api/accounts/oauth/token", _ ->
              {:ok, response}

            :get, "https://auth.openai.com/.well-known/openid-configuration", _ ->
              send(parent, :pending_saved)
              Process.sleep(:infinity)
          end,
          fn -> Auth.token(ctx.dir) end
        )
      end)

    assert_receive :pending_saved, 5_000
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}, 2_000

    assert {:ok, "rotated-fixture-access"} =
             HTTP.with_transport(identity_transport(ctx), fn -> Auth.token(ctx.dir) end)

    {:ok, resolved} = Store.read(ctx.dir)
    assert resolved["refresh_token"] == "rotated-fixture-refresh"
    refute Map.has_key?(resolved, "pending_refresh")
  end

  test "mismatched or expired pending identity never activates tokens or refreshes again", ctx do
    for change <- [%{"sub" => "other-account"}, %{"exp" => 0}] do
      response = response(sign(ctx.key, Map.merge(claims(), change)))
      pending = pending_record(response)
      save(ctx.dir, pending)

      assert {:error, error} =
               HTTP.with_transport(identity_transport(ctx), fn -> Auth.token(ctx.dir) end)

      assert error =~ "identity token validation failed"
      refute error =~ "rotated-fixture"
      assert {:ok, ^pending} = Store.read(ctx.dir)
    end
  end

  test "inconsistent pending expiry is rejected before network or token activation", ctx do
    pending =
      response("unvalidated-fixture-id")
      |> pending_record()
      |> update_in(["pending_refresh", "expires_at"], &(&1 + 3600))

    save(ctx.dir, pending)

    transport = fn _, _, _ -> flunk("invalid pending expiry must not make requests") end

    assert {:error, "ChatGPT pending refresh is invalid. Run `ipse login`."} =
             HTTP.with_transport(transport, fn -> Auth.token(ctx.dir) end)

    assert {:ok, ^pending} = Store.read(ctx.dir)
  end

  test "logout revokes the newest pending refresh and clears all session markers", ctx do
    saved = pending_record(response("unvalidated-fixture-id"))
    save(ctx.dir, saved)

    transport = fn
      :get, "https://auth.openai.com/.well-known/openid-configuration", _ ->
        {:ok, discovery()}

      :post, "https://auth.openai.com/oauth/revoke", fields ->
        assert fields["token"] == "rotated-fixture-refresh"
        {:ok, %{}}
    end

    assert :ok = HTTP.with_transport(transport, fn -> Auth.logout(ctx.dir) end)
    {:ok, clean} = Store.read(ctx.dir)

    for key <- ~w(pending_refresh access_token refresh_token id_token expires_at scopes),
        do: refute(Map.has_key?(clean, key))

    for key <- ~w(client_id subject email ext_agent_host_id), do: assert(clean[key] == saved[key])
  end

  test "malformed optional tokens never activate or create a pending rotation", ctx do
    for field <- ["id_token", "refresh_token"], value <- [false, 17, %{}, [], ""] do
      saved = record()
      save(ctx.dir, saved)
      invalid = Map.put(response("fixture-id"), field, value)

      transport = fn
        :post, "https://auth.openai.com/api/accounts/oauth/token", _ -> {:ok, invalid}
        _, _, _ -> flunk("malformed token response must fail before identity fetching")
      end

      assert {:error, error} = HTTP.with_transport(transport, fn -> Auth.token(ctx.dir) end)
      assert error =~ "invalid token response"
      assert {:ok, ^saved} = Store.read(ctx.dir)

      pending = pending_record(invalid)
      save(ctx.dir, pending)

      no_requests = fn _, _, _ ->
        flunk("saved malformed pending response must not reach the network")
      end

      assert {:error, pending_error} =
               HTTP.with_transport(no_requests, fn -> Auth.token(ctx.dir) end)

      assert pending_error =~ "invalid token response"
      assert {:ok, ^pending} = Store.read(ctx.dir)
    end
  end

  test "successful fresh login replaces pending rotation without adopting its identity", ctx do
    save(ctx.dir, pending_record(response("unvalidated-fixture-id")))

    output = fn message ->
      [_, url | _] = String.split(message, "\n")
      params = URI.decode_query(URI.parse(url).query)
      Process.put(:pending_login_nonce, params["nonce"])
      spawn_link(fn -> callback(params) end)
    end

    transport = fn
      :post, "https://auth.openai.com/api/accounts/oauth/token", fields ->
        assert fields["grant_type"] == "authorization_code"

        fresh =
          response(sign(ctx.key, Map.put(claims(), "nonce", Process.get(:pending_login_nonce))))

        {:ok, Map.put(fresh, "access_token", "fresh-login-access")}

      method, url, fields ->
        identity_transport(ctx).(method, url, fields)
    end

    assert :ok = HTTP.with_transport(transport, fn -> Auth.login(ctx.dir, output: output) end)
    {:ok, clean} = Store.read(ctx.dir)
    refute Map.has_key?(clean, "pending_refresh")
    assert clean["access_token"] == "fresh-login-access"
    assert clean["subject"] == "fixture-account"
  end

  defp identity_transport(ctx) do
    fn
      :get, "https://auth.openai.com/.well-known/openid-configuration", _ ->
        {:ok, discovery()}

      :get, "https://auth.openai.com/.well-known/jwks.json", _ ->
        {:ok, ctx.jwks}

      method, _url, _fields ->
        flunk("pending resolution must not repeat token exchange: #{method}")
    end
  end

  defp save(dir, record), do: Store.with_lock(dir, fn -> Store.write(dir, record) end)

  defp pending_record(response) do
    now = System.system_time(:second)

    Map.put(record(), "pending_refresh", %{
      "response" => response,
      "received_at" => now,
      "expires_at" => now + 3600
    })
  end

  defp record do
    %{
      "access_token" => "old-fixture-access",
      "refresh_token" => "old-fixture-refresh",
      "id_token" => "old-fixture-id",
      "client_id" => "oaiapp_fixture",
      "subject" => "fixture-account",
      "issuer" => "https://auth.openai.com",
      "email" => "pending@example.test",
      "expires_at" => 0,
      "scopes" => ["chatgpt.tokens.use.direct"],
      "ext_agent_host_id" => "fixture-host"
    }
  end

  defp response(id),
    do: %{
      "access_token" => "rotated-fixture-access",
      "refresh_token" => "rotated-fixture-refresh",
      "id_token" => id,
      "expires_in" => 3600,
      "token_type" => "Bearer",
      "scope" => "openid chatgpt.tokens.use.direct"
    }

  defp discovery,
    do: %{
      "issuer" => "https://auth.openai.com",
      "jwks_uri" => "https://auth.openai.com/.well-known/jwks.json",
      "revocation_endpoint" => "https://auth.openai.com/oauth/revoke"
    }

  defp claims,
    do: %{
      "iss" => "https://auth.openai.com",
      "sub" => "fixture-account",
      "aud" => "oaiapp_fixture",
      "email" => "pending@example.test",
      "exp" => System.system_time(:second) + 3600
    }

  defp encode(value), do: value |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp sign(key, claims) do
    data = encode(%{"alg" => "RS256", "kid" => "pending-fixture"}) <> "." <> encode(claims)
    data <> "." <> Base.url_encode64(:public_key.sign(data, :sha256, key), padding: false)
  end

  defp callback(params) do
    uri = URI.parse(params["redirect_uri"])

    query =
      URI.encode_query(%{
        "state" => params["state"],
        "client_id" => params["client_id"],
        "code" => "fixture-code"
      })

    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, uri.port, [:binary, active: false], 2_000)
    :ok = :gen_tcp.send(socket, "GET #{uri.path}?#{query} HTTP/1.1\r\n\r\n")
    :gen_tcp.recv(socket, 0, 2_000)
    :gen_tcp.close(socket)
  end
end
