# Private project-domain authentication component

Dated **2026-10-27**. This is an independent internal substrate checkpoint, not
managed current reads, a Normalizer upgrade, import adoption, source eligibility
or milestone acceptance. The [plan](../../plan.md) owns delivery status. The
[persistence chapter](../../developer/persistence.md#keep-project-domain-attestations-private)
owns current developer training and its verified keyless exercise.

## Ratified boundary and implementation

The parent reviewed the full proposal SHA256
`5fe07646cdf5d55e216749546c1509b639633bda8667d347069dd084f4952ecc`
before implementation. Its original `/tmp/ipse-project-domain-auth-design.md`
is retained in durable evidence. Ratified amendments fix source format
`managed-metadata-v3` and MAC context exactly, omit per-page floor, and retain
actual Collection provenance authentication as a later adapter obligation.

Index version 2 adds only the private top-level `domain_keys` map. Public project
and binding maps remain unchanged, preserving `binding_sha256`. Ordinary identity
mutations retain the private state. Existing version 1 remains readable/keyless;
preview and existing-verifier reads do not initialize or upgrade. Existing public
identity behavior is preserved. Keys/catalog entries share the current one-MiB
index and three-MiB native Identity allocation, inside the existing four-MiB
Identity/service control reserve; no quota increased.

A project master contains 32 random bytes, a separate random public key ID and
its namespace catalog. Limits are 256 masters, 256 namespace entries globally,
eight per project and 192 KiB encoded private map. Namespace entries bind a
format, random fence, prepared/active state and exact first operation/root. Keys
are retained in operator Identity, never supplied by a Collection backup.
Neither provider credentials nor volatile SourceWindow secrets are reused.
Existing OTP crypto primitives are used; no dependency or native code was added.

`with_existing_domain_auth/5` supplies only a verifier for an existing active
catalog. `with_domain_publication/6` checks its exact binding and trusted current-
policy authorizer before key creation; explicit initialization native-publishes
prepared state before entering the first callback. Successful first completion
binds the trusted root witness and writes active state after child locks release.
Later publications do not rewrite Identity. `reconcile_domain/6` requires exact
expected key/fence/operation, current authorization and a trusted proof callback.
Prepared state never automatically replays or resets.

Root witnesses in this component are callback contracts. The tests use explicit
synthetic trusted witnesses, not actual Collection provenance. The eventual
adapter must authenticate actual root absence/materialization, page/context
fences, original sources, current policy and every inherited page before sealing.
The helper does not itself classify a lost active store or implement import
adoption. Unsigned Normalizer-v2 pages remain unavailable to a future current-read
path unless independently recovered from actual validated history.

## Exact MAC bytes and bounded lifetime

Namespace key derivation is:

```text
HMAC-SHA256(project_master, JSON.digest([derivation_scope]))
```

The closed derivation scope contains domain `ipse.project.namespace-key`, version
1, verified project ID, namespace, format and key ID. `JSON.digest` returns the
existing canonical SHA256 as 64 lowercase ASCII bytes. Page fixed scope replaces
the domain with `ipse.managed.page` and adds the catalog fence. Its exact tag is:

```text
HMAC-SHA256(namespace_key, [JSON.digest([fixed_scope, context]), raw_body_bytes])
```

The fixed 64-byte prefix makes this unambiguous and permits arbitrary binary
bodies. Context has exactly version 1, schema 3, reserved ASCII page key (at most
96 bytes), kind `anchor|live|format`, operation ID and positive safe record
revision. Sealing also binds the publication's actual scoped operation ID. Old
page context must come from actual record references; the helper does not prove
those references. No floor lookup or extra per-page context field was introduced.

The primitive returns a raw 32-byte tag; base64url encoding would occupy 43 bytes.
It does not hide an envelope or claim that an eventual wrapped page fits 6 KiB.
That adapter must check its actual final encoded bytes and allocated peak.

The private capability binds its exact effect owner, original upstream owner,
opaque nonce and five-second absolute crypto lease. It supports at most 16 seals,
128 verifications and one MiB of page-crypto input. Each call counts 64 context
digest bytes plus a body of 1..6,144 bytes. The call/body bounds already imply a
stricter aggregate bound; there is no artificial one-MiB exhaustion test.
Invalid contexts refuse before crypto; valid-sized wrong tags consume a verify
attempt. A late callback result becomes unknown. Nonce invalidation runs after
return or exception; retained capabilities cannot be reused. Arbitrary Core IO
is not forcibly preempted or retroactively fenced, and memory zeroization is not
claimed. No raw key belongs in public binding/configuration/header/export or
diagnostic surfaces. Same-user hostile code and hostile BEAM remain outside this
trusted-Core/cooperative-storage boundary.

Nested Resources effects stay inline. Identity → Consent → Collection retains
one actual native owner; Identity checks run only when its capability is top.
All public results are withheld until native checks/release succeed. MACs attest
past host invocation, not present freshness, truth, permission or anti-rollback.
Typed import still needs current floor/adoption checks. Coherent raw same-user
rollback requires an independent watermark if that stronger boundary is desired.

## Author checks and retained failures

Private source snapshot 01 compiled **129 source files** with warnings as errors.
Its first focused run passed 14/15. The nested-lock fixture incorrectly expected
`project_identity_lock_order` from existing inspection, which deliberately
normalizes it to `project_identity_unavailable`; it also lacked the native lock
file needed by the next step. An initial diagnosis mentioned only the latter;
source inspection and the expanded run established the first failed assertion.
The corrected fixture checks both the exact order guard and the existing API's
exact refusal. It creates the required empty 0600 lock, without runtime changes.

Expanded snapshot 02 passed 19/20 with that same assertion failure and two
late-fixture-definition warnings. Moving the unchanged source-derived fixture
loading before test-module compilation removed those warnings. Snapshot 03 then
passed **84/84**, including existing Identity and protected transaction controls.
Snapshot 04 added exact crypto-input accounting, late callback withholding and
binary-tag/current-Consent controls: strict compilation and **87/87** passed.

An author static review then found that the new existing-verifier wrapper
inherited generic absent-identity `{:ok, nil}`. It invoked no callback and created
nothing, but this API should explicitly refuse. Snapshot 05's actual regression
reproduced this result: **23/24**, retained unchanged. The narrow wrapper now
returns `project_domain_unavailable`; ordinary identity inspection is unchanged.

Final immutable snapshot **06** passed strict whole-app compilation of **129
source files** and **88/88** focused tests, seed 214282, in 29.8 seconds. The suite
combines 24 domain-auth cases with existing Identity/Transaction/optional-read/
framing/protected-helper controls. It includes actual native kills after both
prepared and active index rename-before-ACK, separate-VM contention and subsequent
reuse, scoped and unscoped upstream death, cancellation, controller loss,
revocation through actual current Consent, callback exceptions, stale/copied
capabilities, deadline/count/binary/context/closed-schema/global-capacity controls
and unchanged public bindings. Root-witness fixtures remain distinct from these
actual native ownership observations.

The test count was checked against the source AST and the actual combined run:

| Test file under `test/ipse/` | Definitions |
| --- | ---: |
| `extension/project_domain_auth_test.exs` | 24 |
| `extension/project_identity_test.exs` | 21 |
| `runner/transaction_test.exs` | 20 |
| `runner/transaction_optional_read_test.exs` | 12 |
| `runner/transaction_framing_test.exs` | 9 |
| `runner/protected_helper_test.exs` | 2 |
| Total | 88 |

Actual **Elixir 1.18.5** formatting found one helper guard-layout difference;
explicit `do/end` made both formatter versions agree. The first compatibility
compile stopped because its private output directory did not exist; the log is
retained. Creating that directory repaired only the verifier setup. The corrected
two-source-file compile emitted five modules and has no compile/runtime
diagnostics; four-file formatting has
zero differences. The developer manual's isolated keyless example passed against
the actual private runtime. The whole persistence chapter was reviewed and its
new explanation integrated with protected publication; the developer index was
updated. Documentation links/rules pass.

The first sandboxed Mix compile refused its required TCP lock socket. An approved
loopback-capable rerun supplied it without changing TLS, tests or lock behavior.
A command initially requested a not-yet-created private working directory and
failed before execution; it was rerun after copying that directory. No failed run
is presented as a pass. No model, provider, credential, packaging, macOS, whole
source-suite or new Rust-suite verification was performed for this component.

## Source/runtime binding and reproduction

Private helper was built only inside the copied project with the existing native
build script: Rust edition 2021, opt-level=z, strip=symbols, panic=abort. Its
actual SHA256 is
`d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b`.
Runner compiled against that image. It is not assumed byte-identical to historical
6f. Shared helper 108c remained unchanged. No shared build or helper was mutated.

Final sources:

| File | SHA256 |
| --- | --- |
| ProjectIdentity | `66ebd609d78da960646a1894cff25e505ed3ea3acf0a63e8f40669369854da15` |
| DomainAuth | `50dbb61771a95995a9869f7fbbb2861c42cd0318ceaecc49cd92e781c225ac20` |
| Domain-auth test | `2da85144c2cd1d3ddf91ca1c588350debb89c9d03c1ef233597f8939258a44dd` |
| Source-derived fixture loader | `35f09c15c0f40c64ff25bef759ce9c167959f58c5550b2f40ab4346da8843500` |

The [source manifest](project-domain-auth-sources.sha256), 457 files, has SHA256
`3b9140992b4bcd79182a3b252764e50dc1bd667603f46b8e55541ea9165fd108`.
The [runtime manifest](project-domain-auth-runtime.sha256), 612 files, has SHA256
`638ddd5cb0f2afa2cb6217f20b9709dd8fa8bf536a9df58e78be888a5952050b`.
Both were unchanged before/after the final test and manual exercise. These bind
the actual private graph, not untested concurrent worktree changes.

Completed graphs 01..06, original logs, proposal, compatibility scripts and
final runtime/source bindings are retained in the operator's private evidence
directory:

```text
/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/project-domain-auth
```

Preservation verified **13,927 copied files**, every source/destination byte,
the complete final source/runtime manifests before and after copying, ownership,
single-link regular files, 0700 directories and 0600 files. Executable images
are deliberately stored as data. Eighteen source/dependency/build aliases were
not followed; `provenance.json` records their exact original targets. Executed
private BEAMs and project `priv` files are retained. Source-derived native fault
wrappers were cleaned by their test lifecycle; their sources/recipes are
preserved, without claiming their ephemeral executable bytes remain available.

| Preservation record | SHA256 |
| --- | --- |
| `files.sha256` | `c0f0c9a612769ba2468677b8a2b1b7d393db2e49bb64647c4a1311b75acaf928` |
| `provenance.json` | `4c02e115158345efb271e45053c2076fed9893d74085bbb94ed5d441697c92cd` |
| `preservation.log` | `32a8a8ec4b41ee94310f33695d93c4da87c929c5f34e159e42cf9284d3295172` |
| `preservation-receipt.json` | `f0215f19db273ffa63eb6cc2cc44331779777b5390afaeee5f76afd423745748` |

The initial preservation attempt encountered the same sandboxed Mix TCP-lock
refusal. Its loopback-capable rerun then exposed a preservation-script path
error: the source manifest already included `project/`, so appending it twice
failed before copying. Both original logs are preserved. Correcting only that
manifest root produced the verified receipt above; the runtime/source graph did
not change.

To reproduce, copy `graphs/06` into a new private working directory. Recreate
each build app's `priv` alias against the working project where applicable, and
chmod only working executable copies 0700. Run from its project directory,
using its copied build:

```sh
MIX_ENV=test MIX_BUILD_PATH=/absolute/private/working/build mix test --no-compile \
  test/ipse/extension/project_domain_auth_test.exs \
  test/ipse/extension/project_identity_test.exs \
  test/ipse/runner/transaction_test.exs \
  test/ipse/runner/transaction_optional_read_test.exs \
  test/ipse/runner/transaction_framing_test.exs \
  test/ipse/runner/protected_helper_test.exs \
  --seed 214282 --max-cases 2
```

Historical scripts contain their original absolute paths; adjust only working
copies. Never run or change preserved evidence in place. The graph's retained
dependency BEAMs support `--no-compile`; recompilation additionally needs the
admitted dependencies recorded by its copied Mix files.

The parent's static review found no actionable issue in the final code and
whole updated persistence chapter. A separate adversarial audit has begun
against immutable graph 06. Its findings and acceptance are separate evidence;
these author checks do not satisfy that step or permit Collection/Normalizer
integration by themselves.
