# Inspect sessions and recover safely

Inspect the workspace and recorded outcomes before continuing interrupted work
or recovering from a context refusal. The original journal remains the evidence;
do not repeat an uncertain effect just to reconstruct its output.

## Inspect current or saved state

In interactive chat, `/diagnostics` shows phase, active worker, step budget,
approval/question waiting and a content-free byte breakdown of the effective
request. Categories add exactly to encoded JSON size, including escaping and
framing. These are bytes, not provider token counts. Native continuation is counted
without displaying hidden content. No inference or tool call is made.

Inspect a saved session locally without starting/resuming it:

```sh
./bin/ipse diagnose --resume SESSION_ID --state-dir /path/to/sessions
```

Saved diagnostics restore validated compaction projections and count unknown
calls without repairing a truncated tail or writing state. They exclude the
current system instruction/catalog because that can change between invocations;
the scope field says `effective_transcript_without_system`. A recorded configuration
supplies its context ceiling; legacy embedded sessions without one are labelled
`default_not_recorded`. No raw prompts/results, credential data or native reasoning
are exported. Up to 16 validated model/compaction duration measurements show
completed, failed or cancelled requests. They measure owned request work, not
tool execution or operator approval wait; they are not full distributed tracing.
Saved diagnostics also include [normalized request accounting](usage-accounting.md),
with partial usage and unknown outcomes, separately from context bytes.

## Handle uncertain effects and journal state

Loss of a shell helper, invalid/incomplete helper output, or an unexpected tool
worker failure can leave an effect unknown even when an error was displayed.
Inspect files and external systems before explicitly retrying; resume does not
rerun the action. Validation/setup refusals remain known failures. New malformed
or duplicate tool-call IDs stop the response before any approval or execution.
New IDs must be valid UTF-8 and occupy 1–256 bytes, including for questions and
extension tools. IDs are opaque and may contain Unicode or punctuation. Older
oversized pending questions are not silently rewritten; use saved diagnosis and
an explicit fresh-session handoff if the original checkpoint cannot be resumed.
Older duplicate IDs never allow one saved result to settle two calls; unmatched
history remains unknown and the original transcript stays intact.

A running session exclusively owns its journal. Do not edit or append it from
another program while the session is active. Its append process checks file
identity, protection and expected length and stops on detected changes; it does
not revalidate a same-size rewrite on every write. Resume still validates saved
history before accepting work. A journal acknowledgment that fails or exceeds
five seconds stops the session as `journal_unavailable`; it never retries the
record. The record may already have reached disk. Shutdown stops the writer
before releasing the session lock, then resume inspects the durable history.
An unrecorded result remains unknown. Storage can still delay writer termination
and cleanup confirmation; an error is not permission to repeat an uncertain effect.

A missing Session acknowledgment also leaves uncertainty: an approved request
may already have taken effect. The CLI reports this explicitly, exits nonzero,
does not retry and attempts bounded cleanup. The reader stops, and the Session
monitors its owning CLI process. Slow storage or sequential child/transport
cleanup can still outlast the caller's deadline; an unconfirmed-cleanup notice
requires inspection of receipts, the workspace and running processes. The
provider `--timeout-ms` option does not change these Session call deadlines.
Task-owned shell and extension helpers must acknowledge cleanup; task death
alone cannot confirm their exit. A missing acknowledgment stops the Session
with cleanup unconfirmed. Inspect running work before starting another attempt;
this does not expand the documented detached-descendant containment limits.

Journal retention grows independently of the context window. There is no
automatic journal rotation or disk quota. Context compaction does not delete
that evidence or implement forgetting. For long work or a context refusal that
safe compaction cannot resolve, continue through a reviewed fresh-session handoff.

## Continue in a fresh session

Write a short operator-reviewed note with the remaining goal, decisions, relevant
files and unresolved effects:

```sh
./bin/ipse handoff --resume SESSION_ID --state-dir /path/to/sessions \
  --note 'Continue the reviewed CLI change. Inspect the pending write before retrying anything.' \
  > /private/path/handoff.json
```

The parent directory/output permissions are the shell operator's responsibility;
use a private directory and `umask 077` when creating the artifact. The UTF-8 note
is required and bounded to 8192 bytes; the entire encoded artifact is limited to
16 KiB, so heavily escaped notes can require shortening. The artifact records source ID,
a digest of complete decoded source events, unknown-call count and up to 16
bounded call identifiers, with an omitted count. This is not a raw-file checksum
or a signature. It deliberately excludes tool arguments, results, provider data,
auth and saved permission settings. The note itself can be private: this is not
an automatic secret scanner or automatic model-generated summary.

Review the artifact and source workspace, then explicitly import it into fresh
interactive chat with your selected current provider and configuration:

```sh
./bin/ipse chat --handoff /private/path/handoff.json --cwd /path/to/candidate
```

`--handoff` is accepted only for fresh interactive chat (including the default
chat command). It cannot be combined with `--resume`, `run`, `demo`, or another
command mode. Validation occurs before authentication or session creation. The
input must be one closed version-1 UTF-8 JSON object of at most 16 KiB: extra or
duplicate keys, malformed fields and inconsistent unknown-call/omission counts
are rejected. The note remains verbatim, including whitespace, with an 8192-byte
limit. Source IDs/digests and the capped unknown-call references are preserved;
the digest is provenance, not proof that the source history was independently
verified.

Import starts a new, idle session and displays the source identity and unknown
call count. **Type a fresh operator prompt to begin work.** The note enters as
attributed untrusted historical context, not a new task or privileged instruction.
No source session is opened, no saved call is replayed, and no provider settings,
credentials, approvals, tools or native continuation are transferred. Current
configuration and ordinary action approvals still apply. Starting a fresh session
does not resolve source unknown outcomes; inspect effects before retrying them.

The new journal saves the exact validated artifact bytes, their digest and the
historical-context projection once. Later resume validates that saved record
without reopening the import path, even if its file changed or was deleted.
Resume normally with `chat --resume NEW_SESSION_ID`, without `--handoff`.
A corrupt, duplicated or misplaced committed import refuses recovery rather
than silently discarding historical context. Keep the original journal for
inspection. Corrupt committed compaction/research checkpoints also refuse export.

The P18 private Mac transcript was not copied to Serenity. A synthetic long-turn
fixture reproduces the retained-native-data failure shape, with exact diagnostics;
this does not establish which byte category dominated that original live run.
See [developer details](../developer/context-compaction.md#diagnostics-and-explicit-handoff)
and [verification](../developer/testing.md#p19-diagnosis-and-explicit-recovery).
