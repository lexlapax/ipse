# Native retention through the standalone management owner

Historical implementation evidence, **2026-10-28**, branch `codex/p30-p31`.
This extends the [typed Core retention controls](../2026-10-28-managed-retention/index.md)
and [standalone forget owner](managed-forget.md). Current acceptance belongs to
[the plan](../../plan.md); runnable usage belongs to the
[operator manual](../../operator/knowledge-permissions.md#change-a-selected-native-notes-retention).
This record does not close P31C1a/D0/E, installed use or annual turnover.

## One management owner and two exact operation kinds

`knowledge retention NOTE_KEY --policy automatic|pin|session|duration` uses the
existing standalone Resources owner, original management journal, retained lock,
current project binding, signed target and installed literal recipe. Positive
whole-day duration is explicit through `--days`. Foreign or malformed options
refuse before action. The mode ceiling, native input/display and effect-denial
checks are shared with forgetting. Capture permission may be disabled or expired;
these management paths grant no model, worker, shell, workspace or network effect.

`Consent.retain_deferred/8` and `forget_deferred/8` share the existing protected
ledger. Their fixed operation/fact/confirmation kinds remain separate. Each
requires the actual same-owner live review, current management epoch/fingerprint,
one finite operation, zero model/download/cost reservation, at most 64 KiB input
and 16 KiB output. The owner syncs intent before publication. The normalizer consumes
the exact permit under the final Core transaction; settlement follows Identity
finalization. Writer/lock/Resources cleanup remains checked. Uncertain outcomes
are not replayed. Consumed-review callback failures are downgraded to unknown by
the Review owner rather than reported as proof of no mutation.

The host refuses future-admitted or expired non-session targets before review;
the Core rechecks expiry in its locked normalization callback. Pin, ordinary and duration preserve the
public value and original admission clocks while advancing revision/root and
authenticating a typed choice. Session-only uses the signed suppression/deletion
path. Relative deadline rules are displayed before actual native confirmation;
the actual time and computed deadline are retained in the signed result.

## Executed evidence

The isolated runtime was `/tmp/ipse-management-retention-cli-20261028-46784`.
It copies the prior qualified production-profile CLI graph, then overlays the
four typed-retention modules, current ManagedReference, and five root CLI/Consent
modules. The helper remains
`6407e40e96498029ff7e13d96215a263812732aad1979b4c3e5f4b867b5a4d56`.
Every fixture home, workspace and protected directory was on the qualified actual
tmpfs. The graph does not include later document-backend/helper changes and is
not final whole-source/package evidence.

| Run | Actual result |
| --- | --- |
| [46784](retention-cli/logs/control-46784.log) |30 passed,4.2s: management mode/option refusals plus existing Consent/Review controls |
| [46785](retention-cli/logs/native-46785.log) |0/1 passed,8excluded: original fixture looked up Session admission on its pre-Session config; failure followed successful disable and preceded retention review/publication |
| [46786](retention-cli/logs/native-46786.log) |1 passed,8excluded,12.7s: actual native enable, reviewed capture, disable, pin→automatic→duration7days→session-only suppression; authenticated effective-policy readbacks, unchanged public value/original admission/original Session, settled private management journals, inert operation inspection and no model call |
| [46787](retention-cli/logs/source-match-46787.log) |Current five root modules compiled without source diagnostics and their executable BEAM digests matched the tested runtime exactly; the compiler API emitted a deprecation warning, retained in the log; no suite rerun |

The successful fixture reads the original admitted recipe from the actual Session
state captured before closing it. It does not invent admission on the initial
runtime configuration. The first failure is retained and is not counted as a
retention safety failure or pass. Native terminal interactions were serialized
against the other agents' PTY fixtures.

The source/log manifest binds the final root cohort, policy Core dependencies,
fixture and runtime inventory. Runtime files are inventoried, not archived as
build artifacts. All note text, sources and homes were synthetic. No live model,
paid service, full aggregate, installed package, large turnover run or release
was exercised here. The independent read-only review and any later repairs retain
their own scope; current implementation status stays in the plan.

Independent review verified current epoch/recipe/mode/permit/accounting and
cleanup handling. It identified an untested boundary: the old or new deadline can
elapse during staged IO after normalization but before the final root switch.
This cohort has no native deadline fence at that switch. The later
[native fence and delayed-publication controls](../2026-10-28-retention-publication-deadline/index.md)
qualify that separate component boundary. The earlier successful CLI journey
above does not supply new-helper CLI or whole-source qualification.

## Added CLI integration with the final-switch helper

After that fence was frozen, root copied its runtime into a separate
`_build/retention-cli-final-switch-20261028` graph, copied its private resources,
fixed the new graph's own `lib/ipse/priv` symlink, and overlaid only the five root
CLI/Consent modules. Runner and its private helper retain the exact new
`113df584e83b7749a11a72509092cb9c2b32d6fdc3fcf91b0181335f5f8c2550` binding.
The earlier graphs and all23 initial artifacts remain unchanged. The extended
manifest now binds38artifacts and the new730-path runtime inventory.

The [first graph setup](retention-cli/logs/final-switch-build-first-46790.log)
compiled all five modules, then stopped because the verification script expected
the legacy warning-list tuple instead of the requested diagnostics map. No test
or native operation started. The corrected
[setup](retention-cli/logs/final-switch-build-fixed-46790.log) accepted only empty
compile/runtime warning lists and verified the exact helper hash. Its final
[script](retention-cli/final-switch-build.exs) is retained.

[Native46790](retention-cli/logs/final-switch-native-46790.log) passed **1 test,
8excluded,12.5seconds**, seed49022. This repeats the actual standalone lifecycle
journey because finite retention now uses the new native protocol: enable,
reviewed capture, disable, pin→automatic→duration7days→session suppression,
authenticated policy/value/original-clock checks, measured settlement and inert
inspection. Actual runtime homes are on the admitted `/tmp` tmpfs; compilation
artifacts stay under `_build`. PTY use was serialized with other agents.

This closes new-helper standalone CLI integration for that matched host cohort.
It does not include the later direct-worker-result release section or qualify
the final current artifact, whole source, installed package, quality or turnover.
The [new provenance](retention-cli/final-switch-provenance.json) binds the exact
frozen base manifest and additions.
