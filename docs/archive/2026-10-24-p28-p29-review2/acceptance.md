# Qualified v0.1.0 readiness acceptance

Historical decision record, 2026-10-24 Pacific (2026-10-25 UTC). The developer
selected **“Accept candidate with documented qualifications”** in this task after
being offered that choice or another independent review. The question explicitly
excluded authorization for tagging or publication. The [plan](../../plan.md)
owns current milestone status; the [handoff](release-readiness.md) owns the
remaining release actions. Earlier independent verdicts retain their original
scope and result.

## Accepted scope

The repaired runtime/verifier candidate is `45cae30bd7aeab332a1c0821f43d6ec53b8a8406`.
Documentation/evidence head `bde0777c70c9f63c14be11e09f968c823fc75010` has identical
runtime, native, configuration, dependency, developer-tool, test and workflow
source. Its [final CI run](https://github.com/lexlapax/ipse/actions/runs/40157034608)
completed successfully on both platforms:

- Ubuntu: 1,803 tests, zero failures, 36 excluded.
- macOS: 1,768 tests, zero failures, 36 excluded, one skipped.
- Separate macOS native checks: 36 tests, zero failures, six excluded.

All required job steps passed; conditional skips retain their actual status.
The [CI metadata](accepted-head-ci.json) records the exact head, jobs and steps.
The earlier [verification receipt](verification.json) owns the candidate's
complete manual rehearsal, collected archives and checksums. No new runtime or
workflow change is introduced by recording acceptance.

## Qualifications retained

The fresh-account Linux walkthrough was assisted. There is no human macOS or
human upgrade walkthrough. The developer accepts these qualifications for
release readiness; the original unassisted criterion is not relabelled passed.

Grok live API inference remains unverified after HTTP 403. Subscription OAuth
requires an approved Ipse client registration and live eligibility verification.
Gemini foreign-history live acceptance remains unverified. Existing fixture and
installed checks do not establish these live results.

The earlier independent review rejected `c2a19cb`. Repairs, the requested author
adversarial review and subsequent tests are recorded separately; this decision
is developer acceptance with qualifications, not a new independent verdict.
The documented short-private-MCP-value collision remains a known fail-closed
limitation.

## Remaining release actions

No stable tag or release publication is authorized by this decision. Select and
inspect the exact release commit, then obtain authorization for the stable-tag
action. After its workflow completes, inspect the unpublished draft and actual
remote assets before a separate publication action, following the
[release handoff](release-readiness.md#remaining-release-actions).

During cleanup, the developer confirmed they had made no manual edit. The
uncommitted `docs/operator/usage.md` change split a sentence with `/exit`; it was
restored to the committed text. The untracked local `.claude/settings.json` was
preserved without reading its contents and excluded only in this checkout's
`.git/info/exclude`. Neither item enters the release commit.
