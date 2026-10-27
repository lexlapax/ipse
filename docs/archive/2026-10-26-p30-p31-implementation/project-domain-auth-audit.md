Historical-only independent component audit, finalized **2026-10-27**. The literal
report below is preserved from separate owner-only evidence. Original report
SHA256: `b1c1302ca1ac6b29ef181c9338ee3aa714368011227c9410157862108025b391`.
The [component receipt](project-domain-auth-component.md) records author checks;
the [current plan](../../plan.md) owns integration and milestone acceptance.

The audit read the author receipt with SHA256 `f1d4336d92940f77b1c1583be515c02ee729d34244d90586484277f737f49449`.
Before committing the component in `d13857f3ec7856a44a58462a92fc6ed6dd3fb19f`,
its author corrected compilation-count terminology: 129 source files, and two
compatibility source files emitting five modules. The final author receipt SHA256
is `1cd9cfee14ff9991dabeb55811c8b7d6160a14a135545db2fe9c0b5dc5f56736`.
Implementation and tested runtime hashes did not change. The correction does not
replace the independent report's original reviewed-receipt hash.

# Independent ProjectIdentity / DomainAuth audit

2026-10-27. Incremental component audit, with no milestone acceptance or integration approval implied.

## Finding and independence

No actionable defect was found in final Identity source `66ebd609d78da960646a1894cff25e505ed3ea3acf0a63e8f40669369854da15` and DomainAuth source `50dbb61771a95995a9869f7fbbb2861c42cd0318ceaecc49cd92e781c225ac20` under the claimed trusted-Core/cooperative-storage boundary. This auditor did not author either implementation or its owned tests. The author graph was frozen before independent probes; no owner repair occurred during this audit. All independent test assertions were authored separately and no production changes were made.

The author graph is `/tmp/ipse-domain-auth-20261027-06`; the independent working graph is `/tmp/ipse-independent-domain-auth-20261027`. Both were checked against all 457 source rows and 612 runtime rows before and after execution. The manifests and every listed byte remain unchanged. Source manifest SHA256 is `3b9140992b4bcd79182a3b252764e50dc1bd667603f46b8e55541ea9165fd108`; runtime manifest SHA256 is `638ddd5cb0f2afa2cb6217f20b9709dd8fa8bf536a9df58e78be888a5952050b`.

The actual public-API BEAMs are Identity `cf7eaaae2d4f0c15afeb23bbb45f3b0593f3b1ec014a664166bc55e7e1daf019` and DomainAuth `81dbd8f394ef49639908277bea059ded7cae2e01608fab736a8d103e55a68b79`. Executed private helper is `d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b`, pinned by the copied runtime and executed from the private project cwd. No shared helper, repository source/index, author build, or production store was changed. No model, network service, credential, private transcript or qualification dataset was used.

## Scope and static review

Read actual AGENTS, ProjectIdentity public APIs/locking/publication/read validation, the complete DomainAuth module and owned 24 tests, the source-derived native fixture loader, and the author's full archived report. Audited private index-v2 compatibility and closed schemas, unchanged public binding digest, master/catalog limits and confidentiality, current authorizer gate, exact prepared/active/reconciliation state transitions, HMAC byte and contextual binding, verifier/signing separation, exact-owner/nonce/upstream/deadline/counter leases, and native outer-result withholding.

Static review agrees that invalid inputs refuse before crypto counters, valid-size incorrect tags consume verification, the 64-byte canonical digest prefix makes arbitrary raw bodies unambiguous, and call/body limits imply a stricter bound than the one-MiB aggregate. There is no invented aggregate-exhaustion claim.

## Executed evidence

- Unchanged owned DomainAuth suite: **24/24**, seed 20261110, direct Elixir, 13.5 seconds. This first direct rerun used normal `/tmp`; it had no observed fixture collision. The later combined and fresh runs use separate explicitly created private TMPDIRs.
- Independently authored real public-API/native controls: **14/14**, seed 20261111, 7.8 seconds. These invoke actual `Ipse.Extension.ProjectIdentity`, `DomainAuth` and `Transaction` BEAMs, without source-derived substitutions.
- Combined unchanged author suites: **88/88**, seed 20261112/max_cases 2, 33.1 seconds. Separate TMPDIR; includes 24 DomainAuth, 21 Identity, 20 Transaction, 12 optional-read, 9 framing and 2 protected-helper tests. Independent AST counting confirmed every count and the fresh 14.
- Exact after-verification: **1,069/1,069** source/runtime manifest rows still match in both original and independent graphs, including source, executed BEAMs and helper.

