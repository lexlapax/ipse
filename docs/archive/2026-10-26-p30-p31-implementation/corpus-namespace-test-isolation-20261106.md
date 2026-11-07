# Corpus namespace test isolation — 2026-11-06

Historical test evidence. The [plan](../../plan.md) owns current P31 status.

The running full regression against `0cdc36fa` reported an outer failure in
`Ipse.KnowledgeCorpusNamespaceFenceTest`. Its child completed all 16 controls,
but the wrapper rejected warnings that two fixture modules had been redefined.
The parent had passed an unrelated temporary fixture-harness directory to the
child through its complete code path. The original result remains in the active
run's `_build/verification/p31-final-regression-0cdc36fa-20261106-01/run-01/raw-private.log`;
the full run was still active when this record was written.

Commit `90f545c2` changes only the wrapper: the child receives the SDK and its
required dependency paths instead of the parent's entire code path. It still
rejects warnings, and the nested control marker requires exactly 16 cases with
no failures, skips or exclusions.

The focused test passed with both fixture modules deliberately loaded from a
synthetic harness in the parent process. The outer test reported one pass and
exit 0; the required nested marker establishes the 16-case result. The retained
packet is `_build/verification/corpus-namespace-isolation-20261106-01/`.
Its `focused.log` SHA-256 is
`79e6042940dc303dd0eec86bb1bb94d756e39a942a78d21ae9ac22ed90556e53`,
and its `status.txt` SHA-256 is
`931935425fedfe47b826857541e46859418a3c751a13f6afcd132ace14ea5f9f`.
The recorded inputs matched their post-run hashes. The run used one scheduler
and began with 2,814,736 KiB available; it did not use the shared native Input
or TCP test resources.

This isolated pass does not change the earlier full-run failure or establish a
passing current full regression. No model service or retained notes were used.

## Related Graph and Research controls

A separate synthetic Graph MCP child run reproduced the same two fixture-module
redefinition warnings despite five passing controls. Three wrappers had passed
their parent's entire code path to children that explicitly loaded that fixture.
Commits `84fe509b` and `2eff186b` restrict those child paths to their required
SDK and dependencies. The Graph children also now require exactly five and 34
tests, respectively, with no failures, skips or exclusions.

In separate contaminated-parent runs the Graph MCP outer wrapper passed once;
the Graph capture outer wrapper passed once with its native Session case excluded;
and the Research outer wrapper passed once with two unrelated cases excluded.
Their nested markers require all five, 34 and eight respective cases without
failures, skips or exclusions. These runs do not qualify the excluded native
journey or a current full suite. Wrapper and support-file pins matched before
and after the Graph runs. The Research run did not capture a complete SDK
before/after inventory.

The packet `_build/verification/graph-inherited-fixture-20261106-01/` retains
the reproduced warnings in `before.log` (SHA-256
`3237c773b6ab025f241e391c2ee8c1b4da4decac2bfc65a03a944be4f40dad4a`)
and final outer logs for Graph MCP
(`3410dcff4d3544e2fde7b16c4c45df53f6d2293ee0275a022694bb3927255642`),
Graph capture (`d990008e744332f16600df4662337b2b502480276d0a818d4ff17c233c131d19`)
and Research (`d34be75b04c373ca32cafcd95c6449eb8dcf94d2eb576171028c4bfeb4ba5805`).

## Document row-context control

A contaminated-parent run of the document row-context wrapper reached its
control marker but failed on six fixture-module redefinition warnings. Commit
`d6c03395` restricts the child code paths and leaves the warning check intact.
The same contaminated-parent wrapper then passed once with exit 0; its source
hash matched before and after the run. The before and after logs and status are
retained in `_build/verification/doc-inherited-fixture-20261106-01/`. This
focused control does not qualify the full document or installed journey.

The same inherited-path collision was reproduced for paragraph packing and a
selected fidelity test. Commits `c4bccf6b` and `12ff331e` isolate their child
paths; separate contaminated-parent checks passed with the original warning and
semantic assertions. After the fidelity repair, the entire fidelity file ran
at `12ff331e` with a contaminated parent: 38 passed, zero skipped or excluded.
Listed source, SDK and fixture hashes matched after the run; the postchecks do
not cover added files, links or file modes. No native Input or TCP test ran.

The full-file packet is
`_build/verification/document-fidelity-all-12ff331e-20261106-01/`. Its `run.log`
SHA-256 is `d6fa99549303225175a566a4492a9ea639079148b67940e4cced52eb29a87887`,
and `status.txt` SHA-256 is
`eb6ba8ffbbfae35702e014fd9ab71a536114ca209194503acb5a81c409049faf`.
This synthetic file-level result does not establish independent Word fidelity,
installed behavior or complete P31F acceptance.

## Minimum-version formatting check

A full Elixir 1.18.5 formatter check after the Graph changes failed on the two
new test-result markers. That attempt also emitted a Latin-1 locale warning and
an incompatible Hex archive error; its output remains in
`_build/verification/minimum-formatter-full-check-20261106-01/` with `check.log`
SHA-256 `3701057429f7417eaefc48844915272b9986e75e23cae66d3f8afc1196d62669`.

