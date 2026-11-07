# P30 assessment route binding, 2026-11-07

This dated development record describes an isolated candidate, not P30 or P31
completion. The [plan](../../plan.md#p30-advisory-decision-engines) owns current
status; the [decision guide](../../developer/decisions.md#materialize-a-candidate-assessment)
explains the current assessment workflow. This follows the
[assessment materializer checkpoint](candidate-assessment-materializer-20261106.md).

In a source archive based on `662ca1b9c30e0893f68e1410b72e90ac112bf2ee`, the
assessment owner gained a version-2 declaration containing a digest of the public
`advice` decision profile. Its preflight requires that profile to be the only
configured decision profile and compares it with the frozen declaration before
starting a Session. The owner also checks selected main-route and context controls,
and checks a recorded decision's profile and effective execution before projecting
a known result. Version-1 declarations retain reading and scoring; new Session
work requires version 2. These are restrictions on this dedicated development
owner, not a new approval or a general provenance guarantee.

Thirty-four direct synthetic controls passed with no exclusions on Elixir 1.20.4
and Erlang/OTP 29, loading the existing P31 integration candidate's built test
runtime. The two assessment test files include route substitutions, separately
redeclared and rehashed profile mismatch, altered main settings, recorded execution
binding, version-1 scoring, and an isolated OFF-preflight subprocess. The latter
checks that no Ipse application, Session, Input process or new port starts. The
changed Elixir files were formatted with Elixir 1.18.5/OTP 27. No Mix, native
protocol, network, retained notebook or live service was used for these controls.
A local verification note retained the exact command and source hashes under
`_build/verification/p30-route-binding-only-20261107-01/EVIDENCE.md`; this
workspace-local note is not a durable archive dependency.

Independent reviewers reported reading the developer decision and operator
Knowledge-permission manuals. The developer reviewer reported successful direct
runs of two self-contained examples and a reference example using a valid synthetic
note key; an earlier invented `record1` key failed the key grammar and remains a
separate failed attempt. Exact commands for those example runs were not retained.
The operator reviewer statically checked key CLI dispatch and limits and reported
no concrete inaccuracy; operator examples were not executed. The documentation
checker covered 1,318 Markdown files and 10,578 local links with no errors. These
checks do not validate every unrelated statement or establish installed behavior.

The main digest is not a complete matched-workload identity. Declared source and
runtime digests are not authenticated by this increment, and the rubric has no
exact pre-dispatch fence. The synthetic native materialization protocol, full
baseline, independent quality evidence and P30/P31 acceptance remain open.

After the original pure controls, review found that the main-route digest omitted
Ollama's requested context tokens and model pin. The candidate now includes both,
and the preflight substitutions include a validated synthetic pin. An initial
updated control failed because its fixture used a non-version runtime string;
after correcting the fixture, the two pure files passed 34 tests on Elixir
1.20.4/OTP 29. A later run with a direct Ollama configuration comparison passed
35 tests. These controls do not establish native Session behavior. The
previous native-preparation source inventory predates this change and must not
be used to launch the test; a fresh reviewed inventory is required after the
currently running regression finishes.

A subsequent review added Anthropic's `max_tokens` fallback to the digest.
A direct test checks both the produced request and digest for changed limits;
the updated two-file pure run passed 36 tests. Native verification remains open.

Further inspection added supplied response-size limits and structured/summary
schemas to the digest. A direct Ollama request check and the assessment tests
passed 37 pure controls. The digest still does not authenticate dynamically
constructed requests or establish a fully matched workload.

Independent review also confirmed that a decision request may choose a shorter
timeout than the frozen profile's ceiling. The recorded binding checks that
effective value, but the declaration does not freeze it; timing comparisons
therefore need separate exact-request evidence.

The revised candidate subsequently passed one fresh synthetic native Session
assessment: seven main requests including five seed requests, one decision
request and one known settled decision call. It froze the first row, rejected
non-independent synthetic labels and passed Saved/idle no-replay checks.
Independent post-run checks matched the source and runtime inventories and
found no surviving observed group, checked-lock users or open scratch files.
They cannot establish the absence of every detached process. The fixture is
not a model-quality, matched-workload or live-account qualification; the rubric
still lacks a pre-dispatch exact-request fence.
