# Combined source regression — 2026-11-04

This historical verification record preserves a failed integration run. The
[plan](../../plan.md) owns current acceptance; the
[testing chapter](../../developer/testing.md) owns verification procedures.
It is not milestone or release acceptance.

## Frozen run and result

One complete source suite ran against the combined chat, expiry, reoffer and
planning implementation at parent `d3dab913c96fcf4455120470b6a157bebe4547e8`.
The uncommitted product/test patch was
`5fda38ab5c506c83df6124430deb206d82bcf420e4b131edcae3d5e72b026260`.
All 197 source modules, the native helper and four shipped bundles built before
the run. The launcher used a fresh private tmpfs fixture, a successful 32 MiB
write/fsync check, one exclusive dispatch claim, two schedulers and
`mix test --no-compile --no-deps-check`.

The run took 7,180.3 seconds and exited **2**. Its formatter reported
**3,906/3,932 passed**, **26 failed**, **52 invalid**, **128 skipped** and
**121 excluded**. Invalid and skipped cases are not passing qualification.
All six actual combined chat controls completed their final assertions: four
normal accept/cancel/stale controls, explicit reoffer, and planning exit through
acceptance/reopening/fresh-chat recall. None tested a next prompt in the reopened
original conversation; that separate diagnostic remains open.

After the suite, byte/hash checks for source, complete runtime, artifact/helper
and raw links all passed. Independent complete source/runtime path-set and byte
comparisons also passed. No input was rebuilt during the suite. The retained
private raw log has SHA-256
`5ee8a637dc2b41be9d471f468ab55e83fa9333b822e6fac339902a764a215a6f`;
private transcript contents are not published here.

| Retained input or receipt | SHA-256 |
| --- | --- |
| Source manifest | `c61cdbffb09c8d424e7ec15fcf8bb48232ae25c8e5a1a2931acbb4f2512bc858` |
| Runtime manifest | `94c34b8a9a18d597f5458a994bedfd1ef619afb72dd388a343fe1c63ec486914` |
| Catalog/helper manifest | `01cc6c117a6e7fc908589baa35958c625db9eae37e133a56b1a6d4ed3a39f740` |
| Exit and four postchecks | `3b756a89ee2e3db7a6f9dc1326132fdc714fb7e7a7ed65be005feedcab7904ce` |
| Public list of 26 failed cases | `7deca53d63c5ff3965f752bd0eff76c0d7be5d996c16a7902e89e88d4bf0d9c4` |

## Failure disposition

The 26 failures were classified before another integration attempt:

- Three Setup cases supplied a shell-policy answer based only on the OS. The
  actual conditional prompt was absent, so the extra answer cancelled writing.
  The fixture now responds to observed prompts within its original deadline.
- Three managed service cases built consent mappings from both imported
  instances and exceeded the unchanged selection bound. Their fixture now
  selects descriptors belonging to the intended instance.
- Nine Corpus/producer/planner cases stopped at the
  [dense manifest bound](dense-corpus-manifest-20261104.md), before their user
  journeys. The same setup failure invalidated 52 cases across three modules.
  Shorter equivalent descriptor wording preserves schemas and the bound.
- Six native workspace cases placed workspaces under `/dev/shm`. The sandbox
  correctly refused the protected `/dev` overlap. These fixtures now use fresh
  `/tmp` workspaces without changing the sandbox policy or assertions.
- Three Git declaration fixtures failed writing `index.lock` because of disk
  quota. A fresh rerun exposed their oversized input closure: the test copied
  unrelated untracked scratch directories as well as project source, exhausting
  quota even before Git. The reviewed fixture repair uses cached Git paths,
  matching the evaluator's source inventory and preserving current file bytes
  and added source files. The measured 1,285-file closure was 19,445,831 bytes
  before the wide-case additions. Fresh focused verification remains required; no Git
  identity, signing or source limit was changed.
- One stale-A/current-B publication case stopped before its candidate marker.
  Its cause remains unproven. A fresh diagnostic retains the actual consumer
  outcome and journal while preserving the original five-second deadline.
- One privacy check found arbitrary reason inspection in correction result
  journaling. The producer now uses fixed refusal/uncertainty classes while
  preserving the returned outcome and successful receipt.

The reviewed repairs have been applied and a new strict source/native/four-bundle
build passed. Subsequent [focused controls](focused-source-regression-20261104.md)
pass for the failed and invalid cases across distinct source freezes; a complete
final regression remains required. This record does not relabel the failed run or
establish installed, paid-account, human or platform qualification.

An earlier discovery launcher accidentally attempted fixture execution when
ExUnit's registered exit hook ran. It failed in the restricted sandbox before
knowledge/provider effects and is excluded from qualification. Its log and
explicit disposition remain retained separately. Subsequent discovery must
avoid loading a test helper merely to enumerate cases.
