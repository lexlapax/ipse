# Restart checkpoint: pending-proposal acceptance — 2026-10-29

This is an in-progress handoff, not acceptance of P31E or authorization to
replay any unknown effect. The parent owns the main plan and checkpoint. No
test, PTY or native process is known live from this section at checkpoint; the
last native ExUnit handle `91062` exited 0, earlier handle `44241` exited 0,
and the earlier first failed handle `35600` exited 2. The short asynchronous
`functions.exec` cells `1719` and `1738` both finished and handed off those
completed handles. No PTY was reserved for this section at checkpoint.

The actual user request remains real proposal acceptance by exact ID, physical
revision/hash and signed host deadline, with an explicit linked acceptance
event and preserved original source provenance. The independent accepted
direction is [pending-acceptance-independent-direction.md](pending-acceptance-independent-direction.md).
The concrete [proposal](pending-acceptance-proposed-contract.md) SHA-256 at
last verification was `ff0330429485de3ac2d136396031c3fd6e8c04d8949e8f909ee2671f7e3c1396`.
It remains proposed: Core typed mutation and public acceptance are not enabled.

Working source edits in this section:

- `lib/ipse/extension/collection/observed_read.ex` now provides
  `with_managed_proposal/7`. The existing read-view and new retained callback
  share the same signature/anchor/live/override verification; the latter holds
  the native Collection owner through its trusted callback. Last verified source
  SHA-256 `3c39c2693eaf785f36cc8d78f3c9d4def1b4de34e38a02c54b9c1152af12b70c`.
- New `lib/ipse/session/pending_acceptance.ex` prepares closed, bounded exact
  card facts from a signed proposal observation and caller-supplied verified
  proof, samples the signed pending deadline, checks exact 8 KiB preview, and
  can consume a real same-owner `Review` permit into a separate linked
  `pending_proposal_accepted` event. It grants no source, display or mutation
  authority; no production caller invokes it yet. Last verified source SHA-256
  `e0e6c40dff4c3dcd493849c95fc6e70480d3531746302425cf1373f91a438e1c`.
  It has not yet been independently reviewed, exercised with a real `accept`
  permit, wired into Saved chronology/deduplication, or measured for all
  worst-case input/control-byte geometries.
- `test/ipse/extension/collection_normalizer_v3_integration_test.exs` has one
  tagged `held_pending_proposal` test. It uses an actual signed pending
  Collection record and native retained Collection owner but explicitly
  synthetic trusted source members. It compares the original source proof,
  physical revision/hash and signed deadline, exercises card preparation, and
  refuses expiry, missing proof and a fake permit. It does not prove real source
  lease, actual native acceptance input, publication or current-use semantics.

The private `_build/held-pending-proposal-sol-20261029` graph forks the
independently accepted own-root graph and has the above ObservedRead and new
PendingAcceptance BEAMs; it excludes the separate document-embedding Session
delegates as its ancestor did. Strict source compilation logs are
`/tmp/ipse-held-pending-compile-20261029.log` and
`/tmp/ipse-pending-card-compile-20261029.log`. Actual focused native success
is `/tmp/ipse-held-pending-card-native-20261029.log` (1 passed, 37 excluded).
An earlier retained launcher `/tmp/ipse-held-pending-native-20261029.log`
failed before Collection publication with callback unknown because that
launcher omitted `Application.ensure_all_started(:ipse)`; a fresh corrected
run `/tmp/ipse-held-pending-native-v2-20261029.log` passed. The old temporary
homes were preserved; do not replay the failed operation. This new subsection
has not yet been frozen with a complete evidence manifest.

The major live integration gap is original-source ownership during native
display. `ManagementTerminal` currently accepts only `forget` and its
qualified native collector holds exactly four roles: management journal,
Identity, Consent, Collection. A proposal can require an additional original
Session/source lock. Source proof JSON or an old snapshot does not hold that
lease. Shared clarified that the original baseline expressly requires current
source/version eligibility before publication; it does not automatically
require that source lock through faithful local pending-card display. The
existing standalone management display purpose may support the signed pending
derivative as historical without claiming current-source authority. Shared is
marking its earlier stronger source-through-display wording as an open
clarification for Root after restart. Do not copy the expired-target forget
exemption into acceptance or enable a fifth-lease path without proof.

Next resume: resolve the narrow pending-source display purpose with Root; freeze and audit the
retained-reader/card subsection; make the existing same-terminal management
review support the exact `accept CODE` purpose and real owners/expiry; build
the narrow typed Core acceptance and read projection only after closed schemas,
source ownership and exact bounded 32-read/page-split/6,144-byte value/64 KiB
input/2 KiB receipt/8 KiB escaped-card measurements. Preserve original- and
accepted-lineage suppression and clocks, exact source proof values, signed
pending deadline at consume/final admission, one-use permit and no replay.
Prove a genuine CLI signed-pending acceptance and the adversarial cases; pure
card preparation does not complete the task. Coordinate any Session or Core
file ownership with Root and preserve unrelated concurrent edits.

An intervening combined-notes source diagnosis is frozen separately at
[combined-notes-artifact-diagnostic.md](combined-notes-artifact-diagnostic.md)
with manifest `f604c946ea9b15e6b90aacfb18d6740e97c576b60f32412a7e1d1aa798f0cd11`.
The actual 47241 capture committed but its synthetic fixture expected a notice
without selecting the subscribed recall artifact. Root is building a fresh
canonical full artifact for a new combined control; do not replay 47241.

## Accepted-value encoding follow-up

`PendingAcceptance.accepted_values/2` now constructs the distinct closed
accepted-decision value and immutable candidate link described in the reviewed
direction. The deterministic lineage depends on the candidate and original
lineage; the note commits the Collection-encoded link hash, while the link
commits the original pending revision/hash, source-proof digest and exact event
digest. The original proof is retained as a value, without claiming original
serialized bytes. The function checks the encoded 6,144-byte value bounds and
refuses an invalid or non-forward deadline; its caller must still derive that
deadline from current policy and preserve prior clocks and suppression.

The retained native pending-record fixture passed one focused test with the
new encoding and structural revalidation. It checks deterministic keys,
source/link/event hashes, tampered values, a changed event identity, and a
control-character/escaped-text value that exceeds the encoded limit. Its Review
event is explicitly synthetic: structural validation neither authenticates the
display/input nor grants a permit. No Core mutation, current-read projection,
Saved chronology, native `accept` input or public acceptance route is enabled by
this increment. Page geometry, live source/policy ownership, one-use permit,
atomic publication, loss and no-replay controls remain open.

## Direct native Review control

A focused native fixture now creates and reads a signed pending record under
the actual retained Collection owner, releases the owners, and presents the
resulting synthetic-proof card through the existing direct PTY Review API.
Genuine `accept CODE` produces a structurally valid event and accepted values;
the same permit cannot be consumed twice. Bare yes and a wrong code refuse,
and changing the rendered revision spends the permit without accepting either
card. Passing the signed deadline as the explicit clock argument also refuses;
that boundary check is simulated, not a wait for real expiry. The pending
Collection observation remains unchanged. One focused test passed with five
separate PTY scenarios.

This is not the protected management display: its source proofs and policy
facts are synthetic, its display occurs after the Collection lock is released,
and it writes no acceptance event to a management journal or Collection. It
does not authorize publication or qualify source/consent freshness, owner-loss
handling, atomic mutation, or the public acceptance journey.

## Private lease-held acceptance display

The private management terminal now supports a separately bound `accept`
purpose. Its handle records the displayed command and exact facts, and a
different command closes the handle without a reusable permit. The display
labels the candidate historical, requires a structurally valid unexpired
pending card, and bounds the input window by its signed deadline. The trusted
caller must still hold and authenticate the actual Identity, active Consent and
Collection owners; this API does not establish those facts itself.

A synthetic fixture exercised the actual management journal, Identity, Consent
and Collection ownership through native PTY display, checked the displayed
bytes against the Review receipt, released display leases before input, and
reacquired the target and Consent before consuming the permit. Valid input,
bare yes, stale code and cross-purpose use were tested. The cross-purpose
attempt returned cleanup-unconfirmed and could not reuse the handle. A separate
controlled revocation while input waited caused fresh Consent validation to
refuse before consumption. The signed pending Collection record was unchanged.
The source proof and generic Consent policy in this fixture are synthetic;
no original-source lease, semantic publication grant, durable acceptance event
or mutation was exercised. The private API has no production caller.

The existing genuine forget-review control also passed with the command-bound
handle. A stale-epoch display test initially failed because its instrumentation
assigned the pause result instead of the operation result; correcting the
fixture restored the intended refusal check. Both existing native display tests
then passed. Independent review, original-source reacquisition, signed policy
binding and the full atomic acceptance path remain open.

## Pre-consumption public-change planning

The live Review owner can now inspect its exact pending receipt without spending
the permit. `PendingAcceptance.preview/3` derives the prospective event, and
the later consume returns the same event only after the real one-use Review
succeeds. A retained-proposal callback now exposes its same-owner, 32-unit
Collection read closure to a host-only planner. The planner checks the pending
record, signed metadata, observed root and deadline against the event; it reads
the deterministic note and link destinations for absence and constructs the three
public CAS changes within the existing input/value bounds. It grants no authority
and must not be published without the separate signed sidecar, suppression,
source, Consent and final-deadline checks.

Two focused native tests passed. One uses a signed pending record and the actual
held read for destination absence and checks the 32-unit ceiling and a
cross-process read refusal. Changed-root, existing-destination and deadline
refusals use modified observations or a synthetic conflict callback. The other
previews the native Review, plans the public changes under
the reacquired Collection owner, then compares the consumed event; its source
and Consent fixtures remain synthetic. Sidecar planning, worst-case page splits,
receipt geometry, original-source ownership and atomic publication remain open.

A further read-only geometry probe populated a real signed Collection with 27
literal rows and one pending proposal before planning one accepted anchor edit
and the pending-live deletion plus accepted-live insertion. The retained
Collection callback used 30 of 32 read units and produced three sidecar changes
with unsealed encoded body sizes of 1,822, 2,431 and 2,051 bytes. This probes
one populated layout, not every split or merge: two read units remain in this
case, and additional neighbor or buddy reads may exceed the limit. The accepted
rows contain placeholder hashes and eligibility and must not be sealed or
published. Actual accepted semantics, suppression, receipt size and worst-case
page geometry remain unproved.

The same probe was repeated with 60 literal rows. Both layouts used 13 read
units for the retained pending observation, two for the absent public
destinations, five for accepted-anchor planning and ten for the two live edits.
The larger layout again produced three sidecar changes, with unsealed body sizes
of 3,791, 2,387 and 2,198 bytes. The pending observation and live repair each
look up the pending live page; retaining and reusing authenticated observations
under the same real owner may reduce repeated work, but no such reuse is
implemented or qualified. The existing per-call read allowance remains intact.

A 120-row population produced the same 13/2/5/10 read-unit breakdown and three
unsealed sidecar bodies of 3,663, 2,386 and 3,079 bytes. Increasing population
alone did not force a worst-case repair. The actual 32-unit limit counts
repeated calls and latches on excess, so silently memoizing the general read
closure would change its established contract. Any future observation reuse
must instead retain the exact authenticated page and neighbor evidence inside
the same live owner, reject cross-process or escaped use and owner loss, and
remain bounded; this probe does not implement or validate that interface.

## Bounded reuse under the retained owner

The private proposal-planning callback now retains the exact pending live
neighbor result and its selected record from the original authenticated read.
Each can be reused once by the planner. A separate non-consuming lease check
requires the same process, same live native Collection owner and open read
allowance before and after returning cached evidence. All other reads use the
existing per-call accounting; an exhausted allowance remains latched. This
does not grant source, Consent, mutation or publication authority.

The 27-, 60- and 120-row probes now use 25 units each, with phase totals of
13, 15, 20 and 25; the original small probe uses 24. Seven focused native tests
passed, including cross-process and escaped-closure refusal, read-budget
exhaustion, native owner death, and the existing Review and planning controls.
The accepted rows still contain synthetic values. Worst-case splits, actual
source eligibility, accepted semantics and atomic publication remain open.

## Accepted retention calculation

The private acceptance module now calculates an accepted decision's anchor
and value deadline from a caller-supplied literal category rule, acceptance
time, previously authenticated anchor and current policy deadline. Existing
first-admission and pending clocks are preserved, an older baseline can only
narrow, and a policy deadline can only narrow the effective value deadline.
An expired baseline, future prior clock, native choice or retirement refuses.
The literal recipe is used only for the category's retention duration; it does
not reclassify the original source proof as a literal operator assertion.

The focused signed-pending fixture covers fresh ordinary and preference
deadlines, an existing shorter baseline, policy shortening, retained pending
clocks, expiry and suppression refusals. Its acceptance event, source proof,
prior anchor and policy deadline are synthetic. The calculation is pure and
does not authenticate those inputs, seal a live row, journal a native event or
publish a decision. Actual owner-bound source, policy and anchor checks and the
atomic acceptance operation remain necessary.

The private preparation path now reads and authenticates the accepted lineage's
anchor page at the same retained root, refuses a corresponding override, derives
retention, and prepares the public changes. A new checked page-planning entry
point requires each authenticated old row to be absent or exactly equal to its
specified value before producing a repair. Its tests cover absent and matching
rows, stale replacements, occupied insertions and duplicate edits. The focused
native pending fixture also prepared a fresh accepted anchor through the actual
Identity and Collection owners and planned its insertion within the existing
read allowance. The event and source remain synthetic; this does not yet plan
or seal a complete live transition or authorize publication.

The same retained-root fixture now plans both the accepted anchor and the live
transition. The checked planner requires the pending live row to equal the
authenticated pending metadata and the accepted live identity to be absent.
The planned accepted row uses a separate wire marker, restricted to note keys
and the three accepted categories; it is not the literal-current marker. The
fixture decodes the proposed live page and verifies the pending row is removed
and the accepted row has that marker. It stays within the 32-unit read limit.
The codec and checked-planner suite passed 14 tests, and four focused native
acceptance/review/lease tests passed. The marker is syntax only: no current-use
projection, source eligibility, signed mutation, durable event or old-reader
compatibility qualification has been completed. The fixture's event and policy
are synthetic, and the precise active publication-policy binding remains open.

The native PTY management fixture now previews the actual one-use review event,
reacquires its Identity, active test Consent and Collection owners, prepares
the public and checked sidecar changes, and consumes the same permit only after
planning. Its test policy expiry narrows the prospective retention deadline.
Valid input, cancellation, wrong code or purpose and revocation while waiting
were exercised; the source and policy remain synthetic, and no acceptance event
is journaled or published. Four focused native controls passed.

A separate local codec probe compiled the exact older page module from commit
`be7bc9ee5ae35a06893c2616636c7732530f0617` under a test-only module name.
It rejected a page containing the new accepted marker while the current codec
round-tripped it. This proves rejection by that one prior parser, not complete
old-backup, migration or mixed-version operation behavior. The probe inputs and
legacy source were retained under `/tmp/ipse-legacy-page-probe-20261030.exs`
and `/tmp/ipse-legacy-managed-pages-20261030.ex`.

## Durable native review fixture and reconstruction

New management journals identify the pending-acceptance record layout. The
native review fixture now appends its consumed acceptance event through the
actual journal owner after releasing the Collection owners, reloads the JSONL,
and validates its journal, project and namespace bindings. Saved reconstruction
checks the declared layout, event shape, ordering and unique native review,
operation and candidate IDs; historical records never recreate a permit. The
fixture uses synthetic source and policy evidence and performs no publication.
The production acceptance route, source validation and end-to-end effect and
recovery integration remain open.

The review state machine now has a separate one-use acceptance effect claim
after review consumption. A changed first claim spends it, a second or
cross-process claim refuses, and an error or interruption after a claim is
unconfirmed. In the native fixture the reserved acceptance event and exact intent
are now appended by the actual journal owner while source, Identity, Consent
and Collection remain retained; only then does the fixture sign and claim the
effect, followed by its deliberate no-publication refusal. The reloaded journal
checks that order. This does not itself connect the claim to a native root
switch or implement a committed receipt.

The private journal contract now admits a closed effect intent containing the
exact three public CAS changes and their digest, bound to the acceptance event,
operation and original root. A result can currently say only `refused` or
`unknown`; committed publication requires a separately validated native receipt
and is not implemented. Reconstruction rejects results without prior intent,
duplicate records, mismatched requests and digest changes. A missing or unknown
result is returned as an unknown effect for inspection, never replayed.

The native PTY fixture reserves three journal records before review, then
appends the acceptance, intent and a deliberately refused result through the
actual owner. It validates the reloaded journal and tests interrupted and
unknown outcomes by removing or replacing the result in memory. No actual
publication or crash was simulated. Two focused native tests and ten saved
session tests passed; actual native result receipts and interrupted publication
remain unqualified.

The private acceptance module can now retain and revalidate the original
Session source through `StoredSources.with_verified/4` while a caller holds its
callback. It requires the candidate's project, namespace, binding, policy epoch
and consuming Session or management journal identity to match the admitted
context. A focused test used a real retained original journal and source proof,
verified that its native lock remains held during the callback, and refused a
different policy, a well-formed but missing source and native lock-owner loss.
The test journal was synthetic; the surrounding acceptance display and effect
have not yet been integrated with this source lease. Current protected Consent,
source exclusions and publication authority remain separate caller checks.

## Current source-policy checks

Acceptance now has a private check for the exact current semantic policy,
project, namespace, expiry, permitted source category and the registered
proposal and note recipes. The caller must still hold the protected Consent
lease and original source owner; the pure check grants neither authority. The
current Session proof schema uses a nil path, so this fixture does not exercise
path exclusions.

The PTY fixture now installs a valid synthetic semantic policy in the protected
Consent store and repeats this check during selection, retained display and
post-input planning. It also rejects a different note recipe and an expired
policy. Removing the original source category from a newly saved policy
prevented the card from appearing and produced no acceptance event; the
surrounding management control returned `management_control_unconfirmed`, not a
clean denial, and that cleanup path remains open. Four focused native controls,
seventeen source/saved-session tests, compilation and formatting passed.

A later repair adds an explicit native cancellation acknowledgement before an
owner control has transferred any descriptor. The journal and CLI owners both
require that acknowledgement and successful helper exit before returning a
pre-display error as a clean refusal. Unknown, successful or already transferred
paths do not use this shortcut. The denied-source fixture now returns the
specific refusal without displaying the card or recording acceptance. Focused
management tests also check that an unreviewed success remains unconfirmed.

The PTY management fixture now constructs the pending proof from an actual
test Session journal in the same project and namespace. Its display and
post-input planning callbacks run inside the original journal's retained source
lock, with Identity, test Consent and Collection owners nested inside it. A
second process acquired that source lock while input waited; reacquisition then
refused before permit consumption. The existing concurrent Consent revocation
control also passed. This is a synthetic journal and policy, not a production
acceptance route. The native display lease stack does not yet include the source
lock, so source-owner loss during display and all-copy closure remain unproved;
the source policy/exclusion and atomic publication gates remain open.

An inactive original source can now be opened through a private shareable
native lock with an owner-bound, one-use export and settlement token. Its
identity is checked against the retained lock inode; a failed transfer poisons
the token, and an unconfirmed settlement prevents the callback result from
escaping. An actual native collector received and settled the source lease;
recipient death after transfer refused the callback. Cross-process and escaped
tokens, invalid transfer, source-owner loss and later lock reacquisition were
also checked. Nine source and retained-transaction tests passed, as did the PTY
fixture using the new lock without transferring it to the display.

The terminal's current manifest accepts four leases and does not yet carry this
source lease. The isolated transfer therefore does not establish source-owner
loss behavior during display, complete all-copy closure, policy checks or
publication. No public acceptance route has been enabled.

The private acceptance display now uses a distinct v7 native terminal protocol
with five exact transferred leases: the management journal, Identity, Consent,
Collection and the original source. The native guardian requires the expected
slot order, watches the source owner and retained transfer while writing, and
settles the source lease before allowing terminal input. The four-lease v6
protocol remains the path for existing management actions. The acceptance PTY
fixture passed with the real test source, including its post-display lock race
and Consent revocation. Two existing four-lease display tests and nine retained
source/transaction transfer tests also passed. A rebuilt native helper passed
78 Rust tests with two ignored after local PTY/socket access was enabled; the
same suite initially failed under sandbox PTY/socket restrictions.

This establishes the positive five-lease handoff in a fixture, not the full
owner-loss qualification: a source owner has not yet been killed at an
instrumented point during the v7 display. Active source-policy checks, native
publication, interruption recovery and a public acceptance journey remain open.

A later focused v7 control rebuilt the isolated helper with the existing
test-only prewrite stop. After all five leases transferred, the test stopped the
display reader immediately before its first write, killed the actual retained
source owner, and observed the reader reaped without candidate text or a
successful input event. It reloaded the actual management journal and found no
acceptance or effect-intent record. The ordinary non-hook helper was restored
afterward. This covers that prewrite boundary only; loss after a partial display,
the other owners, all-copy closure under every failure and production publication
still require qualification.

The focused v7 loss control now also uses a bounded real-source proposal whose
display exceeds 4,096 bytes and whose marked private tail lies after that byte
offset. With the test-only helper paused after its first write, killing the
source owner reaped the reader: the captured terminal contained the beginning
of the card but neither the marked tail nor the confirmation prompt, and the
management journal contained no acceptance or intent. The prewrite case passed
again in the same run. The normal helper was restored. These are two controlled
source-owner loss points, not exhaustive output, multi-owner or publication
qualification.

The current repository-wide `mix format --check-formatted` passed
(`/tmp/ipse-full-format-20261030.log`). The public dense producer still exposes
selection, page and inspection only. `Producer.Progress.append/5` is a private
controller for bounded, validated supplied facts; its maximum-count result is a
model, not a public native group-production journey. A public path must preserve
source-bound fact validation, bounded transport and the recorded per-invocation
limits rather than exposing an unbounded group payload.

The current artifact passed the public two-page guarded producer Session using
local synthetic embeddings (seed 520736;
`/tmp/ipse-producer-public-two-page-current.log`). It starts with an empty
selected root and does not establish group append or selected-root reuse.

The native document publication-loss fixture now validates the exact owner
marker, then the single signed no-lifecycle release intent, while retaining the
unknown append and unchanged-storage assertions. Its focused run passed
(`/tmp/ipse-document-native-unknown-retest3.log`). An intermediate attempt
incorrectly expected a lifecycle closure and failed; the actual close has no
epoch or closure digest, which the corrected test explicitly checks.

The current-source selected-root control now uses an actual native Session and
local synthetic embedding service with one provided source. It produces a page,
aborts the first Job, and seeds a synthetic version-2 prior selection directly
as a trusted fixture. A forged old ready-slot page outside that selection is
refused without embedding dispatch or a managed storage mutation. Restoring the
slot permits the second Job to reuse the identical immutable page; its stored
record and selected root remain unchanged, and the journal shows no page write.
Saved reconstruction passed (seed 919221;
`/tmp/ipse-native-selected-reuse-try5.log`). Earlier attempts exposed a wrong
source recipe and a duplicate seed key, both corrected in the fixture. The
existing native paged-finalization test also passed after the seed helper was
extended (`/tmp/ipse-seed-paged-finalization-regression.log`). The seeded root
and facts are trusted synthetic setup: this is not public fact production,
public selected-root finalization, wide-group capacity, or full qualification.
The same selected-root control subsequently passed with Saved reconstruction
also checked after confirmed close (seed 618693;
`/tmp/ipse-native-selected-reuse-close.log`).
It now also starts a later Job, replaces the selected root with identical bytes
at a new native revision, and requires the stale Job to refuse before embedding
or a journaled Collection mutation. The root and immutable page stay unchanged
after refusal, and Saved reconstruction passes after close (seed 825188;
`/tmp/ipse-native-selected-root-stale.log`). This is a pre-dispatch revision
check, not an interposition at the final effect boundary.
Another actual Session control replaces the selected root at the embedding
approval wait, after the producer has written its pending claim. The approved
request produces no local HTTP body; the worker refuses, the claim remains
pending, the immutable page stays unchanged and Saved reconstruction passes
after close (seed 81305; `/tmp/ipse-native-selected-delayed-try2.log`). The root
is still trusted synthetic setup. This is one approval-delay schedule, not a
complete egress or cleanup proof.
The approval-delay control now also covers an identical source-head value at a
new native revision. Both root- and source-change cases passed: each refused
before an HTTP body, retained the pending claim and immutable vector page, and
restored after confirmed close (seed 991112;
`/tmp/ipse-native-selected-source-delayed.log`). These remain two controlled
approval-wait schedules over trusted synthetic selected-root setup.
Separate held-response controls let the local synthetic service receive one
embedding request before changing either the selected-root or source-head
revision. Both runs then returned the response, refused ready publication,
retained the pending claim and original immutable page, and restored after
confirmed close (seed 517085; `/tmp/ipse-selected-inflight-root-source.log`).
The request had already left the host; these controls neither cancel it nor
claim that an admitted external effect was rolled back. The prior root remains
trusted synthetic fixture setup.
The ordinary two-page native control passed after the fixture gained its
held-response mode (seed 302290;
`/tmp/ipse-producer-two-page-wire-regression.log`).
Two additional actual Session controls change the selected root or source-head
revision while the already prepared `ready` inline write waits for approval.
Both then record a definite `document_store_refused` action result, leave the
slot pending and the prior immutable page unchanged, and restore after close
(seed 153620; `/tmp/ipse-selected-ready-root-source.log`). These controls use
synthetic fixture writes before approval; they do not interpose inside the
native syscall or establish a physical deadline fence.
The seven selected-root reuse, approval-delay, held-response and ready-approval
controls then passed together (seed 35343;
`/tmp/ipse-selected-root-current-controls.log`).

