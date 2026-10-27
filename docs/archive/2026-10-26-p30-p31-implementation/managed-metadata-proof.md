# Pure managed-metadata codec and capacity proof

Dated nonpublishing investigation, **2026-10-26 Pacific time**. This follows the
[actual capacity refusal at 3,724 records](managed-storage-continuation.md) and
evaluates a replacement for fixed hash-shard pages. **The JSON proposal does not
fit the annual maximum-payload budget and is not ratified for publication.** The
failed store, oracle and pending marker remain unchanged. No Collection, Normalizer,
SDK, native helper or product permission code changes in this checkpoint.

## Reuse the current index as the directory

The [pure codec and leaf planner](../../../dev/knowledge/managed_metadata.ex)
use the already validated current manifest record index as a proposed directory.
There is no second persisted tree. Each record name contains a fixed-width lower
fence; the first fence is zero. An anchor identity is 32 bytes; a live identity is
a kind byte plus the exact 32-byte note/pending/history key. The complete supplied
directory rejects duplicate or malformed references, missing sentinel, unknown
kind bytes and nonpositive revisions. The selected page validates every row in
`[fence, next_fence)`, not only the requested identity. Pages are closed version-3
objects with kind, fence and at most 64 entries, fitting 6,144 canonical bytes.
Version-2 pages refuse. There is no implicit migration of current version-2 stores
or rewriting of their historical receipts.

Insertion replaces one page or splits into two. The split evaluates at most 127
cuts, chooses the least maximum page size and uses the lower cut to break ties.
Deletion or shrinking replacement validates an adjacent page, merges when it
fits, otherwise redistributes, and removes obsolete fence keys. A plan has at most
three changed keys for one tree. Deleting a structural row in this prototype
establishes no permission to discard a source anchor in the product.

Existing `Collection.Blocks` supplies canonical hashed flat receipt partitions;
its 64-KiB blocks and whole-state packing are unsuitable for a 6-KiB sidecar and
32-read normalizer callback. This prototype reuses its partition-validation
principles. `Collection.Encoding` has private receipt-specific array codecs; this
prototype uses the same canonical Base64url and decode/re-encode approach without
changing those APIs. OTP maps, Enum, Integer, Base and bit-preserving encodings
suffice. Canonical bytes use existing `Collection.Migration.encode/1`; no package,
database or new runtime dependency was added.

The future host-only neighbor selector does **not** exist in this checkpoint.
It would need an owner/invocation-bound closure over the verified current index,
trusted managed prefix and needle, current key/revision references, and counted
reads. The supplied directory here is a pure test input, never worker authority.

## Preserve the complete semantic facts

Hashes use canonical unpadded Base64url: decode, exact byte length and re-encode
must agree. Clocks use canonical lowercase base36 for integers in
`0..9,007,199,254,740,991`; floats, padding, aliases, leading zeroes and overflow
refuse. Text is exact UTF-8 bytes, never trimmed or truncated.

The proposed live semantic object has closed fields `version`, `record_key`,
`lineage`, `first_admitted_ms`, `valid_until_ms`, `category`, `eligibility`,
`recipe_sha256`, `policy_sha256`, `record_value_sha256` and `sources`. Its wire
array contains lineage/value/recipe/historical-policy hashes, first/deadline and
category/eligibility codes. The page entry supplies the invertible record key.
The seven source fields are reconstructed only from the exact hash-matched
canonical record and checked source identity. The historical publication policy
remains distinct from the current permission policy. Worker JSON establishes no
source authority. Pin/history categories in the prototype test shape do not
implement their product journeys.

The anchor retains four independent clock slots: first/deadline for note and
pending admission, plus a choice. The full-evidence choice reconstructs the
complete current `Records.override_record` wrapper: version, kind, lineage,
closed override (policy, exact reason and timestamp) and full operator evidence.
All 14 source-proof fields survive, including three IDs, kind/origin, coverage,
path, byte span, quote, quote hash, content hash and receipt hash. The original
4,096-byte wrapper, 1,024-byte override and 2,048-byte proof ceilings still apply.
Packing cannot admit a raw proof that exceeded its original envelope limit.

A **separate, unauthenticated candidate** namespace models a future native
retention-choice capsule. It retains event/display/input hashes, exact target
key/value hash, enclosing lineage, policy, reason, time and an authority reference
(Session ID, event ID and hash). It is not a substitute for the full-evidence
control. No native UI or retained-source contract authenticates that capsule yet;
ordinary answers or SourceIndex proof-shaped JSON cannot mint one. Any omission
or journal-reference substitution needs separate review before product use.

## Check encoded maxima and occupancy

The [shared maximum shapes](../../../dev/knowledge/managed_metadata_shapes.exs)
use safe-integer maxima, a 1,024-byte quote and 256-byte reason. These are declared
codec shapes, not admitted operator events. They are larger than some actual
2026 clock/offset widths; the table is a schema-bound control, not measured native
receipt population.

| Encoded item | Bytes |
| --- | ---: |
| Live wire array | 217 |
| Plain anchor, four non-null maximum clocks | 62 |
| Full-evidence anchor, maximum duration policy | 2,052 |
| Separate candidate capsule anchor, maximum duration | 744 |
| Note-only plain anchor entry weight | 91 |
| Note-only full-evidence entry, pin/session policy | 2,067 |
| Note-only candidate entry, pin/session policy | 759 |
| Live entry weight | 265 |

