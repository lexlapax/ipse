# Session acceptance: cross-clock deadline assessment — 2026-11-03

This is a proposed wire/state design and source assessment, not an
implementation or verification result. The existing
[native primitive](session-acceptance-native-primitive-20261103.md) remains
unchanged. The partial, unwired Session acceptance overlays are isolated in
`.session-acceptance-1405.iBOSbYlH` at the repository root; they do not expose a
card or constitute an acceptance job.

## Why an earlier native anchor is conditional

The live Review permit currently uses `System.monotonic_time(:millisecond)`;
the transaction guard uses Rust `Instant`. The committed guard `i` accepts an
absolute wall cutoff and derives its own monotonic cutoff when armed. A
conversion from Review's remaining time to a wall cutoff can be widened by a
wall rollback or delay before `i`, so it cannot by itself enforce the live
Review deadline at the native switch.

An earlier native anchor would be conservative **if** host and native
monotonic durations advance at compatible rates with compatible suspend
behavior. Let native anchor at `t0`, host sample remaining Review lifetime
`R` at `t1 >= t0`, and Review expire at `D`. If both clocks share the required
elapsed-time semantics, `R <= D - t1`, so `t0 + R <= D`. Delaying delivery
after `t1` only shortens the useful interval. Subtract at least a full
millisecond from a duration formed from millisecond-quantized BEAM readings,
or derive a separately proven conservative high-resolution bound; an elapsed,
zero, overflowing or unbounded duration refuses.

