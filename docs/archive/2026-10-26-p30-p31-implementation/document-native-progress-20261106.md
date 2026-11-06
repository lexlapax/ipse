# Native document progress — 2026-11-06

This is a scoped P31C1b implementation and verification record. It follows
the [Source progress provenance finding](document-progress-provenance-gap-20261106.md)
and preserves that source trace and the earlier
[Source/Index](document-continuation-epoch-20261106.md) and
[shared-generation Job](shared-job-epoch-20261106.md) results. Current milestone
scope is in the [plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance).
This record does not establish P30 or P31 completion.

## Boundary

The candidate records a bounded document progress head in private native
Collection metadata. The actual host-selected project, Session, artifact,
maintenance epoch, plan and body identities, unit and revision bind a head.
The first actual effect creates it; each subsequent publication or preparation
advances it in the same native transaction. A partial write changes the head
revision without completing a unit. Immutable reuse checks the actual record
revision and complete body under the lock in a real native operation. Terminal
publication consumes the exact prepared stages and head in one transaction.
The native operation receipt binds the complete tagged host SDK request.

The Source plan binds its body, expected logical revision, profile and unit
geometry. Its caller-visible catalog base remains an optimistic consistency
stamp, with fresh target/catalog reads, immutable/staged-byte checks and exact
publication CAS; it is not an authenticated original catalog snapshot.
Projection binds its rendered root separately.

Eight heads are an upper bound, not a capacity promise. A Source head reserves
three transport slots and a Projection head reserves two from the existing 16;
all writers must respect those reservations. Admission also reserves reducing
cleanup operations and conservative encoded block, manifest and filesystem
capacity. An oversized reservation refuses the attempted mutation. Maintenance
and cleanup never adopt old progress by changing a caller-controlled counter.
Same-owner reducing cleanup can address the exact old head under a current idle
epoch; a later fence stops an already-started cleanup rather than refreshing it.

These are storage and continuation checks. They do not replace document
approval, source/current-use guards, or inference rules, and they do not prove
that supplied source content is true. General migration, garbage collection,
cross-session or replaced-artifact adoption, populated capacity and model
quality remain open. A later Session control exercised shared SDK
`progress.retire` for a Source head with no remaining stage and retained the
immutable bytes. The direct native old-epoch retirement controls and that
empty-stage SDK case do not establish an operator Source-abort workflow or
cross-session recovery.

## Actual checks and retained failures

The first formatting attempt failed on an ambiguous `if` expression; the source
was corrected before compilation. Initial focused native/schema selections
then passed 11 tests. The first Source/Projection selection passed two of three;
the Facts fixture attempted its maintenance setup before it had established a
Collection namespace. A later selection passed three of four; the Facts fixture
used an ordinary binding where its existing guarded commit requires the v2
shared-producer binding. The fixture was corrected without widening the guard.

The next focused selection passed five native/capacity tests in 4.0 seconds and
two Source/Projection Session tests in 41.2 seconds, with 69 Session cases
excluded. A subsequent run compiled successfully, passed six of seven native
controls and passed both Source/Projection Session tests in 40.9 seconds, again
with 69 excluded. Its receipt-tampering and calibrated capacity controls passed.
Its aggregate remains **failed**: the new checkpoint test expected a native
fence code, but the document profile rejects `checkpoint.drop` before native
CAS. The corrected test asserts that reachable refusal and a separate pure
fence predicate; it does not claim that an administrative request reached
native CAS. A fresh focused run then passed **7 native controls in 5.2 seconds**
and the separate empty-stage SDK retirement Session control in 14.5 seconds,
with 71 excluded. Its compilation and source postchecks passed. The prior
six-of-seven failure remains part of the record.

A separate seven-file legacy/document compatibility selection passed **66
tests in 51.3 seconds**, with no exclusions or failures. It covered the
document Stage, maintenance, Store Session and profile files plus Collection
blocks, encoding and core tests. This normal test-runtime selection used the
same `CollectionStore` source and built test module, with source, runtime and
link guards and independent neutral checks passing. It is not the complete
default suite or the separately open Migration compatibility selection. These
passing and failing selections overlap and must not be added together as a
full-suite count.

The receipt controls use actual native results and reject edited maintenance
epochs, changed partial-write fields, missing or invented prepared references,
and an aborted stage reappearing in the returned progress. The host validator
checks what the individual request makes observable. A continuation tag does
not itself carry the whole prior prepared set; this is not a claim that the
saved result is a cryptographic proof of every earlier receipt.

Two later nonzero-epoch fault controls passed in **23.9 seconds**, with 72 cases
excluded and an unchanged-source postcheck. A disclosed controlled effect
baseline left room for one measured native partial write; the returned unit
stayed zero, altered offsets/revisions refused, and an explicit continuation
resumed the exact slot, epoch and offset before cited publication and Saved
reconstruction. The baseline was not fifteen actual earlier native effects.
The other control closed the owned native port during the next publication
after one known partial write. It retained the unknown intent and returned no
replay continuation. After confirmed owner exit, a native snapshot observed the
retained head and transport identity; same-ID idle resume left the native file
bytes unchanged. No missing acknowledgment was classified as nonpublication.