Commit `2626b361` applies the reported whitespace and line wrapping. The full
`mix format --check-formatted` then passed with Elixir 1.18.5/OTP 27.3.4 in a
fresh UTF-8, offline environment with empty private Mix archives. A separate
syntax-tree comparison against the committed preimages matched after metadata
removal; the changed inputs and formatter configuration matched their post-run
hashes. The packet is
`_build/verification/minimum-formatter-full-check-20261106-02/`; `ast.log`
SHA-256 is `ef53d1a52cc35a55b5af8c3eb64c4164032bc6666effffbb6847f2d98c26b6af`,
and `status.txt` SHA-256 is
`def680c6e4c65dc77e54d67f43606ab9c0ede9027a45820fd9fce8ade356277b`.
This check covers formatting, not compilation, tests or installed use.

## Package fixture and strict compile

The still-running `0cdc36fa` full regression reported a third outer failure in
the package isolation wrapper. Two nested Corpus fixtures expected an immediate
result rather than the new namespace-generation probe. Commit `d5e760fa` updates
those fixtures to assert the probe, a changed-generation conflict and a matching
generation result, retaining the original citation and reranking assertions.
The direct-result path accepts only the expected missing-embedding refusal.
Independent static review found no further blocker in that scope.

A separate isolated run passed one outer wrapper requiring exactly 33 nested
cases and no failures, skips or exclusions. The source and SDK inventories
matched after the run. Its packet is
`_build/verification/packages-focused-0cdc36fa-20261106-02/`; `fixture.log`
SHA-256 is `0a21a615d5069262bd155e6b5d4332c4361c54b45383f5a70c5dc33831434430`
and `status.txt` SHA-256 is
`db8bf9a67ac9e30c546f9712fa799918b86c4289093efc096c42d74fb07642b0`.
This separate pass does not change the live full regression's failure.

An isolated `mix compile --warnings-as-errors` at `8d372cea` passed after the
required native helper was built from the pinned source. Independent postchecks
matched the recorded source, dependencies, selected toolchain, archives and
helper; they do not establish the full dynamic-library closure or all metadata.
The compiler emitted a deprecation warning in the `elixir_uuid` dependency,
but no Ipse application warning. Its packet is
`_build/verification/compile-head-8d372cea-20261106-03/`; `compile.log` SHA-256
is `6ba839a85a48bd0a8ffae5f3424fd6b8a813634f853919f1e5c1c68526f57b24`,
and `run-status.txt` SHA-256 is
`a891486aae54573495b9daa62f6343c7b08a5be25216ec33d1d5b8d62793d45d`.
This proves compilation for that commit, not execution or a current full suite.

The two prior attempts are retained separately: packet `-01` was denied Mix's
local TCP lock by the sandbox before compilation; packet `-02` reached compile
but failed on warnings caused by its missing generated native helper. Neither
failed attempt is reclassified as a pass. Only the fresh `-03` attempt built
the helper before compiling.

## Artifact query time context

An independent scan identified a separate built-artifact test whose synthetic
query lacked the explicit historical time context now required before reranking.
The isolated baseline returned `query_time_changed` instead of reaching its
existing `document_current_check_unavailable` assertion. Commit `b85f381c`
adds that context; it does not change the document capability assertion or
production behavior. Independent static review accepted the fixture's scope.

The baseline and corrected wrapper ran in separate isolated packets at source
base `65c5a567`. The first failed as described; the second passed its one test,
and both packets report matching recorded source and SDK postchecks. Their
`fixture.log` SHA-256 values are respectively
`6093bb6729e1f5d67f15d8371609e87d5fbc7737df8033b205545608df4772f2` and
`9f1e20365f5e89511b615af7135fec5f0a63b098e7f545dd7f0e208b3728a636`.
The retained packets are
`_build/verification/embedding-artifact-context-65c5a567-20261106-01/` and
`_build/verification/embedding-artifact-context-65c5a567-20261106-02/`. This
focused pass does not change the outcome of any full regression. The `0cdc36fa`
full regression subsequently reported the same `query_time_changed` failure as
its fourth outer failure.

## Full regression terminal result

The `0cdc36faeee16bb5134e9933baaa996bd954e3d8` full regression completed in
9,911.0 seconds with exit 2: 4,305 of 4,309 tests passed, four failed, 136 were
skipped and 124 excluded. Its 517-file source copy, launch inputs and recorded
toolchain postchecks matched. Independent host inspection found the owned process
group absent and the Input lock and TCP port 39657 free. The result remains
failed; the later focused fixture passes above do not change it.

The retained packet is
`_build/verification/p31-final-regression-0cdc36fa-20261106-01/run-01/`.
`status.txt` SHA-256 is
`ee1f45d6aabd290847d06b2c9c3532690ef2ee92375832a084a3c42b888e081c`, and the
raw log SHA-256 is
`da18a30baf780ae0685d51cc4190311ef26c187f49f3ea0730662140c59896ed`.
