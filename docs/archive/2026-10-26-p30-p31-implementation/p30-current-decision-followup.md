# P30 current-source decision checks

2026-10-27. This is synthetic component and Session evidence, not a P30
acceptance, installed-package baseline, qualified consumer, or live engine test.
The [plan](../../plan.md#p30-advisory-decision-engines) owns current status.

On the later active worktree, after the MCP cleanup and discovery changes, a
12-file decision, profile, transport, budget and Knowledge policy regression
run passed 100 tests (seed 284929). The run used local synthetic fixtures; it
does not qualify a protected decision consumer, a finite experiment, a live
account or an installed-package baseline. The separate full-suite snapshot
still predates the subsequent worktree repairs.

On 2026-10-30, a later fixed-source full-suite run reported repeated decision,
embedding and Collection Session failures with `Unexpected worker result`.
Its test-build `Ipse.Extension.Host` BEAM contained the private ShareHost probe:
the share fixture had replaced the shared BEAM without restoring it after its
test module finished. An initial repair restored both Host and optional terminal
BEAMs and the previous compiler options in cleanup. A direct fixture run
restored both original file hashes; 12 of 14 unexcluded tests passed, while two
terminal-specific controls failed without their matched terminal. A subsequent
decision Session control passed. Separately, 51 knowledge-independence,
decision and embedding tests passed together without the share fixture. This
identifies a real contamination mechanism, not proof that it caused every
full-suite failure. The running full-suite snapshot predates the repair.

A further fixture repair uses an isolated copy of the Ipse test-build BEAM
directory for instrumentation, then restores the code-server path and loaded
modules during cleanup. It no longer writes the instrumented modules into the
shared build, including if the test VM is interrupted. Twelve non-terminal
share controls passed; the two controls needing the matched terminal were
excluded from that run. The shared Host and terminal BEAM hashes were identical
before and after. The matched-PTY bridge and instrumented cancellation controls
then each passed separately; their default exclusions and explicit commands are
documented in the [testing manual](../../developer/testing.md#exercise-actual-os-policy-and-native-protocols).
These are synthetic terminal controls, not protected-output qualification or a
complete full-suite result.

The older fixed-source suite finished with 3,007 of 3,464 tests passed, 457
failures, 21 invalid, 53 skipped and 55 excluded. It predates the fixture
repairs above. A fresh isolated current-source suite was started from private
index tree `c60ab160e166922d03de7e465e954f6794fc777a`, with rebuilt native
helper SHA-256 `c61df13da6fb2805242c6fbd8f6b50d7bee8ff83605cfe146698bd7e6cc59743`.
Its log is `/tmp/ipse-current-full-20261030b.log`; no outcome is claimed while
the run is in progress.

A private source snapshot was made from the current tracked worktree and the
untracked source, test, development and shipped-fixture files under `lib`,
`test`, `extensions`, `dev` and `priv`. Its private index tree was
`2b8c9fa23c87b9d762aaf6427b0b44ea21b1a2d7`; tracked bytes matched that index
after the checks. Untracked archive records, retained `.serenity-*` evidence,
dependencies and build products were not treated as source. The copied native
helper SHA-256 was
`891758d90dd875a9e890b25c2eade1955a20bd59aa47fe05b5682e09bad991f5`.

Forced test-environment compilation rebuilt 152 modules with warnings treated
as errors. Seventeen focused suites covering decision configuration, neutral
contracts, provider transports, extension capabilities and Session egress,
usage and budget accounting, plus the Knowledge pure decision policy and the
unwired Mint decision experiment, passed **138 tests** with seed 20270710 and
one case at a time. The log is `_build/p30-current-validation.ri5cUYdZ/_build/p30-current-check.log`.
Native-sandbox, macOS-sandbox, macOS-filesystem and memory-scope tags were
excluded by the test configuration. The Session tests use local synthetic HTTP
services; no paid model, live account, download, protected storage workload or
release publication was used.

## Local package baseline

The first PDF-enabled package build stopped after release assembly because the
private snapshot omitted untracked archive documents referenced by the manual.
After adding the current documentation, private tree
`bb0b70cd0f943f13d0fb9d29fcb4c87c556e354b` differs from the tested tree above
only under `docs/`. The offline package build completed, and the documented
installed-package verifier passed with isolated homes, synthetic fixtures and
a utility-only runtime PATH. The archive SHA-256 is
`3be5ea3dbc7057d9b2a3f87425a77332ef63df9af2cc7e030c14ac467cdaa0b6`.
The build and verification logs are
`_build/p30-current-validation.ri5cUYdZ/_build/p30-package-build-complete-docs.log`
and `_build/p30-current-validation.ri5cUYdZ/_build/p30-package-verification.log`.
Tracked bytes matched the private index after verification.

The generic verifier exercised installed CLI, permissions, upgrade, memory,
MCP, delegation and bundled runtime checks. This source snapshot has no reviewed commit, and the
bundled documentation source reference fell back to `v0.1.0`; the archive is
not a release candidate or evidence that those links identify the snapshot.
The frozen independent qualification set, live accounts and native storage
qualification were not exercised.

## Synthetic installed decision Session

The archive above was extracted separately and the `decision-calls` example was
built against its shipped SDK. The first builder invocation failed because it
assumed unversioned dependency directories; a second invocation supplied the
release's versioned Jason, Jsonschex and JSON Pointer beam paths and succeeded.
The resulting example artifact manifest SHA-256 was
`18322c191a5553bc79855c057ca6c7977aecd544104f6f733e4af9992ff262ec`.

The extracted release ran the synthetic
[`decision_installed.exs`](../../../dev/verification/decision_installed.exs)
probe in an isolated home. It passed with marker
`INSTALLED_DECISION_SESSION_PASSED`: approval preceded the loopback request;
the selected compatible route sent no authorization header; typed advice and
usage restored from ordered journal records; and idle resume made no second
request. The probe SHA-256 was
`c0759d9c0aed5d0d651c37308d177a2df1a9ccae7a0c01d79e60682e5df88862`.
A repeat in a fresh scratch directory passed; its retained log is
`_build/p30-current-validation.ri5cUYdZ/_build/p30-installed-decision-probe.log`
with SHA-256 `7b6082d809a38e10250138ac053cdae3aa6db7897b508a4c72d2632b332d3da0`.
These were synthetic Sessions using an example extension, not an
installed Knowledge consumer, paid provider, adversarial review, or complete
decision-package acceptance. The full package verifier above did not include
this separate probe.

The standalone probe was subsequently adapted into the finite `decision`
scenario of `dev/verify.exs`. Its source and installed modes both passed all
five behavioral checks with a precompiled harness, private home, no system
toolchain on the runtime path and unchanged input inventories. Both used the
same built example artifact; the installed mode used the archive above. The
earlier probe hash above identifies the historical standalone version. The
five-check proof-module and scenario-table SHA-256 values were respectively
`b90771b6067a7e7e71808769bc824a669108cd31e1967694d4155cc4e2beba24` and
`1c2cec230b1f85af4d2ad33634b93f9071e2cdfe1bd95d591cc5ba80b7fb65dc`.
The two JSON reports are retained at
`_build/p30-current-validation.ri5cUYdZ/_build/p30-decision-source-scenario.log`
and `_build/p30-current-validation.ri5cUYdZ/_build/p30-decision-scenario.log`.
The working-tree verifier regression passed 34 tests with seed 20270712 and
one case at a time; its log is
`_build/p30-current-validation.ri5cUYdZ/_build/p30-verifier-regression.log`.
This scenario does not establish a Knowledge consumer or live engine access.

The scenario was then extended to seven checks. Separate synthetic Sessions
verify that an operator denial produces no request admission or egress, and
that cancellation after dispatch closes the local socket, records a partial
cancelled outcome and does not replay after resume. Source and installed modes
both passed with unchanged inventories. The current proof-module and scenario
table SHA-256 values are
`869c10a120ee2d7dcf924c260214ecb5b7feeead748dd7ca489fb3d0fa89c402` and
`221c6d9f97d93fb81c17371ec846e22eb06dc8084e9d110b676346b05d168a7e`.
The reports are
`_build/p30-current-validation.ri5cUYdZ/_build/p30-decision-source-adversarial.log`
and `_build/p30-current-validation.ri5cUYdZ/_build/p30-decision-installed-adversarial.log`.
The working-tree verifier regression passed 34 tests with seed 20270713;
`_build/p30-current-validation.ri5cUYdZ/_build/p30-verifier-adversarial-regression.log`
has SHA-256 `90f0c3934bae9d7ae26b9ba7fffad2d64bb612f30c0346305a0365ba34cce465`.
Socket closure demonstrates local cleanup, not that a remote service stopped
computing or billing.

The snapshot contains the current uncommitted experiments and is not a reviewed
commit or an installed artifact. These selected suites do not replace the full
repository regression, platform and packaging checks, authenticated protected
consumer integration, frozen experiment evaluation, or the requested final
adversarial audit. The current host's kernel remains outside the admitted native
storage profile. See the [continuation handoff](handoff-20261027-terra.md).

## Synthetic planner-to-Session shadow control

The uncommitted decision Session fixture now compiles the actual Knowledge
decision policy into its isolated synthetic worker. That worker has no State or
Collection publication capability. With synthetic, explicitly untrusted facts,
the notes-selection control verifies that a fitting set makes no request, an
approved local decision maps a returned choice to its original permitted IDs,
denial causes no egress or request admission, and idle resume does not replay.
The assessment control exercises two candidates in one admitted request: a
high-probability deferral maps to the selected ID, while a lower-probability
answer retains the baseline. Empty candidate input makes no decision request.
This tests actual Session approval, local fixture transport, typed result mapping
and action replay; it does not admit real main-tool candidates, access protected
notes, publish effects, grant an experiment budget or qualify a consumer.

The complete decision Session suite passed 11 tests (seed 46447); a broader
13-file decision, policy and budget selection passed 101 tests (seed 46448).
The additional empty-candidate control was added after those runs and passed
separately (seed 46449), and the full 11-test Session file then passed seed
46450. A subsequent OpenAI-wire loopback control exercises a per-question
refusal alongside an independently usable answer (seed 46451). It uses a
synthetic credential and does not call an OpenAI account. Platform-specific
tags were excluded; no live or paid service was called. The updated 13-file
selection passed 102 tests (seed 46452), including all the added controls.

## Installed decision artifact continuation

On 2026-10-28, a separately built `decision-calls` example artifact was checked
against the current source SDK and the same PDF-enabled diagnostic archive
described in the [handoff](handoff-20261027-terra.md). Both verification modes
passed all seven synthetic loopback checks: approval before request, explicit
compatible route without authorization, denial without egress, idle and
interrupted no-replay, ordered usage restoration and typed advice. Both reported
unchanged inventories and no conversation inference. The artifact manifest
SHA-256 is `d4b297bad8493913a3d1f7d3f719609b94de054122cb71773a1cc72a643fbc07`;
the source and installed logs hash to
`af12e0685d5b2948f8dc2223206c6f5cdbb893b490d7408aefec5f95fb635398` and
`ac6c4f0cd8c67828b2c9c51eb3048326febeed44607d9cfa3d4adfa1d1c31695`.
They are retained under `_build/production-build-Au0AOr9b/_build/`.
This is a synthetic extension proof, not a live decision account, qualified
Knowledge consumer, P30 completion or a distribution-ready archive.
The same decision artifact subsequently passed installed verification against
the newer diagnostic archive that includes the signed-observation repair; its
log is `_build/production-guard-inGks1jJ/_build/decision-guard-check.log` and
has the same installed-log hash above. Archive provenance remains in the handoff.

## Current-worktree focused rerun

On 2026-10-30, an 11-file decision, provider, configuration, accounting,
Session and Knowledge-policy selection passed 69 synthetic tests on the dirty
worktree (seed 520098), after rebuilding the native helper. The initial run
exposed the stale helper and an isolated SDK fixture that omitted the current
context-framing and catalog dependencies and expected an older tool catalog.
The fixture now includes those actual host beams and exercises context sizing
in its separate VM. This focused run does not establish a fixed-source full
suite, installed package, live service, or qualified P30 consumer.

A later current-worktree selection of 12 decision protocol, profile, transport,
usage/budget, extension Session and Knowledge planner files passed 100 tests
(seed 114200; local log `/tmp/ipse-p30-current-focused-20261030.log`). It uses
synthetic local fixtures and excludes the configured platform-specific tags.
It does not establish protected Knowledge decision egress, a separately granted
shadow experiment, live engine access, quality benefit or the full suite.

Another dirty-worktree rerun on 2026-10-30 passed the ten focused decision
protocol, profile, transport, accounting and extension Session files (54 tests,
seed 62145) and the Knowledge decision policy file (15 tests, seed 23620).
These are overlapping synthetic controls, not an independent fixed-source or
installed-runtime qualification, and they do not resolve the protected-consumer
and experiment gaps above.

