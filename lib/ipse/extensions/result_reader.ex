defmodule Ipse.Extensions.ResultReader do
  @moduledoc false
  alias Ipse.Extensions.{ResultSource, ResultView}

  def definition do
    %{
      "type" => "function",
      "function" => %{
        "name" => "saved_result_read",
        "description" =>
          "Read a bounded historical view of a saved result already disclosed in this session. " <>
            "Start with output_id and path, or submit only the returned cursor. " <>
            "References preserve omitted subtrees and large names; complete applies to the requested target.",
        "parameters" => %{
          "type" => "object",
          "additionalProperties" => false,
          "properties" => %{
            "output_id" => %{"type" => "string"},
            "path" => %{"type" => "array", "maxItems" => 12, "items" => %{}},
            "offset" => %{"type" => "integer", "minimum" => 0},
            "cursor" => %{"type" => "object"}
          }
        }
      }
    }
  end

  def materialize(session, delivery) do
    with {:ok, source} <- call(session, {:saved_result_materialize, delivery}) do
      bounded(fn -> ResultSource.materialize(source, delivery) end)
    end
  end

  def saved(state_dir, session_id, output_id) do
    with {:ok, events} <- Ipse.Journal.load(state_dir, session_id),
         {:ok, _} <- Ipse.Session.restore_context(events),
         {:ok, index} <- ResultSource.restore(events),
         {:ok, source} <- ResultSource.source(index, output_id),
         delivery = ResultSource.descriptor(source),
         {:ok, source} <- ResultSource.readable_source(index, delivery) do
      bounded(fn -> ResultSource.materialize(source, delivery) end)
    else
      _ -> {:error, :saved_result_unavailable}
    end
  end

  def read(session, request) do
    with {:ok, source, delivery} <- call(session, {:saved_result_read, request}) do
      view(source, delivery, request)
    end
  end

  def model(session, job_ref, request) do
    with {:ok, source, delivery} <-
           call(session, {:saved_result_model_read, job_ref, request}),
         {:ok, result} <- view(source, delivery, request) do
      {:ok, Jason.encode!(result)}
    else
      _ -> {:error, "Saved result read refused or unavailable."}
    end
  end

  def request_id(%{"cursor" => %{"output_id" => id}}), do: id
  def request_id(%{"output_id" => id}), do: id
  def request_id(_), do: nil

  defp view(source, delivery, request) do
    bounded(fn ->
      with {:ok, %{value: value}} <- ResultSource.materialize(source, delivery),
           do: ResultView.read(value, delivery, request)
    end)
  end

  defp bounded(fun) do
    task =
      Task.async(fn ->
        try do
          fun.()
        rescue
          _ -> {:error, :saved_result_unavailable}
        catch
          _, _ -> {:error, :saved_result_unavailable}
        end
      end)

    case Task.yield(task, 5_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {:error, :saved_result_unavailable}
    end
  end

  defp call(session, request) do
    GenServer.call(session, request, 5_000)
  catch
    :exit, _ -> {:error, :saved_result_unavailable}
  end
end
