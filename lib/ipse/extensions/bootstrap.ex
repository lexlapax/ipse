defmodule Ipse.Extensions.Bootstrap do
  @moduledoc false
  alias Ipse.Extension.ResultPublication
  alias Ipse.Extension.ResultPublication.Output

  # This entrypoint runs only inside a separately launched, explicitly trusted VM.
  def main do
    {:ok, _} = Application.ensure_all_started(:elixir)
    :ok = :io.setopts(:standard_io, binary: true, encoding: :latin1)
    [path, name] = :init.get_plain_arguments() |> Enum.map(&List.to_string/1)
    true = Code.prepend_path(Path.join(path, "ebin"))
    module = String.to_atom("Elixir." <> name)
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
         true <- is_integer(id) and is_binary(stage) and is_map(payload),
         :ok <- Ipse.Extension.validate(payload) do
      {result, next, ready} = dispatch(module, stage, payload, state, initialized)
      :ok = Ipse.Extension.validate(result)
      bytes = Jason.encode!(%{"protocol" => 1, "id" => id, "result" => result})
      true = byte_size(bytes) <= 32_768
      :ok = IO.binwrite(:stdio, <<byte_size(bytes)::unsigned-big-32, bytes::binary>>)
      loop(module, next, ready)
    else
      _ -> System.halt(1)
    end
  end

  defp dispatch(module, "initialize", options, nil, false) do
    Code.ensure_loaded!(module)
    description = module.describe()
    {:ok, state} = module.init(options)

    context = %{
      domain: state,
      description: description,
      origin: nil,
      output: nil,
      producer: nil,
      awaiting_action: false
    }

    {description, context, true}
  end

  defp dispatch(_module, "result.output", payload, %{output: %Output{}} = context, true) do
    {:ok, result, producer} = ResultPublication.chunk(context.output, context.producer, payload)
    {result, %{context | producer: producer}, true}
  end

  defp dispatch(module, stage, payload, %{output: nil} = context, true)
       when stage not in ["initialize", "result.output"] do
    true =
      ResultPublication.domain_request?(
        context.description["sdk"],
        context.description["capabilities"],
        context.origin,
        context.awaiting_action,
        stage,
        payload
      )

    origin = context.origin || %{stage: stage, invocation_id: payload["invocation_id"]}

    original =
      is_nil(context.origin) or
        (stage == "host.actions" and payload["invocation_id"] === origin.invocation_id)

    {:ok, result, state} = module.handle(stage, payload, context.domain)

    case result do
      %Output{} ->
        true =
          original and
            ResultPublication.eligible?(
              context.description["sdk"],
              context.description["capabilities"],
              origin.stage
            )

        {:ok, offer} = ResultPublication.offer(result)
        {:ok, producer} = ResultPublication.open(offer, origin.invocation_id)

        {offer, %{context | domain: nil, origin: origin, output: result, producer: producer},
         true}

      result when is_map(result) ->
        true = result["kind"] not in ~w(result_producer result_chunk)

        {result,
         %{
           context
           | domain: state,
             origin: origin,
             awaiting_action: result["kind"] == "host_call"
         }, true}
    end
  end
end
