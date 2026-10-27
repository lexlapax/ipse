# Settle verified managed-publication input

Dated **2026-10-27** on `codex/p30-p31`. This focused checkpoint supersedes the
successful-settlement description in the [original managed SDK record](managed-sdk-component.md).
It changes neither the current two-sidecar reservation nor the managed wire,
permission, replay, source or storage formats. The [Collection SDK](../../developer/collection-sdk.md)
and [accounting chapter](../../developer/accounting.md) describe current behavior.
The [plan](../../plan.md) remains authoritative for milestone acceptance.

## Change and trust boundary

`ManagedCollectionCall` still reserves one operation, the encoded outer request,
two maximum 6144-byte sidecars with worst-case envelopes, 2048 normalization bytes
and 16384 output bytes before effects. Previously, each successful save settled
that complete conservative reservation, consuming period input capacity that the
actual short publication never used.

Inside the actual Collection normalizer callback, the host now measures:

```text
byte_size(Jason.encode!(outer_request))
+ byte_size(Jason.encode!(normalized_commit))
- byte_size(Jason.encode!(original_commit))
+ byte_size(Jason.encode!(normalization_receipt))
```

A fresh private reference identifies an initially absent process-dictionary slot.
The actual storage process claims it before invoking normalization and requires its
Collection witness operation ID to match the admitted intent. The capture retains
that ID and checks it again with the successful result. It accepts one
invocation; repeated callbacks refuse and invalidate the prior capture. A foreign
process cannot populate the owning process's slot. `try/after` restores the prior
dictionary state on normal return, error or raised callback.

The successful Collection result must still pass its existing closed validation
and response bound. Its `receipt.request_sha256` must match the measured normalized
commit; the normalization must match exactly and retain the binding's digest.
Only that same proven success carries a private actual vector into
`Consent.publish`. Every dimension is a safe unsigned integer within its reserved
amount. Negative normalized growth, an oversized normalization receipt or invalid
measurement refuses. No cost field enters the SDK, journal receipt, Collection
result or normalizer schema.

Input is the measured amount. Operations remain one, output remains 16384, and
model/download/money dimensions remain zero. Known conflict and failed-no-effect
outcomes retain the full reservation. Unknown storage, native cleanup or consent
settlement never releases it, even when the normalizer already captured a valid
smaller measurement. No automatic retry or result promotion was added.

## Bound executed source and runtime

The accepted author graph is `/tmp/ipse-managed-actual-accounting-20261027-06`,
copied from the Root's coherent test baseline
`/tmp/ipse-full-test-baseline-ab100a66d350374e` and rebuilt from its own private
project working directory. It excludes the concurrently authored Collection
directory-admission changes. Mix compiled **130 source files**, with warnings as
errors. The private helper, compiled earlier from the admitted native source,
remained `d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b`.
The shared helper was untouched.

| Input | SHA-256 |
| --- | --- |
| Runtime source `managed_collection_call.ex` | `cb9a03f3c8ab92e58dd75560faf5461e78e398def1d44a95baf42d8e7b8a27ff` |
| Executed ManagedCollectionCall BEAM | `7c471d35eb02ba8bab643591130c001f43f9909da32ae985e51d043364b44fe5` |
| Source-derived accounting tests | `0163d4812cbebdd6241c37b1a0ce6dece7cb2bf2c12dfe826f40fb760323ee00` |
| Managed SDK boundary tests | `cb1b29d4f8e16b9792fd1ca7387da884ad2767f712ec1fc5337776d82a260adf` |
| Managed SDK Session tests | `5d4fe41810247704ce14856d804bf9750ce9b528f9cfb6e2ea568070c6f252be` |
| Complete project/build manifest, 2338 regular inputs | `63bd5e53b0edcd53daf0f26df43656293f8261c645d766906cf0e77195adddcf` |

The complete regular project/build input manifest was checked unchanged after both
test scopes. Symlink aliases are not independent manifest rows; the runtime
binding check separately verifies the selected private helper and source/BEAM
origins. Mix's declared `.mix_test_failures` execution cache is excluded. The
framework's source-derived test module exists only in the ExUnit VM and adds no
runtime public test API.

## Checks actually run

Elixir **1.20.4 / OTP 29** author checks:

- **26/26** tests, seed `20261124`, 12.6 seconds. AST counts are five new
  source-derived accounting tests, five managed boundary tests and sixteen
  managed Session tests. The Session fixture independently compiles an SDK-2
  artifact, uses a synthetic model and the actual protected native storage path.
- Two successive real saves run under a 30000-byte period input limit. Each
  test reconstructs the exact normalized commit from the original action and
  protected stored sidecar values/revisions, verifies its receipt digest and
  exact actual debit, and proves that the combined full reservations exceed the
  cap while the first actual plus the second reservation fits.
- A real staged-publication telemetry hook closes the actual native owner after
  normalization and before root switching. The Session reports cleanup error,
  its durable inner outcome is unknown, consent actual stays null/full reserved
  liability, and the collection generation stays zero. No successful refund or
  publication escapes.
- The known-conflict test now explicitly compares its actual vector to the full
  original reservation. Existing revoked/mode/source/CAS/paged-output/replay and
  owner-loss checks remain in the Session scope.
- Source-derived negative tests separately expose private helpers in a renamed
  test module. They exercise exact arithmetic, negative growth, oversized receipt,
  unsafe/missing/too-small resource dimensions, repeated callback invalidation,
  mismatched result/operation IDs, foreign-process capture and dictionary restoration
  after a raised callback. Closed SDK validation rejects caller cost fields.
