# Proposed native management-v2 authority capsule

2026-10-26. Read-only design and pure size construction. No product changes,
native/helper execution, model calls, credential reads, or authority issuance.
This is a new contract proposal, not a reinterpretation of old SourceIndex
proofs or a claim that managed recall/retraction is implemented.

## Recommendation

Use a separately versioned, host-private **latest effective retention choice**
capsule. Its authority is the trusted native host mint path, protected Collection
storage, and monotonic floor/backup rules under the existing cooperative host
trust boundary. A parsed capsule, arbitrary proof JSON, old operator answer, or
worker-returned object grants nothing. Do not add a hash reference to an absent
authority journal. Do not require an extra permanent authority journal merely to
make the new capsule authoritative.

The proposed capsule needs at most **194 raw bytes for pin/session-forget**, or
**201 raw bytes for duration**, with a newly reviewed UTF-8 reason limit of 64
bytes. Embedded in a single Base64URL page, its contribution is not its own JSON
object: 259/268 ASCII bytes if encoded alone, plus existing anchor/page metadata.
It can be smaller when the actual reason is shorter. The old 256-byte reason and
full quote/evidence contract remain unchanged and separately supported; inputs
exceeding the new limit refuse before review, never truncate.

This capsule size alone **does not certify 24 MiB**. A deliberately simple binary
layout retaining the existing live fields and all four anchor clocks still uses
3,240,955 ASCII payload bytes before page headers for the 3642-note maximum,
against 2,789,376 available. Even a note-only two-clock control is 2,863,515 before
headers. These are exact sizes of the proposed widths, not information-theoretic
lower bounds or a proof that every lossless codec must fail. Storage's separate
binary workload proof must establish actual clock classes, page packing,
index/routing and lifecycle metadata before any capacity claim.

## Live native management journey

1. Native CLI receives an untrusted proposal: exact target key, one of pin,
   ordinary, session-forget, duration, duration if applicable, and reason.
   No Main/worker endpoint can select an origin, supply a native observation,
   choose a protected key, or submit an already-minted capsule. Existing worker
   exclusion of all `host.validity.*` remains.
2. Host validates the admitted project/worktree, current applicable permission
   and reviewed recipe, and target under short Identity -> Consent where needed
   -> actual Collection locking. It records target key/revision/value hash,
   lineage, current root/generation/floor/anchor and current base clocks/choice.
   Verify the canonical value bytes with `Collection.Migration.encode/1`.
   Reject an absent, malformed, stale, ambiguous or unsupported target.
3. Release locks before terminal IO. Host builds a bounded complete escaped
   review showing the full current note while present, scope, exact key/hash/
   lineage, current relevant first/deadline, choice, new effective deadline or
   permanent pin/suppression, complete reason, and an independent fresh 8-byte
   random challenge. If representability/display bounds fail, refuse; no summary
   substituted for the proposed authority. Displaying old quote text is not a
   new semantic/native assertion of that quote.
4. Call actual `Runner.operator_input(display, timeout, 2)`. Require successful
   restoration+exit receipt, the exact display hash, actual native event ID,
   exact text hash and exactly the canonical accepted bytes below. No trim,
   copied legacy answers, CLI `--yes`, interactive flag or timeout fallback.
   Native PTY receipt proves the current native terminal path, not human identity.
5. The host holds an opaque local one-use pending observation bound to its
   actual owner/job, target snapshot and proposed review. This process/ref is
   never serializable to a worker or accepted from JSON. EOF, cancel, timeout,
   owner loss, replaced reader or stale target invalidates it.
6. Reenter original-owner/lease-protected Identity and current permission/CAS,
   then one actual Collection lock. Revalidate exact target revision/hash,
   lineage, prior state, project binding, recipe/current policy and pending
   observation. Any difference refuses with no silent rebase or automatic
   retry. Journal the typed mutation intent before effects if this path has a
   Session journal; standalone native management needs no conversation.
7. A new trusted normalizer/mint writes the choice plus affected note/deletion
   and required sidecars atomically through the reviewed managed Collection
   seam, with `advance_floor:true`. Bind original request, normalization and
   recipe digests in its actual durable result. Consume the pending observation
   once, including when the commit is durably recognized after an interrupted
   reply. Unknown outcome is inspected, never automatically re-executed.

All locks are released before terminal IO. The one-use permit authorizes only
the exact management transaction; it is not a general policy grant. Reserving
and settling actual worst-case changes remains necessary. Automatic capture,
read, retrieval or paraphrase cannot reset the first/deadline or undo suppression.

## Closed capsule bytes

The enclosing versioned anchor row identifies the32-byte lineage and declares
the new format. A capsule must be decoded only through that checked enclosing
format. The following is a proposed canonical fixed-width layout, not an
implemented encoder/decoder:

