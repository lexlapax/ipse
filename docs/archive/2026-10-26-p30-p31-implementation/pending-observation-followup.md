# Pending proposal observation foundation

2026-10-28. This uncommitted internal component supports future protected review;
it does not implement a review workflow, acceptance, current eligibility or
P31 completion. The earlier [literal observation](record-observation-followup.md)
remains separate.

`Collection.ObservedRead.managed_proposal/6` requires an active matching V3 domain
callback and a reviewed `pending.` proposal recipe. Under one checked Collection
view it reads the public record and signed format, derives and checks the
proposal identity from its stored proof-shaped data, refuses an override at the
recipe-selected prefix, and verifies the signed live and anchor rows against the
same witness. It checks value and recipe hashes, historical policy digest,
pending eligibility, category and bounded clock consistency. It returns a
historical record observation and metadata; it does not authenticate the source
proof anew, check live consent or time, display a card, authorize acceptance, or
track later descendants. The view and witness cannot supply a later send or
publication barrier. Other pending formats, overrides, retirement and typed
management remain outside this operation.

An actual private-helper V3 publication control observed a proposal against
its signed pages and checked root, rejected a changed recipe, rejected a
same-view override, and rejected a subsequently altered public value. It uses
synthetic authorized source members and direct test-only writes for the
counterexamples, not real Session Consent or a human review. The initial
focused version passed (46612); the strengthened control passed (46613), and
the signed-publication, observation and read-view selection passed 65 tests
(46614). A subsequent focused control explicitly demonstrated that the stored
worker-supplied expiry differs from the host-signed deadline (46615); consumers
must use the authenticated metadata and recheck current time. The available-host
test-only helper remains unqualified for production
storage. The earlier full diagnostic snapshot predates this component; the
later running corrected snapshot includes it but predates the Session test below.

The separately built Knowledge worker and a saved-consent Session also exercised
publication and observation together. After the Session publishes a pending
proposal, the test reconstructs its saved source window, checks the signed
observation against the actual project domain and revalidates the stored proof
against that window. An altered proof is refused and the signed deadline matches
the publication receipt. The synthetic unattended input and PTY cases passed
on the private diagnostic helper (seed 46623); the test file SHA-256 was
`c7c199453b0ddd5d84fd75bfb8aab9118c353552768bc8a76d39e6c8b3ce7d21`.
The reconstructed window belongs to the same idle Session. This does not
authenticate an external current source, establish cross-session authority, or
hold a lock through display or dispatch.

The same integration now also constructs an in-memory redacted version of that
reconstructed index and confirms that it refuses the stored proof. Both parent
cases passed again (seed 46624); the updated test SHA-256 is
`f60b72265c778c12e4e2dcf354206e671a504641b5765b12eadfa8bfdd6aa1b3`.
The redaction is a test operation on the reconstructed value, not a durable
journal mutation or a demonstration that another Session selects the live index.

The real-worker Session fixture now also copies its synthetic session
directory while the owner is idle. `Journal.load`, source-page validation and
saved reconstruction succeed for both directories, and the same stored proof
revalidates in each. Both parent cases passed before formatting (46634) and
after formatting (46635). The current test SHA-256 is
`c3bb7895c5caf540ed3dfb441081ca16249146cc99429fe9103b74d6165bd390`.
This demonstrates ambiguous candidate locations with real saved test files; it
does not test a durable redaction, a live source selection, a hostile concurrent
copy, or protected rollback detection.
An added assertion then redacts the original reconstructed index in memory and
confirms that the unchanged copied index still accepts the proof; both cases
passed (46636). The resulting test SHA-256 is
`b99b05ceb2cd433039f6d668207067bae2af2426b8db024356e593038aaae690`.
The redaction remains in memory and is not a durable journal operation.
The same copied-source and in-memory redaction controls remain in the later
three-parent Session run (46652), which also adds a native-question terminal
journey; the updated test SHA-256 is
`a596d34f4c56285ca2ecef953f7070eca2b0eaf4502d47b061d959bfa40df01c`.

An evidence-path follow-up found that signed proposal observation assumed the
default `evidence.sources` location despite accepting a reviewed recipe with a
different path. An actual synthetic V3 publication using `citation.sources`
was refused by that reader (46669). The reader now selects the path from the
authenticated recipe; the same correction applies to signed literal
observation, where the newly added guard had introduced the same assumption
(pre-fix reproduction 46668). The combined signed-publication, observation and
read-view selection passed 69 tests (46670) on the private helper. This checks
structural consistency with the signed value and does not authenticate the
stored proof as a current source. That version of `observed_read.ex` SHA-256 is
`0e167a383440b13743725440e4c35ca5c45e853c27a7b367f500bd063ad3c188`; the
updated integration test SHA-256 is
`2726aa7f30588648a2ead61da15d2d4d95a26f332fd7d95ad43b52a072e4c2d4`.
The full run 46663 and the earlier archive predate this correction.

A later review found the literal reader still hardcoded the lineage and
category fields despite the selected recipe's paths. Two actual synthetic V3
publications, each relocating one of those fields while retaining the same
signed metadata binding, succeeded but were refused by the old reader (46672).
The reader now uses the extracted candidate for both comparisons; it continues
to compare against the signed lineage and category. The signed-publication,
observation and read-view selection passed 71 tests (46673); after adding a
dependency-validation assertion for both relocated fields it again passed 71
(46674). The diagnostic helper uses a test-only 7.2.11 override. This proves
neither current source authority nor a production storage profile.

