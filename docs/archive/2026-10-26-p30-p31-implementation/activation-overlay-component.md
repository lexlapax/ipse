# Protected fresh/resumed activation overlay

Dated **2026-10-26**, on `codex/p30-p31`, after managed SDK `bd82c70`, native
managed capture `b55623d` and ReadView `cce9907`. This is an internal host
component checkpoint. It is not a released setup wizard, managed recall or
every-dispatch freshness acceptance. The [plan](../../plan.md) owns milestone
status. Current explanations belong to
[configuration training](../../developer/configuration.md#apply-a-protected-selection-without-changing-base-configuration),
[the collection SDK](../../developer/collection-sdk.md#review-policy-registries-and-activation-data)
and [operator configuration](../../operator/configuration.md#add-optional-behavior-or-recover-a-changed-configuration).

Follow-up independent review confirmed that this checkpoint's `current/2` entered
ordinary recovery and reclaimed pending files during inspection. The
[nonrepairing-reader repair](activation-readonly-repair.md) supersedes that claim
with explicit existing-only readers and frozen reproduction evidence. The source
bindings and original author outcomes below remain unchanged historical facts.

## Boundary and reviewed exceptions

`Config.Activation` applies an already protected settings-v2 activation only
after ordinary configuration resolution/fingerprinting. It leaves source files,
manifest and base fingerprint unchanged. Fresh selection requires the current
known packaged digest, actual installed artifact and declared sidecar, exact
capability ceiling, actual Registry identity and matching actual base routes.
It never imports an artifact, supplies endpoint/profile definitions or starts a
worker/model as part of selection.

`SemanticRoutes.review/2` supplies pre-grant review data using actual configured
destinations. An exact existing service-origin alias is reused. Otherwise the
proposed registration is `origin-` plus the first 56 hexadecimal characters of
the canonical origin's SHA256, within the existing eight-service bound. The saved
policy binds the full routes and activation service references; startup requires
exact equality. A timeout override must narrow the base timeout, with no default
or clamp. Private bounded base state is restored before child admission.

Resume uses only the exact saved activation, including installed artifact/options
and timeout; it never adopts today's enable/disable selection or imports missing
bytes. A saved artifact can remain usable after it leaves the new bundle
inventory. Old metadata without activation stays absent. Idle resume is
byte-identical. Current Consent still gates effects after revocation. An explicit
fresh `--no-extensions` opts out; removal of a saved activation refuses resume.

`Config.Activation.current/2` is host-only nonactivating/nonjoining inspection.
Absent identities/control return nil without creating roots or admitting a
project. Present malformed state refuses. `ProjectIdentity.existing/2` uses the
retained native lock/read and checked lease. Existing primary/folder probes are
read-only. Already admitted linked worktrees preserve the existing native
metadata-copy/cleanup protocol because OTP's public file facts cannot recreate
the saved nanosecond witnesses.

Fresh Session admission can call `ProjectIdentity.join_existing/3` for a new
reciprocal worktree. It requires an already present protected identity index and
retained lock. A bounded native metadata capture identifies exactly one known
repository from that loaded index; no per-project Consent scan is performed.
Reciprocal `.git`/`commondir`/`gitdir` and current primary facts are checked before
the host callback. Under the same Identity lock, the callback verifies a current
project-scoped activation, actual bundle and exact routes. Only `:ok` allows the
existing checked index publication. A new primary, clone, ordinary folder,
unknown repository, revoked/missing/worktree-only grant or poisoned backlink
cannot authorize membership.

The developer explicitly approved **bounded transient native metadata IO for
linked candidates even when authorization later refuses**. This exception does
not authorize new roots, new projects, repair/reclaim or a logical read of mutable
metadata in place of the native witness. The original owner and native lease
remain required before publication. After joining, fresh admission rechecks the
current policy epoch/hash; revocation may leave membership but cannot lend effect
permission. Arbitrary same-UID replacement/tampering is outside the cooperative
host boundary. In particular, native lock acquisition uses its existing
create-capable protocol: pre/post retained-identity checks refuse a missing or
replaced lock, but do not promise zero transient files after hostile concurrent
deletion. No new native protocol was added.

## Exact source graph and actual checks

The final source/build tree is uniquely owned
`/tmp/ipse-activation-overlay-20261026-05/{project,build}`. It was copied during a
coordinated source-stable window. [The source manifest](activation-overlay-sources.sha256)
hashes all 128 compiled application/bundled sources, Mix files and four owned
test/fixture files: **134 files**. Parent CLI draft bytes are included as exact
graph provenance, not as a tested CLI workflow. Dependencies were copied/reused
read-only. The private actual helper remains SHA256
`108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.
No shared helper/build path was changed.

Numbered log prefixes below refer to the independent
`/tmp/ipse-activation-overlay-20261026-01` through `-05` directories, rather than
subdirectories of the final graph.

| Private graph/log | Actual outcome |
| --- | --- |
| `01/existing-first.log` | Initial protected existing/route controls, 10 passed |
| `02/compile-first.log` | Full strict application compile, 127 source files |
| `02/tests-first.log` | Ten direct controls passed; child 5/6 after synthetic SDK-2 fixture returned the wrong result-publication shape |
| `02/tests-second.log` | Eleven parent tests passed, including six actual child Session scenarios, after fixing only that fixture |
| `02/tests-local-route-refusals.log` | Eleven parent tests passed with actual Ollama route derivation, including eight child scenarios; no inference call |
| `03/tests-first.log` | 14/16: two new test assertions were wrong (public view has scope/root, not role; nonexistent foreign target correctly refuses) |
| `03/tests-second.log` | 15/16: real auto-join adapter mistake returned `:ok` inside `Consent.with_policy`, whose checked reader requires `{:ok,data}` |
| `03/tests-repaired.log` | 16/16 after normalizing only after the successful checked reader return, including eleven child scenarios |
| `03/tests-final-v2.log` | 16/16, 6.0s, including twelve child scenarios and revoked-after-authorization control |
| `03/regressions-first.log` | 44 existing Config/semantic-loading/Identity/delegation cases passed, 10.6s |
| `03/integration-regressions.log` | 27/28; fixed-subscription local HTTP fixture refused because the graph was compiled in dev then reused with `--no-compile` under test |
| `04/compile-test.log` | Full strict `MIX_ENV=test` compile, 127 source files; no provider endpoint rule changed |
| `04/tests-final.log` | 88/88 parent tests passed, 18.1s, seed 20261026, plus twelve actual child Session scenarios |
| `03/compat118-final.log` | Elixir 1.18.5: ten owned code/test files have no formatting differences; six affected modules have empty compiler diagnostics, host OTP29 |
| `05/compile-test.log` | Final fresh full strict `MIX_ENV=test` compile, 128 source files |
| `05/tests-final.log` | Final exact graph, 88/88 parent tests, 18.1s, seed 20261026, plus twelve child Session scenarios |
| `05/docs-final.log` | 507 Markdown files, 4577 local links/manual-archive rules, zero errors |

The 88-case command names exactly these existing files:

```sh
MIX_ENV=test MIX_BUILD_PATH=/tmp/ipse-activation-overlay-20261026-05/build mix test --no-compile \
  test/ipse/config/integration_test.exs test/ipse/config/profile_integration_test.exs \
  test/ipse/tools/delegation_integration_test.exs test/ipse/config/activation_session_test.exs \
  test/ipse/extension/project_identity_existing_test.exs test/ipse/extension/semantic_routes_test.exs \
  test/ipse/config_test.exs test/ipse/config/semantic_loading_test.exs \
  test/ipse/extension/project_identity_test.exs test/ipse/tools/delegation_test.exs --seed 20261026
```

The new direct controls kill the **actual native transaction process**, kill its
original caller, or cancel its resource scope while the host authorization
callback is paused. The old index remains byte-identical and no linked binding
is published. These are real process/receipt checks, not manufactured exit facts.
Existing Identity regressions compile their own private Rust fault fixture from
the exact copied sources; production activation checks use the pinned actual
bundled helper.

The independently compiled SDK-2 child worker runs only an explicitly invoked
inert command. The child VM owns a private copy of the entire application/priv
directory before changing its packaged catalog. Its configured Ollama destination
is used for pure route validation, with **zero model/network calls**. It verifies
fresh/revoked/resumed catalogs, exact idle bytes, absent historical activation,
explicit opt-out, timeout narrowing, child base restoration, malformed control,
changed model/origin/sidecar, new linked worktree admission and narrow/off/refused
join cases. Missing known bundles refuse fresh selection while saved installed
bytes remain sufficient for exact resume.

## Manual review and limits

The complete developer configuration, collection SDK and operator configuration
chapters were reviewed as current manuals. Overlay ownership is integrated with
resolution, route review, Session admission, child filtering and resume guidance;
the operator text does not invent a routed setup command. The dated SDK record
also now distinguishes its ignored nonexistent command targets from its actual
40 passing cases and the later separately executed 30 real policy tests.

No dependencies were added. Existing JSON/Jason, Registry/Artifact/Bundles,
ProjectIdentity/Consent and native transaction/read/metadata facilities are reused.
No live model/account calls, paid requests, downloads, private qualification
inputs, primary native rebuild, PTY run, full suite, installed-runtime journey,
OTP27 execution or macOS evidence belongs to this checkpoint. Managed live
eligibility, inherited taint, every-dispatch withdrawal, setup UI and independent
combined audit remain separate work. The parent owns whole-graph baseline and
milestone acceptance.