- **109/109** related tests on the final graph `06`, seed `20261125`, 38.7 seconds: legacy Collection SDK
  pure/Session, CollectionPolicy, Normalizer, ManagedRecipe, SemanticConsent v2,
  Invocation and Resources authority. The expected journal-exhaustion test emits
  its redacted error log; the scope passes.

Actual **Elixir 1.18.5 / OTP 29** checks format the four owned source/test files
without differences and compile the one changed runtime source with diagnostics
`[]`. This is source compatibility evidence, not an ExUnit run or OTP-27 test.
No providers, model services, credentials, PTYs or qualification data were used.
No native helper was rebuilt. This checkpoint establishes neither broader
filesystem/platform qualification nor milestone acceptance.

Both developer chapters were read as whole documents and integrated around
reservation, measured settlement and retained uncertainty. Operator resource and
recovery guidance was checked for consistency. The documentation checker passed
542 Markdown files and 4783 local links before this archive was added; the final
archive/checkpoint check is recorded separately with the preservation receipt.

## Preserve failures and setup provenance

Earlier graphs and failures remain evidence, without being relabeled as the
successful frozen runtime:

1. Graph `01` copied current syntax-stable Collection changes before the Root's
   later coherent-baseline path arrived. It was never compiled or tested.
2. A first copy command used identical private source/destination paths and
   refused before compilation. Its tool output is retained as a setup transcript
   note. The next local compile was denied Mix's TCP filesystem lock; the actual
   `:eperm` log remains. Approval allowed the required loopback lock without
   weakening the tests.
3. Graph `02` strict compilation passed and its 2338 regular input manifest stayed
   unchanged. **24/25** tests passed, seed `20261120`, 26.2 seconds. The native-loss
   fixture incorrectly expected successful Session completion after deliberately
   destroying its native owner; runtime correctly returned cleanup error. Dynamic
   source-derived fixture call warnings were removed without adding a runtime API.
4. Graph `03` was accidentally compiled from graph `02`'s working directory.
   Its explicit source-origin guard refused before any tests. It is not a valid
   private-origin test claim.
5. Correct-origin graph `04` retained unchanged inputs and **24/25** tests passed,
   seed `20261121`, 12.8 seconds. The corrected error expectation revealed the
   fixture then queried `Session.info` after that Session's expected shutdown.
   Caching the ID before dispatch fixed the fixture. The runtime source did not
   change for either native-loss expectation repair.

6. Graph `05` passed **25/25** focused and **109/109** related tests, with its
   complete 2338-row source/runtime manifest unchanged. Parent review requested
   explicit operation-ID capture instead of relying on the private callback's
   implicit operation binding. Graph `06` adds the witness/intent/capture checks
   and a fifth source-derived negative test, retaining all wire shapes. The
   earlier successful graph and both failed fixture graphs remain preserved.

These are author implementation checks. Independent adversarial review remains a
separate requirement before component acceptance. The current two-sidecar reserve
and v2 metadata limits remain; future adaptive/v3 work has no authority from this
accounting repair.

## Durable earlier evidence

The earlier graph `05` and failed fixture graphs `02`/`04` are preserved as
owner-only data beneath
`/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/managed-actual-accounting`.
Its 12192 copied regular files were source/destination byte-checked, all three
2338-row admitted manifests rechecked, and files/directories synced. Data files
are 0600 and directories 0700; reproduced helpers become executable only in a
separate working copy. Symlink aliases are explicitly omitted from copying; their
regular target bytes and the actual selected private helper were separately bound.
The final payload manifest is `files-final.sha256` with SHA-256
`294293b0861e8132ee7ed9b7bf2b06210cf9cbe78ec98a0ad97f1c602c020284`;
provenance SHA-256 is `f1c80d4f68c267619f1b670596a41a1e2f8c70cb053abd1f39db6f4d7df0d016`;
the preservation receipt SHA-256 is
`a68cf5bf17aeb9b9cff6b8dba36ce3a3980aa66f88852914cd08338447e989e7`.
The first preservation attempt copied data but failed encoding tuple metadata.
Its original script/log remain; the corrected resume verified existing copies
byte-for-byte and refused any changed existing filename, then wrote a newly named
final manifest and completed the receipt. The preserved earlier report
`final05/REPORT.md` has SHA-256
`252145427aaf96ee88d1a0ade260aa511d5a1a51e6a0a071d47ecf631d1ad90b`;
it describes the pre-opID-refinement graph, not this final `06` source.

## Final operation-bound evidence

The complete final `06` graph, logs, probes and both reviewed manual chapters are
preserved as 2363 owner-only regular data files beneath
`/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/managed-actual-accounting-final`.
Its independently byte-checked payload manifest SHA-256 is
`445c29d0e336acaac2fc90eeff43679356127862cb0ad5cd8993a815a10baf0c`;
provenance SHA-256 is
`8f5db73b380a91b1f24bd720c61f066084de2c87c28c69194abc2f2ad175fbcc`;
preservation receipt SHA-256 is
`309b038908b3de432713bad91dd054aafce388a2813f9818b58437ae804e234f`.
All 2338 admitted runtime rows were rechecked at source and destination; files and
directories were synced. `.git` metadata and symlink aliases are excluded from
this final copy; regular targets and actual helper identity remain verified.
`REPRODUCTION.txt` requires a separate private working copy and a private-cwd
rebuild; it never makes preserved evidence executable in place.

The preserved `final06/REPORT.md` SHA-256 is
`fd2d141f5b492bb1e830163d5d977a3c29b3efe704520159d9ad72b3a81fc800`.
It is this author record before this final preservation-pointer section. Final
documentation verification passed **544 Markdown files, 4793 local links, zero
errors**; scoped current-toolchain formatting and whitespace checks also passed.
These results remain author evidence; independent execution audit is separate.
