# Independent review of inactive Session-lock startup

2026-10-29. This scoped review covers the frozen
[inactive Session-lock candidate](session-start.md), not an integrated Session
or P31 acceptance. The source and both runtime manifests verified locally.
The candidate acquires the export-capable helper on its first acquisition;
the focused controls support cross-process exclusion and retention after owner
death while a tracked peer remains. Actual Session startup still uses the legacy
path, so this is not a Session/Writer/export integration test.

The review found a concrete integration blocker: the candidate releases through
the generic `Runner.unlock/1` path, which discards release frames and reports a
successful lock-helper exit as success. After descriptor export, the native
helper can report an unconfirmed release while the recipient still retains the
lock; the generic path would report `:ok`. A versioned framed release and
unknown outcome are required before connecting an exporter.

The focused controls did not cover malformed or partial release frames, owner
death during startup, helper-death notification, low descriptor limits, actual
Session/Writer startup or non-Linux execution. The new mode requires a strict
32-hex lock filename and protected parent traversal; those requirements fit the
current Session ID format but are narrower than the legacy helper. The recorded
`--no-compile` commands depend on retained build graphs; a clean-checkout
reproduction needs a pinned rest-of-tree revision and reconstruction commands.
The candidate and both affected user paths remain inactive while these findings
are repaired and tested.

## Genuine Session follow-up review

The later independent review verified the genuine Session cohort and both
runtime inventories. The controls support the narrower claims in the
[host-internal follow-up](session-start.md#host-internal-genuine-session-control):
first acquisition uses the candidate, Writer shutdown precedes lock release,
and a real recipient keeps the lock exclusive until it closes. Its candidate
lifecycle record is deliberately unconfirmed. The test injects the recipient
through a raw native Port, not a production handoff.

The reviewer found that a fresh candidate Session creates its JSONL journal
before attempting the lock. An unsupported older helper can therefore refuse
startup without fallback while leaving an orphan journal; the earlier control
checked only absence of the lock file. The host-internal selector is also an
exported BEAM API, and direct GenServer initialization can bypass the outer
startup registry revalidation. It is safe only under an explicit same-VM trust
boundary or an enforced host-only binding. These findings are being addressed.
The controls did not inject an in-flight Writer file-effect peer or active task
cancellation during close, and did not execute on non-Linux. The frozen source
tar and evidence remain untracked until the eventual commit.
