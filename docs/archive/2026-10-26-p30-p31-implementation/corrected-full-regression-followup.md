# Corrected full regression on the unqualified host

2026-10-27. This is a failed regression on a fixed local source graph, not
platform qualification or a P30/P31 acceptance result. It follows the
[enhancement handoff](handoff-20261027-enhance.md) and corrects the earlier
run's temporary-workspace placement.

The command used the outside-repository private Btrfs temporary directory:
`TMPDIR=/var/tmp/ipse-enhance-tests.slGYaYCG mix test --seed 20270402
--max-cases 2`. It exited 2 after 1,350.0 seconds: 2,390 of 2,651 passed,
261 failed and 36 were excluded by the standard native/macOS/memory-scope tags.
The retained full output is
`_build/enhance-verification-52d8ac809e70/full-test-corrected.log`, SHA-256
`90936bbaf1376aae7aab590bed5450c8bf32b16f14b4aa65d7b31d7dcb990a81`.

The graph was reconstructed from `668e6a3` with the selected enhancement and
package-fixture work described in the [continuation handoff](handoff-20261027-terra.md).
Its private Git index tree was `2e6600e06ae118a431f52e2a70cf18dac57ed0ca`;
`git diff-files --quiet` succeeded after the run. The copied production helper
SHA-256 was `891758d90dd875a9e890b25c2eade1955a20bd59aa47fe05b5682e09bad991f5`.
This frozen graph does not contain the later managed-reference, inference-facts,
dispatch or P30 coverage changes. It excludes other dirty SDK/Mint/capacity
experiments; it is not a test of the whole current working tree.

The host remained `7.2.11-arch1-1`, outside the admitted production native
storage profile. Of the 261 top-level failing test blocks, 258 explicitly include
`*_filesystem_unsupported`, including nested fixture output. Two owner-loss
tests timed out waiting for their spawned owners after their `seed` calls had
already failed with `collection_filesystem_unsupported`; the worker stack traces
appear immediately before those test failure blocks. The remaining absent-root
observation reported the generic `collection_observation_refused`. A separate
synthetic absent-collection diagnostic on the same graph and temporary filesystem
returned `collection_filesystem_unsupported` from `Collection.open_view/2`, then
`collection_observation_refused` from `ObservedRead.read/3`. These observations
identify the first stopping condition for each failure; they cannot prove what the
tests would have done on a qualified platform. Some test bodies report a
positive journey as `NOT RUN` yet are counted as passes; they are not evidence
that those journeys worked.

The previous full run used a TMPDIR inside the outer repository and reported
2,335 of 2,645 passed, 310 failed, four skipped and 36 excluded. Its context
contamination prevents direct attribution of every difference to the temporary
directory. Both failed logs remain retained. Do not change the native profile,
weaken the tests, or replay retained storage effects to obtain a pass. A full
fixed-source run on a qualified host, the current changes, native positive paths,
separate platform and human journeys, and the requested adversarial audit remain
open. No release is authorized by these results.

## Later private-helper diagnostic

The later frozen graph `_build/current-full-corrected-KJqSdscV` included a
privately rebuilt helper that admits this host only for testing, and built its
inert Knowledge bundle before execution. Seed 46621 exited 0 after 2,007.7
seconds: 2,870 passed and 36 excluded. Its retained log SHA-256 is
`bc67aa509b610643c5cd35f986f386548ed45419fc5d6cea396cf44703ec9654`.
The graph and helper provenance are in the continuation handoff. This is a
synthetic diagnostic pass, not production-profile qualification, a human
journey, or a test of the subsequently changed DOCX and native-answer source.
The graph also omitted the tracked `bin/ipse` and `third_party/APACHE-2.0.txt`,
so it is not a full-source result. A later run (46653) was stopped after the
same omissions were found; its SIGTERM log has no test summary despite an exit
code of zero. See the handoff for the corrective run and its provenance.

The corrected complete-source graph `_build/current-complete-GyrZw9bd` then
passed 2,876 tests with 36 excluded (seed 46654, exit 0, 2,018.1 seconds),
and its private index still matched tracked source. The log SHA-256 is
`b952571585aa178f669b4cc4c657dc28416e9aadb505b9a12a1b727d74f0dece`.
It uses the private test-only kernel helper and predates the later historical
observation repair. The newer run covering that repair is recorded in the
[handoff](handoff-20261027-terra.md); neither result qualifies production
storage or unavailable platforms.
