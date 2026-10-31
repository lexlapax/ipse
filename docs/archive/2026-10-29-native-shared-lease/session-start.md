# Inactive export-capable Session lock candidate

Dated 2026-10-29. This is a focused candidate, not an enabled Session feature,
managed-output admission, or P30/P31 acceptance. The
[current plan](../../plan.md) remains authoritative.

The Session candidate described in earlier observations below is now refused
at `init` after the [header owner-loss finding](#fresh-header-owner-loss).
The later [native header follow-up](session-header-native.md) changes Linux
ordinary fresh startup; references below to its earlier ordering are historical.

The later [independent review](session-start-independent-review.md) found that
the generic release path could report success after an exported lock's native
release was unconfirmed. The framed release repair and its focused controls
are recorded below. Ordinary Session startup still uses the legacy lock.

The internal `Session.Lock.acquire_export_candidate/1` starts its guard with a
Linux-only pinned `--lock-export-v1` helper from its first lock acquisition.
There is no release and reacquisition or fallback to `--lock` in this path.
Ordinary Session startup still calls `acquire/1` and uses the legacy helper.
Non-Linux candidate calls refuse; no non-Linux execution was tested. The
candidate is not connected to a descriptor export caller or a managed output
path. A live Session already holding a legacy helper is not migrated.

The [focused Linux fixture](evidence/session-start/focused-test-retry.log)
passed two tests. A separate native helper was refused the same lock while the
candidate owner lived, and again after that owner was killed while a tracked
peer remained. The tracked worker was killed, the guard stayed live for the
peer, the lock inode stayed unchanged, and another helper acquired the lock
after the peer exited and the guard stopped. An invalid source-lock name
refused without creating a legacy lock. The unchanged legacy acquisition also
passed its [existing focused regression](evidence/session-start/legacy-regression.log).
These observations support exclusion and cleanup at the tested boundaries; they
do not prove any descriptor-export handoff or owner-fenced output.

A separate graph pinned to the prior native helper reported
[`EXPORT_START_UNAVAILABLE_NO_FALLBACK`](evidence/session-start/unavailable-formatted.log):
the candidate refused before creating the lock, then explicit legacy acquisition
succeeded. The earlier helper binary SHA-256 was
`a51c2d34654e21b0418b31bbe5ec2423d117230a3a8f3687803d5c1438d1c12e`, matching
the [earlier runtime record](../2026-10-26-p30-p31-implementation/managed-actions-document.md).
That record identifies the binary; this test does not claim to reconstruct its
complete native source. The candidate graph's helper is the ordinary disabled
output cohort whose matching native source is in the
[output experiment snapshot](evidence/output/source-v6.tar).

The [focused source snapshot](evidence/session-start/source.tar),
[manifest](evidence/session-start/manifest.sha256),
[candidate runtime hashes](evidence/session-start/runtime-start.sha256), and
[old-helper runtime hashes](evidence/session-start/runtime-legacy.sha256)
identify the two isolated graphs and retained logs. The graphs and binaries are
under `_build/session-export-start-sol-20261029/` and
`_build/session-export-legacy-sol-20261029/`. The first compilation attempt
reported a stale Operator module; the next had a test harness result-shape
mismatch despite no compile warnings. The [final compile](evidence/session-start/compile-final.log)
passed. The first Mix test attempt hit the sandbox's local TCP EPERM; the
focused retry ran outside the sandbox. The exact test commands were:

```sh
ERL_FLAGS='+S 4' MIX_ENV=test MIX_BUILD_PATH=_build/session-export-start-sol-20261029 mix test --no-compile test/ipse/session/export_lock_test.exs
ERL_FLAGS='+S 4' MIX_ENV=test MIX_BUILD_PATH=_build/session-export-start-sol-20261029 mix test --no-compile test/ipse/runner/protected_lease_test.exs:50
ERL_FLAGS='+S 4' MIX_ENV=test MIX_BUILD_PATH=_build/session-export-legacy-sol-20261029 mix run --no-compile dev/verification/session_export_unavailable.exs
```

Before integration, the caller must preserve original source existence and
identity validation, bind actual Session ownership, track export and unknown
release correctly, and resolve the separate
[native output owner-death race](output-experiment.md). The candidate alone
does none of those things.

## Framed release repair

The candidate guard now uses a distinct release path, restricted to the owning
Port process. It sends the source helper's cancellation frame and confirms only
the exact complete `U/unlocked` response followed by exit status zero. An error,
unexpected or incomplete frame, timeout, nonzero exit, missing Port or foreign
caller produces `:cleanup_unconfirmed`. The generic legacy unlock path is
unchanged. This is the existing `--lock-export-v1` helper's framed protocol,
not an authenticated protocol for arbitrary untrusted Ports.

The [focused controls](evidence/session-release/release-test-v2.log) passed six
tests, including a real `SCM_RIGHTS` recipient that kept the Session lock after
the candidate returned unconfirmed. A separate owner-loss case kept excluding
another process until the recipient closed. The later
[fragmentation-safe observation](evidence/session-release/release-test-fragmented.log)
reran those two affected cases, and the [framing controls](evidence/session-release/release-frame-controls.log)
covered fragmented success, partial and stalled frames, extra bytes, error
frames, nonzero exit and a foreign caller. The tests confirm the collector's
or recipient's local observations; they do not supply an authenticated
final-holder close protocol to Session or recover an interrupted effect.

The release repair uses the separate `_build/session-export-release-sol-20261029/`
graph. During preparation its BEAM modules were accidentally compiled into the
earlier graph; the earlier source was restored from its archived snapshot, and
the original [633-entry runtime inventory](evidence/session-release/prior-runtime-verification.log)
and [artifact manifest](evidence/session-release/prior-manifest-verification.log)
both verified without changing their expected hashes. The repair's unignored
[source snapshot](evidence/session-release/source.tar),
[runtime inventory](evidence/session-release/runtime.sha256) and
[manifest](evidence/session-release/manifest.sha256) identify its distinct
cohort. Commands run from the repository root with the recorded matching helper:

```sh
ERL_FLAGS='+S 4' MIX_ENV=test MIX_BUILD_PATH=_build/session-export-release-sol-20261029 mix test --no-compile test/ipse/session/export_lock_test.exs
ERL_FLAGS='+S 4' MIX_ENV=test MIX_BUILD_PATH=_build/session-export-release-sol-20261029 mix test --no-compile test/ipse/session/export_lock_test.exs:77 test/ipse/session/export_lock_test.exs:166
ERL_FLAGS='+S 4' MIX_ENV=test MIX_BUILD_PATH=_build/session-export-release-sol-20261029 mix test --no-compile test/ipse/session/export_lock_test.exs:135
```

Those `_build` graphs and the historical old-helper binary are local evidence,
not fresh-checkout prerequisites. A fresh Linux checkout needs the documented
toolchain and dependencies, a rebuilt native helper, and a fresh test-environment
compile so `Runner` pins that matching helper before running the fixture. The
prior old-helper refusal control cannot be reproduced from the checkout alone
without an independently obtained matching historical helper. The actual
Session still uses the legacy lock, and the output gate remains closed.

## Recipient observation follow-up

An independent review found that the exported-recipient fixture assumed each
`HELD` and `CLOSED` line arrived in one Port chunk. The fixture now accumulates
a bounded stream, validates the exact ordered lines across split or coalesced
chunks, rejects extra bytes and requires a clean recipient exit. The
[focused controls](evidence/session-observation/recipient-controls-v1.log)
passed both real exported-recipient cases, synthetic split/coalesced and extra
output cases, and explicit missing/dead-Port refusal. The
[source](evidence/session-observation/export-lock-test.exs),
[runtime inventory](evidence/session-observation/runtime.sha256) and
[manifest](evidence/session-observation/manifest.sha256) identify this
separate copied graph. The earlier framed-release
[manifest still verifies](evidence/session-observation/prior-release-verification.log).
The exact focused command was:

```sh
ERL_FLAGS='+S 4' MIX_ENV=test MIX_BUILD_PATH=_build/session-export-observation-sol-20261029 mix test --no-compile test/ipse/session/export_lock_test.exs:77 test/ipse/session/export_lock_test.exs:168 test/ipse/session/export_lock_test.exs:257 test/ipse/session/export_lock_test.exs:282
```

These controls do not cover every loss or interruption during descriptor
transfer, nor do they prove final-holder completion. The non-Linux and clean
checkout limitations above remain. Ordinary startup and managed output do not
select the candidate.

## Host-internal genuine Session control

The separate `Session.start_export_candidate_link/1` selects the candidate
on first acquisition after the same outer startup admission as ordinary Sessions. It
has no CLI, configuration or worker selector; `Session.start_link/1` continues
to use the legacy lock even if its options contain a `lock_mode` key. This is a
host-internal integration candidate, not an enabled output or export workflow.
It does not migrate a live legacy lock. The source and matching helper are
recorded in the [genuine Session cohort](evidence/session-genuine/manifest.sha256).

The [focused controls](evidence/session-genuine/session-test-final.log) passed
four genuine Session/Writer cases. They performed an actual Session prompt and
journal append while a competing native helper was excluded; closed a candidate
without an export; exercised an exported recipient and an unconfirmed Session
close; and killed the Session owner while its Writer and lock guard stopped and
the recipient retained exclusion. The recipient was deliberately injected via
the native Port for the fixture: there is still no Session or worker export API.
The test also checked that a retained recipient prevented candidate resume until
it closed, after which resume succeeded. A subsequent
[legacy close-and-resume control](evidence/session-genuine/legacy-resume-final.log)
passed with the ordinary lock.

An actual candidate Session on the earlier pinned helper refused startup without
falling back; ordinary Session startup remained usable in that separate
[old-helper control](evidence/session-genuine/legacy-unavailable.log). The test
graphs, [source snapshot](evidence/session-genuine/source.tar),
[runtime](evidence/session-genuine/runtime.sha256),
[old-helper runtime](evidence/session-genuine/runtime-legacy.sha256) and
[strict shared-module compile](evidence/session-genuine/coherent-compile.log)
are retained. The initial provisional graph had stale Collection and Saved
modules and failed before reaching the behavior; those logs are preserved. A
first resume-refusal fixture also let the expected linked failure kill its test
process; the isolated retry passed. Exact final test commands were:

```sh
ERL_FLAGS='+S 4' MIX_ENV=test MIX_BUILD_PATH=_build/session-export-genuine-sol-20261029 mix test --no-compile test/ipse/session/export_session_start_test.exs
ERL_FLAGS='+S 4' MIX_ENV=test MIX_BUILD_PATH=_build/session-export-genuine-sol-20261029 mix test --no-compile test/ipse/session/export_session_start_test.exs:93
ERL_FLAGS='+S 4' MIX_ENV=test MIX_BUILD_PATH=_build/session-export-genuine-legacy-sol-20261029 mix run --no-compile dev/verification/session_export_genuine_unavailable.exs
```

Candidate close stops its Writer before releasing the lock and includes the
framed release result in the Session close reply. Because the Writer cannot
append after lock release, its lifecycle closure is temporarily recorded with
`cleanup_confirmed: false` even when an unexported close later succeeds. A safe
post-release receipt design is still needed to record a clean result. Legacy
close and recovery keep their existing behavior. The tests use Linux synthetic
homes, and the old helper and `_build` graphs are not reproduced by a fresh
checkout alone. Neither output admission nor the
[owner-death write fence](output-experiment.md) is implemented.

An independent follow-up review confirmed the bounded ordered stream parser,
its split/coalesced and extra-byte controls, the two real recipient cases, and
the matching source and runtime manifests. The fixture requires a clean exit,
but its synthetic stream test does not separately inject a nonzero exit after
both valid lines. The archived evidence is untracked until the eventual commit.

## Candidate startup audit follow-up

The earlier actual-Session old-helper control checked only for a lock file.
An independent review found that fresh startup created its JSONL header before
the helper refused the lock, leaving an orphan journal. A single header is
subject to journal limits, but repeated failures can accumulate files. The
candidate fresh-start path now creates and admits the fresh ID, establishes
the state directory and registers the ID, then obtains the export-capable lock
before creating its JSONL header. Failed lock acquisition cannot create that
journal. If a later step fails, the normal lock-file inode is retained, and a
journal already created is not deleted. Legacy startup and candidate resume
retain their prior ordering. The [old-helper control](evidence/session-auditfix/unavailable-final.log)
checks both absence of a lock file and absence of a journal before starting a
legacy Session; it covers that helper refusal, not every later startup failure.

`@doc false` and the internal naming are not an access-control boundary. Any
code already executing in the BEAM VM can call the candidate entry point or
start `Ipse.Session` directly with `{:export_v1, opts}`. The latter bypasses
the outer `start_session` registry revalidation; the
[direct-start control](evidence/session-auditfix/new-controls.log) demonstrates
the capability with a valid fixture configuration, not a rejection of invalid
extension configurations. Host BEAM code is trusted in this experiment. The
reviewed extension Host action dispatcher and the CLI contain no candidate
selector, and a worker cannot choose it through those interfaces; this is not
a security guarantee against arbitrary code executing in the host VM. Before
exposing or relying on this selector, startup admission must be enforced at
the actual trust boundary, including direct GenServer startup.

The [final focused controls](evidence/session-auditfix/session-tests-final.log)
passed six tests in a separate matching-helper graph, including an active
blocked provider task and Writer stopped by candidate close before the lock
became available to another helper. This is a process-level in-flight test; it
does not simulate a stalled filesystem write or prove bounded IO cleanup. Two
descriptor-recipient controls initially failed with sandbox `EPERM` and
timeouts; their [failure log](evidence/session-auditfix/session-tests.log) is
retained, and the final run was permitted outside the sandbox. The
[source snapshot](evidence/session-auditfix/source.tar),
[artifact manifest](evidence/session-auditfix/manifest.sha256) and runtime
inventories identify the final helper-specific cohorts. The old helper and
copied `_build` graphs remain local historical evidence, not a fresh-checkout
reproduction. The candidate remains inactive and managed output gates remain
closed.

```sh
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-export-auditfix-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); Code.require_file("test/ipse/session/export_session_start_test.exs")'
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-export-auditfix-legacy-sol-20261029/lib elixir dev/verification/session_export_genuine_unavailable.exs
```

## Fresh-header owner loss

A subsequent independent review identified an untracked file-server boundary
after the candidate acquired its lock. The
[real-Session diagnostic](evidence/session-header-owner-loss/diagnostic.log)
used a copied Journal module with a test-only rendezvous immediately before
the normal `IO.binwrite`. It suspended the actual file server, verified a
write was queued, killed the Session, acquired the same lock using an
independent native contender, then resumed the server while the contender
still held the lock. The journal grew from zero to 1,501 bytes after owner
death and lock acquisition. This demonstrates that creator death does not
fence an already queued file-server operation. The initial instrumented
compile had a syntax error and the first diagnostic never reached the hook;
both failures are preserved alongside the successful run.

All candidate Session initializers, including direct GenServer startup and
resume, now refuse before journal or lock creation. The
[focused gate tests](evidence/session-header-owner-loss/gate-tests.log) passed
three cases, including both entry points and ordinary legacy startup; five
historical candidate tests are explicitly skipped while the gate is closed.
This is containment, not a repair of the underlying file-server lifetime or
the separate same-VM startup-admission binding. The old helper control above
describes its earlier cohort, not the current gated initializer.

An independent contender synchronized before an active candidate shutdown
in the earlier cohort observed the blocked provider task and Writer already
dead when it acquired the lock ([control](evidence/session-header-owner-loss/shutdown-contender.log)).
That observation does not establish a guarantee for queued file-server IO.
The fixture's first attempt lacked the required subscriber and is retained as
a failure. The diagnostic [source snapshot](evidence/session-header-owner-loss/source.tar),
[runtime inventories](evidence/session-header-owner-loss/runtime-diagnostic.sha256)
and [manifest](evidence/session-header-owner-loss/manifest.sha256) identify
the separate historical diagnostic and current gate graphs. The prior
audit-fix source is retained in its source archive; its manifest also names
the mutable workspace Session source, whose current hash necessarily differs
after the new gate. Its recorded manifest is not rewritten.

An independent review verified the diagnostic and gate inventories, checked
that the instrumented Journal adds only the rendezvous before the original
write, and confirmed the synchronized contender observed the task, provider
and Writer dead at lock acquisition. The unconditional gate also covers
candidate resume by source inspection; that particular entry was not run as a
separate control. The reviewer noted that legacy fresh startup creates its
header before acquiring the Session lock, so its header-I/O lifetime needs
separate analysis. The evidence remains untracked until the eventual commit.

Restoring candidate startup requires an owner-fenced header operation. One
possible design has the same native process retain the source lock while it
exclusively creates the header, returns authenticated descriptor identity to
the host for bounded JSON encoding, then writes and synchronizes that exact
header before reporting completion. It must validate directory and file
identity, preserve journal size/reserve rules, handle partial or uncertain
writes without replay, and retain the lock through every in-flight syscall.
No such protocol is implemented or admitted by these observations.

The diagnostic used the pre-gate Session BEAM from the preceding cohort;
the Journal source was generated and compiled only into its copied graph. The
contender control also used that earlier Session cohort. The gate tests used
a separate graph compiled from the current gated Session source:

```sh
IPSE_HEADER_INSTRUMENT_SOURCE=docs/archive/2026-10-29-native-shared-lease/evidence/session-header-owner-loss/journal-instrumented.ex ERL_FLAGS='+S 4' elixir dev/verification/session_header_instrument.exs
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-header-diagnostic-sol-20261029/lib elixir dev/verification/session_header_owner_loss.exs
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-export-auditfix-sol-20261029/lib elixir dev/verification/session_shutdown_contender.exs
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-header-gate-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); Code.require_file("test/ipse/session/export_session_candidate_gate_test.exs"); Code.require_file("test/ipse/session/export_session_start_test.exs")'
```
