# Protected control ledger adversarial review

Dated **2026-10-26**, incremental work after foundation `f9149f5`. This is an
internal host substrate checkpoint, not P31B completion or final P30/P31 review.
The [persistence chapter](../../developer/persistence.md#serialize-protected-consent-before-publication)
teaches the implemented API; the [plan](../../plan.md) owns integration status.
Saved consent does not yet change CLI or Session approval behavior.

A separately tasked reviewer examined the new control ledger, directory-sync
primitive and tests. It made no repository changes, builds, model calls or
held-out-data reads. It reproduced findings with isolated temporary ledgers and
the existing helper. Author-owned tests and independent probes are distinct.

| Severity | Reproduced trigger | Repair and recheck |
| --- | --- | --- |
| P1 | Nested settings passed policy validation and saved successfully, but enclosing state exceeded decoder depth, preventing read/revocation | Bound nested payloads to depth twelve; validate the exact complete encoded state with its read decoder before staging. Accepted boundary settings/receipts remain readable; excess nesting refuses |
| P2 | Float ticket sequence/epoch compared equal to integers | Compare complete ticket with strict equality; float-counter controls refuse |
| P2 | Callback writes then returns an error after failed receipt work; API reports definite error | All unsuccessful post-callback outcomes remain unknown; durable pre-callback `publishing` prevents replay |
| P2 | Reserve one call under cap two, measure actual two, then reserve another; larger measured usage was discarded | Durably retain overrun and block all new reservation/admission/publication until explicit reconciliation. Never reduce measured costs; terminal reconciliation retains period charges |

Independent final probes confirmed all four closures. They also confirmed that
callback failure/process death retains `publishing` and cannot replay; inspection
and revocation remain possible. macOS directory-sync behavior was not exercised.

Author verification passed **14 consent tests**, including separate real VMs
competing for one ceiling, retained lock identity, and a VM halting after possible
publication but before settlement. The combined foundation/control/Runner suite
passed **62 tests**; a subsequent isolated consent run with private child working
directories and explicit ordered code paths passed fourteen again. Rust helper
compilation with `-D warnings` passed; its suite passed **39 tests, one ignored**.
Formatting, strict compilation and documentation checks passed at that checkpoint.
The complete post-control source/package/installed/platform baseline remains a
later gate; these results establish no model quality or deployed headless grant.

The host still needs real origin verification, semantic outer/inner admission,
explicit mode ceilings, journal/reservation integration and endpoint-wide resource
ownership. Sustainable notes, reciprocal Git worktrees and recovery/import floors
remain separate packages. The ledger's 128-outstanding/16,384-ID/8-MiB bounds fail
closed; safe exhaustion is not annual notes qualification.
