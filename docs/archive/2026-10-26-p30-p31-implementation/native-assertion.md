# Native statement/category review, 2026-10-28

Working implementation evidence, not milestone acceptance. The
[plan](../../plan.md) owns remaining P30/P31 scope; the
[operator procedure](../../operator/knowledge-permissions.md#save-your-own-reviewed-statement)
and [source training](../../developer/session-sources.md) describe the working path.

`/remember CATEGORY TEXT` now reviews a new statement as the operator's own
statement, including its category, literal text, workspace, project, artifact,
permission and retention. The existing native Input service binds the actual
one-use confirmation to its Session/client/channel/render. Session records the
`operator_assertion` receipt before invoking the existing protected capture
command. Identity, Consent, accounting and managed publication remain in their
existing owners. No model call is needed.

SourceIndex exposes `native_operator_assertion` and a category-specific
`input.assertion.*` kind. The public proof retains its fourteen-field shape.
The host literal recipe requires the reviewed category and exact complete text.
Plain interactive messages, including whole quoted reports, remain pending.
Native question answers remain pending. An ordinary review cannot become a
current/preference literal merely because a worker changes its classification.
Typed host outcomes still support ordinary literal notes. Existing signed
observations recheck the current recipe, so an old stored literal without the
required source support is not silently promoted.

This host addition is necessary because workers cannot attest native operator
input or convert a clarification answer into endorsement. Domain note building,
retention and capture continuation remain in the existing worker. It reuses the
Input service, SourceIndex, public SDK and protected command API; it adds no
runtime dependency or execution framework. Endorsement does not prove external
truth or grant workspace/shell/MCP/delegation authority.

## Targeted section verification

The isolated graph is `_build/operator-assertion-sol`, with the same explicit
test-only kernel override used in the prior diagnostic graphs. Strict compilation
of 156 modules passed, followed by strict recompilation of changed modules and
matching inert bundles. All homes, grants, projects and statements were synthetic.

The final [section selection](native-assertion/section-46705.log) passed **10 tests**,
seed 46705, max-cases 1, in 8.9 seconds, exit 0. It covers exact receipt/source
binding, quoted-data rendering, category substitution and actual native CLI
saves of ordinary/preference/current statements; cancellation and stale codes;
planning refusal; and revocation between review and confirmation. The actual CLI
fixture checks inert resume, saved reconstruction and zero model admission. Its
protected category-substitution call creates a pending proposal instead of
promoting the reviewed ordinary statement. Log SHA-256:
`19a86a98eab4fb406afd84a4a1eeea2a4e51dd06b2f8983c0d90d187ed6dc22f`.

The affected recipe/record/worker/intake selection (46701) passed 23 of 25 tests.
The two native-intake fixture failures used obsolete permissive-worker source
patches and a recipe digest different from their worker's sidecar. The fixture
now builds its deliberately permissive worker and matching sidecar together;
the host still refuses its fragment/answer literal publication before reservation.
Only that [intake file was rerun](native-assertion/intake-46702.log): **3 parent
tests passed**, seed 46702, 13.6 seconds, exit 0, including the nested native
cases. Its log SHA-256 is
`95beaa2b1f2f6fa0c4de0ec52a1369aa655b3ecf3356663c7eb5c11b44d8fd28`.

Earlier targeted runs exposed a missing Input-purpose allowlist entry, a missing
source-page provenance allowlist entry, and PTY driver writes arriving before
the next native prompt. These were repaired. Their failed logs remain in the
isolated graph (`46697` through `46699`); they are not passing evidence. An
initial extra ceiling fixture also failed compilation (46703), then its two
cases passed (46704) before the final selection. The final implementation was
not validated by repeatedly running the aggregate suite.

## Remaining integration

This accepts a fresh operator statement; it does not accept an existing pending
proposal by ID, replace/forget an old record, or implement current recall and
source leases through inference egress. Capacity/turnover, installed-package and
production-profile qualification remain open. No aggregate suite containing
these changes has run, and no release was published. On the user's 2026-10-28
instruction, finish coherent implementation sections with targeted tests before
running aggregate validation at their appropriate boundary.
