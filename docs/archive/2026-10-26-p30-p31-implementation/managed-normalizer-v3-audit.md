# Independent NormalizerV3 component audit

Date: 2026-10-27. Disposition: **no actionable finding in the scoped candidate**.
This audits the new host-private NormalizerV3 interpreter. It does not qualify
the truth/origin of shaped source receipts, actual Collection publication, SDK
integration, current-read authority, adoption, annual lifecycle or P31 acceptance.

## Frozen source and runtime

Owner graph: /tmp/ipse-normalizer-v3-component-20261027-03. Independent copy:
/tmp/ipse-independent-normalizer-v3-20261027-01. No rebuild or product edit was
performed. Copied BEAMs retain the original private compile origins, which are
recorded individually rather than called a fresh whole-app compilation.

| Bound input | SHA-256 |
| --- | --- |
| NormalizerV3 source | d350e477e59783af8153239a19c57014de5d04941cfc0f75084d13d6d4461184 |
| Executed NormalizerV3 BEAM | b4f311f352a4482729706ed3204413c1aea38c5cde31082b0ae461aa76cd9248 |
| Owning nine tests | 8d4bafe3543a9461840149112e409f6908b82b9d54a21cccbe0e065c98aa1c23 |
| Owner 4060-entry source/build/link manifest | d75c1b8feea8c723105a46a55b2ec5ebf4c78964826a30024b359b5cfa0f20c9 |
| Independent 2346-row regular runtime manifest | 26e8026a258f2ca2fec3d610480070228516aa1066aeb56f4f990c81b692bfc3 |
| Final ten fresh audit tests | 5b8f8d9d3939df11875081e445aa17c272ab958c6781a4f0e28bd71c5f650bd5 |
| Initial eight fresh tests with over-specific expiry expectation | a8b301ab480287744e647ab078e88e8fa2d9fe2834f8d95e23678f4ee7bbe15f |
| Actual source/BEAM/helper verification report | 271c3f3bf0a6541fa5f8084cf8e03664ecb3a7209b4d13b4b061158ed72f1d1a |
| Selected private helper | d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b |

The four bound runtime modules are NormalizerV3, ManagedPages, ProjectIdentity
and DomainAuth. Their exact source bytes match the copied sources and executed
audit-path BEAMs. Origins span the owner's Normalizer graph, its ManagedPages
base and earlier integrated baseline; runtime-check.json records those facts.
Identity/DomainAuth and Directory are earlier authored components of this auditor
and are used here, not newly claimed as independently audited implementations.

Every owner 4060-entry regular/link row, including its admitted Git metadata,
was verified against the original owner graph and independent copy after tests.
The independent execution manifest separately excludes Git metadata, aliases and
the declared Mix execution cache: all 2346 regular project/build rows and their
membership stayed unchanged. At final verification even the owner's execution
cache matched again. External dependency aliases were not followed; actual
dependency BEAMs and helper bytes are present in the copied build/project.

## Static scope and findings

Read the complete NormalizerV3 module, all nine owning tests and fixtures, its
component record/results, and the relevant ManagedPages/Planner authentication
and geometry interfaces. Checked the following:

- Closed options, exact request/recipe/constraint digests, one revision-zero
  fixed-prefix public insert, source membership and override/public/live absence.
- Prepared catalog plus actual absent witness for initialization; active catalog
  and authenticated exact format on present roots. Missing/unsigned metadata
  gains no format-adoption or resealing authority.
- Semantic anchor/live lookup and both local plans bind root summary, native
  root state/hash and manifest; selected values authenticate exact references,
  operation/revision context and selected range. Nonsingle page minima remain
  checked before update; an authentic tag alone does not establish geometry.
- Literal and proposal clocks remain distinct. Exclusive deadlines, retained
  earlier baselines, persistent relabels, future/rollback clocks and safe-integer
  overflow refuse renewal or malformed output. Proposals remain never-current.
- Existing public/live records, overrides, stored choice/retirement and unsupported
  operations refuse. Old operation/revision or body corruption cannot be relabeled
  into newly authenticated data.
- Held read costs plus a separate local 32-unit ceiling, at most five sidecars,
  four nonnull values, one exact-revision deletion, 6144-byte values and a
  2048-byte exact metadata receipt. First format creation is included in the cap.

No repair is requested. Catalog key/fence fields are structurally checked, but
the opaque capability does not expose a catalog-comparison API. The documented
caller prerequisite is the actual matching Identity callback catalog and cap;
substituted well-shaped labels are not authority. The host must enforce that
prerequisite and actual consent/source/C witness provenance. This audit does not
reinterpret arbitrary callback JSON as evidence or hostile same-VM containment.

## Independent execution

Final **29/29 pass**, seed 20261208, 7.0 seconds, Elixir 1.20.4 / OTP 29:
the unchanged nine NormalizerV3 tests, ten unchanged ManagedPages tests and ten
fresh audit cases. Identity admission, namespace preparation/activation and tags
are actual protected native operations. Collection records/witnesses and source
members are explicitly trusted synthetic fixtures: **zero Collection publications**.

The fresh held-read fixture was independently implemented around Directory with
an atomic shared 32-unit counter. It is not an actual C lock/witness or a cache
bypass. F.options/seed from the owning fixture provide recipe and signed synthetic
page construction; this reuse is explicitly separated from the fresh counter and
assertions. Fresh controls cover:

- Retained first/deadline at 199/200, refusal at the exclusive boundary, rollback
  to before first, and persistent-category relabel without renewed lifetime.