A separate actual Session owner-loss control uses one source and an empty
selected root. It kills the Session after the local synthetic embedding service
receives the request and before sending a response. The service observes its
socket close; the journal retains one dispatch and an unresolved embedding
action, the producer claim remains pending, and an idle resume sends no second
request or ready publication (seed 258410;
`/tmp/ipse-producer-owner-loss-verified.log`). The remote effect could already
have occurred; the control does not assert rollback.
The owner-loss and two held-response controls also passed together with the
shared socket fixture (seed 126687;
`/tmp/ipse-producer-held-socket-regression.log`).
The owner-loss test subsequently added a second native case with a trusted
synthetic version-2 selected root. Both empty- and selected-root cases passed;
the selected root and immutable page stayed identical, the socket closed, and
the unresolved action was not replayed after idle resume (seed 49826;
`/tmp/ipse-producer-owner-loss-selected.log`). This does not prove public
selection or every owner-loss interleaving.
Both cases also passed with a second Saved reconstruction after confirmed
resume close (seed 591739; `/tmp/ipse-producer-owner-loss-selected-close.log`).

An additional native selected-root control stops the actual Session at the
`extension_action_commit` boundary after the `ready` record is visible in the
Collection but before its result is journaled. Session death leaves the exact
ready-write intent unresolved; idle resume does not replay it, the ready row,
selected root and immutable page remain unchanged, and Saved reconstruction
passes after close (seed 912389; `/tmp/ipse-ready-owner-loss-try1.log`). The
prior selection and facts are trusted synthetic fixture setup. This checks one
lost-receipt boundary, not public fact production, every native crash schedule
or whether the user observed the completed effect.
That case and both in-flight owner-loss cases passed together (seed 146232;
`/tmp/ipse-producer-crash-boundary-controls.log`).

Compact fact-page decoding now regenerates citations as a bounded batch after
validating the source and chunk list, then retains the existing per-citation
checks, fact validation and exact canonical repack. A malformed citation refuses
the entire batch. Current source and separately built artifact controls passed:
31 evidence tests, four producer compatibility tests, six document-ingestion
tests and one native selected-projection Session test. Their logs are
`/tmp/ipse-batched-evidence-test.log`, `/tmp/ipse-batched-facts-compat.log`,
`/tmp/ipse-batched-facts-document.log` and
`/tmp/ipse-batched-facts-native-session.log`. An initial tag selection excluded
all tests; the corrected wrapper ran the intended case.

For a small local synthetic timing comparison, the retained
[benchmark](fact-batch-benchmark.exs) decoded the same 32 facts and 256
citations five times. One earlier-source run took 404,602 microseconds and one
current-source run took 94,213 microseconds; source and packed-page hashes
matched. These single runs are not a controlled capacity or latency guarantee.
The benchmark and its inputs used no live service. The full development build,
repository formatting check, warnings-as-errors compile and credential-free demo
passed afterward. Public fact staging, group append, maximum geometry and full
P30/P31 qualification remain open.

The retained [differential control](fact-batch-differential.exs) compiled the
earlier frozen and current Evidence/Projection implementations side by side.
It found identical results for 648 valid, malformed and boundary span cases
and 20 valid or altered fact-page cases across legacy and Collection source
formats (`/tmp/ipse-fact-batch-differential.log`). This grid uses synthetic
plain-text sources; the separate document-ingestion and native selected-citation
tests provide the document coverage recorded above. It is not an independent
review or a full producer-capacity test.

The existing graph extraction adapter now validates all structurally valid
fact citations with the same source-span batch, preserving the valid-source
empty-list case. The isolated package suite checked a 32-fact explicit batch,
empty facts and a structurally valid citation bound to different source content;
the graph population suite also passed (`/tmp/ipse-adapter-batch-packages.log`,
`/tmp/ipse-adapter-batch-graph.log`). On one synthetic 32-fact, 256-citation
sample, five explicit-adapter validations took 269,555 microseconds against
the earlier source and 41,552 microseconds against current source, with matching
source and fact hashes. The retained [benchmark](adapter-fact-benchmark.exs)
is illustrative, not a latency or capacity guarantee. The full development
build, formatting, warnings-as-errors compile, documentation check and
credential-free demo passed after this change. A separately built Graph artifact
also passed its local provider/lifecycle control
(`/tmp/ipse-adapter-batch-graph-native.log`). Public shared-producer fact staging
remains open.

The activation overlay's saved-resume control now checks the exact owner marker;
its outer packaged-catalog test and child controls passed (seed 344566;
`/tmp/ipse-activation-session-retest.log`).

Two baseline PTY tests failed because their child selection also ran a newly
added read-only recall test, producing two passes where the driver expected one.
The recall test is now excluded from those child runs and passed independently
(seed 554071; `/tmp/ipse-knowledge-readonly-tag.log`). After the baseline
finished, both native capture PTY tests passed (seed 771341;
`/tmp/ipse-knowledge-native-pty-retest.log`).

The mixed-filesystem baseline subsequently finished with exit 2: 3,349 of
3,466 tests passed, 117 failed, 53 were skipped and 80 excluded (seed 605639). Its complete
log is `/tmp/ipse-p30p31-mixedfs-suite-20261030.log`. The source and dependency
hash manifests both rechecked without changes; the recorded directory symlink
also retained its target. This snapshot predates the fixes recorded above and
contains no Git metadata, causing three evaluator setup failures; it is not a
passing current-source baseline. Existing publication and output gates account
for multiple failures, and the remaining failures require individual assessment.

## Review-bound sidecar signing

The retained plan can now be signed once inside the same Collection owner after
the exact native review permit is consumed. A verification-only Identity
capability refuses before planning; the signing closure also refuses cross-process,
premature and repeated use. It checks the pending and effective policy deadlines
before and after signing and verifies the retained native owner is still live.
This produces candidate signed sidecars only; it neither appends an effect
intent nor switches a Collection root.

The native PTY fixture reacquired a publication-capable Identity lease and test
Consent, retained the original test source, planned within the existing read
limit, consumed the real one-use review and sealed the changes. It verified the
resulting MACs and rejection of modified bodies. A separate premature-signing
scenario refused without consuming the permit, and a verify-only capability
refused before invoking the signing callback. Four focused native controls and
seventeen source/saved-session controls passed. Actual source-policy exclusion,
effect admission, final native deadline, receipt and atomic publication remain
open; the test policy is synthetic and the signed pages were not published.

While running saved-session regressions, a handoff import was rejected because
the current native release-owner start precedes the handoff record. Handoff
validation now accepts one structurally valid initial release-owner marker;
the release-receipt validator still checks its session and sequence.
The regression verifies that resume preserves the existing journal prefix and
adds only the expected owner and release-intent records, without reimporting or
rereading the handoff artifact. Ten focused handoff tests passed.

The earlier isolated full-suite process `18104` subsequently exited 2 after
3,887.9 seconds: 3,007 of 3,384 tests passed, 377 failed, 64 were invalid,
53 skipped and 55 excluded. Its retained log is
`/tmp/ipse-p30-p31-clean-suite-20261029.log`. The snapshot was changed while
the run was live and predates later fixes, so these numbers are diagnostic and
do not establish a fixed current-source baseline. Failures include stale
recovery expectations, fixture/build-context errors and managed paths that need
individual disposition; they cannot be assigned to a single cause.

The acceptance effect claim now checks the exact reconstructed public intent,
including the reviewed event, and refuses an expired candidate. The first
same-owner claim spends the permit even if its intent is changed; a different
process cannot spend it. The terminal-backed fixture journals a real intent,
tries a changed intent, and confirms that the original claim cannot then be
used and recovery reports the journaled intent as unknown. The fixture does
not switch a Collection root. The caller remains responsible for durable
journal admission, the retained owners and a final native publication deadline;
the claim alone does not establish those conditions. Eighteen permit-state
tests and two focused Collection controls passed in the isolated build copy.
The claimed-receipt inspection also now refuses at the candidate expiry, even
when the claim was made earlier. A simulated wall-clock boundary test covers
that host check; it is not a native root-switch deadline or a publication test.
The one-use sidecar sealing callback now also assembles and validates the exact
combined public and signed-sidecar request under the retained Collection owner.
A native management fixture checks that the public changes and every signed
sidecar appear unchanged in that request. This is preparation only: it does not
bind the combined request to a native switch or publish a Collection root.
The sealing callback now binds the combined request digest and its public
intent to the consumed one-use Review before an effect claim can be made.
The claimed request can be checked against that digest; this check does not
authenticate a journal append, source lease or native switch. On the current
worktree, the Review and complete Collection normalizer integration files
passed 64 tests together, and a subsequent Review-only rerun passed 20 tests.
The latter fixture substitutes native input and uses a synthetic intent; the
Collection file includes the separate real-terminal management control.
The claim and later request check now also expire at the earlier of the pending
candidate deadline and the prepared retention/policy deadline. Twenty-two
simulated Review tests cover those boundaries; two focused real-terminal and
Collection controls passed. The final native switch must still apply the same
or an earlier deadline independently.

The native transaction root-switch path now rechecks the identities of all
locks in its retained stack after staging validation and before its final
deadline decision. Native tests cover a refused guard and a replaced retained
lock name without a root rename; seven native transaction tests and 25 Elixir
transaction, deadline and retained-share tests passed. The guard does not yet
receive or monitor the separate original source lease, and the existing
check-to-rename scheduling qualification still applies. Acceptance publication
remains fenced.

The retained-lease collector now rechecks the received lock descriptor's
metadata, exporter process and quiet channel before reporting collection.
A native control exercises changed permissions and unexpected channel data;
the nine source-transfer and retained-share integration tests also passed.
This collector check is not yet called by the transaction switch and does not
complete source-held publication.

A full suite was started from the isolated current-source snapshot
`/tmp/ipse-current-baseline-20261030`, with output in
`/tmp/ipse-current-baseline-20261030.log`. The snapshot predates the collector
and source-bootstrap repairs just described. Its first observed failure was a
capacity bootstrap fixture that compiled an extracted helper without its
`Runner` alias. The workspace helper now uses the fully qualified module, and
the focused bootstrap regression passed. The suite was still running when this
checkpoint was written; no completion or whole-suite result is claimed here.

The Linux native transaction owner can now receive one separately retained
original source description, monitor its exporter through the root decision,
and settle the transfer before releasing its transaction locks. A synthetic
transaction transferred a real original-session lease, changed a fixture root,
and settled the source; a second control killed the source owner before the
decision and observed the old root. Fifty-four source and transaction tests
passed. These controls do not cover source loss during staging or at every
native decision instruction, journal-owner loss, the complete Review/Consent
journey, or durable acceptance receipts. The managed acceptance root switch
remains fenced and the helper protocol is not a public acceptance command.

An isolated helper compiled with `ipse_source_switch_test_hook` paused the
actual transaction immediately before and after its guarded root decision. In
each case the fixture killed the original source owner and received an unknown
outcome. Before the decision the old root remained; after the decision the new
root was present, illustrating why a lost response must not be replayed. This
control covers those two instrumented points in a synthetic transaction; it
does not qualify journal-owner loss, acceptance publication or all possible
failure interleavings. The production helper is built without this test hook.

The transaction can now retain both a frozen management journal lock and the
original source lock through one synthetic native root decision, and settles
them in reverse order. The journal fixture confirms that writes are refused
while frozen and that its intent and result append on either side of the
transfer. Fifty-five source and transaction integration tests passed. This does
not yet fence loss of the BEAM journal writer at the native decision, prove the
full reviewed acceptance flow, or enable managed acceptance publication. The
terminal-backed combined-lease fixture could not reach review while the ongoing
full-suite process held the shared operator terminal lock; it remains to be
rerun after that process exits.

The journal writer now owns an additional native control channel while its
barrier is active. The transaction owner retains that channel alongside the
two lock descriptions and checks it at its final decision. A synthetic
instrumented control killed the actual BEAM writer before and after that
decision: the former left the old root, the latter left the new root, and
neither produced a confirmed result. Both source- and writer-loss hook controls
passed in the isolated test-helper build. The focused journal, source and
transaction selection passed 60 tests with one skipped. These controls do not
yet establish the complete acceptance journey or authorize its root switch.

The writer's frozen barrier now includes bounded digests of its two immediately
preceding acceptance records. An acceptance-specific journal lease requires the
exact event and effect intent to match that barrier; intervening records break
the match. A native guard also refuses unless the transaction currently retains
both descriptions and the writer control. Fourteen source and barrier tests
passed, including a synthetic ordering/invalidation control. The separate
terminal-backed acceptance fixture has been updated to use the stronger lease
but remains unverified while the full-suite process holds the terminal lock.
Neither guard is a Collection publication API or evidence of a committed effect.

After the shared terminal became available, the updated real-terminal fixture
passed with the exact journal-bound acceptance guard, both retained leases and
writer control held together. It also refused a changed intent and a cross-process
guard check. A further 38 focused journal, source, transaction and Review tests
passed, with three excluded. The guard is scoped to the same owner and the exact
event/intent pair; it still does not mutate the Collection or establish a durable
committed-result receipt.

A host-private held-Collection acceptance callback can now apply the exact
claimed combined request after checking the journal-bound native guard, Review
receipt, root witness, CAS revisions and bounded publication deadline. Its
first same-owner attempt spends the callback; cross-process and altered requests
refuse. The real-terminal synthetic fixture exercised the complete retained
Identity, Consent, journal and original-source stack: an altered request left
the proposal intact, while the matching request switched the root to remove the
proposal and add its note and acceptance link. The fixture records the effect
as unknown because a committed-result receipt and recovery verification are not
yet implemented. The public management route remains fenced; the fixture does
not establish later-use provenance or the complete P31 journey.

The later fixture now appends a committed-result record after a confirmed
switch and lease settlement. Historical validation binds its receipt to the
exact accepted event, public intent and combined signed request; a changed
receipt is rejected, and a missing result reconstructs as unknown. The altered
request control still records unknown and leaves the proposal intact. This is
structural journal validation, not proof of present source eligibility or an
independent audit of retained pages. The public acceptance command and later-use
path remain unfinished.

Accepted links now carry the originating journal ID and kind. A host-private
reader retains the original management journal, checks its origin, resolves the
matching committed event, and requires the exact link. A held Collection read
then checks the note, link and authenticated anchor/live rows against that
event. A separate current-policy check applies source exclusions and the
effective deadline. The synthetic terminal-backed fixture held the original
journal, original source, current Consent and Collection together, and refused
expired records, changed events and links, copied journals, project mismatch,
excluded sources and cross-process capabilities. This validates an internal
read composition; it does not yet provide a current-use delivery fence, worker
recall integration or a public acceptance journey.

The current-policy check also requires the exact literal recipe to remain in a
registered managed-read mapping, in addition to its publication mapping. The
terminal-backed fixture passes with that registration and refuses an otherwise
valid policy that removes it. This prerequisite does not identify a particular
calling operation or grant disclosure authority.

A subsequent read-boundary review found that a mapping without the literal
recipe could otherwise classify an accepted record as root-only data. Managed
reads and replay coverage now refuse accepted-decision and acceptance-link
records until their separate current-use path is implemented. A native
Collection control passed for both a proposal-only mapping and a literal mapping,
and the replay coverage test passed. These are refusal controls, not evidence
that accepted decisions can yet be delivered.

The original inactive management journal can now expose a private, one-use
transferable lock lease after its origin and committed acceptance are verified.
Within one file-effect owner, the terminal-backed fixture transferred that lease
and the separately verified original-source lease into the three-lock Collection
transaction and settled both. Cross-process access and reuse of the journal token
refused. This preserves two native lock descriptions for a future use boundary;
it does not fence a sender, terminal output, or a later use after settlement.
In two additional runs of that fixture, killing either the inactive journal
lock holder or the source lock holder after both transfers prevented a successful
overall observation. When the owner survived to report the native transaction
check, that check refused. These controls do not exercise a send or output
interposition.

`ManagedUse.inspect_accepted/3` now composes the original journal and source
leases with the consuming Session's admitted identity, current Consent, signed
Collection observation and both retained native descriptors. It returns only
a bounded historical reference, hashes and a deadline after cleanup. The terminal-backed fixture
uses a distinct consuming Session and checks the exact note, link and event;
changed links and revoked consent refuse. This inspection grants no worker
selection, model send, terminal display or later-use authority.
The live fixture also replaces Consent with policies excluding the source and
removing the read recipe; each fresh admitted pin refuses inspection. Restoring
the allowed policy admits a new inspection, and revoking it refuses again.

That reference has a distinct version binding the accepted note and link,
original journal and event, source version, recipe and retained expiry. Actual
signed-record controls reject changed note, link, event and source facts. The
ordinary managed-use gate still refuses this version, so a structural reference
cannot enable an unfenced delivery.

The host can now reinspect that reference by discovering its current link and
revalidating it through the same journal, source, Consent and signed Collection
owners. The actual fixture passed after an unrelated Collection root advance,
refused an incomplete original source journal, passed after the fixture's source
was restored, and refused a changed event hash and consent revocation. The
inspection remains historical; later disclosure still requires its own fence.

The private native collector also accepts a new exact five-entry manifest for
Identity, Consent, Collection, original management journal and original source.
The terminal-backed fixture transferred and settled all five real lock
descriptions together and refused a reordered manifest. Existing transaction
and four-entry collector controls passed. The collector is inert: it cannot send
or display the decision, and these results do not qualify a delivery boundary.
Rebuilding the native helper changes its binary; earlier fixed-helper capacity
receipts and their pinned hash are not evidence for this new binary.

Read-only `knowledge operation` inspection now recognizes structurally valid
acceptance journals. It reports a committed, refused, not-started or unknown
historical effect without disclosing candidate text or replaying it. A missing
result after intent and an incomplete tail report unknown; the fixture checks
both without repairing or changing the inspected journal. This is diagnosis,
not current-note eligibility or a public acceptance command.

The standalone acceptance fixture now derives its source-correlation context
from the protected policy snapshot, project binding, management journal ID and
both registered publication recipes. It refuses a changed artifact or recipe
and an expired snapshot. The caller must still authenticate the installed
artifact and reacquire current Consent; this context grants no review or effect.
The management host can now derive that context from the installed, reverified
knowledge artifact and the current protected project policy. An isolated
installed-bundle control passed and refused a foreign policy artifact and a
tampered installed sidecar. This selection is historical and does not open the
public acceptance route.

The management host now has a two-pass pending-target continuation. It reads
the signed proposal, retains its original source, then rereads the same facts
under Identity, current Consent and Collection ownership, rechecking the
installed bundle before entering trusted host code. The terminal-backed
installed-bundle fixture passed and refused a missing target and incomplete
source. The callback still requires the native review and publication guards;
it does not itself display or accept the candidate.
The management host now also connects that continuation to the genuine native
acceptance-review handle. The terminal-backed installed-bundle fixture used
that handoff, checked the complete displayed facts against the recorded digest,
and refused a context with a changed policy hash before display. Publication is
now available through a private management-host effect; no public accept command
is exposed.

That effect reacquires the original source, Identity, current Consent and the
exact signed pending target, journals the accepted event and effect intent,
claims the one-use review, and switches the combined request under both native
leases. It records a committed receipt only after the protected callbacks and
source ownership have closed; an unconfirmed effect is recorded as unknown when
possible and is never retried automatically. The terminal-backed fixture passed
the actual publication and a competing-source refusal. Further owner-loss and
post-switch cleanup interposition remain necessary before public adoption.

An isolated 2026-10-30 build with `ipse_source_switch_test_hook` exercised the
host effect through the actual terminal on both sides of the native decision.
Killing the original source holder before the decision left the proposal in
place and the intent unknown. Killing it after the decision left the proposal
removed and its acceptance link present, while the journal still reconstructed
the effect as unknown. Killing the management journal writer before the decision
also left the proposal in place and the intent unknown. A writer-loss control
after the decision verified an unknown intent and that exactly one of the
proposal or acceptance link remained. Separate native transaction controls for
source and writer loss passed on both sides. The instrumented helper SHA-256 was
`0835abbc95c9ea053994d85479f4edf33722f640b1603bbd6eef70e97d45ef08`;
it was built only under `/tmp/ipse-acceptance-hook-20261030`. These controls do
not cover every post-switch cleanup boundary.

A later instrumented run added a pause immediately after the root rename and
before directory synchronization. Killing the actual management writer at that
point left the proposal removed and its acceptance link visible, while the
intent reconstructed as unknown. This covers that specific interrupted effect,
not power-loss durability or every later cleanup boundary. The isolated helper
for this run had SHA-256
`11553fa60204490e744206e2b8a84f8ac345d0022ad0f19a50cfa3b9bd3abf2f`.

A subsequent isolated build paused immediately after the root directory sync
and before the final retained-parent identity check. Killing the management
writer there left the pending record removed and its acceptance link present;
the effect intent reconstructed as unknown. The combined terminal-backed
fixture passed the earlier boundaries and this added control. Its instrumented
helper SHA-256 was
`e781986ddddc3493b4a1c800f8d084de1e0d777fa5b1fc59c13426fdc84b113b`.
This is one cleanup boundary, not proof of all later cleanup or power-loss
behavior, and it does not authorize public acceptance.

The same isolated helper was then used to kill the original source owner at
the post-sync pause. The terminal-backed fixture again found the pending record
removed, its acceptance link present, and the effect intent unknown. This
extends the owner-loss evidence at that boundary; it does not establish current
source eligibility or authorize later disclosure.

A further control intercepted the management Writer's committed-result append
after the protected publication callbacks had returned, then killed that Writer
before the append. The pending record was removed, the acceptance link remained,
and the retained intent reconstructed as unknown. The combined terminal-backed
fixture passed using the same isolated helper. This checks the pre-append loss
boundary; it does not establish durability for an append interrupted after entry.

An isolated helper with both source-switch and journal test hooks then paused
after writing the complete committed-result record but before its file sync.
Killing the management Writer at that pause left the pending record removed and
the acceptance link present. The caller reported an unconfirmed outcome; the
complete committed result was visible in the recovered journal and passed its
structural checks. Visibility in this process-level test is not proof of
power-loss durability. The combined fixture passed with helper SHA-256
`9c8c5ebcbfae01515389afa1d4cb8917e4ee239e077e3c9d86458a59dad85438`.

A later isolated helper added a partial-write pause for the committed-result
record. After Writer loss at that pause, the complete acceptance intent remained
followed by an incomplete tail. Read-only operation inspection reported unknown
and did not change the journal; the pending record was absent and its acceptance
link remained present. The combined fixture passed with helper SHA-256
`80718e1a72e21b5cf2f9923c2c7f9824c4d525459e5b4c6f745e074403b05d8d`.
This tests process interruption, not power-loss persistence or a public accept
workflow.

A private management-host continuation now composes journal reservation,
current installed selection, retained-source review, native input, protected
publication and reservation release. The isolated terminal fixture exercised
the continuation with a synthetic candidate: acceptance removed the pending
record, retained its acceptance link and wrote the linked committed result.
A separate cancelled review retained the exact pending record, created no link,
and wrote no acceptance event or effect intent. The same combined fixture passed
the preceding loss controls with the instrumented helper above. This remains a
private continuation; it is not a public command or a later-use authorization.

