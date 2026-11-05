# Select a fetched body and recover a denied selector — 2026-11-04

Historical scoped checkpoint. Current instructions belong to the
[Research operator chapter](../../operator/research.md#fetch-and-retain-a-selected-source)
and [knowledge-package training](../../developer/knowledge-extensions.md#distinguish-independent-research-from-the-native-ledger).
This completes one ordinary State lifecycle slice, not full P31H or native-note authority.

## Behavior and compatibility

A fetched body retains its canonical full-body identity, exact quote and original
attribution. A changed body receives another immutable root. A separate selector
for the configured State partition, MCP binding and requested URI advances only
through the original host State revision/generation CAS. Gateway timestamps do
not order publication. Earlier bytes and citations stay intact and historical.

After known body publication and denied selector publication, an explicit
`select_retained` command freshly checks the retained body, original binding/URI,
source revision, expiry and original selector base. Its separately approved State
write changes only the selector; it fetches or publishes no body. Already-selected
is read-only, and a later conflicting revision prevents replacing the newer
selection. No old unknown is replayed, settled or refunded.

Fetched roots use strict integer format 2 and capture receipt version 2 from
staging through suppression. Both Research and Corpus need matching readers.
Old readers refuse new claimed/body-only roots; new readers keep legacy captures
inspectable but untracked rather than fabricating selection authority. Ordinary
put cannot rewrite a fetched body. Provided/document formats, same-body forgetting,
all existing presets, approvals, 16-KiB envelopes and cumulative counters remain.

## Evidence actually completed

The accepted five-file extension/test patch is
`b62fc55f31b78a988f645969871a2ab543081e83f3e9ea8f94e2c46bdbc6c3c1`.
Twenty-three pure controls pass, including strict-tag forgeries, denied/unknown
selection, competing CAS, canonical suppression, expired/foreign/altered bodies,
legacy handling and maximum encoded envelopes. Six separate old/new reader
comparisons retain their byte-preserving outcomes. These are component evidence,
not actual unknown-write recovery or model-quality trials.

One fresh ordinary Session/MCP/State actor then passes against the complete
coherent private SDK: dirty fourteen-path overlay over `18e3`, 241 host modules,
16 applications, four normal bundles and both explicit candidate workers. It
uses no partial host overlay. Exact artifact and runtime identities are in the
[safe result](research-fetch-origin-lifecycle-20261104/safe-result.json).

The actual journey fetches A; publishes B's immutable body while denying only its
selector; confirms close and strict Saved/idle recovery; then uses a fresh Session
to inspect/export B and approve one selector-only recovery. Repeating selection
makes no effect. A newly fetched C with an earlier gateway timestamp becomes
selected; a fresh B request cannot cross its original conflicting base. Queries
and exports retain exact UTF-8 citations and immutable A/B rows. Both original
Session histories reopen idle without new intents or State changes.

The actor, immutable pre/post guards and operator check all exit zero. Neutral
host cleanup confirms the launcher and owned workers/helpers absent; Input
entries are empty. There are zero model requests and zero TTY reads. The fresh
fixture is retained, and the actor is not repeated. The
[exact fixture and paired patches](research-fetch-origin-lifecycle-20261104/README.md) and
[manifest](research-fetch-origin-lifecycle-20261104/SHA256SUMS) are public, without private execution contents.

After integration, the two complete Research tests and two existing managed
root-change controls pass: four selected cases in 34.8 seconds, with 200 unrelated
cases excluded. The first Research case runs the 23 pure controls internally;
these counts overlap earlier evidence and are not added. The second exercises
ordinary MCP/State denial, forgetting and unknown-outcome recovery. The normal
native/197-source/four-bundle build, formatting, strict compilation and isolated
credential-free demo also pass. These checks do not replace the open full suite.

## Review and limits

Whole operator Research and developer knowledge-extension chapters were reviewed
against the final source and actual journey. The integrated manual patch teaches
paired upgrade, ordinary approvals, inspect/export/select recovery, finite expiry,
unchanged bounds and the distinction between local State selection and current
source authority. Existing task flows remain intact; no feature-status appendix
was added. Canonical integration validation checks 1,200 Markdown files and 9,841
local links with zero errors.

Earlier candidate compile/pure and compatibility-helper setup failures remain
preserved. The initially reviewed loose numeric-tag candidate was superseded by
the strict correction before this actor. The private launcher review also found
and fixed a worker PID-scan omission; an AST-derived launch-argument control
proves both worker shapes are detected, without starting workers. Two pure helper
setup errors remain recorded. No failed actor or unknown State operation was
resumed to obtain this result.

This is synthetic ordinary MCP/State approval, not a live publisher's truth,
remote freshness, independent human review or native saved-note permission.
Installed use, derivative/cross-store suppression, managed-derived State writes,
model-selected fetched retention, quality, annual work and full P31H remain open.
