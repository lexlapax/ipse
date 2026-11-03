# Pending chat-card journal binding, 2026-11-02

This narrow host consistency repair prepares for the still-unimplemented in-chat acceptance journey. Current milestone status is in [the plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance); the existing standalone review remains the operator path.

Before the repair, `PendingAcceptance.prepare/4` and `valid_facts?/1` accepted a structurally valid non-batch card whose non-null chat Session ID differed from its journal ID. A new pure fixture reproduced that result. Historical `validate_events/2` already required a chat acceptance event's Session and actual journal ID to agree, so this finding is not evidence that a mismatched event could be replayed or that the public standalone review accepted one. The current standalone caller uses a nil Session ID.

Both context preparation and card validation now require a non-null Session ID to equal the journal ID; nil remains valid for standalone review. This is a consistency check, not authentication of a Session, input, source, consent, display or publication authority. It introduces no chat review route or effect.

The initial focused run failed on the mismatch as expected (`/tmp/ipse-pending-chat-binding-before-20261102.log`, seed 791876). The corrected pending batch, correction, rejection, accepted-decision lifecycle and management selection checks passed 13 tests, with five excluded, at seed 791877. The existing actual native public-review fixture passed one test, with 20 excluded, at seed 791878. `./dev/build.sh`, the full formatter check, strict compilation and the credential-free demo with an isolated home passed.

A preliminary full serial suite (seed 791879) was deliberately stopped with SIGTERM before completion to continue implementation. The parent exited 143, and no aggregate pass is claimed. Its retained `/tmp/ipse-chat-binding-full-test-20261102.log` has SHA-256 `f9d3222f038ee01c38d950c62e9618423ef2a83d9424e8e6491ad18337a30394`; child-process release was checked. A full suite remains required on the final source. An earlier launcher was also stopped after its build because its planned demo did not isolate the Ipse home; that demo did not run.
