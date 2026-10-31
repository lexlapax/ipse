defmodule Ipse.Extension.Context do
  @moduledoc "Bounded session context with explicit assertions and receipt-bound excerpts."
  alias Ipse.{Extension}
  @error {:error, :invalid_extension_context}
  @limit 16_384

  @doc "Bounded host capacity facts without another publisher's text."
  def available(contexts, instance, layout) do
    others = Map.delete(contexts, instance)
    occupied = if map_size(others) == 0, do: 0, else: rendered_bytes(others, layout)

    %{
      "version" => 1,
      "instance" => instance,
      "limit_bytes" => @limit,
      "occupied_other_bytes" => occupied,
      "available_bytes" => max(@limit - occupied, 0),
      "max_items" => 8,
      "max_text_bytes" => 2048
    }
  end

  @doc "Conservative final rendered size for public SDK packing; hex receipt fields have fixed lengths."
  def preview_bytes(items, instance), do: Extension.context_rendered_bytes(items, instance)

  def available?(value) do
    keys?(
      value,
      ~w(version instance limit_bytes occupied_other_bytes available_bytes max_items max_text_bytes)
    ) and
      value["version"] === 1 and is_binary(value["instance"]) and
      byte_size(value["instance"]) in 1..64 and
      value["limit_bytes"] === @limit and value["max_items"] === 8 and
      value["max_text_bytes"] === 2048 and
      is_integer(value["occupied_other_bytes"]) and value["occupied_other_bytes"] in 0..@limit and
      value["available_bytes"] === @limit - value["occupied_other_bytes"]
  rescue
    _ -> false
  end

  def validate(request) do
    with :ok <- Extension.validate(request),
         true <- keys?(request, ~w(op items)),
         true <- request["op"] == "context.publish",
         items when is_list(items) <- request["items"],
         true <- length(items) <= 8 and Enum.all?(items, &item?/1),
         true <- length(items) == length(Enum.uniq_by(items, & &1["id"])) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Replace caller session context using host-admitted prior actions; no external IO or retrieval."
  def publish(contexts, identity, request, actions, operation_id, layout \\ nil) do
    with :ok <- validate(request),
         true <- Ipse.Extension.Registry.valid_identity?(identity) and id?(operation_id),
         {:ok, items} <- admit_items(request["items"], identity, actions, operation_id),
         next = replace(contexts, identity["instance"], items),
         value = %{"items" => items, "snapshot_sha256" => Ipse.JSON.digest([next])},
         true <- rendered_bytes(next, layout) <= @limit,
         :ok <-
           Extension.validate(%{
             "api_version" => 1,
             "invocation_id" => operation_id,
             "operation_id" => operation_id,
             "step" => 16,
             "outcome" => %{"status" => "ok", "value" => value}
           }) do
      {:ok, value, next}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def execute(context, intent) do
    case publish(
           context.contributions,
           context.identity,
           intent["request"],
           context.actions,
           intent["operation_id"],
           Map.get(context, :reference_layout)
         ) do
      {:ok, value, _} -> {:ok, value}
      _ -> {:failed, %{"reason" => "context_refused"}}
    end
  end

  def valid_outcome?(_request, "unknown", value, _), do: value == %{}
  def valid_outcome?(_request, "failed", value, _), do: value == %{"reason" => "context_refused"}

  def valid_outcome?(request, "ok", value, operation_id) do
    validate(request) == :ok and keys?(value, ~w(items snapshot_sha256)) and
      Ipse.JSON.sha256?(value["snapshot_sha256"]) and is_list(value["items"]) and
      length(value["items"]) == length(request["items"]) and
      Enum.all?(Enum.zip(request["items"], value["items"]), fn {input, admitted} ->
        keys?(admitted, ~w(id version text priority source provenance)) and
          Map.delete(admitted, "provenance") == input and
          keys?(
            admitted["provenance"],
            ~w(instance identity_sha256 operation_id source_action_sha256)
          ) and
          is_binary(admitted["provenance"]["instance"]) and
          Ipse.JSON.sha256?(admitted["provenance"]["identity_sha256"]) and
          admitted["provenance"]["operation_id"] == operation_id and
          if(input["source"]["kind"] == "receipt",
            do: Ipse.JSON.sha256?(admitted["provenance"]["source_action_sha256"]),
            else: is_nil(admitted["provenance"]["source_action_sha256"])
          )
      end)
  rescue
    _ -> false
  end

  def valid_outcome?(_, _, _, _), do: false

  def apply_result(contexts, parent, actions, event, layout \\ nil) do
    case {event["request"]["op"], event["outcome"]["status"]} do
      {"context.publish", status} ->
        expected =
          publish(
            contexts,
            parent["identity"],
            event["request"],
            actions,
            event["operation_id"],
            layout
          )

        case {status, expected} do
          {"ok", {:ok, value, next}} ->
            if value == event["outcome"]["value"], do: {:ok, next}, else: @error

          {"failed", {:error, _}} ->
            {:ok, invalidate(contexts, parent, layout)}

          {"unknown", _} ->
            {:ok, invalidate(contexts, parent, layout)}

          _ ->
            @error
        end

      _ ->
        {:ok, contexts}
    end
  end

  defp invalidate(contexts, parent, "turn_reference_v1"),
    do: Map.delete(contexts, parent["identity"]["instance"])

  defp invalidate(contexts, _, _), do: contexts

  def admit_replacement(
        contexts,
        identity,
        %{"type" => "extension_action_intent", "request" => %{"op" => "context.publish"}},
        "turn_reference_v1"
      ),
      do: Map.delete(contexts, identity["instance"])

  def admit_replacement(contexts, _, _, _), do: contexts

  def rendered_bytes(contexts, "turn_reference_v1"),
    do: Ipse.Session.Reference.extension_bytes(render(contexts))

  def rendered_bytes(contexts, _), do: byte_size(render(contexts))

  def snapshot(contexts, request) do
    content = render(contexts)

    %{
      "type" => "extension_context_snapshot",
      "version" => 1,
      "request_id" => request["request_id"],
      "context_sha256" => Ipse.JSON.digest([contexts]),
      "content" => content,
      "content_sha256" => Ipse.JSON.sha256(content)
    }
  end

  def render(contexts), do: Extension.render_context(contexts)

  def summary(contexts),
    do: %{
      "items" => Enum.sum(Enum.map(contexts, fn {_, items} -> length(items) end)),
      "bytes" => byte_size(render(contexts)),
      "sha256" => Ipse.JSON.digest([contexts])
    }

  defp admit_items(items, identity, actions, operation_id) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, admitted} ->
      case source(item, actions) do
        {:ok, source_hash} ->
          provenance = %{
            "instance" => identity["instance"],
            "identity_sha256" => Ipse.JSON.digest([identity]),
            "operation_id" => operation_id,
            "source_action_sha256" => source_hash
          }

          {:cont, {:ok, admitted ++ [Map.put(item, "provenance", provenance)]}}

        _ ->
          {:halt, @error}
      end
    end)
  end

  defp source(%{"source" => %{"kind" => "assertion"}}, _), do: {:ok, nil}

  defp source(%{"source" => source, "text" => text}, actions) do
    with [action] <- Enum.filter(actions, &(&1["operation_id"] == source["operation_id"])),
         "ok" <- action["outcome"]["status"],
         value when is_binary(value) <-
           Enum.reduce(source["path"], action["outcome"]["value"], fn key, current ->
             cond do
               is_map(current) and is_binary(key) -> Map.get(current, key)
               is_list(current) and is_integer(key) -> Enum.at(current, key)
               true -> nil
             end
           end),
         true <- String.contains?(value, text) do
      {:ok, Ipse.JSON.digest([action])}
    else
      _ -> @error
    end
  end

  defp replace(contexts, instance, []), do: Map.delete(contexts, instance)
  defp replace(contexts, instance, items), do: Map.put(contexts, instance, items)

  defp item?(item) do
    keys?(item, ~w(id version text priority source)) and
      is_binary(item["id"]) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,31}\z/, item["id"]) and
      text?(item["version"], 128) and text?(item["text"], 2048) and
      is_integer(item["priority"]) and item["priority"] in 0..100 and source?(item["source"])
  end

  defp source?(%{"kind" => "assertion"} = source),
    do: keys?(source, ~w(kind uri)) and (is_nil(source["uri"]) or text?(source["uri"], 1024))

  defp source?(%{"kind" => "receipt"} = source) do
    keys?(source, ~w(kind operation_id path)) and id?(source["operation_id"]) and
      is_list(source["path"]) and length(source["path"]) <= 8 and
      Enum.all?(source["path"], &(text?(&1, 128) or (is_integer(&1) and &1 in 0..255)))
  end

  defp source?(_), do: false

  defp text?(value, max),
    do: is_binary(value) and String.valid?(value) and byte_size(value) in 1..max

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[a-f0-9]{32}\z/, value)
end
