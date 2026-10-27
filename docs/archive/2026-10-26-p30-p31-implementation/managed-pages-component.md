# ManagedPages codec and local repair prerequisite

Recorded 2026-10-27. This is a component receipt, not storage acceptance or a
current operator feature. Its machine-readable
[results](managed-pages-component-results.json) bind the four source/test files.
The earlier [adaptive proof](managed-adaptive-metadata-proof.md), its
[independent audit](managed-adaptive-independent-audit.md), and the actual
[failed 4,000-target continuation](managed-storage-continuation.md) remain
separate evidence. This component does not modify or resume those stores.

## Scope and ownership

The new host-private `Collection.ManagedPages` owns closed IMB2 page syntax,
immutable geometry, a fixed format descriptor and scoped DomainAuth wrapping.
Its substantial `Planner` module prepares a local split/merge from the current
held Collection read closure. Neither module imports development proof modules,
Msgpax, knowledge-package code or a new dependency. The reviewed algorithms use
OTP bit syntax, Base, integer operations and existing Ipse canonical JSON,
Directory and DomainAuth adapters. The maintained-package comparison and reasons
for the bounded canonical packing remain in the earlier adaptive proof.

This slice does not change Collection, Normalizer, ManagedSDK, Identity, native
protocols or operator procedures. No worker endpoint, import/reseal route,
management mint, migration or metadata repair on an existing root is added.
The component has not been wired into publication. Root-owned integration must
still validate actual native absence and Identity prepared/active state, settle
the SDK's extra-change/byte reservation, and bind the actual Collection result.

## Closed format and authentication

`descriptor/0` returns the fixed version-3 map; `format_body/0` returns its exact
canonical JSON bytes. It names `IMB2`, project-domain HMAC-SHA256 v1, the 75-byte
`version/data/mac` wrapper, safe-u53 adaptive ULEB/fixed7 clocks, native-management
v1, both supported retirement syntaxes and the exact key prefixes and geometries.
The descriptor's actual wrapped size is **1,018 bytes**. Calculations retain a
full **6,144-byte** format reserve.

| Geometry | Anchor | Live |
| --- | ---: | ---: |
| Identity bytes | 32 | 33 |
| Header maximum | 7 | 9 |
| Virtual row-byte capacity | 4,544 | 4,542 |
| Minimum/maximum row bytes | 37/337 | 170/183 |
| Nonsingle minimum occupancy | 2,104 | 2,180 |
| Closed decoder row cap | 128 | 128 |

Live geometry always charges recipe and historical-policy hashes per row, even
when an actual page can deduplicate them in its exact local dictionary. All four
live hashes survive: lineage, value, recipe and historical publication policy.
The geometry does not change with a local dictionary or current policy. Virtual
bytes precede compression/count: for example, 128 smallest anchor rows refuse
even when their encoded prefixes could compress. Sorted identities, exact ranges,
canonical clock encodings, dictionaries, flags, closed fields, UTF-8 bounds and
trailing bytes are checked by decoding and exact re-encoding.

`pack/unpack` parse raw closed syntax only. They mint no tag, source truth,
operator permission or current eligibility. `seal(cap,witness,key,body)` binds
the actual publishing operation ID and **old global generation + 1**, together
with page key, kind, schema and exact raw body, through DomainAuth. The key/fence
IDs come from the protected Identity catalog and are not duplicated in each
value. `open(cap,record,neighbors,slot)` checks the exact actual record ref,
canonical whole-value hash/length, MAC, selected neighbor range and old minimum
occupancy. `open_format/2` requires the exact fixed descriptor body.

Shaped maps do not establish that the caller obtained a current native root.
These internal functions require actual host-supplied observations from the
same held, checked Collection callback. Authenticating an old page does not by
itself establish current consent, a complete untrusted backup or a valid domain
choice. Unsigned version-2 pages have no adoption path here.

