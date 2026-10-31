# Public embedding selection bootstrap and pin — implementation

Scoped implementation, 2026-10-29, following the
[reviewed SDK gap](embedding-selection-bootstrap-independent-review.md).
The [plan](../../plan.md) owns acceptance. This does not repair the separately
held [producer source-policy boundary](shared-producer-first-page-independent-review.md).

`embedding.profile` is a separate read-only Actions v2 branch under existing
`host.embedding` and `host.actions`. It returns exactly version, requested public
profile and the existing selection digest. Its host-created `embedding_profile`
binding retains the complete profile/hash; live result validation requires exact
equality to that binding, and Saved validates the binding against the requested
frozen Session snapshot. Self-consistent foreign profile/hash replacement refuses.
It creates no inference source, Usage admission, provider request, credentials
lookup, service reservation or implicit alias choice. Missing/ungranted profiles
refuse before action intent. The ordinary action/read ceilings still apply.

V2 `embedding.create` optionally accepts `expected_selection_sha256` as part of
its immutable request and approved arguments. A present malformed/nil hash, extra
field or v1 pin refuses. The host compares the pin before binding/approval/intent,
in existing binding validators, and at inference execution/dispatch view; result
selection must also match. Old unpinned v1/v2 shapes remain supported. This checks
configured selection, not model weights, reported model or source eligibility.

The [independent implementation review](embedding-selection-bootstrap-implementation-independent-review.md)
accepts this frozen slice within its exact overlay/test scope. Producer adoption,
source-policy dispatch and coherent package qualification remain separate.

## Exact evidence

The [manifest](embedding-selection-bootstrap/manifest.json), SHA-256
`f28479373cf24fc3d82daae2e9f1c0b8370d0d137d557fcf0b39bf6157c071b9`,
pins six current source/test snapshots, ten retained launch/log/helper/initial-test
files, two complete runtime inventories and the prior Core/CLI ancestry manifest.
Each graph has 698 regular files and one separately recorded directory symlink.
The selected helper is unchanged. Binary artifacts remain in the recorded `_build`
graphs. This is a four-source/six-module overlay, not an all-current-source build.

| Check | Result |
| --- | --- |
| `47151` | Six owner modules compile with empty compile/runtime diagnostics |
| `47152` | 14 pure embedding-result controls pass, including existing v1/v2 receipt/capacity behavior and new snapshot/pin controls |
| `47153` | Actual public-bootstrap→approved pinned synthetic loopback inference→mismatched-pin refusal passes; bootstrap/Saved tamper checks pass before an inherited resume-helper assertion fails |
| `47154` | Corrected bootstrap/resume and new missing/ungranted-profile controls both pass; 16 unrelated cases excluded; the already passing inference case is not repeated |

The actual pin control checks full approval arguments, exactly one provider call,
one Usage admission, matching result selection and valid Saved reconstruction.
The subsequent mismatched pin creates neither approval nor action intent nor a
second provider request. The bootstrap control checks no approval/inference/Usage
and rejects a self-consistent altered profile/hash in Saved. Its confirmed resume
preserves old journal bytes as a prefix and appends exactly one valid fresh owner
marker, without another action or provider request.

The first helper had expected a byte-identical journal across resume. Current
native Session startup deliberately appends a fresh `session_release_owner_started`
marker so a prior owner's release claim cannot authorize a new owner. Source and
the existing native-header tests establish that contract. The repaired fixture
allows exactly that validated fresh marker, with a distinct owner ID; legacy
journals still require zero appended bytes. It does not allow arbitrary journal
changes. The original failed log and exact earlier test source are retained.
No production change or broader runtime rerun was made for this fixture repair.

Session tests use actual host approval, inference transport/accounting and Saved
against an authorized isolated synthetic loopback Ollama-shaped endpoint. They
use no live model, external service, credential or paid quota. Fixture artifacts
and temporary journals were removed by their existing teardown; their raw bytes
are not claimed as retained independent receipt evidence. The exact test source,
logs and host executable graph remain. Producer adoption and coherent
package/source qualification are still required.
