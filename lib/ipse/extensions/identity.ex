defmodule Ipse.Extensions.Identity do
  @moduledoc "Closed activation identity shared by transforms, catalogs and owned invocations."
  @keys ~w(instance artifact artifact_sha256 options_sha256 exports_sha256 requires_sha256 subscriptions_sha256 services scope source_sha256 sdk protocol capabilities order lifetime expires_at runtime host_sha256 generation allow_children)
  @optional ~w(text_required state_binding)

  def valid?(identity) when is_map(identity) do
    Enum.sort(Map.keys(Map.drop(identity, @optional))) == Enum.sort(@keys) and
      (not Map.has_key?(identity, "text_required") or
         (is_boolean(identity["text_required"]) and "stream.text" in identity["capabilities"])) and
      (not Map.has_key?(identity, "state_binding") or
         (identity["scope"] == "operator" and
            Ipse.Extensions.State.valid_binding?(identity["state_binding"]))) and
      Ipse.Extension.validate(identity) == :ok and
      is_binary(identity["instance"]) and
      Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, identity["instance"]) and
      is_binary(identity["artifact"]) and
      Regex.match?(
        ~r/\A(?:[a-f0-9]{64}|builtin:[a-z][a-z0-9_-]{0,63}:[1-9][0-9]{0,3})\z/,
        identity["artifact"]
      ) and
      Enum.all?(
        ~w(artifact_sha256 options_sha256 exports_sha256 requires_sha256 subscriptions_sha256 source_sha256 host_sha256),
        &hash?(identity[&1])
      ) and
      Ipse.Extensions.Services.public_bindings?(identity["services"]) and
      identity["scope"] in ~w(operator project) and
      identity["sdk"] === 1 and identity["protocol"] === 1 and identity["generation"] === 1 and
      is_list(identity["capabilities"]) and
      ("host.state.bound" not in identity["capabilities"] or
         Map.has_key?(identity, "state_binding")) and
      Enum.all?(identity["capabilities"], &(&1 in Ipse.Extensions.Catalog.capabilities())) and
      length(identity["capabilities"]) == length(Enum.uniq(identity["capabilities"])) and
      is_integer(identity["order"]) and identity["order"] in 0..1000 and
      identity["lifetime"] in ~w(session persistent) and is_boolean(identity["allow_children"]) and
      (is_nil(identity["expires_at"]) or
         (is_integer(identity["expires_at"]) and identity["expires_at"] >= 0)) and
      runtime?(identity["runtime"])
  rescue
    _ -> false
  end

  def valid?(_), do: false
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[a-f0-9]{64}\z/, value)

  defp runtime?(runtime) when is_map(runtime) do
    Enum.sort(Map.keys(runtime)) == ~w(architecture elixir erts otp) and
      Enum.all?(Map.values(runtime), &(is_binary(&1) and byte_size(&1) in 1..256))
  end

  defp runtime?(_), do: false
end
