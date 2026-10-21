# P27 readiness repairs, 2026-10-21

This is a dated review and verification record, not an operating manual or a
milestone completion claim. Base: `166914a365784e80afb48551138be01bc6b1044b`.
Current acceptance belongs to the [plan](../../plan.md). Follow the
[knowledge implementation course](../../developer/knowledge-extensions.md),
[evaluation course](../../developer/knowledge-evaluation.md) and
[question recovery course](../../developer/operator-questions.md) for current behavior.

## Findings and decisions

The separately requested [Daybreak review](daybreak-review.md) found three
readiness defects. Whole-P27 internal review and final boundary/toolchain checks
found three more.
The repair changes existing owners; it adds no runtime modules or dependencies.

| Finding | Repair and meaningful control |
| --- | --- |
| Future source generations erased earlier as-of evidence | Dataset resolves observation eligibility once. Runner ingests only known history, then uses the same eligible view for projections, Research gateway and rerank admission. Public Session fixtures cover all seven strategies with a future replacement and with a future tombstone. |
| Unsafe integers crossed portable knowledge identities | Evidence owns safe unsigned/positive integers. Source/citation/fact/time validation, callbacks, remote fetch and published schemas share that contract. Safe-maximum controls accompany maximum-plus-one refusals, including refusal before source put/open reads and configured inference. Narrower command limits remain intact. |
| Saved questions replayed historical prefixes repeatedly | One chronological projector keeps raw context and question state. Checkpoint normalization is temporary; native errors remain deferred behind context and Research validation. Pending, answered, mixed-result and error-order controls preserve compatibility. A bounded-active-context scaling fixture detects history replay. |
| A ninth retained projection head proposed inference before refusing publication | Store shares kind/profile identity and slot admission between opening and publication. State and MCP public Corpus/Graph callbacks refuse a new identity before inference/draft writes; existing identities still reach the intended inference proposal. |
| An imported maximum-generation source could not be forgotten | Suppression saturates source generation at the portable ceiling while CAS revision still advances. Public schema-valid import/forget controls cover State and MCP at maximum-minus-one and maximum, with stale-revision and resurrection refusals. |
| The earlier compiler-floor repair emitted warnings under Elixir 1.20 | Environment compiles either bound operations with their captured policy or explicit unbound refusal functions. Its verified precompiled launch dispatch remains dynamic, so bootstrap refusal types do not describe the separately compiled bound implementation. Strict compiler/CLI checks cover both modes without warning suppression or runtime policy fallback. |

The historical selection must preserve permanent suppression. An initial
selected-version-only ingestion draft failed the existing known-forget/later-live
CLI control. The final design ingests all versions observed by the cutoff in
generation order and excludes any known-suppressed source from retrieval. Future
history never enters that ingestion. Captured generations remain available for
exact citation mapping. This control prevents a historical-population fix from
silently becoming a resurrection policy change.

The review also questioned Runner's size. The demonstrated coupling was repeated
lifecycle selection across preparation, gateway and approval. Moving that pure
policy to the existing Dataset owner and passing its resolved population removes
that coupling. A mechanical split into additional phase modules would retain the
same authority problem while adding files; it was not adopted. Existing Runner
custody, serial execution and cleanup ownership remain together.

Saved reconstruction now costs one event traversal plus the active-context work
required by checkpoints and projection boundaries. Canonical digest compatibility
still requires hashing each active context. This does not claim constant-time
hashing or linear total work for an uncompacted, ever-growing conversation.

## Review provenance

- Original Daybreak report: `/tmp/ipse-p27-daybreak-review-166914a.md`, SHA-256
  `9c23dda4c7c458ddc1bd6044c397dd385cdda4d82b347c1f8111e9fe5620d223`. The archived copy adds only the historical notice above its original body.
- Internal repair reviews: `/tmp/ipse-p27-readiness-repair-review-a.md` and
  `/tmp/ipse-p27-readiness-repair-review-b.md`, retained with hashes in the local
  continuation. Review A covers lifecycle selection and Saved; its amendment
  explicitly supersedes the missed selected-only ingestion issue. Review B covers
  numeric boundaries and projection capacity; its citation-test gap was repaired
  with standalone fact constructors and safe-maximum source/citation controls.
  Neither repair reviewer claimed execution or milestone acceptance.
- Whole-document editorial checks read the question and persistence courses,
  Corpus and Graph manuals, and knowledge implementation course. Changed
  evaluation steps teach the explicit observed-history flow. No new manual
  chapter was added.

## Verification

The six-repair snapshot passes the completed platform, toolchain and package
checks below. Native measured-evaluator controls and the final hosted candidate
remain separate from those checks.