The stored capsule is closed `kind=native_management, version=2`: native event,
display hash, challenge, exact target key/value hash, containing lineage, observed
clock, chosen policy and 1–64-byte UTF-8 reason are preserved. Input SHA is checked
against the canonical verb, one space and lowercase challenge hex, without LF or
trimming. Parsing this object never mints a native review permit.

Both retirement encodings remain available as syntax. `native_literal_note`
addresses only the enclosing lineage's exact fixed `note.<lineage>` native
literal derivative. It says nothing about pending, history, paraphrases, arbitrary
prefixes or every nominal retirement event. The full-target alternative retains
key, value hash and exact time. Actual typed mint and inverse semantics remain
integration gates; current capture does not mint either retirement here.

## Bounded local lookup and repair

`Planner.plan(cap,kind,edits,read)` accepts one or two unique edits and the actual
held host read closure. Each edit discovers its selected and neighboring refs
using the closed Directory request, costing four units including nil slots.
Values are then read by exact key, costing one each. No array representing a
whole store, external path, worker callback or new scan API is accepted.

The planner authenticates every selected leaf and required buddy, verifies
consecutive ranges, and checks each old nonsingle leaf against the immutable
minimum **before** repair or resealing. It loads at most four old pages for two
edits. Components merge only when their checked ranges overlap through a shared
page. Deterministic byte-weight splits retain lower fences and use the first
new row for an interior fence; output leaves satisfy the fixed minimum except
the actual sole zero leaf. An empty leaf is allowed only for the sole zero page.

Each semantic edit produces at most three sidecar changes, including a deletion.
A removed page uses its exact positive old revision. New interior fences require
the checked consecutive current slots plus the caller's held global-generation
CAS; their expected revision is zero. `seal_changes` requires the same root
summary/state/hash/manifest and uses the publishing global generation, preserving
the plan's exact revisions. These are host-private plans, not externally trusted
plan documents or authority receipts.

These bounds do not settle the combined Normalizer/SDK contract. In particular,
an anchor shrink/merge plus a live split can require **five** sidecar changes,
including one deletion and four nonnull values. The existing two-sidecar reserve
cannot silently admit that effect. Integration must charge the reviewed finite
change and byte reserve and prove its combined 32-unit read closure separately.

## Checks and declared page calculations

Ten focused tests passed: five pure codec/shape controls and five using actual
native Identity admission, protected catalog writes and DomainAuth leases/tags.
Collection observations in those tests are explicitly trusted callback fixtures;
there were **zero actual Collection publications**. Controls cover exact capsule
and retirement inverses; malformed/truncated/legacy/trailing encodings; all four
hashes; nonsingle underfull refusal; disjoint growth; shrink/merge deletion with
the exact old revision; native absence; missing sentinel; live dictionary split;
wrong body/ref/operation/global revision/root; and escaped owner/capability use.

Both actual Elixir **1.18.5 and 1.20.4** compiled the two production modules with
empty diagnostics and formatted all four source/test files without differences.
ExUnit ran under 1.20.4; no 1.18 ExUnit result is claimed. Initial strict/formatter
harness result-shape, module-redefinition and newline errors are explicitly
retained as harness diagnostics, not product compile failures.

Six final jobs ran sequentially, each with a 30-second deadline, sampled 512-MiB
BEAM limit and 16-million-word main-process heap limit. All completed in under
five seconds each with unchanged source/module bindings and full row/range
inverses. Calculations use synthetic 43-byte tags and make **zero native calls,
model calls, source admissions or publications**. Earlier preliminary jobs briefly
overlapped; no latency or performance qualification follows.

The unchanged declared annual population has 20,220 anchors, 2,730 session
choices, 100 pins, 200 persistent records and 3,642 live values. Nominal 365 days,
30 daily actions and 10,000 cycles describe the input calculation, not executed
endurance. The 3,642 × 6,144-byte value envelope leaves **2,789,376 bytes** for
metadata under the unchanged 24-MiB logical bound.

