defmodule Ipse.Extensions.ServiceCall do
  @moduledoc "Owned value-service contract 1 jobs; executable startup follows durable intent."
  alias Ipse.Extensions.{Worker, Services, Catalog}

  def execute(context, intent) do
    entry = context.service_entry

    payload =
      Services.payload(
        intent["request"],
        intent["service"],
        intent["operation_id"],
        intent["parent_invocation_id"],
        context.session_id,
        context.turn_id
      )

    with {:ok, worker} <-
           Worker.start(
             owner: self(),
             store: entry.store,
             digest: entry.identity["artifact"],
             trusted: entry.identity["artifact"],
             artifact_sha256: entry.identity["artifact_sha256"],
             options: entry.options
           ) do
      try do
        with {:ok, _} <- Worker.call(worker, "initialize", entry.options),
             {:ok, response} <- Worker.call(worker, "invoke.service", payload),
             {:ok, value} <- Catalog.validate_response(intent["service"]["descriptor"], response),
             :ok <- Worker.close(worker) do
          {:ok, Services.outcome(intent["service"], intent["operation_id"], value)}
        else
          _ -> {:unknown, %{}}
        end
      after
        if Process.alive?(worker), do: Worker.close(worker)
      end
    else
      _ -> {:unknown, %{}}
    end
  catch
    :exit, _ -> {:unknown, %{}}
  end
end