- Negative, floating and maximum-safe clock/overflow cases.
- Separate proposal first/deadline, unchanged literal clock and never-current tag.
- Changed verified source membership, wrong recipe binding, malformed/extra catalog
  fields, integer version, format and state controls.
- An otherwise valid 19-unit initialization with 13 units already spent succeeds
  exactly at 32; 14 already spent refuses at the held limit.
- A coherent different root introduced at the repair-plan lookup refuses.
- Foreign-process, after-callback and actual 5010ms-expired capabilities cannot
  mint a successful normalization. First-use expiry leaves outer initialization
  unconfirmed, not a known completed publication.
- A signed empty zero sentinel with a successor cannot fabricate absent lineage.
- Correctly signed same-namespace pages from another protected project fail
  authentication under the actual current project's capability.

The unchanged owning maximum case also reproduces the 24-unit exact-minimum
anchor shrink/redistribution plus live split: five extras, four values and one
retained-revision deletion. This is synthetic held geometry with real tags, not
an actual C publication or independently repeated annual arithmetic.

Actual Elixir 1.18.5 / OTP 29 independently formatted the exact production and
owning test files unchanged, then compiled one production source/one module with
diagnostics []. No ExUnit run on 1.18, OTP-27 or platform expansion is claimed.
No provider, model, PTY, credentials, gold or qualification data was used.

## Preserved failures and limits

The first independent run was **26/27**, seed 20261207. The sole failure expected
the lower-level project_domain_callback_expired reason from a first-publication
Identity call. Normalizer already correctly refused the expired capability;
Identity intentionally maps first-use uncertainty to
project_domain_initialization_unconfirmed. The initial source and complete log
are preserved. Only that outer expected reason was corrected; two additional
signed geometry/project controls were added. No production repair or inner
Normalizer assertion was changed or weakened.

The owner's original Elixir-1.18 parse-error source is separately preserved:
/tmp/ipse-normalizer-v3-component-20261027-02/artifacts/first118-harness-parse-error.exs,
SHA 8e7bc8cb2ab9c4369a0b3a257fb09898b652adfe5924efe079169ca5c0f8dbd3.
Storage confirmed no standalone original error log was retained: the original
tool output reported undefined variable files / CompileError at line3. That
missing raw log is not reconstructed or claimed present. Corrected successful
owner verification logs remain distinct from the failed source.

SDK-v3 reservation, actual C/Identity first-root outcome binding, deferred
accounting settlement, current source authentication and native dispatch remain
separate integration work. Stored typed choices, retirement, adoption/import,
current-read inverse and physical/annual lifecycle acceptance are out of scope.
Reproduce only in a new private working copy, never by executing or modifying
owner-only durable evidence in place.

## Durable audit and owner preservation

The preceding report is the literal independently preserved `working-copy/REPORT.md`,
SHA-256 `ea00f50923fdfb72344f98c30b00e52ed5de9aac20b69d1031ea3bc519d38012`.
The [component record](managed-normalizer-v3-component.md) owns the author's scope;
the [plan](../../plan.md) owns milestone acceptance. Actual Collection/Auth
integration subsequently authored by Storage is separate from this audit's
synthetic held observations and must retain its own exact source/runtime binding.
Its tests are not part of the independent 29-test count above.

Evidence base:
`/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification`.
Both preservation runs checked complete source/destination bytes, lengths,
hashes, actual ownership, data mode `0600`, directory mode `0700`, all admitted
input rows and file/directory fsync. They did not chmod originals or follow aliases.

| Evidence subtree | Payload manifest | Provenance | Preservation receipt |
| --- | --- | --- | --- |
| `independent-normalizer-v3`, 2539 files, 2346 regular runtime rows | `3c5cb9bfddfecd5a341dd4d2f2008a3dec61c9fea03ebac2d39752e5602fb769` | `be46fc1fdb50a3250384a8df036bca123b79c88f1257372df31b630804bcc22d` | `734f7bfb6a309926aa4f834137b73d43937d53c96564ae1417db5f2c2318a3c7` |
| `normalizer-v3-owner`, one full graph, 4064 regular graph paths mapped to 4053 complete unique byte blobs | `daaec48a5538f3c6f3748a4c39f77dea907ee4325570697e519a31b3751ed93c` | `0edf690b6181e15bd609f48e9386193ce1a91df2c9a3597dfc39b81fd9aa375a` | `e97f997ca37b14bdbcf0c44ead9a941ca762caeba0f2919bba8c762a60d2f32d` |

The complete owner graph retains production/test sources, all runtime BEAMs,
private helper bytes, author test/strict/format logs and strict-1.18 output. Its
4060 admitted regular/link entries were verified against the pre/post owner
manifest. Unlike the independent execution manifest, that owner manifest includes
regular Git metadata; it is preserved strictly as data without Git commands.
The three literal aliases are inventoried without following them. Per-graph
manifests map every regular relative path, length and original mode to a complete
SHA-addressed blob, with deduplication only after full byte equality and a final
recheck of all original files and copied blobs.

The external owner freeze verifier, final Elixir-1.18 verifier and original failed
verifier source are separately inventoried. The original parse-error log was
not retained by its author; the report explicitly identifies its tool-transcript
provenance rather than reconstructing a raw log. The independent first 26/27
failure and corrected 29/29 source/logs are both retained in full.

Reconstruct evidence in a new private working directory, verify blob hashes and
lengths, then restore only working-copy executable modes and necessary verified
aliases. Never execute or modify owner-only durable evidence in place.
