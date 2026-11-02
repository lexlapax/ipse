# Word v15 exact package checks — 2026-11-02

Author-run local Linux verification of clean committed source
`23d99498bf5fceb4ab7149102dc324d7aa95ba66`. This supplements the
[source/native annotation increment](word-annotation-completeness-20261102.md).
The [machine receipt](word-annotation-installed-20261102.json) binds source,
archive, unchanged independent artifact and reports. Current procedures belong
to [testing](../../developer/testing.md#verify-documentation-and-packaging-at-their-own-boundaries)
and [installation](../../operator/install.md); the [plan](../../plan.md) owns
remaining qualification.

## Build and verify the committed archive

An independent clean clone at `/tmp/ipse-word-v15-package-20261102` contains only
tracked source. Private/untracked work was not copied. Locked dependency sources
were copied separately, without hard links. The standard PDF-enabled package
command ran with existing offline caches:

```sh
HEX_OFFLINE=true CARGO_NET_OFFLINE=true ./dev/package.sh
```

It exited **0**. The package manual check covered **52 documents**, zero missing
local targets, and the exact committed source reference. The clone stayed
tracked-clean after building and after both installed proofs.

Archive: `ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz`.
SHA-256: `2b7af9038aefbe1e79387dbe3e5a997766007120b871fa1e22f0be01a2411bbc`.
Its bytes remain unchanged after verification. The archive is local; no release
or service was published.

The generic installed-package proof exited **0**. It checks real extracted CLI,
workspace selection, offline setup/doctor, shell/output and uncertainty handling,
upgrade/refusal/recovery, handoff, MCP/delegation/extensions, helpers and the
synthetic explicit-memory workload: 100 records/queries across six Sessions and
two projects, with no model calls. A fixture's exact-token retrieval score is
not independent semantic-quality or native annual-capacity evidence.

## Preserve the independently built artifact

The same `state-documents` Corpus artifact that passed source verification then
passed **all nine installed document checks**. Its manifest SHA-256 is
`783d7f0938f409a647c6a21defaec7893513016c61ebb1ce8b2f0cbecce0888d`.
The verifier checks original artifact bytes before and after execution; it
does not rebuild them for the installed host.

Named checks cover artifact modules, Unicode text, revision visibility, matching
style effects, block packing, linked/orphaned annotations, default-off PDF,
explicit protected PDF extraction and dependency notices. The gate rejects any
missing, false or substituted check. Source and installed reports retain private
homes, precompiled harnesses, unchanged inventories and no system development
toolchain on runtime PATH. The PDF resource backend is available on this host;
ordinary PDF acquisition remains off.

The owning developer testing/Knowledge and operator Corpus/install chapters were
reviewed as whole manuals. Existing source/installed commands, recipe limits and
recovery procedures match the observed scope; package links resolve at the
committed source. These checks qualify the exact local archive and synthetic
artifact behavior. They do not establish complete installed knowledge journeys,
independent Word rendering/answer quality, sustainable storage turnover, other
platforms, real accounts or the final milestone-wide audit. The separate complete
`9f1707c` suite also does not contain this increment.
