# Installed idle-resume verifier repair

Dated 2026-10-31. Historical engineering evidence, not milestone acceptance.
Current verification guidance is in [testing](../../developer/testing.md);
the [plan](../../plan.md) owns remaining qualification.

## Reproduced expectation drift

A clean checkout at `bc23dd53f8a7765412b601a8cf439d9e5f8a2de3` built the
standard PDF-enabled package using existing locked offline dependency caches:

```sh
HEX_OFFLINE=true CARGO_NET_OFFLINE=true ./dev/package.sh
```

Archive `ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz` SHA256:
`9a3e71f1af4864948d4f57c2b95436a39caf8758197c32412f1f4fe518451d73`.
The package manual check found 52 documents and no missing targets.
This archive remains unchanged; its failed package checks are not passes.

The generic installed proof first failed its upgrade control's whole-journal
equality. An idle resume now legitimately appends a native ownership marker.
Confirmed close appends the corresponding release intent. An initial repair
that allowed only the owner marker after confirmed close also failed. A second
driver run against the same archive passed the upgrade control and reached the
shipped handoff check, which had the same obsolete equality. Inspection found
one more instance in the shipped extension demo before rebuilding.

## Bounded repair and source verification

Only verification scripts and the synthetic demo change; runtime admission,
source eligibility, native protocols and gates are unchanged. Snapshots follow
`Session.close_confirmed/1`. Successful idle resume must retain the exact prior
bytes and append exactly one complete, valid owner marker before close. The
upgrade control checks the exact owner/release-intent pair after confirmed close,
same owner, nil idle epoch/closure, actual journal parsing/current intent and
native signed-release claim. A legacy journal without a release layout permits
no suffix. Denied selected-extension resume still permits no mutation. No broad
record allowlist replaces equality.

The extension demo retains exact accounting, presented answer and lifecycle
projection assertions. Its fresh synthetic run passed without network inference:

```sh
mix run -e 'Code.require_file("priv/demo/extensions.exs"); :ok = Ipse.ExtensionDemo.run()'
mix test test/dev/release_test.exs test/dev/verification_test.exs
```

The source tests passed **48 checks in 79.1 seconds**, seed 276631. Formatting
and scoped whitespace checks passed. The full testing chapter was reviewed;
its idle-resume and package sections now explain the precise ownership suffix
and separate confirmed-close proof. No operator procedure changes.

Build and failed-driver logs are retained locally under
`/tmp/ipse-package-bc23dd5-*.log`; source checks use
`/tmp/ipse-package-verifier-*-20261031.log`. A fresh committed-source archive
must repeat installed verification. These source checks do not qualify that
replacement archive or replace the failed whole-source baseline.

## Separate decision artifact

Before the verifier repair, an independently built decision artifact passed
all seven synthetic checks in source mode and against the exact archive above.
Its manifest SHA256 is
`0d946baa2b3d4fb569435a7c03dd878ae963c6d64268b617616eeb82e219ae72`.
Both reports preserve unchanged artifact inventories, private homes and absence
of a development toolchain on runtime PATH. Logs are retained at
`/tmp/ipse-decision-bc23dd5-source.log` and
`/tmp/ipse-decision-bc23dd5-installed.log`. This is neither generic package
acceptance nor live engine or consumer-quality qualification.

## Replacement archive and active-epoch follow-up

The clean committed-source build at
`267b3e6f799f659a28d200167a1ff844e60fd92a` produced the same supported basename
with SHA256
`81e4e52b0e7bd4ea155515fd2b9c242364f3919a0ccfd364868b63cd61d6d794`.
Its generic installed proof passed the repaired upgrade, handoff and extension
checks, and the explicit-memory workload (100 records/100 queries, six Sessions,
two projects, no model calls). It then failed the parallel-delegation demo's
obsolete single-closure assumption. This is still a failed generic package proof.

The recorded active-epoch suffix was the lifecycle closure plus release intent;
the closure correctly says `cleanup_confirmed: false`, since its append precedes
the actual native release. The demo now requires confirmed close, exactly those
two records, unchanged preceding records/bytes, the closure's epoch and digest in
the validated current intent, and the native signed-release claim. Idle resume
requires exactly one valid owner marker, preserving the exact closed prefix.
The separate actual child-result/approval assertions remain intact. A source
run of this parallel demo passed without a model service. The redundant module
attribute/alias that emitted a warning was removed. Inspection covered journal
suffix assertions across all shipped demo scripts before another package build.
Existing delegation, child-accounting and signed-release regression files passed
**22 checks in 4.3 seconds**. No runtime protocol or source gate changed.

Separately, the complete legacy Collection SDK Session file passed **15 checks
in 14.3 seconds**, seed 685894, after the earlier admission restoration.
A fresh independent Corpus artifact passed all **six** document-parser checks
in both source and installed modes against the exact `267b3e6` archive, including
the available native PDF resource backend and all dependency notices. Both
reports retain unchanged inventories, private homes, precompiled harnesses and
no system development toolchain on runtime PATH. Inputs remain synthetic;
this does not establish real Word fidelity or full installed knowledge behavior.
Logs use `/tmp/ipse-package-267b3e6-*.log`,
`/tmp/ipse-documents-267b3e6-*.log` and
`/tmp/ipse-current-legacy-sdk-session-20261031.log`.

## Passing final package

The clean build at `e25d235d1c400e14fd0cbbbed7ca07e51a672443` passed the complete
generic installed-package command above. Its archive SHA256 is
`468860ca983c81379c5205d0b30121ccc1a6559d0d3fd19902b9ca061bd6bf15`.
The [machine receipt](installed-package-20261031.json) retains the source identity,
archive and independent artifact hashes, all five final reports and full-log
hashes. The package checkout remained tracked-clean after building.

Both independent artifacts then passed against this final runtime: seven
decision checks in each of source/installed modes, and six document checks in
each mode. Artifact inventories were unchanged. The generic package proof also
passed offline setup/doctor, permissions, upgrade/refusal/recovery, launcher and
workspace selection, shell uncertainty/output bounds, the synthetic explicit
memory workload, handoff, extension/usage/budget demos, MCP, serial/parallel
delegation and helper cleanup/locks. Runtime PATH excluded the system development
toolchain; every proof used a private home and precompiled harness.

These are local Linux synthetic checks, not hosted macOS, native-policy support
for other kernels, real Word fidelity, live engines, semantic model quality,
full installed knowledge behavior or a passing whole-source baseline. No release
was published. Earlier archive failures above remain failures.

A separate read-only Ollama inventory made no inference request or download.
The selected loopback server now reports `0.40.13`, rather than the provisioning
record's `0.40.5`; the primary Qwen embedding and 4B answer tags retain their full
recorded weight digests. This is current availability, not qualification of the
updated server, offline execution or protected local preset.
