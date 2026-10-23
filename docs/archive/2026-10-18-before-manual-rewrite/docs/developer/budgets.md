> Historical reference only. Snapshot of `docs/developer/budgets.md` at `10b9dd66d06ef28718b58530a7e5b01c7c50397a` on 2026-10-18.
> Original body retained; relative links rebased for this archive.
> Use the [current manual](../../../2026-10-22-before-structural-consolidation/docs/developer/budgets.md).

# Host-owned shared admission

`Ipse.Budget` covers main, summary, registered local-child and
[accounted extension model](extension-model-calls.md) provider requests.
It supplies optional per-session-tree admission independently of diagnostic
capture and report extensions. Embeddings, audio,
MCP/tool charges and operator-wide quotas are not implemented by this increment.
See [operator configuration and recovery](../operator/budgets.md) for procedures.

## Policy and ownership

`Budget.Policy` reuses the existing JSONSchex adapter, usage normalizer, provider
limit validator and fixed-point configured cost estimator. Its closed version-1
policy validates integral limits/reservations and explicit money-basis/rate-card
pairs. It adds no tokenizer, rate service, database or dependency. The custom
reducer is necessary for Ipse's canonical request identity, uncertain liability
and no-replay semantics; ordinary OTP/files/native locks own execution and storage.

Only operator config can select the policy. Session metadata pins it for embedded
callers too, and the ordinary configuration fingerprint includes a configured
policy. Absent policy keeps the previous fingerprint and request behavior.
Strict resume comparison precedes tail repair. Root metadata uses a null root
descriptor; children pin the host-derived root directory and 128-bit session ID,
retain exact delegation origin and inherit the parent's policy. Profile selection
preserves this authority and refuses unsupported effective output caps.

The root Session owns a live ETS prefix checkpoint shared with trusted host
request tasks and children through a private runtime reference. Its identity binds
root and policy; its prefix length/hash is checked under the native ledger lock
before each transaction. It detects live truncation/replacement across children.
Owner death deletes it; orphaned request code cannot book more work. It is not
serialized into configuration, metadata or extension views. This is host integrity,
not cryptographic attestation against an operator who can alter files and code.

## Dispatch and settlement

Session records canonical `request_admitted` before starting the owned request
task. `Budget.run/4` executes inside that task, keeping slow lock/file IO outside
the active GenServer callback. With a policy, the task:

1. Narrows/validates supported provider output caps, takes the shared native lock,
   validates the current prefix and ledger, and durably reserves all configured
   dimensions or records a refusal. Refusal never reaches the provider path.
2. Durably records `dispatch_intent` before invoking the existing provider path.
   The provider task's credential lookup/inference follows admission; ordinary
   CLI auth preflight is separate and OAuth traffic is not a model quota. Each attempt is unique;
   retries and summaries need their own canonical request and reservation.
3. Persists and fsyncs normalized usage peaks before forwarding observations to
   Session's canonical accounting. Duplicate observations are suppressed. A
   committed overdraw still forwards its counters before stopping the provider
   path. An unsuccessful write forwards no observation; its counters remain
   unavailable and the request retains unknown liability, never a zero balance.
   Original provider continuation/admission rules remain applicable.
4. Fsyncs settlement before returning the result to Session. Successful known
   dimensions release unused booking to at least their observed peak. Every other
   dimension retains at least its booking/peak. Final-only overdraw emits actual
   usage before refusing assistant/tool admission. Unconfirmed settlement returns
   an explicit error without publishing uncovered final-only counters, retrying
   or refunding. Previously committed observations remain available.

The settlement decision applies to the entire shared tree. Another request's
overdraw can therefore refuse an already-completed response whose own usage is
within its reservation. The ledger retains that provider completion and measured
usage, while the invoking Session reports failed admission; those are different
boundaries. Refused assistant/native response content is not durably quarantined,
although visible text already emitted cannot be retracted. Keep this fail-closed
policy rather than admitting effects merely because inference was paid for.
Any future private quarantine/export must preserve that distinction and approval
boundary across main, summary and extension-model calls. A controlled interleaved
two-request fixture verifies both refusal and retained ledger usage; it is not a
live-provider or full parallel-child scheduling experiment.

Request-count bookings are never refunded, including a reserved request whose
provider setup fails. Different billing bases never offset one another. Only
configured dimensions are limited; input/money reservations cannot guarantee
actual in-flight liability. Output reservations narrow public provider fields
where supported. ChatGPT subscription output quotas refuse rather than inventing
support. Returned amount overflow is internally greater than the safe numeric
ceiling and appears as null/overflow plus overdraw in inspection.

## Ledger and recovery

