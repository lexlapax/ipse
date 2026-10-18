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
calls, including unknown actions retained inside validated summary checkpoints,
without repairing a truncated tail or writing state. They exclude the
derived system/reference headers; these are reconstructed for a live request,
while saved instruction and skill snapshots remain separate recovery inputs;
the scope field says `effective_transcript_without_system`. A recorded configuration
supplies its context ceiling; legacy embedded sessions without one are labelled
`default_not_recorded`. No raw prompts/results, credential data or native reasoning
are exported. Up to 16 validated model/compaction duration measurements show
completed, failed or cancelled requests. They measure owned request work, not
tool execution or operator approval wait; they are not full distributed tracing.
Saved diagnostics also include [normalized request accounting](usage-accounting.md),
with partial usage and unknown outcomes, separately from context bytes.

Resume also requires the saved provider destination. Repeat the original
`--base-url` or restore its operator profile; dropping or changing that route is
refused before inference. Older sessions use recorded request endpoint hashes
where available. An idle legacy session cannot prove its unrecorded direct route;
implicit-default legacy resume is retained for compatibility and cannot detect
an earlier custom-to-default change in that request-free history. Use a fresh
reviewed session if its original route is unknown; unverifiable custom routing
is refused.

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
record. The record may already have reached disk. A separate lock guardian survives abrupt Session death, stops tracked workers
and waits for writer/scopes/resource and child-guard exits before unlocking.
Already admitted core filesystem operations have separate completion owners that
retain the lock until the operation returns, even if the original worker is dead.
Resume can therefore remain locked after the Session PID disappears. It must not
start a second writer or overlapping owned task. Then resume inspects durable history.
An unrecorded result remains unknown. Storage can still delay writer termination
and cleanup confirmation; an error is not permission to repeat an uncertain effect.

A missing Session acknowledgment also leaves uncertainty: an approved request
may already have taken effect. The CLI reports this explicitly, exits nonzero,
does not retry and attempts bounded cleanup. The reader stops, and the Session
monitors its owning CLI process. Slow storage or sequential child/transport
cleanup can still outlast the caller's deadline; an unconfirmed-cleanup notice
requires inspection of receipts, the workspace and running processes. The
provider `--timeout-ms` option does not change these Session call deadlines.
Known helper launch refusals before any process starts return an ordinary error;
they do not create a cleanup failure. Commands and lock paths containing invalid
UTF-8 or NUL bytes are refused before launch. Once started,
task-owned shell, lock, extension and MCP helpers must acknowledge cleanup,
including helpers started by nested workflows; task or Port disappearance alone
cannot confirm exit. A missing acknowledgment stops the Session
with cleanup unconfirmed. Inspect running work before starting another attempt;
this does not expand the documented detached-descendant containment limits.
After a stdio terminal result, cleanup waits passively for the actual helper exit
within the existing deadline; it does not write cancellation into already closed
stdin. A terminal frame alone, a forced exit or a missing exit receipt still cannot
confirm cleanup. Task-owned HTTP guardians similarly wait for their borrower, private pool and
its monitored child processes before releasing the client slot. If the pool
supervisor disappears, the provider Session stops conservatively; explicitly
resume it idle, inspect the recorded outcome, then send fresh input. Nothing is
retried automatically. Local socket cleanup cannot establish whether remote work
stopped. A stuck local process can keep the Session lock held beyond a caller
timeout; inspect running work and do not delete lock files to bypass ownership.

Valid diagnostic sink receipts and prompt-source checkpoints can coexist with a
pending extension question. Saved diagnosis/handoff validate those independent
records without answering the question or starting callbacks. Older builds could
refuse these combinations as invalid extension actions. Inspect them with the
updated read-only commands; an incompatible extension identity can still prevent
activation, so use an explicit reviewed handoff rather than editing the journal.

Journal retention grows independently of the context window. Mandatory per-file
byte, event and record-size bounds now stop and seal a journal before further
work; operator configuration can lower the finite host ceilings. Saved diagnosis
shows `journal_limit` with the sealed reason and enforced limits, or null when no
limit receipt was recorded. A sealed journal cannot resume or accept an answer;
use the explicit handoff below after inspecting uncertainty and ask unanswered
questions again. No answer/effect is retried automatically. Legacy files over
the host ceiling are preserved and refused; whole-history diagnosis/export is
unavailable. Source-page inspection has a separate 1 MiB record bound, so larger
records need developer-assisted bounded inspection and reviewed notes for a fresh
session rather than a validated automatic handoff. Listing reads a bounded
header even when the later file cannot be restored, so listing is discovery,
not validation of that history. See [journal limits](configuration.md).

There is no automatic rotation or whole-directory disk quota. Context compaction
does not delete evidence or implement forgetting. Startup validates history and can
be slow: a synthetic 64 MiB journal with 200 answered questions took about 20
seconds on Serenity. This is a measured case, not a latency guarantee. For long work or a context refusal that
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
bounded call identifiers, with an omitted count. This includes unknown actions
retained inside validated compaction checkpoints, preserving call occurrences. This is not a raw-file checksum
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
