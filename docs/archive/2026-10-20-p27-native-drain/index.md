# P27 native population completion correction

Historical implementation and verification record, 2026-10-20. This increment
continues from `93f71ad54216253da23bd1de4b5847b756515a3b`. Its immutable private
Linux verification snapshot is `5650d7fba8662e4935a3bc514363206810ae42d6`.
Current instructions are the [evaluation training chapter](../../developer/knowledge-evaluation.md)
and [native protocol](../../../native/README.md#optional-exact-aggregate-memory-scopes).
P27 acceptance remains in [the plan](../../plan.md#p27-optional-research-graph-and-rag).

## Problem and evidence

The stopped comparison's first cell had a zero-exiting leader and closed domain
work, but its native receipt was incomplete with `residual_descendants`. The
collector immediately killed a populated cgroup after leader reap. Neither its
service receipt nor later process disappearance established natural population
closure. The old comparison and peak remain incomplete and immutable.

Twenty fresh no-model ERTS exit/resolver probes and a metadata-only owned-daemon
probe did not reproduce that tail. A separately identified diagnostic collector
then observed two predeclared CPU requests in a fresh private service. Both
completed with final known usage: 112 input tokens, four output tokens, two
requests and zero unknown outcomes. Session, service, native and staging closure
were confirmed. This diagnostic measured no answer quality and supplied no
accepted comparison peak.

The diagnostic observed populated root/application scopes for 204 ms after
leader reap, with empty process/thread listings at each sample, then natural
population zero at 215 ms. It did not kill the residual population and still
reported incomplete. Its 22-sample trace was uncapped. The observed host was
Serenity with kernel `7.2.9-arch1-1`; these are provenance, not backend admission
requirements. The trace SHA256 is
`8b3436b3d589cd17501811a97b22569a4960ea232ed0dc1a21e2c86da10d6cf1`,
and its receipt SHA256 is
`a9e9ca241722eaeb51e66beb21656b7df0f1b2e58c3b21d5fcc3d789007bd699`.

Upstream [Linux 7.2 cgroup code](https://github.com/torvalds/linux/blob/v7.2/kernel/cgroup/cgroup.c)
hides exiting tasks from ordinary enumeration before final population removal.
Its [exit path](https://github.com/gregkh/linux/blob/v7.2.9/kernel/exit.c)
also performs memory teardown before cgroup exit work. That is compatible with
the observation, but does not identify the actual task or establish stale kernel
counters. Cache charges alone do not prove a populated task tree.

A controlled no-model regression reproduced the policy boundary: a zero-exiting
leader left its owned child waiting to allocate 128 MiB after release. The old
collector killed it first and retained an incomplete receipt at roughly 1 MiB.
A separate STOP/CONT control reproduced an existing deadline-ordering defect:
after the original one-second deadline, the old collector accepted a late
observed zero exit because reap handling disabled the subsequent timeout check.

## Selected prospective contract

The collector permits at most two seconds of natural population drain after
observed zero-exit leader reap, within the original workload deadline. This is
a fixed prospective scheduling policy, not a universal teardown bound inferred
from the 215 ms diagnostic. There is no host exception, configurable grace,
model-specific wait or change to service cleanup claims.

The native owner retains scope, authority and anchor through that tail. Owner,
anchor, authority and original-deadline checks remain active through the terminal
output decision. Nonzero exits, persistent population, lost guards and forced
cleanup remain incomplete. Population comes from retained `cgroup.events`,
never a process list or output EOF. Scope and parent-interval peak descriptors
cover the complete tail; the whole-run counter never resets at leader exit.

Final receipt version two adds the fixed `bounded_natural_drain_v1` policy,
2000 ms limit, observed drain/elapsed timing and natural/forced outcome. The
memory quantity remains `linux_memcg_charged_peak_bytes_v1`. New portable
declarations select `linux_cgroup_v2_v2` and bind the completion policy. Both
root and stage audit require matching version/policy/timings and the original
timeout. M/T framing and first-attempt ownership remain unchanged. Historical
declarations require their matching historical source/runtime; none is upgraded.

`leader-exited.json` records actual collector reap. Verification waits for that
barrier before releasing a delayed allocator or injecting post-reap loss. The
barrier grants no authority. Successful receipt checks validate policy, drain,
elapsed ordering and original timeout rather than trusting completion alone.

## Internal review and dispositions

Two independent design contexts compared timestamp and enum state shapes. A
separate cross-judge preferred the minimal timestamp design, 22/25 versus 21/25.
Root selected one leader-reap observation plus the existing stop/cleanup clock,
with explicit backend/declaration identity and microsecond timings. Small private
population-decision and active-guard functions own strict ordering and repeated
guard checks. No separate lifecycle framework was added.

Implementation review found two real issues, both corrected before final gates.
Consecutive population reads could accept cleanup without recording accepted
natural closure, yielding a success receipt later rejected by audit. One read
and its timestamp now govern closure, cleanup and terminal eligibility. The
other issue was a missing final ownership check after potentially slow reap-record
IO. The same guard sequence now runs again at the terminal decision; failure
enters irreversible cleanup and obtains a fresh population observation.

Both reviewers accepted these corrections with no remaining concrete runtime
finding in bounded follow-up. A README wording correction distinguishes draining
output from an active tail and the post-empty output-wait cutoff. Requested
reviewer configurations were `gpt-6-astra` and `gpt-6.1-sol` in independent
contexts. This records requested configurations, not certified backend diversity
or external/human review.

## Verification

The [source identity](source-identity.json) binds 447 source/config/test files,
with selection SHA256
`d01291297259413a5d6ded72660f0527b9318522b4df1ff168cd69dd208f6b06`.
Every selected current file was compared with the immutable Linux snapshot.
Markdown manuals and dated records were reviewed separately.

| Final-candidate check | Result |
| --- | --- |
| macOS source suite, stdio probe enabled | 1,306 passed, one skipped, 36 excluded, 797.7 seconds |
| macOS explicit native suite | 30 passed, six excluded, 25.0 seconds |
| Linux source suite with native enforcement | 1,345 passed, 19 excluded, 726.9 seconds |
| Native pure population/environment decisions | Two passed, 33 filtered |
| Real Linux no-model controls | Twelve drain, four terminal, ten scope and six sequence controls passed |
| Whole measured source and extracted-runtime proofs | Each completed all 350 synthetic rows, post-exit audit and resource checks |
| Audit-before-label controls in both runtimes | Ten refusals each passed, review CLI passed, unmeasured quality scoring refused; no new model work |
| Integrated authority-loss controls | Five passed, fresh attempts, cleanup confirmed and reentry refused |
| Build, formatting, strict compile, demo, packaging and base installed verification | Passed on macOS and Linux |
| Whole affected manuals, links and CI pin policy | Passed; final record/navigation link check run before commit |

The macOS archive SHA256 is
`a14eb186e3e89ee420bfa6693033e0361d221e6f8e5a96724b0aabf508bb772d`.
The Linux archive SHA256 is `be1d9df232277aeff65ff594f2e56a7a24069029254722e063a7a5c921d384c6`.
The source and installed proofs both report `execution_complete: true`,
`resource_complete: true` and `quality_complete: false`. Scripted model responses
and their synthetic peaks establish protocol behavior, not real model quality or
resource comparisons. The installed proof used a fresh extraction and a PATH
without the system development toolchain; source and archive remained unchanged.

The native matrix includes ordinary/detached/nested natural tails and allocation
after actual reap; persistent/nonzero/original-deadline failure; owner C/EOF;
anchor/collector loss; late observed zero exit; and bound-registry replacement
during a post-reap cell. A killed anchor produces the existing E diagnostic and
no terminal receipt. The test separately confirms the owned child disappeared.

Terminal controls use private diagnostic copies with a bounded barrier after
natural emptiness. The guarded copy refuses cancellation; deliberate reversal
of exactly the final guard accepts it. A separate delayed release refuses under
the original deadline. Production source stays unchanged, and these copies
cannot supply accepted experiment peaks.

An early control draft incorrectly expected an M failure receipt after anchor
SIGKILL. The retained run stopped on that assertion. The corrected test accepts
only the existing E failure and absent receipt, with separately observed cleanup;
the native protocol was not weakened to satisfy the test. Earlier eleven-control
passes preceded the final single-observation/terminal-guard fixes and are not
substituted for final-candidate verification.

The full evaluation training chapter and native protocol were read as whole
documents, then integrated with the policy, receipt interpretation and worked
controls. Corpus and Graph user manuals and audience indexes were reviewed.
The optional developer measurement backend changes no ordinary user workflow.
Documentation/link checks and the actual no-model commands verify the current
instructions. No dependency, grant, namespace or ordinary action/page ceiling
was changed.

## Remaining P27 work

This increment does not establish a complete real comparison, exact macOS
aggregate, device memory, independent semantic quality or a selected engine.
The interrupted 280/350 execution, unknown request and stopped 25-row execution
remain immutable. A fresh corrected CPU comparison must use a new declaration
and seal, preserve the original finite request/token allowances and report the
reused-set limitation. Complete post-exit audit, semantic review, quality/resource gates and
whole-milestone review remain required.

The earlier correction commit's hosted macOS job also reports two fixture waits:
a three-second resumed-question completion assertion and a sixty-second combined
CLI test. A separate fixture-budget candidate has passed its affected local
modules. It is outside this native unit, and the exact hosted slowdown cause
remains unproven. Local passing checks do not erase that red hosted evidence or
establish its cause.