The same private continuation subsequently passed acceptance and cancellation
through the ordinary pinned helper, without the interruption hooks. Acceptance
removed the pending record and produced the link; cancellation preserved the
exact pending record, created no link and wrote no acceptance effect. This
terminal fixture used helper SHA-256
`c91465337c54fcea73aa23e4135899d56c5e93936744e954fd7bf69088fc09ce`.
It does not establish the complete public command or later-use path.

A further ordinary-helper control held the original source lock after the
review card appeared and before the typed acceptance reached the continuation.
The continuation refused, retained the exact pending record, created no link,
and wrote no acceptance event or effect intent. This checks a competing owner
at that boundary; it is not a general proof of all source mutations or expiry.

Another ordinary-helper terminal control revoked saved consent from epoch 8 to
epoch 9 after the review card appeared and before typed acceptance. The private
continuation refused, retained the exact pending record, created no acceptance
link, and wrote no acceptance event or effect intent. The focused fixture passed
with `IPSE_TEST_ACCEPTANCE_ORCHESTRATION=1` (one test, 45 excluded). This covers
that revocation ordering, not every expiry or concurrent publication boundary.

An ordinary-helper control also held input after the review card until the
overall management deadline elapsed. The continuation returned
`knowledge_management_cleanup_unconfirmed`, rather than a confirmed
cancellation. In this fixture the exact pending record remained, no acceptance
link existed, and the readable management journal contained no acceptance event
or effect intent. The focused fixture passed with
`IPSE_TEST_ACCEPTANCE_ORCHESTRATION=1` (one test, 45 excluded). This covers an
unanswered review at the overall deadline; it does not establish the outcome of
input or publication racing a signed retention deadline.

On 2026-10-30, a focused rerun of the six generated Session controls at
`test/ipse/extension/managed_collection_call_session_test.exs:1298` passed the
three managed cases and failed the three unmanaged cases. The unmanaged cases
expected a staged native switch, but the current timed-publication gate refused
before staging. The run used synthetic fixtures and an ordinary built helper;
it does not qualify unmanaged timed publication. The separate full-suite run
was still in progress and had observed source changes during its execution.

For accepted-note delivery from an active Session, the inert accepted collector
is insufficient even after increasing its entry count. Its wire format binds
one operation ID to every exporter, while the active Session share uses a
separate transport ID; the terminal lease protocol already carries an operation
per manifest entry. A delivery implementation must coordinate the active Session
lease, Identity, Consent, Collection, original management journal and original
source, and retain the owner-control channels through actual output and cleanup.
The existing five-entry test proves none of that delivery behavior. No gate was
opened by this inspection.

A private Linux terminal probe now accepts the six-entry shape with a separate
operation ID per entry and the exact slot order for active Session, Identity,
Consent, Collection, management journal and original source. Its output is
restricted to the fixed synthetic marker; it is not wired to accepted-note
delivery. A fresh helper compiled with warnings denied, and a PTY control
refused both a five-entry request and an arbitrary payload without displaying
that payload. A subsequent isolated runtime pinned all exporters and the
terminal probe to the same newly built helper. Six synthetic transaction leases
and two owner-control channels transferred and settled in order; the first
lease used a different operation ID from the other five. The fixed marker was
displayed and the probe closed successfully. The leases in this control were
synthetic transaction owners, not an actual Session, management journal or
source. Four further PTY runs killed a synthetic owner corresponding to the
Session, the three-lock stack, the management journal or the source after all
six transfers and before activation. Each probe exited unsuccessfully without
displaying the marker. These are process-loss controls on synthetic exporters;
actual Session, journal and source integration and real accepted-note delivery
remain unqualified.

A later terminal control replaced the first synthetic lock with a real fresh
Session's journal share barrier and retained native Session lock. Its distinct
transport ID was transferred, settled and thawed before confirmed Session close;
the fixed marker displayed and the six-lease probe closed. The three-lock stack,
management and source slots remained synthetic transaction owners, and both
owner-control channels belonged to the fixture rather than the Session/Host
bridge. This narrows the transfer gap but does not authorize production output.

The combined control then replaced the management slot with a newly owned real
management journal. Its Writer barrier and native lock exported and settled a
second distinct transport ID alongside the real Session, and both barriers
thawed before their owners closed. This is an active synthetic management
journal, not the inactive original committed acceptance journal; the source
slot and owner-control channels remain synthetic. The same focused PTY test
passed. Production accepted-note output remains closed.

A further combined PTY run replaced the source slot with a verified inactive
original Session journal and `StoredSources.with_shareable_verified` lease.
The six entries transferred and settled while the source callback retained that
lock, and both real journal barriers closed. The source proof and the active
management journal were independently constructed fixtures; this did not bind
the source to a committed acceptance or exercise real Session/Host control
channels. The other three locks were synthetic transaction owners. The focused
test passed; production disclosure remains unavailable.

The terminal-backed acceptance fixture next supplied the link and event from a
synthetic committed acceptance to an isolated six-lease probe. The probe
reopened the original committed management journal, checked the resolved event,
and retained the exact original source proof named by that event. Both leases
transferred and settled alongside a real fresh Session lock. This focused run
passed with `IPSE_TEST_BOUND_ACCEPTANCE_HELPER` and helper SHA-256
`85d68411143d2be5cd33410dce9e3e7ac02de4535afe1bdaa598c5fe57da80ca`
(one test, 45 excluded). The Identity, Consent and Collection slots were still
synthetic locks, and the owner controls were fixture-owned. No accepted text was
displayed and current-use delivery remains closed.

The next focused run replaced the three synthetic policy/storage locks with the
actual Identity domain authorization, current Consent policy and signed
Collection observation for that same accepted event. It checked the link and
accepted-use policy while retaining those owners, then transferred and settled
all six leases with the real Session, committed journal and recorded source.
The fixed-marker PTY control passed with the same helper (one test, 45
excluded). Its Session and Host owner-control channels are still fixture-owned,
the source and journal callbacks run in fixture tasks, and it never sends
accepted content. It is not a production disclosure or owner-loss qualification.

Four subsequent runs used the same bound acceptance and actual protected
owners, then killed the native owner for the Session, the Identity/Consent/
Collection stack, the committed management journal or the source after lease
transfer and before activation. Each terminal probe exited without displaying
the marker; the surrounding protected read returned an error or unknown rather
than a confirmed close. The focused fixture passed all four controls and the
positive case. These are process-loss tests before activation with fixture-owned
control channels; they do not cover loss during output or qualify disclosure.

The same bound fixture also closed each fixture-owned control channel after
transfer and before activation. Both terminal probes exited without displaying
the marker, and the surrounding protected read did not confirm cleanup. The
focused positive and six loss cases passed together. These channels model the
native protocol but are not the actual Session/Host control handoff.

A separate six-lease bridge control ran through an actual Session and Host
job's controlled share and owner-control handoff. A test-only variant of the
existing leased-terminal bridge transferred the real Session lease and five
synthetic transaction leases, displayed only the fixed marker, settled every
lease, and confirmed Session/Host cleanup before thaw. The isolated runtime
compiled 176 modules with warnings denied and used the same helper SHA-256
`85d68411143d2be5cd33410dce9e3e7ac02de4535afe1bdaa598c5fe57da80ca`;
the selected PTY test passed (one test, 19 excluded). This does not yet combine
the actual owner controls with the committed acceptance and source leases, and
the test-only bridge cannot deliver accepted content.
The existing four-lease Session/Host PTY control also passed separately with
that helper (one test, 19 excluded).

An actual Session/Host control confirmed that a separately tracked
`Resources.file_effect` process cannot call `begin_controlled_session_share`:
the Session checks the requesting process against its Host task and refused
before opening a share barrier. The focused isolated-runtime test passed (one
test, 20 excluded). Composing the protected callback with actual controls must
therefore retain the Host as coordinator; passing the call to the file-effect
worker is not a valid integration.

A test-only coordinator now keeps the real Host task as the Session-control
caller while a tracked file-effect worker owns the three transaction leases
and runs the six-lease terminal probe. It forwards the control operations to
the Host and transfers the terminal Port to the Host before Session close;
without that transfer the existing Session ownership check did not confirm
cleanup. The fixed-marker PTY test passed in the isolated pinned runtime (one
test, 21 excluded). This coordinator is fixture code, not a production API: the
extra owners and three transaction locks are synthetic, and no accepted content
or bound acceptance was delivered. Loss and forged-coordinator tests remain.

The same test-only coordinator was then exercised with the committed acceptance
fixture: its protected worker retained the actual Identity, current Consent,
signed Collection observation, original committed management journal and
recorded source, while the Host coordinated its real Session share and terminal
close. The nested PTY test displayed only the fixed marker and passed; the outer
acceptance fixture passed one test with 45 excluded. The Host Session was a
separate synthetic fixture with its own project context, not a Session admitted
to use this accepted decision. No accepted text or model request was sent, and
no production coordinator or current-use delivery gate was opened. The first
nested launcher attempts stopped at a Hex installation prompt because the test
home was isolated; the successful run invoked the already built Elixir runtime
directly and did not install or fetch dependencies.

The bound coordinator fixture now narrows the terminal deadline to the
accepted-use deadline returned by the protected policy check. A separate
synthetic control shortened that deadline further, waited at the point just
before terminal activation until it elapsed, and observed no marker. The test
required an unconfirmed/error cleanup result or Host termination, rather than a
confirmed close, and the focused positive plus expiry run passed. This checks
the fixture's deadline wiring, not actual accepted-content output, a same-project
Session admission, or every scheduling boundary around display.

A subsequent same-project control renewed the fixture's knowledge consent
through genuine native review and revalidated the accepted record under that
current policy. The Host fixture then reviewed consent again with its actual
synthetic extension catalog, started a fresh Session in the same project and
verified its active policy epoch and digest. Its Host coordinated the protected
worker while the real Session, Identity, Consent, Collection, original
management journal and original source leases were retained. The fixed-marker
terminal test and outer fixture passed (one outer test, 45 excluded). The Host
action remains a synthetic fixture rather than an admitted accepted-reference
consumer; no accepted text was disclosed, and production delivery stays closed.

`ManagedUse.with_accepted_reference/3` now provides a private retained callback
after revalidating a version-6 reference against the current policy, signed
record, committed journal and original source. It supplies only the historical
hash/dependency inspection and owner-bound journal/source lease tokens, never
accepted text. The callback must still establish a separate native delivery
fence; it grants no disclosure authority. The historical inspection path keeps
its original native transaction imports. The focused fixture transferred the
retained leases to the inert five-owner collector, rejected a changed event,
an incomplete source and revoked consent, and passed on rerun.

One preceding run failed before reaching this new callback: a management Writer
reported an unconfirmed cleanup after its control helper exited. A fresh run
passed the complete focused fixture. The cause of that intermittent earlier
failure was not established, and the passing rerun does not erase it.

The same-project Host fixture now derives a version-6 dependency for its own
active Session using `ManagedUse.inspect_accepted`, then enters
`with_accepted_reference/3` in the protected worker. That callback revalidates
the reference and transfers its original journal and source tokens, together
with the three protected transaction leases and real Session share, through
the test-only Host coordinator. The terminal displayed only its fixed marker
and the focused fixture passed with the isolated helper. This is not an
admission of that dependency into the Session's normal managed output path;
accepted content and production disclosure remain unavailable.

One parallel synthetic regression attempt collided with another PTY test and
failed to open the terminal. The regression passed when rerun separately after
the protected-owner fixture finished; this is not counted as a protocol failure.

The separate current-worktree managed Collection Session file completed with
67 of 117 tests passing. It ran concurrently with the full suite, and this
worktree changed while the latter was running. Several failures show existing
publication and managed-output refusals; the remaining failures have not all
been classified. This result is not a fixed-source release baseline.

The full mixed-source run subsequently finished in 4,548.7 seconds with 3,273
of 3,442 tests passing, 169 failing, 21 invalid, 53 skipped and 57 excluded.
Some failures involve the missing `IPSE_LITERAL_AB_ROOT` fixture environment;
others require independent diagnosis. Changes during the run and the concurrent
Session test prevent treating it as a fixed-source baseline.

The 21 invalid tests all belonged to `ProjectIdentityTest`: its generated Rust
probe did not declare two Linux modules newly referenced by the transaction
implementation. The fixture now declares those modules with Linux target guards.
The full `ProjectIdentityTest` file then passed all 21 tests on Linux.
The literal A/B test instead depends on a separately prepared historical runtime
and seed, as described in [its evidence record](literal-v4-source-union.md);
the missing environment variable is not a substitute for that preparation.
On 2026-10-30 the retained historical runtime and recorded launcher regenerated
the synthetic seed at `/tmp/ipse-literal-v4-ab-46915`. With that path explicitly
supplied, the current-worktree consumer test passed (one passed, 116 excluded;
seed 12904): it observed the actual version-4 read and current B quote, then
refused the inherited source-A prerequisite before a candidate intent or the
blanket publication gate. This local preparation depends on the retained old
runtime and is not a reproducible fresh-checkout full-suite setup. The old
runtime is used only to create historical input, not to bypass the current gate.

The current-worktree `InvocationTest` reproduced a separate suite failure: idle
resume correctly appended the release owner marker, while older assertions
required unchanged journal bytes. The affected assertions now require the exact
existing byte prefix and, for release-receipt journals, exactly one valid new
owner marker; callback, egress and state no-replay assertions remain. Failed
startup and rejected-input byte-equality checks were retained. The complete
file passed 61 tests (seed 475996). Other files with older resume assumptions
have not yet been reconciled, and this is not an aggregate-suite result.

The exact-prefix/one-owner-marker assertion is now shared by additional usage,
Gemini and extension resume tests. The affected eight-file run passed 95 of 96
tests (seed 886280; log `/tmp/ipse-resume-multiple-current.log`). The remaining
failure tries to append a fabricated accepted-draft event to a native-owned
journal and receives `journal_lock_owner_required`; it needs a genuine accepted
draft fixture, not a bypass of the lock guard. A focused invocation test also
passed after moving the assertion into the shared helper. Unrelated failed-start
and rejected-input byte-equality checks remain unchanged.

The extension Session lineage test now runs its acceptance in an isolated PTY:
the native input channel witnesses the displayed challenge and the Session
records and consumes the accepted draft through its ordinary API. The test then
checks the resulting extension invocation and action lineage. This replaces the
direct fabricated append and tests immediate acceptance/consumption, rather than
the former synthetic accepted-then-resumed state. The full extension Session and
draft-acceptance files passed together (26 tests). The inference-dispatch lineage
test was then converted to the same witnessed acceptance before exercising real
Session calls to synthetic model, embedding and decision services. A shared test
helper manages the PTY child and input reader. The complete inference-dispatch,
extension Session and draft-acceptance files passed together (30 tests). Other
independently fabricated draft fixtures still need reconciliation.

The MCP resource-lineage test now uses the shared witnessed-acceptance helper
instead of appending a fabricated event. It checks the actual resource read,
source lineage and saved reconstruction after immediate accepted-draft
consumption. The complete MCP catalog, inference-dispatch and extension Session
files passed together (31 tests, seed 904759); this does not qualify a live MCP
service or the full P31 delivery journey.

The producer-configuration test no longer requires an externally supplied
`IPSE_PRODUCER_CANONICAL_ARTIFACT`: in an isolated VM it builds the actual
collection-dense corpus artifact when the variable is absent, then exercises the
same configuration assertions. An explicitly supplied artifact is still used.
The configuration and Knowledge independence files passed together (22 tests,
seed 307163), with the variable unset. This verifies the fixture and module
isolation, not the unqualified shared producer's complete behavior.

Knowledge recall and search now bound index-page traversal independently of the
32-record limit. They refuse empty pages with a continuation, repeated or cycling
continuations, duplicate indexed keys and excess page/row counts with
`invalid_index_progress`. The automatic recall job has already cleared its old
turn contribution before indexing and does not publish a replacement after this
refusal. Source and freshly built Knowledge artifact tests cover those cases and
the normal recall/search controls (10 internal cases in each run). Build,
warnings-as-errors compile and the credential-free demo also passed. This is a
bounded continuation repair, not full managed recall or P31E qualification.
The same check now requires a stable visible count across pages and refuses an
early terminal page when traversal began at the start. An empty terminal page
after an explicit later cursor remains valid but reports partial coverage. The
source and newly built artifact tests passed those controls as well.
An additional positive fixture split five notes across three short index pages;
both recall and search reached the final page and reported complete coverage.
It passed against source and the independently built worker artifact. The pages
were supplied by the fixture, not a live Collection Session.
The next control seeds 32 synthetic notes in an actual native Collection, passes
its authenticated host-generated metadata cursors and reads into the Knowledge
search continuation, and checks complete coverage and all keys across multiple
pages. It passed in both source and independently built artifact modes (12
internal cases each). The caller is a synthetic driver, not an admitted Session
or a protected-use qualification. An initial artifact run refused native-helper
identity because an `ipse-` artifact directory shadowed the application path;
copying it to a neutral temporary directory fixed the fixture without changing
the helper check. The test now performs that copy for supplied artifacts.
The same native-Collection driver now inserts another synthetic note after its
first page. The host refuses the root-bound next cursor, and search returns an
interrupted result without a records field. Both source and built-artifact runs
passed. This control changes the Collection between pages; it does not exercise
Session authorization or loss during an actual delivery.

Automatic recall previously retained earlier metadata keys when a later index
request failed, then published those keys with unavailable coverage. It now
clears the abandoned index and reports a null candidate count before producing
unavailable framing. A simulated later-page failure verifies no record reads,
no stale key in the published items and an explicit unknown count; source and a
freshly built artifact passed 13 internal controls each. The separate actual
Collection root-change control now also drives the automatic job: after an actual
second root change invalidates its cursor, the synthetic context-publication
adapter observes unavailable coverage, an unknown count and no retained index
keys. Source and built-artifact runs passed. Context publication and Session
authorization remain simulated in this control.

Recall and search now compare each record's indexed value hash and byte count
as well as its key and revision. Synthetic same-revision inconsistent-value and
byte-count cases are withheld and counted unavailable; normal Collection writes
derive revisions from increasing generation, so the fixture does not claim that
an ordinary delete and recreate reuses a revision. Source and freshly built
artifact controls also exercise actual Collection reads. This is an additional
identity consistency check, not independent proof of source eligibility.

The current Knowledge Session file initially produced one pass and two terminal
failures. Isolating the native capture showed that the attack fixture's denied
write now ends the Session turn with the managed-history error; its assertion
still expected successful completion before checking the denial. The test now
requires the error for that case and retains its no-record/no-consent-operation
checks. The question fixture's terminal driver also waited only for successful
completion and timed out after a failed turn had returned to the prompt; it now
recognizes either completed outcome, with a focused driver unit test. The full
Knowledge Session file subsequently passed all three tests (seed 935878), and
the Rust driver's eight unit tests passed. These synthetic fixtures do not close
the full protected recall or installed-user acceptance gates.

An isolated current-worktree snapshot was prepared at
`/tmp/ipse-fixed-baseline-20261030`, excluding the workspace's private environment
and previous `_build`/distribution trees. Its build completed and a full suite
was started with the regenerated historical literal fixture. Source hashes were
recorded in `/tmp/ipse-fixed-baseline-sources-20261030.sha256`; build and suite
logs are `/tmp/ipse-fixed-baseline-build-20261030.log` and
`/tmp/ipse-fixed-baseline-suite-20261030.log`. The run is pending; its source
hashes and terminal outcome must be checked before describing it as a fixed-source
baseline. The historical fixture remains an external local prerequisite.

While that snapshot was running, the active worktree's pinned native document
read test was made independent of test order: it now loads the Knowledge
Collection adapter in a child VM and checks that the host's module load state is
unchanged. The native pinned-read and store-isolation files passed together
(two outer tests, seed 723587). This repair is not in the running snapshot and
does not by itself qualify full document generation or production migration.

A later focused run again reported unconfirmed management cleanup before
reaching the retained-reference callback. Its cause remains unknown. An
attempt to reuse a saved synthetic fixture after recompiling also refused
extension activation: its saved consent pinned a different host identity.
That refusal occurred before callback execution and is not evidence of callback
behavior; the callback outcome checks need a freshly reviewed matching policy.
With a freshly reviewed same-project policy and matching runtime, the protected
worker checked that a returned error and a raised exception after callback entry
both yield `accepted_reference_unconfirmed`, while a changed acceptance is
refused before callback entry. It then completed the fixed-marker six-owner
fixture. The focused outer test passed (one passed, 45 excluded); this still
does not establish production delivery or resolve the earlier cleanup failure.

The same fresh-policy worker also passed a genuine version-6 dependency to the
ordinary `ManagedUse.with_dependencies/3` path and verified both refusal and
that its delivery callback was never entered. The focused outer fixture passed
again (one passed, 45 excluded). Normal managed output still uses that ordinary
path and publishes from the Session after a separate deadline check; integrating
accepted references requires an actual delivery fence retaining all owners, not
just making version 6 pass the existing dependency filter.

The same-project retained-reference fixture now also shortens its terminal
deadline to at most 1.5 seconds and waits until after that deadline immediately
before activation. The positive case displayed the fixed marker; the shortened
case did not and returned unconfirmed cleanup or terminated its Host. Both ran
under freshly reviewed same-project policy with actual Session and Host control,
and the outer test passed (one passed, 45 excluded). The shortened deadline is
fixture-imposed, not an observed expiry of saved consent; this does not qualify
accepted-content delivery, mid-write expiry or production cleanup.

The same-project fixture additionally killed the original source's native lease
owner after transfer and immediately before terminal activation. It observed the
kill marker, withheld the fixed display marker and reported unconfirmed cleanup
or Host termination. The positive, shortened-deadline and source-owner-loss
cases passed together (one outer test, 45 excluded). This uses a synthetic
acceptance and a test-only Host coordinator; it does not test mid-write loss or
production accepted-text disclosure. One earlier attempt failed before the kill
marker with terminal lease unavailable. Its cause is not established. The
fixture callback also now reports a terminal error as an error, rather than
wrapping it in a successful tuple, so retained-use cleanup stays unconfirmed.

## MCP cleanup regression observed during the fixed snapshot suite

The isolated full-suite snapshot reported three HTTP MCP interruption cleanup
failures: the old-session DELETE was not observed after owner death, a timed-out
call returned unconfirmed Session cleanup, and an owner-loss case did not
observe DELETE. A focused run of the held-POST/owner-death case against the
active worktree reproduced the missing DELETE (seed 581501). This is not a
passing no-replay control; do not infer that the old server session was closed.

An instrumented focused owner-death run (seed 761473) showed that the relevant
MCP transport was already dead when the resource scope attempted to close it;
its close and termination callbacks had not run. The earlier DELETE in that
run belonged to a different, completed transport. The earlier hypothesis of a
DELETE guardian registering into a blocked resource scope is unsupported: the
ordinary HTTP request task does not inherit that process-local scope.

The managed transport is registered both as an MCP resource and as a tracked
task. A second instrumented owner-death run (seed 535512) identified the same
transport PID in the Session lock guard's quiescence list as both `:peer` and
`:worker`; the guard kills every worker while requesting graceful scope cleanup.
Combined with the previous observation of the dead transport, this identifies
the owner-loss teardown race. Task tracking also authorizes the transport to
register its managed request tasks. The resource scope now records a tracked
task already registered as an MCP resource as a lock-guard peer rather than a
kill-first worker; its task registration remains intact and the scope closes the
resource before stopping tracked tasks. The previously failing owner-death test
passed (seed 25560), including the observed DELETE and inert-resume traffic
check. Temporary tracing was removed before that run.

A broader current-worktree run of MCP HTTP, MCP Session and resource tests
passed 50 of 54 tests (seed 720602). The held owner-death and other owner-loss
cases passed; disconnect, timeout and cancellation still returned unconfirmed
cleanup, and the independent bulk-discovery uncertainty case timed out. Their
causes require separate diagnosis. This is not a full ownership or milestone
qualification, and the isolated full-suite snapshot predates the repair.

The independent bulk-discovery timeout occurred because the SDK awaited a
transport-close message while an abruptly killed, unlinked HTTP transport could
not send one. A bounded monitor now forwards an abnormal transport death to the
SDK client; cleanup remains unconfirmed and discovery does not advance to the
next server. The previously failing loopback test passed (seed 645406), and a
broader run of HTTP discovery, managed HTTP cleanup/unknown and resource tests
passed 30 tests (seed 497592). The monitor exits on transport, client or owner
death and carries no request or credential data.

