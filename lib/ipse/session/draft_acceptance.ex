defmodule Ipse.Session.DraftAcceptance do
  @moduledoc false
  alias Ipse.{JSON, Usage}

  def render(draft, channel) do
    code = Usage.id()
    id = Usage.id()

    if id?(channel) and is_map(draft) and Ipse.Session.Draft.text?(draft.proposal) do
      {:ok,
       %{
         "version" => 1,
         "render_id" => id,
         "channel_id" => channel,
         "draft_id" => draft.id,
         "revision" => draft.revision,
         "code" => code,
         "display" => display(draft.proposal, code)
       }}
    else
      {:error, :invalid_draft_render}
    end
  end

  def receipt(draft, render, text, observation) do
    with true <- valid_render?(draft, render),
         true <- text == "accept " <> render["code"],
         true <- Ipse.Session.Input.valid_observation?(observation, text, 2),
         true <- observation["display_sha256"] == JSON.sha256(render["display"]) do
      {:ok,
       %{
         "version" => 1,
         "render_id" => render["render_id"],
         "channel_id" => render["channel_id"],
         "draft_id" => render["draft_id"],
         "revision" => render["revision"],
         "code" => render["code"],
         "input" => text,
         "observation" => observation
       }}
    else
      _ -> {:error, :invalid_draft_acceptance}
    end
  end

  def valid_receipt?(draft, receipt) when is_map(receipt) do
    with true <-
           Enum.sort(Map.keys(receipt)) ==
             ~w(channel_id code draft_id input observation render_id revision version),
         true <-
           receipt["version"] === 1 and id?(receipt["render_id"]) and id?(receipt["channel_id"]) and
             id?(receipt["code"]),
         {:ok, ^receipt} <-
           receipt(
             draft,
             %{
               "version" => 1,
               "render_id" => receipt["render_id"],
               "channel_id" => receipt["channel_id"],
               "draft_id" => receipt["draft_id"],
               "revision" => receipt["revision"],
               "code" => receipt["code"],
               "display" => display(draft.proposal, receipt["code"])
             },
             receipt["input"],
             receipt["observation"]
           ) do
      true
    else
      _ -> false
    end
  end

  def valid_receipt?(_, _), do: false

  def validate_observation_uniqueness(events) do
    Enum.reduce_while(events, MapSet.new(), fn event, seen ->
      ids =
        case event do
          %{"type" => "input_received", "observation" => %{"event_id" => id}} ->
            [id]

          %{"type" => "draft_replaced", "version" => 2, "observation" => %{"event_id" => id}} ->
            [id]

          %{"type" => "draft_replaced", "version" => 3, "pieces" => pieces}
          when is_list(pieces) ->
            Enum.map(pieces, &get_in(&1, ["observation", "event_id"]))

          %{"type" => "operator_answer", "origin" => %{"pieces" => pieces}}
          when is_list(pieces) ->
            Enum.map(pieces, &get_in(&1, ["observation", "event_id"]))

          %{
            "type" => "draft_accepted",
            "version" => 2,
            "receipt" => %{"observation" => %{"event_id" => id}}
          } ->
            [id]

          _ ->
            []
        end

      if Enum.any?(ids, &(not id?(&1) or MapSet.member?(seen, &1))) or
           length(ids) != length(Enum.uniq(ids)),
         do: {:halt, {:error, :duplicate_operator_observation}},
         else: {:cont, Enum.reduce(ids, seen, &MapSet.put(&2, &1))}
    end)
    |> case do
      %MapSet{} -> :ok
      error -> error
    end
  end

  defp valid_render?(draft, render) when is_map(draft) and is_map(render) do
    Enum.sort(Map.keys(render)) == ~w(channel_id code display draft_id render_id revision version) and
      render["version"] === 1 and id?(render["render_id"]) and id?(render["channel_id"]) and
      id?(render["code"]) and render["draft_id"] == draft.id and
      render["revision"] === draft.revision and
      render["display"] == display(draft.proposal, render["code"])
  end

  defp valid_render?(_, _), do: false

  defp display(text, code),
    do:
      "Proposed request:\n" <>
        Ipse.CLI.Terminal.escape(text) <>
        "\n\nType accept " <> code <> " to submit this exact request.\ndraft> "

  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
end
