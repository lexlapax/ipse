# Saved-result release verifier — 2026-11-06

Historical author-run synthetic verification. The [plan](../../plan.md) owns
current milestone status and [testing](../../developer/testing.md) describes the
current procedure.

The Linux platform job in CI run `42246721917` failed the source saved-result
proof because its journal hash changed across an idle resume. That log did not
record the appended events. A separate fresh synthetic source diagnostic found
the original bytes and events unchanged, followed by exactly a new release-owner
marker and its matching release intent. The current signed release claim verified.
This is evidence for the diagnosis, not an observation of the earlier CI journal.

The verifier now retains the exact original journal prefix and accepts only a
validated owner/intent suffix and signed current claim for the Linux release
layout. A legacy journal must instead remain byte-identical; its result is
reported as `legacy_unchanged`, without claiming a signed release. Four focused
pure tests cover prefix and owner mismatches, unexpected records, invalid or
missing claims and reporting distinctions.

A fresh source verification passed using the current runtime. A separate
installed verification passed with the PDF-enabled Linux package built from
`4f7ed22d` (archive SHA-256
`6973211591988dabf526c9bfa2eb1b66d7b62b2e792ff69f65fe69054d5ed582`)
and the separately pinned verifier overlay. Both checked the complete 4,194,304
bytes and 1,024 fragments, exact historical reads, one worker load and callback,
zero model requests, idle resume and confirmed cleanup. Source, archive,
artifact and overlay checks passed; both process groups and the shared input
and test listener were clear afterward. No real model or account was used.

These controls establish the stated synthetic worker journey, not general
effect replay safety or the missing macOS package result. The earlier CI run
remains failed. Whole-source, platform and P30/P31 qualification remain open.
