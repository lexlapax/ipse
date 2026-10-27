# Review-only stage category diagnostics

Historical experiment, 2026-10-27. The [seventh fault attempt](../serenity-fixture/seventh-fault-outcome/RECEIPT.md)
recorded native write success and sync `EIO`, then an `InvalidData` stage
failure without capturing its line. The pending release was not replayed.

The candidate changes only the stage-channel and stage-script files relative
to the [seventh candidate](../serenity-fixture/seventh-fault-candidate/SOURCE-SHA256SUMS).
The [channel](diagnostic_stage_channel.rs) SHA-256 is
`5fb480b0dd31889b5d9fb60f7880452b0e65dc3f5862a92f92fd5d104f567c21`;
the [stage script](diagnostic_stage_container.exs) SHA-256 is
`8c2028162418b11e6a20a521f8f427adaa68446e6754d92c5b5b6fe10d3cbf5f`.
They add bounded allowlisted outcome categories without printing arbitrary
stage content. The original peer-report/stage-result consistency check remains,
and a contradiction between the added category and stage line also fails.

A freshly compiled no-device Rust test binary ran four filtered
stage-channel tests, all passing. One used a real local shell pipe and exercised
matching, unknown and contradictory lines; the others checked categories and
the existing consistency rule. The source and test results are from the tool
transcript, not an archived raw log. This test does not establish the actual
seventh stage result or test a mounted filesystem.

The candidate has not received an independent adversarial review, a complete
frozen build/bundle review or a device run. Diagnostic stderr can fail or block;
timeouts and interrupted release must still be treated as unknown. The seventh
backing, index and records remain retained, and final backing release is unknown.
No kernel qualification or P31 completion follows from this experiment.
