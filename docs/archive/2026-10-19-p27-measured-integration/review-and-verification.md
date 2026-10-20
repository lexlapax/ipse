# Measured integration review and verification

Dated working record, 2026-10-19. P26 is accepted at `25f1d8e`; P27 remains open.
The implementation begins at `2c2ffd7e01b6ac590937b2854543dc9537b2a67c`.
Use the [current training manual](../../developer/knowledge-evaluation.md) for
supported procedures. Verification below is limited to the named snapshots.

## Selected design

The user selected exact workload-charged RAM, including cache and kernel charges,
through an optional Linux cgroup backend. The comparison uses the separately
approved CPU-only policy. Existing systemd user tools are an approved optional
benchmark dependency. No host name, distribution, kernel release or tool version
is a portable experiment admission requirement. Runtime and host facts belong
to each local seal and its provenance.

Two independently developed design candidates were compared before integration.
The selected owner, `EvaluationMeasuredExecution`, owns native authority,
execution and audit. Freeze owns identities, Runner owns complete domain work,
ModelService owns its daemon/cache lifetime, and Rust owns kernel scope handles.
The finite preparation, cell, finalization and root deadlines are frozen before
execution. No additional external dependency was introduced.

## Adversarial review dispositions

Two reviewers examined the full integration in separate contexts. They used the
same model; this is not model-diverse or external independent validation. One
reviewer had authored Runner/MeasuredExecution, the other the synthetic fixture
and timeout decomposition. Their relevant self-review limits were recorded.

| Finding | Disposition |
| --- | --- |
| Git verification can refresh `.git/index` | Reproduced by touching an unchanged tracked file. The original check rewrote the index. Git now runs with `--no-optional-locks`; the same regression passes without changing index bytes. |
| Installed tool absence is checked only in the outer release PATH | Accepted as an evidence limit. Measured stages and the model daemon construct their own PATHs with system utility directories. Commands select the sealed ERTS explicitly; the installed check does not prove build tools are absent from the entire population. |
| No executable control for the new v2 review/score audit gate | Added a rerunnable post-execution verifier. It requires actual CLI review, failed unmeasured CLI scoring and ten refusal controls before label/review access. Passing evidence remains separate from implementation. |

The review also identified missing live coverage for authority descriptors,
ordinary child isolation and integrated owner/collector/service loss. Five
dedicated fresh-seal controls now pass. A final read-only review of those
controls found no additional actionable issue; its author disclosed earlier
fixture/scoring authorship. The earlier native component tests do not substitute
for these integrated checks.

## Reproduced integration failures

All attempts below used isolated temporary checkouts and synthetic model bytes
on Linux. Serenity's main checkout was not changed. Each failed attempt retained
its original claims and evidence; a new seal and directory were used after a
repair. No failed or uncertain model request was replayed.

1. The explicit ERTS command supplied `-root` in addition to the root supplied by
   the selected `erl` launcher. Actual Linux startup refused with
   `no_or_multiple_root_variables`. Removing the duplicate argument repaired
   startup. The command now has a real ERTS round-trip regression.
2. A redundant raw code-path comparison rejected relative source paths after
   Freeze had normalized and verified them. Removing that second representation
   check preserves Freeze's authoritative ordered runtime snapshot.
3. Preparation passed `/proc/self/fd/4` paths to ordinary native lock and query
   projection children. The child resolved its own descriptors, so catalog
   import failed before model work. A small actual Linux lock probe reproduced
   failure with the self path and success with the owning VM's procfs path.
   Preparation now names its owning VM while keeping authority FDs private.
4. The synthetic daemon launcher passed Erlang character-list paths to Elixir
   binary-path functions. The first complete sequence retained 350 unavailable
   rows and failed its audit. Correcting the launcher conversion made the actual
   generated-wrapper test pass. Those failed rows are not successful predictions.
5. The next sequence completed its first cell, but later synthetic daemons
   refused the fixed port with `eaddrinuse` after the first daemon's connections
   closed. A two-successive-lifetime regression reproduced this failure. The
   fixture now uses TCP address reuse, while retaining exclusive listener
   admission and fresh daemon/cache ownership for each cell.
