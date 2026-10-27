# Binary managed metadata: conditional size result and open gates

Historical nonpublishing investigation, **2026-10-26 Pacific time**. The
[JSON no-fit proof](managed-metadata-proof.md) at `19f377c` remains unchanged.
The earlier [actual managed series](managed-storage-continuation.md) still failed
its 4,000-note target at 3,724 successful publications. Its store and pending
oracle were not changed or resumed. This separate pure experiment changes no
Collection, Normalizer, SDK, native helper, operator procedure or permission.

**There is no capacity qualification.** A conditional native-literal retirement
and shared-hash calendar scenario fits the measured leaf-value budget. Full
target witnesses, distinct historical hashes and maximum-width clocks retain
explicit failing controls. Host authentication, dynamic lifecycle plans and
actual annual publications remain unimplemented by this experiment.

## Encode the same facts without JSON member repetition

The [binary codec](../../../dev/knowledge/managed_metadata_binary.ex) uses OTP
bitstrings, Base and Integer operations behind a closed developer-only module.
The [shape construction](../../../dev/knowledge/managed_metadata_binary_shapes.exs),
[size calculation](../../../dev/knowledge/managed_metadata_binary_proof.exs),
[canonical-page measurement](../../../dev/knowledge/managed_metadata_binary_measure.exs)
and [tests](../../../test/dev/managed_metadata_binary_test.exs) are separate from
product publication. No dependency was added. Existing `Collection.Encoding`
has receipt-specific private arrays; `Collection.Blocks` packs larger flat receipt
blocks. Neither provides this 6-KiB leaf representation. Their canonical encoding
and bounded partition principles are reused; existing `Migration.encode/1`
supplies canonical outer JSON. OTP has no direct canonical safe-integer varint
primitive; the small bounded implementation checks minimal re-encoding. This is
an experimental closed format, not a new product persistence engine.

Each closed JSON page contains version, kind, fixed-width lower fence and a
single unpadded Base64url string. Its binary payload contains magic/version/kind,
count, optional live hash dictionary and sorted rows. The whole canonical value
fits 6,144 bytes, with at most 64 entries. Front coding stores each identity's
exact longest common byte prefix with its predecessor, initially the fence,
then the remaining bytes. A raw anchor identity is 32 bytes; a live identity is
the invertible note/pending/history kind byte plus its 32-byte suffix. The decoder
checks exact prefix length, order, uniqueness and every row against the supplied
next-fence range. Re-encoding must reproduce the complete original page. This
does not itself validate an entire manifest directory or authenticate its owner.

Anchor rows preserve separate first/baseline pairs for note and pending admission.
An explicit bitmap distinguishes nil from zero. First clocks use canonical
unsigned varints; finite baselines store the exact nonnegative delta. Values
are safe integers, never floats or rounded clocks. A varint has at most eight
bytes and rejects overlong, overflow and truncated forms.

Live rows retain **all four** original lineage/value/recipe/historical-policy
hashes, first/deadline, category and eligibility. Recipe and historical-policy
hashes use one canonical sorted dictionary per page; every referenced hash is
retained, and unused/duplicate dictionary entries refuse. Distinct hashes are
also measured rather than assuming sharing. Source facts continue to depend on
the exact hash-matched canonical note under the earlier reviewed projection;
this codec grants no authority to a worker's proof-shaped JSON.

## Keep old evidence and the new candidate separate

The full legacy choice path roundtrips the complete existing override/evidence
wrapper: 256-byte reason, all fourteen source-proof fields, 1,024-byte exact quote,
IDs, origins, coverage, byte offsets, hashes and safe clocks. Original wrapper,
override and proof byte ceilings still apply. Its original 2,052-byte maximum
JSON-anchor control remains in the prior checkpoint. Packing does not convert
that evidence into the smaller native candidate or change its semantics.

