# Independent knowledge CLI configuration repair closure

Dated **2026-10-26**. Historical independent evidence, copied verbatim from
`p31-verification/independent-knowledge-cli-repair/knowledge-cli-repair-audit-2026-10-26.txt`.
Original report SHA256: `eb88d00d95f00f5b6920633518aeded62367bcb51eb25f99584a6767eb767b2e`.

This incremental audit closes the frozen07 finding at frozen08. The [repair record](native-knowledge-cli-config-repair.md) explains the implementation. It is not final milestone acceptance; the [plan](../../plan.md) owns remaining work.

```text
Independent standalone knowledge CLI saved-configuration repair closure
2026-10-26 — frozen08

Disposition
The accepted frozen07 P2 is closed at the exact tested frozen08 bytes. The unchanged
original native reproduction no longer saves the stale route: enable refuses with
knowledge_configuration_changed, no durable control.json is created, and status
correctly reports no ready selection. No new actionable issue was found in the
focused repair scope. This closes the narrow saved-configuration recheck/usability
finding; no widened/new-route authority had been observed in the original defect.
This is component closure, not final whole-implementation/milestone approval.

Exact freeze and runtime bindings
Complete supplied /tmp/ipse-knowledge-cli-20261026-08/{project,build} copied before
execution into /tmp/ipse-independent-knowledge-cli08-KVakUhtG. All724 source/app/dependency ebin/bundle/helper rows match
the final author JSON, SHA256:
07757d94fe5374bf63ceeabc40f08288047ae46c46d1ff9dfcf2c737b324f7e9
Independent relative before/after724-path byte lists are identical, SHA256:
a4bb746d23410c9fe7d4b2b78878076b96268af04fccde1a5ef2c0c190542ddb
Knowledge source SHA256:
86a0bba1db6f065349a0dbfc8e9d97f6a73b0452669ec8fe06ee3439c7ed895c
Transaction source SHA256:
8c769af647054df7d5cf3d468ed3dfd4666d3130d84d9855e6b77195272ea3ef
Both retained helper copies SHA256:
6f431b5aedde35ecb6f8737e7714dbd197df83c7e8d52e909243e0a39152a55d
No shared108c helper/build, repository or production edits. No Ipse/helper rebuild.
Only unused shared deps link removed in own project copy; the known broken
telemetry/src development link is absent, while every bound runtime file matches.
Execution from private PROJECT cwd with absolute private ebin paths avoids fallback
to any shared helper. Linux/Elixir1.20.4/OTP29. Native controls run outside the sandbox
UID-remapped /tmp boundary, using the real matching terminal and helper6f.

Reviewed repair
Read actual07-to08 Knowledge diff and the four-file repair context. The callback
created in run captures the original opts/home/cwd. Inside retained Identity, source
lib/ipse/cli/knowledge.ex:133-136 refreshes runtime, checks ordinary configuration
fingerprint at161-166, then rebuilds the full proposal from that CURRENT runtime.
Only an exactly matching full proposal proceeds to original-epoch Consent.replace.
Changed configuration returns fixed cause and fixed operator guidance. No artifact,
route, project identity, epoch or quota check was removed. Disable/read-only flows
are outside the narrow implementation change; their prior07 evidence is preserved.

Unchanged before reproduction, independently rerun
original-config-before-repro.exs SHA256:
6ed7626c758459db5f3520fbcc0692188de6169ca7bb2a9fb510fd0714e5a17e
Unchanged Rust native driver binary pty-driver-v1 SHA256:
76b8994492661d0dc5704d103aa1d9b86199b47fa6a79f4b9e0c838b9dcff303
Its unchanged source SHA256:
62c8cfe6243ff1cfa575c5fecfefe9b9cb0fc325f9e7106a3e124c9643594059

The child starts demo/scripted from a private config, receives actual folder scope
and full native policy review, changes saved model while the displayed enable code
is paused, and then answers the exact current code. Against08 it prints fixed changed-
configuration refusal; CLI_RESULT config1 and CONFIG_CHANGED_DURING_REVIEW {1,nil}.
Status prints no ready selection and returns0. Therefore unchanged old probe exits1
at its original status==1 assertion. This is expected exploit-condition failure,
not a product test failure or a claim that the old driver passes.

The corrected preservation variant changes only that expected result block. It
asserts refused enable, nil existing snapshot, absent control.json, and successful
status reporting no ready selection. It passes against a separate private root.
SHA25671902a93e8e9733cff03e33510d2f34699c148620a52e931d8d4bb01c1efe4b2.

Six additional fresh native controls, all pass
Each pauses at the complete reviewed enable challenge and mutates only synthetic
configuration state. All verify final exit, durable state and changed-file bytes:
1. Equivalent JSON settings re-encoded with formatting/newline: refuses, no durable
   control.json. Confirms source-byte fingerprint recheck rather than settings-only.
2. Retarget the original config path to a same-bytes private equivalent file via
   symlink: refuses, preserves symlink and bytes, no durable control.json. Canonical
   source identity remains part of the ordinary configuration fingerprint.
3. Change only IPSE_MODEL in the isolated child environment: refuses and creates no
   durable control.json. Re-resolve uses current environment with original options.
4. Atomically rename a new0600 file of IDENTICAL bytes onto the same config path:
   permits exact reviewed policy at epoch1. This avoids an unintended inode-only
   requirement on ordinary configuration sources.
5. Add actual .ipse/config.json selecting another model while original command has
   --no-project-config: permits the unchanged reviewed policy. Original option
   authority is preserved; the new disabled project file is not silently adopted.
6. Edit saved model, then restore the original exact bytes before confirmation:
   permits exact reviewed policy. The check attests current state, not edit history.

Negative receipts confirm nil existing snapshot/no control.json. Positive receipts
have epoch1, policy present and no operations. All changed files remain exactly as
the test mutation left them, and symlink retarget remains a symlink. These are fresh
independent controls, not copies/reruns of the author's four mutation scenarios.

Preserved harness correction
Initial preservation and negative assertions expected an epoch0 map from the new
existing_snapshot API. Actual absence correctly returns nil because the refused
initial grant never creates durable control.json; ordinary before-review snapshot
can provide an in-memory empty epoch0 without persisting it. Assertions were
corrected to require nil plus absent control.json, then rerun successfully. Initial
scripts/logs are preserved and are not product findings. Original exploit script
was never modified. Positive3 controls passed on their first run; no broad repeat.

Evidence and replay
Separate durable independent-knowledge-cli contains full07 before report, positive
exploit receipt, exact before graph and original Rust/Elixir sources. This directory
independent-knowledge-cli-repair preserves the08 graph, all724 bindings, before/after
manifests, exact old drivers, corrected/fresh drivers, logs and synthetic receipts.
Relative MANIFEST.sha256 binds the complete payload; directories0700, data0600,
executables0700. replay/run.sh copies all runtime/project files to a new private temp
root and executes from project cwd. It expects original exploit exit1, then runs the
corrected preservation and six native controls. No durable runtime is executed or
mutated. The replay runner is supplied and syntax-checked; the individually recorded
commands above are the actual executed controls, not an additional full replay run.

Limits
No live provider/model/network call, credentials, user configuration, qualification
input/gold/private transcript or shared/repository/index/helper mutation. Synthetic
configs, reviewed policies and native terminal logs are intentionally retained.
No full suite, alternate platform, exhaustive configuration/consent race schedule,
or publication-after-IO unknown-outcome fault injection was run. Same-UID changes
after the final refresh remain subject to later admission/effect checks; this is
not an atomic filesystem freeze of future operator configuration. Native helper
binary is exact-bound; source graph is the supplied graph, not a claim of complete
native build-preimage provenance. Prior07 controls of owner death, artifact/CAS,
read-only state, fresh-code replay and actual headless approval separation remain
separate evidence. No whole-milestone acceptance claim is made.
```