The three remaining Session expectations must be assessed against the earlier
[managed MCP cleanup decision](managed-mcp-integration.md): a later successful
DELETE cannot establish that an interrupted managed socket closed. They must
not be made to pass by converting unconfirmed cleanup to success.

The affected interruption fixtures now require the unconfirmed result and
Session termination for disconnect, timeout and cancellation; they continue to
check the closed socket, DELETE, unknown or absent result, durable intent and
idle no-replay behavior. All four focused interruption cases passed (seed
224069). The combined current-worktree MCP Session, HTTP, managed cleanup,
managed unknown and resource files passed 59 tests (seed 782690). This does not
establish the full P31 managed-source delivery boundary or a full-suite pass.

The fixed snapshot also exposed an obsolete byte-equality check in the
standalone model-artifact proof. The proof now requires the entire prior journal
as an exact prefix followed by precisely one valid owner-start receipt for the
current release layout; legacy layouts still require no appended bytes. Its
budget-ledger equality and idle/no-replay checks remain. The independently built
artifact proof passed its existing text and structured-output variants (one
outer test, seed 811096). The running snapshot predates this correction.

The snapshot's evaluation Session cases refused because a document-source test
loaded `IpseKnowledge.Evidence` into the host VM during test-file loading. That
test now runs its 11 existing controls in an isolated child VM and checks the
parent's prior module load state is unchanged. The document-source wrapper and
evaluation Session file passed together (12 outer tests, seed 107198); an
initial wrapper assertion expected nine source declarations rather than the 11
expanded cases and failed before that count was corrected. Other tests also
explicitly load domain modules at runtime, so this focused result does not prove
whole-suite isolation for every ordering.

The Collection adapter Session tests also load Evidence and Projection locally
for fixture construction. Their per-test cleanup now deletes and soft-purges
only modules that were absent before that test, and asserts successful cleanup;
previously loaded modules are not removed. The vector-geometry control and the
evaluation Session file passed together (12 tests, seed 967753), and the actual
Session vector-staging control passed separately (seed 698665). This addresses
those two explicit loaders, not every possible source of host contamination or
full-suite test ordering.

Recall and search now retain the generation reported by their initial index,
require later index pages to match it, and withhold accumulated notes and keys
with unavailable coverage if a current read reports another generation. The
new native control commits a second note after a complete single-page index and
before the first read, and verifies search returns no records and an unknown
count. A separate synthetic control changes generation after one successful read
and verifies earlier recall and search values are also withheld. The source and
freshly built Knowledge artifact each passed all 16 inner controls (outer seeds
800271 and 856840). This catches an observed intervening change; the pass does
not retain a Collection lock through publication and does not establish freshness
after the final read. The fixed full-suite snapshot predates this change.

The pass now performs one bounded index check after its reads, including for an
empty first page. A changed generation or count, or a failed check, discards the
accumulated result and reports unavailable coverage. A native Collection test
commits a new note after the last read and before this check; a separate
synthetic test covers empty and nonempty inputs plus check failure. Source and
fresh artifact runs passed 17 inner controls (outer seeds 545896 and 722766).
The extra check raises the measured 32-note synthetic action count from 36 to
37; it remains within the selected mixed-action limit. It is not a lock held
through context publication, and the actual Session integration has not been
rerun for this change.

An actual headless Session control now exercises the freshly built Knowledge
worker with a read-only recall-job policy. Its journal records both successful
index actions, with limits 32 and 1 and matching generations, and a completed
recall event. The selected demo route then refuses managed-history reuse before
any inference request; this test does not demonstrate delivered recall or a
supported provider journey. The original capture fixture had mapped every
export, including the recall job, as a publication operation; that caused the
optional recall job to be recorded `not_started`. The separate control maps the
job read-only while the original fixture retains its prior capture scenario.

The separate real PTY/native-note fixture was then rerun against the current
artifact and registered local Ollama adapter. The first attempt delivered all
three reviewed note texts but failed its old four-read assertion because the
final index check adds a fifth managed read. After updating the fixture to check
both index limits and matching generations, the full journey passed (one outer
test, seed 651009): it covers reviewed note delivery, constrained context,
forget/source withdrawal, cancellation and inert resume using the synthetic
local HTTP provider. This is not a live model or installed-package quality
evaluation, and it does not prove exclusion of a change after the final check.

A further actual Session control paused its event-job completion immediately
after the recall worker's final index check, then committed an unrelated
synthetic Collection record before allowing Session to continue. The registered
local provider received a request with all three earlier note texts withheld;
the test also verified the two successful index actions and five managed-read
receipts. The final focused run passed (seed 388089); the preflight
observation and ordinary synthetic HTTP fixture are not a proof of every race or
of accepted-decision delivery. Two earlier attempts used a PTY scenario name
that stopped after the first reviewed note and timed out before the pause; the
corrected `save_race` scenario reached the intended boundary.
In a subsequent combined two-journey run (seed 846049), the race passed again,
but the original journey failed before enabling Knowledge because its operator
channel was unavailable. The older isolated full suite was running concurrently;
the cause of that terminal failure is not established. The separate earlier
passing original journey remains evidence, not a substitute for this failed run.
Source inspection shows that native operator-channel acquisition uses one
nonblocking `/tmp/ipse-operator-<uid>/input.lock` per effective user, regardless
of the test workspace or PTY. Concurrent same-user PTY fixtures can therefore
contend. The failed log does not identify the lock holder, so it cannot prove
that contention caused this particular failure. The concurrent full-suite
snapshot may likewise have been affected; its PTY failures require independent
classification after the run finishes.

The current managed-reference, lineage and root-transition replay files passed
56 tests together (seed 145181). These are focused host/replay controls; the
post-check root-change Session control above remains the evidence for the
particular provider-withholding interleaving, not a substitute for complete
protected-delivery qualification.

The current one-use Review fixture passed 22 controls (seed 108789), including
the acceptance request binding and deadline cases. It uses substituted input
and does not qualify the actual terminal, retained owners or public acceptance.

The snapshot's child model-job test also required byte-identical idle-resume
journals. Its assertion now uses the shared exact-prefix and valid owner-marker
check while retaining the child-accounting and no-new-HTTP assertions. The
focused file passed (one test, seed 48759); the snapshot predates the correction.

The snapshot also exposed a cold evaluation-manifest test using the former
1 MiB size ceiling after the limit was increased to 4 MiB. The test now checks
that a 1 MiB-padded manifest is accepted, a manifest beyond 4 MiB is refused,
and duplicate decoded keys and excessive nesting still refuse. The focused test
passed (seed 840055). This verifies the boundary fixture, not an evaluator run
or the snapshot's remaining failures.

The native Knowledge permission-construction test also used the old six-effect
count. It now checks all six actual artifact descriptors and their ten mappings:
each has exactly one read mapping with both reviewed recipes, and only capture
exports have the two managed publication mappings. The focused test passed
(seed 32851) without creating consent. This checks proposed policy shape; it
does not grant permission or qualify acceptance and delivery.

On 2026-10-30, current document-acquisition fixtures were updated for the
native journal owner and the current bounded Collection continuation. Idle
resume now checks the unchanged byte prefix and valid new owner marker before
closing; interrupted-effect controls separately compare retained non-journal
files. The original exact-journal assertion failed because confirmed close can
append a release intent. The state-backed acquisition and two owner-loss controls
passed (seeds 504812 and 504813). Two public Collection controls initially
failed because the first continuation no longer necessarily has an active stage.
They now follow at most 40 actual continuations to an active stage before testing
forgery and interruption. Both passed (seed 504814), including citation, selected
source, changed-file refusal and no-replay checks. These focused synthetic DOCX
controls do not establish full document capacity or installed-user qualification.

The text-stream Session fixture now checks the unchanged journal prefix and
new owner marker on idle resume while still checking that no subscription is
restored. All 12 streaming integration tests passed (seed 504816). A separate
current-source run combining streaming and Collection Session controls (seed
504815) finished with 18 of 26 passing; its eight Collection failures reproduce
cases where the protected-publication deadline gate refuses before the
older fixture reaches its intended publication or revocation assertion. These
are unresolved coverage gaps, not successful tests of those scenarios. The gate
was not bypassed for the rerun.

New enhancement drafts now use a version-2 instruction that asks the model to
check available relevant context before asking unanswered material questions,
state low-impact assumptions and identify required missing information when
clarification is unavailable. Replay retains the exact version-1 instruction
for existing histories and rejects a mismatched version and instruction digest.
An actual Session fixture checks the instruction sent to its synthetic model;
43 draft, native-policy and planning-MCP controls passed (seed 504818). This
is prompt guidance, not evidence that a model follows it, that knowledge or
documents were retrieved before questions, or that P31I is qualified.

Native model question dispatch now refuses exact duplicate question objects in
one new batch even when their IDs differ, returning an invalid-arguments result
without opening an operator wait. Historical validation is unchanged. Question,
Session and draft controls passed 37 tests (seed 504819), including actual
dispatch and saved-context reconstruction. Reworded or cross-round repetitions
and retrieval-before-question quality remain open.

A later 2026-10-30 follow-up checks the current visible user turn for a matching
validated `ask_operator` call and recorded answer before opening another native
question. An actual synthetic Session answered one question, attempted the same
question with a different ID, received an invalid-arguments result and restored
its journal. This exact comparison does not recognize rewordings or search past
the visible turn; it does not establish retrieve-first behavior or model quality.
The child-usage resume fixture also now checks the native owner marker after the
unchanged journal prefix; all seven controls passed (seed 504820).
The current-turn check pairs an answer only with the immediately preceding
assistant tool-call group. A reused ID on an unrelated earlier call cannot
qualify a later unanswered question. The question/draft selection passed 45
tests (seed 504823). A further actual Session control kills the owner while
the question is pending, resumes it, answers, and verifies the repeated question
is rejected; all 17 question integration tests passed (seed 504824). No native
terminal witness or cross-turn semantic matching is claimed by that fixture.

The private Session-controlled terminal bridge now retains the recipient PID
sent to its owner-control helper and requires the Host-owned terminal Port to
have that same PID at close preparation. A mismatch poisons the share. Selected
native transfer and simulated settled-boundary controls passed eight tests
(seeds 504826 and 504827); the actual transfer control confirms the retained PID, while the
close-boundary cases deliberately simulate settlement. Matching a PID does not
authenticate the recipient's delivery purpose or prove completion. The existing
terminal close still trusts the Host's observation, and protected-content output
remains gated pending independently authenticated completion and loss controls.
An additional native test (seed 504828, six tests passed) transferred the
Session owner control to an actual observer, then simulated settlement and
attempted close with a different Host-owned Port. The Session poisoned the
share and the observer exited. It does not prove a real terminal settlement or
the positive delivery path.
After the older full suite exited, the actual four-lease synthetic tty bridge
passed with the recipient-PID check in place (seed 504841: one passed, three
skipped). It writes only its fixed synthetic marker and still uses the existing
Host-observed completion; it does not consume the new peer-notice experiment.
An experimental Linux owner-control v2 sender and inert observer now exercise
one authenticated operation-bound peer notice. V1 remains unchanged and no
Session consumes the notice. The sender rejects a wrong operation or repeat;
the peer and sender must also be the same executable identity. The selected
native notice and existing transfer controls passed 12 tests (seed 504840),
including an independently modified same-executable adversarial receiver.
Initial test runs 504835, 504837 and 504839 failed respectively on the actual
same-executable restriction or stale expected error framing; the fixtures were
corrected and those failures are retained here. This is a peer message, not a
proof of helper mode, displayed bytes, settlement, owner liveness at a later
effect, human consent, or an independently accepted delivery protocol.
The subsequent fixed-marker `v9-synthetic-notice-display` mode sends the notice
after the native reader and per-lease close protocols finish. A private PTY
fixture checked exact synthetic bytes, all four retained leases, the bound
Session-control notice and final cleanup; a forged activation refused without
writing or emitting a notice. The first attempt failed because the fixture
treated the newly named success mode as a loss case; the fixture was corrected.
These are native-only controls. No actual Session consumes the notice, and no
helper-purpose authentication, protected content or human acceptance is proven.
The next synthetic integration starts the fixed v9 helper from the actual
Session, transfers only that Port to the current Host, binds owner-control
transfer to its PID, and requires the native `N` before close preparation. After
the Host's release command the recipient sends a bound `F` and waits for the
sender's acknowledgment; Session requires `F`, clean owner exit, closed Host
control and an exited issued terminal before Writer thaw. Direct finish from
settled refuses. Initial integrated runs 504847–504851 displayed the fixed
marker but failed because the sender treated normal peer close as an error;
the event trace identified that mismatch and the final exchange was added.
The actual synthetic Session/Host PTY path then passed (seed 504852), and
eight PTY controls passed (seed 504854), including simulated premature close,
missing final notice and live-terminal thaw refusal. Three other tests were
skipped. These results do not cover protected accepted text, real approval
arguments, every owner-loss interleaving, or human observation and do not open
the production output gate.
With the six-lease fixture explicitly enabled, ten synthetic PTY controls passed
(seed 504856), including the older six-lease and coordinated-worker bridges;
one separately gated case was skipped. The native-only fixture also checked both
notice frames and the sender's final exit after the release exchange.

Additional native PTY controls killed the Session owner after `N` and delayed
release beyond the wall expiry; both retained an unconfirmed outcome. A
test-only stop immediately after the native final deadline check reproduced an
`F` emitted after that expiry. This is a real limitation of the native notice,
not evidence of protected publication. The synthetic Session now supplies its
own wall deadline to the trusted Host's fixed-marker helper and checks both wall
and monotonic deadlines at receipt, close and thaw; an injected late-`F` Session
control and the existing bridges passed 11 PTY tests (seed 504857, one skipped).
The peer frame does not independently bind the helper's expiry to the Session's
value, and the controlled native stop was not run through the actual Session.
Those gaps, physical scheduling races and protected content remain unqualified.
The native `N` message was subsequently extended with the terminal's exact
declared wall expiry. Session requires that value to match its own selected
deadline before accepting the notice; an injected mismatch refuses. Six native
notice controls (seed 504858), twelve synthetic Session/terminal controls
(seed 504859; one skipped), and four native PTY notice/forgery/loss/expiry
controls passed. These tests do not repeat the stopped-helper race in the actual
Session, authenticate protected content or prove physical completion by expiry.
An actual synthetic Session control then held its native `F` message before
Session processing until the Session deadline had elapsed. The Session poisoned
the share and refused confirmed close (seed 504860). This tests delayed Session
processing of a real native frame; it is not the earlier stopped-helper-before-
send interleaving and does not prove physical timing or protected delivery.
The stopped-helper interleaving was then run through an actual synthetic Session
with an isolated, explicitly test-hook-compiled native helper. The helper stopped
after its final wall check; the Session deadline elapsed, the Host died, and the
share was poisoned before the helper resumed. The strengthened rerun checked
the helper exited, no Host success was reported, and all three original locks
could be reacquired (seed 116002; one passed, 36 excluded). The isolated Session
and synthetic terminal BEAM hashes matched
the current test runtime; the isolated Runner was recompiled against the hook
helper. This is fixed-marker, test-hook evidence, not a protected-content,
production-helper, physical-deadline, or complete loss qualification.

The synthetic Session spawn now checks its selected wall deadline as well as
the monotonic deadline before starting the terminal helper. A focused actual
Session/Host control set the wall deadline in the past and observed refusal
without an issued terminal (seed 17869). This is an early refusal only; it does
not qualify protected content or remove the admitted-write timing race.
The control was then strengthened to request a real short synthetic accepted
cutoff, wait for that wall time to pass while the original monotonic deadline
remained current, and observe the same refusal without issuing a terminal (seed
784430). The cutoff is still supplied by the trusted fixture, not authenticated
against protected provenance.

The old baseline's managed MCP approval failure also reproduces on current
source: the revocation-after-server-start test failed (seed 504829) because the
managed approval display gate returned its refusal before an approval or server
start. A separately selected current refusal control passed (seed 504831),
checking no admitted effect, server call or workspace file. An intervening
line-number selection accidentally ran the managed shell owner-loss test; it
also failed before approval under the same gate. Neither refusal qualifies the
blocked revocation, owner-loss or approved-effect tests. The captured MCP
failure is `/tmp/ipse-managed-mcp-current-504829.log`; the synthetic local
server and temporary workspace do not establish a live MCP integration.
The same current refusal fixture was extended to check that no approval is
emitted, saved reconstruction succeeds, and idle resume preserves the existing
journal prefix without starting the server or writing the target. It passed
(seed 504832). The approved-effect and post-start tests remain open.

The fixed baseline suite started on 2026-10-30 has now exited 2 after 4,676.4
seconds: 3,323 of 3,465 passed, 142 failed, 53 skipped and 60 excluded. The
7,663 entries in its selected-source SHA-256 manifest all still match; that
manifest omits root-level files and is not a complete tree identity. It predates
the subsequent runtime and fixture changes, and concurrent PTY tests could have
interfered with native-channel cases. The retained log is
`/tmp/ipse-fixed-baseline-suite-20261030.log`; its failure groups include 48
managed Collection Session cases, 11 native assertion journeys and nine
evaluation Session cases. Some have separately reproduced gate or fixture
causes recorded above; do not generalize those explanations to every failure.
A fresh complete suite against a fixed current source and separate PTY ownership
remains required.

On a later dirty-worktree check, the baseline's built-in-memory and usage-read
idle-resume cases passed with their updated release-receipt assertions (seed
552457), and the MCP bulk transport-loss case passed in isolation (seed 567409).
The source-origin copy case still reproduced its earlier failure: resume now
refused the absent retained lock before it reached the expected origin check.
The fixture now separately checks that missing-lock refusal, then supplies a
private copied lock inode and checks the copied journal's origin refusal without
repairing its torn tail. All 14 source-origin tests passed (seed 144103). These
focused checks do not resolve the other baseline failures or establish a current
full-suite result.

The snapshot's Btrfs-profile refusal test failed its declared filesystem
precondition because that snapshot was on tmpfs. The same test passed on the
current checkout after verifying its filesystem is Btrfs (seed 827645). It
confirms the intended refusal on this host, not protected storage qualification;
future baseline provenance must record the source checkout filesystem.

A new serial full-suite run was started from the private Btrfs snapshot
`/var/tmp/ipse-p30p31-baseline-20261030-01`, with separate Btrfs temporary
workspaces at `/var/tmp/ipse-p30p31-test-workspaces-20261030-01` and
`--max-cases 1`. The selected tracked and nonignored untracked source files
matched the working tree by `rsync` checksum comparison immediately after
copying; dependencies were copied separately and the snapshot build passed.
The SHA-256 file `/tmp/ipse-p30p31-snapshot-manifest-20261030.sha256` has 7,827
regular-file entries but omits a symlink to a directory because `sha256sum`
cannot hash that directory. It is not a complete identity for generated build
files, dependencies or links. The suite handle is 37233 and its log is
`/tmp/ipse-p30p31-btrfs-suite-20261030.log`; it was still running at this
checkpoint. No test result is claimed until its final exit and source checks
are collected.

That run was stopped after it exposed an invalid fixture setup: ordinary
protected Collection workspaces were also on the unqualified Btrfs profile and
repeatedly refused before the intended assertions. Its log ends with SIGTERM;
the shell returned zero, but no suite completion or pass is claimed. Afterward,
all 7,827 recorded regular-file hashes still matched the snapshot. A corrected
serial run retains the Btrfs source checkout and uses a separate tmpfs workspace
at `/tmp/ipse-p30p31-test-workspaces-20261030-02`. Its live handle is 95880 and
its log is `/tmp/ipse-p30p31-mixedfs-suite-20261030.log`. The same manifest and
link limitations apply; final exit, coverage and post-run checks remain pending.
The snapshot's non-build source symlink inventory is now recorded in
`/tmp/ipse-p30p31-snapshot-symlinks-20261030.txt` (one link), and its copied
dependency files in `/tmp/ipse-p30p31-snapshot-deps-20261030.sha256` (744 regular
files). These inventories need post-run comparison; they do not capture the
test build outputs or replace a complete artifact identity.

While that corrected run was still active, its first two reported failures
were the two `ManagedRetentionNativeTest` journeys. Both encountered the
existing `native_review_publication_fence_unavailable` gate before their
intended retention publication; the consumed-review wrapper also reported an
unconfirmed outcome. They are not passing retention controls. The gate remains
in place because the earlier actual native interposition demonstrated a late
publication after Review expiry. The suite had not completed when these failures
were inspected; other failures and its final result remain to be collected.

The running suite later reported a turnover native-review failure with
`native_review_unconfirmed`; its log does not establish the underlying cause,
so it remains unclassified. A separate extension-contribution resume failure
used the old byte-equality assumption. Its fixture now checks the exact
owner-start receipt and checks diagnostics against complete JSON rather than
truncated inspection output. All seven contribution tests passed on the later
working tree; `/tmp/ipse-contributions-resume-retest.log` retains that run.
Neither result changes the source snapshot used by the ongoing suite.
The turnover fixture now records only the inner publication result kind and
atom reason before its assertion, so a later isolated PTY rerun can distinguish
a gate refusal from another unconfirmed outcome. The changed fixture has passed
format and syntax checks; the behavioral rerun remains pending while the full
suite runs.
The ongoing run additionally reported a compaction diagnostic that stopped at
`collection_deadline_fence_unavailable` while requesting retention, and a
headless setup journey that reported managed history unsafe before a later
inference request. The latter's generic message combines dependency and route
checks, so its exact refusal cause remains unclassified. Neither failure is a
passing retention or headless knowledge journey.
The running suite later reported a group of protected Collection Session
failures whose captured results show `collection_deadline_fence_unavailable`
before the expected publication or worker-entry paths. They remain failures;
the refusal does not qualify the positive, conflict, revocation or owner-loss
journeys the tests intended to exercise.
One separate `source_list` failure was an outdated expectation: the current
payload-free root-only preflight admits that source lookup. The later fixture
now verifies the empty-argument terminal notification, withheld result preview,
and a preflight, tool start and recorded result bound to the same call ID; its
companion still verifies managed write denial. Both controls passed on the later
working tree (`/tmp/ipse-managed-write-only-retest2.log`). An intermediate
strengthening run failed because it compared the internal operation name
`source.list` with the public tool name `source_list`; the corrected
call-bound source control passed (`/tmp/ipse-managed-source-bound-retest2.log`).
This is not qualification of protected publication or record-bearing source
delivery.
The headless fixture now emits only three post-failure boolean checks for
dependency availability, unregistered route and empty managed lineage before
failing promptly. Its selected demo route is unregistered by construction;
the post-failure checks are diagnostic and may not reproduce the exact state
at dispatch. The fixture passed syntax and format checks; its isolated native
rerun remains pending while the full suite is active.
The snapshot's lifecycle Session test also failed on a pre-receipt idle-resume
byte comparison. The later fixture now validates the exact owner-start marker
and still checks that no delivery occurs. Its complete file passed 17 tests;
the local log is `/tmp/ipse-lifecycle-resume-retest.log`.
Several running-suite supersession scenarios subsequently failed after the
initial native literal capture, when `/correct` received the CLI's generic
`Statement review refused` response. That response collapses multiple Session
errors, so the captured output does not identify which admission check refused.
These are failures, not successful supersession or evidence that every one has
the same cause. The final suite count and a scoped diagnosis remain pending.
Current source inspection identifies an earlier deterministic intake boundary:
the CLI recognizes `/correct` via `parse_intake/1`, while Session preparation
uses `parse_command/1`, which accepts only `/remember`. This matches the narrow
[remember-only restoration](remember-intake.md); consequently these `/correct`
requests cannot reach supersession review through that Session path. It does
not by itself establish the cause of the separate turnover fixture's
unconfirmed inner publication or qualify a safe supersession repair.
Three evaluator declaration CLI tests also failed because the copied snapshot
contains no `.git` directory and their setup invokes `git ls-files`. The
snapshot run cannot qualify those tests as product failures or successes; they
need a separately verified Git-backed source graph. The running snapshot was
not modified after the failure.
The full declaration CLI test file subsequently passed four tests on the
Git-backed dirty checkout, using its own private synthetic repositories; the
local log is `/tmp/ipse-evaluation-declaration-git-retest.log`. This is a
separate source run, not a correction to the ongoing snapshot's result.
For a future fixed-source baseline, a separate private Btrfs snapshot was
created at `/var/tmp/ipse-p30p31-git-snapshot-20261030-01`. Its selected
working-tree source matched by checksum at capture; a synthetic local-only
fixture commit `e201f50f420999347e212ddce21be8e5f22194ac` records tree
`0782d85a28813ae729b24209baf1197716715346` with 7,828 indexed paths. It is not
the project's reviewed commit or a release source. The snapshot build passed,
and its Git-dependent wide-source declaration control passed (one test, three
excluded); status remained clean afterward. Its build and test logs are
`/tmp/ipse-p30p31-git-snapshot-build-20261030.log` and
`/tmp/ipse-p30p31-git-snapshot-declaration-20261030.log`. A future run must
account for worktree changes after this capture and independently verify build
and dependency identities.
The full evaluator declaration file subsequently passed all four tests on that
same Git-backed graph, which remained clean afterward. Its log is
`/tmp/ipse-p30p31-git-snapshot-declaration-full-20261030.log`.
The snapshot also reported a history catch-up resume failure at an old
byte-equality assertion. The current fixture now validates the exact
owner-start marker while preserving its worker-death and unchanged-trace
checks. The focused cancellation and owner-death test passed on the later
working tree; its log is `/tmp/ipse-history-resume-retest.log`.

