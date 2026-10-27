# Session-owned observation lineage: design under review

This is a proposal, not implemented authority or milestone acceptance.
`Collection.ObservedRead` is an unwired same-view storage observation: it
returns a value and root witness read under a checked Collection view, then
closes that view. The witness becomes historical after closure. It does not
establish current project identity, consent, source eligibility, worker
confinement or permission to use the value later.

## Current propagation and the gap

`CollectionCall` checks the outer pin and obtains current sources under
project binding and policy, then performs a generic storage read. It currently
does not call `ObservedRead`. `Host` constructs an `Actions.result`; Session
validates and records that event before `Actions.resume` delivers its value to
the extension worker. The existing result outcome hash covers the value, not a
same-view root observation. The current continuation schema carries the outcome
but no host lineage. `Actions` replay validates existing action/result shapes
and parent/step/order, and `Invocation` records results and can publish context
or other descendants; neither reconstructs observation lineage.

The [boundary tests](../../../test/ipse/extension/observation_lineage_boundary_test.exs)
exercise `Actions.resume` with synthetic events and show that changing a
host-only observation field does not change the worker payload or the outcome
digest. They document the present interface, not an end-to-end protected read
or an attack proof. Two passed in a private graph (seed 20270303); the
[log](observation-lineage-boundary.log) SHA-256 is
`b7580dea80fb00abdf23ca333ab62a5f8cfab883fd610cdd2af992a25681fb48`.
The test SHA-256 is
`40e55f06029bb2e53b09b9105af9423aa7fef63aa4779bb50778402238ba28e0`.

## Conservative propagation boundary

An extension VM cannot be trusted to declare which output depends on a read.
For a confined, exclusively mediated worker, Session would instead attach the
union of all observations delivered to that worker to every later output,
proposal, effect, host call, service/child input, partial result and continuation.
The union grows monotonically. Any returned value, `context.publish`, saved
result, transformed prompt or presentation, event/feed delivery, tool result,
question/answer continuation, later invocation, main request, compaction, helper
request, MCP call or descendant must carry that union when it can contain or
depend on the worker's data. Mere matching of text or a worker-supplied tag is
not proof of independence. An effect's own results and any resulting assistant
or journal material inherit the union as well. At an uninstrumented boundary,
or when the union cannot be propagated, refuse the protected flow before data
enters the worker; do not drop lineage or silently fall back to generic reads.

Worker termination does not clear lineage already copied into Session state,
durable results, a journal, another worker or a descendant. A question can
close one worker and resume in another, so the Session-owned continuation must
carry the union. Restart/resume must reconstruct it from durable records before
admitting subsequent work. A trusted declassification or reset would require a
specified proof that all relevant data and descendants are absent; no such
operation is currently defined. Bound the number and size of retained entries,
use a conservative fail-closed overflow state, and never evict an entry to make
space. Define explicit lifetime and compatibility rules before implementation.

Even lifetime-wide host taint is insufficient for the current arbitrary worker
boundary. `Worker` launches an owned separate VM, but its OS process has the
user's ambient permissions and the launch does not establish that all network,
filesystem, subprocess or other communication is host-mediated. A worker can
persist or transmit data outside the modeled host paths, and later worker death
cannot retract those copies. A complete enforcement claim therefore requires a
separately reviewed execution confinement/mediation contract covering these
channels and descendants, or a narrower trusted-worker contract with an explicit
threat model. Neither is established here. Do not label arbitrary extension
execution safe merely because a union is attached to host responses.

## Minimum implementation sequence

1. Specify which reads and outputs are covered, allowed worker confinement,
   root identity (including absent versus present), bounds, durable schema and
   upgrade/refusal behavior. Keep legacy or non-observable reads outside the
   protected path unless their provenance can be established.
2. Have the owned storage operation obtain value and witness from one checked
   view. Under the existing project-identity and consent ordering, bind request,
   result, namespace, exact pin, source/eligibility facts, root witness,
   operation and parent invocation to a host-only receipt. Validate the exact
   result and identity again before commit. A value digest alone is insufficient.
3. Journal a versioned receipt and its exact successful action result before
   releasing the value to the worker. Reconstruct the receipt-to-result edge on
   replay; missing, forged, duplicated, reordered, mismatched or interrupted
   records must not become clean lineage. Preserve old journal semantics and
   refuse protected continuation when required evidence is absent. Do not replay
   an interrupted effect or re-read a newer root as if it were the original.
4. In Session state, union receipt identities across worker callbacks and all
   dependent surfaces listed above. Extend action/result, continuation and
   descendant schemas and validators together. Establish each edge from
   Session-owned records, never a worker claim. Ensure the worker receives data
   only after successful durable tracking, and stop on uncertain cleanup.
5. Immediately before each use or irreversible publication, a reviewed owned
   operation must verify current identity, live consent, source eligibility,
   complete lineage, the exact target/body or effect, and every relevant root.
   Hold the relevant authority and collection lock through the actual
   linearization point. `InferenceWire` hashes bind bytes only: they do not bind
   phase, parse settings, lineage, policy or root. The current intent callback
   and closed read view do not supply this barrier. Avoid holding the Session
   GenServer on slow IO, prove a single lock order and owner-death fencing, and
   classify attempted sends or uncertain cleanup as unknown.

Before wiring any route, test actual Session read/commit/resume and all covered
descendant paths, changes or revocation between read and each use, concurrent
writer/owner-death races at the send/effect boundary, taint union and bounded
overflow, malformed/missing/replayed receipts, legacy replay, partial streams,
worker and descendant cancellation, and noninterference of unrelated flows.
Independently attack persistent/unmediated channels under the stated execution
contract. Local unit observations do not establish these properties.

