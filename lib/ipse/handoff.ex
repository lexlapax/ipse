defmodule Ipse.Handoff do
  @moduledoc "Explicit bounded operator-written recovery notes; never transcript replay or permission transfer."
  alias Ipse.{Journal, Session}
  @note_bytes 8192
  @max_unknown 16

  def export(dir, id, note) when is_binary(note) do
    with true <-
           String.valid?(note) and byte_size(note) <= @note_bytes and String.trim(note) != "",
         {:ok, events} <- Journal.load(dir, id),
         {:ok, messages} <- Session.restore_context(events),
         {:ok, _} <- Ipse.Research.restore(events) do
      unknown = Enum.filter(messages, &(get_in(&1, ["ipse_tool_outcome", "status"]) == "unknown"))

      artifact = %{
        "version" => 1,
        "source_session_id" => id,
        "source_events_sha256" => Ipse.Compaction.digest(events),
        "note" => note,
        "requires_effect_review" => true,
        "unknown_tool_count" => length(unknown),
        "unknown_call_ids" =>
          Enum.take(Enum.map(unknown, &safe_id(&1["tool_call_id"])), @max_unknown),
        "unknown_ids_omitted" => max(length(unknown) - @max_unknown, 0)
      }

      if byte_size(Jason.encode!(artifact, pretty: true)) + 1 <= 16_384,
        do: {:ok, artifact},
        else: {:error, "Encoded handoff exceeds 16 KiB; shorten the operator note."}
    else
      false -> {:error, "Supply a nonempty UTF-8 operator note of at most 8192 bytes."}
      {:error, _} = error -> error
    end
  rescue
    _ -> {:error, :invalid_handoff_source}
  end

  def export(_, _, _), do: {:error, "Supply an explicit operator note with --note."}

  defp safe_id(id) when is_binary(id) do
    if byte_size(id) <= 256 and Regex.match?(~r/\A[A-Za-z0-9_.:-]+\z/, id),
      do: id,
      else: "sha256:" <> Base.encode16(:crypto.hash(:sha256, id), case: :lower)
  end

  defp safe_id(_), do: "unavailable"
end