A later complete Migration-file selection hit its **300-second outer timeout**
with exit 124 and no final ExUnit summary. One existing test itself permits 300
seconds, so that outer limit was insufficient for the whole file. Its partial
progress supplies no aggregate totals or compatibility pass. The unchanged-source
postcheck passed, and a subsequent host observation found no owned process group
or Input-lock holder. A properly bounded isolated qualification remains open;
neither product assertions nor test timeouts were changed.

## Bounded capacity observation

The passing instrumented native control used a trusted disposable synthetic
store, not a long-running population. A calibration selected a fitting state;
the actual adjacent native write was refused, leaving the root bytes and
generation unchanged, and an exact owner-bound stage abort then succeeded.

| Synthetic fixture measurement | Observed |
| --- | ---: |
| Public record descriptors | 3,815 |
| Heads / reserved slots | 8 / 16 |
| Active / prepared stages | 8 / 8 |
| Stage records | 104 |
| Known operations / generation | 8 / 8 |
| Encoded blocks / block-body bytes | 45 / 524,225 |
| Reserved future files / bytes | 168 / 9,358,272 |

The public descriptors share a real packed fixture object; stage objects and
headers are physically present. Ledger and descriptor history are synthetic:
this was not 3,815 actual writes, an endurance or throughput run, or a result on
the original notebook. An earlier passing run used the same calibration method
but did not record its count; its exact N remains unknown.

## Evidence and next checks

Only source and log hashes are recorded here, not private journals, document
contents or approval values. Each input inventory and postcheck applies to its
own selection; the corrected checkpoint test is part of the subsequent run,
not the retained failed run.

| Evidence | SHA-256 |
| --- | --- |
| Later-run input inventory | `46b0c97d07427b92069c495875ca1cc7065f6070e7254d685a3f76c993088382` |
| Later strict compilation log | `9ef6b07ce985b2f322f9bf76bc1f755dd88c1e7a59a7a037553028ce7138fd17` |
| Later native log, including the retained fixture failure | `568f96cc51c03761987f2165e77c6a3417789a901eb6177aefacbfb2c40d59d8` |
| Later Source/Projection Session log | `3bc7b8e4698895fccd01e4c31b8deb8acf469bb457c92afe9a546fb36c519ebc` |
| Later source postcheck log | `ba2cf62bd9c5923c5f4bb42d81f83bc1d9f2973b42bbe550d4610c6d56eb6e4c` |
| Earlier passing native selection log | `209e1059ee447901f39fcf2948476f80bc58810e33fede6142e6afe5d9fa5715` |
| Corrected-run input inventory | `efb0dfc7f692016f378042e5afe550b9588478dc71a5f126a43b90f815ace3c4` |
| Corrected seven-control native log | `eb8e4224d2a0b78008257121d287eaccf308d73d522d2cc0349ddfcb498a098a` |
| Empty-stage SDK retirement Session log | `4164c70757531c7a96c9dac84c479939d618e06ea1a76f53319e6018d25f7a63` |
| Seven-file compatibility safe receipt | `28630952996d9f8a135251e11cdf19440fbe6ab56fd3d68afe4d6ea5475e3d44` |
| CollectionStore source in the compatibility selection | `ef346d109125b868d1a1d450c94e9eaf20562b18f4fa97ade3b28744822db770` |
| Post-format normal build | `145a534f877752a9adb737f787b8762e751e1f4891f9a2121b5bbe2e2c6f7ee1` |
| Timed-out Migration selection | `ac3ba7f43a91e295b400dc4b89b6b3d3acf14bf7c53a83c89b35e4b4f7aa197c` |
| First formatting failure log | `a3ab6c4ae9e636d04621f2be0858e576115eb5007ffdd594c129a0e50aaf6617` |
| First Source/Projection fixture failure log | `c2aa672f5071e12be70fc6351951c2b45cd455be9d88b6d243e408f62ac76949` |
| Second Source/Projection fixture failure log | `41e1423e55075bcbbf8370e7469c4106361d8d2276604a438451a643ad0094c8` |

The normal build rebuilt 199 host modules and all four normal bundles with
source postchecks passing. A separate credential-free scripted demo in a fresh
home/workspace passed with its source postcheck. After canonical formatting,
a second normal build rebuilt the same host and bundle owners and passed its
source postcheck. The installed Elixir 1.18.5/OTP 27.3.4 formatter changed 42
files across the pending feature and historical formatting repairs; normalized
parsed syntax remained equal for all 1,053 selected source files, with modes and
exact postimages checked. These formatting changes do not supply a new behavior
test result. The indexed current-manual check passed across 1,243 Markdown files
and 10,182 local links with zero errors. Separate Migration compatibility and
the remaining whole-source milestone baseline are still required.
General producer fencing, GC, migration,
public Source abort and cross-session adoption remain open. No model service,
paid account, original notebook or broad capacity run was needed for these
focused controls. Older unrelated baseline issues involving formatter versions
and a retired macOS runner are being repaired without relaxing their checks.
