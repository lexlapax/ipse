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

## Private result-binding prototype

An unwired [private receipt prototype](observation-receipt-private-prototype.exs)
explores converting a trusted same-view read into a version-3
`ManagedReference` dependency and binding it to an existing action result.
The [diagnostic tests](observation-receipt-private-test.exs) use actual
test-only storage, including a four-record visible scan that `CollectionCall`
shortens to fit the continuation envelope. The dependency hashes the exact
delivered page and adjusted continuation; the separate observation digest
identifies the original full observation. Binding checks the pin, request,
namespace and action-result shape. Structural replay checks do not themselves
authenticate a receipt, establish current eligibility, or validate the enclosing
action chronology.

In particular, the observation contains a decoded root and its claimed raw
digest, not the raw root bytes. A pure function receiving an arbitrary map cannot
establish that those bytes were actually observed. The tests deliberately show
that a substituted syntactically valid observation digest passes the structural
replay check: durable journal provenance and authenticated owned-child delivery
are required, and neither is implemented by the prototype. Its source SHA-256 is
`f411b4d51f7a143ff26ca919ac3bb0eae06ba84ed3b0747c5055757226a54e04`,
test SHA-256 is
`816f6e7aa353695795b73fdd7a59362e91d629b9bf9e9396ee30636d532d757d`,
and [private log](observation-receipt-private.log) SHA-256 is
`cc4c353b757b8622cdfb5293980a7f0ecf65fa6f523b2d127b077646e07c4698`.
The private graph passed 28 receipt and ManagedReference tests (seed 20270313)
using the test-only 7.2.11 helper override. There is no live Session wiring or
end-to-end replay evidence. Independent review reproduced the 28 passing tests
on the same test-only override and confirmed the same provenance limitation;
its [log](observation-receipt-independent.log) SHA-256 is
`0a88ed14a5428a4adfe389cb3e11f98b3c666753a5df106da8e564381281fe94`.
The reviewer requested action/receipt chronology and tamper/replay controls,
including altered shortened continuations, before integration.

The next private [admission prototype](observation-admission-private-prototype.exs)
explores Session-owned one-use job/token matching, `Resources.authorized_effect?`
and a real `Journal.Writer` capacity reservation for a begin/action-result/receipt
triplet. It returns no observed value to the worker. Its
[diagnostic tests](observation-admission-private-test.exs) exercise an actual
owned file-effect observation and native journal, an unauthorized caller,
token replay and missing/reordered/duplicated/altered triplets. Together with
resource-authority and ManagedReference tests, 30 passed (seed 20270314) using
the same test-only kernel override. The [log](observation-admission-private.log)
SHA-256 is `db16dd98d1af831208fbb61398acce9e0fa05f002b4233dbd0d860c052235288`;
the prototype and test hashes are respectively
`9b372379bca71617465f8486732b5af06ceb977a4e4ec3957c9998d3015a4ce0` and
`f4567fcd010b8aebbd3f51810b0628ca5ff17a30bbbadd299569e8223fff570a`.

This is not an actual Session handler or complete replay protocol. It relies on
the owner passing the actual `GenServer.from` caller, retaining the failed state,
and independently authenticating the selected reviewed artifact, pinned policy
and actual view owner. Its triplet replay must be made mandatory and correlated
with the surrounding action chronology; omission of a whole triplet cannot be
detected by its isolated verifier. It cannot provide worker or Session lineage
propagation, current-root authority at later use, confinement, or rollback of
already-dispatched effects. A failed append can leave a partial triplet and must
remain unknown. Independent adversarial review is pending; no production
component uses this prototype.

The subsequent [v2 admission prototype](observation-admission-private-v2.exs)
adds structural replay over a caller-supplied set of expected protected intents.
It requires each expected intent to precede one contiguous begin/result/receipt
triplet, rejects absent/duplicate/reordered or altered triplets and bounds the
event and expected-intent counts. Its source SHA-256 is
`8bcce46e24d62e87977b0fc6e999ae6eba8b33f9cdd4168859e65bb25347a5ba`,
its [test](observation-admission-private-v2-test.exs) SHA-256 is
`03fb983bf011fa2bcaaef74e22ffd2ca4d0df063b90ecb69f119434cca6cf960`,
and its [30-test log](observation-admission-private-v2.log) SHA-256 is
`c2221a553fbfee519aee2365bf830ca0ca191e448bdda852dd03575484e3bc5c`
(seed 20270315, test-only kernel override). The Session must derive the complete
expected-intent set from authenticated, versioned host records; a worker or
receipt cannot select it. This isolated function does not enforce that premise
or integrate `Actions.restore`. Its test uses an actual owned file-effect and
Journal.Writer but directly invokes the Session-owned functions from a synthetic
owner; it is not an end-to-end Session, reviewed Knowledge artifact, or
production-kernel test. Independent review of v2 is pending.
The owner also synchronously waits for three `Journal.Writer` appends; this
diagnostic establishes ordering, not production Session responsiveness or
cleanup under stalled durable IO. A production integration needs bounded
coordination and verified owner-death behavior.

