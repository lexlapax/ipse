# Notes v3 admission, own absence reads and genuine intake — implementation review

Scoped read-only review, 2026-10-29, against the accepted
[notes contract direction](notes-publication-restoration-independent-review.md)
and [root-prerequisite direction](remember-publication-prerequisite-independent-review.md).
The [plan](../../plan.md) owns completion.

Disposition: accept the implemented new-v3-capture and own-root prerequisite
slice within the evidence below. No concrete blocking source defect was found.
This does not qualify every automatic source, top-level `/remember` CLI behavior,
source/owner/revocation race or later-use output/inference boundary.

## Exact source and evidence reviewed

The reviewed current worktree bytes match all seven production overlays in the
[genuine Session positive](remember-publication-absence-integration.md). The
[exact SHA-256 list](notes-publication-implementation-review/source.sha256)
enumerates those owners and all three requested current tests. The production
hashes are:

| Owner | SHA-256 |
| --- | --- |
| Collection | `8115f10d5c251261bf2aaa2e2aa4e6202934724c113850d1f41803e6fd622a56` |
| DocumentStage | `c5db55b3c3f95fb2dd097cdbdd02b769b6043633ce7bcaafff3f0788e9e12652` |
| ManagedCollectionCall | `d8fd728e2beecbaba51cf2a3e7cf6f8a7fb6f3758b8acb0a03577c9801e4bb5b` |
| Session | `d1c235fe3fb12b9434f15e743477f1a4cfeae334af1204d656241f0b8ca96d9e` |
| Session.Invocation | `5731b150a41f085256639955003bb0514ed1cff81d05390fd3b2d979264c5599` |
| ManagedReads | `89f6c6ec82fcf371ef7f6a69f8b90d55cd41e10786cae5c17057aaa10aded04c` |
| ManagedToolUse | `48b6185e29f7c361da73eb2803065f37120bf22beec31202adf1cad27c9a75dc` |

Independently verified the now-durable
[admission manifest](notes-publication-admission/manifest.json), SHA-256
`af4274dbf884df9c4912d564ad0307559f526e58fa3dcc3b78f9844546b7ed59`,
and [prerequisite manifest](notes-publication-prerequisites/manifest.json), SHA-256
`ae6c379a3e297ee63ea6dda1e50ea82ec2bd22d6b962ba90ae4e66cf834edf5b`.
Checked all 12 admission source/test/helper snapshots and 12 retained files,
three prerequisite sources/tests and five retained files, ancestor manifests,
and every regular file/symlink in each named runtime/private-asset inventory.
Each runtime has 707 physical regular files and two recorded symlinks.

Admission changes exactly Collection, ManagedCollectionCall, Invocation and the
separately accepted DocumentStage value-reader BEAM. Prerequisites change exactly
ManagedReads and ManagedToolUse. The positive graph equals the prerequisite
candidate across all 709 inventoried nodes. Its 668 compiled-runtime entries and
seven retained BEAMs match; relative to the original failed control only the two
prerequisite BEAMs change. Verified positive manifest
`71b910e85daa9a4dd2c667f8af2e4a8d77095347c635d821005c3427cb004637`,
all 15 entries, helper `40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02`
and selected artifact manifest `578cd2ade037601ee7f17a2b69f901d116efc664369459e53d9be566cdf317fc`.
The [verifier](notes-publication-implementation-review/verify.exs) and
[result](notes-publication-implementation-review/verify.log) retain these checks.
No runtime test or effect was repeated.

## Final decision and scope

`with_notes_publication_deadline` validates a positive safe-integer host deadline
and any earlier inherited bound, then installs a fresh self/reference marker in
the actual tracked file-effect owner. Profile and deadline state are scoped and
restored on exceptions and ordinary returns; nested scopes preserve the minimum.
Elapsed entry runs no callback. The marker selects a trusted clock contract; it
does not authenticate worker data or grant publication authority.

The actual managed mutation narrows that same scope with the trusted v3
normalization's original nullable `valid_until_ms`. It rejects malformed or
non-capture normalization in this scope. Thus a persistent category still obeys
the policy deadline, and an earlier finite lineage deadline cannot be replaced
by a later Consent bound. Existing source clocks, signed anchors, suppression,
normalizer 32-unit seal and exact normalized request/CAS remain unchanged.
Retention/supersession kinds still refuse before mutation.

