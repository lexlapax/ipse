section = fn text, first, last, replacement ->
  [before, rest] = String.split(text, first, parts: 2)
  [_old, after_text] = String.split(rest, last, parts: 2)
  before <> replacement <> "\n" <> last <> after_text
end
path = "docs/operator/knowledge-permissions.md"
text = File.read!(path)
text = String.replace(text, "Existing-note reads, permission\ninspection/revocation, forgetting and elapsed-policy reclamation remain separate.", "Reviewed forgetting and session-only suppression also refuse: a consumed\n30-second Review permit cannot fence the later rename. Existing-note reads,\npermission inspection/revocation and elapsed-policy reclamation remain separate.")
text = section.(text, "## Forget a selected native note", "## Reclaim an expired native note", """
## Forget a selected native note

`knowledge forget NOTE_KEY` is temporarily unavailable and refuses before native
review. A consumed Review permit can expire while storage is paused; reporting
unknown afterward does not undo a late mutation. `--yes` cannot bypass this gate.
This command starts no new review or mutation while the gate is active.

Preserve earlier management journals and inspect them without replay:

```sh
ipse knowledge operation COPY_THE_MANAGEMENT_JOURNAL_ID --cwd /path/to/project
```

An older `publishing`, unknown or missing result still requires actual storage
inspection. The new gate does not roll back earlier writes or erase original
Session/review journals. Follow
[protected recovery](recovery.md#inspect-unconfirmed-protected-knowledge).

## Change a selected native note's retention

All new retention choices currently refuse. `pin`, `automatic` and `duration`
remain blocked by the deadline gate; `session` uses the now-blocked reviewed
forgetting path. No existing policy is renewed or changed. Existing signed
choices remain readable, and dependencies cannot borrow another revision's
deadline. Inspect uncertain earlier choices with `knowledge operation JOURNAL_ID`
rather than retrying or deleting protected files.
""")
File.write!(path,text)

path = "docs/operator/recovery.md"
text = File.read!(path)
text = String.replace(text, "new pin/automatic/duration retention choices currently refuse", "all new retention choices and reviewed forgetting currently refuse")
text = String.replace(text, "Existing read/inspection,\nforgetting and elapsed-policy reclamation remain separate operations.", "Existing read/inspection and elapsed-policy reclamation remain separate\noperations. State writes carrying a strict `write_before_ms` also refuse before\nintent/IO. Preserve drafts; do not strip deadlines or switch stores to retry.")
text = String.replace(text, "Native forgetting prints a separate management journal ID.", "Earlier native forgetting attempts printed a separate management journal ID.")
text = String.replace(text, "Persistent lock files preserve inode identity.", "Persistent lock files preserve inode identity.\n\nA separate fresh-start header/lock ordering repair is under review. Do not attempt\na second writer for a newly visible journal while its first startup is incomplete;\na header alone is not confirmation that the original owner acquired its lock.")
File.write!(path,text)

path = "docs/operator/corpus.md"
text = File.read!(path)
text = String.replace(text, "A stage whose write approval waits beyond that\ndeadline refuses at its time checks; those checks do not provide a kernel-atomic\nclock-and-rename guarantee. Collection-backed strict-deadline stages are gated\nas described below. A check does not renew the draft.", "State and Collection stage writes that carry a strict deadline now refuse even\nbefore that deadline: the clock check cannot fence scheduling before rename.\nOrdinary small direct publications without a staged/trusted deadline retain their\nseparate approvals. Do not strip a deadline to continue a draft. The explicit\nCollection refusal code is `document_store_deadline_unavailable`; the State code\nis `state_deadline_fence_unavailable`. A check never renews the draft.")
text = String.replace(text, "State-backed and explicitly selected remote stores have separate authority", "Deadline-bearing State drafts are also gated. State-backed ordinary no-deadline\nwork and explicitly selected remote stores have separate authority")
File.write!(path,text)

path = "docs/operator/memory.md"
text = File.read!(path)
text = String.replace(text, "Approve an update while the existing note is still live. Remember and active\nimport proposals include `write_before_ms` in the displayed state request, copied\nfrom that note's expiry. If the note expires while approval is pending, approving\nthe proposal returns `source_expired` and leaves the old record unchanged. Ipse\ndoes not retry the renewal. Inspect or collect the expired note instead.", "Updates to an existing live target and active imports can require that target's\nexpiry as `write_before_ms`. Those deadline-bearing State writes now refuse even\nwhile the target is live: a clock check cannot fence the later rename. The\noperator receives the temporary State-deadline diagnostic; no mutation intent or\nwrite starts. Preserve the target and inspect older uncertain attempts. Do not\nremove the condition or silently switch stores to force renewal. Ordinary initial\nputs without a deadline and ordinary suppression/reads retain their separate\napprovals; this is distinct from the gated native `knowledge forget` command.")
File.write!(path,text)

