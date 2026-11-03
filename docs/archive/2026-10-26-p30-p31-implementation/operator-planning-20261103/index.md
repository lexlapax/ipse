# Deferred operator-authored planning decisions

Dated **2026-11-03**. This is an author-run, synthetic component record for
committed base `c37e14520764ee7df256074b76a1d7d1e8b79024` plus the 13 exact
source, test and manual files in [the final overlay manifest](overlay.sha256).
It records development-source behavior, not a completed milestone or release.
The [plan](../../../plan.md) owns remaining acceptance; current procedures and
implementation guidance belong to the [operator manual](../../../operator/usage.md#plan-before-acting)
and [developer manual](../../../developer/workspace-context.md#withdraw-draft-intent-before-ordinary-work).

## Scope and recovery boundary

A native operator can write and separately accept an exact decision during a
locally entered planning ceiling. The accepted event retains the original
planning entry and both native observations, and is not itself an indexed source
or knowledge publication. Ordinary `/plan exit` makes no publication. A separate
post-exit `/plan save ID` review checks the normal active and enclosing ceilings,
current source and permission, then records a one-shot save intent and a linked
operator assertion. Existing protected literal capture can store the exact text
as an ordinary operator-authored note, with the complete original acceptance
receipt retained in the asserted source proof.

Cancelling before the save intent leaves the decision available for another
explicit review. A witnessed pre-worker refusal is recorded separately from an
unresolved intent. An attempted save is never automatically repeated, including
on resume, and the same decision ID cannot be reused for another attempt. An
intent alone does not prove a worker started. In replay, any later extension
invocation conservatively fences a subsequent claim of an unstarted refusal; the
`later_invocation_seen` bit does not identify which decision caused that later
invocation. A previously witnessed refusal remains known. The operator must
inspect the journal and stored state when an attempted save's outcome is unclear.

This slice accepts words authored by the operator. It does not implement
accepting an assistant-proposed decision or create an accepted-proposal/link
record. Full planning and prompt-assistance acceptance, installed and independent
human use, current-source combinations beyond these controls, and the larger
integrated workload remain open.

## Evidence and fixture corrections

A fresh test build in `/tmp/ipse-p31i-c37.pq2HFHyS` used copied dependencies,
a separate build and home, the native helper and freshly built bundles. The
knowledge bundle manifest digest was
`5202d996cd4d5ef0d8724fa04032d035b6f95cf1cc6cb11d29e4a10b5644ce29`.
`mix compile --force --warnings-as-errors` and the whole-snapshot
`mix format --check-formatted` passed. Dependency compilation emitted upstream
warnings; they were not project compile warnings. Mix required loopback TCP for
its lock, so these commands and the native tests ran with local socket access.
No paid or live provider was called.

The initial single native save test, seed `176246`, actually saved a protected
literal and printed completion, but the fixture timed out: the
terminal had already displayed its next prompt before the asynchronous result.
The PTY fixture was corrected to recognize that existing prompt; the focused
[rerun](plan-save-prompt-fix.log), seed `176247`, passed and completed the source
proof and resumed-session checks. This was a test-driver synchronization fix.

The next control batch, seed `176249`, passed nine of ten cases but the
query-failure fixture failed during teardown. It had
successfully produced the intended pre-dispatch refusal, but left its injected
journal-writer proxy as owner when asking for a confirmed close. The fixture now
restores the original Session owner and stops the proxy before normal teardown.
Its [focused rerun](plan-query-proxy-fix.log), seed `176250`, passed. No
production authority or failure policy changed for either fixture repair.

The raw synthetic terminal failure logs remain in the temporary test snapshot
rather than the repository because they contain one-use review codes. The
`plan-save.log` SHA-256 is
`44af33a63e3e83c48cffdd5b3d374c8c7e17de3b08a63d28aa559d315c80f03c`;
the `plan-controls.log` SHA-256 is
`3bbf815d84d2df061889741c96b5bc34c84ec6540885a4079ca34cd452003bb9`.

On the final fingerprinted source, the [complete native planning group](plan-native-final.log)
passed **11 tests**, seed `176251`, in 14.9 seconds. It covers successful protected
save and linked original receipt, ordinary exit, cancellation and stale review
codes, permission revocation, source replacement, separately injected source-query
and intake refusals, interruption and inert resume. The focused
[planning, assertion, source and terminal regressions](plan-regressions.log)
passed **95 tests**, seed `176252`, in 378.3 seconds. Test exceptions printed in
that log are exercised test paths; ExUnit reported zero failures.

Independent one-scheduler Elixir runs, without Mix, native helpers, sockets or
application startup, passed three initial pure decision replay tests at seed
`176243`, four pure transition tests at seed `176244`, and four pure decision
replay tests at seed `176245` after the conservative-state clarification. The
latter two commands and source-loading boundaries are retained in the
[transition receipt](transition-pure-receipt.txt) and [decision receipt](decision-pure-audit-receipt.txt).
Those pure results do not establish Session behavior. After the manual edits, a
[sanitized documentation check](docs-audit-receipt.txt) found zero errors across
1,084 Markdown files and 8,913 local links.

The final 13-file manifest matched both the isolated snapshot and shared source
after the tests. Its SHA-256 is
`41b94af2fa38a43d02f2f3756a63caceb3c382c6f7f4973b0be2f4e7aecd5911`.
A subsequent whole-document review clarified command limits, exact provenance,
recovery and entry points. The two manuals and audience indexes therefore differ
from the tested snapshot; all eleven code and test fingerprints still match.
A second sanitized check after that editorial review passed 1,086 Markdown files
and 8,936 local links with zero errors.
A complete project test suite, demo, human validation and broader planning
acceptance were not run or established by this record.
