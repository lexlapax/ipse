# Integrated native workload smoke, 2026-11-02

This historical receipt records a synthetic smoke test, not milestone acceptance.
Current scope and acceptance remain in [the plan](../../plan.md).

The test used a fresh isolated copy of commit
`4981862e34b65230d6132485b8f984e14588f0a9` and only the six source and test
overlays in [the fingerprint manifest](integrated-smoke-20261102-overlay.sha256).
Its dependencies, build and home were separate from the working tree. The
snapshot did not include the other uncommitted work in that tree.

On that snapshot, the focused seed and integrated tests passed: 6 passed and
the opt-in smoke was skipped. The native helper and bundled runtime then built,
and a forced test compile passed with warnings treated as errors. The opted-in
smoke passed with 1 test passed, 2 excluded, in 600.8 seconds. The smoke's
dynamic loading emitted a seed-module availability warning.

The fresh cohort began with seven synthetic notes and used four native effects,
each followed by ten actual `Session.prompt` turns through a loopback synthetic
Ollama fixture. It checked the saved sessions and journals, an independent audit
of the resulting collection, and refusal of a second run. The
[completion](integrated-smoke-20261102-complete.json) and
[audit](integrated-smoke-20261102-audit.json) were copied before the successful
test removed its temporary root. The audit's SHA-256 matches the completion
receipt. Paths in the completion receipt identify that removed temporary root;
the underlying session journals and per-turn records were not retained for later
independent inspection. The receipts and fingerprints support the reported
result but are not a substitute for those records.

After the smoke, the coordinator's three dynamically loaded seed calls were
changed to equivalent `apply/3` calls to address the warning. That later edit is
not represented by the overlay manifest and had not been tested at this receipt's
creation. The smoke also does not establish quality or human outcomes, a live
provider or paid account, interruption recovery, the 2,000-note journey, or
annual qualification. Integration against the final source, the remaining
acceptance and documentation checks, and an adequately measured throughput
strategy remain open.
