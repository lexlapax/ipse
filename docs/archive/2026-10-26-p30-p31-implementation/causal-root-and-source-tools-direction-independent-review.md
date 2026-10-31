# Causal root prerequisites and source tools — independent direction

Read-only requirements/source direction, 2026-10-29, following the accepted
[notes implementation slice](notes-publication-implementation-independent-review.md)
and [own-root prerequisite direction](remember-publication-prerequisite-independent-review.md).
The [plan](../../plan.md) owns acceptance. This records two distinct functional
gaps; no implementation, tests, model calls, effects or gate changes were made.
Lifecycle retains the new failed arguments/diagnostics separately. Those new
failure cohorts are not independently qualified by this source-only record.

## Authentic causal root metadata can remain in the publication union

The [baseline](baseline.md) requires source/permission revalidation, complete
causal lineage and model-selected capture of eligible typed host outcomes. It
does not require every root observation to have been created by the final capture
invocation. A historical receipt cannot grant current authority, but authentic
earlier metadata can identify the root that must be freshly checked.

The reported new capture has `entry.input == []` and retains a root dependency
from an earlier metadata-only recall index in addition to its own nil gets.
That propagation is expected: `ManagedLineage.source_dependencies` reads actual
source provenance and unions prior request/output/effect dependencies, including
when an extension reads the typed host outcome. Dropping that older root,
stripping recall, or declaring the source receipt independent would erase causal
information. The current own-parent-only matching rule instead refuses it.

A fresh own nil-get with the same root is **not enough on its own** to qualify
the older dependency. Version-3 `root_observation` is also used for some reads
that can contain nonliteral public record values. Root shape does not prove the
original result carried no content. The old request/result must itself be
authenticated and classified.

The smallest supported extension is a bounded host classification cache:

1. After the original `managed_read_observed` receipt is matched to its actual
   active committed action result, validate the exact intent/result binding,
   Session/parent/operation, namespace/project/pin/policy, dependency union and
   complete request/result digests using existing Actions/ManagedReads checks.
   An observation without the matching committed successful result never qualifies.
2. Classify only a closed successful snapshot, explicit nil-get, or the narrow
   **initial empty metadata-only index**: cursor nil, `coverage: metadata_only`,
   `count: 0`, `records: []`, `next: nil`. Do not classify nonempty index pages,
   scans, record values or a missing record field. No note/override-prefix rule
   is needed. This extends the earlier scan/index refusal only for an explicitly
   demonstrated byte-free metadata result; it does not reclassify all v3 roots.
3. Store dependency-digest → exactly `true` only after that validation. The cache
   is a historical classification, not a current-use permit. Workers cannot
   supply or edit entries. A single pending observation may bridge the existing
   receipt/result chronology, but failed, mismatched, orphaned or interrupted
   records cannot leave it available for a later unrelated result.
4. Include both the cache and pending state in the existing lineage accounting:
   at most 2,048 entries and the existing checked 4-MiB state envelope. Reuse the
   normalized dependency dictionary rather than retaining unbounded result
   bodies. Overflow/malformed state fails closed; do not silently evict causal
   evidence and then accept a partial union. Clear a pending observation at its
   proper lifecycle boundary or mark lineage unavailable if chronology is invalid.
5. Reconstruct classification during Saved/replay from the same validated
   chronological receipt and committed-result pair. Do not deserialize a worker
   cache or infer eligibility from a bare restored dependency. Legacy/missing
   evidence can refuse this new path. Replay classification does not recreate
   a volatile effect capability or execute a request.

For the immediate publication repair retain `entry.input == []`, every member of
the complete invocation/read/source union, and all prior version/project/namespace/
pin/policy/expected-generation checks. Require an exact positive cache entry for
each qualifying causal root and identical **complete** root maps across the union.
The original parent may be a prior event job within this same authenticated
Session; parent inequality is not by itself a source-permission defect.

Fresh actual Identity/policy/Collection ownership still has to validate that
common root at publication. Preserve real native generation/revision CAS and the
normalizer's actual root witness; compare the full witness where available,
without treating a shaped cached root as authority. A root that changed cannot
be rebased onto a fresh nil-get. Record-valued, inherited-content, mixed/stale,
foreign, unmatched or unclassified dependencies refuse. Extending nonempty
invocation input is not needed to close this reported case and is outside this
immediate repair.

