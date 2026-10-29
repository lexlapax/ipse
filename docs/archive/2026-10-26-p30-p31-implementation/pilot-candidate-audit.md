# Inspectable synthetic capture candidates — 2026-10-29

This development-tool increment addresses an evidence gap in the original
[main-route pilot](index.md#first-actual-main-route-pilot): numerical proposal
receipts cannot support independent entailment or usefulness judgments. The
[plan](../../plan.md) still owns P30/P31 acceptance. This increment made no live
provider calls, downloaded no model and retained no actual model transcript.

The finite pilot now accepts an optional fourth audit callback. Its command-line
runner opts in through `IPSE_KNOWLEDGE_PILOT_AUDIT_DIR`, which must name a new
directory. It applies mode 0700 before opening an exclusive mode 0600 JSONL file.
The private sink receives exact validated synthetic source/candidate fields,
including empty candidate sets. Public progress retains numerical metrics and
fixed validation labels. Unrelated assistant prose, malformed proposals and
provider configuration are not added to the audit. The three-session/twenty-turn
workload, at-most-one-continuation rule, selected route and finite request ceiling
remain unchanged.

Each private row is bounded to 64 KiB and file-synced before another request.
An audit failure stops before continuation; the response already received is
still counted. This is not crash-atomic directory publication or a transaction
with a model service. Partial audits remain partial evidence. The new
[contributor chapter](../../developer/capture-pilot.md) teaches setup, output
ownership, failure accounting and semantic-review limits.

The [independent review](pilot-candidate-audit-independent-review.md) reproduced
an existing public-output defect: a rejected model-supplied category could retain
arbitrary text or JSON in public progress. The repair retains only fixed enum
labels and sets invalid categories to nil. The new regression checks both
progress callbacks and returned records for invalid string and map values. The
reviewer's post-repair counterexample confirms both leak flags are false and
that refusal still charges one request without continuation.

Final [focused verification](pilot-candidate-audit/ipse-pilot-audit-46994.log)
passed 14 tests in 0.3 seconds using a retained local runtime, synthetic providers
and temporary files. Controls cover opt-in/default behavior, exact candidate and
source fields, empty proposals, invalid-source withholding, callback error/raise/
throw, no continuation or replay on failure, exclusive private files, encoded
row bounds and the category leak repair. Earlier 12- and 13-test logs are retained
as development history; the frozen source identifies the final 14-test cohort.
The [CLI refusal control](pilot-candidate-audit/ipse-pilot-cli-refusal-46995.log)
exited 1 with confirmation absent, before configuration or model access.

Commands run for the final focused cohort:

```sh
ERL_FLAGS='+S 4' mix format dev/knowledge/pilot.exs dev/pilot-knowledge.exs test/dev/knowledge/pilot_test.exs
ERL_FLAGS='+S 4' ERL_LIBS=_build/literal-v4-ab-current2-sol-20261029/lib elixir -r test/test_helper.exs -r test/dev/knowledge/pilot_test.exs -e 'ExUnit.configure(seed: 46994)'
ERL_FLAGS='+S 4' ERL_LIBS=_build/literal-v4-ab-current2-sol-20261029/lib env -u IPSE_KNOWLEDGE_PILOT_CONFIRM elixir dev/pilot-knowledge.exs
```

The last command is an expected refusal, not a passing live run. The retained
runtime path is local evidence rather than a fresh-checkout build recipe. The
[manifest](pilot-candidate-audit/manifest.json) binds the final source snapshots,
logs, contributor procedure and relevant loaded host-module hashes. The
repository's normal focused test command is in the contributor chapter.

No aggregate source/package suite ran. Independent semantic labels, a newly
authorized main-route run with retained candidates, real validated main-tool
decision assessment, held-out evaluation, protected capture publication and
installed-user qualification remain open. No model quality or qualified consumer
is inferred from this development-tool repair.

The batched [documentation check](pilot-candidate-audit/ipse-docs-followup-46997.log)
checked 754 Markdown files and 6,327 local links with zero errors. It reported
permission warnings for retained private ledger directories; their permissions
were not changed. The new contributor chapter and audience entry points were
reviewed as whole documents. Scoped formatting and repository diff checks passed.

The later [usage-privacy correction](pilot-usage-privacy.md) supersedes the broad
content-free progress claim for raw provider usage: that field could contain
attribution content and is now normalized. This record and its source/manifest
identify the original `163901b` cohort; the later correction preserves them.
