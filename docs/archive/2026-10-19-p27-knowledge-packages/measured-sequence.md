# Native measured sequencing, 2026-10-19

Historical implementation and verification record after `aae6b1f`. This extends
the [native collector](aggregate-memory-native.md) with generic measured stages.
It does not complete P27. The [plan](../../plan.md#p27-optional-research-graph-and-rag)
owns acceptance, the [developer exercise](../../developer/knowledge-evaluation.md#exercise-complete-measured-sequences)
teaches verification, and the [native protocol](../../../native/README.md#sequence-complete-measured-stages)
owns the binary layouts and lifetime rules.

## Keep every application stage inside measurement

The native sequencer runs inside the admitted whole-run population. It launches
preparation, each cell and finalization through the same birth-before-exec
collector. Every stage has a fresh lifetime peak and an independently retained
parent interval. The whole counter remains unreset. No peak is summed with or
subtracted from another peak.

The generic descriptors contain bounded commands and stage identities. They do
not contain a domain plan parser, provider selection or budget policy. Private
raw snapshots and numeric file identities preserve the admitted descriptors;
exclusive synced claims precede stage launch. The collector publishes its usual
native M frame followed by a two-byte T status on the internal stage interface.
The sequencer retains the exact protocol, receipt and status. Child stdout stays
in the opaque log and cannot forge native completion.

A failed application with confirmed cleanup remains failed and permits distinct
later stages and finalization. Missing or unconfirmed collector completion stops
the sequence. No stage is retried. Refusal of the same evidence directory
preserves those attempts. A domain runner still must claim the freeze permanently
before opening inputs; a new output directory cannot grant renewed authority.

## Challenge the whole unit

Two independent contexts reviewed the whole implementation, actual verifier,
fixtures, test/CI coverage and affected manuals. Both found that opening a
writerless FIFO with ordinary read-only flags blocks before the retained-FD type
check. This affected both bootstrap admission and a cells descriptor produced
by preparation.

The lead added a bounded Rust regression and reproduced the defect on Serenity.
The before build passes five tests and fails the FIFO test after its one-second
guard. Opening with O_NONBLOCK before fstat repairs the boundary. The regression
then passes, and two live controls verify that a bootstrap FIFO refuses before
preparation and a cells FIFO refuses before any cell or finalizer. Both reviewers
reread the whole repaired unit and reported no remaining actionable findings.
They inspected the lead's actual logs; this is separate from independent test
execution and does not claim model diversity.

## Direct Linux evidence

The warning-free Linux helper and standalone test binary builds pass. Exact
native source identities are:

| Source | SHA-256 |
| --- | --- |
| `ipse-sequence.rs` | `35fcaf360a069e60019edf23ded901b7e9c3007624d6d60062f90cf8967c01a1` |
| `ipse-runner.rs` | `81291a75a6fbb2a7169253a6e69b1186eef96b23b9cb800cd52f0aa8b82628c1` |
| `ipse-measure.rs` | `e08b304ba803c820ae2f4a32a25f90c47f8a5cfb6fe10fdb4923c6ce1949b546` |

All six native tests, six live sequence cases and ten prior collector controls
pass. The live positive sequence measures fresh BEAM preparation and finalization
with brief Port children. Its whole charged-memory peak is 346,853,376 bytes,
preparation is 214,286,336 bytes and finalization is 345,600,000 bytes. The
independent parent intervals cover their respective stage peaks. A simultaneous
unrelated 256-MiB allocation stays outside the measured population.

The other controls retain a failed but closed application's status despite its
forged stdout, run finalization once after that failure, stop later stages after
collector SIGKILL, and refuse both FIFO inputs without the outer timeout. The
same-output repeat refuses without changing retained evidence. These are
synthetic controls with zero model requests and no private evaluation inputs.

Private final evidence archive SHA-256 is
`4f7f8c40625c25a83df70b6b79b448ffaf2253493e1275d7502174fe069477f4`.
An independent read of the extracted archive reconciles exact M/T bytes, private
receipts and status records for all closed positive/failed stages and verifies
the interrupted-stage omissions. No owned measurement services remain. Serenity's
main checkout stays unchanged at `5e2d85ef4dffe38832c135648ccfc171078765b2`.

## Source and installed checks

The full local source suite passes 1,252 tests with 34 explicit exclusions in
734.4 seconds, with the strict stdio probe and unchanged 60-second test deadlines.
Build, formatting, warnings-as-errors compilation, CI policy and demo pass. A
separate clean Elixir 1.18 formatter invocation passes; its empty archive path
avoids loading the host's newer Hex BEAM. The earlier invocation's incompatible
Hex loader diagnostic remains retained separately.

The actual macOS native/stdio suite passes 30 tests with six exclusions in
25.1 seconds; four standalone Rust policy tests pass. The strict complete macOS
helper build passes. The fresh package, its extracted-runtime verifier and the
installed native sequence admission check pass. The unsupported measurement mode
refuses before reading the nonexistent bootstrap or executing application work.
Archive SHA-256 is `fff10d037eb8f76ee98afc5e267e916fb2ff9797a32873585470ec6d9371ecc8`.

The complete affected manuals were reviewed with the implementation and their
exercise commands. Exact-commit full Linux and hosted gates remain to be recorded
separately. The earlier collector's green platform gates do not cover this new
sequence unit.


## Remaining application work

The evaluator's full preparation/cell/finalization integration is still absent.
It must preserve the complete frozen plan, original project budget allocations,
disjoint Research reservations, permanent first-attempt claims and canonical
accounting. Owned model-service identity, endpoint admission and private cache
first touch remain separate work. Finalization cannot inspect its own later
receipt or the outer-root terminal record; a post-exit audit must reconcile both
before accepting comparison coverage.

The metric remains exact Linux kernel charged RAM. It does not establish summed
RSS, GPU/device peak memory or an exact macOS aggregate. Full held-out quality,
independent semantic judgments, resource comparison and engine selection remain
open. The previous interrupted run and its unknown reservation are unchanged.
