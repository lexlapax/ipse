# Independent native knowledge CLI audit

Dated **2026-10-26**. Historical independent evidence, copied verbatim from
`p31-verification/independent-knowledge-cli/knowledge-cli-audit-2026-10-26.txt`.
Original report SHA256: `a2306504f278d220c169f33cc621f36236d6658b9d699c569e1d0d1e21fd7c14`.

This original audit records the accepted saved-configuration finding at frozen07. Its [repair](native-knowledge-cli-config-repair.md) and [independent closure](native-knowledge-cli-config-audit.md) supersede that open disposition. Current procedures belong to the [operator guide](../../operator/knowledge-permissions.md).

```text
Independent standalone knowledge CLI audit — frozen07 — 2026-10-26

Disposition
One confirmed P2 accepted by the parent: saved configuration is not re-resolved
at publication after a paused native review. A saved file change can produce a
successful grant for the old displayed route that is unusable under the new saved
configuration. Later readiness correctly refuses. This is a narrow configuration
recheck/usability defect; no new-route authority widening was observed. Root is
repairing separately in frozen08. No product fixes were authored by this auditor.
This report evaluates07 only and is not final milestone approval.

Freeze and bindings
Supplied graph /tmp/ipse-knowledge-cli-20261026-07/{project,build} was copied before
execution to /tmp/ipse-independent-knowledge-cli-VNDpoMjq. All724 rows (including dependency ebin, installed bundles,
source and both helper copies) match their supplied byte counts and hashes.
Author JSON manifest SHA256:
081c43ff603ea8a5e30d0fa956d706e02be27c7a97bac56af93445b7c67e44c7
Independent relative724-path before/after lists are byte-identical, SHA256:
7df99106eb64a24e3fe38c950c1442fd8bf5a2ae9e492363484aed066569b891
Knowledge source SHA256:
778bfa7a48fcf21e7f4d85b0973ecc722c932eab444822e5c8515e922fb728e0
Transaction source SHA256:
8c769af647054df7d5cf3d468ed3dfd4666d3130d84d9855e6b77195272ea3ef
Both helper SHA256:
6f431b5aedde35ecb6f8737e7714dbd197df83c7e8d52e909243e0a39152a55d
All execution used absolute private ebin paths from private PROJECT cwd so child
Application.app_dir selected helper6f. Shared108c was not modified or rebuilt.
Copied runtime has the already broken telemetry/src development link omitted and
its unused shared project/deps link removed. Bound runtime files all verified.
Full supplied public project/runtime files and exact helpers are preserved here.
The supplied graph contains the transaction native source; the executable helper
is bound by its exact binary hash. Supplementary shared native operator source was
read for environment diagnosis only, not asserted to be a bound helper preimage.

Read scope
Read AGENTS.md, CLI.Knowledge, CLI parsing/dispatch/help, Runner.Operator, relevant
Identity/Consent/activation boundaries, CLI tests, knowledge_setup and operator_pty
support, and the public knowledge-permissions manual. Its separately retained
snapshot hash is3795385a7d4ca47d9b8da1eeb002e6821dacfaf095a070f97864920a6fdac023;
that manual was not part of the724-row freeze. This review checked source/display
binding, fresh challenge comparison, repeated installed artifact/policy checks,
CAS, option refusal, status nonrepair and ordinary approval separation.

P2: cached configuration survives a saved-config change during review
Source lib/ipse/cli/knowledge.ex:124 prepares the displayed proposal. After native
confirmation, lines128-130 call prepare again with the SAME cached runtime config.
No Config.resolve/runtime reconstruction occurs at publication. Exact artifact,
proposal and epoch checks therefore do not detect a saved config file change.

Minimal independent actual-native reproduction:
1. Fresh private home has config.json selecting provider demo/model scripted;
   empty ordinary workspace. Use CLI knowledge enable with --config and
   --no-project-config. The real helper validates matching native input/display.
2. Own Rust PTY driver answers the displayed folder challenge. It waits until the
   complete policy and fresh enable challenge have reached native output.
3. Child watcher changes only the saved model to changed-during-review, preserving
   the valid config file, then signals the PTY driver to answer the correct code.
4. Enable returns0 and prints saved permission. Existing protected policy still
   names demo://local model scripted. Status under the now-current saved config
   returns1, correctly refusing the mismatch.

Exact source of the unchanged before probe, original-config-before-repro.exs:
6ed7626c758459db5f3520fbcc0692188de6169ca7bb2a9fb510fd0714e5a17e
Native driver used by the clean original config receipt, pty-driver-v1:
76b8994492661d0dc5704d103aa1d9b86199b47fa6a79f4b9e0c838b9dcff303
Its Rust source pty-driver-v1.rs:
62c8cfe6243ff1cfa575c5fecfefe9b9cb0fc325f9e7106a3e124c9643594059
Receipt logs-native/config.log shows CLI_RESULT config0, original scripted route,
then status refusal. The synthetic changed config and protected bytes are retained
under cases-native/config. Parent explicitly accepted P2 as current saved-config
recheck/usability contract gap, with no widened/new-route authority claim.

Other independent actual controls observed
Thirteen native/pipe scenario classes were exercised: twelve defensive controls
passed, plus the positive vulnerability/config receipt above. These are fresh
independent drivers, not reruns of the author's suite:
- Correct full native enable followed by native disable succeeds.
- Installed declared operator.json mutation while review is paused refuses grant.
- Selected Identity index JSON mutation while paused refuses grant.
- Legitimate Consent.revoke during review advances epoch; old grant CAS refuses
  and newer state remains selected with no permission overwritten.
- Bare yes cancellation, incorrect challenge, cross-action code reuse, and a valid
  enable code replayed at a SECOND fresh enable challenge refuse. Existing policy
  remains until an explicit subsequent correct disable. Full second enable display
  and code are visible in logs-native/replay.log.
- Actual input and output on different PTYs, and plain pipes, refuse before project
  admission. No native input or stdout observation was fabricated.
- Actual original native input helper process was found among the owned Erlang
  child-setup descendants by its --operator-input/v2 command identity and SIGKILLed
  while the complete review was paused. The returned result refuses, no policy is
  saved, and later native use succeeds. PID receipt and result are retained in
  logs-native/ownerloss-extra.log. No synthetic helper exit was substituted.
- New headless Session after a real native grant uses only an in-process provider
  fixture. A source-bound unattended capture succeeds with saved_consent and
  never_current/pending normalization. A simultaneous ordinary write is recorded
  denied; its target file remains absent. Session closes, native disable revokes.
  Receipt logs-native/headless-final.log and synthetic own Session journal retained.

Read-only CLI controls:3/3 passed, seed601081, serialized.
Status readiness and permissions inspect exact active policy while preserving both
Identity and Control staged invalid JSON and recursive byte/inode/mode/link/time
inventory. Missing writer at either owner causes status/permissions refusal with
no recreation. Piped disable and unsupported yes/no-yes/provider/model/extensions/
subagents options cannot change the grant. Status in an unadmitted sibling yields
no membership and leaves existing state unchanged. This uses an isolated active
grant from the cancelled cross-action disable fixture, with explicit cleanup of
only audit-created staging and restored audit-renamed writers.

Execution conditions and honest failures
Elixir1.20.4/OTP29 on Linux. No actual provider or network call. The first sandbox
attempt could not exercise native input because sandbox /tmp ownership appears
65534 while helper requires a root-owned sticky /tmp. Authorized escalated commands
then used the real boundary; no helper protection or /tmp metadata was weakened.
That environment-only orchestrator initially overlapped the first rerun and was
stopped by its exact PID. Those mixed initial logs/cases are NOT counted as proof.
Clean logs-native runs used distinct roots. Later final replay may have overlapped
Root's final test window briefly; both passed, but exclusive access is not claimed.

Preserved audit setup errors: initial artifact lookup failed to filter the retained
.import lock from digest entries; initial native-PID search missed erl_child_setup
descendants; initial headless receipt check searched tool_result instead of actual
message records; readonly driver had a keyword-list syntax error. Each was corrected
in audit scripts only and final controls above passed. Initial scripts/logs are
retained and distinguished from product findings. Old source/runtime graphs and
original before driver remain untouched for repair closure.

Durable replay and limits
Owner-only evidence contains provided full graph, exact dependency/app BEAMs,
helpers and bundles, relative before/after manifests, author's JSON, full scripts,
Rust driver source/binaries and logs/synthetic case receipts. replay/run.sh copies
the graph into a fresh temp root, executes only there from project cwd and uses
serial native cases. It requires the actual root-owned /tmp native environment;
run outside the UID-remapped sandbox. Nothing executes against durable evidence.

No credentials, user config, private transcripts, qualification inputs, gold data,
model service, live endpoint, production/repository/index/shared build or helper
mutation occurred. Own synthetic Session records are explicitly test fixtures.
No full suite, alternate OS, exhaustive native loss/cancellation schedule or new
framing proof is claimed. Operator consent/current state remain advisory outside
later effect checks. This is incremental UI/component audit only; frozen08 repair
closure and final whole-implementation/milestone audit remain outstanding.
```
