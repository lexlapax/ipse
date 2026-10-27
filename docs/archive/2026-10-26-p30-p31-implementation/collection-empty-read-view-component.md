# Native-confirmed empty Collection read views

Dated **2026-10-26**, following native framing repair `effa7211994b970153915d8438416b66ca8fe133`
and its [independent closure](native-framing-audit.md). This historical component
record supersedes the unmaterialized-store refusal in the
[original read-view checkpoint](collection-read-view-component.md), preserving
its earlier verification and [independent audit](collection-read-view-audit.md).
Current procedures belong to [persistence training](../../developer/persistence.md#read-several-collection-pages-under-one-validated-index);
the [plan](../../plan.md) owns unfinished integration and acceptance.

## Changed boundary

Read-view open now reads root.json with the versioned native optional H operation.
A validated present root follows the existing full manifest/block/receipt checks.
Only the native absent disposition can create an absent-root view; generic errors,
unsafe roots, owner loss and unsupported helpers do not become empty results.
Ordinary Collection loading retains its previous behavior; the shared empty-state
constructor and existing pointer decoder were extracted without changing that path.

The private cache and returned result/witness use explicit version2. Present
witnesses retain the actual root, exact root hash and manifest hash. Absent
witnesses have root_state absent, null root/root hash/manifest hash, an empty
record index and zero-generation/floor summary. No fabricated digest stands in
for an absent manifest. A second H read confirms absence before cache installation.
Every selected read uses H again under the actual native owner: absence must
remain absent and a present root must retain its exact bytes/hash. First
publication or disappearance of a previously present root invalidates the view.
An anchored materialized empty store remains present with its real witnesses.

All existing owner/caller/cache seals, 16-cache/60-second/512-read/4-MiB bounds,
selected-object validation, native quota and final check/release remain. Cache
finish still withholds results if the cache closes during IO. Opening may create
protected collection directories and retained locks, but publishes no root or
operation receipt. These are storage observations, not managed eligibility,
policy permission or Session absence authority. The pure ManagedReferencev1
contract remains unwired and does not gain nullable manifest hashes implicitly.

## Frozen author graph and tests

Graph `/tmp/ipse-empty-read-view-20261026-02/{project,build}` derives from CLI07
plus Collection/ReadView and two owned test inputs; the later CLI08 configuration
repair was excluded. The [1,105-input manifest](collection-empty-read-view-runtime.json)
binds every retained regular project and actual build runtime input, excluding
unused source aliases. SHA256:
`0cc1159adc6345a3db65abaced1ccbba2df4a6f813a0340b41a269f300f8f764`.
It was established before broad regressions and matched afterward byte for byte.
The private helper remains exact `6f431b5aedde35ecb6f8737e7714dbd197df83c7e8d52e909243e0a39152a55d`,
copied from the verified framing graph, not rebuilt by these checks. Shared108c
was not modified. All execution used the private project cwd.

| Actually executed check | Result |
| --- | --- |
| Strict full private compile | 128 files;exit0; `compile-first.log` |
| Existing/new read-view controls before final inventory | 26/26;7.8s;seed20261105; `tests-first.log` |
| All fourteen Collection, normalization, migration and managed SDK suites | 135/135;300.7s;seed20261106;max cases2; `tests-broad-final.log` |
| Actual Elixir1.18.5/OTP29 | Four files format identically; Collection/ReadView compile diagnostics empty; `compat118-final.log` |
| Exact public persistence source exercise | Empty and present views pass; manual unchanged; `doc-exercise-final.log` |
| Frozen input verification | All1,105 entries unchanged; `integrity-final.log` |

New controls exercise first publication, present-to-absent refusal, unsafe
symlink/hardlink/directory/mode/FIFO/malformed roots, newly appearing unsafe
roots, fabricated absent cache fields/records, actual native-owner loss and
explicit reopen. An actual complete import has twenty source destructive
operations and only four target operations; its floor20/generation4 remains a
valid present view. Imported floor is not incorrectly bounded by local generation.
The initial01 prototype passed25 cases; static review removed that provisional
invalid bound before final02 and added the actual import regression. Initial
logs are retained separately and are not counted as final qualification.

The exact executed persistence manual SHA256 is
`ca6b87931ed2e5adaf301f4d120f88eb170e1f9dce59dd67958bd9c0d47109aa`;
its extracted source exercise is
`a1d5d45ac5633cc45f6f2e4370e5de1ceb20f9f8870ded3c7c7401d99f40a179`.
The complete chapter was reviewed, its old empty-store/refusal explanation
replaced with the explicit v2 contract, and its earlier stale consent/CLI
statement reconciled with the current standalone permission procedure.

## Preservation and limits

Author durable `p31-verification/collection-empty-read-view` retains1,156 payload
files, owner-only directories0700 and regular single-link data0600. Source and
copied bindings were checked before/after preservation; files/directories synced.
Runtime priv was materialized from the same project; unused project/deps and
telemetry source aliases were omitted. The manifest is
`9c7ff90a8cc951f7c213c529e936c2231854c83b8603e2e493d004714dacd565`;
preservation receipt is
`99e05c352593bff339e19c049f2b2f4b3e69c8dc05bc7a50ed5f530362925323`.

These local synthetic fixtures make no model/network call or credential/user-state
access. Native source/helper correspondence is inherited from the explicitly bound
Foundation graph; this component did not rebuild native. No installed package,
whole branch suite, human/macOS/OTP27, sustained capacity, live current recall or
final milestone audit is implied. Independent review of this exact02 graph is
complete in the [separate audit report](collection-empty-read-view-audit.md),
distinct from the earlier present-only read-view audit. Its independently copied
graph passes26 baseline and7 fresh adversarial controls, actual old-helper
refusal and the exact public manual example. All1,105 inputs remain unchanged.
Report SHA256 is
`69fc1acc44d114436ab9d62cbee728c5dcf94106df645074fcd73deb2aafb3e7`;
its durable1,678-file manifest is
`c0134100e7f285cf52f3dcc612ff118a0f93175072cad80add2fac087c827322`.

| Changed input | SHA256 |
| --- | --- |
| Collection | `15d3f0731e06dd95660e067ebbc33bc81bf1c9fc56b1e871511d8f83ed6d1de0` |
| ReadView | `e5095b24260dcf17852f4ea6576c2b0e4e535efa8d19ff1287e7728171b2ebf7` |
| Existing read-view tests | `8a36926a94e18d3cc49d1d9179739f114632dbe2e412245dcd9f7e0e70024809` |
| New empty-read-view tests | `b8ab9a7ed7922cfeb5d3e347715567cab8cdf3a2e280a5fb171b38c9d2be1fd4` |
