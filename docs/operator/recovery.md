# Diagnose and recover interrupted work

Inspect the workspace and any external service before asking Ipse to continue.
An effect can finish without a recorded result. Resume preserves that uncertainty
and never automatically repeats the action.

A managed extension input can also remain unconfirmed after some or all bytes
reached its worker. A delivered-input receipt describes transport settlement;
it does not establish callback completion or a successful later effect. Preserve
the original Session journal and inspect its action outcomes before starting new
work. Idle resume recreates no pending input and sends no saved callback again.

## Find the original session

Use its original state directory, normally `IPSE_HOME/sessions`:

```sh
ipse sessions --json --state-dir /private/path/sessions
ipse diagnose --resume SESSION_ID --state-dir /private/path/sessions
```

Replace the ID with one from the listing. Omit `--state-dir` for the default.
Both commands are local. They make no model requests, activate no extensions,
and repair no journal. Listing reads bounded metadata; a listed session may
still fail whole-history validation.

Use the startup message to choose the next step. These refusals replay no saved
work and do not make an incompatible or damaged journal safe to rewrite:

| Message | Next step |
| --- | --- |
| Saved session was not found | Repeat `ipse sessions --json` with the original `--state-dir` |
| Invalid session ID | Copy a listed ID rather than a filename or path |
| Saved session is malformed or incomplete | Preserve the file and use `ipse diagnose --resume SESSION_ID` with its original state directory |
| Saved journal is malformed or unreadable | Preserve the original; check directory access and request developer-assisted inspection if diagnosis also refuses |
| Saved journal is incomplete | Inspect with diagnosis before deciding whether ordinary locked resume can repair a torn final record |
| Saved journal does not match its original location or file identity | Preserve the copy/replacement; use the original file and state directory, or a reviewed fresh-session handoff |

Diagnosis reports phase, unknown calls, context bytes, accounting, recent request
durations, and journal-limit receipts. Its context scope excludes live system
headers. Bytes are not tokens. Durations cover owned model/compaction work, not
all tools or approval waits. Normal diagnostics omit conversation text and hidden
reasoning, but the underlying journal remains private. For live work, use
`/session`, `/diagnostics`, `/context`, and `/info` without inference.

## Decide whether an effect needs inspection

A validation/setup refusal before execution is a known failure. `not_started`
means that proposal did not run. A missing result after intent, transport loss,
timeout, incomplete output, or worker failure can mean `unknown`.

