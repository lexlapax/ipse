# Enforcing a shared request budget

A budget decides whether work may start and whether a completed response may be
admitted. It must make that decision across a parent and registered local children
without treating interrupted work as free. `Ipse.Budget` wraps the existing provider
path; it is independent of optional diagnostics and cost reports.

The implementation covers main, summary, local-child, and explicitly
[accounted extension text](extension-model-calls.md) and
[embedding](extension-embedding-actions.md) requests. It does not meter
audio, arbitrary MCP/tool charges, out-of-band executable calls, or
operator-wide account usage. A new independent root session is a new quota.

## Read the three layers

Start with these files:

| File | Responsibility |
| --- | --- |
| `lib/ipse/budget/policy.ex` | Closed operator policy, reservations, output-cap narrowing, configured money measurements |
| `lib/ipse/budget/ledger.ex` | Pure validated transitions and per-request liability |
| `lib/ipse/budget/store.ex` | Protected JSONL, native lock, prefix validation, append and fsync |
| `lib/ipse/budget.ex` | Dispatch ordering, observation publication, settlement, resume source validation |

Only operator configuration can choose the policy. Session metadata pins it,
including embedded callers. Children inherit the policy and exact root/origin;
profile selection cannot replace it. A root-owned ETS checkpoint is a private
runtime reference shared with trusted request tasks. Its identity binds root,
policy, and a validated prefix length/hash. Owner death removes this authority,
so orphaned work cannot book another request. It is never serialized to workers.

## Work through one reservation

Session first syncs canonical `request_admitted`, then starts its owned request
task. `Budget.run/4` performs slow storage work there, outside the GenServer:

1. Under the native ledger lock, validate root/policy/prefix and reserve every
   configured dimension, or durably record refusal.
2. Sync `dispatch_intent` before entering provider setup or inference.
3. Sync normalized cumulative usage peaks before forwarding them to Session.
4. Sync settlement before returning a result that Session can admit.

Request-count bookings are never refunded, even if setup fails. A completed,
known dimension can release unused booking down to at least its observed peak.
Failure, cancellation, missing counters, or uncertain settlement retain at least
the reservation/peak. API estimates, subscription API-equivalent estimates, and
local estimates never offset one another.

Read the "full known usage releases unused bookings" fixture in
`test/budget_test.exs`. Follow its second failed request into `Ledger.liability/2`.
Then read "usage reaches the canonical consumer only after the ledger covers it".
This text fixture's ordering forwards measurements only after durable liability
covers them. A failed observation write leaves its measurement unavailable to
that consumer; it must not become a zero balance.

Embedding captures its nonstreaming final metering before guarded publication.
If the guarded write or settlement fails, Session can retain these genuine
counters while refusing a readable vector result. The ledger is not repaired or
refunded. Resume refuses any counter liability it cannot prove covered. The
ordinary text streaming path retains its existing write-before-forward ordering.

Embedding admissions fix generated-output tokens as inapplicable before dispatch.
Their output reservation and measured budget liability are semantic zero while
canonical `output_tokens` stays null. Applicable request/input/money dimensions
still share the exact ledger. `Policy.request_config/1` never turns a text output
reservation into an embedding wire cap. Missing applicable counters or unpriced
money retain their booking/peak.

Final-only overdraw records covered actual counters and refuses assistant/tool
admission. Another concurrent request's overdraw can also refuse this request's
already-completed response. The ledger retains provider completion and usage;
Session success is a separate decision. Visible text already sent cannot be
retracted, and refused response content has no durable quarantine/export contract.

## Understand storage and recovery

Closed records are `reserved`, `refused`, `dispatch_intent`, `observed`, and
`settled`. The header binds exact root, policy, and digest. Unsupported fields,
versions, order, duplicate attempts, foreign scope, duplicate JSON keys, and
incomplete final lines refuse.

| Resource | Ceiling |
| --- | --- |
| Ledger / line | 32 MiB / 64 KiB |
| Reserved requests / refused requests | 40,000 each |
| Observations per request | 64 |
| Decode deadline | 5 seconds |
| Lock retry window | 1 second, plus native-helper startup bound |

Directories must be canonical and owner-only. Files must be regular, single-link,
and owner-only. Existing missing lock files are not recreated on resume. Lock
files retain their inode; releasing the OS lock ends ownership.

Each transaction runs in a filesystem completion owner that retains the lock
until IO returns, even after caller death. Session cleanup can time out while that
critical section completes. Its interrupted caller keeps an unknown result and
never retries automatically. The checkpoint caches reducer state at a validated
prefix, but each transaction still reads/hashes the bounded prefix to catch
rollback and same-size replacement. Fresh resume and inspection decode the full
ledger.

Resume cross-validates each request's liability against own canonical accounting
and every registered child's protected, locked, exact-origin accounting source.
It checks historical peaks, not just the latest lower counters. Missing,
unregistered, unavailable, or under-accounted sources refuse before journal tail
repair. Child accounting uses its separate 16 MiB/10,000-request read bounds.
An idle resume starts no provider and changes no ledger.

A crash between canonical admission and the durable budget decision can leave a
source mismatch. A torn ledger also refuses. There is no automatic repair or
refund. Bounded reviewed handoff into a fresh idle session preserves original
bytes and leaves old liability in the old tree. `ipse budget --resume` inspects
protected saved state; it does not establish the full source coverage of resume.

## Extend the policy safely

Add a pure transition fixture before changing storage. For a new dimension,
specify reservation units, known/unknown measurement, overflow, and release rules.
Then exercise cancellation between reservation, dispatch, observation, and
settlement. Input/money reservations cannot guarantee actual in-flight charges;
unsupported subscription output quotas refuse rather than simulate enforcement.

```sh
mix test test/budget_test.exs
```

This suite uses synthetic providers and local child requests to check competing
bookings, overdraw, failed writes, owner death, prefix rollback, source validation,
and no-replay recovery. It proves these host protocols, not live invoice accuracy.
