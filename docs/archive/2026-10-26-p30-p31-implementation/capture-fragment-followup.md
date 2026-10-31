# Capture fragment admission follow-up

2026-10-27. Working-tree repair within P31 intake; this does not complete or
qualify [P31](../../plan.md#p31-usable-knowledge-and-prompt-assistance).

Previously an exact substring from an interactive operator event or typed
outcome could pass both the worker's direct-note classification and the host's
literal-source recipe. A synthetic example selects a report's claim from a
larger message; both layers accepted it as a literal note before the repair
(seed 46472). The source proof was syntactically valid; this test does not show
an actual protected publication.

The worker now treats a selected fragment or partial-coverage event as a
pending proposal. The host independently refuses literal publication unless the
source has available coverage, starts at byte zero and has the same content
and quote digests. Exact text and permitted origin remain required. This is a
conservative whole-event check, not evidence that a whole event is a direct
assertion: a whole event can itself be pasted or quoted third-party material.
That classification, explicit proposal acceptance, current eligibility and
the protection of existing records remain open. This change does not reclassify
previously saved records, and existing callers that submitted literal fragments
must use the pending path or obtain a supported whole-event source. Historical
or private replay and migration behavior must be verified before enabling this
as a production recall journey.

The initial expanded working-tree run had 31 passes and 10 failures because the
native filesystem profile is unsupported here (seed 46473). A separate diagnostic
graph with the existing test-only helper override and the changed host and worker
sources passed all 41 selected capture, recipe and normalizer tests (seed 46474).
This is not production-profile qualification. A later working-tree run passed
20 non-native tests (seed 46475), including an independent-VM worker continuation
that selects a fragment and reaches the pending lookup. No model or protected
production storage was used. An attempted diagnostic copy into `/tmp` failed
with disk quota errors and its incomplete copy was removed; the passing graph
was copied under the repository's build directory.

The synthetic Session integration was then extended to build the Knowledge
artifact separately and run two native-terminal inputs: the complete event and
the exact `café 日本語` fragment within it. With separately selected matching
saved-consent policies, the whole event produced a current literal note and the
fragment produced a `never_current` pending record. The fragment receipt retained
the interactive origin, nonzero byte offset and distinct source and quote hashes.
Both terminal journeys use a synthetic PTY, model, home and collection; neither
is a human attestation or live-model test. The two parent tests passed (seed
46477) in the diagnostic graph after overlaying the current host and Knowledge
sources. Its helper still has the test-only kernel override. This verifies the
worker's pending route through a Session and managed publication; it does not
establish safe classification of a whole pasted event.

A further synthetic adversarial Session test builds a modified fixture worker
with the former direct-classification behavior. For an actual PTY fragment, the
modified worker submits a literal-note request under a matching saved-consent
policy. The current host reports failure before publication; Collection remains
empty and consent records no operation. The same test against an isolated copy
of the pre-fix host instead reached an `ok` outcome (seed 46479), causing the
expected-refusal assertion to fail. The repaired host's selection passed two
parent tests (seed 46478), including all three terminal child journeys. This
comparison uses the private test-only kernel override, synthetic PTY and models;
the deliberately weakened worker is a test fixture, not a released artifact.

## Whole-event attribution counterexample

An isolated continuation replaced the synthetic terminal input with
`Quoted third-party report: synthetic café 日本語 1`, leaving the separately
built current Knowledge worker, whole-event model behavior, saved-consent
policy and host publication logic unchanged. The existing Session assertion
still observed an `ok` managed publication with `current` eligibility as a
literal note. The two parent tests passed (seed 46625), including the whole
event and separate fragment and weakened-worker child controls. This is a
counterexample to interpreting exact whole-event provenance as the operator's
own assertion; it is not a passing attribution or production qualification.

The changed synthetic test and PTY driver are retained in the diagnostic graph
at `_build/intake-diagnostic-46474/_build/third-party-capture-46625/`; their
SHA-256 values are
`55c44fbc1221df41d8c6cd7a6a7b67870e32fdbc11141227f848d37b7b2c2b55` and
`73f25daadc382fdeb84d0df77f4eff6c650863c238995644cf43b0c5c6ce6dbf`.
The diagnostic graph uses the private test-only kernel override and synthetic
home, terminal and model; the altered fixture files were restored after the
run. A safe attribution design and explicit handling of already published
literal records remain required before enabling current automatic recall.

## Unbound native question answers

A native question answer proves the bytes and input origin, but the current
capture recipe does not bind a proposition to the question, nor does an answer
approve an assistant's premise. Previously the worker and host accepted the
whole answer as a literal note even for `yes` or `blue`. Both now conservatively
route native question answers to pending proposals; the host independently
refuses a worker's forged literal request. Interactive whole events and typed
outcome metadata retain their existing rules. This does not solve quoted
whole-event attribution, secret exclusions, explicit acceptance, or the
handling of every historical read path. A pending publication still requires
the corresponding saved grant; this change does not expand consent.
The host recipe is shared across extensions, so the literal restriction also
applies to other users of that recipe; it is not confined to the bundled worker.
Rebuilding the worker changes its artifact identity, so an existing grant pinned
to the earlier artifact is not silently transferred; the operator must review
the new artifact through the existing permission flow. The host recipe change is
stricter for previously pinned literal recipes as well.

The new worker and host unit tests failed on the old behavior (46637) and 18
focused tests passed after the repair (46638). A diagnostic selection of worker,
recipe, legacy and V3 normalizers passed 60 tests (46639) on the private helper.
An actual signed V3 publication control with synthetic source members refused a
forged answer literal and preserved its checked root (46641). Restoring the old
host check in an isolated copy caused the same test to publish successfully and
fail its refusal assertion (46642); restoring the repair passed (46643). The
expanded control then published that source as `never_current` pending (46644).
The separately built Knowledge Session controls also passed both parent cases
after the change (46645), covering the existing synthetic interactive and
unattended routes, rather than a native-question publication journey.
Seed 46640 accidentally selected the preceding test, not this control. These are
synthetic authorization fixtures with the test-only kernel override, not a real
operator, production storage qualification or proof of safe automatic recall.
The running full regression snapshot predates this change.

At that stage historical observation could still return a previously stored
answer-derived literal; the separate managed dependency derivation re-extracted
the recipe and refused it. Raw reads and any other consumers were not thereby
repaired, and existing records were not migrated or deleted. A complete typed
question and acceptance contract is still needed for future promotion.

Working-tree SHA-256 values are
`d725052994d54c29cd3af4cb192bdc59f708b45be152d1a74f2f19e14d495a76` for
`records.ex`, `af2ecd697bcc9e0df5a7d33ff9309d4c3efb7dc636d50b39005b82c741a8c48e`
for `managed_recipe.ex`, `ca55d246d218d40b05d7e70989bdd8c3fe0f1f407e5c659335834f145c13e2a8`
for the worker test, `71c133517bce856c67d2a59b1cdeefd6a35e01f009bf37c1c58b2078371d6d05`
for the host recipe test, and `b8f6744d089affa3dfd2762f491bfb7dadf3a9f949f00627cd7fdd62259f0359`
for the signed V3 integration test. All passed a targeted formatting check.

A further synthetic control constructs a native question and answer receipt
through `OperatorAnswer`, admits it into `SourceIndex`, resolves the real
source proof and confirms the worker constructs a pending proposal. The worker
and host recipe suites passed 19 tests (46646). The resulting worker-test
SHA-256 is `97cf9a8dba626a509a790c87d92584975da043f07ef7d9132afa32ce8d6b20f5`.
Its observation is synthetic; that control did not exercise a terminal-driven
question through actual managed publication.

The separately built Knowledge Session test now also runs a question through a
synthetic PTY. A native answer source reaches a saved-consent managed pending
publication, with signed `never_current` metadata. A deliberately weakened worker
then attempts to publish that same kind of answer as a literal; the repaired host
refuses, with no committed collection record or consent operation. All three
parent Session tests passed (46649). In an isolated copy with the old host check,
the weakened worker instead published a `current` literal, causing the expected
refusal assertion to fail (46650 and 46651). After restoring the host, all three
parent tests passed again (46652). This uses a synthetic terminal, source, model,
saved policy and private test-only kernel override, not a human or qualified
production storage. The updated Session test SHA-256 is
`a596d34f4c56285ca2ecef953f7070eca2b0eaf4502d47b061d959bfa40df01c`.
The private graph's PTY driver at 46652 predated later planning-specific driver
additions. After overlaying the current driver, all three parent tests passed
again (46667); its SHA-256 is
`6a82d26b23eb7cb80974f3546860fdbdf830b13207d6f5035a3790e0e66a252b`.

The PDF-enabled diagnostic archive was separately extracted under
`/var/tmp/ipse-answer-archive-nKsygOyQ`. With a utility-only PATH, a synthetic
installed-runtime probe loaded `Records` from the packaged Knowledge artifact
and `ManagedRecipe` from the packaged host. It confirmed pending construction,
`never_current` proposal extraction and refusal of a forged literal. The retained
probe is `_build/production-build-Au0AOr9b/_build/installed-answer-probe.exs`,
SHA-256 `9b3a0a4c20c9ddf9d1ac58c07b688c98e23c94d3774af65543d25a04da6c804a`.
This is a pure synthetic installed-runtime check; it does not authenticate an
actual source, exercise terminal publication, or qualify storage on this kernel.
The archive has the dirty-source reference limitation recorded in the handoff.
The same pure guard probe also passed against the later archive containing the
signed-observation repair, with both modules loaded from that extracted archive.
Its updated probe is `_build/production-guard-inGks1jJ/_build/installed-answer-guard-probe.exs`,
SHA-256 `ae758064bc8e93bcd6dbc39b273b6eea7df4ae59e3b0fb81aa9d0d43f96aea4c`;
it has the same synthetic and storage limitations.

## Historical signed observation repair

The actual retained synthetic signed literal from the old host was observable
through `managed_record`, although managed dependency derivation refused it.
The observation now re-extracts the selected recipe from the signed value and
checks its lineage and category before returning it. The embedded source proof
is used only for structural consistency; it is not authenticated as a current
source or current consent. Consequently the stricter native-answer rule refuses
old answer-derived literals on this observation path. Generic raw reads and
existing stored records are unchanged.

An isolated regression creates a signed literal with the former recipe module,
observes it with that module, restores the current module and requires refusal.
It passed (46660); replacing the reader with its pre-repair implementation made
the assertion fail (46661). The restored signed-publication, observation and
read-view selection passed 67 tests (46662) with the private test-only helper.
The current `observed_read.ex`, V3 integration test and subprocess fixture
SHA-256 values are
`e8ea58cc466b8669da13b3402e8782be8bc7b71aea55d6eb3d79ec142f9172aa`,
`15de6c19ef5017deda01bf8a4a9ca3608dd6f26a7fefd35af314a96462c06caf`, and
`61c54df4c9842ec84037d34e1021e32915780c9db4cbb392d15f45ca21017c5d`.
The running full regression and the earlier package predate this repair. These
checks use synthetic authorization and do not establish current source,
consent, delivery-time freshness or production storage qualification.

The subprocess fixture was then extended to create both an old signed native
answer and an old signed partial-source literal. The old recipe observes both;
the current recipe and repaired reader refuse both (46664). The updated V3 test
and fixture SHA-256 values are
`8507c5e538865ccd2d81bb60b3c0372bd85dc9117a767683d7be0a1ab1f351c3` and
`03e8fd536f9934dd5a3232de2397ae89d73de1179dce0595434546c5a0c54917`.
The host source hash is unchanged. Generic raw reads and stored records remain
outside this reader's guard; no durable migration or cross-session freshness is
implied. Full run 46663 includes the earlier native-answer fixture but predates
this added fragment control.
The current signed-publication, observation and read-view selection then passed
all 67 tests with the extended fixture (46666) on the private helper.
The reader was subsequently corrected to use the selected recipe's evidence
path; see the [pending observation follow-up](pending-observation-followup.md)
for the newer hashes and 69-test selection.
