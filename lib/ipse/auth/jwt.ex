defmodule Ipse.Auth.JWT do
  @moduledoc false
  @issuer "https://auth.openai.com"

  # Algorithm and key type are pinned; untrusted token URLs are never followed.
  def validate(token, jwks, client_id, nonce, subject \\ nil)

  def validate(token, %{"keys" => keys}, client_id, nonce, subject) do
    with [header, payload, signature] <- String.split(token, "."),
         {:ok, header_bytes} <- decode(header),
         {:ok, %{"alg" => "RS256", "kid" => kid} = metadata} <- Jason.decode(header_bytes),
         true <- is_binary(kid) and not Map.has_key?(metadata, "crit"),
         [key] <- Enum.filter(keys, &usable_key?(&1, kid)),
         {:ok, n} <- decode(key["n"]),
         {:ok, e} <- decode(key["e"]),
         true <- byte_size(n) >= 256,
         {:ok, sig} <- decode(signature),
         true <-
           :public_key.verify(
             header <> "." <> payload,
             :sha256,
             sig,
             {:RSAPublicKey, :binary.decode_unsigned(n), :binary.decode_unsigned(e)}
           ),
         {:ok, payload_bytes} <- decode(payload),
         {:ok, claims} <- Jason.decode(payload_bytes),
         true <- valid_claims?(claims, client_id, nonce, subject) do
      {:ok, claims}
    else
      _ -> {:error, "ChatGPT identity token validation failed. Start a fresh login."}
    end
  rescue
    _ -> {:error, "ChatGPT identity token validation failed. Start a fresh login."}
  end

  def validate(_, _, _, _, _), do: {:error, "ChatGPT identity token validation failed."}

  def secure_equal?(a, b) when is_binary(a) and is_binary(b) and byte_size(a) == byte_size(b) do
    a
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(b))
    |> Enum.reduce(0, fn {x, y}, acc -> Bitwise.bor(acc, Bitwise.bxor(x, y)) end)
    |> Kernel.==(0)
  end

  def secure_equal?(_, _), do: false

  defp decode(value) when is_binary(value), do: Base.url_decode64(value, padding: false)
  defp decode(_), do: :error

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
end
