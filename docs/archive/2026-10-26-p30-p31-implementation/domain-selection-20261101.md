# Select first-use authorization under the retained Identity owner

Dated **2026-11-01**. Author investigation and focused repair on top of
`a90a2e53391b474845f267277e24517e3346f200`. This is historical engineering
evidence, not an independent review or P30/P31 acceptance. Current contracts
belong to [persistence](../../developer/persistence.md#keep-project-domain-attestations-private)
and [the Collection SDK](../../developer/collection-sdk.md#follow-one-capture-across-its-owners);
the [plan](../../plan.md) owns remaining delivery gates.

## Failure and cause

The complete frozen `f44b63c` suite failed the required positive
`competing V3 saved-consent Sessions cannot both publish at 63 pending records`:
neither contender succeeded when one success was required. The retained root
`/tmp/ipse-collection-sdk-8a14ab945fd49b91f3a930aec5dbd1c7` contained only the
initial settled operation. Inspection found no exhausted operation/input/output
allowance. Limits were eight operations and 100,000 input/output bytes; initial
reserved input/output were 28,902/16,384 bytes and actual input/output were
4,235/16,384. No limit was raised to address this failure.

An isolated current-source run at `a90a2e5` passed, seed 791659, in 14.8 seconds.
That sporadic pass did not establish a repair. The unchanged selected test
against the frozen `f44b63c` host failed with zero successes, seed 791660, in
5.0 seconds. A separate bounded return-only trace on that frozen host reproduced
the failure, seed 791661, in 5.2 seconds. One contender returned
`project_identity_unavailable`; the other passed source/policy planning but
returned `collection_domain_refused`. Neither reserved a publication effect.
The trace recorded no arguments, complete maps or private domain keys. These
old-host/new-launcher comparisons are diagnostic, not current-source qualification.

`ManagedCollectionCall.protected_v3/2` separately probed the active domain, then
set initialization from `existing != :active`. A busy/error result could make
an already active domain look fresh. Its later authorizer then required native
absence from populated storage even though Identity had selected the active
domain. This preliminary probe was outside the publication's retained transaction.

## Repair and controls

`ProjectIdentity.with_domain_publication/6` now also accepts a trusted
two-argument authorizer. It constructs the domain candidate under the retained
Identity owner and passes `(binding, fresh?)` before persisting prepared state.
Denial writes no domain state. Existing one-argument authorizers still run
before selection, preserving their original attempt and one-use permit ordering.
This uses the existing pure `DomainAuth.prepare/3`; it introduces no new protocol,
retry, dependency, helper change or larger limit.

The new-v3 caller explicitly permits initialization but removes its preliminary
verifier. It checks sources/policy and requires actual native absence only for
the authoritative fresh selection. The retained native Collection absence,
prepared-state refusal, actual first-completion witness, Identity activation
and deferred settlement remain mandatory. An active domain still needs its
authenticated format and cannot silently adopt an absent or unsigned store.

Four new `domain_publication_selection` controls failed against the unchanged
runtime, seed 791662: zero passed, four failed, 24 excluded, 1.3 seconds, exit 2.
After implementation they passed, seed 791663: four passed, 24 excluded,
1.5 seconds, exit 0. They cover first versus active selection under Identity,
denial without writes, stale binding, prepared refusal, preserved legacy ordering,
and a real held Identity owner followed by a new active publication. Additional
closed-scope and initialization-disabled assertions preserve refusal before the
new authorizer. Their root witnesses are trusted Identity fixtures; they do not
establish actual Collection or Session provenance.

The separate existing registered two-writer positive retains its exact
one-success expectation, real Collection effect and loser no-replay assertions.
The following cohorts ran serially, with no competing native/Mix/build cohort:

| Current-source selection | Seed | Result |
| --- | ---: | --- |
| Complete domain-auth module plus registered competing publication at line 3163 | 791664 | 29 passed, 166 excluded; 28.9 s; exit 0 |
| NormalizerV3 integration, existing Identity and held-binding modules | 791665 | 62 passed; 69.5 s; completed log |
| `registered_capture_sequence` | 791666 | 2 passed, 165 excluded; 62.6 s; exit 0 |
| Complete Knowledge Session module with accepted recall and accepted approval enabled | 791667 | 6 passed, 9 skipped; 143.9 s; exit 0 |
| Final domain-auth module plus registered competing publication, including closed-scope/disabled-initialization assertions | 791668 | 29 passed, 166 excluded; 28.9 s; exit 0 |

The repeated-capture positive saves 27 candidates through 54 actual synthetic
adapter requests across separate Sessions, crosses a nonzero live split fence,
settles accounting and checks recovery. Its companion refuses legacy-reader
access to an existing managed namespace. These are repeated additions, not
elapsed retention or annual turnover. Real account inference was not used.
The Knowledge cohort also follows actual public native acceptance into recall,
tool approval and reducing management, with its distinct source-loss controls.
Its log is `/tmp/ipse-domain-selection-native-knowledge-20261101.log`.
The final domain log is `/tmp/ipse-domain-selection-final-domain-20261101.log`;
its competing root is `/tmp/ipse-collection-sdk-f68c5ab577c0c699f31c1d6a04244591`.

## Evidence locations and limits

The final source build passed (183 host modules and three inert bundled
artifacts). Whole-checkout formatting, strict compilation, CI action-pin policy,
the documentation checker, isolated credential-free demo and CLI help all
exited 0. Documentation covered 1,015 Markdown files and 8,417 local links with
zero errors; Git discovery emitted permission warnings for existing private
receipt directories, whose contents were not inspected or changed. The whole
persistence, Collection SDK, knowledge-storage, operator knowledge-permissions
and recovery chapters were reviewed; current callback ordering and metadata
versions are integrated into their existing explanations. Audience indexes
retain the same topic ownership. No packaging code changed or package was built.

Check logs use `/tmp/ipse-domain-selection-` followed by
`build`, `format`, `compile`, `ci`, `docs`, `demo` or `help`, then
`-20261101.log`. The [selected-input receipt](domain-selection-20261101.json)
hashes runtime/test inputs and the retained logs after their runs. It is not a
prelaunch freeze or complete loaded-runtime inventory.

Diagnostic launchers are `/tmp/ipse-competing-v3-frozen-baseline-20261101.exs`
and `/tmp/ipse-competing-v3-frozen-trace-20261101.exs`; their matching `.log`
files preserve both failures. Classified trace returns are in
`/tmp/ipse-competing-v3-frozen-returns-20261101.log`. The sporadic initial pass is
`/tmp/ipse-competing-v3-current-baseline-20261101.log`.

New-test before/after logs are
`/tmp/ipse-domain-selection-{baseline,fixed}-20261101.log`. Current cohorts use
`/tmp/ipse-domain-selection-domain-and-competing-20261101.log`,
`/tmp/ipse-domain-selection-identity-storage-regressions-20261101.log` and
`/tmp/ipse-domain-selection-repeated-capture-20261101.log`. The repeated test
retained roots `/tmp/ipse-collection-sdk-593c1e76ba14951973f5ff4b66cee948`
and `/tmp/ipse-collection-sdk-27e5c1f321236af224a708e2c664bbef`.

The available environment is Linux `7.2.11-arch1-1` with the qualified tmpfs
profile. These checks establish no macOS, newer-kernel Btrfs, reboot durability,
human journey, real-model quality or installed package result. The
[complete baseline](full-suite-20261101.md) remains 3,653 passed and 54 failed
at its frozen revision; focused later passes cannot be subtracted from it.
Broader positive integrations, full C0, capacity, lifecycle, whole-source
qualification and the final audit remain open.