Fresh controls independently establish:

1. Canonical map order does not alter tags; every changed valid context field (kind/revision/operation/key) and every changed raw body byte/length fails verification. Version float, unsafe revision, non-ASCII reserved key and extra context field refuse.
2. Exact 6,144-byte body boundary, 16 successful seals then refusal, and 128 verifications then refusal. Malformed inputs do not consume attempts, while correct-sized wrong tags do. Sixteen maximum bodies plus 128 maximum-body verifications remain within their actual aggregate input allocation.
3. A captured capability is redacted and unusable from a different process, after callback completion, or after copying visible fields into a later lease. Existing verifier cannot seal.
4. Actual independently admitted projects using the same namespace, operation, context and body get distinct tags; each rejects the other's tag. Public binding stays stable.
5. Actual native publication admits eight namespaces; ninth returns capacity refusal with byte-identical index. Old valid tag remains verifiable.
6. An extra-key first witness leaves prepared state; automatic retry and initialize:false are blocked. Wrong key/fence reconciliation and denied current authorization are write-free; exact trusted reconciliation activates and advances revision once.
7. Version downgrade with private keys, invalid master encoding, active entry with missing root and extra top-level key fail closed without repair or callback. Restoring the exact valid synthetic fixture permits ordinary existing inspection again.
8. Killing the actual retained native controller after a positive verification withholds the positive result; private bytes stay unchanged and a later verifier reacquires its native lock.
9. Replacing the retained Identity directory during a callback withholds success. Restoring the synthetic original directory allows normal existing inspection.
10. A verifier callback crossing the five-second lease returns unknown and cannot verify after expiry; private bytes remain unchanged.
11. An already active publication still requires exact `:ok` from the current authorizer; non-exact success, denial and headless refusal enter no crypto callback and write nothing.
12. Actual scope cancellation after a positive verification kills the native owner and withholds the final fact.
13. A separate Elixir VM cannot initialize another namespace while the first VM retains Identity's native lock. After release, a separate VM verifies the persistent tag but cannot seal; no read upgrades or index writes occur.
14. Killing the original upstream owner invalidates a paused signer and retained native owner. The prepared namespace remains unreplayable.

The unchanged combined suite additionally reruns the author's actual native rename-before-ACK fault controls for prepared and active writes. Those two tests use source-derived isolated Transaction/Identity fixture modules solely to select their private Rust fault helper; this is distinct from the fresh actual public-API controls. The ephemeral fault helper binaries are cleaned by the owned test lifecycle; source/recipe is retained, without a claim that those transient executable bytes were archived. Actual public API helper bytes are retained.

## Retained verifier failures and corrections

`independent-owned-baseline.log` records sandboxed Mix TCP filesystem-lock refusal before tests. No TLS, tests or lock semantics were weakened; direct Elixir loaded the exact private BEAM graph instead. `run-owned.exs` preserves that direct execution command logic.

`fresh-public-api-first.exs`/`.log` preserve a startup mistake: setting TMPDIR before creating that directory made `System.tmp_dir!` fall back to `/tmp`, whose chmod refused. No test/API probe ran. The corrected startup creates/chmods its literal private directory first.

`fresh-public-api-second.exs`/`.log` preserve **11/12**, with the sole failure `unknown registry: Ipse.Registry`: the startup correction accidentally omitted `Application.ensure_all_started(:ipse)`. The failed scope-control worker could not initialize Resources; this was a harness setup failure, not production scope behavior. Restoring application startup made that unchanged scope test pass. Two additional independent controls were then added for separate-VM persistence/contention and upstream death, giving the final 14/14. Production source/runtime and existing assertions were unchanged across these attempts. No failed control was suppressed or counted as a pass.

## Limits

This component accepts a trusted host callback root witness, not actual Collection provenance. No actual Collection/root-proof/import adoption/current managed reader/SourceIndex/SDK/UI integration is implemented or established by this audit. A future adapter must bind actual absence/materialization, current policy, authentic inherited pages and import/floor adoption. A MAC attests a prior trusted host invocation, not current eligibility, truth, permission or anti-rollback. Current-policy authorizer is checked before callback; this audit does not assert a grant remains held or current throughout arbitrary callback IO.

