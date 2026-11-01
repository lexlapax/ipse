defmodule Ipse.Provider.MintOwned do
  @moduledoc false

  alias Ipse.Provider.{CompletionWitness, MintTransport}
  alias Ipse.Session.Resources

  @doc false
  def execute(runtime, kind, target, timeout, fun) when is_function(fun, 0) do
    with :ok <- Ipse.Provider.Ollama.Models.request_allowed?(runtime, kind),
         {:ok, capability} <- CompletionWitness.reserve_owned_child(runtime, kind, target),
         {:ok, {result, true}} <-
           Resources.controlled_owned_effect(
             Ipse.Provider.Ollama.Models.inherit_job(fn ->
               CompletionWitness.capture(runtime, kind, target, fun)
             end),
             timeout
           ),
         :ok <- CompletionWitness.complete_owned_child(runtime, kind, target, capability) do
      result
    else
      {:ok, {{:managed_native_result, {:error, :invalid_decision_response}, _} = result, false}}
      when kind == :decision ->
        # Preserve the parser's bounded diagnostic after owned-child cleanup.
        # The completion witness remains false and the reservation stays unknown.
        result

      _ ->
        {:error, "Managed inference transport did not confirm native completion and cleanup."}
    end
  rescue
    _ -> {:error, "Managed inference transport did not confirm native completion and cleanup."}
  catch
    _, _ -> {:error, "Managed inference transport did not confirm native completion and cleanup."}
  end

  # This is an internal, unwired transport/ownership seam. `admit` and `finish`
  # are trusted host callbacks; they are not worker JSON or policy grants.
  # A future caller must establish current authority at the send continuation,
  # keep publication private until settlement, and stop on unknown cleanup.
  def run(runtime, kind, url, headers, body, timeout, limit, initial, consume, admit, finish)
      when is_map(runtime) and kind in [:text, :embedding, :decision] and
             is_function(finish, 1) do
    :ok = Ipse.Provider.Ollama.Models.request_allowed?(runtime, kind)
    {:ok, capability} = CompletionWitness.reserve_owned_child(runtime, kind, url)

    scoped =
      Resources.controlled_owned_effect(
        Ipse.Provider.Ollama.Models.inherit_job(fn ->
          result =
            CompletionWitness.capture(runtime, kind, url, fn ->
              case MintTransport.stream_witnessed(
                     url,
                     headers,
                     body,
                     timeout,
                     limit,
                     initial,
                     consume,
                     admit
                   ) do
                {:ok, value} ->
                  case finish.(value) do
                    {:ok, _, _} = completed ->
                      CompletionWitness.native_complete(runtime, kind)
                      {:parsed, completed}

                    _ ->
                      {:parse_failed, :invalid_native_completion}
                  end

                {:error, reason} ->
                  {:unstarted, reason}

                {:unknown, reason} ->
                  {:uncertain, reason}
              end
            end)

          {capability, result}
        end),
        timeout
      )

    case scoped do
      {:ok, {^capability, {{:parsed, completed}, true}}} ->
        case CompletionWitness.complete_owned_child(runtime, kind, url, capability) do
          :ok -> {:settled, completed}
          _ -> {:unknown, :inference_completion_unconfirmed}
        end

      {:ok, {^capability, {{:unstarted, reason}, false}}}
      when reason in [
             :invalid_inference_request,
             :inference_connection_failed,
             :inference_request_refused
           ] ->
        {:unstarted, reason}

      {:ok, _} ->
        {:unknown, :inference_completion_unconfirmed}

      {:unknown, _} ->
        {:unknown, :inference_cleanup_unconfirmed}

      _ ->
        {:unstarted, :inference_scope_refused}
    end
  rescue
    _ -> {:unknown, :inference_completion_unconfirmed}
  catch
    _, _ -> {:unknown, :inference_completion_unconfirmed}
  end

  def run(_, _, _, _, _, _, _, _, _, _, _), do: {:unstarted, :invalid_inference_request}
end
