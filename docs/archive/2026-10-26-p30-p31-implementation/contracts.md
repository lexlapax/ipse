# Frozen host contracts and implementation ownership

Historical implementation contract record, **2026-10-26**, source `fbb207d`.
Read the [baseline](baseline.md), [implementation record](index.md) and
[current plan](../../plan.md). These shapes constrain implementation; they do not
claim current runtime support. Version 1 below means the new contract version,
not a reinterpretation of an old journal event.

## Request construction and source discovery

P31C0 owns a versioned Session admission event selecting `turn_reference_v1`.
Unmarked/legacy sessions retain their existing validator and layout. Its admitted
header stores the workspace/skills snapshot, static runtime selection and ordered
catalog digest. Mutable reported-model facts belong in the tail. Tools selected
at admission remain present while empty: handle existence is checked at dispatch.

Each appended reference occurrence binds:

```json
{"type":"reference_envelope","version":1,"session_id":"SESSION","turn_id":"TURN","epoch":1,"position":0,"source_generation":1,"policy_generation":1,"content_sha256":"SHA256","content":"LABELLED UNTRUSTED REFERENCE"}
```

`position` is an effective-history insertion boundary validated by the host. It
must follow admitted history and never divide a native call/result group. Content
is a user-role data message, never a system/developer instruction or synthetic
unpaired tool result. Reconstruction validates the hash and chronological position;
normal updates append. All selected mutable publishers use this placement.
An epoch transition is explicitly journaled with reason: admitted refresh,
catalog/route change, compaction or safety retraction. An ordinary contribution
update is not an epoch change. Original records remain intact.

P31E owns eligibility generations and revalidation before **every** model dispatch,
including continuations, resume and compaction. Every managed occurrence and
managed tool-result excerpt carries lineage. A deterministic retraction record
binds original/projection hashes and preserves tool pairing. Unsafe native
projection stops dispatch and offers explicit recovery; it never transmits stale
managed evidence. Original transcript erasure is not promised.

The existing 16,384 rendered-byte aggregate limit remains. Knowledge gets at most
8,192 rendered bytes: recall 6,144/four items, source handle 1,024/one item, framing
1,024/one item. Other publishers reserve their existing bytes first. Optional
recall shrinks; required context failure stops. Failed replacement invalidates old
selection. Source readers remain callable with zero inline allocation.

The fixed index reader takes an optional opaque cursor and limit 1..32. Each page
is at most 4,096 rendered bytes; evidence pages at most 8,192 bytes. Cursor identity
binds Session, source-window/version, offset and policy generation. It cannot name
a journal path. Source rows contain host-issued occurrence/version/chunk IDs,
origin class, read handle and explicit available/partial/unavailable coverage.
New receipts create a new generation; forged/cross-session/stale cursors refuse.
Reads count toward step/context budgets and expose no hidden reasoning. E qualifies
at least 64 typed receipts with constrained/zero inline allocation.

## Origin, proposals and draft intent

P31B/D0 own a native verified display/input channel. The channel establishes the
event; argv, stdin, `TERM`, `interactive: true`, model text and journal role cannot.
P31E stores origin as interactive operator, native operator answer, unattended
input, assistant proposal, typed host outcome or attributed reference. Legacy
origin is unverified. A tool caller cannot choose a stronger source class.
Exact quotes must uniquely match immutable admitted UTF-8 bytes; the host computes
offsets without normalization. Exclusion checks precede even pending storage.

A pending proposal binds project, source, ID/version/text hash, expiry and status.
Rendering binds exact text/version/hash, client (Session or standalone review),
render revision and fresh random acceptance code. Only the actual verified
operator event `accept CODE` accepts it. Bare yes, `--yes`, copied model/source
text and piped confirmation do not. Correction, expiry, interruption, revocation
and re-render invalidate old codes. Resume re-renders; it does not auto-accept.
Acceptance retains original origin and adds an acceptance event; it grants no
effect permission or truth attestation to assistant premises. Standalone listing,
rejection, forgetting and retention reduction require no active knowledge worker.
Publication requires active consent. Each review batch fully displays at most
eight items/8 KiB; 64 items/256 KiB/seven days bounds the pending population.

