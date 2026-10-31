# Batched source-citation validation — 2026-10-29

Historical development evidence following the [maximum-count model](shared-producer-v4-full-facts.md);
the [plan](../../plan.md) owns acceptance. This changes domain validation and
test tooling, not Host source authority or public fact production.

A synthetic callback probe of the 256-fact group observed one `append_unit`
callback at roughly 4.6 seconds, close to the existing five-second worker
callback limit. A trial vector-decoder refactor did not target that slow phase
and was withdrawn; the retained source uses the original codec. The probe wraps
`Producer.resume` in a developer model, not the complete worker transport, so
it does not qualify production deadlines.

`Evidence.valid_spans?/2` now validates a source and its chunk list once for a
bounded list of citations, then applies the same closed citation, source identity,
span, document locator and quote checks to each. `valid_span?/2` uses that same
path for one citation. Projection fact packing validates every fact and its
selection first, then validates their combined citations through the batch path.
No fact or citation is accepted merely because another one passed.

Focused controls compare the old and new span validator on a valid citation and
four malformed variants for both a plain source and a segmented DOCX source.
The checked-in tests also reject a forged Word cell locator in a batch. Nine
producer/integrity model cases, four guard1/public-entry model cases, 31
evidence/chunking cases and five Word-ingestion cases each against source and
the correct `state-lexical` artifact passed. The first Word artifact run used
the wrong `collection-dense` preset; the subsequent source run exposed an
incomplete sequential test loader. Both failures are retained. The loader now
strictly compiles the full source module set and both its source and artifact
paths pass.

The same synthetic 256-chunk, 256-short-fact private append completed across
37 invocations with a maximum 506 reads; test execution took 230.0 seconds.
A separate one-unit callback sample observed a 3.35-second maximum. These are
single, differently scheduled samples, not a controlled performance guarantee
or native Session timing. Full escaped fact widths, concurrent load, real
Session handoffs and callback deadlines, independent review, fact inference
authority and native large-group publication remain open. No live model call ran.

The [manifest](shared-producer-v4-batched-spans/manifest.json), SHA-256
`419e774d93dbb0b253066b475b6ddd8e87776c59c4f837dbc874be2a64576ae6`,
pins 122 source, artifact, script and log files. The generated span-comparison
test retained there is the DOCX version; its builder and separate plain-source
log are retained, but the earlier generated plain test was overwritten by the
DOCX probe. The two artifacts were strictly built; the new collection-dense
artifact was not rerun in a native Session for this change.
The current document-ingestion test was formatted after this freeze; an
[AST comparison](batched-spans-format-check.log) confirms no semantic change.
