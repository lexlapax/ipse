# Available-host protected Session diagnostic

2026-10-27. The developer requested adapting gates to available resources.
The [plan](../../plan.md) now permits qualified completion of the tested scope
without treating unavailable platforms, accounts or human journeys as passes;
the current native profile remains unverified. This is functional
diagnostic evidence, not qualification of the production storage profile.

On the available `7.2.11-arch1-1` host, an isolated copy of the current source
was created at `_build/available-host.qEkKPin5`. Only its private
`native/ipse-storage-profile.rs` was modified to accept that exact kernel
release in addition to its existing test conditions. A private helper was built
from that copy with Rust 1.99.1; neither the shared helper nor the production
profile was changed. The private helper SHA-256 is
`b7ea344b9b631208e9f766885d781cf3753d8569ed6a55f08fbe610fa28528bb`,
and the modified private profile SHA-256 is
`02b86baa7a8bbf3b153df1f747ab396a5b0d5f4976305c0d79939dfe5b2d107c`.
The copy uses the existing dependency source and copied dependency build outputs.
The forced test-environment compile of 152 project modules passed with warnings
as errors and local TCP access.

With the same private helper, the synthetic inference-dispatch Session,
Session inference-dispatch, semantic-loading and managed-collection Session
suites reported **39 passed** (seed 46370, one case at a time). These tests
exercise positive protected Session paths that the production-profile run
refused on this host. The command output was observed through the execution
tool; a separate full log was not retained. A post-run source-file inventory
at `source-sha256.txt` in the private graph has SHA-256
`26e9bcae12adbcc0757baf797f2e2ffac8e71a1fd87ddc8605104965a7f56e4c`;
it is not a pre-run immutable source manifest. Test homes and stores were
synthetic; no existing `.serenity-*` evidence, capacity workload, credentials,
external model or release publication was used.

The override intentionally bypasses native-profile admission and therefore
cannot prove the production helper's policy or allocation bounds. In particular,
the Btrfs writeback-error and allocation-failure evidence in the [open audit](2026-10-27-open-audit.md#linux-7211-qualification)
remains unresolved, as do actual managed lineage and the inference current-root
barrier. These positive functional paths are not the full suite, platform
qualification, crash-durability proof, or final adversarial audit.

The same private graph subsequently ran the synthetic observed-read, v3
normalizer and publication, managed pages and directory, neighbors, read-view,
legacy normalizer/managed collection and collection-Session suites. They
reported **134 passed** (seed 46371, one case at a time). This includes the
small actual v3 publication series and the 4,000-identity pure geometry test,
but no 4,000-publication capacity or turnover workload. The available-host
override and the limits above still apply. The command output was observed
through the execution tool; a separate full log was not retained.

## Full diagnostic and corrected failure checks

An isolated full `mix test` run used seed 46372 and one case at a time, using
the same private helper. Its full output is
`_build/available-host.qEkKPin5/full-regression-46372.log`, SHA-256
`c5e422ffddc2b4b175e778cf9ba533e56feacae5fae439af766a5c4e93899eac`.
It finished after 2,002.3 seconds with **2,777 of 2,788 passing, 11 failing,
4 skipped and 36 excluded**. This is a failed run. The post-run source inventory
check passed against the earlier manifest.
The initial copy omitted `.github/workflows`, and its scratch directory was
inside the copied repository; these caused missing-workflow and fixture
boundary/output-isolation failures. A separate profile integration assertion
also assumed that an explicit denial on resume appended no checkpoint; the
working-tree test was repaired and its focused rerun passed. The pipeline used
`tee` without `pipefail`, so its shell exit status is not the test status; the
failure result above comes from the ExUnit summary.
The same run also found a legacy provider-session test that expected unchanged
journal bytes after resuming under explicit denial. The working-tree test and
its fixture documentation now require the original prefix plus the exact bound
version-2 checkpoint; the focused provider fixture test passed (seed 46374).
Two additional verifier failures currently trace to the in-repository scratch
location. The corrected graph includes both test repairs.
Two source-freezing variants also failed with a manifest-size error; the initial
graph lacked `.gitignore` and included generated files. A further frozen Research
evaluator failed without a confirmed cause. All classifications remain subject
to the corrected rerun.

A corrected graph at `_build/available-host-corrected.9kdxAhKx` has the missing
root/workflow files and the repaired test. Its test scratch directory is
`/var/tmp/ipse-available-regression.rPJBrBDh`, created with approved local
access outside the repository. The focused rerun of all 11 failed cases passed
(seed 46375, 130 unrelated cases excluded). Its log is
`_build/available-host-corrected.9kdxAhKx/_build/corrected-failures-46375.log`,
SHA-256 `b25495b3853ba2f97bd220eeaee32ccca2fe28ab6d2bba4301a062088ae38136`.
The pre-run source inventory was unchanged after that rerun; its SHA-256 is
`980d39ee7ab6b4435ebfbadca22ea807a06c48b3971d3d997499a581534b0b0b`.

The corrected full run exited successfully: **2,788 passed, 4 skipped and 36
excluded**, seed 46376, with two cases at a time and `pipefail`. Its log is
`_build/available-host-corrected.9kdxAhKx/_build/full-regression-46376.log`,
SHA-256 `78ba08b3e08aa228972ac32fac51b77f64374d7961ef2c97df491493ea5f87cd`.
The pre-run source inventory remained unchanged. The four skips concern an
optional PDF parser absent from this graph; the excluded tags cover native and
macOS sandbox, macOS filesystem and memory-scope tests. Its helper remains a
test-only override, and neither graph is a release candidate or production
native-profile qualification.

The skipped PDF cases were subsequently exercised separately on the corrected
graph using the existing `_build/p30-current-validation.ri5cUYdZ/priv/ipse-pdf`
binary. Its SHA-256 is
`85cde09bd8783ef99427bcd07f5708b33b9e46138e58288d2790eed1544b6556`;
the parser source in that earlier graph matches the current parser source.
Both PDF test files passed all five selected cases, seed 46377. The log is
`_build/available-host-corrected.9kdxAhKx/_build/pdf-followup-46377.log`,
SHA-256 `eab30784661dd839bf862328e5e698d734d9749eae1490cf2ae80fe8233b5f57`.
This is a separate diagnostic using an existing binary, not a rerun of the full
suite with a newly built parser.

The separately excluded Linux sandbox fixtures were also run on this graph:
`mix test test/ipse/tools/sandbox_test.exs test/ipse/runner/stdio_test.exs
--only native_sandbox --seed 46378 --max-cases 1` passed 17 cases with 22
excluded. The log is `_build/available-host-corrected.9kdxAhKx/_build/native-sandbox-46378.log`,
SHA-256 `e7fe105f254f71210a220aea295ea3ba860914731775917b76ffa3228848145e`.
This exercises the Linux sandbox fixtures on the available host; it does not
establish the separately gated protected-storage profile or its durability.
