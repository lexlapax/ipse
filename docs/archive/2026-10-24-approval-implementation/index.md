# Session permission implementation

Implementation record, 2026-10-24, starting from `877a200`. The developer explicitly
selected implementing approval UX before the external audit, extending the P28
brief's original exclusion of approval semantics. The
[research](../2026-10-24-p28-approval-ux/index.md) and
[walkthrough](../2026-10-24-p28-walkthrough/index.md) explain the scope.
Current procedures belong to [terminal usage](../../operator/usage.md#approve-a-small-task)
and [architecture training](../../developer/architecture.md#trace-a-tool-and-its-approval).

## Permission and machine-name verification

The permission/default-mode baseline is `dac11dc`, with runtime unchanged from
`b874fc7`. Its full local/native/installed and
[hosted Linux/macOS matrix](dac-hosted.json) pass. The successor
`5bb57614aa846f89d0775aa59640ab23447a69fd` prefills the initial browser name with
`ipse@HOST`, as explicitly selected by the developer, while preserving returning
registrations. Its own full local and installed checks pass. The
[verification receipt](verification.json) keeps earlier failures/cancellations
and the predecessor's platform success separately. The table describes `5bb5761`;
the later [Grok increment](../2026-10-24-xai-provider-research/index.md) has its own
verification and does not inherit these exact-build results.

| Gate | Actual result |
| --- | --- |
| Focused Auth/setup, permissions and terminal controls | 76 passed, seed 516367, 19.2 seconds; predecessor's broader set retains 127 passing cases |
| Build, formatting, warnings-as-errors compile and CI policy | Passed in a clean fixed source copy |
| Full Linux suite including native confinement | 1721 passed, zero failures, 19 excluded; seed 549147, 1063.0 seconds, exit 0 |
| Isolated credential-free demo | Passed after the full suite; tracked source tree remains clean |
| Complete installed-package proof | Passed; real grant reuse/revocation/resume, existing upgrade/recovery, memory, MCP, extension and child checks; inventories unchanged |
| Exact archive and runtime notices | SHA256 `2b1f6745a7815778424a23fb13e71e6fd72458383b18e915033049b49b41cc6c`; all 24 runtime-notice files rehashed against SHA256 and Git blob identities; Elixir 1.20.4/OTP 29.1.1 |
| Operator examples against packaged CLI | Archive/application/CLI identity and complete installed behavior proof pass |
| Committed-tree documentation | Clean Git checkout: 415 Markdown files, 3837 local links, zero errors |
| Hosted Ubuntu/macOS and independent proofs | [Prefill run 40117303058](prefill-hosted-failure.json): Ubuntu complete matrix passes; macOS fails a 120-second declaration-CLI fixture timeout, so no combined platform pass; predecessor `dac11dc` passes its complete matrix |

No real provider was contacted for these changes. Earlier P29 live receipts and
human browser/account observations retain their own exact source and scope.

## Implemented authority

- Review each effect remains the interactive default. `--accept-edits` explicitly
  permits root native file edits in chat; it cannot combine with `--yes` or `run`.
- A fresh write/edit proposal offers `edits CODE`; a shell proposal offers
  `session CODE`. Once and deny remain available. Shell reuse matches the entire
  argument map, cwd and requested sandbox policy, without prefix/glob parsing.
- Session owns at most 32 shell grants, each with at most 16 KiB of arguments.
  `/permissions` inspects; `/permissions clear` revokes future dispatch authority.
  Cancellation retains grants; closing/resuming loses them. Children, MCP and
  extension/SDK effects retain separate approval. Headless denial takes precedence.
- Intent-before-effect is retained. Prompt grant/revoke records and each tool's
  `approval_source` explain authority without restoring it on resume. Native edit
  grants retain path checks and additionally reject hardlinks. Existing filesystem
  replacement races and trusted-shell limits remain explicit.
- Embedded callers that omit approval mode retain the same `:ask` default in
  dispatch, startup edit consent and grant admission. No dependency was added.

The fixed seven-effect task compares four writes plus three identical shell calls:
seven decisions with once-only consent, two with explicit edit/exact-command
grants. This is a fixture comparison, not a new human walkthrough or a benchmark
of arbitrary tasks. The installed control independently executes four effects
with two decisions, inspects/clears grants, closes and resumes idle.

## Verification chronology and repairs

| Candidate / check | Retained observation |
| --- | --- |
| Initial focused run, seed 675536 | Four terminal fixture failures matched the old prompt wording. Fresh-code binding was retained; expectations now match explicit allow-once wording. |
| Focused follow-ups | 53 passed, seed 776245, 19.1 seconds; then 88 passed, seed 253648, 22.6 seconds, including chat flag, native edits and child/release controls. |
| Approval-only `48a42d8` | 1720 native-inclusive tests passed, 19 excluded, seed 45144, 1069.3 seconds, exit 0; isolated demo and installed proof passed. Archive SHA256 `a49d0663aeacdf87baa6c1bb01de9f63546bf8cdfe6935cba26ed7fa2b3aeb5e`. [Hosted run cancelled](superseded-hosted.json) after the machine-label request. |
| Combined `8ee16dc` | 1721 native-inclusive tests passed, 19 excluded, seed 393182, 1062.3 seconds, exit 0; isolated demo and installed proof passed. Archive SHA256 `916596ef2b56ad871a7791b0b405c9bcaa72819d519354211a3ca8923fa90f69`. [Hosted run cancelled](superseded-combined-hosted.json) after the default-mode finding. |
| Controlled default-mode reproduction | Omitting `approval` in the real Session fixture returned `{:error, :grant_unavailable}` despite dispatch's default ask policy. One selected case failed, seed 389754. The repair aligns all three permission checks with dispatch; 127 focused cases then passed. |
| `b874fc7` hosted run 40114244391 | Both platforms stopped at docs validation: the index linked a receipt that had not been staged. Local checking saw the untracked file. [Failure retained](final-hosted-failure.json); no hosted ExUnit/installed/later success claimed. |
| Documentation repair `dac11dc` | Missing receipts committed; clean Git checkout docs validation passes. An archive-only check attempt was unsuitable because the checker requires Git metadata; the clean-checkout result replaces that attempt. Full source/installed and hosted Ubuntu/macOS matrix pass. |

Cancelled or failed matrices are not platform passes. Earlier successful suites
used explicit ask mode and do not establish the repaired implicit-mode behavior.
The later prefill failure occurs in the second declaration call of the
`separate_cli` captured-evaluator fixture, inside `System.cmd/3`. That test and
evaluation implementation are unchanged between the passing predecessor and this
candidate. Its cause remains unconfirmed; no assertion or deadline was weakened.
That failure supplied no platform verdict for the later Grok source.

The later combined runtime `622a2c8` now passes its full local native-inclusive
suite, installed proof and complete Ubuntu/macOS matrix, including the unchanged
declaration/Research fixtures. Its
[runtime matrix](../2026-10-24-xai-provider-research/runtime-hosted.json) verifies
the permission and browser-hint behavior together with Grok. This supersedes the
standalone prefill candidate for current combined verification; it does not
diagnose or erase the earlier timeouts. The later developer live-driver commit's
failed macOS controls and their test-only repair remain separate in the Grok record.

## Release rehearsal cleanup

The four RC files were copied into ignored
`dist/rc-rehearsal/v0.1.0-rc.1/assets` and their GitHub digests and archive sidecars
were rechecked. Automatic approval review initially rejected draft deletion without
explicit authorization. The developer then authorized deleting the draft while
retaining the tag/files. Deletion succeeded; the release query returns not found
and the RC tag remains on origin at `e944fcf`. The
[cleanup receipt](../2026-10-23-p28-p29-implementation/rc-assets.json) retains
original inspection and actual deletion facts. Stable publication remains open.
