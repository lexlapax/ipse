# P30C pure consumer policy component

Date: 2026-10-27 (implementation began 2026-10-26). Author verification of a bounded implementation increment;
independent review and integrated P30C/D/E acceptance remain open. Current usage
and the runnable exercise belong to the [developer decision chapter](../../developer/decisions.md#exercise-a-consumer-without-contacting-an-engine).
The [plan](../../plan.md#p30-advisory-decision-engines) remains authoritative for
milestone status. This record establishes no engine quality or live access.

## Authorized scope and resulting behavior

Root ratified only the first pure consumer planners/mappers and zero-call
controls from the read-only P30C proposal. No protected decision-v2 operation,
semantic outer/settings changes, inference authority, experiment runner, live
experiment, managed reader or store effects were authorized in this increment.

`IpseKnowledge.Knowledge.DecisionPolicy` is included in the independently built
Knowledge artifact. Its `plan/3` and `apply/2` perform no IO. Production always
returns a zero-call plan: there is no qualified production catalogue, and supplying
a qualification hash in JSON does not create one. Explicit development mode may
construct bounded legacy `decision.create` request data, but grants no permission
to send it. Facts and pure receipts explicitly remain untrusted data until a
future host producer/admission adapter exists.

Selection filters at most eight packs over sixteen complete rendered candidates;
each decision pack contains at most four records and must fit the actual supplied
allocation, capped at 6144 bytes. `rendered` must include each record's complete
framing/citation/separator bytes; selected chunks are concatenated without adding
unbudgeted bytes, and any shared frame is deducted by the caller before supplying
the allocation. Pack member IDs are canonicalized as sets; permutation-only
alternatives collapse to one zero-call choice. Assessment permits at most eight
candidates; profile names match the existing 64-byte operator grammar. This is a
trusted-caller contract for a future host adapter: supplied JSON proves no actual
allocation, framing completeness or eligibility. Only that future owner may derive
the grant and validate the final rendered projection. A complete fitting set uses every available rendered record
even with strategy none; the decision-pack cardinality does not discard fitting
records. Unknown/incomplete coverage is not an empty set. Fitting total metadata
without all rows produces an explicit zero-call coverage gap. Zero allocation,
absent candidates, zero/one unique alternatives, unavailable budget and absent
qualified strategy all generate no request. Bounded selection excerpts are marked
partial with original byte count and content hash; assessment input never truncates.

Assessment chooses only `keep_baseline` or `defer_candidate` for an existing
proposal. It cannot change text, source class, category, TTL, evidence, operator
acceptance or effect permission. Independent valid per-question refusals use their
baseline; structural corruption invalidates the whole result. Unknown outcome or
advice never installs suppression or publishes another note.

Both mappers reuse the existing complete neutral validator and `select/5` through
three public `Ipse.Extension` delegates. The host `Ipse.Decision` implementation
is unchanged. Probability 0.8 and margin 0.2 are fixed. The margin is redundant
under a normalized selected probability of at least 0.8 (remaining mass<=0.2),
but remains an explicit check. Raw native confidence is separate. Ties/refusal/
low probability/malformed advice use labelled baseline behavior, not invented
negative semantic evidence.

All facts use the unchanged 16-KiB public SDK bound, UTF-8 and closed keys. A
request permits at most 8192 input bytes and 16 KiB escaped total, with 30000-ms
timeout. A private reconstructible Plan has a separate 32-KiB ceiling; it is not
a public wire value or transferable capability. No dependency, service, model,
provider fallback or default automatic consumer is introduced.

## Exact author graph and checks

The [machine-readable receipt](p30c-pure-policy-runtime.json) binds the five owning
code/test inputs, unchanged neutral implementation, all 163 private application
BEAMs, helper inventory and retained Elixir 1.18 artifact files. Base source at
copy was `11d3f9cd8303f088dc2dd2119303e3b8db95540a` plus this component. Root's
later ManagedReference edits were not copied into the frozen graph or tested here.

Private project/build:

```
/tmp/ipse-p30c-policy-20261026-01/project
/tmp/ipse-p30c-policy-20261026-01/build
```

Only dependency source is shared read-only. Generated application, artifacts,
minimal SDK, temporary homes and compiler outputs are private. Primary builds,
`priv` bundles and the shared native helper were not changed or executed.

| Check | Actual outcome |
| --- | --- |
| Full fresh private application compile |128 source files, warnings-as-errors passed on Elixir 1.20.4/OTP 29 |
| Final sealed focused compatibility command |55 passed, seed752530,6.0s; preceding exact-source run5.9s |
| New policy cases within that command |12 cases, including a real separate artifact/minimal-SDK child |
| Actual Elixir 1.18.5 formatting |4 owning source/test files,0 differences; host OTP 29 |
| Actual Elixir 1.18.5 strict minimal SDK plus Knowledge artifact |3 SDK source files, actual Knowledge helpers/artifact build, all 3 delegates and planner/mapper exercised; host Session/Artifact modules unavailable |
| Current formatter / whitespace |4 files and `git diff --check` passed |

Final focused command (run with the private MIX_BUILD_PATH):

```sh
mix test --no-compile test/extensions/knowledge/decision_policy_test.exs \
  test/ipse/decision_test.exs test/ipse/provider/decision_test.exs \
  test/ipse/extension/decision_call_test.exs test/ipse/json_test.exs \
  test/extensions/knowledge/knowledge_capture_test.exs \
  test/extensions/knowledge/knowledge_contracts_test.exs \
  test/extensions/knowledge/profiles_test.exs \
  test/extensions/knowledge/build_spec_test.exs
```

The minimal SDK is compiled from `lib/ipse/json.ex`, `lib/ipse/decision.ex` and
`lib/ipse/extension.ex`, which includes ResultDocument/ResultPublication. Existing
Jason, JSONSchex and JSON Pointer dependencies are copied to private paths. The
actual Knowledge builder's helper whitelist includes the new policy. The child
does not receive the whole host ebin; it asserts Session and Artifact are absent
before exercising request validation, result validation, selection and mapping.
The separately retained floor build is
`/tmp/ipse-p30c-policy-20261026-01/floor118-final/artifact`.

The final sealed repeat used the same seed and passed55 in6.0s. Its695 private
source-code inputs and688 runtime files were byte-identical before/after:
manifest SHA256
`ed7b5142e7cc92516972155801fd8cce162e5da2fd24dd2ba81105e9c2d40797`.
That seal covers private lib/extensions/tests/dependency code and Mix inputs,
application/dependency ebin, copied priv and retained floor SDK/artifact files.
It excludes OS/toolchain distributions and deliberately temporary generated test
outputs. Both full manifests and the repeat log are retained with the receipt;
this is a file-integrity observation, not a new platform or model qualification.

The first compile attempt was blocked by sandbox Mix TCP-lock `:eperm`; an
approved local-loopback retry passed. Its original log was overwritten on retry;
the observed failure remains in the author tool transcript and is not represented
as a retained raw log. The first 16-case run and subsequent 41/55-case compatibility
runs passed. A self-review then corrected full-set baseline inclusion with
strategy none and strengthened the minimum-SDK child to exercise all three
delegates; the final 55-case result is the receipt's claimed source.

Durable raw successful logs and runtime inventory are retained under:

```
/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/p30c-pure-policy
```

## Manual review and remaining boundaries

Reviewed the complete developer decisions, extensions and dependency chapters,
operator extensions chapter and Knowledge README. The developer exercise teaches
pure planning versus dispatch and the public SDK closure; inventory confirms
reuse of project-owned code/existing packages. Operator guidance already keeps
typed advice explicit with no automatic consumer. README setup wording was
reconciled with the existing standalone permission guide; it still distinguishes
automatic capture/recall/lifecycle work from the available permission procedure.

No paid/local live engine inference, network service, model download, native PTY,
full suite, package, installed workflow, OTP 27, macOS or hosted CI was run here.
Actual Elixir 1.18 compilation on OTP 29 is source/toolchain evidence, not OTP 27
execution. Protected decision-helper admission and current managed eligibility/
retraction remain absent. D/E's actual Main-producer replay runner, separately
granted finite evaluation and independent held-out quality comparison remain
unauthorized/unimplemented in this increment. There is no qualified strategy,
no negative engine-quality finding and no P30C-complete claim.
