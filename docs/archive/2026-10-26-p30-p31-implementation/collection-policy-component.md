# Declarative collection publication constraints

Dated **2026-10-26**; internal component evidence for the
[implementation record](index.md). This is not integrated capture or milestone
acceptance. The [current plan](../../plan.md) owns those gates.

`CollectionPolicy` reuses the maintained schema validator through `Ipse.JSON`.
A reviewed mapping supplies a key prefix, recursively closed value schema,
evidence field path, allowed origins and explicit deletion flag. Every mutation
must satisfy the mapping. Each nonnil value retains a nonempty exact subset of
the already authenticated stable source receipts; duplicate or substituted
evidence refuses. Every proof in the batch must have an allowed origin. Empty
proof sets cannot authorize deletion. The function performs no IO, source
authentication or authority admission; the host adapter still owns those checks.

All **seven focused tests** pass in **0.1 seconds**, seed **394922**, against the
complete frozen v3 component runtime. Direct strict compilation passes without
warnings. Logs are `/tmp/ipse-collection-policy-complete-runtime.log` and
`/tmp/ipse-collection-policy-strict.log`. The initial harness passed the same
seven tests but compiled Collection without its sibling modules and emitted
undefined-module warnings; that harness is not the strict receipt. It remains
at `/tmp/ipse-collection-policy-first.log`.

These synthetic receipts are supplied directly as trusted function inputs. The
tests do not establish that worker JSON can authenticate itself, that a quoted
claim is true, that source exclusions are enforced, or that a live publication
has passed consent and suppression checks. Those belong to the integrated host
and independent adversarial qualification.
