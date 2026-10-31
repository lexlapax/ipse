import ExUnit.Assertions
alias Ipse.JSON
[path | rest] = System.argv()
text = File.read!(path) |> String.replace("\r\n", "\n")

[_, display, json, challenge, digest, display_digest, key] =
  Regex.run(
    ~r/(Retained management target at [0-9]+: signed deadline elapsed\. Original source availability and current-use eligibility are not checked\.\nReview the complete proposed facts below\. This confirmation applies only to this exact review\.\n(\{.*?\})\nType forget ([0-9a-f]{16}) to confirm, or anything else to cancel\.\n> )\nMANAGEMENT_FULL_FACTS_DISPLAY_CLOSED ([0-9a-f]{64}) ([0-9a-f]{64}) (note\.[0-9a-f]{64})/s,
    text
  )

assert {:ok, facts} = JSON.decode_unique(json)
assert JSON.digest([facts]) == digest
assert JSON.sha256(display) == display_digest
assert facts["target"]["key"] == key
expected = if rest == ["large"], do: String.duplicate("\\\"", 200), else: "Acme has owner Alex"
assert facts["target"]["value"]["text"] == expected
assert facts["metadata"]["valid_until_ms"] < System.system_time(:millisecond)
assert facts["context"]["management_epoch"] == 1
assert facts["target"]["revision"] == 1
assert facts["target"]["value"]["evidence"]["sources"] != []
assert facts["kind"] == "managed_literal_forget"
assert byte_size(challenge) == 16
IO.puts("MANAGEMENT_RENDERED_FACTS_AND_DISPLAY_EXACT_DIGEST_EXPIRED_TARGET_REVOKED_EPOCH")
