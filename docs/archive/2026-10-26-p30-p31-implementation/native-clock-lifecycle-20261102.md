# Actual native lifecycle across process-clock restarts

Dated **2026-11-02**. Author-run synthetic component verification launched from
`cd7a438` plus the fixture sources in the [receipt](native-clock-lifecycle-20261102.json).
The post-run inventory uses later documentation-only `d52764b`; production
runtime source is unchanged from `39c8043` across both revisions.
Current procedures belong to [testing](../../developer/testing.md#require-positive-controls-and-inspect-uncertainty);
milestone acceptance belongs to [the plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance).

## Executed path

```sh
mix test test/dev/knowledge/managed_clock_lifecycle_test.exs --max-cases 1 --seed 791762
```

The command exited **0**: **one passed**, 17.0 seconds. The preceding full-source
run had already exited and its inventories matched before this native cohort
started. Its separately retained cancellation failure remains open.
The unchanged default `current` supersession fixture then passed separately:
one test, 12 excluded, 9.6 seconds, seed `791764`, terminal exit 0. Global format
checking passed. Documentation checking covered 1,037 Markdown files and 8,588
local links with zero errors; Git enumeration warnings for private staging
directories do not establish their inspection or validation. These are separate
checks, not a replacement whole-suite aggregate.

The seed invokes the existing genuine Session correction/supersession fixture,
including native statement/category and relation review, real publication,
confirmed close, strict reconstruction and idle resume. The optional follow-up
saves expected fixture data and the original journal hash only after those checks.
Serialized expected data supplies no native review, domain key or authority.

Each subsequent child uses the existing test-only clock preload at a fixed
startup offset. The parent waits for its actual zero exit before the next step.
Native helper bytes and production admission remain unchanged; no runner-path
override is accepted. All homes, storage, input and journals are synthetic.

| Simulated day | Actual observations | Generation |
| --- | --- | --- |
| 30 | Ordinary and temporal-history expiry refuse before their signed deadlines. A fresh public native pin review stores a signed confirmation inside that operation's observed start/finish interval. The original public successor bytes remain unchanged | 4 → 5 |
| 91 | Public expiry reclaims both ordinary successor and ordinary historical predecessor after their original deadline; temporal history remains eligible and the pinned successor remains stored | 5 → 7 |
| 366 | Public expiry reclaims elapsed temporal history; the pinned successor remains unchanged, despite the original capture permission's year having elapsed | 7 → 8 |

All successful operations are settled. Repeated read-only operation inspection
returns the same status without modifying its journal or replaying effects.
The original Session journal stays byte-identical across all three checkpoints;
Saved reconstruction and its signed release claim still validate. No new Session
or model is started by the management checkpoints. Cross-day inspection is not
a cross-day active Session resume; the seed's actual idle resume occurs at day 0.

The source journal SHA-256 is
`fdd44883a79bdf6b25ee9c3cfafcfdd1d6f6175fd18c08f17c1b402d4f09404e`.
The retained synthetic root is
`/tmp/ipse-native-clock-6ecd6581d00a7b5aae75108ecd070f90`.
Its four process logs, seed manifest and three phase reports are hashed in the
receipt, along with source inputs, the unchanged native helper and test-reported
clock-library/PTY-driver bytes. This is a post-run component inventory, not a
complete prelaunch loaded-library/environment/permission/in-memory freeze.

## Scope and remaining work

The [plain VM/Rust clock proof](process-clock-20261102.md) alone established
process-clock coherence. This component additionally reaches the genuine native
review and storage path at those process dates. It does not simulate an elapsed
real year or alter the kernel's file timestamps. Review timestamps are compared
with actual operation bounds, without inventing a tighter phase-level latency
requirement; production permit deadlines retain their own enforcement.

Required daily intake, initial 200 persistent notes, 2,000-active capacity,
two overlapping OS owners, the offline week, imports/floors, first temporal
supersession after day 90, 10,000 additional cycles, history/suppression compaction,
representative/maximum payloads and resource accounting remain open. The reports
explicitly set annual-workload qualification false. There is no installed,
human, other-platform, older-toolchain, model-quality or independent-audit claim.
