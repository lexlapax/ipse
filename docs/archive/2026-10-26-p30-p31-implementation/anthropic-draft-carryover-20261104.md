# Anthropic text-only cancelled-draft carryover — 2026-11-04

This dated record qualifies a bounded P31I source/Session increment. Current
operator behavior belongs in [Usage](../../operator/usage.md#refine-a-request-before-submitting-it);
implementation and replay ownership belong in
[Workspace context](../../developer/workspace-context.md#withdraw-draft-intent-before-ordinary-work).
The broader [P31 acceptance](../../plan.md) remains authoritative. This is not a
live Anthropic account, native-terminal, installed-package or model-quality result.

## Problem and repair

Anthropic's adapter retains native content even for an ordinary plain-text answer.
The draft projector previously had no Anthropic policy, so cancelling that draft
could prevent the next ordinary request or saved reconstruction. The repair
admits only an exact native text-only/no-tool interval, keeps its original journal
records, and withholds that complete interval from later requests. Native history
before and after it remains unchanged.

`DraftNative` checks the native provider, optional model metadata, the existing
Stream item bound, exact text-block fields, valid UTF-8 and agreement with visible
text. Thinking, signatures, redacted blocks, tools, unknown fields and disagreement
refuse. `Draft` applies the existing prefix/segment/tail and tool-grouping checks;
`Saved` selects the same policy from the original saved provider during both
chronological and final reconstruction. No permission, dependency, native protocol,
provider route, bound or persisted schema changed. The adapter continues to use
the stateless [Messages API](https://platform.claude.com/docs/en/build-with-claude/working-with-messages),
not the separate threads API.

## Verification

The [safe fixture and counts](anthropic-draft-carryover-20261104/REVIEW.md) retain
an inspectable source patch and bounded execution summary. Thirteen pure controls
passed, including existing native Responses controls and negative Anthropic
shape/projection cases. Three isolated core modules compiled with warnings as
errors and no warnings.

Fresh synthetic Session execution 02 passed one selected test, with 20 unrelated
tests excluded, in 0.4 seconds. Four actual loopback Messages requests exercised
ordinary prior context, a private draft, cancellation followed by unrelated work,
confirmed close and same-ID ordinary continuation. Assertions checked exact
native earlier/later messages in request bodies, absence of private draft input,
proposal and model metadata on later wires, four known completed requests, original
private assistant bytes retained in the journal, strict Saved reconstruction and
idle no-dispatch. The complete normal SDK and the three explicitly loaded overlay
beam paths/digests matched before and after. Input entries were zero, no operator
input or paid request occurred, input hashes matched and no fixture process
remained. Synthetic state was retained. An independent no-App/no-native/no-provider audit
also restored the final journal, confirmed four completed requests and original
private draft retention, and verified unchanged bytes.

This result used the immutable normal SDK with runtime-manifest SHA-256
`616fa20b594c01a4cefe09e5d1269813e0c170fc7ac70828d87f933c1923a4f6`
plus three explicitly pinned candidate host modules. It is not qualification of a
later rebuilt main runtime. Subsequent current-source integration passed the
complete normal build, warning-free compilation, formatting, all 52 focused draft
tests and the credential-free demo. Canonical documentation checks passed with
1,193 Markdown files and 9,782 local links. The
[integration receipt](anthropic-draft-carryover-20261104/main-integration.json)
pins the five current source/test files; the test received a formatting-only line
wrap after the private run. The full source regression remains required. The raw
worktree documentation scan also sees unrelated retained fixture copies; the
canonical check used clean committed files plus these exact reviewed changes.

## Preserved failures and limits

The original pure run showed the missing live policy; it also exposed one test
construction error attempting to JSON-hash invalid UTF-8, which was corrected to
check the validator before JSON encoding. Execution 01 completed live
prior/draft/cancel/ordinary work but failed strict Saved reconstruction because
its separate saved-provider selector had not yet been extended. Its failure,
result and successful integrity/cleanup posts remain preserved. The existing test
removed that first temporary Session directory; no retained-journal replay claim
is made for execution 01. Execution 02 was fresh, not a replay or resume of that
failed fixture. A later source check also corrected a test completion literal to
the existing `completed` value before execution 02; it did not relax the required
four successful completions.

This closes one text-only Anthropic cancellation/carryover path. Tool-bearing and
opaque Anthropic drafts, other unsupported native providers, installed/native
terminal qualification and independent quality remain open. Assistant-proposed
planning decisions and retrieve-first notes/document clarification retain their
separate P31I requirements; operator-authored deferred decisions and explicit
post-exit saves keep their existing contracts. No failed cohort is relabelled a
pass, and unknown effects are never replayed.
