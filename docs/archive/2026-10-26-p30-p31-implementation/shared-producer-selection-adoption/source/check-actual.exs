root = Path.expand("_build/shared-producer-selection-adoption-20261029/session-47170")
bytes = File.read!(Path.join(root, "synthetic-session.jsonl"))
events = bytes |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
header = Enum.find(events, &(&1["type"] == "session"))

[bootstrap] =
  Enum.filter(
    events,
    &(&1["type"] == "extension_action_result" and
        get_in(&1, ["request", "op"]) == "embedding.profile")
  )

{:ok, binding} =
  Ipse.Extension.EmbeddingCall.profile_binding(header["metadata"], bootstrap["request"])

true = binding === bootstrap["effect_binding"]
true = Ipse.Extension.EmbeddingCall.profile_value(binding) === bootstrap["outcome"]["value"]
true = bootstrap["approval"] == "not_required"

[setup] =
  Enum.filter(
    events,
    &(&1["type"] == "extension_invocation_result" and
        get_in(&1, ["payload", "arguments", "action"]) == "selection")
  )

v = setup["value"]["coverage"]

true =
  v["configured_profile"] === binding["profile"] and
    v["selection_sha256"] === binding["selection_sha256"]

true =
  v["reported_model"] === nil and v["coverage"]["effects_used"] === 0 and
    v["coverage"]["reads_used"] === 1

false =
  Enum.any?(
    events,
    &(&1["type"] in ~w(request_admitted request_finished extension_effect_result extension_embedding_request))
  )

[page] =
  Enum.filter(
    events,
    &(&1["type"] == "extension_invocation_result" and
        get_in(&1, ["payload", "arguments", "action"]) == "page")
  )

true = page["action_count"] === 0 and page["value"]["status"] == "refused"
true = page["value"]["gaps"] == [%{"code" => "shared_producer_source_dispatch_unavailable"}]
boundary = Jason.decode!(File.read!(Path.join(root, "native-boundary.json")))
true = boundary["before"] === boundary["after"] and boundary["claim"] === nil
File.write!(Path.join(root, "selection.json"), Jason.encode!(setup["value"]), [:exclusive])

report = %{
  version: 1,
  scope:
    "read-only actual public selection and zero-egress gate evidence; no private producer source dispatch qualification",
  journal_bytes: byte_size(bytes),
  journal_events: length(events),
  journal_sha256: Ipse.JSON.sha256(bytes),
  exact_metadata_bound_profile: true,
  reported_model: nil,
  bootstrap_reads: 1,
  bootstrap_effects: 0,
  inference_admissions: 0,
  gated_page_actions: 0,
  claim: nil,
  unchanged_native_boundary: true,
  event_types: Enum.frequencies_by(events, & &1["type"])
}

File.write!(Path.join(root, "checked.json"), Jason.encode!(report, pretty: true), [:exclusive])
IO.puts(Jason.encode!(report, pretty: true))
