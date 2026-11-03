# Combined 33-note Session failure, 2026-11-03

One fresh synthetic Session using the combined replay-containment and generic
v4 batching candidate failed before the fixture received a provider request.
This does not establish the failure's cause or qualify 33-note recall. The
[earlier strict one-shot](recall33-one-shot-20261103.md) used a different
candidate and Session; neither unknown turn was replayed. The
[generic batching review](generic-v4-batching-dcbb-20261103.md) describes the
preceding focused tests and their limits.

## Input and execution

An isolated source tree was reconstructed from commit
`dcbb07dd451f1402d28391b716b2b177e35331a7` and the archived
[generic patch](recall33-combined-dcbb-20261103/generic-reviewed.patch) and
[strict fixture patch](recall33-combined-dcbb-20261103/recall33-fixture.patch).
The four generic patch outputs matched the earlier candidate's tested source
hashes. A fresh test runtime, native helper and knowledge bundles were built;
project compile with warnings as errors and bundle build succeeded. Dependency
compilation emitted third-party warnings. The initial dependency postcheck
identified one changed generated telemetry Rebar `source.dag` cache; that
failure is retained, and the resulting dependency tree was separately
fingerprinted without rebuilding.

The independently reviewed [one-shot launcher](recall33-combined-dcbb-20261103/launch-once-no-helper.sh)
used the actual strict ExUnit fixture through a
[small test entry point](recall33-combined-dcbb-20261103/exunit-one-shot.exs)
that avoids the repository test helper's `HOME` assignment. The shell left
`HOME` unchanged, cleared relevant inherited VM and loader overrides, used a
private synthetic `IPSE_HOME`, verified source and runtime manifests, and
checked the actual application, relevant loaded BEAM paths, native helper and
knowledge bundle identity. The source review of HOME isolation was not an OS
filesystem trace. The fixture created its own fresh synthetic home, explicit
configuration, source Sessions and consent. It used the product's normal
Worker deadlines and an explicitly configured 5,000 ms provider timeout. The
900-second PTY and 960-second ExUnit limits bound fixture setup and do not
change those product deadlines. No automatic retry was allowed.

## Observed outcome

The fixture created 33 distinct reviewed source Sessions, withheld the source
of the first sorted record, and recorded its one-shot intent before prompting.
The retained log reports all 37 Worker inputs delivered, 35 managed read
observations, managed preflight intent/result and an inference-dispatch intent.
The local fixture accepted a connection but reported it closed before it read
request bytes. The synthetic consumer journal records a failed model measurement
at 16,388 ms and a failed, partial request at 16,389 ms, with unavailable usage
and no specific recorded error reason. The turn ended in error. A dispatch
intent alone does not establish that HTTP request bytes were sent.

The earlier failure's recorded measurements were 15,799 and 15,800 ms. The
similar timings do not establish a timeout or a shared cause. The full
provider-reference assertions, same-Session close/reopen and no-replay check
were not reached. No 33-note success or population-scale success is claimed.

All listed source and post-build dependency files passed the launcher's hash
postcheck; regenerated compiled/native and bundle inventories matched. A
separate read-only check compared all 33
original source journal device/inode/owner identities and hashes and lock
identities with the retained pre-run inventory: 33 matched and none had a
remaining `.held` journal. No second attempt was made. The synthetic fixture,
its source Sessions and failed consumer Session were retained for inspection.

The [evidence manifest](recall33-combined-dcbb-20261103/evidence.sha256),
SHA-256 `102235709b9ca285e7b4283322fab06218183645cf2fc5c8ad606e71f06eb4b1`,
indexes the launcher, patches, source/runtime manifests, logs, input intent and
read-only analysis. Runtime artifacts and the complete consumer journal remain
in volatile synthetic storage, not in this archive. The consumer journal's
[recorded hash](recall33-combined-dcbb-20261103/volatile-consumer-journal.sha256)
permits comparison while that journal remains available; the archived selective
analysis is not independently linked to the unavailable full journal after it
is removed. The [current plan](../../plan.md) owns milestone status.
