# Expected target for reviewed forgetting — 2026-11-06

Historical author-run synthetic verification. The [plan](../../plan.md) owns
current status; [storage training](../../developer/knowledge-storage.md) explains
the implementation boundary.

An internal opt-in `forget/4` can constrain a reviewed forget to an expected
project, namespace, root, key, revision, value digest, original operation ID and
complete Consent-ledger digest. It checks the target and ledger while the
existing owners are held, then checks the ledger again in the publication
transaction. These values narrow the requested effect; they are not permission,
source authority or a substitute for the native review. The ordinary public
forget path remains unchanged.

An independent static review found no additional concrete production defect in
this bounded change. A fresh integrated synthetic native journey with the fence
enabled passed one selected case, with 12 excluded (seed 342424). It covered
root, control and record mismatch refusals, a same-epoch control change after
review, refusal of that stale attempt and a separately reviewed successful
forget against Session-created records. The same ordinary journey with the flag
set to `0` passed one selected case, with 12 excluded (seed 385350). Four pure
target controls passed (seed 524974); 14 integrated Consent read/native tests
passed (seed 228640). The shared input lock, test listener and scoped processes
were clear after these runs.

Earlier private attempts are distinct: one lacked Hex and started no test; a
later setup reported `extension_bundle_unavailable` and warned an effect might
have occurred. That fixture's old teardown deleted its synthetic scenario root;
its log remains retained. The revised opt-in fixture retains a failed scenario
root and terminal output, but that retention has not been deliberately
fault-tested. No attempt was made to replay the uncertain setup.

This evidence covers only the opt-in standalone forget path and its selected
interposition. It does not establish active-effect owner-loss recovery, target
fences for expiry, correction or supersession, actual annual throughput or a
complete P31 journey. Prior v1 aliases cannot supply this expectation by
themselves. The existing 2,000-note notebook was not accessed.