The current configuration and provider-pool files reproduced four further
baseline failures in their pre-receipt idle-resume assertions. Those fixtures now
require the exact previous journal followed by the single valid release-owner
start marker for the current layout. Configuration mismatch still requires the
entire post-resume journal to remain unchanged, and the pool-loss case still
checks socket closure and zero resumed dispatch. Both files passed together
(18 tests); the local log is `/tmp/ipse-config-http-retest.log`. This does not
establish the complete suite or resolve managed-output gates.

The baseline's two parallel-delegation close assertions and interrupted Writer
resume assertion also reproduced on the current tree. The delegation fixtures now
require confirmed close, an unchanged journal prefix, the unconfirmed lifecycle
closure bound to its release intent, and a verified signed release claim before
resume. They then check the exact owner-start marker and preserve the existing
child cleanup and no-replay assertions. The Writer fixture likewise checks the
exact resume marker while preserving its unknown-effect and edited-file checks.
The two complete files passed 24 tests; the separately selected parallel model-job
case also passed. Local logs are `/tmp/ipse-delegation-journal-retest.log` and
`/tmp/ipse-model-jobs-prior-failure.log`. These results do not qualify the full
suite or managed Knowledge operations.

The provider-stream usage-prefix failure also reproduced on the current tree as
an obsolete byte-equality assertion after resume. Its replacement checks the
exact allowed owner marker, the unchanged saved budget snapshot and no repeated
provider call. The complete stream test file passed 16 tests; the local log is
`/tmp/ipse-stream-resume-retest.log`.

The earlier malformed cold-manifest test passed on the current tree (seed
748469). The cost-summary cached-resume assertion was updated to validate the
exact owner-start marker while retaining its 70-request accounting and cached
result checks. The complete cost-summary, child-usage and text-stream files
passed 26 tests together; `/tmp/ipse-summary-stream-retention.log` records that
focused run. These results do not replace the full baseline.

The subsequent private `v10-synthetic-accepted-notice-display` fixture extends
the Session-owned notice exchange to six leases. A focused actual Session and
Host control passed with six synthetic owners (seed 504863), as did the
protected-worker coordination fixture (seed 504866). The retained pending-card
integration then passed its actual accepted-reference callback with a fixed
marker, expiry before activation, and original source-owner loss before
activation (seed 956047; one outer test passed). These are local synthetic
controls, not protected delivery: the Session accepts a cutoff from the trusted
fixture callback without authenticating it to protected provenance. Production
output, approval display, comprehensive owner-loss interleavings and independent
review remain open.

The retained-reference fixture now also kills the original management-journal
owner before terminal activation. Both the notice fixture (seed 402393) and
the earlier fixture mode (seed 652521) passed the outer integration test with
normal, expiry, source-owner-loss and journal-owner-loss cases. Each loss case
requires the fixed marker to be absent and an unconfirmed cleanup or Host
termination; this does not test owner loss after activation or prove protected
output safety.

The notice-mode integration was subsequently expanded to start a fresh admitted
Session after each expiry, source-owner-loss and journal-owner-loss case. Each
fresh Session revalidated the same accepted reference and completed the
six-owner fixed-marker exchange (seed 686238; one outer test passed). This
checks recovery after the fixture subprocess exits, rather than proving when
each lock became available or what happens during an active terminal write.
An attempted direct recovery inspection using the older test context was refused
by the newly enabled consent policy; the passing control uses the newly admitted
Session instead.

The mixed-filesystem baseline reported an unexpected third provider request in
the opaque-continuation control. Inspection showed that its Ollama fixture
contained plain text rather than opaque continuation data. The corrected fixture
includes a synthetic thinking field and passes the refusal and saved-restore
control without a third request (`/tmp/ipse-managed-opaque-retest.log`). A
separate plain-text control changes the source and inspects the actual third
local request: it contains the withdrawal marker and omits the stale answer
(`/tmp/ipse-managed-plain-stale-retest.log`, seed 828629). Its deliberately
invalid provider response does not qualify model behavior or protected delivery.

The baseline's stale-helper control expected the literal word `withdrawn`, but
the actual next main-provider request carried a structured withheld historical
receipt. The current fixture now checks that exact receipt and its tool name,
while retaining the no-helper-dispatch and saved-restore checks. The focused
control passed (seed 687229; `/tmp/ipse-managed-helper-stale-retest.log`). This
does not resolve the gated managed-output and effect paths.

The staged-document owner-loss baseline failure reproduced because confirmed
close created a new release receipt after the retained-file snapshot. The
fixture now checks the signed claim, derives the precise receipt path from the
final release intent, and requires all other retained files to remain identical;
the existing unknown-effect, journal-prefix and no-replay checks remain. Both
document inputs passed the focused test (`/tmp/ipse-doc-owner-loss-retest2.log`).

The ordinary Session lock test also expected a legacy resume after a native
header-backed start. It now checks the actual native resume mode, the guard's
matching mode and continued lock exclusion. The file passed its one enabled
test (five candidate controls remain skipped; seed 197892,
`/tmp/ipse-export-session-start-retest.log`). The public Collection document
owner-loss control now advances actual acquisition continuations and intercepts
the current fused `value.write_parts` commit boundary. It verifies the unknown
intent, inert resume, signed release and unchanged retained files; the focused
test passed (seed 763854; `/tmp/ipse-doc-public-fused-owner-loss.log`). The
separate document journey now uses a larger compressed fixture to reach a real
sealed-stage continuation; it rejects a forged stage epoch, changed file and
forged acquisition before further mutation, then validates selected and indexed
citations (one test passed; `/tmp/ipse-doc-public-staged-auth.log`). Its former
active-offset condition is instead covered at the lower Collection adapter
boundary: an actual partial native write rejects a forged offset with unchanged
header and operation count, and then resumes successfully (one test passed;
`/tmp/ipse-doc-active-offset-auth.log`). This is not an active-offset test
through the complete Word continuation path.

The shell recovery file now checks the exact resume owner marker while retaining
its unknown-effect and no-replay assertions; all ten tests passed (seed 771409,
`/tmp/ipse-tool-recovery-retest.log`). The extension-lab verification now checks
the same bounded marker in its three resume paths; its full source proof passed
(`/tmp/ipse-lab-proof-retest2.log`). The Graph recovery proof is now run in a
fresh VM so the host-domain-module isolation check is independent of prior suite
tests; its isolated proof passed (`/tmp/ipse-knowledge-recovery-isolated.log`).
The terminal assertion fixture's analogous resume and signed-close repair is
under PTY re-verification. Its first current-source rerun failed all 11 scenarios
because the fixture expected a lifecycle closure where the actual idle resume
has only a signed release intent with nil epoch and closure digest
(`/tmp/ipse-operator-assertion-pty-retest.log`). The assertion was corrected to
check that exact intent and its signed claim. A second run finished with six of 11 passing
(`/tmp/ipse-operator-assertion-pty-retest2.log`). Three retention/history cases
hit the existing deadline gate; the remaining two forget cases stalled because
the PTY driver answered before the full approval prompt. The driver now waits
for that prompt, and both forget/cancel cases passed separately (seed 766266;
`/tmp/ipse-operator-forget-pty-retest.log`). The gated retention paths remain
open; these results do not qualify the entire review journey.

The baseline's build-spec and evaluation host-isolation failures followed a
document grant test that loaded Knowledge profiles in the shared test VM. That
test now computes its configuration and invalid-binding refusal in a separate
Elixir VM and asserts the parent module-load state is unchanged. Its focused
test passed (`/tmp/ipse-doc-grant-isolation.log`); a combined run with the
build-spec and evaluation Session files passed 16 tests with 13 unrelated
document tests excluded (`/tmp/ipse-domain-isolation-combined.log`, seed
271840). This identifies one source of suite-order contamination; a current
whole-suite run remains necessary to find any others.

A current ten-file decision configuration, protocol, transport, Session, usage
and pure-policy run passed 60 synthetic tests (seed 497032;
`/tmp/ipse-p30-current-regression-20261030.log`). This does not qualify a
protected consumer, engine experiment or live account.

The workspace recovery baseline failures included obsolete byte-equality
assertions and a test trying to append without the native journal owner. The
fixture now verifies the exact resume marker, confirms the unowned append is
refused, and separately injects the invalid snapshot as external tampering to
retain the recovery rejection check. All eight workspace tests passed
(`/tmp/ipse-workspace-resume-retest2.log`). An intermediate run failed four
tests because the first edit changed the corrupt-tail assertion instead of the
shared resume helper; that edit was corrected before the passing run.

The current development build also passed `mix compile --warnings-as-errors`
(`/tmp/ipse-current-compile-20261030.log`). This is an incremental compilation,
not a clean frozen-source or installed-runtime qualification.

Seven current draft projection, native-data, lineage, ceiling, vertical and
operator-question test files passed 55 tests (seed 545529;
`/tmp/ipse-draft-questions-current-20261030.log`). That run used local fixtures
and did not include PTY tests, a live provider, or full P31I qualification.
The separately deferred draft-acceptance file has now passed all nine current
tests, including its PTY fixtures (seed 31496;
`/tmp/ipse-draft-acceptance-pty-current.log`). This does not establish a live
provider or installed-user journey.

The private shared producer can now hydrate existing durable explicit fact
projections at its pinned Collection snapshot before each group-append unit.
It verifies each projection against the captured source, catalog, selection,
canonical fact pages and entity IDs; a changed input changes the append plan.
The synthetic two-source control covers successful selection, corrupted source
binding and a changed projection between continuations. This is not a public
fact-staging API, a model-extraction receipt, a final approval-delay fence or a
maximum-workload measurement. Explicit zero-fact projections now have a
source-bound empty representation and a synthetic mixed-group selection
control. Empty model output still requires authenticated extraction evidence;
public staging and source-bound model dispatch remain open; the later guarded
explicit projection integration below covers a narrower approval-delayed path.

The private projection writer now commits against the generation returned by
its last sealed-stage inspection instead of taking a fresh snapshot immediately
before commit. Synthetic native controls cover both an unchanged successful
empty-fact projection and an unrelated native write inserted after both stage
inspections, which refuses the final switch. An initial implementation read the
wrong generation field and falsely passed the refusal control; the positive
control exposed that error, and both controls passed after correction. This
generation fence does not authenticate a source deadline or authorize public
staging, nor does it cover a real Session approval queue.

The host now has a private one-source projection authentication relation. It
checks the current catalog page, exact head revision and digest, complete
bounded source bundle and canonical source digest through the retained document
reader, returning the stored observation, expiry and historical fields. A
synthetic tampering control and an actual retained-owner/escaped-reader control
pass. The relation supplies no publication authority: the target must still be
bound to the exact live effect and stage contents, its time checked at the final
decision, and its observed generation fenced through the native write. Model
provenance, Session approval-delay behavior and public staging remain open.

The host can privately inspect a two-stage explicit fact projection under the
retained document reader. The relation checks the sealed stage owners, epochs,
revision preconditions, ready-value hashes, exact captured generation,
projection and catalog binding, stored page references and authenticated source,
and computes the earliest source or stage expiry. Native synthetic controls
cover empty and populated projections, a changed Collection generation, a
different owner and equality at a finite source expiry. The selected producer's
guarded explicit projection commit now uses this relation after Session approval,
rechecks the Session and source, and passes the earliest deadline to the native
generation-bound commit. Unguarded selected-producer fact-root commits and direct
inline publication refuse. Actual synthetic Session controls cover positive
replacement, expired source, expiry while approval waits, omitted guard, direct
write, catalog change and owner loss. These checks do not establish fact truth,
model provenance, all physical crash boundaries or public staging safety.

The dense Corpus `generation_produce` command now accepts an explicit `facts`
action. It reconstructs citations from compact source-local spans, stages the
projection through bounded continuations, and uses the guarded host commit.
The isolated model covers 32 facts with 256 citations and rejects a bad span
before effects; one actual synthetic Session covers the public action and its
guarded publication. Full-width input transport, journal/operation geometry,
model-produced facts, public group append, cleanup, migration and the integrated
capacity and audit gates remain open.

The public fact input now reserves continuation space: encoded arguments with a
null continuation over 12,000 bytes refuse before any Collection request.
A synthetic actual Session staged 32 facts and 256 citations with arguments in
the 11,900–12,000-byte range and restored its journal; a separate model control
checks that an SDK-valid oversized input refuses without a request or mutation.
This does not fit every allowed maximum-width fact set. Multipart durable fact
input and its full operation/journal geometry remain open.

The private compact-input codec now splits a validated source's explicit facts
into at most eight 7,000-byte pages and creates an ordered manifest of page and
row digests. Reconstruction verifies the authenticated manifest, every page,
the source binding, citations and canonical page layout; omitting even a final
page refuses against the original manifest. A synthetic maximum-width case with
32 facts, 256 citations, escaped identifiers, maximum timestamps and large byte
offsets produced eight 6,413-byte pages and a 751-byte manifest. Each proposed
slot wrapper fit the existing native request validator. This is a pure codec and
frame control: no durable reusable slots, manifest authority, native writes,
cleanup, Session handoff or end-to-end capacity are established.

The subsequent multipart implementation writes the pages to eight reusable
`factdraft` slots through a source-guarded, generation-bound inline operation.
The public dense Corpus actions inspect slot revisions, stage each page and
assemble the complete manifest on each projection continuation. The host refuses
unguarded selected-producer writes to those slots. A synthetic actual Session
staged and assembled 32 maximum-width escaped facts with 256 citations, refused
an incomplete set, and restored its journal. Another Session control covers
stale revisions and changed draft identity; an approval-delayed source-expiry
control refuses the slot write. The first full-width attempt exposed a native
packed-size refusal, repaired by factoring packed size into fact-page splitting.
The [local planner](../../../dev/knowledge/plan_fact_input.exs) and its focused
test prepare a manifest from supplied source and row files. Multi-source peak,
slot lifecycle under concurrent jobs, full Session handoffs, cleanup/migration,
model provenance and final qualification remain open.

The private Host group-source predicate now checks the exact catalog slice,
current source heads and complete source bundles for up to eight sources. A
private staged-commit predicate also binds the next Job, selected root, group
header and summary to the captured generation and computes a deadline from the
source and stage expiries. Native split-append controls cover a finite source
deadline, missing evidence, wrong owner, an empty-fact group and root
interposition. These predicates do not grant write authority and are not wired
to public append. Whole-generation source freshness at final selection,
public admission, physical capacity and integrated qualification remain open.

The Host now accepts a distinct guarded group-commit request for an explicitly
selected producer and carries the proof deadline into native admission. An
actual synthetic Session confirms that the group guard cannot be substituted
for a staged fact-projection commit. A second synthetic Session uses a private
test adapter and the guarded Collection operation to commit a live, finite-TTL
source group through ordinary approvals and the journal. An internal guarded
Job entry point now chooses that operation itself, and the private producer
append path uses it. The same synthetic Session controls pass through the Job,
including a changed source head during approval that leaves its cursor unchanged;
private producer progression also has protocol-model controls. For a selected
producer, the Host now refuses direct Job publication and unguarded advancement
from the group phase; a synthetic Session exercises omission and confirms that
begin and abort remain available. This fence is limited to Job advancement and
does not establish whole-generation source freshness at final selection. Public
producer integration, final selection, and integrated qualification remain open.

Finalization replaces group summaries with manifests. A new private Host
predicate reconstructs one current catalog slice and authenticates the complete
source bundles without relying on a retained summary. Synthetic and native
retained-reader controls pass; an eight-segmented-source fixture used 36 reads
for 581,824 source-bundle bytes. This is one bounded group only: manifest/root
binding, cross-group generation fencing, deadline propagation and final
selection admission are not implemented by this predicate.

A further private predicate binds one immutable manifest row and stored group
header to the current authenticated catalog slice. A native reduced-directory
fixture checks a valid row, missing header, wrong cursor and a correctly hashed
manifest naming the wrong source. The caller must still bind the manifest
reference to the staged final root and authenticate every group at a single
unchanged generation before final admission.

A private final-selection predicate now binds three sealed stages to the
current Job, catalog, previous root and reduced manifest references, and returns
their stage deadline. Native finalization controls cover both directory formats.
A second private check visits each manifest group through a bounded retained
reader at the same native generation, verifies the aggregate source-head
digest and computes the earliest source or stage deadline. A one-group native
fixture covers success, stale generation, wrong aggregate digest and expired
deadline. The Host now has an explicit guarded final-selection operation that
checks all groups, rechecks the Session and extension identity, and supplies the
earliest deadline to native admission. A synthetic Session exercises one-source
selection, refusal when its guard is omitted, refusal of a direct root write,
and a source change while final approval waits. A nine-source synthetic Session
also completes two-group selection, while changing or allowing its second-group
source to expire during final approval refuses selection. A separate synthetic
control invokes the same checker with real retained Collection reads and mutates
a source after the first group returns; the second read refuses the changed
generation, and the Session's pending selection remains uncommitted. This uses
a test-supplied read wrapper, not interposition inside the Host's own call.
Maximum-scale cost, wider public producer integration and complete qualification
remain open.

A real active-source proof and two independently verified inactive original
sources now pass through the fixed-text grouped input fixture. The union's
post-callback check also refused when a test-only writer interposition redacted
the active source during the held input. The control observed that the review
callback had already returned success before the enclosing union reported the
stale source. Therefore that post-check withholds its result but cannot prevent
an effect already performed inside the callback. Production supersession must
still revalidate and fence the exact active and inactive sources at publication;
this fixture does not establish that boundary or authorize protected facts.

The native transaction can now retain a second, role-1 Session owner control
alongside its existing role-2 writer control. It checks both controls at the
final root-switch decision and requires sources and the Session control to be
closed before the writer control. The existing two-source acceptance guard
refuses the expanded control shape. Native root controls passed with both
controls present, and loss of either before the switch retained the old root.
A separate switch retained two independently verified original source leases
and both synthetic owner controls; the exact old acceptance guard refused.
The combined transaction and source files passed 48 tests. The helper was
rebuilt with the bundled flags at SHA-256
`60dafd345face806c10aedf62bde294116d371c75f3afa6dd3de36e0a9fd8b85`.
The added slot is not yet wired to the real Session/Writer publication path or
reviewed facts, and these tests do not establish protection after the final
decision or prove power-loss durability.

The private Session sharing protocol now opens and transfers the actual
Writer control, requires its recipient to match the Session control recipient,
and settles the native transaction before thaw. The Writer has a separate
prepare-close state and waits for its control's successful exit; the existing
management journal transaction uses that handshake too. A real Session/Host,
Writer and native transaction completed a synthetic root switch and cleanup.
Killing either the Session or the Writer control before switch left the old
root; a mismatched recipient was refused. A test-held actual Writer control
exit showed the Session waiting before thaw until that exit was processed.
The combined Session, management-journal and source regression files passed
49 tests (12 skipped, 25 excluded), including the recipient and held-exit
controls. The first Writer-loss attempt exposed an unhandled control-exit
message and terminated the Session; explicit normal Writer shutdown fixed the
control path before the passing repeat. These tests do not bind reviewed facts,
inactive-source leases, or an active proof to the final switch. Supersession and
production publication remain gated.

The Writer can now revalidate an exact, bounded active-proof set in the same
serialized operation that freezes its journal, returning the checked sources in
the frozen snapshot. An inactive host-only Session fixture binds the expected
proofs and refuses a different frozen snapshot. Real Session controls passed a
source-bound native switch, a held barrier that refused journal mutations, and
a redaction between ticket issuance and Writer drain that prevented the barrier
from forming. A combined synthetic switch retained the active Session proof,
Session and Writer controls, and two verified inactive original-source leases.
Killing an inactive source after transfer terminated the Host without confirmed
success and left the old root selected. The first test incorrectly required an
unknown result message; the corrected control accepts owner termination and
checks the old root. These tests do not bind the proof set to reviewed relation
facts or provide a production publication adapter; the existing gates remain.

The supersession candidate path now records the exact live Review preview
receipt before entering its source and publication callbacks, then requires the
normalizer to consume that same receipt. A private Session source-fence ticket
checks the recorded intent and review against the pending candidate, derives the
active and inactive proofs from the exact relation facts, and rechecks that
binding at Writer drain. A source-backed signed-predecessor fixture passed
structural receipt, relation and proof-set tampering controls; a Session with no
recorded relation refused the ticket. The simulated Review permit control also
checked that preview and consumed receipts match. The review receipt used by
the binding fixture is synthetic. No positive genuine Session relation has yet
passed this new ticket or earlier-record path, and no production display, live
permit, deadline, inactive-lease or effect integration is established by these
checks. Existing public supersession and Core publication gates remain closed.

The private grouped-review fixture now has the Session send the initial native
manifest with its own fixed synthetic text before transferring the Session
control. It checks the operation, owner PIDs, lease slots and operation IDs,
and selected wall bounds; the native helper checks the activated manifest
against the initial one. A real Session PTY confirmation passed. An instrumented
Host injected different initial text before the Session's manifest; the native
path refused, the task reported unconfirmed cleanup, and the PTY driver observed
no injected text. A malformed manifest also refused. The first two injection
assertions incorrectly assumed Host death and then successful task completion;
the corrected repeat checked the observed refusal and error. The native v13
mode itself accepts arbitrary bounded text and does not authenticate its origin;
only the Session-issued fixed-text fixture uses it. Real relation facts, source
identity and authorization remain unbound and production display stays gated.
The helper was rebuilt with bundled flags at SHA-256
`e56867fef8c69cb5337ba8f1d316c77857cd10e2a9e9efd90ef9a9d8e49cc6d7`.
An initial warning-free compile caught an Elixir bitstring pin warning, fixed
before the passing compile. Concurrent native operator and grouped-terminal
tests encountered terminal-channel contention; those results are kept separate.
The grouped-terminal file passed when rerun alone. Native operator unit tests
passed 21 controls with one subprocess entry ignored. After the final Session
error-handling repair, the Session-issued positive, malformed-manifest and
injected-text controls passed again, as did the held-input terminal-loss control.

The owner-bound inactive-source registry now retains the exact proofs resolved
under each original Session lock. The grouped synthetic review checks that
each source token belongs to the requested Session and exact ordered proof set
before constructing the native manifest. Source tests refused a different
caller, subset, reordered set and cross-session substitution. A PTY control
swapped two original-source tokens and observed refusal before any review text;
the active/inactive union review and injected-manifest refusal also passed.
The source regression file passed 23 tests. The returned binding is host-local
and structural: Session has not independently authenticated these identities
against recorded relation facts, and this does not authorize protected display
or publication.

The supersession display guard now uses the held signed-target callback rather
than closing its Collection view before the display continuation. Thus its
existing Identity, Consent and Collection scopes overlap the continuation.
A source-backed component control compared the same signed target before and
inside a live-policy callback and observed all three native transaction owners;
a wrong policy was refused before continuation. The three held-target controls
passed, as did 10 focused supersession binding, journal and consent tests.
The changed `guard_display` is still behind the public supersession gate; these
component tests do not prove a genuine Session display, cross-process control
transfer, source ownership during native output, or an effect.

