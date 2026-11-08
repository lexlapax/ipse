# Synthetic consent workload and Collection close controls

Recorded development evidence, 2026-11-07. This is a bounded record for review,
not a milestone acceptance or a claim about live accounts, installed artifacts,
or the final integrated source. The earlier full-source regression on local
snapshot `2337e1bae486157d30096ab39c85b0e07de4ece7` exited 2 with 11 failure
headers: a large consent workload timed out, nine Word Session fixture cases
failed setup, and one CollectionStore uncertainty case reported an unconfirmed
close. The new diagnostics do not change that result.

## Large synthetic consent workload

A separately prepared focused candidate used the current root consent
optimization and a copy of the original 25,000-row, 65-publication workload.
The copy changed fixture teardown only, retaining its new synthetic root; the
180-second ExUnit timeout and assertions stayed unchanged. Native build,
warnings-as-errors compile and the selected test exited zero: **1 passed,
8 excluded in 165.6 seconds**. This is a focused run on that source, not an
unchanged rerun of the failed regression. Its margin below the timeout was
14.4 seconds, so it does not establish reliable full-suite timing under other
load or prove the earlier timeout's cause.

Independent inspection found matching baseline source/runtime/toolchain
inventories before and after, matching candidate input nodes, and no observed
members of the three recorded process groups, open scratch files, scratch or
shared input-lock holders, or listeners at the two recorded Mix ports. The
retained synthetic control state had 64 live operations and 25,002 compacted
entries, all recorded as settled, with policy removed. This observation does not
settle effects outside the inspected fixture or establish that every detached
process stopped. Its scratch, synthetic control root, operator home and original
lock inodes remain preserved.

Evidence: `_build/verification/consent-perf-focused-v2-20261107-01/materializer-01/`.
The enabled launcher SHA-256 is
`d9cea484d2c1d25ee58e46c33c04a705fe637680c4e8766569f87ef321fd8789`;
the private test log SHA-256 is
`b8f074766c904fea5b9e7371545e6f4da20efa83f4b5f51628e027f56739ab4d`.
Private logs and synthetic records are not release artifacts.

## Collection close controls

In the failed regression, the synthetic test recorded its interrupted
`value.append` as unknown, observed no `value.seal` result, then received
`cleanup_unconfirmed` from `Session.close_confirmed/1`. The log does not
identify the failing cleanup boundary. The fixture's teardown could remove its
random root; absence of that root cannot settle the earlier action. A separate
fresh diagnostic passed only after its Session was already down and skipped the
conditional close; it did not reproduce the failure. Its unknown append and
original lock inodes remain preserved.

A later v3 test-only diagnostic used a fresh retained synthetic fixture, an
explicit close tracker and three controls. They forced a previously observed
alive check to be followed by a separately confirmed close before the delayed
close call; exercised a completed synthetic document turn and confirmed close;
and injected the existing sticky cleanup-failure state to require an unconfirmed
close and refuse a further close dispatch. Native build, strict compile and the
three controls exited zero: **3 passed, 8 excluded in 2.5 seconds**. The
injected condition is not a native cleanup failure, and the forced race does not
prove it caused the historical result.

The independent v3 audit checked matching recorded source/runtime/toolchain
inventories, no observed members of the three process groups, no open scratch
files or observed scratch/shared input-lock holders, and closed recorded Mix
ports. Among three retained Session journals, one contained 18 matched action
intent/result pairs, all `ok`; two had no action pairs. Invocation and worker
input IDs matched in each journal. Two release receipts verified against their
intents; the third journal had no release intent or receipt, so its cleanup is
not inferred. No named pending file was found, which does not establish absence
of all possible uncertainty. All roots, shared artifact and original locks
remain intact.

Independent audit:
`_build/verification/collection-close-race-design-v2-20261107-01/INDEPENDENT-AUDIT-v3.md`,
SHA-256 `5ab3523544310ccd75d39528822809e17dfc5ea0da50109a6ed595f8ab8b07df`.
The enabled launcher SHA-256 is
`bce3cf747faf5eff9246e1974b25b247fd6f333aa898c61398d1ad673680d357`;
the private diagnostic log SHA-256 is
`678f778ba2d4647589dca5b1732df83a44aa84d32e9b45fb5b57db2a12ab3cda`.
Neither diagnostic accessed the declined populated notebook or ran its recall
check. Final integrated verification, unresolved fixture disposition and
adversarial milestone review remain open.
