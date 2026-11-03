# Saved source-window reuse and strict recall check — 2026-11-03

This synthetic source-runtime check covers a guarded reconstruction change. It
does not establish populated-recall performance, a completed 33-note journey or
annual qualification.

The isolated snapshot was reported exported from commit
18c748fc30ed09438ebdaaaf6d6d13b8e970cbcf, omitting historical archive data.
A full export-to-commit comparison is not retained here. The
[source/test patch](saved-source-window-fold-20261103/task-saved-window.patch)
and separate [developer manual patch](saved-source-window-fold-20261103/task-manual.patch)
have exact [preimages](saved-source-window-fold-20261103/preimages.sha256) and
[outputs](saved-source-window-fold-20261103/outputs.sha256). The manual edit was
prepared separately after the tests; it does not alter the frozen candidate.

In the isolated candidate, an ordinary Session header allows Saved to reuse the
source window produced by its chronological validation fold after the remaining
Saved checks succeed. The candidate creates a fresh window ID and secret;
non-session first records retain the independent reconstruction path. It leaves
source ownership, original-file checks, source-page validation, current permission
and later-use fences unchanged. After the strict failure below, this candidate
was not promoted to the current runtime; this paragraph describes the candidate.
The source-index measurement that motivated this candidate covered more than
one operation; it did not establish which cache lookups hit or what fraction
of elapsed time this change removes.

The run reported an offline source build, strict project compile, test-environment
bundle build and changed-file format check passed. The retained build and format
logs do not independently record the commands, flags or process exit statuses;
the format log is empty. Dependency compilation emitted warnings in both build
environments. HOME stayed inherited; the direct ExUnit runner
used explicit synthetic IPSE_HOME, temporary workspaces and loopback fixtures.
No OS-level home-access trace was taken.

The following selections passed in separate VMs:

- [Source window](saved-source-window-fold-20261103/window.log): eight tests,
  including an actual synthetic 64-tool-receipt history, an independently
  rebuilt window comparison, fresh-handle refusal, legacy-first-record fallback,
  tampered history and confirmed close/reopen.
- [Replay cache](saved-source-window-fold-20261103/cache.log): six tests,
  covering cache bounds, reconstructed input, lifecycle and fresh identities.
- [Cancelled draft](saved-source-window-fold-20261103/draft-cancel.log) and
  [accepted draft](saved-source-window-fold-20261103/draft-accept.log): one
  selected test each, comparing replayed windows against independent rebuilds.
- The genuine synthetic pending-assessment controls for
  [source withdrawal before decision](saved-source-window-fold-20261103/source-loss.log),
  [source withdrawal before output release](saved-source-window-fold-20261103/output-loss.log)
  and [pre-Session grant revocation](saved-source-window-fold-20261103/revocation.log):
  one selected test each. They use the existing native PTY fixture and do not
  qualify a real decision service.

The retained [source manifest](saved-source-window-fold-20261103/task-source.sha256)
has 1,263 regular files. Its complete before/after check logs match. The
[test runtime manifest](saved-source-window-fold-20261103/task-runtime.sha256)
covers 781 files; its two symlink identities and complete path list were also
checked before and after. These manifests refer to the original isolated tree;
the entire source and runtime trees are not archived. The separate
[evidence manifest](saved-source-window-fold-20261103/evidence.sha256) covers
the retained patches, manifests, test entry and synthetic logs.

The controls establish the tested replay equivalence, refusals and fresh handle
behavior; they do not establish identical behavior for every history, prove a
latency improvement or remove the need for live current-use authorization.

## Distinct strict 33-note attempt

One fresh, separate strict fixture attempted a real synthetic Session with 33
natively reviewed notes and one temporarily missing original source. The exact
candidate patch and runtime matched the focused run above. Its
[strict fixture patch](saved-source-window-strict-20261103/strict-fixture.patch)
and [source-manifest delta](saved-source-window-strict-20261103/strict-source.delta)
reconstruct strict source manifest SHA-256
a06c00004c46a11265c7376a91e82b7156b15f089ba10ae76586a0cf64cbd9a0 from the
retained candidate source manifest. The matching test-runtime manifest SHA-256
was 8e846418d4a082e346b841701a7add27262d7ba79607f3af1fe3549a8e3aa510.
An initial copied-runtime preflight refused missing priv paths before any test;
the corrected scratch layout then matched all 781 runtime files and two symlink
identities. The retained [failed copy check](saved-source-window-strict-20261103/copied-runtime-check.log)
and the candidate's identical successful runtime-check log record those scopes.

The [one-shot claim](saved-source-window-strict-20261103/launch.claim) preceded
the attempt. The strict test exited 1; its normal source/runtime postcheck exited
0, as shown in [completion.txt](saved-source-window-strict-20261103/completion.txt).
The fixture used its longer outer PTY/ExUnit bounds; these did not increase the
product's Worker or inference deadlines. No retry was made.

The redacted [event analysis](saved-source-window-strict-20261103/failure-analysis.log)
records 37 delivered Worker inputs, a managed preflight, an inference-dispatch
intent, and a turn error. The separate
[outcome projection](saved-source-window-strict-20261103/outcome-projection.jsonl)
records a failed model measurement at 17,180 ms and a failed partial request
finish at 17,181 ms. The projection uses the literal string `nil` for absent
fields; those placeholders are not original journal values. The synthetic listener
reported a connection closed before
its initial receive returned request bytes; the
[listener projection](saved-source-window-strict-20261103/listener-projection.txt)
binds that observation to the hash of the private one-shot log. This does not
prove why the connection closed or what happened elsewhere. No timeout or other
cause was recorded.

The [source analysis](saved-source-window-strict-20261103/failure-analysis.log)
reported that all 33 original source journals retained their recorded identities
and byte hashes, all 33 lock identities matched the
[pre-run inventory](saved-source-window-strict-20261103/recall-source-before.json),
and no original journal .held path remained. The check script is retained, but
the full post-run source state is not archived. The full consumer journal and
raw terminal log are also not archived; their hashes do not reconstruct those
files or cryptographically authenticate the redacted projections. Synthetic
approval codes and fixture transcript content remain private.

The expected complete 32-note provider-reference assertions and idle-reopen
assertions occurred after the point of failure and were not reached. This
attempt did not prove a successful request, complete fitting-set recall,
performance improvement, or the cause of earlier failures.