Dense Corpus now exposes guarded finalization explicitly through the optional
`guard_sources` command field. Public synthetic Session controls with trusted
captured-group fixtures cover both a successful final switch and refusal when a
source changes while final approval waits. Legacy unguarded bindings retain their
existing command path. Dense Corpus now exposes guarded group append from ready
vector pages and stored explicit facts; a one-source synthetic Session proceeds
from model pages and fact staging through guarded append and selection. Wider
public group production and full capacity qualification remain open.

A six-source, two-vector-page public journey in one synthetic Session hit the
2,048-entry managed-lineage producer limit during append. Its reconstructed
journal recorded 1,972 action results and withheld the next action output;
the result was unknown and no continuation was offered. This is a Session
capacity limit, not evidence that the group was appended. A separate fixture
passes with a confirmed stage-free handoff after page and fact staging; it does
not transfer live stages or replay the interrupted invocation. The two synthetic
journals recorded respectively 1,325 and 930 action results, with no withheld
outputs, and totalled approximately 13 MB. Reconstruction passed for the first
journal before closure and for the second after guarded append and selection.

A first nine-source, two-group public trial completed the first group and a
stage-free handoff, then its second embedding request failed. The synthetic
server had stopped after 120 seconds without a request while facts and the
first group were staged. The fixture now continues listening after an idle
timeout. A fresh isolated trial produced nine sources in two groups, reused the
first group's producer slot after its completed Job step, and selected all nine
sources and facts. It used four Sessions with confirmed stage-free handoffs;
their synthetic journals recorded 2,897 action results, 121 invocation results
and approximately 14.3 MB total, with no withheld outputs. This is not a
maximum-scale, cleanup, migration or real-provider qualification.

An in-memory Host-check model now visits all 125 manifest groups for 1,000
small synthetic sources. It counted 3,750 reads in total, at most 30 per group,
and 546,893 source-bundle bytes; a changed generation at group 63 and a
future-observed source in the last group both refused. The measured run took
840 ms on the test host. This fixture supplies read closures and minimal group
headers: it performs no native operations, lock acquisitions, populated storage
or Session publication and does not establish maximum-width source cost.

An isolated populated native Collection was then seeded directly with the same
1,000-source, 125-group relation. The larger synthetic fixture contained
20,480,000 extracted text bytes and 21,009,893 source-bundle bytes in 2,197
records. Direct fixture seeding used 138 commits and took 14,923 ms; the source
check used 3,750 retained record reads and took 11,134 ms on this test host.
A small-source native control also passed. These measurements exclude normal
ingestion, vector/fact payloads, real document metadata, peak allocation and
the final staged publication; the fixture uses minimal synthetic group headers.

A follow-up on the same 1,000-source and 20,480,000-text-byte geometry prepared
three native stages for a synthetic final Job, catalog and root. After the
source check, an interposed native write changed the generation; the old commit
refused and left the root absent. A fresh explicit generation-bound check then
selected the staged root. The source check took 10,870 ms; the two checks,
interposed write and final switch took 23,645 ms after staging. This control
directly seeds minimal synthetic Job and group values; it does not validate a
full domain reduction, exercise the public Host/Session caller, or measure
normal ingestion, peak allocation, rebuild overlap or real documents.

A later run sampled Collection status after each direct fixture mutation. Its
per-field settled maxima were 2,205 records, 144 operations, 22,510,175 data
bytes, 22,937,230 disk bytes, 30,183,424 allocated bytes and 97,292,288
accounted allocated bytes. The accounted figure includes a 64 MiB reserve.
After selection, status reported 2,200 retained records, 144 operations,
22,491,541 data bytes, 22,925,609 disk bytes, 30,167,040 allocated bytes and
97,275,904 accounted allocated bytes; stage listing was empty. The measurements
are observations after completed mutations, and individual maxima need not
coincide. They do not capture transient allocations within a write, ordinary
ingestion, a previously selected root or rebuild overlap. The directly seeded
Job and projections remain synthetic and are not a full domain qualification.

A separate native run seeded a previous synthetic selected root at the same
1,000-source geometry and bound the staged replacement to its exact revision
and content hash. An interposed write caused the stale commit to refuse while
the previous root and revision remained intact; a fresh source check and commit
selected the replacement, with no stages left. The run observed at most 2,206
records and 30,187,520 allocated bytes after individual mutations; its retained
state had 2,200 records and 30,167,040 allocated bytes. The prior and new roots
reuse the same synthetic projection references. This proves the checked root
transition in this direct fixture, not the full storage overlap of a rebuild,
the public Host/Session path, transient peak allocation or domain-valid data.
An initial fixture run failed because its assertion compared the old root's
revision with the newer staging generation; the corrected isolated run passed.

Lifecycle operation inspection previously ignored an incomplete management
journal tail and could report an earlier result as settled. It now reports the
journal status as unconfirmed when the tail is incomplete, while retaining the
separately observed control status. A native terminal fixture completed a
synthetic forget, appended a partial record under the retained lock, and checked
that inspection returned unconfirmed without changing or replaying the journal.
The fixture then restored its complete journal. This is a diagnostic repair;
it does not reconcile an uncertain effect or enable proposal acceptance.

The full-suite knowledge-setup fixture failed after a headless capture because
its synthetic `:demo` provider was unregistered: the Session correctly refused
to send managed history on that route. An isolated diagnostic confirmed that
the capture had already completed and the following inference was withheld.
The fixture now uses a registered loopback synthetic Ollama route for its
three-request save journey. It retains the saved-consent, `never_current`
proposal, confirmed-close and revocation assertions. All eight knowledge-setup
tests passed after correcting the fixture server's three-response return
assertion. This is synthetic loopback evidence, not live Ollama or a complete
notes qualification. The full-suite run in progress began before this fixture
change and is mixed-source evidence; the earlier failure remains in its log.

The retained management display now has a private retention-review candidate
for `pin`, `ordinary` and `duration`. It binds the native command to the exact
prepared policy and fact digest, rejects an expired or future-admitted target,
and bounds the input window by the existing signed deadline. After input it
reacquires the signed target and current management owners before consuming the
one-use review. A synthetic native terminal fixture confirms each of the three choices,
refuses cancellation, expired and future targets, and checks the stored target
remains unchanged. The focused management file passed six tests; the existing
Review and lifecycle files passed 24 tests before the additional future-time
check. This candidate does not publish a retention choice or expose a public
command. Publication fencing, concurrent owner-loss/revocation cases and
current-source end-to-end retention qualification remain open. The ongoing
full-suite run also predates these source changes and is mixed-source evidence.

The private retention review now rechecks the signed admission and expiry
immediately before consuming the permit. An instrumented native terminal
fixture accepted input, held the revalidation callback past the real signed
deadline, and refused the review without changing storage. The hold is a test
interposition and is not a publication or physical-completion deadline test.

As a prerequisite for an owned retention effect, the Writer's share-barrier
snapshot now identifies the immediately preceding synced lifecycle intent.
A private transaction scope binds that exact intent to the same owner and
retained management journal, and rechecks its deadline while the scope is live.
Native share controls cover the bound case, altered/cross-process guard refusal,
and removal of the binding after an intervening journal append. This scope does
not itself permit a Collection write. The Core retention fence remains closed;
final-switch fencing, effect integration, owner-loss and no-replay controls are
still required.

The Review owner now has a private one-use retention-effect claim. It binds the
consumed native-review receipt to the exact lifecycle intent, original target
request, normalized request and retention receipt; validates the selected policy
and its confirmation-time deadline; and computes a finite switch deadline from
the remaining permit lifetime and any earlier old/new deadline. Even a pin with
no signed expiry has a finite permit-derived bound. Permit-state fixtures check
one-use behavior, altered requests and sidecars, and equality at that bound.
These fixtures simulate terminal input and time; no Collection caller uses this
claim yet. It does not qualify the native final switch, physical completion,
clock rollback, publication or a public retention command.

The private retention candidate now journals its intent, reacquires current
Identity/Consent/Collection ownership, normalizes the exact target and claims
the review once. A separate guarded Collection entry retains the exact
management-journal lease through the native timed root decision; it refuses
ordinary callers that lack that live claim and journal owner. Fresh synthetic
native-terminal runs settled `pin`, `ordinary` and one-day `duration`, preserving
the literal value, recording settled management receipts, and reading back the
authenticated chosen policy, deadline and unchanged original admission clock.
A staged-expiry
control held the root switch past the old signed deadline: the old root remained
selected and operation inspection reported unconfirmed, without replay. A
separate instrumented control killed the actual management Writer immediately
before that switch; the old root remained selected and inspection was
unconfirmed. These are specific synthetic schedules, not exhaustive loss or
physical-clock qualification. Denied, headless and narrowed modes refuse the
private effect; the public retention command remains fenced.

The first effect attempt returned unknown after the Collection reported success:
Consent expected the pre-claim review state. A fresh traced attempt identified
that mismatch, and Consent now verifies the exact claimed-retention receipt
before settlement. Later tests used fresh stores; the original unknown was not
replayed. The first writer-loss control also failed to observe its marker
because the killed Writer was linked to the marker-sending process; the repaired
fixture signals before the kill and separately monitors actual process death.
Independent review, wider loss/expiry races, installed
behavior and the complete retention lifecycle remain open.

An isolated helper built with `ipse_source_switch_test_hook` paused the private
retention effect immediately after the native root rename. The fixture killed
the actual management Writer at that point. A fresh protected read saw the pin
policy, and the selected root's floor anchor matched the one journaled intent;
there was no lifecycle result. `knowledge operation` reported unconfirmed and
did not replay it. The test helper's SHA-256 was
`244f127e17c2d3cdc0928e3d19aa92245a222aac4df227444e75124a6ea0e001`,
and its Runner was compiled against that private helper, not the ordinary one.
The test arms the hook only after retention staging. Earlier attempts armed it
too soon and intercepted another root switch; those failures are not evidence
of the desired boundary and their unknown operations were not replayed. This
control does not prove power-loss durability, every post-switch cleanup point,
or public retention readiness. The normal-helper pre-switch Writer-loss and
generic Collection-fence controls also passed after the fixture update.

The same private helper also paused after the root directory sync and killed
the management Writer there. The pin was visible, the root floor anchor matched
the single intent, no result was journaled, and inspection reported unconfirmed
without replay. The after-rename and after-sync scenarios passed together in one
isolated tagged run. These are two controlled owner-loss points; they do not
establish power-loss durability or the remaining cleanup and public-adoption
requirements.

Two additional private retention controls held native input after the review
card appeared. One changed the protected management epoch; the other advanced
the Collection root with an unrelated synthetic write. Neither retention
attempt settled, the post-race selected root matched the competing state, the
signed target metadata and literal value stayed unchanged, and each management
journal contained exactly one intent. Read-only operation inspection reported
refused or unconfirmed without replay. These are approval-wait schedules, not
interpositions inside the native root decision or full concurrent qualification.

A further native-terminal control selected a synthetic eight-second duration
while the existing signed deadline was much later. At the staged root switch,
the finite publication bound was no more than eight seconds away and preceded
the old deadline. Holding the switch beyond that bound left the old root
selected; operation inspection reported unconfirmed without replay. The existing
old-deadline staging control also passed after the shared fixture changed. The
first version of this test incorrectly assumed a duration started at original
admission; the displayed rule and implementation use native confirmation time.
That failed attempt was not evidence of publication behavior. The short
duration is a private synthetic policy, not a public CLI day setting; this
control does not establish all timing or power-loss schedules.

The public `knowledge retention --policy session` command now invokes the
existing full-facts reviewed forget effect, with a session-retention reason.
Fresh native-terminal controls confirmed the selected literal is removed and
the management journal settles; cancellation leaves the selected root intact.
Denied, headless and narrowed mode controls refuse before touching storage.
The first CLI attempt refused before review because its reason exceeded the
64-byte lifecycle limit; the corrected test used a fresh store. This is a
reducing selected-literal operation and does not erase original journals or
shared evidence. It does not open persistent retention or qualify installed
packages and the complete lifecycle.

The public CLI now routes pin, automatic and duration through the private
guarded effect described above. Fresh synthetic native-terminal CLI controls
settled all three policies, read back their authenticated choices and original
admission clocks, and confirmed the management journal without replay. A
cancelled pin review preserved the selected root; `--yes` and denied, headless
and narrowed modes refused. The existing private timing, race and owner-loss
controls do not by themselves qualify every public or installed failure path.
The public integration and complete lifecycle still require independent audit.

Two subsequent public CLI controls exercised interrupted effects. One held the
staged root switch past the existing signed deadline; another instrumented the
management module to identify and kill its actual journal Writer immediately
before that switch. Both returned a non-success exit, preserved the previously
selected root, and inspection reported an unconfirmed journal without replay.
They passed together on fresh synthetic stores. The Writer interposition is a
test-only recompile and does not cover post-switch loss or power failure; the
earlier private post-rename and post-sync controls have their own stated scope.

The previously failing native Session expiry scenario now passes on current
source. A reviewed literal is assigned a five-second duration, read by a later
Session, and expires while a deliberately delayed read worker processes it.
The tool output is withheld, the release is journaled as withdrawn, saved
reconstruction retains the withheld output, and no additional inference is
dispatched. The raw worker result remains in its protected journal; the test
does not claim historical erasure. The first current-source rerun refused at
operator setup; a second reached the duration review but timed out because the
synthetic terminal driver sent its answer before `approval>` was ready. The
driver now waits for that prompt for all management retention commands, and a
fresh rerun passed. These results do not qualify general capture or recall.

Current-source native CLI reruns also passed the reviewed statement followed by
retention and ordinary expiry journeys. The separate historical-expiry journey
still fails while trying to create its corrected predecessor: the generic
supersession effect remains fenced and its native review returns unconfirmed.
The failed attempt does not establish a saved correction and must not be replayed.

As a source-ownership prerequisite, `StoredSources` can now retain and verify
multiple distinct proofs from one inactive original Session under the same
transferable lock. Focused controls check exact ordered proofs, lock retention,
and refusal of duplicate, mixed-Session and active-Session requests; the whole
stored-sources test file passed 13 tests. The existing single-proof API delegates
to the same implementation. No supersession caller uses this yet, and this does
not solve active-Session sharing, multiple original Session locks, display or
publication fencing. Separately, all 12 extension-result Session tests passed
on current source in isolation after admission failures in the mixed suite;
that is not a diagnosis of the earlier failures or a full-suite result.

The private source lease registry now also retains proofs across multiple
inactive Sessions, returning one owner-bound token per Session in deterministic
order. A two-Session fixture checks simultaneous locks, exact input proof order,
actual transfer and settlement through one native collector, and refusal when
either source owner dies. Duplicate, active-Session and nested lease requests
are refused. The first two-owner transfer fixture used an incorrect collector
slot for the second independent helper; slot zero for each matched the helper
protocol and the corrected control passed. The collector used here allows up to
four leases; this does not qualify an arbitrary-size terminal or root decision.
No supersession caller is connected, and the active Session and complete display
and publication ownership remain open.

The separate grouped terminal protocol now also supports its managed input
phase, and the private management adapter can pass a verified group of source
tokens to it. Synthetic native-terminal controls passed with two and 128 source
owners, read an exact confirmation after lease settlement, and refused when a
live control owner died after the input prompt became ready. The actual
protected pending-review fixture also passed through the group adapter with one
verified inactive source, including its existing one-use review and journal
checks. The first isolated run lacked the bundled artifact; the next reached a
valid review but the fixture collided with an earlier event output. After
copying the bundle and separating fixture outputs, a fresh run passed. These
controls do not bind a real multi-source supersession or its current Session;
they do not qualify protected display after arbitrary owner-loss schedules.

Supersession's existing source scope now uses a mixed active/inactive union:
it checks active proofs through the Session before and after the callback and
retains transferable locks for all inactive originals within that callback.
The callback sees the exact input proof order and only inactive lease tokens.
Controlled Session-owner fixtures passed active-only, inactive-only, mixed and
changed-active-proof cases; the native source and relation files passed 23
tests. This does not transfer the active Session lock to the terminal or root
decision, and the public correction path remains fenced. The Session-owner test
uses a controlled GenServer, not a real supersession Session.

A subsequent synthetic PTY control used an actual active Session journal proof,
two verified inactive original Sessions and the grouped Session/Host terminal
bridge in the same source-union callback. The active proof was checked through
the real Session before and after the callback; the active and original locks
were held during the fixed synthetic marker display. A forged active receipt
was refused before display, with no marker in the captured PTY output. The
fixture temporarily replaces the Session's current action with a synthetic
`collection.call` and uses separately constructed source-policy context; it is
not an authorized supersession or proof of project-policy integration. The
first positive attempt requested an unsupported 64-entry source page and
failed before the callback; the corrected 32-entry request passed.

A private synthetic bridge now transfers the actual active Session lock, its
Host control and a grouped set of inactive original-source leases into the
grouped native terminal. A real Session/Host PTY control passed with two
independently verified synthetic original Sessions and a fixed synthetic marker.
With a test-only pause immediately before activation, killing an original
source owner or the active Session terminated or refused the Host; captured PTY
output contained no marker in either case. The first source-loss assertion
incorrectly required a returned error even though the Host terminated; the
corrected repeat accepted that owner-loss outcome and checked captured output.
Existing six-owner display and notice controls passed after their source-based
instrumentation was updated for the variable-length manifest. This bridge does
not display protected facts, bind the active Session's source proofs to a
relation, authorize input, or perform supersession.

The concurrently running full suite finished with 3,431/3,513 passed, 82
failures, 53 skipped and 86 excluded in 5,408 seconds. Its log is
`/tmp/ipse-full-test-goal-20261030.log`. Source and fixtures changed while it
ran, so this result is diagnostic and cannot serve as a fixed-source baseline.
Individual later reruns recorded above do not turn it into a passing suite.

The transaction adapter now accepts an exact, unique list of one or two live
source tokens and nests their existing native imports in order. A real two-source
root switch passed with both original locks retained. Separate interpositions
killed each source owner after staging; each attempt left the old root selected
and did not return a confirmed switch. The full stored-sources file passed 18
tests. The native transaction has two total import slots, shared with journal
leases, so this is not a multi-source supersession path and does not bind the
active Session, review display or a management journal.

The source-import stack now allows 129 retained imports, and the host grouped
adapter accepts up to 128 distinct source tokens. An isolated current-source
helper (`c31f03989fc6cf22e489fb3871f5bb14084f952e875077f593caacccf3a03cd8`)
passed a native root switch with 128 distinct original Sessions plus one live
management-journal lease. The existing acceptance guard refused that larger
set, and the journal was frozen until the switch settled. A separate 128-source
attempt killed one middle source owner after staging; the old root remained
selected and the callback did not return confirmed success. The helper and its
Runner BEAM were isolated under `/tmp/ipse-many-source-20261030`; the ordinary
helper was not replaced while the mixed-source full suite was running. This is
not a public supersession path, a terminal-display test, or a power-loss test.
Production use still requires a matching rebuilt native helper and host.

After the mixed-source suite finished, the ordinary native helper was rebuilt
from current source with the bundled build flags, then the host and knowledge
bundle were rebuilt. The helper SHA-256 was
`287b73eee9376d0093d3ec3686e6cdee4f54f83f82e53920d11a41f3050fa0da`.
The 128-source plus journal root control passed against this rebuilt runtime.
The protected pending-review group control also passed with two independently
verified inactive original Sessions: it transferred both leases through the
actual management review, accepted the native confirmation, and checked the
recorded display hash and one-use event. This test's second source is an
explicit synthetic fixture, not a source bound to the pending proposal; it does
not authorize multi-source supersession or establish a complete proof-set rule.

Supersession preflight now derives the old/new proof union from the exact
reviewed relation facts and checks it against the sources held for preflight,
display and effect. The binding checks the relation digest, selected recipe and
new-source digest; a shared proof is retained once. Focused tampering controls
and a source-backed signed-predecessor preparation passed. This matches the
current implementation's one-proof-per-side restriction. It does not restore
the disabled Session intake, transfer active-Session ownership, authorize
display or open the generic supersession effect. An initial pure fixture used
an invalid empty-constraint recipe and failed; it was corrected to the
fixture's valid admitted recipe before the passing run.

Relation preflight, display revalidation and the post-input effect boundary now
also require the exact command/mode, admission and preparation clocks, old
deadline, history rule and reviewed proof set. A signed ordinary-predecessor
fixture passed and refused a wrong command, earlier clock, elapsed old deadline
and a rehashed altered history rule. These are local admission checks; they do
not open the Session or Core fences. The active Session bridge currently keeps
its Writer frozen until terminal close, whereas an interactive review needs an
owner-bound thaw before waiting for input. That distinct Session state and its
owner-loss behavior are still required.

A separate native review owner-control mode now keeps the original five-second
setup bound and enforces a total 5,000–120,000 ms lifetime. Its owner-bound Host
opener rechecks the selected helper and action preparation. Source-built controls
passed setup timeout, invalid duration, survival beyond five seconds, finite
expiry and owner closure; the existing owner-control file passed 11 tests. The
ordinary helper and Host were rebuilt with SHA-256
`6e6958a731e39014ec2ec78a35f468026edba60ef7c183e67fa8ad6ad886af28`, and the
existing active-Session synthetic bridge passed on that runtime. This mode sends
no display or review notice and is not wired into Session input. The native
duration begins at helper startup; the eventual Session must independently
enforce its selected absolute deadline. Initial test assertions incorrectly
expected an error exit and no observer frame on ordinary owner closure; the
observed authenticated close frame is now checked explicitly.

An additional source-built v4 review control combines that bounded lifetime
with the existing authenticated peer-notice exchange. A source-built control
received a correctly bound notice after the five-second setup interval and
then observed expiration at the total deadline. A deliberately altered peer
sent a different operation and the sender refused it without reporting a notice.
The focused native-control file passed 12 tests before the separate adversarial
test was added; that test passed independently. The new mode is not wired into
Session or protected review, and the installed native helper was not rebuilt for
this change. The notice alone proves neither displayed facts nor consent.

The host now has an owner-bound opener for the v4 notice control, with the same
action, preparation, helper-identity and deadline checks as v3. The ordinary
helper was rebuilt with the project native flags at SHA-256
`1acfc9e29f6cb492bb80b691b2e8b072f776380ca7a8a3268339ac3d8332021e`, and
the Elixir host was force-compiled. The actual opener refused a different action
and caller and started the expected notice protocol for the bound owner. This
does not establish the terminal's purpose or connect the control to Session.
The complete updated owner-control test file passed 14 tests, including the
forged-operation and repeated-notice peers and v4 lifetime bounds.

A fixed-text synthetic grouped terminal now combines v4's peer notice with
the existing grouped lease and interactive-input protocol. Source-built PTY
controls passed confirmation for small and 128-source groups, checked the
operation-bound notice and final exchange, and refused loss of the Session
control during input. A separate invalid manifest supplied private text and
was refused before display. The grouped-terminal integration test passed on
the updated source. The ordinary helper was rebuilt at SHA-256
`77e084b41aa315c5caabd8a1667bf578d0922740d43714a9672d2a0c24bf88b3` and
the host was force-compiled. These controls use synthetic owners and fixed text;
they do not authorize protected review, establish a Session writer thaw, or
qualify supersession.

The fixed-text grouped review now has an experimental real Session/Host path.
The Session verifies its issued terminal and operation-bound notice before
asking its Writer to thaw, retains both owner controls while input is pending,
and requires the final notice and closed terminal before clearing the Session
fence. A real Session with two original source owners completed the synthetic
confirmation. A held-input control observed the Writer barrier cleared while
unrelated Session calls remained refused, stayed active beyond the original
five-second setup limit, and poisoned the Session when the terminal was killed.
A separate held input expired at the 15-second overall deadline. A pre-notice
thaw attempt was refused with the Writer still frozen. The prior synthetic
notice path passed on rerun alone; an initial concurrent run failed to acquire
its terminal channel while the held-input control was active. These are fixed
synthetic facts and synthetic review authority, not a production supersession
or protected-content implementation. Fact-bound display, exact active-source
revalidation after input, real effect integration and broader loss/race review
remain open.

The source-built native terminal now has a separate synthetic grouped-lease
display mode. It retains the existing single-source and accepted-delivery
protocol shapes and permits at most 128 additional source owners only in the
new mode. Synthetic PTY controls passed with 128 additional owners; killing a
middle owner before display refused without printing the marker. Additional
controls refused missing, malformed and over-limit manifests. This mode is not
wired to protected review or operator input. It does not qualify current Session
ownership, real protected facts, post-display loss or supersession publication.