Focused new qualification should cover the real earlier-event empty index plus
own nil gets, unchanged union and actual current-root admission; equivalent
chronological replay; orphan/failed/wrong-operation receipt/result; cache overflow;
tampered digest/pin/full-root identity; nonempty index/value/scan; stale root and
missing cache. A fresh direct-client headless typed-outcome save is distinct from
the still-blocked model source-tool journey. Preserve both failures; do not retry
their uncertain operations or turn one positive into all-source acceptance.

## Root-only source-tool access needs its actual read and output boundaries

The baseline expressly provides bounded current-Session source listing, reads
and unique quote resolution so the main model can select eligible receipts.
An empty recall root is metadata, not a reason to ban those tools permanently.
There is no requirement to remove that dependency to recover functionality.

Current `Turn.dispatch_tool` refuses the three source names through
`ManagedToolUse.host_operation_unqualified?` whenever the model call has managed
dependencies. That blocks even a root-only union. The existing allowed path is
read-only and narrowly scoped: `SourceRead.read_model` validates closed arguments,
the Session checks exact task/job/current call name and arguments, and the Writer
serves bounded own-Session opaque handles through its actual source window.
`SourceWindow` validates saved read chronology; SourceIndex retains typed tool
outcome metadata separately from untrusted file/shell/MCP content. These owners
must remain. Source listing is not arbitrary source-view, file or other-Session
access, and successful execution does not endorse stdout as a fact.

A bounded root-only exception is supportable only after the entire validated
union, source lookup and release chain are covered:

- Keep every inherited root. Admit only authenticated, classified root-only
  dependencies with one current project/namespace/pin/policy/root; no content
  dependencies or lineage-unavailable shortcut. Revalidate the actual root and
  policy through the existing owned ManagedUse barrier. Preserve source handles,
  original source/receipt hashes and complete dependencies introduced by the
  selected source's provenance; a source page can add causal dependencies beyond
  those already attached to the tool call. That additional lineage must not be
  hidden to keep the request classified as root-only.
- Place the actual bounded source lookup in the trusted current-use path. A
  simple deletion from the name allowlist is insufficient: this branch currently
  calls `SourceRead.read_model` directly, unlike workspace reads that enter
  `with_effect`. Reuse existing exact native-tool binding/admission and Writer
  source access. If the callback runs in an authorized file-effect peer, update
  the source handler only for the exact live job/task and authorized peer; its
  current handler deliberately accepts the task PID itself. Never replace that
  check with arbitrary process ancestry or caller-supplied provenance.
- Retain the existing result-observed/release/cleanup sequence, full source
  lineage and model pre-dispatch revalidation. A source quote is exact support,
  not proof of external truth or permission for later capture. Unavailable,
  expired, foreign or newly content-bearing dependencies must refuse/withdraw
  rather than bypass the still-unqualified content path.

There is a concrete second boundary in current code. `release_result` does
reacquire ManagedUse authority, but `Turn.commit_tool_result/4` merely checks the
wall deadline and calls `Session.notify`. That is an ordinary mailbox send;
Terminal later prints up to 800 characters from the raw tool result. This is not
an actual guarded native payload write and can outlive the release checks.
Suppressing ordinary progress earlier does not fix this result-preview path.

Therefore keep the source-name gate closed until either the actual payload
preview uses an already qualified guarded native output path, or an explicit
safe status-only/withheld-preview choice is implemented for this narrow path.
The latter may retain full journal/model content and all lineage while sending
no source payload in subscriber preview events; it must be named and tested as
withheld preview, not current protected display. Do not use unguarded raw
`tool_result` events to make the model capture trial pass. No new general terminal
framework is required merely to withhold a preview. Model dispatch remains a
separate fresh authority boundary either way.

After that choice, focused controls should prove current root-only list/read/
quote with a genuine typed outcome, full union and source-proof retention;
stale/mixed/policy-expired and foreign handles/clients refusing; later selected
source content adding its real dependencies; and no queued native payload after
authority release/loss. Preserve ordinary write/shell denial and record-bearing
source-tool refusal. A model journey using these tools and a direct explicit-
client capture are separate acceptance observations.

This direction changes no existing record-content, output, saved-consent,
document, State/service or delegation permission. It does not claim the new
reported failures were reproduced here or qualify the original source tool
chain. Lifecycle owns the bounded cache/chronological tests; the source-tool
preview decision remains separately open.
