## Findings

No remaining findings.

### Resolved during review: [warning] Feed metadata prerequisites omit the required runtime-recording grant

**Location**: `/tmp/ipse-p27-manuals-20261021-c1/docs/developer/extension-feeds.md:23`, metadata prerequisite row.

**Finding**: The initial draft row said a declared supported metadata feed sufficed, with an additional recording exception only for tool facts. Wait and recording-stopped feeds also require `lifecycle.record`. Without the adjacent correction, an author following the table could produce a declaration that activation rejects.

**Evidence**: Actual `lib/ipse/extensions/subscriptions.ex:47`–52 requires `lifecycle.record` for feed declarations selecting `wait.started`, `wait.finished` or `session.recording_stopped`. The archived original `extension-feeds.md` states this prerequisite explicitly in its selected-event table. The initial merged chapter listed waits as supported while omitting that specific prerequisite.

**Resolution**: The parent added an explicit adjacent sentence requiring `lifecycle.record` for all three event types. Read back the correction after writing the initial report; it matches Subscriptions.validate/2. The tool prerequisite remains intact.

## Corrections verified during review

Two concrete wording issues were reported to the parent and corrected in the draft while this review was active. Read back both repairs:

- `extension-effects.md` now says `host.results` extends only same-invocation `effect.result.read` through step 512. It explicitly does not extend other read families or permit a later effect. This matches `Actions.limit/2`; the mixed read/other allowance remains separate.
- `extension-feeds.md` now states that additional input in the same Session process cannot restart a stopped enrollment. A new process, including compatible resume followed by explicit input, can enroll. This matches `Feeds.close/3`, which retains `enrolled:true`, and the early-return clause in `Feeds.enroll/4`.

These are resolved observations, not remaining implementation findings.

## Coverage and assessment

Read all 13 merged target chapters as whole documents:

1. `docs/operator/configuration.md`
2. `docs/developer/configuration.md`
3. `docs/developer/workspace-context.md`
4. `docs/developer/usage-accounting.md`
5. `docs/developer/extensions.md`
6. `docs/developer/testing.md`
7. `docs/developer/extension-state.md`
8. `docs/developer/extension-effects.md`
9. `docs/developer/extension-composition.md`
10. `docs/developer/extension-events.md`
11. `docs/developer/extension-feeds.md`
12. `docs/developer/lifecycle-events.md`
13. `docs/developer/text-streams.md`

Read the complete shared, operator and developer indexes. Reviewed all four retained corrections in SECURITY, naming, operator MCP and AGENTS against their previous wording and current implementation. Reviewed the archive-check extension in `scripts/check-docs.exs`, including legacy repository-relative snapshots and new manifest-relative snapshots. Prior retained-manual coverage remains applicable; it was not repeated here.

Compared the new teaching structure with the grouped original contracts and the preserved before snapshots, with particular source checks for per-operation action allowances, feed capability prerequisites and enrollment lifetime, runtime/profile/credential assembly, durable versus ephemeral identity, artifact/public SDK ownership and archive snapshot path resolution. The earlier source reviews in this panel also cover Config, Saved and CurrentInvocation extraction. No additional material source-clarity, ownership, example or limit correction was established.

The merged chapters teach concrete journeys rather than concatenating the removed pages. State/questions, effect families, value services/context, boundary notifications/jobs and live-feed/history responsibilities remain distinguishable. The three indexes assign those topics coherently. Public SDK, generic host, Builtins and independent package ownership remain distinct. Numeric input limits, encoded enclosing bounds, finite action budgets, separate cleanup facts, source-bound recovery and no-replay rules remain visible in the relevant training paths. The four retained corrections resolve the previously inconsistent product/security scope and obsolete macOS environment-file claim.

The archive checker continues checking the older manifest and additionally discovers `manual-provenance.json` recursively. New relative snapshot paths resolve against their own manifest; historical `docs/archive/...` paths retain repository-relative interpretation. A missing or changed snapshot still contributes an archive error. I found no source-level weakening of that check.

## Limits and verdict

Source-only review. No application, compiler, tests, probes, services, network requests or model calls ran. No private workload inputs, outputs or credentials were accessed. Link-check, negative snapshot, operation-validator, configuration/conformance, platform, installed-runtime and synthetic evaluation results supplied by the parent are parent evidence, not independently reproduced checks. No actual-model, held-out semantic quality, live account or new OS qualification claim follows from this review.

All three concrete wording findings were corrected and read back. This pass has no remaining material blocker for the scoped S14 manual consolidation. Final completion and execution evidence remain the parent's responsibility.