P31I owns intent records: original/proposed/accepted text and source/question IDs,
draft ID/version, enclosing mode, and pending → accepted → consumed-once or
pending → cancelled transitions. Replacement increments version. Cancel commits
before ordinary input resumes and appends a tail notice without repeating the
abandoned content. Draft calls use the current Session's ordinary main route and
stable catalog; dispatch rejects forbidden effects, including extension callbacks.
`--yes`/saved grants cannot override draft/planning/read-only ceilings. Acceptance
submits exact text once under the enclosing mode. Resume replays neither intent
nor effects. Model carryover remains a separate live semantic gate.

## Consent, commit order and process coordination

P31B owns protected operator state and mandatory admission; extensions own domain
policy. A grant binds verified project/worktree identity, semantic operation and
reviewed artifact identity, sources/exclusions, local storage/sharing/retention,
route/model/endpoint/billing and finite period budgets. Arbitrary same-name
artifacts cannot inherit trust. Separate default headless denial from explicit
deny/read-only/planning; only default headless denial admits eligible knowledge.
Outer extension invocation and each inner effect must both be covered. No grant
widens workspace, shell, MCP or delegation authority.

Lock order: project control → project storage root. Worker-slot/service locks are
acquired outside these short locks; never wait for inference while holding either.
Use retained native OS lock files across independent VMs, not only ETS/GenServers.
Resource reservations bind operation/source/policy generations and period. Unknown
remote effects retain liability; cancellation is not proof of remote settlement.

Commit protocol to implement/test: durable Session intent before admission/egress;
durable reservation under control lock before dispatch; release lock during work;
revalidate policy/source/suppression under control then storage lock; write/sync
staged complete immutable generation; atomically publish/sync its manifest; record
settlement in protected ledger; append Session receipt. If the last append fails,
the durable operation ID resolves the effect without executing it again. Torn
staging never becomes active. Unknown admission/publication is inspected, not retried.
Revocation writes/syncs its new revision under control lock before acknowledgment;
later publication fails its generation check. Acknowledgment reports in-flight work
and does not promise remote egress already admitted has stopped.

P31C1a owns reciprocal Git worktree admission and reusable durable notes. Workspace
metadata is a candidate only; validate canonical root/common-dir and all gitdir/
commondir/backlink relations plus ownership/no-symlink identity. Revalidate before
recall. C0 prototypes never imply repository sharing is implemented. Imports use
writer fencing, preflight/export/checkpoint, validated atomic root switch and
suppression/version floors. Rollback cannot resurrect forgotten facts.

P31C1b/D1/F own bounded parked work, local acquisition and endpoint inference
slots. Work states remain unstarted/admitted/settled/parked/cancelled/unknown.
Closing the Session stops workers. Only explicitly continued known-unstarted work
can run later. Queue bound: 64 references/1 MiB/seven days, one capture and one
ingestion worker per project. One protected service ID coordinates one inference
slot across models/projects/API paths; release it before tools. Unknown daemon
work requires reconciliation, not lock release or automatic retry.

## Source owners and checks

| Contract | Owner | Meaningful verification |
| --- | --- | --- |
| Versioned tail/epochs | Session.Context, Turn, Saved; provider serializers | Actual bodies on all adapters; unchanged historical prefix/tools; native group integrity; legacy reconstruction |
| Source index/quotes | Generic host result/history/source admission; domain extension capture | 64 receipts; unique/repeated/Unicode quotes; unavailable/redacted versions; zero inline budget; forged cursors |
| Origin/card/review | CLI.Terminal, native terminal adapter, Session/Saved | Real controlling terminal and piped negative; cross-client/stale codes; no permissions inferred |
| Consent/headless | Session tool/extension admission, protected control ledger | Real eligible headless save; generated prose quarantined; shell/write/MCP denied; two-VM revocation race |
| Sustainable storage | Extension state adapter plus knowledge record policy | 2,000-note floor, 30/90-day and annual turnover, pins/history, suppression/import/rollback, disk peaks |
| Draft/planning | Session/Turn/Invocation/Saved and Terminal | Dispatch ceilings before/after callbacks; same main route; stable tools; resume/compaction/cancel canary; enclosing mode |
| Usage/TTFT | Usage, Turn, provider callbacks | Nullable cache partitions, monotonic first-visible-text and user-to-text timings, tool-only null, no hidden reasoning |

The [interaction model](../../../dev/knowledge/interaction.exs) executes a subset
of UI state transitions without trust or publication. Its simulated boundary is
not a replacement for any owning package's integrated tests above.
