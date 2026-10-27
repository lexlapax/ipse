# Protected control turnover and maintenance review

Dated **2026-10-26**. This incremental engineering record supersedes the format
and writer details of the [earlier control checkpoint](control-audit.md), whose
historical results remain intact. Read the [persistence chapter](../../developer/persistence.md#serialize-protected-consent-before-publication)
for the current API. This is not saved-consent workflow, sustainable notes,
platform, model-quality or whole-milestone acceptance.

## Preserve liabilities without retaining every receipt body

The version-2 ledger retains every admitted operation identity and its accounting
timestamp. The most recent 64 terminal records keep full receipts; older terminal
records keep request/receipt digests, sequence, epoch, status and actual resource
vectors. Unknown work and unreconciled overruns remain full records. Duplicate
inspection never creates a new ticket, even if the caller changes its request.
Closed version-1 state upgrades only on a successful mutation, never inspection.

The reader permits 8 MiB and at most 32,768 lifetime identities. New writes use
a smaller 6-MiB-minus-64-KiB ceiling, including maintenance allowance; byte
exhaustion can precede identity exhaustion. No replay-protection reset or eviction
is used. Native allocation admission reserves 18 MiB for control files, retaining
the old root while admitting staged replacement bytes. The
[transaction component](transaction-identity-component.md) explains actual-owner
fencing and the explicitly limited filesystem profile. Unsupported write profiles
refuse; this does not establish portable quota support.

## Independent boundary finding and repair

A separately tasked reviewer seeded a structurally valid ledger containing
27,690 compact terminal identities and three reservations. The 5,668,108-byte
file sat exactly at the former maintenance-admission boundary after its additive
allowances. Public reservation and admission succeeded. A measured overrun then
returned `consent_write_unconfirmed`, leaving the durable row `admitted` with
no actual measurement. A different reserved operation could still be admitted.
Root independently reran this reproduction before repair and observed the same
failure. This was a quarantine failure, not just a missing receipt.

The former calculation added the same `pending * 256` margin after growth had
already occurred. Settlement therefore could not consume the headroom reserved
for it. Policy replacement had the analogous problem with a fixed additional
policy allowance. The repaired calculation reserves each pending row's maximum
future actual/status representation minus the bytes already represented. It
replaces the current policy's bytes with a maximum future policy allowance and
retains epoch-digit headroom. Only terminal receipt bodies receive the global
recent-receipt credit; nonterminal null receipts remain in the base.

The original reproduction now durably retains the measured overrun and refuses
the next admission; revocation succeeds. A behavior regression also uses maximum
safe integer measurements in all six resources, then replaces the policy with
maximum admitted settings and cancels an unrelated known-unstarted reservation.
This checks maintenance after actual accepted writes rather than accepting an
inspection-only synthetic state as evidence of write headroom.

## Checks and evidence boundaries

The focused consent/helper selection passed **24 tests**, seed **169334**, in
**105.5 seconds**, recorded at
`/tmp/ipse-consent-maintenance-regression-final.log`. It includes the original
fourteen consent controls, eight compaction/maintenance cases and two production
helper-override tests. A 25,000-ID fixture then performs 65 actual publications
with maximum 8-KiB receipts, revokes policy and reconciles outstanding liability.
The seeded identities are explicitly not 25,000 individual write transactions.

The independent before/after reproduction is retained as
`/tmp/ipse-audit-consent-overrun-boundary.exs`,
`/tmp/ipse-audit-consent-overrun-before-root.log` and
`/tmp/ipse-audit-consent-overrun-after-root-final.log`. Initial isolated override
attempts used a directory name interpreted by Erlang as an alternative Ipse
application root; helper identity correctly refused there. Those harness failures
are retained separately and supply no successful runtime evidence.

The complete native unit suite passed **62 tests**, with two deliberately ignored
internal subprocess entries, in **8.98 seconds**. Its isolated binary did not
replace the production helper. Whole-source, installed, hosted-platform and final
integrated acceptance remain separately recorded in [verification](verification.md).

The finite [control workload](../../../dev/knowledge/consent_workload.exs) performs
actual individual reservations and settlements, including duplicate inspection,
policy changes, cancellation, unknown reconciliation and measured overruns.
Its 20,950-operation target is separate from semantic notes qualification. It
records loaded BEAM/source/helper hashes, filesystem provenance and synthetic
resource charges; actual model calls are zero. A checkpoint or smaller smoke run
is not annual-turnover qualification. Its VM memory and wall-time guards are
finite, and its private store remains available for inspection after failure.

An isolated complete source checkpoint then passed strict compilation and **82
focused tests**, seed **231770**, in **120.6 seconds**, including transaction,
identity, resource and journal-writer regressions. Its build tree is independent
of concurrent component edits. The log is
`/tmp/ipse-root-control-checkpoint-focused.log`. The Linux control workload passed
110 individual operations on tmpfs and 1,000 on the workspace Btrfs mount. The
latter retained 1,000 IDs, including nine zero-charge cancellations and one
explicitly reconciled overrun; policy revocation/replacement and duplicate
inspection succeeded. Its `control_turnover_passed` remains false because it did
not reach the 20,950-operation target. Timing is diagnostic under concurrent
development, not a reference-hardware latency qualification.

No macOS quota profile is admitted. Unconditional successful-write tests need a
qualified profile; explicit unsupported-profile refusal and excluded profile
journeys must not be relabelled as cross-platform runtime passes. Platform
portability and the complete individual-workload evidence remain open.

## Read admission without operation-ID growth

A subsequent internal `with_policy/6` API holds the current control policy through
a short trusted local-read callback and checked native release. It validates
epoch/digest/expiry/quarantine before entering the callback, gives it only epoch
and policy, and creates no durable period operation. Semantic and mode checks
still belong to the owning host adapter. A read callback cannot invoke inference
or publish content. Standalone inspection remains a separate trusted-host path.

Four actual protected-read tests pass, seed **527896**, in **0.7 seconds** at
`/tmp/ipse-consent-read-focused-repaired.log`: forty consecutive reads leave the
ledger unchanged with zero operation IDs; changed/revoked/expired/malformed pins
never enter the callback; an unresolved overrun blocks consumer reads while
inspection remains available; typed failures and nested control acquisition
discard data and preserve policy. The initial run failed in fixture setup because
`:file` is a reserved ExUnit context key; renaming it to `:control_file` repaired
the harness. That failed run supplies no runtime evidence. Strict isolated module
compilation passes. Session and domain adapters must still integrate this API;
these tests do not establish source eligibility or a complete read-budget policy.