The [frozen management-v2 design](managed-binary-native-choice-design.md), SHA-256
`3e9384b9457ea749481e429517bad728d165f6912b8b0a257748f9c8374ece03`,
is a separately reviewed **future** native contract. The candidate projection
preserves native event16, display hash32, challenge8, target kind+ID33, target
value hash32, observed clock7, choice1, length1 and at most 64 UTF-8 reason bytes.
Pin/session therefore take 194 raw bytes; duration adds seven, totaling 201.
Lineage derives only from the checked enclosing anchor. Exact native input hash
derives from `verb + " " + lowercase challenge hex`, without LF, trimming or
normalization. The semantic input hash must match that reconstruction.

There is no authority reference, fabricated journal, new MAC or host mint in this
prototype. A parser, candidate object or ordinary SourceIndex proof cannot create
operator authority. Actual native observation, target/policy rechecks, one-use
ownership, protected publication and floor/import rules need implementation and
independent review before product use. The candidate retains the latest effective
choice; it promises no old display text or complete historical choice replay.

Retirement has three **separate accounting controls**. Omission is a deliberately
incomplete lifecycle control. The conditional compact form retains closed target
kind `native_literal_note` and retirement time; it could mean all literal recapture
of that exact source lineage is retired only under a fixed reviewed native note
recipe and preserved original history. It cannot silently retire pending
paraphrases or other prefixes. The full control retains exact native key kind/ID,
value hash and time. General arbitrary-prefix recipes or multiple claim
retirements per lineage require additional semantics/bytes. Neither retirement
form is an implemented typed-management contract here.

## Freeze the population and measure actual page bytes

The declared scenario retains 20,220 source anchors: 18,560 ordinary finite
lineages and 1,660 evergreen source versions. The latter include 200 initial
persistent records and 1,460 temporal current versions. Choices are 2,730 session
forgets plus 100 initial pins. Retirement controls contain 8,920 witnesses:
1,460 ordinary corrections, 1,460 temporal supersessions and 6,000 cycle
replacements. The other 2,000 non-forget cycle additions create a fresh record
after deletion. These are explicit accounting scenarios, not an authenticated
domain-year sequence. Nominal 20,950 mutations still exclude bootstrap, initial
pin choices and expiry maintenance; no fake operation receipts were seeded.

Both the frozen 3,460 arithmetic and existing pure Notes-model maximum 3,642 are
reported. At 3,642, the shape mix has 1,635 ordinary current, 347 ordinary history,
1,460 temporal history and 200 persistent: 100 pin, 50 preference and 50 current.
All public values retain the 6,144-byte accounting maximum. No text, evidence,
history, source clock or persistent population was reduced to make metadata fit.
Pending/proposal workloads remain separate and are not silently absorbed here.

Twenty-four finite jobs measure 18 anchor and six live configurations, joining
to 72 combinations. Each canonical page is actually encoded, decoded, compared
against its complete input rows and checked against its next fence. Every page's
size, count and hash is retained. Deterministic source-shaped identities are
development declarations, never admitted Sources or human attestations. All
native/model/publication counts are zero.

Selected packing is greedy by additive conservative virtual weights, with a
64-row cap. An identity is charged its full width plus prefix byte. A live row's
worst dictionary bound charges both full hashes plus index bytes; a declared
one-recipe/one-historical-policy page instead accounts its two shared hashes
explicitly. Canonical front coding then measures the actual savings. Separate
calculation reports conditional split-floor/page-count bounds for a future
virtual-weight planner; **no dynamic binary split/merge planner is implemented**.
Upper-bound misses are distinguished from these actual selected-page measurements.

