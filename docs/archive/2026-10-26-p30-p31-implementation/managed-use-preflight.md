# Managed-use expiry and bounded historical preflight

Dated **2026-10-28**, branch `codex/p30-p31`. This records a focused repair and
verification section in the dirty implementation tree. The [plan](../../plan.md)
owns milestone acceptance; the [collection SDK manual](../../developer/collection-sdk.md)
owns the host contract. This is neither final P30/P31 acceptance nor native
production-profile qualification.

## Repairs and independent review

The independent reviewer identified two gaps: protected policy expiry was checked
before potentially slow final observations, and historical preflight could scan
the same original journal separately for every dependency with a fresh byte budget.

`ManagedUse.with_dependencies` now checks time after the final protected
observation and immediately before entering the use callback. Its deadline is
the earlier of authenticated policy expiry and every refreshed literal's finite
validity deadline. Current source leases, Identity and Consent remain held at
that boundary. Opaque transport-continuation return values survive the existing
Consent pair wrapper without being mistaken for an invalid read response.

Historical `verdicts` now observes each distinct record/recipe once in each
protected phase, with at most 128 distinct records and 128 unique source proofs.
`StoredSources.snapshot` groups proofs by original Session, performs one full
inactive-journal scan per group, and shares one aggregate configured journal byte
budget across those groups. Invalid individual proofs yield individual unavailable
statuses. Authority, origin, native lock or whole-journal failure rejects the
affected group. A second protected observation checks unchanged selected records,
the current policy deadline and each literal deadline before returning verdicts.
Verdicts remain historical and cannot authorize an effect.

Strict `StoredSources.with_verified` forces strict resolution even when a caller
supplies a partial-resolution context. Actual use still acquires source leases
and revalidates the selected live dependencies; it never uses a historical status
cache as authority. Repeated identical effective source references are deduplicated
before source-page validation. The scan-byte bound covers full original-journal
scans; it is not an assertion that all auxiliary source-page IO has that same
byte count.

A second independent read-only review found no new material defect within these
repairs. It requested actual mixed-verdict integration and a wired validity
deadline-crossing control. The mixed control was added below. Wired transport
deadline, TLS, cancellation and delivery controls remain in the transport section;
the helper expiry test alone does not prove those paths.

## Focused execution

All commands ran in `_build/operator-assertion-sol`, `MIX_ENV=test`, with that
graph's retained private available-host native helper. Production admission is
unchanged. Tests used synthetic sources/homes and no live inference or credentials.

```sh
MIX_ENV=test mix test test/ipse/session/managed_use_test.exs \
  test/ipse/session/stored_sources_test.exs --warnings-as-errors
MIX_ENV=test mix test test/ipse/session/operator_assertion_integration_test.exs \
  --only assertion_scenario:save --warnings-as-errors
```

- [Verifier run 46762](managed-use-preflight/verifier-46762.log): **5 passed**, seed
  654685, 0.2 seconds. Checks expiry reached during final observation, opaque
  callback results, failed observation refusal, retained native lock/owner loss,
  precise same-journal good/bad proof statuses, aggregate cross-journal byte limits
  and forced strict-use refusal. SHA-256:
  `18f25c0fcec7338eca65ece213e59123df3cdbbd1936f8f194a2d748430b2008`.
- [Native run 46763](managed-use-preflight/native-46763.log): **1 passed, 4 excluded**,
  seed 765526, 11.3 seconds. Real CLI review/publication, fresh consuming Session,
  unchanged literal use under retained original-source ownership, root selection
  rejection after change, and unchanged literal refresh. SHA-256:
  `f6d68cd078c82fb47f3b889b261d40fb3cb9ed71bca8317f3ff5550f78f77981`.
- [Added batch control 46764](managed-use-preflight/batch-46764.log): **1 passed,
  4 excluded**, seed 23790, 11.4 seconds. The same native fixture now checks a
  canonical batch with two observations of an unchanged literal eligible and a
  stale root selection unavailable, under a scan budget fitting one original
  journal. SHA-256:
  `bbb4a8fde055e75ad628903c6efe67e19c934927219c6dc8e1c21220cd2825f4`.

Source hashes after the added control:

| File | SHA-256 |
| --- | --- |
| `lib/ipse/session/managed_use.ex` | `8d8c834e0a0173d22b77bf8174000a010e30206923b2811a3705c61aa5c6d4f3` |
| `lib/ipse/session/stored_sources.ex` | `23882b76fb6f85c954c51b6533546735ba8fea7be6889bfb6d7230157c8e4506` |
| `lib/ipse/session/source_window.ex` | `0d4eb368fe1444546d259456c60061d6ede5483d1d93583b9ae97bdd29ff7cf5` |
| `test/ipse/session/managed_use_test.exs` | `4de7f0d97317763ce68462a464f7838384d40d49b1c8882dfa62840013c6ec9f` |
| `test/ipse/session/stored_sources_test.exs` | `8a149f58821d732b889d095e8433e3615bf75d802b4b3ae85c537b16fedb2e3a` |
| `test/support/operator_assertion.exs` | `79817674db1ca07b465ce05bae5df8629864bb5ff9ca18c0640501216b8f98ed` |

No aggregate suite, installed workflow, real document-quality evaluation,
production profile admission or release ran for this section. Whole-manual
integration, final source/package checks and final adversarial acceptance remain
open. The first actual HTTP transport check is separate evidence and is not
promoted to universal send/delivery qualification by these results.
