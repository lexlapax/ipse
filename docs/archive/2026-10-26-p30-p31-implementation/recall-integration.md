# Native turn-local note recall: focused integration evidence

Historical implementation evidence captured on 2026-10-28. This is a scoped
diagnostic record, not release, platform, model-quality or complete P31
acceptance. The active ledger remains [the plan](../../plan.md); the accepted
behavior is in the [frozen design](../2026-10-26-p30-p31-plan-review/design.md#recall-without-another-service).

The reviewed native Knowledge artifact now declares one optional metadata-only
`prompt.effective_committed` job scheduled `before_request`. The existing owned
event coordinator waits for its committed result before preparing the first
model input. The job clears its old contribution, obtains closed capacity facts,
pages note metadata and individually reads at most 32 current notes. It makes no
model/helper call and does not rewrite the effective prompt. Changed capabilities,
exports and subscription bytes change the artifact identity and require native
setup review; no older grant is silently promoted.

The generic metadata index returns keys, revisions, byte counts and value hashes,
never values or eligibility. Its opaque authenticated cursor binds the Session,
source window/generation, namespace, selected pin, prefix and exact root. A page
fits 4 KiB; private validity metadata is excluded before selection. Individual
note reads still authenticate signed managed metadata and original sources.

Recall groups whole note text into explicitly unverified derived Reference data.
Lossless pieces carry the exact note key, revision, current read operation ID,
UTF-8 byte offset and total bytes. Every publisher inherits the complete host
read union; these item labels never choose or reduce dependencies. Packing uses
the actual escaped Reference envelope and provenance overhead, with the shared
8 KiB and host item limits. Long text is split losslessly. A note is included
completely or omitted with partial coverage. Bounded index metadata reports
omitted keys and remaining pages and names the fixed index/read tools.

The first real native journey also exposed and repaired two integration errors:
cursor state belongs to Writer, and named main execution profiles must use the
same main-route selector as dispatch rather than comparing their name to a
helper-profile field. Protected event intents now consistently construct and
validate their version-three binding. Writer's private index-scope query remains
owner-only and never enters worker JSON.

Changed sources withdraw an entire validated host Reference selection and insert
an explicit notice while preserving its user role and closed historical marker
identity, with a recomputed content hash. Original journal records remain intact.
A grouped member disappearing invalidates the group; matching text is not
provenance identity. Ordinary native Ollama text can be withdrawn only after the
host binds its exact producing Usage admission and selected policy route and
proves a closed redundant text envelope: empty thinking, no calls, matching visible
text, no unknown fields. The entire occurrence loses its redundant native map
together with the text. Unknown continuations, nonempty thinking, native calls,
foreign providers and unbound lookalikes refuse. This does not authorize rewriting
ChatGPT response IDs or encrypted reasoning.

## Focused verification

The final native selection
[46795](recall-integration/sol-native-note-recall-46795.log) passed three tests
with 48 excluded in 12.6 seconds. Its real terminal setup and three separately
reviewed ordinary/preference/current notes feed a fresh Session through the
registered native Ollama HTTP transport. Assertions cover all three note texts
in the first request, committed recall before dispatch, no helper inference,
stable system prefix and tools, and no promotion of recall to a new operator
assertion. A real reviewed forget removes one member before the next turn;
the raw later request omits its bytes while retaining both current notes. Removing
the original source journal then withholds all note text. Cancellation with a
held response publishes no terminal answer, and resume leaves both original and
consuming journals unchanged. Saved reconstruction equals live messages before
the cancellation case.

The same selection checks exact request/route/model tampering and closed native
text versus opaque continuation refusal. A subsequent unchanged-runtime
[46796](recall-integration/sol-recall-producer-collision-46796.log) passed two
focused tests: byte-identical answers retain distinct real request provenance,
and a mismatched active dispatch admission refuses.

Earlier focused controls retained alongside the final selection include:

- [46780](recall-integration/sol-recall-unit-46780.log): metadata pages/cursors and
  capture compatibility passed; two newly authored fixture envelope assertions
  failed and were corrected. [46781](recall-integration/sol-recall-unit-46781.log)
  then passed 39 tests for the affected worker/Reference files.
- [46786](recall-integration/sol-recall-grouping-46786.log): six worker behaviors
  in an independent VM, including all 32 tiny notes within the measured envelope,
  long UTF-8 lossless pieces, bounded larger sets and missing-source coverage.
- [46787](recall-integration/sol-context-capacity-46787.log): two closed capacity
  and exact escaped-framing controls; another publisher's text is not disclosed.
- [46788](recall-integration/sol-recall-lineage-46788.log): metadata-only event
  inheritance and whole-group member withdrawal passed, with 46 excluded.
- [Artifact build](recall-integration/sol-recall-bundle-build.log) and
  [strict compile](recall-integration/sol-recall-strict-compile.log) completed
  successfully. The strict compile log is empty because the final graph was
  already compiled; its command exited zero with warnings treated as errors.

Representative failed native iterations are preserved:
[Writer ownership](recall-integration/sol-native-note-recall-46782.log),
[named main profile](recall-integration/sol-native-note-recall-46790.log), and
[new producer-role mapping](recall-integration/sol-native-note-recall-46794.log).
[46793](recall-integration/sol-native-note-recall-46793.log) records the earlier
positive journey before the final exact producer-route hardening. These are
implementation/debugging receipts and are not additional acceptance runs.

## Provenance and limits

The [manifest](recall-integration/manifest.json) binds copied logs and the scoped
post-run source cohort under `recall-integration/source/`. It is not a frozen
snapshot of the whole shared worktree. The final native log SHA-256 is
`08ae94845ca4411cc3e774ce09dadb419d97c972e9bf53faaf3abe6da101c1f5`;
the collision/owner-control log is
`95a6f37f250d6a81030f545c56b71f845b5f3cafa42cf2b59178740a53448055`.

Tests used `_build/operator-assertion-sol` and its separately identified
available-host diagnostic native helper
`86d6226c868b7095c6ba7460cc0b42832e98fb70feea0779fb3473ac7bb28a6a`.
The ordinary sandbox launcher failed before commands with its synthetic `/tmp/.git`
mount quota error; authorized focused checks used the existing escalation path
and repository scratch directory. This proves neither production profile
admission nor tmpfs behavior. There were no live accounts or paid requests.

This record does not qualify the frozen 100-prompt recall corpus, semantic answer
quality, latency targets, installed/package flows, macOS or hosted default-provider
recall. Unsupported opaque later-turn withdrawal refuses and requires a fresh
Session or a separately proven projection. Native inference send/result authority
has its own [owned-send evidence](owned-send-integration.md). Direct extension
worker-result delivery still requires its separate final current-authority release
gate; retaining its union for later dispatch is insufficient and is not claimed
as completed here.
