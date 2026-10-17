# Independent extension-package proof

The extension lab exercises domain behavior against candidate core
[`3b0ef78`](../../examples/extension-lab/FROZEN_CORE). Its implementation lives
entirely under [examples/extension-lab](../../examples/extension-lab/README.md),
with an integration test and package-verification workflow. No domain feature
branch, runtime module, native helper change or project dependency is required.
This is concrete SDK coverage, not completion of P22 or selection of P25 engines.

## Build and execution boundary

`build.exs` runs in a separate compiler VM against the already-built
`Ipse.Extension` behavior. It emits immutable worker artifacts, copying the
repository license and pinning every file's length/hash. Versions 0.1.0 and 0.2.0
of the memory worker compile independently. The builder uses Elixir/OTP compiler,
crypto and OTP 27+ JSON encoding; it never runs during import or activation.

The artifacts communicate only through documented `describe`, `init` and `handle`
JSON contracts. They use no private Ipse state API, host PID, filesystem access,
network request or provider call. The text observer also uses the public, pure
ephemeral-frame validation/projection helpers. The operator verifier uses
Session/configuration, journal inspection and normal installation APIs to drive
the trial. For the ephemeral text case only, it inspects synthetic Session and
consumer state with `:sys.get_state/1` to confirm acknowledgment counters. That
privileged fixture instrumentation is not an extension API or a granted host PID.

| Artifact | Domain behavior | Host contracts exercised |
| --- | --- | --- |
| Memory, two versions | Deterministic `entity: Name` / `link: From -> To` extraction, scoped records, deduplication, recall/forget/export, read-only stats and a file workflow | Prompt jobs, typed tools/commands, CAS state, context receipts, questions, file actions and bounded history |
| Lookup | Configurable literal synthetic corpus with a deliberate crash option | Typed value service, explicit operator route and required-recall failure |
| Metadata | Prompt byte-count acknowledgment with no private view grant | Inert notify declaration, exact acknowledgment and private/hash exclusion |
| Observer | Read-only usage consumer with a deliberate hang option | Independent feed queue, pressure closure/gap and no idle reenrollment |
| Tool observer | Checks selected input/result and metadata views | Independent private tool-feed grants and four exact acknowledgments |
| Text observer | Checks visible answer delivery and metadata projection | Negotiated v2 sources, public pure SDK helpers and exact frame acknowledgment |

Domain dispatch remains inside these artifacts. Their trusted executable code
still has ordinary OS permissions; inspection of these examples is not a sandbox
or proof about arbitrary third-party code.

## Capture, recall and deletion

Before-request recall reads scoped memory, calls the explicitly bound lookup
service and publishes literal receipt-backed context. Model admission freezes
that snapshot. After-turn capture reads the original prompt, extracts bounded
labels/relations and proposes a separate approved CAS write. It cannot change
the already admitted answer. This maintenance uses the existing serial effectful
lane; it is not fully concurrent background execution.

Facts retain event/view/source identity, extractor and package versions. Identical
new prompts have different source IDs; explicit historical catch-up deduplicates
the same recorded occurrence without rewriting state. Catch-up uses fixed-range
`prompt.original` pages, exposes gaps/continuation and never chases its own receipts.
It scans at most eight pages per invocation; each page scans at most eight records.

The demonstration store permits eight sources, sixteen entities and a 7,000-byte
domain value, below host bounds. Capacity refuses visibly. It stores extracted
labels/relations and source bindings, not a copy of the whole prompt. Forgetting
an entity removes its containing source facts and retains blocking identities;
this intentionally conservative policy may remove other facts from those sources.
Forget-all uses the host tombstone and blocks recreation in that namespace.
Forget also clears this instance's future context contributions. CAS rejects a
delayed write captured before forget. Journals, old request snapshots and earlier
provider transfers are not erased. These limited policies do not replace P25's
retention, migration, quality or comprehensive deletion design.

## Verification and evidence

The source integration runs compilation and the host verifier in separate VMs.
The operator package verifier imports into an isolated application home, exercises
actual temporary CLI flags with caller and target selected, then runs the same
proof in the already-built release. Its parent PATH contains declared utilities;
the release's own Erlang runtime is allowed, while system Elixir/Erlang/Mix/Rust
executables are rejected. Archive SHA-256 must remain unchanged. Both runs compare
the host's application BEAM bytes before/after the trial and confirm that the
domain modules were never loaded into the host.

The 41 assertions cover real graph/provenance, original/effective input distinction,
awaited recall, frozen request context, explicit tools/commands, approved writes,
questions without write permission, inert question/capture resume, repeated-prompt
identity, deduplication, scoped persistence/isolation, concurrent versions, deletion
and delayed-write conflict, required recall refusal, queue saturation, installed
private-tool/text delivery, saved receipt validation and read-only stats for
missing/populated/deleted records. Stats is operator-only; the proof checks exact
counts/metadata, one state read, no inference and an unchanged tombstone. These
are synthetic fixtures, not live model or retrieval quality measurements.

The final case deliberately crashes a required service. It proves that inference
does not start and cleanup is not promoted to confirmed. The successful test
report therefore ends with `safe_to_continue: false` and
`expected_terminal_cleanup: "unconfirmed"`. No later domain scenario runs; its
isolated verifier VM exits. A matched negative case does not certify descendant
containment or an arbitrary service's effects.

Linux source and installed-release checks have run, including a symlinked temporary
root. The verifier resolves the actual bundled Erlang executable before comparison;
macOS's `/var` and `/private/var` aliases must not be mistaken for a system toolchain.
Hosted proof runs on both workflow jobs. See
[current evidence](testing.md#current-evidence-and-next-checks) for actual results.
The candidate source freeze is independently reviewable with
`git diff 3b0ef78 -- lib native`; future core-feature changes need their own
compatibility checks rather than pretending this historical reference is current.

## Supervised trial and remaining P22 gates

The frozen release authored the read-only stats command in a separate candidate
worktree using explicit ChatGPT subscription `gpt-6.1-sol`/high. Three exact edits
were separately approved; a fresh read-only review session found no actionable
issue within its two-file scope. The supervisor inspected the changes and added
the independent runtime assertions above. Both shipped prompt/presentation hooks
ran in both live sessions, with original/native text preserved and byte-identical
idle resume. No core edit or release rebuild occurred. The
[trial record](testing.md#supervised-extension-only-trial-2026-10-17) separates
live authoring/review from synthetic runtime verification.

The [lifecycle coverage audit](lifecycle-events.md#supported-lifecycle-coverage)
identifies stable and unsupported seams. Hosted verification of the current lab
and bundle-path correction remains the P22 completion gate. Unsupported stages, custom
event publication, concurrent effectful jobs, remote installation and media stay
explicit negotiated enhancements, not silently available callbacks. The
[plan](../plan.md#p22-extension-scaffold-and-lifecycle-hooks) retains those gates.
P23 supplies accounted model work/budgets; P24 supplies media; P25 supplies
researched memory/research/graph/RAG algorithms and adapters.
