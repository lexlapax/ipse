# First foundation adversarial review

Dated **2026-10-26**, against the uncommitted P30A/P31A foundation on
`codex/p30-p31`, base `fbb207d`. The developer explicitly authorized independent
data/review subagents and separately requested a final prompt to give another
agent themselves. This review is incremental; it is not the required final
whole-P30/P31 post-implementation audit or milestone acceptance.

The fresh reviewer examined the neutral decision contract, native wire subsets,
development interaction/capture probes, tests, frozen proposal and evidence.
It made no repository changes, ran no project compilation/tests, made no inference
calls and read no independent answer keys. It used static inspection, official
wire documentation, and isolated Elixir reproductions against existing beams.
Source/snapshot reversal hashes and the pilot's 102/42/42 request/continuation/item
counts reconciled. Evidence and [current implementation status](index.md) remain distinct.

## Findings requiring repair

| Severity | Trigger and consequence | Required repair and regression |
| --- | --- | --- |
| P2 | Native usage accepts fractional `total_tokens` equal under loose comparison, and cached-read/write counts exceeding input | Require safe integer total, exact sum and bounded known detail partitions; reject unknown detail keys |
| P2 | Accept an ordinary draft, enter read-only, then consume; original mode overwrites the newer restriction | Preserve the stricter current/enclosing ceiling or refuse incompatible transition; test both planning and read-only |
| P2 | Correct 64 tiny pending proposals to maximum-size text; aggregate grows to 393,216 bytes above 262,144 | Recheck aggregate bytes after replacement, excluding the previous candidate value |
| P2 | OpenAI encode accepts eleven score levels; selected guide permits 2..10 | Refuse unsupported rubric length in both selected wire subsets; preserve the generic neutral range separately |
| P2 | Propose in project A, switch project before render, render/accept in B | Store original project identity at creation; validate at render and acceptance |
| P2 | Start a new Session/review transition reusing the same client ID; old acceptance code remains usable | Invalidate every render slot on transition, independent of client string equality |

The rubric finding compares the fetched
[OpenAI Decisions guide](https://developers.openai.com/api/docs/guides/decisions)
with its reference: the guide states a narrower count than the rendered reference
expresses. Use the supported intersection, without truncation or engine substitution.
The reviewer also confirmed that native confidence must remain separate from
selected-option probability.

Prototype findings concern fidelity of the nonpublishing model, not existing
runtime authority: those helpers cannot currently save a note or approve an effect.
Nevertheless their contracts must be corrected before using them as implementation
acceptance. Repair status and actual regression results will be recorded below;
none is closed merely by this table.

## Repair and recheck

All six findings above were repaired with regressions. Subsequent independent
review found four pilot issues: selected provider timeout/response ceilings could
be widened; multiple or unselected calls received generic success receipts;
duplicate-key arguments bypassed the bounded parser; and a locally refused
request was counted as a dispatch. The pilot now preserves tighter valid limits,
refuses unsupported batches without successful receipts, uses the bounded JSON
decoder, and distinguishes local refusal from actual dispatch. Independent
isolated probes confirmed all ten repairs in the final source direction.

The reviewer then reproduced `tool_calls: false` being treated as absent; both
initial and continuation paths now reject it. An author check expanded the quota
from text bytes to the full encoded retained candidate map, excluding ephemeral
render leases. Independent recheck found that changing `pending` to `accepted`
could still add one byte at the exact ceiling. The accounting now reserves the
longer status for every proposal. A regression fills the complete encoded budget,
accepts all displayed proposals and verifies the final 262,144-byte bound.

Final focused verification passed **35 tests**, covering the decision contracts,
wire adapters, baseline preservation and development probes. Format, strict
compilation, credential-free demo and documentation checks also passed (466
Markdown files and 4,271 local links at that checkpoint). The earlier full source
suite passed **1,794 tests, 36 excluded**, before these repairs; it is not a full
post-repair receipt. A fresh full suite will run against a fixed revision.

This closes the incremental foundation findings. It does not qualify runtime
consent, capture, retrieval, model quality, installed workflows or the complete
milestone, all of which need their owning implementation and final audit.

## Operator-channel feasibility observation

A separate author-owned temporary Rust/Elixir probe confirmed that OTP's public
`nouse_stdio` port option preserves the original terminal streams while using
descriptors 3/4 for control. A native helper displayed a prompt and read synthetic
input from a real test PTY; piped/actual production qualification is still pending.
The spawned helper has a new OS session, so it has no own `/dev/tty` despite the
inherited terminal descriptors. This observation adds no runtime code or human pass.

The reviewer found the direction compatible with the frozen actual-display/input
boundary if the implementation verifies matching admitted terminal devices, uses
those exact descriptors, sanitizes display, binds fresh codes after completed
display, accepts no attestation through control frames, and invalidates partial
input on parent loss. Same-user terminal injection/PTY automation remains outside
the human-attestation claim. Cancellation, descriptor identity and redirected-input
negative controls remain mandatory implementation tests.
