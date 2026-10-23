# Final P27 review and follow-up, 2026-10-23

Historical review and repair record. The [preserved independent report](review.md)
reviews `ca5838be881049cb0f11eded8f6ab3c9fc2843a3` on Serenity. Its original bytes
are retained. It confirms optional-package acceptance with no P1 or P2, a passing
1532-test native-inclusive Linux suite, an exact package/installed proof and green
[hosted run 40014715937](https://github.com/lexlapax/ipse/actions/runs/40014715937).
Those are the external reviewer's checks of that subject, not fresh checks of the
follow-up. The initial repairs below are implemented in
`89151b6e049e1f7c8b2d396ea42f7c788e155955`; their receipt remains unchanged.
The later [internal whole-P27 audit](internal-audit.md) records three reviewers,
additional causal findings, their integrated repairs and separate final checks.

Current procedures belong to the [MCP manual](../../operator/mcp.md),
[Corpus manual](../../operator/corpus.md), [MCP training](../../developer/mcp.md)
and [verification training](../../developer/testing.md). The [plan](../../plan.md)
owns acceptance status; the [held-out comparison](../2026-10-23-p27-heldout-comparison/index.md)
retains its measured version, frozen data and published scores.

## Dispositions

| Finding | Repair and causal control |
| --- | --- |
| C1, legacy redaction/hash compatibility | Version-one hashing uses only the server's own secrets, exactly as its writer did. Cross-server output redaction remains enabled. Version-two loading and recomputation use the same redaction set. An overlapping-secret unit control and real inert legacy Session resume pin the distinction. |
| C2, explicit version one | A shared journal-version parser admits an absent legacy field or explicit integer two. Explicit one refuses at Session and saved-binding boundaries, before tail repair or dispatch. |
| C3, diagnostic private-value recheck | Extension MCP errors receive the same private-value recheck as successful text. A redaction collision returns unknown without diagnostic text. The fixture performs a real partial effect; its result, journal and idle resume verify no disclosure or replay. |
| D1, measured reference authority | Both manuals name `state-dense`, empty rerank registry and `top_k: 10`. The runnable dense example grants no model authority; a separately built `state-semantic` rerank alternative explicitly adds it. |
| D2, owner-resolution precision | Headline and audit row name the frozen owner's `independent: true` field, the scorer's requirement for it, and the resulting completeness/global-gate dependence. Final independent resolution covers 349 outcomes and 634 pairs. The extra owner resolution affects one rerank case, without changing hybrid or any qualification. No raw record or score was rewritten. |
| D3, provenance and limits | Dated in-place notes identify the earlier 4171fb4 narrative corrections to a7f4982. The original editorial verdict is labelled historical. The toolchain-floor runtime disclaimer is restored; the plan distinguishes each verification version. The comparison names `nvidia_visible_mixed_v1` and partial residency on an 8 GiB GPU. |
| D4, manuals and error clarity | Operator skill guidance states the concurrent-replacement limit; Graph explains retained-generation as-of behavior; dependency purpose and storage typo are corrected. Internal skill-preflight failure has a distinct error from catalog changes. `ipse config --mcp-config` validates the selected file without discovery. Resume guidance names MCP and legacy OTP compatibility. |
| T1, missing controls | Ordinary HTTP tools now exercise server-declared errors, redacted diagnostics, possible effects and inert resume. Twelve additional preset controls complement the original three presets and nine memory/package cases. All fifteen presets verify disabled/idle/resumed capability grants without worker, State, MCP, embedding or model dispatch. The extra preset controls do not invoke domain operations or claim live-service verification. |

## Verification and preserved failures

The [verification receipt](verification.json) binds source files, actual commands,
logs, toolchains and package identities. The initial new MCP cohort reproduced
C1/C2; its diagnostic control first had an absent-environment fixture mistake.
The corrected diagnostic probe reproduced C3. After the repairs, a new resume
control exposed its own missing initial workspace snapshot; copying the real
snapshot makes the inert-resume assertion valid. New preset controls initially
omitted the required Session subscriber and were corrected. These failed trials
remain separate from passing final checks.

The focused host cohort passes 115 tests; the full preset independence file
passes 21 tests. Both documented dense and optional rerank setup examples are
executed through real builders, configuration admission and import in temporary
homes, without starting chat or model calls. Local Elixir 1.18.5 and 1.20.3
formatters pass on OTP 29. This is not a local OTP 27 runtime claim.

Full-platform follow-up results are recorded separately in the receipt. No fresh
real-model answer evaluation, semantic rejudging, charged-memory comparison or
consumed-seal replay is performed. The evidence archive and all initial receipts
remain unchanged; later runtime checks do not change their subjects.

| Final check | Result |
| --- | --- |
| Build, platform formatter and strict compile | Passed on macOS and Linux |
| Complete macOS default suite | 1497 passed, one skipped, 36 excluded; zero failures, 1172.6 seconds |
| Complete Linux native-inclusive suite | 1550 passed, 19 excluded; zero failures, 1032.0 seconds |
| Credential-free demo | Passed on both platforms |
| Fresh package and exact installed-package proof | Passed on both platforms; each proof uses its identified newly built archive |
| Source and exact installed MCP proof | All twelve checks passed in each mode on both platforms, with unchanged inventories and zero live-model calls |
| Whole-document review and docs checker | 396 Markdown files, 3630 local links, zero errors; revised setup examples executed without inference |

The Linux run uses a fresh detached clone of ca5838b plus the exact repair patch.
All fourteen changed runtime/test files match the macOS checkout byte-for-byte.
The primary Serenity checkout, its untracked settings and existing services are
left untouched. The earlier macOS package was copied and hash-verified before
the new build replaced its generated path; the receipt retains that copy's identity.
No fresh macOS sandbox-specific run or local OTP 27 runtime check is claimed.

## Internal adversarial follow-up

The [internal audit](internal-audit.md) preserves its common brief and individual
reports, including original findings and post-fix assessments. It closes the
ordinary/catalog post-redaction privacy gap and legacy public-argument/hash
disagreement without changing frozen evaluation evidence. The owner selected
unknown-and-stop when a server-error diagnostic remains private after redaction.
The [internal receipt](internal-verification.json) binds that follow-up's exact
source and checks; the table above continues to describe 89151b6 only.
