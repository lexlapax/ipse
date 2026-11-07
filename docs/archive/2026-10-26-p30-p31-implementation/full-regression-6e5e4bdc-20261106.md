# Full regression at 6e5e4bdc, 2026-11-06

This historical verification record covers commit
`6e5e4bdc4210923d686563e9283c7d14fb108d5b`. Current milestone status belongs
in [the plan](../../plan.md). The earlier independent full-suite result is
recorded at [98267afd](full-regression-98267afd-20261106.md); neither result
establishes results for later changes.

The isolated, offline-built Linux x86_64 runtime identified that exact commit,
Elixir 1.20.4 and OTP 29.1.1. The test command was
`mix test --no-compile --no-deps-check --max-cases 2`, with no additional
exclusions. It completed with exit zero in 9,993.5 seconds: **4,313 passed,
136 skipped and 124 excluded**. The summary was the final outer suite result;
the recorded Mix failure metadata encoded an empty failure map. The default
test helper excludes native sandbox, macOS sandbox and filesystem, memory
scope, workspace word native, and controlled terminal bridge and loss tags.
Other skips and exclusions are reflected in the totals, not counted as passes.

The pre- and post-run copy guards passed for the same commit and a census of
517 tracked test files, 10,414 source paths, 1,522 runtime leaves, 918 SCM
files and 133 Hex archive files. The two recorded test-file lists have identical
SHA-256 `a89e00ae0c862c17866732133e07d6c11681999d310417fe86d20fe997eb11db`.
The runtime, source and SCM seals, launch-input checks and pre/post toolchain
inventories matched. The original main worktree was not frozen by this packet.
The wrapper used a 10,800-second coordination bound and 30-second kill grace;
it did not change product deadlines.

The wrapper's postchecks found no holder of the native Input lock or TCP port
39657, no matching suite process and no member of the recorded process group.
A later read-only host check likewise found that group absent and the lock and
port free. The private temporary root remains present; these checks establish
process and lock cleanup, not removal of its retained synthetic artifacts.

The local packet is
`_build/verification/p31-final-regression-6e5e4bdc-20261106-01/run-01/`.
Its status, outer summary and private log SHA-256 values are respectively:

```text
a64bb98b4e9d67279f1e76b2ba22b3140710aebd2e963b1bc5df2e69ee830077  status.txt
86922db0668693f9244aa43cdf607b98f9576668d360109dc1c0059c6507b097  outer-summary.txt
ad945b4b0b20fdf6cb9b6a1277bdc6aa1f13a93a271f9dba7bcde8b25ca60c49  raw-private.log
```

This fixture-based local run does not establish the excluded cases, hosted CI,
live accounts, paid inference, browser sign-in, Arch installation or release
verification. It did not run the declined retained-notebook recall check.