| Effect | Inspect before another attempt |
| --- | --- |
| File write/edit | Read the actual target and compare it with the proposed content |
| Shell work | Inspect changed files and still-running processes |
| Remote MCP | Check service-side records; a closed local connection does not stop remote work |
| Delegation | Inspect child results, approvals, changes, and reported cleanup |
| Model request | Keep recorded usage/liability; inspect any [registered service reservation](#reconcile-an-unresolved-inference-reservation) before overlapping work |

Do not repeat a producer merely to recover a lost display. Cancellation stops
owned tasks and ordinary process groups. Detached descendants can remain.
Cleanup acknowledgment, process exit, and successful work are separate facts.
Resolve unconfirmed cleanup before overlapping another attempt.

## Inspect unconfirmed protected knowledge

Managed-derived document mutations remain unavailable until their required
ownership boundaries are qualified. `--yes`, renewing consent, changing the
timeout or moving to tmpfs cannot bypass runtime gates. The current development
source has narrow reviewed capture, literal replacement, forgetting and retention
paths on supported Linux protected-storage profiles. These choices retain their
separate native review requirements; see the
[protected knowledge procedures](knowledge-permissions.md).
Existing read/inspection and elapsed-policy reclamation have separate rules.

Generic State's `write_before_ms` and ordinary fixed-profile document staging
use a final locked decision after synced staging: expiry before that decision
refuses selection; an already admitted native replacement may finish later.
They do not implement a physical completion deadline. State returns its typed
elapsed receipt; document failures after staging remain conservatively unknown.
Any lost completion may have changed storage. Preserve drafts; do not strip
deadlines or switch stores to retry. See [document Collection recovery](corpus.md#query-a-document-collection) and
[explicit Memory](memory.md#remember-and-inspect-a-note) for its target-expiry rule.

A publication refusal for an unsupported request shape starts no protected
publication. An older extension's managed publication cannot borrow the current
native capture path merely because saved permission matches. Use the supported
[native knowledge procedures](knowledge-permissions.md) with a matching artifact
in a new Session; preserve older records and do not edit their requests or grants
to bypass the refusal. This shape gate is distinct from a storage-profile or
expired-source refusal. Earlier uncertain attempts still need inspection below;
a new refusal does not prove that an old operation left storage unchanged.

A current capture can also settle successfully before delivery of its result is
withheld. If a recalled note's original source disappears or permission is revoked
after the new pending proposal is saved, the turn can stop with an unknown Worker
input. Inspect the saved proposal and operation before new work. Do not repeat the
capture to recover its lost delivery; idle resume recreates neither attempt.

Keep the original Ipse home, protected control/identity/collection files and
Session journal. A lost confirmation can leave a saved grant, a durable note,
pending liability or a prepared first-use domain. It does not prove absence.
Concurrent capture can refuse while another process owns Identity. That refusal
does not make an existing collection new or authorize resetting it; inspect the
recorded outcome and wait for ownership cleanup before deciding on new work.
After the original owner has stopped and cleanup is confirmed, inspect locally:

```sh
ipse knowledge status --cwd /path/to/project --json
ipse knowledge permissions --cwd /path/to/project
ipse diagnose --resume SESSION_ID --state-dir /private/path/sessions
```

Use the original home/configuration and Session ID. Status and permissions start
no inference or worker; they can refuse when protected state is unavailable or
malformed. Preserve that refusal. The diagnosis command reads saved history and
does not reconcile Collection or accounting state.

For an interrupted `/correct` or `/supersede`, keep the consuming Session ID and
the original source Session. The replacement may have reached the stored root
before the native owner or its confirmation was lost. Diagnosis and idle resume
do not repeat the relation or restore its review permission. Inspect the exact
old/new keys and actual storage outcome before requesting a new replacement;
ask for developer-assisted inspection if ordinary current-note reads cannot
establish it. The standalone management-journal command below does not substitute
for inspection of that conversation's relation records.

For a note-derived tool approval, preserve the consuming Session and original
source journals. Accepted decisions also need their original committed management
journal. Loss during protected display can stop the consumer before an approval
prompt appears. Inspect its tool intents/results and the actual target, then use
compatible idle resume after ownership cleanup; resume restores no approval or
tool attempt. Keep the original journals available for later current use.

An interrupted write can also leave a private staging file. A later protected
write checks and synchronizes retained stages before admitting more storage;
if synchronization fails, admission refuses and keeps those files. Status is
not a staging-reclamation command. Preserve the original state and investigate
the storage error rather than removing stages to make a retry fit.

An unsupported storage profile is a separate refusal. Check every protected
location against [the native storage requirements](arch-linux.md#check-protected-storage-admission).
Exact `7.2.11-arch1-1` qualifies only the checked tmpfs combination; a default
Btrfs home still refuses on that kernel. Do not delete protected files, silently
relocate them or treat volatile tmpfs as a durable migration fix.

Do not enable again merely to recover a missing confirmation, delete retained
locks or domain keys, reset the collection, edit a ledger, or replay the old
capture. The knowledge CLI has no automatic prepared-domain or unknown-operation
reconciliation command. Request developer-assisted inspection of the exact
operation and actual storage root before deciding on another attempt. Keep
private files local; report sanitized codes and operation IDs instead of their
contents. [Knowledge permissions](knowledge-permissions.md) explains known
configuration conflicts that can be resolved with a fresh review.

Standalone knowledge management prints a separate journal ID before the
forget, retention, pending-rejection or pending-correction review and effect. Preserve that ID and `$IPSE_HOME/knowledge-management`
with the protected state, then inspect it using the original workspace and
configuration:

```sh
ipse knowledge operation MANAGEMENT_JOURNAL_ID --cwd /path/to/project
```

This read-only command reports the historical journal status and current
protected-control operation status. It does not replay, settle, reconcile or
check current note eligibility. A `publishing`, unconfirmed or missing result
requires inspection of the actual storage outcome before another action. An
already admitted reducing action can finish after review expiry or owner loss; a lost
reply does not prove whether the target remains. Even if inspection finds a
settled operation, an earlier unconfirmed close remains a separate outcome.
For pending rejection, inspect both the exact `pending.` target and its
candidate suppression through developer-assisted protected-state inspection;
the absence of a pending row alone does not prove which operation removed it.
Other proposals from the same source can remain. Rejection retains the original
and management journals, and an uncertain attempt is never repeated automatically.
For a pending correction, journal inspection also derives
`replacement_pending_key` from its validated intent. This is the intended edited
candidate, not proof that it exists or was accepted. Inspect both old and intended
keys through developer-assisted protected-state inspection. A correction that
expires after staging can remain `unknown` with its full resource reservation
even when the old root is still selected; inspection does not resolve that
liability or authorize replay.
For an acceptance journal, `journal_status` describes the recorded acceptance
effect: `committed`, `refused`, `not_started`, or `unknown`. A missing result
after intent, or an incomplete journal tail, reports `unknown`. The command
does not check whether an accepted note is currently present or eligible, and
its receipt alone does not establish a current storage state. For public
review, `control_status` reports the correlated protected consent
operation; older private acceptance fixtures may report `unavailable`. A
still-running owner can append after this snapshot.

For a selected batch, inspect each printed management journal/reservation ID.
An acceptance journal additionally reports `batch_manifest_sha256`, `batch_id`,
`batch_index` and `batch_count`. These correlate the frozen selection; they do
not establish that other items succeeded. Each item has separate input,
publication and accounting. Cancellation or an uncertain result stops the batch
and leaves earlier confirmed items saved. List remaining pending keys before a
new review; do not replay the original command with already accepted keys or
assume a rollback. A new selection has a fresh manifest and acceptance codes.

Public proposal review prints a separate `Knowledge reservation` ID before its
management journal is created. If interruption occurred before that journal,
use the reservation ID with the same `knowledge operation ID` command. It
reports the protected resource status with `journal_status: "unavailable"`.
An admitted or unknown reservation remains a liability; inspection neither
settles it nor authorizes retry. Recent records include reserved and actual
resource vectors; compacted settled records retain actual usage and receipt
commitments. Preserve both IDs and the existing journals for diagnosis.
The management review journal can retain the forgotten target's text; removing
the selected note is not erasure of its original or review journals.
New management journals require their matching native lock/header owner; legacy
append and repair paths refuse their native-only layout. An unsafe management
directory or older helper refuses rather than falling back to those paths.
Preserve a header-only journal as an incomplete startup record, not a successful
action. Read-only operation inspection remains available and does not repair it.

## Reconcile an unresolved inference reservation

Use this procedure when an explicitly registered inference service remains
blocked after an interrupted request. Keep the original `IPSE_HOME`; service
state is operator-scoped across projects. These commands need no conversation,
model request or valid conversation configuration:

```sh
ipse inference status --json --cwd /absolute/path/to/workspace
```

The report includes the current `revision`, each service's registered `origins`
and `active` reservation, queued requests and recent outcomes. An `active` entry
is unresolved; elapsed time or a free local OS lock does not establish that its
remote work finished. A fresh home reports an empty state without creating it.
Existing protected state uses the runtime's ordinary lock/layout/cleanup checks;
inspection can maintain those private filesystem entries without changing the
ledger's admission records. Preserve malformed or unsupported state for diagnosis.

Stop or independently reconcile work at every origin and with every client using
that service. For a daemon you own, use its normal administrative procedure and
verify its work has stopped. Ipse does not stop it for you. An Ollama `/api/ps`
snapshot shows loaded models, not whether an earlier request is still running.
If you cannot establish quiescence, leave the reservation blocked.

After that check, copy `SERVICE_ID`, its active reservation's `id`, and the
top-level ledger `revision` from a fresh status report:

```sh
ipse inference reconcile SERVICE_ID RESERVATION_ID REVISION \
  --cwd /absolute/path/to/workspace
```

The native terminal displays the exact home/workspace, service origins,
reservation metadata and expected revision. Type its fresh `reconcile CODE`
only for that complete proposal; any other response cancels. Piped input,
`--yes` and stale challenges cannot confirm it. The runtime also requires the
service lease to be free and the exact ledger revision/reservation unchanged.
A concurrent ledger change refuses; inspect the new state and reassess it.

Success records an operator reconciliation receipt, clears that active marker
and retains lock files. It replays no request and grants no new project or
knowledge permission. Inspect status again before continuing ordinary work.
If the outcome is unknown, preserve the first result and inspect the current
active/recent records; do not replay the command automatically. Recent outcomes
are bounded to32 entries and are not a complete request-history archive.

## Resume compatible work

```sh
ipse chat --resume SESSION_ID --state-dir /private/path/sessions
```

Repeat original explicit configuration, endpoint, MCP file, and temporary
extension selections. Resume keeps the original workspace, provider/model,
sandbox, delegation settings, and instruction snapshot. Changed digests or pinned
artifact/runtime identities can refuse recovery. Restore original inputs or use
a reviewed handoff; do not edit records to remove a mismatch.
Selected extensions also pin every host BEAM: a different application build can
refuse even when the configuration text is unchanged. Keep the old release for
resume/export; [upgrading](install.md#upgrade-without-losing-recovery-options)
explains switching and rollback. Extension-free sessions still require matching
configuration.

Idle resume starts no inference, callbacks, children, or tools. Pending questions
reappear for an explicit answer. A recorded answer survives interruption, but
ordinary resume still starts idle. Use interactive chat for questions; headless
`run` cannot answer them. `/context refresh` changes instructions/skills only,
without making a changed execution configuration compatible.

An answer rejection leaves the question pending. Review its choices and use the
explicit confirmation printed by the terminal; an answer grants no action
permission. A saved-configuration mismatch requires the original inputs or a
fresh handoff, even when no model request had yet been made.

If inference stops because reference context or its tool catalog could not be
admitted, inspect `/context`, `/skills`, `/ext` and the configured MCP selection.
Use `/context refresh` while idle to adopt reviewed instructions/skills and admit
a new context epoch, or start a fresh session. Refresh grants no effect permission.
Do not edit saved reference records or remove native tool results to bypass the
refusal. An oversized extension selection must be reduced by its publisher.

Validated ordinary resume may repair a torn final journal record while holding
the lock. Read-only diagnosis does not. Corrupt committed records/checkpoints
refuse recovery. Preserve originals for investigation.

New sessions bind their journal to its original canonical directory and file
identity. A copied, moved or replaced file can remain readable for inspection,
but cannot resume as the original live source. Use the original file in its
original directory, or the [fresh-session handoff](#continue-in-a-fresh-session)
procedure. Recreating a file at the same pathname does not restore its identity.
Older journals remain usable as conversation history; resume does not upgrade
them into protected publication sources.

## Recover a request draft

Resume the original Session with its original configuration. Idle resume makes
no inference request and never accepts or executes an unfinished proposal:

```sh
ipse chat --resume SESSION_ID --state-dir /private/path/sessions
```

Use `/enhance show` to inspect a completed proposal. `/enhance accept ID` renders
a fresh confirmation bound to its current revision and terminal. A pending
question is answered through its freshly rendered `answer CODE VALUE`. A failed
or interrupted draft can remain incomplete; `/enhance cancel` records its
abandonment before ordinary input is permitted. Cancellation can also complete a
saved abandonment whose separate host notice was interrupted. It does not
repeat the old inference or any uncertain external setup.

A changed or interrupted MCP catalog revalidation stops draft continuation.
Preserve the refusal and cancel explicitly; discovery success alone is not proof
that the original catalog was pinned before the interruption. Configured server
setup may already have run. Inspect its processes/service records before another
attempt if cleanup is unconfirmed.

If provider continuation cannot be safely separated from the draft, subsequent
dispatch or resume refuses. Keep the original journal and use the explicit
[fresh-session handoff](#continue-in-a-fresh-session) with a newly written task
that omits abandoned requirements. Drafts also refuse required compaction until
their verified projection can be rebased. Original private records are retained;
withholding their active projection is not erasure.

## Respect active ownership

One owner holds the journal lock. Close/cancel it normally. The visible Session
can disappear before storage or tracked work settles, and an approved effect
may still complete. Never delete lock files, truncate records, or open another
writer to force resume. Persistent lock files preserve inode identity.

Linux fresh startup requires a matching rebuilt native helper and filesystem
support for no-replace rename and directory fsync. Unsupported or failed steps
refuse startup without an unsafe fallback. An interrupted fresh startup can
leave a `.pending-header-...` file.
It is not a saved Session; preserve it for inspection and do not try to resume or
replay it. If the journal was published before confirmation was lost, inspect
the original state and resume it explicitly only after the lock is free. On other
platforms, do not attempt a second writer for a newly visible journal while its
first startup is incomplete; a header alone does not confirm lock acquisition.

`header_unconfirmed` means publication may have happened; do not automatically
retry startup. Preserve pending files and any published journal and inspect the
original state before choosing explicit resume after the lock is free. A
successful close can conservatively retain `cleanup_confirmed=false` in its
lifecycle record. For a fresh Linux Session, and for a resumed Session with a
recorded lock identity, diagnosis may report
`"release_claim": "signed_release_claim"` after checking a separate signed
record under the Session lock. This is a claim about the original owner's
observed release; it does not rewrite the lifecycle record or prove that a lost
close or publication reply was received. A missing or unverifiable claim, an
active owner, a later resume that has not closed, or a legacy release can report
`"unknown"`.
Preserve the journal, lock and private sidecars when investigating an unknown
close; inspect the actual effect before retrying work.

New Linux journals retain the original lock identity in the header. Resume
requires the existing lock file to match that identity or an earlier release
intent. An older journal with the release-claim layout but neither identity
refuses resume; preserve it for developer-assisted inspection rather than
creating a replacement lock. Older journals without that layout keep their
legacy behavior.

"Saved session already has an owner" means this attempt started no work. Close
the existing owner normally before retrying. A journal resource-limit refusal
preserves history; use the fresh-session handoff procedure below rather than
truncating the file or raising a limit to unseal it.

`journal_unavailable` or a missing acknowledgment can mean an append already
reached disk. Ipse stops without retry. Slow storage can outlast caller deadlines;
`--timeout-ms` controls provider timeouts, not storage/Session call deadlines.

## Continue in a fresh session

Use a handoff when necessary history cannot fit, a journal is sealed, or you
cannot restore the old runtime. Write a concrete note identifying the task,
relevant files, unknown effects, and remaining uncertainty:

```sh
umask 077
IPSE_RECOVERY_DIR=$(mktemp -d)
ipse handoff --resume SESSION_ID --state-dir /private/path/sessions \
  --note 'Continue the reviewed CLI change. Inspect hello.exs and the pending shell effect before retrying. Preserve existing edits.' \
  > "$IPSE_RECOVERY_DIR/handoff.json"
cat "$IPSE_RECOVERY_DIR/handoff.json"
ipse chat --cwd /path/to/project \
  --handoff "$IPSE_RECOVERY_DIR/handoff.json"
```

Review the artifact before import. The fresh conversation starts idle and makes
requests through the configured provider only after a new task. Historical context grants no
permissions and transfers no credentials, provider settings, native continuation,
tools, or approvals. The new journal saves the artifact once; later resume the
new ID normally without its original handoff file.

The artifact contains a source ID, decoded-event digest, unknown count, and up to
sixteen bounded unknown-call references with an omission count. It omits original
arguments/results and provider data. Its digest proves provenance, not authenticity
or independent review. Your note can contain secrets; no scanner reviews it.
Notes allow 8192 UTF-8 bytes and the full version-1 artifact allows 16 KiB, including
JSON escaping. Extra/duplicate fields and inconsistent counts refuse before sign-in
or session creation. Import is only for fresh interactive chat, without `--resume`,
`run`, or `demo`. A new root neither transfers nor refunds old budget liability.

An invalid handoff artifact refuses before a session starts: review its closed
version-1 format and size rather than retrying the same file. An invalid committed
handoff record refuses recovery: keep the original journal for investigation.
Neither failure permits editing history to remove provenance checks.

A sealed journal stays sealed after raising limits. Diagnosis/handoff can inspect
valid bounded histories, but oversized legacy files may refuse export. Preserve
them and request developer-assisted source-page inspection; individual source
records have a separate 1-MiB bound. Do not delete records to make them fit.

## Diagnose your setup

Run the offline checks before starting work:

```sh
ipse doctor
ipse doctor --json --cwd /path/to/project --config /private/path/operator.json
```

Use the same `--cwd`, configuration, profile, project-trust, endpoint, MCP and
state-directory options that you use for the intended session. The command
reports runtime identity, discovered configuration files and their parse/trust
status, selected provider/billing, credential presence and expiry, private-directory
modes, native-policy availability, MCP configuration, selected extension artifacts
and bounded session headers. Every finding supplies a recovery route. Exit 1 means
at least one finding failed; warnings and explained skips alone exit 0.

A project file can appear as untrusted even when its settings were refused.
Inspection does not apply those settings or grant trust. Review the file and
the configuration refusal before explicitly trusting it for a session.

The default command makes no network requests, refreshes no credentials, starts
no MCP servers or extension workers, and tests no session locks. Missing private
directories are reported as created on first use; diagnosis does not create them.
An unsafe home/session directory or an auth directory with group/other access
fails. Restore ownership and private modes before starting a session. Operator
configuration readable or writable by others warns; keep it mode `0600` and keep
credentials out of it.

To request reachability checks explicitly:

```sh
ipse doctor --probe-provider --profile YOUR_CONFIGURED_PROFILE
```

This sends bounded metadata GET requests for the selected route and configured
routine/review roles, using the existing TLS/proxy policy and their credential
sources. Each request has a ten-second deadline; response bodies are discarded,
redirects are refused and failures are never retried. No inference occurs.
401/403 indicates credential refusal; other HTTP or connection failures require
endpoint/account inspection. A successful GET does not prove that a particular
model can run. Subscription reachability is skipped and requires a real session;
the demo needs no provider connection.

`sandbox.native` checks the helper and workspace policy. An `ok` finding does
not probe kernel namespaces or establish enforcement. A requested native policy
that fails these checks is a failure; an unavailable optional policy warns.
macOS remains experimental and warns. Check actual command receipts and the
[native-policy prerequisites](usage.md#choose-shell-confinement).

## Diagnose startup and service errors

For a source checkout:

```sh
elixir --version
rustc --version
./dev/build.sh
./bin/ipse demo
```

The source build needs Elixir 1.18+, OTP 27+, Rust 1.85+, a C linker, and access
to locked dependency sources. A bundled release needs a matching OS/architecture/
Linux-libc archive, without the development toolchain. Mix locks and HTTP fixtures
need loopback sockets. If execution policy refuses them, use an appropriately
permitted terminal. Keep TLS verification and test assertions intact.

| Symptom | Recovery |
| --- | --- |
| Configuration file missing, unreadable, invalid or unsafe (operator scope) | Check `--config`, `IPSE_CONFIG` or `IPSE_HOME/config.json`; no task started. Use `ipse doctor --json` with the same options to list discovered source paths |
| Invalid or refused project configuration | Review `.ipse/config.json`; move operator-only endpoint/profile settings to private operator configuration, or use `--no-project-config`. A refusal starts no task |
| Workspace directory does not exist or cannot be read | Pass `--cwd` with an existing readable directory; use `ipse config` to inspect the selected settings before starting work |
| Provider endpoint refused before dispatch | Inspect `ipse config`; choose HTTPS or explicit HTTP loopback without URL credentials, query or fragment; ChatGPT subscription uses its fixed official endpoint |
| Invalid profile field | Fix the named field in the named profile using the [profile examples](configuration.md#reuse-a-named-model-profile); values are deliberately omitted from the error |
| MCP server has an invalid field | Fix its command, URL, allowlists or private environment/header source using the [MCP manual](mcp.md); a numeric server label means its identifier was invalid or private |
| Unexpected error with a stable code | Preserve saved state and report a minimal synthetic reproduction using the final section below; arbitrary error terms and exception messages are withheld |
| Workspace path cannot be resolved | Check directory permissions and symbolic links, then retry with an existing readable `--cwd`; raw paths and filesystem terms are withheld from error prose |
| Expired/refused browser callback | Keep the terminal open and start a new `ipse login`; each callback has five minutes and must reach that host's loopback listener |
| Stale login completion after refresh/logout | Start a new login; do not resubmit an older callback |
| Terminal refresh-token rejection | Sign in again; unusable tokens are cleared while registration is retained |
| Registration or account/workspace rejection | Check the selected registration and account policy; repeated inference does not repair eligibility |
| Subscription usage/plan error | Check account limits and plan permission; the error alone gives no reset time |
| Credential lock busy | Let the other login/refresh/logout finish, preserving lock files |
| Model refused | Choose an available model/profile explicitly, preserving billing choice |
| HTTP clients busy | Wait; an application permits 64 simultaneous clients |
| Stream/body/output bound | Inspect usage and effects before a fresh task; none of that incomplete response's tools execute |
| Ollama data after its completion marker | Treat the response as incomplete; text shown before the error may already be visible, but its proposed tools are not executed. Check the selected service before a new task |

Stream refusals retain safe provider error codes and identifier-shaped messages.
Numeric HTTP error codes such as `429` are retained as well.
Arbitrary provider prose is withheld. Preserve any shown code with the request
identity when reporting a failure; inspect recorded usage before retrying.

Ipse does not switch subscription failures to paid API calls. Supply the matching
API environment variable privately. Include sanitized status/code/request IDs in
reports, not raw provider prose. A refresh awaiting network identity validation
retains credentials privately, without using an unverified identity or consumed
refresh token. If identity expires, sign in again. Unconfirmed logout revocation
may need account-side disconnection.

Auth, inference, and HTTP MCP share proxy policy. HTTPS destinations use
`HTTPS_PROXY`, whose supported proxy URL syntax is `http://`. Encoded proxy
credentials are allowed. An unsupported/failed selected proxy does not fall back
to direct access. Check `NO_PROXY` and browser loopback bypass separately.

For incomplete Ollama answers, compare input plus output tokens, including reasoning,
with the loaded model's context window. Raising output allowance does not enlarge
that window. Inspect actual `context_length` and
[answer policy](configuration.md#allow-a-longer-extension-answer). Keep the failed
outcome before a separately authorized request.

## Diagnose native policy, MCP, and extensions

`--yes` approves effects without broadening native confinement. `/session` reports
visibility. Linux needs Landlock ABI 6+ and permitted user/mount/network/PID
namespaces. Keep the application/helper outside the writable workspace. Helpers
must be user-owned, singly linked, and not group/other writable. On macOS use
an installed bundle outside the candidate checkout; existing `IPSE_HOME` needs
mode `0700`. Unsafe signatures/cache entries or a full 32-generation cache refuse
setup. Do not remove cache generations while work may still use them.

Native commands do not inherit the host environment. Missing home toolchains,
sibling checkouts, caches, or package network access can be expected policy
restrictions. A hidden path is not proof it is absent on the host. Report skipped
checks and follow [shell confinement](usage.md#choose-shell-confinement), without
silently rerunning unsandboxed.

MCP requires explicit `--mcp-config PATH`. Check executable/URL, protocol, exact
item allowlists, schemas, CA trust, and the selected bearer variable. Discovery
installs nothing. Descriptor changes refuse dispatch. Token rotation needs a
restart; automatic reconnect/replay, redirects, and OAuth negotiation are unsupported.
Server sandbox selection is separate from shell policy. Remote work remains
outside local confinement and can be unknown after dispatch. See [MCP](mcp.md).

For extensions, inspect digest, trust, options, selected instance, compatibility,
and `/ext`. Import alone enables nothing. Changed code/options may require a
fresh session. An operator-scope Memory option needs a binding that permits that
scope; compare both when `extension_admission_refused` occurs. See
[Memory configuration](memory.md#configure-project-notes). Resume needs pinned
identities, including builtin license bytes. A logical binding can preserve data
across upgrades without making an old session resumable. See
[extension recovery](extensions.md#recover-without-replaying-unknown-work).

Corrupt budget ledgers and trace catalogs are separate from journals. Preserve
both journal and ledger on budget refusal. Start a new private trace directory
and session for a corrupt ring; do not rewrite old samples. [Capture controls](observability.md)
explain readiness, drops, closure, and retention.

## Report a reproducible problem

Provide the command with secrets removed, application version, OS/architecture,
provider/model, selected sandbox, sanitized error/request ID, and a minimal
sequence using synthetic files. Distinguish executed, failed, denied, and skipped
checks. For capture failures include readiness, drops, closure reason, and cleanup.
Run `ipse version --json` for the version, compiled source commit (when available),
OTP, Elixir, OS and architecture. `ipse --version` prints just the application
version. Build metadata identifies the source base; it does not attest to a clean
checkout or reproducible build.
Never attach auth files, authorization URLs/codes, environment dumps, hidden
reasoning, or complete private journals.
