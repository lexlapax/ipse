# Context diagnosis and explicit handoff

When compaction refuses to fit retained context, the original journal remains
intact. Do not repeat an effect just to reconstruct output. First inspect the
actual workspace and recorded outcomes, including unknown calls.

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

If safe compaction remains impossible, write a short operator-reviewed note with
the remaining goal, decisions, relevant files and unresolved effects:

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