Native loss/cleanup and callback-output withholding are verified within the cooperative boundary. Arbitrary same-UID file rewriting and hostile BEAM/raw-Core introspection are excluded; no crypto sandbox or memory-zeroization claim is made. Directory replacement is only a negative native-continuity control, not a broader hostile-filesystem security claim. No fresh full repository suite, native operator/PTY Rust suite, compatibility compile, packaging, production store, provider or quality qualification ran here. Author compatibility/strict checks are retained as author evidence, not relabeled independent.

## Exact commands and replay

From a new private graph copy, restore working build/lib/ipse/priv to its working project/priv and chmod the working `project/priv/ipse-runner` 0700. Evidence helpers are stored non-executable. Run only working copies; never execute or modify durable evidence in place.

```sh
elixir -pa '/absolute/private/working/build/lib/*/ebin' /absolute/private/working/run-combined.exs
elixir -pa '/absolute/private/working/build/lib/*/ebin' /absolute/private/working/fresh-public-api-final.exs
elixir /absolute/private/working/count-tests.exs
```

Drivers use their own `__DIR__`, change to their private project cwd, and allocate separate private TMPDIRs. The raw manifest verifier also compares the original author graph at its historical absolute path; adapt that path only in a disposable working copy or independently check each retained manifest row. No Mix metadata write or dependency-source compile is needed for replay. Omitted external source/dependency aliases are recorded by preservation provenance; executed dependency BEAMs and materialized private `priv` bytes are retained.

## Diagnostic paths and hashes

All paths below are relative to the independent working graph (and are preserved at durable evidence's `graph/`). The files.sha256 preservation manifest binds every retained byte, including this report and these scripts/logs.

| Artifact | SHA256 |
| --- | --- |
| `independent-freeze.log` | `3cc6cef802ff79439390dab67c0b5d9d87275728abc597e01863a3eb89795f11` |
| `independent-after.log` | `3cc6cef802ff79439390dab67c0b5d9d87275728abc597e01863a3eb89795f11` |
| `final-sources.sha256` | `3b9140992b4bcd79182a3b252764e50dc1bd667603f46b8e55541ea9165fd108` |
| `final-runtime.sha256` | `638ddd5cb0f2afa2cb6217f20b9709dd8fa8bf536a9df58e78be888a5952050b` |
| `run-owned.exs` | `896f965e3e0f8a25c950cfadf16c003c4f4d6eb893dccb15b4d8ea3a5db0f0d7` |
| `independent-owned-baseline.log` | `e10cbee50e01b07ab2cf163c0fede103c5bb7cfbb8a51f2ee434856106979efb` |
| `independent-owned-direct-first.log` | `ceb215ae0c969e0c961707d0376397e6fe0758f8999bdee86acbf1b5215a97bb` |
| `fresh-public-api-first.exs` | `0ec6081678e8dd30dd5481d6c8e5e507d62f64e3abf6f5e3b9253b044183e82f` |
| `fresh-public-api-first.log` | `d143520511aaa760c71e6d477243e9313243658936a39705b03cd66c52365726` |
| `fresh-public-api-second.exs` | `be5b487e423202c8cf364f801dc2c946c4bf55e8b7e8f2f3ec761595a8f797d3` |
| `fresh-public-api-second.log` | `90cab09dd6fc78060876265c569b65527d4af932961f9f6d6d3407ed36697cce` |
| `fresh-public-api-final.exs` | `e16b643c12289d577a13c9f7d1de7639085978a4c819a39b097487f07fffc244` |
| `fresh-public-api-final.log` | `6d48836a8b65a070117f0ebc175f4bc99f5bf8d1346da52c07724a247f148ad9` |
| `run-combined.exs` | `1a618f46903ec84eac1e29e5e19c850c289ea61f1cb1206664987d5f2a3a3271` |
| `independent-combined.log` | `c91ce2d5104a20be99f1eea46e4ff9a97591dfe955dcb6a64f78dcab60b31d30` |
| `count-tests.exs` | `e93700ddad24e6196dbcdd84aec35eddaec75d656bf24c2960f315e932f387ea` |
| `test-counts.log` | `30f5a71993da3770f86cef9e6e48118d10b84ff9d3efe4712a49b73f112296af` |
| `author-final-report.md` | `f1d4336d92940f77b1c1583be515c02ee729d34244d90586484277f737f49449` |
| `verify-independent.exs` | `a8a6262072283c72ab870045664f5ae3f3aacda916f6780d24f5562af835b9ec` |
