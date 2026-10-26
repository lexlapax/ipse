# Previous P30–P32 plan

Historical snapshot of `a812369`, preserved **2026-10-26** before final handoff
repairs. Local links are rebased and trailing section-separator blank lines removed.
Use the [current plan](../../plan.md), [current design](../../knowledge-design.md)
and [final repair record](index.md).

## P30: advisory decision engines

**Planned; unimplemented; parallel foundation track.** P31 is the active delivery
path when implementation is authorized. P30A/B can proceed independently; later
P30 work consumes the first usable notes journey, not the entire P31 milestone.
The [current design](../../knowledge-design.md#p30-interfaces-and-useful-consumers)
owns detailed contracts. The [second audit disposition](../2026-10-26-p30-p31-plan-review2/index.md)
records repairs; the [former plan](../2026-10-26-p30-p31-plan-review2/prior-plan.md)
preserves the replaced scope.

Target OpenAI Decisions, TypeSafe's hosted System One API for **Jev**, and a
separately configured loopback SystemOne-compatible endpoint. The developer
confirmed that “Zev” meant Jev; the unrelated `zev-rs` project is not selected.
No local engine, SDK, new dependency or live account eligibility is established.

| Package | Output and prerequisites |
| --- | --- |
| P30A | Versioned typed contract, engine/subset identities, consumer inputs, protocol fixtures and frozen finite experiment/benefit criteria; independent parallel work |
| P30B | Explicit profiles/adapters and owned `host.decision` effect with strict validation, usage, budgets, cancellation and no substitution; after A |
| P30C | Deterministic policy mappings and zero-call applicability/bypass over permitted alternatives; integrate saved consent after B and P31B |
| P30D | Implement bounded experiments: notes selection beyond the context budget and candidate assessment in replay/shadow mode on real main-tool inputs; after C and P31E |
| P30E | Evaluate frozen experiments against engine-free baselines and installed workflows; record useful, rejected/no-benefit and unverified dispositions plus separate live/model access; after D; document/graph routing is a later independently qualified addition |

Acceptance requires exact result count/type/range/distribution validation, valid
per-question refusal handling, uncertainty and malformed-output distinctions,
permission/reservation/journal admission before egress, cancellation during actual
work and zero dispatch on denial. Decisions choose within saved authority; they
never create evidence, establish truth, grant permission or silently switch a
model provider/paid service. Consent displays operation-specific pricing, endpoint,
processing/storage region, cache retention and verified/unknown account controls.
Freeze per-consumer quality, abstention, latency and cost bars before evaluation.
Hard protocol/integration gates must pass; completed negative experiments can close
D/E and P30 with **no qualified default consumer**. Missing access/incomplete evidence
stays unverified/open unless explicitly accepted as a qualification. Only useful,
qualified strategies become selectable; fitting note sets bypass retrieval decisions
without an extra call. Protocol success is not model quality.

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

The [current design](../../knowledge-design.md) is the single
detailed contract specification: proposed command vocabulary, main-model capture,
source intake, retention, worktree sharing, headless admission, process coordination,
document extraction, prompt editing and release qualification. This ledger owns
delivery status/dependencies and gates; do not duplicate its lifecycle prose here.

| Package | Output and prerequisites; all unimplemented |
| --- | --- |
| P31A | Freeze setup-first journeys, naming trial, main-Session draft contract including ChatGPT, capture/provider matrix, retention/budgets, acceptance corpora, parser/storage evaluations and recruitment; first active task |
| P31B | Minimal protected project consent, knowledge-only headless exception, cross-process lock/reservation/revocation contract and explicit mode ceilings; after A |
| P31C0 | Prototype source-bound records, protected project identity, exclusions, retention/suppression and export on existing State; after A/B; internal only |
| P31C1a | Sustainable notes storage, reciprocal worktree admission, pins/temporal history, safe reclamation/import and 30/90-day plus annual-turnover qualification; after C0, **required before E release** |
| P31D0 | Guided standalone setup/status/management, bundled notes catalog and next-new-session activation; UI alongside B/C0, installed notes packaging against C1a |
| P31E | Main-model capture with host quotes/proposals and input origin, bounded inclusion/read/search with quality remediation, visible receipts, correction/forget and fresh-session reuse; after B/C1a/D0; **interim notes release checkpoint** |
| P31C1b | Extend storage for document/graph collections, source versions/indexes, durable work references where needed and safe P26/P27/released-notes migration; after C1a, prototype alongside E |
| P31D1 | Remaining knowledge/parser artifacts, catalog composition and installed upgrades; follows applicable C1b/F/G contracts |
| P31F | Text/PDF/DOCX acquisition, change tracking, cited retrieval and explicit no-extra-service quality remediation; after C1b and required D1 packaging; Word can qualify independently of PDF |
| P31G | Source-bound automatic relationships, alias/conflict/time handling and correction; after E, with C1b for graph collections; qualifies separately from F |
| P31H | Research evidence transfer and cross-store lineage/invalidation; integrates each available E/F/G store without requiring unqualified optional backends |
| P31I | Main-Session draft mode and line-oriented enhancement/accepted intent, planning/MCP read classification and deferred decisions; UI/contracts after A/B, integrated clarification needs E and F when documents are selected |
| P31J | Integrated safety, quality, resource, installed-user, migration and whole-manual acceptance; records supported, experimental and unverified slices explicitly |

F and D1 develop together: parser/acquisition code can run in source fixtures
before packaging; F's installed acceptance requires D1's relevant artifacts.
Do not turn this integration relationship into a sequential implementation deadlock.
The early notes release waits for C1a's sustainable capacity, but not C1b, parsers,
automatic graph or P30. Safe exhaustion of the old State store is not release
acceptance. Publication still requires separate authorization. Core notes/recall
quality cannot borrow P27's result or the optional graph/PDF experimental allowance.

Acceptance gates:

- Ordinary installed users enable knowledge without manual builds/JSON/MCP, see
  accurate next-session status, use normal conversations and later recall, correct,
  forget and disable. Covered effects cause zero repeat permission prompts in chat
  or `run`; prove an eligible headless save while generated prose remains attributed
  or pending review and shell/workspace edits remain denied.
- Default capture uses host-validated tools on the selected main route, with all
  adapter protocols covered and live/model quality distinguished. No mandatory
  secondary extractor or new embedding account. Qualify small notes and larger
  document retrieval separately, including paraphrases and citation support. Bare
  affirmatives need an exact host-displayed proposal; models supply quotes, not offsets.
- Preserve authority, evidence and lifecycle under secret/poisoned inputs, concurrent
  processes, revocation, cancellation, queued work, forged worktree membership, divergence, stale context,
  disabled-store forgetting and old-backup migration. Experimental labels waive
  none of these gates. Unknown effects never replay.
- Freeze and measure capture/history/compaction overhead, shared budgets, persistent
  remember/preferences, temporal history, multi-day use, turnover, parser fidelity
  and storage capacity. Verify enhancement on the default main ChatGPT route with
  enforced draft effects and preserved history. Complete Linux/macOS source/package/installed
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