A separate synthetic [GenServer owner diagnostic](observation-owner-private-test.exs)
passes the actual `GenServer.from` caller to the admission function, obtains a
same-view observation in a `Resources`-owned effect and appends through a real
`Journal.Writer`. It returns only `not_exposed` to the effect; no observed value
is released there. Five combined owner, receipt and authority tests passed (seed
20270317) under the test-only kernel override. The test SHA-256 is
`a2e51d88cbc44ed83edf729f559e871fd8cd93a0da3dd301f0ea00c6004e8b0c`,
and [log](observation-owner-private.log) SHA-256 is
`f1e15cf37777640be595fc95734c24047d4300a2e6855779bc7df553fb714bb3`.
This test owner is not the production Session and does not validate reviewed
Knowledge artifact selection, mandatory full replay or downstream propagation.

## Private nonblocking and versioned replay experiment

The private [Session prototype patch](observation-session-private.patch) has
SHA-256 `3c0bd5be7d39fc7a5c951aacf70d3b969c7a3ce1523eb98e655b941d67144286`.
Its owner-issued `:gen_server.send_request` to the existing owner-only writer
does not wait inside a synthetic GenServer callback. With the writer deliberately
suspended, that owner answered another call; when the request timed out, it
returned unknown and exposed no value. The queued append nevertheless landed
after the writer resumed. A structurally valid late envelope is not evidence
that a Session accepted it: replay and lifecycle fencing must classify the
result conservatively, including owner death and partial writes. The prototype
has no production Session handler for the asynchronous writer path.

A separate test-only Session flag records a versioned lineage header and blocks
selected protected reads before worker delivery. Actual Session tests exercised
that withholding and refused resuming with the test flag removed. A real legacy
Session's journal was then copied in memory, marked with a simulated header and
synthetic envelope, and tested for missing, duplicate, altered and reordered
records. Even the structurally valid case refuses restoration because a live
authority barrier is unavailable. The later same-root observation in that test
was not the original Session read and proves no same-view provenance. The
synthetic artifact and private flag do not prove selection of the shipped
Knowledge worker. Removing an optional header together with its external test
flag can resemble a legacy Session; production requires an independently
authenticated, versioned activation/policy anchor and an explicit legacy rule.

The combined [private test log](observation-session-private.log) has SHA-256
`bb63a207ad9b19c7b6a9ca59858724204d332b7d54571b86860a3b0e2f761508`
and reports 23 passing tests (seed 20270323) under the test-only kernel override.
The test-only Session configuration and source have not been applied to the
working tree. This is refusal-path and structural replay evidence only; it is
not end-to-end protected lineage, current-authority, or production-kernel
qualification. Independent adversarial review remains required.

An additional explicit legacy control is preserved in the
[v2 private patch](observation-session-private-v2.patch), SHA-256
`efc3f2dc5691718f2ae8179e39ce36d326c631f61c721fcc6ad108476bbeb0b4`.
It demonstrates that an unmarked legacy history still restores, so removing
both an optional new header and the associated envelope can resemble legacy
unless a separately trusted activation or policy version requires them. The
[v2 log](observation-session-private-v2.log), SHA-256
`1fe06f56eb971f2b53594f2246c380a3cf9876b16224dfe41ade8b50922d2348`,
reports 23 passing tests (seed 20270324) with the same test-only kernel override.
This control documents a blocker; it does not solve downgrade detection.

The [v3 private patch](observation-session-private-v3.patch) adds a synthetic
owner-death control while the actual writer is suspended, in addition to the
late-append and responsiveness controls. It returned no usable worker result;
the writer terminated and the journal remained inspectable. The patch SHA-256
is `6e7f7ca13124669f0c7f45e95e88e35576bf0351dbd2769196eb9bfdf99c3367`.
The [24-test log](observation-session-private-v3.log), seed 20270326, has
SHA-256 `45f41d6d89430c65e9e3a637d674a5c681471b958b4cd0e8c4ead0dbaa3768c6`.
The same test-only kernel override and synthetic-owner limits apply. Worker
or remote effect fencing, Session journal recovery after a late write, and
trusted version anchoring remain unproven.
