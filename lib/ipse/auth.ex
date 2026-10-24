defmodule Ipse.Auth do
  @moduledoc """
  Sign in with ChatGPT for an open-source, locally hosted Ipse instance.

  This version retains one selected ChatGPT registration. Reauthorization must
  match its verified account identity; logout retains the registration and host.

  Protocol: https://developers.openai.com/siwc/token-sharing-open-source/sign-in
  Sessions: https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions
  """

  @issuer "https://auth.openai.com"
  @resource "https://api.openai.com/v1"
  @token_endpoint @issuer <> "/api/accounts/oauth/token"
  @scope "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
  @usage_scope "chatgpt.tokens.use.direct"
  @terminal_refresh_errors ~w(invalid_grant invalid_refresh_token token_expired refresh_token_expired refresh_token_invalidated refresh_token_reused)
  @token_fields ~w(access_token refresh_token id_token expires_at expires_in scopes token_type saved_at pending_refresh)

  @doc "Print a browser sign-in URL and await its loopback callback for five minutes."
  def login(auth_dir, opts \\ []) do
    snapshot =
      with_credential_lock(auth_dir, fn ->
        with {:ok, existing} <- read_credentials(auth_dir), do: ensure_host(auth_dir, existing)
      end)

    with {:ok, existing} <- snapshot,
         {:ok, listener} <-
           :gen_tcp.listen(0, [
             :binary,
             active: false,
             packet: :line,
             packet_size: 16_384,
             ip: {127, 0, 0, 1},
             reuseaddr: true,
             backlog: 5
           ]) do
      try do
        {:ok, {{127, 0, 0, 1}, port}} = :inet.sockname(listener)
        host_label = host_label()

        pending = %{
          state: random(),
          nonce: random(),
          verifier: random(),
          redirect_uri: "http://127.0.0.1:#{port}/auth/callback",
          client_id: existing["client_id"],
          registration_name: host_label
        }

        url = authorization_url(existing, pending)
        # The printed URL never includes an ID token hint or credentials.
        output = Keyword.get(opts, :output, &IO.puts/1)

        naming =
          if pending.client_id,
            do: "This machine: #{host_label}.",
            else:
              "This machine: #{host_label}. New registration name: #{host_label}. Review or edit this suggestion in the browser before approving."

        output.(
          "Continue with ChatGPT:\n#{url}\n#{naming}\nWaiting up to five minutes for browser sign-in…"
        )

        deadline = System.monotonic_time(:millisecond) + 300_000

        with {:ok, callback} <- await_callback(listener, pending, deadline) do
          with_credential_lock(auth_dir, fn ->
            with {:ok, current} <- read_credentials(auth_dir),
                 true <- current == existing do
              complete_login(auth_dir, existing, pending, callback)
            else
              false ->
                {:error,
                 "ChatGPT credentials changed while sign-in was pending. Run `ipse login` again."}

              error ->
                error
            end
          end)
        end
      after
        :gen_tcp.close(listener)
      end
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      _ -> {:error, "Could not start the ChatGPT loopback callback listener."}
    end
  rescue
    _ -> {:error, "ChatGPT sign-in failed. Retry the login command."}
  end

  @doc false
  def host_label(host \\ :inet.gethostname())

  def host_label({:ok, hostname}) when is_list(hostname) do
    short = hostname |> List.to_string() |> String.split(".", parts: 2) |> hd()

    if Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9_-]{0,62}\z/, short),
      do: "ipse@" <> short,
      else: "ipse@unknown-host"
  end

  def host_label(_), do: "ipse@unknown-host"

  defp complete_login(auth_dir, existing, pending, callback) do
    with {:ok, response} <-
           auth_request(:post, @token_endpoint, %{
             "grant_type" => "authorization_code",
             "client_id" => callback["client_id"],
             "code" => callback["code"],
             "code_verifier" => pending.verifier,
             "redirect_uri" => pending.redirect_uri,
             "resource" => @resource
           }),
         {:ok, claims} <-
           validate_identity(
             response["id_token"],
             callback["client_id"],
             pending.nonce,
             existing["subject"]
           ),
         {:ok, record} <-
           token_record(
             Map.drop(existing, [
               "scopes",
               "access_token",
               "refresh_token",
               "id_token",
               "pending_refresh"
             ]),
             response,
             callback["client_id"],
             claims
           ),
         :ok <- write_credentials(auth_dir, record),
         :ok <- permitted(record) do
      :ok
    else
      {:error, {:oauth, "invalid_client"}} ->
        invalid_client()

      {:error, {:oauth, _}} ->
        {:error, "ChatGPT sign-in grant was rejected or expired. Run `ipse login`."}

      error ->
        error
    end
  end

  @doc "Return a usable access token, serializing refreshes across OS processes."
  def token(auth_dir) do
    with_credential_lock(auth_dir, fn ->
      with {:ok, record} <- read_credentials(auth_dir),
           {:ok, record} <- resolve_pending(auth_dir, record),
           :ok <- signed_in(record),
           :ok <- permitted(record) do
        expires_at = record["expires_at"]

        if is_integer(expires_at) and expires_at > System.system_time(:second) + 60 do
          {:ok, record["access_token"]}
        else
          refresh(auth_dir, record)
        end
      end
    end)
  rescue
    _ -> {:error, "Could not load or refresh ChatGPT credentials. Sign in again."}
  end

  @doc "Return selected account information without tokens or secrets."
  def status(auth_dir) do
    with {:ok, record} <- read_credentials(auth_dir), :ok <- signed_in(record) do
      {:ok,
       %{
         email: record["email"],
         client_id: record["client_id"],
         label: record["email"] || "ChatGPT account",
         expires_at: record["expires_at"],
         plan_usage: @usage_scope in (record["scopes"] || [])
       }}
    end
  rescue
    _ -> {:error, "Could not read ChatGPT account status."}
  end

  @doc "Revoke the renewable session and clear local tokens while retaining registration."
  def logout(auth_dir) do
    with_credential_lock(auth_dir, fn ->
      with {:ok, record} <- read_credentials(auth_dir) do
        remote = revoke(revocation_record(record))

        clean = record |> Map.drop(@token_fields) |> Map.put("authorization_epoch", random())

        with :ok <- write_credentials(auth_dir, clean) do
          case remote do
            :ok ->
              :ok

            _ ->
              {:error,
               "Signed out locally; remote revocation could not be confirmed. Disconnect Ipse in ChatGPT Settings to end remote access."}
          end
        end
      end
    end)
  rescue
    _ -> {:error, "Could not sign out of ChatGPT."}
  end

  defp signed_in(record) do
    if nonempty?(record["access_token"]) and nonempty?(record["client_id"]) and
         record["client_id"] != "dynamic_agent_client" and nonempty?(record["subject"]) do
      :ok
    else
      {:error, "No ChatGPT session. Run `ipse login`."}
    end
  end

  defp permitted(record) do
    if is_list(record["scopes"]) and @usage_scope in record["scopes"] do
      :ok
    else
      {:error,
       "ChatGPT plan usage was not authorized. Sign in again and allow plan usage in ChatGPT Settings."}
    end
  end

  defp refresh(auth_dir, record) do
    if nonempty?(record["refresh_token"]) do
      case auth_request(:post, @token_endpoint, %{
             "grant_type" => "refresh_token",
             "client_id" => record["client_id"],
             "refresh_token" => record["refresh_token"],
             "resource" => @resource
           }) do
        {:ok, response} ->
          with {:ok, pending} <- persist_pending(auth_dir, record, response),
               {:ok, next} <- resolve_pending(auth_dir, pending),
               :ok <- permitted(next) do
            {:ok, next["access_token"]}
          end

        {:error, {:oauth, code}} when code in @terminal_refresh_errors ->
          with :ok <- write_credentials(auth_dir, Map.drop(record, @token_fields)) do
            {:error, "ChatGPT session expired or was revoked. Run `ipse login`."}
          end

        {:error, {:oauth, "invalid_client"}} ->
          invalid_client()

        error ->
          error
      end
    else
      {:error, "ChatGPT session cannot refresh. Run `ipse login`."}
    end
  end

  defp persist_pending(auth_dir, record, response) do
    # Validate the token response shape without activating its unverified ID
    # token. Durably retain rotation before discovery/JWKS network operations.
    identity = %{
      "iss" => record["issuer"],
      "sub" => record["subject"],
      "email" => record["email"]
    }

    received = System.system_time(:second)

    with {:ok, candidate} <- token_record(record, response, record["client_id"], identity) do
      pending = %{
        "response" =>
          Map.take(response, ~w(access_token refresh_token id_token expires_in token_type scope)),
        "received_at" => received,
        "expires_at" => received + candidate["expires_in"]
      }

      next = Map.put(record, "pending_refresh", pending)
      with :ok <- write_credentials(auth_dir, next), do: {:ok, next}
    end
  end

  defp resolve_pending(auth_dir, %{"pending_refresh" => pending} = record) when is_map(pending) do
    with %{"response" => response, "received_at" => received, "expires_at" => expires} <- pending,
         true <-
           is_map(response) and is_integer(received) and is_integer(expires) and
             expires > received,
         {:ok, _candidate} <-
           token_record(record, response, record["client_id"], %{}),
         true <- expires == received + response["expires_in"],
         {:ok, claims} <- refresh_identity(response, record),
         {:ok, next} <-
           token_record(
             Map.delete(record, "pending_refresh"),
             response,
             record["client_id"],
             claims
           ) do
      # Retry time must never extend the access token lifetime granted earlier.
      next = Map.put(next, "expires_at", expires)
      with :ok <- write_credentials(auth_dir, next), do: {:ok, next}
    else
      {:error, _} = error -> error
      _ -> {:error, "ChatGPT pending refresh is invalid. Run `ipse login`."}
    end
  end

  defp resolve_pending(_auth_dir, record) do
    if Map.has_key?(record, "pending_refresh"),
      do: {:error, "ChatGPT pending refresh is invalid. Run `ipse login`."},
      else: {:ok, record}
  end

  defp revocation_record(%{"pending_refresh" => %{"response" => response}} = record)
       when is_map(response) do
    if nonempty?(response["refresh_token"]),
      do: Map.put(record, "refresh_token", response["refresh_token"]),
      else: record
  end

  defp revocation_record(record), do: record

  defp invalid_client,
    do:
      {:error,
       "ChatGPT client registration was rejected. Check the client configuration before retrying."}

  defp refresh_identity(response, record) do
    if nonempty?(response["id_token"]) do
      validate_identity(response["id_token"], record["client_id"], nil, record["subject"])
    else
      {:ok, %{"iss" => record["issuer"], "sub" => record["subject"], "email" => record["email"]}}
    end
  end

  defp token_record(existing, response, client_id, claims) do
    expires = response["expires_in"]
    type = response["token_type"]

    if nonempty?(response["access_token"]) and is_integer(expires) and expires > 0 and
         is_binary(type) and String.downcase(type) == "bearer" and
         (is_nil(response["id_token"]) or nonempty?(response["id_token"])) and
         (is_nil(response["refresh_token"]) or nonempty?(response["refresh_token"])) do
      # RFC 6749 permits omission of unchanged refresh_token and scope on renewal.
      scopes =
        case response["scope"] do
          value when is_binary(value) -> String.split(value, " ", trim: true)
          nil -> existing["scopes"] || []
          _ -> []
        end

      now = System.system_time(:second)

      {:ok,
       Map.merge(existing, %{
         "email" => claims["email"],
         "issuer" => claims["iss"],
         "subject" => claims["sub"],
         "client_id" => client_id,
         "access_token" => response["access_token"],
         "refresh_token" => response["refresh_token"] || existing["refresh_token"],
         "id_token" => response["id_token"] || existing["id_token"],
         "token_type" => "Bearer",
         "expires_in" => expires,
         "expires_at" => now + expires,
         "saved_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
         "authorization_epoch" => random(),
         "scopes" => scopes
       })}
    else
      {:error, "ChatGPT returned an invalid token response. Start a fresh login."}
    end
  end

  defp validate_identity(token, client_id, nonce, subject) do
    with true <- nonempty?(token),
         {:ok, discovery} <- discovery(),
         {:ok, jwks} <- auth_request(:get, discovery["jwks_uri"]) do
      validate_token(token, jwks, client_id, nonce, subject)
    else
      {:error, _} = error -> error
      _ -> {:error, "ChatGPT did not return an identity token."}
    end
  end

  defp discovery do
    with {:ok, doc} <- auth_request(:get, @issuer <> "/.well-known/openid-configuration"),
         true <- doc["issuer"] == @issuer,
         true <- trusted_endpoint?(doc["jwks_uri"]) do
      {:ok, doc}
    else
      {:error, _} = error -> error
      _ -> {:error, "ChatGPT identity discovery was invalid."}
    end
  end

  defp trusted_endpoint?(url) when is_binary(url) do
    uri = URI.parse(url)

    uri.scheme == "https" and uri.host == "auth.openai.com" and uri.port == 443 and
      is_nil(uri.userinfo) and is_nil(uri.fragment)
  end

  defp trusted_endpoint?(_), do: false

  defp revoke(record) do
    if nonempty?(record["refresh_token"]) do
      with {:ok, doc} <- discovery(), true <- trusted_endpoint?(doc["revocation_endpoint"]) do
        revoke_attempt(doc["revocation_endpoint"], record, 0)
      else
        _ -> {:error, :unconfirmed}
      end
    else
      :ok
    end
  end

  defp revoke_attempt(endpoint, record, attempt) do
    case auth_request(:post, endpoint, %{
           "token" => record["refresh_token"],
           "token_type_hint" => "refresh_token",
           "client_id" => record["client_id"]
         }) do
      {:ok, _} ->
        :ok

      _ when attempt < 2 ->
        Process.sleep(250 * (attempt + 1))
        revoke_attempt(endpoint, record, attempt + 1)

      _ ->
        {:error, :unconfirmed}
    end
  end

  defp ensure_host(dir, existing) do
    if nonempty?(existing["ext_agent_host_id"]) do
      {:ok, existing}
    else
      <<a::32, b::16, _::4, c::12, _::2, d::14, e::48>> = :crypto.strong_rand_bytes(16)

      hex = fn int, width ->
        int |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(width, "0")
      end

      uuid =
        "#{hex.(a, 8)}-#{hex.(b, 4)}-#{hex.(Bitwise.bor(c, 0x4000), 4)}-#{hex.(Bitwise.bor(d, 0x8000), 4)}-#{hex.(e, 12)}"

      next = Map.put(existing, "ext_agent_host_id", "urn:uuid:" <> uuid)
      with :ok <- write_credentials(dir, next), do: {:ok, next}
    end
  end

  defp authorization_url(existing, pending) do
    params = %{
      "client_id" => pending.client_id || "dynamic_agent_client",
      "ext_agent_host_id" => existing["ext_agent_host_id"],
      "response_type" => "code",
      "redirect_uri" => pending.redirect_uri,
      "scope" => @scope,
      "resource" => @resource,
      "state" => pending.state,
      "nonce" => pending.nonce,
      "code_challenge_method" => "S256",
      "code_challenge" =>
        :crypto.hash(:sha256, pending.verifier) |> Base.url_encode64(padding: false)
    }

    params =
      if pending.client_id,
        do: params,
        else: Map.put(params, "agent_name_hint", pending.registration_name)

    params =
      if nonempty?(existing["email"]),
        do: Map.put(params, "login_hint", existing["email"]),
        else: params

    @issuer <> "/api/accounts/authorize?" <> URI.encode_query(params)
  end

  defp await_callback(listener, pending, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    case :gen_tcp.accept(listener, remaining) do
      {:ok, socket} ->
        result =
          try do
            parse_request(socket, pending, min(remaining, 2_000))
          after
            :gen_tcp.close(socket)
          end

        case result do
          :retry -> await_callback(listener, pending, deadline)
          result -> result
        end

      {:error, :timeout} ->
        {:error, "ChatGPT sign-in timed out after five minutes. Start a fresh login."}

      _ ->
        {:error, "ChatGPT callback listener stopped unexpectedly."}
    end
  end

  defp parse_request(socket, pending, timeout) do
    with {:ok, line} <- :gen_tcp.recv(socket, 0, timeout),
         ["GET", target, "HTTP/1.1"] <- line |> String.trim() |> String.split(" "),
         %URI{path: "/auth/callback", query: query, host: nil} when is_binary(query) <-
           URI.parse(target),
         {:ok, params} <- query_params(query),
         true <- secure_equal?(params["state"], pending.state) do
      result = callback_result(params, pending.client_id)

      case result do
        {:ok, _} ->
          respond(
            socket,
            200,
            "Authorization received. Return to Ipse; it will validate your account."
          )

        _ ->
          respond(socket, 400, "Authorization was declined or invalid. Return to Ipse.")
      end

      result
    else
      _ ->
        respond(socket, 400, "Invalid callback.")
        :retry
    end
  rescue
    _ ->
      respond(socket, 400, "Invalid callback.")
      :retry
  end

  defp query_params(query) do
    pairs = URI.query_decoder(query) |> Enum.to_list()
    keys = Enum.map(pairs, &elem(&1, 0))
    if length(keys) == length(Enum.uniq(keys)), do: {:ok, Map.new(pairs)}, else: :error
  end

  defp callback_result(params, selected_client) do
    cond do
      Map.has_key?(params, "error") ->
        {:error,
         "ChatGPT authorization was declined. Start a fresh login to authorize plan usage."}

      not nonempty?(params["code"]) ->
        {:error, "ChatGPT callback did not include an authorization code."}

      selected_client && params["client_id"] not in [nil, selected_client] ->
        {:error, "ChatGPT returned a different registration. The saved account was preserved."}

      is_nil(selected_client) and
          (not nonempty?(params["client_id"]) or params["client_id"] == "dynamic_agent_client") ->
        {:error, "ChatGPT registration did not return an issued client ID. Start a fresh login."}

      true ->
        {:ok, Map.put(params, "client_id", selected_client || params["client_id"])}
    end
  end

  defp respond(socket, status, body) do
    :gen_tcp.send(
      socket,
      "HTTP/1.1 #{status} #{if status == 200, do: "OK", else: "Bad Request"}\r\n" <>
        "Content-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\n" <>
        "Content-Security-Policy: default-src 'none'\r\nConnection: close\r\nContent-Length: #{byte_size(body)}\r\n\r\n#{body}"
    )
  end

  defp random, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  defp nonempty?(value), do: is_binary(value) and byte_size(value) > 0

  @oauth_errors ~w(invalid_grant invalid_refresh_token token_expired refresh_token_expired refresh_token_invalidated refresh_token_reused invalid_client)

  @doc false
  def decode_auth_response(status, body) when status in 200..299 and is_binary(body) do
    if body == "", do: {:ok, %{}}, else: decode_auth_body(body)
  end

  def decode_auth_response(status, body) when is_integer(status) do
    code =
      if status in 400..499 and status != 429 and is_binary(body) and
           byte_size(body) <= 1_048_576 do
        case Jason.decode(body) do
          {:ok, %{"error" => error}} when is_binary(error) -> error
          {:ok, %{"error" => %{"code" => error}}} when is_binary(error) -> error
          _ -> nil
        end
      end

    if code in @oauth_errors do
      {:error, {:oauth, code}}
    else
      {:error,
       "ChatGPT authorization returned HTTP #{status}. Sign in again if the session expired."}
    end
  end

  if Code.ensure_loaded?(Mix) and Mix.env() == :test do
    def with_auth_transport(transport, fun) do
      key = {__MODULE__, :transport}
      previous = Process.put(key, transport)

      try do
        fun.()
      after
        if previous, do: Process.put(key, previous), else: Process.delete(key)
      end
    end

    def auth_request(method, url, fields \\ []) do
      case Process.get({__MODULE__, :transport}) do
        nil -> real_request(method, url, fields)
        fun -> fun.(method, url, fields)
      end
    end
  else
    def auth_request(method, url, fields \\ []), do: real_request(method, url, fields)
  end

  defp real_request(method, url, fields) do
    uri = URI.parse(url)

    if uri.scheme == "https" and uri.host == "auth.openai.com" and uri.port == 443 and
         is_nil(uri.userinfo) and is_nil(uri.fragment) and method in [:get, :post] do
      headers = [
        {"accept-encoding", "identity"},
        {"content-type", "application/x-www-form-urlencoded"}
      ]

      body = if method == :get, do: nil, else: URI.encode_query(fields)
      request = Finch.build(method, url, headers, body)

      case Ipse.HTTP.bounded_request(request, 1_048_576) do
        {:ok, status, body} ->
          decode_auth_response(status, body)

        {:error, :response_too_large} ->
          {:error, "ChatGPT authorization response exceeded the size limit."}

        _ ->
          {:error, "Could not reach ChatGPT authorization. Check your network and retry."}
      end
    else
      {:error, "ChatGPT authorization endpoint is not trusted."}
    end
  rescue
    _ -> {:error, "ChatGPT authorization request failed."}
  end

  defp decode_auth_body(body) when byte_size(body) <= 1_048_576 do
    case Jason.decode(body) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> {:error, "ChatGPT authorization returned an invalid response."}
    end
  end

  defp decode_auth_body(_),
    do: {:error, "ChatGPT authorization response exceeded the size limit."}

  # Algorithm and key type are pinned; untrusted token URLs are never followed.
  def validate_token(token, jwks, client_id, nonce, subject \\ nil)

  def validate_token(token, %{"keys" => keys}, client_id, nonce, subject)
      when is_binary(token) and byte_size(token) <= 32_768 and is_list(keys) do
    with true <- length(Enum.take(keys, 65)) in 1..64,
         [header, payload, signature] <- String.split(token, ".", parts: 4),
         true <-
           byte_size(header) <= 4_096 and byte_size(payload) <= 24_576 and
             byte_size(signature) <= 1_368,
         {:ok, header_bytes} <- decode_token_component(header),
         {:ok, %{"alg" => "RS256", "kid" => kid} = metadata} <- Jason.decode(header_bytes),
         true <-
           is_binary(kid) and byte_size(kid) in 1..256 and not Map.has_key?(metadata, "crit"),
         [key] <- Enum.filter(keys, &usable_key?(&1, kid)),
         {:ok, n} <- component(key["n"], 1_368),
         true <- byte_size(n) in 256..1_024 and :binary.first(n) > 0,
         true <- byte_size(n) > 256 or :binary.first(n) >= 128,
         {:ok, e} <- component(key["e"], 6),
         true <- byte_size(e) in 1..4 and :binary.first(e) > 0,
         exponent = :binary.decode_unsigned(e),
         true <- exponent >= 3 and rem(exponent, 2) == 1,
         {:ok, sig} <- decode_token_component(signature),
         true <- byte_size(sig) == byte_size(n),
         true <-
           :public_key.verify(
             header <> "." <> payload,
             :sha256,
             sig,
             {:RSAPublicKey, :binary.decode_unsigned(n), exponent}
           ),
         {:ok, payload_bytes} <- decode_token_component(payload),
         {:ok, claims} <- Jason.decode(payload_bytes),
         true <- valid_claims?(claims, client_id, nonce, subject) do
      {:ok, claims}
    else
      _ -> {:error, "ChatGPT identity token validation failed. Start a fresh login."}
    end
  rescue
    _ -> {:error, "ChatGPT identity token validation failed. Start a fresh login."}
  end

  def validate_token(_, _, _, _, _), do: {:error, "ChatGPT identity token validation failed."}

  def secure_equal?(a, b) when is_binary(a) and is_binary(b) and byte_size(a) == byte_size(b) do
    a
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(b))
    |> Enum.reduce(0, fn {x, y}, acc -> Bitwise.bor(acc, Bitwise.bxor(x, y)) end)
    |> Kernel.==(0)
  end

  def secure_equal?(_, _), do: false

  defp decode_token_component(value) when is_binary(value),
    do: Base.url_decode64(value, padding: false)

  defp decode_token_component(_), do: :error

  defp component(value, limit) when is_binary(value) and byte_size(value) <= limit,
    do: decode_token_component(value)

  defp component(_, _), do: :error

  defp usable_key?(key, kid) when is_map(key) do
    key["kid"] == kid and key["kty"] == "RSA" and
      key["alg"] in [nil, "RS256"] and key["use"] in [nil, "sig"] and
      (is_nil(key["key_ops"]) or "verify" in key["key_ops"])
  end

  defp usable_key?(_, _), do: false

  defp valid_claims?(claims, client, nonce, subject) when is_map(claims) do
    now = System.system_time(:second)
    audience = claims["aud"]
    aud_ok = audience == client or (is_list(audience) and client in audience)

    azp_ok =
      (not is_list(audience) or length(audience) <= 1 or claims["azp"] == client) and
        (is_nil(claims["azp"]) or claims["azp"] == client)

    claims["iss"] == @issuer and aud_ok and azp_ok and
      is_integer(claims["exp"]) and claims["exp"] > now and
      (is_nil(claims["nbf"]) or (is_integer(claims["nbf"]) and claims["nbf"] <= now + 30)) and
      (is_nil(claims["iat"]) or (is_integer(claims["iat"]) and claims["iat"] <= now + 30)) and
      is_binary(claims["sub"]) and byte_size(claims["sub"]) > 0 and
      (is_nil(nonce) or secure_equal?(claims["nonce"], nonce)) and
      (is_nil(subject) or secure_equal?(claims["sub"], subject))
  end

  defp valid_claims?(_, _, _, _), do: false

  @filename "chatgpt.json"

  def with_credential_lock(dir, fun, timeout \\ 10_000, provider \\ :chatgpt)
      when provider in [:chatgpt, :xai] do
    with :ok <- prepare_credential_dir(dir) do
      lock = Path.join(dir, ".#{provider}.lock")
      deadline = System.monotonic_time(:millisecond) + timeout
      acquire_credential_lock(lock, deadline, fun)
    end
  end

  def read_credentials(dir, provider \\ :chatgpt) when provider in [:chatgpt, :xai] do
    path = Path.join(dir, if(provider == :chatgpt, do: @filename, else: "xai.json"))

    case File.lstat(path) do
      {:error, :enoent} ->
        {:ok, %{}}

      {:ok, %{type: :regular, mode: mode, size: size}} when size <= 1_048_576 ->
        if Bitwise.band(mode, 0o077) == 0 do
          with {:ok, bytes} <- File.read(path),
               {:ok, value} when is_map(value) <- Jason.decode(bytes) do
            {:ok, value}
          else
            _ -> {:error, "ChatGPT credential file is unreadable or invalid."}
          end
        else
          {:error, "ChatGPT credential file must have owner-only permissions (chmod 600)."}
        end

      _ ->
        {:error, "ChatGPT credential path must be a regular protected file."}
    end
  end

  def write_credentials(dir, value, provider \\ :chatgpt) when provider in [:chatgpt, :xai] do
    filename = if provider == :chatgpt, do: @filename, else: "xai.json"

    with true <- File.dir?(dir),
         :ok <- Ipse.PrivateFile.write_atomic(Path.join(dir, filename), Jason.encode!(value)) do
      :ok
    else
      _ -> {:error, "Could not save protected ChatGPT credentials."}
    end
  end

  defp prepare_credential_dir(dir) do
    with :ok <- File.mkdir_p(dir),
         {:ok, %{type: :directory}} <- File.lstat(dir),
         :ok <- File.chmod(dir, 0o700) do
      :ok
    else
      _ -> {:error, "Could not prepare protected ChatGPT credential directory."}
    end
  end

  defp acquire_credential_lock(lock, deadline, fun) do
    case Ipse.Runner.lock(lock) do
      {:ok, owner} ->
        try do
          File.chmod(lock, 0o600)
          fun.()
        after
          Ipse.Runner.unlock(owner)
        end

      {:error, reason} when is_binary(reason) ->
        if String.starts_with?(reason, "cannot acquire session lock") and
             System.monotonic_time(:millisecond) < deadline do
          Process.sleep(50)
          acquire_credential_lock(lock, deadline, fun)
        else
          {:error,
           "ChatGPT credentials are busy. Retry after the other sign-in or refresh finishes."}
        end

      _ ->
        {:error, "Could not lock ChatGPT credentials."}
    end
  end
end
