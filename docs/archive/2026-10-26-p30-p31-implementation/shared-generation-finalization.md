# Bounded shared-generation finalization

Recorded 2026-10-29. This section implements extension-owned finalization after
the independently reviewed [checkpoint prerequisite repair](shared-job-prerequisites.md).
It does not restore protected writes. The current strict Collection/State gates
remain unchanged, and none of these controls dispatched a native effect or used
a model service.

Later qualification, 2026-10-29: the gate statements in this receipt describe
its frozen pure-test cohort. Subsequent ordinary [State restoration](state-restoration.md)
and [document decision restoration](document-decision-restoration.md) admit
their scoped paths. The additive [native/public finalization control](shared-finalization-native.md)
uses that restored ordinary document path. Managed capture/output and other
protected paths retain their separate restrictions; the original no-effects
claim and frozen manifest here are unchanged.

The [manifest](shared-generation-finalization/manifest.json) binds exact source
snapshots under `_build`, compiled feature cohorts, the public Corpus artifact
and six chronological logs. Compiled artifacts remain under `_build`, rather
than in this archive. Earlier controller, directory and canonical-repair
snapshots remain immutable.

## Implemented behavior

`Reduction` authenticates a maximum of sixteen captured group summaries against
their exact captured catalog pages, source-head sequence and model/extraction
selection. It emits one existing-format manifest page plus entity occurrence
runs sorted by entity identity. Each run uses sixty-four-row immutable pages
and an authenticated bounded directory. At most eight runs are merged. A merge
step emits one existing-format sixty-four-entity page with exact sorted group
memberships. Missing input requests the exact immutable reference; a forged,
reordered, mismatched or malformed input refuses.

`Finalization` advances durable private Job version two through manifest
batches, entity merge, source-head digest, entity-row digest and selection.
Version-one jobs remain inspectable and their append plan digests are unchanged.
Ordinary Source, vector, fact and selected-directory schemas are unchanged. The
new selected root and all directory values are byte-for-byte canonical under
the existing Directory version-one recipe. Consumed summary/run references are
dropped from the active job once their reduction no longer needs them.

`Job` reads each phase's inputs at one native generation. It stages immutable
outputs individually through the existing bounded prepare/commit protocol and
atomically advances the job plus captured catalog. The selected root is not
part of these earlier commits. Final selection prepares three exact sealed
values: job, captured catalog and selected root. It checks complete immutable
manifest/entity-page hashes and sizes before preparing metadata and again at
the sealed-stage generation, then sends `value_commit_at` with that exact
generation. It does not refresh the native epoch between the final proof and
CAS. Unknown results stop without a new continuation or retry. The public
Corpus `generation_job` action now includes explicit `finalize`; a known
intermediate commit returns the next explicit continuation. Capability grants,
SDK ceilings, sixteen effects and 512 reads are unchanged.

## Focused checks

| Receipt | Result |
| --- | --- |
| 46943 | Pure reducer: 17 groups, two manifest batches, five entity pages, 272 entities; root and selected values strictly equal canonical Directory output. Missing/forged/reordered runs and pages, invalid positions, selectors and catalog refuse. One passed, 2.5 s. |
| 46944 | Retained failure: a missing `end` in the new test fixture prevented the controller test from running. No native effects. |
| 46945 | Initial complete pure pipeline and pinned three-stage selection: one passed, 2.6 s. |
| 46946 | Existing edited-append prerequisite regression passed. Second fixture failed because the test harness reused an evidence directory; the harness now creates a distinct fixture subdirectory. |
| 46947 | Final pure control: ten durable phases, every phase through actual client SDK read/result validation to its first proposed effect, at most 86 reads before that effect. Seven final refs checked twice; three sealed metadata stages inspected; direct generation-500 commit, correct generation-501 receipt, missing prerequisite/stale catalog/unknown/gate-cause controls and selected-job inspection. One passed, 2.8 s. |
| 46948 | Official public `corpus/collection-documents` artifact built without diagnostics. |

The fixture has 136 sources and 136 supplied facts. Maximum job bytes were
5,361. Its read-only reduction estimate peaked at 72 transport calls; actual
phase protocol counts were 86, 20, 26, 29, 29, 29, 26, 22, 28 and 20 before
each first proposed effect. The final pre-staged selection used 29 reads and
proposed exactly one three-stage CAS. These are pure fixture/protocol checks,
not native execution, protected publication, model receipts or installed Word
quality evidence.

## Required qualification still open

Digest phases scan only directory metadata, never the complete 20 MiB source
or projection snapshot. They still enforce the complete invocation's 512-read
budget. Very wide or heavily escaped entity labels can exceed that budget;
this section establishes minimal usable finalization, not universal
full-profile metadata geometry. That geometry needs measurement and, if it
exceeds the current format's limits, an explicitly versioned bounded digest
representation or continuation design. No accepted capacity target is lowered.

Current protected publication remains gated. A populated 1,000-source/20 MiB/
10,000-chunk/5,000-entity/20,000-assertion build and rebuild is still required,
including exact transport operations, lifetime keys and immutable runs. Full
raw-source, lexical, native metadata, journal, retained old/staged replacement,
GC and migration peaks remain unmeasured. Later-use authority, actual model
receipt provenance and representative ordinary Word qualification remain
separate open requirements.