An entry weight is its one-entry JSON map size minus one. For a page with empty
header size `H`, sum of entry weights `S` and at least one row, encoded size is
`H + S - 1`. Byte overflow or the 64-row limit gives the insertion trigger below.
Each row lies between the measured closed minimum/maximum weights. Choosing the
most balanced legal split gives a conservative minimum child weight
`floor((trigger - maximum_entry_weight) / 2)`. The count constraint cannot lower
this floor: if a balanced cut reaches the 64-row edge, its smaller side has at
least 64 minimum-weight entries. A merge retains the prior floor; redistribution
uses the same bound. A single remaining leaf may be smaller. These bounds apply
to planner-generated states, not arbitrary externally supplied sparse pages.

| Kind | H | Minimum / maximum weight | Trigger | Child weight floor |
| --- | ---: | ---: | ---: | ---: |
| Full-evidence anchor | 122 | 69 / 2,099 | 4,485 | 1,193 |
| Candidate anchor | 127 | 69 / 791 | 4,485 | 1,847 |
| Live | 117 | 245 / 265 | 6,029 | 2,882 |

Nonshrinking insertion/replacement needs at most two changed sidecars per tree,
so an ordinary new capture has a four-sidecar structural bound. **The full typed
lifecycle does not have that bound:** a shrinking replacement or deletion can
need three changes in one tree and a concurrent split two in the other. This
five-sidecar case, actual 32-read callback accounting, future SDK response reserve,
and a host selector remain open. No SDK allowance was enlarged to hide the gap.

## Calculate the annual budget without publishing

The [bounded calculation](../../../dev/knowledge/managed_metadata_proof.exs)
invokes existing pure Notes/workload functions, not Collection effects. A linked
30-second watchdog, sampled 512-MiB BEAM limit and 16-million-word main heap limit
bound the process. No model, native helper or publication was called. The only
new disk output is the developer report.

The existing pure daily policy model, with no day-90 burst, ends and peaks at
**3,642 notes**, not the frozen arithmetic's 3,460: 1,635 ordinary current,
347 ordinary history, 1,460 temporal history and 200 persistent (100 pin,
50 preference, 50 current). It encounters 12,220 distinct lineages before cycles:
2,000 seed, 7,300 intake and 1,460 each ordinary correction and temporal support.
It also proposes 7,848 expiry record deletions. These calculations expose a
workload-accounting discrepancy; they do not redefine acceptance or prove
implemented management/admission behavior.

The declared cycle scenario adds one fresh source per 8,000 non-forget updates,
giving **20,220 source anchors**; 730 daily and 2,000 cycle forget choices give
**2,730 session choices**, plus **100 initial pin choices**. Domain cycle history,
actual typed choices and source admission are not implemented by that generic
cycle fixture. Counts are explicit scenarios, not authenticated year evidence.
The nominal 20,950 mutations exclude initial 2,000 publications, initial 100 pin
choices and expiry-maintenance operations. Pending/proposal populations and
correction retirement markers require additional accounting.

| Note count at 6,144 bytes each | Space left in 24 MiB | Full-evidence metadata members | Candidate metadata members |
| --- | ---: | ---: | ---: |
| Frozen 3,460 arithmetic | 3,907,584 | 8,349,000 | 4,647,360 |
| Pure daily model 3,642 | 2,789,376 | 8,397,230 | 4,695,590 |

Both layouts exceed the remaining logical budget **before leaf headers**. The
class-aware page-header upper totals at 3,642 are 9,189,683 bytes full-evidence
and 4,988,728 candidate. A full-evidence slot upper bound of 10,206 cannot certify
the 8,192-record ceiling; an upper bound alone does not prove an actual slot
failure. Candidate slot upper 5,996 does not remedy its byte failure. These
figures omit authority-journal storage, extra proposals and correction markers;
including omitted requirements cannot turn either no-fit result into a pass.

The original all-maximum-duration calculation omitted the separate initial pin
choices. It is retained unchanged as a labeled first control, rather than
silently replaced. The revised report has both that control and the class-aware
pin/session cases. Neither represents an actual annual native run.

## Retain verification and failed controls

Twelve pure tests pass, including exact full/candidate roundtrips, canonical
encoding refusal, record/hash/source mismatch, poisoned directory/ranges,
33 same-prefix anchors, 33 computed collisions in the former 9-bit live shard,
ascending/descending/hash insertion, merge-to-sentinel and 10,000 structural
edits. The finite collision search examines at most 65,536 declared source-shaped
fixtures; it admits no real sources and makes no human-attestation claim.

An initial test helper produced uppercase hexadecimal fixtures; correcting the
fixture fixed that refusal. A later deliberate 128-row deletion control exposed
a planner limit of 65 combined rows. Allowing the actual two-page maximum of 128
fixed it; its before/after logs remain. The final regression validates two full
64-row pages rebalancing to 127 rows. This pure proof is not crash, allocation,
native-owner or physical capacity verification.

The [artifact manifest](managed-metadata-proof-artifacts.json) binds exact source,
dependency BEAM/helper bytes, reports, failed/repaired logs, final strict compile,
format checks and documentation receipt. The immutable dependency graph is the
earlier 125-module Elixir 1.20.4/OTP 29 fixture; no current shared build was mutated.
Its native helper is bound for provenance and was never invoked here. Elixir
1.18.5 formatting is a separate compatibility check, not execution qualification.
Relevant developer and operator manuals were reviewed as whole documents; their
current version-2 managed behavior remains accurate and this rejected proposal
adds no operator procedure. The [plan](../../plan.md) retains acceptance gates.

Disposition: keep the no-fit control, seek a separate lossless representation
proof and ratify actual typed authority before product integration. No annual,
4,000-note, C1a or release acceptance follows from this checkpoint.
