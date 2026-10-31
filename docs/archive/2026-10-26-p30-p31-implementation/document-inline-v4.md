# Live inline document claims — implementation candidate, 2026-10-29

This implements the narrow Host amendment from the
[v4 progression review](shared-producer-v4-progression-independent-direction.md),
using the separately [implemented v4 byte/time relation](document-source-use-v4.md).
The [plan](../../plan.md) retains full progression, resource and acceptance work.
This record does not enable a new public producer or qualify live model quality.

An explicitly source-restricted document identity's pending-v4 inline put now
authenticates its actual prior slot under the existing retained document reader.
Expected revision zero requires absence. A positive revision requires the actual
same-key closed compact v4 ready row at that revision; pending, malformed,
missing and mismatched rows refuse. The witness generation must equal the
original inline request generation. The reader closes before the existing
unchanged-generation native CAS, so any intervening mutation invalidates that
CAS. The Host does not refresh the epoch after approval or copy worker claims
into an authorization record. Domain code still proves terminal-group membership;
the structural ready check is not historical model provenance.

The observation is accepted only from the actual current file-effect peer for
the exact active Session/job/action. It is bound to the project, namespace,
identity, parent invocation, actual operation ID and complete request digest.
Only that action's validated durable known successful inline result creates a
live guard2 origin. Unknown, failed or mismatched results consume the observation
and poison the invocation. Saved events do not recreate it. Existing guard1/v3
prepare/commit behavior and batch spending remain separate. Original clocks,
current source authentication and final transport admission remain required.

The isolated graph `_build/document-inline-v4-complete-sol-20261029` strictly
compiles all175current host/bundled inputs into216modules with zero diagnostics.
Its application inventory is regenerated from those exact compiled modules.
This source snapshot includes the notes own-root transition and document Session
delegates together; compilation is not a combined runtime qualification. It
inherits the unchanged helper40fa and bundled assets from the previously tested
[document admission graph](document-source-admission-return.md).

Focused run47235passes nine Session tests: six existing guard1/config/clock/state
cases and three added v4 observation/live-origin/unknown cases. Earlier47234stopped
before tests because the test's Ipse.JSON alias shadowed Elixir.JSON.encode!;
the corrected test uses the explicit Elixir module. The original failing source
and log are retained. The first candidate compile47231omitted the four bundled
source files after removing inherited BEAMs, so Registry's compile-time builtin
lookup failed. The corrected complete-input graph47233is a distinct child;
the failed graph/log remain unchanged.

Selected native run47236passes one new case with nine others excluded. It seeds
a synthetic ready record, authenticates its actual retained revision/generation,
performs an intervening write, and observes the original CAS refusal. Fresh
observation at the new epoch permits the actual pending write, whose real
committing operation/revision are verified. Another fresh-origin observation of
that retained pending record refuses. The synthetic native home remains at
`/tmp/ipse-inline-v4-a92d7c3d203c6e897d2eca3c07a32728`; this is a storage-boundary
control, not actual Session dispatch or a complete producer run. The nine earlier
test bodies remain unchanged apart from formatting when that native case is
added. No aggregate suite, live model call or repeated workload ledger ran.

The [evidence directory](document-inline-v4/) contains the complete175-input
source tar/hash list, exact runtime inventory, current focused tests, initial
failed test source, launchers and failure/pass logs. Manifest SHA-256:
`4e3707b2170c413fe9d084121c8a6b5f3c53ba16f42b3142156d220b995c36df`.
Independent implementation review and actual v4 producer/Session integration
remain required before public adoption. Full lifecycle, output-sink, installed,
resource, owner-loss and P30/P31 acceptance are not claimed.
