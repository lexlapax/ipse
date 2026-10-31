# Source-tool first candidate — independent scoped hold

Read-only source finding, 2026-10-29. **Hold source-tool chain acceptance** for
the frozen [first candidate](managed-source-tool-first-control.md). Lifecycle
identified the missing branch during review coordination; this review confirmed
it in the frozen Turn source. No runtime disclosure counterexample, test, replay,
provider call or effect was executed. The [plan](../../plan.md) owns acceptance.

The [manifest](managed-source-tool-first-control/manifest.sha256) SHA-256 is
`74624e5376cf39be49307566563bcd36835a71b1f3dce146a50c454c804a5b4e`.
All 19 direct manifest rows were independently hashed, including source tar,
retained BEAMs/tests, journal, inventory/difference and actual log. Turn was read
directly from that tar. This is an exact source finding and partial evidence
check, not a complete runtime/authority/replay audit of the candidate.

## Initially empty calls bypass selected-source classification

`Turn.start_admitted_tool` computes `managed` once from the original tool-call
dependencies. For source list/read/quote, an initially empty union takes ordinary
`SourceRead.read_model`; only `managed == true` enters `with_effect` and the later
`ManagedToolUse.release_result` path. Consequently the initially empty branch
does not enter the new `bind_source_result` relation or current ManagedUse result
admission. It can instead take ordinary tool-message/result notification with raw
text.

An initially empty call does not establish that its selected occurrence's
producer dependencies are empty. Source handles address the actual current
Session index, which may contain an occurrence with managed causal content from
an earlier producer. This branch can therefore select additional dependencies
without the proposed complete-result union/current-release check. The new cache
does not prove which occurrence was selected. Later model-lineage propagation
cannot retroactively guard raw result publication.

This is a blocking source-policy coverage gap even if the initial-empty route
predates the new root-only exception. It does not show that the retained partial
positive traversed that branch, that a leak was reproduced, or that an uncertain
effect was automatically replayed. The candidate's observed nonempty-root source
list/read releases cannot qualify an unexercised branch.

## Smallest repair direction

All three source-tool results must enter the exact owner-selected provenance
relation before forwarding, including calls whose original union is empty.
Authenticate original operation/arguments/active call/result and the actual
chronological SourceWindow. Union all selected occurrences with the complete
call dependencies before result hashing, current release and model continuation.
Known-empty producer evidence is distinct from missing mappings; missing or
ambiguous evidence refuses.

Genuine empty result lineage may retain ordinary compatibility only after that
authentication. A nonempty selected union must enter the appropriate existing
current-authority path; this initial scope admits only the exact cached root-only
class and refuses content-bearing/stale/mixed/unavailable dependencies. Ensure
fixed status-only notification covers managed/withheld source results in both
current and withdrawn branches. Do not send selected source text merely because
the initial call was unclassified as managed.

This needs no generic tool framework or new terminal payload sink. Keep the
original candidate immutable and qualify the corrected initially-empty → selected-
managed case, missing producer refusal, actual subscriber notification and
chronological replay in an additive freeze. Full source quote, owner-loss and
other previously stated qualification limits remain open until observed. The
separate [inherited-root publication direction](inherited-root-publication-direction-independent-review.md)
is unaffected: allowing authenticated payload-free inherited root metadata does
not authorize this selected-result bypass.
