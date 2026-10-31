# Literal-source upgrade control review — 2026-10-29

This independent review covers the [literal-v4 upgrade control](literal-v4-source-union.md),
not publication qualification or milestone completion. The [plan](../../plan.md)
remains authoritative. No native test or aggregate suite was repeated.

The retained seed fixture uses actual native input and statement/category review
on its historical matched runtime. The consumer explicitly regrants trusted test
configuration rather than claiming that the old permission silently covers a new
artifact. Its journal assertions identify exactly one actual version-4 managed
read and tie the record's native assertion to the original seed Session. The
controller then makes only that original journal unavailable while the collection
root remains unchanged. A fresh quote from current input B succeeds.

The passing test traces the real Session's return from
`ManagedToolUse.publication_prerequisites?/3` and requires `false`. It also checks
that no managed publication intent was journaled, no blanket-gate diagnostic
caused the result, and the collection generation stays at the captured baseline.
Subscriber notifications, Session info and restored messages do not contain the
synthetic original literal within the observed completion interval. The original
journal is restored and its hash compared exactly. These assertions distinguish
source-union refusal from a test that passes merely because all writes are gated.
They do not establish revocation, retention expiry or every asynchronous sink.

Runtime provenance matters here. The retained failed run46920 used stale
Invocation code and produced an isolated pending record. The corrected launcher
overlays eight gate modules and checks the prerequisite import before application
startup. A separate strict compile compares executable BEAM code MD5s for current
Invocation and ManagedToolUse with the passing runtime. Generation2 is the honest
post-error baseline; the pending effect was neither removed nor replayed. This
section must not be cited as a pristine generation1 consumer journey.

The reviewer [verified all26manifest artifacts](shared-canonical-review/ipse-literal-manifest-review-46991.log),
including source snapshots, all retained failed/passing logs, runtime inventory
and synthetic journal evidence. The [verification script](shared-canonical-review/ipse-literal-manifest-review-46991.exs)
uses retained local runtime paths. Current test changes relative to its frozen
tested snapshot are formatting only; no behavior rerun was required.

No additional concrete defect was found in this scoped control. Actual native
publication lifetimes, shared source/output ownership, complete withdrawal/recall,
package reconstruction and integrated qualification remain open. Earlier and
current containment gates remain unchanged.