path = "docs/developer/extension-state.md"
text = File.read!(path)
text = section.(text, "## Reject an expired prepared write", "## Page and bind storage deliberately", """
## Refuse deadline-bearing prepared writes

The optional `write_before_ms` remains a recognized absolute Unix-millisecond
field on `state.put`, so old requests/receipts stay interpretable. It currently
refuses all new writes before filesystem IO, including otherwise live deadlines.
The previous lock-held check and pre-rename check were separate from rename;
interposing the actual OTP file-server request after the latter check allowed a
successful late write. Do not treat that implementation as an atomic fence.

Session refuses the proposal before mutation intent with an actionable State
deadline diagnostic. The Core fallback returns exactly
`%{"code" => "state_deadline_fence_unavailable"}` as a failed outcome; its closed
validator permits no extra summary or claimed writer fields. No storage read or
write is necessary to construct that refusal. A private write backstop also
rejects a deadline-bearing request.

Ordinary puts that omit the field retain their approval and revision/generation
CAS. Omitting a required domain condition is not an authorized automatic retry.
Old `write_deadline_elapsed` receipts retain their historical clock-validation
contract, but do not prove a kernel-atomic check-and-rename boundary. Use
`test/ipse/extension/state_deadline_gate_test.exs` with `--only state_lifetime_gate`
for the current refusal/ordinary compatibility control; its separately tagged
diagnostic probe requires the retained vulnerable State cohort.
""")
text = String.replace(text, "Delayed approval after expiry becomes domain\n`source_expired` without another write. Inspect the real renewal/delayed-approval/\nresume controls before changing that translation.", "Those deadline-bearing updates now refuse before intent/IO even while the target\nis live. Earlier renewal/delayed-approval controls are historical and need\nintegration reconciliation under this gate; they do not establish current success.\nDo not remove the target condition to bypass refusal.")
File.write!(path,text)

path = "docs/developer/collection-sdk.md"
text = File.read!(path)
text = String.replace(text, "deadline-bearing\nretention/supersession before mutation staging", "Review-dependent\nforget/retention/supersession before mutation staging")
text = String.replace(text, "session-only suppression and elapsed-policy\nreclamation have separate paths.", "session-only suppression is now gated too because its consumed Review permit\ncan expire before rename. Elapsed-policy reclamation has a separate path.")
text = String.replace(text, "Follow `knowledge forget NOTE_KEY` into an owned Resources scope", "The retained, currently gated `knowledge forget NOTE_KEY` path used an owned Resources scope")
text = String.replace(text, "Original and management journals remain; no idle task or automatic", "Original and management journals remain; no idle task or automatic")
text = String.replace(text, "mix test test/ipse/extension/collection_deadline_gate_test.exs\n", "mix test test/ipse/extension/collection_deadline_gate_test.exs\nmix test test/ipse/extension/state_deadline_gate_test.exs --only state_lifetime_gate\n")
File.write!(path,text)

path = "docs/developer/knowledge-extensions.md"
text = File.read!(path)
text = String.replace(text, "forgetting and elapsed-policy reclamation retain their separate authority.", "elapsed-policy reclamation retains its separate authority. Native reviewed\nforgetting/session-only suppression is gated too; ordinary Memory State\nsuppression is a separate no-deadline operation.")
text = String.replace(text, "Native State checks it\nunder its lock and before rename. This is not a kernel-atomic clock-and-rename\nguarantee. Strict-deadline Collection publication is refused rather than treating\nthat precheck as an enforceable fence.", "Deadline-bearing State writes now refuse before intent/IO, just as strict-deadline\nCollection publication refuses. Holding the lock and checking before rename does\nnot make clock and mutation atomic. Ordinary no-deadline direct writes remain\nseparate; do not drop a domain deadline to retry a draft.")
File.write!(path,text)

path = "docs/developer/session-sources.md"
text = File.read!(path)
text = String.replace(text, "An explicit callback error before consumption grants nothing.", "An explicit callback error before consumption grants nothing.\n\n+These checks detect expired callback results; they do not undo an effect after a\n+permit expires. A real stopped transaction demonstrated late forgetting followed\n+by outer Review `unknown`. Review-dependent Collection forget/retention/supersession\n+and their public CLI routes are therefore gated before mutation (CLI before\n+review). A new strict final-effect contract remains unimplemented.") |> String.replace("\n+", "\n")
File.write!(path,text)
