# Independent bulk MCP uncertainty review — 2026-10-29

This scoped review covers the [repair receipt](index.md), frozen four-source
tar and manifest
`d4f6d20d94f460f4eb2334b8ef144a9e39f14ef16f4c00bfa5479c28c8d43af5`.
It assesses the MCP bulk return, Session dispatch, retained actual loopback
controls and their provenance. No code, gate, provider, native helper or runtime
test changed or ran for this review. The [plan](../../plan.md) owns completion.

**Disposition: accept this narrow outcome-preservation repair. No additional
concrete blocker was found.** The result-handler coverage and coherent-baseline
limits below remain open; this is not evidence of an automatic replay exploit
or a general HTTP fault qualification.

## Identity and source path

The [verifier](review/review-manifest.exs) checked all thirteen manifest entries,
all four exact frozen source bodies and all 621 final runtime files. The final
runtime has the same file set as the pinned document-decision base; only
`Elixir.Ipse.MCP.beam` and `Elixir.Ipse.Session.beam` differ. The helper remains
`7e1913446865a16cdfb7c96ca0285dc9e117a018c36c7b1940ba249a72ffd067`.
The [result](review/review-manifest.log) is retained. Source inspection used the
frozen tar; later Session/native barrier work is outside this cohort.

`MCP.discover_server/3` already distinguishes uncertain transport/cleanup outcomes
from known error. The repaired bulk reducer halts with that original unknown
tuple, retaining its message and discarding the incomplete aggregate catalog.
It does not start the next configured server. Successful catalogs, known errors,
bounds and private-value checks retain their existing behavior. No retry or new
connection is introduced by returning the correct tag.

The Session change adds the unknown tag to the existing discovery failure arm.
It calls the same failure/revalidation path as error. If that arm is reached with
a pending draft setup/revalidation, `Turn.mcp_revalidation_failed/2` records an
unknown result and marks the draft interrupted; it does not adopt a catalog or
continue model/tool dispatch. Resource cleanup is checked before this result
case. A cleanup failure takes the existing cleanup-warning/lifecycle closure
path instead, preserving pending setup for Saved reconstruction.

## What the retained controls establish

The real `47065` held-loopback initialization and actual HTTP transport death
reproduces the original downgrade: bulk returns `{:error, message}` even though
the message reports an unknown outcome. This is a returned-tag defect. The old
reducer also halted its server sequence, so that failure alone establishes
neither an automatic replay nor successful tool dispatch.

`47067` uses a small registration observer to find and kill the real transport
while its initialization request is held at the peer. It checks the repaired
unknown tag, local peer socket closure, exactly one initialization, no DELETE
from the dead transport and no request to the next server. A later explicit
healthy-server discovery succeeds once. The observer is a test owner with a
bounded registration callback; this direct test is not a genuine Session
admission or journal control.

`47070` separately uses the actual draft Session/resource/journal path. Its
cleanup warning is the expected result of losing that registered transport.
There is no catalog or explicit setup-result row; the exact setup intent remains
pending, Saved marks discovery interrupted, and resume is idle with no second
setup intent or new peer request. This proves conservative interruption/no
reconnect on this actual schedule. Cleanup failure preempts ordinary result
dispatch, so this test does **not** isolate the newly widened Session arm.
Inspection supports that arm's closed error/unknown routing; a broader coherent
regression or future focused arm control must not be claimed to have run here.

The failed `47063` listener was sandbox `:eperm` before protocol evidence.
`47064` dropped only a remote DELETE reply and wrongly expected catalog failure;
local pool closure and confirmed remote session deletion are distinct. The
rejected first fixture and failed assertion remain retained. `47068` and `47069`
then expected the wrong actual Session result row/message; the corrected test
asserts real cleanup-warning and pending-intent behavior instead. No TLS or
assertion weakening is used to manufacture uncertainty.

## Provenance and remaining limits

Compile `47066` and direct test `47067` were launched without a completion poll
between them. Both completed successfully, but the final inventory cannot prove
one whole-source cohort for every intermediate process. The old reducer cannot
pass the direct exact-tag assertion; `47070` ran after confirmed compilation.
This supports the stated narrow evidence without claiming an ordered aggregate
or isolated execution of every changed branch. No passing workload was rerun.

A local cleanup receipt does not prove cancellation of a remote initialization,
tool or session effect, and missing DELETE acknowledgment does not change that
contract. Unknown remote effects still require inspection before new explicit
work. No model, account, billing route, discovery permission or managed delivery
capability is added. Full HTTP faults, standalone accounts, coherent source/
package checks and the requested final adversarial audit remain open. The parent
owns audience documentation reconciliation, indexes and the coherent commit.
