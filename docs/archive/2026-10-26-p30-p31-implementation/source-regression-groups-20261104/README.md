# Completed nonoperator regression groups — 2026-11-04

The final static census has 473 default test files: 245 serial files and 228
nonoperator files divided into ordinary explicit Mix groups of 77/76/75.
The groups are disjoint and their union with serial is exact. No Mix partition
flag, failed/stale filter or include override was applied. This packet covers
only the three completed nonoperator groups; the serial group remains separate.

| Group | Files | Passed | Skipped | Excluded | Seconds |
| --- | ---: | ---: | ---: | ---: | ---: |
| Fresh UTF-8 parallel 1 | 77 | 609 | 2 | 0 | 1156.0 |
| Parallel 2 | 76 | 648 | 4 | 0 | 266.4 |
| Parallel 3 | 75 | 588 | 1 | 1 | 1211.2 |

All three test exits and every source/runtime/dependency/pathset/link/Git/Hex/
top-level identity postcheck are zero. Each has its own real source/CWD tree,
complete App/priv/dependencies, private Git index and Mix metadata, isolated
HOME/state and protected tmpfs. SDK/App/Bootstrap/helper preflight passed before
each exclusive claim. S2/A2 and max_cases 2 remain declared. The exact mutable
Mix failure-metadata file is separately recorded, not silently ignored as a
runtime payload. This is functional regression evidence, not memcg peak or
performance qualification. The installed-package and annual-workload gates are
not established here.

The first parallel-1 run used an environment that omitted UTF-8 locale and ended
with nine JSON warning-prefix failures plus one Unicode filename cleanup EEXIST.
Separate pure old/fixed controls reproduced both causes. That original log,
state and integrity-zero result remain preserved. The replacement uses exact
installed LC_ALL=C.utf8 and fresh copied source/state. No code, protocol, timeout
or permission change was made to obtain these passes. Original serial's same
setup failure and its independent retry remain separate evidence.

The common source inventory is retained once. Group manifests/test lists and
original absolute-path run pins provide provenance; their paths are not portable
archive commands. Public summaries are the outer Mix results only, without
double-counting subprocess ExUnit summaries. Raw private logs and complete
generated fixture state stay at their original task paths. No transcript or
provider body is copied into this packet.
