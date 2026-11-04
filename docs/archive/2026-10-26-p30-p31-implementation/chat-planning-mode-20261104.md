# Planning exit through decision review — 2026-11-04

This dated record covers a bounded synthetic Linux journey in the combined
implementation. The [plan](../../plan.md) owns acceptance; the
[operator procedure](../../operator/knowledge-permissions.md#review-a-proposed-decision-during-chat)
and [source chapter](../../developer/session-sources.md#move-a-completed-reply-into-native-decision-review)
describe current behavior. This supplements the
[normal-start controls](chat-completed-reply-20261104.md) and
[explicit-resume control](chat-explicit-resume-20261104.md).

## Preserve the actual mode across owners

The CLI's initial configuration can still contain `--planning` after the live
Session completes a witnessed `/plan exit`. Reusing that stale configuration
for standalone review or reopening could refuse review or reenter planning.
Claiming the handoff now captures the actual validated Session Mode. The
owner/ref checked private handle projects only the existing `Mode.config/1`
fields into review and reopening, checks the roundtrip, and clears startup
planning and session edit flags. Provider, model, endpoint and billing remain
the selected values. Explicit ordinary approval, including `--yes`, retains its
existing meaning; no new knowledge or ordinary effect permission is created.

Historical validation also needs the mode at each recorded event. Invocation
and Actions already consumed the validated sparse transition timeline. A real
planning-start prefix exposed the remaining ToolLifecycle reader using the
initial planning header for a later normal nomination. Its first rejected
`tool_started` record was at index 47. The exact receipt failed with frozen
planning metadata and passed with the validated normal mode. ToolLifecycle now
uses that same timeline per event and returns the unchanged original metadata.
Ordinary headerless fragments retain their existing shape. Missing, future,
forged and cross-Session transitions cannot authorize the later tool.

## Keep failed attempts and qualification separate

The first native attempt stopped before inference because its partial override
ebin became `Application.app_dir(:ipse, "ebin")` and lacked the Worker Bootstrap.
That was a fixture closure error. A second fresh attempt used a complete ebin,
completed nomination/capture/handoff and closed the original conversation, then
exposed the ToolLifecycle historical-mode refusal during management review.
Neither failed root was resumed or replayed. Read-only reconstruction with the
reviewed repair subsequently validated the retained original source and handoff.

The isolated repair passed strict compilation and 34 focused controls. The
actual failing prefix and the earlier normal/reoffer histories were rechecked
without changing their bytes. The combined product/test packet is
`_build/verification/notes-integrated-main-20261104-01/product-tests.patch`, SHA256
`5fda38ab5c506c83df6124430deb206d82bcf420e4b131edcae3d5e72b026260`.

The combined main source run produced a successful
`CHAT_REVIEW_PLANNING_RECEIPT` for this fresh synthetic root:

```text
/dev/shm/ipse-main-source-suite-b0oUKP/tmp/ipse-chat-review-planning-e463e0e1c9eb83133e3bb0746b8caef8
```

The receipt follows actual child exit zero and all final assertions: startup
planning, genuine native-reader exit, live normal/enclosing mode, exact
nomination and committed reply, protected capture, native acceptance, same-ID
normal reopening with ended session grants, and current accepted-decision
recall from a fresh chat. Strict Saved/source, committed link, accounting and
spent-handle assertions also ran. The same combined run subsequently produced
all four baseline chat receipts and the explicit-resume receipt.

This is a per-journey result. The surrounding
[source suite](combined-source-regression-20261104.md) subsequently completed
with 26 failures and 52 invalid cases; all frozen-input and complete path-set
postchecks passed. The subsequent
[focused repairs](focused-source-regression-20261104.md) close the failed cases;
a final combined regression remains open.

## Distinguish the next conversation step

The tested original conversation reopens idle and then exits. Its fresh-chat
recall does not establish a usable next prompt in that original conversation.
A subsequent source audit identified own-active accepted-source inspection and
historical root-transition gaps. A subsequent distinct
[first-follow-up repair and control](chat-same-id-followup-20261104.md) passes;
that result does not expand this original planning test's scope. This record also
does not implement assistant decision acceptance inside planning, qualify
installed/human/account use, or close P31I or P31E.
