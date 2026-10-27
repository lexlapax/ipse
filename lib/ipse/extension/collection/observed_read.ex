defmodule Ipse.Extension.Collection.ObservedRead do
  @moduledoc """
  Internal storage observations for a bounded subset of public collection reads.

  The returned result and root witness are read through the same checked
  Collection view. This component grants no Identity, Consent, source,
  eligibility or Session authority: a trusted caller must obtain and retain
  those separately, bind the observation to a committed result, and recheck the
  root before use. An observation is historical as soon as its view is closed.

  Successful `get`, `snapshot`, and visible `scan` results have the same public
  shape and value as the corresponding Collection reads at the witnessed root.
  Stale scan generations refuse instead of returning the generic conflict.
  Their availability differs:
  ReadView refuses legacy root versions 2 and 3 and indexes over its 4 MiB
  encoded-cache bound. Snapshot also reads the public `ipse.observation` key to
  obtain a same-view witness; an unreadable value there refuses observation even
  when the generic metadata-only snapshot succeeds. It never returns that value.
  Other operations refuse. Scan excludes reserved metadata before reading values.
  """
  alias Ipse.{JSON, Extension.Collection}

  @error {:error, :collection_observation_refused}
  @snapshot_probe "ipse.observation"

  @doc false
  def read(root, namespace, request) do
    with {:ok, read_request, kind} <- select(request),
         {:ok, view} <- Collection.open_view(root, namespace) do
      result =
        try do
          with {:ok, observation} <-
                 Collection.view_read(view, read_request),
               {:ok, value} <- value(kind, observation, request) do
            {:ok,
             %{
               "version" => 1,
               "request_sha256" => JSON.digest([request]),
               "result_sha256" => JSON.digest([value]),
               "value" => value,
               "witness" => observation["witness"]
             }}
          else
            _ -> @error
          end
        rescue
          _ -> @error
        catch
          _, _ -> @error
        end

      case Collection.close_view(view) do
        :ok -> result
        _ -> @error
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  defp select(%{"op" => "snapshot"} = request) do
    if Collection.valid_request?(request),
      do: {:ok, %{"op" => "get_many", "keys" => [@snapshot_probe]}, :snapshot},
      else: @error
  end

  defp select(%{"op" => "get", "key" => key} = request) do
    if Collection.valid_request?(request) and not String.starts_with?(key, "host.validity."),
      do: {:ok, %{"op" => "get_many", "keys" => [key]}, :get},
      else: @error
  end

  defp select(
         %{"op" => "scan", "after" => cursor, "limit" => limit, "generation" => generation} =
           request
       ) do
    if Collection.valid_request?(request) and limit in 1..4 and
         (is_nil(cursor) or not String.starts_with?(cursor, "host.validity.")),
       do:
         {:ok,
          %{
            "op" => "visible_scan",
            "after" => cursor,
            "limit" => limit,
            "generation" => generation
          }, :scan},
       else: @error
  end

  defp select(_), do: @error

  defp value(
         kind,
         %{"summary" => summary, "keys" => [key], "records" => [record], "witness" => witness},
         request
       )
       when kind in [:snapshot, :get] and is_map(summary) and is_map(witness) do
    case kind do
      :snapshot ->
        {:ok, summary}

      :get ->
        if(request["key"] == key, do: {:ok, Map.put(summary, "record", record)}, else: @error)
    end
  end

  defp value(
         :scan,
         %{
           "summary" => summary,
           "keys" => keys,
           "records" => records,
           "next" => next,
           "witness" => witness
         },
         request
       )
       when is_map(summary) and is_map(witness) and is_list(keys) and is_list(records) do
    if summary["generation"] === request["generation"] and length(keys) == length(records) and
         Enum.all?(keys, &(not String.starts_with?(&1, "host.validity."))),
       do: {:ok, Map.merge(summary, %{"records" => records, "next" => next})},
       else: @error
  end

  defp value(_, _, _), do: @error
end
