defmodule Ipse.Development.ManagedMetadata.BinaryShapes do
  alias Ipse.Development.ManagedMetadata.Shapes, as: F
  alias Ipse.Development.ManagedMetadata.Binary, as: B
  @calendar DateTime.to_unix(~U[2026-10-26 00:00:00Z], :millisecond)

  def capsule(id, policy \\ %{"kind" => "session"}) do
    challenge = "0123456789abcdef"

    verb =
      %{"pin" => "pin", "ordinary" => "ordinary", "session" => "forget", "duration" => "duration"}[
        policy["kind"]
      ]

    %{
      "version" => 2,
      "kind" => "candidate_native_management",
      "lineage" => id,
      "event_id" => String.duplicate("a", 32),
      "display_sha256" => F.hash("display-v2"),
      "challenge" => challenge,
      "target_key" => "note." <> id,
      "target_value_sha256" => F.hash("value-v2"),
      "observed_at_ms" => B.safe(),
      "policy" => policy,
      "reason" => String.duplicate("r", 64),
      "input_sha256" => Ipse.JSON.sha256(verb <> " " <> challenge)
    }
  end

  def anchor(choice \\ nil, retirement \\ nil, profile \\ :safe_width) do
    clocks =
      case profile do
        :safe_width ->
          [Bitwise.bsl(1, 49), Bitwise.bsl(1, 50), nil, nil]

        :bounded_fixture ->
          [90 * 86_400_000, 180 * 86_400_000, nil, nil]

        :calendar_2026 ->
          [@calendar, @calendar + 90 * 86_400_000, nil, nil]

        :four_safe_clocks ->
          [Bitwise.bsl(1, 49), Bitwise.bsl(1, 50), Bitwise.bsl(1, 49), Bitwise.bsl(1, 50)]
      end

    %{"clocks" => clocks, "choice" => choice, "retirement" => retirement}
  end

  def retirement(id, mode, profile \\ :safe_width) do
    at =
      case profile do
        :bounded_fixture -> 455 * 86_400_000
        :calendar_2026 -> @calendar + 365 * 86_400_000
        _ -> B.safe()
      end

    case mode do
      :none ->
        nil

      :sticky_clock ->
        %{"target_kind" => "native_literal_note", "at_ms" => at}

      :target_witness ->
        %{
          "at_ms" => at,
          "record_key" => "note." <> id,
          "record_value_sha256" => F.hash("retired value")
        }
    end
  end

  def live(n, infinite \\ false, profile \\ :safe_width, category \\ nil) do
    category = category || if(infinite, do: "pin", else: "ordinary")
    {semantic, record} = F.live(n, category)

    record =
      if category == "history",
        do: Map.update!(record, "key", &String.replace_prefix(&1, "note.", "history.")),
        else: record

    semantic = Map.put(semantic, "record_key", record["key"])

    first =
      case profile do
        :bounded_fixture -> 90 * 86_400_000
        :calendar_2026 -> @calendar
        _ -> Bitwise.bsl(1, 49)
      end

    deadline =
      cond do
        infinite -> nil
        profile == :bounded_fixture -> 180 * 86_400_000
        profile == :calendar_2026 -> @calendar + 90 * 86_400_000
        true -> Bitwise.bsl(1, 50)
      end

    semantic =
      semantic |> Map.put("first_admitted_ms", first) |> Map.put("valid_until_ms", deadline)

    {:ok, pair} = Ipse.Development.ManagedMetadata.Codec.encode_live(semantic, record)
    pair
  end
end
