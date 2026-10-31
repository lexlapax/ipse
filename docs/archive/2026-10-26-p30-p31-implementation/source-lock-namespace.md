# Protected helper pins and legacy namespace refusal

Historical scoped verification, 2026-10-28, on `codex/p30-p31`. The
[plan](../../plan.md) owns milestone acceptance. These controls repair two
authority gaps and an interrupted-effect recovery gap; they do not complete
P31C0 or qualify later supersession work.

## Boundaries repaired

Retained original-source locks and the original live Session owner lock now use
the compile-pinned protected native helper. `IPSE_RUNNER_PATH` can still select
an ordinary diagnostic lock helper, but cannot supply a forged live `L locked`
frame as managed source authority. Managed shell admission also selects the
protected helper before its native ready/grant/spawn acknowledgment protocol.
The [earlier source-lock capacity record](../2026-10-28-source-lock-reserve/index.md)
tested a different, older helper cohort and remains historical evidence for its
bounded resource accounting.

Semantic policy versions share the namespace derived from project and collection
ID. Previously a newly reviewed v1 collection read could select an existing v2
managed namespace and reach ordinary `get`/`scan` without authenticating the
record's current original source or expiry. Generic worker collection access now
uses `Collection.execute_unmanaged/4`: the current manifest is loaded and checked
for reserved `host.validity.*` records inside the same native transaction that
would read values or commit changes. An existing managed format therefore refuses
legacy reads and writes. A conversion after Session startup is checked on the next
operation. V3 format metadata survives removal of the last live note; ordinary
worker requests cannot select or delete its private keys. Legitimate namespaces
without managed metadata retain their legacy access.

The v2 managed-read path remains responsible for source/recipe/expiry admission;
its existing metadata-only `status` and `inspect` paths are preserved. Alternate
`collection.store` access uses the separate `document-collections` root and a
domain-separated, host-selected namespace digest. This is a source audit of that
isolation, not an end-to-end managed-input storage-effect qualification.

An admitted managed tool effect with missing or unknown cleanup now makes live
and reconstructed lineage unavailable. Cancellation, owner interruption, failure
and result preparation cannot use that incomplete stage as a reusable admission.
Its earlier external effect may have happened; recovery never replays it.

## Exact focused checks

The isolated graph `_build/managed-tool-sol-20261028` used actual `/tmp` tmpfs
fixtures and helper SHA-256
`ba559266929f43175b782e6115791d92844a59651d1de18b72fdbe899a0cfb7a`.
There were no live accounts, paid services or aggregate test suites.

| Retained log | Result and scope |
| --- | --- |
| [Interrupted-effect compile](source-lock-namespace/effect-interruption-compile.log) | Strict compile succeeded without diagnostics. |
| [46821](source-lock-namespace/effect-stages-interruption-46821.log) | **2 passed, 4 excluded**, 0.2 seconds. Separate MCP start/send stage chronology, exact cleanup, and unavailable live/Saved recovery after admitted missing cleanup. These are protocol/owner fixtures, not actual MCP transport owner-loss tests. |
| [Pinned-helper compile](source-lock-namespace/pinned-lease-compile.log) | Strict compile succeeded without warnings. |
| [46822](source-lock-namespace/protected-lease-46822.log) | **3 passed**, 0.09 seconds. A substitute helper demonstrably emits a forged live lock frame on the ordinary path; protected source and live Session locks ignore it, enforce real exclusion and can be reacquired after release. Actual managed shell spawn also ignores the substitute helper. |
| [Namespace compile](source-lock-namespace/unmanaged-namespace-compile.log) | Strict compile succeeded without warnings. |
| [46823](source-lock-namespace/unmanaged-namespace-46823.log) | Test-module compilation stopped because the newly referenced synthetic MCP HTTP support file was absent from the private graph. No test result is claimed. |
| [46824](source-lock-namespace/unmanaged-namespace-46824.log) | **1 passed, 2 failed, 65 excluded**, 5.5 seconds. The real native late-conversion read/write control passed. Both Session refusals occurred, but fixture assertions expected `collection_unavailable` instead of the existing normalized `collection_consent_denied` result. |
| [46825](source-lock-namespace/unmanaged-namespace-session-46825.log) | **2 passed, 65 excluded**, 5.2 seconds. Only the two corrected Session assertions reran: genuine V3 capture followed by a newly reviewed v1 reader refuses note bytes; an already live v1 reader first reads ordinary content, then refuses after protected-format introduction. Saved reconstruction succeeds. |

The second Session conversion control introduces a reserved format row through
the trusted Collection host primitive. It tests late boundary checking, not a
signed first-publication flow. The other Session control creates real V3 managed
metadata through the normal installed extension capture path.

## Provenance and limits

The [manifest](source-lock-namespace/manifest.json), SHA-256
`c4a3630ed593fb676f40a4bd0c3b1d6074caebe83227c44f8765fd2666584277`,
binds 25 frozen source/fixture/log/runtime artifacts. The runtime inventory records
208 BEAM hashes. The tested Runner BEAM is
`12f9afbbe96e68af104a27ec5e316ebdae2ca1cb2013c65f649b7d13815ae3e2`;
the tested Session Lock BEAM is
`543cd20fafc625a232221f83baedb9300e95c98ea898ad635218fd434a157b40`.
Later shared-source guarded review and supersession edits are excluded from this
snapshot. Parent MCP transport checks and their exact newer overlays are recorded
separately in [managed MCP integration](managed-mcp-integration.md).

The trusted raw `Collection.execute/4` host primitive still grants no source or
policy authority by itself. This repair closes the generic worker entry, not
every conceivable trusted host misuse. Native shell refusal after held approval,
delegation, internal tools, extension action inheritance and managed-input document
storage remain separate C0 integration work. No broad task, platform, recall
quality, endurance or final milestone acceptance follows from these checks.
