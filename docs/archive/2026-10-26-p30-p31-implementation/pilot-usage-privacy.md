# Content-free pilot usage and partial live evidence — 2026-10-29

This follow-up to the [candidate-audit increment](pilot-candidate-audit.md)
repairs another public-progress path and preserves the first outcome of a
specifically approved live run. The [plan](../../plan.md) owns acceptance;
neither this repair nor partial model data qualifies protected capture or P30/P31.

## Repair raw provider-usage passthrough

The pilot retained the provider's entire usage object in progress and returned
records. The live response's usage included attribution items with content as
well as numerical counters. That invalidates the earlier assumption that usage
was inherently content-free. The run's wrapper printed only selected numerical
progress fields and stored its full progress in a private file, so that discovery
does not establish public disclosure of this run's candidate prose. The ordinary
pilot CLI did expose the raw field and needed repair.

The shared initial/continuation response path now calls the existing
`Ipse.Usage.normalize/2`. Progress contains only its closed counters, derived-field
names, counter quality and fixed issue labels. Unknown attribution is omitted;
malformed content in a counter becomes an invalid counter record rather than
being echoed. The private candidate audit and selected provider remain unchanged.
The [contributor procedure](../../developer/capture-pilot.md) describes the
normalized `usage` format and its unknown/invalid limits.

The [focused synthetic suite](pilot-usage-privacy/ipse-pilot-usage-redaction-47008.log)
passed **15 tests** in 0.4 seconds. The new regression supplies nested attribution
content, string counters and a non-map usage payload, checks callbacks and returned
records for redaction, and verifies valid token counts survive. The
[independent review](pilot-usage-privacy-independent-review.md) acknowledges the
earlier review gap and independently checks initial and continuation output for
ChatGPT and Ollama with valid and malformed counters. All four synthetic probe
cases passed without a live request or a redundant suite run.

## Preserve the incomplete live run

The user explicitly approved one new nonpublishing pilot of at most 120 calls on
the configured ChatGPT/gpt-6.1-sol route, with private synthetic candidate audits.
The same launcher started once after an earlier automatic-review rejection.
It sent only the fixed exposed cases and conversation replies, published no
records and performed no workspace tool effects. It used Ipse's own configured
authentication and made no model/provider substitution or download.

Exec `84970` ended with exit 0 after 96 response records, without the launcher's final
result file or outcome record. A matching process was absent after exit. The
[post-exit inspection](pilot-usage-privacy/ipse-partial-pilot-inspection-47009.log)
finds 57 audited turns and 39 proposals through conversation 3/source 17. The cause and exact
attempted-call count are unknown. There was no restart, retry or inferred
completion. The full 120-call reservation remains charged conservatively:
226 of 300 charged including the prior 106; 74 remaining. This is not a claim that
120 new requests actually occurred. The last three intended turns are unobserved.

The [sanitized partial receipt](pilot-usage-privacy/sanitized-partial-receipt.json)
retains numerical observations and raw-file hashes while normalizing usage.
A [separate check](pilot-usage-privacy/ipse-sanitized-pilot-check-47015.log)
validated all 96 closed usage records and absence of content-bearing fields.
Raw progress, candidates and review input remain owner-only under
`_build/capture-candidate-audit-20261029-47000`, copied without altering the
original private `/tmp/ipse-candidate-pilot-20261029-47000` evidence. They must
not be printed or committed. The [accounting checkpoint](live-call-accounting.md)
records the approval, rejection, execution and conservative charge in order.

## Bound development judgments to the observed data

A separate agent reviewed only the supplied ordered source/candidate pairs,
with original case classes and model identity withheld from its task. It dispatched
no Ipse provider calls and did not inspect the implementation or reconstruct
labels from the exposed case catalog. The [label record](pilot-usage-privacy/development-labels.json)
binds the exact private review-input hash and publishes only IDs, closed labels,
reason codes and numerical counts, with no candidate/source prose.

That reviewer judged 39 candidates source-supported: 34 useful, 3 duplicate/not useful
and 2 uncertain. Intake labels distinguish 28 new proposals, 6 replacements, 3 duplicates
and 2 uncertain proposals. Of 18 turns with no proposal, 17 were judged appropriate
omissions and one remained uncertain. All 39 prototype duration categories were
judged appropriate by this reviewer; that is an agent judgment under the pilot's
category vocabulary, not protected native category admission or a gold label.

Strict export verification found two uncertain values encoded as string `nil`
instead of JSON null. The agent preserved its original output and corrected
only those scalars. The initial [failed export](pilot-usage-privacy/ipse-preserve-partial-pilot-47016.log)
and [corrected export](pilot-usage-privacy/ipse-preserve-partial-pilot-47017.log)
are retained; the root [recomputed every aggregate](pilot-usage-privacy/ipse-check-pilot-labels-47018.log)
from the final typed rows. No judgment or source binding changed.

These are partial, exposed development data and one independent agent's
judgments. They establish no held-out, human, installed-user, actual protected
capture, stable-prefix/cache, per-day intake or workload-ratification acceptance.
Public hashes/counts alone cannot prove semantic labels without the private pairs.
Keep this first outcome rather than repeating it until a favorable result appears.

The [manifest](pilot-usage-privacy/manifest.json) pins final changed source snapshots,
receipts, content-free labels, predecessor manifest and relevant loaded host
modules. No aggregate source/package test was run. The full P30/P31 goal remains
active with usable protected journeys and final qualification still required.

The batched [documentation check](pilot-usage-privacy/ipse-usage-privacy-docs-47021.log)
passed 763 Markdown files and 6,432 local links with zero errors. It retained
permission warnings for private ledger directories. The earlier check had one
missing target because this increment's new manifest was not yet written; that
[failed receipt](pilot-usage-privacy/ipse-usage-followup-docs-47019.log) remains.
The manifest was then created before the successful check. No runtime suite was
repeated for this navigation repair.
