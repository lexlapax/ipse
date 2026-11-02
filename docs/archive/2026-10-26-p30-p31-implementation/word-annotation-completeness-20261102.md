# Word annotation completeness and cited locations

2026-11-02, worktree based on `bd222bf`. This is a candidate implementation
record, **not P31F acceptance**. Pure and native Session component checks pass;
final package and independent Word-quality verification remain pending.
Current procedures and extraction contracts belong to
[Corpus](../../operator/corpus.md#acquire-a-small-word-document-from-the-workspace)
and the [developer guide](../../developer/knowledge-extensions.md#follow-acquired-document-bytes-into-cited-storage).

## Close a specific coverage gap

The bounded parser already produced annotation identities, uniquely matched body
reference sites and supported same-paragraph comment ranges. Recipe v14 still
reported unresolved anchors for every annotation part. Recipe v15
checks the declared identities against the emitted paragraphs and matched body
references before emitting that warning. Text extraction and locator geometry
remain unchanged.

Every declared identity must have emitted text and a unique mapped reference;
every visible body reference must resolve. Comments with range markers also need
a supported range. Orphaned, empty, hidden-only, missing, ambiguous and unmapped
cases remain partial. Unsupported rendering keeps its own warnings; automatically
numbered note marks remain unsupported even when the note's site is known.
The candidate does not establish complete Word layout fidelity.

Microsoft's [comment reference contract](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.commentreference?view=openxml-3.0.1)
distinguishes point and range comments. The parser's supported range remains
narrower: visible text in one emitted paragraph or table cell, with ordered
markers and one matching reference. Its existing conservative refusals and
partial-coverage warnings remain in force.

V14 packed sources and citations retain their recipe and remain readable; v15
uses the same bounded block groups. Unknown future recipes do not acquire that
geometry implicitly. Text/Markdown/PDF retain recipe v2. No dependency, runtime
service, permission, native protocol or storage limit changes.

## Verification completed so far

The [machine record](word-annotation-completeness-20261102.json) records exact
source and log hashes. The pure checks run in plain VMs; their fresh Corpus
artifact is compiled independently. Native integration uses actual Sessions and
the public acquisition, query and resume paths.

- Seed 791788: **41 passed**, 64.6 seconds, after formatting. Covers extraction,
  annotation positives/negatives, exact source/citation matching, changed-offset
  refusal, packed block maps, legacy v14 and future-recipe refusal. Includes the
  loopback no-fetch control and fresh-artifact probe.
- Seed 791789: **32 passed**, 30.1 seconds, covering the separate evidence and
  Collection chunking files. Chunk-capacity arithmetic is not populated capacity.
- Seed 791791: **two native annotation controls passed**, 20.5 seconds, with
  State and Collection storage, all three annotation families, exact Unicode
  point/range offsets, original binary hash, complete status, Saved and identical
  evidence after idle resume. No model request occurs.
- Seed 791793: **32 acquisition/ingestion/packing/chunking regressions passed**,
  128.5 seconds. The frozen public 16,079-byte Word input is enabled and verified
  by its original SHA-256. This includes actual acquisition, staging, current-use
  refusals and unknown/recovery boundaries; a round trip is no rendering oracle.
- Seed 791794: **29 fidelity cases passed**, 50.0 seconds, after preserving the
  parent's SDK path order for successive `-pa` arguments. This is its own rerun,
  not an additional independent sample population.
- Seed 791795: the document-verifier gate passes its missing/false/substituted
  check matrix. The gate now requires nine named checks, including actual linked
  and orphaned annotations.
- Seed 791796: the complete verifier regression file passes **35 tests**,
  80.8 seconds, preserving its other source/installed and grammar controls.
- The independently built `state-documents` Corpus artifact passes all **nine
  source artifact checks**, including linked/orphaned footnotes, endnotes and
  comments, with unchanged inventories, precompiled harness and private home.
  A separate parser-enabled source build supplies the existing PDF controls;
  default PDF acquisition remains off. The first artifact command omitted the
  required preset and refused before construction; the explicit-preset build
  succeeds, with both logs retained.
- Isolated compilation of the six extraction/evidence source files passed with
  warnings as errors, without replacing the host runtime.
- The default source build, strict Mix compile, full format check and credential-free
  demo passed. The demo uses a private temporary Ipse home. Its first subprocess
  launch used a relative executable and failed before startup with `:enoent`;
  the absolute launcher succeeds. Both logs remain separate.
- Documentation checks pass; exact counts and logs are retained in the machine record.
  Git enumeration emitted permission warnings for private staging directories;
  their contents were not inspected or copied.

The first annotation positives failed against the old parser. Subsequent broad
runs also exposed an outdated artifact assertion, a sandbox-denied loopback
listener and missing SDK paths in the pure test launcher. The warning assertion
was retained while correcting the launcher. Finally, seeds 791784/791785 found
an invalid source fixture: small metadata uses an embedded version-3 receipt,
whereas a separate `document` field belongs to the version-4 manifest path.
The fixture now follows `Corpus.collection_attrs/5` and explicitly verifies that
the invalid duplicated form still refuses. No source validator was loosened.
Seed 791786 passed all four targeted cases; seeds 791787 and 791788 each passed
all 41 selected tests. Reruns are separate observations, not added sample counts.

The first native annotation run, seed 791790, passed State but stopped at the
Collection profile's normal `draft` result. The test incorrectly expected an
immediate final result. Its corrected path consumes the existing bounded staging
continuation and still requires final success, complete citations and identical
post-resume evidence. The passing two-profile run is separate from that failure.
No product gate, storage allowance or deadline changed.

## Remaining verification

The [complete frozen `9f1707c` suite](full-suite-cancel-repair-20261102.md) passes
with 3,753 tests and zero failures; it does not contain this increment. Its
post-inventory verification completed before these native controls began.
Current native/Mix/PTY cohorts remain serialized.

The owning operator/developer chapters were reviewed as whole manuals and their
annotation, citation and recipe explanations integrated with existing acquisition
procedures. Installed artifact checks and exact candidate packaging,
independent Word quality, full document lifecycle/capacity, local-pair quality and
the original milestone-wide audit remain separate open gates.