The first four-repair snapshot has 439 files with source-inventory SHA-256
`93cae4a0a46536b4ee0fbeee4100e7af6d0be69cf334d1f80310dd65ccb93e15`.
Its full suites failed the same three compiler/CLI checks on both platforms:
macOS passed 1437 of 1440 tests, with one skip and 36 exclusions; Linux passed
1479 of 1482 with 19 exclusions and native sandbox tests enabled. These are
failed gates. Both fresh package matrices passed 17 source/installed commands
with five freshly built knowledge artifacts and unchanged source inventories.
Those receipts remain limited to that earlier snapshot.

The final 439-file source inventory is
`ed469dd74097f87cfbb1afda6de28e6195f2dd4d86a3b1b2af4293d471f23626`.
After the two final corrections, all 40 compiler/CLI/frozen-runtime tests pass
on Elixir 1.20, and all 39 Store tests pass. The supported Elixir 1.18.5/OTP 27
strict build, 40 compiler/CLI tests and generation-ceiling import test also pass.
Fresh package matrices pass all 17 source/installed commands on both platforms,
with unchanged inventories. The full macOS suite passes 1441 tests, with one skip
and 36 exclusions; its dedicated native suite passes 30 with six exclusions.
Linux passes 1483 tests with 19 exclusions and native sandbox tests enabled.
Both builds, formatting, strict compilation, CI-policy checks, documentation
checks and demos pass. Each source inventory is unchanged after the checks and
matches the final inventory above.

The temporary platform controller initially rejected the successful summaries
because its pattern recognized only the failure-form `passed/total` summary.
Both suites had exited zero. Completion verified the original log hashes and
exact all-passing summaries, then ran the remaining native/demo/inventory steps.
The green full suites were not rerun. The source and installed native measured
evaluator proofs also pass in separate fresh Linux scopes. Each completes all
350 scripted outcomes and five authority controls, with confirmed cleanup and
unchanged source inventories matching the final inventory above.

| Native evaluator mode | Knowledge proof | Authority controls |
| --- | --- | --- |
| Source | Exit zero, 350 outcomes, 700990 ms | Exit zero, five controls, 146067 ms |
| Installed package | Exit zero, 350 outcomes, 599715 ms | Exit zero, five controls, 96510 ms |

The retained root is
`serenity:/var/tmp/ipse-p27-readiness-native-linux-20261021-c3`, with separate
`source/summary.json` and `installed/summary.json` receipts. These modes ran
concurrently with scripted models. They establish execution, resource-audit and
authority behavior, not actual-model quality or a matched resource comparison.

Hosted run [39610639358](https://github.com/lexlapax/ipse/actions/runs/39610639358)
tests exact commit `18af42eac9ffb0612848325ab4cbb30831f39704` on Elixir 1.18
and OTP 27. Both jobs completed successfully. Every applicable build, format,
strict compile, policy, documentation, full-suite, demo, package and independent
source/installed proof step passed. The macOS native and experimental App Sandbox
checks also passed; Linux-only optional protocol controls passed on Ubuntu.
Ubuntu completed at `2026-10-21T14:14:28Z` and macOS at
`2026-10-21T14:22:35Z`. The later documentation-only receipt does not change the
439-file runtime/test/tooling inventory certified by this run.

The ninth-head regression first reproduced an unintended `embedding.create`
proposal, then passed State/MCP negative and existing-head positive controls.
The saved-question regression failed against the original implementation:
quadrupling bounded-context history increased measured process reductions from
8293661 to 110774672 (13.36 times). The repaired test requires less than eightfold
work, separating repeated-history replay from necessary context hashing.

Earlier iteration logs are not final acceptance: initial test fixtures needed
correction, and the 79-case integration run exposed the selected-only resurrection
change. A later public maximum-import control reproduced `root_bounds` on forget,
then passed after generation saturation. Its standalone Store fixture now omits
an explicitly forwarded current-directory code path, preventing the checkout's
name from shadowing the SDK. A first compile-time Environment branch still
exposed the unbound bootstrap's inferred refusal type to the precompiled call site;
the targeted strict-runtime test caught it before another broad run. The dynamic
verified dispatch passes that control and the complete 40-case group.
The original compatibility commit's hosted run `39594534394`
is green; it does not certify these new repairs.

This closes structural and implementation readiness for the final configuration
decision and fresh evaluation freeze. P27 remains open. This repair does not
expose the sealed private workload, run
actual-model inference, establish held-out quality or exact matched resources,
provide independent semantic judgments, or select an engine.
