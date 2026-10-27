# Independent P30C pure-policy audit and reporting correction

Date: 2026-10-27. Incremental audit of pure checkpoint
`3b5a64391b1bc4f5bed39c5f2faf79dcee0c7f2b`, followed by a documentation-only
correction. The [literal independent report](p30c-pure-policy-audit-report.md)
is preserved byte-for-byte at its pre-correction finding state. The
[corrected component record](p30c-pure-policy.md) and
[runtime receipt](p30c-pure-policy-runtime.json) are current. The
[plan](../../plan.md#p30-advisory-decision-engines) owns integrated acceptance;
the [developer chapter](../../developer/decisions.md#exercise-a-consumer-without-contacting-an-engine)
teaches the public pure API and its authority limits.

## Accepted finding and exact correction

Root accepted one P3 reporting finding: the author record claimed 12 new policy
tests, but the exact unchanged source declares and executes 11. The original
combined 55-test author result remains unchanged. The finding does not establish
a missing test behavior or a production correctness defect.

Corrected `checks.new_policy_tests` from 12 to 11 and the owning Markdown row,
retaining the original claim explicitly. The runtime status now points to the
completed pure review; added correction metadata binds the original runtime
digest, accepted finding, report/manifest and AST count. All other original
runtime values are unchanged. No production source, test, SDK/build artifact,
native helper, mode, permission or model selection was edited or rerun.

| Population | Actual evidence |
| --- | --- |
| Author's combined focused command |55 passed, seed 752530, 6.0 s; retained author result, not repeated by this correction or independent auditor |
| Exact owned policy suite |11/11 independently; seed 618204, 1.6 s |
| Fresh primary adversarial controls |12/12 first run; seed 508319, 0.02 s |
| Supplemental first run |1/2; overbroad assumption about harmless coherent pure-Plan metadata |
| Corrected supplemental controls |2/2; seed 407961, 0.02 s; original driver/log and correction retained |
| Fresh independent minimal SDK, actual artifact and child |Passed; all 3 delegates exercised without Session/Artifact/DecisionCall available |
| Original/copied declared code/runtime inputs |1383 byte-identical throughout independent testing and preservation |
| Correction control |Author AST-only parse confirms 11 declarations in unchanged test source; no test evaluation or native/model run |

The first supplemental failure expected an unused development qualification hash
change to invalidate pure data. Such coherent metadata grants no production
qualification or action permission. The corrected control changes the
request-bearing profile; that mismatch refuses. The literal report preserves
this harness correction, its initial generator error and one unused private
default-argument warning. None was hidden or relabelled a product fix.

The original filename `independent-baseline-12.log` came from the supplied count;
its bytes actually report 11 passed and remain intact. A separately retained
`independent-baseline-11.log` has the accurate name. AST declarations and actual
executed cases, rather than a filename or supplied receipt, establish the count.

## Frozen evidence and reproduction

Independent report SHA256:
`9b4c4c6e255bee15f30f4a197a742648d5b7bc8af31b8b9400ebf3741e75cee5`.
The archived literal copy has exactly that hash. Independent `files.sha256`
SHA256:
`aa15970f6d463331ba3b237f131b517da3da28f779f0b546cf0048b2aa692fa3`,
with 1835 retained payloads. Original 1383-input manifest SHA256:
`ed7b5142e7cc92516972155801fd8cce162e5da2fd24dd2ba81105e9c2d40797`.
Policy source SHA256 remains
`474ebedf74cb8aa229b09b417179043d680b24f7f21bba8d7807146007d1ea9f`;
owned test remains
`e616ce0d1069312cfb33660363730ab2f459ad787a2fc7ab6305397465105480`.

Durable independent evidence:

```
/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/independent-p30c-pure-policy
```

It contains literal before receipts, source/runtime/private dependency and
artifact bytes, full manifests, first/corrected drivers/logs and preservation
receipts. Original component SHA256 is
`1e5fe7969a871f4a11d0e87dae8b479d5481c8d286e5d990ff30f4939f3a578c`;
original runtime SHA256 is
`cfacdbbd91f8556025a41148690c4cfe50fac6beb17d361febd0b687140f0ae5`.
Both are also recoverable from the audited Git commit. Do not modify or execute
evidence in place. Copy into a fresh private working directory and follow the
literal report's exact reproduction procedure and dependency-link treatment.

Correction control and before/corrected runtime bytes are retained separately at:

```
/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/p30c-reporting-correction
```

`correct.exs` parses the exact source with `Code.string_to_quoted!/1` and
`Macro.prewalk/3`, lists each `test` declaration/line, requires 11 and checks the
unchanged source digest. It verifies that the decoded runtime differs only in
the count, status and explicit reporting-correction metadata. This is a count
and record-integrity check, not another execution of the policy suite.
`verify.exs` repeats those integrity assertions against the corrected bytes and
checks the literal report, independent manifest and unchanged policy/test hashes.
Its output, the documentation check and whitespace check are retained alongside
the correction control. The documentation check covers 531 Markdown files and
4,728 local links with zero errors; `git diff --check` also passes.

## Current scope and manual consistency

The complete current developer decision chapter was reviewed for count and scope
consistency; its hash remains
`5974ae49713e7c21acac707a1c60a366821f065f9def25073b40c326273c7ee0`.
Its procedures make no 12-case claim and still keep pure data, explicit dispatch,
protected helper admission and model quality separate. Operator extension advice
guidance likewise enables no automatic consumer. Their commands and limits need
no correction for this reporting-only change.

No production defect was found within the audited pure scope. This does not
establish a qualified strategy, managed-reader freshness, protected decision-v2
operation, actual Main-input replay runner, live account/model access, automatic
capture/recall or P30 completion. No fresh model/native/network work, full suite,
package, installed or platform verification ran for this correction. The
separately ongoing whole-source baseline and its findings belong to Root's own
verification record; no full-suite pass is inferred here.
