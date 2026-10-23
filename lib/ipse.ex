defmodule Ipse do
  @moduledoc "Public runtime identity, available without Git or a development toolchain."

  @commit (case System.get_env("IPSE_BUILD_COMMIT") do
             value when is_binary(value) ->
               if Regex.match?(~r/\A[0-9a-f]{40,64}\z/, value), do: value

             _ ->
               nil
           end)

  def version, do: Application.spec(:ipse, :vsn) |> to_string()

  def build_info do
    {_, os} = :os.type()
    architecture = :erlang.system_info(:system_architecture) |> to_string()
    arch = architecture |> String.split("-") |> hd()
    arch = if os == :darwin and arch == "aarch64", do: "arm64", else: arch

    %{
      "version" => version(),
      "otp_release" => :erlang.system_info(:otp_release) |> to_string(),
      "elixir" => System.version(),
      "os" => to_string(os),
      "arch" => arch,
      "commit" => @commit
    }
  end
end