`Budget.Store` uses owner-only JSONL and the existing Rust advisory lock. The
stable lock inode is retained. Each transaction runs in a private filesystem
completion owner that owns the ledger lock until the transaction returns. Killing
the caller does not kill that owner or release the lock during pending IO. A
Session cleanup deadline may expire while this admitted critical section finishes;
its result remains unknown to the interrupted caller and is never replayed. Every mutation locks, verifies the protected file
and live prefix, applies the pure transition, appends and fsyncs before releasing.
The root-owned ETS checkpoint also caches validated reducer state at that exact
prefix. Subsequent live transactions decode/fold only a new suffix; valid external
tail records still undergo all transition checks. Cache identity never replaces
root/policy or prefix validation, and state is pinned only after a successful
write/sync or fully validated read. Fresh resume and independent inspection still
decode the full ledger. Every transaction still reads and hashes the bounded
prefix to detect same-size rewrites and rollback: this is not constant-time IO.
The header binds exact root
identity, policy and digest. Closed records are `reserved`, `refused`,
`dispatch_intent`, `observed` and `settled`; unsupported versions/fields/order,
duplicate attempts and foreign scope refuse. `Budget.Ledger` caches aggregate
liability while folding to avoid repeatedly scanning all previous requests.

Bounds are 32 MiB per ledger, 64 KiB per JSON line, 40,000 reserved and 40,000
refused requests, and 64 distinct observations per request. Strict decoding rejects
duplicate JSON keys and incomplete final lines. Decode has a five-second bound;
lock acquisition has a one-second retry window plus the native helper's existing
startup bound. Limits/failures refuse safely, without provider fallback or repair.
Files must be regular, single-link and owner-only; directories must be canonical
and owner-only. Existing missing lock files are not recreated on resume.

Resume creates a fresh checkpoint and cross-validates the saved budget against
canonical own-session accounting and every registered child's protected, locked,
origin-validated accounting source. It compares each request's liability, not the
whole tree total, and checks every historical observation, including peaks above
later/final counters. A refusal cannot conceal canonical usage evidence. It
refuses unregistered entries, unavailable sources or an under-accounted ledger.
The internal child read returns only validated accounting events for this check,
without changing extension transcript grants or the public accounting projection.
This reuses the existing child reader's 16 MiB/10,000-request
bounds. Validation precedes journal tail repair. Idle resume leaves both ledgers
unchanged and never starts a provider.

Observation durability precedes publication, so loss of the request worker at
the publication boundary leaves a conservative ledger ahead of the journal,
rather than making honest canonical accounting exceed its backing liability.
A temporary observation/settlement lock refusal stops the request; after the
lock is released, an otherwise valid idle resume remains possible without replay.
Measurements whose writes failed are unavailable in canonical accounting. Fixed
reservations still cannot bound actual unmetered usage; this ordering is not a
guaranteed invoice ceiling. Do not infer that an unknown reservation is an exact
measurement or relax source validation to recover previously inconsistent files.

An interrupted reservation/dispatch retains unknown liability. A crash between
canonical intent and the durable decision leaves a source mismatch and refuses
resume; there is no automated reconciliation/repair command. Likewise missing or
corrupt state is not treated as a new quota. A fresh independent root session
is deliberately a new quota, not a migration or clearance of old liability.

A torn tail remains refused. The tested continuation route exports a bounded
reviewed handoff without activating budget state, then imports into a fresh idle
session. Both original ledger and journal remain byte-identical, including a torn
journal suffix. Old reservations/observations are neither released nor copied
into the new quota; this route cannot claim repair of the old tree.

Future explicit repair would need all affected ledger/session/tree locks, retained
original bytes, validation against canonical admissions/observations and registered
children, and conservative retention of known reservations/peaks. Dropping any
unterminated line, including valid JSON lacking its newline, without that
cross-check is not a recovery contract.

`ipse budget --resume` is read-only protected-ledger inspection, using the saved
policy without acquiring provider authority. It does not establish full source
coverage; source cross-validation occurs during actual resume. Budget counts
exclude durable refusals while canonical request reports retain those attempted
requests. Optional reports do not mutate this ledger or enforce admission.

## Verification

Fixtures exercise atomic competing processes, actual parallel children, profile
authority, output-cap refusal, known release, failed/unknown holds, observed and
final-only overdraw, money basis separation/overflow, cancellation/owner death,
live and resumed rollback, historical parent/child peaks, unsafe/missing storage,
real observation-lock refusal followed by inert resume, worker loss between
ledger commit and publication, and pre-repair source validation.
The same `priv/budget-demo.exs` runs in source tests and extracted-package checks:
one parent and two successful child provider entries share the quota, the parent's
follow-up call refuses, default-off creates no ledger, and idle resume changes no
journal/ledger bytes. A separate last-slot race covers fail-fast sibling
cancellation while preserving booked liability, rather than assuming every
reservation reaches the provider.
The separate [model-call artifact](../../../2026-10-22-before-structural-consolidation/examples/model-calls/README.md) exercises
the same admission boundary through an independent worker and actual loopback
provider in source and the extracted runtime. Model-job fixtures hold two real
child HTTP requests open together and validate registered-child source facts;
model cancellation/owner loss retain liability without replay.
All providers/rates/credentials in these checks are synthetic. See
[actual evidence](testing.md#current-evidence-and-next-checks) for commands and
results; fixtures do not establish paid inference enforcement or invoice accuracy.
