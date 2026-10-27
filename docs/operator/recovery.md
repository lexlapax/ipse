# Diagnose and recover interrupted work

Inspect the workspace and any external service before asking Ipse to continue.
An effect can finish without a recorded result. Resume preserves that uncertainty
and never automatically repeats the action.

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
| Model request | Keep recorded usage/liability, including failed or incomplete responses |

Do not repeat a producer merely to recover a lost display. Cancellation stops
owned tasks and ordinary process groups. Detached descendants can remain.
Cleanup acknowledgment, process exit, and successful work are separate facts.
Resolve unconfirmed cleanup before overlapping another attempt.

## Inspect unconfirmed protected knowledge

Keep the original Ipse home, protected control/identity/collection files and
Session journal. A lost confirmation can leave a saved grant, a durable note,
pending liability or a prepared first-use domain. It does not prove absence.
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

Do not enable again merely to recover a missing confirmation, delete retained
locks or domain keys, reset the collection, edit a ledger, or replay the old
capture. The operator CLI has no automatic prepared-domain or unknown-operation
reconciliation command. Request developer-assisted inspection of the exact
operation and actual storage root before deciding on another attempt. Keep
private files local; report sanitized codes and operation IDs instead of their
contents. [Knowledge permissions](knowledge-permissions.md) explains known
configuration conflicts that can be resolved with a fresh review.

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

## Respect active ownership

One owner holds the journal lock. Close/cancel it normally. The visible Session
can disappear before storage or tracked work settles, and an approved effect
may still complete. Never delete lock files, truncate records, or open another
writer to force resume. Persistent lock files preserve inode identity.

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