That version of `observed_read.ex` SHA-256 is
`f3560024590693fc570483994cc4cf247e7703b924b4ecdb76f21267fbd9829f`; the
integration test SHA-256 is
`4e569daa1bdc1804b7cf0176c082d9bb492555336bed39f900206ee7896339f2`.
Full regression and a corresponding diagnostic package are in progress; their
exact status and earlier failures are recorded in the [handoff](handoff-20261027-terra.md).

The same audit then relocated a pending proposal's lineage according to its
reviewed recipe. A synthetic signed publication succeeded and the old reader
refused it (46676). The reader now uses the extracted candidate's lineage in the
signed metadata comparisons, while retaining the proposal ID and pending-state
checks. The signed-publication, observation and read-view suites passed 72 tests
(46677) on the test-only helper. This is a structural historical observation,
not proof of current consent, source eligibility or production storage.

The resulting `observed_read.ex` SHA-256 is
`770f3b70379bcd267a0dc651a9c1ace6e2d8443bef1af3e726a57f88d78cdbb1`; the
integration test SHA-256 is
`52b96b8c102e6074118929534e02c6bca3c3fa5d7450dad2de85e99dd4420676`.

The tested `lib/ipse/extension/collection/observed_read.ex` SHA-256 is
`8d70514231a8724181e3cf5cf82c964e6a8c4b394a51ad692a33d17a20b13304`;
after a documentation-only clarification its working-tree SHA-256 is
`d70ae4e23c9233ab66db03b8eee2460e987158ebf60eac44552808188d17d574`. The
signed-publication integration test SHA-256 at seed 46614 was
`c46f4106f050df8ba1bced5493a5a3fe840b82f690ddde59968a43b100d5a20b`;
after the deadline assertion it is
`a261c2162e1608f07f1697902927c49f34e7b081bc11e1036f4cad6b996542ee`.
These identify source, not a
reviewed release or complete audit.

## Cross-session source location remains unresolved

The stored source proof names a Session and occurrence but does not bind the
Session state directory. `ipse` permits a selected `--state-dir`, while the
CLI default is under the operator home. Reopening an arbitrary default path
would therefore not establish that it is the originating journal or its latest
history. A copied older journal with the same Session ID can structurally
reproduce the same source proof, and source redaction is not yet wired into a
durable cross-session lifecycle. No production review route was added on this
basis.

A synthetic SourceIndex control reconstructs the same Session and receipt in a
second window, redacts the original in memory, and shows that the old proof is
refused by the redacted window but still revalidates against the copied window.
The 19-test SourceIndex suite passed (seed 46616). This illustrates the missing
current-window selection; it is not a test of durable redaction or two actual
journal directories.

Before a cross-session review uses a proof, specify and bind an authorized
journal identity/location and project relationship, validate the complete
saved prefix and source pages under the appropriate retained Session lock, and
define how moved, deleted, active, redacted and duplicated histories refuse or
recover. The current `Writer` query checks only its owning Session's current
window. A successfully reconstructed proof is not by itself current consent or
authority to display, accept or publish a proposal.

### Binding and lock-order design constraints

Adding a directory path only to a journal header would not bind it to the
already signed proposal: the stored proof does not include that header, and a
copied or rewritten header is not authenticated by the proposal's live page.
A future format needs a host-derived commitment, made under the publication's
authority, that binds the source Session, its admitted project and a protected
journal identity/location to the proposal. It also needs an explicit legacy
rule; old proposals lack this commitment and cannot silently inherit it. A
versioned sidecar or protected registry would need its own bounded storage,
atomicity, migration and recovery contract. Neither option is selected here.

The existing protected order is Identity → Consent → Collection; its guard
detects same-process reentry, not arbitrary cross-process deadlocks. Session
owners already retain their own Session locks. A review of a source in another
Session must define how that source lock relates to a review Session's lock,
including multiple-source order, active writers and fail-fast contention, before
holding protected locks or terminal IO. The existing `Session.Lock` calls the
general `Runner.lock`, so its use alone must not be assumed to provide a new
protected journal-identity guarantee. No new lock ordering, attestation or
cross-session read authority is implemented by this note.

One possible direction is a versioned host-derived commitment covering the
canonical journal directory identity, Session and project, authenticated by
the same domain as the proposal. A digest alone would not locate the directory:
the operator would need an explicitly selected candidate location or a separate
protected registry. Binding only a worker-provided path or an unsigned journal
header would not suffice. The current V3 live-page row and metadata-change
limits have no such field; adding one requires a reviewed format and bounded
migration rather than silently changing existing signed bytes. Relocation,
backups, deleted journals, redaction, parent/child lock order and old records
remain design requirements, not solved by a path hash.

A location commitment alone would also not prove that the journal at that
location is its latest authorized state. In particular, replacing or rolling
back the contents at the same directory could recreate an earlier prefix whose
proof still matches the signed proposal. A future durable redaction design must
bind a rollback-resistant current head or protected generation to the source
identity, define atomic advancement and recovery with journal appends, and
refuse when either side is missing, inconsistent or ahead without a recoverable
receipt. This is a design inference from the copied-window control, not a
demonstrated durable rollback test or an implemented freshness witness. The
existing Session lock serializes cooperating owners; by itself it does not
authenticate the current journal head.
