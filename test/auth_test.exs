defmodule Ipse.AuthTest do
  use ExUnit.Case, async: false
  alias Ipse.Auth
  alias Ipse.Auth.{HTTP, JWT, Store}

  setup_all do
    private = :public_key.generate_key({:rsa, 2048, 65_537})

    jwk = %{
      "kty" => "RSA",
      "kid" => "local-test-key",
      "alg" => "RS256",
      "use" => "sig",
      "n" => Base.url_encode64(:binary.encode_unsigned(elem(private, 2)), padding: false),
      "e" => Base.url_encode64(:binary.encode_unsigned(elem(private, 3)), padding: false)
    }

    %{private: private, jwks: %{"keys" => [jwk]}}
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "ipse-auth-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "real auth transport rejects credentials embedded in endpoint URLs" do
    assert {:error, "ChatGPT authorization endpoint is not trusted."} =
             HTTP.request(:get, "https://fixture:secret@auth.openai.com/example")
  end

  test "validates signatures, pinned algorithm, issuer, audience, expiry, nonce and subject",
       ctx do
    claims = claims("nonce")
    token = sign(ctx.private, claims)
    assert {:ok, ^claims} = JWT.validate(token, ctx.jwks, "oaiapp_test", "nonce", "account")
    assert {:error, _} = JWT.validate(token, ctx.jwks, "other-client", "nonce")
    assert {:error, _} = JWT.validate(token, ctx.jwks, "oaiapp_test", "wrong-nonce")
    assert {:error, _} = JWT.validate(token, ctx.jwks, "oaiapp_test", "nonce", "other-user")

    for change <- [
          %{"iss" => "https://attacker.invalid"},
          %{"exp" => 0},
          %{"sub" => ""},
          %{"aud" => ["oaiapp_test", "other"], "azp" => "other"}
        ] do
      assert {:error, _} =
               JWT.validate(
                 sign(ctx.private, Map.merge(claims, change)),
                 ctx.jwks,
                 "oaiapp_test",
                 "nonce"
               )
    end

    [header, _payload, signature] = String.split(token, ".")
    tampered = header <> "." <> encode(Map.put(claims, "sub", "attacker")) <> "." <> signature
    assert {:error, _} = JWT.validate(tampered, ctx.jwks, "oaiapp_test", "nonce")

    assert {:error, _} =
             JWT.validate(sign(ctx.private, claims, "HS256"), ctx.jwks, "oaiapp_test", "nonce")

    refute JWT.secure_equal?("state", "different")
    refute JWT.secure_equal?(nil, "state")
  end

  test "new login uses PKCE loopback and issued client; ignores forged state and saves protected identity",
       ctx do
    output = fn message ->
      [_, url | _] = String.split(message, "\n")
      params = URI.parse(url).query |> URI.decode_query()
      assert params["client_id"] == "dynamic_agent_client"
      assert params["agent_name_hint"] == "Ipse"
      assert params["code_challenge_method"] == "S256"
      assert params["resource"] == "https://api.openai.com/v1"

      assert params["ext_agent_host_id"] =~
               ~r/^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

      Process.put(:test_authorization, params)

      spawn_link(fn ->
        callback(params, %{"state" => "forged", "code" => "do-not-use", "client_id" => "attacker"})

        callback(params, %{
          "state" => params["state"],
          "code" => "valid-code",
          "client_id" => "oaiapp_test"
        })
      end)
    end

    transport = fn method, url, fields ->
      case {method, url} do
        {:post, "https://auth.openai.com/api/accounts/oauth/token"} ->
          params = Process.get(:test_authorization)
          assert fields["code"] == "valid-code"
          assert fields["client_id"] == "oaiapp_test"
          assert fields["redirect_uri"] == params["redirect_uri"]

          assert Base.url_encode64(:crypto.hash(:sha256, fields["code_verifier"]), padding: false) ==
                   params["code_challenge"]

          {:ok, response(sign(ctx.private, claims(params["nonce"])))}

        {:get, "https://auth.openai.com/.well-known/openid-configuration"} ->
          {:ok, discovery()}

        {:get, "https://auth.openai.com/.well-known/jwks.json"} ->
          {:ok, ctx.jwks}
      end
    end

    assert :ok = HTTP.with_transport(transport, fn -> Auth.login(ctx.dir, output: output) end)
    assert {:ok, "access-secret"} = Auth.token(ctx.dir)
    assert {:ok, info} = Auth.status(ctx.dir)
    assert info.email == "local@example.test"
    refute Map.has_key?(info, :access_token)
    assert {:ok, %{mode: mode}} = File.stat(Path.join(ctx.dir, "chatgpt.json"))
    assert Bitwise.band(mode, 0o777) == 0o600
    assert {:ok, saved} = Store.read(ctx.dir)
    assert saved["subject"] == "account"
    assert saved["client_id"] == "oaiapp_test"
    # flock files remain in place so every process locks the same inode.
    lock_path = Path.join(ctx.dir, ".chatgpt.lock")
    assert File.regular?(lock_path)
    assert {:ok, lock} = Ipse.Runner.lock(lock_path)
    assert :ok = Ipse.Runner.unlock(lock)
  end

  test "returning login preserves host and registration and rejects replacement client", ctx do
    saved = record()
    save(ctx.dir, saved)

    output = fn message ->
      [_, url | _] = String.split(message, "\n")
      params = URI.parse(url).query |> URI.decode_query()
      assert params["client_id"] == saved["client_id"]
      assert params["ext_agent_host_id"] == saved["ext_agent_host_id"]
      refute Map.has_key?(params, "agent_name_hint")
      refute Map.has_key?(params, "id_token_hint")

      spawn_link(fn ->
        callback(params, %{
          "state" => params["state"],
          "code" => "code",
          "client_id" => "different"
        })
      end)
    end

    transport = fn _, _, _ -> flunk("replacement registration must not reach token exchange") end

    assert {:error, error} =
             HTTP.with_transport(transport, fn -> Auth.login(ctx.dir, output: output) end)

    assert error =~ "different registration"
    assert {:ok, ^saved} = Store.read(ctx.dir)
  end

  test "rotating refresh is serialized and atomically replaces the entire token set", ctx do
    save(ctx.dir, Map.put(record(), "expires_at", 0))
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    on_exit(fn -> if Process.alive?(counter), do: Agent.stop(counter) end)

    transport = fn :post, "https://auth.openai.com/api/accounts/oauth/token", fields ->
      Agent.update(counter, &(&1 + 1))
      assert fields["grant_type"] == "refresh_token"
      assert fields["refresh_token"] == "refresh-secret"
      assert fields["client_id"] == "oaiapp_test"
      refute Map.has_key?(fields, "scope")
      Process.sleep(100)

      {:ok,
       %{
         "access_token" => "new-access",
         "refresh_token" => "new-refresh",
         "expires_in" => 3600,
         "token_type" => "Bearer"
       }}
    end

    tasks =
      for _ <- 1..2,
          do: Task.async(fn -> HTTP.with_transport(transport, fn -> Auth.token(ctx.dir) end) end)

    assert Enum.map(tasks, &Task.await(&1, 5_000)) == [{:ok, "new-access"}, {:ok, "new-access"}]
    assert Agent.get(counter, & &1) == 1
    assert {:ok, saved} = Store.read(ctx.dir)
    assert saved["refresh_token"] == "new-refresh"
    assert saved["access_token"] == "new-access"
    assert saved["expires_at"] > System.system_time(:second)
  end

  test "refresh failure preserves credentials without exposing response secrets", ctx do
    saved = Map.put(record(), "expires_at", 0)
    save(ctx.dir, saved)

    transport = fn _, _, _ ->
      {:error, "ChatGPT authorization returned HTTP 400. Sign in again if the session expired."}
    end

    assert {:error, error} = HTTP.with_transport(transport, fn -> Auth.token(ctx.dir) end)
    refute error =~ "refresh-secret"
    assert {:ok, ^saved} = Store.read(ctx.dir)
  end

  test "logout revokes refresh token and retains registration while clearing local tokens", ctx do
    saved = record()
    save(ctx.dir, saved)

    transport = fn method, url, fields ->
      case {method, url} do
        {:get, "https://auth.openai.com/.well-known/openid-configuration"} ->
          {:ok, discovery()}

        {:post, "https://auth.openai.com/oauth/revoke"} ->
          assert fields == %{
                   "token" => "refresh-secret",
                   "token_type_hint" => "refresh_token",
                   "client_id" => "oaiapp_test"
                 }

          {:ok, %{}}
      end
    end

    assert :ok = HTTP.with_transport(transport, fn -> Auth.logout(ctx.dir) end)
    assert {:ok, clean} = Store.read(ctx.dir)
    assert clean["client_id"] == saved["client_id"]
    assert clean["ext_agent_host_id"] == saved["ext_agent_host_id"]
    refute Map.has_key?(clean, "refresh_token")
    refute Map.has_key?(clean, "id_token")
    assert {:error, _} = Auth.token(ctx.dir)
  end

  test "fails closed on denied usage permission and permissive credential files", ctx do
    save(ctx.dir, Map.put(record(), "scopes", ["openid"]))
    assert {:error, error} = Auth.token(ctx.dir)
    assert error =~ "not authorized"
    File.chmod!(Path.join(ctx.dir, "chatgpt.json"), 0o644)
    assert {:error, error} = Auth.token(ctx.dir)
    assert error =~ "owner-only"
  end

  test "unconfirmed remote revocation clears local secrets and explains recovery", ctx do
    save(ctx.dir, record())
    transport = fn _, _, _ -> {:error, "Network unavailable."} end
    assert {:error, error} = HTTP.with_transport(transport, fn -> Auth.logout(ctx.dir) end)
    assert error =~ "Signed out locally"
    assert error =~ "ChatGPT Settings"
    assert {:ok, clean} = Store.read(ctx.dir)
    for key <- ["access_token", "refresh_token", "id_token"], do: refute(Map.has_key?(clean, key))
    assert clean["client_id"] == "oaiapp_test"
  end

  defp save(dir, record), do: Store.with_lock(dir, fn -> Store.write(dir, record) end)

  defp claims(nonce),
    do: %{
      "iss" => "https://auth.openai.com",
      "aud" => "oaiapp_test",
      "sub" => "account",
      "email" => "local@example.test",
      "exp" => System.system_time(:second) + 3600,
      "nonce" => nonce
    }

  defp encode(value), do: value |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp sign(key, claims, algorithm \\ "RS256") do
    data = encode(%{"alg" => algorithm, "kid" => "local-test-key"}) <> "." <> encode(claims)
    data <> "." <> Base.url_encode64(:public_key.sign(data, :sha256, key), padding: false)
  end

  defp response(id_token),
    do: %{
      "access_token" => "access-secret",
      "refresh_token" => "refresh-secret",
      "id_token" => id_token,
      "token_type" => "Bearer",
      "expires_in" => 3600,
      "scope" => "openid offline_access chatgpt.tokens.use.direct"
    }

  defp record,
    do: %{
      "access_token" => "access-secret",
      "refresh_token" => "refresh-secret",
      "id_token" => "id-secret",
      "client_id" => "oaiapp_test",
      "ext_agent_host_id" => "urn:uuid:00112233-4455-4677-8899-aabbccddeeff",
      "subject" => "account",
      "issuer" => "https://auth.openai.com",
      "email" => "local@example.test",
      "expires_at" => System.system_time(:second) + 3600,
      "scopes" => ["chatgpt.tokens.use.direct"]
    }

  defp discovery,
    do: %{
      "issuer" => "https://auth.openai.com",
      "jwks_uri" => "https://auth.openai.com/.well-known/jwks.json",
      "revocation_endpoint" => "https://auth.openai.com/oauth/revoke"
    }

  defp callback(params, result) do
    uri = URI.parse(params["redirect_uri"])
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, uri.port, [:binary, active: false], 2_000)
    :ok = :gen_tcp.send(socket, "GET #{uri.path}?#{URI.encode_query(result)} HTTP/1.1\r\n\r\n")
    :gen_tcp.recv(socket, 0, 2_000)
    :gen_tcp.close(socket)
  end
end
