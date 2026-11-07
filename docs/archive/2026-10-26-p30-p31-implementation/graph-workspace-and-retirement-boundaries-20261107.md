# Workspace Graph and retirement recovery boundaries, 2026-11-07

Historical source investigation against `622f876e`; the [plan](../../plan.md)
owns current scope. No tests, model calls, or retained-notebook access ran for
this investigation. This record does not authorize recovery or qualify either
feature.

## Graph and acquired documents

Graph's State/MCP query snapshots stored sources, traverses facts, and checks
store and identity state before returning. Its `revalidated` coverage concerns
that stored state; it does not check the original workspace file. Graph also
does not recheck that file before extractor egress or fact publication. The
[operator procedure](../../operator/graph.md) already states those limitations.

The existing Collection workspace guard verifies an acquisition against a
live Session and the specific Collection document effect. It is not a durable
cross-session authorization for a Graph source in State or MCP. A worker-supplied
path and hash by themselves do not establish the acquisition or bind it to a
Graph source generation. The Corpus output-time check is useful implementation
precedent, but does not itself provide the missing Corpus-to-Graph authority.

The remaining implementation needs an explicit authority choice and a trusted,
durable association between the acquisition and exact Graph source generation,
followed by appropriately ordered current-source decisions for query delivery,
extractor dispatch and fact publication. It must preserve existing approval,
effect-budget, source-revalidation and unknown-outcome rules. A design and
actual Session tests must establish the required ordering and distinguish an
admitted in-flight request from a later publication; this investigation does
not prescribe holding a filesystem lock across network IO.

## Interrupted document retirement

`Collection` and native `DocumentDraft` refuse continuation of a partial
retirement under a later maintenance epoch. The new native operation marker and
the live-Session journal/ledger join supply part of the evidence, but do not
prove that an interrupted prior owner and dependent effects are quiescent while
recovery is authorized. The existing release inspection does not retain the
owner lock for that join.

Recovery requires an explicit owner-bound path joining the authenticated prior
journal action and request digest to the exact native marker and current head,
retaining the necessary Session/owner release authority while checking the idle
epoch and making a fresh approved CAS operation. Unknown prior outcomes and
legacy or unprovable heads must remain refused rather than replayed. Removing
the epoch check or treating a temporarily free lock as that proof would not
establish the required boundary.