The coordinated supersession guard now constructs an authority record while the
Identity, Consent, Collection and original-source leases are held. It binds the
ordered source proofs and three retained transaction owners, and passes that
record with the deadline to the guarded child. The old proxy refuses display:
the native recipient does not yet retain and authenticate those owners. A focused
source-owner control rejects swapped or missing inactive leases, and a
coordinator fixture checks authority delivery and refusal without a review
permit. The focused Review, StoredSources and supersession-journal files passed
50 tests; ordinary compilation passed with warnings treated as errors. These
controls do not prove cross-process transfer, real protected display, or
publication, and the supersession gates remain closed. Controlled-terminal
exclusions apply to that test run.

The authority builder additionally checks that its proof list is bounded,
well-formed and unique and actually contains the active Session, rather than
trusting the supplied active-source flag alone. The source-owner control now
also refuses an absent active proof and a duplicate proof. Compilation with
warnings as errors and the same three focused files passed again (50 tests,
with the controlled-terminal exclusions). This is structural validation, not
independent verification of the active proof or cross-process lease transfer.

The earlier mixed-source full run reported an incomplete measurement and
storage inventory in the suppressed lexical evaluation fixture. On the current
source, that selected child fixture passed alone with the default scheduler
configuration and again with the isolation runner's `+S 2:2` configuration (one
test, 26 excluded each time). This does not identify the earlier failure's
cause or replace a fixed-source full evaluation and full-suite run.

The four extension-result admission failures from that mixed-source run did not
reproduce in the current result-session file (12 tests passed). The separate
packed vector catalog-race failure did reproduce: its test waited for a snapshot
request that the current finalization path no longer issues after the two stage
inspections. The control now pauses the final commit at that boundary, changes
the catalog's physical revision, and checks refusal and preservation of the old
selected vectors. The selected test passed (one test, 58 excluded). These runs
do not qualify the complete collection or resolve the other full-suite failures.

The current-source six-source public group-append test passed in isolation
(one test, 21 excluded, 181.8 seconds), including its stage-free Session
handoff and guarded final selection. The earlier mixed-source run had failed
admission at that handoff; the isolated pass does not establish the cause or
replace the full-suite baseline. The mixed run also attempted the literal-v4
upgrade control without `IPSE_LITERAL_AB_ROOT`; that control requires the
separately seeded historical runtime described in its evidence record. Its
missing fixture must remain visible in final qualification.

Follow-up: the historical runtime was present locally, so a fresh isolated
synthetic seed was created at `/tmp/ipse-literal-ab-resume-20261030` with the
native PTY assertion driver and the retained
`_build/retention-cli-final-switch-20261028/lib` graph. Its helper SHA-256 was
`113df584e83b7749a11a72509092cb9c2b32d6fdc3fcf91b0181335f5f8c2550`;
the seed log is `/tmp/ipse-literal-ab-resume-seed.log`. The current-source
consumer, using helper SHA-256
`e56867fef8c69cb5337ba8f1d316c77857cd10e2a9e9efd90ef9a9d8e49cc6d7`, passed
the selected literal-v4 control (one test, 117 excluded): the old literal read
remained in the inherited union, the independent current B quote succeeded,
and loss of A refused before any managed publication intent. This is local
upgrade evidence, not a portable fresh-checkout fixture or a full-suite run.

The native literal-output expiry test also reproduced a mixed-run failure on
current source: it assumed the last read observation was a version-4 literal,
but the later observation was version 3. Selecting the exact note revealed
multiple identical version-4 observations. The fixture now selects by version
and note key and requires one distinct dependency with the reviewed deadline.
The actual native PTY journey then passed, retaining its checks that expired
output is withheld, the release is recorded as withdrawn, and saved Session
reconstruction succeeds. The first adjusted run exposed the repeated
observations before this correction. This is one selected journey, not complete
managed-output qualification.

The selected current native setup and revocation journey passed (one test,
seven excluded). The old native retention component file still fails both
tests because its direct reviewed mutation lacks the now-required journal-owner
publication fence. The current journal-owned retention effect controls passed
four selected tests, covering the three policies, old and shorter new deadline
crossings, and writer loss before switch; 14 tests were excluded. This does not
restore every assertion in the old component file, which remains an open suite
failure. Three other gate tests expected the former blanket retention refusal;
they now check that unconfigured requests refuse without creating management
storage. The generic strict-deadline refusal assertion remains intact. Those
updated controls and the management-mode file passed seven tests together.

The older native retention component fixture now uses a native-header journal,
retained journal lock and writer, and the journal-owned retention publication
entry point. A dedicated synthetic middle lock supplies the required three-level
transaction shape; it is not a Consent ledger or proof of policy authority.
The original component assertions remain, including changed facts, stale
dependencies, recapture suppression and delayed old/new deadline switches.
Both tests passed on current source (32.9 seconds). The first migration attempts
failed on missing source-origin header metadata and then an invalid lock path;
the corrected fixture includes both. The separately tested real management
caller remains the evidence for actual Consent and terminal coordination.

The supersession display guard now uses a shared pre-input structural binding:
it validates the relation and current deadline, derives the exact source union,
and requires an active Session source before retaining owners. The existing
post-review source binding reuses the same check and still requires the exact
native review receipt. The signed-predecessor fixture checks matching pre/post
bindings, absent active source and elapsed deadline. Current compilation with
warnings as errors and the focused Review, journal, StoredSources and native
binding-only files passed 51 tests. The native supersession file ran only its
`binding-only` mode; this does not authorize display or publication and the
actual cross-process/native owner handoff remains open. A current-source
history-use Session run still refuses `/correct` at the closed intake gate.

Knowledge setup and plain status no longer say all protected note saving is
unavailable. Their notice distinguishes the narrow native-reviewed new-statement
path from broad saving readiness; the existing JSON readiness fields remain
conservative. The knowledge CLI file passed eight tests, including native setup
and readiness, and compilation and repository formatting checks passed. The
scripted demo also completed, using the operator configuration available in
this environment. Documentation links and rules passed. These checks do not
qualify complete capture or the remaining protected publication routes.

The complete current-source native assertion integration file ran 11 scenarios:
10 passed, including the save, retention and expiry cases. The history-expiry
scenario failed after its native correction review because its synthetic
supersession publication remained unconfirmed under the current fence. This
does not qualify correction or history expiry; retain the failure for the
supersession integration work. The local log is
`/tmp/ipse-assertion-resume.log`.

Eleven current-source P30 decision, transport, profile, Session, usage and
Knowledge policy test files passed 69 tests with the usual platform and
controlled-terminal exclusions. The log is `/tmp/ipse-p30-current-resume.log`.
These local fixtures do not establish live account access, installed-package
qualification, a qualified consumer or the P30D/E experiments.

The Session now has a private synthetic supersession-review ticket. It requires
the exact recorded pre-review intent, candidate and purpose, a current relation
and the Session's active source proof; its source set and relation are checked
again at Writer drain. The ticket selects the existing fixed-text synthetic
terminal, not protected facts. A real Session/Host fixture without a recorded
relation refused both ticket and Host opener (one test, 64 excluded); an
existing native Session/Writer switch and two journal controls also passed.
Compilation passed with warnings as errors. A genuine recorded-relation
positive, changed-relation and source/owner-loss schedules, cross-process lease
export, and real display remain unverified. The public supersession gates remain
closed.

Two additional real Session/Writer controls exercise the synthetic display
ticket's relation recheck with an actual active source. Trusted test
instrumentation inserts a display-relation binding without a matching recorded
relation: before the drain, the Session refuses without freezing the Writer;
after the Writer has been held and the drain started, it poisons the Session
before transfer. Both selected tests passed (65 excluded). These are negative
controls with injected state, not a genuine recorded-relation positive or
protected terminal display.

The fixed-text leased-terminal bridge now has a private supersession mode that
requests the Session's relation-bound synthetic ticket after validating held
inactive-source identities. A real Session/Host fixture with one active and two
inactive source owners but no recorded relation refused that request before
terminal display. The first test expected clean Session completion; actual
resource cleanup classified the refused bridge as unconfirmed, so the corrected
control checks the error and cleanup quarantine (one passed, 67 excluded). The
existing fixed-text active/inactive review still passed through the native PTY
(one passed, 67 excluded). Compilation passed with warnings as errors. This
does not supply a genuine relation, cross-process publisher export or protected
text; no public gate was opened.

The Session-owned synthetic review protocol now accepts zero inactive sources:
the four required Session and transaction leases remain mandatory, and other
grouped protocols retain their prior minimum. The Elixir source-identity check
also accepts an empty inactive set only when both proof and lease sets are empty.
A real Session with an active-only source passed the fixed-text PTY review; the
active-plus-two-inactive control passed again. Each selected run excluded 68
tests. The native lease matrix passed its one encompassing test, including
malformed manifests and owner-loss modes. The helper was rebuilt at SHA-256
`c6768890455697de64284463092806fa2e30305a7ea7b8e6ee60c625f3f0ccff`, and the
host was force-compiled with warnings as errors. These controls use synthetic
facts and do not qualify the supersession relation or protected display.

An adversarial active-only PTY control now sends an injected initial review
frame before the Session's fixed-text manifest and verifies that its private
marker never reaches the terminal. Test instrumentation records a receipt only
after the forged frame is accepted by the control pipe, so a pre-injection
failure cannot pass the assertion. That selected test passed (69 excluded).
The existing two-inactive-source injection control also passed after requiring
the same sent-frame receipt. These are synthetic-text controls, not proof of
protected-facts provenance or genuine supersession admission.

A controlled positive now appends a structurally valid synthetic relation intent
through the actual Session, using an active proof resolved by its Writer. The
pending purpose, candidate and predecessor values are trusted injected fixture
state; they are not a genuinely admitted `/correct` operation or a signed
predecessor. The relation-bound ticket froze and verified the active proof, and
the native terminal completed the fixed-text review (one test passed, 72
excluded). Separate controls passed ticket issuance and changed-relation refusal
during the held Writer drain (two tests, 71 excluded). The synthetic Session is
terminated by fixture cleanup; no Saved reconstruction or protected display is
claimed. Cross-process publisher-owned lease export and a genuine recorded
relation remain open.

The recorded synthetic-relation terminal fixture now also covers an active
Writer proof plus an independently retained original Session. A fixed-text PTY
review passed with both owners held. A separate interposition killed the
original source owner immediately before display; the bridge refused and the
PTY driver verified that the review text was not displayed. Each selected test
passed with the other tests excluded. The relation and predecessor values remain
injected test fixtures, and this same-process Host bridge does not establish
publisher-child lease export or genuine `/correct` admission.

A test-only coordinator proxy now exercises the recorded synthetic relation
across distinct Host and tracked file-effect processes. The effect owns the
three transaction locks and inactive original-source lease; the Host owns the
Session control and temporarily owns the terminal for Session manifest and thaw
calls. The actual source-union checks and native fixed-text PTY review passed
(one selected test, 75 excluded), and the fixture asserts the two BEAM owners
are distinct. This proxy is test-only and transfers the terminal cooperatively;
it is not wired to `ManagedSupersession.coordinate/3`, does not authenticate
protected facts, and has no coordinated owner-loss qualification. The pending
relation and predecessor are still injected fixtures. The log is
`/tmp/ipse-coordinated-review.log`.

The test-only coordinated proxy now has two pre-display owner-loss controls.
After all synthetic owners transfer, an interposition pauses before the native
display request; killing either the tracked publisher process or the inactive
original-source owner causes refusal, and the PTY driver rejects any displayed
review text. Both selected tests passed (76 excluded); the local log is
`/tmp/ipse-coordinated-review-loss.log`. These controls do not establish loss
behavior after display, after input, or during a real publication, and they do
not wire the proxy into production.

Two further test-only coordinated controls kill the tracked publisher or the
inactive source after fixed-text display while native input is held. Publisher
loss poisons the Session. Source loss does not immediately terminate the input:
the terminal has already completed its source-export settlement and monitors
the two control owners during input. After input is released, the retained
original-source callback refuses with `collection_source_refused`, and the
Session terminates without a successful coordinated result. Each selected test
passed separately with 79 excluded. An initial source-loss test incorrectly
expected immediate refusal and timed out; inspection found the publisher still
waiting for input, so the corrected test releases it and checks the later source
revalidation. This is synthetic fixed-text evidence, not a protected-display
or post-publication owner-loss guarantee. Logs:
`/tmp/ipse-coordinated-input-source.log` and
`/tmp/ipse-coordinated-input-publisher.log`.

An adversarial synthetic relation exposed a missing-owner defect: the relation
named an inactive original but the terminal manifest omitted it, and the
fixed-text review was displayed. The pre-repair PTY driver rejected that display
with exit status 91 (`/tmp/ipse-supersession-missing-owner-before.log`). The
Session now supplies a digest of the ordered inactive proof set to the private
bridge, which compares it to the proofs bound to its retained leases; the
Session also checks that its synthetic manifest contains the expected number of
distinct inactive Session owners. The omitted-owner and different-valid-owner
controls now refuse before display. A test-only interposition disabled the
bridge comparison and confirmed the Session's independent count check poisons
the attempt. Valid active-only, active-plus-original and coordinated fixed-text
reviews passed after the repair; compilation passed with warnings as errors.
This is an internal synthetic binding between trusted processes, not independent
native authentication of a proof-to-owner mapping or protected-facts delivery.

An additional interposition disabled the bridge's proof comparison and replaced
the relation's inactive original with a different valid owner. The Session's
count-only check accepted this equal-count substitution and the synthetic text
reached the PTY; the rejecting driver exited 91
(`/tmp/ipse-supersession-wrong-owner-before.log`).
The Writer barrier now records the device and inode of each expected inactive
session lock from the active journal directory, and the Session compares these
identities with the terminal manifest before accepting it. With the bridge
comparison still interposed, the same test now refuses before display and
poisons the Session (one passed, 81 excluded). Active-only, retained-original,
and two-process coordinated synthetic reviews each passed individually (one
passed, 81 excluded each). Focused Writer and Session regressions passed 19
tests with four excluded. A combined PTY invocation failed its second review
because the driver responds once per invocation; the affected test passed when
run alone. The lock-path identity is sampled at the Writer barrier; path changes
after that snapshot and protected-facts delivery have not been qualified. The
production supersession review gate remains closed.

The post-snapshot path risk is now reproduced. A test pauses immediately before
the synthetic terminal activation, renames the held inactive source lock and
creates another owner-only file at its original path. The reject-display driver
observed the fixed review text and exited 91
(`/tmp/ipse-review-replaced-lock-path.log`). With the regular PTY driver, the operation
did not report success (one selected test passed, 82 excluded), but that later
refusal cannot undo the display. A more specific assertion expecting a returned
`collection_source_refused` did not receive that message, so the test accepts
either an error response or Host termination and does not claim which cleanup
path occurred. No protected content was used. This remains an unresolved
pre-display authority gap; the snapshot alone is insufficient to qualify the
production gate.

The same interposition now additionally acquires the replacement lock with a
separate native source-lock helper before allowing activation. Acquisition
succeeds while the displaced original is still retained, and the reject-display
driver again observes synthetic text (exit 91,
`/tmp/ipse-review-replaced-contender-reject.log`). The regular driver run
passes the subsequent refusal/Host-termination and contender-cleanup control
(one passed, 82 excluded). This demonstrates distinct lock domains after path
replacement; it does not demonstrate a successful competing journal mutation.
A complete fix must establish a stable authority for the pathname throughout the
guarded display, including its ordering against a concurrent replacement, or
explicitly restrict and enforce the threat model. A last-moment stat alone still
leaves a check-to-write race and is not treated as qualification.

The earlier mixed-source full run's clean-VM evaluation group was rerun on the
current worktree. The entire child group passed 25 tests with two excluded;
its outer isolation test passed with two excluded (seed 605812, child duration
286.6 seconds; `/tmp/ipse-evaluation-isolation-current.log`). The suppressed
lexical case also passed separately (one test, 26 excluded). These results do
not explain the earlier incomplete measurements, cover the excluded source and
answer-contract groups, or replace a current fixed-source full-suite baseline.

One representative old Collection Session failure was rerun on the current
worktree: `mix test test/ipse/extension/collection_call_session_test.exs:590`
still fails (zero passed, one failed, 13 excluded;
`/tmp/ipse-collection-publication-gate-current.log`). The SDK2 protected-output
test expects successful publication; the Session reports the strict deadline
fence unavailable instead. The legacy `CollectionCall` path still enters the
closed strict deadline gate, while the managed new-capture path has a separately
scoped final-decision admission. This observation neither qualifies that narrower
path for the SDK2 test nor justifies disabling the gate. The reproduced native
clock-to-rename scheduling counterexample and required authority remain in the
[strict deadline record](strict-deadline-interposition.md).

A current-worktree nine-file P30 regression covering decision contracts, usage,
provider transport, extension capability/Session/calls, configuration and the
pure Knowledge policy passed 57 tests (`/tmp/ipse-p30-current-regression.log`).
It uses synthetic fixtures and does not qualify a protected consumer, a live
engine, the bounded experiments or an installed release.

Current Knowledge recall and Session fixture tests passed together: five outer
tests, including the independent worker's 17-test recall suite
(`/tmp/ipse-notes-recall-current.log`). The recall worker groups note parts into
JSON context assertions and adds index and coverage assertions, then measures
the complete envelope through `Ipse.Extension.context_rendered_bytes/2`. The
pure decision planner instead accepts caller-supplied concatenable rendered
chunks and an already-deducted allocation. Copying raw note text into those
facts would not establish the real rendered budget or source eligibility. An
integrated experiment must derive alternatives from the actual eligible read
set and measure each complete candidate projection with the same context
renderer, while preserving generation/source checks and separate experiment
permission. This is an integration requirement, not evidence that such an
adapter or an actual-input experiment exists.

The Knowledge worker now shares its actual recall projection with an internal,
pure `recall_projection/4` helper. It only accepts ordered subsets of the
supplied read rows and calculates the full grouped context envelope; unknown,
duplicated or reordered selections refuse, and an over-eight-item projection
reports no valid byte measurement. The ordinary greedy recall path uses the same
helper. A child-worker control compares the complete projection with its actual
published items, exercises subsets, Unicode, the real budget, invalid members
and overlarge groups. Recall, Session and pure decision tests passed 20 outer
tests (including 18 recall-child tests); the later overflow control and four
build-spec tests passed. `mix compile --warnings-as-errors` passed after retrying
outside the Mix loopback restriction, and formatting passed. The helper trusts
its supplied context; it is not a host source proof, egress authorization, actual
main-tool experiment, or qualified decision consumer.

The `knowledge/native` artifact was also built against the current test SDK and
its independently loaded recall worker passed the same 18-test child suite (one
outer test; `/tmp/ipse-recall-projection-artifact-test.log`). This is a local
artifact control, not an installed-runtime or quality qualification.

The pure projection now also refuses duplicate keys in its supplied read set.
A bounded `recall_pack_projections/4` measures up to eight named alternatives
over at most four read rows each, canonicalizing members to recall order and
refusing unknown or duplicate members, duplicate IDs and permutation-only sets.
The same actual renderer supplies each byte count and fit result. The focused
recall/Session/policy run passed 20 outer tests, including the 18-test worker
suite (`/tmp/ipse-recall-pack-projections.log`); a separately built
`knowledge/native` artifact passed the worker suite
(`/tmp/ipse-pack-projection-artifact-test.log`). The supplied rows and budget
remain untrusted for permission purposes, and the helper performs no engine
call. Connecting these projections to real main-tool input, host source
revalidation and a separately granted experiment remains open.

The pure notes-selection planner now also accepts version-2 facts with a
complete measured byte count per alternative and an optional full-set measure.
It filters whole projections rather than adding note-text lengths; a missing
measurement never establishes fit. Duplicate sets refuse, production remains
zero-call, and existing result validation and tamper reconstruction still apply.
The worker's `recall_decision_facts/7` derives this bounded data and a private
decision-ID-to-note-key mapping from a fully read and generation-checked recall
fixture. It refuses incomplete coverage and invalid/oversized facts. Focused
recall/Session/policy/neutral tests passed 26 outer tests, including the
18-test worker suite (`/tmp/ipse-real-projection-planner-final.log`); an actual
independent `knowledge/native` artifact passed that worker suite
(`/tmp/ipse-projected-planner-artifact.log`). The fixture does not establish
host source authority or separately granted live experiment consent. Actual
main-tool integration, freshness at use, dispatch and evaluation remain open.

An adversarial policy control found that both selection-facts versions rejected
a complete fitting set when multiple packs existed but no baseline pack was
named. The planner computed the baseline before recognizing the full-set bypass
(`/tmp/ipse-fitting-no-baseline-before.log`). It now permits that case and
produces the complete zero-call selection; unavailable or incomplete eligibility
also returns its explicit null baseline without requiring an irrelevant pack.
The policy, neutral-decision and synthetic Session controls passed after the
repair. The Session fixture additionally checks a version-2 fitting set with no
baseline and verifies zero decision egress and no request admission. This is a
synthetic Session control, not current-source or live experiment qualification.

Version-2 recall facts now bind the supplied generation, metadata index, record
identities, read-operation IDs and instance by canonical digest. The pure
`recall_decision_projection/5` reconstructs facts and the ID-to-key map, applies
the existing advice validator or baseline, and remeasures the selected subset.
Worker controls cover a selected pack, malformed-advice fallback, changed read
receipt, generation, index and ID mapping, and incomplete verification. The
recall, decision-policy and synthetic Session suite passed
(`/tmp/ipse-recall-advice-revalidation-final.log`), and a newly built
`knowledge/native` artifact passed its independent worker suite
(`/tmp/ipse-advice-revalidation-artifact.log`). These are local consistency
checks: worker state can be fabricated, and no host source lock or freshness is
reacquired by this helper. No experiment dispatch or protected output is enabled.

The 32-note worker fixture also builds a bound fact set with the planner's
16-candidate limit and checks that it makes no request or unsupported full-set
selection. Its first assertion assumed the complete projection would fit the
smaller 6144-byte decision allocation; it did not. The corrected control
derives the expected refusal reason from the measured envelope and passes
(`/tmp/ipse-recall-32-binding.log`).

The existing real Collection cursor fixture now also drives the recall worker
through actual native Collection index and record observations, builds measured
decision facts and reprojects synthetic advice. After a second operation changes
the Collection, a fresh index confirms generation 2 while the retained worker
context is still generation 1. The pure reprojection nevertheless accepts that
unchanged historical context, as expected for a function without live storage
authority. The worker suite passed (`/tmp/ipse-real-collection-projection-current.log`).
The fixture supplies synthetic read-operation IDs and calls the worker directly;
it is not a Session egress or protected source test. This counterexample confirms
that a live host root/source guard is necessary before dispatch and before use,
not merely reconstruction of the worker's earlier digest.

An actual Session control now exercises the existing managed preflight for a
decision helper after a synthetic Collection snapshot read. With the current
root, the selected local SystemOne-compatible endpoint receives the request,
the journal contains a nonempty managed dependency preflight, dispatch and a
successful decision result, and Saved reconstruction succeeds. A paired test
holds Session at `decision.create` preflight, changes the Collection root,
and observes the managed read and decision action intent but no decision
dispatch or third provider request; Saved reconstruction also succeeds. The
current text and decision helper controls passed together (two passed, 118
excluded, `/tmp/ipse-managed-helpers-positive.log`); the stale decision control
passed separately (one passed, 119 excluded,
`/tmp/ipse-managed-decision-stale.log`). These are synthetic snapshot inputs,
not protected note-pack adapter integration or a qualified experiment. They
establish neither mid-send revocation nor an independent source-lock mapping.

Additional actual Session controls hold a valid local decision response after
request dispatch. With the synthetic root unchanged, the worker receives the
`relevant` advice and the journal records success. Changing the root before
the response is released prevents both worker receipt of that marker and a
successful decision action result; revoking the saved policy at the same
boundary does likewise. All three journals reconstruct. The current/root-change
pair passed two tests (`/tmp/ipse-managed-decision-response-pair.log`), and the
revocation case passed separately (`/tmp/ipse-managed-decision-response-revoke.log`).
The request was already sent in both negative cases; these controls qualify
response withholding for a synthetic snapshot dependency, not zero egress,
protected note-pack integration or live model quality.