| Field | Bytes | Meaning |
| --- | ---: | --- |
| native event |16| Actual native-v2 nonce; not the independent challenge. |
| display SHA256 |32| Exact originally displayed escaped review commitment. |
| challenge |8| Independent host random challenge used by the accepted input. |
| target kind |1| Closed note/pending/history enum; unknown values refuse. |
| target ID |32| Exact suffix of canonical target key. |
| target canonical value SHA256 |32| Survives target deletion. |
| observed-at ms |7| Host time captured at first completed native observation. |
| choice kind |1| Closed pin/ordinary/session/duration enum. |
| reason length minus one |1| Canonical length; management-v2 accepts1..64. |
| reason bytes |1..64| Exact UTF-8 bytes, no normalization or truncation. |
| duration ms |0 or7| Present only for duration; validated safe integer. |

Maximum 194 bytes for the 2830 pin/session choices; duration maximum 201. Hashes
and IDs are raw fixed bytes, never case-variable hex. Integers use unsigned
big-endian56-bit storage but must be <=2^53-1; high3 bits are zero. A clock null
is represented by an explicit presence bitmap in the enclosing anchor, never
by treating zero as null. Unknown enum, version, extra trailing bytes, invalid
UTF-8, wrong reason length, noncanonical ID or unsafe arithmetic refuses.

The width total includes the separate length byte; maximum reason payload
is 64 bytes, not 65. The future capsule has no Session requirement: native
standalone management can operate without manufacturing Session/SourceIndex IDs.

Exact canonical returned native text, excluding the terminal LF, is:

```
verb <> " " <> lowercase_hex(challenge8)
```

Verbs map unambiguously: pin ->`pin`, ordinary ->`ordinary`, session ->`forget`,
duration ->`duration`. The reviewed duration and reason are selected by the
exact display+challenge; neither is parsed from worker text. Native v2 strips
the terminating terminal LF in its input frame. The host must require exact
returned bytes, then check native `text_sha256` against SHA256 of those bytes.
Input SHA is later losslessly derived from retained enum+challenge; do not store
an unconstrained input SHA and pretend an arbitrary long original input is
recoverable. Sample `forget a5a5a5a5a5a5a5a5` hashes to
`b9787e8a7180d91e4e3472b6358ac40d286ff4c65a0042e1c04dbf65e9f1f687`.

## What survives deletion and what can be derived

Retain target kind+ID and value hash: pending/history IDs are not generally
equal to lineage. A note key may be derived from lineage only after a version
contract proves `note.<lineage>`; the maximum bound conservatively stores it.
Retain native event/display commitment/challenge, exact bounded reason and
observed clock: deleted values cannot regenerate them. Display SHA is a
commitment, not reconstructible display text.

Retain permanent base first/deadline clocks separately for note and pending
lineages, including after expiry, prune and suppression. No anchor eviction.
An automatic publication only tightens its saved baseline, never renews it.
The latest explicit native choice can change effective policy: pin has no
deadline, session remains suppressing, ordinary uses observed time+reviewed90d,
duration uses observed time+duration, with overflow refused. This does not
discard the separate original first/baseline clocks. A later native choice may
replace the previous choice; previous override history is not promised by this
new minimal contract. Native changes must not silently delete required Note
history/shared evidence. Effective prior state is checked live before mint;
only original baseline clocks and latest choice remain afterward.

The capsule is **not** `SourceIndex` source evidence. It does not retain old
display text, old deleted note text, the full256-byte legacy reason, a1024-byte
quote, offsets or a past Session transcript. It cannot supply those later or
turn an operator choice into confirmation of an assistant premise. Retained
Notes/history keep their ordinary full source evidence according to existing
retention and dependent-evidence requirements. A separate optional journal may
provide richer audit, but its growth is counted separately and cannot be a
hidden authority dependency. Do not grant source-read availability from this
capsule alone.

## Protected-store and replay boundary

The host-only mint checks actual native observation and current target under
one-use ownership before writing a new closed version. All readers treat an
entry as effective authority only as part of the admitted protected same-project
Collection and its valid current floor/lineage. Merely validating the binary or
JSON shape never authenticates its creation. No MAC/key registry is added by
this proposal; the current protected-host cooperative same-UID boundary remains,
and arbitrary same-UID rewriting of the whole protected state is not defended.

Replay reconstructs the recorded latest choice and checks its exact structure/
bindings, but never reruns its effect or obtains a fresh native grant. It cannot
reproduce old display text from its SHA. Interrupted prefix before atomic commit
has no choice authority. Successful typed result must match the original intent
and normalized commit; hashes alone are not a native input witness.

Every managed change advances the floor. Older backups must not remove a newer
suppression, pin, original first clock or deadline baseline. Same-project full
backup/migration must preserve the checked management format and floor/lineage
through the actual protected import path; copying arbitrary management rows
through ordinary data import must not promote them into authority. Unknown or
foreign provenance remains unavailable/inert until a fresh native host choice.
This import rule needs explicit implementation/tests before adopting the format.

## Size construction and limits

