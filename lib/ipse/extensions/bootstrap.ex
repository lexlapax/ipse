defmodule Ipse.Extensions.Bootstrap do
  @moduledoc false

  # This entrypoint runs only inside a separately launched, explicitly trusted VM.
  def main do
    {:ok, _} = Application.ensure_all_started(:elixir)
    :ok = :io.setopts(:standard_io, binary: true, encoding: :latin1)
    [path, name] = :init.get_plain_arguments() |> Enum.map(&List.to_string/1)
    true = Code.prepend_path(Path.join(path, "ebin"))
    module = String.to_atom("Elixir." <> name)
    Code.ensure_loaded!(module)
    loop(module, nil, false)
  rescue
    _ -> System.halt(1)
  catch
    _, _ -> System.halt(1)
  end

  defp loop(module, state, initialized) do
    with <<size::unsigned-big-32>> when size <= 32_768 <- IO.binread(:stdio, 4),
         bytes when is_binary(bytes) and byte_size(bytes) == size <- IO.binread(:stdio, size),
         {:ok, %{"protocol" => 1, "id" => id, "stage" => stage, "payload" => payload}} <-
           Jason.decode(bytes),
         true <- is_integer(id) and is_binary(stage) and is_map(payload) do
      {result, next, ready} = dispatch(module, stage, payload, state, initialized)
      bytes = Jason.encode!(%{"protocol" => 1, "id" => id, "result" => result})
      true = byte_size(bytes) <= 32_768
      :ok = IO.binwrite(:stdio, <<byte_size(bytes)::unsigned-big-32, bytes::binary>>)
      loop(module, next, ready)
    else
      _ -> System.halt(1)
    end
  end

  defp dispatch(module, "initialize", options, nil, false) do
    description = module.describe()
    {:ok, state} = module.init(options)
    {description, state, true}
  end

  defp dispatch(module, stage, payload, state, true) when stage != "initialize" do
    {:ok, result, state} = module.handle(stage, payload, state)
    {result, state, true}
  end
end