| Declared case | Metadata plus full format reserve | Headroom |
| --- | ---: | ---: |
| Shared historical hashes, calendar clocks, conditional literal retirement | 2,632,872 | 156,504 |
| Shared historical hashes, safe-width clocks, conditional literal retirement | 2,735,273 | 54,103 |
| Eight historical hashes, calendar clocks, conditional literal retirement | 2,696,959 | 92,417 |
| Full-target retirement, shared/calendar failure control | 3,405,952 | **−616,576** |

Every case has 512 anchor pages and 256 live pages. Measured values are at most
5,743 bytes. The first three rows are conditional arithmetic fits under the
declared retirement semantics; they establish neither universal metadata capacity
nor that every actual retirement can use the compact form. The full-target miss,
earlier full legacy-evidence miss, unbounded historical-hash worst controls and
actual failed 3,724-note continuation remain visible. No physical allocation,
staging peak, import, source-epoch or annual publishing gate is closed.

The first attempt combined anchor/live populations and built a second complete
canonical input tree; it exited `killed` with no final report. Its cause is
**unknown**. The preserved attempt is not classified as a Collection capacity
failure. The revised driver separates anchor/live jobs and hashes a length-framed
stream of individually canonical rows, retaining all input bytes without making
another population-sized JSON tree. Guards were not raised.

## Preserved graph and reproduction

The final private graph is `/tmp/ipse-managed-pages-component-20261027-02`, copied
from the earlier immutable 130-module baseline, then overlaid with only these
component files. It predates later managed-directory/accounting integration and
does not certify those later bytes. All **4,057** source/build/link entries match
before and after tests and final measurements; manifest SHA-256 is
`546b442253e19ef11a428e0bb94ebfac127af1edd7c139dbec4c9ecd0edbf817`.

A byte-verified copy is retained at
`/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/managed-pages-component`.
Its `files.json` binds 4,092 graph/artifact entries, SHA-256
`9eba2fb8508c44a5e2b2d7e0561943ae7f2a8d5405114f079b333d0dd1fedb2b`.
`preservation.json` records exact copy verification, no directory-fsync durability
claim and zero preservation native calls. The bound component-results SHA is
`08bd2078e65ae2dde18b12f3dcca1017234e8857c86cc701f80cc62a540c2a72`.
The graph contains the private helper, separate 1.18/1.20 module outputs, actual
test log, all six page counts/hashes/inverses, first failed attempt and verifier
scripts. Original/final driver input bindings remain distinct.

From a separately frozen matching application graph, one calculation is:

```sh
ERL_FLAGS='+S 2:2' elixir -pa '/private/build/lib/*/ebin' \
  /private/project/dev/knowledge/managed_pages_measure.exs \
  anchor calendar shared literal /private/output.json
```

Run the corresponding `live` job separately; use `safe`, `catalog8` or
`full_target` only as the declared alternate inputs. Join the two exact page
totals with the 6,144-byte format reserve. This developer command publishes
nothing and does not turn a calculation into an operator feature.

## Reader-facing review

Root read the complete codec, planner, owning tests, calculation driver, results
and independent report. The whole persistence and knowledge-storage chapters
were reviewed alongside operator memory and knowledge-permissions guidance.
The persistence chapter now teaches a pure roundtrip before describing actual
held-closure authentication and local repair, with the unwired SDK boundary
explicit. No operator workflow was added.

The complete new pure example passed unchanged against the exact codec sources
in a separately frozen private graph. It used no native read, publication or
model. The frozen chapter SHA-256 is
`6923e15a3370732a21b0abda6b173b2fbdf98c29420a0257184b9d332ae58b1a`;
its exact chapter, extraction driver and pass log accompany the owner Core-v3
evidence as a separately labeled documentation check. That neighboring graph's
Core test results do not establish codec/SDK integration.
