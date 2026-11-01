# Complete clean-source regression result

Dated **2026-11-01**. Historical author verification of frozen commit
`f44b63cb8790b65a3bac21ae01ec02ebec234c77`, before the later root-prerequisite
fixture repair and accepted-approval draft. This is a failed baseline, not
milestone acceptance, installed qualification or an independent audit. Current
scope belongs to [the plan](../../plan.md); current verification procedures
belong to [the testing manual](../../developer/testing.md).

## Terminal result and source identity

The complete parent command was:

```sh
mix test --max-cases 1 --seed 791639
```

It exited **2** after **6,340.8 seconds**: **3,653/3,707 passed, 54 failed,
116 skipped, 112 excluded**. The [machine-readable receipt](full-suite-20261101.json)
retains all 54 numbered top-level failures, their source locations and the exact
parent summary. Nested subprocess summaries were not counted as the parent.
This terminal result supersedes earlier complete-suite totals as the latest
baseline for its exact revision; focused later passes cannot be subtracted from
its failure count.

The run used a separate local clone with independent Git metadata and build
outputs at `/tmp/ipse-p30p31-full-source-20261101-fdrped/repo`. Build, format,
strict compilation, CI policy and documentation checks passed before the test
command. The documentation check covered 1,011 Markdown files and 8,395 local
links with zero errors. Git status was clean before and after the test run;
the post-run reader also checked the exact HEAD and clean tracked/untracked
worktree. Development edits in the original checkout did not change this clone.
Native, PTY, Rust-terminal and other Mix/build cohorts were serialized behind
this run; only isolated pure/compile-only Elixir VMs and source/document work ran
alongside it.

The native helper SHA-256 is
`5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a`.
The reader inventoried 7,828 tracked source paths after completion, hashing
regular-file contents and symlink targets. Its inventory is retained at
`/tmp/ipse-full-source-f44b63c-inventory-20261101.json`; the receipt records its
hash. This is a **post-run source inventory**, not a prelaunch freeze or an
inventory of every loaded runtime/dependency object. Those distinctions remain
material to evidence scope.

The full raw log is
`/tmp/ipse-p30p31-full-source-20261101-fdrped/test.log`; its SHA-256 and the
terminal exit are recorded in the receipt. The collection script's first
attempt rejected its own failure-heading count: ExUnit pads one-digit and
two-digit numbers differently. That attempt wrote no receipt or inventory.
The corrected reader accepts only zero-to-two leading spaces, verifies the
consecutive 1–54 parent headings against the final aggregate, and rejects the
more deeply indented child failure. No test was rerun or reclassified to produce
the receipt.

## Repair direction and limits

The first failure is the canonical root-prerequisite fixture repaired separately
in `3f78205`; its [reproduction and pure checks](root-prerequisite-fixture-20261101.md)
do not qualify this earlier frozen source. Two Knowledge capture cases published
but failed to complete their turns. Their positive fixture used an unregistered
demo continuation; source inspection identifies the current managed-history
route guard as a relevant boundary. A registered-wire fixture repair remains
subject to actual runtime verification.

The remaining failures are in the managed Collection Session module. They
include subscriber-based approval waits, presently gated legacy publication,
unregistered managed continuations, competing pending writers, source/loss
controls and question interruption. This is a triage inventory, not proof that
all failures are stale fixtures. In particular, a timeout can hide an earlier
refusal, and both competing writers failed in the recorded positive race.
Each required positive and fault boundary must be reproduced and restored on
the intended public/native path; turning a positive expectation into a refusal
pass would not complete its requirement.

The available Linux kernel/tmpfs source checks establish no macOS, newer-kernel
Btrfs, reboot durability, paid account, human journey or model-quality result.
Full P30/P31 implementation, the passing combined source/package baseline,
adversarial post-implementation audit and reviewer handoff remain open.
