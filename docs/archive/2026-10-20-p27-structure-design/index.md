# P27 whole-codebase consolidation design

Proposal and design-review record, 2026-10-20. No structural implementation is
established by this document. The design follows a whole-repository survey and
two independent proposals, with a separate design reviewer. The review observed
`3ceeb6d` and six pending answer-contract files. Those changes belong to a separate
verification increment. Current behavior remains in the
[architecture training](../../developer/architecture.md),
[user manual](../../operator/index.md) and
[contributor manual](../../developer/index.md). Status belongs to the
[plan](../../plan.md#p27-optional-research-graph-and-rag).

## Consolidate ownership across the repository

Keep one Mix application and one native executable. Preserve Session ownership,
journal intent before effects, approval, task fencing, independent extension VMs,
explicit provider selection and unknown-outcome recovery. Preserve the public
SDK callback, publication and result interfaces and current persisted formats.
The proposed structure changes repeated coordination and misplaced knowledge;
it does not require moving every sound module.

| Area | Selected change |
| --- | --- |
| Session | Keep one GenServer and its writer, locks, approvals, timers, source IO and dispatch authority. Extract saved-record reconstruction and current invocation state into separate, precisely defined owners. |
| JSON and hashes | Move bounded JSON decoding and raw hashing out of Manifest, and canonical list hashing out of Compaction, into existing `Ipse.JSON`. Migrate callers and delete redundant implementations while preserving exact bytes and errors. |
| Configuration and CLI | Let Config assemble resolved runtime policy. Remove duplicate provider/default tables and validations from CLI. Preserve early credential preflight and fresh credential lookup at dispatch. |
| Usage and costs | Move pure rate-card estimates and request aggregation to `Ipse.Usage.Costs` and `CostSummary`. Budget remains the admission authority. |
| Bundled extensions | Group bundled memory, reporting, hooks and local trace under `lib/ipse/builtins/`, using `Ipse.Builtins` names and updated exact Registry closures. Preserve builtin IDs, options, capabilities and behavior. |
| Public SDK and host | Retain `Ipse.Extension` and its publication interface separately from generic `Ipse.Extensions` host contracts. Audit documented imports before removing internal helpers. |
| Independent extensions | Keep `extensions/knowledge/` independently built, outside host Mix compilation. Keep its State and MCP store adapters separate. |
| Development tooling | Move substantial evaluation, verification and shared fixture implementations from examples and test support into `dev/`. Consolidate repeated build and installed-runtime setup. |
| Examples and tests | Keep small runnable examples and behavior tests. Shared fixtures used by runnable tools belong in `dev/fixtures/`; ExUnit-only fixtures remain in test support. |
| Providers, auth, MCP, native execution | Retain their real protocol, credential, transport and completion owners. Update callers and documentation where shared data or configuration ownership changes. |
| Events and delivery | Preserve different contracts for durable events, required text, finite acknowledged feeds and optional sampled diagnostics. Do not merge them into a generic delivery framework. |
| Packaging and CI | Migrate source paths, generated launches, formatter rules, package contents and every named source, native and installed scenario together. |

The three extension locations represent different roles. `lib/ipse/extension*`
defines the public worker SDK. `lib/ipse/extensions/` implements host admission
and worker contracts. `extensions/knowledge/` contains independently distributed
artifacts. Bundled behavior currently mixed into the host directory moves into
`lib/ipse/builtins/`. The contributor source map must explain these roles directly.
Uniform directory spelling alone would not simplify their interfaces.

Retain earned existing owners such as Session.Lock, Journal.Writer,
TaskResources, FileEffect, HTTP and stdio transports, and the focused Rust
modules. Their lifetime and failure guarantees differ. Keep legal files,
dependency notices, packaged demonstrations and inert skill resources.

## Give development code one clear home

The proposed development tree has these owners:

```text
dev/
  verification/       named scenarios and shared installed-runtime isolation
  evaluation/         declarations, execution, audit, review and scoring
  fixtures/           fixtures shared by tools and tests
  experiments/        development measurements
  platform/           development OS probes
  diagnostics/        development diagnostic implementations
```

Use one `scripts/build-artifact.exs` for the five trusted example recipes and
one `scripts/verify.exs` with explicit source or installed mode and finite named
scenarios. Delete replaced per-example build and verification wrappers after
migrating all callers. Each scenario retains its own exact assertions and
supported/refused platform cases. Installed mode cannot fall back to source.

The common installed runner adopts the strongest existing saved-results checks:
private HOME and environment, trusted proof compilation before launch, absent
development toolchain, and exact archive, runtime, artifact, harness and utility
inventories. Native scenarios retain only their specifically required service-bus
and runtime-directory settings. They do not grant those settings to every proof.

Keep focused evaluation preparation, dataset authoring, evaluation, measurement,
diagnostic and demonstration commands. A universal development dispatcher would
move unrelated command contracts into another hierarchy. Move substantive code
without deleting dataset validation or MCP demo behavior as boilerplate.
Keep the standalone `verify-release.exs` copied into installed packages.

Extract a pure evaluation declaration contract so Plan does not load Runner,
model-service implementation or a test CAS server. Move shared fixtures out of
test-only ownership. Keep execution, model service, measured sequencing, review
and resource accounting distinct. Consolidate input projection and literal
integrity into one dataset owner. Keep Score and Metrics separate: their current
790 and 423 lines would become 1,213 lines without a simpler interface.

## Specify state before extracting it

`Session.Saved` must distinguish the existing narrow context reconstruction from
full pure resume facts. Event/subscription question recovery reads source pages;
it remains with the IO owners after allowed locked tail repair and reload.
A pure reconstruction result cannot claim to have resolved those sources.
Keep the useful message-list context interface instead of adding a one-field
wrapper structure.

`Session.Invocation` must model actual ready, pending-action, output-publication
and interrupted states. Pending approval and its caller remain owner-held facts.
Before extraction, map every field and transition for action begin, approval,
denial, question suspension, result commit, publication, cancellation and timeout.
Account for history/usage source publication and result reservations. The owner
commits intent before installing proposed state or dispatching an effect.
Reject a helper that receives the entire Session map or invents a universal
admission/grant protocol.

Config runtime assembly also needs a closed client-policy contract. Shared
provider facts must have named consumers and fields. Preserve explicitly supplied
fixture keys, endpoint and billing choices, approval behavior, minimal direct
Session fixtures and fresh rotating-token resolution.

## Rewrite both manuals around their readers

Every active chapter, root entrypoint, example README, native guide and bundled
skill receives whole-document review. Retaining a file does not exempt it from
removing repetition or repairing its examples. Consolidate these topics where
the reader benefits:

- Settings and model-profile explanations share one configuration owner in each
  audience. The operator embedding task remains a separate complete procedure.
- Workspace instructions and active-context compaction share developer context
  training, with retained history and source identity explained together.
- Recorded usage and configured costs share accounting guidance. Admission and
  unknown liability remain explicit when explaining budgets.
- Extension authoring, hooks and worked scenarios form a progressive course.
  Conformance exercises belong there; common installed setup belongs in testing.
- State continuations and extension questions share training. Typed file, MCP,
  text-model and embedding effects share a chapter with distinct contracts and
  runnable exercises. Services and context publication share composition training.
- Notifications and jobs share one training task. Finite feeds and historical
  catch-up form another, with their different coverage guarantees preserved.
- Related lifecycle/tool identity and text/event-frame material share their
  respective training topics.

Keep complete operator tasks for Corpus, Graph, Research and Memory. Keep
troubleshooting separate from saved-effect recovery. Keep architecture review,
self-development and feature requests separate: they solve different problems.
Keep legal reporting in SECURITY, contribution flow in CONTRIBUTING, agent rules
and the actual source map in AGENTS, and audience routing in the documentation
indexes. Milestone status stays in the plan; measurements and reviews stay in
the archive.

Preserve substantial superseded manual bodies in a dated archive with original
paths, revision, provenance and replacement links. Repair current links and
anchors directly instead of leaving a page of redirects. Historical source-link
repairs need recorded provenance; old evidence must never appear to verify the
new structure. File-count forecasts are not acceptance requirements.

## Implement in reviewable units

1. Capture supported SDK interfaces, compiled artifacts and imports, exact hash
   fixtures, scenario assertions, source paths, Registry closures and generated
   launch dependencies before changing them.
2. Consolidate artifact construction and verification setup, including stronger
   installed isolation. Migrate CI, packaging, examples and affected manuals;
   delete replaced wrappers and verify every original scenario separately.
3. Move evaluation and shared fixtures, remove eager declaration dependencies,
   and migrate generated launch and frozen-source paths. Verify the complete
   synthetic source and installed execution on supported Linux.
4. Move JSON, cost and builtin ownership with byte-for-byte digest/error checks,
   exact Registry inventories and previously compiled supported SDK artifacts.
5. Implement runtime configuration assembly, then saved reconstruction, then
   current invocation state as separate grounded changes. Exercise approval,
   cancellation, owner/writer death, unknown outcomes, accounting, questions,
   publication and distinct delivery failures.
6. Complete the entire manual and entrypoint review, real synthetic CLI examples,
   links, anchors and stale active-path checks. Run source, native, package and
   installed checks on the actual supported platforms, obtain independent review,
   and commit/push each completed unit.

Host and builtin BEAM identities will change. Preserve legitimate old-session
resume refusals. Teach original-build inspection/export, retained journals and
artifacts, fresh sessions and explicit handoff. Never weaken hash pinning or
replay an unknown effect to make a migration look seamless.

The final private evaluation follows feature repairs, exposed-data tuning and
this structural work. Its final code/configuration freeze precedes release of
the new corpus and questions. No private workload informed these designs.
Implementation, final model quality, exact charged-memory comparison, engine
choice and P27 completion remain open.