Run `elixir /tmp/ipse-native-management-capsule-design-20261026/size.exs` from the
repository root. It uses only Elixir/OTP, hashes inspected source files, constructs
exact envelopes and writes `sizes.term`; output is captured in `sizes.txt`.
No application start, live native code or product codec is invoked.

Width controls preserve all existing proposed live hashes: target key33,
lineage/value/recipe/policy4*32, two7-byte clocks and3 flag/enum bytes =178.
Anchor control is lineage32+bitmap1+four7-byte clocks =61. Latest capsule is
embedded only when present. The optional future page is a39-byte binary header
and sorted binary rows in one Base64URL string, canonical JSON envelope
`{"data":"...","kind":"anchor","version":1}`. A page is at most6144 bytes;
the script tests exact boundary and next-byte refusal. Proposed balanced split
geometry gives anchor minimum2138 raw row bytes/live2181. This geometry requires
an actual reviewed split/merge implementation; none is supplied here.

| Note maximum | Reason maximum | Payload ASCII before headers | Page-value upper | Available metadata |
| ---: | ---: | ---: | ---: | ---: |
|3460|64|3,197,760|3,301,076|3,907,584|
|3642|64|3,240,955|3,345,635|2,789,376|
|3460|256 failure control|3,922,240|4,053,921|3,907,584|
|3642|256 failure control|3,965,435|4,098,480|2,789,376|

These totals use20,220 assumed source anchors,2730 session-forget choices and100
initial native pins =2830 choices; retained notes include history and all200
persistent records. The3460 row is the old frozen arithmetic control;3642 is the
existing pure Notes-model maximum (1635 ordinary current,347 ordinary history,
1460 temporal history,200 persistent). Record payload ceiling remains6144.
Do not substitute the3460 fit-looking row for the3642 result.

The page upper is for these proposed leaf values only. It excludes routing/
catalogue values, Collection manifests/operation receipts, other metadata,
correction retirement markers, extra accepted proposals and journal files.
Thus it is not a safe whole-store upper bound or a24MiB pass. Routing cost cannot
be assumed one6144-byte root; a real many-page index also costs bytes/records.
An optimistic note-only/two-clock control still uses2,863,515 ASCII payload bytes
at3642 notes before headers. Null-clock omission, shared policy dictionaries,
front coding, clock deltas and compression can be lossless, but must be bounded
and measured on the exact workloads rather than assumed to qualify this design.

The20,950-operation workload remains unchanged;100 initial typed pin choices
also need their actual publication/accounting if not already included. This
document adds them to retained-choice size, not silently into or out of the
20,950 count. The assumed8000 fresh cycle sources and actual history transitions
are not yet an implemented/validated domain-year sequence. Repeated changes to
one lineage replace its latest choice but must preserve normal required history.

## Existing owners and integration gaps

* `Runner.Operator.run/3`, `Runner.operator_input/3`: actual v2 native channel,
  owner/restoration/exit proof. Current native nonce16 and returned no-LF text
  were verified by source inspection, not a new native execution.
* `Session.Input.valid_observation?/3`: closed observation validation only.
  A model-supplied map passing it is not a real native receipt.
* `Session.OperatorAnswer` / `Session.SourceIndex.admit_operator_answer/3`:
  committed question+answer/source evidence; no management permission.
* `CLI.Knowledge`: existing actual full-review/fresh-challenge/reprepare+CAS
  pattern. Reuse its boundary principles, not its enable permission for unrelated
  management. New host management route/API still needed.
* `IpseKnowledge.Knowledge.Records.override_record/2` and `saved_override/2`: full old evidence
  shapes; pure validation, not permission. No actual module named
  `NativeOperatorProof` or `OverrideRecord` was found in these source owners.
* `IpseKnowledge.Notes.retention/4`, `forget/3`, `apply_override/2`: pure policy
  transitions and floor requirement; no native mint or durable side effects.
* `ManagedRecipe.extract`: operator override currently explicitly refuses with
  `managed_recipe_requires_typed_choice`. Keep this refusal until real host mint.
* `ProjectIdentity.with_binding`, `Consent` current-policy/CAS/publish,
  `Resources` original-owner fencing, `Collection.execute_managed/6`: existing
  trusted atomic/lifecycle seams. Managed receipt digests are integrity bindings,
  not proof that a worker object came from a native terminal.
* `Collection.Normalizer`: original note/pending clocks and floor-protected
  anchors; current automatic path does not implement typed native overrides.
* `Development.ManagedMetadata.Codec/Leaves`: experimental nonauthority JSON
  codec and original2052/744-byte controls. No binary authority codec exists yet.

Before product adoption: real native positive+forged/changed-target/stale-policy/
owner-loss controls; no trim/UTF-8 reason64/65 boundaries; exact binary malformed
and canonicality tests; original old-proof compatibility; atomic unknown outcome
and replay; old-backup suppression/pin/first-clock preservation; raw/import
capsule refusal; shared-evidence/history retention; full20,950+bootstrap+initial
pin workload with all bytes/records/floors and a separately accounted journal.
