# P28/P29 independent audit and follow-up

Dated 2026-10-24. This record preserves the independent audit supplied by the
developer, then tracks implementation repairs. The [plan](../../plan.md) owns
current acceptance; the [operator](../../operator/index.md) and
[developer](../../developer/index.md) manuals own supported procedures.

## Independent evidence

The [original report](independent-audit.md) reviews clean source `1084f9a`, with
runtime source identical to `288a6a2` and `622a2c8`. Its text is preserved as
supplied. The reviewer reports 1762 passing Linux tests, 19 excluded, successful
build/demo/package/installed checks, no P1 findings, one P2 and thirteen P3s.
Those checks belong to the reviewer; they do not verify the repairs below.

Qualified human walkthroughs, stable tag/publication and live xAI inference remain
open. The assisted Linux run is accepted by the developer but does not establish
an unassisted, macOS or human-upgrade walkthrough. The first xAI API attempt
returned HTTP 403; no successful API inference or subscription eligibility follows.
There is no approved Ipse xAI OAuth registration yet.

## Repair dispositions

| Finding | Repair and verification boundary |
| --- | --- |
| F1 | Remove arbitrary reason inspection from runtime error producers; bound binary diagnostics and refuse term/path/control dumps. Test recovery anchors and context-refresh recovery text. |
| F2 | Apply the existing Transport safe-identifier filter to stream error messages; withhold arbitrary provider prose and retain usage-before-refusal. |
| F3 | Developer approved the official artifact actions on 2026-10-24. Both matrix jobs retain their verified archives; the final job collects and admits the complete set before creating any draft. Manual dispatch exercises the handoff while tag-only guards skip release mutations. Actual hosted handoff verification remains required. |
| F4 | Replace the release body with standalone installation/features/limits and absolute versioned GitHub links. The [previous notes](release-notes-before.md) retain the earlier evidence narrative; relative links are adjusted for this archive location. |
| F5–F6 | Doctor recommends saved setup and lists discovered configuration sources with independent parse/trust status, including refused project configuration; no settings are applied by source inspection. |
| F7 | Test actual saved API configuration for every registry secret, validate recovery heading anchors, align Ollama probe/inference loopback and reject unexpected installed-doctor warnings. The explicit macOS experimental-native warning remains expected. |
| F8 | Put logout/revocation before removing the executable. |
| F9 | Shared native inherited-key policy, registry-driven real-shell check and compiled native conformance probe; require unique rate-card coverage. Record reasons for intentional registry exceptions in the WP1 receipt. |
| F10 | Preserve Gemini reasoning refusal guidance, omit foreign call IDs while retaining native IDs, and refuse Vertex mTLS destinations. Live foreign-history acceptance remains unverified. |
| F11–F12 | Correct endpoint help and explain edit/command grant composition, including mutable scripts. |
| F13 | Exercise SDK and child writes with an active parent edit grant; cancel real work and verify existing edit/command grants survive. |
| F14 | Reconcile RC deletion/current walkthrough wording and distinguish original-scope verification; add missing hosted identities/job steps from GitHub; disclose the four-second after-effect fixture timeout. |

## Verification in progress

The first focused iteration had 84 passing tests and one failure: the new stream
error fixture omitted the required pinned identity and was refused before its
error message. Adding the normal identity frame corrected the fixture. The next
expanded run passed 160 tests (seed 797885, 46.3 seconds), including real child/SDK
effects. That run preceded the final anchor/context and Gemini refusal assertions.
Final focused, full native-inclusive, installed-package and hosted checks are
still required for the resulting candidate. No paid/live inference or release
creation/publication is part of these repairs.

The `2a9d950` full run exposed two regressions in the first F1 repair: changed
skills lost their stable `skill_catalog_changed` cause, and scoped preflight
refusals lost their specific cause. The correction maps known causes to fixed
workspace prose and withholds arbitrary terms. The missing-target assertion now
requires `target does not exist` rather than raw `:enoent`; all outcome, unchanged
queued-call, journal, restoration and non-replay assertions remain. The original
changed-skill assertion is unchanged. The corrected focused workspace/native
selection passes 56 tests (9 excluded), and 31 additional resource/Session-context
checks pass. Final baseline verification must use this subsequent source.
