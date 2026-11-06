defmodule Ipse.Test.PlanningResultGate do
  @moduledoc false

  def target({:in, {:"$gen_call", _, {:append, _, event}}}) do
    with %{
           "type" => "extension_action_result",
           "request" => %{
             "op" => "collection.managed",
             "request" => %{"changes" => [%{"key" => key}]}
           },
           "outcome" => %{"status" => "ok"}
         } <- event,
         true <- is_binary(key) and String.starts_with?(key, "pending."),
         true <- Ipse.Extension.Actions.valid_result?(event) do
      {:ok, event}
    else
      _ -> :ignore
    end
  end

  def target(_), do: :ignore

  def hook(observer) do
    fn state, message, _ ->
      case target(message) do
        {:ok, event} ->
          send(observer, {:managed_result_after_dispatch, self(), event})
          receive do: (:release_planning_result_gate -> :ok)

        :ignore ->
          :ok
      end

      state
    end
  end
end