Only a notes profile with the actual same-owner marker, or the previously
supported document profile, can use the deadline-aware native root switch. The
existing helper stages/syncs complete immutable bytes, validates the fixed staged
inode and makes its final exclusive UTC decision before the one root rename.
A scheduling stop after that decision remains an admitted attempt, not physical
expiry or a new permission. No post-completion clock sample is used to relabel an
otherwise confirmed ordinary operation; uncertainty/cleanup handling remains in
the existing owners. Generic strict callback admission, notes
`execute_profile_before` and strict support reporting remain closed, avoiding the
earlier bare-`:ok` fallback hazard.

`ManagedCollectionCall.new_capture?` first validates the entire closed request,
then requires metadata version exactly 3 and one new nonnil map at revision zero.
Invocation admits only that shape after source prerequisites. Policy planning
still selects the one actual reviewed literal/proposal recipe and constraints;
fresh JSON with another kind gains no authority from shape alone. The actual
publisher retains current original-source resolution, source/recipe equality,
Identity domain authentication, finite Consent reserve/admit/publishing,
first-domain proof, actual receipt/accounting checks and deferred settlement after
Identity finalization/release. Existing/unknown operations are not adopted.
Legacy mutations, managed document effects, inherited State/service effects,
protected argument display and unrelated output gates keep their explicit fences.

## Complete root prerequisites and intake

`ManagedToolUse` retains the union of inherited inputs and all managed reads. For
nonempty dependencies it requires empty inherited input, identical **complete**
root maps and a matching result for every member. `ManagedReads.root_prerequisite?`
accepts only validated version-3 root observations, successful same-namespace
`collection.call` snapshot or explicit nil-get, exact publication pin and expected
generation. Its existing dependency binding checks project, namespace, policy
epoch, pin hash and full request/result digests. Missing `record` is not nil.
Record-valued get, scan/index, foreign current-parent ID, missing result, mixed
root, inherited or unmatched dependency refuses. No prefix hardcoding or dropped
dependency was introduced.

Authenticity here comes from the host's already committed current-invocation
results and managed lineage, not from calling the pure helper with arbitrary
shaped JSON. Complete root identity comes from the authenticated dependency;
public summary fields do not invent an absent root/manifest hash. The pure check
is a CAS prerequisite; the later retained policy/Collection path establishes
actual currentness. After publication an old root observation remains historical,
not authority for later worker output, recall or inference.

Session restores only `/remember`'s `parse_command` intake. It preserves idle/
quiet checks, selected statement/category contract, actual original journal
origin, current source/input generations and same-client/channel prompt-ticket
submission, storing `purpose: nil`. The existing observed confirmation rechecks
render/channel/scope/selection/generations, consumes the genuine witness and
journals the assertion before capture. `/correct` and `/supersede` do not enter
this parser. Statement attestation does not replace current publication consent
or promote copied external prose into independent truth.

## Executed evidence and limits

Retained 47167 strictly compiles the four production overlays without diagnostics.
Retained 47168 passes six selected controls, including real signed native capture,
actual synced-staging expiry for the shorter policy or normalization deadline,
invalid/elapsed entry, same-owner nesting/exception restoration and shape checks.
Its exact executed test versions retain constant-comparison and unused-alias
warnings. The intermediate 47169 compile stops on the unused alias before tests.
Final 47170 strictly compiles the corrected tests and repeats only the strengthened
pure shape case (one pass, 48 excluded); the native positives are not claimed
against that final fixture text. Retained 47171/47172 strictly compile the two
prerequisite owners and pass three focused pure tests (ten excluded). The initial
freezer filename error is documented; it is not a failed runtime control.

The original [first `/remember` attempt](remember-publication-first-control.md)
remains failed and its original home untouched. The distinct positive is a real
native Session-channel fixture, not a top-level terminal client. Its copied
journal orders the genuine assertion before one managed intent/result, preserves
the original assertion proof and 90-day normalization interval, and contains no
model admission. The actual root/Consent inspection matches the exact settled
operation, generation/floor 1 and one-operation accounting; the Session reports
`:ok` and confirms close. The retained inspection script rereads console evidence,
not the effect. Copied journal SourceOrigin still belongs to its original private
temporary path/inode, and synthetic statements do not prove external authorship.

This accepts a concrete local publication increment, not the complete notes or
P30 dependency. Actual automatic typed-outcome/headless capture, policy/source
changes and revocation races, inherited-expiry edges in full Session composition,
Session/file-effect/native owner-loss ordering, lost settlement/result delivery,
public CLI behavior, later-use sinks and coherent current package/non-Linux
qualification remain open. Existing earlier controls may be reused only where
their sources/helpers match. No aggregate/native positive, model/network call,
runtime edit or gate change was performed by this review.
