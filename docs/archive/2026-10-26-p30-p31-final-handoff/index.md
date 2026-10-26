# P30/P31 final plan repair and implementation handoff

Dated **2026-10-26**, source baseline `a812369`. The developer supplied a third
read-only plan audit, then requested a final repair, our own audit and further fixes,
and a handoff for another implementation agent. Its private scratchpad report was
read without copying it into the repository. This record concerns documentation
and design readiness; it does not claim P31 implementation, live cache behavior,
capture propensity or performance measurements.

The [current plan](../../plan.md) owns status and dependencies; the
[current proposal](../../knowledge-design.md) specifies contracts until its planned
implementation-time archival. Start authorized work with the
[implementation handoff](implementation.md). The [previous design](prior-design.md),
[previous plan](prior-plan.md) and [previous repair record](../2026-10-26-p30-p31-plan-review2/index.md)
preserve the replaced checkpoint. Earlier developer answers remain unchanged.
New protocol details below are design judgments, not invented user decisions.

## Supplied findings and repairs

| Finding | Concrete repair |
| --- | --- |
| F1 high: changing header defeats prompt reuse; token-only gate misses it | Add a versioned host turn-local projection after admitted native history, with stable header/catalog epochs and per-adapter serialized-body checks. Preserve historical envelope placement; safe retraction may intentionally reset reuse. Measure cache-read/write/uncached/non-read partitions and request/operator TTFT, with explicit unknown/live qualifications. |
| F2 medium: bare yes can answer a competing prose question | First release uses explicit rendered `accept CODE` only for cards, distinct from effect approval and native question answers. Restated choices remain direct assertions; bare-yes research is observation-only and cannot enable the behavior. |
| F3 medium: notes/index/other publishers overflow context | Correct the cap to eight items per instance, 16 KiB globally rendered. Budget 8 KiB maximum to automatic knowledge context, split into recall, tiny source handle and framing; reserve remaining capacity and shrink optional recall. Full index/evidence uses bounded host reads, available even without an inline handle. Required-source failure and stale-replacement refusal remain visible. |
| F4 medium: 20 items/day is an assumption | Keep it as a floor; finite representative main-model pilots derive useful-unique intake/class mix before capacity freeze. Repeat in integrated sessions. Higher ordinary intake needs capacity/quality remediation; burst exhaustion pauses visibly without evicting persistent evidence. No implicit paid-service selection. |
| F5 medium: draft tool changes reset cache; cancellation can contaminate later work | Keep the ordered catalog stable, reject at dispatch, persist cancellation/fence late work and append tail intent status. Test later prose/effects, compaction/resume and existing grants for cancelled requirements. Distinguish deterministic admission from model semantic adherence and preserve honest native-history limits. |
| F6 low: inferred persistent category needs a remedy | Receipts show category/reason/expiry and a one-step downgrade or task-only action. Retain an operator override so identical support cannot immediately be promoted again. |
| F7 low: headless operators lack review | Provider-free standalone review with controlling-terminal display/response, bounded exact displayed batches, preserved original provenance and fresh version/policy checks. Generated input can inspect but cannot attest as human. |
| F8 low: live design needs an archival transition | First authorized implementation commit archives the exact final proposal, retires its live body and links the frozen baseline from the plan. Implemented behavior belongs in current manuals; later material changes get dated amendments. |

## Source and external checks

Inspected [Session context](../../../lib/ipse/session/context.ex),
[Turn dispatch/catalog](../../../lib/ipse/session/turn.ex),
[extension context](../../../lib/ipse/extension/context.ex),
[saved-result reader](../../../lib/ipse/extension/result_source.ex),
[OpenAI](../../../lib/ipse/provider/openai.ex),
[Anthropic](../../../lib/ipse/provider/anthropic.ex),
[Gemini](../../../lib/ipse/provider/gemini.ex),
[Usage](../../../lib/ipse/usage.ex),
[cost partitions](../../../lib/ipse/usage/costs.ex) and
[terminal input](../../../lib/ipse/cli/terminal.ex).

Additional concrete hazards found while preparing the repair: Anthropic/Gemini
hoist system-role messages, so a trailing system message would not fix F1;
`saved_result_read` currently appears only after a first result; reported model
facts can change the header; context replacement failure can leave an old selection;
and an interactive flag alone does not establish terminal-origin confirmation.
The design now handles each explicitly.

Primary guidance was checked with the OpenAI Docs workflow against
[OpenAI prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching),
[Anthropic prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
and [Gemini context caching](https://ai.google.dev/gemini-api/docs/caching).
Stable layout is not a cache-hit guarantee. The current Anthropic adapter sends
no cache-control configuration; no subscription eligibility or live hit rate is
inferred from API documentation.

## Own final audit

Three independent read-only passes inspect the actual revised contract and handoff:
provider projection/cache/draft behavior, context/capacity/retention, and acceptance/
review/archival lifecycle. The final pass identified these additional gaps, which
were repaired and checked again against the actual text:

| Additional gap | Final repair |
| --- | --- |
| Only knowledge might move to the tail while another context publisher keeps changing the header | The versioned P31 projection covers every selected publisher, with legacy-session replay preserved. Ordinary updates cannot masquerade as intentional epoch resets. |
| Forgotten managed data might survive in paged tool results or compaction excerpts | Revalidate/retract all managed surfaces before dispatch, preserving native pairing and original records. Add forget-after-paged-read continuation, resume and compaction cases. |
| Chat/native answers could still use an unverified interactive boolean; standalone review lacked a distinct identity | Apply verified operator-origin checks to every human-attestation path, keep piped/legacy-unproven input unverified, and bind standalone codes to an independent review client/project without starting a conversation. |
| Retained consent while disabled might permit review publication | Inspection/rejection/forget/reduction remain available; publication needs active valid permission and cannot re-enable knowledge. |
| One-step retention reduction could erase evidence needed by another claim | Suppress the selected derivative, preserve unrelated authorized dependents and show explicit temporal coverage gaps after a user policy override. |

The final follow-up passes found no remaining material contradiction in their
bounded scopes. Context/pilot checks also confirmed that zero-inline source access,
bounded tool-heavy trials, measured workload increases and provisional live targets
have concrete behavior and owners. This is implementation-plan coherence, not a
guarantee that the implementation or performance targets will pass.

## Verification and handoff status

Whole-document operator/developer knowledge and memory guidance remains separate
from the proposal; no existing command examples or runtime behavior changed.
The handoff names source owners, finite P31A deliverables, missing-evidence handling,
the archive transition, verification and a ready-to-paste first implementation prompt.
It does not dispatch another agent or publish a release.

`ERL_CRASH_DUMP=/dev/null elixir dev/check-docs.exs` passes for **442 Markdown files,
4,177 local links**, with zero errors. Whitespace checks pass. The prior design and
plan match `a812369` after declared link/separator transformations, and the previous
repair record's body is unchanged beneath its new supersession notice.
No runtime tests, capture pilot, cache benchmark, live inference, human trial or
dependency installation ran in this documentation-only task. Those remain future
implementation evidence, explicitly assigned in the handoff.
