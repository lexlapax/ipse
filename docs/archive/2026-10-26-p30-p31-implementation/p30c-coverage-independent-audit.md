# Independent P30C coverage follow-up review

Review dated 2026-10-28. This is a bounded read-only audit of the current pure
`DecisionPolicy` and its untrusted-facts tests, following the earlier
[coverage repair](p30c-coverage-followup.md). It is not the P30C integration or
milestone adversarial audit. The [plan](../../plan.md) owns acceptance.

The review traced eligibility and completeness bypasses, aggregate byte/count
consistency, pack membership and UTF-8 allocation, zero/one-alternative and
production zero-call behavior, plan reconstruction, result validation, refusal,
probability/margin handling and baseline mapping. No concrete incorrect non-null
selection or forbidden request was found in this scoped review. In particular,
incomplete/unavailable facts clear the baseline, a fitting aggregate without
all rows yields a gap, a nonempty set without a pack yields no selection, and
fitting complete rows bypass the engine and retain all supplied rows. Valid
decision choices map only to their admitted pack; malformed results use the
previously established baseline. This is a source analysis of untrusted data
contracts, not independent authentication of their content.

An [adversarial grid](p30c-coverage-independent-audit/ipse-p30-pure-audit-20261028.exs)
ran 2,592 combinations of availability, coverage, eligible aggregates, UTF-8
allocation, budget, strategy and planner mode. The [corrected run](p30c-coverage-independent-audit/ipse-p30-pure-audit-20261028-r2.log)
accepted 2,160, rejected 432 contradictory/invalid cases and constructed eight
development requests. It checked null/no-call gaps, production and strategy-none
zero calls, fitting-set preservation, byte bounds, permitted pack mapping and
malformed-advice fallback. The [first run](p30c-coverage-independent-audit/ipse-p30-pure-audit-20261028.log)
failed because the audit harness compared a complete receipt to a partial map;
the corrected harness uses a matching pattern. No production code was changed.

The [hash list](p30c-coverage-independent-audit/hashes.txt) identifies the current
policy/test/SDK source, the host SDK BEAMs used from the private
`_build/managed-mcp-current-20261028` graph, the corrected script and both logs.
The audit loaded the policy from the working tree; this is not a separately
frozen full-source build or an installed-artifact test.

Actual host-derived coverage/allocation, current source and permission checks,
protected helper admission, main-tool candidate provenance, replay/shadow
experiments, benefit evaluation and installed/live-service qualification remain
open. The planner explicitly labels its facts untrusted and does not itself
authorize any decision request or resulting effect.
