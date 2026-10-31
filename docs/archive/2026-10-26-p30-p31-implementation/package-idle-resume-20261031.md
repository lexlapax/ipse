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
