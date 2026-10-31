# Nonpublishing resource proof for the proposed two-literal typed transaction.
# Arbitrary bodies below model encoded maxima, not authenticated IMB2 pages or
# admitted source records. This command never signs or publishes anything.
alias Ipse.Extension.Collection.ManagedPages, as: Pages

[output] = System.argv()
maximum = 9_007_199_254_740_991
digest = String.duplicate("f", 64)

fill = fn target ->
  noise = String.duplicate(<<0, 34, 92, 10, 9, 13, 8, 12>>, div(target, 24))
  base = %{"escaped" => noise, "padding" => ""}
  value = Map.put(base, "padding", String.duplicate("x", target - byte_size(Jason.encode!(base))))
  true = byte_size(Jason.encode!(value)) == target
  true = Enum.all?(Map.values(value), &(byte_size(&1) <= 8192))
  value
end

raw_parts = %{anchor: [2449, 2449, 2449, 2443], live: [2371, 2371, 2371, 2373]}

{sidecars, measurements} =
  Enum.reduce([:anchor, :live], {[], %{}}, fn kind, {changes, report} ->
    profile = Pages.profile(kind)
    # At most two original full leaves plus two nonshrinking row edits. Up to
    # four resulting headers and base64 rounding are charged independently.
    total = 2 * profile.capacity + 2 * profile.maximum + 4 * profile.header
    lengths = Map.fetch!(raw_parts, kind)
    true = Enum.sum(lengths) == total
    true = Enum.all?(lengths, &(&1 <= 4551 and &1 >= profile.floor + profile.header))

    values =
      Enum.map(lengths, fn length ->
        body = :binary.copy(<<255>>, length)

        value = %{
          "version" => 3,
          "data" => Base.url_encode64(body, padding: false),
          "mac" => Base.url_encode64(:binary.copy(<<255>>, 32), padding: false)
        }

        true = byte_size(Jason.encode!(value)) == Pages.encoded_size(body)
        true = byte_size(Jason.encode!(value)) <= 6144
        value
      end)

    sealed = Enum.sum(Enum.map(values, &byte_size(Jason.encode!(&1))))
    bound = div(4 * total + 8, 3) + 4 * Pages.encoded_size(<<>>)
    true = sealed == bound

    next =
      for {value, index} <- Enum.with_index(values) do
        fence = Integer.to_string(index + 1, 16) |> String.pad_leading(Pages.width(kind) * 2, "0")
        %{"key" => Pages.page_key(kind, fence), "expected_revision" => maximum, "value" => value}
      end

    {changes ++ next,
     Map.put(report, kind, %{
       raw_bytes: total,
       sealed_bytes: sealed,
       maximum_body_bytes: Enum.max(lengths),
       sidecars: length(values)
     })}
  end)

old_key = "note." <> String.duplicate("a", 64)
new_key = "note." <> String.duplicate("b", 64)

public = [
  %{"key" => old_key, "expected_revision" => maximum, "value" => fill.(6144)},
  %{"key" => new_key, "expected_revision" => 0, "value" => fill.(6144)}
]

original = %{
  "op" => "commit",
  "expected_generation" => maximum,
  "advance_floor" => true,
  "changes" => public
}

normalized = Map.put(original, "changes", public ++ sidecars)
facts = fill.(16_384)

receipt = %{
  "version" => 3,
  "kind" => "native_literal_supersession",
  "action_sha256" => digest,
  "native_review_sha256" => digest,
  "old_record_key" => old_key,
  "new_record_key" => new_key,
  "first_admitted_ms" => maximum,
  "valid_until_ms" => maximum,
  "history" => [maximum, maximum, maximum, maximum],
  "metadata_refs" => Enum.map(sidecars, &[&1["key"], maximum, digest])
}

receipt_bytes = byte_size(Jason.encode!(receipt))
true = receipt_bytes <= 2048
envelope = %{"metadata_version" => 3, "request" => original, "facts" => facts}

charged =
  byte_size(Jason.encode!(envelope)) + byte_size(Jason.encode!(normalized)) -
    byte_size(Jason.encode!(original)) + receipt_bytes

true = charged <= 65_536
true = Ipse.Extension.Collection.valid_request?(normalized)

File.write!(
  output,
  Jason.encode!(
    %{
      version: 1,
      kind: "proposed_literal_supersession_encoded_bound",
      semantic_authority: false,
      actual_planner_repairs_executed: false,
      actual_native_publication: false,
      marker_record: false,
      sidecar_measurements: measurements,
      public_values: 2,
      each_public_encoded_bytes: 6144,
      facts_encoded_bytes: 16_384,
      normalization_receipt_bytes: receipt_bytes,
      charged_input_bytes: charged,
      input_ceiling: 65_536,
      input_margin: 65_536 - charged,
      nonshrinking_sidecar_bound: 8,
      unique_read_units_bound: 25,
      read_derivation: %{neighbors: 4 * 4, selected_pages: 4, format: 1, overrides: 2, public: 2},
      escaping: "actual JSON NUL/quote/backslash/control strings plus URL-base64 page bytes",
      follow_up_required:
        "actual signed two-tree split repairs, unchanged-root caching and typed atomic publication"
    },
    pretty: true
  )
)
