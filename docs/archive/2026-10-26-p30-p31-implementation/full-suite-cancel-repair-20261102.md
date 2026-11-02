# Complete source baseline after cancellation repair — 2026-11-02

Author-run verification of frozen
`9f1707cb33a7d9619c7a632dac83ae4ce313bc85` in an independently built clean clone.
This is a passing regression baseline for that source, not complete P30/P31,
installed/platform acceptance or an independent audit. The [plan](../../plan.md)
owns current status and [testing](../../developer/testing.md#run-the-complete-source-baseline)
owns the procedure.

## Actual terminal result

```sh
mix test --max-cases 1 --seed 791773
```

The parent command exited **0** after **7,456.0 seconds**: **3,753 passed,
zero failed, 118 skipped and 112 excluded**, with 3,983 declared cases.
The [machine receipt](full-suite-cancel-repair-20261102.json) retains the actual
terminal result and verified pre/post inventory identities. The parser requires
the final complete end-of-log parent summary, matching actual exit and parent
failure headings. It never adds nested subprocess summaries. Its minimum-count
guard rejects small child summaries; it is not an independent exact test census.

This fresh execution includes the
[protected-input cancellation repair](worker-input-cancel-20261102.md).
The [earlier complete failure](full-suite-20261102.md) remains preserved:
3,747 passed and one failed at `39c8043`. Its first failure is not erased or
converted by subtracting focused repairs. This passing execution has its own
source, actual exit, complete aggregate and unchanged-input proof.

## Frozen inputs

The checkout is `/tmp/ipse-p30-p31-fullsuite-20261102-cancel-repair`. It was cloned
without hard links and built separately; private staging directories were not
copied. `./dev/build.sh` and `MIX_ENV=test mix compile --warnings-as-errors`
completed successfully before the prelaunch freeze. No source edit or build
changed this checkout during the run. Native/Mix/PTY cohorts were serialized.

Prelaunch and post-terminal checks match:

- 7,893 tracked source files;
- 633 test-runtime BEAM/application files;
- 83 runtime private assets;
- exact source commit, clean tracked status and native helper bytes.

The helper SHA-256 is
`5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a`.
The raw log `/tmp/ipse-full-p30-p31-cancel-repair-20261102.log` has SHA-256
`a0ffc1f51038114f11dff3d27f1ecbb9ea913c66c5791002b32df4a797abae8e`.
The receipt binds original prelaunch/postcheck JSON hashes. The final inventory
check exited 0 before subsequent native work began.

These inventories bind paths/bytes, followed build symlinks and source/private
symlink text. They exclude complete system Elixir/ERTS/library closure,
environment, permissions/inodes, in-memory code and generated child artifacts.
They establish no complete machine isolation. Later private clock, pure Word and
workload-preflight development in the original checkout changed none of these
frozen inputs; their own source and checks remain separate.

The developer testing and operator recovery chapters were reviewed as whole
documents. Their verification, unknown-input and nonreplaying-recovery guidance
matches the scoped result; no product behavior is changed by this receipt.

## Remaining gates

Skipped/excluded cases are unexecuted by this aggregate. Separate native profiles,
installed packages, accounts, independent semantic quality, complete Word fidelity,
sustainable turnover and final adversarial review remain open. This source does
not contain the later Word-v15 or late-clock drafts. Those require their own
focused checks and a final-candidate baseline; this result cannot qualify them.
No inference allowance, provider, permission or publication authorization changes.
