# Execution profile contract

`Ipse.Profiles` validates up to eight named profiles and main/routine/review role
references with existing JSONSchex plus small cross-field policy checks. Profiles
are closed data, not a workflow engine. P15 scope/trust/precedence bounds apply.
Operator-declared IDs and any `base_url` are operator authority: project/directory
sources cannot redefine those IDs or carry an endpoint, even with generic project
trust. Project-defined IDs still use whole-profile replacement at nearer project
scopes; roles override by key. `URI.new/1` validates endpoint syntax with explicit
scheme, loopback, userinfo/query/fragment and port policy.
The selected main profile overlays file settings before environment/CLI limits;
conflicting provider/model/endpoint overrides fail. The effective manifest and
fingerprint include all configured profiles, roles and selected execution data.
Resume restores the selected profile ID, checks this fingerprint and execution
identity before work, and never changes providers or replays a child automatically.

Reasoning effort maps to Responses `reasoning.effort` while preserving the exact
model name and native continuation. Only documented exact `gpt-6.1-sol` supports
Ipse's initial low/medium/high/xhigh/max allowlist, shared by subscription and API
adapters. Both profile validation and the provider dispatcher reject unsupported
settings. See [model documentation](https://developers.openai.com/api/docs/models/gpt-6.1-sol)
and [reasoning guidance](https://developers.openai.com/api/docs/guides/reasoning).
The [public subscription inference interface](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
uses the public Responses endpoint with storage disabled; account/model support
must still be tested live. Configurable Ollama/Anthropic thinking is omitted:
[Ollama's controls](https://docs.ollama.com/capabilities/thinking) are model-dependent
and must not be guessed from OpenAI effort names.

Delegation definitions advertise only configured IDs and routine/review roles.
Validation rejects unknown routes before approval or child creation, including
parallel groups. A selected profile child starts with an allowlist of inherited
host policy (workspace/sandbox, instruction/skill home inputs, approval, origin
and the parallel-child hardlink restriction),
then selected execution fields. It drops parent API keys, endpoint, provider
module, conversations, native payloads, profiles and MCP state. Credential lookup
occurs in its own request task using the fixed reference for its provider; the
ChatGPT auth directory is passed only to a ChatGPT child. Same-provider inherited
routing retains existing fixture/embedded-provider behavior but removes unused
ordinary delegation-role/configuration data. Separately permitted `host.model`
instances retain a private helper-profile catalog and protected auth-directory
reference, including when the child's main provider differs. These are not SDK
payloads or inherited API keys; helper requests resolve their explicitly selected
provider's credential after admission. See [accounted model calls](extension-model-calls.md).
Helper approval displays the actual egress origin and a SHA-256 of the full target,
derived from the same adapter `endpoint/1` function used for HTTP dispatch. This
avoids a second default-route table and disclosure of URL paths/credentials.
Canonical saved execution facts retain their original profile/root-endpoint
digest contract; the approval's destination facts do not grant extra access.
Children remain owned by the worker and
parent, with existing cancellation, process-group cleanup, separate journal,
mutation approvals, conflict serialization and unknown-effect handling.

Child execution metadata is persisted before inference. `RuntimeInfo` exposes
only profile ID, role and effort alongside the existing provider/model facts.
Successful child results carry host routing facts before the explicitly untrusted
model result; this prevents the parent relying on child self-description. Limits
remain at most six admitted model/helper calls, 120 seconds and the parent's context ceiling.
An optional output cap also ceilings inherited/selected children: the selected
profile can narrow it but cannot widen or omit a parent bound. Combined provider
capability/range checks occur before delegation approval; unsupported subscription
routing refuses instead of dropping the cap. See [provider limits](provider-limits.md).
There is no fallback policy, recursive delegation, child MCP or summary-profile
routing. Configured roles are explicit host routes; semantic task classification
is the parent's proposal, validated by the host.

The feature adds no dependencies. Fixtures cover configuration selection,
unsupported effort/credential/endpoint combinations, explicit role and ID routes,
every adapter's configured model mapping, parent secret/native-history isolation,
forged-route denial, child metadata and idle no-replay. Existing ownership,
cancellation, approvals and interrupted-effect suites remain applicable.
See [operator setup](../operator/model-profiles.md) and [verification](testing.md).
