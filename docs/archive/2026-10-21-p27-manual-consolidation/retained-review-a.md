## Findings

### 1. [warning] Security scope excludes a currently implemented embedding surface

**Location**: `SECURITY.md:126` in `/tmp/ipse-p27-manuals-20261021-c1`.

**Finding**: The attack-surface paragraph groups "Unsupported embeddings/audio" among capabilities that are not implemented. Embeddings are implemented and operator-selectable, so this can lead a reviewer to omit a live input, egress, decoding and accounting boundary.

**Evidence**: Main `lib/ipse/provider/embedding.ex:8` and `:11` select OpenAI `/embeddings` and Ollama `/api/embed`; `embed/3` at line 56 dispatches bounded HTTP and parses the result. `lib/ipse/extensions/embedding_call.ex` and `lib/ipse/embedding_profiles.ex` expose the granted, selected-profile extension path. The retained operator embeddings chapter correctly teaches this current route, and the security document's preceding accounting invariant already includes accounted helper work.

**Remediation**: Remove embeddings from the unimplemented-capability grouping. Identify the existing selected-profile embedding path as current scope while retaining audio and genuinely future capabilities as exclusions. No new security architecture is needed.

### 2. [warning] Naming entrypoint prescribes the superseded coding-only product description

**Location**: `docs/naming.md:63` in the draft.

**Finding**: The chapter explicitly prescribes "an Elixir-native coding agent with local skills and resumable conversations" as the public description. This contradicts the settled general-purpose harness scope and can cause downstream documentation or agents to restore the old framing.

**Evidence**: The draft README opens with "general-purpose local AI harness". AGENTS.md:9 uses the same scope and explicitly distinguishes coding-oriented prototype tools from target-project language choices and general task coverage. The naming chapter's historical/philosophical discussion is sound; its final normative product description is the inconsistent part.

**Remediation**: Align that final description with README/AGENTS, retaining Elixir/OTP as the implementation and coding-oriented tools as current prototype context. No broader rewrite of the naming explanation is necessary.

## Whole-document coverage

Read the target map and review ledger. Reviewed the following retained developer chapters as whole documents:

- `docs/developer/architecture.md`
- `docs/developer/budgets.md`
- `docs/developer/delegation.md`
- `docs/developer/dependencies.md`
- `docs/developer/extension-artifacts.md`
- `docs/developer/extension-invocations.md`
- `docs/developer/knowledge-evaluation.md`
- `docs/developer/knowledge-extensions.md`
- `docs/developer/mcp.md`
- `docs/developer/memory.md`
- `docs/developer/observability.md`
- `docs/developer/operator-questions.md`
- `docs/developer/persistence.md`
- `docs/developer/provider-limits.md`
- `docs/developer/research.md`
- `docs/developer/reviewing-changes.md`
- `docs/developer/runtime-capabilities.md`
- `docs/developer/sandbox.md`
- `docs/developer/self-hosting-evaluation.md`

Reviewed these retained operator chapters as whole documents:

- `docs/operator/arch-linux.md`
- `docs/operator/architecture-review.md`
- `docs/operator/budgets.md`
- `docs/operator/corpus.md`
- `docs/operator/embeddings.md`
- `docs/operator/extension-lab.md`
- `docs/operator/extensions.md`
- `docs/operator/feature-requests.md`
- `docs/operator/graph.md`
- `docs/operator/mcp.md`
- `docs/operator/memory.md`
- `docs/operator/observability.md`
- `docs/operator/recovery.md`
- `docs/operator/research-extensions.md`
- `docs/operator/research.md`
- `docs/operator/self-development.md`
- `docs/operator/subagents.md`
- `docs/operator/troubleshooting.md`
- `docs/operator/usage-accounting.md`
- `docs/operator/usage.md`

Reviewed these root, example, native and bundled-skill entrypoints as whole documents:

- `README.md`
- `CONTRIBUTING.md`
- `SECURITY.md`
- `AGENTS.md`
- `THIRD_PARTY_NOTICES.md`
- `docs/naming.md`
- `native/README.md`
- `examples/embedding-actions/README.md`
- `examples/extension-lab/README.md`
- `examples/mcp-actions/README.md`
- `examples/memory/README.md`
- `examples/model-calls/README.md`
- `examples/saved-results/README.md`
- `priv/skills/project-orientation/SKILL.md`
- `priv/skills/research/SKILL.md`
- `priv/skills/review/SKILL.md`
- `priv/skills/self-development/SKILL.md`

This covers 56 retained documents. Persistence and invocation chapters were also read in full during the immediately preceding S12/S13 reviews; their draft copies compare equal to the reviewed main copies. Large knowledge chapters and the native README were read in sequential complete sections, including the repeated historical-version and component-proof procedures.

## Assessment and limits

Beyond the two semantic inconsistencies above, no concrete correction was established in the retained scope. The chapters maintain useful distinctions between public SDK, generic host, bundled implementations and independent packages. The revised development owners and compiled launch boundaries integrate with their surrounding task examples. Operator examples state prerequisites, distinguish inert construction/inspection from execution, and retain approval, unknown-outcome and recovery procedures. Repeated bounds generally serve different operator, training or protocol tasks rather than competing definitions of authority.

This was source-only review of the isolated draft against actual main implementation after S06–S13. Source spot-checks included the embedding transport/profile/action path, application supervision, invocation/recovery ownership, registry artifact construction and finite example proof assertions. A moved-owner/path search supplemented whole-document reading; it did not replace it. No tests, compiler, application/probes, services, network requests or model calls ran. No private workloads, raw experiment inputs/outputs or credentials were accessed. Commands and numerical limits were assessed against source and existing fixture definitions, not executed or independently qualified on an OS/provider account.

Excluded the already-written consolidation targets and the indexes/testing/feeds/lifecycle/text-streams topics being rewritten by the parent. `docs/index.md` is therefore the one parent-owned item among the 18 entrypoints, not an omitted retained review. Expected pending link/anchor renames were not reported as defects. This report does not certify the parent's final navigation rewrite, merged-topic completeness, actual command execution, live inference, installed-runtime behavior or S14 completion.