| Candidate / 3,642 notes | Clock profile | Historical hashes | Measured page bytes | Plus reserved format record |
| --- | --- | --- | ---: | ---: |
| Conditional native-literal retirement | Synthetic fixture epoch | Shared | 2,590,433 | 2,596,577 |
| Conditional native-literal retirement | Calendar 2026–2027 | Shared | 2,622,538 | 2,628,682 |
| Conditional native-literal retirement | Maximum-width safe clocks | Shared | 2,801,045 | 2,807,189 |
| Conditional native-literal retirement | Calendar 2026–2027 | Every row distinct | 2,929,561 | 2,935,705 |
| Full target/value/time retirement | Calendar 2026–2027 | Shared | 3,408,193 | 3,414,337 |
| Full target/value/time retirement | Maximum-width safe clocks | Shared | 3,586,977 | 3,593,121 |

The available metadata space is **2,789,376 bytes** after 3,642 maximum public
values. The conditional calendar/shared-hash result leaves **160,694 bytes**
after reserving one full 6-KiB future format record. That record is a conservative
reservation, not an invented implemented schema or measured page. Future MAC/seal,
authentication and import-provenance costs are **not included** and must still be
bounded. Sharing one policy is a declared year scenario, not a universal resource
guarantee. Wider historical-policy populations can visibly refuse.
Calendar profiles bound anchor/live/retirement clock widths; the candidate's
fixed seven-byte observation field retains its maximum shape. These byte-shape
fixtures do not simulate a causally validated event chronology.

The old 3,460 control has 3,907,584 bytes available; its calendar candidate with
full target witness uses 3,380,170 page bytes. That fit-looking result cannot
replace the larger population's failure. Full old-evidence calendar/shared-hash
controls at 3,642 use 7,444,973 bytes with compact retirement and 8,223,224 with
full target retirement. All other scenarios, row counts and encoded leaf hashes
are retained in the joined report. Record-slot counts include one extra format
record; they remain separate from logical-byte acceptance.

## Preserve reproducibility without product effects

Every measurement job has a 30-second watchdog, sampled 512-MiB BEAM ceiling and
16-million-word main heap limit. No guard triggered. Seven meaningful codec tests
pass: exact varints, legacy/candidate/retirement roundtrips, input-hash binding,
dictionary canonicality, front coding/ranges, every truncation of a candidate
frame, unsafe clocks, unsupported versions and the exact calendar-clock widths.
Initial runner syntax, missing codec dispatch, warning/branch mistakes and the
temporary report joiner's lexical error are retained separately; they are
development failures, not product capacity outcomes.

The first complete 24-job reports are preserved unchanged. A second run adds
explicit per-job source and loaded-module fingerprints before/after, exact job
arguments and runtime version. Every before/after binding matches, and all 24
page-result objects are identical between runs. Global source freeze plus all
560 dependency BEAMs, 126 frozen source files and the uninvoked 108c helper were
verified before and after. Strict codec compilation and actual Elixir 1.18.5 and
1.20.4 formatting pass. The [artifact manifest](managed-binary-proof-artifacts.json)
binds sources, tests, input jobs, reports, failed controls and verification receipts.

No new current user feature or training procedure follows from this experiment.
Relevant collection/knowledge developer and operator documents remain consistent
with their current version-2 publication contract. The dated archive records
these proposed bytes without presenting them as shipped behavior.

## Keep integration gates open

The prototype's four/five-sidecar structural discussion applies to one primary
change touching one anchor and one live identity. A real correction can change
current plus history and multiple old/new anchors or live leaves. It cannot
inherit that bound, a four-sidecar SDK reserve or the generic eight-change cap.
Actual typed atomic plans, shrink/merge occupancy, counted host neighbors and
the 32-read callback budget require explicit design and tests.

Protected host mint/provenance, raw/untrusted import refusal, backups/floors,
shared-evidence history, recapture/pruning semantics, MAC/seal overhead, physical
preflight/allocation and full individual annual writes are still open. Logical
page arithmetic establishes no 42-MiB Collection/22-MiB control/64-MiB total pass.
No 10,000-edit binary-planner or annual acceptance claim is made. The
[plan](../../plan.md) remains authoritative; the active actual capacity series
still failed at 3,724.
