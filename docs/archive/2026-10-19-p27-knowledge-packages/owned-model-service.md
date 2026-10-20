# Owned model-service component, 2026-10-19

Historical implementation and verification record following `75b7077`. The
source commit containing this record owns the component and synthetic verifiers.
Use the [evaluation training manual](../../developer/knowledge-evaluation.md#exercise-ownership-of-a-model-service)
for current procedures and the [plan](../../plan.md#p27-optional-research-graph-and-rag)
for acceptance status. This component does not complete P27 or enable a measured
comparison.

## Selected ownership

Two isolated architecture candidates and a separate judgment selected one
caller-owned Port receive loop with one guarded operation Task. The contexts
used the same model. The owner drains native frames while the Task stages files,
checks inventory and calls the complete work function. A guardian confirms that
its owner monitor is installed before staging. No reusable borrow/close service
API or new core task-resource kind was added.

`EvaluationModelService.validate/1` is pure. `run/3` takes a closed local
selection, a fresh output directory and one zero-argument callback. It returns
the actual callback outcome separately from its JSON service receipt. Service
loss can interrupt running work, but cannot erase a callback result already
returned. Session closure, canonical inference accounting and quality remain
callback-owned. No diagnostic serializes callback results or private exception
reasons.

The service starts from copied runtime files and the selected manifests' complete
hashed config/layer closure. Every destination is a new private regular inode.
The runtime's private `lib/ollama` exists before launch, preventing ordinary
library discovery from falling through to a sibling or working-directory tree.
The literal non-default loopback origin and selected environment permit no
ambient credentials, proxy, cloud model or provider fallback. The CPU policy
sets explicit visibility values and deterministic daemon defaults. Synthetic
fixtures verify those values, not actual real-model CPU execution.

One native direct-child listener observation is required before HTTP. Child
stdout that resembles proof bytes remains log data. Initial tags and capabilities
must match the selection and residency must be empty. Final tags, CPU residency
and private runtime/manifest/config identities are checked after returned work.
A callback exception stops further inventory HTTP immediately. Native cleanup
uses the retained Port/group, never a diagnostic PID.

Native traffic is limited to 128 MiB. The retained framed log prefix is capped
at 16 MiB encoded bytes in fixed-size chunks, with discarded payload counters.
The caller persists logs only after the Task has stopped and the daemon has
closed. Bytes drained by Runner during close are explicitly outside the retained
prefix. Owner death produces no invented final receipt.

## Safe file admission

OTP's documented file API does not offer the nonblocking, nonfollowing descriptor
admission required here. An lstat followed by open can race a writerless FIFO.
The generic Rust mode `--copy-regular` opens with `O_NONBLOCK|O_NOFOLLOW`, checks
its retained regular descriptor and exact size, and copies through a bounded
read/write loop. It checks source/path identity before and after copying, syncs
the exclusively created private destination and parent, then emits a bounded
identity receipt. Elixir hashes the owned destination against its selected digest.
There is no hardlink, reflink, download, Rust crypto implementation or dependency.

A bounded macOS probe executed the old check/open sequence on Elixir 1.20.3,
OTP 29. After a successful regular-file lstat, its retained Rust parent replaced
the source with an owned writerless FIFO. The BEAM child remained blocked for
500 ms, then was killed and reaped through its retained Child handle. The new
helper refused the same FIFO within one second, exited with 1 and created no
destination. Both children were reaped. This was an OTP 29 execution, not an
execution of the OTP 27 documentation's warning.

The helper assumes a private destination parent with one writer. It checks the
immediate retained parent but does not implement an ancestor filesystem sandbox.
The selected daemon and evaluation callback are trusted code; ordinary process
group escape limits still apply.

## Review and repairs

Independent review covered the whole service lifetime, native copy mode,
verification tools and complete contributor/native/dependency documents.
The reviewers found no additional production defect after the callback-exception
path was corrected. They accepted the single-owner module's cohesion for this
scope; its formatted line count alone did not justify a new abstraction.

Review repaired four false-pass risks in the new synthetic verifier:

- Positive cases now inspect the complete private manifest/blob closure, exact
  contents, single links and distinct source/destination inode pairs.
- The occupied listener checks for pending unauthorized connections. Wildcard
  and forged-only fixtures require no admitted listener, metadata request or
  HTTP marker. Forged bytes use the selected port and positive fake identities,
  while the forged-only child never binds.
- Interruption cases prove callback entry and an actual held HTTP request.
  Owner-death failure cleanup stops and awaits the captured owner, Task and
  Session independently.
- A 144-MiB fixture crosses the 128-MiB native traffic limit. Flood/cap cases
  require the actual bounded, parseable log artifact and numeric counters whose
  retained payload agrees with that artifact.

The first Linux source run passed 16/19. Two failures were a verifier assertion
that incorrectly required valid final inventory in deliberately invalid-final
cases. The third was a missing required `subscriber` option in the synthetic
Session setup. Correcting those fixtures passed 19/19. The strengthened final
source checks passed 22/22, including pure selection validation and 21 service
cases. The CLI verifier initially treated Mix's separator as a fixture path;
that pre-staging failure was corrected and retained. No production failure was
silently relabeled as a passing run.

## Verification at this checkpoint

The final retained-evidence Linux source verifier passed all 21 synthetic cases.
The same21 cases passed through a fresh extracted package's bundled runtime and
native helper with no development executables available in its PATH. The standard
extracted-package verifier also passed. Six native copy controls passed on both
Linux and macOS, including the parent-driven bounded FIFO subprocess. Actual
empty and multibuffer helper invocations checked receipt shape, bytes, mode and
new inode pairs.

The source tree and evidence used a fresh directory on the authorized Linux host;
its main checkout and existing services were untouched. No systemd service,
cgroup benchmark, real model weights or inference was used by these controls.
Source/runtime hashes, private receipts, initial failures and complete logs remain
in the ignored continuation evidence. The macOS build, strict compile and full
source suite passed: 1,272 passed, 1 skipped and 34 excluded in 743.3 seconds,
with strict stdio probes and the unchanged 60-second test deadline.

A later Elixir 1.18 formatter check rejected two layouts accepted by Elixir 1.20.
The reviewed correction separates the final limit comparison after the same
shape/type/range checks and expands one conditional to a block. Both formatters
accept the result. Independent review confirmed identical evaluation order and
error behavior. Final focused source and installed checks cover that correction;
the earlier full-suite result is retained with its original source hash.

### Final focused and installed gates

After the compatibility correction, both formatter versions and the macOS
focused service tests passed. The Linux retained-evidence source and installed
verifiers each passed all 21 cases again. The rebuilt macOS package passed its
standard verifier and the service-owner verifier's unsupported-before-effects
case. Native macOS policy/stdio tests passed 30 with 6 excluded in 24.7 seconds.
The demo, documentation checker and CI policy checker passed. The documentation
checker covered 259 Markdown files and 2,776 local links with zero errors.

The final service source SHA256 is
`85983655d19bcc60a6bf5f9361ba89ca20ccfd21483003f869512f2f75582f03`.
The preceding complete macOS suite tested source
`c1b9cfbcf46c0fba008e1fce074c664b0c95241f5fc988b8bb75397670ac737c`.
The independently reviewed two-hunk compatibility correction is the only change
between them. The verifier/probe hashes stayed
`ca44be338e2168e139d0a9138c347223e06b402154cf7a69368afb35bdebe186` and
`dd9660ae8cf80a6bdf227c3de278e6fe9d70ca9f1750a21f785310e684f1579b`.

A separate root audit read actual source/installed receipts, confirmed listener
PIDs matched the owned fixtures and observed those daemons absent. It reconciled
late-failure work preservation, zero HTTP before ownership, exception-path HTTP
closure and absence of an invented receipt after owner loss. Both Linux releases
used native helper SHA256
`53897ad3ec5d07fcb8362be70fcb427b7275335c512bf0333fac2f30a1bf40f5`.
The Linux package SHA256 was
`5101457f71a04842840fefe074c2d9bad986365695fdbb794f7d713692ac240c`.

The initial Linux evidence archive SHA256 was
`551441b8c8178c517ccfcad81de180d4c75436bd32a840821294e7340b80f442`.
The final compatibility-evidence archive SHA256 is
`1b9c5c2b68e6edf41fba3ddd42ef5858df4136fe5144ed8d3da85042a8212fe0`.
The macOS package SHA256 is
`a18e4c6e60af56c0455108fee5477790afe9447ddd2ec7ddd42642066f2cb386`.
The separate final archive retains the compatibility-source receipts without
replacing the earlier evidence. The ignored repository continuation holds both,
the audits, complete platform logs and frozen source snapshots. Generated
binaries and private receipts are not committed.

CI now runs the six native copy controls on both platforms and an independent
installed service-owner proof. No hosted result for the commit containing this
new unit is inferred from the preceding foundation's green run.

## Remaining integration

The portable declaration and execution seal still do not bind this service
selection. Legacy execution paths continue to refuse version-two seals. Complete
measured entry must verify retained registry identity and permanent native/domain
claims before effects, prepare the exact projected inputs and 14-cell schedule,
and call each full domain lifetime with this private service inside measurement.
It must close Sessions/services/gateways and reconcile canonical liability before
cell exit. All 350 first predictions must be sealed before opening references.
Post-exit read-only audit must reconcile the three distinct peak subjects.

Actual selected-runtime CPU proof, the fresh held-out comparison, independent
semantic review, complete resource comparison and justified optional-engine
selection remain open. These synthetic results establish neither model quality
nor exact workload-charged RAM coverage.
