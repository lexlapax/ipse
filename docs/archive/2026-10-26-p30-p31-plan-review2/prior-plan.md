# Previous P30–P32 plan

Historical snapshot of `7f4857b`, preserved on **2026-10-26** before the second
plan-audit repair. Relative archive links are rebased and trailing section-separator
blank lines removed. The substantive body is unchanged. This is not current
implementation direction. Use the [current plan](../../plan.md),
[current design](../../knowledge-design.md) and [repair record](index.md).

## P30: advisory decision engines

**Planned; unimplemented; parallel foundation track.** P31 is the active delivery
path when implementation is authorized. P30A/B can proceed independently; later
P30 work consumes the first usable notes journey, not the entire P31 milestone.
The [revised design](../2026-10-26-p30-p31-plan-review/design.md#p30-interfaces-and-useful-consumers)
owns detailed contracts. The [audit disposition](../2026-10-26-p30-p31-plan-review/index.md)
records changed decisions; the [former plan](../2026-10-26-p30-p31-plan-review/prior-plan.md)
preserves the replaced scope.

Target OpenAI Decisions, TypeSafe's hosted System One API for **Jev**, and a
separately configured loopback SystemOne-compatible endpoint. The developer
confirmed that “Zev” meant Jev; the unrelated `zev-rs` project is not selected.
No local engine, SDK, new dependency or live account eligibility is established.

| Package | Output and prerequisites |
| --- | --- |
| P30A | Versioned typed contract, actual engine/subset identities, consumer inputs and protocol fixtures; independent parallel work |
| P30B | Explicit profiles/adapters and owned `host.decision` effect with strict validation, usage, budgets, cancellation and no substitution; after A |
| P30C | Deterministic policy mappings over permitted alternatives; integrate saved consent after B and P31B |
| P30D | Notes-retrieval selection and note-candidate assessment in the actual product; after C and P31E; document/graph consumers are later independently qualified additions |
| P30E | Qualify those two consumers against engine-free baselines, installed workflows and separately recorded live/model access; after D; no dependency on PDF or graph completion |

Acceptance requires exact result count/type/range/distribution validation, valid
per-question refusal handling, uncertainty and malformed-output distinctions,
permission/reservation/journal admission before egress, cancellation during actual
work and zero dispatch on denial. Decisions choose within saved authority; they
never create evidence, establish truth, grant permission or silently switch a
model provider/paid service. Consent displays operation-specific pricing, endpoint,
processing/storage region, cache retention and verified/unknown account controls.
Freeze per-consumer quality, abstention, latency and cost bars before evaluation;
unqualified consumers remain experimental/off. Protocol success is not model quality.

## P31: usable knowledge and prompt assistance

**Active planned delivery track; unimplemented.** Start at P31A when runtime work
is authorized. P30 numbering does not imply it must finish first. P26/P27 retain
their completed original scopes, P20 remains completed and voice/media stays P32.
This task authorizes plan remediation, not implementation or a release.

The selected outcome is automatic useful-fact/decision capture with visible changes,
permission remembered across sessions, retrieval before material clarification,
automatic routing only among enabled knowledge sources, and PDF/Word ingestion.
The audit follow-up adds these explicit choices: enablement takes effect in the
next new session; saved knowledge consent also applies to headless `run` without
`--yes`; graph/PDF may remain experimental/off under qualified completion; a narrow
Rust PDF-parser exception is allowed when maintained Elixir/Erlang options are
unsuitable. Workspace/shell/MCP/delegation authority remains separate.

The [revised design](../2026-10-26-p30-p31-plan-review/design.md) is the single
detailed contract specification: proposed command vocabulary, main-model capture,
source intake, retention, worktree sharing, headless admission, process coordination,
document extraction, prompt editing and release qualification. This ledger owns
delivery status/dependencies and gates; do not duplicate its lifecycle prose here.

| Package | Output and prerequisites; all unimplemented |
| --- | --- |
| P31A | Freeze journeys and naming trial, capture/provider matrix, retention/budgets, acceptance corpora, parser/storage evaluations and recruitment; first active task |
| P31B | Minimal protected project consent, knowledge-only headless exception, cross-process lock/reservation/revocation contract and explicit mode ceilings; after A |
| P31C0 | Source-bound note/evidence records, protected project identity, exclusions, TTL/suppression and export on existing State; after A/B; small declared preview limits |
| P31D0 | Guided setup/status/management, bundled notes catalog, next-new-session activation and installed preview packaging; alongside B/C0 |
| P31E | Main-model automatic capture, complete bounded note recall plus read/search, visible receipts, correction/forget and fresh-session reuse; after B/C0/D0; **interim notes release checkpoint** |
| P31C1 | Scalable local storage, durable work references where needed, lifetime/turnover qualification, source versions and safe migration from preview/P26/P27; can prototype earlier, must pass before larger document claims |
| P31D1 | Remaining compatible knowledge/parser artifacts, catalog composition and installed upgrade paths; follows the applicable C1/F/G contracts |
| P31F | Text/PDF/DOCX acquisition, change tracking, cited retrieval and explicit no-extra-service quality remediation; after C1 and the required D1 packaging; Word can qualify independently of PDF |
| P31G | Source-bound automatic relationships, alias/conflict/time handling and correction; after C0/E, with C1 for larger collections; qualifies separately from F |
| P31H | Research evidence transfer and cross-store lineage/invalidation; integrates each available E/F/G store without requiring unqualified optional backends |
| P31I | Line-oriented enhancement/accepted intent, planning/MCP read classification and deferred planning decisions; UI/contracts can start after A/B, integrated clarification needs E and F when documents are selected |
| P31J | Integrated safety, quality, resource, installed-user, migration and whole-manual acceptance; records supported, experimental and unverified slices explicitly |

F and D1 develop together: parser/acquisition code can run in source fixtures
before packaging; F's installed acceptance requires D1's relevant artifacts.
Do not turn this integration relationship into a sequential implementation deadlock.
The early notes release does not wait for C1, all parsers, automatic graph or P30.
It retains honest capacity limits and a migration path; publication still requires
separate authorization. Core notes/recall quality cannot borrow P27's result or
the optional graph/PDF experimental allowance.

Acceptance gates:

- Ordinary installed users enable knowledge without manual builds/JSON/MCP, see
  accurate next-session status, use normal conversations and later recall, correct,
  forget and disable. Covered effects cause zero repeat permission prompts in chat
  or `run`; prove knowledge save while shell/workspace edits remain denied.
- Default capture uses host-validated tools on the selected main route, with all
  adapter protocols covered and live/model quality distinguished. No mandatory
  secondary extractor or new embedding account. Qualify small notes and larger
  document retrieval separately, including paraphrases and citation support.
- Preserve authority, evidence and lifecycle under secret/poisoned inputs, concurrent
  processes, revocation, cancellation, queued work, worktree divergence, stale context,
  disabled-store forgetting and old-backup migration. Experimental labels waive
  none of these gates. Unknown effects never replay.
- Freeze and measure capture overhead, shared budgets, retention/turnover, parser
  fidelity and storage capacity. Complete Linux/macOS source/package/installed
  checks and independent user journeys; absent human-platform evidence stays open
  and needs explicit qualified acceptance at release, never an invented pass.
- PDF/Word and graph remain in delivery scope. The developer permits qualified
  P31 completion with graph/PDF quality failures retained as experimental/off,
  precisely documented with follow-up work. Core notes/recall, Word and safety gates
  remain required. Rewrite manuals for the actual shipped scope at each checkpoint.

Deferred: voice/media, universal historical-chat mining, unattended daemons,
team/cloud synchronization, unrestricted provider routing, live in-session artifact
activation, lossless context erasure and a general workflow framework.

## P32: voice and realtime media

**Deferred; unimplemented. Previously P31; older archives call it P28 or P24.**
Keep the requested scope for a future delivery; it is no longer ahead of
architecture/security review or self-development.
Build on the owned text/provider and P23 accounting foundation. Start with a
chained STT → admitted text agent → TTS extension/client; then add a versioned
realtime provider/session capability for bidirectional transport, interruption,
turn control, playback acknowledgment and reconciliation of generated versus
played history.

Voice choice, STT/TTS/device adapters and UI belong in extensions/clients. Core
owns resource lifetime, admission, approvals, cancellation, flow control and
provider continuation integrity. Use a separate media data plane, ephemeral raw
audio by default, canonical transcripts/usage and explicit endpoint/device/billing
choices. Text subscription authentication does not establish audio eligibility.

Acceptance: synthetic split/slow/disconnected media, revised interim transcripts,
barge-in, stale/unplayed frames, owner death, approval waits and no-replay recovery;
source/package checks and separately recorded opt-in live account/device checks.
Evaluate maintained Elixir/Rust/OS facilities and approve/inventory external
dependencies before adoption. No codec, frontend runtime or service is selected.
See [media boundaries](../2026-10-18-before-manual-rewrite/docs/developer/runtime-capabilities.md#text-and-media-are-distinct-from-diagnostics).
