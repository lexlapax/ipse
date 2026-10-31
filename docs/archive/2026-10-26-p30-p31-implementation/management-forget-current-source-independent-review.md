# Public forget on the fresh host — independent integration review

Scoped read-only review, 2026-10-29, of
[the current-source control](management-forget-current-source.md), following the
[public caller review](management-forget-public-independent-review.md) and
[complete-host/held-reader checkpoint](document-held-reader-independent-review.md).
The [plan](../../plan.md) owns acceptance.

Disposition: accepted as one actual public CLI/native forget integration on the
declared fresh host/helper and selected rebuilt package. No new blocker was
found. This is not an installed-user/package, original assertion authenticity,
capture, full-suite or non-Linux qualification.

## Exact ancestry checked

Verified manifest SHA-256
`9cf92a186e19fb99a7c7d3fd7b9977e18d3bd5338d60ad064aa23e79ecaf9322`
and all 28 entries, including source/runtime archives, inventories, old/current
artifacts/catalogs, retained fixtures/driver/logs, three CLI BEAMs, helper and
copied journal. The [verification script](management-forget-current-source-review/verify.exs)
and [result](management-forget-current-source-review/verify.log) record the checks.

All 217 regular source-tar members equal the actual fork. Its 213-row source hash
list matches its listed members; `.formatter.exs`, `LICENSE`, `mix.exs` and
`mix.lock` are not separately listed there but are bound by the manifest's whole
tar hash and were independently compared to the actual fork. The additional
package inputs comprise eight package source/build files and the license.

The unchanged `base-source.sha256` exactly equals the original 208-input host
snapshot. Against that pre-reader snapshot, actual source differences are only
Collection's accepted reader overlay and Management's public wrapper/comment.
The Collection source and BEAM equal the accepted held-reader cohort. Against
the reviewed public Management source, only the obsolete private/gated comment
changes; CLI/Knowledge source matches the reviewed public files.

The runtime archive exactly matches all 668 regular compiled-runtime files plus
39 private-asset files in the actual fork. Both inherited runtime symlinks match
the accepted reader. Comparing every ancestor regular file finds only the three
recompiled CLI BEAMs and selected bundle catalog changed, plus ten new current
artifact files. Runner, Collection, NormalizerV3, ProjectIdentity/DomainAuth,
ObservedRead, ReadView and other host modules remain the fresh compiled reader
base, not a silent old-host overlay. The helper is exactly
`40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02`.

Verified current artifact manifest
`578cd2ade037601ee7f17a2b69f901d116efc664369459e53d9be566cdf317fc`
against its selected catalog and every declared file's size/hash. The preserved
old artifact is separately bound as
`e7197bccd90590e89c584e33c41c2fb1dbd34765a3a4f3fbdbe214b98cf9b5ec`.
Both archives match their actual graph assets. This verifies retained source,
artifact and runtime identity; it is not an independent deterministic rebuild.
The package builder enforces empty compilation diagnostics, but no separate raw
package/three-module compiler log is pinned in this receipt.

## Failed seed and distinct positive

The first raw log fails at trusted synthetic initial publication with
`project_domain_initialization_unconfirmed`, before public review. Retained
read-only inspection finds prepared Identity domain metadata, no Collection root
and no management journal. No-root does not mean no effects: the prepared domain
is real retained uncertainty. That original operation was not replayed.

Source and sidecar comparison supports the stated cause: the inherited earlier
bundle declares a different note constraint hash, schema and origin policy from
the native-assertion fixture; the current normalizer requires the actual recipe
and constraint hashes to agree before mutation. Retained pure comparison reports
the old policy refusing and the new policy accepting the fixture. This is a
supported explanation, not a separately emitted inner normalizer diagnostic from
the failed run. The raw failure exposes only the outer unknown.

The positive uses a distinct fresh private root, a newly built current package and
its actual selected catalog. Comparing the two retained fixture versions finds
only the addition of the selected sidecar's note constraints alongside its already
selected recipe. No policy check, signature/source predicate or old result was
weakened. The initial synthetic seed remains trusted fixture construction, not
automatic protected capture acceptance or genuine original operator assertion.

Retained actual `Ipse.CLI.run` output prints the journal ID before full facts,
accepts the fresh native challenge, reports settled forget and observes the target
absent. Actual `knowledge operation --json` reports the same journal/control
settled with `replayed: false`. The copied journal has one matching intent and
one settled result. Existing one-use Review, reducing signed CAS, cleanup and
unknown handling retain their independently reviewed implementation. The current
host control adds no model request or retention/supersession/capture activation.

The exact executed fixture is the retained pre-format version; the later blank-line
format correction is not retroactively substituted. Original homes, signing keys
and final stores are not archived. Copied journal SourceOrigin still identifies
the original temporary path/inode; its relocation is not a new authenticated
live-origin inspection. The supplied source assertion is synthetic/unavailable,
and native output/process success does not establish human observation.

No runtime tests/effects, model calls or source edits were repeated by this
review. Broader public loss schedules, installed distribution, coherent current
package/source regression and remaining P30/P31 acceptance remain separate.
