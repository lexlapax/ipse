# Forget-only Core fence restoration — 2026-10-29

Scoped implementation following the [independently reviewed effect direction](reviewed-forget-effect-restoration-independent-review.md)
and [accepted genuine-input prerequisite](management-review-input-independent-review.md).
The [plan](../../plan.md) retains full acceptance. This is the Core change for
the private journaled caller; it does not open a public management route.

`Collection.managed_mutation/8` permits `native_literal_forget` through the
existing normalized-request binding and ordinary atomic CAS. Its refusal list
still includes `native_literal_retention` and `native_literal_supersession`.
No strict-deadline API, quota, provider, normalizer, public CLI or native helper
changed in this slice. Trusted `NormalizerV3.forget/3` still requires exact signed
target/root/facts validation and consumes the same-owner live Review permit.
This is one admitted bounded reducing attempt, not a physical-completion deadline.
A late or unconfirmed completion must remain unknown and cannot be replayed.

The [independent Core review](reviewed-forget-core-independent-review.md) accepts
this narrow change and exact graph deltas. The [read-only verifier](reviewed-forget-core/verify.exs)
and [result](reviewed-forget-core/verify.log) check all pinned rows and runtime
entries. The [private effect candidate](management-forget-effect.md) supplies
separate actual caller tests and awaits its own review; this Core disposition
does not substitute for them.

## Evidence and retained failure

The [manifest](reviewed-forget-core/manifest.json), SHA-256
`47ec7ccfc5cd45581b5d21679eeed4f0533afe536d992072070af770ae477544`,
pins six source snapshots, eight launch/log files, two freeze helpers and three complete runtime
inventories. Each inventory contains 698 regular files and one explicitly
recorded telemetry directory symlink; the freeze does not traverse that link.
Compiled artifacts remain in the named `_build` graphs. These are exact isolated
graphs, not an all-current-source build.

- `47145` copies the accepted private input graph and compiles only Collection
  with zero compile/runtime diagnostics.
- `47146` passes ten of twelve selected tests: the new native storage refusal
  control for retention/supersession, seven ordinary managed-CAS/read-lifetime/
  owner-loss controls, strict deadline refusal with ordinary storage compatibility,
  and direct retention-policy refusal. Both fenced normalizations leave generation,
  floor, root publication and their operation IDs unchanged. The trusted callback
  is a synthetic storage-fence fixture, not proof of native input or Review.
- The other two cases fail their CLI text assertions because this inherited
  graph contains an older `CLI.Knowledge` executable. Current source already
  handles both typed fence errors explicitly. The actual refused outcomes did
  not admit review or mutation. Their original failed log remains pinned.
- `47147` forks that graph and overlays only current `CLI.Knowledge` and
  `CLI.Errors`, again with empty diagnostics. `47148` reruns only the two failed
  CLI cases: two pass, two unrelated cases excluded. Test expectations and product
  source were not weakened to accommodate the old executable.

The first freeze script attempted to read the inherited directory symlink as a
regular file and failed before producing a manifest. Its original script is
retained in the evidence directory; the corrected
freeze records symlink type/target without reading or recursively following it.
This tooling correction did not rerun runtime tests.

Actual genuine-input forgetting, same-journal intent/result ordering, Consent
settlement, changed-target/epoch refusal, expiry, loss and no-replay qualification
belong to the separately composed management effect cohort. The input-only cohort
does not prove those effects. Public forget/session-retention routes and unrelated
protected output gates remain closed. No model call, aggregate suite, installed
package qualification, commit or milestone acceptance is claimed here.
