# Full regression at 98267afd, 2026-11-06

This is a historical verification record for commit
`98267afd035ea8fadd3aa98e73bb0d11e2312672`. Current milestone status belongs
in [the plan](../../plan.md); this record does not establish results for later
commits.

The isolated copy's pre- and post-run checks reported the same commit, 514 test
files, 10,378 source paths, 1,522 runtime leaves, 314 SCM files and 133 Hex
files, with immutable-copy verification passing both times. The toolchain and
launch-input pre- and post-run pins matched. The test-created failure metadata
was absent before the run and present afterward; its post-run hash was recorded
by the copy verifier.

The default suite ran as `mix test --no-compile --no-deps-check --max-cases 2`
in the isolated test environment, with no additional exclusions. It exited zero
after 9,798.0 seconds: **4,294 passed, 136 skipped, 124 excluded**. The outer
result was independently checked as the final line of the private log; it was
not a nested test summary. The wrapper reported successful copy, launch-input
and toolchain postchecks.

After completion, the launcher, bounded owner and BEAM PIDs and the test process
group were absent. A scoped process check found no remaining suite processes;
the native Input lock and TCP port 39657 were free. The corresponding wrapper
postcheck witnesses were empty. The test had a 10,800-second coordination bound
and 30-second kill grace; no product deadline was changed.

The local evidence packet is
`_build/verification/graph-prefix-regression-candidate-20261106-01/run-01/`.
Its status, summary and private log SHA-256 values are respectively:

```text
e06e9331dd6239737e91b6bdba6dd457cb27d401c215df5684e8d2a0a6e933f7  status.txt
ceff61a146f83e006a26ef4d6af02a024f8d53256b00ac6e6ebe28af3dded0ce  outer-summary.txt
872c974fbaa1b26044d9478dfbcd75fa5ddb4cc0c7422d0e51256d430c95946b  raw-private.log
```

This fixture-based suite does not establish live account, paid inference,
browser sign-in, Arch installation or release verification. It did not access
the original notebook or run the declined 2,000-note recall check.
