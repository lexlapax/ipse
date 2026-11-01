# Request local text context through the selected profile

Dated **2026-10-31**, based on `2542b0d` with source, tests and logs inventoried
in the [receipt](ollama-context-profile-20261031.json). This is historical
implementation evidence. Current tasks belong to the
[operator configuration manual](../../operator/configuration.md#request-an-ollama-context-window)
and [contributor training chapter](../../developer/configuration.md#trace-main-and-child-profile-selection).
The [plan](../../plan.md) owns remaining acceptance.

The earlier primary-pair smoke observed loaded context of 4,096 tokens despite
larger architectural declarations. Inspection can report that difference, but
profiles previously could not request a context window. This increment adds the
bounded request setting; it does not qualify the primary pair or authenticate
per-request weights/context.

## Result and compatibility

An operator-owned named Ollama text profile can set `ollama_context_tokens` to an
integer in 512..262144. The existing adapter sends it as `options.num_ctx` along
with any output limit. Main, draft, summary, routed child and extension text
requests use the selected profile. Summary options retain the window while
narrowing output and setting their existing temperature/thinking controls.
Project definitions refuse even under explicit trust. Top-level settings,
embedding profiles, other providers and CLI/environment overrides do not gain
this field. No provider/billing selection, service configuration, model download,
native protocol or dependency changes.

The existing Registry now distinguishes optional route fields by actual
presence. An omitted field produces no added main manifest key, helper snapshot
key or wire option; old public helper snapshots still validate. New selections
bind the value into execution/approval facts and the ordinary configuration
fingerprint. The exact request-body digest also covers it. Selecting another
profile does not retain the parent's request. Existing required OpenRouter
fields/defaults remain required and unchanged.

This is an explicit requested context, not a measured allocation, sufficient
prompt budget, no-truncation guarantee or immutable model closure. Increasing it
can require more memory; the service/model can cap or refuse it. Metadata remains
a cooperative service claim. Full model identity checks around jobs, effective
context checks, offline/resource/quality evidence and embedding-context support
remain open.

## Verification actually run

The first focused cohort passed35of38tests. One fixture incorrectly expected an
unnarrowed helper deadline; two failures exposed missing strict integer/null
admission and project authority checks for the new field. The fixes preserve the
existing request narrowing and add the appropriate producer-owned checks.
The corrected focused cohort passed38tests. The final broader non-terminal
cohort passed **186 tests in 3.9 seconds** across configuration, profiles, actual
delegated wire/Saved history, helper inference, provider registry/conformance,
HTTP and draft response limits.

Native loopback HTTP controls inspect exact normal/draft/summary bodies. The
delegation control additionally verifies selected `num_ctx`, original credential
and history isolation, saved execution metadata and successful child reconstruction.
Legacy helper snapshots, absence, changed fingerprints, another selected profile,
unsupported providers, project refusal and invalid types/bounds are checked.
These are synthetic requests, not live Ollama inference or native terminal use.

The complete documented profile was extracted from the operator chapter and
passed actual CLI inspection with no inference. The first helper used a relative
executable path and failed with `enoent`; its absolute-path correction passed,
with both logs retained. Build, strict compile, format, credential-free demo,
repository policy and whole-manual/link verification are recorded in the receipt.
The operator and contributor configuration chapters were reviewed in full and
reconciled so the older claim that profiles cannot request context is removed.

The native API was checked against Ollama's
[parameter reference](https://docs.ollama.com/modelfile#valid-parameters-and-values),
[context guidance](https://docs.ollama.com/context-length),
[loaded-model response](https://docs.ollama.com/api/ps) and
[embedding request](https://docs.ollama.com/api/embed). This increment only uses
the text adapter's context option. It consumes no real request allowance and
does not replace the separate full suite or installed-candidate qualification.
