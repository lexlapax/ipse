# Saved-note shadow result — 2026-11-03

This synthetic component receipt records an experimental saved-note assessment
result. It does not qualify a decision strategy, a pending-candidate assessment,
a live engine, an installed package, human use, or the P30 milestone. The
[current plan](../../plan.md) owns remaining acceptance.

The `knowledge/decision-shadow` worker retains the assessment plan until the
separately approved decision call returns, then maps the validated decision result
to a bounded choice and reason. A low-probability answer or per-question refusal
returns a null choice. The output labels itself experimental and says the note
was not mutated; the decision call remains an effect and is reserved and charged
under the existing finite experiment policy. A managed extension result is
released through the existing dependency revalidation path.

Verification used an isolated snapshot of commit
`03d2f01d3dfd459f2b53e1b7802f22c80f803619`, with the four source/test files
below overlaid, copied dependencies, a separate build and isolated synthetic
homes. The snapshot excluded duplicate archive material. All model and decision
service requests used synthetic loopback fixtures; no paid call was made.

- Focused format check on the four Elixir source/test files: passed.
- `IPSE_BUILD_COMMIT=03d2f01d3dfd459f2b53e1b7802f22c80f803619 ./dev/build.sh`: passed with loopback access. The first sandboxed build was refused before compilation because Mix could not acquire its TCP filesystem lock (`:eperm`); its log remains in `/tmp`.
- `mix test test/extensions/knowledge/knowledge_capture_test.exs --max-cases 1 --seed 797131`: passed one outer test, including the nested Knowledge capture controls.
- `mix test test/extensions/knowledge/shadow_experiment_session_test.exs --max-cases 1 --seed 797132`: six passed in 123.1 seconds. The selected and low-probability cases checked the tool response, one settled decision call, unchanged collection snapshot, strict journal reconstruction and reopening the same Session idle without another provider request. Other cases covered denial, revoked grant and the two existing decision preflight/result-admission expiry interpositions.
- `MIX_ENV=test mix compile --warnings-as-errors`: passed in the snapshot.
- `elixir dev/check-docs.exs`: the initial main-tree pass checked 1,094 Markdown files and 9,030 local links and emitted permission warnings for unrelated private ledger directories. A later git-backed sanitized mirror check including the final receipt and manual edits passed 1,095 Markdown files and 9,034 links with zero errors.

The existing expiry control interposes at decision-result admission. The six-test
batch did not test withdrawal between decision completion and final output release.
After that batch, a separate test-only interposition blocked the actual assessed
inline result at `managed_output_prepare`, temporarily moved its original
synthetic source journal, and kept it unavailable through the release and turn.
The focused case passed once (seed `797133`, one passed and six excluded, 13.6
seconds): one decision call settled, the bound output release was marked
`withdrawn`, no recorded main-provider request contained the assessed result, and
the original source returned with the same inode and hash. Strict reconstruction
and a same-ID idle reopen did not cause another provider request. This is a
synthetic source-loss control, not a claim about every ownership or failure
boundary. The new saved-note result does not assess a pending proposal.

After the fixture change, the complete `shadow_experiment_session_test.exs` suite
was rerun against that exact final fixture: **seven passed**, seed `797134`, in
137.2 seconds. The runtime and all three test-file hashes listed for that final
fixture matched before and after the run.

The four tested overlay files and SHA-256 hashes were:

```text
b0e7911e55c21083bb7ea8efea39d356e6b692f60d1a8e755b588be95264bda7  extensions/knowledge/src/knowledge.ex
caa426b4708e6700337d8c685d64bbb4eee676ba7651fa4a6b6261010d6f7bb2  test/extensions/knowledge/knowledge_capture_test.exs
1e239f19020e2ccf20d9c037b4eb9497f974b8d720873edca88a71d99f1cf416  test/extensions/knowledge/shadow_experiment_session_test.exs
22dd0ff1054b39edd1efbcf2a60fa4dfb341633aa7c2563abc4f0d6b6607a66d  test/support/shadow_experiment_cli.exs
```

For the later withdrawal case, the runtime and capture-test hashes remained the
same; the two changed fixture files had these hashes:

```text
dd6057d2623d12316bf2898fba44177d7f30ef78b25c69e58c20d7f4b955322c  test/extensions/knowledge/shadow_experiment_session_test.exs
8760574760c6aa47c64a819d2a5d01d6a3e653dc13df7e3ae60aa1703c22707f  test/support/shadow_experiment_cli.exs
```

Synthetic logs remain outside the repository in `/tmp`:

```text
a3f29c3c7177e68cf06c8a8fc3064fd879e53229313fb2bac225ba095747263e  /tmp/ipse-saved-shadow-build.log
2bf603895a9b218dd048f71a56a3c7881c264bd5eb151fc151bbdc1a657e93e5  /tmp/ipse-saved-shadow-build-loopback.log
71773c941527223994f59a8ccc4592d059b769bd54e03c7d96bf32c5fc4e0c4f  /tmp/ipse-saved-shadow-capture.log
d217abf5122f81e7316cb1a785eee159a997ed8790344c0eb12e7f42f179216f  /tmp/ipse-saved-shadow-native.log
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  /tmp/ipse-saved-shadow-compile.log
34cac12283498b1a7968cf3ff8c500f26cf6a2d78f052eec3fa1c2a4379b4a5a  /tmp/ipse-saved-shadow-docs.log
a2292fd615f35545a01441775498effb7545b99684857bda24a828f3978d7fb2  /tmp/ipse-saved-shadow-output-withdrawal.log
360637dcd214b87ac6d5e6a182520107fc9059beb69e368f37e8fea7db6c1e14  /tmp/ipse-saved-shadow-native-final.log
```