That premise is not established by the current implementation. OTP documents
that Erlang monotonic time can be frequency-adjusted and that correction and
time-warp modes affect its behavior; its reported OS clock source does not
alone establish that the Erlang clock advances identically to Rust's clock.
Rust documents Unix `Instant` as using `clock_gettime(CLOCK_MONOTONIC)` but
also reserves the right to change the underlying implementation. Suspend
behavior cannot be inferred from a matching label alone. See [OTP time and
time correction](https://www.erlang.org/doc/apps/erts/time_correction.html)
and [Rust `Instant`](https://doc.rust-lang.org/stable/std/time/struct.Instant.html).
The repository currently has no authority that proves a supported clock
configuration or a conservative drift/suspend bound. Consequently the
cross-clock scheme must fail closed when that proof is unavailable; do not
silently alter VM flags or infer equivalence from one measured run.

## Conditional wire and state proposal

If a supported runtime and defensible duration bound are established, retain
existing `h`, `i` and `j` behavior. Introduce distinct internal strict
commands, provisionally `k` and `l`, after checking the final tag allocation:

1. `k` has only the normal sequence/depth header. At depth three, before any
   data mutation or staging and before imports, it enters a strict pending
   acceptance state and records native `Instant::now()` as the one-shot anchor.
   Its acknowledgment must precede the host's Review-duration sample.
2. After `k`, the same trusted file-effect process checks its actual claimed
   one-use Review permit and exact event/intent/request, then samples remaining
   Review and Session-owner lifetimes. It sends `l` with exactly two u64
   values: the absolute wall cutoff and the positive, conservatively rounded
   remaining duration in milliseconds, at most 120,000. The chosen duration
   may not exceed any applicable live permit or owner lifetime. `l` requires
   exactly one retained active-source descriptor, one live Writer control,
   one live Session control and all three valid locks. Only the real Session
   handoff may bind their semantic identities; descriptor counts alone do not.
3. `l` stores a separate checked `anchor + duration` monotonic cutoff and the
   wall-derived guard cutoff. It refuses an already elapsed cutoff and any
   second arm. The strict pending state refuses legacy `i`; no command may
   downgrade strict mode or replace the guarded owners after arming. Ordinary
   `T` is forbidden before arm, and any switch attempt or owner loss makes
   rearming/retry unavailable for that transaction.
4. At the one native `T` decision, require the supplied wall cutoff to be no
   later than the armed wall cutoff. Tighten the **uncapped** wall-derived
   monotonic cutoff by that difference, then take the minimum of it, the
   anchor-derived owner/Review cutoff and the original transaction lifetime.
   Check all of them, the wall cutoff, locks, and the original live owner
   controls immediately before the existing rename decision. Preserve unknown
   results after an uncertain switch or teardown; a check immediately before
   rename is not kernel-atomic cancellation.

The reported host duration is not a native proof of Review authority. The
host must obtain it from the live same-process claimed permit and the actual
Session-owned ticket, bind it to the exact facts, event, intent and normalized
request, and never allow a worker or serialized receipt to supply it.

## Using the existing native terminal clock

In the 65,536-byte management/review display mode, the terminal lease obtains
`clock_gettime(CLOCK_MONOTONIC)` and sends an `R` frame before receiving its
manifest. Other terminal-lease modes do not all provide that frame. The active input result is a later
`i` frame containing the operation and input bytes; it does **not** currently
carry an input-time clock, an expiring native permit, or a one-use publication
claim. `LeasedTerminal.finish_input` currently computes its Review lifetime in
BEAM after input. Therefore the existing scalar `R` alone is not authority and
must not simply be accepted from a caller.

Independent source review also found that existing `LeasedTerminal.run_opened`
adds BEAM millisecond-quantized remaining durations to this earlier native
`R` for display and overall native deadlines. The earlier anchor is
conservative against delivery delay, but that existing conversion has no
explicit rounding reserve or established cross-clock rate/suspend bound.
This is a source-level qualification issue; it is not a demonstrated exploit.

A narrower candidate is to make an earlier terminal-clock reading the
authoritative native deadline for this new acceptance permit. For example, a
fixed native lifetime added to the terminal's pre-manifest `R` begins *before*
display and input, so any handoff or user delay only shortens the opportunity
to act. If it expires while the user is reading, visibly refuse and require a
new render/code. This conservative choice may be less usable than an
input-time clock but does not need an unproved BEAM-to-native duration
conversion. Alternatively a versioned terminal protocol could record the
native clock at verified input; that is a new protocol and needs its own proof,
not a property of today's `R` frame.

The Review implementation would have to keep the clock reading inside the
same-process, one-use permit derived from the *actual* native handle. It must
bind the same Session/client, terminal operation and native render
acknowledgement, full displayed facts, exact input, event, intent and
normalized request. Only the live claimed permit could supply its exact
cutoff to the Session-bound transaction; a worker value, serialized receipt,
unbound `R`, or caller-selected extension of the cutoff refuses. Preserve the
existing Review/BEAM lifetime check as an additional gate, but explicitly
define this native cutoff as the authoritative final-switch expiry for the
new acceptance path; do not claim it also enforces a separate BEAM-monotonic
deadline after the last BEAM check. A variant with a retained native permit
issuer may be needed if the reviewed ownership boundary requires final native
attestation rather than trusted same-process binding.

The transaction must compare that exact absolute cutoff against the same
explicit Linux `CLOCK_MONOTONIC`, with matching time namespace/clock identity,
round the current reading up, reject overflow and mismatch, and check again
immediately before its one attempted switch. Rust `Instant` is not a wire
representation of that timestamp; use the explicitly defined OS clock at both
ends and fail closed if the identity cannot be established. The two helper
processes are currently spawned by the same runtime, but that fact alone is
not a verified namespace attestation for every supported environment. Linux
time namespaces can offset this clock; see [time namespaces](https://man7.org/linux/man-pages/man7/time_namespaces.7.html).

Linux `CLOCK_MONOTONIC` excludes time spent suspended. A Review lifetime based
on it therefore pauses during system suspend; wall expiry is an additional
gate but may move backward. If the product requires expiry during suspend,
both native endpoints need a separately reviewed suspend-aware clock such as
`CLOCK_BOOTTIME`, or the path must fail closed; the current terminal `R` value
cannot be reinterpreted as boottime. See [Linux clock semantics](https://man7.org/linux/man-pages/man2/clock_gettime.2.html).
The design must also test lost Session, Writer, source and Review owner before
the native decision and unconfirmed outcomes around/after rename. Liveness
checks are admission fences, not atomic cancellation. This alternative has not
been implemented or tested, and does not establish the missing Session-owned
acceptance authority.

## Alternative when clock compatibility is not provable

Consider a native-owned Review authority with its own native monotonic expiry,
created as part of the verified terminal input and bound to the exact
Session/client/facts/intent/request and a one-use operation. A native
transaction would retain and check that authenticated owner at the final
decision, in addition to wall and transaction cutoffs. This would require a new
native permit/lifetime contract and a proof that its issuer, recipient,
one-use consumption and cleanup remain bound across the whole flow. It is not
an existing capability, and merely attaching a live process without proving
its actual deadline would be insufficient. Retaining the current BEAM check as
an additional gate does not by itself prove that its separate deadline cannot
expire after the check. Choose and review the authoritative expiry semantics
before implementation.

## Required controls

For either design, test successful actual Session/Writer/source/Review
ownership with a real native terminal, then missing or substituted owner,
wrong recipient, lost owner, altered intent/request and expired or reused
permit. For a conditional cross-clock scheme, test runtime admission refusal
for unknown clock source, correction or suspend semantics; induced delayed
host sampling and delayed arm delivery; rollback and forward jumps; strict
expiry before arm and final switch; rounding and overflow; and the tighter
cutoff against an independently shorter transaction lifetime. Also test
unarmed `T`, second `l`, legacy `i` downgrade, cutoff widening, owner
replacement and repeat switch attempts. Fault injection around the rename
boundary must preserve unknown rather than claim atomic cancellation. A pure
arithmetic test or matching source label cannot establish cross-clock
compatibility. For the native-clock candidate, additionally test provenance
and time-namespace mismatch, substitution of `R`, displayed bytes, input or
operation, one-use claim/replay, input arriving after the early deadline,
wall rollback and forward changes, expiry during handoff, the selected
suspend semantics, and an owner loss on both sides of the switch decision.
No test in this assessment has run.
