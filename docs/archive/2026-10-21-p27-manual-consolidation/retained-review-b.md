# Retained manuals review B

## Scope and result

Reviewed the retained draft at `/tmp/ipse-p27-manuals-20261021-c1` as whole documents, using `/tmp/ipse-p27-manual-targets.json` and `/tmp/ipse-p27-whole-manual-review.tsv` to select coverage. Compared suspected errors with current implementation in `/Users/spuri/projects/lexlapax/ipse`. This is a source-only editorial assessment for S14, not a new implementation or security certification.

Three concrete corrections follow. Otherwise the covered chapters can retain their existing prose. Their worked examples generally distinguish scripted exercises from real inference, configuration from approval, saved receipts from current evidence, and process exit from confirmed cleanup. No additional material training-example gap or conflicting authoritative topic ownership was identified. Expected navigation renames are excluded from findings.

## Findings

### B1. Correct the implemented embedding boundary in the security policy

- Priority: P2.
- Draft location: `SECURITY.md:126-128`.
- Current text groups "Unsupported embeddings/audio" with future package distribution and production knowledge engines as unimplemented attack surfaces. This leaves the current embedding feature looking excluded from the threat model even though it accepts approved external inference and persists private vector results.
- Source evidence: `lib/ipse/extensions/host.ex:357-358` dispatches `embedding.create` to `EmbeddingCall.execute/2`; `lib/ipse/extensions/embedding_call.ex:9-20` admits the request; `lib/ipse/provider/embedding.ex:8-12,58-68` implements OpenAI/Ollama endpoints and bounded HTTP dispatch. The covered operator embedding procedure explicitly exercises this implemented path.
- Remediation: explicitly include the supported OpenAI/Ollama embedding path among current reviewable boundaries. Limit any deferred-feature exclusion to actually unsupported providers/modalities or future functionality. Keep the requirement for a concrete reachable path.

### B2. Remove the obsolete macOS environment-file failure description

- Priority: P3.
- Draft location: `docs/operator/mcp.md:158-159`.
- The chapter says abrupt supervisor failure can leave owner-only temporary environment data on macOS. That describes the former file transport and conflicts with the current native protocol chapter. It sends an operator investigating credential retention toward a file that current launches do not create.
- Source evidence: `native/ipse-macos-sandbox.rs:230-240` constructs an in-memory `input_prefix`; lines 243-265 encode/decode its bounded frame. Lines 278-284 read that frame from descriptor zero and exec the selected server. `native/ipse-stdio.rs:246-248,320-334` forwards the prefix over the worker's stdin. The retained `native/README.md` explicitly explains that no environment file is staged.
- Remediation: describe the selected environment's private pipe transfer, or simply remove the obsolete current-launch warning. If old-generation files matter to recovery, identify them explicitly as historical artifacts and retain the warning that current transport does not erase them.

### B3. Remove stale milestone direction from the agent entrypoint

- Priority: P2.
- Draft location: `AGENTS.md:44-52`.
- This entrypoint still says P24 "now owns" architecture/security work, P25 owns the comparative trial, and knowledge capabilities "defer to P26/P27". An agent choosing its next task receives outdated direction even though the same file tells it to use the active milestone. This is substantive scope guidance, not merely a dated wording preference.
- Source evidence: current `docs/plan.md:27,46,67-89` records P24/P25/P26 as completed within their scopes and P27 as active. Current `lib/ipse/builtins/memory.ex` and `extensions/knowledge/src/{corpus,graph,research}.ex` implement the capabilities described in the retained manuals. The draft's own updated code map already lists those owners.
- Remediation: retain the extension-first design instruction, remove the obsolete present-tense milestone summary, and direct agents to `docs/plan.md` for current scope/status. Do not turn AGENTS into another milestone ledger.

## Whole-document coverage

Developer chapters, all read in full:

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

Operator chapters, all read in full:

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

Root/example/native/bundled-skill entrypoints, all read in full:

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

## Exclusions and evidence limits

The consolidation targets and root-owned indexes/testing/feeds/lifecycle/text-streams were excluded as requested. `docs/index.md` is the eighteenth entrypoint in the inventory and remains root-owned, so this report does not claim its review. Coverage is 19 retained developer chapters, 20 retained operator chapters and 17 other entrypoints, 56 whole documents.

Source tracing focused on concrete suspected discrepancies and the S06-S13 ownership changes. Reading every chapter does not establish independent execution of every command or boundary value. No applications, tests, compilers, probes, services, network calls, model requests or private workloads were accessed. No repository or draft file was changed. Parent-reported verification remains parent evidence. Only this report was written.
