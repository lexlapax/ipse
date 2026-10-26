# Native operator-channel incremental audit

Dated **2026-10-26**, work after `512ddf3`; see [contracts](contracts.md),
[native protocol](../../../native/README.md#observe-one-actual-terminal-display-and-input)
and the [implementation record](index.md). This is a low-level observation
primitive. It does not finish P31B/D0, mint Session origin witnesses or change any
CLI approval behavior. PTY automation supplies no independent human evidence.

The independent reviewer read the new helper/wrapper and exercised existing
compiled controls without building or modifying source. It made no model calls or
held-out-data reads. Author tests and independent rechecks remain distinct.

| Severity | Trigger | Repair and recheck |
| --- | --- | --- |
| P2 | Partial control request or full/flow-stopped terminal blocks before the input-loop deadline; owner loss cannot interrupt it | One deadline and cancellation-first polling cover request, display and input. Private pipes and a new verified terminal open description use nonblocking IO. Full-display/partial-request deadline and parent-loss tests pass; parent flags stay unchanged |
| P3 | Native minimum Unicode filtering permits characters escaped by the host policy | Document minimum Cc filtering and require the existing complete host Unicode escaping; wrapper validates it before opening a channel |
| P3 | Missing initial private output descriptor escapes to generic binary stdout error framing | Operator-specific setup errors use bounded plain stderr; independent probe confirms nonzero exit with zero stdout bytes |

The author also pinned this channel to the bundled helper's compile-time binary
digest. Environment-selected helpers cannot supply terminal observations. Tests
substitute an executable that would forge valid nonce-bound frames; both override
and isolated packaged-helper replacement refuse. The isolated test checks its
actual selected application and executable permissions to avoid a vacuous pass.
This pin assumes trusted host installation, not distribution authentication.

Independent final review confirmed the three repairs. A synthetic allocated PTY
then exercised the current Elixir wrapper with `synthetic café 日本語`; returned
text/hash matched. This was machine input, not a person, acceptance or publication.

Native PTY tests pass **nine, one ignored subprocess entry**. Complete native
Runner coverage passes **48, two ignored subprocess entries**. Wrapper/consent/
Runner coverage passes **31 tests**. All native tests compile with `-D warnings`.
The final combined changed-feature suite passes **66 tests**, followed by the
complete native suite's 48 passes/two ignored entries, after the platform C-character
type repair. Formatting and strict compilation also pass.
Later fixed-revision full/source/package/installed/platform evidence is separate.

## Preserve first fixture failures

The first standalone run passed six and failed one: the mismatched-terminal
fixture dropped its master before the child entered, preventing the intended
refusal observation. Retaining that master repaired the fixture, not the runtime.
A parallel complete-native run exposed a control-pipe inheritance race; pipes now
use atomic close-on-exec on Linux and PTY fixture ownership serializes allocation/
spawn. High control descriptors are installed after child exec to preserve the
spawn error pipe. The parent-loss assertion remains. A later parallel run exposed
the display assertion reading only one stream fragment; it now accumulates the
entire bounded prompt before asserting. Neither fix lengthened the native deadline
or removed a safety check.

Final PTY allocation uses the already-inventoried C library's standard POSIX
functions, without an extra libutil link or executable dependency. The current
complete-native run passes with that allocator. macOS execution remains a CI gate.

Raw first and final logs are retained outside Git at
`/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/`,
with owner-only files and a SHA-256 manifest. They contain synthetic diagnostics,
not portable milestone acceptance. Source tests still need the exact integrated
Session/CLI witness and policy path before any origin or saved-grant claim.
