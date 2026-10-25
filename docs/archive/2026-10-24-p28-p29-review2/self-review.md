# Author adversarial review before v0.1.0

Dated 2026-10-24. Historical evidence of the developer-requested author review of
`e2aefb5`, after the second independent review's runtime repairs. This is not a
new independent acceptance verdict. The [plan](../../plan.md) owns remaining
release decisions; [verification training](../../developer/testing.md) owns the
current procedure. The [receipt](self-review.json) records controls and results.

## Findings and repairs

**S1, P3: linked archive admission.** Two correctly named archive symlinks pointing
outside the staging directory, with matching sidecars, passed `verify_assets!/2`.
The checksum reader followed those links; a non-regular object could also fail or
block during hashing. Admission now checks `lstat` before hashing: archives must
be nonempty regular files and sidecars must be regular files. Controls cover a
symlink with valid checksum, missing archive, empty archive, directory and linked
sidecar. The synthetic external target stays unchanged. This protects trusted
release staging from accidental indirection; it is not protection against a
hostile concurrent directory replacement. Platform jobs still own archive-content
and installed-runtime verification.

**S2, P3: vacuous setup diagnosis verification.** The shared validator accepted an
empty `checks` list. Bare doctor had a complete-ID check, but configured setup
routes could lose findings without failing this assertion. All three routes now
require version 1 and the exact complete ordered ID set, before the existing
warning/skip policy. Controls remove all/one findings, duplicate/reorder findings,
change the version and inject warnings or unexplained skips. A full valid report
and the documented macOS warning remain positive controls.

**S3, P3: numeric stream codes lost.** A subsequent wire-format counterexample
found that the error-code repair retained string identifiers but discarded numeric
OpenRouter codes. The [official error contract](https://openrouter.ai/docs/api_reference/errors-and-debugging)
defines numeric codes and documents their use in mid-stream SSE errors. An actual
parser call with synthetic code `429` withheld both the prose and the code.
Chat Completions now converts integer HTTP codes in 100..599 to decimal text;
other values still pass the existing identifier filter. Both top-level and choice
error frames retain 400/429/502/503 while withholding private prose. Out-of-range
integers, floats and maps stay withheld. The actual parser counterexample now
retains `code: 429` and no private prose; all twelve adapter tests pass, seed
674910. This changes diagnostic text, so the full runtime baseline is repeated
and recorded in the final verification receipt.

## Additional boundary review

Reviewed native grants through Session approval, tool validation, durable start
and scoped path checks. Grant keys include every shell argument, workspace and
sandbox; children/external tools do not inherit native grants. Existing controls
cover changed shell text/arguments, confinement/workspace drift, symlink/hardlink
refusals, headless denial, revocation, pending and executing cancellation, and idle
resume without authority. Reusing a granted script after a granted edit remains an
explicitly documented operator choice, not a promise of immutable script content.

Reviewed diagnostic producers and terminal escaping, selected-key filtering and
stream error identifiers, fixed subscription endpoints, exact versioned asset
names, workflow ordering, mutation guards and stable/RC note rendering. The numeric
wire control above found the additional diagnostic defect after the first two
verification repairs. The short private MCP-value collision
remains a reproduced and documented limitation; this review does not grant an
exception to privacy filtering. Fixture checks do not establish live provider or
subscription behavior.

## Verification scope

The two pre-repair counterexamples admitted invalid inputs; the same controls now
refuse them. Focused release/verifier tests pass **43/43**, seed 153432, 79.1 seconds.
The strengthened installed verifier passes all twelve checks against the retained
`b7d3bce` Linux archive, including actual bare/demo-setup/Grok-setup doctor reports,
with unchanged inventories and no model calls. Formatting and manual checks pass.
The complete native-inclusive suite at `e2aefb5` passes 1,782 tests with 19 excluded.
S1/S2 change developer verification only; S3 subsequently changes stream-error
text. These scopes are kept separate, with new full and hosted results recorded
once terminal. No native implementation or dependency changes are involved.

No stable tag, release draft or publication, new authorization, paid inference,
or private transcript was created by this review. Human walkthrough qualifications
and live-provider acceptance are not inferred from these checks.