## Narrow bundled Knowledge capture and state prototype

The current native Knowledge capture worker reads a source and quote, then
performs an override `get` and an existing-record `get`. A pending proposal may
also page through a `scan` before a managed commit; otherwise it returns a
suppressed, expired, existing or saved result. These subsequent decisions and
the returned result can depend on observed collection data. `ObservedRead`
currently supports only `get` and `snapshot`: a complete capture path also
needs a same-view public scan preserving reserved-key filtering, pagination,
generation checks, output bounds and root witnessing. Disallowing that path
must be explicit, rather than falling back to unobserved scans. A trusted
bundled-worker exception also requires an independently reviewed, pinned
artifact and dependency closure: a name or reported identity alone does not
prove that executable code is the reviewed worker. No OS confinement claim is
made for that trusted-worker exception.

A private pure-state [prototype](observation-lineage-state-prototype.exs) and
[tests](observation-lineage-state-prototype-test.exs) explore a monotonic
session-wide union, worker generation tracking, 32-origin/16-worker bounds,
and sticky refusal for untracked edges or uncertain cleanup. The source hash is
`578a783ac85fd2f044db2dabaee2d126e426fb74a34c86872709024ae44a68ee`;
the test hash is
`f3055da818ced7e75bd93d55cd0bcd633094d3336514b15a7311a4f6d5eab175`.
Four state tests plus two boundary tests passed in a private graph (seed
20270304). This prototype is archived rather than added to the runtime: an
immutable value cannot force its owner to retain a poisoned successor, and a
new value after restart can discard history. It authenticates neither receipts
nor workers and cannot discover an untracked effect. Those are concrete missing
Session and replay invariants, not implementation details resolved by a set of
digests. It is not a safe standalone gate and must not authorize a read or
publication.

A private-only [visible-scan prototype](observed-visible-scan-prototype.patch)
adds a bounded read-view selector that excludes reserved keys before value IO
and returns a root witness with the public scan result. It refuses stale
generations rather than returning the generic conflict result. The patch is
based on Directory SHA-256
`1aea077f1727e893766e783c0a6e747492f9975dcb9bd54700d92c772d2a2a13`,
ObservedRead SHA-256
`06af1dea20a48f0bab4e316e1ea9d833356a55e18cb8c24ef1831a00068579ea`,
and observation test SHA-256
`c7abf75d1a27a8ac6e1eefed322cfe358097e134aca6f8f2e0cec6fca006273d`.
The patched hashes are respectively
`46a73b6b14420702b0f7b020502b04541906c6f86e2ac8b9becd7786a3527e2a`,
`fdabdc123aae06ff773a5658dbd40ffba4278e034fcbcc63896b370079013992`,
and `490857c031c2a00e96f86d08b615e8898565e12e3ee1dc909394dc8c542962f3`.
The patch SHA-256 is
`88362c9f12f7fb404f71cf936cb7deec07eef0d1d1b997d4043f1dd2aa9c023a`.
It passed 38 observation, read-view and directory tests (seed 20270306) in a
private graph with a test-only 7.2.11 kernel override; the
[log](observed-visible-scan-prototype.log) SHA-256 is
`0e42640ee40bfe6fb40601ee982b629b1d4148e90cd7313cb8def1c746442312`.
The override does not qualify that kernel for production. Independent
adversarial review and actual Session lineage work remain required. The patch
has not been applied to production source.

Independent review of the first prototype passed its 38-test suite and 32
cursor/limit controls but found that stale generation was detected only after
visible values were read. A revised [v2 patch](observed-visible-scan-prototype-v2.patch)
threads the requested generation into the view and checks it after exact-root
revalidation, under the collection lock, before any selected value read. It
adds stale-generation versus corrupt-object, changed-root-between-pages and
scan-specific native owner-loss controls. Its patch SHA-256 is
`992fedb9503a3f3524aa60fd1f32c4f1ef1193aad200cab2b4ffdff7c475e66d`;
the [40-test private log](observed-visible-scan-prototype-v2.log) SHA-256 is
`0a108c6b74654e44a9602361519c2af1b12881a0b08676a2d8ed2793659f462f`
(seed 20270309, same test-only kernel override). The initial revised run had
one failing control because the stale error was collapsed into the generic
error; the final run above passed after preserving the stale error. Independent
review of v2 is recorded below. Neither version is Session lineage enforcement.

An independent private graph reproduced all 40 v2 tests (seed 20270309); its
[log](observed-visible-scan-independent.log) has SHA-256
`35a94e000fda55605e439dc729b3f5c6728ef91d95a3a3cfdf8dfb358628d0df`.
The reviewer confirmed the root/generation check precedes value IO and retained
the trusted-host/cooperative-storage and historical-witness limitations. After
the checked base hashes matched, the exact v2 patch was applied to the working
tree without Session wiring. A newly copied fixed-source graph strictly compiled
143 project files and passed 40 tests (seed 20270310); its
[log](observed-visible-scan-final.log) SHA-256 is
`74ff7519455cccae9bbd6614134782123f23ac7348afdaf34a46875561eb00ba`.
Both graphs used the explicitly test-only kernel override, whose helper SHA-256
is `05d5aa7f9f5c6453254b885b91a6a9dcd602e9077842ae4d05ed7e7bdd591d1a`.
These results are not kernel qualification or current-authority evidence.