The decision preflight now has actual Session controls for a specific recorded
literal, beyond the synthetic root-only snapshot. Separate fresh synthetic
historical seeds were created through the retained pre-gate runtime and native
PTY; fixture setup explicitly replaces consent for the test artifact. With its
original journal current, the Session records the note's version-4 dependency
and sends its synthetic text to the selected loopback decision endpoint. When
the original source journal is renamed after the read but before decision
preflight, the Session records the dependency and decision intent, but no
decision dispatch or provider request. The test restores the journal and checks
its original SHA-256. Each strengthened fresh-seed control passed one test
with 124 excluded (`/tmp/ipse-managed-literal-decision-positive-fresh.log` and
`/tmp/ipse-managed-literal-decision-refusal-fresh.log`). Reusing the first
already-consumed seed for a strengthened positive timed out waiting for a
provider request; it was replaced by a fresh-seed run, without asserting its
cause. These are local synthetic, historical-upgrade controls, not an installed
journey, decision-pack integration, mid-send source-loss test or live model
qualification. The original publication and display gates remain in force.

Two further real Session controls use separate fresh historical literal seeds
and hold the local decision response after its request is observed. With the
original source current, the synthetic note reaches the local endpoint and
the worker receives the valid advice. In the paired case, the fixture renames
the original journal after request dispatch and before releasing the response;
the worker does not receive the advice marker and the journal contains no
successful decision action. The version-4 dependency and dispatch intent are
present, Saved reconstruction passes, and the original journal is restored and
hash-checked. Each control passed one test with the remaining tests excluded
(`/tmp/ipse-literal-held-current.log` and `/tmp/ipse-literal-held-lost.log`).
The note has already left the process before the negative interposition; this
is response withholding for one synthetic source, not a no-egress or complete
multi-source/owner-loss guarantee.

A test-only shadow worker now connects the measured pack planner to actual
Session-managed reads of two separately reviewed synthetic literal records. It
indexes, reads both records, checks the generation again, derives complete
projection measurements, calls the selected local decision endpoint and
reprojects the returned choice. The Session journal records both version-4
dependencies and the decision result; the test checks that no Collection or
State publication was requested. In a paired fresh-seed control, withdrawing
their original journal before decision preflight leaves both recorded
dependencies and the action intent but prevents decision dispatch and worker
reprojection; the source journal is restored and hash-checked. The current and
withdrawn cases each passed one test with 128 excluded. A strengthened current
control also checks ordinary Collection commits and State deletion
(`/tmp/ipse-pair-final-check.log`); the stale run is
`/tmp/ipse-pair-runner-stale.log`.

`test/support/managed_literal_pair_runner.exs` creates the two-note seed in a
new directory using an explicitly supplied retained historical runtime. For
example, in an environment where that runtime is present:

```sh
elixir test/support/managed_literal_pair_runner.exs /tmp/ipse-new-pair-fixture \
  _build/retention-cli-final-switch-20261028/lib
IPSE_LITERAL_AB_ROOT=/tmp/ipse-new-pair-fixture IPSE_TEST_MANAGED_PACK=1 \
  mix test test/ipse/extension/managed_collection_call_session_test.exs --only managed_pack_decision
```

Use a fresh directory and seed for each selected control; the stale variant is
`managed_pack_decision_stale`. The runner is not a portable fresh-checkout
fixture because its historical runtime is not part of the current build. The
fixture supplies its own query and deliberately small calculated allocation,
uses two notes from one original Session and explicitly replaces consent for
the test artifact. It is not evidence of a real user workload, the host's
actual shared-context allocation, separate finite-experiment consent,
independent source owners, quality benefit or an enabled production consumer.

Version-2 projection facts now accept up to the recall worker's 8192-byte
ceiling; version-1 concatenable-chunk facts retain their 6144-byte limit. A
test-only Session worker obtains `context.available` and uses the actual lesser
of that available amount and the recall ceiling. Two fitting synthetic notes
produce a complete zero-call bypass (`/tmp/ipse-actual-budget-bypass.log`). A
separate fresh seed contains eight long reviewed literals. Their complete
projection does not fit the actual allocation, while two measured alternatives
do; the worker sends a shadow decision to the local fixture and reprojects its
response without a Collection or State mutation. That actual-budget overflow
control passed (`/tmp/ipse-wide-budget-retry.log`). The initial attempt timed
out in the fixture's five-second provider accept while the worker was still
reading notes; the retry uses an explicit 30-second fixture wait. A second
fresh wide seed withdraws the original journal before decision preflight: all
eight version-4 dependencies and the decision intent are recorded, with no
decision dispatch, and the source is restored and hash-checked
(`/tmp/ipse-wide-budget-stale.log`). Each selected Session control passed one
test with other cases excluded; policy/recall controls passed 18 outer tests.

The wide seed is reproducible with `managed_literal_pair_runner.exs` by adding
the final `wide` argument and selecting `managed_pack_actual_overflow` or
`managed_pack_actual_overflow_stale` with a fresh seed each time. These are
test-only artifacts and a synthetic query, all notes share one original source,
and the configured approval is not a separate finite-experiment grant. The
controls do not qualify the production consumer, live model quality, actual
user workload or multi-owner source loss.

The wide test-only worker now gets its query from the current Session's
`source.list` and `source.read` results before it requests the actual context
allocation. The positive control verifies the synthetic prompt in the local
decision request and both source-read action results in the journal
(`/tmp/ipse-wide-source-query.log`). The paired withdrawal control verifies the
current prompt in the journaled decision intent and still records no dispatch
after source loss (`/tmp/ipse-wide-source-stale.log`). Each passed one selected
test. This exercises an actual Session input and budget in a synthetic fixture;
it is not the frozen human workload, a separately granted finite experiment,
independent source owners or a production note-selection route.

The wide seed runner now accepts `split`: it creates four synthetic reviewed
notes in each of two separately closed original Sessions and verifies both
source proofs and journal hashes. With that seed, the actual-budget shadow
control passed and observed all eight version-4 dependencies
(`/tmp/ipse-split-source-positive.log`). Separate fresh split seeds withdrew
the first and second original journals in turn before decision preflight; both
controls recorded the decision intent and all eight dependencies, dispatched no
decision, restored the removed journal and verified both original hashes
(`/tmp/ipse-split-first-stale.log`, `/tmp/ipse-split-second-stale.log`). Each
selected case passed one test. The second-source run sets
`IPSE_TEST_SOURCE_INDEX=1`; the default selects the first. The existing
single-note and pair seed modes also passed after the fixture refactor.
This proves the stated preflight withdrawal cases for two historical sources;
it does not prove concurrent owner death, loss during send, or user-workload
quality and does not grant a production experiment.

The split-source worker now also has held-response Session controls. The
current-source case sends the actual synthetic Session query to the local
decision endpoint and reprojects its accepted response. In two fresh-seed
negative cases, the fixture withdraws the first or second original journal
after the request arrives but before the response is released. Both record all
eight version-4 dependencies and a decision dispatch, but neither delivers a
successful decision result or the worker reprojection marker; both journals are
restored and hash-checked. Saved reconstruction passes in all three cases.
Each selected control passed one test (`/tmp/ipse-split-held-check-current.log`,
`/tmp/ipse-split-held-check0.log`, `/tmp/ipse-split-held-check1.log`). The
request had already left the process in the negative cases. This is response
withholding under synthetic source withdrawal, not no-egress, native-owner death,
or a production experiment qualification.

An interactive-approval attempt on a fresh split-source fixture exposed the
existing managed-display gate: the Session refuses to display protected approval
arguments without its current-source output fence. The corrected control checks
the refusal, all eight observed version-4 dependencies, no approval event, no
decision dispatch or admission, no reprojection, and successful Saved
reconstruction. It passed one selected test with 134 excluded
(`/tmp/ipse-refused-pack-test.log`). The initial test expecting an interactive
approval timed out because the gate had correctly refused
(`/tmp/ipse-denied-pack-test.log`). This does not test an operator denial; that
case remains open until managed approval display is safely available.

## Managed approval restoration investigation

The current refusal has two independent guards. `Session.Invocation` refuses a
managed question or interactive mutation before the ordinary approval branch
records a wait or sends the full proposal to the subscriber. Its `approve/5`
also denies a managed invocation even if an approval were somehow queued.
Removing only the first guard would therefore both expose the proposal through
`Session.notify/2` without the source display fence and still deny the action;
removing both would bypass that fence altogether. The ordinary CLI receives
the full proposal, creates its own token, and renders the escaped complete
arguments through its regular input reader. Passing that message to the CLI is
already disclosure, before any later display check.

The later Session-owned synthetic review machinery improves on the older
private bridge: the Session selects the fixed-text helper and verifies the
manifest and control notices. It still handles synthetic text, not the actual
approval proposal, and the separately reproduced post-snapshot source-lock
pathname replacement can allow even that fixed text to be displayed. It does
not establish an authenticated current-source display for the two-source
decision. The native approval path must bind the exact escaped proposal,
destination and execution facts, all current source and Consent owners, the
specific terminal and an operation-bound one-use input receipt; after input it
must reacquire and revalidate authority at effect entry. The snapshot/path race,
owner loss, expiry, terminal failure and no-replay outcomes need adversarial
controls. These are implementation requirements inferred from the current
boundaries, not a reviewed protocol or authorization to open either guard.

The recall worker's ordered engine-free greedy selection is now exposed as the
pure `recall_baseline_projection/3` and used by ordinary recall itself. Focused
controls compare it to actual published items for 32 fitting notes and for an
oversized first note followed by two fitting notes. Recall and decision-policy
tests passed 18 outer tests (`/tmp/ipse-recall-baseline-new3.log`); the separately
built Knowledge artifact passed the recall worker suite in its independent VM
(`/tmp/ipse-baseline-artifact-test.log`). The initial 1500-byte edge fixture
could not fit even the short-note framing; the passing case uses 2500 bytes.
The existing shadow fixture still supplies an artificial one-note baseline and
does not compare against this engine-free selection. In particular, the greedy
baseline may exceed the decision policy's four-record pack limit. A faithful
experiment needs an explicit representation and comparison for that baseline;
this refactor alone neither supplies one nor changes experiment authorization.

The pure `recall_shadow_comparison/5` now pairs the full greedy projection with
reconstructed advice without forcing the baseline into a four-record pack. It
exposes a shadow projection only on a selected answer, preserving malformed
advice as no shadow selection instead of presenting the policy's artificial
fallback pack as ordinary recall. A worker fixture with eight synthetic notes
compares an actual publication containing more than four notes to four-note
decision packs, checks malformed advice and rejects a changed generation. The
first attempt with 970-byte notes included only four under its actual budget;
the passing pure fixture uses 700-byte notes. Recall and policy tests passed 18
outer tests (`/tmp/ipse-recall-shadow-comparison-v2.log`), and the separately
built Knowledge artifact passed its recall suite
(`/tmp/ipse-shadow-compare-artifact.log`).

The test-only two-source Session worker also computes this comparison after
successful shadow advice and checks its baseline fits. One fresh split-source
synthetic control passed (`/tmp/ipse-shadow-compare-session.log`); its trace
records only the included-note count, not note content. This demonstrates the
comparison on the synthetic Session input and actual reported allocation, not
quality benefit, human workload coverage, separately granted experiment
consent, protected display, or production consumer admission. The policy's
fallback action itself still names its configured pack; a future live adapter
must use the real baseline on failure and must not mistake that pack for it.

The comparison now returns the ordinary publication explicitly, sharing the
same conversion used by the recall worker. The control checks it against actual
published items and verifies that both malformed advice and an explicit valid
refusal retain the full ordinary result while exposing no shadow selection. A
zero-allocation control also revealed that decision reconstruction rejected an
empty selection when the empty-note coverage framing did not fit. The mapper
now represents that case as zero added bytes: publishing no items removes the
publisher. It does not claim that the original coverage frame fits. The focused
recall and policy suite passed 18 outer tests
(`/tmp/ipse-shadow-ordinary-fallback.log`), and the independently built Knowledge
artifact passed the worker suite (`/tmp/ipse-ordinary-fallback-artifact.log`).
No production consumer or additional authority is enabled.

The split-source Session fixture now also sends a valid low-confidence System
One response through the actual local decision adapter. The test-only worker
records `low_probability`, compares the ordinary baseline, exposes no shadow
selection and returns no chosen pack; it does not publish that baseline. All
eight original-source dependencies are observed, no Collection, State or
context mutation is requested, and Saved reconstruction succeeds. A fresh
selected-advice control still passes after the fixture change. Each selected
case passed separately with fresh split seeds
(`/tmp/ipse-final-managed_pack_low_confidence.log` and
`/tmp/ipse-final-managed_pack_actual_overflow.log`). The selected test uses
programmatic fixture approval, not finite-experiment consent or protected
interactive approval. System One's adapter has no per-question refusal shape;
explicit refusal is covered by pure mapping tests, not this Session control.

The pure policy now maps closed host failure outcomes separately from model
advice: denial, unknown, response, timeout, cancellation, request failure and
limit retain distinct receipt reasons, while invalid shapes and changed facts
refuse. The shadow failure adapter reconstructs the bound facts and returns the
ordinary baseline without a shadow choice. Focused recall and policy tests passed
18 outer tests (`/tmp/ipse-shadow-failure-mapping.log`), and a fresh independent
artifact passed the recall worker suite (`/tmp/ipse-shadow-failure-artifact.log`).

A fresh synthetic two-source Session sent an out-of-range System One response.
The actual host reported `decision_request_failed`, left its inference service
reservation unknown and stopped the turn before any third HTTP request. The
test-only worker recorded that exact class and no shadow selection; no decision
response event was recorded and Saved reconstruction passed
(`/tmp/ipse-malformed-session-v2-test.log`). The first test incorrectly expected
`decision_response` and clean continuation; its failure is retained at
`/tmp/ipse-malformed-session-test.log`. The current path therefore does **not**
demonstrate a host-level malformed-response versus request-failure distinction,
which remains open for P30 acceptance. The pure mapping distinguishes only the
class the host actually supplies; it does not authorize use after source loss or
replay an unknown request.

The subsequent repair preserves the parser's `invalid_decision_response` after
confirmed controlled-child cleanup while leaving the native completion witness
false. The registered dispatch carries that diagnostic with the unknown service
outcome; Session records `decision_response` and a failed partial completion,
without admitting advice or settling the service reservation. Replay accepts
that failure code for a failed partial decision completion, but has no retained
invalid body with which to independently verify the diagnosis. Ordinary
unregistered decision calls also preserve the parser error.

The fresh two-source control checks the error diagnostic, unknown-service notice,
failed/partial journal completion, no response event, no third HTTP request and
Saved reconstruction (`/tmp/ipse-malformed-repair-final-test.log`). An
ordinary Session regression checks the failure code for wrong-model and invalid
distribution replies (`/tmp/ipse-decision-response-unregistered.log`); the
decision Session, transport, owned-effect and dispatch files passed 38 tests
before the additional assertion (`/tmp/ipse-decision-malformed-regression.log`).
This is a focused local repair, not full transport/loss qualification, live
account acceptance or a completed P30 audit.

A separate real loopback socket-disconnect control now verifies that a lost
decision connection is still `decision_request_failed`, with no decision
response, failed partial accounting, valid Usage/Actions restoration and no
automatic second request. The complete decision Session file passed
(`/tmp/ipse-decision-disconnect-control.log`). A fresh split-source malformed
response case also closes and reopens the saved Session while the fixture
listener remains active; the reopened Session is idle and sends no request
(`/tmp/ipse-malformed-resume-test.log`). These controls distinguish the two
observed local paths but do not independently authenticate discarded response
bytes on replay or qualify all managed transport failures.

Two further split-source Session controls held a malformed decision response,
then temporarily withdrew the first or second original journal before releasing
the response. Both observed all eight version-4 dependencies, no decision
response event or context publication, and no subsequent provider request.
The Session journal retained the worker's fixed diagnostic result, but the
subscriber received only the fixed `managed_dependencies_unavailable` withheld
receipt; Saved reconstruction passed and both source hashes were restored and
checked. Each case passed with a fresh seed
(`/tmp/ipse-malformed-source-0-test.log` and
`/tmp/ipse-malformed-source-1-test.log`). The request had already been sent.
Two initial assertions were too strong: the first expected no historical worker
result in the journal (`/tmp/ipse-malformed-lost-test.log`), and the second
expected no subscriber receipt at all (`/tmp/ipse-malformed-lost-v2-test.log`).
These controls verify the stated synthetic withdrawal and fixed receipt, not
owner death, every possible output sink or production experiment admission.

The decision Session file now includes a one-request shared-budget control for
malformed output: partial liability remains, the idle resumed Session sends no
replay and a further explicit attempt cannot dispatch under the exhausted cap.
Fourteen tests passed (`/tmp/ipse-malformed-shared-budget.log`). This is the
ordinary shared budget, not the separate finite P30 experiment grant.

A new pure developer scoring primitive compares selection aggregates against
the frozen supported-answer, cost, critical recall, citation and p95 latency
thresholds. It uses integer arithmetic, rejects malformed or mismatched counts,
and reports incomplete evidence as unverified before assigning an evaluated
disposition. Four focused tests passed (`/tmp/ipse-decision-metrics.log`). Its
gate statuses and inputs are supplied by the caller: it does not validate the
underlying workload, reviewer independence, accounting, protocol gates or
identity freeze, and `useful_candidate` is not qualification. Candidate-assessment
metrics were subsequently added for false-durable reduction, useful and critical
capture and latency, including an explicit finite-cost-cap gate. Five focused
tests across both consumers passed (`/tmp/ipse-decision-metrics-both.log`).
Real frozen inputs, experiment consent, evaluation orchestration and P30D/E
acceptance remain open.

The scorer's follow-up audit found that the selection input did not explicitly
require a finite-resources gate and neither comparison reported abstentions.
Both now require bounded abstention counts and report baseline and candidate
counts with their common denominator; selection additionally requires an
explicit finite-resources gate, and reports all caller-supplied gate details.
Five focused tests passed (`/tmp/ipse-decision-metrics-abstention.log`). The
counts and gate statuses are still untrusted caller inputs, not verified evidence
or a replacement for the separate experiment grant.

Aggregate critical-recall counts can hide a lost critical query when a different
query improves. Selection now requires a separate paired-critical gate, and a
pure `critical_pairs/3` helper reuses the existing paired-metrics validation to
report individual lost query IDs. Missing, failed or unmeasured critical pairs
leave the gate unverified. The synthetic swapped-outcome control demonstrates
equal aggregate recall with a paired loss and a resulting rejection; duplicate
IDs and invalid values refuse (`/tmp/ipse-decision-critical-pairs.log`, six
focused tests). Pair identity, applicability and review labels are still
caller-supplied, and this does not establish an actual frozen evaluation.
The existing evaluation scoring file and new decision scoring file passed 28
tests together (`/tmp/ipse-decision-score-regression.log`).

An opt-in integrated fixture now connects an actual Session's synthetic
main-model tool calls to the private native pending-acceptance continuation.
The Session captures two unattended-input proposals under programmatically
installed test consent, closes and resumes, then closes again. The real PTY
review accepts the first signed pending record; the test checks the exact
original source proof and text in the acceptance event and confirms that the
pending row is gone while its acceptance link and accepted-decision note exist.
The management helper also checks the committed journal and receipt. The
selected test passed (`/tmp/ipse-genuine-pending-acceptance-final.log`), and the
two ordinary capture controls passed (`/tmp/ipse-pending-capture-regression.log`).

This fixture uses a synthetic model, programmatic policy installation and the
installed local Knowledge bundle; it does not expose a public acceptance command
or qualify later accepted-note use. An exact manifest check against a newly built
artifact failed (`/tmp/ipse-genuine-pending-acceptance-artifact.log`): the
installed bundle digest differed from that fresh build. The successful journey
therefore does not establish that the fresh current-source artifact was used;
no claim is made that the differing digests identify a behavioral difference.
Current-artifact reproduction, real provider behavior, public caller review,
additional loss/expiry cases and integrated P31E acceptance remain open.

The integrated fixture was subsequently rerun in a copied temporary runtime.
Only inside that isolated runtime, it stages the freshly built Knowledge
artifact and a matching bundle catalog, verifies the selected manifest digest,
and then performs the same Session capture and private native acceptance. One
selected test passed (`/tmp/ipse-genuine-pending-current-artifact.log`); the
two ordinary capture controls passed separately
(`/tmp/ipse-fresh-acceptance-capture-regression.log`). The retained temporary
bundle manifest SHA-256 is
`93d25ab6ab63d6a7bb696b15b0a41abe0c2224178df15e983229617605e90ec3`;
the Knowledge source file was `f635d331e9de6f7d439510fef470961c06829c72b5bc157e2e027f2c66e3152e`
when checked. The copied host runtime is not a frozen whole-source build, and
the fixture still uses synthetic model calls, programmatic consent and a
private continuation. Public acceptance, live-model behavior, additional
adversarial controls and full P31E qualification remain open.

The fresh-artifact Session fixture now also cancels native review of the first
model-produced proposal and verifies its exact Collection record is unchanged
before accepting it. A subsequent duplicate attempt refuses without displaying
another card or changing the acceptance link. For the second Session-produced
proposal, the fixture pauses native input after display, revokes the saved test
consent, and then releases input. The continuation refuses, leaves the exact
pending record unchanged, creates no acceptance link, and records no acceptance
event or effect intent. This combined private synthetic journey passed in a
temporary current-artifact runtime (`/tmp/ipse-pending-session-revocation.log`);
the ordinary capture controls passed separately
(`/tmp/ipse-pending-session-revocation-regression.log`). The revocation and
policy are test-programmatic; this does not open the public acceptance path or
qualify native owner loss and source-path replacement at display.

An isolated test-hooked native helper now pauses the actual private pending-card
reader immediately before its first write. The input is a proposal captured by
the synthetic main-model Session with the freshly built Knowledge artifact. The
control renames that proposal's original Session lock file, creates and acquires
an independent replacement lock, and resumes the reader. The native card and
synthetic proposal text appeared despite the replacement; the later private
acceptance refused without an acceptance event or effect intent. The safe-display
assertion intentionally fails (`/tmp/ipse-pending-path-swap-test.log`, zero
passed and one failed). It restores the original lock pathname after the test.

This extends the earlier fixed-marker supersession counterexample to actual
pending-card content. The retained instrumented helper SHA-256 is
`2e74f6a85cd4317acd647413472cff55820aedd35bfcb5f227baaab860f75378`;
its extra PID marker exists only under `ipse_terminal_display_test_hook`. The
ordinary helper compiled separately with warnings denied, and the normal
installed-bundle positive/cancel/revocation journey passed
(`/tmp/ipse-pending-path-swap-positive-regression.log`). A pre-write pathname
check alone cannot close the concurrent check-to-write race. The public
acceptance gate must stay closed until source ownership and actual display have
a reviewed, enforceable shared boundary. The fixture and card are synthetic;
this is not evidence of disclosure of a user's private data.

On the available Linux `7.2.11-arch1-1` x86-64 host, a separate disposable
tmpfs probe acquired an exclusive `flock` and write file lease on the original
lock, then used another process to rename it and acquire an exclusive lock on
a replacement. `F_GETLEASE` still reported the original write lease after the
replacement. The retained [probe](../../../dev/fixtures/source_lock_lease_probe.rs)
compiled with warnings denied and printed
`replacement_lock_acquired_while_original_was_leased`. This rules out a regular
file lease alone as a repair for the observed pathname replacement on this
host; it is not a portability or complete kernel-security proof.

The Linux manual describes [file leases](https://man7.org/linux/man-pages/man2/F_SETLEASE.2const.html)
as associated with an open file description, and [fanotify](https://man7.org/linux/man-pages/man7/fanotify.7.html)
describes rename as a notification rather than a permission event. Those API
descriptions and the local interposition do not establish that a userspace
notification plus a later check can prevent a concurrent rename and terminal
write. A repair must identify an enforceable boundary and its supported threat
model; the public acceptance gate remains closed.

The [2026-10-31 boundary correction](pending-review-boundary-20261031.md)
supersedes the source-path display blocker above. The original baseline requires
fresh source verification before publication, while signed pending review can
faithfully display historical data without asserting current source eligibility.
The failed pre-write control and file-lease probe remain historical evidence of
the stronger guarantee that was attempted; they are not a requirement to add a
new native protocol. Public acceptance qualification remains open for the
separate caller and integrated checks recorded in the current plan.
