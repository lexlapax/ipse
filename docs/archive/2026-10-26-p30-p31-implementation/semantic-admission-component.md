# Semantic consent admission component

Dated **2026-10-26**. This is an incremental P31B engineering receipt, not an
operator procedure or whole-milestone acceptance. The [frozen baseline](baseline.md#permission-headless-operation-and-coordination)
and [contracts](contracts.md#consent-commit-order-and-process-coordination) own
the required boundary; the [plan](../../plan.md) owns completion status.

## Authority and Session activation

`Config.Semantics` admits operator-only `semantic_selections` references. Project
configuration cannot define, replace or erase them, including an empty registry
and explicitly trusted project configuration. A reference contains the project,
exact protected policy digest and enabled flag; it neither trusts an executable
artifact nor creates a protected permission grant.

`Extension.SemanticConsent.prepare/3` builds a closed policy for explicit setup
review. It binds the full reviewed artifact identity digest, namespace, admitted
project/worktree scope, source categories and literal relative-path exclusions,
local collection, retention categories, selected concrete inference routes and
disclosures, exact outer descriptor digests/inner operations, finite six-counter
period limits, expiry and headless choice. Source settings are independently
hashed. Existing bounded JSON parsing/encoding and Registry identity validation
are reused; cross-field scope and operation constraints belong to this adapter.
The prepared value establishes no operator-channel proof and is saved only through
the existing protected Consent API after host review.
Exclusions match an exact path or a directory prefix ending in `/`; wildcard
syntax, traversal and repeated separators refuse rather than silently implying
glob matching.

Namespaces are the digest of the closed version/project/logical-collection tuple;
setup cannot substitute a caller-selected identifier. One reviewed artifact policy
is active per project control ledger. A reviewed bundle can compose several domain
features, but separate artifact grants cannot silently multiply the project's
control allocation ceiling. Earlier domain artifacts remain explicit migration
inputs, with no inherited trust or permission.

`SemanticRoutes` constructs destinations from actual admitted main configuration
and named model, embedding and decision profile preparation. `main` is a separate
disclosure binding, with no inference-helper grant implied. Operator-only
`inference_services` explicitly groups canonical endpoint origins under stable
service identities; overlapping aliases refuse. Setup's nullable processing,
storage, cache and account labels remain reviewed disclosures, not facts attested
by providers. No authentication or network request occurs during this preflight.

Fresh-Session `Config.Semantics.admit/4` requires both selection and an independently
loaded matching protected policy. Its pin binds Session/project/worktree/binding,
policy epoch/digest, exact identity, namespace, routes and source policy.
`SemanticConsent.resume/2` preserves the old pin, including nil; it does not activate
a newly enabled selection. Each effect checks current policy epoch, expiry and
digest, so revocation or replacement cannot expand an existing pin. UI disable
must durably revoke protected consent before acknowledgment; editing only the
selection's enabled flag prevents new admission but is not immediate revocation.

`SemanticAdmission` loads the protected identity/control state and actual routes
for fresh admission, and returns a bounded inactive reason when a selection cannot
be admitted. Session creates its ID before the first exclusive Journal header,
then records the pin and Mode in that header. Resume validates and preserves the
original descriptor; a nil or inactive original admission does not load a later
grant. Session reports an unavailable selection as an inactive status.

This increment retains strict existing configuration and artifact resume
compatibility. Its direct equivalent-runtime test establishes nil-pin preservation;
it does not establish CLI resume after editing the operator configuration's source
digest. Compatibility for next-new-Session policy changes remains a separate
integration task owned by the root implementation.

## Mode and effect boundaries

The CLI/runtime now retain separate `approval_origin` and `headless` fields.
Unattended `--yes` is still headless. A missing legacy approval origin is explicit,
so legacy denial cannot silently become default-headless permission.
`Extension.Mode` separately captures active/enclosing normal, read-only, planning
and draft ceilings, plus available/paused/disabled knowledge. Inheritance retains
saved restrictions across resume/children rather than letting CLI approval widen
them. Broad approval never creates a semantic pin.

`SemanticConsent.authorize/5` accepts only a host-classified reviewed mapping for
local collection read/publication or selected model/embedding/decision inference.
It checks exact outer/inner coverage, every host-derived source category/path row
(at most 64), exclusions and the effect's current source-window generation. An
allowed row does not upgrade another row. The permanent Session pin contains
source policy; an ordinary new source window does not invalidate all authority.
The host source owner still validates actual origin, quotes, suppression and
source identity before constructing this context. A worker-supplied label is not
such proof. Workspace/shell, MCP, arbitrary service and delegation operations
are outside the accepted classes.

Publication mappings may contain the six closed reviewed CollectionPolicy
constraints: version, key prefix, closed value schema, evidence field path,
allowed source origins and explicit deletion choice. Only collection publication
accepts these constraints. Four base mapping fields must be unique, and worker
effects cannot carry constraints. The pure adapter accepts an older unconstrained
mapping for component compatibility; the live CollectionCall classifier must
refuse unconstrained publication and enforce the pinned constraints separately.

Authorization produces a finite reservation request, not dispatch permission.
Durable Session intent and Consent.reserve/admit/publish/settle remain mandatory.
Local collection reads instead use explicit `check/5`, which returns no durable
ticket; `authorize/5` rejects that class to prevent a reservation for every page.
The protected period `operations` budget counts durable knowledge mutations and
selected extra effects. Local reads charge Session read/step/context-byte ceilings;
this component implements no aggregate project-period read allowance. A read still
requires current protected-policy checking under the control/storage callback.
Paid API inference requires a nonzero finite cost reservation; actual pricing
and usage must still be established by its inference owner. No price is inferred
from a model name. Default-headless denial may permit an otherwise authorized
knowledge effect; explicit denial, publication under read-only/planning/draft,
and knowledge pause/disable still refuse it. Ordinary source reads retain their
existing read authority and are not newly classified as semantic capture.

## Checks and remaining integration

An isolated source checkpoint of SemanticConsent, SemanticAdmission, SemanticRoutes,
Config.Semantics, Mode, Config/CLI, Session/Saved, Journal, Delegation and the root's
CollectionPolicy compiled with warnings-as-errors against a copied complete
dependency snapshot. Expected module replacement warnings were suppressed only
for this explicit replacement of already compiled modules. **54 tests** passed
with seed **631431** in **1.3 seconds** after final child-pin isolation and
formatter compatibility repairs. Local receipts:

- `/tmp/ipse-semantic-admission-checkpoint-20261026-03/strict.log`
- `/tmp/ipse-semantic-admission-checkpoint-20261026-03/tests.log`
- `/tmp/ipse-semantic-admission-checkpoint-20261026-02/tests.log` (initial failures)

The active protected-IO branch actually ran on this host: explicit folder identity,
protected policy replacement, fresh active pin with actual route inventory, resume,
durable revocation and a subsequent inactive admission. Original-pin resume remained
available for inspecting the conversation. This test uses a synthetic reviewed
artifact identity; it does not start an extension or model. The first header tests
exercise actual fresh/resumed demo Sessions with inactive semantic admission.
The native helper was copied unchanged into the isolated runtime, SHA256
`385f42879330838a8635af4689d5c9fd422c6f19beb9de72b710474ac08f216c`;
no environment helper override or native rebuild was used.

Tests exercise exact identity/model/endpoint/namespace/Session/worktree bindings;
nil-pin next-new activation; revoke/replace/expiry; source generation changes;
excluded/generated source classes; finite strict counters; selected paid
inference; default headless versus explicit denial and unattended `--yes`;
enclosing/inherited ceilings; actual child inheritance; exclusive first-header ID
creation; explicit malformed header refusal; operator-only loading, fingerprinting
and runtime propagation; exact service aliases and reviewed publication constraints.
Input receipt validation retains its historical error precedence during bounded
context inspection. The first Mix attempt encountered an unrelated in-progress Collection
planner compile error. A direct first attempt used an incomplete dependency build
and failed eleven tests with missing Registry modules; the corrected dependency
path passed all tests. The latest first run passed 52/54: a new fixture wrongly
assumed message-only projections passed existing subscription validation, and the
isolated runtime lacked its own bundled helper directory. The corrected fixture
uses a real legacy header; the unchanged pinned helper supplies the runtime path.
Those initial logs remain temporary evidence.

Self-review also found that the later `semantic_admission` descriptor field had
not joined the older pin/context fields removed by child_config. Fresh Session
startup replaced it, but child configuration must never carry the parent pin.
The field is now removed at child construction and covered by the inheritance
regression. Actual Elixir 1.18.5 formatting checked the new Config.Semantics
guard form, and the documentation checker passed with 483 Markdown documents,
4,391 local links and no errors. The root owns independent review of this increment.

These are author checks. Before/after outer and inner dispatch gates, approved
Collection SDK/domain mapping, protected
setup/disable UI, actual eligible default-headless publication and independent
adversarial integration audit remain required. No automatic save, complete P31B,
source/installed parity, platform or model-quality acceptance is claimed here.
