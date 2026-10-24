# Existing-provider equivalence fixtures

Captured from `dd510a72e31e15402eeb473fcf29929243b8ca2c` on 2026-10-24 UTC in a
separate source/build root. [Provenance](provenance.json) records source/fixture
hashes. These synthetic records contain no credentials or live requests.

`equivalence.json` contains complete Config manifests, destination digests, usage
and cost estimates for the five existing routes. Each JSONL is an idle session
followed by completed synthetic usage; its usage JSON captures the original restore
result. Legacy variants remove only destination and metering events to represent
the supported request-free format.

Tests relocate only workspace paths, preserve provider/billing/destination facts,
and require unchanged journals after idle resume. Internal MapSets and tuples use
portable JSON. Bundled skill paths still identify the capture root: idle resume
must not read or refresh them. Never regenerate goldens from a refactored runtime.

To reproduce, extract the recorded Git revision separately and build with its
locked dependencies. From that baseline, run its `mix run` with the absolute path
to [`capture-provider-registry.exs`](../../../dev/fixtures/capture-provider-registry.exs)
and a new output directory as the only argument. It loads the adjacent test
helper using pre-refactor APIs. Compare facts and source hashes; synthetic IDs
and timestamps naturally differ. Current assertions are in
[`registry_test.exs`](../../ipse/provider/registry_test.exs).
