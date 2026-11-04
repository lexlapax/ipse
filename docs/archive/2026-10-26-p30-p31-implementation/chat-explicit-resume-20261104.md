# Explicit-resume decision review — 2026-11-04

This is a historical qualification record for the isolated source prototype.
The [operator procedure](../../operator/knowledge-permissions.md#review-a-proposed-decision-during-chat)
and [developer explanation](../../developer/session-sources.md#move-a-completed-reply-into-native-decision-review)
own current behavior after integration. This follows the
[completed-reply baseline](chat-completed-reply-20261104.md); it does not close
P31 or replace required whole-source, installed or platform checks.

## Contract and bounded implementation

An explicitly resumed interactive conversation, without an initial task, may
offer a new review of its existing pending decision. Startup registers a waiting
native reader, performs the bounded read-only check before its first read or
`you>` prompt, then either enters ordinary chat or activates one fresh handoff.
The existing confirmed reader stop, Session close and standalone native review
remain the authority path. No new Input protocol or asynchronous preflight
process is used. Input typed before a prompt is not claimed as accepted work.

The original version-1 handoff stays unchanged. A version-2 wrapper binds that
original, a new actual Writer receipt, new client/generation, review/focus IDs,
render revision and validated normal mode. Idle focus does not invent a turn or
request. Every prior matching reservation needs a validated known disposition;
missing, unknown or contradictory evidence blocks another review. Current
Identity, selected Consent rows, signed pending value and original source are
checked again at display and publication. Management facts remain standalone
with `session_id: nil`; later protected use authenticates both source receipts.

The added `Consent.with_policy_operations/7` projects only bounded distinct
selected existing rows under the existing policy transaction. It neither
creates a ledger nor grants authority. Compact receipt hashes cannot establish
a known cancellation without the required matching journal. Known policy
denial is distinct from an uncertain earlier effect. Ordinary configured
approval, including an explicit `--yes`, survives; session edit/shell grants do
not. Internal reopening disables reoffer, preventing a cancellation loop.

## Source identity and checks actually run

The candidate was applied over the qualified isolated baseline at
`_build/verification/ipse-chat-current-ace41-20261103-01`, before integration on
main. Exact source and test packets are identified below; this is not a claim
that a later main revision was tested with these same receipts.
The [retained evidence manifest](chat-explicit-resume-20261104/manifest.sha256)
identifies the source/test packets, qualification receipts and preserved failures.

| Packet or receipt | SHA-256 |
| --- | --- |
| Eight-module source and focused tests, `reoffer-source.patch` | `5f976400e8b16c656d33016c89ee35339e6ddb9ae785bd94d1eab4c2ebe5b514` |
| Two-card fixture, driver and launcher, `reoffer-fixture.patch` | `60509fc8d2422c220ce4d1a06ea2766529657f3aaf40df12412ef1ffabde7dee` |
| Complete frozen runtime/artifact/fixture manifest | `e4e8c08731261f49af7ea00bf49373a97f730af306d577e18b5566da4df1353b` |
| Strict compile receipt | `2752233b11954fa51af93c708dcc3d89feb4f5b6b6594f23e3890caeb69ea094` |
| Six focused constructed controls | `d111bb1ec0d0e37683f280ec09c2385619fcf9ef9e164db8a8317f48650a6dbf` |
| Actual selected-operation/compaction/locking controls | `3a16abf164a8cf3b634f59ab3df6b7f3069eed336259e88c693c133041d05fca` |
| Fresh actual two-card control | `ff8869c9f252806ff3d947b46260126b300a8e0fc0234b7e29255e5cad611087` |
| Complete runtime closure preflight | `00f5fc4ab0c7581abae57d05ddea043ed7911c7ebc0a9c6ee8eaf9bbdf8b2171` |

Strict `elixirc --warnings-as-errors --ignore-module-conflict` compiled the eight
changed modules together with the two unchanged baseline Input owners into an
isolated output. Six constructed controls passed: wrapper/source/focus history,
known/unknown accounting, compact receipts, unowned activation, zero reader
arming on snapshot and authorized read-entry invalidation. Foreign calls leave
the legitimate snapshot intact. These controls alone are not native input proof.

Four separate actual file-owner controls passed in a fresh synthetic tmpfs home:
selected rows and old callback shape, current-policy/revocation/invalid-ID
refusals, projection after 65 actual settled operations, and concurrent admission
under a retained policy read. Source/runtime/helper postchecks were unchanged.

Read-only compatibility checks passed on both retained qualified controls10
conversations and their actual accepted/cancelled management receipts. Full
Saved, SourceWindow, actual byte receipts, handoff history and spent capture
identities remained valid. A syntactically valid receipt displaced one byte was
refused by actual source verification without new journal or ledger effects.
A real committed receipt attached in memory to a different pending selection
was refused by the full acceptance validator and the prior-disposition gate.

## One fresh two-card native journey

One selected ExUnit test passed in 15.2 seconds. Its driver used a genuine
synthetic PTY and actual native `approval>` input, not an injected acceptance
message. The loopback provider and workspace were synthetic; no account or paid
inference was used.

1. The main route nominated and completed one answer; the ordinary protected
   capture created one pending candidate and its original handoff.
2. The first native card received cancellation. The same conversation reopened
   with workspace edit grants false, then the client exited.
3. Explicit same-ID resume performed its check before any ordinary `you>` prompt.
   It offered the same pending candidate with a different fresh native code.
4. Exact acceptance created a second management operation and a version-2
   wrapper with the new actual source receipt. There was still only one
   nomination and one capture. The original wrapper/provenance stayed unchanged.
5. The same conversation reopened without an automatic third card. After exit,
   a fresh chat recalled the accepted decision through a version-6 protected
   read and completed normally. Final receipt/accounting assertions passed.

Before effects, the launcher proved the complete selected application ebin,
`Ipse.Extension.Bootstrap`, every worker dependency ebin, exact private directory,
executable helper, bundle inventory and fixture closure. A partial override ebin
was not used as the worker's application root. Every frozen manifest input was
rechecked after the run and remained unchanged. The retained synthetic root is:

```text
/dev/shm/ipse-reoffer-qualification-50c53e7875fda8330b76a93b445ba608/tmp/ipse-chat-reoffer-087ed4c71747f70bd853a49930243fb2
```

## Failure and withdrawal ledger

Earlier evidence is retained rather than relabelled as passing:

| Earlier result | Disposition |
| --- | --- |
| Asynchronous preflight plus a new preserving Input-pause design had strict and constructed positives | Withdrawn: startup can check before the first read, eliminating that protocol. Preserved manifest `66570e57687bd44e4a357da9bda85664448ed77bb80e3c30e847045964a1708b` identifies its source, outputs and logs. No native qualification is claimed for it. |
| Initial selected-row concurrency fixture passed 3/4 | Its receive asserted on the wrong process: protected callbacks run in a controlled file-effect child. An explicit observer handshake corrected the fixture; all four then passed. Product locking was not weakened. |
| Initial retained selector expected one journal but found original plus fresh recall | The read-only selector was corrected to choose the journal containing the actual handoff. No effects were retried. |
| First startup guard controls passed 5/6 | An earlier authorized managed-approval read shortcut bypassed snapshot invalidation. Both authorized read-entry clauses now invalidate; foreign requests preserve the snapshot. Six fresh controls passed. |
| First different-selection negative expected its modified full journal to validate | The existing `validate_management` boundary already rejected it. The expectation was corrected to require refusal; the new explicit `matches_facts?` check is redundant defense, not a relaxation. |
| Fresh two-card native run | First selected actual attempt passed 1/1, with unchanged postchecks. |

## Remaining limits and integration gates

The actual journey starts in normal mode. Planning-start then witnessed exit
has separate investigation and qualification; this receipt does not establish
that combination. Current accepted-note recall from its own active original
conversation remains unavailable. This is one known-cancel then explicit-resume
journey, not unlimited-card, independent human, installed-package, macOS or
live-model qualification. Unknown reservations are deliberately not replayed.

After integration, run the focused commands in the developer chapter and the
required formatting, strict compilation, source/native/demo/package and
documentation checks at the final source revision. Keep later qualification
separate from this exact-source receipt.
