> Historical only. Preserved on 2026-10-22 from `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` before the structural/manual rewrite. Use [current guidance](https://github.com/lexlapax/ipse/blob/main/docs/operator/recovery.md). Relative prose links point to the original commit; commands and claims retain their original text.

# Inspect a session and recover work

After an interruption, inspect the workspace before asking Ipse to continue.
An error can mean an effect completed without a recorded result. Resume preserves
that uncertainty and never automatically repeats the action.

## Find the session and inspect it locally

Use the state directory from the original invocation. Without `--state-dir`, the
store is `IPSE_HOME/sessions`, normally `~/.ipse/sessions`.

```sh
ipse sessions --json --state-dir /private/path/sessions
ipse diagnose --resume SESSION_ID --state-dir /private/path/sessions
```

Replace `SESSION_ID` with an ID from the listing. These commands do not sign in,
make model requests, execute extensions, or repair journals. Listing reads bounded
metadata; a listed session can still fail whole-history validation.

Diagnosis shows the saved phase, unknown-call count, context-byte categories,
accounting, recent request durations, and any recorded journal-limit receipt.
Its context scope is `effective_transcript_without_system`: reconstructed live
system headers are excluded. Bytes are not provider token counts. Duration
measurements cover owned model/compaction work, not all tool work or approval
waiting. No prompts, results, credentials, or hidden reasoning are exported.

For a live session, `/session`, `/diagnostics`, `/context`, and `/info` provide
local inspection. They make no inference. Keep journals private even when the
standard diagnostic display contains no conversation text.

## Distinguish an unstarted action from an unknown effect

A validation, configuration, or setup refusal before execution is a known
failure. A tool shown as `not_started` did not execute that proposal. A missing
result after intent, transport loss, timeout, incomplete output, or worker failure
can leave the outcome `unknown`.

For an unknown file write, read the actual target and compare it with the proposed
content. For shell work, inspect files and running processes. For remote MCP,
inspect the service's records as well. A closed local connection does not prove
remote work stopped. Ask for another action only after deciding what remains
necessary. Do not repeat work just to recover a lost display.

Cancellation stops owned tasks and ordinary process groups. Detached descendants
can remain. Cleanup acknowledgments are separate from task/VM exit and from the
success of the requested work. If Ipse reports cleanup unconfirmed, resolve
running work before starting an overlapping attempt.

## Resume compatible saved work

```sh
ipse chat --resume SESSION_ID --state-dir /private/path/sessions
```

Repeat the original explicit configuration, MCP selection, endpoint, and temporary
extension selection when applicable. Resume retains the original workspace,
provider/model, sandbox, delegation settings, and instruction snapshots. Changed
configuration digests or pinned extension/runtime identities can refuse recovery.
Restore the original inputs or use a fresh handoff. Do not edit saved records to
remove a mismatch.

Idle resume reconstructs history without provider requests, callbacks, children,
or tool replay. Pending structured questions reappear for an explicit answer.
A recorded answer survives interruption, but ordinary idle resume does not start
inference automatically. Use interactive chat for a pending question; headless
`run` cannot answer it.

A torn final journal record can be repaired during validated ordinary resume
under the session lock. Corrupt committed records or checkpoints refuse recovery.
Read-only diagnosis does not repair the tail. Preserve the original files for
investigation rather than deleting suspect records.

## Respect the session lock

One active owner holds the journal lock. Close or cancel the other session
normally. A lock can remain held after the visible Session process disappears
while tracked work, storage, or cleanup is still settling. An approved operation
may still complete during that time.

Do not delete lock files, truncate journals, or open a second writer to force
resume. Locks release through ownership, while the persistent file preserves
its identity. Missing acknowledgments and `journal_unavailable` mean a record
may already have reached disk. Ipse stops and does not retry it. Slow storage can
outlast caller deadlines; `--timeout-ms` changes provider deadlines, not those
storage/Session calls.

## Continue in a fresh session

Use a handoff when required history cannot fit, a journal is sealed, or a reviewed
configuration/runtime change prevents compatible resume. First inspect unresolved
effects. Write your own concise continuation note with the goal, decisions,
relevant files, and remaining uncertainty.

Create the output in a private directory. The shell controls output permissions:

```sh
umask 077
IPSE_RECOVERY_DIR=$(mktemp -d)
ipse handoff --resume SESSION_ID --state-dir /private/path/sessions \
  --note 'Continue the reviewed CLI change. Inspect hello.exs and the pending shell effect before retrying. Preserve existing edits.' \
  > "$IPSE_RECOVERY_DIR/handoff.json"
cat "$IPSE_RECOVERY_DIR/handoff.json"
```

Review the note and provenance, then import it with your deliberately selected
current provider and configuration:

```sh
ipse chat --provider chatgpt --cwd /path/to/project \
  --handoff "$IPSE_RECOVERY_DIR/handoff.json"
```

This starts a fresh idle conversation. Type a new task to begin. The example uses
real subscription inference only after you submit that task. The note is
attributed historical context; it does not become an action request or transfer
credentials, approvals, tools, provider settings, or native continuation.

The export includes source ID, a digest of decoded source events, unknown-call
count, and up to 16 bounded unknown-call references with an omission count. It
excludes original arguments/results and provider data. The digest establishes
provenance, not authenticity or independent review. Your note itself can contain
private information; no automatic secret scanner reviews it.

The UTF-8 note is at most 8192 bytes and the entire version-1 artifact at most
16 KiB. Escaping can make a shorter note exceed the encoded limit. Extra or
duplicate fields and inconsistent unknown-call counts are rejected before
sign-in or session creation. Import works only for fresh interactive chat;
it cannot combine with `--resume`, `run`, or `demo`.

The new journal saves the validated artifact once. Later use normal
`ipse chat --resume NEW_SESSION_ID`; the original handoff path is no longer
required. A fresh session does not resolve source uncertainty or refund its old
[budget liability](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/budgets.md).

## Recover from storage and identity limits

A journal sealed at its byte/event/record limit cannot resume, even after limits
are raised. Diagnosis and handoff can inspect valid bounded histories. Oversized
legacy files may refuse whole-history export too. Ask a developer for bounded
source-page inspection and prepare a reviewed manual note if automatic handoff
cannot validate the file. Source-page reads have their own 1 MiB record bound.

Extension sessions pin exact artifacts, options, host API, and runtime identity.
Keep a matching frozen runner for old sessions. Changing built-in license bytes
also changes identity. A reviewed logical memory binding can preserve note data
across versions, but does not make an old session resumable. See
[extension upgrades](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/extensions.md#recovery-and-execution-boundaries) and
[memory migration](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/memory.md#export-migrate-and-upgrade).

Budget-ledger corruption is a separate refusal. Preserve both ledger and journal;
a handoff can continue a validated conversation without repairing or activating
the damaged tree. Diagnostic trace-ring corruption likewise needs a fresh trace
directory and session, not journal editing. See [Diagnostic capture](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/observability.md).
