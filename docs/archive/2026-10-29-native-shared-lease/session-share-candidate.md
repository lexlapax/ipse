# Session lock sharing and Writer barrier candidate

2026-10-29 implementation checkpoint. This section is **not** a production
managed-display or worker-delivery qualification. The [plan](../../plan.md)
owns completion; the [accepted terminal design](guarded-terminal-integration-independent-review.md)
still requires a Session/Host operation barrier, exact owner controls and actual
operator reader/guardian closure. All protected-output and management-effect
gates remain closed.

## What is implemented

New private Linux header/resume helper modes acquire the Session's original
flock from startup; no existing live helper is closed and reacquired. They keep
the existing native-owned header creation, source identity, journal append,
repair and framed release. A single `Y` shares that held open description, and
matching `K` waits for the retained native peer's close/settlement handshake.
Any other source command while shared terminates unconfirmed. The source helper
requires a strictly increasing 64-bit per-owner share ordinal, with explicit
overflow refusal; it does not inherit the Transaction prototype's 256-ID
lifetime limit. The trusted Lock guard derives a fresh 128-bit transport ID
from a private 128-bit owner epoch, that ordinal and the caller's operation.
That transport ID can bind the other three management leases to the same inert
collector. The native export accepts a bounded remaining setup time, while the
host checks its own deadline; a future caller must still enforce one common
deadline across the complete multi-owner operation.

`Writer.request_share_barrier` is an asynchronous owner request. Once prior
Writer operations have drained and its journal identity is rechecked, it
returns an opaque token and snapshot containing the exact journal identity,
offset, count, source-window snapshot, job reference and owner generation.
While frozen, Writer rejects further writes and source operations. `Session.Lock`
only arms the exact tracked Writer's token, blocks new tracked work and journal
IO while armed/shared, and permits Writer thaw only after matching native
settlement or cancellation before export. A premature thaw request is
asynchronous within Writer, avoiding a Writer/guard cycle. A failed or lost
export, close or release remains unconfirmed; `LOCK_UN` is never used.

The host-only `Session.start_share_candidate_link` selects these modes for
fresh/resumed candidates. Normal CLI/config/worker startup still chooses the
existing modes. Same-VM host code is trusted; the hidden function and direct
GenServer init are not an access-control boundary. No worker SDK bridge selects
this candidate. An old pinned helper without the new mode refuses before
creating a journal. No fallback closes/reacquires a live lock.

## What remains open

This is a Writer/Lock primitive and candidate Session selector, **not** the
required production Session state machine. No actual Host job can yet establish
the nonblocking operation-bound Session barrier, freeze every proof/job mutation,
poison immediately on cancellation, or hand the exact Session and Host EOF
controls to a tty guardian. `:sys.replace_state` in the Session tests is a
test-only probe executed inside the real Session process; its synthetic job
references do not demonstrate a genuine Host job or responsive Session barrier.
There is no actual forked reader/guardian all-copy close, fixed safe redraw,
full-facts native Review display or Management journal conversion here. The
four-owner management route and generic 132-description route remain gated.
Retained native recipient authentication still depends on trusted pinned-mode
and exact operation/role integration, which this single-process collector does
not establish. Current Linux controls do not qualify other platforms.

## Focused evidence

The [verified evidence manifest](evidence/session-share-candidate/manifest.sha256)
contains final source and matching helper, runtime inventories and selected
logs. A genuine candidate Session starts from its native header owner, runs a
credential-free fixture prompt, closes and resumes with the same lock inode and
unchanged header. Its actual Writer/source-window snapshot refuses a foreign
caller and supports a safe pre-export cancellation. A synchronized premature
thaw/arm control confirms that Writer and its guard do not deadlock.

Real native Unix-socket tests cover repeated header shares, resumed-lock share,
recipient close/thaw and owner death. In the Session-owner loss case, the test
first uses the test-only in-process probe to share the real Session's lock, then
stops the recipient and kills the actual Session. After its guard exits, an
independent contender remains blocked until the native recipient resumes and
exits. The lock and stored journal are never reconstructed or replayed. The
older pinned helper refusal leaves no fresh journal. Ordinary legacy-mode
Session startup/close/resume was checked separately on its earlier graph.

The first socket control returned unconfirmed before collection; a diagnostic
run succeeded after observation delayed the recipient, consistent with querying
an Erlang Port PID before the child had exec'd the pinned helper. The new
private collector mode sends an operation-bound readiness frame before exports;
it does not grant activation. The original failure and diagnostic are retained.
The initial old-helper fixture exited through its linked startup failure; the
corrected fixture traps that synthetic test process exit and confirms refusal.
No external model, service or aggregate suite ran.

The final helper was built with `rustc --edition=2021 -D warnings
native/ipse-runner.rs -o /tmp/ipse-session-share-helper-v3`. The pinned standard
graph is `_build/session-share-candidate-v4-sol-20261029`; `Runner` was compiled
against its matching private helper, then the exact Lock and Writer sources
were compiled into it. Session was compiled in the earlier candidate graph from
the same source snapshot. The separately inventoried old-helper graph uses its
old helper with newly compiled candidate modules. Earlier incremental logs do
not claim their source is identical to the final snapshot. Unix-socket cases
ran outside the sandbox's socket restriction; the native sandbox tag is excluded
from ordinary fixture execution.

The final affected selections ran with the absolute graph path:

```sh
ERL_FLAGS='+S 4' ERL_LIBS=/home/lexlapax/projects/lexlapax/ipse/_build/session-share-candidate-v4-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); Code.require_file("test/ipse/session/share_barrier_test.exs")'
ERL_FLAGS='+S 4' ERL_LIBS=/home/lexlapax/projects/lexlapax/ipse/_build/session-share-candidate-v4-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); Code.require_file("test/ipse/session/share_candidate_test.exs")'
ERL_FLAGS='+S 4' ERL_LIBS=/home/lexlapax/projects/lexlapax/ipse/_build/session-share-candidate-v4-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); ExUnit.configure(exclude: [:test], include: [native_sandbox: true]); Code.require_file("test/ipse/session/share_barrier_test.exs"); Code.require_file("test/ipse/session/share_candidate_test.exs")'
IPSE_SESSION_SHARE_OLD_HELPER_TEST=1 ERL_FLAGS='+S 4' ERL_LIBS=/home/lexlapax/projects/lexlapax/ipse/_build/session-share-old-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); Code.require_file("test/ipse/session/share_candidate_old_helper_test.exs")'
```
