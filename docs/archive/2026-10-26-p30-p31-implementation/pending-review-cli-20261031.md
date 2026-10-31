# Standalone pending review: public CLI and resource recovery

2026-10-31. Historical implementation and local verification record from the
dirty `codex/p30-p31` worktree. This follows the [boundary correction](pending-review-boundary-20261031.md)
and supersedes its public-route availability claim. It is not an independent
audit, installed release or P31E completion. Current procedures belong to
[Knowledge management](../../operator/knowledge-permissions.md#review-a-pending-proposal),
[recovery](../../operator/recovery.md#inspect-unconfirmed-protected-knowledge),
[developer training](../../developer/knowledge-extensions.md#follow-protected-capture-from-a-session-source)
and the [plan](../../plan.md).

## Operator path and scope

`knowledge review [--json] [--after KEY]` lists at most 32 physical pending
record references with key, revision, hash and byte size. The existing native
metadata index reads no values. Its partial flag covers a continuation or a
remaining page. Project/domain ownership and the retained management snapshot
bound the read; active capture consent is unnecessary. Revoked consent does
not prevent listing. Neither signed deadlines nor current eligibility are
asserted, and listing grants no publication authority.

`knowledge review PENDING_KEY [--state-dir ORIGINAL_SESSIONS]` opens one exact
signed target through the existing native review flow. It rejects provider
overrides, `--yes`, JSON confirmation, piped input, explicit deny and narrowed
execution modes. The controlling input/display channel is real; no fabricated
Session is started to obtain it. The card includes original provenance, category
and the proposed accepted-decision retention rule, limited by the current policy
and earlier lineage. Its actual display receipt binds that annotation, while
fresh policy equality keeps the rule stable through publication.

The baseline's broader batch/reject/correct/defer journeys remain unfinished.
The [accepted recall follow-up](accepted-recall-20261031.md) adds scoped current-use
integration. This exposes the independently directed valid
single-card subset as experimental source behavior, not a full notes release.

## Admission, accounting and inspection

The public adapter reuses `Consent.reserve/4`, `admit/4` and `settle/4`. It
reserves one `notes.capture` operation, 131,072 input bytes, 16,384 output bytes,
and zero model/download/cost dimensions. An exhausted finite grant refuses
before native display or a management journal. The reservation ID is the native
operation ID, and its epoch/policy must match the displayed facts. Its opening
source generation is zero because a selected target version has not yet been
read; the later exact signed card and freshly checked original source provide
the actual publication version binding. Reservation alone grants none of that
authority.

The 120-second native setup/display/input budget starts before resource admission.
Target owners are released for human input. After exact `accept CODE`, the
existing source, policy, target, one-use permit, sidecar bounds, journal and
native final-admission checks decide publication. The public adapter measures
the encoded event plus sealed request as input and the actual Collection receipt
as output. Input is checked against reservation before the effect. After all
owners confirm close, success settles one operation and those measured bytes.
Known pre-publication refusals settle zero effect usage. An uncertain return or
caller death preserves the liability; no journal or receipt creates replay.

`Consent.operation/3` exposes its existing recent/compacted lookup through a
read-only protected snapshot. The CLI inspection command accepts a management
journal ID or, when that journal path is absent, a reservation ID. Existing
malformed journals still refuse rather than being hidden by fallback. A journal
with an acceptance event correlates its operation epoch and exact native-target
request digest to the protected record. Inspection is neither settlement nor a
current-note eligibility check.

## Verification

All modified host modules were compiled with warnings as errors into a copied
test runtime. Its `priv` link was replaced only inside that copy. The test built
and staged a fresh Knowledge artifact and asserted equality with its installed
manifest before actual Session capture. The remaining host modules came from
the earlier built test runtime; this is a focused coherent overlay, not a frozen
whole-repository or packaged-runtime acceptance claim.

The opt-in `genuine_pending_public_review` case passed through the actual CLI
parser and native terminal. It covers:

- Two synthetic main-model pending captures across close/resume.
- Metadata discovery without proposal text, including after revocation, with no control/journal mutation.
- Piped input and exhausted allowance refusing before review/storage admission.
- Wrong code and cancellation with unchanged pending state and zero effect usage.
- Native acceptance, exact original proof/text, committed journal, atomic pending removal and accepted note/link, plus measured settled usage.
- Duplicate refusal without another card or another accepted note.
- Policy expiry and revocation after display, refusing publication and preserving the candidate.
- Killing the actual CLI during native input, no acceptance event/intent, confirmed journal-lock release, and retained admitted liability inspectable without replay.
- Inspection by both journal and reservation ID after success.

Three public-mode/option/target tests passed. The focused existing consent,
compaction, review permit, acceptance-selection and management-mode regression
set passed 50 tests. Read-only operation inspection additionally checks a revoked
in-flight entry and a compacted receipt without changing control state.

Local receipts are `/tmp/ipse-public-review-isolated-compile.log`,
`/tmp/ipse-public-review-mode-tests.log`,
`/tmp/ipse-public-review-session-cli.log` and
`/tmp/ipse-public-review-accounting-contracts.log`. They are temporary local
paths. To reproduce, use the isolated-runtime copy procedure in the
[boundary record](pending-review-boundary-20261031.md#local-evidence-and-limits),
compile the current modified modules into that copy, and run the Session file
with `IPSE_TEST_GENUINE_PENDING_PUBLIC_REVIEW=1`, its isolated fresh-bundle root,
and only `genuine_pending_public_review`. No paid credentials or real provider
inference were used; policy installation and model behavior are synthetic.

The broader full suite began before this public integration and is tracked in
`/tmp/ipse-historical-review-full-suite.log`. It was deliberately stopped with
SIGTERM at 08:33:24 local time after 27 reported failures. The verified Mix test
process was live when stopped; subsequent process inspection found no remaining
fixture VM or native helper. The shutdown exit code is not a passing suite
result: no final aggregate receipt exists. This obsolete, contended cohort
cannot qualify this newer source. Whole-source checks,
additional effect-stage loss controls, the adversarial
audit and reviewer handoff remain open.

An overlapping public-review run refused its wrong-code stage with
`operator channel unavailable` before creating a management journal. The native
channel intentionally uses one retained `input.lock` per OS user, even for
different PTYs. Running that control concurrently with terminal cases in the
full suite was not independent isolation. A subsequent full public journey
passed, including the actual inspection commands, but does not repair the
concurrent broad-suite cohort. Run terminal suites sequentially; keep this
interference distinct from product failures and obtain a fresh uncontended
whole-source baseline before completion.
