# Inactive original result lease — 2026-11-06

This dated implementation and verification record covers the internal
`Ipse.Session.StoredSources.with_result/3` helper. Current contributor guidance
is in [extension training](../../developer/extensions.md#consume-an-explicitly-selected-historical-result);
the [operator extension manual](../../operator/extensions.md#invoke-a-command-and-inspect-its-complete-result)
owns existing result inspection. The [plan](../../plan.md) owns remaining scope.
This helper checkpoint does not qualify public document restore, general backup,
protected input reuse, full capacity or a whole-source regression.

## Ownership contract

The caller separately authorizes an exact version-1 selection containing a
foreign Session ID and existing saved-result delivery descriptor. The helper
uses the consumer's history directory, requires the same canonical cwd and an
actually admitted project, and retains the inactive original's native OS lock,
file identity and source origin. It strictly reconstructs Saved, requires known
closed work and readable committed result bytes, and retains the actual target
ProjectIdentity around its callback. Its checked original-lock protocol is
Linux-only.

The callback receives bytes/value/delivery, the complete recorded output
dependency union, producing invocation intent, only that invocation's validated
action-result events, actual project binding and a same-process zero-argument
guard. That guard must confirm immediately before a target CAS. Postchecks,
file close and native unlock must also confirm before the callback result
returns. A post-callback error cannot establish that a target effect was absent.
The helper supplies neither an SDK operation nor permission, current source
eligibility, retry or automatic replay.

The existing Resources effect owner is entered before acquiring leases. Nested
distinct-original selections can reuse the actual held project capability;
copying its map cannot recreate that capability. Same-Session selection and
same-original reentry remain unsupported. Nonempty managed dependencies are
returned intact; the separate Restore integration currently refuses them.

## Actual focused qualification

The final command used normal-start Mix with `--no-compile --no-deps-check`,
`--max-cases 1 --trace --seed 826047`, selecting only
`test/ipse/session/stored_result_lease_test.exs`. It used an independent immutable
`2a56c60b` runtime with all sixteen application ebins and a strictly compiled
private StoredSources override. The entry and test-require wrapper verified
loaded/compiler object origins after Mix established its paths. No main or
frozen runtime BEAM was replaced, and no warning was suppressed.

Final attempt 07 passed **8/8 controls in 4.7 seconds**, under a 180-second outer
bound plus ten-second kill grace. Canonical Elixir 1.18.5/OTP27 formatting passed;
the isolated helper compilation on Elixir 1.20 produced no diagnostics.

The positive exercised an actual explicit operator command result, exact bytes,
complete source intent, held native original lock, nested distinct-original
selection, a nonempty v2 managed root-read union and the exact producing action
subset. Negatives covered active/same Sessions, changed descriptors and input,
wrong/unadmitted projects, forged held capabilities, copied/hardlinked journals,
torn/legacy/unfinalized sources, foreign/expired guards and killed lock owners.
All data and Sessions were disposable synthetic fixtures. No original notebook,
model, provider, terminal approval or global Input was used.

Primary, original exit, runtime and input postchecks returned zero. Independent
scoped host checks found the owned processes absent and group empty. This is
not a global Input-neutrality claim while unrelated actors run.

## Preserved earlier outcomes

| Attempt | Outcome and cause |
| --- | --- |
| 01 | 0/8: reversed Artifact.import fixture arguments prevented Session setup; no result lease exercised |
| 02 | 4/8: valid callbacks refused; stale Mix checker lookup warning preserved |
| 03 | Unsupported `test.loadpaths` task stopped setup before App/tests |
| 04 | 4/8: valid off semantic admission incorrectly refused; old lookup warning preserved |
| Diagnostic 01 | Sanitized function-return classes located the project check; 0/1 selected, no values/transcripts traced |
| 05 | 7/8, zero warnings: v1 read fixture had an empty dependency union, violating the nested positive's assertion |
| 06 | 7/8, zero warnings: explicit external precondition exposed that same fixture deficiency |
| 07 | 8/8 after using the actual v2 managed-read fixture; production helper unchanged from 05 and 06 |

The whole effect-owner correction was already present in attempt 04. Earlier
source/setup preimages and failed outcomes remain separate; none is reclassified
as passing. Existing managed-policy fixture and Knowledge.Contracts bytes were
equal to the frozen runtime copies used by the final check.

## Evidence commitments

| Item | SHA-256 |
| --- | --- |
| StoredSources production source | `3f9221496ad28efc5a63103c5e74b4fe717c01dec87faa19264afca369593589` |
| Focused test source | `ecb78c817967968ecd57392fc679e14e4d8580f2054726a2bff89202c0853b40` |
| Strictly compiled private helper BEAM | `a22023f446f82f590d79e14a35fb4613b434baef4fae8ff701b2b62967f64383` |
| Attempt 07 log | `6e019174606be3ffcc0af807f864a56396658ef3454bc91668f2bf85f297039c` |
| Attempt 07 status | `f60ea92591d8ca58f8a029627634291a93baaebf7b4c0bab499c48b1f7649644` |
| Independent scoped status | `c522f6a404628df6fac9382c467a8abd999e8859796cace69ea6d3a4ff5e4015` |

Private journals, values, raw logs and compiled files remain private. The
contributor chapter and overlapping operator extension chapter were reviewed
whole against the implementation; the operator chapter requires no new helper
procedure. Caller selection/approval, current validator provenance and actual
target publication remain separate integration gates.

The documentation checker passed across 1,254 Markdown files and 10,245 local
links with zero errors. A temporary Git excludes file restricted untracked
enumeration to this new archive record; tracked documents remained included.
This avoided unrelated historical fixture copies without changing the checker
or tracked documentation rules.