6. The first owner-loss control took its immutable snapshot after the population
   became empty, while the root collector could still write its final receipt.
   That control failed. It now retains the collector's process start identity
   and waits for that process to exit before checking receipt immutability.
   All byte assertions remain. A fresh five-control execution passes.

The original interrupted 280/350 comparison and its unknown request
`460d3a507ac34384429899dd4a37d668` remain immutable. These synthetic exercises do
not resume or renew that comparison.

## Checks and outstanding evidence

The complete source synthetic exercise passes at temporary verification snapshot
`682ff08a4238a105c751facc01ee237930c838f8`. It saves 350 successful first rows
across fourteen cells and sixteen measured stages. The read-only audit digest is
`3b6e78364a30dc88765ffb7a6fb0923b12dc73571b85122dea05ed82449026f6`;
the first-prediction digest is
`783b296aabaaed61ddecd29fc0f3241960fb0be170d40cd49233a84526bec016`.
The scripted service recorded 350 answer, 156 embedding, two extraction and
50 rerank operations. These are protocol/accounting observations, not inference
quality measurements. The [closed source summary](source-proof.json) retains
the exact identities, counters and synthetic peak subject. Five byte-tamper and two directory-replacement controls,
read-only repeated audit and refused reentry pass. Actual CLI review succeeds;
untouched semantic templates fail scoring as unmeasured. Ten audit/path/hash
refusal controls leave labels/reviews unopened and all evaluation artifacts
unchanged.

Five integrated authority/loss controls pass at later temporary snapshot
`6cfda178c49723ca8d2884f87040739e4c2023a3`. Each observes real ERTS descriptors
4–8 and kernel membership. The service-stop case verifies no authority object
survives in the ordinary native helper or daemon's FD inventory. Owner loss,
collector loss, service stop, live registry replacement and first-answer daemon
self-exit all retain incomplete outcomes, confirmed scope cleanup and refused
reentry. The daemon-loss case retains a noncompleted canonical request; absent
domain accounting is reported as unavailable, without an inferred reconciliation.

On macOS, 1,294 full-suite tests pass with one skipped and 34 excluded. The
explicit native run passes 30 tests, six excluded, and four native policy tests
pass. Build, strict core/script compilation, demo, package construction and the
extracted-package verifier pass. The focused boundary/fixture run passes 27
tests. Linux's actual generated-daemon fixture run passes four cases, including
successive lifetimes on the same origin. Strict native controls pass thirteen
sequence, seven bound-authority and one environment-selector tests; macOS runs
the three portable authority tests. The live generic native collector's ten
controls and sequencer's six controls pass with zero inference requests.

The exact baseline commit's hosted run
[39367709590](https://github.com/lexlapax/ipse/actions/runs/39367709590) is red.
Ubuntu passed all steps; macOS stopped at two existing aggregate 60-second test
deadlines, before package/native proof steps. The nine-case independence test
and multi-process CLI test have been split into independent complete cases with
unchanged deadlines and assertions. Their focused ordinary-deadline run passes;
a new exact-source hosted result is still required.

The [installed synthetic exercise](installed-proof.json) also passes all 350
rows, sixteen stages, repeated audit, tamper/reentry and review/scoring controls.
It produces the same first-prediction digest. Its independent audit digest is
`ff962017c71a2f2635647aace46cdc1a5be99b81f3877294a08c864729dc2213`.
The tested archive SHA256 is
`6b3144d42c6a54e546997f0059dad8c85fc57dc4494859de1dc1994aee2be738`.
Runtime provenance is Elixir 1.20.4/OTP 29 on x86-64 Linux. Observed host facts,
including the kernel and systemd versions, are retained as evidence, not
experiment admission requirements. The separate Linux extracted-package check
and source demo pass. The full Linux native-enabled source suite passes 1,333
tests, with 17 excluded, in 700.4 seconds. Its source remains clean in the
isolated checkout; Serenity's main checkout is unchanged at `5e2d85e`.

Whole-manual editorial review was completed across the affected
contributor chapter and operator entry points. Its one callback-exception
clarification was repaired. Documentation checking reports 262 Markdown files,
2,803 local links/rules and zero errors; formatting and CI action policy pass.
Actual selected-runtime CPU inference, a fresh held-out 350-row comparison,
independent semantic review and the final quality/resource selection remain
open. No new real model weights or real inference were started for this working
checkpoint.
